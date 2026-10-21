// 원본: Sources/CheckCore/TokenVault.swift @ a63fea2 (계약) · C§3.4 · E§5.2
// Android 금고: 앱 전용 파일(noBackupFilesDir — 백업·기기 이전에서 빠진다) + Android Keystore AES-GCM 봉투.
// security-crypto(EncryptedSharedPreferences)는 쓰지 않는다(폐기 — C§3.4, MASTG-BEST-0050).
//
// 계약(K3 TokenVault): 실패를 삼키되 **write 가 실패한 키는 read 가 null**. 낡은 refresh token 을 돌려주면 GoTrue 재사용 감지로
// 근무 중 강제 로그아웃이 된다('없다'는 재로그인, '낡았다'는 사고).
// - write 실패(키 무효화·디스크 잠금·이름 바꾸기 실패) → 그 키의 파일을 지운다. 지우지 못하면(디렉터리 쓰기 막힘 — 파일 자체는
//   쓸 수 있다) 제자리에서 0바이트로 자른다(다음 실행에도 read = null). 그것도 못 하면 이 프로세스가 그 키를 "독"으로 기억해
//   read 가 null 이다 — 이 마지막 경우만 프로세스가 죽은 뒤 낡은 파일이 다시 읽힐 수 있다(파일·디렉터리 둘 다 쓰기 불가).
// - read 실패(파일 깨짐·키 없음·인증 태그 불일치) → null.
// - AAD = 키 이름: 다른 키의 파일을 바꿔 끼워도 열리지 않는다.
package com.yehsung.aingcheck.android.vault

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** AES-GCM 봉투(IV 12바이트 + 암호문·태그). 실패는 던진다 — 삼키는 일은 금고가 한다. */
interface VaultCipher {
    fun seal(plain: ByteArray, aad: ByteArray): ByteArray
    fun open(sealed: ByteArray, aad: ByteArray): ByteArray
}

/** Android Keystore 의 AES-256 키(기기 밖으로 나가지 않는다 — 다른 기기로 옮겨진 파일은 열리지 않는다). */
class AndroidKeystoreCipher(private val alias: String = DEFAULT_ALIAS) : VaultCipher {
    private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    private fun existingKey(): SecretKey? = keyStore().getKey(alias, null) as? SecretKey

    private fun createKey(): SecretKey = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER).run {
        init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        generateKey()
    }

    override fun seal(plain: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, existingKey() ?: createKey())
        cipher.updateAAD(aad)
        val iv = cipher.iv
        require(iv.size == IV_BYTES) { "IV 길이 ${iv.size}" }
        return iv + cipher.doFinal(plain)
    }

    override fun open(sealed: ByteArray, aad: ByteArray): ByteArray {
        require(sealed.size > IV_BYTES) { "봉투가 짧다" }
        val key = existingKey() ?: throw IllegalStateException("금고 키가 없다")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, sealed, 0, IV_BYTES))
        cipher.updateAAD(aad)
        return cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES)
    }

    companion object {
        const val PROVIDER = "AndroidKeyStore"
        const val DEFAULT_ALIAS = "aingcheck.vault.v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}

class KeystoreTokenVault(private val dir: File, private val cipher: VaultCipher) : TokenVault {
    /** 실패한 write 뒤 파일을 지우지 못한 키(이 프로세스 동안 read = null). */
    private val poisoned = HashSet<String>()

    @Synchronized
    override fun read(key: String): String? {
        if (key in poisoned) return null
        val file = fileFor(key)
        return try {
            if (!file.isFile) return null
            val bytes = file.readBytes()
            if (bytes.isEmpty() || bytes[0] != FORMAT_VERSION) return null
            String(cipher.open(bytes.copyOfRange(1, bytes.size), aad(key)), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    @Synchronized
    override fun write(value: String, key: String) {
        val target = fileFor(key)
        val temp = File(dir, target.name + ".tmp")
        try {
            val sealed = byteArrayOf(FORMAT_VERSION) + cipher.seal(value.toByteArray(Charsets.UTF_8), aad(key))
            if (!dir.isDirectory && !dir.mkdirs()) throw IOException("금고 디렉터리를 못 만든다")
            FileOutputStream(temp).use { out ->
                out.write(sealed)
                out.fd.sync()
            }
            if (!temp.renameTo(target)) throw IOException("이름 바꾸기 실패")
            poisoned.remove(key)
        } catch (_: Exception) {
            temp.delete()
            forget(key, target)
        }
    }

    @Synchronized
    override fun delete(key: String) {
        forget(key, fileFor(key))
    }

    /** 파일을 지운다 → 못 지우면 제자리 0바이트로 자른다 → 그것도 안 되면 독으로 기억한다(낡은 값을 돌려주지 않는다). */
    private fun forget(key: String, target: File) {
        target.delete()
        if (target.exists()) runCatching { FileOutputStream(target).use { it.fd.sync() } }
        if (target.exists() && target.length() > 0L) poisoned += key else poisoned.remove(key)
    }

    private fun fileFor(key: String): File {
        val hex = key.toByteArray(Charsets.UTF_8).joinToString("") { "%02x".format(it) }
        return File(dir, "v$FORMAT_VERSION-$hex.bin")
    }

    private fun aad(key: String): ByteArray = "aingcheck.vault|$key".toByteArray(Charsets.UTF_8)

    private companion object {
        const val FORMAT_VERSION: Byte = 1
    }
}
