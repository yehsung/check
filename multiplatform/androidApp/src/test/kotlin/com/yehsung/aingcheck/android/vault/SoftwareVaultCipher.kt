// 시험용 봉투: JDK AES-GCM(소프트웨어 키). Robolectric·JVM 에는 AndroidKeyStore 가 없어 파일 층(KeystoreTokenVault)만 여기서 잰다.
// 진짜 Keystore 는 기기 계측(androidTest …/vault/KeystoreTokenVaultDeviceTest)이 잰다.
package com.yehsung.aingcheck.android.vault

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class SoftwareVaultCipher(seed: Int) : VaultCipher {
    private val key = SecretKeySpec(ByteArray(32) { (it * 7 + seed).toByte() }, "AES")
    private val random = SecureRandom()
    var failSeal = false

    override fun seal(plain: ByteArray, aad: ByteArray): ByteArray {
        check(!failSeal) { "키 무효화 흉내" }
        val iv = ByteArray(12).also(random::nextBytes)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
        c.updateAAD(aad)
        return iv + c.doFinal(plain)
    }

    override fun open(sealed: ByteArray, aad: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed, 0, 12))
        c.updateAAD(aad)
        return c.doFinal(sealed, 12, sealed.size - 12)
    }
}
