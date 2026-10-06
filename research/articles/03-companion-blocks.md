---
title: "Companion Blocks and Companion Extensions"
subtitle: "Statics for Kotlin without a new concept: companion, minus the object"
author: "Notes from KEEP-0449, KEEP-0427, KEEP-0150, KEEP-0152"
date: "October 2026"
lang: en
---

## At a glance

| KEEP | What | Status |
|---|---|---|
| [0449](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0449-companions-block-extension.md) | Companion blocks and extensions | Experimental in 2.5.0 (expected) |
| [0427](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0427-static-member-type-extension.md) | `static` members, `T::static` extensions | Rejected in favor of 0449 |
| [0150](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0150-jvm-static-annotation-in-interface-companion.md) | `@JvmStatic` in interface companions | Stable in 1.3 |
| [0152](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0152-jvm-field-annotation-in-interface-companion.md) | `@JvmField` in interface companions | Stable in 1.3 |

- **Kotlin version**: KEEP-0449 says "Experimental in 2.5.0
  (expected)". In practice, kotlinc 2.4.20 (this project's
  version) already accepts companion blocks behind a flag
  (observed, not in the KEEP). The examples below follow the
  KEEP and were not all compile-checked against 2.4.20.
- **How to enable**: `-Xcompanion-blocks-and-extensions`, taken
  from this project's `build.gradle.kts`. The KEEP itself
  does not name a flag.
- **Discussion**: [KEEP discussion
  #467](https://github.com/Kotlin/KEEP/discussions/467).
- **YouTrack**: KT-11968 (extend the companion scope of a type
  with no companion), KT-15595 (drop the empty companion),
  KT-16872 (do not generate both the static and the instance
  method).
- **Lineage**: KEEP-347 ("Statics and static extensions") was
  replaced by KEEP-0427, which was rejected in favor of KEEP-0449.

The teaser, straight from the KEEP's TL;DR:

```kotlin
data class Vector(val x: Double, val y: Double) {
    companion { // companion block
        val Zero: Vector get() = Vector(0.0, 0.0)
    }
}

// companion extension
companion val Vector.UnitX get() = Vector(1.0, 0.0)
```

Three claims carry the whole design:

- A companion extension can target a type with no companion
  object and no companion block, including Java types.
- Companion block members become real platform statics where the
  platform has them (JVM, JS, Swift).
- Companion blocks and extensions win over companion objects in
  resolution.

## The problem

Kotlin's answer to "class members" (Java's `static`) has always
been the companion object: an object nested in the class whose
members you reach through the class name.

```kotlin
data class Vector(val x: Double, val y: Double) {
    companion object {
        val Zero: Vector = Vector(0.0, 0.0)
    }
}

fun Vector.isZero() = this == Vector.Zero
```

It is flexible: the companion is a value, it can implement an
interface, you can pass it around. KEEP-0449 lists five places
where it falls short, and is explicit that they hurt different
users by different amounts. That framing matters: there is no
single "statics problem", and the design is a trade-off across
all five.

### #1 You cannot extend a companion that does not exist

You can add a "static-looking" function today by extending the
companion object:

```kotlin
val Vector.Companion.UnitX get() = Vector(1.0, 0.0)

val u = Vector.UnitX
```

But only if the author wrote a `companion object`. Java types
never have one, and plenty of Kotlin types do not either.

```kotlin
// java.util.UUID: no Kotlin companion object
val UUID.Companion.Nil: UUID  // ERROR: unresolved Companion
    get() = UUID(0L, 0L)
```

This is KT-11968, one of the oldest open requests in the tracker.

### #2 Mapping to platform statics is clumsy

Frameworks often demand a real static. JUnit 4's `@BeforeClass`
is the classic:

```kotlin
class OrderRepositoryTest {
    companion object {
        @BeforeClass @JvmStatic
        fun startDatabase() { /* ... */ }
    }
}
```

Forget `@JvmStatic` and the test either fails at runtime or,
worse, runs with unintended behavior. Getting it right requires
knowing Kotlin's compilation strategy, not just Kotlin and the JVM.

### #3 One annotation per platform

`@JvmStatic`, `@JsStatic`, and so on. Multiplatform library
authors must remember each one. KEEP-0449 declares a
multiplatform `@Static` out of scope, but companion blocks make
it largely unnecessary.

### #4 An extra object allocation

A companion object is an object. On the JVM, `Vector.Zero`
compiles to `Vector.Companion.INSTANCE.getZero()`:

```java
class Vector {
    static class Companion {
        private Companion() { }
        public static Companion INSTANCE = Companion();
        public Vector getZero() {
            return new Vector(0.0, 0.0);
        }
    }
}
```

`@JvmStatic` does not remove the object. It adds a static bridge
that calls the instance method:

```java
class Vector {
    static Vector getZero() {
        return Vector.Companion.INSTANCE.getZero();
    }
}
```

In an application with thousands of classes (the KEEP names
IntelliJ IDEA) that is thousands of extra classes to load and
initialize. Converting Java to Kotlin doubles the class count for
every class with statics, which shows up in startup time. On
Native there is no JIT, so every companion access may also pay
for an "is it created yet?" check.

Simply dropping the empty companion (KT-15595) or the duplicate
method (KT-16872) would break binary compatibility: code compiled
against the old shape would stop linking.

### #5 No expect/actual matching against statics

Kotlin has no statics, so an `expect` class cannot be
`actual`ized by a Java class whose members are static:

```kotlin
expect class Vector {
    companion object {
        val Zero: Vector
    }
}
// a Java Vector with `static Vector getZero()`
// cannot actualize this
```

Niche, but it blocks libraries that want to wrap existing Java
code in an expect/actual facade on the way to multiplatform.

## The feature, step by step

### Step 1: a companion block

Drop the word `object`:

```kotlin
data class Vector(val x: Double, val y: Double) {
    companion {
        val Zero: Vector = Vector(0.0, 0.0)
    }
}

val origin = Vector.Zero
```

Use sites do not change. What changes is what you lose. A
companion block keeps the *companion* half of a companion object:

- its members are reachable through the type name,
- they participate in context-sensitive resolution.

and drops the *object* half:

- there is no classifier you can refer to (no `Vector.Companion`),
- there is no instance holding the members.

### Step 2: no instance means no value

The type name is not an expression when only a companion block
exists:

```kotlin
val v = Vector(3.0, 4.0)
val z1 = v.Zero      // ERROR: not reachable via instance
val c = Vector       // ERROR: Vector is not a value
```

If you need the companion as a value (pass it, implement an
interface with it), you need a companion object. That is the
dividing line the KEEP draws.

### Step 3: several blocks, unqualified use inside the class

A class may have more than one companion block (§1.2.1). The
members are visible unqualified from the class body:

```kotlin
data class Vector(val x: Double, val y: Double) {
    companion {
        val Zero: Vector = Vector(0.0, 0.0)
    }

    fun normalize(): Vector = when (this) {
        Zero -> this
        else -> scale(1 / length())
    }

    fun length() = kotlin.math.sqrt(x * x + y * y)
    fun scale(k: Double) = Vector(x * k, y * k)

    companion {
        const val Dimensions: Int = 2
    }
}
```

This is KEEP Example 1.1 fleshed out. Note `const val` is
allowed in a block (§1.4).

### Step 4: a companion extension

Put `companion` in front of a top-level function or property
with a receiver type:

```kotlin
companion val Vector.UnitX: Vector
    get() = Vector(1.0, 0.0)

companion fun Vector.polar(r: Double, a: Double) =
    Vector(r * cos(a), r * sin(a))

val diagonal = Vector.polar(1.0, PI / 4)
```

The receiver is a *type*, not a value: there is no `this` of
type `Vector` inside the body. It is the type name you write
before the dot at the call site.

### Step 5: extend a type with no companion at all

This is the headline for KT-11968. The receiver needs no
companion object and no companion block:

```kotlin
import java.util.UUID

companion val UUID.Nil: UUID = UUID(0L, 0L)

companion fun UUID.parseOrNull(s: String): UUID? =
    runCatching { UUID.fromString(s) }.getOrNull()

val id = UUID.parseOrNull("not-a-uuid") ?: UUID.Nil
```

Java statics (`UUID.fromString`, `UUID.randomUUID`) and your
companion extensions now share one call syntax.

The same works for stdlib interfaces (my reading of §1.3.2, which
allows classes and interfaces):

```kotlin
companion fun <T> List.ofNotNull(
    vararg items: T?,
): List<T> = items.filterNotNull()

val tags = List.ofNotNull("kotlin", null, "jvm")
```

### Step 6: companion extension properties can hold state

Ordinary extension properties cannot have initializers or backing
fields. Companion extension properties can (§1.3.5), because they
are really top-level properties attached to a type name:

```kotlin
companion val Money.Zero: Money = Money(0, "EUR")

companion var HttpClient.defaultTimeoutMs: Long = 30_000

@JvmField
companion val Temperature.AbsoluteZero =
    Temperature(-273.15)
```

`@JvmField` is explicitly allowed. Regular extension properties
cannot do any of this.

### Step 7: fake constructors with `invoke`

Operators are forbidden in companion blocks, with two exceptions:
`invoke` and `of` (§1.2.4). `invoke` gives you a constructor-like
call that can `suspend` or take context parameters:

```kotlin
data class Vector(val x: Double, val y: Double) {
    companion {
        suspend operator fun invoke(
            file: StructureFormat,
        ): Vector {
            val x = file.readDouble()
            val y = file.readDouble()
            return Vector(x, y)
        }
    }
}

suspend fun load(f: StructureFormat) = Vector(f)
```

`of` is the hook for collection literals (KEEP-0416):

```kotlin
class Path(val segments: List<String>) {
    companion {
        operator fun of(
            vararg parts: String,
        ): Path = Path(parts.toList())
    }
}

val p: Path = ["api", "v1", "orders"]
```

Companion extensions may define `invoke` but **not** `of`
(§1.3.4). More on why in the rules section.

## Typical usage

### Domain constants without the allocation

```kotlin
@JvmInline
value class Money(val cents: Long) {
    companion {
        val Zero: Money = Money(0)
        const val CentsPerUnit: Long = 100

        fun of(units: Long): Money =
            Money(units * CentsPerUnit)
    }
}
```

On the JVM, `Money.Zero` becomes a static getter on `Money` with
a private static field initialized in `<clinit>`. No
`Money.Companion` class exists.

### Validated factories next to a private constructor

```kotlin
class Email private constructor(val value: String) {
    companion {
        fun parse(raw: String): Email? =
            if ("@" in raw) Email(raw.trim()) else null
    }
}

val e = Email.parse("simon@example.com")
```

The block lives inside the class, so it sees the private
constructor. A companion extension would not.

### JUnit and other "needs a real static" frameworks

```kotlin
class OrderRepositoryTest {
    companion {
        @BeforeClass
        fun startDatabase() { /* ... */ }
    }
}
```

Companion block members compile to static members of the class
(§4.1.1), which is exactly what JUnit's reflection looks for. My
reading: no `@JvmStatic` needed, because there is no instance
method to bridge to.

### Library ergonomics: extending types you do not own

```kotlin
companion fun Duration.ofMinutesAndSeconds(
    m: Int,
    s: Int,
): Duration = m.minutes + s.seconds

companion fun HttpStatusCode.isRetryable(
    code: Int,
): Boolean = code == 429 || code >= 500
```

A library can add "static" helpers to `kotlin.time.Duration` or a
Ktor type without asking the owner to add a companion.

### Enums: helpers next to the entries

```kotlin
enum class HttpMethod {
    GET, HEAD, POST, PUT, DELETE;

    companion {
        val Safe: Set<HttpMethod> = setOf(GET, HEAD)

        fun parse(s: String): HttpMethod? =
            entries.firstOrNull {
                it.name.equals(s, ignoreCase = true)
            }
    }
}
```

Entries are initialized before the rest of companion
initialization (§3.2.2), so `Safe` can reference `GET` safely.

### Collection factories in the stdlib

KEEP-0416 (collection literals) plans to put `of` into a
companion block on `List`, `Set`, `Sequence`, the array types and
their mutable variants once companion blocks stabilize:

```kotlin
public expect interface List<out E> {
    // ...
    public companion {
        public operator fun <T> of(
            vararg elements: T,
        ): List<T>
    }
}

val xs = List.of(1, 2, 3)
```

On the JVM `List` maps to `java.util.List`, which Kotlin cannot
change. KEEP-0416 suggests implementing the mapped block the way
`Int.Companion` maps to `IntCompanionObject`.

### Multiplatform facades over Java

```kotlin
// commonMain
expect class Vector {
    companion {
        val Zero: Vector
    }
}
```

Members in a companion block may omit their body when marked
`expect` (§1.2.5), and static members of a Java class may
`actual`ize them (§4.1.5). Combined with §1.3.3, an `expect`
class can also be actualized by a type alias to that Java class.

## Rules and edge cases

### What a companion block may contain

Only functions and properties (§1.1 grammar). No constructors, no
`init` blocks, no extension members, and no operators other than
`invoke` and `of` (§1.2.4).

```kotlin
class Order {
    companion {
        init { }                      // ERROR: no init
        fun String.toOrderId() = 1L   // ERROR: extension
        operator fun plus(x: Int) = 1 // ERROR: operator
        class Builder                 // ERROR: not allowed
    }
}
```

The `plus` ban follows from "the type name is not a value": if
`plus` were allowed you would have to accept `Order + 1`. `invoke`
and `of` are tolerated because there the type name acts as a
scope (a fake constructor, a collection literal), not as a value.

No `init` is deliberate: "No complex initialization semantics".
Class initialization order is already a source of hard bugs; the
KEEP refuses to add a general way to run arbitrary code at class
init. Property initializers are the only hook.

### No inheritance modifiers, bodies required

```kotlin
class Order {
    companion {
        open fun create(): Order = Order()  // ERROR
        abstract fun empty(): Order         // ERROR
        fun fromJson(s: String): Order // ERROR: no body
    }
}
```

Members may not be `open`, `abstract`, `final` or `override`
(§1.2.5). So every member needs a body, except `expect` and
`external` ones.

### Where blocks and extensions are not allowed

```kotlin
object Registry {
    companion { }          // ERROR: blocks not in objects
}

companion fun Registry.reset() { } // ERROR: object receiver

class Order {
    companion fun Order.empty() = Order() // ERROR
}
```

- No companion block inside an `object` (§1.2.2). For an object,
  the type name already *is* the instance.
- A companion extension's receiver must be a class or interface,
  never an object (§1.3.2).
- `companion` as a modifier is only for top-level callables
  (§1.3.1). Member companion extensions are gone; with context
  parameters you can still demand extra scope.

### Receiver type restrictions

The receiver must be a declared classifier or type alias, with no
type arguments and no type parameters (§1.3.2):

```kotlin
companion fun List.noInts() = emptyList<Int>()  // ok
companion fun List<Int>.zeros() = 0             // ERROR
companion fun <A> A.none(): A? = null           // ERROR
companion fun Array.sizeLimit() = Int.MAX_VALUE // ok
companion fun Array<Int>.x() = 0                // ERROR
```

This is stricter than class literals: even `reified` type
parameters are out, and `Array` must appear bare. Other positions
in the signature are free, so generics move to the function:

```kotlin
companion fun <T> List.ofNotNull(
    vararg items: T?,
): List<T> = items.filterNotNull()
```

(The KEEP's own example of this rule writes
`fun <T> Example.from(elements: List<T>)` without the `companion`
modifier; the intent is clearly a companion extension.)

### Type aliases

A type alias in receiver position means the outer type of its
expansion (§1.3.3). Nullability (`?` or `& Any`) is dropped first,
and function types are rejected:

```kotlin
typealias Edges<T> = List<Pair<T, T>>
companion fun Edges.none() = 0      // same as List.none()

typealias MaybeUser = User?
companion fun MaybeUser.guest() =   // same as User.guest()
    User("guest")

typealias Handler = (Request) -> Response
companion fun Handler.noop() = 0    // ERROR: function type
```

The same rule applies at the call site (§2.3.3):

```kotlin
class Cache<T> {
    companion {
        fun capacity(): Int = 1024
    }
}

typealias IntCache = Cache<Int>?
val n = IntCache.capacity()  // same as Cache.capacity()
```

The reason is multiplatform: an `expect` class can be actualized
by a type alias, and calls must keep resolving.

### No annotations on the receiver

```kotlin
companion fun @Ann Vector.bad() = 0    // ERROR
@receiver:Ann
companion fun Vector.alsoBad() = 0     // ERROR
```

§1.3.7 forbids annotating the receiver in any way, including
`@receiver` and `@type` use sites. This lets a platform erase the
receiver completely. Related, §1.3.6: the receiver does not count
as a formal parameter.

### The resolution order for `T.f()`

Companion block members and companion extensions are reached
through the *phantom static implicit `this`*, a receiver the spec
already uses for enum entries and Java statics. The spec says that
receiver beats the companion object receiver. §2.3.1 extends the
order for an explicit type receiver `T`:

1. Static members **and companion block members** of `T`.
2. Implicitly declared static members of `T`.
3. **Companion extensions** of `T`.
4. Everything you would get for `T.Companion.f()`, i.e.
   companion object members and their extensions.

```kotlin
class Example {
    companion object {
        fun test() { }            // (1)
    }
}

companion fun Example.test() { }  // (2)

fun use() {
    Example.test()            // resolves to (2)
    Example.Companion.test()  // resolves to (1)
}
```

A companion extension, even a top-level one, beats a member of
the companion object. Blocks and extensions act as one receiver
that is exhausted before the companion object is tried. The
escape hatch is to write `T.Companion` explicitly, which only works
in that direction: there is no syntax to name the companion block.

The same applies to companion object *extensions*:

```kotlin
class Example { companion object }

fun Example.Companion.foo() = 1   // (1)
companion fun Example.foo() = 2   // (2)

val r = Example.foo()             // resolves to (2)
```

### Blocks and objects in the same class

Both may coexist (§1.2.3):

```kotlin
class Example {
    companion {
        fun foo() { }  // (1)
        fun bar() { }  // (2)
    }

    companion object {
        fun foo() { }  // (3)

        fun inside() {
            foo()          // (3)
            Example.foo()  // (1)
            bar()          // (2)
            Example.bar()  // (2)
        }
    }
}
```

Inside the companion object, the object's own receiver has the
highest priority, so bare `foo()` is (3). The phantom static
`this` of the enclosing class is still there, so `bar()` finds the
block member. Now move that code to an extension on the companion:

```kotlin
fun Example.Companion.outside() {
    foo()          // (3)
    Example.foo()  // (1)
    bar()          // ERROR: unresolved
    Example.bar()  // (2)
}
```

An extension to the companion object only gets the companion
object receiver, not the enclosing class's static scope.

### What is in scope inside a block member

The class instance `this` is absent (§2.2.1), and so is the
companion object receiver:

```kotlin
class Order(val total: Money) {
    companion object {
        fun currency() = "EUR"
    }

    companion {
        fun empty(): Order {
            println(total)      // ERROR: no instance
            println(currency()) // ERROR: no object scope
            println(Order.currency()) // ok, qualified
            return Order(Money.Zero)
        }
    }
}
```

`this` does not reach the phantom static receiver either (§2.1.2):

```kotlin
class Order {
    companion {
        fun self() = this   // ERROR: no `this` here
    }
}
```

### What is in scope inside a companion extension

Only the phantom static `this` of the receiver type, at the
highest priority (§2.2.2). No companion object receiver, so the
code generation does not depend on whether a companion object
exists:

```kotlin
class Example {
    companion object {
        fun test() { }
    }
}

companion fun Example.example() {
    test()          // ERROR: companion object not in scope
    Example.test()  // ok: companion object member
}
```

This is a visible change from KEEP-0427, whose type extensions
did bring the companion object into scope.

Block members and companion extensions see each other
unqualified, from either side (Example 2.4):

```kotlin
class Example {
    companion {
        fun inBlock() { }
        fun fromBlock() {
            inBlock()
            ext()
        }
    }
}

companion fun Example.ext() { }

companion fun Example.fromExt() {
    inBlock()
    ext()
}
```

### Instance members versus block members

From instance code, block members are reachable unqualified
"unless they conflict with an actual member". The instance `this`
outranks the phantom static `this`:

```kotlin
class Account(val id: String) {
    fun label() = "acct-$id"           // (1)

    companion {
        @JvmName("defaultLabel")
        fun label() = "acct-unknown"   // (2)
    }

    fun show() = label()               // (1)
    fun fallback() = Account.label()   // (2)
}
```

The `@JvmName` is not decoration: on the JVM both would be
`label()Ljava/lang/String;`, one static and one instance, and the
JVM forbids that (Example 4.1.2).

### Callable references

§2.3.2 adds blocks and companion extensions to callable reference
resolution, before instance members:

```kotlin
data class Vector(val x: Double, val y: Double) {
    companion {
        val Zero = Vector(0.0, 0.0)
    }
}

companion fun Vector.unit(dim: Int): Vector =
    if (dim == 0) Vector(1.0, 0.0)
    else Vector(0.0, 1.0)

val z: KProperty0<Vector> = Vector::Zero
val u: (Int) -> Vector = Vector::unit
```

The receiver type never appears in the reference's type. Note
`KProperty0`, not `KProperty1<Vector, ...>`. Ordering detail (my
reading of the list): `Vector::f` checks companion block members
and companion extensions *before* instance members, so a block
member shadows a same-named instance member in a reference.

### Imports

Block members are imported like Java statics (§1.2.6):

```kotlin
import geo.Vector.Zero

val origin = Zero
```

Companion extensions are top-level declarations. The KEEP wants
to "explore ways to automatically import" those declared next to
the type, as companion object members are visible once the type
is imported. That is a stated aim, not a rule yet.

### Context-sensitive resolution

Block members "participate in context-sensitive resolution"
(KEEP-379), so with an expected type you can drop the prefix:

```kotlin
fun describe(v: Vector) = when (v) {
    Zero -> "zero vector"
    else -> "(${v.x}, ${v.y})"
}
```

Whether companion extension *properties* such as `UnitX` are
found the same way is not spelled out in KEEP-0449 (KEEP-0427's
example showed it for its type extensions). Treat it as open.

### Superclasses: scope linking, not inheritance

Block members are not inherited. A subclass member with the same
signature *hides* rather than overrides. But the parent's scope is
*linked* to the child's body, which looks like inheritance for
short names (§2.5, Example 2.7):

```kotlin
open class Shape {
    companion {
        fun unit() = 1.0
    }
}

companion fun Shape.origin() = 0.0

class Circle : Shape() {
    fun area() {
        unit()          // ok, scope linking
        Shape.unit()    // ok
        Circle.unit()   // ERROR: not on Circle
        origin()        // ERROR: ext needs static this
        Shape.origin()  // ok
        Circle.origin() // ERROR
    }
}
```

The asymmetry is the trap: bare `unit()` works, bare `origin()`
does not, because companion extensions only come through the
phantom static `this`, which only covers `Circle` itself. The
KEEP admits this "leads to a more complicated mental model" but
declines to deprecate superclass linking here. It is the same
rule nested classes already follow (`Nested()` works in a
subclass, `B.Nested()` does not).

### Generics and the class's type parameters

KEEP-0449 does not state a rule. KEEP-0427 forbade static members
from referencing the enclosing class's type parameters and told
you to introduce a fresh one. My reading: the same holds for
blocks, since there is no instance to fix `T`:

```kotlin
class Box<T>(val value: T) {
    companion {
        fun empty(): Box<T>? = null  // ERROR (my reading)
        fun <T> of(v: T): Box<T> = Box(v)  // ok
    }
}
```

### Constants and initialization order

Constants are a separate scope linked to the rest of the static
scope (§2.4), and they are initialized before any other
companion property (§3.2). So a block property may use a `const`
declared later:

```kotlin
class Http {
    companion {
        val defaultUrl = "http://localhost:$Port"
        const val Port: Int = 8080
    }
}
```

Non-constant out-of-order reads are explicitly undefined
behavior:

```kotlin
class Problem {
    companion {
        val a = getTheB()   // undefined behavior
        val b = 5
        fun getTheB() = b
    }
}
// on the JVM: a == 0 (default field value)
```

### When companion initialization happens

§3.1 lists the minimum triggers. Initialization must happen
before:

1. a constructor of the class is called,
2. its companion object is accessed,
3. an enum entry is accessed,
4. a non-`const` block member is accessed or called,
5. an implicit static member like `entries` is used.

Platforms may do it earlier (JVM reflection triggers class init).
Within it, program order holds, constants first. Following the
JVM, initializing a class also initializes its superclass and
every superinterface with at least one non-abstract member
(§3.3), recursively.

Calling a companion extension does **not** initialize the
extended class (§3.4). Its own properties initialize like
top-level properties:

```kotlin
companion val Vector.hasFiniteBasis: Boolean = true

fun findBasis(): List<Vector> {
    if (!Vector.hasFiniteBasis) return emptyList()
    // Vector may not be initialized yet here
    return listOf(Vector.UnitX)
}
```

### Enums

Entries, `entries`, `valueOf` and `values` "officially" become
companion block members (§1.5):

```kotlin
enum class Direction { UP, DOWN }

// is considered as
class Direction : Enum<Direction> private constructor() {
    companion {
        public val UP: Direction
        public val DOWN: Direction
        public val entries: EnumEntries<Direction>
        public fun valueOf(value: String): Direction
        public fun values(): Array<Direction>
    }
}
```

Initialization order (§3.2.2): entries, then `entries`/`values`
support, then your companion initialization in program order. A
consequence of the resolution order: an enum's companion
extension cannot hijack an entry, because block members (step 1)
beat companion extensions (step 3):

```kotlin
companion val Direction.UP: Int = 1  // declared fine
val d = Direction.UP  // the entry, not the extension
```

(That last pair is my reading of §2.3.1; the KEEP does not show
it.)

### Interfaces

Companion blocks work in interfaces too. The appendix handles the
JVM restriction that interface fields must be `public static
final`: private state moves to a hidden nested class.

```kotlin
interface IdGenerator {
    fun next(): Long

    companion {
        var issued: Int = 0
        const val Prefix: String = "id-"
    }
}
```

Interface-specific rules from the appendix:

- `const val` stays on the interface itself, so it must be
  `public` or `internal`.
- Several blocks and companion objects each become a separate
  nested class; initialization follows declaration order.
- `@JvmField` is all-or-nothing across all blocks and objects of
  the interface. If all properties use it, no nested class is
  generated, and the fields must be public or internal.
- `private` members become legal in interface companions (statics
  do not take part in inheritance). `protected` stays forbidden.

```kotlin
interface Plugin {
    companion {
        @JvmField val ApiVersion: Int = 3
        val registry = mutableListOf<String>() // ERROR:
        // mix of @JvmField and plain properties
    }
}
```

The `@JvmField` all-or-nothing rule mirrors KEEP-0152's existing
restriction on interface companion *objects*: `@JvmField` there is
"applicable only if all companion properties are `public final
val` annotated with `@JvmField`".

### Collection literal `of`: blocks yes, extensions no

```kotlin
class Path(val parts: List<String>) {
    companion {
        operator fun of(vararg p: String) =
            Path(p.toList())
    }
}

class Query(val terms: List<String>)

companion operator fun Query.of(  // ERROR: §1.3.4
    vararg t: String,
) = Query(t.toList())
```

KEEP-0416 explains: extensions can win over inapplicable members,
and allowing them would force the compiler to consider every
imported `of`, defeating the declaration-site checks. KEEP-0416
also forbids eligible `of` declarations in both the companion
object and a companion block of the same type, since a `vararg`
candidate in the block would always win.

### Migration from companion objects

First, when you cannot migrate. The companion object must stay if
it:

1. is used as a value,
2. participates in inheritance (implements an interface, extends
   a class),
3. defines operators other than `invoke` and `of`.

```kotlin
class User(val name: String) {
    companion object : Comparator<User> {
        override fun compare(a: User, b: User) =
            a.name.compareTo(b.name)
    }
}

val sorted = users.sortedWith(User)  // a value: keep it
```

The KEEP's honest note: in an established codebase the gain is
often small. If what you want is Java-friendly statics, keep the
companion object and add `@JvmStatic`.

**When neither source nor binary compatibility matters** (an
application, not a library), only declaration sites change. In
this order, the code compiles at each step:

1. Turn extensions on the companion object into companion
   extensions.
2. Drop `object` from `companion object`.

```kotlin
// before
class Vector(val x: Double, val y: Double) {
    companion object {
        val Zero = Vector(0.0, 0.0)
    }
}
val Vector.Companion.UnitX get() = Vector(1.0, 0.0)

// after
class Vector(val x: Double, val y: Double) {
    companion {
        val Zero = Vector(0.0, 0.0)
    }
}
companion val Vector.UnitX get() = Vector(1.0, 0.0)
```

(The KEEP's step 1 literally says "to object extensions"; from
context it means companion extensions.)

**For a library**, move the code first and delegate:

```kotlin
class Example {
    companion {
        fun foo() { /* real code */ }
    }

    companion object {
        @Deprecated("Use the companion block")
        fun foo() = Example.foo()  // the block's foo
    }
}
```

`Example.foo()` resolves to the block because blocks beat
objects. Then, depending on your consumers:

- Still compiled with pre-feature Kotlin versions: keep the
  companion object as is; both old and new stay source and binary
  compatible.
- Only binary compatibility matters: deprecate the companion
  object as hidden, so new code always resolves to the block.
- Later: remove the companion object. (The KEEP says "the
  companion block" here; it must mean the object.)

A JVM wrinkle (my reading, not in the KEEP): if the old companion
member had `@JvmStatic`, the class already has a static
`foo()`. The new block member also compiles to static `foo()` on
the class, so keeping `@JvmStatic` on the delegating copy would be
a platform clash. Drop the annotation; Java callers of
`Example.foo()` keep working, now hitting the real static.

## Platform interop

### JVM: companion block members are statics

§4.1.1 and §4.1.2: members become static members of the class,
backing fields become private static fields, and companion
initialization goes into `<clinit>` in program order.

```kotlin
// file Vector.kt
data class Vector(val x: Double, val y: Double) {
    companion {
        val Zero: Vector = Vector(0.0, 0.0)
        const val Dimensions: Int = 2
    }
}

companion fun Vector.unit(dim: Int): Vector =
    Vector(1.0, 0.0)
```

```java
class Vector {
    // instance fields and constructor omitted

    private static final Vector Zero;
    public static Vector getZero() { return Zero; }

    public static final int Dimensions = 2;

    static {
        Zero = new Vector(0.0, 0.0);
    }
}

class VectorKt {
    static Vector unit(int dim) { ... }
}
```

No `Vector$Companion` class, no `INSTANCE`, no bridge. From Java:

```java
Vector origin = Vector.getZero();
int dims = Vector.Dimensions;
Vector ux = VectorKt.unit(0);
```

### JVM: companion extensions are file-facade statics

§4.1.3: a companion extension is a static member of the file's
`FileKt` class, **without** a parameter for the receiver. Its name
is the source name unless `@JvmName` overrides it. Compare with a
regular extension, where the receiver is the first parameter:

```kotlin
fun Vector.len() = sqrt(x * x + y * y)
companion fun Vector.unit(dim: Int) = Vector(1.0, 0.0)
```

```java
// in VectorKt
static double len(Vector receiver) { ... }
static Vector unit(int dim) { ... }
```

Erasing the receiver causes clashes in one file:

```kotlin
companion fun Money.zero() = Money(0)  // ERROR:
companion fun Vector.zero() = Vector(0.0, 0.0)
// both are `zero()` statics in the same FileKt
```

The fix is `@JvmName` (Example 4.1.2):

```kotlin
@JvmName("zeroMoney")
companion fun Money.zero() = Money(0)

@JvmName("zeroVector")
companion fun Vector.zero() = Vector(0.0, 0.0)
```

Java sees `zeroMoney()` and `zeroVector()`; Kotlin still writes
`Money.zero()` and `Vector.zero()`.

### JVM: renamed companion object fields

Today a companion object's state lives in static fields of the
outer class, named after the property. Those names would clash
with block backing fields, so §4.1.4 changes the companion object
scheme: private fields introduced by a companion object are
mangled as `CompanionObjectName$fieldName`.

```kotlin
class Vector(val x: Double, val y: Double) {
    companion object {
        const val Dimensions: Int = 2
        val Special: MutableMap<Vector, String> =
            mutableMapOf()
    }
}
```

```java
public class Vector {
    public static final Companion Companion;
    public static final int Dimensions = 2;
    private static Map<Vector, String> Companion$Special;

    static {
        Companion$Special = new LinkedHashMap();
        Companion = new Companion();
    }

    public static final class Companion {
        public final Map<Vector, String> getSpecial() {
            return Vector.Companion$Special;
        }
    }
}
```

Only private fields get mangled. `@JvmField`, `lateinit` and
`const` produce non-private fields, so the same name in a
companion object and a companion block is a platform clash:

```kotlin
class Config {
    companion object {
        const val Version = 1
    }
    companion {
        const val Version = 2  // ERROR: platform clash
    }
}
```

### JVM: interfaces

```kotlin
interface Thing {
    companion {
        var currentId: Int = 0
    }
}
```

```java
public interface Thing {
    static class Thing$CompanionBlock {
        private static int _currentId;
        static { _currentId = 0; }
    }

    static int getCurrentId() {
        return Thing$CompanionBlock._currentId;
    }

    static void setCurrentId(int id) {
        Thing$CompanionBlock._currentId = id;
    }
}
```

Accessors stay on the interface; only the backing field moves.
The nested class "should not leak", so it is not part of the
binary API. Reflection can still observe the oddity that the
backing field of an interface property lives in a nested class.

### How this relates to `@JvmStatic` and `@JvmField` today

KEEP-0150 (Stable in 1.3) made `@JvmStatic` legal on interface
companion object members. The static method in the interface
delegates to the companion member. It cannot be used on `const`
or `@JvmField` properties and requires `-jvm-target 1.8`.

```kotlin
interface Codec {
    companion object {
        @JvmStatic fun utf8(): Codec = Utf8Codec
    }
}
```

```java
Codec c = Codec.utf8();  // static on the interface,
// calls Codec.Companion.utf8() under the hood
```

KEEP-0152 (Stable in 1.3) made `@JvmField` legal on interface
companion properties: a static field on the interface,
initialized in the interface's `<clinit>`. Restrictions: no
`const`, `lateinit` or delegated properties, no custom accessors,
no overriding, and all companion properties must be `public final
val` with `@JvmField`. Adding or removing it is binary
incompatible because it changes the field's owner.

```kotlin
interface Defaults {
    companion object {
        @JvmField val Charset: String = "UTF-8"
    }
}
```

Companion blocks make the `@JvmStatic` dance unnecessary: the
static *is* the member. KEEP-0449 does not say whether
`@JvmStatic` is permitted on block members. KEEP-0427 forbade
platform static annotations on its `static` members; my reading
is that on a block member it would be redundant at best. Do not
claim either way on stage.

`@JvmField` is explicitly mentioned for companion extension
properties (§1.3.5) and in the interface appendix.

### Binary and source compatibility

- Block member to companion extension, or back: **not** binary
  compatible on the JVM. One is a static on the class, the other
  a static on `FileKt` (warning after the Swift section).
- Companion object to companion block: Java and old Kotlin
  callers link against `Companion.INSTANCE.foo()`, so this is a
  binary break unless you keep the delegating object (see
  migration).
- The BCV plugin should list block members as `static` on the JVM
  and drop the receiver of companion extensions. On other
  platforms it should mark block members explicitly and record the
  extension's receiver.
- The KEEP notes that on the JVM "turning a callable into a
  companion extension is binary (yet not source) compatible".
  My reading: a top-level `fun unitX()` in `Vector.kt` and
  `companion fun Vector.unitX()` in the same file both compile to
  `VectorKt.unitX()`, but Kotlin callers must now write
  `Vector.unitX()`.

### JS

Block members compile to JS `static` class members; companion
initialization to a `static {}` initialization block; constants
become plain static properties without a backing field. Companion
extensions compile like any top-level declaration, named verbatim
unless `@JsName` overrides it.

```js
class Vector {
    static #Zero;
    static get Zero() { return Vector.#Zero; }
    static Dimensions = 2;
    static { this.#Zero = new Vector(0.0, 0.0); }
}

function unit(dim) { ... }
```

JS statics are visible through the prototype chain, but accessed
through the class name the right overload is chosen.

### Swift (export)

Swift has `static` (not overridable) and `class` (overridable)
type members. `static` is the closer match, but Swift forbids
redeclaring a `static` member in a subclass, while Kotlin allows
hiding. The KEEP uses the compiler's private `@_nonoverride`
attribute:

```swift
class Vector {
    @_nonoverride static var Zero: Vector { get }
    @_nonoverride static var Dimensions: Int { get }
}

extension Vector {
    @_nonoverride static func unit(dim: Int) -> Vector
}
```

Companion extensions become a Swift `extension`. Name mangling,
extra arguments and `class` members were considered and rejected
because the resulting API is awkward to consume from Swift. The
KEEP only specifies the exported shape, not Swift-side
initialization or backing fields.

### Native and initialization changes

Companion initialization follows JVM semantics everywhere,
including initializing superclasses and superinterfaces.
Kotlin/Native does not do that today. Of three rollout options,
the KEEP picks: use the new initialization **only when the
feature flag is enabled** while experimental, and everywhere once
stable. Turning it on for every 2.5 build was too risky (behavior
changes on a version bump with no code change); per-class opt-in
was too fine-grained and breaks when a parent starts using blocks.

### Reflection

- Block members show up in `KClass.members` like other members.
  Blocks themselves are not reflected; any number of blocks look
  the same.
- In `kotlin-reflect` they count as static: `staticXXX` returns
  them, `memberXXX` does not. No new `declaredXXX` API, since
  nothing is inherited.
- A block member is recognizable by having no `INSTANCE` parameter
  and not being a constructor.
- `KCallable` gains `companionExtensionClass: KClass<*>?`, `null`
  for anything that is not a companion extension.
- `call`/`callBy` take no receiver argument for either kind.

```kotlin
val p: KProperty0<Vector> = Vector::Zero
val zero = p.get()  // no receiver argument
```

The KEEP's own snippet for §5.5 reads the receiver via
`p.companionParameter?.type`, which does not match the
`companionExtensionClass` property it adds in §5.3. Expect the
final API name to settle during implementation.

## Design decisions

### Why KEEP-0427 (`static` and `T::static`) lost

KEEP-0427 surfaced a new concept, the *static scope*, through two
syntaxes:

```kotlin
data class Vector(val x: Double, val y: Double) {
    static val Zero: Vector = Vector(0.0, 0.0)
    static fun Int.asVector(): Vector = Vector(1.0, 0.0)
}

val Vector::static.UnitX: Vector
    get() = Vector(1.0, 0.0)
```

The discussion of 0427 (and of KEEP-347 before it) produced the
key feedback that KEEP-0449 opens with: there is no single
problem, but a pile of them that different users rank
differently. KEEP-0449 restarts from three principles, each a
direct answer to 0427:

- **No multiplication of concepts.** 0427 added "static scope"
  next to companion objects and needed new vocabulary (static
  member, static extension, type extension, plus a `member`
  prefix to disambiguate). 0449 generalizes the existing word
  *companion*.
- **Simple and to the point.** 0427 had static `init` blocks,
  static extension members inside classes, member type extensions
  that take part in inheritance, star-imports of classes, and a
  `KStaticDeclarationContainer`. 0449 keeps only what the five
  problems need: no `init`, top-level-only extensions, no
  inheritance.
- **Expose only as much as needed.** Do not put into the language
  what better compiler analysis could solve.

Concrete semantic differences worth knowing:

| Question | KEEP-0427 | KEEP-0449 |
|---|---|---|
| Static vs companion lookup | Interleaved per scope | Blocks/exts first, then object |
| Companion object in extension body | In scope | Not in scope |
| Static init code | `static init {}` | Initializers only |

The lookup change is the subtle one. 0427 resolved `T.f()` by
trying, *for each scope level*, the static receiver and then the
companion receiver. 0449 considered that ("make all companion
declarations work as a single receiver") and rejected it, because
then a companion object member would beat a top-level companion
extension. 0449 instead exhausts blocks and extensions first. Its
reasons:

- It is easy to explain: try companion blocks and extensions,
  then try `T.Companion.f()`.
- It reuses existing receiver machinery to answer what is in scope
  inside block members, companion extensions and companion object
  members.
- Companion object members can always be named explicitly with
  `T.Companion`; blocks and extensions cannot be named, so they
  get the priority.

### Syntax: `companion` modifier vs `Vector::companion`

An earlier iteration wrote extensions as
`val Vector::companion.UnitX`. JetBrains ran user research on
both forms; the modifier version was easier to understand and
caused fewer moments of confusion, especially among experienced
Kotlin developers.

```kotlin
val Vector::companion.UnitX get() = Vector(1.0, 0.0) // old
companion val Vector.UnitX get() = Vector(1.0, 0.0)  // new
```

KEEP-0427 had already rejected `Int::class.zero()` because
`Int::class` would mean a receiver in a signature and a
`KClass<Int>` in a body.

### Alternatives for "no instance" that lost

The hard part was signalling that the companion instance is not
available, so it can be compiled away.

- **A compiler flag** (`-companion-compilation=static`) that
  forbids companion instances and compiles companion objects to
  statics. Too implicit (it lives in the build file), too global
  (not per class), and it overloads `companion object` with two
  meanings.

```kotlin
// same source, two binary shapes depending on a flag
class Vector {
    companion object { val Zero = Vector() }
}
```

- **An annotation on the companion object.** Fixes the global
  problem, but still bends `companion object`, and adding or
  removing the annotation would change the binary shape.
- **Namespaces.** Influential (a block *is* a namespace-like
  thing), but a general namespace feature does not get closer to
  solving the five problems.
- **Extension companion objects** (from KEEP-0427): add extra
  companion objects to an existing class.

```kotlin
companion object Vector.Directions {
    val UnitX: Vector = Vector(1.0, 0.0)
}
```

  It keeps objects as the carrier, so it does nothing for
  allocation or real statics.

- **Mangled JVM names** (KEEP-347): compile a type extension as
  `Example$foo`. Fewer clashes, but `$` names look internal to
  Java, and mixed Java/Kotlin inheritance stays ambiguous. 0427
  dropped mangling; 0449 keeps the source name and uses
  `@JvmName` for clashes.
- **Static objects** (KEEP-347): dropped in 0427 because it was
  unclear whether a static object is a real type.

### Uniform initialization, JVM-shaped

Kotlin could have matched each platform's native initialization
rules. The KEEP picks uniform semantics instead and aligns them
with the JVM, the primary target and the one JetBrains controls
least. The cost lands on Native, which must start initializing
supertypes.

### Comparisons the KEEPs make

- **Java**: blocks are Java statics plus a static initializer, by
  design; that is the stated mental model for Java developers.
  Like Java, statics are hidden, not overridden.
- **Swift**: `static` (not `class`) type members, with
  `@_nonoverride` to allow hiding. Companion extensions map to
  Swift extensions, which is the closest analogue to adding type
  members to a type you do not own.
- **JS**: `static` members and static initialization blocks.
- **C#**: KEEP-0427 cites C# `static` (and Java's) as the meaning
  of "static" it targets; the `StringUtils` pattern in Java and C#
  is its example of stateless utility functions.

## Open questions and what may change

- **Flag and version.** "Experimental in 2.5.0 (expected)". No
  flag name in the KEEP.
- **Auto-import of companion extensions** declared next to the
  type: the KEEP wants to "explore ways", no rule yet.
- **Multiplatform `@Static`** (problem #3) is out of scope.
- **`@JvmStatic` on block members**: not addressed.
- **Context-sensitive resolution for companion extensions**: not
  addressed; only block members are said to participate.
- **Superclass scope linking**: kept for now, despite the
  confusing qualified/unqualified asymmetry. A deprecation would
  be a separate proposal.
- **Swift**: initialization, backing fields and constants are not
  specified, only the exported shape.
- **Interfaces**: the all-or-nothing `@JvmField` rule and
  per-block nested classes are a conservative first cut; "we could
  loosen some of those restrictions".
- **Out-of-order initialization** stays undefined behavior.
- **Reflection naming** (`companionExtensionClass` vs
  `companionParameter`) is inconsistent in the text.
- **Stdlib adoption**: `List.of` and friends (KEEP-0416) wait for
  companion blocks to stabilize.

```kotlin
// Not decided yet: does this need an import of
// the file that declares UnitX?
import geo.Vector

val u = Vector.UnitX
```

## Cheat sheet

```kotlin
class Vector(val x: Double, val y: Double) {
    companion {                      // static members
        val Zero = Vector(0.0, 0.0)  // private static field
        const val Dims = 2
        operator fun invoke(s: String) =
            s.split(",").let {
                Vector(it[0].toDouble(), it[1].toDouble())
            }
    }
}

companion val Vector.UnitX = Vector(1.0, 0.0)  // FileKt
companion fun UUID.nil() = UUID(0L, 0L)        // Java type

Vector.Zero; Vector("1,2"); UUID.nil()
Vector::Zero          // KProperty0<Vector>
```

- `companion { }`: functions and properties only; no `init`,
  constructors, extensions, or operators except `invoke`/`of`.
- No `open`/`abstract`/`final`/`override`; bodies required unless
  `expect`/`external`. Not allowed in `object`.
- No instance: not `v.Zero`, not `val c = Vector`.
- `companion fun T.f()`: top-level only; `T` a class/interface or
  alias, no type args, no type parameters, no annotations; only
  `invoke` as operator (no `of`). Properties may have
  initializers and `@JvmField`.
- `T.f()` order: block members, implicit statics, companion
  extensions, then `T.Companion`. Use `T.Companion.f()` to reach
  the object.
- Inside a block: no `this`, no companion object unqualified.
  Inside a companion extension: only `T`'s static scope.
- Parent block members: unqualified via scope linking, never as
  `Child.f()`. Hiding, not overriding.
- Init triggers: constructor, companion object, enum entry,
  non-const member, implicit static. Constants first, then
  program order. Companion extensions do not trigger it.
- JVM: block members are statics on the class, `<clinit>`;
  companion extensions are `FileKt` statics without a receiver
  parameter; `@JvmName` for clashes; companion object fields get
  `Companion$name`.
- Block member to extension or back: binary incompatible on JVM.

## Talking points

- "A companion block is a companion object minus the object: same
  call syntax, no instance, no extra class."
- "You can finally write `UUID.nil()` or `List.ofNotNull(...)`
  for types you don't own. No companion required."
- "On the JVM a companion block member *is* a Java static. No
  `@JvmStatic`, no `INSTANCE`, no bridge."
- "Blocks and companion extensions always beat the companion
  object. Need the object? Say `Companion` explicitly."
- "This replaced a `static` keyword proposal. The team chose to
  generalize `companion` instead of adding a second concept."
- "No `init` in companion blocks, on purpose. Class
  initialization bugs are bad enough already."
- "If your companion object is a value, implements an interface
  or defines `plus`, keep it. Blocks are for statics."
- "Status: designed, experimental expected in 2.5. Not
  something to ship on today."

### Tricky questions

**"Why not just add `static` like Java?"** That was KEEP-0427. It
introduced a static scope concept, `static` and `T::static`, static
init blocks and inheritable type extensions. Feedback showed the
problems were many and weighted differently, so KEEP-0449
generalized the existing `companion` concept, kept only what the
problems need, and tested the syntax in user research.

**"If both exist, which `foo` does `Vector.foo()` call?"** The
companion block member, then a companion extension, and only then
the companion object member, even if the companion extension is
top-level and the object member is "closer". Write
`Vector.Companion.foo()` for the object.

**"Can I replace my companion object with a block in a published
library?"** Not as a drop-in on the JVM: callers are linked
against `Companion.INSTANCE`. Add the block, make the object
delegate to it, deprecate the object (hidden, if only binary
compatibility matters), remove it later. If you only want Java
statics, `@JvmStatic` on the companion object is still the
simplest answer.
