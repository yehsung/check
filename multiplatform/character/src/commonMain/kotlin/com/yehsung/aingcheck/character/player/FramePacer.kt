// 원본: 없음 (설계 F §5.4 프레임 정책 — 맥 `CheckOverlayReactions` 의 유휴 6 · 활성 30fps 를 vsync 정수배로. 미니게임 `MiniGameFrameRate` 와는 다른 규칙이다)
package com.yehsung.aingcheck.character.player

import com.yehsung.aingcheck.character.math.Vec2
import kotlin.math.abs
import kotlin.math.hypot

/**
 * 프레임 정책(F §5.4). 목표는 맥과 같다: 유휴 6fps · 활성 30fps. **간격은 vsync 정수배**로 고른다 —
 * n = argmin |주사율/n − 목표| (동점이면 작은 n). 60Hz 상한 × 비배수 주사율에서 생기던 저더를 피한다(기억 game-frame-rate-judder).
 */
object FramePacer {
    /** 주사율 Hz · 목표 fps → vsync 몇 번마다 한 프레임인가(≥ 1). */
    fun vsyncInterval(refreshHz: Double, targetFps: Double): Int {
        require(refreshHz > 0 && targetFps > 0) { "주사율 · 목표는 양수" }
        var best = 1
        var bestError = Double.MAX_VALUE
        val maxN = (refreshHz / targetFps * 2).toInt().coerceAtLeast(1) + 1
        for (n in 1..maxN) {
            val err = abs(refreshHz / n - targetFps)
            if (err < bestError - 1e-12) { bestError = err; best = n }
        }
        return best
    }

    fun effectiveFps(refreshHz: Double, targetFps: Double): Double = refreshHz / vsyncInterval(refreshHz, targetFps)

    /**
     * 활성인가(30fps) — 리액션 재생 중과 그 뒤 [resetAfterS](0.1s), 깜빡임, 걷기(F §1.3 fps 정책).
     * @param reactionEndsAt 마지막 리액션 모션이 끝나는 장면 시각(없으면 null).
     */
    fun isActive(now: Double, reactionEndsAt: Double?, resetAfterS: Double, blinking: Boolean, walking: Boolean): Boolean =
        blinking || walking || (reactionEndsAt != null && now < reactionEndsAt + resetAfterS)

    /**
     * 다시 그릴 필요가 있는가: 칸 · 그림이 같고 네 꼭짓점이 모두 [thresholdPx](0.25px) 안에서만 움직였으면 그리지 않는다(F §5.4).
     */
    fun needsRedraw(previousKey: String?, previousQuad: List<Vec2>?, key: String, quad: List<Vec2>, thresholdPx: Double = 0.25): Boolean {
        if (previousKey != key || previousQuad == null || previousQuad.size != quad.size) return true
        return previousQuad.indices.any { hypot(previousQuad[it].x - quad[it].x, previousQuad[it].y - quad[it].y) >= thresholdPx }
    }
}
