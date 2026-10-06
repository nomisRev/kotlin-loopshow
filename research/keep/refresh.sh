#!/usr/bin/env bash
# Re-downloads the Kotlin Evolution and Enhancement Process proposals (KEEPs) from
# github.com/Kotlin/KEEP into this folder: proposals/, notes/, resources/ and the upstream README.
set -euo pipefail
cd "$(dirname "$0")"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git clone -q --depth 1 https://github.com/Kotlin/KEEP.git "$TMP/KEEP"
rm -rf proposals notes resources
cp -R "$TMP/KEEP/proposals" "$TMP/KEEP/notes" "$TMP/KEEP/resources" .
cp "$TMP/KEEP/README.md" KEEP-README.md
git -C "$TMP/KEEP" log -1 --format='%H %cI' > upstream-commit.txt
ls proposals/KEEP-*.md | sed 's|proposals/||' > index.txt
echo "updated $(wc -l < index.txt | tr -d ' ') KEEPs at $(cut -c1-7 upstream-commit.txt)"
date -u +"%Y-%m-%dT%H:%M:%SZ" > last-refresh.txt
