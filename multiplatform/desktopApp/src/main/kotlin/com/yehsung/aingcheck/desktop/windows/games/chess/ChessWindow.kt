// 원본: Sources/check/CheckChessWindow.swift:200-205(제목·자동저장 키 check.chess.window) · ★360-371(닫기 ≠ 최소화) · ★460
//       (W4-e — 공용 세로 화면 ChessScreen 을 크기 조절 창에 그대로: 기본 440×720dp · 최소 400×600, W-3 #2)
package com.yehsung.aingcheck.desktop.windows.games.chess

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.desktop.windows.games.minigame.BoardWindowDoors
import com.yehsung.aingcheck.desktop.windows.games.minigame.GameWindowFrame
import com.yehsung.aingcheck.ui.games.chess.ChessScreen
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe

/** 체스 창 규약 — 오목 창을 그대로 베꼈다(★360-371: 닫기는 DidHide 뒤 DidClose, 최소화는 DidHide 만). 턴제라 IME·키 모니터 없음. */
class ChessWindowDoors(private val store: ChessStore) : BoardWindowDoors {
    override fun windowDidShow() = store.windowDidShow()
    override fun windowDidHide() = store.windowDidHide()
    override fun windowDidClose() = store.windowDidClose()
    override fun windowOcclusionDidChange(visible: Boolean) = store.windowOcclusionDidChange(visible)
}

@Composable
fun ChessWindowContent(games: GamesStore, chess: ChessStore, me: BoardGameMe, dark: Boolean, onLeave: () -> Unit, modifier: Modifier = Modifier) {
    GameWindowFrame(dark, modifier) {
        ChessScreen(games, chess, me, onLeave = onLeave, modifier = Modifier.fillMaxSize())
    }
}
