// 원본: Sources/CheckCore/TetrisDuelStore.swift:607-610(`defaults` — 앱 배선이 넣는다 · nil 이면 프로세스 안에만) · :1092(신청 ok)·:1170(수락 ok
//       → noteOwnsMatch) · TetrisDuelStoreGame.swift:332-333(사용자별 키)·:406(UserDefaults.set — cfprefsd 가 지켜 강제 종료에도 남는다)
//       (vc3 한 판 한 기기 — check 개발 부탁 ①: Windows AppGraph `tetris.defaults = prefs`)
//
// 같은 kv 폴더(FileDesktopKeyValueStore.inDataDir — 앱이 쓰는 그 자리)로 AppGraph 를 두 번 조립한다:
//   1) 첫 그래프 — 로그인 → 수락(tetris_respond, 옛 서버: my_device 없음) → 이 기기가 연 판 기록.
//   2) 앱을 닫거나(정상 종료: kv close) 강제 종료(닫지 않음 — 묶음 창 60초 안) → 같은 폴더로 둘째 그래프 → 같은 사람 로그인
//      → my_device 없는 옛 판 상태(tetris_state)를 받는다 → 이 기기가 두는 판(playingElsewhere=false · 구동기 생성).
//   ★ 기준선: 기록 없는 새 폴더로 선 그래프(같은 사람 · 같은 응답)는 안 둔다 — 위 '둔다' 가 기록 덕이지 기본값이 아니다.
//   3) 계정 전환(A → B)·로그아웃: 앱을 실제처럼 start 하고 A 가 판을 세운 뒤 바꾸면 판·구동기·오목/체스 상태가 내려간다
//      (맥 Sources/check/WorkTimerStore.swift:4120-4126 · :4265-4267 의 gomoku/chess/tetris.reset() — 데스크톱 AppGraph 의 로그아웃 리스너).
// 망은 MockEngine(`.invalid`)뿐 · 픽스처는 합성.
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
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelPhase
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.ownsMatch
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.desktop.AppGraph
import com.yehsung.aingcheck.desktop.AppSeams
import com.yehsung.aingcheck.desktop.AppWirings
import com.yehsung.aingcheck.desktop.DesktopPlatform
import com.yehsung.aingcheck.desktop.SilentCharacterSink
import com.yehsung.aingcheck.desktop.overlay.engine.FakeMeasure
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsKeys
import com.yehsung.aingcheck.desktop.platform.windows.store.FileDesktopKeyValueStore
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutScreen
import com.yehsung.aingcheck.desktop.shell.flyout.SyntheticScreen
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitReadOutcome
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitRunner
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockEngineConfig
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.Executor
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

private class OwnershipPlatform : DesktopPlatform {
    override val paths = object : AppPaths {
        override val dataDir: String = Files.createTempDirectory("own-data").toFile().apply { deleteOnExit() }.path
        override val cacheDir = "C"; override val logDir = "L"; override val userHome = "H"
    }
    override val env = object : EnvReader { override fun get(name: String): String? = null }
    override val tokenVault: TokenVault = InMemoryTokenVault()
    override val installationIdentity = object : InstallationIdentity {
        override fun installationId(): String = WiringTestRig.INSTALLATION
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

/** 옛 서버(my_device 를 싣지 않는다) — 수락은 판을 active 로, 상태는 그 판을 그대로 돌려준다. */
private object OldServer {
    const val MATCH = "7e7e0000-0000-4000-8000-0000000000b1"
    const val PEER = "d0000000-0000-4000-8000-0000000000ee"
    /** 계정 전환 뒤 같은 기기에 들어오는 다음 사람(합성). */
    const val NEXT_USER = "b0000000-0000-4000-8000-0000000000bb"
    val nowMs: Long get() = WiringTestRig.BASE_MS

    fun state(): String =
        """{"match_id":"$MATCH","status":"active","stake":3,"seed":4242,"server_now_ms":$nowMs,"accepted_at_ms":${nowMs - 2_000},""" +
            """"ready_deadline_ms":${nowMs + 28_000},""" +
            """"me":{"id":"${WiringTestRig.USER}","display_name":"나","ready":false,"seq":0},""" +
            """"opponent":{"id":"$PEER","display_name":"라이벌","ready":false,"seq":0},"ruby_balance":97}"""
}

/** 앱 한 벌(같은 kv 를 받는다). [close] = 배선 범위만 걷는다 — kv 를 닫을지(정상 종료)는 시험이 정한다. */
private class OwnershipRig(val test: TestScope, val kv: FileDesktopKeyValueStore) {
    val requests = mutableListOf<String>()
    /** B 의 토큰으로 나간 요청 경로(계정 전환 시험이 본다). */
    val nextUserPaths = mutableListOf<String>()
    val hosts = mutableSetOf<String>()
    val uncaught = mutableListOf<Throwable>()
    private val engine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(test.testScheduler)
            addHandler { request ->
                hosts += request.url.host
                val p = request.url.encodedPath
                requests += p
                val json = headersOf(HttpHeaders.ContentType, "application/json")
                // 다음 사람(B)의 서버 몫엔 판이 없다 — B 세션에 판이 보이면 그건 앞 사람(A)의 것이 남은 것이다.
                val nextUser = request.headers[HttpHeaders.Authorization].orEmpty().contains(OldServer.NEXT_USER)
                if (nextUser) nextUserPaths += p
                when {
                    nextUser && p.contains("/rpc/tetris_") ->
                        respond(
                            """{"status":"ok","server_now_ms":${OldServer.nowMs},"me":{"ruby_balance":5,"wins":0,"losses":0,"draws":0,""" +
                                """"active_match_id":null,"incoming":[]},"users":[],"matches":[]}""",
                            HttpStatusCode.OK, json,
                        )
                    p.endsWith("/rpc/tetris_respond") ->
                        respond("""{"status":"ok","accepted":true,"state":${OldServer.state()},"server_now_ms":${OldServer.nowMs}}""", HttpStatusCode.OK, json)
                    p.endsWith("/rpc/tetris_state") ->
                        respond("""{"status":"ok","state":${OldServer.state()},"server_now_ms":${OldServer.nowMs}}""", HttpStatusCode.OK, json)
                    p.endsWith("/rpc/tetris_lobby") ->
                        respond(
                            """{"status":"ok","server_now_ms":${OldServer.nowMs},"me":{"ruby_balance":97,"wins":0,"losses":0,"draws":0,""" +
                                """"active_match_id":"${OldServer.MATCH}","incoming":[]},"users":[],"matches":[]}""",
                            HttpStatusCode.OK, json,
                        )
                    p.endsWith("/rpc/take_pokes") -> respond("[]", HttpStatusCode.OK, json)
                    else -> respond("""{"code":"PGRST202","message":"no fixture"}""", HttpStatusCode.NotFound, json)
                }
            }
        },
    )
    val graph = AppGraph(
        platform = OwnershipPlatform(),
        clock = object : Clock {
            override fun now(): Instant = Instant.fromEpochMilliseconds(WiringTestRig.BASE_MS + test.testScheduler.currentTime)
        },
        monotonic = object : MonotonicClock {
            override fun elapsedNanos(): Long = test.testScheduler.currentTime * 1_000_000
        },
        desktopConfig = DesktopAppConfig(duels = true),
        backend = AppGraph.Backend("https://ownership.invalid", "stub-anon-key"),
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
            keyValueStore = kv,
        ),
        scope,
    )
    val tetris: TetrisDuelStore get() = app.tetris

    fun signIn() = app.sessionStore.adoptSignedInSession(
        SupabaseSession("tok-${WiringTestRig.USER}", "ref-${WiringTestRig.USER}", WiringTestRig.USER),
        "own@aing.example",
    )

    fun close() = job.cancel()
}

class TetrisOwnershipRestartTest {
    private val dirs = mutableListOf<Path>()
    private val opened = mutableListOf<FileDesktopKeyValueStore>()

    @AfterTest
    fun cleanup() {
        opened.forEach { runCatching { it.close() } }
        dirs.forEach { it.toFile().deleteRecursively() }
    }

    /** 앱 자리 kv(즉시 쓰기 키·머리 그대로 · 묶음 창 60초 — 시험 중엔 예약 쓰기가 오지 않는다). */
    private fun appKv(dir: Path): FileDesktopKeyValueStore =
        FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }

    private fun newDir(): Path = Files.createTempDirectory("tetris-own-kv").also { dirs.add(it) }

    private fun onDisk(kv: FileDesktopKeyValueStore): Map<String, String> =
        if (Files.exists(kv.file)) FileDesktopKeyValueStore.decode(Files.readString(kv.file)) else emptyMap()

    private val key = TetrisDuelStore.ownedMatchesKey(WiringTestRig.USER)

    /** 첫 실행: 수락 → 이 기기가 연 판 기록이 앱 kv 에 선다. */
    private fun TestScope.firstRunAccepts(dir: Path): Pair<OwnershipRig, FileDesktopKeyValueStore> {
        val kv = appKv(dir)
        // 첫 실행 화면을 이미 지난 설치(동의·자동 실행 값이 있다).
        kv.putBoolean(DesktopSettingsKeys.AI_TOOL_DATA_CONSENT, false)
        kv.putBoolean(DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF, false)
        val first = OwnershipRig(this, kv)
        first.signIn()
        runCurrent()
        return first to kv
    }

    private suspend fun TestScope.accept(rig: OwnershipRig) {
        rig.tetris.respond(OldServer.MATCH, accept = true)
        runCurrent()
        assertNotNull(rig.tetris.duel, "전제: 수락한 첫 그래프가 판을 세웠다")
        assertTrue(rig.tetris.ownsMatch(OldServer.MATCH), "전제: 수락 기록")
        assertTrue(rig.kv.getString(key)?.contains("\"${OldServer.MATCH}\"") == true, "수락 기록이 앱 kv 에 안 남았다(defaults 배선이 없다)")
    }

    /** 다시 켠 앱: 같은 사람 로그인 → my_device 없는 판 상태 → 둔다. */
    private suspend fun TestScope.secondRunPlays(kv: FileDesktopKeyValueStore): OwnershipRig {
        val again = OwnershipRig(this, kv)
        again.signIn()
        runCurrent()
        assertTrue(again.tetris.ownsMatch(OldServer.MATCH), "다시 켠 앱이 '이 기기가 연 판' 기록을 못 읽었다")
        again.tetris.refreshMatch(OldServer.MATCH)
        runCurrent()
        assertEquals(OldServer.MATCH, again.tetris.match?.id, "전제: 판 상태를 받았다")
        assertFalse(again.tetris.playingElsewhere, "다시 켠 앱이 자기 판을 '다른 기기 판'으로 읽었다")
        assertNotNull(again.tetris.duel, "다시 켠 앱이 자기 판에 구동기를 안 세웠다")
        assertTrue(again.requests.any { it.endsWith("/rpc/tetris_state") }, "판 상태 요청이 안 나갔다")
        assertTrue(again.hosts.all { it == "ownership.invalid" }, "망은 MockEngine 의 .invalid 만: ${again.hosts}")
        return again
    }

    /** ★ 기준선: 기록 없는 새 폴더(같은 사람 · 같은 옛 서버 응답)는 안 둔다. */
    private suspend fun TestScope.strangerDoesNotPlay() {
        val stranger = OwnershipRig(this, appKv(newDir()))
        stranger.signIn()
        runCurrent()
        stranger.tetris.refreshMatch(OldServer.MATCH)
        runCurrent()
        assertEquals(OldServer.MATCH, stranger.tetris.match?.id)
        assertTrue(stranger.tetris.playingElsewhere && stranger.tetris.duel == null, "기록 없는 기기가 판을 뒀다 — 위 '둔다' 가 기본값이다")
        stranger.tetris.reset()
        stranger.close()
    }

    @Test
    fun acceptedMatchIsStillThisDevicesAfterAQuitAndRelaunch() = runTest {
        val dir = newDir()
        val (first, kv) = firstRunAccepts(dir)
        try {
            accept(first)
        } finally {
            first.tetris.reset()
            first.close()
        }
        kv.close() // 정상 종료(조정자 종료 단계 kv.flush)
        val again = secondRunPlays(appKv(dir))
        assertTrue(first.uncaught.isEmpty() && again.uncaught.isEmpty(), "잡히지 않은 예외: ${first.uncaught + again.uncaught}")
        again.tetris.reset()
        again.close()
        strangerDoesNotPlay()
    }

    /** 강제 종료(묶음 창 안 — kv 를 닫지 않는다): 기록 키는 즉시 쓰기 머리라 이미 디스크에 있다(맥 cfprefsd 몫). */
    @Test
    fun acceptedMatchSurvivesAForceKillInsideTheDebounceWindow() = runTest {
        val dir = newDir()
        val (first, kv) = firstRunAccepts(dir)
        try {
            accept(first)
            assertTrue(kv.isImmediate(key), "기록 키가 즉시 쓰기가 아니다: $key")
            assertTrue(onDisk(kv)[key]?.contains("\"${OldServer.MATCH}\"") == true, "수락 직후 디스크에 기록이 없다 — 강제 종료면 잃는다")
            // 음성 대조: 묶음 키(창 자리 같은 것)는 60초 묶음 창 안에선 아직 디스크에 없다 — 위 '있다' 가 즉시 쓰기 덕이다.
            kv.putString("check.overlay.position", "1,2")
            assertNull(onDisk(kv)["check.overlay.position"], "묶음 키가 바로 쓰였다 — 즉시 쓰기 판정이 눈이 멀었다")
        } finally {
            first.tetris.reset()
            first.close()
        }
        // kv 를 닫지 않고(flush 없음) 같은 파일로 새 실행.
        val again = secondRunPlays(appKv(dir))
        again.tetris.reset()
        again.close()
        strangerDoesNotPlay()
    }

    /**
     * 즉시 쓰기 머리는 점까지 — `tetris.duel.ownedMatches.` 로 끝난다. 머리가 점을 잃으면 이름이 비슷한 다른 키
     * (`…ownedMatchesBackup` 같은 것)까지 즉시 쓰기로 잡아 묶음 창이 무너진다. 사용자 id 가 붙은 키만 잡는다.
     */
    @Test
    fun immediatePrefixCatchesOnlyPerUserOwnedMatchKeys() {
        assertEquals(setOf("tetris.duel.ownedMatches."), FileDesktopKeyValueStore.WORK_IMMEDIATE_KEY_PREFIXES)
        val kv = appKv(newDir())
        assertTrue(kv.isImmediate(key), "사용자별 기록 키가 즉시 쓰기가 아니다: $key")
        assertTrue(kv.isImmediate(TetrisDuelStore.ownedMatchesKey("Other-User")), "다른 사용자 기록 키도 즉시 쓰기여야 한다")
        for (near in listOf("tetris.duel.ownedMatches", "tetris.duel.ownedMatchesBackup", "tetris.duel.ownedMatch.x", "tetris.duel.hold", "tetris.lobby")) {
            assertFalse(kv.isImmediate(near), "머리가 비슷한 다른 키를 즉시 쓰기로 잡았다: $near")
        }
    }

    /**
     * 계정에 묶인 게임 상태 중 남은 것(맥 WorkTimerStore.swift:4120-4126 로그아웃 · :4265-4267 adoptWorkStateOwner 가
     * gomoku/chess/tetris.reset() 으로 내리는 것 — 폰 PhoneAppModel.kt sessionDidSignOut 도 같다).
     */
    private fun leftovers(rig: OwnershipRig): List<String> = buildList {
        val t = rig.tetris
        if (t.match != null) add("tetris.match=${t.match?.id}")
        if (t.duel != null) add("tetris.duel(구동기)")
        if (t.phase != TetrisDuelPhase.lobby) add("tetris.phase=${t.phase}")
        if (rig.app.gomoku.notice != null) add("gomoku.notice")
        if (rig.app.chess.notice != null) add("chess.notice")
    }

    /**
     * 실제 앱처럼 시작(AppWirings.start — social 이 로그인 변화를 보고 onSignedOut 사슬을 낸다) → A 로그인 → A 가 판을 세우고
     * (수락 → 구동기) 오목·체스에도 A 의 안내가 떠 있다.
     */
    private suspend fun TestScope.startedWithASeated(): Pair<OwnershipRig, FileDesktopKeyValueStore> {
        val kv = appKv(newDir())
        kv.putBoolean(DesktopSettingsKeys.AI_TOOL_DATA_CONSENT, false)
        kv.putBoolean(DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF, false)
        val rig = OwnershipRig(this, kv)
        rig.app.start()
        runCurrent()
        rig.signIn()
        runCurrent()
        seatA(rig)
        return rig to kv
    }

    private suspend fun TestScope.seatA(rig: OwnershipRig) {
        accept(rig)
        rig.app.gomoku.notice = "A 의 오목 안내"
        rig.app.chess.notice = "A 의 체스 안내"
        assertEquals(5, leftovers(rig).size, "전제: A 의 판·구동기·단계·오목·체스가 다 서 있다 — ${leftovers(rig)}")
    }

    /**
     * 계정 전환(A → B 직행): 앞 사람의 판·구동기·오목/체스 상태를 내린다. 남기면 A 의 판이 B 세션에서 '이 기기가 두는 판'으로
     * 남고 그 판 루프가 B 의 토큰으로 보고를 낸다(맥 :4122-4123 주석). 영속 기록('이 기기가 연 판')은 사용자별 키라 A 몫으로 남는다.
     */
    @Test
    fun accountSwitchDropsThePreviousPersonsGames() = runTest {
        val (rig, kv) = startedWithASeated()
        try {
            rig.app.sessionStore.adoptSignedInSession(
                SupabaseSession("tok-${OldServer.NEXT_USER}", "ref-${OldServer.NEXT_USER}", OldServer.NEXT_USER),
                "next@aing.example",
            )
            advanceTimeBy(5_000)
            runCurrent()
            assertEquals(OldServer.NEXT_USER, rig.app.sessionStore.session?.userID, "전제: B 로 바뀌었다")
            val left = leftovers(rig)
            assertTrue(left.isEmpty(), "계정 전환 뒤 앞 사람(A)의 것이 B 에게 남았다: $left")
            assertFalse(rig.tetris.ownsMatch(OldServer.MATCH), "B 가 A 의 '이 기기가 연 판' 기록을 가졌다")
            assertTrue(kv.getString(key)?.contains("\"${OldServer.MATCH}\"") == true, "A 의 영속 기록(사용자별 키)이 지워졌다 — reset 이 기록까지 걷었다")
            assertTrue(rig.uncaught.isEmpty(), "잡히지 않은 예외: ${rig.uncaught}")
        } finally {
            rig.tetris.reset()
            rig.close()
        }
    }

    /** 로그아웃: 같은 사슬 — 판·구동기·오목/체스 상태를 내린다(맥 WorkTimerStore.swift:4120-4126). */
    @Test
    fun signOutDropsTheGames() = runTest {
        val (rig, _) = startedWithASeated()
        try {
            rig.scope.launch { rig.app.sessionStore.signOut() }
            advanceTimeBy(5_000)
            runCurrent()
            assertNull(rig.app.sessionStore.session, "전제: 로그아웃했다")
            val left = leftovers(rig)
            assertTrue(left.isEmpty(), "로그아웃 뒤 앞 사람의 것이 남았다: $left")
            assertTrue(rig.uncaught.isEmpty(), "잡히지 않은 예외: ${rig.uncaught}")
        } finally {
            rig.tetris.reset()
            rig.close()
        }
    }
}
