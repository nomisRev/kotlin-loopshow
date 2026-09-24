---
theme: kotlin
transition: view-transition
layout: default
canvasWidth: 1440
aspectRatio: 16/9
colorSchema: both
title: Kotlin at Devoxx Belgium 2026
favicon: /favicon.svg
fonts:
  sans: JetBrains Sans
  mono: JetBrains Mono
  provider: none
  local:
    - JetBrains Sans
    - JetBrains Mono
highlighter: shiki
themeConfig:
  kodee: greeting
  drawnAnnotation:
    connect: false
  snippets:
    dir: src/main/kotlin/presentation/snippets
    javaDir: src/main/java/presentation/snippets
    package: presentation.snippets
    imports:
      - presentation.support.*
kodee:
  variant: welcome
  size: small
  position: corner
---

<!-- @formatter:off -->

# A companion block adds members in place

> Kotlin 2.5.0-Beta1 · `-Xcompanion-blocks-and-extensions`

<DrawnAnnotation text="Money.zero()" :line="2" label="A plain static call from Java\nno `@JvmStatic`, no `.Companion`" :geometry="{ label: { x: 0.5531, y: 0.6360, width: 0.5300 } }"/>

```kotlin
class Money(val cents: Int) {
  companion {
    fun zero(): Money = Money(0)
  }
}
```
```java
public class Register {
  Money total = Money.zero();
}
```

---

# A companion extension needs no companion

> Kotlin 2.5.0-Beta1 · `-Xcompanion-blocks-and-extensions`

<DrawnAnnotation text="companion fun LocalDate.epoch()" label="`LocalDate` is a Java class,\nit has no Kotlin companion to extend" :geometry="{ label: { x: 0.5852, y: 0.3779 } }"/>

```kotlin
import java.time.LocalDate

companion fun LocalDate.epoch() = LocalDate.ofEpochDay(0)

println(LocalDate.epoch())
```
```console
1970-01-01
```

---

# Square brackets build a collection

> Experimental in Kotlin 2.4.0 · `-Xcollection-literals`

<DrawnAnnotation text="[&quot;Ada&quot;, &quot;Linus&quot;, &quot;Grace&quot;]" label="A `List` by default" :geometry="{ label: { x: 0.5825, y: 0.3084, width: 0.2200 } }"/>
<DrawnAnnotation text="Set<Int>" label="The expected type picks the collection" color="var(--fundamentals-blue)" :geometry="{ label: { x: 0.3747, y: 0.4049, width: 0.4000 } }"/>

```kotlin
val names = ["Ada", "Linus", "Grace"]
val ages: Set<Int> = [36, 17, 28]

fun sum(numbers: Iterable<Int>): Int = numbers.sum()

val six = sum([1, 2, 3])
```

---

# A literal needs an `of()`

> Experimental in Kotlin 2.4.0 · `-Xcollection-literals`

<DrawnAnnotation text="operator fun of" label="A companion `of` operator makes `Team` a literal target" :geometry="{ label: { x: 0.3968, y: 0.5159, width: 0.6000 } }"/>

```kotlin
@JvmInline
value class Team(private val members: List<Member>) {
  companion object {
    operator fun of(vararg members: Member) = Team(members.toList())
  }
}

val team: Team = [Member("Ada", 36), Member("Linus", 17)]
println(team)
```
```console
Team(members=[Member(name=Ada, age=36), Member(name=Linus, age=17)])
```

---

# Destructuring matches by name, not position

> Kotlin 2.3.20 · `-Xname-based-destructuring=complete`

<DrawnAnnotation text="val (age, name)" label="Declared out of order, still bound by property name" :geometry="{ label: { x: 0.5831, y: 0.4564 } }"/>

```kotlin
data class Person(val name: String, val age: Int)
val person = Person("Ada", 36)

val (age, name) = person
println("$name is $age")
```
```console
Ada is 36
```

---

# `context` supplies a context without a receiver

> Stable since Kotlin 2.4.0

<TypeHint :line="8" context="Logger">
<DrawnAnnotation text="context(logger: Logger)" label="Requires a `Logger` dependency in the surrounding context"  :geometry="{ label: { x: 0.5789, y: 0.4513 }, connector: { type: 'quadratic', start: { x: 0.3251, y: 0.5217 }, control: { x: 0.3559, y: 0.5184 }, end: { x: 0.3674, y: 0.4873 } } }"/>

```kotlin
class Logger(val tag: String) {
  fun log(message: String) = println("[$tag] $message")
}

context(logger: Logger)
fun greet(name: String) = logger.log("hello, $name")

fun main() = context(Logger("APP")) {
  greet("Grace")
}
```
```console
[APP] hello, Grace
```

</TypeHint>

---

# An explicit backing field replaces the underscore

> Stable since Kotlin 2.4.0

<DrawnAnnotation text="List<String>" label="Outside, it is what the declaration says" :geometry="{ label: { x: 0.5461, y: 0.3138, width: 0.4200 }, connector: { type: 'quadratic', start: { x: 0.3453, y: 0.3763 }, control: { x: 0.3761, y: 0.3730 }, end: { x: 0.3876, y: 0.3419 } } }"/>
<DrawnAnnotation text="field" color="var(--fundamentals-blue)" />
<DrawnAnnotation text="items.add"  label="One property: the backing field keeps the wider type" color="var(--fundamentals-blue)" :geometry="{ label: { x: 0.4521, y: 0.6122 }, connector: { type: 'quadratic', start: { x: 0.1644, y: 0.5721 }, control: { x: 0.1729, y: 0.6137 }, end: { x: 0.1994, y: 0.6139 } } }"/>

```kotlin
class Cart {
  val items: List<String>
    field = mutableListOf()

  fun add(item: String) {
    items.add(item)
  }
}
```

<InlineCompilerError :line="2" text="add" message="Unresolved reference `add` on receiver type `List<String>`">

```kotlin
val cart = Cart()
cart.items.add("Ticket")
```

</InlineCompilerError>

---

# Ignoring a return value is a warning

> Experimental since Kotlin 2.3.0 · `-Xreturn-value-checker=full`

<DrawnAnnotation text="@CheckReturnValue" label="Java's annotation, read as `@MustUseReturnValues`: Error Prone, Spring and jOOQ ship one" :geometry="{ label: { x: 0.5746, y: 0.3168, width: 0.4905 }, connector: { type: 'quadratic', start: { x: 0.2533, y: 0.3329 }, control: { x: 0.3619, y: 0.3528 }, end: { x: 0.3835, y: 0.3303 } } }"/>

```java
import org.jetbrains.annotations.CheckReturnValue;

@CheckReturnValue
public class Money {
  private final long cents;

  public Money(long cents) { this.cents = cents; }

  public Money plus(Money other) { return new Money(cents + other.cents); }
}
```

<Warning :line="2" text="price.plus(Money(250))" message="Unused return value of 'plus'.">

```kotlin
val price = Money(1000)
price.plus(Money(250))
```

</Warning>

---

# Nullability is part of the type

> Kotlin reads JSpecify · Spring Framework 7 ships it

<DrawnAnnotation text="@NullMarked" label="JSpecify: everything here is non-null unless said otherwise" :geometry="{ label: { x: 0.5276, y: 0.3008, width: 0.6000 }, connector: { type: 'quadratic', start: { x: 0.1836, y: 0.3311 }, control: { x: 0.2303, y: 0.3345 }, end: { x: 0.2489, y: 0.3196 } } }"/>
<DrawnAnnotation text="@Nullable String" />

```java
import org.jspecify.annotations.NullMarked;
import org.jspecify.annotations.Nullable;

@NullMarked
public class Users {
  public static @Nullable String nickname(String id) { return null; }
}
```

<InlineCompilerError :line="4" text="Users.nickname(&quot;ada&quot;)" message="Initializer type mismatch: expected `String`, actual `String?`">

```kotlin
val shown = Users.nickname("ada") ?: "Ada"

val nick: String =
  Users.nickname("ada")
```

</InlineCompilerError>

---

# Kotlin compiles for Java 26

> Kotlin 2.4.0 emits Java 26 bytecode · `jvmToolchain(26)`

<DrawnAnnotation text="permits Circle, Square"/>
<DrawnAnnotation text="when (shape)" label="Java's `permits` list makes the Kotlin `when` exhaustive" :geometry="{ label: { x: 0.7313, y: 0.3841, width: 0.4042 } }"/>

```java
public sealed interface Shape permits Circle, Square {}
record Circle(double radius) implements Shape {}
record Square(double side) implements Shape {}
```

<SmartCast :line="2" text="shape">
<SmartCast :line="2" text="shape" occurrence="2">
<SmartCast :line="3" text="shape">
<SmartCast :line="3" text="shape" occurrence="2">
<DrawnAnnotation text="shape." :line="3" occurrence="2" label="A record component reads as a property with smart-casting" color="var(--fundamentals-blue)" :geometry="{ label: { x: 0.5764, y: 0.6322 }, connector: { type: 'quadratic', start: { x: 0.4179, y: 0.6125 }, control: { x: 0.4524, y: 0.6400 }, end: { x: 0.4500, y: 0.6857 } } }"/>

```kotlin
fun area(shape: Shape): Double = when (shape) {
  is Circle -> Math.PI * shape.radius * shape.radius
  is Square -> shape.side * shape.side
}
```

</SmartCast>
</SmartCast>
</SmartCast>
</SmartCast>

---

# `when` compiles to `invokedynamic`

> Stable since Kotlin 2.4.20 · JVM 21 and later

<DrawnAnnotation text="typeSwitch" label="The same invokedynamic Java's pattern-matching `switch` uses (JEP 441)" :geometry="{ label: { x: 0.4723, y: 0.8556, width: 0.7000 }, connector: { type: 'quadratic', start: { x: 0.6262, y: 0.7993 }, control: { x: 0.6202, y: 0.8149 }, end: { x: 0.6262, y: 0.8348 } } }"/>

```kotlin
sealed interface Shape
data class Circle(val radius: Double) : Shape
data class Square(val side: Double) : Shape

fun area(shape: Shape): Double = when (shape) {
  is Circle -> Math.PI * shape.radius * shape.radius
  is Square -> shape.side * shape.side
}
```

```bash
$ javap -c AreaKt | grep invokedynamic
   8: invokedynamic #29,  0  // InvokeDynamic #0:typeSwitch:(Ljava/lang/Object;I)I
```

---

# Lombok classes are visible to Kotlin

> `kotlin("plugin.lombok")` · Alpha since Kotlin 2.3.20

<DrawnAnnotation text="@Data" label="Getters and setters exist only once Lombok has run" :geometry="{ label: { x: 0.3638, y: 0.3028, width: 0.5500 }, connector: { type: 'quadratic', start: { x: 0.1153, y: 0.3325 }, control: { x: 0.1663, y: 0.3315 }, end: { x: 0.2173, y: 0.3095 } } }"/>
<DrawnAnnotation text="talk.title = " label="The plugin lets Kotlin see them as properties" color="var(--fundamentals-blue)" :geometry="{ label: { x: 0.5110, y: 0.6767 }, connector: { type: 'quadratic', start: { x: 0.2076, y: 0.6492 }, control: { x: 0.2992, y: 0.6449 }, end: { x: 0.3102, y: 0.6766 } } }"/>

```java no-compile
@Data
public class Talk {
  private String title;
  private int minutes;
}
```

```kotlin no-compile
val talk = Talk()
talk.title = "Kotlin at Devoxx"
println(talk.minutes)
```

---

# Rich errors are unions, not exceptions

> KEEP-441 · under design

<DrawnAnnotation text="User | FetchError" label="The error is part of the return type" :geometry="{ label: { x: 0.6761, y: 0.4277, width: 0.4540 }, connector: { type: 'quadratic', start: { x: 0.4515, y: 0.4745 }, control: { x: 0.4861, y: 0.4888 }, end: { x: 0.5320, y: 0.4538 } } }"/>
<DrawnAnnotation text="?.charge" label="Safe calls propagate the error to the right" color="var(--fundamentals-blue)" :geometry="{ label: { x: 0.6545, y: 0.6646, width: 0.4087 }, connector: { type: 'quadratic', start: { x: 0.4092, y: 0.6237 }, control: { x: 0.4174, y: 0.6775 }, end: { x: 0.4522, y: 0.6671 } } }"/>
<SmartCast :line="10" text="transaction">
<SmartCast :line="11" text="transaction">

```kotlin no-compile
error object FetchError
error class TransactionError(val message: String)

fun fetchUser(): User | FetchError = ...
fun User.charge(amount: Double): TransactionId | TransactionError = ...

val transaction = fetchUser()?.charge(amount = 10.0)

when (transaction) {
  is TransactionId -> "Transaction succeeded: $transaction"
  is TransactionError -> "Transaction failed: ${transaction.message}"
  is FetchError -> "Failed to fetch data"
}
```

</SmartCast>
</SmartCast>

---

# Kotlin LSP brings Kotlin to VS Code and agents

> Roadmap: Support Kotlin LSP and VS Code · KT-80322

```bash
brew install JetBrains/utils/kotlin-lsp

kotlin-lsp --stdio
```

- **VS Code**: the Kotlin extension by JetBrains, powered by the LSP
- **Any editor**: Neovim, Zed, Helix, and every other LSP client
- **Agents**: Claude Code, Codex and friends get diagnostics, navigation and completion

---

# Kotlin runs everywhere

> One language, one codebase, every platform

<KotlinPlatforms />

---
layout: intro
class: meet-us-slide
kodee: wave
---

<div class="lesson-number">KotlinConf 2027</div>

# KotlinConf 2027 is coming to Kraków

- **21–23 April 2027** · ICE Kraków
- Ticket prices rise after **16 October 2026**
- Call for Papers: ask us at the booth
