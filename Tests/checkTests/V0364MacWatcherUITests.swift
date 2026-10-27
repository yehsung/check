import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.65 맥 화면의 **관전자 수** — 세 게임(오목·체스·테트리스) × 세 자리(로비 "지금 대결 중" 줄 · 관전 화면 ·
// 대국자 본인 화면).
//
// 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다(이 저장소 관례). 그리고 **결과를 잰다** —
// "그 부품을 불렀는가"(모양)가 아니라 "그 자리에 잉크가 늘었는가 / 줄이 안 자랐는가 / 라벨이 뜻을 말하는가" 다.
// ★ 픽셀 **색**은 재지 않는다. 재는 것은 ① 잉크 양의 갈림 ② 다른 줄이 안 움직였는가 ③ 순수 글자값 셋이다.
//
// 기준선은 언제나 **같은 장면에서 수 한 칸만 바꾼 것**이다(기준선이 같은 입력이면 그 단언은 영원히 초록이다).

// MARK: - 렌더 도우미

private enum WUError: Error { case render }

@MainActor
private func wuBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw WUError.render }
    return bitmap
}

/// `rect`(pt) 안에서 **배경과 다른** 픽셀 수(잉크). 배경은 그 사각형의 가장 흔한 밝기가 아니라
/// `background` 사각형의 평균으로 잡는다 — 칩이 들어오든 말든 바탕은 같은 자리다.
private func wuInk(_ bitmap: NSBitmapImageRep, rect: CGRect, background: CGRect, tolerance: Int = 14) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    func box(_ value: CGRect) -> (x0: Int, x1: Int, y0: Int, y1: Int)? {
        let x0 = max(0, Int(value.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(value.maxX * 2))
        let y0 = max(0, Int(value.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(value.maxY * 2))
        return x0 <= x1 && y0 <= y1 ? (x0, x1, y0, y1) : nil
    }
    guard let base = box(background), let target = box(rect) else { return 0 }
    var sums = [0, 0, 0], samples = 0
    for y in base.y0...base.y1 {
        for x in base.x0...base.x1 {
            let o = y * bpr + x * spp
            for channel in 0..<3 { sums[channel] += Int(data[o + channel]) }
            samples += 1
        }
    }
    guard samples > 0 else { return 0 }
    let mean = sums.map { $0 / samples }
    var count = 0
    for y in target.y0...target.y1 {
        for x in target.x0...target.x1 {
            let o = y * bpr + x * spp
            if (0..<3).contains(where: { abs(Int(data[o + $0]) - mean[$0]) > tolerance }) { count += 1 }
        }
    }
    return count
}

/// 두 장이 `rect` 안에서 다른 픽셀 수. 창 전체를 같은 장면으로 두고 **수 한 칸만** 바꿨으므로
/// 이 값이 0 이면 "그 수가 그림까지 못 갔다" 는 뜻이다(모양이 아니라 결과를 재는 자리).
private func wuDiffPixels(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect,
                          threshold: Int = 24) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return -1 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(lhs.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return -1 }
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if (0..<min(3, spp)).contains(where: { abs(Int(a[o + $0]) - Int(b[o + $0])) > threshold }) { count += 1 }
        }
    }
    return count
}

/// 두 장이 `rect` 안에서 다른 **행들의 세로 범위**(pt). 다른 행이 없으면 nil.
/// 줄이 자랐는지를 이 한 값으로 잰다 — 첫 줄만 달라졌으면 범위가 그 줄 높이 안쪽이고,
/// 줄이 1pt라도 자라면 그 아래 줄이 통째로 밀려 범위가 목록 끝까지 늘어난다.
private func wuDiffBand(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect,
                        threshold: Int = 24) -> (top: CGFloat, bottom: CGFloat)? {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return nil }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(lhs.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return nil }
    var top = Int.max, bottom = Int.min
    for y in y0...y1 {
        var differs = false
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if (0..<min(3, spp)).contains(where: { abs(Int(a[o + $0]) - Int(b[o + $0])) > threshold }) {
                differs = true
                break
            }
        }
        if differs {
            top = min(top, y)
            bottom = max(bottom, y)
        }
    }
    guard top <= bottom else { return nil }
    return (CGFloat(top) / 2, CGFloat(bottom) / 2)
}

// MARK: - ① 글자값 (순수)

/// 없으면: 라벨을 "3" 으로만 읽어도, 두 수가 같은 글자를 내도 초록이다 — 보이스오버 사용자는 그 숫자가
/// 무엇의 3 인지 영영 모른다.
@Test
func v0364WatcherLabelSaysWhatTheNumberMeansAndChangesWithTheCount() {
    #expect(WatcherCountText.accessibility(1) == "관전자 1명")
    #expect(WatcherCountText.accessibility(12) == "관전자 12명")
    #expect(WatcherCountText.caption(3) == "3명이 보고 있어요")
    // ★ 기준선 갈림: 수가 다르면 글자도 다르다(같으면 아래 단언이 영원히 초록이다).
    #expect(WatcherCountText.accessibility(1) != WatcherCountText.accessibility(2))
    #expect(WatcherCountText.caption(1) != WatcherCountText.caption(2))
    // 숫자만 읽히면 뜻이 없다 — 라벨은 **숫자가 아니다**.
    #expect(WatcherCountText.accessibility(3) != "3")
    #expect(WatcherCountText.accessibility(3).contains("관전자"))
}

// MARK: - ② 칩 자체 — 0 이면 안 그린다 · 1 이상이면 그린다

/// 없으면: `count > 0` 게이트를 지워 "0" 칩이 모든 카드에 서도, 반대로 칩을 통째로 지워도 초록이다.
/// (스토어가 수를 모르는 창 — `*_watch_live` 가 없는 서버 — 도 0 으로 오므로 이 게이트 하나가
///  "아무도 안 본다" 와 "모른다" 를 같이 지운다.)
@MainActor
@Test
func v0364WatcherChipDrawsNothingAtZeroAndInkAtOneOrMore() throws {
    let frame = CGRect(x: 0, y: 0, width: 120, height: 28)
    func chip(_ count: Int) throws -> NSBitmapImageRep {
        try wuBitmap(
            WatcherCountChip(count: count, height: 18)
                .frame(width: frame.width, height: frame.height, alignment: .leading)
                .background(Color.black)
        )
    }
    let zero = try chip(0)
    let one = try chip(1)
    let many = try chip(42)
    let background = CGRect(x: 110, y: 0, width: 10, height: 28)   // 칩이 절대 닿지 않는 오른쪽 끝
    let zeroInk = wuInk(zero, rect: frame, background: background)
    let oneInk = wuInk(one, rect: frame, background: background)
    let manyInk = wuInk(many, rect: frame, background: background)
    print("[관전자 칩] 0 → \(zeroInk)px · 1 → \(oneInk)px · 42 → \(manyInk)px")
    #expect(zeroInk == 0, "0 인데 \(zeroInk)px 를 그렸다 — '0명이 보고 있어요' 가 카드마다 선다")
    #expect(oneInk > 80, "1 인데 그림이 \(oneInk)px 뿐이다 — 칩이 안 선다")
    // ★ 기준선 갈림: 두 자리 수는 한 자리보다 더 그린다(수가 그림까지 간다 — 상수 그림이 아니다).
    #expect(manyInk > oneInk, "42 와 1 이 같은 양을 그린다(\(manyInk) vs \(oneInk)) — 수가 그림에 안 닿는다")
}

// MARK: - 픽스처: 체스

private func wuChessUser(_ name: String, _ suffix: Int) -> ChessUser {
    ChessUser(id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))", displayName: name,
              avatarURL: nil, characterID: "fox", isWorking: true, isCapable: true, inMatch: false, center: nil)
}

private let wuFrozen = Date(timeIntervalSince1970: 2_000_000_000)
private let wuChessA = wuChessUser("대결자", 30)
private let wuChessB = wuChessUser("상대", 60)
private let wuChessMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

/// 로비 두 줄 — **첫 줄에만** 관전자 수를 넣는다(둘째 줄은 언제나 0). 줄이 자라면 둘째 줄이 밀린다.
@MainActor
private func wuChessLobby(firstWatchers: Int) -> ChessStore {
    let store = ChessStore()
    store.pollStepSeconds = 3_600
    store.hasLoadedLobby = true
    store.hasLoadedRanking = true
    store.spectatorFeaturesEnabled = true
    store.rubyBalance = 42
    store.record = ChessRecord(wins: 7, losses: 3, draws: 1)
    store.users = [wuChessA, wuChessB]
    store.liveMatches = [
        ChessLiveMatch(id: "live-0", a: wuChessA, b: wuChessB, stake: .five, startedAt: wuFrozen,
                       watchers: firstWatchers),
        ChessLiveMatch(id: "live-1", a: wuChessB, b: wuChessA, stake: .ten, startedAt: wuFrozen),
    ]
    return store
}

@MainActor
private func wuChessWatch(count: Int) -> ChessStore {
    let store = wuChessLobby(firstWatchers: 0)
    let fen = "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
    var watch = ChessSpectateState(id: "live-0", faces: [wuChessA, wuChessB], stake: 5)
    watch.black = wuChessB
    watch.white = wuChessA
    watch.fen = fen
    watch.position = ChessPosition(fen: fen)
    watch.plyCount = 6
    watch.turn = .white
    watch.clock = ChessServerClock(whiteMsLeft: 274_000, blackMsLeft: 192_000, incrementMs: 3_000,
                                   turnStartedAt: nil, running: .white)
    watch.startedAt = wuFrozen
    store.spectating = watch
    store.spectatorCount = count
    return store
}

@MainActor
private func wuChessPlaying(count: Int) -> ChessStore {
    let store = ChessStore()
    store.pollStepSeconds = 3_600
    store.phase = .playing
    store.rubyBalance = 32
    store.record = ChessRecord(wins: 7, losses: 3, draws: 1)
    let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    let position = ChessPosition(fen: fen)
    store.match = ChessMatchState(
        id: "match-1", stake: 10, myColor: .white, opponent: wuChessA, fen: fen, position: position,
        plyCount: 0, turn: .white, lastMove: nil, moves: [],
        clock: ChessServerClock(whiteMsLeft: 300_000, blackMsLeft: 300_000, incrementMs: 3_000,
                                turnStartedAt: nil, running: .white),
        isInCheck: false, legalMoves: position.map { ChessRules.legalMoves(in: $0) } ?? [],
        isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil,
        drawOfferBy: nil, drawOfferedByMe: false)
    store.spectatorCount = count
    return store
}

@MainActor
private func wuChessPanel(_ store: ChessStore) -> some View {
    ChessPanel(store: store, me: { wuChessMe }, clipsOverflowInsteadOfScroll: true)
}

private var wuChessBodyTop: CGFloat {
    ChessWindowLayout.contentPadding + ChessWindowLayout.headerHeight + ChessWindowLayout.headerSpacing
}

/// 체스 로비 오른쪽 열(400) — "지금 대결 중" 이 여기 있다.
private var wuChessLobbySide: CGRect {
    CGRect(x: ChessWindowLayout.contentPadding + ChessWindowLayout.lobbyListWidth + ChessWindowLayout.columnSpacing,
           y: wuChessBodyTop, width: ChessWindowLayout.lobbySideWidth, height: ChessWindowLayout.bodyHeight)
}

/// 체스 대국·관전 오른쪽 열(572).
private var wuChessSideColumn: CGRect {
    CGRect(x: ChessWindowLayout.contentPadding + ChessWindowLayout.boardSide + ChessWindowLayout.columnSpacing,
           y: wuChessBodyTop, width: ChessWindowLayout.sideColumnWidth, height: ChessWindowLayout.bodyHeight)
}

/// 판돈 칩 | 상태 상자 줄(두 사람 카드 아래). 관전자 칩은 **이 줄의 상태 상자 안**에 선다.
private var wuChessStatusRow: CGRect {
    CGRect(x: wuChessSideColumn.minX + 190 + ChessWindowLayout.matchSideSpacing,
           y: wuChessSideColumn.minY + ChessWindowLayout.playerCardHeight * 2
              + ChessWindowLayout.matchSideSpacing * 3,
           width: wuChessSideColumn.width - 190 - ChessWindowLayout.matchSideSpacing,
           height: ChessWindowLayout.stakeStatusMinHeight)
}

// MARK: - ③ 체스

/// 없으면: 로비 줄에서 관전자 수를 통째로 지워도, 반대로 칩 높이를 20 으로 올려 **카드가 자라도** 초록이다
/// (오목이 20 으로 두자 카드가 53 → 55 로 자라 렌더 시험 둘이 카드를 0장으로 셌다 — 같은 함정이다).
@MainActor
@Test
func v0364ChessLobbyRowShowsWatchersWithoutGrowingTheRow() throws {
    let base = try wuBitmap(wuChessPanel(wuChessLobby(firstWatchers: 0)))
    let seven = try wuBitmap(wuChessPanel(wuChessLobby(firstWatchers: 7)))
    let twelve = try wuBitmap(wuChessPanel(wuChessLobby(firstWatchers: 12)))
    let drawn = wuDiffPixels(base, seven, rect: wuChessLobbySide)
    // ★ 기준선 갈림: 7 과 12 도 **서로 다르게** 그려진다(상수 그림이면 여기가 0 이다).
    let counted = wuDiffPixels(seven, twelve, rect: wuChessLobbySide)
    print("[체스 로비] 0↔7 \(drawn)px · 7↔12 \(counted)px")
    #expect(drawn > 150, "관전자 7명인데 로비 줄이 0명일 때와 \(drawn)px 밖에 안 다르다 — 칩이 안 선다")
    #expect(counted > 0, "7 과 12 가 같은 그림이다 — 수가 그림까지 안 간다")

    // ★ 둘째 줄은 **한 픽셀도** 안 움직인다: 달라진 행의 세로 범위가 한 줄 높이 안쪽이다.
    let band = try #require(wuDiffBand(base, seven, rect: wuChessLobbySide), "아무 행도 안 달라졌다")
    print("[체스 로비] 달라진 띠 \(band.top)~\(band.bottom)pt (줄 높이 36)")
    #expect(band.bottom - band.top <= 40,
            "달라진 띠가 \(band.bottom - band.top)pt 다 — 첫 줄이 자라 아래 줄이 통째로 밀렸다")
}

/// 없으면: 관전 화면·대국 화면에서 `spectatorCount` 를 안 그려도, 0 일 때도 칩을 그려도 초록이다.
@MainActor
@Test
func v0364ChessWatchAndMatchScreensDrawTheWatcherCountInTheStakeRow() throws {
    let screens: [(String, @MainActor (Int) -> ChessStore)] = [("관전", wuChessWatch), ("대국", wuChessPlaying)]
    for (label, make) in screens {
        let zero = try wuBitmap(wuChessPanel(make(0)))
        let three = try wuBitmap(wuChessPanel(make(3)))
        let eleven = try wuBitmap(wuChessPanel(make(11)))
        let drawn = wuDiffPixels(zero, three, rect: wuChessStatusRow)
        let counted = wuDiffPixels(three, eleven, rect: wuChessStatusRow)
        print("[체스 \(label)] 0↔3 \(drawn)px · 3↔11 \(counted)px")
        #expect(drawn > 100, "\(label) 화면에서 관전자 3명이 \(drawn)px 밖에 안 더한다 — 칩이 안 선다")
        #expect(counted > 0, "\(label) 화면에서 3 과 11 이 같은 그림이다")
        // ★ 같은 자리의 **다른 것은 바뀌지 않았다**: 달라진 행이 그 줄 안쪽이다(판돈 줄 44pt).
        let band = try #require(wuDiffBand(zero, three, rect: wuChessSideColumn), "\(label): 아무 행도 안 달라졌다")
        #expect(band.top >= wuChessStatusRow.minY - 2 && band.bottom <= wuChessStatusRow.maxY + 2,
                "\(label): 달라진 띠가 판돈 줄 밖이다(\(band.top)~\(band.bottom) vs \(wuChessStatusRow.minY)~\(wuChessStatusRow.maxY))")
    }
}

// MARK: - 픽스처: 오목

private func wuGomokuUser(_ name: String, _ suffix: Int) -> GomokuUser {
    GomokuUser(id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))", displayName: name,
               avatarURL: nil, characterID: "fox", isWorking: true, isCapable: true, inMatch: true, center: nil)
}

private let wuGomokuA = wuGomokuUser("대결자", 30)
private let wuGomokuB = wuGomokuUser("상대", 60)
private let wuGomokuMe = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

@MainActor
private func wuGomokuLobby(firstWatchers: Int) -> GomokuStore {
    let store = GomokuStore()
    store.hasLoadedLobby = true
    store.rubyBalance = 42
    store.record = GomokuRecord(wins: 7, losses: 3, draws: 1)
    store.users = [wuGomokuA, wuGomokuB]
    store.liveMatches = [
        GomokuLiveMatch(id: "live-0", a: wuGomokuA, b: wuGomokuB, stake: .five, startedAt: wuFrozen,
                        watchers: firstWatchers),
        GomokuLiveMatch(id: "live-1", a: wuGomokuB, b: wuGomokuA, stake: .ten, startedAt: wuFrozen),
    ]
    return store
}

@MainActor
private func wuGomokuWatch(count: Int) -> GomokuStore {
    let store = wuGomokuLobby(firstWatchers: 0)
    var watch = GomokuSpectateState(id: "live-0", faces: [wuGomokuA, wuGomokuB], stake: 5)
    watch.black = wuGomokuA
    watch.white = wuGomokuB
    watch.turn = .black
    watch.startedAt = wuFrozen
    watch.moveCount = 4
    store.spectating = watch
    store.spectatorCount = count
    return store
}

@MainActor
private func wuGomokuPanel(_ store: GomokuStore) -> some View {
    GomokuPanel(store: store, me: { wuGomokuMe }, clipsOverflowInsteadOfScroll: true)
}

private var wuGomokuBodyTop: CGFloat {
    GomokuWindowLayout.contentPadding + GomokuWindowLayout.headerHeight + GomokuWindowLayout.headerSpacing
}

private var wuGomokuLobbySide: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding + GomokuWindowLayout.lobbyListWidth + GomokuWindowLayout.columnSpacing,
           y: wuGomokuBodyTop, width: GomokuWindowLayout.lobbySideWidth, height: GomokuWindowLayout.bodyHeight)
}

private var wuGomokuSideColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding + GomokuWindowLayout.boardSide + GomokuWindowLayout.columnSpacing,
           y: wuGomokuBodyTop, width: GomokuWindowLayout.sideColumnWidth, height: GomokuWindowLayout.bodyHeight)
}

/// 관전 상태 상자(판돈 칩 오른쪽 · 두 사람 카드 아래).
private var wuGomokuStatusBox: CGRect {
    CGRect(x: wuGomokuSideColumn.minX + GomokuWindowLayout.stakeChipWidth + GomokuWindowLayout.matchSideSpacing,
           y: wuGomokuSideColumn.minY + GomokuWindowLayout.playerCardHeight * 2
              + GomokuWindowLayout.matchSideSpacing * 2,
           width: wuGomokuSideColumn.width - GomokuWindowLayout.stakeChipWidth - GomokuWindowLayout.matchSideSpacing,
           height: GomokuWindowLayout.spectateStatusMinHeight)
}

// MARK: - ④ 오목

/// 없으면: 오목 로비 카드에서 관전자 수를 지워도, 칩 높이를 올려 카드가 53 → 55 로 자라도 초록이다.
@MainActor
@Test
func v0364GomokuLobbyCardShowsWatchersWithoutGrowingTheCard() throws {
    let base = try wuBitmap(wuGomokuPanel(wuGomokuLobby(firstWatchers: 0)))
    let nine = try wuBitmap(wuGomokuPanel(wuGomokuLobby(firstWatchers: 9)))
    let fourteen = try wuBitmap(wuGomokuPanel(wuGomokuLobby(firstWatchers: 14)))
    let drawn = wuDiffPixels(base, nine, rect: wuGomokuLobbySide)
    let counted = wuDiffPixels(nine, fourteen, rect: wuGomokuLobbySide)
    print("[오목 로비] 0↔9 \(drawn)px · 9↔14 \(counted)px")
    #expect(drawn > 150, "관전자 9명인데 로비 카드가 0명일 때와 \(drawn)px 밖에 안 다르다")
    #expect(counted > 0, "9 와 14 가 같은 그림이다 — 수가 그림까지 안 간다")
    let band = try #require(wuDiffBand(base, nine, rect: wuGomokuLobbySide), "아무 행도 안 달라졌다")
    print("[오목 로비] 달라진 띠 \(band.top)~\(band.bottom)pt (카드 높이 53)")
    #expect(band.bottom - band.top <= 56,
            "달라진 띠가 \(band.bottom - band.top)pt 다 — 카드가 자라 아래 카드가 밀렸다(C18)")
}

/// 없으면: 오목 관전 화면이 관전자 수를 안 그려도 초록이다(그 자리는 "관전자 수는 없다" 라는 옛 주석이
/// 지키고 있던 자리다 — 주석을 지워도 그림은 안 바뀐다).
@MainActor
@Test
func v0364GomokuWatchScreenDrawsTheWatcherCountInTheStatusBox() throws {
    let zero = try wuBitmap(wuGomokuPanel(wuGomokuWatch(count: 0)))
    let five = try wuBitmap(wuGomokuPanel(wuGomokuWatch(count: 5)))
    let twenty = try wuBitmap(wuGomokuPanel(wuGomokuWatch(count: 20)))
    let drawn = wuDiffPixels(zero, five, rect: wuGomokuStatusBox)
    let counted = wuDiffPixels(five, twenty, rect: wuGomokuStatusBox)
    print("[오목 관전] 0↔5 \(drawn)px · 5↔20 \(counted)px")
    #expect(drawn > 100, "관전 상태 상자에 관전자 수가 \(drawn)px 밖에 안 뜬다")
    #expect(counted > 0, "5 와 20 이 같은 그림이다")
    let band = try #require(wuDiffBand(zero, five, rect: wuGomokuSideColumn), "아무 행도 안 달라졌다")
    #expect(band.top >= wuGomokuStatusBox.minY - 2 && band.bottom <= wuGomokuStatusBox.maxY + 2,
            "달라진 띠가 상태 상자 밖이다(\(band.top)~\(band.bottom))")
}

// MARK: - 픽스처: 테트리스

private func wuTetrisUser(_ name: String, _ suffix: Int) -> TetrisDuelUser {
    TetrisDuelUser(id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))", displayName: name,
                   avatarURL: nil, characterID: "fox", isWorking: true, isCapable: true,
                   inMatch: true, isFocused: false)
}

private let wuTetrisA = wuTetrisUser("대결자", 30)
private let wuTetrisB = wuTetrisUser("상대", 60)

@MainActor
private func wuTetrisLobby(firstWatchers: Int, spectating: Bool = true) -> TetrisDuelStore {
    let store = TetrisDuelStore()
    store.pollStepSeconds = 3_600
    store.gameLoopStepSeconds = 3_600
    store.clock = { wuFrozen }
    store.hasLoadedLobby = true
    store.rankingEnabled = true
    store.spectatorFeaturesEnabled = spectating
    store.rubyBalance = 42
    store.record = TetrisDuelRecord(wins: 7, losses: 3, draws: 1)
    store.users = [wuTetrisA, wuTetrisB]
    store.liveMatches = [
        TetrisDuelLiveMatch(id: "live-0", a: wuTetrisA, b: wuTetrisB, stake: .five, startedAt: wuFrozen,
                            watchers: firstWatchers),
        TetrisDuelLiveMatch(id: "live-1", a: wuTetrisB, b: wuTetrisA, stake: .ten, startedAt: wuFrozen),
    ]
    return store
}

@MainActor
private func wuTetrisPanel(_ store: TetrisDuelStore) -> some View {
    TetrisDuelPanel(store: store, me: { wuChessMe }, clipsOverflowInsteadOfScroll: true)
}

private var wuTetrisBodyTop: CGFloat {
    TetrisDuelWindowLayout.contentPadding + TetrisDuelWindowLayout.headerHeight + TetrisDuelWindowLayout.headerSpacing
}

private var wuTetrisLobbySide: CGRect {
    CGRect(x: TetrisDuelWindowLayout.contentPadding + TetrisDuelWindowLayout.lobbyListWidth
              + TetrisDuelWindowLayout.columnSpacing,
           y: wuTetrisBodyTop, width: TetrisDuelWindowLayout.lobbySideWidth,
           height: TetrisDuelWindowLayout.bodyHeight)
}

/// 내 판이 선 스토어(진행 중). 대결 화면 위 띠의 관전자 칩은 **내 판을 보고 있는 사람 수**다
/// (`tetris_state`·`tetris_report` 응답이 싣는 값 — 로비 줄·관전 화면의 것과 **다른 자리**다).
@MainActor
private func wuTetrisPlaying(count: Int) -> TetrisDuelStore {
    let store = wuTetrisLobby(firstWatchers: 0)
    // `match` 대입은 didSet 으로 관전을 내린다 — 관전자 수는 **그 뒤에** 적는다.
    store.match = TetrisDuelMatchState(
        id: "7e7e0000-0000-4000-8000-000000000060", stake: 5, seed: 7, opponent: wuTetrisA,
        acceptedAt: wuFrozen, readyDeadline: wuFrozen.addingTimeInterval(24), startAt: nil, maxEnd: nil,
        meReady: true, opponentBoard: TetrisDuelOpponentBoard.empty, isFinished: false,
        outcome: nil, endReason: nil, rubyDelta: nil, finishedAt: nil)
    store.phase = .playing
    store.spectatorCount = count
    return store
}

/// 대결 화면 **위 띠**(판돈 칩 | 관전자 칩 | 경과 시간) — 본문 맨 위 34pt 한 줄.
private var wuTetrisMatchTopBar: CGRect {
    CGRect(x: TetrisDuelWindowLayout.contentPadding, y: wuTetrisBodyTop,
           width: TetrisDuelWindowLayout.innerWidth, height: TetrisDuelWindowLayout.matchTopBarHeight)
}

/// 테트리스 창 전체(위 띠 밖이 안 움직였는지 이 사각형으로 되묻는다).
private var wuTetrisWhole: CGRect {
    CGRect(x: 0, y: 0, width: TetrisDuelWindowLayout.contentSize.width,
           height: TetrisDuelWindowLayout.contentSize.height)
}

// MARK: - ⑤ 테트리스 로비

/// 없으면: 테트리스 로비 줄에서 관전자 수·[관전] 칩을 지워도 초록이고, 칩이 줄을 키워 아래 줄이 밀려도 초록이다.
@MainActor
@Test
func v0364TetrisLobbyRowShowsWatchersWithoutGrowingTheRow() throws {
    let base = try wuBitmap(wuTetrisPanel(wuTetrisLobby(firstWatchers: 0)))
    let four = try wuBitmap(wuTetrisPanel(wuTetrisLobby(firstWatchers: 4)))
    let sixteen = try wuBitmap(wuTetrisPanel(wuTetrisLobby(firstWatchers: 16)))
    let drawn = wuDiffPixels(base, four, rect: wuTetrisLobbySide)
    let counted = wuDiffPixels(four, sixteen, rect: wuTetrisLobbySide)
    print("[테트리스 로비] 0↔4 \(drawn)px · 4↔16 \(counted)px")
    #expect(drawn > 150, "관전자 4명인데 로비 줄이 0명일 때와 \(drawn)px 밖에 안 다르다")
    #expect(counted > 0, "4 와 16 이 같은 그림이다")
    let band = try #require(wuDiffBand(base, four, rect: wuTetrisLobbySide), "아무 행도 안 달라졌다")
    print("[테트리스 로비] 달라진 띠 \(band.top)~\(band.bottom)pt (줄 높이 32)")
    #expect(band.bottom - band.top <= 36,
            "달라진 띠가 \(band.bottom - band.top)pt 다 — 첫 줄이 자라 아래 줄이 밀렸다")
}

/// 없으면: **배선 한 줄이 빠져도**(`CheckApp.wireTetrisDuel` 의 `spectatorFeaturesEnabled`) 화면이 똑같아
/// 테트리스 관전이 통째로 죽은 채 전 스위트가 초록이다 — 로비 줄에 [관전] 칩이 서는 것이 그 배선의 유일한 흔적이다.
@MainActor
@Test
func v0364TetrisLobbyWatchChipAppearsOnlyWhenTheMasterSwitchIsOn() throws {
    let off = try wuBitmap(wuTetrisPanel(wuTetrisLobby(firstWatchers: 0, spectating: false)))
    let on = try wuBitmap(wuTetrisPanel(wuTetrisLobby(firstWatchers: 0, spectating: true)))
    let drawn = wuDiffPixels(off, on, rect: wuTetrisLobbySide)
    print("[테트리스 관전 스위치] 꺼짐↔켜짐 \(drawn)px")
    #expect(drawn > 300, "주 스위치를 켜도 [관전] 칩이 안 선다(\(drawn)px 차)")

    // ★ 그리고 **앱 배선이 실제로 켠다.** 화면만 그릴 줄 알고 아무도 안 켜면 이 기능은 사용자에게 0 이다.
    let app = try String(contentsOf: v0364RepoURL("Sources/check/CheckApp.swift"), encoding: .utf8)
    let body = try #require(v0364Between(v0364StripComments(app), "private func wireTetrisDuel() {", "\n    }"))
    #expect(body.contains("tetris.spectatorFeaturesEnabled = true"),
            "CheckApp 의 테트리스 배선에 관전 주 스위치가 없다 — 칩도 안 뜨고 요청도 한 번도 안 나간다")
}

// MARK: - ⑥ 테트리스 대국 화면 (내 판 위 띠)

/// 없으면: 대결 화면 위 띠(`TetrisDuelTopBar`)의 `WatcherCountChip(count: store.spectatorCount, …)` **한 줄을
/// 통째로 지워도** `--filter v0364` 가 전부 초록이다 — 로비 줄만 재고 있었기 때문이다. 그러면 대국자는
/// "내 판을 몇 명이 보고 있는지" 를 영영 못 본다(체스는 같은 자리를 관전·대국 두 화면 다 잰다).
/// 사각형은 **본문 맨 위 34pt 한 줄**(`matchTopBarHeight`)이고, 갈린 띠가 그 줄 **안**인지도 되묻는다 —
/// 칩이 줄을 키우면 아래 세 열이 통째로 밀린다.
@MainActor
@Test
func v0364TetrisMatchTopBarDrawsTheWatcherCountInTheStakeRow() throws {
    let zero = try wuBitmap(wuTetrisPanel(wuTetrisPlaying(count: 0)))
    let three = try wuBitmap(wuTetrisPanel(wuTetrisPlaying(count: 3)))
    let eleven = try wuBitmap(wuTetrisPanel(wuTetrisPlaying(count: 11)))
    let drawn = wuDiffPixels(zero, three, rect: wuTetrisMatchTopBar)
    // ★ 기준선 갈림: 3 과 11 도 **서로 다르게** 그려진다(상수 그림이면 여기가 0 이다).
    let counted = wuDiffPixels(three, eleven, rect: wuTetrisMatchTopBar)
    print("[테트리스 대국 위 띠] 0↔3 \(drawn)px · 3↔11 \(counted)px")
    #expect(drawn > 100, "대국 화면에서 관전자 3명이 \(drawn)px 밖에 안 더한다 — 위 띠에 칩이 안 선다")
    #expect(counted > 0, "대국 화면에서 3 과 11 이 같은 그림이다 — 수가 그림까지 안 간다")

    // ★ 창 전체를 봐도 달라진 행이 **위 띠 안**이다: 칩이 줄을 키우면 아래 세 열(내 판·상대 열·오른쪽 열)이
    //   통째로 밀려 띠가 창 끝까지 늘어난다.
    let band = try #require(wuDiffBand(zero, three, rect: wuTetrisWhole), "아무 행도 안 달라졌다")
    let bar = wuTetrisMatchTopBar
    print("[테트리스 대국 위 띠] 달라진 띠 \(band.top)~\(band.bottom)pt (띠 \(bar.minY)~\(bar.maxY))")
    #expect(band.top >= bar.minY - 2 && band.bottom <= bar.maxY + 2,
            "달라진 띠가 위 띠 밖이다(\(band.top)~\(band.bottom) vs \(bar.minY)~\(bar.maxY)) — 줄이 자라 아래가 밀렸다")
}

// MARK: - 소스 읽기 도우미

func v0364RepoURL(_ relative: String) -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { url.deleteLastPathComponent() }     // Tests/checkTests/<이 파일> → 저장소 루트
    return url.appendingPathComponent(relative)
}

/// `//` 줄 주석을 걷는다(이 저장소 규약 — 안 걷으면 설명을 지워야만 초록이 되는 시험이 된다).
func v0364StripComments(_ source: String) -> String {
    source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
        guard let range = line.range(of: "//") else { return String(line) }
        // 문자열 리터럴 안의 "//" 는 건드리지 않는다(이 파일들에는 URL 이 없지만 규약은 지킨다).
        let before = line[line.startIndex..<range.lowerBound]
        return before.filter { $0 == "\"" }.count % 2 == 0 ? String(before) : String(line)
    }.joined(separator: "\n")
}

func v0364Between(_ source: String, _ start: String, _ end: String) -> String? {
    guard let from = source.range(of: start) else { return nil }
    let rest = source[from.upperBound...]
    guard let to = rest.range(of: end) else { return nil }
    return String(rest[rest.startIndex..<to.lowerBound])
}
