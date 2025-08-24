package ru.marslab.snaptrace.ai.logging

import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.slf4j.event.Level as Slf4jLevel
import ch.qos.logback.classic.Level as LogbackLevel

class LoggingTest {
    @Test
    fun `mapToSlf4j maps strings correctly`() {
        assertEquals(Slf4jLevel.TRACE, Logging.mapToSlf4j("TRACE"))
        assertEquals(Slf4jLevel.DEBUG, Logging.mapToSlf4j("DEBUG"))
        assertEquals(Slf4jLevel.INFO, Logging.mapToSlf4j("INFO"))
        assertEquals(Slf4jLevel.WARN, Logging.mapToSlf4j("WARN"))
        assertEquals(Slf4jLevel.WARN, Logging.mapToSlf4j("WARNING"))
        assertEquals(Slf4jLevel.ERROR, Logging.mapToSlf4j("ERROR"))
        // default fallback
        assertEquals(Slf4jLevel.INFO, Logging.mapToSlf4j("UNKNOWN"))
    }

    @Test
    fun `mapToLogback maps strings correctly`() {
        assertEquals(LogbackLevel.TRACE, Logging.mapToLogback("TRACE"))
        assertEquals(LogbackLevel.DEBUG, Logging.mapToLogback("DEBUG"))
        assertEquals(LogbackLevel.INFO, Logging.mapToLogback("INFO"))
        assertEquals(LogbackLevel.WARN, Logging.mapToLogback("WARN"))
        assertEquals(LogbackLevel.WARN, Logging.mapToLogback("WARNING"))
        assertEquals(LogbackLevel.ERROR, Logging.mapToLogback("ERROR"))
        // default fallback
        assertEquals(LogbackLevel.INFO, Logging.mapToLogback("UNKNOWN"))
    }

    @Test
    fun `LoggingService returns class based logger`() {
        val svc = LoggingService(Slf4jLevel.INFO)
        val logger = svc.getLogger(LoggingTest::class.java)
        assertNotNull(logger)
    }
}
