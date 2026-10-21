// K2 TokenVaultContract 를 Android 금고의 파일 층에 돌린다(JVM). 쓰기 실패를 두 가지로 심는다:
//   ① 봉투 실패(키 무효화) — 파일을 지울 수 있다 ② 디렉터리 쓰기 막힘 — 지우지 못해 제자리 자르기·독 기억으로 막는다.
package com.yehsung.aingcheck.android.vault

import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.testkit.vault.TokenVaultContract
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

private val made = mutableListOf<File>()

private fun freshDir(): File = Files.createTempDirectory(File(System.getProperty("java.io.tmpdir")).toPath(), "vault").toFile().also { made += it }

private fun cleanup() {
    made.forEach { d -> d.walkBottomUp().forEach { it.setWritable(true); it.delete() } }
    made.clear()
}

class CipherFailureVaultContractTest : TokenVaultContract() {
    override fun createSubject(): Subject {
        val cipher = SoftwareVaultCipher(seed = 1)
        val vault = KeystoreTokenVault(freshDir(), cipher)
        return object : Subject {
            override val vault: TokenVault = vault
            override fun breakWrites() { cipher.failSeal = true }
        }
    }

    @After fun tearDown() = cleanup()
}

class ReadOnlyDirectoryVaultContractTest : TokenVaultContract() {
    override fun createSubject(): Subject {
        val dir = freshDir()
        val vault = KeystoreTokenVault(dir, SoftwareVaultCipher(seed = 2))
        return object : Subject {
            override val vault: TokenVault = vault
            override fun breakWrites() { check(dir.setWritable(false)) { "chmod 실패" } }
        }
    }

    @After fun tearDown() = cleanup()
}

/** 계약 밖의 Android 몫: 다음 실행(새 금고 객체)에서도 낡은 값이 살아나지 않는다 · 파일이 바뀌면 열리지 않는다. */
class KeystoreTokenVaultFileTest {
    @After fun tearDown() = cleanup()

    @Test
    fun failedWriteStaysNullAcrossRestartWhenDirectoryIsReadOnly() {
        val dir = freshDir()
        KeystoreTokenVault(dir, SoftwareVaultCipher(3)).write("rotated-before", "refresh")
        check(dir.setWritable(false))
        KeystoreTokenVault(dir, SoftwareVaultCipher(3)).write("rotated-after", "refresh")
        // 새 프로세스 흉내: 독 기억이 없는 새 객체로 읽는다. 파일은 제자리에서 0바이트로 잘려 있어야 한다.
        assertNull("다음 실행에 낡은 refresh 가 살아났다", KeystoreTokenVault(dir, SoftwareVaultCipher(3)).read("refresh"))
        // 기준선: 막히기 전에 쓴 다른 키는 그대로 읽힌다.
        dir.setWritable(true)
        val v = KeystoreTokenVault(dir, SoftwareVaultCipher(3))
        v.write("a", "access")
        assertEquals("a", KeystoreTokenVault(dir, SoftwareVaultCipher(3)).read("access"))
    }

    /** 파일도 디렉터리도 쓸 수 없으면(지우기·자르기 둘 다 실패) 이 프로세스는 독 기억으로 null 을 낸다. */
    @Test
    fun unwritableFileAndDirectoryFallBackToPoison() {
        val dir = freshDir()
        val v = KeystoreTokenVault(dir, SoftwareVaultCipher(6))
        v.write("rotated-before", "refresh")
        val file = dir.listFiles()!!.single { it.name.endsWith(".bin") }
        check(file.setWritable(false) && dir.setWritable(false))
        v.write("rotated-after", "refresh")
        assertTrue("기준선: 파일이 그대로 남아 있어야 이 경로를 잰다", file.length() > 0)
        assertNull("같은 프로세스가 낡은 refresh 를 돌려줬다", v.read("refresh"))
        file.setWritable(true)
    }

    @Test
    fun otherKeyOrTamperedFileDoesNotOpen() {
        val dir = freshDir()
        val v = KeystoreTokenVault(dir, SoftwareVaultCipher(4))
        v.write("secret-a", "a")
        v.write("secret-b", "b")
        val files = dir.listFiles()!!.filter { it.name.endsWith(".bin") }.sortedBy { it.name }
        assertEquals(2, files.size)
        // a 의 파일을 b 자리에 덮는다(AAD = 키 이름이라 열리지 않아야 한다).
        files[0].copyTo(files[1], overwrite = true)
        assertNull(v.read("b"))
        assertEquals("secret-a", v.read("a"))
        // 다른 키(다른 기기의 Keystore)로는 열리지 않는다.
        assertNull(KeystoreTokenVault(dir, SoftwareVaultCipher(5)).read("a"))
        // 평문이 파일에 없다.
        assertTrue(files.none { String(it.readBytes(), Charsets.ISO_8859_1).contains("secret-") })
    }
}
