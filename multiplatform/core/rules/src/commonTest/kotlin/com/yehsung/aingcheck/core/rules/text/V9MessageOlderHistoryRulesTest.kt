// 원본: Tests/checkTests/MessageOlderHistoryTests.swift ③ · ⑥(머리가 이기는 잇기 · 읽음 따라가기 · 앞에 붙이기 · 미끄러짐 틈 메우기) @ main 341eb4e3
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.MessageHistoryEntry
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class V9MessageOlderHistoryRulesTest {
    private val now = SwiftDate(1_789_621_500.0)
    private fun e(id: String, secondsAgo: Double, mine: Boolean = false, read: Boolean? = null, unread: Boolean? = null, peer: String = "p") =
        MessageHistoryEntry(id, peer, "민수", null, "말 $id", now.addingTimeInterval(-secondsAgo), mine,
            readByPeer = if (mine) read else null, isUnread = if (mine) null else unread)

    @Test
    fun mergedLetsTheHeadWinAndDoesNotResort() {
        val head = listOf(e("h1", 100.0), e("h2", 50.0))
        val older = listOf(e("o1", 90_000.0), e("h1", 100.0), e("o1", 90_000.0))
        assertEquals(listOf("o1", "h1", "h2"), MessageOlderHistoryRules.merged(older, head).map { it.id })
        assertEquals(head, MessageOlderHistoryRules.merged(emptyList(), head))
    }

    @Test
    fun readFollowsTheHeadOnlyWhenTheHeadHasAReadMine() {
        val older = listOf(e("o1", 90_000.0, mine = true, read = false), e("o2", 89_000.0, mine = true, read = null))
        val unreadHead = listOf(e("h1", 10.0, mine = true, read = false))
        assertEquals(older, MessageOlderHistoryRules.readFollowingHead(older, unreadHead), "머리에 읽은 내 말이 없으면 그대로")
        val readHead = listOf(e("h1", 10.0, mine = true, read = true))
        val after = MessageOlderHistoryRules.readFollowingHead(older, readHead)
        assertEquals(true, after[0].readByPeer)
        assertNull(after[1].readByPeer, "모름(nil)은 그대로 둔다")
    }

    @Test
    fun prependingSkipsKnownAndNewerThanHeadAndClearsUnread() {
        val head = listOf(e("h1", 100.0), e("h2", 50.0))
        val older = listOf(e("o2", 80_000.0, unread = true))
        val page = listOf(e("o0", 95_000.0, unread = true), e("o1", 90_000.0), e("o2", 80_000.0), e("h1", 100.0), e("late", 0.0))
        val out = MessageOlderHistoryRules.prepending(page, older, head)
        assertEquals(listOf("o0", "o1", "o2"), out.map { it.id }, "머리 id · 받은 id · 머리보다 새 줄은 빠진다")
        assertNull(out.first().isUnread, "지난 쪽 모양은 안 읽음 칸을 비운다")
        assertNull(out.last().isUnread, "넘겨받은 기존 쪽도 지난 쪽 모양으로")
    }

    @Test
    fun headSlideCarriesOnlyTheWindowEdgeLeavers() {
        val previous = listOf(e("a", 86_500.0), e("b", 3_600.0), e("c", 60.0), e("x", 86_600.0, peer = "q"))
        val next = listOf(e("c", 60.0))
        val carried = MessageOlderHistoryRules.carriedAcrossHeadSlide("p", previous, next, emptyList(), now)
        assertEquals(listOf("a"), carried.map { it.id }, "24시간 경계를 넘은 줄만 옮긴다(1시간 전 b 는 서버가 다른 이유로 뺐다 · 남의 대화 x 는 안 옮긴다)")
    }
}
