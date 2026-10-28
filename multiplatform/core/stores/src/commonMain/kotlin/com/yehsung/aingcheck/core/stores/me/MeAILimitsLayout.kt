// 원본: Sources/CheckMobileKit/Me/MeAILimitsLayout.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

/**
 * 폰 「AI 리밋」 카드의 가로 예산(v0.3.46 — 순수 계산). 카드 화면은 숫자 칸이 한 줄이라 넘쳐도 높이가 안 변하고 증상은 말줄임(= 숫자 자릿수
 * 오독 "100% 이…")이다 — 렌더 높이로는 안 잡혀서 값이 맞는지를 여기서 잰다. 단위는 iOS pt 와 같은 수의 dp 다(Compose 화면 갈래 W4-c 가
 * 같은 예산을 쓴다 — 글자 실측 상수는 iOS 실측이라 Android 글꼴로 다시 재야 한다).
 *
 * 한 줄의 가로 배치: `[이름 칸 108] 10 [5시간 바(남는 폭) 6 숫자 62] 10 [주간 바(남는 폭) 6 숫자 62]`.
 * INV-MeAILimitsLayout-1ce60481 이식: 바 폭은 **상수가 아니다** — 기기 폭이 다르면 남는 폭이 다르다. 두 바는 같은 몫을 받으므로 두 칸의 폭이
 *   언제나 같고, 열 머리 오른쪽 끝이 숫자 칸 오른쪽 끝과 **구조적으로** 맞는다(측정 상수가 아니라 항등식 — [barWidth] 는 산식이다).
 */
object MeAILimitCardBudget {
    // 기기 폭 → 카드 안쪽 폭
    const val sideMargin: Double = 16.0
    const val cardPadding: Double = 16.0

    fun cardOuterWidth(screenWidth: Double): Double = screenWidth - sideMargin * 2
    fun innerWidth(screenWidth: Double): Double = cardOuterWidth(screenWidth) - cardPadding * 2

    /** 이 앱이 받는 가장 좁은 기기(375)와 기본 기기(393) — Android 는 360dp 폭 기기도 받는다(화면 갈래가 그 폭으로도 되묻는다). */
    const val narrowestScreenWidth: Double = 375.0
    const val referenceScreenWidth: Double = 393.0

    // 가로 칸
    const val nameColumnWidth: Double = 108.0
    const val markSide: Double = 26.0
    const val markGap: Double = 6.0
    const val nameGap: Double = 10.0
    const val barValueGap: Double = 6.0
    const val columnGap: Double = 10.0
    const val valueWidth: Double = 62.0
    const val barHeight: Double = 6.0
    const val separatorHeight: Double = 1.0

    val nameTextWidth: Double get() = nameColumnWidth - markSide - markGap

    /** 바를 뺀 고정분 합. */
    val fixedWidth: Double get() = nameColumnWidth + nameGap + barValueGap * 2 + valueWidth * 2 + columnGap

    /** 바 하나의 폭 = 남는 것을 둘로 나눈다(**산식**이다 — 숫자 칸이나 간격을 고치면 바가 따라 줄어야 한다). */
    fun barWidth(innerWidth: Double): Double = (innerWidth - fixedWidth) / 2

    /** 한 칸(바 + 간격 + 숫자)의 폭. 두 칸은 **언제나 같다**. */
    fun cellWidth(innerWidth: Double): Double = barWidth(innerWidth) + barValueGap + valueWidth

    /** 바가 이보다 좁아지면 "조금 썼다"가 "안 썼다"로 보인다(= 이 설계의 하한). */
    const val minimumBarWidth: Double = 20.0

    // 글자 크기(기본 글자 크기에서의 pt)
    const val valueFontSize: Double = 12.0
    const val headerFontSize: Double = 11.0
    const val nameFontSize: Double = 13.0
    const val planFontSize: Double = 11.0

    /** iOS 실측: "100% 이상" 12pt bold monospacedDigit. */
    const val worstValueWidth: Double = 60.45

    /** iOS 실측: "안티그래비티" 13pt semibold. */
    const val worstNameWidth: Double = 67.47

    /** iOS 실측: "5시간" 11pt semibold. */
    const val worstHeaderWidth: Double = 26.21

    fun valueFits(measured: Double): Boolean = measured <= valueWidth

    // 기기 묶음 머리글(맥 두 대 이상) — 머리글은 구획 표시라 제공자 이름보다 조용하다.
    const val deviceNameFontSize: Double = 12.0
    const val deviceNameBottomGap: Double = 4.0
    const val deviceNameTopGap: Double = 8.0

    /** iOS 실측: `예성의 MacBook Pro (A1B2)` 12pt semibold. */
    const val worstDeviceNameWidth: Double = 154.65

    /** 그 이름이 **한 줄에** 들어가는가(넘으면 두 줄로 접힌다 — 말줄임이 아니다). */
    fun deviceNameFitsOneLine(measured: Double, screenWidth: Double): Boolean = measured <= innerWidth(screenWidth)

    // 겹침 꼬리는 **잘리지 않는 자리**에 있다(v0.3.47 P2) — 머리글은 [이름(두 줄까지 · 넘치면 말줄임)] [꼬리(제 폭 고정)].
    const val deviceTailGap: Double = 4.0

    /** iOS 실측: 가장 넓은 꼬리 `(WWWW)` 12pt semibold — 평균이 아니라 가장 넓은 쪽(눌리면 두 맥을 가를 글자가 없다). */
    const val worstDeviceTailWidth: Double = 57.6

    /** 꼬리가 그 기기에서 **반드시** 들어갈 자리가 있는가. */
    fun deviceTailAlwaysFits(measured: Double, screenWidth: Double): Boolean = measured + deviceTailGap <= innerWidth(screenWidth)

    /** 이름이 **두 줄에도 안 드는** 길이인가 = 말줄임이 확실히 나는 조건(두 줄 폭은 넉넉히 innerWidth × 2). */
    fun deviceNameOverflowsTwoLines(measured: Double, screenWidth: Double): Boolean = measured > innerWidth(screenWidth) * 2
}
