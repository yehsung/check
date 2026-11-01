// 원본: Tests/checkTests/V0369RummyPanelRenderTests.swift 의 뜻(화면 글자를 값으로 잰다) — 폰 표는 터치 기준이라 맥 글자와 그대로 비교하지 않고 뜻을 잰다.
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.wire.games.RummyEndReason
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLastEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GamesRummyTextTest {
    /** 사용자 글자 전부(고정 글자 + 규칙 + 확인 + 대표 조립). */
    private val everyLine: List<String> = RummyPhoneText.ruleList.flatMap { listOf(it.title, it.detail) } +
        listOf(RummyCloseDecision.confirmForfeit, RummyCloseDecision.confirmCloseRoom).mapNotNull { RummyPhoneText.exit(it) }.flatMap { listOf(it.title, it.detail, it.confirm) } +
        listOf(
            RummyPhoneText.title, RummyPhoneText.cardSubtitle, RummyPhoneText.cardOpenHint, RummyPhoneText.myTurn,
            RummyPhoneText.otherDevice, RummyPhoneText.otherDeviceDetail, RummyPhoneText.rotating, RummyPhoneText.backgroundWarning, RummyPhoneText.createHint, RummyPhoneText.joinEmpty,
        )

    @Test
    fun noMacWordsOrTrademark() {
        // 없으면: 맥 표를 옮기다 남은 "창을 닫으면"·⌥·마우스 어휘가 폰에 뜬다. 상표 이름도 여기서 막는다.
        val banned = listOf("창", "마우스", "클릭", "호버", "⌥", "트랙패드", "커서", "메뉴바", "루미")
        for (line in everyLine) for (word in banned) assertFalse(word in line, "\"$line\" 에 \"$word\"")
    }

    @Test
    fun timeoutIsOneTile() {
        // 사용자 10-30 결정(화남 — 되묻지 말 것): 시간 초과는 되돌리고 1장. 낡은 '3장' 인수인계 문구가 들어오면 빨강.
        val rule = RummyPhoneText.ruleList.first { it.title == "시간 60초" }.detail
        assertTrue("되돌리고 1장" in rule, rule)
        assertFalse("3장" in rule, rule)
        assertEquals("비님 시간 초과 — 되돌리고 1장 뽑음", RummyPhoneText.lastEvent(RummyLastEvent(kind = "timeout_penalty"), "비"))
    }

    @Test
    fun splitRuleMatchesTheUserDecision() {
        val rule = RummyPhoneText.ruleList.first { it.title == "등수 분배" }.detail
        assertTrue("2명 +N·−N" in rule && "3명 +N·0·−N" in rule && "4명 +2N·0·−N·−N" in rule, rule)
    }

    @Test
    fun exitCopyAsksOnlyWhenTheStoreAsks() {
        assertNull(RummyPhoneText.exit(RummyCloseDecision.close))
        assertNull(RummyPhoneText.exit(RummyCloseDecision.leaveRoom))
        val forfeit = assertNotNull(RummyPhoneText.exit(RummyCloseDecision.confirmForfeit))
        assertEquals("나가면 기권돼 꼴찌가 되고 판돈을 잃어요.", forfeit.detail)
        assertNotNull(RummyPhoneText.exit(RummyCloseDecision.confirmCloseRoom))
    }

    @Test
    fun formatters() {
        assertEquals("1:05", RummyPhoneText.clock(65))
        assertEquals("0:00", RummyPhoneText.clock(-3))
        assertEquals("+3", RummyPhoneText.net(3))
        assertEquals("−3", RummyPhoneText.net(-3))
        assertEquals("0", RummyPhoneText.net(0))
        assertEquals("점수 —", RummyPhoneText.score(null))
        assertEquals("점수 +4", RummyPhoneText.score(4))
        assertEquals("점수 −4", RummyPhoneText.score(-4))
        assertEquals("—", RummyPhoneText.rank(null))
        assertEquals("2등", RummyPhoneText.rank(2))
        assertEquals("2위", RummyPhoneText.ladderRank(2))
        assertEquals("랙 묶음 합 12 / 30", RummyPhoneText.plan(0, 12))
        assertEquals("랙 묶음 10 + 판 8 = 18 / 30", RummyPhoneText.plan(8, 10))
    }

    @Test
    fun peopleCaptionHasThreeBranches() {
        assertEquals(RummyPhoneText.peopleCaptionNoRoom, RummyPhoneText.peopleCaption(inRoom = false, amHost = false))
        assertEquals(RummyPhoneText.peopleCaptionHost, RummyPhoneText.peopleCaption(inRoom = true, amHost = true))
        assertEquals(RummyPhoneText.peopleCaptionGuest, RummyPhoneText.peopleCaption(inRoom = true, amHost = false))
    }

    @Test
    fun endReasonAndLastEvent() {
        assertEquals("비님이 랙을 비웠어요", RummyPhoneText.endReason(RummyEndReason.rackEmpty, "비"))
        assertEquals("랙을 비운 사람이 나왔어요", RummyPhoneText.endReason(RummyEndReason.rackEmpty, null))
        // 내가 이겼으면 내 이름을 남처럼 부르지 않는다.
        assertEquals("랙을 비웠어요", RummyPhoneText.endReason(RummyEndReason.rackEmpty, "나", winnerIsMe = true))
        assertEquals("비님 혼자 남아 끝났어요", RummyPhoneText.endReason(RummyEndReason.lastStanding, "비"))
        assertEquals("혼자 남아 끝났어요", RummyPhoneText.endReason(RummyEndReason.lastStanding, "나", winnerIsMe = true))
        assertEquals("판이 끝났어요", RummyPhoneText.endReason(null, null))
        assertNull(RummyPhoneText.lastEvent(null, "비"))
        assertNull(RummyPhoneText.lastEvent(RummyLastEvent(kind = "play"), null))
        assertNull(RummyPhoneText.lastEvent(RummyLastEvent(kind = "모름"), "비"))
    }

    @Test
    fun myTurnStatusFollowsTheEditor() {
        val faces = listOf("A10", "B10", "C10").map { RummyFace.of(it)!! }
        val before = RummyTurnEditor(emptyList(), faces, initialDone = false)
        assertEquals("첫 등록 0/30점", RummyPhoneText.myTurnStatus(before))
        val done = RummyTurnEditor(emptyList(), faces, initialDone = true)
        assertEquals(RummyPhoneText.myTurn, RummyPhoneText.myTurnStatus(done), "안 바꿨으면 이유를 말하지 않는다")
        assertTrue(done.move(done.rack[0].id, com.yehsung.aingcheck.core.rules.rummy.RummyDropTarget.NewMeld))
        assertEquals("맞지 않는 묶음이 있어요.", RummyPhoneText.myTurnStatus(done))
    }

    @Test
    fun availabilityTable() {
        assertNull(RummyPhoneText.unavailable(RummyAvailability.available))
        assertEquals(RummyNoticeText.updateRequired, RummyPhoneText.unavailable(RummyAvailability.updateRequired))
        assertEquals(RummyPhoneText.serverMissing, RummyPhoneText.unavailable(RummyAvailability.serverMissing))
    }
}
