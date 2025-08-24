package ru.marslab.snaptrace.ai.routes

import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Application.registerHealthRoutes() {
    routing {
        get("/health") {
            call.respond(mapOf("status" to "ok"))
        }
    }
}
