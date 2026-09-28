#!/bin/bash
#
# render-release-notes.sh — render the canonical release note skeleton.
#
# Reads .github/RELEASE_NOTES_TEMPLATE.md, fills in the version and the
# changelog range, and writes docs/releases/<tag>.md. The skeleton is the only
# place the pinned style lives, so this keeps every new note starting from the
# same structure — pair it with scripts/check-release-notes.sh before publishing.
#
# Usage:
#   bash scripts/render-release-notes.sh <version>          # writes docs/releases/v<version>.md
#   bash scripts/render-release-notes.sh <version> --stdout # prints the note instead
#   bash scripts/render-release-notes.sh --self-test        # template conformance only
#
# <version> is the marketing version from Ozyune.xcodeproj (MARKETING_VERSION).
# The previous tag is resolved from the repository's tags; for the first release
# the note links to the tag's commit list instead of a comparison.
#
# 模板本身的结构由 scripts/check-release-notes.sh --skeleton 校验，因此 --self-test
# 不需要任何 tag 或版本号。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_SLUG="yuzio-ai/ozyune"
TEMPLATE="$REPO_ROOT/.github/RELEASE_NOTES_TEMPLATE.md"
NOTES_DIR="$REPO_ROOT/docs/releases"
CHECK="$REPO_ROOT/scripts/check-release-notes.sh"

if [ ! -f "$TEMPLATE" ]; then
    echo "❌ template not found: ${TEMPLATE#"$REPO_ROOT"/}" >&2
    exit 1
fi

# ── --self-test ──────────────────────────────────
if [ "${1:-}" = "--self-test" ]; then
    bash "$CHECK" --skeleton "$TEMPLATE"
    exit $?
fi

# ── arguments ────────────────────────────────────
VERSION="${1:-}"
TO_STDOUT=0
if [ "${2:-}" = "--stdout" ]; then
    TO_STDOUT=1
fi

if [ -z "$VERSION" ]; then
    sed -n '3,19p' "$0"
    exit 1
fi

if ! printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
    echo "❌ version must look like 1.2.0 — got '$VERSION'" >&2
    exit 1
fi

TAG="v$VERSION"

# ── previous tag ─────────────────────────────────
PREVIOUS_TAG=""
if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "❌ tag $TAG already exists — release notes for it should already be committed" >&2
    exit 1
fi

PREVIOUS_TAG="$(git -C "$REPO_ROOT" tag --list 'v*' --sort=-v:refname 2>/dev/null | head -1)"

# ── render ───────────────────────────────────────
# The template opens with an HTML comment block addressed to the author; drop it,
# and leave the inline <!-- hints --> in place so the writer knows what to fill.
render() {
    awk '
        NR == 1 && /^<!--/ { skipping = 1 }
        skipping { if ($0 ~ /-->/) skipping = 0; next }
        { print }
    ' "$TEMPLATE"
}

if [ -n "$PREVIOUS_TAG" ]; then
    CHANGELOG="https://github.com/$REPO_SLUG/compare/$PREVIOUS_TAG...$TAG"
else
    CHANGELOG="https://github.com/$REPO_SLUG/commits/$TAG"
fi

OUTPUT="$(mktemp "${TMPDIR:-/tmp}/ozyune-notes.XXXXXX")"
trap 'rm -f "$OUTPUT"' EXIT
render \
    | sed -e "s|{{VERSION}}|$VERSION|g" \
          -e "s|{{CHANGELOG_URL}}|$CHANGELOG|g" \
    > "$OUTPUT"

if [ "$TO_STDOUT" -eq 1 ]; then
    cat "$OUTPUT"
    exit 0
fi

mkdir -p "$NOTES_DIR"
DESTINATION="$NOTES_DIR/$TAG.md"
if [ -e "$DESTINATION" ]; then
    echo "❌ already exists: ${DESTINATION#"$REPO_ROOT"/}" >&2
    exit 1
fi
cp "$OUTPUT" "$DESTINATION"

RELATIVE="${DESTINATION#"$REPO_ROOT"/}"

echo "──────────────────────────────────────────────"
echo " 已生成: $RELATIVE"
if [ -n "$PREVIOUS_TAG" ]; then
    echo " 变更范围: $PREVIOUS_TAG...$TAG"
else
    echo " 变更范围: 首个版本（$TAG）"
fi
echo "──────────────────────────────────────────────"
echo " 下一步:"
echo "   1. 填写正文，删掉用不到的小节与全部 <!-- 提示 -->"
echo "   2. bash scripts/check-release-notes.sh $RELATIVE"
echo "   3. git add $RELATIVE"
echo "   4. ./scripts/preflight.sh          # 打包后、发布前"
echo "   5. 发布（标题恒等于 tag，不要手打）："
echo "      gh release create $TAG Ozyune.zip --title $TAG --notes-file $RELATIVE"
