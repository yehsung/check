package com.yehsung.aingcheck.spike.windows

import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.fail

/**
 * 망 봉인 카나리아(K12). 봉인 없이 돌리면 빨갛다 — 그것이 정상이다.
 * 맥: sandbox-exec 네트워크 거부, Windows: 시험 전용 JDK 의 java.exe 아웃바운드 차단 규칙(winseal.ps1).
 * 이름 풀이를 거치지 않게 IP 로 연결한다(DNS 는 OS 서비스가 대신 하므로 봉인 판정을 흐린다).
 */
class NetworkCanaryTest {
    @Test
    fun outboundConnectionIsBlocked() {
        assertEquals("1", System.getenv("AINGCHECK_NETWORK_SEALED"), "AINGCHECK_NETWORK_SEALED=1 없이 돈 실행은 게이트가 아니다")
        val started = System.nanoTime()
        try {
            Socket().use { it.connect(InetSocketAddress("1.1.1.1", 443), 3_000) }
        } catch (e: IOException) {
            println("canary: blocked after ${(System.nanoTime() - started) / 1_000_000}ms — $e")
            return
        }
        fail("봉인이 새었다: 1.1.1.1:443 에 연결됐다")
    }
}
