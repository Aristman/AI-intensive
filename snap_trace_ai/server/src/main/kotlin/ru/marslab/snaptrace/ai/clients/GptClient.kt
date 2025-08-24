package ru.marslab.snaptrace.ai.clients

interface GptClient {
    suspend fun caption(imageUrl: String, prompt: String): String
}

class GptClientStub : GptClient {
    override suspend fun caption(imageUrl: String, prompt: String): String {
        return "caption: $prompt"
    }
}
