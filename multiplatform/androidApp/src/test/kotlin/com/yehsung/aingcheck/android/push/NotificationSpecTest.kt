package com.yehsung.aingcheck.android.push

import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.RouteRequest
import com.yehsung.aingcheck.feature.phone.push.PhonePushMegaphone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationSpecTest {
    private fun decide(vararg pairs: Pair<String, String>, viewing: AingRoute? = null) = NotificationSpecs.decide(mapOf(*pairs), viewing)

    @Test
    fun unknownOrMissingTypeIsNotPosted() {
        assertTrue(decide("type" to "tetris_invite", "match_id" to "m") is PushDecision.Drop)
        assertTrue(decide("peer_id" to "p") is PushDecision.Drop)
        assertTrue(decide("type" to "") is PushDecision.Drop)
    }

    @Test
    fun requiredIdsAreChecked() {
        assertTrue(decide("type" to "message") is PushDecision.Drop)
        assertTrue(decide("type" to "message", "peer_id" to "../x") is PushDecision.Drop)
        assertTrue(decide("type" to "gomoku_invite") is PushDecision.Drop)
        assertTrue(decide("type" to "chess_invite", "match_id" to "a b") is PushDecision.Drop)
        // 기준선: 같은 모양에 id 만 맞으면 게시한다.
        assertTrue(decide("type" to "chess_invite", "match_id" to "ab") is PushDecision.Post)
    }

    @Test
    fun idsAreTrimmedAndLowercasedTypeTolerant() {
        val d = decide("type" to " MESSAGE ", "peer_id" to " ABC-1 ", "title" to "t", "body" to "b")
        assertEquals(AingRoute.Message("abc-1"), ((d as PushDecision.Post).spec.tap.route))
        assertEquals("message-abc-1", d.spec.tag)
    }

    @Test
    fun optionalIdsFoldToLists() {
        val noReport = decide("type" to "feedback_reply") as PushDecision.Post
        assertEquals(AingRoute.Feedback(null), noReport.spec.tap.route)
        assertEquals("feedback-list", noReport.spec.tag)
        val badReport = decide("type" to "feedback_reply", "report_id" to "%%") as PushDecision.Post
        assertEquals(AingRoute.Feedback(null), badReport.spec.tap.route)
        val work = decide("type" to "work_check") as PushDecision.Post
        assertEquals(AingRoute.Now, work.spec.tap.route)
    }

    @Test
    fun missingTitleFallsBackToChannelName() {
        val d = decide("type" to "gomoku_invite", "match_id" to "m1") as PushDecision.Post
        assertEquals("오목 신청", d.spec.title)
        assertEquals("", d.spec.body)
    }

    /**
     * 확성기 판정은 앞/뒤(Swift `isAppActive`)로 가른다 — 보고 있는 라우트로 가르지 않는다. 라우트 없는 화면(미션 · nav 대화상자 …)은 viewing 이
     * null 이어도 앞이다.
     */
    @Test
    fun megaphoneSplitsOnForegroundNotOnViewing() {
        val data = mapOf("type" to "message", "peer_id" to "p1", "megaphone_id" to "MP-1", "title" to "보낸사람", "body" to "다들 화이팅")
        val megaphone = PhonePushMegaphone("mp-1", "보낸사람", "다들 화이팅")
        // 앞 + 라우트 없는 화면 → 숨김(앱 배너로 표식을 넘긴다).
        assertEquals(PushDecision.Hide(AingRoute.Message("p1"), AingChannel.MESSAGE, megaphone), NotificationSpecs.decide(data, viewing = null, isForeground = true))
        // 뒤 → 게시, 탭에 표식 · 태그는 확성기별.
        val posted = NotificationSpecs.decide(data, viewing = null, isForeground = false) as PushDecision.Post
        assertEquals(RouteRequest(AingRoute.Message("p1"), megaphone = megaphone), posted.spec.tap)
        assertEquals("megaphone-mp-1", posted.spec.tag)
        // 기준선: megaphone_id 없음 → 지금과 같다(앞이어도 보고 있지 않은 대화면 게시 · 표식 없음).
        val plain = NotificationSpecs.decide(data - "megaphone_id", viewing = null, isForeground = true) as PushDecision.Post
        assertEquals(RouteRequest(AingRoute.Message("p1")), plain.spec.tap)
        assertEquals("message-p1", plain.spec.tag)
    }
}
