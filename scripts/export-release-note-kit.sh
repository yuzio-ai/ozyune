#!/bin/bash
#
# export-release-note-kit.sh — package the release note convention for another
# repository.
#
# Usage:
#   bash scripts/export-release-note-kit.sh                    # tarball: ./release-note-kit.tar.gz
#   bash scripts/export-release-note-kit.sh --tarball [<file>] # tarball at <file>
#   bash scripts/export-release-note-kit.sh --copy <repo-root> # copy into a target repository
#   ... --copy <repo-root> --force                             # overwrite existing kit files
#
# The kit is five files (see docs/release-notes-convention.md):
#
#   scripts/release-notes-lib.sh
#   scripts/check-release-notes.sh
#   scripts/render-release-notes.sh
#   .github/release-notes.conf
#   .github/RELEASE_NOTES_TEMPLATE.md
#
# The three scripts are copied byte for byte. The conf ships with empty
# REPO_SLUG / PRODUCT_NAME / ASSET_NAME values so a fresh repository starts from
# the documented fallbacks (slug from `origin`, product and asset from the
# repository name) instead of this repository's identity. Edit the conf and the
# template prose after adopting — nothing else.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT=(
    scripts/release-notes-lib.sh
    scripts/check-release-notes.sh
    scripts/render-release-notes.sh
    .github/release-notes.conf
    .github/RELEASE_NOTES_TEMPLATE.md
)

MODE="tarball"
TARGET=""
FORCE=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --tarball)
            MODE="tarball"
            if [ "$#" -ge 2 ] && [ "${2#-}" = "$2" ]; then
                TARGET="$2"
                shift
            fi
            ;;
        --copy)
            [ "$#" -ge 2 ] || { echo "❌ --copy needs a target repository root" >&2; exit 1; }
            MODE="copy"
            TARGET="$2"
            shift
            ;;
        --force) FORCE=1 ;;
        -h|--help)
            sed -n '3,24p' "$0"
            exit 0
            ;;
        *)
            echo "❌ unknown argument: $1" >&2
            exit 1
            ;;
    esac
    shift
done

if [ "$MODE" = "tarball" ] && [ -z "$TARGET" ]; then
    TARGET="release-note-kit.tar.gz"
fi

for file in "${KIT[@]}"; do
    [ -f "$REPO_ROOT/$file" ] || { echo "❌ kit file missing in this repository: $file" >&2; exit 1; }
done

# ── stage the kit, with a neutral conf ───────────────────────────────────
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/release-note-kit.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

for file in "${KIT[@]}"; do
    mkdir -p "$STAGE/$(dirname "$file")"
    cp "$REPO_ROOT/$file" "$STAGE/$file"
done

# Reset the identity values; comments and the LANGUAGES example stay.
sed -e 's|^REPO_SLUG=.*|REPO_SLUG=""|' \
    -e 's|^PRODUCT_NAME=.*|PRODUCT_NAME=""|' \
    -e 's|^ASSET_NAME=.*|ASSET_NAME=""|' \
    "$STAGE/.github/release-notes.conf" > "$STAGE/.github/release-notes.conf.new"
mv "$STAGE/.github/release-notes.conf.new" "$STAGE/.github/release-notes.conf"

# ── deliver ──────────────────────────────────────────────────────────────
if [ "$MODE" = "tarball" ]; then
    tar -czf "$TARGET" -C "$STAGE" "${KIT[@]}"
    echo "✅ 已打包: $TARGET"
    echo "   在目标仓库根目录解包: tar -xzf $TARGET"
else
    [ -d "$TARGET" ] || { echo "❌ not a directory: $TARGET" >&2; exit 1; }
    conflicts=""
    for file in "${KIT[@]}"; do
        if [ -e "$TARGET/$file" ] && [ "$FORCE" -eq 0 ]; then
            conflicts="$conflicts $file"
        fi
    done
    if [ -n "$conflicts" ]; then
        echo "❌ 目标仓库已存在以下 kit 文件（--force 覆盖）:" >&2
        for file in $conflicts; do echo "   - $file" >&2; done
        exit 1
    fi
    for file in "${KIT[@]}"; do
        mkdir -p "$TARGET/$(dirname "$file")"
        cp "$STAGE/$file" "$TARGET/$file"
    done
    echo "✅ 已复制 5 个 kit 文件到: $TARGET"
fi

echo "──────────────────────────────────────────────"
echo " 下一步（详见 docs/release-notes-convention.md）:"
echo "   1. 编辑 .github/release-notes.conf —— REPO_SLUG / PRODUCT_NAME / ASSET_NAME / LANGUAGES"
echo "   2. 按产品改写 .github/RELEASE_NOTES_TEMPLATE.md 的正文（结构不动）"
echo "   3. 接入 CI: bash scripts/render-release-notes.sh --self-test && bash scripts/check-release-notes.sh"
