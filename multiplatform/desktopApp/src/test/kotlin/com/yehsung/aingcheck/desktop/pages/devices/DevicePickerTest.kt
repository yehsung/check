package com.yehsung.aingcheck.desktop.pages.devices

import com.yehsung.aingcheck.core.rules.ailimit.AILimitDevice
import com.yehsung.aingcheck.desktop.pages.ailimits.AiLimitsFixture
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 맥 AILimitMainDeviceSettingsRow(CheckSettingsView.swift:261-345) — 이름 겹침 꼬리 · 고른 표시 · 두 대 이상일 때만. */
class DevicePickerTest {
    @Test
    fun rowsCarryTailForDuplicateNamesAndMarkEffectiveMain() {
        val store = AiLimitsFixture.store()
        val rows = DevicePickerModel.rows(store.devices, store.mainDeviceID)
        assertEquals(listOf("win:aaaa1111", "mac:bbbb2222", "win:cccc3333"), rows.map { it.deviceID })
        assertEquals("DESK-01", rows[0].parts.base)
        assertTrue(rows[0].parts.tail != null && rows[2].parts.tail != null && rows[0].parts.tail != rows[2].parts.tail, "같은 이름 둘은 꼬리로 가른다")
        assertNull(rows[1].parts.tail)
        // 고른 기기 없음 → 가장 최근(맥 AILimitMainDeviceRule).
        assertEquals(listOf(true, false, false), rows.map { it.selected })
        assertEquals(listOf(false, true, false), DevicePickerModel.rows(store.devices, "mac:bbbb2222").map { it.selected })
        // 사라진 기기를 골라 뒀으면 다시 최근으로.
        assertEquals(listOf(true, false, false), DevicePickerModel.rows(store.devices, "win:gone").map { it.selected })
    }

    @Test
    fun pickerOnlyWithTwoOrMoreDevices() {
        assertFalse(DevicePickerModel.showsPicker(emptyList()))
        assertFalse(DevicePickerModel.showsPicker(listOf(AILimitDevice("win:a", "A", 1.0))))
        assertTrue(DevicePickerModel.showsPicker(listOf(AILimitDevice("win:a", "A", 1.0), AILimitDevice("win:b", "B", 2.0))))
    }

    @Test
    fun choosingGoesThroughActions() = runBlocking {
        val store = AiLimitsFixture.store()
        val actions = AiLimitsFixture.FakeActions(store)
        actions.setMainDevice("win:cccc3333")
        assertEquals(listOf("main:win:cccc3333"), actions.calls)
        assertEquals(listOf(false, false, true), DevicePickerModel.rows(store.devices, store.mainDeviceID).map { it.selected })
    }

    @Test
    fun desktopWordingSaysComputerNotMac() {
        // W-9 #5: 데스크톱 새 문구는 '컴퓨터' — '맥' 글자가 남지 않는다.
        for (text in listOf(DevicePickerText.TITLE, DevicePickerText.DETAIL, DevicePickerText.SINGLE)) {
            assertFalse("맥" in text, text)
            assertTrue("컴퓨터" in text, text)
        }
    }
}
