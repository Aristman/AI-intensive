package ru.marslab.snaptrace.ai

import io.ktor.server.config.*
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.slf4j.event.Level
import ru.marslab.snaptrace.ai.clients.ClientsFactory
import ru.marslab.snaptrace.ai.clients.GptClientStub
import ru.marslab.snaptrace.ai.clients.RealArtClient
import ru.marslab.snaptrace.ai.clients.RealGptClient
import ru.marslab.snaptrace.ai.logging.LoggingService

class ClientsFactoryEnvTest {

    @Test
    fun `fromConfig returns real clients when flag and creds present`() {
        val config: ApplicationConfig = MapApplicationConfig()
        val logging = LoggingService(Level.INFO)
        val env = mapOf(
            "SNAPTRACE_USE_REAL" to "true",
            "YANDEX_IAM_TOKEN" to "iam-token",
            "YANDEX_FOLDER_ID" to "folder-123"
        )

        val clients = ClientsFactory.fromConfig(config, logging, env)
        assertTrue(clients.useReal)
        assertTrue(clients.art is RealArtClient)
        assertTrue(clients.gpt is RealGptClient)
        assertEquals("folder-123", clients.folderId)
        assertEquals("iam-token", clients.iamToken)
    }

    @Test
    fun `fromConfig returns stubs when folder missing`() {
        val config: ApplicationConfig = MapApplicationConfig()
        val logging = LoggingService(Level.INFO)
        val env = mapOf(
            "SNAPTRACE_USE_REAL" to "true",
            "YANDEX_IAM_TOKEN" to "iam-token"
        )

        val clients = ClientsFactory.fromConfig(config, logging, env)
        assertFalse(clients.useReal)
        assertTrue(clients.gpt is GptClientStub)
    }
}
