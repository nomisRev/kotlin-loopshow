# Kotlin at Devoxx Belgium 2026

Kotlin booth showcase for Devoxx BE 2026 (5–9 October, Kinepolis Antwerp): a 19-slide Slidev
loop built on [`slidev-theme-kotlin`](https://www.npmjs.com/package/slidev-theme-kotlin), in the
same voice as kotlin-fundamentals. Every `kotlin` and `java` fence compiles with Kotlin 2.4.20;
the topic plan lives in `PLAN.md`, and the full candidate list that the loop was cut from is a
second deck, `extras.md` (`npm run dev:extras`).

## Run locally

Requires Node.js 20.12 or newer and a JDK 21.

```bash
npm install
npm run dev
```

## Booth loop

Autoplay is off in `npm run dev` so the deck stays an authoring tool. Add `?autoplay` to the URL
to loop it on the booth screen, or `?autoplay=8` for eight seconds per slide; Magic Move steps
hold for six seconds, the last slide wraps to the first, and a slide can set `autoplay: 15` in
its frontmatter. The timer lives in `global-top.vue`.

```bash
npm run build        # static site in dist/, open dist/index.html?autoplay
npm run export       # slides-export.pdf for the venue player
```

## Compile the snippets

```bash
npm run snippets     # regenerates the snippets of slides.md and extras.md
./gradlew build      # compiles every Kotlin and Java fence, checks the snippets are up to date
```

## Structure

| Path | Content |
| --- | --- |
| `slides.md` | the booth loop, all 19 slides inline |
| `extras.md`, `lessons/*.md` | every candidate slide from the plan, one file per section |
| `components/KotlinPlatforms.vue` | the "Kotlin runs everywhere" diagram |
| `global-top.vue` | booth autoplay |
| `research/` | cached Kotlin changelog and last year's Lambda World deck |

## Still to fill in

The KotlinConf slide carries a `<!-- PLACEHOLDER -->` comment: confirm the CFP status and add
the ticket QR code from DevRel. The extras deck keeps the talks, quiz and logo wall placeholders.
