---
title: "Rich Errors"
subtitle: "Recoverable failures as T | E: no wrapper, no exception, checked by the type system"
author: "Notes from KEEP-0462, KEEP-0441"
date: "October 2026"
lang: en
---

## At a glance

| Document | Status | Role |
|---|---|---|
| [KEEP-0462](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0462-rich-errors.md) | Public discussion | Formal design |
| [KEEP-0441](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0441-rich-errors-motivation.md) | Design review | Motivation, first draft |
| Design note 0009 | Discussion #498 | Real-world use cases |

- YouTrack: [KT-68296](https://youtrack.jetbrains.com/issue/KT-68296).
  Discussions: #447 (motivation), #487 (design), #498 (use cases).
- Authors: Michail Zarečenskij and Roman Venediktov, with
  Alejandro Serrano Mena, Marat Akhin and Ross Tate.
- Kotlin version: none. Neither KEEP names a release, a
  compiler flag or an opt-in annotation. Treat it as a design
  under public discussion, not as something you can try in
  2.4.20.
- Depends on two other KEEPs: the unused return value checker
  ([KEEP-0412](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0412-unused-return-value-checker.md),
  Experimental in 2.3), which turns an ignored union result
  into a compile error, and data-flow-based exhaustiveness
  ([KEEP-0442](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0442-dfa-exhaustiveness.md),
  Stable in 2.3.0).
- Goals: put errors in signatures, end the "is `null` a value or
  a failure?" ambiguity, keep inference polynomial, separate
  recoverable errors from exceptions.
- Non-goals: general union types, checked exceptions.

The teaser:

```kotlin
error object NotFound

fun load(id: UserId): User | NotFound

when (val user = load(id)) {
    is User -> println("Hello, ${user.name}")
    is NotFound -> println("Not found!")
}
```

## The problem

KEEP-0441 starts from two questions: how do I say a function can
fail, and how do I handle it when it does? Kotlin has unchecked
exceptions and no dedicated construct for recoverable errors. So
every codebase grows its own dialect.

### Exceptions are fine, for what they are good at

The KEEP keeps exceptions for two jobs:

1. **Preconditions.** `require(name.isNotBlank())` patches a gap
   in the type system. You do not recover from a blank user name
   any more than from passing an `Int` where a `String` was
   expected.
2. **Non-local handling.** Spring's `@ResponseStatus` or an
   IntelliJ framework handler catches far from the throw site.
   Nobody in between wants to see it.

```kotlin
fun register(name: String): User {
    require(name.isNotBlank()) { "blank name" }
    // a bug at the call site, not a domain outcome
    return User(name)
}
```

Rich errors do not touch either case. The problem is everything
else: failures the caller is *expected* to handle.

### `null` is concise but ambiguous

```kotlin
fun <T> List<T>.firstOrNull(): T?

val users: List<User?> = loadSlots()
val first = users.firstOrNull()
if (first == null) {
    // empty list, or a null first slot?
}
```

`null` carries no reason. Chains erase the origin too:

```kotlin
fun fetch(id: UserId): User?
fun User.charge(amount: Money): Transaction?

val tx = fetch(id)?.charge(amount)
if (tx == null) {
    // fetch failed, or charge failed?
}
```

### Sealed hierarchies are precise but expensive

```kotlin
sealed interface ChargeResult {
    data class Success(val tx: Transaction) : ChargeResult
    data object CardDeclined : ChargeResult
    data class RateLimited(
        val retryAfter: Duration,
    ) : ChargeResult
}
```

`Success` is a wrapper that adds no information and allocates.
Every call site needs a `when` to unwrap it, or a set of
hand-written `map`/`flatMap` operators. And because sealed
subclasses belong to one parent, shared cases get redeclared. In
Signal's registration API (design note 0009) `InvalidRequest` is
declared 11 times and `RateLimited` 9 times, one per endpoint
hierarchy. You cannot write `fun handle(e: RateLimited)` that
works for all endpoints, because there is no common type.

The counts in the note: DuckDuckGo-Android has 75 custom
`sealed ...Result/Error/Failure` types, Signal 125, AnkiDroid 18,
IntelliJ IDEA Ultimate 552. None of the three Android apps uses
Arrow.

### `kotlin.Result` was never meant for this

`Result<T>` exists for `Continuation.resumeWith`. It is a value
class, not sealed, so `isSuccess` does not smart cast. It has one
type parameter and the failure is always a `Throwable`.

```kotlin
fun getUser(): Result<User> {
    val raw = fetchUserResult()
        .getOrElse { return Result.failure(it) }
    val user = raw.parseUserResult()
        .getOrElse { return Result.failure(it) }
    return Result.success(user)
}
```

Three business calls, most of the code is plumbing. KEEP-0441
also records history: Kotlin once banned `?.`, `?:` and `!!` on
`Result` to repurpose them later, then dropped the idea because
binding `Result` to exceptions (for example mapping Java
`throws` clauses to it) got too complicated.

### Third-party wrappers

Arrow's `Either`, and dozens of internal `Result` types in the
Kotlin compiler and IntelliJ, show the demand. They also show
that one generic wrapper never quite fits: Signal's own 469-line
`NetworkResult` says in its KDoc that complicated requests are
"better off writing your own sealed class".

The KEEP's summary: Kotlin has no first-class way to say "this
function can fail in a recoverable way", so APIs fragment.

## The feature, step by step

### Step 1: declare an error type

A new soft keyword, `error`, goes in front of `class` or
`object`:

```kotlin
error object NotFound
error object PermissionDenied
error class NetworkError(val code: Int)
error class RateLimited(val retryAfter: Duration)
```

Every error class and object gets compiler-generated `equals`,
`hashCode` and `toString`. The KEEP lists exactly those three; it
does not mention `copy` or `componentN`, so do not assume an
error class is a data class.

Error types can have members and nested declarations. The KEEP's
appendix shows a function in an error object body, and the
design note nests a sealed class inside an error class:

```kotlin
error class CaptchaFailure(
    val code: Int,
    val kind: Kind,
) {
    sealed class Kind {
        data object NotReady : Kind()
        data object Transient : Kind()
    }
}
```

### Step 2: return a union

`|` combines one value type with one or more error types:

```kotlin
fun loadUser(id: UserId): User | NotFound | PermissionDenied
```

Before and after, using AnkiDroid's three-way result from the
design note:

```kotlin
// Before
sealed class SaveNoteResult {
    data object Success : SaveNoteResult()
    data class Failure(val msg: String?) :
        SaveNoteResult()
    data class Warning(val msg: String?) :
        SaveNoteResult()
}

// After
error class SaveFailure(val msg: String?)
error class SaveWarning(val msg: String?)

suspend fun saveNote(): Unit | SaveFailure | SaveWarning
```

`Unit` is the success marker. The note suggests
`typealias Ok = Unit` if that reads better.

### Step 3: handle it with `when`

Error types and the value type are disjoint, so `is` checks
split the union cleanly and the `when` is exhaustive without
`else`:

```kotlin
when (val r = loadUser(id)) {
    is User -> greet(r)
    is NotFound -> respond(404)
    is PermissionDenied -> respond(403)
}
```

Smart casts inside each branch work exactly as for sealed types,
because a smart cast is a type intersection:
`(User | NotFound) & NotFound` is `NotFound`.

### Step 4: name a set of errors with a type alias

Error types cannot inherit, so composition goes through
`typealias`:

```kotlin
typealias UserFetchError = NotFound | PermissionDenied

fun loadUser(id: UserId): User | UserFetchError
fun loadOrder(id: OrderId): Order | UserFetchError
```

An alias is substituted as written, then the whole type is
normalized (duplicates removed). So
`User | UserFetchError | NotFound` is `User | NotFound |
PermissionDenied`.

### Step 5: chain with `|.`

The error-safe-call operator `|.` is to `T | E` what `?.` is to
`T?`:

```kotlin
val r = foo()|.bar()
// means
val tmp = foo()
val r = if (tmp is Error) tmp else tmp.bar()
```

The error types of the chain accumulate in the result type:

```kotlin
error object NoUser
error object Declined

fun fetch(id: UserId): User | NoUser
fun User.charge(m: Money): Transaction | Declined

fun pay(id: UserId, m: Money) {
    // Transaction | NoUser | Declined
    when (val tx = fetch(id)|.charge(m)) {
        is Transaction -> println("paid ${tx.id}")
        is NoUser -> println("no such user")
        is Declined -> println("card declined")
    }
}
```

Compare with the `null` version in "The problem": same chain
length, but the origin of the failure survives.

### Step 6: bail out early with `ifError`

There is no Elvis for errors. Instead the standard library gets
`ifError`, and a lambda that returns `Nothing` (a `return`, a
`throw`) smart casts the receiver to the value type afterwards:

```kotlin
fun greeting(id: UserId): String | UserFetchError {
    val user = loadUser(id).ifError { return it }
    // user: User
    return "Hello, ${user.name}"
}
```

Or recover with a fallback value:

```kotlin
val user: User = loadUser(id).ifError { Guest }
```

### Step 7: escalate to an exception

When an error is impossible in context, turn it into a crash:

```kotlin
val user: User = loadUser(adminId).throwIfError()
// throws KotlinErrorException(NotFound) on failure
```

`throwError()` on any `Error` throws `KotlinErrorException`
wrapping the error value.

### Step 8: the compiler will not let you drop it

Together with the unused return value checker (KEEP-0412), an
ignored union result is a compile error:

```kotlin
fun audit(id: UserId) {
    loadUser(id) // ERROR: result must be used (KEEP-0412)
}
```

The KEEP says "the compiler will report an error if such a
result is ignored". It does not give the diagnostic text, so the
message above is mine.

## Typical usage

### Replace `null` where `null` is also a value

The KEEP's own examples for the standard library:

```kotlin
error object NotPresent
error object InvalidFormat

operator fun <K, V> Map<K, V>.get(
    key: K,
): V | NotPresent

fun String.toInt(): Int | InvalidFormat
```

Note: 0462 writes `String.toInt()` while 0441 writes
`toIntOrError()`. The migration section says the standard
library gains `XOrError` alternatives next to the existing
nullable and throwing versions. Read the 0462 snippet as a shape,
not as a final stdlib name.

### A service layer with shared error vocabulary

The Signal example from the design note, condensed. One
declaration per distinct error, aliases per endpoint:

```kotlin
error class InvalidRequest(val message: String)
error class RateLimited(val retryAfter: Duration)
error object Unauthorized
error class NetworkFailure(val cause: IOException)
error class Unexpected(val cause: Throwable)

typealias Transport = NetworkFailure | Unexpected
typealias CreateSessionError =
    InvalidRequest | RateLimited

suspend fun createSession(
    phone: String,
): Session | CreateSessionError | Transport
```

Transport and domain errors sit at the same level, so there is
one `when` instead of the nested `RequestResult` dispatch Signal
has today. And a shared handler is now expressible, because a
union of *only* errors is a valid parameter type:

```kotlin
fun RegistrationState.onTransport(
    e: NetworkFailure | Unexpected,
): RegistrationState = when (e) {
    is NetworkFailure -> copy(event = NetworkError)
    is Unexpected -> copy(event = UnknownError)
}
```

No sealed class can do this without a common supertype declared
in advance.

### Precise result types per operation

DuckDuckGo shared one `CaptchaResolverResult` between two
functions, so every caller had a dead branch. With unions each
function states its own contract:

```kotlin
// Before: both return CaptchaResolverResult
// After:
suspend fun submitCaptcha(
    info: CaptchaInfo,
): TransactionId | CaptchaFailure

suspend fun captchaSolution(
    id: TransactionId,
): CaptchaSolution | InProgress | CaptchaFailure
```

`InProgress` as an error member turns the polling loop into an
`is InProgress ->` branch.

### A linear pipeline in one function

DuckDuckGo's bookmark import used `runCatching`, a custom
`ExtractionResult` and an `ImportSavedSitesResult`, plus a fourth
sealed type just to translate between them. With unions:

```kotlin
suspend fun downloadZip(url: String): Uri | DownloadFailed
suspend fun extract(zip: Uri): TempFile | ParseFailed
suspend fun import(f: TempFile): List<Site> | ImportFailed

suspend fun importTakeout(
    url: String,
): Int | DownloadFailed | ParseFailed | ImportFailed {
    val zip = downloadZip(url).ifError { return it }
    try {
        val file = extract(zip).ifError { return it }
        return import(file)|.let { it.size }
    } finally {
        cleanup(zip)
    }
}
```

The return type is the sum of the stages. Add an error to a
stage and the compiler makes you handle it or widen the
signature.

### Replace an out-callback with the return type

AnkiDroid's `onPaste` returned `String?` and reported the reason
through a `showError` callback; nothing tied the two together.

```kotlin
// Before
fun onPaste(
    uri: Uri,
    showError: (MediaError) -> Unit,
): String?

// After
fun onPaste(uri: Uri): String | MediaError

// Call site
val tag = onPaste(uri).ifError { e ->
    snackbar(e.describe())
    return false
}
insert(tag)
```

### Internal tags inside an algorithm

An error object can be a private sentinel. Because the tag is
internal, no caller value can collide with it:

```kotlin
@PublishedApi
internal error object NotFoundYet

inline fun <T> Sequence<T>.last(
    predicate: (T) -> Boolean,
): T {
    var last: T | NotFoundYet = NotFoundYet
    for (e in this) if (predicate(e)) last = e
    if (last == NotFoundYet) throw NoSuchElementException()
    return last // smart cast to T
}
```

Today's version needs a `T?` plus a `found` flag plus
`@Suppress("UNCHECKED_CAST")`. The tag version needs none of
them.

### Coroutines

The KEEP has no coroutines section. What follows combines the
design note's examples (which use `suspend` freely) with my
reading of the type rules.

A `suspend` function returns a union like any other function:

```kotlin
suspend fun fetchOrder(
    id: OrderId,
): Order | NotFound | NetworkFailure
```

Early return out of `withContext` uses a labelled return, as in
the design note:

```kotlin
suspend fun total(id: OrderId): Money | NotFound =
    withContext(Dispatchers.IO) {
        val order = repo.find(id)
            .ifError { return@withContext it }
        order.lines.sumOf { it.price }
    }
```

Because unions are allowed as type arguments (the KEEP itself
uses `List<String | MyError>`), `async` should infer a union
`Deferred` (my reading):

```kotlin
coroutineScope {
    val user = async { loadUser(id) }
    val cart = async { loadCart(id) }
    // Deferred<User | NotFound>
    // Deferred<Cart | CartLocked>
    val u = user.await()
        .ifError { return@coroutineScope it }
    val c = cart.await()
        .ifError { return@coroutineScope it }
    Checkout(u, c)
}
```

Three consequences worth knowing (my reading, not KEEP text):

- An error value is a return value, not a throwable. Returning
  `NotFound` from a child coroutine does not cancel its siblings
  or the parent scope. If you want fail-fast cancellation, use
  `throwIfError()`, which throws `KotlinErrorException` and
  cancels like any exception.
- No catch-all is involved, so the well-known trap of
  `runCatching` swallowing `CancellationException` does not
  exist on the error path.
- `Flow<Price | Stale>` is just a flow of values; `|.` and `when`
  work per element.

## Rules and edge cases

### Error types: what an `error` declaration may not do

The KEEP: error types **cannot** have superclasses,
superinterfaces or generic parameters. They form a flat
hierarchy so that unions stay disjoint.

```kotlin
error class Timeout(val after: Duration)

error class HttpError(val code: Int) : Exception()
// ERROR: error types cannot have superclasses

error object Offline : Retryable
// ERROR: error types cannot have superinterfaces

error class Failed<C>(val cause: C)
// ERROR: error types cannot be generic
```

The diagnostic texts are mine; the rules are the KEEP's.

The no-generics rule is the one an Arrow user hits first. KEEP-0441
says it directly: wrappers with two type parameters (`Either`)
cannot be represented by an error type, and the restriction
exists "to keep unions tractable and prevent exponential type
inference". Generic *functions* over errors are fine (see
Generics below); generic *error classes* are not.

What you can do is put any data, including a sealed non-error
hierarchy, inside an error class (Example 5 in the design note):

```kotlin
sealed interface Field
data object Email : Field
data object Age : Field

error class Invalid(val fields: List<Field>)
```

### The type hierarchy: `Error`, `Value`, `Any`

```text
             Any?
           /      \
       Value?      Any
        |    \    /   \
        |    Value     Error
        |      |        |
       Int?   Int    ParseError
          \    |      /
             Nothing
```

- Every error type implicitly extends the abstract class
  `kotlin.Error`.
- `Error` cannot be extended explicitly. Being an `Error` is
  therefore a runtime characteristic: `x is Error` is a real
  `instanceof` check.
- `Error` is a subtype of `Any`. `Any?` stays the top type.
- A new type `Value` is the supertype of all non-error types. It
  looks like an interface in source but does not exist at
  runtime; the compiler treats it specially, like `Nothing`.
  `x is Value` compiles to `x !is Error`.

```kotlin
fun describe(x: Any) = when (x) {
    is Value -> "plain value" // runtime: x !is Error
    is Error -> "error"
}
```

That last `when` being exhaustive is my reading. It follows from
`Any` splitting into `Value` and `Error`, but the KEEP does not
show it.

Two naming traps the KEEP flags itself:

- `kotlin.Error` here "is not related to `java.lang.Error` in
  any way". Today `kotlin.Error` is a stdlib type alias for
  `java.lang.Error` on the JVM. The KEEP does not say how that
  name collision is resolved (my observation; open).
- `Value` versus `value class` is acknowledged as confusing; a
  better name is an open question.

Subtyping between unions follows set inclusion, as the KEEP's
diagram shows:

```kotlin
val a: Int | ParseError = 42
val b: Int | ParseError | Timeout = a  // wider: OK
val c: Int? | ParseError = a           // nullable: OK
val d: Value | ParseError = a          // OK
val e: Int | Error = b                 // OK
val f: Any = e                         // OK
val g: Int | ParseError = b
// ERROR: type mismatch, Timeout is not covered
```

### Where a union may appear

The KEEP's examples put unions in:

```kotlin
// return types
fun parse(s: String): Money | InvalidFormat

// parameter types, including error-only unions
fun log(e: NetworkError | ValidationError)

// local variables
var last: Order | NotFoundYet = NotFoundYet

// type arguments
fun save(rows: List<Row | Skipped>)

// receiver types and function types
fun <T : Value?, E : Error> (T | E).orNull(): T? =
    ifError { null }

// type aliases
typealias FetchError = NotFound | PermissionDenied
```

The JVM section also mentions classes "that use union types as
bounds for their type parameters", so unions are allowed in
upper bounds.

`orNull` above is my own helper, not a proposed stdlib function.

### Where a union may not appear, or what it may not contain

**Only one non-error type, and it goes leftmost.** This is the
non-goal "no full-blown union types" made concrete:

```kotlin
fun id(): Int | String
// ERROR: only one non-error type per union

fun load(): NotFound | User
// ERROR: the non-error type must be leftmost

fun ok(): User | NotFound | PermissionDenied // OK
```

**Error components are never nullable.** The value component
can be:

```kotlin
fun find(): String? | NetworkError  // OK
fun bad(): String | NetworkError?
// ERROR: nullable error type in a union
```

Open: whether a nullable error type *on its own*
(`val e: NetworkError?`) is allowed. The KEEP notes it could be
read as `Nothing? | NetworkError` and leaves it undecided.

**No union without errors.** A union needs at least one error
type. An error-only union is fine:

```kotlin
fun report(e: Timeout | Offline)  // OK, no value type
```

**Repeated components are normalized** and "a diagnostic might
be reported" when written explicitly:

```kotlin
fun f(): Int | Timeout | Timeout
// WARNING (possibly): repeated component; type is
// Int | Timeout
```

**Local error declarations.** KEEP-0441 declared
`error object NotFound` inside an inline function body. KEEP-0462
replaced that example with a top-level `@PublishedApi internal
error object`. Whether local error declarations are allowed is
not stated in 0462 (open; my guess is the change is because a
public inline function cannot expose a local class).

### Generics: at most one error type parameter per union

Inference has to stay polynomial and unambiguous. The rule: in a
single union, there may be only one type parameter that can
range over errors.

```kotlin
// OK: E is the only error parameter
fun <E : Error> retry(
    op: () -> (Order | E),
): Order | E

// OK: T bounded by Value?, disjoint from E
fun <T : Value?, E : Error> recover(x: T | E): T

// OK: plain T is not a union at all
fun <T> identity(x: T): T

fun <E1 : Error, E2 : Error> both(x: Int | E1 | E2)
// ERROR: E1 and E2 are not disjoint

fun <T, E : Error> loose(x: T | E)
// ERROR: T (bound Any?) may contain errors,
// so T and E are not disjoint
```

The fix for the last one is always the same: bound the value
parameter with `Value?` (or `Value`).

Note what is *not* an error: a default-bound `T` combined with a
concrete error type. The KEEP's own `firstOrError` does this:

```kotlin
fun <T> List<T>.firstOrError(): T | NoSuchElement // OK
```

That compiles, but call sites can get the traceability warning
described below.

### Generic code sees errors as ordinary `Any`

Because `Error : Any`, every existing generic API accepts errors
with no change:

```kotlin
val seen: Set<Any> = setOf(Timeout, Offline)
val results: List<Order | NotFound> =
    ids.map { repo.find(it) }
val failures = results.filterIsInstance<NotFound>()
```

This is the main design decision of 0462 (see Design decisions):
`List<T>`, `map`, `filter`, `HashMap` work over errors for free.

### `ifError` in detail

The proposed stdlib functions, verbatim apart from line breaks:

```kotlin
inline fun <T : R, R : Value?, E : Error, ER : Error>
    (T | E).ifError(
        onError: (E) -> (R | ER),
    ): R | ER

inline fun <T : Value?, E : Error>
    (T | E).ifError(onError: (E) -> Nothing): T

fun Error.throwError(): Nothing

fun <T : Value?, E : Error>
    (T | E).throwIfError(): T
```

Both `ifError` overloads have contracts: `callsInPlace(onError,
AT_MOST_ONCE)` and "`this is Error` holds in `onError`". The
`Nothing` overload adds `returns() implies (this is Value)`, and
`throwIfError` has `returns() implies (this is Value?)`.

The four type parameters of the first overload let the handler
change both sides:

```kotlin
sealed interface Shipping
class Courier : Shipping
class Pickup : Shipping

error object NoAddress
error object Blocked
error object Retry

fun a(s: Courier | NoAddress | Blocked) {
    // T = Courier, R = Shipping, ER = Nothing
    val x: Shipping = s.ifError { Pickup() }
}

fun b(s: Int | NoAddress | Blocked) {
    // T = R = Int, E = NoAddress | Blocked, ER = Retry
    val y: Int | Retry = s.ifError { e ->
        when (e) {
            is NoAddress -> Retry
            is Blocked -> e.throwError()
        }
    }
}

fun c(s: Int | NoAddress) {
    s.ifError { return }   // Nothing overload
    println(s + 1)         // s smart cast to Int
}
```

In `c`, note the smart cast is on `s` itself, through the
contract, not only on the returned value.

### Smart casts: intersections do the work

Why can `ifError` pass `this` (checked against `Error`) to a
parameter of type `E`? Because a Kotlin smart cast intersects:

```text
(T | E) & Error
  ~> (T & Error) | (E & Error)
  ~> Nothing | E
  ~> E
```

The same mechanism narrows to a sub-union through an alias:

```kotlin
typealias FsError =
    FileNotFound | AccessDenied | TooLarge

fun read(p: Path): String | FileNotFound | AccessDenied

fun show(p: Path) {
    val r = read(p)
    if (r is FsError) {
        // r: FileNotFound | AccessDenied
        return
    }
    // r: String
    println(r.length)
}
```

`|.` also feeds data flow. Like `?.`, a successful result
implies a successful receiver:

```kotlin
val user: User | NoUser = fetch(id)
val tx = user|.charge(amount)
if (tx is Error) return
// tx !is Error implies user !is Error
println(user.name) // user smart cast to User
```

### Exhaustiveness and negative information

Exhaustiveness uses the data-flow information from KEEP-0442
(Stable in 2.3.0): a case already excluded need not be repeated.

```kotlin
fun pay(): Receipt | Declined | Timeout

fun checkout() {
    val r = pay()
    if (r is Declined) return
    when (r) {   // no `is Declined`, no else
        is Timeout -> retryLater()
        is Receipt -> show(r)
    }
}
```

*Negative smart casts* go further: after excluding cases, the
variable's *type* shrinks, so you can call members without a
`when`:

```kotlin
val r = pay()
if (r is Declined) return
// r: Receipt | Timeout
if (r is Timeout) return
// r: Receipt
println(r.total)
```

The KEEP warns that negative smart casting is new and complex
for the compiler and "might be delivered later than error
unions themselves". Expect the `when` version to work first.

Two exhaustiveness facts that follow from the hierarchy:

```kotlin
when (val r = loadUser(id)) {
    is User -> greet(r)
    is Error -> fail(r)  // covers every error member
}

when (val r = loadUser(id)) {
    is User -> greet(r)
    is NotFound -> respond(404)
} // ERROR: 'when' must be exhaustive,
  // add 'is PermissionDenied'
```

### No `?.`, `?:` or `!!` for errors

The existing operators keep their exact meaning; they only see
`null`.

```kotlin
val r: User | NotFound = loadUser(id)
r?.name
// ERROR (my reading): NotFound has no 'name';
// '?.' only short-circuits on null
r ?: Guest
// WARNING (my reading): elvis on a non-null type
r!!.name
// ERROR (my reading): '!!' does not remove NotFound
```

The diagnostics are my reading of "existing operators are not
extended"; the KEEP does not list them.

There is no combined `?|.` either. If a union has a nullable
value component, you handle `null` and errors in separate steps:

```kotlin
fun find(): String? | NetworkError

val s = find().ifError { return }
// s: String?
val len = s?.length ?: 0
```

The KEEP's reason: many safe-call variants confuse readers, and
it does not expect null-based and error-based APIs to mix
locally in the long run.

### Error traceability: two call-site warnings

Chains bring back the `null` problem in one case: the same error
type from two steps.

```kotlin
fun resolve(v: UserId): User | AccessDenied
fun User.record(v: UserId): Record | AccessDenied

val r = resolve(v)|.record(v)
// WARNING: AccessDenied may come from two sources
```

The fix is to split the chain:

```kotlin
val user = resolve(v)
if (user is AccessDenied) {
    println("cannot see user"); return
}
val rec = user.record(v)
if (rec is AccessDenied) {
    println("cannot see record"); return
}
```

The second warning is about generics. `firstOrError` on a list
whose element type could *be* `NoSuchElement`:

```kotlin
fun <T> List<T>.firstOrError(): T | NoSuchElement

fun inspect(xs: List<Any>) {
    val x = xs.firstOrError()
    // WARNING: Any is not disjoint from NoSuchElement
}

fun <V> applyFirst(xs: List<V>, f: (V) -> Unit) {
    val x = xs.firstOrError()
    // WARNING: V is not disjoint from NoSuchElement
    if (x is NoSuchElement) return
    f(x)
}
```

If `V` is `NoSuchElement`, an empty list and a list whose first
element is `NoSuchElement` are indistinguishable. The KEEP's fix
avoids the ambiguous call:

```kotlin
fun <V> applyFirst(xs: List<V>, f: (V) -> Unit) {
    val x = if (xs.isNotEmpty()) xs[0] else return
    f(x)
}
```

Both rules, as the KEEP states them:

- For `|.`, the receiver's error component must be disjoint from
  the error component of the called function's inferred return
  type.
- After inference for a generic call, each inferred type
  argument must be disjoint from the rest of every error union
  it participates in, in the substituted signature.

Planned refinements (all tentative):

- **Redundancy exemption.** No warning inside a function whose
  own signature already mixes the same parameter and error,
  because its callers get the warning:

  ```kotlin
  fun <V> List<V>.lastOrError(): V | NoSuchElement =
      asReversed().firstOrError() // intended: no warning
  ```

- **An assumption contract**, syntax explicitly "purely
  illustrative", that pushes the check to callers instead of
  `@Suppress`:

  ```kotlin
  fun <V> List<V>.applyFirst(f: (V) -> Unit) {
      contract {
          assuming<V>().doesNotContain<NoSuchElement>()
      }
      // no warning here; checked at call sites
  }
  ```

- **Exempting type parameters**: no warning when the inferred
  argument is itself a type parameter, if the other options are
  not ergonomic enough.

### Equality and identity

Error objects compare with `==` (the KEEP's `last == NotFound`
example). Error classes get generated `equals`, so two
`RateLimited(5.seconds)` are equal. Since `Error : Any`, errors
work as map keys and set elements.

```kotlin
check(RateLimited(5.seconds) == RateLimited(5.seconds))
val counts = mutableMapOf<Any, Int>()
counts[Timeout] = 1
```

### `is Any` and existing runtime checks

Under the 0441 draft, `x is Any` would have changed behaviour.
Under 0462 it does not: errors are `Any`. What *is* new is code
that receives an error through an `Any`-typed path without
knowing it:

```kotlin
fun render(x: Any?) = x.toString()

render(Timeout) // prints: Timeout (generated toString)
```

This is exactly why `?.` and `!!` cannot be reused; see Design
decisions.

## Comparison with exceptions, Result, sealed types and Arrow

This section is long on purpose: it is the question you will get
most at the booth.

### Exceptions

```kotlin
// Exception style
fun loadUser(id: UserId): User // throws NotFoundException

// Rich error style
fun loadUser(id: UserId): User | NotFound
```

| | Exceptions | Rich errors |
|---|---|---|
| In signature | No (Kotlin) | Yes |
| Must handle | No | Yes, with KEEP-0412 |
| Propagation | Non-local | Explicit: `\|.` or `return` |

The KEEP keeps exceptions for preconditions, bugs and non-local
framework handling, and draws the line at recoverable errors.
It is explicitly not checked exceptions: no `throws` clause, no
`try/catch` at every call site, errors compose through higher
order functions because they are values (`map { load(it) }`
gives `List<User | NotFound>`).

Bridge: `throwIfError()` turns an error into a
`KotlinErrorException`. The KEEP has no stdlib function for the
other direction (catching an exception into an error). Writing
one is a few lines (my helper):

```kotlin
error class Failed(val cause: Throwable)

inline fun <T : Value?> attempt(
    block: () -> T,
): T | Failed = try {
    block()
} catch (e: IOException) {
    Failed(e)
}
```

### `kotlin.Result`

```kotlin
// Result
fun parse(s: String): Result<Money>
parse(s).fold(::show) { e -> log(e) }

// Rich error, KEEP-0441's mapping of Result
error class ExceptionError(val e: Throwable)
fun parse(s: String): Money | ExceptionError
```

`Result` has one type parameter, a `Throwable` failure, no smart
casts, and a dozen combinators. A union has any number of typed
errors, smart casts and `when`. KEEP-0441 sees `Result` as a
coroutine-machinery type and does not plan to extend it.

### Sealed hierarchies

| | Sealed result type | Rich errors |
|---|---|---|
| Success wrapper | Yes, allocated | None |
| Share a case | Redeclare | Reuse the type |
| Combine sets | New hierarchy | `A \| B` or an alias |

What you lose: an error type cannot implement an interface, so
you cannot give all your errors a common `val message`. You can
still put a sealed (non-error) payload inside one error class.

### Arrow `Either<E, A>`

```kotlin
// Arrow
fun loadUser(id: UserId): Either<UserError, User>

// Rich errors
fun loadUser(id: UserId): User | UserFetchError
```

Precise differences:

- **Order.** `Either<E, A>` puts the error left; a union puts the
  value leftmost.
- **Representation.** `Either` allocates a `Left` or `Right`. A
  union is the bare value or the bare error object; only
  primitives box.
- **Error type.** Arrow's `E` is any type, usually a sealed
  interface. A union member must be an `error` declaration: no
  inheritance, no generics. So `UserError` as a sealed interface
  does not port directly; it becomes a type alias of flat error
  types.
- **Combining.** Two `Either`s with different `E` need a common
  supertype or `mapLeft`. Two unions just widen: `fetch(id)|.
  charge(m)` has type `Tx | NoUser | Declined` with no
  declaration.
- **Variance.** `Either<Nothing, User>` is a subtype of
  `Either<UserError, User>` by declaration-site variance. Union
  subtyping is set inclusion, so `User` alone is a subtype of
  `User | NotFound` without any wrapping.
- **Combinators.** `map`, `flatMap`, `mapLeft`, `fold`,
  `getOrElse`. The union has `|.` (≈ `map`/`flatMap`, chosen by
  whether the call returns a union), `ifError` (≈ `getOrElse`,
  `recover`, `mapLeft`), and `when` (≈ `fold`).

```kotlin
// Arrow
val name = loadUser(id)
    .map { it.name }
    .getOrElse { "guest" }

// Rich errors
val name = loadUser(id)|.name.ifError { "guest" }
```

(The second line relies on `|.` working for property access as
for calls; the KEEP shows only calls. My reading.)

Interop (KEEP: "straightforward conversion"), as my own helpers:

```kotlin
fun <A : Value?, E : Error> Either<E, A>.toUnion():
    A | E = when (this) {
    is Either.Left -> value
    is Either.Right -> value
}

fun <A : Value?, E : Error> (A | E).toEither():
    Either<E, A> =
    if (this is Error) Either.Left(this)
    else Either.Right(this) // needs negative smart cast
```

Only `Either`s whose `E` is an error type convert this way.

### Arrow `Raise<E>`

This is the closer match, because both styles work on bare
values in direct style.

```kotlin
// Arrow, context parameters
context(_: Raise<UserFetchError>)
fun loadUser(id: UserId): User

// Rich errors
fun loadUser(id: UserId): User | UserFetchError
```

| Arrow `Raise` | Rich errors |
|---|---|
| `raise(NotFound)` | `return NotFound` |
| `ensure(c) { E }` | `if (!c) return E` |
| `ensureNotNull(x) { E }` | `x ?: return E` |
| `x.bind()` | `x.ifError { return it }` |
| `recover({ f() }) { e -> }` | `f().ifError { e -> }` |
| `withError(::wrap) { f() }` | `f().ifError { wrap(it) }` |
| `either { }` | the function body itself |
| `zipOrAccumulate` | no equivalent |

The real differences:

- **Mechanism.** Arrow's `raise` short-circuits by throwing a
  `RaiseCancellationException` (a `CancellationException`) that
  the `either { }` or `recover` builder catches. That is why
  Arrow warns about catching `CancellationException` inside a
  `Raise` scope and about leaking a `Raise` into a lambda that
  runs later. A union is a plain return value: no exception, no
  scope to leak, nothing for a `catch (e: Throwable)` to
  swallow.
- **Where the error lives.** With `Raise`, the error type is in a
  context parameter and the return type is clean. With unions it
  is in the return type, so it shows up in `map { }`, `async { }`
  and collection types (`List<User | NotFound>`). That is more
  honest and more noisy.
- **Implicit propagation.** Inside a `Raise<E>` scope, calling
  another `Raise<E>` function propagates silently. With unions
  you propagate visibly, with `|.` or `ifError { return it }`.
  (KEEP-0441 notes that a `?`- or `try`-style operator "was
  proposed" and is being explored; 0462 does not include one.)
- **Error widening.** With `Raise`, calling a
  `Raise<Declined>` function from a `Raise<NoUser>` context needs
  `withError` or a common supertype. Unions widen automatically.
- **Accumulation.** Arrow's `zipOrAccumulate`, `mapOrAccumulate`
  and `EitherNel` collect *several error values*. `|.` short
  circuits on the first error; it accumulates *types*, not
  values. Nothing in the KEEP replaces Arrow's accumulation.
- **Error type freedom.** `Raise<E>` accepts any `E`, including
  generic and sealed types. Union members must be flat,
  non-generic `error` types.

## Platform interop

### JVM representation: `Object`, no wrapper

Any union compiles to `java.lang.Object`. Neither component is
boxed, because error types and value types are disjoint and an
`instanceof` check tells them apart. Primitives are the
exception: `Int | ParseError` boxes the `Int` to make the type
reference-based.

```kotlin
fun parse(s: String): Int | ParseError
// JVM: returns Object, either java.lang.Integer
// or a ParseError instance
```

`is Error` compiles to `instanceof` against the runtime
`kotlin.Error` class; `is Value` compiles to `!(x instanceof
Error)`.

### Mangling: hidden from Java

`Object` is useless to a Java caller, and `bar(Object)` would
accept anything. So every function with a union in its signature
is mangled, `<name>-<hash>`, like inline class functions
([KEEP-0104](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0104-inline-classes.md)),
where the hash is over the unerased signature. A hyphen is
not a legal Java identifier, so Java cannot call it.

```kotlin
class UserService {
    fun load(id: String): User | NotFound = TODO()
    fun count(): Int = 0
}
```

What Java sees (my sketch of the mangled shape; the KEEP does
not give a concrete hash):

```java
UserService s = new UserService();
s.count();        // fine
// s.load("42");  // does not exist
// bytecode name is like load-AbCdEf1, not callable
```

Classes that use a union in a type parameter bound have *all*
constructors hidden, plus every method that references those
type parameters. Unions elsewhere hide only the affected
signatures:

```kotlin
class Cache<V : Value | Stale> {  // union in a bound
    fun get(k: String): V = TODO() // hidden
    fun size(): Int = 0            // visible
}
// Java cannot construct Cache at all
```

The KEEP compares this to `Result`, which is not mangled but has
an unsafe signature and is hidden from Java by the IDE.

### Binary compatibility

The hash covers the unerased signature, so changing the set of
errors is binary-incompatible, even behind a type alias:

```kotlin
// v1
typealias LoadError = NotFound
fun load(id: String): User | LoadError

// v2: new hash, old binaries fail to link
typealias LoadError = NotFound | Timeout
```

It is also source-incompatible, because exhaustive `when`s break.
The KEEP mentions a possible alternative hash (only "has a
union", not which) but doubts its value. The intended answer for
evolving APIs is open unions (see Open questions).

### Java interop plugin (planned)

Exposure to Java should be explicit and opt-in, like
`kotlinx-coroutines-reactor` for coroutines. JetBrains plans a
compiler plugin. Return-type errors become checked exceptions;
parameter unions become overloads:

```kotlin
@JvmExposeErrors
fun find(
    q: String | Cancelled | Paused,
): List<String> | Timeout | Offline
```

The KEEP's description of the generated Kotlin:

```kotlin
@Throws(Timeout.Exception::class,
        Offline.Exception::class)
fun find(q: String): List<String>
@Throws(Timeout.Exception::class,
        Offline.Exception::class)
fun find(q: Cancelled): List<String>
@Throws(Timeout.Exception::class,
        Offline.Exception::class)
fun find(q: Paused): List<String>
```

So Java would see (my rendering):

```java
try {
    List<String> r = Api.find("kotlin");
} catch (Timeout.Exception e) {
    retry();
} catch (Offline.Exception e) {
    showOffline();
}
```

Each overload calls the original and maps errors to exceptions in
one `when`. Undecided: how an error maps to its exception. Two
options are on the table:

```kotlin
@AssociatedException
error object Timeout
// plugin generates Timeout.Exception : Throwable

error object Offline {
    fun asException(): IOException = IOException()
}
// plugin uses the return type for @Throws
```

The plugin only handles top-level unions. `List<String | Err>`
in a signature is out of scope; export such functions by hand.

### Coroutines on the JVM

Not discussed in the KEEP. My reading: a `suspend` function
already returns `Object` at the bytecode level (the value or
`COROUTINE_SUSPENDED`), so a union return type adds no new
representation. A `suspend` function with a union in its
signature should be mangled and hidden from Java by the same
rule as any other function.

### Kotlin/Native, JS, Wasm

Same representation everywhere: no wrapper, the value is one of
its components, treated like `Any`.

- **Native**: Objective-C and Swift interop have the same
  problem as Java, so declarations with unions are **not
  exported** to Objective-C or Swift.
- **JS and Wasm**: TypeScript has unions, so `@JsExport` works:

```kotlin
@JsExport
fun loadUser(): User | NotFound | PermissionDenied
```

```text
export function loadUser():
    User | NotFound | PermissionDenied;
```

For KMP this means: a common API with unions is exportable to
the web target and invisible to iOS and Java consumers. Plan
an adapter layer at those boundaries.

### Reflection and serialization

Neither KEEP mentions `KType` representation of unions,
`typeOf<User | NotFound>()`, or kotlinx.serialization support.
Open.

## Design decisions

### `Error` under `Any`, not beside it

KEEP-0441 (the first draft) made `Error` a parallel hierarchy
with a new top type `Any? | Error`. KEEP-0462 reversed that, and
explains why.

With a new top type, `Any?` stops being the most general type.
Either every generic declaration adds the bound `Any? | Error`
by hand, library by library, leaving the ecosystem half-migrated
for years; or the default bound changes, which breaks everyone.
And even the opt-in path is source-incompatible:

```kotlin
class List<T /* : Any? */>

fun first(xs: List<*>) {
    val x: Any? = xs[0]
    // breaks if T's bound becomes Any? | Error
}
```

`is Any` checks would also change meaning. With `Error : Any`,
adding errors is "nothing different from the addition of a new
class". `Any?` still means "no information", and every `Any` has
`toString`, `equals`, `hashCode`.

### Why `?.`, `?:` and `!!` are not reused

KEEP-0441 reused `?.` for errors and let `!!` throw on them.
0462 drops both. The cost of putting `Error` under `Any` is that
errors can hide in `Any`, `Any?` or an unbounded `T`. Extending
the null operators would silently change existing programs:

```kotlin
fun show(f: () -> Any?) {
    val v by lazy { f() }
    if (v != null) {
        v!!.toString() // never throws today
    }
}
```

If `!!` also threw on errors, this could start throwing with no
source change. `?.` on an `Any?` would gain new short-circuits;
`?:` would evaluate its right side in new cases. Hence a new
operator.

Elvis was already rejected in 0441 for a different reason: there
is no syntactic place to *name* the error, so errors could be
swallowed silently. `ifError { }` gives the error a parameter.

### `|.` over `!.`

`!.` was the most requested spelling. It lost because `!`
signals danger in Kotlin (`!!`) and in natural language, while
this operator is the *safe* one that should not draw attention.
`|` already appears in the type, and `|.` relates to `T | E` the
way `?.` relates to `T?`.

### Unboxed `Object` over a `Box`

Wrapping unions in a box looks Java-friendly. The KEEP rejects
it:

- It breaks subtyping. `List<String>` could no longer be passed
  as `List<String | MyError>`, since the elements are not boxed.
- Generic code would not know whether a value is boxed;
  `arg is String` would become `instanceof String ||
  (instanceof Box && getValue() instanceof String)`.
- Java still could not express more than one error: a
  `Box<String, Error>` lets Java pass any error and gives no
  information on return.

"Instead of convenient union semantics it will become just
another awkward Either-like wrapper."

### Flat, non-generic errors and one value type

Both restrictions serve the goal of polynomial, unambiguous
inference and the non-goal of general union types. Disjointness
is what makes `(T | E) & Error = E` hold and keeps `when` and
smart casts precise.

### Not checked exceptions

KEEP-0441 lists what went wrong in Java: forced `try/catch` or
`throws` at every level, non-trivial control flow, poor
composition with higher-order functions. Errors as values avoid
all three: they pass through `map`, `async`, `retry` helpers as
values, and propagation is one operator.

### Comparison with other languages

KEEP-0441's survey:

- **Two-value returns** (Go, Lua, JS callbacks): suit dynamic or
  structural typing.
- **Wrappers** (Rust `Result`, Haskell/Scala `Either`, Java
  `Optional`): need combinators or monad comprehensions; Kotlin's
  libraries prefer direct values with smart casts and
  extensions.
- **Effect systems** (Scala, OCaml, Effect-TS): powerful, but
  require heavy type machinery and a paradigm shift.
- **Zig error unions** (`FileNotFound!File`): the closest
  relative. Optionals and error unions are orthogonal, there are
  dedicated operators, and feedback is positive. Zig errors are
  integer tags with no payload, and its most requested change is
  payloads; Kotlin error classes carry data from day one.

## Open questions and what may change

From the KEEPs:

- **Status itself.** 0462 is in public discussion; no version or
  flag is announced.
- **Nullable error types on their own** (`NetworkError?`).
- **The name `Value`**, and (my addition) how `kotlin.Error`
  coexists with today's `kotlin.Error` alias.
- **Negative smart casts** may ship after unions.
- **Traceability refinements**: the redundancy exemption, the
  `assuming<V>().doesNotContain<E>()` contract (syntax
  illustrative), exempting type parameters.
- **Hashing scheme** for mangling.
- **Exception mapping** in the Java plugin
  (`@AssociatedException` or an `asException()` member).
- **Migration plan**: "upcoming documents". The stdlib will add
  `XOrError` variants beside nullable and throwing ones.
- **A propagation operator** like Rust's `?` or Zig's `try`:
  "proposed" and "being explored" (0441), not in 0462.

Future extensions in 0462:

**Open unions.** A trailing `*` reserves room for future errors,
making additions source- and binary-compatible. Callers need an
`else`:

```kotlin
fun sync(): Int | Timeout | Offline | *

when (val r = sync()) {
    is Int -> done(r)
    is Timeout -> retry()
    is Offline -> wait()
    else -> log(r) // required: unknown future errors
}
```

They interact with traceability: `|.` after an open union warns
for any call that adds an error, since it might already be in
`*`:

```kotlin
fun Int.render(): String | Corrupt
sync()|.render()   // WARNING: Corrupt may be in *
sync()|.toString() // OK, adds no error
```

**`!!` for errors.** Possible only after a long migration:
deprecate `!!` on operands that are not `Value?` subtypes
(warning for two major versions, then an error for two more),
then reintroduce `!!` that throws on both `null` and errors.

## Cheat sheet

```kotlin
error object NotFound
error class RateLimited(val after: Duration)
typealias LoadError = NotFound | RateLimited

fun load(id: Id): User | LoadError

when (val r = load(id)) {        // exhaustive
    is User -> use(r)
    is NotFound -> miss()
    is RateLimited -> wait(r.after)
}

val u = load(id).ifError { return it } // early exit
val g = load(id).ifError { Guest }     // fallback
val t = load(id)|.charge(m) // User|LoadError|Declined
val x = load(id).throwIfError()        // escalate
```

- `error class` / `error object`: generated `equals`,
  `hashCode`, `toString`; no supertypes, no generics.
- Union: at most one value type, leftmost; any number of error
  types; error parts never nullable; value part may be.
- `Error : Any`; `Value` is the compile-time-only supertype of
  non-errors; `is Value` means `!is Error`.
- One error-ranging type parameter per union; bound the value
  parameter with `Value?`.
- `|.` chains; no `?|.`, no error Elvis, no error `!!` (yet).
- Warnings: same error from two chain steps; inferred type
  argument overlapping an error.
- JVM: `Object`, unboxed except primitives; mangled
  `name-hash`, hidden from Java; error-set change breaks binary
  compatibility.
- Native: not exported to Swift/ObjC. JS/Wasm: exported as TS
  unions.
- Status: public discussion, no release.

## Talking points

- "Rich errors are a union of one value and any number of error
  types: `User | NotFound`. No wrapper, no exception."
- "Exceptions stay for bugs and preconditions. Rich errors are
  for failures your caller is supposed to handle."
- "`|.` is to `User | NotFound` what `?.` is to `User?`, and the
  error types add up along the chain."
- "Error types are flat: no inheritance, no generics. That is
  what keeps unions disjoint and inference polynomial."
- "On the JVM it is just `Object`. Errors are their own classes,
  so `instanceof` tells them apart. Only primitives box."
- "Signal declares `RateLimited` nine times. With rich errors you
  declare it once and union it in."
- "It is not checked exceptions: errors are values, so they flow
  through `map`, `async` and your retry helper."
- "It is a proposal in public discussion. There is no flag to
  turn on yet."

Tricky questions:

**"Is this just Arrow's `Either` built in?"** Closer to `Raise`
than `Either`: direct style, no wrapper. Differences: errors must
be flat non-generic `error` types, unions widen automatically
without `withError`, propagation is explicit (`|.`, `ifError {
return it }`) rather than implicit through a context, it is a
plain return rather than a thrown `CancellationException`, and
there is no accumulation like `zipOrAccumulate`.

**"Why not reuse `?.` and `!!`?"** Because `Error` is a subtype
of `Any`, an error can already sit in any `Any?` or unbounded
`T`. Teaching `?.` or `!!` about errors would change the runtime
behaviour of existing code without a source change. `!!` may come
back after a four-major-version deprecation cycle.

**"Can I call it from Java or Swift?"** Not directly. Functions
with unions are mangled and hidden from Java, and not exported to
Objective-C/Swift. JetBrains plans an opt-in
`@JvmExposeErrors` plugin that turns return errors into checked
exceptions and parameter unions into overloads. JS and Wasm
export them as TypeScript unions.
