// 원본: 없음 — W4-e 시험 조립(가짜 창 손잡이 · 껍데기 · 장면 씨앗 · 배율 렌더). 씨앗은 ui GomokuScreenFlowTest·ChessScreenFlowTest 의 합성 값 그대로.
package com.yehsung.aingcheck.desktop.windows.games.minigame

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import com.yehsung.aingcheck.core.stores.chess.ChessInvite
import com.yehsung.aingcheck.core.stores.chess.ChessLiveMatch
import com.yehsung.aingcheck.core.stores.chess.ChessRankEntry
import com.yehsung.aingcheck.core.stores.chess.ChessRankingBoard
import com.yehsung.aingcheck.core.stores.chess.ChessRecord
import com.yehsung.aingcheck.core.stores.chess.ChessStake
import com.yehsung.aingcheck.core.stores.chess.ChessUser
import com.yehsung.aingcheck.core.stores.gomoku.GomokuInvite
import com.yehsung.aingcheck.core.stores.gomoku.GomokuLiveMatch
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRankEntry
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRankingBoard
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRecord
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStake
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.testsupport.PixelImage
import com.yehsung.aingcheck.desktop.windows.games.minigame.rig.BoardGameRig
import com.yehsung.aingcheck.desktop.windows.games.minigame.rig.TestBoardArt
import com.yehsung.aingcheck.desktop.windows.games.minigame.rig.boardClock
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowHandle
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice
import com.yehsung.aingcheck.desktop.windows.kit.WindowBoundsStore
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent
import com.yehsung.aingcheck.ui.games.gomoku.LocalBoardGameArt
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Image

/** 창 0 — 손잡이는 상태만 적는다. */
class FakeGameWindowHandle : GameWindowHandle {
    var shown = 0
    var hidden = 0
    var disposed = false
    var bounds = PxRect(0, 0, 440, 720)
    override var isMinimized: Boolean = false
    override var isOnScreen: Boolean = false
    override fun restoreFromMinimized() { isMinimized = false }
    override fun showAndFocus() { shown++; isOnScreen = true }
    override fun hide() { hidden++; isOnScreen = false }
    override fun boundsPx(): PxRect = bounds
    override fun setBoundsPx(rect: PxRect) { bounds = rect }
    override fun dispose() { disposed = true }
}

/** 시험 껍데기 — 손잡이는 가짜, 통지는 [sink] 로(실제 껍데기와 같은 길), 받은 통지·사건은 적는다. */
class FakeGameWindowShell(
    private val sink: (List<StoreNotice>) -> Unit = {},
    private val local: (WindowEvent) -> Unit = {},
) : GameWindowShell {
    val handles = mutableListOf<FakeGameWindowHandle>()
    val notices = mutableListOf<StoreNotice>()
    var attention = 0
    var emit: (WindowEvent) -> Unit = {}
    override fun createHandle(onEvent: (WindowEvent) -> Unit, onBoundsChanged: () -> Unit): GameWindowHandle {
        emit = onEvent
        return FakeGameWindowHandle().also { handles += it }
    }
    override fun onNotices(notices: List<StoreNotice>) { this.notices += notices; sink(notices) }
    override fun onWindowEvent(event: WindowEvent) = local(event)
    override fun requestAttention() { attention++ }
}

class MemoryBounds : WindowBoundsStore {
    val saved = mutableMapOf<String, PxRect>()
    override fun load(key: String): PxRect? = saved[key]
    override fun save(key: String, rect: PxRect) { saved[key] = rect }
}

object GameWindowScenes {
    val WORK_AREA = PxRect(0, 0, 1920, 1040)

    fun host(shells: Map<GameWindowKind, GameWindowShell>, miniGame: MiniGameWindowState? = null, storeOpen: GamesWindowsHost.StoreWindowOpeners = GamesWindowsHost.StoreWindowOpeners.None) =
        GamesWindowsHost(shells, MemoryBounds(), { listOf(WORK_AREA) }, { 1.0 }, miniGame, storeOpen)

    fun fakeShells(vararg overrides: Pair<GameWindowKind, GameWindowShell>): Map<GameWindowKind, GameWindowShell> =
        GamesWindowsHost.OWN_KINDS.associateWith { FakeGameWindowShell() as GameWindowShell } + overrides

    const val SEED_INVITE_ID = "11111111-0000-4000-8000-0000000000a1"
    const val SEED_LIVE_ID = "22222222-0000-4000-8000-0000000000b2"
    val SEED_USERS = listOf(
        GomokuUser("aaaaaaaa-0000-4000-8000-000000000001", "솜사탕", null, "fox", isWorking = true, isCapable = true, inMatch = false, center = "서울"),
        GomokuUser("aaaaaaaa-0000-4000-8000-000000000002", "구름빵", null, null, isWorking = false, isCapable = true, inMatch = false),
        GomokuUser("aaaaaaaa-0000-4000-8000-000000000003", "달토끼", null, "aing", isWorking = true, isCapable = true, inMatch = true),
    )
    val SEED_CHESS_USERS = listOf(
        ChessUser("bbbbbbbb-0000-4000-8000-000000000001", "체스솜", null, "fox", isWorking = true, isCapable = true, inMatch = false, center = "서울"),
        ChessUser("bbbbbbbb-0000-4000-8000-000000000002", "체스구름", null, null, isWorking = false, isCapable = true, inMatch = false),
        ChessUser("bbbbbbbb-0000-4000-8000-000000000003", "체스달", null, "shiba", isWorking = true, isCapable = false, inMatch = false),
    )

    /** 오목 로비(서버 호출 없이 스토어 칸을 직접 채운다 — 세션 없는 호스트라 화면 열기가 조회를 안 낸다). */
    fun seedGomokuLobby(rig: BoardGameRig, record: GomokuRecord = GomokuRecord(6, 2, 1)) {
        val g = rig.gomoku
        g.users = SEED_USERS
        g.hasLoadedLobby = true
        g.hasLoadedInbox = true
        g.record = record
        g.spectatorFeaturesEnabled = true
        g.incoming = listOf(GomokuInvite(SEED_INVITE_ID, SEED_USERS[1], 5, boardClock.addingTimeInterval(42.0)))
        g.liveMatches = listOf(GomokuLiveMatch(SEED_LIVE_ID, SEED_USERS[2], SEED_USERS[0], GomokuStake.ten, boardClock.addingTimeInterval(-95.0), watchers = 3))
        g.ranking = GomokuRankingBoard(
            entries = listOf(GomokuRankEntry(SEED_USERS[0].id, 1, SEED_USERS[0], 6, 2, 1, 4), GomokuRankEntry(SEED_USERS[2].id, 2, SEED_USERS[2], 3, 3, 0, 0)),
            me = null, recordSince = null,
        )
        g.hasLoadedRanking = true
    }

    fun seedChessLobby(rig: BoardGameRig, record: ChessRecord = ChessRecord(4, 1, 2)) {
        val c = rig.chess
        c.users = SEED_CHESS_USERS
        c.hasLoadedLobby = true
        c.record = record
        c.spectatorFeaturesEnabled = true
        c.incoming = ChessInvite("33333333-0000-4000-8000-0000000000c1", SEED_CHESS_USERS[1], 5, boardClock.addingTimeInterval(42.0))
        c.liveMatches = listOf(ChessLiveMatch("44444444-0000-4000-8000-0000000000d2", SEED_CHESS_USERS[0], SEED_CHESS_USERS[2], ChessStake.ten, boardClock.addingTimeInterval(-95.0), watchers = 2))
        c.ranking = ChessRankingBoard(
            entries = listOf(ChessRankEntry(SEED_CHESS_USERS[0].id, 1, SEED_CHESS_USERS[0], 4, 1, 2, 3), ChessRankEntry(SEED_CHESS_USERS[1].id, 2, SEED_CHESS_USERS[1], 1, 1, 0, 0)),
            me = null, recordSince = null,
        )
        c.hasLoadedRanking = true
    }

    @Composable
    fun BoardArt(content: @Composable () -> Unit) = CompositionLocalProvider(LocalBoardGameArt provides TestBoardArt.art, content = content)

    /**
     * 오프스크린 렌더(창 0). [scale] = Windows 배율(1.0 = 100%, 1.5 = 150%) — 창 기본 크기(dp)에 곱한 픽셀로 그린다.
     * [afterFirst] 는 첫 장 뒤 한 번(화면 수명이 연 판에 키를 넣는 자리).
     */
    @OptIn(ExperimentalComposeUiApi::class)
    fun render(widthDp: Int, heightDp: Int, scale: Float, frames: Int = 4, afterFirst: () -> Unit = {}, content: @Composable () -> Unit): PixelImage {
        val w = (widthDp * scale).toInt()
        val h = (heightDp * scale).toInt()
        val scene = ImageComposeScene(width = w, height = h, density = Density(scale), content = content)
        try {
            var image: Image? = null
            for (i in 0 until frames) {
                image?.close()
                image = scene.render(i * 16_666_667L)
                if (i == 0) afterFirst()
            }
            val bitmap = Bitmap.makeFromImage(requireNotNull(image))
            val pixels = IntArray(w * h)
            for (y in 0 until h) for (x in 0 until w) pixels[y * w + x] = bitmap.getColor(x, y)
            bitmap.close()
            image.close()
            return PixelImage(w, h, pixels)
        } finally {
            scene.close()
        }
    }
}
