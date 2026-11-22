// 원본: Sources/CheckCore/DuelRoomAdoption.swift @ main 341eb4e3 — 판 9 1:1 대기방
//
// 방에서 선 판을 **이 기기가 연 판**으로 받는다(게임 스토어마다 한 줄). 방 참가는 서버가 그 게임의 신청(방장) + 수락(참가자)을 한 트랜잭션으로
// 부르므로 방장 기기는 신청 응답을 받은 적이 없다. 방 숨이 '시작됨 + 판 id' 를 돌려주면(방장) · 참가가 ok 면(참가자) 장부가 있는 게임은 장부에
// 적고 그 판을 다시 읽는다 — 다음은 게임마다 원래 길(진행 중 판으로 넘어가면 판 화면)이 그대로 한다. 알까기는 로비를 다시 읽는다.
package com.yehsung.aingcheck.core.stores.rooms

import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiOnlineStore
import com.yehsung.aingcheck.core.stores.chess.ChessStore
import com.yehsung.aingcheck.core.stores.crossy.CrossyDuelStore
import com.yehsung.aingcheck.core.stores.crossy.noteOwnsMatch
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStore
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.noteOwnsMatch

suspend fun GomokuStore.adoptRoomMatch(matchID: String) = refreshMatch(matchID.lowercase())

suspend fun ChessStore.adoptRoomMatch(matchID: String) = refreshMatch(matchID.lowercase())

suspend fun TetrisDuelStore.adoptRoomMatch(matchID: String) {
    noteOwnsMatch(matchID.lowercase())
    refreshMatch(matchID.lowercase())
}

suspend fun ReversiStore.adoptRoomMatch(matchID: String) = refreshMatch(matchID.lowercase())

suspend fun CrossyDuelStore.adoptRoomMatch(matchID: String) {
    noteOwnsMatch(matchID.lowercase())
    refreshMatch(matchID.lowercase())
}

@Suppress("UNUSED_PARAMETER")
suspend fun AlkkagiOnlineStore.adoptRoomMatch(matchID: String) = refreshLobby()
