// W2-h3 Codex 계정 스토어 — 30분 간격 · 강제 하한 60초 · auth.json 부재면 프로세스 0 · 스냅샷 영속.
// 원본: Sources/CheckCore/CheckCodexAccountUsage.swift:754-869(CodexAccountUsageStore)
// Windows: auth.json 부재 = 미로그인(keyring 모드 포함 — W-3 #11, config.toml 은 읽지 않는다). 파일 내용은 읽지 않는다(존재만).
package com.yehsung.aingcheck.feature.desktop.tokens.account

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.nio.file.Files
import java.nio.file.Path

class CodexAccountUsageStore(
    private val store: DesktopKeyValueStore,
    /** 부를 때마다 다시 푼다(DesktopAiHomes.codexHome — 조립 지점이 넘긴다). */
    private val codexHome: () -> Path,
    /**
     * AI 도구 기록 읽기 동의(W-13 #5 · 맥 aiToolDataAllowed — WorkTimerStoreMacEdition.swift:54-64 · WorkTimerStoreSync.swift:790).
     * 거짓이면 auth.json 존재 확인도 codex.exe 실행도 하지 않고, 주기도 쓰지 않는다(동의하면 바로 다음 틱이 돈다). 기본 참 = 옛 호출 그대로.
     */
    private val isPermitted: () -> Boolean = { true },
    private val runner: suspend (now: SwiftDate) -> CodexProbeResult,
) : CodexAccountSource {
    override var snapshot: CodexAccountUsage? = restore()
        private set
    override var lastStatus: CodexAccountProbeStatus? = null
        private set
    var lastProbeAt: SwiftDate? = null
        private set
    var runnerCallCount: Int = 0
        private set
    private var inFlight = false

    fun isDue(now: SwiftDate, force: Boolean = false): Boolean {
        if (inFlight) return false
        val last = lastProbeAt ?: return true
        val elapsed = now.timeIntervalSince(last)
        return if (force) elapsed >= FORCED_REFRESH_FLOOR_SECONDS else elapsed >= REFRESH_INTERVAL_SECONDS
    }

    override suspend fun refreshIfDue(now: SwiftDate, force: Boolean) {
        if (!isPermitted()) return
        if (!isDue(now, force)) return
        lastProbeAt = now
        inFlight = true
        try {
            // ★ auth.json 이 없으면 로그인 안 된 것 — 프로세스를 띄우지 않는다(내용은 읽지 않는다).
            if (!Files.exists(codexHome().resolve("auth.json"))) {
                lastStatus = CodexAccountProbeStatus.NOT_LOGGED_IN
                return
            }
            runnerCallCount += 1
            when (val result = runner(now)) {
                is CodexProbeResult.Success -> {
                    snapshot = result.usage
                    lastStatus = CodexAccountProbeStatus.OK
                    store.putString(SNAPSHOT_KEY, persisted.encodeToString(Persisted.serializer(), Persisted.of(result.usage)))
                }
                is CodexProbeResult.Failure -> lastStatus = result.status
            }
        } finally {
            inFlight = false
        }
    }

    private fun restore(): CodexAccountUsage? = store.getString(SNAPSHOT_KEY)?.let { text ->
        try { persisted.decodeFromString(Persisted.serializer(), text).toUsage() } catch (_: Exception) { null }
    }

    /** Swift JSONEncoder 기본 모양(Date = 2001 기준 초 Double, nil 키 생략). */
    @Serializable
    private data class Persisted(val fetchedAt: Double, val lifetimeTokens: Long? = null, val buckets: Map<String, Long> = emptyMap()) {
        fun toUsage() = CodexAccountUsage(SwiftDate.fromReferenceDate(fetchedAt), lifetimeTokens, buckets)
        companion object {
            fun of(u: CodexAccountUsage) = Persisted(u.fetchedAt.timeIntervalSinceReferenceDate, u.lifetimeTokens, u.buckets)
        }
    }

    companion object {
        const val SNAPSHOT_KEY: String = "check.codexAccount.snapshot"
        /** 30분 하한(Swift refreshInterval 1800). INV-CheckCodexAccountUsage-58d33024 이식: 하한이 없으면 30초 틱마다 app-server 를 띄운다. */
        const val REFRESH_INTERVAL_SECONDS: Double = 1800.0
        /** 월 롤오버 등 강제 갱신의 하한(Swift forcedRefreshFloor 60). */
        const val FORCED_REFRESH_FLOOR_SECONDS: Double = 60.0
        private val persisted = Json { explicitNulls = false; ignoreUnknownKeys = true }
    }
}
