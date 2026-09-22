#!/bin/bash
#
# preflight.sh — Ozyune.app 发布前检查（7 项）
#
# 用法:
#   ./scripts/preflight.sh [路径/Ozyune.app]
#
# 默认检查仓库根目录下的 Ozyune.app。全部通过则退出码为 0，
# 任意一项失败退出码为 1，并在末尾汇总失败项。
#
# 检查项:
#   1. 签名完整性 (codesign --verify --deep --strict)
#   2. 签名身份 (Developer ID Application / Team / 时间戳)
#   3. Gatekeeper 评估 (spctl: accepted + Notarized Developer ID)
#   4. 架构 (通用二进制: x86_64 + arm64)
#   5. Info.plist 关键值与 project.pbxproj 构建设置一致
#   6. 公证票据已装订 (xcrun stapler validate)
#   7. zip 回环 (ditto 打包再解压后，签名与 Gatekeeper 评估仍有效)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$REPO_ROOT/Ozyune.app}"
PBXPROJ="$REPO_ROOT/Ozyune.xcodeproj/project.pbxproj"

PASS=0
FAIL=0
FAILED_ITEMS=()

ok()  { printf '  ✅ %s\n' "$1"; }
bad() { printf '  ❌ %s\n' "$1"; }

report() { # report <check-number> <check-name> <0=pass|1=fail>
    if [ "$3" -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        FAILED_ITEMS+=("$1. $2")
    fi
}

# 从 pbxproj 提取构建设置的期望值
project_setting() { # project_setting <key>
    grep -m1 "$1 = " "$PBXPROJ" | sed "s/.*$1 = //; s/;.*//; s/[\"']//g"
}

# 从 app 的 Info.plist 读取值
app_plist_value() { # app_plist_value <key>
    /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null
}

echo "──────────────────────────────────────────────"
echo " Ozyune 发布前检查"
echo " 目标: $APP"
echo "──────────────────────────────────────────────"

if [ ! -d "$APP" ]; then
    echo "❌ 找不到 app bundle: $APP"
    exit 1
fi

# ── 1. 签名完整性 ───────────────────────────────
echo "1. 签名完整性"
rc=0
codesign --verify --deep --strict --verbose=2 "$APP" >/dev/null 2>&1 || rc=1
[ $rc -eq 0 ] && ok "codesign --verify --deep --strict 通过" || bad "签名验证失败"
report 1 "签名完整性" $rc

# ── 2. 签名身份 ─────────────────────────────────
echo "2. 签名身份"
identity="$(codesign -dv --verbose=2 "$APP" 2>&1)"
rc=0
echo "$identity" | grep -q 'Authority=Developer ID Application' || rc=1
echo "$identity" | grep -q 'TeamIdentifier=' || rc=1
echo "$identity" | grep -q 'Timestamp=' || rc=1
if [ $rc -eq 0 ]; then
    ok "$(echo "$identity" | grep -m1 'Authority=Developer ID Application' | sed 's/Authority=//')"
    ok "Team: $(echo "$identity" | grep -m1 'TeamIdentifier=' | sed 's/TeamIdentifier=//')，含签名时间戳"
else
    bad "不是有效的 Developer ID Application 签名（或缺少 Team/时间戳）"
fi
report 2 "签名身份" $rc

# ── 3. Gatekeeper 评估 ──────────────────────────
echo "3. Gatekeeper 评估"
assessment="$(spctl -a -vv "$APP" 2>&1)"
rc=0
echo "$assessment" | grep -q 'accepted' || rc=1
echo "$assessment" | grep -q 'source=Notarized Developer ID' || rc=1
if [ $rc -eq 0 ]; then
    ok "accepted — Notarized Developer ID"
else
    bad "Gatekeeper 未接受："
    echo "$assessment" | sed 's/^/     /'
fi
report 3 "Gatekeeper 评估" $rc

# ── 4. 架构 ─────────────────────────────────────
echo "4. 架构"
binary="$APP/Contents/MacOS/$(app_plist_value CFBundleExecutable)"
arches="$(lipo -info "$binary" 2>/dev/null)"
rc=0
echo "$arches" | grep -q 'x86_64' || rc=1
echo "$arches" | grep -q 'arm64' || rc=1
if [ $rc -eq 0 ]; then
    ok "通用二进制 (x86_64 + arm64)"
else
    bad "缺少架构：$arches"
fi
report 4 "架构" $rc

# ── 5. Info.plist 与构建设置一致 ────────────────
echo "5. Info.plist 关键值"
rc=0
for pair in "CFBundleShortVersionString:MARKETING_VERSION" \
            "CFBundleVersion:CURRENT_PROJECT_VERSION" \
            "CFBundleIdentifier:PRODUCT_BUNDLE_IDENTIFIER" \
            "LSMinimumSystemVersion:MACOSX_DEPLOYMENT_TARGET"; do
    plist_key="${pair%%:*}"
    setting_key="${pair##*:}"
    app_value="$(app_plist_value "$plist_key")"
    expected="$(project_setting "$setting_key")"
    if [ "$app_value" = "$expected" ]; then
        ok "$plist_key = $app_value"
    else
        bad "$plist_key: app 为 '$app_value'，$setting_key 为 '$expected'"
        rc=1
    fi
done
report 5 "Info.plist 关键值" $rc

# ── 6. 公证票据装订 ─────────────────────────────
echo "6. 公证票据 (stapler)"
rc=0
staple_out="$(xcrun stapler validate "$APP" 2>&1)" || rc=1
echo "$staple_out" | grep -q 'worked' || rc=1
[ $rc -eq 0 ] && ok "票据已 stapled，离线也能通过 Gatekeeper" || bad "未装订公证票据"
report 6 "公证票据装订" $rc

# ── 7. zip 回环 ─────────────────────────────────
echo "7. zip 回环"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
app_name="$(basename "$APP")"
rc=0
ditto -c -k --keepParent "$APP" "$TMP/roundtrip.zip" 2>/dev/null || rc=1
mkdir -p "$TMP/out"
ditto -x -k "$TMP/roundtrip.zip" "$TMP/out" 2>/dev/null || rc=1
unzipped="$TMP/out/$app_name"
codesign --verify --deep --strict "$unzipped" >/dev/null 2>&1 || rc=1
roundtrip_spctl="$(spctl -a -vv "$unzipped" 2>&1)"
echo "$roundtrip_spctl" | grep -q 'accepted' || rc=1
echo "$roundtrip_spctl" | grep -q 'source=Notarized Developer ID' || rc=1
[ $rc -eq 0 ] && ok "打包 → 解压后签名与公证状态完好" || bad "zip 回环后签名/Gatekeeper 失效"
report 7 "zip 回环" $rc

# ── 汇总 ────────────────────────────────────────
echo "──────────────────────────────────────────────"
if [ $FAIL -eq 0 ]; then
    echo " 🎉 全部通过 ($PASS/7)，可以发布"
    exit 0
else
    echo " ⚠️  通过 $PASS/7，失败 $FAIL 项："
    for item in "${FAILED_ITEMS[@]}"; do
        echo "   - $item"
    done
    exit 1
fi
