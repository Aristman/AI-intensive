package ru.marslab.snaptrace.ai.clients

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.ClientRequestException
import io.ktor.client.plugins.ServerResponseException
import io.ktor.client.plugins.HttpRequestTimeoutException
import io.ktor.client.request.post
import io.ktor.client.request.headers
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.coroutines.delay
import org.slf4j.LoggerFactory
import ru.marslab.snaptrace.ai.metrics.Metrics

class RealGptClient(
    private val iamToken: String,
    private val folderId: String,
    private val cfg: GptConfig,
    private val client: HttpClient = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(
                Json { ignoreUnknownKeys = true }
            )
        }
        install(HttpTimeout) {
            requestTimeoutMillis = cfg.timeoutMs
            connectTimeoutMillis = cfg.timeoutMs
            socketTimeoutMillis = cfg.timeoutMs
        }
    },
) : GptClient {

    private val log = LoggerFactory.getLogger(RealGptClient::class.java)

    @Serializable
    private data class CompletionOptions(
        val stream: Boolean = false,
        val temperature: Double,
        @SerialName("maxTokens") val maxTokens: Int,
        val reasoningOptions: ReasoningOptions = ReasoningOptions(),
    )

    @Serializable
    private data class ReasoningOptions(val mode: String = "DISABLED")

    @Serializable
    private data class Message(val role: String, val text: String)

    @Serializable
    private data class GptRequest(
        val modelUri: String,
        val completionOptions: CompletionOptions,
        val messages: List<Message>,
    )

    @Serializable
    private data class GptResponse(
        val result: Result? = null
    ) {
        @Serializable
        data class Result(
            val alternatives: List<Alternative> = emptyList()
        )
        @Serializable
        data class Alternative(
            val message: Message? = null,
            val status: String? = null
        ) {
            @Serializable
            data class Message(val role: String? = null, val text: String? = null)
        }
    }

    override suspend fun caption(imageUrl: String, prompt: String): String {
        val modelUri = "gpt://$folderId/${cfg.model}"
        val req = GptRequest(
            modelUri = modelUri,
            completionOptions = CompletionOptions(
                temperature = cfg.temperature,
                maxTokens = cfg.maxTokens
            ),
            messages = listOf(
                Message(
                    role = "user",
                    text = buildString {
                        appendLine(cfg.systemText)
                        appendLine()
                        appendLine("Ссылка на изображение: $imageUrl")
                        appendLine("Подсказка: $prompt")
                        append("Сгенерируй подпись.")
                    }
                ),
            )
        )

        val startedAt = System.currentTimeMillis()
        try {
            val resp: GptResponse = withRetry(
                actionName = "gpt.completion",
                maxAttempts = cfg.retryMaxAttempts,
                baseDelayMs = cfg.retryBaseDelayMs,
                maxDelayMs = cfg.retryMaxDelayMs,
            ) {
                val httpResp = client.post(cfg.endpoint) {
                    contentType(ContentType.Application.Json)
                    headers {
                        append("Authorization", "Bearer $iamToken")
                        append("x-folder-id", folderId)
                    }
                    setBody(req)
                }
                val code = httpResp.status.value
                when {
                    code in 200..299 -> httpResp.body<GptResponse>()
                    code == 429 -> throw ClientRequestException(httpResp, "Too Many Requests")
                    code in 500..599 -> throw ServerResponseException(httpResp, "Server error ${httpResp.status}")
                    else -> throw ClientRequestException(httpResp, "HTTP ${httpResp.status}")
                }
            }
            val text = resp.result?.alternatives?.firstOrNull()?.message?.text?.takeIf { !it.isNullOrBlank() }
            Metrics.recordGpt(System.currentTimeMillis() - startedAt, success = true)
            return text ?: ""
        } catch (e: Exception) {
            Metrics.recordGpt(System.currentTimeMillis() - startedAt, success = false)
            log.warn("GPT request failed after retries: ${e.message}")
            throw e
        }
    }

    private suspend fun <T> withRetry(
        actionName: String,
        maxAttempts: Int,
        baseDelayMs: Long,
        maxDelayMs: Long,
        block: suspend () -> T,
    ): T {
        var attempt = 1
        var nextDelay = baseDelayMs.coerceAtLeast(0)
        while (true) {
            try {
                return block()
            } catch (e: Exception) {
                val retriable = isRetriable(e)
                if (!retriable || attempt >= maxAttempts) {
                    log.debug("$actionName attempt=$attempt failed, retriable=$retriable; giving up: ${e.message}")
                    throw e
                }
                log.debug("$actionName attempt=$attempt failed; retrying in ${nextDelay}ms: ${e.message}")
                delay(nextDelay)
                attempt += 1
                nextDelay = (nextDelay * 2).coerceAtMost(maxDelayMs)
            }
        }
    }

    private fun isRetriable(e: Exception): Boolean {
        return when (e) {
            is HttpRequestTimeoutException -> true
            is ServerResponseException -> true // 5xx
            is ClientRequestException -> {
                // Retry on 429 Too Many Requests
                try {
                    e.response.status.value == 429
                } catch (_: Throwable) { false }
            }
            else -> false
        }
    }
}

