// 원본: Sources/CheckCore/AlkkagiGame.swift @ e4995a3a(알까기 고정 걸음 규칙 — 맥 0.3.80~0.3.84 · 폰 1.0.18) — Android 판 8
//
// 600점 판 좌표의 1:1 알까기 규칙(1/240초 고정 걸음). **서버 `alkkagi_simulate` 와 같은 값이어야 한다** — 서버가 판정하고 앱은 같은 계산으로
// 다시 그린다(조준 화살 · 쏜 수의 재생). 승패 · 판 상태는 서버 스냅숏이 권위다(재생 결과가 서버 값을 바꾸지 않는다).
// Swift 는 값 타입(struct)이다 — Kotlin 은 [copy] 로 복제한다(돌 배열까지 깊이).
package com.yehsung.aingcheck.core.rules.alkkagi

import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

data class AlkkagiVector(val x: Double, val y: Double) {
    val length: Double get() = hypot(x, y)
    operator fun plus(o: AlkkagiVector) = AlkkagiVector(x + o.x, y + o.y)
    operator fun minus(o: AlkkagiVector) = AlkkagiVector(x - o.x, y - o.y)
    operator fun times(s: Double) = AlkkagiVector(x * s, y * s)

    companion object {
        val zero = AlkkagiVector(0.0, 0.0)
    }
}

class AlkkagiGame private constructor(
    stones: List<Stone>,
    currentPlayer: Player,
    phase: Phase,
    placementRemaining: Double,
    turnRemaining: Double,
    result: Result?,
    shotCount: Int,
    var physics: Physics,
    private var accumulatedTime: Double,
) {
    enum class Player(val rawValue: String) {
        black("black"), white("white");

        val opponent: Player get() = if (this == black) white else black

        companion object {
            fun of(raw: String): Player? = entries.firstOrNull { it.rawValue == raw }
        }
    }

    data class Stone(
        val id: Int,
        val owner: Player,
        val position: AlkkagiVector,
        val velocity: AlkkagiVector = AlkkagiVector.zero,
        val isOut: Boolean = false,
        val isPlaced: Boolean = true,
    )

    enum class Phase { placing, aiming, rolling, finished }

    sealed interface Result {
        data class Winner(val player: Player) : Result
        data object Draw : Result
    }

    data class Impact(val position: AlkkagiVector, val strength: Double, val isRingOut: Boolean)

    /** 감속 성질 — 1/240초 걸음마다 속도에 exp(-drag·dt) 를 곱하고 friction·dt 만큼 속력을 깎는다. 서버 SQL 과 같은 값. */
    data class Physics(val drag: Double, val friction: Double) {
        companion object {
            val ice = Physics(2.0, 0.0)
            val board = Physics(1.5, 300.0)
            val heavy = Physics(2.2, 500.0)
            /** 지금 앱 · 서버가 쓰는 값 — 대표 답 (B) 바둑판 마찰(#d_eeuXIRdSJWxL, 11-09). */
            val current = board
        }
    }

    companion object {
        const val boardSize: Double = 600.0
        const val stoneRadius: Double = 20.0
        const val maxPull: Double = 135.0
        /** 판의 첫 수(흑)의 최대 당김 = 81(최대의 60% — 대표 #d_5KuZ3DGTw6BY · 서버 `alk_first_shot_max_pull()`). 규칙은 **입력**에 건다. */
        const val firstShotMaxPull: Double = 81.0
        const val placementDuration: Double = 30.0
        const val turnDuration: Double = 30.0
        private const val fixedStep: Double = 1.0 / 240.0
        private const val clockTolerance: Double = 1e-9
        private const val impulseScale: Double = 11.0
        private const val restSpeed: Double = 6.0

        /** 새 판(흑 아래 · 백 위, 아직 안 놓음). */
        fun newGame(): AlkkagiGame {
            val columns = listOf(80.0, 190.0, 300.0, 410.0, 520.0)
            val stones = Player.entries.flatMap { player ->
                columns.mapIndexed { column, x ->
                    Stone(column + if (player == Player.black) 0 else 5, player, AlkkagiVector(x, if (player == Player.black) 460.0 else 140.0), isPlaced = false)
                }
            }
            return AlkkagiGame(stones, Player.black, Phase.placing, placementDuration, turnDuration, null, 0, Physics.current, 0.0)
        }

        /** 서버 스냅숏을 시계를 흘리지 않고 그대로 세운다. 모양이 틀리면 null. */
        fun restore(
            stones: List<Stone>,
            currentPlayer: Player,
            phase: Phase,
            placementRemaining: Double = placementDuration,
            turnRemaining: Double = turnDuration,
            result: Result? = null,
            shotCount: Int = 0,
        ): AlkkagiGame? {
            if (stones.size > 10 || stones.map { it.id }.toSet().size != stones.size) return null
            if (shotCount < 0 || shotCount == Int.MAX_VALUE) return null
            if (!placementRemaining.isFinite() || placementRemaining !in 0.0..placementDuration) return null
            if (!turnRemaining.isFinite() || turnRemaining !in 0.0..turnDuration) return null
            if ((phase == Phase.finished) != (result != null)) return null
            val ok = stones.all { s ->
                s.id in 0 until 10 && s.owner == (if (s.id < 5) Player.black else Player.white) &&
                    s.position.x.isFinite() && s.position.y.isFinite() && s.velocity.x.isFinite() && s.velocity.y.isFinite() &&
                    s.velocity.length.isFinite() && (s.isOut || isOnBoard(s.position)) &&
                    (s.isPlaced || (!s.isOut && s.velocity.length == 0.0))
            }
            if (!ok) return null
            return AlkkagiGame(stones, currentPlayer, phase, placementRemaining, turnRemaining, result, shotCount, Physics.current, 0.0)
        }

        private fun isOnBoard(p: AlkkagiVector): Boolean = p.x >= 0 && p.x <= boardSize && p.y >= 0 && p.y <= boardSize
    }

    var stones: MutableList<Stone> = stones.toMutableList()
    var currentPlayer: Player = currentPlayer
        private set
    var phase: Phase = phase
        private set
    var placementRemaining: Double = placementRemaining
        private set
    var turnRemaining: Double = turnRemaining
        private set
    var result: Result? = result
        private set
    var shotCount: Int = shotCount
        private set

    fun copy(): AlkkagiGame =
        AlkkagiGame(stones.toList(), currentPlayer, phase, placementRemaining, turnRemaining, result, shotCount, physics, accumulatedTime)

    override fun equals(other: Any?): Boolean = other is AlkkagiGame && other.stones == stones && other.currentPlayer == currentPlayer &&
        other.phase == phase && other.placementRemaining == placementRemaining && other.turnRemaining == turnRemaining &&
        other.result == result && other.shotCount == shotCount && other.physics == physics && other.accumulatedTime == accumulatedTime

    override fun hashCode(): Int = stones.hashCode() * 31 + shotCount

    fun placedCount(player: Player): Int = stones.count { it.owner == player && it.isPlaced && !it.isOut }

    fun canPlace(stoneID: Int, position: AlkkagiVector): Boolean {
        if (phase != Phase.placing || !position.x.isFinite() || !position.y.isFinite()) return false
        val index = stones.indexOfFirst { it.id == stoneID }
        if (index < 0) return false
        val s = stones[index]
        if (s.owner != currentPlayer || s.isOut) return false
        if (position.x < stoneRadius || position.x > boardSize - stoneRadius || position.y < stoneRadius || position.y > boardSize - stoneRadius) return false
        if (!(if (currentPlayer == Player.black) position.y >= 320 else position.y <= 280)) return false
        return stones.indices.all { other ->
            other == index || !stones[other].isPlaced || stones[other].isOut || (stones[other].position - position).length >= 2 * stoneRadius + 2
        }
    }

    fun placeStone(stoneID: Int, position: AlkkagiVector): Boolean {
        if (!canPlace(stoneID, position)) return false
        val index = stones.indexOfFirst { it.id == stoneID }
        stones[index] = stones[index].copy(position = position, velocity = AlkkagiVector.zero, isPlaced = true)
        return true
    }

    fun confirmPlacement(): Boolean {
        if (phase != Phase.placing || !stones.all { it.owner != currentPlayer || it.isPlaced }) return false
        if (currentPlayer == Player.black) {
            currentPlayer = Player.white
            placementRemaining = placementDuration
        } else {
            currentPlayer = Player.black
            placementRemaining = 0.0
            turnRemaining = turnDuration
            phase = Phase.aiming
        }
        return true
    }

    fun shoot(stoneID: Int, pull: AlkkagiVector): Boolean {
        val length = pull.length
        if (phase != Phase.aiming || !pull.x.isFinite() || !pull.y.isFinite() || !length.isFinite() || length < 6) return false
        val index = stones.indexOfFirst { it.id == stoneID }
        if (index < 0) return false
        val s = stones[index]
        if (s.owner != currentPlayer || !s.isPlaced || s.isOut || !isOnBoard(s.position)) return false
        val speed = min(length, maxPull) * impulseScale
        stones[index] = s.copy(velocity = pull * (-speed / length))
        accumulatedTime = 0.0
        shotCount += 1
        phase = Phase.rolling
        return true
    }

    fun advance(dt: Double): List<Impact> {
        if (!dt.isFinite() || dt <= 0) return emptyList()
        var timeLeft = dt
        while (phase == Phase.placing) {
            if (timeLeft + clockTolerance < placementRemaining) {
                placementRemaining -= timeLeft
                return emptyList()
            }
            timeLeft = max(0.0, timeLeft - placementRemaining)
            placementRemaining = 0.0
            placeRemainingStones()
            if (!confirmPlacement()) return emptyList()
            if (timeLeft == 0.0) return emptyList()
        }
        if (phase == Phase.aiming) {
            if (timeLeft + clockTolerance >= turnRemaining) {
                val elapsed = max(0.0, timeLeft - turnRemaining) % (2 * turnDuration)
                currentPlayer = currentPlayer.opponent
                if (elapsed >= turnDuration) currentPlayer = currentPlayer.opponent
                turnRemaining = turnDuration - elapsed % turnDuration
            } else {
                turnRemaining -= timeLeft
            }
            return emptyList()
        }
        if (phase != Phase.rolling) return emptyList()
        // 멈췄던 창 뒤의 따라잡기를 묶는다 — 보통 프레임은 나머지를 들고 간다.
        accumulatedTime += min(dt, 0.25)
        val impacts = mutableListOf<Impact>()
        while (phase == Phase.rolling && accumulatedTime + 1e-12 >= fixedStep) {
            accumulatedTime = max(0.0, accumulatedTime - fixedStep)
            step(impacts)
            if (stones.all { !it.isPlaced || it.isOut || it.velocity.length == 0.0 }) finishShot()
        }
        return impacts
    }

    /** 지금 쏠 수 있는 최대 당김. 판의 첫 수(흑 · 아직 0수)만 [firstShotMaxPull]. */
    val shotPullLimit: Double
        get() = if (phase == Phase.aiming && shotCount == 0 && currentPlayer == Player.black) firstShotMaxPull else maxPull

    val isFirstShotLimited: Boolean get() = shotPullLimit < maxPull

    fun remaining(player: Player): Int = stones.count { it.owner == player && !it.isOut && (phase == Phase.placing || it.isPlaced) }

    private fun placeRemainingStones() {
        val spacing = 2 * stoneRadius + 2
        val firstRow = if (currentPlayer == Player.black) 320.0 else stoneRadius
        val lastRow = if (currentPlayer == Player.black) boardSize - stoneRadius else 280.0
        for (index in stones.indices) {
            val s = stones[index]
            if (s.owner != currentPlayer || s.isPlaced) continue
            if (placeStone(s.id, s.position)) continue
            // Swift 부동소수 stride 는 더해 가지 않고 `시작 + 칸 × 번호` 로 센다(누적 오차 없음) — 같은 꼴로 센다.
            var row = 0
            placement@ while (firstRow + row * spacing <= lastRow) {
                val y = firstRow + row * spacing
                var column = 0
                while (stoneRadius + column * spacing <= boardSize - stoneRadius) {
                    if (placeStone(s.id, AlkkagiVector(stoneRadius + column * spacing, y))) break@placement
                    column += 1
                }
                row += 1
            }
        }
    }

    private fun live(i: Int): Boolean = stones[i].isPlaced && !stones[i].isOut

    private fun step(impacts: MutableList<Impact>) {
        var timeLeft = fixedStep
        moveStones(0.0, impacts)
        // 쓸어 보는 접촉 — 고정 걸음 사이의 비스듬한 충돌도 빠뜨리지 않는다. 64회 상한은 퇴화 더미의 일을 묶는다.
        for (round in 0 until 64) {
            var travel = timeLeft
            var contact: Pair<Int, Int>? = null
            for (first in stones.indices) {
                if (!live(first)) continue
                for (second in stones.indices) {
                    if (second <= first || !live(second)) continue
                    val time = contactTime(first, second) ?: continue
                    if (time > travel) continue
                    if (!isOnBoard(stones[first].position + stones[first].velocity * time)) continue
                    if (!isOnBoard(stones[second].position + stones[second].velocity * time)) continue
                    travel = time
                    contact = first to second
                }
            }
            moveStones(travel, impacts)
            timeLeft = max(0.0, timeLeft - travel)
            val c = contact ?: break
            resolveContact(c.first, c.second, impacts)
            moveStones(0.0, impacts)
            if (timeLeft <= 1e-12) break
        }
        val damping = exp(-physics.drag * fixedStep)
        val friction = physics.friction * fixedStep
        for (index in stones.indices) {
            if (!live(index)) continue
            var velocity = stones[index].velocity * damping
            if (friction > 0) {
                val speed = velocity.length
                velocity = if (speed > friction) velocity * ((speed - friction) / speed) else AlkkagiVector.zero
            }
            stones[index] = stones[index].copy(velocity = if (velocity.length < restSpeed) AlkkagiVector.zero else velocity)
        }
    }

    private fun contactTime(first: Int, second: Int): Double? {
        val delta = stones[second].position - stones[first].position
        val relative = stones[second].velocity - stones[first].velocity
        val diameter = 2 * stoneRadius
        val separation = delta.x * delta.x + delta.y * delta.y - diameter * diameter
        if (separation < -1e-7) return 0.0
        val closing = delta.x * relative.x + delta.y * relative.y
        val speedSquared = relative.x * relative.x + relative.y * relative.y
        if (closing >= 0 || speedSquared <= 0) return null
        val discriminant = closing * closing - speedSquared * separation
        if (discriminant < 0) return null
        val time = (-closing - sqrt(discriminant)) / speedSquared
        return if (time >= -1e-10) max(0.0, time) else null
    }

    private fun resolveContact(first: Int, second: Int, impacts: MutableList<Impact>) {
        val delta = stones[second].position - stones[first].position
        val distance = delta.length
        val relative = stones[second].velocity - stones[first].velocity
        val normal = when {
            distance > 1e-10 -> delta * (1 / distance)
            relative.length > 0 -> relative * (-1 / relative.length)
            else -> AlkkagiVector(1.0, 0.0)
        }
        val correction = normal * (max(0.0, 2 * stoneRadius - distance) / 2)
        stones[first] = stones[first].copy(position = stones[first].position - correction)
        stones[second] = stones[second].copy(position = stones[second].position + correction)
        val closing = relative.x * normal.x + relative.y * normal.y
        if (closing >= -1e-8) return
        // 같은 질량 · 반발 0.92: 접선 운동은 지키고 에너지를 조금 잃는다.
        val impulse = normal * (-closing * 1.92 / 2)
        stones[first] = stones[first].copy(velocity = stones[first].velocity - impulse)
        stones[second] = stones[second].copy(velocity = stones[second].velocity + impulse)
        impacts += Impact((stones[first].position + stones[second].position) * 0.5, min(1.0, -closing / (maxPull * impulseScale)), false)
    }

    private fun moveStones(time: Double, impacts: MutableList<Impact>) {
        for (index in stones.indices) {
            if (!live(index)) continue
            val start = stones[index].position
            val velocity = stones[index].velocity
            val end = start + velocity * time
            stones[index] = stones[index].copy(position = end)
            if (isOnBoard(end)) continue
            // 효과는 처음 넘은 가장자리에 두되, 떠난 중심은 그대로 둔다.
            var exitTime = time
            if (end.x < 0 && velocity.x < 0) exitTime = min(exitTime, -start.x / velocity.x)
            if (end.x > boardSize && velocity.x > 0) exitTime = min(exitTime, (boardSize - start.x) / velocity.x)
            if (end.y < 0 && velocity.y < 0) exitTime = min(exitTime, -start.y / velocity.y)
            if (end.y > boardSize && velocity.y > 0) exitTime = min(exitTime, (boardSize - start.y) / velocity.y)
            val edge = start + velocity * max(0.0, exitTime)
            impacts += Impact(
                AlkkagiVector(min(max(edge.x, 0.0), boardSize), min(max(edge.y, 0.0), boardSize)),
                min(1.0, velocity.length / (maxPull * impulseScale)), true,
            )
            stones[index] = stones[index].copy(isOut = true, velocity = AlkkagiVector.zero)
        }
    }

    private fun finishShot() {
        val black = remaining(Player.black)
        val white = remaining(Player.white)
        if (black == 0 || white == 0) {
            result = if (black == 0 && white == 0) Result.Draw else Result.Winner(if (black > 0) Player.black else Player.white)
            phase = Phase.finished
        } else {
            currentPlayer = currentPlayer.opponent
            phase = Phase.aiming
        }
        turnRemaining = turnDuration
        accumulatedTime = 0.0
    }
}
