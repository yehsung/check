package com.yehsung.aingcheck.testkit.seal

import org.junit.jupiter.api.Assumptions.assumeTrue
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * A-X3: 시험 작업자(와 그 부모인 일회용 Gradle 데몬)가 **봉인을 건 프로세스의 자손**인가.
 * gate-*.sh 의 안쪽 단계가 자기 PID 를 AINGCHECK_GATE_PID 로 준다(맥 sandbox-exec·Linux unshare 는 exec 로 이어진다).
 * 봉인 밖에서 떠 있던 데몬을 재사용하면 이 사슬이 끊긴다 → 빨강.
 */
class SealAncestryTest {
    @Test
    fun testWorkerDescendsFromTheSealedGateProcess() {
        val gatePid = System.getenv("AINGCHECK_GATE_PID")?.toLongOrNull()
        assumeTrue(gatePid != null, "게이트 밖 실행(또는 Windows) — 부모 사슬 판정 없음")
        val chain = generateSequence(ProcessHandle.current()) { it.parent().orElse(null) }
            .take(32)
            .map { handle -> handle.pid() to handle.info().command().orElse("?") }
            .toList()
        println("AINGCHECK-ANCESTRY " + chain.joinToString(" <- ") { "${it.first}:${it.second.substringAfterLast('/')}" })
        assertTrue(chain.any { it.first == gatePid }, "시험 JVM 이 봉인 프로세스($gatePid)의 자손이 아니다: $chain")
    }
}
