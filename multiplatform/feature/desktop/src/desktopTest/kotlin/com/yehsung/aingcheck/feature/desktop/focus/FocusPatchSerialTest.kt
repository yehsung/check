// 원본: Sources/check/WorkTimerStorePoke.swift 1040-1234(★F5 PATCH 직렬화 · F6 만료 실패 60초 · F7 사용자 실패 원복 · F4) @ a90d8623
package com.yehsung.aingcheck.feature.desktop.focus

import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.ultra.FakeServer
import com.yehsung.aingcheck.feature.desktop.ultra.FakeSessionHost
import com.yehsung.aingcheck.feature.desktop.ultra.PROFILES_PATH
import com.yehsung.aingcheck.feature.desktop.ultra.Reply
import com.yehsung.aingcheck.feature.desktop.ultra.TEST_USER
import com.yehsung.aingcheck.feature.desktop.ultra.TestClock
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FocusPatchSerialTest {
    private class Rig(scope: TestScope, vararg patchReplies: Reply) {
        val clock = TestClock()
        val server = FakeServer(scope).on("PATCH", PROFILES_PATH, *patchReplies)
        val host = FakeSessionHost(server.service(clock::now))
        val kv = InMemoryDesktopKeyValueStore()
        val notices = mutableListOf<String>()
        val focus = FocusModeController(host, kv, scope, clock::now) { notices += it }
        val patches: List<String> get() = server.calls.filter { it.method == "PATCH" }.map { it.body }
    }

    @Test
    fun threeQuickTapsSendAtMostTwoPatchesEndingWithLastIntent() = runTest {
        // ★F5 첫 PATCH 를 붙잡아 둔 채 세 번 누른다(끔 → 3시간 → 계속 → 끔). 날아가는 동안의 의도는 끝난 뒤 마지막 하나로.
        val gate = CompletableDeferred<Unit>()
        val rig = Rig(this, Reply.Hold(gate, Reply.Json("", 204)), Reply.Json("", 204))
        rig.focus.applyServerFocusMode(false, rig.focus.intentSerial) // 서버가 끔을 확인했다
        rig.focus.cycleFocusStage()
        runCurrent()
        rig.focus.cycleFocusStage()
        rig.focus.cycleFocusStage()
        runCurrent()
        assertEquals(1, rig.patches.size, "날아가는 동안 두 번째 PATCH 는 없다")
        gate.complete(Unit)
        advanceUntilIdle()
        assertTrue(rig.patches.size <= 2, "세 번 연타 → PATCH ${rig.patches.size}건")
        assertEquals("""{"focus_mode":false}""", rig.patches.last(), "마지막 의도(끔)")
        assertEquals(false, rig.focus.serverValue)
        assertFalse(rig.focus.isFocusOn)
        assertNull(rig.focus.record(TEST_USER), "끔으로 확정되면 기록을 비운다")
    }

    @Test
    fun expiryPatchFailureDoesNotRestoreAndRetriesAfter60Seconds() = runTest {
        // ★F6 만료로 끈 PATCH 가 실패 → 원복 0 · 기록 유지 · 60초 뒤 다시.
        val rig = Rig(this, Reply.Json("", 204), Reply.Json("""{"message":"down"}""", 503), Reply.Json("", 204))
        rig.focus.applyServerFocusMode(false, rig.focus.intentSerial)
        rig.focus.cycleFocusStage() // 3시간 켬
        advanceUntilIdle()
        assertEquals(listOf("""{"focus_mode":true}"""), rig.patches)
        rig.clock.advance(FocusStagePolicy.TIMED_DURATION_SECONDS)
        rig.focus.evaluateFocusStageExpiry(rig.clock.now())
        advanceUntilIdle()
        assertEquals(2, rig.patches.size)
        assertFalse(rig.focus.isFocusOn, "원복하지 않는다(사용자는 이미 끝난 3시간을 다시 보지 않는다)")
        assertTrue(rig.notices.isEmpty(), "만료 실패는 안내하지 않는다")
        assertNotNull(rig.focus.record(TEST_USER), "기록은 남긴다(다시 보낼 근거)")
        val retryAt = assertNotNull(rig.focus.expiryRetryAt)
        assertEquals(60.0, retryAt.timeIntervalSince(rig.clock.now()))
        rig.clock.advance(59.0)
        rig.focus.evaluateFocusStageExpiry(rig.clock.now())
        advanceUntilIdle()
        assertEquals(2, rig.patches.size, "59초 = 아직")
        rig.clock.advance(1.0)
        rig.focus.evaluateFocusStageExpiry(rig.clock.now())
        advanceUntilIdle()
        assertEquals(3, rig.patches.size, "60초 = 다시 보낸다")
        assertEquals(false, rig.focus.serverValue)
        assertNull(rig.focus.record(TEST_USER))
        assertNull(rig.focus.expiryRetryAt)
    }

    @Test
    fun userPatchFailureRestoresServerValueWithNotice() = runTest {
        // ★F7 사용자가 누른 PATCH 실패 → 서버가 확인한 값(끔)으로 원복 + 안내.
        val rig = Rig(this, Reply.Json("""{"message":"down"}""", 503))
        rig.focus.applyServerFocusMode(false, rig.focus.intentSerial)
        rig.focus.cycleFocusStage()
        assertTrue(rig.focus.isFocusOn, "낙관 갱신")
        advanceUntilIdle()
        assertFalse(rig.focus.isFocusOn)
        assertNull(rig.focus.record(TEST_USER))
        assertEquals(listOf(FocusStagePolicy.CHANGE_FAILED_NOTICE), rig.notices)
    }

    @Test
    fun serverOnWithoutRecordIsAlways() = runTest {
        // ★F4 서버 켜짐 + 이 기기 기록 없음 = always(바꾸지 않는다). 요청 0.
        val rig = Rig(this, Reply.Json("", 204))
        rig.focus.applyServerFocusMode(true, rig.focus.intentSerial)
        advanceUntilIdle()
        assertTrue(rig.focus.isFocusOn)
        assertEquals(FocusStage.ALWAYS, rig.focus.focusStage(rig.clock.now()))
        assertTrue(rig.patches.isEmpty())
    }

    @Test
    fun restartWithExpiredTimedRecordTurnsOffImmediately() = runTest {
        // 앱이 꺼진 동안 끝난 1단 → 서버 켜짐을 받자마자 끔 PATCH(재시작 만료).
        val rig = Rig(this, Reply.Json("", 204))
        FocusStageRecords(rig.kv).write(FocusStageRecord(FocusStage.TIMED, rig.clock.now().addingTimeInterval(-1.0)), TEST_USER)
        rig.focus.applyServerFocusMode(true, rig.focus.intentSerial)
        advanceUntilIdle()
        assertEquals(listOf("""{"focus_mode":false}"""), rig.patches)
        assertFalse(rig.focus.isFocusOn)
    }

    @Test
    fun focusStageHasNoSideEffects() = runTest {
        // ★F8 읽기는 요청도 기록도 바꾸지 않는다.
        val rig = Rig(this, Reply.Json("", 204))
        FocusStageRecords(rig.kv).write(FocusStageRecord(FocusStage.TIMED, rig.clock.now().addingTimeInterval(-1.0)), TEST_USER)
        rig.host.session = null
        rig.focus.setFocusMode(true)
        rig.host.session = SupabaseSession("access-token", null, TEST_USER)
        val before = rig.kv.snapshot()
        repeat(3) {
            rig.focus.focusStage(rig.clock.now())
            rig.focus.focusStageFace(rig.clock.now())
        }
        advanceUntilIdle()
        assertEquals(before, rig.kv.snapshot())
        assertTrue(rig.patches.isEmpty())
        assertTrue(rig.focus.isFocusOn)
    }
}
