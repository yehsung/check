// 원본: Sources/check/CheckGomokuWindow.swift:6-35(머리 규약) · :302-320(닫힘 경로, ★314) · :342-356(가림) · ★410
//       (W4-e — 공용 세로 화면 GomokuScreen 을 크기 조절 창에 그대로: 기본 440×720dp · 최소 400×600, W-3 #2)
//       대국 채팅 신고·차단(Store 11.12 · W-14 #1): CheckGomokuWindow.swift:198-204(`safety` nil 이면 ··· 가 서지 않는다) ·
//       GomokuPanel.swift:2093-2101(··· → [신고하기]·[차단하기]) — 폰 NavGraph.kt:269-275 와 같은 모양(GomokuWindowSafety)
package com.yehsung.aingcheck.desktop.windows.games.gomoku

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.blockPeer
import com.yehsung.aingcheck.desktop.windows.games.minigame.BoardWindowDoors
import com.yehsung.aingcheck.desktop.windows.games.minigame.GameWindowFrame
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameSafety
import com.yehsung.aingcheck.ui.games.gomoku.GomokuScreen
import com.yehsung.aingcheck.ui.screens.messages.MessagesBlockConfirmSheet
import com.yehsung.aingcheck.ui.screens.messages.MessagesReportSheet
import com.yehsung.aingcheck.ui.screens.messages.MessagesReportTarget

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

/**
 * 대국 채팅 ··· 의 신고·차단 문 — 메시지 탭 스토어·시트를 그대로 쓴다(세 입구가 한 시트 · 한 문구). 폰 NavGraph.kt:269-275 와 같은 몸.
 * [messages] 가 없으면 null — ⋯ 메뉴를 세우지 않는다(맥 CheckGomokuWindow.swift:198 `safety == nil`). 깃발로 거르지 않는다:
 * 채팅이 서는 판이면 신고·차단도 서야 한다(채팅 서랍은 duels 깃발과 무관하게 사람 판이면 선다 — GomokuMatch.kt:127).
 */
object GomokuWindowSafety {
    fun of(messages: MessagesStore?): BoardGameSafety? = messages?.let { m ->
        BoardGameSafety(
            block = { peerID -> m.blockPeer(peerID) }, // 확인 덮개를 지난 뒤에만 불린다
            reportSheet = { target, onSent, onClose ->
                MessagesReportSheet(m, MessagesReportTarget(target.peerID, target.peerName), onSent, onClose)
            },
            blockConfirmSheet = { peerName, onConfirm, onClose -> MessagesBlockConfirmSheet(peerName, onConfirm, onClose) },
        )
    }
}

/**
 * 오목 창 본문. [onLeave] = 화면의 뒤로 → 창 닫기(사용자 닫기와 같은 길 — 대국은 계속).
 * [safety] = 대국 채팅 신고·차단 문([GomokuWindowSafety.of]). 차단 문구 판(맥)은 창 바탕 [GameWindowFrame] 이 준다.
 */
@Composable
fun GomokuWindowContent(
    games: GamesStore,
    gomoku: GomokuStore,
    me: BoardGameMe,
    dark: Boolean,
    onLeave: () -> Unit,
    modifier: Modifier = Modifier,
    safety: BoardGameSafety? = null,
) {
    GameWindowFrame(dark, modifier) {
        GomokuScreen(games, gomoku, me, onLeave = onLeave, modifier = Modifier.fillMaxSize(), safety = safety)
    }
}
