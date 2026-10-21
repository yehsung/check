// 원본: 없음(새 코드) — 설계 D§13-4(Win32 API 는 물리 픽셀, AWT/Compose 는 배율을 나눈 논리 좌표 — **좌표 변환은 한 함수에만**)
// 플라이아웃·오버레이·울트라가 모두 이 함수를 쓴다. 반올림은 한 규칙(반 올림, floor(v + 0.5))으로만 한다 —
// 두 곳이 다른 반올림을 쓰면 150%·175% 에서 1px 씩 어긋난 창이 생긴다.
package com.yehsung.aingcheck.desktop.platform.windows.flyout

import kotlin.math.floor

object ScreenSpace {
    const val BASE_DPI = 96

    fun scaleForDpi(dpi: Int): Double {
        require(dpi > 0) { "DPI $dpi" }
        return dpi.toDouble() / BASE_DPI
    }

    fun scaleForPercent(percent: Int): Double {
        require(percent > 0) { "배율 $percent%" }
        return percent / 100.0
    }

    /** DIP(논리) 길이 → 물리 픽셀. */
    fun dipToPx(dip: Double, scale: Double): Int = floor(dip * scale + 0.5).toInt()

    /** 물리 픽셀 → DIP(논리). 되돌릴 때 [dipToPx] 와 짝이 맞는다(정수 DIP 는 왕복이 같다 — 시험). */
    fun pxToDip(px: Int, scale: Double): Double = px / scale

    /** 모니터 원점 기준 논리 좌표 → 화면 물리 좌표(음수 좌표 모니터 포함). */
    fun dipPointToScreenPx(monitorOriginPx: Int, dipOffset: Double, scale: Double): Int = monitorOriginPx + dipToPx(dipOffset, scale)
}
