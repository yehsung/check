// 대결 말풍선의 스토어 사실(int-w4b ②). 원본: Sources/check/CheckOverlayWindow.swift
//   :1297 오목 alive = `store.gomoku.incoming` id · :1393-1397 gomokuAttentionIsCurrent(창 안 보임 · 같은 판 · 안 끝남 · 내 차례 · 같은 수)
//   :1450 체스 alive = `store.chess.visibleIncoming?.id` · :1538-1542 chessAttentionIsCurrent(plyCount)
//   :1591 테트리스 alive = `store.tetris.visibleIncomingInvites` id · :1677-1680 tetrisAttentionIsCurrent(창 안 보임 · 같은 판 · 안 끝남 — 차례 없음)
// 맥은 펌프가 띄우기 직전에 스토어를 **실시간으로** 읽는다 — 여기 함수도 부를 때마다 스토어 지금 값을 읽는다(밀어 넣는 사본 없음).
// 오버레이 명령 루프와 스토어는 같은 조립 scope(한 스레드)에서 돈다(AppGraph — stores·overlay.start 모두 같은 scope).
package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.desktop.overlay.engine.DuelFacts
import com.yehsung.aingcheck.desktop.overlay.engine.DuelFactsSource
import com.yehsung.aingcheck.desktop.overlay.engine.DuelGame
import com.yehsung.aingcheck.desktop.overlay.engine.DuelMatchFact

object OverlayDuelFacts {
    /** 조립(AppGraph 오버레이 묶음)이 세 스토어로 짓는다 — OverlayWiringDeps.duelFacts. */
    fun from(gomoku: GomokuStore, chess: ChessStore, tetris: TetrisDuelStore): DuelFactsSource = DuelFactsSource { game ->
        when (game) {
            DuelGame.GOMOKU -> gomoku(gomoku)
            DuelGame.CHESS -> chess(chess)
            DuelGame.TETRIS -> tetris(tetris)
        }
    }

    /** 맥 :1297 · :1394-1396 — 내 차례 = `match.turn == match.myColor`, 수 번호 = moveCount. */
    fun gomoku(store: GomokuStore): DuelFacts = DuelFacts(
        aliveInviteIds = store.incoming.mapTo(LinkedHashSet()) { it.id },
        windowVisible = store.isWindowVisible,
        match = store.match?.let { m -> DuelMatchFact(m.id, m.isFinished, myTurn = m.turn == m.myColor, moveCount = m.moveCount) },
    )

    /** 맥 :1450 · :1539-1541 — 받은 신청은 화면에 보이는 하나(`visibleIncoming` — 차단·잠긴 빌드는 없음), 수 번호 = plyCount. */
    fun chess(store: ChessStore): DuelFacts = DuelFacts(
        aliveInviteIds = setOfNotNull(store.visibleIncoming?.id),
        windowVisible = store.isWindowVisible,
        match = store.match?.let { m -> DuelMatchFact(m.id, m.isFinished, myTurn = m.turn == m.myColor, moveCount = m.plyCount) },
    )

    /** 맥 :1591 · :1678-1679 — 테트리스는 차례가 없다(엔진 attentionIsCurrent 가 TETRIS 는 판 id·끝남만 본다). */
    fun tetris(store: TetrisDuelStore): DuelFacts = DuelFacts(
        aliveInviteIds = store.visibleIncomingInvites.mapTo(LinkedHashSet()) { it.id },
        windowVisible = store.isWindowVisible,
        match = store.match?.let { m -> DuelMatchFact(m.id, m.isFinished, myTurn = true, moveCount = 0) },
    )
}
