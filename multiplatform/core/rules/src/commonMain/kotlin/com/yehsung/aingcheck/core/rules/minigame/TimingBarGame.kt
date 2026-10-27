// 원본: Sources/CheckCore/TimingBarGame.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.minigame

import kotlin.math.abs
import kotlin.math.floor

/**
 * 타이밍 바 규칙(10라운드). 동일성 등급 **비트**(C§5.1 E5 — 골든 `timing-bar/rules` · `timing-bar/scripted`).
 * 판정 색·글리프는 그림의 것이라 옮기지 않는다(등급 [Verdict] 와 라벨만 — 접근성 글자는 규칙과 한 벌).
 * Swift 는 값 타입이다. Kotlin 은 참조라 복제가 필요하면 [copy] 를 부른다.
 */
class TimingBarGame private constructor(
    private var rng: MiniGameRandom,
    phase: Phase,
    roundScores: MutableList<Int>,
    private var targetCenter: Double,
    private var targetWidthValue: Double,
    private var stoppedPosition: Double?,
    lastHit: Boolean?,
) {
    sealed interface Phase {
        data object Ready : Phase
        /** 라운드 진행 중. [t] 는 라운드 시작부터 흐른 초. */
        data class Running(val round: Int, val t: Double) : Phase
        /** 정지 직후 결과 표시. [hold] 가 0 이 되면 다음 라운드(또는 끝)로. */
        data class RoundResult(val round: Int, val score: Int, val hold: Double) : Phase
        /** 10라운드 끝. */
        data class Finished(val total: Int) : Phase
    }

    /** 정지 순간의 판정 등급 — 점수에서만 나오는 순수 함수. 라벨은 색 없이도 결과를 말한다. */
    enum class Verdict(val label: String) {
        perfect("완벽!"), great("훌륭!"), good("좋아"), close("아슬"), miss("빗나감"),
    }

    var phase: Phase = phase
        private set
    private val scores: MutableList<Int> = roundScores
    val roundScores: List<Int> get() = scores.toList()
    /** 마지막 정지가 목표 안이었는지. 시작 전·무효 뒤엔 null. */
    var lastHit: Boolean? = lastHit
        private set

    constructor(seed: ULong) : this(MiniGameRandom(seed), Phase.Ready, mutableListOf(), 0.5, 0.30, null, null)

    fun copy(): TimingBarGame =
        TimingBarGame(rng.copy(), phase, scores.toMutableList(), targetCenter, targetWidthValue, stoppedPosition, lastHit)

    /** Swift `==`: 난수 상태는 비교하지 않는다. */
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is TimingBarGame) return false
        return phase == other.phase && scores == other.scores && targetCenter == other.targetCenter &&
            targetWidthValue == other.targetWidthValue && stoppedPosition == other.stoppedPosition && lastHit == other.lastHit
    }

    override fun hashCode(): Int = phase.hashCode() * 31 + scores.hashCode()

    // MARK: 읽기

    /** 현재(또는 마지막) 라운드 번호. 시작 전 0. */
    val round: Int
        get() = when (val p = phase) {
            Phase.Ready -> 0
            is Phase.Running -> p.round
            is Phase.RoundResult -> p.round
            is Phase.Finished -> roundCount
        }

    val total: Int get() = scores.sum()

    /** 연속 명중(70점 이상) 횟수 — **표시 전용**(총점에 더하지 않는다: 서버 상한 1000 · 순위 의미). */
    val combo: Int
        get() {
            var streak = 0
            for (score in scores.asReversed()) {
                if (score < 70) break
                streak += 1
            }
            return streak
        }

    val isPlaying: Boolean get() = phase is Phase.Running || phase is Phase.RoundResult

    /** 트랙 위 마커 위치 0…1. 결과 표시 중엔 정지한 자리에 얼어 있다. */
    val markerPosition: Double
        get() = when (val p = phase) {
            is Phase.Running -> markerPosition(p.t, period(p.round))
            is Phase.RoundResult -> stoppedPosition ?: 0.0
            Phase.Ready, is Phase.Finished -> 0.0
        }

    val target: Pair<Double, Double> get() = targetCenter to targetWidthValue

    // MARK: 전이

    fun step(dt: Double) {
        val d = swiftMin(swiftMax(dt, 0.0), maxStep)
        when (val p = phase) {
            is Phase.Running -> phase = Phase.Running(p.round, p.t + d)
            is Phase.RoundResult -> {
                val remaining = p.hold - d
                if (remaining > 0) {
                    phase = Phase.RoundResult(p.round, p.score, remaining)
                } else if (p.round >= roundCount) {
                    phase = Phase.Finished(total)
                } else {
                    startRound(p.round + 1)
                }
            }
            Phase.Ready, is Phase.Finished -> Unit
        }
    }

    /** 클릭. 시작 전/끝난 뒤엔 새 판, 진행 중엔 정지, 결과 표시 중엔 무시. */
    fun tap() {
        when (val p = phase) {
            Phase.Ready, is Phase.Finished -> {
                scores.clear()
                lastHit = null
                stoppedPosition = null
                startRound(1)
            }
            is Phase.Running -> {
                val pos = markerPosition(p.t, period(p.round))
                val distance = abs(pos - targetCenter) / (targetWidthValue / 2)
                val score = roundScore(distance)
                scores.add(score)
                lastHit = distance <= 1
                stoppedPosition = pos
                phase = Phase.RoundResult(p.round, score, resultHold)
            }
            is Phase.RoundResult -> Unit
        }
    }

    /** 판 무효(창 닫힘·패널 전환). 점수는 버리고 시작 전으로. */
    fun invalidate() {
        phase = Phase.Ready
        scores.clear()
        lastHit = null
        stoppedPosition = null
    }

    private fun startRound(round: Int) {
        val width = targetWidth(round)
        targetWidthValue = width
        targetCenter = rng.uniform(width / 2 + 0.05, 1 - width / 2 - 0.05)
        stoppedPosition = null
        phase = Phase.Running(round, 0.0)
    }

    companion object {
        const val roundCount: Int = 10
        const val resultHold: Double = 0.6
        const val maxStep: Double = 1.0 / 30.0

        /** 라운드 주기(초). 0.42 밑으로는 안 내려간다. */
        fun period(round: Int): Double = swiftMax(0.42, 1.10 - 0.075 * (round - 1).toDouble())

        /** 목표 구간 폭(트랙 = 1). 0.07 밑으로는 안 내려간다. */
        fun targetWidth(round: Int): Double = swiftMax(0.07, 0.24 - 0.019 * (round - 1).toDouble())

        /** 삼각파 0→1→0(해석식 — 과거·미래 시각도 계산된다). Swift `(x + 0.5).rounded(.down)` = floor. */
        fun markerPosition(t: Double, period: Double): Double {
            val x = t / period
            return 2 * abs(x - floor(x + 0.5))
        }

        /** 목표 중심 거리 d 를 점수로: 안이면 100 → 70(정확도 비례, Swift `.rounded()`), 밖이면 0. */
        fun roundScore(distance: Double): Int {
            if (!(distance <= 1)) return 0
            return 100 - (30 * distance).roundedHalfAwayFromZero().toInt()
        }

        /** 점수 → 판정 등급(100 / 90 / 80 / 70). */
        fun verdict(score: Int): Verdict = when {
            score >= 100 -> Verdict.perfect
            score >= 90 -> Verdict.great
            score >= 80 -> Verdict.good
            score >= 70 -> Verdict.close
            else -> Verdict.miss
        }
    }
}
