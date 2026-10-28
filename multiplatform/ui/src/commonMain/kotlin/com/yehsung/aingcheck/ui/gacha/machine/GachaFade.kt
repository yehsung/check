// 원본: 없음 — 이식 규칙(기억 easing-must-not-drive-opacity · G §2-3 W4-c ④ "불투명도에 이징을 쓰지 않는다").
//
// 기계·상점·미션 화면의 **불투명도는 전부 이 파일의 함수로만** 만든다. 여기 함수는 날 진행도(선형)뿐이다 — smoothstep · easeOut · 스프링 ·
// 지수 감쇠 · 거듭제곱 곡선을 불투명도에 걸지 않는다(움직임과 흐려짐을 같은 곡선으로 깎으면 "밀려나기 전에 사라진다").
//
// Swift 기계(GachaMachineView.swift)는 몇 자리에서 불투명도에 smooth · exp · pow 를 걸었다(무대 조명 · 어둠 · 섬광 · 빛 고리 · 안내 글자).
// 이식은 그 자리를 같은 구간의 **직선**으로 바꿨다(구간 끝점·최댓값은 원문 그대로). 위치·크기·회전·흐림 정도는 원문 곡선 그대로다.
// `GachaOpacityStructureTest` 가 소스로 잰다: 불투명도 자리(alpha · copy(alpha=) · graphicsLayer alpha …)의 식과 그 식이 부르는 지역 값에
// 이징 이름이 0 이어야 한다.
package com.yehsung.aingcheck.ui.gacha.machine

import kotlin.math.max
import kotlin.math.min

object GachaFade {
    private fun clamp01(x: Double): Double = min(1.0, max(0.0, x))

    /** a…b 에서 0 → 1 로 곧게. */
    fun rise(a: Double, b: Double, x: Double): Double = if (b <= a) (if (x >= a) 1.0 else 0.0) else clamp01((x - a) / (b - a))

    /** a…b 에서 1 → 0 으로 곧게. */
    fun fall(a: Double, b: Double, x: Double): Double = 1 - rise(a, b, x)

    /** 0 에서 [peak] 로 켜진 뒤 [length] 동안 곧게 0 까지(섬광 · 고리 — 원문 지수 감쇠의 자리). */
    fun decay(t: Double, length: Double, peak: Double = 1.0): Double = if (t < 0) 0.0 else peak * fall(0.0, length, t)

    /** a 에서 켜지기 시작해 [inLength] 동안 오르고, b 부터 [outLength] 동안 내린다. */
    fun window(x: Double, a: Double, inLength: Double, b: Double, outLength: Double): Double =
        rise(a, a + inLength, x) * fall(b, b + outLength, x)

    fun f(x: Double): Float = clamp01(x).toFloat()
}
