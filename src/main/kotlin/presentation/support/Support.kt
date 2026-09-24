// Hand-written context for the generated snippets in ../snippets/.
//
// The slides use these symbols without defining them on every slide; each
// generated file star-imports this package. A snippet that defines its own
// symbol of the same name shadows the one here, because a declaration in the
// file's own package wins over a star import.
package presentation.support

import java.util.concurrent.CompletableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import reactor.core.publisher.Flux
import reactor.core.publisher.Mono

/** Shared dataset, the same names as kotlin-fundamentals. */
data class Member(val name: String, val age: Int)

val members = listOf(Member("Ada", 36), Member("Linus", 17), Member("Grace", 28))

/** The conference domain behind the coroutine slides. */
data class Speaker(val name: String)
data class Talk(val title: String, val minutes: Int)
data class Dashboard(val speaker: Speaker, val talks: List<Talk>, val attendance: List<Int>)

val talks = listOf(Talk("Structured concurrency", 45), Talk("Flow", 30))

suspend fun fetchTalks(): List<Talk> {
  delay(10)
  return talks
}

/** A Java-style SDK with one method per asynchronous style. */
class ConferenceSdk {
  fun speaker(id: Long): CompletableFuture<Speaker> =
    CompletableFuture.completedFuture(Speaker("Grace"))

  fun talks(speakerId: Long): Mono<List<Talk>> = Mono.just(talks)

  fun attendance(talkId: Long): Flux<Int> = Flux.just(10, 20, 30, 40, 50)
}

val sdk = ConferenceSdk()

/** An application scope for the cancellation slides. */
val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

/** Graph nodes for the nested type alias slide. */
typealias NodeId = Int
