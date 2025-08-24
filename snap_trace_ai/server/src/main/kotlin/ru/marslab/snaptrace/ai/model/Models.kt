package ru.marslab.snaptrace.ai.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CreateJobResponse(
    val jobId: String,
    val status: String = "queued"
)

@Serializable
data class JobStatusResponse(
    val status: String,
    val error: String? = null,
    val result: FeedItem? = null
)

@Serializable
data class FeedResponse(
    val items: List<FeedItem>,
    val nextCursor: String? = null
)

@Serializable
data class FeedItem(
    val id: String,
    val imageUrl: String,
    val text: String,
    val timestamp: String,
    val location: GeoLocation? = null
)

@Serializable
data class GeoLocation(
    val lat: Double,
    val lon: Double,
    val placeName: String? = null
)
