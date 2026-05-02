#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 exc-D inc.

set -e

# ====================================================
# convert-comments.sh
# Apply or revert locale-specific comment / string substitutions.
#
# Each lang/<locale>/<source-path>.tsv is a tab-separated pair list:
#   <english-text>	<locale-text>
# Lines without a tab (or with empty fields) are ignored.
#
# Usage:
#   ./convert-comments.sh ja                # all files, English -> Japanese
#   ./convert-comments.sh ja setup.sh       # one file, English -> Japanese
#   ./convert-comments.sh ja --reverse      # all files, Japanese -> English
#   ./convert-comments.sh ja setup.sh --reverse
# ====================================================

print_usage() {
    cat <<'EOF'
Usage: ./convert-comments.sh <locale> [--reverse] [file]

  <locale>      Target locale (e.g., ja, en)
  --reverse     Swap dictionary columns (revert FROM the locale)
  [file]        Optional source file (default: all files with dicts)
EOF
}

LOCALE=""
REVERSE=false
TARGET_FILE=""

for arg in "$@"; do
    case "$arg" in
        --reverse) REVERSE=true ;;
        -h|--help) print_usage; exit 0 ;;
        --*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *)
            if [ -z "$LOCALE" ]; then
                LOCALE="$arg"
            else
                TARGET_FILE="$arg"
            fi
            ;;
    esac
done

if [ -z "$LOCALE" ]; then
    print_usage
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

DICT_DIR="lang/$LOCALE"
if [ ! -d "$DICT_DIR" ]; then
    echo "No dictionary directory: $DICT_DIR" >&2
    exit 1
fi

# Escape a string for use as a sed BRE pattern (delimiter = '|').
# Backslash must be first so subsequent escapes are not double-escaped.
escape_pattern() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//]/\\]}"
    s="${s//\[/\\[}"
    s="${s//./\\.}"
    s="${s//\*/\\*}"
    s="${s//^/\\^}"
    s="${s//\$/\\\$}"
    s="${s//|/\\|}"
    printf '%s' "$s"
}

# Escape a string for use as a sed replacement (delimiter = '|').
escape_replacement() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//&/\\&}"
    s="${s//|/\\|}"
    printf '%s' "$s"
}

apply_dict() {
    local dict="$1"
    local source="$2"
    if [ ! -f "$source" ]; then
        echo "  skip (source not found): $source"
        return
    fi

    local sed_script
    sed_script=$(mktemp)

    # Sort pairs by source-string length descending so longer keys are
    # applied before shorter ones (avoids partial-match collisions).
    awk -F'\t' -v rev="$REVERSE" '
        NF >= 2 && $1 != "" && $2 != "" {
            if (rev == "true") { src=$2; dst=$1 }
            else               { src=$1; dst=$2 }
            print length(src) "\t" src "\t" dst
        }' "$dict" | LC_ALL=C sort -rn -t$'\t' -k1,1 | while IFS=$'\t' read -r _len src dst; do
        s_esc=$(escape_pattern "$src")
        r_esc=$(escape_replacement "$dst")
        printf 's|%s|%s|g\n' "$s_esc" "$r_esc"
    done > "$sed_script"

    if [ -s "$sed_script" ]; then
        sed -i.bak -f "$sed_script" "$source"
        rm -f "${source}.bak"
        echo "  converted: $source"
    fi
    rm -f "$sed_script"
}

if [ -n "$TARGET_FILE" ]; then
    DICT="$DICT_DIR/$TARGET_FILE.tsv"
    if [ ! -f "$DICT" ]; then
        echo "No dictionary: $DICT" >&2
        exit 1
    fi
    apply_dict "$DICT" "$TARGET_FILE"
else
    while IFS= read -r dict; do
        rel="${dict#"$DICT_DIR"/}"
        source="${rel%.tsv}"
        apply_dict "$dict" "$source"
    done < <(find "$DICT_DIR" -type f -name '*.tsv' | sort)
fi

echo "Done."
