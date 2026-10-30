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
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

/** 부작용 녹음 플랫폼: 트레이 show/remove · 전원 구독 열고 닫기를 한 줄 장부에 적는다. */
private class RecordingPlatform(val log: MutableList<String>) : DesktopPlatform {
    // 할 일 목록(TodoWiring)이 dataDir 아래 todos.<계정>.json 을 쓴다 — 저장소 안 상대 경로("D")에 흘리지 않게 임시 폴더.
    override val paths = object : AppPaths {
        override val dataDir: String = java.nio.file.Files.createTempDirectory("asm-data").toFile().apply { deleteOnExit() }.path
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
    config: DesktopAppConfig = DesktopAppConfig(),
    kv: DesktopKeyValueStore = InMemoryDesktopKeyValueStore(),
) {
    val log = mutableListOf<String>()
    val hosts = mutableSetOf<String>()
    val requests = mutableListOf<String>()
    val uncaught = mutableListOf<Throwable>()
    val platform = RecordingPlatform(log)
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
        gameWindows = FakeGameFactory(),
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
    /** W-6 #6: 조립 → 시작 → 종료 한 벌(실패해도 리그를 닫는다 — 안 닫으면 틱 루프가 가상 시계를 끝없이 돌려 runTest 가 멈춘다). 근무 마무리가 맨 앞, 실시간 shutdown 뒤에 껍데기, tray.remove 가 맨 끝. */
    @Test
    fun assembledGraphStartsThenShutsDownInW6Order() = runTest {
        val r = AssemblyRig(this)
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
        val off = AssemblyRig(this, DesktopAppConfig(poke = false))
        assertFalse(off.app.social.actions.canPoke)
        off.app.start()
        advanceTimeBy(120_000)
        runCurrent()
        assertEquals(0, off.requests.count { it.endsWith("/rpc/take_pokes") }, "poke=false 면 take_pokes 0")
        off.app.shutdownSteps().forEach { if (it is ShutdownStep.Always) it.run() }
        off.close()

        val on = AssemblyRig(this, DesktopAppConfig(poke = true))
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
        val r = AssemblyRig(this, kv = answered)
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
}
