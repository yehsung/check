import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.44 체스 말이 **미끄러지는 그림** — 보간 기하(`ChessBoardGeometry`) · 세 겹 그림(`ChessBoardView`) ·
// 세 자리 배선(`ChessPanel`)을 전부 **잉크를 세서** 잰다.
//
// ★ 여기서 재는 것은 "함수를 불렀다" 가 아니다. 모든 단언은 비트맵의 픽셀 수거나 픽셀 좌표다 —
//   `flight` 를 받아 놓고 **안 그리는** 뷰, 도착 칸을 안 빼서 말이 **둘로 보이는** 뷰, 잡힌 말을 그 자리에서
//   **지우는** 뷰가 전부 빨개져야 한다(그게 사용자가 고쳐 달라고 한 증상 셋이다).
//
// ★ 감지기는 V0344 와 같다: 칸·덮개는 전부 중간 톤이고 **말만 극단**(최대 ≥ 235 또는 최소 ≤ 55)이라는 규칙을
//   `ChessBoardView` 가 지키므로 "그 자리에 극단 픽셀이 있는가" 가 곧 "그 자리에 말이 있는가" 다.
//   그래서 날고 있는 말도 **극단 색 그대로** 그려야 한다 — 흐리게 그리면 이 파일의 절반이 공허해진다.
//
// ★ 비트맵 비교는 전부 **허용오차**(잉크 수 · 최대 채널 차)다. 바이트 동치가 없으므로 ImageRenderer 가
//   첫 두 장을 다르게 굽는 병(`CheckRenderSettle` 머리말, 채널당 ≤ 2)에 면역이고, 한 장만 구워도 된다.
//
// PNG 는 `CHECK_SNAPSHOT_DIR/chess-flight/` 에 남는다 — **사람이 직접 열어 본다**(디자인 작업에서 초록
// 테스트는 아무것도 증명하지 않는다).

// MARK: - 국면 픽스처 (FEN 으로 적는다 — 손으로 칸을 놓으면 판이 조용히 달라진다)

/// 초기 배치에서 1.e4 를 둔 뒤. **두 칸** 전진이라 궤적의 가운데가 정확히 e3 칸 중앙에 떨어진다 —
/// "두 칸 사이에 있다" 를 칸 프로브 하나로 잴 수 있는 유일한 거리다.
private let cfStandardFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
private let cfAfterE4FEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"

/// 앙파상 **전**: 백 폰 d5 · 흑 폰 e5(방금 두 칸 왔다) · 왕 둘.
private let cfEnPassantBeforeFEN = "4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1"
/// 앙파상 **후**: 백 폰이 e6 에 서고 **e5 가 비었다**. 잡힌 칸이 도착 칸과 다르므로 멈춘 판의 그 칸 잉크가
/// 0 이다 — 잡힌 말이 보이는지를 "0 대 있음" 으로 가를 수 있는 자리다(보통의 잡기는 도착 칸에 잡은 말이 선다).
private let cfEnPassantAfterFEN = "4k3/8/4P3/8/8/8/8/4K3 b - - 0 1"

/// 보통의 잡기 **전**: 백 폰 d4 · 흑 폰 e5. 잡힌 칸이 **도착 칸과 같아서** 잡힌 말과 잡은 말이
/// 한 칸에서 겹친다 — ⑬이 z 순서를 재는 유일한 꼴이다(앙파상은 두 칸이 달라 안 겹친다).
private let cfPawnCaptureBeforeFEN = "rnbqkbnr/pppp1ppp/8/4p3/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 2"

/// 킹사이드 캐슬링 전·후(왕 e1·룩 h1 → 왕 g1·룩 f1).
private let cfCastleBeforeFEN = "4k3/8/8/8/8/8/8/4K2R w K - 0 1"
private let cfCastleAfterFEN = "4k3/8/8/8/8/8/8/5RK1 b - - 1 1"

/// 흑 나이트 g4 가 f6 로 뛴다. 넘어가는 자리에 선 말을 **룩**으로 둔 까닭(실측 2026-10-06): 나이트의 궤적이
/// 칸 가운데에 가장 가까워지는 지점도 0.447칸(34pt) 떨어져 있어서, 폰처럼 실루엣이 가운데로 몰린 말과는
/// 그림이 거의 안 겹친다(밝은 잉크 손실 18px — "위에 그렸다" 와 "아래에 그렸다" 를 못 가른다).
/// 룩은 받침·몸통·어깨 띠가 칸 폭을 넓게 채워 겹침이 수백 픽셀로 벌어진다.
private let cfKnightBeforeFEN = "4k3/8/8/5RR1/6n1/8/8/4K3 b - - 0 1"
private let cfKnightAfterFEN = "4k3/8/5n2/5RR1/8/8/8/4K3 w - - 1 2"

private func cfPosition(_ fen: String) throws -> ChessPosition {
    try #require(ChessPosition(fen: fen), "FEN 을 못 읽었다: \(fen)")
}

private func cfSquare(_ notation: String) throws -> ChessSquare {
    try #require(ChessSquare(notation))
}

private func cfMove(_ from: String, _ to: String) throws -> ChessMove {
    ChessMove(from: try cfSquare(from), to: try cfSquare(to))
}

/// 그 수의 애니메이션. 기준 시각은 1970 고정이라 어느 기계에서나 같은 숫자가 나온다.
private func cfFlight(_ from: String, _ to: String, before: String, after: String,
                      matchID: String = "match-1", ply: Int = 7) throws -> ChessMoveFlight {
    try #require(ChessMoveFlight.make(move: try cfMove(from, to),
                                     before: try cfPosition(before),
                                     after: try cfPosition(after),
                                     matchID: matchID, ply: ply, generation: 1,
                                     startedAt: Date(timeIntervalSince1970: 1_790_000_000)),
                 "\(from)\(to) 의 애니메이션이 안 만들어졌다 — 수와 국면이 안 맞는다")
}

// MARK: - 시각 (이징의 역함수로 **정확한** 진행도를 집는다)

/// `easeOut` 의 역함수. `easeOut(t) = 1 - (1-t)³` 이므로 `t = 1 - ∛(1-e)` 다.
/// 이걸로 집어야 "t = 0.5" 가 **이징이 들어간 0.5** 가 된다 — `slideDuration` 의 절반을 쓰면 `easeOut(0.5)`
/// = 0.875 라 말이 도착 칸에 거의 닿아 있고, 그러면 "두 칸 사이" 프로브가 도착 칸에서 잉크를 본다.
private func cfRawProgress(forEased eased: Double) -> Double { 1 - cbrt(1 - eased) }

/// 집어 낸 진행도의 허용오차. `Date` 는 2001 기준 초를 double 로 들고 있어 2026년 시각의 ulp 가
/// **1.19e-07초**다(실측). `addingTimeInterval` → `timeIntervalSince` 왕복에서 그만큼이 흔들리고,
/// 0.175~0.20초로 나누면 진행도 오차가 ~6e-07, 이징을 거치면 최대 **6.2e-07** 이 된다(실측값 셋 중 최대).
/// 그래서 "정확히 0.5" 는 이 창 안에서만 말할 수 있다 — 1e-12 로 적으면 단언이 시각의 자리수에 걸려 빨개진다.
private let cfProgressTolerance = 1e-5

/// 미끄러짐의 **이징이 들어간** 진행도가 정확히 `eased` 인 시각.
private func cfSlideMoment(_ flight: ChessMoveFlight, eased: Double) -> Date {
    flight.startedAt.addingTimeInterval(flight.slideDuration * cfRawProgress(forEased: eased))
}

/// 밀림의 **이징이 들어간** 진행도가 정확히 `eased` 인 시각(지연을 지난 뒤부터 센다).
private func cfKnockoutMoment(_ flight: ChessMoveFlight, eased: Double) -> Date {
    flight.startedAt.addingTimeInterval(
        flight.knockoutDelay + flight.knockoutDuration * cfRawProgress(forEased: eased))
}

/// 밀림 **날 진행도** `raw` 의 시각. 오프셋·비율은 `easeOut(raw)` 로 깎이지만 **불투명도는 날 진행도로**
/// 깎이므로(`ChessMoveFlight` 의 ⑤ 주석), 흐려짐을 재는 자리는 이쪽으로 잡아야 뜻이 분명하다.
/// `eased` 로 흐려짐을 겨누면 `easeOut` 을 거꾸로 풀어야 해서 숫자가 읽히지 않는다.
private func cfKnockoutMomentRaw(_ flight: ChessMoveFlight, raw: Double) -> Date {
    flight.startedAt.addingTimeInterval(flight.knockoutDelay + flight.knockoutDuration * raw)
}

// MARK: - 그림 · 좌표

private func cfGeometry(_ orientation: ChessColor = .white) -> ChessBoardGeometry {
    ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: orientation)
}

private enum CFRenderError: Error { case failed }

/// 판 **하나만** 그린 비트맵(scale 2). 창을 통째로 굽지 않으므로 좌표에 창 오프셋이 없고 한 장이 빠르다.
@MainActor
private func cfBoardBitmap(_ position: ChessPosition?, orientation: ChessColor = .white,
                           lastMove: ChessMove? = nil,
                           flight: ChessFlightFrame? = nil) throws -> NSBitmapImageRep {
    let view = ChessBoardView(position: position, geometry: cfGeometry(orientation),
                              lastMove: lastMove, flight: flight)
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw CFRenderError.failed }
    return bitmap
}

private func cfSave(_ bitmap: NSBitmapImageRep, name: String) {
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "chess-flight")
}

/// 그 칸의 **가운데 50% 상자**(판 좌표). V0344 의 `cpSquareProbe` 와 같은 규칙 — 칸 테두리·좌표 글자를 뺀다.
private func cfSquareProbe(_ square: ChessSquare, _ g: ChessBoardGeometry) -> CGRect {
    let box = g.rect(of: square)
    return box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)
}

/// 칸 단위 오프셋의 **기대 화면 오프셋**. ★ `ChessBoardGeometry.offset(fileDelta:rankDelta:)` 를 쓰지 않고
/// 뒤집기 규칙(`column = orientation == .white ? file : 7 - file` · `row = orientation == .white ? 7 - rank : rank`)
/// 에서 직접 센다.
///
/// ★ 왜 두 벌로 세는가(실측 2026-10-06): 프로브를 production 의 `offset(...)` 으로 잡았더니 **뒤집기를
///   지운 뮤테이션에서 프로브가 결함과 같이 움직여** 잉크 단언이 통째로 초록이었다(밀린 쪽 1,378px ·
///   반대쪽 58px — 둘 다 "맞는" 자리에서 재고 있었다). 재는 자리를 재는 대상에서 가져오면 아무것도 안 잰다.
private func cfExpectedShift(fileCells: Double, rankCells: Double, _ g: ChessBoardGeometry) -> CGSize {
    let columnSign: CGFloat = g.orientation == .white ? 1 : -1      // 화면 열이 file 과 같은 방향인가
    let rowSign: CGFloat = g.orientation == .white ? -1 : 1         // 화면 행은 rank 와 반대(백) · 같다(흑)
    return CGSize(width: columnSign * CGFloat(fileCells) * g.cell,
                  height: rowSign * CGFloat(rankCells) * g.cell)
}

/// 한 점을 가운데로 둔 `fraction` 칸 크기 상자. **칸 격자에 얽히지 않은 자리**를 재는 데 쓴다
/// (두 칸 사이 · 밀려난 자리는 어떤 칸의 중앙도 아니다).
private func cfPointProbe(_ point: CGPoint, _ g: ChessBoardGeometry, fraction: CGFloat = 0.5) -> CGRect {
    let side = g.cell * fraction
    return CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
}

// MARK: - 잉크 (V0344 의 private 헬퍼와 같은 모양 — 다른 파일의 것은 private 이라 복사)

/// **말 잉크** — 아주 밝거나(최대 ≥ 235) 아주 어두운(최소 ≤ 55) 픽셀.
private func cfPieceInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    cfCount(bitmap, rect: rect) { r, g, b in max(r, max(g, b)) >= 235 || min(r, min(g, b)) <= 55 }
}

/// **어두운** 쪽만(최소 ≤ 55) — 흑 말의 채움이다. 흰 말 위에 흑 말이 올라갔는지를 가른다.
private func cfDarkInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    cfCount(bitmap, rect: rect) { r, g, b in min(r, min(g, b)) <= 55 }
}

/// **밝은** 쪽만(최대 ≥ 235) — 흰 말의 채움이다. 이 수가 **줄면** 그 자리를 다른 것이 덮었다는 뜻이다.
private func cfBrightInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    cfCount(bitmap, rect: rect) { r, g, b in max(r, max(g, b)) >= 235 }
}

private func cfCount(_ bitmap: NSBitmapImageRep, rect: CGRect,
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

private extension CGRect {
    /// 가운데 점. 이름을 `center` 로 두지 않는 까닭: 테스트 모듈 안에 같은 이름의 확장이 또 생기면
    /// 호출이 모호해져 **이 파일과 무관한 파일**이 빨개진다.
    var cfCenter: CGPoint { CGPoint(x: midX, y: midY) }
}

/// 사각형 안 **말 잉크를 감싸는 상자**(pt). 잉크가 없으면 nil. 밀림이 **얼마나** 갔는지를 재는 자리다.
private func cfInkBounds(_ bitmap: NSBitmapImageRep, rect: CGRect) -> CGRect? {
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

/// 사각형 안에서 두 비트맵의 채널 최대 차(0 이면 한 바이트도 다르지 않다).
private func cfMaxChannelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return 255 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(lhs.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 255 }
    var worst = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let offset = y * bpr + x * spp
            for channel in 0..<min(3, spp) {
                worst = max(worst, abs(Int(a[offset + channel]) - Int(b[offset + channel])))
            }
        }
    }
    return worst
}

/// 말이 선 칸의 표기 집합(가운데 50% 상자에 말 잉크가 있는 칸).
private func cfInkedSquares(_ bitmap: NSBitmapImageRep, _ g: ChessBoardGeometry) -> Set<String> {
    var out: Set<String> = []
    for index in 0..<64 {
        guard let square = ChessSquare(index: index) else { continue }
        if cfPieceInk(bitmap, rect: cfSquareProbe(square, g)) > 0 { out.insert(square.notation) }
    }
    return out
}

// MARK: - ① 순간이동이 아니다 — t = 0.5 에서 말이 두 칸 **사이**에 있다

/// 없으면: `flight` 를 받아 놓고 멈춘 판만 그리는 뷰가 초록으로 통과한다. 이 파일에서 "순간이동이 아니다"를
/// 재는 **단 하나의** 단언이고, 나머지 시험은 전부 이 자리 위에 선다.
@MainActor
@Test
func theSlidingPieceSitsBetweenTheTwoSquaresAtHalfProgress() throws {
    let g = cfGeometry()
    let after = try cfPosition(cfAfterE4FEN)
    let flight = try cfFlight("e2", "e4", before: cfStandardFEN, after: cfAfterE4FEN)
    // 전제: 거리 두 칸이라 궤적의 가운데가 정확히 e3 칸 중앙이다(프로브가 칸 하나로 떨어진다).
    #expect(abs(flight.slideDuration - 0.20) < 1e-12, "두 칸 미끄러짐이 \(flight.slideDuration)s 다 — 0.20s 여야 한다")

    let frame = try #require(flight.frame(now: cfSlideMoment(flight, eased: 0.5)))
    let moving = try #require(frame.moving.first)
    #expect(abs(moving.t - 0.5) < cfProgressTolerance,
            "이징이 들어간 진행도가 \(moving.t) 다 — 0.5 를 집지 못했다")

    let from = try cfSquare("e2"), to = try cfSquare("e4"), middle = try cfSquare("e3")
    let flying = try cfBoardBitmap(after, flight: frame)
    let frozen = try cfBoardBitmap(after)
    cfSave(flying, name: "slide-half")
    cfSave(frozen, name: "slide-frozen")

    let flyingFrom = cfPieceInk(flying, rect: cfSquareProbe(from, g))
    let flyingTo = cfPieceInk(flying, rect: cfSquareProbe(to, g))
    let flyingMiddle = cfPieceInk(flying, rect: cfSquareProbe(middle, g))
    print("[미끄러짐 t=0.5] 출발 e2 \(flyingFrom)px · 도착 e4 \(flyingTo)px · 가운데 e3 \(flyingMiddle)px")

    #expect(flyingFrom == 0, "t=0.5 인데 출발 칸에 말이 남아 있다(\(flyingFrom)px)")
    #expect(flyingTo == 0, "t=0.5 인데 도착 칸에 말이 벌써 있다(\(flyingTo)px) — 순간이동이다")
    #expect(flyingMiddle > 0, "두 칸 가운데에 아무것도 없다 — 말이 궤적 위에 안 그려졌다")

    // ★ 기준선이 갈린다: 멈춘 판은 **정확히 반대**다(도착 칸에 있고 가운데가 비어 있다).
    //   안 갈리면 위 세 줄은 "판이 통째로 비었다" 로도 초록이 된다.
    #expect(cfPieceInk(frozen, rect: cfSquareProbe(to, g)) > 0, "멈춘 판의 도착 칸이 비었다 — 전제가 깨졌다")
    #expect(cfPieceInk(frozen, rect: cfSquareProbe(middle, g)) == 0, "멈춘 판의 가운데 칸에 말이 있다 — 국면이 틀렸다")
    #expect(cfPieceInk(frozen, rect: cfSquareProbe(from, g)) == 0)
}

// MARK: - ② 두 끝 — t = 0 은 출발 칸, t = 1 과 애니메이션 없음은 도착 칸

/// 없으면: 보간이 두 끝에서 멈춘 판과 어긋나도(0 에서 벌써 반쯤 가 있거나 1 에서 못 닿거나) 초록이다 —
/// 그러면 수가 시작할 때와 끝날 때 말이 한 번씩 **튄다**.
@MainActor
@Test
func theSlideStartsOnTheOriginAndLandsExactlyOnTheDestination() throws {
    let g = cfGeometry()
    let after = try cfPosition(cfAfterE4FEN)
    let flight = try cfFlight("e2", "e4", before: cfStandardFEN, after: cfAfterE4FEN)
    let from = try cfSquare("e2"), to = try cfSquare("e4")

    let start = try #require(flight.frame(now: flight.startedAt))
    #expect(start.moving.first?.t == 0, "시작 프레임의 t 가 0 이 아니다")
    let startBitmap = try cfBoardBitmap(after, flight: start)
    cfSave(startBitmap, name: "slide-t0")
    #expect(cfPieceInk(startBitmap, rect: cfSquareProbe(from, g)) > 0, "t=0 인데 출발 칸이 비었다")
    #expect(cfPieceInk(startBitmap, rect: cfSquareProbe(to, g)) == 0, "t=0 인데 도착 칸에 말이 있다")

    // 끝에 **거의** 닿은 프레임. 정확히 `startedAt + duration` 을 쓰지 않는 까닭: Date 왕복 오차(위 ★)가
    // 그 시각의 경과를 0.20000004768초로 만들어 `isFinished` 의 열린 경계(`>`)에서 이미 끝난 뒤로 떨어진다
    // (실측 — 0.175초짜리는 반대로 0.17499995 가 되어 안 떨어진다. 자리수에 따라 갈리므로 쓰지 않는다).
    // 경계 자체의 계약은 모델 시험(`theNilFrameAndTheFinishedFlagAgreeEverywhere`)이 잰다.
    let end = try #require(flight.frame(now: flight.startedAt.addingTimeInterval(flight.duration - 0.0005)),
                           "끝에 닿기 직전 프레임이 없다 — 마지막 한 장이 안 그려진다")
    let endT = try #require(end.moving.first).t
    #expect(1 - endT < 1e-6, "마지막 프레임의 t 가 \(endT) 다 — 1 에 닿지 못했다")
    let endBitmap = try cfBoardBitmap(after, flight: end)
    cfSave(endBitmap, name: "slide-t1")
    #expect(cfPieceInk(endBitmap, rect: cfSquareProbe(to, g)) > 0, "t=1 인데 도착 칸이 비었다")
    #expect(cfPieceInk(endBitmap, rect: cfSquareProbe(from, g)) == 0, "t=1 인데 출발 칸에 말이 남아 있다")

    // t=1 의 그림은 멈춘 판과 **같은 자리**다(보간이 도착 칸에 정확히 닿는다 — 어긋나면 마지막에 튄다).
    let frozen = try cfBoardBitmap(after)
    let difference = cfMaxChannelDifference(endBitmap, frozen, rect: g.rect(of: to))
    print("[미끄러짐 t=1] 도착 칸 채널 최대 차 = \(difference)")
    #expect(difference <= 2, "t=1 의 말이 멈춘 판의 자리와 \(difference) 만큼 어긋났다")
    #expect(flight.isFinished(now: flight.startedAt.addingTimeInterval(flight.duration + 0.001)))
}

// MARK: - ③ 말이 둘로 보이지 않는다

/// 없으면: `hidden` 을 빼먹어 도착 칸에도 말이 그려지는 뷰가 초록이다 — 사용자에게는 **같은 말이 두 개**로
/// 보이고(캐슬링이면 넷), 그게 "따라가기가 힘들다" 의 가장 심한 꼴이다.
@MainActor
@Test
func theBoardNeverShowsTheSamePieceTwiceWhileItFlies() throws {
    let g = cfGeometry()
    let after = try cfPosition(cfAfterE4FEN)
    let flight = try cfFlight("e2", "e4", before: cfStandardFEN, after: cfAfterE4FEN)
    let frame = try #require(flight.frame(now: cfSlideMoment(flight, eased: 0.5)))
    let destination = try cfSquare("e4")
    #expect(frame.hidden == [destination], "숨긴 칸이 도착 칸 하나가 아니다: \(frame.hidden.map(\.notation))")

    let flying = try cfBoardBitmap(after, flight: frame)
    let frozen = try cfBoardBitmap(after)
    let flyingSquares = cfInkedSquares(flying, g)
    let frozenSquares = cfInkedSquares(frozen, g)
    print("[둘로 안 보인다] 날 때 \(flyingSquares.count)칸 · 멈출 때 \(frozenSquares.count)칸")
    #expect(frozenSquares.count == 32, "멈춘 판이 \(frozenSquares.count)칸이다 — 전제가 깨졌다")
    #expect(flyingSquares.count == 32,
            "날고 있는데 말이 \(flyingSquares.count)칸에 서 있다 — 도착 칸을 안 뺐다(둘로 보인다)")

    // ★ 기준선이 갈린다: `hidden` 을 비운 같은 프레임은 **33칸**이다. 안 갈리면 위 단언은
    //   "`hidden` 을 아예 안 쓰는 뷰" 를 못 잡는다(그 뷰에서도 멈춘 판은 32칸이다).
    let leaky = ChessFlightFrame(moving: frame.moving, leaving: frame.leaving, hidden: [])
    let leakyBitmap = try cfBoardBitmap(after, flight: leaky)
    cfSave(leakyBitmap, name: "slide-hidden-missing")
    let leakySquares = cfInkedSquares(leakyBitmap, g)
    print("[둘로 안 보인다] 숨김을 비우면 \(leakySquares.count)칸: 더 생긴 칸 = \(leakySquares.subtracting(flyingSquares).sorted())")
    #expect(leakySquares.count == 33, "숨김을 비웠는데 칸 수가 안 늘었다 — 이 감지기가 아무것도 안 잰다")
    #expect(leakySquares.subtracting(flyingSquares) == ["e4"])
}

// MARK: - ④ 잡힌 말이 **보인다** (밀려난 자리에 잉크가 있다)

/// 없으면: 잡힌 말을 아예 안 그리는 뷰가 초록이다 — 그게 "말이 갑자기 사라진다" 는 그 증상이다.
/// 앙파상으로 재는 까닭: 잡힌 칸이 도착 칸과 **달라서** 멈춘 판의 그 칸 잉크가 0 이다(보통의 잡기는
/// 도착 칸에 잡은 말이 서서 기준선이 안 갈린다).
@MainActor
@Test
func theCapturedPieceIsDrawnPushedOutOfItsSquare() throws {
    let g = cfGeometry()
    let after = try cfPosition(cfEnPassantAfterFEN)
    let flight = try cfFlight("d5", "e6", before: cfEnPassantBeforeFEN, after: cfEnPassantAfterFEN)
    let knockout = try #require(flight.knockout)
    let victim = try cfSquare("e5")
    #expect(knockout.square == victim,
            "잡힌 칸이 \(knockout.square.notation) 다 — 앙파상은 **도착 칸이 아니다**")
    #expect(knockout.pushFile == 1 && knockout.pushRank == 1,
            "밀림 방향이 (\(knockout.pushFile), \(knockout.pushRank)) 다 — 잡은 말이 온 방향(+1,+1)을 안 이었다")

    // 불투명도가 **아직 정확히 1** 인 지점이다. 흐려짐은 진행도 0.35 부터 시작하므로(`knockoutFadeStart`)
    // 0.30 에서는 분수가 1.077 로 잘려 1 이 되고, 그래도 벌써 0.165칸(12.54pt) 밀려나 있다 —
    // "먼저 밀려나고 나중에 흐려진다" 를 **밝기 손실 없이** 잴 수 있는 창이 그 구간이다.
    // ★ 경계값 0.35 를 쓰지 않는 까닭: Date 왕복 오차가 0.35000027 을 만들어 불투명도가 0.99999958 로
    //   내려간다(실측). 경계의 정확한 값은 모델 시험이 잰다.
    let pushedFrame = try #require(flight.frame(now: cfKnockoutMoment(flight, eased: 0.30)))
    let leaving = try #require(pushedFrame.leaving)
    #expect(leaving.opacity == 1, "밀림 0.30 에서 벌써 흐려졌다(불투명도 \(leaving.opacity))")
    #expect(abs(leaving.fileOffset - 0.55 * 0.30) < cfProgressTolerance
            && abs(leaving.rankOffset - 0.55 * 0.30) < cfProgressTolerance,
            "오프셋이 (\(leaving.fileOffset), \(leaving.rankOffset)) 칸이다 — 0.165 칸이어야 한다")

    // 기대 오프셋은 **두 벌로** 센다(위 `cfExpectedShift` ★) — 프로브를 재는 대상에서 가져오면 안 된다.
    let expected = cfExpectedShift(fileCells: leaving.fileOffset, rankCells: leaving.rankOffset, g)
    #expect(abs(expected.width - 12.54) < 0.01 && abs(expected.height + 12.54) < 0.01,
            "백 판의 기대 오프셋이 \(expected) 다 — (+12.54, −12.54)pt 여야 한다")
    let shift = g.offset(fileDelta: leaving.fileOffset, rankDelta: leaving.rankOffset)
    #expect(abs(shift.width - expected.width) < 0.01 && abs(shift.height - expected.height) < 0.01,
            "기하가 낸 화면 오프셋 \(shift) 가 기대 \(expected) 와 다르다")
    let home = g.center(of: knockout.square)
    let pushed = CGPoint(x: home.x + expected.width, y: home.y + expected.height)
    let probe = cfPointProbe(pushed, g, fraction: 0.4)

    let flying = try cfBoardBitmap(after, flight: pushedFrame)
    let frozen = try cfBoardBitmap(after)
    // ★ 프레임을 **먼저 받아 둔다**. 인자 자리에 `try #require(...)` 를 바로 쓰면 `flight:` 가 옵셔널이라
    //   매크로의 `T` 가 `ChessFlightFrame?` 로 묶여 **한 겹만 벗기고 nil 을 그대로 통과시킨다**
    //   (컴파일러도 "never equals nil" 로 경고한다). 그러면 프레임이 nil 인 회귀에서 `atStart` 가 멈춘 판이 되어
    //   아래 `pushedInk > beforePushInk` 가 0 과 비교하며 공허하게 초록이 된다.
    let startFrame = try #require(flight.frame(now: flight.startedAt),
                                  "시작 시각의 프레임이 nil 이다 — 밀리기 전 기준선을 못 잡는다")
    let atStart = try cfBoardBitmap(after, flight: startFrame)
    cfSave(flying, name: "knockout-pushed")
    cfSave(frozen, name: "knockout-frozen")

    let pushedInk = cfPieceInk(flying, rect: probe)
    let frozenInk = cfPieceInk(frozen, rect: probe)
    let beforePushInk = cfPieceInk(atStart, rect: probe)
    print("[잡힌 말] 밀려난 자리: 밀린 뒤 \(pushedInk)px · 밀리기 전 \(beforePushInk)px · 멈춘 판 \(frozenInk)px")

    // ★ 기준선이 갈린다: 멈춘 판에는 그 자리에 **아무것도 없다**(앙파상으로 비워진 칸이다).
    #expect(frozenInk == 0, "멈춘 판의 그 자리에 벌써 잉크가 \(frozenInk)px 있다 — 기준선이 안 갈린다")
    #expect(pushedInk > 500, "밀려난 자리에 잡힌 말이 \(pushedInk)px 뿐이다 — 안 그려졌다")
    // 그리고 **실제로 밀렸다**: 같은 상자를 밀리기 전(진행도 0)에 재면 더 적다(말이 아직 칸 가운데에 있다).
    #expect(pushedInk > beforePushInk,
            "밀린 뒤(\(pushedInk)px)가 밀리기 전(\(beforePushInk)px)보다 많지 않다 — 밀림이 그림에 안 들어갔다")
}

// MARK: - ⑤ 먼저 밀려나고 **나중에** 흐려진다

/// 없으면: 오프셋·비율과 불투명도를 **같이** 깎는 뷰가 초록이다 — 그러면 잡힌 말은 그 자리에서 그냥 사라진
/// 것과 구분되지 않는다(사용자가 고쳐 달라고 한 바로 그 증상).
///
/// 재는 상자는 e5 칸을 밀림 방향으로 0.55칸 넓힌 자리다. 그 안에서 **빠지는 말만** 재려고 날고 있는 말을
/// 뺀 프레임을 쓴다(숫자는 모델의 `frame(now:)` 가 낸 그대로다 — 손으로 다시 계산하지 않는다).
@MainActor
@Test
func theCapturedPieceSlidesOutFirstAndFadesAfterwards() throws {
    let g = cfGeometry()
    let after = try cfPosition(cfEnPassantAfterFEN)
    let flight = try cfFlight("d5", "e6", before: cfEnPassantBeforeFEN, after: cfEnPassantAfterFEN)
    let square = try #require(flight.knockout).square
    let home = g.rect(of: square)
    // 밀림의 끝(0.55칸)까지 담는 상자. 오른쪽·위로만 넓힌다(밀림 방향이 (+file, +rank) = 화면 (+x, −y)).
    let region = CGRect(x: home.minX, y: home.minY - g.cell * 0.55,
                        width: home.width + g.cell * 0.55, height: home.height + g.cell * 0.55)

    var inks: [(eased: Double, ink: Int, center: CGPoint?)] = []
    for eased in [0.0, 0.2, 0.4, 0.6, 0.8] {
        let real = try #require(flight.frame(now: cfKnockoutMoment(flight, eased: eased)))
        // 날고 있는 말을 뺀 같은 프레임 — 상자 안에 **빠지는 말 하나만** 남는다.
        let onlyLeaving = ChessFlightFrame(moving: [], leaving: real.leaving, hidden: real.hidden)
        let bitmap = try cfBoardBitmap(after, flight: onlyLeaving)
        if eased == 0.0 || eased == 0.4 || eased == 0.8 {
            cfSave(bitmap, name: "knockout-\(Int(eased * 100))")
        }
        let bounds = cfInkBounds(bitmap, rect: region)
        inks.append((eased, cfPieceInk(bitmap, rect: region),
                     bounds.map { CGPoint(x: $0.midX, y: $0.midY) }))
    }
    for row in inks {
        print("[밀림] 진행도 \(row.eased): 잉크 \(row.ink)px · 가운데 \(row.center.map { "(\($0.x), \($0.y))" } ?? "없음")")
    }

    // 단조 감소 — 비율과 불투명도가 둘 다 진행도에 따라 줄기만 하므로 중간에 늘어날 수 있는 길이 없다.
    for (earlier, later) in zip(inks, inks.dropFirst()) {
        #expect(earlier.ink > later.ink,
                "진행도 \(earlier.eased)(\(earlier.ink)px) 가 \(later.eased)(\(later.ink)px) 보다 많지 않다 — 단조가 깨졌다")
    }
    // ★ **끝에서는** 잉크가 0 이다 — 흐려짐이 그림에 안 들어갔으면 비율만 줄어 끝까지 잉크가 남는다.
    //   ★ 날 진행도 **0.999** 로 잰다(1.0 이 아니다): 1.0 은 `startedAt + duration` 과 같은 시각이고
    //   `isFinished` 의 경계가 열려 있어(`>`) 부동소수 반올림 한 틱에 따라 프레임이 nil 로 떨어진다.
    //   0.999 의 불투명도는 (1 − 0.999) / 0.65 = **0.0015** 라 뜻은 똑같다.
    let nearEnd = try #require(flight.frame(now: cfKnockoutMomentRaw(flight, raw: 0.999)))
    let nearEndLeaving = try #require(nearEnd.leaving)
    #expect(nearEndLeaving.opacity < 0.01, "전제: 끝 직전에는 거의 투명하다(지금 \(nearEndLeaving.opacity))")
    let endInk = cfPieceInk(try cfBoardBitmap(
        after, flight: ChessFlightFrame(moving: [], leaving: nearEnd.leaving, hidden: nearEnd.hidden)),
        rect: region)
    #expect(endInk == 0, "끝까지 가도 잡힌 말이 \(endInk)px 남아 있다 — 흐려짐이 그림에 안 들어갔다")
    // ★ 그리고 **0.8 에서는 아직 또렷하다**(날 진행도 0.4152 → 불투명도 0.8997). 이 줄이 이 시험의 핵심이다 —
    //   불투명도를 `easeOut` 으로 깎았던 첫 판은 여기서 불투명도가 **0.0123** 이라 잉크가 0 이었다. 그러면
    //   잡힌 말은 밀려 나가기도 전에 사라져서 "갑자기 말이 사라진다" 로 되돌아간다(그게 고치려던 증상이다).
    #expect(inks[4].ink > 0,
            "밀림 0.8 에서 잡힌 말이 벌써 0px 다 — 밀려 나가기 전에 사라진다")
    #expect(inks[0].ink > 2_000, "밀림 시작에 잡힌 말이 \(inks[0].ink)px 뿐이다 — 전제가 깨졌다")

    // ★ 그리고 **먼저 밀려난다**: 불투명도가 1 로 남아 있는 지점에서 잉크의 가운데가 밀림 방향으로 옮겨져 있다.
    let still = try #require(flight.frame(now: flight.startedAt))
    let pushed = try #require(flight.frame(now: cfKnockoutMoment(flight, eased: 0.30)))
    let pushedLeaving = try #require(pushed.leaving)
    #expect(pushedLeaving.opacity == 1, "전제: 0.30 에서는 아직 불투명도가 1 이다")
    let stillCenter = try #require(cfInkBounds(try cfBoardBitmap(
        after, flight: ChessFlightFrame(moving: [], leaving: still.leaving, hidden: still.hidden)),
        rect: region)).cfCenter
    let pushedCenter = try #require(cfInkBounds(try cfBoardBitmap(
        after, flight: ChessFlightFrame(moving: [], leaving: pushed.leaving, hidden: pushed.hidden)),
        rect: region)).cfCenter
    let moved = CGSize(width: pushedCenter.x - stillCenter.x, height: pushedCenter.y - stillCenter.y)
    print("[밀림] 불투명도 1 인 채로 옮겨 간 거리 = \(moved)")
    // 허용오차 4pt: 잉크 상자는 2px 격자에서 잡히고(±0.25pt) 비율이 줄며 가장자리 픽셀의 문턱이 바뀐다
    // (실측 오차 ≤ 0.9pt). 12.54pt 의 밀림과는 세 배 넘게 벌어져 있어 "안 밀렸다" 와 구별된다.
    #expect(abs(moved.width - 12.54) < 4 && abs(moved.height + 12.54) < 4,
            "흐려지기 전에 옮겨 간 거리가 \(moved) 다 — (+12.54, −12.54)pt 여야 한다(먼저 밀려나지 않았다)")
}

// MARK: - ⑥ 흑으로 두는 판은 **화면상 반대쪽**으로 간다

/// 없으면: 뒤집기를 잊은 기하가 초록이다 — 흑으로 두는 사람만 말이 엉뚱한 쪽으로 미끄러지고 잡힌 말이
/// 잡은 말 쪽으로 **되밀려 들어온다**(판 좌표를 그대로 화면에 쓰면 그렇게 된다).
@MainActor
@Test
func theBlackSideBoardSlidesAndPushesTheOppositeWayOnScreen() throws {
    let white = cfGeometry(.white), black = cfGeometry(.black)
    let after = try cfPosition(cfAfterE4FEN)
    let flight = try cfFlight("e2", "e4", before: cfStandardFEN, after: cfAfterE4FEN)
    let frame = try #require(flight.frame(now: cfSlideMoment(flight, eased: 0.5)))
    let moving = try #require(frame.moving.first)

    // 두 방향에서 궤적의 가운데가 가는 **화면 좌표**. 판을 뒤집으면 이 점이 판 가운데를 지나 맞은편으로 간다.
    // ★ 보간 함수가 아니라 **가운데 칸의 중앙**으로 잡는다(e2→e4 는 두 칸이라 t=0.5 가 정확히 e3 중앙이다) —
    //   프로브를 `rect(from:to:t:)` 로 잡으면 그 함수가 깨져도 프로브가 같이 움직여 아무것도 안 잰다.
    let middle = try cfSquare("e3")
    let whiteSpot = white.center(of: middle), blackSpot = black.center(of: middle)
    for g in [white, black] {
        let interpolated = g.rect(from: moving.from, to: moving.to, t: moving.t).cfCenter
        let expected = g.center(of: middle)
        #expect(abs(interpolated.x - expected.x) < 0.01 && abs(interpolated.y - expected.y) < 0.01,
                "\(g.orientation) 판의 보간 가운데가 \(interpolated) 다 — e3 중앙 \(expected) 여야 한다")
    }
    print("[흑 판] 궤적 가운데: 백 \(whiteSpot) · 흑 \(blackSpot)")
    #expect(abs(whiteSpot.x + blackSpot.x - white.side) < 0.01
            && abs(whiteSpot.y + blackSpot.y - white.side) < 0.01,
            "두 방향의 궤적 가운데가 판 가운데를 기준으로 마주보지 않는다(백 \(whiteSpot) · 흑 \(blackSpot))")

    let whiteBitmap = try cfBoardBitmap(after, orientation: .white, flight: frame)
    let blackBitmap = try cfBoardBitmap(after, orientation: .black, flight: frame)
    cfSave(blackBitmap, name: "slide-half-black")

    // 각 비트맵은 **자기 자리에만** 잉크가 있고 상대의 자리는 비어 있다(둘 다 그 자리의 멈춘 판은 빈 칸이다).
    let whiteProbe = cfPointProbe(whiteSpot, white, fraction: 0.5)
    let blackProbe = cfPointProbe(blackSpot, black, fraction: 0.5)
    let whiteAtWhite = cfPieceInk(whiteBitmap, rect: whiteProbe)
    let whiteAtBlack = cfPieceInk(whiteBitmap, rect: blackProbe)
    let blackAtBlack = cfPieceInk(blackBitmap, rect: blackProbe)
    let blackAtWhite = cfPieceInk(blackBitmap, rect: whiteProbe)
    print("[흑 판] 백 비트맵: 백자리 \(whiteAtWhite)px · 흑자리 \(whiteAtBlack)px / 흑 비트맵: 흑자리 \(blackAtBlack)px · 백자리 \(blackAtWhite)px")
    #expect(whiteAtWhite > 0 && whiteAtBlack == 0, "백 판의 말이 흑 판 자리에도 있다")
    #expect(blackAtBlack > 0 && blackAtWhite == 0, "흑 판의 말이 백 판 자리로 갔다 — 뒤집기가 안 들어갔다")

    let difference = cfMaxChannelDifference(whiteBitmap, blackBitmap, rect: CGRect(x: 0, y: 0, width: white.side, height: white.side))
    print("[흑 판] 두 비트맵 채널 최대 차 = \(difference)")
    #expect(difference > 60, "두 방향의 판이 거의 같은 그림이다(최대 차 \(difference))")

    // 잡힌 말이 **밀리는 방향**도 뒤집힌다. 같은 판 좌표 오프셋이 두 방향에서 화면 부호가 반대여야 한다.
    let capture = try cfFlight("d5", "e6", before: cfEnPassantBeforeFEN, after: cfEnPassantAfterFEN)
    let captureAfter = try cfPosition(cfEnPassantAfterFEN)
    let pushedFrame = try #require(capture.frame(now: cfKnockoutMoment(capture, eased: 0.30)))
    let leaving = try #require(pushedFrame.leaving)
    let blackExpected = cfExpectedShift(fileCells: leaving.fileOffset, rankCells: leaving.rankOffset, black)
    #expect(abs(blackExpected.width + 12.54) < 0.01 && abs(blackExpected.height - 12.54) < 0.01,
            "흑 판의 기대 밀림 오프셋이 \(blackExpected) 다 — (−12.54, +12.54)pt 여야 한다")
    let blackShift = black.offset(fileDelta: leaving.fileOffset, rankDelta: leaving.rankOffset)
    #expect(abs(blackShift.width - blackExpected.width) < 0.01
            && abs(blackShift.height - blackExpected.height) < 0.01,
            "흑 판 기하가 낸 오프셋 \(blackShift) 가 기대 \(blackExpected) 와 다르다 — 뒤집기가 안 들어갔다")

    // ★ 프로브는 **기대값**으로 잡는다. production 의 `offset(...)` 으로 잡으면 뒤집기를 지운 결함에서
    //   프로브가 결함과 같이 움직여 둘 다 "맞는" 자리를 재게 된다(실측 — 그때 이 두 줄이 초록이었다).
    let blackHome = black.center(of: leaving.square)
    let blackPushed = CGPoint(x: blackHome.x + blackExpected.width, y: blackHome.y + blackExpected.height)
    let blackMirror = CGPoint(x: blackHome.x - blackExpected.width, y: blackHome.y - blackExpected.height)
    let capturedBitmap = try cfBoardBitmap(captureAfter, orientation: .black, flight: pushedFrame)
    cfSave(capturedBitmap, name: "knockout-pushed-black")
    let pushedInk = cfPieceInk(capturedBitmap, rect: cfPointProbe(blackPushed, black, fraction: 0.4))
    let mirrorInk = cfPieceInk(capturedBitmap, rect: cfPointProbe(blackMirror, black, fraction: 0.4))
    print("[흑 판] 잡힌 말: 밀린 쪽 \(pushedInk)px · 반대쪽 \(mirrorInk)px")
    #expect(pushedInk > 500, "흑 판에서 잡힌 말이 밀린 쪽에 \(pushedInk)px 뿐이다")
    #expect(pushedInk > mirrorInk * 2,
            "흑 판에서 밀린 쪽(\(pushedInk)px)과 반대쪽(\(mirrorInk)px)이 비슷하다 — 방향이 안 뒤집혔다")
}

// MARK: - ⑦ 캐슬링은 **둘이 같이** 움직인다

/// 없으면: 왕만 미끄러뜨리고 룩은 순간이동하는 파생·뷰가 초록이다(캐슬링은 수가 왕의 두 칸 이동으로만
/// 적히므로 룩을 잊기 가장 쉬운 자리다).
@MainActor
@Test
func castlingSlidesBothTheKingAndTheRook() throws {
    let g = cfGeometry()
    let after = try cfPosition(cfCastleAfterFEN)
    let flight = try cfFlight("e1", "g1", before: cfCastleBeforeFEN, after: cfCastleAfterFEN)
    #expect(flight.sliders.count == 2, "캐슬링에 미끄러지는 말이 \(flight.sliders.count)개다 — 왕·룩 둘이어야 한다")
    #expect(flight.sliders.last?.piece.kind == .king, "왕이 배열 마지막이 아니다 — 룩이 왕 위에 그려진다")

    let frame = try #require(flight.frame(now: cfSlideMoment(flight, eased: 0.5)))
    #expect(frame.moving.count == 2)
    let rookTo = try cfSquare("f1"), kingTo = try cfSquare("g1")
    #expect(frame.hidden == Set([rookTo, kingTo]),
            "숨긴 칸이 \(frame.hidden.map(\.notation).sorted()) 다 — 도착 칸 둘이어야 한다")

    let flying = try cfBoardBitmap(after, flight: frame)
    cfSave(flying, name: "castle-half")
    // 궤적의 가운데: 왕 e1→g1 은 f1 중앙, 룩 h1→f1 은 g1 중앙에 떨어진다(서로 스쳐 지난다).
    let kingSpot = cfSquareProbe(rookTo, g)        // 왕의 궤적 가운데 = 룩의 도착 칸
    let rookSpot = cfSquareProbe(kingTo, g)        // 룩의 궤적 가운데 = 왕의 도착 칸
    let kingInk = cfPieceInk(flying, rect: kingSpot)
    let rookInk = cfPieceInk(flying, rect: rookSpot)
    print("[캐슬링] 왕 자리 \(kingInk)px · 룩 자리 \(rookInk)px")
    #expect(kingInk > 0 && rookInk > 0, "두 궤적 중 한쪽에 말이 없다(왕 \(kingInk)px · 룩 \(rookInk)px)")
    // 둘 다 **출발 칸을 떠났다**: e1·h1 은 멈춘 판에서도 비어 있고 지금도 비어 있어야 한다.
    let kingFrom = try cfSquare("e1"), rookFrom = try cfSquare("h1")
    #expect(cfPieceInk(flying, rect: cfSquareProbe(kingFrom, g)) == 0, "왕이 출발 칸에 남아 있다")
    #expect(cfPieceInk(flying, rect: cfSquareProbe(rookFrom, g)) == 0, "룩이 출발 칸에 남아 있다")

    // ★ 기준선이 갈린다: **룩 조각만 뺀** 같은 프레임은 룩 궤적 자리가 통째로 빈다(도착 칸 f1 은 숨겨지지
    //   않으니 멈춘 룩이 그려지고, g1 은 숨겨져 아무것도 없다). 즉 위 `rookInk > 0` 은 룩을 잊은 파생을 잡는다.
    let king = try #require(frame.moving.last)
    let kingOnly = ChessFlightFrame(moving: [king], leaving: frame.leaving, hidden: [king.to])
    let kingOnlyBitmap = try cfBoardBitmap(after, flight: kingOnly)
    cfSave(kingOnlyBitmap, name: "castle-king-only")
    let kingOnlyRookInk = cfPieceInk(kingOnlyBitmap, rect: rookSpot)
    print("[캐슬링] 룩을 잊으면 룩 자리 \(kingOnlyRookInk)px")
    #expect(kingOnlyRookInk == 0, "룩 조각을 뺐는데도 룩 자리에 잉크가 \(kingOnlyRookInk)px 있다 — 감지기가 안 잰다")
}

// MARK: - ⑧ 나이트는 말을 **뛰어넘는다**(지나가는 말 위에 그려진다)

/// 없으면: 날고 있는 말을 멈춘 말 **아래**에 그리는 뷰가 초록이다 — 나이트가 지나가는 칸의 말 뒤로 숨어
/// 궤적이 끊긴 것처럼 보인다(두 칸을 건너뛰는 나이트에서 가장 두드러진다).
///
/// 흑 나이트가 **흰** 룩 위를 지나게 꾸몄다. 겹친 자리에서 밝은 잉크(흰 말의 채움)가 **줄고** 어두운
/// 잉크(흑 말의 채움)가 **늘면** 나이트가 그 위에 그려진 것이다 — 멈춘 말을 나중에 그리면(= 나이트가 아래)
/// 흰 말의 픽셀이 그대로라 밝은 잉크가 **한 픽셀도 안 줄어든다**.
///
/// ★ 재는 지점이 **0.5 가 아니다**(실측 2026-10-06). 나이트 수는 성분 하나가 홀수라 궤적의 가운데가 언제나
///   두 칸이 맞닿은 금 위에 떨어지고, 거기서는 양쪽 말과 거의 안 겹친다. 궤적이 칸 가운데에 가장 가까워지는
///   지점은 `t = 0.4`(남은 거리 0.447칸)다 — 거기서 나이트의 가운데가 g5 칸 **안쪽**에 들어온다.
@MainActor
@Test
func theFlyingKnightIsDrawnOnTopOfThePiecesItJumpsOver() throws {
    let g = cfGeometry()
    let after = try cfPosition(cfKnightAfterFEN)
    let flight = try cfFlight("g4", "f6", before: cfKnightBeforeFEN, after: cfKnightAfterFEN)
    let frame = try #require(flight.frame(now: cfSlideMoment(flight, eased: 0.4)))
    let moving = try #require(frame.moving.first)
    #expect(moving.piece == ChessPiece(.black, .knight))

    // 궤적 위 자리를 **칸 중앙 둘 사이의 선형 보간**으로 직접 센다(production 보간 함수와 두 벌).
    let origin = g.center(of: moving.from), target = g.center(of: moving.to)
    let spot = CGPoint(x: origin.x + (target.x - origin.x) * moving.t,
                       y: origin.y + (target.y - origin.y) * moving.t)
    let interpolated = g.rect(from: moving.from, to: moving.to, t: moving.t).cfCenter
    #expect(abs(interpolated.x - spot.x) < 0.01 && abs(interpolated.y - spot.y) < 0.01,
            "보간 자리 \(interpolated) 가 직접 센 \(spot) 와 다르다")
    let passed = try cfSquare("g5")
    let cell = g.rect(of: passed)
    // 전제 둘: 나이트의 가운데가 지나가는 칸 **안**이고, 그 칸에는 멈춘 판에서 흰 폰이 서 있다.
    // (둘 중 하나가 깨지면 아래 밝기 손실 단언이 공허해진다.)
    #expect(cell.contains(spot), "나이트의 가운데 \(spot) 가 g5 칸 \(cell) 밖이다")
    #expect(after[passed] == ChessPiece(.white, .rook), "g5 에 흰 룩이 없다 — 국면이 틀렸다")
    #expect(!frame.hidden.contains(passed), "지나가는 칸이 숨김에 들어 있다 — 폰이 안 그려진다")

    let flying = try cfBoardBitmap(after, flight: frame)
    let frozen = try cfBoardBitmap(after)
    cfSave(flying, name: "knight-jump")
    cfSave(frozen, name: "knight-frozen")

    let flyingDark = cfDarkInk(flying, rect: cell), frozenDark = cfDarkInk(frozen, rect: cell)
    let flyingBright = cfBrightInk(flying, rect: cell), frozenBright = cfBrightInk(frozen, rect: cell)
    print("[나이트] g5 칸: 어두운 잉크 \(frozenDark)px → \(flyingDark)px · 밝은 잉크 \(frozenBright)px → \(flyingBright)px")
    // 실측(2026-10-06): 어두운 잉크 3,368 → 6,335px(+2,967). 흑 나이트의 몸통이 그 칸에 들어왔다는 뜻이다.
    #expect(flyingDark > frozenDark + 1_500,
            "지나가는 칸에 흑 나이트가 안 왔다(어두운 잉크 \(frozenDark)px → \(flyingDark)px)")
    // ★ 이 줄이 z 순서를 잰다: 흰 룩의 밝은 채움이 **덮여서** 줄어야 한다.
    //   나이트를 멈춘 말보다 먼저 그리면(= 아래) 룩의 픽셀이 한 장도 안 바뀌어 이 손실이 **정확히 0** 이 된다.
    //   실측 손실은 214px 다(3,928 → 3,714) — 궤적이 칸 가운데에 0.447칸까지만 다가가고 말은 칸의 86%만
    //   채우므로 겹침이 이 정도다. 문턱 100px 은 그 실측과 "아래에 그렸다"(0px) 사이에 둔 것이다.
    #expect(frozenBright - flyingBright > 100,
            "흰 룩의 밝은 잉크가 \(frozenBright)px → \(flyingBright)px(손실 \(frozenBright - flyingBright)px)다 — 나이트가 룩 **아래**에 그려졌다")

    // 지나가는 칸의 그림이 멈춘 판과 **다르다**(그 칸 가운데 잉크로도 갈린다).
    // ★ `t = 0.4` 에서는 나이트가 f5 쪽으로는 안 들어간다(실측 최대 차 0) — 그래서 f5 는 찍어만 두고
    //   단언은 g5 하나로 좁힌다. "두 칸 다 바뀐다" 로 적으면 영원히 빨간 단언이 된다.
    let g5Probe = cfSquareProbe(passed, g)
    let g5Difference = cfMaxChannelDifference(flying, frozen, rect: g5Probe)
    let f5Probe = cfSquareProbe(try cfSquare("f5"), g)
    print("[나이트] g5 칸 가운데 채널 최대 차 = \(g5Difference) · 잉크 \(cfPieceInk(frozen, rect: g5Probe))px → \(cfPieceInk(flying, rect: g5Probe))px")
    print("[나이트] f5 칸 가운데 채널 최대 차 = \(cfMaxChannelDifference(flying, frozen, rect: f5Probe))(참고 — 그 칸까지는 안 간다)")
    #expect(g5Difference > 60, "g5 칸 가운데가 나이트가 지나가도 그대로다(최대 차 \(g5Difference))")
}

// MARK: - ⑨ 기본값 nil 이면 그림이 안 바뀐다

/// 없으면: `flight` 를 더하면서 멈춘 판의 그림을 바꿔 놓고도 초록이다(기존 32칸 단언이 V0344 에 있지만
/// 그 파일은 창을 통째로 굽는다 — 판 뷰 하나만 그린 그림도 32칸인지는 여기서만 잰다).
@MainActor
@Test
func theBoardWithoutAFlightStillDrawsExactlyThirtyTwoPieces() throws {
    let g = cfGeometry()
    let bitmap = try cfBoardBitmap(.standard)
    cfSave(bitmap, name: "initial-no-flight")
    let inked = cfInkedSquares(bitmap, g)
    print("[애니메이션 없음] 말이 선 칸 \(inked.count)개")
    #expect(inked.count == 32, "애니메이션 없는 초기 배치가 \(inked.count)칸이다 — 32칸이어야 한다")
    for (square, _) in ChessPosition.standard.pieces {
        #expect(inked.contains(square.notation), "\(square.notation) 에 말이 안 그려졌다")
    }
    #expect(inked.count == ChessPosition.standard.pieces.count)
}

// MARK: - ⑩ TimelineView 로 감싼 뒤에도 **제스처가 산다**

/// 없으면: 판을 `TimelineView` 안으로 넣으면서 탭·호버·접근성이 죽어도 렌더 시험은 전부 초록이다
/// (그림은 그대로이기 때문이다). 애니메이션을 얻고 입력을 잃는 것이 이 작업에서 가장 쉬운 사고다.
@MainActor
@Test
func theBoardTapStillReachesTheStoreAfterWrappingInATimeline() async throws {
    let g = cfGeometry(.white)
    let store = ChessStore()
    store.pollStepSeconds = 3_600
    store.phase = .playing
    let position = ChessPosition.standard
    store.match = ChessMatchState(
        id: "match-1", stake: 10, myColor: .white,
        opponent: ChessUser(id: "00000000-0000-0000-0000-000000000011", displayName: "민수",
                            avatarURL: nil, characterID: "fox", isWorking: true, isCapable: true,
                            inMatch: true, center: nil),
        fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        position: position, plyCount: 0, turn: .white, lastMove: nil, moves: [],
        clock: ChessServerClock(whiteMsLeft: 300_000, blackMsLeft: 300_000, incrementMs: 3_000,
                                turnStartedAt: nil, running: .white),
        isInCheck: false, legalMoves: ChessRules.legalMoves(in: position),
        isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil,
        drawOfferBy: nil, drawOfferedByMe: false)

    // 뷰가 하는 일 그대로: 화면 좌표 → 칸 → `store.tap`. 좌표 변환도 함께 재므로 기하가 틀어지면 빨개진다.
    let e2 = try cfSquare("e2")
    let tapped = try #require(g.square(at: g.center(of: e2)))
    #expect(tapped == e2, "칸 중앙을 눌렀는데 \(tapped.notation) 이 나온다")
    await store.tap(tapped)
    #expect(store.selection?.from == e2, "탭이 스토어에 안 닿았다(고른 칸 \(store.selection?.from.notation ?? "없음"))")
    let expectedTargets = Set([try cfSquare("e3"), try cfSquare("e4")])
    #expect(store.selection?.targets == expectedTargets,
            "e2 폰의 갈 수 있는 칸이 \(store.selection?.targets.map(\.notation).sorted() ?? []) 다")

    // 그리고 **소스에서** 입력이 TimelineView 밖에 남아 있는지 본다 — 안으로 들어가면 틱마다 제스처가
    // 새로 달려 눌림이 떨어지는데, 그건 렌더 비트맵으로는 한 픽셀도 안 보인다.
    let panel = cfStripped(try CheckCoreSourceLayout.joinedSplitSource("ChessPanel.swift"))
    #expect(panel.contains("} .contentShape(Rectangle()) .onContinuousHover"),
            "판의 입력 수식어가 TimelineView 안으로 들어갔다 — 탭·호버가 틱마다 다시 달린다")
    #expect(panel.contains(".gesture( SpatialTapGesture()"), "판의 탭 제스처가 없어졌다")
    #expect(panel.contains(".onChange(of: match.id) { _, _ in hovered = nil }"), "판 바뀜에 호버를 안 지운다")
    #expect(panel.contains(".onChange(of: match.plyCount) { _, _ in hovered = nil }"), "수가 바뀔 때 호버를 안 지운다")
    #expect(cfCount(".accessibilityLabel(ChessText.boardAccessibility(", in: panel) == 2,
            "판 접근성 라벨이 \(cfCount(".accessibilityLabel(ChessText.boardAccessibility(", in: panel))곳이다 — 대국·관전 둘이어야 한다")
}

// MARK: - ⑪ 배선 — 세 자리 전부에서 애니메이션이 판에 닿는다

/// 없으면: 모델·뷰가 다 멀쩡한데 **한 자리만** 배선해서 "어떤 때는 되고 어떤 때는 안 된다" 가 된다.
/// 사용자에게는 재현 조건이 안 보여 찾는 데만 한참 걸리는 꼴이다.
///
/// ★ 어느 프레임을 재는가: 애니메이션의 시작 시각을 **먼 미래**로 두면 `TimelineView` 가 주는 어떤 실제
///   시각에서도 진행도가 정확히 0 이다. 그 t=0 그림은 **수를 두기 전의 배치**(잡힌 말이 아직 서 있고
///   움직인 말이 아직 출발 칸에 있다)이고, 멈춘 판으로는 절대 나올 수 없는 그림이다 — 배선이 끊기면
///   곧바로 빨개진다. (중간 프레임을 창 통째로 집을 수는 없다: `TimelineView` 가 넘기는 시각은 실제
///   벽시계라 렌더가 언제 끝나는지에 달려 있다. 중간 프레임의 그림은 ①~⑧ 이 판 뷰에서 잰다.)
///
/// ★ `beginFlight` 뒤에 **await 를 두지 않는다**: 그 문이 띄우는 거두기 Task 는 MainActor 를 기다리므로
///   동기 렌더 사이에는 못 끼어든다. 중간에 await 를 하나 넣으면 0.3초짜리 Task 가 값을 지워 빨개진다.
@MainActor
@Test
func allThreeBoardSitesReceiveTheFlightFromTheStore() throws {
    for site in CFSite.allCases {
        let g = cfGeometry()
        let before = try cfPosition(cfEnPassantBeforeFEN)
        let after = try cfPosition(cfEnPassantAfterFEN)
        let move = try cfMove("d5", "e6")
        let from = try cfSquare("d5"), to = try cfSquare("e6"), victim = try cfSquare("e5")

        // 멈춘 기준선 먼저(애니메이션 없이 같은 화면).
        let frozenStore = try cfSiteStore(site, position: after, move: move)
        let frozen = try cfPanelBitmap(frozenStore)
        cfSave(frozen, name: "site-\(site.label)-frozen")
        #expect(frozenStore.flight == nil, "기준선에 애니메이션이 서 있다")

        // 같은 화면 + 먼 미래에 시작하는 애니메이션 → t=0 = **수를 두기 전**의 그림.
        let store = try cfSiteStore(site, position: after, move: move)
        store.isWindowVisible = true
        store.clock = { Date(timeIntervalSince1970: 4_000_000_000) }
        store.beginFlight(matchID: site.matchID, previousMatchID: site.matchID, previousPly: 6,
                          previousPosition: before, nextPly: 7, nextPosition: after, move: move)
        let flight = try #require(store.flight, "\(site.label): 깔때기가 애니메이션을 안 세웠다")
        #expect(flight.matchID == site.matchID)
        let flying = try cfPanelBitmap(store)
        cfSave(flying, name: "site-\(site.label)-t0")

        let fromInk = (frozen: cfPieceInk(frozen, rect: cfPanelProbe(from, g)),
                       flying: cfPieceInk(flying, rect: cfPanelProbe(from, g)))
        let toInk = (frozen: cfPieceInk(frozen, rect: cfPanelProbe(to, g)),
                     flying: cfPieceInk(flying, rect: cfPanelProbe(to, g)))
        let victimInk = (frozen: cfPieceInk(frozen, rect: cfPanelProbe(victim, g)),
                         flying: cfPieceInk(flying, rect: cfPanelProbe(victim, g)))
        print("[\(site.label)] 출발 d5 \(fromInk.frozen)→\(fromInk.flying)px · 도착 e6 \(toInk.frozen)→\(toInk.flying)px · 잡힌 e5 \(victimInk.frozen)→\(victimInk.flying)px")

        // 세 칸이 **셋 다** 멈춘 판과 다르다 = 이 화면이 받은 것이 멈춘 국면이 아니라 프레임이다.
        #expect(fromInk.frozen == 0 && fromInk.flying > 0,
                "\(site.label): 움직인 말이 출발 칸에 안 섰다(\(fromInk.frozen)→\(fromInk.flying)px) — 배선이 끊겼다")
        #expect(toInk.frozen > 0 && toInk.flying == 0,
                "\(site.label): 도착 칸이 벌써 차 있다(\(toInk.frozen)→\(toInk.flying)px) — 도착 칸을 안 뺐다")
        #expect(victimInk.frozen == 0 && victimInk.flying > 0,
                "\(site.label): 잡힌 말이 안 그려졌다(\(victimInk.frozen)→\(victimInk.flying)px)")

        // ★ 다른 판의 애니메이션은 새지 않는다 — 같은 스토어가 세 화면을 먹이므로 이 거르기가 필요하다.
        let alien = try cfSiteStore(site, position: after, move: move)
        alien.isWindowVisible = true
        alien.clock = { Date(timeIntervalSince1970: 4_000_000_000) }
        alien.beginFlight(matchID: "other-match", previousMatchID: "other-match", previousPly: 6,
                          previousPosition: before, nextPly: 7, nextPosition: after, move: move)
        #expect(alien.flight?.matchID == "other-match", "전제: 다른 판의 애니메이션이 섰다")
        let alienBitmap = try cfPanelBitmap(alien)
        let difference = cfMaxChannelDifference(alienBitmap, frozen, rect: cfPanelBoardRect)
        print("[\(site.label)] 다른 판 애니메이션일 때 판 채널 최대 차 = \(difference)")
        #expect(difference <= 2,
                "\(site.label): 다른 판(other-match)의 애니메이션이 이 판에 새어 그림이 \(difference) 만큼 바뀌었다")
        store.clearFlight()
        alien.clearFlight()
    }
}

/// 배선이 **배터리 계약**을 지키는지. 틱이 도는지는 비트맵으로 볼 수 없으니(ImageRenderer 는 한 장만
/// 굽는다) 소스에서 잰다 — `paused:` 가 거른 값을 보는지, 간격이 주사율에서 오는지, 자리가 셋인지.
@Test
func allThreeBoardSitesPauseTheTimelineWhenNothingIsMoving() throws {
    let panel = cfStripped(try CheckCoreSourceLayout.joinedSplitSource("ChessPanel.swift"))
    #expect(cfCount("paused: flight == nil", in: panel) == 3,
            "`paused: flight == nil` 이 \(cfCount("paused: flight == nil", in: panel))곳이다 — 대국·관전·결과 셋이어야 한다")
    // ★ 거른 값(`flight`)을 봐야 한다. `store.flight != nil` 로 두면 **다른 판**의 애니메이션 때문에
    //   이 화면이 60fps 로 깨어 있는다(그림은 하나도 안 바뀌는 채로).
    #expect(!panel.contains("paused: store.flight == nil"), "paused 가 거르지 않은 값을 본다")
    #expect(cfCount("MiniGameFrameRate.minimumInterval(", in: panel) == 3,
            "틱 간격을 주사율에서 안 가져오는 자리가 있다 — 1/60 을 박으면 75Hz·144Hz 에서 저더가 돌아온다")
    #expect(cfCount("MiniGameFrameRateMonitor.shared.refreshHz", in: panel) == 3)
    #expect(cfCount("flight?.frame(now: context.date)", in: panel) == 3,
            "그릴 한 장을 모델에서 안 받아 오는 자리가 있다")
    // 거른 값이 **세 자리 전부** 자기 화면의 판 id 로 걸러진다(대국·결과는 `match.id`, 관전은 `watch.id`).
    #expect(cfCount("$0.matchID ==", in: panel) == 2, "관전·결과의 거르기가 둘이 아니다")
    #expect(panel.contains("flight.matchID == match.id"), "대국 판의 거르기가 없다")
    #expect(panel.contains("$0.matchID == watch.id"), "관전 판의 거르기가 없다")
}

// MARK: - ⑫ 흐려지는 잡힌 말이 **날고 있는 말까지** 흐리지 않는다

/// 없으면: 불투명도를 `GraphicsContext` **사본이 아니라 원본**에 걸어도 48건이 전부 초록이다(실측 2026-10-06).
/// `GraphicsContext` 는 값이라 원본에 걸면 그 뒤에 그리는 ⑤c 까지 같이 흐려진다 — 그러면 **잡는 수마다
/// 잡은 말이 도착하는 순간 같이 투명해져** 사라진 것처럼 보인다. 고치려던 증상이 잡힌 말에서 잡은 말로 옮겨간다.
///
/// 왜 기존 그물이 못 무나: 잡힘을 재는 시험들은 전부 `moving: []` 로 **날고 있는 말을 뺀** 프레임을 넘기고,
/// 날고 있는 말을 재는 시험들은 잡기가 없는 수(e2e4 · 나이트)를 쓴다. 그래서 "불투명도가 1 아래인 잡힌 말"과
/// "날고 있는 말"이 **한 장에 같이 있는 프레임**을 아무도 그리지 않는다. 그 한 장이 이 시험이다.
///
/// 앙파상으로 재는 까닭: 잡힌 칸(e5)과 도착 칸(e6)이 **다른 칸**이라 도착 칸의 잉크가 날고 있는 말의 것뿐이다.
@MainActor
@Test
func theFadingCapturedPieceDoesNotFadeTheFlyingPieceWithIt() throws {
    let g = cfGeometry()
    let after = try cfPosition(cfEnPassantAfterFEN)
    let flight = try cfFlight("d5", "e6", before: cfEnPassantBeforeFEN, after: cfEnPassantAfterFEN)
    let destination = try cfSquare("e6")

    // 잡힌 말이 **뚜렷하게 흐려진** 지점. 불투명도는 날 진행도로 깎이므로 날 진행도 0.85 로 겨눈다
    // (→ (1 − 0.85) / (1 − 0.35) = **0.2308**). 그때 미끄러짐은 이미 끝에 닿아 날고 있는 폰이 도착 칸
    // 위에 있다 — 두 겹이 한 장에 겹치는 구간이 여기다(0.07875 + 0.85 × 0.22 = 0.266초 > 미끄러짐 0.175초).
    let frame = try #require(flight.frame(now: cfKnockoutMomentRaw(flight, raw: 0.85)))
    let leaving = try #require(frame.leaving)
    let moving = try #require(frame.moving.first)
    #expect(leaving.opacity < 0.5, "전제: 이 지점에서 잡힌 말이 흐려져 있어야 한다(지금 \(leaving.opacity))")
    #expect(1 - moving.t < 1e-3, "전제: 이 지점에서 날고 있는 말이 도착 칸에 닿아 있어야 한다(t = \(moving.t))")

    // 같은 프레임에서 **잡힌 말만** 뺀 것. 도착 칸의 잉크는 두 그림에서 같아야 한다 —
    // 잡힌 말은 e5 쪽에 있고 도착 칸을 한 픽셀도 건드리지 않는다.
    let withoutVictim = ChessFlightFrame(moving: frame.moving, leaving: nil, hidden: frame.hidden)
    let both = try cfBoardBitmap(after, flight: frame)
    let flierOnly = try cfBoardBitmap(after, flight: withoutVictim)
    cfSave(both, name: "knockout-fade-with-flier")

    let probe = cfSquareProbe(destination, g)
    let flierInk = cfPieceInk(flierOnly, rect: probe)
    let bothInk = cfPieceInk(both, rect: probe)
    print("[흐려짐 격리] 도착 칸 e6: 잡힌 말 없이 \(flierInk)px · 같이 그리면 \(bothInk)px")
    #expect(flierInk > 500, "전제: 날고 있는 말이 도착 칸에 \(flierInk)px 뿐이다 — 재는 자리가 비었다")
    // 여유 50px: 잉크는 문턱(≥235) 셈이라 ImageRenderer 가 첫 두 장을 다르게 굽는 ±2 채널 잡음이
    // 가장자리 픽셀 몇 개를 넘나들게 한다(실측 손실 0px). 원본에 걸린 결함은 3,056 → 0px 이라
    // 이 여유와 3천 픽셀 떨어져 있다.
    #expect(bothInk > flierInk - 50,
            "흐려지는 잡힌 말이 날고 있는 말의 잉크를 \(flierInk - bothInk)px 깎았다 — 불투명도가 사본이 아니라 원본에 걸렸다")

    // ★ 기준선이 갈린다: 두 그림은 **어딘가는 달라야** 한다(잡힌 말을 아예 안 그리면 위 두 줄은 공허하다).
    let whole = CGRect(x: 0, y: 0, width: g.side, height: g.side)
    let anyDifference = cfMaxChannelDifference(both, flierOnly, rect: whole)
    print("[흐려짐 격리] 판 전체 채널 최대 차 = \(anyDifference)")
    #expect(anyDifference > 20,
            "잡힌 말을 더해도 그림이 \(anyDifference) 밖에 안 바뀐다 — 흐려진 잡힌 말이 아예 안 그려졌다")
}

// MARK: - ⑬ 잡힌 말은 잡은 말 **아래**에 그려진다

/// 없으면: ⑤b(빠지는 말)를 ⑤c(날고 있는 말) **뒤로** 옮겨도 50건이 전부 초록이다(실측 2026-10-06 — 뮤테이션
/// m35 가 한 건도 안 물렸다). 그러면 보통의 잡기에서 **죽어 가는 말이 도착하는 말을 덮어** 잡은 말이 자기
/// 무덤 뒤로 숨는다 — 무엇이 그 칸에 남는지가 0.2초 동안 안 보인다.
///
/// 왜 기존 그물이 못 무나: 잡힘을 재는 시험들은 `moving: []` 로 날고 있는 말을 빼고, 앙파상으로 재는 ④⑤·⑫는
/// 잡힌 칸과 도착 칸이 **달라서** 두 겹이 애초에 겹치지 않는다. 겹치는 것은 **보통의 잡기**뿐이다.
///
/// 감지기는 ⑧(나이트)과 같다: 흰 말의 **밝은 잉크**가 줄면 그 위에 어두운 것이 올라온 것이다.
@MainActor
@Test
func theCapturedPieceIsDrawnUnderTheCapturerNotOverIt() throws {
    let g = cfGeometry()
    let before = try cfPosition(cfPawnCaptureBeforeFEN)
    let move = try cfMove("d4", "e5")
    // `after` 를 엔진으로 만든다 — 손으로 적은 FEN 은 "수와 국면이 맞는가" 단언을 공허하게 만든다.
    let after = try #require(ChessRules.apply(move, to: before), "합법 수가 아니다: d4e5")
    let flight = try #require(ChessMoveFlight.make(move: move, before: before, after: after,
                                                   matchID: "match-1", ply: 3, generation: 1,
                                                   startedAt: Date(timeIntervalSince1970: 1_790_000_000)),
                              "애니메이션이 안 만들어졌다")
    let destination = try cfSquare("e5")
    #expect(flight.knockout?.square == destination, "보통의 잡기는 잡힌 칸 = 도착 칸이다 — 그래서 두 겹이 겹친다")

    // 밀림 진행도 0.15: 불투명도는 **정확히 1**(흐려짐은 0.35 부터)이고 잡은 말은 궤적의 88% 까지 왔다 —
    // 두 말이 도착 칸에서 가장 많이 겹치는 창이다.
    let frame = try #require(flight.frame(now: cfKnockoutMoment(flight, eased: 0.15)))
    let leaving = try #require(frame.leaving)
    let moving = try #require(frame.moving.first)
    #expect(leaving.opacity == 1, "전제: 이 지점에서 잡힌 말이 아직 또렷해야 한다(지금 \(leaving.opacity))")
    #expect(moving.t > 0.8, "전제: 잡은 말이 도착 칸에 들어와야 한다(t = \(moving.t))")
    #expect(moving.piece == ChessPiece(.white, .pawn))
    #expect(leaving.piece == ChessPiece(.black, .pawn), "감지기가 색으로 가르므로 두 말의 색이 달라야 한다")

    let both = try cfBoardBitmap(after, flight: frame)
    let capturerOnly = try cfBoardBitmap(after, flight: ChessFlightFrame(
        moving: frame.moving, leaving: nil, hidden: frame.hidden))
    let victimOnly = try cfBoardBitmap(after, flight: ChessFlightFrame(
        moving: [], leaving: leaving, hidden: frame.hidden))
    cfSave(both, name: "capture-overlap-both")

    let probe = cfSquareProbe(destination, g)
    let bothBright = cfBrightInk(both, rect: probe)
    let capturerBright = cfBrightInk(capturerOnly, rect: probe)
    let victimDark = cfDarkInk(victimOnly, rect: probe)
    let bothDark = cfDarkInk(both, rect: probe)
    print("[겹침] 도착 칸 e5: 밝은 잉크 잡은말만 \(capturerBright)px → 같이 \(bothBright)px · "
          + "어두운 잉크 잡힌말만 \(victimDark)px → 같이 \(bothDark)px")

    // 전제 둘(기준선이 갈린다): 두 말이 **각각** 그 칸에 뚜렷하게 그려진다.
    #expect(capturerBright > 500, "전제: 잡은 말의 밝은 잉크가 \(capturerBright)px 뿐이다")
    #expect(victimDark > 500, "전제: 잡힌 말의 어두운 잉크가 \(victimDark)px 뿐이다")

    // ★ 무는 자리: 잡은 말의 밝은 채움이 **거의 그대로** 남아야 한다(위에 그려졌으므로).
    //   순서를 뒤집으면 어두운 폰이 그 자리를 덮어 이 수가 통째로 무너진다.
    #expect(bothBright > capturerBright - 100,
            "밝은 잉크가 \(capturerBright)px → \(bothBright)px(손실 \(capturerBright - bothBright)px) — 잡힌 말이 잡은 말 **위**에 그려졌다")
    // 그리고 잡힌 말은 사라진 게 아니다 — 겹치지 않는 둘레에 어두운 잉크가 남는다.
    #expect(bothDark > 0, "두 겹을 같이 그렸는데 어두운 잉크가 없다 — 잡힌 말이 아예 안 그려졌다")
}

// MARK: - 배선 시험용 자리 · 스토어

private enum CFSite: CaseIterable {
    case playing, spectate, result

    var label: String {
        switch self {
        case .playing: return "대국"
        case .spectate: return "관전"
        case .result: return "결과"
        }
    }

    /// 애니메이션이 붙는 판 id. 관전은 로비 카드의 id 를 그대로 쓴다.
    var matchID: String {
        switch self {
        case .playing, .result: return "match-1"
        case .spectate: return "live-1"
        }
    }
}

private let cfOpponent = ChessUser(id: "00000000-0000-0000-0000-000000000011", displayName: "민수",
                                   avatarURL: nil, characterID: "fox", isWorking: true,
                                   isCapable: true, inMatch: true, center: nil)
private let cfPeer = ChessUser(id: "00000000-0000-0000-0000-000000000012", displayName: "준호",
                               avatarURL: nil, characterID: "squirrel", isWorking: true,
                               isCapable: true, inMatch: true, center: nil)
private let cfMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

/// `turnStartedAt` 을 nil 로 둔다 — 보간이 꺼져 남은 시간이 `now` 와 무관해지고 렌더가 결정적이 된다.
private let cfFrozenClock = ChessServerClock(whiteMsLeft: 274_000, blackMsLeft: 192_000,
                                             incrementMs: 3_000, turnStartedAt: nil, running: .white)

@MainActor
private func cfSiteStore(_ site: CFSite, position: ChessPosition, move: ChessMove) throws -> ChessStore {
    let store = ChessStore()
    store.pollStepSeconds = 3_600
    store.hasLoadedLobby = true
    store.hasLoadedRanking = true
    store.spectatorFeaturesEnabled = true
    store.rubyBalance = 42
    store.record = ChessRecord(wins: 7, losses: 3, draws: 1)
    switch site {
    case .playing, .result:
        store.phase = site == .result ? .result : .playing
        store.match = ChessMatchState(
            id: site.matchID, stake: 10, myColor: .white, opponent: cfOpponent,
            fen: cfEnPassantAfterFEN, position: position, plyCount: 7, turn: site == .result ? nil : .black,
            lastMove: move, moves: [], clock: cfFrozenClock, isInCheck: false,
            legalMoves: site == .result ? [] : ChessRules.legalMoves(in: position),
            isFinished: site == .result, outcome: site == .result ? .won : nil,
            endReason: site == .result ? .checkmate : nil, rubyDelta: site == .result ? 10 : nil,
            drawOfferBy: nil, drawOfferedByMe: false)
    case .spectate:
        store.phase = .lobby
        var watch = ChessSpectateState(id: site.matchID, faces: [cfOpponent, cfPeer], stake: 5)
        watch.white = cfOpponent
        watch.black = cfPeer
        watch.fen = cfEnPassantAfterFEN
        watch.position = position
        watch.plyCount = 7
        watch.appliedSeq = 7
        watch.lastMove = move
        watch.turn = .black
        watch.clock = cfFrozenClock
        watch.startedAt = Date(timeIntervalSince1970: 1_790_000_000)
        store.spectating = watch
    }
    return store
}

@MainActor
private func cfPanelBitmap(_ store: ChessStore) throws -> NSBitmapImageRep {
    let view = ChessPanel(store: store, me: { cfMe }, clipsOverflowInsteadOfScroll: true)
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw CFRenderError.failed }
    return bitmap
}

/// 창 안 판의 왼쪽 위(레이아웃 상수에서만 뽑는다 — V0344 의 `cpBoardOrigin` 과 같은 규칙).
private var cfPanelBoardOrigin: CGPoint {
    CGPoint(x: ChessWindowLayout.contentPadding,
            y: ChessWindowLayout.contentPadding + ChessWindowLayout.headerHeight + ChessWindowLayout.headerSpacing)
}

private var cfPanelBoardRect: CGRect {
    CGRect(origin: cfPanelBoardOrigin,
           size: CGSize(width: ChessWindowLayout.boardSide, height: ChessWindowLayout.boardSide))
}

/// 창 좌표로 옮긴 칸 가운데 50% 상자.
private func cfPanelProbe(_ square: ChessSquare, _ g: ChessBoardGeometry) -> CGRect {
    cfSquareProbe(square, g).offsetBy(dx: cfPanelBoardOrigin.x, dy: cfPanelBoardOrigin.y)
}

// MARK: - 소스 헬퍼 (다른 파일의 것은 private 이라 복사 — V0344ChessWindowTests 와 같은 규칙)

/// 주석을 걷어내고 공백을 한 칸으로 접는다. **안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다.**
private func cfStripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// 걷어낸 소스에서 그 글자가 몇 번 나오는가(겹치지 않게 센다).
private func cfCount(_ needle: String, in source: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var rest = Substring(source)
    while let found = rest.range(of: needle) {
        count += 1
        rest = rest[found.upperBound...]
    }
    return count
}
