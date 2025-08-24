package ru.marslab.snaptrace.ai.clients

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.headers
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

class RealArtClient(
    private val iamToken: String,
    private val folderId: String,
    private val cfg: ArtConfig,
    private val client: HttpClient = HttpClient(CIO) {
        install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
        install(HttpTimeout) {
            requestTimeoutMillis = cfg.timeoutMs
            connectTimeoutMillis = cfg.timeoutMs
            socketTimeoutMillis = cfg.timeoutMs
        }
    },
) : ArtClient {

    @Serializable
    private data class AspectRatio(
        @SerialName("widthRatio") val width: Int,
        @SerialName("heightRatio") val height: Int,
    )

    @Serializable
    private data class GenerationOptions(
        val seed: Long,
        val aspectRatio: AspectRatio,
    )

    @Serializable
    private data class ArtMessage(
        val weight: String = "1",
        val text: String,
    )

    @Serializable
    private data class ArtRequest(
        val modelUri: String,
        val generationOptions: GenerationOptions,
        val messages: List<ArtMessage>,
    )

    @Serializable
    private data class StartOpResponse(
        val id: String,
        val done: Boolean = false,
    )

    @Serializable
    private data class OperationGetResponse(
        val id: String? = null,
        val done: Boolean = false,
        val response: OpResponse? = null,
    ) {
        @Serializable
        data class OpResponse(val image: String? = null)
    }

    override suspend fun generate(prompt: String): ArtResult {
        val modelUri = "art://$folderId/${cfg.model}"
        val req = ArtRequest(
            modelUri = modelUri,
            generationOptions = GenerationOptions(
                seed = cfg.seed,
                aspectRatio = AspectRatio(cfg.aspectWidth, cfg.aspectHeight)
            ),
            messages = listOf(ArtMessage(text = prompt))
        )

        val start: StartOpResponse = client.post(cfg.endpoint) {
            contentType(ContentType.Application.Json)
            headers {
                append("Authorization", "Bearer $iamToken")
                append("x-folder-id", folderId)
            }
            setBody(req)
        }.body()

        val opId = start.id
        val startedAt = System.currentTimeMillis()
        while (System.currentTimeMillis() - startedAt < cfg.pollTimeoutMs) {
            val op: OperationGetResponse = client.get("${cfg.operationsEndpoint}/$opId") {
                headers { append("Authorization", "Bearer $iamToken") }
            }.body()
            if (op.done) {
                val b64 = op.response?.image
                if (!b64.isNullOrBlank()) {
                    val dataUrl = "data:image/jpeg;base64,$b64"
                    return ArtResult(imageUrl = dataUrl)
                } else {
                    throw IllegalStateException("Yandex Art operation done but image is empty")
                }
            }
            kotlinx.coroutines.delay(cfg.pollIntervalMs)
        }
        throw IllegalStateException("Yandex Art operation timeout")
    }
}
