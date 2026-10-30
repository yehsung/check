// W2-h1 — 토큰 사용량 스토어(주기 스캔 · 캐시 영속 · 스냅숏 복원 · 스캔 입구 게이트).
// 원본: Sources/CheckCore/CheckTokenUsage.swift:1996-2341(TokenUsageStore, macOS).
// Windows 차이:
//  · ★ INV-CheckTokenUsage-b93282d9 이식: 허용 게이트([isScanPermitted])는 **스캔의 유일한 입구**(startScan)에 건다 — 주기 루프·지금 스캔·
//    배경 스캔이 모두 이 한 곳을 지난다. 맥은 앱스토어 판 동의(AIToolDataConsent), Windows 는 조립 지점이 정한다(기본 허용 — 직접 배포판).
//  · ★ INV-CheckTokenUsage-1e4bfd85 이식: 맥의 '시험 프로세스 실홈 차단 단일 지점'(realHomeScanIsBlocked)은 [DesktopAiHomes] 주입으로 대체한다 —
//    이 패키지는 user.home·환경 변수를 읽지 않으므로 시험은 합성 홈만 본다(TokenHomeIsolationTest 가 카나리로 잰다).
//  · 종료 저장(willTerminate 관찰)은 셸이 [persistForTermination] 을 부른다(조립 몫). 스냅숏은 UserDefaults 대신 DesktopKeyValueStore.
package com.yehsung.aingcheck.feature.desktop.tokens.scan

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.nio.file.Path
import kotlin.coroutines.coroutineContext

class TokenUsageStore(
    private val homes: DesktopAiHomes,
    private val keyValueStore: DesktopKeyValueStore,
    /** 캐시 파일 기준 경로(…/token-usage-cache.json). null 이면 메모리에만(시험). */
    private val cacheBase: Path?,
    private val clock: () -> SwiftDate = { SwiftDate(System.currentTimeMillis() / 1000.0) },
    private val isScanPermitted: () -> Boolean = { true },
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    companion object {
        const val SNAPSHOT_KEY = "check.tokenUsage.snapshot"
        const val REFRESH_PERIOD_SECONDS = 120.0
        const val MIN_REFRESH_INTERVAL_SECONDS = 3.0
        const val SAVE_INTERVAL_SECONDS = 300.0
    }

    private val usage = MutableStateFlow(restoreSnapshot())
    private val scanning = MutableStateFlow(false)

    /** 이번 KST 월 집계. 복원한 스냅숏은 같은 달일 때만(월이 바뀌었으면 null 로 두고 재스캔). */
    val currentMonthUsage: StateFlow<TokenUsageMonthly?> = usage.asStateFlow()
    val isScanning: StateFlow<Boolean> = scanning.asStateFlow()

    @Volatile var scanCount: Int = 0
        private set
    @Volatile var saveCount: Int = 0
        private set
    @Volatile var lastScanFileCount: Int = 0
        private set
    @Volatile var lastScanAt: SwiftDate? = null
        private set

    private val lock = Any()
    private var inFlight: CompletableDeferred<Unit>? = null
    private var cache: TokenUsageCache? = null
    private var lastRefreshAt: SwiftDate? = null
    private var dirty: MutableSet<TokenUsageCacheStore.Part> = mutableSetOf()
    private var lastSaveAt: SwiftDate = clock()

    /** 팝오버(플라이아웃) 주기: 즉시 한 번, 그다음 120초마다. 취소되면 더러운 캐시를 강제 저장. */
    suspend fun runRefreshLoop() {
        try {
            while (coroutineContext.isActive) {
                refreshIfStale()
                delay((REFRESH_PERIOD_SECONDS * 1000).toLong())
            }
        } finally {
            withContext(kotlinx.coroutines.NonCancellable) { persistIfDirty(force = true) }
        }
    }

    /** 3초 안에 다시 부르면 건너뛴다. 스캔 중이면 그 스캔을 기다린다. */
    suspend fun refreshIfStale() {
        inFlightOrNull()?.let { it.await(); return }
        val last = lastRefreshAt
        if (last != null && clock().timeIntervalSince(last) < MIN_REFRESH_INTERVAL_SECONDS) return
        startScan()
    }

    suspend fun refreshNow() {
        inFlightOrNull()?.let { it.await(); return }
        startScan()
    }

    /** 앱 종료 직전(셸이 부른다): 더러우면 동기 저장. */
    fun persistForTermination() {
        val (snapshot, parts) = synchronized(lock) {
            val c = cache ?: return
            if (dirty.isEmpty()) return
            val p = dirty.toSet()
            dirty = mutableSetOf()
            lastSaveAt = clock()
            saveCount += 1
            c to p
        }
        cacheBase?.let { TokenUsageCacheStore.save(snapshot, parts, it) }
    }

    private fun inFlightOrNull(): CompletableDeferred<Unit>? = synchronized(lock) { inFlight }

    /** 스캔의 유일한 입구(★ INV-CheckTokenUsage-b93282d9). */
    private suspend fun startScan() {
        if (!isScanPermitted()) return
        val mine = CompletableDeferred<Unit>()
        val existing = synchronized(lock) {
            val current = inFlight
            if (current == null) inFlight = mine
            current
        }
        if (existing != null) {
            existing.await()
            return
        }
        try {
            scanning.value = true
            scanCount += 1
            val now = clock()
            lastRefreshAt = now
            val base = cache
            val result = withContext(ioDispatcher) {
                val start = base ?: cacheBase?.let(TokenUsageCacheStore::load) ?: TokenUsageCache()
                TokenUsageIncrementalScanner.update(start, homes, now)
            }
            synchronized(lock) {
                cache = result.cache
                dirty.addAll(result.stats.changedParts)
            }
            apply(result.usage)
            lastScanFileCount = result.stats.claudeFilesStatted + result.stats.codexFilesStatted
            lastScanAt = clock()
            persistIfDirty(force = false)
        } finally {
            scanning.value = false
            synchronized(lock) { inFlight = null }
            mine.complete(Unit)
        }
    }

    /** 5분 스로틀(force 면 무시). 더러운 쪽(state·entries)만 쓴다. */
    private suspend fun persistIfDirty(force: Boolean) {
        val job = synchronized(lock) {
            val c = cache ?: return
            if (dirty.isEmpty()) return
            val now = clock()
            if (!force && now.timeIntervalSince(lastSaveAt) < SAVE_INTERVAL_SECONDS) return
            val parts = dirty.toSet()
            dirty = mutableSetOf()
            lastSaveAt = now
            saveCount += 1
            c to parts
        }
        val base = cacheBase ?: return
        withContext(ioDispatcher) { TokenUsageCacheStore.save(job.first, job.second, base) }
    }

    /** total > 0 일 때만 스냅숏을 덮는다(빈 스캔이 지난 값을 지우지 않게). */
    private fun apply(value: TokenUsageMonthly) {
        usage.value = value
        if (value.total > 0) keyValueStore.putString(SNAPSHOT_KEY, value.encode())
    }

    private fun restoreSnapshot(): TokenUsageMonthly? {
        val text = keyValueStore.getString(SNAPSHOT_KEY) ?: return null
        val restored = runCatching { TokenUsageMonthly.decode(text) }.getOrNull() ?: return null
        return restored.takeIf { it.month == TokenUsageIncrementalScanner.kstMonthString(clock()) }
    }
}
