import CoreGraphics
import Foundation
import Testing
@testable import CheckCore

// v0.3.48 — 판 위 포인터 해석기(`ChessBoardPointer`). 누름·움직임·뗌이 **어떤 행동으로 나오는가**를 전수로 잰다.
//
// 해석기는 순수 값이라 SwiftUI·창·스토어가 하나도 없다. 그래서 여기 단언은 전부 "이 입력 열을 넣으면 이 행동 열이
// 나온다" 다 — 상태 이름이 무엇인지, 함수가 있는지는 세지 않는다.
//
// ★ 기준선이 갈리는지 확인했다(같은 입력의 기준선은 영원히 초록이다):
//   · 문턱 — 3.9pt(탭) · 4.0pt(끌기) · 4.1pt(끌기), 가로·세로·대각선 → ①
//   · 누름의 종류 — 끌 수 있는 말 · 못 끄는 내 말 · 빈 칸/상대 말 · 도착 칸 넷이 **같은 움직임**에 다른 답 → ②③④
//   · 뗀 자리 — 같은 칸 · 다른 칸 · 판 밖 → ③⑤
//   · 칸 경계를 넘은 손떨림 — 0.8pt · 3.9pt(누른 칸의 탭) · 4.0pt · 4.1pt(아무 일도 없다) → ③b
//   · 취소 — 끌던 중 · 끌기 전 · 아무것도 안 누름 → ⑥

private func dpSquare(_ notation: String) throws -> ChessSquare {
    try #require(ChessSquare(notation), "칸 이름이 아니다: \(notation)")
}

/// 76pt 칸(실제 판과 같은 크기)에서 그 칸 가운데. 백이 아래다 — 해석기는 방향을 모르고, 이 함수는 재는 자리만 만든다.
private func dpCenter(_ square: ChessSquare) -> CGPoint {
    CGPoint(x: CGFloat(square.file) * 76 + 38, y: CGFloat(7 - square.rank) * 76 + 38)
}

private typealias Action = ChessBoardPointer.Action

@Suite("체스 끌기 — 포인터 해석기")
struct V0348ChessDragPointerTests {

    // MARK: - ① 문턱 경계(3.9 / 4.0 / 4.1pt)

    @Test("문턱 — 3.9pt 는 탭이고 4.0pt 부터 끌기다(가로·세로·대각선)")
    func thresholdBoundary() throws {
        // 없으면: 문턱이 0 이어도(모든 클릭이 끌기) · 40 이어도(끌기가 안 잡힘) · `>` 로 뒤집혀도 초록이다.
        let e2 = try dpSquare("e2")
        let origin = dpCenter(e2)
        #expect(ChessBoardPointer.dragThreshold == 4)

        // (방향, 거리) → 끌기인가. 대각선은 **유클리드 거리**로 잰다 — 축마다 따로 재면 (3, 3)=4.24pt 가 탭이 된다.
        let cases: [(dx: CGFloat, dy: CGFloat, drags: Bool)] = [
            (3.9, 0, false), (4.0, 0, true), (4.1, 0, true),
            (0, -3.9, false), (0, -4.0, true), (0, 4.1, true),
            (-3.9, 0, false), (-4.0, 0, true),
            (2.8, 2.8, false),          // 3.96pt
            (3.0, 3.0, true),           // 4.24pt — 어느 축도 4 를 안 넘지만 거리는 넘는다
        ]
        for item in cases {
            var pointer = ChessBoardPointer()
            #expect(pointer.press(at: origin, square: e2, grab: .movable, isSelectionTarget: false) == [])
            let moved = CGPoint(x: origin.x + item.dx, y: origin.y + item.dy)
            let actions = pointer.move(to: moved)
            if item.drags {
                #expect(actions == [.beginDrag(e2), .dragMoved(moved)],
                        "(\(item.dx), \(item.dy)) 움직였는데 끌기가 안 시작됐다: \(actions)")
                #expect(pointer.draggingFrom == e2)
            } else {
                #expect(actions == [], "(\(item.dx), \(item.dy)) 는 문턱 밑인데 행동이 나왔다: \(actions)")
                #expect(pointer.draggingFrom == nil)
                // 그리고 그 자리에서 떼면 **지금의 탭 그대로**다.
                #expect(pointer.release(at: moved, square: e2) == [.tap(e2)])
            }
        }
    }

    @Test("문턱 밑에서 흔들리다 뗀 누름은 탭 한 번이다 — 끌기도 놓기도 안 나온다")
    func jitterUnderTheThresholdIsOneTap() throws {
        // 없으면: 흔들림이 **누적**돼 끌기로 넘어가도(매 움직임의 변위를 더해도) 초록이다. 문턱은 누른 자리에서 잰다.
        let e2 = try dpSquare("e2")
        let origin = dpCenter(e2)
        var pointer = ChessBoardPointer()
        _ = pointer.press(at: origin, square: e2, grab: .movable, isSelectionTarget: false)
        var all: [Action] = []
        for step in 0..<40 {
            let wobble = CGPoint(x: origin.x + (step.isMultiple(of: 2) ? 3 : -3), y: origin.y + 2)
            all += pointer.move(to: wobble)
        }
        all += pointer.release(at: CGPoint(x: origin.x + 3, y: origin.y + 2), square: e2)
        #expect(all == [.tap(e2)], "문턱 밑 흔들림 40번이 \(all) 을 냈다")
        #expect(pointer.isIdle)
    }

    @Test("한 번 넘은 문턱은 되돌아와도 끌기다 — 출발 칸에 도로 놓는 것은 놓기이지 탭이 아니다")
    func onceDraggingAlwaysDragging() throws {
        // 없으면: 말을 집어 들었다가 제자리에 내려놓은 것이 탭(= 고르기 **해제**)으로 읽혀도 초록이다.
        let e2 = try dpSquare("e2")
        let origin = dpCenter(e2)
        var pointer = ChessBoardPointer()
        _ = pointer.press(at: origin, square: e2, grab: .movable, isSelectionTarget: false)
        _ = pointer.move(to: CGPoint(x: origin.x + 30, y: origin.y))
        #expect(pointer.move(to: origin) == [.dragMoved(origin)], "되돌아온 움직임이 끄는 자리로 안 나왔다")
        #expect(pointer.release(at: origin, square: e2) == [.drop(from: e2, on: e2)])
    }

    @Test("움직임 없이 멀리서 뗌만 온 누름도 끌기다 — 시작과 놓기가 함께 나온다")
    func flickWithoutMoveEvents() throws {
        // 없으면: 빠르게 튕긴 끌기(중간 움직임이 한 번도 안 온다)가 **누른 칸의 탭**으로 읽혀 말이 안 간다.
        let e2 = try dpSquare("e2"), e4 = try dpSquare("e4")
        var pointer = ChessBoardPointer()
        _ = pointer.press(at: dpCenter(e2), square: e2, grab: .movable, isSelectionTarget: false)
        #expect(pointer.release(at: dpCenter(e4), square: e4) == [.beginDrag(e2), .drop(from: e2, on: e4)])
        #expect(pointer.isIdle)
    }

    // MARK: - ② 끌기 → 놓기(칸 · 판 밖)

    @Test("끌기의 한 바퀴 — 시작 한 번, 자리 여럿, 놓기 한 번")
    func aFullDrag() throws {
        // 없으면: 움직일 때마다 `beginDrag` 가 다시 나가거나(고르기가 매번 다시 선다) 놓기가 두 번 나가도 초록이다.
        let e2 = try dpSquare("e2"), e4 = try dpSquare("e4")
        var pointer = ChessBoardPointer()
        var all: [Action] = []
        all += pointer.press(at: dpCenter(e2), square: e2, grab: .movable, isSelectionTarget: false)
        let path = stride(from: 0, through: 152, by: 19).map { CGPoint(x: dpCenter(e2).x, y: dpCenter(e2).y - CGFloat($0)) }
        for point in path { all += pointer.move(to: point) }
        all += pointer.release(at: dpCenter(e4), square: e4)

        #expect(all.filter { if case .beginDrag = $0 { return true } else { return false } } == [.beginDrag(e2)])
        #expect(all.last == .drop(from: e2, on: e4))
        #expect(all.filter { if case .drop = $0 { return true } else { return false } }.count == 1)
        // 끄는 자리는 문턱을 넘은 뒤의 움직임마다 하나씩이다(0pt 는 문턱 밑이라 안 나온다).
        let moved = all.compactMap { action -> CGPoint? in
            if case .dragMoved(let point) = action { return point } else { return nil }
        }
        #expect(moved == Array(path.dropFirst()))
        #expect(!all.contains { if case .tap = $0 { return true } else { return false } }, "끌기에서 탭이 나왔다")
        // 뗀 뒤의 움직임·뗌은 아무것도 안 낸다.
        #expect(pointer.move(to: dpCenter(e4)) == [])
        #expect(pointer.release(at: dpCenter(e4), square: e4) == [])
    }

    @Test("판 밖에서 떼면 놓은 칸이 nil 이다 — 누른 칸으로 바꿔치지 않는다")
    func droppingOffTheBoard() throws {
        // 없으면: 판 밖 뗌이 "가장 가까운 칸" 이나 누른 칸으로 접혀, 손이 판을 벗어난 사람의 말이 엉뚱한 칸에 놓인다.
        let e2 = try dpSquare("e2")
        var pointer = ChessBoardPointer()
        _ = pointer.press(at: dpCenter(e2), square: e2, grab: .movable, isSelectionTarget: false)
        _ = pointer.move(to: CGPoint(x: -40, y: 300))
        #expect(pointer.release(at: CGPoint(x: -40, y: 300), square: nil) == [.drop(from: e2, on: nil)])
    }

    // MARK: - ③ 끌기가 안 되는 누름 — 같은 칸에서 뗐거나(③) 문턱 밑에서 뗐을 때만(③b) 탭

    @Test("빈 칸·상대 말 — 4pt 를 넘겨 떨려도 같은 칸이면 탭, 다른 칸·판 밖이면 아무 일도 없다")
    func plainPressTapsOnlyOnTheSameSquare() throws {
        // 없으면: 끌기가 안 되는 누름이 끌기로 시작되거나, 다른 칸에서 뗀 것이 누른 칸의 탭으로 나가도 초록이다.
        let e4 = try dpSquare("e4"), e5 = try dpSquare("e5")
        let origin = dpCenter(e4)
        // 같은 칸 안에서 30pt(문턱의 7배) 움직였다 — 그래도 탭이다.
        var same = ChessBoardPointer()
        _ = same.press(at: origin, square: e4, grab: .none, isSelectionTarget: false)
        let inside = CGPoint(x: origin.x + 30, y: origin.y - 20)
        #expect(same.move(to: inside) == [], "끌 수 없는 누름이 움직임에 행동을 냈다")
        #expect(same.draggingFrom == nil)
        #expect(same.release(at: inside, square: e4) == [.tap(e4)])

        var other = ChessBoardPointer()
        _ = other.press(at: origin, square: e4, grab: .none, isSelectionTarget: false)
        _ = other.move(to: dpCenter(e5))
        #expect(other.release(at: dpCenter(e5), square: e5) == [], "다른 칸에서 뗐는데 행동이 나왔다")

        var outside = ChessBoardPointer()
        _ = outside.press(at: origin, square: e4, grab: .none, isSelectionTarget: false)
        #expect(outside.release(at: CGPoint(x: 700, y: 10), square: nil) == [])
        #expect(outside.isIdle)
    }

    @Test("도착 칸을 눌렀으면 끌기가 아니다 — 그 칸에 끌 수 있는 말이 있다고 해도")
    func pressingASelectionTargetNeverDrags() throws {
        // 없으면: 고른 말의 도착 칸을 누르며 손이 4pt 미끄러진 클릭-도착이 **그 칸의 말을 집는 끌기**로 읽힌다.
        // 기준선: `isSelectionTarget` 만 다르고 나머지가 같은 누름은 끌기가 된다.
        let d5 = try dpSquare("d5")
        let origin = dpCenter(d5)
        let slid = CGPoint(x: origin.x + 9, y: origin.y)

        var target = ChessBoardPointer()
        _ = target.press(at: origin, square: d5, grab: .movable, isSelectionTarget: true)
        #expect(target.move(to: slid) == [])
        #expect(target.release(at: slid, square: d5) == [.tap(d5)], "도착 칸 누름이 탭으로 안 나왔다")

        var plain = ChessBoardPointer()
        _ = plain.press(at: origin, square: d5, grab: .movable, isSelectionTarget: false)
        #expect(plain.move(to: slid) == [.beginDrag(d5), .dragMoved(slid)], "전제: 같은 누름이 도착 칸이 아니면 끌기다")
    }

    // MARK: - ③b 칸 경계를 넘은 손떨림 — 문턱 밑이면 누른 칸의 탭이다

    @Test("끌기가 안 되는 누름 — 문턱 밑 손떨림은 칸 경계를 넘어 떼도 누른 칸의 탭이고, 4pt 부터는 아무 일도 없다")
    func aWiggleAcrossACellBorderStillTapsThePressedSquare() throws {
        // 없으면: 도착 칸의 경계 0.4pt 안쪽을 누른 손이 0.4pt 바깥(옆 칸)에서 떼면 **수도 문구도 없이** 삼켜진다
        //        (옛 탭 제스처는 같은 입력에 적어도 거절 문구를 냈다). 반대로 문턱을 없애 "어디서 떼든 누른 칸의 탭"
        //        으로 풀어도 초록이면 안 된다 — 누른 채 옆 칸으로 옮겨 가 버린 손은 클릭이 아니다.
        let e4 = try dpSquare("e4"), f4 = try dpSquare("f4"), e5 = try dpSquare("e5"), h4 = try dpSquare("h4")
        // e4 와 f4 가 만나는 세로 경계(x = 380) · e4 와 e5 가 만나는 가로 경계(y = 304) · 판의 오른쪽 변(x = 608).
        let borderX = dpCenter(e4).x + 38, borderY = dpCenter(e4).y - 38, edgeX = dpCenter(h4).x + 38
        let rowY = dpCenter(e4).y

        struct Wiggle {
            let label: String
            let press: CGPoint
            let pressed: ChessSquare
            let release: CGPoint
            let released: ChessSquare?
            let taps: Bool
        }
        // 정확히 4.0pt 인 경우는 2진수로 딱 떨어지는 좌표(….5)로만 만든다 — 경계가 뺄셈의 반올림에 안 흔들린다.
        let cases: [Wiggle] = [
            Wiggle(label: "0.8pt(경계 0.4pt 안 → 0.4pt 밖)",
                   press: CGPoint(x: borderX - 0.4, y: rowY), pressed: e4,
                   release: CGPoint(x: borderX + 0.4, y: rowY), released: f4, taps: true),
            Wiggle(label: "3.9pt",
                   press: CGPoint(x: borderX - 0.5, y: rowY), pressed: e4,
                   release: CGPoint(x: borderX + 3.4, y: rowY), released: f4, taps: true),
            Wiggle(label: "4.0pt",
                   press: CGPoint(x: borderX - 0.5, y: rowY), pressed: e4,
                   release: CGPoint(x: borderX + 3.5, y: rowY), released: f4, taps: false),
            Wiggle(label: "4.1pt",
                   press: CGPoint(x: borderX - 0.5, y: rowY), pressed: e4,
                   release: CGPoint(x: borderX + 3.6, y: rowY), released: f4, taps: false),
            Wiggle(label: "세로 3.0pt(위 칸으로)",
                   press: CGPoint(x: dpCenter(e4).x, y: borderY + 1.5), pressed: e4,
                   release: CGPoint(x: dpCenter(e4).x, y: borderY - 1.5), released: e5, taps: true),
            Wiggle(label: "세로 4.0pt(위 칸으로)",
                   press: CGPoint(x: dpCenter(e4).x, y: borderY + 0.5), pressed: e4,
                   release: CGPoint(x: dpCenter(e4).x, y: borderY - 3.5), released: e5, taps: false),
            Wiggle(label: "판 밖으로 0.8pt",
                   press: CGPoint(x: edgeX - 0.4, y: rowY), pressed: h4,
                   release: CGPoint(x: edgeX + 0.4, y: rowY), released: nil, taps: true),
            Wiggle(label: "판 밖으로 4.0pt",
                   press: CGPoint(x: edgeX - 0.5, y: rowY), pressed: h4,
                   release: CGPoint(x: edgeX + 3.5, y: rowY), released: nil, taps: false),
        ]
        // 끌기가 안 되는 누름 둘: 빈 칸·상대 말(`none`) · 도착 칸(끌 수 있는 말이 서 있어도 `none` 으로 덮인다).
        let presses: [(name: String, grab: ChessBoardPointer.Grab, isTarget: Bool)] = [
            ("빈 칸·상대 말", .none, false), ("도착 칸", .none, true), ("도착 칸(내 말이 선)", .movable, true),
        ]
        for item in cases {
            for kind in presses {
                var pointer = ChessBoardPointer()
                #expect(pointer.press(at: item.press, square: item.pressed, grab: kind.grab,
                                      isSelectionTarget: kind.isTarget) == [])
                #expect(pointer.move(to: item.release) == [], "\(kind.name) · \(item.label): 움직임에 행동이 나왔다")
                let released = pointer.release(at: item.release, square: item.released)
                let wanted: [Action] = item.taps ? [.tap(item.pressed)] : []
                #expect(released == wanted,
                        "\(kind.name) · \(item.label): \(item.released?.notation ?? "판 밖") 에서 뗐더니 \(released)")
                #expect(pointer.isIdle)
            }
        }
        // ★ 기준선: 같은 칸 안이면 문턱을 넘겨도 탭이다(③) — 4pt 가 "탭의 한계" 가 된 것이 아니다.
        var same = ChessBoardPointer()
        _ = same.press(at: CGPoint(x: borderX - 30, y: rowY), square: e4, grab: .none, isSelectionTarget: true)
        #expect(same.release(at: CGPoint(x: borderX - 0.5, y: rowY), square: e4) == [.tap(e4)])
    }

    // MARK: - ④ 못 끄는 내 말 — 끌기는 없고, 뗄 때 거절 한 번

    @Test("못 끄는 내 말을 끌려 하면 끌기는 안 시작되고, 어디서 떼든 탭이 **한 번** 나온다")
    func stuckPieceRefusesOnceOnRelease() throws {
        // 없으면: 내 차례가 아닐 때 말을 끌려 한 사람이 아무 답도 못 받거나(다른 칸에서 떼면 무음),
        //        문턱을 넘는 순간과 뗄 때 **두 번** 거절을 듣는다.
        let e2 = try dpSquare("e2"), e4 = try dpSquare("e4")
        for release in [(point: dpCenter(e4), square: Optional(e4)),      // 다른 칸
                        (point: dpCenter(e2), square: Optional(e2)),      // 같은 칸
                        (point: CGPoint(x: -5, y: -5), square: nil)] {    // 판 밖
            var pointer = ChessBoardPointer()
            var all: [Action] = []
            all += pointer.press(at: dpCenter(e2), square: e2, grab: .stuck, isSelectionTarget: false)
            all += pointer.move(to: CGPoint(x: dpCenter(e2).x, y: dpCenter(e2).y - 60))
            all += pointer.move(to: release.point)
            #expect(all == [], "못 끄는 말이 움직임에 행동을 냈다: \(all)")
            #expect(pointer.draggingFrom == nil)
            all += pointer.release(at: release.point, square: release.square)
            #expect(all == [.tap(e2)], "\(release.square?.notation ?? "판 밖") 에서 뗐을 때 \(all)")
        }
    }

    // MARK: - ⑤ 판 밖 누름

    @Test("판 밖을 누른 누름은 뗄 때까지 아무것도 안 낸다 — 판 안으로 들어와 떼도")
    func pressingOffTheBoardIsSilent() throws {
        // 없으면: 판 밖에서 누른 채 판 안으로 들어와 뗀 것이 그 칸의 탭으로 읽힌다(옛 탭 제스처에는 없던 입력이다).
        let e4 = try dpSquare("e4")
        var pointer = ChessBoardPointer()
        #expect(pointer.press(at: CGPoint(x: -3, y: 100), square: nil, grab: .none, isSelectionTarget: false) == [])
        #expect(!pointer.isIdle)
        #expect(pointer.move(to: dpCenter(e4)) == [])
        #expect(pointer.release(at: dpCenter(e4), square: e4) == [])
        #expect(pointer.isIdle)
    }

    // MARK: - ⑥ 취소

    @Test("끌던 중에 취소하면 거두기가 한 번 나오고, 그 뒤의 움직임·뗌은 아무것도 안 낸다")
    func cancelWhileDraggingSpendsThePress() throws {
        // 없으면: 끄는 중에 상대가 기권했는데 그 뒤 마우스를 뗀 자리로 **수가 나간다**.
        //        또는 취소된 누름이 처음으로 돌아가, 다음 움직임이 새 누름으로 읽혀 같은 말을 다시 집는다.
        let e2 = try dpSquare("e2"), e4 = try dpSquare("e4")
        var pointer = ChessBoardPointer()
        _ = pointer.press(at: dpCenter(e2), square: e2, grab: .movable, isSelectionTarget: false)
        _ = pointer.move(to: dpCenter(e4))
        #expect(pointer.draggingFrom == e2)

        #expect(pointer.cancel() == [.cancel])
        #expect(pointer.draggingFrom == nil)
        #expect(!pointer.isIdle, "취소된 누름이 처음으로 돌아갔다 — 마우스는 아직 눌려 있다")
        #expect(pointer.isTracking(pressAt: dpCenter(e2)), "취소 뒤의 움직임이 새 누름으로 읽힌다")
        #expect(pointer.cancel() == [], "두 번째 취소가 또 거두기를 냈다")
        #expect(pointer.move(to: dpCenter(e4)) == [])
        #expect(pointer.release(at: dpCenter(e4), square: e4) == [], "취소한 뒤 뗐는데 놓기가 나갔다")
        #expect(pointer.isIdle)

        // ★ 기준선: 취소가 없으면 같은 입력이 놓기를 낸다.
        var control = ChessBoardPointer()
        _ = control.press(at: dpCenter(e2), square: e2, grab: .movable, isSelectionTarget: false)
        _ = control.move(to: dpCenter(e4))
        #expect(control.release(at: dpCenter(e4), square: e4) == [.drop(from: e2, on: e4)])
    }

    @Test("끌기 전의 취소는 '끌 수 있다' 만 버린다 — 같은 칸에서 떼면 탭은 그대로 나간다")
    func cancelBeforeDraggingKeepsTheTap() throws {
        // 없으면: 판이 바뀐 뒤에도 누를 때의 판정으로 끌기가 시작되거나(바뀐 판의 말이 아니다),
        //        반대로 취소가 탭까지 지워 클릭-클릭이 폴링 한 번에 씹힌다.
        let e2 = try dpSquare("e2"), e4 = try dpSquare("e4")
        for grab in [ChessBoardPointer.Grab.movable, .stuck, .none] {
            var same = ChessBoardPointer()
            _ = same.press(at: dpCenter(e2), square: e2, grab: grab, isSelectionTarget: false)
            #expect(same.cancel() == [], "끌기 전 취소가 행동을 냈다")
            #expect(same.move(to: CGPoint(x: dpCenter(e2).x + 20, y: dpCenter(e2).y)) == [],
                    "\(grab): 취소한 뒤에 끌기가 시작됐다")
            #expect(same.release(at: dpCenter(e2), square: e2) == [.tap(e2)], "\(grab): 탭이 사라졌다")

            var other = ChessBoardPointer()
            _ = other.press(at: dpCenter(e2), square: e2, grab: grab, isSelectionTarget: false)
            _ = other.cancel()
            #expect(other.release(at: dpCenter(e4), square: e4) == [], "\(grab): 다른 칸에서 뗐는데 행동이 나왔다")
        }
        // 아무것도 안 누른 채의 취소는 아무 일도 없다(판이 바뀔 때마다 불린다).
        var idle = ChessBoardPointer()
        #expect(idle.cancel() == [])
        #expect(idle.isIdle)
    }

    @Test("스토어가 끌기를 거절하면 그 누름은 조용히 끝난다 — 뗄 때 놓기도 탭도 안 나온다")
    func refusedDragIsSpent() throws {
        // 없으면: 스토어가 "보내는 중" 이라 거절한 끌기가 뗄 때 놓기를 또 내서 거절 문구가 두 번 뜬다.
        let e2 = try dpSquare("e2"), e4 = try dpSquare("e4")
        var pointer = ChessBoardPointer()
        _ = pointer.press(at: dpCenter(e2), square: e2, grab: .movable, isSelectionTarget: false)
        #expect(pointer.move(to: dpCenter(e4)).first == .beginDrag(e2))
        pointer.dragRefused()
        #expect(pointer.draggingFrom == nil)
        #expect(pointer.move(to: dpCenter(e4)) == [])
        #expect(pointer.release(at: dpCenter(e4), square: e4) == [])
        #expect(pointer.isIdle)
        // 끌고 있지 않을 때의 거절 통지는 아무것도 안 바꾼다(뗌과 함께 나온 시작이 거절된 경우다).
        pointer.dragRefused()
        #expect(pointer.isIdle)
    }

    // MARK: - ⑦ 뗌 없이 끝난 누름

    @Test("뗌 없이 죽은 누름 뒤의 새 누름 — 끌던 말을 거두고 새로 시작한다")
    func aNewPressAfterALostRelease() throws {
        // 없으면: 제스처가 중간에 죽으면 해석기가 '끄는 중' 에 굳어, 다음 클릭이 **옛 말의 놓기**로 나간다.
        let e2 = try dpSquare("e2"), e4 = try dpSquare("e4"), g1 = try dpSquare("g1")
        var pointer = ChessBoardPointer()
        _ = pointer.press(at: dpCenter(e2), square: e2, grab: .movable, isSelectionTarget: false)
        _ = pointer.move(to: dpCenter(e4))

        // 뷰는 "이 시작점을 따라가고 있는가" 로 새 누름을 가린다.
        #expect(pointer.isTracking(pressAt: dpCenter(e2)))
        #expect(!pointer.isTracking(pressAt: dpCenter(g1)), "다른 점에서 시작한 누름을 같은 누름으로 본다")

        #expect(pointer.press(at: dpCenter(g1), square: g1, grab: .movable, isSelectionTarget: false) == [.cancel])
        #expect(pointer.draggingFrom == nil)
        #expect(pointer.isTracking(pressAt: dpCenter(g1)))
        #expect(!pointer.isTracking(pressAt: dpCenter(e2)), "거둔 누름을 아직 따라가고 있다")
        #expect(pointer.release(at: dpCenter(g1), square: g1) == [.tap(g1)], "새 누름이 옛 말의 놓기로 나갔다")
        #expect(!pointer.isTracking(pressAt: dpCenter(g1)), "뗀 누름을 아직 따라가고 있다 — 같은 자리의 다음 클릭이 안 눌린다")

        // 끌기 전에 죽은 누름은 거둘 말이 없다 — 새 누름만 받는다.
        var early = ChessBoardPointer()
        _ = early.press(at: dpCenter(e2), square: e2, grab: .movable, isSelectionTarget: false)
        #expect(early.press(at: dpCenter(g1), square: g1, grab: .none, isSelectionTarget: false) == [])
        #expect(early.release(at: dpCenter(g1), square: g1) == [.tap(g1)])
        // 소진된 누름(취소된 끌기)이 뗌 없이 죽어도 같다.
        var spent = ChessBoardPointer()
        _ = spent.press(at: dpCenter(e2), square: e2, grab: .movable, isSelectionTarget: false)
        _ = spent.move(to: dpCenter(e4))
        _ = spent.cancel()
        #expect(spent.press(at: dpCenter(g1), square: g1, grab: .movable, isSelectionTarget: false) == [],
                "이미 거둔 끌기를 또 거뒀다")
        #expect(spent.release(at: dpCenter(g1), square: g1) == [.tap(g1)])
    }
}
