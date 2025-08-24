package ru.marslab.snaptrace.ai

import ru.marslab.snaptrace.ai.model.FeedItem
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

object InMemoryStore {
    private val jobs = ConcurrentHashMap<String, String>() // jobId -> status
    private val feed = ConcurrentHashMap<String, FeedItem>() // id -> item

    fun init() {
        // no-op; reserved for future warmup
    }

    fun createJob(jobId: String) {
        jobs[jobId] = "queued"
    }

    fun getJobStatus(jobId: String): String? = jobs[jobId]

    fun setJobStatus(jobId: String, status: String) {
        jobs[jobId] = status
    }

    fun publishItem(item: FeedItem) {
        feed[item.id] = item
        // find job and set published if exists
        jobs[item.id]?.let { _ -> jobs[item.id] = "published" }
    }

    fun listFeed(limit: Int): List<FeedItem> = feed.values
        .sortedByDescending { Instant.parse(it.timestamp) }
        .take(limit)
}
