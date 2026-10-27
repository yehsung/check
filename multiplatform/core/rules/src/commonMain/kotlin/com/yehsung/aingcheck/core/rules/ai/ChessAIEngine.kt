// 원본: Sources/CheckCore/ChessAIEngine.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.ai

import com.yehsung.aingcheck.core.foundation.rng.SplitMix64
import com.yehsung.aingcheck.core.rules.chess.ChessCode
import com.yehsung.aingcheck.core.rules.chess.ChessEngine
import com.yehsung.aingcheck.core.rules.chess.ChessMove
import com.yehsung.aingcheck.core.rules.chess.ChessPosition
import com.yehsung.aingcheck.core.rules.chess.ChessRawMove
import com.yehsung.aingcheck.core.rules.chess.ChessUndo
import com.yehsung.aingcheck.core.rules.chess.repetitionKey
import kotlin.math.abs
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.TimeMark
import kotlin.time.TimeSource

// 기기 안 체스 AI. 공개 입구는 `ChessAI.bestMove`(측정·보고용 `ChessAI.decide`) 하나다.
//
// 오목 AI 와 같은 계약: 단일 난이도(항상 최선) · 시간 상한 1.5초 · 취소 문 · 순수 동기 함수 · 점수가 **완전히 같은** 수끼리는 씨앗 무작위.
// 판 표현은 새로 만들지 않는다: 탐색은 `ChessEngine`(ChessRules.kt)의 제자리 make/unmake·generate·isAttacked·pinnedMask 를 그대로 쓴다
// — 규칙을 한 줄도 다시 적지 않는다(두 벌이면 그 어긋남은 대국 중 불법 수로 드러난다).
// 탐색: 반복 심화 네가맥스 알파베타(PVS) + 치환표(Zobrist) + 수 정렬(치환표 수 → MVV-LVA → 킬러 → 이력) + 널 무브 + LMR + **정지 탐색**.
// 메이트는 거리로 점수화한다(`mate - ply`). 스테일메이트는 0(무승부).
// 시간: 마감은 예산보다 조금 앞에 둔다. 반복 심화는 예산의 절반을 넘겨 쓴 뒤에는 다음 깊이를 시작하지 않는다.
//
// Kotlin 이식 메모: Swift UInt64 해시는 Long 비트 · 시간은 주입한 단조 [TimeSource] · 안정 정렬(Swift sort 와 같은 동점 순서) ·
// 동점 고르기는 [SwiftRandomSource](Swift randomElement 와 같은 알고리즘) — 골든 `chess/ai-trace` 가 수·점수·깊이·노드 수까지 대조한다.

/** 한 수를 고를 때의 한도. 오목([GomokuAISearchLimits])과 같은 모양이다. */
data class ChessAISearchLimits(
    val timeBudget: Duration = 1500.milliseconds,
    val maxDepth: Int = 64,
    val tieBreakSeed: ULong? = null,
)

/** 한 번의 탐색 결과. */
data class ChessAIDecision(
    val move: ChessMove,
    /** 센티폰(폰 한 개 = 100). **두는 쪽 시점**이다. */
    val score: Int,
    /** 끝까지 마친 가장 깊은 반복 심화 깊이. */
    val depth: Int,
    val nodes: Int,
    val elapsed: Duration,
) {
    /** 메이트 점수면 **몇 반수 뒤** 메이트인가(+ = 내가 이긴다, − = 내가 당한다). 아니면 null. */
    val mateInPlies: Int?
        get() = when {
            score >= ChessAIScore.mateThreshold -> ChessAIScore.mate - score
            score <= -ChessAIScore.mateThreshold -> -(ChessAIScore.mate + score)
            else -> null
        }
}

object ChessAI {
    /**
     * `position` 에서 차례인 쪽이 둘 최선의 수. 합법 수가 없거나 성립하지 않는 국면이면 null.
     * `repetitionCounts` 를 넘기면 **세 번째 반복이 되는 수를 무승부(0)로** 셈한다.
     */
    fun bestMove(
        position: ChessPosition,
        repetitionCounts: Map<String, Int> = emptyMap(),
        limits: ChessAISearchLimits = ChessAISearchLimits(),
        isCancelled: () -> Boolean = { false },
        timeSource: TimeSource = TimeSource.Monotonic,
    ): ChessMove? = decide(position, repetitionCounts, limits, isCancelled, timeSource)?.move

    /** [bestMove] 와 같은 탐색이지만 점수·깊이·노드·걸린 시간까지 낸다. */
    fun decide(
        position: ChessPosition,
        repetitionCounts: Map<String, Int> = emptyMap(),
        limits: ChessAISearchLimits = ChessAISearchLimits(),
        isCancelled: () -> Boolean = { false },
        timeSource: TimeSource = TimeSource.Monotonic,
    ): ChessAIDecision? {
        val engine = ChessEngine.create(position) ?: return null
        val search = ChessAISearch(engine, limits.timeBudget, isCancelled, timeSource)
        val depth = maxOf(1, limits.maxDepth)
        val seed = limits.tieBreakSeed
        val rng: SwiftRandomSource = if (seed != null) SeededSwiftRandom(seed) else SystemSwiftRandom
        return search.decide(depth, repetitionCounts, rng)
    }
}

// MARK: - 점수 눈금

internal object ChessAIScore {
    /** 0 반수 메이트의 절댓값. `mate - ply` 로 거리를 담는다. */
    const val mate = 32_000
    const val mateThreshold = mate - 1_000
    const val infinity = 1 shl 20
    /** 센티폰 기물 가치(ChessCode 순서: 빈칸 · 폰 · 나이트 · 비숍 · 룩 · 퀸 · 왕). */
    val piece: IntArray = intArrayOf(0, 100, 320, 330, 500, 900, 20_000)
}

// MARK: - 표(칸 가치 · Zobrist)

/** 칸 가치표와 Zobrist 키. 표는 **보이는 대로**(위가 8랭크) 적고 한 번만 뒤집어 칸 번호(a1 = 0)로 옮긴다. */
internal object ChessAITables {
    /** 중반 표(폰·나이트·비숍·룩·퀸·왕). 색인은 `ChessCode` 의 말 종류 - 1. */
    val midgame: Array<IntArray> = arrayOf(
        flip(
            intArrayOf(
                0, 0, 0, 0, 0, 0, 0, 0,
                50, 50, 50, 50, 50, 50, 50, 50,
                10, 10, 20, 30, 30, 20, 10, 10,
                5, 5, 10, 25, 25, 10, 5, 5,
                0, 0, 0, 20, 20, 0, 0, 0,
                5, -5, -10, 0, 0, -10, -5, 5,
                5, 10, 10, -20, -20, 10, 10, 5,
                0, 0, 0, 0, 0, 0, 0, 0,
            ),
        ),
        flip(
            intArrayOf(
                -50, -40, -30, -30, -30, -30, -40, -50,
                -40, -20, 0, 0, 0, 0, -20, -40,
                -30, 0, 10, 15, 15, 10, 0, -30,
                -30, 5, 15, 20, 20, 15, 5, -30,
                -30, 0, 15, 20, 20, 15, 0, -30,
                -30, 5, 10, 15, 15, 10, 5, -30,
                -40, -20, 0, 5, 5, 0, -20, -40,
                -50, -40, -30, -30, -30, -30, -40, -50,
            ),
        ),
        flip(
            intArrayOf(
                -20, -10, -10, -10, -10, -10, -10, -20,
                -10, 0, 0, 0, 0, 0, 0, -10,
                -10, 0, 5, 10, 10, 5, 0, -10,
                -10, 5, 5, 10, 10, 5, 5, -10,
                -10, 0, 10, 10, 10, 10, 0, -10,
                -10, 10, 10, 10, 10, 10, 10, -10,
                -10, 5, 0, 0, 0, 0, 5, -10,
                -20, -10, -10, -10, -10, -10, -10, -20,
            ),
        ),
        flip(
            intArrayOf(
                0, 0, 0, 0, 0, 0, 0, 0,
                5, 10, 10, 10, 10, 10, 10, 5,
                -5, 0, 0, 0, 0, 0, 0, -5,
                -5, 0, 0, 0, 0, 0, 0, -5,
                -5, 0, 0, 0, 0, 0, 0, -5,
                -5, 0, 0, 0, 0, 0, 0, -5,
                -5, 0, 0, 0, 0, 0, 0, -5,
                0, 0, 5, 5, 5, 5, 0, 0,
            ),
        ),
        flip(
            intArrayOf(
                -20, -10, -10, -5, -5, -10, -10, -20,
                -10, 0, 0, 0, 0, 0, 0, -10,
                -10, 0, 5, 5, 5, 5, 0, -10,
                -5, 0, 5, 5, 5, 5, 0, -5,
                0, 0, 5, 5, 5, 5, 0, -5,
                -10, 5, 5, 5, 5, 5, 0, -10,
                -10, 0, 5, 0, 0, 0, 0, -10,
                -20, -10, -10, -5, -5, -10, -10, -20,
            ),
        ),
        flip(
            intArrayOf(
                -30, -40, -40, -50, -50, -40, -40, -30,
                -30, -40, -40, -50, -50, -40, -40, -30,
                -30, -40, -40, -50, -50, -40, -40, -30,
                -30, -40, -40, -50, -50, -40, -40, -30,
                -20, -30, -30, -40, -40, -30, -30, -20,
                -10, -20, -20, -20, -20, -20, -20, -10,
                20, 20, 0, 0, 0, 0, 20, 20,
                20, 30, 10, 0, 0, 10, 30, 20,
            ),
        ),
    )

    /** 끝내기 표. 폰과 왕만 중반과 다르다(폰은 밀어야 하고, 왕은 중앙으로 걸어 나와야 한다). */
    val endgame: Array<IntArray> = arrayOf(
        flip(
            intArrayOf(
                0, 0, 0, 0, 0, 0, 0, 0,
                90, 90, 90, 90, 90, 90, 90, 90,
                55, 55, 55, 55, 55, 55, 55, 55,
                30, 30, 30, 30, 30, 30, 30, 30,
                15, 15, 15, 15, 15, 15, 15, 15,
                5, 5, 5, 5, 5, 5, 5, 5,
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0,
            ),
        ),
        midgame[1],
        midgame[2],
        midgame[3],
        midgame[4],
        flip(
            intArrayOf(
                -50, -40, -30, -20, -20, -30, -40, -50,
                -30, -20, -10, 0, 0, -10, -20, -30,
                -30, -10, 20, 30, 30, 20, -10, -30,
                -30, -10, 30, 40, 40, 30, -10, -30,
                -30, -10, 30, 40, 40, 30, -10, -30,
                -30, -10, 20, 30, 30, 20, -10, -30,
                -30, -30, 0, 0, 0, 0, -30, -30,
                -50, -30, -30, -30, -30, -30, -30, -50,
            ),
        ),
    )

    /** 보이는 순서(8랭크 먼저)를 칸 번호(a1 = 0)로 옮긴다. */
    private fun flip(visual: IntArray): IntArray = IntArray(64) { square ->
        val file = square and 7
        val rank = square shr 3
        visual[(7 - rank) * 8 + file]
    }

    /** 말·칸 키 16×64 + 캐슬링 권리 16 + 앙파상 파일 8 + 차례 1. 씨앗("chessAI!")을 박아 **둘 때마다 같은 표**다. */
    val zobristPieces: LongArray
    val zobristCastling: LongArray
    val zobristEnPassant: LongArray
    val zobristSide: Long

    init {
        val rng = SplitMix64(0x6368_6573_7341_4921uL)
        zobristPieces = LongArray(16 * 64) { rng.next().toLong() }
        zobristCastling = LongArray(16) { rng.next().toLong() }
        zobristEnPassant = LongArray(8) { rng.next().toLong() }
        zobristSide = rng.next().toLong()
    }
}

// MARK: - 탐색

/** [ChessAISearch.generateLegal] 의 결과(Swift 튜플 `(start, count, inCheck)`). */
private class ChessGenerated(val start: Int, val count: Int, val inCheck: Boolean)

/** 두기 전 상태(Swift 튜플 `(undo, hash)`). */
internal class ChessAIMoveState(val undo: ChessUndo, val hash: Long)

internal class ChessAISearch(
    engine: ChessEngine,
    private val budget: Duration,
    private val isCancelled: () -> Boolean,
    timeSource: TimeSource = TimeSource.Monotonic,
) {
    var engine: ChessEngine = engine
        private set

    // 시간·취소
    private val started: TimeMark = timeSource.markNow()
    /** 마감 = 예산 − 여유(틱 간격 + 루트 마무리). 여유는 예산/50 과 20ms 중 작은 쪽. */
    private val deadline: Duration = budget - minOf(budget / 50, 20.milliseconds)
    var aborted = false
        private set
    var nodes = 0
        private set

    // 수 버퍼: ply 마다 창 하나.
    private val moveStack = ArrayList<ChessRawMove>(maxPly * 128)
    private val scores = IntArray(maxPly * maxMoves)
    private val killers = Array(maxPly * 2) { noMove }
    private val history = IntArray(16 * 64)
    private val ttKey = LongArray(1 shl ttBits)
    private val ttScore = IntArray(1 shl ttBits)
    private val ttDepth = IntArray(1 shl ttBits) { -1 }
    /** 1 정확 · 2 아래 경계(베타 끊기) · 3 위 경계(알파에 못 미침). */
    private val ttFlag = ByteArray(1 shl ttBits)
    private val ttFrom = IntArray(1 shl ttBits) { -1 }
    private val ttTo = IntArray(1 shl ttBits) { -1 }
    private val ttPromotion = IntArray(1 shl ttBits)
    private val ttMask = (1 shl ttBits) - 1
    private val pawnFiles = IntArray(16)
    private val pieceCounts = IntArray(12)
    private val midgameTable = IntArray(6 * 64)
    private val endgameTable = IntArray(6 * 64)
    private val pieceValue = IntArray(7)

    /** 뿌리에서 지금까지 거쳐 온 국면 해시(경로 반복 판정). */
    private val hashPath = ArrayList<Long>(maxPly)
    var hash: Long = 0L
        private set

    init {
        for (kind in 0 until 6) {
            for (square in 0 until 64) {
                midgameTable[kind * 64 + square] = ChessAITables.midgame[kind][square]
                endgameTable[kind * 64 + square] = ChessAITables.endgame[kind][square]
            }
        }
        for (kind in 0 until 7) pieceValue[kind] = ChessAIScore.piece[kind]
        hash = fullHash(engine)
    }

    // MARK: 해시

    /** 두고 나서 해시를 증분 갱신한다. `piece` 는 **두기 전**의 말 코드. 앙파상 칸은 늘 넣는다(과하게 갈라도 손해가 적다). */
    private fun updateHash(piece: Int, undo: ChessUndo) {
        val move = undo.move
        hash = hash xor ChessAITables.zobristPieces[piece * 64 + move.from]
        val placed = if (move.promotion == 0) piece else (move.promotion or (piece and ChessCode.blackBit))
        hash = hash xor ChessAITables.zobristPieces[placed * 64 + move.to]
        if (undo.captured != ChessCode.empty) hash = hash xor ChessAITables.zobristPieces[undo.captured * 64 + undo.capturedSquare]
        if (undo.rookFrom >= 0) {
            val rook = engine.cells[undo.rookTo].toInt()
            hash = hash xor ChessAITables.zobristPieces[rook * 64 + undo.rookFrom]
            hash = hash xor ChessAITables.zobristPieces[rook * 64 + undo.rookTo]
        }
        hash = hash xor ChessAITables.zobristCastling[undo.castling and 15]
        hash = hash xor ChessAITables.zobristCastling[engine.castling and 15]
        if (undo.enPassant >= 0) hash = hash xor ChessAITables.zobristEnPassant[undo.enPassant and 7]
        if (engine.enPassant >= 0) hash = hash xor ChessAITables.zobristEnPassant[engine.enPassant and 7]
        hash = hash xor ChessAITables.zobristSide
    }

    /** 두고 해시·경로를 함께 민다. 되돌리기는 [undoMove]. 증분 해시 대조 시험이 여기를 직접 부른다. */
    fun makeMove(move: ChessRawMove): ChessAIMoveState {
        val piece = engine.cells[move.from].toInt()
        val before = hash
        hashPath.add(before)
        val undo = engine.make(move)
        updateHash(piece, undo)
        return ChessAIMoveState(undo, before)
    }

    fun undoMove(state: ChessAIMoveState) {
        engine.unmake(state.undo)
        hashPath.removeAt(hashPath.size - 1)
        hash = state.hash
    }

    // MARK: 시간

    private fun tick() {
        nodes += 1
        if (nodes and 511 == 0 && !aborted) {
            if (started.elapsedNow() >= deadline || isCancelled()) aborted = true
        }
    }

    private fun checkAbortNow(): Boolean {
        if (!aborted && (started.elapsedNow() >= deadline || isCancelled())) aborted = true
        return aborted
    }

    private val elapsed: Duration get() = started.elapsedNow()

    private val elapsedFraction: Double
        get() {
            val total = budget.inWholeNanoseconds.toDouble()
            return if (total > 0) elapsed.inWholeNanoseconds.toDouble() / total else 1.0
        }

    // MARK: 평가

    /** 두는 쪽 시점의 센티폰 점수. 기물 + 칸 가치표(중반↔끝내기 보간) + 폰 구조 + 왕 안전 + 비숍 한 쌍 + 몰기. */
    fun evaluate(): Int {
        var midgame = 0
        var endgame = 0
        var phase = 0
        pawnFiles.fill(0)
        pieceCounts.fill(0)

        val cells = engine.cells
        for (square in 0 until 64) {
            val cell = cells[square].toInt()
            if (cell == ChessCode.empty) continue
            val kind = cell and ChessCode.kindMask
            val isBlack = (cell and ChessCode.blackBit) != 0
            val colorIndex = if (isBlack) 1 else 0
            pieceCounts[colorIndex * 6 + kind - 1] += 1
            // 흑은 같은 표를 위아래로 뒤집어 읽는다(칸 번호 ^ 56 = 랭크 반사).
            val view = if (isBlack) square xor 56 else square
            val material = pieceValue[kind]
            val mid = material + midgameTable[(kind - 1) * 64 + view]
            val end = material + endgameTable[(kind - 1) * 64 + view]
            if (isBlack) {
                midgame -= mid
                endgame -= end
            } else {
                midgame += mid
                endgame += end
            }
            if (kind == ChessCode.pawn) pawnFiles[colorIndex * 8 + (square and 7)] += 1
            when (kind) {
                ChessCode.knight, ChessCode.bishop -> phase += 1
                ChessCode.rook -> phase += 2
                ChessCode.queen -> phase += 4
                else -> Unit
            }
        }

        // 사국 중 가장 흔한 둘(맨 왕 · 작은 말 하나)은 탐색 안에서 바로 0 으로 접는다.
        val pawns = pieceCounts[0] + pieceCounts[6]
        val heavy = pieceCounts[3] + pieceCounts[4] + pieceCounts[9] + pieceCounts[10]
        val minors = pieceCounts[1] + pieceCounts[2] + pieceCounts[7] + pieceCounts[8]
        if (pawns == 0 && heavy == 0 && minors <= 1) return 0

        for (colorIndex in 0 until 2) {
            var structure = 0
            for (file in 0 until 8) {
                val count = pawnFiles[colorIndex * 8 + file]
                if (count <= 0) continue
                // 이중 폰: 같은 파일의 둘째부터 벌점.
                if (count > 1) structure -= (count - 1) * 18
                val left = if (file > 0) pawnFiles[colorIndex * 8 + file - 1] else 0
                val right = if (file < 7) pawnFiles[colorIndex * 8 + file + 1] else 0
                // 고립 폰: 옆 파일에 같은 색 폰이 없다.
                if (left == 0 && right == 0) structure -= 14 * count
            }
            if (pieceCounts[colorIndex * 6 + ChessCode.bishop - 1] >= 2) structure += 30
            if (colorIndex == 0) {
                midgame += structure
                endgame += structure
            } else {
                midgame -= structure
                endgame -= structure
            }
        }

        // 왕 안전(중반만).
        for (colorIndex in 0 until 2) {
            val shield = pawnShield(colorIndex)
            midgame += if (colorIndex == 0) shield else -shield
        }

        // 몰기: 한쪽이 **왕만** 남았으면 상대 왕을 변·구석으로 밀고 내 왕을 붙인다.
        val whiteForce = pieceCounts[0] + pieceCounts[1] + pieceCounts[2] + pieceCounts[3] + pieceCounts[4]
        val blackForce = pieceCounts[6] + pieceCounts[7] + pieceCounts[8] + pieceCounts[9] + pieceCounts[10]
        if (whiteForce > 0 && blackForce == 0) {
            val mop = mopUp(0, 1)
            midgame += mop
            endgame += mop
        } else if (blackForce > 0 && whiteForce == 0) {
            val mop = mopUp(1, 0)
            midgame -= mop
            endgame -= mop
        }

        val clamped = minOf(phase, 24)
        var score = (midgame * clamped + endgame * (24 - clamped)) / 24
        if (engine.side == 1) score = -score
        return score
    }

    /** 몰기 점수(이긴 쪽 시점, 늘 0 이상). 변까지의 거리 + 두 왕 사이 거리. */
    private fun mopUp(strong: Int, weak: Int): Int {
        val weakSquare = engine.kings[weak]
        val strongSquare = engine.kings[strong]
        val weakFile = weakSquare and 7
        val weakRank = weakSquare shr 3
        val edge = (3 - minOf(weakFile, 7 - weakFile)) + (3 - minOf(weakRank, 7 - weakRank))
        val distance = abs(weakFile - (strongSquare and 7)) + abs(weakRank - (strongSquare shr 3))
        return 12 * edge + 6 * (14 - distance)
    }

    private fun pawnShield(colorIndex: Int): Int {
        val kingSquare = engine.kings[colorIndex]
        val kingFile = kingSquare and 7
        val kingRank = kingSquare shr 3
        val wanted = ChessCode.pawn or (if (colorIndex == 1) ChessCode.blackBit else 0)
        var shield = 0
        for (file in maxOf(0, kingFile - 1)..minOf(7, kingFile + 1)) {
            var found = false
            for (step in 1..2) {
                val rank = if (colorIndex == 0) kingRank + step else kingRank - step
                if (rank < 0 || rank >= 8) break
                if (engine.cells[rank * 8 + file].toInt() == wanted) {
                    shield += if (step == 1) 10 else 5
                    found = true
                    break
                }
            }
            // 폰이 하나도 없는 파일은 상대 룩·퀸이 바로 들어오는 길이다.
            if (!found) shield -= 12
        }
        return shield
    }

    // MARK: 수 생성 · 정렬

    /** 이 ply 의 합법 수를 버퍼 창에 담는다. `capturesOnly` 면 잡기·퀸 승격만(정지 탐색). 체크일 때는 부르는 쪽이 false 로 부른다. */
    private fun generateLegal(capturesOnly: Boolean): ChessGenerated {
        val start = moveStack.size
        engine.generate(moveStack)
        val end = moveStack.size
        val moverIndex = engine.side
        val kingSquare = engine.kings[moverIndex]
        val byBlack = moverIndex == 0
        val inCheck = engine.isAttacked(kingSquare, byBlack)
        val pins = engine.pinnedMask(kingSquare, moverIndex == 1)
        var write = start
        var index = start
        while (index < end) {
            val move = moveStack[index]
            index += 1
            if (capturesOnly) {
                val isCapture = engine.cells[move.to].toInt() != ChessCode.empty || move.flags and ChessRawMove.enPassant != 0
                if (!(isCapture || move.promotion == ChessCode.queen)) continue
            }
            if (engine.needsKingSafetyCheck(move, kingSquare, pins, inCheck)) {
                val undo = engine.make(move)
                val safe = !engine.isAttacked(engine.kings[moverIndex], byBlack)
                engine.unmake(undo)
                if (!safe) continue
            }
            moveStack[write] = move
            write += 1
        }
        moveStack.subList(write, end).clear()
        return ChessGenerated(start, write - start, inCheck)
    }

    private fun popMoves(count: Int) {
        if (count > 0) moveStack.subList(moveStack.size - count, moveStack.size).clear()
    }

    /** 창에 담긴 수에 정렬 점수를 매긴다: 치환표 수 → 잡기·승격(MVV-LVA) → 킬러 두 개 → 이력. */
    private fun scoreMoves(start: Int, count: Int, ply: Int, ttMove: ChessRawMove) {
        val base = ply * maxMoves
        for (offset in 0 until count) {
            val move = moveStack[start + offset]
            val score: Int
            if (move.from == ttMove.from && move.to == ttMove.to && move.promotion == ttMove.promotion) {
                score = 1 shl 30
            } else {
                val victim = engine.cells[move.to].toInt()
                val isEnPassant = move.flags and ChessRawMove.enPassant != 0
                if (victim != ChessCode.empty || isEnPassant || move.promotion != 0) {
                    val victimKind = if (isEnPassant) ChessCode.pawn else (victim and ChessCode.kindMask)
                    val attackerKind = engine.cells[move.from].toInt() and ChessCode.kindMask
                    val promotionBonus = if (move.promotion == 0) 0 else pieceValue[move.promotion] - 100
                    score = 1_000_000 + 100 * pieceValue[victimKind] - pieceValue[attackerKind] + promotionBonus
                } else if (move == killers[ply * 2]) {
                    score = 900_000
                } else if (move == killers[ply * 2 + 1]) {
                    score = 890_000
                } else {
                    val piece = engine.cells[move.from].toInt()
                    score = minOf(history[piece * 64 + move.to], 880_000)
                }
            }
            scores[base + offset] = score
        }
    }

    /** 남은 수 중 점수가 가장 큰 것을 `index` 자리로 끌어온다(선택 정렬 한 걸음). */
    private fun pickBest(start: Int, count: Int, index: Int, ply: Int) {
        val base = ply * maxMoves
        var bestOffset = index
        var bestScore = scores[base + index]
        var offset = index + 1
        while (offset < count) {
            if (scores[base + offset] > bestScore) {
                bestScore = scores[base + offset]
                bestOffset = offset
            }
            offset += 1
        }
        if (bestOffset == index) return
        val a = moveStack[start + index]
        moveStack[start + index] = moveStack[start + bestOffset]
        moveStack[start + bestOffset] = a
        scores[base + bestOffset] = scores[base + index]
        scores[base + index] = bestScore
    }

    // MARK: 무승부 규칙

    /** 지금 국면이 규칙으로 무승부인가(탐색 안쪽 전용). 경로 반복은 **한 번만 되돌아와도** 무승부로 본다. */
    private fun isDrawByRule(): Boolean {
        if (engine.halfmove >= 100) return true
        if (engine.halfmove < 4 || hashPath.size < 2) return false
        val limit = minOf(engine.halfmove, hashPath.size)
        var index = hashPath.size - 2
        var steps = 2
        while (index >= 0 && steps <= limit) {
            if (hashPath[index] == hash) return true
            index -= 2
            steps += 2
        }
        return false
    }

    /** 두는 쪽에 폰·왕 말고 다른 말이 있는가(널 무브를 걸러내는 조건). */
    private fun hasNonPawnMaterial(): Boolean {
        val me = if (engine.side == 0) 0 else ChessCode.blackBit
        for (square in 0 until 64) {
            val cell = engine.cells[square].toInt()
            if (cell == ChessCode.empty || (cell and ChessCode.blackBit) != me) continue
            val kind = cell and ChessCode.kindMask
            if (kind != ChessCode.pawn && kind != ChessCode.king) return true
        }
        return false
    }

    // MARK: 정지 탐색

    /** 잡기(와 퀸 승격)가 끝날 때까지만 더 보는 탐색. 체크면 그 자리에서 벗어나는 수를 전부 본다(깊이 한도 안에서). */
    private fun quiesce(alphaIn: Int, betaIn: Int, ply: Int, checkDepth: Int): Int {
        tick()
        if (aborted) return 0
        if (ply >= maxPly - 2) return evaluate()

        val moverIndex = engine.side
        val inCheck = engine.isAttacked(engine.kings[moverIndex], moverIndex == 0)
        val full = inCheck && checkDepth > 0
        var alpha = alphaIn
        var best = -ChessAIScore.infinity
        var standPat = 0
        if (!full) {
            standPat = evaluate()
            best = standPat
            if (best >= betaIn) return best
            if (best > alpha) alpha = best
        }

        val generated = generateLegal(capturesOnly = !full)
        try {
            if (generated.count == 0) {
                // 전부 보고도 수가 없으면 판정이다: 체크면 메이트, 아니면 스테일메이트(무승부).
                if (full) return -(ChessAIScore.mate - ply)
                return best
            }
            scoreMoves(generated.start, generated.count, ply, noMove)

            for (index in 0 until generated.count) {
                pickBest(generated.start, generated.count, index, ply)
                val move = moveStack[generated.start + index]
                if (!full) {
                    // 델타 가지치기: 잡아 봐야 알파에 한참 못 미치는 잡기는 보지 않는다.
                    val victim = if (move.flags and ChessRawMove.enPassant != 0) ChessCode.pawn
                    else (engine.cells[move.to].toInt() and ChessCode.kindMask)
                    val gain = pieceValue[victim] + (if (move.promotion == 0) 0 else 800)
                    if (standPat + gain + 200 < alpha) continue
                }
                val state = makeMove(move)
                val score = -quiesce(-betaIn, -alpha, ply + 1, if (full) checkDepth - 1 else checkDepth)
                undoMove(state)
                if (aborted) return 0
                if (score > best) {
                    best = score
                    if (score > alpha) {
                        alpha = score
                        if (alpha >= betaIn) break
                    }
                }
            }
            return best
        } finally {
            popMoves(generated.count)
        }
    }

    // MARK: 알파베타

    fun search(depthIn: Int, alphaIn: Int, betaIn: Int, ply: Int, allowNull: Boolean): Int {
        tick()
        if (aborted) return 0
        if (ply > 0 && isDrawByRule()) return 0
        if (ply >= maxPly - 2) return evaluate()

        val moverIndex = engine.side
        val inCheck = engine.isAttacked(engine.kings[moverIndex], moverIndex == 0)
        var depth = depthIn
        // 체크 중이면 한 수 더 본다(강제수다).
        if (inCheck && ply < 48) depth += 1
        if (depth <= 0) return quiesce(alphaIn, betaIn, ply, 4)

        var alpha = alphaIn
        var beta = betaIn
        val slot = hash.toInt() and ttMask
        var ttMove = noMove
        if (ttKey[slot] == hash) {
            ttMove = ChessRawMove(ttFrom[slot], ttTo[slot], ttPromotion[slot], 0)
            if (ttDepth[slot] >= depth && ply > 0) {
                val score = fromTT(ttScore[slot], ply)
                when (ttFlag[slot].toInt()) {
                    1 -> return score
                    2 -> alpha = maxOf(alpha, score)
                    3 -> beta = minOf(beta, score)
                    else -> Unit
                }
                if (alpha >= beta) return score
            }
        }

        // 널 무브: 한 수를 **거르고도** 베타를 넘으면 이 가지는 볼 필요가 없다(체크·폰만 남은 판에서는 쓰지 않는다).
        if (allowNull && !inCheck && ply > 0 && depth >= 3 && beta < ChessAIScore.mateThreshold && hasNonPawnMaterial()) {
            // 50수 카운터는 **건드리지 않는다**(널 무브는 실제로 둔 수가 아니다).
            val savedEnPassant = engine.enPassant
            val savedHash = hash
            hashPath.add(hash)
            engine.side = engine.side xor 1
            engine.enPassant = -1
            hash = hash xor ChessAITables.zobristSide
            if (savedEnPassant >= 0) hash = hash xor ChessAITables.zobristEnPassant[savedEnPassant and 7]
            val reduction = 2 + depth / 6
            val score = -search(depth - 1 - reduction, -beta, -beta + 1, ply + 1, false)
            engine.side = engine.side xor 1
            engine.enPassant = savedEnPassant
            hash = savedHash
            hashPath.removeAt(hashPath.size - 1)
            if (aborted) return 0
            if (score >= beta) return beta
        }

        val generated = generateLegal(capturesOnly = false)
        try {
            if (generated.count == 0) {
                // 수가 없다 → 체크면 메이트(거리로 점수화), 아니면 스테일메이트는 **무승부**다.
                return if (inCheck) -(ChessAIScore.mate - ply) else 0
            }
            scoreMoves(generated.start, generated.count, ply, ttMove)

            var best = -ChessAIScore.infinity
            var bestMove = noMove
            for (index in 0 until generated.count) {
                pickBest(generated.start, generated.count, index, ply)
                val move = moveStack[generated.start + index]
                val isCapture = engine.cells[move.to].toInt() != ChessCode.empty || move.flags and ChessRawMove.enPassant != 0
                val state = makeMove(move)
                var score: Int
                if (index == 0) {
                    score = -search(depth - 1, -beta, -alpha, ply + 1, true)
                } else {
                    // 늦은 수 줄이기: 정렬이 뒤로 보낸 조용한 수는 한 칸 얕게 본다. 알파를 넘으면 제 깊이로 다시 본다.
                    var reduction = 0
                    if (depth >= 3 && index >= 3 && !isCapture && !inCheck && move.promotion == 0) {
                        // 체크를 거는 수는 줄이지 않는다(강제수다).
                        val opponentIndex = engine.side
                        if (!engine.isAttacked(engine.kings[opponentIndex], opponentIndex == 0)) {
                            reduction = if (index >= 6) 2 else 1
                        }
                    }
                    score = -search(depth - 1 - reduction, -(alpha + 1), -alpha, ply + 1, true)
                    if (!aborted && score > alpha && reduction > 0) {
                        score = -search(depth - 1, -(alpha + 1), -alpha, ply + 1, true)
                    }
                    if (!aborted && score > alpha && score < beta) {
                        score = -search(depth - 1, -beta, -alpha, ply + 1, true)
                    }
                }
                undoMove(state)
                if (aborted) return 0
                if (score > best) {
                    best = score
                    bestMove = move
                    if (score > alpha) {
                        alpha = score
                        if (alpha >= beta) {
                            if (!isCapture) {
                                // 킬러·이력: 같은 깊이의 **다른 가지**에서도 같은 수가 끊는 일이 잦다.
                                if (killers[ply * 2] != move) {
                                    killers[ply * 2 + 1] = killers[ply * 2]
                                    killers[ply * 2] = move
                                }
                                val piece = engine.cells[move.from].toInt()
                                val bonus = depth * depth
                                val slotIndex = piece * 64 + move.to
                                history[slotIndex] = minOf(history[slotIndex] + bonus, 800_000)
                            }
                            break
                        }
                    }
                }
            }

            val flag = if (best >= betaIn) 2 else if (best <= alphaIn) 3 else 1
            if (ttKey[slot] != hash || ttDepth[slot] <= depth) {
                ttKey[slot] = hash
                ttScore[slot] = toTT(best, ply)
                ttDepth[slot] = depth.toShort().toInt()
                ttFlag[slot] = flag.toByte()
                ttFrom[slot] = bestMove.from.toByte().toInt()
                ttTo[slot] = bestMove.to.toByte().toInt()
                ttPromotion[slot] = bestMove.promotion
            }
            return best
        } finally {
            popMoves(generated.count)
        }
    }

    /** 메이트 점수는 치환표에 **그 국면에서의 거리**로 넣는다. */
    private fun toTT(score: Int, ply: Int): Int = when {
        score >= ChessAIScore.mateThreshold -> score + ply
        score <= -ChessAIScore.mateThreshold -> score - ply
        else -> score
    }

    private fun fromTT(score: Int, ply: Int): Int = when {
        score >= ChessAIScore.mateThreshold -> score - ply
        score <= -ChessAIScore.mateThreshold -> score + ply
        else -> score
    }

    // MARK: 뿌리

    fun decide(maxDepth: Int, repetitionCounts: Map<String, Int>, rng: SwiftRandomSource): ChessAIDecision? {
        val rootStart = moveStack.size
        try {
            val generated = generateLegal(capturesOnly = false)
            if (generated.count <= 0) return null

            var rootMoves: List<ChessRawMove> = (0 until generated.count).map { moveStack[generated.start + it] }
            // 둘 수 있는 수가 하나면 탐색할 것이 없다(점수·깊이는 0).
            if (rootMoves.size == 1) return ChessAIDecision(rootMoves[0].move, 0, 0, nodes, elapsed)

            // 세 번째 반복이 되는 수는 **무승부**다.
            val forcedDraw = HashSet<ChessRawMove>()
            if (repetitionCounts.isNotEmpty()) {
                for (move in rootMoves) {
                    val state = makeMove(move)
                    val key = engine.position.repetitionKey
                    undoMove(state)
                    if ((repetitionCounts[key] ?: 0) + 1 >= 3) forcedDraw.add(move)
                }
            }

            var bestMoves: List<ChessRawMove> = listOf(rootMoves[0])
            var bestScore = 0
            var completedDepth = 0
            var previous = IntArray(rootMoves.size)
            var depth = 1
            while (depth <= maxDepth) {
                var iterationBest = -ChessAIScore.infinity
                var iterationMoves = ArrayList<ChessRawMove>()
                val iterationScores = IntArray(rootMoves.size) { -ChessAIScore.infinity }
                for ((index, move) in rootMoves.withIndex()) {
                    if (move in forcedDraw) {
                        // 무승부는 탐색하지 않는다 — 값이 0 으로 정해져 있다.
                        iterationScores[index] = 0
                        if (0 > iterationBest) {
                            iterationBest = 0
                            iterationMoves = arrayListOf(move)
                        } else if (iterationBest == 0) {
                            iterationMoves.add(move)
                        }
                        continue
                    }
                    val state = makeMove(move)
                    var score: Int
                    var exact = true
                    if (iterationMoves.isEmpty()) {
                        score = -search(depth - 1, -ChessAIScore.infinity, ChessAIScore.infinity, 1, true)
                    } else {
                        score = -search(depth - 1, -(iterationBest + 1), -iterationBest, 1, true)
                        if (!aborted && score > iterationBest) {
                            // 좁은 창으로 "더 좋다"가 나오면 **전 창으로 다시** 본다.
                            score = -search(depth - 1, -ChessAIScore.infinity, ChessAIScore.infinity, 1, true)
                        } else {
                            exact = false
                        }
                    }
                    undoMove(state)
                    if (aborted) break
                    iterationScores[index] = score
                    if (exact && score > iterationBest) {
                        iterationBest = score
                        iterationMoves = arrayListOf(move)
                    } else if (exact && score == iterationBest) {
                        iterationMoves.add(move)
                    }
                }
                if (aborted || iterationMoves.isEmpty()) break
                completedDepth = depth
                bestScore = iterationBest
                bestMoves = iterationMoves
                previous = iterationScores
                // 다음 깊이는 좋은 수부터(안정 정렬).
                val snapshot = previous
                val order = rootMoves.indices.sortedWith { a, b -> compareDescending(snapshot[a], snapshot[b]) }
                rootMoves = order.map { rootMoves[it] }
                previous = IntArray(order.size) { snapshot[order[it]] }
                // 메이트가 확정되면 더 깊이 볼 것이 없다.
                if (abs(bestScore) >= ChessAIScore.mateThreshold) break
                if (checkAbortNow()) break
                if (elapsedFraction > 0.5) break
                depth += 1
            }

            val chosen = bestMoves.randomElement(rng) ?: rootMoves[0]
            return ChessAIDecision(chosen.move, bestScore, completedDepth, nodes, elapsed)
        } finally {
            if (moveStack.size > rootStart) moveStack.subList(rootStart, moveStack.size).clear()
        }
    }

    companion object {
        const val maxPly = 96
        /** 한 노드가 낼 수 있는 유사 합법 수의 넉넉한 상한. */
        const val maxMoves = 256
        const val ttBits = 18

        val noMove = ChessRawMove(0, 0, 0, 0)

        fun fullHash(engine: ChessEngine): Long {
            var value = 0L
            for (square in 0 until 64) {
                val cell = engine.cells[square].toInt()
                if (cell == ChessCode.empty) continue
                value = value xor ChessAITables.zobristPieces[cell * 64 + square]
            }
            value = value xor ChessAITables.zobristCastling[engine.castling and 15]
            if (engine.enPassant >= 0) value = value xor ChessAITables.zobristEnPassant[engine.enPassant and 7]
            if (engine.side == 1) value = value xor ChessAITables.zobristSide
            return value
        }
    }
}
