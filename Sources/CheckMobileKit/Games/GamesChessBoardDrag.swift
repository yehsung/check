import CheckCore
import CoreGraphics
import Foundation
import Observation
import SwiftUI

// 폰 1.0.16 — 체스 판에서 말을 **끌어 두기**(맥 v0.3.48 `ChessPlayBoard` 의 폰 짝). 탭 2단은 그대로 남는다.
//
// 맥과 같은 세 조각이다. 판단은 코어 `ChessStore`(`grab`·`beginDrag`·`placeDrop`·`finishDrop`), 누름 해석은 코어
// `ChessBoardPointer`, 뷰는 얇은 어댑터. 폰에서 **새로 생긴 일은 둘**이고 이 파일이 그 둘을 쥔다:
//
//  ① **판이 ScrollView 안에 있다.** 맥에는 없던 충돌이다 — 판 위에서 시작한 손이 말을 집는 손인지 화면을 내리는
//     손인지를 누군가 정해야 한다. 그래서 해석기 앞에 문을 하나 더 세운다(`GamesChessDragGate`·`GamesChessBoardTouch`).
//  ② **손가락이 말을 가린다.** 마우스 커서는 말을 안 가린다. 그래서 든 말은 손 **위로** 띄우되, 놓을 칸은 말이
//     아니라 **손가락 밑**으로 읽는다(`GamesChessDragHand`) — 말 밑으로 읽으면 맨 아래 줄에 영영 못 놓는다.
//
// 이 파일은 `#if os(iOS)` 밖이다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다'). UIKit 을 만나는 곳은
// `GamesChessBoardTouchSurface.swift` 하나이고, 거기는 손가락 좌표를 이 파일의 컨트롤러에 넣을 뿐 판단이 없다.

// MARK: - 문턱의 판결

/// 손이 문턱을 **처음 넘은 순간** 이 손을 집을지 스크롤에 넘길지를 가른다. 순수 값.
package enum GamesChessDragGate {
    package enum Verdict: Equatable, Sendable {
        case pickUp
        case yieldToScroll
    }

    /// 움직임과 **모든** 갈 곳 사이의 코사인이 이 값보다 작으면 "그쪽으로 끌 리가 없다" 로 읽는다(120도 밖).
    /// 90도로 자르면 문턱(4pt)의 손떨림만으로도 판결이 뒤집힌다 — 4pt 에서 1pt 흔들림은 14도다. 그래서 여유를 둬
    /// 말을 집으려는 손은 거의 다 집히고, **갈 곳의 정반대로 쓸어내린** 손만 스크롤로 간다.
    package static let oppositeCosine: CGFloat = -0.5

    /// 스토어가 말한 끌기 가능 여부에 "놓은 말이 답을 기다리는가" 를 더한다.
    ///
    /// ★ 스토어 `grab` 은 `isBusy` 만 본다. 뷰가 왕복을 Task 로 넘기므로 뗀 틱과 `isBusy` 사이에 한 홉이 있는데,
    ///   그 틈에 집은 말은 놓을 때 `placeDrop` 이 거절한다 — 문구까지 간 뒤에야 알게 된다. 폰은 틈에 집지 않는다.
    package static func grab(_ fromStore: ChessBoardPointer.Grab,
                             hasPendingDrop: Bool) -> ChessBoardPointer.Grab {
        guard hasPendingDrop, fromStore == .movable else { return fromStore }
        return .stuck
    }

    /// 문턱을 넘은 판결. `motion` 은 누른 점에서 지금 점까지, `targets` 는 갈 곳들로 가는 **화면** 벡터다.
    ///
    /// | 시작 칸            | 방향                       | 판결     |
    /// | ------------------ | -------------------------- | -------- |
    /// | 빈 칸·상대 말·도착 칸 | 어디든                     | 스크롤   |
    /// | 내 말이지만 못 끈다   | 어디든                     | 스크롤   |
    /// | 끌 수 있는 내 말     | 갈 곳 중 하나라도 그쪽      | **집는다** |
    /// | 끌 수 있는 내 말     | 모든 갈 곳의 정반대(폰을 뒤로) | 스크롤   |
    ///
    /// 폰이 앞으로만 가므로 "세로면 스크롤" 로는 못 가른다 — 폰을 집는 손이 곧 세로다.
    /// 방향이 하는 일은 하나, 어디로도 못 가는 쪽으로 쓸어내린 손을 스크롤에 돌려주는 것이다.
    package static func verdict(grab: ChessBoardPointer.Grab, motion: CGSize,
                                targets: [CGSize]) -> Verdict {
        guard grab == .movable else { return .yieldToScroll }
        let length = (motion.width * motion.width + motion.height * motion.height).squareRoot()
        // 갈 곳을 모르면 방향으로 거절하지 않는다(`grab` 이 끌 수 있다고 했으면 스토어를 믿는다).
        guard length > 0, !targets.isEmpty else { return .pickUp }
        for target in targets {
            let reach = (target.width * target.width + target.height * target.height).squareRoot()
            guard reach > 0 else { continue }
            let cosine = (motion.width * target.width + motion.height * target.height) / (length * reach)
            if cosine >= oppositeCosine { return .pickUp }
        }
        return .yieldToScroll
    }

    /// 그 칸에서 갈 곳들로 가는 화면 벡터. 뒤집기는 기하 안에서 끝난다 — 흑 판에서 폰의 앞이 화면 위인 것도 여기서 나온다.
    package static func targetVectors(from square: ChessSquare, targets: Set<ChessSquare>,
                                      geometry: ChessPhoneBoardGeometry) -> [CGSize] {
        let start = geometry.center(of: square)
        return targets.map { target in
            let end = geometry.center(of: target)
            return CGSize(width: end.x - start.x, height: end.y - start.y)
        }
    }
}

// MARK: - 손가락 한 번

/// 터치 한 번(누름 → 움직임 → 뗌)의 상태 기계. 순수 값 — 코어 `ChessBoardPointer` 를 품고 그 앞에 스크롤 문을 세운다.
///
/// 맥과 갈리는 곳 둘:
///  · **문턱을 넘어도 집지 않는 손이 있다.** 맥의 마우스에는 스크롤이 없어 해석기가 곧바로 끌기로 간다.
///  · **슬롭(`tapSlop`) 안에서 뗀 손은 칸 경계를 넘었어도 누른 칸의 탭이다.** 맥은 문턱 이상 움직여 다른 칸에서 떼면
///    버리는데, 손가락은 4pt 를 예사로 흔들리므로 그대로 옮기면 칸 가장자리 도착 탭이 문구도 없이 사라진다.
///    슬롭을 넘은 손은 이미 스크롤에 넘어갔다.
package struct GamesChessBoardTouch: Equatable, Sendable {
    package enum Stage: Equatable, Sendable {
        case idle
        /// 눌렀고 문턱을 아직 안 넘었다.
        case undecided
        /// 말을 집었다.
        case dragging
        /// 집지 않기로 했다 — 슬롭 안에서 떼면 탭, 슬롭을 넘으면 스크롤.
        case yielded
        /// 끌던 중에 거뒀다. 손이 떨어질 때까지 아무것도 안 낸다(맥 `ChessBoardPointer.spent` 와 같은 까닭).
        case spent
    }

    /// 탭이 스크롤로 넘어가는 거리(pt). 맥의 끌기 문턱과 다른 값이다 — 시스템 스크롤이 움직이기 시작하는 거리와 맞췄다.
    package static let tapSlop: CGFloat = 10

    package private(set) var stage: Stage = .idle
    private var pointer = ChessBoardPointer()
    private var origin: CGPoint = .zero
    private var pressedSquare: ChessSquare?
    private var grab: ChessBoardPointer.Grab = .none
    private var targets: [CGSize] = []
    private var leftSlop = false

    package init() {}

    /// 지금 끌고 있는 말의 출발 칸.
    package var draggingFrom: ChessSquare? { stage == .dragging ? pointer.draggingFrom : nil }
    /// 이 손을 스크롤에 넘겨야 하는가. 참이 된 뒤로 이 손은 탭도 끌기도 아니다.
    package var handsOffToScroll: Bool { stage == .yielded && leftSlop }

    package mutating func press(at point: CGPoint, square: ChessSquare?, grab: ChessBoardPointer.Grab,
                                isSelectionTarget: Bool, targets: [CGSize]) -> [ChessBoardPointer.Action] {
        let abandoned = pointer.press(at: point, square: square, grab: grab, isSelectionTarget: isSelectionTarget)
        origin = point
        pressedSquare = square
        // 도착 칸을 눌렀으면 끌기가 아니다(해석기 ③과 같은 판정을 문도 본다 — 문이 먼저 답하므로).
        self.grab = isSelectionTarget ? .none : grab
        self.targets = targets
        leftSlop = false
        stage = square == nil ? .yielded : .undecided
        return abandoned
    }

    package mutating func move(to point: CGPoint) -> [ChessBoardPointer.Action] {
        switch stage {
        case .undecided:
            guard crossedThreshold(point) else { return [] }
            return decide(at: point)
        case .dragging:
            return pointer.move(to: point)
        case .yielded:
            noteSlop(point)
            return []
        case .idle, .spent:
            return []
        }
    }

    /// 뗐다. `square` 는 **손가락 밑** 칸이고 판 밖이면 nil 이다.
    package mutating func release(at point: CGPoint, square: ChessSquare?) -> [ChessBoardPointer.Action] {
        defer { self = GamesChessBoardTouch() }
        // 움직임 없이 뗌만 멀리서 온 손(빠르게 튕긴 손)도 문을 지난다 — 판결은 **뗀 자리**로도 잰다.
        if stage == .undecided, crossedThreshold(point) {
            if GamesChessDragGate.verdict(grab: grab, motion: motion(to: point), targets: targets) == .pickUp {
                return pointer.release(at: point, square: square)
            }
            stage = .yielded
        }
        switch stage {
        case .undecided:
            return pressedSquare.map { [.tap($0)] } ?? []
        case .dragging:
            return pointer.release(at: point, square: square)
        case .yielded:
            noteSlop(point)
            guard !leftSlop, let pressedSquare else { return [] }
            return [.tap(pressedSquare)]
        case .idle, .spent:
            return []
        }
    }

    /// 전제가 바뀌었다. 끌던 중이면 거두고 이 손을 소진시킨다. 아직 집기 전이면 "집을 수 있다" 는 판정만 버린다 —
    /// 탭은 남긴다(같은 칸에서 떼면 스토어가 바뀐 판에 대고 다시 판단한다. 맥 `ChessBoardPointer.cancel` 과 같다).
    package mutating func revoke() -> [ChessBoardPointer.Action] {
        let actions = pointer.cancel()
        switch stage {
        case .dragging: stage = .spent
        case .undecided: grab = .none
        case .idle, .yielded, .spent: break
        }
        return actions
    }

    /// 시스템이 터치를 거뒀다(전화·알림 센터·시트). 끌던 말을 거두고 처음으로 돌아간다.
    package mutating func abandon() -> [ChessBoardPointer.Action] {
        let actions: [ChessBoardPointer.Action] = stage == .dragging ? [.cancel] : []
        self = GamesChessBoardTouch()
        return actions
    }

    /// 스토어가 끌기를 거절했다(누른 뒤 문턱 전에 판이 바뀌었다 — 문구는 스토어가 말했다). 이 손은 스크롤로 간다.
    package mutating func dragRefused() {
        pointer.dragRefused()
        stage = .yielded
        leftSlop = true
    }

    private mutating func decide(at point: CGPoint) -> [ChessBoardPointer.Action] {
        if GamesChessDragGate.verdict(grab: grab, motion: motion(to: point), targets: targets) == .pickUp {
            stage = .dragging
            return pointer.move(to: point)
        }
        _ = pointer.cancel()
        stage = .yielded
        noteSlop(point)
        return []
    }

    private func motion(to point: CGPoint) -> CGSize {
        CGSize(width: point.x - origin.x, height: point.y - origin.y)
    }

    private func crossedThreshold(_ point: CGPoint) -> Bool {
        let delta = motion(to: point), threshold = ChessBoardPointer.dragThreshold
        return delta.width * delta.width + delta.height * delta.height >= threshold * threshold
    }

    private mutating func noteSlop(_ point: CGPoint) {
        let delta = motion(to: point)
        if delta.width * delta.width + delta.height * delta.height >= Self.tapSlop * Self.tapSlop {
            leftSlop = true
        }
    }
}

// MARK: - 전제

/// 끌기의 전제(맥 `ChessPlayBoard.DragPremise` 와 같은 넷 + 판 id). 하나라도 바뀌면 끌던 말을 거둔다 —
/// 상대 기권·시간패(`isMyTurn`) · 판 교체(`matchID`) · 수가 나아감(`ply`) · 왕복 시작(`isBusy`) · 화면 떠남(`isWindowVisible`).
package struct GamesChessDragPremise: Equatable, Sendable {
    package let matchID: String
    package let ply: Int
    package let isMyTurn: Bool
    package let isBusy: Bool
    package let isWindowVisible: Bool

    /// 스토어의 **지금** 전제. 판이 없으면 nil 이다(그것도 전제가 바뀐 것이다).
    @MainActor
    package init?(store: ChessStore) {
        guard let current = store.match else { return nil }
        matchID = current.id
        ply = current.plyCount
        isMyTurn = current.isMyTurn
        isBusy = store.isBusy
        isWindowVisible = store.isWindowVisible
    }
}

// MARK: - 손에 든 말

/// 판 위에서 제자리를 떠나 있는 말 한 장 — 끄는 중이거나, 놓고 답을 기다리는 중이다(맥 `ChessBoardLift` 의 짝).
package struct GamesChessBoardLift: Equatable, Sendable {
    package enum Place: Equatable, Sendable {
        /// 끄는 중 — 그림은 판 위에 뜬 `GamesChessHeldPiece` 가 맡고, 캔버스는 출발 칸만 비운다.
        /// 손 좌표를 여기 싣지 않는 것이 일부러다: 실으면 손이 움직일 때마다 64칸을 다시 그린다.
        case hand
        /// 놓았다 — 그 칸에 그대로 선다(답을 기다리는 중 · 승격을 고르는 중).
        case square(ChessSquare)
    }

    package let piece: ChessPiece
    /// 그리지 않을 칸(= 출발 칸). 안 빼면 같은 말이 두 자리에 보인다.
    package let from: ChessSquare
    package let place: Place

    package init(piece: ChessPiece, from: ChessSquare, place: Place) {
        self.piece = piece
        self.from = from
        self.place = place
    }

    /// 지금 판에 든 말. **놓은 말이 먼저다**(스토어가 판·수 번호를 맞춰 본 값 — 자기 치유는 거기서 한다).
    /// 끄는 말은 셋이 다 맞을 때만 그린다: 컨트롤러가 끄는 중이다 · 스토어 걸쇠가 같은 칸이다 · 그 칸에 말이 있다.
    /// 하나라도 어긋나면 말은 판이 말하는 제자리에 그려진다 — 유령 말을 구조적으로 막는다.
    package static func resolve(pending: ChessPendingDrop?, draggingFrom: ChessSquare?,
                                latch: ChessSquare?, position: ChessPosition?) -> GamesChessBoardLift? {
        if let pending {
            return GamesChessBoardLift(piece: pending.piece, from: pending.from, place: .square(pending.to))
        }
        guard let draggingFrom, latch == draggingFrom, let piece = position?[draggingFrom] else { return nil }
        return GamesChessBoardLift(piece: piece, from: draggingFrom, place: .hand)
    }

    /// 손가락 밑이 갈 수 있는 칸이면 그 칸(놓으면 어디로 가는지 보여 준다).
    package static func dropTarget(lift: GamesChessBoardLift?, handSquare: ChessSquare?,
                                   targets: Set<ChessSquare>) -> ChessSquare? {
        guard lift?.place == .hand, let handSquare, targets.contains(handSquare) else { return nil }
        return handSquare
    }
}

/// 손에 든 말의 자리. 순수 — 좌표는 판 좌표, y 는 아래로 자란다.
package enum GamesChessDragHand {
    /// 든 말의 크기(칸 대비). 손가락 위로 떠도 무슨 말인지 읽히는 크기다.
    package static let pieceScale: CGFloat = 1.45
    /// 손가락 끝에서 말 **중심**까지의 최소 거리(pt). 손가락 크기는 판 크기를 안 따라가므로 칸 비율만으로 정하면
    /// 작은 판(분할 화면)에서 말이 손에 묻힌다.
    package static let minimumLift: CGFloat = 60
    /// 집는 순간 말이 손가락에서 위로 올라오는 시간(초).
    package static let raiseDuration: Double = 0.12

    package static func lift(cell: CGFloat) -> CGFloat {
        max(minimumLift, cell * 1.3)
    }

    /// 손가락이 `finger` 에 있을 때 말을 그릴 상자.
    ///
    /// 가로는 말이 판 밖으로 안 나가게 묶는다(판 옆은 화면 끝이다). 세로는 **손가락을 판 안으로 묶은 뒤** 위로
    /// 띄운다 — 맨 윗줄에서는 말이 판 위로 넘치는데 그 자리는 상대 카드라 잘리지 않고 그 위에 얹힌다.
    /// 숫자가 아닌 좌표는 0 으로 읽는다(맥 `cursorCenter` 와 같다 — 판을 깨지 않는다).
    package static func pieceBox(finger: CGPoint, geometry: ChessPhoneBoardGeometry) -> CGRect {
        let side = geometry.side
        let size = geometry.cell * pieceScale
        func finite(_ value: CGFloat) -> CGFloat { value.isFinite ? value : 0 }
        // 판보다 큰 말은 없지만, 있다면 한계가 뒤집히지 않게 한가운데로 모은다.
        let low = min(size / 2, side / 2), high = max(side - size / 2, side / 2)
        let x = min(high, max(low, finite(finger.x)))
        let y = min(side, max(0, finite(finger.y))) - lift(cell: geometry.cell)
        return CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }

    /// 동작 줄이기면 말이 올라오는 움직임 없이 **처음부터 떠 있다**. 든 말이 손을 따라가는 것은 직접 조작이라 그대로다.
    package static func startsRaised(reduceMotion: Bool) -> Bool { reduceMotion }
}

// MARK: - 컨트롤러

/// 터치 → 스토어 어댑터. **판단은 여기 없다**(문턱은 `GamesChessBoardTouch`, 둘 수 있는가는 스토어).
///
/// 값을 `@State` 대신 클래스에 두는 까닭 둘: UIKit 인식기가 터치 콜백 안에서 **그 자리에서** 답을 들어야 상태를
/// 옮길 수 있고, 손 좌표(`handPoint`)를 든 말 뷰만 읽어야 손이 움직일 때마다 판이 다시 안 그려진다.
@MainActor
@Observable
package final class GamesChessBoardDragController {
    /// 한 번의 터치 입력이 닿는 곳. 뷰가 그릴 때마다 새 값을 넘긴다.
    package struct Port {
        /// nil 이면 끌기가 없는 판이다(탭만 받는다).
        package var store: ChessStore?
        package var geometry: ChessPhoneBoardGeometry
        package var onTap: (ChessSquare) -> Void

        package init(store: ChessStore?, geometry: ChessPhoneBoardGeometry,
                     onTap: @escaping (ChessSquare) -> Void) {
            self.store = store
            self.geometry = geometry
            self.onTap = onTap
        }
    }

    package private(set) var draggingFrom: ChessSquare?
    /// 손가락 자리(판 좌표). 끄는 중이 아니면 nil.
    package private(set) var handPoint: CGPoint?
    /// 손가락 밑 칸. 칸을 넘을 때만 바뀌므로 판은 이 값을 읽어도 칸마다 한 번만 다시 그린다.
    package private(set) var handSquare: ChessSquare?

    @ObservationIgnored package private(set) var touch = GamesChessBoardTouch()
    /// 지금 누름이 **시작될 때 본** 전제. 통지가 왔을 때 "그 변화가 이 누름 뒤에 일어났는가" 를 가르는 기준이다.
    @ObservationIgnored private var pressPremise: GamesChessDragPremise?

    package init() {}

    package func press(at point: CGPoint, port: Port) {
        let square = port.geometry.square(at: point)
        let store = port.store
        pressPremise = store.flatMap(GamesChessDragPremise.init(store:))
        var grab = ChessBoardPointer.Grab.none
        var vectors: [CGSize] = []
        if let square, let store {
            grab = GamesChessDragGate.grab(store.grab(at: square), hasPendingDrop: store.pendingDrop != nil)
            vectors = GamesChessDragGate.targetVectors(from: square, targets: store.targets(from: square),
                                                       geometry: port.geometry)
        }
        let isTarget = square.map { store?.selection?.targets.contains($0) == true } ?? false
        perform(touch.press(at: point, square: square, grab: grab, isSelectionTarget: isTarget, targets: vectors),
                port: port)
    }

    package func move(to point: CGPoint, port: Port) {
        perform(touch.move(to: point), port: port)
    }

    package func release(at point: CGPoint, port: Port) {
        perform(touch.release(at: point, square: port.geometry.square(at: point)), port: port)
    }

    /// 시스템이 터치를 거뒀다 · 판이 화면에서 내려갔다.
    package func abandon(store: ChessStore?) {
        settle(touch.abandon(), store: store)
    }

    /// 전제가 바뀌었다는 통지. ★ **그 누름이 본 판과 지금 판이 다를 때만** 거둔다 — 이 통지는 값이 바뀐 다음
    /// 그리기에 오므로, 그사이 시작한 누름은 이미 바뀐 판을 보고 눌렀다(맥 실창 프로브에서 실제로 났다).
    package func premiseDidChange(store: ChessStore?) {
        guard pressPremise != store.flatMap(GamesChessDragPremise.init(store:)) else { return }
        settle(touch.revoke(), store: store)
    }

    /// 스토어가 먼저 걸쇠를 내렸다. 그 끌기를 아직 붙들고 있을 때만 거둔다(같은 까닭).
    package func latchDidChange(store: ChessStore?) {
        guard let from = touch.draggingFrom, store?.dragOrigin != from else { return }
        settle(touch.revoke(), store: store)
    }

    private func settle(_ actions: [ChessBoardPointer.Action], store: ChessStore?) {
        guard actions.contains(.cancel) else { return }
        clearHand()
        store?.cancelDrag()
    }

    /// 해석기가 낸 행동을 스토어로 옮긴다.
    private func perform(_ actions: [ChessBoardPointer.Action], port: Port) {
        for action in actions {
            switch action {
            case .tap(let square):
                port.onTap(square)
            case .beginDrag(let square):
                // 거절되면 뒤따르는 행동은 버린다(문구는 스토어가 말했다).
                guard port.store?.beginDrag(from: square) == true else {
                    touch.dragRefused()
                    clearHand()
                    return
                }
                draggingFrom = square
            case .dragMoved(let point):
                if handPoint != point { handPoint = point }
                let square = port.geometry.square(at: point)
                if handSquare != square { handSquare = square }
            case .drop(let from, let target):
                clearHand()
                // ★ 동기 구간을 **이 자리에서** 끝낸다 — 놓은 말이 같은 틱에 도착 칸에 서야 번쩍임이 없다.
                //   서버 왕복만 뒤로 넘긴다(맥 `ChessPlayBoard.perform` 과 같다).
                if let store = port.store, let move = store.placeDrop(from: from, on: target) {
                    Task { await store.finishDrop(move) }
                }
            case .cancel:
                clearHand()
                port.store?.cancelDrag()
            }
        }
    }

    private func clearHand() {
        if draggingFrom != nil { draggingFrom = nil }
        if handPoint != nil { handPoint = nil }
        if handSquare != nil { handSquare = nil }
    }
}

// MARK: - 든 말 그림

/// 손 위에 뜬 말 한 장. 입력을 받지 않는 순수 그림이고, 캔버스와 **같은 색·같은 실루엣**이다.
///
/// 캔버스 **밖**에 따로 그리는 까닭: 캔버스는 판 사각형에서 잘린다. 맨 윗줄로 끌 때 말이 판 위로 넘쳐야 손에 안 가린다.
package struct GamesChessHeldPiece: View {
    let piece: ChessPiece
    let cell: CGFloat

    package init(piece: ChessPiece, cell: CGFloat) {
        self.piece = piece
        self.cell = cell
    }

    package var body: some View {
        Canvas { context, size in
            GamesChessBoardCanvas.draw(piece, in: CGRect(origin: .zero, size: size), cell: cell, into: &context)
        }
    }
}

/// 손을 따라다니는 층. `handPoint` 를 **이 뷰만** 읽는다 — 판 본문이 읽으면 손이 움직일 때마다 판이 다시 그려진다.
struct GamesChessHandLayer: View {
    let controller: GamesChessBoardDragController
    let piece: ChessPiece
    let geometry: ChessPhoneBoardGeometry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised = false

    var body: some View {
        if let finger = controller.handPoint {
            let box = GamesChessDragHand.pieceBox(finger: finger, geometry: geometry)
            let isUp = raised || GamesChessDragHand.startsRaised(reduceMotion: reduceMotion)
            GamesChessHeldPiece(piece: piece, cell: geometry.cell)
                .frame(width: box.width, height: box.height)
                // 집는 순간에만 손가락 자리·칸 크기에서 제 자리·제 크기로 올라온다. 애니메이션이 이 두 줄에만 걸리므로
                // 손을 따라가는 `position` 은 늦지 않는다.
                .scaleEffect(isUp ? 1 : 1 / GamesChessDragHand.pieceScale)
                .offset(y: isUp ? 0 : min(finger.y, geometry.side) - box.midY)
                .position(x: box.midX, y: box.midY)
                .allowsHitTesting(false)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeOut(duration: GamesChessDragHand.raiseDuration)) { raised = true }
                }
                .onDisappear { raised = false }
        }
    }
}

// MARK: - 데모 장면

#if DEBUG
/// 데모 라우트 `games/chess/match/<id>/drag/<출발>/<손가락>[/drop]` 이 세우는 끌기 한 장면(DEBUG 전용).
/// 스크린샷은 헤드리스라 손가락이 없다(작업 규칙 §0-1). 그래서 **인식기가 부르는 바로 그 문**(`press`·`move`·
/// `release`)을 장면이 대신 불러 코어 게이트를 하나도 우회하지 않는다.
package struct GamesChessDragPreview: Hashable, Sendable {
    package var from: ChessSquare
    package var finger: ChessSquare
    /// 참이면 놓기까지 간다(승격 시트 장면).
    package var drops: Bool

    package init(from: ChessSquare, finger: ChessSquare, drops: Bool) {
        self.from = from
        self.finger = finger
        self.drops = drops
    }

    /// 문턱을 넘겨 말을 집고, 손가락 칸까지 옮긴다.
    @MainActor
    func play(on controller: GamesChessBoardDragController, port: GamesChessBoardDragController.Port) {
        let start = port.geometry.center(of: from), end = port.geometry.center(of: finger)
        let dx = end.x - start.x, dy = end.y - start.y
        let length = max(1, (dx * dx + dy * dy).squareRoot())
        let step = ChessBoardPointer.dragThreshold + 1
        controller.press(at: start, port: port)
        controller.move(to: CGPoint(x: start.x + dx / length * step, y: start.y + dy / length * step), port: port)
        controller.move(to: end, port: port)
        if drops { controller.release(at: end, port: port) }
    }
}

extension EnvironmentValues {
    @Entry var gamesChessDragPreview: GamesChessDragPreview? = nil
}
#endif
