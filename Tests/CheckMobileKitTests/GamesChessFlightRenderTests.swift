import AppKit
import CheckCore
import CheckRenderTestSupport
import Foundation
import SwiftUI
import Testing
@testable import CheckMobileKit

// 폰 체스 판 — **말이 움직이는 그림**을 잉크를 세서 잰다(기하 `ChessPhoneBoardGeometry` · 세 겹 그림
// `GamesChessBoardCanvas` · 프레임 루프 `GamesChessBoard`).
//
// ★ 여기서 재는 것은 "함수를 불렀다" 가 아니다. 거의 모든 단언은 비트맵의 픽셀 수거나 픽셀 좌표다 —
//   `flight` 를 받아 놓고 **안 그리는** 판, 도착 칸을 안 빼서 말이 **둘로 보이는** 판, 잡힌 말을 그 자리에서
//   **지우는** 판이 전부 빨개져야 한다(그게 사용자가 고쳐 달라고 한 증상 셋이다).
//
// ★ 왜 맥 스위트가 폰 판을 굽을 수 있나: `GamesChessBoardCanvas`·`GamesChessBoard` 에 `#if os(iOS)` 가 **없다**
//   (SwiftUI `Canvas`·`TimelineView` 뿐이고 `GamesDisplay` 만 iOS 분기 한 줄이다). `CheckMobileKit` 의 절반이
//   iOS 전용이라 그 안에 뒀으면 그림을 재는 길이 통째로 사라진다(위젯 머리 줄에서 쓴 것과 같은 수법).
//
// ★ 감지기: **칸·덮개는 중간 톤 · 말만 극단**(최대 ≥ 235 또는 최소 ≤ 55)이라는 규칙을 캔버스가 지키므로
//   "그 자리에 극단 픽셀이 있는가" 가 곧 "그 자리에 말이 있는가" 다.

@MainActor
@Suite("폰 체스 판 — 말 이동·잡힘 애니메이션(그림으로 잰다)")
struct GamesChessFlightRenderTests {

    // MARK: - 국면 픽스처 (FEN 으로 적는다 — 손으로 칸을 놓으면 판이 조용히 달라진다)

    /// 초기 배치.
    static let standardFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    /// 1.e4 를 둔 뒤. **두 칸** 전진이라 궤적의 가운데가 정확히 e3 칸 중앙에 떨어진다 —
    /// "두 칸 사이에 있다" 를 칸 프로브 하나로 잴 수 있는 유일한 거리다.
    static let afterE4FEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
    /// 앙파상 **전**: 백 폰 d5 · 흑 폰 e5(방금 두 칸 왔다) · 왕 둘.
    static let enPassantBeforeFEN = "4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1"
    /// 앙파상 **후**: 백 폰이 e6 에 서고 **e5 가 비었다**. 잡힌 칸이 도착 칸과 달라서 두 겹이 안 겹친다.
    static let enPassantAfterFEN = "4k3/8/4P3/8/8/8/8/4K3 b - - 0 1"
    /// 보통의 잡기 **전**: 백 폰 d4 · 흑 폰 e5. 잡힌 칸이 **도착 칸과 같아서** 두 겹이 한 칸에서 겹친다.
    static let pawnCaptureBeforeFEN = "rnbqkbnr/pppp1ppp/8/4p3/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 2"

    /// 기준 시각 고정 — 어느 기계에서나 같은 숫자가 나온다.
    static let epoch = Date(timeIntervalSince1970: 1_790_000_000)

    /// 폰 판 한 변. 아이폰 기준 폭(393) − 양쪽 여백(16×2) 을 `GamesChessBoardMetrics` 에 넣은 값 = **360pt**
    /// (칸 45pt 정확). 숫자를 손으로 적지 않는 까닭: 예산 → 한 변 계산이 깨지면 이 파일이 같이 빨개진다.
    static let side = GamesChessBoardMetrics.side(fitting: CGSize(width: 393 - 32, height: 700))

    static func position(_ fen: String) throws -> ChessPosition {
        try #require(ChessPosition(fen: fen), "FEN 을 못 읽었다: \(fen)")
    }

    static func square(_ notation: String) throws -> ChessSquare {
        try #require(ChessSquare(notation), "칸 표기를 못 읽었다: \(notation)")
    }

    /// 그 수의 애니메이션.
    static func flight(_ from: String, _ to: String, before: String, after: String) throws -> ChessMoveFlight {
        try #require(ChessMoveFlight.make(move: ChessMove(from: try square(from), to: try square(to)),
                                          before: try position(before), after: try position(after),
                                          matchID: "match-1", ply: 7, generation: 1, startedAt: epoch),
                     "\(from)\(to) 의 애니메이션이 안 만들어졌다 — 수와 국면이 안 맞는다")
    }

    // MARK: - 시각 (이징의 역함수로 **정확한** 진행도를 집는다)

    /// `easeOut` 의 역함수. `easeOut(t) = 1 − (1−t)³` 이므로 `t = 1 − ∛(1−e)` 다.
    /// 이걸로 집어야 "t = 0.5" 가 **이징이 들어간 0.5** 가 된다 — `slideDuration` 의 절반을 쓰면
    /// `easeOut(0.5) = 0.875` 라 말이 도착 칸에 거의 닿아 있다.
    static func rawProgress(forEased eased: Double) -> Double { 1 - cbrt(1 - eased) }

    /// 진행도 허용오차. `Date` 왕복의 ulp(2026년 시각에서 1.19e-07초)가 진행도로 번지는 폭이다.
    static let progressTolerance = 1e-5

    static func slideMoment(_ flight: ChessMoveFlight, eased: Double) -> Date {
        flight.startedAt.addingTimeInterval(flight.slideDuration * rawProgress(forEased: eased))
    }

    /// 밀림의 **이징이 들어간** 진행도가 정확히 `eased` 인 시각(지연을 지난 뒤부터 센다).
    static func knockoutMoment(_ flight: ChessMoveFlight, eased: Double) -> Date {
        flight.startedAt.addingTimeInterval(
            flight.knockoutDelay + flight.knockoutDuration * rawProgress(forEased: eased))
    }

    /// 밀림 **날 진행도** `raw` 의 시각. 오프셋·비율은 `easeOut(raw)` 로 깎이지만 **불투명도는 날 진행도로**
    /// 깎이므로, 흐려짐을 겨누는 자리는 이쪽으로 잡아야 뜻이 분명하다.
    static func knockoutMomentRaw(_ flight: ChessMoveFlight, raw: Double) -> Date {
        flight.startedAt.addingTimeInterval(flight.knockoutDelay + flight.knockoutDuration * raw)
    }

    // MARK: - 그림 · 좌표

    static func geometry(_ orientation: ChessColor = .white) -> ChessPhoneBoardGeometry {
        ChessPhoneBoardGeometry(side: side, orientation: orientation)
    }

    enum RenderFailure: Error { case failed }

    /// 폰이 쓰는 **그 캔버스**를 굽는다(scale 2 · 판 하나만 — 창 오프셋이 없다).
    static func bitmap(_ position: ChessPosition?,
                       orientation: ChessColor = .white,
                       lastMove: (from: ChessSquare, to: ChessSquare)? = nil,
                       selected: ChessSquare? = nil,
                       targets: Set<ChessSquare> = [],
                       flight: ChessFlightFrame? = nil) throws -> NSBitmapImageRep {
        let view = GamesChessBoardCanvas(position: position, geometry: geometry(orientation),
                                         lastMove: lastMove, selected: selected, targets: targets,
                                         flight: flight)
        return try bake(view.fixedSize())
    }

    static func bake(_ view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { throw RenderFailure.failed }
        return rep
    }

    /// 그 칸의 **가운데 50% 상자**(판 좌표) — 칸 테두리·좌표 글자를 뺀다.
    static func squareProbe(_ square: ChessSquare, _ g: ChessPhoneBoardGeometry) -> CGRect {
        let box = g.rect(of: square)
        return box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)
    }

    /// 한 점을 가운데로 둔 `fraction` 칸 크기 상자. **칸 격자에 얽히지 않은 자리**를 재는 데 쓴다
    /// (두 칸 사이 · 밀려난 자리는 어떤 칸의 중앙도 아니다).
    static func pointProbe(_ point: CGPoint, _ g: ChessPhoneBoardGeometry, fraction: CGFloat = 0.5) -> CGRect {
        let side = g.cell * fraction
        return CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
    }

    /// 칸 단위 오프셋의 **기대 화면 오프셋**.
    ///
    /// ★ `ChessPhoneBoardGeometry.offset(fileDelta:rankDelta:)` 를 **쓰지 않고** 뒤집기 규칙에서 직접 센다.
    ///   맥에서 프로브를 production 의 `offset(...)` 으로 잡았더니 뒤집기를 지운 뮤테이션에서 **프로브가 결함과
    ///   같이 움직여** 잉크 단언이 통째로 초록이었다. 재는 자리를 재는 대상에서 가져오면 아무것도 안 잰다.
    static func expectedShift(fileCells: Double, rankCells: Double, _ g: ChessPhoneBoardGeometry) -> CGSize {
        let columnSign: CGFloat = g.orientation == .white ? 1 : -1   // 화면 열이 file 과 같은 방향인가
        let rowSign: CGFloat = g.orientation == .white ? -1 : 1      // 화면 행은 rank 와 반대(백) · 같다(흑)
        return CGSize(width: columnSign * CGFloat(fileCells) * g.cell,
                      height: rowSign * CGFloat(rankCells) * g.cell)
    }

    // MARK: - 잉크

    /// **말 잉크** — 아주 밝거나(최대 ≥ 235) 아주 어두운(최소 ≤ 55) 픽셀.
    static func pieceInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
        count(bitmap, rect: rect) { r, g, b in max(r, max(g, b)) >= 235 || min(r, min(g, b)) <= 55 }
    }

    /// **어두운** 쪽만(최소 ≤ 55) — 흑 말의 채움이다.
    static func darkInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
        count(bitmap, rect: rect) { r, g, b in min(r, min(g, b)) <= 55 }
    }

    /// **밝은** 쪽만(최대 ≥ 235) — 흰 말의 채움이다. 이 수가 **줄면** 그 자리를 다른 것이 덮었다는 뜻이다.
    static func brightInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
        count(bitmap, rect: rect) { r, g, b in max(r, max(g, b)) >= 235 }
    }

    static func count(_ bitmap: NSBitmapImageRep, rect: CGRect,
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

    /// 사각형 안 **말 잉크를 감싸는 상자**(pt). 잉크가 없으면 nil. 밀림이 **얼마나** 갔는지를 재는 자리다.
    static func inkBounds(_ bitmap: NSBitmapImageRep, rect: CGRect) -> CGRect? {
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
    static func maxChannelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
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
    static func inkedSquares(_ bitmap: NSBitmapImageRep, _ g: ChessPhoneBoardGeometry) -> Set<String> {
        var out: Set<String> = []
        for index in 0..<64 {
            guard let square = ChessSquare(index: index) else { continue }
            if pieceInk(bitmap, rect: squareProbe(square, g)) > 0 { out.insert(square.notation) }
        }
        return out
    }

    static var whole: CGRect { CGRect(x: 0, y: 0, width: side, height: side) }

    // MARK: - ① 순간이동이 아니다 — t = 0.5 에서 말이 두 칸 **사이**에 있다

    /// 없으면: `flight` 를 받아 놓고 멈춘 판만 그리는 판이 초록으로 통과한다. "순간이동이 아니다"를 재는
    /// **단 하나의** 단언이고 나머지 시험은 전부 이 자리 위에 선다.
    @Test("t=0.5 에 출발 칸 0px · 도착 칸 0px · 두 칸 가운데에 잉크 (멈춘 판은 정확히 반대)")
    func theSlidingPieceSitsBetweenTheTwoSquaresAtHalfProgress() throws {
        let g = Self.geometry()
        let after = try Self.position(Self.afterE4FEN)
        let flight = try Self.flight("e2", "e4", before: Self.standardFEN, after: Self.afterE4FEN)
        // 전제: 거리 두 칸이라 궤적의 가운데가 정확히 e3 칸 중앙이다(프로브가 칸 하나로 떨어진다).
        #expect(abs(flight.slideDuration - 0.20) < 1e-12,
                "두 칸 미끄러짐이 \(flight.slideDuration)s 다 — 0.20s 여야 한다")

        let frame = try #require(flight.frame(now: Self.slideMoment(flight, eased: 0.5)))
        let moving = try #require(frame.moving.first)
        #expect(abs(moving.t - 0.5) < Self.progressTolerance,
                "이징이 들어간 진행도가 \(moving.t) 다 — 0.5 를 집지 못했다")

        let from = try Self.square("e2"), to = try Self.square("e4"), middle = try Self.square("e3")
        let flying = try Self.bitmap(after, flight: frame)
        let frozen = try Self.bitmap(after)

        let flyingFrom = Self.pieceInk(flying, rect: Self.squareProbe(from, g))
        let flyingTo = Self.pieceInk(flying, rect: Self.squareProbe(to, g))
        let flyingMiddle = Self.pieceInk(flying, rect: Self.squareProbe(middle, g))
        print("[미끄러짐 t=0.5] 출발 e2 \(flyingFrom)px · 도착 e4 \(flyingTo)px · 가운데 e3 \(flyingMiddle)px")

        #expect(flyingFrom == 0, "t=0.5 인데 출발 칸에 말이 남아 있다(\(flyingFrom)px)")
        #expect(flyingTo == 0, "t=0.5 인데 도착 칸에 말이 벌써 있다(\(flyingTo)px) — 순간이동이다(hidden 을 안 뺐다)")
        #expect(flyingMiddle > 0, "두 칸 가운데에 아무것도 없다 — 말이 궤적 위에 안 그려졌다")

        // ★ 기준선이 갈린다: 멈춘 판은 **정확히 반대**다. 안 갈리면 위 세 줄은 "판이 통째로 비었다" 로도 초록이다.
        #expect(Self.pieceInk(frozen, rect: Self.squareProbe(to, g)) > 0, "멈춘 판의 도착 칸이 비었다 — 전제가 깨졌다")
        #expect(Self.pieceInk(frozen, rect: Self.squareProbe(middle, g)) == 0, "멈춘 판의 가운데 칸에 말이 있다")
        #expect(Self.pieceInk(frozen, rect: Self.squareProbe(from, g)) == 0)
    }

    // MARK: - ② 기준선을 가른다 — **순간이동 빌드**는 칸 사이 프레임이 0장이다

    /// ★ 맥에서 쓴 것과 같은 가름: 애니메이션을 안 만드는 빌드(= `frame` 을 안 넘기는 판)를 **같은 분석기**로
    ///   재서 칸 사이 프레임 수를 센다. 기준선이 안 갈리면 ①의 숫자는 아무것도 증명하지 않는다 —
    ///   기준선이 같은 입력이면 그 테스트는 영원히 초록이다.
    @Test("칸 사이 프레임: 애니메이션 8장 대 순간이동 0장")
    func theTeleportBaselineHasNoFramesBetweenSquares() throws {
        let g = Self.geometry()
        // 일곱 칸을 가로지르는 룩으로 잰다(a1→a8). 궤적이 길어서 여덟 표본이 전부 **두 칸 어디에서도
        // 멀리** 떨어져 있다 — 두 칸 전진(e2e4)으로 재면 마지막 표본의 프로브가 도착 칸의 멈춘 말에 닿아
        // 순간이동 쪽에서도 잉크가 세어진다(실측 501px).
        let before = try Self.position("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1")
        let move = ChessMove(from: try Self.square("a1"), to: try Self.square("a8"))
        let after = try #require(ChessRules.apply(move, to: before), "합법 수가 아니다: a1a8")
        let flight = try #require(ChessMoveFlight.make(move: move, before: before, after: after,
                                                       matchID: "m", ply: 1, generation: 1, startedAt: Self.epoch))
        #expect(abs(flight.slideDuration - 0.30) < 1e-12, "일곱 칸은 뚜껑(0.30s)에 닿는다 — 지금 \(flight.slideDuration)s")
        let frozen = try Self.bitmap(after)

        var animated = 0, teleported = 0
        var trace: [String] = []
        for step in 1...8 {
            let eased = Double(step) / 10          // 0.1 … 0.8
            let frame = try #require(flight.frame(now: Self.slideMoment(flight, eased: eased)))
            let moving = try #require(frame.moving.first)
            // 궤적 위의 **그 지점**에 프로브를 둔다. 멈춘 판에서 그 자리는 빈 칸이다(말은 e4 에 있다).
            let spot = g.rect(from: moving.from, to: moving.to, t: moving.t)
            let probe = Self.pointProbe(CGPoint(x: spot.midX, y: spot.midY), g, fraction: 0.4)
            let flyingInk = Self.pieceInk(try Self.bitmap(after, flight: frame), rect: probe)
            let frozenInk = Self.pieceInk(frozen, rect: probe)
            if flyingInk > 0 { animated += 1 }
            if frozenInk > 0 { teleported += 1 }
            trace.append("t=\(eased): 애니 \(flyingInk)px · 순간이동 \(frozenInk)px")
        }
        for line in trace { print("[기준선] \(line)") }
        print("[기준선] 칸 사이에 말이 있는 프레임: 애니메이션 \(animated)/8 · 순간이동 \(teleported)/8")

        #expect(animated == 8, "여덟 프레임 중 \(animated)장만 궤적 위에 말이 있다")
        #expect(teleported == 0, "순간이동 빌드에서도 칸 사이에 말이 \(teleported)장 보인다 — 기준선이 안 갈렸다")
    }

    // MARK: - ③ 두 끝 — t = 0/1 이 멈춘 판과 **바이트까지** 같다

    /// 없으면: 보간이 두 끝에서 멈춘 판과 어긋나도(0 에서 벌써 반쯤 가 있거나 1 에서 못 닿거나) 초록이다 —
    /// 그러면 수가 시작할 때와 끝날 때 말이 한 번씩 **튄다**.
    @Test("rect(from:to:t:) 의 t=0/1 은 rect(of:) 와 완전히 같은 사각형 (백·흑 판 둘 다)", arguments: [ChessColor.white, .black])
    func theInterpolatedRectMatchesTheFrozenSquareExactlyAtBothEnds(orientation: ChessColor) throws {
        let g = Self.geometry(orientation)
        let from = try Self.square("e2"), to = try Self.square("e4")
        #expect(g.rect(from: from, to: to, t: 0) == g.rect(of: from),
                "t=0 사각형 \(g.rect(from: from, to: to, t: 0)) 이 출발 칸 \(g.rect(of: from)) 과 다르다")
        #expect(g.rect(from: from, to: to, t: 1) == g.rect(of: to),
                "t=1 사각형 \(g.rect(from: from, to: to, t: 1)) 이 도착 칸 \(g.rect(of: to)) 과 다르다")
        // 범위 밖·숫자 아님도 두 끝으로 떨어진다(음수 시각·지난 시각에 판이 안 깨지는 근거).
        #expect(g.rect(from: from, to: to, t: -3) == g.rect(of: from))
        #expect(g.rect(from: from, to: to, t: 4) == g.rect(of: to))
        #expect(g.rect(from: from, to: to, t: .nan) == g.rect(of: from))
    }

    /// 그림으로도 같은 말이다: t=1 프레임은 멈춘 판과 **눈으로 같고**, t=0.5 프레임은 **눈으로 다르다**.
    @Test("t=1 그림은 멈춘 판과 같고 t=0.5 그림은 다르다(같은 기준으로 양쪽을 잰다)")
    func theLandingFrameLooksIdenticalToTheFrozenBoard() throws {
        let after = try Self.position(Self.afterE4FEN)
        let flight = try Self.flight("e2", "e4", before: Self.standardFEN, after: Self.afterE4FEN)

        // t = 1 프레임은 **손으로 짓는다**. 모델에서 뽑으면 `startedAt + duration` 의 `Date` 왕복 오차
        // (0.2 → 0.20000004768…)가 열린 경계(`isFinished` 는 `>`)를 넘겨 프레임이 nil 로 떨어진다 —
        // 여기서 재는 것은 "t 가 1 이면 멈춘 판과 같은 그림인가" 이므로 t 를 정확히 1 로 둬야 뜻이 분명하다.
        let slider = try #require(flight.sliders.first)
        let landed = ChessFlightFrame(
            moving: [ChessFlightFrame.Moving(piece: slider.piece, from: slider.from, to: slider.to, t: 1)],
            leaving: nil, hidden: [slider.to])
        let half = try #require(flight.frame(now: Self.slideMoment(flight, eased: 0.5)))

        let frozen = try Self.bake(GamesChessBoardCanvas(position: after, geometry: Self.geometry()).fixedSize())
        let atEnd = try Self.bake(GamesChessBoardCanvas(position: after, geometry: Self.geometry(), flight: landed).fixedSize())
        let atHalf = try Self.bake(GamesChessBoardCanvas(position: after, geometry: Self.geometry(), flight: half).fixedSize())

        let endDiff = try #require(CheckRenderDiff(try Self.cgImage(atEnd), try Self.cgImage(frozen)))
        let halfDiff = try #require(CheckRenderDiff(try Self.cgImage(atHalf), try Self.cgImage(frozen)))
        print("[두 끝] t=1 대 멈춘 판: \(endDiff) / t=0.5 대 멈춘 판: \(halfDiff)")
        #expect(endDiff.looksSame, "t=1 그림이 멈춘 판과 다르다(\(endDiff)) — 도착 순간 말이 튄다")
        #expect(halfDiff.looksDifferent, "t=0.5 그림이 멈춘 판과 같다(\(halfDiff)) — 기준선이 안 갈렸다")
    }

    static func cgImage(_ rep: NSBitmapImageRep) throws -> CGImage {
        try #require(rep.cgImage, "비트맵에서 CGImage 를 못 꺼냈다")
    }

    // MARK: - ④ 잡힌 말이 **보인다**(밀려난 자리에 잉크가 있다)

    /// 없으면: `leaving` 을 안 그리는 판이 초록이다 — 잡힌 말은 `position` 에 **이미 없어서** ⑤a 가 한 번도
    /// 그리지 않으므로, 여기가 비면 "말이 갑자기 사라진다"(사용자가 말한 증상)로 그대로 되돌아간다.
    @Test("잡힌 말은 밀려난 자리에 그려진다 — 멈춘 판의 그 자리는 0px 다")
    func theCapturedPieceIsDrawnPushedOutOfItsSquare() throws {
        let g = Self.geometry()
        let after = try Self.position(Self.enPassantAfterFEN)
        let flight = try Self.flight("d5", "e6", before: Self.enPassantBeforeFEN, after: Self.enPassantAfterFEN)
        let knockout = try #require(flight.knockout)
        #expect(knockout.square == (try Self.square("e5")),
                "앙파상의 잡힌 칸은 도착 칸이 아니라 지나친 칸(e5)이어야 한다 — 지금 \(knockout.square.notation)")

        let frame = try #require(flight.frame(now: Self.knockoutMoment(flight, eased: 0.60)))
        let leaving = try #require(frame.leaving)
        // 날고 있는 말을 뺀 같은 프레임 — 재는 상자 안에 **빠지는 말 하나만** 남는다.
        let onlyLeaving = ChessFlightFrame(moving: [], leaving: leaving, hidden: frame.hidden)
        let flying = try Self.bitmap(after, flight: onlyLeaving)
        let frozen = try Self.bitmap(after)

        let home = g.center(of: knockout.square)
        let shift = Self.expectedShift(fileCells: leaving.fileOffset, rankCells: leaving.rankOffset, g)
        let pushed = CGPoint(x: home.x + shift.width, y: home.y + shift.height)
        let probe = Self.pointProbe(pushed, g, fraction: 0.4)
        let pushedInk = Self.pieceInk(flying, rect: probe)
        let frozenInk = Self.pieceInk(frozen, rect: probe)
        print("[잡힘] 밀려난 자리 \(pushed): 애니메이션 \(pushedInk)px · 멈춘 판 \(frozenInk)px")

        #expect(pushedInk > 150, "잡힌 말이 밀려난 자리에 \(pushedInk)px 뿐이다 — 안 그려졌다")
        #expect(frozenInk == 0, "멈춘 판의 그 자리에 \(frozenInk)px 가 있다 — 기준선이 안 갈렸다")
    }

    // MARK: - ⑤ ★ 먼저 밀려나고 **나중에** 흐려진다 (이 작업에서 가장 비쌌던 함정)

    /// 없으면: 오프셋·비율과 불투명도를 **같은 `easeOut`** 으로 깎는 길이 초록이다. easeOutCubic 이 움직임의
    /// 87.5%를 앞 절반에 몰아넣기 때문에 그렇게 깎으면 불투명도가 밀림 절반에서 벌써 **0.192**, 80%에서
    /// **0.012** 가 된다 — 잡힌 말이 **밀려나기도 전에 사라진다**(고치려던 증상 그대로다).
    @Test("밀림 잉크는 단조 감소 · 끝에서 0 · 그러나 0.8 지점에서는 아직 또렷하다")
    func theCapturedPieceSlidesOutFirstAndFadesAfterwards() throws {
        let g = Self.geometry()
        let after = try Self.position(Self.enPassantAfterFEN)
        let flight = try Self.flight("d5", "e6", before: Self.enPassantBeforeFEN, after: Self.enPassantAfterFEN)
        let square = try #require(flight.knockout).square
        let home = g.rect(of: square)
        // 밀림의 끝(0.55칸)까지 담는 상자. 오른쪽·위로만 넓힌다(밀림 방향이 (+file, +rank) = 화면 (+x, −y)).
        let region = CGRect(x: home.minX, y: home.minY - g.cell * 0.55,
                            width: home.width + g.cell * 0.55, height: home.height + g.cell * 0.55)

        var inks: [(eased: Double, ink: Int, opacity: Double)] = []
        for eased in [0.0, 0.2, 0.4, 0.6, 0.8] {
            let real = try #require(flight.frame(now: Self.knockoutMoment(flight, eased: eased)))
            let leaving = try #require(real.leaving)
            let onlyLeaving = ChessFlightFrame(moving: [], leaving: leaving, hidden: real.hidden)
            inks.append((eased, Self.pieceInk(try Self.bitmap(after, flight: onlyLeaving), rect: region),
                         leaving.opacity))
        }
        for row in inks { print("[밀림] 진행도 \(row.eased): 잉크 \(row.ink)px · 불투명도 \(row.opacity)") }

        // 단조 감소 — 비율과 불투명도가 둘 다 진행도에 따라 줄기만 하므로 중간에 늘어날 길이 없다.
        for (earlier, later) in zip(inks, inks.dropFirst()) {
            #expect(earlier.ink > later.ink,
                    "진행도 \(earlier.eased)(\(earlier.ink)px) 가 \(later.eased)(\(later.ink)px) 보다 많지 않다 — 단조가 깨졌다")
        }
        // 끝에서는 잉크가 0 이다 — 흐려짐이 그림에 안 들어갔으면 비율만 줄어 끝까지 잉크가 남는다.
        // 날 진행도 0.999 로 잰다(1.0 은 `isFinished` 경계라 반올림 한 틱에 프레임이 nil 로 떨어진다).
        let nearEnd = try #require(flight.frame(now: Self.knockoutMomentRaw(flight, raw: 0.999)))
        let nearEndLeaving = try #require(nearEnd.leaving)
        #expect(nearEndLeaving.opacity < 0.01, "전제: 끝 직전에는 거의 투명하다(지금 \(nearEndLeaving.opacity))")
        let endInk = Self.pieceInk(try Self.bitmap(after, flight: ChessFlightFrame(
            moving: [], leaving: nearEndLeaving, hidden: nearEnd.hidden)), rect: region)
        #expect(endInk == 0, "끝까지 가도 잡힌 말이 \(endInk)px 남아 있다 — 흐려짐이 그림에 안 들어갔다")

        // ★★ 이 줄이 이 시험의 핵심이다. 이징이 들어간 0.8 의 **날** 진행도는 0.4152 → 불투명도 0.8997 이라
        //   말이 아직 또렷해야 한다. 불투명도를 `easeOut` 으로 깎으면 여기서 0.3077 이 되어 잉크가 0 이 된다
        //   (맥 실측 0px → 755px).
        #expect(inks[4].opacity > 0.8,
                "밀림 0.8 의 불투명도가 \(inks[4].opacity) 다 — 불투명도가 **날 진행도**가 아니라 easeOut 으로 깎였다")
        #expect(inks[4].ink > 0, "밀림 0.8 에서 잡힌 말이 벌써 0px 다 — 밀려 나가기 전에 사라진다")
        #expect(inks[0].ink > 700, "밀림 시작에 잡힌 말이 \(inks[0].ink)px 뿐이다 — 전제가 깨졌다")

        // ★ 그리고 **먼저 밀려난다**: 불투명도가 1 로 남아 있는 지점에서 잉크의 가운데가 밀림 방향으로 옮겨져 있다.
        let still = try #require(flight.frame(now: flight.startedAt))
        let pushed = try #require(flight.frame(now: Self.knockoutMoment(flight, eased: 0.30)))
        let pushedLeaving = try #require(pushed.leaving)
        #expect(pushedLeaving.opacity == 1, "전제: 0.30 에서는 아직 불투명도가 1 이다")
        let stillCenter = try #require(Self.inkBounds(try Self.bitmap(after, flight: ChessFlightFrame(
            moving: [], leaving: still.leaving, hidden: still.hidden)), rect: region))
        let pushedCenter = try #require(Self.inkBounds(try Self.bitmap(after, flight: ChessFlightFrame(
            moving: [], leaving: pushedLeaving, hidden: pushed.hidden)), rect: region))
        let moved = CGSize(width: pushedCenter.midX - stillCenter.midX, height: pushedCenter.midY - stillCenter.midY)
        // 기대값: 0.55칸 × easeOut(0.30) 을 (+x, −y) 로. 45pt 칸에서 ±7.43pt 다.
        let expected = Self.expectedShift(fileCells: pushedLeaving.fileOffset,
                                          rankCells: pushedLeaving.rankOffset, g)
        print("[밀림] 불투명도 1 인 채로 옮겨 간 거리 = \(moved) · 기대 \(expected)")
        #expect(abs(moved.width - expected.width) < 3 && abs(moved.height - expected.height) < 3,
                "흐려지기 전에 옮겨 간 거리가 \(moved) 다 — \(expected) 여야 한다(먼저 밀려나지 않았다)")
    }

    // MARK: - ⑥ ★ 흑으로 두는 판은 **화면상 반대쪽**으로 간다 (offset 의 부호)

    /// 없으면: 뒤집기를 잊은 기하가 초록이다 — 흑으로 두는 사람만 말이 엉뚱한 쪽으로 미끄러지고 잡힌 말이
    /// 잡은 말 쪽으로 **되밀려 들어온다**(판 좌표를 그대로 화면에 쓰면 그렇게 된다).
    @Test("흑 판: 궤적도 밀림도 화면에서 마주보는 쪽으로 간다")
    func theBlackSideBoardSlidesAndPushesTheOppositeWayOnScreen() throws {
        let white = Self.geometry(.white), black = Self.geometry(.black)
        let after = try Self.position(Self.afterE4FEN)
        let flight = try Self.flight("e2", "e4", before: Self.standardFEN, after: Self.afterE4FEN)
        let frame = try #require(flight.frame(now: Self.slideMoment(flight, eased: 0.5)))
        let moving = try #require(frame.moving.first)

        // ★ 프로브를 보간 함수가 아니라 **가운데 칸의 중앙**으로 잡는다(e2→e4 는 두 칸이라 t=0.5 가 정확히
        //   e3 중앙이다) — `rect(from:to:t:)` 로 잡으면 그 함수가 깨져도 프로브가 같이 움직여 아무것도 안 잰다.
        let middle = try Self.square("e3")
        let whiteSpot = white.center(of: middle), blackSpot = black.center(of: middle)
        // 보간 함수가 **그 자리를** 내는지 두 방향에서 따로 본다. `rect(from:to:t:)` 에 `orientation` 이 또
        // 들어가면(이중 뒤집기) 흑 판에서 이 줄이 빨개진다.
        for g in [white, black] {
            let box = g.rect(from: moving.from, to: moving.to, t: moving.t)
            let interpolated = CGPoint(x: box.midX, y: box.midY)
            let expected = g.center(of: middle)
            #expect(abs(interpolated.x - expected.x) < 0.01 && abs(interpolated.y - expected.y) < 0.01,
                    "\(g.orientation) 판의 보간 가운데가 \(interpolated) 다 — e3 중앙 \(expected) 여야 한다")
        }
        print("[흑 판] 궤적 가운데: 백 \(whiteSpot) · 흑 \(blackSpot)")
        #expect(abs(whiteSpot.x + blackSpot.x - white.side) < 0.01
                && abs(whiteSpot.y + blackSpot.y - white.side) < 0.01,
                "두 방향의 궤적 가운데가 판 가운데를 기준으로 마주보지 않는다(백 \(whiteSpot) · 흑 \(blackSpot))")

        let whiteBitmap = try Self.bitmap(after, orientation: .white, flight: frame)
        let blackBitmap = try Self.bitmap(after, orientation: .black, flight: frame)
        let whiteProbe = Self.pointProbe(whiteSpot, white, fraction: 0.5)
        let blackProbe = Self.pointProbe(blackSpot, black, fraction: 0.5)
        let whiteAtWhite = Self.pieceInk(whiteBitmap, rect: whiteProbe)
        let whiteAtBlack = Self.pieceInk(whiteBitmap, rect: blackProbe)
        let blackAtBlack = Self.pieceInk(blackBitmap, rect: blackProbe)
        let blackAtWhite = Self.pieceInk(blackBitmap, rect: whiteProbe)
        print("[흑 판] 백 비트맵: 백자리 \(whiteAtWhite)px · 흑자리 \(whiteAtBlack)px / 흑 비트맵: 흑자리 \(blackAtBlack)px · 백자리 \(blackAtWhite)px")
        #expect(whiteAtWhite > 0 && whiteAtBlack == 0, "백 판의 말이 흑 판 자리에도 있다")
        #expect(blackAtBlack > 0 && blackAtWhite == 0, "흑 판의 말이 백 판 자리로 갔다 — 뒤집기가 안 들어갔다")

        // 잡힌 말이 **밀리는 방향**도 뒤집힌다. 같은 판 좌표 오프셋이 두 방향에서 화면 부호가 반대여야 한다.
        let capture = try Self.flight("d5", "e6", before: Self.enPassantBeforeFEN, after: Self.enPassantAfterFEN)
        let captureAfter = try Self.position(Self.enPassantAfterFEN)
        let pushedFrame = try #require(capture.frame(now: Self.knockoutMoment(capture, eased: 0.30)))
        let leaving = try #require(pushedFrame.leaving)
        let whiteExpected = Self.expectedShift(fileCells: leaving.fileOffset, rankCells: leaving.rankOffset, white)
        let blackExpected = Self.expectedShift(fileCells: leaving.fileOffset, rankCells: leaving.rankOffset, black)
        #expect(abs(whiteExpected.width + blackExpected.width) < 0.01
                && abs(whiteExpected.height + blackExpected.height) < 0.01,
                "두 방향의 기대 밀림이 서로 반대가 아니다(백 \(whiteExpected) · 흑 \(blackExpected))")
        let blackShift = black.offset(fileDelta: leaving.fileOffset, rankDelta: leaving.rankOffset)
        #expect(abs(blackShift.width - blackExpected.width) < 0.01
                && abs(blackShift.height - blackExpected.height) < 0.01,
                "흑 판 기하가 낸 오프셋 \(blackShift) 가 기대 \(blackExpected) 와 다르다 — 뒤집기가 안 들어갔다")

        // ★ 프로브는 **기대값**으로 잡는다(위 `expectedShift` 의 ★).
        let blackHome = black.center(of: leaving.square)
        let blackPushed = CGPoint(x: blackHome.x + blackExpected.width, y: blackHome.y + blackExpected.height)
        let blackMirror = CGPoint(x: blackHome.x - blackExpected.width, y: blackHome.y - blackExpected.height)
        let capturedBitmap = try Self.bitmap(captureAfter, orientation: .black, flight: ChessFlightFrame(
            moving: [], leaving: leaving, hidden: pushedFrame.hidden))
        let pushedInk = Self.pieceInk(capturedBitmap, rect: Self.pointProbe(blackPushed, black, fraction: 0.4))
        let mirrorInk = Self.pieceInk(capturedBitmap, rect: Self.pointProbe(blackMirror, black, fraction: 0.4))
        print("[흑 판] 잡힌 말: 밀린 쪽 \(pushedInk)px · 반대쪽 \(mirrorInk)px")
        #expect(pushedInk > 150, "흑 판에서 잡힌 말이 밀린 쪽에 \(pushedInk)px 뿐이다")
        #expect(pushedInk > mirrorInk * 2,
                "흑 판에서 밀린 쪽(\(pushedInk)px)과 반대쪽(\(mirrorInk)px)이 비슷하다 — 방향이 안 뒤집혔다")
    }

    // MARK: - ⑦ ★★ 흐려지는 잡힌 말이 **날고 있는 말까지** 흐리지 않는다 (사본 함정)

    /// 없으면: 불투명도를 `GraphicsContext` **사본이 아니라 원본**에 걸어도 전부 초록이다(맥 실측 48/48).
    /// `GraphicsContext` 는 값이라 원본에 걸면 그 뒤에 그리는 ⑤c 까지 같이 흐려진다 — **잡는 수마다 잡은 말이
    /// 도착하는 순간 같이 투명해져** 사라진 것처럼 보인다. 증상이 잡힌 말에서 잡은 말로 옮겨갈 뿐이다.
    ///
    /// 왜 다른 시험이 못 무나: 잡힘을 재는 ④⑤는 `moving: []` 로 **날고 있는 말을 빼고**, 미끄러짐을 재는 ①②③은
    /// 잡기가 없는 수(e2e4)를 쓴다. "불투명도가 1 아래인 잡힌 말"과 "날고 있는 말"이 **한 장에 같이 있는**
    /// 프레임을 아무도 그리지 않는다. 그 한 장이 이 시험이다(앙파상이라 두 칸이 달라 겹치지도 않는다).
    @Test("잡힌 말이 흐려져도 날고 있는 말의 잉크는 그대로다 (불투명도는 context 사본에)")
    func theFadingCapturedPieceDoesNotFadeTheFlyingPieceWithIt() throws {
        let g = Self.geometry()
        let after = try Self.position(Self.enPassantAfterFEN)
        let flight = try Self.flight("d5", "e6", before: Self.enPassantBeforeFEN, after: Self.enPassantAfterFEN)
        let destination = try Self.square("e6")

        // 잡힌 말이 **뚜렷하게 흐려진** 지점(날 진행도 0.85 → 불투명도 0.2308). 그때 미끄러짐은 이미 끝에 닿아
        // 날고 있는 폰이 도착 칸 위에 있다 — 두 겹이 한 장에 겹치는 구간이 여기다.
        let frame = try #require(flight.frame(now: Self.knockoutMomentRaw(flight, raw: 0.85)))
        let leaving = try #require(frame.leaving)
        let moving = try #require(frame.moving.first)
        #expect(leaving.opacity < 0.5, "전제: 이 지점에서 잡힌 말이 흐려져 있어야 한다(지금 \(leaving.opacity))")
        #expect(1 - moving.t < 1e-3, "전제: 이 지점에서 날고 있는 말이 도착 칸에 닿아 있어야 한다(t = \(moving.t))")

        let withoutVictim = ChessFlightFrame(moving: frame.moving, leaving: nil, hidden: frame.hidden)
        let both = try Self.bitmap(after, flight: frame)
        let flierOnly = try Self.bitmap(after, flight: withoutVictim)

        let probe = Self.squareProbe(destination, g)
        let flierInk = Self.pieceInk(flierOnly, rect: probe)
        let bothInk = Self.pieceInk(both, rect: probe)
        print("[사본 함정] 도착 칸 e6: 잡힌 말 없이 \(flierInk)px · 같이 그리면 \(bothInk)px")
        #expect(flierInk > 150, "전제: 날고 있는 말이 도착 칸에 \(flierInk)px 뿐이다 — 재는 자리가 비었다")
        // 여유 20px: 잉크는 문턱 셈이라 ImageRenderer 의 ±2 채널 잡음이 가장자리 픽셀 몇 개를 넘나든다.
        // 원본에 걸린 결함은 이 자리를 통째로 0 으로 떨어뜨린다.
        #expect(bothInk > flierInk - 20,
                "흐려지는 잡힌 말이 날고 있는 말의 잉크를 \(flierInk - bothInk)px 깎았다 — 불투명도가 사본이 아니라 **원본**에 걸렸다")

        // ★ 기준선이 갈린다: 두 그림은 **어딘가는 달라야** 한다(잡힌 말을 아예 안 그리면 위 두 줄은 공허하다).
        let anyDifference = Self.maxChannelDifference(both, flierOnly, rect: Self.whole)
        print("[사본 함정] 판 전체 채널 최대 차 = \(anyDifference)")
        #expect(anyDifference > 20,
                "잡힌 말을 더해도 그림이 \(anyDifference) 밖에 안 바뀐다 — 흐려진 잡힌 말이 아예 안 그려졌다")
    }

    // MARK: - ⑧ 겹침 순서 — 잡힌 말은 잡은 말 **아래**, 캐슬링의 왕은 룩 **위**

    /// 없으면: ⑤b 를 ⑤c **뒤로** 옮겨도 초록이다(맥 실측 — 뮤테이션이 한 건도 안 물렸다). 그러면 보통의
    /// 잡기에서 **죽어 가는 말이 도착하는 말을 덮어** 잡은 말이 자기 무덤 뒤로 숨는다.
    @Test("보통의 잡기: 잡은 말의 밝은 잉크가 그대로 남는다(잡힌 말이 그 아래다)")
    func theCapturedPieceIsDrawnUnderTheCapturerNotOverIt() throws {
        let g = Self.geometry()
        let before = try Self.position(Self.pawnCaptureBeforeFEN)
        let move = ChessMove(from: try Self.square("d4"), to: try Self.square("e5"))
        // `after` 를 엔진으로 만든다 — 손으로 적은 FEN 은 "수와 국면이 맞는가" 단언을 공허하게 만든다.
        let after = try #require(ChessRules.apply(move, to: before), "합법 수가 아니다: d4e5")
        let flight = try #require(ChessMoveFlight.make(move: move, before: before, after: after,
                                                       matchID: "m", ply: 3, generation: 1, startedAt: Self.epoch))
        let destination = try Self.square("e5")
        #expect(flight.knockout?.square == destination, "보통의 잡기는 잡힌 칸 = 도착 칸이다 — 그래서 두 겹이 겹친다")

        // 밀림 진행도 0.15: 불투명도는 **정확히 1**(흐려짐은 0.35 부터)이고 잡은 말은 궤적의 88%까지 왔다.
        let frame = try #require(flight.frame(now: Self.knockoutMoment(flight, eased: 0.15)))
        let leaving = try #require(frame.leaving)
        let moving = try #require(frame.moving.first)
        #expect(leaving.opacity == 1, "전제: 이 지점에서 잡힌 말이 아직 또렷해야 한다(지금 \(leaving.opacity))")
        #expect(moving.t > 0.8, "전제: 잡은 말이 도착 칸에 들어와야 한다(t = \(moving.t))")
        #expect(moving.piece == ChessPiece(.white, .pawn))
        #expect(leaving.piece == ChessPiece(.black, .pawn), "감지기가 색으로 가르므로 두 말의 색이 달라야 한다")

        let both = try Self.bitmap(after, flight: frame)
        let capturerOnly = try Self.bitmap(after, flight: ChessFlightFrame(
            moving: frame.moving, leaving: nil, hidden: frame.hidden))
        let victimOnly = try Self.bitmap(after, flight: ChessFlightFrame(
            moving: [], leaving: leaving, hidden: frame.hidden))

        let probe = Self.squareProbe(destination, g)
        let bothBright = Self.brightInk(both, rect: probe)
        let capturerBright = Self.brightInk(capturerOnly, rect: probe)
        let victimDark = Self.darkInk(victimOnly, rect: probe)
        let bothDark = Self.darkInk(both, rect: probe)
        print("[겹침] 도착 칸 e5: 밝은 잉크 잡은말만 \(capturerBright)px → 같이 \(bothBright)px · "
              + "어두운 잉크 잡힌말만 \(victimDark)px → 같이 \(bothDark)px")

        #expect(capturerBright > 150, "전제: 잡은 말의 밝은 잉크가 \(capturerBright)px 뿐이다")
        #expect(victimDark > 150, "전제: 잡힌 말의 어두운 잉크가 \(victimDark)px 뿐이다")
        #expect(bothBright > capturerBright - 40,
                "밝은 잉크가 \(capturerBright)px → \(bothBright)px — 잡힌 말이 잡은 말 **위**에 그려졌다")
        #expect(bothDark > 0, "두 겹을 같이 그렸는데 어두운 잉크가 없다 — 잡힌 말이 아예 안 그려졌다")
    }

    /// 캐슬링은 **둘이 같이** 움직인다(왕·룩). 배열 순서대로 그려야 스치는 구간에서 왕이 룩 위에 온다.
    @Test("캐슬링: 왕과 룩이 둘 다 궤적 위에 있고 두 출발 칸은 비어 있다")
    func castlingSlidesBothTheKingAndTheRook() throws {
        let g = Self.geometry()
        let before = try Self.position("4k3/8/8/8/8/8/8/4K2R w K - 0 1")
        let move = ChessMove(from: try Self.square("e1"), to: try Self.square("g1"))
        let after = try #require(ChessRules.apply(move, to: before), "캐슬링이 합법이 아니다")
        let flight = try #require(ChessMoveFlight.make(move: move, before: before, after: after,
                                                       matchID: "m", ply: 1, generation: 1, startedAt: Self.epoch))
        #expect(flight.sliders.count == 2, "캐슬링인데 미끄러지는 말이 \(flight.sliders.count)개다")
        #expect(flight.sliders.last?.piece.kind == .king, "왕이 배열 **마지막**이어야 한다(그래야 룩 위에 그려진다)")

        let frame = try #require(flight.frame(now: Self.slideMoment(flight, eased: 0.5)))
        let bitmap = try Self.bitmap(after, flight: frame)
        for moving in frame.moving {
            let spot = g.rect(from: moving.from, to: moving.to, t: moving.t)
            let ink = Self.pieceInk(bitmap, rect: Self.pointProbe(CGPoint(x: spot.midX, y: spot.midY), g, fraction: 0.4))
            print("[캐슬링] \(moving.piece.kind) \(moving.from.notation)→\(moving.to.notation): \(ink)px")
            #expect(ink > 0, "\(moving.piece.kind) 가 궤적 위에 안 그려졌다")
            #expect(Self.pieceInk(bitmap, rect: Self.squareProbe(moving.from, g)) == 0,
                    "\(moving.piece.kind) 가 출발 칸 \(moving.from.notation) 에 남아 있다")
        }
        // ★ "도착 칸이 비었는가" 는 캐슬링에서 물을 수 없다 — t=0.5 에 왕은 f1(룩의 도착 칸)에, 룩은
        //   g1(왕의 도착 칸)에 있다. 둘이 **서로의 도착 칸을 지나가는 것**이 캐슬링이다. `hidden` 계약은
        //   ①(e2e4)이 재고, 여기서는 그 교차를 그대로 못으로 박는다.
        let crossing = [("g1", ChessPieceKind.rook), ("f1", .king)]
        for (notation, kind) in crossing {
            let square = try Self.square(notation)
            let ink = Self.pieceInk(bitmap, rect: Self.squareProbe(square, g))
            print("[캐슬링] 교차 \(notation)(\(kind)): \(ink)px")
            #expect(ink > 0, "t=0.5 에 \(notation) 가 비어 있다 — 왕과 룩이 서로의 도착 칸을 지나가지 않는다")
        }
    }

    /// 끌어 놓아 **이미 도착해 있는** 말(`landed`)은 밀려나는 잡힌 말보다 **위**에 그려진다.
    /// 폰은 아직 끌어서 두지 않으므로 `landed` 는 늘 nil 이지만, 프레임이 그 칸을 실어 보내는 한 받아야 한다.
    @Test("landed 칸의 말은 밀려나는 잡힌 말 위에 그려진다")
    func theLandedPieceIsDrawnAboveTheCapturedOne() throws {
        let g = Self.geometry()
        let before = try Self.position(Self.pawnCaptureBeforeFEN)
        let move = ChessMove(from: try Self.square("d4"), to: try Self.square("e5"))
        let after = try #require(ChessRules.apply(move, to: before))
        let made = try #require(ChessMoveFlight.make(move: move, before: before, after: after,
                                                     matchID: "m", ply: 3, generation: 1, startedAt: Self.epoch))
        let dropped = try #require(made.withMoverLanded(), "끌어 놓은 사본이 안 만들어졌다")
        #expect(dropped.landed == (try Self.square("e5")))
        #expect(dropped.sliders.isEmpty, "잡기만 남아야 한다(왕·룩이 없는 수다)")

        let frame = try #require(dropped.frame(now: dropped.startedAt.addingTimeInterval(0.02)))
        #expect(frame.landed == (try Self.square("e5")))
        let withLanded = try Self.bitmap(after, flight: frame)
        // 같은 프레임에서 `landed` 만 지운 것 — 그러면 멈춘 배치의 흰 폰이 ⑤a 에 그려지고 잡힌 말이 그 **위**에 얹힌다.
        let withoutLanded = try Self.bitmap(after, flight: ChessFlightFrame(
            moving: frame.moving, leaving: frame.leaving, hidden: frame.hidden, landed: nil))
        let probe = Self.squareProbe(try Self.square("e5"), g)
        let above = Self.brightInk(withLanded, rect: probe)
        let below = Self.brightInk(withoutLanded, rect: probe)
        print("[landed] 흰 폰의 밝은 잉크: landed 로 맨 위 \(above)px · 그냥 두면 \(below)px")
        #expect(above > below, "landed 칸의 말이 맨 위로 안 올라갔다(\(above)px vs \(below)px)")
    }

    // MARK: - ⑨ 기본값 nil 이면 그림이 안 바뀐다

    @Test("flight 가 nil 이면 32말이 제자리에 있다(애니메이션이 생기기 전과 같은 그림)")
    func theBoardWithoutAFlightStillDrawsExactlyThirtyTwoPieces() throws {
        let g = Self.geometry()
        let bitmap = try Self.bitmap(ChessPosition.standard)
        let inked = Self.inkedSquares(bitmap, g)
        var expected: Set<String> = []
        for index in 0..<64 {
            guard let square = ChessSquare(index: index), ChessPosition.standard[square] != nil else { continue }
            expected.insert(square.notation)
        }
        print("[기본값] 말이 보이는 칸 \(inked.count)개 / 기대 \(expected.count)개")
        #expect(inked == expected, "빠진 칸 \(expected.subtracting(inked).sorted()) · 남는 칸 \(inked.subtracting(expected).sorted())")
    }

    // MARK: - ⑩ 배터리 계약 — flight 가 없으면 한 틱도 돌지 않는다

    @Test("paused 는 flight 가 nil 일 때만 참이다")
    func theTimelinePausesExactlyWhenThereIsNoFlight() throws {
        #expect(GamesChessFlightLoop.isPaused(flight: nil), "애니메이션이 없는데 paused 가 거짓이다 — 배터리 계약이 깨졌다")
        let flight = try Self.flight("e2", "e4", before: Self.standardFEN, after: Self.afterE4FEN)
        #expect(!GamesChessFlightLoop.isPaused(flight: flight), "애니메이션이 있는데 paused 가 참이다 — 말이 안 움직인다")
    }

    /// 그리고 판이 **그 값을 실제로 TimelineView 에 넣는다**(헬퍼만 맞고 뷰가 상수를 쓰면 위 시험은 공허하다).
    @Test("GamesChessBoard 의 TimelineView 가 paused 에 isPaused 를 넣고 주사율을 화면에서 읽는다")
    func theBoardWiresThePauseContractIntoTheTimeline() throws {
        let source = try Self.canvasSource()
        #expect(source.contains("paused: GamesChessFlightLoop.isPaused(flight: flight)"),
                "TimelineView 의 paused 가 `GamesChessFlightLoop.isPaused(flight: flight)` 가 아니다")
        #expect(source.contains("MiniGameFrameRate.minimumInterval(forRefreshRate: refreshHz)"),
                "프레임 간격이 코어 `MiniGameFrameRate` 를 안 지난다 — 주사율 저더 함정으로 되돌아간다")
        #expect(source.contains("GamesDisplay.maximumFramesPerSecond"),
                "주사율을 화면에서 안 읽는다(ProMotion 120 에서 60fps 로 돈다)")
    }

    /// 주석을 **걷어낸** 캔버스 소스. 안 걷어내면 설명을 지워야만 초록이 되는 시험이 된다.
    static func canvasSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(
            "Sources/CheckMobileKit/Games/GamesChessBoardCanvas.swift"), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hit = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<hit.lowerBound])
            }
            .joined(separator: "\n")
    }

    // MARK: - ⑪ 관전 판은 입력이 없다 (§6 ⑨)

    /// 없으면: 관전 화면이 실수로 선택·도착 점을 넘겨도 그려진다 — 관전자에게는 "내 차례·내 색" 이 없으므로
    /// 그 그림은 누를 수 없는 표시다. 부르는 쪽이 매번 빈 값을 넘기기를 믿지 않고 **판이 끊는다**.
    @Test("onTapSquare 가 nil 이면 선택·도착 점을 그리지 않는다(입력이 있으면 그린다)")
    func theSpectatorBoardDrawsNoSelectionOrTargets() throws {
        let position = ChessPosition.standard
        let selection = try Self.square("e2")
        let targets: Set<ChessSquare> = [try Self.square("e3"), try Self.square("e4")]

        func render(interactive: Bool) throws -> NSBitmapImageRep {
            try Self.bake(GamesChessBoard(
                position: position, flight: nil, whiteAtBottom: true,
                selection: selection, legalTargets: targets, lastMove: nil,
                onTapSquare: interactive ? { _ in } : nil
            ).frame(width: Self.side, height: Self.side))
        }

        let spectator = try render(interactive: false)
        let player = try render(interactive: true)
        let plain = try Self.bake(GamesChessBoard(
            position: position, flight: nil, whiteAtBottom: true,
            selection: nil, legalTargets: [], lastMove: nil, onTapSquare: nil
        ).frame(width: Self.side, height: Self.side))

        let spectatorVsPlain = try #require(CheckRenderDiff(try Self.cgImage(spectator), try Self.cgImage(plain)))
        let playerVsPlain = try #require(CheckRenderDiff(try Self.cgImage(player), try Self.cgImage(plain)))
        print("[관전] 관전 대 빈 값: \(spectatorVsPlain) / 대국 대 빈 값: \(playerVsPlain)")
        #expect(spectatorVsPlain.looksSame,
                "관전 판에 선택·도착 점이 그려졌다(\(spectatorVsPlain)) — §6 ⑨ 를 판이 안 끊었다")
        // ★ 기준선이 갈린다: 같은 값을 **입력이 있는** 판에 넘기면 그림이 달라진다. 안 갈리면 위 한 줄은
        //   "선택 덮개를 아무도 안 그린다" 로도 초록이다.
        #expect(playerVsPlain.looksDifferent,
                "대국 판에서도 선택·도착 점이 안 보인다(\(playerVsPlain)) — 기준선이 안 갈렸다")
    }

    // MARK: - ⑫ 판 크기 예산

    @Test("판 한 변은 높이 예산을 같이 보고 8 의 배수로 떨어진다")
    func theBoardSideRespectsTheHeightBudgetAndStaysAMultipleOfEight() {
        // 너비만 보면 세로가 짧은 화면에서 판 아래가 잘린다.
        #expect(GamesChessBoardMetrics.side(fitting: CGSize(width: 900, height: 420)) == 416,
                "높이 예산을 안 봤다(\(GamesChessBoardMetrics.side(fitting: CGSize(width: 900, height: 420))))")
        #expect(GamesChessBoardMetrics.side(fitting: CGSize(width: 361, height: 700)) == 360)
        for budget in [CGSize(width: 393, height: 800), CGSize(width: 320, height: 500), CGSize(width: 1_024, height: 1_024)] {
            let side = GamesChessBoardMetrics.side(fitting: budget)
            #expect(side.truncatingRemainder(dividingBy: 8) == 0, "\(budget) → \(side) 가 8 의 배수가 아니다 — 칸마다 반 픽셀이 남는다")
            #expect(side <= min(budget.width, budget.height), "\(budget) → \(side) 가 예산을 넘었다")
        }
        // 터무니없는 예산도 판을 안 깨뜨린다(cell 이 0 이면 모든 탭이 삼켜지고 그림이 빈다).
        for bad in [CGSize(width: 0, height: 0), CGSize(width: -40, height: 900),
                    CGSize(width: CGFloat.nan, height: CGFloat.nan)] {
            #expect(GamesChessBoardMetrics.side(fitting: bad) == GamesChessBoardMetrics.minimumSide, "\(bad) 에서 바닥값이 안 나왔다")
        }
    }

    // MARK: - ⑬ 탭 ↔ 칸 (뒤집기가 한 값을 지난다)

    @Test("square(at:) 은 64칸을 되돌려 준다 · 흑 판은 뒤집혀 있다 · 판 밖은 nil", arguments: [ChessColor.white, .black])
    func tappingTheCenterOfEverySquareGivesThatSquareBack(orientation: ChessColor) throws {
        let g = Self.geometry(orientation)
        for index in 0..<64 {
            let square = try #require(ChessSquare(index: index))
            #expect(g.square(at: g.center(of: square)) == square,
                    "\(orientation) 판에서 \(square.notation) 중앙을 눌렀는데 \(g.square(at: g.center(of: square))?.notation ?? "없음") 가 나왔다")
        }
        // 아래 왼쪽 모서리: 백 판은 a1, 흑 판은 h8 이다(뒤집기가 그리기와 같은 값을 지난다).
        let bottomLeft = CGPoint(x: g.cell * 0.5, y: g.side - g.cell * 0.5)
        #expect(g.square(at: bottomLeft)?.notation == (orientation == .white ? "a1" : "h8"))
        for outside in [CGPoint(x: -1, y: 10), CGPoint(x: 10, y: -1),
                        CGPoint(x: g.side, y: 10), CGPoint(x: 10, y: g.side)] {
            #expect(g.square(at: outside) == nil, "판 밖 \(outside) 가 칸으로 읽혔다")
        }
    }
}
