// 원본: Sources/CheckCore/TokenVault.swift @ a63fea2 (계약: 왕복 · 삭제 멱등 · write 실패 ⇒ read nil)
// K2 TokenVaultContract — 플랫폼 금고마다 이 추상 시험을 상속해 돌린다:
//   InMemory(여기) · Android Keystore(에뮬레이터 계측, W1-g) · Windows DPAPI(러너·VM, W1-f).
package com.yehsung.aingcheck.testkit.vault

import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

abstract class TokenVaultContract {
    /** 시험 하나마다 새 금고. [Subject.breakWrites] 뒤의 write 는 실패해야 한다(디스크 잠금·키 무효화 등 구현이 고른다). */
    interface Subject {
        val vault: TokenVault
        fun breakWrites()
    }

    protected abstract fun createSubject(): Subject

    @Test
    fun roundTripsValues() {
        val s = createSubject()
        s.vault.write("access-1", "access")
        s.vault.write(LONG_REFRESH, "refresh")
        assertEquals("access-1", s.vault.read("access"))
        assertEquals(LONG_REFRESH, s.vault.read("refresh"))
    }

    @Test
    fun overwriteReturnsLatestValue() {
        val s = createSubject()
        s.vault.write("r1", "refresh")
        s.vault.write("r2", "refresh")
        assertEquals("r2", s.vault.read("refresh"))
    }

    @Test
    fun missingKeyReadsNullAndDeleteIsIdempotent() {
        val s = createSubject()
        assertNull(s.vault.read("never"))
        s.vault.delete("never")
        s.vault.write("v", "k")
        s.vault.delete("k")
        s.vault.delete("k")
        assertNull(s.vault.read("k"))
    }

    /** 계약의 핵심: 실패를 삼키되 **낡은 값을 돌려주지 않는다**(낡은 refresh 로 grant → 재사용 감지 강제 로그아웃). */
    @Test
    fun failedWriteMakesReadNullInsteadOfStale() {
        val s = createSubject()
        s.vault.write("rotated-before", "refresh")
        s.breakWrites()
        s.vault.write("rotated-after", "refresh")
        assertNull(s.vault.read("refresh"), "write 가 실패했는데 낡은 토큰이 남았다")
    }

    @Test
    fun unicodeAndKeysAreIndependent() {
        val s = createSubject()
        s.vault.write("한글·이모지🙂", "a")
        s.vault.write("b-value", "b")
        assertEquals("한글·이모지🙂", s.vault.read("a"))
        assertEquals("b-value", s.vault.read("b"))
    }

    private companion object {
        /** JWT 크기(1KB 남짓)의 값. 진짜 JWT 모양(eyJ…)은 쓰지 않는다 — 비밀 검사 문형과 겹친다. */
        val LONG_REFRESH: String = buildString { repeat(64) { append("refresh.segment-") } }
    }
}

/** 시험용 금고(Swift InMemoryTokenVault 그대로): failsWrites 면 값이 저장되지 않고 그 키의 기존 값도 지워진다. */
class InMemoryTokenVault : TokenVault {
    private val storage = HashMap<String, String>()
    var failsWrites: Boolean = false

    override fun read(key: String): String? = storage[key]

    override fun write(value: String, key: String) {
        if (failsWrites) {
            storage.remove(key)
            return
        }
        storage[key] = value
    }

    override fun delete(key: String) {
        storage.remove(key)
    }
}
