package ru.marslab.snaptrace.ai

import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.plugins.statuspages.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.server.plugins.calllogging.*
import io.ktor.server.request.*
import kotlinx.serialization.json.Json
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import ru.marslab.snaptrace.ai.routes.registerFeedRoutes
import ru.marslab.snaptrace.ai.routes.registerHealthRoutes
import ru.marslab.snaptrace.ai.routes.registerJobRoutes
import ru.marslab.snaptrace.ai.util.respondError
import ru.marslab.snaptrace.ai.clients.ClientsFactory
import ru.marslab.snaptrace.ai.logging.Logging

fun main() {
    embeddedServer(Netty, port = 8080, host = "0.0.0.0") {
        serverModule()
    }.start(wait = true)
}

fun Application.serverModule() {
    // Централизованная установка логирования и получение сервиса логирования
    val logging = Logging.install(this)
    install(ContentNegotiation) {
        json(
            Json {
                prettyPrint = false
                ignoreUnknownKeys = true
                explicitNulls = false
                encodeDefaults = true
            }
        )
    }
    install(StatusPages) {
        exception<Throwable> { call, cause ->
            call.respondError(500, cause.message ?: "internal_error")
        }
    }

    // In-memory storage for MVP skeleton
    InMemoryStore.init()
    InMemoryStore.configureLogger(logging)
    // Configure processors using application.conf (falls back to env inside)
    val clients = ClientsFactory.fromConfig(environment.config, logging)
    InMemoryStore.configureProcessors(clients.art, clients.gpt)
    // Start background worker for job processing if enabled
    val autostart = environment.config.propertyOrNull("snapTrace.worker.autostart")?.getString()?.toBoolean() ?: true
    if (autostart) {
        InMemoryStore.startWorker(CoroutineScope(Dispatchers.Default), processingDelayMs = 10L)
    }
    registerHealthRoutes()
    registerJobRoutes()
    registerFeedRoutes()
}
