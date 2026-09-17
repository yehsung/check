import CheckCore
import CoreGraphics
import Foundation

// 오목 판 좌표 · 폰 탭 규칙(순수 — macOS `swift test` 로 검증한다).
//
// 판 좌표계는 맥 `GomokuBoardGeometry`(Sources/check/GomokuPanel.swift)와 **같은 식**이다: 바깥 여백 6% 안에
// 15줄을 같은 간격으로 긋고, 누른 자리에서 가장 가까운 교차점을 고르되 반 칸을 넘으면 판 밖이다.
// 맥 타입은 앱 타깃 안이라 폰 모듈이 못 부른다 — 식이 갈리지 않게 테스트가 교차점 225개 전부를 되묻는다.

/// 판(또는 판의 일부) 그림의 좌표계. 행은 **아래가 1**(렌주 표기 · 서버 y)이고 화면 y 는 위가 0 이라 뒤집는다.
package struct GomokuPhoneBoardGeometry: Equatable, Sendable {
    /// 그림 한 변(pt).
    package let side: CGFloat
    /// 그리는 줄 수(전체 판 15, 규칙 예시 9).
    package var lines: Int
    /// 가장 왼쪽 열의 x · 가장 아래 행의 y(규칙 예시는 가운데만 잘라 그린다).
    package var originX: Int
    package var originY: Int
    /// 바깥 여백 비율(좌표 글자와 가장자리 돌이 들어갈 자리).
    package var insetRatio: CGFloat

    package init(side: CGFloat, lines: Int = GomokuBoard.size, originX: Int = 0, originY: Int = 0, insetRatio: CGFloat = 0.06) {
        self.side = side
        self.lines = lines
        self.originX = originX
        self.originY = originY
        self.insetRatio = insetRatio
    }

    package var inset: CGFloat { side * insetRatio }
    package var cell: CGFloat { (side - inset * 2) / CGFloat(lines - 1) }

    package func contains(_ point: GomokuPoint) -> Bool {
        point.x >= originX && point.x < originX + lines && point.y >= originY && point.y < originY + lines
    }

    /// 교차점의 화면 위치.
    package func location(of point: GomokuPoint) -> CGPoint {
        CGPoint(
            x: inset + CGFloat(point.x - originX) * cell,
            y: inset + CGFloat(originY + lines - 1 - point.y) * cell
        )
    }

    /// 화면 위치에서 가장 가까운 교차점. 가장 가까운 교차점에서 가로·세로 어느 쪽이든 **반 칸을 넘으면** nil(판 밖).
    package func point(at location: CGPoint) -> GomokuPoint? {
        guard cell > 0 else { return nil }
        let column = (location.x - inset) / cell
        let row = (location.y - inset) / cell
        let ix = Int(column.rounded())
        let iy = Int(row.rounded())
        guard (0..<lines).contains(ix), (0..<lines).contains(iy),
              abs(column - CGFloat(ix)) <= 0.5, abs(row - CGFloat(iy)) <= 0.5 else { return nil }
        return GomokuPoint(x: originX + ix, y: originY + lines - 1 - iy)
    }

    /// 화점(D4·L4·H8·D12·L12).
    package static let starPoints: [GomokuPoint] = [(3, 3), (11, 3), (7, 7), (3, 11), (11, 11)].compactMap {
        GomokuPoint(x: $0.0, y: $0.1)
    }
}

/// 탭 한 번이 무엇이 되는가.
package enum GomokuTapOutcome: Equatable, Sendable {
    /// 판 밖(격자 바깥 여백). 조용하다 — 거절이 아니라 빈 곳을 누른 것이다.
    case none
    /// 미리보기 돌을 이 칸에 세웠다(또는 옮겼다).
    case preview(GomokuPoint)
    /// 같은 칸을 다시 눌렀다 — 둔다(`GomokuStore.place`).
    case place(GomokuPoint)
    /// 지금 둘 수 없는 칸·때다. **스토어에 넘겨** 거절 이유 한 줄과 진단 줄을 남기게 한다(맥과 같은 규약 —
    /// 뷰가 미리 걸러 조용히 삼키면 "눌렀는데 아무 반응이 없다"가 된다). 스토어는 같은 조건을 먼저 보고 서버로 안 보낸다.
    case refuse(GomokuPoint)
}

/// 폰의 "첫 탭은 미리보기, 같은 칸 다시 탭하면 착수"(SPEC-ios §3.5). 맥은 호버로 미리보기를 세우고 클릭으로 바로 둔다.
///
/// 미리보기는 **그 판 그 수(match id · move_count)** 에서 세운 것만 산다. 미리보기를 세운 뒤 서버가 자동 착수로 수를
/// 넘겼거나 판이 바뀌면, 같은 칸을 다시 눌러도 곧바로 두지 않고 미리보기부터 다시 세운다 — 사용자가 본 판과 다른 판에
/// 돌이 놓이면 안 된다.
package struct GomokuTapPreview: Equatable, Sendable {
    package private(set) var point: GomokuPoint?
    private var matchID: String?
    private var moveCount: Int?

    package init() {}

    /// 지금 판에서 그려야 할 미리보기 자리(없으면 nil). 판이 바뀌었거나 둘 수 없는 때면 그리지 않는다.
    package func visiblePoint(match: GomokuMatchState, isBusy: Bool, forbidden: [GomokuPoint: GomokuForbiddenReason]) -> GomokuPoint? {
        guard let point, isCurrent(match), Self.canPlace(match: match, isBusy: isBusy),
              match.board[point] == nil, forbidden[point] == nil else { return nil }
        return point
    }

    /// 탭 한 번. `point` 는 `GomokuPhoneBoardGeometry.point(at:)` 의 결과(판 밖이면 nil).
    package mutating func tap(
        _ point: GomokuPoint?, match: GomokuMatchState, isBusy: Bool,
        forbidden: [GomokuPoint: GomokuForbiddenReason]
    ) -> GomokuTapOutcome {
        guard let point else { return .none }
        guard Self.canPlace(match: match, isBusy: isBusy), match.board[point] == nil, forbidden[point] == nil else {
            clear()
            return .refuse(point)
        }
        if self.point == point, isCurrent(match) {
            clear()
            return .place(point)
        }
        self.point = point
        matchID = match.id
        moveCount = match.moveCount
        return .preview(point)
    }

    package mutating func clear() {
        point = nil
        matchID = nil
        moveCount = nil
    }

    private func isCurrent(_ match: GomokuMatchState) -> Bool {
        matchID == match.id && moveCount == match.moveCount
    }

    /// 지금 내가 둘 수 있는 때인가(끝나지 않음 · 내 차례 · 왕복 중 아님). 스토어 `place` 의 앞 가드와 같은 조건이다.
    package static func canPlace(match: GomokuMatchState, isBusy: Bool) -> Bool {
        !match.isFinished && match.turn == match.myColor && !isBusy
    }
}

/// [기권] 누름 받기(맥 `GomokuResignGuard` 와 같은 규칙) — 대국 화면이 나타난 직후의 누름은 이 화면을 보고 누른 것이 아니다
/// (로비 [수락]을 두 번 누른 두 번째 누름이 막 열린 대국 화면에 떨어지는 경로).
package enum GomokuPhoneResignGuard {
    package static let armDelay: TimeInterval = 1.0

    package static func acceptsTap(shownAt: Date?, now: Date) -> Bool {
        guard let shownAt else { return true }
        return now.timeIntervalSince(shownAt) >= armDelay
    }
}

/// 판돈 창 고르기(맥 `GomokuStakeSelection`): 이미 고른 판돈을 다시 누르면 해제.
package enum GomokuPhoneStakeSelection {
    package static func toggled(current: GomokuStake?, tapped: GomokuStake) -> GomokuStake? {
        current == tapped ? nil : tapped
    }

    /// 이 판돈을 걸 수 있는가. **잔액을 모르면(nil) 막지 않는다**(맥 0.3.29 규칙 — 서버가 거절하면 그때 안내한다).
    package static func affordable(_ stake: GomokuStake, balance: Int?) -> Bool {
        guard let balance else { return true }
        return balance >= stake.rawValue
    }
}

/// 로비 [도전] 활성 조건(맥 `GomokuChallengeGate` 와 같다 — **근무 여부를 보지 않는다**).
package enum GomokuPhoneChallengeGate {
    @MainActor
    package static func isEnabled(user: GomokuUser, store: GomokuStore) -> Bool {
        user.isCapable && !user.inMatch && store.outgoing == nil && store.match == nil && !store.isBusy
    }
}

/// 끝난 판의 승리선(w15 — 비평 "이긴 5목이 강조되지 않는다"). 마지막 수를 지나는 가로·세로·두 대각선 중
/// 같은 색이 **5개 이상** 이어진 줄의 양 끝 돌을 돌려준다(장목이면 그 전체). 5목으로 끝난 판이 아니면 nil.
package enum GomokuPhoneWinLine {
    package static func ends(board: GomokuBoard, lastMove: GomokuPoint?) -> (from: GomokuPoint, to: GomokuPoint)? {
        guard let lastMove, let color = board[lastMove] else { return nil }
        for (dx, dy) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
            var from = lastMove
            var to = lastMove
            var count = 1
            while let next = GomokuPoint(x: to.x + dx, y: to.y + dy), board[next] == color {
                to = next
                count += 1
            }
            while let next = GomokuPoint(x: from.x - dx, y: from.y - dy), board[next] == color {
                from = next
                count += 1
            }
            if count >= 5 { return (from, to) }
        }
        return nil
    }
}
