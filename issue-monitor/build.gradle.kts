plugins {
    kotlin("jvm") version "2.1.20"
    application
    id("com.github.johnrengelman.shadow") version "8.1.1"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.20"
}

group = "ru.marslab"
version = "1.0.0"

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    testImplementation(kotlin("test"))
}

kotlin {
    jvmToolchain(17)
}

application {
    mainClass.set("ru.marslab.issuemonitor.MainKt")
}

// Produce a fat JAR for easier deployment
tasks.named<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar>("shadowJar") {
    archiveBaseName.set("issue-monitor")
    archiveClassifier.set("all")
    archiveVersion.set(version.toString())
}

tasks.build {
    dependsOn(tasks.named("shadowJar"))
}

tasks.named("distZip") { dependsOn(tasks.named("shadowJar")) }
tasks.named("distTar") { dependsOn(tasks.named("shadowJar")) }
tasks.named("startScripts") { dependsOn(tasks.named("shadowJar")) }
