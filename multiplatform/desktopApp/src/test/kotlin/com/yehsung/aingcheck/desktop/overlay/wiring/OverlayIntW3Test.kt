// int-w3 W-14 #4 — 오버레이 문 넷: ① 셸 알림 → 말풍선 문(같은 사건은 한 표면만 W-3 #6) ② 팀 소식·새 버전·대결 신청 공급(맥과 같은 사건·문구)
// ③ 화면 바뀜 → 모니터 다시 읽기 ④ 할 일 보드 호스트(설정 꺼짐이면 콕 반응만 · 열면 todo_sync 한 번 — MockEngine 녹음).
// 맥 줄: CheckApp.swift:214(새 버전) · :359·401·437(신청 큐) · :617-622(isTodoEnabled 가드) · TodoSyncCoordinator.swift:49(boardOpened) ·
// WorkTimerStoreSync.swift:362-367 + CheckOverlayReactions.swift:133-165(출근 인사). 픽스처는 합성뿐(실서버·창 0).
package com.yehsung.aingcheck.desktop.overlay.wiring

import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.now.NowTodoSyncTransport
import com.yehsung.aingcheck.core.stores.now.todo.TodoListStore
import com.yehsung.aingcheck.core.stores.now.todo.TodoSync
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncCoroutineScheduler
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncReason
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlayFrameComposer
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfacePresenter
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfaces
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfacesConfig
import com.yehsung.aingcheck.desktop.overlay.assembly.OverlaySurfacesTest
import com.yehsung.aingcheck.desktop.overlay.engine.BoardHost
import com.yehsung.aingcheck.desktop.overlay.engine.BubbleKind
import com.yehsung.aingcheck.desktop.overlay.engine.ClickAction
import com.yehsung.aingcheck.desktop.overlay.engine.DuelGame
import com.yehsung.aingcheck.desktop.overlay.engine.DuelAttention
import com.yehsung.aingcheck.desktop.overlay.engine.DuelAttentionKind
import com.yehsung.aingcheck.desktop.overlay.surface.OverlayWindowDpiRelay
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.desktop.overlay.engine.FakeMeasure
import com.yehsung.aingcheck.desktop.overlay.engine.FakeSink
import com.yehsung.aingcheck.desktop.overlay.engine.HitTarget
import com.yehsung.aingcheck.desktop.overlay.engine.MonitorInfo
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayBubble
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayPoint
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayRect
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayTimings
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayView
import com.yehsung.aingcheck.desktop.overlay.engine.PointerKind
import com.yehsung.aingcheck.desktop.overlay.engine.PointerOutcome
import com.yehsung.aingcheck.desktop.overlay.render.ComposedOverlay
import com.yehsung.aingcheck.desktop.overlay.todoboard.FakeBoardSurface
import com.yehsung.aingcheck.desktop.overlay.todoboard.ManualTimer
import com.yehsung.aingcheck.desktop.overlay.todoboard.MemoryTodoFiles
import com.yehsung.aingcheck.desktop.platform.windows.display.DisplayChange
import com.yehsung.aingcheck.desktop.platform.windows.display.DisplayChangeSource
import com.yehsung.aingcheck.desktop.platform.windows.display.DisplayMessages
import com.yehsung.aingcheck.desktop.platform.windows.display.Win32DisplayChangeSource
import com.yehsung.aingcheck.desktop.platform.windows.msg.MessageHandler
import com.yehsung.aingcheck.desktop.shell.notify.ShellNotice
import com.yehsung.aingcheck.desktop.shellapi.DesktopUpdateState
import com.yehsung.aingcheck.desktop.shellapi.NotifyKind
import com.yehsung.aingcheck.desktop.wiring.OverlayPresenter
import com.yehsung.aingcheck.desktop.wiring.OverlayWiring
import com.yehsung.aingcheck.desktop.wiring.OverlayWiringDeps
import com.yehsung.aingcheck.desktop.wiring.WiringTestRig
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.socialapi.QueuedBubbleMessage
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.InMemoryDesktopWorkState
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import com.sun.jna.platform.win32.WinDef
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Clock
import kotlin.time.Instant

class OverlayIntW3Test {
    private val wallEpoch = 1_792_465_200L

    private class Rig(
        val scope: TestScope,
        config: DesktopAppConfig = DesktopAppConfig(duels = true, poke = true),
        enabled: Boolean = true,
        surfaces: OverlaySurfaces? = null,
        extra: (OverlayWiringDeps) -> OverlayWiringDeps = { it },
        wallEpoch: Long,
    ) {
        val work = InMemoryDesktopWorkState()
        val overlayOn = MutableStateFlow(enabled)
        val views = ArrayList<OverlayView>()
        val outcomes = ArrayList<PointerOutcome>()
        val wiring = OverlayWiring(
            extra(
                OverlayWiringDeps(
                    desktopConfig = config,
                    keyValueStore = InMemoryDesktopKeyValueStore(),
                    clock = object : Clock {
                        override fun now(): Instant = Instant.fromEpochMilliseconds(wallEpoch * 1000 + scope.testScheduler.currentTime)
                    },
                    monotonic = object : MonotonicClock {
                        override fun elapsedNanos(): Long = scope.testScheduler.currentTime * 1_000_000
                    },
                    workState = { work },
                    overlayEnabled = overlayOn,
                    sink = FakeSink(),
                    measure = FakeMeasure(),
                    presenter = OverlayPresenter { view, _ -> views += view },
                    onPointerOutcome = { outcomes += it },
                    random = Random(7),
                ),
            ),
            surfaces,
        )

        /** 화면에 뜬 말풍선(같은 말풍선은 한 번). */
        fun bubbles(): List<OverlayBubble> = views.mapNotNull { it.bubble }.distinctBy { it.text to it.shownAt }
        fun texts(): List<String> = bubbles().map { it.text }
        fun startWorking() = work.set(DesktopWorkSnapshot(isWorking = true, startOrigin = WorkStartOrigin.MANUAL))
        fun click() {
            wiring.onPointer(PointerKind.DOWN, OverlayPoint(20.0, 20.0), HitTarget.Body)
            wiring.onPointer(PointerKind.UP, OverlayPoint(20.0, 20.0), HitTarget.Body)
        }
    }

    private fun TestScope.rig(
        config: DesktopAppConfig = DesktopAppConfig(duels = true, poke = true),
        enabled: Boolean = true,
        surfaces: OverlaySurfaces? = null,
        extra: (OverlayWiringDeps) -> OverlayWiringDeps = { it },
    ) = Rig(this, config, enabled, surfaces, extra, wallEpoch)

    private fun TestScope.step(ms: Long) { advanceTimeBy(ms); runCurrent() }

    /** 설정 "캐릭터를 눌러 할 일 열기"(보드 시험). */
    private var boardOn = false

    /** 셸 대결 신청 알림. [ref] = 신청 id(ShellWiring.notifyDuelInvite 가 DuelInviteNotice.inviteId 를 싣는다 — 짝짓기 열쇠). */
    private fun invite(peer: String, stake: Long, game: String = "오목", ref: String? = null) =
        ShellNotice(NotifyKind.DUEL_INVITE, "$game 대결 신청", "${peer}님이 $game 대결을 신청했어요 · 루비 $stake", ref = ref)

    // ───────────────────────── ① 셸 알림 → 말풍선 문 ─────────────────────────

    @Test
    fun `셸 대결 신청 알림 — 캐릭터 켜짐이면 말풍선이 맡고(true) 글 그대로 한 번 뜬다, 꺼짐·깃발 꺼짐은 false 로 셸 토스트`() = runTest {
        val r = rig()
        r.wiring.start(backgroundScope)
        r.startWorking()
        step(100)
        val notice = invite("합성상대", 5)
        assertTrue(r.wiring.shellBubble(notice), "켜짐 → 말풍선이 맡는다(셸은 풍선 0)")
        step(8_000) // 출근 말풍선(5초)이 끝난 뒤 대기열이 띄운다
        assertEquals(1, r.texts().count { it == notice.body }, "글 그대로 한 번")

        // 음성 대조 1: 캐릭터를 끈 사용자 → false(그때만 토스트 — W-3 #6), 말풍선 0
        val off = rig(enabled = false)
        off.wiring.start(backgroundScope)
        step(100)
        assertFalse(off.wiring.shellBubble(notice))
        step(8_000)
        assertFalse(off.texts().contains(notice.body))

        // 음성 대조 2: 대결 깃발 꺼짐 → false(W-3 #7)
        val noDuels = rig(config = DesktopAppConfig(duels = false))
        noDuels.wiring.start(backgroundScope)
        noDuels.startWorking()
        step(100)
        assertFalse(noDuels.wiring.shellBubble(notice))
        step(8_000)
        assertFalse(noDuels.texts().contains(notice.body))

        // stop 뒤 → false
        r.wiring.stop()
        assertFalse(r.wiring.shellBubble(invite("다른상대", 3)))
        r.wiring.stop(); off.wiring.stop(); noDuels.wiring.stop()
    }

    @Test
    fun `같은 신청은 한 표면만 — 구조 신청(onDuelInvite)이 먼저 왔으면 셸 글은 두 번째 말풍선을 만들지 않는다, 누르면 그 판`() = runTest {
        val r = rig()
        r.wiring.start(backgroundScope)
        r.startWorking()
        step(100)
        val expires = SwiftDate.fromEpochMillis((wallEpoch + 60) * 1000)
        r.wiring.onDuelInvite(DuelGame.GOMOKU, "m-1", "합성상대", 5, expires)
        assertTrue(r.wiring.shellBubble(invite("합성상대", 5, ref = "m-1")))
        step(20_000)
        val notice = invite("합성상대", 5)
        val invites = r.bubbles().filter { it.kind is BubbleKind.Invite || it.text == notice.body }
        assertEquals(1, invites.size, "한 표면 한 번: ${r.bubbles()}")
        assertEquals(BubbleKind.Invite(DuelGame.GOMOKU, "m-1"), invites.single().kind, "구조 신청 말풍선 — 누르면 그 판")

        // 음성 대조: 판돈이 다른 신청(짝 아님)의 셸 글은 따로 뜬다
        val r2 = rig()
        r2.wiring.start(backgroundScope)
        r2.startWorking()
        step(100)
        r2.wiring.onDuelInvite(DuelGame.GOMOKU, "m-2", "합성상대", 5, SwiftDate.fromEpochMillis((wallEpoch + 120) * 1000))
        assertTrue(r2.wiring.shellBubble(invite("합성상대", 10, ref = "m-3")))
        step(20_000)
        assertEquals(1, r2.bubbles().count { it.kind is BubbleKind.Invite }, "구조 신청 하나")
        assertEquals(1, r2.bubbles().count { it.text == invite("합성상대", 10).body }, "짝 없는 셸 글 하나: ${r2.bubbles()}")
        r.wiring.stop(); r2.wiring.stop()
    }

    @Test
    fun `셸 문 — 메시지는 같은 큐에 있을 때만, 찌르기는 poke 깃발, 업데이트는 버전을 안 뒤에만 true`() = runTest {
        val versions = MutableSharedFlow<String>(extraBufferCapacity = 2)
        val r = rig(extra = { it.copy(updateVersions = versions) })
        r.wiring.start(backgroundScope)
        step(100)
        val msg = ShellNotice(NotifyKind.MESSAGE, "메시지", "합성 본문", senderId = "u-2")
        assertFalse(r.wiring.shellBubble(msg), "큐가 비었으면 오버레이가 맡을 것이 없다")
        r.wiring.bubbles.append(listOf(QueuedBubbleMessage("m-1", "합성친구", "합성 본문", SwiftDate.fromEpochMillis(wallEpoch * 1000), fromUserID = "u-2")))
        assertTrue(r.wiring.shellBubble(msg), "같은 인스턴스 큐에 있으면 엔진이 띄운다")

        val update = ShellNotice(NotifyKind.UPDATE, "새 버전", "0.4.0")
        assertFalse(r.wiring.shellBubble(update), "버전을 모르면 false")
        versions.emit("0.4.0")
        step(50)
        assertTrue(r.wiring.shellBubble(update))

        val poke = ShellNotice(NotifyKind.POKE, "콕", "합성친구님이 콕 찔렀어요!")
        assertTrue(r.wiring.shellBubble(poke))
        val noPoke = rig(config = DesktopAppConfig(duels = true, poke = false))
        assertFalse(noPoke.wiring.shellBubble(poke), "poke 깃발 꺼짐 → false")
        r.wiring.stop()
    }

    // ───────────────────────── ② 팀 소식 · 새 버전 ─────────────────────────

    private fun member(id: String, name: String, working: Boolean) =
        TeamMemberStatus(id, name, if (working) WorkStatus.working else WorkStatus.offWork, updatedAt = null, currentSessionStartedAt = null)

    @Test
    fun `팀 소식 — 첫 목록은 시드만, 퇴근→출근 전이만 '○○님 출근!', 나와 새로 나타난 근무자는 인사 0`() = runTest {
        val team = MutableStateFlow(listOf(member("me", "나", false), member("u-a", "합성가", false), member("u-b", "합성나", true)))
        val r = rig(extra = { it.copy(teamStatuses = team, selfUserId = { "me" }) })
        r.wiring.start(backgroundScope)
        r.startWorking()
        step(6_000) // 출근 말풍선이 지나간 뒤
        assertTrue(r.texts().none { it.endsWith("님 출근!") }, "첫 목록은 시드만")

        team.value = listOf(member("me", "나", true), member("u-a", "합성가", true), member("u-b", "합성나", true), member("u-c", "합성다", true))
        step(4_000)
        val greetings = r.texts().filter { it.endsWith("님 출근!") }
        assertEquals(listOf("합성가님 출근!"), greetings, "전이한 사람만(나·처음 보는 근무자·이미 근무 중 제외)")
        r.wiring.stop()
    }

    @Test
    fun `새 버전 — 공급이 온 순간 보이고 한가하면 '새 업데이트가 있어요!' 한 번, 새 빌드가 아니면 0`() = runTest {
        val state = MutableStateFlow(DesktopUpdateState(currentBuild = 80))
        val r = rig(extra = { it.copy(updateVersions = OverlayWiring.updateVersions(state)) })
        r.wiring.start(backgroundScope)
        r.startWorking()
        step(6_000)
        state.value = DesktopUpdateState(currentBuild = 80, latestBuild = 80, latestVersion = "0.3.80")
        step(1_000)
        assertFalse(r.texts().contains(OverlayTimings.UPDATE_BUBBLE_TEXT), "음성 대조: 같은 빌드는 새 버전이 아니다")
        state.value = DesktopUpdateState(currentBuild = 80, latestBuild = 81, latestVersion = "0.3.81")
        step(1_000)
        assertEquals(1, r.texts().count { it == OverlayTimings.UPDATE_BUBBLE_TEXT })
        assertEquals("새 업데이트가 있어요!", OverlayTimings.UPDATE_BUBBLE_TEXT, "맥 CheckOverlayWindow.swift:119 문구")
        r.wiring.stop()
    }

    @Test
    fun `updateVersions — 새 빌드일 때만 버전, 같은 버전 되풀이·빈 이름은 0`() = runTest {
        val out = OverlayWiring.updateVersions(
            flowOf(
                DesktopUpdateState(currentBuild = 80),
                DesktopUpdateState(currentBuild = 80, latestBuild = 79, latestVersion = "0.3.79"),
                DesktopUpdateState(currentBuild = 80, latestBuild = 81, latestVersion = "0.3.81"),
                DesktopUpdateState(currentBuild = 80, latestBuild = 81, latestVersion = "0.3.81", notes = "다시"),
                DesktopUpdateState(currentBuild = 80, latestBuild = 82, latestVersion = " "),
                DesktopUpdateState(currentBuild = 80, latestBuild = 83, latestVersion = "0.3.83"),
            ),
        ).toList()
        assertEquals(listOf("0.3.81", "0.3.83"), out)
    }

    // ───────────────────────── ③ 화면 바뀜 ─────────────────────────

    private class FakeDisplays : DisplayChangeSource {
        val listeners = ArrayList<(DisplayChange) -> Unit>()
        var closed = 0
        override fun addListener(listener: (DisplayChange) -> Unit): Registration {
            listeners += listener
            return Registration { closed += 1; listeners -= listener }
        }
        fun fire(c: DisplayChange) = listeners.toList().forEach { it(c) }
    }

    @Test
    fun `화면 바뀜 — 출처가 알리면 발표자가 모니터를 다시 읽고 새 작업 영역 안으로 조인다, 알림 없으면 다시 읽지 않는다`() = runTest {
        val wide = MonitorInfo("\\\\.\\DISPLAY1", OverlayRect(0.0, 0.0, 1920.0, 1080.0), OverlayRect(0.0, 0.0, 1920.0, 1040.0), primary = true)
        val small = MonitorInfo("\\\\.\\DISPLAY1", OverlayRect(0.0, 0.0, 1280.0, 720.0), OverlayRect(0.0, 0.0, 1280.0, 690.0), primary = true)
        val port = OverlaySurfacesTest.FakePort(listOf(wide), scale = 1.0)
        val presenter = OverlaySurfacePresenter(port, OverlayFrameComposer { _, w, h, _, _ -> ComposedOverlay.empty(w, h) }) { null }
        val surfaces = OverlaySurfaces(FakeSink(), presenter, BoardHost.None, null, presenter, null) {}
        val displays = FakeDisplays()
        val r = rig(surfaces = surfaces, extra = { it.copy(displayChanges = displays) })
        r.wiring.start(backgroundScope)
        r.startWorking()
        step(500)
        assertEquals(1, displays.listeners.size)
        val reads = port.monitorReads
        val before = presenter.frameDip!!
        assertTrue(before.left > 1280.0, "넓은 화면 오른쪽 위: $before")

        step(2_000)
        assertEquals(reads, port.monitorReads, "음성 대조: 알림이 없으면 틱이 모니터를 다시 읽지 않는다")

        port.monitorList = listOf(small)
        displays.fire(DisplayChange.DISPLAY_MODE)
        step(200)
        assertEquals(reads + 1, port.monitorReads, "알림 → 다음 그림 전에 한 번 다시 읽는다")
        val after = presenter.frameDip!!
        assertTrue(after.left + after.width <= 1280.0 && after.top + after.height <= 690.0, "새 작업 영역 안: $after")

        r.wiring.stop()
        assertEquals(1, displays.closed, "stop 은 출처 등록을 거둔다")
        displays.fire(DisplayChange.DPI)
        step(200)
        assertEquals(reads + 1, port.monitorReads, "stop 뒤 0")
    }

    @Test
    fun `Win32 출처 — WM_DISPLAYCHANGE·WM_DPICHANGED·작업 영역 WM_SETTINGCHANGE 만 알리고, 다른 설정·메시지는 0, 마지막 듣는 이가 떠나면 처리기 해제`() {
        val handlers = HashMap<Int, MutableList<MessageHandler>>()
        var unhooked = 0
        val source = Win32DisplayChangeSource { msg, h ->
            handlers.getOrPut(msg) { ArrayList() } += h
            Registration { unhooked += 1; handlers[msg]?.remove(h) }
        }
        fun send(msg: Int, wParam: Long) =
            handlers[msg].orEmpty().toList().forEach { assertEquals(null, it.handle(WinDef.HWND(), msg, WinDef.WPARAM(wParam), WinDef.LPARAM(0)), "DefWindowProc 로 넘긴다") }

        val got = ArrayList<DisplayChange>()
        val reg = source.addListener { got += it }
        assertEquals(3, source.hookCount)
        send(DisplayMessages.WM_DISPLAYCHANGE, 0)
        send(DisplayMessages.WM_DPICHANGED, 0x00900090)
        send(DisplayMessages.WM_SETTINGCHANGE, DisplayMessages.SPI_SETWORKAREA)
        send(DisplayMessages.WM_SETTINGCHANGE, 0x0014) // SPI_SETDESKWALLPAPER — 화면 구성 아님
        send(0x0218, 0) // WM_POWERBROADCAST — 걸지도 않았다
        assertEquals(listOf(DisplayChange.DISPLAY_MODE, DisplayChange.DPI, DisplayChange.WORK_AREA), got)

        reg.close()
        assertEquals(3, unhooked)
        assertEquals(0, source.hookCount)
        send(DisplayMessages.WM_DISPLAYCHANGE, 0)
        assertEquals(3, got.size, "해제 뒤 0")
    }

    // ───────────────────────── ④ 할 일 보드 호스트 ─────────────────────────

    @Test
    fun `할 일 보드 — 설정 꺼짐이면 클릭은 콕 반응만·todo_sync 0, 켜면 같은 클릭이 보드를 열고 todo_sync 한 번(boardOpened)`() = runTest {
        val net = WiringTestRig(this, answer = { path ->
            if (path.endsWith("/rpc/todo_sync")) """{"status":"ok","items":[],"watermark_ms":1789621500000,"rejected":[],"full":true}""" else null
        })
        // 실패해도 주기 맞춤 타이머·틱을 거둔다(안 거두면 runTest 정리가 가상 시간을 끝없이 민다).
        try {
            boardScenario(net)
        } finally {
            net.close()
        }
    }

    private suspend fun TestScope.boardScenario(net: WiringTestRig) {
        net.signIn()
        val nowS = { (WiringTestRig.BASE_MS + testScheduler.currentTime) / 1000.0 }
        val list = TodoListStore("/synthetic/todos.${WiringTestRig.USER}.json", MemoryTodoFiles(), nowS)
        val sync = TodoSync(list, NowTodoSyncTransport(SessionContext(net.sessionStore, AppConfig())), TodoSyncCoroutineScheduler(net.scope), net.scope, nowS)
        sync.activate(WiringTestRig.USER)
        step(500)
        assertEquals(1, net.count("/rpc/todo_sync"), "시작 맞춤 한 번(기준선)")

        val surface = FakeBoardSurface()
        val board = OverlaySurfaces.boardController(
            OverlaySurfacesConfig(
                keyValueStore = InMemoryDesktopKeyValueStore(),
                todoStore = list,
                boardEnabled = { boardOn },
                onBoardOpened = { sync.requestSync(TodoSyncReason.boardOpened) },
            ),
            list,
            surface,
            ManualTimer(),
        )
        val r = rig(extra = { it.copy(board = board) })
        r.wiring.start(backgroundScope)
        try {
            boardClicks(r, surface, net)
        } finally {
            r.wiring.stop()
        }
    }

    private fun TestScope.boardClicks(r: Rig, surface: FakeBoardSurface, net: WiringTestRig) {
        r.startWorking()
        step(6_000)

        r.click()
        step(500)
        assertEquals(ClickAction.Hit, r.outcomes.last().click, "꺼짐 → 콕 반응(맥 :618 guard isTodoEnabled else false → 때리기)")
        assertFalse(surface.calls.contains("show"))
        assertEquals(1, net.count("/rpc/todo_sync"), "꺼짐에서 서버 요청 0")

        boardOn = true
        step(1_000)
        r.click()
        step(500)
        assertEquals(ClickAction.ToggleBoard, r.outcomes.last().click)
        assertTrue(surface.visible, "보드가 열렸다")
        assertEquals(2, net.count("/rpc/todo_sync"), "연 순간 boardOpened 한 번")

        r.click() // 닫기 — 닫을 때는 맞추지 않는다
        step(500)
        assertFalse(surface.visible)
        assertEquals(2, net.count("/rpc/todo_sync"))
    }

    // ───────────────────────── int-w4a polish ─────────────────────────

    /** ① 같은 상대가 60초 안에 같은 판돈으로 두 번 — 글은 똑같지만 신청 id 가 다르다. 구조 둘이 먼저, 셸 글 둘이 뒤여도 말풍선은 정확히 둘. */
    @Test
    fun `polish① 같은 상대·같은 판돈 신청 두 건 — 신청 id 로 짝지어 말풍선은 정확히 둘, 글만 말풍선 0`() = runTest {
        val r = rig()
        r.wiring.start(backgroundScope)
        r.startWorking()
        step(8_000) // 출근 말풍선이 끝난 뒤
        val exp = SwiftDate.fromEpochMillis((wallEpoch + 60) * 1000)
        r.wiring.onDuelInvite(DuelGame.GOMOKU, "inv-1", "합성상대", 5, exp)
        r.wiring.onDuelInvite(DuelGame.GOMOKU, "inv-2", "합성상대", 5, exp)
        assertTrue(r.wiring.shellBubble(invite("합성상대", 5, ref = "inv-1")))
        assertTrue(r.wiring.shellBubble(invite("합성상대", 5, ref = "inv-2")))
        step(40_000)
        val body = invite("합성상대", 5).body
        assertEquals(
            listOf(BubbleKind.Invite(DuelGame.GOMOKU, "inv-1"), BubbleKind.Invite(DuelGame.GOMOKU, "inv-2")),
            r.bubbles().map { it.kind }.filterIsInstance<BubbleKind.Invite>(),
            "구조 신청 말풍선 둘(누르면 각자 그 판): ${r.bubbles()}",
        )
        assertEquals(0, r.bubbles().count { it.kind !is BubbleKind.Invite && it.text == body }, "글만 말풍선 0: ${r.bubbles()}")

        // 음성 대조: 신청 id 가 짝이 없는 셸 글(구조 신청 없이 온 것)은 글 그대로 한 번 뜬다
        r.wiring.onDuelInvite(DuelGame.GOMOKU, "inv-3", "합성상대", 5, SwiftDate.fromEpochMillis((wallEpoch + 120) * 1000))
        assertTrue(r.wiring.shellBubble(invite("합성상대", 5, ref = "inv-x")))
        step(40_000)
        assertEquals(1, r.bubbles().count { it.kind !is BubbleKind.Invite && it.text == body }, "짝 없는 id 의 글은 한 번: ${r.bubbles()}")
        r.wiring.stop()
    }

    /** ② 캐릭터를 끈 동안 온 신청 — 셸은 토스트(false), 엔진 큐엔 안 남는다 → 60초 안에 다시 켜도 같은 신청 말풍선 0. */
    @Test
    fun `polish② 캐릭터 꺼짐에 온 구조 신청은 큐에 남지 않는다 — 다시 켜도 말풍선 0, 켜짐이면 한 번`() = runTest {
        val r = rig(enabled = false)
        r.wiring.start(backgroundScope)
        r.startWorking()
        step(8_000)
        val exp = SwiftDate.fromEpochMillis((wallEpoch + 60) * 1000)
        r.wiring.onDuelInvite(DuelGame.CHESS, "inv-off", "합성상대", 3, exp)
        assertFalse(r.wiring.shellBubble(invite("합성상대", 3, game = "체스", ref = "inv-off")), "꺼짐 → 셸이 토스트")
        step(2_000)
        r.overlayOn.value = true // 60초 안에 다시 켠다
        step(30_000)
        assertEquals(0, r.bubbles().count { it.kind is BubbleKind.Invite }, "토스트로 알린 신청이 말풍선으로 또 뜬다: ${r.bubbles()}")

        // 양성 대조: 켜진 채로 온 신청은 한 번 뜬다
        r.wiring.onDuelInvite(DuelGame.CHESS, "inv-on", "합성상대", 3, SwiftDate.fromEpochMillis((wallEpoch + 120) * 1000))
        step(20_000)
        assertEquals(listOf(BubbleKind.Invite(DuelGame.CHESS, "inv-on")), r.bubbles().map { it.kind }.filterIsInstance<BubbleKind.Invite>())
        r.wiring.stop()
    }

    /** ③ 차례 알림 구조 정보 → 말풍선(같은 판 다음 차례도 뜬다) → 누르면 OpenDuel(그 판) → openDuel 이 그 게임 창을 그 판 id 로. */
    @Test
    fun `polish③ 차례 알림 — 같은 판 다음 차례도 다시 뜨고, 누르면 그 판 창(openDuel)`() = runTest {
        val r = rig()
        r.wiring.start(backgroundScope)
        r.startWorking()
        step(8_000)
        r.wiring.onDuelAttention(DuelAttention(DuelGame.GOMOKU, "m-9", DuelAttentionKind.MY_TURN, "합성상대", 4))
        step(300)
        val first = r.bubbles().last()
        assertEquals(BubbleKind.Invite(DuelGame.GOMOKU, "m-9"), first.kind)
        r.wiring.onPointer(PointerKind.DOWN, OverlayPoint(20.0, 20.0), HitTarget.Bubble)
        r.wiring.onPointer(PointerKind.UP, OverlayPoint(20.0, 20.0), HitTarget.Bubble)
        step(100)
        val click = r.outcomes.map { it.click }.filterIsInstance<ClickAction.OpenDuel>()
        assertEquals(listOf(ClickAction.OpenDuel(DuelGame.GOMOKU, "m-9")), click)
        val opened = RecordingGameWindows()
        r.outcomes.forEach { OverlayWiring.openDuel(it, opened) }
        assertEquals(listOf("gomoku:m-9"), opened.opened)

        // 같은 판의 다음 차례(수 번호 6) — 사실 공급이 없어도 첫 알림의 수 번호에 묶여 버려지지 않는다
        step(15_000)
        r.wiring.onDuelAttention(DuelAttention(DuelGame.GOMOKU, "m-9", DuelAttentionKind.MY_TURN, "합성상대", 6))
        step(300)
        assertEquals(2, r.bubbles().count { it.kind == BubbleKind.Invite(DuelGame.GOMOKU, "m-9") }, "다음 차례 말풍선: ${r.bubbles()}")

        // 음성 대조: 대결 말풍선이 아닌 클릭(때리기)·다른 게임 판
        OverlayWiring.openDuel(PointerOutcome(click = ClickAction.Hit), opened)
        OverlayWiring.openDuel(PointerOutcome(click = ClickAction.OpenDuel(DuelGame.TETRIS, "t-1")), opened)
        OverlayWiring.openDuel(PointerOutcome(click = ClickAction.OpenDuel(DuelGame.CHESS, "c-1")), opened)
        assertEquals(listOf("gomoku:m-9", "tetris:t-1", "chess:c-1"), opened.opened)
        r.wiring.stop()
    }

    private class RecordingGameWindows : DesktopGameWindows {
        val opened = mutableListOf<String>()
        override fun openGames(kind: MiniGameKind?) = Unit
        override fun openGomoku(focusMatchID: String?) { opened += "gomoku:$focusMatchID" }
        override fun openChess(focusMatchID: String?) { opened += "chess:$focusMatchID" }
        override fun openTetrisDuel(focusMatchID: String?) { opened += "tetris:$focusMatchID" }
        override fun openGacha() = Unit
        override fun openCakeGift() = Unit
        override fun closeAll() = Unit
    }

    /** ④ 오버레이 창 자신의 WM_DPICHANGED(보조 모니터 배율) → 모니터 다시 읽기. 다른 메시지는 null·다시 읽기 0, stop 뒤 0. */
    @Test
    fun `polish④ 오버레이 창 WM_DPICHANGED — 0 을 돌려주고 발표자가 모니터를 다시 읽는다, 다른 메시지·stop 뒤는 0`() = runTest {
        val mon = MonitorInfo("\\\\.\\DISPLAY2", OverlayRect(1920.0, 0.0, 1280.0, 720.0), OverlayRect(1920.0, 0.0, 1280.0, 690.0), primary = false)
        val port = OverlaySurfacesTest.FakePort(listOf(mon), scale = 1.0)
        val presenter = OverlaySurfacePresenter(port, OverlayFrameComposer { _, w, h, _, _ -> ComposedOverlay.empty(w, h) }) { null }
        val dpi = OverlayWindowDpiRelay()
        val surfaces = OverlaySurfaces(FakeSink(), presenter, BoardHost.None, null, presenter, null, displayChanges = dpi) {}
        val r = rig(surfaces = surfaces) // 앱 숨은 창 출처(displayChanges)는 없다 — 이 창의 메시지만
        r.wiring.start(backgroundScope)
        r.startWorking()
        step(500)
        assertEquals(1, dpi.listenerCount, "start 가 오버레이 창 출처를 듣는다")
        val reads = port.monitorReads

        assertEquals(null, dpi.handle(DisplayMessages.WM_DISPLAYCHANGE), "숨은 창이 받는 메시지는 창 프로시저로 넘긴다")
        assertEquals(null, dpi.handle(0x0201), "WM_LBUTTONDOWN 은 넘긴다")
        step(200)
        assertEquals(reads, port.monitorReads, "음성 대조: 배율 아닌 메시지는 다시 읽지 않는다")

        assertEquals(WinDef.LRESULT(0), dpi.handle(DisplayMessages.WM_DPICHANGED), "처리했으면 0(MSDN)")
        step(200)
        assertEquals(reads + 1, port.monitorReads, "보조 모니터 배율 → 다음 그림 전에 한 번 다시 읽는다")

        r.wiring.stop()
        assertEquals(0, dpi.listenerCount, "stop 은 창 출처 등록을 거둔다")
        dpi.handle(DisplayMessages.WM_DPICHANGED)
        step(200)
        assertEquals(reads + 1, port.monitorReads, "stop 뒤 0")
    }
}
