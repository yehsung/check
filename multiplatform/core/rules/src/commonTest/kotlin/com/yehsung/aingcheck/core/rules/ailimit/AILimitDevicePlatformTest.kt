// 원본: Tests/CheckMobileKitTests/V1016PCLabelTests.swift(가르는 키 · 대체 이름 · 맥만 있는 명부 불변 · 맥+PC 무꼬리) @ 1a5eeca6
// 기대값은 Swift 시험의 글자 리터럴 그대로다(구현 상수로 기대값을 쓰지 않는다).
package com.yehsung.aingcheck.core.rules.ailimit

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class AILimitDevicePlatformTest {
    private fun device(id: String, label: String? = null) = AILimitDevice(id, label, null)

    /** 소문자 `win:` 접두만 PC 다 — 대문자·다른 접두·빈 값은 맥(서버 프로브와 같은 입력). */
    @Test
    fun platformKeyMirrorsServer() {
        assertEquals("win:", AILimitDevicePlatform.windowsPrefix)
        assertEquals(AILimitDevicePlatform.windows, AILimitDevicePlatform.of("win:0b7e4b1c-1111-2222-3333-44445555a1b2"))
        assertEquals(AILimitDevicePlatform.mac, AILimitDevicePlatform.of("WIN:abc"), "대소문자를 느슨하게 받으면 서버와 판정이 갈린다")
        assertEquals(AILimitDevicePlatform.mac, AILimitDevicePlatform.of("Win:abc"))
        assertEquals(AILimitDevicePlatform.mac, AILimitDevicePlatform.of("A0A0A0A0-0000-0000-0000-000000000000"), "맥 식별자는 대문자 UUID 다")
        assertEquals(AILimitDevicePlatform.mac, AILimitDevicePlatform.of(""))
        assertEquals(AILimitDevicePlatform.mac, AILimitDevicePlatform.of("winner:1"), "콜론까지가 접두다(서버 like 'win:%' 도 이 값을 mac 으로 읽는다)")
    }

    /** 이름을 안 올린 기기: 맥은 `이름 모를 맥 ABCD` · PC 는 `이름 모를 PC ABCD`. */
    @Test
    fun unnamedPrefixFollowsPlatform() {
        assertEquals("이름 모를 맥 9F8E", device("DEVICE-9F8E").baseName)
        assertEquals("이름 모를 PC A1B2", device("win:0b7e4b1c-1111-2222-3333-44445555a1b2").baseName)
        assertEquals("이름 모를 맥", AILimitDevice.unnamedPrefix)
        assertEquals("이름 모를 PC", AILimitDevice.unnamedPCPrefix)
    }

    /** 이름을 올린 기기에는 종류 낱말이 없다 — 사람이 적은 컴퓨터 이름 그대로. */
    @Test
    fun namedDeviceKeepsItsOwnName() {
        assertEquals("DESKTOP-4F2K", device("win:0b7e-a1b2", "DESKTOP-4F2K").baseName)
        assertEquals("거실 Mac mini", device("DEVICE-77AA", "거실 Mac mini").baseName)
    }

    /** 맥만 있는 명부는 글자가 1비트도 안 바뀐다 — 이 판에서 지킬 불변. */
    @Test
    fun macOnlyRosterIsUnchanged() {
        val names = AILimitDeviceRoster.displayNames(
            listOf(device("DEVICE-9F8E"), device("DEVICE-2B1C"), device("AAAA-77AA", "Mac mini"), device("BBBB-88BB", "Mac mini"), device("CCCC-99CC", "사무실 iMac")),
        )
        assertEquals("이름 모를 맥 9F8E", names["DEVICE-9F8E"])
        assertEquals("이름 모를 맥 2B1C", names["DEVICE-2B1C"])
        assertEquals("Mac mini (77AA)", names["AAAA-77AA"], "겹친 이름의 꼬리 규칙이 바뀌었다")
        assertEquals("Mac mini (88BB)", names["BBBB-88BB"])
        assertEquals("사무실 iMac", names["CCCC-99CC"], "안 겹치는 이름에는 아무것도 붙지 않는다")
    }

    /** 맥 하나 + PC 하나가 둘 다 이름이 없어도 서로 갈린다 — 종류 낱말이 이미 다르므로 꼬리가 안 붙는다. */
    @Test
    fun macAndPCUnnamedDoNotCollide() {
        val parts = AILimitDeviceRoster.displayNameParts(listOf(device("DEVICE-A1B2"), device("win:0000-0000-0000-a1b2")))
        assertEquals("이름 모를 맥 A1B2", parts["DEVICE-A1B2"]?.base)
        assertNull(parts["DEVICE-A1B2"]?.tail)
        assertEquals("이름 모를 PC A1B2", parts["win:0000-0000-0000-a1b2"]?.base)
        assertNull(parts["win:0000-0000-0000-a1b2"]?.tail, "꼬리까지 붙으면 같은 꼬리 둘이 나란히 서서 가르는 뜻을 잃는다")
    }
}
