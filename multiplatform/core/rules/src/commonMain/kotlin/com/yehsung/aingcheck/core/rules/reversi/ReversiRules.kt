// 원본: Sources/CheckCore/ReversiRules.swift @ 12624739 (판정 몫 — 값 타입은 core/wire …/games/ReversiValues.kt)
package com.yehsung.aingcheck.core.rules.reversi

import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiCounts
import com.yehsung.aingcheck.core.wire.games.ReversiEndKind
import com.yehsung.aingcheck.core.wire.games.ReversiIllegalReason
import com.yehsung.aingcheck.core.wire.games.ReversiResult

// 아잉 뒤집기(내부 이름 reversi) 규칙 — 리버시 표준(WOF·JOF): 8×8 · 흑 선 · 8방향 동시 뒤집기 · 하나 이상 끼워야 합법 ·
// 둘 곳이 없을 때만 자동 패스 · 둘 다 없으면 끝 · 빈칸은 이긴 쪽에 더한다 · 같으면 32:32 무승부.
// 설계: flip/SPEC.md §2 · §4.1. 규칙 정본 rules.md V-01~V-17, 정답지 cases.json(Tests/checkTests/Fixtures/reversi/cases.json).
//
// ── 쌍둥이 ──
// 서버(plpgsql `reversi_*`)·맥 Swift(ReversiRules.swift)·이 파일이 같은 판정을 따로 한다. 이름 대응은 SPEC §2.1 표가 정본이다:
// validate_board ↔ `ReversiBoard.fromString` · counts ↔ `ReversiBoard.counts` · flips ↔ `flips` · legal_moves ↔ `legalMoves` ·
// apply+next_turn+end_kind+score_wof ↔ `play` · next_turn ↔ `nextTurn` · end_kind ↔ `endKind` · score_wof ↔ `score` · perft ↔ `perft`.
// 공개 표면(이름·서명)은 스토어·화면 갈래와의 계약이다(맥과 같은 이름).
//
// Kotlin 이식 메모: Swift `Result<ReversiMoveOutcome, ReversiIllegalReason>` → [ReversiPlay](Played · Illegal 두 갈래).
// 값 타입(판 · 색 · 돌 수 · 결과 · 끝 분류 · 불법 까닭)은 와이어 모듈에 산다(모듈 방향 rules → wire, 아잉 큐브 RummyFace 선례).

/** Swift `ReversiPoint` — 칸 좌표. col 0 = a열(왼쪽), row 0 = 1행(위). 와이어는 idx 하나만 쓰고, 이 타입은 화면 표기("d3")용이다. */
class ReversiPoint private constructor(val col: Int, val row: Int) {
    val idx: Int get() = row * 8 + col

    /** 소문자 좌표("d3"). */
    val coord: String get() = "${'a' + col}${row + 1}"

    override fun equals(other: Any?): Boolean = other is ReversiPoint && other.col == col && other.row == row

    override fun hashCode(): Int = idx

    override fun toString(): String = coord

    companion object {
        /** Swift `init?(col:row:)`. */
        fun of(col: Int, row: Int): ReversiPoint? = if (col in 0 until 8 && row in 0 until 8) ReversiPoint(col, row) else null

        /** Swift `init?(idx:)`. */
        fun of(idx: Int): ReversiPoint? = if (idx in 0 until 64) ReversiPoint(idx % 8, idx / 8) else null

        /** Swift `init?(coord:)` — "d3"·"D3" → (col 3, row 2). 정확히 두 글자(열 a~h 대소문자 + 행 1~8)만 받는다. */
        fun fromCoord(coord: String): ReversiPoint? {
            if (coord.length != 2) return null
            // ASCII 대문자 → 소문자(Swift `| 0x20`). 숫자·기호는 아래 범위 검사에서 걸러진다. ASCII 밖 글자는 Swift 에서 UTF-8 두 바이트 이상이라 길이에서 걸린다.
            val first = coord[0].code
            val second = coord[1].code
            if (first > 0x7F || second > 0x7F) return null
            val letter = first or 0x20
            if (letter !in 'a'.code..'h'.code || second !in '1'.code..'8'.code) return null
            return ReversiPoint(letter - 'a'.code, second - '1'.code)
        }
    }
}

/** Swift `ReversiScore` — WOF 점수(V-11): 많은 쪽이 이기고 빈칸은 전부 이긴 쪽에 더한다. 같으면 32:32. 합은 늘 64. 끝난 판에만 있다. */
data class ReversiScore(val black: Int, val white: Int, val result: ReversiResult)

/** Swift `ReversiMoveOutcome` — 합법 수 하나를 둔 결과(서버 `reversi_judge` 합법 갈래와 1:1). */
data class ReversiMoveOutcome(
    /** 둔 뒤의 판. */
    val board: ReversiBoard,
    /** 뒤집힌 칸(오름차순, 둔 칸은 빠진다). */
    val flipped: List<Int>,
    /** 다음 차례. null = 끝. */
    val next: ReversiColor?,
    /** 상대가 둘 곳이 없어 자동 패스됐고 둔 사람이 이어 둔다(V-09). */
    val passed: Boolean,
    val isOver: Boolean,
    val counts: ReversiCounts,
    /** 끝났을 때만. */
    val score: ReversiScore?,
    /** 끝났을 때만. */
    val end: ReversiEndKind?,
)

/** Swift `Result<ReversiMoveOutcome, ReversiIllegalReason>` — 한 수의 판정. */
sealed interface ReversiPlay {
    data class Played(val outcome: ReversiMoveOutcome) : ReversiPlay
    data class Illegal(val reason: ReversiIllegalReason) : ReversiPlay

    /** Swift `try? result.get()`. */
    val outcomeOrNull: ReversiMoveOutcome? get() = (this as? Played)?.outcome
}

/** Swift `ReversiRules.nextTurn` 의 튜플 `(next, passed)`. */
data class ReversiNextTurn(val next: ReversiColor?, val passed: Boolean)

/** Swift `perftDivide` 의 한 줄 `(idx, nodes)`. 뿌리가 패스면 idx 가 null. */
data class ReversiPerftDivide(val idx: Int?, val nodes: Long)

/** Swift `ReversiBoard.sides(_:)` — `color` 쪽에서 본 (내 돌, 상대 돌). */
internal fun ReversiBoard.sides(color: ReversiColor): Pair<ULong, ULong> = if (color == ReversiColor.black) black to white else white to black

/** Swift `ReversiBoard.bits(_:)` — 그 색의 돌 비트. */
internal fun ReversiBoard.bits(color: ReversiColor): ULong = if (color == ReversiColor.black) black else white

/** Swift `ReversiBoard.init(own:opp:color:)` — `color` 쪽 (내 돌, 상대 돌)에서 판을 다시 만든다. */
internal fun reversiBoardOf(own: ULong, opp: ULong, color: ReversiColor): ReversiBoard =
    if (color == ReversiColor.black) ReversiBoard(black = own, white = opp) else ReversiBoard(black = opp, white = own)

/** Swift `ReversiRules` — 규칙 판정(순수 함수). 서버 `reversi_*` 판정 함수와 cases.json 이 정답지다. */
object ReversiRules {
    /** `idx` 에 `color` 를 두면 뒤집힐 칸(오름차순). 범위 밖·빈칸 아님·하나도 못 끼움이면 []. */
    fun flips(board: ReversiBoard, color: ReversiColor, idx: Int): List<Int> {
        if (idx !in 0 until 64) return emptyList()
        val (own, opp) = board.sides(color)
        return ReversiBits.indices(ReversiBits.flips(own, opp, idx))
    }

    /** `color` 의 합법 수(오름차순). */
    fun legalMoves(board: ReversiBoard, color: ReversiColor): List<Int> {
        val (own, opp) = board.sides(color)
        return ReversiBits.indices(ReversiBits.moves(own, opp))
    }

    fun hasLegalMove(board: ReversiBoard, color: ReversiColor): Boolean {
        val (own, opp) = board.sides(color)
        return ReversiBits.moves(own, opp) != 0uL
    }

    /**
     * 한 수를 둔다(V-06~V-11). 불법이면 까닭(범위 밖 → 이미 돌 → 끼울 돌 없음 순서)만 돌려주고 판은 그대로다.
     * 차례 검사는 하지 않는다 — 누가 둘 차례인지는 판 문자열에 없다(서버·AI 판이 따로 본다).
     */
    fun play(board: ReversiBoard, color: ReversiColor, idx: Int): ReversiPlay {
        if (idx !in 0 until 64) return ReversiPlay.Illegal(ReversiIllegalReason.outOfRange)
        if (board[idx] != null) return ReversiPlay.Illegal(ReversiIllegalReason.occupied)
        val (own, opp) = board.sides(color)
        val flipped = ReversiBits.flips(own, opp, idx)
        if (flipped == 0uL) return ReversiPlay.Illegal(ReversiIllegalReason.noFlip)
        val after = reversiBoardOf(own or flipped or (1uL shl idx), opp and flipped.inv(), color)
        val turn = nextTurn(after, color)
        val isOver = turn.next == null
        return ReversiPlay.Played(
            ReversiMoveOutcome(
                board = after,
                flipped = ReversiBits.indices(flipped),
                next = turn.next,
                passed = turn.passed,
                isOver = isOver,
                counts = after.counts,
                score = if (isOver) wofScore(after) else null,
                end = if (isOver) endKindOfFinished(after) else null,
            ),
        )
    }

    /**
     * `mover` 가 방금 둔 뒤 다음 차례(V-09): ① 상대에게 합법 수가 있으면 (상대, false) ② 없고 mover 에 있으면
     * 상대 자동 패스 (mover, true) ③ 둘 다 없으면 끝 (null, false).
     */
    fun nextTurn(board: ReversiBoard, mover: ReversiColor): ReversiNextTurn {
        if (hasLegalMove(board, mover.opponent)) return ReversiNextTurn(mover.opponent, false)
        if (hasLegalMove(board, mover)) return ReversiNextTurn(mover, true)
        return ReversiNextTurn(null, false)
    }

    /** 끝난 판의 분류(V-10). 안 끝났으면(어느 쪽이든 둘 곳이 있으면) null. */
    fun endKind(board: ReversiBoard): ReversiEndKind? = if (isOver(board)) endKindOfFinished(board) else null

    /** WOF 점수(V-11). 끝난 판에만 — 안 끝났으면 null. */
    fun score(board: ReversiBoard): ReversiScore? = if (isOver(board)) wofScore(board) else null

    /**
     * 수 세기(V-17) — `ply_pass` 관례: 강제 패스도 한 수로 세고, depth 에 닿기 전에 끝난 판은 세지 않는다.
     * depth 0 은 1(국면 자신), 음수는 0.
     */
    fun perft(board: ReversiBoard, toMove: ReversiColor, depth: Int): Long {
        if (depth < 0) return 0
        val (own, opp) = board.sides(toMove)
        return ReversiBits.perft(own, opp, depth)
    }

    /** 실패 진단용 divide: 첫 수마다 그 아래 노드 수(idx 오름차순). 뿌리가 패스면 `(null, 노드)` 한 줄, 끝난 판·depth < 1 이면 []. */
    fun perftDivide(board: ReversiBoard, toMove: ReversiColor, depth: Int): List<ReversiPerftDivide> {
        if (depth < 1) return emptyList()
        val moves = legalMoves(board, toMove)
        if (moves.isEmpty()) {
            if (!hasLegalMove(board, toMove.opponent)) return emptyList()
            return listOf(ReversiPerftDivide(null, perft(board, toMove.opponent, depth - 1)))
        }
        return moves.map { idx ->
            val outcome = play(board, toMove, idx).outcomeOrNull ?: return@map ReversiPerftDivide(idx, 0)
            ReversiPerftDivide(idx, perft(outcome.board, toMove.opponent, depth - 1))
        }
    }

    // MARK: 내부(AI 판·엔진이 같이 쓴다 — Swift 처럼 internal: 끝났는지 안 보는 점수·분류를 모듈 밖이 부르지 못하게, 검토 F5)

    /** 둘 다 둘 곳이 없다(V-10). */
    internal fun isOver(board: ReversiBoard): Boolean =
        ReversiBits.moves(board.black, board.white) == 0uL && ReversiBits.moves(board.white, board.black) == 0uL

    /** 끝났다고 이미 아는 판의 분류: 한쪽 0개 → wipeout(가득 차도 전멸 먼저) → 빈칸 0 → board_full → no_moves. */
    internal fun endKindOfFinished(board: ReversiBoard): ReversiEndKind {
        val counts = board.counts
        if (counts.black == 0 || counts.white == 0) return ReversiEndKind.wipeout
        if (counts.empty == 0) return ReversiEndKind.boardFull
        return ReversiEndKind.noMoves
    }

    /** WOF 점수 계산(끝났는지는 보지 않는다). */
    internal fun wofScore(board: ReversiBoard): ReversiScore {
        val counts = board.counts
        if (counts.black > counts.white) return ReversiScore(counts.black + counts.empty, counts.white, ReversiResult.blackWin)
        if (counts.white > counts.black) return ReversiScore(counts.black, counts.white + counts.empty, ReversiResult.whiteWin)
        return ReversiScore(32, 32, ReversiResult.draw)
    }
}
