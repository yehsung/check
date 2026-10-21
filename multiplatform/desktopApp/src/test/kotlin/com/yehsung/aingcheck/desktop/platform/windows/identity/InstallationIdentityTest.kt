package com.yehsung.aingcheck.desktop.platform.windows.identity

import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** G §5-1 #6: 레지스트리 → UUIDv5. 못 읽으면 무작위 UUID 를 써 놓고 다시 읽어 같을 때만, 아니면 null(토큰 업로드 0). */
class InstallationIdentityTest {
    @field:TempDir
    lateinit var tmp: Path

    private class FakeSource(var guid: String?, var sid: String?, var throws: Boolean = false) : MachineIdentitySource {
        override fun machineGuid(): String? = if (throws) error("레지스트리 접근 거부") else guid
        override fun userSid(): String? = if (throws) error("토큰 거부") else sid
    }

    private val guid = "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
    private val sid = "S-1-5-21-1004336348-1177238915-682003330-1001"

    @Test
    fun machineDerivedIsStableAcrossFreshInstancesAndWritesNothing() {
        val file = tmp.resolve("aing-check/installation-id")
        val a = WindowsInstallationIdentity(FakeSource(guid, sid), file, randomUuid = { error("무작위를 쓰면 안 된다") }).resolve()
        val b = WindowsInstallationIdentity(FakeSource(guid, sid), file, randomUuid = { error("무작위를 쓰면 안 된다") }).resolve()
        assertEquals(WindowsInstallationIdentity.Origin.MACHINE_DERIVED, a.origin)
        assertEquals("43c6f224-3251-5e0a-b887-c5ccf28a2f96", a.installationId)
        assertEquals(a, b)
        assertFalse(Files.exists(file), "레지스트리를 읽었는데 폴백 파일을 만들었다")
    }

    @Test
    fun registryUnavailableFallsBackToVerifiedRandomFileAndReusesIt() {
        val file = tmp.resolve("aing-check/installation-id")
        val first = UUID.fromString("0F3C2A1E-58F4-4B9E-9C1D-2A7B6E5D4C3B")
        val a = WindowsInstallationIdentity(FakeSource(null, sid), file, randomUuid = { first }).resolve()
        assertEquals(WindowsInstallationIdentity.Origin.FALLBACK_FILE, a.origin)
        assertEquals("0f3c2a1e-58f4-4b9e-9c1d-2a7b6e5d4c3b", a.installationId)
        assertEquals("0f3c2a1e-58f4-4b9e-9c1d-2a7b6e5d4c3b", Files.readString(file).trim())
        // 다음 실행(새 인스턴스)은 다른 무작위를 받아도 파일의 값을 쓴다 — 재실행마다 새 기기가 되면 순위표 두 배.
        val b = WindowsInstallationIdentity(FakeSource(guid, null), file, randomUuid = { UUID.randomUUID() }).resolve()
        assertEquals(a.installationId, b.installationId)
        assertEquals(WindowsInstallationIdentity.Origin.FALLBACK_FILE, b.origin)
    }

    @Test
    fun sourceThatThrowsIsTreatedAsUnreadable() {
        val file = tmp.resolve("id")
        val r = WindowsInstallationIdentity(FakeSource(guid, sid, throws = true), file, randomUuid = { UUID(1, 2) }).resolve()
        assertEquals(WindowsInstallationIdentity.Origin.FALLBACK_FILE, r.origin)
        assertEquals(UUID(1, 2).toString(), r.installationId)
    }

    @Test
    fun malformedRegistryValueUsesFallbackInsteadOfHashingGarbage() {
        val file = tmp.resolve("id")
        val r = WindowsInstallationIdentity(FakeSource("garbage", sid), file, randomUuid = { UUID(3, 4) }).resolve()
        assertEquals(WindowsInstallationIdentity.Origin.FALLBACK_FILE, r.origin)
    }

    @Test
    fun unwritableFallbackMeansNoIdentityAndIsNotCached() {
        // 부모 자리에 파일이 있어 폴더를 못 만든다 → 쓰기 실패 → null(닫힘).
        val blocker = tmp.resolve("blocked")
        Files.writeString(blocker, "file, not a directory")
        val file = blocker.resolve("installation-id")
        val identity = WindowsInstallationIdentity(FakeSource(null, null), file, randomUuid = { UUID(5, 6) })
        val r = identity.resolve()
        assertEquals(WindowsInstallationIdentity.Origin.UNAVAILABLE, r.origin)
        assertNull(identity.installationId())
        assertNull(WindowsDeviceIdentity.deviceId(identity.installationId()), "신원이 없으면 device_id 도 없다(토큰 업로드 0)")
        // 실패는 캐시하지 않는다: 길이 열리면 다음 호출이 신원을 얻는다.
        Files.delete(blocker)
        val later = identity.resolve()
        assertEquals(WindowsInstallationIdentity.Origin.FALLBACK_FILE, later.origin)
        assertEquals(UUID(5, 6).toString(), later.installationId)
    }

    @Test
    fun corruptFallbackFileIsReplacedAndVerified() {
        val file = tmp.resolve("id")
        Files.writeString(file, "not a uuid\n")
        val r = WindowsInstallationIdentity(FakeSource(null, null), file, randomUuid = { UUID(7, 8) }).resolve()
        assertEquals(UUID(7, 8).toString(), r.installationId)
        assertTrue(Files.readString(file).trim() == UUID(7, 8).toString())
    }

    @Test
    fun resolvedValueIsPinnedForTheProcessLifetime() {
        val file = tmp.resolve("id")
        val src = FakeSource(guid, sid)
        val identity = WindowsInstallationIdentity(src, file)
        val first = identity.installationId()
        assertNotNull(first)
        src.sid = "S-1-5-21-9-9-9-1001" // 실행 중 값이 바뀌어도 같은 실행 안에서 기기가 둘이 되지 않는다
        assertEquals(first, identity.installationId())
    }
}
