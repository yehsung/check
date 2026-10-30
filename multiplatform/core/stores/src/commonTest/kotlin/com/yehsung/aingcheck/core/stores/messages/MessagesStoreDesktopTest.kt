// 원본: Sources/check/WorkTimerStoreMessages.swift `requestMessageActivityRefreshCoalesced`·`closeMessageActivityWindow`(724-761)
//       — Windows 공용 패치 8.
// 데스크톱(트레이 상주) 몫만 잰다. 폰 경로(realtimeMessageRead)는 MessagesStoreTest 가 그대로 잰다.
package com.yehsung.aingcheck.core.stores.messages

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MessagesStoreDesktopTest {
    private suspend fun TestScope.make(): Triple<StoreHarness, MessagesServer, MessagesStore> {
        val server = MessagesServer().also { it.received("a1", "peer-a", 0, unread = false) }
        val h = StoreHarness(this) { server.route(it) }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" })
        return Triple(h, server, store)
    }

    // ---------------------------------------------------------------- 8 · 읽음 신호 창

    @Test
    fun windowCloseRefreshesOnceEvenWhenAppInactive() = runTest {
        val (h, _, store) = make()
        assertFalse(store.isAppActive)
        store.readSignalArrived()
        store.readSignalArrived()
        assertTrue(store.isHistoryStale, "안 보이는 화면인데 신호 순간에 낡음을 안 적었다")
        assertNotNull(store.readSignalWindowClosed(), "창 안에 맡은 조회가 없는데 새로고침을 안 띄웠다")
        advanceUntilIdle()
        assertEquals(1, h.count("message_unread_summary"), "트레이 상주(앱 비활성)에서도 창 하나에 요약 한 번")
        assertEquals(0, h.count("message_history_with_pokes"))
        assertTrue(store.isHistoryStale)
        h.assertClean()
    }

    @Test
    fun windowCloseSkipsWhenLaterSummaryAlreadyAnswered() = runTest {
        val (h, _, store) = make()
        store.readSignalArrived()
        // 창이 열린 사이 신호 **뒤에** 띄운 요약(예: 플라이아웃 열기) — 이 계기의 답이다.
        store.performLoadSummary()
        assertEquals(1, h.count("message_unread_summary"))
        assertNull(store.readSignalWindowClosed(), "신호 뒤에 띄운 요약이 맡았는데 다시 물었다")
        advanceUntilIdle()
        assertEquals(1, h.count("message_unread_summary"))
        h.assertClean()
    }

    @Test
    fun summaryLaunchedBeforeSignalDoesNotCoverIt() = runTest {
        val (h, _, store) = make()
        store.performLoadSummary()
        store.readSignalArrived()
        assertNotNull(store.readSignalWindowClosed(), "신호 **앞에** 띄운 요약은 신호 뒤 변화를 못 본다")
        advanceUntilIdle()
        assertEquals(2, h.count("message_unread_summary"))
        h.assertClean()
    }

    @Test
    fun visibleScreenNeedsHistoryLaunchedAfterSignal() = runTest {
        val (h, _, store) = make()
        store.appDidBecomeActive()
        store.listDidAppear()
        advanceUntilIdle()
        val history = h.count("message_history_with_pokes")
        store.readSignalArrived()
        assertFalse(store.isHistoryStale, "보이는 화면인데 낡음을 적었다")
        // 요약만 신호 뒤에 떴다 — 보이는 화면의 이력은 아직 아무도 안 맡았다.
        store.performLoadSummary()
        assertNotNull(store.readSignalWindowClosed())
        advanceUntilIdle()
        assertEquals(history + 1, h.count("message_history_with_pokes"), "보이는 화면인데 창 뒤 이력을 안 받았다")
        h.assertClean()
    }
}
