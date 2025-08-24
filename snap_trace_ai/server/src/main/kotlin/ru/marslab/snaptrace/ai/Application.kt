package ru.marslab.snaptrace.ai

import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.statuspages.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json
import ru.marslab.snaptrace.ai.routes.registerFeedRoutes
import ru.marslab.snaptrace.ai.routes.registerHealthRoutes
import ru.marslab.snaptrace.ai.routes.registerJobRoutes
import ru.marslab.snaptrace.ai.util.respondError

fun main() {
    embeddedServer(Netty, port = 8080, host = "0.0.0.0") {
        serverModule()
    }.start(wait = true)
}

fun Application.serverModule() {
    install(ContentNegotiation) {
        json(
            Json {
                prettyPrint = false
                ignoreUnknownKeys = true
                explicitNulls = false
            }
        )
    }
    install(StatusPages) {
        exception<Throwable> { call, cause ->
            call.respondError(500, cause.message ?: "internal_error")
        }
    }

    // In-memory storage for MVP skeleton
    InMemoryStore.init()

    // Routes
    registerHealthRoutes()
    registerJobRoutes()
    registerFeedRoutes()
}
