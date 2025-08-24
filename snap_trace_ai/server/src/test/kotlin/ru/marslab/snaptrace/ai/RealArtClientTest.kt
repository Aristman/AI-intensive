package ru.marslab.snaptrace.ai

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import ru.marslab.snaptrace.ai.clients.ArtConfig
import ru.marslab.snaptrace.ai.clients.RealArtClient

class RealArtClientTest {
    @Test
    fun generate_returns_data_url_when_operation_ready() = runBlocking {
        val startUrl = "https://example.com/start"
        val opsUrl = "https://example.com/ops"
        val engine = MockEngine { request ->
            val url = request.url.toString()
            if (request.method == HttpMethod.Post && url == startUrl) {
                respond(
                    content = """{"id":"op-1","done":false}""",
                    status = HttpStatusCode.OK,
                    headers = headersOf("Content-Type", "application/json")
                )
            } else if (request.method == HttpMethod.Get && url == "$opsUrl/op-1") {
                respond(
                    content = """{"id":"op-1","done":true,"response":{"image":"QUJD"}}""",
                    status = HttpStatusCode.OK,
                    headers = headersOf("Content-Type", "application/json")
                )
            } else {
                respond(
                    content = "not found",
                    status = HttpStatusCode.NotFound,
                    headers = headersOf("Content-Type", "text/plain")
                )
            }
        }
        val http = HttpClient(engine) {
            install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
        }
        val cfg = ArtConfig(
            endpoint = startUrl,
            operationsEndpoint = opsUrl,
            model = "yandex-art/latest",
            seed = 42,
            aspectWidth = 2,
            aspectHeight = 1,
            pollIntervalMs = 1,
            pollTimeoutMs = 1_000,
            timeoutMs = 5_000,
        )
        val client = RealArtClient(
            iamToken = "token",
            apiKey = "",
            folderId = "folder",
            cfg = cfg,
            client = http,
        )
        val result = client.generate("prompt")
        assertEquals("data:image/jpeg;base64,QUJD", result.imageUrl)
    }

    @Test
    fun generate_throws_timeout_when_not_done_within_deadline() {
        runBlocking {
            val startUrl = "https://example.com/start"
            val opsUrl = "https://example.com/ops"
            val engine = MockEngine { request ->
                val url = request.url.toString()
                if (request.method == HttpMethod.Post && url == startUrl) {
                    respond(
                        content = """{"id":"op-2","done":false}""",
                        status = HttpStatusCode.OK,
                        headers = headersOf("Content-Type", "application/json")
                    )
                } else if (request.method == HttpMethod.Get && url == "$opsUrl/op-2") {
                    respond(
                        content = """{"id":"op-2","done":false}""",
                        status = HttpStatusCode.OK,
                        headers = headersOf("Content-Type", "application/json")
                    )
                } else {
                    respond(
                        content = "not found",
                        status = HttpStatusCode.NotFound,
                        headers = headersOf("Content-Type", "text/plain")
                    )
                }
            }
            val http = HttpClient(engine) {
                install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
            }
            val cfg = ArtConfig(
                endpoint = startUrl,
                operationsEndpoint = opsUrl,
                model = "yandex-art/latest",
                seed = 42,
                aspectWidth = 2,
                aspectHeight = 1,
                pollIntervalMs = 1,
                pollTimeoutMs = 10,
                timeoutMs = 5_000,
            )
            val client = RealArtClient(
                iamToken = "token",
                apiKey = "",
                folderId = "folder",
                cfg = cfg,
                client = http,
            )
            assertFailsWith<IllegalStateException> {
                client.generate("prompt")
            }
        }
    }

    @Test
    fun generate_throws_when_done_but_image_missing() {
        runBlocking {
            val startUrl = "https://example.com/start"
            val opsUrl = "https://example.com/ops"
            val engine = MockEngine { request ->
                val url = request.url.toString()
                if (request.method == HttpMethod.Post && url == startUrl) {
                    respond(
                        content = """{"id":"op-3","done":false}""",
                        status = HttpStatusCode.OK,
                        headers = headersOf("Content-Type", "application/json")
                    )
                } else if (request.method == HttpMethod.Get && url == "$opsUrl/op-3") {
                    respond(
                        content = """{"id":"op-3","done":true,"response":{}}""",
                        status = HttpStatusCode.OK,
                        headers = headersOf("Content-Type", "application/json")
                    )
                } else {
                    respond(
                        content = "not found",
                        status = HttpStatusCode.NotFound,
                        headers = headersOf("Content-Type", "text/plain")
                    )
                }
            }
            val http = HttpClient(engine) {
                install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
            }
            val cfg = ArtConfig(
                endpoint = startUrl,
                operationsEndpoint = opsUrl,
                model = "yandex-art/latest",
                seed = 42,
                aspectWidth = 2,
                aspectHeight = 1,
                pollIntervalMs = 1,
                pollTimeoutMs = 1_000,
                timeoutMs = 5_000,
            )
            val client = RealArtClient(
                iamToken = "token",
                apiKey = "",
                folderId = "folder",
                cfg = cfg,
                client = http,
            )
            assertFailsWith<IllegalStateException> {
                client.generate("prompt")
            }
        }
    }
}

