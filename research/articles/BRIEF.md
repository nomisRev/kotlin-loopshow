# Brief: tutorial articles from KEEPs

Reader: Simon, a Kotlin developer advocate. He knows Kotlin deeply and needs to catch up on
these features fast and precisely enough to teach them and answer hard questions at a booth.
He reads the result as an EPUB on a reMarkable Paper Pro (e-ink, reflowed, no colour).

Sources live in `research/keep/` (a snapshot of github.com/Kotlin/KEEP):
`proposals/KEEP-NNNN-*.md`, `notes/NNNN-*.md`. Read every source KEEP for your article
completely before writing. The project compiles with Kotlin 2.4.20.

## Accuracy rules

- The KEEP text is the source of truth. Use only syntax, semantics, flags and version numbers
  stated in the KEEP. Never invent syntax, compiler flags, annotations or stdlib functions.
- If the KEEP leaves something open, say it is open. If you extrapolate, label it
  "(my reading)" so it is clearly not a KEEP claim.
- State the status precisely (e.g. "Experimental in 2.4, enable with `-X...`",
  "Public discussion, not implemented"). Do not upgrade a proposal into a shipped feature.
- Rejected alternatives are part of the rationale: explain why they were rejected, as the
  KEEP argues it.

## Structure (Pandoc Markdown)

Start with a YAML metadata block:

```
---
title: "<Feature name>"
subtitle: "<one-line claim>"
author: "Notes from KEEP-NNNN[, KEEP-MMMM]"
date: "October 2026"
lang: en
---
```

Then these `##` sections, in this order. Adapt names to the topic, drop a section only if
it truly does not apply, and add sub-sections (`###`) freely:

1. **At a glance**: status of each KEEP, Kotlin version, how to enable it, YouTrack issue,
   and a 5-line code teaser.
2. **The problem**: the rationale. Show the pain in today's Kotlin with code.
3. **The feature, step by step**: tutorial order, simplest case first, building up.
4. **Typical usage**: realistic patterns (domain models, DSLs, Ktor/Compose/coroutines-style
   library code where it fits).
5. **Rules and edge cases**: resolution, inference, overloads, inheritance, generics,
   nullability, visibility, interaction with other features, error and warning cases. Show
   code that does not compile and explain why. This should be the longest section.
6. **Platform interop**: what Java sees (show the Java side in a `java` fence), JVM binary
   shape and ABI, binary and source compatibility, JS/Native/Wasm/KMP differences,
   reflection, serialization where relevant.
7. **Design decisions**: alternatives considered and why they lost. Compare with
   Scala/Swift/C#/Java where the KEEP does.
8. **Open questions and what may change**.
9. **Cheat sheet**: a compact recap, as short code plus a short bullet list.
10. **Talking points**: 5–8 one-liners Simon can say on stage or at a booth, plus 3 tricky
    audience questions with crisp answers.

## Code

- Every section and sub-section has at least one code example. Prefer before/after pairs.
- Use fenced blocks with a language: ```` ```kotlin ````, ```` ```java ````, ```` ```text ````.
- Keep code lines at **60 characters or less** (e-ink reflow). Wrap arguments instead.
- Mark compile errors and warnings with trailing comments: `// ERROR: ...`, `// WARNING: ...`.
  Show runtime output as `// prints: ...` comments.
- Use small, concrete domain examples (User, Order, Money, Temperature, HTTP requests).
  Avoid foo/bar.

## Prose

- Dense, direct and technical. No marketing language, no filler intros, no "In this article".
- Short paragraphs. Explain why, not only what.
- Tables are fine but keep them to 3 columns or less.
- No raw HTML, no HTML anchors, no images, no footnotes. Plain Markdown links to the KEEPs on
  GitHub are fine.
- Length: as long as the material needs, typically 3,000–7,000 words.

## Output

Write a single file to `research/articles/<NN>-<slug>.md` (the exact name is given in your
task). Do not create other files. Finish with a 3-line summary: file path, word count and any
place where the KEEP was ambiguous.
