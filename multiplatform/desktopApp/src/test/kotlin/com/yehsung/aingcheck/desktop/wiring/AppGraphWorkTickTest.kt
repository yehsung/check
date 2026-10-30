// 조립 그래프 전체(AppGraph.assemble)를 가짜 세션으로 띄워 MockEngine 녹음으로 잰다 — 반박 검증 must_fix 두 건:
//  ① 근무 중 work_tick·하트비트 루프가 돌아 서버 last_seen_at 이 얼지 않는다(스캐빈저 10분 — close_abandoned_work_sessions).
//  ② Windows 가 client_devices 'windows' 행을 등록한다(ultra_windows_floor_build · windows_device_build 가 읽는다).
// 픽스처는 합성(.invalid 주소 · 합성 uuid)만.
@file:OptIn(ExperimentalCoroutinesApi::class, ExperimentalTime::class)

package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.RunningTests
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.foundation.platform.desktop.AppPaths
import com.yehsung.aingcheck.core.foundation.platform.desktop.EnvReader
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyRegistrationResult
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyService
import com.yehsung.aingcheck.core.foundation.platform.desktop.LoginItem
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.RasterImage
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayClick
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.desktop.AppGraph
import com.yehsung.aingcheck.desktop.AppSeams
import com.yehsung.aingcheck.desktop.AppWirings
import com.yehsung.aingcheck.desktop.DesktopPlatform
import com.yehsung.aingcheck.desktop.SilentCharacterSink
import com.yehsung.aingcheck.desktop.overlay.engine.FakeMeasure
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutScreen
import com.yehsung.aingcheck.desktop.shell.flyout.SyntheticScreen
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsKeys
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitReadOutcome
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitRunner
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockEngineConfig
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.ByteArrayContent
import io.ktor.http.content.TextContent
import io.ktor.http.headersOf
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import java.nio.file.Path
import java.util.concurrent.Executor
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Clock
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

private class TickPlatform(private val installation: String?) : DesktopPlatform {
    override val paths = object : AppPaths {
        // 할 일 목록 파일이 저장소 안 상대 경로에 흘리지 않게 임시 폴더.
        override val dataDir: String = java.nio.file.Files.createTempDirectory("tick-data").toFile().apply { deleteOnExit() }.path
        override val cacheDir = "C"; override val logDir = "L"; override val userHome = "H"
    }
    override val env = object : EnvReader { override fun get(name: String): String? = null }
    override val tokenVault: TokenVault = InMemoryTokenVault()
    override val installationIdentity = object : InstallationIdentity {
        override fun installationId(): String? = installation
    }
    override val singleInstance = object : SingleInstanceGuard { override fun tryAcquire() = true; override fun release() {} }
    override val tray = object : TrayHost {
        override fun show(icon: RasterImage, tooltip: String) {}
        override fun update(icon: RasterImage, tooltip: String) {}
        override fun remove() {}
        override fun addClickListener(listener: (click: TrayClick, screenX: Int, screenY: Int) -> Unit) = Registration { }
    }
    override val hotkeys = object : HotkeyService {
        override fun register(chord: HotkeyChord, onPressed: () -> Unit) = HotkeyRegistrationResult.Conflict(0)
    }
    override val idle = FakeIdle()
    override val power = object : PowerEvents {
        override fun addListener(listener: (PowerEvent) -> Unit): Registration = Registration { }
    }
    override val session = FakeSessionEvents()
    override val loginItem: LoginItem? = null
}

/** work_tick 응답 갈래. */
private enum class TickMode { OK, MISSING, OVERLOAD, TRANSPORT }

private data class TickReq(val t: Long, val method: String, val path: String, val body: String) {
    val isWorkTick: Boolean get() = path.endsWith("/rpc/work_tick")
    val carriesHeartbeat: Boolean get() = isWorkTick && body.contains("\"p_heartbeat\":true")
    val isLegacyWorkingBeat: Boolean
        get() = method == "POST" && path.endsWith("/rest/v1/work_statuses") && body.contains("\"status\":\"working\"")
}

private class TickRig(val test: TestScope, var mode: TickMode, installation: String? = WiringTestRig.INSTALLATION) {
    val requests = mutableListOf<TickReq>()
    val uncaught = mutableListOf<Throwable>()

    /** 소속 읽기를 503 으로 막는다(오프라인 부팅 — 실행 킥이 망 결합 전에 실패). */
    var membershipFail = false

    /** work_tick 응답의 자기 행을 off_work 로(서버가 이미 이 세션을 닫았다 — 다른 기기 종료·백스톱). */
    var ownOff = false
    private val engine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(test.testScheduler)
            addHandler { request ->
                val body = when (val b = request.body) {
                    is TextContent -> b.text
                    is ByteArrayContent -> b.bytes().decodeToString()
                    else -> ""
                }
                val p = request.url.encodedPath
                val m = request.method.value
                requests += TickReq(test.testScheduler.currentTime / 1000, m, p, body)
                val json = headersOf(HttpHeaders.ContentType, "application/json")
                when {
                    p.endsWith("/rpc/work_tick") -> when (mode) {
                        TickMode.OK -> respond(if (ownOff) tickOwnOff(test.testScheduler.currentTime) else TICK_OK, HttpStatusCode.OK, json)
                        TickMode.MISSING -> respond("""{"code":"PGRST202","message":"missing"}""", HttpStatusCode.NotFound, json)
                        TickMode.OVERLOAD -> respond("""{"message":"overloaded"}""", HttpStatusCode.ServiceUnavailable, json)
                        TickMode.TRANSPORT -> throw java.io.IOException("unreachable (synthetic)")
                    }
                    p.endsWith("/rpc/register_device") || p.endsWith("/rpc/unregister_device") ->
                        respond("""{"status":"ok"}""", HttpStatusCode.OK, json)
                    p.endsWith("/rpc/take_pokes") -> respond("[]", HttpStatusCode.OK, json)
                    p.endsWith("/rest/v1/memberships") && membershipFail ->
                        respond("""{"message":"unavailable"}""", HttpStatusCode.ServiceUnavailable, json)
                    p.endsWith("/rest/v1/memberships") ->
                        respond(
                            """[{"team_id":"${WiringTestRig.TEAM}","role":"member","teams":{"name":"T","weekly_goal_hours":40}}]""",
                            HttpStatusCode.OK, json,
                        )
                    p.endsWith("/rest/v1/profiles") -> respond("""[{"token_usage_public":false,"focus_mode":null}]""", HttpStatusCode.OK, json)
                    // 서버가 넣은 행을 돌려준다(return=representation) — 큐가 세션 id 를 '확인'으로 찍는다.
                    p.endsWith("/rest/v1/work_sessions") && m == "POST" -> respond("[$body]", HttpStatusCode.OK, json)
                    p.endsWith("/rest/v1/work_sessions") || p.endsWith("/rest/v1/work_statuses") || p.endsWith("/rest/v1/work_status_devices") ->
                        respond("[]", HttpStatusCode.OK, json)
                    else -> respond("""{"code":"PGRST202","message":"no fixture"}""", HttpStatusCode.NotFound, json)
                }
            }
        },
    )
    val graph = AppGraph(
        platform = TickPlatform(installation),
        clock = object : Clock {
            override fun now(): Instant = Instant.fromEpochMilliseconds(WiringTestRig.BASE_MS + test.testScheduler.currentTime)
        },
        monotonic = object : MonotonicClock {
            override fun elapsedNanos(): Long = test.testScheduler.currentTime * 1_000_000
        },
        desktopConfig = DesktopAppConfig(),
        backend = AppGraph.Backend("https://tick.invalid", "stub-anon-key"),
        osVersion = "Windows 11",
        httpFactory = { configure -> HttpClient(engine) { configure() } },
    )
    private val job = SupervisorJob()
    val scope = CoroutineScope(test.coroutineContext.minusKey(Job) + job + CoroutineExceptionHandler { _, e -> uncaught += e })
    val app: AppWirings = graph.assemble(
        AppSeams(
            events = Executor { it.run() },
            mainDispatcher = StandardTestDispatcher(test.testScheduler),
            window = FakeWindowPort(),
            screen = FlyoutScreen { SyntheticScreen.facts },
            characterSink = SilentCharacterSink(),
            bubbleMeasure = FakeMeasure(),
            gameWindows = FakeGameFactory(),
            homes = DesktopAiHomes(Path.of("synthetic-home")) { Path.of("synthetic-home", ".codex") },
            tokenCacheFile = null,
            aiLimitRunner = AILimitRunner { _, _ -> AILimitReadOutcome(emptyMap()) },
            codexAccountRunner = { _ -> awaitCancellation() },
            computeDiagnostics = { _, _ -> null },
            runningTests = object : RunningTests { override val isRunningTests: Boolean = true },
            // 첫 실행을 마친 설치(동의·자동 실행 값이 있다) — 첫 실행 화면이 플라이아웃을 열어 빠른 주기로 바꾸지 않게.
            keyValueStore = InMemoryDesktopKeyValueStore().apply {
                putBoolean(DesktopSettingsKeys.AI_TOOL_DATA_CONSENT, false)
                putBoolean(DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF, false)
            },
        ),
        scope,
    )

    val nowSeconds: Long get() = test.testScheduler.currentTime / 1000

    fun signIn() = app.sessionStore.adoptSignedInSession(
        SupabaseSession("tok-${WiringTestRig.USER}", "ref-${WiringTestRig.USER}", WiringTestRig.USER),
        "tick@aing.example",
    )

    fun count(suffix: String, method: String? = null) = requests.count { it.path.endsWith(suffix) && (method == null || it.method == method) }

    fun between(from: Long, to: Long) = requests.filter { it.t in from..to }

    fun close() = job.cancel()

    val working: Boolean get() = app.work.store.snapshot.value.isWorking

    private fun iso(ms: Long) = Instant.fromEpochMilliseconds(WiringTestRig.BASE_MS + ms).toString()

    private fun tickOwnOff(ms: Long): String =
        """{"v":1,"server_now":"${iso(ms)}","team_id":"${WiringTestRig.TEAM}","heartbeat":null,""" +
            """"statuses":[{"user_id":"${WiringTestRig.USER}","status":"off_work","updated_at":"${iso(ms)}",""" +
            """"last_seen_at":"${iso(ms)}","active_session_id":null,"profiles":{"display_name":"나","avatar_url":null}}],""" +
            """"sessions_active":[],"sessions_weekly":[],"devices":[],"away":null}"""

    companion object {
        const val TEAMMATE = "d0000000-0000-4000-8000-0000000000c3"
        val TICK_OK = """{"v":1,"server_now":"2026-09-16T00:00:00.000Z","team_id":"${WiringTestRig.TEAM}",""" +
            """"heartbeat":{"mode":"session","status":"working"},""" +
            """"statuses":[{"user_id":"$TEAMMATE","status":"working","updated_at":"2026-09-16T00:00:00.000Z",""" +
            """"last_seen_at":"2026-09-16T00:00:00.000Z","active_session_id":null,"profiles":{"display_name":"합성팀원","avatar_url":null}}],""" +
            """"sessions_active":[],"sessions_weekly":[],"devices":[],"away":null}"""
    }
}

/** 단언이 빨개져도 그래프의 무한 박자(틱·정책·폴링)를 반드시 내린다 — 안 내리면 실패한 시험이 끝나지 않는다. */
private inline fun TickRig.use(block: (TickRig) -> Unit) {
    try {
        block(this)
    } finally {
        close()
    }
}

/** [from, 쓰기…, to] 사이 가장 긴 공백(초). */
private fun maxGap(from: Long, beats: List<Long>, to: Long): Long =
    (listOf(from) + beats + listOf(to)).zipWithNext { a, b -> b - a }.maxOrNull() ?: (to - from)

private suspend fun TestScope.advanceInSteps(total: Duration, step: Duration = 10.minutes) {
    var left = total
    while (left > Duration.ZERO) {
        val d = if (left < step) left else step
        advanceTimeBy(d)
        runCurrent()
        left -= d
    }
}

class AppGraphWorkTickTest {
    /** 근무 3시간 10분: work_tick 이 30초마다 하트비트를 실어 나간다(공백 ≤ 60초 — 스캐빈저 10분보다 한참 안쪽). */
    @Test
    fun workingSessionHeartbeatsThroughWorkTickEveryThirtySeconds() = runTest(timeout = 2.minutes) {
        TickRig(this, TickMode.OK).use { r ->
            r.app.start(); runCurrent()
            r.signIn()
            advanceInSteps(2.minutes)
            val start = r.nowSeconds
            r.app.work.commands.start(WorkStartOrigin.MANUAL); runCurrent()
            advanceInSteps(190.minutes)
            val end = r.nowSeconds
            val beats = r.between(start, end).filter { it.carriesHeartbeat }
            assertTrue(beats.size >= 360, "근무 190분에 하트비트를 실은 work_tick 이 ${beats.size}건 — 30초마다여야 한다")
            val gap = maxGap(start, beats.map { it.t }, end)
            assertTrue(gap <= 60, "하트비트 공백 최대 ${gap}초 — 60초 안이어야 한다(서버 10분 스캐빈저)")
            assertTrue(beats.drop(2).all { it.body.contains("\"p_session_id\":\"") }, "확인된 세션 id 를 싣는다(⑬)")
            assertTrue(beats.all { it.body.contains("\"p_device_id\":\"${WiringTestRig.DEVICE}\"") }, "기기 행은 'win:'||installation_id")
            // work_tick 이 팀 상태·away 조각을 한 번에 가져온다 — 4 GET·away_sync 를 따로 내지 않는다.
            assertEquals(0, r.count("/rest/v1/work_statuses", "GET"), "팀 상태 4 GET 펼침 0")
            assertEquals(0, r.count("/rpc/away_sync"), "away 는 work_tick 조각 — away_sync 두 벌 금지")
            // work.applyTeamStatus 를 지났다(팀 상태 반영 → 소셜 빚 되맞춤).
            assertTrue(r.app.work.teamStatuses.value.any { it.id == TickRig.TEAMMATE }, "work_tick 조각이 팀 상태로 반영된다")

            r.app.work.commands.stop(); runCurrent()
            advanceTimeBy(5.seconds); runCurrent()
            val idleFrom = r.nowSeconds
            advanceInSteps(30.minutes)
            val idleTicks = r.between(idleFrom + 1, r.nowSeconds).count { it.isWorkTick }
            assertTrue(idleTicks in 5..7, "비근무 30분 work_tick ${idleTicks}건 — 300초마다여야 한다")
            assertTrue(r.between(idleFrom + 1, r.nowSeconds).none { it.carriesHeartbeat }, "비근무 틱은 하트비트를 싣지 않는다")
            assertTrue(r.uncaught.isEmpty(), "잡히지 않은 예외 ${r.uncaught}")
        }
    }

    /** work_tick 이 없는 서버(404 PGRST202): 이 실행 동안 끄고 레거시 하트비트 + 기기 행 + 팀 상태 4 GET 으로 같은 틱에 펼친다. */
    @Test
    fun missingWorkTickFallsBackToLegacyHeartbeatInTheSameTick() = runTest(timeout = 2.minutes) {
        TickRig(this, TickMode.MISSING).use { r ->
            r.app.start(); runCurrent()
            r.signIn()
            advanceInSteps(2.minutes)
            val start = r.nowSeconds
            r.app.work.commands.start(WorkStartOrigin.MANUAL); runCurrent()
            advanceInSteps(30.minutes)
            val end = r.nowSeconds
            val window = r.between(start, end)
            assertEquals(1, window.count { it.isWorkTick }, "404 한 번이면 이 실행 동안 끈다(⑨)")
            val beats = window.filter { it.isLegacyWorkingBeat }
            val gap = maxGap(start, beats.map { it.t }, end)
            assertTrue(gap <= 60, "레거시 하트비트 공백 최대 ${gap}초 (${beats.size}건)")
            assertTrue(
                window.count { it.method == "POST" && it.path.endsWith("/rest/v1/work_status_devices") && it.body.contains(WiringTestRig.DEVICE) } >= 50,
                "기기 행(work_status_devices) 하트비트",
            )
            assertTrue(window.count { it.method == "GET" && it.path.endsWith("/rest/v1/work_statuses") } >= 50, "폴백 팀 상태 GET")
            assertTrue(r.app.work.workTickGate.snapshot.disabledReason != null, "게이트가 꺼졌다")
        }
    }

    /** 과부하(503): 4 GET·away 로 펼치지 않고, 근무 중 하트비트만 120초 간격으로 지킨다(Swift 10-30 안정화와 같은 뜻). */
    @Test
    fun overloadedWorkTickHoldsWithoutFanOutButKeepsSessionAlive() = runTest(timeout = 2.minutes) {
        TickRig(this, TickMode.OVERLOAD).use { r ->
            r.app.start(); runCurrent()
            r.signIn()
            advanceInSteps(2.minutes)
            val start = r.nowSeconds
            r.app.work.commands.start(WorkStartOrigin.MANUAL); runCurrent()
            advanceInSteps(60.minutes)
            val end = r.nowSeconds
            val window = r.between(start, end)
            assertEquals(0, window.count { it.method == "GET" && it.path.endsWith("/rest/v1/work_statuses") }, "과부하 중 팀 GET 펼침 0")
            assertEquals(0, window.count { it.path.endsWith("/rpc/away_sync") }, "과부하 중 away_sync 0")
            // (b) 과부하는 30·60·120·120…초 × 지터(0.8~1.2) 백오프 — 회복 확인 1건이 120초 안팎마다 나간다(1시간 정지 아님).
            val ticks = window.filter { it.isWorkTick }.map { it.t }
            assertTrue(ticks.size in 20..45, "과부하 60분 work_tick ${ticks.size}건 — 백오프 상한 120초×지터마다 한 건이어야 한다")
            val tickGap = maxGap(start, ticks, end)
            assertTrue(tickGap <= 180, "과부하 중 회복 확인(work_tick) 공백 최대 ${tickGap}초 — 상한 120초×1.2 + 슬라이스")
            val gate = r.app.work.workTickGate.snapshot
            assertEquals(0, gate.consecutiveTransientFailures, "과부하는 (c) 정지 카운터에 세지 않는다 — $gate")
            assertEquals(null, gate.suspendedUntil, "과부하로 정지(폴백 고정)에 들어가지 않는다 — $gate")
            val beats = window.filter { it.isLegacyWorkingBeat }
            val gap = maxGap(start, beats.map { it.t }, end)
            assertTrue(gap <= 180, "과부하 중 하트비트 공백 최대 ${gap}초 — 10분 스캐빈저보다 한참 안쪽이어야 한다")
            assertTrue(beats.size <= 60 * 60 / 120 + 2, "과부하 중 하트비트 ${beats.size}건 — 120초에 한 번 이하")
        }
    }

    /**
     * 오프라인 부팅(반박 검증 must_fix 1 · s1): 첫 소속 읽기가 실패해도 틱 루프가 슬라이스마다 소속을 다시 확인한다
     * (Swift confirmMembershipIfNeeded). 망이 붙으면 한 슬라이스 안에 팀이 서고, 근무가 서버에 오르고, 확정 뒤엔 요청 0.
     */
    @Test
    fun offlineBootRecoversMembershipWithinOneSliceSoWorkReachesServer() = runTest(timeout = 2.minutes) {
        TickRig(this, TickMode.OK).use { r ->
            r.membershipFail = true
            r.app.start(); runCurrent()
            r.signIn()
            advanceInSteps(1.minutes, 10.seconds)
            assertEquals(null, r.app.sessionStore.profile?.teamID, "전제: 첫 소속 읽기가 실패해 팀이 비었다")
            r.membershipFail = false
            val back = r.nowSeconds
            advanceInSteps(40.seconds, 10.seconds)
            assertEquals(WiringTestRig.TEAM, r.app.sessionStore.profile?.teamID, "망이 붙은 뒤 한 슬라이스(30초) 안에 팀이 선다")
            val start = r.nowSeconds
            r.app.work.commands.start(WorkStartOrigin.MANUAL); runCurrent()
            advanceInSteps(40.minutes)
            val end = r.nowSeconds
            val window = r.between(start, end)
            assertTrue(window.any { it.method == "POST" && it.path.endsWith("/rest/v1/work_sessions") }, "근무 세션이 서버에 오른다")
            val beats = window.filter { it.carriesHeartbeat }
            val gap = maxGap(start, beats.map { it.t }, end)
            assertTrue(gap <= 60, "하트비트 공백 최대 ${gap}초 (${beats.size}건) — 팀이 서야 work_tick 이 하트비트를 싣는다")
            val later = r.between(back + 31, end).count { it.path.endsWith("/rest/v1/memberships") }
            assertEquals(0, later, "소속이 확정되면 소속 확인 요청 0")
            assertTrue(r.uncaught.isEmpty(), "잡히지 않은 예외 ${r.uncaught}")
        }
    }

    /** 오프라인 부팅 중에 시작한 근무(큐에 noTeam 으로 남음)는 망이 붙은 그 틱에 재생된다 — 팀 확정이 큐 드레인보다 앞이다. */
    @Test
    fun workStartedDuringOfflineBootReplaysOnTheTickAfterMembershipRecovers() = runTest(timeout = 2.minutes) {
        TickRig(this, TickMode.OK).use { r ->
            r.membershipFail = true
            r.app.start(); runCurrent()
            r.signIn()
            advanceInSteps(20.seconds, 10.seconds)
            r.app.work.commands.start(WorkStartOrigin.MANUAL); runCurrent()
            advanceInSteps(40.seconds, 10.seconds)
            assertEquals(0, r.count("/rest/v1/work_sessions", "POST"), "전제: 팀이 없어 근무가 서버에 못 올랐다")
            r.membershipFail = false
            val back = r.nowSeconds
            advanceInSteps(10.minutes, 10.seconds)
            val post = r.between(back, r.nowSeconds).firstOrNull { it.method == "POST" && it.path.endsWith("/rest/v1/work_sessions") }
            assertTrue(post != null && post.t - back <= 31, "망이 붙은 다음 틱(≤30초)에 근무 세션이 오른다 — ${post?.t?.minus(back)}초")
            val beats = r.between(post.t, r.nowSeconds).filter { it.carriesHeartbeat }
            val gap = maxGap(post.t, beats.map { it.t }, r.nowSeconds)
            assertTrue(gap <= 60, "하트비트 공백 최대 ${gap}초")
            assertTrue(r.working)
        }
    }

    /**
     * 과부하·도달 불가 100초(반박 검증 must_fix 2 · s2): 회복 확인 work_tick 이 백오프 상한(120초×지터) 안에 돌아오고, 서버가
     * 그새 닫은 세션을 그 틱에 안다. (b) 는 (c) 정지 카운터에 세지 않는다 — 1시간 정지로 빠지지 않는다.
     */
    @Test
    fun overloadBlipResumesWorkTickWithinBackoffCap() = runTest(timeout = 2.minutes) { blipResumes(TickMode.OVERLOAD) }

    @Test
    fun transportBlipResumesWorkTickWithinBackoffCap() = runTest(timeout = 2.minutes) { blipResumes(TickMode.TRANSPORT) }

    private suspend fun TestScope.blipResumes(mode: TickMode) {
        TickRig(this, TickMode.OK).use { r ->
            r.app.start(); runCurrent()
            r.signIn()
            advanceInSteps(2.minutes)
            r.app.work.commands.start(WorkStartOrigin.MANUAL); runCurrent()
            advanceInSteps(5.minutes)
            val blipAt = r.nowSeconds
            r.mode = mode
            advanceInSteps(100.seconds, 10.seconds)
            r.mode = TickMode.OK
            r.ownOff = true
            val rec = r.nowSeconds
            var learnedAt: Long? = null
            repeat(30) {
                advanceInSteps(10.seconds, 10.seconds)
                if (learnedAt == null && !r.working) learnedAt = r.nowSeconds
            }
            val during = r.between(blipAt, rec)
            assertEquals(0, during.count { it.method == "GET" && it.path.endsWith("/rest/v1/work_statuses") }, "깜빡임 중 팀 GET 펼침 0")
            assertEquals(0, during.count { it.path.endsWith("/rpc/away_sync") }, "깜빡임 중 away_sync 0")
            val first = r.between(rec + 1, r.nowSeconds).firstOrNull { it.isWorkTick }?.t
            assertTrue(first != null && first - rec <= 180, "회복 뒤 첫 work_tick +${first?.minus(rec)}초 — 백오프 상한 120초×1.2 + 슬라이스 안")
            assertTrue(learnedAt != null && learnedAt!! - rec <= 210, "서버가 닫은 세션을 +${learnedAt?.minus(rec)}초에 알았다")
            val gate = r.app.work.workTickGate.snapshot
            assertEquals(null, gate.suspendedUntil, "과부하·도달 불가는 1시간 정지를 걸지 않는다 — $gate")
            assertTrue(r.uncaught.isEmpty(), "잡히지 않은 예외 ${r.uncaught}")
        }
    }

    /** 로그인하면 client_devices 에 'windows' 행을 올린다(울트라 밑바닥 1 · Windows 빌드 축). 로그아웃은 그 행을 지운다. */
    @Test
    fun signInRegistersWindowsClientDeviceRow() = runTest(timeout = 1.minutes) {
        TickRig(this, TickMode.OK).use { r ->
            r.app.start(); runCurrent()
            r.signIn()
            advanceInSteps(1.minutes)
            val regs = r.requests.filter { it.path.endsWith("/rpc/register_device") }
            assertEquals(1, regs.size, "로그인 한 번에 register_device 한 번")
            val body = regs.single().body
            assertTrue(body.contains("\"p_platform\":\"windows\""), body)
            assertTrue(body.contains("\"p_installation_id\":\"${WiringTestRig.INSTALLATION}\""), "work_tick 의 'win:'||inst 와 같은 설치 id — $body")
            val build = Regex("\"p_app_build\":(\\d+)").find(body)?.groupValues?.get(1)?.toLong()
            assertTrue(build != null && build >= 1, "ultra_windows_floor_build 는 app_build ≥ 1 을 본다 — $body")
            assertTrue(!body.contains("p_apns"), "Windows 는 푸시 토큰이 없다 — $body")
            assertEquals(0, r.count("/rpc/register_device_fcm"))

            r.scope.launch { r.app.sessionStore.signOut() }
            advanceInSteps(1.minutes)
            assertEquals(1, r.count("/rpc/unregister_device"), "로그아웃 정리가 이 설치의 행을 지운다")
        }
    }

    /** 설치 식별자를 확인하지 못했으면 기기 행을 올리지 않는다(지어낸 신원 금지). */
    @Test
    fun noInstallationIdentityMeansNoDeviceRow() = runTest(timeout = 1.minutes) {
        TickRig(this, TickMode.OK, installation = null).use { r ->
            r.app.start(); runCurrent()
            r.signIn()
            advanceInSteps(1.minutes)
            assertEquals(0, r.count("/rpc/register_device"))
        }
    }
}
