// 원본: Sources/check/WorkTimerStore.swift:1142-1148 @ a63fea2 (맥은 UUID 를 한 번 만들어 둔다) — 시험은 새 코드:
//       G §5-1 #6(레지스트리를 못 읽으면 무작위 UUID — 써 놓고 다시 읽어 같을 때만, 아니면 토큰 업로드 0)
//       · 기억 device-identity-must-not-be-invented · R2 검증 지적(I1: '다시 읽어 같을 때만' 비교를 지워도 초록이었다)
package com.yehsung.aingcheck.desktop.platform.windows.identity

import org.junit.jupiter.api.io.TempDir
import java.io.IOException
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

    /**
     * 저장 이음매 가짜: 쓰기는 늘 성공하고, 쓴 **뒤의** 읽기를 [readBack] 이 정한다(쓰기 전 읽기는 null — 파일 없음).
     * 디스크로는 "썼는데 다시 읽으니 다르다"를 싸게 만들 수 없어서 이 이음매로 주입한다.
     */
    private class ScriptedStore(private val readBack: (written: String) -> String?) : FallbackIdStore {
        var written: String? = null
        var writes = 0
        override fun read(): String? = written?.let(readBack)
        override fun write(text: String) {
            writes++
            written = text
        }
    }

    private fun resolveWith(store: ScriptedStore): WindowsInstallationIdentity =
        WindowsInstallationIdentity(FakeSource(null, sid), store, randomUuid = { UUID.fromString("0f3c2a1e-58f4-4b9e-9c1d-2a7b6e5d4c3b") })

    @Test
    fun faithfulStoreGivesTheWrittenValue() {
        // 기준선(다른 입력): 쓴 그대로 읽히면 그 값을 쓴다 — 아래 세 사례와 저장 결과만 다르다.
        val store = ScriptedStore { it }
        val identity = resolveWith(store)
        assertEquals(WindowsInstallationIdentity.Resolved("0f3c2a1e-58f4-4b9e-9c1d-2a7b6e5d4c3b", WindowsInstallationIdentity.Origin.FALLBACK_FILE), identity.resolve())
        assertEquals(1, store.writes)
    }

    @Test
    fun writeSucceedsButReadBackDiffersMeansNoIdentity() {
        // 쓰기는 성공했다고 했는데 다시 읽으니 다른(그러나 모양은 멀쩡한) 값 — 저장이 다른 자리로 갔거나 덮였다.
        val store = ScriptedStore { "9b2d6c1e-7a40-4f3e-8c55-1d2e3f405162\n" }
        val identity = resolveWith(store)
        val r = identity.resolve()
        assertEquals(WindowsInstallationIdentity.Origin.UNAVAILABLE, r.origin)
        assertNull(r.installationId)
        assertEquals(1, store.writes, "쓰기를 시도하지 않았다 — 이 사례는 '쓴 뒤 다시 읽기'를 재지 못한다")
        assertNull(WindowsDeviceIdentity.deviceId(r.installationId), "확인 안 된 신원으로 device_id 를 만들었다(토큰 업로드 0 이어야)")
    }

    @Test
    fun writeSucceedsButReadBackFailsMeansNoIdentity() {
        val store = ScriptedStore { throw IOException("주입된 다시 읽기 실패") }
        val r = resolveWith(store).resolve()
        assertEquals(WindowsInstallationIdentity.Resolved(null, WindowsInstallationIdentity.Origin.UNAVAILABLE), r)
        assertEquals(1, store.writes)
    }

    @Test
    fun writeSucceedsButValueVanishesMeansNoIdentity() {
        val store = ScriptedStore { null }
        val r = resolveWith(store).resolve()
        assertEquals(WindowsInstallationIdentity.Resolved(null, WindowsInstallationIdentity.Origin.UNAVAILABLE), r)
        assertEquals(1, store.writes)
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
