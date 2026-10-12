import Foundation

// v0.3.48 — 말을 **끌어서** 두기. 클릭-클릭(말 고르기 → 도착 칸)은 한 글자도 안 바뀐 채로 남는다.
//
// 세 조각으로 갈랐다 — 가른 이유는 전부 **재 볼 수 있느냐**다:
//   · 판단(둘 수 있는가 · 무엇을 보내는가 · 놓은 말을 어디에 그리는가)은 `ChessStore`(끌어서 두기 절).
//   · 누름·움직임·뗌을 **행동**으로 바꾸는 일은 이 파일의 `ChessBoardPointer`. 순수 값이라 SwiftUI 없이 전수로 잰다.
//   · 뷰(`ChessPlayBoard`)는 제스처 값을 해석기에 먹이고 나온 행동을 스토어에 옮기는 얇은 어댑터다.
//
// 이 파일에는 화면이 없다(AppKit·SwiftUI 금지 — 코어는 폰과 나눠 쓴다). 좌표는 뷰가 준 점 그대로이고
// 점 → 칸 변환은 뷰의 `ChessBoardGeometry` 가 끝내서 넘긴다.

// MARK: - 놓은 말

/// **끌어 놓은 말이 답을 기다리는 동안** 도착 칸에 머물게 하는 꼬리표.
///
/// 1:1 판은 서버가 권위라(ChessStore 머리말 ①) 놓는 순간 판을 바꾸지 않는다. 그런데 답까지 100~300ms 가
/// 걸리고, 그동안 말을 출발 칸에 도로 그리면 "놓았는데 되돌아갔다가 다시 미끄러진다" 가 된다. 그래서 **판은
/// 그대로 두고** 이 값 하나만 세워 뷰가 "출발 칸을 비우고 도착 칸에 그린다". 승격을 고르는 동안에도 같다.
///
/// ★ 이 값이 남으면 **유령 말**이 된다(판에는 없는 말이 그려진다). 그래서 지우는 자리를 믿지 않고
///   `ChessStore.pendingDrop` 이 **읽을 때마다** 판·수 번호·차례·출발 칸의 말을 다시 맞춰 본다.
package nonisolated struct ChessPendingDrop: Equatable, Sendable {
    package let matchID: String
    /// 놓을 때의 수 번호(= 그때의 `plyCount`). 판이 한 수라도 나아가면 이 꼬리표는 낡은 것이다.
    package let ply: Int
    package let from: ChessSquare
    package let to: ChessSquare
    /// 놓은 말(수를 **두기 전**의 말 — 승격하는 폰은 고르는 동안 폰으로 서 있다).
    package let piece: ChessPiece

    package init(matchID: String, ply: Int, from: ChessSquare, to: ChessSquare, piece: ChessPiece) {
        self.matchID = matchID
        self.ply = ply
        self.from = from
        self.to = to
        self.piece = piece
    }
}

// MARK: - 포인터 해석기

/// 판 위 포인터(누름 → 움직임 → 뗌)를 **행동**으로 바꾸는 작은 상태 기계. 순수 값 — 뷰가 `@State` 로 든다.
///
/// 여기 있는 판정 셋:
///  ① **문턱**: 누른 자리에서 `dragThreshold`(4pt) 이상 움직여야 끌기다. 그 밑에서 떼면 지금의 탭 그대로다.
///  ② **같은 칸 · 손떨림**: 끌기가 안 되는 누름(빈 칸·상대 말·도착 칸)은 뗀 칸이 누른 칸과 같으면 탭이다 —
///     손이 4pt 넘게 떨려도 같은 칸이면 탭이라 지금보다 덜 씹힌다. 뗀 칸이 **달라도** 뗀 점이 누른 점에서
///     문턱 밑이면 누른 칸의 탭이다: 칸 경계 바로 안쪽을 누른 손이 1pt 떨려 옆 칸에서 떼는 것은 클릭이지
///     끌기가 아니다(안 그러면 도착 칸 클릭이 문구도 없이 삼켜진다). 문턱 이상 움직여 다른 칸·판 밖에서
///     뗀 것만 아무 일도 없다 — 그 손은 클릭을 그만두고 떠난 것이다.
///  ③ **도착 칸을 눌렀으면 끌기가 아니다**: 이미 고른 말의 도착 칸을 누른 것은 클릭-도착이다.
///
/// 여기 **없는** 것: 그 말을 지금 끌 수 있는가(스토어 `grab(at:)` 이 누를 때 한 번 말해 준다) · 점이 어느 칸인가
/// (뷰의 기하가 바꿔서 준다) · 놓은 수가 합법인가(스토어 `placeDrop`).
///
/// 상태는 넷이다 — `idle` · `pressed`(눌렀고 아직 끌기가 아니다) · `dragging` · `spent`(이 누름은 끝났다:
/// 판 밖을 눌렀거나, 끌던 중에 취소됐거나, 스토어가 끌기를 거절했다 — 뗄 때까지 아무 행동도 안 낸다).
/// `spent` 가 따로 있는 까닭: 끌던 중에 판이 바뀌어 취소한 뒤에도 마우스는 여전히 눌려 있다. 그 누름이
/// `idle` 로 떨어지면 다음 움직임이 **새 누름**으로 읽혀, 취소한 말을 그 자리에서 다시 집는다.
package nonisolated struct ChessBoardPointer: Equatable, Sendable {
    /// 누른 칸에서 끌기가 될 수 있는가 — 누르는 순간 스토어가 말해 준다(`ChessStore.grab(at:)`).
    package enum Grab: Equatable, Sendable {
        /// 지금 끌 수 있는 내 말.
        case movable
        /// 내 말인데 지금은 못 끈다(내 차례가 아니다 · 보내는 중이다 · 갈 곳이 없다). 끌기는 시작되지 않고
        /// **뗄 때 한 번** 기존 탭 거절이 난다 — 끌려다 만 사람에게 이유를 말해 준다.
        case stuck
        /// 빈 칸 · 상대 말.
        case none
    }

    /// 해석기가 내는 행동. 뷰는 이 다섯만 옮긴다.
    package enum Action: Equatable, Sendable {
        /// 지금의 탭 그대로(`ChessStore.tap`).
        case tap(ChessSquare)
        /// 끌기를 시작한다(`ChessStore.beginDrag`). 거절되면 뷰가 `dragRefused()` 로 알린다.
        case beginDrag(ChessSquare)
        /// 끄는 말의 새 자리(뷰 좌표 그대로).
        case dragMoved(CGPoint)
        /// 놓았다. `on` 이 nil 이면 판 밖이다.
        case drop(from: ChessSquare, on: ChessSquare?)
        /// 끌기를 거둔다(말을 제자리에).
        case cancel
    }

    /// 끌기 문턱(pt). 이 값 **이상** 움직이면 끌기이고 그 밑은 탭이다.
    /// 문턱이 있어야 하는 까닭: 0 이면 클릭하다 손이 조금만 흔들려도 끌기가 되어 "고른 말을 다시 눌러 해제" 가
    /// 죽는다(끌기는 출발 칸에 도로 놓아도 고르기를 남긴다). 76pt 칸의 5% 남짓이라 말을 집어 옮기는 손에는 안 걸린다.
    package static let dragThreshold: CGFloat = 4

    private enum Phase: Equatable, Sendable {
        case idle
        case pressed(square: ChessSquare, grab: Grab)
        case dragging(from: ChessSquare)
        case spent
    }

    private var phase: Phase = .idle
    /// 이 누름이 시작된 점. `idle` 이면 nil 이다.
    private var origin: CGPoint?

    package init() {}

    package var isIdle: Bool { phase == .idle }

    /// 지금 끌고 있는 말의 출발 칸(끌기가 아니면 nil).
    package var draggingFrom: ChessSquare? {
        if case .dragging(let from) = phase { return from }
        return nil
    }

    /// 그 점에서 시작한 누름을 **이미 따라가고 있는가**. 제스처는 누름을 따로 알려 주지 않고 "시작점이 붙은
    /// 변화" 만 주므로, 뷰는 이 물음이 거짓일 때 그 변화를 새 누름으로 넣는다(뗌 없이 끝난 앞 누름도 여기서 걸린다).
    package func isTracking(pressAt point: CGPoint) -> Bool {
        phase != .idle && origin == point
    }

    // MARK: 입력

    /// 눌렀다. `square` 가 nil 이면 판 밖이다. `isSelectionTarget` 은 그 칸이 이미 고른 말의 도착 칸인가다.
    package mutating func press(at point: CGPoint, square: ChessSquare?, grab: Grab,
                                isSelectionTarget: Bool) -> [Action] {
        // 앞 누름이 뗌 없이 끝났다(제스처가 중간에 죽었다) — 끌던 말부터 거두고 새 누름을 받는다.
        let abandoned: [Action] = draggingFrom == nil ? [] : [.cancel]
        origin = point
        guard let square else {
            phase = .spent
            return abandoned
        }
        // ③ 도착 칸을 눌렀으면 끌기가 아니다 — 그 칸에 무엇이 있든 클릭-도착으로만 읽는다.
        phase = .pressed(square: square, grab: isSelectionTarget ? .none : grab)
        return abandoned
    }

    /// 누른 채 움직였다.
    package mutating func move(to point: CGPoint) -> [Action] {
        switch phase {
        case .pressed(let square, .movable):
            guard hasCrossedThreshold(point) else { return [] }
            phase = .dragging(from: square)
            return [.beginDrag(square), .dragMoved(point)]
        case .dragging:
            return [.dragMoved(point)]
        case .idle, .pressed, .spent:
            return []
        }
    }

    /// 뗐다. `square` 가 nil 이면 판 밖에서 뗐다.
    package mutating func release(at point: CGPoint, square: ChessSquare?) -> [Action] {
        defer {
            phase = .idle
            origin = nil
        }
        switch phase {
        case .pressed(let pressed, .movable):
            // 움직임 없이 뗌만 멀리서 온 누름(빠르게 튕긴 끌기)도 끌기다 — 문턱은 **뗀 자리**로도 잰다.
            if hasCrossedThreshold(point) { return [.beginDrag(pressed), .drop(from: pressed, on: square)] }
            return [.tap(pressed)]                              // ① 문턱 밑 = 지금의 탭
        case .pressed(let pressed, .stuck):
            return [.tap(pressed)]                              // 끌려다 만 내 말 — 어디서 떼든 거절 한 번
        case .pressed(let pressed, .none):
            // ② 같은 칸에서 뗐거나, 칸은 달라도 문턱 밑(손떨림)이면 **누른 칸**의 탭.
            //    문턱 이상 움직여 다른 칸·판 밖에서 뗀 것만 조용히 버린다.
            if square == pressed || !hasCrossedThreshold(point) { return [.tap(pressed)] }
            return []
        case .dragging(let from):
            return [.drop(from: from, on: square)]
        case .idle, .spent:
            return []
        }
    }

    /// 끄는 중에 판이 바뀌었다(상대 기권·시간패·판 교체·내 차례 아님·왕복 시작·창 가림/닫힘).
    ///
    /// 끌던 중이면 거두고 이 누름을 **소진**시킨다 — 그 뒤 마우스를 떼도 수가 나가지 않는다.
    /// 아직 끌기 전이면 "끌 수 있다" 는 누를 때의 판정만 버린다(그 판정은 바뀐 판의 것이 아니다). 탭은 남긴다:
    /// 같은 칸에서 떼면 지금처럼 스토어가 **바뀐 판에 대고** 다시 판단한다(클릭 동작을 건드리지 않는다).
    package mutating func cancel() -> [Action] {
        switch phase {
        case .dragging:
            phase = .spent
            return [.cancel]
        case .pressed(let square, _):
            phase = .pressed(square: square, grab: .none)
            return []
        case .idle, .spent:
            return []
        }
    }

    /// 스토어가 끌기를 거절했다(`beginDrag` 가 false — 누른 뒤 문턱을 넘기 전에 판이 바뀌었다).
    /// 거절 문구는 스토어가 이미 말했으므로 이 누름은 조용히 소진된다.
    package mutating func dragRefused() {
        if case .dragging = phase { phase = .spent }
    }

    private func hasCrossedThreshold(_ point: CGPoint) -> Bool {
        guard let origin else { return false }
        let dx = point.x - origin.x, dy = point.y - origin.y
        // 제곱끼리 견준다 — 제곱근을 거치지 않으니 경계(정확히 4pt)가 그 반올림에 흔들리지 않는다.
        return dx * dx + dy * dy >= Self.dragThreshold * Self.dragThreshold
    }
}
