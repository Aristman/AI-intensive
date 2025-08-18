package ru.marslab.issuemonitor.service

import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
import ru.marslab.issuemonitor.config.Config
import ru.marslab.issuemonitor.mcp.McpClient
import ru.marslab.issuemonitor.notify.TelegramNotifier
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

class IssueMonitorService(
    private val config: Config,
    private val mcp: McpClient,
    private val telegram: TelegramNotifier?
) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun run() = coroutineScope {
        var lastCount: Int? = null
        while (this.isActive) {
            try {
                ensureMcp()
                val count = fetchOpenIssuesCount()
                val shouldSend = config.sendAlways || lastCount == null || lastCount != count
                if (shouldSend) {
                    val ts = OffsetDateTime.now(ZoneOffset.UTC).format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)
                    val link = "https://github.com/${config.owner}/${config.repo}/issues"
                    val text = """
                        <b>AI-intensive</b> — открытых задач: <b>${count}</b>
                        Репозиторий: ${config.owner}/${config.repo}
                        Ссылка: ${link}
                        Время (UTC): ${ts}
                    """.trimIndent()
                    telegram?.sendMessage(text)
                    lastCount = count
                }
            } catch (e: Exception) {
                println("[IssueMonitor] Error: ${e.message}")
            }
            val interval = if (config.pollIntervalSeconds > 0) config.pollIntervalSeconds else 3600L
            delay(interval * 1000)
        }
    }

    private suspend fun ensureMcp() {
        mcp.ensureConnected()
        mcp.initialize()
    }

    private suspend fun fetchOpenIssuesCount(): Int {
        val args: JsonObject = buildJsonObject {
            put("owner", config.owner)
            put("repo", config.repo)
        }
        val result = mcp.toolsCall("get_repo", args)
        val obj = result.jsonObject
        val open = obj["open_issues_count"]?.jsonPrimitive?.int
            ?: obj["openIssuesCount"]?.jsonPrimitive?.int
            ?: 0
        return open
    }
}
