// 원본: 없음(시험) — W-6 #6(배선마다 가짜로 한 바퀴) · W-6 #1(poke 깃발 꺼짐 = take_pokes·발신 0) · W-3 #7(duels 꺼짐 = 신청 점 0) ·
//       W3-c1(트레이 클릭·메뉴·두 번째 실행) · W3-c5(플라이아웃 열 때 조회 · 60초 스로틀) · W3-c0(메시지 배경 갱신 60초).
// 가짜만: 스텁 서버(SharedTestHarness — MockEngine 녹음) · 가짜 트레이·창·전원·테마 · InMemoryDesktopKeyValueStore. 창 0.
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.RasterImage
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayClick
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayHost
import com.yehsung.aingcheck.core.rules.format.WorkStatus
import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionProfile
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.desktop.pages.shared.SharedPage
import com.yehsung.aingcheck.desktop.pages.shared.SharedTestHarness
import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacement
import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacer
import com.yehsung.aingcheck.desktop.platform.windows.tray.TaskbarTheme
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutController
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutScreen
import com.yehsung.aingcheck.desktop.shell.flyout.SyntheticScreen
import com.yehsung.aingcheck.desktop.shell.notify.ShellNotice
import com.yehsung.aingcheck.desktop.shell.tray.TrayMenuItemId
import com.yehsung.aingcheck.desktop.shell.tray.TrayMenuPresenter
import com.yehsung.aingcheck.desktop.shell.update.UpdatePollSchedule
import com.yehsung.aingcheck.desktop.shellapi.BalloonNotifier
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.shellapi.NotifyContext
import com.yehsung.aingcheck.desktop.shellapi.NotifyKind
import com.yehsung.aingcheck.desktop.shellapi.NotifySurface
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import java.util.concurrent.Executor
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class FakeTray : TrayHost, BalloonNotifier {
    var shows = 0
    var updates = 0
    var removes = 0
    var clickRegistrations = 0
    var clickClosed = 0
    private var click: ((TrayClick, Int, Int) -> Unit)? = null
    val balloons = mutableListOf<NotifyKind>()
    override fun show(icon: RasterImage, tooltip: String) { shows++ }
    override fun update(icon: RasterImage, tooltip: String) { updates++ }
    override fun remove() { removes++ }
    override fun addClickListener(listener: (click: TrayClick, screenX: Int, screenY: Int) -> Unit): Registration {
        click = listener
        clickRegistrations++
        return Registration { clickClosed++; click = null }
    }
    fun click(kind: TrayClick) = click?.invoke(kind, 1900, 1050)
    override fun showBalloon(title: String, body: String, kind: NotifyKind, respectQuietTime: Boolean): Boolean { balloons += kind; return true }
    override fun setOnBalloonClick(handler: (NotifyKind) -> Unit) {}
}

internal class FakeWindowPort : FlyoutWindowPort {
    var attached = 0
    var precreated = 0
    var shows = 0
    var hides = 0
    override fun show(placement: FlyoutPlacement) { shows++ }
    override fun hide() { hides++ }
    override fun attach(pages: FlyoutPageHost, nav: FlyoutController) { attached++ }
    override fun precreate() { precreated++ }
}

internal class CountingRegistrations {
    var added = 0
    var closed = 0
    fun reg(): Registration { added++; return Registration { closed++ } }
}

@OptIn(ExperimentalCoroutinesApi::class)
internal class ShellRig(
    scope: TestScope,
    val config: DesktopAppConfig = DesktopAppConfig(),
    answer: (String) -> String? = SharedTestHarness.withTeam,
    schedule: UpdatePollSchedule = UpdatePollSchedule(initialDelayMillis = FAR, intervalMillis = FAR),
    inviteDots: Flow<InviteDots> = flowOf(InviteDots.NONE),
    menu: TrayMenuPresenter? = null,
) {
    val h = SharedTestHarness(scope, answer, config)
    val tray = FakeTray()
    val port = FakeWindowPort()
    val power = CountingRegistrations()
    val theme = CountingRegistrations()
    val instance = CountingRegistrations()
    var activate: (() -> Unit)? = null
    var toggles = 0
    val work = MutableStateFlow(WorkStatusSnapshot(WorkStatus.offWork, 0))
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
                override fun addListener(listener: (PowerEvent) -> Unit): Registration = power.reg()
            },
            work = work,
            toggleWork = { toggles++ },
            quit = {},
            events = Executor { it.run() },
            window = port,
            screen = FlyoutScreen { SyntheticScreen.facts },
            menu = menu,
            instanceListen = { onActivate -> activate = onActivate; instance.reg() },
            theme = object : TaskbarThemeSource {
                override fun current(): TaskbarTheme = TaskbarTheme.LIGHT
                override fun addListener(listener: (TaskbarTheme) -> Unit): Registration = theme.reg()
            },
            rankingsFace = { RankingsMyFace("aing", CharacterMood.entries.first()) },
            inviteDots = inviteDots,
            updateSchedule = schedule,
        ),
    )
    val nav get() = wiring.handle.nav

    fun count(fragment: String): Int = h.paths.count { it.contains(fragment) }

    companion object {
        const val FAR = 1_000_000_000L
        val TOAST_CTX = NotifyContext(overlayVisible = false, fullscreenQuiet = false, bubbleAllowedByFocus = true, toastEnabled = true)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class ShellWiringTest {
    /** start → stop 한 바퀴: 붙이기·미리 만들기·구독 넷(클릭·전원·테마·두 번째 실행)이 서고, stop 이 전부 걷고 트레이를 내린다. */
    @Test
    fun startThenStopAttachesAndReleasesEverything() = runTest {
        val r = ShellRig(this)
        r.h.signIn()
        r.wiring.start()
        testScheduler.runCurrent()
        assertEquals(1, r.port.attached, "창에 페이지를 붙이지 않았다")
        assertEquals(1, r.port.precreated, "창을 미리 만들지 않았다")
        assertEquals(1, r.tray.clickRegistrations)
        assertEquals(1, r.power.added, "업데이트 조회기가 전원 사건을 듣지 않는다")
        assertEquals(1, r.theme.added, "테마 변화를 듣지 않는다")
        assertEquals(1, r.instance.added, "두 번째 실행을 듣지 않는다")
        assertEquals(1, r.tray.shows, "트레이 첫 그림이 없다")
        assertEquals(TaskbarTheme.LIGHT, r.wiring.handle.theme.value)

        // 두 번 start 해도 한 벌.
        r.wiring.start()
        assertEquals(1, r.tray.clickRegistrations, "start 두 번에 구독이 겹쳤다")

        // 왼쪽 클릭 = 열기, 다시 = 닫기. 두 번째 실행 = 열기.
        r.tray.click(TrayClick.PRIMARY)
        assertTrue(r.nav.visible.value)
        r.tray.click(TrayClick.PRIMARY)
        assertFalse(r.nav.visible.value)
        requireNotNull(r.activate).invoke()
        assertTrue(r.nav.visible.value, "두 번째 실행 신호가 플라이아웃을 열지 않았다")

        // 음성 대조: 도는 동안엔 메시지 배경 갱신이 60초마다 요약을 부른다.
        val before = r.h.paths.size
        testScheduler.advanceTimeBy(125_000)
        testScheduler.runCurrent()
        assertTrue(r.h.paths.size > before, "배경 갱신이 돌지 않는다 — 아래 '멈춤' 단언이 헛돈다")

        r.wiring.stop()
        assertEquals(1, r.tray.removes, "stop 이 트레이를 내리지 않았다")
        assertEquals(1, r.tray.clickClosed)
        assertEquals(1, r.power.closed, "업데이트 전원 Registration 을 닫지 않았다")
        assertEquals(1, r.theme.closed)
        assertEquals(1, r.instance.closed)
        assertFalse(r.nav.visible.value, "stop 뒤에도 플라이아웃이 열려 있다")
        val frozen = r.h.paths.size
        testScheduler.advanceTimeBy(300_000)
        testScheduler.runCurrent()
        assertEquals(frozen, r.h.paths.size, "stop 뒤에도 서버를 부른다: ${r.h.paths.drop(frozen)}")
        r.tray.click(TrayClick.PRIMARY)
        assertFalse(r.nav.visible.value, "stop 뒤 클릭이 플라이아웃을 열었다")
    }

    /** W-6 #1: poke 꺼짐 → 껍데기는 찌르기를 알리지 않고(풍선 0) 서버 take_pokes 도 0. 켬과 견준다. */
    @Test
    fun pokeFlagOffDeliversNothingAndNeverTakesPokes() = runTest {
        val off = ShellRig(this, DesktopAppConfig(poke = false))
        off.h.signIn()
        off.wiring.start()
        testScheduler.advanceTimeBy(185_000)
        testScheduler.runCurrent()
        assertNull(off.wiring.handle.notifier.deliver(ShellNotice(NotifyKind.POKE, "콕", "누가 찔렀다"), ShellRig.TOAST_CTX))
        assertTrue(off.tray.balloons.isEmpty(), "깃발 꺼진 찌르기가 풍선으로 떴다")
        assertEquals(FlyoutRoute.Messages, off.wiring.handle.notifier.routeFor(ShellNotice(NotifyKind.MESSAGE, "t", "b")))
        assertEquals(0, off.count("take_pokes"), "poke 꺼진 껍데기가 take_pokes 를 불렀다: ${off.h.paths}")
        assertTrue(off.h.paths.isNotEmpty(), "서버 녹음이 비었다 — 0 단언이 헛돈다")
        off.wiring.stop()

        // 음성 대조: 켜면 같은 사건이 풍선으로 가고 목적지가 콕 목록이다. 그래도 껍데기는 take_pokes 를 부르지 않는다(소셜 배선 몫 — 2회 금지).
        val on = ShellRig(this, DesktopAppConfig(poke = true))
        on.h.signIn()
        on.wiring.start()
        testScheduler.advanceTimeBy(185_000)
        testScheduler.runCurrent()
        assertEquals(NotifySurface.TOAST, on.wiring.handle.notifier.deliver(ShellNotice(NotifyKind.POKE, "콕", "누가 찔렀다"), ShellRig.TOAST_CTX))
        assertEquals(listOf(NotifyKind.POKE), on.tray.balloons)
        assertEquals(FlyoutRoute.PokeList, on.wiring.handle.notifier.routeFor(ShellNotice(NotifyKind.MESSAGE, "t", "b")))
        assertEquals(0, on.count("take_pokes"), "껍데기가 take_pokes 를 부른다 — 소셜 poller 와 겹쳐 2회가 된다: ${on.h.paths}")
        on.wiring.stop()
    }

    /** W-3 #7: duels 꺼짐 → 게임 스토어가 신청을 알려도 트레이 점 0 · 신청 안내 0. 켬과 견준다. */
    @Test
    fun duelsFlagOffKeepsInviteDotAndNoticeOff() = runTest {
        val invites = flowOf(InviteDots(gomoku = true, chess = true, tetris = true))
        val off = ShellRig(this, DesktopAppConfig(duels = false), inviteDots = invites)
        off.wiring.start()
        testScheduler.runCurrent()
        val dotsOff = off.wiring.handle.dots.value
        assertFalse(dotsOff.gomokuInvite || dotsOff.chessInvite || dotsOff.tetrisInvite, "duels 꺼진 빌드에 신청 점: $dotsOff")
        assertNull(off.wiring.handle.notifier.deliver(ShellNotice(NotifyKind.DUEL_INVITE, "오목", "신청"), ShellRig.TOAST_CTX))
        off.wiring.stop()

        val on = ShellRig(this, DesktopAppConfig(duels = true), inviteDots = invites)
        on.wiring.start()
        testScheduler.runCurrent()
        assertTrue(on.wiring.handle.dots.value.gomokuInvite, "켠 빌드인데 점이 없다 — 꺼짐 단언이 헛돈다")
        on.wiring.stop()
    }

    /** W3-c5: 플라이아웃이 열릴 때마다 조회 — 60초 안에 다시 열면 스로틀, 지나면 한 번 더. 업데이트 점은 조회기 상태에서. */
    @Test
    fun flyoutOpenChecksForUpdatesWithSixtySecondThrottle() = runTest {
        val release = """{"status":"ok","platform":"windows","min_build":1,"latest_build":99}"""
        val r = ShellRig(this, answer = { path -> if (path.endsWith("/rpc/client_release")) release else SharedTestHarness.withTeam(path) })
        r.wiring.start()
        testScheduler.runCurrent()
        val base = r.count("client_release")
        r.nav.open()
        testScheduler.runCurrent()
        assertEquals(base + 1, r.count("client_release"), "열었는데 조회하지 않았다: ${r.h.paths}")
        r.nav.hide()
        testScheduler.advanceTimeBy(10_000)
        r.nav.open()
        testScheduler.runCurrent()
        assertEquals(base + 1, r.count("client_release"), "60초 안 재열기가 스로틀을 넘었다")
        r.nav.hide()
        testScheduler.advanceTimeBy(61_000)
        r.nav.open()
        testScheduler.runCurrent()
        assertEquals(base + 2, r.count("client_release"), "60초 뒤 재열기가 조회하지 않았다")
        assertTrue(r.wiring.handle.dots.value.updateAvailable, "새 빌드(99)인데 업데이트 점이 없다")
        r.wiring.stop()
    }

    /** W3-c1: 오른쪽 클릭 메뉴 — 로그인 전엔 '근무 시작' 칸이 꺼져 골라도 안 하고, 로그인 뒤엔 한 번 한다. */
    @Test
    fun trayMenuToggleWorkOnlyWhenSignedIn() = runTest {
        val menu = TrayMenuPresenter { _, _, _ -> TrayMenuItemId.TOGGLE_WORK }
        val r = ShellRig(this, menu = menu)
        r.wiring.start()
        testScheduler.runCurrent()
        r.tray.click(TrayClick.SECONDARY)
        assertEquals(0, r.toggles, "로그인 전에 근무 토글이 됐다")
        r.h.signIn()
        testScheduler.runCurrent()
        assertEquals(SessionPhase.SignedIn, r.h.session.phaseFlow.value)
        r.tray.click(TrayClick.SECONDARY)
        assertEquals(1, r.toggles)
        r.wiring.stop()
    }

    /** 폭(W3-c1): 로그인 화면 · 무소속 = 340, 소속 있음 = 414. 상점·미션 덮개는 공용 라우터 판정 뒤에만. */
    @Test
    fun widthsAndOverlayPagesFollowTheSharedRouter() {
        val teamless = SessionProfile(userID = "u", email = null, teamID = null)
        val inTeam = SessionProfile(userID = "u", email = null, teamID = "t")
        assertEquals(FlyoutPlacer.NARROW_WIDTH_DIP, ShellWidths.requested(SessionPhase.SignedOut, null))
        assertEquals(FlyoutPlacer.NARROW_WIDTH_DIP, ShellWidths.requested(SessionPhase.SignedIn, teamless))
        assertEquals(FlyoutPlacer.WIDTH_DIP, ShellWidths.requested(SessionPhase.SignedIn, inTeam))
        assertEquals(ShellOverlayPage.SHOP, ShellPages.overlayFor(SharedPage.Pending(FlyoutRoute.Shop)))
        assertEquals(ShellOverlayPage.MISSIONS, ShellPages.overlayFor(SharedPage.Missions))
        assertNull(ShellPages.overlayFor(SharedPage.SignedOut), "로그아웃 화면을 상점이 덮었다")
        assertNull(ShellPages.overlayFor(SharedPage.Pending(FlyoutRoute.Ultra)))
    }
}
