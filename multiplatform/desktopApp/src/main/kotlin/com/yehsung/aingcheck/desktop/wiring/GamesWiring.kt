// 원본: 없음(새 코드) — W-windows-resume W-6 #6(조립 구조) · W-3 #7(duels 깃발 꺼짐 = 대결 신청 안내 0) ·
//       갈래 보고 coordinator_patches: W4-d(DesktopGameWindows 실구현 · 로그아웃·계정 전환 → closeAll() · KeyValueWindowBoundsStore(기기 단위,
//       접두 'windowBounds.')) · W4-e(EDT 에서 ComposeGamesWindows.create(…) — GameWindowWiring.wire 는 create 안 · others = W4-f 호스트 ·
//       게임 레일 → openGames/openGomoku/openChess/openTetrisDuel) · W4-f(GachaWindowHost · CakeGiftWindowHost(userIsLooking = 플라이아웃 보임).start)
//
// 게임 창 한 벌을 의존 묶음([GamesDeps])에서 만든다. 창은 문([GameWindowFactory])으로만 짓는다 — 시험은 가짜 문(창 0), 앱은 [GameWindowFactory.Compose].
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.desktop.windows.cakegift.CakeGiftWindowHost
import com.yehsung.aingcheck.desktop.windows.gacha.GachaWindowHost
import com.yehsung.aingcheck.desktop.windows.games.minigame.ComposeGamesWindows
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.windows.kit.KeyValueWindowBoundsStore
import com.yehsung.aingcheck.desktop.windows.kit.WindowBoundsStore
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** 뽑기 창 문(W4-f GachaWindowHost). */
interface GachaDoor {
    fun open()
    fun close()
}

/** 케이크 선물 창 문(W4-f CakeGiftWindowHost — 시트가 서면 스스로 뜬다). */
interface CakeGiftDoor {
    fun start(scope: CoroutineScope): Job
    fun openByUser()
    fun close()
}

/** 창을 짓는 문. 앱 = [Compose](EDT 에서 부른다), 시험 = 가짜(창 0 — 기억 agents-no-visible-windows). */
interface GameWindowFactory {
    /** 미니게임·오목·체스·테트리스 대결 창(W4-e). [others] = 뽑기·케이크(W4-f) — 보드 호스트가 openGacha·openCakeGift·closeAll 을 넘긴다. */
    fun board(deps: GamesDeps, bounds: WindowBoundsStore, others: DesktopGameWindows): DesktopGameWindows
    fun gacha(deps: GamesDeps, bounds: WindowBoundsStore): GachaDoor
    fun cake(deps: GamesDeps, bounds: WindowBoundsStore): CakeGiftDoor

    object Compose : GameWindowFactory {
        override fun board(deps: GamesDeps, bounds: WindowBoundsStore, others: DesktopGameWindows): DesktopGameWindows =
            ComposeGamesWindows.create(
                games = deps.games,
                gomoku = deps.gomoku,
                chess = deps.chess,
                config = deps.desktopConfig,
                bounds = bounds,
                workAreas = deps.workAreas,
                scale = deps.scale,
                dark = deps.dark,
                reduceMotion = deps.reduceMotion,
                me = deps.boardMe,
                myUserID = { deps.session.profileFlow.value?.userID },
                now = deps.now,
                onOpenShop = { deps.flyout.open(FlyoutRoute.Shop) },
                onOpenRankings = { deps.flyout.open(FlyoutRoute.Rankings(RankingsBoard.minigame.rawValue)) },
                others = others,
                onInvite = deps.onInvite,
                onTurnWhileHidden = deps.onTurnWhileHidden,
            )

        override fun gacha(deps: GamesDeps, bounds: WindowBoundsStore): GachaDoor {
            val host = GachaWindowHost(deps.me, bounds, deps.workAreas, deps.scale, deps.reduceMotion)
            return object : GachaDoor {
                override fun open() = host.open()
                override fun close() = host.close()
            }
        }

        override fun cake(deps: GamesDeps, bounds: WindowBoundsStore): CakeGiftDoor {
            val host = CakeGiftWindowHost(deps.me, bounds, deps.workAreas, deps.scale, userIsLooking = { deps.flyout.visible.value })
            return object : CakeGiftDoor {
                override fun start(scope: CoroutineScope): Job = host.start(scope)
                override fun openByUser() = host.openByUser()
                override fun close() = host.close()
            }
        }
    }
}

/**
 * 게임 창 의존 묶음. 스토어는 이미 지은 것(AppGraph). [deviceStore] = dataDir 의 기기 단위 설정 — 창 자리 키는 'windowBounds.<창>'.
 * [flyout] = 껍데기 손잡이의 nav(상점·순위 열기 · 케이크 창의 '보고 있나').
 */
data class GamesDeps(
    val games: GamesStore,
    val gomoku: GomokuStore,
    val chess: ChessStore,
    val me: MeStore,
    val session: SessionStore,
    val desktopConfig: DesktopAppConfig,
    val deviceStore: DesktopKeyValueStore,
    val flyout: FlyoutNavigator,
    /** 모니터별 작업 영역(물리 픽셀). */
    val workAreas: () -> List<PxRect>,
    val scale: () -> Double = { 1.0 },
    val dark: () -> Boolean = { false },
    val reduceMotion: () -> Boolean = { false },
    val boardMe: () -> BoardGameMe = { BoardGameMe.unknown },
    val now: () -> SwiftDate,
    /** 대결 신청 도착(깃발 duels 가 켜졌을 때만 온다 — GameWindowWiring). 조립: 껍데기 notifier 로 DUEL_INVITE. */
    val onInvite: (GameWindowKind) -> Unit = {},
    val onTurnWhileHidden: (GameWindowKind) -> Unit = {},
    val factory: GameWindowFactory = GameWindowFactory.Compose,
)

data class GamesHandle(
    /** 플라이아웃 게임 레일·상점(뽑기)·알림이 여는 문 하나. */
    val windows: DesktopGameWindows,
    val bounds: WindowBoundsStore,
    val gacha: GachaDoor,
    val cake: CakeGiftDoor,
)

class GamesWiring(private val deps: GamesDeps) {
    private val bounds: WindowBoundsStore = KeyValueWindowBoundsStore(deps.deviceStore, BOUNDS_PREFIX)
    private val gacha = deps.factory.gacha(deps, bounds)
    private val cake = deps.factory.cake(deps, bounds)
    private val others = object : DesktopGameWindows {
        override fun openGames(kind: MiniGameKind?) = Unit
        override fun openGomoku(focusMatchID: String?) = Unit
        override fun openChess(focusMatchID: String?) = Unit
        override fun openTetrisDuel(focusMatchID: String?) = Unit
        override fun openGacha() = gacha.open()
        override fun openCakeGift() = cake.openByUser()
        override fun closeAll() {
            gacha.close()
            cake.close()
        }
    }
    private val board = deps.factory.board(deps, bounds, others)

    val handle = GamesHandle(windows = board, bounds = bounds, gacha = gacha, cake = cake)

    private val jobs = mutableListOf<Job>()

    /**
     * 케이크 창 감시 + 계정 감시(W4-d): 로그인했던 사람이 로그아웃하거나 다른 계정으로 바뀌면 [DesktopGameWindows.closeAll] 한 번.
     * 처음부터 로그아웃이면 부르지 않는다. 두 번 불러도 한 번.
     */
    fun start(scope: CoroutineScope) {
        if (jobs.isNotEmpty()) return
        jobs += cake.start(scope)
        jobs += scope.launch {
            var last: String? = null
            deps.session.profileFlow.map { it?.userID }.distinctUntilChanged().collect { user ->
                if (last != null && user != last) board.closeAll()
                last = user
            }
        }
    }

    /** 구독만 걷는다. 창은 프로세스와 함께 내린다(종료 훅에서 EDT 를 기다리지 않는다). */
    fun stop() {
        jobs.forEach { it.cancel() }
        jobs.clear()
    }

    companion object {
        /** W4-d: 창 자리 키 접두(KeyValueWindowBoundsStore 기본과 같다 — 조립에서 한 번 더 적어 둔다). */
        const val BOUNDS_PREFIX = "windowBounds."
    }
}
