// 원본: Sources/CheckCore/TokenVault.swift @ a63fea2 (계약: write 가 실패한 키는 read 가 반드시 nil)
//       · 시험은 새 코드: 설계 D§7(DPAPI 파일 금고) · D-E10(읽기 전용 폴더 주입) · W0-e 실측(엔트로피 거부)
//       · R2 검증 지적(V2: 사다리 ③ 독을 Windows 에서도 같은 짝으로 — ACL 거부 + 공유 READ 핸들, 아래 시험 주석)
package com.yehsung.aingcheck.desktop.platform.windows.runner

import com.sun.jna.platform.win32.Kernel32
import com.sun.jna.platform.win32.WinBase
import com.sun.jna.platform.win32.WinNT
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
import java.nio.file.StandardOpenOption
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

    /**
     * 사다리 ③(독)의 Windows 짝(맥·Linux 는 FileTokenVaultFileRulesTest 의 0444/0555). 현재 사용자에게 세 겹으로 막는다:
     *  - 금고 폴더 ACL: WRITE_DATA(파일 추가)·APPEND_DATA(하위 폴더 추가)·DELETE_CHILD 거부 → 새 임시 파일 실패(쓰기 실패)
     *  - 대상 파일 ACL: WRITE_DATA·APPEND_DATA·DELETE 거부 → 0바이트 자르기 실패(②)
     *  - 대상 파일을 공유 READ 만 허락하는 핸들로 쥐고 있는다(백신·백업·색인기가 쥔 꼴 — 금고 머리의 '잠금') → 지우기 실패(①)
     * 핸들이 필요한 까닭(실측, run 39638126754·39639966589): windows-latest 러너의 토큰은 SeBackupPrivilege·SeRestorePrivilege 가
     * **켜져(Enabled)** 있어, 파일 DELETE·폴더 DELETE_CHILD 를 거부(icacls 로 (DENY)(DE,WD,AD) 확인)해도 DeleteFileW 가 성공했다 —
     * ACL 만으로는 ③ 까지 가지 못했다(NoSuchFileException). 공유 위반은 특권과 무관하다. 같은 ACL 만 단 쌍둥이 파일의 지우기
     * 결과·특권 상태를 AINGCHECK-ACL 줄로 남긴다(러너 환경의 사실이라 단언하지 않는다 — 보통 사용자 토큰에는 두 특권이 꺼져 있다).
     */
    @Test
    fun poisonKeepsTheSameRunNullWhenTheFileCanBeNeitherDeletedNorTruncated() {
        val dir = tmp.resolve("vault")
        val vault = FileTokenVault(dir, DpapiProtector())
        vault.write("rotated-before", "refresh")
        val file = vault.fileFor("refresh")
        val before = Files.readAllBytes(file)
        val twin = dir.resolve("acl-twin.bin")
        Files.write(twin, byteArrayOf(1, 2, 3))
        val me = dir.fileSystem.userPrincipalLookupService.lookupPrincipalByName(System.getProperty("user.name"))
        fun deny(vararg perms: AclEntryPermission) =
            AclEntry.newBuilder().setType(AclEntryType.DENY).setPrincipal(me).setPermissions(*perms).build()
        val views = listOf(dir, file, twin).associateWith { Files.getFileAttributeView(it, AclFileAttributeView::class.java) }
        val saved = views.mapValues { (_, v) -> v.acl }
        var lock: WinNT.HANDLE? = null
        try {
            for (f in listOf(file, twin)) {
                views.getValue(f).acl = listOf(deny(AclEntryPermission.WRITE_DATA, AclEntryPermission.APPEND_DATA, AclEntryPermission.DELETE)) + saved.getValue(f)
            }
            views.getValue(dir).acl =
                listOf(deny(AclEntryPermission.WRITE_DATA, AclEntryPermission.APPEND_DATA, AclEntryPermission.DELETE_CHILD)) + saved.getValue(dir)
            // 관측(단언 아님): ACL 만으로 지우기가 막히는가 — 쌍둥이 파일로 잰다.
            val twinAcl = runCatching { RunnerSupport.runTool("icacls.exe", twin.toString()) }.getOrElse { "icacls 실패: $it" }
            val twinDelete = runCatching { Files.delete(twin) }
            val priv = runCatching { RunnerSupport.runTool("whoami.exe", "/priv", "/fo", "csv", "/nh") }.getOrElse { "" }
                .lines().filter { l -> listOf("SeBackup", "SeRestore", "SeTakeOwnership").any { it in l } }.joinToString(" ")
            println(
                "AINGCHECK-ACL acl-only-delete=" +
                    (if (twinDelete.isSuccess) "succeeded" else "denied(${twinDelete.exceptionOrNull()?.javaClass?.simpleName})") +
                    " owner=${Files.getOwner(dir)} user=$me priv=[$priv] twin-acl=[${twinAcl.trim().lines().joinToString(" | ")}]",
            )
            lock = Kernel32.INSTANCE.CreateFile(
                file.toString(), WinNT.GENERIC_READ, WinNT.FILE_SHARE_READ, null, WinNT.OPEN_EXISTING, WinNT.FILE_ATTRIBUTE_NORMAL, null,
            )
            check(lock != null && lock != WinBase.INVALID_HANDLE_VALUE) { "잠금 핸들을 못 열었다(err ${Kernel32.INSTANCE.GetLastError()})" }
            // 주입이 실제로 걸렸는지 먼저 잰다(안 걸렸으면 이 시험은 ③ 을 재지 못한다). 쓰기로 열기는 자르지 않는다.
            check(runCatching { Files.createTempFile(dir, "probe", ".tmp") }.isFailure) { "폴더에 새 파일을 만들 수 있다" }
            check(runCatching { Files.newOutputStream(file, StandardOpenOption.WRITE).close() }.isFailure) { "파일을 쓰기로 열 수 있다" }
            check(runCatching { Files.delete(file) }.isFailure) { "대상 파일을 지울 수 있다" }
            vault.write("rotated-after", "refresh")
            assertContentEquals(before, Files.readAllBytes(file), "주입이 새었다 — 지우기나 자르기가 됐다(③ 까지 가지 않았다)")
            assertNull(vault.read("refresh"), "같은 실행에서 낡은 토큰이 돌아왔다(독이 없다)")
        } finally {
            lock?.let { if (it != WinBase.INVALID_HANDLE_VALUE) Kernel32.INSTANCE.CloseHandle(it) }
            for ((path, acl) in saved) runCatching { views.getValue(path).acl = acl }
        }
    }

    @Test
    fun valueSurvivesANewVaultInstance() {
        val dir = tmp.resolve("vault")
        FileTokenVault(dir, DpapiProtector()).write("한글·이모지🙂 refresh", "refresh")
        assertEquals("한글·이모지🙂 refresh", FileTokenVault(dir, DpapiProtector()).read("refresh"))
    }
}
