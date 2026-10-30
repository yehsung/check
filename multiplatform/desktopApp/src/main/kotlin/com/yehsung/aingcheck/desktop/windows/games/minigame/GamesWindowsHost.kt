// 원본: Sources/check/CheckMiniGameWindow.swift:150-367(미니게임 창 — 창 넷의 원형) · CheckGomokuWindow.swift:6-35·302-356 ·
//       CheckChessWindow.swift:200-205·360-371 · CheckTetrisDuelWindow.swift:1-40·268-277 · CheckApp.swift:344-440(창 문 배선)
//       (W4-e 게임 창 넷 — games.md §2·§4. 창 수명은 W4-d kit 의 GameWindowSlot, 사건→통지 판정은 GameWindowEvents 표 한 곳)
package com.yehsung.aingcheck.desktop.windows.games.minigame

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameHub
import com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowHandle
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowSlot
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice
import com.yehsung.aingcheck.desktop.windows.kit.WindowBoundsStore
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent

/**
 * 게임 창 하나의 껍데기 — 실제 창을 만들고([createHandle]) 표가 낸 통지를 스토어로 옮긴다([onNotices]).
 * 판정은 하지 않는다(사건→통지는 kit `GameWindowEvents`, 통지→스토어 호출은 [BoardGameNoticeSink]·[MiniGameWindowState]).
 */
interface GameWindowShell {
    /** 창을 만든다(지연 생성 — 처음 열 때 한 번, 고착 재생성 때 다시). 창 사건은 [onEvent] 로, 자리 바뀜은 [onBoundsChanged] 로 넘긴다. */
    fun createHandle(onEvent: (WindowEvent) -> Unit, onBoundsChanged: () -> Unit): GameWindowHandle
    fun onNotices(notices: List<StoreNotice>)
    /** 통지 표에 없는 껍데기 몫(초점을 되찾으면 미니게임 화면에 '초점 있음'을 돌려준다 등). 표보다 **먼저** 부른다. */
    fun onWindowEvent(event: WindowEvent) = Unit
    /** 앱이 뒤에 있을 때 주의 끌기(FlashWindowEx). 창이 없으면 아무 일도 없다. */
    fun requestAttention() = Unit
}

/**
 * 판 게임 셋(오목·체스·테트리스 대결)의 스토어 창 문 — 맥 이름 그대로(GamesBoardGameLink · GomokuStore.kt:546-590 ·
 * ChessStore.kt:459-504 · TetrisDuelStore.kt:481-525). 스토어마다 얇은 어댑터가 구현한다(gomoku/·chess/·tetris/).
 */
interface BoardWindowDoors {
    fun windowDidShow()
    fun windowDidHide()
    fun windowDidClose()
    fun windowOcclusionDidChange(visible: Boolean)
}

/** 판 게임 창의 통지 → 스토어 호출. 표가 낸 순서 그대로 부른다(★CheckGomokuWindow.swift:314 — 닫힘은 DidHide 뒤 DidClose). */
object BoardGameNoticeSink {
    fun apply(doors: BoardWindowDoors, notices: List<StoreNotice>, readRefreshRate: () -> Unit = {}) {
        for (notice in notices) when (notice) {
            StoreNotice.DidShow -> doors.windowDidShow()
            StoreNotice.DidHide -> doors.windowDidHide()
            StoreNotice.DidClose -> doors.windowDidClose()
            is StoreNotice.Occlusion -> doors.windowOcclusionDidChange(notice.visible)
            StoreNotice.ReadRefreshRate -> readRefreshRate()
            // 판 게임 창에는 표가 내지 않는다(키 상실·닫기로 대국을 끝내지 않는다 — CheckGomokuWindow.swift:6-35). 빠짐없는 when 이라 새 통지는 여기서 멈춘다.
            StoreNotice.PauseIfPlaying, StoreNotice.EndRound, StoreNotice.MachineActive, StoreNotice.MachineInactive -> Unit
        }
    }
}

/** 미니게임 창이 무엇을 보이는가. 허브는 미니게임 창 안에 있다(games.md §1). */
sealed interface MiniGameWindowRoute {
    data object Hub : MiniGameWindowRoute
    data class Game(val kind: MiniGameKind) : MiniGameWindowRoute
    /** 닫힌 창 — 그리지 않는다(숨은 창이 판을 다시 열어 토큰을 받지 않게). 다시 열면 [last] 로 돌아간다. */
    data class Closed(val last: MiniGameKind?) : MiniGameWindowRoute
}

/**
 * 미니게임 창의 껍데기 상태. 통지 셋을 화면 값으로 옮긴다:
 *  · PauseIfPlaying → `windowFocused = false`(화면이 core MiniGamePauseState.resigningKey 로 얼린다 — ④ 키 상실은 **일시정지만**, 0.3.62)
 *  · EndRound → 허브 `closeScreen`(진행 중인 판을 끝낸다 — ③ 닫기 = 판 끝, CheckMiniGameWindow.swift:247. 기록 게임(테트리스·플래피 — quittingKeepsTheScore)은 여기까지 점수로 제출)
 *  · ReadRefreshRate → 창이 선 **뒤** 그 화면 주사율을 다시 읽는다(②·⑤ CheckMiniGameWindow.swift:225-232·276)
 */
class MiniGameWindowState(private val hub: GamesMiniGameHub, private val probeHz: () -> Int = { DEFAULT_HZ }) {
    var route: MiniGameWindowRoute by mutableStateOf(MiniGameWindowRoute.Hub)
        private set
    var windowFocused: Boolean by mutableStateOf(true)
        private set
    var refreshHz: Int by mutableStateOf(DEFAULT_HZ)
        private set

    /** 바깥 정지 토글 번호(ui GamesMiniGameScreen.pauseToggleSerial — 공용 패치 11). ESC 한 번 = +1([togglePause]). */
    var pauseToggleSerial: Int by mutableStateOf(0)
        private set

    /**
     * 판이 얼었는가(정지 카드 · 3-2-1) — 화면이 onFrozenChanged 로 적는다(화면이 사라지면 false). 얼어 있는 동안 키 라우터는 판 키를 받지 않는다
     * (맥 MiniGamePanel action `guard !pauseState.isFrozen` · wantsStrokes `!pauseState.isFrozen`).
     */
    var frozen: Boolean by mutableStateOf(false)
        internal set

    /** ESC = 정지 토글(맥 onEscape → PauseState.escaped). 전이는 화면의 core MiniGamePauseState.toggled 가 한다. */
    fun togglePause() {
        pauseToggleSerial += 1
    }

    /**
     * 창을 연다. [kind] 가 있으면 그 게임으로 — 노출 목록 밖(길건너 — W-3 #1)이면 허브에 남는다.
     * [kind] 없는 열기(플라이아웃 게임 레일 · 두 번째 실행)는 **멱등**이다 — 판 도중이면 그 판을 그대로 둔다(맥 show() 는 창만 앞으로,
     * CheckMiniGameWindow.swift:213-235 · 레일은 kind 없이 openMiniGameWindow(), CheckMenuView.swift:976-978). 허브로 돌리면 화면 수명의
     * closeScreen 이 판을 끝낸다(테트리스는 그 점수로 확정 제출, 플래피는 버림).
     */
    fun show(kind: MiniGameKind?) {
        windowFocused = true
        val current = route
        if (kind == null && current is MiniGameWindowRoute.Game) return
        val target = kind ?: (current as? MiniGameWindowRoute.Closed)?.last
        route = if (target != null && MiniGameExposure.isVisible(target)) MiniGameWindowRoute.Game(target) else MiniGameWindowRoute.Hub
    }

    /** 게임 화면의 뒤로 → 허브(화면이 사라지며 허브 `closeScreen` 이 판을 끝낸다 — ui GamesMiniGameScreen 의 화면 수명). */
    fun backToHub() {
        route = MiniGameWindowRoute.Hub
    }

    fun onWindowEvent(event: WindowEvent) {
        when (event) {
            WindowEvent.FocusGained, WindowEvent.Restored, WindowEvent.Shown -> windowFocused = true
            else -> Unit
        }
    }

    fun apply(notices: List<StoreNotice>) {
        for (notice in notices) when (notice) {
            StoreNotice.PauseIfPlaying -> {
                windowFocused = false
                hub.controller?.releaseAllKeys() // ★433 뗌 — 눌린 채 얼면 돌아와서 저절로 미끄러진다(대결 창과 같은 규칙)
            }
            StoreNotice.EndRound -> endRound()
            StoreNotice.ReadRefreshRate -> refreshHz = probeHz()
            StoreNotice.DidShow, StoreNotice.DidHide, StoreNotice.DidClose, is StoreNotice.Occlusion,
            StoreNotice.MachineActive, StoreNotice.MachineInactive -> Unit
        }
    }

    private fun endRound() {
        val game = route as? MiniGameWindowRoute.Game
        if (game != null) {
            // 닫기 = 판 끝, 기록이 남는 게임은 그 점수로 제출(맥 endRound(closing:) → settleMiniGameLiveRound → quittingKeepsTheScore,
            // CheckMiniGameWindow.swift:303 · MiniGamePanel.swift:567-570 · WorkTimerStoreMiniGame.swift:300-305).
            // 공용 패치 1 전 임시: core GamesPlayController.endRound(:408-427) 는 테트리스만 확정하고 플래피는 abandon 한다 —
            // 끝내기 **전에** 점수를 읽어 두고, core 가 버린(Abandoned) 기록 게임만 여기서 한 번 올린다. core 에 '닫기 = quittingKeepsTheScore 정산'
            // 문이 서면 이 가지를 지운다(shared_patch_requests).
            val live = hub.controller?.takeIf { it.kind == game.kind && it.isPlaying }
            val keptScore = live?.score
            // 화면이 사라지기 전에 허브에서 직접 끝낸다 — onDispose 의 closeScreen 은 그 뒤 no-op(activeKind 가 비었다) → 제출은 한 번.
            val outcome = live?.endRound()
            hub.closeScreen(game.kind)
            if (outcome == GamesPlayController.EndOutcome.Abandoned && keptScore != null && quittingKeepsTheScore(game.kind)) {
                hub.recordScore(game.kind, keptScore)
            }
        }
        route = MiniGameWindowRoute.Closed(game?.kind)
    }

    companion object {
        const val DEFAULT_HZ = 60

        /** 접어도(창 닫기) 기록이 남는 게임(맥 MiniGamePanel.swift:567-570 PauseState.quittingKeepsTheScore — 길건너는 Windows 에서 숨김). */
        fun quittingKeepsTheScore(kind: MiniGameKind): Boolean = when (kind) {
            MiniGameKind.tetris, MiniGameKind.flappy, MiniGameKind.crossy -> true
            MiniGameKind.timingBar -> false
        }
    }
}

/**
 * 게임 창 넷(미니게임·오목·체스·테트리스 대결)의 [DesktopGameWindows]. 뽑기·케이크 선물은 W4-f 의 구현([others])에 넘긴다.
 * 판 게임 창은 **스토어를 거쳐** 연다(맥 openWindow(focusMatchID) → 스토어가 조회를 쏘고 presentWindow → 이 호스트의 [present]).
 */
class GamesWindowsHost(
    private val shells: Map<GameWindowKind, GameWindowShell>,
    bounds: WindowBoundsStore,
    workAreas: () -> List<PxRect>,
    scale: () -> Double,
    private val miniGame: MiniGameWindowState?,
    private val storeOpen: StoreWindowOpeners = StoreWindowOpeners.None,
    private val others: DesktopGameWindows = DesktopGameWindows.None,
    /** 고착 감시 예약(맥 0.5초 — CheckGomokuWindow.swift:384-419). 실제 조립은 Swing 타이머, 시험은 기본값(예약 0). */
    private val later: (delayMs: Long, action: () -> Unit) -> Unit = { _, _ -> },
) : DesktopGameWindows {
    /** 판 게임 스토어의 openWindow(focusMatchID) — 조립(AppGraph)이 스토어를 잇는다. 없으면 바로 창만 연다. */
    interface StoreWindowOpeners {
        fun gomoku(focusMatchID: String?): Boolean
        fun chess(focusMatchID: String?): Boolean
        fun tetrisDuel(focusMatchID: String?): Boolean

        object None : StoreWindowOpeners {
            override fun gomoku(focusMatchID: String?) = false
            override fun chess(focusMatchID: String?) = false
            override fun tetrisDuel(focusMatchID: String?) = false
        }
    }

    private val slots: Map<GameWindowKind, GameWindowSlot> = OWN_KINDS.associateWith { kind ->
        val shell = requireNotNull(shells[kind]) { "껍데기 없음: $kind" }
        lateinit var slot: GameWindowSlot
        slot = GameWindowSlot(
            kind = kind,
            create = { shell.createHandle(onEvent = { event -> shell.onWindowEvent(event); slot.onEvent(event) }, onBoundsChanged = { slot.rememberBounds() }) },
            bounds = bounds,
            workAreas = workAreas,
            scale = scale,
            onNotices = shell::onNotices,
        )
        slot
    }

    fun slot(kind: GameWindowKind): GameWindowSlot = requireNotNull(slots[kind]) { "이 호스트의 창이 아니다: $kind" }

    /** 스토어 presentWindow 문 — 창을 (지연 생성해) 앞으로. */
    fun present(kind: GameWindowKind) {
        val slot = slot(kind)
        slot.open()
        later(GameWindowSlot.STUCK_CHECK_DELAY_MS) { slot.checkStuck() }
    }

    /** 스토어 dismissWindow 문(로그아웃 reset — 앞 계정의 판이 떠 있으면 안 된다). */
    fun dismiss(kind: GameWindowKind) = slot(kind).closeFromApp()

    fun requestAttention(kind: GameWindowKind) {
        if (slot(kind).isCreated) shells[kind]?.requestAttention()
    }

    override fun openGames(kind: MiniGameKind?) {
        miniGame?.show(kind)
        present(GameWindowKind.MiniGame)
    }

    override fun openGomoku(focusMatchID: String?) {
        if (!storeOpen.gomoku(focusMatchID)) present(GameWindowKind.Gomoku)
    }

    override fun openChess(focusMatchID: String?) {
        if (!storeOpen.chess(focusMatchID)) present(GameWindowKind.Chess)
    }

    override fun openTetrisDuel(focusMatchID: String?) {
        if (!storeOpen.tetrisDuel(focusMatchID)) present(GameWindowKind.TetrisDuel)
    }

    override fun openGacha() = others.openGacha()

    override fun openCakeGift() = others.openCakeGift()

    override fun closeAll() {
        OWN_KINDS.forEach { slot(it).closeFromApp() }
        others.closeAll()
    }

    companion object {
        val OWN_KINDS: List<GameWindowKind> = listOf(GameWindowKind.MiniGame, GameWindowKind.Gomoku, GameWindowKind.Chess, GameWindowKind.TetrisDuel)
    }
}
