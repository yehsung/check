// 원본: Sources/check/CheckTodoBoardAppearance.swift :16-58(TodoBoardTint 재질 실측) · :62-86(TodoBoardContrast) · :105-368(TodoBoardAppearance
//       범위·파생값·대비) · :376-453(TodoBoardAppearanceStore 영속·조작) · CheckTodoBoardWindow.swift :76-182(⌥+스크롤 누적기) ·
//       :741-744(adjustsOpacity) · CheckTodoBoardView.swift :103-139(TodoBoardTextShadow) — W-3 #9 뒤로 미룬 보드 외양(W-9 #1 W5-b4)
//
// 사용자가 만지는 값은 **진하기 하나**(opacity, 0.20~0.95, 기본 0.55). 나머지(틴트·재질 겹·표면 배율·글자 그림자)는 전부 파생이다.
// Windows 에는 맥 hudWindow 블러 재질이 없다 — 재질의 **밝기 기여**(회색 0.283 을 알파 0.40×blurAlpha 로 한 겹)만 그려서
// 평평한 바탕 위의 색·대비 수식이 맥과 같게 한다(블러 자체는 없음 — unresolved).
package com.yehsung.aingcheck.desktop.overlay.todoboard

import androidx.compose.ui.graphics.Color
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToLong

/** sRGB 성분(0…1). */
data class BoardRgb(val r: Double, val g: Double, val b: Double) {
    companion object {
        fun gray(level: Double) = BoardRgb(level, level, level)
    }
}

/** 맥 TodoBoardTint(:16) — 재질 실측 상수(정본 한 벌). */
object TodoBoardTint {
    /** 출고 세기 = 사용자 조절 기본값(리터럴을 따로 두지 않는다 — :19). */
    const val OPACITY: Double = TodoBoardAppearance.DEFAULT_OPACITY
    /** hudWindow(다크) 재질 틴트 알파 — 실측 0.40(:22). */
    const val MATERIAL_TINT_ALPHA = 0.40
    /** 그 틴트의 회색 레벨 — 실측 0.283, 순흑이 아니다(:27). */
    const val MATERIAL_TINT_WHITE = 0.283
    /** 순백 바탕이 재질을 통과한 밝기 — 0.713(:32). */
    const val HUD_OVER_WHITE_LEVEL = 0.713
    /** CheckTheme.panel 의 sRGB(:41). */
    val PANEL_RGB = BoardRgb(0.17, 0.18, 0.24)
    /** CheckTheme.primaryText 흰색 알파(:44). */
    const val PRIMARY_TEXT_ALPHA = 0.94
    /** CheckTheme.secondaryText 흰색 알파(:46). */
    const val SECONDARY_TEXT_ALPHA = 0.68
    /** 보드 테두리 — 흰색 0.18 1px(CheckTodoBoardView.swift:453). 선은 표면 배율을 받지 않는다. */
    const val BORDER_WHITE_ALPHA = 0.18

    // ── 그리는 색 — 색은 **테마 토큰에서만** 받는다(D5): 보드는 어두움 고정이라 boardTint(어두움 0x2B2E3D) = CheckTheme.panel,
    //    label(어두움 = 흰색) · boardTextHalo(검정)에 알파만 준다. ──

    /**
     * 재질 겹(Windows 는 블러 없이 밝기 기여만) — 회색 0.283 × 알파 a(= 0.40·blurAlpha) 한 겹과 **같은 합성**을 흰색 w → 검정 k 두 겹으로 낸다:
     * (1−k)(w + (1−w)B) = 0.283a + (1−a)B ⇔ k = 0.717a, w = 0.283a/(1−k). 반환 = (흰 겹, 검정 겹) 알파.
     */
    fun materialLayerAlphas(blurAlpha: Double): Pair<Double, Double> {
        val a = MATERIAL_TINT_ALPHA * blurAlpha.coerceIn(0.0, 1.0)
        val k = (1 - MATERIAL_TINT_WHITE) * a
        val w = if (k >= 1.0) 0.0 else MATERIAL_TINT_WHITE * a / (1 - k)
        return w to k
    }

    fun materialWhite(colors: AingColors, blurAlpha: Double): Color = colors.label.copy(alpha = materialLayerAlphas(blurAlpha).first.toFloat())
    fun materialBlack(colors: AingColors, blurAlpha: Double): Color = colors.boardTextHalo.copy(alpha = materialLayerAlphas(blurAlpha).second.toFloat())

    /** CheckTheme.panel × [alpha](맥 CheckTodoBoardView.swift:472). */
    fun panelColor(colors: AingColors, alpha: Double): Color = colors.boardTint.copy(alpha = alpha.coerceIn(0.0, 1.0).toFloat())

    /** 테두리 흰색 0.18(:453). */
    fun borderColor(colors: AingColors): Color = colors.label.copy(alpha = BORDER_WHITE_ALPHA.toFloat())

    /** 글자 헤일로 — 검정 × 알파(:151). */
    fun haloColor(colors: AingColors, alpha: Double): Color = colors.boardTextHalo.copy(alpha = alpha.coerceIn(0.0, 1.0).toFloat())

    /** 진하기 버튼 원(TodoBoardOpacityButton :914) — 켜짐·호버 0.14, 평소 0.06. 면이라 표면 배율을 받는다. */
    fun opacityButtonFill(colors: AingColors, on: Boolean): Color = colors.label.copy(alpha = if (on) 0.14f else 0.06f)

    /** 재질을 바탕 위에 얹은 밝기(:51). 블러가 걷히면 재질 틴트 기여도 같이 준다. */
    fun materialLevel(over: Double, blurAlpha: Double = 1.0): Double {
        val alpha = MATERIAL_TINT_ALPHA * blurAlpha.coerceIn(0.0, 1.0)
        return alpha * MATERIAL_TINT_WHITE + (1 - alpha) * over
    }
}

/** 맥 TodoBoardContrast(:62) — WCAG 2.x 상대휘도·대비비. */
object TodoBoardContrast {
    const val AA_BODY_TEXT = 4.5
    const val AA_LARGE_TEXT = 3.0

    fun relativeLuminance(c: BoardRgb): Double {
        fun linear(ch: Double) = if (ch <= 0.04045) ch / 12.92 else ((ch + 0.055) / 1.055).pow(2.4)
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    fun ratio(a: BoardRgb, b: BoardRgb): Double {
        val la = relativeLuminance(a)
        val lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/** 맥 TodoBoardAppearance(:105) — 값 하나에서 화면이 쓰는 숫자를 전부 파생한다. */
data class TodoBoardAppearance(val opacity: Double = DEFAULT_OPACITY) {
    companion object {
        /** 가장 투명 — 판으로 보이는 하한(:164). */
        const val MIN_OPACITY = 0.20
        /** 가장 불투명 — 1.0 을 주지 않는 건 정체성 때문(:170). */
        const val MAX_OPACITY = 0.95
        /** 기본 — 블러 1.0 · 그림자 꺼짐(:175). */
        const val DEFAULT_OPACITY = 0.55
        /** 키 1회·스크롤 1틱(:181) — 레일을 15스텝에 훑는다. */
        const val STEP = 0.05
        /** 블러 무릎점 = 그림자 임계(같은 숫자가 설계 — :209). */
        const val BLUR_KNEE = 0.52

        /** 레일 안으로(:222). NaN 만 기본값, ±무한대는 그쪽 끝. 0.1% 격자로 반올림. */
        fun clamped(value: Double): Double {
            if (value.isNaN()) return DEFAULT_OPACITY
            val bounded = min(max(value, MIN_OPACITY), MAX_OPACITY)
            return (bounded * 1000).roundHalfAwayFromZero() / 1000
        }

        /** 두 겹 알파를 직접 주는 대비(:336). */
        fun textContrast(tintAlpha: Double, blurAlpha: Double, textAlpha: Double = TodoBoardTint.PRIMARY_TEXT_ALPHA, backdrop: Double = 1.0): Double {
            val behind = TodoBoardTint.materialLevel(backdrop, blurAlpha)
            val background = blend(TodoBoardTint.PANEL_RGB, BoardRgb.gray(behind), tintAlpha)
            val text = blend(BoardRgb.gray(1.0), background, textAlpha)
            return TodoBoardContrast.ratio(text, background)
        }

        /** 알파 합성 한 겹(sRGB 성분 공간 — :350). */
        fun blend(color: BoardRgb, over: BoardRgb, alpha: Double): BoardRgb {
            val a = alpha.coerceIn(0.0, 1.0)
            return BoardRgb(a * color.r + (1 - a) * over.r, a * color.g + (1 - a) * over.g, a * color.b + (1 - a) * over.b)
        }

        /** Swift `.rounded()`(0.5 는 0 에서 먼 쪽) — Kotlin roundToLong 은 음수 반에서 다르다. */
        private fun Double.roundHalfAwayFromZero(): Double = if (this >= 0) (this + 0.5).let { kotlin.math.floor(it) } else -kotlin.math.floor(-this + 0.5)
    }

    /** 패널 틴트 알파 = 사용자 값(:231). */
    val tintAlpha: Double get() = clamped(opacity)

    /** 재질(블러) 겹의 알파(:271) — 무릎점 위 1.0, 아래 t^1.5. */
    val blurAlpha: Double
        get() {
            val op = clamped(opacity)
            if (op >= BLUR_KNEE) return 1.0
            val t = (op - MIN_OPACITY) / (BLUR_KNEE - MIN_OPACITY)
            return t.pow(1.5).coerceIn(0.0, 1.0)
        }

    /** 보드 위 표면(입력창·배지·버튼 원)의 알파 배율(:302). 글자·선에는 곱하지 않는다. */
    val surfaceAlpha: Double get() = min(clamped(opacity) / DEFAULT_OPACITY, 1.0)

    /** 무릎점 아래면 글자 뒤에 어두운 헤일로(:315). */
    val needsTextShadow: Boolean get() = clamped(opacity) < BLUR_KNEE

    /** "55%"(:318). */
    val percentLabel: String get() = "${(clamped(opacity) * 100).roundHalfAwayFromZero().toLong()}%"

    /** 순백 바탕 위 보드 배경(:323). */
    val backgroundLevel: BoardRgb get() = backgroundOver(1.0)

    /** [backdrop] 밝기 바탕 위 보드 배경 — 화면 합성 순서(바탕 → 재질 겹 → 패널 틴트)와 같다. */
    fun backgroundOver(backdrop: Double): BoardRgb {
        val behind = TodoBoardTint.materialLevel(backdrop, blurAlpha)
        return blend(TodoBoardTint.PANEL_RGB, BoardRgb.gray(behind), tintAlpha)
    }

    fun textContrast(textAlpha: Double = TodoBoardTint.PRIMARY_TEXT_ALPHA, backdrop: Double = 1.0): Double =
        textContrast(tintAlpha, blurAlpha, textAlpha, backdrop)
}

/** 맥 TodoBoardTextShadow(CheckTodoBoardView.swift:103-139) — 헤일로 세기 0…1. */
object TodoBoardTextShadow {
    const val RAMP_STEPS = 2.0
    const val TIGHT_RADIUS = 1.0
    const val TIGHT_ALPHA = 1.0
    const val SOFT_RADIUS = 4.0
    const val SOFT_ALPHA = 0.7

    /** 켤지는 needsTextShadow 만 정한다. 세기는 기본값을 0 으로 잡은 램프, 하한 0.5. */
    fun strength(appearance: TodoBoardAppearance): Double {
        if (!appearance.needsTextShadow) return 0.0
        val span = TodoBoardAppearance.STEP * RAMP_STEPS
        val ramp = (TodoBoardAppearance.DEFAULT_OPACITY - appearance.tintAlpha) / span
        return min(max(ramp, 0.5), 1.0)
    }
}

/**
 * 보드 진하기의 주인(맥 TodoBoardAppearanceStore :376). 값 하나를 **맥 키 이름** `check.todoBoardOpacity` 에 남기고 바뀔 때만 알린다.
 * kv 는 문자열이라 숫자를 문자열로 쓴다(맥도 문자열 저장을 받아 준다 — :422). 모든 호출은 UI 스레드에서.
 */
class TodoBoardAppearanceStore(private val kv: DesktopKeyValueStore) {
    companion object {
        const val DEFAULTS_KEY = "check.todoBoardOpacity"

        /** 읽기는 clamp 가 아니라 **검증**이다(:406) — 범위 밖·해석 불가면 기본값. */
        fun restoredOpacity(raw: String?): Double {
            val stored = raw?.trim()?.toDoubleOrNull() ?: return TodoBoardAppearance.DEFAULT_OPACITY
            if (!stored.isFinite() || stored < TodoBoardAppearance.MIN_OPACITY || stored > TodoBoardAppearance.MAX_OPACITY) {
                return TodoBoardAppearance.DEFAULT_OPACITY
            }
            return TodoBoardAppearance.clamped(stored)
        }
    }

    var appearance: TodoBoardAppearance = TodoBoardAppearance(restoredOpacity(kv.getString(DEFAULTS_KEY)))
        private set

    /** 값이 실제로 바뀌었을 때만(같은 값 재통지 0 — :386). Compose 쪽은 이것으로 상태를 갱신한다. */
    private val listeners = ArrayList<(TodoBoardAppearance) -> Unit>()

    fun addListener(listener: (TodoBoardAppearance) -> Unit): () -> Unit {
        listeners += listener
        return { listeners -= listener }
    }

    /** 사용자 조작(:436). NaN 은 통째로 무시(기본값 리셋 아님). */
    fun setOpacity(value: Double) {
        if (value.isNaN()) return
        val next = TodoBoardAppearance.clamped(value)
        if (next == appearance.opacity) return
        appearance = TodoBoardAppearance(next)
        kv.putString(DEFAULTS_KEY, next.toString())
        listeners.toList().forEach { it(appearance) }
    }

    /** 상대 조절(:450) — 유한하지 않은 델타는 버린다. */
    fun nudge(delta: Double) {
        if (!delta.isFinite()) return
        setOpacity(appearance.opacity + delta)
    }
}

/** 스크롤 한 개에서 판단에 필요한 넷(맥 TodoBoardScrollSample :76). [deltaY] 는 pt, 부호는 문서 방향. */
data class TodoBoardScrollSample(val deltaY: Double, val isPrecise: Boolean, val isInverted: Boolean = false, val isMomentum: Boolean = false) {
    companion object {
        /**
         * Windows 휠 한 이벤트 → 표본. AWT/Compose 의 회전 값은 **아래(사용자 쪽)가 양수**, 걸림쇠 한 칸 = 1.0.
         * 정수면 걸림쇠 휠(이산 — 한 이벤트 = 한 스텝), 소수면 정밀 터치패드(누적). 문서 방향(아래로 = 내용이 위로)은 회전과 반대라
         * deltaY = −회전 × [PT_PER_NOTCH]. Windows 는 장치별 '자연스러운 스크롤' 뒤집기를 앱에 알리지 않는다(isInverted=false).
         */
        fun fromWheelRotation(rotation: Double): TodoBoardScrollSample =
            TodoBoardScrollSample(deltaY = -rotation * PT_PER_NOTCH, isPrecise = rotation.isFinite() && rotation != rotation.roundToLong().toDouble())

        /** 정밀 터치패드 한 칸(회전 1.0)의 거리(pt) — 한 번 쓸기(맥 240pt)가 약 6칸. VM 손 판정 대상. */
        const val PT_PER_NOTCH = 40.0
    }
}

/** ⌥(Windows: Alt)+스크롤 누적기(맥 TodoBoardScrollOpacityGesture :105) — 창도 이벤트도 모르는 순수 값 로직. */
class TodoBoardScrollOpacityGesture {
    companion object {
        const val SWEEP_DISTANCE = 240.0
        val RAIL_STEPS: Double get() = (TodoBoardAppearance.MAX_OPACITY - TodoBoardAppearance.MIN_OPACITY) / TodoBoardAppearance.STEP
        /** 한 스텝 거리 = 한 번 쓸기가 레일 절반(:121). 바닥 8pt. */
        val STEP_DISTANCE: Double get() = max(8.0, SWEEP_DISTANCE / (RAIL_STEPS / 2))
        /** 한 이벤트 최대 스텝(:128) — Int 변환 붕괴 방어. Swift `.rounded()` = 0.5 는 먼 쪽. */
        val MAX_STEPS_PER_EVENT: Double get() = max(4.0, kotlin.math.floor(RAIL_STEPS / 2 + 0.5))

        /**
         * 이 조합이 진하기 조절인가(맥 :741 ⌥ 만, ⌘·⌃·⇧ 섞이면 물러남). Windows: Alt 만 — Ctrl(확대)·Shift(가로 스크롤)·Win 이 섞이면 물러난다.
         * CapsLock·NumLock 은 무시.
         */
        fun adjustsOpacity(alt: Boolean, ctrl: Boolean, shift: Boolean, meta: Boolean): Boolean = alt && !ctrl && !shift && !meta
    }

    private var accumulated = 0.0

    /** 보드를 열고 닫을 때 잔여를 턴다(:136). */
    fun reset() { accumulated = 0.0 }

    /** 이벤트 하나 → 이번에 적용할 스텝 수(양수 = 더 진하게, 물리적 위쪽 — :160). */
    fun steps(sample: TodoBoardScrollSample): Int {
        if (sample.isMomentum) { accumulated = 0.0; return 0 }
        if (!sample.deltaY.isFinite() || sample.deltaY == 0.0) return 0
        val up = if (sample.isInverted) -sample.deltaY else sample.deltaY
        if (!sample.isPrecise) { accumulated = 0.0; return if (up > 0) 1 else -1 }
        if (accumulated != 0.0 && (up > 0) != (accumulated > 0)) accumulated = 0.0
        accumulated += up
        val q = accumulated / STEP_DISTANCE
        val raw = if (q >= 0) kotlin.math.floor(q) else -kotlin.math.floor(-q)
        val bounded = min(max(raw, -MAX_STEPS_PER_EVENT), MAX_STEPS_PER_EVENT)
        if (bounded == raw) accumulated -= bounded * STEP_DISTANCE else accumulated = 0.0
        return bounded.toInt()
    }
}
