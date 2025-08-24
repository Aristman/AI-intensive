package ru.marslab.snaptrace.ai

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.client.request.forms.*
import io.ktor.http.*
import io.ktor.http.content.*
import io.ktor.server.config.*
import io.ktor.server.testing.*
import kotlinx.coroutines.delay
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

    @Test
    fun job_status_transitions_to_published() = testApplication {
        application { serverModule() }
        // Create job
        val mp = MultiPartFormDataContent(
            formData {
                append("prompt", "s2 test")
                append("file", ByteArray(128), Headers.build {
                    append(HttpHeaders.ContentType, ContentType.Image.JPEG.toString())
                    append(HttpHeaders.ContentDisposition, "filename=\"s2.jpg\"")
                })
            }
        )
        val createResp = client.post("/v1/jobs") {
            header(HttpHeaders.ContentType, mp.contentType.toString())
            setBody(mp)
        }
        assertEquals(HttpStatusCode.OK, createResp.status)
        val body = createResp.bodyAsText()
        val jobId = Regex(""""jobId":"([a-f0-9\-]+)"""").find(body)?.groupValues?.get(1)
        assertTrue(jobId != null, "jobId should be present")

        // Poll status until published with timeout
        var status: String? = null
        var attempts = 0
        while (attempts < 50) { // up to ~1s with 20ms sleeps
            val sResp = client.get("/v1/jobs/$jobId")
            assertEquals(HttpStatusCode.OK, sResp.status)
            val sBody = sResp.bodyAsText()
            status = Regex(""""status":"(\w+)"""").find(sBody)?.groupValues?.get(1)
            if (status == "published") break
            delay(20)
            attempts++
        }
        println("job_status_transitions_to_published: status=$status after $attempts attempts")
        assertEquals("published", status)
    }
}
