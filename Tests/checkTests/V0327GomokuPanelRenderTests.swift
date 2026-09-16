import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.3.27 1:1 오목 **화면** 렌더 — 로비 · 대국(흑 차례 X) · 결과 · 규칙 보기 · 팝오버 배너 · 미니게임 헤더 입구.
//
// 전부 ImageRenderer(scale 2)로 그리고 `CHECK_SNAPSHOT_DIR/gomoku/` 에 PNG 를 남긴다 — 사람이 직접 열어 본다
// (디자인 작업에서 초록 테스트는 아무것도 증명하지 않는다). 모든 장에서 **노란 상자(255,204,0) 픽셀 0** 을 단언한다:
// Picker/Menu/TextField 가 섞이면 ImageRenderer 가 그 자리를 노란 상자로 그리고, 그 자리의 픽셀 검증은 눈이 먼다.
//
// 스토어는 네트워크 없는 `GomokuStore()` 를 만들어 상태를 직접 채운다(§6.3 "전부 internal set").
// 공유 인스턴스(`store.gomoku`)는 건드리지 않는다 — 병렬로 도는 팝오버 렌더 테스트의 배너가 켜진다.

// MARK: - 픽스처

private func gpUser(_ name: String, _ suffix: Int, working: Bool = true, capable: Bool = true,
                    inMatch: Bool = false, character: String? = "shiba") -> GomokuUser {
    GomokuUser(
        id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))",
        displayName: name, avatarURL: nil, characterID: character,
        isWorking: working, isCapable: capable, inMatch: inMatch
    )
}

private let gpMinsu = gpUser("민수", 11, character: "fox")
private let gpJunho = gpUser("준호", 12, character: "squirrel")

private func gpUsers() -> [GomokuUser] {
    [
        gpUser("지영", 13, working: false),
        gpMinsu,
        gpUser("태화", 14, inMatch: true),
        gpUser("옛버전사용자", 15, capable: false),
        gpJunho,
        gpUser("서연", 16, character: "ghost"),
        gpUser("하늘", 17, working: false),
        gpUser("바다", 18),
        gpUser("가장긴별명열두글자입니다", 19),
        gpUser("산", 20, working: false)
    ]
}

@MainActor
private func gpLobbyStore(outgoing: Bool) -> GomokuStore {
    let store = GomokuStore()
    store.users = gpUsers()
    store.record = GomokuRecord(wins: 7, losses: 3, draws: 1)
    store.rubyBalance = 42
    store.selectedStake = .five
    if outgoing {
        store.outgoing = GomokuInvite(id: "out-1", peer: gpJunho, stake: 10, expiresAt: Date().addingTimeInterval(31))
        store.notice = "준호님이 수락하면 대결이 시작돼요"
    } else {
        store.incoming = [
            GomokuInvite(id: "in-1", peer: gpMinsu, stake: 5, expiresAt: Date().addingTimeInterval(48)),
            GomokuInvite(id: "in-2", peer: gpUser("서연", 16, character: "ghost"), stake: 3, expiresAt: Date().addingTimeInterval(55))
        ]
        store.notice = "지영님은 지금 근무 중이 아니에요"
    }
    return store
}

/// K01(3-3) 모양 — 흑 F8·G8·H6·H7 이 있으면 **H8 이 흑의 3-3 금수**다(규범 판정·스텁 흉내 모두). 나머지 돌은 멀리 둔다.
@MainActor
private func gpPlayingBoard() -> GomokuBoard {
    var board = GomokuBoard()
    for notation in ["F8", "G8", "H6", "H7", "L4"] {
        if let p = GomokuPoint(notation: notation) { board[p] = .black }
    }
    for notation in ["C3", "M12", "K13", "B14", "D12"] {
        if let p = GomokuPoint(notation: notation) { board[p] = .white }
    }
    return board
}

@MainActor
private func gpPlayingStore(turn: GomokuColor) -> GomokuStore {
    let store = GomokuStore()
    store.phase = .playing
    store.rubyBalance = 32
    store.record = GomokuRecord(wins: 7, losses: 3, draws: 1)
    store.isWindowVisible = false
    store.match = GomokuMatchState(
        id: "match-1", stake: 10, myColor: .black, opponent: gpMinsu, board: gpPlayingBoard(),
        lastMove: GomokuPoint(notation: "D12"), moveCount: 10, turn: turn,
        deadline: Date().addingTimeInterval(18), isFinished: false, outcome: nil, endReason: nil,
        rubyDelta: nil, blackPassed: false
    )
    return store
}

@MainActor
private func gpResultStore(outcome: GomokuOutcome, reason: GomokuEndReason) -> GomokuStore {
    let store = GomokuStore()
    store.phase = .result
    store.rubyBalance = outcome == .won ? 52 : 32
    store.record = GomokuRecord(wins: 8, losses: 3, draws: 1)
    var board = gpPlayingBoard()
    for notation in ["D9", "E9", "F9", "G9", "H9"] {
        if let p = GomokuPoint(notation: notation) { board[p] = .black }
    }
    let delta: Int
    switch outcome {
    case .won: delta = 10
    case .lost: delta = -10
    case .draw: delta = 0
    }
    store.match = GomokuMatchState(
        id: "match-1", stake: 10, myColor: .black, opponent: gpMinsu, board: board,
        lastMove: GomokuPoint(notation: "H9"), moveCount: 21, turn: nil, deadline: nil, isFinished: true,
        outcome: outcome, endReason: reason, rubyDelta: delta, blackPassed: false
    )
    return store
}

private let gpMe = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

@MainActor
private func gpPanel(_ store: GomokuStore) -> some View {
    GomokuPanel(store: store, me: { gpMe }, clipsOverflowInsteadOfScroll: true)
}

/// 판 왼쪽 위(창 좌표, pt). 레이아웃 상수에서만 나온다.
private var gpBoardOrigin: CGPoint {
    CGPoint(
        x: GomokuWindowLayout.contentPadding,
        y: GomokuWindowLayout.contentPadding + GomokuWindowLayout.headerHeight + GomokuWindowLayout.headerSpacing
    )
}

// MARK: - 화면

@MainActor
@Test
func gomokuLobbyRendersWithoutYellowBoxes() throws {
    let size = GomokuWindowLayout.contentSize
    for (name, outgoing) in [("lobby", false), ("lobby-outgoing", true)] {
        let bitmap = try gpBitmap(gpPanel(gpLobbyStore(outgoing: outgoing)))
        gpSave(bitmap, name: name)
        #expect(bitmap.pixelsWide == Int(size.width) * 2 && bitmap.pixelsHigh == Int(size.height) * 2,
                "\(name) 가 \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)px 다 — 고정 창을 넘치거나 모자란다")
        #expect(gpYellowPixels(bitmap) == 0, "\(name) 에 노란 상자가 있다 — Picker/Menu/TextField 가 섞였다")
    }

    // 상대가 많아도 목록 카드가 608pt 본문을 넘지 않는다(2026-09-16 실측 결함: 10명에서 카드가 창 아래로 뚫고 나갔다).
    // 창 아래 여백 띠(마지막 20pt 중 안쪽 16pt)는 사람이 2명이든 10명이든 **한 픽셀도 달라지지 않아야** 한다.
    let crowded = try gpBitmap(gpPanel(gpLobbyStore(outgoing: false)))
    let sparse = gpLobbyStore(outgoing: false)
    sparse.users = Array(sparse.users.prefix(2))
    let few = try gpBitmap(gpPanel(sparse))
    let band = CGRect(x: 0, y: size.height - GomokuWindowLayout.contentPadding + 2,
                      width: size.width, height: GomokuWindowLayout.contentPadding - 4)
    #expect(gpMaxChannelDifference(crowded, few, rect: band) <= 2,
            "상대가 많을 때 목록 카드가 본문 아래 여백까지 자란다 — 창 밖으로 잘린다")
}

/// 상대 목록 조회가 실패하면 빈 목록을 "대결할 사람이 없어요"로 말하지 않는다 — 연결 안내와 [다시 불러오기].
@MainActor
@Test
func lobbyLoadFailureShowsConnectionHelpInsteadOfAnEmptyList() throws {
    func store(users: [GomokuUser], failed: Bool, loaded: Bool) -> GomokuStore {
        let store = gpLobbyStore(outgoing: false)
        store.users = users
        store.incoming = []
        store.notice = nil
        store.lobbyLoadFailed = failed
        store.hasLoadedLobby = loaded
        return store
    }
    let failedEmpty = try gpBitmap(gpPanel(store(users: [], failed: true, loaded: false)))
    let failedList = try gpBitmap(gpPanel(store(users: gpUsers(), failed: true, loaded: true)))
    let emptyLoaded = try gpBitmap(gpPanel(store(users: [], failed: false, loaded: true)))
    let loading = try gpBitmap(gpPanel(store(users: [], failed: false, loaded: false)))
    let okList = try gpBitmap(gpPanel(store(users: gpUsers(), failed: false, loaded: true)))
    gpSave(failedEmpty, name: "lobby-load-failed")
    gpSave(failedList, name: "lobby-load-failed-with-list")
    gpSave(emptyLoaded, name: "lobby-empty")
    gpSave(loading, name: "lobby-loading")
    for (name, bitmap) in [("failedEmpty", failedEmpty), ("failedList", failedList), ("emptyLoaded", emptyLoaded), ("loading", loading)] {
        #expect(gpYellowPixels(bitmap) == 0, "\(name) 에 노란 상자가 있다")
    }
    // 목록 카드 안(왼쪽 540pt 열)에서 실패 화면이 '상대 없음'·'불러오는 중'과 다르게 그려진다.
    let list = CGRect(x: GomokuWindowLayout.contentPadding,
                      y: GomokuWindowLayout.contentPadding + GomokuWindowLayout.headerHeight + GomokuWindowLayout.headerSpacing,
                      width: GomokuWindowLayout.lobbyListWidth, height: GomokuWindowLayout.bodyHeight)
    #expect(gpMaxChannelDifference(failedEmpty, emptyLoaded, rect: list) > 60, "조회 실패가 '대결할 사람이 없어요'와 똑같이 보인다")
    #expect(gpMaxChannelDifference(loading, emptyLoaded, rect: list) > 60, "불러오는 중이 '대결할 사람이 없어요'와 똑같이 보인다")
    #expect(gpMaxChannelDifference(failedList, okList, rect: list) > 60, "목록이 있을 때 조회 실패 안내가 안 보인다")
}

/// 사각형(pt) 안에서 두 비트맵의 채널 최대 차(0 이면 한 바이트도 다르지 않다).
private func gpMaxChannelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
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

@MainActor
@Test
func blackTurnMarksForbiddenPointsWithAnX() throws {
    let blackTurn = try gpBitmap(gpPanel(gpPlayingStore(turn: .black)))
    let whiteTurn = try gpBitmap(gpPanel(gpPlayingStore(turn: .white)))
    gpSave(blackTurn, name: "playing-black-turn")
    gpSave(whiteTurn, name: "playing-white-turn")
    #expect(gpYellowPixels(blackTurn) == 0)
    #expect(gpYellowPixels(whiteTurn) == 0)

    let geometry = GomokuBoardGeometry(side: GomokuWindowLayout.boardSide)
    let h8 = try #require(GomokuPoint(notation: "H8"))
    let spot = geometry.location(of: h8)
    let x = gpBoardOrigin.x + spot.x, y = gpBoardOrigin.y + spot.y
    let marked = gpPixel(blackTurn, x: x, y: y)
    let plain = gpPixel(whiteTurn, x: x, y: y)
    #expect(gpIsForbiddenRed(marked), "내가 흑이고 흑 차례인데 H8(3-3 금수)에 X 가 없다 \(marked)")
    #expect(!gpIsForbiddenRed(plain), "백 차례인데 X 가 그려졌다 \(plain)")

    // 돌이 놓인 자리에는 X 가 없다(F8 은 흑돌 — 가운데가 어둡다).
    let f8 = try #require(GomokuPoint(notation: "F8"))
    let stone = geometry.location(of: f8)
    let onStone = gpPixel(blackTurn, x: gpBoardOrigin.x + stone.x, y: gpBoardOrigin.y + stone.y)
    #expect(!gpIsForbiddenRed(onStone), "흑돌 위에 X 가 겹쳤다 \(onStone)")
}

@MainActor
@Test
func gomokuResultRendersWinAndLoss() throws {
    for (name, outcome, reason) in [("result-won", GomokuOutcome.won, GomokuEndReason.five),
                                    ("result-lost-timeout", .lost, .timeout),
                                    ("result-draw", .draw, .boardFull)] {
        let bitmap = try gpBitmap(gpPanel(gpResultStore(outcome: outcome, reason: reason)))
        gpSave(bitmap, name: name)
        #expect(gpYellowPixels(bitmap) == 0, "\(name) 에 노란 상자가 있다")
    }
}

@MainActor
@Test
func rulesOverlayRendersAllSixExamples() throws {
    let store = gpPlayingStore(turn: .black)
    store.isRulesVisible = true
    let bitmap = try gpBitmap(gpPanel(store))
    gpSave(bitmap, name: "rules")
    #expect(gpYellowPixels(bitmap) == 0)

    // 오버레이가 판을 가린다 — 규칙을 연 판과 안 연 판의 H8 자리 픽셀이 다르다.
    let plain = try gpBitmap(gpPanel(gpPlayingStore(turn: .black)))
    #expect(gpDiffCount(bitmap, plain) > 100_000, "규칙 보기가 화면을 거의 안 바꾼다")
    #expect(GomokuRuleExample.all.count == 6)
}

// MARK: - 세 번째 열(v0.3.28): 채팅 · 지금 대결 중 · 자동 착수

/// 세 번째 열(로비 = 지금 대결 중 · 대국/결과 = 채팅)의 창 좌표. **두 화면에서 x 가 같다**
/// (540+400 = 608+332 = 940) — 숫자를 적지 않고 레이아웃 상수에서만 뽑는다.
private var gpThirdColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding + GomokuWindowLayout.innerSize.width - GomokuWindowLayout.chatWidth,
           y: gpBoardOrigin.y, width: GomokuWindowLayout.chatWidth, height: GomokuWindowLayout.bodyHeight)
}

/// 대국 화면 가운데 열(두 사람·판돈·상태줄).
private var gpMatchSideColumn: CGRect {
    CGRect(x: gpBoardOrigin.x + GomokuWindowLayout.boardSide + GomokuWindowLayout.columnSpacing,
           y: gpBoardOrigin.y, width: GomokuWindowLayout.sideColumnWidth, height: GomokuWindowLayout.bodyHeight)
}

@MainActor
private func gpChatStore(muted: Bool = false, messages: Bool = true, draft: String = "") -> GomokuStore {
    let store = gpPlayingStore(turn: .black)
    store.isMuted = muted
    store.chatDraft = draft
    if messages {
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        store.chat = [
            GomokuChatMessage(seq: 1, isMine: false, sentAt: now, quick: nil, body: "안녕하세요, 잘 부탁해요"),
            GomokuChatMessage(seq: 2, isMine: true, sentAt: now.addingTimeInterval(20),
                              quick: .gg, body: GomokuQuickPhrase.gg.text)
        ]
        store.chatSeq = 2
    }
    return store
}

@MainActor
private func gpLiveMatches(_ count: Int) -> [GomokuLiveMatch] {
    let now = Date()
    return (0..<count).map { index in
        GomokuLiveMatch(
            id: "live-\(index)",
            a: gpUser("대결자\(index)", 30 + index, inMatch: true),
            b: gpUser("상대\(index)", 60 + index, inMatch: true),
            stake: [GomokuStake.three, .five, .ten][index % 3],
            startedAt: now.addingTimeInterval(-Double(60 * (index + 1) + 15))
        )
    }
}

/// 채팅 열이 **실제로 픽셀을 그리는지** 재는 장. 빈 로그 · 말풍선 둘 · 음소거 셋이 서로 달라야 한다
/// (셋 다 "아무것도 안 그림"이면 세 비교가 전부 0 이 되어 한꺼번에 빨개진다).
@MainActor
@Test
func chatColumnDrawsLogQuickPhrasesAndComposer() throws {
    let empty = try gpBitmap(gpPanel(gpChatStore(messages: false)))
    let talking = try gpBitmap(gpPanel(gpChatStore()))
    let muted = try gpBitmap(gpPanel(gpChatStore(muted: true)))
    let typed = try gpBitmap(gpPanel(gpChatStore(messages: false, draft: "한 수만 더 생각해 볼게요")))
    gpSave(talking, name: "playing-chat")
    gpSave(muted, name: "playing-chat-muted")
    for (name, bitmap) in [("empty", empty), ("talking", talking), ("muted", muted), ("typed", typed)] {
        // 입력칸이 노란 상자로 그려지면(진짜 AppKit 위젯이 스냅샷에 섞이면) 이 자리의 픽셀 검증이 통째로 눈이 먼다.
        #expect(gpYellowPixels(bitmap) == 0, "\(name) 에 노란 상자가 있다 — 채팅 입력칸이 대체 경로를 안 탔다")
    }
    #expect(gpMaxChannelDifference(empty, talking, rect: gpThirdColumn) > 60, "말풍선이 그려지지 않았다")
    #expect(gpMaxChannelDifference(empty, muted, rect: gpThirdColumn) > 30, "음소거해도 대화 자리가 그대로다")
    #expect(gpMaxChannelDifference(empty, typed, rect: gpThirdColumn) > 30, "입력칸에 친 글자가 안 그려졌다")
    // 내 말풍선은 accent 배경이다 — 빈 로그보다 파란 잉크가 확실히 많아야 한다(머리글 토글도 accent 라 '차이'로 잰다).
    #expect(gpAccentInk(talking, rect: gpThirdColumn) > gpAccentInk(empty, rect: gpThirdColumn) + 200,
            "내 말풍선(accent 배경)이 안 보인다")
    // 판·가운데 열은 채팅이 바뀐다고 흔들리지 않는다(세 열이 서로의 자리를 침범하지 않는다).
    let board = CGRect(x: gpBoardOrigin.x, y: gpBoardOrigin.y,
                       width: GomokuWindowLayout.boardSide, height: GomokuWindowLayout.boardSide)
    #expect(gpMaxChannelDifference(empty, talking, rect: board) <= 2, "채팅이 판 그림을 흔들었다")

    // 결과 화면에도 채팅 열이 남는다(끝난 뒤 인사 120초).
    let finished = gpResultStore(outcome: .won, reason: .five)
    finished.chat = gpChatStore().chat
    let result = try gpBitmap(gpPanel(finished))
    gpSave(result, name: "result-chat")
    #expect(gpYellowPixels(result) == 0)
    #expect(gpMaxChannelDifference(try gpBitmap(gpPanel(gpResultStore(outcome: .won, reason: .five))),
                                   result, rect: gpThirdColumn) > 60,
            "결과 화면에서 채팅 열이 사라졌다 — 끝난 뒤 인사할 자리가 없다")
}

/// 로비 세 번째 열: "지금 대결 중" 카드. 상한 여섯을 넘겨도 열이 본문(608pt)을 뚫지 않는다.
@MainActor
@Test
func lobbyThirdColumnShowsLiveMatches() throws {
    let quiet = gpLobbyStore(outgoing: false)
    let busy = gpLobbyStore(outgoing: false)
    busy.liveMatches = gpLiveMatches(3)
    let crowded = gpLobbyStore(outgoing: false)
    crowded.liveMatches = gpLiveMatches(9)

    let quietBitmap = try gpBitmap(gpPanel(quiet))
    let busyBitmap = try gpBitmap(gpPanel(busy))
    let crowdedBitmap = try gpBitmap(gpPanel(crowded))
    gpSave(busyBitmap, name: "lobby-live-matches")
    gpSave(crowdedBitmap, name: "lobby-live-matches-crowded")
    #expect(gpYellowPixels(busyBitmap) == 0 && gpYellowPixels(crowdedBitmap) == 0)
    #expect(gpMaxChannelDifference(quietBitmap, busyBitmap, rect: gpThirdColumn) > 60,
            "'지금 대결 중' 카드가 안 그려졌다")
    // 상대 목록·판돈 열은 세 번째 열이 차도 그대로다.
    let list = CGRect(x: GomokuWindowLayout.contentPadding, y: gpBoardOrigin.y,
                      width: GomokuWindowLayout.lobbyListWidth, height: GomokuWindowLayout.bodyHeight)
    #expect(gpMaxChannelDifference(quietBitmap, busyBitmap, rect: list) <= 2, "대결 중 목록이 상대 목록을 흔들었다")
    // 아홉 건이어도 창 아래 여백 띠는 한 픽셀도 달라지지 않는다("외 N건"으로 접힌다).
    let size = GomokuWindowLayout.contentSize
    let band = CGRect(x: 0, y: size.height - GomokuWindowLayout.contentPadding + 2,
                      width: size.width, height: GomokuWindowLayout.contentPadding - 4)
    #expect(gpMaxChannelDifference(busyBitmap, crowdedBitmap, rect: band) <= 2,
            "대결이 많을 때 목록이 본문 아래 여백까지 자란다 — 창 밖으로 잘린다")
}

/// 자동으로 놓인 돌은 **작은 회색 점**으로 구분되고, 같은 사실이 상태줄에 글자로도 뜬다(툴팁은 픽셀을 안 만든다).
@MainActor
@Test
func autoPlacedStonesGetAGreyDotAndASpokenStatusLine() throws {
    let plain = gpPlayingStore(turn: .black)
    let auto = gpPlayingStore(turn: .black)
    var match = try #require(auto.match)
    let l4 = try #require(GomokuPoint(notation: "L4"))     // 흑돌이 있고 **마지막 수가 아닌** 자리(D12 가 마지막 수)
    match.autoPoints = [l4]
    auto.match = match
    auto.myAutoStreak = GomokuStore.autoPlaceLossStreak - 1

    let plainBitmap = try gpBitmap(gpPanel(plain))
    let autoBitmap = try gpBitmap(gpPanel(auto))
    gpSave(autoBitmap, name: "playing-auto-placed")
    #expect(gpYellowPixels(autoBitmap) == 0)

    let geometry = GomokuBoardGeometry(side: GomokuWindowLayout.boardSide)
    let spot = geometry.location(of: l4)
    let dot = gpPixel(autoBitmap, x: gpBoardOrigin.x + spot.x, y: gpBoardOrigin.y + spot.y)
    let bare = gpPixel(plainBitmap, x: gpBoardOrigin.x + spot.x, y: gpBoardOrigin.y + spot.y)
    #expect(gpIsAutoGrey(dot), "자동으로 놓인 흑돌에 회색 점이 없다 \(dot)")
    #expect(!gpIsAutoGrey(bare), "사람이 둔 돌에 회색 점이 그려졌다 \(bare)")

    // 툴팁에만 두지 않는다 — 상태줄에 "자동으로 놓인 수 N개"와 연속 경고가 글자로 선다.
    #expect(gpMaxChannelDifference(plainBitmap, autoBitmap, rect: gpMatchSideColumn) > 60,
            "상태줄에 자동 착수 안내·경고가 안 뜬다 — 호버하지 않으면 아무도 모른다")
}

/// 자동 착수 표시색(회색 0.62)인가 — 흑돌 가운데(어둡다)·백돌(밝다) 어느 쪽과도 갈린다.
private func gpIsAutoGrey(_ pixel: (Int, Int, Int)) -> Bool {
    let channels = [pixel.0, pixel.1, pixel.2]
    guard let low = channels.min(), let high = channels.max() else { return false }
    return low >= 130 && high <= 190 && high - low <= 25
}

/// 사각형(pt) 안에서 파랑이 확실히 앞서는 픽셀 수(CheckTheme.accent 계열 — 내 말풍선 배경·강조 글자).
private func gpAccentInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
            if b > 140 && b > r + 60 && b > g + 30 { count += 1 }
        }
    }
    return count
}

// MARK: - 팝오버 배너

@MainActor
@Test
func popoverInviteBannerFitsItsHeightBudget() throws {
    let invite = GomokuInvite(id: "in-1", peer: gpMinsu, stake: 5, expiresAt: Date().addingTimeInterval(48))
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let plain = try gpBitmap(CheckMenuView(store: gpTeamStore(now: now)))
    let banner = try gpBitmap(CheckMenuView(store: gpTeamStore(now: now), previewGomokuInvite: invite))
    gpSave(banner, name: "popover-banner")
    #expect(gpYellowPixels(banner) == 0)
    let grown = Double(banner.pixelsHigh - plain.pixelsHigh) / 2
    #expect(abs(grown - Double(CheckMenuView.gomokuInviteBannerHeight)) <= 1,
            "배너가 팝오버를 \(grown)pt 늘렸는데 예산은 \(CheckMenuView.gomokuInviteBannerHeight)pt 로 센다")
    #expect(Double(banner.pixelsHigh) / 2 <= 700, "배너를 얹은 팝오버가 700pt 상한을 넘는다")
    #expect(banner.pixelsWide == plain.pixelsWide, "배너가 팝오버 폭을 바꿨다")

    let alone = try gpBitmap(
        GomokuInviteBanner(invite: invite, onAccept: {}, onDecline: {})
            .frame(width: CheckMenuView.contentColumnWidth)
            .padding(8)
            .background(CheckTheme.background)
    )
    gpSave(alone, name: "banner")
    #expect(gpYellowPixels(alone) == 0)
}

// MARK: - 미니게임 헤더 입구

@MainActor
@Test
func miniGameHeaderShowsTheGomokuEntry() throws {
    defer { MiniGameSpaceKey.remove() }
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let store = gpTeamStore(now: now)
    store.isMiniGamePanelVisible = true
    store.miniGameBoardLoaded = true
    let bitmap = try gpBitmap(
        CheckMiniGameWindowView(store: store, clipsOverflowInsteadOfScroll: true)
            .background(CheckTheme.background)
    )
    gpSave(bitmap, name: "minigame-header-entry")
    #expect(gpYellowPixels(bitmap) == 0)

    // 게임 열 머리글 띠 안에 입구의 초록 글자·아이콘이 있고, 344pt 열 밖으로 넘치지 않는다.
    let band = CGRect(
        x: MiniGameWindowLayout.contentPadding, y: MiniGameWindowLayout.contentPadding,
        width: MiniGameWindowLayout.canvasSize.width, height: MiniGameWindowLayout.headerHeight
    )
    let greens = gpGreenInk(bitmap, rect: band.insetBy(dx: -30, dy: 0))
    #expect(greens.count > 40, "미니게임 헤더에 [1:1 오목] 입구가 안 보인다(초록 픽셀 \(greens.count))")
    #expect(Double(greens.maxX) / 2 <= Double(band.maxX), "입구가 게임 열(344pt) 밖으로 넘친다(maxX \(Double(greens.maxX) / 2)pt)")

    let entry = try gpBitmap(MiniGameGomokuEntryButton(action: {}))
    #expect(Double(entry.pixelsWide) / 2 <= 100, "입구 버튼이 \(Double(entry.pixelsWide) / 2)pt 다 — 칩 둘과 한 줄에 못 선다")
}

// MARK: - 규칙 예시 · 문구(순수)

/// 규칙 보기의 예시 좌표는 코퍼스에서 옮긴 것이다 — 옮기다 틀리면 "3-3 금수" 그림이 금수가 아닌 판을 보여 준다.
@Test
func ruleExamplesMatchTheJudgeAndFitTheCrop() throws {
    #expect(GomokuRuleExample.all.map(\.id) == ["K01", "K12", "K19", "K24", "K28", "K34"])
    let crop = GomokuRuleExample.cropGeometry
    let geometry = GomokuBoardGeometry(side: 158, lines: crop.lines, originX: crop.originX, originY: crop.originY)
    for example in GomokuRuleExample.all {
        let stones = example.black + example.white + [example.point] + (example.pivot.map { [$0] } ?? [])
        for notation in stones {
            let point = try #require(GomokuPoint(notation: notation), "\(example.id) 의 '\(notation)' 이 정규형 좌표가 아니다")
            #expect(geometry.contains(point), "\(example.id) 의 \(notation) 이 예시 그림(9×9) 밖이다")
        }
        let point = try #require(GomokuPoint(notation: example.point))
        #expect(example.board[point] == nil, "\(example.id) 의 착점이 이미 차 있다")
        #expect(GomokuRules.judge(board: example.board, point: point, color: .black) == example.expected,
                "\(example.id) 판정이 예시 설명과 다르다")
    }
    // 거짓 3 의 전환점(I8)은 장목 자리다 — 그래서 가로가 3이 아니다.
    let falseThree = try #require(GomokuRuleExample.all.first { $0.id == "K34" })
    let pivot = try #require(falseThree.pivot.flatMap { GomokuPoint(notation: $0) })
    var withH8 = falseThree.board
    withH8[try #require(GomokuPoint(notation: "H8"))] = .black
    #expect(GomokuRules.judge(board: withH8, point: pivot, color: .black) == .forbidden(.overline))
}

@MainActor
@Test
func gomokuTextIsPlainUserLanguage() throws {
    #expect(GomokuText.forbiddenStatus(.doubleThree) == "3-3 금수라 둘 수 없어요")
    #expect(GomokuText.forbiddenStatus(.doubleFour) == "4-4 금수라 둘 수 없어요")
    #expect(GomokuText.forbiddenStatus(.overline) == "장목 금수라 둘 수 없어요")
    #expect(GomokuText.forbiddenStatus(.budget) == "판정할 수 없는 자리예요")
    #expect(GomokuText.forbiddenTooltip(.doubleThree) == "3-3 금수 자리예요")
    #expect(GomokuText.remaining(18.2) == "19초")
    #expect(GomokuText.remaining(0) == "0초")
    #expect(GomokuText.remaining(-3) == "0초")
    #expect(GomokuText.rubyDelta(10) == "+10")
    #expect(GomokuText.rubyDelta(-5) == "−5")
    #expect(GomokuText.rubyDelta(0) == "±0")
    // 판돈 줄은 순수익 기준 — 결과 카드의 루비 변화(+10)와 같은 숫자를 말한다.
    #expect(GomokuText.stakeLine(10) == "10 · 이기면 +10")
    #expect(GomokuText.rubyDelta(10) == "+10")
    #expect(GomokuRuleExample.ruleLines[6].contains("판돈만큼 더"), "규칙 보기의 판돈 설명이 결과 카드와 다른 숫자를 말한다")
    #expect(!GomokuRuleExample.ruleLines[6].contains("두 배") && !GomokuText.stakeCaption.contains("두 배"))
    // 보이스오버 문구.
    let match = try #require(gpPlayingStore(turn: .black).match)
    #expect(GomokuText.boardAccessibility(match, forbiddenCount: 1)
            == "오목판, 흑 5개, 백 5개, 마지막 수 D12, 내 차례예요, 금수 자리 1곳")
    var waiting = match
    waiting.turn = .white
    #expect(GomokuText.boardAccessibility(waiting, forbiddenCount: 0) == "오목판, 흑 5개, 백 5개, 마지막 수 D12, 상대 차례예요")
    #expect(GomokuText.clockAccessibility(18.2) == "남은 시간 19초")
    #expect(GomokuText.record(nil) == "전적 —")
    #expect(GomokuText.record(GomokuRecord(wins: 3, losses: 2, draws: 1)) == "3승 2패 1무")
    #expect(GomokuText.status(for: gpUser("a", 1, inMatch: true)) == "대국 중")
    #expect(GomokuText.status(for: gpUser("a", 1, working: false, capable: false)) == "업데이트 필요")
    #expect(GomokuText.status(for: gpUser("a", 1)) == "근무 중")
    #expect(GomokuText.status(for: gpUser("a", 1, working: false)) == "근무 안 함")

    var shown: [String] = [
        GomokuText.subtitle, GomokuText.lobbyCaption, GomokuText.emptyUsers, GomokuText.stakeCaption,
        GomokuText.noIncoming, GomokuText.myTurn, GomokuText.opponentTurn, GomokuText.blackPassed,
        GomokuText.resignConfirm, GomokuText.inviteBannerSubtitle, GomokuText.inviteTitle(name: "민수"),
        CheckOverlayController.gomokuInviteBubbleText(name: "민수", stake: 5),
        GomokuText.loadingUsers, GomokuText.usersLoadFailed, GomokuText.reloadUsers, GomokuText.stakeLine(5),
        GomokuText.clockAccessibility(7), GomokuText.boardAccessibility(match, forbiddenCount: 2),
        CheckOverlayController.gomokuAttentionBubbleText(
            GomokuAttention(kind: .myTurn, matchID: "m", opponentName: "민수", moveCount: 2)),
        CheckOverlayController.gomokuAttentionBubbleText(
            GomokuAttention(kind: .matchStarted, matchID: "m", opponentName: "민수", moveCount: 0)),
        GomokuNoticeText.inviteDeclined, GomokuNoticeText.timedOut
    ]
    for reason in [GomokuForbiddenReason.doubleThree, .doubleFour, .overline, .budget] {
        shown += [GomokuText.forbiddenStatus(reason), GomokuText.forbiddenTooltip(reason)]
    }
    for reason in [GomokuEndReason.five, .timeout, .resign, .boardFull, .abandoned] {
        for outcome in [GomokuOutcome.won, .lost, .draw] {
            shown.append(GomokuText.endReason(reason, outcome: outcome))
        }
    }
    // v0.3.28 세 번째 열(채팅 · 지금 대결 중)과 자동 착수 문구도 같은 잣대를 지난다.
    shown += GomokuQuickPhrase.allCases.map(\.text)
    shown += [
        GomokuText.chatTitle, GomokuText.chatMute, GomokuText.chatUnmute, GomokuText.chatEmpty,
        GomokuText.chatPlaceholder, GomokuText.chatSend, GomokuText.chatSendHelp,
        GomokuText.chatMuteHelp, GomokuText.chatUnmuteHelp,
        GomokuText.liveTitle, GomokuText.noLiveMatches, GomokuText.elapsed(75), GomokuText.more(3),
        GomokuText.autoPlacedCount(2),
        GomokuNoticeText.chatMutedByMe, GomokuNoticeText.chatMutedByOpponent,
        GomokuNoticeText.chatOpponentOutdated, GomokuNoticeText.chatBlocked,
        GomokuNoticeText.chatTooLong(100), GomokuNoticeText.autoPlaced, GomokuNoticeText.autoPlacedStone,
        GomokuNoticeText.abandoned(outcome: .won), GomokuNoticeText.abandoned(outcome: .lost)
    ]
    shown += [GomokuNoticeText.autoStreakWarning(GomokuStore.autoPlaceLossStreak - 1)].compactMap { $0 }
    // 경고는 **한 번 남았을 때만** 뜬다(첫 번째부터 겁을 주면 매 판 뜨고, 그러면 아무도 안 읽는다).
    #expect(GomokuNoticeText.autoStreakWarning(GomokuStore.autoPlaceLossStreak - 1) != nil)
    #expect(GomokuNoticeText.autoStreakWarning(0) == nil)
    // 규칙 보기의 시간 설명이 새 규칙을 말한다(시간 초과 = 패배가 아니라 무작위 대리 착수).
    #expect(GomokuRuleExample.ruleLines[4].contains("무작위") && GomokuRuleExample.ruleLines[4].contains("3번 연속"))
    #expect(!GomokuRuleExample.ruleLines[4].contains("차례인 사람이 져요"), "옛 시간 규칙이 규칙 보기에 남아 있다")
    #expect(GomokuText.elapsed(75) == "1:15" && GomokuText.elapsed(0) == "0:00" && GomokuText.elapsed(-5) == "0:00")
    shown += GomokuRuleExample.ruleLines
    shown += GomokuRuleExample.all.flatMap { [$0.title, $0.detail] }
    let banned = ["서버", "로컬", "계정", "실시간", "RPC", "rpc", "status", "timeout", "budget", "forbidden", "null", "오류 코드"]
    for text in shown {
        for word in banned {
            #expect(!text.contains(word), "사용자 문구 '\(text)' 에 진단 어휘 '\(word)' 가 있다")
        }
    }
}

// MARK: - 소스 계약(주석을 걷어낸 뒤)

@Test
func gomokuPanelKeepsClocksInLeavesAndUsesNoYellowBoxControls() throws {
    let panel = gpStripped(try gpSource("GomokuPanel.swift"))
    #expect(panel.components(separatedBy: ".checkTooltipLayer()").count - 1 == 1, "툴팁 레이어가 루트 하나가 아니다")
    // 금지 목록은 **그대로다**. 다만 채팅 입력칸의 정본 위젯 `CheckTextEditor(` 는 문자열로 보면
    // `TextEditor(` 를 품고 있어(부분 문자열), 그대로 검사하면 써야 할 위젯이 금지에 걸린다.
    // 그래서 그 이름만 먼저 가리고 **맨몸 `TextEditor(`** 가 남는지 본다 — 목록을 푸는 것이 아니라 두 이름을 가르는 것이다.
    let bare = panel.replacingOccurrences(of: "CheckTextEditor(", with: "CheckEditorWidget<")
    for forbidden in ["Picker(", "Menu(", "TextField(", "TextEditor(", ".help("] {
        #expect(!bare.contains(forbidden), "오목 화면에 \(forbidden) 가 있다")
    }
    // 가려 놓고 아무것도 안 쓰면 위 검사가 헐거워진다 — 그 위젯이 실제로 서 있는지 되묻는다.
    #expect(panel.contains("CheckTextEditor("), "채팅 입력칸이 정본 위젯(CheckTextEditor)을 안 쓴다")
    // 전송 세 갈래가 **한 문**을 지난다(확정 먼저 — IME 마지막 음절 유실 방지).
    #expect(panel.contains("CheckEditorSend.commitThenSend { store.sendChatDraft() }"),
            "채팅 전송이 조합 확정 문을 안 지난다 — 마지막 음절이 빠진 채 나간다")
    #expect(panel.contains(".keyboardShortcut(.return, modifiers: .command)"), "채팅 ⌘↩ 경로가 없다")
    #expect(panel.contains("onRenderedEmptyChange:"), "placeholder 를 스토어 값으로 판정한다 — 조합 중 글자와 겹친다")
    // 창 루트(GomokuPanel)는 시계를 읽지 않는다 — 초 단위 값은 잎 뷰 둘에서만.
    let root = try #require(gpRegion(panel, from: "struct GomokuPanel: View {", to: "private struct GomokuHeader: View {"))
    for clock in ["TimelineView", "remainingSeconds", "Date()", "expiresAt"] {
        #expect(!root.contains(clock), "창 루트가 '\(clock)' 를 읽는다 — 창 전체가 매 틱 다시 그려진다")
    }
    #expect(panel.components(separatedBy: "remainingSeconds(").count - 1 == 1, "남은 시간을 잎 뷰 밖에서도 읽는다")
    let clock = try #require(gpRegion(panel, from: "struct GomokuTurnClock: View {", to: "// MARK:"))
    #expect(clock.contains("remainingSeconds(now: context.date)"))

    // 보이스오버: 판은 한 요소로(돌 수·마지막 수·차례), 차례 링은 남은 초, 상태줄(금수 이유)은 한 문장으로 읽힌다.
    let board = try #require(gpRegion(panel, from: "private struct GomokuPlayBoard: View {", to: "private struct GomokuMatchSide: View {"))
    #expect(board.contains(".accessibilityLabel(GomokuText.boardAccessibility(match, forbiddenCount: forbidden.count))"),
            "판에 보이스오버 라벨이 없다")
    let ring = try #require(gpRegion(panel, from: "struct GomokuTurnClock: View {", to: "private struct GomokuResultCard: View {"))
    #expect(ring.contains(".accessibilityLabel(GomokuText.clockAccessibility(remaining))"), "차례 링에 남은 시간 라벨이 없다")
    let side = try #require(gpRegion(panel, from: "private struct GomokuMatchSide: View {", to: "private struct GomokuPlayerCard: View {"))
    #expect(side.contains(".accessibilityElement(children: .combine)"), "상태줄(금수 이유)이 한 문장으로 읽히지 않는다")

    // 팝오버 배너는 시계를 전혀 읽지 않는다(팝오버 트리 — V0238 무효화 계약).
    let banner = try #require(gpRegion(panel, from: "struct GomokuInviteBanner: View {", to: "private struct GomokuActionButton: View {"))
    for clock in ["TimelineView", "expiresAt", "Date(", "displayNow"] {
        #expect(!banner.contains(clock), "팝오버 배너가 '\(clock)' 를 읽는다")
    }

    let menu = gpStripped(try gpSource("CheckMenuView.swift"))
    #expect(!menu.contains("expiresAt"), "팝오버가 신청 만료 시각을 직접 비교한다 — 판정은 스토어 결과만 읽는다")
    let longSession = try #require(menu.range(of: "if isMainScreen, showsLongSessionBanner { return .longSession }"))
    let gomoku = try #require(menu.range(of: "if store.isSignedIn, gomokuBannerInvite != nil { return .gomokuInvite }"))
    let retro = try #require(menu.range(of: "if store.isSignedIn, store.showsRetroBanner { return .retro }"))
    #expect(longSession.lowerBound < gomoku.lowerBound && gomoku.lowerBound < retro.lowerBound,
            "배너 우선순위가 longSession > gomokuInvite > retro 가 아니다")
    #expect(menu.contains("case .gomokuInvite: return Self.gomokuInviteBannerHeight"), "배너 높이가 목록 행수 예산에 안 들어간다")

    let miniGame = gpStripped(try gpSource("MiniGamePanel.swift"))
    #expect(miniGame.contains("MiniGameGomokuEntryButton { store.gomoku.openWindow(focusMatchID: nil) }"),
            "미니게임 헤더 입구가 오목 창을 안 연다")
}

// MARK: - 헬퍼

private enum GPRenderError: Error { case failed }

@MainActor
private func gpBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw GPRenderError.failed }
    return bitmap
}

private func gpSave(_ bitmap: NSBitmapImageRep, name: String) {
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "gomoku")
}

/// ImageRenderer 가 AppKit 기반 컨트롤을 대신 그리는 노란 상자(255,204,0)의 픽셀 수.
private func gpYellowPixels(_ bitmap: NSBitmapImageRep) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return -1 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var hits = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            if data[o] >= 240 && data[o + 1] >= 195 && data[o + 2] <= 40 { hits += 1 }
        }
    }
    return hits
}

private func gpPixel(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) -> (Int, Int, Int) {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return (0, 0, 0) }
    let px = min(max(Int(x * 2), 0), bitmap.pixelsWide - 1)
    let py = min(max(Int(y * 2), 0), bitmap.pixelsHigh - 1)
    let o = py * bitmap.bytesPerRow + px * bitmap.samplesPerPixel
    return (Int(data[o]), Int(data[o + 1]), Int(data[o + 2]))
}

private func gpIsForbiddenRed(_ pixel: (Int, Int, Int)) -> Bool {
    pixel.0 > 170 && pixel.1 < 110 && pixel.2 < 110
}

private func gpDiffCount(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
          let pa = a.bitmapData, let pb = b.bitmapData else { return Int.max }
    let bpr = a.bytesPerRow, spp = a.samplesPerPixel
    var count = 0
    for y in 0..<a.pixelsHigh {
        for x in 0..<a.pixelsWide {
            let o = y * bpr + x * spp
            if abs(Int(pa[o]) - Int(pb[o])) > 8 || abs(Int(pa[o + 1]) - Int(pb[o + 1])) > 8 { count += 1 }
        }
    }
    return count
}

/// 사각형(pt) 안 초록 잉크(CheckTheme.working 글자·아이콘) 픽셀 수와 가장 오른쪽 픽셀 x(px).
private func gpGreenInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> (count: Int, maxX: Int) {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return (0, 0) }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return (0, 0) }
    var count = 0, maxX = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            let r = Int(data[o]), g = Int(data[o + 1])
            if g > r + 80 && g > 150 {
                count += 1
                maxX = max(maxX, x)
            }
        }
    }
    return (count, maxX)
}

@MainActor
private func gpTeamStore(now: Date) -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: gpDefaults("check-v0327-gomoku-render-tests"),
        tokenUsage: gpInertTokenStore()
    )
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.displayNow = now
    store.teamMembers = [
        TeamMemberStatus(id: "00000000-0000-0000-0000-000000000002", name: "영식", status: .working, updatedAt: nil,
                         currentSessionStartedAt: now.addingTimeInterval(-3_661), weeklyDurationSeconds: 14_400,
                         avatarURL: CheckMascotAssets.url(for: .neutral)),
        TeamMemberStatus(id: "00000000-0000-0000-0000-000000000003", name: "민수", status: .working,
                         updatedAt: now.addingTimeInterval(-420), currentSessionStartedAt: now.addingTimeInterval(-7_620),
                         weeklyDurationSeconds: 28_800, lastSeenAt: now.addingTimeInterval(-420)),
        TeamMemberStatus(id: "00000000-0000-0000-0000-000000000001", name: "yesung", status: .offWork, updatedAt: nil,
                         currentSessionStartedAt: nil, weeklyDurationSeconds: 7_200)
    ]
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    return store
}

/// 고정 이름 스위트(UUID 스위트는 실행마다 plist 를 영구히 쌓는다).
private func gpDefaults(_ suiteName: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func gpInertTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    return TokenUsageStore(
        defaults: gpDefaults("check-v0327-gomoku-render-token-tests"),
        homeDirectory: tmp.appendingPathComponent("check-v0327-gomoku-token-home", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-v0327-gomoku-token-cache.json", isDirectory: false)
    )
}

private func gpSource(_ name: String) throws -> String {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check", isDirectory: true)
    return try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
}

/// `from` 부터 그 뒤 첫 `to` 직전까지(없으면 nil).
private func gpRegion(_ source: String, from start: String, to end: String) -> String? {
    guard let head = source.range(of: start) else { return nil }
    let tail = source.range(of: end, range: head.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
    return String(source[head.upperBound..<tail])
}

/// 주석을 걷어내고 공백을 한 칸으로 접는다(V0317ShopTests.stripped 와 같은 규칙).
private func gpStripped(_ source: String) -> String {
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
