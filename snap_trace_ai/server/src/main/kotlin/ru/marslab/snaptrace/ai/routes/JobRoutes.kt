package ru.marslab.snaptrace.ai.routes

import io.ktor.http.*
import io.ktor.http.content.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.utils.io.*
import io.ktor.utils.io.core.*
import ru.marslab.snaptrace.ai.InMemoryStore
import ru.marslab.snaptrace.ai.model.CreateJobResponse
import ru.marslab.snaptrace.ai.model.JobStatusResponse
import java.util.*

fun Application.registerJobRoutes() {
    routing {
        post("/v1/jobs") {
            val config = call.application.environment.config
            val maxBytes = runCatching { config.property("snapTrace.upload.maxBytes").getString().toLong() }
                .getOrDefault(15L * 1024 * 1024) // 15 MB default

            var prompt: String? = null
            var lat: Double? = null
            var lon: Double? = null
            var deviceId: String? = null
            var fileContentType: ContentType? = null
            var fileSize: Long = 0
            var fileProvided = false
            var errorResponse: Pair<HttpStatusCode, Any>? = null

            val multipart = call.receiveMultipart()
            multipart.forEachPart { part ->
                when (part) {
                    is PartData.FileItem -> {
                        fileProvided = true
                        fileContentType = part.contentType
                        val ct = part.contentType
                        if (ct == null || !(ct.match(ContentType.Image.JPEG) || ct.match(ContentType.Image.PNG))) {
                            errorResponse = HttpStatusCode.UnsupportedMediaType to mapOf("error" to "unsupported_media_type")
                            part.dispose()
                            return@forEachPart
                        }
                        // Read at most maxBytes+1 and check overflow
                        val channel = part.provider()
                        val packet: ByteReadPacket = channel.readRemaining(maxBytes + 1)
                        fileSize = packet.remaining
                        if (fileSize > maxBytes) {
                            errorResponse = HttpStatusCode.BadRequest to mapOf("error" to "file_too_large")
                            packet.discard()
                            part.dispose()
                            return@forEachPart
                        }
                        packet.discard()
                        part.dispose()
                    }
                    is PartData.FormItem -> {
                        when (part.name) {
                            "prompt" -> prompt = part.value.trim().ifEmpty { null }
                            "lat" -> lat = part.value.toDoubleOrNull()
                            "lon" -> lon = part.value.toDoubleOrNull()
                            "deviceId" -> deviceId = part.value.trim().ifEmpty { null }
                        }
                        part.dispose()
                    }
                    else -> part.dispose()
                }
            }

            errorResponse?.let { (code, body) ->
                return@post call.respond(code, body)
            }
            if (!fileProvided) {
                return@post call.respond(HttpStatusCode.BadRequest, mapOf("error" to "missing_file"))
            }
            if (prompt == null) {
                return@post call.respond(HttpStatusCode.BadRequest, mapOf("error" to "missing_prompt"))
            }

            // TODO: EXIF нормализация (timestamp, geo) — опционально, на этапе S1 можно пропустить

            val jobId = UUID.randomUUID().toString()
            InMemoryStore.createJob(jobId, prompt = prompt ?: "", lat = lat, lon = lon, deviceId = deviceId)
            InMemoryStore.enqueueJob(jobId)
            call.respond(HttpStatusCode.OK, CreateJobResponse(jobId = jobId))
        }

        get("/v1/jobs/{jobId}") {
            val jobId = call.parameters["jobId"] ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "missing_jobId"))
            val status = InMemoryStore.getJobStatus(jobId) ?: return@get call.respond(HttpStatusCode.NotFound, mapOf("error" to "not_found"))
            call.respond(JobStatusResponse(status = status, error = null, result = null))
        }
    }
}
