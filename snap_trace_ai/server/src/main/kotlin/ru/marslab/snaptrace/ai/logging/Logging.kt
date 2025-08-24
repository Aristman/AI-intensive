package ru.marslab.snaptrace.ai.logging

import ch.qos.logback.classic.Level as LogbackLevel
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.request.path
import io.ktor.server.request.httpMethod
import org.slf4j.Logger
import org.slf4j.LoggerFactory
import org.slf4j.event.Level as Slf4jLevel

/**
 * Центральная точка настройки логирования.
 * - Выставляет уровень корневого логгера Logback из application.conf (snapTrace.logging.level)
 * - Инсталлирует Ktor CallLogging с MDC полями method/path и фильтрацией /health
 * - Предоставляет [LoggingService] для DI
 */
object Logging {
    fun install(app: Application): LoggingService {
        val levelStr = app.environment.config.propertyOrNull("snapTrace.logging.level")?.getString()?.uppercase()
            ?: "INFO"
        val ktorLevel = mapToSlf4j(levelStr)
        val logbackLevel = mapToLogback(levelStr)

        // Программно устанавливаем уровень корневого логгера
        (LoggerFactory.getLogger(Logger.ROOT_LOGGER_NAME) as ch.qos.logback.classic.Logger).level = logbackLevel

        // Ktor CallLogging
        app.install(CallLogging) {
            level = ktorLevel
            filter { call -> !call.request.path().startsWith("/health") }
            mdc("method") { call -> call.request.httpMethod.value }
            mdc("path") { call -> call.request.path() }
        }

        return LoggingService(ktorLevel)
    }

    internal fun mapToSlf4j(level: String): Slf4jLevel = when (level) {
        "TRACE" -> Slf4jLevel.TRACE
        "DEBUG" -> Slf4jLevel.DEBUG
        "INFO" -> Slf4jLevel.INFO
        "WARN", "WARNING" -> Slf4jLevel.WARN
        "ERROR" -> Slf4jLevel.ERROR
        else -> Slf4jLevel.INFO
    }

    internal fun mapToLogback(level: String): LogbackLevel = when (level) {
        "TRACE" -> LogbackLevel.TRACE
        "DEBUG" -> LogbackLevel.DEBUG
        "INFO" -> LogbackLevel.INFO
        "WARN", "WARNING" -> LogbackLevel.WARN
        "ERROR" -> LogbackLevel.ERROR
        else -> LogbackLevel.INFO
    }
}

class LoggingService(val level: Slf4jLevel) {
    fun getLogger(forClass: Class<*>): Logger = LoggerFactory.getLogger(forClass)
}
