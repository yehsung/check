// int-w3(W-14 #5) — 제보 답장 배너 문을 **진짜 MeStore** 에 묶었을 때(HomeBannerStores.feedbackReply): 서버가 준 마지막 답장 시각이 오면 서고,
// X 가 그 시각을 '봤음'으로 적어 내려가며(맥 WorkTimerStore.swift:3142-3147 — 지금 시각이 아니라 서버 시각), 같은 시각을 다시 받아도 다시 서지 않는다.
// 더 새 답장이 오면 다시 선다(음성 대조). 네트워크 0(하네스 MockEngine) · 픽스처 합성.
package com.yehsung.aingcheck.desktop.pages.shared

import com.yehsung.aingcheck.core.stores.me.loadFeedbackReplyLatest
import com.yehsung.aingcheck.desktop.wiring.HomeBannerStores
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class HomeBannerFeedbackStoreTest {
    @Test
    fun `답장 — 서버 시각이 오면 서고 X 로 내려가며 같은 시각엔 다시 안 서고 더 새 답장엔 선다`() = runTest {
        var latest = "\"2026-10-29T03:00:00Z\""
        val h = SharedTestHarness(this, answer = { p -> SharedTestHarness.withTeam(p) ?: if (p.endsWith("/rpc/feedback_reply_latest")) latest else null })
        h.signIn()
        advanceUntilIdle()
        val reply = HomeBannerStores.feedbackReply(h.me)
        assertFalse(reply.unseen(), "전제: 답장 시각을 받기 전엔 배너가 없다")
        h.me.loadFeedbackReplyLatest()
        advanceUntilIdle()
        assertTrue(reply.unseen(), "새 답장 시각이 왔는데 배너가 안 섰다")
        reply.markSeen()
        assertFalse(reply.unseen(), "X 뒤에도 배너가 남았다")
        h.me.loadFeedbackReplyLatest()
        advanceUntilIdle()
        assertFalse(reply.unseen(), "같은 답장 시각을 다시 받았는데 배너가 되살아났다 — '봤음'이 저장되지 않았다")
        latest = "\"2026-10-29T05:00:00Z\""
        h.me.loadFeedbackReplyLatest()
        advanceUntilIdle()
        assertTrue(reply.unseen(), "더 새 답장이 왔는데 배너가 안 섰다(음성 대조)")
    }
}
