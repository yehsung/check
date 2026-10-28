// 원본: Sources/CheckMobileKit/Games/GamesGomokuRuleExamples.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuForbiddenReason
import com.yehsung.aingcheck.core.rules.renju.GomokuJudgement
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint

/**
 * 규칙 보기 시트의 예시 국면 — 맥 `GomokuRuleExample` 을 그대로 옮겼다. **좌표는 조사 코퍼스에서 온 값**이고([id] 가 코퍼스 케이스 번호)
 * 기대 판정은 시험이 W1-b 판정기로 되묻는다.
 */
data class GomokuPhoneRuleExample(
    val id: String,
    val title: String,
    val detail: String,
    val black: List<String>,
    val white: List<String>,
    val point: String,
    val expected: GomokuJudgement,
    val pivot: String? = null,
) {
    /** 규칙 예시 판에 얹는 표시. */
    enum class Mark { forbidden, win, legal, pivot }

    /** 예시 판(부를 때마다 새 판 — Kotlin 판은 가변 참조라 값 의미를 지킨다). */
    val board: GomokuBoard
        get() {
            val board = GomokuBoard()
            for (notation in black) GomokuPoint.fromNotation(notation)?.let { board[it] = GomokuColor.black }
            for (notation in white) GomokuPoint.fromNotation(notation)?.let { board[it] = GomokuColor.white }
            return board
        }

    val marks: Map<GomokuPoint, Mark>
        get() {
            val marks = LinkedHashMap<GomokuPoint, Mark>()
            GomokuPoint.fromNotation(point)?.let { p ->
                marks[p] = when (expected) {
                    GomokuJudgement.Win -> Mark.win
                    is GomokuJudgement.Forbidden -> Mark.forbidden
                    else -> Mark.legal
                }
            }
            pivot?.let { GomokuPoint.fromNotation(it) }?.let { marks[it] = Mark.pivot }
            return marks
        }

    companion object {
        /** 여섯 예시 모두 H8 을 가운데로 둔 9×9(D..L × 4..12) 안에 들어온다. */
        const val cropOriginX: Int = 3
        const val cropOriginY: Int = 3
        const val cropLines: Int = 9

        val all: List<GomokuPhoneRuleExample> = listOf(
            GomokuPhoneRuleExample(
                id = "K01", title = "3-3 금수", detail = "열린 3이 한꺼번에 두 개 생겨요",
                black = listOf("F8", "G8", "H6", "H7"), white = emptyList(), point = "H8",
                expected = GomokuJudgement.Forbidden(GomokuForbiddenReason.doubleThree),
            ),
            GomokuPhoneRuleExample(
                id = "K12", title = "4-4 금수", detail = "막혀 있어도 4가 두 개면 금수예요",
                black = listOf("E8", "F8", "G8", "H9", "H10", "H11"), white = listOf("D8", "H12"), point = "H8",
                expected = GomokuJudgement.Forbidden(GomokuForbiddenReason.doubleFour),
            ),
            GomokuPhoneRuleExample(
                id = "K19", title = "장목 금수", detail = "흑은 6개 이상 이을 수 없어요",
                black = listOf("E8", "F8", "G8", "I8", "J8"), white = emptyList(), point = "H8",
                expected = GomokuJudgement.Forbidden(GomokuForbiddenReason.overline),
            ),
            GomokuPhoneRuleExample(
                id = "K24", title = "5목이 먼저", detail = "금수 모양이 함께 생겨도 5목이면 이겨요",
                black = listOf("D8", "E8", "F8", "G8", "H9", "H10", "I9", "J10"), white = emptyList(), point = "H8",
                expected = GomokuJudgement.Win,
            ),
            GomokuPhoneRuleExample(
                id = "K28", title = "4-3은 괜찮아요", detail = "4 하나 + 3 하나는 둘 수 있어요",
                black = listOf("E8", "F8", "G8", "H9", "H10"), white = listOf("D8"), point = "H8",
                expected = GomokuJudgement.Legal,
            ),
            GomokuPhoneRuleExample(
                id = "K34", title = "거짓 3", detail = "4로 만들 자리(주황)가 장목이라 가로는 3이 아니에요",
                black = listOf("G8", "J8", "I6", "I7", "I9", "I10", "I11", "H9", "H10"), white = emptyList(), point = "H8",
                expected = GomokuJudgement.Legal, pivot = "I8",
            ),
        )

        /** 설명 줄(맥과 같은 문장). */
        val ruleLines: List<String> = listOf(
            "흑이 먼저 둬요. 가로·세로·대각선으로 5개를 먼저 이으면 이겨요.",
            "흑만 금수가 있어요 — 3-3, 4-4, 장목(6개 이상). 흑 차례엔 금수 자리에 X가 떠요.",
            "흑은 정확히 5개여야 이기고, 백은 5개 이상이면 이겨요.",
            "5목이 되는 수는 금수 모양이 함께 생겨도 흑의 승리예요. 4-3은 금수가 아니에요.",
            "한 수에 30초. 30초를 넘기면 무작위로 놓입니다 · 3번 연속이면 집니다.",
            "흑이 둘 곳이 없으면 차례가 백으로 넘어가고, 판이 가득 차면 무승부예요.",
            // v0.3.64: 판돈 수수료를 없앴다(사용자 결정 2026-10-22) — 맥 `GomokuRuleExample` 규칙 줄과 같은 문장.
            "수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고, 무승부면 건 판돈을 돌려받아요.",
        )
    }
}
