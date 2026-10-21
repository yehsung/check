// 원본: Sources/CheckMobileKit/Theme/MobileThemePalette.swift @ a63fea2
// 원본: Sources/check/CheckGachaWindow.swift @ a63fea2 (GachaWindowPalette — 브랜드 보라 판·글자)
// 원본: Sources/CheckCore/CheckTheme.swift @ a63fea2 (맥 다크 남색 가족 — 다크 값의 출처)
//
// 색 토큰의 **숫자**. 화면은 이 값을 직접 쓰지 않고 AingTheme.colors(뜻 이름) 또는 MaterialTheme.colorScheme(M3 부품)을 쓴다.
// 값은 iOS·맥 원본 그대로다 — `AingPaletteSwiftContractTest` 가 Swift 원문을 읽어 토큰마다 대조한다(원본이 바뀌면 빨강).
package com.yehsung.aingcheck.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Color
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

/** 한 색(채널 0…1) + 불투명도. Swift `MobileThemePalette.RGB` 와 같은 뜻 — 불투명도가 1 이 아니면 아래 면에 겹쳐 그린다(CSS rgba). */
@Immutable
data class AingRgb(val r: Double, val g: Double, val b: Double, val alpha: Double = 1.0) {
    /** 불투명한 [backdrop] 위에 겹친 결과(불투명). */
    fun compositedOver(backdrop: AingRgb): AingRgb {
        val a = alpha
        return AingRgb(r * a + backdrop.r * (1 - a), g * a + backdrop.g * (1 - a), b * a + backdrop.b * (1 - a))
    }

    /** 같은 색, 다른 불투명도. */
    fun opacity(value: Double): AingRgb = copy(alpha = value)

    /** WCAG 상대 휘도(불투명 기준 — 반투명이면 먼저 [compositedOver]). */
    val relativeLuminance: Double
        get() {
            fun channel(c: Double) = if (c <= 0.03928) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }

    /** WCAG 대비(1…21). 반투명 색은 상대 면 위에 겹친 뒤 잰다. */
    fun contrast(against: AingRgb): Double {
        val fg = if (alpha < 1) compositedOver(against) else this
        val a = fg.relativeLuminance
        val b = against.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /** 0xRRGGBB(반올림) — 대조용. */
    val hex: Int
        get() {
            fun byte(v: Double) = (v * 255).roundToInt().coerceIn(0, 255)
            return (byte(r) shl 16) or (byte(g) shl 8) or byte(b)
        }

    /** Compose 색(sRGB). */
    fun toColor(): Color = Color(r.toFloat(), g.toFloat(), b.toFloat(), alpha.toFloat())

    /** 두 색이 채널마다 [tolerance] 안에서 같은가(시험·대조용). */
    fun approximatelyEquals(other: AingRgb, tolerance: Double = 1e-9): Boolean =
        abs(r - other.r) <= tolerance && abs(g - other.g) <= tolerance && abs(b - other.b) <= tolerance &&
            abs(alpha - other.alpha) <= tolerance

    companion object {
        fun hex(hex: Int, alpha: Double = 1.0) =
            AingRgb(((hex shr 16) and 0xFF) / 255.0, ((hex shr 8) and 0xFF) / 255.0, (hex and 0xFF) / 255.0, alpha)

        /** 0…255 정수 채널(시안 rgba(60,60,67,.74) 를 그대로 옮기는 모양). */
        fun rgb255(r: Int, g: Int, b: Int, alpha: Double = 1.0) = AingRgb(r / 255.0, g / 255.0, b / 255.0, alpha)
    }
}

/** 한 토큰의 라이트·다크 값. */
@Immutable
data class AingPair(val light: AingRgb, val dark: AingRgb) {
    fun pick(dark: Boolean): AingRgb = if (dark) this.dark else light

    companion object {
        /** 라이트·다크 구분 없는 값(메달·재질). */
        fun both(value: AingRgb) = AingPair(value, value)
    }
}

/**
 * 토큰 표. **한 줄 = 토큰 하나(라이트/다크 쌍)** — 이름과 순서는 Swift `MobileThemePalette` 와 같다.
 * 맨 아래 `brand*` 는 이식에서 더한 자리다: M3 뼈대(탭 막대·스위치·대화상자 단추)를 칠할 브랜드 보라(맥 뽑기 창 판·글자 색).
 */
object AingPalette {
    // MARK: 바탕·표면
    val background = AingPair(AingRgb.hex(0xF2F2F7), AingRgb.hex(0x1A1C26))
    val surface = AingPair(AingRgb.hex(0xFFFFFF), AingRgb.hex(0x2B2E3D))
    val surface2 = AingPair(AingRgb.hex(0xF4F4F8), AingRgb.hex(0x353848))
    val fill = AingPair(AingRgb.rgb255(118, 118, 128, 0.12), AingRgb.hex(0xFFFFFF, 0.09))
    val fill2 = AingPair(AingRgb.rgb255(118, 118, 128, 0.07), AingRgb.hex(0xFFFFFF, 0.05))
    val separator = AingPair(AingRgb.rgb255(60, 60, 67, 0.17), AingRgb.hex(0xFFFFFF, 0.10))
    val glass = AingPair(AingRgb.hex(0xFFFFFF, 0.74), AingRgb.rgb255(51, 54, 74, 0.82))
    val glassLine = AingPair(AingRgb.hex(0x000000, 0.07), AingRgb.hex(0xFFFFFF, 0.14))
    val bubbleIn = AingPair(AingRgb.hex(0xE9E9EE), AingRgb.hex(0x343747))

    // MARK: 글자
    val label = AingPair(AingRgb.hex(0x0B0B10), AingRgb.hex(0xFFFFFF, 0.95))
    val label2 = AingPair(AingRgb.rgb255(60, 60, 67, 0.74), AingRgb.rgb255(235, 236, 245, 0.64))
    /** 3단 기호·선 전용(글자 금지 — 라이트 1.9:1). */
    val label3 = AingPair(AingRgb.rgb255(60, 60, 67, 0.34), AingRgb.rgb255(235, 236, 245, 0.30))
    /** 3단 글자(자리표시·끝난 할 일·모자란 가격). */
    val label3Text = AingPair(AingRgb.rgb255(60, 60, 67, 0.73), AingRgb.rgb255(235, 236, 245, 0.56))

    // MARK: 뜻 색 — 이 뜻으로만 쓴다(초록 = 근무 중·달성 · 앰버 = 끊김·대기 · 파랑 = 선택·진행·링크 · 빨강 = 위험 · 보라 = AI 토큰)
    val accent = AingPair(AingRgb.hex(0x1864CF), AingRgb(0.33, 0.67, 1.0))
    val accentFill = AingPair(AingRgb.hex(0x1864CF), AingRgb.hex(0x2A74DE))
    val accentTint = AingPair(AingRgb.hex(0x1864CF, 0.10), AingRgb(0.33, 0.67, 1.0, 0.11))
    val accentLine = AingPair(AingRgb.hex(0x1864CF, 0.30), AingRgb(0.33, 0.67, 1.0, 0.38))
    val onAccentFill = AingPair.both(AingRgb.hex(0xFFFFFF))
    val tabSelected = AingPair(AingRgb.hex(0x1864CF), AingRgb.hex(0x7DC0FF))

    val working = AingPair(AingRgb.hex(0x127A51), AingRgb(0.35, 0.88, 0.63))
    val workingDot = AingPair(AingRgb.hex(0x2FC47E), AingRgb(0.35, 0.88, 0.63))
    val workingTint = AingPair(AingRgb.hex(0x2FC47E, 0.14), AingRgb(0.35, 0.88, 0.63, 0.14))
    val offWork = AingPair(AingRgb.hex(0x666E7D), AingRgb(0.58, 0.68, 0.80))
    val offWorkDot = AingPair(AingRgb.hex(0xA7B1C0), AingRgb(0.58, 0.68, 0.80))
    val pending = AingPair(AingRgb.hex(0x9A5B00), AingRgb(1.0, 0.72, 0.33))
    val pendingDot = AingPair(AingRgb.hex(0xFFA826), AingRgb(1.0, 0.72, 0.33))
    val pendingTint = AingPair(AingRgb.hex(0xFFA826, 0.16), AingRgb(1.0, 0.72, 0.33, 0.16))
    val danger = AingPair(AingRgb.hex(0xC83238), AingRgb(1.0, 0.45, 0.46))
    val dangerTint = AingPair(AingRgb.hex(0xC83238, 0.10), AingRgb(1.0, 0.45, 0.46, 0.08))
    val aiToken = AingPair(AingRgb.hex(0x7A4FE0), AingRgb(0.72, 0.55, 1.0))
    val badge = AingPair.both(AingRgb.hex(0xFF3B30))

    // MARK: 순위 메달
    val gold = AingPair(AingRgb.hex(0xF5B700), AingRgb.hex(0xFFD24A))
    val silver = AingPair(AingRgb.hex(0xAAB3C0), AingRgb.hex(0xD6DCE6))
    val bronze = AingPair(AingRgb.hex(0xD38445), AingRgb.hex(0xE0955A))
    val goldInk = AingPair.both(AingRgb.hex(0x4A3500))
    val silverInk = AingPair.both(AingRgb.hex(0x2B313A))
    val bronzeInk = AingPair.both(AingRgb.hex(0x3F1E05))
    val crownInk = AingPair.both(AingRgb.hex(0x5A4100))

    // MARK: 그라디언트 — 두 곳(+ 나무판 재질)만
    /** '우리 팀' 게이지 전용. */
    val gaugeStops = listOf(AingRgb.hex(0x59E0A1), AingRgb.hex(0x54ABFF))
    /** 로그인 버튼 전용. */
    val startStops = listOf(AingRgb.hex(0x52D994), AingRgb.hex(0x2EAD9E))
    /** 오목 나무판. */
    val woodStops = listOf(AingRgb.hex(0xE0BA7D), AingRgb.hex(0xC99E61))
    val brandNavy = AingRgb.hex(0x1A1A2E)
    /** 아잉이 몸 색(라벤더). */
    val brandLavender = AingRgb.hex(0x9979E6)

    // MARK: 이니셜 원(맥 해시 팔레트 6색의 틴트형 — 순서는 파랑·청록·주황·분홍·보라·초록)
    val avatarInks = listOf(
        AingPair(AingRgb.hex(0x365AC0), AingRgb.hex(0xA0BAFF)),
        AingPair(AingRgb.hex(0x176C67), AingRgb.hex(0x5DD3CB)),
        AingPair(AingRgb.hex(0x8E510C), AingRgb.hex(0xF5B36A)),
        AingPair(AingRgb.hex(0xA73658), AingRgb.hex(0xF6A0B5)),
        AingPair(AingRgb.hex(0x6F46C1), AingRgb.hex(0xC5ABF4)),
        AingPair(AingRgb.hex(0x206D41), AingRgb.hex(0x7ED9A2)),
    )
    const val AVATAR_TINT_OPACITY_LIGHT = 0.15
    const val AVATAR_TINT_OPACITY_DARK = 0.16

    /** 이름 → 팔레트 칸(맥 `CheckTheme.avatarColor(for:)` 와 같은 해시: 유니코드 스칼라 합 mod 6). */
    fun avatarIndex(seed: String): Int {
        var sum = 0L // Swift Int(64비트) `&+` 와 같은 폭
        var i = 0
        while (i < seed.length) {
            val cp = seed.codePointAtCompat(i)
            sum += cp
            i += if (cp >= 0x10000) 2 else 1
        }
        return (abs(sum) % avatarInks.size).toInt()
    }

    // MARK: 위젯
    val widgetBackground = AingPair(AingRgb.hex(0xFFFFFF), AingRgb.hex(0x232633))

    // MARK: 브랜드 보라(이식에서 더함 — 맥 GachaWindowPalette 의 판·글자 색. M3 뼈대 칠, 동적 색 대신)
    /** 보라 글자·채움(라이트 진한 라벤더 · 다크 옅은 라벤더). */
    val brandInk = AingPair(AingRgb.hex(0x6A4FC8), AingRgb.hex(0xCDBDFF))
    /** 보라 판 위 제목 글자(라이트 짙은 가지색 · 다크 거의 흰 라벤더). */
    val brandTitle = AingPair(AingRgb.hex(0x2D2150), AingRgb.hex(0xF4EFFF))
    /** 보라 판(라이트 흰 판 97% · 다크 보라 판). */
    val brandCard = AingPair(AingRgb.hex(0xFFFFFF, 0.97), AingRgb.hex(0x2B2148))

    // MARK: 대비 검사 대상(BaseThemeTests 와 같은 묶음)
    val textTokens: List<Pair<String, AingPair>> = listOf(
        "label" to label, "label2" to label2, "label3Text" to label3Text,
        "accent" to accent, "working" to working, "offWork" to offWork, "pending" to pending,
        "danger" to danger, "aiToken" to aiToken,
    )

    val tintedTextPairs: List<Triple<String, AingPair, AingPair>> = listOf(
        Triple("accent/accentTint", accent, accentTint),
        Triple("working/workingTint", working, workingTint),
        Triple("pending/pendingTint", pending, pendingTint),
        Triple("danger/dangerTint", danger, dangerTint),
    )
}

/** 공용 코드에서 쓰는 코드 포인트(대리 쌍 합치기). */
internal fun String.codePointAtCompat(index: Int): Int {
    val high = this[index]
    if (high.isHighSurrogate() && index + 1 < length) {
        val low = this[index + 1]
        if (low.isLowSurrogate()) return ((high.code - 0xD800) shl 10) + (low.code - 0xDC00) + 0x10000
    }
    return high.code
}
