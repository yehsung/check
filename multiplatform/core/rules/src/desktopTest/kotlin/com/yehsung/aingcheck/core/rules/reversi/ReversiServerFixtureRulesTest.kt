// 원본: Tests/checkTests/V03xxReversiFixtureContractTests.swift:599-681(독립 산식 — 서버 판과 Swift 규칙이 같다) @ 12624739
package com.yehsung.aingcheck.core.rules.reversi

import com.yehsung.aingcheck.core.wire.games.ReversiActionResponse
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiMatchStatus
import com.yehsung.aingcheck.core.wire.games.ReversiPly
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * 서버 실출력 픽스처(`Tests/checkTests/Fixtures/reversi-rpc/` — 서버 갈래가 실제 RPC 응답 원문을 뽑은 것) × **Kotlin 규칙**.
 * 서버 판정(SQL)과 Kotlin 규칙이 갈려도(합법 수·뒤집힌 칸·끝 분류·WOF 점수) 스텁 시험은 서버 원문을 그대로 믿어 초록이다 —
 * 그래서 원문 값을 **Kotlin 규칙으로 다시 셈한** 값과 잰다. 씨앗 판(수 기록이 1 부터가 아닌 판)도 있어 "마지막 돌 한 수를 되돌려 다시 둔다" 로 잰다.
 * 원문은 앱 디코더(SwiftJson — 와이어 모델)로 읽고, 키·관계는 같은 파일의 트리로 본다.
 */
class ReversiServerFixtureRulesTest {
    private val directory = "Tests/checkTests/Fixtures/reversi-rpc"

    private fun files(): List<String> {
        val root = File(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 가 없다" }, directory)
        return root.list()!!.filter { it.endsWith(".json") && it != "_manifest.json" }.sorted()
    }

    private fun text(file: String): String = RepoFiles.readText("$directory/$file")

    // 없으면: 서버 판정과 Kotlin 규칙이 갈려도 아무 시험도 안 본다.
    @Test
    fun serverBoardsAgreeWithKotlinRules() {
        var states = 0
        var legalChecked = 0
        var undoChecked = 0
        var scored = 0
        for (file in files()) {
            val raw = Json.parseToJsonElement(text(file)).jsonObject
            val rawState = raw["state"] as? JsonObject ?: continue
            states += 1
            val state = assertNotNull(SwiftJson.decode(ReversiActionResponse.serializer(), text(file)).state, "$file: state 디코드")
            val match = assertNotNull(state.match, "$file: match")
            val board = assertNotNull(match.board, "$file: 판")
            assertEquals(board.counts, match.discs, "$file: discs")
            val legal = state.legalMoves ?: emptyList()
            val turn = match.turn
            when (match.matchStatus) {
                ReversiMatchStatus.active -> {
                    val mover = turn ?: fail("$file: active 인데 차례가 없다")
                    assertTrue(ReversiRules.hasLegalMove(board, mover), "$file: 차례 주인이 둘 곳이 없다(V-09 불변식)")
                    if (state.myColor == mover) {
                        assertEquals(ReversiRules.legalMoves(board, mover), legal.map { it.toInt() }, "$file: legal_moves")
                        legalChecked += 1
                    } else {
                        assertTrue(legal.isEmpty(), "$file: 내 차례가 아닌데 legal_moves 가 있다")
                    }
                    val started = assertNotNull(match.turnStartedMs)
                    val deadline = assertNotNull(match.deadlineMs)
                    assertEquals(((state.turnSeconds ?: 0L) * 1000).toDouble(), deadline - started, "$file: 마감 = 시작 + 30초")
                }
                else -> {
                    assertTrue(legal.isEmpty(), "$file: 진행 중이 아닌데 legal_moves 가 있다")
                    assertTrue((rawState["match"] as JsonObject)["deadline_ms"] is JsonNull, "$file: 진행 중이 아닌데 마감이 있다")
                }
            }
            if (match.matchStatus == ReversiMatchStatus.finished) {
                val score = match.score
                if (score != null) {
                    // 자연 종료 — WOF 점수 · 끝 분류가 Kotlin 규칙과 같다(V-10·V-11).
                    val kotlin = ReversiRules.score(board) ?: fail("$file: 끝난 판인데 Kotlin 규칙은 안 끝났다고 한다")
                    assertTrue(score.black == kotlin.black.toLong() && score.white == kotlin.white.toLong(), "$file: 점수")
                    assertEquals(kotlin.result, match.result, "$file: 결과")
                    assertEquals(ReversiRules.endKind(board)?.rawValue, match.endReason?.rawValue, "$file: 끝 분류")
                    scored += 1
                } else {
                    assertTrue(match.endReason?.rawValue in setOf("resign", "abandoned"), "$file: 점수 없는 자연 종료")
                }
            }
            // 마지막 돌 한 수를 되돌려 다시 두면 서버 판이 나와야 한다(뒤에 패스만 있을 때).
            val moves = state.moves ?: emptyList()
            val lastIndex = moves.indexOfLast { it.kind == ReversiPly.Kind.stone }
            if (lastIndex >= 0 && moves.drop(lastIndex + 1).all { it.kind == ReversiPly.Kind.pass }) {
                val row = moves[lastIndex]
                val idx = assertNotNull(row.idx).toInt()
                val cells = board.string.toCharArray()
                cells[idx] = '.'
                for (cell in row.flipped) cells[cell.toInt()] = row.color.opponent.cell
                val prior = assertNotNull(ReversiBoard.fromString(cells.concatToString()))
                val outcome = ReversiRules.play(prior, row.color, idx).outcomeOrNull ?: fail("$file: 되돌린 판에서 그 수가 불법이다")
                assertEquals(board, outcome.board, "$file: 다시 둔 판이 서버 판과 다르다")
                assertEquals(row.flipped.map { it.toInt() }, outcome.flipped, "$file: 뒤집힌 칸")
                val passes = moves.size - 1 - lastIndex
                assertEquals(passes == 1, outcome.passed, "$file: 뒤따른 패스 줄")
                if (match.matchStatus == ReversiMatchStatus.active) assertEquals(turn, outcome.next, "$file: 다음 차례")
                undoChecked += 1
            }
        }
        assertEquals(30, states, "상태가 실린 픽스처 ${states}장")
        assertEquals(6, legalChecked, "내 차례 원문 ${legalChecked}장")
        assertEquals(10, undoChecked, "되돌려 다시 둔 원문 ${undoChecked}장")
        assertEquals(7, scored)
        // 시작 판 재생 — 수 기록이 1 부터 빠짐없는 원문 하나(첫 수 d3).
        val first = SwiftJson.decode(ReversiActionResponse.serializer(), text("reversi_move__ok.json")).state!!.match!!.board
        assertEquals(first, ReversiRules.play(ReversiBoard.start, ReversiColor.black, 19).outcomeOrNull?.board)
    }
}
