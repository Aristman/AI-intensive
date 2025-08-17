package ru.marslab.issuemonitor.notify

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import ru.marslab.issuemonitor.config.Config
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit

class TelegramNotifier(private val config: Config) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    fun sendMessage(text: String) {
        require(config.telegramEnabled) { "Telegram notifications disabled" }
        require(config.telegramBotToken.isNotBlank()) { "TELEGRAM_BOT_TOKEN is not set" }
        require(config.telegramChatId.isNotBlank()) { "TELEGRAM_CHAT_ID is not set" }

        val url = "https://api.telegram.org/bot${config.telegramBotToken}/sendMessage"
        val bodyForm = "chat_id=${urlEncode(config.telegramChatId)}&text=${urlEncode(text)}&parse_mode=HTML"
        val req = Request.Builder()
            .url(url)
            .post(bodyForm.toRequestBody("application/x-www-form-urlencoded".toMediaType()))
            .build()

        client.newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                val err = resp.body?.string()
                throw RuntimeException("Telegram sendMessage failed: ${resp.code} ${resp.message} ${err}")
            }
        }
    }

    private fun urlEncode(s: String): String = URLEncoder.encode(s, StandardCharsets.UTF_8)
}
