package ru.marslab.snaptrace.ai

import ru.marslab.snaptrace.ai.model.FeedItem
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.LinkedBlockingQueue

object InMemoryStore {
    private val jobs = ConcurrentHashMap<String, String>() // jobId -> status
    private val feed = ConcurrentHashMap<String, FeedItem>() // id -> item
    private val queue = LinkedBlockingQueue<String>()
    @Volatile private var worker: Job? = null

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

    fun enqueueJob(jobId: String) {
        queue.offer(jobId)
    }

    fun startWorker(scope: CoroutineScope, processingDelayMs: Long = 50L) {
        if (worker != null) return
        worker = scope.launch(Dispatchers.Default) {
            while (isActive) {
                val jobId = queue.take() // blocking
                jobs[jobId]?.let {
                    jobs[jobId] = "processing"
                    try {
                        // Simulate processing
                        delay(processingDelayMs)
                        val now = Instant.now().toString()
                        val item = FeedItem(
                            id = jobId,
                            imageUrl = "https://example.com/media/$jobId.jpg",
                            text = "generated", // placeholder
                            timestamp = now,
                            location = null
                        )
                        feed[jobId] = item
                        jobs[jobId] = "published"
                    } catch (t: Throwable) {
                        jobs[jobId] = "failed"
                    }
                }
            }
        }
    }
    fun stopWorker() {
        worker?.cancel()
        worker = null
    }
}
