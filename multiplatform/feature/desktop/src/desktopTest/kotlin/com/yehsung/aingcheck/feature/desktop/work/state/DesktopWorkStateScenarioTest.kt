// W2-g5 상태 코어 장면 시험 — 규약 번호는 xplat-w1/briefs/work.md §2(⑬~⑱ · C#22 · ㉓).
// Swift 기준: SessionOwnershipTests · AdoptedSessionStoreTests · V0238TickTests · V0236SyncTests 의 단언을 본뜬다.
package com.yehsung.aingcheck.feature.desktop.work.state

import com.yehsung.aingcheck.core.wire.models.StatusDeviceClaim
import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkOperation
import com.yehsung.aingcheck.feature.desktop.work.WorkEvent
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import kotlinx.coroutines.runBlocking
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DesktopWorkStateScenarioTest {

    @Test
    fun c22_startEnqueuesStartWithLowercaseIdAndStrongOwnership() {
        val r = WorkStateRig(deviceId = WIN_DEVICE)
        r.store.start()
        val id = r.store.currentSessionId!!
        assertEquals("a0000000-0000-4000-8000-000000000001", id, "대문자 UUID 원천이어도 만드는 순간 소문자(C#22)")
        val item = r.queue.items.value.single()
        assertEquals(PendingWorkOperation.Start, item.operation)
        assertEquals(id, item.sessionId)
        assertEquals(ME, item.ownerUserId)
        assertEquals(T0, item.sessionStartedAt)
        assertEquals(id, r.kv.getString(OwnedSessionLedger.OWNED_ID_KEY))
        assertEquals("strong", r.kv.getString(OwnedSessionLedger.OWNED_STRENGTH_KEY))
        val snap = r.store.snapshot.value
        assertTrue(snap.isWorking && snap.ownsStrongly && !snap.adopted)
        assertEquals(WorkStartOrigin.MANUAL, snap.startOrigin)
        assertEquals(1, r.store.workStateWriteGeneration, "⑱ start 는 세대를 올린다")
        assertEquals(listOf("clearSuppression", "anchored(0,true,true)"), r.policy.calls)
        assertEquals(T0, snap.lastMeaningfulInputAt, "근무 시작은 그 자체가 입력")
    }

    @Test
    fun rule17_stopPlantsSuppressionExceptDuringTermination() {
        val manual = WorkStateRig()
        manual.store.start()
        manual.queue.drain()
        manual.now = at(5_400)
        manual.store.stop()
        val stop = manual.queue.items.value.single()
        assertEquals(PendingWorkOperation.Stop(5_400), stop.operation)
        assertEquals(at(5_400), stop.endedAt)
        assertTrue("suppress" in manual.policy.calls, "수동 종료는 자동 시작을 억제한다")
        assertEquals(2, manual.store.workStateWriteGeneration)
        assertNull(manual.store.ownedSessionId, "종료는 소유를 내려놓는다")

        val quitting = WorkStateRig()
        quitting.store.start()
        quitting.store.beginTermination()
        quitting.store.stop()
        assertFalse("suppress" in quitting.policy.calls, "⑰ 종료 시퀀스의 stop 은 억제를 심지 않는다")
    }

    @Test
    fun rule13_tickCarriesConfirmedSessionOnly_fourBranches() {
        val r = WorkStateRig(deviceId = WIN_DEVICE)
        r.input = at(-30)
        // 세션 없음 → heartbeat=false
        val none = r.store.planWorkTick()!!
        assertEquals(WorkTickArgs(TEAM, false, null, null, false, null, ME, 0), none)
        // 확인 전 → 입력만(세션 id 0)
        r.store.start()
        r.queue.drain()
        val unconfirmed = r.store.planWorkTick()!!
        assertEquals(true, unconfirmed.heartbeat)
        assertNull(unconfirmed.sessionId, "⑬ 확인 전이면 currentSessionID 를 싣지 않는다")
        assertEquals(WIN_DEVICE, unconfirmed.deviceId)
        assertFalse(unconfirmed.openedSession)
        assertEquals(T0, unconfirmed.lastInputAt)
        // 확인된 내 세션 → id + opened(강한 소유)
        val id = r.store.currentSessionId
        r.store.setConfirmedServerSessionId(id)
        val owner = r.store.planWorkTick()!!
        assertEquals(id, owner.sessionId)
        assertTrue(owner.openedSession)
        // 흡수 → 입력만
        val a = WorkStateRig(deviceId = WIN_DEVICE)
        a.apply(working(SESSION_X, at(-600), at(-15)))
        val adopted = a.store.planWorkTick()!!
        assertTrue(adopted.heartbeat)
        assertNull(adopted.sessionId)
        assertFalse(adopted.openedSession)
        assertEquals(WIN_DEVICE, adopted.deviceId)
    }

    @Test
    fun nullDeviceId_meansZeroDeviceRowWrites() {
        val r = WorkStateRig(deviceId = null)
        r.input = at(-5)
        r.store.start()
        r.queue.drain()
        assertNull(r.store.planWorkTick()!!.deviceId, "p_device_id null")
        assertEquals(HeartbeatPlan.Skip, r.store.planHeartbeat(awayServerSupported = true), "확인 전 + 기기 없음 → reportDeviceInput 0")
        r.store.setConfirmedServerSessionId(r.store.currentSessionId)
        val beat = r.store.planHeartbeat(awayServerSupported = true) as HeartbeatPlan.Beat
        assertNull(beat.device, "기기 없음 → work_status_devices upsert 0")
        val adopted = WorkStateRig(deviceId = "")
        adopted.input = at(-5)
        adopted.apply(working(SESSION_X, at(-600), at(-15)))
        assertNull(adopted.store.deviceId, "빈 문자열도 신원 없음")
        assertEquals(HeartbeatPlan.Skip, adopted.store.planHeartbeat(awayServerSupported = true))
    }

    @Test
    fun heartbeatPlan_branches() {
        val r = WorkStateRig(deviceId = WIN_DEVICE)
        r.input = at(-5)
        assertEquals(HeartbeatPlan.Skip, r.store.planHeartbeat(true), "근무 중 아님")
        r.store.start()
        r.queue.drain()
        r.input = at(-1)
        assertEquals(HeartbeatPlan.DeviceInputOnly(TEAM, WIN_DEVICE, T0), r.store.planHeartbeat(true), "확인 전: 입력만(②′)")
        assertEquals(HeartbeatPlan.Skip, r.store.planHeartbeat(false), "서버가 입력 열을 모르면 입력 보고도 0")
        val id = r.store.currentSessionId!!
        r.store.setConfirmedServerSessionId(id)
        assertEquals(
            HeartbeatPlan.Beat(TEAM, id, T0, DeviceClaimUpsert(WIN_DEVICE, id, true, T0)),
            r.store.planHeartbeat(true),
        )
        assertEquals(HeartbeatPlan.Beat(TEAM, id, null, DeviceClaimUpsert(WIN_DEVICE, id, true, null)), r.store.planHeartbeat(false))
    }

    @Test
    fun rule14_inputObservedBeforeOwnershipAndMonotonic() {
        val r = WorkStateRig(deviceId = WIN_DEVICE)
        r.input = at(-10)
        assertEquals(HeartbeatPlan.Skip, r.store.planHeartbeat(true))
        assertEquals(at(-10), r.store.snapshot.value.lastMeaningfulInputAt, "⑭ 비근무여도 입력 관측은 먼저 전진")
        r.input = at(-60)
        r.store.advanceMeaningfulInput()
        assertEquals(at(-10), r.store.snapshot.value.lastMeaningfulInputAt, "뒤로 가지 않는다")
        r.input = at(30)
        r.store.advanceMeaningfulInput()
        assertEquals(T0, r.store.snapshot.value.lastMeaningfulInputAt, "미래 입력은 now 로 자른다")
    }

    @Test
    fun c22_uppercasePersistedIdRescuedOnRestart() {
        val r = WorkStateRig(deviceId = WIN_DEVICE)
        r.own(SESSION_S.uppercase(), SessionClaimStrength.STRONG)
        r.apply(working(SESSION_S, at(-3 * 3_600), at(-20)))
        val snap = r.store.snapshot.value
        assertFalse(snap.adopted, "대문자로 영속된 내 세션도 내 것")
        assertTrue(snap.ownsStrongly, "강도는 영속된 그대로")
        assertEquals(WorkStartOrigin.RESUME, snap.startOrigin)
        assertEquals(SESSION_S, r.kv.getString(OwnedSessionLedger.OWNED_ID_KEY), "디스크 표현을 소문자로 이관")
        assertEquals(SESSION_S, snap.confirmedSessionId, "도장 (b): 열린 행에서 온 값")
    }

    @Test
    fun weakBackstopIsNotLaunderedToStrongOnRestart() {
        val r = WorkStateRig(deviceId = WIN_DEVICE)
        r.own(SESSION_S, SessionClaimStrength.WEAK)
        r.apply(working(SESSION_S, at(-600), at(-20)))
        assertFalse(r.store.snapshot.value.ownsStrongly)
        assertEquals("weak", r.kv.getString(OwnedSessionLedger.OWNED_STRENGTH_KEY))
    }

    @Test
    fun rule18_lateTeamStatusDroppedByGeneration() {
        val r = WorkStateRig()
        val stale = r.store.workStateWriteGeneration
        r.store.start()
        r.queue.drain()
        r.apply(offWork(0, at(-30)), generation = stale)
        assertTrue(r.store.snapshot.value.isWorking, "⑱ 시작 전 세대의 '퇴근' 응답이 시작을 되돌리지 못한다")
        r.apply(offWork(0, at(-30)))
        assertFalse(r.store.snapshot.value.isWorking, "현재 세대 응답은 반영")
    }

    @Test
    fun pendingQueueBlocksRemoteApply() {
        val r = WorkStateRig()
        r.store.start()
        r.apply(offWork(0, at(-30)))
        assertTrue(r.store.snapshot.value.isWorking, "줄에 항목이 남아 있으면 서버 스냅숏으로 덮지 않는다")
    }

    @Test
    fun serverClosed_a_liveSessionClosedAtSleepTime() {
        val r = WorkStateRig()
        r.store.start()
        val id = r.store.currentSessionId!!
        r.queue.drain()
        r.policy.marker = SleepCloseMarker(id.uppercase(), T0, at(3_600), at(3_000))
        r.now = at(7_200)
        r.apply(offWork(0, at(3_600)))
        val stop = r.queue.items.value.single()
        assertEquals(PendingWorkOperation.Stop(3_000), stop.operation)
        assertEquals(at(3_000), stop.endedAt, "endedAt = max(start, min(sleepBegan, lastInput))")
        assertEquals(AutoCloseReason.SLEEP, stop.autoCloseReason)
        assertNull(r.store.currentSessionId)
        assertNull(r.policy.marker)
        assertEquals(listOf<WorkEvent>(WorkEvent.AutoClosed(AutoCloseReason.SLEEP, at(3_000))), r.events)
    }

    @Test
    fun serverClosed_b_relaunchEnqueuesCorrection_onlyForOwnedMarker() {
        val r = WorkStateRig()
        r.own(SESSION_S, SessionClaimStrength.STRONG)
        r.policy.marker = SleepCloseMarker(SESSION_S, at(-7_200), at(-3_600), null)
        r.apply(offWork(0, at(-3_600)))
        val stop = r.queue.items.value.single()
        assertEquals(SESSION_S, stop.sessionId)
        assertEquals(PendingWorkOperation.Stop(3_600), stop.operation)
        assertEquals(AutoCloseReason.SLEEP, stop.autoCloseReason)
        assertNull(r.store.ownedSessionId)

        val stranger = WorkStateRig()
        stranger.own(SESSION_X, SessionClaimStrength.STRONG)
        stranger.policy.marker = SleepCloseMarker(SESSION_S, at(-7_200), at(-3_600), null)
        stranger.apply(offWork(0, at(-3_600)))
        assertTrue(stranger.queue.items.value.isEmpty(), "내 것이 아닌 마커로는 정정하지 않는다")
    }

    @Test
    fun remoteEnded_abandonedVsElsewhere() {
        val a = WorkStateRig()
        a.store.start()
        a.queue.drain()
        a.now = at(3_600)
        a.apply(offWork(2_900, at(2_900)))
        val snap = a.store.snapshot.value
        assertEquals(WorkStateConstants.REMOTE_ABANDONED_CLOSE_NOTICE, snap.syncMessage)
        assertEquals(AutoCloseReason.ABANDONED, snap.lastAutoClose?.reason)
        assertEquals(2_900, snap.lastAutoClose?.seconds)
        assertEquals(listOf<WorkEvent>(WorkEvent.AutoClosed(AutoCloseReason.ABANDONED, at(2_900))), a.events)
        assertFalse("suppress" in a.policy.calls)

        val e = WorkStateRig()
        e.store.start()
        e.queue.drain()
        e.now = at(3_600)
        e.apply(offWork(3_500, at(3_500)))
        assertEquals(WorkStateConstants.REMOTE_ENDED_ELSEWHERE_NOTICE, e.store.snapshot.value.syncMessage)
        assertTrue("suppress" in e.policy.calls)
        assertTrue(e.events.isEmpty())
    }

    @Test
    fun rule15c_stampClearedWhenOpenRowDiffers_thenAdopted() {
        val r = WorkStateRig(deviceId = WIN_DEVICE)
        r.store.start()
        r.queue.drain()
        val id = r.store.currentSessionId!!
        r.store.setConfirmedServerSessionId(id)
        r.apply(working(id, T0, at(10)))
        assertEquals(id, r.store.confirmedSessionId, "같은 열린 행이면 도장 유지")
        r.apply(working(id, T0, at(20), openSession = false))
        assertEquals(id, r.store.confirmedSessionId, "(c) 는 열린 행이 있을 때만 지운다")
        r.apply(working(SESSION_X, at(60), at(90)))
        assertTrue(r.store.adoptedRemoteSession)
        assertEquals(SESSION_X, r.store.confirmedSessionId, "(c) 로 지우고 흡수가 (b) 로 다시 찍는다")
        assertNull(r.store.planWorkTick()!!.sessionId, "흡수 세션은 tick 에 세션 id 0")
    }

    @Test
    fun rule16_yieldMatrix() {
        fun adoptedAfter(device: String, own: SessionClaimStrength, claimDevice: String, opened: Boolean): Boolean {
            val r = WorkStateRig(deviceId = device)
            r.own(SESSION_S, own)
            r.apply(working(SESSION_S, at(-3_600), at(-10)))
            r.apply(working(SESSION_S, at(-3_600), at(-10), listOf(StatusDeviceClaim(claimDevice, SESSION_S, at(-20), opened))))
            assertFalse(r.store.adoptedRemoteSession, "첫 관측만으로는 물러나지 않는다(전진이 필요)")
            r.apply(working(SESSION_S, at(-3_600), at(-10), listOf(StatusDeviceClaim(claimDevice, SESSION_S, at(10), opened))))
            return r.store.adoptedRemoteSession
        }
        assertTrue(adoptedAfter(WIN_DEVICE, SessionClaimStrength.WEAK, MAC_DEVICE, false), "동급 약함: 'win:' > 맥 대문자 → Windows 가 물러난다")
        assertFalse(adoptedAfter(MAC_DEVICE, SessionClaimStrength.WEAK, WIN_DEVICE, false), "같은 상황의 맥은 버틴다")
        assertFalse(adoptedAfter(WIN_DEVICE, SessionClaimStrength.STRONG, MAC_DEVICE, false), "강한 쪽은 버틴다")
        assertTrue(adoptedAfter(WIN_DEVICE, SessionClaimStrength.WEAK, MAC_DEVICE, true), "약한 쪽은 강한 주장에 물러난다")
        assertFalse(adoptedAfter(MAC_DEVICE, SessionClaimStrength.STRONG, WIN_DEVICE, true), "동급 강함(이론상): 'win:' < 맥 id 가 거짓이라 맥은 버틴다")
        assertFalse(WorkClaimRules.yieldsToClaim(WIN_DEVICE, true, true, MAC_DEVICE), "동급 강함: 맥은 'win:' 에 물러나지 않는다")
        assertTrue(WorkClaimRules.yieldsToClaim(MAC_DEVICE, true, true, WIN_DEVICE), "동급 강함: Windows 가 물러난다")
        assertFalse(WorkClaimRules.yieldsToClaim(MAC_DEVICE, false, false, null), "기기 신원 없음: 동급에서 물러나지 않는다")
    }

    @Test
    fun rule23_autoCloseIsNoOpForAdoptedSession() {
        val r = WorkStateRig()
        r.apply(working(SESSION_X, at(-600), at(-15)))
        r.store.closeOwnedSessionLocally(T0, AutoCloseReason.SLEEP, "x")
        assertTrue(r.store.snapshot.value.isWorking)
        assertTrue(r.queue.items.value.isEmpty())
        assertTrue(r.events.isEmpty())
    }

    @Test
    fun autoClose_recordsResumeTarget_andResumeKeepsStrength() = runBlocking {
        val r = WorkStateRig(deviceId = WIN_DEVICE)
        r.store.start()
        val id = r.store.currentSessionId!!
        r.queue.drain()
        r.now = at(1_800)
        r.store.closeOwnedSessionLocally(at(1_800), AutoCloseReason.AWAY, "자리 비움")
        assertEquals(listOf<WorkEvent>(WorkEvent.AutoClosed(AutoCloseReason.AWAY, at(1_800))), r.events)
        assertEquals(1_800, r.store.snapshot.value.accumulatedTodaySeconds)
        r.queue.drain()
        val calls = mutableListOf<Pair<String, String>>()
        r.reopen = WorkReopenCall { t, s -> calls += t to s }
        r.now = at(1_800 + 29 * 60)
        assertTrue(r.store.canResumeRecentlyClosed())
        r.store.performResumeRecentlyClosed()
        assertEquals(listOf(TEAM to id), calls)
        val snap = r.store.snapshot.value
        assertTrue(snap.isWorking && snap.ownsStrongly, "재개는 마감 때의 강도(strong)를 되살린다")
        assertEquals(T0, snap.startedAt)
        assertEquals(WorkStartOrigin.RESUME, snap.startOrigin)
        assertEquals(0, snap.accumulatedTodaySeconds, "마감 때 더한 몫을 되뺀다")
        assertTrue(r.queue.items.value.isEmpty(), "재개는 서버 reopen 으로 끝 — 줄에 넣지 않는다")
    }

    @Test
    fun resumeWindowAndLongSessionExclusion() {
        val late = WorkStateRig()
        late.store.start()
        late.store.closeOwnedSessionLocally(at(600), AutoCloseReason.SLEEP, "x")
        late.now = at(600 + 30 * 60 + 1)
        assertFalse(late.store.canResumeRecentlyClosed(), "30분 창 밖")
        late.store.resumeRecentlyClosed()
        assertNull(late.store.snapshot.value.lastAutoClose, "창 밖이면 재개 대상을 지운다")

        val long = WorkStateRig()
        long.store.start()
        long.store.closeOwnedSessionLocally(at(12 * 3_600), AutoCloseReason.LONG_SESSION, "x")
        assertFalse(long.store.canResumeRecentlyClosed(), "12h 마감은 재개 대상이 아니다")
    }

    @Test
    fun nudgeStartEmitsOnceAndPokeFactsReflectOwnRow() {
        val r = WorkStateRig(deviceId = WIN_DEVICE)
        r.store.start(WorkStartOrigin.NUDGE)
        r.store.start(WorkStartOrigin.NUDGE)
        assertEquals(listOf<WorkEvent>(WorkEvent.NudgeStarted), r.events)
        assertEquals(WorkStartOrigin.NUDGE, r.store.snapshot.value.startOrigin)

        val a = WorkStateRig(deviceId = WIN_DEVICE)
        a.input = at(-3)
        a.apply(working(SESSION_X.uppercase(), at(-600), at(-15), listOf(StatusDeviceClaim(MAC_DEVICE, SESSION_X.uppercase(), at(-15)))))
        a.store.advanceMeaningfulInput()
        val facts = a.store.pokeConsumeFacts()
        assertTrue(facts.localSessionOpen && facts.adoptedRemoteSession)
        assertEquals(SESSION_X, facts.canonicalSessionID)
        assertEquals(SESSION_X, facts.ownOpenSessionID)
        assertEquals(listOf(MAC_DEVICE to SESSION_X), facts.ownDeviceClaims, "세션 id 는 정규화, 기기 id 는 원문")
        assertEquals(WIN_DEVICE, facts.deviceID)
        assertEquals(at(-3), facts.lastMeaningfulInputAt)
        assertNull(WorkStateRig().store.pokeConsumeFacts().ownDeviceClaims, "내 행을 아직 못 봤으면 판정 불가(null)")
    }

    @Test
    fun weakBackstopReclaimAfterThreeStalledObservations() {
        val r = WorkStateRig(deviceId = WIN_DEVICE)
        val seen = at(-400)
        r.apply(working(SESSION_X, at(-3_600), seen))
        assertTrue(r.store.adoptedRemoteSession)
        listOf(0, 60, 120).forEach { t ->
            r.now = at(t)
            r.apply(working(SESSION_X, at(-3_600), seen))
            assertTrue(r.store.adoptedRemoteSession, "정체 5분 전엔 되찾지 않는다(t=$t)")
        }
        r.now = at(300)
        r.apply(working(SESSION_X, at(-3_600), seen))
        assertFalse(r.store.adoptedRemoteSession, "3회·5분 정체 → 약하게 되찾는다")
        assertEquals("weak", r.kv.getString(OwnedSessionLedger.OWNED_STRENGTH_KEY))
        assertFalse(r.store.snapshot.value.ownsStrongly)
    }

    @Test
    fun backstopDoesNotReclaimWhileForeignDeviceClaimsSession() {
        val r = WorkStateRig(deviceId = WIN_DEVICE)
        val seen = at(-400)
        val claims = listOf(StatusDeviceClaim(MAC_DEVICE, SESSION_X, seen))
        r.apply(working(SESSION_X, at(-3_600), seen, claims))
        listOf(0, 60, 120, 300).forEach { t ->
            r.now = at(t)
            r.apply(working(SESSION_X, at(-3_600), seen, claims))
        }
        assertTrue(r.store.adoptedRemoteSession, "남의 기기 행이 이 세션을 주장하면 백스톱을 세우지 않는다")
    }

    @Test
    fun accountSwitchResetsLocalState() {
        val r = WorkStateRig()
        r.store.adoptWorkStateOwner(ME)
        r.store.start()
        r.store.adoptWorkStateOwner(ME)
        assertTrue(r.store.snapshot.value.isWorking, "같은 계정이면 그대로")
        r.store.adoptWorkStateOwner("someone-else")
        val snap = r.store.snapshot.value
        assertFalse(snap.isWorking)
        assertNull(snap.sessionId)
        assertNull(r.store.ownedSessionId)
        assertTrue("clearAway" in r.policy.calls)
    }

    @Test
    fun signedOutStartMarksLoginRequired() {
        val r = WorkStateRig(userId = null)
        r.store.start()
        assertTrue(r.queue.items.value.isEmpty())
        assertEquals(WorkStateConstants.LOGIN_REQUIRED, r.store.snapshot.value.syncMessage)
        assertTrue(r.store.snapshot.value.pendingSync)
        assertNull(r.store.planWorkTick(), "로그인 없음 → 틱 대신 레거시 경로")
    }

    @Test
    fun confirmStillWorkingOnlyWhilePromptShown() {
        val r = WorkStateRig()
        r.store.confirmStillWorking()
        assertFalse("longConfirmed" in r.policy.calls)
        r.store.start()
        r.store.showLongSessionPrompt(at(12 * 3_600))
        assertEquals(at(12 * 3_600), r.store.snapshot.value.longSessionPromptShownAt)
        r.store.confirmStillWorking()
        assertNull(r.store.snapshot.value.longSessionPromptShownAt)
        assertTrue("longConfirmed" in r.policy.calls)
    }

    /** 구조 시험(주석을 걷고 스캔): 상태 코어는 금지 표·열을 이름으로도 쓰지 않는다. */
    @Test
    fun forbiddenWritesAbsentFromStateSources() {
        val dir = File("src/commonMain/kotlin/com/yehsung/aingcheck/feature/desktop/work/state")
        val files = dir.listFiles { f -> f.extension == "kt" }.orEmpty()
        assertTrue(files.size >= 3, "상태 코어 소스를 찾지 못했다: ${dir.absolutePath}")
        val forbidden = listOf("app_build", "app_version", "token_usage_monthly", "take_pokes", "/rest/v1/profiles")
        for (f in files) {
            val code = f.readText()
                .replace(Regex("/\\*.*?\\*/", RegexOption.DOT_MATCHES_ALL), "")
                .lines().joinToString("\n") { it.substringBefore("//") }
            for (word in forbidden) assertFalse(word in code, "${f.name} 에 금지어 $word")
        }
    }
}
