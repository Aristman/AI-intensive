package ru.marslab.snaptrace.ai

import ru.marslab.snaptrace.ai.model.FeedItem
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.CancellationException
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
import org.slf4j.Logger
import org.slf4j.LoggerFactory
import ru.marslab.snaptrace.ai.logging.LoggingService

object InMemoryStore {
    
    private val jobs = ConcurrentHashMap<String, String>() // jobId -> status
    private val feed = ConcurrentHashMap<String, FeedItem>() // id -> item
    private val queue = LinkedBlockingQueue<String>()
    @Volatile private var worker: Job? = null
    @Volatile private var log: Logger = LoggerFactory.getLogger(InMemoryStore::class.java)

    private data class JobMeta(
        val prompt: String,
        val lat: Double?,
        val lon: Double?,
        val deviceId: String?
    )
    private val jobMeta = ConcurrentHashMap<String, JobMeta>()

    private data class JobRuntime(
        val art: ArtClient,
        val gpt: GptClient
    )
    private val jobRuntime = ConcurrentHashMap<String, JobRuntime>()

    @Volatile private var artClient: ArtClient = ArtClientStub()
    @Volatile private var gptClient: GptClient = GptClientStub()

    fun init() {
        log.debug("InMemoryStore initialized")
    }

    fun configureLogger(logging: LoggingService) {
        this.log = logging.getLogger(InMemoryStore::class.java)
        log.debug("Logger configured for InMemoryStore, level={}", logging.level)
    }

    fun createJob(jobId: String, prompt: String = "", lat: Double? = null, lon: Double? = null, deviceId: String? = null) {
        jobs[jobId] = "queued"
        log.info("Job created: jobId={}, hasMeta={}", jobId, (prompt.isNotEmpty() || lat != null || lon != null || deviceId != null))
        if (prompt.isNotEmpty() || lat != null || lon != null || deviceId != null) {
            jobMeta[jobId] = JobMeta(prompt, lat, lon, deviceId)
            log.debug("Job meta saved: jobId={}, promptLen={}, lat={}, lon={}, deviceId=set?{}",
                jobId, prompt.length, lat, lon, deviceId != null)
        }
    }

    fun getJobStatus(jobId: String): String? = jobs[jobId]

    fun setJobStatus(jobId: String, status: String) {
        jobs[jobId] = status
        log.debug("Job status set: jobId={}, status={}", jobId, status)
    }

    fun publishItem(item: FeedItem) {
        feed[item.id] = item
        // find job and set published if exists
        jobs[item.id]?.let { _ -> jobs[item.id] = "published" }
        log.info("Feed item published: id={}, textLen={}", item.id, item.text.length)
    }

    fun listFeed(limit: Int): List<FeedItem> = feed.values
        .sortedByDescending { Instant.parse(it.timestamp) }
        .take(limit)

    fun enqueueJob(jobId: String) {
        // Snapshot current processors for this job to avoid race with reconfiguration
        jobRuntime[jobId] = JobRuntime(artClient, gptClient)
        queue.offer(jobId)
        log.debug("Job enqueued: jobId={}", jobId)
    }

    fun startWorker(scope: CoroutineScope, processingDelayMs: Long = 50L) {
        if (worker?.isActive == true) return
        log.info("Worker starting with delay={}ms", processingDelayMs)
        worker = scope.launch(Dispatchers.Default) {
            while (isActive) {
                val jobId = queue.take() // blocking
                jobs[jobId]?.let {
                    jobs[jobId] = "processing"
                    log.info("Processing started: jobId={}", jobId)
                    var requeued = false
                    try {
                        // Simulate processing
                        val meta = jobMeta[jobId]
                        val prompt = meta?.prompt ?: ""
                        log.debug("Stage 1: calling ArtClient.generate jobId={}, promptLen={}", jobId, prompt.length)
                        // Stage 1: Art generates image URL
                        val rt = jobRuntime[jobId] ?: JobRuntime(artClient, gptClient)
                        val art = rt.art.generate(prompt)
                        delay(processingDelayMs)
                        log.debug("Stage 2: calling GptClient.caption jobId={}", jobId)
                        // Stage 2: GPT generates caption
                        val caption = rt.gpt.caption(art.imageUrl, prompt)
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
                        log.info("Job published: jobId={}, captionLen={}", jobId, caption.length)
                    } catch (ce: CancellationException) {
                        // Distinguish between worker cancellation vs. inner timeouts (which are also CancellationException)
                        if (!isActive) {
                            // Worker itself was cancelled — don't fail the job; re-queue
                            jobs[jobId] = "queued"
                            log.info("Worker cancelled during processing; re-queue jobId={}", jobId)
                            queue.offer(jobId)
                            requeued = true
                        } else {
                            // Timeout or child cancellation inside processing — treat as failure
                            jobs[jobId] = "failed"
                            log.warn("Job failed (cancellation/timeout): jobId={}, reason=", jobId, ce)
                        }
                    } catch (t: Throwable) {
                        jobs[jobId] = "failed"
                        log.warn("Job failed: jobId={}, reason=", jobId, t)
                    } finally {
                        if (!requeued) {
                            jobRuntime.remove(jobId)
                        }
                    }
                }
            }
        }
    }
    fun stopWorker() {
        worker?.cancel()
        worker = null
        log.info("Worker stopped")
    }

    fun configureProcessors(art: ArtClient, gpt: GptClient) {
        this.artClient = art
        this.gptClient = gpt
        log.info("Processors configured: art={}, gpt={}", art.javaClass.simpleName, gpt.javaClass.simpleName)
    }
}
