// 원본: 없음(조정자 배선) — W-6 #1·#6 · W-3 #11 · W2-h1 P5(TokenUsageStore) · W2-h2 P5(AILimitStore·DesktopAILimitSync) ·
// W2-h3 P5(TokenUploadCoordinator·CodexAccountUsageStore — TokenScanSource 는 h1 스캔 스토어를 이 배선이 감싸 댄다).
//
// 토큰 쪽 한 벌: 로컬 스캔(깃발 무관 — 로컬 표시) · AI 리밋 읽기·업로드(ai_limits — **깃발 없이 연다**, W-3 #11) ·
// 토큰 업로드 조정자(tokenUpload=false 면 token_usage_device_{monthly,daily}·하트비트 쓰기 0 — 게이트는 조정자 맨 앞 ★1).
// 서버·파일 작업은 [serial] 한 줄로만 돈다(조정자·계정 스토어는 스레드 안전하지 않다).
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitRunner
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitSession
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitStore
import com.yehsung.aingcheck.feature.desktop.ailimits.DesktopAILimitSync
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountUsageStore
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexProbeResult
import com.yehsung.aingcheck.feature.desktop.tokens.diag.CodexUsageDiagnostics
import com.yehsung.aingcheck.feature.desktop.tokens.scan.TokenUsageStore
import com.yehsung.aingcheck.feature.desktop.tokens.upload.TokenScanSource
import com.yehsung.aingcheck.feature.desktop.tokens.upload.TokenUploadCoordinator
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.nio.file.Path
import kotlin.time.Clock

/** 토큰 배선이 받는 것. 이름·타입은 AppGraph 의 것 그대로(desktopConfig·clock·deviceId). [sessionStore] 에는 SessionStore 를 넘긴다. */
data class TokensWiringDeps(
    val desktopConfig: DesktopAppConfig,
    val sessionStore: SessionHost,
    val service: SupabaseWorkService,
    val keyValueStore: DesktopKeyValueStore,
    val clock: Clock,
    /** AppGraph.deviceId(`win:…` 또는 null — 새로 짓지 않는다). null 이면 기기 단위 쓰기 0. */
    val deviceId: () -> String?,
    /** `DesktopAiHomes(paths.userHome) { WindowsEnvironment.system().codexHome().path }`. */
    val homes: DesktopAiHomes,
    /** `<앱 데이터>/token-usage-cache.json`. null 이면 메모리만(시험). */
    val cacheBase: Path?,
    /** 생성 상수 BuildIdentity.BUILD(windowsBuild). 0 이하면 진단 0. */
    val appBuild: Long,
    /** 서버 수집 설정(fetchTokenUsageSettings 값 && 불러옴 — MeStore). */
    val tokenUsageCollect: () -> Boolean,
    /** 배경 스캔은 근무 중일 때만(Swift refreshTokenUsageInBackgroundIfDue). */
    val workState: DesktopWorkState,
    /** `AILimitWindowsRunner.live(homes, AILimitHTTPKtor.fetcher(httpClient()), BuildIdentity.VERSION)`. */
    val aiLimitRunner: AILimitRunner,
    /** 이 PC 이름(`platform.env["COMPUTERNAME"]`) — 식별자가 아니다. */
    val deviceLabel: () -> String?,
    /** `{ now -> withContext(IO) { probe.fetch(now) } }`(CodexAccountProbe — 후보·실행은 조립 지점이 값으로). */
    val codexAccountRunner: suspend (now: SwiftDate) -> CodexProbeResult,
    /** `{ m, b -> withContext(IO) { CodexUsageDiagnosticsScanner.compute(homes.codexHome(), m, b) } }`. */
    val computeDiagnostics: suspend (month: String, appBuild: Long) -> CodexUsageDiagnostics?,
    val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    val tickMillis: Long = TokensWiring.TICK_MILLIS,
)

class TokensWiring(private val deps: TokensWiringDeps) {
    companion object {
        /** 30초 틱(맥 WorkTimerStore 주기와 같은 자리 — 리밋·배경 스캔 판정은 각 스토어 간격이 정한다). */
        const val TICK_MILLIS: Long = 30_000
    }

    /** W2-h1 로컬 스캔(깃발 무관). */
    val scan: TokenUsageStore = TokenUsageStore(
        homes = deps.homes,
        keyValueStore = deps.keyValueStore,
        cacheBase = deps.cacheBase,
        clock = ::wallNow,
        isScanPermitted = { true },
        ioDispatcher = deps.ioDispatcher,
    )

    /** W2-h3 이 기대는 스캔 문 — h1 스토어를 감싼다(W2-h3 unresolved: 'h1 스캔 스토어가 TokenScanSource 구현'). */
    val scanSource: TokenScanSource = object : TokenScanSource {
        override val currentMonthUsage: TokenUsageMonthly? get() = scan.currentMonthUsage.value
        override val lastScanAt: SwiftDate? get() = scan.lastScanAt
        override val lastScanFileCount: Int get() = scan.lastScanFileCount
        override suspend fun refreshNow() = scan.refreshNow()
        override suspend fun refreshIfStale() = scan.refreshIfStale()
    }

    /** W2-h3 Codex 계정 스토어(auth.json 부재면 프로세스 0). */
    val account: CodexAccountUsageStore = CodexAccountUsageStore(deps.keyValueStore, deps.homes::codexHome, deps.codexAccountRunner)

    /** W2-h3 업로드 조정자 — tokenUpload 깃발은 조정자 안 ★1 게이트가 맨 앞에서 본다(여기서 바꾸지 않는다). */
    val upload: TokenUploadCoordinator = TokenUploadCoordinator(
        config = deps.desktopConfig,
        host = deps.sessionStore,
        deviceId = deps.deviceId,
        tokenUsageCollect = deps.tokenUsageCollect,
        store = deps.keyValueStore,
        appBuild = deps.appBuild,
        computeDiagnostics = deps.computeDiagnostics,
    )

    /** W2-h2 리밋 스토어(설정 창·플라이아웃이 읽는다). */
    val aiLimits: AILimitStore = AILimitStore(
        defaults = deps.keyValueStore,
        clock = ::wallNow,
        deviceLabelProvider = deps.deviceLabel,
        runner = deps.aiLimitRunner,
    )

    /** W2-h2 리밋 업로드 — 깃발 없이 연다(W-3 #11). 게이트는 세션·기기 id·지문뿐. */
    val aiLimitSync: DesktopAILimitSync = DesktopAILimitSync(
        store = aiLimits,
        service = deps.service,
        session = { deps.sessionStore.session?.let { AILimitSession(it.accessToken, it.userID) } },
        deviceId = deps.deviceId,
    )

    private val serial = Mutex()
    private var job: Job? = null
    private var flyoutJob: Job? = null
    private var scope: CoroutineScope? = null

    /** 끝난 30초 틱 수(시험·진단). */
    @Volatile var ticks: Int = 0
        private set

    fun start(scope: CoroutineScope) {
        if (job != null) return
        this.scope = scope
        job = scope.launch {
            // 스캔 값이 바뀌면 올릴지 묻는다(변경·60초 게이트는 조정자 몫 — 깃발 꺼짐이면 그 안에서 0).
            launch {
                scan.currentMonthUsage.drop(1).collect { serially { upload.uploadTokenUsageIfNeeded(scanSource, account, wallNow()) } }
            }
            while (isActive) {
                tick()
                delay(deps.tickMillis)
            }
        }
    }

    /** 30초 틱 한 번: 리밋 읽기·업로드 → 배경 스캔(근무 중일 때만)·토큰 업로드·하트비트. */
    suspend fun tick() {
        serially { aiLimitSync.refreshAILimitsIfNeeded(wallNow()) }
        serially {
            upload.refreshTokenUsageInBackgroundIfDue(scanSource, account, deps.workState.snapshot.value.isWorking, wallNow())
        }
        ticks += 1
    }

    /** 플라이아웃이 열렸다: 스캔 주기(즉시·120초) · 리밋 강제(5분 하한 유지) · 내 행. 닫히면 [onFlyoutClosed]. */
    fun onFlyoutOpened() {
        val s = scope ?: return
        if (flyoutJob?.isActive == true) return
        flyoutJob = s.launch {
            launch { scan.runRefreshLoop() }
            serially { aiLimitSync.refreshAILimitsIfNeeded(wallNow(), force = true) }
            serially { upload.loadMyTokenRowIfDue(wallNow()) }
        }
    }

    fun onFlyoutClosed() {
        flyoutJob?.cancel()
        flyoutJob = null
    }

    /** Main 종료 훅(W-6 #6: QuitFinisher 뒤, 실시간 shutdown 앞) — 맥 willTerminate 의 스캔 캐시 강제 저장. */
    suspend fun finishForQuit() {
        withContext(deps.ioDispatcher) { scan.persistForTermination() }
    }

    fun stop() {
        flyoutJob?.cancel()
        flyoutJob = null
        job?.cancel()
        job = null
        scope = null
    }

    private suspend fun serially(block: suspend () -> Unit) {
        try {
            serial.withLock { block() }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            // 한 갈래 실패가 틱을 멈추지 않는다(각 스토어가 실패를 자기 장부에 적는다).
        }
    }

    private fun wallNow(): SwiftDate = SwiftDate.fromEpochMillis(deps.clock.now().toEpochMilliseconds())
}
