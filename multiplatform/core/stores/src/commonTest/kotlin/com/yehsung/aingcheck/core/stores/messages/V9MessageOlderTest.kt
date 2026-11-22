// 원본: Tests/CheckMobileKitTests/V1019MessageOlderTests.swift @ 7142916e (폰 1.0.19 — 이전 대화 더 보기)
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.MessageNoticeText
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 판 9 — 이전 대화 더 보기(메시지 30일 보관 · message_page · 대표 #d_xygj8oZRFlfH 4번). */
@OptIn(ExperimentalCoroutinesApi::class)
class V9MessageOlderTest {
    private val peer = "11111111-aaaa-4aaa-8aaa-000000000001"

    private fun pageRow(id: String, mine: Boolean, epochSeconds: Long): String {
        val from = if (mine) StoreHarness.ME else peer
        val to = if (mine) peer else StoreHarness.ME
        return """{"id":"$id","from_user":"$from","to_user":"$to","body":"옛 말 $id","is_megaphone":false,"is_mine":$mine,""" +
            """"created_epoch_ms":${epochSeconds * 1000},"created_epoch_us":${epochSeconds * 1_000_000},"read_by_peer":true,"unread_for_me":true}"""
    }

    @Test
    fun loadsOlderPageWithoutTouchingUnreadAndClearsOnClose() = runTest {
        val server = MessagesServer()
        server.received("head-1", peer, at = 10)
        val base = server.base
        val h = StoreHarness(this) { r ->
            if (r.rpcName == "message_page") Reply.Json("[" + pageRow("old-2", true, base - 90_000) + "," + pageRow("old-1", false, base - 100_000) + "]")
            else server.route(r)
        }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" })
        store.listDidAppear()
        advanceUntilIdle()
        store.conversationDidAppear(peer, "t1")
        advanceUntilIdle()
        assertEquals(0, h.count("message_page"), "대화를 열기만 했는데 지난 쪽을 불렀다")
        assertEquals(MessagesOlderRowState.button, store.olderRowState(peer))
        assertEquals(MessageNoticeText.expiry, store.expiryNotice, "성공 전에는 24시간 문장")
        val unreadBefore = store.badgeCount

        store.loadOlderMessages(peer)
        advanceUntilIdle()
        val body = h.storeRequests.first { it.rpcName == "message_page" }.bodyText
        assertTrue(body.contains("\"p_peer\":\"$peer\"") && body.contains("\"p_before_us\":null") && body.contains("\"p_limit\":50"), body)
        assertEquals(listOf("old-1", "old-2", "head-1"), store.conversationMessages(peer).map { it.id })
        assertEquals(unreadBefore, store.badgeCount, "지난 쪽의 받은 말이 안 읽음으로 셌다")
        assertEquals(MessageNoticeText.storeExpiry, store.expiryNotice)
        assertEquals(MessagesOlderRowState.end, store.olderRowState(peer), "상한(50)보다 적게 왔으면 끝이다")
        assertTrue(store.conversationItems(peer).any { it.id == "old-1" }, "대화 줄이 지난 쪽을 안 잇는다")

        store.conversationDidDisappear("t1")
        assertTrue(store.olderPages.isEmpty() && store.olderHasMore.isEmpty(), "대화를 닫았는데 지난 쪽이 남았다")
    }

    @Test
    fun missingFunctionHidesRowAndReopenRearmsWithoutARequest() = runTest {
        val server = MessagesServer()
        server.received("head-1", peer, at = 10)
        val h = StoreHarness(this) { r -> if (r.rpcName == "message_page") Reply.missingFunction else server.route(r) }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" })
        store.conversationDidAppear(peer, "t1")
        advanceUntilIdle()
        store.loadOlderMessages(peer)
        advanceUntilIdle()
        assertEquals(false, store.olderAvailable)
        assertNull(store.olderRowState(peer))
        assertFalse(store.olderFailed, "함수 없음을 [다시 시도]로 그렸다")
        store.conversationDidDisappear("t1")
        val calls = h.count("message_page")
        store.conversationDidAppear(peer, "t2")
        assertEquals(MessagesOlderRowState.button, store.olderRowState(peer))
        assertEquals(calls, h.count("message_page"), "다시 세우며 요청을 냈다")
    }

    @Test
    fun photoOnlyOlderLineReadsAsFallbackText() = runTest {
        val server = MessagesServer()
        server.received("head-1", peer, at = 10)
        val base = server.base
        val photo = """{"id":"p-1","from_user":"$peer","to_user":"${StoreHarness.ME}","body":"📷 사진","caption":null,""" +
            """"photo_path":"${peer}/22222222-2222-4222-8222-222222222222.jpg","photo_width":1600,"photo_height":1200,"is_megaphone":false,"is_mine":false,""" +
            """"created_epoch_ms":${(base - 90_000) * 1000},"created_epoch_us":${(base - 90_000) * 1_000_000}}"""
        val h = StoreHarness(this) { r -> if (r.rpcName == "message_page") Reply.Json("[$photo]") else server.route(r) }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" })
        store.conversationDidAppear(peer, "t1")
        advanceUntilIdle()
        store.loadOlderMessages(peer)
        advanceUntilIdle()
        val line = store.conversationMessages(peer).first { it.id == "p-1" }
        assertTrue(line.wire.photo != null, "사진 칸이 실리지 않았다")
        assertEquals("📷 사진", line.body, "사진만 보낸 줄이 빈 말풍선으로 선다(대체 글이어야 한다)")
    }
}
