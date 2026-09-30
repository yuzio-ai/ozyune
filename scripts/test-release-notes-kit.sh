#!/bin/bash
#
# test-release-notes-kit.sh — prove the release note kit is portable.
#
# Usage:
#   bash scripts/test-release-notes-kit.sh
#
# Adopts the kit into throwaway repositories under $TMPDIR and asserts:
#   1. the three kit scripts carry no repository specific values;
#   2. a single-language adoption works end to end (render → fill → check),
#      with a different product, slug and asset;
#   3. a two-language adoption works with custom headings and markers
#      (English + 日本語, marker **変更履歴**：);
#   4. regressions stay fixed: a conf without LANGUAGES fails loudly instead of
#      silently degrading, and the first-release render prints full guidance;
#   5. scripts/export-release-note-kit.sh delivers exactly the five kit files,
#      with the conf identity values reset to their fallbacks.
#
# Everything runs in mktemp directories; the repository is never touched.
# All assertions pass → exit 0; any failure → exit 1.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT=(
    scripts/release-notes-lib.sh
    scripts/check-release-notes.sh
    scripts/render-release-notes.sh
    .github/release-notes.conf
    .github/RELEASE_NOTES_TEMPLATE.md
)

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/release-note-kit-test.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

PASSED=0
FAILED=0

expect() { # expect <label> <haystack> <needle>
    if printf '%s' "$2" | grep -qF "$3"; then
        echo "PASS: $1"
        PASSED=$((PASSED + 1))
    else
        echo "FAIL: $1 — expected: $3"
        printf '%s\n' "$2"
        FAILED=$((FAILED + 1))
    fi
}

adopt() { # adopt <dir> — the five kit files, byte for byte
    local file
    for file in "${KIT[@]}"; do
        mkdir -p "$1/$(dirname "$file")"
        cp "$REPO_ROOT/$file" "$1/$file"
    done
}

echo "──────────────────────────────────────────────"
echo " release note kit 自测"
echo "──────────────────────────────────────────────"

# ── 1. no repository specific values in the kit scripts ──────────────────
PRODUCT_NAME="$(bash -c '. "$1/.github/release-notes.conf"; printf %s "${PRODUCT_NAME:-}"' _ "$REPO_ROOT")"
REPO_SLUG_VALUE="$(bash -c '. "$1/.github/release-notes.conf"; printf %s "${REPO_SLUG:-}"' _ "$REPO_ROOT")"
for literal in "$PRODUCT_NAME" "$REPO_SLUG_VALUE"; do
    [ -n "$literal" ] || continue
    hits=""
    for file in scripts/release-notes-lib.sh scripts/check-release-notes.sh scripts/render-release-notes.sh; do
        if grep -qF -- "$literal" "$REPO_ROOT/$file"; then
            hits="$hits $file"
        fi
    done
    if [ -n "$hits" ]; then
        echo "FAIL: kit scripts must not hardcode '$literal' — found in:$hits"
        FAILED=$((FAILED + 1))
    else
        echo "PASS: kit scripts carry no '$literal'"
        PASSED=$((PASSED + 1))
    fi
done

# ── 2. single-language adoption (English only, product "Acme") ───────────
A="$ROOT/acme"
adopt "$A"
cat > "$A/.github/release-notes.conf" <<'EOF'
REPO_SLUG="acme/widget"
PRODUCT_NAME="Acme"
NOTES_DIR="docs/releases"
ASSET_NAME="Widget.zip"
LANGUAGES=(
  'en|english|English|**Full changelog**: |New,Changed,Fixed,Requirements,Installation|3,4'
)
EOF
cat > "$A/.github/RELEASE_NOTES_TEMPLATE.md" <<'EOF'
<!--
Acme release notes — single-language template.
{{PRODUCT}}, {{VERSION}}, {{ASSET}} and {{CHANGELOG_URL}} are substituted by
scripts/render-release-notes.sh.
-->

{{PRODUCT}} {{VERSION}} {{ONE_LINE_SUMMARY}}.

### New

<!-- One bullet per addition. Delete the section if there is none. -->

### Changed

<!-- One bullet per change. Delete the section if there is none. -->

### Fixed

<!-- One bullet per fix. Delete the section if there are none. -->

### Requirements

- macOS 13 or later.

### Installation

1. Download `{{ASSET}}` from the assets below
2. Unzip and move `{{PRODUCT}}.app` to `/Applications`

**Full changelog**: {{CHANGELOG_URL}}
EOF

out="$(cd "$A" && bash scripts/render-release-notes.sh 0.1.0 2>&1)"
expect "A: render succeeds" "$out" "已生成: docs/releases/v0.1.0.md"
note="$A/docs/releases/v0.1.0.md"
expect "A: product substituted" "$(cat "$note")" "Acme 0.1.0 {{ONE_LINE_SUMMARY}}."
expect "A: asset substituted" "$(cat "$note")" "\`Widget.zip\`"
expect "A: first-release changelog" "$(cat "$note")" "https://github.com/acme/widget/commits/v0.1.0"

out="$(cd "$A" && bash scripts/check-release-notes.sh docs/releases/v0.1.0.md 2>&1)"
expect "A: unfilled skeleton is rejected" "$out" "unreplaced template placeholder"
expect "A: hint left is rejected" "$out" "authoring comment left in the note"

sed -e 's/{{ONE_LINE_SUMMARY}}/kicks off the series/' -e 's|<!--.*-->|- done.|' "$note" > "$note.filled"
mv "$note.filled" "$note"
out="$(cd "$A" && bash scripts/check-release-notes.sh 2>&1)"
expect "A: filled note passes" "$out" "🎉 1 份发布说明符合固定样式"

sed 's/Widget\.zip/Widget-0.1.0.zip/g' "$note" > "$note.bad"
out="$(cd "$A" && bash scripts/check-release-notes.sh "$note.bad" 2>&1)"
expect "A: versioned asset rejected" "$out" "the asset is called Widget.zip"
rm -f "$note.bad"

# ── 3. two-language adoption (English + 日本語, custom markers) ──────────
B="$ROOT/kotoba"
adopt "$B"
cat > "$B/.github/release-notes.conf" <<'EOF'
REPO_SLUG="kotoba/kotoba-app"
PRODUCT_NAME="Kotoba"
NOTES_DIR="docs/releases"
ASSET_NAME="Kotoba.zip"
LANGUAGES=(
  'en|english|English|**Full changelog**: |New,Fixed,Requirements,Installation|2,3'
  'ja|日本語|日本語|**変更履歴**：|新規,修正,必要環境,インストール|2,3'
)
EOF
cat > "$B/.github/RELEASE_NOTES_TEMPLATE.md" <<'EOF'
<a href="#english">English</a> | <a href="#日本語">日本語</a>

<a id="english"></a>
## English

{{PRODUCT}} {{VERSION}} {{ONE_LINE_SUMMARY}}.

### New

<!-- Delete the section if there is none. -->

### Fixed

<!-- Delete the section if there are none. -->

### Requirements

- macOS 13 or later.

### Installation

1. Download `{{ASSET}}` from the assets below

**Full changelog**: {{CHANGELOG_URL}}

<a id="日本語"></a>
## 日本語

{{PRODUCT}} {{VERSION}} {{ONE_LINE_SUMMARY}}.

### 新規

<!-- なければ削除。 -->

### 修正

<!-- なければ削除。 -->

### 必要環境

- macOS 13 以降。

### インストール

1. 下の Assets から `{{ASSET}}` をダウンロード

**変更履歴**：{{CHANGELOG_URL}}
EOF

out="$(cd "$B" && bash scripts/render-release-notes.sh 0.2.0 2>&1)"
expect "B: render succeeds" "$out" "已生成: docs/releases/v0.2.0.md"
note="$B/docs/releases/v0.2.0.md"
sed -e 's/{{ONE_LINE_SUMMARY}}/first cut/' -e 's|<!--.*-->|- done.|' "$note" > "$note.filled"
mv "$note.filled" "$note"
out="$(cd "$B" && bash scripts/check-release-notes.sh 2>&1)"
expect "B: filled note passes" "$out" "🎉 1 份发布说明符合固定样式"

sed 's/^\*\*変更履歴\*\*：/**Full changelog**: /' "$note" > "$note.bad"
out="$(cd "$B" && bash scripts/check-release-notes.sh "$note.bad" 2>&1)"
expect "B: missing ja marker rejected" "$out" "[ja] missing the closing changelog line"
rm -f "$note.bad"

out="$(cd "$B" && bash scripts/render-release-notes.sh --self-test 2>&1)"
expect "B: self-test passes" "$out" "🎉 1 份发布说明符合固定样式"

# ── 4. regressions ───────────────────────────────────────────────────────
R="$ROOT/regress"
adopt "$R"
cat > "$R/.github/release-notes.conf" <<'EOF'
REPO_SLUG="acme/widget"
PRODUCT_NAME="Acme"
NOTES_DIR="docs/releases"
ASSET_NAME="Widget.zip"
LANGUAGES=(
  'en|english|English|**Full changelog**: |New,Requirements,Installation|1,2'
)
EOF
cat > "$R/.github/RELEASE_NOTES_TEMPLATE.md" <<'EOF'
{{PRODUCT}} {{VERSION}} {{ONE_LINE_SUMMARY}}.

### New

- something.

### Requirements

- macOS 13 or later.

### Installation

1. Download `{{ASSET}}`

**Full changelog**: {{CHANGELOG_URL}}
EOF

# First release (no tags): render must succeed and print the whole guidance.
out="$(cd "$R" && bash scripts/render-release-notes.sh 0.1.2 2>&1)"
rc=$?
[ "$rc" -eq 0 ] && echo "PASS: R: first-release render exits 0" || { echo "FAIL: R: first-release render exits 0 — got $rc"; FAILED=$((FAILED + 1)); }
[ "$rc" -eq 0 ] && PASSED=$((PASSED + 1))
expect "R: first-release changelog printed" "$out" "变更范围: 首个版本（v0.1.2）"
expect "R: publish guidance printed" "$out" "gh release create v0.1.2 Widget.zip"

# A conf without LANGUAGES must fail loudly, never degrade silently.
sed '/^LANGUAGES=(/,/^)/d' "$R/.github/release-notes.conf" > "$R/conf.new"
mv "$R/conf.new" "$R/.github/release-notes.conf"
out="$(cd "$R" && bash scripts/render-release-notes.sh 0.9.9 --stdout 2>&1)"
rc=$?
[ "$rc" -ne 0 ] && echo "PASS: R: render without LANGUAGES fails" || { echo "FAIL: R: render without LANGUAGES fails — exit 0"; FAILED=$((FAILED + 1)); }
[ "$rc" -ne 0 ] && PASSED=$((PASSED + 1))
expect "R: render fails with friendly message" "$out" "❌ LANGUAGES is empty in .github/release-notes.conf"
out="$(cd "$R" && bash scripts/check-release-notes.sh docs/releases/v0.1.2.md 2>&1)"
rc=$?
[ "$rc" -ne 0 ] && echo "PASS: R: check without LANGUAGES fails" || { echo "FAIL: R: check without LANGUAGES fails — exit 0"; FAILED=$((FAILED + 1)); }
[ "$rc" -ne 0 ] && PASSED=$((PASSED + 1))
expect "R: check fails with friendly message" "$out" "❌ LANGUAGES is empty in .github/release-notes.conf"

# ── 5. export helper ─────────────────────────────────────────────────────
E="$ROOT/exported"
mkdir -p "$E"
out="$(bash "$REPO_ROOT/scripts/export-release-note-kit.sh" --copy "$E" 2>&1)"
expect "E: --copy reports success" "$out" "✅ 已复制 5 个 kit 文件到: $E"
files_ok=1
for file in "${KIT[@]}"; do
    [ -f "$E/$file" ] || { files_ok=0; echo "FAIL: E: missing $file"; FAILED=$((FAILED + 1)); }
done
[ "$files_ok" -eq 1 ] && { echo "PASS: E: all five kit files delivered"; PASSED=$((PASSED + 1)); }
same=1
for file in scripts/release-notes-lib.sh scripts/check-release-notes.sh scripts/render-release-notes.sh; do
    cmp -s "$REPO_ROOT/$file" "$E/$file" || { same=0; echo "FAIL: E: $file was modified in export"; FAILED=$((FAILED + 1)); }
done
[ "$same" -eq 1 ] && { echo "PASS: E: scripts exported byte for byte"; PASSED=$((PASSED + 1)); }
expect "E: conf slug reset" "$(grep '^REPO_SLUG=' "$E/.github/release-notes.conf")" 'REPO_SLUG=""'
expect "E: conf product reset" "$(grep '^PRODUCT_NAME=' "$E/.github/release-notes.conf")" 'PRODUCT_NAME=""'
expect "E: conf asset reset" "$(grep '^ASSET_NAME=' "$E/.github/release-notes.conf")" 'ASSET_NAME=""'

out="$(bash "$REPO_ROOT/scripts/export-release-note-kit.sh" --copy "$E" 2>&1)"
expect "E: --copy refuses to overwrite" "$out" "已存在以下 kit 文件"
out="$(bash "$REPO_ROOT/scripts/export-release-note-kit.sh" --copy "$E" --force 2>&1)"
expect "E: --force overwrites" "$out" "✅ 已复制 5 个 kit 文件到: $E"

T="$ROOT/kit.tar.gz"
out="$(bash "$REPO_ROOT/scripts/export-release-note-kit.sh" --tarball "$T" 2>&1)"
expect "E: --tarball reports success" "$out" "✅ 已打包: $T"
listing="$(tar -tzf "$T" | LC_ALL=C sort)"
sorted_kit="$(printf '%s\n' "${KIT[@]}" | LC_ALL=C sort)"
if [ "$listing" = "$sorted_kit" ]; then
    echo "PASS: E: tarball has exactly the five kit files"
    PASSED=$((PASSED + 1))
else
    echo "FAIL: E: tarball has exactly the five kit files — got:"
    printf '%s\n' "$listing"
    FAILED=$((FAILED + 1))
fi

echo "──────────────────────────────────────────────"
echo " $PASSED 项通过，$FAILED 项失败"
if [ "$FAILED" -eq 0 ]; then
    echo " 🎉 release note kit 可整包复用"
    exit 0
else
    echo " ⚠️  kit 自测未通过"
    exit 1
fi
