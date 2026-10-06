---
title: "Modern Kotlin Properties"
subtitle: "Explicit backing fields split a property's type; lateinit val splits its timeline"
author: "Notes from KEEP-0430, KEEP-0455, KEEP-0452, KEEP-0073, KEEP-0086"
date: "October 2026"
lang: en
---

## At a glance

Two proposals change what a single property declaration can say.
Explicit backing fields let one property have a narrow public type
and a wider private type. `lateinit val` lets a property be assigned
later, but only once. They solve different problems, have very
different statuses, and meet in the same kind of class: a view
model, a service, a test fixture.

| KEEP | Status | Where |
|---|---|---|
| [0430 Explicit backing fields](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0430-explicit-backing-fields.md) | Stable in 2.4 | KT-14663 |
| [0455 `lateinit val`](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0455-lateinit-val.md) | Public discussion | discussion #475 |
| [0452 Assign-once](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0452-assign-once.md) | Superseded by 0455 | discussion #471 |
| [0073 `isInitialized`](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0073-lateinit-property-isinitialized-intrinsic.md) | Stable (since 1.2) | KT-9327 |
| [0086 Local/top-level lateinit](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0086-local-and-top-level-lateinit-vars.md) | Stable in 1.2 | issue #86 |

What that means in practice:

- **Explicit backing fields (EBF)** are stable in Kotlin 2.4. The
  KEEP names no compiler flag. I compiled every EBF example in this
  article with `kotlinc` 2.4.20 and no extra options.
- **`lateinit val`** is a design in public discussion. KEEP-0455 talks
  about feedback "from experimental release", so an experimental
  release is planned, but no version and no flag are given. Kotlin
  2.4.20 rejects it with *"'lateinit' modifier is allowed only on
  mutable properties"*. Every `lateinit val` example below is
  proposal syntax, not something you can compile today.
- KEEP-0452 (assign-once via an `assignOnce()` delegate) is
  superseded. It matters only as the rationale for 0455.
- KEEP-0073 and KEEP-0086 are old, shipped background: how
  `lateinit var` works today.

The teaser:

```kotlin
class CartViewModel {
    val state: StateFlow<Cart>
        field = MutableStateFlow(Cart())   // Kotlin 2.4

    lateinit val repo: CartRepository      // proposal
}
```

## The problem

### Two names for one thing

Kotlin's read-only collection and flow interfaces are views. You
want the outside world to see `StateFlow`, and you want your own code
to write into a `MutableStateFlow`. Today that takes two
declarations, a naming convention and a getter.

```kotlin
class CartViewModel {
    private val _state = MutableStateFlow(Cart())
    val state: StateFlow<Cart> get() = _state

    fun add(item: Item) {
        _state.update { it + item }
    }
}
```

The docs call this the
[backing property](https://kotlinlang.org/docs/properties.html#backing-properties)
pattern. KEEP-0430 lists where it shows up: `List` and `MutableList`,
`LiveData` and `MutableLiveData`, `SharedFlow`/`MutableSharedFlow`,
`StateFlow`/`MutableStateFlow`, Rx `Observable` and `Subject`.

The cost is not huge, but it adds up:

- Two names, `_state` and `state`, for one concept. Every reader has
  to learn the underscore convention.
- Inside the class you have to remember which one to use. Writing
  `state` where you meant `_state` gives a compile error. Writing
  `_state` where you meant `state` is silent.
- The getter is boilerplate that exists only to change the static
  type.

### Late, but only once

The second pain is `lateinit var`. KEEP-0455's open-source survey
says the two most common uses, together up to 80% of all
`lateinit var` declarations, are:

- **Assign once**: set during setup, never changed after (Android
  view lookups, test fixtures).
- **Dependency injection**: set by a framework, often through
  `@Inject`.

```kotlin
class CheckoutActivity : AppCompatActivity() {
    lateinit var total: TextView

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        total = findViewById(R.id.total)
        // never reassigned after this
    }
}

class OrderService {
    @Inject lateinit var payments: PaymentGateway
}
```

In both, the property is stable after the first write. But `var`
says the opposite: anyone can reassign it at any time, and nothing
catches it.

```kotlin
fun refresh(activity: CheckoutActivity) {
    activity.total = TextView(activity) // compiles, a bug
}
```

`lateinit var` also has type restrictions that follow from its
compilation scheme (KEEP-0086 lists them): no nullable types, no
primitive types, no initializer, no delegate.

```kotlin
class Session {
    lateinit var retries: Int     // ERROR: primitive type
    lateinit var coupon: String?  // ERROR: nullable type
}
```

So "set later, exactly once" has no direct spelling. You pick
`lateinit var` and lose the "once", or a nullable `var` and lose
non-nullability, or `by lazy` and lose the ability to assign from
outside.

## The feature, step by step

### Part 1: explicit backing fields

#### Step 1: declare the field

The syntax is the `field` keyword after the property type, then an
initializer. The property type is what everyone sees. The field type
is what the class stores.

```kotlin
class CartViewModel {
    val state: StateFlow<Cart>
        field = MutableStateFlow(Cart())
}
```

There is no `_state`, no getter, and the property is still a plain
`val state: StateFlow<Cart>` to callers.

The field type is inferred from the initializer. In the snippet
above it is `MutableStateFlow<Cart>`: the expected type
`StateFlow<Cart>` drives inference, so `MutableStateFlow(Cart())`
and `MutableLiveData()` work without repeating type arguments.

```kotlin
class CityViewModel : ViewModel() {
    val city: LiveData<String>
        field = MutableLiveData() // MutableLiveData<String>
}
```

#### Step 2: use the wider type inside

Within the declaring scope the compiler smart casts the property to
the field type. You write `state`, and you get `MutableStateFlow`.

```kotlin
class CartViewModel {
    val state: StateFlow<Cart>
        field = MutableStateFlow(Cart())

    fun add(item: Item) {
        state.update { it + item }  // MutableStateFlow API
    }

    fun clear() {
        state.value = Cart()        // settable value
    }
}
```

Outside, the property is only what its declared type says.

```kotlin
fun render(vm: CartViewModel) {
    println(vm.state.value)          // OK, StateFlow API
    vm.state.value = Cart()          // ERROR: val cannot be
                                     // reassigned
}
```

The KEEP frames this as a smart cast that is available exactly
where a private property would be accessible if you wrote it in the
same place. That single rule explains every case in the Rules
section below.

#### Step 3: state the field type explicitly

You can write `field: Type = ...` when inference would pick the
wrong type, or when you want the type on the page.

```kotlin
class Inventory {
    val stock: Map<Sku, Int>
        field: HashMap<Sku, Int> = HashMap()

    fun restock(sku: Sku, n: Int) {
        stock.merge(sku, n, Int::plus) // HashMap API
    }
}
```

#### Step 4: initialize later, in `init`

The initializer is optional. If you omit it, you must give the field
type, and the property must be definitely assigned in the
constructor, exactly like any `val` without an initializer.

```kotlin
class Clock(start: Int) {
    val ticks: StateFlow<Int>
        field: MutableStateFlow<Int>

    init {
        ticks = MutableStateFlow(start)
    }

    fun tick() {
        ticks.value++
    }
}
```

This is a compile-time "assign once": definite assignment analysis
checks it. Keep it in mind for Part 2, where `lateinit val` does the
same job at runtime.

#### Step 5: what it compiles to

The KEEP says the backing field gets the type of the EBF, and that
access "happens through getter", which the implementation "may
optimize" by reading the field directly. On the JVM with 2.4.20,
`javap -p` on `CartViewModel` shows:

```text
public final class CartViewModel {
  private final MutableStateFlow<Cart> state;
  public final StateFlow<Cart> getState();
  public final void add(Item);
}
```

One private field with the precise type, one public getter with the
public type. Inside `add`, the compiled code reads the field
directly with `getfield` (observed in 2.4.20; the KEEP only allows
this optimization, it does not require it).

### Part 2: `lateinit val` (proposal)

Everything in this part is KEEP-0455 design text. It does not
compile in 2.4.20.

#### Step 1: declare it, assign it once

```kotlin
class OrderService {
    lateinit val payments: PaymentGateway

    fun start(config: Config) {
        payments = PaymentGateway(config)
    }

    fun charge(order: Order) {
        payments.charge(order.total)
    }
}
```

`lateinit val` is "applicable in the same declaration sites as
`lateinit var`". Unlike a plain `val`, the assignment is not limited
to `init` blocks: "it can be late initialized in any scope".

#### Step 2: the runtime contract

The property starts in a special uninitialized state. The KEEP
defines two operations:

- **Write**: if uninitialized, store the value. Otherwise throw,
  "indicating a reassignment attempt".
- **Read**: if initialized, return the value. Otherwise throw,
  "indicating an attempt to read an uninitialized property".

```kotlin
val service = OrderService()
service.charge(order)       // throws: uninitialized
service.start(config)       // OK, first write
service.start(config)       // throws: already set
```

The exception type in the KEEP's JVM sketch is
`IllegalStateException` with the messages "Property is
uninitialized" and "Property already set". The KEEP presents that
code as "could be compiled to", so treat the exact type and message
as illustrative, not specified.

The KEEP is explicit that this is a runtime contract: "There is no
requirement for the compiler to ensure at compile time that the
property is initialized before the first read and never
reassigned."

#### Step 3: nullable and primitive types work

`lateinit var` uses `null` as the "not yet" marker, so it can't hold
`null` or a primitive. `lateinit val` uses a private sentinel
object, so "nullable and primitive types are allowed".

```kotlin
class Checkout {
    lateinit val coupon: Coupon?  // null is a real value
    lateinit val attempts: Int    // primitive is fine

    fun begin(c: Coupon?) {
        coupon = c       // assigning null counts as the
                         // one write
        attempts = 0
    }
}
```

After `coupon = null`, a second `coupon = ...` throws. `null` is a
value, not "uninitialized".

#### Step 4: where it sits in the property model

The KEEP's table, condensed: `lateinit` moves the read-write
invariants of a property from compile time to runtime.

| Declaration | Read | Write |
|---|---|---|
| `var` | after first write (compile time) | anytime |
| `lateinit var` | after first write (runtime) | anytime |
| `lateinit val` | after first write (runtime) | once (runtime) |
| `val` | after first write (compile time) | once (compile time) |

```kotlin
class Matrix {
    var  a: Int = 0          // checked, mutable
    lateinit var  b: Name    // unchecked read, mutable
    lateinit val  c: Name    // unchecked read, one write
    val  d: Name = Name("d") // checked, one write
}
```

`lateinit var` stays. The KEEP explicitly does not deprecate it:
the builder pattern needs reassignment, and `lateinit var` "may be
preferred in performance-sensitive contexts".

### Part 3: how the two combine

#### Two orthogonal axes

EBF splits a property in **space**: one type inside the class,
another outside. `lateinit val` splits it in **time**: unset, then
set once, then fixed. Both are about making a single declaration say
precisely what the old two-declaration or convention-based patterns
said loosely.

```kotlin
class CartViewModel {
    // type axis: Mutable inside, read-only outside
    val state: StateFlow<Cart>
        field = MutableStateFlow(Cart())

    // time axis: injected later, exactly once (proposal)
    @set:Inject lateinit val repo: CartRepository

    fun load(userId: UserId) {
        state.value = repo.cartFor(userId)
    }
}
```

#### Compile-time once vs runtime once

An EBF without initializer is assigned once in `init`, checked by
the compiler. `lateinit val` is assigned once anywhere, checked at
runtime. When the value is available in the constructor, prefer the
compile-time version.

```kotlin
// value known at construction: compile-time once
class Feed(source: Source) {
    val items: StateFlow<List<Post>>
        field: MutableStateFlow<List<Post>>
    init { items = MutableStateFlow(source.initial()) }
}

// value arrives later: runtime once (proposal)
class FeedScreen {
    lateinit val feed: Feed
    fun onAttach(f: Feed) { feed = f }
}
```

#### Can one property have both?

Neither KEEP addresses `lateinit val x: A field: B`. The facts:
KEEP-0430 requires an EBF property to be a `val` with a backing
field, and KEEP-0455 says `lateinit val` "exposes no backing field
on the source level" and stores into a field of effectively `Any?`
type. My reading: the two designs don't fit together, and the
combination should be treated as unsupported until a KEEP says
otherwise.

```kotlin
class Screen {
    lateinit val title: StateFlow<String>
        field: MutableStateFlow<String>  // not specified by
                                         // either KEEP
}
```

#### The case neither covers

KEEP-0430 calls out the Android fragment binding: assigned in
`onCreateView`, released to `null` in `onDestroyView`. That is "late
initialization with early destruction". EBF does not support it, and
`lateinit val` cannot be reset by design. The backing property
pattern stays.

```kotlin
class ProfileFragment : Fragment() {
    private var _binding: ProfileBinding? = null
    val binding get() = _binding!!

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
```

## Typical usage

### Coroutines state holders

The flagship use. One property, mutable inside, read-only outside.

```kotlin
class DownloadTracker {
    val progress: StateFlow<Percent>
        field = MutableStateFlow(Percent(0))

    val done: SharedFlow<FileId>
        field = MutableSharedFlow(extraBufferCapacity = 8)

    fun report(id: FileId, p: Percent) {
        progress.value = p
        if (p.isComplete) done.tryEmit(id)
    }
}
```

`MutableSharedFlow(extraBufferCapacity = 8)` infers its type
argument from `SharedFlow<FileId>`. That compiled in 2.4.20.

### Collections in domain models

```kotlin
class Order(val id: OrderId) {
    val lines: List<OrderLine>
        field = mutableListOf()

    val total: Money
        get() = lines.fold(Money.ZERO) { acc, l ->
            acc + l.price
        }

    fun add(line: OrderLine) {
        require(line.qty > 0) { "qty must be positive" }
        lines += line   // MutableList.plusAssign
    }
}
```

`total` is a normal computed property next to an EBF one. Only
properties with an EBF lose custom getters.

### Top-level registries

Top-level EBF properties work. The smart cast is available in the
same file, because that is where a `private` top-level property is
visible.

```kotlin
// Routes.kt
val routes: Map<String, Handler>
    field = mutableMapOf()

fun route(path: String, handler: Handler) {
    routes[path] = handler       // MutableMap in this file
}
```

In another file, `routes[path] = handler` is an error: `Map` has no
`set`.

### Ktor-style plugin state

```kotlin
class RateLimiter(private val limit: Int) {
    val hits: Map<ClientIp, Int>
        field = HashMap()

    fun allow(ip: ClientIp): Boolean {
        val n = (hits[ip] ?: 0) + 1
        hits[ip] = n
        return n <= limit
    }
}
```

### `lateinit val` for injection and tests (proposal)

DI uses the setter, so annotations need `@set:`.

```kotlin
class InvoiceController {
    @set:Inject lateinit val invoices: InvoiceRepository
    @set:Inject lateinit val mailer: Mailer

    fun send(id: InvoiceId) {
        mailer.send(invoices.find(id))
    }
}
```

Test fixtures set once in `@BeforeTest`:

```kotlin
class PricingTest {
    lateinit val catalog: Catalog

    @BeforeTest fun setUp() {
        catalog = Catalog.load("prices.json")
    }

    @Test fun discount() {
        assertEquals(Money(90), catalog.price(Sku("A")))
    }
}
```

A `@BeforeTest` that runs on the same instance twice would throw,
which is the point: a fixture silently overwritten is the kind of bug
assign-once wants to surface. (JUnit's default is a fresh instance
per test, so this is fine in practice; my reading.)

## Rules and edge cases

### Explicit backing fields: what must hold

KEEP-0430's design restrictions, each with the 2.4.20 diagnostic.

#### Only `val`

```kotlin
class Account {
    var balance: Number          // ERROR: only 'val'
        field = 0L               // properties with EBF
}
```

The KEEP lists "can't be `var`" as a design restriction. A setter
on a property whose field has a different type would need a rule
for converting the property type into the field type; the KEEP does
not try.

#### No custom getter, and no accessors at all

```kotlin
class Account {
    val owner: CharSequence
        field = StringBuilder()
        get() = field   // ERROR: properties with EBF
                        // cannot have accessors
}
```

The KEEP rules out a custom getter. The getter is what makes the
"call goes through the getter, smart cast to the field type" story
sound: if you could return something else, the cast would be wrong.

#### Final only

```kotlin
open class Repo {
    open val cache: Map<Key, Row>
        field = HashMap()        // ERROR: must be final
}
```

"Effectively final modality." An override could change the getter,
and then the smart cast inside `Repo` would lie. Same reason as the
getter rule. A member of an `open` class is fine as long as the
property itself is final, which is the default.

Corollary: no `abstract` and no interface properties, since those
have no backing field at all.

```kotlin
interface Store {
    val items: List<Item>
        field = mutableListOf()  // ERROR: backing fields
                                 // inside interfaces
}
```

#### No delegates, no `const`

```kotlin
class Prefs {
    val theme: Theme by lazy { load() }
        field = ...              // ERROR: syntax, a
                                 // delegate has no field
}
```

The grammar change makes `field` an alternative to a delegate, not
an addition. `const val` is also excluded.

#### Field type must be a subtype

```kotlin
class Label {
    val text: CharSequence
        field = 42      // ERROR: field type must be a
                        // subtype of property type
}
```

The public getter returns the field, so the field has to be a valid
value of the property type.

#### Same type is a warning

```kotlin
class Label {
    val text: String
        field = "hello"         // WARNING: unnecessary EBF,
                                // same type as property
}
```

#### Visibility: field is private, property is not

`private` is "the default and the only allowed visibility for
explicit backing fields". You cannot write `internal field`. The
property itself must be more visible than the field, which means
anything except `private`.

```kotlin
class Cart {
    private val items: List<Item>
        field = mutableListOf() // ERROR: private properties
                                // cannot have EBF
}
```

A private property with an EBF would be pointless: the smart cast
would cover every use site, so just declare the field type.

`protected` and `internal` properties are allowed. The field stays
private, and the smart cast still follows private rules (next
section). The KEEP explicitly lists "non-private visibility of the
backing property" (e.g. `internal _state` for tests, `protected
_state` for subclasses) as unsupported.

#### No extension, context-parameter, or local properties

```kotlin
val Order.audit: List<Event>
    field = mutableListOf()      // ERROR: extension
                                 // properties have no field

fun checkout() {
    val log: List<String>
        field = mutableListOf()  // ERROR: local properties
}
```

Extension and context-parameter properties never had a backing
field. For locals the KEEP just says "can't"; the 2.4.20 parser
reports it as an unresolved `field`.

#### No `@JvmField`

```kotlin
class Metrics {
    @JvmField val counts: Map<Name, Int>
        field = HashMap()        // ERROR: @JvmField not
                                 // allowed with EBF
}
```

`@JvmField` would expose the field publicly, with the field type.
That defeats the point.

### Explicit backing fields: where the smart cast applies

Rule: wherever a `private` member at that spot would be visible.

```kotlin
class Ledger {
    val entries: List<Entry>
        field = mutableListOf()

    fun add(e: Entry) {
        entries.add(e)           // OK, own member
    }

    fun merge(other: Ledger) {
        entries.addAll(other.entries)
        other.entries.clear()    // OK, other instance:
                                 // private is per class
    }

    inner class Writer {
        fun w(e: Entry) {
            entries.add(e)       // OK, nested scope
        }
    }

    companion object {
        fun seed(l: Ledger) {
            l.entries.add(Entry.Genesis) // OK
        }
    }
}
```

Each of those compiled with 2.4.20. Lambdas inside members work too.
Where a private member is not visible, there is no smart cast:

```kotlin
class AuditLedger : Ledger() {     // assume Ledger open
    fun f() {
        entries.add(Entry.Audit)   // ERROR: List has no add
    }
}

fun Ledger.addAll(es: List<Entry>) {
    entries.addAll(es)             // ERROR: extension is
}                                  // outside the class
```

Subclasses and extension functions (even in the same file) are
outside a class's private scope, so they see `List`.

### Explicit backing fields and inline functions

"Automatic smart cast on properties with EBF is disabled inside
Public-API inline functions (with `public` and `protected`
visibility)." The body of a public inline function is copied into
client code, where the field is not accessible.

```kotlin
class Ledger {
    val entries: List<Entry>
        field = mutableListOf()

    inline fun record(e: () -> Entry) {
        entries.add(e())          // ERROR: no smart cast
    }

    internal inline fun recordInternal(e: Entry) {
        entries.add(e)            // OK
    }

    private inline fun recordPrivate(e: Entry) {
        entries.add(e)            // OK
    }
}
```

In 2.4.20, `@PublishedApi internal inline` also gets no smart cast
(observed; the KEEP only names `public` and `protected`, and
`@PublishedApi` is public ABI, so it follows the same logic).

### Explicit backing fields: deferred initialization

Without an initializer, normal `val` definite assignment applies,
with the field type as the declared type.

```kotlin
class Session {
    val tokens: List<Token> field: MutableList<Token>
    // ERROR: field must be initialized
}

class Session2 {
    val tokens: List<Token> field: MutableList<Token>
    fun reset() {
        tokens = mutableListOf() // ERROR: val cannot be
    }                            // reassigned
}

class Session3(t: MutableList<Token>) {
    val tokens: List<Token> field: MutableList<Token>
    init {
        println(tokens)        // ERROR: must be initialized
        tokens = t
    }
}
```

One sharp edge I hit in 2.4.20 (not in the KEEP, looks like a
compiler bug): assigning a value of the *property* type in `init`
compiles, then fails at runtime.

```kotlin
open class Shape
class Circle : Shape()

class Canvas {
    val shape: Shape field: Circle
    init {
        shape = Shape()   // compiles in 2.4.20
    }
}
// Canvas() throws ClassCastException:
// Shape cannot be cast to Circle
```

The generated code is a `checkcast Circle` before `putfield`. Per
the KEEP's "field type must be a subtype" rule this assignment
should be rejected. Do not demo this as intended behavior.

### Explicit backing fields: smart cast from any type

The field type only needs to be a subtype, so the "wider inside"
type can be anything more specific:

```kotlin
class Greeting {
    val text: Any
        field = "Hello, Devoxx"

    fun length(): Int = text.length  // smart cast to String
}
```

Legal, and occasionally useful for hiding a concrete type from the
API. Mostly a good trivia question.

### Explicit backing fields: the read-only view is not a wall

An EBF exposes the *same object* with a narrower static type. A
caller can downcast it. This ran in 2.4.20:

```kotlin
fun hack(vm: CartViewModel) {
    val s = vm.state
    if (s is MutableStateFlow) {
        s.value = Cart()         // mutates the view model
    }
}
```

The old backing property pattern had the same property. The KEEP
lists "returning read-only view", e.g. `_state.asStateFlow()`, as an
unsupported use case: if you need a real wrapper, keep the two
declarations.

```kotlin
class SafeCartViewModel {
    private val _state = MutableStateFlow(Cart())
    val state: StateFlow<Cart> = _state.asStateFlow()
}
```

### Explicit backing fields: unsupported shapes

KEEP-0430 lists these as out of scope; keep using backing
properties.

```kotlin
// transform on read
private val _count = atomic(0)
val count: Int get() = _count.value

// read-only wrapper object
private val _city = MutableStateFlow("")
val city: StateFlow<String> = _city.asStateFlow()

// field visible to tests
internal val _state = MutableStateFlow(Ui())
val state: StateFlow<Ui> get() = _state
```

Also `ThreadLocal`, `WeakReference` and other containers where the
public value is *derived* from the stored one. The KEEP notes that
delegates already hide storage; the backing property is needed only
because you want access to the hidden type.

### Explicit backing fields: `expect`/`actual`

```kotlin
// common
expect class Counter {
    val hits: List<Hit>
        field = mutableListOf()  // ERROR: expect property
                                 // can't have EBF
}

// jvm
actual class Counter {
    actual val hits: List<Hit>
        field = mutableListOf() // OK, implementation detail
}
```

During matching only the property types are compared. The EBF plays
no role.

### `lateinit val`: declarations it rejects (proposal)

Like `lateinit var`, it "permits no custom setter or getter".

```kotlin
class Profile {
    lateinit val name: String
        get() = field.trim()     // not allowed: no custom
                                 // getter or setter
    lateinit val age: Int = 0    // not allowed: lateinit
                                 // has no initializer
}
```

The second line is my reading: the KEEP says an assign-once property
"is declared without an initializer", and `lateinit` never allowed
one.

The field is hidden: "`@field:` annotation target is invalid for
`lateinit val`".

```kotlin
class Model {
    @field:Transient
    lateinit val cache: Cache    // invalid target
}
```

Abstract and `expect` are not supported either:

```kotlin
abstract class Plugin {
    abstract lateinit val id: PluginId  // not supported
}
expect class Env {
    lateinit val home: Path              // not supported
}
```

The KEEP notes `expect`/`actual` matching requires the `lateinit`
modifier to match exactly, so an `expect val` cannot be actualized
with `lateinit val` either.

### `lateinit val`: inheritance

For override matching, `lateinit val` is a `val`, with one
exception: an `open lateinit val` has a generated setter, so it
can't be overridden by a plain `val`.

| Overridden | By `val` | By `lateinit val` |
|---|---|---|
| open `val` | yes | yes |
| open `lateinit val` | no | yes |
| open `var` | no | no |

`var` and `lateinit var` can override all four kinds (`val`,
`lateinit val`, `var`, `lateinit var`).

```kotlin
open class Base {
    open val region: Region = Region.EU
    open lateinit val client: HttpClient
}

class Child : Base() {
    override lateinit val region: Region  // OK
    override val client: HttpClient =     // not allowed:
        HttpClient()                     // val lacks setter
}
```

The KEEP says `open lateinit val` is "technically allowed" but
discouraged: late initialization is an implementation detail
subclasses should not depend on.

### `lateinit val`: no smart casts (yet)

Once set, a `lateinit val` never changes. That sounds like a
perfect smart-cast candidate, and KEEP-0452 wanted it. KEEP-0455
postpones it.

```kotlin
class Viewer {
    lateinit val shape: Shape

    fun area(): Double =
        if (shape is Circle) {
            shape.radius   // ERROR (proposal): no smart
        } else 0.0         // cast on lateinit val
}
```

The reasoning: `lateinit val` is not thread-safe, so under a data
race two threads could observe different values. Stability is "not
guaranteed and thus smartcasts on it are theoretically unsound."
Supporting them "would unprecedentedly weaken Kotlin smartcasts
safety contract." If a thread-safe variant appears, "there would be
no obstacles". Workaround, as for any unstable property:

```kotlin
fun area(): Double {
    val s = shape
    return if (s is Circle) s.radius else 0.0
}
```

### `lateinit val`: augmented assignment

`a += b` resolves to `a.plusAssign(b)` or `a = a.plus(b)`. For a
`lateinit val`, the second form reads and then writes, so it throws
on the read (if unset) or on the write (if set). KEEP-0455 removes
it from resolution, like for a plain `val`.

```kotlin
class Basket {
    lateinit val tags: MutableList<String>
    lateinit val count: Int

    fun f() {
        tags += "sale"     // OK: tags.plusAssign("sale")
        count += 1         // ERROR (my reading): Int has
    }                      // no plusAssign, and the
}                          // a = a + b form is excluded
```

The KEEP also allows (does not require) a compiler or IDE warning
for execution paths where a write unconditionally follows a read.

### `lateinit val`: `isInitialized` is omitted

`lateinit var` has `this::prop.isInitialized`. KEEP-0455 drops it
for `lateinit val` in the initial implementation:

```kotlin
class Uploader {
    lateinit val target: Bucket

    fun close() {
        if (this::target.isInitialized) {  // not provided
            target.flush()
        }
    }
}
```

Why: "building logic around initialization status is discouraged"
for assign-once properties, and only about 5% of `lateinit var`
declarations use `isInitialized` per the survey. If you need the
check, use a nullable `var` or `lateinit var`. If it is added later,
it would be an intrinsic like the existing one.

### Background: how `isInitialized` works on `lateinit var`

KEEP-0073 is worth knowing, because the restrictions are the same
kind of reasoning you will need for `lateinit val`. It is an inline,
intrinsic extension on `KProperty0<*>`, valid only when the receiver
is a property *literal* whose backing field is accessible at the call
site. The compiler emits a direct `GETFIELD` and null check.

```kotlin
class UploadTest {
    lateinit var file: File

    @AfterTest fun tearDown() {
        if (this::file.isInitialized) file.delete()
    }

    fun check(other: UploadTest) {
        other::file.isInitialized   // OK, same class
        val p = this::file
        p.isInitialized             // ERROR: not a literal
    }
}

class Other {
    fun f(t: UploadTest) {
        t::file.isInitialized       // ERROR: field not
    }                               // accessible here
}
```

Calls from other classes are forbidden so that removing `lateinit`
stays a source- and binary-compatible change; same logic for inline
functions, where it is disallowed. Nested and inner classes, lambdas
and local classes inside members are fine (private ones go through a
synthetic accessor). Known wart: "Extract variable" or `.let` breaks
the call, because the receiver stops being a literal.

### Background: local and top-level `lateinit var`

KEEP-0086 (stable in 1.2) allowed `lateinit` on top-level properties
and locals, with all member restrictions. Locals are handy for
assigning inside lambdas:

```kotlin
fun loadUser(db: Db): User {
    lateinit var user: User
    db.transaction {
        user = fetchUser()
    }
    return user
}
```

`lateinit val` is "applicable in the same declaration sites as
`lateinit var`", so locals and top-level are in scope for it too
(the KEEP gives no separate local example).

### Thread safety

Neither feature adds synchronization.

- EBF: a plain field. Thread safety is whatever the field type
  provides. `MutableStateFlow` is thread-safe; `mutableListOf()` is
  not. Changing a property to EBF changes nothing here.
- `lateinit val`: "**not** thread-safe, so assign-once semantics are
  not guaranteed in presence of data-races on the property."

```kotlin
val svc = OrderService()
coroutineScope {
    launch(Dispatchers.Default) { svc.start(cfgA) }
    launch(Dispatchers.Default) { svc.start(cfgB) }
}
// proposal semantics: maybe one throws, maybe both
// writes "succeed" and readers see either value
```

A thread-safe version would guarantee that exactly one of any number
of concurrent writes succeeds and all reads after it see the same
value. KEEP-0455 considered a `volatile` field plus
`AtomicReferenceFieldUpdater.compareAndSet` and rejected it:

1. It complicates code generation and costs performance; `volatile`
   blocks many optimizations even on a write-once, read-many field.
2. Write-write races on a `lateinit val` "would manifest during
   testing with high probability in practice even without
   synchronization."
3. Every other Kotlin property is unsynchronized by default; a
   hidden synchronization point "might mask missing synchronization
   elsewhere in code".

The KEEP leaves the door open for an explicit opt-in to
thread safety later, based on feedback.

## Platform interop

### Explicit backing fields on the JVM

One private field with the field type, one public getter with the
property type. Observed with 2.4.20:

```text
public final class CartViewModel {
  private final MutableStateFlow<Cart> state;
  public final StateFlow<Cart> getState();
}
```

What Java sees is the getter only:

```java
CartViewModel vm = new CartViewModel();
StateFlow<Cart> s = vm.getState();   // OK
MutableStateFlow<Cart> m =
    vm.getState();                   // compile error
```

Top-level properties compile to a private static field in the file
class (`private static final Circle top` with
`public static final Shape getTop()` in my test).

Things to note:

- **Binary compatibility of migration.** The old pattern compiled to
  `private final MutableStateFlow _state` plus `getState()`. The new
  one compiles to `private final MutableStateFlow state` plus
  `getState()`. Public ABI is identical; only a private field name
  changed. My reading: migrating is binary compatible for callers,
  but anything that reflects on the private field name (`_state`)
  breaks.
- **Field type changes.** Since the field is private, changing
  `field = ArrayList()` to `field = LinkedList()` is not an ABI
  change for other modules (my reading), as long as no public inline
  function depends on it. The inline rule above guarantees that.
- **No `@JvmField`**, so you cannot expose the field to Java.
- **Smart cast is source-only.** Java code in the same class
  hierarchy has no such cast; Java sees what Java sees.

Collections are a special case on the JVM: `List` and `MutableList`
both map to `java.util.List`, so in bytecode the field and getter
types look the same. The distinction is Kotlin-only metadata.

### Explicit backing fields and reflection

Per KEEP-0430: "Existing Kotlin reflection functionality will behave
in the way as if there were no explicit backing fields. However,
additional functionality will be added to support explicit backing
fields." No API is specified.

```kotlin
val p = CartViewModel::state
println(p.returnType)  // StateFlow<Cart>, per the KEEP's
                       // "as if there were no EBF"
```

Java reflection on the private field shows the field type (my
reading of the bytecode above).

### Explicit backing fields and annotations

The `@field:` use-site target on an EBF property is an open
question: "placing these annotations before the `field` keyword
seems like a straightforward solution", but the KEEP keeps it open.

```kotlin
class Store {
    @field:Transient         // KEEP: annotation target
    val items: List<Item>    // for EBF is an open question
        field = mutableListOf()
}
```

### Explicit backing fields: JS, Native, Wasm, KMP

KEEP-0430 does not discuss backends. The feature is a front-end
type-system rule plus "the backing field gets a type of EBF", so I
expect identical source behavior on all targets (my reading). The
only KMP-specific rules are the `expect`/`actual` ones above: no EBF
on `expect`, ignored during matching.

```kotlin
// commonMain
class Presence {
    val online: StateFlow<Set<UserId>>
        field = MutableStateFlow(emptySet())
}
```

### `lateinit val` on the JVM (proposal)

KEEP-0455 sketches this Java for `lateinit val property: String`:

```java
public final class Example {
    private static final Object UNINITIALIZED =
        new Object();
    private Object _property = UNINITIALIZED;

    @NotNull public String getProperty() {
        if (_property == UNINITIALIZED)
            throw new IllegalStateException(
                "Property is uninitialized");
        return (String) _property;
    }

    public void setProperty(@NotNull String v) {
        if (_property != UNINITIALIZED)
            throw new IllegalStateException(
                "Property already set");
        _property = v;
    }
}
```

Points to take away:

- **Private field of type `Object`.** The sentinel lets `null` and
  primitives be real values. A primitive is stored boxed (my
  reading, implied by `Object`).
- **Java sees a getter and a setter.** The setter enforces
  assign-once, so Java cannot bypass the contract.
- **The sentinel** is a static field, possibly shared by all
  `lateinit val`s of a class; if `protected`, subclasses can reuse
  it. A stdlib sentinel was rejected because it would have to be
  public.

Compare with `lateinit var`, which KEEP-0452 describes: a nullable
field that is public (KEEP-0086: for top-level, "with the same
visibility as a property setter"), with `null` as the marker.

```java
// lateinit var service: Service
public Service service;          // public field
public Service getService() {
    Service s = service;
    if (s == null) throw ...;    // uninitialized
    return s;
}
public void setService(Service v) { service = v; }
```

Java can write `obj.service = null` and make an initialized
`lateinit var` uninitialized again. This is exactly why Kotlin
**removed `lateinit val` before 1.0**: it used the same public-field
scheme, and Java could break the "once" guarantee. The private field
in KEEP-0455 is the fix.

### `lateinit val` and dependency injection

A DI framework cannot inject into an `Object`-typed field: it picks
what to inject by field type. So injection goes through the setter,
which has the right parameter type.

```kotlin
class Application {
    @Inject lateinit var a: Service       // field injection
    @set:Inject lateinit val b: Service  // setter injection
}
```

The KEEP rejects changing annotation defaulting for `lateinit val`
and instead proposes an IDE intention that adds `@set:` for known
annotations like `@Inject`.

### `lateinit val` and reflection

Exposed as `KProperty`, not `KMutableProperty`, "consistent with
their `val` nature". The generated setter is still visible to Java
reflection, which is what DI needs. Writable Kotlin reflection may
be relaxed later "if reflective writes prove necessary".

```kotlin
val p = Application::b
p is KMutableProperty<*>   // false (proposal)
```

### `lateinit val` and serialization

The field is effectively `Any?` and the sentinel isn't serializable,
so field-based serializers can't handle it without special support.
The KEEP's position: assign-once properties usually hold services
and views, so ignoring them in serialization by default "might be
acceptable".

### `lateinit val` and Hibernate

Semantically perfect for generated IDs; technically not usable.
Hibernate must use property access (private `Object` field), and
more importantly it *reads* the ID on `persist` to decide whether
the entity is new. Reading an unset `lateinit val` throws.

```kotlin
@Entity
class Item {
    @get:Id
    @get:GeneratedValue(
        strategy = GenerationType.IDENTITY
    )
    @get:Access(AccessType.PROPERTY)
    lateinit val id: Long    // persist() reads id: throws
}
```

The KEEP proposes an IDE warning for `lateinit val` with Hibernate.
Stick with `var id: Long? = null`.

### `lateinit val` on other backends

KEEP-0455 describes only the JVM scheme ("For example, on the JVM").
JS, Native and Wasm are not discussed; treat them as unspecified.

## Design decisions

### EBF: why `field`, and why so narrow

The bar was the backing property pattern itself, which the KEEP
calls "intuitive and relatively concise". Supporting more cases
(transform on read, read-only wrappers, non-private fields, early
destruction) without exceeding that conciseness "often" produced
something "too implicit and magical". The chosen design has the best
"coverage / simplicity ratio".

```kotlin
// supported: same object, narrower type
val state: StateFlow<Ui>
    field = MutableStateFlow(Ui())

// not supported: different object on read
private val _n = atomic(0)
val n: Int get() = _n.value
```

The name builds on "implicit backing fields", an existing concept.
The KEEP admits the feature is really "giving properties more power
by revealing more specific type in private scope", and the naming is
still open for discussion.

### EBF: smart cast vs a separate name

The design deliberately keeps one name and uses a smart cast, rather
than a second accessible identifier. The KEEP specifies that the
call semantically goes through the getter, translated as
`(getCity() as MutableLiveData<String>).setValue(newValue)`. That
framing is why the property must be final with no custom getter: the
cast is only safe if the getter returns the field.

```kotlin
// what `city.value = x` means inside the class
(getCity() as MutableLiveData<String>).setValue(x)
```

### EBF: a related future idea

KEEP-0430 mentions "typed delegate access": inside the class,
`::prop` would be a `KDelegatedProperty0<Lazy<String>, String>`, so
`::prop.getDelegate().isInitialized()` works without reflection
ceremony. Outside, it is a normal `KProperty0`. Same idea (a more
specific type in private scope) applied to delegates; it needs its
own KEEP because a property reference is not a property.

```kotlin
class Config {
    val env by lazy { loadEnv() }
    fun ready() =
        ::env.getDelegate().isInitialized() // future idea
}
```

### `lateinit val`: what changed from KEEP-0452

KEEP-0452 proposed the same semantics with a different shape. KEEP
0455 lists the decisions made after community discussion.

| Topic | KEEP-0452 | KEEP-0455 |
|---|---|---|
| Surface | `var x by assignOnce()` | `lateinit val x` |
| Storage | delegate object | private backing field |
| Thread safety | safe by default | not thread-safe |
| Smart casts | proposed | postponed |
| `isInitialized` | via delegate access | omitted |

The superseded design, for reference:

```kotlin
// KEEP-0452, superseded
class Example {
    var property: String by assignOnce()
    var fast: String by assignOnce(
        mode = AssignOnceThreadSafetyMode.NONE
    )
}
```

0452 preferred the delegate because thread-safety mode is a builder
parameter, annotations behave like on any delegated property, and no
syntax is needed. Its own analysis showed the costs:

- **Smart casts** would make `AssignOnce` a special delegate the
  compiler trusts. To keep that sound it would need to be `sealed`
  or `@SubclassOptInRequired`, and wrappers around `assignOnce()`
  would confuse stability detection.
- **Allocation**: a delegate object per property.
- **Serialization**: `kotlinx.serialization` treats delegated
  properties as transient.

0452 also floated `assignonce var` as a new soft keyword, and
`lateinit val`, noting `lateinit val` is "conceptually confusing as
`val`s are expected to be immutable". 0455 chose `lateinit val`
anyway; it fits the table above, where `lateinit` means "move the
invariant to runtime".

### Why not a general "stable delegate" annotation

KEEP-0452 rejected a `@Stable` marker on `getValue` to enable smart
casts on arbitrary delegates. Stability is an invariant of the whole
delegate (including `setValue`), the compiler can't verify it, and a
wrong annotation produces non-local runtime failures through
generated accessors. That's another reason smart casts for
`lateinit val` are tied to a guaranteed-safe implementation.

### Why not the `lateinit var` field scheme

A `null`-based field would allow field injection with plain
`@Inject`, but forbid nullable types, and a public field lets Java
break the contract. KEEP-0455 chose the sentinel for both nullable
types and DI (through the setter), and the private field to keep
Java out. Trade-off acknowledged: `lateinit val` "looks similar to
`lateinit var`" but has no exposed field, which "may create
confusion".

```kotlin
@Inject lateinit var a: Service       // field
@set:Inject lateinit val b: Service   // setter
```

### JVM `StableValue`

KEEP-0452 looked at JEP-502 `StableValue` as a JVM compilation
target. It was removed in JDK 26; its successor `LazyConstant`
(JEP-526) does not fit. Amber suggested similar functionality might
come through `VarHandle`.

```java
// not used: StableValue was removed in JDK 26
```

## Open questions and what may change

### Explicit backing fields

- **Name and syntax** are "a subject of discussion", even though the
  feature is stable in 2.4.
- **Annotation target** for the field (`@field:` before `field`) is
  open.
- **Reflection** will get "additional functionality" for EBF; none
  is specified.
- Unsupported use cases (non-private fields, read-only wrappers,
  early destruction) might be revisited, but the KEEP argues against
  them on simplicity grounds.

```kotlin
// might never be supported (KEEP's "unsupported")
internal val state: StateFlow<Ui>
    internal field = MutableStateFlow(Ui())
```

### `lateinit val`

- **Status**: public discussion, then an experimental release.
  Expect changes.
- **Thread safety** "might be changed in the future based on
  feedback"; a user-selectable thread-safety mode is mentioned.
- **Smart casts** come with a thread-safe variant, if ever.
- **`isInitialized`** may be added later as an intrinsic.
- **`KMutableProperty`** exposure may be relaxed for reflective
  writes.
- **Setter visibility** (`private set` on a `lateinit val`, and who
  may assign from outside the class) is not discussed. The JVM
  sketch shows a public setter; I would not teach anything more
  specific yet.
- **EBF + `lateinit val`** on one property is not discussed.

```kotlin
class Checkout {
    lateinit val gateway: Gateway
        private set   // not addressed by KEEP-0455
}
```

## Cheat sheet

```kotlin
class CartViewModel {
    // EBF, Kotlin 2.4
    val state: StateFlow<Cart>
        field = MutableStateFlow(Cart())

    val log: List<Event> field: MutableList<Event>
    init { log = mutableListOf() }

    fun add(i: Item) = state.update { it + i }

    // lateinit val, proposal only
    @set:Inject lateinit val repo: CartRepo
    lateinit val coupon: Coupon?
}
```

Explicit backing fields:

- `val p: Public field = Impl()` or `field: Impl`.
- Smart cast to field type where a private member would be visible:
  class, nested/inner, companion, lambdas, same file for top-level.
- Not in subclasses, extensions, or public/protected inline funs.
- Must be: `val`, final, no accessors, not delegated, not `const`,
  not local/extension/abstract/interface, not `private`, no
  `@JvmField`, not `expect`.
- Field type must be a subtype; same type is a warning.
- JVM: private field of field type + getter of property type.
- Same object, not a wrapper: callers can downcast.

`lateinit val` (KEEP-0455, public discussion):

- Write once anywhere, read after write, both checked at runtime.
- Nullable and primitive types allowed (sentinel, not `null`).
- No smart casts, no `isInitialized`, not thread-safe.
- Annotations: no `@field:`; DI uses `@set:Inject`.
- Reflection: `KProperty`, not `KMutableProperty`.
- `open lateinit val` can't be overridden by `val`.
- No abstract, no `expect`, no custom accessors.
- `a += b` only via `plusAssign`.
- JVM: private `Object` field, checking getter and setter.

## Talking points

- "The underscore convention is over: one property, mutable inside,
  read-only outside, stable in Kotlin 2.4."
- "An explicit backing field is a smart cast you get wherever a
  private member would be visible. That one rule explains every
  edge case."
- "It's the same object with a narrower type, not a defensive copy.
  If you need `asStateFlow()`, keep the old pattern."
- "Public ABI doesn't change when you migrate: still one private
  field, still `getState()`."
- "`lateinit val` is late but once: the 80% case of `lateinit var`
  finally says what it means."
- "Kotlin had `lateinit val` before 1.0 and removed it, because Java
  could reset the public field. The new design uses a private field
  and a checking setter."
- "`lateinit val` isn't thread-safe on purpose: a hidden lock would
  mask the missing one elsewhere."
- "`lateinit val` is still a proposal. EBF you can use today."

**Q: Why can't I use an explicit backing field on an `open` or
overridable property?**
Inside the class the compiler treats reads as
`(getter() as FieldType)`. An override could return a different
object and that cast would fail. Final property, no custom getter:
the getter always returns the field, so the cast is safe.

```kotlin
open val s: StateFlow<Int>
    field = MutableStateFlow(0)  // ERROR: must be final
```

**Q: If `lateinit val` never changes, why no smart cast?**
Because it isn't thread-safe. Under a data race two threads can see
different values, so stability isn't guaranteed and a smart cast
would be unsound. KEEP-0455 says a thread-safe variant would remove
the obstacle. Until then, copy to a local `val`.

```kotlin
val s = shape
if (s is Circle) println(s.radius)
```

**Q: My DI stopped injecting after switching to `lateinit val`.**
The backing field is private and typed `Object`, and `@field:` is
not allowed. Annotate the setter: `@set:Inject`. The KEEP proposes
an IDE intention for this.

```kotlin
@set:Inject lateinit val payments: PaymentGateway
```
