// W0-e Windows 탐침(G §2-3 W0-e ①②, §8-3). 출시 빌드가 아니다.
// - 버전은 A §2-3 표와 같게 둔다(Kotlin 2.4.21 · Compose 1.12.2 · JNA 5.19.1 · JDK 21).
// - 시험 JVM 은 -PtestJavaExecutable=<봉인 JDK>\bin\java.exe 로 바꿀 수 있다(§8-6 "시험 전용 JDK").
import org.jetbrains.compose.desktop.application.dsl.TargetFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.time.Instant
import java.time.temporal.ChronoUnit

plugins {
    kotlin("jvm") version "2.4.21"
    // Compose 플러그인이 1.6.10 부터 이 플러그인을 요구한다(탐침은 Composable 을 쓰지 않는다 — 포장 작업만 쓴다).
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.21"
    id("org.jetbrains.compose") version "1.12.2"
}

group = "com.yehsung.aingcheck.spike"

val spikeBuild: String = providers.gradleProperty("spike.build").getOrElse("1")
val spikeGitSha: String = providers.gradleProperty("spike.gitSha")
    .orElse(providers.environmentVariable("GITHUB_SHA"))
    .getOrElse("unknown")
val spikeTreeSha: String = providers.gradleProperty("spike.treeSha").getOrElse("unknown")
// 빌드 시각은 산출물 검증의 핵심이다(기억 binary-verification-needs-build-time). 설정 단계에서 한 번 정한다.
// CI 는 -Pspike.buildTime 으로 여러 Gradle 호출에 같은 값을 준다(호출마다 다시 컴파일되지 않게).
val spikeBuildTime: String = providers.gradleProperty("spike.buildTime")
    .getOrElse(Instant.now().truncatedTo(ChronoUnit.SECONDS).toString())
val spikeVersion = "1.0.$spikeBuild"

java {
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_21) }
}

dependencies {
    // Compose 컴파일러 플러그인은 런타임이 클래스패스에 없으면 컴파일을 멈춘다. 실제 desktopApp 도 이것을 싣는다.
    implementation("org.jetbrains.compose.runtime:runtime:1.12.2")
    implementation("net.java.dev.jna:jna:5.19.1")
    implementation("net.java.dev.jna:jna-platform:5.19.1")
    testImplementation(kotlin("test"))
}

val buildInfoDir = layout.buildDirectory.dir("generated/buildinfo/kotlin")
val buildInfoJson = layout.buildDirectory.file("buildinfo.json")

val generateBuildInfo = tasks.register("generateBuildInfo") {
    val outDir = buildInfoDir
    val outJson = buildInfoJson
    val values = mapOf(
        "version" to spikeVersion,
        "build" to spikeBuild,
        "buildTime" to spikeBuildTime,
        "gitSha" to spikeGitSha,
        "treeSha" to spikeTreeSha,
    )
    inputs.properties(values)
    outputs.dir(outDir)
    outputs.file(outJson)
    doLast {
        fun q(s: String) = "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
        val src = outDir.get().file("com/yehsung/aingcheck/spike/windows/BuildInfo.kt").asFile
        src.parentFile.mkdirs()
        src.writeText(
            buildString {
                appendLine("// 생성 파일(generateBuildInfo). 손으로 고치지 않는다.")
                appendLine("package com.yehsung.aingcheck.spike.windows")
                appendLine()
                appendLine("object BuildInfo {")
                values.forEach { (k, v) -> appendLine("    const val ${k.uppercase()}: String = ${q(v)}") }
                appendLine("}")
            },
        )
        outJson.get().asFile.writeText(
            values.entries.joinToString(",", "{", "}\n") { (k, v) -> q(k) + ":" + q(v) },
        )
    }
}

kotlin.sourceSets.named("main") { kotlin.srcDir(buildInfoDir) }
tasks.named("compileKotlin") { dependsOn(generateBuildInfo) }

tasks.test {
    useJUnitPlatform()
    providers.gradleProperty("testJavaExecutable").orNull?.let { executable = it }
    // 구조 시험(출시 빌드 제외)이 저장소 꼭대기를 찾게 한다.
    systemProperty("spike.repoRoot", rootDir.resolve("../../..").canonicalPath)
    testLogging {
        events("passed", "failed", "skipped")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
        showStandardStreams = true
    }
}

// 봉인 밖 예열: 시험 런타임 의존을 미리 받아 둔다(봉인 아래 --offline 시험이 내려받기를 못 하므로).
tasks.register("resolveTestRuntime") {
    val cp = configurations.named("testRuntimeClasspath")
    doLast { println("testRuntimeClasspath: ${cp.get().files.size} files") }
}

// 봉인 JDK 로 탐침을 바로 돌리기 위한 클래스패스 묶음(build/probe-lib).
val probeLibs = tasks.register<Sync>("probeLibs") {
    from(tasks.jar)
    from(configurations.runtimeClasspath)
    into(layout.buildDirectory.dir("probe-lib"))
}
tasks.named("assemble") { dependsOn(probeLibs) }

compose.desktop {
    application {
        mainClass = "com.yehsung.aingcheck.spike.windows.MainKt"
        jvmArgs += listOf("-Dfile.encoding=UTF-8")
        nativeDistributions {
            targetFormats(TargetFormat.Msi)
            packageName = "AingSpike"
            packageVersion = spikeVersion
            vendor = "AingCheck Spike"
            description = "AingCheck W0-e Windows probe (not a release build)"
            modules("java.xml", "java.logging", "jdk.unsupported")
            windows {
                perUserInstall = true
                dirChooser = false
                shortcut = false
                menu = false
                // 탐침 전용 값. 실제 앱의 upgradeUuid 는 W6 이 따로 만든다(A §2-2).
                upgradeUuid = "4a01e2f4-608f-4c8c-85db-44786420cf57"
            }
        }
    }
}
