// 원본: Tests/checkTests/V0369RummyV2MatchTests.swift (seatArrangement · isAcceptable · outcome) · V0369RummyV2LobbyTests.swift (compass) ·
//       V0370RummyBoardFeelTests.swift (preview) @ 1a5eeca6 — 픽셀 대신 값으로 잰다.
package com.yehsung.aingcheck.core.rules.rummy

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RummyBoardPreviewTest {
    @Test
    fun seatsStartAfterMine() {
        // 없으면: 상대 줄이 차례 순서가 아닌 자리 번호 순으로 서서 "다음 사람"을 잘못 읽는다.
        assertEquals(RummySeatArrangement(top = 1), RummySeatArrangement.arrange(listOf(0, 1), 0))
        assertEquals(RummySeatArrangement(top = 0), RummySeatArrangement.arrange(listOf(0, 1), 1))
        assertEquals(RummySeatArrangement(left = 2, right = 0), RummySeatArrangement.arrange(listOf(0, 1, 2), 1))
        assertEquals(RummySeatArrangement(left = 3, top = 0, right = 1), RummySeatArrangement.arrange(listOf(0, 1, 2, 3), 2))
        assertEquals(listOf(3L, 0L, 1L), RummySeatArrangement.arrange(listOf(3, 1, 0, 2), 2).ordered)
        // 내 자리가 없으면(놀던 기기·기권 뒤) 번호 순.
        assertEquals(listOf(0L, 1L), RummySeatArrangement.arrange(listOf(1, 0), null).ordered)
        assertEquals(RummySeatArrangement(), RummySeatArrangement.arrange(listOf(5), 5))
    }

    @Test
    fun compassMatchesTheSeatArrangement() {
        assertEquals(RummySeatCompass.bottom, RummySeatCompass.of(2, 2, listOf(0, 1, 2, 3)))
        assertEquals(RummySeatCompass.bottom, RummySeatCompass.of(2, null, listOf(0, 1, 2, 3)))
        assertEquals(RummySeatCompass.top, RummySeatCompass.of(1, 0, listOf(0, 1)))
        assertEquals(RummySeatCompass.left, RummySeatCompass.of(1, 0, listOf(0, 1, 2)))
        assertEquals(RummySeatCompass.right, RummySeatCompass.of(2, 0, listOf(0, 1, 2)))
        assertEquals(RummySeatCompass.left, RummySeatCompass.of(3, 2, listOf(0, 1, 2, 3)))
        assertEquals(RummySeatCompass.top, RummySeatCompass.of(0, 2, listOf(0, 1, 2, 3)))
        assertEquals(RummySeatCompass.right, RummySeatCompass.of(1, 2, listOf(0, 1, 2, 3)))
        assertEquals(RummySeatCompass.top, RummySeatCompass.of(9, 2, listOf(0, 1, 2)), "모르는 자리는 위")
    }

    @Test
    fun faceKeysNumberEqualMelds() {
        val a = listOf(ef("A1 A2 A3"), ef("B5 C5 D5"), ef("A3 A1 A2"))
        assertEquals(listOf("f:A1,A2,A3#0", "f:B5,C5,D5#0", "f:A1,A2,A3#1"), RummyBoardMeld.faceKeys(a))
    }

    @Test
    fun previewFromTheEditorAnswer() {
        val frames = listOf(RummyRect(0, 0, 120, 56), RummyRect(200, 0, 120, 56))
        val ids = listOf(listOf(0, 1, 2), listOf(3, 4, 5))
        val landing = RummyDropPreview.Landing(1, ef("B1 B2 B3 B4"), RummyRect(200, 0, 160, 56), 3, valid = true)
        // 없으면: 끼울 자리 캐럿이 손에 든 타일을 세어 한 칸 밀린 자리에 선다.
        assertEquals(
            RummyBoardPreview.Insert(1, 280, landing.frame, true),
            RummyBoardPreview.make(RummyDropPreview(RummyDropPlan.Insert(1, 1), landing), 1, ids, frames, setOf(4)),
        )
        assertEquals(
            RummyBoardPreview.Insert(1, 320, landing.frame, true),
            RummyBoardPreview.make(RummyDropPreview(RummyDropPlan.Insert(1, 3), landing), 1, ids, frames, emptySet()),
        )
        // 붙기: 자석은 칸의 대상 쪽 끝이다.
        val right = RummyBoardPreview.make(RummyDropPreview(RummyDropPlan.Attach(1, RummyAttachSide.right), landing), 1, ids, frames, emptySet())
        assertEquals(RummyRect(320, 0, 40, 56), (right as RummyBoardPreview.Attach).slots)
        assertEquals(320L, right.magnetSeamX)
        val leftLanding = landing.copy(blockStart = 0)
        val left = RummyBoardPreview.make(RummyDropPreview(RummyDropPlan.Attach(1, RummyAttachSide.left), leftLanding), 1, ids, frames, emptySet())
        assertEquals(240L, left?.magnetSeamX)
        assertEquals(1, left?.targetSet)
        assertTrue(left?.completes == true)
        // 새 묶음 · 받침대행 · 거절.
        val ghost = RummyBoardPreview.make(RummyDropPreview(RummyDropPlan.NewSet(ep(8, 8)), landing), 1, ids, frames, emptySet())
        assertEquals(RummyBoardPreview.Ghost(landing.frame), ghost)
        assertNull(ghost?.targetSet)
        assertFalse(ghost?.completes == true)
        assertNull(RummyBoardPreview.make(RummyDropPreview(RummyDropPlan.Rack, null), 1, ids, frames, emptySet()))
        assertNull(RummyBoardPreview.make(null, 1, ids, frames, emptySet()))
        // 없는 묶음 번호는 점선으로 접는다.
        assertEquals(RummyBoardPreview.Ghost(landing.frame), RummyBoardPreview.make(RummyDropPreview(RummyDropPlan.Insert(7, 0), landing), 1, ids, frames, emptySet()))
    }

    @Test
    fun beforeInitialDropsTheGreenCheck() {
        // 없으면: 첫 등록 전 판 묶음 위로 끌면 초록 체크가 떠서 놓고 [완료]를 눌러야 막히는 것을 안다(3판 검증).
        val insert = RummyBoardPreview.Insert(0, 40, RummyRect(0, 0, 160, 56), true)
        assertFalse(insert.beforeInitial(touchesTable = true).completes)
        assertTrue(insert.beforeInitial(touchesTable = false).completes)
        val ghost = RummyBoardPreview.Ghost(RummyRect(0, 0, 40, 56))
        assertEquals(ghost, ghost.beforeInitial(touchesTable = true))
    }

    @Test
    fun paletteIsTheRealFourColors() {
        assertEquals(listOf(0xDE2F45, 0x2563EB, 0x141318, 0xEA7A0C), RummyTilePalette.inks)
        assertEquals(0x2563EB, RummyTilePalette.ink(1))
        assertEquals(RummyTilePalette.noInk, RummyTilePalette.ink(null))
        assertEquals(RummyTilePalette.noInk, RummyTilePalette.ink(9))
        assertEquals("빨강 7", RummyTilePalette.accessibilityName(RummyGoldenText.face("A7")))
        assertEquals("주황 13", RummyTilePalette.accessibilityName(RummyGoldenText.face("D13")))
        assertEquals("조커", RummyTilePalette.accessibilityName(RummyGoldenText.face("J")))
    }

    @Test
    fun tileSizeDerivesFromWidth() {
        val rack = RummyTileSize.rack
        assertEquals(36.0, rack.size.width)
        assertEquals(50.0 * 0.075, rack.bevel)
        assertEquals(36.0 * 0.6, rack.numberFont)
        // 아주 작은 판 타일(전체 맞춤)에도 최소값이 선다.
        val tiny = RummyTileSize.canvas(0.25)
        assertEquals(10.0, tiny.size.width)
        assertEquals(2.0, tiny.bevel)
        assertEquals(3.0, tiny.corner)
        assertEquals(3.5, tiny.markSize)
    }

    @Test
    fun artAcceptsOnlyTheRightShape() {
        assertTrue(RummyArtRules.isAcceptable(RummyArtKind.rack, 2400, 478))
        assertFalse(RummyArtRules.isAcceptable(RummyArtKind.rack, 500, 100), "너무 작다")
        assertFalse(RummyArtRules.isAcceptable(RummyArtKind.rack, 1024, 1024), "받침대가 정사각")
        assertTrue(RummyArtRules.isAcceptable(RummyArtKind.table, 512, 512))
        assertFalse(RummyArtRules.isAcceptable(RummyArtKind.table, 100, 100))
        assertFalse(RummyArtRules.isAcceptable(RummyArtKind.table, 2400, 478), "펠트가 가로로 길다")
        assertFalse(RummyArtRules.isAcceptable(RummyArtKind.table, 0, 0))
    }

    @Test
    fun artOutcomeTable() {
        val good = 2400 to 478
        assertEquals(RummyArtOutcome.replace, RummyArtRules.outcome(200, 1000, good, RummyArtKind.rack))
        assertEquals(RummyArtOutcome.keep, RummyArtRules.outcome(200, 1000, null, RummyArtKind.rack), "못 읽는 그림")
        assertEquals(RummyArtOutcome.keep, RummyArtRules.outcome(200, RummyArtRules.maxBytes + 1, good, RummyArtKind.rack), "너무 크다")
        assertEquals(RummyArtOutcome.keep, RummyArtRules.outcome(200, 1000, 512 to 512, RummyArtKind.rack), "모양이 틀렸다")
        assertEquals(RummyArtOutcome.keep, RummyArtRules.outcome(304, 0, null, RummyArtKind.rack))
        assertEquals(RummyArtOutcome.keep, RummyArtRules.outcome(500, 0, null, RummyArtKind.table))
        assertEquals(RummyArtOutcome.revert, RummyArtRules.outcome(404, 0, null, RummyArtKind.table))
    }

    @Test
    fun artPathsAndCaps() {
        assertEquals("rummy/rack.png", RummyArtKind.rack.remotePath)
        assertEquals("rummy-table", RummyArtKind.table.bundleName)
        assertEquals(150, RummyArtRules.rackCapPixels(2400, 478))
        assertEquals(100, RummyArtRules.rackCapPixels(1600, 319))
        assertNull(RummyArtRules.rackCapPixels(0, 0))
    }
}
