// W-13 #8 — 기기 낱말: 'win:'(소문자 — 서버 거울) → PC, 그 밖 → 맥, 빈 id → 컴퓨터. 라벨은 그대로, 겹치면 꼬리.
package com.yehsung.aingcheck.desktop.pages.devices

import com.yehsung.aingcheck.core.rules.ailimit.AILimitDevice
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceNameParts
import kotlin.test.Test
import kotlin.test.assertEquals

class DesktopDeviceNamesTest {
    @Test
    fun `낱말 — win 은 PC, 그 밖은 맥, 빈 것만 컴퓨터`() {
        assertEquals("PC", DesktopDeviceWord.of("win:3f2a9c1e"))
        assertEquals("맥", DesktopDeviceWord.of("8F14E45F-CEEA-467A-9575-0000000000AB"))
        assertEquals("맥", DesktopDeviceWord.of("WIN:3f2a"), "대문자 WIN: 은 서버 거울(like 'win:%')이 Windows 로 안 본다")
        assertEquals("컴퓨터", DesktopDeviceWord.of(""))
        assertEquals("컴퓨터", DesktopDeviceWord.of(null))
    }

    @Test
    fun `이름 — 라벨 없으면 기기마다 낱말, 라벨은 그대로, 같은 기본 이름만 꼬리`() {
        val devices = listOf(
            AILimitDevice("win:aaaa1111", null, 3.0),
            AILimitDevice("mac-bbbb2222", null, 2.0),
            AILimitDevice("win:cccc3333", "사무실", 1.0),
            AILimitDevice("mac-dddd4444", "사무실", 0.5),
        )
        val parts = DesktopDeviceNames.parts(devices)
        assertEquals(AILimitDeviceNameParts("이름 모를 PC 1111", null), parts["win:aaaa1111"])
        assertEquals(AILimitDeviceNameParts("이름 모를 맥 2222", null), parts["mac-bbbb2222"])
        assertEquals(AILimitDeviceNameParts("사무실", "3333"), parts["win:cccc3333"])
        assertEquals(AILimitDeviceNameParts("사무실", "4444"), parts["mac-dddd4444"])
        val rows = DevicePickerModel.rows(devices, mainDeviceID = "win:aaaa1111")
        assertEquals("이름 모를 PC 1111", rows.first().parts.base, "기기 고르기 줄이 데스크톱 이름 규칙을 안 탄다")
        assertEquals(listOf(true, false, false, false), rows.map { it.selected })
    }
}
