// 원본: Tests/checkTests/ReversiContractTests.swift @ 12624739
package com.yehsung.aingcheck.core.rules.reversi

import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiCounts
import com.yehsung.aingcheck.core.wire.games.ReversiEndKind
import com.yehsung.aingcheck.core.wire.games.ReversiEndReason
import com.yehsung.aingcheck.core.wire.games.ReversiIllegalReason
import com.yehsung.aingcheck.core.wire.games.ReversiPly
import com.yehsung.aingcheck.core.wire.games.ReversiResult
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 아잉 뒤집기 규칙 표면의 **성립 안 하는 입력** 계약과 와이어 어휘. 서버·와이어·화면은 판을 64자 '.bw' 문자열로, 칸을 idx(0~63)로,
 * 결과·끝 사유·불법 까닭을 정해진 영어 낱말로 주고받는다(SPEC §2.2). 각 단언에는 "한 글자만 다른 입력"을 기준선으로 같이 둔다.
 */
class ReversiContractTest {
    private val start = "...........................wb......bw..........................."

    // 없으면: 63자·65자·다른 글자의 판을 받아들여 엉뚱한 칸에 돌이 놓인 채로 판정이 돈다(서버 reversi_board_ok 는 거절한다).
    @Test
    fun boardStringRejectsMalformed() {
        assertEquals(ReversiBoard.start, ReversiBoard.fromString(start), "기준선: 시작 판 문자열")
        val sixtyThree = start.dropLast(1)
        assertNull(ReversiBoard.fromString(sixtyThree), "63자")
        assertNotNull(ReversiBoard.fromString("$sixtyThree."), "기준선: 한 글자 더하면 64자")
        assertNull(ReversiBoard.fromString("$start."), "65자")
        assertNull(ReversiBoard.fromString(""))
        for (bad in listOf("x", "-", "B", "W", " ", "é", "흑")) {
            assertNull(ReversiBoard.fromString(bad + start.drop(1)), "첫 칸 $bad")
        }
        assertNotNull(ReversiBoard.fromString("b" + start.drop(1)), "기준선: 첫 칸 b")
        val mixed = (0 until 64).map { listOf('.', 'b', 'w')[it % 3] }.joinToString("")
        assertEquals(mixed, ReversiBoard.fromString(mixed)?.string)
        assertEquals(mixed, ReversiBoard.fromString(mixed)?.toString())
    }

    // 없으면: 와이어 board 칸을 객체·배열로 내보내거나 잘못된 판을 디코드해 버리면 서버 state 와 왕복이 깨진다.
    @Test
    fun boardCodableIsSingleString() {
        val list = ListSerializer(ReversiBoard.serializer())
        val text = SwiftJson.encode(list, listOf(ReversiBoard.start))
        assertEquals("[\"$start\"]", text)
        assertEquals(listOf(ReversiBoard.start), SwiftJson.decode(list, text))
        assertFailsWith<SerializationException> { SwiftJson.decode(list, "[\"${start.dropLast(1)}\"]") }
        assertFailsWith<SerializationException> { SwiftJson.decode(list, "[64]") }
        val counts = SwiftJson.encodeToElement(ReversiCounts.serializer(), ReversiCounts(3, 1, 60)) as JsonObject
        assertEquals(mapOf("black" to 3, "white" to 1, "empty" to 60), counts.mapValues { it.value.jsonPrimitive.int })
    }

    // 없으면: idx −1·64 가 판 밖 판정 없이 비트 이동(음수·64 이상 shift — Kotlin 은 64 로 나눈 나머지만큼 민다)으로 들어가 엉뚱한 칸을 뒤집는다.
    @Test
    fun outOfRangeIndexIsRejected() {
        val board = ReversiBoard.start
        for (idx in listOf(-1, 64, -64, 100, Int.MIN_VALUE, Int.MAX_VALUE)) {
            assertNull(board[idx], "$idx")
            assertTrue(ReversiRules.flips(board, ReversiColor.black, idx).isEmpty(), "$idx")
            assertEquals(ReversiPlay.Illegal(ReversiIllegalReason.outOfRange), ReversiRules.play(board, ReversiColor.black, idx), "$idx")
        }
        // 기준선: 판 안의 같은 줄 — 까닭이 갈린다(이미 돌 · 못 뒤집음 · 합법).
        assertTrue(board[27] == ReversiColor.white && board[28] == ReversiColor.black && board[0] == null)
        assertEquals(ReversiPlay.Illegal(ReversiIllegalReason.occupied), ReversiRules.play(board, ReversiColor.black, 27))
        assertEquals(ReversiPlay.Illegal(ReversiIllegalReason.noFlip), ReversiRules.play(board, ReversiColor.black, 0))
        assertEquals(listOf(27), ReversiRules.play(board, ReversiColor.black, 19).outcomeOrNull?.flipped)
    }

    // 없으면: "i1"·"a9"·"d10" 같은 좌표가 다른 칸으로 읽혀 화면 표기와 와이어 idx 가 갈린다.
    @Test
    fun pointRejectsMalformed() {
        assertNull(ReversiPoint.of(col = 8, row = 0))
        assertNull(ReversiPoint.of(col = 0, row = 8))
        assertNull(ReversiPoint.of(col = -1, row = 0))
        assertEquals(63, ReversiPoint.of(col = 7, row = 7)?.idx, "기준선")
        assertNull(ReversiPoint.of(-1))
        assertNull(ReversiPoint.of(64))
        assertEquals("h8", ReversiPoint.of(63)?.coord, "기준선")
        for (bad in listOf("", "d", "i1", "a9", "a0", "d10", "d3 ", " d3", "3d", "@1", "`1", "é1", "dd")) {
            assertNull(ReversiPoint.fromCoord(bad), bad)
        }
        assertEquals(7, ReversiPoint.fromCoord("h1")?.idx, "기준선")
        assertEquals("a8", ReversiPoint.fromCoord("A8")?.coord, "읽기는 대문자도, 쓰기는 소문자")
    }

    // 없으면: 깊이 음수로 재귀가 끝나지 않거나, 깊이 0 divide 가 뭔가를 내서 진단이 거짓말한다.
    @Test
    fun perftBoundaries() {
        assertEquals(0L, ReversiRules.perft(ReversiBoard.start, ReversiColor.black, -5))
        assertEquals(1L, ReversiRules.perft(ReversiBoard.start, ReversiColor.black, 0))
        assertEquals(4L, ReversiRules.perft(ReversiBoard.start, ReversiColor.black, 1), "기준선")
        assertTrue(ReversiRules.perftDivide(ReversiBoard.start, ReversiColor.black, 0).isEmpty())
        assertTrue(ReversiRules.perftDivide(ReversiBoard.start, ReversiColor.black, -1).isEmpty())
        assertEquals(listOf(19, 26, 37, 44), ReversiRules.perftDivide(ReversiBoard.start, ReversiColor.black, 1).map { it.idx }, "기준선")
    }

    // 없으면: 서버 어휘(black_win · board_full · no_flip …)와 글자가 하나라도 다르면 와이어 디코드가 실패하거나 다른 뜻으로 읽힌다.
    @Test
    fun wireVocabularyMatchesServer() {
        assertEquals(listOf("black", "white"), ReversiColor.entries.map { it.rawValue })
        assertTrue(ReversiColor.black.cell == 'b' && ReversiColor.white.cell == 'w')
        assertTrue(ReversiColor.black.opponent == ReversiColor.white && ReversiColor.white.opponent == ReversiColor.black)
        assertEquals(listOf("black_win", "white_win", "draw"), ReversiResult.entries.map { it.rawValue })
        assertTrue(ReversiResult.blackWin.winner == ReversiColor.black && ReversiResult.whiteWin.winner == ReversiColor.white && ReversiResult.draw.winner == null)
        assertEquals(listOf("board_full", "wipeout", "no_moves"), ReversiEndKind.entries.map { it.rawValue })
        assertEquals(
            listOf("board_full", "wipeout", "no_moves", "resign", "abandoned"),
            listOf(ReversiEndReason.boardFull, ReversiEndReason.wipeout, ReversiEndReason.noMoves, ReversiEndReason.resign, ReversiEndReason.abandoned).map { it.rawValue },
        )
        assertEquals(listOf("out_of_range", "occupied", "no_flip"), ReversiIllegalReason.entries.map { it.rawValue })
        assertEquals(listOf("stone", "pass"), ReversiPly.Kind.entries.map { it.rawValue })
        val decoded = SwiftJson.decode(ListSerializer(ReversiEndReason.serializer()), """["abandoned","resign","timeout","WIPEOUT"]""")
        assertEquals(
            listOf(ReversiEndReason.abandoned, ReversiEndReason.resign, ReversiEndReason.unknown, ReversiEndReason.unknown),
            decoded, "모르는 값(대문자 포함)은 unknown, 아는 값은 그대로",
        )
        assertTrue(
            ReversiEndReason.of(ReversiEndKind.noMoves) == ReversiEndReason.noMoves &&
                ReversiEndReason.of(ReversiEndKind.boardFull) == ReversiEndReason.boardFull &&
                ReversiEndReason.of(ReversiEndKind.wipeout) == ReversiEndReason.wipeout,
        )
        // 결과·색·끝 분류는 모르는 글자를 접지 않고 던진다(Swift 합성 Codable — 판정 어휘가 넓어지면 디코드가 알린다).
        assertFailsWith<SerializationException> { SwiftJson.decode(ReversiColor.serializer(), "\"purple\"") }
        assertFailsWith<SerializationException> { SwiftJson.decode(ReversiResult.serializer(), "\"BLACK_WIN\"") }
    }

    // 없으면: 칸 하나의 차이를 판정이 못 본다. A09 c3 은 f6 이 빈칸이라 불법 — f6 에 흑을 놓으면 같은 c3 이 대각 두 개를 뒤집는다.
    @Test
    fun oneCellChangesTheVerdict() {
        val item = ReversiCorpusFile.hand("A09")
        val text = item.str("board")!!
        val board = ReversiCorpusFile.board(text, "A09")
        assertEquals(ReversiPlay.Illegal(ReversiIllegalReason.noFlip), ReversiRules.play(board, ReversiColor.black, 18))
        val cells = text.toCharArray()
        assertEquals('.', cells[45])
        cells[45] = 'b'
        val changed = assertNotNull(ReversiBoard.fromString(cells.concatToString()))
        assertEquals(listOf(27, 36), ReversiRules.flips(changed, ReversiColor.black, 18))
    }

    // 없으면: 코퍼스·기보의 판 문자열이 우리 표현을 거쳐 한 글자라도 바뀌면(칸 순서·글자) 서버와 대조할 때 갈린다.
    @Test
    fun corpusBoardsRoundTrip() {
        val corpus = ReversiCorpusFile.load()
        var count = 0
        val texts = ReversiCorpusFile.hand(corpus).flatMap { listOfNotNull(it.str("board"), it.obj("expected")!!.str("board_after")) } +
            corpus.objects("wthor_sample").map { it.str("final_board")!! }
        for (text in texts) {
            assertEquals(text, ReversiBoard.fromString(text)?.string, text)
            count += 1
        }
        assertEquals(48 + 33 + 200, count)
    }
}
