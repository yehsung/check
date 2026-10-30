// 원본: Sources/check/CheckMiniGameWindow.swift:150-367(창 만들기·사건 연결 — 나머지 창이 "그대로 베꼈다") · MiniGamePanel.swift:146-460(키 모니터) ·
//       CheckTetrisDuelWindow.swift:1-40(전용 키 게이트 "키가 향한 창 === 이 창") · ★433(뗌 먼저) · CheckApp.swift:344-440(조립)
//       (W4-e — 실제 AWT/Compose 창. 시험은 이 파일을 쓰지 않는다: 창 0 — 손잡이는 GameWindowShell 뒤에서 가짜로 바뀐다)
package com.yehsung.aingcheck.desktop.windows.games.minigame

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.awt.ComposeWindow
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterDirectory
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.windows.games.chess.ChessWindowContent
import com.yehsung.aingcheck.desktop.windows.games.chess.ChessWindowDoors
import com.yehsung.aingcheck.desktop.windows.games.gomoku.GomokuWindowContent
import com.yehsung.aingcheck.desktop.windows.games.gomoku.GomokuWindowDoors
import com.yehsung.aingcheck.desktop.windows.games.gomoku.GomokuWindowSafety
import com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelIme
import com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelInput
import com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelKeys
import com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelWindowContent
import com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelWindowDoors
import com.yehsung.aingcheck.desktop.windows.games.tetris.TetrisDuelWindowState
import com.yehsung.aingcheck.desktop.windows.kit.AttentionFlash
import com.yehsung.aingcheck.desktop.windows.kit.CloakProbe
import com.yehsung.aingcheck.desktop.windows.kit.DesktopGameWindows
import com.yehsung.aingcheck.desktop.windows.kit.DuelInviteNotice
import com.yehsung.aingcheck.desktop.windows.kit.GameKeyMap
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowHandle
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.windows.kit.ImeGate
import com.yehsung.aingcheck.desktop.windows.kit.RefreshRateProbe
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice
import com.yehsung.aingcheck.desktop.windows.kit.WindowBoundsStore
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubBoardFacts
import com.yehsung.aingcheck.ui.games.minigame.rememberMiniGameArt
import com.yehsung.aingcheck.ui.screens.session.kit.LocalAppUserCharacters
import java.awt.Dimension
import java.awt.KeyEventDispatcher
import java.awt.KeyboardFocusManager
import java.awt.event.ComponentAdapter
import java.awt.event.ComponentEvent
import java.awt.event.KeyEvent
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent as AwtWindowEvent
import java.awt.event.WindowFocusListener
import javax.swing.SwingUtilities
import javax.swing.Timer
import javax.swing.WindowConstants

/**
 * 창이 받은 키 하나. [ownsKeys] = 키가 실제로 향한 창이 이 창이다(맥 strokeBelongsToGame). 받았으면 true(삼킨다).
 * ⚠️ 반환은 **이 창의 판이 받은 키**일 때만 true — 뗌도 같다(뗌 적용은 무조건이지만 삼킴은 owns). 창마다 전역 디스패처가 생성 순서로
 * 붙고 앞이 true 면 뒤는 못 본다 — 남의 창 뗌을 삼키면 그 창의 키가 굳는다(맥 MiniGamePanel.swift:307-308 `belongs && wantsStrokes()` ·
 * CheckTetrisDuelWindow.swift:436 `belongs && live`).
 */
fun interface GameKeyRouter {
    fun route(vk: Int, down: Boolean, hasModifiers: Boolean, isRepeat: Boolean, ownsKeys: Boolean): Boolean
}

/**
 * 창 하나의 키 문(AWT KeyEventDispatcher 한 벌의 몸 — 창 0 으로 시험한다). 눌린 키 표로 자동 반복을 가린다:
 * AWT 는 반복을 '뗌 없는 누름'으로 준다 — **이 창이 받은** 누름이 이미 눌려 있으면 반복(★4 반복 무시).
 * 남의 창으로 간 누름은 적지 않는다(그 뗌을 앞 디스패처가 가져가도 이 창의 다음 누름이 반복으로 버려지지 않게).
 */
class GameKeyDispatch(private val router: GameKeyRouter) {
    private val pressed = HashSet<Int>()

    fun dispatch(vk: Int, down: Boolean, hasModifiers: Boolean, ownsKeys: Boolean): Boolean {
        val repeat = when {
            !down -> { pressed.remove(vk); false }
            ownsKeys -> !pressed.add(vk)
            else -> false
        }
        return router.route(vk, down, hasModifiers, repeat, ownsKeys)
    }

    /** 초점을 잃으면 눌린 키를 전부 뗀다(⚠️ 뗌이 안 오면 키가 굳는다 — 대결 스토어의 누른 채가 남지 않게). */
    fun releaseAll() {
        pressed.toList().forEach { router.route(it, down = false, hasModifiers = false, isRepeat = false, ownsKeys = false) }
        pressed.clear()
    }
}

/** 실제 창 손잡이(EDT 에서 만든다). 닫기 단추는 숨기기만 — 파괴는 고착 재생성 때뿐. */
class ComposeGameWindowHandle(
    kind: GameWindowKind,
    title: String,
    private val onEvent: (WindowEvent) -> Unit,
    private val onBoundsChanged: () -> Unit,
    private val keyRouter: GameKeyRouter?,
    onCreated: (ComposeWindow) -> Unit,
    content: @Composable () -> Unit,
) : GameWindowHandle {
    val window: ComposeWindow = ComposeWindow()
    private val keys: GameKeyDispatch? = keyRouter?.let(::GameKeyDispatch)
    private var lastVisible = true
    private val keyDispatcher: KeyEventDispatcher? = keys?.let { k ->
        KeyEventDispatcher { e -> dispatchKey(k, e) }
    }
    private val cloakTimer = Timer(CLOAK_POLL_MS) {
        // 세션 잠금·가상 데스크톱 전환은 AWT 사건이 없다 — DWM cloak 을 읽어 바뀔 때만 넘긴다(완전히 덮임은 Windows 에 없다 — games.md 위험 ③).
        if (!window.isVisible) return@Timer
        val visible = !CloakProbe.isCloaked(window)
        if (visible != lastVisible) {
            lastVisible = visible
            onEvent(WindowEvent.Visibility(visible))
        }
    }

    init {
        window.title = title
        window.defaultCloseOperation = WindowConstants.DO_NOTHING_ON_CLOSE
        // AWT 좌표는 논리 단위(= dp) — Windows 배율은 JDK 가 곱한다(W-3 #2 최소 400×600).
        window.minimumSize = Dimension(kind.minWidthDp, kind.minHeightDp)
        window.setContent { content() }
        window.addWindowListener(object : WindowAdapter() {
            override fun windowClosing(e: AwtWindowEvent) = onEvent(WindowEvent.UserClosed)
            override fun windowIconified(e: AwtWindowEvent) = onEvent(WindowEvent.Minimized)
            override fun windowDeiconified(e: AwtWindowEvent) = onEvent(WindowEvent.Restored)
        })
        window.addWindowFocusListener(object : WindowFocusListener {
            override fun windowGainedFocus(e: AwtWindowEvent) = onEvent(WindowEvent.FocusGained)
            override fun windowLostFocus(e: AwtWindowEvent) {
                releaseAll()
                onEvent(WindowEvent.FocusLost)
            }
        })
        window.addComponentListener(object : ComponentAdapter() {
            override fun componentMoved(e: ComponentEvent) = onBoundsChanged()
            override fun componentResized(e: ComponentEvent) = onBoundsChanged()
        })
        // ⑤ 화면 이동 = 주사율 재계산(CheckMiniGameWindow.swift:276).
        window.addPropertyChangeListener("graphicsConfiguration") { onEvent(WindowEvent.ScreenChanged) }
        // IME 는 실시간 창(미니게임·테트리스 대결)만 뗀다 — 그 창의 자리(minigame/·tetris/)가 [onCreated] 로 넘긴다. 오목·체스는 채팅 칸이 있어 그대로.
        onCreated(window)
        keyDispatcher?.let { KeyboardFocusManager.getCurrentKeyboardFocusManager().addKeyEventDispatcher(it) }
        cloakTimer.start()
    }

    private fun dispatchKey(keys: GameKeyDispatch, e: KeyEvent): Boolean {
        val down = when (e.id) {
            KeyEvent.KEY_PRESSED -> true
            KeyEvent.KEY_RELEASED -> false
            else -> return false
        }
        val owns = e.component?.let { it === window || SwingUtilities.getWindowAncestor(it) === window } == true
        val mods = e.isControlDown || e.isAltDown || e.isMetaDown
        return keys.dispatch(e.keyCode, down, mods, owns)
    }

    private fun releaseAll() {
        keys?.releaseAll()
    }

    override val isMinimized: Boolean get() = (window.extendedState and java.awt.Frame.ICONIFIED) != 0
    override val isOnScreen: Boolean get() = window.isShowing && !isMinimized

    override fun restoreFromMinimized() {
        window.extendedState = window.extendedState and java.awt.Frame.ICONIFIED.inv()
    }

    override fun showAndFocus() {
        window.isVisible = true
        window.toFront()
        window.requestFocus()
    }

    override fun hide() {
        releaseAll()
        window.isVisible = false
    }

    override fun boundsPx(): PxRect {
        val s = scaleOf()
        val left = (window.x * s).toInt()
        val top = (window.y * s).toInt()
        return PxRect(left, top, left + (window.width * s).toInt(), top + (window.height * s).toInt())
    }

    override fun setBoundsPx(rect: PxRect) {
        val s = scaleOf()
        window.setBounds((rect.left / s).toInt(), (rect.top / s).toInt(), (rect.width / s).toInt(), (rect.height / s).toInt())
    }

    override fun dispose() {
        cloakTimer.stop()
        keyDispatcher?.let { KeyboardFocusManager.getCurrentKeyboardFocusManager().removeKeyEventDispatcher(it) }
        window.dispose()
    }

    private fun scaleOf(): Double = window.graphicsConfiguration?.defaultTransform?.scaleX?.takeIf { it > 0.0 } ?: 1.0

    companion object {
        const val CLOAK_POLL_MS = 1_000
    }
}

/** 창 하나의 껍데기(실제 창). [keys] 는 실시간 창만, [notices] 는 그 창의 통지 → 스토어 길. */
class ComposeGameWindowShell(
    private val kind: GameWindowKind,
    private val title: String,
    private val notices: (List<StoreNotice>) -> Unit,
    private val localEvent: (WindowEvent) -> Unit = {},
    private val keys: GameKeyRouter? = null,
    private val onCreated: (ComposeWindow) -> Unit = {},
    /** 창 내용(창 뿌리). internal = 시험이 창 없이 그린다(GomokuWindowSafetyTest — 창 0, 기억 agents-no-visible-windows). */
    internal val content: @Composable () -> Unit,
) : GameWindowShell {
    var handle: ComposeGameWindowHandle? = null
        private set

    override fun createHandle(onEvent: (WindowEvent) -> Unit, onBoundsChanged: () -> Unit): GameWindowHandle =
        ComposeGameWindowHandle(kind, title, onEvent, onBoundsChanged, keys, onCreated, content).also { handle = it }

    override fun onNotices(notices: List<StoreNotice>) = this.notices(notices)
    override fun onWindowEvent(event: WindowEvent) = localEvent(event)
    override fun requestAttention() {
        handle?.window?.let { AttentionFlash.flashUntilForeground(it) }
    }

    fun refreshHz(): Int = handle?.window?.let { RefreshRateProbe.hz(it) } ?: MiniGameWindowState.DEFAULT_HZ
}

/** 조립 지점(AppGraph — 조정자 C3)이 부르는 한 입구. EDT 에서 부른다. 배선(GameWindowWiring.wire)도 여기서 한다. */
/** 게임 창 내용에 착용 캐릭터 표를 흘린다(LocalAppUserCharacters — 로비·대결 아바타 BoardAvatar/PersonAvatar 가 읽는다). */
@Composable
internal fun WithCharacters(characters: () -> AppUserCharacterDirectory, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalAppUserCharacters provides characters(), content = content)
}

object ComposeGamesWindows {
    @Suppress("LongParameterList")
    fun create(
        games: GamesStore,
        gomoku: GomokuStore,
        chess: ChessStore,
        config: DesktopAppConfig,
        bounds: WindowBoundsStore,
        workAreas: () -> List<PxRect>,
        scale: () -> Double,
        dark: () -> Boolean,
        reduceMotion: () -> Boolean,
        me: () -> BoardGameMe,
        myUserID: () -> String?,
        now: () -> SwiftDate,
        onOpenShop: () -> Unit,
        onOpenRankings: () -> Unit,
        others: DesktopGameWindows = DesktopGameWindows.None,
        onInvite: (GameWindowKind) -> Unit = {},
        onTurnWhileHidden: (GameWindowKind) -> Unit = {},
        onInviteNotice: (DuelInviteNotice) -> Unit = {},
        /** 착용 캐릭터 표(W-8 3차 — 안드로이드 AingShell 과 같은 자리). Compose 상태를 읽는 람다라 표가 오면 다시 그린다. 기본 = 빈 표(이니셜). */
        characters: () -> AppUserCharacterDirectory = { AppUserCharacterDirectory(CharacterArt.portraitIds) },
        /** 대국 채팅 신고·차단(W-14 #1 · Store 11.12) — 메시지 탭 스토어. null 이면 ⋯ 메뉴 0(맥 `safety == nil`). 체스·테트리스 대결은 채팅이 없다. */
        messages: MessagesStore? = null,
    ): GamesWindowsHost {
        lateinit var host: GamesWindowsHost
        lateinit var miniShell: ComposeGameWindowShell
        lateinit var duelShell: ComposeGameWindowShell
        val miniState = MiniGameWindowState(games.miniGames, visibleKinds = games.miniGames.visibleKinds) { miniShell.refreshHz() }
        val duelState = TetrisDuelWindowState(TetrisDuelWindowDoors(games.tetris)) { duelShell.refreshHz() }
        val gomokuDoors = GomokuWindowDoors(gomoku)
        val gomokuSafety = GomokuWindowSafety.of(messages)
        val chessDoors = ChessWindowDoors(chess)
        val closeOf = { kind: GameWindowKind -> { host.slot(kind).onEvent(WindowEvent.UserClosed) } }

        miniShell = ComposeGameWindowShell(
            GameWindowKind.MiniGame, "게임", miniState::apply, miniState::onWindowEvent,
            keys = miniGameKeys(games, miniState),
            onCreated = { ImeGate.detach(it) }, // 물리 키 자리로 받아야 한글 상태에서도 Z/X 가 먹는다
        ) {
            WithCharacters(characters) {
            val facts = remember(gomoku, chess) { GamesHubBoardFacts.of(gomoku, chess) }
            MiniGameWindowContent(
                games, miniState, facts, rememberMiniGameArt(), myUserID(), now, dark(), reduceMotion(),
                onOpenBoard = { destination ->
                    when (destination) {
                        GamesDestination.Gomoku -> host.openGomoku()
                        GamesDestination.Chess -> host.openChess()
                        GamesDestination.TetrisDuel -> host.openTetrisDuel()
                        is GamesDestination.MiniGame -> host.openGames(destination.kind)
                    }
                },
                onOpenShop = onOpenShop, onOpenRankings = onOpenRankings,
            )
            }
        }
        val gomokuShell = ComposeGameWindowShell(GameWindowKind.Gomoku, "오목", { BoardGameNoticeSink.apply(gomokuDoors, it) }) {
            WithCharacters(characters) { GomokuWindowContent(games, gomoku, me(), dark(), onLeave = closeOf(GameWindowKind.Gomoku), safety = gomokuSafety) }
        }
        val chessShell = ComposeGameWindowShell(GameWindowKind.Chess, "체스", { BoardGameNoticeSink.apply(chessDoors, it) }) {
            WithCharacters(characters) { ChessWindowContent(games, chess, me(), dark(), onLeave = closeOf(GameWindowKind.Chess)) }
        }
        duelShell = ComposeGameWindowShell(
            GameWindowKind.TetrisDuel, "테트리스 1:1", duelState::apply, keys = duelKeys(games),
            onCreated = TetrisDuelIme::detach,
        ) {
            WithCharacters(characters) {
                TetrisDuelWindowContent(games, duelState, myUserID(), me().name, dark(), reduceMotion(), onBack = closeOf(GameWindowKind.TetrisDuel))
            }
        }

        host = GamesWindowsHost(
            shells = mapOf(
                GameWindowKind.MiniGame to miniShell, GameWindowKind.Gomoku to gomokuShell,
                GameWindowKind.Chess to chessShell, GameWindowKind.TetrisDuel to duelShell,
            ),
            bounds = bounds, workAreas = workAreas, scale = scale, miniGame = miniState,
            storeOpen = GameWindowWiring.openers(gomoku, chess, games.tetris), others = others,
            later = { ms, action -> Timer(ms.toInt()) { action() }.apply { isRepeats = false; start() } },
        )
        GameWindowWiring.wire(gomoku, chess, games.tetris, host, config, onInvite, onTurnWhileHidden, onInviteNotice)
        return host
    }

    /**
     * 미니게임 창 키: 테트리스는 키 표, 길건너는 방향 = 뛰기(GameKeyMap.hop), 다른 게임은 스페이스 = 탭, ESC = 정지 토글. 판이 얼었으면(초점 상실 · ESC 정지 · 3-2-1) 판 키를 받지 않는다.
     * ⚠️뗌은 게이트보다 먼저 적용하되(★★ MiniGamePanel.swift:302-308) **삼킴은 이 창 판의 키만**(`belongs && wantsStrokes()`) — 남의 창(대결) 뗌을 삼키면 그 창 키가 굳는다.
     * ESC(맥 :332 onEscape · :983-990)는 **정지·재개를 실제로 했을 때만** 삼킨다 — 시작 전 · 결과 화면의 ESC 는 흘린다(남의 취소 키를 훔치지 않게).
     */
    fun miniGameKeys(games: GamesStore, state: MiniGameWindowState): GameKeyRouter = miniGameKeys({ games.miniGames.controller }, state)

    /** 같은 라우터 — 판을 주는 자리만 뗐다(시험이 씨앗을 고른 판을 꽂는다: MiniGameKeyReplayTest). */
    fun miniGameKeys(controllerOf: () -> GamesPlayController?, state: MiniGameWindowState): GameKeyRouter = GameKeyRouter { vk, down, mods, repeat, owns ->
        val controller = controllerOf() ?: return@GameKeyRouter false
        val gameOwns = owns && state.windowFocused && state.route is MiniGameWindowRoute.Game
        if (vk == GameKeyMap.VK_ESCAPE) {
            if (!down || mods || !gameOwns || !(state.frozen || controller.isPlaying)) return@GameKeyRouter false
            if (!repeat) state.togglePause()
            return@GameKeyRouter true
        }
        // 정지 카드 · 3-2-1 동안은 판 키가 아니다(스크림 뒤에서 판이 움직이면 정지가 아니다 — 맥 action `guard !isFrozen` · wantsStrokes).
        val live = gameOwns && !state.frozen
        if (vk == GameKeyMap.VK_SPACE) {
            if (down && !repeat && !mods && live) SoloTetrisKeys.action(controller)
            return@GameKeyRouter gameOwns // 정지 중 스페이스는 삼키기만(맥 shouldConsume 뒤 action 이 아무것도 안 한다)
        }
        // 길건너 뛰기(맥 MiniGamePanel.swift:279-296): 테트리스 가지보다 **앞**(↑↓←→ 가 두 표에 다 있다) · wantsHops = 길건너 ∧ ¬얼음(:999).
        // 게이트는 키가 게임 창으로 갔는가(gameOwns) — 뗌은 삼키기만, 조합키는 흘리고, OS 키 반복은 삼키기만(한 번 누름 = 한 칸).
        val hop = GameKeyMap.hop(vk)
        if (hop != null && controller.kind == MiniGameKind.crossy && !state.frozen) {
            if (!gameOwns) return@GameKeyRouter false
            if (!down) return@GameKeyRouter true
            if (mods) return@GameKeyRouter false
            if (!repeat) controller.hop(hop)
            return@GameKeyRouter true
        }
        if (controller.kind != MiniGameKind.tetris) return@GameKeyRouter false
        val stroke = GameKeyMap.stroke(vk, down, mods, repeat, live)
            ?: return@GameKeyRouter down && repeat && !mods && live // ★4 반복은 삼키기만(MiniGamePanel.swift:311)
        SoloTetrisKeys.apply(controller, stroke)
        live
    }

    /** 대결 창 키 — 실제 대결 스토어로. */
    fun duelKeys(games: GamesStore): GameKeyRouter = duelKeys(TetrisDuelKeys.input(games.tetris))

    /**
     * 대결 창 키: 키 표 그대로 누름/뗌, 스페이스 = 하드드롭. 키 상실해도 판은 계속(뗌만 정리).
     * 받는 때 = 키가 향한 창이 이 창 ∧ 판 흐름(카운트다운·판 중 — CheckTetrisDuelWindow.swift:537 isLive). ⚠️뗌은 게이트보다 먼저, 무조건 적용(★433)하되
     * 삼킴은 `belongs && live`(:436) — 로비에선 스페이스가 초점 단추로 가고, 남의 창(솔로) 뗌은 그 창 디스패처까지 간다.
     */
    fun duelKeys(input: TetrisDuelInput): GameKeyRouter = GameKeyRouter { vk, down, mods, repeat, owns ->
        val gameOwns = owns && input.live
        if (vk == GameKeyMap.VK_SPACE) {
            if (down && !repeat && !mods && gameOwns) input.hardDrop()
            return@GameKeyRouter gameOwns
        }
        val stroke = GameKeyMap.stroke(vk, down, mods, repeat, gameOwns)
            ?: return@GameKeyRouter down && repeat && !mods && gameOwns // ★4 반복은 삼키기만(DAS·ARR 은 엔진 시계 — :441)
        input.stroke(stroke)
        gameOwns
    }
}
