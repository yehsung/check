import Foundation

// 아잉 뒤집기 — 돌이 **뒤집히는 동안**을 담는 순수 값. 계약은 설계서 FLIP/SPEC.md §4.5.
//
// 체스 `ChessMoveFlight` 규약을 따른다: 애니메이션을 `(판 id, 시작 시각, 놓은 칸, 색, 뒤집힐 칸, 칸마다 지연)` 값으로 두고
// **어떤 프레임이든 `now` 하나로 결정**한다(`withAnimation` 은 중간 프레임을 밖에서 재현할 수 없어 시험을 못 짠다).
//
// 지키는 약속:
//  · 칸마다 가로 비율을 |cos| 로 줄였다가(반에서 0) 다시 편다. **반을 지나는 순간 색이 바뀐다**(둔 사람의 상대 색 → 둔 사람 색).
//  · **불투명도는 건드리지 않는다** — 돌 색이 늘 극단이라 렌더 감지기가 돌을 센다. 이징으로 불투명도를 깎으면
//    밀려나기 전에 사라진다.
//  · 지연은 놓은 칸에서의 거리순(행·열 2차원 체비쇼프 거리 — 같은 고리는 같이 뒤집힌다).
//  · 응답이 **온 뒤에** 시작한다(낙관적 그림 없음). 새 판이 직전 판 + **돌 한 수**(+ 그 뒤 자동 패스)일 때만 그 수의
//    `flipped` 로 시작하고, 한 번에 돌 두 수 이상 건너뛰면 애니메이션 없이 바로 맞춘다. 다른 판 id 면 무시한다.
//  · 화면 좌표·그림은 없다(뷰 몫). 입력·합법성·판정은 이 값을 보지 않는다.

/// 판 위에서 **뒤집히는 중인 수 하나**. 순수 값 — `now` 하나면 어느 프레임이든 결정적이다.
package nonisolated struct ReversiFlipAnimation: Equatable, Sendable {
    /// 돌 하나가 뒤집히는 시간(초).
    package static let flipDuration: TimeInterval = 0.32
    /// 놓은 칸에서 한 고리 멀어질 때마다 늦게 시작하는 시간(초).
    package static let ringDelay: TimeInterval = 0.06

    package let matchID: String
    package let startedAt: Date
    /// 이번에 놓은 돌의 칸(뒤집히지 않는다 — 그냥 나타난다).
    package let placedIdx: Int
    /// 둔 색 = 뒤집힌 뒤의 색.
    package let color: ReversiColor
    /// 뒤집히는 칸(오름차순, 서버 `flipped` 그대로).
    package let flipped: [Int]
    /// 칸마다 시작 지연(초). 키는 `flipped` 의 칸과 같다.
    package let delays: [Int: TimeInterval]

    package init(matchID: String, startedAt: Date, placedIdx: Int, color: ReversiColor, flipped: [Int]) {
        self.matchID = matchID
        self.startedAt = startedAt
        self.placedIdx = placedIdx
        self.color = color
        self.flipped = flipped
        var delays: [Int: TimeInterval] = [:]
        for idx in flipped {
            delays[idx] = Double(max(0, Self.ringDistance(placedIdx, idx) - 1)) * Self.ringDelay
        }
        self.delays = delays
    }

    /// 마지막 칸이 다 뒤집히기까지 걸리는 시간(초).
    package var duration: TimeInterval { (delays.values.max() ?? 0) + Self.flipDuration }

    /// 다 끝났는가(뷰는 이때 애니메이션을 내리고 판을 그대로 그린다).
    package func isFinished(now: Date) -> Bool { now.timeIntervalSince(startedAt) >= duration }

    /// 칸의 진행률 0…1. 이 수에서 뒤집히는 칸이 아니면 nil.
    package func progress(idx: Int, now: Date) -> Double? {
        guard let delay = delays[idx] else { return nil }
        let elapsed = now.timeIntervalSince(startedAt) - delay
        return min(1, max(0, elapsed / Self.flipDuration))
    }

    /// 칸의 가로 비율(1 = 온전한 원, 0 = 옆으로 선 순간). 뒤집히는 칸이 아니면 1.
    package func xScale(idx: Int, now: Date) -> Double {
        guard let p = progress(idx: idx, now: now) else { return 1 }
        return abs(cos(Double.pi * p))
    }

    /// 지금 그릴 색. 반 전에는 옛 색(둔 사람의 상대), 반부터 새 색. 뒤집히는 칸이 아니면 nil(판 그대로 그린다).
    package func displayedColor(idx: Int, now: Date) -> ReversiColor? {
        guard let p = progress(idx: idx, now: now) else { return nil }
        return p < 0.5 ? color.opponent : color
    }

    /// 직전 판과 새 판으로 애니메이션을 정한다. 같은 판이고 `move_count` 가 **돌 한 수**(1) 또는 **돌 한 수 + 자동 패스**(2)
    /// 만큼만 올랐고, 그 기록이 손에 있을 때만 값이 나온다. 그 밖(다른 판 · 줄어듦 · 두 수 이상 건너뜀 · 패스만 · 기록 구멍)은 nil.
    package static func make(
        from previous: ReversiMatchState?, to next: ReversiMatchState, at now: Date
    ) -> ReversiFlipAnimation? {
        guard let previous, previous.id == next.id else { return nil }
        return make(matchID: next.id, previousMoveCount: previous.moveCount, nextMoveCount: next.moveCount,
                    plies: next.plies, at: now)
    }

    /// 같은 판정의 값 버전 — 관전(`ReversiSpectating`)처럼 `ReversiMatchState` 가 없는 깔때기가 쓴다.
    /// `plies` 는 새 판의 기록(이번에 온 수가 들어 있어야 한다).
    package static func make(
        matchID: String, previousMoveCount: Int, nextMoveCount: Int, plies: [ReversiPly], at now: Date
    ) -> ReversiFlipAnimation? {
        let delta = nextMoveCount - previousMoveCount
        guard delta == 1 || delta == 2 else { return nil }
        let fresh = plies
            .filter { $0.seq > previousMoveCount && $0.seq <= nextMoveCount }
            .sorted { $0.seq < $1.seq }
        guard fresh.count == delta, let stone = fresh.first, stone.seq == previousMoveCount + 1,
              stone.kind == .stone, let idx = stone.idx, !stone.flipped.isEmpty
        else { return nil }
        if delta == 2, fresh[1].kind != .pass { return nil }
        return ReversiFlipAnimation(
            matchID: matchID, startedAt: now, placedIdx: idx, color: stone.color, flipped: stone.flipped)
    }

    /// 두 칸의 고리 거리(행·열 2차원 — 1차원 idx 차로 재지 않는다, V-01).
    private static func ringDistance(_ a: Int, _ b: Int) -> Int {
        max(abs(a / 8 - b / 8), abs(a % 8 - b % 8))
    }
}
