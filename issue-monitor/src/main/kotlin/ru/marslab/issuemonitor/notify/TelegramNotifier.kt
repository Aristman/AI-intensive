package ru.marslab.issuemonitor.notify

import ru.marslab.issuemonitor.config.Config
import ru.marslab.issuemonitor.mcp.McpClient
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class TelegramNotifier(private val config: Config, private val mcp: McpClient) {

    suspend fun sendMessage(text: String) {
        require(config.telegramEnabled) { "Telegram notifications disabled" }
        // If TELEGRAM_DEFAULT_CHAT_ID is set on server, chat_id may be omitted
        val args = buildJsonObject {
            if (config.telegramChatId.isNotBlank()) put("chat_id", config.telegramChatId)
            put("text", text)
            put("parse_mode", "HTML")
            put("disable_web_page_preview", true)
        }
        // Use MCP server tool
        mcp.toolsCall("tg_send_message", args)
    }
}
