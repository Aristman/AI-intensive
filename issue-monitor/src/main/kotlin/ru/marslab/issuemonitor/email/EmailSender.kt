package ru.marslab.issuemonitor.email

import ru.marslab.issuemonitor.config.Config

class EmailSender(private val config: Config) {
    fun send(subject: String, body: String) {
        throw UnsupportedOperationException("Email sending is disabled. Use Telegram notifications.")
    }
}
