package com.yehsung.aingcheck.testkit.seal

import com.yehsung.aingcheck.testkit.tripwire.NetworkTripwire
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

/**
 * 봉인 카나리아(A§4-1, K12). OS 봉인(③층)이 실제로 켜졌는지를 **바깥 연결 시도**로 잰다.
 *
 * - `ip`: 1.1.1.1:443 소켓 연결(이름 풀이 없음 — 트립와이어가 관여하지 못한다)
 * - `host`: example.com 을 JDK 기본 풀이로 찾은 뒤 :443 연결(트립와이어 통로 [NetworkTripwire.canaryBypass])
 *
 * 둘 다 실패해야 봉인이다. 이름 풀이 자체의 성패(`dnsResolved`)는 기록만 한다:
 * 맥 sandbox-exec 는 mDNSResponder(유닉스 소켓) 경유 풀이를 막지 않을 수 있고, Windows 방화벽은 java.exe 만 막아
 * DNS 클라이언트 서비스의 풀이는 산다. 데이터가 나가는 것은 연결이므로 판정은 연결로 한다.
 */
object NetworkCanary {
    data class Probe(val name: String, val blocked: Boolean, val detail: String)
    data class Result(val probes: List<Probe>, val dnsResolved: Boolean) {
        val sealed: Boolean get() = probes.all { it.blocked }
        fun summary(): String =
            probes.joinToString(" ") { "${it.name}=${if (it.blocked) "blocked" else "OPEN"}(${it.detail})" } +
                " dns=${if (dnsResolved) "resolved" else "failed"}"
    }

    private const val TIMEOUT_MS = 3_000

    fun probe(): Result {
        val ip = connect("ip", InetSocketAddress(InetAddress.getByAddress(byteArrayOf(1, 1, 1, 1)), 443))
        var dnsResolved = false
        val host = try {
            val addresses = NetworkTripwire.canaryBypass { InetAddress.getAllByName("example.com") }
            dnsResolved = addresses.isNotEmpty()
            connect("host", InetSocketAddress(addresses.first(), 443))
        } catch (e: Exception) {
            Probe("host", blocked = true, detail = "${e.javaClass.simpleName}: ${e.message}")
        }
        return Result(listOf(ip, host), dnsResolved)
    }

    private fun connect(name: String, address: InetSocketAddress): Probe = try {
        Socket().use { it.connect(address, TIMEOUT_MS) }
        Probe(name, blocked = false, detail = "connected ${address.address.hostAddress}:${address.port}")
    } catch (e: Exception) {
        Probe(name, blocked = true, detail = "${e.javaClass.simpleName}: ${e.message}")
    }
}
