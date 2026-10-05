import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.44 체스 말 이동 — **궤적을 픽셀에서 숫자로 뽑는** 독립 검증.
//
// 왜 또 재는가: 모델 단언(`ChessMoveFlight` 가 돌려주는 t·오프셋이 맞다)과 "사람 눈에 미끄러지는 것이 보인다"
// 는 **다른 명제**다. 모델이 완벽해도 뷰가 `flight` 를 안 보거나, 기하가 두 끝 사각형만 돌려주거나,
// 이징이 선형으로 깎여 있으면 화면은 여전히 순간이동한다. 그래서 여기서는 **그려진 비트맵만** 믿는다.
//
// 재는 법: 판에 **말이 하나뿐인 국면**을 만들어 그리면 '판 전체 잉크의 무게중심' 이 곧 그 말의 위치다
// (칸 색·덮개는 전부 중간 톤이고 말만 극단이라는 `ChessBoardView` 의 규칙이 이걸 가능하게 한다).
// 날고 있는 말만 따로 집어낼 길은 없으므로 **판을 비워서** 집어낸다.
//
// ★ 무게중심은 칸 중앙과 **같지 않다**(폰은 받침이 아래에 있어 잉크가 아래로 치우친다). 그래서 끝점 단언은
//   '칸 중앙' 이 아니라 **같은 말을 그 칸에 멈춰 세운 그림의 무게중심**과 비교한다 — 같은 모양이 평행이동만
//   하므로 그 기준이 곧 '칸 중앙' 의 말 좌표계 표현이다. 실측 치우침은 테스트가 출력한다.
//
// ★ 시각은 `0…duration` 을 **21 등분**해서 꽂는다(i/20). `isFinished` 가 `elapsed > duration` 이라
//   마지막 표본(i=20)도 프레임이 있고 거기서 t 가 정확히 1 이다.

// MARK: - 픽스처

private let tjT0 = Date(timeIntervalSince1970: 1_790_000_000)
private let tjScale: CGFloat = 2
/// 실제 창과 같은 한 변(608pt = 칸 76pt). 여기서 재야 "0.3칸" 이 화면의 0.3칸이다.
private let tjSide: CGFloat = 608

private func tjSquare(_ notation: String) -> ChessSquare {
    guard let square = ChessSquare(notation) else {
        fatalError("테스트 좌표가 틀렸다: \(notation)")
    }
    return square
}

/// 손으로 짠 국면. 빈 판에 말을 하나씩 놓는다 — 검증을 안 거치므로 왕이 없어도 된다(그림만 잰다).
private func tjPosition(_ pieces: [(String, ChessPiece)]) -> ChessPosition {
    var position = ChessPosition.empty
    for (notation, piece) in pieces { position[tjSquare(notation)] = piece }
    return position
}

private let tjGeometry = ChessBoardGeometry(side: tjSide, orientation: .white)

/// 재는 판. 덮개·좌표를 **전부 끈다** — 마지막 수 틴트나 좌표 글자가 섞이면 무게중심이 말 아닌 잉크에 끌린다.
@MainActor
private func tjBoard(_ position: ChessPosition?, _ frame: ChessFlightFrame?,
                     geometry: ChessBoardGeometry = tjGeometry) -> some View {
    ChessBoardView(position: position, geometry: geometry, showsCoordinates: false, flight: frame)
}

@MainActor
private func tjBitmap(_ view: some View) throws -> NSBitmapImageRep {
    // `CheckRenderSettle` 을 쓰는 까닭: ImageRenderer 가 한 내용의 첫 두 장을 뒤 장들과 다르게 굽는다
    // (채널당 ≤2). 무게중심은 수천 픽셀 평균이라 그 잡음에 둔하지만, **임계값 바로 위에 있는 픽셀**의
    // 수는 그 잡음으로도 갈린다 — 잡힌 말의 '칸 바깥' 판정이 그 경우다.
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: tjScale) else {
        throw TJError.renderFailed
    }
    return bitmap
}

private enum TJError: Error { case renderFailed }

// MARK: - 픽셀 측정기

/// **말 잉크** 판정 — 아주 밝거나(최대 ≥ 235) 아주 어둡다(최소 ≤ 55).
/// 칸은 밝은 (204,184,153) · 어두운 (112,89,71) 이라 둘 다 아니다(최대 ≤ 204 · 최소 ≥ 71).
private func tjIsPieceInk(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    max(r, max(g, b)) >= 235 || min(r, min(g, b)) <= 55
}

/// 비트맵 전체 말 잉크의 **무게중심**(pt)과 픽셀 수. 잉크가 없으면 nil.
private func tjCentroid(_ bitmap: NSBitmapImageRep) -> (point: CGPoint, count: Int)? {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return nil }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var sumX = 0.0, sumY = 0.0, count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            guard tjIsPieceInk(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) else { continue }
            sumX += Double(x) + 0.5
            sumY += Double(y) + 0.5
            count += 1
        }
    }
    guard count > 0 else { return nil }
    let s = Double(tjScale)
    return (CGPoint(x: sumX / Double(count) / s, y: sumY / Double(count) / s), count)
}

/// 두 비트맵이 **채널 임계값 이상** 다른 픽셀의 수와 그 픽셀들을 감싸는 상자(pt).
///
/// 임계값을 6 으로 두는 근거: `CheckRenderSettle` 을 지난 두 장은 각자 굳어 있어 같은 내용이면 **0** 이다.
/// 내용이 다를 때 섞여 들어올 수 있는 ImageRenderer 잡음의 실측 상한이 채널당 2 이므로 6 은 그 세 배다.
private func tjDiff(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep,
                    threshold: Int = 6) -> (count: Int, box: CGRect) {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
          lhs.samplesPerPixel >= 3, rhs.samplesPerPixel >= 3
    else { return (-1, .null) }
    let bprA = lhs.bytesPerRow, sppA = lhs.samplesPerPixel
    let bprB = rhs.bytesPerRow, sppB = rhs.samplesPerPixel
    var count = 0
    var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
    for y in 0..<lhs.pixelsHigh {
        for x in 0..<lhs.pixelsWide {
            let oa = y * bprA + x * sppA, ob = y * bprB + x * sppB
            var worst = 0
            for channel in 0..<3 {
                worst = max(worst, abs(Int(a[oa + channel]) - Int(b[ob + channel])))
            }
            guard worst >= threshold else { continue }
            count += 1
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard count > 0 else { return (0, .null) }
    let s = CGFloat(tjScale)
    return (count, CGRect(x: CGFloat(minX) / s, y: CGFloat(minY) / s,
                          width: CGFloat(maxX - minX + 1) / s, height: CGFloat(maxY - minY + 1) / s))
}

/// 칸 격자에서 가장 가까운 칸 중앙까지의 거리(**칸 단위**). 말 좌표계의 치우침을 뺀 위치로 잰다.
private func tjGridDistanceCells(_ inkCenter: CGPoint, bias: CGSize,
                                 geometry: ChessBoardGeometry) -> Double {
    let probe = CGPoint(x: inkCenter.x - bias.width, y: inkCenter.y - bias.height)
    var best = Double.greatestFiniteMagnitude
    for index in 0..<64 {
        guard let square = ChessSquare(index: index) else { continue }
        let center = geometry.center(of: square)
        let dx = Double(probe.x - center.x), dy = Double(probe.y - center.y)
        best = min(best, (dx * dx + dy * dy).squareRoot() / Double(geometry.cell))
    }
    return best
}

// MARK: - 궤적 뽑기

private struct TJTrack {
    let label: String
    let flight: ChessMoveFlight
    /// 21개 표본의 무게중심(pt). 잉크가 없으면 nil.
    let centers: [CGPoint?]
    /// 같은 말을 출발 칸·도착 칸에 **멈춰 세운** 그림의 무게중심.
    let restFrom: CGPoint
    let restTo: CGPoint
    /// 말 좌표계 치우침(무게중심 − 칸 중앙). 두 끝에서 같아야 한다.
    let bias: CGSize
}

@MainActor
private func tjTrack(_ label: String, piece: ChessPiece, from: String, to: String,
                     extra: [(String, ChessPiece)] = []) throws -> TJTrack {
    let move = ChessMove(from: tjSquare(from), to: tjSquare(to))
    let before = tjPosition([(from, piece)] + extra)
    let after = tjPosition([(to, piece)])
    guard let flight = ChessMoveFlight.make(move: move, before: before, after: after,
                                            matchID: "tj", ply: 7, generation: 1, startedAt: tjT0)
    else { throw TJError.renderFailed }

    // 멈춘 기준 둘. 날고 있는 그림과 **같은 뷰·같은 말**이라 모양에서 오는 치우침이 똑같이 들어간다.
    guard let restFromInk = tjCentroid(try tjBitmap(tjBoard(tjPosition([(from, piece)]), nil))),
          let restToInk = tjCentroid(try tjBitmap(tjBoard(after, nil)))
    else { throw TJError.renderFailed }

    let fromCenter = tjGeometry.center(of: move.from)
    let biasFrom = CGSize(width: restFromInk.point.x - fromCenter.x,
                          height: restFromInk.point.y - fromCenter.y)

    var centers: [CGPoint?] = []
    for i in 0...20 {
        let now = tjT0.addingTimeInterval(flight.duration * Double(i) / 20)
        let frame = flight.frame(now: now)
        let bitmap = try tjBitmap(tjBoard(after, frame))
        centers.append(tjCentroid(bitmap)?.point)
    }

    return TJTrack(label: label, flight: flight, centers: centers,
                   restFrom: restFromInk.point, restTo: restToInk.point, bias: biasFrom)
}

/// 출발→도착 방향으로 **남은 거리**(pt). 단조성은 이 수열로 잰다(2차원 거리는 비껴간 프레임을 못 잡는다).
private func tjRemaining(_ track: TJTrack) -> [Double?] {
    let dx = Double(track.restTo.x - track.restFrom.x)
    let dy = Double(track.restTo.y - track.restFrom.y)
    let length = (dx * dx + dy * dy).squareRoot()
    guard length > 0 else { return track.centers.map { _ in nil } }
    let ux = dx / length, uy = dy / length
    return track.centers.map { center in
        guard let center else { return nil }
        return (Double(track.restTo.x - center.x) * ux) + (Double(track.restTo.y - center.y) * uy)
    }
}

// MARK: - ① 폰 두 칸: 궤적이 단조롭고 이징이 보이는가

@MainActor
@Test
func theSlidingPawnWalksForwardWithoutTeleportingOrBacktracking() throws {
    let track = try tjTrack("폰 e2→e4", piece: ChessPiece(.white, .pawn), from: "e2", to: "e4")
    try tjAssertTrack(track, expectedSlideSeconds: 0.20, minimumOffGridAtThreePoints: 5)
}

// MARK: - ② 룩이 판을 가로지르기

@MainActor
@Test
func theRookCrossingTheBoardTakesTheCappedDurationAndStillSlides() throws {
    let track = try tjTrack("룩 a1→h1", piece: ChessPiece(.white, .rook), from: "a1", to: "h1")
    #expect(track.flight.slideDuration == 0.30,
            "일곱 칸인데 \(track.flight.slideDuration)s 다 — 뚜껑(0.30)이 안 걸렸다")
    try tjAssertTrack(track, expectedSlideSeconds: 0.30, minimumOffGridAtThreePoints: 6)
}

// MARK: - ③ 나이트는 격자를 가장 많이 벗어난다(대각선 성분)

@MainActor
@Test
func theKnightLeavesTheSquareGridOnMoreFramesThanAStraightMove() throws {
    let knight = try tjTrack("나이트 b1→c3", piece: ChessPiece(.white, .knight), from: "b1", to: "c3")
    try tjAssertTrack(knight, expectedSlideSeconds: 0.20, minimumOffGridAtThreePoints: 9)
}

/// 궤적 하나에 거는 단언 전부. 숫자는 전부 **출력**하므로 빨개질 때 무엇이 틀렸는지 로그에서 읽힌다.
@MainActor
private func tjAssertTrack(_ track: TJTrack, expectedSlideSeconds: TimeInterval,
                           minimumOffGridAtThreePoints: Int) throws {
    let remaining = tjRemaining(track)
    let total = remaining[0] ?? 0

    print("[\(track.label)] slide=\(track.flight.slideDuration)s duration=\(track.flight.duration)s")
    print("[\(track.label)] 멈춘 기준: from=\(tjFmt(track.restFrom)) to=\(tjFmt(track.restTo)) " +
          "치우침=(\(tjF(track.bias.width)), \(tjF(track.bias.height))) 총거리=\(tjF(total))pt")
    print("[\(track.label)] 남은거리(pt): " +
          remaining.map { $0.map { tjF($0) } ?? "nil" }.joined(separator: " "))

    // 표본마다 잉크가 **있어야** 한다 — 하나라도 nil 이면 그 프레임에 말이 사라졌다는 뜻이다.
    #expect(!track.centers.contains(where: { $0 == nil }),
            "말이 안 그려진 프레임이 있다 — 날고 있는 동안 판이 비었다")

    #expect(track.flight.slideDuration == expectedSlideSeconds,
            "미끄러짐 길이가 \(track.flight.slideDuration)s 다(사양 \(expectedSlideSeconds)s)")

    // ① 단조성. 두 층으로 잰다 — **모델은 엄격히**, **픽셀은 측정한 래스터화 바닥만큼 느슨하게**.
    //
    // ★ 왜 픽셀을 엄격히 못 재는가(실측): 무게중심을 "극단 픽셀이냐" 는 **이진 판정**으로 뽑으므로,
    //   말이 반 픽셀 움직일 때 평평한 가로 테두리(폰 받침은 폭 73px)의 한 줄이 통째로 켜지거나 꺼진다.
    //   잉크 4,742px 짜리 폰에서 그 한 줄이 무게중심에서 20pt 떨어져 있으면 73/4742 × 20 = 0.31pt 가
    //   한 번에 튄다. 그리고 easeOut 의 끝 기울기가 0 이라 마지막 표본들의 **모델 이동이 0.02pt** 뿐이어서
    //   그 틀림이 부호를 뒤집는다. 실측: 폰 두 칸의 i=18 에서 모델 +0.152pt 가 측정 −0.43pt 로 찍혔다.
    //   그래서 "그려진 위치가 모델을 따라가는가"(잔차)와 "모델이 되돌아가는가"(엄격)를 따로 잰다.
    let total2 = total
    let modelRemaining: [Double] = (0...20).map {
        total2 * (1 - ChessMoveFlight.easeOut(Double($0) / 20))
    }
    var worstResidual = 0.0
    for i in 0...20 {
        guard let measured = remaining[i] else { continue }
        worstResidual = max(worstResidual, abs(measured - modelRemaining[i]))
    }
    var modelBacktrack = 0.0, worstBacktrack = 0.0
    for i in 0..<20 {
        modelBacktrack = max(modelBacktrack, modelRemaining[i + 1] - modelRemaining[i])
        guard let a = remaining[i], let b = remaining[i + 1] else { continue }
        worstBacktrack = max(worstBacktrack, b - a)
    }
    print("[\(track.label)] 모델 되돌아감 \(tjF(modelBacktrack, 4))pt · 측정 되돌아감 \(tjF(worstBacktrack))pt · " +
          "모델↔픽셀 최대 잔차 \(tjF(worstResidual))pt")
    #expect(modelBacktrack <= 0, "모델이 \(tjF(modelBacktrack, 4))pt 되돌아간다 — 이징이 단조롭지 않다")
    // 그려진 자리가 모델을 1pt(2px) 안에서 따라간다. 실측 최대는 0.58pt 였다.
    #expect(worstResidual <= 1.0,
            "그려진 무게중심이 모델에서 \(tjF(worstResidual))pt 벗어난다 — 뷰가 다른 자리를 그린다")
    // 측정 되돌아감의 상한은 잔차 두 개 몫(≤2pt)이고, 실측 최대는 0.40pt = 칸의 0.5% 다. 1pt 를 넘으면
    // 래스터화로 설명이 안 되므로 그때는 **실제로 뒤로 간 것**이다.
    #expect(worstBacktrack <= 1.0,
            "궤적이 \(tjF(worstBacktrack))pt 되돌아간다 — 래스터화 바닥(≤1pt)을 넘었다, 말이 뒤로 갔다")

    // ② 격자를 벗어난 프레임 수. 세 임계값으로 센다(사양이 쓴 0.3 칸과 그 아래 둘).
    var offGrid = [0.3: 0, 0.2: 0, 0.1: 0]
    var distances: [Double] = []
    for center in track.centers {
        guard let center else { distances.append(0); continue }
        let d = tjGridDistanceCells(center, bias: track.bias, geometry: tjGeometry)
        distances.append(d)
        for threshold in offGrid.keys where d >= threshold { offGrid[threshold, default: 0] += 1 }
    }
    print("[\(track.label)] 격자 거리(칸): " + distances.map { tjF($0, 3) }.joined(separator: " "))
    print("[\(track.label)] 격자 밖 프레임: ≥0.3칸 \(offGrid[0.3]!) · ≥0.2칸 \(offGrid[0.2]!) · " +
          "≥0.1칸 \(offGrid[0.1]!) (21 중)")
    #expect(offGrid[0.3]! >= minimumOffGridAtThreePoints,
            "0.3칸 이상 벗어난 프레임이 \(offGrid[0.3]!)개뿐이다")
    // 0.1 칸 = 7.6pt 는 76pt 칸에서 눈에 또렷한 어긋남이다. 절반 이상이 여기 걸려야 "칸 사이를 지난다" 다.
    #expect(offGrid[0.1]! >= 11,
            "0.1칸(7.6pt) 이상 벗어난 프레임이 \(offGrid[0.1]!)개뿐이다 — 칸 중앙만 밟는다")

    // ③ 이징 — 앞 절반이 뒤 절반보다 더 많이 움직인다. easeOut(0.5)=0.875 → 7배가 사양의 값이다.
    if let r0 = remaining[0], let r10 = remaining[10], let r20 = remaining[20] {
        let first = r0 - r10, second = r10 - r20
        let ratio = second > 0.0001 ? first / second : Double.infinity
        print("[\(track.label)] 앞 절반 \(tjF(first))pt · 뒤 절반 \(tjF(second))pt · 비 \(tjF(ratio, 2))")
        #expect(first > second, "앞 절반(\(tjF(first))pt)이 뒤 절반(\(tjF(second))pt)보다 안 크다 — 선형이다")
        // 선형이면 1.0, easeOutCubic 이면 7.0. 4 는 그 사이를 **확실히** 가른다.
        #expect(ratio >= 4, "앞/뒤 비가 \(tjF(ratio, 2)) 다 — 이징이 깎였다(선형은 1.0, easeOutCubic 은 7.0)")
    } else {
        Issue.record("절반 비교에 쓸 프레임이 비었다")
    }

    // ④ 끝점 — 첫 표본은 출발, 마지막 표본은 도착. 기준은 같은 말을 멈춰 세운 그림이다.
    if let first = track.centers[0], let last = track.centers[20] {
        let dFirst = hypot(Double(first.x - track.restFrom.x), Double(first.y - track.restFrom.y))
        let dLast = hypot(Double(last.x - track.restTo.x), Double(last.y - track.restTo.y))
        print("[\(track.label)] 끝점 오차: 출발 \(tjF(dFirst, 3))pt · 도착 \(tjF(dLast, 3))pt")
        #expect(dFirst <= 1.0, "t=0 무게중심이 출발 칸에서 \(tjF(dFirst, 3))pt 벗어났다")
        #expect(dLast <= 1.0, "t=1 무게중심이 도착 칸에서 \(tjF(dLast, 3))pt 벗어났다")
    } else {
        Issue.record("끝점 프레임이 비었다")
    }

    // ⑤ 실제로 그려질 프레임 수 — `TimelineView` 에 넘어가는 간격은 주사율에서 온다.
    for hz in [60, 120, 144, 165] {
        let interval = MiniGameFrameRate.minimumInterval(forRefreshRate: hz)
        let frames = Int(track.flight.duration / interval)
        print("[\(track.label)] \(hz)Hz 간격 \(tjF(interval * 1000, 3))ms → \(frames) 프레임")
        #expect(frames >= 8,
                "\(hz)Hz 에서 \(frames) 프레임뿐이다 — 8장 미만이면 '미끄러진다'로 안 보인다(상수가 틀렸다)")
    }
}

// MARK: - ④ 잡힌 말이 칸을 벗어나는가

/// 퀸 d1 → d5 가 흑 폰을 잡는 수. 밀림 방향이 (0, +1) 한 축이라 '원래 칸 바깥' 이 화면에서 **위쪽 하나**다.
///
/// 잡힌 말만 따로 재기 위해 `ChessFlightFrame(moving: [], leaving: …)` 로 **미끄러지는 말을 뺀** 프레임을
/// 뷰에 넘긴다. 값은 모델이 계산한 그대로 쓴다(여기서 숫자를 만들지 않는다) — 섞이면 퀸의 잉크가
/// 잡힌 말의 잉크로 세어진다.
@MainActor
@Test
func theCapturedPieceIsPushedOutOfItsSquareAndFadesLast() throws {
    let move = ChessMove(from: tjSquare("d1"), to: tjSquare("d5"))
    let queen = ChessPiece(.white, .queen)
    let victim = ChessPiece(.black, .pawn)
    let before = tjPosition([("d1", queen), ("d5", victim)])
    let after = tjPosition([("d5", queen)])
    guard let flight = ChessMoveFlight.make(move: move, before: before, after: after,
                                            matchID: "tj", ply: 9, generation: 1, startedAt: tjT0)
    else { throw TJError.renderFailed }

    #expect(flight.knockout?.square == tjSquare("d5"))
    #expect(flight.knockout?.pushFile == 0 && flight.knockout?.pushRank == 1)
    #expect(flight.duration == 0.33250, "잡기 수 전체 길이가 \(flight.duration)s 다(사양 0.3325s)")

    let victimRect = tjGeometry.rect(of: tjSquare("d5"))

    // 기준 둘. ★ **갈려야 하는 기준선이다**: 멈춘 판에는 '칸 바깥 잉크' 가 0 이어야 한다.
    //   빈 판(미끄러지는 말도 잡힌 말도 없음)이 차분의 바닥이고, 멈춘 판은 d5 에 퀸이 선 그림이다.
    let hidden = Set([tjSquare("d5")])
    let blank = try tjBitmap(tjBoard(after, ChessFlightFrame(moving: [], leaving: nil, hidden: hidden)))
    let stopped = try tjBitmap(tjBoard(after, nil))

    let stoppedDiff = tjDiff(stopped, blank)
    print("[잡기] 멈춘 판 차분 \(stoppedDiff.count)px 상자 \(tjFmt(stoppedDiff.box))")
    #expect(stoppedDiff.count > 0, "멈춘 판과 빈 판이 같다 — d5 의 퀸이 안 그려졌다(기준선이 무의미하다)")
    let stoppedOutside = !victimRect.insetBy(dx: -0.5, dy: -0.5).contains(stoppedDiff.box)
    #expect(stoppedOutside == false,
            "멈춘 판의 잉크가 d5 바깥 \(tjFmt(stoppedDiff.box)) 까지 나간다 — 바깥 판정이 못 쓴다")

    var framesOutside = 0
    var framesWithInk = 0
    var maxOvershootCells = 0.0
    var rows: [String] = []
    for i in 0...20 {
        let now = tjT0.addingTimeInterval(flight.duration * Double(i) / 20)
        guard let full = flight.frame(now: now), let leaving = full.leaving else {
            rows.append("i=\(i) leaving 없음")
            continue
        }
        let only = ChessFlightFrame(moving: [], leaving: leaving, hidden: hidden)
        let bitmap = try tjBitmap(tjBoard(after, only))
        let diff = tjDiff(bitmap, blank)
        guard diff.count > 0 else {
            rows.append("i=\(i) k=\(tjF(flight.knockoutProgress(now: now), 3)) 잉크 0")
            continue
        }
        framesWithInk += 1
        // 밀림이 위쪽(+rank)이므로 '칸 바깥' 은 d5 사각형 **위** 다.
        let overshoot = Double(victimRect.minY - diff.box.minY) / Double(tjGeometry.cell)
        if overshoot > 0 {
            framesOutside += 1
            maxOvershootCells = max(maxOvershootCells, overshoot)
        }
        rows.append("i=\(i) k=\(tjF(flight.knockoutProgress(now: now), 3)) " +
                    "오프셋=\(tjF(leaving.rankOffset, 3))칸 비율=\(tjF(leaving.scale, 3)) " +
                    "불투명=\(tjF(leaving.opacity, 3)) 잉크=\(diff.count)px " +
                    "칸밖=\(tjF(overshoot, 3))칸")
    }
    for row in rows { print("[잡기] " + row) }
    print("[잡기] 잉크 있는 프레임 \(framesWithInk)/21 · 칸 밖 프레임 \(framesOutside) · " +
          "최대 돌출 \(tjF(maxOvershootCells, 3))칸")

    #expect(framesOutside >= 3,
            "잡힌 말이 원래 칸을 벗어난 프레임이 \(framesOutside)개뿐이다 — 그 자리에서 사라진 것과 같다")
    #expect(maxOvershootCells >= 0.1,
            "최대 돌출이 \(tjF(maxOvershootCells, 3))칸이다 — 칸 안에서만 꿈틀거린다")

    // 밀림이 **먼저**, 흐려짐이 **나중**. 오프셋이 이미 나간 동안 불투명도가 1 인 프레임이 있어야 한다.
    var pushedWhileOpaque = 0
    for i in 0...20 {
        let now = tjT0.addingTimeInterval(flight.duration * Double(i) / 20)
        guard let leaving = flight.frame(now: now)?.leaving else { continue }
        if leaving.opacity >= 0.999 && leaving.rankOffset >= 0.05 { pushedWhileOpaque += 1 }
    }
    print("[잡기] 불투명 1 인 채 0.05칸 넘게 밀린 프레임 \(pushedWhileOpaque)")
    #expect(pushedWhileOpaque >= 1,
            "밀리기 시작할 때 이미 흐려지고 있다 — '그 자리에서 사라진다'와 구분되지 않는다")
}

// MARK: - ⑤ 흑으로 두는 사람은 **반대쪽**으로 밀려야 한다

/// 같은 잡기 수를 판을 뒤집어 그린다. 밀림 방향은 모델이 판 좌표(+rank)로 담으므로, 뒤집힌 화면에서는
/// 같은 값이 **화면 아래쪽**이 되어야 한다 — 부호를 안 뒤집으면 흑으로 두는 사람만 잡힌 말이
/// 잡은 말 쪽으로 되밀려 들어온다(사양의 함정 그대로다).
@MainActor
@Test
func theCapturedPieceIsPushedTheOtherWayOnAFlippedBoard() throws {
    let move = ChessMove(from: tjSquare("d1"), to: tjSquare("d5"))
    let before = tjPosition([("d1", ChessPiece(.white, .queen)), ("d5", ChessPiece(.black, .pawn))])
    let after = tjPosition([("d5", ChessPiece(.white, .queen))])
    guard let flight = ChessMoveFlight.make(move: move, before: before, after: after,
                                            matchID: "tj", ply: 9, generation: 1, startedAt: tjT0)
    else { throw TJError.renderFailed }

    let hidden = Set([tjSquare("d5")])
    // 밀림이 가장 크면서 아직 흐려지지 않은 자리 — 실측 i=10(k=0.244, 오프셋 0.313칸, 불투명 0.664)이다.
    let now = tjT0.addingTimeInterval(flight.duration * 10 / 20)
    guard let leaving = flight.frame(now: now)?.leaving else { throw TJError.renderFailed }

    for orientation in [ChessColor.white, ChessColor.black] {
        let geometry = ChessBoardGeometry(side: tjSide, orientation: orientation)
        let blank = try tjBitmap(tjBoard(after, ChessFlightFrame(moving: [], leaving: nil, hidden: hidden),
                                         geometry: geometry))
        let pushed = try tjBitmap(tjBoard(after, ChessFlightFrame(moving: [], leaving: leaving, hidden: hidden),
                                          geometry: geometry))
        let diff = tjDiff(pushed, blank)
        let cell = geometry.rect(of: tjSquare("d5"))
        // 잡힌 말의 잉크 무게중심이 칸 중앙에서 화면 y 로 얼마나 벗어났는가(pt, + 는 아래).
        let dy = Double(diff.box.midY - cell.midY)
        print("[뒤집기] \(orientation == .white ? "백" : "흑") 판: 칸 \(tjFmt(cell)) 잉크 \(tjFmt(diff.box)) " +
              "Δy=\(tjF(dy))pt (\(diff.count)px)")
        #expect(diff.count > 0, "잡힌 말이 안 그려졌다(\(orientation))")
        if orientation == .white {
            #expect(dy < -4, "백 판에서 잡힌 말이 위로(+rank) 안 밀렸다 — Δy=\(tjF(dy))pt")
        } else {
            #expect(dy > 4, "흑 판에서 잡힌 말이 아래로 안 밀렸다 — 뒤집기 부호가 빠졌다, Δy=\(tjF(dy))pt")
        }
    }
}

// MARK: - ⑥ 캐슬링은 **둘 다** 미끄러진다

/// 왕만 미끄러지고 룩이 순간이동하면 "성이 어떻게 됐지" 가 그대로 남는다. 왕만 담은 프레임과 차분해서
/// 룩이 **자기 궤적 위에** 그려지는지 본다.
@MainActor
@Test
func castlingSlidesTheRookAsWellAsTheKing() throws {
    let move = ChessMove(from: tjSquare("e1"), to: tjSquare("g1"))
    let before = tjPosition([("e1", ChessPiece(.white, .king)), ("h1", ChessPiece(.white, .rook))])
    let after = tjPosition([("g1", ChessPiece(.white, .king)), ("f1", ChessPiece(.white, .rook))])
    guard let flight = ChessMoveFlight.make(move: move, before: before, after: after,
                                            matchID: "tj", ply: 11, generation: 1, startedAt: tjT0)
    else { throw TJError.renderFailed }

    #expect(flight.sliders.count == 2, "미끄러지는 말이 \(flight.sliders.count)개다 — 룩이 빠졌다")
    #expect(flight.sliders.first?.piece.kind == .rook && flight.sliders.last?.piece.kind == .king,
            "순서가 \(flight.sliders.map { String($0.piece.fenCharacter) }) 다 — 왕이 마지막(위)이어야 한다")
    #expect(flight.frame(now: tjT0)?.hidden == Set([tjSquare("f1"), tjSquare("g1")]),
            "숨길 칸이 둘이 아니다 — 캐슬링에서 말이 넷으로 보인다")

    let now = tjT0.addingTimeInterval(flight.duration * 0.5)
    guard let full = flight.frame(now: now), full.moving.count == 2 else { throw TJError.renderFailed }
    let kingOnly = ChessFlightFrame(moving: [full.moving[1]], leaving: nil, hidden: full.hidden)

    let both = try tjBitmap(tjBoard(after, full))
    let king = try tjBitmap(tjBoard(after, kingOnly))
    let diff = tjDiff(both, king)
    let kingBox = tjGeometry.rect(from: tjSquare("e1"), to: tjSquare("g1"), t: full.moving[1].t)
    print("[캐슬링] t=\(tjF(full.moving[1].t, 3)) 왕 상자 \(tjFmt(kingBox)) · 룩 몫 잉크 \(diff.count)px " +
          "상자 \(tjFmt(diff.box))")
    #expect(diff.count > 500, "왕만 그린 그림과 \(diff.count)px 밖에 안 다르다 — 룩이 안 미끄러진다")
    // 룩은 h1 에서 f1 로 **왼쪽으로** 가므로 왕보다 왼쪽에 있다(둘이 스치는 구간이다).
    #expect(diff.box.midX < kingBox.midX,
            "룩 몫 잉크가 왕 오른쪽에 있다 — 룩이 엉뚱한 칸에서 그려진다")
}

// MARK: - ⑦ 가장 짧은 수도 프레임이 모이는가

/// 한 칸 수(0.175s)가 **최악의 경우**다 — 여기서 프레임이 모자라면 상수가 틀렸다는 뜻이다.
@Test
func theShortestMoveStillGetsEnoughFrames() {
    let shortest = ChessMoveFlight.slideSeconds(distance: 1)
    #expect(shortest == 0.175, "한 칸 길이가 \(shortest)s 다(사양 0.175s)")
    var rows: [String] = []
    for hz in [24, 30, 48, 60, 75, 90, 120, 144, 165, 240] {
        let interval = MiniGameFrameRate.minimumInterval(forRefreshRate: hz)
        let frames = Int(shortest / interval)
        rows.append("\(hz)Hz→\(frames)")
        // 24·30Hz 는 맥 내장·외장 화면에 없는 값이라 단언하지 않고 **수만 남긴다**(아래 ★).
        if hz >= 48 {
            #expect(frames >= 8,
                    "\(hz)Hz 에서 한 칸 수가 \(frames) 프레임뿐이다 — 사람 눈에 '미끄러진다'로 안 보인다")
        }
    }
    print("[프레임 수] 한 칸 0.175s: " + rows.joined(separator: " · "))
    // ★ 48Hz 아래는 8장을 못 채운다(24Hz 4장 · 30Hz 5장). 맥에 그 주사율 화면이 없으므로 단언하지 않지만
    //   숫자는 남긴다 — `MiniGameFrameRate` 가 24·30 을 **그대로 쓰도록** 적혀 있어서 코드상으로는 닿는 길이다.
}

// MARK: - ⑧ 사람이 볼 띠 PNG

/// 한 수를 0 / 0.25 / 0.5 / 0.75 / 1.0 다섯 장으로 이어 붙인 띠. 실제 FEN 과 엔진이 만든 `after` 로 굽는다 —
/// 손으로 짠 국면은 '그럴듯한 그림' 이지만 '실제로 일어나는 수' 는 아니다.
@MainActor
@Test
func theFourMoveStripsAreWrittenForHumanReview() throws {
    let cases: [(name: String, title: String, fen: String, from: String, to: String)] = [
        ("01-pawn-one-step", "① 폰 한 칸 e2→e3",
         "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "e2", "e3"),
        ("02-rook-across", "② 룩이 판을 가로지르기 a1→h1",
         "4k3/5ppp/8/8/5K2/8/5PPP/R7 w - - 0 1", "a1", "h1"),
        ("03-queen-takes-pawn", "③ 퀸이 폰을 잡기 d1×d5",
         "r3k2r/pp3ppp/8/3p4/8/8/PP3PPP/3QK3 w - - 0 1", "d1", "d5"),
        ("04-castling", "④ 캐슬링 e1→g1 (룩 h1→f1)",
         "r3k2r/pppq1ppp/2n2n2/8/8/2N2N2/PPPQ1PPP/R3K2R w KQkq - 0 1", "e1", "g1")
    ]

    for item in cases {
        guard let before = ChessPosition(fen: item.fen) else {
            Issue.record("FEN 이 안 읽힌다: \(item.fen)")
            continue
        }
        let move = ChessMove(from: tjSquare(item.from), to: tjSquare(item.to))
        // ★ `after` 를 엔진으로 만든다 — 손으로 짠 배치는 수가 **합법인지**를 한 글자도 증명하지 않는다.
        guard let after = ChessRules.apply(move, to: before) else {
            Issue.record("합법 수가 아니다: \(item.title)")
            continue
        }
        guard let flight = ChessMoveFlight.make(move: move, before: before, after: after,
                                                matchID: "strip", ply: 1, generation: 1, startedAt: tjT0)
        else {
            Issue.record("애니메이션이 안 만들어진다: \(item.title)")
            continue
        }
        print("[띠] \(item.title): 미끄러지는 말 \(flight.sliders.count) · " +
              "잡힘 \(flight.knockout.map { "\($0.piece.fenCharacter)@\($0.square.notation)" } ?? "없음") · " +
              "길이 \(flight.duration)s")

        let bitmap = try tjBitmap(tjStrip(title: item.title, flight: flight, after: after, move: move))
        tjSaveStrip(bitmap, name: "\(item.name).png")
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
    }

    print("[띠] 저장 위치: \(tjStripDirectory.path)")
}

/// 띠 한 장. 판 변을 300pt 로 줄인다(5장 가로로 이어 붙여도 3,000px 안에 든다).
@MainActor
private func tjStrip(title: String, flight: ChessMoveFlight,
                     after: ChessPosition, move: ChessMove) -> some View {
    let geometry = ChessBoardGeometry(side: 300, orientation: .white)
    let fractions: [Double] = [0, 0.25, 0.5, 0.75, 1.0]
    return VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Color.white)
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(fractions.enumerated()), id: \.offset) { _, fraction in
                let now = tjT0.addingTimeInterval(flight.duration * fraction)
                VStack(spacing: 6) {
                    ChessBoardView(
                        position: after,
                        geometry: geometry,
                        lastMove: move,              // 실제 화면과 같다 — 마지막 수 틴트가 두 칸에 깔린다.
                        showsCoordinates: true,
                        flight: flight.frame(now: now)
                    )
                    Text(String(format: "%.0f%% · %.0fms", fraction * 100, flight.duration * fraction * 1000))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
        }
    }
    .padding(16)
    .background(Color(white: 0.12))
}

private var tjStripDirectory: URL {
    let base = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-snapshots", isDirectory: true)
    return base.appendingPathComponent("chess-flight-strip", isDirectory: true)
}

private func tjSaveStrip(_ bitmap: NSBitmapImageRep, name: String) {
    let dir = tjStripDirectory
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: dir.appendingPathComponent(name))
}

// MARK: - 출력 서식

private func tjF(_ value: Double, _ places: Int = 2) -> String {
    value.isFinite ? String(format: "%.\(places)f", value) : "∞"
}

private func tjFmt(_ point: CGPoint) -> String {
    "(\(tjF(Double(point.x))), \(tjF(Double(point.y))))"
}

private func tjFmt(_ rect: CGRect) -> String {
    rect.isNull ? "없음"
        : "(\(tjF(Double(rect.minX))), \(tjF(Double(rect.minY))))–" +
          "(\(tjF(Double(rect.maxX))), \(tjF(Double(rect.maxY))))"
}
