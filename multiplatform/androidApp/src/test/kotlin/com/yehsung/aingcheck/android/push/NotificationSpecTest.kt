package com.yehsung.aingcheck.android.push

import com.yehsung.aingcheck.android.routing.AingRoute
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
}
