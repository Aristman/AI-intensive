package ru.marslab.snaptrace.ai

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.server.testing.*
import io.ktor.server.config.*
import kotlin.test.Test
import kotlin.test.assertEquals

class HealthRouteTest {
    @Test
    fun health_ok() = testApplication {
        environment {
            // Отключаем автозапуск воркера для изоляции тестов
            config = MapApplicationConfig(
                "snapTrace.worker.autostart" to "false"
            )
        }
        application { serverModule() }

        val response = client.get("/health")
        assertEquals(HttpStatusCode.OK, response.status)
        val body = response.bodyAsText()
        // very lenient check
        assert(body.contains("ok"))
    }
}
