// 원본: Tests/checkTests/V0312AntigravityWiringTests.swift · V0241ToolMixTests.swift(toolUsageLabel · detailTooltip — 안티그래비티는 캡션 밖) @ 1b8260d
package com.yehsung.aingcheck.core.stores.rankings

import com.yehsung.aingcheck.core.wire.models.TokenBoardEntry
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class RankingsTokenCaptionTest {
    private fun entry(claude: Long, codexLocal: Long, codexServer: Long?, total: Long) = TokenBoardEntry(
        userID = "u", name = "이름", avatarURL = null, total = total, claudeInput = claude, claudeOutput = 0, claudeCacheRead = 0,
        claudeCacheCreation = 0, codexInput = codexLocal, codexOutput = 0, codexEffectiveFromServer = codexServer,
    )

    /**
     * INV-SupabaseWorkModels-bf12f84b: 안티그래비티는 캡션에 넣지 않는다. 기준선(안티그래비티 0)에서는 캡션 합 == 굵은 총합이고,
     * 안티그래비티가 있는 행은 캡션이 같고 툴팁에만 세 번째 줄이 선다(세 값 합 == 총합).
     */
    @Test
    fun antigravityStaysOutOfCaptionAndOnlyTooltipExplainsTheRest() {
        val plain = entry(claude = 19_660_000_000, codexLocal = 0, codexServer = 2_540_000, total = 19_662_540_000)
        assertEquals("Claude 196.6억 · Codex 254만", TokenBoardText.toolUsageLabel(plain))
        assertEquals("Claude 19,660,000,000 · Codex 2,540,000", TokenBoardText.detailTooltip(plain))
        val withAntigravity = plain.copy(total = plain.total + 7_000_000_000)
        assertEquals(7_000_000_000, withAntigravity.antigravityEffective)
        assertEquals("Claude 196.6억 · Codex 254만", TokenBoardText.toolUsageLabel(withAntigravity), "캡션에 안티그래비티가 섰다")
        assertEquals("Claude 19,660,000,000 · Codex 2,540,000 · 안티그래비티 7,000,000,000", TokenBoardText.detailTooltip(withAntigravity))
        assertNull(TokenBoardText.toolUsageLabel(entry(0, 0, 0, 5)), "두 종류가 0 이면 줄 자체가 없다")
        // 옛 RPC(서버 몫 없음): 순위판 캡션 전용 max(로컬, 계정) 미러.
        assertEquals("Codex 9", TokenBoardText.toolUsageLabel(entry(0, 9, null, 9)))
    }
}
