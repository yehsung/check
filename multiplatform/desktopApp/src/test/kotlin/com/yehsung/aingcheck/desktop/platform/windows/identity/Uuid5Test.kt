// 원본: 없음(새 시험) — RFC 9562 §5.5(UUIDv5) · 설계 D§2-5 · G §5-1 #6 · K6. 기대값은 Python 3 uuid.uuid5 로 따로 낸 벡터
package com.yehsung.aingcheck.desktop.platform.windows.identity

import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

/**
 * K6 신원 계산. 기대값은 **다른 구현**(Python 3 표준 uuid.uuid5, 2026-10-21 이 맥에서 계산)에서 왔다 —
 * 같은 Kotlin 함수로 기대값을 만들면 틀린 구현도 초록이다(기억 comparison-baseline-must-differ).
 */
class Uuid5Test {
    @Test
    fun matchesPublishedVector() {
        // uuid.uuid5(uuid.NAMESPACE_DNS, 'python.org') — Python 문서의 예.
        assertEquals("886313e1-3b8a-5372-9b90-0c9aee199e5d", Uuid5.nameBased(Uuid5.NAMESPACE_DNS, "python.org").toString())
    }

    @Test
    fun namespaceIsDerivedFromItsDocumentedName() {
        assertEquals(WindowsDeviceIdentity.NAMESPACE, Uuid5.nameBased(Uuid5.NAMESPACE_URL, WindowsDeviceIdentity.NAMESPACE_NAME))
        assertEquals("aafb227d-cd3f-5244-9eb4-8496576dbc12", WindowsDeviceIdentity.NAMESPACE.toString())
    }

    @Test
    fun installationIdMatchesPythonForFixedInputs() {
        val cases = listOf(
            Triple("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "S-1-5-21-1004336348-1177238915-682003330-1001", "43c6f224-3251-5e0a-b887-c5ccf28a2f96"),
            Triple("0f3c2a1e-58f4-4b9e-9c1d-2a7b6e5d4c3b", "S-1-5-21-1004336348-1177238915-682003330-1001", "e43443c9-bc88-5404-9cca-2a2282577227"),
            Triple("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "S-1-5-21-1004336348-1177238915-682003330-1002", "e982f2df-b680-58c4-ab79-b1922199baa8"),
            Triple("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "S-1-5-21-3623811015-3361044348-30300820-1013", "f7651fc2-2687-5b42-8e44-12b2f603b110"),
        )
        for ((guid, sid, expected) in cases) {
            assertEquals(expected, WindowsDeviceIdentity.installationId(guid, sid), "$guid · $sid")
        }
    }

    @Test
    fun anyInputChangeChangesTheId() {
        val base = WindowsDeviceIdentity.installationId("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "S-1-5-21-1-2-3-1001")
        assertNotEquals(base, WindowsDeviceIdentity.installationId("6ba7b810-9dad-11d1-80b4-00c04fd430c9", "S-1-5-21-1-2-3-1001"))
        assertNotEquals(base, WindowsDeviceIdentity.installationId("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "S-1-5-21-1-2-3-1002"))
    }

    @Test
    fun outputIsLowercaseVersion5RfcVariant() {
        val id = WindowsDeviceIdentity.installationId("6BA7B810-9DAD-11D1-80B4-00C04FD430C8", "S-1-5-21-1-2-3-1001")!!
        assertEquals(id.lowercase(), id)
        val u = UUID.fromString(id)
        assertEquals(5, u.version())
        assertEquals(2, u.variant())
    }

    @Test
    fun registryCaseAndWhitespaceDoNotSplitTheDevice() {
        // MachineGuid 는 보통 소문자지만 대문자·공백이 섞여도 같은 기기여야 한다(기기가 둘로 갈리면 순위표 두 배).
        val a = WindowsDeviceIdentity.installationId("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "S-1-5-21-1-2-3-1001")
        val b = WindowsDeviceIdentity.installationId(" 6BA7B810-9DAD-11D1-80B4-00C04FD430C8\n", " s-1-5-21-1-2-3-1001 ")
        assertEquals(a, b)
    }

    @Test
    fun malformedInputsAreRejectedInsteadOfHashed() {
        assertNull(WindowsDeviceIdentity.installationId("not-a-guid", "S-1-5-21-1-2-3-1001"))
        assertNull(WindowsDeviceIdentity.installationId("1-2-3-4-5", "S-1-5-21-1-2-3-1001"))
        assertNull(WindowsDeviceIdentity.installationId("6ba7b810-9dad-11d1-80b4-00c04fd430c8", ""))
        assertNull(WindowsDeviceIdentity.installationId("6ba7b810-9dad-11d1-80b4-00c04fd430c8", "tester"))
    }

    @Test
    fun deviceIdIsWinPrefixPlusLowercaseInstallationId() {
        assertEquals("win:43c6f224-3251-5e0a-b887-c5ccf28a2f96", WindowsDeviceIdentity.deviceId("43C6F224-3251-5E0A-B887-C5CCF28A2F96"))
        assertNull(WindowsDeviceIdentity.deviceId(null))
    }
}
