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
import ru.marslab.snaptrace.ai.clients.ArtClient
import ru.marslab.snaptrace.ai.clients.ArtClientStub
import ru.marslab.snaptrace.ai.clients.GptClient
import ru.marslab.snaptrace.ai.clients.GptClientStub

object InMemoryStore {
    private val jobs = ConcurrentHashMap<String, String>() // jobId -> status
    private val feed = ConcurrentHashMap<String, FeedItem>() // id -> item
    private val queue = LinkedBlockingQueue<String>()
    @Volatile private var worker: Job? = null

    private data class JobMeta(
        val prompt: String,
        val lat: Double?,
        val lon: Double?,
        val deviceId: String?
    )
    private val jobMeta = ConcurrentHashMap<String, JobMeta>()

    @Volatile private var artClient: ArtClient = ArtClientStub()
    @Volatile private var gptClient: GptClient = GptClientStub()

    fun init() {
        // no-op; reserved for future warmup
    }

    fun createJob(jobId: String, prompt: String = "", lat: Double? = null, lon: Double? = null, deviceId: String? = null) {
        jobs[jobId] = "queued"
        if (prompt.isNotEmpty() || lat != null || lon != null || deviceId != null) {
            jobMeta[jobId] = JobMeta(prompt, lat, lon, deviceId)
        }
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
                        val meta = jobMeta[jobId]
                        val prompt = meta?.prompt ?: ""
                        // Stage 1: Art generates image URL
                        val art = artClient.generate(prompt)
                        delay(processingDelayMs)
                        // Stage 2: GPT generates caption
                        val caption = gptClient.caption(art.imageUrl, prompt)
                        val now = Instant.now().toString()
                        val item = FeedItem(
                            id = jobId,
                            imageUrl = art.imageUrl,
                            text = caption,
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

    fun configureProcessors(art: ArtClient, gpt: GptClient) {
        this.artClient = art
        this.gptClient = gpt
    }
}
