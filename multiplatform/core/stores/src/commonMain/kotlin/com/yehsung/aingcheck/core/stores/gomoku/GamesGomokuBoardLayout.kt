// 원본: Sources/CheckMobileKit/Games/GamesGomokuBoardLayout.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuForbiddenReason
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.math.abs
import kotlin.math.floor

// 오목 판 좌표 · 폰 탭 규칙(순수 — 데스크톱 JVM 시험으로 잰다).
//
// 판 좌표계는 맥 `GomokuBoardGeometry` 와 **같은 식**이다: 바깥 여백 6% 안에 15줄을 같은 간격으로 긋고, 누른 자리에서 가장 가까운 교차점을
// 고르되 반 칸을 넘으면 판 밖이다. 행은 **아래가 1**(렌주 표기 · 서버 y)이고 화면 y 는 위가 0 이라 뒤집는다.

/** 판(또는 판의 일부) 그림의 좌표계. */
data class GomokuPhoneBoardGeometry(
    /** 그림 한 변(pt). */
    val side: Double,
    /** 그리는 줄 수(전체 판 15, 규칙 예시 9). */
    val lines: Int = GomokuBoard.size,
    /** 가장 왼쪽 열의 x · 가장 아래 행의 y(규칙 예시는 가운데만 잘라 그린다). */
    val originX: Int = 0,
    val originY: Int = 0,
    /** 바깥 여백 비율(좌표 글자와 가장자리 돌이 들어갈 자리). */
    val insetRatio: Double = 0.06,
) {
    val inset: Double get() = side * insetRatio
    val cell: Double get() = (side - inset * 2) / (lines - 1).toDouble()

    fun contains(point: GomokuPoint): Boolean =
        point.x >= originX && point.x < originX + lines && point.y >= originY && point.y < originY + lines

    /** 교차점의 화면 위치. */
    fun location(point: GomokuPoint): BoardPoint = BoardPoint(
        x = inset + (point.x - originX).toDouble() * cell,
        y = inset + (originY + lines - 1 - point.y).toDouble() * cell,
    )

    /** 화면 위치에서 가장 가까운 교차점. 가장 가까운 교차점에서 가로·세로 어느 쪽이든 **반 칸을 넘으면** null(판 밖). */
    fun point(location: BoardPoint): GomokuPoint? {
        if (cell <= 0) return null
        val column = (location.x - inset) / cell
        val row = (location.y - inset) / cell
        if (!column.isFinite() || !row.isFinite()) return null
        val ix = roundHalfAwayFromZero(column)
        val iy = roundHalfAwayFromZero(row)
        if (ix !in 0 until lines || iy !in 0 until lines) return null
        if (abs(column - ix) > 0.5 || abs(row - iy) > 0.5) return null
        return GomokuPoint.at(originX + ix.toInt(), originY + lines - 1 - iy.toInt())
    }

    companion object {
        /** 화점(D4·L4·H8·D12·L12). */
        val starPoints: List<GomokuPoint> = listOf(3 to 3, 11 to 3, 7 to 7, 3 to 11, 11 to 11).mapNotNull { GomokuPoint.at(it.first, it.second) }
    }
}

/** Swift `x.rounded()`(0.5 는 0 에서 먼 쪽 — C§2.5. `Math.round` 는 −2.5 → −2 라 갈린다). */
internal fun roundHalfAwayFromZero(value: Double): Long {
    val magnitude = floor(abs(value) + 0.5)
    return (if (value < 0) -magnitude else magnitude).toLong()
}

/** 탭 한 번이 무엇이 되는가. */
sealed interface GomokuTapOutcome {
    /** 판 밖(격자 바깥 여백). 조용하다 — 거절이 아니라 빈 곳을 누른 것이다. */
    data object none : GomokuTapOutcome
    /** 미리보기 돌을 이 칸에 세웠다(또는 옮겼다). */
    data class preview(val point: GomokuPoint) : GomokuTapOutcome
    /** 같은 칸을 다시 눌렀다 — 둔다(`GomokuStore.place`). */
    data class place(val point: GomokuPoint) : GomokuTapOutcome
    /** 지금 둘 수 없는 칸·때다. **스토어에 넘겨** 거절 이유 한 줄과 진단 줄을 남기게 한다(뷰가 조용히 삼키지 않는다). */
    data class refuse(val point: GomokuPoint) : GomokuTapOutcome
}

/**
 * 폰의 "첫 탭은 미리보기, 같은 칸 다시 탭하면 착수"(SPEC-ios §3.5). 미리보기는 **그 판 그 수(match id · move_count)** 에서 세운 것만 산다 —
 * 사용자가 본 판과 다른 판에 돌이 놓이면 안 된다. Swift 값 타입(뷰 `@State`)이라 Kotlin 은 화면이 `remember` 로 드는 작은 가변 값이다.
 */
class GomokuTapPreview {
    var point: GomokuPoint? = null
        private set
    private var matchID: String? = null
    private var moveCount: Int? = null

    /** 지금 판에서 그려야 할 미리보기 자리(없으면 null). 판이 바뀌었거나 둘 수 없는 때면 그리지 않는다. */
    fun visiblePoint(match: GomokuMatchState, isBusy: Boolean, forbidden: Map<GomokuPoint, GomokuForbiddenReason>): GomokuPoint? {
        val point = point ?: return null
        if (!isCurrent(match) || !canPlace(match, isBusy) || match.board[point] != null || forbidden[point] != null) return null
        return point
    }

    /** 탭 한 번. [point] 는 `GomokuPhoneBoardGeometry.point(location)` 의 결과(판 밖이면 null). */
    fun tap(point: GomokuPoint?, match: GomokuMatchState, isBusy: Boolean, forbidden: Map<GomokuPoint, GomokuForbiddenReason>): GomokuTapOutcome {
        if (point == null) return GomokuTapOutcome.none
        if (!canPlace(match, isBusy) || match.board[point] != null || forbidden[point] != null) {
            clear()
            return GomokuTapOutcome.refuse(point)
        }
        if (this.point == point && isCurrent(match)) {
            clear()
            return GomokuTapOutcome.place(point)
        }
        this.point = point
        matchID = match.id
        moveCount = match.moveCount
        return GomokuTapOutcome.preview(point)
    }

    fun clear() {
        point = null
        matchID = null
        moveCount = null
    }

    private fun isCurrent(match: GomokuMatchState): Boolean = matchID == match.id && moveCount == match.moveCount

    override fun equals(other: Any?): Boolean =
        other is GomokuTapPreview && other.point == point && other.matchID == matchID && other.moveCount == moveCount

    override fun hashCode(): Int = (point?.hashCode() ?: 0) * 31 + (matchID?.hashCode() ?: 0)

    companion object {
        /** 지금 내가 둘 수 있는 때인가(끝나지 않음 · 내 차례 · 왕복 중 아님). 스토어 `place` 의 앞 가드와 같은 조건이다. */
        fun canPlace(match: GomokuMatchState, isBusy: Boolean): Boolean = !match.isFinished && match.turn == match.myColor && !isBusy
    }
}

/** [기권] 누름 받기 — 대국 화면이 나타난 직후의 누름은 이 화면을 보고 누른 것이 아니다(로비 [수락] 두 번 누름의 둘째가 떨어지는 경로). */
object GomokuPhoneResignGuard {
    const val armDelay: Double = 1.0

    fun acceptsTap(shownAt: SwiftDate?, now: SwiftDate): Boolean {
        if (shownAt == null) return true
        return now.timeIntervalSince(shownAt) >= armDelay
    }
}

/** 판돈 창 고르기(맥 `GomokuStakeSelection`): 이미 고른 판돈을 다시 누르면 해제. */
object GomokuPhoneStakeSelection {
    fun toggled(current: GomokuStake?, tapped: GomokuStake): GomokuStake? = if (current == tapped) null else tapped

    /** 이 판돈을 걸 수 있는가. **잔액을 모르면(null) 막지 않는다**(맥 0.3.29 규칙 — 서버가 거절하면 그때 안내한다). */
    fun affordable(stake: GomokuStake, balance: Long?): Boolean {
        if (balance == null) return true
        return balance >= stake.rawValue
    }
}

/**
 * 로비 [도전] 활성 조건(맥 `GomokuChallengeGate` 와 같다 — **근무 여부를 보지 않는다**).
 * §8-17 #1: 판돈 대결 진입이 잠긴 빌드(`duelsLocked`)에서는 꺼진다 — 스토어 문(`challenge`)과 **짝으로** 막는다(한쪽만 막으면 다른 쪽이 연다).
 */
object GomokuPhoneChallengeGate {
    fun isEnabled(user: GomokuUser, store: GomokuStore): Boolean =
        !store.duelsLocked && user.isCapable && !user.inMatch && store.outgoing == null && store.match == null && !store.isBusy
}

/**
 * 끝난 판의 승리선. 마지막 수를 지나는 가로·세로·두 대각선 중 같은 색이 **5개 이상** 이어진 줄의 양 끝 돌을 돌려준다(장목이면 그 전체).
 * 5목으로 끝난 판이 아니면 null.
 */
object GomokuPhoneWinLine {
    fun ends(board: GomokuBoard, lastMove: GomokuPoint?): Pair<GomokuPoint, GomokuPoint>? {
        if (lastMove == null) return null
        val color = board[lastMove] ?: return null
        for ((dx, dy) in listOf(1 to 0, 0 to 1, 1 to 1, 1 to -1)) {
            var from: GomokuPoint = lastMove
            var to: GomokuPoint = lastMove
            var count = 1
            while (true) {
                val next = GomokuPoint.at(to.x + dx, to.y + dy) ?: break
                if (board[next] != color) break
                to = next
                count += 1
            }
            while (true) {
                val next = GomokuPoint.at(from.x - dx, from.y - dy) ?: break
                if (board[next] != color) break
                from = next
                count += 1
            }
            if (count >= 5) return from to to
        }
        return null
    }
}
