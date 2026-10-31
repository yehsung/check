// 원본: Tests/CheckMobileKitTests/MessagesSendIdempotencyTests.swift ①②②'③④ @ 1a5eeca6 — 전송 멱등 키(서버 20261101131000)
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
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
}
