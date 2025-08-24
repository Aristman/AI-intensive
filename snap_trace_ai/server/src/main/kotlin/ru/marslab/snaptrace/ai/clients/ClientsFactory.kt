package ru.marslab.snaptrace.ai.clients

import io.ktor.server.config.*
import ru.marslab.snaptrace.ai.logging.LoggingService

data class AiClients(
    val art: ArtClient,
    val gpt: GptClient,
    val useReal: Boolean,
    val iamToken: String?,
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
    private const val ENV_FOLDER = "YANDEX_FOLDER_ID"
    private const val ENV_USE_REAL = "SNAPTRACE_USE_REAL"

    fun fromEnv(env: Map<String, String> = System.getenv()): AiClients {
        val iam = env[ENV_IAM]?.takeIf { it.isNotBlank() }
        val folder = env[ENV_FOLDER]?.takeIf { it.isNotBlank() }
        val useRealFlag = env[ENV_USE_REAL]?.lowercase()?.let { it == "1" || it == "true" || it == "yes" } ?: false
        val canUseReal = useRealFlag && iam != null && folder != null
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
                art = RealArtClient(iam!!, folder!!, artCfg),
                gpt = RealGptClient(iam, folder, gptCfg),
                useReal = true,
                iamToken = iam,
                folderId = folder,
            )
        } else {
            AiClients(
                art = ArtClientStub(),
                gpt = GptClientStub(),
                useReal = false,
                iamToken = iam,
                folderId = folder,
            )
        }
    }

    fun fromConfig(config: ApplicationConfig, logging: LoggingService, env: Map<String, String> = System.getenv()): AiClients {
        val log = logging.getLogger(ClientsFactory::class.java)
        val iam = env[ENV_IAM]?.takeIf { it.isNotBlank() }
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

        val canUseReal = useRealFlag && iam != null && folder != null
        return if (canUseReal) {
            log.info("AI clients: using REAL Yandex clients (flag={}, folderId set={})", useRealFlag, folder != null)
            AiClients(
                art = RealArtClient(iam!!, folder!!, artCfg, logger = logging.getLogger(RealArtClient::class.java)),
                gpt = RealGptClient(iam, folder, gptCfg, logger = logging.getLogger(RealGptClient::class.java)),
                useReal = true,
                iamToken = iam,
                folderId = folder,
            )
        } else {
            log.info("AI clients: using STUB clients (flag={}, iam set={}, folder set={})", useRealFlag, iam != null, folder != null)
            AiClients(
                art = ArtClientStub(),
                gpt = GptClientStub(),
                useReal = false,
                iamToken = iam,
                folderId = folder,
            )
        }
    }
}
