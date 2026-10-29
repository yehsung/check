// 원본: Sources/check/WorkTimerStore.swift @ a90d8623 3335-3345(로그인 직후 요약 1회) · WorkTimerStoreMessages.swift 60(60초 눈금)
//
// W-3 #13 — 플라이아웃이 닫혀 있어도 로그인 동안 안 읽음 요약을 60초마다 받는다(가짜 시계). 로그아웃이면 0회, 로그아웃 전이에서 reset 1회.
// ⚠️ 근무 여부를 보지 않는다(shell.md §2 ⑥) — 이 시험엔 근무 입력 자체가 없다.
package com.yehsung.aingcheck.desktop.pages.shared

import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.mutableIntStateOf
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MessagesBackgroundRefreshTest {
    @Test
    fun `로그인 직후 1회 · 그 뒤 60초마다 1회 · 로그아웃이면 멈추고 reset 1회`() = runTest {
        val signedIn = MutableStateFlow(false)
        var refreshes = 0
        var resets = 0
        val job = MessagesBackgroundRefresh(signedIn, refresh = { refreshes++ }, onSignedOut = { resets++ }).start(backgroundScope)
        runCurrent()
        advanceTimeBy(300_000)
        assertEquals(0, refreshes, "로그아웃 상태엔 0회")
        assertEquals(0, resets, "처음부터 로그아웃이면 reset 을 부르지 않는다")

        signedIn.value = true
        runCurrent()
        assertEquals(1, refreshes, "로그인 직후 1회")
        advanceTimeBy(59_999)
        assertEquals(1, refreshes, "60초 전엔 그대로")
        advanceTimeBy(1)
        runCurrent()
        assertEquals(2, refreshes, "60초에 1회")
        advanceTimeBy(120_000)
        runCurrent()
        assertEquals(4, refreshes)

        signedIn.value = false
        runCurrent()
        advanceTimeBy(600_000)
        assertEquals(4, refreshes, "로그아웃 뒤 0회")
        assertEquals(1, resets)
        job.cancel()
    }

    @Test
    fun `진짜 메시지 스토어 — 닫힌 플라이아웃에서도 요약이 나간다`() = runTest {
        val h = SharedTestHarness(this, answer = SharedTestHarness.withTeam)
        h.signIn()
        advanceUntilIdle()
        h.paths.clear()
        MessagesBackgroundRefresh(h.host.signedInFlow(), refresh = { h.messages.requestActivityRefresh() }).start(backgroundScope)
        runCurrent()
        advanceTimeBy(1_000)
        runCurrent()
        assertTrue(h.paths.any { it.endsWith("/rpc/message_unread_summary") }, "요약 RPC 가 나가야 한다: ${h.paths}")
        assertTrue(!h.nav.visible.value, "플라이아웃은 닫혀 있다")
    }

    @Test
    fun `안 읽음 점 흐름 — 배지 0 이면 거짓, 1 이상이면 참`() = runTest {
        val badge = mutableIntStateOf(0)
        val seen = mutableListOf<Boolean>()
        backgroundScope.launch { MessagesUnreadDot.flow { badge.intValue }.collect { seen += it } }
        runCurrent()
        badge.intValue = 2
        Snapshot.sendApplyNotifications()
        runCurrent()
        badge.intValue = 3
        Snapshot.sendApplyNotifications()
        runCurrent()
        badge.intValue = 0
        Snapshot.sendApplyNotifications()
        runCurrent()
        assertEquals(listOf(false, true, false), seen)
    }
}
