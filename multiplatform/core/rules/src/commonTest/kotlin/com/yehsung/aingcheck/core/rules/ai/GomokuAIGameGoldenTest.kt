// 원본: Tests/checkTests/V0332GomokuAIMatchTests.swift(1. 순수 값) · Tests/checkTests/GoldenExport/games-board/GoldenExportGamesBoardAI.swift(renju/ai-game) @ 1b8260d
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.rules.renju.GomokuTurnWarning
import com.yehsung.aingcheck.core.rules.renju.asArray
import com.yehsung.aingcheck.core.rules.renju.asObject
import com.yehsung.aingcheck.core.rules.renju.bitsOf
import com.yehsung.aingcheck.core.rules.renju.bool
import com.yehsung.aingcheck.core.rules.renju.optBool
import com.yehsung.aingcheck.core.rules.renju.optInt
import com.yehsung.aingcheck.core.rules.renju.optString
import com.yehsung.aingcheck.core.rules.renju.optStringValue
import com.yehsung.aingcheck.core.rules.renju.strings
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * AI 판 한 판의 로컬 상태(GomokuAIGame)가 Swift 와 걸음마다 같다 — 골든 `renju/ai-game`(대본 15개).
 * 서버 1:1 과 한 벌인 규칙: 흑 금수 · 백 장목 승 · 판 가득 무승부 · 흑 규칙 패스 · 대리 착수(금수 제외 · 연속 N회 패, 단 5목이 이긴다) ·
 * 사람 시계(30초, 멈춤·이어 감). 시각은 1970 기준 초 Double(C§2.5) — 골든은 t0 기준 상대 초 비트로 잰다.
 */
class GomokuAIGameGoldenTest {
    private val t0 = 1_800_000_000.0

    private fun state(game: GomokuAIGame, now: Double): Map<String, Any?> = linkedMapOf(
        "board" to game.board.serverString,
        "moveCount" to game.moveCount,
        "lastMove" to game.lastMove?.notation,
        "turn" to game.turn?.rawValue,
        "deadlineBits" to game.deadline?.let { bitsOf(it - t0) },
        "pausedBits" to game.pausedRemaining?.let(::bitsOf),
        "finished" to game.isFinished,
        "outcome" to game.outcome?.name,
        "endReason" to game.endReason?.rawValue,
        "autoPoints" to game.autoPoints.sortedBy { it.y * 15 + it.x }.map { it.notation },
        "lastAuto" to game.lastMoveWasAuto,
        "blackPassed" to game.blackPassed,
        "streak" to game.humanAutoStreak,
        "expired" to game.isHumanClockExpired(now),
        "watches" to GomokuTurnWarning.watchesMyClock(game.isFinished, game.deadline, game.turn, game.humanColor),
    )

    private fun expected(json: JsonObject): Map<String, Any?> = linkedMapOf(
        "board" to json.string("board"),
        "moveCount" to json.int("moveCount"),
        "lastMove" to json.optString("lastMove"),
        "turn" to json.optString("turn"),
        "deadlineBits" to json.optString("deadlineBits"),
        "pausedBits" to json.optString("pausedBits"),
        "finished" to json.bool("finished"),
        "outcome" to json.optString("outcome"),
        "endReason" to json.optString("endReason"),
        "autoPoints" to json.array("autoPoints").strings(),
        "lastAuto" to json.bool("lastAuto"),
        "blackPassed" to json.bool("blackPassed"),
        "streak" to json.int("streak"),
        "expired" to json.bool("expired"),
        "watches" to json.bool("watches"),
    )

    @Test
    fun scriptedGamesMatchSwiftStepByStep() {
        val golden = Golden.load("renju/ai-game")
        var steps = 0
        val ops = HashSet<String>()
        for (case in golden.cases) {
            val id = case.string("id")
            if (id == "ids") {
                assertEquals(case.string("idPrefix"), GomokuAIGame.idPrefix)
                for (row in case.array("matches")) {
                    val pair = row.asArray()
                    assertEquals(pair[1].toString().toBoolean(), GomokuAIGame.isAIMatchID(pair[0].optStringValue()), "isAIMatchID(${pair[0]})")
                }
                assertEquals(case.bool("nilMatches"), GomokuAIGame.isAIMatchID(null))
                assertEquals(case.bool("freshPrefix"), GomokuAIGame.start(GomokuColor.black, t0).id.startsWith(GomokuAIGame.idPrefix))
                continue
            }
            val human = GomokuColor.fromRawValue(case.string("humanColor"))!!
            val turnSeconds = Golden.bits(case.string("turnSecondsBits"))
            val lossStreak = case.int("autoLossStreak")
            val boardText = case.optString("board")
            val game = if (boardText == null) {
                GomokuAIGame.start(human, t0, id = "ai-golden-$id", turnSeconds = turnSeconds, autoLossStreak = lossStreak)
            } else {
                GomokuAIGame.fromBoard(
                    human, GomokuBoard.fromServerString(boardText)!!, GomokuColor.fromRawValue(case.string("turn"))!!, t0,
                    id = "ai-golden-$id", humanAutoStreak = case.int("humanAutoStreak"), turnSeconds = turnSeconds, autoLossStreak = lossStreak,
                )
            }
            for ((index, element) in case.array("steps").withIndex()) {
                val step = element.asObject()
                val op = step.string("op")
                ops.add(op)
                val now = t0 + Golden.bits(step.string("tBits"))
                val point = step.optString("point")?.let { GomokuPoint.fromNotation(it)!! }
                val fixed = step.optInt("index")
                val before = game.copy()
                val result: Any? = when (op) {
                    "start", "check" -> null
                    "human" -> game.humanPlace(point!!, now)?.let { it.kind.rawValue + (it.reason?.let { r -> ":" + r.rawValue } ?: "") }
                    "ai" -> game.applyAIMove(point, now)
                    "auto" -> game.autoPlaceHuman(now) { fixed!! }
                    "fallback" -> game.randomAIFallback { fixed!! }?.notation
                    "pause" -> { game.pause(now); null }
                    "resume" -> { game.resume(now); null }
                    "resign" -> { game.resign(); null }
                    else -> fail(golden.failure(id, "모르는 op $op"))
                }
                val wantResult: Any? = when (val r = step["result"]) {
                    null, is kotlinx.serialization.json.JsonNull -> null
                    else -> if (op == "ai" || op == "auto") step.optBool("result") else step.optString("result")
                }
                if (wantResult != result) fail(golden.failure(id, "${index}번째 걸음 $op 결과: Swift $wantResult · Kotlin $result"))
                val got = state(game, now)
                val want = expected(step.obj("state"))
                if (got != want) {
                    val key = want.keys.first { want[it] != got[it] }
                    fail(golden.failure(id, "${index}번째 걸음 $op 뒤 $key: Swift ${want[key]} · Kotlin ${got[key]}"))
                }
                // 거절·실패는 판을 바꾸지 않는다(Swift `game == before`).
                if (result is String && op == "human" || result == false) assertEquals(before, game, "${id} ${index}번째: 거절이 판을 바꿨다")
                steps++
            }
        }
        assertTrue(steps > 60, "걸음 $steps 개")
        assertEquals(setOf("start", "human", "ai", "auto", "fallback", "pause", "resume", "resign", "check"), ops)
    }

    /** 값 의미: copy 는 판·자동 착수 집합까지 떼어 낸다(Swift struct 대입). */
    @Test
    fun copyIsIndependent() {
        val game = GomokuAIGame.start(GomokuColor.black, t0, id = "ai-copy")
        val copy = game.copy()
        assertEquals(game, copy)
        copy.autoPlaceHuman(t0 + 30) { 0 }
        assertEquals(0, game.moveCount)
        assertEquals(1, copy.moveCount)
        assertTrue(game.autoPoints.isEmpty() && copy.autoPoints.size == 1)
        val board = game.board
        board[GomokuPoint.fromNotation("A1")!!] = GomokuColor.white
        assertEquals(0, game.board.stoneCount, "board 게터가 내부 판을 내줬다")
    }
}

