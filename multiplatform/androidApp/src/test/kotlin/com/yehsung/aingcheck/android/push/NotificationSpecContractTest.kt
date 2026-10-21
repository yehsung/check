// W1-g 완료 기준 ④: contract/push/payloads 5종(서버 트리거 실출력, W0-c) → K7 data 맵 → NotificationSpec 기대 사양.
// 정본 폴더가 없으면 **빨강**이다(건너뛰지 않는다) — 이 폴더는 W0-c 가 낸다(병합 순서는 완료 보고에 적었다).
package com.yehsung.aingcheck.android.push

import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.RouteRequest
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class NotificationSpecContractTest {
    private val kinds = listOf("message", "gomoku_invite", "chess_invite", "feedback_reply", "work_check")

    private fun data(kind: String): Map<String, String> =
        K7DataMessage.fromSqlPayload(RepoFiles.readText("contract/push/payloads/$kind.json"), kind)

    private fun post(kind: String, viewing: AingRoute? = null): NotificationSpec {
        val d = decideFor(kind, viewing)
        assertTrue("$kind 는 게시돼야 한다: $d", d is PushDecision.Post)
        return (d as PushDecision.Post).spec
    }

    private fun decideFor(kind: String, viewing: AingRoute?) = NotificationSpecs.decide(data(kind), viewing)

    @Test
    fun contractFolderHasExactlyTheFiveKinds() {
        val dir = File(System.getProperty("aingcheck.repoRoot"), "contract/push/payloads")
        assertTrue("정본 폴더가 없다: $dir (W0-c 병합 전이면 빨강이 맞다)", dir.isDirectory)
        val names = dir.listFiles()!!.filter { it.name.endsWith(".json") }.map { it.name.removeSuffix(".json") }.toSet()
        assertEquals(kinds.toSet(), names)
        // 채널 다섯과 글자까지 같다(K7 · E§6.5).
        assertEquals(kinds.toSet(), AingChannel.entries.map { it.id }.toSet())
    }

    @Test
    fun messageSpec() {
        val spec = post("message")
        assertEquals(
            NotificationSpec(
                channel = AingChannel.MESSAGE,
                title = "보낸사람",
                body = "오늘 회의 몇 시예요?",
                tag = "message-0a11ce00-0000-4000-8000-00000000a501",
                group = NotificationSpecs.MESSAGE_GROUP,
                tap = RouteRequest(AingRoute.Message("0a11ce00-0000-4000-8000-00000000a501")),
                actions = emptyList(),
                category = NotificationSpecs.CATEGORY_MESSAGE,
            ),
            spec,
        )
        // 서버의 thread_id 와 앱이 짓는 태그가 같은 묶음을 가리킨다.
        assertEquals(data("message")["thread_id"], spec.tag)
    }

    @Test
    fun gomokuInviteSpecCarriesAccept() {
        val match = "0f0f0000-0000-4000-8000-00000000f506"
        val route = AingRoute.GomokuInvite(match)
        assertEquals(
            NotificationSpec(
                AingChannel.GOMOKU_INVITE, "오목 신청", "보낸사람님이 오목 대결을 신청했어요 · 루비 3", "gomoku-$match", null,
                RouteRequest(route),
                listOf(NotificationActionSpec(NotificationSpecs.ACCEPT_ACTION_ID, "수락", RouteRequest(route, accept = true))),
                NotificationSpecs.CATEGORY_SOCIAL,
            ),
            post("gomoku_invite"),
        )
    }

    @Test
    fun chessInviteSpecCarriesAccept() {
        val match = "1a1a0000-0000-4000-8000-00000001a507"
        val route = AingRoute.ChessInvite(match)
        assertEquals(
            NotificationSpec(
                AingChannel.CHESS_INVITE, "체스 신청", "보낸사람님이 체스 대결을 신청했어요 · 루비 5", "chess-$match", null,
                RouteRequest(route),
                listOf(NotificationActionSpec(NotificationSpecs.ACCEPT_ACTION_ID, "수락", RouteRequest(route, accept = true))),
                NotificationSpecs.CATEGORY_SOCIAL,
            ),
            post("chess_invite"),
        )
    }

    @Test
    fun feedbackReplySpec() {
        val report = "1b1b0000-0000-4000-8000-00000001b508"
        assertEquals(
            NotificationSpec(
                AingChannel.FEEDBACK_REPLY, "제보에 답장이 왔어요", "확인했어요. 다음 판에서 고칠게요.", "feedback-$report", null,
                RouteRequest(AingRoute.Feedback(report)), emptyList(), NotificationSpecs.CATEGORY_SOCIAL,
            ),
            post("feedback_reply"),
        )
    }

    @Test
    fun workCheckSpecOpensNow() {
        assertEquals(
            NotificationSpec(
                AingChannel.WORK_CHECK, "아직 근무 중이에요?", "10분 안에 앱을 열면 근무가 이어져요", "work-check", null,
                RouteRequest(AingRoute.Now), emptyList(), NotificationSpecs.CATEGORY_REMINDER,
            ),
            post("work_check"),
        )
        // 서버 collapse_id 와 같은 태그(같은 근무 확인은 하나만 보인다).
        assertEquals("work-check", data("work_check")["thread_id"])
    }

    @Test
    fun viewingTheSameConversationHidesOnlyThatMessage() {
        val peer = "0a11ce00-0000-4000-8000-00000000a501"
        assertEquals(PushDecision.Hide(AingRoute.Message(peer), AingChannel.MESSAGE), decideFor("message", AingRoute.Message(peer)))
        // 기준선: 다른 대화·다른 화면을 보고 있으면 게시한다.
        assertTrue(decideFor("message", AingRoute.Message("someone-else")) is PushDecision.Post)
        assertTrue(decideFor("message", AingRoute.Messages) is PushDecision.Post)
        // 메시지가 아닌 종류는 보고 있는 화면과 상관없이 게시한다.
        assertTrue(decideFor("work_check", AingRoute.Now) is PushDecision.Post)
        assertTrue(decideFor("gomoku_invite", AingRoute.GomokuInvite("0f0f0000-0000-4000-8000-00000000f506")) is PushDecision.Post)
    }

    @Test
    fun everyPayloadIsDataOnlyStrings() {
        for (kind in kinds) {
            val d = data(kind)
            assertEquals(kind, d["type"])
            assertTrue("$kind 에 title·body 가 없다", d["title"]!!.isNotBlank() && d["body"]!!.isNotBlank())
            assertTrue("$kind data 에 notification·aps 가 섞였다", d.keys.none { it == "aps" || it == "_apns" || it == "notification" })
        }
    }
}
