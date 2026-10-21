package com.yehsung.aingcheck.desktop.platform.windows.runner

import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.desktop.platform.windows.vault.DataProtector
import com.yehsung.aingcheck.desktop.platform.windows.vault.DpapiProtector
import com.yehsung.aingcheck.desktop.platform.windows.vault.FileTokenVault
import com.yehsung.aingcheck.testkit.vault.TokenVaultContract
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.AclEntry
import java.nio.file.attribute.AclEntryPermission
import java.nio.file.attribute.AclEntryType
import java.nio.file.attribute.AclFileAttributeView
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

/** 진짜 DPAPI 위에 봉인 실패 스위치만 얹는다(CryptProtectData 실패 주입). */
class SwitchableDpapi(private val real: DataProtector = DpapiProtector()) : DataProtector {
    @Volatile var failProtect = false
    override fun protect(plain: ByteArray, entropy: ByteArray): ByteArray {
        if (failProtect) throw IllegalStateException("주입된 CryptProtectData 실패")
        return real.protect(plain, entropy)
    }
    override fun unprotect(sealed: ByteArray, entropy: ByteArray): ByteArray = real.unprotect(sealed, entropy)
}

/** G §2-3 W1-f ① DPAPI 금고 TokenVaultContract — 주입 ①: 봉인 단계 실패(이전 파일은 디스크에 그대로). */
@EnabledOnOs(OS.WINDOWS)
class DpapiProtectorFailureContractWindowsTest : TokenVaultContract() {
    @field:TempDir
    lateinit var tmp: Path

    override fun createSubject(): Subject {
        val dpapi = SwitchableDpapi()
        val vault = FileTokenVault(tmp.resolve("vault-${System.nanoTime()}"), dpapi)
        return object : Subject {
            override val vault: TokenVault = vault
            override fun breakWrites() {
                dpapi.failProtect = true
            }
        }
    }
}

/**
 * 주입 ②: 금고 폴더 ACL 에 '쓰기(파일 추가)·덧붙이기 거부'를 현재 사용자로 단다(D-E10 의 "읽기 전용 폴더" — Windows 폴더의 읽기 전용
 * 속성은 파일 만들기를 막지 않아 ACL 로 한다). 새 임시 파일을 못 만든다 → 금고는 대상 파일을 지워 낡은 값을 없애야 한다.
 */
@EnabledOnOs(OS.WINDOWS)
class DpapiAclDenyContractWindowsTest : TokenVaultContract() {
    @field:TempDir
    lateinit var tmp: Path
    private val restore = mutableListOf<Pair<Path, List<AclEntry>>>()

    override fun createSubject(): Subject {
        val dir = tmp.resolve("vault-${System.nanoTime()}")
        val vault = FileTokenVault(dir, DpapiProtector())
        return object : Subject {
            override val vault: TokenVault = vault
            override fun breakWrites() {
                Files.createDirectories(dir)
                val view = Files.getFileAttributeView(dir, AclFileAttributeView::class.java)
                val before = view.acl
                val me = dir.fileSystem.userPrincipalLookupService.lookupPrincipalByName(System.getProperty("user.name"))
                val deny = AclEntry.newBuilder()
                    .setType(AclEntryType.DENY)
                    .setPrincipal(me)
                    .setPermissions(AclEntryPermission.WRITE_DATA, AclEntryPermission.APPEND_DATA)
                    .build()
                view.acl = listOf(deny) + before
                restore.add(dir to before)
                // 주입이 실제로 걸렸는지 먼저 잰다(안 걸렸으면 이 시험은 아무것도 재지 않는다).
                val probe = runCatching { Files.createTempFile(dir, "probe", ".tmp").also { Files.delete(it) } }
                check(probe.isFailure) { "ACL 거부가 걸리지 않았다 — 임시 파일을 만들 수 있다" }
            }
        }
    }

    @AfterEach
    fun unlock() {
        for ((dir, acl) in restore) runCatching { Files.getFileAttributeView(dir, AclFileAttributeView::class.java).acl = acl }
    }
}

/** DPAPI 고유 성질(가짜 보호기로는 못 재는 것). */
@EnabledOnOs(OS.WINDOWS)
class DpapiFileRulesWindowsTest {
    @field:TempDir
    lateinit var tmp: Path

    @Test
    fun onDiskBytesAreADpapiBlobNotThePlaintext() {
        val vault = FileTokenVault(tmp.resolve("vault"), DpapiProtector())
        vault.write("plain-refresh-value", "refresh")
        val bytes = Files.readAllBytes(vault.fileFor("refresh"))
        assertFalse(String(bytes, Charsets.ISO_8859_1).contains("plain-refresh-value"))
        // DPAPI 덩어리 머리: dwVersion(1) + 공급자 GUID {df9d8cd0-1501-11d1-8c7a-00c04fc297eb}(리틀 엔디언 바이트).
        val provider = byteArrayOf(
            0xD0.toByte(), 0x8C.toByte(), 0x9D.toByte(), 0xDF.toByte(), 0x01, 0x15, 0xD1.toByte(), 0x11,
            0x8C.toByte(), 0x7A, 0x00, 0xC0.toByte(), 0x4F, 0xC2.toByte(), 0x97.toByte(), 0xEB.toByte(),
        )
        assertEquals(1, bytes[0].toInt())
        assertContentEquals(provider, bytes.copyOfRange(4, 20))
        assertEquals("plain-refresh-value", vault.read("refresh"))
    }

    @Test
    fun blobMovedUnderAnotherKeyIsRejectedByEntropy() {
        val vault = FileTokenVault(tmp.resolve("vault"), DpapiProtector())
        vault.write("access-value", "access")
        Files.copy(vault.fileFor("access"), vault.fileFor("refresh"))
        assertNull(vault.read("refresh"), "엔트로피가 다른데 풀렸다")
        assertEquals("access-value", vault.read("access"))
    }

    @Test
    fun valueSurvivesANewVaultInstance() {
        val dir = tmp.resolve("vault")
        FileTokenVault(dir, DpapiProtector()).write("한글·이모지🙂 refresh", "refresh")
        assertEquals("한글·이모지🙂 refresh", FileTokenVault(dir, DpapiProtector()).read("refresh"))
    }
}
