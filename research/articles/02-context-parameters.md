---
title: "Context Parameters"
subtitle: "Implicit arguments resolved by type, without scope pollution, and now passable by name"
author: "Notes from KEEP-0367, KEEP-0448 (background: KEEP-0259, KEEP-0443)"
date: "October 2026"
lang: en
---

## At a glance

| KEEP | Status in the KEEP | Role |
|---|---|---|
| [KEEP-0367](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0367-context-parameters.md) | In progress | The feature |
| [KEEP-0448](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0448-explicit-context-arguments.md) | Experimental in 2.4 | `f(name = value)` for contexts |
| [KEEP-0259](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0259-context-receivers.md) | Superseded by 0367 | Context receivers |
| [KEEP-0443](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0443-suspend-CoroutineContext-context-parameter.md) | Rejected | `suspend` gives a `CoroutineContext` |

- KEEP-0367 says "Design proposal, In progress" and names no compiler
  flag and no release. KEEP-0448 says "Experimental in 2.4" and calls
  itself "an integral part" of the context parameters design.
- Checked against kotlinc 2.4.20 while writing these notes: context
  parameters compile with no flag. Explicit context arguments need a
  flag; this repository's `build.gradle.kts` enables them with
  `-Xexplicit-context-arguments` (the KEEP does not name the flag).
- Passing `-Xcontext-receivers` to 2.4.20 is an error: "experimental
  context receivers are superseded by context parameters".
- Issues: the original request is
  [KT-10468](https://youtrack.jetbrains.com/issue/KT-10468) "multiple
  receivers" (cited by KEEP-0259). KEEP-0443 was driven by
  [KT-15555](https://youtrack.jetbrains.com/issue/KT-15555) "suspend
  properties". KEEP-0367 is discussed in
  [KEEP issue 367](https://github.com/Kotlin/KEEP/issues/367), KEEP-0448
  in [discussion 465](https://github.com/Kotlin/KEEP/discussions/465).

The teaser:

```kotlin
context(logger: Logger)
fun User.save() = logger.log("saving $id")

context(ConsoleLogger()) { user.save() }
user.save(logger = FileLogger()) // KEEP-0448
```

## The problem

Some values are needed everywhere but are never the subject of the
call: a logger, a transaction, a repository, a clock, a coroutine
scope. Today you have three options, and all three hurt.

### Option 1: pass it explicitly

```kotlin
fun User.save(logger: Logger, tx: Transaction) {
  logger.log("saving $id")
  insert(this, tx)
  audit(this, logger, tx)
}

fun audit(u: User, logger: Logger, tx: Transaction) {
  logger.log("audit ${u.id}")
}
```

Every function in the call chain must accept and forward the same
arguments, even functions that only pass them through. Adding one more
service means touching every signature on the path.

### Option 2: member extensions

KEEP-0259 opens with the existing Kotlin way to express "an action that
needs a context": a member extension.

```kotlin
interface TransactionScope {
  fun User.save() { /* ... */ }
}

with(txScope) { user.save() }
```

The KEEP lists three limits:

- A member extension cannot be declared on a third-party class. You
  cannot add `Flow.launchFlow()` to `CoroutineScope` from outside
  kotlinx.coroutines, and inside it the dependency would point the
  wrong way.
- A member extension is always an extension. There is no way to write
  a top-level `updateSession()` that requires a `TransactionScope` but
  is not callable as `tx.updateSession()`.
- Only one receiver can be the context. A function that needs a
  `CoroutineScope` and a `TransactionScope` at the same time cannot be
  expressed.

### Option 3: extension receivers as scopes

```kotlin
fun ResourceScope.openFile(file: File): InputStream
```

This works, but the scope is now `this`. Inside a lambda typed
`ResourceScope.() -> R`, every member of `ResourceScope` (and of `Any`)
is in scope unqualified, and `this` no longer means the enclosing class.

### What the KEEPs want

Declarations that state "I need a `Logger` from my caller's context",
with values resolved by type at compile time, multiple contexts per
declaration, no change to the meaning of `this`, and no flood of
members into scope. KEEP-0259 tried this with *context receivers*.
KEEP-0367 replaces it with *context parameters*: named, and not
receivers.

## The feature, step by step

### 1. Declare a context parameter

`context(...)` precedes the declaration and contains `name: Type`
pairs, like a parameter list (§1.1).

```kotlin
interface Logger { fun log(message: String) }

context(logger: Logger)
fun logWithTime(message: String) =
  logger.log("${System.nanoTime()}: $message")
```

Inside the body, `logger` is just a parameter. It lives in the same
scope as the value parameters, so names must be unique across both
lists (§1.2, §7.3).

```kotlin
context(id: Int)
fun load(id: Int) {} // ERROR: conflicting declarations
```

The list may not be empty, and trailing commas are allowed by the
grammar (§7.1).

```kotlin
context() fun nothing() {} // ERROR: empty context list
```

### 2. Call it: arguments are resolved, not written

At the call site you do not pass the context argument. The compiler
fills it from two sources (§1.4): context parameters in scope, and
implicit receivers.

```kotlin
context(logger: Logger)
fun User.archive() {
  logWithTime("archiving $id") // uses 'logger'
}

fun Logger.cleanup(user: User) {
  user.archive() // uses the extension receiver
}
```

If no compatible value exists, the call does not resolve.

```kotlin
fun main() {
  logWithTime("boot")
  // ERROR: no context argument for 'logger: Logger'
}
```

### 3. Provide values with `context(...)`

The standard library function `context` puts values into the context
of a lambda (§2.1). The KEEP specifies arities one to three and allows
the compiler to build it in; kotlinc 2.4.20 accepts up to six values
(checked; seven is rejected).

```kotlin
fun main() {
  context(ConsoleLogger()) {
    logWithTime("boot")
  }
  context(ConsoleLogger(), userRepository) {
    User(1, "Ada").archive()
  }
}
```

The signatures from §2.1:

```kotlin
fun <A, R> context(
  context: A,
  block: context(A) () -> R,
): R

fun <A, B, R> context(
  a: A, b: B,
  block: context(A, B) () -> R,
): R
```

`with(logger) { ... }` also works, because implicit receivers are a
source for context resolution. The difference: `with` makes `logger`
the `this` of the block, `context` does not touch `this`.

### 4. Anonymous parameters and `contextOf`

Use `_` when the body never names the value but callees need it
(§1.1). It still participates in resolution.

```kotlin
context(_: Logger)
fun User.delete() {
  logWithTime("deleting $id") // fine: forwarded
}
```

To reach an anonymous value, use `contextOf` (§2.2). It replaces
KEEP-0259's `this@Logger`.

```kotlin
context(_: Logger)
fun User.rename(to: String) {
  contextOf<Logger>().log("rename $id -> $to")
}
```

Its declared shape is itself a context parameter:

```kotlin
context(ctx: A) fun <A> contextOf(): A = ctx
```

The KEEP wants the type argument written explicitly and suggests
restricting inference of `A` (for example with `@NoInfer`).

Multiple `_` parameters are allowed; it is the only name that may
repeat (§1.2).

```kotlin
context(_: Logger, _: UserRepository)
fun User.sync() { /* ... */ }
```

### 5. Contextual properties

Properties take context parameters too, for the property as a whole
(§1.3).

```kotlin
interface UserRepository { fun getById(id: Int): User? }

context(users: UserRepository)
val firstUser: User?
  get() = users.getById(1)
```

Such a property has no backing field, so it cannot have an initializer:
the context value only exists at access time and can differ per access.

```kotlin
context(_: Logger)
val User.label: String = "user"
// ERROR: property with context parameters cannot be
// initialized because it has no backing field
```

`var` works with a getter and a setter; both see the same context.

```kotlin
interface Clock { fun now(): Long }

class Session {
  context(clock: Clock)
  var lastSeen: Long
    get() = clock.now()
    set(value) { /* store */ }
}
```

### 6. Function types and lambdas with contexts

Function types gain a `context(...)` prefix. Only types, no names
(§1.7).

```kotlin
typealias Handler =
  context(Transaction) (UserId) -> User?

typealias Counter =
  context(Logger) User.() -> Int
```

A lambda of such a type sees its context values as if declared with
`_` (§1.8): they resolve, but only `contextOf` reaches them by name.

```kotlin
fun <A> withConsoleLogger(
  block: context(Logger) () -> A,
): A = context(ConsoleLogger()) { block() }

withConsoleLogger {
  logWithTime("doing something")
  contextOf<Logger>().log("hello")
}
```

### 7. Bridge functions: get the receiver feel back

Named parameters mean `r.raise(e)` instead of `raise(e)`. For DSL-style
APIs, §3.1 recommends a top-level *bridge function* that forwards to
the context value.

```kotlin
interface Raise<in E> {
  fun raise(error: E): Nothing
}

context(r: Raise<E>)
fun <E> raise(error: E): Nothing = r.raise(error)
```

Now any function with a `Raise` in context reads like a receiver DSL,
while only the bridged names enter scope:

```kotlin
context(_: Raise<E>)
fun <E, A> Either<E, A>.bind(): A = when (this) {
  is Left -> raise(error)
  is Right -> value
}
```

### 8. Explicit context arguments (KEEP-0448)

Sometimes you want to pass the context value by hand: to override one
value, or to break an ambiguity. KEEP-0448 reuses named-argument
syntax with the context parameter's name.

```kotlin
context(logger: Logger, service: OrderService)
fun process(order: Order) { /* ... */ }

context(logger: Logger, service: OrderService)
fun processAll(orders: List<Order>) {
  orders.forEach {
    process(it, logger = OnlyCritical(logger))
  }
}
```

Only `logger` is given; `service` is still resolved implicitly. That
partial form is deliberate (see Design decisions). Without the KEEP,
the same override needed a nested `context(OnlyCritical(logger)) { }`.

## Typical usage

KEEP-0367 sorts use cases into five groups (§4). Each wants a slightly
different style of declaration.

### Implicits: services passed down the call chain

Name the parameter, use it by name. Repositories and loggers are the
KEEP's examples (§4.1).

```kotlin
context(users: UserRepository, logger: Logger)
fun User.friends(): List<User> {
  logger.log("friends of $id")
  return friendIds.mapNotNull { users.getById(it) }
}

context(users: UserRepository, logger: Logger)
fun recommend(user: User): List<User> =
  user.friends().flatMap { it.friends() }
```

`recommend` never forwards anything by hand. Adding a third service
changes the `context(...)` lists, not every call.

### Scopes: unlocking abilities

The context marks "you are inside X", like `CoroutineScope` unlocking
`launch` (§4.2). Here the parameter is usually `_`, and the scope type
is designed together with bridge functions.

```kotlin
interface ResourceScope {
  fun onClose(release: () -> Unit)
}

context(scope: ResourceScope)
fun File.open(): InputStream =
  inputStream().also { s -> scope.onClose(s::close) }

fun <R> resourceScope(
  block: context(ResourceScope) () -> R,
): R = TODO("run block, then release")
```

Before, this would be `fun ResourceScope.openFile(file: File)`. With a
context parameter the subject (`File`) is the receiver and the scope is
context, matching the KEEP's `File.open()` example.

```kotlin
resourceScope {
  val input = File("orders.csv").open()
  val config = File("app.conf").open()
  // both closed when the block ends
}
```

Transactions fit the same mould, as KEEP-0259 described: functions run
*in* a transaction, not *on* one.

```kotlin
context(_: Transaction)
fun updateUserSession(id: UserId) {
  val session = loadSession(id)
  storeSession(session.copy(lastAccess = now()))
}
```

### Extending DSLs

A DSL today is an interface with members. Context parameters let a
third party add operations *from outside* and add operations only for
certain type arguments (§4.3.1).

```kotlin
class JsonBuilder {
  fun put(key: String, value: Any?) { /* ... */ }
}

context(b: JsonBuilder)
infix fun String.by(value: Any?) = b.put(this, value)

fun json(block: context(JsonBuilder) () -> Unit) =
  JsonBuilder().also { context(it) { block() } }

val user = json {
  "name" by "Ada"
  "age" by 36
}
```

A *contextual operator*: `by` exists only inside the builder, and
`JsonBuilder` never had to declare it.

Restricting by type argument:

```kotlin
interface Table<T>

context(t: Table<Order>)
fun overdue(): List<Order> = TODO()
// only callable where a Table<Order> is in context
```

`@DslMarker` applies uniformly to receivers and context parameters
(§4.3.2, §7.7; rules in the next section).

### Type-class style: context-oriented dispatch

Require an interface parameterized by the type, and you get something
close to type classes (§4.4).

```kotlin
interface ToJson<T> { fun toJson(thing: T): Json }

context(serializer: ToJson<T>)
fun <T> T.toJson(): Json = serializer.toJson(this)

context(_: ToJson<T>)
fun <T> ApplicationCall.json(thing: T) =
  respondJson(thing.toJson())
```

```kotlin
object MoneyJson : ToJson<Money> {
  override fun toJson(thing: Money) =
    Json.obj("cents" to thing.cents)
}

context(MoneyJson) {
  call.json(Money(1999))
}
```

The KEEP warns strongly against "copies" of an existing API with an
added context parameter: overload resolution is tricky and you may call
the unintended version. A `context(c: Comparator<T>) T.compareTo(...)`
next to the member `compareTo` is the cautionary example.

### Dependency injection

Context arguments are fully resolved at compile time, so a function's
`context(...)` list is a compile-time-checked dependency list (§4.5.1).

```kotlin
class CheckoutController {
  context(orders: OrderRepository, payments: Payments)
  fun checkout(cart: Cart): Order { /* ... */ }
}

fun main() {
  val orders = PostgresOrders(pool)
  val payments = StripePayments(apiKey)
  context(orders, payments) {
    CheckoutController().checkout(cart)
  }
}
```

Constructors cannot take context parameters, so §4.5.2 shows how to
fake one with `companion object` + `operator fun invoke`:

```kotlin
class DbUserService(
  val logger: Logger,
  val connection: DbConnection,
) : UserService {
  companion object {
    context(logger: Logger, connection: DbConnection)
    operator fun invoke(): DbUserService =
      DbUserService(logger, connection)
  }
}
```

And then immediately advises against it (§4.5.3), because it leads to
nested `context` pyramids:

```kotlin
// do not do this
context(ConsoleLogger(), DbConnectionPool(2)) {
  context(DbUserService()) {
    /* ... */
  }
}

// do this: build explicitly, inject once
val logger = ConsoleLogger()
val pool = DbConnectionPool(2)
val userService = DbUserService(logger, pool)
context(logger, userService) {
  /* ... */
}
```

### Coroutines-style library code

KEEP-0259's motivating example, rewritten with context parameters:
`launchFlow` belongs to neither `Flow` nor `CoroutineScope`, so it is
an extension on the subject with the scope as context.

```kotlin
context(scope: CoroutineScope)
fun <T> Flow<T>.launchFlow(): Job =
  scope.launch { collect() }
```

### Migrating from context receivers

Code written against the 1.6.20 prototype (`-Xcontext-receivers`) does
not compile any more. In 2.4.20 the old form reports "context
parameters must be named. Use '_' to declare an anonymous context
parameter" (checked).

```kotlin
// KEEP-0259 (gone)
context(Logger, Storage<User>)
fun userInfo(name: String): Info {
  info("Retrieving $name")        // Logger member
  return this@Storage.info(name)  // labelled this
}
```

```kotlin
// KEEP-0367
context(logger: Logger, storage: Storage<User>)
fun userInfo(name: String): Info {
  logger.info("Retrieving $name")
  return storage.info(name)
}
```

The mechanical recipe:

- Give every context a name, or `_` plus `contextOf<T>()`.
- Replace unqualified member calls with `name.member()`.
- Replace `this@Type` with the name or `contextOf<Type>()`.
- Remove `context(...)` from classes and constructors (see
  "Context and classes" below).

For libraries exposing a scope type, §3.2–§3.4 give a migration that
keeps *source compatibility* for users:

```kotlin
// 1. extension-receiver functions -> context
fun <E> Raise<E>.ensureFound(u: User?): User
// becomes
context(_: Raise<E>)
fun <E> ensureFound(u: User?): User

// 2. member extensions -> top-level contextual
interface Raise<in E> {
  fun <A> Either<E, A>.bind(): A
}
// expose additionally as
context(_: Raise<E>)
fun <E, A> Either<E, A>.bind(): A

// 3. keep the receiver runner, add a new one
fun <E, A> runRaise(
  block: Raise<E>.() -> A,
): Either<E, A>
fun <E, A> runRaiseContext(
  block: context(Raise<E>) () -> A,
): Either<E, A>
```

The context variant of the runner needs a different name to avoid an
overload conflict (§3.3): `Raise<E>.() -> A` and
`context(Raise<E>) () -> A` are the same type for typing purposes.

How to spot a scope type (§3.2): it is often an extension receiver
without being the subject of the action, and there is a "run" function
taking `S.() -> R`.

## Rules and edge cases

### Where `context(...)` is allowed

| Declaration | Allowed? |
|---|---|
| Top-level, member, extension, local functions | Yes |
| Properties (getter + setter together) | Yes |
| Operators | Yes, except delegation operators |
| Constructors (primary, secondary) | No |
| Classes / interfaces | No |
| Delegated properties (`by`) | No |
| Property with initializer / backing field | No |
| Getter-only or setter-only context | No |

Errors reported by kotlinc 2.4.20 (checked):

```kotlin
class Svc(val logger: Logger) {
  context(l: Logger) constructor() : this(l)
  // ERROR: context parameters on constructors
  // are unsupported
}

context(_: String)
fun interface Handler { fun handle() }
// ERROR: context parameters on classes
// are unsupported

context(_: Logger)
val cached: String by lazy { "x" }
// ERROR: context parameters on delegated
// properties are unsupported
```

Why: for constructors, the interplay with inheritance and
private/protected visibility is unresolved (§6.1). For delegation the
KEEP says the right semantics are unclear (§1.3). For getter-only
contexts, it is unclear how a property reference would behave if getter
and setter had different contexts.

Local contextual functions do compile in 2.4.20 (checked), which
KEEP-0259 had excluded:

```kotlin
fun report(orders: List<Order>) {
  context(l: Logger) fun line(o: Order) =
    l.log("order ${o.id}")
  context(ConsoleLogger()) { orders.forEach { line(it) } }
}
```

### `context` is a soft keyword

`context` stays a valid identifier (§7.2). Inside a body, `context(`
could start a call or a local declaration. The parser looks two tokens
ahead: identifier followed by `:` means a declaration, anything else is
a call.

```kotlin
fun setup() {
  context(l: Logger) fun f() {} // local declaration
  context(ConsoleLogger()) { f() } // a call
}
```

This replaces KEEP-0259's lookahead problem: there, `context(Ctx)`
before a local `fun` was ambiguous with calling a user function named
`context`, which was one reason local contextual declarations were
deferred.

### Context resolution: exactly one value per parameter

Resolution is a new phase after the normal applicability check (§7.5).
For each candidate and each context parameter, the compiler walks the
tower of scopes, innermost first, looking for **exactly one** implicit
receiver or context parameter of a compatible type at a level.

Three outcomes:

1. No compatible value for some parameter: the candidate is dropped.
2. More than one compatible value at the same level: *context
   ambiguity* error.
3. Otherwise: applicable.

```kotlin
class ConsoleLogger : Logger { /* ... */ }
class FileLogger : Logger { /* ... */ }

context(console: ConsoleLogger, file: FileLogger)
fun example1() = logWithTime("hello")
// ERROR: multiple potential context arguments
// for 'logger: Logger' in scope
```

Both values come from the same `context(...)` list, so they sit at the
same level. Inner levels win over outer ones:

```kotlin
context(file: FileLogger)
fun example2() = context(ConsoleLogger()) {
  logWithTime("hello")
}
// prints: console hello

context(console: ConsoleLogger, file: FileLogger)
fun example3() = context(console) {
  logWithTime("hello") // uses 'console'
}

context(console: ConsoleLogger, file: FileLogger)
fun example4() = with(console) {
  logWithTime("hello") // uses 'console'
}
```

This is the idiomatic way to disambiguate without KEEP-0448: re-enter
the value you want in a nested scope.

Resolution is per parameter and does not backtrack across
substitutions: for a generic context type, constraints join the
candidate's constraint system; if that fails the candidate is
inapplicable "without trying to substitute different implicit receivers
available in the context" (§7.5).

```kotlin
context(c: Comparator<T>)
fun <T> maxOf2(a: T, b: T): T =
  if (c.compare(a, b) >= 0) a else b

context(byTotal) { maxOf2(order1, order2) }
// T = Order; the context must supply exactly
// one Comparator<Order>
```

### Smart casts count

Smart casts on context values are considered during resolution (§7.6).

```kotlin
context(ctx: Any)
fun handle() {
  if (ctx is Logger) logWithTime("typed")
}
```

### Contexts do not fill receiver holes

A context parameter is not an implicit receiver. It is not a source for
`this`, for unqualified member calls, or for extension receivers.
KEEP-0443 calls this out as a deliberate property of the design:

```kotlin
fun String.shout() = uppercase()

context(str: String)
fun demo() {
  length     // ERROR: unresolved
  shout()    // ERROR: unresolved
  str.length // OK
}
```

The reverse is not true: implicit receivers *do* fill context
parameters, as shown with `with(console)` above.

### Receiver shadowed by context

A subtle trap (§7.10): you call a member through an outer implicit
receiver while a context value of the same type sits in a more nested
scope. That is an error, even if no contextual function is involved.

```kotlin
class Cow {
  fun moo() {}

  fun test() = context(Cow()) {
    moo()
    // ERROR: call to 'moo' uses an implicit receiver
    // shadowed by a context parameter. Make the
    // receiver explicit using 'this' or
    // 'contextOf<Cow>()'.
  }
}
```

The rationale: a member or extension on the receiver would otherwise
be silently chosen over the lexically closer context value, which
surprises readers.

### Overload resolution and ambiguity

**Rule (§7.8):** when choosing the most specific candidate, implicitly
resolved context parameters play **no role**. Overloads that differ only
in their contexts are ambiguous whenever both apply.

```kotlin
context(value: Any) fun describe() {}
context(string: String) fun describe() {}

fun test() = context("hello") {
  describe()
  // ERROR: overload resolution ambiguity
}
```

The KEEP's argument: with a value argument you can force the other
overload with `f("hello" as Any)`. With an implicit context there is
nothing to cast, and nothing in the code to point at.

Because of this, §1.5 asks for a declaration-site warning when every
context of one overload is a supertype of another's. kotlinc 2.4.20
reports it as "the following overloads conflict with this contextual
declaration. Calls will be ambiguous because context arguments are not
used for overload resolution" (checked).

```kotlin
open class Parent
class Child : Parent()

fun audit() {}                        // WARNING
context(x: Child) fun audit() {}      // WARNING
context(x: Child, a: Admin)
fun audit() {}                        // fine

context(x: Parent) fun bill() {}      // WARNING
context(x: Child) fun bill() {}
```

A plain function versus a contextual one is the same case: no context
(the empty set) is trivially "all supertypes". In 2.4.20 calling it with
the context present is ambiguous (checked):

```kotlin
fun greet() = println("plain")
context(_: Int) fun greet() = println("ctx")

fun main() {
  greet() // prints: plain
  context(1) { greet() }
  // ERROR: overload resolution ambiguity
}
```

Note: KEEP-0443 describes the opposite, that the contextual overload
wins inside `context(1)`, calls that "suspicious", and says it is
"a potential subject to change in the context parameters proposal".
The 2.4.20 compiler reports ambiguity, which matches §7.8 and the §1.5
warning.

Declaring two overloads with the exact same context set is a conflict
(§1.5). Overloads with genuinely different context sets are fine, as
long as callers never have both contexts available.

### Explicit context arguments: the rules

From KEEP-0448:

- **Syntax:** named-argument form, using the context parameter's name.
- **Partial:** pass any subset; the rest are resolved implicitly.
- **Not `_`:** an anonymous parameter cannot be given explicitly.
- **No positional after:** a context parameter has no position, so no
  positional arguments may follow an explicit context argument.
- **Resolved with named arguments,** not in the context resolution
  phase, so the value feeds type inference and overload choice.
- **Participates in most-specific selection,** like an optional
  parameter that is only considered when explicitly given.
- **Bypasses `@DslMarker`,** just like an explicit receiver does.
- **No property form:** contextual properties have no call syntax.

Disambiguating overloads by name:

```kotlin
context(theA: Audit) fun record() {}
context(theB: Billing) fun record() {}

context(oneA: Audit, oneB: Billing)
fun close() {
  record()            // ERROR: ambiguity
  record(theA = oneA) // OK: first overload
}
```

KEEP-0448 strongly recommends naming context parameters *uniquely among
similar overloads* so the name itself can serve as a disambiguator.

Specificity by explicit argument type:

```kotlin
context(x: Parent) fun foo() { println("parent") }
context(x: Child) fun foo() { println("child") }

fun test() {
  context(Child()) { foo() } // ERROR: ambiguity
  foo(x = Child())           // prints: child
}
```

Explicit context arguments compete with ordinary value arguments:

```kotlin
fun ship(x: Parent) { println("value") }
context(x: Child) fun ship() { println("context") }

fun test() {
  context(Child()) { ship() } // prints: context
  ship(x = Child())           // prints: context
}
```

The first call has no argument for the value overload. In the second,
both overloads accept `x = Child()`, and `Child` is more specific than
`Parent`.

Errors (checked with 2.4.20 and the flag):

```kotlin
context(_: Logger) fun ping() {}
ping(_ = ConsoleLogger())
// ERROR: no parameter with name '_' found

context(logger: Logger, service: Service)
fun run(id: Int) {}
run(logger = ConsoleLogger(), 1)
// ERROR: mixing named and positional arguments

context(a: Logger) val banner: String get() = ""
banner(a = ConsoleLogger())
// ERROR: no context argument for 'a: Logger'
```

For a property, nest instead: `context(ConsoleLogger()) { banner }`. A
property reference such as `context(x, ::banner)` does not help, because
references resolve their context eagerly at creation time.

**Interaction with named-only parameters.** KEEP-0439 (still a proposal)
lets a parameter be `named`. KEEP-0448 notes the usual escape hatch, a
positional call, then disappears, and offers no solution other than
recommending libraries not ship both versions. KEEP-0439 itself says
`named` is not applicable to context parameters.

### Inheritance and parameter names

Context parameters are part of the signature (§1.5). Overrides must
keep the same types in the same order; no widening.

```kotlin
interface Shape {
  context(canvas: Canvas) fun draw()
}

class Circle : Shape {
  context(canvas: Canvas) override fun draw() {}
}
```

Renaming is allowed but now matters for explicit arguments. The name
used at a call is the one of the most specific override (§7.14), and
the compiler warns on a change, including named to `_` and back.

```kotlin
open class Base {
  context(a: Int) open fun limit() = a
}

class Derived : Base() {
  context(_: Int) override fun limit() = 2
  // WARNING: the corresponding parameter in the
  // supertype 'Base' is named 'a'
}
```

When two supertypes disagree on a name, it is ambiguous: a warning at
the class, and an error if you try to use it explicitly (§7.15).

```kotlin
interface I1 { context(_: String) fun foo() }
interface I2 { context(s: String) fun foo() }

abstract class C : I1, I2
// WARNING: names '<unused var>' and 's' of
// parameter #0 conflict in supertypes

fun test(c: C) {
  c.foo(s = "")
  // ERROR: named argument is prohibited for
  // parameter with an ambiguous name
}
```

### Function types: equivalence versus resolution

For typing, a function type with contexts equals the type with all
parameters as value parameters in the same order (§1.7). These are the
same type:

```kotlin
context(Logger, User) () -> Int
context(Logger) User.() -> Int
context(Logger) (User) -> Int
Logger.(User) -> Int
(Logger, User) -> Int
```

Equivalence is "for typing purposes, not for resolution purposes".
Consequences:

```kotlin
fun apply(
  x: context(String, Double) Int.(z: Long) -> Unit,
  y: Int,
) {
  context("", 1.0) { y.x(1L) } // OK
  x("", 1.0, y, 1L)            // OK, all as values
  y.x("", 1.0, 1L)             // ERROR
}
```

A *value* of function type can be invoked with contexts as positional
arguments. A *declared function* cannot:

```kotlin
context(_: String, _: Double)
fun Int.scale(z: Long) {}

fun test(y: Int) {
  context("", 1.0) { y.scale(1L) } // OK
  y.scale("", 1.0, 1L)             // ERROR
  scale("", 1.0, y, 1L)            // ERROR
}
```

### Lambdas and inference

During applicability, the expected lambda type is stripped of its
context (`nocontext(U)`, §7.4); context values are then bound inside.
Context parameters are never inferred for a lambda unless a contextual
function type is "pushed" onto it (§7.9).

```kotlin
val f = { logWithTime("x") }
// ERROR: no context argument; nothing pushed

val g: context(Logger) () -> Unit =
  { logWithTime("x") } // OK
```

Context parameters take part in builder-style inference (§7.9).

### Callable references

The KEEP specifies **eager** resolution (§5.1): the context must be
available where the reference is created, and the resulting type
mentions no context.

```kotlin
context(users: UserService)
fun save(u: User) {}

context(users: UserService)
fun saveAll(list: List<User>) =
  list.forEach(::save)
  // KEEP: ::save is (User) -> Unit
```

```kotlin
context(users: UserService)
fun User.doStuff(x: Int): Int = x + 1

// val r = User::doStuff // unresolved: no context

context(users: UserService)
fun example() {
  val g = User::doStuff // g: User.(Int) -> Int
  val h: context(UserService) User.(Int) -> Int =
    { doStuff(it) }     // keep context: a lambda
}
```

Captured contexts count like captured receivers for equality and
hashing (§5.3). Property references are also resolved eagerly, so a
`KProperty1<User, String>` needs no new reflection type (§2.3).

**Implementation note (checked):** kotlinc 2.4.20 rejects `::save`
above with "callable reference to ... is unsupported because it has
context parameters". Use a lambda (`list.forEach { save(it) }`) until
the KEEP's §5 behaviour ships.

### `@DslMarker`

A value is X-marked if its type is annotated with an `@DslMarker`
annotation X (§7.7). New rule: if a nearer X-marked value is in scope
(receiver or context) and context resolution picks an X-marked value
from an outer scope, it is an error. The old receiver rule still
applies. Context parameters do not conflict with receivers when the
receivers are used as receivers.

```kotlin
@DslMarker annotation class ExampleMarker

@ExampleMarker interface ExampleScope<A> {
  fun exemplify(): A
}

context(example: ExampleScope<A>)
fun <A> similarExampleTo(other: A): A = other

fun dsl() = withExampleContext(3) {     // (1)
  withExampleReceiver("b") {            // (2)
    similarExampleTo("hello") // OK, (2)
    similarExampleTo(1)
    // ERROR: cannot be called in this context
    // with an implicit receiver (resolves to 1)
  }
}
```

The notes on DSL markers (notes/0005) add that a marker on a function
type propagates to all its implicit values, contexts included:
`@ExampleMarker context(A) B.() -> Unit` marks both `A` and `B`.

### Subtyping among contexts is allowed

KEEP-0259 forbade repeated or subtype-related context receivers on a
declaration. KEEP-0367 drops that rule, otherwise
`context(a: A, b: B, block)` could not be declared generically. The
problem moves to the use site as an ambiguity error.

```kotlin
context(primary: Logger, audit: Logger)
fun dual() {
  primary.log("a")      // fine: by name
  logWithTime("b")      // ERROR: ambiguity
}
```

### Methods from `Any`

KEEP-0259 listed as an open issue that `toString()` in a
`context(LoggingContext)` function resolved to the context receiver.
Since context parameters are not receivers, that pollution is gone
(KEEP-0443's "Dependencies" section relies on exactly this). Checked
with 2.4.20:

```kotlin
context(logger: Logger)
fun describe(): String = toString()
// ERROR: unresolved reference 'toString'
```

## Platform interop

### JVM: extra leading parameters

A contextual function compiles to a method with extra parameters in
this order (§7.11):

1. context parameters,
2. extension receiver,
3. value parameters.

Properties compile to getters/setters with the same order (§7.12).
Parameter names do not affect the JVM ABI, but the compiler uses the
declared names where possible.

```kotlin
package shop

context(tx: Tx)
fun total(order: Order): Money = TODO()

class OrderService {
  context(tx: Tx, clock: Clock)
  fun Order.pay(amount: Money): Boolean = TODO()

  context(clock: Clock)
  var lastSeen: Long
    get() = clock.now()
    set(value) {}
}
```

`javap` output from kotlinc 2.4.20 (checked):

```text
public final class shop.CKt {
  public static final shop.Money
    total(shop.Tx, shop.Order);
}
public final class shop.OrderService {
  public final boolean
    pay(shop.Tx, shop.Clock, shop.Order, shop.Money);
  public final long getLastSeen(shop.Clock);
  public final void setLastSeen(shop.Clock, long);
}
```

For members the dispatch receiver is the JVM `this`; contexts come
first among the declared parameters.

### What Java sees

Plain parameters. Java passes them positionally (this compiles against
the classes above):

```java
class Checkout {
  static void run(Tx tx, Clock clock,
                  OrderService s, Order o) {
    Money m = CKt.total(tx, o);
    boolean ok = s.pay(tx, clock, o, m);
    long t = s.getLastSeen(clock);
    s.setLastSeen(clock, 42L);
  }
}
```

There is no implicit resolution on the Java side; Java callers are
always "explicit context argument" callers, by position.

### Function types on the JVM

By the type equivalence in §1.7, `context(A, B) R.(P) -> T` is an
ordinary `Function4<A, B, R, P, T>` (KEEP-0259 states the same
`FunctionN` mapping). A lambda parameter
`block: context(Logger) () -> Unit` appears to Java as
`Function1<? super Logger, Unit>` (checked).

### Binary and source compatibility

- Adding, removing or reordering a context parameter changes the JVM
  descriptor, so it is a binary-incompatible change, exactly like a
  value parameter (my reading of §7.11).
- Renaming a context parameter is binary-compatible (names are not in
  the ABI) but can break source that uses KEEP-0448 explicit arguments
  (my reading of §7.14 plus KEEP-0448).
- Migrating `fun <E> Raise<E>.f()` to `context(_: Raise<E>) fun <E> f()`
  keeps the JVM descriptor: both compile to `f(Raise)`, for top-level
  and member functions alike (checked with `javap`). Java callers and
  already-compiled bytecode keep working. Kotlin call sites change
  (`raise.f()` becomes `f()` in context), which is why §3.4 relies on
  keeping the receiver variants for source compatibility.
- The receiver-based runner and the context runner cannot be overloads
  (§3.3), because their lambda parameter types are equal.

### Context receivers ABI, for comparison

KEEP-0259 put context receivers after the dispatch receiver and before
the extension receiver, giving `f(C1, C2, R, P1, P2)`. KEEP-0367 has the
same effective order. The ABI story did not change; the source story
did.

### Other targets

§7.13: "Targets may not follow the same ABI compatibility guarantees as
those described for the JVM." The KEEP specifies nothing for JS,
Native or Wasm. Source semantics are common Kotlin, so KMP common code
can declare and call contextual functions (my reading).

KEEP-0443 asked whether `actual context(_: CoroutineContext) fun foo()`
may actualize `expect suspend fun foo()` and answered no; that proposal
was rejected, so the question is moot, but it shows that `context` and
`suspend` are different signatures.

### Reflection

§2.4 extends `kotlin.reflect`:

```kotlin
interface KParameter {
  enum class Kind {
    INSTANCE, EXTENSION_RECEIVER, VALUE,
    CONTEXT_PARAMETER // new, in the KEEP
  }
}

val KCallable<*>.contextParameters: List<KParameter>
  get() = parameters.filter {
    it.kind == KParameter.Kind.CONTEXT_PARAMETER
  }
```

Shipped naming differs: the 2.4.20 `kotlin-stdlib` has
`KParameter.Kind.CONTEXT`, and `kotlin-reflect` has
`kotlin.reflect.full.contextParameters` (checked with `javap`).

§2.5: a contextual property is a `KProperty` that also extends the
function type of its getter. `KProperty0/1/2` are not extended for
context parameters.

## Design decisions

### From receivers to parameters

The central change. KEEP-0259 put context values into scope as
receivers: every member of every context became callable unqualified.
The KEEP-0367 Q&A gives scope pollution as the main objection:

- too many functions in scope make the right one hard to find;
- it becomes much harder to tell where a member comes from.

KEEP-0259 had seen it coming. Its "Open issues" section notes that one
pair of braces used to add at most one implicit receiver; context
receivers removed that natural limit. Its style guide warned that a
context receiver acts like a wildcard `import *`, so few existing types
were fit to be one. Its own `PrintWriter` example (`println` silently
switching target depending on `context(PrintWriter)`) showed the
danger.

Context parameters keep the useful half, implicit passing, and drop the
risky half, implicit scope. Bridge functions bring back the receiver
feel, but only for names a library author chose to export.

```kotlin
// KEEP-0259: all of PrintWriter in scope
context(PrintWriter)
fun hello() = println("Hello") // which println?

// KEEP-0367: explicit
context(out: PrintWriter)
fun hello() = out.println("Hello")
```

### Names instead of `this@Type`

KEEP-0259 had considered `context(name: Type)` and rejected it as
lacking use cases, suggesting wrapper interfaces like `CallScope`
instead. It used generated labels: `this@Logger`, with rules for
generics, nullability and function types, and type aliases as a
workaround when labels clashed. KEEP-0367 makes names mandatory, adds
`_` and `contextOf<T>()`, and removes the label machinery.

### Parentheses and the `context` keyword

From KEEP-0259, unchanged: `context` won over `with`, `using`, `given`,
`implicit`, `within` and others because "contextual function" reads
naturally in prose. `context(...)` won over `context<...>` because it
reads as a parameter list, which leaves room for exactly what happened:
named entries (`context(name: Type)`) and modifiers or annotations on
them. KEEP-0367 now makes `context` a modifier in the grammar and
recommends ordering: annotations, then `context`, then other modifiers.

```kotlin
@Deprecated("use v2")
context(@Audited users: UserRepository)
public suspend fun User.load(): Profile = TODO()
```

### No contexts on constructors or classes

KEEP-0259's prototype supported `context(A) class C`. KEEP-0367 drops
it. Reasons (§6, Q&A):

- inheritance and visibility interplay is unclear: should a class's
  context be in scope for extensions to that class? Should visibility
  matter?
- a common request is one constructor with value parameters and one
  with the same values as contexts, which clashes on the platform.
- "scoped properties" (`with val` in KEEP-0259's future work) may be a
  better general answer, and context-in-class now would get in its way.

§6.3 lays out the possible roadmap as levels:

1. no context for constructors (current);
2. contexts only for secondary constructors;
3. primary constructors, without `val`/`var`;
4. `val`/`var` context parameters, without entering the context;
5. `val`/`var` context parameters enter every declaration's context.

The two workarounds the KEEP offers:

```kotlin
// stored once per instance
class TypeScope(val analysis: AnalysisScope) {
  fun Type.equalTo(other: Type): Boolean = TODO()
}

// required per operation
class TypeScope {
  context(analysis: AnalysisScope)
  fun Type.equalTo(other: Type): Boolean = TODO()
}
```

### Eager callable references

Five designs were considered. Eager wins because:

- receivers are implicit in calls but explicit in references
  (`User::save`); contexts have no reference-side syntax;
- passing `::save` to `map`/`forEach` while reusing the outer context
  is a common, important case.

KEEP-0259 had planned the opposite, `::f` typed as
`context(LoggingContext) (Params) -> Unit`. §5.4 keeps a richer,
expected-type-driven resolution as future work, together with similar
conversions for `suspend` and `@Composable`.

### Dropping the subtyping restriction

Multi-value `context(a, b) { }` is generic in `A` and `B`, which could
be related by subtyping. KEEP-0367 chose developer responsibility plus
use-site ambiguity errors over type-level restrictions or making the
function a built-in.

### Contexts and most-specific selection

KEEP-0259 said candidates *with* context requirements are more specific
than the same candidates without. KEEP-0367 §7.8 says contexts play no
role. The reasoning: there is no way to steer an implicit argument, so
picking silently would be unfixable for the caller. KEEP-0448 then gives
callers the steering wheel (explicit arguments), and only explicit
ones count.

### Explicit arguments: all-or-nothing rejected

KEEP-0448 considered allowing explicit context arguments only when all
are given. Rejected because:

- adding a context parameter to an existing function would then break
  every call that passes any context explicitly;
- partial passing covers "slightly adjust one value" without repeating
  the rest;
- "those not given are resolved implicitly" is easy to understand.

```kotlin
doSomething(logger = OnlyCritical(logger))
// instead of being forced to write
doSomething(
  logger = OnlyCritical(logger),
  service = service,
)
```

Without KEEP-0448, the only fix for an overload ambiguity was a helper
function that fixed one overload, which does not scale and needs
captured intermediate values:

```kotlin
context(oneA: Audit)
fun recordFromAudit() = record()

context(oneA: Audit, oneB: Billing)
fun close() = recordFromAudit()
```

### KEEP-0443: `suspend` as a `CoroutineContext` provider (rejected)

The idea: every `suspend` function body behaves as if wrapped in
`context(continuation.context) { ... }`, so suspend code can call
`context(_: CoroutineContext)` functions and `coroutineContext` becomes
an ordinary contextual property instead of a compiler intrinsic.

```kotlin
// proposed, never shipped
suspend fun compute() {
  checkBudget() // would resolve CoroutineContext
}

context(ctx: CoroutineContext)
fun checkBudget() { ctx.ensureActive() }
```

Its goals: answer KT-15555 ("suspend properties") without expensive
`suspend` properties; let CPU-bound helpers such as `isPrime` check
cancellation without becoming `suspend`; unify two "pass by context"
mechanisms.

Discarded alternatives inside KEEP-0443: an implicit
`context(_: CoroutineContext)` on every `suspend` signature (intrusive,
not in the binary signature, risks overload changes); exposing
`Continuation` (unsafe, and does not solve KT-15555); just allowing
`suspend` properties (properties should be cheap). A Compose analogue
was also discarded because `CompositionLocal`s are keyed by global
tokens, not types, and `Composer` is internal.

The status is "Rejected", but the KEEP text does not record the final
reason. It lists two concerns of its own: *discoverability* (the link
between `suspend` and contexts is not visible) and *`CoroutineContext`
becomes even more magical*, coupling the language core more tightly to
a stdlib type. My reading: those are the likely reasons; treat that as
an inference, not a quote.

What it still teaches: contexts and `suspend` are distinct signatures.
They do not conflict as overloads, cannot override each other, and
cannot `actual`ize each other, and a contextual function reference is
not a `suspend` function value.

### Other languages

KEEP-0259 compares with Scala 3 `using`/`given`: a `using` clause is the
same idea as a context parameter, and KEEP-0367's named form is closer
to Scala's `(using ord: Ordering[Person])` than context receivers were.
KEEP-0259 also frames contexts as a limited typed coeffect system, the
dual of algebraic effects in Koka or Eff. KEEP-0443 lists Swift
`TaskLocal`, Java `ThreadLocal` and `ScopedValue` as related
dynamic-context mechanisms; context parameters are the static,
compile-time-resolved counterpart.

```kotlin
// Scala 3:
// def printAll(s: Seq[Person])
//   (using ord: Ordering[Person]) = ...
context(ord: Comparator<Person>)
fun printAll(people: Sequence<Person>) = TODO()
```

## Open questions and what may change

- **Status.** KEEP-0367 is "In progress"; KEEP-0448 is
  "Experimental in 2.4". Details can still move.
- **Callable references.** The KEEP's eager resolution is not what
  2.4.20 does (it rejects references to contextual callables). A
  context-aware, expected-type-driven resolution is listed as future
  work (§5.4), tied to a broader design for function conversions
  including `suspend` and `@Composable`.
- **Constructors and classes.** The five levels of §6.3 describe how
  far it could go. "Scoped properties" (`with val`) are mentioned but
  not designed.
- **Delegated properties.** Contexts on `by` properties and contextual
  `getValue`/`setValue` operators are excluded "at this point";
  semantics unclear.
- **Properties and explicit arguments.** No syntax for passing a
  context to a property explicitly.
- **Named-only parameters (KEEP-0439).** If both land, positional
  disambiguation disappears for `named` parameters; KEEP-0448 has no
  solution beyond advice to library authors.
- **`contextOf` inference.** The KEEP suggests `@NoInfer`-style
  restriction "if possible"; whether you can rely on inference for `A`
  is implementation-defined.
- **Plain vs contextual overloads.** KEEP-0443 flagged the "contextual
  wins" behaviour as suspicious and possibly changing; 2.4.20 reports
  ambiguity. Treat the declaration-site warning as the stable signal.
- **Non-JVM ABI.** Explicitly not guaranteed (§7.13).
- **`context` built-in.** The KEEP lets the compiler implement
  `context(...)` as a built-in rather than library overloads, so the
  maximum arity is not part of the spec.

## Cheat sheet

```kotlin
// declare
context(logger: Logger, _: Tx)
fun User.save() { logger.log("$id") }

// property: getter only, no field
context(repo: UserRepository)
val current: User get() = repo.me()

// provide
context(ConsoleLogger(), tx) { user.save() }

// anonymous access
contextOf<Tx>()

// lambda type
fun <R> inTx(block: context(Tx) () -> R): R

// bridge function
context(r: Raise<E>)
fun <E> raise(e: E): Nothing = r.raise(e)

// explicit (KEEP-0448)
user.save(logger = FileLogger())
```

- Names are mandatory; `_` for anonymous, `contextOf<T>()` to read it.
- Sources: context parameters and implicit receivers, innermost level
  first, exactly one match per level.
- Context values are not receivers: no unqualified members, no `this`.
- Contexts do not decide overloads unless passed explicitly.
- No contexts on constructors, classes, delegated properties,
  initializers, or only one accessor.
- Function types: `context(A, B) R.(P) -> T` is `(A, B, R, P) -> T`.
- References resolve contexts eagerly (KEEP); 2.4.20 rejects them.
- JVM: contexts, then extension receiver, then value parameters.
- Explicit args: by name, partial OK, not `_`, no positional after,
  not for properties.

## Talking points

- "Context parameters are parameters you pass by type instead of by
  position or by name."
- "We tried context receivers, and they put too much in scope. The
  shipped design keeps the implicit passing and drops the implicit
  `this`."
- "If you want the DSL feel back, write a one-line bridge function. You
  choose what enters scope, not the compiler."
- "It is compile-time dependency injection: a missing dependency is a
  compile error, not a runtime failure."
- "Java sees a normal method. Contexts are just the first parameters."
- "Two loggers at the same level is an error, not a coin flip. Nest a
  `context(...)` or, in 2.4, pass `logger = ...` by name."
- "Name your context parameters. With explicit arguments, the name is
  the API."

**Q: Why can't I write `context(Logger) class Service`?**
Context-in-class was in the KEEP-0259 prototype and was removed.
Inheritance and visibility questions are unresolved, constructors with
both value and context forms clash on the platform, and the team
expects "scoped properties" to be the better design. Today: take it as
a constructor value, or put `context(...)` on each member that needs it.

**Q: I have `fun f()` and `context(_: Int) fun f()`. Inside
`context(1) { f() }`, which one runs?**
Neither: it is an ambiguity error in 2.4.20, and the compiler already
warns at the declaration. Implicit contexts never count for
"most specific". If the context parameter is named, an explicit
argument such as `f(n = 1)` selects the contextual one.

**Q: Why don't contexts work in `suspend` functions automatically, like
`coroutineContext`?**
KEEP-0443 proposed exactly that, making every `suspend` body provide
its `CoroutineContext` as a context value, and it was rejected. The
KEEP itself worried about discoverability and making `CoroutineContext`
even more special to the compiler. Today, `suspend` and
`context(_: CoroutineContext)` are separate: pass `coroutineContext`
in with `context(coroutineContext) { ... }`.
