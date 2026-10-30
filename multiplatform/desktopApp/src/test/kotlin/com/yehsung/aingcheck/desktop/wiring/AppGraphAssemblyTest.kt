// 본 통합 조립(W-6 #6) 시험: AppGraph.assemble 이 배선 여섯을 가짜 OS·MockEngine 위에서 headless 로 만들고 → start → 종료 순서 한 벌을
// 돈다. 종료 순서는 단계 이름과 부작용(트레이·전원 구독) 녹음으로 단언한다. 픽스처는 합성뿐 — 망은 MockEngine(`.invalid`)만 받는다.
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
import com.yehsung.aingcheck.desktop.AppGraph
import com.yehsung.aingcheck.desktop.AppSeams
import com.yehsung.aingcheck.desktop.AppWirings
import com.yehsung.aingcheck.desktop.DesktopPlatform
import com.yehsung.aingcheck.desktop.ShutdownSequence
import com.yehsung.aingcheck.desktop.ShutdownStep
import com.yehsung.aingcheck.desktop.SilentCharacterSink
import com.yehsung.aingcheck.desktop.overlay.engine.FakeMeasure
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleKind
import com.yehsung.aingcheck.desktop.overlay.engine.ClickAction
import com.yehsung.aingcheck.desktop.overlay.engine.DuelAttention
import com.yehsung.aingcheck.desktop.overlay.engine.DuelAttentionKind
import com.yehsung.aingcheck.desktop.overlay.engine.DuelGame
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayView
import com.yehsung.aingcheck.desktop.overlay.engine.PointerOutcome
import com.yehsung.aingcheck.desktop.overlay.engine.HitTarget
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayMode
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayPoint
import com.yehsung.aingcheck.desktop.overlay.engine.PointerKind
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfacePresenter
import com.yehsung.aingcheck.desktop.shellapi.Entry
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.stores.gomoku.GomokuInvite
import com.yehsung.aingcheck.core.stores.gomoku.GomokuMatchState
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.desktop.shellapi.NotifySurface
import com.yehsung.aingcheck.desktop.todo.TodoQuarantineLog
import com.yehsung.aingcheck.desktop.windows.kit.DuelInviteNotice
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import java.nio.file.Files
import com.yehsung.aingcheck.desktop.platform.windows.display.DisplayChangeSource
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
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import java.nio.file.Path
import java.util.concurrent.Executor
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsKeys
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

/** 부작용 녹음 플랫폼: 트레이 show/remove · 전원 구독 열고 닫기를 한 줄 장부에 적는다. */
private class RecordingPlatform(val log: MutableList<String>, dataDir: Path) : DesktopPlatform {
    // 할 일 목록(TodoWiring)이 dataDir 아래 todos.<계정>.json 을 쓴다 — 저장소 안 상대 경로("D")에 흘리지 않게 임시 폴더(시험 끝에 통째로 지운다 — TempDataDirs).
    override val paths = object : AppPaths {
        override val dataDir: String = dataDir.toString()
        override val cacheDir = "C"; override val logDir = "L"; override val userHome = "H"
    }
    override val env = object : EnvReader { override fun get(name: String): String? = null }
    override val tokenVault: TokenVault = InMemoryTokenVault()
    override val installationIdentity = object : InstallationIdentity {
        override fun installationId(): String = WiringTestRig.INSTALLATION
    }
    override val singleInstance = object : SingleInstanceGuard { override fun tryAcquire() = true; override fun release() {} }
    override val tray = object : TrayHost {
        override fun show(icon: RasterImage, tooltip: String) { log += "tray.show" }
        override fun update(icon: RasterImage, tooltip: String) {}
        override fun remove() { log += "tray.remove" }
        override fun addClickListener(listener: (click: TrayClick, screenX: Int, screenY: Int) -> Unit) =
            Registration { log += "tray.click.close" }
    }
    override val hotkeys = object : HotkeyService {
        override fun register(chord: HotkeyChord, onPressed: () -> Unit) = HotkeyRegistrationResult.Conflict(0)
    }
    override val idle = FakeIdle()
    var powerOpen = 0
    override val power = object : PowerEvents {
        override fun addListener(listener: (PowerEvent) -> Unit): Registration {
            powerOpen++
            return Registration { powerOpen--; log += "power.close" }
        }
    }
    override val session = FakeSessionEvents()
    override val loginItem: LoginItem? = null
}

private class AssemblyRig(
    val test: TestScope,
    dirs: TempDataDirs,
    config: DesktopAppConfig = DesktopAppConfig(),
    kv: DesktopKeyValueStore = InMemoryDesktopKeyValueStore(),
    val gameWindows: FakeGameFactory = FakeGameFactory(),
    overlayPresenter: OverlayPresenter = OverlayPresenter.None,
    /** 조립 전에 dataDir 를 채운다(할 일 손상 파일 등 — 합성만). */
    prepareDataDir: (Path) -> Unit = {},
) {
    val log = mutableListOf<String>()
    val hosts = mutableSetOf<String>()
    val requests = mutableListOf<String>()
    val uncaught = mutableListOf<Throwable>()
    val dataDir: Path = dirs.new("asm-data").also(prepareDataDir)
    val platform = RecordingPlatform(log, dataDir)
    val port = FakeWindowPort()
    var displayOpen = 0
    private val engine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(test.testScheduler)
            addHandler { request ->
                hosts += request.url.host
                requests += request.url.encodedPath
                if (request.url.encodedPath.endsWith("/rpc/take_pokes")) {
                    respond("[]", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
                } else {
                    respond("""{"code":"PGRST202","message":"no fixture"}""", HttpStatusCode.NotFound, headersOf(HttpHeaders.ContentType, "application/json"))
                }
            }
        },
    )
    val graph = AppGraph(
        platform = platform,
        clock = object : Clock {
            override fun now(): Instant = Instant.fromEpochMilliseconds(WiringTestRig.BASE_MS + test.testScheduler.currentTime)
        },
        monotonic = object : MonotonicClock {
            override fun elapsedNanos(): Long = test.testScheduler.currentTime * 1_000_000
        },
        desktopConfig = config,
        backend = AppGraph.Backend("https://assembly.invalid", "stub-anon-key"),
        osVersion = "Windows 11",
        httpFactory = { configure -> HttpClient(engine) { configure() } },
    )
    private val job = SupervisorJob()
    val scope = CoroutineScope(test.coroutineContext.minusKey(Job) + job + CoroutineExceptionHandler { _, e -> uncaught += e })
    val seams = AppSeams(
        events = Executor { it.run() },
        mainDispatcher = StandardTestDispatcher(test.testScheduler),
        window = port,
        screen = FlyoutScreen { SyntheticScreen.facts },
        characterSink = SilentCharacterSink(),
        bubbleMeasure = FakeMeasure(),
        gameWindows = gameWindows,
        overlayPresenter = overlayPresenter,
        homes = DesktopAiHomes(Path.of("synthetic-home")) { Path.of("synthetic-home", ".codex") },
        tokenCacheFile = null,
        aiLimitRunner = AILimitRunner { _, _ -> AILimitReadOutcome(emptyMap()) },
        codexAccountRunner = { _ -> awaitCancellation() },
        computeDiagnostics = { _, _ -> null },
        runningTests = object : RunningTests { override val isRunningTests: Boolean = true },
        keyValueStore = kv,
        displayChanges = DisplayChangeSource { listener ->
            displayOpen++
            Registration { displayOpen-- }
        },
    )
    val app: AppWirings = graph.assemble(seams, scope)

    fun close() = job.cancel()
}

class AppGraphAssemblyTest {
    /** 시험마다 임시 dataDir — 끝나면 안의 todos.*.json·로그째 지운다(deleteOnExit 는 빈 폴더만 지운다). */
    private val dirs = TempDataDirs()

    @AfterTest
    fun removeDataDirs() = dirs.close()

    /** W-6 #6: 조립 → 시작 → 종료 한 벌(실패해도 리그를 닫는다 — 안 닫으면 틱 루프가 가상 시계를 끝없이 돌려 runTest 가 멈춘다). 근무 마무리가 맨 앞, 실시간 shutdown 뒤에 껍데기, tray.remove 가 맨 끝. */
    @Test
    fun assembledGraphStartsThenShutsDownInW6Order() = runTest {
        val r = AssemblyRig(this, dirs)
        try {
            r.app.start()
            advanceTimeBy(5_000)
            runCurrent()
            assertEquals(1, r.port.attached, "shell.start 가 플라이아웃 창을 한 번 잇는다")
            // W-3 #6: 말풍선 큐 한 벌 — 소셜이 쌓은 메시지를 오버레이가 띄운다.
            assertSame(r.app.overlay.bubbles, r.app.social.bubbles, "오버레이·소셜 말풍선 큐가 둘이다")
            assertTrue(r.app.os.isStarted, "os.start 는 shell.start 뒤 start() 안에서")
            // 첫 실행(동의·자동 실행 값 없음): 플라이아웃을 한 번 연다 — 공용 호스트가 첫 실행 화면을 그린다(W-13 #5·#6).
            assertTrue(r.app.pages.firstRun.pending.value, "빈 설정이면 첫 실행 대기")
            assertTrue(r.app.shell.handle.nav.visible.value, "첫 실행이면 start() 가 플라이아웃을 연다")
            assertTrue("tray.show" in r.log, "트레이 첫 그림은 shell.start 몫(고정 Off 아이콘 없음)")
            assertTrue(r.platform.powerOpen > 0, "업데이트·근무·오버레이가 전원 사건을 듣는다")
            // W-14 #4: 화면 바뀜 출처는 overlay.start 가 한 번 열고 overlay.stop 이 거둔다.
            assertEquals(1, r.displayOpen, "오버레이가 화면 바뀜 출처를 듣지 않는다")

            val steps = mutableListOf<String>()
            ShutdownSequence.run(r.app.shutdownSteps(), elapsedMillis = { testScheduler.currentTime }) { name ->
                steps += name
                r.log += "step:$name"
            }
            assertEquals(
                listOf(
                    AppWirings.STEP_WORK_FINISH,
                    AppWirings.STEP_TOKENS_PERSIST,
                    AppWirings.STEP_TOKENS_STOP,
                    AppWirings.STEP_REALTIME_SHUTDOWN,
                    AppWirings.STEP_GAMES_STOP,
                    AppWirings.STEP_TODO_STOP,
                    AppWirings.STEP_OVERLAY_STOP,
                    AppWirings.STEP_WORK_STOP,
                    AppWirings.STEP_OS_STOP,
                    AppWirings.STEP_SHELL_STOP,
                    AppWirings.STEP_KV_FLUSH,
                ),
                steps,
            )
            assertEquals("os.stop", AppWirings.STEP_OS_STOP)
            assertEquals("kv.flush", AppWirings.STEP_KV_FLUSH)
            // 트레이는 껍데기의 맨 끝, kv flush 는 그 뒤(W3-d — 앞 단계들이 kv 에 쓴 뒤).
            assertEquals(listOf("tray.remove", "step:${AppWirings.STEP_KV_FLUSH}"), r.log.takeLast(2), "트레이 → kv flush 가 맨 끝: ${r.log.takeLast(6)}")
            val realtimeAt = r.log.indexOf("step:${AppWirings.STEP_REALTIME_SHUTDOWN}")
            val firstPowerClose = r.log.indexOf("power.close")
            assertTrue(firstPowerClose > realtimeAt, "전원·업데이트 구독은 실시간 shutdown 뒤에 닫힌다: ${r.log}")
            assertEquals(0, r.platform.powerOpen, "종료 뒤 전원 구독 0(할 일 깨어남 구독 포함)")
            assertEquals(0, r.displayOpen, "종료 뒤 화면 바뀜 구독 0")
            assertEquals("todo.stop", AppWirings.STEP_TODO_STOP)
            assertTrue(r.hosts.all { it == "assembly.invalid" }, "망은 MockEngine 의 .invalid 만: ${r.hosts}")
            assertTrue(r.uncaught.isEmpty(), "잡히지 않은 예외: ${r.uncaught}")
        } finally {
            r.close()
        }
    }

    /** W-6 #1: poke=false 면 찌르기 발신을 조립하지 않는다(받기 0 · 보내기 0), 켜면 조립한다. */
    @Test
    fun pokeFlagDecidesWhetherSenderIsAssembled() = runTest {
        val off = AssemblyRig(this, dirs, DesktopAppConfig(poke = false))
        assertFalse(off.app.social.actions.canPoke)
        off.app.start()
        advanceTimeBy(120_000)
        runCurrent()
        assertEquals(0, off.requests.count { it.endsWith("/rpc/take_pokes") }, "poke=false 면 take_pokes 0")
        off.app.shutdownSteps().forEach { if (it is ShutdownStep.Always) it.run() }
        off.close()

        val on = AssemblyRig(this, dirs, DesktopAppConfig(poke = true))
        assertTrue(on.app.social.actions.canPoke)
        on.close()
    }

    /** 첫 실행 화면은 동의·자동 실행 값이 하나라도 없을 때만 — 둘 다 답한 설치는 시작해도 플라이아웃을 열지 않는다. */
    @Test
    fun firstRunOpensFlyoutOnlyWhileSettingsAreUnanswered() = runTest {
        val answered = InMemoryDesktopKeyValueStore().apply {
            putBoolean(DesktopSettingsKeys.AI_TOOL_DATA_CONSENT, false)
            putBoolean(DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF, false)
        }
        val r = AssemblyRig(this, dirs, kv = answered)
        try {
            assertFalse(r.app.pages.firstRun.pending.value, "둘 다 답했으면 첫 실행 아님")
            r.app.start()
            runCurrent()
            assertFalse(r.app.shell.handle.nav.visible.value, "첫 실행이 아니면 시작해도 플라이아웃을 열지 않는다")
            r.app.shutdownSteps().forEach { if (it is ShutdownStep.Always) it.run() }
        } finally {
            r.close()
        }
    }

    /** 전체 상한: 끝나지 않는 Bounded 단계는 상한에서 끊기고, 뒤의 Always 단계(트레이 걷기)는 상한이 지나도 돈다. */
    @Test
    fun budgetCutsBoundedStepsButAlwaysStepsStillRun() = runTest {
        val ran = mutableListOf<String>()
        ShutdownSequence.run(
            listOf(
                ShutdownStep.Bounded("hang", maxMillis = 10_000) { awaitCancellation() },
                ShutdownStep.Bounded("late", maxMillis = 10_000) { ran += "late" },
                ShutdownStep.Always("tray") { ran += "tray" },
            ),
            elapsedMillis = { testScheduler.currentTime },
            budgetMillis = 4_500,
        )
        assertEquals(4_500, testScheduler.currentTime, "상한에서 정확히 끊는다")
        assertEquals(listOf("tray"), ran, "상한이 지나면 Bounded 는 건너뛰고 Always 는 돈다")
    }

    // ───────────────────────── int-w4a polish — 실제 조립 그래프 ─────────────────────────

    /**
     * ①③ 실제 AppGraph: 게임 배선 문(GamesDeps.onInviteArrival → overlay.onDuelInvite · 셸 notifyDuelInvite → overlay.shellBubble)으로
     * 같은 상대·같은 판돈 두 건을 보내면 말풍선이 신청 id 로 정확히 둘. 차례 알림(GamesDeps.onDuelAttention)은 그 판의 말풍선이 되고,
     * 대결 말풍선 클릭 결과(OpenDuel)는 조립의 포인터 문이 게임 창을 그 판 id 로 연다(맥 CheckApp.swift:370·407·443).
     */
    @Test
    fun duelBubblesPairByInviteIdAndAttentionClickOpensThatMatchInAssembledGraph() = runTest {
        val views = ArrayList<OverlayView>()
        val r = AssemblyRig(this, dirs, DesktopAppConfig(duels = true), overlayPresenter = { v, _ -> views += v })
        try {
            r.app.start()
            advanceTimeBy(1_000)
            runCurrent()
            val deps = requireNotNull(r.gameWindows.deps) { "조립이 게임 배선을 짓지 않았다" }
            fun bubbles() = views.mapNotNull { it.bubble }.distinctBy { it.text to it.shownAt }
            val exp = SwiftDate.fromEpochMillis(WiringTestRig.BASE_MS + testScheduler.currentTime + 60_000)
            // int-w4b ②: 말풍선은 띄우기 직전 스토어 사실을 읽는다 — 스토어가 신청을 받은 뒤 알리는 순서(GomokuStore announceNewInvites) 그대로.
            r.app.gomoku.incoming = listOf(synthInvite("inv-1", exp), synthInvite("inv-2", exp))
            r.app.gomoku.match = synthMatch("g-7", moveCount = 3)

            deps.onInviteArrival(DuelGame.GOMOKU, "inv-1", "합성상대", 5, exp)
            deps.onInviteArrival(DuelGame.GOMOKU, "inv-2", "합성상대", 5, exp)
            val n1 = DuelInviteNotice(GameWindowKind.Gomoku, "합성상대", 5, "inv-1")
            val n2 = DuelInviteNotice(GameWindowKind.Gomoku, "합성상대", 5, "inv-2")
            assertEquals(NotifySurface.BUBBLE, r.app.shell.handle.notifyDuelInvite(n1), "캐릭터 켜짐 → 말풍선이 맡는다(토스트 0)")
            assertEquals(NotifySurface.BUBBLE, r.app.shell.handle.notifyDuelInvite(n2))
            advanceTimeBy(40_000)
            runCurrent()
            assertEquals(
                listOf(BubbleKind.Invite(DuelGame.GOMOKU, "inv-1"), BubbleKind.Invite(DuelGame.GOMOKU, "inv-2")),
                bubbles().map { it.kind }.filterIsInstance<BubbleKind.Invite>(),
                "신청 말풍선 정확히 둘: ${bubbles()}",
            )
            assertEquals(0, bubbles().count { it.kind !is BubbleKind.Invite && it.text == n1.body }, "글만 말풍선 0: ${bubbles()}")

            deps.onDuelAttention(DuelAttention(DuelGame.GOMOKU, "g-7", DuelAttentionKind.MY_TURN, "합성상대", 3))
            advanceTimeBy(500)
            runCurrent()
            assertEquals(BubbleKind.Invite(DuelGame.GOMOKU, "g-7"), bubbles().last().kind, "차례 알림 → 그 판 말풍선: ${bubbles()}")

            r.app.overlayPointerOutcome(PointerOutcome(click = ClickAction.Hit))
            assertEquals(emptyList(), r.gameWindows.board.opened, "음성 대조: 때리기 클릭은 창 0")
            r.app.overlayPointerOutcome(PointerOutcome(click = ClickAction.OpenDuel(DuelGame.CHESS, "c-7")))
            r.app.overlayPointerOutcome(PointerOutcome(click = ClickAction.OpenDuel(DuelGame.GOMOKU, "inv-2")))
            assertEquals(listOf("chess:c-7", "gomoku:inv-2"), r.gameWindows.board.opened)
            r.app.shutdownSteps().forEach { if (it is ShutdownStep.Always) it.run() }
        } finally {
            r.close()
        }
    }

    // ───────────────────────── int-w4b overlay2 — 실제 조립 그래프 ─────────────────────────

    /**
     * ① 엿보기(근무 전) 중 대결 말풍선 클릭: 맥은 `shouldBeVisible` 이 거짓이면 클릭 통과 문을 열지 않고(CheckOverlayWindow.swift:729
     * updateHitThrough 가드 · :2224 기본 통과) handleClick(:954)도 같은 가드라 아무것도 열지 않는다. 조립 그래프에서: 엿보기 그림은
     * 창 전체 클릭 통과, 포인터가 와도 판 창 0. 음성 대조 — 같은 결과 문에 OpenDuel 을 넣으면 그 판 창이 열린다(배선이 죽은 0 이 아니다).
     */
    @Test
    fun peekDuelBubbleClickPassesThroughLikeMacInAssembledGraph() = runTest {
        val views = ArrayList<OverlayView>()
        val r = AssemblyRig(this, dirs, DesktopAppConfig(duels = true), overlayPresenter = { v, _ -> views += v })
        try {
            r.app.start()
            advanceTimeBy(1_000)
            runCurrent()
            val deps = requireNotNull(r.gameWindows.deps) { "조립이 게임 배선을 짓지 않았다" }
            val exp = SwiftDate.fromEpochMillis(WiringTestRig.BASE_MS + testScheduler.currentTime + 60_000)
            r.app.gomoku.incoming = listOf(synthInvite("inv-p", exp))
            deps.onInviteArrival(DuelGame.GOMOKU, "inv-p", "합성상대", 5, exp)
            advanceTimeBy(500)
            runCurrent()
            val peek = views.last()
            assertEquals(OverlayMode.Peek, peek.mode, "근무 전 신청 → 엿보기")
            assertEquals(BubbleKind.Invite(DuelGame.GOMOKU, "inv-p"), peek.bubble?.kind)
            assertTrue(OverlaySurfacePresenter.clickThroughFor(peek), "엿보기 그림은 창 전체 클릭 통과(맥 :729 · :2224)")

            r.app.overlay.onPointer(PointerKind.DOWN, OverlayPoint(20.0, 20.0), HitTarget.Bubble)
            r.app.overlay.onPointer(PointerKind.UP, OverlayPoint(20.0, 20.0), HitTarget.Bubble)
            advanceTimeBy(100)
            runCurrent()
            assertEquals(emptyList(), r.gameWindows.board.opened, "엿보기 중 말풍선 클릭 → 판 창 0(맥 handleClick :954)")

            r.app.overlayPointerOutcome(PointerOutcome(click = ClickAction.OpenDuel(DuelGame.GOMOKU, "inv-p")))
            assertEquals(listOf("gomoku:inv-p"), r.gameWindows.board.opened, "음성 대조: OpenDuel 결과는 그 판 창")
            r.app.shutdownSteps().forEach { if (it is ShutdownStep.Always) it.run() }
        } finally {
            r.close()
        }
    }

    /**
     * ② DuelFacts 공급자: 조립의 오버레이는 띄우기 직전 오목 스토어 사실(창 보임·지금 판)을 읽는다(맥 :1375 · :1393-1397 gomokuAttentionIsCurrent).
     * 대조 — 창이 안 보이면 바쁜 말풍선 뒤에 기다리던 차례 말풍선이 뜬다. 본 — 기다리는 사이 판 창이 뜨면(windowDidShow) 버린다,
     * 창을 닫은 뒤라도 기다리는 사이 판이 끝나면 버린다.
     */
    @Test
    fun pendingTurnBubbleIsDroppedOnceTheBoardWindowShowsOrTheMatchEndsInAssembledGraph() = runTest {
        val views = ArrayList<OverlayView>()
        val r = AssemblyRig(this, dirs, DesktopAppConfig(duels = true), overlayPresenter = { v, _ -> views += v })
        try {
            r.app.start()
            advanceTimeBy(1_000)
            runCurrent()
            val deps = requireNotNull(r.gameWindows.deps) { "조립이 게임 배선을 짓지 않았다" }
            fun bubbles() = views.mapNotNull { it.bubble }.distinctBy { it.text to it.shownAt }
            fun turnBubbles() = bubbles().filter { it.kind == BubbleKind.Invite(DuelGame.GOMOKU, "g-7") }
            fun busyThenTurn(inviteId: String, moveCount: Int) {
                val exp = SwiftDate.fromEpochMillis(WiringTestRig.BASE_MS + testScheduler.currentTime + 60_000)
                r.app.gomoku.match = synthMatch("g-7", moveCount)
                r.app.gomoku.incoming = listOf(synthInvite(inviteId, exp))
                deps.onInviteArrival(DuelGame.GOMOKU, inviteId, "합성상대", 5, exp)
                deps.onDuelAttention(DuelAttention(DuelGame.GOMOKU, "g-7", DuelAttentionKind.MY_TURN, "합성상대", moveCount))
                advanceTimeBy(100)
                runCurrent()
                assertEquals(BubbleKind.Invite(DuelGame.GOMOKU, inviteId), bubbles().last().kind, "신청 말풍선이 앞을 막는다: ${bubbles()}")
            }

            busyThenTurn("inv-a", 3)
            advanceTimeBy(40_000)
            runCurrent()
            assertEquals(1, turnBubbles().size, "대조: 창이 안 보이면 기다리던 차례 말풍선이 뜬다: ${bubbles()}")

            busyThenTurn("inv-b", 5)
            r.app.gomoku.windowDidShow()
            advanceTimeBy(40_000)
            runCurrent()
            assertTrue(r.app.gomoku.isWindowVisible)
            assertEquals(1, turnBubbles().size, "판 창을 연 뒤 대기 차례 말풍선 0: ${bubbles()}")

            r.app.gomoku.isWindowVisible = false
            busyThenTurn("inv-c", 7)
            r.app.gomoku.match = synthMatch("g-7", 7, finished = true)
            advanceTimeBy(40_000)
            runCurrent()
            assertEquals(1, turnBubbles().size, "판이 끝난 뒤 대기 차례 말풍선 0: ${bubbles()}")
            r.app.shutdownSteps().forEach { if (it is ShutdownStep.Always) it.run() }
        } finally {
            r.close()
        }
    }

    /**
     * ③ 메시지 도착 말풍선 클릭(OpenMessages) → 플라이아웃의 그 사람 대화(맥 CheckApp.swift:192-199 — `openMessagePanel(peer:from: .overlay)`
     * 뒤 presentMenuPopover). 보낸이를 모르면(nil·빈 문자열 — WorkTimerStoreMessages.swift:266-271) 콕 목록. 음성 대조 — 때리기 클릭은 창 0.
     */
    @Test
    fun messageArrivalBubbleClickOpensThatConversationInAssembledGraph() = runTest {
        val r = AssemblyRig(this, dirs, DesktopAppConfig(poke = true))
        try {
            r.app.start()
            advanceTimeBy(1_000)
            runCurrent()
            val nav = r.app.shell.handle.nav
            nav.hide()
            r.app.overlayPointerOutcome(PointerOutcome(click = ClickAction.Hit))
            assertFalse(nav.visible.value, "음성 대조: 때리기 클릭은 플라이아웃을 열지 않는다")

            r.app.overlayPointerOutcome(PointerOutcome(click = ClickAction.OpenMessages("u-1")))
            assertTrue(nav.visible.value, "말풍선 클릭은 플라이아웃을 연다(맥 presentMenuPopover)")
            assertEquals(FlyoutRoute.Conversation("u-1", Entry.OVERLAY), nav.route.value)
            nav.back()
            assertEquals(FlyoutRoute.Home, nav.route.value, "말풍선에서 온 대화의 뒤로 = 홈(맥 .overlay)")

            nav.hide()
            r.app.overlayPointerOutcome(PointerOutcome(click = ClickAction.OpenMessages("")))
            assertEquals(FlyoutRoute.PokeList, nav.route.value, "빈 보낸이는 대화가 아니라 콕 목록")
            nav.hide()
            nav.navigate(FlyoutRoute.Home)
            r.app.overlayPointerOutcome(PointerOutcome(click = ClickAction.OpenMessages(null)))
            assertEquals(FlyoutRoute.PokeList, nav.route.value, "보낸이 모름 → 콕 목록(맥 openPokeListToPickAPeer)")
            assertTrue(nav.visible.value)
            r.app.shutdownSteps().forEach { if (it is ShutdownStep.Always) it.run() }
        } finally {
            r.close()
        }
    }

    /** ⑤ 실제 AppGraph: 할 일 손상 파일 격리 → 앱 로그 폴더(logDir 가 절대 경로가 아니면 dataDir/logs) 한 줄. 깨끗하면 로그 파일 0. */
    @Test
    fun todoQuarantineGoesToAppLogFileInAssembledGraph() = runTest {
        val clean = AssemblyRig(this, dirs)
        try {
            clean.app.start()
            advanceTimeBy(1_000)
            runCurrent()
            assertFalse(Files.exists(clean.dataDir.resolve("logs").resolve(TodoQuarantineLog.FILE_NAME)), "음성 대조: 손상 없으면 로그 0")
            clean.app.shutdownSteps().forEach { if (it is ShutdownStep.Always) it.run() }
        } finally {
            clean.close()
        }

        val r = AssemblyRig(this, dirs, prepareDataDir = { d -> Files.writeString(d.resolve("todos.local.json"), "{ 합성 손상") })
        try {
            r.app.start()
            advanceTimeBy(1_000)
            runCurrent()
            val log = r.dataDir.resolve("logs").resolve(TodoQuarantineLog.FILE_NAME)
            assertTrue(Files.exists(log), "격리 보고가 앱 로그 파일에 없다: ${Files.list(r.dataDir).use { it.toList() }}")
            val lines = Files.readAllLines(log)
            assertEquals(1, lines.size, "한 줄: $lines")
            assertTrue(lines.single().contains("todo quarantine") && lines.single().contains("todos.local.json") && lines.single().contains("preserved=true"), lines.single())
            assertFalse(lines.single().contains("합성 손상"), "사용자 문장은 싣지 않는다")
            r.app.shutdownSteps().forEach { if (it is ShutdownStep.Always) it.run() }
        } finally {
            r.close()
        }
    }
}

private fun synthPeer() = GomokuUser(
    id = "peer-synth", displayName = "합성상대", avatarURL = null, characterID = null, isWorking = true, isCapable = true, inMatch = false,
)

private fun synthInvite(id: String, expiresAt: SwiftDate) = GomokuInvite(id, synthPeer(), 5, expiresAt)

private fun synthMatch(id: String, moveCount: Int, finished: Boolean = false) = GomokuMatchState(
    id = id, stake = 5, myColor = GomokuColor.black, opponent = synthPeer(), board = GomokuBoard(), lastMove = null,
    moveCount = moveCount, turn = if (finished) null else GomokuColor.black, deadline = null, isFinished = finished,
    outcome = null, endReason = null, rubyDelta = null, blackPassed = false,
)
