---
title: "Collection Literals"
subtitle: "[1, 2, 3] is sugar for Type.of(1, 2, 3), and the expected type picks Type"
author: "Notes from KEEP-0416"
date: "October 2026"
lang: en
---

## At a glance

| Item | Value |
|---|---|
| KEEP | [KEEP-0416](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0416-collection-literals.md) |
| Status | Experimental since Kotlin 2.4.0 |
| YouTrack | KT-43871 |
| Discussion | KEEP discussion #496 |
| Author | Nikita Bobko |

The KEEP itself does not name the compiler flag. This project's
`build.gradle.kts` enables it with `-Xcollection-literals`, and every
"observed" snippet in this article was compiled with Kotlin 2.4.20 and
that flag. Where I say "observed", the behaviour comes from running the
2.4.20 compiler, not from the KEEP text.

Related: the long-term stdlib shape depends on
[companion blocks](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0449-companions-block-extension.md)
(KEEP-0449, a separate experimental feature).

```kotlin
val ports = [8080, 8443]          // List<Int>
val roles: Set<String> = ["admin", "dev"]
val ids: IntArray = [1, 2, 3]
val tags: Tags = ["kotlin", "jvm"] // Tags.of(...)
val empty: MutableList<String> = []
```

The whole feature in one sentence: square brackets desugar to a call
to `operator fun of` on the expected type, and fall back to `List` when
there is no useful expected type.

## The problem

Kotlin has always had a family of `xxxOf` functions instead of
literals. They work, but the KEEP lists five concrete annoyances.

### Noise at the call site

```kotlin
// today
if (readlnOrNull() in listOf("y", "Y", "yes", null)) {
    confirm()
}

// with collection literals
if (readlnOrNull() in ["y", "Y", "yes", null]) {
    confirm()
}
```

### The listOf / emptyList dance

When a list shrinks to zero elements some people rewrite `listOf()`
to `emptyList()`, and back again when it grows. A literal has one
spelling for every size.

```kotlin
// today: two different functions
val none: List<String> = emptyList()
val some: List<String> = listOf("admin")

// with literals: one syntax
val none2: List<String> = []
val some2: List<String> = ["admin"]
```

### Ambiguous intent

The KEEP points out that `listOf(10)` can be misread as "a list with
capacity 10". `[10]` cannot.

### Mutable collections need a different function

```kotlin
// today
val toVisit = mutableListOf<String>()
val visited = mutableSetOf<String>()

// with literals, the declared type drives it
val toVisit2: MutableList<String> = []
val visited2: MutableSet<String> = []
```

### Annotations already had them

Annotation arguments already accept `[...]` for arrays. The
same brackets were illegal in ordinary expressions. Collection
literals close that gap.

```kotlin
annotation class Retry(val codes: IntArray)

@Retry([502, 503]) // legal for years
fun fetch() = Unit

val codes = [502, 503] // legal only now
```

The KEEP is explicit about who benefits most: "The feature brings more
value to newcomers rather than to experienced Kotlin users and should
target the newcomers primarily." The value is aesthetics and
readability, which is why the KEEP leads with ten before/after pairs
from the Kotlin compiler codebase rather than with a benchmark.

## The feature, step by step

### Step 1: the default is List

With no expected type, a literal is a read-only `kotlin.List`.

```kotlin
val primes = [2, 3, 5, 7]   // List<Int>
val words = ["ktor", "exposed"] // List<String>
val maybe = ["a", null]     // List<String?>
```

In the current implementation this is literally `listOf(...)`.
Observed bytecode for `fun list() = [1, 2, 3]`:

```text
invokestatic CollectionsKt.listOf:([Ljava/lang/Object;)
```

Once companion blocks land and the stdlib adds `of` functions, the
fallback is expected to become `kotlin.collections.List.of(...)`.

### Step 2: the expected type picks the collection

Give the literal a type and it becomes that type.

```kotlin
val roles: Set<String> = ["admin", "admin", "dev"]
println(roles) // prints: [admin, dev]

val ids: IntArray = [1, 2, 3]
val names: Array<String> = ["Ada", "Grace"]
val queue: MutableList<Order> = []
```

Observed: `IntArray` literals compile to a plain `newarray int`, just
like `intArrayOf`; `Set` compiles to `setOf(...)`.

The expected type also flows into the elements, exactly as it does for
a `listOf` call with an explicit type argument:

```kotlin
val limits: List<Long> = [1, 2] // elements are Long
println(limits[0].javaClass) // prints: class java.lang.Long
```

### Step 3: what is an "expected type"?

The KEEP defines it as the type the "hole" accepts, as opposed to the
actual type of the expression in it:

```kotlin
val n: Number = 1  // actual Int, expected Number
val s: Short = 1   // expected type changes actual type
```

For collection literals, these positions have a *definite* expected
type, and the literal is desugared directly to `Type.of(...)`:

- explicit `return`, single-expression functions with a declared
  return type, and the last expression of a lambda
- assignments and initializations
- default values of function parameters
- delegate expressions in interface delegation

```kotlin
fun defaults(): Set<String> = ["read"]   // return

var current: Set<String> = ["read"]      // init
fun reset() { current = ["read", "write"] } // assign

fun grant(roles: Set<String> = ["read"]) = roles

class Readers : Collection<String> by ["ada", "bob"]
```

Argument positions are handled differently (they take part in
overload resolution, see Rules). Everything else falls back to `List`.

### Step 4: your own type opts in with `operator fun of`

A type supports literals when its *static scope* declares an
`operator fun of` with a `vararg` parameter.

```kotlin
class Tags private constructor(
    val items: List<String>,
) {
    companion object {
        operator fun of(vararg tags: String): Tags =
            Tags(tags.distinct())
    }
}

val t: Tags = ["kotlin", "jvm", "kotlin"]
// same as: Tags.of("kotlin", "jvm", "kotlin")
```

The KEEP defines static scope precisely: members of companion blocks,
members of `Type.Companion` when it is a companion object, or static
members if the type is declared in Java. Companion extensions and
extensions on `Type.Companion` are excluded on purpose.

Note what is *not* required: the type need not implement `Collection`
or `Iterable` (needed for `Array<T>`), and it need not be generic
(needed for `IntArray`).

### Step 5: companion blocks instead of companion objects

With companion blocks (KEEP-0449) the `of` becomes a real static
member, no `Companion` instance involved. Observed: this compiles in
2.4.20 with `-Xcompanion-blocks-and-extensions` as well.

```kotlin
class Path(val parts: List<String>) {
    companion {
        operator fun of(vararg parts: String): Path =
            Path(parts.toList())
    }
}

fun bin(): Path = ["usr", "local", "bin"]
```

Observed bytecode: `invokestatic Path.of:([Ljava/lang/String;)LPath;`
versus `invokevirtual Tags$Companion.of` for the companion-object
version.

### Step 6: fixed-arity overloads for speed

You may add `of` overloads that differ only in the number of
parameters, typically to return specialised instances for zero or one
element. The stdlib does exactly that with `listOf`.

```kotlin
class Row private constructor(val cells: List<String>) {
    companion object {
        operator fun of(): Row = Row(emptyList())
        operator fun of(cell: String): Row =
            Row(listOf(cell))
        operator fun of(vararg cells: String): Row =
            Row(cells.toList())
    }
}

val r0: Row = []           // of()
val r1: Row = ["id"]       // of(cell)
val r3: Row = ["a", "b", "c"] // of(vararg)
```

### Step 7: non-empty collections

Parameters in front of the `vararg` are allowed if they have the same
type. That gives you a compile-time non-empty literal.

```kotlin
class Nel<T>(val head: T, val tail: List<T>) {
    companion object {
        operator fun <T> of(head: T, vararg tail: T) =
            Nel(head, tail.toList())
    }
}

val ok: Nel<Int> = [1, 2, 3]
val bad: Nel<Int> = [] // ERROR: no value passed for 'head'
```

### Step 8: nesting

Literals nest, and each level gets its own expected type.

```kotlin
val grid: List<Set<Int>> = [[1, 1], [2]]
println(grid) // prints: [[1], [2]]

val matrix: Array<IntArray> = [
    [1, 0],
    [0, 1],
]
```

## Typical usage

### Configuration and CLI arguments

```kotlin
val compilerArgs = [
    "-no-reflect",
    "-d", outDir.absolutePathString(),
    "-module-name", moduleName,
]
```

The trailing comma is allowed, which keeps diffs small.

### Named arguments in DSL-style calls

```kotlin
fun server(
    port: Int,
    methods: Set<HttpMethod>,
    origins: List<String> = [],
) = Unit

server(
    port = 8080,
    methods = [HttpMethod.Get, HttpMethod.Post],
    origins = ["https://kotlinlang.org"],
)
```

The parameter type `Set<HttpMethod>` decides that the literal is a
`Set`; the caller never writes `setOf`.

### Domain types that validate

`of` is a constructor, so it can enforce invariants.

```kotlin
@JvmInline
value class Currencies private constructor(
    val codes: Set<String>,
) {
    companion object {
        operator fun of(vararg codes: String): Currencies {
            require(codes.all { it.length == 3 })
            return Currencies(codes.toSet())
        }
    }
}

val accepted: Currencies = ["EUR", "USD"]
```

### Building up state

```kotlin
class Cart {
    private val items: MutableList<Order> = []
    private val seen: MutableSet<String> = []

    fun add(order: Order) {
        if (seen.add(order.id)) items += order
    }
}
```

### Returning from functions and lambdas

```kotlin
override fun mimeTypes(): List<String> =
    ["text/x-kotlin"]

val defaultsFor: (User) -> Set<String> = { user ->
    if (user.isAdmin) ["read", "write"] else ["read"]
}
```

Observed: each branch of the `if` gets `Set<String>` as its expected
type and compiles to `setOf(...)`.

### Iteration and membership

```kotlin
for (key in [arg.value, arg.shortName]) {
    if (key.isNotEmpty()) register(key)
}

if (status in [301, 302, 307, 308]) followRedirect()
```

Both of these are fallback positions, so they create a `List`.

### Library authors: persistent / immutable collections

The KEEP explicitly cites kotlinx.collections.immutable and Guava as
reasons the syntax must be open. A library adds one operator and its
users get literals (my reading of how such a library would do it; the
KEEP does not show the declaration):

```kotlin
class PVector<T> private constructor(/* ... */) {
    companion object {
        operator fun <T> of(vararg xs: T): PVector<T> =
            TODO()
    }
}

val history: PVector<Event> = [Started, Paused]
```

## Rules and edge cases

### Declaration rules for `operator fun of`

The KEEP lists twelve restrictions. They exist for one reason: given
only the outer type (`List<T>`, `IntArray`, `Tags`), the compiler must
be able to compute the element type *without* running full overload
resolution on `of`. That is what lets literals participate in
resolution of the outer call.

**1. No extensions.** `of` must be a member of the companion object or
of a companion block.

```kotlin
class Money { companion object }
operator fun Money.Companion.of(
    vararg cents: Long,
) = Money()
// ERROR: 'operator' modifier is not applicable
// to function: must not have an extension receiver
```

The KEEP's argument: every other operator works on an existing value
of the type, while `of` *is* the constructor of the type. Allowing
extensions would mean imported `of`s could win when members are not
applicable, and the declaration-site checks below would become
impossible.

**2. Exactly one `vararg` overload**, its `vararg` is the last
parameter, and any parameters before it have the same type.

```kotlin
class Point { companion object {
    operator fun of(x: Int, y: Int): Point = Point()
    // ERROR: one of the overloads of operator 'of'
    // must have a single 'vararg' parameter
} }

class Csv { companion object {
    operator fun of(vararg x: Int): Csv = Csv()
    operator fun of(vararg x: String): Csv = Csv()
    // ERROR: only one overload of operator 'of'
    // is allowed to have 'vararg' parameters
} }
```

The `Point` case is why literals are not tuples: you cannot write a
type-safe "exactly two" literal.

**3. Return type must be the owning class** (by ClassId), and
**8. non-nullable**.

```kotlin
class Id { companion object {
    operator fun of(vararg x: Int): String = ""
    // ERROR: return type of 'operator of' must
    // match outer classifier 'Id'
} }

class Slot { companion object {
    operator fun of(vararg x: Int): Slot? = null
    // ERROR: return type of 'operator fun of'
    // cannot be nullable
} }
```

The compiler found `of` by looking at the expected type, so the result
had better be that type.

**4. All overloads have the same return type** (same type-parameter
constraints if generic). **6. Overloads differ only in arity.**

```kotlin
class Cells { companion object {
    operator fun of(vararg x: Int): Cells = Cells()
    operator fun of(x: String): Cells = Cells()
    // ERROR: parameter types in operator 'of' must
    // match the type of 'vararg' parameter
} }
```

The KEEP's motivating example: if a two-argument `of` returned
`MyList<String>` while the `vararg` one returned `MyList<Int>`, the
outer call would be resolved using the `vararg` signature and then
fail with a type mismatch after desugaring, while the hand-written
`MyList.of(1, 2)` would work. The literal and its desugaring must not
disagree.

**5. Same visibility for all overloads.**

```kotlin
class Batch { companion object {
    operator fun of(vararg x: Int): Batch = Batch()
    private operator fun of(x: Int): Batch = Batch()
    // ERROR: visibility of operator 'of' must be
    // the same for all overloads
} }
```

**7. No extension receivers, context parameters or receivers.**

```kotlin
class Ports { companion object {
    operator fun Int.of(vararg x: Int): Ports = Ports()
    // ERROR: must not have an extension receiver
} }
```

**9.** Not both a companion object and a companion block may declare
eligible `of`s for the same type. Otherwise a companion-block `vararg`
candidate would silently win.

**10. No default values.**

```kotlin
class Page { companion object {
    operator fun of(
        size: Int = 0,
        vararg x: Int,
    ): Page = Page()
    // ERROR: must not have parameters with
    // default values
} }
```

**11.** All overloads are `suspend` or none are.
**12.** No contracts.

### What is allowed

- `inline` with `reified` type parameters. This is how `Array<T>`
  itself can be expressed.
- `suspend`, `tailrec`, `infix` where normal modifier rules allow.

```kotlin
class Batch { companion object {
    suspend operator fun of(vararg ids: Int): Batch =
        Batch()
} }

fun plain() {
    val b: Batch = [1] // ERROR: suspend function
    // 'of' can only be called from a coroutine
}

suspend fun ok() {
    val b: Batch = [1] // fine
}
```

The KEEP's argument for `suspend`: the only operators that cannot be
`suspend` are the ones that represent properties (`getValue`,
`setValue`, `provideDelegate`). `of` is not a property.

### Fallback: when there is no eligible `of`

If the expected type is concrete and has no eligible `of`, the
compiler uses the `List` fallback, and then checks `List` against the
expected type as usual.

```kotlin
val a: Any = [1, 2]               // List<Int>
val b: Iterable<Int> = [1, 2]     // List<Int>
val c: Collection<Int> = [1, 2]   // List<Int>

class Invoice
val d: Invoice = [1, 2]
// ERROR: expected type 'Invoice' for collection
// literal does not define operator 'of' and is
// not a supertype of 'List'
```

That error message is observed in 2.4.20 and is worth memorising: it
is the one people will hit most often.

### No mutable fallback

There is no `of` on `MutableCollection` or `MutableIterable`, and
`List` is not a subtype of them, so this fails by design:

```kotlin
val bag: MutableCollection<String> = [""]
// ERROR: ... does not define operator 'of' and
// is not a supertype of 'List'
```

Observed: the same happens for concrete JDK types like
`ArrayList<Int>`, `HashSet<Int>` and `EnumSet<DayOfWeek>`, because
they have no Kotlin `of` operator and Java statics are not considered
yet (see Platform interop).

```kotlin
val al: ArrayList<Int> = [1] // ERROR
val hs: HashSet<Int> = [1]   // ERROR
```

### The empty literal

```kotlin
val nothing = []
// ERROR: cannot infer type for type parameter 'T'

val users: List<User> = [] // fine
```

The KEEP compares this to `emptyList()`, which returns `List<T>`, not
`List<Nothing>`. Without an expected type there is no `T`, and the
compiler asks you for one.

### Overload resolution: what works

A literal in argument position behaves like a lambda or a callable
reference: its own typing is postponed, but its elements are analysed
and contribute constraints to every candidate of the outer call.

For each candidate whose parameter type is a fixed type:

1. Expand the literal to a notional `ParamType.of(...)`.
2. Pick the `of` overload by argument count only.
3. Record the `vararg` element type (the KEEP calls it CLET) and the
   return type (CLT).
4. Add constraints `type(e) <: CLET` for each element and
   `CLT <: ParamType`.

Candidates whose constraint system becomes unsound are filtered out.
That is why "inner type" overloads work:

```kotlin
@JvmName("flushPaths")
fun flush(files: List<String>) = println("paths")
@JvmName("flushFiles")
fun flush(files: List<File>) = println("files")

flush(["a.txt", "b.txt"]) // prints: paths
```

And "both differ" overloads work too, including when one side only
has the `List` fallback:

```kotlin
fun audit(ids: Set<String>) = println("set")
fun audit(ids: Iterable<Int>) = println("iterable")

audit([42]) // prints: iterable
```

`Set<String>` has an `of` but `42` is not a `String`, so it is
filtered out. `Iterable` has no `of`, so it uses the `List`
fallback, and `List<Int> <: Iterable<Int>` holds.

`println` is another fallback case:

```kotlin
println([1, 2]) // println(Any?) with List<Int>
```

### Overload resolution: what does not work

**List vs Set (outer-type) overloads are ambiguous.**

```kotlin
fun index(ids: List<Int>) = Unit
fun index(ids: Set<Int>) = Unit

index([1]) // ERROR: overload resolution ambiguity
```

The KEEP's reasoning: such pairs usually consist of a "main" overload
and a convenience overload that delegates to it, and the compiler
cannot know which is the main one. The syntax also has no way to say
"I meant Set". Write `index(setOf(1))` or `index(listOf(1))`.

**Iterable vs Sequence vs Array is ambiguous**, which is the case
people will actually hit, because the stdlib `plus` has all three:

```kotlin
val optIns = listOf("ExperimentalTime")
val all = optIns + ["ExperimentalUnsignedTypes"]
// ERROR: overload resolution ambiguity
//   Iterable<T>.plus(element: T)
//   Iterable<T>.plus(elements: Array<out T>)
//   Iterable<T>.plus(elements: Iterable<T>)
//   Iterable<T>.plus(elements: Sequence<T>)
//   ... and the Collection<T> variants
```

This is intentional for the first version. A hard-coded preference
between `Array`, `Iterable` and `Sequence` would be observable in
resolution and hard to evolve. The KEEP lists four possible future
directions: a general priority among literal target shapes, extending
the fallback so an ambiguous literal becomes `List` (effectively
preferring `Iterable`), an explicitly-typed literal syntax, and
targeted annotations for preferred overloads.

**Generic parameters postpone the literal.** If the parameter type is
an unfixed type variable, the literal adds no constraints during
filtering, so its elements cannot disambiguate.

```kotlin
@JvmName("gs")
fun <T : List<String>> validate(value: T) = Unit
@JvmName("gi")
fun <T : List<Int>> validate(value: T) = Unit

validate([1]) // ERROR: overload resolution ambiguity

fun <T> id(value: T): T = value
@JvmName("ds") fun direct(v: List<String>) = Unit
@JvmName("di") fun direct(v: List<Int>) = Unit

direct([1])     // resolves to List<Int>
direct(id([1])) // ERROR: ambiguity, id postpones
```

**Locality still wins.** The KEEP rejected a proposal to only refine
candidates on the nearest scope level. As with callable references,
resolution may pick a farther-away function if the closer one is not
applicable:

```kotlin
fun log(lines: List<Int>) {}        // top level
class Logger {
    fun log(lines: List<String>) {} // member
    fun test() {
        log([1]) // resolves to the top-level one
    }
}
```

The KEEP chose consistency with callable references over "fixing"
this.

### Completing postponed literals

Once the outer call is chosen, a postponed literal picks a
"representative" from the lower and upper constraints on its type
variable: the types that have an `of`.

- exactly one candidate: use it
- none: use the `List` fallback
- two or more: error

```kotlin
fun <T> id(value: T): T = value
fun <T> pick(vararg xs: T): T = xs[0]

val s: Set<Int> = id([1, 2, 2])
println(s) // prints: [1, 2]

val i: Iterable<Int> = id([1, 2]) // List fallback

val c: Collection<Int> =
    pick(setOf(1), listOf(2), [3])
// ERROR: type of collection literal is ambiguous.
// Multiple candidates declare operator 'of':
// Set, List
```

The fallback is deliberately *not* applied eagerly when the expected
type is a type variable. The KEEP's example shows why:

```kotlin
open class Ids { companion object {
    operator fun <T> of(vararg xs: T): Ids = TODO()
} }

fun <T : Ids> store(ids: T) = Unit

store([1]) // green: completes to Ids
```

An eager `List` fallback here would lose the `Ids` bound that only
becomes visible during completion.

The KEEP flags this whole postponed-literal procedure as experimental:
inference and resolution may change.

### Lambdas and inference through generic calls

```kotlin
fun <T> compute(block: () -> T): T = block()

val roles: Set<String> = compute { ["admin"] }
// completed as Set<String>
```

The KEEP's own example 8 (an Elvis inside `apply` inside a
`compute` lambda) works in the implementation, but the KEEP says this
inference path "is not a stable part of the proposal yet":

```kotlin
fun <D> MutableMap<String, MutableSet<D>>.addTo(
    key: String,
    value: D,
) {
    compute(key) { _, old ->
        (old ?: []).apply { add(value) }
    }
}
```

The interaction with eager lambda analysis "needs a separate design
pass" and is not specified.

### Elements inside a literal

When a literal is an argument, its elements are analysed like other
arguments of the outer call:

- lambda elements are postponed; only their parameter count and
  declared parameter types count for resolution
- callable references are resolved eagerly enough to contribute
  constraints
- nested literals are descended into recursively
- everything else is analysed in "dependent mode"

```kotlin
val handlers: List<(Request) -> Response> = [
    { req -> ok(req) },
    ::notFound,
]
```

For nested literals, the outer `of` overload is chosen first (by
count), and only then are inner literals expanded. The restrictions on
`of` guarantee that inner literals cannot affect which outer `of` is
picked.

### Varargs and spreads

Three different things, worth keeping apart.

**`of` itself is vararg.** That is the operator convention.

**A literal is not a vararg list.** Passing a literal where a
`vararg` *element* is expected gives you one element that is a
collection:

```kotlin
fun tag(vararg labels: List<String>) =
    println(labels.size)

tag(["a"], ["b", "c"]) // prints: 2
```

**Spread of a literal** (observed, not in the KEEP): the spread
argument's expected type is the array type, so the literal becomes an
array and is spread.

```kotlin
fun total(vararg cents: Int) = cents.sum()

println(total(*[100, 250])) // prints: 350
```

That compiles, but it is a roundabout `total(100, 250)`.

**Spread *inside* a literal is not part of the proposal.** The KEEP
only lists it as a question next to `arrayOf().copyOf()`. In 2.4.20 it
is a syntax error:

```kotlin
val base = [1, 2]
val more: List<Int> = [0, *base.toIntArray()]
// ERROR: syntax error: Expecting an element
```

Use `listOf(0) + base` or `buildList { }`.

### Equality and `when`: a trap

`==` and `when` branch conditions are *not* positions with an expected
type. The literal falls back to `List`, with element types inferred on
their own:

```kotlin
val amounts: List<Long> = listOf(1L, 2L)

println(amounts == [1, 2]) // prints: false
when (amounts) {
    [1, 2] -> println("hit")
    else -> println("miss") // prints: miss
}
```

`[1, 2]` is `List<Int>`, and `Integer(1) != Long(1)`. The KEEP wanted
these positions to have an expected type, and rejected it: `amounts ==
listOf(1, 2)` is already `false` today, and `amounts == id([1, 2])`
would be `false` under any rule, so special-casing the bare literal
would make it disagree with its own desugaring. The KEEP marks
disallowing literals in equality and `when` conditions as an open
question. Observed: in 2.4.20 they compile without a warning.

### Flexible types from Java

A Java parameter `List<T>` is seen as the flexible
`(Mutable)List<T>`. The KEEP says the current implementation searches
the *mutable lower bound*, which is safer at runtime.

```kotlin
val synced = Collections.synchronizedList<String>(
    ["a"],
)
synced.add("b") // works: it was mutableListOf
```

Observed bytecode: `CollectionsKt.mutableListOf`. The KEEP notes this
is not final; an earlier draft used the read-only upper bound.

For nullability and array-variance flexibility the bound does not
matter (same static scope). For `dynamic` on Kotlin/JS the upper bound
`Any` is used, so the result is a `List`.

### Intersection types

If the expected type is `A & B`, the KEEP proposes an error: neither
`A.of` nor `B.of` returns `A & B`.

```kotlin
interface Auditable
interface Versioned
fun <T> save(x: T) where T : Auditable,
                         T : Versioned = Unit

save([1])
// ERROR: expected type 'Auditable & Versioned'
// for collection literal does not define operator
// 'of' and is not a supertype of 'List'
```

Intersections that collapse, like `List<Int>? & List<Int>` or
`T & Any`, should keep working; the KEEP asks for targeted testing.

### Maps are not covered

There is no map literal syntax and no `Map.of` operator in this
proposal.

```kotlin
val prices = ["EUR": 1]
// ERROR: syntax error: Expecting ']'

val rates: Map<String, Int> = ["EUR" to 1]
// ERROR: expected type 'Map<String, Int>' does not
// define operator 'of' and is not a supertype of
// 'List'
```

The second error is the important one: a `List<Pair>` is not a `Map`.
The KEEP gives three reasons for leaving maps out; see Design
decisions. Keep using `mapOf`.

### What cannot be expressed at all

The KEEP's own "after" column admits two cases with no literal:

```kotlin
// target is a type argument, not an expected type
modules.mapNotNullTo(hashSetOf()) { find(it) }

// no expected type and no useful fallback
if (row != emptyList<Int>()) { /* ... */ }
```

And `listOfNotNull` has no literal equivalent, which is one reason the
`xxxOf` functions stay.

## Platform interop

### What Java sees from your `of`

Companion object without annotations:

```kotlin
class Tags(val items: List<String>) {
    companion object {
        operator fun of(vararg t: String) = Tags(t.toList())
    }
}
```

```java
Tags tags = Tags.Companion.of("kotlin", "jvm");
```

With `@JvmStatic` (observed: both the static bridge and the companion
method are emitted):

```kotlin
class Ids(val raw: IntArray) {
    companion object {
        @JvmStatic
        operator fun of(vararg ids: Int) = Ids(ids)
    }
}
```

```java
Ids ids = Ids.of(1, 2, 3);
```

With a companion block, `of` is a plain static method and there is no
`Companion` field at all (observed `javap`: `public static final Path
of(java.lang.String...)`):

```java
Path bin = Path.of("usr", "local", "bin");
```

This is why the operator is named `of`: it matches the JDK 9
convenience factories (JEP 269) and Guava's `ImmutableList.of`, so a
Kotlin type's literal support reads as an idiomatic Java factory.

### Using Java types as targets

Java static `of` methods are **not** considered in the current
experimental implementation.

```kotlin
val days: EnumSet<DayOfWeek> = [DayOfWeek.MONDAY]
// ERROR: does not define operator 'of'
```

If support is added, the proposed starting point is: a Java static
`of` counts only if it obeys the same restrictions as a Kotlin
`operator fun of`. The KEEP says this is not final.

Inheritance of Java statics is an open question. Java inherits
statics from classes, not from interfaces:

```java
public interface IBase {
    static IBase of(int... x) { return null; }
}
public class Base {
    public static Base of(int... x) { return null; }
}
public class ExtendsClass extends Base {}
public class Impl implements IBase {}
```

```kotlin
val a: Base = [1, 2]
// red today, green if Java statics are supported
val b: ExtendsClass = [1, 2]
// red either way: Base.of returns Base,
// or no `of` is inherited at all
val c: Impl = [1, 2]
// red: interface statics are not inherited
```

Because extension `of` is forbidden, you cannot bolt literal support
onto a Java collection from Kotlin. The KEEP's answer is that it
hopes the JVM ecosystem keeps following the JEP 269 pattern.

### Binary shape and compatibility

A literal is pure call-site desugaring. Nothing about it reaches the
callee's signature: a function taking `List<String>` still takes
`java.util.List`. So (my reading):

- Adding `operator` to an existing `of` is source-compatible and
  binary-compatible; it only enables new call sites.
- Changing which `of` overloads exist changes compiled call sites,
  like any overload change.
- Removing `operator` breaks source of literal users, not binaries
  already compiled.

Observed call-site shapes on the JVM:

| Literal | Compiles to |
|---|---|
| `[1, 2]` (no type) | `listOf(Object[])` |
| `["x"]` as `List` | `listOf(Object)` |
| `Set<Int>` | `setOf(Object[])` |
| `IntArray` | `newarray int` |
| `Tags` (companion object) | `Tags$Companion.of` |
| `Path` (companion block) | `Path.of` static |

### The future stdlib on JVM

The planned stdlib change (once companion blocks are stable) adds
`companion { operator fun of(...) }` with three overloads (vararg,
one, zero) to `List`, `MutableList`, `Set`, `MutableSet`, `Sequence`,
`Array` and all primitive and unsigned arrays.

```kotlin
public expect interface List<out E> : Collection<E> {
    public companion {
        public operator fun <T> of(
            vararg elements: T,
        ): List<T>
        public operator fun <T> of(element: T): List<T>
        public operator fun <T> of(): List<T>
    }
}
```

On the JVM `kotlin.collections.List` is mapped to `java.util.List`,
which Kotlin cannot change. The KEEP proposes a mapped companion like
`Int.Companion`, which maps to `kotlin.jvm.internal.IntCompanionObject`.

### Kotlin `List.of` is not Java `List.of`

The KEEP deliberately keeps Kotlin semantics:

```kotlin
val maybe: List<String?> = [null] // fine
val s: Set<Int> = [1, 1]
println(s) // prints: [1]
```

```java
java.util.List.of((Object) null); // NPE
java.util.Set.of(1, 1);  // IllegalArgumentException
```

The argument for sets: it would be very surprising for
`Set.of(compute1(), compute2())` to throw because two runtime values
happen to be equal.

The KEEP also notes that today's `setOf(vararg)` and `mapOf(vararg)`
do not return unmodifiable wrappers, unlike Java, and that it is
unknown whether that was an oversight or a performance choice.

### JS, Native, Wasm, Swift

- **JS:** a literal whose expected type is `dynamic` uses the `List`
  fallback via the upper bound `Any`. The KEEP rejects resolving `of`
  at runtime as too implicit. "In JavaScript, square brackets always
  return an `Array`", so least astonishment says: plain fallback.
- **Companion blocks** compile to static members "on supported
  platforms", which is how `List.of` avoids a `Companion` allocation.
- **Swift export:** exporting `operator fun of` as
  `ExpressibleByArrayLiteral` is not supported yet. Non-empty literals
  (`of(head, vararg tail)`) are a known mismatch, since Swift array
  literals can always be empty.

### Reflection and serialization

The KEEP says nothing about either. My reading: since literals are
call-site sugar for an ordinary function call, there is nothing to
reflect on and nothing for kotlinx.serialization to handle. A
serialized `Set<String>` built from `["a"]` is the same as one built
with `setOf("a")`.

### Annotations

Annotation constructor arguments are resolved like ordinary call
arguments, so the existing array literals keep compiling unchanged,
now through the general mechanism.

```kotlin
annotation class Route(
    val methods: Array<String>,
    val codes: IntArray,
)

@Route(["GET", "HEAD"], [200, 304])
fun index() = Unit
```

This was a hard constraint on the design: an "always `List`" rule
would have broken every one of these.

## Performance

### The benchmark

The KEEP's JMH benchmark (`resources/collection-literals-benchmark`,
JDK 17, five elements unless noted, throughput in ops/ms, higher is
better) compares a vararg-array factory with a "manual" builder that
calls `add`/`put` per element:

| Benchmark | ops/ms |
|---|---|
| listOf, vararg array | 344,460 |
| listOf, manual `add` | 135,482 |
| setOf, vararg array | 40,686 |
| setOf, manual `add` | 49,329 |
| mapOf, vararg `Map.Entry` | 25,164 |
| mapOf, manual `put` | 51,304 |
| mapOf, two arrays | 38,183 |
| Kotlin `listOf` (5) | 342,670 |
| Java `List.of` (5) | 360,196 |
| Kotlin `listOf` (11) | 285,115 |
| Java `List.of` (11) | 90,537 |

What it shows:

- **Lists:** wrapping the vararg array (`Arrays.asList`) is about 2.5
  to 3x faster than adding element by element. Lists are array-backed
  and the most common collection.
- **Sets:** the builder is only about 20% faster; the vararg array is
  the redundant allocation.
- **Maps:** the builder is about 2x faster, mostly because of the
  `Map.Entry`/`Pair` boxing, not because of the array.
- **Kotlin vs Java:** at 5 elements they are on par (Java has a
  dedicated 5-argument overload). At 11 elements Java falls to its
  vararg overload and copies the array; Kotlin is about 3x faster.

### Why Kotlin does not copy the vararg

The KEEP's "unique vararg statement": in pure Kotlin a `vararg`
parameter is practically always a fresh array.

```kotlin
fun accept(vararg cents: Int) = Unit

accept(1, 2)              // new array at call site
accept(*existing)         // spread copies the array
::accept.invoke(intArrayOf(1, 2)) // not copied!
```

Only the callable-reference case passes an array through, and nobody
takes references to `listOf`. Java cannot assume this, so `List.of`
must defensively copy, which is why Java ships ten fixed-arity
`List.of` overloads to avoid the copy for small sizes. Kotlin keeps
just three: zero, one (both return specialised lists) and vararg.

### Companion object allocation

With `companion object`, the call is `Tags.Companion.of(...)` on a
singleton. The KEEP says this has not been measured; companion blocks
compile to statics and avoid it. Before stabilisation, the impact on
user-defined companion-object `of`s should be validated.

### Future

`@VarargOverloads` (like `@JvmOverloads`) or `inline vararg` might
remove the array allocation altogether. The KEEP notes this is only
relevant for sets and maps.

## Design decisions

### Square brackets

```kotlin
val a = [1, 2, 3]
```

Chosen because Kotlin already used them in annotations, most
programmers know them from other languages, and they echo
mathematical matrix notation. The KEEP's one recorded concern: Java's
`new int[10]` looks similar, and a future `List [10]` would look even
more like "an array of ten lists". The KEEP accepts the collision,
comparing it to lambdas, which also look like Java but mean
something else.

### Rejected: always `List`

```kotlin
val ids: IntArray = [1, 2] // would not compile
```

Simpler mental model, but:

1. no reuse for `Set`, `Array`, `IntArray`; and array literals in
   annotations would become a breaking change
2. kotlinx.collections.immutable, Guava and others could not opt in
3. Kotlin's style is to add syntax and let libraries implement it,
   like `suspend` in the language and `async` in kotlinx.coroutines

The KEEP argues contextual typing is no more surprising than what we
already accept:

```kotlin
send(complicatedExpression()) // type unknown
send { println(it) }          // type unknown
send([1, 2])                  // type unknown
```

### Rejected: three granular operators

The alternative was a builder protocol, desugaring `[1, 2, 3]` to:

```kotlin
val tmp = List.createCollectionBuilder<Int>(3)
tmp.plusAssign(1)
tmp.plusAssign(2)
tmp.plusAssign(3)
List.freeze(tmp)
```

Rejected because it is more complex (three scattered operators, where
does Ctrl-click go?), exposes the builder type in public API, makes
returning different types per size awkward, and is *slower* for
lists, which are 3x faster with a pre-filled array. The KEEP calls
this a "double win": the simpler design is also the faster one.

### Rejected: more positions with an expected type

Making `==` and `when` conditions expected-type positions would make
`listOf(1L, 2L) == [1, 2]` true. Rejected because the literal would
then disagree with its own desugaring (`== listOf(1, 2)` is false)
and with `== id([1, 2])`. Disallowing the syntax in these positions
remains open.

### Rejected (for now): `List [1, 2]`

```kotlin
fun index(ids: Set<Int>) = Unit
fun index(ids: List<Int>) = Unit

index(List [1, 2]) // not proposed
index(listOf(1, 2)) // already works
```

Rejected because `listOf` (and later `List.of`) already solve it. The
KEEP adds a subtle point: `List [1, 2]` is already valid Kotlin today
if someone declares an `operator fun get` on the companion, possibly
as an extension in another library. So the syntax cannot be reserved,
and any future version would need its own ambiguity rules.

### Rejected: locality-restricted resolution

Covered in Rules: refining only the nearest scope level was rejected
for consistency with callable references.

### Not now: List vs Set overload preference

Possible later, the same way `foo(1)` prefers `Int` over `Long`: make
`List` "more specific" than other literal targets. Not planned,
because either overload might be the main one.

### Not now: map literals

```kotlin
val m = ["key": 1] // not in this proposal
```

Three reasons:

1. **Java interop.** `java.util.Map.of` has up to 11 overloads with an
   even number of parameters plus `ofEntries(Map.Entry...)`. No clean
   operator convention matches that.
2. **Boxing.** The natural `of(vararg Map.Entry<K, V>)` allocates an
   entry per pair; the benchmark shows a manual `put` loop 2x faster.
3. **`Map.Entry` is an interface.** For `[1: "a"]`, which class should
   the call site instantiate?

Maps can be added later; the KEEP wants to get collections right
first.

### Not now: tuples

The `of` rules (mandatory `vararg`, uniform element type) make typed
tuples impossible, and the KEEP does not plan tuples in the first
version. It only wants to avoid accidentally closing the door on
square brackets for tuples later.

### Other languages

| Language | Literals | User types |
|---|---|---|
| Java | arrays only | no (JEP 186 dropped) |
| Swift | `[...]`, typed | `ExpressibleByArrayLiteral` |
| C# 12 | `[...]`, typed | `IEnumerable`/`Add` or builder |
| Scala | none | `apply` factory |
| Python | `[...]`, `{...}` | no (dynamic) |

Swift is the closest relative: same syntax, polymorphic by expected
type, user types opt in. C# collection expressions are also
target-typed, but have no default:

```text
var list = [1, 2]; // C# error: no target type
```

Kotlin differs by falling back to `List`. Java explicitly chose `of`
factories over literals (JEP 269 after JEP 186), and Scala recently
discussed and rejected a pre-SIP for collection literals.

## Open questions and what may change

The KEEP flags all of these as not final:

- **Postponed-literal completion** (choosing a representative from
  constraints) is experimental; inference and resolution may change.
- **Inference through lambdas, Elvis and `apply`** (example 8) works
  but is "not a stable part of the proposal yet".
- **Eager lambda analysis** interaction is unspecified.
- **Flexible mutability:** lower bound (mutable) today; the read-only
  upper bound may come back.
- **Java static `of`:** not supported; which ones would count, and
  whether Java or Kotlin inheritance rules apply, is open.
- **Equality and `when`:** may be disallowed syntactically.
- **`Array` vs `Iterable` vs `Sequence` ambiguity:** four candidate
  fixes listed, none chosen.
- **Companion-object allocation cost** not measured yet.
- **Stdlib `List.of` etc.** wait for companion blocks; until then the
  fallback is `listOf`.
- **Swift export** of `of` as `ExpressibleByArrayLiteral`.
- **Map literals and tuples** possibly later, possibly other syntax.

```kotlin
// may change: currently compiles and prints false
println(listOf(1L) == [1])

// may change: currently mutableListOf
Collections.synchronizedList<String>(["a"])

// may become green: Java static of
val days: EnumSet<DayOfWeek> = [DayOfWeek.MONDAY]
```

IDE plans from the KEEP: an inspection to replace explicit `Type.of`
with a literal (on by default), an inspection to replace
`listOf`/`setOf` (probably off by default), and a hint that rewrites
`[1, 2].toMutableList()` into a typed declaration. None of the `xxxOf`
functions will be deprecated.

## Cheat sheet

```kotlin
val xs = [1, 2]              // List<Int> (listOf)
val s: Set<Int> = [1, 1]     // setOf -> [1]
val a: IntArray = [1, 2]     // newarray
val m: MutableList<User> = []
val e = []                   // ERROR: infer T

class Tags { companion {     // or companion object
    operator fun of(vararg t: String): Tags = TODO()
} }
val t: Tags = ["kotlin"]     // Tags.of("kotlin")

fun f(x: List<String>) = Unit
@JvmName("fi") fun f(x: List<Int>) = Unit
f([1])                       // List<Int> one wins

fun g(x: List<Int>) = Unit
fun g(x: Set<Int>) = Unit
g([1])                       // ERROR: ambiguity
listOf(1) + [2]              // ERROR: ambiguity
listOf(1L) == [1]            // false (List<Int>)
val mp: Map<String, Int> = ["a" to 1] // ERROR
```

- Experimental since 2.4.0; this project enables it with
  `-Xcollection-literals`.
- `[...]` becomes `Type.of(...)` where `Type` is the expected type.
- No expected type, or a type without `of` that `List` fits: `List`.
- `of` is a member of a companion object or companion block, never an
  extension; exactly one `vararg` overload; extra overloads differ
  only in arity; non-null return of the owning class; same visibility;
  no defaults, receivers or contracts.
- `inline reified` and `suspend` `of` are allowed.
- Inner-type overloads (`List<String>` vs `List<File>`) resolve;
  outer-type overloads (`List` vs `Set`, `Iterable` vs `Array`) are
  ambiguous.
- No maps, no tuples, no spread inside literals.
- No mutable fallback: `MutableCollection`, `ArrayList`, `HashSet`
  fail.
- Java static `of` methods are ignored for now.
- Annotation array literals keep working, now via the same mechanism.

## Talking points

- "`[1, 2, 3]` is not a new collection type. It is a call to
  `Type.of(1, 2, 3)`, and the type you expect decides which `Type`."
- "No expected type? You get a `List`, the same thing `listOf` gives
  you today."
- "Any class can opt in with one `operator fun of` in its companion.
  It doesn't even have to be a collection."
- "Annotations already accept `[...]` for arrays. This just lets the
  rest of your code use it too."
- "`List<String>` versus `List<File>` overloads resolve fine. `List`
  versus `Set` doesn't, on purpose: the syntax can't say which one you
  meant."
- "The single `of` operator beat the builder-style design on both
  simplicity and speed: lists are about 3x faster with a pre-filled
  array."
- "Kotlin can trust that a vararg array is fresh, so `List.of` needs
  three overloads where Java needs ten."
- "No map literals yet: Java's `Map.of` shape, entry boxing, and
  `Map.Entry` being an interface all got in the way."

### Tricky questions

**"Why is `listOf(1L, 2L) == [1, 2]` false?"**
`==` gives the literal no expected type, so it becomes `List<Int>`,
and boxed `Int` never equals boxed `Long`. The KEEP considered making
`==` an expected-type position and rejected it because
`== listOf(1, 2)` and `== id([1, 2])` would still be false; the
literal must not behave differently from its own desugaring.

**"Can I make `[...]` produce a Guava `ImmutableList` or an
`ArrayList`?"**
Not directly today. Java static `of` methods are not considered yet,
and you cannot declare `of` as an extension, so `ArrayList<Int> = [1]`
fails. Declare `MutableList<Int>` instead, or wrap the Java type in a
Kotlin type with its own `operator fun of`. Java static support is
proposed but not final.

**"Why can't I write `optIns + ["x"]`?"**
`plus` has overloads for an element, an `Array`, an `Iterable` and a
`Sequence`, and the literal fits several of them. The KEEP leaves
that ambiguous on purpose rather than hard-coding a preference it
might regret. Write `optIns + "x"` or `optIns + listOf("x")`.
