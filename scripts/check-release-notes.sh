#!/bin/bash
#
# check-release-notes.sh — release note style check.
#
# .github/RELEASE_NOTES_TEMPLATE.md defines the pinned release note style; this
# script enforces it. A note authored from scratch cannot pass, so a new release
# cannot quietly drift away from the previous one.
#
# Usage:
#   bash scripts/check-release-notes.sh                     # all docs/releases/*.md
#   bash scripts/check-release-notes.sh <file> [<file>...]  # specific files
#   bash scripts/check-release-notes.sh --skeleton <file>   # structure only: allow
#                                                           # unfilled sections and {{placeholders}}
#
# Pinned invariants:
#   1. the language nav line first, then English before 简体中文, both anchored;
#   2. ## for a language, ### for a section, and no other heading level;
#   3. sections come from one vocabulary and keep its order (see EN_SECTIONS);
#   4. Requirements / Installation (系统要求 / 安装) are always present;
#   5. every section that survives has content;
#   6. the language block closes with compare/<previous-tag>...<tag>
#      (commits/<tag> for the first release), and <tag> matches the file name;
#   7. the asset is always Ozyune.zip, never Ozyune-<version>.zip.
#
# 全部通过退出码为 0，任意一项失败退出码为 1。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_SLUG="yuzio-ai/ozyune"
NOTES_DIR="$REPO_ROOT/docs/releases"

# The fixed vocabulary, in the only order sections may appear.
EN_SECTIONS=("New" "Changed" "Fixed" "How it works" "Engineering" "Known limitations" "Requirements" "Installation")
ZH_SECTIONS=("新增" "变更" "修复" "实现方式" "工程质量" "已知限制" "系统要求" "安装")
# Indexes into the vocabulary that every release note must carry.
REQUIRED_INDEXES=(6 7)

SKELETON=0
PROBLEMS=()
FAILED_FILES=0

problem() { PROBLEMS+=("$1"); }

# index_of <needle> <haystack...> — prints the 0-based index, or fails.
index_of() {
    local needle="$1"; shift
    local i=0
    for candidate in "$@"; do
        if [ "$candidate" = "$needle" ]; then
            printf '%s' "$i"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

# version_key <vX.Y.Z> — zero padded, and stripped of the leading "v", so a plain
# lexical sort matches version order (v10.0.0 must sort after v9.0.0).
version_key() {
    printf '%s' "$1" | sed 's/^v//' | awk -F. '{ printf "%04d%04d%04d", $1, $2, $3 }'
}

# lowest_note_tag <dir> — the oldest release note next to this one. That note is
# the only one allowed to link to commits/<tag> instead of a comparison; every
# later release must point at its predecessor.
lowest_note_tag() {
    local dir="$1" candidate
    for candidate in "$dir"/v*.md; do
        [ -e "$candidate" ] || continue
        candidate="${candidate##*/}"
        printf '%s %s\n' "$(version_key "${candidate%.md}")" "${candidate%.md}"
    done | LC_ALL=C sort -k1,1 | head -1 | awk '{ print $2 }'
}

# strip_comments <file> — drop HTML comments, so authoring hints never read as
# content. Comments inside a ``` fence are literal content and are left alone.
strip_comments() {
    awk '
        /^[[:space:]]*```/ { fence = !fence; print; next }
        fence { print; next }
        {
            line = $0
            while (match(line, /<!--/)) {
                before = substr(line, 1, RSTART - 1)
                rest = substr(line, RSTART + 4)
                if (match(rest, /-->/)) {
                    line = before substr(rest, RSTART + 3)
                    continue
                }
                # Multi-line comment: swallow lines up to the one that closes it,
                # then loop again — the closing line may hold another comment.
                line = before
                while ((getline more) > 0) {
                    if (match(more, /-->/)) { line = line substr(more, RSTART + 3); break }
                }
                continue
            }
            print line
        }' "$1"
}

# outside_fences <file> — the lines that are not inside a ``` code fence.
# A fence may be indented (a list item wraps its block in spaces), so the marker
# is matched after any leading whitespace — see headings_of and strip_comments.
outside_fences() {
    awk '
        /^[[:space:]]*```/ { fence = !fence; next }
        !fence { print }
    ' "$1"
}

# headings_of <stripped-file> — "line<TAB>level<TAB>text", code fences excluded.
headings_of() {
    awk '
        /^[[:space:]]*```/ { fence = !fence; next }
        fence { next }
        /^#+ / {
            match($0, /^#+/)
            level = RLENGTH
            printf "%d\t%d\t%s\n", NR, level, substr($0, level + 2)
        }
    ' "$1"
}

# block_has <headings> <from> <to> <level> <text> — 0 when found inside (from, to); to=0 means EOF.
block_has() {
    awk -F'\t' -v from="$2" -v to="$3" -v level="$4" -v text="$5" '
        $2 == level && $3 == text && $1 > from && (to == 0 || $1 < to) { found = 1 }
        END { exit !found }
    ' "$1"
}

# empty_sections <stripped> <headings> — "line<TAB>text" for headings with no body.
empty_sections() {
    awk -v headings_file="$2" '
        BEGIN {
            while ((getline h < headings_file) > 0) {
                split(h, parts, "\t")
                heading_at[parts[1]] = parts[3]
            }
        }
        {
            if (NR in heading_at) {
                if (current != "" && !content) printf "%d\t%s\n", current_line, current
                current = heading_at[NR]; current_line = NR; content = 0
                next
            }
            if (current != "" && $0 ~ /[^[:space:]]/) content = 1
        }
        END {
            if (current != "" && !content) printf "%d\t%s\n", current_line, current
        }' "$1"
}

# check_sections <headings> <from> <to> <lang> — vocabulary, order and required sections.
check_sections() {
    local headings="$1" from="$2" to="$3" lang="$4"
    local -a vocabulary
    if [ "$lang" = "en" ]; then vocabulary=("${EN_SECTIONS[@]}"); else vocabulary=("${ZH_SECTIONS[@]}"); fi

    local line level text index last=-1
    while IFS=$'\t' read -r line level text; do
        [ "$level" = "3" ] || continue
        [ "$line" -gt "$from" ] || continue
        if [ "$to" -ne 0 ] && [ "$line" -ge "$to" ]; then
            continue
        fi
        if ! index="$(index_of "$text" "${vocabulary[@]}")"; then
            problem "[$lang] line $line: \"$text\" is not a fixed section name"
            continue
        fi
        if [ "$index" -le "$last" ]; then
            problem "[$lang] line $line: \"$text\" is out of order or repeated"
        fi
        last="$index"
    done < "$headings"

    local required
    for required in "${REQUIRED_INDEXES[@]}"; do
        if ! block_has "$headings" "$from" "$to" 3 "${vocabulary[$required]}"; then
            problem "[$lang] missing required section \"${vocabulary[$required]}\""
        fi
    done
}

# validate_changelog <url> <lang> <tag> <is-first-release>
validate_changelog() {
    local url="$1" lang="$2" tag="$3" first="$4"
    if [ -z "$url" ]; then
        problem "[$lang] missing the closing changelog line"
        return 0
    fi
    [ "$SKELETON" -eq 1 ] && return 0
    local expected="https://github.com/$REPO_SLUG/compare/<previous-tag>...$tag"
    local pattern="^https://github\.com/$REPO_SLUG/compare/v[0-9][0-9.]*\.\.\.$tag\$"
    if [ "$first" -eq 1 ]; then
        expected="https://github.com/$REPO_SLUG/compare/<previous-tag>...$tag (or commits/$tag for the first release)"
        pattern="^https://github\.com/$REPO_SLUG/(compare/v[0-9][0-9.]*\.\.\.$tag|commits/$tag)\$"
    fi
    if ! printf '%s' "$url" | grep -qE "$pattern"; then
        problem "[$lang] changelog link must be $expected — got: $url"
    fi
}

check_file() { # check_file <path>
    local file="$1"
    local base
    base="$(basename "$file")"
    PROBLEMS=()

    if [ "$SKELETON" -eq 0 ] && ! printf '%s' "$base" | grep -qE '^v[0-9]+\.[0-9]+(\.[0-9]+)?\.md$'; then
        problem "file name must be v<major>.<minor>[.<patch>].md — got $base"
    fi

    strip_comments "$file" | tr -d '\r' > "$STRIPPED"
    headings_of "$STRIPPED" > "$HEADINGS"

    # ── language nav line ────────────────────────
    local nav_line
    nav_line="$(grep -nF -m1 '<a href="#english">English</a> | <a href="#简体中文">简体中文</a>' "$STRIPPED" | cut -d: -f1)"
    if [ -z "$nav_line" ]; then
        problem 'missing the language nav line: <a href="#english">English</a> | <a href="#简体中文">简体中文</a>'
    elif [ "$nav_line" -gt 1 ] && [ "$(head -n $((nav_line - 1)) "$STRIPPED" | grep -c '[^[:space:]]')" -ne 0 ]; then
        problem "the language nav line must be the first non-blank line"
    fi

    # ── anchors ──────────────────────────────────
    local en_anchor zh_anchor
    en_anchor="$(grep -nF -m1 '<a id="english"></a>' "$STRIPPED" | cut -d: -f1)"
    zh_anchor="$(grep -nF -m1 '<a id="简体中文"></a>' "$STRIPPED" | cut -d: -f1)"
    [ -n "$en_anchor" ] || problem 'missing the anchor <a id="english"></a>'
    [ -n "$zh_anchor" ] || problem 'missing the anchor <a id="简体中文"></a>'

    # ── heading levels and language labels ───────
    local line level text
    while IFS=$'\t' read -r line level text; do
        case "$level" in
            2)
                case "$text" in
                    English|简体中文) ;;
                    *) problem "line $line: language heading must be \"English\" or \"简体中文\" — got \"$text\"" ;;
                esac
                ;;
            3) ;;
            *) problem "line $line: h$level heading — only ## for a language and ### for a section are allowed — \"$text\"" ;;
        esac
    done < "$HEADINGS"

    # ── language order ───────────────────────────
    local en_line zh_line en_count zh_count
    en_line="$(awk -F'\t' '$2 == 2 && $3 == "English" { print $1 }' "$HEADINGS" | head -1)"
    zh_line="$(awk -F'\t' '$2 == 2 && $3 == "简体中文" { print $1 }' "$HEADINGS" | head -1)"
    en_count="$(awk -F'\t' '$2 == 2 && $3 == "English"' "$HEADINGS" | wc -l | tr -d ' ')"
    zh_count="$(awk -F'\t' '$2 == 2 && $3 == "简体中文"' "$HEADINGS" | wc -l | tr -d ' ')"
    [ "$en_count" = "1" ] || problem "\"## English\" must appear exactly once — found $en_count"
    [ "$zh_count" = "1" ] || problem "\"## 简体中文\" must appear exactly once — found $zh_count"
    if [ -n "$en_line" ] && [ -n "$zh_line" ]; then
        if [ "$en_line" -gt "$zh_line" ]; then
            problem "English must come first — English is at line $en_line, 简体中文 at line $zh_line"
        else
            if [ -n "$en_anchor" ] && [ "$en_anchor" -gt "$en_line" ]; then
                problem "[en] the English anchor must precede the \"## English\" heading"
            fi
            check_sections "$HEADINGS" "$en_line" "$zh_line" en
            check_sections "$HEADINGS" "$zh_line" 0 zh
        fi
    fi

    # ── closing changelog lines ──────────────────
    local tag="${base%.md}"
    local first=0
    if [ "$tag" = "$(lowest_note_tag "$(dirname "$file")")" ]; then
        first=1
    fi
    local en_url zh_url en_log zh_log
    en_url="$(sed -n 's/^\*\*Full changelog\*\*: //p' "$STRIPPED" | head -1)"
    zh_url="$(sed -n 's/^\*\*完整变更\*\*：//p' "$STRIPPED" | head -1)"
    en_log="$(grep -nF -m1 '**Full changelog**: ' "$STRIPPED" | cut -d: -f1)"
    zh_log="$(grep -nF -m1 '**完整变更**：' "$STRIPPED" | cut -d: -f1)"
    validate_changelog "$en_url" en "$tag" "$first"
    validate_changelog "$zh_url" zh "$tag" "$first"
    if [ -n "$en_log" ] && [ -n "$zh_anchor" ] && [ "$en_log" -ge "$zh_anchor" ]; then
        problem "[en] the changelog line must close the English block, before the 简体中文 anchor"
    fi
    if [ -n "$zh_log" ] && [ -n "$zh_anchor" ] && [ "$zh_log" -le "$zh_anchor" ]; then
        problem "[zh] the changelog line must close the 简体中文 block, after the 简体中文 anchor"
    fi

    # ── asset name ───────────────────────────────
    if grep -qE 'Ozyune-[0-9]' "$STRIPPED"; then
        problem "the asset is called Ozyune.zip — found $(grep -m1 -oE 'Ozyune-[0-9][0-9A-Za-z._-]*' "$STRIPPED")"
    fi

    # ── actually filled in ───────────────────────
    if [ "$SKELETON" -eq 0 ]; then
        local leftover
        leftover="$(grep -m1 -oE '\{\{[^}]*\}\}' "$STRIPPED")"
        [ -z "$leftover" ] || problem "unreplaced template placeholder left in the note: $leftover"
        local hints
        hints="$(outside_fences "$file" | grep -cF '<!--')"
        if [ "$hints" -gt 0 ]; then
            problem "authoring comment left in the note — remove all $hints <!-- ... --> hint(s) (comments inside a code fence are content and are fine)"
        fi
        while IFS=$'\t' read -r line text; do
            [ -n "$line" ] || continue
            problem "line $line: section \"$text\" has no content — fill it in or delete it"
        done < <(empty_sections "$STRIPPED" "$HEADINGS")
    fi

    # ── report ───────────────────────────────────
    if [ "${#PROBLEMS[@]}" -eq 0 ]; then
        printf '  ✅ %s\n' "${file#"$REPO_ROOT"/}"
    else
        FAILED_FILES=$((FAILED_FILES + 1))
        printf '  ❌ %s\n' "${file#"$REPO_ROOT"/}"
        local item
        for item in "${PROBLEMS[@]}"; do
            printf '     - %s\n' "$item"
        done
    fi
}


# ── arguments ────────────────────────────────────
FILES=()
if [ "$#" -gt 0 ]; then
    for argument in "$@"; do
        case "$argument" in
            --skeleton) SKELETON=1 ;;
            -h|--help)
                sed -n '3,22p' "$0"
                exit 0
                ;;
            *) FILES+=("$argument") ;;
        esac
    done
fi

if [ "${#FILES[@]}" -eq 0 ]; then
    if [ -d "$NOTES_DIR" ]; then
        while IFS= read -r found; do
            FILES+=("$found")
        done < <(find "$NOTES_DIR" -maxdepth 1 -name '*.md' | LC_ALL=C sort)
    fi
    if [ "${#FILES[@]}" -eq 0 ]; then
        echo "❌ no release notes found under ${NOTES_DIR#"$REPO_ROOT"/}" >&2
        exit 1
    fi
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ozyune-release-notes.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
STRIPPED="$WORK_DIR/stripped.md"
HEADINGS="$WORK_DIR/headings.tsv"

echo "──────────────────────────────────────────────"
echo " Ozyune 发布说明样式"
if [ "$SKELETON" -eq 1 ]; then
    echo " 模式: 只校验骨架"
fi
echo "──────────────────────────────────────────────"

for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ not a file: $file" >&2
        exit 1
    fi
    check_file "$file"
done

echo "──────────────────────────────────────────────"
if [ "$FAILED_FILES" -eq 0 ]; then
    echo " 🎉 ${#FILES[@]} 份发布说明符合固定样式"
    exit 0
else
    echo " ⚠️  ${#FILES[@]} 份中有 $FAILED_FILES 份偏离固定样式"
    echo "     模板: .github/RELEASE_NOTES_TEMPLATE.md"
    exit 1
fi

