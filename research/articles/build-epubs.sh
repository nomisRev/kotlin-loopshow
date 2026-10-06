#!/usr/bin/env bash
# Builds one EPUB per article in ./epub for the reMarkable: the tutorial first, then the
# original KEEP texts it is based on as appendix chapters. Mentions of and links to a
# bundled KEEP become in-book links (see keep-links.lua).
set -euo pipefail
cd "$(dirname "$0")"
KEEP_DIR=../keep
COMMIT=$(cut -c1-7 "$KEEP_DIR/upstream-commit.txt")

# article -> bundled KEEP/note file stems, primary sources first
books=(
  "01-value-classes:KEEP-0454-better-immutability-value-classes-MFVC KEEP-0468-inline-value-classes KEEP-0470-will-become-value KEEP-0453-better-immutability-value-classes-motivation 0001-value-classes KEEP-0104-inline-classes KEEP-0340-multi-field-value-classes KEEP-0394-jvm-expose-boxed"
  "02-context-parameters:KEEP-0367-context-parameters KEEP-0448-explicit-context-arguments KEEP-0259-context-receivers KEEP-0443-suspend-CoroutineContext-context-parameter"
  "03-companion-blocks:KEEP-0449-companions-block-extension KEEP-0427-static-member-type-extension KEEP-0150-jvm-static-annotation-in-interface-companion KEEP-0152-jvm-field-annotation-in-interface-companion"
  "04-collection-literals:KEEP-0416-collection-literals"
  "05-name-based-destructuring:KEEP-0438-name-based-destructuring KEEP-0032-destructuring-in-parameters KEEP-0412-underscores-for-local-variables"
  "06-properties:KEEP-0430-explicit-backing-fields KEEP-0455-lateinit-val KEEP-0452-assign-once KEEP-0073-lateinit-property-isinitialized-intrinsic KEEP-0086-local-and-top-level-lateinit-vars"
  "07-rich-errors:KEEP-0462-rich-errors KEEP-0441-rich-errors-motivation 0009-rich-errors-use-cases"
  "08-api-guardrails:KEEP-0412-unused-return-value-checker KEEP-0439-named-only-parameters KEEP-0193-named-arguments-in-their-own-position KEEP-0412-underscores-for-local-variables"
  "09-power-assert:KEEP-0458-power-assert-explanation"
)

source_of() {
  if [[ $1 == KEEP-* ]]; then echo "$KEEP_DIR/proposals/$1.md"; else echo "$KEEP_DIR/notes/$1.md"; fi
}

id_of() {
  if [[ $1 =~ ^KEEP-([0-9]+)-(.*)$ ]]; then
    echo "keep-${BASH_REMATCH[1]}-$(tr '[:upper:]' '[:lower:]' <<< "${BASH_REMATCH[2]}")"
  else
    echo "note-$(tr '[:upper:]' '[:lower:]' <<< "$1")"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p epub

for book in "${books[@]}"; do
  article=${book%%:*}
  stems=${book#*:}
  export BOOK=$stems
  parts=()

  # front matter of the article becomes the book metadata
  awk 'NR==1 && /^---$/ {on=1; next} on && /^---$/ {exit} on' "$article.md" > "$TMP/$article.meta.yaml"

  {
    echo '# Tutorial {#tutorial}'
    echo
    PREFIX=tutorial IS_KEEP=0 pandoc "$article.md" -f markdown -t markdown \
      --lua-filter keep-links.lua --wrap=none
  } > "$TMP/$article.00.md"
  parts+=("$TMP/$article.00.md")

  i=0
  for stem in $stems; do
    i=$((i + 1))
    src=$(source_of "$stem")
    id=$(id_of "$stem")
    title=$(grep -m1 '^# ' "$src" | sed 's/^# //')
    if [[ $stem =~ ^KEEP-([0-9]+) ]]; then label="KEEP-${BASH_REMATCH[1]}"; else label="Design note ${stem%%-*}"; fi
    out="$TMP/$article.$(printf '%02d' "$i").md"
    {
      echo "# $label · $title {#$id}"
      echo
      echo "*Original text from the Kotlin KEEP repository at commit $COMMIT. [Back to the tutorial](#tutorial).*"
      echo
      PREFIX=$id IS_KEEP=1 pandoc "$src" -f gfm -t markdown \
        --lua-filter keep-links.lua --wrap=none
    } > "$out"
    parts+=("$out")
  done

  pandoc "${parts[@]}" -f markdown -t epub3 \
    --metadata-file "$TMP/$article.meta.yaml" \
    --css epub.css --toc --toc-depth=2 --split-level=2 \
    --syntax-highlighting=monochrome \
    -o "epub/$article.epub"
  echo "epub/$article.epub ($(wc -w $article.md | awk '{print $1}') words tutorial + $(wc -w $(for s in $stems; do source_of $s; done) | tail -1 | awk '{print $1}') words KEEP text)"
done
