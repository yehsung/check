import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

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
                    inMatch: Bool = false, character: String? = "shiba", center: String? = nil) -> GomokuUser {
    GomokuUser(
        id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))",
        displayName: name, avatarURL: nil, characterID: character,
        isWorking: working, isCapable: capable, inMatch: inMatch, center: center
    )
}

/// 같은 사람에 **센터만** 얹은 사본. 다른 칸은 한 글자도 안 바꾼다 — 그래야 두 그림의 차이가
/// 오직 배지에서만 온다(이름·상태가 함께 바뀌면 배선이 끊겨도 차이가 나서 초록이 된다).
private func gpWithCenter(_ user: GomokuUser, _ center: String) -> GomokuUser {
    var copy = user
    copy.center = center
    return copy
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
private func gpPanel(_ store: GomokuStore, me: GomokuPlayerFace = gpMe) -> some View {
    GomokuPanel(store: store, me: { me }, clipsOverflowInsteadOfScroll: true)
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

// MARK: - 대국 채팅(v0.3.28 · v0.3.30 오른쪽 열 안) · 지금 대결 중 · 자동 착수

/// 대국 화면 **채팅 카드**의 창 좌표(v0.3.30 — 오른쪽 열 안, 카드들과 [기권] 사이). 숫자는 레이아웃 상수에서만 뽑는다.
/// 위: 두 카드(84×2) + 간격 10×2 + 판돈 줄(상태 상자 한 줄 = 최소 높이 44) + 간격 10. 아래: [기권] 34 + 간격 10.
/// 실측(2026-09-17): 넓은 획 행 72·156(상대 카드) · 314(채팅 카드 윗변) · 523·547·552·576(칩 두 줄) ·
/// 584·624(입력칸) · 636(채팅 카드 아랫변) · 646~680([기권]).
private var gpChatCard: CGRect {
    let top = gpMatchSideColumn.minY + GomokuWindowLayout.playerCardHeight * 2
        + GomokuWindowLayout.matchSideSpacing * 3 + 44
    let bottom = gpMatchSideColumn.maxY - 34 - GomokuWindowLayout.matchSideSpacing
    return CGRect(x: gpMatchSideColumn.minX, y: top, width: gpMatchSideColumn.width, height: bottom - top)
}

/// 대국 화면 오른쪽 열(두 사람·판돈·상태줄·채팅·기권 — v0.3.30 부터 이 열 하나다).
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

/// 채팅 카드가 **실제로 픽셀을 그리는지** 재는 장. 빈 로그 · 말풍선 둘 · 음소거 셋이 서로 달라야 한다
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
    #expect(gpMaxChannelDifference(empty, talking, rect: gpChatCard) > 60, "말풍선이 그려지지 않았다")
    #expect(gpMaxChannelDifference(empty, muted, rect: gpChatCard) > 30, "음소거해도 대화 자리가 그대로다")
    #expect(gpMaxChannelDifference(empty, typed, rect: gpChatCard) > 30, "입력칸에 친 글자가 안 그려졌다")
    // 내 말풍선은 accent 배경이다 — 빈 로그보다 파란 잉크가 확실히 많아야 한다(머리글 토글도 accent 라 '차이'로 잰다).
    #expect(gpAccentInk(talking, rect: gpChatCard) > gpAccentInk(empty, rect: gpChatCard) + 200,
            "내 말풍선(accent 배경)이 안 보인다")
    // 판·두 사람 카드·[기권]은 채팅이 바뀐다고 흔들리지 않는다(채팅 카드가 제 자리 밖을 침범하지 않는다).
    let board = CGRect(x: gpBoardOrigin.x, y: gpBoardOrigin.y,
                       width: GomokuWindowLayout.boardSide, height: GomokuWindowLayout.boardSide)
    #expect(gpMaxChannelDifference(empty, talking, rect: board) <= 2, "채팅이 판 그림을 흔들었다")
    let resign = CGRect(x: gpMatchSideColumn.minX, y: gpChatCard.maxY + 2,
                        width: gpMatchSideColumn.width, height: gpMatchSideColumn.maxY - gpChatCard.maxY - 2)
    #expect(gpMaxChannelDifference(empty, talking, rect: resign) <= 2, "대화가 쌓이자 [기권]이 밀렸다")

    // --- 빠른 문구 격자를 **따로** 잰다 ---
    // 위 네 장은 격자에 대해 모두 같은 입력(isSendingChat·isOpponentMuted·opponentChatCapable·chatNotice 가
    // 전부 같다)이라 격자가 네 장에서 같은 자리·같은 픽셀로 앉아 **모든 차이값에서 상쇄된다** —
    // `GomokuQuickPhraseGrid(store: store)` 한 줄을 지워도 위 단언이 전부 초록이었다(2026-09-16 실측).
    // v0.3.30: 칩 4열 × 2줄 · 칩 높이 24pt · 줄 간격 5pt → 격자 높이 2×24 + 5 = 53pt.
    // 격자 아래는 간격 8 + 입력 줄 40 + 카드 안쪽 여백 12 = 60pt 다.
    let chipHeight = 24, chipGap = 5, chipRows = 2
    let gridHeight = CGFloat(chipRows * chipHeight + (chipRows - 1) * chipGap)
    let gridBand = CGRect(x: gpChatCard.minX, y: gpChatCard.maxY - 60 - gridHeight,
                          width: gpChatCard.width, height: gridHeight)
    // ① 칩이 **실제로 픽셀을 그린다** — 높이 24pt 짜리 상자 두 줄이 예산 자리에 정확히 선다.
    //    (재는 사각형을 채팅 카드로 좁힌다 — [기권]의 채운 면은 연속한 넓은 행이라 24pt 짝을 가짜로 만든다.)
    let chipTops = gpBoxTops(talking, rect: gpChatCard, height: chipHeight)
    #expect(chipTops == (0..<chipRows).map { Int(gridBand.minY) + $0 * (chipHeight + chipGap) },
            "빠른 문구 칩 \(chipRows)줄(높이 \(chipHeight)pt · 간격 \(chipGap)pt)이 예산 자리에 없다 — 찾은 줄 \(chipTops)")
    // ② 격자는 로그 **아래 고정**이다 — 말이 오가도, 음소거해도 그 자리가 안 움직인다.
    #expect(gpMaxChannelDifference(empty, talking, rect: gridBand) <= 2, "대화가 쌓이자 빠른 문구 격자가 밀렸다")
    #expect(gpMaxChannelDifference(empty, muted, rect: gridBand) <= 2, "음소거하자 빠른 문구 격자가 밀렸다")
    // ③ 보내는 중이면 칩이 비활성으로 흐려진다(`.disabled(store.isSendingChat)`). 격자 자리에서만 재서
    //    머리글 토글·보내기 버튼이 같이 흐려지는 것과 섞이지 않게 한다.
    let sendingStore = gpChatStore()
    sendingStore.isSendingChat = true
    let sending = try gpBitmap(gpPanel(sendingStore))
    gpSave(sending, name: "playing-chat-sending")
    #expect(gpYellowPixels(sending) == 0, "sending 에 노란 상자가 있다")
    #expect(gpMaxChannelDifference(talking, sending, rect: gridBand) > 30,
            "보내는 중인데 빠른 문구 칩이 그대로다 — 그 자리에 격자가 없다")

    // 결과 화면에도 채팅 카드가 남는다(끝난 뒤 인사 120초) — 오른쪽 열 아래쪽(결과 카드 밑)에서 잰다.
    let finished = gpResultStore(outcome: .won, reason: .five)
    finished.chat = gpChatStore().chat
    let result = try gpBitmap(gpPanel(finished))
    gpSave(result, name: "result-chat")
    #expect(gpYellowPixels(result) == 0)
    let resultChat = CGRect(x: gpMatchSideColumn.minX, y: gpMatchSideColumn.minY + 300,
                            width: gpMatchSideColumn.width, height: gpMatchSideColumn.height - 300)
    #expect(gpMaxChannelDifference(try gpBitmap(gpPanel(gpResultStore(outcome: .won, reason: .five))),
                                   result, rect: resultChat) > 60,
            "결과 화면에서 채팅 카드가 사라졌다 — 끝난 뒤 인사할 자리가 없다")
}

/// 채팅 로그는 **언제나 최신 말에 붙는다**.
///
/// 이 자리는 픽셀로 못 잰다: 앱 갈래는 `ScrollView` 인데 ImageRenderer 는 그 안을 못 그려서, 스냅샷은
/// 언제나 클립 갈래(맨 아래 = 최신)만 본다. 그래서 앱만 맨 위에 멈춰 있어도 렌더 검증이 전부 초록이었다
/// (2026-09-16 실측: 앱 갈래에 `ScrollViewReader`·`defaultScrollAnchor`·`scrollTo` 가 하나도 없었다).
/// 정본은 `MessageConversationView`(CheckMessageView.swift) — 두 갈래가 **같은 끝**을 그리고, 맨 아래로
/// 보내는 계기 셋이 **한 함수 안에** 모여 있다. 여기서는 그 네 조각이 서 있는지를 소스로 묻는다.
@Test
func chatLogSticksToTheNewestMessageInBothBranches() throws {
    let panel = gpStripped(try gpSource("GomokuPanel.swift"))
    let column = try #require(gpRegion(panel, from: "private struct GomokuChatCard: View {",
                                       to: "private struct GomokuChatBubble: View {"))
    #expect(column.contains("ScrollViewReader"), "채팅 로그가 ScrollViewReader 없이 그려진다 — 최신 말로 못 내려간다")
    #expect(column.contains(".defaultScrollAnchor(.bottom)"), "채팅 로그가 처음부터 맨 아래에 서지 않는다")
    #expect(column.contains("proxy.scrollTo("), "맨 아래로 보내는 호출이 없다")
    // 계기 셋 — 하나만 빠져도 **그 상황에서만** 위에 멈춘다(그래서 셋을 따로 묻는다).
    #expect(column.contains(".onAppear"), "처음 열 때 맨 아래로 가지 않는다")
    #expect(column.contains("onChange(of: store.match?.id)"), "판이 바뀌어도 앞 판 자리에 멈춰 있다")
    #expect(column.contains("onChange(of: store.chat.last?.seq)"), "새 말이 와도 따라 내려가지 않는다")
    // 클립 갈래(스냅샷)도 **같은 끝**이다 — 두 그림이 다르면 스냅샷으로 아무것도 확인할 수 없다.
    #expect(column.contains("overlay(alignment: .bottom)"), "스냅샷 갈래가 아래(최신)를 기준으로 그리지 않는다")
}

/// 로비 오른쪽 **위** 칸: "지금 대결 중". v0.3.29 부터 **자르지 않고 스크롤한다** —
/// 옛 상한(`maxCards = 6`)과 "외 N건" 줄은 없앴다(사용자 요구).
///
/// 스냅샷은 클립 갈래를 타므로(ImageRenderer 는 ScrollView 안을 못 그린다) **칸에 들어가는 만큼만** 보인다.
/// 그래서 "12건과 20건이 한 픽셀도 다르지 않다"가 곧 '접은 것이 아니라 잘랐다'의 증거다 — 상한으로
/// 접는 화면이었다면 그 자리에 '외 6건'과 '외 14건'이라는 **서로 다른 글자**가 섰을 것이다.
@MainActor
@Test
func lobbyRightColumnScrollsLiveMatchesInsteadOfTruncating() throws {
    let quiet = gpLobbyStore(outgoing: false)
    let busy = gpLobbyStore(outgoing: false)
    busy.liveMatches = gpLiveMatches(3)
    let crowded = gpLobbyStore(outgoing: false)
    crowded.liveMatches = gpLiveMatches(9)
    let many = gpLobbyStore(outgoing: false)
    many.liveMatches = gpLiveMatches(12)
    let tooMany = gpLobbyStore(outgoing: false)
    tooMany.liveMatches = gpLiveMatches(20)

    let quietBitmap = try gpBitmap(gpPanel(quiet))
    let busyBitmap = try gpBitmap(gpPanel(busy))
    let crowdedBitmap = try gpBitmap(gpPanel(crowded))
    let manyBitmap = try gpBitmap(gpPanel(many))
    let tooManyBitmap = try gpBitmap(gpPanel(tooMany))
    gpSave(busyBitmap, name: "lobby-live-matches")
    gpSave(crowdedBitmap, name: "lobby-live-matches-crowded")
    gpSave(manyBitmap, name: "lobby-live-matches-many")
    for (name, bitmap) in [("3건", busyBitmap), ("9건", crowdedBitmap), ("12건", manyBitmap), ("20건", tooManyBitmap)] {
        #expect(gpYellowPixels(bitmap) == 0, "\(name) 에 노란 상자가 있다")
    }
    #expect(gpMaxChannelDifference(quietBitmap, busyBitmap, rect: gpLobbySideColumn) > 60,
            "'지금 대결 중' 카드가 안 그려졌다")
    // 상대 목록은 오른쪽 열이 차도 그대로다(두 열이 서로의 자리를 침범하지 않는다).
    #expect(gpMaxChannelDifference(quietBitmap, busyBitmap, rect: gpLobbyListColumn) <= 2,
            "대결 중 목록이 상대 목록을 흔들었다")

    // --- 자르지 않는다: **보이는 카드를 직접 센다** ---
    // 여백 띠 단언만으로는 아무것도 증명되지 않는다(옛 시험의 교훈: `prefix(maxCards)` 를 지워도 초록이었다).
    let three = gpBoxTops(busyBitmap, rect: gpLobbySideColumn, height: gpLiveCardHeight)
    let twelve = gpBoxTops(manyBitmap, rect: gpLobbySideColumn, height: gpLiveCardHeight)
    let twenty = gpBoxTops(tooManyBitmap, rect: gpLobbySideColumn, height: gpLiveCardHeight)
    #expect(three.count == 3, "3건인데 카드가 \(three.count)장이다(윗변 \(three))")
    #expect(twelve.count > 3,
            "12건인데 카드가 \(twelve.count)장뿐이다 — 칸이 남는데 옛 상한이 아직 자른다(윗변 \(twelve))")
    #expect(twelve == twenty,
            "20건과 12건이 다르게 보인다 — 칸 안에서 잘리는 것이 아니라 건수를 세어 접고 있다 \(twelve) vs \(twenty)")

    // 옛 "외 N건" 줄이 사라졌다 — 마지막 카드 **아래**가 12건과 20건에서 한 픽셀도 다르지 않다.
    let lastBottom = try #require(twelve.last) + gpLiveCardHeight
    let moreLine = CGRect(x: gpLobbySideColumn.minX, y: CGFloat(lastBottom) + 2,
                          width: gpLobbySideColumn.width, height: 20)
    #expect(gpMaxChannelDifference(manyBitmap, tooManyBitmap, rect: moreLine) <= 2,
            "마지막 카드 아래에서 12건과 20건이 다르다 — '외 N건' 같은 글자가 아직 남아 있다")

    // 창 아래 여백 띠는 몇 건이든 한 픽셀도 달라지지 않는다(칸 밖으로 안 자란다).
    let size = GomokuWindowLayout.contentSize
    let band = CGRect(x: 0, y: size.height - GomokuWindowLayout.contentPadding + 2,
                      width: size.width, height: GomokuWindowLayout.contentPadding - 4)
    for (name, bitmap) in [("9건", crowdedBitmap), ("12건", manyBitmap), ("20건", tooManyBitmap)] {
        #expect(gpMaxChannelDifference(busyBitmap, bitmap, rect: band) <= 2,
                "\(name)에서 '지금 대결 중'이 창 아래 여백까지 자란다 — 창 밖으로 잘린다")
    }

    // 소스 계약 — 상한·접기가 정말 없어졌고, 스크롤 두 갈래가 서 있다.
    let panel = gpStripped(try gpSource("GomokuPanel.swift"))
    let column = try #require(gpRegion(panel, from: "private struct GomokuLiveMatchColumn: View {",
                                       to: "private struct GomokuLiveMatchCard: View {"))
    #expect(!column.contains("maxCards"), "'지금 대결 중'이 아직 상한으로 자른다")
    #expect(!column.contains("GomokuText.more("), "'지금 대결 중'이 아직 '외 N건'으로 접는다")
    #expect(column.contains("ScrollView"), "앱 갈래에 스크롤이 없다 — 넘치는 대결을 볼 길이 아예 없다")
    #expect(column.contains("clipsOverflowInsteadOfScroll"),
            "스냅샷 갈래가 없다 — ImageRenderer 는 ScrollView 안을 못 그려 이 칸에서 눈이 먼다")
    #expect(column.contains("minHeight: 0"), "minHeight 0 이 없다 — 카드가 608pt 본문을 뚫는다")
}

/// 로비가 **두 열**이다(v0.3.29): 상대 목록 780 · 오른쪽 400, 가운데 판돈 카드는 없다.
///
/// 두 가지를 픽셀로 잰다. ① 상대 행의 [도전] 버튼이 780pt 목록의 오른쪽 끝(실측 771.5pt)까지 간다 —
/// 옛 540pt 열이었다면 x 530 언저리에서 멈춘다. ② 오른쪽 열 **맨 위**가 "지금 대결 중"이다 —
/// 대결 건수를 바꾸면 그 자리 픽셀이 바뀐다(옛 화면에서 그 자리는 판돈 카드라 꿈쩍도 안 했다).
@MainActor
@Test
func lobbyIsTwoColumnsAndTheStakeCardIsGone() throws {
    let store = gpLobbyStore(outgoing: false)
    store.liveMatches = gpLiveMatches(3)
    let bitmap = try gpBitmap(gpPanel(store))
    gpSave(bitmap, name: "lobby-two-columns")
    #expect(gpYellowPixels(bitmap) == 0, "두 열 로비에 노란 상자가 있다")

    // ① [도전] 버튼(채운 accent)이 목록 오른쪽 끝까지 간다.
    let challenge = gpAccentBounds(bitmap, rect: gpLobbyListColumn)
    #expect(challenge.count > 1000, "상대 목록에 [도전] 버튼이 안 보인다")
    #expect(challenge.box.maxX > 700,
            "[도전] 버튼이 x \(challenge.box.maxX)pt 에서 끝난다 — 상대 목록이 아직 540pt 열이다")
    #expect(challenge.box.maxX < gpLobbyListColumn.maxX, "[도전] 버튼이 목록 열 밖으로 넘친다")

    // ② 오른쪽 열 맨 위가 '지금 대결 중'이다(그 자리가 대결 건수에 반응한다).
    let noneBitmap = try gpBitmap(gpPanel(gpLobbyStore(outgoing: false)))
    let topBand = CGRect(x: gpLobbySideColumn.minX, y: gpLobbySideColumn.minY + 28,
                         width: gpLobbySideColumn.width, height: 60)
    #expect(gpMaxChannelDifference(noneBitmap, bitmap, rect: topBand) > 60,
            "오른쪽 열 맨 위가 대결 건수에 반응하지 않는다 — 그 자리가 아직 판돈 카드다")

    // 소스 계약 — 판돈 버튼은 로비 열에서 사라지고 **판돈 창에만** 있다.
    let panel = gpStripped(try gpSource("GomokuPanel.swift"))
    let side = try #require(gpRegion(panel, from: "private struct GomokuLobbySide: View {",
                                     to: "private struct GomokuOutgoingLine: View {"))
    #expect(!side.contains("GomokuStakeButton("), "로비 오른쪽 열에 아직 판돈 카드가 있다")
    let prompt = try #require(gpRegion(panel, from: "private struct GomokuStakePrompt: View {",
                                       to: "struct GomokuInviteBanner: View {"))
    #expect(prompt.contains("GomokuStakeButton("), "판돈 창에 판돈 버튼이 없다")
    // 로비는 두 열이라 세 번째 열(채팅 폭)을 그리지 않는다.
    let lobby = try #require(gpRegion(panel, from: "private var lobby: some View {", to: "private func playing("))
    #expect(!lobby.contains("chatWidth"), "로비가 아직 세 번째 열(chatWidth)을 그린다")
}

/// 판돈 창: [도전]을 누르면 화면 **가운데**에 뜨고, 뒤가 어두워지고, 판돈 버튼 **셋**이 각자 자리에 선다.
///
/// 버튼 셋을 세는 법: 고른 판돈만 accent 로 꽉 차고 나머지는 테두리뿐이다. 그래서 버튼 줄을 셋으로 쪼개면
/// **고른 칸에만** 잉크가 있다 — 3·5·10 을 차례로 골라 잉크가 왼쪽→가운데→오른쪽으로 옮겨 가면 세 자리가
/// 모두 실재한다는 뜻이다(버튼 하나를 지우면 나머지가 넓어져 칸이 어긋난다).
///
/// v0.3.30: 창은 **아무것도 안 골라진 채** 열리고(지난번 판돈 `store.selectedStake` 로 강조하지 않는다),
/// 맨 아래 버튼이 미선택이면 [취소](테두리), 고르면 같은 자리에서 [N 걸고 도전하기](채운 accent)로 바뀐다.
@MainActor
@Test
func stakePromptDimsTheLobbyAndDrawsThreeStakeButtons() throws {
    let card = CGRect(x: (GomokuWindowLayout.contentSize.width - GomokuWindowLayout.stakePromptWidth) / 2, y: 0,
                      width: GomokuWindowLayout.stakePromptWidth, height: GomokuWindowLayout.contentSize.height)
    func lobbyStore(balance: Int?) -> GomokuStore {
        let store = gpLobbyStore(outgoing: false)
        store.liveMatches = gpLiveMatches(3)
        // 지난번에 10 을 걸었다 — 새 창이 이 값을 강조하면 v0.3.29 의 "열자마자 골라져 있음"이 되살아난 것이다.
        store.selectedStake = .ten
        store.rubyBalance = balance
        return store
    }
    func promptBitmap(selection: GomokuStake?, balance: Int?) throws -> NSBitmapImageRep {
        try gpBitmap(GomokuPanel(store: lobbyStore(balance: balance), me: { gpMe },
                                 clipsOverflowInsteadOfScroll: true, previewStakeTarget: gpMinsu,
                                 previewStakeSelection: selection))
    }
    /// 판돈 버튼 줄(창 위 y 319~363 에 선다 — 2026-09-16 실측)을 셋으로 쪼갠 각 칸의 accent 잉크.
    func thirds(_ bitmap: NSBitmapImageRep) -> [Int] {
        let row = CGRect(x: card.minX + 20, y: 340, width: card.width - 40, height: 8)
        let third = row.width / 3
        return (0..<3).map { index in
            gpAccentBounds(bitmap, rect: CGRect(x: row.minX + third * CGFloat(index), y: row.minY,
                                                width: third, height: row.height)).count
        }
    }
    /// 맨 아래 버튼 띠(판돈 줄 아래 · 카드 안). 채운 [도전하기]는 이 띠를 accent 로 거의 다 칠하고,
    /// 테두리뿐인 [취소]는 획과 글자만 칠한다(실측: 미선택 수천 px · 선택 수만 px).
    let bottomBand = CGRect(x: card.minX + 20, y: 395, width: card.width - 40, height: 60)

    let closed = try gpBitmap(gpPanel(lobbyStore(balance: 42)))
    let open = try promptBitmap(selection: nil, balance: 42)
    gpSave(open, name: "lobby-stake-prompt")
    #expect(gpYellowPixels(open) == 0, "판돈 창에 노란 상자가 있다 — Menu/Picker 가 섞였다")

    // ① 뒤가 어두워진다 — 창에서 먼 상대 목록 구석까지 덮개가 깔린다(실측 (50,52,66) → (19,20,25)).
    let corner = gpPixel(closed, x: 40, y: 600), dimmed = gpPixel(open, x: 40, y: 600)
    #expect(dimmed.0 < corner.0 - 15 && dimmed.1 < corner.1 - 15 && dimmed.2 < corner.2 - 15,
            "판돈 창을 열었는데 뒤가 안 어두워졌다 \(corner) → \(dimmed)")
    #expect(gpMaxChannelDifference(closed, open, rect: gpLobbyListColumn) > 60, "덮개가 상대 목록을 안 덮는다")

    // ② 처음 열면 **아무것도 안 골라져 있다** — 지난번 판돈(10)이 가게에 남아 있어도 세 칸 모두 비었다.
    #expect(thirds(open) == [0, 0, 0], "판돈 창이 이미 골라진 채 열렸다 \(thirds(open))")

    // ③ 판돈 버튼 셋이 각자 자리에 있다.
    var chosen: [NSBitmapImageRep] = []
    for (index, stake) in [GomokuStake.three, .five, .ten].enumerated() {
        let bitmap = try promptBitmap(selection: stake, balance: 42)
        chosen.append(bitmap)
        let counts = thirds(bitmap)
        #expect(counts[index] > 1500, "판돈 \(stake.rawValue)을 골랐는데 \(index + 1)번째 칸이 안 찼다 \(counts)")
        for other in 0..<3 where other != index {
            #expect(counts[other] == 0, "판돈 \(stake.rawValue)을 골랐는데 \(other + 1)번째 칸도 찼다 \(counts)")
        }
    }
    gpSave(chosen[1], name: "lobby-stake-prompt-chosen")
    #expect(gpYellowPixels(chosen[1]) == 0, "판돈을 고른 창에 노란 상자가 있다")

    // ④ 맨 아래 버튼이 [취소] → [도전하기]로 바뀐다(같은 자리에서 테두리 → 채운 accent).
    let cancelInk = gpAccentInk(open, rect: bottomBand)
    let challengeInk = gpAccentInk(chosen[1], rect: bottomBand)
    #expect(cancelInk < 8_000, "고르기 전인데 맨 아래가 채운 버튼이다(accent \(cancelInk)px) — [취소]가 아니다")
    #expect(challengeInk > 20_000, "판돈을 골랐는데 맨 아래가 [도전하기](채운 accent)로 안 바뀌었다(\(challengeInk)px)")
    // 캡션도 고른 판돈을 말한다("판돈을 고르세요" → "판돈 5 · 이기면 +5").
    let caption = CGRect(x: card.minX + 20, y: 280, width: card.width - 40, height: 24)
    #expect(gpMaxChannelDifference(open, chosen[1], rect: caption) > 60, "판돈을 골랐는데 캡션이 그대로다")

    // ⑤ 루비가 모자란 판돈은 비활성 — **골라 둔 값이어도** 안 찬다(+ 이유 한 줄이 뜬다) · [도전하기]도 흐리다.
    let rich = try promptBitmap(selection: .ten, balance: 42)
    let poor = try promptBitmap(selection: .ten, balance: 4)
    gpSave(poor, name: "lobby-stake-prompt-short")
    #expect(gpYellowPixels(poor) == 0, "모자람 안내가 뜬 판돈 창에 노란 상자가 있다")
    #expect(thirds(rich)[2] > 1500, "루비가 넉넉한데 판돈 10이 안 골라졌다 \(thirds(rich))")
    #expect(thirds(poor)[2] == 0, "루비 4개로 판돈 10을 고를 수 있게 그려졌다 \(thirds(poor))")
    #expect(gpMaxChannelDifference(rich, poor, rect: card) > 60, "모자란 이유 한 줄이 안 뜬다")
    // 모자람 줄이 한 줄 끼어 버튼 띠가 아래로 밀린다 — 띠를 넉넉히 잡아 흐린 [도전하기]를 잰다.
    let poorBand = CGRect(x: bottomBand.minX, y: bottomBand.minY, width: bottomBand.width, height: bottomBand.height + 30)
    #expect(gpAccentInk(poor, rect: poorBand) < 8_000,
            "루비가 모자란데 [도전하기]가 또렷하다(\(gpAccentInk(poor, rect: poorBand))px) — 누를 수 있어 보인다")
    // 같은 사실은 앱 어디서나 같은 말로 — 상점·신청 거절과 한 출처를 쓴다.
    #expect(GomokuText.stakeShortfall == WorkTimerStore.shortfallNotice(need: nil, have: nil),
            "판돈 창의 모자람 문구가 앱의 다른 화면과 다른 말을 한다")

    // 소스 계약 — 판돈 버튼은 **고르기만** 하고, 신청은 [도전하기] 한 곳에서만 나간다. Esc 는 언제나 닫는다.
    let panel = gpStripped(try gpSource("GomokuPanel.swift"))
    let prompt = try #require(gpRegion(panel, from: "private struct GomokuStakePrompt: View {",
                                       to: "struct GomokuInviteBanner: View {"))
    #expect(prompt.components(separatedBy: "store.challenge(").count - 1 == 1, "신청이 나가는 자리가 하나가 아니다")
    let stakeButtons = try #require(gpRegion(prompt, from: "GomokuStakeButton(", to: "if GomokuStake.allCases.contains"))
    #expect(!stakeButtons.contains("store.challenge("), "판돈 버튼이 아직 누르자마자 신청한다")
    #expect(stakeButtons.contains("GomokuStakeSelection.toggled("), "판돈 버튼이 고르기 규칙(한 번 더 누르면 해제)을 안 지난다")
    #expect(!prompt.contains("isSelected: store.selectedStake"), "판돈 창이 지난번 판돈으로 강조된 채 열린다")
    #expect(prompt.contains(".keyboardShortcut(.cancelAction)"), "Esc 로 판돈 창이 안 닫힌다")
    #expect(prompt.contains(".keyboardShortcut(.defaultAction)"), "판돈을 고른 뒤 ↩ 로 신청할 수 없다")
}

/// 받은 신청이 늘수록 오른쪽 열 **아래 칸**이 자라고 **위 칸**이 그만큼 줄어든다 — 그리고 둘은 언제나
/// 열을 정확히 채운다(`위 + 12 + 아래 = 608`). 받은 신청이 없으면 아래 칸은 한 줄로 접힌다.
///
/// 잰 값(2026-09-16, 안내 줄 없는 가게): 0건 → 537+12+59 · 2건 → 350+12+246 · 5건 → 329+12+267 ·
/// 5건+보낸 신청 → 286+12+310. 아래 칸이 가장 두꺼운 경우(310)도 예산(320) 안이고, 위 칸은 언제나
/// 최소 높이(220) 위다 — 이 둘이 깨지면 [취소]가 잘려 보낸 신청을 거둘 길이 사라진다.
@MainActor
@Test
func lobbyInvitesBoxCollapsesAndTheLiveBoxTakesTheRest() throws {
    func store(incoming: Int, outgoing: Bool) -> GomokuStore {
        let store = gpLobbyStore(outgoing: false)
        store.notice = nil                    // 안내 줄은 이 시험이 재는 두 칸 밖의 세 번째 칸이다
        store.liveMatches = gpLiveMatches(3)
        let frozen = Date(timeIntervalSince1970: 2_000_000_000)
        store.incoming = (0..<incoming).map {
            GomokuInvite(id: "in-\($0)", peer: gpUser("신청자\($0)", 70 + $0), stake: 5, expiresAt: frozen)
        }
        store.outgoing = outgoing ? GomokuInvite(id: "out-1", peer: gpJunho, stake: 10, expiresAt: frozen) : nil
        return store
    }
    /// 두 칸의 경계를 그림에서 찾는다: 넓은 획 둘이 **정확히 칸 간격(12pt)** 만큼 떨어진 마지막 짝이
    /// 위 칸의 아랫변과 아래 칸의 윗변이다(카드 사이 간격은 8pt 라 섞이지 않는다).
    func split(_ bitmap: NSBitmapImageRep) -> (live: Int, invites: Int)? {
        let spacing = Int(GomokuWindowLayout.lobbySideSpacing)
        let rows = gpWideRows(bitmap, rect: gpLobbySideColumn, minimum: 600)
        guard let boundary = rows.last(where: { rows.contains($0 + spacing) }) else { return nil }
        return (live: boundary - Int(gpLobbySideColumn.minY),
                invites: Int(gpLobbySideColumn.maxY) - (boundary + spacing))
    }

    var lives: [Int] = [], invites: [Int] = []
    for (name, incoming, outgoing) in [("0건", 0, false), ("2건", 2, false), ("5건", 5, false),
                                       ("5건+보낸신청", 5, true)] {
        let bitmap = try gpBitmap(gpPanel(store(incoming: incoming, outgoing: outgoing)))
        gpSave(bitmap, name: "lobby-invites-\(incoming)\(outgoing ? "-out" : "")")
        #expect(gpYellowPixels(bitmap) == 0, "\(name) 에 노란 상자가 있다")
        let measured = try #require(split(bitmap), "\(name): 오른쪽 열에서 두 칸의 경계를 못 찾았다")
        lives.append(measured.live)
        invites.append(measured.invites)
        #expect(measured.live + Int(GomokuWindowLayout.lobbySideSpacing) + measured.invites
                == Int(GomokuWindowLayout.bodyHeight),
                "\(name): 위 \(measured.live) + 12 + 아래 \(measured.invites) 가 608 이 아니다 — 열이 뜨거나 넘친다")
        #expect(CGFloat(measured.invites) <= GomokuWindowLayout.lobbyInvitesMaxHeight,
                "\(name): 아래 칸이 \(measured.invites)pt 로 예산 \(Int(GomokuWindowLayout.lobbyInvitesMaxHeight))pt 를 넘는다")
        #expect(CGFloat(measured.live) >= GomokuWindowLayout.lobbyLiveMinHeight,
                "\(name): 위 칸이 \(measured.live)pt 로 최소 \(Int(GomokuWindowLayout.lobbyLiveMinHeight))pt 보다 얇다")
    }
    #expect(invites == invites.sorted(), "받은 신청이 늘어도 아래 칸이 안 자란다 \(invites)")
    #expect(invites[0] < 100, "받은 신청이 없는데 아래 칸이 \(invites[0])pt 다 — 한 줄로 안 접혔다")
    #expect(lives[0] > lives[1] && lives[1] > lives[2] && lives[2] > lives[3],
            "받은 신청이 늘었는데 위 칸이 그만큼 안 줄었다 \(lives)")
    #expect(invites[3] > invites[2], "보낸 신청 한 줄이 아래 칸에 안 붙었다 \(invites)")
}

// MARK: - 소속 센터 배지 (v0.3.29)

/// "지금 대결 중" 카드 한 장의 높이(pt). **두 시험이 같은 값을 읽는다** — 갈리면 한쪽이 카드를
/// 못 세거나 엉뚱한 띠를 잰다.
///
/// 0.3.29 에서 48 → 53 으로 커졌다: 이름 줄에 18pt 얼굴(센터 배지가 설 자리)이 들어와 그 줄이
/// 글자 높이(13pt)가 아니라 얼굴 높이로 선다. 실측(ImageRenderer scale 2, 세 건):
/// 넓은 획 행 [72, 106, 159, 167, 220, 228, 281] — 카드 윗변 106·167·228, 아랫변이 각각 +53,
/// 카드 사이 간격은 8pt(159 → 167). 72 는 열을 감싼 카드의 윗변이다.
private let gpLiveCardHeight = 53

/// 로비 왼쪽(상대 목록) 열.
@MainActor
private var gpLobbyListColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding, y: gpBoardOrigin.y,
           width: GomokuWindowLayout.lobbyListWidth, height: GomokuWindowLayout.bodyHeight)
}

/// 로비 **오른쪽** 열(v0.3.29 — 위 칸 지금 대결 중 · 아래 칸 받은/보낸 신청). 두 열이라 이 열이 끝이다.
@MainActor
private var gpLobbySideColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding + GomokuWindowLayout.lobbyListWidth + GomokuWindowLayout.columnSpacing,
           y: gpBoardOrigin.y, width: GomokuWindowLayout.lobbySideWidth, height: GomokuWindowLayout.bodyHeight)
}

/// 센터를 아는 나(대국 화면 내 카드 — 앱은 `WorkTimerStore.myCenter` 에서 읽어 넘긴다).
private let gpMeCentered = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba", center: "서울")

/// 센터 배지(서울·부산)가 오목 **다섯 자리 모두**에서 실제 픽셀을 만든다.
///
/// ★ 자리마다 **따로** 잰다. 한 장에서 한 번만 재면 다섯 중 하나만 배선돼도 초록이다 —
///   그러면 `center:` 를 넘기는 걸 잊어도 통과하는, 이 변경이 답하려는 질문을 못 답하는 시험이 된다.
/// ★ 시각이 흐르는 글자(신청 카운트다운 · 대결 경과 m:ss · 차례 시계)는 재는 자리에서 **뺀다.**
///   두 렌더 사이에 초가 바뀌기만 해도 픽셀이 달라져서, 배선이 끊겨도 초록을 만든다.
/// ★ 두 그림의 입력은 **센터 말고 전부 같다**(만료·시작 시각까지 bare 에서 그대로 가져온다) —
///   기준선이 다르면 그 시험은 배지가 아니라 다른 것을 잰다.
@MainActor
@Test
func centerBadgesDrawPixelsOnEveryGomokuFace() throws {
    // ── 로비: 상대 행 · 받은 신청 카드 · 지금 대결 중 카드 ──────────────────────────────
    let live = gpLiveMatches(3)
    let bare = gpLobbyStore(outgoing: false)
    bare.liveMatches = live
    let badged = gpLobbyStore(outgoing: false)
    badged.users = bare.users.enumerated().map { gpWithCenter($1, $0.isMultiple(of: 2) ? "서울" : "부산") }
    badged.incoming = bare.incoming.map {
        GomokuInvite(id: $0.id, peer: gpWithCenter($0.peer, "부산"), stake: $0.stake, expiresAt: $0.expiresAt)
    }
    badged.liveMatches = live.map {
        GomokuLiveMatch(id: $0.id, a: gpWithCenter($0.a, "서울"), b: gpWithCenter($0.b, "부산"),
                        stake: $0.stake, startedAt: $0.startedAt)
    }
    let bareLobby = try gpBitmap(gpPanel(bare))
    let badgedLobby = try gpBitmap(gpPanel(badged))
    gpSave(badgedLobby, name: "lobby-center-badges")
    #expect(gpYellowPixels(badgedLobby) == 0, "배지를 단 로비에 노란 상자가 있다")
    #expect(gpMaxChannelDifference(bareLobby, badgedLobby, rect: gpLobbyListColumn) > 60,
            "상대 목록 행의 아바타에 센터 배지가 없다")
    // 신청 카드는 **왼쪽 90pt** 만 잰다 — 카드 오른쪽 끝의 '남은 초'는 두 렌더 사이에 달라진다.
    // v0.3.29 부터 받은 신청은 오른쪽 열 **아래 칸**이다. 열 전체를 재면 위 칸(대결 카드)의 얼굴에만
    // 배지가 달려도 이 단언이 초록이 되므로 **아래 칸만** 잘라 잰다.
    // 실측(이 가게): 위 칸 72..377 · 아래 칸 389..635 · 안내 줄 647..680.
    let inviteFaces = CGRect(x: gpLobbySideColumn.minX, y: 389, width: 90, height: 635 - 389)
    #expect(gpMaxChannelDifference(bareLobby, badgedLobby, rect: inviteFaces) > 60,
            "받은 신청 카드의 아바타에 센터 배지가 없다")
    // 대결 카드는 **윗줄(두 사람 줄)만** 잰다 — 아랫줄의 경과 m:ss 는 초가 바뀐다.
    let cardTops = gpBoxTops(bareLobby, rect: gpLobbySideColumn, height: gpLiveCardHeight)
    // 실패하면 **잰 값**을 함께 보여 준다 — 카드 높이가 바뀌었을 때 다음 사람이 숫자를 찾아 헤매지 않게.
    #expect(cardTops.count == live.count,
            """
            지금 대결 중 카드가 \(cardTops.count)장 보인다(기대 \(live.count)장) — 카드 높이 상수 \
            \(gpLiveCardHeight)pt 가 틀렸다. 이 그림의 넓은 획 행: \
            \(gpWideRows(bareLobby, rect: gpLobbySideColumn, minimum: 300))
            """)
    // 띠는 카드 안쪽 여백 8 + 얼굴 18 + 배지가 아래로 넘치는 2pt 까지 덮고, 아랫줄(판돈·경과)이 시작하는
    // top+32 앞에서 끝난다 — 그래야 배지를 놓치지도, 매초 바뀌는 경과 글자를 집지도 않는다.
    for top in cardTops {
        let nameRow = CGRect(x: gpLobbySideColumn.minX, y: CGFloat(top) + 2,
                             width: gpLobbySideColumn.width, height: 28)
        #expect(gpMaxChannelDifference(bareLobby, badgedLobby, rect: nameRow) > 60,
                "지금 대결 중 카드(윗변 \(top))의 두 사람에 센터 배지가 없다")
    }

    // ── 대국: 상대 카드 · 내 카드 ───────────────────────────────────────────────────────
    let barePlaying = gpPlayingStore(turn: .black)
    let badgedPlaying = gpPlayingStore(turn: .black)
    badgedPlaying.match?.opponent = gpWithCenter(gpMinsu, "부산")
    let barePlayingBitmap = try gpBitmap(gpPanel(barePlaying))
    let badgedPlayingBitmap = try gpBitmap(gpPanel(badgedPlaying, me: gpMeCentered))
    gpSave(badgedPlayingBitmap, name: "playing-center-badges")
    #expect(gpYellowPixels(badgedPlayingBitmap) == 0, "배지를 단 대국 화면에 노란 상자가 있다")
    // 두 카드의 얼굴(캐릭터 초상)은 오른쪽 열 **왼쪽 90pt** 에 선다(오른쪽 끝의 차례 시계는 매초 바뀐다).
    // v0.3.30: 카드 한 장 = 고정 높이 84pt(초상 60 + 안쪽 여백 4×2 + 카드 위아래 여백 8×2), 두 장 사이 간격 10pt.
    let card = GomokuWindowLayout.playerCardHeight, gap = GomokuWindowLayout.matchSideSpacing
    let opponentFace = CGRect(x: gpMatchSideColumn.minX, y: gpMatchSideColumn.minY, width: 90, height: card)
    let myFace = CGRect(x: gpMatchSideColumn.minX, y: gpMatchSideColumn.minY + card + gap, width: 90, height: card)
    #expect(gpMaxChannelDifference(barePlayingBitmap, badgedPlayingBitmap, rect: opponentFace) > 60,
            "대국 화면 상대 카드에 센터 배지가 없다")
    #expect(gpMaxChannelDifference(barePlayingBitmap, badgedPlayingBitmap, rect: myFace) > 60,
            "대국 화면 내 카드에 센터 배지가 없다 — 내 센터는 앱이 아는 값(myCenter)에서 온다")

    // ── 결과 카드 ──────────────────────────────────────────────────────────────────────
    let bareResult = gpResultStore(outcome: .won, reason: .five)
    let badgedResult = gpResultStore(outcome: .won, reason: .five)
    badgedResult.match?.opponent = gpWithCenter(gpMinsu, "부산")
    let bareResultBitmap = try gpBitmap(gpPanel(bareResult))
    let badgedResultBitmap = try gpBitmap(gpPanel(badgedResult))
    gpSave(badgedResultBitmap, name: "result-center-badge")
    #expect(gpYellowPixels(badgedResultBitmap) == 0, "배지를 단 결과 화면에 노란 상자가 있다")
    #expect(gpMaxChannelDifference(bareResultBitmap, badgedResultBitmap, rect: gpMatchSideColumn) > 60,
            "결과 카드의 상대 아바타에 센터 배지가 없다")
}

/// 서버 어휘('seoul'/'busan') → 화면 글자("서울"/"부산") 변환은 **스토어 경계 한 번**이다(CenterLabel 규약).
/// 여기서 지키는 것 셋: ① 두 값이 옳게 바뀐다 ② 키가 없는 **옛 서버**에서도 디코드가 통째로 실패하지 않는다
/// ③ 서버가 셋째 센터를 여는 날 옛 앱이 그 사람을 조용히 '서울'로 **단정하지 않는다**(모르면 배지 없음).
@Test
func gomokuRowsTranslateCenterThroughCenterLabel() throws {
    func center(_ json: String) throws -> String?? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let row = try decoder.decode(GomokuUserRow.self, from: Data(json.utf8))
        return GomokuStore.user(from: row)?.center
    }
    #expect(try center(#"{"user_id":"U","display_name":"민수","center":"busan"}"#) == "부산")
    #expect(try center(#"{"user_id":"U","display_name":"민수","center":"seoul"}"#) == "서울")
    #expect(try center(#"{"user_id":"U","display_name":"민수","center":null}"#) == .some(nil))
    #expect(try center(#"{"user_id":"U","display_name":"민수"}"#) == .some(nil),
            "center 를 안 싣는 옛 서버의 응답이 통째로 버려졌다")
    #expect(try center(#"{"user_id":"U","display_name":"민수","center":"daejeon"}"#) == .some(nil),
            "모르는 센터를 접어서 그리고 있다 — 모르면 배지가 없어야 한다")
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
    gpAccentBounds(bitmap, rect: rect).count
}

/// 같은 accent 잉크를 **어디에** 칠했는지까지 — 픽셀 수와 그 잉크를 감싸는 상자(pt).
/// 잉크가 없으면 `.null` 상자를 돌려준다. 나란히 선 버튼 중 **어느 것이 골라졌는지**를 자리로 재는 자다.
private func gpAccentBounds(_ bitmap: NSBitmapImageRep, rect: CGRect) -> (count: Int, box: CGRect) {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return (0, .null) }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return (0, .null) }
    var count = 0
    var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
            if b > 140 && b > r + 60 && b > g + 30 {
                count += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard count > 0 else { return (0, .null) }
    return (count, CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2,
                          width: CGFloat(maxX - minX) / 2, height: CGFloat(maxY - minY) / 2))
}

// MARK: - v0.3.30: 빈 대결 칸 폭 · 카드 말풍선 · 오른쪽 열 세로 예산 · 기권 방어

/// 로비 "지금 대결 중" 칸은 **대결이 하나도 없어도** 오른쪽 열 폭(400pt)을 다 채운다.
///
/// 2026-09-17 사용자 스크린샷: 빈 목록일 때 카드가 글자 폭(약 140pt)만 감싸 400pt 열 가운데에 세로 막대로 섰다.
/// 목록이 있으면 ScrollView 가 폭을 펴서 옛 시험(전부 3건 이상)이 한 번도 못 봤다. 여기서는 **빈 목록**으로 잰다:
/// 카드 윗변·아랫변 획이 열 폭 거의 전부(둥근 모서리 두 개를 뺀 368pt = 736px 이상)에 깔려야 한다.
@MainActor
@Test
func lobbyLiveMatchesCardFillsTheColumnWhenEmpty() throws {
    let store = gpLobbyStore(outgoing: false)
    store.incoming = []
    store.notice = nil
    store.liveMatches = []
    let bitmap = try gpBitmap(gpPanel(store))
    gpSave(bitmap, name: "lobby-live-empty")
    #expect(gpYellowPixels(bitmap) == 0)
    let wide = gpWideRows(bitmap, rect: gpLobbySideColumn, minimum: 700)
    let top = Int(gpLobbySideColumn.minY)
    #expect(wide.contains(top),
            "빈 '지금 대결 중' 카드의 윗변이 열 폭을 못 채운다 — 가운데 좁은 막대로 섰다(넓은 획 행 \(wide))")
    // 아랫변도 같다(윗변만 넓고 아래가 좁은 '종이 접힘'이 아니다). 받은 신청 칸 윗변과 12pt 떨어진 짝으로 찾는다.
    let spacing = Int(GomokuWindowLayout.lobbySideSpacing)
    #expect(wide.contains { $0 > top && wide.contains($0 + spacing) },
            "빈 '지금 대결 중' 카드의 아랫변이 열 폭을 못 채운다(넓은 획 행 \(wide))")
}

/// 카드 말풍선 판정 시각. 말은 T0(상대)·T0+2(나)에 왔다.
private let gpBubbleT0 = Date(timeIntervalSince1970: 1_790_000_000)

@MainActor
private func gpBubbleStore(muted: Bool = false, withChat: Bool = true) -> GomokuStore {
    let store = gpPlayingStore(turn: .black)
    store.isMuted = muted
    if withChat {
        store.chat = [
            GomokuChatMessage(seq: 1, isMine: false, sentAt: gpBubbleT0, quick: nil, body: "잘 부탁해요! 살살 둬 주세요"),
            GomokuChatMessage(seq: 2, isMine: true, sentAt: gpBubbleT0.addingTimeInterval(2),
                              quick: .think, body: GomokuQuickPhrase.think.text)
        ]
        store.chatSeq = 2
    }
    return store
}

@MainActor
private func gpBubblePanel(_ store: GomokuStore, now: Date?) -> some View {
    GomokuPanel(store: store, me: { gpMe }, clipsOverflowInsteadOfScroll: true, previewBubbleNow: now)
}

/// 카드 한 장의 **말풍선 자리**(pt). 초상·이름 칸 오른쪽부터, 차례 링 자리 왼쪽까지 — 링(초 단위로 바뀐다)은 뺀다.
private func gpBubbleSlot(card index: Int) -> CGRect {
    let x = gpMatchSideColumn.minX + 12 + 68 + 12 + 132 + 12
    let right = gpMatchSideColumn.maxX - 12 - 54 - 12
    let y = gpMatchSideColumn.minY + CGFloat(index) * (GomokuWindowLayout.playerCardHeight + GomokuWindowLayout.matchSideSpacing)
    return CGRect(x: x, y: y + 4, width: right - x, height: GomokuWindowLayout.playerCardHeight - 8)
}

/// 채팅을 보내면 **그 사람 카드 옆 말풍선**으로도 5초 뜬다(v0.3.30 사용자 요구).
///
/// 재는 것: ① 보낸 직후 두 카드 모두 말풍선 자리에 픽셀이 선다(내 것은 accent) ② 5초가 지난 말은 사라진다(각자 시각대로)
/// ③ 내가 채팅을 껐으면 상대 말풍선은 안 뜨고 내 것은 뜬다 ④ 말풍선이 떠도 **열의 나머지는 한 픽셀도 안 움직인다**
/// (카드 높이 고정 — 같은 대화에서 시각만 다른 두 장을 비교한다).
@MainActor
@Test
func playerCardsShowTheLatestLineAsASpeechBubble() throws {
    let noChat = try gpBitmap(gpBubblePanel(gpBubbleStore(withChat: false), now: gpBubbleT0.addingTimeInterval(3)))
    let both = try gpBitmap(gpBubblePanel(gpBubbleStore(), now: gpBubbleT0.addingTimeInterval(3)))
    let mineOnly = try gpBitmap(gpBubblePanel(gpBubbleStore(), now: gpBubbleT0.addingTimeInterval(6)))
    let none = try gpBitmap(gpBubblePanel(gpBubbleStore(), now: gpBubbleT0.addingTimeInterval(8)))
    let muted = try gpBitmap(gpBubblePanel(gpBubbleStore(muted: true), now: gpBubbleT0.addingTimeInterval(3)))
    gpSave(both, name: "playing-speech-bubbles")
    gpSave(muted, name: "playing-speech-bubbles-muted")
    for (name, bitmap) in [("both", both), ("mineOnly", mineOnly), ("none", none), ("muted", muted)] {
        #expect(gpYellowPixels(bitmap) == 0, "\(name) 에 노란 상자가 있다")
    }
    let opponentSlot = gpBubbleSlot(card: 0), mySlot = gpBubbleSlot(card: 1)

    // ① 보낸 직후: 두 카드 모두 말풍선 — 내 것은 accent 배경.
    #expect(gpMaxChannelDifference(noChat, both, rect: opponentSlot) > 60, "상대가 보낸 말이 상대 카드 옆에 안 뜬다")
    #expect(gpMaxChannelDifference(noChat, both, rect: mySlot) > 60, "내가 보낸 말이 내 카드 옆에 안 뜬다")
    #expect(gpAccentInk(both, rect: mySlot) > gpAccentInk(noChat, rect: mySlot) + 1_000,
            "내 말풍선이 내 말 색(accent)이 아니다")
    #expect(gpAccentInk(both, rect: opponentSlot) <= gpAccentInk(noChat, rect: opponentSlot) + 50,
            "상대 말풍선이 내 말 색(accent)으로 칠해졌다")

    // ② 5초: 상대 말(T0)은 T0+6 에 사라지고 내 말(T0+2)은 남는다 · T0+8 에는 둘 다 없다.
    #expect(gpMaxChannelDifference(noChat, mineOnly, rect: opponentSlot) <= 2, "5초가 지난 상대 말풍선이 남아 있다")
    #expect(gpMaxChannelDifference(noChat, mineOnly, rect: mySlot) > 60, "아직 5초가 안 된 내 말풍선이 사라졌다")
    #expect(gpMaxChannelDifference(noChat, none, rect: opponentSlot) <= 2, "옛 말이 상대 카드에 남아 있다")
    #expect(gpMaxChannelDifference(noChat, none, rect: mySlot) <= 2, "옛 말이 내 카드에 남아 있다")

    // ③ 내가 채팅을 껐다: 상대 말풍선 없음, 내 말풍선 있음.
    #expect(gpMaxChannelDifference(noChat, muted, rect: opponentSlot) <= 2, "채팅을 껐는데 상대 말이 카드로 샌다")
    #expect(gpMaxChannelDifference(noChat, muted, rect: mySlot) > 60, "채팅을 껐다고 내 말풍선까지 사라졌다")

    // ④ 카드 높이 고정 — 같은 대화에서 말풍선만 켜고 끈 두 장은 두 카드 **아래** 전부가 같다.
    let below = CGRect(x: gpMatchSideColumn.minX,
                       y: gpMatchSideColumn.minY + GomokuWindowLayout.playerCardHeight * 2 + GomokuWindowLayout.matchSideSpacing * 2,
                       width: gpMatchSideColumn.width, height: gpMatchSideColumn.height - GomokuWindowLayout.playerCardHeight * 2 - 20)
    #expect(gpMaxChannelDifference(both, none, rect: below) <= 2, "말풍선이 뜨자 판돈 줄·채팅·기권이 밀렸다")
    // 판도 그대로다.
    let board = CGRect(x: gpBoardOrigin.x, y: gpBoardOrigin.y, width: GomokuWindowLayout.boardSide, height: GomokuWindowLayout.boardSide)
    #expect(gpMaxChannelDifference(both, none, rect: board) <= 2, "말풍선이 판 그림을 흔들었다")
}

/// 오른쪽 열 **가장 꽉 찬 경우**에도 채팅 로그가 두 줄 이상 보이고, [기권] 확인이 잘리지 않는다.
///
/// 가장 꽉 찬 경우 = 상태 상자 네 줄(내 차례 · 흑 패스 · 자동 착수 개수 · 연속 경고) + 상대가 채팅을 껐다는 줄 +
/// 글자 수(상한 근처) + [기권] 확인 상태(문구 + 두 버튼). 로그 높이는 **대화가 가득한 장과 빈 장의 차이가 서는
/// 세로 범위**로 잰다 — 말풍선은 로그 틀에 잘려 위아래를 꽉 채우고, 머리글·격자·입력 줄은 두 장이 같다.
@MainActor
@Test
func fullestMatchColumnKeepsTheChatLogReadable() throws {
    func fullest(messages: Bool) throws -> GomokuStore {
        let store = gpPlayingStore(turn: .black)
        var match = try #require(store.match)
        match.blackPassed = true
        match.autoPoints = [try #require(GomokuPoint(notation: "L4"))]
        store.match = match
        store.myAutoStreak = GomokuStore.autoPlaceLossStreak - 1
        store.isOpponentMuted = true
        store.chatDraft = String(repeating: "가", count: 90)
        if messages {
            let t0 = Date(timeIntervalSince1970: 1_784_000_000)
            store.chat = (1...14).map {
                GomokuChatMessage(seq: $0, isMine: $0.isMultiple(of: 2), sentAt: t0.addingTimeInterval(Double($0)),
                                  quick: nil, body: "\($0)번째 말이에요")
            }
            store.chatSeq = 14
        }
        return store
    }
    func render(_ store: GomokuStore) throws -> NSBitmapImageRep {
        try gpBitmap(GomokuPanel(store: store, me: { gpMe }, clipsOverflowInsteadOfScroll: true, previewConfirmResign: true))
    }
    let full = try render(try fullest(messages: true))
    let empty = try render(try fullest(messages: false))
    gpSave(full, name: "playing-fullest-confirm")
    #expect(gpYellowPixels(full) == 0)

    let extent = try #require(gpDiffRowExtent(full, empty, rect: gpMatchSideColumn),
                              "대화가 가득한 장과 빈 장이 오른쪽 열에서 같다 — 로그가 한 줄도 안 보인다")
    let logHeight = extent.maxY - extent.minY
    #expect(logHeight >= GomokuWindowLayout.chatLogMinHeight,
            "가장 꽉 찬 경우 채팅 로그가 \(logHeight)pt 로 최소 \(Int(GomokuWindowLayout.chatLogMinHeight))pt 보다 얇다")

    // [기권] 확인(채운 빨강 [기권하기])이 열 **안**에 온전히 선다 — 열 아래 40pt 에 빨강 면이 있다.
    let bottom = CGRect(x: gpMatchSideColumn.minX, y: gpMatchSideColumn.maxY - 40, width: gpMatchSideColumn.width, height: 40)
    #expect(gpRedFill(full, rect: bottom) > 10_000, "가장 꽉 찬 경우 [기권하기]가 열 아래로 잘렸다(\(gpRedFill(full, rect: bottom))px)")
    // 창 아래 여백 띠는 평범한 대국 화면과 한 픽셀도 다르지 않다(열이 창 밖으로 안 자란다).
    let plain = try gpBitmap(gpPanel(gpPlayingStore(turn: .black)))
    let size = GomokuWindowLayout.contentSize
    let band = CGRect(x: 0, y: size.height - GomokuWindowLayout.contentPadding + 2,
                      width: size.width, height: GomokuWindowLayout.contentPadding - 4)
    #expect(gpMaxChannelDifference(plain, full, rect: band) <= 2, "가장 꽉 찬 오른쪽 열이 창 아래 여백까지 자란다")
}

/// 두 장이 채널 차 30 을 넘게 다른 행들의 세로 범위(pt). 다른 행이 없으면 nil.
private func gpDiffRowExtent(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> (minY: CGFloat, maxY: CGFloat)? {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return nil }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(lhs.pixelsHigh - 1, Int(rect.maxY * 2))
    var first: Int?, last: Int?
    for y in y0...y1 {
        var differs = false
        for x in x0...x1 where !differs {
            let o = y * bpr + x * spp
            for c in 0..<min(3, spp) where abs(Int(a[o + c]) - Int(b[o + c])) > 30 { differs = true; break }
        }
        if differs {
            if first == nil { first = y }
            last = y
        }
    }
    guard let first, let last else { return nil }
    return (CGFloat(first) / 2, CGFloat(last) / 2)
}

/// 채운 빨강(CheckTheme.danger 면) 픽셀 수.
private func gpRedFill(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
            if r > 170 && r > g + 60 && r > b + 60 { count += 1 }
        }
    }
    return count
}

/// 기권 방어의 소스 계약(v0.3.30). 누름 판정·키보드 차단·확인 접기·화면 전환 리셋이 **제자리에** 서 있는가.
/// 행동 자체는 실제 창 하네스(`V0330GomokuMatchLayoutTests` — 수락 자리 두 번 누름 재현)가 잰다.
@Test
func resignButtonIsGuardedAgainstStrayTapsAndKeys() throws {
    let panel = gpStripped(try gpSource("GomokuPanel.swift"))
    let side = try #require(gpRegion(panel, from: "private struct GomokuMatchSide: View {", to: "private struct GomokuPlayerCard: View {"))
    #expect(side.contains("guard GomokuResignGuard.acceptsTap(shownAt: shownAt, now: GomokuResignGuard.clock()) else { return }"),
            "[기권]이 화면이 막 나타난 직후의 누름을 거르지 않는다 — 로비 [수락] 더블클릭이 기권 확인을 연다")
    #expect(side.components(separatedBy: ".focusable(false)").count - 1 >= 2,
            "[기권]·[기권하기]가 키보드(스페이스·↩)로 눌린다")
    #expect(side.contains(".task(id: confirmResign)"), "기권 확인이 스스로 접히지 않는다")
    #expect(side.contains(".onChange(of: match.id)"), "판이 바뀌어도 누름 기준 시각을 새로 안 적는다")
    let root = try #require(gpRegion(panel, from: "struct GomokuPanel: View {", to: "private struct GomokuHeader: View {"))
    #expect(root.contains(".onChange(of: store.phase)"), "화면이 바뀌어도 기권 확인이 남는다")
    #expect(root.contains(".onChange(of: store.isWindowVisible)"), "창이 다시 떠도 기권 확인이 남는다")
    // 대국·결과는 두 열이다 — 세 번째 채팅 열이 없다.
    #expect(!root.contains("chatWidth"), "대국·결과 화면이 아직 세 번째 채팅 열을 그린다")
    #expect(root.components(separatedBy: "GomokuChatCard(").count - 1 == 1, "결과 화면에 채팅 카드가 없다")
    #expect(side.contains("GomokuChatCard("), "대국 오른쪽 열 안에 채팅 카드가 없다")
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
        // v0.3.29 판돈 창 · [도전] 툴팁 · 보낸 신청 한 줄.
        GomokuText.stakePromptTitle(name: "민수"), GomokuText.stakePromptCaption, GomokuText.stakeShortfall,
        GomokuText.challengeHelp, GomokuText.outgoingTitle(name: "준호"), GomokuText.outgoingTitle,
        // v0.3.30 판돈 창 고른 뒤 캡션 · [도전하기].
        GomokuText.stakePromptChosen(5), GomokuText.challengeWithStake(5), GomokuText.challengeNowHelp,
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
    return try String(contentsOf: directory.appendingCheckSourcePath(name), encoding: .utf8)
}

/// `from` 부터 그 뒤 첫 `to` 직전까지(없으면 nil).
private func gpRegion(_ source: String, from start: String, to end: String) -> String? {
    guard let head = source.range(of: start) else { return nil }
    let tail = source.range(of: end, range: head.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
    return String(source[head.upperBound..<tail])
}

/// 사각형 안에서 **중성(흰 계열) 테두리 획이 가로로 넓게 깔린** pt 행 목록 — 상자를 **세는** 자다.
///
/// 칩·카드의 위아래 획은 열 폭을 거의 채우므로(측정: 337~390px) `minimum` 을 넘고, 말풍선·글자는
/// 좁거나(≤ 222px) 파랗다(accent 는 R−B 가 170 이라 중성 조건에서 걸린다). 그래서 "높이 h 인 상자 n 개"를
/// `행 y 와 y+h 가 둘 다 넓다` 는 짝으로 셀 수 있다 — **상자를 지우면 짝이 사라져 수가 어긋난다**.
private func gpWideRows(_ bitmap: NSBitmapImageRep, rect: CGRect, minimum: Int) -> [Int] {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return [] }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let ax0 = max(0, Int(rect.minX * 2)), ax1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    var rows: [Int] = []
    for y in Int(rect.minY)...Int(rect.maxY) {
        let py = min(max(y * 2, 0), bitmap.pixelsHigh - 1)
        var hits = 0
        for x in ax0...ax1 {
            let o = py * bpr + x * spp
            let r = Int(data[o]), b = Int(data[o + 2])
            if r >= 62 && r <= 120 && abs(r - b) <= 40 { hits += 1 }
        }
        if hits >= minimum { rows.append(y) }
    }
    return rows
}

/// 높이 `height` pt 인 상자가 몇 개 서 있는가 — 위 획과 아래 획이 짝지어진 행들의 목록(각 상자의 윗변 y).
private func gpBoxTops(_ bitmap: NSBitmapImageRep, rect: CGRect, height: Int, minimum: Int = 300) -> [Int] {
    let wide = gpWideRows(bitmap, rect: rect, minimum: minimum)
    return wide.filter { wide.contains($0 + height) }
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
