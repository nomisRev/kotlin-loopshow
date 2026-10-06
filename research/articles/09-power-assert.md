---
title: "Power-Assert Explanations"
subtitle: "Assertion functions get structured call-site data instead of a pre-baked string"
author: "Notes from KEEP-0458"
date: "October 2026"
lang: en
---

## At a glance

| Item | Value |
|---|---|
| KEEP | [KEEP-0458](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0458-power-assert-explanation.md) |
| Type | Design proposal (compiler plugin + runtime library) |
| Status | Prototype available in 2.4.0-Beta2 |
| Discussion | [KEEP-478](https://github.com/Kotlin/KEEP/discussions/478) |
| YouTrack | KT-66807, KT-66806, KT-66808 |
| Runtime | `kotlin("power-assert-runtime")` |
| Package | `kotlin.powerassert` |

Status, precisely: the KEEP says "Prototype available in
2.4.0-Beta2" and "some things may change before the final
2.4.0 release". The runtime API is explicitly declared
*unstable* ("stable for use but unstable for
implementation"). The KEEP does not say which release makes
it stable. This deck builds with 2.4.20; the KEEP makes no
claim about 2.4.20, so treat the API as experimental there
too (my reading).

How to enable it, as the KEEP shows it for the Beta:

```kotlin
plugins {
    kotlin("jvm") version "2.4.0-Beta2"
    kotlin("plugin.power-assert") version "2.4.0-Beta2"
}

dependencies {
    implementation(kotlin("power-assert-runtime"))
}
```

The teaser: one annotation, one intrinsic property.

```kotlin
@PowerAssert
fun verify(ok: Boolean) {
    if (!ok) throw AssertionError(
        PowerAssert.explanation?.toDefaultMessage()
    )
}
```

The one-sentence version: Power-Assert stops handing your
assertion function a finished `String` and starts handing it
a `CallExplanation`, a data model of the call site with
source text, offsets and every intermediate runtime value.

## The problem

### What Power-Assert does today

Power-Assert is a Kotlin compiler plugin. It rewrites calls to
a configured set of functions, identified by fully-qualified
name. By default that set is just `kotlin.assert`.

```kotlin
data class Mascot(val name: String)

assert(mascot.name == "Kodee")
```

The plugin turns that call into roughly this:

```kotlin
val tmp1 = mascot
val tmp2 = tmp1.name
val tmp3 = tmp2 == "Kodee"
assert(tmp3, { "assert(mascot.name == ...)\n..." })
```

Every subexpression is hoisted into a temporary, in evaluation
order. The last argument becomes a lambda that builds a
diagram. The diagram *layout* is fixed at compile time; only
the values are spliced in at runtime. The output:

```text
assert(mascot.name == "Kodee")
       |      |    |
       |      |    false
       |      Unknown
       Mascot(name=Unknown)
```

Any function works as a target if it takes a `String` or a
`() -> String` as its **last** parameter. `kotlin.test`'s
`assertTrue` and `assertEquals` are the usual candidates.

### Three pain points

The KEEP names three key problems.

**1. Configuration on every build.** The function list must
be repeated in every Gradle project. An assertion library has
no way to tell the plugin "my functions support you". So each
consumer configures, by name, the functions of every library
they use. The KEEP does not show that DSL; the plugin docs at
kotlinlang.org cover it (not a KEEP claim, my note).

```kotlin
// build.gradle.kts, today
powerAssert {
    // the list of FQ function names goes here,
    // per project, per library you use
}
```

**2. Parameter conventions.** To be a target your function
must end in a message parameter. That is a convention, not a
contract. A library author who wants Power-Assert support
must shape their API around it:

```kotlin
// Must end with String or () -> String,
// or the plugin cannot transform it.
fun assertPositive(
    amount: Money,
    message: () -> String,
)
```

**3. Static diagrams.** The plugin hands you a `String`. You
cannot find out which comparison failed, what the left and
right values were, or where in the source a value came from.
IntelliJ's "click to see difference" needs expected and actual
values as objects; a string gives you neither.

```kotlin
fun assertOrder(ok: Boolean, message: () -> String) {
    if (!ok) {
        val text = message()
        // text is all you get. Which `==` failed?
        // What was `expected`? Parse ASCII art?
        throw AssertionError(text)
    }
}
```

### Goals and non-goals

Goals, from the KEEP: functions are *discoverable* instead of
configured; they get call-site data through the plugin rather
than a parameter convention; and that data is *structured*,
so rendering is dynamic and tools can use it.

Non-goals are equally explicit:

- Not a macro or dynamic code execution system. It describes
  code; it is not for metaprogramming.
- Not a replacement for an assertion library. It enhances
  existing ones.
- No removal of existing behaviour. String-message
  transformation stays.

```kotlin
// Non-goal: this is NOT an expression-tree API
// you can use to rewrite or re-run code.
// You only get source text + recorded values.
```

## The feature, step by step

### Step 1: annotate a function

Put `@PowerAssert` on a function. No message parameter needed.

```kotlin
import kotlin.powerassert.PowerAssert

@PowerAssert
fun verify(condition: Boolean) {
    if (!condition) throw AssertionError("failed")
}
```

Call sites need nothing. With the plugin applied, the plugin
discovers the annotation and transforms every call to
`verify` without any FQ-name configuration.

```kotlin
verify(order.total > Money.ZERO)
```

### Step 2: read the explanation

Inside an annotated function, read the intrinsic
`PowerAssert.explanation`. It is a `CallExplanation?`.

```kotlin
import kotlin.powerassert.CallExplanation
import kotlin.powerassert.PowerAssert
import kotlin.powerassert.toDefaultMessage

@PowerAssert
fun verify(condition: Boolean) {
    if (!condition) {
        val e: CallExplanation? =
            PowerAssert.explanation
        throw AssertionError(
            e?.toDefaultMessage() ?: "failed"
        )
    }
}
```

`toDefaultMessage()` renders the familiar diagram. For the
mascot example, it prints the same tree as before.

```text
verify(mascot.name == "Kodee")
       |      |    |
       |      |    false
       |      Unknown
       Mascot(name=Unknown)
```

(Illustrative: this is the KEEP's diagram with the function
name changed. The exact layout is the renderer's business and
may change between versions.)

### Step 3: handle `null`

`explanation` is nullable on purpose. It is `null` when:

- the call site was compiled without the plugin,
- the caller is not Kotlin (Java, for example),
- the function is called via reflection or a method reference.

```kotlin
val checks = listOf(true, false)
checks.forEach(::verify)
// method reference: explanation == null inside
```

So every `@PowerAssert` function needs a fallback path. The
KEEP's own examples do one of three things: fall back to a
plain message, `error(...)` out, or just `println` the raw
value.

```kotlin
val e = PowerAssert.explanation
    ?: throw AssertionError(message)
```

### Step 4: keep the user's message out of it

Real assertion functions also take a message. Mark it with
`@PowerAssert.Ignore` so the plugin does not record its
subexpressions. This is the KEEP's headline example:

```kotlin
@PowerAssert
fun powerAssert(
    condition: Boolean,
    @PowerAssert.Ignore message: String? = null,
) {
    if (!condition) {
        val explanation = PowerAssert.explanation
        throw AssertionError(buildString {
            append("Assertion failed:")
            if (message != null) {
                append(" ").append(message)
            }
            if (explanation != null) {
                appendLine()
                appendLine(
                    explanation.toDefaultMessage()
                )
            }
        })
    }
}
```

Note the message is now an ordinary optional parameter. It is
not the last-parameter hook anymore, so its position is free.

### Step 5: walk the data model

`CallExplanation` is data, not text. Iterate it.

```kotlin
@PowerAssert
fun dump(condition: Boolean) {
    val e = PowerAssert.explanation ?: return
    for (x in e.expressions) {
        val src = e.source.substring(
            x.startOffset, x.endOffset,
        )
        println("$src = ${x.value}")
    }
}

dump(user.age >= 18)
// prints: user = User(name=Ann, age=17)
// prints: user.age = 17
// prints: 18 = 18
// prints: user.age >= 18 = false
```

(The printed lines are my reading of the model: one
`Expression` per intermediate value, in evaluation order, and
the literal `18` is present as a `LiteralExpression`. Whether
`>=` produces a plain `ValueExpression` is my reading; only
equality gets its own subclass.)

## The data model

### `@PowerAssert`

```kotlin
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.BINARY)
public annotation class PowerAssert {
    public companion object {
        @JvmStatic
        public val explanation: CallExplanation?
        // implemented as a compiler intrinsic
    }

    @Target(
        AnnotationTarget.VALUE_PARAMETER,
        AnnotationTarget.CLASS,
    )
    @Retention(AnnotationRetention.BINARY)
    public annotation class Ignore
}
```

`BINARY` retention matters: the annotation must survive into
the compiled library so that a *different* compilation (the
user's test module) can discover it at call sites.

### `Explanation`

The abstract base. `CallExplanation` is its only subclass
today.

```kotlin
public abstract class Explanation
internal constructor() {
    public abstract val offset: Int
    public abstract val source: String
    public abstract val expressions: List<Expression>
}
```

The constructor is `internal`, so you cannot add your own
subclass; the library owns the hierarchy.

### `CallExplanation` and `Argument`

```kotlin
public class CallExplanation(
    override val offset: Int,
    override val source: String,
    public val arguments: List<Argument?>,
) : Explanation() {
    override val expressions: List<Expression>
        get() = arguments
            .sortedBy { it?.startOffset }
            .flatMap {
                it?.expressions.orEmpty()
            }

    public class Argument(
        public val startOffset: Int,
        public val endOffset: Int,
        public val kind: Kind,
        public val expressions: List<Expression>,
    ) {
        public enum class Kind {
            DISPATCH, CONTEXT, EXTENSION, VALUE,
        }
    }
}
```

Two orders, two purposes:

- `arguments` is in **parameter** order, so you can index it
  like the function signature.
- `expressions` is re-sorted by **source** position
  (`startOffset`), so a renderer walks left to right through
  the text.

Note that `CallExplanation` and `Argument` have public
constructors. That is what lets the fluent-assertion example
later in this article build a synthetic combined explanation.

### `Expression`

```kotlin
public abstract class Expression
internal constructor(
    public val startOffset: Int,
    public val endOffset: Int,
    public val displayOffset: Int,
    public val value: Any?,
)
```

Three subclasses today:

| Subclass | Meaning |
|---|---|
| `ValueExpression` | a runtime value |
| `LiteralExpression` | a source literal; hidden by default |
| `EqualityExpression` | `==` result plus `lhs` and `rhs` |

Expressions come in **evaluation order**. `1 + 2` yields
three entries:

```kotlin
powerAssert(1 + 2 == 4)
// expressions, in order (my reading):
//   1        LiteralExpression, value 1
//   2        LiteralExpression, value 2
//   1 + 2    ValueExpression,   value 3
//   4        LiteralExpression, value 4
//   ... == 4 EqualityExpression, value false
```

The KEEP only states the first three entries (for `1 + 2`);
the classification as literal versus value is my reading of
the class descriptions.

`EqualityExpression` exists for one reason the KEEP spells
out: IntelliJ's "click to see difference". It carries both
sides as objects.

```kotlin
for (x in explanation.expressions) {
    if (x is EqualityExpression &&
        x.value == false
    ) {
        println("expected ${x.rhs}, got ${x.lhs}")
    }
}
```

### `toDefaultMessage`

```kotlin
public fun Explanation.toDefaultMessage(
    render: (Expression) -> String? /* = <default> */,
): String
```

The `render` lambda decides the label for each expression;
returning `null` presumably omits it (my reading, implied by
the `String?` return type and "literals excluded by
default"). The KEEP recommends that assertion libraries write
their own renderer, so they do not depend on compiler-plugin
releases for layout fixes and can match their house style.

```kotlin
val text = explanation.toDefaultMessage { x ->
    when (x) {
        is LiteralExpression -> null
        else -> x.value.toString()
    }
}
```

(The lambda body is my example; the KEEP only gives the
signature and that the parameter has a default.)

## Source text and offsets

This is the part people get wrong. There are two kinds of
offset.

- `Explanation.offset`: character offset of `source` **within
  the file**.
- `Expression.startOffset` (inclusive), `endOffset`
  (exclusive), `displayOffset`: offsets **within `source`**.

```kotlin
val text = e.source.substring(
    x.startOffset, x.endOffset,
)
// the source of one subexpression
```

`displayOffset` lies within `[startOffset, endOffset]` and is
where the diagram's `|` should point. For `mascot.name` it is
the `n` of `name`, not the `m` of `mascot`. For `a == b` it is
the first `=`.

### `source` is a block, not a line

`source` always contains the leading whitespace of the
original code, and anything outside the call's range (comments
before or after) is **replaced with spaces**. Given:

```kotlin
fun test() {
    /* leading comment */ powerAssert(
        mascot.name == "Kodee"
    ) // trailing comment
}
```

`source` is:

```text
                          powerAssert(
        mascot.name == "Kodee"
    )
```

Columns stay aligned with the file, so you can draw under any
line and call `trimIndent()` at the very end.

The four expressions and their offsets, as columns within
the `mascot.name` line (`s` start, `d` display, `e` end; the
real offsets also count the preceding line of `source`):

```text
        mascot.name == "Kodee"

mascot                  s=8   d=8   e=14
mascot.name             s=8   d=15  e=19
"Kodee"                 s=23  d=23  e=30
mascot.name == "Kodee"  s=8   d=20  e=30
```

(Redrawn from the KEEP's offset diagram as a table to fit
the page.)

Offsets are not stable across plugin versions. The *meaning*
is stable, the numbers may move to render better diagrams.
Never snapshot-test raw offsets.

## Typical usage

### A `kotlin.test`-style assertion, no config

```kotlin
data class Money(val cents: Long)
data class Order(val id: String, val total: Money)

@PowerAssert
fun assertValid(
    order: Order,
    @PowerAssert.Ignore message: String? = null,
) {
    if (order.total.cents <= 0) {
        val e = PowerAssert.explanation
        throw AssertionError(buildString {
            appendLine(message ?: "Invalid order")
            e?.let { append(it.toDefaultMessage()) }
        })
    }
}
```

Users just call it:

```kotlin
assertValid(repo.find("o-42"))
```

The diagram shows what `repo.find("o-42")` returned, without
the test author printing anything.

```text
Invalid order
assertValid(repo.find("o-42"))
            |    |
            |    Order(id=o-42, total=Money(cents=0))
            InMemoryRepo@1b6d3586
```

(Illustrative output, my reading of the default layout.)

### IntelliJ diff integration (KEEP example)

The KEEP's first use case throws OpenTest4J errors built from
failed `EqualityExpression`s. Condensed:

```kotlin
@PowerAssert
fun powerAssert(
    condition: Boolean,
    @PowerAssert.Ignore message: String? = null,
) {
    contract { returns() implies condition }
    if (condition) return

    val e = PowerAssert.explanation
        ?: throw AssertionFailedError(message)

    val failed = e.expressions
        .filterIsInstance<EqualityExpression>()
        .filter { it.value == false }

    val text = buildString {
        // ZWSP: OpenTest4J trims messages
        appendLine(
            message?.takeIf { it.isNotBlank() }
                ?: "​"
        )
        append(e.toDefaultMessage())
        append("​")
    }

    throw when (failed.size) {
        0 -> AssertionFailedError(text)
        1 -> AssertionFailedError(
            text, failed[0].rhs, failed[0].lhs,
        )
        else -> MultipleFailuresError(
            text, failed.map { EqualityError(it) },
        )
    }
}

private class EqualityError(
    x: EqualityExpression,
) : AssertionFailedError(
    "Expected <${x.rhs}>, actual <${x.lhs}>",
    x.rhs, x.lhs,
) {
    override fun fillInStackTrace() = this
}
```

Points worth teaching:

- `contract { returns() implies condition }` still works, so
  `powerAssert(x is User)` smart-casts `x` afterwards.
- The convention is `rhs` = expected, `lhs` = actual.
- One failed `==` gives a diff link; several give one per
  failure via `MultipleFailuresError`.

Output from the KEEP:

```text
powerAssert(mascot is Int)
            |      |
            Kodee  false


powerAssert(mascot == "Kodee" && mascot == "Duke")
            |      |             |      |
            |      true          |      false
            "Kodee"              "Kodee"

Expected :Duke
Actual   :Kodee
<Click to see difference>
```

And with two failed equalities:

```text
powerAssert(mascot == "Duke" || mascot == "Ferris")
            |      |            |      |
            |      false        |      false
            "Kodee"             "Kodee"

Expected <Duke>, actual <Kodee>
Expected :Duke
Actual   :Kodee
<Click to see difference>

Expected <Ferris>, actual <Kodee>
Expected :Ferris
Actual   :Kodee
<Click to see difference>
```

### Soft and fluent assertions (KEEP example)

Each `@PowerAssert` call gets its own explanation. A fluent
DSL can merge several into one diagram. The scope type is
marked `@PowerAssert.Ignore` on the **class**, so every
parameter or receiver of that type is skipped automatically.

```kotlin
@PowerAssert.Ignore
interface AssertScope<out T> {
    val subject: T
    fun collectFailure(
        message: String?,
        explanation: Explanation?,
    )
}

@PowerAssert
fun AssertScope<String>.hasLength(length: Int) {
    if (subject.length != length) collectFailure(
        "\"$subject\" does not have length $length",
        PowerAssert.explanation,
    )
}
```

The outer `assertThat` re-bases nested expressions onto its
own `source` and wraps them into a synthetic argument:

```kotlin
@PowerAssert
fun <T> assertThat(
    subject: T,
    block: AssertScope<T>.() -> Unit,
) {
    val primary = PowerAssert.explanation
        ?: error("power-assert plugin is required")
    val failures =
        mutableListOf<Pair<String?, List<Expression>>>()
    val scope = object : AssertScope<T> {
        override val subject: T get() = subject
        override fun collectFailure(
            message: String?,
            explanation: Explanation?,
        ) {
            val delta = (explanation?.offset ?: 0) -
                primary.offset
            val moved = explanation?.expressions
                ?.map { it.copy(delta) }.orEmpty()
            failures.add(message to moved)
        }
    }
    scope.block()
    if (failures.isEmpty()) return
    val synthetic = Argument(
        -1, -1, Argument.Kind.VALUE,
        failures.flatMap { it.second },
    )
    val combined = CallExplanation(
        primary.offset, primary.source,
        primary.arguments + synthetic,
    )
    throw AssertionError(combined.toDefaultMessage())
}
```

(Condensed. The KEEP's version also de-duplicates
expressions by source text and value and lists the failure
messages. Note `Expression.copy(delta)` is used by the KEEP
example but is not listed in its API overview; check the
runtime sources for its exact shape.)

Usage and output, from the KEEP:

```kotlin
val subject = "Unknown"
assertThat(subject) {
    hasLength("Kodee".length)
    startsWith("Kodee".substring(0, 1))
}
```

```text
Assertion failed:
 * String "Unknown" does not have length '5'.
 * String "Unknown" does not start with "K".
assertThat(subject) {
           |
           "Unknown"

    hasLength("Kodee".length)
                      |
                      5

    startsWith("Kodee".substring(0, 1))
                       |
                       "K"

}
```

Why this works: the nested calls are inside the lambda, so
they lie inside the outer call's `source` block. Their
explanations have a larger file `offset`; subtracting the
outer one maps them into the outer coordinate system.

### Not just assertions: a pretty-printer (KEEP example)

`@PowerAssert` is not tied to failure. The KEEP builds a
`pprintln` that annotates string-template holes with values.

```kotlin
fun main() {
    val name = "World"
    pprintln("""
        Hello, $name!
        My name is ${Random.nextInt()}.
    """.trimIndent())
}
```

```text
pprintln("""
    Hello, ${name = World}!
    My name is ${Random.nextInt() = -780043044}.
""".trimIndent())
```

The implementation inspects the character before each
expression in `source`: `$` means a simple template hole,
`{`/`}` around it means a block hole.

```kotlin
val prefix = source.getOrNull(x.startOffset - 1)
val suffix = source.getOrNull(x.endOffset)
if (prefix == '$') { /* wrap in ${... = v} */ }
```

### The library-author recipe

```kotlin
// 1. Annotate the assertion entry point.
@PowerAssert
fun assertSorted(
    items: List<Int>,
    // 2. Ignore what you never render.
    @PowerAssert.Ignore message: String? = null,
) {
    if (items == items.sorted()) return
    // 3. Read once, always handle null.
    val e = PowerAssert.explanation
    // 4. Render your own way.
    throw AssertionError(
        e?.toDefaultMessage() ?: message
    )
}
```

## Rules and edge cases

### Where `PowerAssert.explanation` may be read

Only inside a function annotated `@PowerAssert`. The plugin
enforces this at compile time.

```kotlin
fun helper() {
    val e = PowerAssert.explanation
    // ERROR: only allowed in @PowerAssert functions
}
```

(The KEEP states the restriction; it does not give the
diagnostic text. The comment above paraphrases.)

Without the plugin applied to the declaring module, reading
the property is a **runtime** error, not a compile error. The
intrinsic has no real implementation.

```kotlin
// module compiled WITHOUT the plugin
@PowerAssert
fun check(ok: Boolean) {
    PowerAssert.explanation
    // compiles, but throws at runtime
}
```

Corollary: a library that ships `@PowerAssert` functions must
apply the plugin to its own `main` source set. The plugin is
not enabled for `main` source sets by default (see the
security section), so the library author has to opt in (my
reading). The KEEP's
Beta setup does it like this:

```kotlin
powerAssert {
    includedSourceSets = provider {
        kotlin.sourceSets.map { it.name }
    }
}
```

### The declaration transformation

For each `@PowerAssert` function, the plugin generates a
synthetic copy with an extra `() -> CallExplanation`
parameter, and rewrites `PowerAssert.explanation` in both.

```kotlin
// what you write
@PowerAssert
fun powerAssert(condition: Boolean) {
    val explanation = PowerAssert.explanation
}
```

```kotlin
// what the plugin produces (conceptually)
@PowerAssert
fun powerAssert(condition: Boolean) {
    val explanation = null
}

@JvmSynthetic
fun `powerAssert$powerassert`(
    condition: Boolean,
    `$explanation`: () -> CallExplanation,
) {
    val explanation = `$explanation`.invoke()
}
```

Details from the KEEP:

- the copy loses `@PowerAssert`,
- gains `@JvmSynthetic`,
- copies every other annotation from the original.

This explains every `null` case: anything that reaches the
*original* function (Java, reflection, a callable reference,
a call site compiled without the plugin) gets `null` baked in.

### The call-site transformation

A call to an annotated function becomes a call to the copy:

```kotlin
powerAssert(mascot.name == "Kodee")
```

```kotlin
val tmp1 = mascot
val tmp2 = tmp1.name
val tmp3 = "Kodee"
val tmp4 = tmp2 == tmp3
`powerAssert$powerassert`(
    tmp4, { CallExplanation(...) },
)
```

Note: literals now get a temporary too (`tmp3`), unlike the
old string transformation. That is what gives a
`LiteralExpression` entry.

### Argument order is fixed

`arguments` is always in **parameter** order, grouped in
`Kind` enum order: dispatch, context, extension, value.

```kotlin
class Dispatch {
    context(c1: Context1, c2: Context2)
    fun Extension.example(p1: Param1, p2: Param2)
}
```

Any call yields six slots: `DISPATCH`, `CONTEXT` (c1),
`CONTEXT` (c2), `EXTENSION`, `VALUE` (p1), `VALUE` (p2).
Named arguments do not change that.

```kotlin
@PowerAssert
fun assertBetween(
    value: Int, min: Int, max: Int,
)

assertBetween(max = 10, min = 1, value = temp)
// arguments[0] -> value  (temp)
// arguments[1] -> min    (1)
// arguments[2] -> max    (10)
```

Meanwhile `expressions` re-sorts by `startOffset`, so it
follows the text: `max`'s literal first (my reading of the
`sortedBy` getter).

### When an argument slot is `null`

The slot is `null` when the argument was:

- omitted, using a default value,
- implicit, as context arguments usually are,
- on a parameter marked `@PowerAssert.Ignore`,
- of a type whose class is marked `@PowerAssert.Ignore`.

```kotlin
@PowerAssert
fun assertTemp(
    t: Temperature,
    unit: String = "C",
)

assertTemp(reading)
// arguments[0] -> Argument(VALUE, ...)
// arguments[1] -> null   (default used)
```

Index by parameter position and null-check; do not assume
`arguments.size` equals the number of non-null entries.

### Context parameters

```kotlin
@PowerAssert
context(clock: Clock)
fun assertNotExpired(token: Token) { /* ... */ }

with(systemClock) {
    assertNotExpired(session.token)
}
// arguments[0] -> null   (CONTEXT, implicit)
// arguments[1] -> VALUE: session, session.token
```

If you pass a context argument explicitly in a form the
language allows, you would get a populated `CONTEXT` slot
(my reading; the KEEP only says implicit ones are `null`).

### `@PowerAssert.Ignore` on a class

```kotlin
@PowerAssert.Ignore
class TestContext

@PowerAssert
fun TestContext.assertOk(response: HttpResponse)

ctx.assertOk(client.get("/health"))
// EXTENSION slot -> null (class is ignored)
// VALUE slot     -> client, client.get(...)
```

This is how the fluent example keeps `AssertScope` receivers
out of every diagram.

### Inheritance

Put the annotation on the **base** declaration. Overrides
inherit it; repeating it is allowed but not required.

```kotlin
interface Matcher<T> {
    @PowerAssert
    fun assertMatches(actual: T)
}

class EmailMatcher : Matcher<String> {
    override fun assertMatches(actual: String) {
        // still a @PowerAssert function:
        val e = PowerAssert.explanation
    }
}
```

The KEEP does not say what happens if you annotate only an
override (open, my reading: it is not the "base function
declaration", so treat it as unsupported).

### `expect` / `actual`

The annotation must be on **both** declarations.

```kotlin
// commonMain
@PowerAssert
expect fun assertOnMainThread(cond: Boolean)

// jvmMain
@PowerAssert
actual fun assertOnMainThread(cond: Boolean) {
    // ...
}
```

The KEEP does not specify the diagnostic if one side lacks it.

### Defaults, `inline`, `suspend`

All three work with no special handling, per the KEEP.

```kotlin
@PowerAssert
suspend fun eventually(
    @PowerAssert.Ignore timeoutMs: Long = 1_000,
    check: suspend () -> Boolean,
) { /* retry, then read explanation */ }

@PowerAssert
inline fun assertAll(cond: Boolean) { /* ... */ }
```

### Other compiler plugins

Behaviour with other plugins is "not well-defined". The KEEP
singles out Compose: `@Composable` plus `@PowerAssert` might
work if both plugins run in the same order at declaration and
call site, but it breaks Compose's guarantees by handing the
function non-parameter expressions. Strongly discouraged.

```kotlin
@Composable
@PowerAssert // discouraged by the KEEP
fun AssertVisible(cond: Boolean) { }
```

Same rule for any plugin: do not stack behaviours on one
function.

### Evaluation order and short-circuiting

Expressions are recorded in evaluation order. The
transformation evaluates each subexpression **once**, stores
it in a temporary, then reuses the temporary (visible in the
lowered code above). So Power-Assert does not re-run your
code to render a diagram.

```kotlin
var calls = 0
fun next(): Int = ++calls

powerAssert(next() == 2)
// next() runs once; diagram shows 1
// calls == 1 afterwards
```

(The `calls == 1` claim is my reading of the temporaries
model.)

Short-circuit operators keep their semantics. In the KEEP's
`&&` example both sides ran because the left was `true`. If
the left side of `&&` is `false`, the right side never runs,
and there is nothing to record for it (my reading; the KEEP
does not show this case).

```kotlin
powerAssert(user != null && user.isAdmin)
// user == null:
//   user.isAdmin is never evaluated,
//   so no Expression for it (my reading)
```

### Side effects and mutable values

`Expression.value` is the object reference captured at
evaluation time, typed `Any?`. Nothing in the KEEP says
values are copied or stringified eagerly. So if a mutable
object changes between evaluation and rendering, the diagram
shows the *later* state (my reading).

```kotlin
val cart = mutableListOf("apple")

@PowerAssert
fun assertEmptyThenClear(
    items: MutableList<String>,
) {
    val empty = items.isEmpty()
    items.clear()          // side effect first
    if (!empty) throw AssertionError(
        PowerAssert.explanation?.toDefaultMessage()
    )
}

assertEmptyThenClear(cart)
// diagram shows: cart -> []  (my reading)
```

Rule for library authors: read and render the explanation
before you mutate anything you were handed.

Also, `toString()` of each value runs during rendering, inside
your assertion. A throwing or slow `toString()` now affects
failure reporting (my reading).

### Performance

Where the cost goes:

- **Every call, pass or fail:** the temporaries. Each
  subexpression is stored in a local. That is cheap but not
  free, and it changes the bytecode shape of every call site.
- **Every call:** allocating the
  `{ CallExplanation(...) }` lambda (my reading; it captures
  the temporaries).
- **Only when read:** constructing `CallExplanation`. The
  synthetic parameter is `() -> CallExplanation`, so nothing
  is built until you call `PowerAssert.explanation`.
- **Only when rendered:** `toDefaultMessage()` and the
  `toString()` calls.

So read `PowerAssert.explanation` only on the failure path:

```kotlin
@PowerAssert
fun assertFast(ok: Boolean) {
    if (ok) return               // nothing built
    val e = PowerAssert.explanation  // built here
    throw AssertionError(e?.toDefaultMessage())
}
```

`@PowerAssert.Ignore` is the main knob: ignored arguments get
no temporaries at all, which "potentially" saves compile time
and runtime overhead. Ignore lambdas, scopes, configuration
objects and messages you never render.

```kotlin
@PowerAssert
fun assertResponse(
    response: HttpResponse,
    @PowerAssert.Ignore
    config: AssertConfig = AssertConfig(),
)
```

Related: [KEEP-0465](https://github.com/Kotlin/KEEP/blob/main/proposals/stdlib/KEEP-0465-kotlin.test-lazy-assertion-messages.md)
(Experimental in 2.4.20) adds `kotlin.test` overloads with a
lazy `() -> String` message, motivated partly by the cost of
Power-Assert messages. It is the string path; KEEP-0458 is the
structured path.

```kotlin
// KEEP-0465 shape, @ExperimentalKotlinTestApi
assertTrue(order.isPaid) { "unpaid: $order" }
```

### Three transformations, one plugin

| Target | Plugin generates |
|---|---|
| `@PowerAssert` function | `CallExplanation` lambda |
| FQ-named, runtime present | `CallExplanation(...)` `.toDefaultMessage()` |
| FQ-named, no runtime | compile-time `String` |

The middle row is a free upgrade for existing users: an old
`assertEquals` configured by name now gets a runtime-laid-out
diagram, which can adapt to the actual values.

```kotlin
// FQ-named target + runtime on classpath
assert(cond, {
    CallExplanation(...).toDefaultMessage()
})
```

(The KEEP's listing passes `tmp3` here; with four temporaries
the condition should be `tmp4`. Looks like a typo.)

### Security

The called function sees source text and values the caller
never passed explicitly: every subexpression of every
argument. A malicious or careless library could log them.

```kotlin
assertValid(login(user, password = secret))
// the library receives `secret`'s value
// as an Expression in the explanation
```

The KEEP's mitigations: the plugin must be applied explicitly,
and it is not enabled for `main` source sets by default.
Its advice: know which call sites are transformed, and
re-check when a library upgrade adds `@PowerAssert` to more
functions. Making transformation visible at call sites is
"being worked on", nothing to share.

## Platform interop

### Java callers

Java sees the original function and `PowerAssert`'s
`@JvmStatic` getter. The synthetic copy is `@JvmSynthetic`, so
Java source cannot call it.

```java
// Java
Assertions.powerAssert(order.isPaid(), null);
// runs the original: explanation == null
// -> your fallback message
```

```java
// The intrinsic, via @JvmStatic
CallExplanation e = PowerAssert.getExplanation();
// only meaningful inside a transformed body;
// without the plugin it fails at runtime
```

### JVM binary shape

Per annotated function, two methods (my naming from the KEEP's
listing):

```text
powerAssert(Z)V                          original
powerAssert$powerassert(ZLkotlin/...)V   synthetic
```

(The descriptor is my illustration: `Z` is the Boolean, the
second parameter is the `Function0` returning
`CallExplanation`.)

ABI consequences (my reading):

- Removing `@PowerAssert` from a published function removes
  the synthetic method; already-compiled callers that target
  it break at link time. Treat adding or removing it as an ABI
  change.
- Adding `@PowerAssert` is safe for old callers; they keep
  calling the original and get `null`.

### Runtime dependency

The KEEP says the Gradle plugin *will* add
`power-assert-runtime` as an `implementation` dependency to
every source set where Power-Assert is enabled, tracked as
[KT-85250](https://youtrack.jetbrains.com/issue/KT-85250).
For 2.4.0-Beta2 it is "not yet supported", so add it by hand.

A library that does not want to leak the runtime
transitively:

```kotlin
plugins {
    kotlin("jvm") version "2.4.0-Beta2"
    kotlin("plugin.power-assert") version "2.4.0-Beta2"
}

dependencies {
    compileOnly(kotlin("power-assert-runtime"))
}

powerAssert {
    addRuntimeDependency = false
}
```

The trap: the body's `PowerAssert.explanation` becomes
`null`, but references to `CallExplanation` and friends stay
in the bytecode. Without the runtime at run time you get
`NoClassDefFoundError` on the JVM, or link errors on other
targets.

```kotlin
@PowerAssert
fun check(ok: Boolean) {
    if (!ok) {
        val e = PowerAssert.explanation
        // e is a CallExplanation? local:
        // the class must exist at runtime
    }
}
```

### Multiplatform

- The runtime library's sources live under `commonMain` in
  the Kotlin repo (the KEEP's API link points there), so the
  model is common code.
- `expect`/`actual`: annotate both sides.
- `@JvmStatic`/`@JvmSynthetic` are JVM-only details; the
  KEEP does not describe the generated names on JS, Native or
  Wasm.
- Missing runtime: `NoClassDefFoundError` on JVM, "errors at
  runtime or during linking" elsewhere.

```kotlin
// commonTest: works on every target
// that has the plugin + runtime
@Test
fun total() {
    powerAssert(cart.total() == Money(1_000))
}
```

The KEEP's Gradle snippets only show `kotlin("jvm")`. For
KMP, `includedSourceSets` takes source set names, which is
how you would pick `commonTest` and friends (my reading).

### Reflection and callable references

```kotlin
val f = ::powerAssert
f(false, null)
// goes to the original -> explanation == null

// Reflection (KFunction.call, Method.invoke)
// also reaches the original -> null
```

## Design decisions

### Annotation discovery instead of configuration

The old model put knowledge in the build of every consumer.
The new model puts it in the library binary with `BINARY`
retention. One library release, every user benefits.

```kotlin
// before: each consumer
powerAssert { /* list FQ names */ }

// after: once, in the library
@PowerAssert fun assertThat(/* ... */)
```

### An intrinsic, not a parameter

A parameter would be the old convention again. The intrinsic
keeps the public signature clean, lets the plugin add the
real parameter only on the synthetic copy, and gives a clean
`null` story for non-plugin callers.

```kotlin
// rejected shape (my framing)
fun assertThat(x: Any?, e: CallExplanation? = null)
// pollutes the API, callable by hand,
// Java sees it
```

### A list of expressions, not a tree

The KEEP's reasoning:

- A list is a far simpler data structure. A tree forces many
  design choices about how each expression kind is shaped.
- The plugin already produces a list of temporaries. A tree
  would mean rewriting much of the plugin.
- Not a dead end: a future tree can keep the list properties
  as a DFS walk, without breaking code.

```kotlin
// `1 + 2 + 3` is flat:
// [1, 2, 3(=1+2), 3, 6]
// not Plus(Plus(1, 2), 3)
```

### Few `Expression` subclasses

`LiteralExpression` exists so an explanation can always be
complete while the default diagram hides noise.
`EqualityExpression` exists for IntelliJ's diff. More may
come; the KEEP floats a `StringTemplateExpression`.

```kotlin
when (x) {
    is EqualityExpression -> diff(x.lhs, x.rhs)
    is LiteralExpression -> Unit
    else -> label(x.value)
}
```

### The `Explanation` base class

Room for other explanation kinds, notably local variables:
explain a `val`'s initializer and send it along with the call.
The KEEP lists three concerns: more data leaks (security),
more transformation cost even if unused (performance), and
who decides which locals are explained (syntax).

```kotlin
val expected = Money(1_000)    // explain this too?
powerAssert(total == expected) // future idea only
```

### Keeping the string path

Removing string-message support was a non-goal. Instead it
got better: runtime layout through `toDefaultMessage()` when
the runtime is present, the old compile-time string when not.

### Comparison

The KEEP does not compare with other languages. (Groovy and
Spock popularised power asserts; that is general knowledge,
not KEEP content.)

## Open questions and what may change

- **API stability.** Unstable overall. "Stable for use,
  unstable for implementation." New use cases mostly arrive as
  new `Explanation`/`Expression` subclasses, so exhaustive
  `when` over them will break.
- **Offsets.** Values may change between plugin versions.
- **Automatic runtime dependency.** Promised, tracked by
  KT-85250, not in 2.4.0-Beta2.
- **Pre-2.4.0 changes.** The KEEP warns that things may change
  before the final release.
- **Call-site visibility.** Making transformed calls obvious
  in source or IDE: work in progress, nothing concrete.
- **Local variable explanations.** Explored, not decided.
- **Tree representation.** Possible later.
- **New features.** The authors ask for use cases, not API
  wish lists, via the
  [discussion](https://github.com/Kotlin/KEEP/discussions/478)
  and `#power-assert` on Kotlin Slack.

```kotlin
// Future-proof rendering: always keep an else
when (x) {
    is EqualityExpression -> /* ... */ Unit
    else -> /* unknown subclass */ Unit
}
```

Ambiguities found in the KEEP text itself:

- The string-call listing passes `tmp3` instead of `tmp4`.
- The fluent example calls `Expression.copy(Int)`, which is
  not in the API overview.
- "Will automatically be added" versus "not yet supported"
  for the runtime dependency: the first is the plan, the
  second the Beta2 state.

## Cheat sheet

```kotlin
@PowerAssert
fun assertThat(
    cond: Boolean,
    @PowerAssert.Ignore msg: String? = null,
) {
    if (cond) return
    val e = PowerAssert.explanation
        ?: throw AssertionError(msg)
    for (x in e.expressions) {
        if (x is EqualityExpression &&
            x.value == false) {
            /* x.lhs actual, x.rhs expected */
        }
    }
    throw AssertionError(e.toDefaultMessage())
}
```

- `@PowerAssert` (BINARY): call sites auto-transformed, no
  FQ-name config.
- `PowerAssert.explanation`: intrinsic, `CallExplanation?`,
  only inside `@PowerAssert` functions.
- `null` for: no plugin at call site, Java, reflection,
  callable references.
- `CallExplanation`: `offset`, `source`, `arguments`
  (parameter order, nullable), `expressions` (source order).
- `Argument.Kind`: DISPATCH, CONTEXT, EXTENSION, VALUE.
- `Expression`: `startOffset`, `endOffset`, `displayOffset`,
  `value`. Subclasses: Value, Literal, Equality.
- `@PowerAssert.Ignore` on a parameter or a class: slot is
  `null`, no temporaries.
- Plugin generates `name$powerassert` copy, `@JvmSynthetic`,
  extra `() -> CallExplanation`.
- Overrides inherit; `expect`/`actual` need both; avoid with
  `@Composable`.
- Runtime: `kotlin("power-assert-runtime")`; opt out with
  `addRuntimeDependency = false`.
- Status: prototype in 2.4.0-Beta2, API unstable.

## Talking points

- "Power-Assert used to hand you a string. Now it hands you
  the call site as data."
- "Library authors add one annotation; users stop configuring
  function names in Gradle."
- "Your assertion function no longer needs a message
  parameter at the end to get a diagram."
- "Failed `==` comes with both sides as objects, so IntelliJ's
  diff link just works."
- "Arguments come in parameter order, expressions in source
  order, every value in evaluation order."
- "Nothing is re-evaluated. Values are captured once into
  temporaries."
- "Even if your library never adopts it, existing
  `assert` diagrams get a runtime layout once the runtime
  library is present."
- "It is a prototype in 2.4.0-Beta2 and the API is
  unstable. Play with it, file use cases."

```kotlin
powerAssert(order.total == expected)
```

**Q: Isn't this a macro system in disguise?**
No, explicitly a non-goal. You get source text, offsets and
recorded values. You cannot change, re-run or generate code.

**Q: What if Java or a method reference calls my function?**
It hits the original, non-synthetic function, where the
plugin replaced `PowerAssert.explanation` with `null`. Always
write a fallback.

**Q: Can a test library now see my secrets?**
It can see every subexpression of the arguments you pass to a
`@PowerAssert` function, including values you did not intend
to show. The plugin is opt-in and off for `main` source sets
by default, but you should know which calls are transformed
and re-check on library upgrades.

```kotlin
// review: what does this call expose?
assertValid(login(user, password = secret))
```
