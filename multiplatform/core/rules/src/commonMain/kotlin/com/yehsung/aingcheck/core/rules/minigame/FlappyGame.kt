// 원본: Sources/CheckCore/FlappyGame.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.minigame

/**
 * 플래피 아잉 규칙. 시드만 주면 결정론적으로 같은 판이 나온다.
 *
 * 동일성 등급 **이산**(G §8-14 · C§5.1 E4): 움직이는 기둥의 easeOut `1 − pow(1 − p, 3)` 를 Kotlin 은 pow 없이 `(q·q)·q` 로 낸다 —
 * Darwin pow 와 ±1ulp 갈릴 수 있다(W0-b C-X1: 25.7%). 그 값(틈 중심 · `lastScorePipeCenter`)만 허용 오차로 대조하고, 정수·열거
 * 출력과 나머지 실수(새 · 기둥 x · 시계)는 골든 `flappy/scripted` 가 비트로 잰다. Swift 는 고치지 않는다(판단 — G §2-3 W1-a ④).
 *
 * Swift 는 값 타입이다. Kotlin 은 참조라 복제가 필요하면 [copy] 를 부른다.
 */
class FlappyGame private constructor(
    private var rng: MiniGameRandom,
    bird: Bird,
    pipes: List<Pipe>,
    score: Int,
    phase: Phase,
    flashRemaining: Double,
    elapsed: Double,
    scrolled: Double,
    lastFlapAt: Double?,
    flapCount: Int,
    lastScoreAt: Double?,
    lastScorePipeCenter: Double?,
) {
    data class Pipe(
        val x: Double,
        /** 틈 중심의 기준선. 움직이는 기둥이면 여기서 한 번 튄다. */
        val centerY: Double,
        val gap: Double,
        val passed: Boolean = false,
        /** 화면에 들어온 뒤 튀기까지의 지연(초). null 이면 고정 기둥. */
        val shiftDelay: Double? = null,
        /** 튀는 폭과 방향(+ 아래 · − 위). */
        val shiftOffset: Double = 0.0,
        /** 튀기 시작하는 판 시각(초) — 화면 오른쪽 끝에 들어올 때 한 번 채워진다. */
        val shiftAt: Double? = null,
    ) {
        val isShifting: Boolean get() = shiftDelay != null

        /**
         * 그 시각의 틈 중심. **충돌·그리기가 같은 이 함수를 쓴다.** 튀기 전에는 기준선, shiftAt 부터 0.12초 동안 easeOut 으로
         * shiftOffset 만큼 옮겨 간 뒤 머문다. easeOut 의 세제곱은 pow 대신 곱셈이다(이산 등급 — 클래스 머리 주석).
         */
        fun center(at: Double): Double {
            val start = shiftAt ?: return centerY
            val progress = swiftMin(swiftMax((at - start) / shiftDuration, 0.0), 1.0)
            val q = 1 - progress
            val eased = 1 - q * q * q
            val moved = centerY + shiftOffset * eased
            return swiftMin(swiftMax(moved, gap / 2), height - gap / 2)
        }

        /** 위 기둥 [0, center − gap/2]. */
        fun topRect(at: Double): MiniGameRect = MiniGameRect(x, 0.0, pipeWidth, swiftMax(0.0, center(at) - gap / 2))

        /** 아래 기둥 [center + gap/2, height]. */
        fun bottomRect(at: Double, height: Double): MiniGameRect {
            val top = center(at) + gap / 2
            return MiniGameRect(x, top, pipeWidth, swiftMax(0.0, height - top))
        }
    }

    data class Bird(val x: Double, val y: Double, val vy: Double)

    sealed interface Phase {
        /** 시작 전(루프 정지). 액션 = 새 판 + 첫 점프. */
        data object Ready : Phase
        data object Running : Phase
        /** 충돌 직후 유예. */
        data class Over(val hold: Double) : Phase
        data object Result : Phase
    }

    var bird: Bird = bird
        private set
    private var pipeList: MutableList<Pipe> = pipes.toMutableList()
    val pipes: List<Pipe> get() = pipeList.toList()
    var score: Int = score
        private set
    var phase: Phase = phase
        private set
    var flashRemaining: Double = flashRemaining
        private set
    /** 판 시계(초) — 움직이는 기둥의 틈 위치가 이 시계를 본다. */
    var elapsed: Double = elapsed
        private set

    // 그림 전용 상태. INV-FlappyGame-2cc5e60d 이식: v0.2.51 에서 지운 `trail`(잔상)·`stageChangedAt`(무대 전환 시각)은
    // Kotlin 에도 두지 않는다 — 그리지 않는 값을 매 프레임 갱신하면 지운 의미가 없다(되살리려면 사용자에게 다시 묻는다).
    /** 이번 판이 흘려보낸 가로 거리 — 배경 패럴랙스의 유일한 시계. */
    var scrolled: Double = scrolled
        private set
    var lastFlapAt: Double? = lastFlapAt
        private set
    var flapCount: Int = flapCount
        private set
    var lastScoreAt: Double? = lastScoreAt
        private set
    var lastScorePipeCenter: Double? = lastScorePipeCenter
        private set

    constructor(seed: ULong) : this(
        rng = MiniGameRandom(seed),
        bird = Bird(birdX, height / 2, 0.0),
        pipes = emptyList(),
        score = 0,
        phase = Phase.Ready,
        flashRemaining = 0.0,
        elapsed = 0.0,
        scrolled = 0.0,
        lastFlapAt = null,
        flapCount = 0,
        lastScoreAt = null,
        lastScorePipeCenter = null,
    )

    /** 픽스처 — 임의 상태에서 시작한다(난수는 seed). */
    constructor(
        seed: ULong,
        bird: Bird,
        pipes: List<Pipe>,
        score: Int,
        phase: Phase,
        elapsed: Double = 0.0,
        scrolled: Double = 0.0,
        lastFlapAt: Double? = null,
        flapCount: Int = 0,
        lastScoreAt: Double? = null,
        lastScorePipeCenter: Double? = null,
    ) : this(
        MiniGameRandom(seed), bird, pipes, score, phase, 0.0, elapsed, scrolled, lastFlapAt, flapCount,
        lastScoreAt, lastScorePipeCenter,
    )

    fun copy(): FlappyGame = FlappyGame(
        rng.copy(), bird, pipeList, score, phase, flashRemaining, elapsed, scrolled, lastFlapAt, flapCount,
        lastScoreAt, lastScorePipeCenter,
    )

    /** Swift `==`: 난수 상태는 비교하지 않는다. */
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is FlappyGame) return false
        return bird == other.bird && pipeList == other.pipeList && score == other.score && phase == other.phase &&
            flashRemaining == other.flashRemaining && elapsed == other.elapsed && scrolled == other.scrolled &&
            lastFlapAt == other.lastFlapAt && flapCount == other.flapCount && lastScoreAt == other.lastScoreAt &&
            lastScorePipeCenter == other.lastScorePipeCenter
    }

    override fun hashCode(): Int = bird.hashCode() * 31 + score

    /** 지금 점수의 무대(팔레트 — 규칙은 안 본다). */
    val stage: MiniGameStage get() = MiniGameStage.forFlappyScore(score)

    val isPlaying: Boolean get() = phase == Phase.Running || phase is Phase.Over

    val isGameOver: Boolean get() = phase is Phase.Over || phase == Phase.Result

    val hitbox: MiniGameRect
        get() = MiniGameRect(bird.x - hitboxSize / 2, bird.y - hitboxSize / 2, hitboxSize, hitboxSize)

    // MARK: 전이

    /** 액션. ready/result 면 새 판 + 첫 점프, running 이면 점프, over 유예 중엔 무시. */
    fun flap() {
        when (phase) {
            Phase.Ready, Phase.Result -> {
                startRound()
                bird = bird.copy(vy = flapVelocity)
            }
            Phase.Running -> bird = bird.copy(vy = flapVelocity)
            is Phase.Over -> return
        }
        lastFlapAt = elapsed
        flapCount += 1
    }

    /** 허브가 판을 끊을 때. 진행 중이면 그 점수로 결과 확정. 포커스 상실은 여기로 안 온다(v0.3.62). */
    fun interrupt() {
        when (phase) {
            Phase.Running, is Phase.Over -> {
                phase = Phase.Result
                flashRemaining = 0.0
            }
            Phase.Ready, Phase.Result -> Unit
        }
    }

    fun step(dt: Double) {
        val d = swiftMin(swiftMax(0.0, dt), maxStep)
        when (val p = phase) {
            Phase.Ready, Phase.Result -> return
            is Phase.Over -> {
                flashRemaining = swiftMax(0.0, flashRemaining - d)
                val left = p.hold - d
                phase = if (left <= 0) Phase.Result else Phase.Over(left)
                return
            }
            Phase.Running -> Unit
        }

        elapsed += d

        var vy = nextVelocity(bird.vy, d)
        var y = bird.y + vy * d
        if (y - hitboxSize / 2 < 0) {
            y = hitboxSize / 2
            vy = 0.0
        }
        bird = bird.copy(y = y, vy = vy)

        val speed = speed(forScore = score)
        scrolled += speed * d
        for (i in pipeList.indices) {
            var pipe = pipeList[i].let { it.copy(x = it.x - speed * d) }
            val delay = pipe.shiftDelay
            if (delay != null && pipe.shiftAt == null && pipe.x <= width) {
                pipe = pipe.copy(shiftAt = elapsed + delay)
            }
            if (!pipe.passed && bird.x > pipe.x + pipeWidth) {
                pipe = pipe.copy(passed = true)
                score += 1
                lastScoreAt = elapsed
                lastScorePipeCenter = pipe.center(elapsed)
            }
            pipeList[i] = pipe
        }
        if (score >= maxScore) {
            score = maxScore
            phase = Phase.Result
            return
        }

        while (pipeList.isNotEmpty() && pipeList[0].x + pipeWidth < 0) {
            pipeList.removeAt(0)
            val gapToNext = spacing(forScore = score)
            val lastX = pipeList.lastOrNull()?.x ?: (firstPipeX - gapToNext)
            pipeList.add(makePipe(lastX + gapToNext, score, rng))
        }

        val box = hitbox
        if (box.maxY >= height || pipeList.any { collides(box, it, height, elapsed) }) {
            phase = Phase.Over(overHold)
            flashRemaining = flashDuration
        }
    }

    private fun startRound() {
        bird = Bird(birdX, height / 2, 0.0)
        score = 0
        flashRemaining = 0.0
        elapsed = 0.0
        scrolled = 0.0
        lastFlapAt = null
        flapCount = 0
        lastScoreAt = null
        lastScorePipeCenter = null
        val gapToNext = spacing(forScore = 0)
        pipeList = MutableList(pipeCount) { i -> makePipe(firstPipeX + i.toDouble() * gapToNext, 0, rng) }
        phase = Phase.Running
    }

    companion object {
        const val width: Double = MiniGameCanvas.logicalWidth
        const val height: Double = MiniGameCanvas.logicalHeight
        val logicalSize: MiniGameSize get() = MiniGameSize(width, height)
        const val birdX: Double = 0.28 * width
        const val hitboxSize: Double = 24.0
        const val spriteSize: Double = 34.0
        const val gravity: Double = 1360.0
        const val flapVelocity: Double = -317.0
        const val maxFallSpeed: Double = 574.0
        const val pipeWidth: Double = 44.0
        const val firstPipeX: Double = width + 80
        const val pipeCount: Int = 3
        val maxScore: Int get() = MiniGameKind.flappy.maxScore
        const val centerMargin: Double = 36.0
        const val overHold: Double = 0.4
        const val flashDuration: Double = 0.15
        const val maxStep: Double = 1.0 / 30.0

        const val shiftMinScore: Int = 15
        const val shiftChance: Double = 0.30
        const val shiftJump: Double = 58.0
        const val shiftDelayMin: Double = 0.45
        const val shiftDelayMax: Double = 1.10
        const val shiftDuration: Double = 0.12

        /** 틈 높이: 132 에서 점수당 3 줄고 96 에서 멈춘다. */
        fun gap(forScore: Int): Double = swiftMax(96.0, 132.0 - (3 * maxOf(0, forScore)).toDouble())

        /** 스크롤 속도(pt/s): 130 에서 점수당 3, 230 에서 멈춘다. */
        fun speed(forScore: Int): Double = swiftMin(230.0, 130.0 + (3 * maxOf(0, forScore)).toDouble())

        /** 기둥 사이 수평 간격: 150 에서 점수당 2 좁아지고 115 에서 멈춘다. */
        fun spacing(forScore: Int): Double = swiftMax(115.0, 150.0 - (2 * maxOf(0, forScore)).toDouble())

        /** 중력 적분 뒤 속도(최대 낙하 574 클램프). */
        fun nextVelocity(vy: Double, dt: Double): Double = swiftMin(vy + gravity * dt, maxFallSpeed)

        /** AABB — 히트박스가 그 시각의 위 또는 아래 기둥과 겹치면 충돌. */
        fun collides(bird: MiniGameRect, pipe: Pipe, height: Double, time: Double): Boolean =
            bird.intersects(pipe.topRect(time)) || bird.intersects(pipe.bottomRect(time, height))

        /**
         * 새 기둥. 난수 소비 순서(기준선 → 판정 → 지연 → 방향)는 결정론의 일부다. 15점 미만은 판정 난수를 쓰지 않는다(단락 평가).
         * 방향은 여백 안에 들어가는 쪽으로만, 양쪽 다 안 되면 고정 기둥으로 강등한다.
         */
        fun makePipe(x: Double, score: Int, rng: MiniGameRandom): Pipe {
            val gap = gap(forScore = score)
            val lo = gap / 2 + centerMargin
            val hi = height - gap / 2 - centerMargin
            val center = rng.uniform(lo, hi)
            if (!(score >= shiftMinScore && rng.unit() < shiftChance)) return Pipe(x, center, gap)
            val delay = rng.uniform(shiftDelayMin, shiftDelayMax)
            val wantsDown = rng.unit() < 0.5
            val canDown = center + shiftJump <= hi
            val canUp = center - shiftJump >= lo
            val offset = when {
                (wantsDown && canDown) || (!wantsDown && canDown && !canUp) -> shiftJump
                (!wantsDown && canUp) || (wantsDown && !canDown && canUp) -> -shiftJump
                else -> return Pipe(x, center, gap)
            }
            return Pipe(x, center, gap, shiftDelay = delay, shiftOffset = offset)
        }
    }
}
