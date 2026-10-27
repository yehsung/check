// 원본: Tests/checkTests/GoldenExport/_base/GoldenTetrisOps.swift(goldFoldLight · goldFoldBoard) · Tests/checkTests/GoldenExport/games-tetris-minigame/GoldenGamesSupport.swift(GoldenTetrisText) @ 1b8260d
package com.yehsung.aingcheck.core.rules.tetris

import com.yehsung.aingcheck.core.rules.minigame.DualFold
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.bits
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.obj
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int

/** 테트리스 골든 접기·글자 — Swift `GoldenTetrisFold` · `GoldenTetrisText` 와 같은 칸 · 같은 순서. */
object TetrisGoldenSupport {
    const val LETTERS: String = "ijlostz"

    fun light(g: TetrisGame, h: DualFold) {
        val a = g.active
        if (a != null) {
            h.add(a.piece.rawValue); h.add(a.rotation.rawValue); h.add(a.column); h.add(a.row)
        } else {
            h.add(-1)
        }
        val next = g.next
        h.add(next.size)
        for (p in next) h.add(p.rawValue)
        h.add(g.heldPiece?.rawValue ?: -1)
        h.add(g.holdUsed)
        h.add(g.score); h.add(g.advance); h.add(g.lines); h.add(g.combo); h.add(g.backToBack)
        when (val p = g.phase) {
            TetrisGame.Phase.Ready -> h.add(0)
            TetrisGame.Phase.Running -> h.add(1)
            is TetrisGame.Phase.LineClear -> { h.add(2); h.add(p.remaining) }
            is TetrisGame.Phase.Are -> { h.add(3); h.add(p.remaining) }
            is TetrisGame.Phase.Over -> { h.add(4); h.add(p.hold) }
            TetrisGame.Phase.Result -> h.add(5)
        }
        h.add(g.elapsed)
        val c = g.lastClear
        if (c != null) {
            h.add(c.lines)
            h.add(c.spin.ordinal)
            h.add(c.backToBack); h.add(c.perfectClear); h.add(c.points); h.add(c.at)
        } else {
            h.add(-2)
        }
        h.add(g.level); h.add(g.scoreLevel); h.add(g.isGrounded)
    }

    /**
     * 화면·조준이 읽는 파생 값(Swift `GoldenTetrisDerived.values`): ghost(piece · rotation · column · row, 없으면 −1) ·
     * isPlaying · isGameOver · difficultyLevel · pendingGarbageLines.
     */
    fun derivedValues(g: TetrisGame): List<Int> {
        val out = ArrayList<Int>(9)
        val ghost = g.ghost
        if (ghost != null) out += listOf(ghost.piece.rawValue, ghost.rotation.rawValue, ghost.column, ghost.row) else out += -1
        out += if (g.isPlaying) 1 else 0
        out += if (g.isGameOver) 1 else 0
        out += g.difficultyLevel
        out += g.pendingGarbageLines
        return out
    }

    fun derived(g: TetrisGame, h: DualFold) {
        for (v in derivedValues(g)) h.add(v)
    }

    /** 굳힘 사건 글자(Swift `GoldenTetrisDerived.event`): "줄:스핀:B2B 0/1:퍼펙트 0/1:점수:공격", 없으면 "-". */
    fun event(c: TetrisGame.ClearEvent?): String =
        if (c == null) "-"
        else "${c.lines}:${c.spin.name}:${if (c.backToBack) 1 else 0}:${if (c.perfectClear) 1 else 0}:${c.points}:${c.attack}"

    fun board(g: TetrisGame, h: DualFold) {
        for (r in 0 until TetrisGame.totalRows) for (c in 0 until TetrisGame.columns) h.add(g.cell(r, c)?.rawValue ?: -1)
    }

    fun boardText(g: TetrisGame): String = (0 until TetrisGame.totalRows).joinToString("/") { r ->
        (0 until TetrisGame.columns).map { c -> g.cell(r, c)?.let { LETTERS[it.rawValue] } ?: '.' }.joinToString("")
    }

    fun pieces(list: List<TetrisGame.Piece>): String = list.map { LETTERS[it.rawValue] }.joinToString("")

    fun phaseMatches(p: TetrisGame.Phase, want: JsonObject): Boolean = when (p) {
        TetrisGame.Phase.Ready -> want.string("kind") == "ready"
        TetrisGame.Phase.Running -> want.string("kind") == "running"
        is TetrisGame.Phase.LineClear -> want.string("kind") == "lineClear" && bitsEqual(p.remaining, want.string("remainingBits"))
        is TetrisGame.Phase.Are -> want.string("kind") == "are" && bitsEqual(p.remaining, want.string("remainingBits"))
        is TetrisGame.Phase.Over -> want.string("kind") == "over" && bitsEqual(p.hold, want.string("holdBits"))
        TetrisGame.Phase.Result -> want.string("kind") == "result"
    }

    fun bitsEqual(value: Double, bits: String): Boolean = value.toRawBits() == Golden.bits(bits).toRawBits()

    fun bool(o: JsonObject, key: String): Boolean = (o[key] as? JsonPrimitive)?.boolean ?: error("골든 칸 '$key' 가 불이 아니다")

    /** 끝 상태 칸 대조(Swift `GoldenTetrisText.final` — 해시·프레임 수는 부르는 쪽이 본다). 다른 칸 이름 목록을 돌려준다. */
    fun finalMismatches(g: TetrisGame, want: JsonObject): List<String> {
        val out = mutableListOf<String>()
        fun check(name: String, ok: Boolean, got: () -> Any?) { if (!ok) out += "$name(Kotlin ${got()})" }
        check("score", g.score == want.int("score")) { g.score }
        check("advance", g.advance == want.int("advance")) { g.advance }
        check("lines", g.lines == want.int("lines")) { g.lines }
        check("combo", g.combo == want.int("combo")) { g.combo }
        check("backToBack", g.backToBack == want.int("backToBack")) { g.backToBack }
        check("level", g.level == want.int("level")) { g.level }
        check("next", pieces(g.next) == want.string("next")) { pieces(g.next) }
        val held = g.heldPiece?.let { LETTERS[it.rawValue].toString() } ?: "-"
        check("held", held == want.string("held")) { held }
        check("phase", phaseMatches(g.phase, want.obj("phase"))) { g.phase }
        check("elapsed", bitsEqual(g.elapsed, want.string("elapsedBits"))) { Golden.bitsText(g.elapsed) }
        check("attackSentTotal", g.attackSentTotal == want.int("attackSentTotal")) { g.attackSentTotal }
        val pending = want.array("pendingGarbage").map { (it as JsonPrimitive).int }
        check("pendingGarbage", g.pendingGarbage == pending) { g.pendingGarbage }
        check("levelFloor", g.levelFloor == want.int("levelFloor")) { g.levelFloor }
        val mask = want.array("garbageMask").map { (it as JsonPrimitive).int }
        check("garbageMask", g.garbageMask == mask) { g.garbageMask }
        check("board", boardText(g) == want.string("board")) { boardText(g) }
        return out
    }

    /** _base 연산(contract/README.md §2-4). */
    fun applyBaseOp(op: String, g: TetrisGame) {
        when (op) {
            "L+" -> g.setLeftHeld(true)
            "L-" -> g.setLeftHeld(false)
            "R+" -> g.setRightHeld(true)
            "R-" -> g.setRightHeld(false)
            "SD+" -> g.setSoftDropHeld(true)
            "SD-" -> g.setSoftDropHeld(false)
            "CW" -> g.rotate(clockwise = true)
            "CCW" -> g.rotate(clockwise = false)
            "HOLD" -> g.holdCurrentPiece()
            "ACT" -> g.action()
            else -> error("모르는 테트리스 연산 '$op'")
        }
    }
}
