package ru.marslab.issuemonitor.config

import java.io.File
import java.io.FileInputStream
import java.util.Properties

data class Config(
    val mcpUrl: String = env("MCP_WS_URL") ?: "ws://localhost:3001",
    val owner: String = env("GITHUB_OWNER") ?: "Aristman",
    val repo: String = env("GITHUB_REPO") ?: "AI-intensive",
    val pollIntervalSeconds: Long = (env("POLL_INTERVAL_SECONDS")?.toLongOrNull() ?: 3600L),
    val sendAlways: Boolean = env("SEND_ALWAYS")?.toBooleanStrictOrNull() ?: false,
    val issuesListLimit: Int = env("ISSUES_LIST_LIMIT")?.toIntOrNull() ?: 5,

    // Telegram
    val telegramEnabled: Boolean = env("TELEGRAM_ENABLED")?.toBooleanStrictOrNull() ?: true,
    val telegramBotToken: String = env("TELEGRAM_BOT_TOKEN") ?: "",
    val telegramChatId: String = env("TELEGRAM_CHAT_ID") ?: "",

    val smtpHost: String = env("SMTP_HOST") ?: "smtp.gmail.com",
    val smtpPort: Int = env("SMTP_PORT")?.toIntOrNull() ?: 587,
    val smtpUsername: String = env("SMTP_USERNAME") ?: "",
    val smtpPassword: String = env("SMTP_PASSWORD") ?: "",
    val smtpFrom: String = env("SMTP_FROM") ?: env("SMTP_USERNAME") ?: "",
    val smtpTo: String = env("SMTP_TO") ?: "aristov775@gmail.com",
    val smtpStartTls: Boolean = env("SMTP_STARTTLS")?.toBooleanStrictOrNull() ?: true
) {
    companion object {
        private fun env(key: String): String? = System.getenv(key)

        fun load(): Config {
            // Optional fallback to config.properties
            val path = System.getenv("CONFIG_FILE") ?: "config.properties"
            val props = Properties()
            val file = File(path)
            if (file.exists()) {
                FileInputStream(file).use { props.load(it) }
            }

            // Optional dotenv: DOTENV_FILE, issue-monitor/.env, .env
            val dotenv = loadDotEnv(
                listOf(
                    System.getenv("DOTENV_FILE"),
                    "issue-monitor/.env",
                    ".env"
                ).filterNotNull()
            )

            fun p(k: String) = System.getenv(k) ?: dotenv[k] ?: props.getProperty(k)

            return Config(
                mcpUrl = p("MCP_WS_URL") ?: "ws://localhost:3001",
                owner = p("GITHUB_OWNER") ?: "aristman",
                repo = p("GITHUB_REPO") ?: "AI-intensive",
                pollIntervalSeconds = (p("POLL_INTERVAL_SECONDS")?.toLongOrNull() ?: 3600L),
                sendAlways = p("SEND_ALWAYS")?.toBooleanStrictOrNull() ?: false,
                issuesListLimit = p("ISSUES_LIST_LIMIT")?.toIntOrNull() ?: 5,
                telegramEnabled = p("TELEGRAM_ENABLED")?.toBooleanStrictOrNull() ?: true,
                telegramBotToken = p("TELEGRAM_BOT_TOKEN") ?: "",
                telegramChatId = p("TELEGRAM_CHAT_ID") ?: "",
                smtpHost = p("SMTP_HOST") ?: "smtp.gmail.com",
                smtpPort = p("SMTP_PORT")?.toIntOrNull() ?: 587,
                smtpUsername = p("SMTP_USERNAME") ?: "",
                smtpPassword = p("SMTP_PASSWORD") ?: "",
                smtpFrom = p("SMTP_FROM") ?: (p("SMTP_USERNAME") ?: ""),
                smtpTo = p("SMTP_TO") ?: "aristov775@gmail.com",
                smtpStartTls = p("SMTP_STARTTLS")?.toBooleanStrictOrNull() ?: true,
            )
        }

        private fun loadDotEnv(paths: List<String>): Map<String, String> {
            val map = linkedMapOf<String, String>()
            for (p in paths) {
                val f = File(p)
                if (!f.exists() || !f.isFile) continue
                f.readLines().forEach { raw ->
                    val line = raw.trim()
                    if (line.isEmpty() || line.startsWith("#")) return@forEach
                    val idx = line.indexOf('=')
                    if (idx <= 0) return@forEach
                    val key = line.substring(0, idx).trim()
                    val value = line.substring(idx + 1).trim()
                    if (key.isNotEmpty()) map[key] = value
                }
            }
            return map
        }
    }
}
