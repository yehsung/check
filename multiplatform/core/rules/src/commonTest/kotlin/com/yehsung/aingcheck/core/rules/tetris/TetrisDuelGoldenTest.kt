// 원본: Tests/checkTests/GoldenExport/games-tetris-minigame/GoldenExportTetris.swift(tetris/duel-rules · tetris/duel · GoldenDuelReplay) @ 1b8260d
package com.yehsung.aingcheck.core.rules.tetris

import com.yehsung.aingcheck.core.rules.minigame.DualFold
import com.yehsung.aingcheck.core.rules.minigame.GoldenFailures
import com.yehsung.aingcheck.core.rules.minigame.GoldenOps
import com.yehsung.aingcheck.core.rules.minigame.ReplayTrace
import com.yehsung.aingcheck.core.rules.tetris.TetrisGoldenSupport.bitsEqual
import com.yehsung.aingcheck.core.rules.tetris.TetrisGoldenSupport.bool
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.hex64
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import com.yehsung.aingcheck.testkit.golden.stringValue
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.int
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 테트리스 1:1 대결 세션(v0.3.60)이 Swift 와 비트로 같다: 가속 바닥 · 시작 시각 · 판 글자 · 다시 열기(G1), 그리고 세션 대본 넷(G3 —
 * 시작 맞추기 · 폰 한 칸 이동 3종 · 상대 공격 차분 · 가속 · 30초 따라잡기 · 보고 차분 · 끝).
 */
class TetrisDuelGoldenTest {

    @Test
    fun duelRulesMatchSwift() {
        val golden = Golden.load("tetris/duel-rules")
        val f = GoldenFailures(golden)
        for (case in golden.cases) {
            val id = case.string("id")
            when {
                id == "rampLevelFloor" -> {
                    val times = GoldenOps.bits(case.string("timesBits"))
                    val want = GoldenOps.ints(case.string("values"))
                    times.forEachIndexed { i, t ->
                        val got = TetrisDuelSession.rampLevelFloor(t)
                        f.check(id, got == want[i]) { "t=$t: 기대 ${want[i]} · Kotlin $got" }
                    }
                }
                id == "localStart" -> {
                    val inputs = case.array("inputsBits").map { GoldenOps.bits(it.stringValue()) }
                    val want = GoldenOps.bits(case.string("valuesBits"))
                    inputs.forEachIndexed { i, (a, b, c) ->
                        val got = TetrisDuelSession.localStart(a, b, c)
                        f.check(id, got.toRawBits() == want[i].toRawBits()) { "입력 $i: 기대 ${Golden.bitsText(want[i])} · Kotlin ${Golden.bitsText(got)}" }
                    }
                }
                id.startsWith("board-") -> {
                    val cps = case.string("cps")
                    val text = if (cps.isEmpty()) "" else buildString {
                        cps.split(' ').forEach { appendScalar(it.toInt(16)) }
                    }
                    val valid = TetrisDuelBoard.isValid(text)
                    f.check(id, valid == bool(case, "valid")) { "isValid Kotlin $valid" }
                    val decoded = TetrisDuelBoard.decode(text)?.joinToString("") { row ->
                        row.map { cell ->
                            when (cell) {
                                TetrisDuelCell.Empty -> '.'
                                is TetrisDuelCell.Piece -> TetrisDuelBoard.letter(cell.piece)
                                TetrisDuelCell.Garbage -> 'G'
                            }
                        }.joinToString("")
                    }
                    val want = case["decoded"].let { if (it == null || it is JsonNull) null else it.stringValue() }
                    f.check(id, decoded == want) { "decode Kotlin $decoded" }
                }
                id == "encode-fixture" -> {
                    val rows = case.array("rows").map { it.stringValue() }
                    val game = TetrisGame(3uL, TetrisGame.boardFixture(rows), active = null, garbageMask = TetrisGame.garbageMaskFixture(rows))
                    f.check(id, TetrisDuelBoard.encode(game) == case.string("text")) { "encode Kotlin ${TetrisDuelBoard.encode(game)}" }
                    f.check(id, TetrisGoldenSupport.boardText(game) == case.string("fixtureBoard")) { "boardFixture Kotlin ${TetrisGoldenSupport.boardText(game)}" }
                    val mask = case.array("fixtureMask").map { (it as JsonPrimitive).int }
                    f.check(id, game.garbageMask == mask) { "garbageMaskFixture Kotlin ${game.garbageMask}" }
                }
                id.startsWith("resume-") -> {
                    val point = TetrisDuelResumePoint(
                        seq = case.int("seq"), board = case.string("board"), lines = case.int("lines"),
                        garbageSent = case.int("garbageSent"), garbageApplied = case.int("garbageApplied"),
                        pending = case.int("pending"), elapsedSeconds = Golden.bits(case.string("elapsedSecondsBits")),
                    )
                    val session = TetrisDuelSession.resuming(case.int("seed").toLong(), point)
                    val want = case["result"]
                    if (want == null || want is JsonNull) {
                        f.check(id, session == null) { "Swift 는 풀지 못했는데(null) Kotlin 은 세션을 만들었다" }
                    } else if (session == null) {
                        f.fail(id, "Swift 는 세션을 만들었는데 Kotlin 은 null")
                    } else {
                        val bad = sessionMismatches(session, want as JsonObject)
                        f.check(id, bad.isEmpty()) { "세션 칸 $bad" }
                    }
                }
                id.startsWith("new-") -> {
                    val session = TetrisDuelSession(case.int("seed").toLong(), case.int("startingSeq"), case.int("garbageAppliedIn"))
                    val bad = sessionMismatches(session, case.obj("result"))
                    f.check(id, bad.isEmpty()) { "세션 칸 $bad" }
                }
                else -> f.fail(id, "Kotlin 시험이 모르는 case")
            }
        }
        f.assertNone()
        assertTrue(f.compared > 30)
    }

    @Test
    fun duelScriptsMatchSwift() {
        val golden = Golden.load("tetris/duel")
        val f = GoldenFailures(golden)
        var maxFloor = 1
        for (case in golden.cases) {
            val id = case.string("id")
            val run = replayDuel(case)
            maxFloor = maxOf(maxFloor, run.maxFloor)
            val final = case.obj("final")
            val mismatch = run.trace.firstMismatch(
                case.string("frameBytes"), GoldenOps.hexes(case.string("checkpoints")), final.int("frames"),
                final.hex64("hash"), run.fold.total.value,
            )
            f.check(id, mismatch == null) { mismatch!! }
            f.check(id, run.reports == case.int("reports")) { "보고 수 Kotlin ${run.reports} · Swift ${case.int("reports")}" }
            f.check(id, run.maxFloor == case.int("maxLevelFloor")) { "가속 바닥 최댓값 Kotlin ${run.maxFloor}" }
            val bad = sessionMismatches(run.session, final.obj("session")).toMutableList()
            if (!bitsEqual(run.session.droppedSeconds, final.string("droppedSecondsBits"))) bad += "droppedSeconds"
            val lastAt = final["lastReportAtBits"]
            val lastOk = if (lastAt == null || lastAt is JsonNull) run.session.lastReportAt == null
            else run.session.lastReportAt?.let { bitsEqual(it, lastAt.stringValue()) } == true
            if (!lastOk) bad += "lastReportAt"
            val last = final["lastReport"]
            val report = run.lastReport
            if (last is JsonObject && report != null) {
                if (report.seq != last.int("seq") || report.board != last.string("board") || report.lines != last.int("lines") ||
                    report.garbageSent != last.int("garbageSent") || report.garbageApplied != last.int("garbageApplied") ||
                    report.pending != last.int("pending") || report.toppedOut != bool(last, "toppedOut")
                ) bad += "lastReport($report)"
            } else if (!(last == null || last is JsonNull) || report != null) {
                bad += "lastReport 유무"
            }
            f.check(id, bad.isEmpty()) { "끝 칸 $bad" }
        }
        f.assertNone()
        assertTrue(maxFloor >= 12, "대본이 가속 바닥 12 까지 가지 않았다(최대 $maxFloor) — 골든이 바뀌었나")
    }

    class DuelRun(
        val session: TetrisDuelSession,
        val fold: DualFold,
        val trace: ReplayTrace,
        val reports: Int,
        val lastReport: TetrisDuelReport?,
        val maxFloor: Int,
    )

    companion object {
        /** 유니코드 스칼라 하나를 UTF-16 으로(공용 소스셋 — JVM 전용 appendCodePoint 를 쓰지 않는다). */
        fun StringBuilder.appendScalar(cp: Int) {
            if (cp < 0x10000) {
                append(cp.toChar())
            } else {
                val v = cp - 0x10000
                append((0xD800 + (v shr 10)).toChar())
                append((0xDC00 + (v and 0x3FF)).toChar())
            }
        }

        fun sessionMismatches(s: TetrisDuelSession, want: JsonObject): List<String> {
            val out = mutableListOf<String>()
            if (s.seed != want.int("seed").toLong()) out += "seed"
            if (s.started != bool(want, "started")) out += "started"
            if (s.finished != bool(want, "finished")) out += "finished"
            if (s.seq != want.int("seq")) out += "seq(${s.seq})"
            if (s.garbageApplied != want.int("garbageApplied")) out += "garbageApplied(${s.garbageApplied})"
            if (!bitsEqual(s.simulated, want.string("simulatedBits"))) out += "simulated(${Golden.bitsText(s.simulated)})"
            val startAt = want["startAtBits"]
            val startOk = if (startAt == null || startAt is JsonNull) s.startAt == null
            else s.startAt?.let { bitsEqual(it, startAt.stringValue()) } == true
            if (!startOk) out += "startAt(${s.startAt})"
            if (s.reportedAttackSent != want.int("reportedAttackSent")) out += "reportedAttackSent"
            if (s.isLive != bool(want, "isLive")) out += "isLive"
            if (s.toppedOut != bool(want, "toppedOut")) out += "toppedOut"
            out += TetrisGoldenSupport.finalMismatches(s.game, want.obj("game")).map { "game.$it" }
            if (TetrisGoldenSupport.pieces(s.game.next) != want.string("firstNext")) out += "next"
            return out
        }

        fun applyDuelOp(op: String, s: TetrisDuelSession, now: Double) {
            when (op) {
                "L+" -> s.setLeftHeld(true)
                "L-" -> s.setLeftHeld(false)
                "R+" -> s.setRightHeld(true)
                "R-" -> s.setRightHeld(false)
                "SD+" -> s.setSoftDropHeld(true)
                "SD-" -> s.setSoftDropHeld(false)
                "CW" -> s.rotate(clockwise = true)
                "CCW" -> s.rotate(clockwise = false)
                "HOLD" -> s.hold()
                "HD" -> s.hardDrop()
                "ML" -> s.moveLeftOneCell()
                "MR" -> s.moveRightOneCell()
                "SD1" -> s.softDropOneCell()
                "REL" -> s.releaseAllKeys()
                "FIN" -> s.finish()
                "N" -> Unit
                else -> when {
                    op.startsWith("SY") -> {
                        val (a, b) = op.removePrefix("SY").split('/').map { it.toLong().toDouble() }
                        s.syncStart(a, b, now)
                    }
                    op.startsWith("A") -> s.absorbOpponentAttack(op.removePrefix("A").toInt())
                    op.startsWith("Q") -> s.adoptServerSeq(op.removePrefix("Q").toInt())
                    else -> error("모르는 대결 연산 '$op'")
                }
            }
        }

        private fun boardFold(s: TetrisDuelSession, h: DualFold) {
            TetrisGoldenSupport.board(s.game, h)
            for (mask in s.game.garbageMask) h.add(mask)
        }

        private fun fold(s: TetrisDuelSession, reason: TetrisDuelReportReason?, report: TetrisDuelReport?, h: DualFold) {
            val g = s.game
            TetrisGoldenSupport.light(g, h)
            h.add(g.levelFloor)
            val pending = g.pendingGarbage
            h.add(pending.size)
            for (n in pending) h.add(n)
            h.add(g.attackSentTotal)
            h.addOptional(s.startAt)
            h.add(s.simulated)
            h.add(s.started)
            h.add(s.finished)
            h.add(s.droppedSeconds)
            h.add(s.garbageApplied)
            h.add(s.seq)
            h.addOptional(s.lastReportAt)
            h.add(s.reportedAttackSent)
            h.add(s.reportedToppedOut)
            h.add(s.isLive)
            h.add(s.toppedOut)
            if (reason != null && report != null) {
                h.add(reason.ordinal + 1)
                h.add(report.seq)
                for (byte in report.board.encodeToByteArray()) h.add(byte.toInt() and 0xFF)
                h.add(report.lines)
                h.add(report.garbageSent)
                h.add(report.garbageApplied)
                h.add(report.pending)
                h.add(report.toppedOut)
            } else {
                h.add(0)
            }
        }

        /** Swift `GoldenDuelReplay.run` 과 같은 순서: 시작 → preOps(now 0) → 판 접기 → 프레임마다 [연산 → advance → 보고 → 접기]. */
        fun replayDuel(case: JsonObject): DuelRun {
            val seed = case.int("seed").toLong()
            val dt = Golden.bits(case.string("dtBits"))
            val resume = case["resume"] as? JsonObject
            val session = if (resume != null) {
                TetrisDuelSession.resuming(
                    seed,
                    TetrisDuelResumePoint(
                        seq = resume.int("seq"), board = resume.string("board"), lines = resume.int("lines"),
                        garbageSent = resume.int("garbageSent"), garbageApplied = resume.int("garbageApplied"),
                        pending = resume.int("pending"), elapsedSeconds = Golden.bits(resume.string("elapsedSecondsBits")),
                    ),
                ) ?: error("다시 열기 판을 못 풀었다")
            } else {
                TetrisDuelSession(seed)
            }
            case.string("preOps").split(' ').filter { it.isNotEmpty() }.forEach { applyDuelOp(it, session, 0.0) }
            val h = DualFold()
            boardFold(session, h)
            val trace = ReplayTrace(case.int("checkpointEvery"))
            var reports = 0
            var lastReport: TetrisDuelReport? = null
            var maxFloor = session.game.levelFloor
            var frame = 0
            for (ops in GoldenOps.decode(case.string("ops"))) {
                frame += 1
                val now = frame.toDouble() * dt
                h.beginFrame()
                val before = session.game.advance
                for (op in ops) applyDuelOp(op, session, now)
                if ("N" !in ops) session.advance(now)
                val reason = session.reportReason(now)
                val report = reason?.let { session.makeReport(now) }
                if (reason != null) {
                    reports += 1
                    lastReport = report
                }
                fold(session, reason, report, h)
                if (session.game.advance != before) boardFold(session, h)
                trace.endFrame(h)
                maxFloor = maxOf(maxFloor, session.game.levelFloor)
            }
            return DuelRun(session, h, trace, reports, lastReport, maxFloor)
        }
    }

    /** 대조(기준선이 다른 입력): 대본에서 한 칸 이동 하나를 빼면 프레임 바이트가 그 프레임 근처에서 갈린다 — 재생이 연산을 쓴다. */
    @Test
    fun droppingOneCellMoveChangesTheReplay() {
        val golden = Golden.load("tetris/duel")
        val case = golden.case("phone-60")
        val ops = GoldenOps.decode(case.string("ops"))
        val at = ops.indexOfFirst { "ML" in it || "MR" in it }
        assertTrue(at >= 0, "phone-60 대본에 한 칸 이동이 없다")
        val edited = ops.toMutableList().also { list -> list[at] = list[at].filter { it != "ML" && it != "MR" } }
        val rle = edited.joinToString(",") { "1:" + it.joinToString(" ") }
        val mutated = JsonObject(case.toMutableMap().also { it["ops"] = JsonPrimitive(rle) })
        val run = replayDuel(mutated)
        val firstDiff = (0 until run.trace.frames).firstOrNull {
            !run.trace.frameBytes.regionMatches(it * 2, case.string("frameBytes"), it * 2, 2)
        }
        assertTrue(firstDiff != null && firstDiff >= at, "한 칸 이동을 빼도 재생이 같다(또는 그 앞에서 갈렸다): $firstDiff, 뺀 프레임 ${at + 1}")
        assertEquals(at, firstDiff, "처음 갈린 프레임이 연산을 뺀 프레임이어야 한다")
    }
}
