// 원본: Sources/CheckCore/ReversiFlipAnimation.swift @ 12624739 (값 몫 — `make(from:to:at:)` 의 ReversiMatchState 짝은 스토어 단계)
package com.yehsung.aingcheck.core.rules.reversi

import com.yehsung.aingcheck.core.rules.renju.swiftMax
import com.yehsung.aingcheck.core.rules.renju.swiftMin
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiPly
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos

// 아잉 뒤집기 — 돌이 **뒤집히는 동안**을 담는 순수 값. 계약은 설계서 FLIP/SPEC.md §4.5.
//
// 체스 `ChessMoveFlight` 규약을 따른다: 애니메이션을 `(판 id, 시작 시각, 놓은 칸, 색, 뒤집힐 칸, 칸마다 지연)` 값으로 두고
// **어떤 프레임이든 `now` 하나로 결정**한다(중간 프레임을 밖에서 재현할 수 있어야 시험을 짠다).
//
// 지키는 약속:
//  · 칸마다 가로 비율을 |cos| 로 줄였다가(반에서 0) 다시 편다. **반을 지나는 순간 색이 바뀐다**(둔 사람의 상대 색 → 둔 사람 색).
//  · **투명도 값을 두지 않는다** — 돌 색이 늘 극단이라 렌더 감지기가 돌을 센다. 이징으로 투명도를 깎으면 밀려나기 전에 사라진다.
//  · 지연은 놓은 칸에서의 거리순(행·열 2차원 체비쇼프 거리 — 같은 고리는 같이 뒤집힌다).
//  · 응답이 **온 뒤에** 시작한다(낙관적 그림 없음). 새 판이 직전 판 + **돌 한 수**(+ 그 뒤 자동 패스)일 때만 그 수의
//    `flipped` 로 시작하고, 한 번에 돌 두 수 이상 건너뛰면 애니메이션 없이 바로 맞춘다. 다른 판 id 면 무시한다.
//  · 화면 좌표·그림은 없다(뷰 몫). 입력·합법성·판정은 이 값을 보지 않는다.
//
// Kotlin 이식 메모: 시각은 Swift `Date` → 1970 기준 초 Double. `make(from: ReversiMatchState?, to:, at:)` 는 스토어 값이 생기는 다음 단계가
// 아래 값 버전 [make] 를 불러 한 줄로 잇는다(판 id 가 같을 때만 — Swift `previous.id == next.id`).

/** Swift `ReversiFlipAnimation` — 판 위에서 **뒤집히는 중인 수 하나**. `now` 하나면 어느 프레임이든 결정적이다. */
data class ReversiFlipAnimation(
    val matchID: String,
    /** 1970 기준 초. */
    val startedAt: Double,
    /** 이번에 놓은 돌의 칸(뒤집히지 않는다 — 그냥 나타난다). */
    val placedIdx: Int,
    /** 둔 색 = 뒤집힌 뒤의 색. */
    val color: ReversiColor,
    /** 뒤집히는 칸(오름차순, 서버 `flipped` 그대로). */
    val flipped: List<Int>,
) {
    /** 칸마다 시작 지연(초). 키는 [flipped] 의 칸과 같다. */
    val delays: Map<Int, Double> = flipped.associateWith { idx -> maxOf(0, ringDistance(placedIdx, idx) - 1).toDouble() * ringDelay }

    /** 마지막 칸이 다 뒤집히기까지 걸리는 시간(초). */
    val duration: Double get() = (delays.values.maxOrNull() ?: 0.0) + flipDuration

    /** 다 끝났는가(뷰는 이때 애니메이션을 내리고 판을 그대로 그린다). */
    fun isFinished(now: Double): Boolean = now - startedAt >= duration

    /** 칸의 진행률 0…1. 이 수에서 뒤집히는 칸이 아니면 null. */
    fun progress(idx: Int, now: Double): Double? {
        val delay = delays[idx] ?: return null
        val elapsed = (now - startedAt) - delay
        return swiftMin(1.0, swiftMax(0.0, elapsed / flipDuration))
    }

    /** 칸의 가로 비율(1 = 온전한 원, 0 = 옆으로 선 순간). 뒤집히는 칸이 아니면 1. */
    fun xScale(idx: Int, now: Double): Double {
        val p = progress(idx, now) ?: return 1.0
        return abs(cos(PI * p))
    }

    /** 지금 그릴 색. 반 전에는 옛 색(둔 사람의 상대), 반부터 새 색. 뒤집히는 칸이 아니면 null(판 그대로 그린다). */
    fun displayedColor(idx: Int, now: Double): ReversiColor? {
        val p = progress(idx, now) ?: return null
        return if (p < 0.5) color.opponent else color
    }

    companion object {
        /** 돌 하나가 뒤집히는 시간(초). */
        const val flipDuration: Double = 0.32

        /** 놓은 칸에서 한 고리 멀어질 때마다 늦게 시작하는 시간(초). */
        const val ringDelay: Double = 0.06

        /**
         * Swift `make(matchID:previousMoveCount:nextMoveCount:plies:at:)` — 같은 판의 `move_count` 가 **돌 한 수**(1) 또는
         * **돌 한 수 + 자동 패스**(2) 만큼만 올랐고, 그 기록이 손에 있을 때만 값이 나온다. 그 밖(줄어듦 · 두 수 이상 건너뜀 · 패스만 · 기록 구멍)은 null.
         * `plies` 는 새 판의 기록(이번에 온 수가 들어 있어야 한다).
         */
        fun make(matchID: String, previousMoveCount: Int, nextMoveCount: Int, plies: List<ReversiPly>, now: Double): ReversiFlipAnimation? {
            val delta = nextMoveCount - previousMoveCount
            if (delta != 1 && delta != 2) return null
            val fresh = plies.filter { it.seq > previousMoveCount && it.seq <= nextMoveCount }.sortedBy { it.seq }
            val stone = fresh.firstOrNull() ?: return null
            val idx = stone.idx
            if (fresh.size != delta || stone.seq != previousMoveCount + 1 || stone.kind != ReversiPly.Kind.stone || idx == null || stone.flipped.isEmpty()) {
                return null
            }
            if (delta == 2 && fresh[1].kind != ReversiPly.Kind.pass) return null
            return ReversiFlipAnimation(matchID, now, idx, stone.color, stone.flipped)
        }

        /** 두 칸의 고리 거리(행·열 2차원 — 1차원 idx 차로 재지 않는다, V-01). */
        private fun ringDistance(a: Int, b: Int): Int = maxOf(abs(a / 8 - b / 8), abs(a % 8 - b % 8))
    }
}
