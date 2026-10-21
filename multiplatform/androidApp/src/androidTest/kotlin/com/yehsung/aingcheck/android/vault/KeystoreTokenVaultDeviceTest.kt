// W1-g 완료 기준 ①: 진짜 Android Keystore 금고가 기기(ART, 에뮬레이터 계측)에서 K2 TokenVaultContract 를 통과한다.
// 쓰기 실패를 두 가지로 심는다. 둘 다 **원래 키를 남긴다** — 그래야 "실패한 write 뒤 낡은 값" 단언이 금고의 forget 을 잰다
// (키를 바꿔 끼우면 옛 암호문이 어차피 안 열려 그 단언이 늘 초록이다 — 2차 검증 DX1).
//   ① 봉인 실패 — 진짜 Keystore 봉투를 감싼 시험 래퍼가 seal 만 실패시킨다. 낡은 파일은 같은 키로 여전히 열린다.
//   ② 디렉터리 쓰기 막힘 — 파일을 지우지 못해 제자리 자르기로 막는다.
// 키 무효화(같은 별칭이 복호 전용 키로 바뀜)는 계약 근거가 아니라 "키 상실 시 던지지 않고 null" 덧붙임으로 아래 기기 몫에 둔다.
// 금고마다 별칭·디렉터리가 따로이고, 끝나면 둘 다 지운다(운영 별칭 aingcheck.vault.v1 은 건드리지 않는다).
package com.yehsung.aingcheck.android.vault

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.testkit.vault.TokenVaultContract
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.util.UUID
import javax.crypto.KeyGenerator

private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
private val aliases = mutableListOf<String>()
private val dirs = mutableListOf<File>()

private fun freshAlias() = "aingcheck.vault.test.${UUID.randomUUID()}".also { aliases += it }
private fun freshDir() = File(context.noBackupFilesDir, "vault-test-${UUID.randomUUID()}").also { dirs += it }

private fun cleanup() {
    val ks = KeyStore.getInstance(AndroidKeystoreCipher.PROVIDER).apply { load(null) }
    aliases.forEach { runCatching { ks.deleteEntry(it) } }
    aliases.clear()
    dirs.forEach { d -> d.setWritable(true); d.deleteRecursively() }
    dirs.clear()
}

/** 같은 별칭을 복호 전용 키로 갈아 끼운다 → 다음 암호화는 InvalidKeyException(키 무효화와 같은 결과). */
private fun replaceWithDecryptOnlyKey(alias: String) {
    KeyStore.getInstance(AndroidKeystoreCipher.PROVIDER).apply { load(null) }.deleteEntry(alias)
    KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, AndroidKeystoreCipher.PROVIDER).run {
        init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        generateKey()
    }
}

/** 진짜 Keystore 봉투를 그대로 쓰되 seal 만 실패시킨다(open 은 원래 키로 그대로 연다). */
private class SealFailingCipher(private val inner: VaultCipher) : VaultCipher {
    @Volatile var failSeal = false

    override fun seal(plain: ByteArray, aad: ByteArray): ByteArray {
        if (failSeal) throw GeneralSecurityException("심은 봉인 실패(원래 키는 남아 있다)")
        return inner.seal(plain, aad)
    }

    override fun open(sealed: ByteArray, aad: ByteArray): ByteArray = inner.open(sealed, aad)
}

@RunWith(AndroidJUnit4::class)
class KeystoreSealFailureContractTest : TokenVaultContract() {
    override fun createSubject(): Subject {
        val cipher = SealFailingCipher(AndroidKeystoreCipher(freshAlias()))
        val vault = KeystoreTokenVault(freshDir(), cipher)
        return object : Subject {
            override val vault: TokenVault = vault
            override fun breakWrites() { cipher.failSeal = true }
        }
    }

    @After fun tearDown() = cleanup()
}

@RunWith(AndroidJUnit4::class)
class KeystoreReadOnlyDirectoryContractTest : TokenVaultContract() {
    override fun createSubject(): Subject {
        val dir = freshDir()
        val vault = KeystoreTokenVault(dir, AndroidKeystoreCipher(freshAlias()))
        return object : Subject {
            override val vault: TokenVault = vault
            override fun breakWrites() = check(dir.setWritable(false)) { "chmod 실패" }
        }
    }

    @After fun tearDown() = cleanup()
}

/** 기기 몫 덧붙임: 진짜 Keystore 봉투가 평문을 남기지 않고, 별칭을 잃으면(다른 기기로 옮겨진 파일) 열리지 않는다. */
@RunWith(AndroidJUnit4::class)
class KeystoreTokenVaultDeviceTest {
    @After fun tearDown() = cleanup()

    @Test
    fun ciphertextOnDiskAndLostKeyReadsNull() {
        val dir = freshDir()
        val alias = freshAlias()
        val vault = KeystoreTokenVault(dir, AndroidKeystoreCipher(alias))
        vault.write("refresh-plain-marker", "refresh")
        assertEquals("refresh-plain-marker", vault.read("refresh"))
        val files = dir.listFiles()!!.filter { it.isFile }
        assertEquals(1, files.size)
        assertTrue("평문이 파일에 있다", !String(files[0].readBytes(), Charsets.ISO_8859_1).contains("plain-marker"))
        assertTrue("금고가 백업 제외 자리 밖이다", dir.canonicalPath.startsWith(context.noBackupFilesDir.canonicalPath))
        // 키를 잃는다(새 기기 · 키 삭제) → 같은 파일을 읽으면 null(낡은 값도 깨진 값도 아니다).
        KeyStore.getInstance(AndroidKeystoreCipher.PROVIDER).apply { load(null) }.deleteEntry(alias)
        assertNull(KeystoreTokenVault(dir, AndroidKeystoreCipher(alias)).read("refresh"))
        println("AINGCHECK-VAULT keystore ciphertext-bytes=${files[0].length()} lost-key=null")
    }

    /**
     * 키 상실 시 null(계약 근거 아님): 같은 별칭이 복호 전용 키로 바뀌면 진짜 Keystore 의 암호화 init 이 던진다 — 금고는 던지지 않고
     * 그 키를 null 로 읽는다. 옛 암호문은 새 키로 어차피 안 열리므로 이 시험은 금고의 forget 을 재지 않는다(그건 위 두 계약 주체).
     */
    @Test
    fun keyInvalidatedWriteIsSwallowedAndReadsNull() {
        val dir = freshDir()
        val alias = freshAlias()
        val vault = KeystoreTokenVault(dir, AndroidKeystoreCipher(alias))
        vault.write("rotated-before", "refresh")
        assertEquals("rotated-before", vault.read("refresh"))
        replaceWithDecryptOnlyKey(alias)
        vault.write("rotated-after", "refresh") // 던지면 이 시험이 빨갛다
        assertNull(vault.read("refresh"))
    }
}
