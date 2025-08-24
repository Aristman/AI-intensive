package ru.marslab.snaptrace.ai.metrics

import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.LongAdder

/**
 * Простейший реестр метрик в памяти.
 * Не зависит от Micrometer/Prometheus, пригоден для unit-тестов.
 */
object Metrics {
    // GPT
    private val gptAttempts = AtomicLong(0)
    private val gptSuccesses = AtomicLong(0)
    private val gptTotalDurationMs = LongAdder()

    // ART (start)
    private val artStartAttempts = AtomicLong(0)
    private val artStartSuccesses = AtomicLong(0)
    private val artStartTotalDurationMs = LongAdder()

    // ART (poll)
    private val artPollAttempts = AtomicLong(0)
    private val artPollSuccesses = AtomicLong(0)
    private val artPollTotalDurationMs = LongAdder()

    fun recordGpt(durationMs: Long, success: Boolean) {
        gptAttempts.incrementAndGet()
        if (success) gptSuccesses.incrementAndGet()
        gptTotalDurationMs.add(durationMs)
    }

    fun recordArtStart(durationMs: Long, success: Boolean) {
        artStartAttempts.incrementAndGet()
        if (success) artStartSuccesses.incrementAndGet()
        artStartTotalDurationMs.add(durationMs)
    }

    fun recordArtPoll(durationMs: Long, success: Boolean) {
        artPollAttempts.incrementAndGet()
        if (success) artPollSuccesses.incrementAndGet()
        artPollTotalDurationMs.add(durationMs)
    }

    // Getters for tests/diagnostics
    fun snapshot(): Snapshot = Snapshot(
        gptAttempts = gptAttempts.get(),
        gptSuccesses = gptSuccesses.get(),
        gptTotalDurationMs = gptTotalDurationMs.sum(),
        artStartAttempts = artStartAttempts.get(),
        artStartSuccesses = artStartSuccesses.get(),
        artStartTotalDurationMs = artStartTotalDurationMs.sum(),
        artPollAttempts = artPollAttempts.get(),
        artPollSuccesses = artPollSuccesses.get(),
        artPollTotalDurationMs = artPollTotalDurationMs.sum(),
    )

    fun reset() {
        gptAttempts.set(0)
        gptSuccesses.set(0)
        gptTotalDurationMs.reset()
        artStartAttempts.set(0)
        artStartSuccesses.set(0)
        artStartTotalDurationMs.reset()
        artPollAttempts.set(0)
        artPollSuccesses.set(0)
        artPollTotalDurationMs.reset()
    }

    data class Snapshot(
        val gptAttempts: Long,
        val gptSuccesses: Long,
        val gptTotalDurationMs: Long,
        val artStartAttempts: Long,
        val artStartSuccesses: Long,
        val artStartTotalDurationMs: Long,
        val artPollAttempts: Long,
        val artPollSuccesses: Long,
        val artPollTotalDurationMs: Long,
    )
}
