package ru.marslab.snaptrace.ai.routes

import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import ru.marslab.snaptrace.ai.InMemoryStore
import ru.marslab.snaptrace.ai.model.FeedResponse

fun Application.registerFeedRoutes() {
    routing {
        get("/v1/feed") {
            val limit = call.request.queryParameters["limit"]?.toIntOrNull() ?: 10
            val items = InMemoryStore.listFeed(limit)
            call.respond(FeedResponse(items = items, nextCursor = null))
        }
    }
}
