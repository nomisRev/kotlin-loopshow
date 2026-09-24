#!/usr/bin/env bash
# Re-downloads the Kotlin "what's new" docs, the language feature status table and the roadmap
# from the kotlin-web-site repository (the source of kotlinlang.org/docs) into this folder.
set -euo pipefail
cd "$(dirname "$0")"
BASE=https://raw.githubusercontent.com/JetBrains/kotlin-web-site/master/docs/topics
for f in whatsnew22 whatsnew2220 whatsnew23 whatsnew2320 whatsnew24 whatsnew2420 whatsnew-eap; do
  curl -sfL -o "$f.md" "$BASE/whatsnew/$f.md" && echo "updated $f.md"
done
# Add the next release here once it has a page, e.g. whatsnew25
curl -sfL -o kotlin-language-features-and-proposals.md "$BASE/kotlin-language-features-and-proposals.md" && echo "updated kotlin-language-features-and-proposals.md"
curl -sfL -o roadmap.md "$BASE/roadmap.md" && echo "updated roadmap.md"
curl -sfL "https://api.github.com/repos/JetBrains/kotlin/releases?per_page=10" | grep -E '"(tag_name|published_at)"' | paste - - > releases.txt && echo "updated releases.txt"
date -u +"%Y-%m-%dT%H:%M:%SZ" > last-refresh.txt
