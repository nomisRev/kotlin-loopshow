#!/usr/bin/env bash
# Converts every KEEP and design note in ../keep into its own EPUB for the reMarkable:
# proposals/, stdlib/ and notes/ in this folder. Links to other KEEPs point to GitHub.
set -euo pipefail
cd "$(dirname "$0")"
HERE=$(pwd)
KEEP_DIR=$(cd ../keep && pwd)
ARTICLES=$(cd ../articles && pwd)
COMMIT=$(cut -c1-7 "$KEEP_DIR/upstream-commit.txt")
export HERE KEEP_DIR ARTICLES COMMIT

convert() {
  local rel=$1                      # e.g. proposals/stdlib/KEEP-0382-uuid.md
  local src="$KEEP_DIR/$rel" stem dir out title label
  stem=$(basename "$rel" .md)
  dir=$(dirname "$rel")
  case $dir in
    proposals) out="$HERE/proposals/$stem.epub" ;;
    proposals/stdlib) out="$HERE/stdlib/$stem.epub" ;;
    notes) out="$HERE/notes/note-$stem.epub" ;;
  esac
  title=$(grep -m1 '^# ' "$src" | sed -e 's/^# //' -e 's/`//g')
  if [[ $stem =~ ^KEEP-([0-9]+) ]]; then label="KEEP-${BASH_REMATCH[1]}"; else label="Design note ${stem%%-*}"; fi
  local id
  id=$(tr "[:upper:]" "[:lower:]" <<< "$stem"); [[ $dir == notes ]] && id="note-$id"
  BOOK= PREFIX=$id IS_KEEP=1 STANDALONE=1 \
  GITHUB_BASE="https://github.com/Kotlin/KEEP/blob/main/$dir/" \
  pandoc "$src" -f gfm -t epub3 \
    --lua-filter "$ARTICLES/keep-links.lua" \
    --resource-path "$(dirname "$src")" \
    --metadata title="$label · $title" \
    --metadata subtitle="Kotlin KEEP repository, commit $COMMIT" \
    --metadata lang=en \
    --css "$ARTICLES/epub.css" --toc --toc-depth=2 --split-level=2 \
    --syntax-highlighting=monochrome \
    -o "$out" 2> >(grep -v 'Could not' >&2 || true)
  echo "$out"
}
export -f convert

mkdir -p proposals stdlib notes
cd "$KEEP_DIR"
{ ls proposals/KEEP-*.md; ls proposals/stdlib/KEEP-*.md; ls notes/*.md; } \
  | xargs -P 8 -I{} bash -c 'convert "$1"' _ {} | sed "s|$HERE/||"
