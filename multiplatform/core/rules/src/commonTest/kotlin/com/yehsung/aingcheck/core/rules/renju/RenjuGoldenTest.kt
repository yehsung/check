// 원본: Tests/checkTests/GoldenExport/games-board/GoldenExportGamesBoardRenju.swift(골든 생성기) · Tests/checkTests/V0327GomokuRulesTests.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.renju

import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * 렌주 판정이 Swift 와 비트로 같다(C§5.1 E7 — 판정과 **노드 수**). 노드 수가 같아야 서버 gomoku_judge 와 예산 초과 여부가 같다.
 *  · renju/cases            코퍼스 91건(입력 검증 · 판정 · 노드 수)
 *  · renju/forbidden-points 무작위 국면 칸마다(흑 판정·노드 · 백 판정 · 금수 표시 목록, 작은 예산 판 포함)
 *  · renju/inputs           좌표 · 색 · 서버 금수 사유 · 서버 판 문자열 · 차례 경고 표
 */
class RenjuGoldenTest {
    private fun mismatch(golden: GoldenFile, case: JsonObject, detail: String): Nothing = fail(golden.failure(case.string("id"), detail))

    private fun label(judgement: GomokuJudgement): String = when (judgement) {
        GomokuJudgement.Legal -> "legal"
        GomokuJudgement.Win -> "win"
        is GomokuJudgement.Forbidden -> judgement.reason.rawValue
        GomokuJudgement.Occupied -> "occupied"
        GomokuJudgement.OutOfRange -> "out-of-range"
    }

    private fun code(judgement: GomokuJudgement): Char = when (judgement) {
        GomokuJudgement.Legal -> 'L'
        GomokuJudgement.Win -> 'W'
        is GomokuJudgement.Forbidden -> when (judgement.reason) {
            GomokuForbiddenReason.doubleThree -> 'T'
            GomokuForbiddenReason.doubleFour -> 'F'
            GomokuForbiddenReason.overline -> 'O'
            GomokuForbiddenReason.budget -> 'B'
        }
        GomokuJudgement.Occupied, GomokuJudgement.OutOfRange -> '?'
    }

    /** 코퍼스 입력 → 앱 타입. 정규형 아닌 좌표·같은 칸 두 번·색 철자가 틀리면 null(V0327 corpusBoard 와 같은 검증). */
    private fun corpusBoard(black: List<String>, white: List<String>, player: String, point: String): Triple<GomokuBoard, GomokuColor, GomokuPoint>? {
        val color = GomokuColor.fromRawValue(player) ?: return null
        val board = GomokuBoard()
        for ((list, stone) in listOf(black to GomokuColor.black, white to GomokuColor.white)) {
            for (notation in list) {
                val target = GomokuPoint.fromNotation(notation) ?: return null
                if (board[target] != null) return null
                board[target] = stone
            }
        }
        val target = GomokuPoint.fromNotation(point) ?: return null
        return Triple(board, color, target)
    }

    @Test
    fun corpusJudgementsAndNodeCountsMatchSwift() {
        val golden = Golden.load("renju/cases")
        var judged = 0
        var multiNode = 0
        for (case in golden.cases) {
            val black = case.array("black").strings().map(::cpsText)
            val white = case.array("white").strings().map(::cpsText)
            val parsed = corpusBoard(black, white, cpsText(case.string("player")), cpsText(case.string("point")))
            if ((parsed != null) != case.bool("parsed")) mismatch(golden, case, "입력 검증: Kotlin parsed=${parsed != null}, Swift ${case.bool("parsed")}")
            if (parsed == null) continue
            val (board, color, target) = parsed
            val before = board.serverString
            val counted = GomokuRules.judgeCounting(board, target, color, case.int("budget"))
            assertEquals(before, board.serverString, "판정이 들어온 판을 고쳤다(${case.string("id")}) — 엔진은 사본을 써야 한다")
            if (label(counted.judgement) != case.optString("judgement")) {
                mismatch(golden, case, "판정 Kotlin ${label(counted.judgement)} · Swift ${case.optString("judgement")}")
            }
            if (counted.nodes != case.optInt("nodes")) mismatch(golden, case, "노드 Kotlin ${counted.nodes} · Swift ${case.optInt("nodes")} — §4.2 순서·계수")
            judged++
            if (counted.nodes > 1) multiNode++
        }
        assertEquals(91, golden.cases.size, "코퍼스 91건")
        assertTrue(judged >= 80, "판정을 대조한 건이 $judged 개뿐이다")
        assertTrue(multiNode >= 10, "재귀(노드 2 이상) 사례가 $multiNode 개뿐이다 — 순서 계약을 못 잰다")
    }

    @Test
    fun forbiddenPointsAndPerCellJudgementsMatchSwift() {
        val golden = Golden.load("renju/forbidden-points")
        var cells = 0
        val seen = HashMap<Char, Int>()
        for (case in golden.cases) {
            val board = GomokuBoard.fromServerString(case.string("board")) ?: mismatch(golden, case, "판 글자를 못 읽었다")
            val budget = case.int("budget")
            val swiftNodes = HashMap<Int, Int>()
            for (row in case.array("blackNodes")) {
                val pair = row.asArray()
                swiftNodes[pair[0].intValue()] = pair[1].intValue()
            }
            val black = StringBuilder()
            val white = StringBuilder()
            for (index in 0 until GomokuBoard.cellCount) {
                val point = GomokuPoint.at(index % GomokuBoard.size, index / GomokuBoard.size)!!
                if (board[point] != null) {
                    black.append('.'); white.append('.')
                    continue
                }
                val counted = GomokuRules.judgeCounting(board, point, GomokuColor.black, budget)
                val c = code(counted.judgement)
                black.append(c)
                seen[c] = (seen[c] ?: 0) + 1
                val want = swiftNodes[index] ?: 1
                if (counted.nodes != want) mismatch(golden, case, "${point.notation} 노드 Kotlin ${counted.nodes} · Swift $want")
                white.append(code(GomokuRules.judge(board, point, GomokuColor.white)))
                cells++
            }
            val wantBlack = case.string("black")
            if (black.toString() != wantBlack) {
                val at = black.indices.first { black[it] != wantBlack[it] }
                mismatch(golden, case, "흑 판정 첫 불일치 ${GomokuPoint.at(at % 15, at / 15)} Kotlin ${black[at]} · Swift ${wantBlack[at]}")
            }
            assertEquals(case.string("white"), white.toString(), golden.failure(case.string("id"), "백 판정"))
            val shown = GomokuRules.forbiddenPoints(board, budget).entries
                .sortedBy { it.key.y * GomokuBoard.size + it.key.x }
                .map { "${it.key.notation}:${it.value.rawValue}" }
            assertEquals(case.array("forbidden").strings(), shown, golden.failure(case.string("id"), "forbiddenPoints"))
        }
        // 골든이 공허하지 않다: 판정 종류가 전부 나오고 예산 초과까지 잰다.
        for (c in "LWTFOB") assertTrue((seen[c] ?: 0) > 0, "판정 '$c' 가 한 번도 안 나왔다: $seen")
        assertTrue(cells > 10_000, "빈칸 대조가 $cells 칸뿐이다")
    }

    @Test
    fun inputTablesMatchSwift() {
        val golden = Golden.load("renju/inputs")
        val kinds = HashMap<String, Int>()
        for (case in golden.cases) {
            val kind = case.string("kind")
            kinds[kind] = (kinds[kind] ?: 0) + 1
            when (kind) {
                "notation" -> {
                    val point = GomokuPoint.fromNotation(cpsText(case.string("input")))
                    assertEquals(case.optInt("x"), point?.x, golden.failure(case.string("id"), "x"))
                    assertEquals(case.optInt("y"), point?.y, golden.failure(case.string("id"), "y"))
                    assertEquals(case.optString("notation"), point?.notation, golden.failure(case.string("id"), "notation"))
                    if (point != null) assertEquals(point, GomokuPoint.fromNotation(point.notation), "표기 왕복")
                }
                "color" -> assertEquals(case.optString("color"), GomokuColor.fromRawValue(cpsText(case.string("input")))?.rawValue,
                    golden.failure(case.string("id"), "색"))
                "serverReason" -> {
                    val input = case.optString("input")?.let(::cpsText)
                    assertEquals(case.optString("reason"), GomokuForbiddenReason.fromServerReason(input)?.rawValue,
                        golden.failure(case.string("id"), "금수 사유 '${input}'"))
                }
                "serverString" -> {
                    val text = cpsText(case.string("input"))
                    val board = GomokuBoard.fromServerString(text)
                    assertEquals(case.bool("valid"), board != null, golden.failure(case.string("id"), "판 문자열 유효"))
                    assertEquals(case.optInt("stoneCount"), board?.stoneCount, golden.failure(case.string("id"), "돌 수"))
                    if (board != null) assertEquals(text, board.serverString, "판 문자열 왕복")
                }
                "turnWarning" -> {
                    val remaining = case.optBits("remainingBits")
                    assertEquals(case.bool("active"), GomokuTurnWarning.isActive(remaining), golden.failure(case.string("id"), "isActive($remaining)"))
                    val got = GomokuTurnWarning.intensity(remaining)
                    assertEquals(case.string("intensityBits"), bitsOf(got), golden.failure(case.string("id"), "intensity($remaining) 비트"))
                }
                "turnWarningConstants" -> {
                    assertEquals(case.string("lowTimeSecondsBits"), bitsOf(GomokuTurnWarning.lowTimeSeconds))
                    assertEquals(case.string("minimumIntensityBits"), bitsOf(GomokuTurnWarning.minimumIntensity))
                    assertEquals(case.string("maximumIntensityBits"), bitsOf(GomokuTurnWarning.maximumIntensity))
                    assertEquals(
                        case.array("tintBits").strings(),
                        listOf(GomokuTurnWarning.tintRed, GomokuTurnWarning.tintGreen, GomokuTurnWarning.tintBlue).map(::bitsOf),
                    )
                    assertEquals(case.string("depthRatioBits"), bitsOf(GomokuTurnWarning.depthRatio))
                    assertEquals(case.string("cornerRatioBits"), bitsOf(GomokuTurnWarning.cornerRatio))
                    assertEquals(case.int("layerCount"), GomokuTurnWarning.layerCount)
                    assertEquals(case.string("peakOpacityBits"), bitsOf(GomokuTurnWarning.peakOpacity))
                    assertEquals(case.int("nodeBudget"), GomokuRules.nodeBudget, "렌주 노드 예산 = 서버 gomoku_judge 상수")
                }
                else -> fail(golden.failure(case.string("id"), "모르는 kind $kind"))
            }
        }
        for (kind in listOf("notation", "color", "serverReason", "serverString", "turnWarning", "turnWarningConstants")) {
            assertTrue((kinds[kind] ?: 0) > 0, "표 '$kind' 가 비었다: $kinds")
        }
    }

    /** 225칸 표기 왕복 · 서버 인덱스(y*15+x) — 골든 밖의 전수 성질. */
    @Test
    fun everyPointRoundTripsAndServerIndexIsRowMajor() {
        for (y in 0 until 15) {
            for (x in 0 until 15) {
                val point = GomokuPoint.at(x, y)!!
                assertEquals(point, GomokuPoint.fromNotation(point.notation))
                val board = GomokuBoard()
                board[point] = GomokuColor.black
                assertEquals('b', board.serverString[y * 15 + x])
            }
        }
        assertEquals(null, GomokuPoint.at(-1, 0))
        assertEquals(null, GomokuPoint.at(0, 15))
    }

    /** Kotlin 은 참조라 Swift 값 의미를 [GomokuBoard.copy] 로 지킨다: 사본을 고쳐도 원본이 안 바뀐다. */
    @Test
    fun boardCopyIsIndependent() {
        val board = GomokuBoard()
        board[GomokuPoint.fromNotation("H8")!!] = GomokuColor.black
        val copy = board.copy()
        copy[GomokuPoint.fromNotation("H9")!!] = GomokuColor.white
        assertEquals(1, board.stoneCount)
        assertEquals(2, copy.stoneCount)
        assertTrue(board != copy)
    }
}
