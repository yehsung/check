// 원본: Sources/CheckMobileKit/Games/GamesTetrisGesture.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.rules.minigame.MiniGamePoint
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.hypot

/**
 * 테트리스 판 위 제스처 판정 — **순수 계산만** 한다(화면 없음). 그래서 JVM 시험이 "손가락 움직임 → 조각 조작"을 화면 없이
 * 구동한다. 화면(W4-b)은 끌기 값을 그대로 넘기고 돌려받은 걸음을 엔진에 먹이기만 한다.
 *
 * **왜 기존 두 게임의 제스처를 못 쓰나**: 플래피·타이밍 바는 판 어디든 첫 끌기 변화를 **한 번의 탭**으로 접는다.
 * 테트리스는 한 번의 끌기가 **여러 칸**을 만들고 행동도 셋(좌·우·소프트드롭)이라 그 구조로는 표현이 안 된다.
 *
 * **하드드롭은 여기 없다.** 제스처로 주지 않는다 — 소프트드롭 끌기와 구분이 어렵고 오인식 한 번이 곧 판 종료다. 버튼만이다.
 */
enum class TetrisGestureStep { moveLeft, moveRight, softDrop }

/**
 * 판정에 쓰는 임계값 **전부**. 실기로 되맞출 자리가 여기 하나뿐이도록 모아 둔다 — 감도 조정이 한 줄이 된다.
 * `cellWidth` 만 화면에서 온다(논리 셀 13pt × 화면 배율).
 *
 * INV-GamesTetrisGesture-0e63a3b7 이식: **나머지 둘(8pt · 0.25초)은 확정값이 아니다.** 출처는 SPEC 부록 폰 절인데, 그 부록은 난이도
 * 재튜닝 **이전** 산출이라 이미 낡은 값이 셋 드러났다. 그리고 어느 쪽이든 **아직 손가락으로 재지 않았다** — Android 실기(갤럭시 한 대 ·
 * W3/W4 실기 단계)로 10판을 잰 뒤 이 두 수를 고치는 것이 남은 일이다. 값은 Swift 와 같게 둔다(두 플랫폼 감도가 갈리지 않게).
 */
class TetrisGestureThresholds(cellWidth: Double, tapMaxDistance: Double = 8.0, tapMaxDuration: Double = 0.25) {
    /** 한 칸을 만드는 이동 거리 = 화면 셀 폭. 손가락을 따라가게 하는 값이라 **거리 기준**이다(맥의 DAS/ARR 은 폰에 없다). */
    val cellWidth: Double = maxOf(1.0, cellWidth)

    /** 탭으로 볼 최대 이동(pt). */
    val tapMaxDistance: Double = maxOf(0.0, tapMaxDistance)

    /** 탭으로 볼 최대 시간(초). */
    val tapMaxDuration: Double = maxOf(0.0, tapMaxDuration)

    fun withCellWidth(width: Double): TetrisGestureThresholds = TetrisGestureThresholds(width, tapMaxDistance, tapMaxDuration)

    override fun equals(other: Any?): Boolean =
        other is TetrisGestureThresholds && other.cellWidth == cellWidth && other.tapMaxDistance == tapMaxDistance &&
            other.tapMaxDuration == tapMaxDuration

    override fun hashCode(): Int = (cellWidth.hashCode() * 31 + tapMaxDistance.hashCode()) * 31 + tapMaxDuration.hashCode()

    override fun toString(): String = "TetrisGestureThresholds(cellWidth=$cellWidth, tapMaxDistance=$tapMaxDistance, tapMaxDuration=$tapMaxDuration)"
}

/**
 * 한 번의 끌기(손을 댄 순간 ~ 뗀 순간)를 걸음으로 바꾼다. 끌기의 `translation` 은 **시작점부터의 누적**이라
 * 이미 먹인 만큼을 이 타입이 기억한다.
 *
 * **축 잠금**: 먼저 문턱을 넘은 축이 그 끌기 동안 이긴다. 그대로 두면 살짝 비스듬한 가로 끌기가 **소프트드롭을 같이 만든다.**
 * 무엇을 잃는가 — **확정(락)이 아니다.** 잃는 것은 하나뿐이다: **조준한 곳보다 낮은 자리에 떨어뜨린다.**
 * 아픈 구간은 조각이 실제로 공중에 있는 **초반**이다(L1~7 에서만 손가락이 끼어들 틈이 있다). 접지 예산은 이 판단과 **무관하다**.
 *
 * Swift 는 값 타입이다. Kotlin 은 참조라 복제가 필요하면 [copy] 를 부른다.
 */
class TetrisGestureTracker(thresholds: TetrisGestureThresholds) {
    /** 잠긴 축. 문턱을 처음 넘을 때 정해지고 끌기가 끝나면 풀린다. */
    enum class Axis { horizontal, vertical }

    var thresholds: TetrisGestureThresholds = thresholds
        private set
    var axis: Axis? = null
        private set

    /** 이미 걸음으로 바꿔 먹인 양(축별). `translation` 이 누적값이라 이만큼을 빼고 본다. */
    private var consumedX = 0.0
    private var consumedY = 0.0

    /** 지금 따라가고 있는 접촉의 시작점. **`onEnded` 를 못 받는 경우가 있어서** 이걸로 새 끌기를 알아본다. */
    private var startLocation: MiniGamePoint? = null

    fun copy(): TetrisGestureTracker = TetrisGestureTracker(thresholds).also {
        it.axis = axis
        it.consumedX = consumedX
        it.consumedY = consumedY
        it.startLocation = startLocation
    }

    /** 셀 폭이 바뀌면 문턱을 갈아 끼운다(화면이 트래커를 다시 만들지 않고 재사용할 때). */
    fun updateCellWidth(width: Double) {
        thresholds = thresholds.withCellWidth(width)
    }

    /**
     * 끌기 변화 — 시작점부터의 누적 이동을 주면 이번에 새로 생긴 걸음들을 돌려준다.
     *
     * 문턱을 여러 배 넘겼으면 **그 배수만큼** 돌려준다(빠르게 긋는 손가락을 잃지 않는다). 방향이 도중에 바뀌면
     * 반대 방향 걸음이 그대로 나온다 — 손가락 위치가 곧 조각 위치라는 규약이다.
     */
    fun drag(startLocation: MiniGamePoint, translation: MiniGameSize): List<TetrisGestureStep> {
        // **새 접촉인가.** 끌기 끝은 항상 오지 않는다(시스템 제스처·전화 수신 등으로 취소되면 안 온다). 그때 잠금과
        // 소비량이 남아 있으면 `pending = 0 − consumed` 가 **큰 반대 부호**가 되어 손도 안 댄 이동이 우수수 나온다.
        // 입력을 잃는 게 아니라 **없는 입력을 만든다** — 그쪽이 훨씬 나쁘다. 시작점이 바뀌면 상태를 버리고 새로 시작한다.
        if (this.startLocation != startLocation) {
            this.startLocation = startLocation
            axis = null
            consumedX = 0.0
            consumedY = 0.0
        }
        val cell = thresholds.cellWidth
        if (axis == null) {
            // 아직 안 잠겼다: 먼저 한 칸을 만든 축이 이긴다. 둘 다 넘었으면 더 많이 간 쪽.
            // **위로 끄는 것은 축을 잠그지 않는다.** 위로는 아무 동작도 없는데 잠가 버리면 그 끌기 내내 좌우가 통째로 죽는다.
            val overX = abs(translation.width) >= cell
            val overY = translation.height >= cell
            if (overX || overY) {
                axis = if (overX && overY) {
                    if (abs(translation.width) >= translation.height) Axis.horizontal else Axis.vertical
                } else if (overX) Axis.horizontal else Axis.vertical
            } else {
                return emptyList()
            }
        }
        return when (axis) {
            Axis.horizontal -> {
                // 가로는 **환불한다** — 손가락을 되돌리면 조각도 되돌아온다(손가락 위치가 곧 조각 위치).
                val steps = steps(translation.width, consumed = consumedX, cell = cell)
                consumedX = steps.second
                List(abs(steps.first)) { if (steps.first > 0) TetrisGestureStep.moveRight else TetrisGestureStep.moveLeft }
            }
            Axis.vertical -> {
                // 세로는 **래칫이다(환불 없음)**. 소프트드롭은 되돌릴 수 없는 동작인데 환불하면 같은 구간을 아래위로 문지르는
                // 것만으로 소프트드롭이 무한정 나온다 — 칸당 1점이라 **점수 위조**가 된다. 내려간 최대치만 기억한다.
                val steps = steps(maxOf(translation.height, consumedY), consumed = consumedY, cell = cell)
                consumedY = steps.second
                if (steps.first > 0) List(steps.first) { TetrisGestureStep.softDrop } else emptyList()
            }
            null -> emptyList()
        }
    }

    /**
     * 끌기 끝 — 이 끌기가 **탭**(시계 회전)이었는가. 잠금·소비량을 비워 다음 끌기를 받을 준비를 한다.
     *
     * 탭은 "한 칸도 안 움직였다"가 아니라 **이동이 `tapMaxDistance` 미만이고 `tapMaxDuration` 안에 뗐다** 이다.
     * 걸음을 하나라도 낸 끌기는 탭이 아니다(축이 잠겼다는 것이 그 증거다).
     *
     * INV-GamesTetrisGesture-19aa5de9 이식: **죽은 구간이 있다**(의도한 것): 8pt 이상 움직였지만 셀 폭에 못 미친 채 떼면 회전도
     * 이동도 안 난다. 0.25초를 넘겨 천천히 떼도 마찬가지다. 애매한 입력을 **아무 동작으로도 확정하지 않기** 위해서다 —
     * 실기 10판에서 "탭이 자꾸 씹힌다"가 나오면 `tapMaxDuration` 부터 늘린다.
     */
    fun end(translation: MiniGameSize, elapsed: Double): Boolean {
        val moved = hypot(translation.width, translation.height)
        val isTap = axis == null && moved < thresholds.tapMaxDistance && elapsed < thresholds.tapMaxDuration
        axis = null
        consumedX = 0.0
        consumedY = 0.0
        startLocation = null
        return isTap
    }

    /** 누적 이동에서 **아직 안 먹인** 칸 수와 새 소비량. 부호는 방향이다. */
    private fun steps(total: Double, consumed: Double, cell: Double): Pair<Int, Double> {
        val pending = total - consumed
        if (abs(pending) < cell) return 0 to consumed
        val count = floor(abs(pending) / cell).toInt()
        val signed = if (pending > 0) count else -count
        return signed to consumed + signed.toDouble() * cell
    }

    override fun equals(other: Any?): Boolean =
        other is TetrisGestureTracker && other.thresholds == thresholds && other.axis == axis &&
            other.consumedX == consumedX && other.consumedY == consumedY && other.startLocation == startLocation

    override fun hashCode(): Int = thresholds.hashCode() * 31 + (axis?.hashCode() ?: 0)
}
