package ru.marslab.issuemonitor.mcp

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import okhttp3.*
import okio.ByteString
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit

class McpClient(private val url: String) : WebSocketListener() {
    private val client = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .build()

    private var webSocket: WebSocket? = null

    private val json = Json { ignoreUnknownKeys = true }
    private val pending = ConcurrentHashMap<Long, CompletableDeferred<JsonObject>>()
    private val idMutex = Mutex()
    private var lastId = 0L

    suspend fun connect() {
        if (webSocket != null) return
        val request = Request.Builder().url(url).build()
        webSocket = client.newWebSocket(request, this)
    }

    suspend fun ensureConnected() {
        if (webSocket == null) connect()
    }

    fun close() {
        webSocket?.close(1000, "bye")
        webSocket = null
    }

    private suspend fun nextId(): Long = idMutex.withLock { ++lastId }

    private fun send(payload: String) {
        val ws = webSocket ?: throw IllegalStateException("WebSocket is not connected")
        ws.send(payload)
    }

    suspend fun initialize(): JsonObject {
        val id = nextId()
        val obj = buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", id)
            put("method", "initialize")
        }
        val deferred = CompletableDeferred<JsonObject>()
        pending[id] = deferred
        send(json.encodeToString(JsonObject.serializer(), obj))
        return deferred.await()
    }

    suspend fun toolsCall(name: String, args: JsonObject): JsonElement {
        val id = nextId()
        val params = buildJsonObject {
            put("name", name)
            put("arguments", args)
        }
        val obj = buildJsonObject {
            put("jsonrpc", "2.0")
            put("id", id)
            put("method", "tools/call")
            put("params", params)
        }
        val deferred = CompletableDeferred<JsonObject>()
        pending[id] = deferred
        send(json.encodeToString(JsonObject.serializer(), obj))
        val resultEnvelope = deferred.await()
        // Expected: { name, result }
        return resultEnvelope["result"] ?: JsonNull
    }

    override fun onOpen(webSocket: WebSocket, response: Response) {
        // no-op
    }

    override fun onMessage(webSocket: WebSocket, text: String) {
        val el = runCatching { json.parseToJsonElement(text) }.getOrNull() ?: return
        val obj = el.jsonObject
        val idEl = obj["id"] ?: return
        val id = when (idEl) {
            is JsonPrimitive -> if (idEl.isString) idEl.content.toLongOrNull() else idEl.longOrNull
            else -> null
        } ?: return

        val result = obj["result"]?.jsonObject
        val error = obj["error"]

        val deferred = pending.remove(id)
        if (deferred != null) {
            if (error != null) {
                deferred.completeExceptionally(RuntimeException("MCP error: $error"))
            } else if (result != null) {
                deferred.complete(result)
            } else {
                deferred.completeExceptionally(RuntimeException("Invalid MCP response: $text"))
            }
        }
    }

    override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
        // ignore binary
    }

    override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
        // Bubble up failures to all waiters
        val ex = RuntimeException("WebSocket failure", t)
        pending.values.forEach { it.completeExceptionally(ex) }
        pending.clear()
        this.webSocket = null
    }

    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
        // Complete all pending with error
        val ex = RuntimeException("WebSocket closed: $code $reason")
        pending.values.forEach { it.completeExceptionally(ex) }
        pending.clear()
        this.webSocket = null
    }
}
