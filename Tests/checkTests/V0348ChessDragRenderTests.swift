import AppKit
import CheckRenderTestSupport
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.48 체스 **끌어서 두기의 그림** — 손에 든 말(`ChessBoardLift`) · 끄는 말 밑의 도착 칸(`dropTarget`) ·
// 끌어 놓아 이미 도착해 있는 말의 겹침(`ChessFlightFrame.landed`)을 전부 **잉크를 세서** 잰다.
//
// ★ 여기서 재는 것은 "인자를 받았다" 가 아니다. 모든 단언은 비트맵의 픽셀 수거나 픽셀 좌표다 — 손에 든 말을
//   받아 놓고 **출발 칸에도 그대로 그리는** 뷰(말이 둘로 보인다), 커서 자리에 **안 그리는** 뷰, 잡힌 말을
//   끌어 놓은 말 **위에** 그리는 뷰가 전부 빨개져야 한다.
//
// ★ 감지기는 V0344·V0346 과 같다: 칸·덮개는 전부 중간 톤이고 **말만 극단**(최대 ≥ 235 또는 최소 ≤ 55)이라
//   "그 자리에 극단 픽셀이 있는가" 가 곧 "그 자리에 말이 있는가" 다. 그래서 새 덮개(`dropTarget`)도 중간 톤에
//   머무는지를 여기서 되묻는다 — 극단으로 떨어지면 빈 칸이 말로 세어져 이 저장소의 체스 렌더 검증이 통째로 눈이 먼다.
//
// ★ 그림끼리의 "같다"·"다르다" 는 `CheckRenderDiff` 로만 잰다(같다 Δ≤2 · 다르다 Δ>8 픽셀 40개↑). 바이트 동치는
//   쓰지 않는다. 그림은 `CheckRenderSettle` 로 굳혀서 굽는다(ImageRenderer 는 첫 두 장을 다르게 굽는다).
//
// PNG 는 `CHECK_SNAPSHOT_DIR/chess-drag/` 에 남는다 — 사람이 직접 열어 본다.

// MARK: - 헬퍼 (V0346ChessFlightRenderTests 의 것은 private 이라 복사 — 같은 규칙)

private let drAfterE4FEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
/// 1.e4 d5 뒤(백 차례). 백 폰 e4 가 흑 폰 d5 를 잡을 수 있다.
private let drBeforeCaptureFEN = "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2"
/// 2.exd5 뒤(흑 차례). 백 폰이 d5 에 서 있다.
private let drAfterCaptureFEN = "rnbqkbnr/ppp1pppp/8/3P4/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2"
/// 킹사이드 캐슬링 뒤: 왕 g1 · 룩 f1.
private let drCastledFEN = "4k3/8/8/8/8/8/8/5RK1 b - - 1 1"

private func drPosition(_ fen: String) throws -> ChessPosition {
    try #require(ChessPosition(fen: fen), "FEN 을 못 읽었다: \(fen)")
}

private func drSquare(_ notation: String) throws -> ChessSquare {
    try #require(ChessSquare(notation))
}

private func drGeometry(_ orientation: ChessColor = .white) -> ChessBoardGeometry {
    ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: orientation)
}

private enum DRRenderError: Error { case failed }

/// 판 **하나만** 그린 굳은 비트맵(scale 2).
@MainActor
private func drBitmap(_ view: ChessBoardView, name: String) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2) else { throw DRRenderError.failed }
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "chess-drag")
    return bitmap
}

private func drDiff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) throws -> CheckRenderDiff {
    let imageA = try #require(a.cgImage), imageB = try #require(b.cgImage)
    return try #require(CheckRenderDiff(imageA, imageB), "두 그림을 견줄 판을 못 만들었다")
}

/// 그 칸의 **가운데 50% 상자**(판 좌표) — 칸 테두리·좌표 글자를 뺀다.
private func drProbe(_ square: ChessSquare, _ g: ChessBoardGeometry) -> CGRect {
    let box = g.rect(of: square)
    return box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)
}

/// 한 점을 가운데로 둔 `fraction` 칸 크기 상자.
private func drPointProbe(_ point: CGPoint, _ g: ChessBoardGeometry, fraction: CGFloat = 0.5) -> CGRect {
    let side = g.cell * fraction
    return CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
}

private func drCount(_ bitmap: NSBitmapImageRep, rect: CGRect,
                     where predicate: (Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var hits = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if predicate(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) { hits += 1 }
        }
    }
    return hits
}

/// **말 잉크** — 아주 밝거나(최대 ≥ 235) 아주 어두운(최소 ≤ 55) 픽셀.
private func drPieceInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    drCount(bitmap, rect: rect) { r, g, b in max(r, max(g, b)) >= 235 || min(r, min(g, b)) <= 55 }
}

/// **밝은** 쪽만(최대 ≥ 235) — 흰 말의 채움. 이 수가 줄면 그 자리를 다른 것이 덮었다는 뜻이다.
private func drBrightInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    drCount(bitmap, rect: rect) { r, g, b in max(r, max(g, b)) >= 235 }
}

/// **어두운** 쪽만(최소 ≤ 55) — 흑 말의 채움.
private func drDarkInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    drCount(bitmap, rect: rect) { r, g, b in min(r, min(g, b)) <= 55 }
}

/// 사각형 안 채널 값의 (최소, 최대) — 덮개가 **중간 톤**에 머무는지를 숫자로 본다.
private func drChannelRange(_ bitmap: NSBitmapImageRep, rect: CGRect) -> (low: Int, high: Int) {
    var low = 255, high = 0
    _ = drCount(bitmap, rect: rect) { r, g, b in
        low = min(low, min(r, min(g, b)))
        high = max(high, max(r, max(g, b)))
        return false
    }
    return (low, high)
}

/// 말이 선 칸의 표기 집합(가운데 50% 상자에 말 잉크가 있는 칸).
private func drInkedSquares(_ bitmap: NSBitmapImageRep, _ g: ChessBoardGeometry) -> Set<String> {
    var out: Set<String> = []
    for index in 0..<64 {
        guard let square = ChessSquare(index: index) else { continue }
        if drPieceInk(bitmap, rect: drProbe(square, g)) > 0 { out.insert(square.notation) }
    }
    return out
}

/// 사각형 안 **말 잉크를 감싸는 상자**(pt). 잉크가 없으면 nil.
private func drInkBounds(_ bitmap: NSBitmapImageRep, rect: CGRect) -> CGRect? {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return nil }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return nil }
    var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
            guard max(r, max(g, b)) >= 235 || min(r, min(g, b)) <= 55 else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard minX <= maxX else { return nil }
    return CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2,
                  width: CGFloat(maxX - minX) / 2, height: CGFloat(maxY - minY) / 2)
}

private let drWhitePawn = ChessPiece(.white, .pawn)

// MARK: - ① 끄는 중 — 출발 칸에 말이 없고 커서 자리에 말이 있다

/// 없으면: 손에 든 말을 받아 놓고 **출발 칸에도 그대로 그려** 말이 둘로 보이거나, 커서 자리에 아무것도 안
/// 그려 "집었는데 말이 사라졌다" 가 되어도 초록이다.
@MainActor
@Test
func theDraggedPieceLeavesItsSquareAndFollowsTheCursor() throws {
    let g = drGeometry()
    let e2 = try drSquare("e2"), e4 = try drSquare("e4")
    // 커서는 e4 칸 한가운데(빈 칸). 프로브가 칸 하나로 떨어진다.
    let cursor = g.center(of: e4)

    let resting = try drBitmap(ChessBoardView(position: .standard, geometry: g, selected: e2), name: "drag-resting")
    let dragging = try drBitmap(
        ChessBoardView(position: .standard, geometry: g, selected: e2,
                       lifted: ChessBoardLift(piece: drWhitePawn, from: e2, place: .cursor(cursor))),
        name: "drag-over-e4")

    let from = (resting: drPieceInk(resting, rect: drProbe(e2, g)), dragging: drPieceInk(dragging, rect: drProbe(e2, g)))
    let at = (resting: drPieceInk(resting, rect: drProbe(e4, g)), dragging: drPieceInk(dragging, rect: drProbe(e4, g)))
    print("[끄는 중] 출발 e2 \(from.resting)→\(from.dragging)px · 커서 e4 \(at.resting)→\(at.dragging)px")

    #expect(from.resting > 0, "전제: 멈춘 판의 e2 에 폰이 있다")
    #expect(from.dragging == 0, "끄는 중인데 출발 칸에 말이 남아 있다(\(from.dragging)px) — 말이 둘로 보인다")
    #expect(at.resting == 0, "전제: 멈춘 판의 e4 는 비었다")
    #expect(at.dragging > 0, "커서 자리에 말이 없다 — 집은 말이 사라졌다")

    // 판의 나머지는 그대로다: 말이 선 칸이 정확히 "e2 가 빠지고 e4 가 든" 집합이다(31 + 1).
    var expected = Set(ChessPosition.standard.pieces.map(\.square.notation))
    expected.remove("e2")
    expected.insert("e4")
    #expect(drInkedSquares(dragging, g) == expected)
    let moved = try drDiff(resting, dragging)
    #expect(moved.looksDifferent, "끄는 그림이 멈춘 그림과 같다(\(moved))")

    // 선택 덮개는 출발 칸에 **남는다**(어디서 집었는지 보인다) — 말을 숨기면서 덮개까지 지우지 않는다.
    let noOverlay = try drBitmap(
        ChessBoardView(position: .standard, geometry: g,
                       lifted: ChessBoardLift(piece: drWhitePawn, from: e2, place: .cursor(cursor))),
        name: "drag-no-selection")
    let overlay = try drDiff(dragging, noOverlay)
    print("[끄는 중] 출발 칸 선택 덮개 유무 차이: \(overlay)")
    #expect(overlay.looksDifferent, "말을 든 출발 칸에 선택 덮개가 안 그려진다(\(overlay))")

    // 살짝 크게(1.12배) 그린다 — 잉크 상자의 폭이 멈춘 폰보다 넓다.
    let still = try #require(drInkBounds(resting, rect: g.rect(of: e2)))
    let lifted = try #require(drInkBounds(dragging, rect: g.rect(of: e4).insetBy(dx: -8, dy: -8)))
    let ratio = lifted.width / still.width
    print("[끄는 중] 폰 잉크 폭 \(still.width)pt → \(lifted.width)pt (×\(ratio))")
    #expect(ratio > 1.07 && ratio < 1.17, "끄는 말의 크기가 ×\(ratio) 다 — 1.12배여야 한다")
    // 말 **중심**이 커서다: 잉크 상자의 가로 중심이 커서 x 와 같다(폰은 좌우 대칭이다).
    #expect(abs(lifted.midX - cursor.x) < 1.5, "끄는 말의 중심이 커서에서 \(lifted.midX - cursor.x)pt 벗어났다")
}

/// 없으면: 커서가 칸 **사이**에 있을 때 말이 가까운 칸으로 딱딱 붙어도(칸 단위로만 그려도) 초록이다.
@MainActor
@Test
func theDraggedPieceIsDrawnAtTheCursorNotSnappedToASquare() throws {
    let g = drGeometry()
    let e2 = try drSquare("e2")
    // d4·e4·d5·e5 네 칸이 만나는 모서리 — 어느 칸의 가운데도 아니다.
    let corner = CGPoint(x: g.rect(of: try drSquare("e4")).minX, y: g.rect(of: try drSquare("e4")).minY)
    let bitmap = try drBitmap(
        ChessBoardView(position: .standard, geometry: g,
                       lifted: ChessBoardLift(piece: drWhitePawn, from: e2, place: .cursor(corner))),
        name: "drag-between-squares")
    let onCorner = drPieceInk(bitmap, rect: drPointProbe(corner, g, fraction: 0.3))
    print("[끄는 중] 네 칸 모서리 잉크 \(onCorner)px")
    #expect(onCorner > 0, "칸 사이에 둔 커서 자리에 말이 없다 — 말이 칸에 붙어 그려진다")
    // 네 칸의 **가운데**에는 말 몸통이 없다(모서리에 걸친 조각만 있다) — 칸 하나에 통째로 들어앉지 않았다.
    let bounds = try #require(drInkBounds(bitmap, rect: drPointProbe(corner, g, fraction: 2)))
    #expect(abs(bounds.midX - corner.x) < 1.5, "말의 중심이 모서리에서 \(bounds.midX - corner.x)pt 벗어났다")
}

/// 없으면: 커서가 판 밖으로 나가면 말이 통째로 사라져 "어디 갔는지 모른다" 가 되어도 초록이다.
@MainActor
@Test
func theDraggedPieceIsClampedToTheBoardWhenTheCursorLeavesIt() throws {
    let g = drGeometry()
    let e2 = try drSquare("e2")
    let rowY = g.center(of: try drSquare("a4")).y
    // 왼쪽으로 100pt 나갔다 — 말 중심이 x = 0 으로 당겨져 **오른쪽 절반**이 판에 남는다.
    let outside = try drBitmap(
        ChessBoardView(position: .standard, geometry: g,
                       lifted: ChessBoardLift(piece: drWhitePawn, from: e2,
                                              place: .cursor(CGPoint(x: -100, y: rowY)))),
        name: "drag-clamped-left")
    let edge = CGRect(x: 0, y: rowY - g.cell / 2, width: g.cell / 2, height: g.cell)
    let edgeInk = drPieceInk(outside, rect: edge)
    print("[끄는 중] 판 왼쪽 밖 100pt — 가장자리 잉크 \(edgeInk)px")
    #expect(edgeInk > 0, "커서가 판을 나가자 말이 사라졌다")
    #expect(drPieceInk(outside, rect: drProbe(e2, g)) == 0, "판 밖으로 끄는 중인데 출발 칸에 말이 있다")

    // 아래·오른쪽 모서리 밖과 숫자가 아닌 좌표도 판을 깨지 않는다.
    for point in [CGPoint(x: 9_999, y: 9_999), CGPoint(x: CGFloat.nan, y: rowY)] {
        let bitmap = try drBitmap(
            ChessBoardView(position: .standard, geometry: g,
                           lifted: ChessBoardLift(piece: drWhitePawn, from: e2, place: .cursor(point))),
            name: "drag-clamped-odd")
        let inked = drInkedSquares(bitmap, g)
        #expect(!inked.contains("e2"))
        // 나머지 31칸의 말은 전부 그대로 그려진다(판이 깨지지 않았다).
        var others = Set(ChessPosition.standard.pieces.map(\.square.notation))
        others.remove("e2")
        #expect(others.isSubset(of: inked), "빠진 칸: \(others.subtracting(inked).sorted())")
    }
}

// MARK: - ② 놓고 답을 기다리는 중 — 도착 칸에 말이 있다

/// 없으면: 놓은 말이 답을 기다리는 동안 출발 칸에 도로 그려져(되돌아갔다가 다시 간다) 초록이다.
/// 그리고 이 그림은 **답이 온 뒤의 판과 같아야** 한다 — 다르면 답이 오는 순간 말이 한 번 튄다.
@MainActor
@Test
func thePendingPieceStandsOnItsDestinationExactlyLikeTheMoveAlreadyHappened() throws {
    let g = drGeometry()
    let e2 = try drSquare("e2"), e4 = try drSquare("e4")
    let pending = try drBitmap(
        ChessBoardView(position: .standard, geometry: g,
                       lifted: ChessBoardLift(piece: drWhitePawn, from: e2, place: .square(e4))),
        name: "pending-e4")
    #expect(drPieceInk(pending, rect: drProbe(e2, g)) == 0, "답을 기다리는 중인데 출발 칸에 말이 있다")
    #expect(drPieceInk(pending, rect: drProbe(e4, g)) > 0, "답을 기다리는 중인데 도착 칸에 말이 없다")

    let moved = try drBitmap(ChessBoardView(position: try drPosition(drAfterE4FEN), geometry: g), name: "pending-after")
    let same = try drDiff(pending, moved)
    print("[놓은 말] 답을 기다리는 그림 vs 답이 온 뒤의 판: \(same)")
    #expect(same.looksSame, "놓은 말의 자리·크기가 답이 온 뒤와 다르다 — 답이 오는 순간 말이 튄다(\(same))")

    // ★ 기준선: 꼬리표가 없으면 말은 출발 칸에 있다(위 두 줄이 "판이 원래 그렇다" 가 아니다).
    let resting = try drBitmap(ChessBoardView(position: .standard, geometry: g), name: "pending-resting")
    #expect(drPieceInk(resting, rect: drProbe(e2, g)) > 0)
    #expect(drPieceInk(resting, rect: drProbe(e4, g)) == 0)
    let fromResting = try drDiff(pending, resting)
    #expect(fromResting.looksDifferent, "놓은 말의 그림이 멈춘 판과 같다(\(fromResting))")
}

/// 없으면: 잡는 수를 놓고 기다리는 동안 놓은 말이 잡힐 말 **밑에** 깔려 그려져도 초록이다.
@MainActor
@Test
func thePendingCapturerIsDrawnOverThePieceItIsAboutToTake() throws {
    let g = drGeometry()
    let before = try drPosition(drBeforeCaptureFEN)
    let e4 = try drSquare("e4"), d5 = try drSquare("d5")
    let box = g.rect(of: d5)

    let victimOnly = try drBitmap(ChessBoardView(position: before, geometry: g), name: "pending-capture-before")
    let pending = try drBitmap(
        ChessBoardView(position: before, geometry: g,
                       lifted: ChessBoardLift(piece: drWhitePawn, from: e4, place: .square(d5))),
        name: "pending-capture")
    let capturerOnly = try drBitmap(ChessBoardView(position: try drPosition(drAfterCaptureFEN), geometry: g),
                                    name: "pending-capture-after")

    let bright = (alone: drBrightInk(capturerOnly, rect: box), both: drBrightInk(pending, rect: box),
                  victim: drBrightInk(victimOnly, rect: box))
    print("[놓은 말 · 잡기] d5 밝은 잉크 — 잡은 말만 \(bright.alone)px · 둘 다 \(bright.both)px · 잡힐 말만 \(bright.victim)px")
    #expect(bright.alone > 500, "전제: 흰 폰의 밝은 잉크가 \(bright.alone)px 뿐이다")
    #expect(bright.both > bright.alone - 100,
            "밝은 잉크가 \(bright.alone)px → \(bright.both)px — 놓은 말이 잡힐 말 **밑에** 그려졌다")
    #expect(drPieceInk(pending, rect: drProbe(e4, g)) == 0, "놓은 말이 출발 칸에도 그려졌다")
}

// MARK: - ③ 인자 nil = 그림이 안 바뀐다

/// 없으면: 새 인자를 더하면서 멈춘 판의 그림을 바꿔 놓고도 초록이다. 진짜 그물은 V0344~V0346 의 렌더 시험이
/// **한 줄도 안 고쳐진 채** 통과하는 것이고, 여기서는 새 인자를 nil 로 **적어 넘긴** 그림이 안 넘긴 그림과 같은지,
/// 그리고 말이 여전히 32칸인지를 한 번 더 본다.
@MainActor
@Test
func nilDragArgumentsLeaveTheBoardExactlyAsItWas() throws {
    let g = drGeometry()
    let e2 = try drSquare("e2")
    let targets: Set<ChessSquare> = [try drSquare("e3"), try drSquare("e4")]
    let plain = try drBitmap(
        ChessBoardView(position: .standard, geometry: g, lastMove: nil, selected: e2, targets: targets),
        name: "nil-plain")
    let explicit = try drBitmap(
        ChessBoardView(position: .standard, geometry: g, lastMove: nil, selected: e2, targets: targets,
                       flight: nil, lifted: nil, dropTarget: nil),
        name: "nil-explicit")
    let diff = try drDiff(plain, explicit)
    print("[인자 nil] \(diff)")
    #expect(diff.looksSame, "새 인자를 nil 로 넘겼는데 그림이 달라졌다(\(diff))")
    #expect(drInkedSquares(plain, g) == Set(ChessPosition.standard.pieces.map(\.square.notation)))
    #expect(drInkedSquares(plain, g).count == 32)

    // 애니메이션 프레임도 같다: `landed` 가 없는 프레임은 이 값이 생기기 전과 같은 겹침으로 그려진다.
    let after = try drPosition(drAfterE4FEN)
    let moving = ChessFlightFrame.Moving(piece: drWhitePawn, from: e2, to: try drSquare("e4"), t: 0.5)
    let frame = ChessFlightFrame(moving: [moving], leaving: nil, hidden: [try drSquare("e4")])
    let withFrame = try drBitmap(ChessBoardView(position: after, geometry: g, flight: frame), name: "nil-flight")
    let withFrameExplicit = try drBitmap(
        ChessBoardView(position: after, geometry: g, flight: frame, lifted: nil, dropTarget: nil),
        name: "nil-flight-explicit")
    let frameDiff = try drDiff(withFrame, withFrameExplicit)
    #expect(frameDiff.looksSame, "\(frameDiff)")
    #expect(drPieceInk(withFrame, rect: drProbe(try drSquare("e3"), g)) > 0, "전제: 미끄러지는 말이 그려진다")
}

// MARK: - ④ 끄는 말 밑의 도착 칸 — 한 단 더 진하고, 여전히 중간 톤이다

/// 없으면: 도착 칸 덮개가 안 그려지거나, 반대로 **극단 색**으로 그려져 빈 칸이 말로 세어진다(이 저장소의 체스
/// 렌더 검증 전체가 "극단 픽셀 = 말" 에 서 있다).
@MainActor
@Test
func theDropTargetIsVisiblyStrongerButStaysMidTone() throws {
    let g = drGeometry()
    let e2 = try drSquare("e2")
    // e3 은 어두운 칸, e4 는 밝은 칸이다 — 두 바탕 모두에서 잰다.
    for name in ["e3", "e4"] {
        let square = try drSquare(name)
        let targets: Set<ChessSquare> = [try drSquare("e3"), try drSquare("e4")]
        let plain = try drBitmap(
            ChessBoardView(position: .standard, geometry: g, selected: e2, targets: targets),
            name: "target-\(name)-plain")
        let strong = try drBitmap(
            ChessBoardView(position: .standard, geometry: g, selected: e2, targets: targets, dropTarget: square),
            name: "target-\(name)-strong")
        let box = g.rect(of: square).insetBy(dx: 2, dy: 2)
        let range = drChannelRange(strong, rect: box)
        let ink = drPieceInk(strong, rect: box)
        let diff = try drDiff(plain, strong)
        print("[도착 칸 \(name)] 채널 \(range.low)…\(range.high) · 말 잉크 \(ink)px · 덮개 유무 차이 \(diff)")
        #expect(ink == 0, "\(name): 도착 칸 덮개가 극단 색이다 — 빈 칸이 말로 세어진다(\(range.low)…\(range.high))")
        #expect(range.high < 235 && range.low > 55)
        #expect(diff.looksDifferent, "\(name): 도착 칸이 한 단 더 진해지지 않았다(\(diff))")
        // 덮개는 **그 칸만** 바꾼다 — 바뀐 픽셀이 칸 하나(152×152px) 안에 든다.
        #expect(diff.visiblePixels <= 152 * 152, "\(name): 덮개가 칸 밖까지 번졌다(\(diff.visiblePixels)px)")
        #expect(drInkedSquares(strong, g) == Set(ChessPosition.standard.pieces.map(\.square.notation)))
    }
}

// MARK: - ⑤ 끌어 놓아 이미 도착해 있는 말은 맨 위다

/// 없으면: 끌어서 잡은 수에서 밀려나는 잡힌 말이 **잡은 말 위에** 얹혀 그려진다 — 끌어 놓은 말은 날지 않고
/// 멈춘 배치에 있으므로, 순서를 손보지 않으면 잡힌 말(멈춘 말 위에 그린다)이 그 위에 온다.
@MainActor
@Test
func theLandedCapturerStaysOnTopOfThePieceBeingKnockedOut() throws {
    let g = drGeometry()
    let after = try drPosition(drAfterCaptureFEN)
    let d5 = try drSquare("d5")
    let box = g.rect(of: d5)
    // 밀림이 막 시작한 순간: 잡힌 흑 폰이 d5 **그 자리에** 불투명하게 서 있다(겹침이 가장 큰 프레임).
    let leaving = ChessFlightFrame.Leaving(piece: ChessPiece(.black, .pawn), square: d5,
                                           fileOffset: 0, rankOffset: 0, scale: 1, opacity: 1)

    let landed = try drBitmap(
        ChessBoardView(position: after, geometry: g,
                       flight: ChessFlightFrame(moving: [], leaving: leaving, hidden: [], landed: d5)),
        name: "landed-capture")
    // ★ 대조군: 같은 프레임에서 `landed` 만 뺀다 — 잡힌 말이 위에 온다.
    let buried = try drBitmap(
        ChessBoardView(position: after, geometry: g,
                       flight: ChessFlightFrame(moving: [], leaving: leaving, hidden: [])),
        name: "landed-capture-buried")
    let alone = try drBitmap(ChessBoardView(position: after, geometry: g), name: "landed-capture-alone")

    let bright = (alone: drBrightInk(alone, rect: box), landed: drBrightInk(landed, rect: box),
                  buried: drBrightInk(buried, rect: box))
    let dark = (landed: drDarkInk(landed, rect: box), buried: drDarkInk(buried, rect: box))
    print("[도착해 있는 말 · 잡기] d5 밝은 잉크 — 잡은 말만 \(bright.alone)px · landed \(bright.landed)px · landed 없음 \(bright.buried)px")
    print("[도착해 있는 말 · 잡기] d5 어두운 잉크 — landed \(dark.landed)px · landed 없음 \(dark.buried)px")
    #expect(bright.alone > 500)
    #expect(bright.landed > bright.alone - 100,
            "밝은 잉크가 \(bright.alone)px → \(bright.landed)px — 잡힌 말이 끌어 놓은 말 **위에** 그려졌다")
    #expect(bright.buried < bright.alone - 400,
            "전제: `landed` 가 없으면 잡힌 말이 위에 온다(밝은 잉크 \(bright.buried)px) — 대조군이 안 갈렸다")
    // 잡힌 말은 사라진 게 아니다(가장자리에 어두운 잉크가 남는다) — 밀려나며 드러난다.
    let pushed = ChessFlightFrame.Leaving(piece: ChessPiece(.black, .pawn), square: d5,
                                          fileOffset: -0.5, rankOffset: 0.5, scale: 0.8, opacity: 1)
    let later = try drBitmap(
        ChessBoardView(position: after, geometry: g,
                       flight: ChessFlightFrame(moving: [], leaving: pushed, hidden: [], landed: d5)),
        name: "landed-capture-pushed")
    let pushedSpot = CGPoint(x: box.midX - g.cell * 0.5, y: box.midY - g.cell * 0.5)
    #expect(drDarkInk(later, rect: drPointProbe(pushedSpot, g, fraction: 0.4)) > 0, "밀려난 잡힌 말이 안 그려진다")
    #expect(drBrightInk(later, rect: drProbe(d5, g)) > 0, "끌어 놓은 말이 도착 칸에서 사라졌다")
}

/// 없으면: 왕을 끌어 캐슬링했을 때 미끄러지는 룩이 **왕 위를** 지나간다(클릭으로 둔 캐슬링은 왕이 위다).
///
/// 겹침을 색으로 가르려고 지나가는 말을 **흑 룩**으로 둔다 — 실제 캐슬링의 룩은 왕과 같은 색이라 누가 위인지
/// 잉크 수로는 안 갈린다. 뷰는 프레임이 말하는 대로 그릴 뿐이라 그리는 순서를 재는 데는 같은 자리다.
@MainActor
@Test
func theLandedKingStaysOnTopOfTheSlidingRook() throws {
    let g = drGeometry()
    let castled = try drPosition(drCastledFEN)
    let g1 = try drSquare("g1"), h1 = try drSquare("h1"), f1 = try drSquare("f1")
    let box = g.rect(of: g1)
    // 룩이 h1 → f1 의 **한가운데**(= g1, 왕이 선 칸)를 지나는 프레임.
    let passing = ChessFlightFrame.Moving(piece: ChessPiece(.black, .rook), from: h1, to: f1, t: 0.5)

    let onTop = try drBitmap(
        ChessBoardView(position: castled, geometry: g,
                       flight: ChessFlightFrame(moving: [passing], leaving: nil, hidden: [], landed: g1)),
        name: "landed-king-on-top")
    let under = try drBitmap(
        ChessBoardView(position: castled, geometry: g,
                       flight: ChessFlightFrame(moving: [passing], leaving: nil, hidden: [])),
        name: "landed-king-under")
    let alone = try drBitmap(ChessBoardView(position: castled, geometry: g), name: "landed-king-alone")

    let bright = (alone: drBrightInk(alone, rect: box), onTop: drBrightInk(onTop, rect: box),
                  under: drBrightInk(under, rect: box))
    print("[도착해 있는 말 · 캐슬링] g1 밝은 잉크 — 왕만 \(bright.alone)px · landed \(bright.onTop)px · landed 없음 \(bright.under)px")
    #expect(bright.alone > 500)
    #expect(bright.onTop > bright.alone - 100,
            "밝은 잉크가 \(bright.alone)px → \(bright.onTop)px — 룩이 끌어 놓은 왕 **위를** 지나간다")
    #expect(bright.under < bright.alone - 400, "전제: `landed` 가 없으면 룩이 위다 — 대조군이 안 갈렸다")
    // 룩은 사라진 게 아니다 — 왕의 실루엣 밖으로 삐져나온 성벽이 어두운 잉크를 더한다(왕 혼자일 때는 테두리뿐이다).
    let dark = (alone: drDarkInk(alone, rect: box), onTop: drDarkInk(onTop, rect: box))
    print("[도착해 있는 말 · 캐슬링] g1 어두운 잉크 — 왕만 \(dark.alone)px · landed \(dark.onTop)px")
    #expect(dark.onTop > dark.alone + 40, "지나가는 룩이 아예 안 그려졌다(\(dark.alone)px → \(dark.onTop)px)")
}
