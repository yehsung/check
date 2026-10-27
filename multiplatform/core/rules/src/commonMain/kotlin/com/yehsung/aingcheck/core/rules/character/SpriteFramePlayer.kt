// 원본: Sources/CheckCore/CharacterKit/SpriteFramePlayer.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.character

/**
 * 한 상태의 프레임 재생 시계 — **순수 함수**(호출부가 elapsed 를 준다). 프레임 끝 시각은 **정수 ms 로 누적**하고 마지막에 나눈다
 * (0.1 을 실수로 더해 가면 경계가 0.30000000000000004 가 된다).
 */
class SpriteFramePlayer(state: CharacterManifest.State) {
    private val frameEnds: DoubleArray
    private val frameCount: Int = state.frames.size
    private val loops: Boolean = state.loop

    /** 한 바퀴 길이(초). */
    val totalDuration: Double

    init {
        var accumulatedMs = 0L
        frameEnds = DoubleArray(state.frames.size) { index ->
            val ms = if (index < state.durationsMs.size) maxOf(0L, state.durationsMs[index]) else 0L
            accumulatedMs += ms
            accumulatedMs.toDouble() / 1000
        }
        totalDuration = accumulatedMs.toDouble() / 1000
    }

    /** 반열린 구간 [시작, 끝) — 경계면 다음 프레임. 루프면 접고, 아니면 마지막에서 멈춘다. 음수 · 무한 · NaN → 0. */
    fun frameIndex(elapsed: Double): Int {
        if (frameCount <= 0) return 0
        val last = frameCount - 1
        if (!(totalDuration > 0)) return 0
        if (!elapsed.isFinite()) return 0
        if (!(elapsed > 0)) return 0
        var t = elapsed
        if (loops) {
            t %= totalDuration   // Swift truncatingRemainder 와 같다(IEEE fmod)
            if (t < 0) t += totalDuration
        } else if (t >= totalDuration) {
            return last
        }
        for (index in 0..last) if (t < frameEnds[index]) return index
        return last
    }
}
