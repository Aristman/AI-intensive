package ru.marslab.issuemonitor

import kotlinx.coroutines.runBlocking
import ru.marslab.issuemonitor.config.Config
import ru.marslab.issuemonitor.mcp.McpClient
import ru.marslab.issuemonitor.notify.TelegramNotifier
import ru.marslab.issuemonitor.service.IssueMonitorService

fun main() = runBlocking {
    val config = Config.load()

    println("[IssueMonitor] Starting with repo ${config.owner}/${config.repo}, MCP=${config.mcpUrl}")
    val mcp = McpClient(config.mcpUrl)
    val telegram = if (config.telegramEnabled) TelegramNotifier(config) else null

    val service = IssueMonitorService(config, mcp, telegram)

    Runtime.getRuntime().addShutdownHook(Thread {
        println("[IssueMonitor] Shutting down...")
        mcp.close()
    })

    service.run()
}
