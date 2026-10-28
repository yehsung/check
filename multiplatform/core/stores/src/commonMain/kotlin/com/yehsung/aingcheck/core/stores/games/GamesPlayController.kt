// 원본: Sources/CheckMobileKit/Games/GamesPlayController.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.games

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.rules.minigame.FlappyGame
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.minigame.MiniGamePoint
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import com.yehsung.aingcheck.core.rules.minigame.TimingBarGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.rules.tetris.TetrisLayout
import com.yehsung.aingcheck.core.wire.SwiftDate

/**
 * 미니게임 한 판을 **돌리는** 것(엔진 구동). 규칙은 코어 `TimingBarGame`·`FlappyGame`·`TetrisGame`(W1-a)이고, 이 타입은 맥 게임 잎 뷰가
 * 하던 일 — 탭 → 전이, 프레임 시각 → `step(dt)`, 시작·끝 알림 — 을 화면 밖으로 꺼냈다. 그래서 JVM 시험이 "탭 입력 → 상태 전이"를
 * 화면 없이 구동한다.
 *
 * 지키는 것(맥과 같다)
 * - **물리는 논리 좌표·시간 기준이다.** 화면 크기·주사율은 이 타입에 들어오지 않는다(dt 는 실제 경과).
 *   dt 는 엔진의 `maxStep` 으로 잘린다 — 앱이 멈췄다 돌아온 첫 프레임이 몇 초를 한꺼번에 흘리지 않는다.
 *   INV-GamesPlayController-ea27c41e 이식: 그 상한은 **게임마다 다르다**: 타이밍 바·플래피는 1/30초, 테트리스는 **1/20초**다
 *   (엔진 상수 `TetrisGame.maxStep` — 이 구동기는 dt 를 깎지 않고 엔진에 그대로 넘긴다. 24Hz·30Hz 화면이 판을 느리게 돌리지 않게).
 * - 시작 뒤 첫 프레임은 기준만 잡는다(정지해 있던 시간을 물려받지 않는다).
 * - 끝난 판은 **한 번만** 알린다([onFinished]). 타이밍 바는 10라운드 완주, 플래피는 결과 확정(게임오버 유예 뒤),
 *   테트리스는 `Result` 전이(탑아웃 유예 뒤 · `interrupt()` 포함).
 * - 폰 전용 출구가 **둘**이다. 뜻이 다르므로 함수도 둘이다:
 *   · [abandon] — 판을 **기록 없이 버린다**(로그아웃 · 화면 경합 정리). 알리지 않으므로 제출도 없다.
 *   · [endRound] — 판을 **끝낸다**(뒤로가기 · 앱이 background 로 감). 타이밍 바·플래피는 버리는 것과 같고,
 *     **테트리스만 그 자리에서 점수를 확정해 알린다**(폰에서 background 는 비용이 0.05초뿐인 무한 일시정지라 살려 두면 순위표가 흔들린다).
 *
 * 폰 테트리스 입력(끌기·탭)의 **판정도 여기 있다**([canvasDragChanged]·[canvasDragEnded]) — JVM 시험이 손가락 좌표부터 조각 위치까지
 * 화면 없이 구동한다.
 *
 * 길건너 아잉이(v0.3.67)는 폰에 아직 없다 — `MiniGameKind.phoneCases` 가 거르므로 이 구동기가 crossy 로 만들어지는 일이 없다.
 * 빠짐없는 when 을 지키려고 '판 없음'으로 답한다(폰 판이 붙는 다음 판 — W4-b · 폰 1.0.15 와 같이 — 에 채운다).
 */
class GamesPlayController(val kind: MiniGameKind, seed: ULong) {
    /** [endRound] 가 무엇을 했는가. 허브가 이 값으로 안내 문구를 고른다. */
    sealed interface EndOutcome {
        /** 끝낼 판이 없었다(진행 중이 아니다 — 결과 카드는 그대로 둔다). */
        data object None : EndOutcome

        /** 기록 없이 끝냈다(타이밍 바·플래피). 알리지 않았으므로 제출도 없다. */
        data object Abandoned : EndOutcome

        /** 그 점수로 **확정**했다(테트리스). [onFinished] 는 이 함수 안에서 이미 불렸다. */
        data class Confirmed(val score: Int) : EndOutcome
    }

    var timing: TimingBarGame by mutableStateOf(TimingBarGame(seed))
        private set
    var flappy: FlappyGame by mutableStateOf(FlappyGame(seed))
        private set
    var tetris: TetrisGame by mutableStateOf(TetrisGame(seed))
        private set

    /** 탭이 판에 먹혔을 때마다 +1(가벼운 햅틱의 방아쇠). **판이 실제로 바뀌었을 때만** 올린다 — 소진된 홀드·못 도는 회전은 조용해야 한다. */
    var tapSerial: Int by mutableStateOf(0)
        private set

    /** 게임오버·완주마다 +1(한 번짜리 햅틱의 방아쇠). */
    var gameOverSerial: Int by mutableStateOf(0)
        private set

    /** 하드드롭마다 +1(테트리스 — 단단한 햅틱). 이동·소프트드롭에는 **serial 이 없다**(초당 56~213회는 햅틱이 낼 수 있는 속도가 아니다). */
    var hardDropSerial: Int by mutableStateOf(0)
        private set

    /** 줄을 **실제로 지운** 배치마다 +1(테트리스 — 묵직한 햅틱). 소거 없는 배치는 올리지 않는다. */
    var lineClearSerial: Int by mutableStateOf(0)
        private set

    /** 판이 **시작됐다**(탭으로 ready/결과 → 진행). 허브가 라운드 토큰을 챙긴다. */
    var onStarted: (() -> Unit)? = null

    /** 유효하게 끝난 판의 점수. 판마다 한 번. */
    var onFinished: ((Int) -> Unit)? = null

    /**
     * 이 판의 **벽시계 상한**(초 · 폰 테트리스만 — 허브가 `beginRound` 에서 건넨다. 기존 두 게임은 null).
     * 상한을 지나면 [tick] 이 판을 끝낸다([endRound]). 사용자 스위치로 주지 않는다.
     *
     * INV-GamesPlayController-646dcd5c 이식: **절대 시각이 아니라 길이다.** 마감을 재는 [tick] 의 `now` 는 화면 프레임 시계가 주는
     * **실제 벽시계**다. 허브가 주입 시계로 찍은 절대 시각을 건네면 축이 둘로 섞여 시계를 주입한 빌드(데모·시험)에서 판이 첫 프레임에
     * 죽는다. 길이로 받으면 기준점을 [tick] 이 자기 축에서 잡으므로 축이 하나뿐이다.
     */
    var roundLimitSeconds: Double? = null

    /** 위 길이를 **tick 축**에서 절대 시각으로 굳힌 값. 판마다 첫 틱이 잡고, 새 판·출구가 비운다. */
    private var roundDeadline: SwiftDate? = null
    private var lastTick: SwiftDate? = null
    private var reportedFinish = false
    private var seedSource: ULong = seed

    // MARK: 테트리스 제스처(폰 전용 · 화면 없이 구동된다)

    private val gesture = TetrisGestureTracker(TetrisGestureThresholds(cellWidth = TetrisLayout.cell))

    /** 지금 따라가는 접촉의 시작점·첫 프레임 시각. 시작점이 바뀌면 새 접촉이다(끌기 끝은 늘 오지 않는다). */
    private var gestureStartLocation: MiniGamePoint? = null
    private var gestureStartedAt: SwiftDate? = null

    // MARK: 읽기

    /** 프레임 루프가 돌아야 하는가. */
    val isPlaying: Boolean
        get() = when (kind) {
            MiniGameKind.timingBar -> timing.isPlaying
            MiniGameKind.flappy -> flappy.isPlaying
            MiniGameKind.tetris -> tetris.isPlaying
            MiniGameKind.crossy -> false
        }

    /** 지금(또는 마지막) 판의 점수. */
    val score: Int
        get() = when (kind) {
            MiniGameKind.timingBar -> timing.total
            MiniGameKind.flappy -> flappy.score
            MiniGameKind.tetris -> tetris.score
            MiniGameKind.crossy -> 0          // 폰에 없음(머리 주석)
        }

    // MARK: 입력

    /**
     * 캔버스 탭(맥의 클릭·스페이스와 같은 한 번의 행동).
     *
     * INV-GamesPlayController-2a73ec7c 이식: 테트리스만 뜻이 갈린다: 진행 중이면 **시계 회전**이다(반시계는 버튼, 하드드롭도 버튼 — 설계 G).
     * 맥처럼 `game.action()` 을 그대로 부르면 판 위 탭 한 번이 **하드드롭**이 되어, 조각을 돌리려던 손가락이 판을 끝낸다.
     * 시작 전·결과 카드에서만 `action()`(= 새 판)이다.
     */
    fun tap() {
        val wasPlaying = isPlaying
        when (kind) {
            MiniGameKind.timingBar -> {
                val next = timing.copy()
                next.tap()
                if (next != timing) {
                    timing = next
                    tapSerial += 1
                }
            }
            MiniGameKind.flappy -> {
                val next = flappy.copy()
                val before = next.flapCount
                val beforePhase = next.phase
                next.flap()
                flappy = next
                if (next.flapCount != before || next.phase != beforePhase) tapSerial += 1
            }
            MiniGameKind.tetris -> {
                if (tetris.isPlaying) {
                    rotate(clockwise = true)
                } else {
                    val next = tetris.copy()
                    next.action()
                    if (next != tetris) {
                        tetris = next
                        tapSerial += 1
                    }
                }
            }
            MiniGameKind.crossy -> Unit       // 폰에 없음(머리 주석)
        }
        if (isPlaying && !wasPlaying) {
            reportedFinish = false
            lastTick = null
            // 새 판의 상한 기준점은 **이 판의 첫 틱**이 다시 잡는다 — 앞 판의 기준점을 물려받으면 즉사한다.
            roundDeadline = null
            // INV-GamesPlayController-8b96b90c 이식: **이 줄을 지우지 마라.** 앞 끌기의 축 잠금·소비량이 남은 채 새 판이 켜지면 손도 안 댄 첫 조각이 곧장 옆으로 가거나
            //    바닥까지 소프트드롭된다. 화면 쪽 방어(접촉 소진 표시)와 **짝**이다.
            resetGesture()
            onStarted?.invoke()
        }
    }

    /** 회전. 캔버스 탭이 시계, 버튼이 반시계다(설계 G — 버튼도 시계면 자리 하나를 버리고 반시계가 폰에서 사라진다). */
    fun rotate(clockwise: Boolean) {
        if (kind != MiniGameKind.tetris) return
        val next = tetris.copy()
        val before = next.active
        next.rotate(clockwise)
        tetris = next
        if (next.active != before) tapSerial += 1
    }

    /**
     * 홀드(조각당 1회). 소진됐으면 엔진이 no-op 이고 **serial 도 안 올린다** — 눌러도 조용하다.
     * 갈아탄 조각이 스폰 자리에서 막히면 **그 자리에서 판이 끝난다** — 그 전이는 프레임 루프 **밖**이라 여기서 직접 센다.
     */
    fun hold() {
        if (kind != MiniGameKind.tetris) return
        val next = tetris.copy()
        val before = next.holdUsed
        val beforePiece = next.active
        val mark = tetrisHapticMark(next)
        next.holdCurrentPiece()
        tetris = next
        if (next.holdUsed != before || next.active != beforePiece) tapSerial += 1
        noteTetrisHaptics(next, mark)
    }

    /**
     * [즉시 내리기] 버튼. **진행 중일 때만** — 시작·다시는 캔버스가 한다(버튼이 판을 켜면 켜자마자 한 조각이 떨어진다).
     * 하드드롭은 락딜레이를 안 기다리고 **그 자리에서** 굳혀 줄을 지운다 — 프레임 루프 밖이라 여기서 소거 햅틱을 센다.
     */
    fun hardDrop() {
        if (kind != MiniGameKind.tetris || tetris.phase != TetrisGame.Phase.Running) return
        val next = tetris.copy()
        val mark = tetrisHapticMark(next)
        next.action()
        tetris = next
        hardDropSerial += 1
        noteTetrisHaptics(next, mark)
    }

    /** 엔진을 **프레임 루프 밖에서** 건드리기 직전의 햅틱 기준점(마지막 소거 시각 · 이미 끝난 판인가). */
    private fun tetrisHapticMark(game: TetrisGame): Pair<Double?, Boolean> = game.lastClear?.at to (game.phase is TetrisGame.Phase.Over)

    /**
     * 기준점 뒤에 **새로 생긴** 소거·게임오버를 센다. [tick] 의 테트리스 갈래와 **같은 판정 한 벌**이다.
     * (`lastClear` 는 소거가 0줄인 배치에도 적힌다 — 그래서 `lines > 0` 이 있어야 한다.)
     */
    private fun noteTetrisHaptics(game: TetrisGame, mark: Pair<Double?, Boolean>) {
        val clear = game.lastClear
        if (clear != null && clear.lines > 0 && clear.at != mark.first) lineClearSerial += 1
        if (!mark.second && game.phase is TetrisGame.Phase.Over) gameOverSerial += 1
    }

    /**
     * 가로 한 칸 — **엔진 무수정**이다. 누름과 뗌을 **같은 호출 안에서 연달아** 준다: 누름이 이동을 즉시 하고 뗌은 이동을 안 주므로,
     * 쌍 사이에 시간이 안 흘러 DAS(0.167초)가 만기될 수 없고 쌍이 끝나면 반복 상태가 완전히 원상복구된다.
     * INV-GamesPlayController-c440648d 이식: **쌍 사이에 `step(dt)` 을 끼우지 마라** — 그 순간 자동 반복이 살아나 한 번의 걸음이 여러 칸이 된다.
     * INV-GamesPlayController-65adb64e 이식: 엔진을 직접 부르는 시험(W1-a 엔진 계약)은 이 [feed] 를 한 번도 안 지난다 — 뗌을 지워도 초록이었다.
     *   그래서 이 배선은 **이 함수를 실제로 지나는** 시험(`GamesPlayControllerTest.oneCellStepsAreSymmetricAndLeaveNoRepeat`)이 못 박는다.
     *   엔진 계약과 이 배선은 서로를 대신하지 못한다 — 둘 다 있어야 한다.
     */
    fun moveLeftOneCell() = feed(TetrisGestureStep.moveLeft)
    fun moveRightOneCell() = feed(TetrisGestureStep.moveRight)

    /** 세로 한 칸(엔진 `softDropOneCell` — 한 칸 · 1점 · 접지 리셋 예산 안 씀 · 중력 되감기). */
    fun softDropOneCell() = feed(TetrisGestureStep.softDrop)

    private fun feed(step: TetrisGestureStep) {
        if (kind != MiniGameKind.tetris || tetris.phase != TetrisGame.Phase.Running) return
        val next = tetris.copy()
        when (step) {
            TetrisGestureStep.moveLeft -> {
                next.setLeftHeld(true)
                next.setLeftHeld(false)
            }
            TetrisGestureStep.moveRight -> {
                next.setRightHeld(true)
                next.setRightHeld(false)
            }
            TetrisGestureStep.softDrop -> next.softDropOneCell()
        }
        tetris = next
    }

    // MARK: 테트리스 제스처

    /** 화면 배율이 정해졌다(또는 바뀌었다) — 한 칸 문턱은 **화면 셀 폭**이다(논리 13 × 배율). */
    fun updateCellWidth(width: Double) {
        gesture.updateCellWidth(width)
    }

    /** 끌기 변화 — 시작점부터의 누적 이동을 그대로 넘기면 새로 생긴 걸음이 엔진에 먹는다. 시각은 **탭 판정용**이다. */
    fun canvasDragChanged(startLocation: MiniGamePoint, translation: MiniGameSize, time: SwiftDate) {
        if (kind != MiniGameKind.tetris) return
        if (gestureStartLocation != startLocation) {
            gestureStartLocation = startLocation
            gestureStartedAt = time
        }
        for (step in gesture.drag(startLocation, translation)) feed(step)
    }

    /** 끌기 끝 — 탭(8pt 미만 · 0.25초 안)이면 **시계 회전**이다. @return 이 끌기가 탭이었는가(회전을 시도했는가). */
    fun canvasDragEnded(translation: MiniGameSize, time: SwiftDate): Boolean {
        if (kind != MiniGameKind.tetris) return false
        val elapsed = gestureStartedAt?.let { maxOf(0.0, time.timeIntervalSince(it)) } ?: 0.0
        gestureStartLocation = null
        gestureStartedAt = null
        if (!gesture.end(translation, elapsed)) return false
        rotate(clockwise = true)
        return true
    }

    /** 새 판·출구에서 트래커를 비운다. 안 비우면 앞 끌기의 축 잠금·소비량이 다음 판으로 샌다. */
    private fun resetGesture() {
        gesture.end(MiniGameSize(0.0, 0.0), 0.0)
        gestureStartLocation = null
        gestureStartedAt = null
    }

    // MARK: 프레임

    /** 프레임 시각 한 번(화면의 프레임 시계가 날짜가 바뀔 때 부른다). */
    fun tick(now: SwiftDate) {
        if (!isPlaying) {
            lastTick = null
            return
        }
        // 판 상한은 **가드 뒤 · dt 계산 앞**이다: 첫 프레임(기준만 잡는 프레임)에서도 걸려야 앱이 오래 멈춰 있다 돌아온 그 순간에 판이 끝난다.
        // 기준점도 **여기서** 잡는다 — 그래야 마감과 그걸 재는 `now` 가 같은 축에 있다([roundLimitSeconds] 주석).
        val limit = roundLimitSeconds
        if (kind == MiniGameKind.tetris && limit != null) {
            val deadline = roundDeadline ?: now.addingTimeInterval(limit)
            roundDeadline = deadline
            if (now >= deadline) {
                endRound()
                return
            }
        }
        val last = lastTick
        lastTick = now
        if (last == null) return
        val dt = now.timeIntervalSince(last)
        when (kind) {
            MiniGameKind.timingBar -> {
                val next = timing.copy()
                next.step(dt)
                timing = next
                val phase = next.phase
                if (phase is TimingBarGame.Phase.Finished && !reportedFinish) {
                    reportedFinish = true
                    gameOverSerial += 1
                    onFinished?.invoke(phase.total)
                }
            }
            MiniGameKind.flappy -> {
                val next = flappy.copy()
                val wasRunning = next.phase == FlappyGame.Phase.Running
                next.step(dt)
                flappy = next
                if (wasRunning && next.phase is FlappyGame.Phase.Over) gameOverSerial += 1
                if (next.phase == FlappyGame.Phase.Result && !reportedFinish) {
                    reportedFinish = true
                    onFinished?.invoke(next.score)
                }
            }
            MiniGameKind.tetris -> {
                // 소거·게임오버 햅틱 판정은 버튼 경로(`hardDrop()`·`hold()`)와 **한 벌**이다.
                val next = tetris.copy()
                val mark = tetrisHapticMark(next)
                next.step(dt)
                tetris = next
                noteTetrisHaptics(next, mark)
                // 맥 잎 뷰의 `onChange(of: game.phase)` 와 같은 자리 — `Result` 로 들어간 순간이 확정이다.
                if (next.phase == TetrisGame.Phase.Result && !reportedFinish) {
                    reportedFinish = true
                    onFinished?.invoke(next.score)
                }
            }
            MiniGameKind.crossy -> Unit       // 폰에 없음(머리 주석)
        }
    }

    // MARK: 출구

    /**
     * 판을 **기록 없이** 버린다(로그아웃 · 화면 경합 정리). 시작 전 화면으로 돌아간다.
     * 진행 중이 아니면 아무것도 하지 않는다(결과 카드는 그대로 둔다). 끝났다고 알리지 않는다 — 그래서 제출도 없다.
     *
     * INV-GamesPlayController-15344b76 이식: **뒤로가기·background 는 여기가 아니라 [endRound] 다.** 로그아웃은 남의 계정에 점수를 올리면 안 되고, 화면 경합 정리는
     * 아직 시작도 안 한 판을 치우는 것이고, 뒤로가기·background 는 사람이 **실제로 쌓아 올린 판**이다.
     * @return 진행 중인 판을 실제로 끝냈는가.
     */
    fun abandon(): Boolean {
        if (!isPlaying) return false
        reportedFinish = true
        lastTick = null
        // 상한은 **길이와 기준점 둘 다** 비운다 — 다음 판의 길이는 허브가 `beginRound` 에서 다시 건네고, 기준점은 그 판의 첫 틱이 잡는다.
        roundLimitSeconds = null
        roundDeadline = null
        resetGesture()
        when (kind) {
            MiniGameKind.timingBar -> {
                val next = timing.copy()
                next.invalidate()
                timing = next
            }
            MiniGameKind.flappy -> {
                // 플래피 규칙에는 '무효'가 없다(interrupt 는 그 점수로 결과를 확정한다) — 새 판(시작 전)으로 갈아 끼운다.
                seedSource += 0x9E37_79B9u
                flappy = FlappyGame(seedSource)
            }
            MiniGameKind.tetris -> {
                // 테트리스도 같다(`interrupt()` 는 확정이다) — 버리려면 새 판으로 갈아 끼워야 한다.
                seedSource += 0x9E37_79B9u
                tetris = TetrisGame(seedSource)
            }
            MiniGameKind.crossy -> Unit       // 폰에 없음(머리 주석)
        }
        return true
    }

    /**
     * 판을 **끝낸다**(화면을 떠남 · 앱이 background 로 감). 기존 두 게임은 [abandon] 과 같고, **테트리스는 그 자리에서 점수를 확정해 알린다.**
     *
     * INV-GamesPlayController-615974ae 이식: 왜 테트리스만 다른가: 폰에서 background 는 **비용 0 의 무한 일시정지**다. 복귀 첫 프레임의 dt 는 `maxStep`(1/20)으로 잘리므로
     * 몇 분을 나가 있어도 판이 잃는 것은 0.05초뿐이다. 그래서 나가는 순간 **여기까지의 점수로 확정**한다.
     * INV-GamesPlayController-e5a30ec5 이식: `interrupt()` 뒤에는 **tick 이 다시 오지 않는다** — 여기서 직접 [onFinished] 를 부르지 않으면 **점수가 조용히 사라진다.**
     */
    fun endRound(): EndOutcome {
        if (!isPlaying) return EndOutcome.None
        return when (kind) {
            MiniGameKind.timingBar, MiniGameKind.flappy, MiniGameKind.crossy -> if (abandon()) EndOutcome.Abandoned else EndOutcome.None
            MiniGameKind.tetris -> {
                reportedFinish = true
                lastTick = null
                roundLimitSeconds = null
                roundDeadline = null
                resetGesture()
                val next = tetris.copy()
                next.interrupt()
                next.releaseAllKeys()
                tetris = next
                val score = next.score
                onFinished?.invoke(score)
                EndOutcome.Confirmed(score)
            }
        }
    }

    /** 시험·데모 전용: 임의 상태에서 시작한다(Swift `#if DEBUG replaceForTesting`). */
    fun replaceForTesting(timing: TimingBarGame? = null, flappy: FlappyGame? = null, tetris: TetrisGame? = null) {
        if (timing != null) this.timing = timing
        if (flappy != null) this.flappy = flappy
        if (tetris != null) this.tetris = tetris
        lastTick = null
        reportedFinish = !isPlaying
    }
}
