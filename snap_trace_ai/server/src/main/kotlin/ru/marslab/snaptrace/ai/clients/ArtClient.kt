package ru.marslab.snaptrace.ai.clients

interface ArtClient {
    suspend fun generate(prompt: String): ArtResult
}

data class ArtResult(
    val imageUrl: String
)

class ArtClientStub : ArtClient {
    override suspend fun generate(prompt: String): ArtResult {
        // Return a deterministic placeholder URL for testing/MVP
        val safe = prompt.lowercase().replace("\n", " ").take(16).ifEmpty { "img" }
        return ArtResult(imageUrl = "https://example.com/art/$safe.jpg")
    }
}
