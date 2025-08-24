package ru.marslab.snaptrace.ai

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import org.junit.Test
import kotlin.test.assertEquals
import ru.marslab.snaptrace.ai.clients.GptConfig
import ru.marslab.snaptrace.ai.clients.RealGptClient

class RealGptClientTest {
    @Test
    fun caption_returns_text_from_alternative() = runBlocking {
        val endpoint = "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"
        val engine = MockEngine { _ ->
            respond(
                content = """{"result":{"alternatives":[{"message":{"text":"OK"}}]}}""",
                status = HttpStatusCode.OK,
                headers = headersOf("Content-Type", "application/json")
            )
        }
        val http = HttpClient(engine) {
            install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
        }
        val cfg = GptConfig(
            endpoint = endpoint,
            model = "yandexgpt",
            temperature = 0.6,
            maxTokens = 2000,
            systemText = "system",
            timeoutMs = 5_000,
        )
        val client = RealGptClient(
            iamToken = "token",
            apiKey = "",
            folderId = "folder",
            cfg = cfg,
            client = http,
        )
        val result = client.caption("https://example.com/img.jpg", "prompt")
        assertEquals("OK", result)
    }

    @Test
    fun caption_returns_empty_when_result_missing() = runBlocking {
        val endpoint = "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"
        val engine = MockEngine { _ ->
            respond(
                content = "{}",
                status = HttpStatusCode.OK,
                headers = headersOf("Content-Type", "application/json")
            )
        }
        val http = HttpClient(engine) {
            install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
        }
        val cfg = GptConfig(
            endpoint = endpoint,
            model = "yandexgpt",
            temperature = 0.6,
            maxTokens = 2000,
            systemText = "system",
            timeoutMs = 5_000,
        )
        val client = RealGptClient(
            iamToken = "token",
            apiKey = "",
            folderId = "folder",
            cfg = cfg,
            client = http,
        )
        val result = client.caption("https://example.com/img.jpg", "prompt")
        assertEquals("", result)
    }

    @Test
    fun caption_returns_empty_when_alternatives_empty() = runBlocking {
        val endpoint = "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"
        val engine = MockEngine { _ ->
            respond(
                content = """{"result":{"alternatives":[]}}""",
                status = HttpStatusCode.OK,
                headers = headersOf("Content-Type", "application/json")
            )
        }
        val http = HttpClient(engine) {
            install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
        }
        val cfg = GptConfig(
            endpoint = endpoint,
            model = "yandexgpt",
            temperature = 0.6,
            maxTokens = 2000,
            systemText = "system",
            timeoutMs = 5_000,
        )
        val client = RealGptClient(
            iamToken = "token",
            apiKey = "",
            folderId = "folder",
            cfg = cfg,
            client = http,
        )
        val result = client.caption("https://example.com/img.jpg", "prompt")
        assertEquals("", result)
    }

    @Test
    fun caption_returns_empty_when_message_text_missing_or_blank() = runBlocking {
        val endpoint = "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"
        val engine = MockEngine { _ ->
            respond(
                content = """{"result":{"alternatives":[{"message":{}}]}}""",
                status = HttpStatusCode.OK,
                headers = headersOf("Content-Type", "application/json")
            )
        }
        val http = HttpClient(engine) {
            install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
        }
        val cfg = GptConfig(
            endpoint = endpoint,
            model = "yandexgpt",
            temperature = 0.6,
            maxTokens = 2000,
            systemText = "system",
            timeoutMs = 5_000,
        )
        val client = RealGptClient(
            iamToken = "token",
            apiKey = "",
            folderId = "folder",
            cfg = cfg,
            client = http,
        )
        val result = client.caption("https://example.com/img.jpg", "prompt")
        assertEquals("", result)
    }
}
