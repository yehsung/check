// 원본: Tests/CheckMobileKitTests/MegaphoneBannerPhoneTests.swift · MegaphoneBannerPhoneViewTests.swift(판정 · 배선 몫) @ f3360b47
// 폰 배선: 메시지함 필터가 visibleHistory 한 자리에서 배지까지 · 옛 서버 기준선 · v2 없음 · 접두 경합 · 푸시 앞/뒤/눌러 들어옴 · 실시간 'megaphone' ·
// 보낸 뒤 내 배너 · 로그아웃 · 미룸 규칙/배선 · 코어 상수 5초 뒤 스스로 닫힘 · 늦게 켜진 필터의 요약 v2 다시 받기.
// 진짜 조립(PhoneAppModel)을 붙여 **스텁이 받은 요청**으로 잰다. 카드 단추([닫기] 하나)는 androidApp MegaphoneBannerCardTest 가 잰다.
package com.yehsung.aingcheck.feature.phone.messages

import com.yehsung.aingcheck.core.net.realtime.RealtimeLinkConstants
import com.yehsung.aingcheck.core.net.realtime.RealtimeTransportEvent
import com.yehsung.aingcheck.core.rules.text.MegaphoneBannerRules
import com.yehsung.aingcheck.core.stores.messages.MegaphoneBannerStore
import com.yehsung.aingcheck.feature.phone.FakeTransport
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.feature.phone.app.isMegaphoneBannerDeferred
import com.yehsung.aingcheck.feature.phone.app.syncMegaphoneBannerDeferral
import com.yehsung.aingcheck.feature.phone.push.PhonePushAction
import com.yehsung.aingcheck.feature.phone.push.PhonePushContent
import com.yehsung.aingcheck.feature.phone.push.PhonePushMegaphone
import com.yehsung.aingcheck.feature.phone.push.PhonePushPresentation
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MegaphoneBannerPhoneTest {
    private val peer = "00000000-0000-4000-8000-0000000000aa"

    /** 받은 줄 하나(with_reads 모양). */
    private fun row(id: String, body: String, at: Double, unread: Boolean = true): String =
        """{"id":"$id","from_user":"$peer","to_user":"${PhoneHarness.ME}","body":"$body","created_at":null,"is_mine":false,""" +
            """"peer_user_id":"$peer","peer_display_name":"보낸이","peer_avatar_url":null,"created_epoch":$at,"read_by_peer":null,"unread":$unread}"""

    private class Rig(val h: PhoneHarness, val transport: FakeTransport) {
        val banner: MegaphoneBannerStore get() = h.app.megaphoneBanner
    }

    /**
     * [inbox] = megaphone_inbox 응답(null = 함수 없음 · 옛 서버). 이력은 확성기 줄(m-mega) · 위조 접두 DM(m-fake) · 평범한 줄(m-plain).
     * v1 요약은 셋 다 세고(3), v2 는 확성기 줄을 뺀다(2). [inboxReply] 를 주면 그것이 [inbox] 를 이긴다(연결 실패 재현).
     */
    private fun TestScope.rig(
        inbox: (PhoneHarness) -> String? = { h -> "[" + item(h, "m-mega", "g-1", 30.0) + "]" },
        v2: Boolean = true,
        inboxReply: ((PhoneHarness) -> Reply)? = null,
    ): Rig {
        val transport = FakeTransport()
        lateinit var h: PhoneHarness
        h = PhoneHarness(this, transport = transport) { r: RecordedRequest ->
            val t = h.now().timeIntervalSince1970
            when (r.rpcName) {
                "megaphone_inbox" -> inboxReply?.invoke(h) ?: inbox(h)?.let { Reply.Json(it) } ?: Reply.missingFunction
                "message_unread_summary" -> Reply.Json("""{"status":"ok","total":3,"peers":[{"peer_user_id":"$peer","unread":3}]}""")
                "message_unread_summary_v2" -> if (v2) Reply.Json("""{"status":"ok","total":2,"peers":[{"peer_user_id":"$peer","unread":2}]}""") else Reply.missingFunction
                "message_history_with_pokes" -> Reply.missingFunction
                "message_history_with_reads", "message_history" -> Reply.Json(
                    "[" + row("m-mega", "📢 모두 안녕", t - 30) + "," + row("m-fake", "📢 공짜 배너", t - 20) + "," + row("m-plain", "안녕", t - 10) + "]",
                )
                "app_user_directory" -> Reply.Json("[]")
                "message_blocks", "my_blocked_users", "blocked_users" -> Reply.Json("[]")
                "gomoku_lobby", "gomoku_inbox", "tetris_lobby", "chess_lobby" -> Reply.missingFunction
                "work_phone_touch" -> Reply.Json("""{"status":"not_working"}""")
                else -> null
            }
        }
        h.signIn()
        // 타이머는 시험이 잰다 — advanceUntilIdle 이 5초 표시를 지나쳐 배너를 닫지 않게 손으로 돌리지 않는 타이머를 꽂는다.
        h.app.megaphoneBanner.schedule = { _, _ -> }
        return Rig(h, transport)
    }

    private fun item(h: PhoneHarness, message: String, megaphone: String, ago: Double): String =
        """{"message_id":"$message","megaphone_id":"$megaphone","sender_id":"$peer","sender_display_name":"보낸이","body":"모두 안녕",""" +
            """"created_epoch":${h.now().timeIntervalSince1970 - ago}}"""

    private fun TestScope.activateAndLoad(r: Rig) {
        r.h.app.messages.appDidBecomeActive()
        advanceUntilIdle()
    }

    private suspend fun TestScope.loadHistory(r: Rig) {
        r.h.app.messages.performLoadHistory()
        advanceUntilIdle()
    }

    @Test
    fun filterReachesBadges() = runTest {
        val r = rig()
        activateAndLoad(r)
        loadHistory(r)
        val ids = r.h.app.messages.visibleHistory.map { it.id }
        assertFalse("m-mega" in ids, "inbox 가 말한 확성기 줄이 메시지함에 남았다")
        assertTrue("m-plain" in ids)
        assertTrue("m-fake" in ids, "위조 접두 DM 은 refresh 한 번 뒤 메시지로 보여야 한다")
        assertTrue(r.h.count("message_unread_summary_v2") >= 1, "필터가 켜졌는데 요약이 v2 가 아니다")
        assertEquals(0, r.h.count("message_unread_summary"), "필터가 켜졌는데 옛 요약(확성기 줄을 센다)을 불렀다 — 배지가 안 꺼진다")
        assertEquals(2, r.h.app.messages.badgeCount, "탭 배지가 v2 요약을 따라오지 않았다")
        assertEquals("g-1", r.banner.current?.megaphoneID, "켜 둔 사이 온 신선한 확성기가 안 떴다")
    }

    @Test
    fun unavailableKeepsMessages() = runTest {
        val r = rig(inbox = { null })
        activateAndLoad(r)
        loadHistory(r)
        assertEquals(MegaphoneBannerStore.Capability.unavailable, r.banner.capability)
        assertEquals(listOf("m-mega", "m-fake", "m-plain"), r.h.app.messages.visibleHistory.map { it.id }, "옛 서버에서 📢 줄이 사라졌다")
        assertEquals(0, r.h.count("message_unread_summary_v2"))
        assertEquals(3, r.h.app.messages.badgeCount, "옛 서버 기준선: 옛 요약 3")
    }

    @Test
    fun missingV2TurnsFilterOff() = runTest {
        val r = rig(v2 = false)
        activateAndLoad(r)
        loadHistory(r)
        // 한 번이 아니라 '한 번 이상': v2 404 가 필터를 끄는 순간(capability 바뀜) onCapabilityChange 가 메시지함의 요약 짝을 다시 맞추며
        // 옛 요약을 한 번 더 부를 수 있다(Swift f3360b47 의 같은 시험도 >= 1 로 잰다). 결과(줄이 보임 · 배지 3)는 아래가 잰다.
        assertTrue(r.h.count("message_unread_summary") >= 1, "v2 404 뒤 옛 요약으로 안 내려갔다")
        assertTrue("m-mega" in r.h.app.messages.visibleHistory.map { it.id }, "v2 가 없는데 줄만 숨겼다 — 배지가 고착된다")
        assertEquals(3, r.h.app.messages.badgeCount)
    }

    @Test
    fun prefixRowsWaitForOneRefresh() = runTest {
        // 이력이 inbox 보다 먼저: 첫 판정 전(unknown)에는 접두 받은 줄 둘 다 보류 → refresh 뒤 판정.
        val r = rig()
        loadHistory(r)
        val ids = r.h.app.messages.visibleHistory.map { it.id }
        assertFalse("m-mega" in ids, "확성기 줄이 판정 뒤에도 남았다")
        assertTrue("m-fake" in ids, "위조 DM 이 refresh 뒤에도 숨겨져 있다(접두만 보고 숨겼다)")
        assertTrue(r.h.count("megaphone_inbox") >= 1, "보류 줄 판정에 refresh 가 없었다")
    }

    @Test
    fun foregroundPushBecomesBanner() = runTest {
        val r = rig()
        r.h.app.push.appDidBecomeActive()
        advanceUntilIdle()
        val content = PhonePushContent.Message(peer, PhonePushMegaphone("g-9", "보낸이", "📢 지금 모여요"))
        assertEquals(PhonePushPresentation.hidden, r.h.app.push.didReceive(content), "앞에서 받은 확성기는 시스템 알림을 숨겨야 한다")
        assertEquals("g-9", r.banner.current?.megaphoneID)
        assertEquals("지금 모여요", r.banner.current?.body)
        assertEquals(peer, r.banner.current?.senderID)
        // 기준선: 표식 없는 메시지 푸시는 시스템 알림 그대로.
        assertEquals(PhonePushPresentation.banner, r.h.app.push.didReceive(PhonePushContent.Message(peer)))
    }

    @Test
    fun backgroundPushStaysSystem() = runTest {
        val r = rig()
        val content = PhonePushContent.Message(peer, PhonePushMegaphone("g-9", "보낸이", "📢 지금 모여요"))
        assertEquals(PhonePushPresentation.banner, r.h.app.push.didReceive(content), "뒤에서는 지금처럼 시스템 알림")
        assertNull(r.banner.current, "뒤에서 받은 푸시로 앱 배너를 띄웠다")
    }

    /**
     * 이 내용(표식을 실은 Message)을 진짜 안드로이드 길이 만드는지는 androidApp AingMessagingServiceTest.tappedBackgroundMegaphoneOpensBannerNotThread 가
     * 잰다(게시된 알림의 PendingIntent → RouteIntents.parse → RouteTargets.megaphoneTapContent). 여기는 그 내용 → 배너.
     */
    @Test
    fun tappedPushOpensBannerNotThread() = runTest {
        val r = rig()
        r.h.app.push.handleResponse(PhonePushContent.Message(peer, PhonePushMegaphone("g-7", "보낸이", "어제 말")), PhonePushAction.open)
        assertEquals("g-7", r.banner.current?.megaphoneID, "눌러 들어온 확성기가 배너로 안 떴다")
        assertNull(r.h.app.router.lastOpenedTarget, "확성기를 눌렀는데 대화로 갔다")
        // 기준선: 표식 없는 메시지는 그 대화를 연다.
        r.h.app.push.handleResponse(PhonePushContent.Message(peer), PhonePushAction.open)
        assertEquals(PhoneRouteTarget.Message(peer), r.h.app.router.lastOpenedTarget)
    }

    @Test
    fun realtimeMegaphoneRefreshesBanner() = runTest {
        val r = rig()
        activateAndLoad(r)
        r.h.app.realtime.coalesceSeconds = 1.0
        r.h.app.realtime.appDidBecomeActive()
        r.transport.emit(RealtimeTransportEvent.Opened)
        r.transport.emit(RealtimeTransportEvent.Joined)
        advanceUntilIdle()
        r.h.markRequests()
        r.transport.emit(RealtimeTransportEvent.Broadcast(RealtimeLinkConstants.megaphoneBroadcastEvent))
        advanceTimeBy(1_001)
        runCurrent()
        advanceUntilIdle()
        assertEquals(1, r.h.count("megaphone_inbox"), "'megaphone' 신호가 배너 refresh 로 안 갔다")
        assertEquals(0, r.h.count("message_unread_summary") + r.h.count("message_unread_summary_v2"), "'megaphone' 이 메시지 조회를 깨웠다(.drain 으로 떨어졌다)")
        assertEquals(0, r.h.count("take_pokes"))
        // 기준선: 'ring' 은 지금처럼 메시지 요약.
        r.transport.emit(RealtimeTransportEvent.Broadcast("ring"))
        advanceTimeBy(1_001)
        runCurrent()
        advanceUntilIdle()
        assertTrue(r.h.count("message_unread_summary") + r.h.count("message_unread_summary_v2") >= 1)
    }

    @Test
    fun ownBannerAfterSend() = runTest {
        var sendReply = """{"status":"ok","duplicate":false,"megaphone_id":"g-own","recipients":4,"price":30,"ruby_balance":70}"""
        val r = rig()
        r.h.route = { req ->
            when (req.rpcName) {
                "megaphone_info" -> Reply.Json("""{"status":"ok","enabled":true,"price":30,"cooldown_seconds":600,"cooldown_remaining_seconds":0,"recipients":4,"max_length":200,"ruby_balance":100}""")
                "send_megaphone" -> Reply.Json(sendReply)
                "megaphone_inbox" -> Reply.Json("[]")
                else -> null
            }
        }
        val mega = r.h.app.messages.megaphone
        mega.open()
        advanceUntilIdle()
        mega.setDraft("모두 안녕")
        mega.requestSend()
        mega.confirmSend()
        advanceUntilIdle()
        assertEquals("g-own", r.banner.current?.megaphoneID, "보낸 직후 내 배너가 안 떴다")
        assertTrue(r.banner.current?.isOwn == true)
        r.banner.dismissCurrent()
        advanceUntilIdle()
        // 기준선: 루비 부족 응답이면 안 뜬다.
        sendReply = """{"status":"insufficient_ruby","need":30,"have":5}"""
        mega.setDraft("또")
        mega.requestSend()
        mega.confirmSend()
        advanceUntilIdle()
        assertNull(r.banner.current, "보내지 못했는데 내 배너가 떴다")
    }

    @Test
    fun signOutResetsBanner() = runTest {
        val r = rig()
        activateAndLoad(r)
        assertTrue(r.banner.current != null && r.banner.hides("m-mega"), "기준선: 로그아웃 전에는 채워져 있다")
        r.h.app.session.signOut()
        advanceUntilIdle()
        assertNull(r.banner.current)
        assertFalse(r.banner.hides("m-mega"))
        assertEquals(MegaphoneBannerStore.Capability.unknown, r.banner.capability)
    }

    @Test
    fun deferralRules() {
        assertTrue(MegaphoneBannerPhoneRules.isDeferred(modalPresented = true, matchScreenVisible = false, miniGameRoundPlaying = false))
        assertTrue(MegaphoneBannerPhoneRules.isDeferred(false, true, false))
        assertTrue(MegaphoneBannerPhoneRules.isDeferred(false, false, true))
        assertFalse(MegaphoneBannerPhoneRules.isDeferred(false, false, false))
        assertTrue(MegaphoneBannerPhoneRules.needsDeferralSync(isDeferred = true, hasCurrent = true, hasQueue = false))
        assertFalse(MegaphoneBannerPhoneRules.needsDeferralSync(isDeferred = true, hasCurrent = false, hasQueue = true))
        assertTrue(MegaphoneBannerPhoneRules.needsDeferralSync(isDeferred = false, hasCurrent = false, hasQueue = true))
        assertNull(MegaphoneBannerPhoneRules.deferralPollKey(null, 0))
        assertEquals("g#2", MegaphoneBannerPhoneRules.deferralPollKey("g", 2))
        assertTrue(MegaphoneBannerPhoneRules.swipeDismisses(translation = -40f, predictedEnd = -40f))
        assertTrue(MegaphoneBannerPhoneRules.swipeDismisses(translation = -10f, predictedEnd = -100f), "위로 튕기면 짧아도 닫힌다")
        assertFalse(MegaphoneBannerPhoneRules.swipeDismisses(translation = 40f, predictedEnd = 200f), "아래로 끈 것을 닫았다")
        assertEquals(16f, MegaphoneBannerPhoneRules.dragOffset(200f), "아래로는 고무줄 상한")
    }

    @Test
    fun deferralWiring() = runTest {
        val r = rig()
        var modal = false
        r.h.app.megaphoneModalProbe = { modal }
        r.banner.presentOwn("하나", senderName = "나")
        assertTrue(r.banner.current != null, "기준선: 시트가 없으면 그대로 뜬다")
        modal = true
        assertTrue(r.h.app.isMegaphoneBannerDeferred)
        r.h.app.syncMegaphoneBannerDeferral()
        assertNull(r.banner.current, "시트가 떴는데 배너가 그 밑에 남았다")
        r.banner.presentOwn("둘", senderName = "나")
        assertNull(r.banner.current, "미루는 동안 새 배너가 떴다")
        assertEquals(2, r.banner.queue.size)
        modal = false
        r.h.app.syncMegaphoneBannerDeferral()
        assertTrue(r.banner.current != null, "시트가 닫혔는데 안 떴다")
    }

    // 없으면: 폰 배너가 코어 상수 말고 제 숫자를 세거나, [닫기]를 안 누르면 계속 떠 있는 결함이 초록(Swift 8e83aa35 autoDismissUsesCoreConstant).
    @Test
    fun autoDismissUsesCoreDisplaySeconds() = runTest {
        val r = rig()
        val delays = mutableListOf<Double>()
        val fires = mutableListOf<() -> Unit>()
        r.banner.schedule = { after, fire -> delays += after; fires += fire }
        r.banner.presentFromPush("g-5", senderName = "보낸이", body = "📢 곧 올라가요", senderID = peer)
        assertEquals("g-5", r.banner.current?.megaphoneID)
        // 폰 배너의 보여 주는 시간은 맥과 한 벌인 코어 상수다(2026-10-30 사용자 결정 — 5초).
        assertEquals(5.0, MegaphoneBannerRules.displaySeconds)
        assertEquals(listOf(MegaphoneBannerRules.displaySeconds), delays, "폰 배너가 코어 상수 말고 다른 시간을 센다")
        assertTrue(r.banner.current != null, "기준선: 시간이 오기 전에 배너가 사라졌다")
        fires.first()()
        assertNull(r.banner.current, "[닫기]를 안 누르면 배너가 계속 떠 있다")
    }

    // 2026-10-30 안드로이드 이식 검증에서 찾은 결함(Swift f3360b47 filterTurningOnLaterRefetchesSummaryAsV2): 첫 판정 실패 → 옛 요약
    // (확성기 줄도 셈) → 실시간 refresh 가 필터를 켜도 메시지함이 그 사실을 몰라 숨긴 줄을 센 배지가 다음 활동 새로고침까지 남았다.
    // 코어 `onCapabilityChange` 한 곳(조립이 messages.megaphoneFilterDidSettle 로 잇는다)에서 잡는다.
    @Test
    fun filterTurningOnLaterRefetchesSummaryAsV2() = runTest {
        var inboxDown = true
        val r = rig(inboxReply = { h -> if (inboxDown) Reply.Offline else Reply.Json("[" + item(h, "m-mega", "g-1", 30.0) + "]") })
        activateAndLoad(r)
        assertTrue(r.banner.capability == MegaphoneBannerStore.Capability.unknown && r.banner.lastRefreshFailed, "전제: 첫 판정 실패")
        assertTrue(r.h.count("message_unread_summary") >= 1, "기준선: 판정을 모르는 동안은 옛 요약")
        assertEquals(0, r.h.count("message_unread_summary_v2"), "기준선: 아직 v2 를 부를 까닭이 없다")
        assertEquals(3L, r.h.app.messages.summary?.summary?.total, "기준선: 옛 요약은 확성기 줄도 센다")
        r.h.app.realtime.coalesceSeconds = 1.0
        r.h.app.realtime.appDidBecomeActive()
        r.transport.emit(RealtimeTransportEvent.Opened)
        r.transport.emit(RealtimeTransportEvent.Joined)
        advanceUntilIdle()
        assertEquals(0, r.h.count("message_unread_summary_v2"), "기준선: 연결이 붙어도 필터를 모르면 v2 가 아니다")

        inboxDown = false
        r.transport.emit(RealtimeTransportEvent.Broadcast(RealtimeLinkConstants.megaphoneBroadcastEvent))
        advanceTimeBy(1_001)
        runCurrent()
        advanceUntilIdle()
        assertEquals(MegaphoneBannerStore.Capability.available, r.banner.capability, "실시간 refresh 가 필터를 안 켰다")
        assertTrue(r.h.count("message_unread_summary_v2") >= 1, "필터가 켜졌는데 요약을 v2 로 다시 받지 않았다(배지 고착)")
        assertEquals(2L, r.h.app.messages.summary?.summary?.total, "배지 재료(요약)가 확성기 줄을 센 옛 값에 남았다")
    }
}
