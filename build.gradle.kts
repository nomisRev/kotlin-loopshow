plugins {
  id("org.jetbrains.kotlin.jvm") version "2.4.20"
}

repositories {
  mavenCentral()
}

dependencies {
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-reactive:1.11.0")
  implementation("org.jetbrains.kotlinx:kotlinx-coroutines-reactor:1.11.0")
  implementation("io.projectreactor:reactor-core:3.7.11")
  implementation("org.jetbrains:annotations:26.0.1")
  implementation("jakarta.validation:jakarta.validation-api:3.1.1")
  implementation("org.jspecify:jspecify:1.0.0")
  implementation("org.springframework.ai:spring-ai-client-chat:1.0.3")
  implementation("org.springframework:spring-web:6.2.11")
}

kotlin {
  jvmToolchain(21)
  compilerOptions.freeCompilerArgs.addAll(
    "-Xcollection-literals",
    "-Xreturn-value-checker=full",
    "-Xallow-returns-result-of",
    "-Xcontext-sensitive-resolution",
    "-Xintrinsic-const-evaluation",
    "-Xcompanion-blocks-and-extensions",
    "-Xexplicit-context-arguments",
    "-Xlocal-type-aliases",
    "-Xname-based-destructuring=complete",
  )
}

val snippetsCheck = tasks.register<Exec>("snippetsCheck") {
  commandLine("npx", "slidev-kotlin-snippets", "--check")
}

tasks.check { dependsOn(snippetsCheck) }
