// 원본: Tests/checkTests/MegaphoneBannerStoreTests.swift @ a3d59e74(a3d59e74) — 확성기 배너 코어: 필터 술어 세 갈래 · inbox 404 · 신선도 10분 ·
// 푸시 진입 24시간 · 본 것 기록 · 한 번에 하나 5초 · 멈춤 · 미룸 · 접두 경합 · 요약 v2 폴백 · 본인 배너 · reset · 전선 · 작성 문구 ·
// 필터 바뀜 알림(onCapabilityChange) · 화면 읽기 붙듦(holdsAutoDismiss)
// 진짜 세션 스토어(StoreHarness)를 붙여 **스텁이 받은 요청**으로 잰다. 타이머는 손으로 돌린다(5초를 기다리지 않는다).
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.MegaphoneBanner
import com.yehsung.aingcheck.core.rules.text.MegaphoneBannerRules
import com.yehsung.aingcheck.core.rules.text.MegaphoneCooldownScope
import com.yehsung.aingcheck.core.rules.text.MegaphoneInboxItem
import com.yehsung.aingcheck.core.rules.text.MegaphoneInfo
import com.yehsung.aingcheck.core.rules.text.MegaphoneInfoResponse
import com.yehsung.aingcheck.core.rules.text.MegaphoneRules
import com.yehsung.aingcheck.core.rules.text.MegaphoneSendOutcome
import com.yehsung.aingcheck.core.rules.text.MegaphoneSendResponse
import com.yehsung.aingcheck.core.rules.text.MegaphoneText
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 손으로 돌리는 타이머 + 시계. */
class BannerTimers(var now: SwiftDate = SwiftDate(1_800_000_000.0)) {
    private val pending = mutableListOf<Pair<SwiftDate, () -> Unit>>()

    /** 걸린 타이머의 길이(초) — 걸린 순서대로. */
    val scheduledDelays = mutableListOf<Double>()
    val schedule: MegaphoneBannerSchedule = { after, fire ->
        scheduledDelays += after
        pending += now.addingTimeInterval(after) to fire
    }

    fun advance(seconds: Double) {
        val target = now.addingTimeInterval(seconds)
        while (true) {
            val next = pending.filter { it.first <= target }.minByOrNull { it.first } ?: break
            pending.remove(next)
            now = next.first
            next.second()
        }
        now = target
    }
}

/** inbox 한 줄(JSON). [ago] 초 전. */
fun inboxRow(message: String, megaphone: String, ago: Double, now: SwiftDate, body: String = "모두 안녕", sender: String = "peer-1"): String =
    """{"message_id":"$message","megaphone_id":"$megaphone","sender_id":"$sender","sender_display_name":"보낸이",""" +
        """"sender_avatar_url":null,"body":"$body","created_epoch":${now.timeIntervalSince1970 - ago}}"""

@OptIn(ExperimentalCoroutinesApi::class)
class MegaphoneBannerStoreTest {
    private class Rig(val h: StoreHarness, val store: MegaphoneBannerStore, val timers: BannerTimers)

    private suspend fun TestScope.rig(
        inbox: (BannerTimers) -> Reply = { Reply.Json("[]") },
        summary: (String) -> Reply? = { null },
    ): Rig {
        val timers = BannerTimers()
        val h = StoreHarness(this) { r ->
            when (r.rpcName) {
                "megaphone_inbox" -> inbox(timers)
                "message_unread_summary", "message_unread_summary_v2" -> summary(r.rpcName!!)
                else -> null
            }
        }
        h.signIn()
        val store = MegaphoneBannerStore(TestMegaphoneHost(h.session), h.storeScope, h.prefs, clock = { timers.now }, schedule = timers.schedule)
        return Rig(h, store, timers)
    }

    @Test
    fun filterPredicateThreeWays() = runTest {
        var missing = false
        val r = rig(inbox = { t -> if (missing) Reply.missingFunction else Reply.Json("[" + inboxRow("msg-1", "mg-1", 30.0, t.now) + "]") })
        assertFalse(r.store.hides("msg-1"), "모름(unknown)인데 숨겼다")
        r.store.refresh()
        assertEquals(MegaphoneBannerStore.Capability.available, r.store.capability)
        assertTrue(r.store.hides("msg-1"), "inbox 가 말한 id 를 안 숨겼다")
        assertFalse(r.store.hides("msg-2"), "inbox 가 말하지 않은 id 를 숨겼다")
        missing = true
        r.store.refresh()
        assertEquals(MegaphoneBannerStore.Capability.unavailable, r.store.capability)
        assertFalse(r.store.hides("msg-1"), "함수가 사라진 서버(불가)에서 계속 숨겼다 — 메시지가 사라진다")
        assertEquals(MegaphoneBannerStore.UNREAD_SUMMARY_V1, r.store.unreadSummaryFunction)
    }

    // 없으면: 첫 판정이 실패한 뒤 실시간·푸시 refresh 가 필터를 켜도 소유자(메시지함)가 몰라 옛 요약을 쓰는 결함이 초록(Swift f3360b47).
    @Test
    fun capabilityChangeNotifiesOnlyWhenValueChanges() = runTest {
        var missing = false
        val r = rig(inbox = { t -> if (missing) Reply.missingFunction else Reply.Json("[" + inboxRow("msg-1", "mg-1", 30.0, t.now) + "]") })
        val seen = mutableListOf<MegaphoneBannerStore.Capability>()
        r.store.onCapabilityChange = { seen += r.store.capability }
        r.store.refresh()
        assertEquals(listOf(MegaphoneBannerStore.Capability.available), seen, "모름 → 켜짐에서 한 번 부르지 않았다(쓴 뒤 값으로)")
        r.store.refresh()
        assertEquals(1, seen.size, "기준선: 같은 값(켜짐 → 켜짐)이면 부르지 않는다")
        missing = true
        r.store.refresh()
        assertEquals(MegaphoneBannerStore.Capability.unavailable, seen.last(), "켜짐 → 꺼짐에서 부르지 않았다")
        r.store.reset()
        assertEquals(listOf(MegaphoneBannerStore.Capability.available, MegaphoneBannerStore.Capability.unavailable, MegaphoneBannerStore.Capability.unknown), seen)
    }

    @Test
    fun inboxMissingTurnsFilterOff() = runTest {
        val r = rig(inbox = { Reply.missingFunction })
        r.store.refresh()
        assertEquals(MegaphoneBannerStore.Capability.unavailable, r.store.capability)
        assertFalse(r.store.needsVerification("x", "📢 안녕"), "필터가 꺼진 서버에서 접두 줄을 붙들었다")
        assertEquals(MegaphoneBannerStore.UNREAD_SUMMARY_V1, r.store.unreadSummaryFunction)
        assertNull(r.store.current)
    }

    @Test
    fun freshnessTenMinutes() = runTest {
        val r = rig(inbox = { t -> Reply.Json("[" + inboxRow("m-old", "g-old", 601.0, t.now) + "," + inboxRow("m-new", "g-new", 599.0, t.now) + "]") })
        r.store.refresh()
        assertEquals("g-new", r.store.current?.megaphoneID, "10분 안의 것이 안 떴다")
        assertTrue(r.store.queue.isEmpty(), "10분 넘은 것이 줄에 섰다")
        assertTrue(r.store.hides("m-old") && r.store.hides("m-new"), "묵은 것도 메시지함에서는 빠져야 한다")
    }

    @Test
    fun pushEntryIgnoresFreshness() = runTest {
        val r = rig(inbox = { t -> Reply.Json("[" + inboxRow("m-1", "g-1", 3_600.0 * 23, t.now, sender = "peer-9") + "]") })
        val t = r.timers
        r.store.presentFromPush("g-1", senderName = "보낸이", body = "📢 모두 안녕", createdAt = t.now.addingTimeInterval(-3_600.0 * 23))
        assertEquals("g-1", r.store.current?.megaphoneID, "23시간 전 푸시 진입이 안 떴다")
        assertEquals("모두 안녕", r.store.current?.body, "📢 표식을 안 뗐다")
        r.h.scope.advanceUntilIdle()
        assertEquals("m-1", r.store.current?.messageID, "뒤이은 inbox 가 메시지 id 를 맞추지 않았다")
        assertEquals("peer-9", r.store.current?.senderID)
        r.store.presentFromPush("g-2", senderName = null, body = "늦은 것", createdAt = t.now.addingTimeInterval(-3_600.0 * 25))
        assertFalse(r.store.queue.any { it.megaphoneID == "g-2" }, "25시간 전 푸시가 섰다")
    }

    @Test
    fun seenRecordSurvivesRelaunchPerAccount() = runTest {
        val r = rig(inbox = { t -> Reply.Json("[" + inboxRow("m-1", "g-1", 10.0, t.now) + "]") })
        r.store.refresh()
        assertEquals("g-1", r.store.current?.megaphoneID)
        // 재실행: 같은 기본값 저장소 · 새 스토어 → 다시 안 뜬다.
        val again = MegaphoneBannerStore(TestMegaphoneHost(r.h.session), r.h.storeScope, r.h.prefs, clock = { r.timers.now }, schedule = r.timers.schedule)
        again.refresh()
        assertNull(again.current, "본 확성기가 재실행 뒤 다시 떴다")
        assertTrue(again.hides("m-1"), "본 것이어도 메시지함에서는 빠져야 한다")
        assertEquals(listOf("g-1"), r.h.prefs.getString(MegaphoneBannerRules.seenKey(r.h.session.session!!.userID))?.split('\n'))
        // 다른 계정 키는 비어 있다(계정별).
        assertNull(r.h.prefs.getString(MegaphoneBannerRules.seenKey("someone-else")))
    }

    // 2026-10-30 사용자 결정으로 8초 → 5초("너무 오래 떠있으면 안좋을듯").
    @Test
    fun oneAtATimeFiveSeconds() = runTest {
        val r = rig(inbox = { t -> Reply.Json("[" + inboxRow("m-2", "g-2", 5.0, t.now) + "," + inboxRow("m-1", "g-1", 50.0, t.now) + "]") })
        r.store.refresh()
        assertEquals("g-1", r.store.current?.megaphoneID, "오래된 것부터가 아니다")
        assertEquals(listOf("g-2"), r.store.queue.map { it.megaphoneID }, "한 번에 하나가 아니다")
        assertEquals(5.0, MegaphoneBannerRules.displaySeconds)
        r.timers.advance(4.9)
        assertEquals("g-1", r.store.current?.megaphoneID, "기준선: 5초 전에 닫혔다")
        r.timers.advance(0.2)
        assertNull(r.store.current, "5초가 지났는데 떠 있다")
        r.timers.advance(0.2)
        assertNull(r.store.current, "쉬는 0.4초 전에 다음 장이 떴다")
        r.timers.advance(0.2)
        assertEquals("g-2", r.store.current?.megaphoneID, "다음 장이 안 떴다")
    }

    @Test
    fun pauseAndResume() = runTest {
        val r = rig(inbox = { t -> Reply.Json("[" + inboxRow("m-1", "g-1", 5.0, t.now) + "]") })
        r.store.refresh()
        r.timers.advance(4.0)
        r.store.pauseTimer()
        assertTrue(r.store.isTimerPaused)
        r.timers.advance(30.0)
        assertEquals("g-1", r.store.current?.megaphoneID, "누르고 있는 동안 사라졌다")
        r.store.resumeTimer()
        r.timers.advance(2.9)
        assertEquals("g-1", r.store.current?.megaphoneID, "남은 1초가 아니라 3초 중 긴 쪽이어야 한다")
        r.timers.advance(0.2)
        assertNull(r.store.current)
    }

    // 없으면: 화면 읽기 사용자가 본문(최대 198자)을 다 듣기 전에 배너가 올라가는 결함이 초록(2026-10-31 모바일 세션 지적 · Swift a3d59e74
    // voiceOverHoldsAutoDismiss 짝). 붙들면 [닫기]로만 · 미룸에서 돌아와 다시 떠도 붙든다 · 풀리면 다시 5초 · 기준선: 안 붙들면 5초.
    @Test
    fun screenReaderHoldsAutoDismiss() = runTest {
        val r = rig()
        var held = true
        r.store.holdsAutoDismiss = { held }
        r.store.presentOwn("천천히 들어요", senderName = "나")
        assertFalse(MegaphoneBannerRules.displaySeconds in r.timers.scheduledDelays, "붙드는데 5초 타이머가 걸렸다")
        r.timers.advance(100.0)
        assertEquals("천천히 들어요", r.store.current?.body, "화면 읽기가 켜져 있는데 저절로 닫혔다")
        // 멈췄다 풀어도(누르기) 붙듦이 이긴다.
        r.store.pauseTimer()
        r.store.resumeTimer()
        r.timers.advance(100.0)
        assertTrue(r.store.current != null, "멈춤을 풀자 붙듦을 잊었다")
        // 미룸(대결·미니게임·시트)에서 돌아와 다시 뜨는 배너도 같은 자리(startTimer)를 지난다.
        var deferred = true
        r.store.isBannerDeferred = { deferred }
        r.store.deferralChanged()
        assertNull(r.store.current, "전제: 미루면 내린다")
        deferred = false
        r.store.deferralChanged()
        assertTrue(r.store.current != null, "전제: 풀리면 다시 뜬다")
        r.timers.advance(100.0)
        assertTrue(r.store.current != null, "미룸에서 돌아온 배너가 저절로 닫혔다")
        // [닫기] 는 언제나 닫는다.
        r.store.dismissCurrent()
        assertNull(r.store.current)

        // 화면 읽기를 끄면 떠 있는 배너를 처음부터 5초 센다.
        r.timers.advance(MegaphoneBannerRules.gap)
        r.store.presentOwn("끄면 다시 센다", senderName = "나")
        r.timers.advance(30.0)
        held = false
        r.store.autoDismissHoldChanged()
        r.timers.advance(4.9)
        assertTrue(r.store.current != null, "풀린 뒤 5초가 아니다")
        r.timers.advance(0.1)
        assertNull(r.store.current, "풀린 뒤 5초에 안 닫혔다")

        // 기준선: 처음부터 안 붙들면 5초 뒤 닫힌다 · 다시 켜면 걸린 타이머를 버린다.
        r.timers.advance(MegaphoneBannerRules.gap)
        r.store.presentOwn("기준선", senderName = "나")
        r.timers.advance(2.0)
        held = true
        r.store.autoDismissHoldChanged()
        r.timers.advance(100.0)
        assertEquals("기준선", r.store.current?.body, "화면 읽기를 켰는데 걸려 있던 타이머가 닫았다")
    }

    @Test
    fun deferralHoldsAndReleasesFreshOnly() = runTest {
        var deferred = true
        val r = rig(inbox = { t -> Reply.Json("[" + inboxRow("m-1", "g-1", 30.0, t.now) + "]") })
        r.store.isBannerDeferred = { deferred }
        r.store.refresh()
        assertNull(r.store.current, "미루는 동안 떴다")
        assertEquals(1, r.store.queue.size)
        r.timers.advance(600.0)
        deferred = false
        r.store.deferralChanged()
        assertNull(r.store.current, "풀렸을 때 신선도 밖의 것이 떴다")
        assertTrue(r.store.queue.isEmpty())
        // 떠 있던 것은 미루기 시작하면 줄 맨 앞으로.
        r.store.presentOwn("내 말", senderName = "나")
        assertTrue(r.store.current?.isOwn == true)
        deferred = true
        r.store.deferralChanged()
        assertNull(r.store.current)
        assertTrue(r.store.queue.first().isOwn, "떠 있던 배너가 줄 맨 앞으로 안 돌아갔다")
    }

    @Test
    fun prefixOnlyLinesWaitForOneRefresh() = runTest {
        val r = rig(inbox = { t -> Reply.Json("[" + inboxRow("m-real", "g-1", 5.0, t.now) + "]") })
        assertTrue(r.store.needsVerification("m-real", "📢 모두 안녕"), "모를 때 접두 줄을 판정 보류하지 않았다")
        assertFalse(r.store.needsVerification("m-plain", "안녕"), "접두 없는 줄을 보류했다")
        assertFalse(r.store.hides("m-fake"), "접두만 보고 숨겼다")
        r.store.refresh(verifying = setOf("m-real", "m-fake"))
        assertTrue(r.store.hides("m-real"))
        assertFalse(r.store.hides("m-fake"), "위조 DM(📢 로 시작하는 1:1)을 숨겼다")
        assertFalse(r.store.needsVerification("m-fake", "📢 공짜 배너"), "refresh 한 번 뒤에도 판정을 미뤘다")
        assertEquals(1, r.h.count("megaphone_inbox"))
    }

    @Test
    fun unreadSummaryFallsBackAndDisablesFilter() = runTest {
        var v2: Reply = Reply.missingFunction
        val r = rig(
            inbox = { t -> Reply.Json("[" + inboxRow("m-1", "g-1", 5.0, t.now) + "]") },
            summary = { name -> if (name == "message_unread_summary_v2") v2 else Reply.Json("""{"status":"ok","total":2,"peers":[]}""") },
        )
        r.store.refresh()
        assertEquals(MegaphoneBannerStore.UNREAD_SUMMARY_V2, r.store.unreadSummaryFunction)
        assertEquals(2L, r.store.fetchUnreadSummary().total)
        assertEquals(1, r.h.count("message_unread_summary_v2"))
        assertEquals(1, r.h.count("message_unread_summary"), "v2 404 뒤 옛 함수로 내려가지 않았다")
        assertFalse(r.store.hides("m-1"), "v2 가 없는데 필터를 안 껐다 — 배지가 고착된다")
        assertEquals(MegaphoneBannerStore.UNREAD_SUMMARY_V1, r.store.unreadSummaryFunction)
        // 기준선: v2 가 있으면 v2 만.
        val ok = rig(
            inbox = { t -> Reply.Json("[" + inboxRow("m-1", "g-1", 5.0, t.now) + "]") },
            summary = { name -> if (name == "message_unread_summary_v2") Reply.Json("""{"status":"ok","total":0,"peers":[]}""") else null },
        )
        ok.store.refresh()
        assertEquals(0L, ok.store.fetchUnreadSummary().total)
        assertEquals(0, ok.h.count("message_unread_summary"))
        assertTrue(ok.store.hides("m-1"))
    }

    @Test
    fun ownBannerAfterSending() = runTest {
        val r = rig(inbox = { t -> Reply.Json("[" + inboxRow("m-1", "g-1", 5.0, t.now) + "]") })
        r.store.refresh()
        r.store.presentOwn("📢 내가 보낸 말", senderName = "나", megaphoneID = "g-own")
        assertEquals("g-1", r.store.current?.megaphoneID, "떠 있던 것을 밀어냈다")
        assertEquals("g-own", r.store.queue.first().megaphoneID, "줄 맨 앞이 아니다")
        assertTrue(r.store.queue.first().isOwn)
        assertEquals("내가 보낸 말", r.store.queue.first().body)
        r.store.dismissCurrent()
        r.timers.advance(0.5)
        assertTrue(r.store.hasSeen("g-own"), "응답 id 를 본 것으로 안 적었다")
        r.store.presentOwn("다시", senderName = "")
        r.store.dismissCurrent()
        r.timers.advance(0.5)
        assertFalse(r.store.seenMegaphoneIDs.any { it.startsWith("local-") }, "자리값 id 가 기록에 들어갔다")
    }

    @Test
    fun resetClearsEverything() = runTest {
        val r = rig(inbox = { t -> Reply.Json("[" + inboxRow("m-1", "g-1", 5.0, t.now) + "," + inboxRow("m-2", "g-2", 4.0, t.now) + "]") })
        r.store.refresh()
        assertTrue(r.store.hides("m-1") && r.store.current != null && r.store.queue.isNotEmpty(), "기준선: reset 전에는 채워져 있다")
        r.store.reset()
        assertEquals(MegaphoneBannerStore.Capability.unknown, r.store.capability)
        assertTrue(r.store.knownMessageIDs.isEmpty() && r.store.queue.isEmpty())
        assertNull(r.store.current)
        r.timers.advance(10.0)
        assertNull(r.store.current, "지난 타이머가 살아 다음 장을 띄웠다")
        assertTrue(r.h.prefs.getString(MegaphoneBannerRules.seenKey(r.h.session.session!!.userID)) != null, "기록은 계정 키에 남아야 한다")
    }

    @Test
    fun wireDecoding() = runTest {
        val now = SwiftDate(1_800_000_000.0)
        val raw = Json.parseToJsonElement(
            "[" + inboxRow("m-1", "g-1", 5.0, now, body = "📢 hi") + "," +
                """{"megaphone_id":"g-broken"},""" +
                """{"message_id":"m-3","megaphone_id":"g-3","from_user":"p-3","body":"x","created_epoch":${1_800_000_000_000.0}}""" + "]",
        )
        val banners = MegaphoneInboxItem.banners(raw)
        assertEquals(listOf("g-1", "g-3"), banners.map { it.megaphoneID }, "깨진 한 줄이 나머지를 죽였다")
        assertEquals("hi", banners[0].body)
        assertEquals("p-3", banners[1].senderID, "from_user 를 못 받았다")
        assertEquals(1_800_000_000.0, banners[1].createdAt.timeIntervalSince1970, "밀리초를 초로 못 바꿨다")
        assertEquals(MegaphoneBanner.fallbackSenderName, banners[1].senderName)
        val info = MegaphoneInfoResponse.decode(
            Json.parseToJsonElement(
                """{"status":"ok","price":30,"recipients":4,"cooldown_remaining_seconds":250,"global_cooldown_seconds":300,""" +
                    """"global_cooldown_remaining_seconds":250,"cooldown_scope":"global"}""",
            ),
        )
        assertEquals(300L, info.globalCooldownSeconds)
        assertEquals("global", info.cooldownScope)
        val sent = MegaphoneSendResponse.decode(Json.parseToJsonElement("""{"status":"cooldown","retry_after_seconds":120,"scope":"global"}"""))
        assertEquals(MegaphoneSendOutcome.cooldown(120, MegaphoneCooldownScope.global), MegaphoneSendOutcome.from(sent))
        val old = MegaphoneSendResponse.decode(Json.parseToJsonElement("""{"status":"cooldown","retry_after_seconds":120}"""))
        assertEquals(MegaphoneCooldownScope.personal, (MegaphoneSendOutcome.from(old) as MegaphoneSendOutcome.cooldown).scope, "옛 서버는 사람당")
    }

    @Test
    fun composerTexts() {
        assertEquals("다음 확성기까지 5분", MegaphoneText.globalCooldown(300))
        assertEquals("다음 확성기까지 5분", MegaphoneText.cooldownLine(remaining = 250, globalRemaining = 250), "같으면 앱 전체 문구")
        assertEquals("10분 뒤에 다시 보낼 수 있어요", MegaphoneText.cooldownLine(remaining = 600, globalRemaining = 120), "긴 쪽(사람당)")
        assertNull(MegaphoneText.cooldownLine(0, 0))
        // 작성 화면이 그 줄을 쓴다(부르는 자리): 정보 → 줄 · 보내기 판정.
        val now = 1_800_000_000.0
        val info = MegaphoneInfo.from(
            MegaphoneInfoResponse(price = 30, recipients = 4, cooldownRemainingSeconds = 250, globalCooldownSeconds = 300, globalCooldownRemainingSeconds = 250),
            now,
        )
        assertEquals("다음 확성기까지 5분", MegaphoneRules.infoLine(false, info, false, now))
        val personal = MegaphoneInfo.from(MegaphoneInfoResponse(price = 30, recipients = 4, cooldownRemainingSeconds = 600), now)
        assertEquals("10분 뒤에 다시 보낼 수 있어요", MegaphoneRules.infoLine(false, personal, false, now), "옛 서버(전역 키 없음)는 옛 문구")
        // 전역 cooldown 응답 → 앱 전체 문구 · 정보에 앱 전체 끝 시각.
        val outcome = MegaphoneSendOutcome.cooldown(null, MegaphoneCooldownScope.global)
        assertEquals("다음 확성기까지 5분", MegaphoneText.notice(outcome, MegaphoneRules.cooldownSecondsAfter(outcome, info)).first)
        assertEquals(now + 300, MegaphoneRules.infoAfter(outcome, info?.copy(globalCooldownEndsAt = null), now)?.globalCooldownEndsAt)
    }
}
