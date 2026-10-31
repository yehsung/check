// 원본: Tests/CheckMobileKitTests/MessagesSendIdempotencyTests.swift ①~⑨ · 분류 가장자리(반박 보강 56ce31e7) @ 1a5eeca6 — 전송 멱등 키(서버 20261101131000)
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MessagesSendIdempotencyTest {
    private val peerA = "peer-a"
    private val peerB = "peer-b"
    private val okWithID = Reply.Json("""{"status":"ok","message_id":"m1","ring":"sent"}""")
    private val okWithoutID = Reply.Json("""{"status":"ok","ring":"sent"}""")
    private val gatewayTimeout = Reply.Json("""{"message":"upstream"}""", 504)

    private inner class Rig(val h: StoreHarness, val server: MessagesServer, val store: MessagesStore, val script: MutableList<Reply>) {
        val slept = mutableListOf<Double>()

        /** 전선에 나간 키(차례대로). */
        fun wireKeys(): List<String?> = h.storeRequests.filter { it.rpcName == "send_message" }.map {
            (SwiftJson.parse(it.bodyText) as JsonObject)["p_client_message_id"]?.jsonPrimitive?.content
        }

        fun sends(): Int = h.count("send_message")

        fun send(text: String, peer: String) {
            store.setDraft(text, peer)
            assertTrue(store.sendDraft(peer, isComposing = false))
        }
    }

    private suspend fun TestScope.rig(): Rig {
        val server = MessagesServer()
        val script = mutableListOf<Reply>()
        val h = StoreHarness(this) { r ->
            if (r.rpcName == "send_message" && script.isNotEmpty()) script.removeAt(0) else server.route(r)
        }
        h.signIn()
        var serial = 0
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { serial += 1; "key-$serial" })
        val rig = Rig(h, server, store, script)
        store.sleep = { seconds -> rig.slept += seconds }
        store.appDidBecomeActive()
        advanceUntilIdle()
        return rig
    }

    /** message_id 를 실은 ok 를 한 번 받아 "키를 아는 서버" 증거를 세운다. */
    private fun TestScope.prime(rig: Rig) {
        rig.script += okWithID
        rig.send("증거", peerB)
        advanceUntilIdle()
        assertTrue(rig.store.serverKnowsSendKey, "message_id 를 실은 ok 가 증거로 안 셌다")
        assertEquals(emptyList(), rig.store.pendingOutgoing)
    }

    @Test
    fun keyIsThePendingBubbleIDAndAnOkWithoutMessageIDIsNotEvidence() = runTest {
        val r = rig()
        r.script += okWithoutID
        r.send("첫 말", peerA)
        val bubble = r.store.pendingOutgoing.single().id
        advanceUntilIdle()
        assertEquals(listOf<String?>(bubble), r.wireKeys())
        assertFalse(r.store.serverKnowsSendKey, "message_id 없는 ok 를 증거로 셌다")
        assertTrue(r.store.unconfirmedSends.isEmpty(), "확정 답(ok)을 받은 전송을 기억했다")
    }

    @Test
    fun ambiguousFailureRetriesOnceWithSameKeyOnlyAfterEvidence() = runTest {
        val r = rig()
        prime(r)
        val before = r.sends()
        r.script += listOf(gatewayTimeout, okWithID)
        r.send("다시 간다", peerA)
        val bubble = r.store.pendingOutgoing.single().id
        advanceUntilIdle()
        assertEquals(2, r.sends() - before)
        assertEquals(listOf<String?>(bubble, bubble), r.wireKeys().takeLast(2), "재시도 전선 키")
        assertEquals(listOf(1.5), r.slept, "재시도 잠")
        assertEquals(null, r.store.sendNotices[peerA])
        assertEquals("", r.store.draft(peerA), "성공했는데 글이 입력칸으로 돌아왔다")
        assertTrue(r.store.unconfirmedSends.isEmpty(), "성공한 전송을 기억했다")
    }

    @Test
    fun retryIsBoundedAndOnlyForAmbiguousFailures() = runTest {
        val r = rig()
        prime(r)
        // 504·504 → 요청 2건 뒤 연결 문구 · 글 되돌림.
        var before = r.sends()
        r.script += listOf(gatewayTimeout, gatewayTimeout)
        r.send("두 번 다 잃는다", peerA)
        advanceUntilIdle()
        assertEquals(2, r.sends() - before, "재시도가 한 번이 아니다")
        assertEquals(MessagesSendRules.connectionNotice, r.store.sendNotices[peerA])
        assertEquals("두 번 다 잃는다", r.store.draft(peerA))
        assertEquals(emptyList(), r.store.pendingOutgoing)
        assertEquals(listOf(1.5), r.slept)
        // 전송 실패(오프라인)도 모호한 실패다 — ok 로 이어진다.
        before = r.sends()
        r.script += listOf(Reply.Offline, okWithID)
        r.send("오프라인", peerB)
        advanceUntilIdle()
        assertEquals(2, r.sends() - before)
        assertEquals(null, r.store.sendNotices[peerB])
        // 429 는 답을 준 것 — 되치지 않는다.
        before = r.sends()
        r.script += Reply.Json("""{"message":"rate"}""", 429)
        r.send("429", peerB)
        advanceUntilIdle()
        assertEquals(1, r.sends() - before, "429 를 되쳤다")
        // 거절 status 도 되치지 않는다.
        before = r.sends()
        r.script += Reply.Json("""{"status":"target_focused"}""")
        r.send("거절", peerB)
        advanceUntilIdle()
        assertEquals(1, r.sends() - before, "거절 status 를 되쳤다")
        assertEquals(listOf(1.5, 1.5), r.slept, "확정 실패에 재시도 잠이 들었다")
    }

    @Test
    fun noEvidenceMeansNoRetry() = runTest {
        val r = rig()
        // 첫 전송 — 증거가 없다.
        r.script += gatewayTimeout
        r.send("첫 말을 잃는다", peerA)
        advanceUntilIdle()
        assertEquals(1, r.sends(), "증거 없이 재시도했다")
        assertEquals(MessagesSendRules.connectionNotice, r.store.sendNotices[peerA])
        assertEquals("첫 말을 잃는다", r.store.draft(peerA))
        assertEquals(emptyList(), r.store.pendingOutgoing)
        // message_id 없는 ok 는 세웠던 깃발도 내린다(되돌린 서버) — 그 뒤에는 재시도하지 않는다.
        prime(r)
        r.script += okWithoutID
        r.send("옛 서버", peerB)
        advanceUntilIdle()
        assertFalse(r.store.serverKnowsSendKey)
        val before = r.sends()
        r.script += Reply.Offline
        r.send("시간 초과", peerB)
        advanceUntilIdle()
        assertEquals(1, r.sends() - before, "옛 서버에서 재시도했다 — 키를 모르는 서버면 두 통이 된다")
        assertEquals("시간 초과", r.store.draft(peerB))
        assertTrue(r.slept.isEmpty(), "증거 없이 재시도 잠에 들었다")
    }

    @Test
    fun manualResendAfterAmbiguousFailureReusesKey() = runTest {
        val r = rig()
        suspend fun TestScope.sendOnce(text: String, peer: String, reply: Reply): String? {
            r.script += reply
            r.send(text, peer)
            advanceUntilIdle()
            return r.wireKeys().last()
        }
        val k1 = sendOnce("같은 말", peerA, Reply.Offline)
        assertEquals("같은 말", r.store.draft(peerA), "실패한 글이 입력칸으로 안 돌아왔다")
        // 되돌아온 글을 그대로 다시 보낸다([보내기] 재탭).
        r.script += Reply.Offline
        assertTrue(r.store.sendDraft(peerA, isComposing = false))
        advanceUntilIdle()
        assertEquals(k1, r.wireKeys().last(), "같은 상대·같은 본문 재전송이 새 키를 만들었다")
        val k2 = sendOnce("다른 말", peerA, Reply.Offline)
        assertNotEquals(k1, k2, "다른 본문이 앞 키를 썼다")
        val k3 = sendOnce("같은 말", peerB, Reply.Offline)
        assertTrue(k3 != k1 && k3 != k2, "다른 상대가 앞 키를 썼다")
        assertEquals(3, r.store.unconfirmedSends.size)
        // 기억한 키로 다시 보냈는데 서버가 확정 거절 → 기억을 지운다 → 다음은 새 키.
        assertEquals(k1, sendOnce("같은 말", peerA, Reply.Json("""{"status":"too_long","max_length":3}""")), "다른 전송 뒤에도 기억이 남아야 한다")
        val k4 = sendOnce("같은 말", peerA, okWithoutID)
        assertTrue(k4 !in listOf(k1, k2, k3), "확정 거절 뒤 재전송이 옛 키를 썼다")
        // 기억한 키로 다시 보내 성공 → 기억을 지운다 → 같은 말을 또 보내면 새 키.
        assertEquals(k2, sendOnce("다른 말", peerA, okWithoutID))
        val k7 = sendOnce("다른 말", peerA, okWithoutID)
        assertNotEquals(k2, k7, "성공한 뒤의 같은 말이 옛 키를 썼다 — 서버가 duplicate 로 삼킨다")
        // 10분이 지나면 잊는다(상대 B 의 "같은 말"은 아직 기억에 있다).
        assertEquals(listOf(k3), r.store.unconfirmedSends.map { it.key })
        r.h.clockShift += r.store.unconfirmedSendReuseSeconds + 1
        val k8 = sendOnce("같은 말", peerB, okWithoutID)
        assertNotEquals(k3, k8, "10분 지난 기억의 키를 썼다")
        assertTrue(r.store.unconfirmedSends.isEmpty())
    }

    /** ⑤ 이모티콘: 504→ok 재시도 성공 · 504→504 실패 모두 쓰던 글 그대로 · 빈 입력칸에 토큰을 안 꽂는다. */
    @Test
    fun stickerRetryNeverTouchesTheDraft() = runTest {
        val r = rig()
        prime(r)
        r.store.setDraft("쓰던 글", peerA)
        r.script += listOf(gatewayTimeout, okWithID)
        assertTrue(r.store.sendSticker(AingSticker.joy, peerA))
        val bubble = r.store.pendingOutgoing.single().id
        advanceUntilIdle()
        assertEquals(listOf<String?>(bubble, bubble), r.wireKeys().takeLast(2), "이모티콘 재시도 전선 키")
        assertEquals("쓰던 글", r.store.draft(peerA), "이모티콘 재시도가 쓰던 글을 건드렸다")
        r.script += listOf(gatewayTimeout, gatewayTimeout)
        assertTrue(r.store.sendSticker(AingSticker.joy, peerA))
        advanceUntilIdle()
        assertEquals("쓰던 글", r.store.draft(peerA), "이모티콘 실패가 쓰던 글을 건드렸다")
        assertEquals(MessagesSendRules.connectionNotice, r.store.sendNotices[peerA])
        // 빈 입력칸에도 토큰이 안 꽂힌다.
        r.script += listOf(gatewayTimeout, gatewayTimeout)
        assertTrue(r.store.sendSticker(AingSticker.joy, peerB))
        advanceUntilIdle()
        assertEquals("", r.store.draft(peerB), "이모티콘 실패가 빈 입력칸에 토큰을 꽂았다")
    }

    /** 앞 계정 값이 다음 계정에 서지 않았는가(⑥ · ⑥' 의 공통 끝 단언). */
    private fun assertNothingLeaked(r: Rig) {
        assertTrue(r.store.drafts.isEmpty(), "앞 계정의 글이 남았다: ${r.store.drafts}")
        assertTrue(r.store.sendNotices.isEmpty(), "앞 계정의 문구가 남았다: ${r.store.sendNotices}")
        assertEquals(emptyList(), r.store.pendingOutgoing, "앞 계정의 말풍선이 남았다")
        assertTrue(r.store.unconfirmedSends.isEmpty(), "앞 계정의 전송 기억이 남았다")
        assertFalse(r.store.serverKnowsSendKey, "로그아웃이 증거 깃발을 안 지웠다 — 다음 계정이 증거 없이 재시도한다")
        assertFalse(r.store.isSending, "앞 계정의 전송 중 표시가 남았다")
    }

    /** ⑥ 재시도 잠 동안 로그아웃(세대 변화) — 두 번째 요청이 나가지 않고, 깃발·기억·글·문구·말풍선이 다음 계정에 안 선다. */
    @Test
    fun logoutDuringRetryWaitStopsTheSecondRequest() = runTest {
        val r = rig()
        prime(r)
        val gate = CompletableDeferred<Unit>()
        var arrivals = 0
        r.store.sleep = { seconds ->
            if (seconds == r.store.sendRetryDelaySeconds) {
                arrivals += 1
                gate.await()
            }
        }
        val before = r.sends()
        r.script += gatewayTimeout
        r.send("앞 계정의 글", peerA)
        advanceUntilIdle()
        assertEquals(1, arrivals, "504 뒤 재시도 잠에 들지 않았다")
        assertEquals(1, r.sends() - before)
        assertTrue(r.store.isSending, "재시도 잠 전에 왕복이 끝나 아래 단언이 공허하다")

        r.h.session.signOut()
        advanceUntilIdle()
        r.store.reset()
        assertFalse(r.store.serverKnowsSendKey, "로그아웃이 증거 깃발을 안 지웠다")
        // 잠을 풀고, 혹시 나갈 두 번째 요청이 스텁에 닿을 시간을 준다.
        r.script += gatewayTimeout
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(1, r.sends() - before, "로그아웃 뒤 재시도가 나갔다")
        assertNothingLeaked(r)
    }

    /** ⑥' 재시도 요청(두 번째)이 떠 있는 동안 로그아웃 — 그 늦은 504 가 다음 계정의 입력칸·문구·말풍선·기억·깃발에 안 선다. */
    @Test
    fun logoutDuringRetryRoundTripDoesNotLeak() = runTest {
        val r = rig()
        prime(r)
        val gate = CompletableDeferred<Unit>()
        val before = r.sends()
        r.script += listOf(gatewayTimeout, Reply.Gate(gate, gatewayTimeout))
        r.send("앞 계정의 글", peerA)
        runCurrent()
        // 재시도 잠(주입 — 곧바로 돌아온다) 뒤 두 번째 요청이 문에 붙잡힐 때까지만 민다. 시간을 밀면 붙잡힌 요청이 HTTP 시한에 걸린다.
        var turns = 0
        while (r.sends() - before < 2 && turns < 50) {
            runCurrent()
            turns += 1
        }
        assertEquals(2, r.sends() - before, "재시도 요청이 떠나지 않았다")
        assertTrue(r.store.isSending, "재시도 왕복이 로그아웃 전에 끝나 아래 단언이 공허하다")

        r.h.session.signOut()
        runCurrent()
        r.store.reset()
        runCurrent()
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(2, r.sends() - before)
        assertNothingLeaked(r)
    }

    /** ⑦ 답을 못 받은 말이 실은 저장됐고 이력에도 이미 섰을 때 — 같은 키 재전송의 duplicate 응답 뒤 그 말은 한 번만 보이고 자리 말풍선이 안 남는다. */
    @Test
    fun duplicateResponseLeavesExactlyOneMessage() = runTest {
        val r = rig()
        // 서버는 저장했는데 답이 끊겼다(증거 없음 → 재시도 없이 실패 · 글 되돌림 · 키 기억).
        r.script += Reply.Offline
        r.send("저장된 말", peerA)
        advanceUntilIdle()
        val k1 = r.wireKeys().last()
        assertEquals("저장된 말", r.store.draft(peerA))
        r.server.sent("m1", peerA, 60, body = "저장된 말")
        // 그 사이 이력이 한 번 돌아 행이 이미 화면에 있다 — 다음 이력엔 "처음 나타난" 행이 없는 가장 까다로운 쪽.
        r.store.requestActivityRefresh(includeHistory = true)
        advanceUntilIdle()
        assertEquals(listOf("m1"), r.store.thread(peerA)?.messages?.map { it.id })

        r.script += Reply.Json("""{"status":"ok","body":"저장된 말","ring":"duplicate","message_id":"m1","created_at":"2026-09-17T04:57:40.000Z","duplicate":true}""")
        assertTrue(r.store.sendDraft(peerA, isComposing = false))
        advanceUntilIdle()
        assertEquals(k1, r.wireKeys().last(), "되돌아온 글의 재전송이 새 키를 만들었다 — 서버가 두 통으로 둔다")
        assertEquals(emptyList(), r.store.pendingOutgoing, "duplicate 응답 뒤 자리 말풍선이 남았다")
        assertEquals(listOf("m1"), r.store.thread(peerA)?.messages?.map { it.id })
        assertEquals(null, r.store.sendNotices[peerA])
        assertEquals("", r.store.draft(peerA))
        assertTrue(r.store.unconfirmedSends.isEmpty())
        assertTrue(r.store.serverKnowsSendKey, "duplicate 응답도 키를 안다는 증거다")
    }

    /** ⑧ 재시도 잠 동안 같은 대화에 새 말을 보내려 하면 — 글·이모티콘 모두 막히고 새로 친 글은 입력칸에 남으며, 재시도까지 실패해도 옛 글이 덮지 않는다. */
    @Test
    fun newInputDuringRetryIsKept() = runTest {
        val r = rig()
        prime(r)
        val gate = CompletableDeferred<Unit>()
        var arrivals = 0
        r.store.sleep = { seconds ->
            if (seconds == r.store.sendRetryDelaySeconds) {
                arrivals += 1
                gate.await()
            }
        }
        val before = r.sends()
        r.script += listOf(gatewayTimeout, gatewayTimeout)
        r.send("옛 글", peerA)
        val bubble = r.store.pendingOutgoing.single().id
        advanceUntilIdle()
        assertEquals(1, arrivals)
        r.store.setDraft("새로 친 글", peerA)
        assertFalse(r.store.canSend(peerA))
        assertFalse(r.store.sendDraft(peerA, isComposing = false), "재시도 중에 두 번째 전송이 떴다")
        assertFalse(r.store.sendSticker(AingSticker.joy, peerA), "재시도 중에 이모티콘이 떴다")
        assertEquals("새로 친 글", r.store.draft(peerA), "막힌 전송이 새로 친 글을 지웠다")
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(2, r.sends() - before)
        assertEquals("새로 친 글", r.store.draft(peerA), "실패한 옛 글이 새로 친 글을 덮었다")
        assertEquals(MessagesSendRules.connectionNotice, r.store.sendNotices[peerA])
        assertEquals(emptyList(), r.store.pendingOutgoing)
        assertEquals(listOf(bubble), r.store.unconfirmedSends.map { it.key })
        assertEquals("옛 글", r.store.unconfirmedSends.first().body)
    }

    /** ⑨ 되돌린 서버(키를 모름) — 증거 뒤라도 message_id 없는 ok 를 보면 깃발을 내리고, 다음 모호한 실패는 재시도하지 않는다. 거절 status 는 깃발을 바꾸지 않는다. */
    @Test
    fun okWithoutMessageIDLowersTheFlagAndRejectionDoesNot() = runTest {
        val r = rig()
        prime(r)
        r.script += okWithoutID
        r.send("되돌린 뒤 첫 말", peerA)
        advanceUntilIdle()
        assertFalse(r.store.serverKnowsSendKey, "키를 모르는 판의 ok 뒤에도 깃발이 섰다 — 재시도가 두 통을 만든다")
        val before = r.sends()
        r.script += gatewayTimeout
        r.send("되돌린 뒤 둘째 말", peerA)
        advanceUntilIdle()
        assertEquals(1, r.sends() - before, "키를 모르는 판에서 재시도했다")
        assertTrue(r.slept.isEmpty())
        // 확정 거절(status)은 증거를 바꾸지 않는다 — 서버 판은 ok 로만 잰다.
        prime(r)
        r.script += Reply.Json("""{"status":"target_focused"}""")
        r.send("거절", peerA)
        advanceUntilIdle()
        assertTrue(r.store.serverKnowsSendKey, "거절 status 가 깃발을 내렸다")
    }

    /** 분류: 답을 못 받은 실패만 모호하다 — 취소·401(토큰 갱신 실패 뒤 원래 오류)·429·4xx·디코드 실패는 확정. 여기서 새면 확정 실패를 되치거나 취소한 왕복을 되살린다. */
    @Test
    fun ambiguousFailureClassificationEdges() {
        for (error in listOf(
            kotlinx.io.IOException("timeout"),
            io.ktor.client.plugins.HttpRequestTimeoutException("https://golden.invalid", 1_000L),
        )) {
            assertTrue(MessagesSendRules.isAmbiguousFailure(error), "$error 를 확정으로 봤다")
        }
        for (status in listOf(500, 502, 503, 504)) {
            assertTrue(MessagesSendRules.isAmbiguousFailure(SupabaseWorkServiceError.InvalidResponse(status)), "$status 를 확정으로 봤다")
        }
        val definite = listOf(
            CancellationException("cancelled"),
            SupabaseWorkServiceError.SessionExpired,
            SupabaseWorkServiceError.RateLimited(null),
            SupabaseWorkServiceError.InvalidResponse(400),
            SupabaseWorkServiceError.InvalidResponse(404),
            SupabaseWorkServiceError.InvalidResponse(409),
            SupabaseWorkServiceError.InvalidResponse(-1),
            SupabaseWorkServiceError.SessionAlreadyOpen,
            SerializationException("200 인데 본문을 못 읽음"),
        )
        for (error in definite) {
            assertFalse(MessagesSendRules.isAmbiguousFailure(error), "$error 를 모호하다고 봐 되친다")
        }
    }
}
