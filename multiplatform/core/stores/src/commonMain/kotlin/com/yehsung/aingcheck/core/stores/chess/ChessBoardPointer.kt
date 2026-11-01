// 원본: Sources/CheckCore/ChessDrag.swift(ChessBoardPointer) @ 1a5eeca6
//
// 판 위 포인터(누름 → 움직임 → 뗌)를 **행동**으로 바꾸는 작은 상태 기계. 순수 값이라 화면 없이 전수로 잰다(ChessBoardPointerTest).
// 판단은 셋으로 갈린다: 둘 수 있는가·무엇을 보내는가는 [ChessStore](끌어서 두기 절), 누름을 행동으로 바꾸는 일은 여기, 화면(`ChessBoard`)은 제스처 값을 먹이고 나온
// 행동을 스토어에 옮기는 얇은 어댑터다. 점 → 칸 변환은 화면의 기하가 끝내서 넘긴다.
package com.yehsung.aingcheck.core.stores.chess

import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.stores.gomoku.BoardPoint

/**
 * 여기 있는 판정 셋:
 *  ① **문턱**: 누른 자리에서 [dragThreshold] 이상 움직여야 끌기다. 그 밑에서 떼면 지금의 탭 그대로다.
 *  ② **같은 칸 · 손떨림**: 끌기가 안 되는 누름(빈 칸·상대 말·도착 칸)은 뗀 칸이 누른 칸과 같으면 탭이다. 뗀 칸이 **달라도** 뗀 점이 문턱 밑이면 누른 칸의 탭이다 —
 *     칸 경계 바로 안쪽을 누른 손이 조금 떨려 옆 칸에서 뗀 것은 탭이지 끌기가 아니다. 문턱 이상 움직여 다른 칸·판 밖에서 뗀 것만 아무 일도 없다.
 *  ③ **도착 칸을 눌렀으면 끌기가 아니다**: 이미 고른 말의 도착 칸을 누른 것은 탭-도착이다.
 *
 * 상태는 넷이다 — idle · pressed(눌렀고 아직 끌기가 아니다) · dragging · spent(이 누름은 끝났다: 판 밖을 눌렀거나, 끌던 중에 취소됐거나, 스토어가 끌기를 거절했거나,
 * 부모 스크롤이 손가락을 가져갔다 — 뗄 때까지 아무 행동도 안 낸다). spent 가 따로 있는 까닭: 끌던 중에 판이 바뀌어 취소한 뒤에도 손가락은 여전히 닿아 있다. 그 누름이 idle 로
 * 떨어지면 다음 움직임이 **새 누름**으로 읽혀 취소한 말을 그 자리에서 다시 집는다.
 *
 * @param dragThreshold 끌기 문턱(좌표 단위). 맥은 마우스라 4pt 다([DEFAULT_DRAG_THRESHOLD]). 폰은 손가락이라 화면이 플랫폼 터치 슬롭(px)을 넘긴다 — 4pt 면 탭하던 손가락의
 *   떨림이 끌기가 되어 "고른 말을 다시 눌러 해제"가 죽는다.
 */
class ChessBoardPointer(val dragThreshold: Double = DEFAULT_DRAG_THRESHOLD) {
    /** 해석기가 내는 행동. 화면은 이 다섯만 옮긴다. */
    sealed interface Action {
        /** 지금의 탭 그대로([ChessStore.tap]). */
        data class Tap(val square: ChessSquare) : Action

        /** 끌기를 시작한다([ChessStore.beginDrag]). 거절되면 화면이 [dragRefused] 로 알린다. */
        data class BeginDrag(val square: ChessSquare) : Action

        /** 끄는 말의 새 자리(화면 좌표 그대로). */
        data class DragMoved(val point: BoardPoint) : Action

        /** 놓았다. [on] 이 null 이면 판 밖이다. */
        data class Drop(val from: ChessSquare, val on: ChessSquare?) : Action

        /** 끌기를 거둔다(말을 제자리에). */
        data object Cancel : Action
    }

    private sealed interface Phase {
        data object Idle : Phase
        data class Pressed(val square: ChessSquare, val grab: ChessDragGrab) : Phase
        data class Dragging(val from: ChessSquare) : Phase
        data object Spent : Phase
    }

    private var phase: Phase = Phase.Idle

    /** 이 누름이 시작된 점. idle 이면 null 이다. */
    private var origin: BoardPoint? = null

    val isIdle: Boolean get() = phase == Phase.Idle

    /** 지금 끌고 있는 말의 출발 칸(끌기가 아니면 null). */
    val draggingFrom: ChessSquare? get() = (phase as? Phase.Dragging)?.from

    /** 그 점에서 시작한 누름을 이미 따라가고 있는가. */
    fun isTracking(pressAt: BoardPoint): Boolean = phase != Phase.Idle && origin == pressAt

    /** 눌렀다. [square] 가 null 이면 판 밖이다. [isSelectionTarget] 은 그 칸이 이미 고른 말의 도착 칸인가다. */
    fun press(point: BoardPoint, square: ChessSquare?, grab: ChessDragGrab, isSelectionTarget: Boolean): List<Action> {
        // 앞 누름이 뗌 없이 끝났다(제스처가 중간에 죽었다) — 끌던 말부터 거두고 새 누름을 받는다.
        val abandoned = if (draggingFrom == null) emptyList() else listOf(Action.Cancel)
        origin = point
        if (square == null) {
            phase = Phase.Spent
            return abandoned
        }
        // ③ 도착 칸을 눌렀으면 끌기가 아니다 — 그 칸에 무엇이 있든 탭-도착으로만 읽는다.
        phase = Phase.Pressed(square, if (isSelectionTarget) ChessDragGrab.none else grab)
        return abandoned
    }

    /** 누른 채 움직였다. */
    fun move(point: BoardPoint): List<Action> = when (val current = phase) {
        is Phase.Pressed -> {
            if (current.grab == ChessDragGrab.movable && hasCrossedThreshold(point)) {
                phase = Phase.Dragging(current.square)
                listOf(Action.BeginDrag(current.square), Action.DragMoved(point))
            } else {
                emptyList()
            }
        }
        is Phase.Dragging -> listOf(Action.DragMoved(point))
        Phase.Idle, Phase.Spent -> emptyList()
    }

    /** 뗐다. [square] 가 null 이면 판 밖에서 뗐다. */
    fun release(point: BoardPoint, square: ChessSquare?): List<Action> {
        val result = when (val current = phase) {
            is Phase.Pressed -> when (current.grab) {
                // 움직임 없이 뗌만 멀리서 온 누름(빠르게 튕긴 끌기)도 끌기다 — 문턱은 **뗀 자리**로도 잰다.
                ChessDragGrab.movable ->
                    if (hasCrossedThreshold(point)) listOf(Action.BeginDrag(current.square), Action.Drop(current.square, square))
                    else listOf(Action.Tap(current.square)) // ① 문턱 밑 = 지금의 탭
                ChessDragGrab.stuck -> listOf(Action.Tap(current.square)) // 끌려다 만 내 말 — 어디서 떼든 거절 한 번
                // ② 같은 칸에서 뗐거나, 칸은 달라도 문턱 밑(손떨림)이면 **누른 칸**의 탭. 문턱 이상 움직여 다른 칸·판 밖에서 뗀 것만 조용히 버린다.
                ChessDragGrab.none ->
                    if (square == current.square || !hasCrossedThreshold(point)) listOf(Action.Tap(current.square)) else emptyList()
            }
            is Phase.Dragging -> listOf(Action.Drop(current.from, square))
            Phase.Idle, Phase.Spent -> emptyList()
        }
        phase = Phase.Idle
        origin = null
        return result
    }

    /**
     * 끄는 중에 판이 바뀌었다(상대 기권·시간패·판 교체·내 차례 아님·왕복 시작·화면 가림/닫힘).
     * 끌던 중이면 거두고 이 누름을 **소진**시킨다 — 그 뒤 손가락을 떼도 수가 나가지 않는다. 아직 끌기 전이면 "끌 수 있다"는 누를 때의 판정만 버린다.
     * 탭은 남긴다: 같은 칸에서 떼면 스토어가 **바뀐 판에 대고** 다시 판단한다.
     */
    fun cancel(): List<Action> = when (val current = phase) {
        is Phase.Dragging -> {
            phase = Phase.Spent
            listOf(Action.Cancel)
        }
        is Phase.Pressed -> {
            phase = Phase.Pressed(current.square, ChessDragGrab.none)
            emptyList()
        }
        Phase.Idle, Phase.Spent -> emptyList()
    }

    /**
     * 부모 스크롤이 이 손가락을 가져갔다(폰 전용 — 마우스에는 없는 사건). 끄는 중이 아닌 누름에서만 일어난다(끌 수 있는 말을 누른 손가락은 화면이 먼저 소비한다).
     * 그 손은 스크롤하러 떠났으므로 뗄 때 탭도 안 낸다.
     */
    fun stolenByScroll(): List<Action> {
        val out = if (draggingFrom == null) emptyList() else listOf(Action.Cancel)
        if (phase != Phase.Idle) phase = Phase.Spent
        return out
    }

    /** 스토어가 끌기를 거절했다([ChessStore.beginDrag] 가 false — 누른 뒤 문턱을 넘기 전에 판이 바뀌었다). 거절 문구는 스토어가 이미 말했으므로 이 누름은 조용히 소진된다. */
    fun dragRefused() {
        if (phase is Phase.Dragging) phase = Phase.Spent
    }

    private fun hasCrossedThreshold(point: BoardPoint): Boolean {
        val start = origin ?: return false
        val dx = point.x - start.x
        val dy = point.y - start.y
        // 제곱끼리 견준다 — 제곱근을 거치지 않으니 경계(정확히 문턱)가 그 반올림에 흔들리지 않는다.
        return dx * dx + dy * dy >= dragThreshold * dragThreshold
    }

    companion object {
        /** 맥(마우스)의 끌기 문턱(pt). 이 값 **이상** 움직이면 끌기이고 그 밑은 탭이다. */
        const val DEFAULT_DRAG_THRESHOLD: Double = 4.0
    }
}
