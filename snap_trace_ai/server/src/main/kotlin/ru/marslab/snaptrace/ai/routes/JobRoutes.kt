package ru.marslab.snaptrace.ai.routes

import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable
import ru.marslab.snaptrace.ai.InMemoryStore
import ru.marslab.snaptrace.ai.model.CreateJobResponse
import ru.marslab.snaptrace.ai.model.JobStatusResponse
import java.time.Instant
import java.util.*

fun Application.registerJobRoutes() {
    routing {
        // Stub of multipart upload: we just consume and ignore content for MVP skeleton
        post("/v1/jobs") {
            // In real implementation: parse multipart, validate file and fields
            val jobId = UUID.randomUUID().toString()
            InMemoryStore.createJob(jobId)
            call.respond(HttpStatusCode.OK, CreateJobResponse(jobId = jobId))
        }

        get("/v1/jobs/{jobId}") {
            val jobId = call.parameters["jobId"] ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "missing_jobId"))
            val status = InMemoryStore.getJobStatus(jobId) ?: return@get call.respond(HttpStatusCode.NotFound, mapOf("error" to "not_found"))
            call.respond(JobStatusResponse(status = status, error = null, result = null))
        }
    }
}
