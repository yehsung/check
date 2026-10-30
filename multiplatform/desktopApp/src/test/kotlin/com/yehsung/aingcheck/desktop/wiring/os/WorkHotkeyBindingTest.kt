// 원본: Sources/check/WorkShortcut.swift:331-406 @ a63fea2 (apply · handlePress) — 시험은 새 코드. 가짜 HotkeyService 만(창·스레드 0).
package com.yehsung.aingcheck.desktop.wiring.os

import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyRegistrationResult
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyService
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class WorkHotkeyBindingTest {
    /** 녹음하는 가짜. [held] 에 든 조합은 '다른 앱이 쥐고 있다'(1409). */
    private class FakeHotkeys : HotkeyService {
        val log = mutableListOf<String>()
        val held = mutableSetOf<HotkeyChord>()
        val live = mutableMapOf<HotkeyChord, () -> Unit>()
        override fun register(chord: HotkeyChord, onPressed: () -> Unit): HotkeyRegistrationResult {
            log += "register ${chord.keyCode}"
            if (chord in held || chord in live) return HotkeyRegistrationResult.Conflict(1409)
            live[chord] = onPressed
            return HotkeyRegistrationResult.Registered(Registration { log += "unregister ${chord.keyCode}"; live.remove(chord) })
        }
        fun press(chord: HotkeyChord) = live.getValue(chord).invoke()
    }

    private val f12Chord = HotkeyChord(ctrl = true, alt = true, shift = false, win = false, keyCode = HotkeyPolicy.VK_F12)
    private val altChord = HotkeyChord(ctrl = true, alt = true, shift = false, win = false, keyCode = 0x4B /* K */)

    private class Rig(scope: TestScope, initial: HotkeyChord?) {
        val hotkeys = FakeHotkeys()
        val chord = MutableStateFlow(initial)
        val recording = MutableStateFlow(false)
        var now = 10_000L
        var allowed = true
        var toggles = 0
        var rejections = 0
        val binding = WorkHotkeyBinding(
            service = hotkeys, chord = chord, recording = recording,
            canToggle = { allowed }, toggle = { toggles++ }, onRejected = { rejections++ },
            monotonicMillis = { now }, registerContext = StandardTestDispatcher(scope.testScheduler),
        )
        val job = binding.start(scope.backgroundScope)
    }

    @Test
    fun `기본 조합 등록 → Active, 누르면 토글, 끄면 풀고 Off`() = runTest {
        val r = Rig(this, HotkeyPolicy.DEFAULT)
        runCurrent()
        assertEquals(WorkHotkeyStatus.Active(HotkeyPolicy.DEFAULT), r.binding.status.value)
        r.hotkeys.press(HotkeyPolicy.DEFAULT)
        assertEquals(1, r.toggles)
        r.chord.value = null
        runCurrent()
        assertEquals(WorkHotkeyStatus.Off, r.binding.status.value)
        assertEquals(listOf("register 32", "unregister 32"), r.hotkeys.log)
        assertTrue(r.hotkeys.live.isEmpty())
    }

    @Test
    fun `다른 앱이 쥔 조합 → Conflict(1409) 흐름, 키가 풀리면 reapply 로 Active`() = runTest {
        val r = Rig(this, HotkeyPolicy.DEFAULT)
        r.hotkeys.held += HotkeyPolicy.DEFAULT
        runCurrent()
        assertEquals(WorkHotkeyStatus.Conflict(HotkeyPolicy.DEFAULT, 1409), r.binding.status.value)
        r.hotkeys.held.clear()
        r.binding.reapply()
        runCurrent()
        assertEquals(WorkHotkeyStatus.Active(HotkeyPolicy.DEFAULT), r.binding.status.value)
    }

    @Test
    fun `조합을 바꾸면 옛 것을 먼저 풀고 새 것을 건다 · 규칙 위반은 등록 시도 0`() = runTest {
        val r = Rig(this, HotkeyPolicy.DEFAULT)
        runCurrent()
        r.chord.value = altChord
        runCurrent()
        assertEquals(WorkHotkeyStatus.Active(altChord), r.binding.status.value)
        assertEquals(listOf("register 32", "unregister 32", "register 75"), r.hotkeys.log)
        r.chord.value = f12Chord
        runCurrent()
        assertEquals(WorkHotkeyStatus.Invalid(f12Chord, HotkeyPolicy.Rejection.RESERVED_KEY), r.binding.status.value)
        assertEquals("unregister 75", r.hotkeys.log.last(), "규칙 위반 조합을 등록하려 했다")
    }

    @Test
    fun `기록 중이면 내린다(Paused) — 지금 조합을 다시 눌러 지정해도 토글되지 않는다`() = runTest {
        val r = Rig(this, HotkeyPolicy.DEFAULT)
        runCurrent()
        r.recording.value = true
        runCurrent()
        assertEquals(WorkHotkeyStatus.Paused, r.binding.status.value)
        assertTrue(r.hotkeys.live.isEmpty())
        r.recording.value = false
        runCurrent()
        assertEquals(WorkHotkeyStatus.Active(HotkeyPolicy.DEFAULT), r.binding.status.value)
    }

    @Test
    fun `연타 가드 1·5초 — 거부된 누름은 시각을 남기지 않는다`() = runTest {
        val r = Rig(this, HotkeyPolicy.DEFAULT)
        runCurrent()
        r.hotkeys.press(HotkeyPolicy.DEFAULT)
        r.now += 1_499
        r.hotkeys.press(HotkeyPolicy.DEFAULT)
        assertEquals(1, r.toggles, "1.5초 안의 두 번째 누름이 토글했다")
        r.now += 1
        r.allowed = false
        r.hotkeys.press(HotkeyPolicy.DEFAULT)
        assertEquals(1, r.rejections)
        r.allowed = true
        r.now += 10
        r.hotkeys.press(HotkeyPolicy.DEFAULT)
        assertEquals(2, r.toggles, "거부 직후 조건이 풀렸는데 키가 먹통이다")
    }

    @Test
    fun `close 는 풀고 Off`() = runTest {
        val r = Rig(this, HotkeyPolicy.DEFAULT)
        runCurrent()
        r.binding.close()
        runCurrent()
        assertEquals(WorkHotkeyStatus.Off, r.binding.status.value)
        assertTrue(r.hotkeys.live.isEmpty())
    }
}
