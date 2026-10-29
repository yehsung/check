// 원본: Sources/check/CheckGomokuWindow.swift:6-35(머리 규약) · :302-320(닫힘 경로, ★314) · :342-356(가림) · ★410
//       (W4-e — 공용 세로 화면 GomokuScreen 을 크기 조절 창에 그대로: 기본 440×720dp · 최소 400×600, W-3 #2)
package com.yehsung.aingcheck.desktop.windows.games.gomoku

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.desktop.windows.games.minigame.BoardWindowDoors
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.GomokuScreen
import com.yehsung.aingcheck.desktop.windows.games.minigame.GameWindowFrame

/**
 * 오목 창 규약(맥 머리말 그대로):
 *  ① 키 상실·닫기로 **대국을 끝내지 않는다**(windowDidResignKey 없음이 계약 — 표의 FocusLost 는 빈 통지)
 *  ② 최소화 = '안 보임'(폴링만 멈춤 — DidHide 만, DidClose 금지) ③ 턴제라 키 모니터·주사율 감시 없음 — IME 도 떼지 않는다(채팅 칸, games.md 위험 ①)
 */
class GomokuWindowDoors(private val store: GomokuStore) : BoardWindowDoors {
    override fun windowDidShow() = store.windowDidShow()
    override fun windowDidHide() = store.windowDidHide()
    override fun windowDidClose() = store.windowDidClose()
    override fun windowOcclusionDidChange(visible: Boolean) = store.windowOcclusionDidChange(visible)
}

/** 오목 창 본문. [onLeave] = 화면의 뒤로 → 창 닫기(사용자 닫기와 같은 길 — 대국은 계속). */
@Composable
fun GomokuWindowContent(games: GamesStore, gomoku: GomokuStore, me: BoardGameMe, dark: Boolean, onLeave: () -> Unit, modifier: Modifier = Modifier) {
    GameWindowFrame(dark, modifier) {
        GomokuScreen(games, gomoku, me, onLeave = onLeave, modifier = Modifier.fillMaxSize())
    }
}
