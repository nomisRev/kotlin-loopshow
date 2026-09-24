# Kotlin Showcase – Devoxx BE 2026 · topic plan

Booth slideshow that loops unattended on the JetBrains/Kotlin booth screen at Devoxx Belgium,
5–9 October 2026, Kinepolis Antwerp. Conference theme: "From Developer to Builder" (agentic
engineering, AI tooling). Audience: mostly Java/JVM developers walking past; many have not
written Kotlin, most know Java 21–26.

Built with Slidev on `slidev-theme-kotlin` 0.13.0 in `kotlin-devoxx-slides/`, in the same voice
as kotlin-fundamentals (`kotlin-slides-voice` skill): one claim per H1, the code is the slide,
`DrawnAnnotation` labels instead of prose, every `kotlin` fence compiles with Kotlin 2.4.20 plus
the `-X` flags from `kotlin-fundamentals/lessons/appendix-compiler-flags.md`.

## What last year's deck did (Lambda World 2025, 30 slides)

Section 1 "Kotlin 💜 Functional Programming" (evergreen: data-oriented programming, structured
concurrency, cancellation, nullability), section 2 "Kotlin is evolving" (context parameters,
unused return value checker, data-flow exhaustiveness, rich errors WIP, immutability WIP,
context-sensitive resolution, nested type aliases, annotation targets, name-based destructuring,
collection literals, named/evolving parameters), section 3 ecosystem (Koog, Kotlin AI examples,
Kotlin Notebook screenshots), section 4 booth logistics (talk, KotlinConf, quiz, "industry
leaders use Kotlin").

What changed since then and what the new deck must reflect:

| Feature | Lambda World 2025 | Devoxx BE 2026 (Kotlin 2.4.20, 2.5.0-Beta1) |
| --- | --- | --- |
| Context parameters | 2.2 preview | **Stable 2.4.0**; explicit context arguments experimental (`-Xexplicit-context-arguments`) |
| Unused return value checker | 2.2/2.3 | Experimental 2.3.0; `returnsResultOf` contract 2.4.0; roadmap: default warnings |
| Data-flow exhaustiveness | 2.3 | Stable 2.3.0 |
| Nested type aliases | 2.2 | Stable 2.3.0; local type aliases experimental (`-Xlocal-type-aliases`) |
| Annotation targets (`@all`, param-property default) | 2.2 | Stable 2.4.0 |
| Explicit backing fields | – | Experimental 2.3.0, **Stable 2.4.0** |
| Name-based destructuring | 2.3/2.4 slide | Experimental 2.3.20; `only-syntax` mode **Stable in 2.5.0-Beta1** |
| Collection literals | WIP | Experimental 2.4.0 (`-Xcollection-literals`, `operator fun of`) |
| Context-sensitive resolution | 2.2 | Still experimental; sealed/enclosing supertypes in scope since 2.3 |
| Compile-time constants | – | Experimental 2.4.0, **Stable in 2.5.0-Beta1** |
| Named/evolving parameters | WIP | `@IntroducedAt` experimental 2.4.0 |
| Companion blocks & extensions (statics) | – | Experimental in **2.5.0-Beta1** (`-Xcompanion-blocks-and-extensions`) |
| Rich errors | WIP | Still KEEP discussion (KEEP-441 motivation); no syntax shipped |
| Immutability / `copy var` | WIP | Still exploration and design (KT-77734) |
| `when` via `invokedynamic` | – | Stable and default 2.4.20 |
| Java support | – | Java 25 (2.3.0), Java 26 (2.4.0) |
| stdlib | – | UUID stable 2.4; `isSorted`; `allDistinct/allEqual` 2.4.20; `onTrue/onFalse/ifOrNull` 2.5 beta |

Cached sources: `research/kotlin-changelog/` (what's new 2.2.0 → 2.4.20 + EAP, features & proposals
table, roadmap as of August 2026). Refresh with `research/kotlin-changelog/refresh.sh`; last year's PDF and page thumbnails are in `research/lambda-world-2025/`.

## Design constraints for a booth loop

- Unattended and auto-advancing: nobody narrates, so every slide must be readable in ~15 s with
  no presenter notes. Annotations carry the explanation; a `>` lede names the version status
  (`> Stable since Kotlin 2.4.0`, `> Experimental in Kotlin 2.5.0-Beta1`, `> KEEP-441, under design`).
- No click builds. Magic Move is fine across slides (auto-advance still animates), but no
  `v-click`, `on="1"` or exercise slides.
- Chains of at most 2–3 slides per topic; the loop restarts every ~10 minutes so a passer-by sees
  a full cycle while waiting for coffee.
- Keep last year's rhythm: a section title slide, then 1–3 code slides per feature, then an
  ecosystem block, then logistics.
- Booth screen is landscape 16:9; export to PDF (`npm run export`) for the venue player, keep
  the Slidev build for a laptop loop. Auto-advance needs a small global component
  (`setInterval` → `$slidev.nav.next()`, wrap to slide 1); Slidev has no built-in autoplay.
- Devoxx theme is agentic engineering, so the ecosystem block leans on the Kotlin AI examples
  (Spring AI, LangChain4j, MCP), Kotlin LSP/VS Code and the Kotlin Toolchain. Kotlin Notebook
  (sunset) and Koog are excluded.

## Proposed slide list (≈45 slides, 6 sections)

### 0 · Cover and agenda (2)

1. Cover: "Kotlin at Devoxx Belgium 2026" – `layout: cover`, `kodee: welcome`.
2. Loop agenda (ordered list): Why Kotlin · What shipped in 2.3–2.4 · What's next in 2.5 · Kotlin 💜 Java · AI & tooling · Meet us.

### 1 · Why Kotlin (evergreen, 7) — reuse last year's section 1, in the new voice

| # | H1 claim | Source | Note |
| --- | --- | --- | --- |
| 3 | Section: "Kotlin is pragmatic, safe and expressive" | new | intro layout, 4 bullets from last year's slide 2 |
| 4 | `when` on a sealed type covers every case | last year p.3 (`Expr<T>`) | `InlineCompilerError` "'when' expression must be exhaustive, add 'is True'" |
| 5 | Nullability is part of the type | last year p.7 + lesson-2-3 | `SmartCast` wrapper on `user.name` |
| 6 | Exhaustiveness follows the data flow | lesson-2-2 (same H1 exists) | Stable 2.3.0, `TrafficLight` |
| 7 | `suspend` lifts every async style into one | last year p.4 + lesson-6 "A Java SDK has three asynchronous styles" | CompletableFuture + Reactor + Flow |
| 8 | `produce` ties the channel to a scope | last year p.5 + lesson-6 | structured concurrency |
| 9 | Cancellation is cooperative | last year p.6 + lesson-6 | `ensureActive`, `NonCancellable` |
| 10 | Kotlin runs everywhere | last year p.8 | JVM / Android / iOS / Web / Wasm / Desktop / Server diagram; theme has no diagram component → inline SVG or `layout: image` with a rebuilt PNG |

### 2 · What shipped since last year (Kotlin 2.3 → 2.4.20, 11)

| # | H1 claim | Version lede | Source |
| --- | --- | --- | --- |
| 11 | Section: "What shipped in Kotlin 2.3 and 2.4" | – | new |
| 12 | `context` supplies a context without a receiver | Stable 2.4.0 | lesson-5 (Logger example, last year p.10) |
| 13 | A context argument is passed by name | Experimental 2.4.0 `-Xexplicit-context-arguments` | appendix + lesson-5 "Pass a context argument by name"; chain from 12 |
| 14 | An explicit backing field replaces the underscore | Stable 2.4.0 | lesson-6 (`StateFlow` `field =`) |
| 15 | Ignoring a return value is a warning | Experimental 2.3.0 `-Xreturn-value-checker` | appendix + last year p.11 `formatGreeting` (`Warning` wrapper) |
| 16 | A contract can name the real must-use call | Experimental 2.4.0 `returnsResultOf` | appendix (2-slide magic move) — optional, cut first if too long |
| 17 | Destructuring matches by name, not position | Experimental 2.3.20 → `only-syntax` Stable 2.5.0-Beta1 | appendix + lesson-4; show `(val age, val name = first) = person` |
| 18 | Square brackets build a collection | Experimental 2.4.0 `-Xcollection-literals` | lesson-2-1 / lesson-3 |
| 19 | A literal needs an `of()` | same | lesson-3 (custom `operator fun of`, nested matrix from what's new) |
| 20 | Context-sensitive resolution drops the qualifier | Experimental since 2.2.0, improved 2.3 | appendix (`Season.next`, last year p.15) |
| 21 | More constants evaluate at compile time | Experimental 2.4.0 → Stable 2.5.0-Beta1 | appendix (`"kotlin".uppercase()`) |
| 22 | `@IntroducedAt` keeps old callers compiling | Experimental 2.4.0 | last year p.20 (`Button`), Java fence beside it showing the generated overloads |
| 23 | Nested type aliases are Stable | Stable 2.3.0 | last year p.16 (`Dijkstra`) — optional |

### 3 · What's next (2.5 and KEEP, 5)

| # | H1 claim | Version lede | Source |
| --- | --- | --- | --- |
| 24 | Section: "What's next in Kotlin 2.5 and beyond" | – | new |
| 25 | A companion block adds members in place | Experimental 2.5.0-Beta1 `-Xcompanion-blocks-and-extensions` | appendix (`Money.zero()`); java fence: `Money.zero()` is a plain static, no `@JvmStatic` — the Java-crowd hook |
| 26 | A companion extension reaches types you don't own | same | appendix (`LocalDate.epoch()`) |
| 27 | Rich errors are unions, not exceptions | KEEP-441, under design | last year p.13 (`User \| FetchError`); `no-compile` fence, "design may change" stamp |
| 28 | `copy var` updates an immutable value in place | KT-77734, exploration | last year p.14; `no-compile` |
| 29 | `CoroutineContext` becomes a context parameter | KEEP-443, discussion | new, `no-compile`; ties back to slide 12 — optional |

### 4 · Kotlin 💜 Java (Devoxx-specific, 5)

Devoxx is a Java conference; last year's deck (Lambda World) had no interop section. Every
slide pairs a `kotlin` fence with a `java` fence.

| # | H1 claim | Version lede | Source |
| --- | --- | --- | --- |
| 30 | Section: "Kotlin 💜 Java" | – | new |
| 31 | Kotlin compiles for Java 26 | 2.4.0 | new: `jvmTarget` + a record / sealed Java hierarchy consumed from Kotlin with `when` |
| 32 | A Java `@CheckReturnValue` is a Kotlin must-use call | 2.3.0 | lesson-4 "Java libraries opt in with `@CheckReturnValue`" |
| 33 | A value class can expose its box to Java | Experimental 2.2 `@JvmExposeBoxed` | new; Java fence calls the boxed API |
| 34 | Annotations land on the parameter and the property | Stable 2.4.0 | last year p.17 (Jakarta `@NotBlank`) |
| 35 | Lombok classes are visible to Kotlin | Alpha 2.3.20 | new; optional, `no-compile` |
| 36 | `when` compiles to `invokedynamic` | Stable 2.4.20 | new; optional — bytecode-only story, cut if the section is long |

### 5 · AI and tooling (4)

Kotlin Notebook has been sunset and Koog is deliberately left out, so this section is about the
language and toolchain in an AI-assisted workflow, not about JetBrains AI products.

| # | Slide | Source |
| --- | --- | --- |
| 37 | Section: "From developer to builder" (Devoxx theme) | new |
| 38 | Kotlin AI examples: Spring AI, LangChain4j, MCP from Kotlin | last year p.22 minus the notebook mention; QR code to the repo; one short `kotlin` fence (Spring AI `ChatClient` or the Kotlin MCP SDK) instead of a screenshot |
| 39 | The Kotlin Toolchain installs in one line / `kotlin init` | lesson-1 (same H1) |
| 40 | Kotlin LSP brings Kotlin to VS Code and agents | new; roadmap item "Support Kotlin LSP and VS Code"; `bash` fence with the install, screenshot optional |
| 41 | Ktor, Exposed, Compose Multiplatform in one line each | new tooling-overview bullet slide (Ktor 3, Exposed DAO 2.0, CMP) — optional |

### 6 · Meet us (4)

| # | Slide | Note |
| --- | --- | --- |
| 42 | Join us for the talk(s) | placeholder: JetBrains talks at Devoxx BE 2026 still to be filled in (speaker, room, time) |
| 43 | KotlinConf 2027 is coming to Kraków | 21–23 April 2027, ICE Kraków; ticket price rises after 16 October 2026; CFP status to confirm |
| 44 | Win a Kodee plushie / quiz | placeholder, booth activity to confirm |
| 45 | Industry leaders use Kotlin | last year p.30 logo wall (needs the asset from the JetBrains deck) |

Cut order if the loop is too long: 36, 35, 41, 29, 23, 16, then merge 18+19.

## Open decisions (defaults chosen, flag if you disagree)

1. **Compiler version**: pin Kotlin 2.4.20 for the snippet build (same as kotlin-fundamentals) and mark
   the 2.5.0-Beta1 slides with a lede; companion blocks already compile on 2.4.20 with the flag.
   Alternative: bump the snippet build to 2.5.0-Beta1 so the `only-syntax` destructuring and const
   evaluation slides need no flag.
2. **Rich errors / immutability**: kept as `no-compile` "under design" slides because they were the
   crowd-pullers last year, with an explicit "design may change" stamp.
3. **Auto-advance**: implement in `global-top.vue` of the deck (10 s per slide, magic-move slides 6 s),
   toggled with a query param so `npm run dev` stays usable for authoring.
4. **Logo wall / KotlinConf / talk slides**: need assets from JetBrains DevRel; scaffolded as
   placeholders.
5. **Assets to source**: "Kotlin runs everywhere" diagram, Kotlin LSP screenshot (optional),
   JetBrains talk schedule at Devoxx BE 2026.

## Work breakdown after this plan

1. `lessons/01-why-kotlin.md` … `lessons/06-meet-us.md`, one file per section, `src:` imported from `slides.md`.
2. Snippet compile setup: copy `build.gradle.kts` flags from kotlin-fundamentals appendix; `npm run snippets && ./gradlew build`.
3. Auto-advance component + `npm run export` check.
4. Annotation geometry pass in the editor (Alt+Shift+A), PNG export review.
