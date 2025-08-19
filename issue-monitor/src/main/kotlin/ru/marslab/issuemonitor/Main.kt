package ru.marslab.issuemonitor

import kotlinx.coroutines.runBlocking
import ru.marslab.issuemonitor.config.Config
import ru.marslab.issuemonitor.mcp.McpClient
import ru.marslab.issuemonitor.notify.TelegramNotifier
import ru.marslab.issuemonitor.service.IssueMonitorService

fun main(vararg args: String) = runBlocking {
    var config = Config.load()

    // CLI override for interval in seconds: --interval=180, --interval 180, or first positional int
    val intervalArg: Long? = runCatching {
        var value: Long? = null
        val list = args.toList()
        for (i in list.indices) {
            val a = list[i]
            if (a.startsWith("--interval=")) {
                value = a.substringAfter("=").toLong()
                break
            }
            if (a == "--interval" && i + 1 < list.size) {
                value = list[i + 1].toLong()
                break
            }
        }
        // if not found, try first positional numeric
        if (value == null && list.isNotEmpty()) {
            val first = list.first()
            if (!first.startsWith("--")) {
                value = first.toLong()
            }
        }
        value
    }.getOrNull()

    if (intervalArg != null && intervalArg > 0) {
        config = config.copy(pollIntervalSeconds = intervalArg)
    }

    println("[IssueMonitor] Starting with repo ${config.owner}/${config.repo}, MCP=${config.mcpUrl}, interval=${config.pollIntervalSeconds}s")
    val mcp = McpClient(config.mcpUrl)
    val telegram = if (config.telegramEnabled) TelegramNotifier(config, mcp) else null

    val service = IssueMonitorService(config, mcp, telegram)

    Runtime.getRuntime().addShutdownHook(Thread {
        println("[IssueMonitor] Shutting down...")
        mcp.close()
    })

    service.run()
}
