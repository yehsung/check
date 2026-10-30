// 원본: 없음(시험) — int-w2 배선 social-games-shell: 착용 캐릭터 표 수명(W-8 3차 · 폰 PhoneAppModel.kt:335·360·370) · 대결 신청 → 알림 한 문
// (맥 CheckOverlayWindow.swift:1268·1424·1565 글) · 울트라 화면 떠나면 안내 지우기(W3-c3 nice) · Store 업데이트 목적지(W-13 #7).
// 가짜만: SharedTestHarness(MockEngine 녹음) · 가짜 트레이·창(ShellRig). 창 0.
package com.yehsung.aingcheck.desktop.shell.wiring

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.format.WorkStatus
import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import com.yehsung.aingcheck.desktop.pages.shared.SharedPage
import com.yehsung.aingcheck.desktop.pages.shared.SharedTestHarness
import com.yehsung.aingcheck.desktop.platform.windows.tray.TaskbarTheme
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutScreen
import com.yehsung.aingcheck.desktop.shell.flyout.SyntheticScreen
import com.yehsung.aingcheck.desktop.shell.update.UpdatePollSchedule
import com.yehsung.aingcheck.desktop.shell.update.StoreUpdateDestination
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.NotifyKind
import com.yehsung.aingcheck.desktop.shellapi.NotifySurface
import com.yehsung.aingcheck.desktop.windows.kit.DuelInviteNotice
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.wiring.FakeTray
import com.yehsung.aingcheck.desktop.wiring.FakeWindowPort
import com.yehsung.aingcheck.desktop.wiring.ShellDeps
import com.yehsung.aingcheck.desktop.wiring.ShellOverlayPage
import com.yehsung.aingcheck.desktop.wiring.ShellPages
import com.yehsung.aingcheck.desktop.wiring.ShellWiring
import com.yehsung.aingcheck.desktop.wiring.TaskbarThemeSource
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import java.util.concurrent.Executor

/** ShellRig(ShellWiringTest) 와 같은 가짜 묶음 + int-w2 칸(울트라 떠남). 창 0 · 서버는 MockEngine 녹음. */
internal class W2ShellRig(scope: TestScope, config: DesktopAppConfig = DesktopAppConfig(), onUltraPageLeft: () -> Unit = {}) {
    val h = SharedTestHarness(scope, SharedTestHarness.withTeam, config)
    val tray = FakeTray()
    val wiring = ShellWiring(
        ShellDeps(
            session = h.session,
            sessionContext = h.context,
            service = h.service,
            messages = h.messages,
            rankings = h.rankings,
            me = h.me,
            appearance = h.appearance,
            desktopConfig = config,
            clientIdentity = ClientIdentity(ClientPlatform.WINDOWS, SharedTestHarness.BUILD, "0.1.0"),
            deviceStore = InMemoryDesktopKeyValueStore(),
            monotonic = object : MonotonicClock {
                override fun elapsedNanos(): Long = scope.testScheduler.currentTime * 1_000_000
            },
            scope = h.storeScope,
            tray = tray,
            power = object : PowerEvents {
                override fun addListener(listener: (PowerEvent) -> Unit): Registration = Registration {}
            },
            work = MutableStateFlow(WorkStatusSnapshot(WorkStatus.offWork, 0)),
            toggleWork = {},
            quit = {},
            events = Executor { it.run() },
            window = FakeWindowPort(),
            screen = FlyoutScreen { SyntheticScreen.facts },
            theme = object : TaskbarThemeSource {
                override fun current(): TaskbarTheme = TaskbarTheme.LIGHT
                override fun addListener(listener: (TaskbarTheme) -> Unit): Registration = Registration {}
            },
            rankingsFace = { RankingsMyFace("aing", CharacterMood.entries.first()) },
            updateSchedule = UpdatePollSchedule(initialDelayMillis = FAR, intervalMillis = FAR),
            onUltraPageLeft = onUltraPageLeft,
        ),
    )
    val nav get() = wiring.handle.nav

    companion object {
        const val FAR = 1_000_000_000L
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class ShellIntW2HooksTest {
    private fun W2ShellRig.characterCalls() = h.paths.count { it == SupabaseWorkService.appUserCharactersPath }

    /** 로그인 직후 한 번 · 플라이아웃 열 때 60초 스로틀 · 로그아웃 reset. 시작 전·로그아웃 상태는 0건(새 폴링 없음). */
    @Test
    fun characterDirectoryFollowsSessionAndFlyoutWithoutNewPolling() = runTest {
        val r = W2ShellRig(this)
        r.h.signIn()
        testScheduler.runCurrent()
        assertEquals(0, r.characterCalls(), "start 전에 캐릭터 표를 물었다")

        r.wiring.start()
        testScheduler.runCurrent()
        assertEquals(1, r.characterCalls(), "로그인 직후 한 번이 아니다")

        r.nav.open(FlyoutRoute.Home)
        testScheduler.runCurrent()
        assertEquals(1, r.characterCalls(), "60초 안에 다시 물었다(스로틀)")
        r.nav.hide()
        testScheduler.advanceTimeBy(61_000)
        r.nav.open(FlyoutRoute.Home)
        testScheduler.runCurrent()
        assertEquals(2, r.characterCalls(), "60초 지나 플라이아웃을 열었는데 안 물었다")

        r.h.session.signOut()
        testScheduler.runCurrent()
        assertEquals(null, r.wiring.handle.characters.lastAttemptAt, "로그아웃했는데 표를 reset 하지 않았다")
        r.nav.hide()
        testScheduler.advanceTimeBy(61_000)
        r.nav.open(FlyoutRoute.Home)
        testScheduler.runCurrent()
        assertEquals(2, r.characterCalls(), "로그아웃 상태에서 표를 물었다")
        r.wiring.stop()
    }

    /** 맥 말풍선 글 그대로 · duels 꺼짐이면 표면 0(풍선 0) · 켬이면 풍선 하나(오버레이 없음 = 토스트). 서버 요청 0. */
    @Test
    fun duelInviteNoticeUsesMacTextAndRespectsDuelsFlag() = runTest {
        val gomoku = DuelInviteNotice(GameWindowKind.Gomoku, "새벽", 5)
        assertEquals("새벽님이 오목 대결을 신청했어요 · 루비 5", gomoku.body)
        assertEquals("체스 대결 신청 · 루비 10", DuelInviteNotice(GameWindowKind.Chess, " ", 10).body)
        assertEquals("새벽님이 테트리스 대결을 신청했어요 · 루비 3", DuelInviteNotice(GameWindowKind.TetrisDuel, "새벽", 3).body)

        val off = W2ShellRig(this, DesktopAppConfig(duels = false))
        assertNull(off.wiring.handle.notifyDuelInvite(gomoku), "duels 꺼진 빌드가 신청을 알렸다")
        assertEquals(0, off.tray.balloons.size)

        val on = W2ShellRig(this, DesktopAppConfig(duels = true))
        assertEquals(NotifySurface.TOAST, on.wiring.handle.notifyDuelInvite(gomoku), "켠 빌드인데 알림이 안 갔다 — 꺼짐 단언이 헛돈다")
        assertEquals(listOf(NotifyKind.DUEL_INVITE), on.tray.balloons)
        testScheduler.runCurrent()
        assertEquals(0, off.h.paths.size + on.h.paths.size, "알림이 서버를 불렀다")
        off.wiring.stop()
        on.wiring.stop()
    }

    /** 울트라 화면이 보이다가 다른 화면·닫힘으로 바뀌면 한 번. 울트라를 안 거친 이동·닫힘은 0. */
    @Test
    fun leavingUltraPageClearsNoticeOnce() = runTest {
        var left = 0
        val r = W2ShellRig(this, onUltraPageLeft = { left++ })
        r.wiring.start()
        r.nav.open(FlyoutRoute.Home)
        testScheduler.runCurrent()
        r.nav.navigate(FlyoutRoute.Rankings("minigame"))
        r.nav.hide()
        testScheduler.runCurrent()
        assertEquals(0, left, "울트라를 안 거쳤는데 지웠다")

        r.nav.open(FlyoutRoute.Ultra)
        testScheduler.runCurrent()
        r.nav.navigate(FlyoutRoute.Home)
        testScheduler.runCurrent()
        assertEquals(1, left, "울트라 → 홈에서 안내를 안 지웠다")
        r.nav.navigate(FlyoutRoute.Ultra)
        testScheduler.runCurrent()
        r.nav.hide()
        testScheduler.runCurrent()
        assertEquals(2, left, "울트라를 연 채 닫았는데 안 지웠다")
        r.wiring.stop()
    }

    /** W-13 #7: 제품 ID(영숫자 대문자 12자)면 Store 주소, 비었거나 자리표시·틀린 꼴이면 AppLinks(WINDOWS)=null(단추 숨김). */
    @Test
    fun storeUpdateDestinationOnlyForValidProductId() {
        assertEquals("ms-windows-store://pdp/?ProductId=9NBLGGH4R315", StoreUpdateDestination.of("9NBLGGH4R315"))
        assertEquals("ms-windows-store://pdp/?ProductId=9NBLGGH4R315", StoreUpdateDestination.of(" 9NBLGGH4R315 "))
        assertNull(StoreUpdateDestination.of(""))
        assertNull(StoreUpdateDestination.of("__U7_STORE_PRODUCT_ID__"))
        assertNull(StoreUpdateDestination.of("9nblggh4r315"))
        assertNull(StoreUpdateDestination.of("9NBLGGH4R31"))
        // 이 저장소의 store.properties 는 자리표시 → 생성 상수 "" → 단추 숨김(지금과 같음).
        assertNull(StoreUpdateDestination.windows)

        val needs = SharedPage.NeedsUpdate(99)
        assertEquals(ShellOverlayPage.UPDATE, ShellPages.overlayFor(needs, "ms-windows-store://pdp/?ProductId=9NBLGGH4R315"))
        assertNull(ShellPages.overlayFor(needs, null), "목적지가 없는데 공용 화면을 덮었다")
        assertNull(ShellPages.overlayFor(SharedPage.Launching, "ms-windows-store://pdp/?ProductId=9NBLGGH4R315"))
        assertTrue(ShellPages.overlayFor(SharedPage.Missions, null) == ShellOverlayPage.MISSIONS)
    }
}
