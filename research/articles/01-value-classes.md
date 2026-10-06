---
title: "Value Classes 2.0"
subtitle: "Identity-free, shallow-immutable classes with any number of fields, designed to land on Valhalla"
author: "Notes from KEEP-0454, KEEP-0468, KEEP-0470"
date: "October 2026"
lang: en
---

## At a glance

Four documents make up this story. One is a motivation document, one
is the core design, and two handle migration. Three older KEEPs give
the background.

| KEEP | Status (as stated in the KEEP) | Scope |
|---|---|---|
| [0453](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0453-better-immutability-value-classes-motivation.md) | Public discussion | Motivation and design space |
| [0454](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0454-better-immutability-value-classes-MFVC.md) | Experimental (phase I) in 2.5 | Multi-field ("full") value classes |
| [0468](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0468-inline-value-classes.md) | Public discussion | `inline value class` spelling and migration |
| [0470](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0470-will-become-value.md) | Proposed | `@WillBecomeValue` annotation |
| [0104](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0104-inline-classes.md) | Stable in 1.5.0 | Today's inline value classes |
| [0340](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0340-multi-field-value-classes.md) | "Unknown"; JVM prototype since 1.8.20 | The earlier, flattening MFVC design |
| [0394](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0394-jvm-expose-boxed.md) | Experimental in 2.2 | `@JvmExposeBoxed` for Java callers |

- **YouTrack**: [KT-77734](https://youtrack.jetbrains.com/issue/KT-77734)
  is the umbrella issue for 0453 and 0454.
- **Discussions**: 0453 is
  [#472](https://github.com/Kotlin/KEEP/discussions/472), 0454 is
  [#473](https://github.com/Kotlin/KEEP/discussions/473), 0468 is
  [#501](https://github.com/Kotlin/KEEP/discussions/501), 0470 is
  [#504](https://github.com/Kotlin/KEEP/discussions/504).
- **Enabling it**: KEEP-0454 does not name a compiler flag. KEEP-0468
  defines `-Xfull-value-classes=on|off` and
  `-Xinline-value-class-migration=warning|strict`. It also gives a
  timeline: `warning` becomes the default in 2.5.20, `strict` in 2.6,
  and `-Xfull-value-classes=on` in 2.7+. (My reading:
  `-Xfull-value-classes=on` is the switch that turns on the KEEP-0454
  semantics. KEEP-0468 only says "when full value classes are enabled
  (either by default or with an explicit compiler flag)".)
- **This repo** compiles with Kotlin 2.4.20, so none of the multi-field
  code below compiles here yet. `@JvmInline value class` has been
  stable since 1.5.0. `@JvmExposeBoxed` is experimental since 2.2.

The teaser:

```kotlin
value class Money(val cents: Long, val currency: String)

fun main() {
    val a = Money(1999, "EUR")
    val b = Money(1999, "EUR")
    println(a == b) // prints: true
    println(a)      // structural toString, like data
    a === b         // ERROR: identity is not available
}
```

There are two fields and no `@JvmInline`. You get structural
equality, there is no identity, and the runtime is free to represent
it as it likes.

## The problem

### Identity you never asked for

Every Kotlin class instance has an identity. For mutable data that is
the point: two references to the same `ShoppingCart` see the same
mutations. For immutable data, identity is accidental. It is only
there because the JVM allocates an object.

```kotlin
data class Money(val cents: Long, val currency: String)

fun main() {
    val price = Money(1999, "EUR")
    val parsed = Money(1999, "EUR")
    println(price == parsed)  // prints: true
    println(price === parsed) // prints: false
}
```

Code that branches on that `===`, locks on a shared `Money`, or keys
an `IdentityHashMap` on it is already fragile today. The design notes
call relying on the identity of an immutable class like `String` "a
bad programming practice". The language does not stop you. Kotlin
already treats `Int`, `Long` and `Double` as identity-free, and
deprecates `===` on them. User types never got that treatment beyond
single-field inline classes.

### The single-field ceiling

Inline value classes (KEEP-0104) are the only user-defined value types
today. They allow exactly one property, because a multi-value wrapper
cannot be returned from a JVM method without a box.

```kotlin
@JvmInline
value class Temperature(val celsius: Double) // fine

@JvmInline
value class Complex(val re: Double, val im: Double)
// ERROR (today): inline class must have exactly
// one primary constructor parameter
```

As a result people work around it. KEEP-0340 lists Jetpack Compose
types that pack two `Float`s into one `Long` (`Offset`, `Size`,
`IntOffset`), and plain `data class`es (`Rect`, `RoundRect`) where the
packing trick runs out. KorGE writes hand-specialised `PointArrayList`
types and keeps mutable boxes in object pools to avoid allocation.

### Data classes do not promise immutability

A `data class` is "value-like" only by convention. Nothing stops a
`var`, and nothing stops someone mutating a cached instance:

```kotlin
data class Book(var title: String, var isbn: String)

class LibraryRepository(private val cache: List<Book>) {
    val books: List<Book> get() = cache
}

fun egoisticClient(repo: LibraryRepository) {
    repo.books.forEach { it.title = it.title.uppercase() }
    // every other reader of the cache now sees the change
}
```

KEEP-0453 says this matters most in two places. Compose and caches
rely on "inputs did not change" checks. Concurrent code shares data
across coroutines and threads. Both need guarantees, not conventions.

### The copy ladder

Immutable updates in Kotlin today mean nested `copy` calls:

```kotlin
val updated = user.copy(
    address = user.address.copy(
        zipCode = user.address.zipCode.copy(
            code = "1079MZ"
        )
    )
)
```

`copy` has a second problem besides verbosity. Adding a property to a
data class breaks the binary signature of `copy`. Jake Wharton's
"Public API challenges in Kotlin" is cited in the design notes for
this.

### The JVM is moving underneath us

Project Valhalla (JEP 401) brings value classes to the JVM. JDK types
such as `Integer`, `Optional` and `java.time` classes are on the path
to becoming value classes. Java's `==` on them becomes a
*substitutability test*. If Kotlin has no source-level concept of "this
type has no identity", it cannot compile to Valhalla value classes,
and it cannot warn users about code that will change behaviour.

## The feature, step by step

### Step 1: declare a value class with several fields

KEEP-0454's proposal in one sentence: remove the one-property
restriction.

```kotlin
value class Complex(val re: Double, val im: Double)

value class Money(val cents: Long, val currency: String)

value class Point(val x: Int, val y: Int)
```

Primary properties must be `val`. The `value` modifier means two
things at once: the class has no stable identity, and its stored state
is exactly its primary properties.

A good working mental model, which the KEEP itself uses: **a value
class is a shallow-immutable data class without identity.**

### Step 2: know what is generated

Like a data class, the compiler generates structural `equals`,
`hashCode` and `toString` from the primary properties. Unlike a data
class, it does **not** generate `copy()` or `componentN()`.

```kotlin
value class Money(val cents: Long, val currency: String)

fun demo() {
    val m = Money(500, "EUR")
    println(m == Money(500, "EUR")) // prints: true
    println(m.hashCode() ==
        Money(500, "EUR").hashCode()) // prints: true
    m.copy(cents = 600) // ERROR: no copy()
    m.component1()        // ERROR: no componentN()
}
```

### Step 3: only primary properties are stored

Because a value is fully described by its primary properties, nothing
else may have a backing field. Delegated properties are forbidden as
well, and that includes `lazy`, because the `Lazy` instance needs a
field.

```kotlin
value class Order(val id: String, val lines: List<Line>) {
    // OK: computed, no backing field
    val total: Long get() = lines.sumOf { it.cents }

    val cached: Long = 0 // ERROR: backing field not allowed
    val summary by lazy { "$id" } // ERROR: delegation
}

class Line(val sku: String, val cents: Long)
```

KEEP-0454 lists "delegation to stable expressions" as a possible
extension. Examples are delegating to a primary property, a `const
val`, or an `object`. That only works if the "no backing field for
the delegate" optimisation is guaranteed on all backends. Today it is
not.

### Step 4: destructure by name, not by position

`val (a, b) = e` on an expression of a value-class type is interpreted
as **name-based** destructuring
([KEEP-0438](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0438-name-based-destructuring.md)).
The variable names must match property names, so their order no
longer matters.

```kotlin
value class Point(val x: Int, val y: Int)

fun describe(p: Point): String {
    val (y, x) = p // name-based: y = p.y, x = p.x
    return "x=$x y=$y"
}
```

If you really want positional destructuring (the KEEP mentions `Pair`
and tuples), you write `operator fun component1()` and so on by hand.

### Step 5: validate in `init`, share invariants via abstract parents

`init` blocks work as usual:

```kotlin
value class Percentage(val value: Int) {
    init {
        require(value in 0..100) { "Out of range: $value" }
    }
}
```

What is new is that value classes can be `abstract` or `sealed`. An
abstract value class stores nothing, but its constructor still runs
for every subclass. That makes it a place to centralise invariants,
which an interface cannot do:

```kotlin
sealed value class Interval<T : Comparable<T>>
protected constructor(start: T, end: T) {
    init {
        require(start <= end) { "start > end" }
    }
}

value class IntInterval(val start: Int, val end: Int) :
    Interval<Int>(start, end)

value class DateInterval(
    val start: Long,
    val end: Long,
) : Interval<Long>(start, end)
```

### Step 6: value objects

If one or more properties are allowed, zero are as well. A `value
object` is the identity-free counterpart of a `data object`:

```kotlin
sealed interface UserResponse

value object UserUnknown : UserResponse

value class UserFound(val name: String) : UserResponse
```

A value object has exactly one possible value. The compiler may
therefore keep a canonical singleton or recreate the box each time it
is needed (`UserUnknown()`), and you cannot tell the difference.
Initialisation still happens only once.

### Step 7: decide inline or full

After this change Kotlin has two kinds of value class:

- **Inline value class**: today's single-field kind. Its inlining is
  *observable*: in JVM signatures, in serialization, and in exports.
- **Full value class**: the new kind, with any number of fields. If it
  is inlined at all, the inlining is not observable.

KEEP-0468 gives the inline kind an explicit, cross-platform spelling:

```kotlin
// New, preferred on every platform (incl. common)
inline value class Color(val rgb: Int)

// Still valid, same kind, no migration required
@JvmInline
value class RgbColor(val rgb: Int)

// Once full value classes are enabled: full kind,
// even with a single property
value class UserId(val raw: String)
```

Note that last line. Once the switch happens, a plain single-field
`value class` is no longer inline.

### Step 8: update values today, and with copy vars tomorrow

There is no `copy`, so for now an update is a constructor call:

```kotlin
value class Cart(val items: List<String>, val total: Long)

fun Cart.add(sku: String, cents: Long): Cart =
    Cart(items + sku, total + cents)

fun checkout(start: Cart): Cart {
    var cart = start
    cart = cart.add("kotlin-mug", 1500)
    cart = cart.add("kotlin-tee", 2500)
    return cart
}
```

KEEP-0454 calls this "painful" and promises a separate
ergonomic-updates KEEP. It says the experimental version should follow
one release after experimental MFVCs. KEEP-0453 says the team
currently favours **copy vars**, a design going back to the 2021
design notes. The sketch below uses the *design-notes syntax*. It is
**not implemented and not final**:

```kotlin
// Design-notes sketch, NOT valid Kotlin today
value class Cart(
    copy var items: List<String>,
    copy var total: Long,
)

fun checkout(start: Cart): Cart {
    var cart = start
    cart.items += "kotlin-mug" // = cart with new items
    cart.total += 1500
    return cart
}
```

The rule behind it: assigning to a `copy var` of a value stored in a
`var` rebinds the variable to an updated copy. It can never mutate a
shared instance, because value classes have no identity that could be
shared.

### Step 9: prepare existing classes with `@WillBecomeValue`

For a class that should become a value class later, KEEP-0470 proposes
an annotation that makes the compiler warn about identity-sensitive
uses now:

```kotlin
@OptIn(ExperimentalValueClassApi::class)
@WillBecomeValue
class Uuid(
    val mostSignificantBits: Long,
    val leastSignificantBits: Long,
)

fun check(a: Uuid, b: Uuid) {
    a === b                    // WARNING: identity
    synchronized(a) { }        // WARNING: synchronization
    System.identityHashCode(a) // WARNING: identity hash
}
```

Only the author of the class needs the opt-in. Users of `Uuid` do not,
and they get the warnings.

## Typical usage

### Domain identifiers and money

A single-field ID that is serialized as a bare string should stay
inline. Give it the explicit `inline` modifier so that nobody can
"just add a field" without the change showing up in review:

```kotlin
@Serializable
inline value class UserId(val raw: String)

value class Money(val cents: Long, val currency: String) {
    init { require(currency.length == 3) }

    operator fun plus(other: Money): Money {
        require(currency == other.currency)
        return Money(cents + other.cents, currency)
    }
}
```

KEEP-0468 shows the trap the modifier prevents. Take an unmarked
`@Serializable value class UserId(val raw: String)`. Once full value
classes are on, adding `val tag: String = ""` *silently* changes its
JSON shape from `"u1"` to an object. In a KMP project it could even
serialize differently on JVM and non-JVM targets.

### Sealed hierarchies with value objects

Value objects and sealed value classes fit result and event types
where identity was never meaningful:

```kotlin
sealed interface FetchResult

value object NotFound : FetchResult
value class Found(val body: String) : FetchResult
value class Failed(val status: Int) : FetchResult

fun render(r: FetchResult): String = when (r) {
    NotFound -> "404"
    is Found -> r.body
    is Failed -> "HTTP ${r.status}"
}
```

Compare `data object NotFound`. Deserialization or reflection can
produce a second instance of it, and `===` then says false. With
`value object` that bug class disappears, because `===` is not
available.

### Compose UI state

KEEP-0454 spends a section on Compose. The primary properties of a
value class are stored `val`s with no custom getters, so the Compose
compiler could infer stability, and could do so **across modules**.
Today it gives up on classes from modules that were not compiled with
the Compose plugin.

```kotlin
value class UserCard(
    val name: String,
    val nickname: String,
)

@Composable
fun UserView(user: UserCard) {
    Row {
        Text(user.name)
        Text("(${user.nickname})")
    }
}
```

The KEEP goes further. Compose could track *which* properties a
composable reads and restart `UserView` only when `name` or `nickname`
changes. This is listed as an opportunity, not a commitment. One
caveat: a `List<T>` property still makes the class unstable, because
the list might be a `MutableList` at runtime. Value classes are
*shallow* immutable.

### Shared state in coroutines

Value classes are safe to publish across threads: nobody can mutate
them through a shared reference. Combined with `StateFlow`, an update
is an explicit replacement:

```kotlin
value class Session(val user: String, val hits: Int)

class SessionStore {
    private val state =
        MutableStateFlow(Session("anon", 0))

    fun hit() = state.update { s ->
        Session(s.user, s.hits + 1)
    }
}
```

### Evolving a library type

Adding a primary property is a semantic change, just as it is for a
data class. It can still be kept binary compatible with
`@IntroducedAt`
([KEEP-0431](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0431-version-overloading.md)):

```kotlin
value class Point(
    val x: Int,
    @IntroducedAt("2.0") val y: Int = 0,
)
// keeps a hidden Point(Int) constructor (and its
// default-argument bridge) for old callers
```

## Rules and edge cases

### Declaration rules at a glance

Everything below follows from "the primary properties *are* the
value". The list is collected from KEEP-0454, plus KEEP-0104 for the
inherited rules.

```kotlin
value class A(var x: Int)          // ERROR: var primary
value class B(val x: Int) {
    var y: Int = 0                 // ERROR: backing field
    val z by lazy { 1 }            // ERROR: delegation
}
open value class C(val x: Int)     // ERROR: open
abstract value class D(val x: Int) // ERROR: abstract
                                   // cannot store state
```

Abstract value classes may have only abstract properties or
properties with custom accessors. Final and abstract value classes may
implement interfaces and extend abstract value classes, and nothing
else:

```kotlin
open class Entity
abstract value class Shape

value class Circle(val r: Double) : Shape()   // OK
value class Bad(val r: Double) : Entity()     // ERROR:
// a value class cannot extend an identity class

class Mutable(var r: Double) : Shape()        // OK
```

The last line surprises people. A **non-value class may extend an
abstract value class.** The KEEP's model: an abstract value class is
identity-*free*, like an interface. It imposes no identity
requirement. A concrete value subclass has no identity, and a concrete
identity subclass adds identity. The reverse direction is forbidden,
because an identity superclass imposes an identity requirement that a
subclass cannot remove.

### Why no `open` value classes

The KEEP shows the puzzle that partial state would create:

```kotlin
// Hypothetical: if open/stateful bases were allowed
abstract value class Base(val x: Int)
value class Derived(val y: Int) : Base(42)

fun puzzle(a: Base, base: Base) {
    println(a == base) // compare x only, or x and y?
    println(base == a) // symmetric?
}
```

There is no good answer for `equals` symmetry, and Valhalla would not
support stateless open value classes either. So: no `open`, and
abstract value classes store nothing. The KEEP notes that Valhalla
does allow fields in abstract value classes. It forbids them in Kotlin
anyway, on the bet that most such Java classes will not have fields.

### Identity and `===`

`===` is a compile error on value class types. This was already true
for inline value classes:

```kotlin
value class Point(val x: Int, val y: Int)

fun same(a: Point, b: Point) =
    a === b // ERROR: identity equality is forbidden
```

The type system cannot see through generics, `Any` or interfaces:

```kotlin
infix fun <T> T.refEq(other: T): Boolean = this === other

fun leak() {
    val a = Point(1, 2)
    val b = Point(1, 2)
    println(a refEq b) // could be false: two boxes
    val anyA: Any = a
    println(anyA === anyA) // compiles; result unspecified
}
```

The KEEP accepts this hole. Inline value classes have had it since
1.5, and the team knows of no case where it matters in practice. It
lists three ways it could close the hole later:

1. A `Value` supertype with negative bounds (`T : !Value`), so that
   `===` is allowed only on non-value types. This needs limited
   negative types in the type system.
2. Debug and test runtime checks that panic on `===` against value
   objects. Kotlin/Native has related plans in KT-71000.
3. Make `===` on value objects a substitutability test on *all*
   platforms, as Java's `==` does under Valhalla. On non-JVM backends
   this has a real runtime cost.

There is also a proposed runtime check:

```kotlin
// Proposed in KEEP-0454 "Possible extensions"
fun Any?.hasIdentity(): Boolean

fun cacheKey(x: Any): Any =
    if (x.hasIdentity()) IdentityKey(x) else x
```

`hasIdentity()` looks at the concrete runtime class. It returns
`false` for a value class even when that value currently sits in a
box, and `false` for `null`.

### The opposite problem in Java

Under Valhalla, Java's `==` on `Integer` stops comparing references
and starts comparing values, even through `Object`. Two Kotlin facts
hold together, and an audience may mix them up:

```kotlin
fun javaSide(a: Any, b: Any) = a === b
// Kotlin value class boxes: may be false for equal values
// Valhalla JDK value objects: true for equal values,
// because the JVM's acmp becomes a substitutability test
```

(My reading: on a Valhalla JVM, once Kotlin compiles full value
classes to JVM value classes at stage 2, `===` through `Any` would
follow the JVM. KEEP-0454 does not state this explicitly. It lists
"how should `===` work" as an open question.)

### Equality and boxing

Inline value classes could not override `equals`, because a
user-defined `equals(Any?)` forces boxing on every `==`. KEEP-0454
lifts that restriction for both kinds, with a cost model:

```kotlin
inline value class Email(val raw: String) {
    override fun equals(other: Any?): Boolean =
        other is Email &&
            raw.equals(other.raw, ignoreCase = true)
    override fun hashCode(): Int =
        raw.lowercase().hashCode()
}
// Allowed with KEEP-0454; == on Email may box
```

- No `equals` override: the compiler avoids boxing where it can. That
  is "immediately possible" for `@JvmInline` classes on the JVM and
  for single-property value classes on other platforms.
- `equals(Any?)` overridden: no boxing-free `==`.
- Planned fix: typed `equals`
  ([KEEP-0456](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0456-equals.md),
  [KT-24874](https://youtrack.jetbrains.com/issue/KT-24874)), which
  would let the compiler skip the box again.

### Smart casts across module boundaries

Today a `val` from another module is not smart-cast-stable, because
the library could add a custom getter in a later version:

```kotlin
// module lib
data class User(val name: String?)
value class Profile(val name: String?)

// module app
fun greet(u: User, p: Profile) {
    if (u.name != null) u.name.length
    // ERROR: smart cast impossible, 'name' is a
    // public API property declared in another module
    if (p.name != null) p.name.length // OK
}
```

Value class primary properties are guaranteed to be stored fields
without custom getters. Turning one into a computed property is
already a breaking change. So the compiler can treat them as stable
across modules.

### Initialization order (early initialization)

Valhalla requires every field of a value object to be assigned
*before* `super()` is called, so that `this` is never observable while
partially initialised. Kotlin aligns with this by assigning primary
properties first:

```kotlin
value class Complex(val re: Double, val im: Double) {
    init { println("init") }
}

// Before (regular classes):   After (value classes):
//   super()                     this.re = re
//   this.re = re                this.im = im
//   this.im = im                super()
//   init body                   init body
```

This changes nothing for existing inline value classes. They cannot
extend classes, so their `super()` is effectively a no-op. Valhalla's
own default is stricter: the whole constructor body runs in the
prologue. Kotlin could adopt that only after designing a Kotlin
equivalent of JEP 513 ("flexible constructor bodies"). The KEEP says
the default *may* become stricter before MFVCs go stable.

### Value objects vs data objects

```kotlin
data object Idle
value object Busy

fun check(a: Any) {
    println(a === Idle) // allowed, discouraged
    // Busy has no identity: you cannot even ask
}
```

| | `data object` | `value object` |
|---|---|---|
| Identity | yes (one intended instance) | no |
| `===` | allowed, may surprise | not available on the type |
| Runtime | canonical singleton | singleton or re-created box |

### The `inline` modifier and its errors

KEEP-0468 rules:

```kotlin
inline value class Color(val rgb: Int)        // OK

inline data class Rgb(val rgb: Int)
// ERROR: `inline` requires a value class

inline value class Complex(
    val re: Double,
    val im: Double,
) // ERROR: inline value class requires one property

@JvmInline
inline value class Hex(val rgb: Int)
// ERROR: `@JvmInline` is redundant

inline class Legacy(val rgb: Int)
// historical spelling = inline value class;
// quick fix adds `value`, may be deprecated later
```

`@JvmInline` in **common** code changes meaning. It used to mean
"inline on the JVM only". Now it means "inline on all platforms".

### Migration diagnostics, mode by mode

Take an existing unmarked single-field value class in non-JVM or
common code:

```kotlin
value class Color(val rgb: Int)
```

| Flags | Effect on that line |
|---|---|
| `migration=warning`, `full=off` | inline; warning + "add `inline`" fix |
| `migration=strict`, `full=off` | compile error until marked |
| `full=on` | full value class; no diagnostic |

Two more rules. `-Xfull-value-classes=on` cannot be combined with
either migration mode, because migration is assumed to be finished.
And there are three ways to accept the full-class behaviour early:
turn on `-Xfull-value-classes=on`; or use the `warning` mode with
`-Xwarning-level=IMPLICIT_INLINE_VALUE_CLASS:disabled`; or, not
recommended, use `@Suppress`.

### Expect/actual

The *kind* (inline or full) is part of the expect/actual contract.
The spelling is not.

```kotlin
// common
expect inline value class Color(val rgb: Int)

// jvm: either spelling is fine
@JvmInline
actual value class Color(val rgb: Int)

// native
actual inline value class Color(val rgb: Int)
```

```kotlin
// common, full value classes enabled
expect value class UserId(val raw: String)

// jvm
actual inline value class UserId(val raw: String)
// ERROR: full / inline kind mismatch
```

There is a compatibility wrinkle. An existing JVM `@JvmInline` actual
whose expect is unmarked gets an IDE fix that adds `inline` to the
*expect*, not one that removes `@JvmInline`.

### Three stages, one breaking hop

KEEP-0454 frames the evolution of a value class as three stages:

| Stage | Meaning | Hop to next |
|---|---|---|
| 0 | `@JvmInline` / inline value class | **breaking** (ABI) |
| 1 | full value class, compiled as box | seamless |
| 2 | full value class, Valhalla/optimised | n/a |

```kotlin
@JvmInline
value class Color(val code: Int) // stage 0

value class Color(val code: Int) // stage 1
// Same source shape, different ABI: compiled callers
// pass `int`; new code expects a `Color` box.
```

The KEEP believes most `@JvmInline` classes are used for performance
first and immutability second, so this hop is rarely needed. The
stdlib's `UInt`, `ULong`, `UByte`, `UShort`, `Duration` and `Result`
are expected to stay inline. Stage 1 to stage 2 should be binary
compatible on the JVM ("up to our current knowledge"). Other platforms
compile closed-world, so optimisation does not touch ABI there.

### Moving data classes and regular classes

A regular class becomes a value class: every identity-sensitive
operation may change behaviour (`===`, `identityHashCode`,
`synchronized`, `WeakReference`). That is what `@WillBecomeValue`
exists for.

A data class becomes a value class: `copy()` and `componentN()`
disappear, which breaks both source and binary compatibility. The KEEP
sketches an annotation ("back-of-napkin syntax") to separate the
generated methods from the class kind:

```kotlin
// Sketch only: Pair's 5-step migration in KEEP-0454
@GenerateDataClassMethods(
    components = DEPRECATED,
    copy = DEPRECATED,
)
value class Pair<A, B>(val first: A, val second: B)
// steps: GENERATE -> DEPRECATED -> HIDDEN -> removed
```

Until then, the KEEP's advice for anyone who needs `copy()` during the
transition is to have the IDE generate one by hand.

### `@WillBecomeValue` rules

All *declaration* checks of a full value class run on the annotated
class as **errors**. *Usage* checks are **warnings**:

```kotlin
@OptIn(ExperimentalValueClassApi::class)
@WillBecomeValue
class Account(
    var balance: Long, // ERROR: vars forbidden
    note: String,      // ERROR: non-property ctor param
) : Base()             // ERROR if Base is not an abstract
                       // or sealed value (or ValueBased)

open class Base
```

It applies to final classes, abstract and sealed classes, and object
declarations. It does not apply to classes that are already value
classes, to interfaces, to enums, or to `open` classes. Data classes
pass the primary-constructor checks automatically, and their generated
`equals`/`hashCode` count as structural. KEEP-0470 also lists stdlib
types that cannot be annotated yet because they are `open`:
`IntProgression` and therefore `IntRange`, and `Base64`.

### Nullability and the inline mapping

These rules are unchanged from KEEP-0104 and only apply to the
**inline** kind. The JVM type depends on nullability:

```kotlin
@JvmInline value class Score(val v: Int)
@JvmInline value class Tag(val s: String)
@JvmInline value class Note(val s: String?)

fun a(x: Score)  {} // int
fun b(x: Score?) {} // LScore; (box)
fun c(x: Tag?)   {} // String (null is free)
fun d(x: Note?)  {} // LNote; to tell Note(null) from null
```

### Arrays and varargs

KEEP-0104 forbids `vararg` of inline value class types: should the
array hold boxed or unboxed values? `Array<Color>` holds boxes, and
an unboxed array needs a hand-written `ColorArray` wrapper. The design
notes propose a reified `VArray<T>` as the long-term answer. KEEP-0454
does not say whether full value classes may appear in `vararg`. That
is open. (My reading: at stage 1 they are ordinary boxes, so nothing
technical blocks it, but the KEEP does not commit.)

```kotlin
@JvmInline value class Color(val rgb: Int)

fun paint(vararg colors: Color) {}
// ERROR: vararg of inline class type is prohibited
```

## Platform interop

### Inline value classes on the JVM (stage 0)

This is today's world and it does not change. An inline class
parameter becomes its underlying type. To avoid clashes, and to stop
Java from bypassing `init`, the function name is **mangled** with a
hash suffix:

```kotlin
@JvmInline
value class UserId(val raw: String) {
    init { require(raw.isNotBlank()) }
}

fun charge(user: UserId, cents: Long) { }
fun lookup(): UserId = UserId("u1")
fun all(ids: List<UserId>) { }
```

```java
// What Java sees (descriptors simplified)
// static void charge-<hash>(String, long)
//   -> not callable: '-' is illegal in Java names
// static String lookup()
//   -> top-level, no inline params: not mangled,
//      returns the underlying String
// static void all(List<UserId>)
//   -> generic position: boxed type kept

String raw = MainKt.lookup();          // works
MainKt.all(List.of());                 // works
// MainKt.charge(...)                  // does not exist
```

The box class `UserId` exists. Its constructor is synthetic, so Java
cannot call it. Kotlin moves between the two forms with `box-impl` and
`unbox-impl` and runs `init` through a static `constructor-impl`.
Members become static `-impl` methods. Methods from `Any` get static
`equals-impl`, `hashCode-impl`, and a reserved `equals-impl0` for
boxing-free `==`.

Boxing happens whenever the inline type is used *as another type*:
nullable (for primitives and nullable underlyings), generic, `Any`, or
an interface.

```kotlin
interface Shape
@JvmInline value class Side(val len: Int) : Shape

fun asShape(s: Shape) {}
fun <T> id(x: T): T = x

fun demo(s: Side) {
    asShape(s)    // boxing
    val t = id(s) // box in, unbox out
}
```

`@JvmName` on a function disables the mangling, which is the
traditional workaround.

### `@JvmExposeBoxed` (experimental since 2.2)

KEEP-0394 adds Java-callable boxed variants next to the mangled ones,
and a real, `init`-running public constructor:

```kotlin
@JvmExposeBoxed
@JvmInline
value class PositiveInt(val number: Int) {
    init { require(number >= 0) }
    fun add(o: PositiveInt) = PositiveInt(number + o.number)
}
```

```java
PositiveInt a = new PositiveInt(3);   // runs init
PositiveInt b = a.add(new PositiveInt(4));
// new PositiveInt(-1) throws IllegalArgumentException
```

Details worth knowing:

- It can go on classes, constructors, functions and accessors. On a
  class it applies to every member that can be exposed, but not to
  nested classes or companions. The KEEP expects a module-wide flag
  "like `-Xjvm-expose-boxed`".
- It is not allowed on `suspend` functions.
- Naming rules: the boxed variant takes the Kotlin name, or the
  `jvmName` argument if one is given. `@JvmName` renames only the
  unboxed variant, unless no exposed name is given, in which case both
  variants get it.
- A top-level function with no inline parameters that *returns* an
  inline class is not mangled. Exposing it under the same name would
  give Java two methods it cannot tell apart, so explicitly annotating
  it requires an explicit name.
- A default value on the property also exposes a no-arg constructor
  (useful for JPA).
- It works the same with the new `inline value class` spelling.

### Full value classes on the JVM, stage 1 (the experimental phase)

KEEP-0454 is explicit: **MFVCs are not inlined by the Kotlin
compiler.** An MFVC is a reference box. Interop is "basically interop
with regular Kotlin classes".

```kotlin
value class Money(val cents: Long, val currency: String)

fun total(a: Money, b: Money): Money =
    Money(a.cents + b.cents, a.currency)
```

```java
// (my reading of "regular Kotlin class" interop)
Money a = new Money(1999L, "EUR");
long c = a.getCents();
Money t = MainKt.total(a, a); // no mangling expected
boolean same = a.equals(t);
```

The KEEP does not spell out the exact JVM signatures for stage 1. The
Java side above is extrapolated from "regular Kotlin classes" and is
not a quoted guarantee.

Values stay value-like even though they live in boxes:

- `==`, `equals` and `hashCode` are structural and ignore which box
  you have.
- `===` and `identityHashCode` are disallowed on the type.
- Shallow immutability means you cannot change one box to make it
  distinguishable from another.

```kotlin
value class User(
    val name: String,
    val meta: MutableMap<String, String>,
)

fun shallow() {
    val meta = mutableMapOf<String, String>()
    val a = User("Marat", meta)
    val b = User("Marat", meta)
    b.meta["city"] = "Amsterdam" // mutates shared map
    println(a == b) // prints: true (still)
}
```

### Stage 2: Valhalla

On a Valhalla JVM the same Kotlin class compiles to a JVM value class.
The API, the ABI and the interop layer stay those of stage 1. In the
KEEP's words, "most of the 'valueness' is done by the JVM, invisible
to us". The Kotlin restrictions (no `open`, no stored state in
abstract parents, early initialisation, value-only supertypes) are
chosen so that the switch is binary compatible.

Because MFVCs ship as plain boxes, they do **not** depend on Valhalla
arriving on the JDK, or on Android. Android was the reason given back
in KEEP-0340.

### History: the 1.8.20 flattening prototype

KEEP-0340 described a different JVM design, prototyped since 1.8.20.
It wrote `@JvmInline` on multi-field classes and **flattened** them
into several locals, fields and parameters:

```kotlin
// KEEP-0340 prototype syntax (superseded)
@JvmInline
value class DPoint(val x: Double, val y: Double)

class Holder(val p: DPoint)
// Holder stored two double fields; access went through
// synthetic getters such as `getP-x`()
```

Returns were always boxed, because a JVM method cannot return two
values. The design relied on synthetic `unbox-impl-x` getters, and
mangled every function that took the type. KEEP-0454 drops this
approach: immutability comes first, and the optimisation is left to
Valhalla or the compiler later. KEEP-0468 now *requires* exactly one
property for the inline kind, so a multi-field `@JvmInline` class is
no longer part of the plan. (My reading: KEEP-0468's "inline value
class requires one primary property" error makes the prototype
spelling invalid going forward.)

### JS, Native, Wasm and Swift export

- **Stage 1 everywhere**: a box, which is easy to interoperate with,
  but "not 100% idiomatic" on each platform.
- **JS**: reference-based, so it keeps using boxes, as the JVM does.
- **Native/Wasm**: may later expose MFVCs as structs. They must then
  never be exposed through pointers that allow in-place mutation. A
  separate design is promised.
- **Closed world**: on klib platforms, layout is re-resolved at final
  compilation, so adding a field does not create a binary
  compatibility problem *inside Kotlin*.
- **Foreign ABI**: once MFVCs are exported as Swift structs or Wasm
  struct types, adding a field changes the layout for prebuilt
  non-Kotlin consumers. Prefer opaque exports, or coordinate releases.

```kotlin
// Single-field export today: SKIE exposes an inline
// value class as its underlying property.
inline value class Meters(val value: Double)
```

The original reason for "shape-based inlining" on non-JVM targets was
that closed-world klib platforms seemed safe. KEEP-0468 calls that
assumption "too optimistic". Serialization, exports, compiler plugins
and API validators all observe the inline kind.

### Serialization

Rule of thumb from KEEP-0468: tools should read the **recorded kind**,
not count properties.

```kotlin
@Serializable
inline value class Color(val rgb: Int) // inline: 16711680

@Serializable
@JvmInline
value class Legacy(val rgb: Int)       // same inline shape

@Serializable
value class Pixel(val x: Int, val y: Int)
// full: object-like, as a data class would be
```

KEEP-0470 describes full value classes as "not embedded into the
underlying single field by libraries and frameworks, e.g.
`kotlinx.serialization`, Spring". There is also a third case. A legacy
unmarked single-field class compiled *before* full value classes were
enabled keeps the inline behaviour.

For the inline kind, KEEP-0394 adds one more requirement:
`kotlinx.serialization` must keep working even when an exposed boxed
constructor is called.

### Reflection

KEEP-0468 plans to normalise the kind in reflection:

```kotlin
// Planned API (KEEP-0468)
val KClass<*>.isInline: Boolean   // member
val KClass<*>.isFullValue: Boolean
    get() = isValue && !isInline
val KClass<*>.isInlineValue: Boolean
    get() = isValue && isInline

fun kind(k: KClass<*>) = when {
    k.isInlineValue -> "inline"
    k.isFullValue -> "full"
    else -> "identity"
}
```

`isInline` is true for classes marked `inline`, for `@JvmInline`
classes, and for unmarked single-field classes compiled before full
value classes were enabled. For inline classes, `Duration::class` and
`d::class` still give the box class, as KEEP-0104 specified. A known
gap from KEEP-0394 also remains: a property typed `PositiveInt` has
the JVM getter `int getAge()`, so a reflective framework can build an
object that skips `PositiveInt`'s `init`.

### On the JVM, when `@JvmInline` is materialised

`inline value class` emits the `@JvmInline` annotation in bytecode. As
a result, tools that look for it, such as Spring, keep working without
changes:

```kotlin
inline value class OrderId(val raw: Long)
// bytecode carries @JvmInline, same as the old spelling
```

## Design decisions

### Immutability first, performance later

The 2021 design notes put the model like this: "Step 1: I declare
this is a value class... Step 2: the compiler can optimise boxing
whenever it can." KEEP-0453 makes it the explicit priority: "developers
should adopt better value classes for the clarity, safety, and
correctness they provide... and not for speculative performance
benefits". This decision cuts the dependency on Valhalla and Android
runtimes, and lets the feature ship on all platforms at once.

```kotlin
value class Complex(val re: Double, val im: Double)
// Today: a box, like a data class.
// Valhalla: a JVM value class. Same source, same ABI.
```

### Why `value` replaced `inline` in 1.5, and why `inline` is back

The 1.5 rename from `inline class` to `value class` happened because
"inline" misled people. The functions of an inline class are not
inline. The class is not always inlined. And the modifier really just
removes identity. KEEP-0468 brings `inline` back, only as a second
modifier that selects a representation kind that *is* observable. It
keeps `value` as the semantic marker. Reviving the bare `inline
class` was rejected because it hides that the declaration is a value
class, and because it reopens an old migration.

```kotlin
inline class Old(val x: Int)        // historical
value class Semantic(val x: Int)    // value semantics
inline value class Kind(val x: Int) // + observable inlining
```

### Why `@JvmInline` was required in the first place

The design notes argue that the short form should mean the right thing.
On a Valhalla JVM the right thing is a Valhalla value class, so the
pre-Valhalla inline form had to carry an annotation from day one. That
plan is now paying off. Plain `value class` on the JVM can become the
full, Valhalla-ready kind without breaking anyone's `@JvmInline` code.

### Alternatives to the `inline` modifier (KEEP-0468)

```kotlin
@PlatformInline value class A(val x: Int) // rejected
@NonInlined value class B(val x: Int)     // rejected
@JvmInline @KlibInline
value class C(val x: Int)                 // rejected
```

- **`@PlatformInline`**: one more annotation for a class kind that
  should read as one coherent declaration. Its only upside was that
  it could fade away if Valhalla made the inline kind less needed.
- **Negative marker (`@NonInlined`)**: least churn, but "preserves
  the wrong long-term default". The ordinary case would look unusual.
- **`@KlibInline` / `@NonJvmInline`**: mirrors the implementation
  split, not what the user means ("this is the inline kind").
- **`@JvmInline` everywhere**: the name wrongly suggests a JVM-only
  concept, and hints that other backends could ignore it.
- **Keep shape-based inlining forever**: you could never declare a
  full one-field class, and field count would stay observable.
- **Flip the meaning by language version**: the same source would have
  a different observable shape depending on flags. "Too dangerous."

### No value interfaces

```kotlin
value interface ValueLike // NOT proposed
```

An interface is a behaviour contract and is agnostic about identity.
A `value interface` would exist only in Kotlin metadata. Java could
implement it with a mutable identity class, and Swift protocols have
no "value types only" constraint either. The guarantee would break at
the first language boundary. The 2021 notes did float `value
interface` and an `AnyValue` root. KEEP-0454 drops both.

### Abstract value classes instead

There are two reasons. First, abstract value classes can enforce
construction invariants, as in the `Interval` example. Second,
Valhalla plans abstract value classes, `java.lang.Number` among them,
and Kotlin needs a counterpart for `expect`/`actual typealias`
commonisation:

```kotlin
// jvmMain
actual typealias DomainBase =
    com.example.AbstractDomainValueBase

// commonMain: impossible without abstract value classes
expect abstract value class DomainBase()
```

### No `copy`, no `componentN`

KEEP-0340 gave the reasons. `copy` is verbose, nests badly, and does
not work with operators (`a = a.copy(b = a.b + 2)` instead of
`a.b += 2`). Positional destructuring exposes field order.
KEEP-0454 adds a binary-compatibility argument: `copy` breaks when a
field is added, while withers and copy vars do not.

### Ergonomic updates: lenses vs withers vs copy vars

KEEP-0453 compares three options:

```kotlin
// Lenses (Arrow Optics)
User.address.zipCode.code.modify(user) { "1079MZ" }

// Withers (Lombok, Java JEP 468 style)
user.withAddress(user.address.withZip(zip))

// Copy vars (design-notes sketch)
user.address.zipCode.code = "1079MZ"
```

- **Lenses** compose well, but "feel more like a library trick" and
  sit outside the data.
- **Withers** are familiar from Java and binary-friendly, but you
  still get the "wither ladder".
- **Copy vars** use mutable value semantics, as Swift structs do:
  "mutable xor shared". This is the current favourite. Its cost is a
  third kind of property next to `val` and `var`. The design notes
  pick `copy var` over reusing `var`. A value class can legitimately
  have ordinary `var` properties with custom accessors that mutate an
  underlying handle, so a context-dependent `var` would confuse
  people. The notes reject Swift's `mutating` keyword for the same
  reason: the receiver is copied, not mutated.

### `@WillBecomeValue` naming

| Rejected | Why |
|---|---|
| `@ValueBased` | Confusing next to `value class` |
| `@IdentityFree` | Second name for the same concept |
| `@TreatAsValue` | Hides why it is not one yet |

The JDK's `@jdk.internal.ValueBased` (JEP 390) is JVM-only and
internal to the JDK, so Kotlin cannot reuse it for its own types.
Kotlin already warns on `@ValueBased` JDK classes (KT-70722).

### Comparison with other languages

```kotlin
// Kotlin value class: no identity, any size,
// boxed or flattened at the compiler's discretion
value class Vec(val x: Double, val y: Double)
```

- **Valhalla Java**: closest in spirit. Value classes, abstract value
  classes, early initialisation and `==` as substitutability. Kotlin
  deliberately keeps its restrictions a superset of Valhalla's.
- **C#/Swift/Rust/Go structs**: the design notes explain why value
  classes are *not* structs. A struct promises to be embedded and
  copied. A value class only promises no identity, so a large value
  can stay a pointer. Valhalla also keeps big values on the heap.
- **Swift**: the inspiration for copy vars (struct `var` properties)
  and for `Boolean.toggle()`.
- **Scala**: Scala 3 opaque types are erased type aliases with no Java
  story. Scala 2 value classes are close to Kotlin inline classes, but
  keep the boxed class and its members available. That is roughly what
  `@JvmExposeBoxed` adds.

## Open questions and what may change

The ergonomic-updates KEEP is not published. Copy vars are the
favourite, not a decision. Lenses and withers are still being
considered.

```kotlin
// Not specified anywhere yet:
// copy var? copy fun? copy-typed lambdas? withX()?
```

Other open items:

- **`===` semantics** for value types reached through generics or
  `Any`. The candidates are negative bounds, debug checks and
  substitutability. The KEEP's call to action asks the community
  directly.
- **Deep immutability** is "a second-order extension". It needs
  immutable collections, arrays, and a bridge to reference types. It
  would make MFVCs "compile-time checked stable types for Compose".
- **`hasIdentity()`** is only proposed.
- **Typed `equals`** (KEEP-0456) is a listed dependency of the MFVC
  release.
- **Stage 0 to stage 1 migration** via `@JvmExposeBoxed` plus
  something like `@JvmInline(deprecated = true)`. That syntax is
  "back-of-the-envelope".
- **`@GenerateDataClassMethods`** is "back-of-napkin syntax".
- **Delegation to stable expressions** depends on a guaranteed
  optimisation.
- **Stricter early initialisation** depends on a Kotlin version of
  JEP 513.
- **Struct exports** for Native, Wasm and Swift.
- **`vararg` and `VArray`** for full value classes are not addressed
  in KEEP-0454.
- **The `@WillBecomeValue` declaration differs** between KEEPs.
  KEEP-0454 sketches it with `@SinceKotlin("2.X")`, retention
  `BINARY`, and "actual name to be decided later". KEEP-0470 adds
  `@MustBeDocumented` and an `@ExperimentalValueClassApi` opt-in at
  level `ERROR`, and calls that opt-in name "tentative".
- **Dependencies** that KEEP-0454 lists for the MFVC release:
  `@WillBecomeValue`, typed `equals`/`hashCode`, name-based
  destructuring, early-initialisation design, and version overloading.
- **The flag schedule** (2.5.20, 2.6, 2.7+) comes from a KEEP in
  public discussion. Treat it as the plan, not a promise.

```kotlin
// Tentative names that may change:
// kotlin.WillBecomeValue, kotlin.ExperimentalValueClassApi
```

## Cheat sheet

```kotlin
// Full value class (any number of vals)
value class Money(val cents: Long, val cur: String)

// Inline kind, explicit, all platforms
inline value class UserId(val raw: String)
@JvmInline value class Legacy(val raw: String) // same

// Abstract/sealed parents and value objects
sealed value class Shape
value class Circle(val r: Double) : Shape()
value object Empty : Shape()

// Name-based destructuring
val (cur, cents) = Money(100, "EUR")

// Migration helper for future value classes
@OptIn(ExperimentalValueClassApi::class)
@WillBecomeValue class Uuid(val hi: Long, val lo: Long)
```

- No identity: `===` is an error on the type. Through `Any` or
  generics, `===` is unspecified.
- `equals`, `hashCode` and `toString` are generated. `copy` and
  `componentN` are not.
- Only primary `val`s are stored. No other backing fields, no
  delegation, no `lazy`.
- Never `open`. Abstract value classes store nothing. Only interfaces
  and abstract value classes can be supertypes.
- Primary properties are smart-cast-stable across modules.
- Primary properties are assigned before `super()`, as Valhalla
  requires.
- Stage 0 (inline) to stage 1 (full) breaks the ABI. Stage 1 to
  stage 2 (Valhalla) should be seamless.
- Java sees mangled names and underlying types for the inline kind,
  unless you use `@JvmExposeBoxed`. For full value classes it sees an
  ordinary class (boxed).
- Flags: `-Xinline-value-class-migration=warning|strict`,
  `-Xfull-value-classes=on|off`.
- KEEP-0454 is experimental (phase I) in 2.5. KEEP-0468 and KEEP-0470
  are proposals.

## Talking points

- "A value class is a data class that gave up its identity and
  promised never to change."
- "Value classes are now about immutability, not performance.
  Performance is a bonus that Valhalla delivers later, without you
  recompiling your callers."
- "Multi-field value classes ship as plain boxes. That is why they
  don't wait for Valhalla, and why they work on Android and every KMP
  target."
- "`inline value class` says out loud what your serializer already
  assumed: this wrapper disappears at runtime."
- "No `copy()`, on purpose. Copy vars are coming so that
  `order.status = Shipped` copies instead of mutating."
- "Value class properties are smart-cast-stable across modules. Data
  class properties are not."
- "`@WillBecomeValue` is Kotlin's version of the JDK's `@ValueBased`:
  warnings today, value class tomorrow."
- "An abstract value class can have a regular class as a subclass.
  Identity can be added, never removed."

**Q: Can I just remove `@JvmInline` and get a multi-field-ready
class?**
No, not without breaking binaries. Compiled callers pass the
underlying type, for example `int` or `String`, under mangled names.
A full value class is passed as a box. KEEP-0454 calls this hop
"unfortunately a breaking change". The suggested escape hatch is
`@JvmExposeBoxed` to expose both forms, then deprecate the inline
form, then remove it. That deprecation step is still only sketched.

**Q: If `===` is forbidden, what does `listOf(a).contains(b)` or an
`IdentityHashMap` do?**
`contains` uses `equals`, so it works structurally. Identity-based
containers receive boxes through `Any`. They compile, and the result
depends on whether the runtime reused a box. The KEEP knows about
this hole. It proposes `Any?.hasIdentity()` for code that needs to
check, and lists ways to fix `===` later.

**Q: Will my value class be flattened like a C struct on a Valhalla
JVM?**
Kotlin's job is to compile it to a JVM value class with compatible
restrictions. Whether it is flattened is up to the JVM, which keeps
large values on the heap, just as the design notes say a value class
"enables, but does not guarantee" such optimisations. Correctness
never depends on it, because no code can observe the difference.
