// 원본: Tests/CheckMobileKitTests/V0347AILimitClearedRowTests.swift(옛 문구 회귀 금지 몫) — 공용 패치 21 의 맥·PC 문구 세 줄
package com.yehsung.aingcheck.core.stores.me

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * 폰(Android)·PC 판이 생겼으니 "맥 앱에서"·"고른 맥" 만으로는 틀린 말이 된다. 사용자가 고른 글자 그대로인지,
 * 옛 맥 전용 문구로 되돌아가지 않았는지를 잰다. 가운뎃점은 U+00B7(·) 하나뿐이다(닮은 글자 U+30FB·U+2022 가 아니다).
 */
class MacPcWordingTest {
    private val inviteSecondLine = MeText.inviteShareMessage("아잉팀", "ABC123").lines()[1]

    private val all get() = listOf(
        AILimitSurfaceText.noVisibleProviders,
        AILimitSurfaceText.substitutedMainDevice,
        inviteSecondLine,
    )

    @Test
    fun threeLinesAreExactlyTheChosenWording() {
        assertEquals("맥·PC 앱에서 AI 도구에 로그인하고 리밋 보기를 켜면 보여요", AILimitSurfaceText.noVisibleProviders)
        assertEquals("고른 기기는 지금 보여 줄 숫자가 없어서 다른 기기를 보여 주고 있어요", AILimitSurfaceText.substitutedMainDevice)
        assertEquals("맥·PC 앱에서 가입할 때 이 코드를 입력하면 같은 팀이 돼요.", inviteSecondLine)
        assertEquals(
            "맥·PC 앱에서 가입할 때 이 코드를 입력하면 같은 팀이 돼요.",
            MeText.inviteShareMessage(null, "ABC123").lines()[1],
            "팀 이름이 없어도 둘째 줄은 같다",
        )
        // 폰 카드가 보는 별칭도 같은 상수다(한쪽만 고쳐지는 날을 막는다).
        assertEquals(AILimitSurfaceText.noVisibleProviders, MeAILimitsText.aiLimitsNoProviders)
        assertEquals(AILimitSurfaceText.substitutedMainDevice, MeAILimitsText.aiLimitsSubstitutedDevice)
    }

    @Test
    fun middleDotIsU00B7() {
        for (s in listOf(AILimitSurfaceText.noVisibleProviders, inviteSecondLine)) {
            assertTrue(s.startsWith("맥·PC 앱에서"), "가운뎃점이 U+00B7 이 아니다: $s")
            assertFalse(s.contains('・') || s.contains('•'), "닮은 가운뎃점이 섞였다: $s")
        }
    }

    @Test
    fun noLineFallsBackToMacOnlyWording() {
        for (s in all) {
            assertFalse(s.startsWith("맥 앱에서"), "옛 맥 전용 문구로 돌아갔다: $s")
            assertFalse("고른 맥" in s, "옛 '고른 맥' 문구로 돌아갔다: $s")
        }
    }
}
