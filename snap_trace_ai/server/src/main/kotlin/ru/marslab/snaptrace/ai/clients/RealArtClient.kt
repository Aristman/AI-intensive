package ru.marslab.snaptrace.ai.clients

import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.ClientRequestException
import io.ktor.client.plugins.ServerResponseException
import io.ktor.client.plugins.HttpRequestTimeoutException
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
import kotlinx.coroutines.delay
import org.slf4j.LoggerFactory
import org.slf4j.Logger
import ru.marslab.snaptrace.ai.metrics.Metrics

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
    logger: Logger? = null,
) : ArtClient {

    private val log = logger ?: LoggerFactory.getLogger(RealArtClient::class.java)

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

        val startStartedAt = System.currentTimeMillis()
        val start: StartOpResponse = try {
            val res = withRetry<StartOpResponse>(
                actionName = "art.start",
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
                    code in 200..299 -> httpResp.body<StartOpResponse>()
                    code == 429 -> throw ClientRequestException(httpResp, "Too Many Requests")
                    code in 500..599 -> throw ServerResponseException(httpResp, "Server error ${httpResp.status}")
                    else -> throw ClientRequestException(httpResp, "HTTP ${httpResp.status}")
                }
            }
            Metrics.recordArtStart(System.currentTimeMillis() - startStartedAt, success = true)
            res
        } catch (e: Exception) {
            Metrics.recordArtStart(System.currentTimeMillis() - startStartedAt, success = false)
            log.warn("Art start failed after retries: ${e.message}")
            throw e
        }

        val opId = start.id
        val startedAt = System.currentTimeMillis()
        while (System.currentTimeMillis() - startedAt < cfg.pollTimeoutMs) {
            val op: OperationGetResponse = try {
                var attempt = 1
                var nextDelay = cfg.retryBaseDelayMs.coerceAtLeast(0)
                var result: OperationGetResponse? = null
                while (true) {
                    val pollAttemptStarted = System.currentTimeMillis()
                    try {
                        val httpResp = client.get("${cfg.operationsEndpoint}/$opId") {
                            headers { append("Authorization", "Bearer $iamToken") }
                        }
                        val code = httpResp.status.value
                        val res = when {
                            code in 200..299 -> httpResp.body<OperationGetResponse>()
                            code == 429 -> throw ClientRequestException(httpResp, "Too Many Requests")
                            code in 500..599 -> throw ServerResponseException(httpResp, "Server error ${httpResp.status}")
                            else -> throw ClientRequestException(httpResp, "HTTP ${httpResp.status}")
                        }
                        Metrics.recordArtPoll(System.currentTimeMillis() - pollAttemptStarted, success = true)
                        result = res
                        break
                    } catch (e: Exception) {
                        Metrics.recordArtPoll(System.currentTimeMillis() - pollAttemptStarted, success = false)
                        val retriable = isRetriable(e)
                        if (!retriable || attempt >= cfg.retryMaxAttempts) {
                            log.debug("art.poll attempt=$attempt failed, retriable=$retriable; giving up: ${e.message}")
                            throw e
                        }
                        log.debug("art.poll attempt=$attempt failed; retrying in ${nextDelay}ms: ${e.message}")
                        delay(nextDelay)
                        attempt += 1
                        nextDelay = (nextDelay * 2).coerceAtMost(cfg.retryMaxDelayMs)
                    }
                }
                result!!
            } catch (e: Exception) {
                log.debug("Art poll failed (will continue if time remains): ${e.message}")
                // if poll attempt fails even after retries, wait and try next loop until timeout
                delay(cfg.pollIntervalMs)
                continue
            }
            if (op.done) {
                val b64 = op.response?.image
                if (!b64.isNullOrBlank()) {
                    val dataUrl = "data:image/jpeg;base64,$b64"
                    return ArtResult(imageUrl = dataUrl)
                } else {
                    throw IllegalStateException("Yandex Art operation done but image is empty")
                }
            }
            delay(cfg.pollIntervalMs)
        }
        throw IllegalStateException("Yandex Art operation timeout")
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
            is ServerResponseException -> true
            is ClientRequestException -> {
                try { e.response.status.value == 429 } catch (_: Throwable) { false }
            }
            else -> false
        }
    }
}
