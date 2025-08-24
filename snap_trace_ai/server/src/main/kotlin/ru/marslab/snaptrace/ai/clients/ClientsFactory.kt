package ru.marslab.snaptrace.ai.clients

import io.github.cdimascio.dotenv.Dotenv
import io.ktor.server.config.*
import ru.marslab.snaptrace.ai.logging.LoggingService

data class AiClients(
    val art: ArtClient,
    val gpt: GptClient,
    val useReal: Boolean,
    val iamToken: String?,
    val apiKey: String,
    val folderId: String?,
)

data class GptConfig(
    val endpoint: String,
    val model: String,
    val temperature: Double,
    val maxTokens: Int,
    val systemText: String,
    val timeoutMs: Long,
    val retryMaxAttempts: Int = 3,
    val retryBaseDelayMs: Long = 200,
    val retryMaxDelayMs: Long = 2000,
)

data class ArtConfig(
    val endpoint: String,
    val operationsEndpoint: String,
    val model: String,
    val seed: Long,
    val aspectWidth: Int,
    val aspectHeight: Int,
    val pollIntervalMs: Long,
    val pollTimeoutMs: Long,
    val timeoutMs: Long,
    val retryMaxAttempts: Int = 3,
    val retryBaseDelayMs: Long = 200,
    val retryMaxDelayMs: Long = 2000,
)

object ClientsFactory {
    private const val ENV_IAM = "YANDEX_IAM_TOKEN"
    private const val ENV_API_KEY = "YANDEX_API_KEY"
    private const val ENV_FOLDER = "YANDEX_FOLDER_ID"
    private const val ENV_USE_REAL = "SNAPTRACE_USE_REAL"

    /**
     * Loads environment variables by merging System.getenv() with values from a local .env file (if present).
     * Values from .env override System environment variables.
     */
    private fun loadEnvWithDotenv(): Map<String, String> {
        val merged = System.getenv().toMutableMap()
        // Try load from current working directory
        runCatching {
            val dot1 = Dotenv.configure()
                .ignoreIfMalformed()
                .ignoreIfMissing()
                .load()
            dot1.entries().forEach { e -> merged[e.key] = e.value }
        }
        // Try load from server module directory (works when started from repo root)
        runCatching {
            val dot2 = Dotenv.configure()
                .directory("snap_trace_ai/server")
                .ignoreIfMalformed()
                .ignoreIfMissing()
                .load()
            dot2.entries().forEach { e -> merged[e.key] = e.value }
        }
        return merged
    }

    fun fromEnv(env: Map<String, String> = loadEnvWithDotenv()): AiClients {
        val iam = env[ENV_IAM]?.takeIf { it.isNotBlank() }
        val apiKey = env[ENV_API_KEY]?.takeIf { it.isNotBlank() }.orEmpty()
        val folder = env[ENV_FOLDER]?.takeIf { it.isNotBlank() }
        val useRealFlag = env[ENV_USE_REAL]?.lowercase()?.let { it == "1" || it == "true" || it == "yes" } ?: false
        val canUseReal = useRealFlag && folder != null && (iam != null || apiKey.isNotBlank())
        return if (canUseReal) {
            // Defaults if config isn't available
            val gptCfg = GptConfig(
                endpoint = "https://llm.api.cloud.yandex.net/foundationModels/v1/completion",
                model = "yandexgpt",
                temperature = 0.6,
                maxTokens = 2000,
                systemText = "Сгенерируй лаконичную подпись к изображению на основе подсказки",
                timeoutMs = 15000,
                retryMaxAttempts = 3,
                retryBaseDelayMs = 200,
                retryMaxDelayMs = 2000,
            )
            val artCfg = ArtConfig(
                endpoint = "https://llm.api.cloud.yandex.net/foundationModels/v1/imageGenerationAsync",
                operationsEndpoint = "https://llm.api.cloud.yandex.net/operations",
                model = "yandex-art/latest",
                seed = 1863,
                aspectWidth = 2,
                aspectHeight = 1,
                pollIntervalMs = 1000,
                pollTimeoutMs = 60000,
                timeoutMs = 15000,
                retryMaxAttempts = 3,
                retryBaseDelayMs = 200,
                retryMaxDelayMs = 2000,
            )
            AiClients(
                art = RealArtClient(iamToken = iam.orEmpty(), apiKey = apiKey, folderId = folder!!, cfg = artCfg),
                gpt = RealGptClient(iamToken = iam.orEmpty(), apiKey = apiKey, folderId = folder!!, cfg = gptCfg),
                useReal = true,
                iamToken = iam,
                apiKey = apiKey,
                folderId = folder,
            )
        } else {
            AiClients(
                art = ArtClientStub(),
                gpt = GptClientStub(),
                useReal = false,
                iamToken = iam,
                apiKey = apiKey,
                folderId = folder,
            )
        }
    }

    fun fromConfig(config: ApplicationConfig, logging: LoggingService, env: Map<String, String> = loadEnvWithDotenv()): AiClients {
        val log = logging.getLogger(ClientsFactory::class.java)
        // Avoid leaking secrets into logs; log only keys
        runCatching { log.info("env keys={}", env.keys.joinToString(",")) }
        val iam = env[ENV_IAM]?.takeIf { it.isNotBlank() }.orEmpty()
        val apiKey = env[ENV_API_KEY]?.takeIf { it.isNotBlank() }.orEmpty()
        val folder = env[ENV_FOLDER]?.takeIf { it.isNotBlank() }
        val useRealFlag = env[ENV_USE_REAL]?.lowercase()?.let { it == "1" || it == "true" || it == "yes" } ?: false
        fun get(path: String, def: String) = config.propertyOrNull(path)?.getString() ?: def
        fun getInt(path: String, def: Int) = config.propertyOrNull(path)?.getString()?.toIntOrNull() ?: def
        fun getLong(path: String, def: Long) = config.propertyOrNull(path)?.getString()?.toLongOrNull() ?: def
        fun getDouble(path: String, def: Double) = config.propertyOrNull(path)?.getString()?.toDoubleOrNull() ?: def

        val gptCfg = GptConfig(
            endpoint = get("snapTrace.yc.gpt.endpoint", "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"),
            model = get("snapTrace.yc.gpt.model", "yandexgpt"),
            temperature = getDouble("snapTrace.yc.gpt.temperature", 0.6),
            maxTokens = getInt("snapTrace.yc.gpt.maxTokens", 2000),
            systemText = get("snapTrace.yc.gpt.systemText", "Сгенерируй лаконичную подпись к изображению на основе подсказки"),
            timeoutMs = getLong("snapTrace.httpClient.timeoutMs", 15000),
            retryMaxAttempts = getInt("snapTrace.httpClient.retry.maxAttempts", 3),
            retryBaseDelayMs = getLong("snapTrace.httpClient.retry.baseDelayMs", 200),
            retryMaxDelayMs = getLong("snapTrace.httpClient.retry.maxDelayMs", 2000),
        )
        val artCfg = ArtConfig(
            endpoint = get("snapTrace.yc.art.endpoint", "https://llm.api.cloud.yandex.net/foundationModels/v1/imageGenerationAsync"),
            operationsEndpoint = get("snapTrace.yc.art.poll.operationsEndpoint", "https://llm.api.cloud.yandex.net/operations"),
            model = get("snapTrace.yc.art.model", "yandex-art/latest"),
            seed = getLong("snapTrace.yc.art.seed", 1863),
            aspectWidth = getInt("snapTrace.yc.art.aspect.widthRatio", 2),
            aspectHeight = getInt("snapTrace.yc.art.aspect.heightRatio", 1),
            pollIntervalMs = getLong("snapTrace.yc.art.poll.intervalMs", 1000),
            pollTimeoutMs = getLong("snapTrace.yc.art.poll.timeoutMs", 60000),
            timeoutMs = getLong("snapTrace.httpClient.timeoutMs", 15000),
            retryMaxAttempts = getInt("snapTrace.httpClient.retry.maxAttempts", 3),
            retryBaseDelayMs = getLong("snapTrace.httpClient.retry.baseDelayMs", 200),
            retryMaxDelayMs = getLong("snapTrace.httpClient.retry.maxDelayMs", 2000),
        )

        val canUseReal = useRealFlag && folder != null && (iam != null || apiKey.isNotBlank())
        return if (canUseReal) {
            log.info("AI clients: using REAL Yandex clients (flag={}, folderId set={})", useRealFlag, folder)
            AiClients(
                art = RealArtClient(
                    iamToken = iam.orEmpty(),
                    apiKey = apiKey,
                    folderId = folder!!,
                    cfg = artCfg,
                    logger = logging.getLogger(RealArtClient::class.java)
                ),
                gpt = RealGptClient(
                    iamToken = iam.orEmpty(),
                    apiKey = apiKey,
                    folderId = folder!!,
                    cfg = gptCfg,
                    logger = logging.getLogger(RealGptClient::class.java)
                ),
                useReal = true,
                iamToken = iam,
                apiKey = apiKey,
                folderId = folder,
            )
        } else {
            log.info("AI clients: using STUB clients (flag={}, iam set={}, folder set={})", useRealFlag, iam, folder)
            AiClients(
                art = ArtClientStub(),
                gpt = GptClientStub(),
                useReal = false,
                iamToken = iam,
                apiKey = apiKey,
                folderId = folder,
            )
        }
    }
}
