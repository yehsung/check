import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.60 1:1 테트리스 **화면** 렌더 — 로비 · 순위 탭 · 판돈 창 · 받은 신청 · 준비 · 카운트다운 · 판(방해 줄 미터 · 상대 판) ·
// 120초 뒤 가속 표시 · 결과 승/패 · 기권 확인 · 미니게임 머리글 입구 묶음. 라이트·다크 둘 다.
//
// 전부 ImageRenderer(scale 2)로 그리고 `CHECK_SNAPSHOT_DIR/stills/` 에 PNG 를 남긴다(사람이 직접 열어 본다 —
// 디자인 작업에서 초록 테스트는 아무것도 증명하지 않는다). 단언은 **"그 자리에 그 잉크가 있는가"** 이고, 언제나
// 같은 장면에서 한 값만 바꾼 **기준선**과 견준다(기준선이 같은 입력이면 그 단언은 영원히 초록이다).
//
// 스토어는 네트워크 없는 `TetrisDuelStore()` 를 만들어 상태를 직접 채운다. 시계 둘(벽시계·단조)은 고정값을 주입해
// 경과 초·카운트다운·남은 초가 매번 같은 그림이 되게 한다.

// MARK: - 픽스처

private let trWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private let trUptime: TimeInterval = 1_000
private let trMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

private func trUser(_ name: String, _ suffix: Int, working: Bool = true, capable: Bool = true,
                    inMatch: Bool = false, focused: Bool = false, character: String? = "fox") -> TetrisDuelUser {
    TetrisDuelUser(id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))", displayName: name,
                   avatarURL: nil, characterID: character, isWorking: working, isCapable: capable,
                   inMatch: inMatch, isFocused: focused)
}

private let trMinsu = trUser("민수", 11, character: "fox")
private let trJunho = trUser("준호", 12, character: "squirrel")
private let trSeoyeon = trUser("서연", 16, character: "ghost")

private func trUsers() -> [TetrisDuelUser] {
    TetrisDuelStore.sortedForLobby([
        trUser("지영", 13, working: false),
        trMinsu,
        trUser("태화", 14, inMatch: true),
        trUser("옛버전사용자", 15, capable: false),
        trJunho,
        trSeoyeon,
        trUser("하늘", 17, working: false, focused: true),
        trUser("가장긴별명열두글자입니다", 19),
    ])
}

@MainActor
private func trStore() -> TetrisDuelStore {
    let store = TetrisDuelStore()
    store.pollStepSeconds = 3_600
    store.gameLoopStepSeconds = 3_600
    store.clock = { trWall0 }
    store.uptime = { trUptime }
    store.hasLoadedLobby = true
    store.hasLoadedRanking = true
    store.rankingEnabled = true
    store.rubyBalance = 42
    store.record = TetrisDuelRecord(wins: 7, losses: 3, draws: 1)
    return store
}

@MainActor
private func trLobbyStore(users: Bool = true, invites: Bool = true) -> TetrisDuelStore {
    let store = trStore()
    guard users else { return store }
    store.users = trUsers()
    store.liveMatches = [
        TetrisDuelLiveMatch(id: "live-1", a: trJunho, b: trSeoyeon, stake: .five, startedAt: trWall0),
        TetrisDuelLiveMatch(id: "live-2", a: trUser("태화", 14), b: trUser("바다", 18), stake: .ten, startedAt: trWall0),
    ]
    store.ranking = TetrisDuelRankingBoard(
        entries: trUsers().enumerated().map { index, user in
            TetrisDuelRankEntry(id: user.id, rank: index + 1, user: user, wins: 9 - index, losses: index,
                                draws: 1, points: 9 - index * 2)
        },
        me: TetrisDuelMyRank(rank: 2, wins: 7, losses: 3, draws: 1, points: 4),
        recordSince: trWall0)
    guard invites else { return store }
    store.incoming = [
        TetrisDuelInvite(id: "in-1", peer: trMinsu, stake: 5, expiresAt: trWall0.addingTimeInterval(48)),
        TetrisDuelInvite(id: "in-2", peer: trJunho, stake: 3, expiresAt: trWall0.addingTimeInterval(40)),
    ]
    store.outgoing = TetrisDuelInvite(id: "out-1", peer: trSeoyeon, stake: 10, expiresAt: trWall0.addingTimeInterval(31))
    return store
}

/// 상대 판 글자판(20행 · 위에서 아래로). 아래 두 줄이 방해 줄(G)이다.
private let trOpponentText: String = (Array(repeating: "..........", count: 11) + [
    "....T.....",
    "...TTT....",
    "........OO",
    "Z.......OO",
    "ZZ..SS..JJ",
    ".ZSS.LLLJ.",
    "IIII.L..J.",
    "GGGGG.GGGG",
    "GGGGG.GGGG",
]).joined()

private func trOpponentBoard(pending: Int = 1, toppedOut: Bool = false, empty: Bool = false,
                             ready: Bool = true) -> TetrisDuelOpponentBoard {
    let cells = empty ? TetrisDuelOpponentBoard.emptyCells : (TetrisDuelBoard.decode(trOpponentText) ?? [])
    return TetrisDuelOpponentBoard(cells: cells, hasBoard: !empty, lines: empty ? 0 : 4, attackSent: empty ? 0 : 2,
                                   pending: pending, toppedOut: toppedOut, ready: ready)
}

/// 내 판 — 맨 아래 두 줄이 방해 줄, 그 위에 굳은 조각들, 떨어지는 T 하나, 들어올 방해 줄 `pending`.
private func trGame(pending: [Int] = [2, 1], levelFloor: Int = 1, garbage: Bool = true) -> TetrisGame {
    let rows = [
        "Z.........",
        "ZZ.....OO.",
        ".Z..SS.OOJ",
        "LLLSS..IIJ",
        "L.JJJ..IJJ",
        "TTT..IIII.",
        ".T..LLL..L",
    ] + (garbage ? ["GGG.GGGGGG", "GGG.GGGGGG"] : [])
    return TetrisGame(seed: 7, board: TetrisGame.boardFixture(bottomRows: rows),
                      active: TetrisGame.ActivePiece(piece: .t, column: 3, row: 24),
                      next: [.i, .o, .s, .z, .l], heldPiece: .j, advance: 40, lines: 6,
                      pendingGarbage: pending, attackSentTotal: 3,
                      garbageMask: garbage ? TetrisGame.garbageMaskFixture(bottomRows: rows) : [],
                      levelFloor: levelFloor)
}

private func trMatch(finished: Bool = false, outcome: TetrisDuelOutcome? = nil, reason: TetrisDuelEndReason? = nil,
                     delta: Int? = nil, board: TetrisDuelOpponentBoard = trOpponentBoard(),
                     readyDeadline: Date? = nil, meReady: Bool = true) -> TetrisDuelMatchState {
    TetrisDuelMatchState(
        id: "7e7e0000-0000-4000-8000-000000000060", stake: 5, seed: 7, opponent: trMinsu,
        acceptedAt: trWall0.addingTimeInterval(-6), readyDeadline: readyDeadline ?? trWall0.addingTimeInterval(24),
        startAt: nil, maxEnd: nil, meReady: meReady, opponentBoard: board, isFinished: finished,
        outcome: outcome, endReason: reason, rubyDelta: delta, finishedAt: finished ? trWall0 : nil)
}

/// 판이 도는 스토어. `elapsed` 초 전에 판이 시작됐다(단조 시계 기준).
@MainActor
private func trPlayingStore(elapsed: TimeInterval = 74, game: TetrisGame = trGame(),
                            board: TetrisDuelOpponentBoard = trOpponentBoard()) -> TetrisDuelStore {
    let store = trStore()
    let match = trMatch(board: board)
    store.match = match
    store.duel = TetrisDuelSession(seed: 7, startedGame: game, startAt: trUptime - elapsed, simulated: elapsed)
    store.duelMatchID = match.id
    store.myStats = TetrisDuelMyStats(lines: game.lines, attackSent: game.attackSentTotal,
                                      pendingGarbage: game.pendingGarbageLines, levelFloor: game.levelFloor,
                                      toppedOut: false)
    store.phase = .playing
    return store
}

@MainActor
private func trFinishedStore(outcome: TetrisDuelOutcome, reason: TetrisDuelEndReason, delta: Int) -> TetrisDuelStore {
    let store = trPlayingStore(elapsed: 212, game: trGame(pending: [], levelFloor: 19))
    store.match = trMatch(finished: true, outcome: outcome, reason: reason, delta: delta,
                          board: trOpponentBoard(pending: 0, toppedOut: outcome == .won))
    store.duel?.finish()
    store.phase = .finished
    return store
}

// MARK: - 렌더 도우미

private enum TRError: Error { case render }

/// 창 화면 한 장(900×554 · scale 2). `scheme` 은 시스템 모양 — 창은 다크로 고정되지만, 시스템 의미 색이 새면 라이트에서 드러난다.
@MainActor
private func trRender(_ store: TetrisDuelStore, scheme: ColorScheme = .dark, tab: TetrisDuelLobbyTab? = nil,
                      stakeTarget: TetrisDuelUser? = nil, stake: TetrisDuelStake? = nil,
                      confirmResign: Bool = false, rules: Bool = false,
                      name: String? = nil) throws -> NSBitmapImageRep {
    let panel = TetrisDuelPanel(store: store, me: { trMe }, clipsOverflowInsteadOfScroll: true,
                                previewStakeTarget: stakeTarget, previewStakeSelection: stake,
                                previewConfirmResign: confirmResign, previewLobbyTab: tab, previewRules: rules)
        .environment(\.colorScheme, scheme)
    let bitmap = try trBitmap(panel)
    if let name {
        MiniGameSnapshots.save(bitmap, name: "tetris-duel-\(name)-\(scheme == .dark ? "dark" : "light").png", sub: "stills")
    }
    return bitmap
}

@MainActor
private func trBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw TRError.render }
    return bitmap
}

/// `rect`(pt) 안에서 `target`(0~255) 과 채널마다 `tolerance` 안쪽인 픽셀 수.
private func trCount(_ bitmap: NSBitmapImageRep, near target: (Int, Int, Int), tolerance: Int = 16, in rect: CGRect) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return -1 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var hits = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if abs(Int(data[o]) - target.0) <= tolerance, abs(Int(data[o + 1]) - target.1) <= tolerance,
               abs(Int(data[o + 2]) - target.2) <= tolerance { hits += 1 }
        }
    }
    return hits
}

/// 아주 밝은(거의 흰) 픽셀 수 — 큰 글자(카운트다운 숫자)의 잉크.
private func trBright(_ bitmap: NSBitmapImageRep, in rect: CGRect) -> Int {
    trCount(bitmap, near: (245, 245, 245), tolerance: 14, in: rect)
}

/// 두 그림에서 채널 차가 `threshold` 를 넘는 픽셀의 비율.
private func trDifferentShare(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, threshold: Int = 24) -> Double {
    guard let da = a.bitmapData, let db = b.bitmapData, a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh
    else { return 1 }
    let spp = a.samplesPerPixel, bpr = a.bytesPerRow
    var differ = 0
    for y in 0..<a.pixelsHigh {
        for x in 0..<a.pixelsWide {
            let o = y * bpr + x * spp
            for c in 0..<3 where abs(Int(da[o + c]) - Int(db[o + c])) > threshold {
                differ += 1
                break
            }
        }
    }
    return Double(differ) / Double(a.pixelsWide * a.pixelsHigh)
}

private func trByte(_ rgb: (r: Double, g: Double, b: Double)) -> (Int, Int, Int) {
    (Int((rgb.r * 255).rounded()), Int((rgb.g * 255).rounded()), Int((rgb.b * 255).rounded()))
}

/// 노란 상자 감지 — `TextField`·분절 `Picker` 가 섞이면 ImageRenderer 가 그 자리를 노란 상자(255,204,0)로 그린다.
private func trYellowPixels(_ bitmap: NSBitmapImageRep) -> Int {
    trCount(bitmap, near: (255, 204, 0), tolerance: 12,
            in: CGRect(x: 0, y: 0, width: Double(bitmap.pixelsWide) / 2, height: Double(bitmap.pixelsHigh) / 2))
}

// ── 창 안 자리(pt) — 레이아웃 상수에서만 나온다 ──
private var trBodyTop: CGFloat { TetrisDuelWindowLayout.contentPadding + TetrisDuelWindowLayout.headerHeight
    + TetrisDuelWindowLayout.headerSpacing }
private var trColumnsTop: CGFloat { trBodyTop + TetrisDuelWindowLayout.matchTopBarHeight
    + TetrisDuelWindowLayout.matchTopBarSpacing }
private var trCanvasRect: CGRect {
    CGRect(x: TetrisDuelWindowLayout.contentPadding,
           y: trColumnsTop + TetrisDuelWindowLayout.playerCardHeight + TetrisDuelWindowLayout.playerCardSpacing,
           width: TetrisDuelWindowLayout.canvasSize.width, height: TetrisDuelWindowLayout.canvasSize.height)
}
private var trOpponentRect: CGRect {
    CGRect(x: trCanvasRect.maxX + TetrisDuelWindowLayout.columnSpacing, y: trCanvasRect.minY,
           width: TetrisDuelWindowLayout.opponentColumnWidth, height: TetrisDuelWindowLayout.canvasSize.height)
}
private var trSideRect: CGRect {
    CGRect(x: trOpponentRect.maxX + TetrisDuelWindowLayout.columnSpacing, y: trColumnsTop,
           width: TetrisDuelWindowLayout.sideColumnWidth, height: TetrisDuelWindowLayout.matchColumnHeight)
}
private var trTopBarRect: CGRect {
    CGRect(x: TetrisDuelWindowLayout.contentPadding, y: trBodyTop,
           width: TetrisDuelWindowLayout.innerWidth, height: TetrisDuelWindowLayout.matchTopBarHeight)
}
/// 내 판의 미터 띠(논리 → 캔버스 실제 pt → 창 pt).
private var trMeterBand: CGRect {
    let t = MiniGameCanvas.transform(in: TetrisDuelWindowLayout.canvasSize, logicalSize: TetrisLayout.logicalSize)
    let logical = TetrisBoardPainter.meterTrackRect
    return CGRect(x: trCanvasRect.minX + t.origin.x + logical.minX * t.scale,
                  y: trCanvasRect.minY + t.origin.y + logical.minY * t.scale,
                  width: logical.width * t.scale, height: logical.height * t.scale)
}
private var trLobbyListRect: CGRect {
    CGRect(x: TetrisDuelWindowLayout.contentPadding, y: trBodyTop + TetrisDuelWindowLayout.lobbyTabHeight + 10,
           width: TetrisDuelWindowLayout.lobbyListWidth,
           height: TetrisDuelWindowLayout.bodyHeight - TetrisDuelWindowLayout.lobbyTabHeight - 10)
}

private let trAccent = (84, 171, 255)
private let trWorking = (89, 224, 161)
private let trDanger = (255, 115, 117)
private let trPending = (255, 184, 84)

// MARK: - 색 대비(순수)

@Test("방해 줄 회색: 무대 5종 우물·상대 미니 판 위 3:1 이상 · 조각 7색과 채널 차 0.20 이상 · 미터 빨강도 3:1 이상")
func theGarbageGrayAndTheMeterStandOut() {
    // 없으면: 회색이 우물에 묻혀 방해 줄이 빈칸처럼 보이거나(대비), 어떤 조각 색과 겹쳐 "내가 놓은 조각" 으로 읽힌다(채널 차).
    func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    func lum(_ c: (Double, Double, Double)) -> Double { 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2) }
    func contrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let la = lum(a), lb = lum(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
    func rgb(_ color: Color) -> (Double, Double, Double) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }
    func over(_ top: (Double, Double, Double), _ alpha: Double, _ bottom: (Double, Double, Double)) -> (Double, Double, Double) {
        (top.0 * alpha + bottom.0 * (1 - alpha), top.1 * alpha + bottom.1 * (1 - alpha), top.2 * alpha + bottom.2 * (1 - alpha))
    }
    let gray = (TetrisDuelPalette.garbageRGB.r, TetrisDuelPalette.garbageRGB.g, TetrisDuelPalette.garbageRGB.b)
    let meter = (TetrisDuelPalette.meterRGB.r, TetrisDuelPalette.meterRGB.g, TetrisDuelPalette.meterRGB.b)
    var worstGray = Double.infinity, worstMeter = Double.infinity
    for stage in MiniGameStage.all {
        for sky in [stage.skyTop, stage.skyBottom] {
            let well = over(rgb(TetrisPalette.wellColor), TetrisPalette.wellOpacity, rgb(sky))
            worstGray = min(worstGray, contrast(gray, well))
            worstMeter = min(worstMeter, contrast(meter, well))
        }
    }
    let mini = (TetrisDuelPalette.miniWellRGB.r, TetrisDuelPalette.miniWellRGB.g, TetrisDuelPalette.miniWellRGB.b)
    let miniGray = contrast(gray, mini)
    print("[대비] 방해 줄 회색 vs 우물 최소 \(String(format: "%.2f", worstGray)):1 · 미니 판 \(String(format: "%.2f", miniGray)):1"
          + " · 미터 \(String(format: "%.2f", worstMeter)):1")
    #expect(worstGray >= 3, "방해 줄이 가장 밝은 우물 위에서 \(worstGray):1 이다")
    #expect(miniGray >= 3, "상대 미니 판 위 방해 줄이 \(miniGray):1 이다")
    #expect(worstMeter >= 3, "미터 빨강이 우물에 묻힌다(\(worstMeter):1)")
    // 조각 7색 어느 것과도 갈린다(채널 최대 차 — 조각끼리의 문턱과 같다).
    var closest = (distance: Double.infinity, piece: TetrisGame.Piece.i)
    for piece in TetrisGame.Piece.allCases {
        let c = TetrisPalette.rgb[piece]!
        let d = max(abs(c.r - gray.0), max(abs(c.g - gray.1), abs(c.b - gray.2)))
        if d < closest.distance { closest = (d, piece) }
    }
    print("[대비] 방해 줄 회색 ↔ 가장 가까운 조각 \(closest.piece) 채널차 \(String(format: "%.3f", closest.distance))")
    #expect(closest.distance >= 0.20, "방해 줄 회색이 \(closest.piece) 조각과 \(closest.distance) 밖에 안 갈린다")
    // ★ 기준선: 회색이 실제로 무채색이다(색이 끼면 그 색 조각과 섞여 읽힌다).
    #expect(max(gray.0, gray.1, gray.2) - min(gray.0, gray.1, gray.2) < 0.12)
}

// MARK: - 렌더 · 스틸

@MainActor
@Suite("1:1 테트리스 창 렌더 · 스틸", .serialized)
struct TetrisDuelPanelRenderTests {
    @Test("로비: 상대 줄·[신청]·받은 신청 둘·보낸 신청 — 비어 있는 로비와 견준다")
    func theLobbyDrawsPeopleInvitesAndChallengeButtons() throws {
        // 없으면: 상대 목록·[신청] 단추가 안 그려지거나(빈 로비와 같은 그림), 노란 상자(입력 컨트롤)가 섞여도 모른다.
        let full = try trRender(trLobbyStore(), name: "lobby")
        _ = try trRender(trLobbyStore(), scheme: .light, name: "lobby")
        let empty = try trRender(trLobbyStore(users: false))
        let fullAccent = trCount(full, near: trAccent, tolerance: 20, in: trLobbyListRect)
        let emptyAccent = trCount(empty, near: trAccent, tolerance: 20, in: trLobbyListRect)
        print("[로비] 목록 칸 파랑(신청 단추) \(fullAccent)px · 빈 로비 \(emptyAccent)px")
        #expect(fullAccent > emptyAccent + 2_000, "상대 줄의 [신청] 단추가 안 보인다")
        #expect(trYellowPixels(full) == 0, "노란 상자가 그려졌다 — TextField·분절 Picker 가 섞였다")
        // 받은 신청 카드(오른쪽 열 맨 아래)의 [수락] 파랑 — 신청이 없으면 그 자리는 비어 있다.
        let side = CGRect(x: TetrisDuelWindowLayout.contentPadding + TetrisDuelWindowLayout.lobbyListWidth
                            + TetrisDuelWindowLayout.columnSpacing,
                          y: trBodyTop + TetrisDuelWindowLayout.bodyHeight - TetrisDuelWindowLayout.invitesMaxHeight,
                          width: TetrisDuelWindowLayout.lobbySideWidth, height: TetrisDuelWindowLayout.invitesMaxHeight)
        let noInvites = try trRender(trLobbyStore(invites: false), name: "lobby-no-invites")
        let withInvites = trCount(full, near: trAccent, tolerance: 20, in: side)
        let without = trCount(noInvites, near: trAccent, tolerance: 20, in: side)
        print("[로비] 신청 칸 파랑 \(withInvites)px · 신청 없음 \(without)px")
        #expect(withInvites > without + 1_000, "받은 신청 카드의 [수락] 이 안 보인다")
    }

    @Test("받은·보낸 신청 칸: 가장 긴 내용(카드 · 보낸 줄 · 두 줄 안내)의 자연 높이가 예산 안이다")
    func theInvitesBoxFitsItsBudget() throws {
        // 없으면: 예산을 상수 산수로만 믿다가 실제 칸이 더 길어 부모 열의 `.clipped()` 에 안내 줄 끝이 잘린다(체스에서 실측된 사고).
        let store = trLobbyStore()
        store.notice = "상대가 다른 대결 중이에요 — 이 안내는 일부러 길게 써서 두 줄로 접히는지 본다(가장 긴 안내 자리)"
        let full = try trBitmap(TetrisDuelInvitesBox(store: store).frame(width: TetrisDuelWindowLayout.lobbySideWidth))
        store.notice = nil
        let short = try trBitmap(TetrisDuelInvitesBox(store: store).frame(width: TetrisDuelWindowLayout.lobbySideWidth))
        let fullHeight = Double(full.pixelsHigh) / 2, shortHeight = Double(short.pixelsHigh) / 2
        print("[신청 칸] 두 줄 안내 \(fullHeight)pt · 안내 없음 \(shortHeight)pt / 예산 \(TetrisDuelWindowLayout.invitesMaxHeight)pt")
        #expect(fullHeight <= Double(TetrisDuelWindowLayout.invitesMaxHeight), "신청 칸이 예산을 넘는다 — 안내 끝이 잘린다")
        #expect(fullHeight > shortHeight + 20, "두 줄 안내가 칸을 안 키운다 — 이 시험이 가장 긴 경우를 안 잰다")
    }

    @Test("순위 탭: 1~3위 금빛 등수 · 판돈 창: 고른 판돈과 [신청하기]")
    func theRankingTabAndTheStakePrompt() throws {
        // 없으면: 순위 탭이 빈 안내만 그리거나(순위표가 안 선다), 판돈 창이 처음부터 판돈을 골라 둔 채 열린다.
        let store = trLobbyStore()
        let ranking = try trRender(store, tab: .ranking, name: "ranking")
        _ = try trRender(store, scheme: .light, tab: .ranking, name: "ranking")
        let noRanking = trLobbyStore()
        noRanking.ranking = nil
        let empty = try trRender(noRanking, tab: .ranking)
        let rankGold = trCount(ranking, near: trPending, tolerance: 20, in: trLobbyListRect)
        let emptyGold = trCount(empty, near: trPending, tolerance: 20, in: trLobbyListRect)
        print("[순위] 금빛 등수 \(rankGold)px · 순위 없음 \(emptyGold)px")
        #expect(rankGold > emptyGold + 100, "순위 탭이 순위를 안 그린다")

        let prompt = try trRender(store, stakeTarget: trMinsu, stake: .five, name: "stake-prompt")
        _ = try trRender(store, scheme: .light, stakeTarget: trMinsu, stake: .five, name: "stake-prompt")
        let unchosen = try trRender(store, stakeTarget: trMinsu, stake: nil, name: "stake-prompt-unchosen")
        let center = CGRect(x: 280, y: 150, width: 340, height: 260)
        let chosenBlue = trCount(prompt, near: trAccent, tolerance: 20, in: center)
        let unchosenBlue = trCount(unchosen, near: trAccent, tolerance: 20, in: center)
        print("[판돈] 고름 \(chosenBlue)px · 안 고름 \(unchosenBlue)px")
        #expect(chosenBlue > unchosenBlue + 3_000, "판돈을 골라도 단추·[신청하기] 가 안 선다(처음엔 아무것도 안 골라져야 한다)")
    }

    @Test("준비 · 카운트다운: 기다림 카드와 큰 숫자 3")
    func readyAndCountdown() throws {
        let ready = trStore()
        ready.match = trMatch(board: trOpponentBoard(pending: 0, empty: true, ready: false),
                              readyDeadline: trWall0.addingTimeInterval(24))
        ready.duel = TetrisDuelSession(seed: 7)
        ready.duelMatchID = ready.match?.id
        ready.phase = .ready
        let readyImage = try trRender(ready, name: "ready")
        _ = try trRender(ready, scheme: .light, name: "ready")

        let countdown = trStore()
        countdown.match = trMatch(board: trOpponentBoard(pending: 0, empty: true))
        var session = TetrisDuelSession(seed: 7)
        session.syncStart(startAtMs: 10_000, serverNowMs: 7_500, localNow: trUptime)   // 2.5초 뒤 시작 → "3"
        countdown.duel = session
        countdown.duelMatchID = countdown.match?.id
        countdown.phase = .countdown
        #expect(countdown.countdownSeconds() == 2.5)
        let countdownImage = try trRender(countdown, name: "countdown")
        _ = try trRender(countdown, scheme: .light, name: "countdown")
        let middle = CGRect(x: trCanvasRect.midX - 40, y: trCanvasRect.midY - 50, width: 80, height: 90)
        let digit = trBright(countdownImage, in: middle)
        let waiting = trBright(readyImage, in: middle)
        print("[카운트다운] 가운데 흰 잉크 \(digit)px · 준비 화면 \(waiting)px")
        #expect(digit > 800, "카운트다운 숫자가 안 보인다")
    }

    @Test("판: 내 판 방해 줄 회색 · 우물 왼쪽 빨간 미터 · 상대 미니 판 — 방해 줄 없는 판과 견준다")
    func thePlayingBoardShowsGarbageMeterAndTheOpponent() throws {
        // 없으면: 방해 줄이 조각 색으로 그려지거나(회색 0), 들어올 줄 미터가 안 그려지거나, 상대 판이 빈 채로 남는다.
        let gray = trByte(TetrisDuelPalette.garbageRGB)
        let red = trByte(TetrisDuelPalette.meterRGB)
        let playing = try trRender(trPlayingStore(), name: "playing")
        _ = try trRender(trPlayingStore(), scheme: .light, name: "playing")
        let clean = try trRender(trPlayingStore(game: trGame(pending: [], garbage: false),
                                                board: trOpponentBoard(pending: 0, empty: true)))

        let myGray = trCount(playing, near: gray, tolerance: 10, in: trCanvasRect)
        let cleanGray = trCount(clean, near: gray, tolerance: 10, in: trCanvasRect)
        let meter = trCount(playing, near: red, tolerance: 18, in: trMeterBand)
        let cleanMeter = trCount(clean, near: red, tolerance: 18, in: trMeterBand)
        let opponentGray = trCount(playing, near: gray, tolerance: 10, in: trOpponentRect)
        let cleanOpponentGray = trCount(clean, near: gray, tolerance: 10, in: trOpponentRect)
        print("[판] 내 판 회색 \(myGray)px(기준 \(cleanGray)) · 미터 빨강 \(meter)px(기준 \(cleanMeter))"
              + " · 상대 판 회색 \(opponentGray)px(기준 \(cleanOpponentGray))")
        #expect(myGray > cleanGray + 1_500, "내 판의 방해 줄이 회색으로 안 그려진다")
        #expect(meter > 300 && cleanMeter < 20, "들어올 방해 줄 미터가 우물 왼쪽에 안 선다")
        #expect(opponentGray > cleanOpponentGray + 300, "상대 판의 방해 줄이 안 보인다")
        // 미터는 들어올 줄 수만큼 자란다(3줄 vs 8줄 — 같은 장면에서 한 값만 바꾼다).
        let more = try trRender(trPlayingStore(game: trGame(pending: [5, 3])), name: "playing-8-incoming")
        let moreMeter = trCount(more, near: red, tolerance: 18, in: trMeterBand)
        print("[판] 미터 3줄 \(meter)px · 8줄 \(moreMeter)px")
        #expect(Double(moreMeter) > Double(meter) * 2, "미터가 들어올 줄 수를 안 따른다")
        #expect(trYellowPixels(playing) == 0)
    }

    @Test("120초 뒤: 위 띠에 '속도 올라가는 중' — 가속 전 판과 견준다 · 기권 확인 상태")
    func theRampIndicatorAndResignConfirm() throws {
        let before = try trRender(trPlayingStore(elapsed: 74, game: trGame(levelFloor: 1)))
        let ramp = trPlayingStore(elapsed: 134, game: trGame(levelFloor: 11))
        let after = try trRender(ramp, name: "ramp-120s")
        _ = try trRender(ramp, scheme: .light, name: "ramp-120s")
        let orangeBefore = trCount(before, near: trPending, tolerance: 20, in: trTopBarRect)
        let orangeAfter = trCount(after, near: trPending, tolerance: 20, in: trTopBarRect)
        print("[가속] 위 띠 주황 가속 전 \(orangeBefore)px · 뒤 \(orangeAfter)px")
        #expect(orangeAfter > orangeBefore + 300, "2분이 지났는데 '속도 올라가는 중' 이 안 선다")

        let confirm = try trRender(trPlayingStore(), confirmResign: true, name: "resign-confirm")
        let plain = try trRender(trPlayingStore())
        let actionRow = CGRect(x: trSideRect.minX, y: trSideRect.maxY - TetrisDuelWindowLayout.actionRowHeight,
                               width: trSideRect.width, height: TetrisDuelWindowLayout.actionRowHeight)
        let filled = trCount(confirm, near: trDanger, tolerance: 18, in: actionRow)
        let outline = trCount(plain, near: trDanger, tolerance: 18, in: actionRow)
        print("[기권] 확인 채움 빨강 \(filled)px · 첫 단추 \(outline)px")
        #expect(filled > outline + 2_000, "기권 확인이 첫 누름과 같은 그림이다 — 한 번 눌러 바로 기권된다")
    }

    @Test("결과: 승(초록 · +4) / 패(빨강 · −5) 카드 — 서로 다른 그림")
    func resultCardsWinAndLose() throws {
        let won = try trRender(trFinishedStore(outcome: .won, reason: .topout, delta: 4), name: "result-won")
        _ = try trRender(trFinishedStore(outcome: .won, reason: .topout, delta: 4), scheme: .light, name: "result-won")
        let lost = try trRender(trFinishedStore(outcome: .lost, reason: .topout, delta: -5), name: "result-lost")
        _ = try trRender(trFinishedStore(outcome: .lost, reason: .topout, delta: -5), scheme: .light, name: "result-lost")
        let card = CGRect(x: trSideRect.minX, y: trSideRect.minY, width: trSideRect.width, height: 90)
        let wonGreen = trCount(won, near: trWorking, tolerance: 18, in: card)
        let lostGreen = trCount(lost, near: trWorking, tolerance: 18, in: card)
        let wonRed = trCount(won, near: trDanger, tolerance: 18, in: card)
        let lostRed = trCount(lost, near: trDanger, tolerance: 18, in: card)
        print("[결과] 승 카드 초록 \(wonGreen)/빨강 \(wonRed) · 패 카드 초록 \(lostGreen)/빨강 \(lostRed)")
        #expect(wonGreen > lostGreen + 300 && lostRed > wonRed + 300, "승·패 카드가 색으로 갈리지 않는다")
        _ = try trRender(trFinishedStore(outcome: .draw, reason: .noShow, delta: 0), name: "result-no-show")
    }

    @Test("규칙 창: 다섯 줄(공격 · 방해 줄 · 승부 · 연결 · 판돈) — 공격 표와 수수료는 설계 값 그대로")
    func theRulesSheet() throws {
        // 없으면: 규칙 글이 설계(D2 공격 표 · 수수료)와 다른 숫자를 말해도 아무도 모른다.
        let sheet = try trRender(trLobbyStore(), rules: true, name: "rules")
        let plain = try trRender(trLobbyStore())
        #expect(trDifferentShare(sheet, plain, threshold: 12) > 0.3, "규칙 창이 안 덮였다")
        let titles = TetrisDuelText.rules.map(\.title)
        #expect(titles == ["공격", "방해 줄", "승부", "연결", "판돈"])
        let attack = TetrisDuelText.rules[0].detail
        #expect(attack.contains("2줄") && attack.contains("1줄") && attack.contains("3줄은 2줄") && attack.contains("4줄은 4줄"),
                "공격 표가 설계(2→1 · 3→2 · 4→4)와 다르다: \(attack)")
        #expect((1...4).map { TetrisGame.attackLines(lines: $0) } == [0, 1, 2, 4], "엔진 공격 표가 규칙 글과 갈렸다")
        // v0.3.64: 수수료를 없앴다 — 판돈 줄은 "판돈만큼 더"만 말하고 수수료 · 비율을 말하지 않는다.
        #expect(TetrisDuelText.rules[4].detail.contains("판돈만큼 더"))
        #expect(!TetrisDuelText.rules[4].detail.contains("수수료") && !TetrisDuelText.rules[4].detail.contains("%"))
        #expect(TetrisDuelText.rules[3].detail.contains("15초"))
    }

    @Test("라이트 시스템 모양에서도 창 그림이 거의 같다 — 시스템 의미 색이 새지 않는다")
    func lightAndDarkSchemesMatch() throws {
        // 없으면: `.primary`·기본 단추 색 같은 시스템 의미 색이 섞여도 모른다 — 창은 다크로 고정되지만 그 색은 라이트 판에서
        //        검은 글자가 되어 어두운 바탕에 묻힌다(렌더 테스트는 기본 라이트로 그리므로 여기서 먼저 드러난다).
        for (label, store) in [("로비", trLobbyStore()), ("판", trPlayingStore())] {
            let dark = try trRender(store, scheme: .dark)
            let light = try trRender(store, scheme: .light)
            let share = trDifferentShare(dark, light)
            print("[모양] \(label) 라이트·다크 다른 픽셀 \(String(format: "%.3f", share * 100))%")
            #expect(share < 0.01, "\(label): 라이트·다크가 \(share * 100)% 다르다 — 시스템 의미 색이 섞였다")
        }
    }

    @Test("미니게임 사이드바: 같이 하기 문(오목·체스·테트리스·큐브) 스틸 — v0.3.69 전에는 머리글 묶음")
    func theMiniGameSidebarEntriesStill() throws {
        let sidebar = MiniGameSidebar(selected: .tetris, isPlaying: false, isFrozen: false, invites: MiniGameDuelInvites(tetris: true),
                                      onSelect: { _ in }, onGomoku: {}, onChess: {}, onTetrisDuel: {}, onRummy: {})
            .frame(width: MiniGameWindowLayout.sidebarWidth, height: MiniGameWindowLayout.contentSize.height)
            .background(CheckTheme.background)
        let bitmap = try trBitmap(sidebar)
        MiniGameSnapshots.save(bitmap, name: "minigame-sidebar-entries.png", sub: "stills")
        let green = trCount(bitmap, near: trWorking, tolerance: 22,
                            in: CGRect(x: 0, y: 0, width: Double(bitmap.pixelsWide) / 2, height: Double(bitmap.pixelsHigh) / 2))
        print("[사이드바] 초록 \(green)px")
        #expect(green > 200, "사이드바에 대결 문이 안 보인다")
    }
}

// MARK: - 상대 상태 한 줄

/// "준비 완료" 는 판이 서기 전까지만이다 — 판 중·끝난 뒤에도 남으면 상대가 아직 안 들어온 것처럼 읽힌다(0.3.60 스틸에서 잡았다).
@MainActor
@Test("상대 상태 줄 — 준비 완료는 판 전까지만, 판 중엔 대결 중, 탑아웃·끝은 따로")
func tetrisDuelOpponentPresenceFollowsPhase() {
    func board(ready: Bool, toppedOut: Bool = false) -> TetrisDuelOpponentBoard {
        TetrisDuelOpponentBoard(cells: TetrisDuelOpponentBoard.emptyCells, hasBoard: ready, lines: 0, attackSent: 0,
                                pending: 0, toppedOut: toppedOut, ready: ready)
    }
    let label = TetrisDuelOpponentPresence.label
    #expect(label(board(ready: false), .ready, false) == "들어오는 중")
    #expect(label(board(ready: true), .ready, false) == "준비 완료")
    #expect(label(board(ready: true), .countdown, false) == "준비 완료")
    #expect(label(board(ready: true), .playing, false) == "대결 중")
    #expect(label(board(ready: true, toppedOut: true), .playing, false) == "꼭대기에 닿았어요")
    #expect(label(board(ready: true, toppedOut: true), .finished, true) == "꼭대기에 닿았어요")
    #expect(label(board(ready: true), .finished, true) == "대결 끝")
    // no_show: 상대가 끝내 안 들어왔으면 끝난 뒤에도 "들어오는 중" 이 아니라… 준비 안 한 사실이 남는다.
    #expect(label(board(ready: false), .finished, true) == "들어오는 중")
}
