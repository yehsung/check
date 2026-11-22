// 원본: Tests/CheckMobileKitTests/V1019MegaphoneFeedTests.swift @ 94975fa8 (폰 1.0.19 — 지난 확성기 줄 규칙 · 메시지 스토어 배선)
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedItem
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedText
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class V9MessagesMegaphoneFeedTest {
    private fun item(id: String, sender: String?, own: Boolean = false, recipients: Long? = 46) =
        MegaphoneFeedItem(id, sender, "보낸이", null, "📢 아닌 본문", recipients, SwiftDate(1_800_000_000.0), 1_800_000_000_000_000L, own)

    @Test
    fun rowRules() {
        assertEquals("peer-a", MessagesMegaphoneFeedRules.actionTarget(item("m1", "peer-a"), "me")?.peerID)
        assertNull(MessagesMegaphoneFeedRules.actionTarget(item("m2", "me", own = true), "me"))
        assertNull(MessagesMegaphoneFeedRules.actionTarget(item("m3", "ME"), "me"), "서버가 is_mine 을 틀려도 내 글이다")
        assertNull(MessagesMegaphoneFeedRules.actionTarget(item("m4", null), "me"))
        val now = SwiftDate(1_800_000_000.0)
        val time = MegaphoneFeedText.timeLabel(now, now, MessagesTime.kst)
        assertEquals("$time · 46명에게", MessagesMegaphoneFeedRules.metaText(item("m5", "a"), now))
        assertEquals(time, MessagesMegaphoneFeedRules.metaText(item("m6", "a", recipients = null), now))
    }

    private val feedRow =
        """[{"megaphone_id":"11111111-1111-1111-1111-111111111111","sender_id":"peer-a","sender_display_name":"가나","body":"안녕하세요",""" +
            """"recipients":46,"is_mine":false,"created_epoch_ms":1800000000000,"created_epoch_us":1800000000000000}]"""

    @Test
    fun storeOpensFirstPageFiltersBlockedAndResets() = runTest {
        val h = StoreHarness(this) { r -> if (r.rpcName == "megaphone_feed") Reply.Json(feedRow) else null }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, megaphoneHost = TestMegaphoneHost(h.session))
        assertTrue(store.showsMegaphoneFeedEntry, "모르면 문이 선다(누르면 그때 묻는다)")
        assertEquals(0, h.count("megaphone_feed"), "스토어를 만드는 것만으로 부르지 않는다")
        store.megaphoneFeed.open()
        advanceUntilIdle()
        val bodies = h.storeRequests.filter { it.rpcName == "megaphone_feed" }.map { it.bodyText }
        assertEquals(1, bodies.size)
        assertTrue(bodies[0].contains("\"p_before_us\":null") && bodies[0].contains("\"p_limit\":30"), bodies[0])
        assertEquals(listOf("가나"), store.visibleMegaphoneFeed.map { it.senderName })
        assertTrue(store.megaphoneFeed.isAvailable == true && store.megaphoneFeed.hasLoaded)
        store.hiddenBlockedPeerIDs = setOf("peer-a")
        assertTrue(store.visibleMegaphoneFeed.isEmpty(), "차단한 사람 글이 곧바로 빠지지 않았다")
        store.megaphoneFeed.close()
        store.reset()
        assertTrue(store.megaphoneFeed.items.isEmpty())
        assertNull(store.megaphoneFeed.isAvailable)
    }

    @Test
    fun doorClosedThenRearmedWithoutARequest() = runTest {
        val h = StoreHarness(this) { r -> if (r.rpcName == "megaphone_feed") Reply.missingFunction else null }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, megaphoneHost = TestMegaphoneHost(h.session))
        store.megaphoneFeed.open()
        advanceUntilIdle()
        assertEquals(false, store.megaphoneFeed.isAvailable)
        assertFalse(store.showsMegaphoneFeedEntry)
        store.megaphoneFeed.close()
        val before = h.count("megaphone_feed")
        store.megaphoneFeed.rearm()
        assertTrue(store.showsMegaphoneFeedEntry)
        assertEquals(before, h.count("megaphone_feed"), "rearm 은 요청 없이 문만 다시 세운다")
    }
}
