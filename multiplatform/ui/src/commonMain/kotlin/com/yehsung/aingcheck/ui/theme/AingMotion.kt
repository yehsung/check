// 원본: 없음 — 이식 규칙(기억 easing-must-not-drive-opacity · 체스 잡힘 모션 실측). 맥·iOS 의 개별 애니메이션 값은 화면 갈래가 옮긴다.
//
// 움직임 토큰. 규칙 하나가 이 파일의 이유다(기억 easing-must-not-drive-opacity, 2026-10-06 체스 잡힘 모션 실측):
//
//   **위치·크기만 이징하고, 불투명도는 날 진행도(선형)로 깎는다.**
//
// 움직임과 흐려짐을 같은 easeOut 으로 깎으면 두 채널이 같은 시각에 끝나 "밀려나기 전에 사라진다"(easeOutCubic 은 이동의 87.5% 를
// 앞 절반에 몰아넣는다 — 진행도 0.5 에서 불투명도가 이미 0.19). 그래서 흐려짐 사양은 [fade] 하나뿐이고 이징 인자를 받지 않는다.
// ui 모듈 main 에서 fadeIn·fadeOut·Crossfade 는 [fade] 를 써야 한다(`AingMotionStructureTest` 가 소스로 잰다).
package com.yehsung.aingcheck.ui.theme

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween

object AingMotion {
    /** easeOutCubic `1-(1-t)³` — 위치·크기 전용. */
    val moveEasing: Easing = Easing { t -> 1f - (1f - t) * (1f - t) * (1f - t) }

    /** 표준 이동(시트·카드 들어오기). */
    val standardEasing: Easing = CubicBezierEasing(0.2f, 0f, 0f, 1f)

    const val SHORT_MS = 150
    const val MEDIUM_MS = 250
    const val LONG_MS = 400

    /** 위치·크기 애니메이션 사양(이징 있음). */
    fun <T> move(durationMillis: Int = MEDIUM_MS, delayMillis: Int = 0, easing: Easing = moveEasing): FiniteAnimationSpec<T> =
        tween(durationMillis, delayMillis, easing)

    /** 불투명도 애니메이션 사양 — **언제나 선형**. 이징 인자가 없는 것이 계약이다. */
    fun <T> fade(durationMillis: Int = MEDIUM_MS, delayMillis: Int = 0): FiniteAnimationSpec<T> =
        tween(durationMillis, delayMillis, LinearEasing)

    /**
     * 손으로 그리는 흐려짐(진행도 → 불투명도): 날 진행도 [progress] 가 [holdUntil] 을 지날 때부터 선형으로 0 까지.
     * 체스 수리식 `min(1, (1-k)/(1-0.35))` 과 같은 모양 — `holdUntil = 0.35` 면 앞 35% 는 그대로 보인다.
     */
    fun fadeOutOpacity(progress: Float, holdUntil: Float = 0f): Float {
        val k = progress.coerceIn(0f, 1f)
        if (holdUntil >= 1f) return if (k < 1f) 1f else 0f
        return ((1f - k) / (1f - holdUntil)).coerceIn(0f, 1f)
    }

    /** 이동 진행도(이징 적용). 불투명도에 넣지 않는다. */
    fun moveProgress(progress: Float): Float = moveEasing.transform(progress.coerceIn(0f, 1f))
}
