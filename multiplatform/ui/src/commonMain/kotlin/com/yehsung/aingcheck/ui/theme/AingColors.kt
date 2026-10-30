// 원본: Sources/CheckMobileKit/Theme/MobileTheme.swift @ 862be0f
//
// 뜻 이름 색(라이트·다크 중 하나로 굳힌 Compose 색). 화면은 `AingTheme.colors.working` 처럼 쓴다 — 색 리터럴을 화면에 적지 않는다.
package com.yehsung.aingcheck.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color

@Immutable
class AingColors private constructor(val isDark: Boolean) {
    private fun c(pair: AingPair): Color = pair.pick(isDark).toColor()

    // 바탕·표면
    val background = c(AingPalette.background)
    val surface = c(AingPalette.surface)
    val surface2 = c(AingPalette.surface2)
    val fill = c(AingPalette.fill)
    val fill2 = c(AingPalette.fill2)
    val separator = c(AingPalette.separator)
    val glass = c(AingPalette.glass)
    val glassLine = c(AingPalette.glassLine)
    val bubbleIn = c(AingPalette.bubbleIn)

    // 글자
    val label = c(AingPalette.label)
    val label2 = c(AingPalette.label2)
    /** 선·기호 전용(글자 금지 — 글자는 [label3Text]). */
    val label3 = c(AingPalette.label3)
    val label3Text = c(AingPalette.label3Text)

    // 뜻 색
    val accent = c(AingPalette.accent)
    val accentFill = c(AingPalette.accentFill)
    val accentTint = c(AingPalette.accentTint)
    val accentLine = c(AingPalette.accentLine)
    val onAccentFill = c(AingPalette.onAccentFill)
    val tabSelected = c(AingPalette.tabSelected)
    val working = c(AingPalette.working)
    val workingDot = c(AingPalette.workingDot)
    val workingTint = c(AingPalette.workingTint)
    val offWork = c(AingPalette.offWork)
    val offWorkDot = c(AingPalette.offWorkDot)
    val pending = c(AingPalette.pending)
    val pendingDot = c(AingPalette.pendingDot)
    val pendingTint = c(AingPalette.pendingTint)
    val danger = c(AingPalette.danger)
    val dangerTint = c(AingPalette.dangerTint)
    val aiToken = c(AingPalette.aiToken)
    val badge = c(AingPalette.badge)

    // 메달
    val gold = c(AingPalette.gold)
    val silver = c(AingPalette.silver)
    val bronze = c(AingPalette.bronze)
    val goldInk = c(AingPalette.goldInk)
    val silverInk = c(AingPalette.silverInk)
    val bronzeInk = c(AingPalette.bronzeInk)
    val crownInk = c(AingPalette.crownInk)

    // 희귀 강조(뽑기 전용 내장 둘 — 황금 · 무지개). 브랜드 자리처럼 뽑기 화면에서만 쓴다.
    /** 금빛 글자·기호(메달 [gold] 는 원 바탕 전용). */
    val goldText = c(AingPalette.goldText)
    /** 무지개 일곱 빛(빨 → 보) — 이름·테두리 칠. */
    val rainbowStops: List<Color> = AingPalette.rainbowStops.map { c(it) }

    // 그라디언트 정지점(뜻으로만 — '우리 팀' 게이지 · 로그인 단추 · 나무판)
    val gaugeStops: List<Color> = AingPalette.gaugeStops.map { it.toColor() }
    val startStops: List<Color> = AingPalette.startStops.map { it.toColor() }
    val woodStops: List<Color> = AingPalette.woodStops.map { it.toColor() }

    // 위젯
    val widgetBackground = c(AingPalette.widgetBackground)

    // 브랜드 보라 — 브랜드 자리 전용(뽑기·아잉이·이모티콘·앱 아이콘, G §8-15). M3 뼈대·선택 표시는 위 accent 가족(iOS 파랑).
    val brandInk = c(AingPalette.brandInk)
    val brandTitle = c(AingPalette.brandTitle)
    val brandCard = c(AingPalette.brandCard)
    val brandLavender = AingPalette.brandLavender.toColor()
    val brandNavy = AingPalette.brandNavy.toColor()

    // 데스크톱 오버레이 말풍선(인사 · 메시지 도착 · 대결 신청 — 맥 CheckGreetingBubble/CheckMessageArrivalBubble, 공용 패치 6).
    // 맥 말풍선은 어둠 모드에서도 흰 캡슐이라 **라이트 · 다크가 같은 값**이다(라이트 표면 · 글자에 불투명도 — W5-b2 BubbleStyle 이 임시로 쓴 값 그대로).
    /** 말풍선 바탕(흰 0.92). */
    val overlayBubbleFill = AingPalette.surface.light.toColor().copy(alpha = 0.92f)

    /** 말풍선 테두리(0.5 획, 검정 0.10). */
    val overlayBubbleStroke = AingPalette.label.light.toColor().copy(alpha = 0.10f)

    /** 말풍선 글자(검정 0.85). */
    val overlayBubbleText = AingPalette.label.light.toColor().copy(alpha = 0.85f)

    /** 도착 강조 — 누를 수 있는 말풍선(메시지 도착 · 대결 신청)의 ›(검정 0.45). */
    val overlayBubbleArrival = AingPalette.label.light.toColor().copy(alpha = 0.45f)

    // 데스크톱 할 일 보드(공용 패치 6). 틴트 = 보드 바탕(W5-b3 이 쓴 표면색 그대로 — 진하기 · 블러는 W-3 #9 외양 갈래).
    /** 보드 바탕 틴트. */
    val boardTint = c(AingPalette.surface)

    /** 보드 글자 후광(맥 todoBoardTextHalo 의 검정 — 세기 · 겹수는 쓰는 쪽이 정한다). */
    val boardTextHalo = AingRgb.hex(0x000000).toColor()

    /** 이니셜 원: (글자 색, 원 바탕 색). */
    fun avatar(seed: String): Pair<Color, Color> {
        val ink = AingPalette.avatarInks[AingPalette.avatarIndex(seed)].pick(isDark)
        val tint = ink.opacity(if (isDark) AingPalette.AVATAR_TINT_OPACITY_DARK else AingPalette.AVATAR_TINT_OPACITY_LIGHT)
        return ink.toColor() to tint.toColor()
    }

    companion object {
        val Light = AingColors(isDark = false)
        val Dark = AingColors(isDark = true)

        fun of(dark: Boolean): AingColors = if (dark) Dark else Light
    }
}
