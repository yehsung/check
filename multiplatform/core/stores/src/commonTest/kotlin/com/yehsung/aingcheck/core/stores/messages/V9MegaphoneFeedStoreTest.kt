// 원본: Tests/checkTests/MegaphoneFeedTests.swift @ main 341eb4e3 (지난 확성기 — 요청 키 · 커서 · 디코드 · 더 보기 · 문 · 세대 · 꼬리 · 놓친 신호 · 운영자 내리기)
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedItem
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedPage
import com.yehsung.aingcheck.core.rules.text.MegaphoneFeedText
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 판 9 — 지난 확성기 스토어(맥 0.3.86 · 아이폰 1.0.19 와 같은 코어). */
@OptIn(ExperimentalCoroutinesApi::class)
class V9MegaphoneFeedStoreTest {
    private class Host(private val store: SessionStore) : SessionHost {
        override val session: SupabaseSession? get() = store.session
        override val sessionGeneration: Int get() = store.sessionGeneration
        override val service: SupabaseWorkService get() = store.service
        override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = store.withSessionRetry(operation)
    }

    private val other = "33333333-3333-4333-8333-333333333333"

    private fun row(id: String, us: Long, sender: String = other, body: String = "모두 안녕", mine: Boolean? = false): String =
        """{"megaphone_id":"$id","sender_id":"$sender","sender_display_name":"보낸이","sender_avatar_url":null,"body":"$body",""" +
            """"recipients":46,"is_mine":${mine ?: "null"},"created_epoch_ms":${us / 1000},"created_epoch_us":$us}"""

    private fun array(vararg rows: String) = Reply.Json("[" + rows.joinToString(",") + "]")

    private suspend fun TestScope.make(pageSize: Int = 2, route: (Map<String, Any?>) -> Reply): Pair<StoreHarness, MegaphoneFeedStore> {
        val h = StoreHarness(this) { r ->
            if (r.rpcName == "megaphone_feed" || r.rpcName == "megaphone_admin_hide") {
                val body = SwiftJson.parse(r.bodyText) as JsonObject
                route(mapOf("rpc" to r.rpcName) + body.mapValues { (_, v) -> if (v is JsonNull) null else v.jsonPrimitive.content })
            } else null
        }
        h.signIn()
        val store = MegaphoneFeedStore(Host(h.session), h.storeScope).also { it.pageSize = pageSize }
        return h to store
    }

    private fun bodies(h: StoreHarness, rpc: String): List<JsonObject> =
        h.storeRequests.filter { it.rpcName == rpc }.map { SwiftJson.parse(it.bodyText) as JsonObject }

    @Test
    fun requestKeysAreExactAndTheCursorIsTheOldestMicros() = runTest {
        val big = 9_007_199_254_740_993L // 2^53 + 1 — 실수로 지나면 끝자리가 바뀐다
        val (h, store) = make { b ->
            if (b["p_before_us"] == null) array(row("m3", big + 2), row("m2", big)) else array(row("m1", big - 5))
        }
        store.open()
        advanceUntilIdle()
        assertEquals(listOf("m3", "m2"), store.items.map { it.id })
        assertTrue(store.hasMore, "가득 찬 쪽(2 = 쪽 크기)이면 더 있다")
        store.loadMore()
        advanceUntilIdle()
        val sent = bodies(h, "megaphone_feed")
        assertEquals(setOf("p_before_us", "p_limit"), sent[0].keys, "키는 정확히 둘")
        assertEquals(JsonNull, sent[0]["p_before_us"], "첫 쪽은 명시적 null")
        assertEquals(big.toString(), sent[1].getValue("p_before_us").jsonPrimitive.content, "다음 쪽 커서는 마지막 줄의 µs 그대로(2^53+1)")
        assertEquals(listOf("m3", "m2", "m1"), store.items.map { it.id })
        assertFalse(store.hasMore, "덜 찬 쪽이면 끝")
    }

    @Test
    fun decodeKeepsBodyAndDropsBrokenRowsOnly() = runTest {
        val (_, store) = make(pageSize = 30) {
            Reply.Json("[" + row("m2", 2_000_000L, body = "📢 그대로") + """,{"megaphone_id":"bad","created_epoch_us":"x"},""" + row("m1", 1_000_000L, mine = null, sender = "SELF") + "]")
        }
        store.open()
        advanceUntilIdle()
        assertEquals(listOf("m2", "m1"), store.items.map { it.id }, "깨진 줄만 빠진다")
        assertEquals("📢 그대로", store.items[0].body, "서버가 머리말을 이미 뗐다 — 다시 떼지 않는다")
        assertEquals(46L, store.items[0].recipients)
        assertEquals(MegaphoneFeedText.recipients(46), "46명에게")
    }

    @Test
    fun missingFunctionClosesTheDoorAndRearmReopensWithoutARequest() = runTest {
        var missing = true
        val (h, store) = make { if (missing) Reply.missingFunction else array(row("m1", 1L)) }
        store.open()
        advanceUntilIdle()
        assertEquals(false, store.isAvailable, "함수 없음 → 닫힘")
        val before = h.storeRequests.size
        store.rearm()
        assertNull(store.isAvailable, "rearm 은 모름으로")
        assertEquals(before, h.storeRequests.size, "rearm 은 요청을 안 낸다")
        missing = false
        store.open()
        advanceUntilIdle()
        assertEquals(true, store.isAvailable)
    }

    @Test
    fun transportFailureKeepsTheDoor() = runTest {
        var offline = false
        val (_, store) = make { if (offline) Reply.Offline else array(row("m1", 1L)) }
        store.open()
        advanceUntilIdle()
        offline = true
        store.refresh()
        advanceUntilIdle()
        assertEquals(true, store.isAvailable, "연결 실패는 문을 안 건드린다")
        assertTrue(store.loadFailed)
        assertEquals(listOf("m1"), store.items.map { it.id }, "받아 둔 줄은 그대로")
    }

    @Test
    fun resetDiscardsInFlightResponses() = runTest {
        val gate = CompletableDeferred<Unit>()
        val (_, store) = make { Reply.Gate(gate, array(row("m1", 1L))) }
        store.open()
        runCurrent()
        store.reset()
        gate.complete(Unit)
        advanceUntilIdle()
        assertTrue(store.items.isEmpty(), "reset 뒤 도착한 응답이 목록에 들었다")
        assertFalse(store.hasLoaded)
    }

    @Test
    fun liveRefreshKeepsTheLoadedTailButReopenReplacesIt() = runTest {
        val first = array(row("m4", 4L), row("m3", 3L))
        val (_, store) = make { b -> if (b["p_before_us"] == null) first else array(row("m2", 2L), row("m1", 1L)) }
        store.open()
        advanceUntilIdle()
        store.loadMore()
        advanceUntilIdle()
        assertEquals(listOf("m4", "m3", "m2", "m1"), store.items.map { it.id })
        store.refresh() // 떠 있는 동안의 실시간 새로고침
        advanceUntilIdle()
        assertEquals(listOf("m4", "m3", "m2", "m1"), store.items.map { it.id }, "읽던 꼬리를 날렸다")
        store.close()
        store.open() // 새로 열면 첫 쪽으로 갈아 끼운다
        advanceUntilIdle()
        assertEquals(listOf("m4", "m3"), store.items.map { it.id }, "다시 열었는데 옛 꼬리가 남았다")
    }

    @Test
    fun missedSignalRefreshesOnceOnReturn() = runTest {
        val (h, store) = make { array(row("m1", 1L)) }
        store.noteMissedSignal()
        assertFalse(store.missedSignal, "닫힌 페이지는 표시를 세우지 않는다")
        store.open()
        advanceUntilIdle()
        val before = h.storeRequests.count { it.rpcName == "megaphone_feed" }
        store.noteMissedSignal()
        store.refreshIfMissedSignal()
        store.refreshIfMissedSignal()
        advanceUntilIdle()
        assertEquals(before + 1, h.storeRequests.count { it.rpcName == "megaphone_feed" }, "다시 보일 때 한 번만 읽는다")
    }

    @Test
    fun adminHideSendsExactKeysAndRemovesOnlyOnSuccess() = runTest {
        var status = "forbidden"
        val (h, store) = make { b ->
            if (b["rpc"] == "megaphone_admin_hide") Reply.Json("""{"status":"$status","hidden":true}""") else array(row("m2", 2L), row("m1", 1L))
        }
        store.open()
        advanceUntilIdle()
        store.adminHide("m2")
        store.adminHide("m2") // 겹쳐 누르기 — 한 건
        advanceUntilIdle()
        assertEquals(1, h.storeRequests.count { it.rpcName == "megaphone_admin_hide" })
        assertEquals(MegaphoneFeedText.adminForbidden, store.notice?.text)
        assertEquals(listOf("m2", "m1"), store.items.map { it.id }, "forbidden 인데 줄을 뺐다")
        status = "not_found"
        store.adminHide("m2")
        advanceUntilIdle()
        val body = bodies(h, "megaphone_admin_hide").last()
        assertEquals(setOf("p_id", "p_hidden"), body.keys)
        assertEquals("true", body.getValue("p_hidden").jsonPrimitive.content)
        assertEquals(listOf("m1"), store.items.map { it.id }, "이미 없는 글(not_found)도 목록에서 뺀다")
    }

    @Test
    fun firstPageApplyIsPure() {
        val store = MegaphoneFeedStore(null, TestScope())
        val item = { id: String, us: Long -> MegaphoneFeedItem(id, null, "보낸이", null, "말", null, SwiftDate.fromEpochMillis(us / 1000), us) }
        store.applyFirstPage(MegaphoneFeedPage(listOf(item("a", 2L)), hasMore = true))
        assertEquals(true, store.isAvailable)
        assertTrue(store.hasLoaded && store.hasMore)
        store.applyFirstPage(MegaphoneFeedPage(emptyList(), hasMore = true))
        assertFalse(store.hasMore, "빈 쪽에는 더 보기가 없다")
    }
}
