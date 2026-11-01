import AppKit
@testable import CheckCore
import CheckMobileShared
import Foundation
import SwiftUI
import Testing
@testable import CheckMobileKit

// 폰 1.0.16 체스 **끌어 두기**. 터치 면(`GamesChessBoardTouchSurface`)은 UIKit 이라 맥 스위트가 못 본다 —
// 그래서 판단을 전부 그 앞의 순수 값·컨트롤러에 뒀고, 여기서 **인식기가 부르는 바로 그 문**
// (`press`·`move`·`release`)을 진짜 `ChessStore` 에 대고 부른다. 재는 것:
//
//  ① 칸 왕복 · 손가락 밑 칸(흑 판 포함)      ② 손 궤적 — 말이 손에 안 가리고 판 밖으로 안 나간다
//  ③ 문턱 — 경계값, 탭이 살아 있는가          ④ 스크롤 양보 — 내 말에서 시작한 손만 집는다
//  ⑤ 놓기 — 코어 경로·승격·판 밖·새 끌기 거절  ⑥ 거두기 — 전제가 바뀌면 수가 안 나간다
//  ⑦ 그림 — 출발 칸이 비고 놓은 말이 도착 칸에 선다  ⑧ 배선 — 두는 판에만 끌기가 있다
//
// 합성 터치로 시뮬레이터를 돌리지 않는 까닭: 작업 규칙 §0-1. UIKit 인식기와 스크롤의 실제 경합은 이 파일이 **못 잰다**.

private func sq(_ notation: String) -> ChessSquare { ChessSquare(notation)! }

private let peer = ChessUser(
    id: "00000000-0000-0000-0000-0000000000cc", displayName: "민수", avatarURL: nil,
    characterID: "fox", isWorking: true, isCapable: true, inMatch: true, center: "seoul")

private let standardFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
/// 흑 차례 — 흑으로 두는 사람의 판(뒤집힌다).
private let blackToMoveFEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
private let promoFEN = "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"

private let side: CGFloat = 360
private func board(_ orientation: ChessColor = .white) -> ChessPhoneBoardGeometry {
    ChessPhoneBoardGeometry(side: side, orientation: orientation)
}

private func matchState(id: String = "match-drag", myColor: ChessColor = .white, turn: ChessColor = .white,
                        fen: String = standardFEN, plyCount: Int = 10, legalMoves: [ChessMove],
                        isFinished: Bool = false) -> ChessMatchState {
    ChessMatchState(
        id: id, stake: 5, myColor: myColor, opponent: peer, fen: fen,
        position: ChessPosition(fen: fen), plyCount: plyCount,
        turn: isFinished ? nil : turn, lastMove: nil, moves: [], clock: .initial,
        isInCheck: false, legalMoves: legalMoves, isFinished: isFinished, outcome: nil,
        endReason: nil, rubyDelta: nil, drawOfferBy: nil,
        drawOfferedByMe: false, whiteGraceMs: nil, blackGraceMs: nil)
}

/// 표준 시작 국면에서 백이 둘 수 있는 수 몇 개(서버가 준 `legal_moves` 자리).
private let openingMoves = [
    ChessMove(from: sq("e2"), to: sq("e3")), ChessMove(from: sq("e2"), to: sq("e4")),
    ChessMove(from: sq("d2"), to: sq("d3")), ChessMove(from: sq("g1"), to: sq("f3"))
]

@MainActor
private func store(_ match: ChessMatchState) -> ChessStore {
    let store = ChessStore()
    store.phase = .playing
    store.match = match
    return store
}

/// 터치 한 번을 인식기처럼 넣는 작은 받침.
@MainActor
private final class Rig {
    let store: ChessStore
    let controller = GamesChessBoardDragController()
    let geometry: ChessPhoneBoardGeometry
    private(set) var taps: [ChessSquare] = []

    init(_ store: ChessStore, orientation: ChessColor = .white) {
        self.store = store
        geometry = board(orientation)
    }

    /// 화면이 `onTapSquare` 에 넘기는 것과 같은 길(`store.tap`)을 **동기로** 기록만 한다 — 탭 경로는 `tapThrough` 가 잰다.
    var port: GamesChessBoardDragController.Port {
        GamesChessBoardDragController.Port(store: store, geometry: geometry,
                                           onTap: { [weak self] in self?.taps.append($0) })
    }

    func center(_ notation: String) -> CGPoint { geometry.center(of: sq(notation)) }
    func press(_ notation: String) { controller.press(at: center(notation), port: port) }
    func move(_ point: CGPoint) { controller.move(to: point, port: port) }
    func move(_ notation: String) { move(center(notation)) }
    func release(_ point: CGPoint) { controller.release(at: point, port: port) }
    func release(_ notation: String) { release(center(notation)) }

    /// 말을 집어 들어 그 칸 위까지 끈다(문턱을 넘는 작은 한 걸음 + 나머지).
    func pickUp(_ from: String, over to: String) {
        press(from)
        let start = center(from), end = center(to)
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        move(CGPoint(x: start.x + dx / length * 5, y: start.y + dy / length * 5))
        move(to)
    }
}

// MARK: - ① 칸 왕복

@MainActor
@Suite("폰 체스 끌어 두기 — 값", .serialized)
struct GamesChessDragTests {
    @Test("★ 칸 왕복 — 64칸 전부, 양쪽 판에서 가운데 점이 그 칸으로 돌아오고 칸 안 네 귀퉁이도 그 칸이다",
          arguments: [ChessColor.white, .black])
    func everySquareRoundTrips(orientation: ChessColor) throws {
        let g = board(orientation)
        var seen = Set<ChessSquare>()
        for index in 0..<64 {
            let square = try #require(ChessSquare(index: index))
            #expect(g.square(at: g.center(of: square)) == square, "\(square.notation) 왕복이 틀렸다")
            let box = g.rect(of: square).insetBy(dx: 0.5, dy: 0.5)
            for corner in [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                           CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)] {
                #expect(g.square(at: corner) == square, "\(square.notation) 귀퉁이가 이웃 칸으로 읽힌다")
            }
            seen.insert(square)
        }
        #expect(seen.count == 64)
    }

    @Test("판 밖 점은 어느 칸도 아니다 — 끝 값 포함")
    func outsideIsNoSquare() {
        let g = board()
        for point in [CGPoint(x: -1, y: 10), CGPoint(x: 10, y: -1), CGPoint(x: side, y: 10), CGPoint(x: 10, y: side)] {
            #expect(g.square(at: point) == nil, "\(point) 가 칸으로 읽혔다")
        }
    }

    // MARK: ② 손 궤적

    @Test("★ 손 궤적 — 판 안 어디서든 말이 손가락 **위**에 있고 말 밑이 손가락에서 떨어져 있다")
    func thePieceStaysAboveTheFinger() {
        let g = board()
        for x in stride(from: CGFloat(0), through: side, by: 15) {
            for y in stride(from: CGFloat(0), through: side, by: 15) {
                let box = GamesChessDragHand.pieceBox(finger: CGPoint(x: x, y: y), geometry: g)
                // 손가락 끝(접점 위 약 20pt)에 말이 묻히지 않는다.
                #expect(box.maxY <= y - 20, "(\(x),\(y)) 말 밑 \(box.maxY) 가 손가락에 묻힌다")
                #expect(box.minX >= 0 && box.maxX <= side, "(\(x),\(y)) 말이 판 옆으로 나갔다")
            }
        }
    }

    @Test("손 궤적 — 가운데에서는 손을 1:1 로 따라가고, 변에서만 묶인다")
    func thePieceFollowsTheFingerExactlyInTheMiddle() {
        let g = board()
        let lift = GamesChessDragHand.lift(cell: g.cell)
        let a = GamesChessDragHand.pieceBox(finger: CGPoint(x: 150, y: 200), geometry: g)
        let b = GamesChessDragHand.pieceBox(finger: CGPoint(x: 163, y: 171), geometry: g)
        #expect(a.midX == 150 && a.midY == 200 - lift, "말 중심이 손가락 바로 위가 아니다")
        #expect(b.midX - a.midX == 13 && b.midY - a.midY == -29, "말이 손보다 늦거나 빠르다")
        #expect(a.width == g.cell * GamesChessDragHand.pieceScale, "든 말의 크기가 약속과 다르다")
        #expect(a.width > g.cell, "든 말이 판의 말보다 작다")
    }

    @Test("손 궤적 — 손이 판 밖으로 나가도 말은 마지막 변에 머문다 · 숫자가 아닌 좌표는 판을 안 깬다")
    func theFingerOutsideTheBoardIsClamped() {
        let g = board()
        let lift = GamesChessDragHand.lift(cell: g.cell)
        let up = GamesChessDragHand.pieceBox(finger: CGPoint(x: 180, y: -500), geometry: g)
        #expect(up.midY == -lift, "판 위로 나간 손을 말이 끝없이 따라간다")
        let down = GamesChessDragHand.pieceBox(finger: CGPoint(x: 180, y: 9000), geometry: g)
        #expect(down.midY == side - lift, "판 아래로 나간 손을 말이 끝없이 따라간다")
        let left = GamesChessDragHand.pieceBox(finger: CGPoint(x: -500, y: 200), geometry: g)
        #expect(left.minX == 0)
        let broken = GamesChessDragHand.pieceBox(finger: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), geometry: g)
        #expect(broken.minX.isFinite && broken.minY.isFinite)
    }

    @Test("작은 판에서도 손가락 위 거리가 바닥값 밑으로 안 내려간다 — 손가락은 판을 따라 작아지지 않는다")
    func theLiftHasAFloor() {
        #expect(GamesChessDragHand.lift(cell: 20) == GamesChessDragHand.minimumLift)
        #expect(GamesChessDragHand.lift(cell: 90) > GamesChessDragHand.minimumLift)
    }

    @Test("동작 줄이기 — 말이 올라오는 움직임 없이 처음부터 떠 있다")
    func reduceMotionSkipsTheRaise() throws {
        #expect(GamesChessDragHand.startsRaised(reduceMotion: true))
        #expect(!GamesChessDragHand.startsRaised(reduceMotion: false))
        let code = stripComments(try Self.source("Sources/CheckMobileKit/Games/GamesChessBoardDrag.swift"))
        let layer = try #require(Self.between(code, from: "struct GamesChessHandLayer", to: "#if DEBUG"))
        #expect(layer.contains("@Environment(\\.accessibilityReduceMotion)"), "동작 줄이기 설정을 안 읽는다")
        #expect(layer.contains("guard !reduceMotion else { return }"), "동작 줄이기에서도 애니메이션을 건다")
        #expect(layer.components(separatedBy: "withAnimation").count == 2, "애니메이션이 올라오는 한 자리 밖으로 번졌다")
    }

    // MARK: ③ 문턱

    @Test("★ 문턱 — 4pt 밑은 아무 일 없고 정확히 4pt 에서 집는다")
    func thresholdBoundary() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        rig.press("e2")
        let start = rig.center("e2")
        rig.move(CGPoint(x: start.x, y: start.y - 3.99))
        #expect(rig.controller.draggingFrom == nil, "문턱 밑에서 집었다")
        #expect(rig.store.dragOrigin == nil)
        rig.move(CGPoint(x: start.x, y: start.y - 4))
        #expect(rig.controller.draggingFrom == sq("e2"), "정확히 4pt 에서 안 집혔다")
        #expect(rig.store.dragOrigin == sq("e2"), "걸쇠가 안 걸렸다")
        #expect(rig.store.selection?.from == sq("e2"), "집은 말이 곧 고른 말이다")
        #expect(rig.controller.handPoint == CGPoint(x: start.x, y: start.y - 4))
        #expect(ChessBoardPointer.dragThreshold == 4, "맥과 같은 문턱이다")
    }

    @Test("★ 탭 2단이 산다 — 문턱 밑으로 떼면 탭이고 끌기가 시작되지 않는다")
    func aTapIsStillATap() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        rig.press("e2")
        rig.release(CGPoint(x: rig.center("e2").x + 2, y: rig.center("e2").y))
        #expect(rig.taps == [sq("e2")], "제자리 뗌이 탭이 아니다")
        #expect(rig.store.dragOrigin == nil, "탭인데 걸쇠가 걸렸다")
        #expect(rig.controller.touch.stage == .idle)
    }

    @Test("★ 탭 2단을 진짜 스토어로 — 내 말을 고르고 도착 칸을 누르면 그 수가 코어로 간다")
    func tapThrough() async throws {
        let chess = ChessStore()
        chess.startAIMatch(humanColor: .white)
        let controller = GamesChessBoardDragController()
        let port = GamesChessBoardDragController.Port(
            store: chess, geometry: board(), onTap: { square in Task { await chess.tap(square) } })
        func tap(_ notation: String) {
            let point = board().center(of: sq(notation))
            controller.press(at: point, port: port)
            controller.release(at: point, port: port)
        }
        tap("e2")
        #expect(await baseWaitUntil { chess.selection?.from == sq("e2") }, "첫 탭이 말을 못 골랐다")
        tap("e4")
        #expect(await baseWaitUntil { chess.match?.plyCount == 1 }, "둘째 탭이 수를 못 뒀다")
        chess.reset()
    }

    @Test("도착 칸을 누른 손은 문턱을 넘어도 끌기가 아니다 — 슬롭 안에서 떼면 그 칸의 탭이다")
    func pressingATargetIsATap() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        rig.press("e2")
        rig.release("e2")
        #expect(rig.taps == [sq("e2")])
        rig.store.selection = ChessSelection(from: sq("e2"), targets: [sq("e3"), sq("e4")])
        rig.press("e4")
        let start = rig.center("e4")
        rig.move(CGPoint(x: start.x + 6, y: start.y))
        #expect(rig.controller.draggingFrom == nil, "도착 칸을 눌렀는데 끌었다")
        rig.release(CGPoint(x: start.x + 6, y: start.y))
        #expect(rig.taps == [sq("e2"), sq("e4")], "슬롭 안 손떨림에 도착 탭이 사라졌다")
    }

    @Test("칸 경계를 넘은 손떨림도 슬롭 안이면 누른 칸의 탭이다")
    func aShakyTapAcrossTheBorderKeepsThePressedSquare() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        // e4 는 빈 칸. 오른쪽 변 1pt 안쪽을 누르고 6pt 움직여 f4 에서 뗀다.
        let box = rig.geometry.rect(of: sq("e4"))
        let start = CGPoint(x: box.maxX - 1, y: box.midY)
        rig.controller.press(at: start, port: rig.port)
        let end = CGPoint(x: start.x + 6, y: start.y)
        #expect(rig.geometry.square(at: end) == sq("f4"), "전제: 뗀 곳은 옆 칸이다")
        rig.controller.move(to: end, port: rig.port)
        rig.controller.release(at: end, port: rig.port)
        #expect(rig.taps == [sq("e4")])
    }

    // MARK: ③-2 집힌 뒤의 손떨림

    @Test("★ 잘못된 수 금지 — 폰 칸 위쪽 끝을 누른 손이 5pt 떨려 옆 칸에서 떼도 수가 안 나간다(탭이다)")
    func aWobbleAcrossTheBorderSendsNoMove() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        let box = rig.geometry.rect(of: sq("e2"))
        let start = CGPoint(x: box.midX, y: box.minY + 1)
        let end = CGPoint(x: start.x, y: start.y - 5)
        #expect(rig.geometry.square(at: end) == sq("e3"), "전제: 뗀 곳은 갈 수 있는 옆 칸이다")
        rig.controller.press(at: start, port: rig.port)
        rig.controller.move(to: end, port: rig.port)
        #expect(rig.controller.draggingFrom == sq("e2"), "전제: 문턱을 넘어 집혔다")
        rig.controller.release(at: end, port: rig.port)
        #expect(rig.store.pendingDrop == nil, "탭하다 흔들린 손이 수를 보냈다")
        #expect(rig.store.dragOrigin == nil, "걸쇠가 남았다")
        #expect(rig.controller.draggingFrom == nil && rig.controller.handPoint == nil)
        #expect(rig.store.selection?.from == sq("e2"), "첫 탭이면 말이 골라져 있어야 한다")
        #expect(rig.taps.isEmpty, "고르기는 집을 때 이미 끝났다 — 탭을 또 내면 도로 해제된다")
    }

    @Test("손떨림으로 못 가는 옆 칸에서 떼도 거절 문구가 안 뜬다 — 탭이지 놓기가 아니다")
    func aWobbleOntoAnIllegalSquareIsNotRefused() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        let box = rig.geometry.rect(of: sq("e2"))
        let start = CGPoint(x: box.maxX - 1, y: box.midY)
        let end = CGPoint(x: start.x + 5, y: start.y)
        #expect(rig.geometry.square(at: end) == sq("f2"), "전제: 뗀 곳은 옆 칸이다")
        rig.controller.press(at: start, port: rig.port)
        rig.controller.move(to: end, port: rig.port)
        rig.controller.release(at: end, port: rig.port)
        #expect(rig.store.notice == nil, "탭하다 흔들린 손이 거절 문구를 받았다")
        #expect(rig.store.pendingDrop == nil)
    }

    @Test("★ 탭 2단 — 고른 말을 다시 누른 손이 5pt 떨려도 해제된다")
    func aWobblyRetapStillDeselects() async {
        let chess = ChessStore()
        chess.startAIMatch(humanColor: .white)
        let controller = GamesChessBoardDragController()
        let port = GamesChessBoardDragController.Port(
            store: chess, geometry: board(), onTap: { square in Task { await chess.tap(square) } })
        let start = board().center(of: sq("e2"))
        let end = CGPoint(x: start.x + 1, y: start.y - 5)
        controller.press(at: start, port: port)
        controller.release(at: start, port: port)
        #expect(await baseWaitUntil { chess.selection?.from == sq("e2") }, "전제: 첫 탭이 말을 골랐다")
        controller.press(at: start, port: port)
        controller.move(to: end, port: port)
        controller.release(at: end, port: port)
        #expect(await baseWaitUntil { chess.selection == nil }, "떨린 재탭이 고르기를 못 풀었다")
        #expect(chess.dragOrigin == nil)
        #expect(chess.match?.plyCount == 0, "재탭이 수를 뒀다")
        chess.reset()
    }

    @Test("★ 멀리 갔다 돌아온 끌기는 탭이 아니다 — 출발 칸에 놓으면 고르기가 남는다")
    func aRealDragBackHomeKeepsTheSelection() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        rig.press("e2")
        rig.release("e2")
        rig.store.selection = ChessSelection(from: sq("e2"), targets: [sq("e3"), sq("e4")])
        rig.pickUp("e2", over: "e4")
        rig.move("e2")
        rig.release("e2")
        #expect(rig.taps == [sq("e2")], "끌어 돌아온 손이 탭까지 냈다 — 고르기가 풀린다")
        #expect(rig.store.selection?.from == sq("e2"))
    }

    @Test("★ 말은 슬롭을 넘어야 뜬다 — 떨린 탭에 튀어 오르지 않고, 진짜 끌기는 슬롭부터 놓칠 때까지 떠 있다")
    func thePieceFloatsOnlyPastTheSlop() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        let start = rig.center("e2")
        rig.press("e2")
        rig.move(CGPoint(x: start.x, y: start.y - 5))
        #expect(rig.controller.draggingFrom == sq("e2"), "전제: 문턱을 넘어 집혔다")
        #expect(rig.store.selection?.from == sq("e2"), "전제: 도착 점은 이미 떠 있다")
        #expect(rig.controller.floatingFrom == nil, "떨린 탭에 말이 떴다")
        #expect(GamesChessBoardLift.resolve(pending: nil, draggingFrom: rig.controller.floatingFrom,
                                            latch: rig.store.dragOrigin, position: rig.store.match?.position) == nil,
                "슬롭 안에서 출발 칸이 비었다")
        rig.move(CGPoint(x: start.x, y: start.y - 10))
        #expect(rig.controller.floatingFrom == sq("e2"), "슬롭을 넘었는데 말이 안 떴다")
        #expect(GamesChessBoardLift.resolve(pending: nil, draggingFrom: rig.controller.floatingFrom,
                                            latch: rig.store.dragOrigin, position: rig.store.match?.position)?
            .place == .hand)
        // 슬롭 안으로 돌아와도 내리지 않는다 — 깜빡인다.
        rig.move(CGPoint(x: start.x, y: start.y - 2))
        #expect(rig.controller.floatingFrom == sq("e2"))
        rig.controller.abandon(store: rig.store)
        #expect(rig.controller.floatingFrom == nil, "거둔 말이 떠 있다")
    }

    @Test("★ 튕긴 손 — 움직임 없이 뗌만 온 손도 문을 지난다: 슬롭 밖이면 끌기, 슬롭 안이면 탭, 뒤로 튕기면 아무 일 없음")
    func aFlickPassesTheGateOnRelease() {
        let far = Rig(store(matchState(legalMoves: openingMoves)))
        far.press("e2")
        far.release("e4")
        #expect(far.store.pendingDrop?.to == sq("e4"), "멀리 튕긴 끌기가 안 놓였다")
        #expect(far.taps.isEmpty)

        let near = Rig(store(matchState(legalMoves: openingMoves)))
        let box = near.geometry.rect(of: sq("e2"))
        let start = CGPoint(x: box.midX, y: box.minY + 1)
        near.controller.press(at: start, port: near.port)
        near.controller.release(at: CGPoint(x: start.x, y: start.y - 5), port: near.port)
        #expect(near.store.pendingDrop == nil, "슬롭 안에서 튕긴 손이 수를 보냈다")
        #expect(near.taps == [sq("e2")], "슬롭 안 뗌은 누른 칸의 탭이다")

        let back = Rig(store(matchState(legalMoves: openingMoves)))
        back.press("e2")
        back.release(CGPoint(x: back.center("e2").x, y: back.center("e2").y + 30))
        #expect(back.store.pendingDrop == nil && back.store.dragOrigin == nil, "뒤로 튕긴 손이 말을 집었다")
        #expect(back.store.notice == nil)
        #expect(back.taps.isEmpty, "스크롤로 간 손이 탭을 냈다")
    }

    // MARK: ④ 스크롤 양보

    @Test("★ 스크롤 양보 — 빈 칸·상대 말에서 시작한 손은 어느 방향이든 슬롭에서 스크롤로 넘어간다",
          arguments: ["e4", "e7"], [CGSize(width: 0, height: 12), CGSize(width: 0, height: -12),
                                    CGSize(width: 12, height: 0), CGSize(width: -12, height: 0)])
    func notMyPieceYields(start: String, motion: CGSize) {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        rig.press(start)
        let origin = rig.center(start)
        rig.move(CGPoint(x: origin.x + motion.width / 4, y: origin.y + motion.height / 4))
        #expect(rig.controller.touch.stage == .undecided, "문턱 밑에서 판결했다")
        rig.move(CGPoint(x: origin.x + motion.width * 0.5, y: origin.y + motion.height * 0.5))
        #expect(rig.controller.touch.stage == .yielded, "문턱을 넘었는데 판결이 없다")
        #expect(!rig.controller.touch.handsOffToScroll, "슬롭 안에서 벌써 넘겼다 — 칸 가장자리 탭이 죽는다")
        rig.move(CGPoint(x: origin.x + motion.width, y: origin.y + motion.height))
        #expect(rig.controller.touch.handsOffToScroll, "슬롭을 넘겼는데 스크롤이 못 받는다")
        #expect(rig.store.dragOrigin == nil, "내 말이 아닌데 걸쇠가 걸렸다")
        #expect(rig.controller.draggingFrom == nil)
        rig.release(CGPoint(x: origin.x + motion.width, y: origin.y + motion.height))
        #expect(rig.taps.isEmpty, "스크롤로 넘어간 손이 탭까지 냈다")
    }

    @Test("★ 내 말이어도 지금 못 끌면 스크롤이다 — 상대 차례 · 왕복 중 · 갈 곳 없음")
    func stuckPieceYields() {
        let theirTurn = Rig(store(matchState(turn: .black, legalMoves: [])))
        theirTurn.pickUp("e2", over: "e4")
        #expect(theirTurn.controller.draggingFrom == nil, "상대 차례에 집혔다")
        #expect(theirTurn.controller.touch.handsOffToScroll)

        let busy = Rig(store(matchState(legalMoves: openingMoves)))
        busy.store.isBusy = true
        busy.pickUp("e2", over: "e4")
        #expect(busy.controller.draggingFrom == nil, "왕복 중에 집혔다")

        let blocked = Rig(store(matchState(legalMoves: openingMoves)))
        blocked.pickUp("a1", over: "a3")
        #expect(blocked.controller.draggingFrom == nil, "갈 곳 없는 룩이 집혔다")
    }

    @Test("못 끄는 내 말을 제자리에서 떼면 탭이 나간다 — 거절 문구는 그 길로 난다")
    func stuckPieceTapStillSpeaks() {
        let rig = Rig(store(matchState(turn: .black, legalMoves: [])))
        rig.press("e2")
        rig.release("e2")
        #expect(rig.taps == [sq("e2")])
    }

    @Test("★ 내 말에서 시작한 손은 방향으로 갈린다 — 갈 곳 쪽이면 집고, 폰을 뒤로 쓸면 스크롤이다")
    func directionSplitsMyPiece() {
        // 위로(폰의 앞) — 이게 "세로면 스크롤" 로는 못 가르는 까닭이다.
        let up = Rig(store(matchState(legalMoves: openingMoves)))
        up.press("e2")
        up.move(CGPoint(x: up.center("e2").x, y: up.center("e2").y - 5))
        #expect(up.controller.draggingFrom == sq("e2"), "폰을 앞으로 끄는 손이 안 집혔다")

        // 옆으로 비껴도 120도 안이면 집는다.
        let side = Rig(store(matchState(legalMoves: openingMoves)))
        side.press("e2")
        side.move(CGPoint(x: side.center("e2").x + 5, y: side.center("e2").y))
        #expect(side.controller.draggingFrom == sq("e2"), "손떨림으로 옆을 향한 손이 안 집혔다")

        // 아래로(폰의 뒤) — 어디로도 못 가는 쪽이다.
        let down = Rig(store(matchState(legalMoves: openingMoves)))
        down.press("e2")
        down.move(CGPoint(x: down.center("e2").x, y: down.center("e2").y + 5))
        #expect(down.controller.draggingFrom == nil, "폰을 뒤로 쓴 손이 집혔다 — 스크롤이 막힌다")
        #expect(down.controller.touch.stage == .yielded)
        down.move(CGPoint(x: down.center("e2").x, y: down.center("e2").y + 11))
        #expect(down.controller.touch.handsOffToScroll)
    }

    @Test("★ 방향 판결은 흑 판에서 뒤집힌다 — 흑 폰의 앞도 화면 위다(화면 벡터로 재지 않으면 흑만 틀린다)")
    func directionUsesScreenVectorsOnTheBlackBoard() {
        let moves = [ChessMove(from: sq("e7"), to: sq("e6")), ChessMove(from: sq("e7"), to: sq("e5"))]
        func match() -> ChessMatchState {
            matchState(myColor: .black, turn: .black, fen: blackToMoveFEN, legalMoves: moves)
        }
        let up = Rig(store(match()), orientation: .black)
        up.press("e7")
        up.move(CGPoint(x: up.center("e7").x, y: up.center("e7").y - 5))
        #expect(up.controller.draggingFrom == sq("e7"), "흑 폰을 앞으로 끄는 손이 안 집혔다")

        let down = Rig(store(match()), orientation: .black)
        down.press("e7")
        down.move(CGPoint(x: down.center("e7").x, y: down.center("e7").y + 5))
        #expect(down.controller.draggingFrom == nil, "흑 폰을 뒤로 쓴 손이 집혔다")
    }

    @Test("방향 판결 표 — 갈 곳이 사방이면 어디로든 집고, 120도 경계를 지킨다")
    func verdictTable() {
        let up = CGSize(width: 0, height: -45)
        let right = CGSize(width: 45, height: 0)
        typealias Gate = GamesChessDragGate
        #expect(Gate.verdict(grab: .movable, motion: CGSize(width: 0, height: 5), targets: [up, right]) == .pickUp,
                "오른쪽 갈 곳과 90도면 아직 집는다")
        #expect(Gate.verdict(grab: .movable, motion: CGSize(width: 0, height: 5), targets: [up]) == .yieldToScroll)
        // 120도 안쪽(110도)은 집고, 그 너머(130도)는 양보한다.
        let at130 = CGSize(width: 5 * sin(130 * Double.pi / 180), height: -5 * cos(130 * Double.pi / 180))
        #expect(Gate.verdict(grab: .movable, motion: at130, targets: [up]) == .yieldToScroll)
        let at110 = CGSize(width: 5 * sin(110 * Double.pi / 180), height: -5 * cos(110 * Double.pi / 180))
        #expect(Gate.verdict(grab: .movable, motion: at110, targets: [up]) == .pickUp)
        // 끌 수 없으면 방향과 무관하다.
        #expect(Gate.verdict(grab: .stuck, motion: up, targets: [up]) == .yieldToScroll)
        #expect(Gate.verdict(grab: .none, motion: up, targets: [up]) == .yieldToScroll)
    }

    // MARK: ⑤ 놓기

    @Test("★ 놓으면 코어 경로로 둔다 — 로봇 판에서 끌어 놓은 수가 판에 들어간다")
    func dropGoesThroughTheCore() async throws {
        let chess = ChessStore()
        chess.startAIMatch(humanColor: .white)
        let rig = Rig(chess)
        rig.pickUp("e2", over: "e4")
        #expect(rig.controller.handSquare == sq("e4"))
        #expect(GamesChessBoardLift.dropTarget(
            lift: GamesChessBoardLift.resolve(pending: chess.pendingDrop, draggingFrom: rig.controller.draggingFrom,
                                              latch: chess.dragOrigin, position: chess.match?.position),
            handSquare: rig.controller.handSquare, targets: chess.selection?.targets ?? []) == sq("e4"),
                "손가락 밑 도착 칸이 표시되지 않는다")
        rig.release("e4")
        #expect(rig.controller.draggingFrom == nil && rig.controller.handPoint == nil, "놓았는데 손에 말이 남았다")
        #expect(chess.pendingDrop?.to == sq("e4") && chess.pendingDrop?.from == sq("e2"),
                "★ 놓은 그 틱에 말이 도착 칸에 서야 한다(번쩍임)")
        #expect(await baseWaitUntil { chess.match?.plyCount == 1 }, "놓은 수가 판에 안 들어갔다")
        #expect(chess.match?.position?[sq("e4")]?.kind == .pawn)
        #expect(rig.taps.isEmpty, "끌기가 탭까지 냈다")
        chess.reset()
    }

    @Test("★ 놓을 칸은 말 밑이 아니라 손가락 밑이다 — 맨 아랫줄에 놓을 수 있어야 한다")
    func theDropSquareIsUnderTheFinger() {
        let moves = [ChessMove(from: sq("g1"), to: sq("f3")), ChessMove(from: sq("f3"), to: sq("g1"))]
        let fen = "rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 1"
        let rig = Rig(store(matchState(fen: fen, legalMoves: moves)))
        rig.pickUp("f3", over: "g1")
        #expect(rig.controller.handSquare == sq("g1"))
        let box = GamesChessDragHand.pieceBox(finger: rig.center("g1"), geometry: rig.geometry)
        #expect(rig.geometry.square(at: CGPoint(x: box.midX, y: box.midY)) != sq("g1"), "전제: 말은 손 위에 떠 있다")
        rig.release("g1")
        #expect(rig.store.pendingDrop?.to == sq("g1"), "맨 아랫줄에 놓지 못했다")
    }

    @Test("★ 승격 — 끌어 놓으면 시트 경로로 가고, 폰은 고르는 동안 도착 칸에 머문다")
    func promotionKeepsTheSheetPath() throws {
        let four = ChessPieceKind.promotionChoices.map { ChessMove(from: sq("a7"), to: sq("a8"), promotion: $0) }
        let rig = Rig(store(matchState(fen: promoFEN, legalMoves: four)))
        rig.pickUp("a7", over: "a8")
        rig.release("a8")
        let prompt = try #require(rig.store.promotion, "승격을 묻지 않는다")
        #expect(prompt.from == sq("a7") && prompt.to == sq("a8"))
        let lift = GamesChessBoardLift.resolve(pending: rig.store.pendingDrop, draggingFrom: nil, latch: nil,
                                               position: rig.store.match?.position)
        #expect(lift?.place == .square(sq("a8")), "고르는 동안 폰이 도착 칸에 없다")
        #expect(lift?.piece.kind == .pawn)
        // 대국 화면이 시트를 세우는 값이 그대로 선다.
        let chrome = GamesChessMatchChrome(match: try #require(rig.store.match), promotion: rig.store.promotion,
                                           notice: nil, isBusy: false, isRobotMatch: false,
                                           initialMs: ChessClock.initialMs)
        #expect(chrome.showsPromotionSheet)
        rig.store.cancelPromotion()
        #expect(rig.store.pendingDrop == nil, "시트를 닫았는데 폰이 도착 칸에 남았다")
    }

    @Test("★ 판 밖에 놓으면 제자리 — 수도 문구도 없고 고르기는 남는다")
    func droppingOutsideReturnsThePiece() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        rig.pickUp("e2", over: "e4")
        rig.move(CGPoint(x: 40, y: side + 80))
        #expect(rig.controller.handSquare == nil)
        rig.release(CGPoint(x: 40, y: side + 80))
        #expect(rig.store.pendingDrop == nil, "판 밖에 놓았는데 수가 섰다")
        #expect(rig.store.promotion == nil)
        #expect(rig.store.dragOrigin == nil, "걸쇠가 남았다")
        #expect(rig.store.notice == nil, "판 밖 놓기에 거절 문구가 떴다")
        #expect(rig.store.selection?.from == sq("e2"), "고르기까지 사라졌다")
        #expect(GamesChessBoardLift.resolve(pending: nil, draggingFrom: rig.controller.draggingFrom,
                                            latch: rig.store.dragOrigin, position: rig.store.match?.position) == nil,
                "말이 공중에 남았다")
    }

    @Test("출발 칸에 도로 놓으면 수가 없다 · 못 가는 칸에 놓으면 코어의 거절 문구가 난다")
    func droppingOnSourceAndIllegalSquare() {
        let back = Rig(store(matchState(legalMoves: openingMoves)))
        back.pickUp("e2", over: "e4")
        back.move("e2")
        back.release("e2")
        #expect(back.store.pendingDrop == nil)
        #expect(back.store.notice == nil)
        #expect(back.store.selection?.from == sq("e2"))

        let illegal = Rig(store(matchState(legalMoves: openingMoves)))
        illegal.pickUp("e2", over: "e4")
        illegal.move("h5")
        illegal.release("h5")
        #expect(illegal.store.pendingDrop == nil)
        #expect(illegal.store.notice != nil, "못 가는 칸에 놓았는데 아무 말이 없다")
    }

    @Test("★ 놓은 말이 답을 기다리는 동안 새 끌기를 거절한다 — 왕복 전의 틈에도")
    func noNewDragWhileWaiting() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        rig.pickUp("e2", over: "e4")
        rig.release("e4")
        // 여기는 `finishDrop` Task 가 돌기 **전**이다 — `isBusy` 는 아직 거짓이다.
        #expect(rig.store.pendingDrop != nil && !rig.store.isBusy, "전제: 왕복 전의 틈이다")
        #expect(rig.store.grab(at: sq("d2")) == .movable, "기준선: 스토어만 보면 집을 수 있다 — 이 문이 필요한 까닭")
        rig.pickUp("d2", over: "d3")
        #expect(rig.controller.draggingFrom == nil, "답을 기다리는데 다른 말이 집혔다")
        #expect(rig.store.pendingDrop?.to == sq("e4"), "앞서 놓은 수의 꼬리표가 지워졌다")
    }

    // MARK: ⑥ 거두기

    enum Change: String, CaseIterable, CustomTestStringConvertible {
        case theirResign, otherMatch, plyAdvanced, busy, hidden, matchGone
        var testDescription: String { rawValue }
    }

    @Test("★ 거두기 — 전제가 바뀌면 끌던 말을 내려놓고, 그 뒤 손을 떼도 수가 안 나간다", arguments: Change.allCases)
    func aChangedPremiseRevokes(change: Change) {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        if change == .hidden { rig.store.isWindowVisible = true }
        rig.pickUp("e2", over: "e4")
        #expect(rig.controller.draggingFrom == sq("e2"), "전제: 끄는 중이다")
        switch change {
        case .theirResign:
            rig.store.match = matchState(legalMoves: openingMoves, isFinished: true)
        case .otherMatch:
            rig.store.match = matchState(id: "match-other", legalMoves: openingMoves)
        case .plyAdvanced:
            rig.store.match = matchState(plyCount: 11, legalMoves: openingMoves)
        case .busy:
            rig.store.isBusy = true
        case .hidden:
            rig.store.isWindowVisible = false
        case .matchGone:
            rig.store.match = nil
        }
        // 화면이 `.onChange` 로 부르는 그 문.
        rig.controller.premiseDidChange(store: rig.store)
        #expect(rig.controller.draggingFrom == nil, "전제가 바뀌었는데 말이 손에 남았다")
        #expect(rig.controller.handPoint == nil)
        #expect(rig.store.dragOrigin == nil, "걸쇠가 안 내려갔다")
        #expect(rig.controller.touch.stage == .spent, "그 손이 소진되지 않았다 — 다음 움직임이 말을 다시 집는다")

        rig.move("e3")
        #expect(rig.controller.draggingFrom == nil, "거둔 손이 말을 다시 집었다")
        rig.release("e4")
        #expect(rig.store.pendingDrop == nil, "거둔 뒤 손을 뗐는데 수가 섰다")
        #expect(rig.taps.isEmpty, "거둔 손이 탭을 냈다")
    }

    @Test("기준선 — 전제가 그대로면 통지가 와도 끌기가 안 끊긴다(폴링이 끌기를 끊으면 안 된다)")
    func anUnchangedPremiseKeepsTheDrag() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        rig.pickUp("e2", over: "e4")
        rig.controller.premiseDidChange(store: rig.store)
        rig.controller.latchDidChange(store: rig.store)
        #expect(rig.controller.draggingFrom == sq("e2"), "판이 그대로인데 말을 떨어뜨렸다")
        rig.release("e4")
        #expect(rig.store.pendingDrop?.to == sq("e4"))
    }

    @Test("스토어가 먼저 걸쇠를 내리면 손에서도 거둔다")
    func theStoreLatchRevokes() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        rig.pickUp("e2", over: "e4")
        rig.store.cancelDrag()
        rig.controller.latchDidChange(store: rig.store)
        #expect(rig.controller.draggingFrom == nil)
        rig.release("e4")
        #expect(rig.store.pendingDrop == nil)
    }

    @Test("집기 전에 전제가 바뀌면 끌기만 접히고 탭은 남는다 — 그 뒤 문턱을 넘어도 안 집힌다")
    func revokeBeforePickUpKeepsTheTap() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        rig.press("e2")
        rig.store.match = matchState(plyCount: 11, legalMoves: openingMoves)
        rig.controller.premiseDidChange(store: rig.store)
        rig.move(CGPoint(x: rig.center("e2").x, y: rig.center("e2").y - 6))
        #expect(rig.controller.draggingFrom == nil, "낡은 판정으로 말을 집었다")
        rig.release(CGPoint(x: rig.center("e2").x, y: rig.center("e2").y - 6))
        #expect(rig.taps == [sq("e2")], "탭까지 사라졌다")
    }

    @Test("시스템이 터치를 거두면 말이 제자리로 — 전화·알림 센터")
    func aCancelledTouchDropsThePiece() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        rig.pickUp("e2", over: "e4")
        rig.controller.abandon(store: rig.store)
        #expect(rig.controller.draggingFrom == nil)
        #expect(rig.store.dragOrigin == nil)
        #expect(rig.store.pendingDrop == nil)
        #expect(rig.controller.touch.stage == .idle)
    }

    @Test("끌기 없는 판 — 스토어가 없으면 내 말이든 아니든 탭만 받는다")
    func noStoreMeansTapsOnly() {
        let controller = GamesChessBoardDragController()
        var taps: [ChessSquare] = []
        let port = GamesChessBoardDragController.Port(store: nil, geometry: board(), onTap: { taps.append($0) })
        let start = board().center(of: sq("e2"))
        controller.press(at: start, port: port)
        controller.move(to: CGPoint(x: start.x, y: start.y - 5), port: port)
        #expect(controller.draggingFrom == nil)
        controller.release(at: CGPoint(x: start.x, y: start.y - 5), port: port)
        #expect(taps == [sq("e2")])
    }

    // MARK: 든 말 판정

    @Test("든 말 판정 — 놓은 말이 먼저, 걸쇠가 어긋나면 그리지 않는다")
    func liftResolution() {
        let position = ChessPosition(fen: standardFEN)
        let pending = ChessPendingDrop(matchID: "m", ply: 0, from: sq("e2"), to: sq("e4"),
                                       piece: ChessPiece(.white, .pawn))
        #expect(GamesChessBoardLift.resolve(pending: pending, draggingFrom: sq("d2"), latch: sq("d2"), position: position)?
            .place == .square(sq("e4")), "놓은 말이 먼저다")
        #expect(GamesChessBoardLift.resolve(pending: nil, draggingFrom: sq("d2"), latch: sq("d2"), position: position)?
            .place == .hand)
        #expect(GamesChessBoardLift.resolve(pending: nil, draggingFrom: sq("d2"), latch: nil, position: position) == nil,
                "걸쇠가 내려갔는데 말이 공중에 있다")
        #expect(GamesChessBoardLift.resolve(pending: nil, draggingFrom: sq("d4"), latch: sq("d4"), position: position) == nil,
                "빈 칸에서 말이 나왔다")
    }

    // MARK: ⑧ 배선

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    static func between(_ code: String, from: String, to: String) -> String? {
        guard let start = code.range(of: from),
              let end = code.range(of: to, range: start.upperBound..<code.endIndex) else { return nil }
        return String(code[start.lowerBound..<end.lowerBound])
    }

    @Test("★ 배선 — 두는 두 판(1:1·로봇)은 끌고, 관전 판에는 끌기 인자가 없다")
    func onlyPlayingBoardsDrag() throws {
        for path in ["Sources/CheckMobileKit/Games/GamesChessMatch.swift",
                     "Sources/CheckMobileKit/Games/GamesChessAIViews.swift"] {
            let code = stripComments(try Self.source(path))
            #expect(code.contains("dragStore: store"), "\(path): 이 판에 끌기가 안 붙었다")
        }
        for path in ["Sources/CheckMobileKit/Games/GamesChessWatch.swift",
                     "Sources/CheckMobileKit/Games/GamesChessRanking.swift"] {
            let code = stripComments(try Self.source(path))
            #expect(!code.contains("dragStore"), "\(path): 관전·순위 판에 끌기가 붙었다")
        }
        // 판을 그리는 자리가 늘면 그 자리도 여기서 정해야 한다.
        let games = URL(fileURLWithPath: "Sources/CheckMobileKit/Games", relativeTo: Self.root)
        let files = try FileManager.default.contentsOfDirectory(at: games, includingPropertiesForKeys: nil)
        let callers = try files.filter { $0.pathExtension == "swift" }.filter { file in
            let code = stripComments(try String(contentsOf: file, encoding: .utf8))
            return code.contains("GamesChessBoard(\n") || code.contains("GamesChessBoard(position")
        }.map(\.lastPathComponent).sorted()
        #expect(callers == ["GamesChessAIViews.swift", "GamesChessMatch.swift", "GamesChessWatch.swift"],
                "판을 그리는 자리가 달라졌다: \(callers)")
    }

    @Test("★ 터치 면 — 스크롤이 이 인식기의 실패를 기다리고, 입력 층은 입력이 있는 판에만, TimelineView 밖에 선다")
    func theTouchSurfaceContract() throws {
        let surface = stripComments(try Self.source("Sources/CheckMobileKit/Games/GamesChessBoardTouchSurface.swift"))
        #expect(surface.contains("shouldBeRequiredToFailBy"), "스크롤과의 순서를 정하지 않았다")
        #expect(surface.contains("other is UIPanGestureRecognizer && other.view is UIScrollView"))
        #expect(surface.contains("controller.touch.handsOffToScroll"), "손을 스크롤에 넘기는 길이 없다")
        #expect(surface.contains("state = .failed"))
        #expect(surface.contains("override func reset()"), "끝나는 길을 다 덮지 않았다")
        #expect(surface.contains("dismantleUIView"), "판이 내려갈 때 끌던 말을 안 거둔다")

        let canvas = stripComments(try Self.source("Sources/CheckMobileKit/Games/GamesChessBoardCanvas.swift"))
        #expect(!canvas.contains("SpatialTapGesture"), "옛 탭 제스처가 남았다 — 끌기와 같은 누름에 둘이 답한다")
        let layer = try #require(Self.between(canvas, from: "private func inputLayer(", to: "private func board("))
        #expect(layer.contains("if isInteractive"), "관전 판에도 입력 층이 선다")
        let body = try #require(Self.between(canvas, from: "let handSquare = dragStore", to: "private func dragPort("))
        let head = try #require(Self.between(canvas, from: "let lift = dragStore", to: "GeometryReader { proxy"))
        #expect(head.contains("drag.floatingFrom") && head.contains("drag.handSquare"),
                "끌기 값을 클로저 안에서 읽으면 칸이 바뀌어도 판이 안 그려질 수 있다")
        let timeline = try #require(body.range(of: "TimelineView(.animation"))
        let input = try #require(body.range(of: ".overlay { inputLayer(geometry) }"))
        let closing = try #require(body.range(of: "board(geometry, frame:"))
        #expect(timeline.lowerBound < closing.lowerBound && closing.upperBound < input.lowerBound,
                "입력 층이 TimelineView 안으로 들어갔다 — 틱마다 끌던 손을 떨군다")
        #expect(body.contains("drag.premiseDidChange(store: dragStore)"), "전제 통지가 끊겼다")
        #expect(body.contains("drag.latchDidChange(store: dragStore)"), "걸쇠 통지가 끊겼다")
    }

    @Test("판 본문이 손 좌표를 안 읽는다 — 읽으면 손이 움직일 때마다 64칸을 다시 그린다")
    func theBoardBodyDoesNotReadTheHandPoint() throws {
        let canvas = stripComments(try Self.source("Sources/CheckMobileKit/Games/GamesChessBoardCanvas.swift"))
        #expect(!canvas.contains("handPoint"))
    }

    @Test("데모 장면 라우트 — 꼬리가 값으로 풀리고, 모르는 칸은 장면 없이 판만 연다")
    func theDemoRouteTail() throws {
        let scene = try #require(MobileAppModel.demoChessRoute("games/chess/match/demo-chess-my-turn/drag/c4/f7"))
        #expect(scene.focusMatchID == "demo-chess-my-turn")
        #expect(scene.drag == GamesChessDragPreview(from: sq("c4"), finger: sq("f7"), drops: false))
        let drop = try #require(MobileAppModel.demoChessRoute("games/chess/match/demo-chess-promo/drag/b7/c8/drop"))
        #expect(drop.drag?.drops == true)
        let bad = try #require(MobileAppModel.demoChessRoute("games/chess/match/demo-chess-promo/drag/zz/c8"))
        #expect(bad.focusMatchID == "demo-chess-promo" && bad.drag == nil)
        #expect(MobileAppModel.demoChessRoute("games/chess/match/demo-chess-promo")?.drag == nil)
    }

    @Test("데모 장면은 인식기와 같은 문으로 판을 세운다 — 출발 칸 걸쇠·손 자리·도착 칸이 진짜로 선다")
    func theDemoScenePlaysThroughTheRealDoors() {
        let rig = Rig(store(matchState(legalMoves: openingMoves)))
        GamesChessDragPreview(from: sq("e2"), finger: sq("e4"), drops: false)
            .play(on: rig.controller, port: rig.port)
        #expect(rig.store.dragOrigin == sq("e2"))
        #expect(rig.controller.handPoint == rig.center("e4"))
        #expect(rig.controller.handSquare == sq("e4"))
        #expect(rig.controller.floatingFrom == sq("e2"), "장면이 띄우는 말을 못 세운다 — 캡처가 빈손이 된다")
    }
}

// MARK: - ⑦ 그림

@MainActor
@Suite("폰 체스 끌어 두기 — 그림")
struct GamesChessDragRenderTests {
    private typealias Render = GamesChessFlightRenderTests

    private static func bitmap(lifted: GamesChessBoardLift?, dropTarget: ChessSquare? = nil,
                               targets: Set<ChessSquare> = []) throws -> NSBitmapImageRep {
        let view = GamesChessBoardCanvas(position: ChessPosition(fen: standardFEN), geometry: Render.geometry(),
                                         targets: targets, lifted: lifted, dropTarget: dropTarget)
        return try Render.bake(view.fixedSize())
    }

    private static let pawn = ChessPiece(.white, .pawn)

    @Test("★ 끄는 중 — 출발 칸이 비고, 캔버스는 든 말을 안 그린다(겹치면 말이 둘로 보인다)")
    func theSourceSquareEmpties() throws {
        let g = Render.geometry()
        let e2 = Render.squareProbe(sq("e2"), g), e4 = Render.squareProbe(sq("e4"), g)
        let baseline = try Self.bitmap(lifted: nil)
        #expect(Render.pieceInk(baseline, rect: e2) > 50, "기준선: 집기 전에는 e2 에 말이 있다")
        let held = try Self.bitmap(lifted: GamesChessBoardLift(piece: Self.pawn, from: sq("e2"), place: .hand))
        #expect(Render.pieceInk(held, rect: e2) == 0, "집은 말이 출발 칸에 남았다")
        #expect(Render.pieceInk(held, rect: e4) == 0, "끄는 말을 캔버스가 칸에 그렸다")
    }

    @Test("★ 놓고 기다리는 중 — 출발 칸은 비고 말은 도착 칸에 선다")
    func aPlacedPieceStandsOnItsTarget() throws {
        let g = Render.geometry()
        let e2 = Render.squareProbe(sq("e2"), g), e4 = Render.squareProbe(sq("e4"), g)
        let baseline = try Self.bitmap(lifted: nil)
        #expect(Render.pieceInk(baseline, rect: e4) == 0, "기준선: e4 는 비었다")
        let placed = try Self.bitmap(lifted: GamesChessBoardLift(piece: Self.pawn, from: sq("e2"), place: .square(sq("e4"))))
        #expect(Render.pieceInk(placed, rect: e2) == 0, "놓은 말이 출발 칸에도 있다")
        #expect(Render.pieceInk(placed, rect: e4) > 50, "놓은 말이 도착 칸에 없다")
    }

    @Test("★ 잡는 수로 놓으면 놓은 말만 보인다 — 잡힌 말이 그 밑에 겹치지 않는다")
    func aPlacedPieceHidesTheCapturedOne() throws {
        let g = Render.geometry()
        let e7 = Render.squareProbe(sq("e7"), g)
        let queen = ChessPiece(.white, .queen)
        let lift = GamesChessBoardLift(piece: queen, from: sq("d1"), place: .square(sq("e7")))
        func bake(_ fen: String) throws -> NSBitmapImageRep {
            try Render.bake(GamesChessBoardCanvas(position: ChessPosition(fen: fen), geometry: g, lifted: lift).fixedSize())
        }
        let overPiece = try bake(standardFEN)
        let overEmpty = try bake("rnbqkbnr/pppp1ppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        #expect(Render.pieceInk(overPiece, rect: e7) > 50, "놓은 말이 안 그려졌다")
        #expect(Render.maxChannelDifference(overPiece, overEmpty, rect: e7) < 8, "잡힌 말이 놓은 말 밑에 비친다")
    }

    @Test("★ 손 밑 도착 칸 덮개 — 그림이 달라지지만 말로 세이지 않는다(중간 톤 규칙)")
    func theDropHaloStaysMidTone() throws {
        let g = Render.geometry()
        let e4 = Render.squareProbe(sq("e4"), g)
        let plain = try Self.bitmap(lifted: nil, targets: [sq("e4")])
        let marked = try Self.bitmap(lifted: nil, dropTarget: sq("e4"), targets: [sq("e4")])
        #expect(Render.maxChannelDifference(plain, marked, rect: e4) > 8, "손 밑 칸 표시가 안 그려졌다")
        #expect(Render.pieceInk(marked, rect: e4) == 0, "덮개가 말로 세인다 — 렌더 감지기가 공허해진다")
        // 칸보다 큰 원 — 손가락이 칸을 덮어도 둘레가 보인다.
        let beside = Render.squareProbe(sq("d4"), g)
        #expect(Render.maxChannelDifference(plain, marked, rect: beside) > 4, "원이 칸 밖으로 안 나온다")
    }

    @Test("★ 든 말 그림 — 캔버스와 같은 극단 색으로, 받은 상자 안에 그려진다")
    func theHeldPieceDraws() throws {
        let cell: CGFloat = 45
        let box = cell * GamesChessDragHand.pieceScale
        let rep = try Render.bake(GamesChessHeldPiece(piece: Self.pawn, cell: cell).frame(width: box, height: box))
        let ink = Render.pieceInk(rep, rect: CGRect(x: box * 0.25, y: box * 0.25, width: box * 0.5, height: box * 0.5))
        #expect(ink > 100, "든 말이 안 그려졌다(\(ink))")
    }
}
