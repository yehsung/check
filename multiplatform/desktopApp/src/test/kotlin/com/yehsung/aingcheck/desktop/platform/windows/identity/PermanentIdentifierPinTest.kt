// 원본: 없음(새 시험) — G §8-13(영구 식별자는 지금 잠근다: Windows installation_id 이름공간 aafb227d-…·MSI upgradeUuid 6798ece1-…,
//       둘 다 값 고정 시험으로 묶는다) · K6 · 기억 device-identity-must-not-be-invented
package com.yehsung.aingcheck.desktop.platform.windows.identity

import java.io.File
import java.util.Properties
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.fail

/**
 * **영구 식별자 고정(G §8-13).** 첫 출시 뒤 이 값들이 바뀌면
 *  - 이름공간·이름 꼴·접두: 모든 Windows 기기가 새 기기로 보여 같은 토큰이 두 기기 행으로 올라간다(순위표 두 배).
 *  - MSI upgradeUuid: 새 판이 옛 판을 업그레이드로 알아보지 못해 둘이 나란히 깔린다.
 * 기대값은 **손으로 적은 글자**다(구현 상수에서 다시 만들지 않는다). 이 시험을 고쳐 초록으로 만들지 마라 — 값을 바꾸는 것은
 * 설계 결정이고, 바꾸면 기존 설치가 전부 갈린다.
 */
class PermanentIdentifierPinTest {
    @Test
    fun installationIdNamespaceIsPinned() {
        assertEquals("aafb227d-cd3f-5244-9eb4-8496576dbc12", WindowsDeviceIdentity.NAMESPACE.toString())
        assertEquals("https://github.com/yehsung/check#windows-installation-id/v1", WindowsDeviceIdentity.NAMESPACE_NAME)
    }

    @Test
    fun nameLayoutAndDeviceIdPrefixArePinned() {
        // 이름 꼴: "aing-check|" + 소문자 MachineGuid + "|" + 대문자 SID. 레지스트리 쪽 대소문자·공백은 다듬어 같은 이름이 된다.
        assertEquals(
            "aing-check|6ba7b810-9dad-11d1-80b4-00c04fd430c8|S-1-5-21-1004336348-1177238915-682003330-1001",
            WindowsDeviceIdentity.name(" 6BA7B810-9DAD-11D1-80B4-00C04FD430C8\r\n", "s-1-5-21-1004336348-1177238915-682003330-1001 "),
        )
        assertEquals("win:", WindowsDeviceIdentity.DEVICE_ID_PREFIX)
    }

    @Test
    fun endToEndVectorFromAnotherImplementationIsPinned() {
        // Python 3: uuid.uuid5(uuid.UUID('aafb227d-cd3f-5244-9eb4-8496576dbc12'),
        //   'aing-check|6ba7b810-9dad-11d1-80b4-00c04fd430c8|S-1-5-21-1004336348-1177238915-682003330-1001') (2026-10-22 다시 계산).
        val id = WindowsDeviceIdentity.installationId("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "S-1-5-21-1004336348-1177238915-682003330-1001")
        assertEquals("43c6f224-3251-5e0a-b887-c5ccf28a2f96", id)
        assertEquals("win:43c6f224-3251-5e0a-b887-c5ccf28a2f96", WindowsDeviceIdentity.deviceId(id))
    }

    @Test
    fun msiUpgradeUuidIsPinned() {
        // 값의 자리는 조정자 몫 multiplatform/version.properties(빌드 논리 aingcheck.desktop-app 이 versions.required 로 읽는다).
        val mp = System.getProperty("aingcheck.mpRoot") ?: fail("aingcheck.mpRoot 시스템 속성이 없다(aingcheck.test-seal 밖 실행)")
        val props = Properties().apply { File(mp, "version.properties").reader(Charsets.UTF_8).use { load(it) } }
        assertEquals("6798ece1-0749-4a92-856f-ca1f4847c522", props.getProperty("windowsUpgradeUuid"))
    }
}
