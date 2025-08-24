package ru.marslab.snaptrace.ai.util

import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import kotlinx.serialization.Serializable

suspend fun ApplicationCall.respondError(statusCode: Int, message: String) {
    respond(HttpStatusCode.fromValue(statusCode), ErrorResponse("error", message))
}

suspend fun ApplicationCall.respondOk(payload: Any) {
    respond(HttpStatusCode.OK, payload)
}

@Serializable
data class ErrorResponse(val code: String, val message: String)
