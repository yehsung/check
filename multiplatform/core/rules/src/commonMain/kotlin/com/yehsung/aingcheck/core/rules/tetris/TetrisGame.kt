// 원본: Sources/CheckCore/TetrisGame.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.tetris

import com.yehsung.aingcheck.core.rules.minigame.MiniGameRandom
import com.yehsung.aingcheck.core.rules.minigame.roundedHalfAwayFromZero
import com.yehsung.aingcheck.core.rules.minigame.swiftMax
import com.yehsung.aingcheck.core.rules.minigame.swiftMin

/**
 * 테트리스 규칙(v0.3.38 · v0.3.60 대결 확장). 시드만 주면 결정론적으로 같은 판이 나온다 — Swift `TetrisGame` 과 **비트로 같다**
 * (골든 `tetris/rules` · `tetris/bags` · `tetris/garbage-holes` · `tetris/scripted` · `tetris/duel`, C§5.1 E2·E3).
 *
 * 축 하나: 난이도 시계는 **advance = 고정한 조각 수 + 지운 줄 수** 다(시간도 프레임도 아니다). 시간 상수는 전부 초 단위이고
 * 화면은 dt 만 흘려 준다. 입력 선행(스폰 전 키 버퍼링)은 넣지 않는다(2026-09-23 사용자 확정 — `lockResetLimit` 바닥 2 의 종료 보장).
 *
 * Swift 는 값 타입(struct)이다. Kotlin 은 참조라 복제가 필요하면 [copy] 를 부른다(대결 세션 · 미리 떨어뜨려 보기).
 * 중력은 `pow` 를 부르지 않고 Swift(Darwin)가 낸 **비트 표**를 쓴다([GRAVITY_SECONDS_BITS] — G §8-14: pow 비트가 Darwin↔JVM,
 * aarch64↔amd64 에서 갈린다). 구조 시험 `TetrisMinigameNoPowStructureTest` 가 런타임 pow 0 을 잰다.
 */
class TetrisGame private constructor(
    private var cells: Array<Piece?>,
    active: ActivePiece?,
    next: MutableList<Piece>,
    heldPiece: Piece?,
    holdUsed: Boolean,
    score: Int,
    advance: Int,
    lines: Int,
    combo: Int,
    backToBack: Int,
    phase: Phase,
    elapsed: Double,
    lastClear: ClearEvent?,
    pendingGarbage: MutableList<Int>,
    attackSentTotal: Int,
    private var garbageRows: IntArray,
    levelFloor: Int,
    private var rng: MiniGameRandom,
    private var bag: MutableList<Piece>,
    private var repeatCountdown: Double?,
    private var repeatDirection: Int,
    private var leftHeld: Boolean,
    private var rightHeld: Boolean,
    private var softDropHeld: Boolean,
    private var fallCountdown: Double,
    private var groundedSeconds: Double,
    private var groundedTotalSeconds: Double,
    private var lockResets: Int,
    private var lowestRow: Int,
    private var lastActionWasRotation: Boolean,
    private var lastKickWasFinal: Boolean,
    private var garbageRng: MiniGameRandom,
    private var garbageHeadHole: Int?,
) {
    // MARK: - 판 · 조각

    /** 조각 7종. [entries] 순서는 7-bag 섞기의 입력이라 **바꾸면 같은 시드가 다른 판을 낸다.** rawValue = ordinal. */
    enum class Piece {
        i, j, l, o, s, t, z;

        val rawValue: Int get() = ordinal
    }

    /** 회전 상태. 0 = 스폰 · R = 시계 · 2 = 180° · L = 반시계(SRS 표기). */
    enum class Rotation(val rawValue: Int) {
        spawn(0), right(1), flip(2), left(3);

        val clockwise: Rotation
            get() = when (this) {
                spawn -> right
                right -> flip
                flip -> left
                left -> spawn
            }
        val counterClockwise: Rotation
            get() = when (this) {
                spawn -> left
                right -> spawn
                flip -> right
                left -> flip
            }
    }

    /** 판 좌표 한 칸(행 0 = 맨 위). */
    data class Cell(val row: Int, val column: Int)

    /** 상자 안 오프셋(dx = 열, dy = 행). 킥표에서는 y 양수 = 위. */
    data class Offset(val dx: Int, val dy: Int)

    /** 떨어지는 조각. 좌표는 바운딩 상자의 왼쪽 위 칸이다(SRS 킥이 상자를 옮기는 규칙이라). */
    data class ActivePiece(val piece: Piece, val rotation: Rotation = Rotation.spawn, val column: Int, val row: Int) {
        /** 판 좌표로 푼 네 칸. */
        val cells: List<Cell> get() = shape(piece, rotation).map { Cell(row + it.dy, column + it.dx) }
    }

    /** T-스핀 판정. */
    enum class Spin { none, mini, full }

    /** 방금 끝난 배치의 결과(그림 전용 — 규칙은 읽지 않는다). [attack] 은 상쇄 전 공격 줄 수(v0.3.60). */
    data class ClearEvent(
        val lines: Int,
        val spin: Spin,
        val backToBack: Boolean,
        val perfectClear: Boolean,
        val points: Int,
        val at: Double,
        val attack: Int = 0,
    )

    sealed interface Phase {
        /** 시작 전(루프 정지). 액션 = 새 판. */
        data object Ready : Phase
        data object Running : Phase
        /** 줄소거 정지. */
        data class LineClear(val remaining: Double) : Phase
        /** ARE(조각 사이 텀). */
        data class Are(val remaining: Double) : Phase
        /** 탑아웃 직후 유예. */
        data class Over(val hold: Double) : Phase
        /** 결과 카드(루프 정지). 액션 = 새 판. */
        data object Result : Phase
    }

    // MARK: - 상태(읽기 전용)

    var active: ActivePiece? = active
        private set
    private val nextQueue: MutableList<Piece> = next
    var heldPiece: Piece? = heldPiece
        private set
    var holdUsed: Boolean = holdUsed
        private set
    var score: Int = score
        private set
    /** 난이도 시계. 고정한 조각 수 + 지운 줄 수. */
    var advance: Int = advance
        private set
    var lines: Int = lines
        private set
    /** 콤보수. −1 = 사슬 없음. */
    var combo: Int = combo
        private set
    /** B2B 사슬 길이. −1 = 없음, 0 = 첫 어려운 소거, 1 이상부터 ×1.5. */
    var backToBack: Int = backToBack
        private set
    var phase: Phase = phase
        private set
    /** 판 시각(초) — step(dt) 이 흘린 dt 의 합. */
    var elapsed: Double = elapsed
        private set
    var lastClear: ClearEvent? = lastClear
        private set
    private val pendingQueue: MutableList<Int> = pendingGarbage
    /** 보낸 공격 누계(상쇄하고 남은 것만, 단조 증가). */
    var attackSentTotal: Int = attackSentTotal
        private set
    /** 대결 가속 바닥(기본 1 = 꺼짐). */
    var levelFloor: Int = levelFloor
        private set

    /** 굳은 칸. `board[행][열]`, 행 0 이 맨 위. 읽을 때마다 새 목록이다 — 자주 읽는 자리는 [cell] 을 쓴다. */
    val board: List<List<Piece?>> get() = List(totalRows) { r -> List(columns) { c -> cells[r * columns + c] } }

    fun cell(row: Int, column: Int): Piece? = cells[row * columns + column]

    /** 넥스트 큐. 언제나 [nextCount] 개를 채워 둔다. */
    val next: List<Piece> get() = nextQueue.toList()

    /** 들어올 방해 줄 묶음들(도착 순서). */
    val pendingGarbage: List<Int> get() = pendingQueue.toList()

    /** 방해 줄 칸 표시(행마다 bit c = c열 — 그림·인코딩 전용). Swift `[UInt16]`. */
    val garbageMask: List<Int> get() = garbageRows.toList()

    // MARK: - 읽기

    val level: Int get() = level(forAdvance = advance)
    /** 난이도가 실제로 읽는 레벨 = max(level, levelFloor). */
    val difficultyLevel: Int get() = maxOf(level, levelFloor)
    val pendingGarbageLines: Int get() = pendingQueue.sum()

    fun isGarbage(row: Int, column: Int): Boolean {
        if (row < 0 || row >= totalRows || column < 0 || column >= columns) return false
        return (garbageRows[row] and (1 shl column)) != 0
    }

    val scoreLevel: Int get() = scoreLevel(forLevel = level)

    val advanceToNextLevel: Int
        get() {
            val step = if (advance < advanceAtGravityCap) 20 else 50
            val base = if (advance < advanceAtGravityCap) 0 else advanceAtGravityCap
            return step - (advance - base) % step
        }

    val isPlaying: Boolean
        get() = when (phase) {
            Phase.Running, is Phase.LineClear, is Phase.Are, is Phase.Over -> true
            Phase.Ready, Phase.Result -> false
        }

    val isGameOver: Boolean
        get() = when (phase) {
            is Phase.Over, Phase.Result -> true
            else -> false
        }

    /** 고스트(지금 하드드롭하면 앉을 자리) — 그리기·조준 전용. */
    val ghost: ActivePiece?
        get() {
            var candidate = active ?: return null
            while (true) {
                val down = candidate.copy(row = candidate.row + 1)
                if (!fits(down)) return candidate
                candidate = down
            }
        }

    /** 지금 접지(한 칸도 못 내려감) 상태인가. */
    val isGrounded: Boolean
        get() {
            val a = active ?: return false
            return !fits(a.copy(row = a.row + 1))
        }

    // MARK: - 만들기

    /** 시드에서 새 판(준비 상태). */
    constructor(seed: ULong) : this(
        cells = arrayOfNulls(totalRows * columns),
        active = null,
        next = mutableListOf(),
        heldPiece = null,
        holdUsed = false,
        score = 0,
        advance = 0,
        lines = 0,
        combo = -1,
        backToBack = -1,
        phase = Phase.Ready,
        elapsed = 0.0,
        lastClear = null,
        pendingGarbage = mutableListOf(),
        attackSentTotal = 0,
        garbageRows = IntArray(totalRows),
        levelFloor = 1,
        rng = MiniGameRandom(seed),
        bag = mutableListOf(),
        repeatCountdown = null,
        repeatDirection = 0,
        leftHeld = false,
        rightHeld = false,
        softDropHeld = false,
        fallCountdown = gravitySecondsForLevel(1),
        groundedSeconds = 0.0,
        groundedTotalSeconds = 0.0,
        lockResets = 0,
        lowestRow = -1,
        lastActionWasRotation = false,
        lastKickWasFinal = false,
        garbageRng = MiniGameRandom(seed xor garbageSeedSalt),
        garbageHeadHole = null,
    )

    /**
     * 픽스처 — 임의 상태에서 시작한다(난수는 seed). Swift 의 둘째 init 과 같은 인자·기본값이다.
     * 판은 40×10 으로 맞추고(모자라면 위를 비우고 넘치면 위를 버린다), 넥스트를 채우고, 낙하 시계·가장 낮은 줄을 맞춘다.
     */
    constructor(
        seed: ULong,
        board: List<List<Piece?>>,
        active: ActivePiece?,
        phase: Phase = Phase.Running,
        next: List<Piece> = emptyList(),
        heldPiece: Piece? = null,
        holdUsed: Boolean = false,
        score: Int = 0,
        advance: Int = 0,
        lines: Int = 0,
        combo: Int = -1,
        backToBack: Int = -1,
        elapsed: Double = 0.0,
        softDropHeld: Boolean = false,
        pendingGarbage: List<Int> = emptyList(),
        attackSentTotal: Int = 0,
        garbageMask: List<Int> = emptyList(),
        levelFloor: Int = 1,
    ) : this(seed) {
        this.cells = normalized(board)
        this.active = active
        this.phase = phase
        this.nextQueue.clear()
        this.nextQueue.addAll(next)
        this.heldPiece = heldPiece
        this.holdUsed = holdUsed
        this.score = score
        this.advance = advance
        this.lines = lines
        this.combo = combo
        this.backToBack = backToBack
        this.elapsed = elapsed
        this.softDropHeld = softDropHeld
        this.pendingQueue.clear()
        this.pendingQueue.addAll(pendingGarbage.filter { it > 0 })
        this.attackSentTotal = maxOf(0, attackSentTotal)
        this.garbageRows = normalizedMask(garbageMask)
        this.levelFloor = clampedLevelFloor(levelFloor)
        refillNext()
        fallCountdown = fallInterval
        lowestRow = active?.let { bottomRow(it) } ?: -1
    }

    /** Swift 값 복사와 같은 뜻의 깊은 복제(난수 상태까지). */
    fun copy(): TetrisGame = TetrisGame(
        cells = cells.copyOf(),
        active = active,
        next = nextQueue.toMutableList(),
        heldPiece = heldPiece,
        holdUsed = holdUsed,
        score = score,
        advance = advance,
        lines = lines,
        combo = combo,
        backToBack = backToBack,
        phase = phase,
        elapsed = elapsed,
        lastClear = lastClear,
        pendingGarbage = pendingQueue.toMutableList(),
        attackSentTotal = attackSentTotal,
        garbageRows = garbageRows.copyOf(),
        levelFloor = levelFloor,
        rng = rng.copy(),
        bag = bag.toMutableList(),
        repeatCountdown = repeatCountdown,
        repeatDirection = repeatDirection,
        leftHeld = leftHeld,
        rightHeld = rightHeld,
        softDropHeld = softDropHeld,
        fallCountdown = fallCountdown,
        groundedSeconds = groundedSeconds,
        groundedTotalSeconds = groundedTotalSeconds,
        lockResets = lockResets,
        lowestRow = lowestRow,
        lastActionWasRotation = lastActionWasRotation,
        lastKickWasFinal = lastKickWasFinal,
        garbageRng = garbageRng.copy(),
        garbageHeadHole = garbageHeadHole,
    )

    /**
     * Swift `==` 와 같은 칸: 난수 상태(조각·구멍)는 비교하지 않고 나머지는 **내부 시계까지 전부** 본다
     * (접지 시계 하나가 갈라져도 다음 프레임의 결과가 갈린다).
     */
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is TetrisGame) return false
        return cells.contentEquals(other.cells) && active == other.active && nextQueue == other.nextQueue &&
            heldPiece == other.heldPiece && holdUsed == other.holdUsed &&
            score == other.score && advance == other.advance && lines == other.lines &&
            combo == other.combo && backToBack == other.backToBack &&
            phase == other.phase && elapsed == other.elapsed && lastClear == other.lastClear &&
            bag == other.bag &&
            repeatCountdown == other.repeatCountdown && repeatDirection == other.repeatDirection &&
            leftHeld == other.leftHeld && rightHeld == other.rightHeld &&
            softDropHeld == other.softDropHeld && fallCountdown == other.fallCountdown &&
            groundedSeconds == other.groundedSeconds && groundedTotalSeconds == other.groundedTotalSeconds &&
            lockResets == other.lockResets && lowestRow == other.lowestRow &&
            lastActionWasRotation == other.lastActionWasRotation &&
            lastKickWasFinal == other.lastKickWasFinal &&
            pendingQueue == other.pendingQueue && attackSentTotal == other.attackSentTotal &&
            garbageRows.contentEquals(other.garbageRows) && levelFloor == other.levelFloor &&
            garbageHeadHole == other.garbageHeadHole
    }

    override fun hashCode(): Int = 31 * cells.contentHashCode() + score * 17 + advance

    // MARK: - 입력

    /** 액션. ready/result 면 새 판, running 이면 하드드롭, 그 밖(텀·유예)에서는 아무 일도 없다. */
    fun action() {
        when (phase) {
            Phase.Ready, Phase.Result -> startRound()
            Phase.Running -> hardDrop()
            is Phase.LineClear, is Phase.Are, is Phase.Over -> return
        }
    }

    /** 왼쪽 눌림/뗌. 뗌은 멱등이다. */
    fun setLeftHeld(held: Boolean) {
        if (held == leftHeld) return
        leftHeld = held
        updateRepeat(pressed = if (held) -1 else null, released = if (held) null else -1)
    }

    fun setRightHeld(held: Boolean) {
        if (held == rightHeld) return
        rightHeld = held
        updateRepeat(pressed = if (held) 1 else null, released = if (held) null else 1)
    }

    /** 소프트드롭 눌림/뗌. 누르는 순간 다음 칸까지 남은 시간을 새 간격으로 줄인다. */
    fun setSoftDropHeld(held: Boolean) {
        if (held == softDropHeld) return
        softDropHeld = held
        fallCountdown = swiftMin(fallCountdown, fallInterval)
    }

    /**
     * 소프트드롭 **한 칸**(폰 끌기). 한 칸만 내려가고 못 내려가면 아무것도 안 한다(굳히지 않는다). 칸당 1점.
     * 접지 리셋 예산을 쓰지 않는다(중력과 같은 뜻). 끝에 낙하 시계를 되감는다(공짜 중력 한 칸 방지).
     */
    fun softDropOneCell(): Boolean {
        if (phase != Phase.Running) return false
        val current = active ?: return false
        val candidate = current.copy(row = current.row + 1)
        if (!fits(candidate)) return false
        active = candidate
        lastActionWasRotation = false
        addScore(1)
        noteNewLowestRow()
        fallCountdown = fallInterval
        return true
    }

    /** 회전. 성공하면 접지 리셋을 한 번 쓴다. */
    fun rotate(clockwise: Boolean) {
        if (phase != Phase.Running) return
        val current = active ?: return
        val target = if (clockwise) current.rotation.clockwise else current.rotation.counterClockwise
        val offsets = kicks(current.piece, current.rotation, target)
        for ((index, offset) in offsets.withIndex()) {
            val candidate = current.copy(rotation = target, column = current.column + offset.dx, row = current.row - offset.dy)
            if (!fits(candidate)) continue
            active = candidate
            lastActionWasRotation = true
            lastKickWasFinal = index == offsets.size - 1
            registerPlacementAction()
            return
        }
    }

    /** 홀드(조각당 1회). 접지 총량 예산은 이어진다(한 번의 배치에 붙는다). 리셋 횟수는 새로 준다. */
    fun holdCurrentPiece() {
        if (phase != Phase.Running) return
        val current = active ?: return
        if (holdUsed) return
        val incoming = heldPiece ?: takeFromQueue()
        heldPiece = current.piece
        holdUsed = true
        spawn(incoming, fromHold = true)
    }

    /** v0.3.60 대결: 상대 공격 [lines] 줄을 대기열 끝에 묶음 하나로 받는다. 진행 중(조각·텀)일 때만 — 받아들였으면 true. */
    fun receiveGarbage(lines: Int): Boolean {
        if (lines <= 0) return false
        return when (phase) {
            Phase.Running, is Phase.LineClear, is Phase.Are -> {
                pendingQueue.add(lines)
                true
            }
            Phase.Ready, is Phase.Over, Phase.Result -> false
        }
    }

    /** v0.3.60 대결: 가속 바닥. 1 = 꺼짐, [maxLevelFloor] 에서 자른다. */
    fun setLevelFloor(floor: Int) {
        levelFloor = clampedLevelFloor(floor)
    }

    /** 허브가 판을 끊을 때. 진행 중이면 그 점수로 결과 확정. 포커스 상실은 여기로 안 온다(v0.3.62 — 멈춤). */
    fun interrupt() {
        when (phase) {
            Phase.Running, is Phase.LineClear, is Phase.Are, is Phase.Over -> {
                phase = Phase.Result
                releaseAllKeys()
            }
            Phase.Ready, Phase.Result -> Unit
        }
    }

    fun releaseAllKeys() {
        leftHeld = false
        rightHeld = false
        softDropHeld = false
        repeatDirection = 0
        repeatCountdown = null
    }

    // MARK: - 한 걸음

    /**
     * 한 프레임. 첫 줄이 dt 클램프(1/20)다. 안에서는 dt 를 사건 사이로 잘라 흘리고(자동 반복 · 낙하 · 접지 만료),
     * 자른 조각의 남은 시간은 다음 단계로 넘긴다 — 24fps 와 119fps 가 같은 판을 낸다.
     */
    fun step(dt: Double) {
        val clamped = swiftMin(swiftMax(0.0, dt), maxStep)
        if (!(clamped > 0)) return
        var remaining = clamped
        while (remaining > 1e-12) {
            when (val p = phase) {
                Phase.Ready, Phase.Result -> return
                is Phase.Over -> {
                    val used = swiftMin(remaining, p.hold)
                    remaining -= used
                    phase = if (p.hold - used <= 0) Phase.Result else Phase.Over(p.hold - used)
                    if (phase == Phase.Result) return
                }
                is Phase.LineClear -> {
                    val used = swiftMin(remaining, p.remaining)
                    elapsed += used
                    remaining -= used
                    advanceRepeatClock(used)
                    phase = if (p.remaining - used <= 0) Phase.Are(areSeconds) else Phase.LineClear(p.remaining - used)
                }
                is Phase.Are -> {
                    val used = swiftMin(remaining, p.remaining)
                    elapsed += used
                    remaining -= used
                    advanceRepeatClock(used)
                    if (p.remaining - used <= 0) {
                        spawn(takeFromQueue(), fromHold = false)
                    } else {
                        phase = Phase.Are(p.remaining - used)
                    }
                }
                Phase.Running -> remaining = advanceRunning(remaining)
            }
        }
    }

    // MARK: - 진행 중 한 조각

    /** `.running` 동안 dt 를 사건 사이로 잘라 흘린다. 조각이 굳으면 쓰지 않은 시간을 돌려준다. */
    private fun advanceRunning(dt: Double): Double {
        var remaining = dt
        while (remaining > 1e-12) {
            if (active == null) return remaining
            fallCountdown = swiftMin(fallCountdown, fallInterval)
            val grounded = isGrounded
            if (grounded) {
                if (lockResets >= lockResetLimit(forLevel = difficultyLevel)) {
                    lockPiece()
                    return remaining
                }
                val untilLock = swiftMin(
                    lockDelaySeconds(forLevel = difficultyLevel) - groundedSeconds,
                    maxGroundedSeconds - groundedTotalSeconds,
                )
                if (untilLock <= 0) {
                    lockPiece()
                    return remaining
                }
                val slice = swiftMax(0.0, swiftMin(remaining, swiftMin(untilLock, repeatCountdown ?: Double.POSITIVE_INFINITY)))
                remaining -= slice
                elapsed += slice
                groundedSeconds += slice
                groundedTotalSeconds += slice
                advanceRepeatClock(slice)
                fireDueRepeat()
            } else {
                groundedSeconds = 0.0
                val slice = swiftMax(0.0, swiftMin(remaining, swiftMin(fallCountdown, repeatCountdown ?: Double.POSITIVE_INFINITY)))
                remaining -= slice
                elapsed += slice
                fallCountdown -= slice
                advanceRepeatClock(slice)
                fireDueRepeat()
                if (fallCountdown <= 0) {
                    fallOneCell()
                    fallCountdown = fallInterval
                }
            }
            if (phase != Phase.Running) return remaining
        }
        return 0.0
    }

    /** 지금 조각이 한 칸 떨어지는 데 걸리는 시간. 소프트드롭이 눌려 있으면 중력의 1/20. */
    private val fallInterval: Double
        get() = if (softDropHeld) softDropSeconds(forLevel = difficultyLevel) else gravitySecondsForLevel(difficultyLevel)

    /** DAS/ARR 시계만 흘린다(조각이 없는 동안에도 — 입력은 쌓이지 않는다). */
    private fun advanceRepeatClock(dt: Double) {
        val countdown = repeatCountdown ?: return
        repeatCountdown = swiftMax(0.0, countdown - dt)
    }

    /** 자동 반복이 만기면 한 칸 옮긴다(막혀 있어도 시계는 다시 감긴다). */
    private fun fireDueRepeat() {
        val countdown = repeatCountdown ?: return
        if (!(countdown <= 0) || repeatDirection == 0) return
        repeatCountdown = arrSeconds
        if (phase != Phase.Running || active == null) return
        shift(repeatDirection)
    }

    /** 방향키 상태가 바뀔 때 자동 반복을 다시 잡는다. 새로 누른 쪽이 이긴다. 뗌에서는 즉시 이동을 주지 않는다. */
    private fun updateRepeat(pressed: Int?, released: Int?) {
        if (pressed != null) {
            repeatDirection = pressed
            repeatCountdown = dasSeconds
            if (phase == Phase.Running && active != null) shift(pressed)
            return
        }
        if (released == null || released != repeatDirection) return
        if (leftHeld) {
            repeatDirection = -1
            repeatCountdown = dasSeconds
        } else if (rightHeld) {
            repeatDirection = 1
            repeatCountdown = dasSeconds
        } else {
            repeatDirection = 0
            repeatCountdown = null
        }
    }

    /** 가로 한 칸. 성공하면 접지 리셋을 한 번 쓴다. */
    private fun shift(dx: Int): Boolean {
        val current = active ?: return false
        val candidate = current.copy(column = current.column + dx)
        if (!fits(candidate)) return false
        active = candidate
        lastActionWasRotation = false
        registerPlacementAction()
        return true
    }

    /** 중력·소프트드롭 한 칸. */
    private fun fallOneCell() {
        val current = active ?: return
        val candidate = current.copy(row = current.row + 1)
        if (!fits(candidate)) return
        active = candidate
        lastActionWasRotation = false
        if (softDropHeld) addScore(1)
        noteNewLowestRow()
    }

    /** 하드드롭 — 끝까지 떨어뜨리고 락딜레이 없이 굳힌다. 칸당 2점. 0칸이면 회전 표시를 지우지 않는다(T-스핀). */
    private fun hardDrop() {
        var candidate = active ?: return
        var dropped = 0
        while (true) {
            val down = candidate.copy(row = candidate.row + 1)
            if (!fits(down)) break
            candidate = down
            dropped += 1
        }
        active = candidate
        if (dropped > 0) {
            lastActionWasRotation = false
            addScore(2 * dropped)
        }
        lockPiece()
    }

    /** 이동·회전이 성공했을 때의 접지 리셋 회계(Extended Placement). */
    private fun registerPlacementAction() {
        val limit = lockResetLimit(forLevel = difficultyLevel)
        if (lockResets < limit) {
            lockResets += 1
            groundedSeconds = 0.0
        }
        noteNewLowestRow()
    }

    /** 가장 낮은 줄을 갱신했으면 리셋 예산을 재충전한다(L ≤ 15 에서만). */
    private fun noteNewLowestRow() {
        val a = active ?: return
        val bottom = bottomRow(a)
        if (bottom <= lowestRow) return
        lowestRow = bottom
        if (lockResetRefreshes(forLevel = difficultyLevel)) {
            lockResets = 0
            groundedSeconds = 0.0
        }
    }

    // MARK: - 굳히기

    private fun lockPiece() {
        val current = active ?: return
        val spin = detectSpin(current)
        // 행 범위만 막는다(열은 fits 가 먼저 거른다 — 여기서 또 막으면 불변식이 깨진 것을 조용히 삼킨다).
        for (c in current.cells) {
            if (c.row >= 0 && c.row < totalRows) cells[c.row * columns + c.column] = current.piece
        }
        active = null

        val cleared = clearFullRows()
        val difficult = isDifficult(cleared, spin)

        var b2bApplies = false
        if (cleared > 0) {
            if (difficult) {
                b2bApplies = backToBack >= 0
                backToBack += 1
            } else {
                backToBack = -1
            }
            combo += 1
        } else {
            combo = -1
        }

        val perfect = cleared > 0 && isBoardEmpty
        val points = placementPoints(cleared, spin, scoreLevel, b2bApplies, combo, perfect)
        addScore(points)

        val attack = attackLines(cleared)
        val canceled = cancelPendingGarbage(attack)
        attackSentTotal += attack - canceled

        lastClear = ClearEvent(cleared, spin, b2bApplies, perfect, points, elapsed, attack)

        advance += 1 + cleared
        lines += cleared

        holdUsed = false
        if (cleared == 0 && pendingQueue.isNotEmpty() && !insertPendingGarbage()) return
        phase = if (cleared > 0) Phase.LineClear(lineClearSeconds) else Phase.Are(areSeconds)
    }

    /** 대기열을 앞에서부터 [amount] 줄까지 깎는다. 실제로 깎은 줄 수를 돌려준다. */
    private fun cancelPendingGarbage(amount: Int): Int {
        var left = amount
        while (left > 0 && pendingQueue.isNotEmpty()) {
            val first = pendingQueue[0]
            if (first <= left) {
                left -= first
                pendingQueue.removeAt(0)
                garbageHeadHole = null
            } else {
                pendingQueue[0] = first - left
                left = 0
            }
        }
        return amount - left
    }

    /**
     * 대기열 앞에서부터 최대 [maxGarbageInsertPerLock] 줄을 판 바닥에 밀어 넣는다(묶음마다 구멍 한 열 · 같은 묶음은 같은 구멍).
     * 탑아웃 검사를 먼저 한다(맨 위 n행에 칸이 있으면 판을 건드리지 않고 끝낸다).
     */
    private fun insertPendingGarbage(): Boolean {
        val count = minOf(maxGarbageInsertPerLock, pendingGarbageLines)
        if (count <= 0) return true
        for (i in 0 until count * columns) {
            if (cells[i] != null) {
                phase = Phase.Over(overHold)
                releaseAllKeys()
                return false
            }
        }
        val holes = ArrayList<Int>(count)
        while (holes.size < count && pendingQueue.isNotEmpty()) {
            val first = pendingQueue[0]
            val hole = garbageHeadHole ?: (garbageRng.next() % columns.toULong()).toInt()
            val take = minOf(first, count - holes.size)
            repeat(take) { holes.add(hole) }
            if (take == first) {
                pendingQueue.removeAt(0)
                garbageHeadHole = null
            } else {
                pendingQueue[0] = first - take
                garbageHeadHole = hole
            }
        }
        val fullMask = (1 shl columns) - 1
        val n = holes.size
        val newCells = arrayOfNulls<Piece>(totalRows * columns)
        cells.copyInto(newCells, destinationOffset = 0, startIndex = n * columns, endIndex = totalRows * columns)
        for ((k, hole) in holes.withIndex()) {
            val row = totalRows - n + k
            for (c in 0 until columns) newCells[row * columns + c] = if (c == hole) null else Piece.i
        }
        cells = newCells
        val newMask = IntArray(totalRows)
        garbageRows.copyInto(newMask, destinationOffset = 0, startIndex = n, endIndex = totalRows)
        for ((k, hole) in holes.withIndex()) newMask[totalRows - n + k] = fullMask and (1 shl hole).inv()
        garbageRows = newMask
        return true
    }

    /** 3코너 규칙. 마지막 행동이 회전인 T 만 본다. */
    private fun detectSpin(piece: ActivePiece): Spin {
        if (piece.piece != Piece.t || !lastActionWasRotation) return Spin.none
        val centerRow = piece.row + 1
        val centerColumn = piece.column + 1
        val topLeft = isBlocked(centerRow - 1, centerColumn - 1)
        val topRight = isBlocked(centerRow - 1, centerColumn + 1)
        val bottomLeft = isBlocked(centerRow + 1, centerColumn - 1)
        val bottomRight = isBlocked(centerRow + 1, centerColumn + 1)
        val blocked = listOf(topLeft, topRight, bottomLeft, bottomRight).count { it }
        if (blocked < 3) return Spin.none
        val front = when (piece.rotation) {
            Rotation.spawn -> topLeft to topRight
            Rotation.right -> topRight to bottomRight
            Rotation.flip -> bottomLeft to bottomRight
            Rotation.left -> topLeft to bottomLeft
        }
        if (front.first && front.second) return Spin.full
        return if (lastKickWasFinal) Spin.full else Spin.mini
    }

    /** 꽉 찬 줄을 지우고 위를 내린다(방해 줄 표시도 같은 술어로 거른다). 지운 줄 수를 돌려준다. */
    private fun clearFullRows(): Int {
        val keptRows = ArrayList<Int>(totalRows)
        var cleared = 0
        for (r in 0 until totalRows) {
            var full = true
            for (c in 0 until columns) if (cells[r * columns + c] == null) { full = false; break }
            if (full) cleared += 1 else keptRows.add(r)
        }
        if (cleared == 0) return 0
        val newCells = arrayOfNulls<Piece>(totalRows * columns)
        val newMask = IntArray(totalRows)
        for ((k, r) in keptRows.withIndex()) {
            val dest = cleared + k
            cells.copyInto(newCells, destinationOffset = dest * columns, startIndex = r * columns, endIndex = (r + 1) * columns)
            newMask[dest] = garbageRows[r]
        }
        cells = newCells
        garbageRows = newMask
        return cleared
    }

    private val isBoardEmpty: Boolean get() = cells.all { it == null }

    // MARK: - 조각 내보내기

    /** 새 판. 난수만 이어 받고 나머지는 전부 처음 값으로 돌린다. */
    private fun startRound() {
        cells = arrayOfNulls(totalRows * columns)
        active = null
        nextQueue.clear()
        bag.clear()
        heldPiece = null
        holdUsed = false
        score = 0
        advance = 0
        lines = 0
        combo = -1
        backToBack = -1
        elapsed = 0.0
        lastClear = null
        releaseAllKeys()
        groundedSeconds = 0.0
        groundedTotalSeconds = 0.0
        lockResets = 0
        lowestRow = -1
        lastActionWasRotation = false
        lastKickWasFinal = false
        pendingQueue.clear()
        attackSentTotal = 0
        garbageRows = IntArray(totalRows)
        garbageHeadHole = null
        levelFloor = 1
        phase = Phase.Running
        spawn(takeFromQueue(), fromHold = false)
    }

    /**
     * 새 조각을 스폰 자리에 놓는다. 스폰 4칸 중 하나라도 막혀 있으면 블록아웃으로 끝난다(겹친 조각을 그대로 남긴다).
     * [fromHold] 는 접지 예산의 주인을 가른다(홀드로 갈아탄 조각은 같은 배치).
     */
    private fun spawn(piece: Piece, fromHold: Boolean) {
        val candidate = ActivePiece(piece, Rotation.spawn, spawnColumn, spawnRow)
        active = candidate
        groundedSeconds = 0.0
        if (!fromHold) groundedTotalSeconds = 0.0
        lockResets = 0
        lowestRow = bottomRow(candidate)
        lastActionWasRotation = false
        lastKickWasFinal = false
        fallCountdown = fallInterval
        if (!fits(candidate)) {
            phase = Phase.Over(overHold)
            releaseAllKeys()
            return
        }
        phase = Phase.Running
    }

    private fun takeFromQueue(): Piece {
        refillNext()
        val piece = nextQueue.removeAt(0)
        refillNext()
        return piece
    }

    /** 7-bag: 봉지가 비면 7종을 새로 섞는다. */
    private fun refillNext() {
        while (nextQueue.size < nextCount) {
            if (bag.isEmpty()) bag.addAll(shuffledBag(rng))
            nextQueue.add(bag.removeAt(0))
        }
    }

    // MARK: - 판 질의

    /** 조각이 판 안에 들어가고 굳은 칸과 겹치지 않는가. */
    fun fits(piece: ActivePiece): Boolean {
        for (o in shape(piece.piece, piece.rotation)) {
            val row = piece.row + o.dy
            val column = piece.column + o.dx
            if (column < 0 || column >= columns || row >= totalRows) return false
            if (row < 0) return false
            if (cells[row * columns + column] != null) return false
        }
        return true
    }

    /** T-스핀 모서리 판정용. 판 밖은 막힌 것으로 센다. */
    private fun isBlocked(row: Int, column: Int): Boolean {
        if (row < 0 || row >= totalRows || column < 0 || column >= columns) return true
        return cells[row * columns + column] != null
    }

    /** 점수는 언제나 [maxScore] 에서 잘린다. */
    private fun addScore(points: Int) {
        score = minOf(maxScore, score + maxOf(0, points))
    }

    companion object {
        /** 표준 10×40. 아래 20행만 보이고 위 20행은 버퍼다. */
        const val columns: Int = 10
        const val totalRows: Int = 40
        const val visibleRows: Int = 20
        const val firstVisibleRow: Int = totalRows - visibleRows
        const val spawnRow: Int = 18
        const val spawnColumn: Int = 3
        const val nextCount: Int = 5

        /** dt 상한 1/20(기존 두 게임의 1/30 과 일부러 다르다 — 24Hz 화면에서 판이 실시간의 80% 로 돌지 않게). */
        const val maxStep: Double = 1.0 / 20.0
        const val dasSeconds: Double = 0.167
        const val arrSeconds: Double = 0.033

        /**
         * 조각 사이 텀(레벨과 무관하게 고정).
         *
         * INV-TetrisGame-5818f66b 이식: 이 값과 [lineClearSeconds] 가 서버 시간 하한 `minigame_min_seconds('tetris', …)` 의
         * **유일한 뿌리다**. 바꾸면 그 SQL 도 같이(서버 대조는 맥 로컬 계약 시험 — C§5.6. Kotlin 은 골든 `tetris/rules` 로 Swift 값과 묶인다).
         */
        const val areSeconds: Double = 0.100

        /** INV-TetrisGame-95dd2f28 이식: 줄소거 정지 — 지운 줄 수와 무관하게 고정(위 [areSeconds] 와 한 벌, 서버 하한의 뿌리). */
        const val lineClearSeconds: Double = 0.500
        const val overHold: Double = 0.4

        /**
         * 조각당 접지 총 체류 시간의 상한.
         *
         * INV-TetrisGame-5ed72a43 이식: 선택적 보험이 아니라 **필수 상수**다(빼면 고의 늘어뜨리기 상계가 24.7분 → 71.0분).
         * 예산은 조각이 아니라 한 번의 배치에 붙는다(홀드로 갈아타도 이어진다 — [holdCurrentPiece]).
         */
        const val maxGroundedSeconds: Double = 1.00
        const val advanceAtGravityCap: Int = 280
        const val scoreLevelCap: Int = 30

        /** 엔진 점수 상한. [com.yehsung.aingcheck.core.rules.minigame.MiniGameKind.tetris] 의 maxScore 와 같다. */
        const val maxScore: Int = 100_000_000

        // v0.3.60 1:1 대결 상수(기본값 = 꺼짐 — 솔로 판은 비트 그대로)
        const val maxGarbageInsertPerLock: Int = 8
        const val maxLevelFloor: Int = 30

        /** 방해 줄 구멍 난수의 시드 소금 — 조각 난수와 다른 스트림이어야 한다. */
        private const val garbageSeedSalt: ULong = 0x6A09E667F3BCC909uL

        /**
         * 중력 표(초/칸) — Swift `gravitySeconds(forStage: 1…20)` = Darwin `pow(0.8 − 0.007·(E−1), E−1)` 의 **비트**.
         * Kotlin 은 pow 를 부르지 않는다(G §8-14: `Math.pow` 는 aarch64·amd64 JVM 끼리도, Darwin 과도 단계 18 에서 1ulp 갈린다 —
         * W0-b C-X1 실측). 표 값은 골든 `tetris/rules` 의 `gravitySecondsBits` 와 시험이 비트로 대조한다.
         */
        val GRAVITY_SECONDS_BITS: LongArray = longArrayOf(
            0x3ff0000000000000L, 0x3fe9604189374bc7L, 0x3fe3c4fc1df3300eL, 0x3fde4131b7f7c25eL, 0x3fd6bb8be59ff28aL,
            0x3fd0c4aa89a5e27cL, 0x3fc847580ebfec1dL, 0x3fc13efcd73e7cf2L, 0x3fb808aac4b7f144L, 0x3fb06c3cff639f17L,
            0x3fa600fbefc7ca72L, 0x3f9ce5184d4d1360L, 0x3f9296c941a1be2bL, 0x3f876d828a2366a0L, 0x3f7ce97edd2eceafL,
            0x3f7176a9daf17423L, 0x3f64a4ffc76e4356L, 0x3f57dfaecd02a35fL, 0x3f4aff6e95f09144L, 0x3f3dd84e47b9ce37L,
        )
        private val GRAVITY_SECONDS: DoubleArray = DoubleArray(20) { Double.fromBits(GRAVITY_SECONDS_BITS[it]) }

        /** 공격 표(사용자 확정 2026-10-20): 1줄 0 · 2줄 1 · 3줄 2 · 4줄 4. */
        fun attackLines(lines: Int): Int = when {
            lines < 2 -> 0
            lines == 2 -> 1
            lines == 3 -> 2
            else -> 4
        }

        /** advance → 레벨(정수 나눗셈). 280 앞은 20 마다, 뒤는 50 마다. */
        fun level(forAdvance: Int): Int {
            val a = maxOf(0, forAdvance)
            if (a < advanceAtGravityCap) return 1 + a / 20
            return 15 + (a - advanceAtGravityCap) / 50
        }

        /** 점수 배수·화면 표시 레벨(1…30). 난이도 함수는 이 값을 쓰지 않는다. */
        fun scoreLevel(forLevel: Int): Int = minOf(maxOf(1, forLevel), scoreLevelCap)

        /** 레벨 → 표준 중력 공식의 지수 단계(4 + level, 19 에서 멈춤). */
        fun gravityStage(forLevel: Int): Int = minOf(4 + maxOf(1, forLevel), 19)

        /**
         * 중력(초/칸). 표준 공식 `(0.8 − 0.007·(E−1))^(E−1)` 을 단계 1…20 비트 표로 읽는다.
         *
         * INV-TetrisGame-9a29a22a 이식: `min(stage, 20)` 클램프는 장식이 아니다(밑이 E = 116 부터 음수 · E = 115 는 언더플로).
         * 표가 1…20 뿐이라 클램프가 곧 표의 범위다 — 식이 있는 곳(여기)에 그대로 둔다.
         */
        fun gravitySeconds(forStage: Int): Double = GRAVITY_SECONDS[minOf(maxOf(forStage, 1), 20) - 1]

        /** Swift `gravitySeconds(forLevel:)`(Kotlin 은 인자 이름으로 겹쳐 쓸 수 없어 이름에 붙였다). */
        fun gravitySecondsForLevel(level: Int): Double = gravitySeconds(forStage = gravityStage(forLevel = level))

        /** 소프트드롭(초/칸) — 중력의 20배. */
        fun softDropSeconds(forLevel: Int): Double = gravitySecondsForLevel(forLevel) / 20

        /** 락딜레이(초). 0.50(L≤15) → 0.16(L≥30) 선형. */
        fun lockDelaySeconds(forLevel: Int): Double {
            if (forLevel <= 15) return 0.50
            if (forLevel >= 30) return 0.16
            return 0.50 + (0.16 - 0.50) * (forLevel - 15).toDouble() / 15.0
        }

        /**
         * 접지 리셋 한도. 15(L≤15) → 2(L≥28) 선형(Swift `.rounded()` — 0.5 는 0 에서 먼 쪽).
         *
         * INV-TetrisGame-86145117 이식: **이 축이 판을 끝낸다** — 20G 에서 한도 2 면 어느 벽에도 못 닿아 1·10열이 영구히 비고
         * 남은 빈칸 ÷ 4 조각 안에 탑아웃이다. 횟수라서 주사율과 무관하다(시간으로 막으면 저주사율이 순위를 가른다).
         */
        fun lockResetLimit(forLevel: Int): Int {
            if (forLevel <= 15) return 15
            if (forLevel >= 28) return 2
            return (15.0 + (2.0 - 15.0) * (forLevel - 15).toDouble() / 13.0).roundedHalfAwayFromZero().toInt()
        }

        /** 가장 낮은 줄을 갱신하면 리셋 재충전 — L > 15 에서는 끈다. */
        fun lockResetRefreshes(forLevel: Int): Boolean = forLevel <= 15

        /** 행동 점수(레벨 배수 전). */
        fun actionPoints(lines: Int, spin: Spin = Spin.none): Int = when (spin) {
            Spin.none -> when (lines) { 1 -> 100; 2 -> 300; 3 -> 500; 4 -> 800; else -> 0 }
            Spin.full -> when (lines) { 0 -> 400; 1 -> 800; 2 -> 1200; 3 -> 1600; else -> 0 }
            Spin.mini -> when (lines) { 0 -> 100; 1 -> 200; 2 -> 400; else -> 0 }
        }

        /** '어려운 소거' — 테트리스와 모든 T-스핀 줄소거. */
        fun isDifficult(lines: Int, spin: Spin): Boolean {
            if (lines == 4) return true
            return lines > 0 && spin != Spin.none
        }

        /** 퍼펙트 클리어 보너스(레벨 배수 전). */
        fun perfectClearPoints(lines: Int, backToBackTetris: Boolean): Int {
            if (lines == 4 && backToBackTetris) return 3200
            return when (lines) { 1 -> 800; 2 -> 1200; 3 -> 1800; 4 -> 2000; else -> 0 }
        }

        /** 콤보 점수 = 50 × 콤보수 × 레벨. */
        fun comboPoints(combo: Int, scoreLevel: Int): Int = maxOf(0, combo) * 50 * scoreLevel

        /** 한 배치가 만드는 점수 전부(드롭 점수 제외). B2B 배수는 행동 점수에만 `× 3 / 2`(정수). */
        fun placementPoints(lines: Int, spin: Spin, scoreLevel: Int, backToBack: Boolean, combo: Int, perfectClear: Boolean): Int {
            var points = actionPoints(lines, spin) * scoreLevel
            if (backToBack) points = points * 3 / 2
            if (perfectClear) points += perfectClearPoints(lines, backToBack && lines == 4) * scoreLevel
            points += comboPoints(combo, scoreLevel)
            return points
        }

        private val SHAPES: Array<Array<List<Offset>>> = Array(7) { p ->
            Array(4) { r -> shapeOf(Piece.entries[p], Rotation.entries[r]) }
        }

        /** 바운딩 상자 안의 네 칸(dx = 열, dy = 행). */
        fun shape(piece: Piece, rotation: Rotation): List<Offset> = SHAPES[piece.ordinal][rotation.ordinal]

        private fun shapeOf(piece: Piece, rotation: Rotation): List<Offset> {
            fun o(vararg xy: Int): List<Offset> = (xy.indices step 2).map { Offset(xy[it], xy[it + 1]) }
            return when (piece) {
                Piece.i -> when (rotation) {
                    Rotation.spawn -> o(0, 1, 1, 1, 2, 1, 3, 1)
                    Rotation.right -> o(2, 0, 2, 1, 2, 2, 2, 3)
                    Rotation.flip -> o(0, 2, 1, 2, 2, 2, 3, 2)
                    Rotation.left -> o(1, 0, 1, 1, 1, 2, 1, 3)
                }
                Piece.j -> when (rotation) {
                    Rotation.spawn -> o(0, 0, 0, 1, 1, 1, 2, 1)
                    Rotation.right -> o(1, 0, 2, 0, 1, 1, 1, 2)
                    Rotation.flip -> o(0, 1, 1, 1, 2, 1, 2, 2)
                    Rotation.left -> o(1, 0, 1, 1, 0, 2, 1, 2)
                }
                Piece.l -> when (rotation) {
                    Rotation.spawn -> o(2, 0, 0, 1, 1, 1, 2, 1)
                    Rotation.right -> o(1, 0, 1, 1, 1, 2, 2, 2)
                    Rotation.flip -> o(0, 1, 1, 1, 2, 1, 0, 2)
                    Rotation.left -> o(0, 0, 1, 0, 1, 1, 1, 2)
                }
                Piece.o -> o(1, 0, 2, 0, 1, 1, 2, 1)
                Piece.s -> when (rotation) {
                    Rotation.spawn -> o(1, 0, 2, 0, 0, 1, 1, 1)
                    Rotation.right -> o(1, 0, 1, 1, 2, 1, 2, 2)
                    Rotation.flip -> o(1, 1, 2, 1, 0, 2, 1, 2)
                    Rotation.left -> o(0, 0, 0, 1, 1, 1, 1, 2)
                }
                Piece.t -> when (rotation) {
                    Rotation.spawn -> o(1, 0, 0, 1, 1, 1, 2, 1)
                    Rotation.right -> o(1, 0, 1, 1, 2, 1, 1, 2)
                    Rotation.flip -> o(0, 1, 1, 1, 2, 1, 1, 2)
                    Rotation.left -> o(1, 0, 0, 1, 1, 1, 1, 2)
                }
                Piece.z -> when (rotation) {
                    Rotation.spawn -> o(0, 0, 1, 0, 1, 1, 2, 1)
                    Rotation.right -> o(2, 0, 1, 1, 2, 1, 1, 2)
                    Rotation.flip -> o(0, 1, 1, 1, 1, 2, 2, 2)
                    Rotation.left -> o(1, 0, 0, 1, 1, 1, 0, 2)
                }
            }
        }

        /** SRS 월킥표. y 양수 = 위(판 행에는 `- dy` 로 적용). 5번째(마지막)로 성공한 T 회전은 완전 T-스핀. 180° 없음. */
        fun kicks(piece: Piece, from: Rotation, to: Rotation): List<Offset> {
            fun k(vararg xy: Int): List<Offset> = (xy.indices step 2).map { Offset(xy[it], xy[it + 1]) }
            if (piece == Piece.o) return k(0, 0)
            val key = from.rawValue to to.rawValue
            if (piece == Piece.i) {
                return when (key) {
                    0 to 1 -> k(0, 0, -2, 0, 1, 0, -2, -1, 1, 2)
                    1 to 0 -> k(0, 0, 2, 0, -1, 0, 2, 1, -1, -2)
                    1 to 2 -> k(0, 0, -1, 0, 2, 0, -1, 2, 2, -1)
                    2 to 1 -> k(0, 0, 1, 0, -2, 0, 1, -2, -2, 1)
                    2 to 3 -> k(0, 0, 2, 0, -1, 0, 2, 1, -1, -2)
                    3 to 2 -> k(0, 0, -2, 0, 1, 0, -2, -1, 1, 2)
                    3 to 0 -> k(0, 0, 1, 0, -2, 0, 1, -2, -2, 1)
                    0 to 3 -> k(0, 0, -1, 0, 2, 0, -1, 2, 2, -1)
                    else -> k(0, 0)
                }
            }
            return when (key) {
                0 to 1 -> k(0, 0, -1, 0, -1, 1, 0, -2, -1, -2)
                1 to 0 -> k(0, 0, 1, 0, 1, -1, 0, 2, 1, 2)
                1 to 2 -> k(0, 0, 1, 0, 1, -1, 0, 2, 1, 2)
                2 to 1 -> k(0, 0, -1, 0, -1, 1, 0, -2, -1, -2)
                2 to 3 -> k(0, 0, 1, 0, 1, 1, 0, -2, 1, -2)
                3 to 2 -> k(0, 0, -1, 0, -1, -1, 0, 2, -1, 2)
                3 to 0 -> k(0, 0, -1, 0, -1, -1, 0, 2, -1, 2)
                0 to 3 -> k(0, 0, 1, 0, 1, 1, 0, -2, 1, -2)
                else -> k(0, 0)
            }
        }

        /** 빈 판(40×10). */
        fun emptyBoard(): List<List<Piece?>> = List(totalRows) { List(columns) { null } }

        /**
         * 판 리터럴 픽스처. 한 줄이 한 행, `.` 은 빈 칸, `i j l o s t z`(대소문자)는 그 조각, 다른 글자는 `i`. 바닥에 붙는다.
         */
        fun boardFixture(bottomRows: List<String>): List<List<Piece?>> {
            val board = MutableList(totalRows) { MutableList<Piece?>(columns) { null } }
            val start = totalRows - bottomRows.size
            for ((offset, line) in bottomRows.withIndex()) {
                val row = start + offset
                if (row < 0 || row >= totalRows) continue
                for ((column, character) in line.withIndex()) {
                    if (column >= columns || character == '.') continue
                    board[row][column] = pieceForFixtureCharacter(character)
                }
            }
            return board
        }

        /** 방해 줄 표시 픽스처 — `G`·`g` 칸에만 비트. */
        fun garbageMaskFixture(bottomRows: List<String>): List<Int> {
            val mask = IntArray(totalRows)
            val start = totalRows - bottomRows.size
            for ((offset, line) in bottomRows.withIndex()) {
                val row = start + offset
                if (row < 0 || row >= totalRows) continue
                for ((column, character) in line.withIndex()) {
                    if (column < columns && (character == 'G' || character == 'g')) mask[row] = mask[row] or (1 shl column)
                }
            }
            return mask.toList()
        }

        private fun pieceForFixtureCharacter(character: Char): Piece = when (character) {
            'i', 'I' -> Piece.i
            'j', 'J' -> Piece.j
            'l', 'L' -> Piece.l
            'o', 'O' -> Piece.o
            's', 'S' -> Piece.s
            't', 'T' -> Piece.t
            'z', 'Z' -> Piece.z
            else -> Piece.i
        }

        /** 표시를 40행으로(모자라면 위를 0 으로, 넘치면 위를 버린다). 10비트 밖은 버린다. */
        private fun normalizedMask(mask: List<Int>): IntArray {
            val allColumns = (1 shl columns) - 1
            var rows = mask.map { it and allColumns and 0xFFFF }
            if (rows.size > totalRows) rows = rows.takeLast(totalRows)
            if (rows.size < totalRows) rows = List(totalRows - rows.size) { 0 } + rows
            return rows.toIntArray()
        }

        private fun clampedLevelFloor(floor: Int): Int = minOf(maxOf(1, floor), maxLevelFloor)

        /** 픽스처 판을 40×10 으로(모자라면 위를 비우고, 넘치면 위를 버린다). */
        private fun normalized(board: List<List<Piece?>>): Array<Piece?> {
            var rows = board.map { row ->
                when {
                    row.size < columns -> row + List(columns - row.size) { null }
                    row.size > columns -> row.take(columns)
                    else -> row
                }
            }
            if (rows.size > totalRows) rows = rows.takeLast(totalRows)
            if (rows.size < totalRows) rows = List(totalRows - rows.size) { List<Piece?>(columns) { null } } + rows
            val out = arrayOfNulls<Piece>(totalRows * columns)
            for (r in 0 until totalRows) for (c in 0 until columns) out[r * columns + c] = rows[r][c]
            return out
        }

        private fun bottomRow(piece: ActivePiece): Int = piece.cells.maxOfOrNull { it.row } ?: piece.row

        /** Fisher-Yates. `rng.next() % (index + 1)` 는 부호 없는 나머지다(부호 있는 % 면 조각열이 갈린다 — C§2.5). */
        fun shuffledBag(rng: MiniGameRandom): List<Piece> {
            val bag = Piece.entries.toMutableList()
            var index = bag.size - 1
            while (index > 0) {
                val pick = (rng.next() % (index + 1).toULong()).toInt()
                val tmp = bag[index]
                bag[index] = bag[pick]
                bag[pick] = tmp
                index -= 1
            }
            return bag
        }
    }
}
