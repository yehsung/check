// 원본: Sources/CheckMobileKit/Components/MobileComponentModels.swift @ 862be0f (부품 순수 규칙)
//
// 부품 규칙(iOS MobileComponentModels 의 순수 규칙과 같은 값). 플랫폼 무관.
package com.yehsung.aingcheck.ui.components

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ComponentRulesTest {
    @Test
    fun ringWidthRoundsHalfToEvenLikeSwift() {
        assertEquals(2f, CharacterMood.ringWidth(25f))   // 1.0 → 하한 2
        assertEquals(2f, CharacterMood.ringWidth(52f))   // 2.08 → 2
        assertEquals(3f, CharacterMood.ringWidth(68f))   // 2.72 → 3
        assertEquals(5f, CharacterMood.ringWidth(132f))  // 5.28 → 5
        // .5 에서 Swift .toNearestOrEven 은 짝수로(Double 곱): 62.5×0.04 = 2.5 → 2, 87.5×0.04 = 3.5 → 4. 올림 반올림이면 3·4.
        assertEquals(2f, CharacterMood.ringWidth(62.5f))
        assertEquals(4f, CharacterMood.ringWidth(87.5f))
        assertEquals(6.0, CharacterMood.roundHalfEven(6.5))
        assertEquals(8.0, CharacterMood.roundHalfEven(7.5))
        assertEquals(-2.0, CharacterMood.roundHalfEven(-2.5))
    }

    @Test
    fun moodMapsToRingAndExpression() {
        assertEquals(PresenceStatus.Working, CharacterMood.Working.ring)
        assertEquals(PresenceStatus.Pending, CharacterMood.Lost.ring)
        assertEquals(PresenceStatus.Off, CharacterMood.Off.ring)
        assertNull(CharacterMood.Plain.ring)
        assertEquals(CharacterExpression.Negative, CharacterMood.Off.expression)
        assertEquals(listOf(CharacterExpression.Neutral), listOf(CharacterMood.Working, CharacterMood.Lost, CharacterMood.Plain).map { it.expression }.distinct())
    }

    @Test
    fun rubyGlyphPicksDownscaledArt() {
        assertEquals("ruby-48", RubyGlyph.assetName(24f, 2f))   // 48px
        assertEquals("ruby-96", RubyGlyph.assetName(24f, 3f))   // 72px
        assertEquals("ruby-96", RubyGlyph.assetName(24f, 4f))   // 96px
        assertEquals("ruby", RubyGlyph.assetName(44f, 3f))      // 132px
        assertEquals("ruby-48", RubyGlyph.assetName(17f, 0.5f)) // 배율 1 미만은 1 로
    }

    @Test
    fun rubyPriceRuleDoesNotInventShortageWhenBalanceUnknown() {
        assertFalse(RubyPriceRule.isShort(50, null))
        assertTrue(RubyPriceRule.isShort(50, 49))
        assertFalse(RubyPriceRule.isShort(50, 50))
        assertEquals("루비 30개, 모자라요", RubyPriceRule.accessibilityText(30, true))
        assertEquals("–", RubyPriceRule.balanceText(null))
        assertEquals("루비 잔액 모름", RubyPriceRule.balanceAccessibility(null))
    }

    @Test
    fun stageArtChoiceFollowsPixelsAndExpression() {
        assertTrue(CharacterStageMetrics.prefersStageArt("fox", CharacterExpression.Neutral, 132f, 2f))   // 264px > 192
        assertFalse(CharacterStageMetrics.prefersStageArt("fox", CharacterExpression.Neutral, 52f, 3f))   // 156px
        assertFalse(CharacterStageMetrics.prefersStageArt("fox", CharacterExpression.Negative, 132f, 3f)) // 시무룩은 192px 뿐
        assertFalse(CharacterStageMetrics.prefersStageArt("aing", CharacterExpression.Neutral, 132f, 3f)) // 아잉은 무대 그림이 없다
    }

    @Test
    fun contributionGridLayoutMatchesIos() {
        assertEquals(13f, ContributionGridLayout.cellSize(400f, 13))               // 상한
        val c = ContributionGridLayout.cellSize(150f, 13)                           // (150 - 2.5×12)/13 = 9.23
        assertTrue(kotlin.math.abs(c - 120f / 13f) < 1e-4f)
        assertEquals(0f, ContributionGridLayout.cellSize(0f, 13))
        assertEquals(0f, ContributionGridLayout.cellSize(100f, 0))
        val (w, h) = ContributionGridLayout.gridSize(10f, 13)
        assertEquals(10f * 13 + 2.5f * 12, w)
        assertEquals(10f * 7 + 2.5f * 6, h)
        assertEquals(listOf(0f, 0.30f, 0.55f, 0.78f, 1f, 1f), listOf(0, 1, 2, 3, 4, 9).map { ContributionLevels.opacity(it) })
        assertEquals(0f, ContributionLevels.opacity(-1))
    }

    @Test
    fun galleryVariantsDifferInOnePlaceOnly() {
        // 진열장 기준선이 '한 군데만 다른 장면'이 되려면 잔디 씨앗은 기본값 그대로여야 하고, 미래 칸 3개는 늘 null.
        val levels = galleryLevels(0)
        assertEquals(13, levels.size)
        assertEquals(3, levels.flatten().count { it == null })
        assertTrue(levels.flatten().filterNotNull().toSet().containsAll(listOf(0, 1, 2, 3, 4)), "단계 0~4 가 다 나와야 사다리가 보인다")
        assertTrue(galleryLevels(1) != levels)
    }

    @Test
    fun artPathsFollowSyncLayout() {
        assertEquals("files/characters/fox/portrait-neutral.png", CharacterArt.portraitPath("fox", CharacterExpression.Neutral))
        assertEquals("files/characters/aing_gold/portrait-negative.png", CharacterArt.portraitPath("aing_gold", CharacterExpression.Negative))
        assertEquals("files/characters/fox/manifest.json", CharacterArt.manifestPath("fox"))
        assertEquals("files/art/ruby-48.png", CharacterArt.rubyPath(17f, 2f))
        assertEquals("files/art/stage-fox-neutral.png", CharacterArt.stagePath("fox"))
        assertEquals(CharacterStageMetrics.stageArtIds, CharacterArt.spriteIds.toSet())
    }
}
