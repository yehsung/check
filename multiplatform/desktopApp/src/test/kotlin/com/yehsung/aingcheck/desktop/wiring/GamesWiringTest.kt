// 원본: 없음(시험) — W-6 #6(배선마다 가짜로 한 바퀴) · W4-d(로그아웃·계정 전환 → closeAll · 창 자리 키 'windowBounds.') ·
//       W4-e·W4-f(보드 호스트의 others = 뽑기·케이크) · W-3 #7(duels 꺼짐 = 신청 안내 0 — 실제 ComposeGamesWindows.create 경로).
// 가짜만: 스텁 서버(SharedTestHarness·BoardGameRig — MockEngine 녹음) · 가짜 창 문 · InMemoryDesktopKeyValueStore. 창 0(열지 않는다).
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.gomoku.GomokuInvite
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.pages.shared.SharedTestHarness
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.shellapi.InMemoryFlyoutNavigator
import com.yehsung.aingcheck.desktop.windows.games.minigame.GameWindowScenes
import com.yehsung.aingcheck.desktop.windows.games.minigame.rig.BoardGameRig
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.windows.kit.WindowBoundsStore
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.ui.games.gomoku.boardClock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

internal class FakeBoardWindows : DesktopGameWindows {
    var closeAlls = 0
    var others: DesktopGameWindows = DesktopGameWindows.None
    /** 판 창 열기 기록("gomoku:<판 id>" — 오버레이 말풍선 클릭 시험). */
    val opened = mutableListOf<String>()
    override fun openGames(kind: MiniGameKind?) = Unit
    override fun openGomoku(focusMatchID: String?) { opened += "gomoku:$focusMatchID" }
    override fun openChess(focusMatchID: String?) { opened += "chess:$focusMatchID" }
    override fun openTetrisDuel(focusMatchID: String?) { opened += "tetris:$focusMatchID" }
    override fun openGacha() = others.openGacha()
    override fun openCakeGift() = others.openCakeGift()
    override fun closeAll() { closeAlls++; others.closeAll() }
}

internal class FakeGameFactory(private val realBoard: Boolean = false) : GameWindowFactory {
    val board = FakeBoardWindows()
    /** 조립이 넘긴 GamesDeps(구조 신청·차례 알림 문을 실제 그래프 그대로 부르는 시험용). */
    var deps: GamesDeps? = null
    var gachaOpens = 0
    var gachaCloses = 0
    var cakeStarts = 0
    var cakeOpens = 0
    var cakeCloses = 0
    var cakeJob: Job? = null

    override fun board(deps: GamesDeps, bounds: WindowBoundsStore, others: DesktopGameWindows): DesktopGameWindows {
        this.deps = deps
        return if (realBoard) GameWindowFactory.Compose.board(deps, bounds, others) else board.also { it.others = others }
    }

    override fun gacha(deps: GamesDeps, bounds: WindowBoundsStore): GachaDoor = object : GachaDoor {
        override fun open() { gachaOpens++ }
        override fun close() { gachaCloses++ }
    }

    override fun cake(deps: GamesDeps, bounds: WindowBoundsStore): CakeGiftDoor = object : CakeGiftDoor {
        override fun start(scope: CoroutineScope): Job { cakeStarts++; return scope.launch { kotlinx.coroutines.awaitCancellation() }.also { cakeJob = it } }
        override fun openByUser() { cakeOpens++ }
        override fun close() { cakeCloses++ }
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
internal class GamesRig(
    scope: TestScope,
    config: DesktopAppConfig = DesktopAppConfig(),
    realBoard: Boolean = false,
) {
    val h = SharedTestHarness(scope, SharedTestHarness.withTeam, config)
    val board = BoardGameRig(me = null, duelsEnabled = config.toAppConfig().duelsEnabled)
    val factory = FakeGameFactory(realBoard)
    val deviceStore = InMemoryDesktopKeyValueStore()
    val flyout = InMemoryFlyoutNavigator()
    val invites = mutableListOf<GameWindowKind>()
    val wiring = GamesWiring(
        GamesDeps(
            games = board.games,
            gomoku = board.gomoku,
            chess = board.chess,
            me = h.me,
            session = h.session,
            desktopConfig = config,
            deviceStore = deviceStore,
            flyout = flyout,
            workAreas = { listOf(PxRect(0, 0, 1920, 1032)) },
            now = { SwiftDate(1_789_621_500.0) },
            onInvite = { invites += it },
            factory = factory,
        ),
    )
}

@OptIn(ExperimentalCoroutinesApi::class)
class GamesWiringTest {
    /** start → stop 한 바퀴 + W4-d: 처음 로그아웃은 닫지 않고, 로그아웃 · 계정 전환마다 closeAll 한 번, stop 뒤엔 0. */
    @Test
    fun startThenStopClosesWindowsOnSignOutAndAccountSwitchOnly() = runTest {
        val r = GamesRig(this)
        r.wiring.start(r.h.storeScope)
        r.wiring.start(r.h.storeScope)
        testScheduler.runCurrent()
        assertEquals(1, r.factory.cakeStarts, "케이크 감시가 없거나 겹쳤다")
        assertEquals(0, r.factory.board.closeAlls, "처음부터 로그아웃인데 창을 닫았다")

        r.h.signIn(SharedTestHarness.USER)
        testScheduler.runCurrent()
        assertEquals(0, r.factory.board.closeAlls, "로그인만 했는데 창을 닫았다")
        r.h.signIn(OTHER_USER)
        testScheduler.runCurrent()
        assertEquals(1, r.factory.board.closeAlls, "계정 전환에 창을 닫지 않았다")
        assertEquals(1, r.factory.gachaCloses, "closeAll 이 뽑기 창(others)까지 가지 않았다")
        assertEquals(1, r.factory.cakeCloses, "closeAll 이 케이크 창(others)까지 가지 않았다")

        r.wiring.stop()
        assertTrue(r.factory.cakeJob?.isCancelled == true, "stop 이 케이크 감시를 걷지 않았다")
        r.h.signIn(SharedTestHarness.USER)
        testScheduler.runCurrent()
        assertEquals(1, r.factory.board.closeAlls, "stop 뒤에도 계정 감시가 돈다")
    }

    /** W4-e·W4-f: 보드 호스트의 others = 뽑기·케이크. 창 자리 키 = 'windowBounds.' + 창(W4-d). */
    @Test
    fun othersRouteToGachaAndCakeAndBoundsUseDevicePrefix() = runTest {
        val r = GamesRig(this)
        val windows = r.wiring.handle.windows
        assertSame(r.factory.board, windows)
        windows.openGacha()
        windows.openCakeGift()
        assertEquals(1, r.factory.gachaOpens)
        assertEquals(1, r.factory.cakeOpens)
        r.wiring.handle.bounds.save(GameWindowKind.Gomoku.boundsKey, PxRect(10, 20, 410, 620))
        assertEquals(listOf(GamesWiring.BOUNDS_PREFIX + GameWindowKind.Gomoku.boundsKey), r.deviceStore.keys(GamesWiring.BOUNDS_PREFIX))
        assertEquals(PxRect(10, 20, 410, 620), r.wiring.handle.bounds.load(GameWindowKind.Gomoku.boundsKey))
    }

    /**
     * W-3 #7 — 실제 ComposeGamesWindows.create(창은 열지 않는다): duels 꺼짐이면 오목 신청이 와도 안내 0, 켬이면 1.
     * 배선 한 바퀴 동안 대결 서버 경로 요청은 0(배선이 스스로 서버를 부르지 않는다 — MockEngine 녹음).
     */
    @Test
    fun duelsFlagOffSuppressesInviteNoticeThroughRealBoardWiring() = runTest {
        val invite = GomokuInvite("11111111-0000-4000-8000-0000000000a1", GameWindowScenes.SEED_USERS[0], 5, boardClock)

        val off = GamesRig(this, DesktopAppConfig(duels = false), realBoard = true)
        off.wiring.start(off.h.storeScope)
        testScheduler.runCurrent()
        requireNotNull(off.board.gomoku.onInviteArrived) { "실제 보드 배선이 오목 문을 잇지 않았다" }.invoke(invite)
        assertEquals(0, off.invites.size, "duels 꺼진 빌드가 신청 안내를 냈다")
        assertNotNull(off.board.chess.presentWindow, "실제 보드 배선이 체스 문을 잇지 않았다")
        off.board.settle()
        assertEquals(0, off.board.server.calls.size + off.h.paths.count { DUEL_PATHS.any(it::contains) }, "배선이 서버를 불렀다")
        off.wiring.stop()

        val on = GamesRig(this, DesktopAppConfig(duels = true), realBoard = true)
        requireNotNull(on.board.gomoku.onInviteArrived).invoke(invite)
        assertEquals(listOf(GameWindowKind.Gomoku), on.invites, "켠 빌드인데 안내가 안 갔다 — 꺼짐 단언이 헛돈다")
        on.board.close()
        off.board.close()
    }

    companion object {
        const val OTHER_USER = "d0000000-0000-4000-8000-000000000002"
        val DUEL_PATHS = listOf("gomoku", "chess", "tetris")
    }
}
