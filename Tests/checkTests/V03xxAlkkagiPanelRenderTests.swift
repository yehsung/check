import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 1:1 알까기 **화면** 렌더(SPEC v1.1 §5 · §7.2 U 줄) — 로비 3열 · '곧 열려요' · 판돈 덮개 · 규칙 덮개 · 판 중(판돈 칩 · 관전자 수 칩 ·
// 놓친 차례 경고 · 기권 확인 · 돌 수 카드) · 결과 승/패/무/무효 · 관전(배치 중 · 진행) · 받은 신청 배너 · 판 그림이 0.3.80 과 같음.
//
// 전부 ImageRenderer(scale 2)로 `CheckRenderSettle` 이 굳힌 뒤 재고, `CHECK_SNAPSHOT_DIR/alkkagi-v2-render/` 에 PNG 를 남긴다
// (사람이 직접 열어 본다 — 디자인 작업에서 초록 시험은 아무것도 증명하지 않는다). 목록은 `clipsOverflowInsteadOfScroll`
// 갈래로 그린다(ImageRenderer 는 ScrollView 안을 못 그린다). 대화 카드(되살리기용 · 0.3.80 모양)는 AppKit 판으로 남긴다
// (`CheckTextEditor` 는 ImageRenderer 노란 칸 — 화면에 올리지 않는 창 객체의 호스팅 뷰를 AppKit 이 그린다).
// 상태는 C1 표면의 `package internal(set)` 칸에 바로 심는다(스토어에 서비스 · host 가 없어 네트워크 0).
// 화면은 **잉크**로 재고, 단언마다 결과가 갈리는 기준선 짝(빈 가게 · 칩 0 · 다른 결과 · 옛 판)을 둔다.

// MARK: - 픽스처

private let arWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private let arNowMs = arWall0.timeIntervalSince1970 * 1000

private func arID(_ n: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", n) }

private let arMe = AlkkagiPeer(id: arID(13), displayName: "영식", characterID: "shiba")
private let arMinsu = AlkkagiPeer(id: arID(11), displayName: "민수", characterID: "fox")
private let arJunho = AlkkagiPeer(id: arID(12), displayName: "준호", characterID: "squirrel")
private let arTaehwa = AlkkagiPeer(id: arID(14), displayName: "태화", characterID: "ghost")
private let arSeoyeon = AlkkagiPeer(id: arID(16), displayName: "서연", characterID: "ghost")

private func arUser(_ peer: AlkkagiPeer, working: Bool = true, inMatch: Bool = false, capable: Bool = true,
                    focused: Bool = false) -> AlkkagiLobbyUser {
    AlkkagiLobbyUser(id: peer.id, displayName: peer.displayName, characterID: peer.characterID, isWorking: working,
                     inMatch: inMatch, isCapable: capable, isFocused: focused)
}

/// 로비 사람 여섯(다섯 상태 — 근무 중 · '—' · 대결 중 · 집중 모드 · 앱 업데이트 필요).
private let arUsers: [AlkkagiLobbyUser] = [
    arUser(arMinsu),
    arUser(arJunho, inMatch: true),
    arUser(arSeoyeon, working: false),
    arUser(arTaehwa, inMatch: true),
    arUser(AlkkagiPeer(id: arID(17), displayName: "하늘", characterID: "fox"), working: false, focused: true),
    arUser(AlkkagiPeer(id: arID(15), displayName: "옛버전사용자", characterID: "squirrel"), capable: false),
]

@MainActor
private func arStore(populated: Bool = true) -> AlkkagiOnlineStore {
    let store = AlkkagiOnlineStore(clock: { arWall0 })
    store.me = arMe
    store.hasLoadedLobby = true
    store.spectatorFeaturesEnabled = true
    store.rankingEnabled = true
    store.rubyBalance = 42
    guard populated else {
        store.ranking = AlkkagiRankingBoard(entries: [], me: nil)
        return store
    }
    store.record = AlkkagiRecord(wins: 7, losses: 3, draws: 1)
    store.users = arUsers
    store.ranking = AlkkagiRankingBoard(
        entries: [
            AlkkagiRankEntry(rank: 1, id: arMinsu.id, displayName: "민수", characterID: "fox", wins: 9, losses: 1, draws: 1),
            AlkkagiRankEntry(rank: 2, id: arJunho.id, displayName: "준호", characterID: "squirrel", wins: 8, losses: 3),
            AlkkagiRankEntry(rank: 3, id: arSeoyeon.id, displayName: "서연", characterID: "ghost", wins: 6, losses: 3, draws: 2),
            AlkkagiRankEntry(rank: 4, id: arMe.id, displayName: "영식", characterID: "shiba", wins: 7, losses: 3, draws: 1),
        ],
        me: AlkkagiMyRank(rank: 4, wins: 7, losses: 3, draws: 1))
    store.liveMatches = [AlkkagiLiveMatch(id: arID(950), black: arJunho, white: arTaehwa, stake: 10, shotCount: 6, watchers: 2)]
    store.incoming = [
        AlkkagiInvite(id: arID(800), opponent: arMinsu, expiresAtMs: arNowMs + 48_000, stake: 5),
        AlkkagiInvite(id: arID(801), opponent: arSeoyeon, expiresAtMs: arNowMs + 40_000, stake: 3),
        AlkkagiInvite(id: arID(802), opponent: arTaehwa, expiresAtMs: arNowMs + 30_000, stake: 10),
    ]
    store.outgoing = AlkkagiInvite(id: arID(810), opponent: arSeoyeon, expiresAtMs: arNowMs + 52_000, stake: 3)
    return store
}

private func arStones(_ edit: (inout [AlkkagiGame.Stone]) -> Void = { _ in }) -> [AlkkagiGame.Stone] {
    var stones = AlkkagiGame().stones
    for index in stones.indices { stones[index].isPlaced = true }
    edit(&stones)
    return stones
}

/// 판 중(0.3.80 비교 그림 `alkkagi-2-play` 와 **같은 돌 자리**) — 나 흑(영식) · 상대 백(민수) · 내 차례 · 4수째 · 백 1개 밖 · 마감 21초.
private func arAimingStones() -> [AlkkagiGame.Stone] {
    arStones { stones in
        stones[0].position = AlkkagiVector(x: 120, y: 420)
        stones[2].position = AlkkagiVector(x: 300, y: 330)
        stones[6].isOut = true
        stones[7].position = AlkkagiVector(x: 280, y: 210)
        stones[8].position = AlkkagiVector(x: 430, y: 180)
    }
}

private func arAiming(stake: Int? = 5, watchers: Int = 2, missed: Int = 1) -> AlkkagiMatch {
    AlkkagiMatch(id: arID(900), revision: 9, phase: .aiming, currentPlayer: .black, myColor: .black,
                 black: arMe, white: arMinsu, stones: arAimingStones(), deadlineMs: arNowMs + 21_000, shotCount: 4,
                 placementRevision: 2, myReady: true, opponentReady: true, stake: stake,
                 myMissedTurns: missed, opponentMissedTurns: 0, forfeitAfter: 3, watchers: watchers)
}

/// 배치 중(숨긴 동시 배치) — 내 돌 5개만 · 3개 놓음 · 남은 18초.
private func arPlacing() -> AlkkagiMatch {
    var stones = AlkkagiGame().stones.filter { $0.owner == .black }
    for index in 0..<3 { stones[index].isPlaced = true }
    return AlkkagiMatch(id: arID(901), revision: 1, phase: .placing, currentPlayer: .black, myColor: .black,
                        black: arMe, white: arMinsu, stones: stones, deadlineMs: arNowMs + 18_000,
                        placementRevision: 3, myReady: false, opponentReady: true, stake: 5, watchers: 1)
}

/// 끝난 판(내 흑) — 결과 · 사유 · 판돈.
private func arFinished(_ result: AlkkagiMatchResult, reason: String, stake: Int? = 5) -> AlkkagiMatch {
    let stones = arStones { stones in
        switch result {
        case .black:
            for index in 5..<10 { stones[index].isOut = true }
            stones[1].position = AlkkagiVector(x: 260, y: 380)
        case .white:
            for index in 0..<5 { stones[index].isOut = true }
            for index in [5, 6, 9] { stones[index].isOut = true }
            stones[7].position = AlkkagiVector(x: 260, y: 300)
            stones[8].position = AlkkagiVector(x: 380, y: 250)
        default:
            for index in 0..<10 { stones[index].isOut = true }
        }
    }
    return AlkkagiMatch(id: arID(902), revision: 23, phase: .finished, currentPlayer: .white, myColor: .black,
                        black: arMe, white: arMinsu, stones: stones, shotCount: 11, result: result, finishReason: reason,
                        placementRevision: 2, myReady: true, opponentReady: true, stake: stake, settled: true)
}

@MainActor
private func arMatchStore(_ match: AlkkagiMatch) -> (AlkkagiOnlineStore, AlkkagiLocalModel) {
    let store = arStore(populated: false)
    store.state = match
    let model = AlkkagiLocalModel()
    model.soundEnabled = false
    model.attachOnline(store)
    return (store, model)
}

/// 관전 — 준호(흑) vs 태화(백). 배치 중이면 돌 [] (숨긴 배치).
private func arWatch(placing: Bool) -> AlkkagiWatchState {
    if placing {
        return AlkkagiWatchState(id: arID(950), revision: 1, phase: .placing, black: arJunho, white: arTaehwa,
                                 blackReady: true, whiteReady: false, stones: [], deadlineMs: arNowMs + 14_000,
                                 stake: 10, watchers: 3)
    }
    return AlkkagiWatchState(id: arID(950), revision: 12, phase: .aiming, currentPlayer: .white,
                             black: arJunho, white: arTaehwa, blackReady: true, whiteReady: true,
                             stones: arAimingStones(), deadlineMs: arNowMs + 17_000, shotCount: 6, stake: 10,
                             blackMissedTurns: 0, whiteMissedTurns: 1, watchers: 3)
}

@MainActor
private let arCharacters = AppUserCharacterDirectory(knownIDs: AppUserAvatarArt.knownIDs)

@MainActor
private func arPanel(_ store: AlkkagiOnlineStore, model: AlkkagiLocalModel? = nil, stakeTarget: AlkkagiLobbyUser? = nil,
                     rules: Bool = false, confirmResign: Bool = false, characters: Bool = true) -> some View {
    AlkkagiOnlinePanel(store: store, clipsOverflowInsteadOfScroll: true, previewStakeTarget: stakeTarget,
                       previewRules: rules, previewConfirmResign: confirmResign, previewModel: model,
                       previewCharacters: characters ? arCharacters : nil)
        .environment(\.colorScheme, .dark)
}

// MARK: - 창 좌표(레이아웃 상수에서만 뽑는다)

private var arBodyOrigin: CGPoint {
    CGPoint(x: BoardGameLayout.contentPadding, y: BoardGameLayout.contentPadding + BoardGameLayout.headerHeight
            + BoardGameLayout.headerSpacing)
}
private var arBoardRect: CGRect {
    CGRect(origin: arBodyOrigin, size: CGSize(width: BoardGameLayout.boardSide, height: BoardGameLayout.boardSide))
}
private var arSideRect: CGRect {
    CGRect(x: arBodyOrigin.x + BoardGameLayout.boardSide + BoardGameLayout.columnSpacing, y: arBodyOrigin.y,
           width: BoardGameLayout.sideColumnWidth, height: BoardGameLayout.bodyHeight)
}
/// 오른쪽 열 위 두 카드 아래(상태 카드 · 결과 카드 자리).
private var arSideMiddleRect: CGRect {
    CGRect(x: arSideRect.minX, y: arSideRect.minY + BoardGameLayout.playerCardHeight * 2 + BoardGameLayout.matchSideSpacing * 2,
           width: arSideRect.width, height: 170)
}
/// 오른쪽 열 맨 아래(동작 줄).
private var arSideBottomRect: CGRect {
    CGRect(x: arSideRect.minX, y: arSideRect.maxY - 60, width: arSideRect.width, height: 60)
}
private var arHeaderRect: CGRect {
    CGRect(x: BoardGameLayout.contentPadding, y: BoardGameLayout.contentPadding,
           width: BoardGameLayout.innerSize.width, height: BoardGameLayout.headerHeight)
}
private var arLobbyUsersRect: CGRect {
    CGRect(origin: arBodyOrigin, size: CGSize(width: ReversiWindowLayout.lobbyUsersWidth, height: ReversiWindowLayout.bodyHeight))
}
private var arLobbyRankRect: CGRect {
    CGRect(x: arBodyOrigin.x + ReversiWindowLayout.lobbyUsersWidth + ReversiWindowLayout.columnSpacing, y: arBodyOrigin.y,
           width: ReversiWindowLayout.lobbyRankWidth, height: ReversiWindowLayout.bodyHeight)
}
private var arLobbySideRect: CGRect {
    CGRect(x: arLobbyRankRect.maxX + ReversiWindowLayout.columnSpacing, y: arBodyOrigin.y,
           width: ReversiWindowLayout.lobbySideWidth, height: ReversiWindowLayout.bodyHeight)
}
private var arCenterRect: CGRect {
    CGRect(x: BoardGameLayout.contentSize.width / 2 - 150, y: BoardGameLayout.contentSize.height / 2 - 90,
           width: 300, height: 180)
}

// MARK: - 픽셀 도구

private enum ARRenderError: Error { case failed }

/// 굳힌 비트맵(scale 2). 같은 내용의 첫 두 장이 다르게 구워지는 ImageRenderer 버릇을 `CheckRenderSettle` 이 걷어낸다.
@MainActor
private func arBitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view, scale: 2) else { throw ARRenderError.failed }
    return bitmap
}

/// AppKit 이 그린 픽셀(2x) — 화면에 올리지 않는 창(borderless · orderFront 안 함)에 붙인 호스팅 뷰.
@MainActor
private func arAppKit(_ view: some View, size: CGSize) throws -> NSBitmapImageRep {
    let host = NSHostingView(rootView: AnyView(view))
    host.appearance = NSAppearance(named: .darkAqua)
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    host.layoutSubtreeIfNeeded()
    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    rep.size = size
    let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    host.displayIgnoringOpacity(host.bounds, in: context)
    NSGraphicsContext.restoreGraphicsState()
    window.contentView = nil
    withExtendedLifetime(window) {}
    return rep
}

private func arSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "alkkagi-v2-render")
}

private func arCount(_ bitmap: NSBitmapImageRep, rect: CGRect, where predicate: (Int, Int, Int) -> Bool) -> Int {
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

/// 사각형(pt) 안의 **잉크** 픽셀 수 — 유채색(채널 폭 ≥ 40)이거나 밝은 글자(최대 ≥ 150).
private func arInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    arCount(bitmap, rect: rect) { r, g, b in
        let high = max(r, max(g, b)), low = min(r, min(g, b))
        return (high - low) >= 40 || high >= 150
    }
}

/// 사각형(pt) 안 빨강 잉크(`CheckTheme.danger`).
private func arRed(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    arCount(bitmap, rect: rect) { r, g, b in r > 170 && r > g + 70 && r > b + 50 }
}

/// 사각형(pt) 안에서 두 비트맵의 채널 최대 차(0 이면 한 바이트도 다르지 않다).
private func arMaxDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
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

/// 판 지문 — 판 사각형을 16×16 칸으로 나눠 칸마다 평균 RGB(0~255). 0.3.80 그림과 같은지 재는 짧은 값이다.
private func arBoardFingerprint(_ bitmap: NSBitmapImageRep, rect: CGRect = arBoardRect) -> [Int] {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return [] }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let cells = 16
    let cellW = rect.width * 2 / CGFloat(cells), cellH = rect.height * 2 / CGFloat(cells)
    var out: [Int] = []
    for row in 0..<cells {
        for column in 0..<cells {
            let x0 = Int(rect.minX * 2 + CGFloat(column) * cellW), x1 = Int(rect.minX * 2 + CGFloat(column + 1) * cellW)
            let y0 = Int(rect.minY * 2 + CGFloat(row) * cellH), y1 = Int(rect.minY * 2 + CGFloat(row + 1) * cellH)
            var sum = [0, 0, 0], n = 0
            for y in y0..<min(y1, bitmap.pixelsHigh) {
                for x in x0..<min(x1, bitmap.pixelsWide) {
                    let o = y * bpr + x * spp
                    sum[0] += Int(data[o]); sum[1] += Int(data[o + 1]); sum[2] += Int(data[o + 2]); n += 1
                }
            }
            out += sum.map { n > 0 ? $0 / n : 0 }
        }
    }
    return out
}

private func arWorst(_ a: [Int], _ b: [Int]) -> Int {
    guard a.count == b.count, !a.isEmpty else { return 255 }
    return zip(a, b).map { abs($0 - $1) }.max() ?? 255
}

/// 0.3.80 판 지문(`REPO/.claude/alkkagi-compare-render/alkkagi-2-play.png` — 같은 돌 자리 · ImageRenderer scale 2 · 굳힌 뒤).
/// `ALKKAGI_BOARD_0380_PNG` 에 그 그림을 주면 이 표 대신 그림에서 직접 뽑는다(표를 새로 적을 때).
private let arBoardFingerprint0380: [Int] = AR0380.fingerprint

// MARK: - 소스 도구

private func arSourceRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

/// 주석을 걷은 소스(문자열 리터럴 안의 `//` 는 지키지 않는다 — 이 파일들은 리터럴에 `//` 가 없다).
private func arStripped(_ path: String) throws -> String {
    let raw = try String(contentsOf: arSourceRoot().appendingPathComponent(path), encoding: .utf8)
    return raw.components(separatedBy: "\n").map { line -> String in
        guard let range = line.range(of: "//") else { return line }
        return String(line[..<range.lowerBound])
    }.joined(separator: "\n")
}

/// 문자열 리터럴(따옴표 안) 전부.
private func arLiterals(_ code: String) -> [String] {
    var out: [String] = []
    var current = ""
    var inside = false
    var escaped = false
    for ch in code {
        if inside {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; current.append(ch); continue }
            if ch == "\"" { out.append(current); current = ""; inside = false; continue }
            current.append(ch)
        } else if ch == "\"" {
            inside = true
        }
    }
    return out
}

private let arUFiles = ["Sources/check/AlkkagiOnlinePanel.swift", "Sources/check/AlkkagiPanelLobby.swift",
                        "Sources/check/AlkkagiPanelWatch.swift", "Sources/check/AlkkagiInviteBanner.swift",
                        "Sources/check/AlkkagiGameView.swift", "Sources/check/CheckAlkkagiWindow.swift",
                        "Sources/CheckCore/AlkkagiNoticeText.swift"]

private func arForbidden(_ literal: String) -> [String] {
    ["대전", "초대", "참가비", "💎"].filter { literal.contains($0) }
}

// MARK: - 시험

@MainActor
@Suite("1:1 알까기 — 맥 화면 렌더(SPEC §5)", .serialized)
struct V03xxAlkkagiPanelRenderTests {

    @Test("로비 3열 — 사람 여섯(다섯 상태) · 순위 · 내 전적 · 지금 대결 중 · 받은 신청 1+외 2 · 보낸 신청(기준선: 빈 가게)")
    func lobbyDrawsAllThreeColumns() throws {
        // 없으면: 로비 세 열이 크롬(카드 테두리·제목)만 그리고 내용(사람·순위·대결 중·신청)이 비어도 초록이다(0.3.80 로비가 ImageRenderer 에서
        // 사람 목록을 빈 칸으로 그린 것과 같은 결함).
        let full = try arBitmap(arPanel(arStore()))
        let bare = try arBitmap(arPanel(arStore(populated: false)))
        arSave(full, "1-lobby")
        arSave(bare, "1-lobby-empty")
        let size = BoardGameLayout.contentSize
        #expect(full.pixelsWide == Int(size.width) * 2 && full.pixelsHigh == Int(size.height) * 2,
                "로비가 \(full.pixelsWide)×\(full.pixelsHigh)px — 고정 창(1240×700)을 넘치거나 모자란다")
        for (label, rect, minimum) in [("상대 목록", arLobbyUsersRect, 6_000), ("순위", arLobbyRankRect, 4_000),
                                       ("오른쪽(전적·대결·신청)", arLobbySideRect, 3_000)] {
            let withContent = arInk(full, rect: rect), without = arInk(bare, rect: rect)
            print("[로비] \(label): 잉크 \(withContent)px (빈 가게 \(without)px)")
            #expect(withContent > without + minimum, "\(label) 열이 내용을 안 그린다(\(withContent) vs \(without))")
        }
        // 머리글: 전적 캡슐 · 루비 칩 · [연습하기] · [규칙] — 같은 머리(두 그림 모두 그린다), 전적 글자만 갈린다.
        #expect(arMaxDifference(full, bare, rect: arHeaderRect) > 60, "머리 전적 캡슐이 전적을 안 따른다")
        // 순서 · 상태 글자(순수 — 화면과 같은 출처).
        let store = arStore()
        #expect(store.visibleUsers.map(\.displayName).prefix(2) == ["민수", "서연"], "도전할 수 있는 사람이 먼저 서지 않는다")
        #expect(arUsers.map(AlkkagiOpponentRow.statusLine) == ["근무 중", "대결 중", "—", "대결 중", "집중 모드", "앱 업데이트 필요"])
        #expect(arUsers.map { AlkkagiOpponentList.canChallenge($0, store: store) } == [true, false, true, false, false, false])
        #expect(AlkkagiRecordSource.headerLine(store) == "7승 3패 1무 · 4위 · 승점 +4")
        store.record = AlkkagiRecord(wins: 8, losses: 3, draws: 1)   // 기준선: 두 출처가 어긋나면 순위를 섞지 않는다
        #expect(AlkkagiRecordSource.headerLine(store) == "8승 3패 1무")
        #expect(store.visibleIncomingInvites.count == 3 && AlkkagiText.incomingMore(2) == "외 2건")
        // 아바타가 이니셜로 안 떨어진다 — 캐릭터 표가 있으면 첫 줄 얼굴이 캐릭터(기준선: 표가 없으면 이니셜 원).
        let initials = try arBitmap(arPanel(arStore(), characters: false))
        let face = CGRect(x: arLobbyUsersRect.minX + 16, y: arLobbyUsersRect.minY + 56, width: 60, height: 50)
        #expect(arMaxDifference(full, initials, rect: face) > 60, "줄 아바타가 캐릭터를 안 그린다(이니셜과 같다)")
    }

    @Test("로비 '곧 열려요'(문 닫힘 · 서버 옛판) — 사람 줄 대신 한 줄(기준선: 같은 사람 · 문 열림이면 줄을 그린다)")
    func lobbySoonReplacesRows() throws {
        // 없으면: 문이 닫힌 동안 모든 줄이 capable 거짓이라 줄마다 '앱 업데이트 필요'가 뜬다(VC-8) — 사용자는 업데이트를 찾아 헤맨다.
        let soon = arStore()
        soon.availability = .serverMissing
        let open = arStore()
        #expect(AlkkagiOpponentList.emptyState(soon) == .soon)
        #expect(AlkkagiOpponentList.emptyState(open) == nil, "기준선: 문 열림이면 줄")
        #expect(AlkkagiOpponentList.EmptyState.soon.text == "1:1 알까기는 곧 열려요")
        let update = arStore()
        update.availability = .updateRequired
        #expect(AlkkagiOpponentList.emptyState(update) == .update)
        let failed = arStore(populated: false)
        failed.lobbyLoadFailed = true
        #expect(AlkkagiOpponentList.emptyState(failed) == .failed)
        let loading = AlkkagiOnlineStore(clock: { arWall0 })
        #expect(AlkkagiOpponentList.emptyState(loading) == .loading)
        #expect(AlkkagiOpponentList.emptyState(arStore(populated: false)) == AlkkagiOpponentList.EmptyState.none)
        #expect(AlkkagiRankColumn.emptyText(soon) == "순위는 곧 열려요")
        let soonBitmap = try arBitmap(arPanel(soon))
        let openBitmap = try arBitmap(arPanel(open))
        arSave(soonBitmap, "1b-lobby-soon")
        #expect(arInk(soonBitmap, rect: arLobbyUsersRect) + 4_000 < arInk(openBitmap, rect: arLobbyUsersRect),
                "곧 열려요인데 사람 줄이 그려졌다")
        // 내 전적 카드는 문과 상관없이 같다(받은 신청 [수락] 은 문이 닫히면 흐려진다 — 일부러 다르다).
        let recordRect = CGRect(x: arLobbySideRect.minX, y: arLobbySideRect.minY, width: arLobbySideRect.width,
                                height: ReversiWindowLayout.lobbyRecordHeight)
        #expect(arMaxDifference(soonBitmap, openBitmap, rect: recordRect) <= 8, "내 전적 카드가 문 상태에 흔들린다")
        let inviteRect = CGRect(x: arLobbySideRect.minX, y: arLobbySideRect.maxY - ReversiWindowLayout.lobbyInvitesMaxHeight,
                                width: arLobbySideRect.width, height: ReversiWindowLayout.lobbyInvitesMaxHeight)
        #expect(arMaxDifference(soonBitmap, openBitmap, rect: inviteRect) > 30, "문이 닫혔는데 [수락] 이 그대로 눌릴 모양이다")
    }

    @Test("판돈 덮개 — 5 고름(기억) · 잔액 7 이면 10 흐림 + 모자람 · 잔액 모르면 막지 않음 · 규칙 덮개 다섯 줄")
    func stakeAndRulesPrompts() throws {
        // 없으면: 판돈 창이 안 서거나(가운데가 로비 그대로), 모자란 판돈이 눌리거나, 고른 판돈을 잊어 매번 3으로 돌아간다(D16).
        let store = arStore()
        store.rubyBalance = 7
        store.selectedStake = .five
        let lobby = try arBitmap(arPanel(store))
        let stake = try arBitmap(arPanel(store, stakeTarget: arUsers[0]))
        arSave(stake, "1c-lobby-stake")
        #expect(arMaxDifference(stake, lobby, rect: arCenterRect) > 60, "판돈 창이 안 그려졌다")
        #expect(AlkkagiStakePrompt.affordable(.five, balance: 7) && !AlkkagiStakePrompt.affordable(.ten, balance: 7))
        #expect(AlkkagiStakePrompt.affordable(.ten, balance: nil), "잔액을 모르는데 막았다")
        #expect(AlkkagiText.challengeWithStake(5) == "5 걸고 도전하기")
        #expect(AlkkagiText.stakePromptChosen(5) == "판돈 5 · 이기면 +5")
        // 기억 — 고른 값이 바뀌면 덮개 그림이 갈린다(기준선: 3 고름).
        store.selectedStake = .three
        let stakeThree = try arBitmap(arPanel(store, stakeTarget: arUsers[0]))
        #expect(arMaxDifference(stake, stakeThree, rect: arCenterRect) > 60, "고른 판돈이 덮개에 안 선다")

        let rules = try arBitmap(arPanel(store, rules: true))
        arSave(rules, "1d-lobby-rules")
        #expect(arMaxDifference(rules, lobby, rect: arCenterRect) > 60, "규칙 창이 안 그려졌다")
        #expect(AlkkagiText.rulesLines.count == 5)
        #expect(AlkkagiText.rulesLines[4].contains("세 번") && AlkkagiText.rulesLines[1].contains("수락할 때"))
    }

    @Test("판 중 — 판돈 칩 · 관전자 수 칩 2(기준선 0 · 스위치 꺼짐) · 놓친 차례 경고 · 돌 수 카드 · 빨간 [기권] · 확인 경고")
    func matchSide() throws {
        // 없으면: 대국자가 관전자 수를 못 보거나(VC-6), 놓친 차례 경고가 안 서 판돈을 잃거나, 기권 확인이 판돈 경고 없이 서도 초록이다.
        let (store, model) = arMatchStore(arAiming())
        #expect(store.spectatorCount == 2, "전제: 관전자 수가 STATE watchers 를 따른다")
        let play = try arBitmap(arPanel(store, model: model))
        arSave(play, "2-play")
        let (zeroStore, zeroModel) = arMatchStore(arAiming(watchers: 0))
        let zero = try arBitmap(arPanel(zeroStore, model: zeroModel))
        #expect(arMaxDifference(play, zero, rect: arSideMiddleRect) > 60, "관전자 수 칩이 안 선다(2 와 0 이 같은 그림)")
        let (offStore, offModel) = arMatchStore(arAiming())
        offStore.spectatorFeaturesEnabled = false
        let off = try arBitmap(arPanel(offStore, model: offModel))
        #expect(arMaxDifference(off, zero, rect: arSideMiddleRect) <= 8, "관전 스위치가 꺼졌는데 칩이 섰다")
        // 놓친 차례 경고(기준선: 0번이면 경고 없음).
        #expect(store.missedTurnWarning.map { AlkkagiNoticeText.missedTurn(mine: $0.mine, forfeitAfter: $0.forfeitAfter) }
                == "시간이 지나 차례가 넘어갔어요 · 두 번 더 넘기면 져요")
        let (calmStore, _) = arMatchStore(arAiming(missed: 0))
        #expect(calmStore.missedTurnWarning == nil)
        // 판돈 칩(머리) — 옛 판(판돈 nil)은 칩이 없다.
        let (oldStore, oldModel) = arMatchStore(arAiming(stake: nil))
        let old = try arBitmap(arPanel(oldStore, model: oldModel))
        #expect(arMaxDifference(play, old, rect: arHeaderRect) > 60, "판돈 칩이 머리에 안 선다")
        // 돌 수 카드(STATE 값만 — 나간 돌을 뺀다).
        #expect(AlkkagiMatchSide<EmptyView, EmptyView>.remaining(arAiming(), .black) == 5)
        #expect(AlkkagiMatchSide<EmptyView, EmptyView>.remaining(arAiming(), .white) == 4)
        #expect(AlkkagiStoneCountCard.countsLine(black: 5, white: 4) == "흑 5 · 백 4")
        #expect(AlkkagiStoneCountCard.shotsLine(4) == "쏜 횟수 4번")
        // 기권 확인 — 빨간 잉크가 늘고 판돈 경고 줄이 선다(옛 판은 '이번 판은 져요').
        let confirm = try arBitmap(arPanel(store, model: model, confirmResign: true))
        arSave(confirm, "2b-play-resign-confirm")
        print("[판 중] 동작 줄 빨강 \(arRed(play, rect: arSideBottomRect)) → 확인 \(arRed(confirm, rect: arSideBottomRect))")
        #expect(arRed(confirm, rect: arSideBottomRect) > arRed(play, rect: arSideBottomRect) + 400, "기권 확인이 안 섰다")
        #expect(arRed(play, rect: arSideBottomRect) > 200, "[기권] 이 빨간 띠가 아니다")
        #expect(AlkkagiMatchSide<EmptyView, EmptyView>.resignWarning(stake: 5) == "기권하면 판돈을 잃어요")
        #expect(AlkkagiMatchSide<EmptyView, EmptyView>.resignWarning(stake: nil) == "기권하면 이번 판은 져요")

        let (placingStore, placingModel) = arMatchStore(arPlacing())
        let placing = try arBitmap(arPanel(placingStore, model: placingModel))
        arSave(placing, "2a-placing")
        #expect(arMaxDifference(placing, play, rect: arSideMiddleRect) > 60)
    }

    @Test("판 그림은 0.3.80 과 같다 — 같은 돌 자리 지문(기준선: 돌 하나를 옮기면 갈린다)")
    func boardPixelsMatch0380() throws {
        // 없으면: 오른쪽 열 · 머리를 바꾸다 판 그림(돌 · 바둑판 · 그림자 · 크기 · 자리)이 바뀌어도 초록이다(§5.9 — 손맛은 그대로).
        let (store, model) = arMatchStore(arAiming())
        let now = try arBitmap(AlkkagiGameView(onlineStore: store, model: model).environment(\.colorScheme, .dark))
        let mine = arBoardFingerprint(now)
        var reference = arBoardFingerprint0380
        if let path = ProcessInfo.processInfo.environment["ALKKAGI_BOARD_0380_PNG"],
           let data = FileManager.default.contents(atPath: path), let old = NSBitmapImageRep(data: data) {
            reference = arBoardFingerprint(old)
            print("[판 지문] 0.3.80 그림에서 뽑음: \(reference.map(String.init).joined(separator: ","))")
        }
        let worst = arWorst(mine, reference)
        print("[판 지문] 0.3.80 과 칸 평균 최대 차 \(worst)")
        #expect(worst <= 3, "판 그림이 0.3.80 과 달라졌다(칸 평균 최대 차 \(worst))")
        // 기준선: 백돌 하나를 옮긴 같은 판은 지문이 갈린다.
        var moved = arAiming()
        moved.stones[8].position = AlkkagiVector(x: 150, y: 120)
        let (movedStore, movedModel) = arMatchStore(moved)
        let other = try arBitmap(AlkkagiGameView(onlineStore: movedStore, model: movedModel).environment(\.colorScheme, .dark))
        #expect(arWorst(arBoardFingerprint(other), reference) > 12, "돌을 옮겼는데 지문이 같다 — 이 시험은 아무것도 안 잰다")
    }

    @Test("결과 승·패·무·무효 — 오른쪽 결과 카드(루비 +5 / −5 / 0 · 돌려받음) · 판 위 띠 · 옛 판은 루비 줄 없음")
    func resultCards() throws {
        // 없으면: 결과가 색으로만 말하거나('흑돌 승리!'), 루비 줄이 틀리거나, [로비로]가 두 번 서도 초록이다(DF#57 · #59).
        let cases: [(String, AlkkagiMatch, AlkkagiOutcome, Int, String)] = [
            ("3-result-win", arFinished(.black, reason: "ring_out"), .win, 5, "상대 돌을 모두 판 밖으로 밀어냈어요"),
            ("3b-result-loss", arFinished(.white, reason: "timeout"), .loss, -5, "차례를 세 번 넘겨 졌어요"),
            ("3c-result-draw", arFinished(.draw, reason: "ring_out"), .draw, 0, "마지막 돌이 함께 나가 무승부예요"),
            ("3d-result-void", arFinished(.draw, reason: "void"), .draw, 0, "판이 무효가 되어 판돈을 돌려받았어요"),
        ]
        var bitmaps: [String: NSBitmapImageRep] = [:]
        for (name, match, outcome, delta, reason) in cases {
            let (store, model) = arMatchStore(match)
            #expect(store.outcome == outcome, "\(name)")
            #expect(store.rubyDelta == delta, "\(name): 루비 \(String(describing: store.rubyDelta))")
            #expect(AlkkagiNoticeText.endReason(store.endReason, outcome: store.outcome) == reason, "\(name)")
            let bitmap = try arBitmap(arPanel(store, model: model))
            arSave(bitmap, name)
            bitmaps[name] = bitmap
            #expect(arInk(bitmap, rect: arSideMiddleRect) > 3_000, "\(name): 결과 카드가 비었다")
        }
        #expect(AlkkagiText.rubyLine(5) == "+5" && AlkkagiText.rubyLine(-5) == "−5" && AlkkagiText.rubyLine(0) == "0 · 판돈을 돌려받았어요")
        if let win = bitmaps["3-result-win"], let loss = bitmaps["3b-result-loss"] {
            #expect(arMaxDifference(win, loss, rect: arSideMiddleRect) > 60, "승과 패의 결과 카드가 같다")
            // 판 위 띠: 판 위쪽 44pt 에 결과 글자(승 초록 · 패 빨강) — 기준선: 판 중 그림의 같은 자리.
            let band = CGRect(x: arBoardRect.minX + 150, y: arBoardRect.minY, width: arBoardRect.width - 300, height: 44)
            let (playStore, playModel) = arMatchStore(arAiming())
            let play = try arBitmap(arPanel(playStore, model: playModel))
            #expect(arMaxDifference(win, play, rect: band) > 60, "판 위 결과 띠가 없다")
            #expect(arRed(loss, rect: band) > arRed(win, rect: band) + 100, "패 띠가 빨강이 아니다")
        }
        // 옛 판(판돈 nil) — 루비 줄 없음(기준선: 판돈 판은 +5).
        let (oldStore, _) = arMatchStore(arFinished(.black, reason: "ring_out", stake: nil))
        #expect(oldStore.rubyDelta == nil)
        #expect(AlkkagiText.outcomeTitle(.draw) == "무승부예요" && AlkkagiText.outcomeTitle(.win) == "이겼어요")
    }

    @Test("관전 — 배치 중(돌 0 · 숨긴 배치 안내) · 진행(돌 · 차례 · 관전자 수) · [나가기] · 관전 결과는 3인칭")
    func spectate() throws {
        // 없으면: 배치 중 관전자에게 한쪽 돌이 보이거나(숨긴 배치 누설), 관전 화면이 로비 자리에 안 서거나, 남의 판 결과를 '이겼어요'로 말한다.
        let placingStore = arStore()
        placingStore.watched = arWatch(placing: true)
        let aimingStore = arStore()
        aimingStore.watched = arWatch(placing: false)
        let placing = try arBitmap(arPanel(placingStore))
        let aiming = try arBitmap(arPanel(aimingStore))
        arSave(placing, "4-watch-placing")
        arSave(aiming, "4b-watch-aiming")
        // 돌 잉크: 진행 판은 돌(극단 흑·백)이 서고 배치 중은 없다.
        func stoneInk(_ bitmap: NSBitmapImageRep) -> Int {
            arCount(bitmap, rect: arBoardRect.insetBy(dx: 40, dy: 40)) { r, g, b in
                (r < 40 && g < 40 && b < 40) || (r > 235 && g > 235 && b > 235)
            }
        }
        print("[관전] 돌 잉크 배치 중 \(stoneInk(placing)) · 진행 \(stoneInk(aiming))")
        #expect(stoneInk(aiming) > stoneInk(placing) + 4_000, "진행 판 관전에 돌이 안 섰다(또는 배치 중에 돌이 섰다)")
        #expect(AlkkagiSpectateView.headline(arWatch(placing: true)) == "두 사람이 돌을 숨겨 놓는 중이에요")
        #expect(AlkkagiSpectateView.headline(arWatch(placing: false)) == "백 차례")
        #expect(AlkkagiText.watchOutcome(.black) == "흑 승리" && AlkkagiText.watchEndReason(.resign, result: .white) == "흑이 기권했어요")
        // 로비 자리에 선다 — 머리에 [연습하기] 가 없다(기준선: 로비 머리에는 있다).
        let lobby = try arBitmap(arPanel(arStore()))
        #expect(arMaxDifference(aiming, lobby, rect: arHeaderRect) > 60)
    }

    @Test("받은 신청 배너 — 아이콘 · 제목 · 판돈 RubyIcon + 'N · 1분 안에 응답하세요' · [수락][거절][보기] · 💎 글자 0")
    func inviteBanner() throws {
        // 없으면: 배너가 상대 초상 · '수락하면 돌 배치를 시작해요'(0.3.80)로 남아 판돈을 모른 채 수락하거나, 판돈이 💎 글자로 선다(VC-7).
        let invite = AlkkagiInvite(id: arID(800), opponent: arMinsu, expiresAtMs: arNowMs + 48_000, stake: 5)
        func banner(_ invite: AlkkagiInvite) throws -> NSBitmapImageRep {
            try arBitmap(AlkkagiInviteBanner(invite: invite, isBusy: false, serverNowMs: { arNowMs },
                                             onAccept: {}, onDecline: {}, onOpen: {})
                .frame(width: 316).padding(12).background(CheckTheme.background)
                .environment(\.colorScheme, .dark).fixedSize())
        }
        let staked = try banner(invite)
        arSave(staked, "5-invite-banner")
        var legacy = invite
        legacy.stake = nil
        let plain = try banner(legacy)
        #expect(staked.pixelsHigh == plain.pixelsHigh, "판돈 줄이 배너 높이를 바꿨다")
        let line = CGRect(x: 12, y: 12, width: 316, height: 40)
        #expect(arMaxDifference(staked, plain, rect: line) > 60, "판돈 줄이 안 선다(기준선: 옛 신청)")
        #expect(AlkkagiText.inviteBannerTitle(name: "민수") == "민수님이 1:1 알까기 대결을 신청했어요")
        #expect(AlkkagiText.inviteBubbleText(name: "민수", stake: 5).hasSuffix("루비 5"))
        #expect(AlkkagiText.myTurnText(shooterName: nil) == "알까기 내 차례예요")
        #expect(AlkkagiText.dotReason == "1:1 알까기 신청")
        #expect(AlkkagiEntryIcon.resolved == AlkkagiEntryIcon.symbol || AlkkagiEntryIcon.resolved == AlkkagiEntryIcon.fallback)
        #expect(AlkkagiEntryIcon.symbol != "circle.lefthalf.filled", "뒤집기 기호와 겹친다(DF#3)")
    }

    @Test("화면 글자에 '대전'·'초대'·'참가비'·'💎' 0 · 아바타는 캐릭터 힌트를 넘긴다 · 판 화면에 대화 카드 없음(기준선: 0.3.80 글자는 걸린다)")
    func copyAndSourceContracts() throws {
        // 없으면: 0.3.80 낱말('참가비 없는 대전' · '초대할 수 있는 상대' · '대전 대화')이 남거나, 아바타가 이니셜로 떨어지거나, 대화 카드가 판에 다시 서도 초록이다.
        var hits: [String] = []
        for file in arUFiles {
            for literal in arLiterals(try arStripped(file)) where !arForbidden(literal).isEmpty {
                hits.append("\(file): \(literal)")
            }
        }
        #expect(hits.isEmpty, "금지 낱말: \(hits)")
        let legacy = arLiterals(#"Text("참가비 없는 대전") ; Text("지금 초대할 수 있는 상대가 없어요") ; "판돈 💎 5""#)
        #expect(legacy.flatMap(arForbidden) == ["대전", "참가비", "초대", "💎"], "기준선: 검사기가 0.3.80 글자를 못 잡는다")
        // 아바타 — 알까기 화면의 모든 CheckAvatarView 호출이 사람 id 와 캐릭터 힌트를 넘긴다.
        for file in ["Sources/check/AlkkagiPanelLobby.swift"] {
            let code = try arStripped(file)
            let calls = code.components(separatedBy: "CheckAvatarView(").dropFirst()
            #expect(calls.count == 5, "\(file): 아바타 \(calls.count)곳")
            for call in calls {
                let head = String(call.prefix(260))
                #expect(head.contains("userID:") && head.contains("characterHint:"), "\(file): 힌트 없는 아바타 — \(head.prefix(80))")
            }
        }
        // 대화 카드는 판 화면에서 빠졌다(정의만 남는다 — 되살리기용).
        let game = try arStripped("Sources/check/AlkkagiGameView.swift")
        #expect(game.components(separatedBy: "AlkkagiChatPanel(").count == 1, "판 화면이 대화 카드를 다시 그린다")
        #expect(game.contains("struct AlkkagiChatPanel"), "되살리기용 대화 카드 부품이 사라졌다")
        #expect(game.contains("AlkkagiStoneCountCard("), "돌 수 카드가 판 화면에 없다")
        // 0.3.80 머리 단추가 없다([새로고침] · [게임 목록]).
        let panel = try arStripped("Sources/check/AlkkagiOnlinePanel.swift") + game
        #expect(!panel.contains("\"새로고침\"") && !panel.contains("\"게임 목록\""), "0.3.80 머리 단추가 남았다")
    }

    @Test("결재 카드 '알림'용 — 판 중 오른쪽 열 두 장(돌 수 카드 = 지을 안 · 대화 카드 = 0.3.80 모양 AppKit 판)")
    func approvalCardSidePair() throws {
        // 없으면: 대표에게 보일 '대화를 빼는' 전후 그림이 같은 픽스처로 안 남는다(VC-10 · §0 #11).
        let (store, model) = arMatchStore(arAiming())
        let play = try arBitmap(arPanel(store, model: model))
        let side = try #require(play.cgImage?.cropping(to: CGRect(x: arSideRect.minX * 2, y: arSideRect.minY * 2,
                                                                 width: arSideRect.width * 2, height: arSideRect.height * 2)))
        arSave(NSBitmapImageRep(cgImage: side), "6-side-stone-count")
        // 대화 카드(0.3.80 모양) — 같은 판 · 같은 대화 두 줄. AppKit 이 그린다(입력칸은 ImageRenderer 노란 칸).
        var chatMatch = arAiming()
        chatMatch.chatSeq = 2
        chatMatch.chat = [AlkkagiChatMessage(seq: 1, senderID: arMinsu.id, body: "잘 부탁해요", sentAtMs: arNowMs - 40_000),
                          AlkkagiChatMessage(seq: 2, senderID: arMe.id, body: "좋아요", sentAtMs: arNowMs - 30_000)]
        let (chatStore, chatModel) = arMatchStore(chatMatch)
        _ = chatStore
        let chatSize = CGSize(width: BoardGameLayout.sideColumnWidth, height: 300)
        let chat = try arAppKit(AlkkagiChatPanel(model: chatModel).frame(width: chatSize.width, height: chatSize.height)
            .background(CheckTheme.background).environment(\.colorScheme, .dark), size: chatSize)
        arSave(chat, "6b-side-chat-card-0380")
        #expect(arInk(chat, rect: CGRect(origin: .zero, size: chatSize)) > 2_000, "대화 카드가 비었다")
    }
}

// MARK: - 0.3.80 판 지문 표

/// `ALKKAGI_BOARD_0380_PNG=<REPO>/.claude/alkkagi-compare-render/alkkagi-2-play.png` 로 한 번 돌려 찍은 16×16 칸 평균 RGB.
private enum AR0380 {
    static let fingerprint: [Int] = [
        69, 63, 57, 160, 135, 96, 160, 134, 96, 160, 134, 95, 159, 133, 95, 159, 133, 94, 158, 132, 94, 158, 132, 93, 157, 131, 92, 157, 130, 92, 156, 130, 91, 156, 129, 91, 155, 129, 90, 155, 128, 90, 155, 127, 89, 69, 62, 57,
        98, 85, 69, 215, 177, 118, 214, 176, 117, 213, 175, 116, 212, 174, 115, 211, 173, 114, 211, 172, 113, 209, 170, 111, 208, 169, 111, 209, 169, 110, 208, 169, 109, 207, 168, 109, 206, 167, 107, 206, 166, 107, 205, 165, 106, 96, 82, 66,
        97, 85, 68, 215, 177, 117, 215, 177, 117, 214, 176, 116, 214, 175, 115, 213, 174, 114, 212, 173, 113, 210, 171, 112, 210, 170, 111, 210, 171, 111, 209, 170, 110, 209, 169, 109, 208, 168, 108, 207, 167, 107, 205, 165, 105, 95, 82, 66,
        97, 84, 68, 213, 174, 115, 222, 206, 182, 209, 172, 116, 209, 170, 112, 209, 171, 112, 209, 170, 111, 207, 168, 109, 206, 167, 108, 206, 167, 108, 206, 166, 107, 203, 164, 105, 204, 166, 109, 217, 201, 176, 203, 163, 104, 95, 82, 66,
        97, 84, 68, 213, 175, 115, 210, 178, 128, 212, 174, 114, 211, 172, 113, 211, 172, 112, 211, 171, 112, 208, 169, 110, 208, 168, 109, 208, 169, 109, 213, 180, 130, 214, 192, 161, 206, 166, 106, 203, 169, 119, 203, 163, 104, 95, 81, 66,
        97, 84, 68, 212, 174, 114, 213, 174, 114, 212, 173, 113, 212, 172, 113, 211, 171, 112, 210, 170, 111, 216, 208, 195, 207, 167, 108, 208, 168, 108, 206, 167, 109, 203, 168, 116, 205, 165, 105, 205, 164, 104, 203, 162, 103, 95, 81, 65,
        97, 84, 67, 212, 173, 114, 213, 173, 114, 211, 172, 112, 211, 172, 112, 210, 171, 111, 209, 170, 110, 207, 167, 108, 207, 167, 107, 207, 167, 107, 206, 166, 106, 206, 165, 105, 205, 164, 104, 204, 163, 104, 202, 161, 102, 95, 81, 65,
        96, 83, 67, 211, 172, 113, 211, 172, 112, 210, 171, 111, 210, 170, 111, 209, 169, 110, 208, 168, 109, 203, 164, 106, 202, 163, 105, 206, 166, 106, 205, 165, 105, 205, 164, 104, 203, 163, 103, 203, 162, 102, 201, 160, 101, 94, 81, 65,
        96, 83, 67, 210, 171, 112, 211, 172, 112, 210, 170, 111, 209, 170, 110, 209, 169, 109, 208, 168, 108, 156, 131, 93, 144, 119, 82, 206, 165, 105, 205, 164, 104, 204, 163, 104, 203, 162, 102, 203, 161, 102, 201, 159, 100, 94, 80, 65,
        96, 83, 67, 209, 170, 111, 210, 171, 111, 209, 169, 110, 209, 169, 109, 208, 168, 108, 207, 167, 107, 205, 165, 105, 204, 164, 104, 205, 164, 104, 204, 163, 103, 203, 162, 103, 202, 161, 101, 202, 160, 101, 200, 158, 99, 94, 80, 64,
        96, 83, 66, 209, 169, 110, 209, 170, 110, 111, 98, 79, 202, 164, 105, 207, 167, 107, 206, 166, 106, 204, 164, 104, 203, 163, 104, 204, 163, 103, 203, 162, 102, 203, 161, 102, 201, 160, 100, 201, 159, 100, 199, 158, 98, 94, 80, 64,
        96, 82, 66, 208, 168, 109, 209, 169, 109, 195, 158, 102, 190, 154, 101, 117, 101, 78, 206, 165, 105, 204, 163, 104, 203, 162, 103, 203, 162, 103, 121, 105, 81, 180, 143, 91, 196, 156, 98, 105, 92, 73, 198, 157, 97, 94, 79, 64,
        95, 82, 66, 207, 167, 108, 208, 168, 108, 206, 166, 107, 206, 166, 106, 195, 157, 100, 204, 164, 104, 202, 162, 103, 202, 161, 102, 202, 161, 101, 192, 152, 96, 201, 159, 99, 200, 158, 99, 189, 150, 93, 197, 156, 96, 93, 79, 64,
        95, 82, 66, 207, 167, 107, 207, 167, 107, 206, 166, 106, 206, 165, 105, 205, 164, 104, 204, 163, 103, 202, 161, 102, 201, 160, 101, 202, 160, 101, 201, 159, 100, 200, 159, 99, 199, 158, 98, 199, 157, 97, 197, 155, 95, 93, 79, 63,
        92, 79, 64, 209, 168, 108, 206, 166, 106, 205, 165, 105, 204, 164, 104, 204, 163, 103, 203, 162, 102, 202, 161, 101, 201, 160, 100, 201, 159, 99, 200, 158, 99, 199, 157, 98, 198, 156, 97, 198, 155, 96, 199, 156, 96, 90, 76, 62,
        27, 30, 40, 34, 34, 39, 34, 34, 40, 34, 34, 40, 34, 34, 40, 34, 34, 40, 35, 34, 40, 35, 34, 40, 35, 35, 41, 35, 35, 41, 35, 35, 41, 35, 35, 41, 35, 35, 41, 36, 35, 42, 36, 35, 42, 31, 33, 44,
    ]
}
