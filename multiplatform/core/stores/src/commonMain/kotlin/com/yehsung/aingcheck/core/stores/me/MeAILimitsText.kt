// 원본: Sources/CheckMobileKit/Me/MeAILimitsText.swift · Sources/CheckMobileShared/AILimitSurfaceRules.swift:80-110(AILimitSurfaceText) · Sources/CheckMobileShared/AILimitColumnStyle.swift:118-120(AILimitColumnText) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.ailimit.AILimitDisplay
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.format.TokenNumberFormatter
import com.yehsung.aingcheck.core.rules.insights.TokenDailyGrid

/**
 * 그릴 줄이 **하나도 없을 때** 폰 카드와 위젯이 쓰는 한 문장 · 다른 맥으로 대체했을 때의 한 줄. 두 표면이 **같은 상수**를 쓴다(위젯 — W2-f —
 * 은 이 모듈을 본다). 까닭(연동 없음 / 맥 설정에서 껐음)을 가르지 않는다 — 위젯은 가릴 수 없고, 폰의 단서는 3일이면 스스로 사라져 문구가 혼자 바뀐다.
 */
object AILimitSurfaceText {
    const val noVisibleProviders = "맥 앱에서 AI 도구에 로그인하고 리밋 보기를 켜면 보여요"

    /** 고른 맥 대신 **다른 맥**을 그리고 있을 때(v0.3.47 P1). 고른 맥의 이름은 적지 않는다(꼬리 규약이 보이는 묶음 사이에서만 선다). */
    const val substitutedMainDevice = "고른 맥은 지금 보여 줄 숫자가 없어서 다른 맥을 보여 주고 있어요"
}

/** 창이 **아예 없는** 칸의 글자. `—`(판정 불가)와 다른 말이다 — 데스크톱 카드 모델과 같은 글자여야 한다. */
object AILimitColumnText {
    const val absentValueText = "없음"
}

/**
 * AI 리밋 카드 문구(플랫폼 무관). 규약: **출처를 말하지 않는다**(캡션은 나이만) · 숫자·캡션·"이상"은 코어 규칙(AILimitDisplay)이 만든다 —
 * 여기는 제목·빈 상태·토큰 줄처럼 리밋 값이 아닌 문장뿐이다.
 */
object MeAILimitsText {
    const val aiLimitsTitle = "AI 리밋"
    const val aiLimitsCaption = "5시간 창과 주간 창에서 쓴 비율이에요."
    const val aiLimitsLoading = MeText.loading
    const val aiLimitsFailed = "AI 리밋을 불러오지 못했어요"

    /**
     * 그릴 줄이 하나도 없다 — 까닭이 **둘**이다(연동 없음 · 맥 설정에서 껐음). 글자는 위젯과 **같은 상수** 하나에서 온다.
     * INV-MeAILimitsText-b8342336 이식: 여기에 "로그인하면 보여요" 를 다시 적지 마라 — 설정에서 끈 사람은 이미 로그인해 있다.
     */
    const val aiLimitsNoProviders = AILimitSurfaceText.noVisibleProviders

    const val aiLimitsSubstitutedDevice = AILimitSurfaceText.substitutedMainDevice

    /** 카드 제목의 보이스오버가 덧붙이는 말("가장 높은" — 요약은 5시간 창의 **최악**을 모은다). */
    const val aiLimitsFiveHourPeak = "5시간 가장 높은 값"

    /** 창 라벨 + 값 한 줄(보이스오버). 예: "Claude 5시간 27%, 12분 전". */
    fun aiLimitAccessibility(provider: AILimitProvider, display: AILimitDisplay): String {
        val window = display.window?.displayName ?: ""
        return "${provider.displayName} $window ${display.valueText}, ${display.captionText}"
    }

    /**
     * 줄 하나를 **한 문장**으로(보이스오버) — 기기 이름이 **맨 앞**이다(묶음 머리글을 지나쳐 줄에 바로 닿은 사람에게 주인을 먼저 말한다).
     * [deviceName] null = 맥이 한 대다.
     */
    fun aiLimitRowAccessibility(deviceName: String?, row: AILimitDisplayRow): String {
        val windows = AILimitWindow.entries.sortedBy { it.sortOrder }.map { window ->
            val display = row.display(window) ?: return@map aiLimitAbsentAccessibility(window)
            aiLimitAccessibility(row.provider, display)
        }
        return (listOfNotNull(deviceName, row.provider.displayName) + windows).joinToString(", ")
    }

    /**
     * 그 창이 **아예 없는** 칸(보이스오버). 예: "5시간 없음".
     * INV-MeAILimitsText-2aebf345 이식: 판정 불가(`—`)와 **다른 말이어야 한다** — 화면의 글자를 그대로 읽어 주는 것이고 글자는 공유 규칙
     *   ([AILimitColumnText.absentValueText]) 하나에서 온다. "모름"을 따로 적으면 보는 사람과 듣는 사람이 다른 사실을 받는다.
     */
    fun aiLimitAbsentAccessibility(window: AILimitWindow): String = "${window.displayName} ${AILimitColumnText.absentValueText}"

    // 토큰 축(리밋과 나란히 — 섞지 않는다)

    const val aiTokenTodayTitle = "오늘 AI 토큰"
    const val aiTokenRecentTitle = "최근 12주"

    /** "12,345,678 토큰" · 0 이면 "사용 없음"(잔디 말풍선과 **같은 함수**). */
    fun aiTokenValue(tokens: Long): String = TokenDailyGrid.tooltipValueText(tokens)

    /** 좁은 자리용 축약 — "196.6억 토큰". */
    fun aiTokenCompact(tokens: Long): String =
        if (tokens > 0) "${TokenNumberFormatter.compactKorean(tokens)} 토큰" else TokenDailyGrid.tooltipValueText(0)
}
