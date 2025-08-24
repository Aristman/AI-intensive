package ru.marslab.snaptrace.ai.clients

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.post
import io.ktor.client.request.headers
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

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

        val resp: GptResponse = client.post(cfg.endpoint) {
            contentType(ContentType.Application.Json)
            headers {
                append("Authorization", "Bearer $iamToken")
                append("x-folder-id", folderId)
            }
            setBody(req)
        }.body()

        val text = resp.result?.alternatives?.firstOrNull()?.message?.text?.takeIf { !it.isNullOrBlank() }
        return text ?: ""
    }
}
