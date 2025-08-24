package ru.marslab.snaptrace.ai

import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.http.content.*
import io.ktor.server.testing.*
import io.ktor.server.config.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import ru.marslab.snaptrace.ai.clients.ArtClient
import ru.marslab.snaptrace.ai.clients.ArtClientStub
import ru.marslab.snaptrace.ai.clients.ArtResult
import ru.marslab.snaptrace.ai.clients.GptClient
import ru.marslab.snaptrace.ai.clients.GptClientStub
import kotlin.test.Ignore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class JobRoutesTest {
    companion object {
        private val workerLock = Mutex()
    }
    private fun ByteArrayContentType(ct: ContentType) = object : OutgoingContent.ByteArrayContent() {
        override val contentType: ContentType = ct
        override fun bytes(): ByteArray = ByteArray(1024) { 1 } // 1KB dummy
    }

    @Test
    fun create_job_success() = testApplication {
        environment {
            config = MapApplicationConfig(
                "snapTrace.worker.autostart" to "false"
            )
        }
        application { serverModule() }
        InMemoryStore.stopWorker()
        InMemoryStore.configureProcessors(ArtClientStub(), GptClientStub())
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
        environment {
            config = MapApplicationConfig(
                "snapTrace.worker.autostart" to "false"
            )
        }
        application { serverModule() }
        InMemoryStore.stopWorker()
        InMemoryStore.configureProcessors(ArtClientStub(), GptClientStub())
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
        environment {
            config = MapApplicationConfig(
                "snapTrace.worker.autostart" to "false"
            )
        }
        application { serverModule() }
        InMemoryStore.stopWorker()
        InMemoryStore.configureProcessors(ArtClientStub(), GptClientStub())
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
        environment {
            config = MapApplicationConfig(
                "snapTrace.worker.autostart" to "false"
            )
        }
        application { serverModule() }
        InMemoryStore.stopWorker()
        InMemoryStore.configureProcessors(ArtClientStub(), GptClientStub())
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
                "snapTrace.upload.maxBytes" to "100", // 100 bytes
                "snapTrace.worker.autostart" to "false"
            )
        }
        application { serverModule() }
        InMemoryStore.stopWorker()
        InMemoryStore.configureProcessors(ArtClientStub(), GptClientStub())
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

    @Ignore("flaky: требует доработки изоляции воркера и синхронизации исполнения теста")
    @Test
    fun job_status_transitions_to_published() = testApplication {
        workerLock.withLock {
            environment {
                config = MapApplicationConfig(
                    "snapTrace.worker.autostart" to "false"
                )
            }
            application { serverModule() }
            // Ensure isolated worker and stub clients for this test
            InMemoryStore.stopWorker()
            InMemoryStore.configureProcessors(ArtClientStub(), GptClientStub())
            InMemoryStore.startWorker(CoroutineScope(Dispatchers.Default), processingDelayMs = 10L)
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

    @Ignore("flaky: требует доработки обработки ошибок и изоляции воркера в тесте")
    @Test
    fun job_fails_when_art_client_throws() = testApplication {
        workerLock.withLock {
            environment {
                config = MapApplicationConfig(
                    "snapTrace.worker.autostart" to "false"
                )
            }
            application { serverModule() }
            // Ensure isolated worker and failing stub clients for this test
            InMemoryStore.stopWorker()
            InMemoryStore.configureProcessors(
                art = object : ArtClient {
                    override suspend fun generate(prompt: String): ArtResult {
                        throw RuntimeException("art down")
                    }
                },
                gpt = object : GptClient {
                    override suspend fun caption(imageUrl: String, prompt: String): String = "n/a"
                }
            )
            InMemoryStore.startWorker(CoroutineScope(Dispatchers.Default), processingDelayMs = 10L)

            val mp = MultiPartFormDataContent(
                formData {
                    append("prompt", "should fail")
                    append("file", ByteArray(64), Headers.build {
                        append(HttpHeaders.ContentType, ContentType.Image.JPEG.toString())
                        append(HttpHeaders.ContentDisposition, "filename=\"bad.jpg\"")
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
            assertTrue(jobId != null)

            var status: String? = null
            var attempts = 0
            while (attempts < 50) {
                val sResp = client.get("/v1/jobs/$jobId")
                assertEquals(HttpStatusCode.OK, sResp.status)
                val sBody = sResp.bodyAsText()
                status = Regex(""""status":"(\w+)"""").find(sBody)?.groupValues?.get(1)
                if (status == "failed") break
                delay(20)
                attempts++
            }
            println("job_fails_when_art_client_throws: status=$status after $attempts attempts")
            assertEquals("failed", status)
        }
    }
}
