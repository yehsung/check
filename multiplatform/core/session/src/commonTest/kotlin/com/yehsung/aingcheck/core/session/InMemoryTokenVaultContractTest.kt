// 원본: Sources/CheckCore/TokenVault.swift(InMemoryTokenVault · 계약) @ 1b8260d
// G §2-3 W2-a ① 의 InMemory 몫: 세션 시험이 쓰는 금고가 K2 계약(왕복 · 삭제 멱등 · write 실패 ⇒ read null)을 지킨다.
// Keystore 몫은 androidApp 계측(KeystoreSealFailureContractTest · KeystoreReadOnlyDirectoryContractTest — 에뮬레이터),
// DPAPI 몫은 desktopApp 러너 시험(DpapiVaultWindowsTest — windows-x64·windows-11-arm CI)이 같은 추상 시험을 돈다.
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import com.yehsung.aingcheck.testkit.vault.TokenVaultContract

class InMemoryTokenVaultContractTest : TokenVaultContract() {
    override fun createSubject(): Subject {
        val vault = InMemoryTokenVault()
        return object : Subject {
            override val vault: TokenVault = vault
            override fun breakWrites() {
                vault.failsWrites = true
            }
        }
    }
}

/** 세션 시험의 세는 금고([CountingVault])도 같은 계약을 지킨다 — 시험 도우미가 계약을 흐리면 세션 시험의 '낡은 토큰 없음' 단언이 공허해진다. */
class CountingVaultContractTest : TokenVaultContract() {
    override fun createSubject(): Subject {
        val vault = CountingVault()
        return object : Subject {
            override val vault: TokenVault = vault
            override fun breakWrites() {
                vault.failsWrites = true
            }
        }
    }
}
