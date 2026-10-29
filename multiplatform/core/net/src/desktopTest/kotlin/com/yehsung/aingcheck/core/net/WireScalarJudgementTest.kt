// 원본: 없음(W1-d 글자 판정이 번들 표를 따르는지 — 8차 fold, G §8-20 #3 · §8-16 ②)
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.net.realtime.RealtimeFeature
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** JDK `Character` 와 Swift 가 갈리는 글자로 잰다 — U+0085(NEL): Swift 공백 · JDK 아님. U+001C(FS): Swift 아님 · JDK 공백. U+00A0: Swift 공백 · JDK isWhitespace 아님. */
class WireScalarJudgementTest {
    @Test
    fun inviteCodeDropsSwiftWhitespaceOnly() {
        // Swift `code.uppercased().filter { !$0.isWhitespace && $0 != "-" }`.
        assertEquals("AB\u001CCD", normalizeInviteCode("ab\u0085 -\u001Ccd"))
        assertEquals("AB12", normalizeInviteCode(" ab-1\t2 "))
    }

    @Test
    fun realtimeEnvironmentTrimsSwiftWhitespacesOnly() {
        // Swift `trimmingCharacters(in: .whitespaces)` — 줄바꿈은 남는다(그래서 "1\n" 은 켬이 아니다).
        assertTrue(RealtimeFeature.isEnabled(false, mapOf(RealtimeFeature.environmentName to " \t1 ")))
        assertFalse(RealtimeFeature.isEnabled(true, mapOf(RealtimeFeature.environmentName to "1\n")))
        assertTrue(RealtimeFeature.isEnabled(true, mapOf(RealtimeFeature.environmentName to " \t ")), "공백뿐이면 저장 값")
    }
}
