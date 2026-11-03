// 원본: Tests/checkTests/ReversiAIGameTests.swift @ 12624739
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.rules.reversi.ReversiCorpusFile
import com.yehsung.aingcheck.core.rules.reversi.ReversiPlay
import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.rules.reversi.ReversiScore
import com.yehsung.aingcheck.core.rules.reversi.ints
import com.yehsung.aingcheck.core.rules.reversi.intOrNull
import com.yehsung.aingcheck.core.rules.reversi.obj
import com.yehsung.aingcheck.core.rules.reversi.objects
import com.yehsung.aingcheck.core.rules.reversi.str
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiEndReason
import com.yehsung.aingcheck.core.wire.games.ReversiIllegalReason
import com.yehsung.aingcheck.core.wire.games.ReversiPly
import com.yehsung.aingcheck.core.wire.games.ReversiResult
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonArray
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * 아잉 뒤집기 AI 판([ReversiAIGame]) — 로컬 판의 차례·시계·연속 자동 착수 규칙(맥 `ReversiAIGameTests` 의 Kotlin 판).
 * 서버 1:1 과 같은 규칙이어야 하는 자리: 30초 자동 착수 · 연속 3회 패(자연 종료 우선) · 직접 착수는 연속 횟수 0 · 자동 패스는 시계·연속 횟수에 안 들어감 ·
 * 사람이 둘 곳 없으면 AI 차례가 연달아 옴 · 화면이 안 보이면 사람 시계를 멈춤. 연속 횟수의 정답지는 cases.json `streak` S01~S05 다.
 */
class ReversiAIGameTest {
    private val t0 = 1_800_000_000.0

    private fun at(seconds: Double): Double = t0 + seconds

    private fun stone(seq: Int, color: ReversiColor, idx: Int, flipped: List<Int>, auto: Boolean = false) =
        ReversiPly(seq, color, ReversiPly.Kind.stone, idx, flipped, auto)

    private fun pass(seq: Int, color: ReversiColor) = ReversiPly(seq, color, ReversiPly.Kind.pass, null, emptyList(), false)

    private class Run(val game: ReversiAIGame) {
        var abandonedAt: Int? = null
    }

    /**
     * streak 사건을 AI 판에 옮긴다. 사람 색 사건: auto → `autoPlaceHuman`, move → `playHuman`. AI 색 사건(auto·move): `playAI`.
     * pass 사건은 동작이 아니라 **직전 수의 결과**다 — 기록 끝이 그 색의 pass 줄인지 확인만 한다.
     * `targets` 가 있으면 돌 사건마다 그 칸을 차례로 둔다(없으면 합법 수 가운데 첫 칸).
     */
    private fun run(events: List<List<JsonElement>>, human: ReversiColor, board: ReversiBoard, turn: ReversiColor, targets: List<Int>?, label: String): Run {
        val state = Run(ReversiAIGame(human, board, turn, t0))
        val queue = ArrayDeque(targets ?: emptyList())
        for ((i, event) in events.withIndex()) {
            val kind = (event.getOrNull(0) as? JsonPrimitive)?.content ?: fail("$label 사건 $i: 모양을 못 읽었다 $event")
            val color = ReversiColor.of((event.getOrNull(1) as? JsonPrimitive)?.content) ?: fail("$label 사건 $i: 모양을 못 읽었다 $event")
            val now = at((i + 1) * 31.0)
            if (kind == "pass") {
                val last = state.game.plies.lastOrNull()
                assertTrue(last != null && last.kind == ReversiPly.Kind.pass && last.color == color && !last.auto, "$label 사건 $i: $color 자동 패스 줄이 없다")
                continue
            }
            if (state.game.turn != color) fail("$label 사건 $i: $color 차례가 아니다(지금 ${state.game.turn})")
            val legal = state.game.legalMoves
            val target = if (targets == null) legal[0] else queue.removeFirst()
            if (color == human) {
                if (kind == "auto") {
                    val index = legal.indexOf(target).takeIf { it >= 0 } ?: fail("$label 사건 $i: $target 가 합법 수가 아니다")
                    assertEquals(target, state.game.autoPlaceHuman(now) { index }, "$label 사건 $i")
                } else {
                    assertTrue(state.game.playHuman(target, now) is ReversiPlay.Played, "$label 사건 $i: 사람 수 $target 불법")
                }
            } else {
                assertTrue(state.game.playAI(target, now), "$label 사건 $i: AI 수 $target 불법")
            }
            if (state.abandonedAt == null && state.game.endReason == ReversiEndReason.abandoned) state.abandonedAt = i
            if (event.size > 2 && (event[2] as? JsonPrimitive)?.booleanOrNull == true) {
                assertTrue(state.game.isFinished && state.game.endReason != ReversiEndReason.abandoned, "$label 사건 $i: 이 수로 판이 자연히 끝나야 한다")
            }
        }
        return state
    }

    /** cases.json 기대(사람 색 하나로 투영)와 맞세운다. */
    private fun expectStreak(run: Run, expected: JsonObject, human: ReversiColor, label: String) {
        assertEquals(expected.obj("streak")!!.intOrNull(human.rawValue), run.game.humanAutoStreak, "$label 연속 횟수")
        if (expected.str("abandoned") == human.rawValue) {
            assertEquals(expected.intOrNull("at_event"), run.abandonedAt, "$label abandoned 사건 번호")
            assertEquals(expected.str("result"), run.game.result?.rawValue, "$label 결과")
            assertEquals(expected.str("end_reason"), run.game.endReason?.rawValue, "$label 끝 사유")
            assertNull(run.game.score, "$label: abandoned 는 점수 없이 승패만(V-15)")
        } else {
            assertNull(run.abandonedAt, "$label: abandoned 가 아니어야 한다")
            assertNotEquals(ReversiEndReason.abandoned, run.game.endReason, label)
        }
    }

    // 없으면: AI 판 id 가 uuid 처럼 보이거나 머리말 판정이 느슨하면 스토어가 AI 판 요청을 서버로 보낸다(서버 경로 차단의 근거).
    @Test
    fun aiMatchIdentity() {
        val a = ReversiAIGame(ReversiColor.black, t0)
        val b = ReversiAIGame(ReversiColor.black, t0)
        assertTrue(a.id.startsWith("ai-") && a.id != b.id)
        assertTrue(ReversiAIGame.isAIMatchID(a.id))
        assertTrue(ReversiAIGame.isAIMatchID("ai-1"))
        assertFalse(ReversiAIGame.isAIMatchID("9e39ff11-1b1a-45b2-836a-982b916de122"))
        assertFalse(ReversiAIGame.isAIMatchID(null))
        assertFalse(ReversiAIGame.isAIMatchID("AI-1"))
        assertEquals("ai-fixed", ReversiAIGame(ReversiColor.white, t0, id = "ai-fixed").id)
        assertEquals(a.id, a.id.lowercase(), "id 는 소문자(Swift uuidString.lowercased())")
    }

    // 없으면: 흑 선(V-04)·사람 시계의 시작이 틀려도(백인데 시계가 돎) 화면이 엉뚱한 마감을 그린다.
    @Test
    fun newGameStartsWithBlack() {
        val black = ReversiAIGame(ReversiColor.black, t0)
        assertTrue(black.board == ReversiBoard.start && black.turn == ReversiColor.black && black.plies.isEmpty() && black.moveCount == 0)
        assertEquals(t0, black.turnStartedAt)
        assertEquals(at(30.0), black.humanDeadline())
        assertEquals(listOf(19, 26, 37, 44), black.legalMoves)
        val white = ReversiAIGame(ReversiColor.white, t0)
        assertTrue(white.turn == ReversiColor.black && white.aiColor == ReversiColor.black)
        assertNull(white.humanDeadline(), "기준선: AI 차례엔 사람 시계가 없다")
        assertNull(white.humanRemaining(at(10.0)))
        assertTrue(!white.isFinished && white.result == null && white.endReason == null && white.score == null)
    }

    // 없으면: 사람 수가 차례·판을 잘못 넘기거나, 불법 수가 판을 바꾸거나, 직접 착수가 연속 횟수를 안 지운다.
    @Test
    fun humanMove() {
        val game = ReversiAIGame(ReversiColor.black, ReversiBoard.start, ReversiColor.black, t0, humanAutoStreak = 2)
        assertEquals(ReversiPlay.Illegal(ReversiIllegalReason.noFlip), game.playHuman(0, at(5.0)))
        assertEquals(ReversiPlay.Illegal(ReversiIllegalReason.occupied), game.playHuman(27, at(5.0)))
        assertEquals(ReversiPlay.Illegal(ReversiIllegalReason.outOfRange), game.playHuman(64, at(5.0)))
        assertTrue(game.plies.isEmpty() && game.board == ReversiBoard.start && game.humanAutoStreak == 2, "불법 수는 아무것도 안 바꾼다")
        val outcome = assertNotNull(game.playHuman(19, at(5.0)).outcomeOrNull)
        assertEquals(listOf(27), outcome.flipped)
        assertEquals(listOf(stone(1, ReversiColor.black, 19, listOf(27))), game.plies)
        assertEquals(0, game.humanAutoStreak, "직접 착수는 연속 횟수를 0 으로")
        assertTrue(game.turn == ReversiColor.white && game.turnStartedAt == at(5.0) && game.humanDeadline() == null)
        assertTrue(game.lastStoneIdx == 19 && game.autoStones.isEmpty())
        val before = game.copy()
        assertEquals(ReversiPlay.Illegal(ReversiIllegalReason.outOfRange), game.playHuman(20, at(6.0)), "AI 차례에 사람 수")
        assertEquals(before, game)
    }

    // 없으면: 엔진이 낸 규칙 밖 수가 판을 깨거나, 대타(무작위 합법 수)가 AI 차례 밖에서도 나온다.
    @Test
    fun aiMove() {
        val game = ReversiAIGame(ReversiColor.white, t0)
        val before = game.copy()
        assertFalse(game.playAI(0, at(1.0)))
        assertFalse(game.playAI(64, at(1.0)))
        assertEquals(before, game)
        assertEquals(44, game.randomAIFallback { it - 1 })
        assertEquals(44, game.randomAIFallback { 99 }, "범위 밖 지수는 끝으로 접는다")
        assertTrue(game.playAI(44, at(2.0)))
        assertTrue(game.turn == ReversiColor.white && game.humanDeadline() == at(32.0))
        assertNull(game.randomAIFallback { 0 }, "사람 차례엔 대타가 없다")
        assertFalse(game.playAI(43, at(3.0)), "사람 차례에 AI 수")
    }

    // 없으면: 사람이 둘 곳 없을 때 판이 사람 차례에 멈추거나, 자동 패스가 사람 시계·연속 횟수를 건드린다.
    @Test
    fun humanPassGivesAIConsecutiveTurns() {
        val p = ReversiCorpusFile.board(PASS_BOARD, "passBoard")
        val afterHuman = assertNotNull(ReversiRules.play(p, ReversiColor.black, 55).outcomeOrNull).board
        val game = ReversiAIGame(ReversiColor.black, afterHuman, ReversiColor.white, t0, humanAutoStreak = 2)
        assertTrue(game.playAI(47, at(3.0)))
        assertEquals(listOf(ReversiPly.Kind.stone, ReversiPly.Kind.pass), game.plies.map { it.kind })
        assertEquals(pass(2, ReversiColor.black), game.plies.last())
        assertEquals(ReversiColor.white, game.turn, "사람이 둘 곳이 없어 AI 가 이어 둔다")
        assertTrue(game.humanDeadline() == null && game.humanRemaining(at(100.0)) == null)
        assertEquals(2, game.humanAutoStreak, "자동 패스는 연속 횟수를 건드리지 않는다")
        assertEquals(2, game.moveCount)
        assertTrue(game.playAI(5, at(9.0)))
        assertTrue(game.turn == ReversiColor.black && game.turnStartedAt == at(9.0) && game.humanDeadline() == at(39.0), "사람 시계는 AI 의 두 번째 수부터")
        assertEquals(2, game.humanAutoStreak)

        val baseline = ReversiAIGame(ReversiColor.white, t0)
        assertTrue(baseline.playAI(19, at(3.0)))
        assertTrue(baseline.plies.map { it.kind } == listOf(ReversiPly.Kind.stone) && baseline.turn == ReversiColor.white && baseline.humanDeadline() == at(33.0))
    }

    // 없으면: AI 가 둘 곳 없을 때 사람 차례가 이어지면서 사람 시계가 새로 시작하지 않는다(옛 마감으로 곧바로 자동 착수).
    @Test
    fun aiPassRestartsHumanClock() {
        val e01 = ReversiCorpusFile.hand("E01")
        val game = ReversiAIGame(ReversiColor.black, ReversiCorpusFile.board(e01.str("board"), "E01"), ReversiColor.black, t0)
        assertNotNull(game.playHuman(2, at(20.0)).outcomeOrNull)
        assertTrue(game.plies.map { it.kind } == listOf(ReversiPly.Kind.stone, ReversiPly.Kind.pass) && game.plies.last().color == ReversiColor.white)
        assertTrue(game.turn == ReversiColor.black && game.humanDeadline() == at(50.0))
    }

    // 없으면: 30초 자동 착수가 사람 합법 수 밖을 두거나, 기록에 auto 가 안 남거나(화면 회색 점), 연속 횟수가 안 오른다.
    @Test
    fun thirtySecondAutoPlace() {
        val game = ReversiAIGame(ReversiColor.black, t0)
        assertFalse(game.isHumanClockExpired(at(29.999)))
        assertTrue(game.isHumanClockExpired(at(30.0)))
        assertEquals(18.0, game.humanRemaining(at(12.0)))
        val other = game.copy()
        assertEquals(44, game.autoPlaceHuman(at(30.0)) { it - 1 })
        assertEquals(19, other.autoPlaceHuman(at(30.0)) { 0 }, "기준선: 지수가 다르면 다른 칸")
        assertEquals(listOf(stone(1, ReversiColor.black, 44, listOf(36), auto = true)), game.plies)
        assertTrue(game.humanAutoStreak == 1 && game.autoStones == setOf(44) && game.turn == ReversiColor.white)
        assertTrue(game.humanDeadline() == null && !game.isHumanClockExpired(at(1000.0)))
        val before = game.copy()
        assertNull(game.autoPlaceHuman(at(31.0)) { 0 }, "AI 차례엔 자동 착수 없음")
        assertEquals(before, game)
        val clamped = ReversiAIGame(ReversiColor.black, t0)
        assertEquals(19, clamped.autoPlaceHuman(at(30.0)) { -7 }, "음수 지수는 0 으로 접는다")
    }

    // 없으면: 연속 횟수 규칙(직접 착수 0 · 자동 패스 무시 · 사람마다 따로 · 세 번째에 패 · 자연 종료 우선)이 서버 정답지와 갈린다.
    @Test
    fun streakCasesReplay() {
        val corpus = ReversiCorpusFile.load()
        val pass = ReversiCorpusFile.board(PASS_BOARD, "passBoard")
        val end = ReversiCorpusFile.board(END_BOARD, "endBoard")
        val checked = ArrayList<String>()
        for (item in corpus.objects("streak")) {
            val id = item.str("id")!!
            val projections: List<Projection> = when (id) {
                "S01", "S02" -> listOf(Projection(ReversiColor.black, ReversiBoard.start, ReversiColor.black, null))
                "S03" -> listOf(Projection(ReversiColor.black, pass, ReversiColor.black, PASS_MOVES))
                "S04" -> listOf(
                    Projection(ReversiColor.black, ReversiBoard.start, ReversiColor.black, null),
                    Projection(ReversiColor.white, ReversiBoard.start, ReversiColor.black, null),
                )
                "S05" -> listOf(Projection(ReversiColor.white, end, ReversiColor.white, END_MOVES))
                else -> fail("모르는 streak 사례 $id — 이 시험에 투영을 더하라")
            }
            val events = item["events"]!!.jsonArray.map { (it as JsonArray).toList() }
            for (p in projections) {
                val label = "$id(사람 ${p.human})"
                val result = run(events, p.human, p.board, p.turn, p.targets, label)
                expectStreak(result, item.obj("expected")!!, p.human, label)
                checked.add(label)
            }
        }
        assertEquals(6, checked.size, "$checked")
    }

    private data class Projection(val human: ReversiColor, val board: ReversiBoard, val turn: ReversiColor, val targets: List<Int>?)

    // 없으면: 세 번째 자동 착수가 판을 끝낼 때 abandoned 가 자연 결과를 덮어쓴다(서버 reversi__play 순서와 갈림).
    // 기준선: 같은 판에서 세 번째 자동 착수만 판을 안 끝내는 칸(45)으로 바꾸면 사람 패(abandoned).
    @Test
    fun naturalEndBeatsAbandon() {
        val end = ReversiCorpusFile.board(END_BOARD, "endBoard")
        fun play(lastAuto: Int): ReversiAIGame {
            val game = ReversiAIGame(ReversiColor.white, end, ReversiColor.white, t0)
            val steps = listOf(48 to true, 42 to false, 10 to true, 37 to false, lastAuto to true)
            for ((n, step) in steps.withIndex()) {
                val (idx, human) = step
                val now = at((n + 1) * 31.0)
                if (human) {
                    val index = game.legalMoves.indexOf(idx).takeIf { it >= 0 } ?: fail("$idx 가 합법 수가 아니다")
                    assertEquals(idx, game.autoPlaceHuman(now) { index })
                } else {
                    assertTrue(game.playAI(idx, now))
                }
            }
            return game
        }
        val natural = play(38)
        assertEquals(3, natural.humanAutoStreak)
        assertTrue(natural.isFinished && natural.endReason == ReversiEndReason.wipeout && natural.result == ReversiResult.whiteWin)
        assertEquals(ReversiScore(0, 64, ReversiResult.whiteWin), natural.score)
        assertTrue(natural.winner == ReversiColor.white && natural.finishedAt == at(155.0))
        val abandoned = play(45)
        assertEquals(3, abandoned.humanAutoStreak)
        assertTrue(abandoned.isFinished && abandoned.endReason == ReversiEndReason.abandoned && abandoned.result == ReversiResult.blackWin)
        assertTrue(abandoned.score == null && abandoned.turn == null && abandoned.turnStartedAt == null)
    }

    // 없으면: 화면을 숨긴 동안 사람 시계가 계속 돌아 돌아오자마자 자동 착수되거나, 멈춘 동안 AI 수 뒤 시작한 사람 차례가 그냥 돈다.
    @Test
    fun pauseAndResume() {
        val game = ReversiAIGame(ReversiColor.black, t0)
        game.pause(at(10.0))
        assertTrue(game.isClockPaused && game.humanDeadline() == null)
        assertEquals(20.0, game.humanRemaining(at(500.0)))
        assertFalse(game.isHumanClockExpired(at(1000.0)))
        game.pause(at(50.0))
        assertEquals(20.0, game.humanRemaining(at(500.0)), "두 번 멈춰도 처음 남은 초")
        game.resume(at(100.0))
        assertTrue(!game.isClockPaused && game.humanDeadline() == at(120.0) && game.turnStartedAt == at(90.0))
        assertEquals(10.0, game.humanRemaining(at(110.0)))
        game.resume(at(200.0))
        assertEquals(at(120.0), game.humanDeadline(), "멈추지 않은 시계를 이어도 그대로")
        assertEquals(at(30.0), ReversiAIGame(ReversiColor.black, t0).humanDeadline(), "기준선: 안 멈춘 판은 30초에 마감")

        val aiFirst = ReversiAIGame(ReversiColor.white, t0)
        aiFirst.pause(at(1.0))
        assertTrue(aiFirst.playAI(19, at(5.0)))
        assertTrue(aiFirst.turn == ReversiColor.white && aiFirst.humanDeadline() == null && aiFirst.humanRemaining(at(400.0)) == 30.0)
        aiFirst.resume(at(60.0))
        assertEquals(at(90.0), aiFirst.humanDeadline())

        val done = ReversiAIGame(ReversiColor.black, t0)
        done.resign(at(3.0))
        done.pause(at(4.0))
        assertFalse(done.isClockPaused, "끝난 판은 멈추지 않는다")
    }

    // 없으면: 기권이 점수를 남기거나(V-15), 끝난 판에 수가 또 들어간다.
    @Test
    fun resign() {
        val game = ReversiAIGame(ReversiColor.white, t0)
        assertTrue(game.playAI(19, at(1.0)))
        game.resign(at(7.0))
        assertTrue(game.isFinished && game.turn == null && game.result == ReversiResult.blackWin && game.endReason == ReversiEndReason.resign && game.score == null)
        assertTrue(game.finishedAt == at(7.0) && game.winner == ReversiColor.black)
        val before = game.copy()
        game.resign(at(9.0))
        assertEquals(ReversiPlay.Illegal(ReversiIllegalReason.outOfRange), game.playHuman(20, at(9.0)))
        assertFalse(game.playAI(20, at(9.0)))
        assertNull(game.autoPlaceHuman(at(9.0)) { 0 })
        assertEquals(before, game)
    }

    // 없으면: 검증·렌더용 시작 판에서 차례 주인이 둘 곳이 없으면 판이 그 자리에 멈춘다(불변식 위반을 V-09 로 접지 않음).
    @Test
    fun boardInitFoldsStuckTurn() {
        val corpus = ReversiCorpusFile.load()
        val e02 = ReversiCorpusFile.board(ReversiCorpusFile.hand("E02", corpus).str("board"), "E02")
        val passed = ReversiAIGame(ReversiColor.black, e02, ReversiColor.black, t0)
        assertEquals(listOf(pass(1, ReversiColor.black)), passed.plies)
        assertTrue(passed.turn == ReversiColor.white && !passed.isFinished)
        val normal = ReversiAIGame(ReversiColor.black, e02, ReversiColor.white, t0)
        assertTrue(normal.plies.isEmpty() && normal.turn == ReversiColor.white, "기준선: 둘 곳 있는 차례면 그대로")
        val e05 = ReversiCorpusFile.board(ReversiCorpusFile.hand("E05", corpus).str("board"), "E05")
        val over = ReversiAIGame(ReversiColor.white, e05, ReversiColor.black, t0)
        assertTrue(over.isFinished && over.endReason == ReversiEndReason.noMoves)
        assertEquals(ReversiScore(63, 1, ReversiResult.blackWin), over.score)
    }

    // 없으면: AI 판의 기록(돌·패스 줄 순서와 seq)·자연 종료(점수·사유)가 실전 판에서 서버 기록과 갈려도 손 사례만으로는 모른다.
    @Test
    fun wthorSampleThroughAIGame() {
        val games = ReversiCorpusFile.load().objects("wthor_sample")
        for ((n, sample) in games.withIndex()) {
            val label = sample.str("id")!!
            val human = if (n % 2 == 0) ReversiColor.black else ReversiColor.white
            val game = ReversiAIGame(human, t0)
            val moves = ReversiCorpusFile.indices(sample.str("moves")!!, label)
            val passesBefore = sample.ints("passes_before")!!
            val expectedKinds = ArrayList<ReversiPly.Kind>()
            for ((k, idx) in moves.withIndex()) {
                val now = at(k + 1.0)
                if (game.turn == human) {
                    assertTrue(game.playHuman(idx, now) is ReversiPlay.Played, "$label $k: 사람 수 불법")
                } else {
                    assertTrue(game.playAI(idx, now), "$label $k: AI 수 불법")
                }
                expectedKinds.add(ReversiPly.Kind.stone)
                if ((k + 1) in passesBefore) expectedKinds.add(ReversiPly.Kind.pass)
            }
            val plies = game.plies
            assertEquals(expectedKinds, plies.map { it.kind }, "$label 기록 줄")
            assertEquals((1..plies.size).toList(), plies.map { it.seq }, "$label seq")
            assertEquals(moves, plies.mapNotNull { it.idx }, "$label 돌 칸")
            for ((prev, ply) in plies.zipWithNext()) {
                if (ply.kind == ReversiPly.Kind.pass) assertEquals(prev.color.opponent, ply.color, "$label: 패스는 방금 둔 사람의 상대")
            }
            assertTrue(game.isFinished && game.board.string == sample.str("final_board"), "$label 마지막 판")
            assertTrue(game.result?.rawValue == sample.str("result") && game.endReason?.rawValue == sample.str("end"), "$label 결과·사유")
            val pair = sample.obj("score")!!
            assertEquals<Pair<Int?, Int?>?>(pair.intOrNull("black") to pair.intOrNull("white"), game.score?.let { it.black to it.white }, "$label 점수")
            assertTrue(game.humanAutoStreak == 0 && game.autoStones.isEmpty())
        }
    }

    private companion object {
        /** S03 재현 자리(흑 차례): 흑 55 → 백 47 → **흑 둘 곳 없음(자동 패스)** → 백 5 → 흑 6 → 백 14 → 흑 13 이 판을 끝내지 않는다. */
        const val PASS_BOARD = "bwwwb...bwwwb...bbbwbbbbbbwwbbbbbbbwbwwbbbwwbww.bbbbbbw.wwwwwwww"
        val PASS_MOVES = listOf(55, 47, 5, 6, 14, 13)

        /** S05 재현 자리(백 차례): 백 48 → 흑 42 → 백 10 → 흑 37 → 백 38 이 흑을 전멸시킨다(0:64). 백 45·46 은 판을 안 끝낸다. */
        const val END_BOARD = "................w.b......wbwwwww..wbw....w.ww....bbbw..........."
        val END_MOVES = listOf(48, 42, 10, 37, 38)
    }
}
