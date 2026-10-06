---
title: "Name-based destructuring"
subtitle: "Destructure by property name, not by position, and make order bugs impossible"
author: "Notes from KEEP-0438, KEEP-0032, KEEP-0412"
date: "October 2026"
lang: en
---

## At a glance

Three sources feed this article. Facts come with a label so you know
where each one is from:

- **KEEP**: the proposal text. This is the source of truth.
- **(release notes)**: the Kotlin "What's new" pages in
  `research/kotlin-changelog/`.
- **(kotlinc 2.4.20)**: behaviour I checked by compiling small files
  with the 2.4.20 compiler this project uses.
- **(my reading)**: my own extrapolation. It is not a KEEP claim.

| Source | Status |
|---|---|
| [KEEP-0438](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0438-name-based-destructuring.md) name-based + new positional | Design proposal |
| [KEEP-0032](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0032-destructuring-in-parameters.md) lambda destructuring | Stable in 1.1 |
| [KEEP-0412](https://github.com/Kotlin/KEEP/blob/main/proposals/KEEP-0412-underscores-for-local-variables.md) `val _` | Experimental in 2.2 |

- **KEEP-0438 status line**: "Working on the implementation, it's not
  public yet". The snapshot is older than the releases.
- **Shipped** (release notes): Experimental since **Kotlin 2.3.20**,
  behind `-Xname-based-destructuring=<mode>`. The modes are
  `only-syntax`, `name-mismatch` and `complete`.
- **Next** (release notes): the 2.5.0-Beta1 EAP page says name-based
  destructuring "in `only-syntax` mode" becomes Stable. That covers the
  full `(val x, val y)` form only. The short `val (x, y)` form keeps its
  positional meaning.
- **YouTrack**: [KT-19627](https://youtrack.jetbrains.com/issue/KT-19627/Object-name-based-destructuring)
  "Object name-based destructuring".
- **Discussion**: [KEEP-438](https://github.com/Kotlin/KEEP/discussions/438).

Enabling it on 2.3.20 to 2.4.x (release notes):

```kotlin
kotlin {
    compilerOptions {
        freeCompilerArgs.add(
            "-Xname-based-destructuring=only-syntax"
        )
    }
}
```

Teaser:

```kotlin
data class User(val name: String, val email: String)

val (email, name) = user        // positional: swapped!
(val email, val name) = user    // by name: correct
(val mail = email) = user       // renaming
for ((val name) in users) println(name)
val [first, second] = 1 to "one" // new positional
```

## The problem

### Positional destructuring is `componentN` in disguise

Today `val (a, b) = x` compiles to `x.component1()` and
`x.component2()`. The variable *names* play no part. The KEEP calls
this **position-based** or **positional** destructuring.

```kotlin
val (name, age) = person

// desugars to
val tmp = person
val name = tmp.component1()
val age = tmp.component2()
```

For a data class the compiler generates one `componentN` for each
primary constructor property, in declaration order:

```kotlin
data class Person(val name: String, val age: Int)
// compiler-generated, conceptually:
//   operator fun component1(): String = name
//   operator fun component2(): Int = age
```

### Loss of semantic clarity

When two properties have the same type, swapping the names still
compiles. The bug only shows up at runtime:

```kotlin
data class User(val username: String, val email: String)

val user = User("alice", "alice@example.com")
val (email, username) = user
println(email)    // prints: alice
println(username) // prints: alice@example.com
```

Nothing in this code looks wrong. The reader trusts the names, and the
compiler ignores them.

### Refactoring hazards: adding a property in the middle

The KEEP's main example. You add `age` between `name` and `address`.
You also add a secondary constructor so old callers keep compiling:

```kotlin
// v1
data class Person(val name: String, val address: String)

// v2: 'age' inserted in the middle
data class Person(
    val name: String,
    val age: Int?,
    val address: String,
) {
    constructor(name: String, address: String) :
        this(name, null, address)
}
```

Two things break:

1. **Source compatibility.** `val (name, address) = person` now binds
   `address` to `component2()`, which is `age: Int?`. If the types
   differ you get a compile error far from the change. If they match,
   the code silently reads the wrong field.
2. **Binary compatibility.** `component2()` changed its return type
   from `String` to `Int?`. Already compiled clients call
   `component2()Ljava/lang/String;`, and that method no longer exists.

```kotlin
// client compiled against v1
val (name, address) = person
// v2 source: address is Int?  -> type errors
// v2 binary: NoSuchMethodError on component2
```

Adding a property with a default is normally a binary-compatible
change. Data classes break that rule only because of position.

### Private properties block everything after them

Positional destructuring needs access to *every* `componentN` up to
the last one you bind. A `private` property makes its `componentN`
private, so you cannot destructure past it. Not even `_` helps:

```kotlin
data class Account(
    val owner: String,
    private val pin: Int,
    val iban: String,
)

fun show(a: Account) {
    val (o, p, i) = a // ERROR: INVISIBLE_MEMBER
    val (o2, _, i2) = a // ERROR: INVISIBLE_MEMBER
}
```

### Difficult extensibility

You can declare a `componentN` extension, but which `N`? It must not
clash with the generated ones, and readers must count to find it.

```kotlin
data class Money(val amount: Long, val currency: String)

// "the third component is the formatted string"?
operator fun Money.component3(): String =
    "$amount $currency"

val (amount, currency, label) = money // works, but obscure
```

### Where position still makes sense

The KEEP does not want to remove positional destructuring. Some types
really are ordered:

- ordered collections: `List`, arrays;
- unnamed tuples: `Pair`, `Triple`;
- key-value pairs: `IndexedValue`, `Map.Entry`. These are ordered by
  convention, because the stdlib treats the key as the first component
  (see `associate`).

```kotlin
val (head, next) = listOf(1, 2, 3)  // fine
val (k, v) = "EUR" to 100           // fine
```

### Out of scope

KEEP-0438 does **not** change data classes. They still generate
`componentN` functions. The KEEP leaves better control over those to a
separate proposal.

## The feature, step by step

Code in this section uses the syntax shipped under
`-Xname-based-destructuring=only-syntax` unless I say otherwise.

### Step 1: the full form, `(val x) = e`

Put each new variable inside parentheses with its own `val`. Each name
must match a property of the right-hand side:

```kotlin
data class User(val name: String, val email: String)

val user = User("alice", "alice@example.com")
(val email, val name) = user
println(name)  // prints: alice
println(email) // prints: alice@example.com
```

Order no longer matters. The KEEP gives this translation:

```kotlin
(val email, val name) = user
// translates to
val tmp = user
val email = tmp.email
val name = tmp.name
```

### Step 2: take only what you need

Each entry is an independent property read, so you can pick any subset
in any order. You never need `_` to skip a property:

```kotlin
data class Order(
    val id: Long,
    val customer: String,
    val total: Long,
    val currency: String,
)

(val total, val currency) = order
(val id) = order
```

### Step 3: renaming with `=`

If the local name should differ from the property, write
`val local = property`. The KEEP describes `val x` as shorthand for
`val x = x`.

```kotlin
(val orderId = id, val amount = total) = order
println(orderId) // prints: the order id
```

The right of `=` must be a **simple identifier**: one property name.
No dotted paths, no Elvis, no calls (see Rules).

### Step 4: types and `var`

Each entry is a full variable declaration, so you can add a type and
use `var` per entry:

```kotlin
(val name: String, var email: String) = user
email = email.lowercase()
```

The KEEP says repeating `val` "opens the door to using `var`". That is
the payoff of the repetition. (kotlinc 2.4.20: `var` works in
declarations and the type is checked against the property type.)

### Step 5: for-loops

Destructuring works in the element position of `for`:

```kotlin
val users = listOf(
    User("alice", "a@example.com"),
    User("bob", "b@example.com"),
)

for ((val email, val name) in users) {
    println("$name <$email>")
}
// prints: alice <a@example.com>
// prints: bob <b@example.com>
```

Translation from the KEEP:

```kotlin
for (tmp in users) {
    val email = tmp.email
    val name = tmp.name
    // body
}
```

### Step 6: lambdas

KEEP-0032 (Kotlin 1.1) added positional destructuring in lambda
parameters: `{ (a, b) -> ... }`. KEEP-0438 adds the full name-based
form in the same place:

```kotlin
users.forEach { (val name) -> println(name) }

users.map { (val name, val email) ->
    "$name <$email>"
}
```

The declarations run as the first statements of the body, in argument
order. That matches KEEP-0032's rule for positional parameters:

```kotlin
{ (val name, val email) -> body() }
// translates to
{ arg1 ->
    val name = arg1.name
    val email = arg1.email
    body()
}
```

The grammar also allows a type on the whole destructured parameter:

```kotlin
users.forEach { (val email): User ->
    println(email)
}
```

### Step 7: the new positional syntax with `[ ]`

Positional destructuring gets its own brackets. They are modelled on
the collection literal syntax, so they read as "ordered":

```kotlin
val pair = Pair(3, "hello")

[val number, val text] = pair // full form
val [number2, text2] = pair   // short form
```

It still calls `componentN`, with the same runtime behaviour as today.
Taking the second element of an empty list still fails at runtime.

The short form is meant for loops and lambdas over key-value pairs:

```kotlin
val prices = mapOf("EUR" to 100, "USD" to 110)

for ([code, amount] in prices) {
    println("$code=$amount")
}
```

### Step 8: the end goal, four forms

The KEEP's end state, after migration, has two axes: by name or by
position, and short or full.

```kotlin
val (fullName, age) = person            // name, short
(val name = fullName, val age) = person // name, full

val [number, string] = pair             // position, short
[val number, val string] = pair         // position, full
```

Both short and full forms allow renaming, and both allow `val` or
`var`. In the short form one `val`/`var` applies to every variable.
In the end state, parentheses mean "by name" and brackets mean "by
position".

Today the short-form `val (x, y)` is still positional. It only becomes
name-based in Phase 3 of the migration (see Rules and Design). On
2.4.20 that behaviour is available as
`-Xname-based-destructuring=complete`.

## Typical usage

### Domain models: no more order-coupling

```kotlin
data class Invoice(
    val id: String,
    val issuedTo: String,
    val net: Long,
    val vat: Long,
    val currency: String,
)

fun render(invoice: Invoice): String {
    (val net, val vat, val currency) = invoice
    return "${net + vat} $currency"
}
```

Insert `discount` between `net` and `vat` and `render` still reads
the right fields. The old positional `val (id, to, net, vat) = invoice`
would have shifted silently.

### HTTP request handling

Any type with properties works, not only data classes. A plain class
with `val`s is enough:

```kotlin
class HttpRequest(
    val method: String,
    val path: String,
    val headers: Map<String, String>,
) {
    val contentType: String?
        get() = headers["Content-Type"]
}

fun route(req: HttpRequest): String {
    (val method, val path, val contentType) = req
    return "$method $path ($contentType)"
}
```

`contentType` is a computed property, not a constructor parameter, and
it still destructures.

### Ktor-style handlers and coroutines code

Lambdas that receive an event or a message can unpack the fields they
care about in the parameter list:

```kotlin
data class Event(
    val id: Long,
    val type: String,
    val payload: String,
)

suspend fun consume(events: Flow<Event>) {
    events.collect { (val type, val payload) ->
        dispatch(type, payload)
    }
}
```

(Uses `kotlinx.coroutines.flow.Flow`. `dispatch` is your own function.)

### Maps, indices and pairs: name or position, your choice

`Map.Entry` has `key` and `value` properties, and `IndexedValue` has
`index` and `value`. So both styles work (kotlinc 2.4.20):

```kotlin
for ((val key, val value) in prices) {
    println("$key -> $value")
}

for ([code, amount] in prices) {
    println("$code -> $amount")
}

for ((val index, val value) in names.withIndex()) {
    println("$index: $value")
}
```

If you want your own names, the bracket form is the shortest. The
name-based form needs renaming:
`(val code = key, val amount = value)`.

### Extension properties as "virtual fields"

Destructuring works for **any** property that resolves on the value,
extension properties included:

```kotlin
data class Temperature(val celsius: Double)

val Temperature.fahrenheit: Double
    get() = celsius * 9 / 5 + 32

(val celsius, val fahrenheit) = Temperature(20.0)
println(fahrenheit) // prints: 68.0
```

This solves the KEEP's "difficult extensibility" problem. You don't
pick an `N`. You declare a property and destructure it by name.

## Rules and edge cases

### Resolution: plain property access

The translation is the whole semantics. Each `val x = p` becomes
`val x = tmp.p`, resolved like any `tmp.p` at that point. The KEEP
notes that this makes the feature available for **any property in any
type**:

- primary-constructor properties of data classes;
- body properties and computed properties of regular classes;
- abstract properties in classes and interfaces;
- extension properties;
- Java getters and record components, seen as Kotlin properties (see
  Interop).

Because the property is resolved on the static type, interfaces work:

```kotlin
interface Shape {
    val area: Double
    val name: String
}

fun describe(s: Shape) {
    (val name, val area) = s
    println("$name: $area")
}
```

### Which properties are eligible: the three options

The KEEP considered three scopes:

1. only primary constructor properties;
2. only member properties;
3. any property, including extensions.

It chose **option 3**. Option 1 is how Java records and Haskell
records work, but it rules out interfaces, because interfaces have no
constructor. Options 2 and 3 both make destructuring "a shorthand for a
sequence of simple declarations". Option 2 would give class authors
full control over what can be destructured. The KEEP judged that this
control is not worth the reduced availability and the lack of
uniformity with the rest of the language.

### Evaluation order and exceptions

The right side is evaluated once, into a temporary. Properties are then
read **in the order written in the destructuring**, not in declaration
order. If one accessor throws, the later ones never run:

```kotlin
class Sensor {
    val id: String get() = "s-1"
    val reading: Double
        get() = error("offline")
    val unit: String
        get() = "C".also { println("unit read") }
}

(val id, val reading, val unit) = Sensor()
// throws IllegalStateException: offline
// "unit read" is never printed
```

### Unknown name: error

```kotlin
(val mail) = user
// ERROR: unresolved reference 'mail' on
//        receiver of type 'User'
```

(Compiler message from kotlinc 2.4.20.) With positional destructuring
you can name the variable anything. Here the name is a reference, so
typos are caught.

### Visibility: private properties are simply skipped

Visibility is checked per property. You can skip a private property and
still read everything else:

```kotlin
data class Account(
    val owner: String,
    private val pin: Int,
    val iban: String,
)

(val owner, val iban) = account   // OK
(val pin) = account
// ERROR: cannot access 'val pin: Int':
//        it is private in 'Account'
```

Compare this to the positional `val (o, _, i) = account`, which is an
error. Inside `Account` itself `pin` is visible, so `(val pin) = this`
compiles there (my reading: it follows from ordinary resolution).

### Renaming takes only a simple identifier

```kotlin
(val city = address.city) = person
// ERROR: syntax error (only identifiers after '=')

(val name = fullName ?: "n/a") = person
// ERROR: syntax error

(val name = fullName) = person // OK
```

The KEEP restricts renaming on purpose. Once you want expressions, a
separate line per variable reads better. Nested access, Elvis and
indexing (`(val name = ["name"]) = json`) are listed as **potential
extensions**, not part of the proposal.

### Types: declared vs property type

An explicit type works like it does on a plain `val`. The property type
must be assignable to it:

```kotlin
(val name: CharSequence) = user // OK, String <: CS
(val name: Int) = user
// ERROR: initializer type mismatch:
//        expected 'Int', actual 'String'
```

### Nullability

Because the access is `tmp.p`, a nullable receiver is a normal
unsafe-call error. There is no implicit `?.`:

```kotlin
val maybe: User? = find(id)
(val name) = maybe
// ERROR: only safe (?.) or non-null asserted
//        (!!.) calls are allowed on a nullable
//        receiver of type 'User?'

(val name) = maybe ?: return
```

### Generics

The property type is the member type after substitution, just like
`tmp.p`:

```kotlin
data class Page<T>(val items: List<T>, val next: String?)

fun first(page: Page<User>) {
    (val items, val next) = page
    // items: List<User>, next: String?
}
```

### Duplicate names

All new variables are ordinary locals in one scope, so the usual
conflict rule applies. To read one property twice you would need two
different local names, and that works:

```kotlin
(val id = name, val id = email) = user
// ERROR: conflicting declarations

(val a = name, val b = name) = user // OK
```

KEEP-0032's naming rule still holds for lambdas. All names declared in
one lambda's parameter list, plain parameters and destructured
components alike, must be unique.

### Underscore `_`

KEEP-0412 made `val _ = expr` legal for unused locals (Experimental in
2.2). Positional destructuring has long allowed `_` to skip a
component. KEEP-0438's grammar note says: in the parenthesised forms
(`multiParenVariableDeclaration` and
`fullMultiParenVariableDeclaration`), `_` is **forbidden, except when
using renaming**.

```kotlin
(val _, val email) = user
// ERROR: underscore in name-based destructuring
//        without renaming is forbidden

(val _ = name, val email) = user // allowed
```

The reasoning: in name-based destructuring, `_` would be a property
name, and there is no property called `_`. You also don't need it to
skip anything, because you just leave the property out. With renaming,
`val _ = name` reads `name` and discards it, which can matter if the
getter has a side effect you want to trigger (my reading).

The bracket forms are not covered by that note, so `_` keeps working
there (kotlinc 2.4.20):

```kotlin
val [_, amount] = "EUR" to 100      // OK
[val _, val amount2] = "EUR" to 100 // OK
```

**Migration catch.** Today the short form `val (x, _) = e` is
positional and legal. Under `name-mismatch` the compiler already warns
(kotlinc 2.4.20): "this syntax will be used for name-based
destructuring in a future release, and an underscore without renaming
will become an error". Under `complete` it is the error above.

### No annotations or modifiers on entries

You cannot annotate an individual entry in the full form. The KEEP
flags this as an important restriction:

```kotlin
(@Suppress("UNUSED") val name) = user
// ERROR: only expressions are allowed here
```

Why: `(val` must be recognisable after **one token** of lookahead.

- `(` could also start a parenthesised expression.
- `[` could also start an indexing expression or collection literal.

Modifiers that can never start an expression (like `public`) could be
allowed in theory. Annotations, though, can precede expressions. The
parser would need unbounded lookahead to tell `(@A val x)` from
`(@A expr)`, which would hurt parsing performance. A dedicated keyword
was rejected as too wordy for such a common feature.

### Loops and lambdas: `val` only

In loops and lambdas only `val` is allowed. That fits `for` and lambda
parameters, which are never reassignable:

```kotlin
for ((var name) in users) { }
// ERROR: syntax error

users.forEach { (var name) -> }
// ERROR: syntax error
```

### Nested destructuring is not proposed

KEEP-0032 already noted that nested destructuring
(`{ ((a, b), c) -> }`) is unsupported for `val`/`var`. KEEP-0438 does
not add it. Nested property *paths* in renaming are also only a
"potential extension".

```kotlin
(val city = address.city) = person
// not in the proposal (see above)

(val address) = person
(val city) = address // two steps instead
```

### Declaration only, no assignment

Destructuring only **declares** new variables. Assigning into existing
`var`s is a potential extension that the KEEP explicitly declines for
now. It raises questions like whether declaration and assignment can be
mixed:

```kotlin
var name = "unknown"
(name, val age) = person
// not proposed
```

### Smart casts through contracts (forward-looking)

The KEEP points out that the translation has typing consequences *if*
properties ever get contracts. Entries are checked in order, so an
earlier property's contract can smart-cast the receiver for a later
one:

```kotlin
open class A {
    val x: Int
        get() {
            contract { returns() implies (this@A is B) }
            ...
        }
}
class B(val y: Int) : A()

fun test(thing: A) {
    (val x, val y) = thing // accepted (hypothetical)
    (val y, val x) = thing // rejected
}
```

(The KEEP writes this in the short `val (x, y)` form, which means
name-based in the end state.) Property contracts do not exist today.
The KEEP notes that positional destructuring already behaves this way
with contracts on `componentN` functions.

### The migration warnings in detail

The KEEP defines three phases. They are not tied to a Kotlin version
or timeline. Compilers are expected to offer a flag that opts into
Phase 3.

**Phase 1: awareness.**

- Ship the full name-based form and both bracket forms. None of them
  conflicts with existing syntax.
- `val (x, y) = e` stays positional.
- *Tooling* (the IDE) nudges you to switch where the flip would change
  meaning. Ideally it offers automatic migration:
  - destructuring that uses auto-generated data class `componentN`
    becomes name-based, with renaming if needed;
  - all other usages become the bracket positional form.
- Tooling special-cases the inherently ordered types (`List`, arrays,
  `Pair`, `Triple`, `IndexedValue`, `Map.Entry`). There is **no**
  user-extensible list, because it would only be useful during
  migration.

**Phase 2: warnings.** The nudge moves from the IDE into the
*compiler*. It **warns** on every destructuring whose meaning would
change.

**Phase 3: the flip.** `val (x, y) = e` becomes name-based. Lambdas
and loops follow, so `{ (x, y) -> }` becomes name-based too.

**The intersection** makes this practical. If a short positional
declaration uses exactly the primary-constructor property names of a
data class, in the same order, positional and name-based give the same
result. That code needs **no** change:

```kotlin
data class User(val name: String, val email: String)

val (name, email) = user  // same meaning before & after
val (email2, name2) = user // changes meaning: warned
```

How 2.4.20 maps onto these phases (release notes plus kotlinc 2.4.20;
the mapping to phases is my reading):

| Mode | What it does |
|---|---|
| `only-syntax` | Phase 1: new forms on, `val (x, y)` still positional |
| `name-mismatch` | Phase 2: warnings on `val (x, y)` that would change |
| `complete` | Phase 3: `val (x, y)` is name-based, `[ ]` is positional |

The `name-mismatch` warnings I observed (kotlinc 2.4.20, shortened):

```kotlin
data class User(val name: String, val email: String)
class Box(val w: Int, val h: Int) {
    operator fun component1() = w
    operator fun component2() = h
}

val (email, name) = user
// WARNING: variable name 'email' differs from
//   accessed property name 'name'. This syntax
//   will be used for name-based destructuring
//   in a future release, and this code will
//   change its meaning.

val (w, h) = box
// WARNING: ... will stop compiling or change its
//   meaning for non-data class 'Box'

val (a, b) = listOf(1, 2)
// WARNING: ... non-data class 'List<Int>'

val (k, v) = "EUR" to 100
// WARNING: 'k' differs from accessed property
//   name 'first'

val (key, value) = entry // no warning
```

The warning text suggests three fixes: the full name-based form, the
bracket positional form, or renaming the variables to match. The
compiler, unlike the KEEP's Phase 1 IDE tooling, does warn on `Pair`,
`List` and `IndexedValue` (kotlinc 2.4.20). The fix for those is
`[k, v]`.

Under `complete`, the same lines fail:

```kotlin
val (k, v) = "EUR" to 100
// ERROR: unresolved reference 'k' on receiver
//        of type 'Pair<String, Int>'

val [k, v] = "EUR" to 100 // the migration
```

Note that `val (first, second) = pair` and `val (key, value) = entry`
mean the same thing in both modes.

### Short-form renaming needs `complete`

The grammar adds renaming to the short parenthesised form,
`val (n = name, email) = user`. On 2.4.20 this is rejected under
`only-syntax` and `name-mismatch`, with an error that asks for
`-Xname-based-destructuring=complete`. That makes sense. During Phase 1
the short form is still positional, and renaming has no meaning in a
positional declaration.

```kotlin
val (n = name, email) = user
// ERROR (only-syntax): the feature "enable name
//   based destructuring short form" is
//   experimental ... '-Xname-based-
//   destructuring=complete'
```

The KEEP itself does not say when short-form renaming becomes legal.
The flagged behaviour is what kotlinc does.

### Without any flag

On 2.4.20 without the flag, the full form is rejected (kotlinc 2.4.20):

```kotlin
(val name) = user
// ERROR: the feature "name based destructuring"
//        is only available since language
//        version 2.5
```

With `-language-version 2.5` (experimental on 2.4.20), the full form
compiles and `val (x, y)` stays positional without warnings. This
matches the 2.5.0-Beta1 note that `only-syntax` becomes the stable
default.

### Per-type switching is not a thing

You cannot mark a type as "destructure by name". The meaning depends
only on the syntax at the use site: parentheses or brackets. See Design
decisions for why.

## Platform interop

### JVM bytecode: getters in, `componentN` out

Name-based destructuring compiles to plain getter calls.
Bracket-positional compiles to `componentN`. From `javap -c` on
kotlinc 2.4.20 output:

```kotlin
fun t(u: User): String {
    (val email, val name) = u
    val [a, b] = u
    return email + name + a + b
}
```

```text
invokevirtual User.getEmail:()Ljava/lang/String;
invokevirtual User.getName:()Ljava/lang/String;
invokevirtual User.component1:()Ljava/lang/String;
invokevirtual User.component2:()Ljava/lang/String;
```

The declaring class is unchanged. Name-based destructuring adds no
members, no annotations and no metadata. It is a purely use-site
feature.

### Binary and source compatibility

The coupling moves from **position** to **name**:

| Change in library | Positional client | Name-based client |
|---|---|---|
| insert property mid-constructor | breaks (src + bin) | unaffected |
| reorder properties | silent swap or break | unaffected |
| rename a property | unaffected | breaks |

The last row is my reading, but it follows directly from the
translation. Renaming a property already breaks every ordinary
`user.name` access, so name-based destructuring adds no new kind of
fragility. It only removes the position-based one. Data classes keep
generating `componentN` (out of scope), so old positional clients keep
linking exactly as before.

### Java classes with getters

Kotlin already shows Java getters as synthetic properties: `getName()`
becomes `name` and `isActive()` becomes `isActive`. The KEEP's
translation is `tmp.p`, so these destructure by name (kotlinc 2.4.20
confirms this):

```java
public class JUser {
    private final String name;
    private final boolean active;

    public JUser(String name, boolean active) {
        this.name = name;
        this.active = active;
    }
    public String getName() { return name; }
    public boolean isActive() { return active; }
}
```

```kotlin
val ju = JUser("jane", true)
(val name, val isActive) = ju
(val enabled = isActive) = ju
println("$name $enabled") // prints: jane true
```

Before this feature you could only destructure such a class by writing
`operator fun JUser.component1()` extensions yourself.

### Java records

Java records have no `componentN`, so positional destructuring never
worked on them. Kotlin does expose record components as properties,
so name-based destructuring works:

```java
public record Point(int x, int y) {}
```

```kotlin
val p = Point(1, 2)
val (x, y) = p
// ERROR: destructuring of type 'Point' requires
//        operator function 'component1()'

(val x, val y) = p      // OK
(val y2 = y, val x2 = x) = p
```

(Both results checked with kotlinc 2.4.20. The KEEP does not mention
Java at all. It works because of the "any property" rule.)

### What Java sees of Kotlin types

Nothing changes on the Java side. A Kotlin data class still exposes
`getName()`, `component1()`, `copy(...)` and so on. Java has no
destructuring declarations. Java 21's record patterns (JEP 440, which
the KEEP cites) only apply to real records. A Kotlin `@JvmRecord data
class` is a real record, so Java can pattern-match it. That has nothing
to do with KEEP-0438 (my reading):

```java
// Java 21, on a Kotlin @JvmRecord data class
if (obj instanceof User(String name, String email)) {
    System.out.println(name);
}
```

Java record patterns are **positional**, against the canonical
constructor. Kotlin's new default is by name.

### JS, Native, Wasm, KMP

The KEEP defines the feature purely as a frontend desugaring to
property accesses. Nothing about it is backend-specific, so it should
behave identically on every target and in common code (my reading).
For `expect`/`actual` classes, the properties visible on the `expect`
declaration are the ones you can destructure in common code (my
reading).

### Reflection and serialization

There is nothing to reflect on. No declarations, annotations or
metadata are added. kotlinx.serialization is unaffected (my reading).
Note one difference from positional destructuring: it works on classes
that have no `componentN` at all, such as serializable DTOs that are
not data classes.

## Design decisions

### Why new syntax instead of re-interpreting `val (x, y)` now?

Flipping the meaning overnight would silently change every
declaration whose names don't match its positions. The KEEP gets there
through three phases, using the intersection (matching data class
declarations) to keep most existing code valid.

```kotlin
val (name, email) = user // survives the flip
val (a, b) = user        // must migrate first
```

### Why `(val x, val y)`?

The syntax had to look familiar enough to be accepted and different
enough not to be confused with the old form. Writing `val` in each
entry:

- makes it obvious that new variables are declared;
- reads naturally with renaming: `val name = fullName`;
- allows `var` and a type on each entry;
- leaves room for pattern matching, where Kotlin will need to tell
  "compare with existing `name`" from "bind new `name`". A token like
  `val` is needed for that anyway.

```kotlin
// future pattern matching idea from the KEEP,
// not proposed syntax:
person is Person(val name, val age)
```

The cost is the repeated `val`. The KEEP accepts it.

### Why `[ ]` for positional?

Brackets look like collection literals, which are ordered. That gives
an immediate "by position" reading, and it pairs nicely with the
parentheses for "by name".

### Rejected: per-type destructuring mode

The alternative was a modifier or annotation on a class that decides
whether `val (x, y)` is by name or by position for that type. It lost
for two reasons:

- the **use site** no longer tells you which kind applies;
- it **breaks with generics**. If `person` has an interface type, does
  `val (age, name) = person` follow the interface or the runtime
  subclass?

```kotlin
interface Named { val name: String }

fun <T : Named> greet(t: T) {
    val (name) = t // by name? by position?
}
```

### Rejected: rich expressions after `=`

`(val city = address.city)` and similar are only possible extensions.
The KEEP's view is that complex right-hand sides read better as
separate statements.

### Rejected: annotations per entry, and a keyword

See Rules. Allowing annotations would need unbounded parser lookahead.
A keyword to mark the destructuring kind was called "too wordy for a
feature that is so heavily used".

### Rejected: only constructor properties, or only members

Constructor-only (as in Java records and Haskell) cannot abstract over
interfaces. Members-only gives the class author control but is less
available and inconsistent with the rest of the language. The KEEP
picks "any property".

### Known cost: completion

When you type `(val name = <caret>`, the IDE does not yet know the
right-hand side type, so it cannot suggest property names. The KEEP's
suggested mitigation is a template that asks for the expression first
and then moves the caret inside the parentheses.

### Comparison with Java and Haskell

The KEEP compares with Java record patterns (JEP 440) and Haskell
record patterns. Both are tied to the declared record components or
constructor. Kotlin's version works on any property, extensions
included. It is "a shorthand for a sequence of simple declarations",
not a structural pattern. Java's patterns are also positional and use
a type or `var` per component. Kotlin's use `val` and match by name.
The KEEP does not compare with Scala, Swift or C#.

## Open questions and what may change

- **Timeline of phases.** The KEEP deliberately ties none of the three
  phases to a version. The release notes show `only-syntax` heading to
  Stable in 2.5.0. When the short form flips by default is not stated
  anywhere in the sources.
- **Short-form renaming and `var`.** The end-goal grammar allows
  `val (n = name, age)` and `var (...)`. The KEEP doesn't say in which
  phase these become available. kotlinc 2.4.20 requires `complete`.
- **IDE vs compiler special-casing.** Phase 1 says *tooling* should
  special-case ordered types like `Pair` and `List`. The 2.4.20
  `name-mismatch` mode warns on them anyway. Whether that stays is
  open.
- **Potential extensions**, none of them proposed:
  - nested paths: `(val city = address.city) = person`;
  - Elvis: `(val name = fullName ?: "unknown") = person`;
  - indexing: `(val name = ["name"]) = json`;
  - assignment to existing variables: `(name, val age) = person`;
  - pattern matching: `person is Person(val name, val age)`.
- **Data class `componentN` control** is explicitly out of scope and
  left to a future KEEP.
- **Contracts on properties** would make the order of entries matter
  for typing. That is speculative, because property contracts do not
  exist.
- **Function parameter destructuring** (`fun f((a, b): Pair<..>)`) was
  floated in KEEP-0032 as "may be supported later". KEEP-0438 does not
  touch it.

```kotlin
// none of these are proposed:
(val city = address.city) = person
(name, val age) = person
fun show((val name): User) {}
```

## Cheat sheet

```kotlin
// by name, full (Phase 1+, -X...=only-syntax)
(val email, val name) = user
(val mail = email) = user           // rename
(val name: String, var email) = user
for ((val name) in users) { }
users.map { (val name) -> name }
users.forEach { (val email): User -> }

// by position, new
val [code, amount] = "EUR" to 100   // short
[val code2, val amt2] = "EUR" to 100 // full
for ([k, v] in map) { }

// by name, short (Phase 3, -X...=complete)
val (email, name) = user
val (mail = email) = user
```

- Name-based means `tmp.prop` for each entry, in written order.
- Works on any property: data, regular, interface, extension, Java
  getters, Java records.
- Pick any subset. Skip private properties freely.
- Renaming takes only a simple identifier.
- No annotations per entry. No `var` in loops or lambdas.
- `_` is forbidden in `( )` unless renamed. It is fine in `[ ]`.
- Brackets still call `componentN`.
- Migration: IDE nudge, then compiler warnings, then the flip of
  `val (x, y)`.
- Matching data class code (same names, same order) needs no change.
- JVM: getter calls. Nothing new on the declaring class.

## Talking points

- "`val (email, name) = user` compiles today and swaps your fields.
  Name-based destructuring makes that impossible."
- "Parentheses mean by name, brackets mean by position. That's the
  whole mental model."
- "It's just property access: `(val x) = e` is `val x = e.x`. So it
  works on any class, interface, extension property, even Java getters
  and records."
- "Adding a property in the middle of a data class no longer breaks
  your callers, at the source level or the binary level."
- "Private property in the middle? Positional destructuring gave up.
  Name-based just skips it."
- "Your existing `val (name, email) = user` already matches the names,
  so it survives the flip unchanged."
- "Migration is three steps: IDE hints, compiler warnings, then the
  short syntax changes meaning. You can try each step today with
  `-Xname-based-destructuring`."

**Q: Does this deprecate data classes or `componentN`?**
No. Data classes still generate `componentN`, and the KEEP explicitly
leaves them alone. The bracket syntax still uses them. Only the meaning
of the short `val (x, y)` form flips, and only in Phase 3.

**Q: How do I destructure a `Pair` or a map entry after the flip?**
Use brackets: `val [k, v] = pair` or `for ([key, value] in map)`.
Name-based also works where the names fit:
`(val first, val second) = pair` or `for ((val key, val value) in
map)`. Code that already uses `key`/`value` or `first`/`second`
doesn't change meaning.

**Q: Why can't I write `(@Suppress("X") val x) = e`?**
`(` and `[` already start expressions, and annotations can precede
expressions. Deciding which rule applies would then need unbounded
lookahead. The KEEP kept one-token lookahead for parser performance,
and rejected a dedicated keyword as too wordy.
