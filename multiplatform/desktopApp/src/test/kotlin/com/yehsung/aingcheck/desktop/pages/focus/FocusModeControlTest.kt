// W3-c3 집중 모드 단추 — 맥 CheckFocusModeButton.swift(문구·겉모습 표) · FocusStagePolicy(3시간) · PATCH profiles.focus_mode 1건.
package com.yehsung.aingcheck.desktop.pages.focus

import com.yehsung.aingcheck.desktop.pages.ultra.FakeServer
import com.yehsung.aingcheck.desktop.pages.ultra.FakeSessionHost
import com.yehsung.aingcheck.desktop.pages.ultra.ME
import com.yehsung.aingcheck.desktop.pages.ultra.PROFILES_PATH
import com.yehsung.aingcheck.desktop.pages.ultra.Reply
import com.yehsung.aingcheck.desktop.pages.ultra.TestClock
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.focus.FocusModeController
import com.yehsung.aingcheck.feature.desktop.focus.FocusStage
import com.yehsung.aingcheck.feature.desktop.focus.FocusStageFace
import com.yehsung.aingcheck.feature.desktop.focus.FocusStagePolicy
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class FocusModeControlTest {
    @Test
    fun `누름 한 번 = PATCH 1건 · 1단 · 남은 시간은 FocusStagePolicy 에서`() = runTest {
        val server = FakeServer(this).on("PATCH", PROFILES_PATH, Reply.Json("", 204))
        val clock = TestClock()
        val host = FakeSessionHost(server.service(clock::now))
        val controller = FocusModeController(host, InMemoryDesktopKeyValueStore(), this, clock::now)
        val model = FocusModeModel(controller, clock::now)
        assertEquals(FocusStage.OFF, model.face().stage)
        assertEquals("집중", FocusModeText.label(model.face()))
        assertEquals("집중 모드 꺼짐 — 누르면 3시간 집중", FocusModeText.tooltip(model.face()))

        model.press()
        advanceUntilIdle()
        assertEquals(1, server.count("PATCH", PROFILES_PATH), "PATCH 수")
        val call = server.calls.single { it.method == "PATCH" }
        assertEquals("""{"focus_mode":true}""", call.body)
        assertTrue(("id" to "eq.$ME") in call.query, "자기 행만: ${call.query}")
        val face = model.face()
        assertEquals(FocusStageFace(FocusStage.TIMED, FocusStagePolicy.TIMED_DURATION_SECONDS.toInt()), face)
        assertEquals("1단", FocusModeText.label(face))
        assertEquals("1단 · 3시간 남음 — 한 번 더 누르면 끌 때까지 계속", FocusModeText.tooltip(face))
        clock.advance(1.0)
        assertEquals("1단 · 2시간 59분 남음 — 한 번 더 누르면 끌 때까지 계속", FocusModeText.tooltip(model.face()), "분은 내림")
        clock.advance(FocusStagePolicy.TIMED_DURATION_SECONDS - 30)
        assertEquals("1단, 곧 해제 남음", FocusModeText.accessibilityValue(model.face()))
        clock.advance(30.0)
        assertEquals(FocusStage.OFF, model.face().stage, "3시간이 지나면 꺼짐으로 읽는다(만료 PATCH 는 박자 몫)")
        assertEquals(1, server.count("PATCH", PROFILES_PATH), "읽기(face)는 요청을 내지 않는다(F8)")
    }

    @Test
    fun `세 번 누름 — 1단 → 2단 → 끔 · 각 단계 PATCH 1건씩`() = runTest {
        val server = FakeServer(this).on("PATCH", PROFILES_PATH, Reply.Json("", 204))
        val clock = TestClock()
        val controller = FocusModeController(FakeSessionHost(server.service(clock::now)), InMemoryDesktopKeyValueStore(), this, clock::now)
        val model = FocusModeModel(controller, clock::now)
        model.press(); advanceUntilIdle()
        model.press(); advanceUntilIdle()
        assertEquals(FocusStageFace(FocusStage.ALWAYS), model.face())
        assertEquals("2단", FocusModeText.label(model.face()))
        assertEquals("2단 · 끌 때까지 계속 — 누르면 집중 모드 해제", FocusModeText.tooltip(model.face()))
        // 1단 → 2단은 서버 값이 그대로(켜짐)라 PATCH 를 내지 않는다(F5 — 이미 같으면 0).
        assertEquals(1, server.count("PATCH", PROFILES_PATH))
        model.press(); advanceUntilIdle()
        assertEquals(FocusStage.OFF, model.face().stage)
        assertEquals(listOf("""{"focus_mode":true}""", """{"focus_mode":false}"""), server.bodies("PATCH", PROFILES_PATH))
    }

    @Test
    fun `남은 시간 표 — 맥 FocusModeButtonText remaining`() {
        val table = mapOf(0 to "곧 해제", 59 to "곧 해제", 60 to "1분", 3599 to "59분", 3600 to "1시간", 3660 to "1시간 1분", 10_799 to "2시간 59분", 10_800 to "3시간")
        for ((s, want) in table) assertEquals(want, FocusModeText.remaining(s), "$s 초")
        assertEquals("3시간", FocusModeText.timedDurationText)
    }

    @Test
    fun `겉모습 표 — 어느 두 단계도 바탕·달·글자 중 둘 이상 다르다`() {
        val stages = FocusStage.entries
        for (a in stages) for (b in stages) {
            if (a == b) continue
            val sa = FocusModeStyle(a)
            val sb = FocusModeStyle(b)
            val differs = listOf(sa.fillLevel != sb.fillLevel, sa.icon != sb.icon, FocusModeText.label(FocusStageFace(a)) != FocusModeText.label(FocusStageFace(b)))
            assertTrue(differs.count { it } >= 2, "$a vs $b")
        }
    }
}
