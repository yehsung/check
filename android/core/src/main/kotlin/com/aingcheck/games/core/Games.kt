package com.aingcheck.games.core

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

enum class GameKind(val wire: String, val title: String, val maxScore: Int) {
    TIMING("timing_bar", "타이밍 바", 1000),
    FLAPPY("flappy", "플래피 아잉", 999)
}

/** SplitMix64; overflow and unsigned shifts deliberately match MiniGameRandom. */
class GameRandom(private var state: Long) {
    fun next(): Long {
        state += 0x9E3779B97F4A7C15uL.toLong()
        var z = state
        z = (z xor (z ushr 30)) * 0xBF58476D1CE4E5B9uL.toLong()
        z = (z xor (z ushr 27)) * 0x94D049BB133111EBuL.toLong()
        return z xor (z ushr 31)
    }
    fun unit(): Double = (next() ushr 11).toDouble() / 9007199254740992.0
    fun uniform(low: Double, high: Double) = low + (high - low) * unit()
}

interface Game {
    val score: Int
    val playing: Boolean
    val finished: Boolean
    fun tap()
    fun step(seconds: Double)
}

private fun stepSize(seconds: Double) = if (seconds.isFinite()) seconds.coerceIn(0.0, 1.0 / 30) else 0.0

class TimingGame(seed: Long) : Game {
    enum class Phase { READY, RUNNING, HOLD, FINISHED }
    private val rng = GameRandom(seed)
    var phase = Phase.READY; private set
    var round = 0; private set
    private var time = 0.0
    private var hold = 0.0
    private var stopped = 0.0
    private val results = mutableListOf<Int>()
    val scores: List<Int> get() = results.toList()
    var targetCenter = 0.5; private set
    var targetWidth = 0.30; private set
    override val score get() = results.sum()
    override val playing get() = phase == Phase.RUNNING || phase == Phase.HOLD
    override val finished get() = phase == Phase.FINISHED
    val marker get() = if (phase == Phase.RUNNING) position(time, period(round)) else stopped
    val lastScore get() = results.lastOrNull()

    override fun tap() {
        when (phase) {
            Phase.READY, Phase.FINISHED -> { results.clear(); startRound(1) }
            Phase.RUNNING -> {
                stopped = marker
                results += scoreAt(abs(stopped - targetCenter) / (targetWidth / 2))
                hold = 0.6
                phase = Phase.HOLD
            }
            Phase.HOLD -> Unit
        }
    }
    override fun step(seconds: Double) {
        val dt = stepSize(seconds)
        when (phase) {
            Phase.RUNNING -> time += dt
            Phase.HOLD -> {
                hold -= dt
                if (hold <= 0) {
                    if (round == 10) phase = Phase.FINISHED else startRound(round + 1)
                }
            }
            else -> Unit
        }
    }
    private fun startRound(number: Int) {
        round = number
        time = 0.0
        stopped = 0.0
        targetWidth = width(number)
        targetCenter = rng.uniform(targetWidth / 2 + 0.05, 1 - targetWidth / 2 - 0.05)
        phase = Phase.RUNNING
    }
    companion object {
        fun period(round: Int) = max(0.42, 1.10 - 0.075 * (round - 1))
        fun width(round: Int) = max(0.07, 0.24 - 0.019 * (round - 1))
        fun position(time: Double, period: Double): Double {
            val x = time / period
            return 2 * abs(x - floor(x + 0.5))
        }
        fun scoreAt(distance: Double) = if (distance <= 1) 100 - (30 * distance).roundToInt() else 0
    }
}

class FlappyGame(seed: Long) : Game {
    enum class Phase { READY, RUNNING, OVER, RESULT }
    data class Pipe(
        var x: Double, val center: Double, val gap: Double,
        var passed: Boolean = false, val shiftDelay: Double? = null,
        val shiftOffset: Double = 0.0, var shiftAt: Double? = null
    ) {
        fun centerAt(time: Double): Double {
            val at = shiftAt ?: return center
            val progress = ((time - at) / 0.12).coerceIn(0.0, 1.0)
            return (center + shiftOffset * (1 - (1 - progress).pow(3))).coerceIn(gap / 2, HEIGHT - gap / 2)
        }
    }
    private val rng = GameRandom(seed)
    var phase = Phase.READY; private set
    var birdY = HEIGHT / 2; private set
    var velocity = 0.0; private set
    var elapsed = 0.0; private set
    var scrolled = 0.0; private set
    private var hold = 0.0
    private val obstacles = mutableListOf<Pipe>()
    val pipes: List<Pipe> get() = obstacles
    override var score = 0; private set
    override val playing get() = phase == Phase.RUNNING || phase == Phase.OVER
    override val finished get() = phase == Phase.RESULT
    override fun tap() {
        when (phase) {
            Phase.READY, Phase.RESULT -> {
                birdY = HEIGHT / 2; velocity = -317.0; score = 0; elapsed = 0.0; scrolled = 0.0
                obstacles.clear()
                repeat(3) { obstacles += makePipe(WIDTH + 80 + it * spacing(0)) }
                phase = Phase.RUNNING
            }
            Phase.RUNNING -> velocity = -317.0
            Phase.OVER -> Unit
        }
    }
    override fun step(seconds: Double) {
        val dt = stepSize(seconds)
        if (phase == Phase.OVER) {
            hold -= dt
            if (hold <= 0) phase = Phase.RESULT
            return
        }
        if (phase != Phase.RUNNING) return
        elapsed += dt
        velocity = min(velocity + 1360 * dt, 574.0)
        birdY += velocity * dt
        if (birdY - 12 < 0) { birdY = 12.0; velocity = 0.0 }
        val movement = speed(score) * dt
        scrolled += movement
        obstacles.forEach {
            it.x -= movement
            if (it.shiftDelay != null && it.shiftAt == null && it.x <= WIDTH) it.shiftAt = elapsed + it.shiftDelay
            if (!it.passed && BIRD_X > it.x + 44) { it.passed = true; score++ }
        }
        if (score >= 999) { score = 999; phase = Phase.RESULT; return }
        while (obstacles.isNotEmpty() && obstacles.first().x + 44 < 0) {
            obstacles.removeAt(0)
            obstacles += makePipe((obstacles.lastOrNull()?.x ?: (WIDTH + 80 - spacing(score))) + spacing(score))
        }
        if (birdY + 12 >= HEIGHT || obstacles.any {
                // CGRect.intersects requires positive overlap, not just a shared edge.
                BIRD_X + 12 > it.x && BIRD_X - 12 < it.x + 44 &&
                    (birdY - 12 < it.centerAt(elapsed) - it.gap / 2 || birdY + 12 > it.centerAt(elapsed) + it.gap / 2)
            }) {
            phase = Phase.OVER; hold = 0.4
        }
    }
    private fun makePipe(x: Double): Pipe {
        val gap = gap(score)
        val low = gap / 2 + 36; val high = HEIGHT - gap / 2 - 36
        val center = rng.uniform(low, high)
        if (score < 15 || rng.unit() >= 0.30) return Pipe(x, center, gap)
        val delay = rng.uniform(0.45, 1.10)
        val down = rng.unit() < 0.5
        val canDown = center + 58 <= high; val canUp = center - 58 >= low
        val offset = when {
            down && canDown || !down && canDown && !canUp -> 58.0
            !down && canUp || down && !canDown && canUp -> -58.0
            else -> return Pipe(x, center, gap)
        }
        return Pipe(x, center, gap, shiftDelay = delay, shiftOffset = offset)
    }
    companion object {
        const val WIDTH = 292.0
        const val HEIGHT = 302.0
        const val BIRD_X = 0.28 * WIDTH
        fun gap(score: Int) = max(96.0, 132.0 - 3 * max(0, score))
        fun speed(score: Int) = min(230.0, 130.0 + 3 * max(0, score))
        fun spacing(score: Int) = max(115.0, 150.0 - 2 * max(0, score))
    }
}
