package ru.marslab.snaptrace.ai

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.client.request.forms.*
import io.ktor.http.*
import io.ktor.http.content.*
import io.ktor.server.config.*
import io.ktor.server.testing.*
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class JobRoutesTest {
    private fun ByteArrayContentType(ct: ContentType) = object : OutgoingContent.ByteArrayContent() {
        override val contentType: ContentType = ct
        override fun bytes(): ByteArray = ByteArray(1024) { 1 } // 1KB dummy
    }

    @Test
    fun create_job_success() = testApplication {
        application { serverModule() }
        val mp1 = MultiPartFormDataContent(
            formData {
                append("prompt", "Закат над морем")
                append("file", ByteArray(1024), Headers.build {
                    append(HttpHeaders.ContentType, ContentType.Image.JPEG.toString())
                    append(HttpHeaders.ContentDisposition, "filename=\"image.jpg\"")
                })
            }
        )
        val response = client.post("/v1/jobs") {
            header(HttpHeaders.ContentType, mp1.contentType.toString())
            setBody(mp1)
        }
        val body = response.bodyAsText()
        println("create_job_success: status=${response.status} body=${body}")
        assertEquals(HttpStatusCode.OK, response.status)
        assertTrue(body.contains("jobId"))
        assertTrue(body.contains("queued"))
    }

    @Test
    fun create_job_missing_file() = testApplication {
        application { serverModule() }
        val mp2 = MultiPartFormDataContent(
            formData { append("prompt", "тест") }
        )
        val response = client.post("/v1/jobs") {
            header(HttpHeaders.ContentType, mp2.contentType.toString())
            setBody(mp2)
        }
        val body = response.bodyAsText()
        println("create_job_missing_prompt: status=${response.status} body=${body}")
        assertEquals(HttpStatusCode.BadRequest, response.status)
    }

    @Test
    fun create_job_missing_prompt() = testApplication {
        application { serverModule() }
        val mp3 = MultiPartFormDataContent(
            formData {
                append("file", ByteArray(1024), Headers.build {
                    append(HttpHeaders.ContentType, ContentType.Image.PNG.toString())
                    append(HttpHeaders.ContentDisposition, "filename=\"image.png\"")
                })
            }
        )
        val response = client.post("/v1/jobs") {
            header(HttpHeaders.ContentType, mp3.contentType.toString())
            setBody(mp3)
        }
        assertEquals(HttpStatusCode.BadRequest, response.status)
    }

    @Test
    fun create_job_unsupported_media() = testApplication {
        application { serverModule() }
        val mp4 = MultiPartFormDataContent(
            formData {
                append("prompt", "тест")
                append("file", ByteArray(1024), Headers.build {
                    append(HttpHeaders.ContentType, ContentType.Image.GIF.toString())
                    append(HttpHeaders.ContentDisposition, "filename=\"image.gif\"")
                })
            }
        )
        val response = client.post("/v1/jobs") {
            header(HttpHeaders.ContentType, mp4.contentType.toString())
            setBody(mp4)
        }
        assertEquals(HttpStatusCode.UnsupportedMediaType, response.status)
    }

    @Test
    fun create_job_too_large() = testApplication {
        environment {
            config = MapApplicationConfig(
                "snapTrace.upload.maxBytes" to "100" // 100 bytes
            )
        }
        application { serverModule() }
        val mp5 = MultiPartFormDataContent(
            formData {
                append("prompt", "тест")
                append("file", ByteArray(1024), Headers.build {
                    append(HttpHeaders.ContentType, ContentType.Image.JPEG.toString())
                    append(HttpHeaders.ContentDisposition, "filename=\"big.jpg\"")
                })
            }
        )
        val response = client.post("/v1/jobs") {
            header(HttpHeaders.ContentType, mp5.contentType.toString())
            setBody(mp5)
        }
        val body = response.bodyAsText()
        println("create_job_too_large: status=${response.status} body=${body}")
        assertEquals(HttpStatusCode.BadRequest, response.status)
    }
}
