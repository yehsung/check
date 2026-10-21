package com.yehsung.aingcheck.desktop.platform.windows.vault

import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.testkit.vault.TokenVaultContract
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.condition.DisabledOnOs
import org.junit.jupiter.api.condition.OS
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 금고 계약(testkit TokenVaultContract)을 파일 금고에 건다 — 맥 JVM 몫. 진짜 DPAPI 는 Windows 러너 시험(runner/DpapiVaultWindowsTest)이 같은 계약을 돈다.
 * 쓰기 실패 주입 ①: 봉인(암호화) 단계 실패 — 이전 파일은 그대로 남아 있으므로 금고가 지우지 않으면 낡은 값이 돌아온다.
 */
class FileTokenVaultProtectorFailureContractTest : TokenVaultContract() {
    @field:TempDir
    lateinit var tmp: Path

    override fun createSubject(): Subject {
        val protector = FakeProtector()
        val vault = FileTokenVault(tmp.resolve("vault-${System.nanoTime()}"), protector)
        return object : Subject {
            override val vault: TokenVault = vault
            override fun breakWrites() {
                protector.failProtect = true
            }
        }
    }
}

/**
 * 쓰기 실패 주입 ②(POSIX): 금고 폴더를 r-x 로 — 새 파일도 못 만들고 **지우지도 못한다**. 금고는 대상 파일을 0바이트로 잘라
 * 낡은 값이 다음 실행에서도 돌아오지 않게 하고, 이 실행 동안은 독(poison)으로 null 을 지킨다. Windows 는 POSIX 권한이 없어
 * 같은 주입을 ACL 거부로 한다(runner 몫).
 */
@DisabledOnOs(OS.WINDOWS)
class FileTokenVaultReadOnlyDirectoryContractTest : TokenVaultContract() {
    @field:TempDir
    lateinit var tmp: Path
    private val locked = mutableListOf<Path>()

    override fun createSubject(): Subject {
        val dir = tmp.resolve("vault-${System.nanoTime()}")
        val vault = FileTokenVault(dir, FakeProtector())
        return object : Subject {
            override val vault: TokenVault = vault
            override fun breakWrites() {
                Files.createDirectories(dir)
                Files.setPosixFilePermissions(dir, PosixFilePermissions.fromString("r-xr-xr-x"))
                locked.add(dir)
            }
        }
    }

    @AfterEach
    fun unlock() {
        locked.forEach { runCatching { Files.setPosixFilePermissions(it, PosixFilePermissions.fromString("rwx------")) } }
    }
}

/** 계약 밖의 파일 규약(D§7): 파일 이름·손상·엔트로피·재시작. */
class FileTokenVaultFileRulesTest {
    @field:TempDir
    lateinit var tmp: Path

    @Test
    fun fileNameIsSha256OfKeyAndNeverTheKeyItself() {
        val dir = tmp.resolve("vault")
        val vault = FileTokenVault(dir, FakeProtector())
        vault.write("v", "supabase.refresh_token")
        val names = Files.list(dir).use { s -> s.map { it.fileName.toString() }.toList() }
        // 기대값은 다른 구현(Python hashlib.sha256)으로 쟀다.
        assertEquals(listOf("489fcb554684102112fea05661f16b2b5943d88e37490a73fb00d8dd92422656.bin"), names)
        assertFalse(names.any { it.contains("refresh") })
        assertEquals("8be568b99cf0b2a059d4637d39d189ccf8d394e3c5ba75ddea88e666d357b5e9", FileTokenVault.sha256Hex("한글 키"))
    }

    @Test
    fun ciphertextOnDiskDiffersFromPlaintext() {
        val dir = tmp.resolve("vault")
        val vault = FileTokenVault(dir, FakeProtector())
        vault.write("plain-refresh-value", "refresh")
        val bytes = Files.readAllBytes(vault.fileFor("refresh"))
        assertFalse(String(bytes, Charsets.ISO_8859_1).contains("plain-refresh-value"))
    }

    @Test
    fun corruptedFileReadsNullAndIsRemoved() {
        val dir = tmp.resolve("vault")
        val vault = FileTokenVault(dir, FakeProtector())
        vault.write("value", "k")
        val f = vault.fileFor("k")
        Files.write(f, Files.readAllBytes(f).also { it[it.size - 1] = (it[it.size - 1].toInt() xor 1).toByte() })
        assertNull(vault.read("k"))
        assertFalse(Files.exists(f), "손상 파일을 지우지 않았다")
    }

    @Test
    fun fileMovedUnderAnotherKeyDoesNotDecrypt() {
        // 엔트로피 = "aing-check.v1|" + 키 — 다른 키 자리로 옮긴 봉인은 풀리지 않는다(DPAPI 엔트로피 짝, W0-e 실측과 같은 성질).
        val dir = tmp.resolve("vault")
        val vault = FileTokenVault(dir, FakeProtector())
        vault.write("access-value", "access")
        Files.copy(vault.fileFor("access"), vault.fileFor("refresh"))
        assertNull(vault.read("refresh"))
        assertEquals("access-value", vault.read("access"))
    }

    @Test
    fun poisonIsLiftedByTheNextSuccessfulWrite() {
        val protector = FakeProtector()
        val vault = FileTokenVault(tmp.resolve("vault"), protector)
        vault.write("r1", "refresh")
        protector.failProtect = true
        vault.write("r2", "refresh")
        assertNull(vault.read("refresh"))
        protector.failProtect = false
        vault.write("r3", "refresh")
        assertEquals("r3", vault.read("refresh"))
    }

    @Test
    fun noTemporaryFilesAreLeftBehind() {
        val protector = FakeProtector()
        val dir = tmp.resolve("vault")
        val vault = FileTokenVault(dir, protector)
        repeat(5) { vault.write("v$it", "k$it") }
        protector.failProtect = true
        vault.write("x", "k0")
        val leftovers = Files.list(dir).use { s -> s.filter { it.fileName.toString().endsWith(".tmp") }.count() }
        assertEquals(0L, leftovers)
    }

    @DisabledOnOs(OS.WINDOWS)
    @Test
    fun staleValueDoesNotComeBackAfterRestartWhenDirectoryIsReadOnly() {
        val dir = tmp.resolve("vault")
        val vault = FileTokenVault(dir, FakeProtector())
        vault.write("rotated-before", "refresh")
        Files.setPosixFilePermissions(dir, PosixFilePermissions.fromString("r-xr-xr-x"))
        try {
            vault.write("rotated-after", "refresh")
            assertNull(vault.read("refresh"), "같은 실행")
            // 새 실행(새 인스턴스, 독 없음): 지울 수 없던 파일은 0바이트로 잘려 풀리지 않아야 한다.
            assertNull(FileTokenVault(dir, FakeProtector()).read("refresh"), "다시 켜니 낡은 토큰이 돌아왔다")
            assertTrue(Files.size(vault.fileFor("refresh")) == 0L)
        } finally {
            Files.setPosixFilePermissions(dir, PosixFilePermissions.fromString("rwx------"))
        }
    }
}
