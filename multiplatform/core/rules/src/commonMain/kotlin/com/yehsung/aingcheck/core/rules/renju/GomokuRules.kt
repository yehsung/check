// 원본: Sources/CheckCore/GomokuRules.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.renju

// 1:1 오목(렌주룰, 15×15, 흑만 금수) 착수 판정 — 순수·결정적. Swift 원본의 머리 주석이 규범이다(rules.final.md D0~D7 · §4.2).
//
//  · 방향 순서 가로(1,0) → 세로(0,1) → /(1,1) → \(1,-1)
//  · 전환점 순서 +d 먼저, 그다음 −d
//  · 3 판정은 왼쪽부터 단락 평가(any), threes == 2 즉시 반환, 조기 종료
//  · 노드는 judgeBlack **진입마다 1**(루트 포함), nodes > 예산이 되는 순간 초과
// 이 순서가 바뀌면 판정은 같아도 **노드 수**가 달라지고, 그러면 서버(gomoku_judge)와 예산 초과 여부가 갈린다.
// 골든 `renju/cases`(코퍼스 91건, nodes 포함) · `renju/forbidden-points`(무작위 국면 칸마다 판정·노드)가 순서를 못 박는다.
//
// 재귀 중 판 상태(규범 A3): 재귀는 **조상 가상 돌을 모두 둔 판**에서 내려간다. 판을 제자리에서 고치고 돌아올 때 되돌린다.
// 5목 전환점은 무효(D-2): 전환점 판정이 win 이면 그 3은 진짜 3이 아니다 — 3 판정은 `== legal` 만 센다.
//
// Swift 와 다른 점(값 의미): Swift `GomokuBoard` 는 값 타입이라 대입이 복사다. Kotlin 은 참조라 **복사는 [GomokuBoard.copy]** 로만
// 한다 — 판정기(엔진)는 들어온 판의 칸을 언제나 복사해서 쓴다(호출자의 판을 고치지 않는다).

/** 돌 색. 흑 선공. 상수 이름 = Swift case 이름(C-X10), [rawValue] = Swift rawValue. */
enum class GomokuColor(val rawValue: String) {
    black("black"),
    white("white");

    val opponent: GomokuColor get() = if (this == black) white else black

    companion object {
        /** Swift `GomokuColor(rawValue:)` — 글자가 정확히 같을 때만(대소문자·공백 정규화 없음). */
        fun fromRawValue(raw: String): GomokuColor? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * x = 열 A..O(0…14, 왼→오), y = 행 1..15(0…14, 아래→위). 서버 board 인덱스 = y*15 + x.
 * 이 타입의 값은 **언제나 판 안**이다 — Swift 의 실패 가능 생성자 둘을 [at]·[fromNotation] 으로 옮겼다(범위 밖이면 null).
 */
class GomokuPoint private constructor(val x: Int, val y: Int) {
    /** "H8" 같은 표기. */
    val notation: String get() = "${('A'.code + x).toChar()}${y + 1}"

    override fun equals(other: Any?): Boolean = other is GomokuPoint && other.x == x && other.y == y
    override fun hashCode(): Int = y * GomokuBoard.size + x
    override fun toString(): String = notation

    companion object {
        /** Swift `GomokuPoint(x:y:)` — 범위 밖이면 null. */
        fun at(x: Int, y: Int): GomokuPoint? {
            if (x !in 0 until GomokuBoard.size || y !in 0 until GomokuBoard.size) return null
            return GomokuPoint(x, y)
        }

        /**
         * Swift `GomokuPoint(notation:)`. 정규형 `^[A-O]([1-9]|1[0-5])$` **만** 받는다(설계자 확정 D-3).
         * 소문자·0 채움·공백·전각 숫자는 모두 null. 스칼라(코드 포인트)를 직접 본다 — Swift 가 unicodeScalars 로 센다.
         */
        fun fromNotation(notation: String): GomokuPoint? {
            val scalars = codePoints(notation)
            if (scalars.size != 2 && scalars.size != 3) return null
            val column = scalars[0]
            if (column < 0x41 || column > 0x4F) return null // A…O
            val digits = scalars.subList(1, scalars.size)
            if (!digits.all { it in 0x30..0x39 }) return null
            if (digits.first() == 0x30) return null // 0 채움·"0" 금지
            var row = 0
            for (digit in digits) row = row * 10 + (digit - 0x30)
            if (row !in 1..GomokuBoard.size) return null
            return at(column - 0x41, row - 1)
        }

        private fun codePoints(text: String): List<Int> {
            val out = ArrayList<Int>(text.length)
            var i = 0
            while (i < text.length) {
                val cp = text.codePointAtCompat(i)
                out += cp
                i += if (cp >= 0x10000) 2 else 1
            }
            return out
        }
    }
}

/** 공용(commonMain) 코드 포인트 읽기 — 짝이 맞는 대리 쌍만 합친다(Swift unicodeScalars 와 같은 셈, 짝 없는 대리는 Swift 문자열에 올 수 없다). */
internal fun String.codePointAtCompat(index: Int): Int {
    val high = this[index]
    if (high.isHighSurrogate() && index + 1 < length) {
        val low = this[index + 1]
        if (low.isLowSurrogate()) return ((high.code - 0xD800) shl 10) + (low.code - 0xDC00) + 0x10000
    }
    return high.code
}

/** 흑 금수의 종류. [rawValue] 는 서버 `gomoku_judge` 의 반환 어휘와 **문자 그대로 같다**. */
enum class GomokuForbiddenReason(val rawValue: String) {
    doubleThree("forbidden-double-three"),
    doubleFour("forbidden-double-four"),
    overline("forbidden-overline"),
    budget("forbidden-budget");

    companion object {
        fun fromRawValue(raw: String): GomokuForbiddenReason? = entries.firstOrNull { it.rawValue == raw }

        /**
         * Swift `GomokuForbiddenReason(serverReason:)`. 판정 어휘 전체('forbidden-double-three')든 접두사를 뗀 값('double-three',
         * 'budget')이든 같은 사유로 읽는다. 모르는 값·null·빈 값은 null.
         * Swift 는 `trimmingCharacters(in: .whitespacesAndNewlines).lowercased()` — 앞뒤 공백 집합은 [isSwiftWhitespaceOrNewline]
         * (유니코드 White_Space + U+200B), 소문자는 유니코드 소문자(Kotlin `lowercase()` 도 유니코드다 — 이 어휘는 ASCII 라 결과가 같다).
         */
        fun fromServerReason(serverReason: String?): GomokuForbiddenReason? {
            if (serverReason == null) return null
            val raw = trimSwiftWhitespace(serverReason).lowercase()
            if (raw.isEmpty()) return null
            val full = if (raw.startsWith("forbidden-")) raw else "forbidden-$raw"
            return fromRawValue(full.replace("_", "-"))
        }

        private fun trimSwiftWhitespace(text: String): String {
            var start = 0
            var end = text.length
            while (start < end && isSwiftWhitespaceOrNewline(text[start].code)) start++
            while (end > start && isSwiftWhitespaceOrNewline(text[end - 1].code)) end--
            return text.substring(start, end)
        }
    }
}

/**
 * Foundation `CharacterSet.whitespacesAndNewlines` — 맥에서 U+0000…U+10FFFF 를 전수로 잰 집합(2026-10-28, Xcode 27 SDK):
 * U+0009…U+000D · U+0020 · U+0085 · U+00A0 · U+1680 · U+2000…U+200B · U+2028 · U+2029 · U+202F · U+205F · U+3000.
 * 유니코드 White_Space 와 다른 점은 **U+200B(폭 없는 공백)이 들어 있다**는 것 하나다(골든 renju/inputs reason-17 이 잰다).
 */
internal fun isSwiftWhitespaceOrNewline(code: Int): Boolean = when (code) {
    in 0x09..0x0D, 0x20, 0x85, 0xA0, 0x1680, in 0x2000..0x200B, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000 -> true
    else -> false
}

/** 판정 결과. Swift 연관값 열거 → sealed(C-X10). */
sealed interface GomokuJudgement {
    data object Legal : GomokuJudgement
    data object Win : GomokuJudgement
    data class Forbidden(val reason: GomokuForbiddenReason) : GomokuJudgement
    data object Occupied : GomokuJudgement
    data object OutOfRange : GomokuJudgement
}

/** 15×15 판. 칸 값은 0 빈칸 / 1 흑 / 2 백. Swift 값 타입 → Kotlin 은 [copy] 로 복사한다. */
class GomokuBoard private constructor(internal val cells: ByteArray) {
    constructor() : this(ByteArray(CELL_COUNT))

    fun copy(): GomokuBoard = GomokuBoard(cells.copyOf())

    operator fun get(point: GomokuPoint): GomokuColor? = when (cells[point.y * size + point.x].toInt()) {
        1 -> GomokuColor.black
        2 -> GomokuColor.white
        else -> null
    }

    operator fun set(point: GomokuPoint, color: GomokuColor?) {
        cells[point.y * size + point.x] = when (color) {
            GomokuColor.black -> 1
            GomokuColor.white -> 2
            null -> 0
        }
    }

    val stoneCount: Int get() = cells.count { it.toInt() != 0 }

    /** 서버 board 문자열(225자, '.', 'b', 'w'). */
    val serverString: String
        get() = buildString(CELL_COUNT) {
            for (cell in cells) append(
                when (cell.toInt()) {
                    1 -> 'b'
                    2 -> 'w'
                    else -> '.'
                },
            )
        }

    override fun equals(other: Any?): Boolean = other is GomokuBoard && other.cells.contentEquals(cells)
    override fun hashCode(): Int = cells.contentHashCode()
    override fun toString(): String = "GomokuBoard($serverString)"

    companion object {
        const val size: Int = 15
        const val cellCount: Int = size * size
        private const val CELL_COUNT = cellCount

        /**
         * Swift `GomokuBoard(serverString:)`: UTF-8 바이트가 정확히 225개이고 전부 '.'·'b'·'w' 일 때만. 하나라도 어긋나면 null —
         * 손상된 판을 "대충 읽어" 그리면 둘 수 없는 자리를 둘 수 있다고 보여 준다.
         */
        fun fromServerString(serverString: String): GomokuBoard? {
            val bytes = serverString.encodeToByteArray()
            if (bytes.size != CELL_COUNT) return null
            val cells = ByteArray(CELL_COUNT)
            for ((index, byte) in bytes.withIndex()) {
                cells[index] = when (byte.toInt()) {
                    '.'.code -> 0
                    'b'.code -> 1
                    'w'.code -> 2
                    else -> return null
                }
            }
            return GomokuBoard(cells)
        }
    }
}

object GomokuRules {
    /** 노드 예산(설계자 확정 D-1). **서버 gomoku_judge 와 같은 상수**여야 한다. */
    const val nodeBudget: Int = 10_000

    fun judge(board: GomokuBoard, point: GomokuPoint, color: GomokuColor): GomokuJudgement =
        judgeCounting(board, point, color, nodeBudget).judgement

    /**
     * 흑 차례 X 표시용: 빈칸 중 흑에게 금수(예산 초과 포함)인 칸. `budget` 은 앱에서는 언제나 [nodeBudget] 이다(작은 예산은 검증용).
     * Swift 는 사전(순서 없음)을 돌려준다 — Kotlin 은 칸 순서(y → x)대로 넣은 [LinkedHashMap] 이고 비교는 내용으로 한다.
     */
    fun forbiddenPoints(board: GomokuBoard, budget: Int = nodeBudget): Map<GomokuPoint, GomokuForbiddenReason> {
        val engine = RenjuEngine(board.cells.copyOf(), budget)
        val result = LinkedHashMap<GomokuPoint, GomokuForbiddenReason>()
        for (y in 0 until GomokuBoard.size) {
            for (x in 0 until GomokuBoard.size) {
                if (engine.cells[y * GomokuBoard.size + x].toInt() != 0) continue
                engine.nodes = 0
                val reason: GomokuForbiddenReason? = try {
                    when (engine.judgeBlack(x, y)) {
                        BlackVerdict.overline -> GomokuForbiddenReason.overline
                        BlackVerdict.doubleFour -> GomokuForbiddenReason.doubleFour
                        BlackVerdict.doubleThree -> GomokuForbiddenReason.doubleThree
                        BlackVerdict.win, BlackVerdict.legal -> null
                    }
                } catch (_: GomokuBudgetExceeded) {
                    GomokuForbiddenReason.budget
                }
                val point = GomokuPoint.at(x, y)
                if (reason != null && point != null) result[point] = reason
            }
        }
        return result
    }

    /** [judgeCounting] 의 결과(Swift 튜플 `(judgement, nodes)`). */
    data class Counted(val judgement: GomokuJudgement, val nodes: Int)

    /**
     * 판정 + 노드 수(§4.2 계수). `budget` null 이면 예산 없음(코퍼스 교차 검증 전용).
     * 예산을 넘으면 `Forbidden(budget)` 이고 nodes 는 초과가 확정된 순간의 값이다. 백은 노드 1. 이미 돌이 있으면 Occupied, nodes 0.
     */
    fun judgeCounting(board: GomokuBoard, point: GomokuPoint, color: GomokuColor, budget: Int?): Counted {
        if (board[point] != null) return Counted(GomokuJudgement.Occupied, 0)
        val engine = RenjuEngine(board.cells.copyOf(), budget)
        return when (color) {
            GomokuColor.white -> Counted(engine.judgeWhite(point.x, point.y), 1)
            GomokuColor.black -> try {
                val verdict = engine.judgeBlack(point.x, point.y)
                Counted(verdict.judgement, engine.nodes)
            } catch (_: GomokuBudgetExceeded) {
                Counted(GomokuJudgement.Forbidden(GomokuForbiddenReason.budget), engine.nodes)
            }
        }
    }
}

// MARK: - 엔진 (§4.2 의사코드 그대로)

/** Swift `throws(GomokuBudgetExceeded)` — 재귀를 한 번에 빠져나오는 데만 쓴다(예산 초과는 드물다). */
private class GomokuBudgetExceeded : RuntimeException()

private enum class BlackVerdict {
    win, overline, doubleFour, doubleThree, legal;

    val judgement: GomokuJudgement
        get() = when (this) {
            win -> GomokuJudgement.Win
            legal -> GomokuJudgement.Legal
            overline -> GomokuJudgement.Forbidden(GomokuForbiddenReason.overline)
            doubleFour -> GomokuJudgement.Forbidden(GomokuForbiddenReason.doubleFour)
            doubleThree -> GomokuJudgement.Forbidden(GomokuForbiddenReason.doubleThree)
        }
}

/** 판정기. [cells] 는 **이 엔진만의 사본**이다(부르는 쪽이 복사해 넘긴다). */
private class RenjuEngine(val cells: ByteArray, val budget: Int?) {
    var nodes = 0

    fun at(x: Int, y: Int): Int {
        if (x < 0 || x >= N || y < 0 || y >= N) return OFF
        return cells[y * N + x].toInt()
    }

    /** D0: (x,y)를 지나는 `color` 연속 수(p 포함, p 는 이미 그 색으로 놓여 있다). */
    fun run(x: Int, y: Int, dx: Int, dy: Int, color: Int): Int {
        var count = 1
        var k = 1
        while (at(x + k * dx, y + k * dy) == color) { count += 1; k += 1 }
        k = 1
        while (at(x - k * dx, y - k * dy) == color) { count += 1; k += 1 }
        return count
    }

    /** D3: p 를 포함하는 5칸 창 가운데 '흑 4 + 빈칸 1, 창 바로 바깥 두 칸이 흑 아님'인 창의 서로 다른 흑돌 집합 개수. */
    fun countFours(x: Int, y: Int, dx: Int, dy: Int): Int {
        val masks = ArrayList<Int>(2)
        for (s in -4..0) {
            var blacks = 0
            var empties = 0
            var mask = 0
            var inside = true
            for (k in 0 until 5) {
                val offset = s + k
                val value = at(x + offset * dx, y + offset * dy)
                if (value == OFF) { inside = false; break }
                if (value == BLACK) {
                    blacks += 1
                    mask = mask or (1 shl (offset + 4))
                } else if (value == EMPTY) {
                    empties += 1
                }
            }
            if (!(inside && blacks == 4 && empties == 1)) continue
            if (at(x + (s - 1) * dx, y + (s - 1) * dy) == BLACK) continue
            if (at(x + (s + 5) * dx, y + (s + 5) * dy) == BLACK) continue
            if (!masks.contains(mask)) masks.add(mask)
        }
        return masks.size
    }

    /** 열린 4 판정 — d 줄 안에서만 본다(A7). */
    fun isStraightFour(x: Int, y: Int, dx: Int, dy: Int): Boolean {
        var i = 1
        while (at(x + i * dx, y + i * dy) == BLACK) i += 1
        var j = 1
        while (at(x - j * dx, y - j * dy) == BLACK) j += 1
        return i + j - 1 == 4 &&
            at(x + i * dx, y + i * dy) == EMPTY &&
            at(x - j * dx, y - j * dy) == EMPTY &&
            at(x + (i + 1) * dx, y + (i + 1) * dy) != BLACK &&
            at(x - (j + 1) * dx, y - (j + 1) * dy) != BLACK
    }

    /** D4: 전환점 후보 중 두면 p 를 지나는 열린 4가 되는 점. 순서는 **+d 먼저**(규범). 점은 y*N + x 로 담는다. */
    fun straightFourPoints(x: Int, y: Int, dx: Int, dy: Int): IntArray {
        var out = IntArray(0)
        for (sign in SIGNS) {
            var k = 1
            while (at(x + sign * k * dx, y + sign * k * dy) == BLACK) k += 1
            val qx = x + sign * k * dx
            val qy = y + sign * k * dy
            if (at(qx, qy) != EMPTY) continue
            val index = qy * N + qx
            cells[index] = BLACK.toByte()
            if (isStraightFour(x, y, dx, dy)) out += index
            cells[index] = EMPTY.toByte()
        }
        return out
    }

    /** D6 흑의 판정. (x,y)는 빈칸이고, 판에는 조상 가상 돌이 모두 있다. */
    fun judgeBlack(x: Int, y: Int): BlackVerdict {
        nodes += 1
        if (budget != null && nodes > budget) throw GomokuBudgetExceeded()
        val index = y * N + x
        cells[index] = BLACK.toByte()
        try {
            val runs = IntArray(4) { run(x, y, DIRECTIONS[it][0], DIRECTIONS[it][1], BLACK) }
            if (runs.contains(5)) return BlackVerdict.win
            if (runs.any { it >= 6 }) return BlackVerdict.overline

            val fours = IntArray(4) { countFours(x, y, DIRECTIONS[it][0], DIRECTIONS[it][1]) }
            if (fours.sum() >= 2) return BlackVerdict.doubleFour

            val shaped = ArrayList<IntArray>(4)
            for (d in 0 until 4) {
                if (fours[d] != 0) continue
                val points = straightFourPoints(x, y, DIRECTIONS[d][0], DIRECTIONS[d][1])
                if (points.isNotEmpty()) shaped.add(points)
            }
            if (shaped.size < 2) return BlackVerdict.legal

            var threes = 0
            for ((i, points) in shaped.withIndex()) {
                var valid = false
                for (q in points) {
                    if (judgeBlack(q % N, q / N) == BlackVerdict.legal) {
                        valid = true
                        break
                    }
                }
                if (valid) {
                    threes += 1
                    if (threes == 2) return BlackVerdict.doubleThree
                }
                if (threes + (shaped.size - i - 1) < 2) return BlackVerdict.legal
            }
            return BlackVerdict.legal
        } finally {
            cells[index] = EMPTY.toByte()
        }
    }

    /** D7 백의 판정. 금수 없음, 5 이상이면 승리. */
    fun judgeWhite(x: Int, y: Int): GomokuJudgement {
        val index = y * N + x
        cells[index] = WHITE.toByte()
        try {
            for (direction in DIRECTIONS) {
                if (run(x, y, direction[0], direction[1], WHITE) >= 5) return GomokuJudgement.Win
            }
            return GomokuJudgement.Legal
        } finally {
            cells[index] = EMPTY.toByte()
        }
    }

    companion object {
        const val EMPTY = 0
        const val BLACK = 1
        const val WHITE = 2
        /** 판 밖. 흑의 판정에서 백돌과 똑같이 '막힘'이다. */
        const val OFF = 3
        /** 규범 순서: 가로, 세로, /, \. */
        val DIRECTIONS: Array<IntArray> = arrayOf(intArrayOf(1, 0), intArrayOf(0, 1), intArrayOf(1, 1), intArrayOf(1, -1))
        val SIGNS: IntArray = intArrayOf(1, -1)
        const val N = GomokuBoard.size
    }
}

// MARK: - AI 엔진용 도우미 (docs/plan/gomoku-ai.md §2)
//
// 엔진은 탐색 중 흑 후보가 금수인지 수만 번 묻는다. 엔진이 들고 있는 판과 **같은 판정기**를 제자리에서 고쳐 가며 묻는 문.
// 판정 자체는 위 `RenjuEngine.judgeBlack` 그대로라 순서·노드 계수·예산(10,000)이 한 벌이다.

/** 제자리에서 고쳐 쓰는 흑 판정기. 판 좌표는 [GomokuBoard] 와 같다. Swift 값 타입 → Kotlin 은 [copy] 로 복사한다. */
class GomokuRenjuProbe private constructor(private val engine: RenjuEngine) {
    constructor(board: GomokuBoard) : this(RenjuEngine(board.cells.copyOf(), GomokuRules.nodeBudget))

    fun copy(): GomokuRenjuProbe = GomokuRenjuProbe(RenjuEngine(engine.cells.copyOf(), GomokuRules.nodeBudget))

    /** 칸 하나를 바꾼다(엔진의 착수·되돌리기와 짝을 맞춘다). */
    fun setCell(x: Int, y: Int, color: GomokuColor?) {
        engine.cells[y * GomokuBoard.size + x] = when (color) {
            GomokuColor.black -> RenjuEngine.BLACK.toByte()
            GomokuColor.white -> RenjuEngine.WHITE.toByte()
            null -> RenjuEngine.EMPTY.toByte()
        }
    }

    /** 빈칸 (x, y) 에 흑이 두면? `GomokuRules.judge(board, point, black)` 와 같은 값(빈칸이 아니면 Occupied). */
    fun blackJudgement(x: Int, y: Int): GomokuJudgement {
        if (engine.cells[y * GomokuBoard.size + x].toInt() != RenjuEngine.EMPTY) return GomokuJudgement.Occupied
        engine.nodes = 0
        return try {
            engine.judgeBlack(x, y).judgement
        } catch (_: GomokuBudgetExceeded) {
            GomokuJudgement.Forbidden(GomokuForbiddenReason.budget)
        }
    }
}
