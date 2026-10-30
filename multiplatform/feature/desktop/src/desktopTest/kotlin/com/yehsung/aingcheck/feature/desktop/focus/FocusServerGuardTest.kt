// 원본: Sources/check/WorkTimerStorePoke.swift 1110-1132(★F9 PATCH 세대 가드 — 1128 guard generation == sessionGeneration)
//       · 1185-1200(★F10 늦은 서버 GET — 1197 의도 번호가 바뀌었고 서버값을 이미 알면 버린다)
//       · 834-842(★F11 서버값 로드는 성공할 때까지 — 날아가는 중엔 겹쳐 보내지 않는다) @ a90d8623
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

/** 합성 둘째 사용자(실제 계정 아님). */
private const val OTHER_USER: String = "00000000-0000-0000-0000-0000000000CD"

private fun settings(focusOn: Boolean): Reply.Json =
    Reply.Json("""[{"token_usage_public":true,"token_usage_collect":true,"focus_mode":$focusOn}]""")

class FocusServerGuardTest {
    private class Rig(scope: TestScope) {
        val clock = TestClock()
        val server = FakeServer(scope)
        val host = FakeSessionHost(server.service(clock::now))
        val kv = InMemoryDesktopKeyValueStore()
        val notices = mutableListOf<String>()
        val focus = FocusModeController(host, kv, scope, clock::now) { notices += it }
        val patches: List<String> get() = server.calls.filter { it.method == "PATCH" }.map { it.body }
        val gets: Int get() = server.count("GET", PROFILES_PATH)
    }

    @Test
    fun f9PatchResultFromLeftSessionDoesNotTouchNewSession() = runTest {
        // ★F9 PATCH 가 날아가는 동안 로그아웃 → 다른 계정 로그인. 떠난 세션의 응답은 새 사용자의 서버값·PATCH 를 만지지 않는다.
        val gate = CompletableDeferred<Unit>()
        val rig = Rig(this)
        rig.server.on("PATCH", PROFILES_PATH, Reply.Hold(gate, Reply.Json("", 204)), Reply.Json("", 204))
        rig.focus.applyServerFocusMode(false, rig.focus.intentSerial)
        rig.focus.cycleFocusStage() // 3시간 켬 → PATCH true 날아감
        runCurrent()
        assertEquals(listOf("""{"focus_mode":true}"""), rig.patches)
        // 로그아웃(장부 비우기) + 세대 증가 + 다른 계정.
        rig.focus.reset()
        rig.host.sessionGeneration += 1
        rig.host.session = SupabaseSession("access-token-2", null, OTHER_USER)
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(1, rig.patches.size, "떠난 세션의 응답이 새 세션에 PATCH 를 만들지 않는다")
        assertNull(rig.focus.serverValue, "새 세션은 서버값을 아직 모른다(떠난 세션의 성공을 옮겨 적지 않는다)")
        assertFalse(rig.focus.isFocusOn)
        assertTrue(rig.notices.isEmpty())
    }

    @Test
    fun f10LateServerGetAfterConfirmedTapIsDropped() = runTest {
        // ★F10 GET 이 떠난 뒤 누른 3시간이 서버에 닿았다(serverValue 확인) → 늦게 온 GET(끔)은 화면·기록을 덮지 않는다.
        val gate = CompletableDeferred<Unit>()
        val rig = Rig(this)
        rig.server.on("GET", PROFILES_PATH, Reply.Hold(gate, settings(false)))
        rig.server.on("PATCH", PROFILES_PATH, Reply.Json("", 204))
        rig.focus.loadServerFocusMode()
        runCurrent()
        assertEquals(1, rig.gets)
        rig.focus.cycleFocusStage()
        runCurrent() // GET 을 붙잡은 동안엔 가상 시간을 넘기지 않는다(HttpTimeout 30초가 GET 을 죽인다)
        assertEquals(true, rig.focus.serverValue, "누름이 서버에 닿았다")
        gate.complete(Unit)
        advanceUntilIdle()
        assertTrue(rig.focus.isFocusOn, "늦은 GET(끔)이 방금 켠 1단을 끄지 않는다")
        assertEquals(true, rig.focus.serverValue)
        assertEquals(FocusStage.TIMED, assertNotNull(rig.focus.record(TEST_USER)).stage, "기록도 남는다")
        assertEquals(listOf("""{"focus_mode":true}"""), rig.patches)
    }

    @Test
    fun f10LateServerGetAfterFailedTapStillApplies() = runTest {
        // ★F10 짝: 누름이 실패해 서버값을 끝내 모른다 → 늦은 GET 이 아는 것 중 가장 새롭다 — 반영한다.
        val gate = CompletableDeferred<Unit>()
        val rig = Rig(this)
        rig.server.on("GET", PROFILES_PATH, Reply.Hold(gate, settings(true)))
        rig.server.on("PATCH", PROFILES_PATH, Reply.Json("""{"message":"down"}""", 503))
        rig.focus.loadServerFocusMode()
        runCurrent()
        rig.focus.cycleFocusStage()
        runCurrent()
        assertNull(rig.focus.serverValue)
        assertFalse(rig.focus.isFocusOn, "F7 원복")
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(true, rig.focus.serverValue, "서버값을 몰랐으면 늦은 GET 도 반영한다")
        assertTrue(rig.focus.isFocusOn)
        assertEquals(FocusStage.ALWAYS, rig.focus.focusStage(rig.clock.now()), "F4 서버 켜짐 + 기록 없음 = 계속")
    }

    @Test
    fun f11ServerLoadRetriesUntilSuccessButNeverStacks() = runTest {
        // ★F11 실패하면 다음 박자에 다시(성공 때만 '받았다'). 날아가는 중엔 몇 번 불러도 GET 1건.
        val gate = CompletableDeferred<Unit>()
        val rig = Rig(this)
        rig.server.on("GET", PROFILES_PATH, Reply.Offline, Reply.Hold(gate, settings(true)))
        rig.focus.loadServerFocusMode()
        advanceUntilIdle()
        assertEquals(1, rig.gets)
        assertNull(rig.focus.serverValue, "실패 = 아직 모른다")
        repeat(4) {
            rig.focus.loadServerFocusMode()
            runCurrent()
        }
        assertEquals(2, rig.gets, "날아가는 GET 이 있으면 겹쳐 보내지 않는다")
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(true, rig.focus.serverValue)
        repeat(3) {
            rig.focus.loadServerFocusMode()
            advanceUntilIdle()
        }
        assertEquals(2, rig.gets, "한 번 받으면 같은 세션에선 다시 묻지 않는다")
    }
}
