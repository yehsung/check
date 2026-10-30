// W2-h3 Codex 계정 프로브 — `codex app-server` 에 JSONL 3줄을 쓰고 id 2 응답을 읽는다(Windows 판).
// 원본: Sources/CheckCore/CheckCodexAccountUsage.swift:102-183(캐시) · :446-516(fetch 확정 규칙) · :517-750(세션)
// 맥의 셸 조회(:184-383 — zsh 로그인 셸 · nvm · 심)는 Windows 판으로 대체: 후보는 **네이티브 exe 만**, `.cmd/.bat` 를 cmd.exe 로 띄우지 않는다.
// 후보 디렉터리(PATH 칸 · 설치 위치)는 조립 지점(AppGraph)이 값으로 넘긴다 — 이 패키지는 환경 변수를 직접 읽지 않는다(홈 격리).
package com.yehsung.aingcheck.feature.desktop.tokens.account

import com.yehsung.aingcheck.core.wire.SwiftDate
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** 띄울 명령(실행 파일 + 앞 인자). 러너가 끝에 `app-server` 를 붙인다. */
data class CodexToolchain(val command: List<String>, val environment: Map<String, String> = emptyMap(), val workingDirectory: Path? = null) {
    val executable: String get() = command.first()
}

/** 프로세스가 어떻게 끝났나(Swift SessionKind) — fetch 의 후보 확정이 본다. */
enum class CodexSessionKind { RESPONDED, EXITED, TIMEOUT, LAUNCH_FAILED }

data class CodexProbeOutcome(val result: CodexProbeResult, val kind: CodexSessionKind, val pid: Long? = null)

/** Windows 후보 — 네이티브 exe 만. */
object CodexToolchainCandidates {
    private val forbidden = setOf("cmd", "bat", "ps1", "vbs", "js")

    /** `.exe` 로 끝나는 정규 파일만(대소문자 무시). `.cmd/.bat/.ps1` 과 확장자 없는 심은 거른다(cmd.exe 를 띄우지 않는다). */
    fun isNativeExecutable(path: Path): Boolean {
        val name = path.fileName?.toString()?.lowercase() ?: return false
        val ext = name.substringAfterLast('.', "")
        return ext == "exe" && ext !in forbidden && Files.isRegularFile(path)
    }

    /** searchDirectories 의 `codex.exe` → extra(설치 위치) 순, 중복 없이, 네이티브만. */
    fun nativeCandidates(searchDirectories: List<Path>, extra: List<Path> = emptyList()): List<Path> {
        val out = LinkedHashMap<String, Path>()
        for (dir in searchDirectories) {
            val p = dir.resolve("codex.exe")
            if (isNativeExecutable(p)) out.putIfAbsent(p.toAbsolutePath().normalize().toString().lowercase(), p)
        }
        for (p in extra) if (isNativeExecutable(p)) out.putIfAbsent(p.toAbsolutePath().normalize().toString().lowercase(), p)
        return out.values.toList()
    }
}

/** 한 번의 app-server 세션(Swift runSession). 블로킹 — 부르는 쪽이 IO 디스패처에서 돈다. */
object CodexAppServerSession {
    /**
     * 요청 3줄을 쓰고 **표준 입력을 닫는다** → stdout 을 줄 단위로 읽다 id 2 줄이면 끝. 데드라인이 지나면 시간 초과.
     * 어느 쪽이든 끝나면 **프로세스 트리**(자손 먼저)를 죽인다 — npm 런처가 자식을 남기는 맥의 고아 문제를 Windows 에선 트리 종료로 막는다.
     * stderr 는 버린다. 창은 띄우지 않는다(콘솔 앱 · 자식 stdio 리다이렉트).
     */
    fun run(toolchain: CodexToolchain, appVersion: String, fetchedAt: SwiftDate,
            deadlineMillis: Long = CodexAccountProbeProtocol.FETCH_DEADLINE_MILLIS): CodexProbeOutcome {
        val builder = ProcessBuilder(toolchain.command + "app-server")
            .redirectError(ProcessBuilder.Redirect.DISCARD)
        toolchain.workingDirectory?.let { builder.directory(it.toFile()) }
        builder.environment().putAll(toolchain.environment)
        val process = try {
            builder.start()
        } catch (e: IOException) {
            return CodexProbeOutcome(CodexProbeResult.Failure(CodexAccountProbeStatus.FAILED, e.message ?: "기동 실패"), CodexSessionKind.LAUNCH_FAILED)
        }
        val pid = process.pid()
        try {
            process.outputStream.use { out ->
                out.write((CodexAccountProbeProtocol.requestLines(appVersion).joinToString("\n") + "\n").encodeToByteArray())
                out.flush()
            }
        } catch (_: IOException) {
            // 이미 끝난 프로세스 — 아래 읽기가 EOF 로 판정한다.
        }
        val received = Collections.synchronizedList(ArrayList<String>())
        val done = CountDownLatch(1)
        val responded = java.util.concurrent.atomic.AtomicBoolean(false)
        val reader = Thread {
            try {
                process.inputStream.bufferedReader(Charsets.UTF_8).use { r ->
                    while (true) {
                        val line = r.readLine() ?: break
                        if (line.isEmpty()) continue
                        received += line
                        if (CodexAccountProbeProtocol.lineHasUsageResponseID(line)) {
                            responded.set(true)
                            break
                        }
                    }
                }
            } catch (_: IOException) {
            } finally {
                done.countDown()
            }
        }
        reader.isDaemon = true
        reader.start()
        val finished = done.await(deadlineMillis, TimeUnit.MILLISECONDS)
        destroyTree(process)
        val lines = synchronized(received) { received.toList() }
        if (!finished) {
            return CodexProbeOutcome(
                CodexProbeResult.Failure(CodexAccountProbeStatus.TIMEOUT, "${deadlineMillis / 1000}초 안에 응답 없음"), CodexSessionKind.TIMEOUT, pid)
        }
        val parsed = CodexAccountProbeProtocol.parse(lines, fetchedAt = fetchedAt)
        if (responded.get()) return CodexProbeOutcome(parsed, CodexSessionKind.RESPONDED, pid)
        // 응답 없이 끝났어도 그때까지 받은 줄에 답이 있을 수 있다.
        if (CodexAccountProbeProtocol.confirmsToolchain(parsed)) return CodexProbeOutcome(parsed, CodexSessionKind.RESPONDED, pid)
        return CodexProbeOutcome(CodexProbeResult.Failure(CodexAccountProbeStatus.FAILED, "응답 없이 종료"), CodexSessionKind.EXITED, pid)
    }

    /** 자손 → 자신 순으로 강제 종료하고 잠깐 기다린다. */
    fun destroyTree(process: Process) {
        val descendants = try { process.descendants().toList() } catch (_: Exception) { emptyList() }
        for (child in descendants.reversed()) child.destroyForcibly()
        process.destroyForcibly()
        try { process.waitFor(2, TimeUnit.SECONDS) } catch (_: InterruptedException) { Thread.currentThread().interrupt() }
        for (child in descendants) {
            try { child.onExit().get(2, TimeUnit.SECONDS) } catch (_: Exception) { }
        }
    }
}

/**
 * Swift `CodexAccountUsageProbe.fetch` 의 후보 확정 규칙(셸 조회 없음).
 * 확인된 툴체인은 캐시하고, 그것이 돌지 못하면(응답 없이 종료·기동 실패) 버리고 재탐색. 후보는 [MAX_CANDIDATE_ATTEMPTS] 개까지,
 * 시간 초과는 환경 문제라 거기서 멈춘다. 후보 0 → codexNotInstalled(확정 툴체인을 막 버린 뒤면 failed), 전부 실패 → failed 를 30분 캐시.
 */
class CodexAccountProbe(
    private val candidates: () -> List<CodexToolchain>,
    private val run: (CodexToolchain, SwiftDate) -> CodexProbeOutcome,
) {
    private var confirmed: CodexToolchain? = null
    private var failedAt: SwiftDate? = null
    private var failedStatus: CodexAccountProbeStatus = CodexAccountProbeStatus.FAILED

    val confirmedToolchain: CodexToolchain? @Synchronized get() = confirmed

    @Synchronized
    fun fetch(now: SwiftDate): CodexProbeResult {
        var excluded: String? = null
        confirmed?.let { cached ->
            val outcome = run(cached, now)
            when (outcome.kind) {
                CodexSessionKind.RESPONDED, CodexSessionKind.TIMEOUT -> return outcome.result
                CodexSessionKind.EXITED, CodexSessionKind.LAUNCH_FAILED -> {
                    confirmed = null
                    excluded = cached.executable
                }
            }
        }
        val failed = failedAt
        if (failed != null && now.timeIntervalSince(failed) < CodexAccountProbeProtocol.LOCATE_FAILURE_TTL_SECONDS) {
            return CodexProbeResult.Failure(failedStatus, "탐색 실패 캐시")
        }
        val list = candidates().filter { it.executable != excluded }
        if (list.isEmpty()) {
            val status = if (excluded == null) CodexAccountProbeStatus.CODEX_NOT_INSTALLED else CodexAccountProbeStatus.FAILED
            failedAt = now
            failedStatus = status
            return CodexProbeResult.Failure(status, if (excluded == null) "codex 실행 파일 없음" else "확정 툴체인 폐기 뒤 남은 후보 없음")
        }
        var last: CodexProbeResult = CodexProbeResult.Failure(CodexAccountProbeStatus.FAILED, "후보 없음")
        for (candidate in list.take(CodexAccountProbeProtocol.MAX_CANDIDATE_ATTEMPTS)) {
            val outcome = run(candidate, now)
            last = outcome.result
            if (CodexAccountProbeProtocol.confirmsToolchain(outcome.result)) {
                confirmed = candidate
                failedAt = null
                return outcome.result
            }
            if (outcome.kind == CodexSessionKind.TIMEOUT) return outcome.result
        }
        failedAt = now
        failedStatus = CodexAccountProbeStatus.FAILED
        return if (last is CodexProbeResult.Failure) last else CodexProbeResult.Failure(CodexAccountProbeStatus.FAILED, "후보 전부 실패")
    }
}
