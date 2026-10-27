// 원본: Sources/CheckCore/CrossyGame.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.minigame.crossy

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.roundedHalfAwayFromZero
import com.yehsung.aingcheck.core.rules.minigame.swiftMax
import com.yehsung.aingcheck.core.rules.minigame.swiftMin
import kotlin.math.floor

/**
 * 길건너 아잉이(v0.3.67) — 규칙(G §8-16: W1-a 가 규칙·골든까지 옮긴다. 화면은 폰 1.0.15 와 같이 W4-b 에서).
 *
 * 가로 9칸, 줄은 앞으로 끝없이 생긴다(시작 줄 0, 앞 +). 줄 종류 넷: 풀밭(나무·바위가 막는다) · 찻길 · 강(통나무) · 기찻길.
 * 앞으로 한 칸 = 뛰기 한 번 = [hopSeconds](0.12초) — 서버 시간 하한 `minigame_min_seconds('crossy', s) = s × 0.09`
 * (= s × hopSeconds × [serverTimeMarginFactor])의 재료다. 뛰는 중 입력은 **한 칸만** 줄 서고, 앞 뛰기가 끝난 순간 남은 dt 를
 * 이어 받아 시작한다. 점수는 **착지**에서 오르고 줄지 않는다(가장 앞 줄). 줄은 시드 고정 난수 하나로 **순서대로만** 만든다.
 *
 * 동일성 등급 **비트**: pow·삼각함수가 없고 사칙·비교·floor·Swift `.rounded()` 뿐이다(골든 `crossy/lanes` · `crossy/scripted`).
 * Swift 는 값 타입이다. Kotlin 은 참조라 복제가 필요하면 [copy] 를 부른다(Swift synthesized `==` 처럼 [equals] 는 난수까지 본다).
 */
class CrossyGame private constructor(
    phase: Phase,
    lanes: MutableList<Lane>,
    player: Player,
    hop: Hop?,
    queued: Direction?,
    score: Int,
    cameraRow: Double,
    sinceProgress: Double,
    death: Death?,
    elapsed: Double,
    hopCount: Int,
    roundSeed: ULong,
    private var seedSource: CrossyRandom,
    private var generator: CrossyRandom,
    private var roundsStarted: Int,
    private var segmentKind: LaneKind,
    private var segmentLeft: Int,
    private var segmentIndex: Int,
    private var pathColumn: Int,
) {
    // MARK: 값 타입

    enum class Direction(val rawValue: String) {
        forward("forward"), back("back"), left("left"), right("right");

        /** 줄 변화(앞 +1). */
        val rowDelta: Int get() = when (this) { forward -> 1; back -> -1; left, right -> 0 }

        /** 칸 변화(오른쪽 +1). */
        val columnDelta: Int get() = when (this) { left -> -1; right -> 1; forward, back -> 0 }
    }

    enum class LaneKind(val rawValue: String) { grass("grass"), road("road"), river("river"), rail("rail") }

    /** 풀밭의 막는 물건. 나무 높이(0…2)는 그림의 것이다. */
    sealed interface Prop {
        data class Tree(val height: Int) : Prop
        data object Rock : Prop
    }

    /** 움직이는 물체. [x] 는 왼쪽 끝(칸 단위). */
    data class Mover(val x: Double, val length: Double, val variant: Int = 0, val isTruck: Boolean = false) {
        val maxX: Double get() = x + length

        /** 가운데 [center], 반폭 [halfWidth] 구간과 겹치는가(끝 너그러움 [grace] 만큼 안으로 좁혀 잰다). */
        fun overlaps(center: Double, halfWidth: Double, grace: Double = 0.0): Boolean =
            center + halfWidth > x + grace && center - halfWidth < maxX - grace
    }

    /**
     * 한 줄. 풀밭은 [props], 찻길·강은 [movers], 기찻길은 [train]·[trainCountdown]·[trainRandom].
     * Swift 는 값 타입이라 읽은 쪽이 고쳐도 판이 안 바뀐다. Kotlin 은 참조라 고치는 문(set)을 모듈 안([CrossyGame])으로만 열고,
     * [movers] 는 읽기 목록, [trainRandom] 은 읽을 때마다 사본이다(판 밖에서 난수를 굴려 판을 바꾸지 못하게).
     */
    class Lane(
        val row: Int,
        val kind: LaneKind,
        props: List<Prop?>? = null,
        direction: Int = 1,
        speed: Double = 0.0,
        movers: List<Mover> = emptyList(),
        train: Mover? = null,
        trainCountdown: Double = 0.0,
        trainSeed: ULong = 0uL,
    ) {
        var props: List<Prop?> = props ?: List(columns) { null }
            internal set
        var direction: Int = direction
            internal set
        var speed: Double = speed
            internal set
        internal val moverList: MutableList<Mover> = movers.toMutableList()
        val movers: List<Mover> get() = moverList
        var train: Mover? = train
            internal set
        var trainCountdown: Double = trainCountdown
            internal set
        internal var trainRng: CrossyRandom = CrossyRandom(trainSeed)
        val trainRandom: CrossyRandom get() = trainRng.copy()

        /** 흐름 속도(칸/초, 방향 포함). */
        val velocity: Double get() = direction.toDouble() * speed

        /** 그 칸이 막혔는가(풀밭의 나무·바위). 놀이 칸 밖도 막힘이다. */
        fun isBlocked(column: Int): Boolean {
            if (column < 0 || column >= columns) return true
            return kind == LaneKind.grass && props[column] != null
        }

        /** 경고등(기차가 나타나기 [warnSeconds] 전부터 지나갈 때까지). */
        val isTrainWarning: Boolean get() = kind == LaneKind.rail && (train != null || trainCountdown <= warnSeconds)

        /** x 에 서 있는 아잉이를 태울 통나무(강만). */
        fun log(under: Double): Mover? {
            if (kind != LaneKind.river) return null
            return moverList.firstOrNull { under >= it.x - logGrace && under <= it.maxX + logGrace }
        }

        fun copy(): Lane = Lane(row, kind, props, direction, speed, moverList, train, trainCountdown).also {
            it.trainRng = trainRng.copy()
        }

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is Lane) return false
            return row == other.row && kind == other.kind && props == other.props && direction == other.direction &&
                speed == other.speed && moverList == other.moverList && train == other.train &&
                trainCountdown == other.trainCountdown && trainRng == other.trainRng
        }

        override fun hashCode(): Int = row * 31 + kind.hashCode()
    }

    /** 뛰기 한 번. 통나무에서 뛰면 출발 줄의 흐름이 두 끝을 같이 민다. */
    data class Hop(
        val fromRow: Int,
        val fromX: Double,
        val toRow: Int,
        val toX: Double,
        /** 착지 x 가 흐름을 따라 움직이는가(강으로 뛰는 경우). */
        val toFloats: Boolean,
        val elapsed: Double,
        val direction: Direction,
        /** 막힌 칸이라 제자리에서 통통 뛰었다. */
        val bumped: Boolean,
        /** 출발이 통나무 위였다. */
        val fromRiding: Boolean,
    ) {
        /** 0…1 진행. */
        val progress: Double get() = swiftMin(1.0, swiftMax(0.0, elapsed / hopSeconds))
    }

    data class Player(val row: Int, val x: Double, val riding: Boolean, val facing: Direction)

    enum class DeathCause(val rawValue: String, val caption: String) {
        car("car", "차에 치였어요"),
        water("water", "물에 빠졌어요"),
        carriedOff("carriedOff", "통나무와 떠내려갔어요"),
        train("train", "기차에 치였어요"),
        leftBehind("leftBehind", "놓쳤어요"),
    }

    data class Death(val cause: DeathCause, val row: Int, val x: Double, val at: Double, val pushDirection: Int)

    sealed interface Phase {
        data object Ready : Phase
        data object Running : Phase
        /** 죽음 연출. 0 이 되면 결과. */
        data class Over(val hold: Double) : Phase
        data object Result : Phase
    }

    /** 충돌을 따지는 자리 · 그림 자리. */
    data class Spot(val row: Int, val x: Double)
    data class Visual(val row: Double, val x: Double, val lift: Double)

    // MARK: 상태(전부 읽기 전용)

    var phase: Phase = phase
        private set
    private var laneList: MutableList<Lane> = lanes
    /** 들고 있는 줄들(카메라 뒤 ~ 가장 앞 줄 앞). 목록은 읽을 때마다 새것이고, 줄은 모듈 밖에서 못 고친다([Lane] 머리 주석). */
    val lanes: List<Lane> get() = laneList.toList()
    var player: Player = player
        private set
    var hop: Hop? = hop
        private set
    /** 뛰는 중 들어온 입력 하나(그 뒤 입력은 버린다). */
    var queued: Direction? = queued
        private set
    /** 점수 = 착지한 가장 앞 줄(뒤로 가도 줄지 않는다). */
    var score: Int = score
        private set
    var cameraRow: Double = cameraRow
        private set
    var sinceProgress: Double = sinceProgress
        private set
    var death: Death? = death
        private set
    var elapsed: Double = elapsed
        private set
    var hopCount: Int = hopCount
        private set
    var roundSeed: ULong = roundSeed
        private set

    // MARK: 만들기

    /** 시드에서 시작 판(준비 상태)을 만든다. */
    constructor(seed: ULong) : this(
        phase = Phase.Ready,
        lanes = mutableListOf(),
        player = Player(0, startColumn.toDouble(), false, Direction.forward),
        hop = null,
        queued = null,
        score = 0,
        cameraRow = 0.0,
        sinceProgress = 0.0,
        death = null,
        elapsed = 0.0,
        hopCount = 0,
        roundSeed = 0uL,
        seedSource = CrossyRandom(seed),
        generator = CrossyRandom(0uL),
        roundsStarted = 0,
        segmentKind = LaneKind.grass,
        segmentLeft = 0,
        segmentIndex = 0,
        pathColumn = startColumn,
    ) {
        val first = seedSource.next()
        roundSeed = first
        generator = CrossyRandom(first)
        fillLanes()
    }

    /** Swift 값 복사와 같은 뜻의 깊은 복제(줄 · 난수까지). */
    fun copy(): CrossyGame = CrossyGame(
        phase, laneList.mapTo(mutableListOf()) { it.copy() }, player, hop, queued, score, cameraRow, sinceProgress, death,
        elapsed, hopCount, roundSeed, seedSource.copy(), generator.copy(), roundsStarted, segmentKind, segmentLeft,
        segmentIndex, pathColumn,
    )

    /** Swift synthesized `==` — 저장 칸 전부(난수 상태 · 덩어리 장부까지). */
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is CrossyGame) return false
        return phase == other.phase && laneList == other.laneList && player == other.player && hop == other.hop &&
            queued == other.queued && score == other.score && cameraRow == other.cameraRow &&
            sinceProgress == other.sinceProgress && death == other.death && elapsed == other.elapsed &&
            hopCount == other.hopCount && roundSeed == other.roundSeed && seedSource == other.seedSource &&
            generator == other.generator && roundsStarted == other.roundsStarted && segmentKind == other.segmentKind &&
            segmentLeft == other.segmentLeft && segmentIndex == other.segmentIndex && pathColumn == other.pathColumn
    }

    override fun hashCode(): Int = score * 31 + hopCount

    // MARK: 파생(순수)

    val isPlaying: Boolean get() = phase == Phase.Running || phase is Phase.Over

    val isGameOver: Boolean get() = phase is Phase.Over || phase == Phase.Result

    /** 그 줄(들고 있는 범위 밖이면 null). */
    fun lane(at: Int): Lane? {
        val first = laneList.firstOrNull() ?: return null
        if (at < first.row || at - first.row >= laneList.size) return null
        return laneList[at - first.row]
    }

    /** 지금 충돌을 따지는 자리. 뛰는 중이면 절반을 넘긴 순간 도착 줄로 넘어간다. */
    val occupancy: Spot
        get() {
            val h = hop ?: return Spot(player.row, player.x)
            val p = h.progress
            val row = if (p < 0.5) h.fromRow else h.toRow
            return Spot(row, h.fromX + (h.toX - h.fromX) * p)
        }

    /** 그림의 자리 — 줄(연속) · x · 뜬 높이(포물선). */
    val playerVisual: Visual
        get() {
            val h = hop ?: return Visual(player.row.toDouble(), player.x, 0.0)
            val p = h.progress
            val row = h.fromRow.toDouble() + (h.toRow - h.fromRow).toDouble() * p
            val x = h.fromX + (h.toX - h.fromX) * p
            return Visual(row, x, 4 * p * (1 - p))
        }

    // MARK: 입력

    /** 클릭·스페이스. 시작 전·결과면 새 판 + 앞으로 한 칸, 진행 중이면 앞으로 한 칸, 죽음 연출 중엔 무시. */
    fun action() {
        when (phase) {
            Phase.Ready, Phase.Result -> {
                startRound()
                input(Direction.forward)
            }
            Phase.Running -> input(Direction.forward)
            is Phase.Over -> return
        }
    }

    /** 방향 입력. 시작 전이면 새 판을 열고 그 방향으로 뛴다. 결과 화면의 방향키는 무시한다. */
    fun input(direction: Direction) {
        when (phase) {
            Phase.Ready -> startRound()
            Phase.Running -> Unit
            is Phase.Over, Phase.Result -> return
        }
        if (hop != null) {
            if (queued == null) queued = direction
            return
        }
        beginHop(direction, carry = 0.0)
    }

    /** 허브가 판을 끊을 때. 진행 중이면 그 점수로 결과 확정(유효). */
    fun interrupt() {
        when (phase) {
            Phase.Running, is Phase.Over -> {
                phase = Phase.Result
                queued = null
            }
            Phase.Ready, Phase.Result -> Unit
        }
    }

    // MARK: 시간

    fun step(dt: Double) {
        val d = swiftMin(swiftMax(0.0, dt), maxStep)
        when (val p = phase) {
            Phase.Ready, Phase.Result -> return
            is Phase.Over -> {
                elapsed += d
                moveLanes(d)
                val left = p.hold - d
                phase = if (left <= 0) Phase.Result else Phase.Over(left)
                return
            }
            Phase.Running -> Unit
        }

        elapsed += d
        moveLanes(d)
        movePlayer(d)
        if (phase is Phase.Over) return
        if (score >= maxScore) {
            score = maxScore
            phase = Phase.Result
            hop = null
            queued = null
            return
        }
        moveCamera(d)
        sinceProgress += d
        checkDeaths()
        fillLanes()
    }

    // MARK: 내부 — 한 판

    private fun startRound() {
        // 첫 판은 시작 카드 뒤에 서 있던 길 그대로다. 그다음 판부터 새 길(시드 줄기는 처음 시드에서 결정적으로 나온다).
        if (roundsStarted > 0) {
            roundSeed = seedSource.next()
            generator = CrossyRandom(roundSeed)
            laneList = mutableListOf()
            segmentKind = LaneKind.grass
            segmentLeft = 0
            segmentIndex = 0
            pathColumn = startColumn
        }
        roundsStarted += 1
        player = Player(0, startColumn.toDouble(), false, Direction.forward)
        hop = null
        queued = null
        score = 0
        cameraRow = 0.0
        sinceProgress = 0.0
        death = null
        elapsed = 0.0
        hopCount = 0
        fillLanes()
        phase = Phase.Running
    }

    private fun beginHop(direction: Direction, carry: Double) {
        player = player.copy(facing = direction)
        hopCount += 1
        val fromRow = player.row
        val fromX = player.x
        val toRow = fromRow + direction.rowDelta
        val target = lane(toRow)
        var toX = fromX + direction.columnDelta.toDouble()
        var floats = false
        var bumped = false
        if (target?.kind == LaneKind.river) {
            floats = true
            if (!player.riding) toX = toX.roundedHalfAwayFromZero()
            // 놀이 칸 밖으로 뛰는 것은 막힘이다(검토 지적 2026-10-27 — 통나무 위 끝 칸 옆 뛰기가 즉사였다).
            if (toX < playMinX || toX > playMaxX) bumped = true
        } else {
            val column = toX.roundedHalfAwayFromZero().toInt()
            if (target?.isBlocked(column) ?: true) {
                bumped = true
            } else {
                toX = column.toDouble()
            }
        }
        hop = if (bumped) {
            Hop(fromRow, fromX, fromRow, fromX, player.riding, carry, direction, bumped = true, fromRiding = player.riding)
        } else {
            Hop(fromRow, fromX, toRow, toX, floats, carry, direction, bumped = false, fromRiding = player.riding)
        }
    }

    private fun movePlayer(dt: Double) {
        var current = hop
        if (current == null) {
            if (player.riding) {
                val lane = lane(player.row)
                if (lane != null) player = player.copy(x = player.x + lane.velocity * dt)
            }
            return
        }
        if (current.fromRiding) {
            val lane = lane(current.fromRow)
            if (lane != null) {
                val shift = lane.velocity * dt
                current = current.copy(fromX = current.fromX + shift)
                if (current.toFloats) current = current.copy(toX = current.toX + shift)
            }
        }
        current = current.copy(elapsed = current.elapsed + dt)
        // 1e-9 는 부동소수 덧셈 찌꺼기 몫이다(0.01 열두 번이 0.12 에 모자라 한 프레임 늦게 착지하지 않게).
        if (!(current.elapsed >= hopSeconds - 1e-9)) {
            hop = current
            return
        }
        val carry = swiftMax(0.0, current.elapsed - hopSeconds)
        hop = null
        land(current)
        if (phase is Phase.Over) return
        val next = queued
        if (next != null) {
            queued = null
            beginHop(next, carry)
        }
    }

    private fun land(landed: Hop) {
        player = player.copy(row = landed.toRow, x = landed.toX)
        val lane = lane(landed.toRow) ?: return
        if (lane.kind == LaneKind.river) {
            if (lane.log(player.x) != null) {
                player = player.copy(riding = true)
            } else {
                player = player.copy(riding = false)
                die(DeathCause.water, push = 0)
                return
            }
        } else {
            player = player.copy(riding = false, x = player.x.roundedHalfAwayFromZero())
        }
        if (landed.toRow > score) {
            score = landed.toRow
            sinceProgress = 0.0
        }
    }

    private fun moveCamera(dt: Double) {
        val target = playerVisual.row
        if (target > cameraRow) cameraRow += (target - cameraRow) * swiftMin(1.0, followRate * dt)
        cameraRow += creepSpeed(score) * dt
    }

    private fun checkDeaths() {
        if (player.riding && hop == null && (player.x < playMinX || player.x > playMaxX)) {
            die(DeathCause.carriedOff, push = 0)
            return
        }
        val current = hop
        if (current != null && current.fromRiding && current.progress < 0.5 &&
            (current.fromX < playMinX || current.fromX > playMaxX)
        ) {
            die(DeathCause.carriedOff, push = 0)
            return
        }
        val spot = occupancy
        val lane = lane(spot.row)
        if (lane != null) {
            when (lane.kind) {
                LaneKind.road -> if (lane.moverList.any { it.overlaps(spot.x, playerHalfWidth, grace = 0.06) }) {
                    die(DeathCause.car, push = lane.direction)
                    return
                }
                LaneKind.rail -> {
                    val train = lane.train
                    if (train != null && train.overlaps(spot.x, playerHalfWidth)) {
                        die(DeathCause.train, push = lane.direction)
                        return
                    }
                }
                LaneKind.grass, LaneKind.river -> Unit
            }
        }
        if (spot.row.toDouble() < cameraRow - behindRows || sinceProgress >= idleLimit) {
            die(DeathCause.leftBehind, push = 0)
        }
    }

    private fun die(cause: DeathCause, push: Int) {
        val spot = occupancy
        death = Death(cause, spot.row, spot.x, elapsed, push)
        player = player.copy(row = spot.row, x = spot.x, riding = false)
        hop = null
        queued = null
        phase = Phase.Over(deathHold)
    }

    // MARK: 내부 — 줄

    private fun moveLanes(dt: Double) {
        for (lane in laneList) {
            when (lane.kind) {
                LaneKind.road, LaneKind.river -> {
                    val v = lane.velocity * dt
                    for (m in lane.moverList.indices) {
                        var mover = lane.moverList[m]
                        mover = mover.copy(x = mover.x + v)
                        if (v > 0 && mover.x > trackRight) mover = mover.copy(x = mover.x - trackLength)
                        if (v < 0 && mover.maxX < trackLeft) mover = mover.copy(x = mover.x + trackLength)
                        lane.moverList[m] = mover
                    }
                }
                LaneKind.rail -> stepRail(lane, dt)
                LaneKind.grass -> Unit
            }
        }
    }

    /** 들고 있는 줄을 카메라 뒤 [lanesBehind] ~ 가장 앞 줄 앞 [lanesAhead] 로 맞춘다. 앞은 순서대로만 만든다(결정성). */
    private fun fillLanes() {
        val lowest = minOf(player.row, floor(cameraRow).toInt()) - lanesBehind
        val highest = maxOf(player.row, score) + lanesAhead
        if (laneList.isEmpty()) {
            var row = minOf(lowest, wallRow - 2)
            while (row <= highest) {
                laneList.add(makeLane(row))
                row += 1
            }
            return
        }
        while (laneList.last().row < highest) laneList.add(makeLane(laneList.last().row + 1))
        val first = laneList.first()
        if (first.row < lowest) {
            val drop = minOf(lowest - first.row, laneList.size - 1)
            repeat(drop) { laneList.removeAt(0) }
        }
    }

    private fun makeLane(r: Int): Lane {
        if (r <= wallRow) {
            val props: List<Prop?> = List(columns) { c -> Prop.Tree(if (((c + r) and 1) == 0) 2 else 1) }
            return Lane(r, LaneKind.grass, props)
        }
        if (r <= startGrassRows) return startGrass(r)
        if (segmentLeft <= 0) beginSegment(r)
        segmentLeft -= 1
        segmentIndex += 1
        return when (segmentKind) {
            LaneKind.grass -> grass(r)
            LaneKind.road -> road(r)
            LaneKind.river -> river(r)
            LaneKind.rail -> rail(r)
        }
    }

    /** 시작 풀밭(−2…3). 가운데 줄기(3·4·5 칸)는 비운다. 난수 순서: 칸마다 판정 → (참이면) 나무/바위 → (나무면) 높이. */
    private fun startGrass(r: Int): Lane {
        val props = MutableList<Prop?>(columns) { null }
        val edgeColumns = if (r < 0) listOf(0, 1, 7, 8) else listOf(0, 8)
        for (c in edgeColumns) {
            if (!(generator.unit() < (if (r < 0) 0.7 else 0.45))) continue
            props[c] = if (generator.unit() < 0.75) Prop.Tree((generator.next() % 3uL).toInt()) else Prop.Rock
        }
        if (r > 0) {
            for (c in listOf(1, 2, 6, 7)) {
                if (!(generator.unit() < 0.2)) continue
                props[c] = if (generator.unit() < 0.7) Prop.Tree((generator.next() % 3uL).toInt()) else Prop.Rock
            }
        }
        pathColumn = startColumn
        return Lane(r, LaneKind.grass, props)
    }

    private fun beginSegment(r: Int) {
        val d = difficulty(r)
        var weights: List<Pair<LaneKind, Double>> = listOf(
            LaneKind.grass to 0.30 - 0.10 * d,
            LaneKind.road to 0.36,
            LaneKind.river to if (r >= riverStartRow) 0.22 + 0.04 * d else 0.0,
            LaneKind.rail to if (r >= railStartRow) 0.08 + 0.10 * d else 0.0,
        )
        // 같은 종류의 덩어리가 연달아 오지 않는다.
        weights = weights.map { if (it.first == segmentKind) it.first to 0.0 else it }
        val total = weights.fold(0.0) { acc, w -> acc + w.second }
        var pick = generator.unit() * total
        var kind = LaneKind.road
        for ((candidate, weight) in weights) {
            if (!(weight > 0)) continue
            if (pick < weight) {
                kind = candidate
                break
            }
            pick -= weight
            kind = candidate
        }
        val maxLength = when (kind) {
            LaneKind.grass -> 2
            LaneKind.road -> 2 + (2 * d).toInt()
            LaneKind.river -> 2 + (d + 0.2).toInt()
            LaneKind.rail -> 1 + (d + 0.4).toInt()
        }
        segmentKind = kind
        segmentLeft = 1 + (generator.next() % maxLength.toULong()).toInt()
        segmentIndex = 0
        if (kind == LaneKind.grass) {
            pathColumn = 1 + (generator.next() % (columns - 2).toULong()).toInt()
        }
    }

    private fun grass(r: Int): Lane {
        val d = difficulty(r)
        val props = MutableList<Prop?>(columns) { null }
        for (c in 0 until columns) {
            if (c == pathColumn) continue
            if (!(generator.unit() < 0.18 + 0.12 * d)) continue
            props[c] = if (generator.unit() < 0.7) Prop.Tree((generator.next() % 3uL).toInt()) else Prop.Rock
        }
        return Lane(r, LaneKind.grass, props)
    }

    private fun road(r: Int): Lane {
        val d = difficulty(r)
        val direction = if (generator.unit() < 0.5) 1 else -1
        val truck = generator.unit() < 0.22 + 0.15 * d
        val length = if (truck) truckLength else carLength
        var count = 1
        if (generator.unit() < 0.5 + 0.3 * d) count += 1
        if (d > 0.4 && generator.unit() < 0.3 + 0.3 * d) count += 1
        val speed = generator.uniform(1.5, 2.3) * (1 + 0.9 * d) * (if (truck) 0.85 else 1.0)
        val colorBase = (generator.next() % 5uL).toInt()
        val xs = place(count, { length }, minGap = 3.0)
        val movers = xs.mapIndexed { i, x -> Mover(x, length, (colorBase + i) % 5, truck) }
        return Lane(r, LaneKind.road, direction = direction, speed = speed, movers = movers)
    }

    private fun river(r: Int): Lane {
        val d = difficulty(r)
        // 한 강 안에서는 흐름이 번갈아 간다(첫 줄만 무작위). 난수는 언제나 하나 뽑는다.
        val coin = if (generator.unit() < 0.5) 1 else -1
        val previous = laneList.lastOrNull()
        val direction = if (segmentIndex > 1 && previous != null && previous.kind == LaneKind.river) -previous.direction else coin
        val speed = generator.uniform(0.9, 1.3) * (1 + 0.6 * d)
        val count = if (d < 0.5) 3 else 2
        val shortest = if (d < 0.4) 3 else 2
        val lengths = ArrayList<Double>(count)
        repeat(count) { lengths.add((shortest + (generator.next() % 2uL).toInt()).toDouble()) }
        val xs = place(count, { lengths[it] }, minGap = 1.2)
        val movers = ArrayList<Mover>(count)
        for ((i, x) in xs.withIndex()) movers.add(Mover(x, lengths[i], (generator.next() % 3uL).toInt()))
        return Lane(r, LaneKind.river, direction = direction, speed = speed, movers = movers)
    }

    private fun rail(r: Int): Lane {
        val direction = if (generator.unit() < 0.5) 1 else -1
        val countdown = generator.uniform(1.5, 6.0)
        return Lane(r, LaneKind.rail, direction = direction, speed = trainSpeed, trainCountdown = countdown,
            trainSeed = generator.next())
    }

    /** 트랙 위에 [count] 개를 고르게 + 흔들어 놓는다(왼쪽 끝 x 들). 사이는 언제나 [minGap] 이상. */
    private fun place(count: Int, length: (Int) -> Double, minGap: Double): List<Double> {
        val slot = trackLength / count.toDouble()
        val offset = generator.uniform(0.0, slot)
        return List(count) { i ->
            val room = swiftMax(0.0, slot - length(i) - minGap)
            val jitter = generator.uniform(0.0, room)
            var x = trackLeft + offset + i.toDouble() * slot + jitter
            if (x > trackRight) x -= trackLength
            x
        }
    }

    // MARK: 시험 · 미리보기 전용

    /** 지금 판에서 [row] 줄까지 이어서 만들면 나올 줄들(판은 안 바뀐다 — 사본에서 만든다). */
    fun previewLanes(through: Int): List<Lane> {
        val copy = copy()
        while (copy.laneList.isNotEmpty() && copy.laneList.last().row < through) {
            copy.laneList.add(copy.makeLane(copy.laneList.last().row + 1))
        }
        return copy.laneList
    }

    /** 그 줄을 통째로 갈아 끼운다(시험이 물체를 원하는 자리에 세운다). 들고 있지 않은 줄이면 아무 일도 없다. */
    fun replaceLane(lane: Lane) {
        val first = laneList.firstOrNull() ?: return
        if (lane.row < first.row || lane.row - first.row >= laneList.size) return
        laneList[lane.row - first.row] = lane
    }

    /** 판을 바로 진행 중으로 연다(뛰지 않고). */
    fun startForTesting() {
        startRound()
    }

    /** 아잉이를 그 자리에 세운다(착지 규칙을 거치지 않는다). */
    fun placePlayerForTesting(row: Int, x: Double, riding: Boolean = false) {
        player = player.copy(row = row, x = x, riding = riding)
        hop = null
        queued = null
    }

    companion object {
        const val columns: Int = 9
        const val startColumn: Int = 4

        /** 뛰기 한 번의 시간(초) — 서버 시간 하한의 재료(바꾸면 `minigame_min_seconds('crossy')` 도 같이). */
        const val hopSeconds: Double = 0.12

        /** 서버 시간 하한이 [hopSeconds] 에 거는 배수(서버 식 s × 0.09 의 0.09 = hopSeconds × 이 값). */
        const val serverTimeMarginFactor: Double = 0.75
        val maxScore: Int get() = MiniGameKind.crossy.maxScore
        const val maxStep: Double = 1.0 / 30.0
        const val deathHold: Double = 1.1
        const val playerHalfWidth: Double = 0.3
        const val logGrace: Double = 0.2
        const val carLength: Double = 1.4
        const val truckLength: Double = 2.4
        const val trackMargin: Double = 5.0
        const val warnSeconds: Double = 1.0
        const val trainLength: Double = 14.0
        const val trainSpeed: Double = 24.0
        const val behindRows: Double = 2.5
        const val idleLimit: Double = 9.0
        const val followRate: Double = 3.0
        const val startGrassRows: Int = 3
        const val wallRow: Int = -3
        const val railStartRow: Int = 14
        const val riverStartRow: Int = 6
        const val difficultyRows: Double = 250.0
        const val lanesBehind: Int = 8
        const val lanesAhead: Int = 24

        val trackLeft: Double get() = -0.5 - trackMargin
        val trackRight: Double get() = columns.toDouble() - 0.5 + trackMargin
        val trackLength: Double get() = trackRight - trackLeft
        const val playMinX: Double = -0.5
        val playMaxX: Double get() = columns.toDouble() - 0.5

        /** 난이도 0…1 — 줄 번호로 오른다(4 줄부터 254 줄까지). */
        fun difficulty(row: Int): Double = swiftMin(1.0, swiftMax(0.0, (row - 4).toDouble() / difficultyRows))

        /** 카메라가 혼자 앞으로 가는 빠르기(줄/초). */
        fun creepSpeed(row: Int): Double = 0.18 + 0.27 * difficulty(row)

        private fun stepRail(lane: Lane, dt: Double) {
            val train = lane.train
            if (train != null) {
                val moved = train.copy(x = train.x + lane.direction.toDouble() * trainSpeed * dt)
                val gone = if (lane.direction > 0) moved.x > trackRight else moved.maxX < trackLeft
                if (gone) {
                    lane.train = null
                    val d = difficulty(lane.row)
                    lane.trainCountdown = lane.trainRng.uniform(4.0, 7.0) * (1 - 0.35 * d)
                } else {
                    lane.train = moved
                }
                return
            }
            lane.trainCountdown -= dt
            if (lane.trainCountdown <= 0) {
                val start = if (lane.direction > 0) trackLeft - trainLength else trackRight
                lane.train = Mover(start, trainLength)
                lane.trainCountdown = 0.0
            }
        }
    }
}

/** 이 게임의 결정적 난수(SplitMix64 — `MiniGameRandom` 과 같은 식). 상태가 값으로 드러나 [equals] 가 상태를 본다. */
class CrossyRandom(seed: ULong) {
    var state: ULong = seed
        private set

    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }

    /** [0, 1) 균등. */
    fun unit(): Double = (next() shr 11).toDouble() / 9007199254740992.0

    /** [lo, hi] 균등. */
    fun uniform(lo: Double, hi: Double): Double = lo + (hi - lo) * unit()

    fun copy(): CrossyRandom = CrossyRandom(state)

    override fun equals(other: Any?): Boolean = other is CrossyRandom && other.state == state

    override fun hashCode(): Int = state.hashCode()
}
