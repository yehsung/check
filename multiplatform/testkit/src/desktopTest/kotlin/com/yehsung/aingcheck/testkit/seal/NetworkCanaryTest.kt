package com.yehsung.aingcheck.testkit.seal

import org.junit.jupiter.api.Assumptions.assumeTrue
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * 봉인이 진짜 켜졌는지 증명한다(A§4-1, K12). 게이트 스크립트가 `AINGCHECK_NETWORK_SEALED=1` 을 줄 때만 돈다.
 * 변수가 없으면 건너뛴다 — 그런 실행은 게이트가 아니다(gate-*.sh 가 이 시험이 실제로 돌았는지 결과 XML 로 센다).
 *
 * 판정(X3): 봉인 없이 변수만 주고 돌리면 **빨강**, 봉인 아래에서는 초록.
 */
class NetworkCanaryTest {
    @Test
    fun outboundConnectionsFailUnderTheSeal() {
        assumeTrue(
            System.getenv("AINGCHECK_NETWORK_SEALED") == "1",
            "게이트 밖 실행 — multiplatform/scripts/gate-fast.sh 로 돌린다(AINGCHECK_NETWORK_SEALED=1)",
        )
        val result = NetworkCanary.probe()
        println("AINGCHECK-CANARY ${result.summary()}")
        assertTrue(result.sealed, "봉인이 새고 있다 — 바깥 연결이 열렸다: ${result.summary()}")
    }
}
