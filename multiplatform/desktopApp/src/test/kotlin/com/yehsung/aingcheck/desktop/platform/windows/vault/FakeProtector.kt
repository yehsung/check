package com.yehsung.aingcheck.desktop.platform.windows.vault

import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * 맥 JVM 시험용 보호기. DPAPI 의 성질 중 금고 규약이 기대는 둘만 흉내 낸다:
 * ① 봉인된 바이트는 원문과 다르다 ② **다른 엔트로피·손상된 바이트는 풀리지 않는다**(예외). 암호학적 강도는 목표가 아니다.
 * [failProtect] 를 켜면 봉인이 실패한다(CryptProtectData 실패 주입).
 */
class FakeProtector(private val secret: ByteArray = "aingcheck-test-protector".toByteArray()) : DataProtector {
    @Volatile var failProtect = false

    override fun protect(plain: ByteArray, entropy: ByteArray): ByteArray {
        if (failProtect) throw IllegalStateException("주입된 봉인 실패")
        val body = xor(plain, entropy)
        return tag(entropy, plain) + body
    }

    override fun unprotect(sealed: ByteArray, entropy: ByteArray): ByteArray {
        require(sealed.size >= 32) { "짧다" }
        val plain = xor(sealed.copyOfRange(32, sealed.size), entropy)
        require(MessageDigest.isEqual(sealed.copyOfRange(0, 32), tag(entropy, plain))) { "The data is invalid" }
        return plain
    }

    private fun tag(entropy: ByteArray, plain: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        mac.update(entropy.size.toString().toByteArray())
        mac.update(entropy)
        mac.update(plain)
        return mac.doFinal()
    }

    private fun xor(data: ByteArray, entropy: ByteArray): ByteArray {
        val stream = MessageDigest.getInstance("SHA-256").digest(secret + entropy)
        return ByteArray(data.size) { i -> (data[i].toInt() xor stream[i % stream.size].toInt()).toByte() }
    }
}
