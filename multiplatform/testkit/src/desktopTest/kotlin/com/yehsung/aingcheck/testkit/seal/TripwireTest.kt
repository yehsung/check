package com.yehsung.aingcheck.testkit.seal

import com.yehsung.aingcheck.testkit.tripwire.NetworkTripwire
import java.net.InetAddress
import java.net.UnknownHostException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * ②층 트립와이어가 Gradle 시험 작업자에서 실제로 로드되는지(A-X4), localhost 는 사는지.
 * 봉인 여부와 무관하게 늘 돈다 — 트립와이어는 봉인 밖 개발 실행에서도 켜져 있다.
 */
class TripwireTest {
    @Test
    fun outsideNameLookupIsBlockedByOurResolverAndRecorded() {
        val recorded = NetworkTripwire.expectBlocked {
            val error = assertFailsWith<UnknownHostException> { InetAddress.getByName("example.com") }
            assertTrue(
                error.message.orEmpty().startsWith("aingcheck tripwire: blocked name lookup "),
                "우리 제공자가 아닌 곳에서 실패했다(로드 안 됨?): ${error.message}",
            )
        }
        assertTrue(NetworkTripwire.isInstalled(), "InetAddressResolverProvider 가 로드되지 않았다")
        assertEquals(listOf("lookup example.com"), recorded)
    }

    @Test
    fun localhostStillResolves() {
        val recorded = NetworkTripwire.expectBlocked {
            val addresses = InetAddress.getAllByName("localhost")
            assertTrue(addresses.all { it.isLoopbackAddress }, "localhost 가 루프백이 아니다: ${addresses.toList()}")
        }
        assertEquals(emptyList<String>(), recorded)
    }

    @Test
    fun reverseLookupOfOutsideAddressIsBlocked() {
        val recorded = NetworkTripwire.expectBlocked {
            // getCanonicalHostName 은 실패를 삼키고 숫자 주소를 돌려준다 — 기록이 남는지로 판정한다.
            InetAddress.getByAddress(byteArrayOf(93, 184.toByte(), 215.toByte(), 14)).canonicalHostName
        }
        assertEquals(listOf("reverse 93.184.215.14"), recorded)
    }

    @Test
    fun nothingLeakedOutsideExpectedScopesSoFar() {
        assertEquals(emptyList<String>(), NetworkTripwire.blockedSoFar())
    }
}
