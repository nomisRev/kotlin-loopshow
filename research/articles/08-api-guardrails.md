---
title: "API Guardrails"
subtitle: "Unused return values and named-only parameters: two ways to make a library API hard to misuse"
author: "Notes from KEEP-0412 (unused return value checker), KEEP-0439, with KEEP-0193 and KEEP-0412 (underscores)"
date: "October 2026"
lang: en
---

## At a glance

Both features attack the same class of bug: the call compiles,
type-checks and is still wrong. One of them catches results you
throw away. The other catches arguments you pass in the wrong slot.
Neither changes runtime behaviour. They only change what the
compiler is willing to accept without saying anything.

| Feature | Status | Enable with |
|---|---|---|
| Unused return value checker (KEEP-0412) | Experimental in 2.3 | `-Xreturn-value-checker=check` or `full` |
| `val _ =` unnamed locals (KEEP-0412 underscores) | Experimental in 2.2 | used as the escape hatch |
| Named-only parameters (KEEP-0439) | Public discussion | not implemented |
| Named args in own position (KEEP-0193) | Stable in 1.4 | always on |

Sources and trackers:

- [KEEP-0412, unused return value checker](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0412-unused-return-value-checker.md),
  YouTrack [KT-12719](https://youtrack.jetbrains.com/issue/KT-12719),
  discussion [KEEP#412](https://github.com/Kotlin/KEEP/issues/412).
  Authors: Leonid Startsev, Mikhail Zarechenskiy.
- [KEEP-0412, underscores for local variables](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0412-underscores-for-local-variables.md),
  same discussion thread.
- [KEEP-0439, named-only parameters](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0439-named-only-parameters.md),
  YouTrack [KT-14934](https://youtrack.jetbrains.com/issue/KT-14934),
  discussion [#442](https://github.com/Kotlin/KEEP/discussions/442).
  Author: Roman Efremov.
- [KEEP-0193, named arguments in their own position](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0193-named-arguments-in-their-own-position.md),
  YouTrack [KT-7745](https://youtrack.jetbrains.com/issue/KT-7745).

This project compiles with Kotlin 2.4.20 and already passes
`-Xreturn-value-checker=full`. In 2.4.20 the `named` modifier is
still a syntax error (checked with `kotlinc` 2.4.20): everything
about named-only parameters in this article is the proposal, not
shipped behaviour.

The teaser:

```kotlin
fun Money.withVat(rate: Double): Money =
    Money(cents + (cents * rate).toLong())

price.withVat(0.21)
// WARNING: unused return value of 'withVat'

// Proposed (KEEP-0439), does not compile today
fun transfer(amount: Money, named dryRun: Boolean)
transfer(price, true) // ERROR: name required
```

## The problem

A library author controls the declaration. The caller controls the
call site. Most API misuse happens in the gap between the two, in
places where Kotlin today has no opinion.

### Results that silently vanish

KEEP-0412 opens with this function. Read it once and look for the
bug:

```kotlin
fun formatGreeting(name: String): String {
    if (name.isBlank()) return "Hello, anonymous user!"
    if (!name.contains(' ')) {
        "Hello, " +
            name.replaceFirstChar(Char::titlecase) + "!"
    }
    val (firstName, lastName) = name.split(' ')
    return "Hello, $firstName! " +
        "Or should I call you Dr. $lastName?"
}
```

The author forgot `return` on the second branch. The string is built
and dropped, control falls through, and `split(' ')` returns a
single-element list, so destructuring `lastName` throws at runtime.
The existing "unused expression" diagnostic does not catch this:
`"a" + b` is a call to `plus`, and calls are assumed to have side
effects.

The same pattern shows up with immutable APIs, where the whole
point is that the method returns a new value:

```kotlin
data class Order(val items: List<Item>, val total: Money)

fun addFee(order: Order, fee: Money): Order {
    order.copy(total = order.total + fee) // result lost
    return order  // fee never added
}
```

and with "status" returns that everyone ignores even though they
shouldn't. KEEP-0412 calls out `File.delete(): Boolean` as the
canonical weak API: it reports failure through its return value,
and almost nobody checks it.

Other ecosystems already deal with this. Rust has `#[must_use]`,
C++ has `[[nodiscard]]`, Java has ErrorProne's `@CheckReturnValue`
and Sonar's RSPEC-2201. Swift inverts the default: every unused
non-void result warns unless the function is marked
`@discardableResult`.

### Arguments in the wrong slot

KEEP-0439 starts from the Kotlin docs' own example:

```kotlin
fun reformat(
    str: String,
    normalizeCase: Boolean = true,
    upperCaseFirstLetter: Boolean = true,
    divideByCamelHumps: Boolean = false,
    wordSeparator: Char = ' ',
) { /* ... */ }

reformat(myStr, true, false, true, ' ')
```

Which `true` is which? The Kotlin coding conventions already tell
you to name `Boolean` arguments and runs of same-typed primitives.
Java developers fake it with comments:

```java
reformat(myStr, /* normalizeCase = */ true);
```

Swapped positional arguments of the same type compile fine and
fail later, often silently:

```kotlin
fun <T> assertEquals(expected: T, actual: T)

assertEquals(response.status, 200) // swapped, still green
```

Multiple lambdas make it worse, because trailing-lambda syntax
hides which parameter the last block binds to:

```kotlin
fun Result.process(
    onSuccess: () -> Unit,
    onError: () -> Unit,
)

result.process(onSuccess = { log("ok") }) {
    log("is this onError? yes, but you have to look it up")
}
```

The convention exists, IDE inspections exist (`BooleanLiteralArgument`,
`CopyWithoutNamedArguments`), detekt has `UnnamedParameterUse`. The
KEEP's argument is that none of these travel with the library:
every consumer must configure their own build. A library author has
no way to say "this argument must be named" and have that enforced
on everyone who calls it.

### The common thread

Both KEEPs move a piece of API intent from documentation into the
declaration, where the compiler can see it:

```kotlin
// "Use the result" and "name this argument"
// are both documentation today.
/** Returns a new Order. Don't ignore it. */
fun Order.withDiscount(
    percent: Int,
    /** Pass by name, please. */
    applyToShipping: Boolean,
): Order
```

## Part 1: the unused return value checker, step by step

### Step 1: turn it on

The checker is a compiler switch with three states:

```text
-Xreturn-value-checker=disable
    default while experimental
-Xreturn-value-checker=check
    report on marked APIs only
-Xreturn-value-checker=full
    also treat all your own code as must-use
```

In Gradle today, through free compiler arguments (the KEEP says to
"stay tuned for Gradle DSL updates"):

```kotlin
kotlin {
    compilerOptions.freeCompilerArgs.add(
        "-Xreturn-value-checker=check",
    )
}
```

### Step 2: the simplest warning

In `check` mode, the stdlib is already "RVC-approved", so you get
warnings on stdlib calls immediately:

```kotlin
fun normalize(email: String): String {
    email.trim()          // WARNING: unused return value
    email.lowercase()     // WARNING: unused return value
    return email
}
```

`String` is immutable, so `trim()` without using the result can
never be what you meant.

### Step 3: what counts as "used"

The KEEP defines usage precisely. The result of expression `A` is
used if `A` is:

- an initializer of a property, parameter or local, including a
  delegate: `val a = A`, `val x by A`;
- the argument of `return` or `throw`;
- an argument to another call, including operator conventions:
  `f(A)`, `A == 42`, `A + "s"`, `"Hi ${A}"`;
- a receiver: `A.foo()`, `A?.bar()`;
- a condition in `if`, `while`, `when`, including a `when` branch
  condition: `when (x) { A -> ... }`;
- the last statement of a lambda: `list.map { A }`.

```kotlin
fun audit(order: Order) {
    val total = order.total()        // used: initializer
    log("total=${order.total()}")    // used: template arg
    if (order.isPaid()) ship(order)  // used: condition
    order.total().format()
    // total() is used as a receiver, format() is not
    // WARNING: unused return value of 'format'
}
```

Anything that is not in that list, and is not ignorable by itself,
gets the warning.

### Step 4: mark the exceptions with `@IgnorableReturnValue`

Some functions return something useful that callers may still drop.
`MutableList.add` returns `Boolean`, but almost nobody checks it.
The author marks such functions:

```kotlin
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.BINARY)
public annotation class IgnorableReturnValue
```

```kotlin
class Cart {
    private val items = mutableListOf<Item>()

    @IgnorableReturnValue
    fun add(item: Item): Boolean = items.add(item)

    fun total(): Money = items.sumOf { it.price }
}

cart.add(book)   // OK, explicitly ignorable
cart.total()     // WARNING in full mode
```

Note the target: functions only. No `CONSTRUCTOR`, no `PROPERTY`.
The KEEP says this is deliberate, to discourage constructors and
properties with side effects. A constructor call or property read
that is thrown away is always a warning (once the declaration is
must-use).

### Step 5: opt in a scope with `@MustUseReturnValues`

```kotlin
@Target(AnnotationTarget.FILE, AnnotationTarget.CLASS)
@Retention(AnnotationRetention.BINARY)
public annotation class MustUseReturnValues
```

Every callable in the annotated file or class is non-ignorable,
even in `check` mode:

```kotlin
@MustUseReturnValues
class PriceCalculator {
    fun net(order: Order): Money = TODO()
    fun gross(order: Order): Money = TODO()
}

calc.net(order) // WARNING, even with =check
```

The name is plural and there is no `FUNCTION` target on purpose:
the KEEP wants authors to "think about and design non-ignorable APIs
as a whole, not on a per-function basis". The annotation exists for
two jobs: gradual migration of a big API, and adding ignorability
information on overrides (Rules section).

### Step 6: the escape hatch, `val _ =`

Sometimes you genuinely need to drop a must-use value. KEEP-0412
(underscores) adds unnamed locals:

```kotlin
fun warmUp(cache: PriceCache) {
    val _ = cache.load()  // no warning, intent is explicit
}
```

`val _` is not a suppression. It is a declaration with no name, so
the checker sees the value used as an initializer. The reviewer
sees, in one token, that dropping the result is deliberate.

### Step 7: full mode for your own code

In `full` mode, every callable you compile becomes non-ignorable
(and is flagged as such in metadata), not only annotated ones:

```kotlin
// compiled with -Xreturn-value-checker=full
fun greet(user: User): String = "Hi ${user.name}"

fun main() {
    greet(User("Ann"))
    // WARNING: unused return value of 'greet'.
}
```

That is the exact message `kotlinc` 2.4.20 prints for this snippet.
For an application, `full` is "check my own code too". For a
library, it is the publishing switch: see Typical usage.

## Part 2: named-only parameters, step by step

Everything here is from KEEP-0439, status "Public discussion". It
does not compile in 2.4.20.

### Step 1: the `named` modifier

`named` is a new soft keyword on a value parameter. The argument
must then be passed by name, or omitted if it has a default:

```kotlin
fun CharSequence.startsWith(
    char: Char,
    named ignoreCase: Boolean = false,
): Boolean

cs.startsWith('a')                    // OK
cs.startsWith('a', ignoreCase = true) // OK
cs.startsWith('a', true)              // ERROR
```

The error is an error, not a warning (unless softened, step 5).
Because `named` is a soft keyword, it stays a valid identifier
elsewhere (my reading, by analogy with other soft keywords).

### Step 2: several named-only parameters

```kotlin
fun String.reformat(
    named normalizeCase: Boolean,
    named upperCaseFirstLetter: Boolean,
): String

s.reformat(false, true) // ERROR
s.reformat(
    normalizeCase = false,
    upperCaseFirstLetter = true,
) // OK
```

The modifier is per parameter. The ones without it keep today's
flexible behaviour.

### Step 3: defaults

A named-only parameter with a default can simply be left out. A
named-only parameter without a default must appear, by name:

```kotlin
fun charge(
    amount: Money,
    named idempotencyKey: String,
    named capture: Boolean = true,
)

charge(price, idempotencyKey = key)      // OK
charge(price, key)                       // ERROR
charge(price)
// ERROR: no value passed for idempotencyKey
```

### Step 4: constructors

`named` is allowed on constructor value parameters, including
`val`/`var` properties declared in the primary constructor:

```kotlin
class RetrySettings(
    named val maxRetries: Int,
    named val delayMillis: Long,
    named val exponentialBackoff: Boolean,
)

RetrySettings(3, 500, true) // ERROR
RetrySettings(
    maxRetries = 3,
    delayMillis = 500,
    exponentialBackoff = true,
) // OK
```

### Step 5: soften it during migration

Making an existing parameter `named` breaks every positional
caller. The KEEP proposes a stdlib annotation to downgrade the
error to a warning:

```kotlin
@Target(FUNCTION, CONSTRUCTOR, FILE)
@Retention(BINARY)
annotation class SoftNamedOnlyParametersCheck(
    named val ideOnlyDiagnostic: Boolean = false,
)
```

```kotlin
@SoftNamedOnlyParametersCheck
fun CharSequence.startsWith(
    char: Char,
    named ignoreCase: Boolean = false,
): Boolean

cs.startsWith('a', false) // WARNING (not ERROR)
```

With `ideOnlyDiagnostic = true`, the warning appears only in the
IDE and is disabled everywhere else, so a stdlib-scale migration
does not flood build logs. The annotation has no `VALUE_PARAMETER`
target: the KEEP finds it hard to imagine one parameter being an
error and another a warning on the same function. On a file, it
applies to all top-level functions in that file. On a data class
constructor, it also applies to the generated `copy()`.

The KEEP spells the name two ways:
`SoftNamedOnlyParametersCheck` in the declaration and
`SoftNamedOnlyParameterCheck` in the examples. The final name is
open.

### Step 6: lambdas cannot go trailing

A `named` function-typed parameter cannot be passed as a trailing
lambda:

```kotlin
fun Response.handle(
    named onSuccess: (Body) -> Unit,
    named onError: (Status) -> Unit,
)

response.handle({ show(it) }, { alert(it) }) // ERROR
response.handle(onSuccess = { show(it) }) {
    alert(it)
} // ERROR: onError cannot be trailing
response.handle(
    onSuccess = { show(it) },
    onError = { alert(it) },
) // OK
```

## Typical usage

### Immutable domain models

Value-style APIs are the strongest case for the checker. Every
"modifier" returns a new instance:

```kotlin
@MustUseReturnValues
data class Money(val cents: Long, val currency: String) {
    operator fun plus(other: Money): Money {
        require(currency == other.currency)
        return Money(cents + other.cents, currency)
    }
    fun withVat(rate: Double): Money =
        copy(cents = cents + (cents * rate).toLong())
}

fun checkout(cart: Cart): Money {
    val net = cart.total()
    net.withVat(0.21) // WARNING: result lost
    return net
}
```

The generated `copy()` is already checked in `full` mode (verified
with `kotlinc` 2.4.20: `u.copy("B")` warns "unused return value of
'copy'").

### Fluent builders

Builders that return `this` for chaining are the textbook
`@IgnorableReturnValue` case. The KEEP's example is Netty's
`ByteBuf.clear()`, which "returns self and is definitely ignorable".
The terminal `build()` is not:

```kotlin
class RequestBuilder {
    private var url = ""
    private val headers = mutableMapOf<String, String>()

    @IgnorableReturnValue
    fun url(value: String): RequestBuilder =
        apply { url = value }

    @IgnorableReturnValue
    fun header(k: String, v: String): RequestBuilder =
        apply { headers[k] = v }

    fun build(): HttpRequest = HttpRequest(url, headers)
}

val b = RequestBuilder()
b.url("https://api.example.com") // OK
b.header("Accept", "json")       // OK
b.build()                        // WARNING
```

Without the annotation, `b.url(...)` as a statement warns in `full`
mode (verified with 2.4.20). This is the main work when opting a
library in: find every "returns self for chaining" method and mark
it. If the builder is purely immutable (each call returns a new
builder), do not mark it: dropping the result is then a real bug.

### Repository and service layers

Status-returning mutations are the `File.delete()` problem in your
own code:

```kotlin
interface OrderRepository {
    fun save(order: Order): Order       // must-use
    @IgnorableReturnValue
    fun delete(id: OrderId): Boolean    // caller may drop
}

fun cancel(repo: OrderRepository, order: Order) {
    repo.save(order.copy(status = CANCELLED))
    // WARNING in full mode: maybe you meant to
    // return the saved version with the new version tag?
    repo.delete(order.id) // OK
}
```

Whether `delete` should be ignorable is an API decision. The
KEEP's third goal is exactly this: surface APIs "that everyone
ignores but probably shouldn't".

### Coroutines-style APIs

`launch` returns a `Job` and `async` returns a `Deferred`. Dropping
a `Deferred` usually means you forgot `await()`. Dropping a `Job`
is normal. How kotlinx.coroutines marks these is the library's
choice, and the KEEP only says "some kotlinx libraries will be
RVC-approved from the start" without listing which (open). The
shape you would expect (my reading):

```kotlin
scope.launch { refresh() }         // fire and forget
scope.async { loadPrices() }       // a lost Deferred
                                   // is likely a bug
```

### Named-only in DSLs: flags plus a trailing lambda

The KEEP rejected a "fence" syntax precisely because DSLs need a
group of named-only options followed by a positional trailing
lambda:

```kotlin
fun Route.get(
    path: String,
    named authenticated: Boolean = false,
    named rateLimit: Int = 100,
    handler: suspend Call.() -> Unit,
)

get("/orders", authenticated = true) {
    respond(orders())
}
get("/health", true) { respond("ok") } // ERROR
```

### Compose-style modifiers and settings objects

All-named APIs from the KEEP's examples table:

```kotlin
fun Modifier.padding(
    named start: Dp = 0.dp,
    named top: Dp = 0.dp,
    named end: Dp = 0.dp,
    named bottom: Dp = 0.dp,
): Modifier

Modifier.padding(8.dp, 0.dp, 8.dp)  // ERROR
Modifier.padding(start = 8.dp, end = 8.dp) // OK
```

### Name as a continuation of the function name

The KEEP's most interesting example: `foldTo` could become an
overload of `fold` whose first parameter is named-only:

```kotlin
fun <T, K, R, M : MutableMap<in K, R>>
    Grouping<T, K>.fold(
        named to: M,
        initialValue: R,
        operation: (acc: R, element: T) -> R,
    ): M

groups.fold(to = cache, initialValue = 0) { a, _ ->
    a + 1
}
```

The KEEP is explicit that it is not promoting this over `foldTo`;
it is only showing that `named` supports both styles. Applied to a
domain API:

```kotlin
fun copy(named from: Path, named to: Path)

copy(from = upload, to = archive)
```

### Test assertions

```kotlin
fun <T> assertEquals(named expected: T, actual: T)

assertEquals(expected = 200, response.status) // OK
assertEquals(response.status, 200)            // ERROR
```

Note that `expected = 200` followed by a positional `actual` works
because of KEEP-0193 (Kotlin 1.4): a named argument in its own
position may be followed by positional ones.

## Rules and edge cases

### Checker: what is ignorable by itself

Four kinds of expressions never warn, regardless of the callee.

**1. `Unit`, `Nothing`, `Nothing?` results.** For generic
functions the substituted type counts:

```kotlin
fun <T> fetch(name: String): T = TODO()
fun <T> tryAcquire(): T? = null

fetch<Unit>("ping")    // OK, T = Unit
fetch<Order>("o-1")    // WARNING
tryAcquire<Unit>()     // WARNING: Unit? is NOT ignorable
```

`Unit?` is deliberately not on the list. It typically arises from
something like `tryAcquire(): T?`, and those results are meant to
be null-checked even when the value itself is useless. (The
`tryAcquire<Unit>()` warning is verified with 2.4.20.)

For Java interop, platform `Unit!`, `Nothing!` and `java.lang.Void`
(which appears in generic overrides of Java methods) are also
ignorable.

**2. Pre- and post-increment.** `++i` and `i++` are ignorable as
expressions. `inc()` itself is not, because `inc()` computes the
new value but does not assign it:

```kotlin
var retries = 0
retries++          // OK
++retries          // OK
retries.inc()      // WARNING: does nothing
```

**3. Boolean short-circuits ending in `Nothing`.** If the right side
of `&&` or `||` has type `Nothing`, the whole expression is
ignorable:

```kotlin
fun ship(order: Order) {
    order.isPaid() || return                  // OK
    order.isShipped() && throw AlreadyShipped()  // OK
    order.isPaid() && order.isShipped()  // WARNING
}
```

**4. Calls to ignorable callables.** Either explicitly
(`@IgnorableReturnValue`) or implicitly ("unspecified"). See next.

### Checker: three kinds of callable

| Kind | How you get it | Warns? |
|---|---|---|
| Non-ignorable | full mode, `@MustUseReturnValues`, inherited | yes |
| Explicitly ignorable | `@IgnorableReturnValue` | no |
| Unspecified | everything else (most JDK) | no |

The checker treats explicit and unspecified the same. The difference
matters only for overrides and expect/actual. This is the migration
trick: code that nobody has reviewed is unspecified and stays
silent, so turning on `check` does not produce a flood of false
positives from Netty or the JDK.

```kotlin
java.io.File("tmp.csv").delete()  // OK: JDK, unspecified
listOf(1, 2).map { it * 2 }       // WARNING: stdlib
```

Both lines verified with 2.4.20 in `full` mode. Note the KEEP's
wording: "most JDK functions (but not their Kotlin counterparts)
will be implicitly ignorable".

### Checker: propagating expressions

Control-flow expressions and type operators are neither ignorable
nor non-ignorable. They pass the question down to their operands.

**`if` and `when` branches.** If the whole `if`/`when` is unused,
the last expression of each branch is unused:

```kotlin
fun label(order: Order): String {
    if (order.isPaid()) order.receipt() else order.invoice()
    // WARNING on both receipt() and invoice()
    return if (order.isPaid()) order.receipt() else ""
}
```

Conditions count as usage, including `when` branch conditions:

```kotlin
when (status) {
    parse(raw) -> retry()   // parse() used, retry() not
    else -> fail()          // fail() not used
}
```

**Elvis.** Both sides of `?:` propagate. The left side is only
"type consumed" (compared with null), not "value consumed":

```kotlin
fun load(id: OrderId) {
    findOrder(id) ?: return   // WARNING on findOrder
    val o = findOrder(id) ?: return  // OK
}
```

This one surprises people. `findOrder(id) ?: return` looks like a
guard, but the found order is thrown away right after the null
check. If you only want the existence check, say so with `== null`
or keep the value.

**`try`/`catch`/`finally`.** The last expressions of `try` and
`catch` blocks propagate. `finally` has no result, so its last
expression is just a statement:

```kotlin
val receipt = try {
    gateway.charge(card)          // used: try is used
} catch (e: IOException) {
    Receipt.failed(e)             // used
} finally {
    audit.record(card)            // WARNING if must-use
}
```

**Type operators.** `as`, `as?`, `is`, `!is` and `!!` propagate:

```kotlin
repo.find(id)!!          // WARNING: find() unused
repo.find(id) as Order   // WARNING
```

### Checker: higher-order functions

`packageName?.let { list.add(it) }` has type `Boolean?`, but the
body is an ignorable `add`. Ideally `let` would propagate like an
`if`. There is no way to express or infer that today, so the KEEP
marks `let` "and some other functions" as `@IgnorableReturnValue`
to avoid false positives:

```kotlin
user?.let { emails.add(it.email) }   // OK
user?.let { "Dear " + it.name }      // OK too: let is
                                     // ignorable (gap)
```

The second line is a missed bug, and the KEEP accepts that for
now. The planned fix is a contract kind that declares a higher-order
function as propagating, which depends on finalizing contracts
(KEEP-0139). Not every stdlib HOF is ignorable: `map` still warns.

### Checker: overrides

Two rules.

**Rule 1: ignorability is inherited.** Implement a stdlib interface
and your override is must-use. That includes `Any.hashCode()`,
which counts as declared in the stdlib:

```kotlin
class Sku(val code: String) {
    override fun hashCode(): Int = code.hashCode()
}

sku.hashCode() // WARNING in check mode
```

**Rule 2: you cannot turn an explicitly ignorable function into a
non-ignorable one.** Otherwise the warning would depend on the
static type: report on `Derived`, silently lost on `Base`. That
breaks substitutability.

```kotlin
interface Repo {
    @IgnorableReturnValue
    fun save(o: Order): Boolean
}

@MustUseReturnValues
class DbRepo : Repo {
    override fun save(o: Order): Boolean = true
    // WARNING: overriding ignorable methods with
    // must-use methods is a semantically incorrect
    // change
}
```

The KEEP says "not allowed". Kotlin 2.4.20 reports it as a warning
(verified), suggesting you mark `save` as `@IgnorableReturnValue`.

The reverse is fine: an override may become ignorable.

```kotlin
@MustUseReturnValues
interface PriceSource {
    fun price(sku: Sku): Money
}

object FreeSample : PriceSource {
    @IgnorableReturnValue
    override fun price(sku: Sku) = Money.ZERO
}

fun probe(p: PriceSource) {
    p.price(sku)          // WARNING
    FreeSample.price(sku) // OK
}
```

Unspecified (for example Java) members can be upgraded to must-use
on override, because `@MustUseReturnValues` on the scope has
priority over the parent:

```java
public interface JavaInventory {
    String sku();
    boolean reserve();
}
```

```kotlin
@MustUseReturnValues
interface Inventory : JavaInventory {
    override fun sku(): String
    @IgnorableReturnValue
    override fun reserve(): Boolean
}

fun check(j: JavaInventory, k: Inventory) {
    j.sku()      // OK: unspecified
    k.sku()      // WARNING
    k.reserve()  // OK
}
```

Resolution order for a callable's status:

1. `@IgnorableReturnValue` on it, or `@MustUseReturnValues` on an
   enclosing scope.
2. The immediate parent's status, if there is one.
3. The feature mode.

### Checker: expect/actual

Not overriding: a separate rule. Ignorability must match between
`expect` and `actual`. Explicit vs. implicit ignorable do not
conflict (neither warns):

```kotlin
expect class Clock {
    fun now(): Instant
    fun tick(): Instant
}

@MustUseReturnValues
actual class Clock {
    actual fun now(): Instant = TODO()
    // WARNING: implicitly ignorable expect
    // actualized as non-ignorable
    @IgnorableReturnValue
    actual fun tick(): Instant = TODO() // OK
}
```

The one exception: when the actual member is declared outside the
class, for example contributed by a Java supertype or reached
through a typealias, a non-ignorable/unspecified mismatch is
allowed:

```kotlin
@file:MustUseReturnValues
expect class Clock { fun now(): Instant }

// jvmMain, JavaClock is a Java class
actual class Clock : JavaClock() // no warning
```

The KEEP warns this can produce different warnings in common and
platform code; avoid it.

### Checker: `val _` rules

From the underscores KEEP:

```kotlin
fun bootstrap() {
    val _ = cache.load()          // OK
    val _: Boolean = file.delete() // OK, typed
    val _ = cache.load()          // OK, several allowed
    var _ = cache.load()          // ERROR: only val
    val _ by lazy { load() }      // ERROR: no delegate
    println(_)                    // ERROR: unresolved
}

class Service {
    val _ = init()  // ERROR: only local variables
}
```

The shorter `_ = expr` statement was rejected: it looks like an
assignment to an existing `_` (confusable with an unused lambda
parameter `{ idx, _ -> ... }`), and `val` matches positional
destructuring `val (a, _) = pair`. Underscored function parameters
(`fun f(_: String)`) are explicitly out of scope.

### Checker: annotations need the feature on

The ignorability annotations are experimental stdlib API. With the
checker disabled they are an error:

```kotlin
// compiled with the default (disable)
@IgnorableReturnValue
fun add(item: Item): Boolean = TODO()
// ERROR: ignorability-related annotations are
// experimental and cannot be used with
// -Xreturn-value-checker in disabled state.
```

(Message verified with 2.4.20.) The KEEP says this restriction is
lifted when the feature is stable.

### Named-only: overload resolution is unaffected

The name check happens after resolution:

```kotlin
fun notify(named urgent: Boolean) {} // (1)
fun notify(urgent: Any) {}           // (2)

notify(true)
// resolves to (1), then ERROR: name required,
// even though (2) is applicable
```

The KEEP rejects the alternative (let `named` filter candidates)
for two reasons. First, adopting `named` would silently move calls
to a more general overload instead of flagging them:

```kotlin
class FastString : CharSequence { /* ... */ }

fun FastString.indexOf(
    string: String,
    named startIndex: Int = 0,
    named ignoreCase: Boolean = false,
): Int = TODO()

fun find(s: CharSequence, q: String) {
    if (s is FastString) {
        s.indexOf(q, 0, true)
        // with resolution-affecting named: silently
        // CharSequence.indexOf. With the KEEP: ERROR.
    }
}
```

Second, omitting a name would become a way to pick an overload,
and the KEEP calls it "absurd" to treat a missing name as intent
rather than a mistake.

### Named-only: overrides

A mismatch in `named` between an override and the overridden
parameter is a warning, not an error:

```kotlin
interface Notifier {
    fun send(msg: String, named silent: Boolean)
}

class EmailNotifier : Notifier {
    override fun send(msg: String, silent: Boolean) {}
    // WARNING: 'named' differs from overridden
}
```

The KEEP does not specify which declaration's rule applies at a
call through `EmailNotifier`. My reading: the check uses the
resolved callee, so calls via `Notifier` require the name and calls
via `EmailNotifier` do not, which is exactly why the mismatch is
flagged.

Intersection overrides get `named` only if every inherited
parameter is `named` and has the same name:

```kotlin
interface A {
    fun foo(named p: Int)
    fun bar(named p: Int)
    fun baz(named p: Int)
}
interface B {
    fun foo(named p: Int)
    fun bar(named other: Int)
    fun baz(p: Int)
}
interface C : A, B
// foo(named p: Int)
// bar(<ambiguous>: Int)
// baz(p: Int)
```

### Named-only: where `named` is not allowed

```kotlin
context(named log: Logger)    // ERROR: context param
fun audit() {}

var price: Money = Money.ZERO
    set(named value) {}       // ERROR: setter param

val f: (named Int) -> Unit    // ERROR: function type
```

Allowed: regular function parameters, extension function
parameters, and constructor parameters (including `val`/`var`
ones).

### Named-only: varargs

KEEP-0439 says nothing about `vararg`. This is open. What today's
Kotlin already does with a named vararg (verified with 2.4.20):

```kotlin
fun tag(vararg labels: String, color: String = "red")

tag("a", "b", color = "blue")      // OK
tag(labels = arrayOf("a", "b"))    // OK
tag(labels = *arrayOf("a", "b"))   // OK
tag(labels = "a")
// ERROR: assigning single elements to varargs
// in named form is prohibited
```

So a hypothetical `named vararg labels: String` would force callers
to build an array, losing the main ergonomic benefit of `vararg`
(my reading). KEEP-0193 also forbids naming arguments that map to
a vararg in the middle of a positional call, so the two features
do not obviously compose. Expect this to be settled in discussion.

### Named-only: interaction with KEEP-0193

Since 1.4, you can name any positional, non-vararg argument as long
as it stays in its own position:

```kotlin
fun ship(order: Order, express: Boolean, note: String)

ship(order, express = true, "fragile")   // OK
ship(express = true, order, "fragile")   // ERROR
```

That is what makes named-only parameters in the middle of a list
pleasant:

```kotlin
fun ship(
    order: Order,
    named express: Boolean,
    note: String,
)

ship(order, express = true, "fragile") // OK (my reading)
ship(order, true, "fragile")           // ERROR
```

KEEP-0439 does not discuss this combination explicitly; it follows
from "the argument is passed with name" plus KEEP-0193.

### Named-only: data class `copy()`

All `copy()` parameters are meant to become named-only, in two
phases with no fixed versions:

```kotlin
data class User(val id: Long, val name: String)

user.copy(name = "Ann") // OK in both phases
user.copy(1, "Ann")
// Phase 1: WARNING
// Phase 2: ERROR (unless the constructor has
//          @SoftNamedOnlyParametersCheck)
```

Phase 1 marks `copy()` parameters `named` when compiling data
classes, treats data classes from older compilers as if they were
`named`, and softens the error to a warning. A flag lets you jump
to phase 2; the KEEP gives `-Xnamed-only-parameters-in-data-class-copy`
only as an example ("e.g."), so the final flag name is open.

### Named-only: expect/actual

`named` must match exactly between `expect` and `actual`; a
mismatch is an error. An `expect` with a `named` parameter cannot
be actualized by a Java declaration at all:

```kotlin
// commonMain
expect fun hash(
    data: ByteArray,
    named algorithm: String,
): String

// jvmMain: actualizing via a Java declaration,
// e.g. a typealias to a Java class whose method
// provides hash(...)
// ERROR: Java parameters are never named-only
```

The reason is KT-66205: in some setups common code of a dependent
project can see platform declarations, and it would see a
named-only parameter in one compilation and a positional Java one
in another. The KEEP starts with the strictest rule on purpose.

### How the two features combine

The two guardrails cover the two ends of a call: what goes in and
what comes out.

```kotlin
@MustUseReturnValues
class Ledger {
    fun transfer(
        from: Account,
        to: Account,
        amount: Money,
        named dryRun: Boolean = false,
    ): TransferResult = TODO()
}

ledger.transfer(alice, bob, fee, true)
// ERROR: dryRun must be named
ledger.transfer(alice, bob, fee, dryRun = true)
// WARNING: unused TransferResult
val result =
    ledger.transfer(alice, bob, fee, dryRun = true)
```

The `true` was a boolean you could not read, and the result was a
dry-run outcome you threw away: two independent ways to write a
dry run that looks like a real transfer. Note that `from` and `to`
remain positional. Same-typed adjacent parameters are a strong
candidate for `named` too:

```kotlin
fun transfer(
    named from: Account,
    named to: Account,
    amount: Money,
): TransferResult
```

Some observations on the combination (my reading, neither KEEP
discusses the other):

- They share a migration philosophy. Both have a soft mode (checker
  `check` mode and unspecified ignorability; `@SoftNamedOnlyParametersCheck`)
  so a library can adopt the rule without breaking consumers.
- They differ in severity. Unused results are warnings. Missing
  names are errors. A missing name is unambiguous; an unused result
  sometimes is intended, hence `val _`.
- They differ in default. The checker inverts the default
  (everything must-use, exceptions annotated). `named` keeps the
  default (flexible), exceptions marked. The KEEP explicitly
  rejected named-by-default.
- Both are stored in Kotlin metadata, not in the JVM signature, so
  neither affects Java callers at all.
- The `SoftNamedOnlyParametersCheck` declaration itself uses
  `named val ideOnlyDiagnostic`, so it dogfoods the feature.

## Platform interop

### Checker: how a library opts in

The KEEP first considered annotations everywhere, then chose a
Kotlin metadata flag. The compiler sets it on every callable it
compiles in `full` mode, and only on annotated declarations in
`check` mode:

```text
mode     local warnings      metadata flag set on
disable  none                nothing
check    marked APIs only    @MustUseReturnValues scopes
full     all non-ignorable   every callable
```

Consumers in `check` mode then get warnings for that library with
no further configuration. The flag can be read with
`kotlin-metadata-jvm` if you write your own analyzer.

The migration loop the KEEP describes:

1. Library author annotates `@IgnorableReturnValue` where needed.
2. Releases a new, "RVC-approved" version (compiled in `full`).
3. Clients enable the checker and see misuse warnings.
4. Clients annotate their own code and release RVC-approved
   versions in turn.

`kotlin-stdlib` and "some kotlinx libraries" are RVC-approved from
the start. When the feature goes stable, `check` becomes the
default, so every Kotlin user benefits from every opted-in library
automatically.

### Checker: binary compatibility

```kotlin
// library compiled with -Xreturn-value-checker=full
fun parse(raw: String): Order = TODO()
```

- Metadata is compatible both ways. You can switch modes freely.
- `full` does not make the compiler emit pre-release binaries.
- Consumers with the feature disabled see no difference.
- Adding or removing `@IgnorableReturnValue` changes no JVM
  signature (BINARY retention, metadata only). It is a source
  change for consumers only in the sense of warnings appearing or
  disappearing (my reading).

### Checker: Java annotations

These Java annotations are treated like `@MustUseReturnValues`:

```text
com.google.errorprone.annotations.CheckReturnValue
edu.umd.cs.findbugs.annotations.CheckReturnValue
org.jetbrains.annotations.CheckReturnValue
org.springframework.lang.CheckReturnValue
org.jooq.CheckReturnValue
```

And this one like `@IgnorableReturnValue`:

```text
com.google.errorprone.annotations.CanIgnoreReturnValue
```

So Guava, already annotated with ErrorProne's annotations, is
checked from Kotlin:

```java
import org.jetbrains.annotations.CheckReturnValue;

@CheckReturnValue
public class Prices {
    public static long withVat(long cents) {
        return cents + cents * 21 / 100;
    }
}
```

```kotlin
fun main() {
    Prices.withVat(100)
    // WARNING: unused return value of 'withVat'.
}
```

Verified with `kotlinc` 2.4.20 in `check` mode. The KEEP notes most
Java libraries lack an "explicitly ignorable" annotation and put
`@CheckReturnValue` per method, so for Kotlin code it asks you to
use the Kotlin annotations or `full` mode. A
[JSpecify proposal](https://github.com/jspecify/jspecify/issues/200)
could eventually give mixed Java/Kotlin projects one vocabulary.

### Checker: what Java callers see

Nothing. Java has no unused-result check of its own, and the Kotlin
annotations have BINARY retention, so they are in the class file
but invisible to reflection. Whether ErrorProne or IntelliJ's Java
inspections read `kotlin.IgnorableReturnValue` is up to those tools;
the KEEP only hopes linters will recognize both sets (open).

```java
// Java caller of a Kotlin full-mode library
Order o = Orders.parse(raw);  // fine
Orders.parse(raw);            // no Kotlin warning here
```

### Named-only: what Java callers see

`named` does not change how a function is exported. Java passes
everything positionally, as it always does:

```kotlin
fun charge(
    amount: Long,
    named capture: Boolean,
): Receipt = TODO()
```

```java
Receipt r = PaymentsKt.charge(1999L, true); // fine
```

The guardrail only exists for Kotlin callers. If Java callers
matter, keep the parameter order readable anyway, or offer Java
a builder (my reading).

### Named-only: binary shape, ABI and reflection

- `named` is stored in Kotlin metadata. Nothing else in the
  compiled output changes. Same JVM descriptor, same `$default`
  synthetic, same parameter names.
- Adding `named` is therefore binary compatible: old compiled
  callers keep linking (my reading of "doesn't affect the output
  artifact").
- It is a source-breaking change for Kotlin callers who pass the
  argument positionally. That is what
  `@SoftNamedOnlyParametersCheck` is for.
- Removing `named` is source and binary compatible (my reading).
- Renaming a parameter was always source-breaking for named
  callers. With `named`, every caller is a named caller, so a
  rename breaks all of them (my reading). Parameter names become
  real API.
- Reflection: `KParameter` gets `isNamedOnly: Boolean`.

```kotlin
val p = ::charge.parameters[1]
println(p.isNamedOnly) // prints: true (proposed)
```

### Named-only: KMP

Strict `expect`/`actual` matching, no actualization to Java when
`named` is present. JS, Native and Wasm are not mentioned
separately; since the modifier only lives in metadata and is
checked in the frontend, nothing platform-specific is expected (my
reading). The same holds for the checker: it is a frontend
diagnostic, and the KEEP's only platform-specific rules are the JVM
ones (Java types and annotations).

## Design decisions

### Checker: inverted default, like Swift

The KEEP's data: only about 15% of non-Unit functions return a
value it is fine to drop. Putting `@CheckReturnValue` on the other
85% would mean annotating most of the stdlib. So Kotlin follows
Swift's `@discardableResult` model rather than Rust's `#[must_use]`
or C++'s `[[nodiscard]]`:

```kotlin
// Rejected: opt-in per function (ErrorProne style)
@CheckReturnValue fun trim(): String

// Chosen: must-use by default, exceptions marked
@IgnorableReturnValue fun add(e: E): Boolean
```

### Checker: unspecified as a migration state

Flipping the default for all code at once would flag every Netty
`ByteBuf.clear()` call, a library that will never carry Kotlin
annotations. The three-state model (non-ignorable, ignorable,
unspecified) and the `check`/`full` split let the ecosystem migrate
library by library.

### Checker: metadata flag, not annotations everywhere

"The initial idea was to use annotations everywhere", but the KEEP
settled on a compiler-set metadata flag controlled by the mode.
`@MustUseReturnValues` remains for partial migration.

### Checker: no FUNCTION target on `@MustUseReturnValues`, no constructor/property target on `@IgnorableReturnValue`

Both restrictions push design. The first nudges authors to decide
for a whole class or file. The second refuses to bless side-effecting
constructors and property getters.

```kotlin
@IgnorableReturnValue      // ERROR: wrong target
val nextId: Long get() = counter++
```

### Checker: `let` is ignorable for now

Making HOFs propagate needs a new contract kind. Until then the
KEEP accepts false negatives in `let` over false positives
everywhere.

### Underscore: `val _ =` over `_ =`

Covered in Rules: alignment with destructuring and avoiding
confusion with `_` lambda parameters.

### Named-only: modifier, not annotation

```kotlin
fun f(@NamedOnly flag: Boolean)   // rejected
fun f(named flag: Boolean)        // chosen
```

The KEEP's reasons: cleaner, clearly distinct from user-defined
annotations, and meant to be broadly used rather than tied to a
domain (unlike `@DslMarker` or `@BuilderInference`).

### Named-only: per-parameter modifier, not a "fence"

Python and Julia use a separator after which all parameters are
keyword-only. The Kotlin version would look like:

```kotlin
// Rejected
fun CharSequence.startsWith(
    char: Char, *, ignoreCase: Boolean = false,
)
```

A fence is nicer for Compose's `TextStyle` with 25 parameters, but
it assumes named-only parameters are contiguous and at the end. Two
use cases break that: DSLs with named options followed by a
trailing lambda, and named first parameters such as
`fold(named to: M, ...)`.

### Named-only: not the default

Swift labels every argument by default. The KEEP judges flexible
parameters the most commonly desired kind, "it's not our goal to
migrate a whole world", and migrating such core functionality would
be onerous.

### Named-only: does not affect resolution

Covered in Rules: silent re-resolution to a more general overload,
and absurd "drop the name to pick an overload" semantics.

### Named-only: strict expect/actual

Starting strict is the conservative choice given KT-66205. It can
be relaxed later; the opposite would be a breaking change (my
reading).

## Open questions and what may change

Checker:

- Gradle DSL for the mode: "stay tuned". Today it is
  `freeCompilerArgs`.
- Default becomes `check` when stable; date not given.
- Annotations usable in disabled mode once stable.
- A contract to make HOFs like `let` propagating; depends on
  contracts maturing.
- Which kotlinx libraries are RVC-approved: "some".
- Reporting values that are only "type consumed" (Elvis left side):
  the formal appendix says "we may want to".
- Overriding ignorable with must-use: the KEEP says not allowed,
  2.4.20 reports a warning. Severity may change.
- JSpecify adoption for Java.

```kotlin
// may get a contract instead of being ignorable
user?.let { "Dear " + it.name } // OK today
```

Named-only parameters:

- Status is public discussion. No version, no flag to enable it.
- Annotation name: `SoftNamedOnlyParametersCheck` vs
  `SoftNamedOnlyParameterCheck`.
- `copy()` migration flag name is only an example; phases have no
  timeline.
- `vararg` parameters are not addressed.
- Call-through-override semantics with a mismatched `named` is not
  spelled out.
- IDE quick fix "add argument names" is required, details open.

```kotlin
// unresolved by the KEEP
fun log(named vararg tags: String)
```

## Cheat sheet

```kotlin
// -Xreturn-value-checker=disable|check|full
@file:MustUseReturnValues

class Cart {
    @IgnorableReturnValue
    fun add(i: Item): Boolean = TODO()
    fun total(): Money = TODO()
}

cart.add(book)           // OK
cart.total()             // WARNING
val _ = cart.total()     // OK, deliberate
cart.isEmpty() || return // OK, Nothing on rhs
count++                  // OK

// Proposed, KEEP-0439
fun charge(
    amount: Money,
    named capture: Boolean = true,
    named onDone: () -> Unit = {},
)
charge(fee, false)            // ERROR
charge(fee, capture = false)  // OK
charge(fee) { }               // ERROR: no trailing
```

Unused return value checker:

- Experimental since 2.3. `check` warns on marked APIs (stdlib,
  opted-in libraries, `@MustUseReturnValues`). `full` also makes
  your own code must-use and publishes that in metadata.
- Used = initializer, `return`/`throw`, argument, receiver,
  condition, last lambda statement.
- Ignorable: `Unit`, `Nothing`, `Nothing?` (not `Unit?`),
  `++`/`--`, `&&`/`||` with `Nothing` on the right,
  `@IgnorableReturnValue`, unspecified (most JDK).
- Propagating: `if`/`when` branches, both sides of `?:`, `try` and
  `catch` (not `finally`), `as`, `as?`, `is`, `!!`.
- Overrides inherit; cannot go ignorable to must-use; can go the
  other way. Expect/actual must agree.
- ErrorProne/FindBugs/JetBrains/Spring/jOOQ `@CheckReturnValue`
  and ErrorProne `@CanIgnoreReturnValue` are honoured.

Named-only parameters:

- Public discussion only. `named` soft modifier on value and
  constructor parameters. Not on context, setter or function-type
  parameters.
- Positional use is an error; omitting a defaulted one is fine.
- No trailing lambda for a `named` function parameter.
- No effect on overload resolution. Override mismatch is a
  warning. Expect/actual must match exactly.
- Metadata only: Java calls positionally; JVM signature unchanged;
  `KParameter.isNamedOnly`.
- `@SoftNamedOnlyParametersCheck(ideOnlyDiagnostic)` for
  migration. Data class `copy()` will become named-only in two
  phases.

## Talking points

- "Kotlin now flips the default: if a function returns something,
  you're expected to use it. The exceptions get an annotation."
- "`val _ =` isn't a suppression, it's a declaration. Reviewers see
  you meant to drop it."
- "Turn on `check` today and you get warnings for the whole stdlib
  for free. Your own code joins with `full`."
- "For a library, `full` mode is a publishing decision: it writes
  'must use' into your metadata for every consumer."
- "`foo() ?: return` throws away `foo()`. The checker will tell
  you."
- "Named-only parameters let the library, not the linter config,
  decide which arguments need a name. Still a proposal."
- "`named` never changes which overload you call. It only refuses
  to compile when the name is missing."
- "Java callers don't see either guardrail. Both live in Kotlin
  metadata."

Tricky questions:

**"Why is `java.io.File.delete()` not flagged, if it's the KEEP's
own example of a bad API?"** JDK methods are "unspecified" during
migration, so the checker stays quiet on them. Only the Kotlin
counterparts and annotated or RVC-approved code warn. The example
illustrates the goal, not the current coverage.

```kotlin
File("tmp").delete()  // OK: JDK is unspecified
```

**"My override of an ignorable method returns something important.
Can I make it must-use?"** No. If `Base.save()` is ignorable and
`Derived.save()` were must-use, the warning would appear or vanish
depending on the static type, which breaks substitutability. The
KEEP forbids it (2.4.20 warns). The reverse, must-use to ignorable,
is allowed.

```kotlin
@MustUseReturnValues
class DbRepo : Repo {
    override fun save(o: Order) = true // WARNING
}
```

**"If I add `named` to a published function, do I break my
users?"** Not binary: the JVM signature is unchanged and only
metadata records the modifier. It is source-breaking for Kotlin
callers who pass it positionally, which is why the KEEP proposes
`@SoftNamedOnlyParametersCheck` to ship it as a warning first (and
optionally IDE-only). Java callers are unaffected.

```kotlin
@SoftNamedOnlyParametersCheck
fun search(q: String, named fuzzy: Boolean = false)
search("kotlin", true) // WARNING, not ERROR
```
