package com.yehsung.aingcheck.desktop.platform.windows.runner

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * 자식 JVM 띄우기 자체를 모든 OS 에서 잰다 — Windows 러너의 프로세스 사이 시험(뮤텍스·활성화 신호·JNA 풀기)이
 * '자식이 안 떴다'로 빨개지는지 '판정이 틀렸다'로 빨개지는지 가르려면 이 길이 먼저 초록이어야 한다.
 */
class ChildJvmTest {
    @Test
    fun childSeesTheTestClasspathAndReturnsItsOutput() {
        // 인자는 ASCII 만: Windows 의 java 런처는 명령줄을 ANSI 코드 페이지로 읽어 한글 인자가 깨진다(시험 대상이 아니다).
        val r = RunnerSupport.runChild(listOf("echo", "aing", "check"))
        assertEquals(0, r.exitCode, r.stderr)
        assertEquals("aing check", r.stdout)
    }

    @Test
    fun childComputesTheSameUuid5AsThisProcess() {
        // 자식은 이 프로세스와 다른 JVM 이다 — 같은 입력에서 같은 신원이 나와야 "두 번 계산해도 같은 값" 이 프로세스 경계를 넘는다.
        val r = RunnerSupport.runChild(listOf("uuid5", "python.org"))
        assertEquals("886313e1-3b8a-5372-9b90-0c9aee199e5d", r.stdout)
    }

    @Test
    fun unknownCommandFailsLoudly() {
        assertEquals(64, RunnerSupport.runChild(listOf("nope")).exitCode)
    }
}
