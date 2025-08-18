package ru.marslab.issuemonitor.service

import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
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
        while (this.isActive) {
            try {
                ensureMcp()
                val count = fetchOpenIssuesCount()
                val issuesList = fetchLatestIssues(limit = config.issuesListLimit)
                val ts = OffsetDateTime.now(ZoneOffset.UTC).format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)
                val link = "https://github.com/${config.owner}/${config.repo}/issues"
                val issuesHtml = if (issuesList.isEmpty()) "<i>Нет открытых задач</i>" else issuesList.joinToString("\n") { (title, url, number) ->
                    val safeTitle = title.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                    "• <a href=\"${url}\">#${number} ${safeTitle}</a>"
                }
                val text = """
                    <b>${config.owner}/${config.repo}</b>
                    Открытых задач: <b>${count}</b>
                    Список последних:
                    ${issuesHtml}
                    Ссылка: ${link}
                    Время (UTC): ${ts}
                """.trimIndent()
                telegram?.sendMessage(text)
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
        val repoObj = mcp.toolsCall("get_repo", args).jsonObject
        val open = repoObj["open_issues_count"]?.jsonPrimitive?.int
            ?: repoObj["openIssuesCount"]?.jsonPrimitive?.int
            ?: 0
        return open
    }

    private suspend fun fetchLatestIssues(limit: Int = 5): List<Triple<String, String, Int>> {
        val args: JsonObject = buildJsonObject {
            put("owner", config.owner)
            put("repo", config.repo)
            put("state", "open")
            put("per_page", limit)
            put("page", 1)
        }
        val arr = mcp.toolsCall("list_issues", args).jsonArray
        return arr.take(limit).mapNotNull { el ->
            val o = el.jsonObject
            val title = o["title"]?.jsonPrimitive?.content ?: return@mapNotNull null
            val url = o["html_url"]?.jsonPrimitive?.content ?: o["url"]?.jsonPrimitive?.content ?: return@mapNotNull null
            val number = o["number"]?.jsonPrimitive?.int ?: 0
            Triple(title, url, number)
        }
    }
}
