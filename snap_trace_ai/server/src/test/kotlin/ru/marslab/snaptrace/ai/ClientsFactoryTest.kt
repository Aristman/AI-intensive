package ru.marslab.snaptrace.ai

import org.junit.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import ru.marslab.snaptrace.ai.clients.*

class ClientsFactoryTest {
    @Test
    fun returns_stubs_when_flag_missing() {
        val env = mapOf<String, String>()
        val c = ClientsFactory.fromEnv(env)
        assertFalse(c.useReal)
        assertTrue(c.art is ArtClientStub)
        assertTrue(c.gpt is GptClientStub)
    }

    @Test
    fun returns_stubs_when_flag_true_but_tokens_missing() {
        val env = mapOf(
            "SNAPTRACE_USE_REAL" to "true"
        )
        val c = ClientsFactory.fromEnv(env)
        assertFalse(c.useReal)
        assertTrue(c.art is ArtClientStub)
        assertTrue(c.gpt is GptClientStub)
    }

    @Test
    fun returns_real_when_flag_true_and_tokens_present() {
        val env = mapOf(
            "SNAPTRACE_USE_REAL" to "true",
            "YANDEX_IAM_TOKEN" to "token",
            "YANDEX_FOLDER_ID" to "folder"
        )
        val c = ClientsFactory.fromEnv(env)
        assertTrue(c.useReal)
        assertTrue(c.art is RealArtClient)
        assertTrue(c.gpt is RealGptClient)
    }
}
