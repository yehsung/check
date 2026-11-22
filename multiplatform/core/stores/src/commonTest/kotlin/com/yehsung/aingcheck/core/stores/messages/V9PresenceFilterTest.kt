// 원본: Tests/CheckMobileKitTests/V1019PresenceFilterTests.swift @ 777a0e31 (폰 1.0.19 — 거르기 칸)
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 판 9 — 사람 찾기 거르기 칸 '전체 · 근무중 · 자리비움'(맥 0.3.87 · 아이폰 1.0.19 · 대표 #d_xygj8oZRFlfH 9번). */
@OptIn(ExperimentalCoroutinesApi::class)
class V9PresenceFilterTest {
    private fun entry(id: String, working: Boolean) = PokeDirectoryEntry(userID = id, name = id, avatarURL = null, isWorking = working)

    @Test
    fun admitsLooksAtWorkingOnly() {
        val on = entry("on", true)
        val off = entry("off", false)
        assertTrue(MessagesPresenceFilter.all.admits(on) && MessagesPresenceFilter.all.admits(off))
        assertTrue(MessagesPresenceFilter.working.admits(on) && !MessagesPresenceFilter.working.admits(off))
        assertTrue(!MessagesPresenceFilter.away.admits(on) && MessagesPresenceFilter.away.admits(off))
        // 집중은 칸을 바꾸지 않는다 — 집중 켠 채 근무 중은 근무중 칸, 집중 켠 채 퇴근은 자리비움 칸.
        assertTrue(MessagesPresenceFilter.working.admits(on.copy(isFocused = true)))
        assertTrue(MessagesPresenceFilter.away.admits(off.copy(isFocused = true)))
    }

    @Test
    fun copyMatchesMacAndIPhone() {
        assertEquals(listOf("전체", "근무중", "자리비움"), MessagesPresenceFilter.entries.map { it.label })
        assertEquals("지금 근무 중인 사람이 없어요", MessagesPresenceFilterText.empty(MessagesPresenceFilter.working, false))
        assertEquals("자리를 비운 사람이 없어요", MessagesPresenceFilterText.empty(MessagesPresenceFilter.away, false))
        assertEquals("근무 중인 사람 중엔 맞는 이름이 없어요", MessagesPresenceFilterText.empty(MessagesPresenceFilter.working, true))
        assertEquals("자리를 비운 사람 중엔 맞는 이름이 없어요", MessagesPresenceFilterText.empty(MessagesPresenceFilter.away, true))
        assertNull(MessagesPresenceFilterText.empty(MessagesPresenceFilter.all, true))
        assertNull(MessagesPresenceFilterText.empty(MessagesPresenceFilter.all, false))
    }

    private fun row(id: String, name: String, working: Boolean): String =
        """{"user_id":"$id","display_name":"$name","avatar_url":null,"is_working":$working,"message_capable":true,"center":null,"status_message":null,"focus_mode":false}"""

    @Test
    fun storeSubtractsKeepsOrderAndsWithSearchAndResetsOnSignOut() = runTest {
        val server = MessagesServer().also {
            it.directory = "[" + listOf(row("peer-ga", "가나", false), row("peer-na", "나나", true), row("peer-da", "다나", true), row("peer-ra", "라마", false))
                .joinToString(",") + "]"
        }
        val h = StoreHarness(this) { r -> server.route(r) }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" })
        store.loadDirectory(force = true)
        advanceUntilIdle()
        val all = store.filteredDirectory("").map { it.name }
        assertEquals(listOf("나나", "다나", "가나", "라마"), all, "전제: 근무 중 먼저 → 이름순")
        assertEquals(MessagesPresenceFilter.all, store.directoryPresenceFilter)
        assertEquals(all, store.visibleDirectory("").map { it.name })
        val before = h.storeRequests.size

        store.selectDirectoryPresenceFilter(MessagesPresenceFilter.working)
        assertEquals(listOf("나나", "다나"), store.visibleDirectory("").map { it.name })
        assertEquals(listOf("나나"), store.visibleDirectory("나나").map { it.name }, "이름 찾기와 AND 가 아니다")
        assertTrue(store.visibleDirectory("ㄱ").isEmpty(), "자리비움인 가나가 근무중 칸에 섰다")
        store.selectDirectoryPresenceFilter(MessagesPresenceFilter.away)
        assertEquals(listOf("가나", "라마"), store.visibleDirectory("").map { it.name })
        assertTrue(store.visibleDirectory("다").isEmpty())
        advanceUntilIdle()
        assertEquals(before, h.storeRequests.size, "칸 고르기가 네트워크를 불렀다")

        store.reset()
        assertEquals(MessagesPresenceFilter.all, store.directoryPresenceFilter, "로그아웃 뒤에도 칸이 남았다")
    }
}
