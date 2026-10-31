// 원본: Sources/CheckCore/GomokuStore.swift(user(from:) · liveMatch · rankingBoard) · ChessStore.swift · TetrisDuelStore.swift — 응답의 사진 · 착용값이 화면 값까지 실려 오는지
//
// 게임 화면 순위 · 관전 줄 얼굴이 쓰는 값: 응답에 있는 avatar_url · character 가 스토어 경계에서 사라지지 않는다. 사라지면 화면이 넘겨도 소용이 없다.
package com.yehsung.aingcheck.core.stores

import com.yehsung.aingcheck.core.stores.chess.chessRankingBoard
import com.yehsung.aingcheck.core.stores.gomoku.gomokuRankingBoard
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.rankingBoard
import com.yehsung.aingcheck.core.wire.games.ChessRPCStatus
import com.yehsung.aingcheck.core.wire.games.ChessRankRow
import com.yehsung.aingcheck.core.wire.games.ChessRankingResponse
import com.yehsung.aingcheck.core.wire.games.GomokuRPCStatus
import com.yehsung.aingcheck.core.wire.games.GomokuRankRow
import com.yehsung.aingcheck.core.wire.games.GomokuRankingResponse
import com.yehsung.aingcheck.core.wire.games.TetrisRPCStatus
import com.yehsung.aingcheck.core.wire.games.TetrisRankRow
import com.yehsung.aingcheck.core.wire.games.TetrisRankingResponse
import kotlin.test.Test
import kotlin.test.assertEquals

class PersonFaceValuesTest {
    private val photo = "https://example.com/p.jpg"

    @Test
    fun gomokuRankingKeepsPhotoAndCharacter() {
        val user = gomokuRankingBoard(GomokuRankingResponse(GomokuRPCStatus.ok, rows = listOf(GomokuRankRow(rank = 1, userId = "A", displayName = "가", avatarUrl = photo, character = "fox")))).entries.single().user
        assertEquals(photo, user.avatarURL)
        assertEquals("fox", user.characterID)
    }

    @Test
    fun chessRankingKeepsPhotoAndCharacter() {
        val user = chessRankingBoard(ChessRankingResponse(ChessRPCStatus.ok, rows = listOf(ChessRankRow(rank = 1, userId = "A", displayName = "가", avatarUrl = photo, character = "fox")))).entries.single().user
        assertEquals(photo, user.avatarURL)
        assertEquals("fox", user.characterID)
    }

    @Test
    fun tetrisRankingKeepsPhotoAndCharacter() {
        val user = TetrisDuelStore.rankingBoard(TetrisRankingResponse(TetrisRPCStatus.ok, rows = listOf(TetrisRankRow(rank = 1, id = "A", displayName = "가", avatarUrl = photo, character = "fox")))).entries.single().user
        assertEquals(photo, user.avatarURL)
        assertEquals("fox", user.characterID)
    }
}
