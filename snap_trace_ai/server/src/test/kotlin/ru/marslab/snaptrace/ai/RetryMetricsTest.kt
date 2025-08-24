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
import ru.marslab.snaptrace.ai.clients.GptConfig
import ru.marslab.snaptrace.ai.clients.RealGptClient
import ru.marslab.snaptrace.ai.clients.ArtConfig
import ru.marslab.snaptrace.ai.clients.RealArtClient
import ru.marslab.snaptrace.ai.metrics.Metrics

class RetryMetricsTest {

    @Test
    fun gpt_retries_then_succeeds_and_records_metrics() = runBlocking {
        Metrics.reset()
        val endpoint = "https://example.com/gpt"
        var calls = 0
        val engine = MockEngine { _ ->
            calls += 1
            if (calls == 1) {
                respond(
                    content = "error",
                    status = HttpStatusCode.InternalServerError,
                    headers = headersOf("Content-Type", "text/plain")
                )
            } else {
                respond(
                    content = """{"result":{"alternatives":[{"message":{"text":"OK"}}]}}""",
                    status = HttpStatusCode.OK,
                    headers = headersOf("Content-Type", "application/json")
                )
            }
        }
        val http = HttpClient(engine) { install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) } }
        val cfg = GptConfig(
            endpoint = endpoint,
            model = "yandexgpt",
            temperature = 0.6,
            maxTokens = 2000,
            systemText = "system",
            timeoutMs = 5_000,
            retryMaxAttempts = 3,
            retryBaseDelayMs = 1,
            retryMaxDelayMs = 4,
        )
        val client = RealGptClient(
            iamToken = "token",
            apiKey = "",
            folderId = "folder",
            cfg = cfg,
            client = http,
        )
        val result = client.caption("https://img", "prompt")
        assertEquals("OK", result)
        val s = Metrics.snapshot()
        assertEquals(1, s.gptAttempts)
        assertEquals(1, s.gptSuccesses)
    }

    @Test
    fun gpt_retries_and_fails_records_failure_metric() = runBlocking {
        Metrics.reset()
        val endpoint = "https://example.com/gpt"
        val engine = MockEngine { _ ->
            respond(
                content = "error",
                status = HttpStatusCode.InternalServerError,
                headers = headersOf("Content-Type", "text/plain")
            )
        }
        val http = HttpClient(engine) { install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) } }
        val cfg = GptConfig(
            endpoint = endpoint,
            model = "yandexgpt",
            temperature = 0.6,
            maxTokens = 2000,
            systemText = "system",
            timeoutMs = 5_000,
            retryMaxAttempts = 2,
            retryBaseDelayMs = 1,
            retryMaxDelayMs = 2,
        )
        val client = RealGptClient(
            iamToken = "token",
            apiKey = "",
            folderId = "folder",
            cfg = cfg,
            client = http,
        )
        assertFailsWith<Exception> { client.caption("https://img", "prompt") }
        val s = Metrics.snapshot()
        assertEquals(1, s.gptAttempts)
        assertEquals(0, s.gptSuccesses)
    }

    @Test
    fun art_start_retries_then_succeeds_and_records_metrics() = runBlocking {
        Metrics.reset()
        val startUrl = "https://example.com/start"
        val opsUrl = "https://example.com/ops"
        var startCalls = 0
        val engine = MockEngine { request ->
            val url = request.url.toString()
            if (request.method == HttpMethod.Post && url == startUrl) {
                startCalls += 1
                if (startCalls == 1) {
                    respond(
                        content = "error",
                        status = HttpStatusCode.InternalServerError,
                        headers = headersOf("Content-Type", "text/plain")
                    )
                } else {
                    respond(
                        content = """{"id":"op-10","done":false}""",
                        status = HttpStatusCode.OK,
                        headers = headersOf("Content-Type", "application/json")
                    )
                }
            } else if (request.method == HttpMethod.Get && url == "$opsUrl/op-10") {
                respond(
                    content = """{"id":"op-10","done":true,"response":{"image":"QUJD"}}""",
                    status = HttpStatusCode.OK,
                    headers = headersOf("Content-Type", "application/json")
                )
            } else {
                respond("not found", HttpStatusCode.NotFound, headersOf("Content-Type", "text/plain"))
            }
        }
        val http = HttpClient(engine) { install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) } }
        val cfg = ArtConfig(
            endpoint = startUrl,
            operationsEndpoint = opsUrl,
            model = "yandex-art/latest",
            seed = 1,
            aspectWidth = 2,
            aspectHeight = 1,
            pollIntervalMs = 1,
            pollTimeoutMs = 1_000,
            timeoutMs = 5_000,
            retryMaxAttempts = 3,
            retryBaseDelayMs = 1,
            retryMaxDelayMs = 4,
        )
        val client = RealArtClient(
            iamToken = "token",
            apiKey = "",
            folderId = "folder",
            cfg = cfg,
            client = http,
        )
        val res = client.generate("prompt")
        assertEquals("data:image/jpeg;base64,QUJD", res.imageUrl)
        val s = Metrics.snapshot()
        assertEquals(1, s.artStartAttempts)
        assertEquals(1, s.artStartSuccesses)
        // at least one poll recorded
        // attempts must be >= successes
        assert(s.artPollAttempts >= s.artPollSuccesses)
        assert(s.artPollAttempts >= 1)
    }

    @Test
    fun art_poll_fail_then_succeed_records_both_attempts() = runBlocking {
        Metrics.reset()
        val startUrl = "https://example.com/start"
        val opsUrl = "https://example.com/ops"
        var pollCalls = 0
        val engine = MockEngine { request ->
            val url = request.url.toString()
            if (request.method == HttpMethod.Post && url == startUrl) {
                respond(
                    content = """{"id":"op-20","done":false}""",
                    status = HttpStatusCode.OK,
                    headers = headersOf("Content-Type", "application/json")
                )
            } else if (request.method == HttpMethod.Get && url == "$opsUrl/op-20") {
                pollCalls += 1
                if (pollCalls == 1) {
                    respond(
                        content = "error",
                        status = HttpStatusCode.InternalServerError,
                        headers = headersOf("Content-Type", "text/plain")
                    )
                } else {
                    respond(
                        content = """{"id":"op-20","done":true,"response":{"image":"QUJD"}}""",
                        status = HttpStatusCode.OK,
                        headers = headersOf("Content-Type", "application/json")
                    )
                }
            } else {
                respond("not found", HttpStatusCode.NotFound, headersOf("Content-Type", "text/plain"))
            }
        }
        val http = HttpClient(engine) { install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) } }
        val cfg = ArtConfig(
            endpoint = startUrl,
            operationsEndpoint = opsUrl,
            model = "yandex-art/latest",
            seed = 1,
            aspectWidth = 2,
            aspectHeight = 1,
            pollIntervalMs = 1,
            pollTimeoutMs = 1_000,
            timeoutMs = 5_000,
            retryMaxAttempts = 2,
            retryBaseDelayMs = 1,
            retryMaxDelayMs = 2,
        )
        val client = RealArtClient(
            iamToken = "token",
            apiKey = "",
            folderId = "folder",
            cfg = cfg,
            client = http,
        )
        val res = client.generate("prompt")
        assertEquals("data:image/jpeg;base64,QUJD", res.imageUrl)
        val s = Metrics.snapshot()
        // one failed poll + one successful poll
        assert(s.artPollAttempts >= 2)
        assert(s.artPollSuccesses >= 1)
    }
}
