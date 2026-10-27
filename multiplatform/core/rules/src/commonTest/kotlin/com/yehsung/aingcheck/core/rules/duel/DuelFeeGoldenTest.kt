// 원본: Tests/checkTests/V0354DuelFeeTests.swift(손 표) · Tests/checkTests/GoldenExport/games-board/GoldenExportGamesBoardDuelFee.swift(골든 생성기) @ 1b8260d
package com.yehsung.aingcheck.core.rules.duel

import com.yehsung.aingcheck.core.rules.renju.optInt
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 판돈 수수료(C§5.1 E10). v0.3.64 부터 0 이다 — 이긴 사람은 2×판돈(순이익 +판돈).
 * INV-DuelFee-306dfc91: 클라 식과 서버 `duel_fee` 가 갈리면 결과 카드와 잔량 칩이 한 화면에서 다른 숫자를 말한다.
 * ① 골든 `duel-fee/fee`(Swift `DuelFee` 가 낸 판돈 −5…100 표)와 비트로 같다 ② **손으로 적은 표**(식에서 기대값을 만들지 않는다)와 같다.
 */
class DuelFeeGoldenTest {
    @Test
    fun feeTableMatchesSwift() {
        val golden = Golden.load("duel-fee/fee")
        var stakes = 0
        for (case in golden.cases) {
            if (case.string("id") == "percent") {
                assertEquals(case.int("percent"), DuelFee.percent, "수수료 비율")
                continue
            }
            val stake = case.int("stake")
            assertEquals(case.optInt("fee"), DuelFee.fee(stake), golden.failure(case.string("id"), "fee"))
            assertEquals(case.optInt("payout"), DuelFee.winnerPayout(stake), golden.failure(case.string("id"), "winnerPayout"))
            assertEquals(case.optInt("net"), DuelFee.winnerNet(stake), golden.failure(case.string("id"), "winnerNet"))
            stakes++
        }
        assertEquals(106, stakes, "판돈 −5…100")
    }

    /** 명세(손으로 적은 값): 판돈 3/5/10 → 수수료 0 · 수령 6/10/20 · 순이익 +3/+5/+10, 0 과 음수는 0. */
    @Test
    fun handWrittenTable() {
        val table = listOf(
            intArrayOf(3, 0, 6, 3),
            intArrayOf(5, 0, 10, 5),
            intArrayOf(10, 0, 20, 10),
            intArrayOf(0, 0, 0, 0), // AI·로봇 대국(판돈 0)
            intArrayOf(-5, 0, 0, 0), // 방어선 — 서버에 그런 판은 없다
            intArrayOf(1, 0, 2, 1),
            intArrayOf(13, 0, 26, 13),
            intArrayOf(25, 0, 50, 25),
        )
        for ((stake, fee, payout, net) in table.map { listOf(it[0], it[1], it[2], it[3]) }) {
            assertEquals(fee, DuelFee.fee(stake), "판돈 $stake 수수료")
            assertEquals(payout, DuelFee.winnerPayout(stake), "판돈 $stake 승자 수령")
            assertEquals(net, DuelFee.winnerNet(stake), "판돈 $stake 순이익")
        }
        assertEquals(0, DuelFee.percent)
    }

    /** 기준선: 옛 식(반올림 10%, v0.3.54)이 되살아나면 판돈 3 이상에서 갈린다 — 표가 그 차이를 실제로 잰다는 확인. */
    @Test
    fun oldRoundedTenPercentWouldDiffer() {
        var differs = 0
        for (stake in 1..100) {
            val oldFee = (2 * stake * 10 + 50) / 100
            if (stake >= 3) assertTrue(oldFee > 0 && DuelFee.winnerNet(stake) != stake - oldFee, "판돈 $stake 에서 옛 식과 같다")
            if (DuelFee.winnerNet(stake) != stake - oldFee) differs++
        }
        assertEquals(98, differs, "판돈 3…100 이 옛 식과 갈린다")
    }
}
