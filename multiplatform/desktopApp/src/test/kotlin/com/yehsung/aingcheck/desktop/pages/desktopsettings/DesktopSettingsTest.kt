package com.yehsung.aingcheck.desktop.pages.desktopsettings

import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.nudge.AutoStartSuppression
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** W-9 #3 설정 저장소 · W-9 #4 단축키 기록기. 키 글자는 맥 원본 줄(WorkTimerStore.swift:3560-3574 · CheckApp.swift:757 · MacEdition.swift:178)과 같아야 한다. */
class DesktopSettingsTest {
    private fun chord(vk: Int, ctrl: Boolean = false, alt: Boolean = false, shift: Boolean = false, win: Boolean = false) =
        HotkeyChord(ctrl = ctrl, alt = alt, shift = shift, win = win, keyCode = vk)

    @Test
    fun keysAreMacUserDefaultsKeys() {
        assertEquals("check.overlayEnabled", DesktopSettingsKeys.OVERLAY_ENABLED)
        assertEquals("check.todoEnabled", DesktopSettingsKeys.TODO_ENABLED)
        assertEquals("check.todoBoardOpacity", DesktopSettingsKeys.TODO_BOARD_OPACITY)
        assertEquals("check.work.autoStartEnabled", DesktopSettingsKeys.AUTO_WORK_START)
        assertEquals("check.workShortcut.enabled", DesktopSettingsKeys.WORK_SHORTCUT_ENABLED)
        assertEquals("check.workShortcut.combo", DesktopSettingsKeys.WORK_SHORTCUT_COMBO)
        assertEquals("check.launchAtLogin.userTurnedOff", DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF)
        assertEquals("check.mas.aiToolDataConsent", DesktopSettingsKeys.AI_TOOL_DATA_CONSENT)
        // 넛지 두 키는 쓰는 쪽(AutoStartSuppression)과 같은 글자여야 다시 읽힌다.
        assertEquals(AutoStartSuppression.SUPPRESSED_KEY, DesktopSettingsKeys.NUDGE_AUTO_START_SUPPRESSED)
        assertEquals(AutoStartSuppression.LAST_ALIVE_KEY, DesktopSettingsKeys.NUDGE_LAST_ALIVE_AT)
    }

    @Test
    fun defaultsFollowMacExceptConsentWhichStartsRefused() {
        val s = DesktopSettingsStore(InMemoryDesktopKeyValueStore())
        assertTrue(s.autoWorkStart.value)
        assertTrue(s.overlayEnabled.value)
        assertFalse(s.tokenUsageCollect.value, "동의 전 수집 0 — 기본 거절")
        assertEquals(HotkeySetting(true, HotkeyPolicy.DEFAULT), s.hotkey.value)
        assertTrue(s.launchAtLogin.value)
        assertEquals(TodoBoardSetting(true, null), s.todoBoard.value)
        assertEquals(NudgeSetting(false, null), s.nudge.value)
        assertFalse(s.hotkeyRecording.value)
    }

    @Test
    fun changesFlowAndPersistAcrossRestart() {
        val kv = InMemoryDesktopKeyValueStore()
        val s = DesktopSettingsStore(kv)
        s.setAutoWorkStart(false)
        s.setOverlayEnabled(false)
        s.setTokenUsageCollect(true)
        s.setHotkeyEnabled(false)
        assertTrue(s.setHotkey(chord(0x4B, ctrl = true, alt = true)))
        s.setLaunchAtLogin(false)
        s.setTodoEnabled(false)
        s.setTodoBoardOpacity(0.6)
        assertFalse(s.autoWorkStart.value)
        assertEquals(chord(0x4B, ctrl = true, alt = true), s.hotkey.value.chord)
        assertEquals("true", kv.getString("check.launchAtLogin.userTurnedOff"))
        val again = DesktopSettingsStore(kv)
        assertFalse(again.autoWorkStart.value)
        assertFalse(again.overlayEnabled.value)
        assertTrue(again.tokenUsageCollect.value)
        assertEquals(HotkeySetting(false, chord(0x4B, ctrl = true, alt = true)), again.hotkey.value)
        assertFalse(again.launchAtLogin.value)
        assertEquals(TodoBoardSetting(false, 0.6), again.todoBoard.value)
        again.resetHotkey()
        assertNull(kv.getString(DesktopSettingsKeys.WORK_SHORTCUT_COMBO))
        assertEquals(HotkeyPolicy.DEFAULT, DesktopSettingsStore(kv).hotkey.value.chord)
    }

    @Test
    fun forbiddenChordChangesNothing() {
        val kv = InMemoryDesktopKeyValueStore()
        val s = DesktopSettingsStore(kv)
        assertFalse(s.setHotkey(chord(0x4B, ctrl = true, alt = true, win = true)), "Win 조합")
        assertFalse(s.setHotkey(chord(0x4B, ctrl = true)), "수식키 하나")
        assertFalse(s.setHotkey(chord(HotkeyPolicy.VK_F12, ctrl = true, alt = true)), "F12")
        assertEquals(HotkeyPolicy.DEFAULT, s.hotkey.value.chord)
        assertNull(kv.getString(DesktopSettingsKeys.WORK_SHORTCUT_COMBO))
        // 깨진 값·정책이 거절하는 저장 값은 기본값으로 읽는다.
        kv.putString(DesktopSettingsKeys.WORK_SHORTCUT_COMBO, "ctrl:75")
        assertEquals(HotkeyPolicy.DEFAULT, DesktopSettingsStore(kv).hotkey.value.chord)
        kv.putString(DesktopSettingsKeys.WORK_SHORTCUT_COMBO, "garbage")
        assertEquals(HotkeyPolicy.DEFAULT, DesktopSettingsStore(kv).hotkey.value.chord)
        assertEquals(chord(0x20, ctrl = true, alt = true, shift = true), HotkeyChordCodec.decode(HotkeyChordCodec.encode(HotkeyPolicy.DEFAULT)))
    }

    @Test
    fun launchActualReflectsWithoutRewritingIntent() {
        val kv = InMemoryDesktopKeyValueStore()
        val s = DesktopSettingsStore(kv)
        s.reflectLaunchAtLoginActual(false)
        assertFalse(s.launchAtLogin.value)
        assertNull(kv.getString(DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF), "실제 상태 반영은 사용자 뜻 키를 쓰지 않는다")
    }

    @Test
    fun nudgeReloadReadsSuppressionKeys() {
        val kv = InMemoryDesktopKeyValueStore()
        val s = DesktopSettingsStore(kv)
        kv.putBoolean(AutoStartSuppression.SUPPRESSED_KEY, true)
        kv.putLong(AutoStartSuppression.LAST_ALIVE_KEY, 1_790_000_000_000)
        assertEquals(NudgeSetting(false, null), s.nudge.value)
        s.reloadNudge()
        assertEquals(NudgeSetting(true, 1_790_000_000_000), s.nudge.value)
    }

    // ---------------------------------------------------------------- 기록기

    @Test
    fun recorderSavesAllowedChordAndStops() {
        val s = DesktopSettingsStore(InMemoryDesktopKeyValueStore())
        val r = HotkeyRecorder(s)
        r.start()
        assertTrue(s.hotkeyRecording.value)
        assertEquals(HotkeyKeyResult.Ignored, r.onKey(0x11, ctrl = true, alt = false, shift = false, win = false), "수식키만 — 기다린다")
        assertEquals(HotkeyKeyResult.Saved(chord(0x4B, ctrl = true, alt = true)), r.onKey(0x4B, ctrl = true, alt = true, shift = false, win = false))
        assertFalse(s.hotkeyRecording.value)
        assertEquals(chord(0x4B, ctrl = true, alt = true), s.hotkey.value.chord)
    }

    @Test
    fun recorderRejectsAndKeepsRecording() {
        val s = DesktopSettingsStore(InMemoryDesktopKeyValueStore())
        val r = HotkeyRecorder(s)
        r.start()
        assertEquals(HotkeyKeyResult.Rejected(HotkeyPolicy.Rejection.WIN_KEY_RESERVED), r.onKey(0x4B, true, true, false, true))
        assertEquals(HotkeyNotice.REJECTED_SYSTEM, HotkeyNotice.resolve(true, r.lastRejection, s.hotkeyStatus.value, true))
        assertEquals(HotkeyKeyResult.Rejected(HotkeyPolicy.Rejection.RESERVED_KEY), r.onKey(HotkeyPolicy.VK_F12, true, true, false, false))
        assertEquals(HotkeyKeyResult.Rejected(HotkeyPolicy.Rejection.TOO_FEW_MODIFIERS), r.onKey(0x4B, true, false, false, false))
        assertEquals(HotkeyNotice.REJECTED_SHAPE, HotkeyNotice.resolve(true, r.lastRejection, s.hotkeyStatus.value, true))
        assertEquals(HotkeyKeyResult.Rejected(HotkeyPolicy.Rejection.KEY_IS_IME), r.onKey(AwtToWindowsVk.map(0), true, true, false, false))
        assertEquals(HotkeyNotice.REJECTED_IME, HotkeyNotice.resolve(true, r.lastRejection, s.hotkeyStatus.value, true))
        // Ctrl+Esc 는 취소가 아니다(수식키 없는 Esc 만 취소).
        assertEquals(HotkeyKeyResult.Rejected(HotkeyPolicy.Rejection.TOO_FEW_MODIFIERS), r.onKey(0x1B, true, false, false, false))
        assertTrue(s.hotkeyRecording.value)
        assertEquals(HotkeyPolicy.DEFAULT, s.hotkey.value.chord)
        assertEquals(HotkeyKeyResult.Cancelled, r.onKey(0x1B, false, false, false, false))
        assertFalse(s.hotkeyRecording.value)
        assertEquals(HotkeyKeyResult.Ignored, r.onKey(0x4B, true, true, false, false), "기록 중이 아니면 무시")
    }

    @Test
    fun switchingOffEndsRecordingAndHidesOldConflict() {
        val s = DesktopSettingsStore(InMemoryDesktopKeyValueStore())
        val r = HotkeyRecorder(s)
        r.start()
        s.setHotkeyEnabled(false)
        assertFalse(s.hotkeyRecording.value)
        r.start()
        assertFalse(s.hotkeyRecording.value, "끈 상태에선 기록을 시작하지 않는다")
        s.noteHotkeyStatus(HotkeyRegistrationStatus.CONFLICT)
        assertNull(HotkeyNotice.resolve(false, null, HotkeyRegistrationStatus.CONFLICT, enabled = false))
        assertEquals(HotkeyNotice.CONFLICT, HotkeyNotice.resolve(false, null, HotkeyRegistrationStatus.CONFLICT, enabled = true))
        assertEquals(HotkeyNotice.FAILED, HotkeyNotice.resolve(false, null, HotkeyRegistrationStatus.FAILED, enabled = true))
        assertNull(HotkeyNotice.resolve(false, null, HotkeyRegistrationStatus.ACTIVE, enabled = true))
        assertEquals(HotkeyNotice.RECORDING, HotkeyNotice.resolve(true, null, HotkeyRegistrationStatus.PAUSED, enabled = true))
    }

    @Test
    fun noticeTextsFollowMacSentences() {
        // 맥 CheckSettingsView.swift:956-960 의 다섯 줄 — '⌃ ⌥ ⌘'·'esc'·'macOS 단축키' 자리만 Windows 말로.
        assertEquals("Ctrl Alt Shift 중 두 개 이상과 함께 눌러요 · Esc 취소", HotkeyNotice.RECORDING.text)
        assertEquals("Ctrl Alt Shift 중 두 개 이상을 함께 눌러 주세요", HotkeyNotice.REJECTED_SHAPE.text)
        assertEquals("단축키를 등록하지 못했어요.", HotkeyNotice.FAILED.text)
        assertTrue(HotkeyNotice.CONFLICT.text.endsWith("다른 키로 바꿔 주세요."))
        assertTrue(HotkeyNotice.REJECTED_SYSTEM.text.endsWith("다른 조합을 눌러 주세요"))
    }

    @Test
    fun keyNamesAndAwtMapping() {
        assertEquals("Ctrl+Alt+Shift+Space", WindowsKeyNames.display(HotkeyPolicy.DEFAULT))
        assertEquals("Ctrl+Alt+F13", WindowsKeyNames.display(chord(0x7C, ctrl = true, alt = true)))
        assertEquals("Alt+Shift+키 255", WindowsKeyNames.display(chord(0xFF, alt = true, shift = true)))
        assertEquals(0x0D, AwtToWindowsVk.map(10))
        assertEquals(0x7C, AwtToWindowsVk.map(61440))
        assertEquals(0xBA, AwtToWindowsVk.map(59))
        assertEquals(0x41, AwtToWindowsVk.map(65))
        assertEquals(0x2E, AwtToWindowsVk.map(127))
        assertEquals(0x5B, AwtToWindowsVk.map(524))
        assertNull(AwtToWindowsVk.map(0x10000))
    }
}
