import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.41 — 1:1 오목 **순위 열 · 관전 화면** 렌더(W4). 하네스는 V0327GomokuPanelRenderTests 그대로다(ImageRenderer scale 2 ·
// 노란 상자 0 · CHECK_SNAPSHOT_DIR/gomoku 저장 · 스냅샷은 클립 갈래 · 좌표는 레이아웃 상수에서만). 그 파일의 헬퍼는 private 이라
// 여기 한 벌 더 있다(V0330 과 같은 관례).
//
// 감지기를 옛 사각형 위에 세우지 않는다(C23): 상대 열 · 순위 열 · 관전 상태 상자 사각형을 **따로** 만들고, 내 행 강조는
// '나 포함 vs 나 제외' 두 장의 채널 차로 잰다 — accent 0.18 채움은 푸른 픽셀 감지기에 안 잡혀서, 그 감지기로 재면 채움을 진하게
// 올려 통과시키는 유혹이 생긴다.
//
// 각 시험의 첫 줄은 "없으면 어떤 결함이 초록으로 통과하는가"다.

// MARK: - 픽스처

private func rwUser(_ name: String, _ suffix: Int, working: Bool = true, capable: Bool = true,
                    inMatch: Bool = false, character: String? = "shiba", center: String? = nil) -> GomokuUser {
    GomokuUser(
        id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))",
        displayName: name, avatarURL: nil, characterID: character,
        isWorking: working, isCapable: capable, inMatch: inMatch, center: center
    )
}

/// 순위 행 한 줄. **user 는 스토어 경계(`user(from:)`)가 만드는 모양 그대로** — 근무·가능·대국 중이 전부 false 다.
/// 화면이 이 값으로 아바타를 흐리게 하면 전원이 흐려진다(그래서 픽스처도 그 모양이다).
private func rwEntry(_ rank: Int, _ name: String, _ suffix: Int, wins: Int, losses: Int, draws: Int) -> GomokuRankEntry {
    let characters = ["fox", "shiba", "squirrel", "ghost"]
    let user = GomokuUser(
        id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))",
        displayName: name, avatarURL: nil, characterID: characters[suffix % characters.count],
        isWorking: false, isCapable: false, inMatch: false, center: suffix.isMultiple(of: 2) ? "서울" : "부산"
    )
    return GomokuRankEntry(id: user.id, rank: rank, user: user, wins: wins, losses: losses, draws: draws, points: wins - losses)
}

/// N 명짜리 순위표(서버 순서 흉내 — 승점 내림차순, 동률은 같은 순위). 정렬 자체는 스토어 몫이 아니라 여기서는 모양만 만든다.
private func rwBoard(_ count: Int, since: Date? = nil) -> GomokuRankingBoard {
    let entries = (0..<count).map { index in
        rwEntry(index + 1, "순위\(index + 1)", 100 + index, wins: max(0, 12 - index), losses: index / 2, draws: index % 3)
    }
    return GomokuRankingBoard(entries: entries, me: nil, recordSince: since)
}

/// 2026-10-06 12:00 KST(= 03:00 UTC) — 어느 시간대에서 돌려도 10월 6일.
private let rwSinceDate = Date(timeIntervalSince1970: 1_791_255_600)

@MainActor
private func rwLobbyStore() -> GomokuStore {
    let store = GomokuStore()
    store.users = [
        rwUser("지영", 13, working: false), rwUser("민수", 11, character: "fox"), rwUser("태화", 14, inMatch: true),
        rwUser("준호", 12, character: "squirrel"), rwUser("가장긴별명열두글자입니다", 19)
    ]
    store.record = GomokuRecord(wins: 7, losses: 3, draws: 1)
    store.rubyBalance = 42
    store.hasLoadedLobby = true
    return store
}

@MainActor
private func rwLiveMatches(_ count: Int) -> [GomokuLiveMatch] {
    // 시작 시각은 얼린다 — 경과 m:ss 가 두 렌더 사이에 달라지면 카드 아랫줄이 흔들려 다른 것을 재게 된다.
    let frozen = Date(timeIntervalSince1970: 2_000_000_000)
    return (0..<count).map { index in
        GomokuLiveMatch(
            id: "live-\(index)",
            a: rwUser("대결자\(index)", 30 + index, inMatch: true, character: "fox"),
            b: rwUser("상대\(index)", 60 + index, inMatch: true, character: "ghost"),
            stake: [GomokuStake.three, .five, .ten][index % 3],
            startedAt: frozen
        )
    }
}

private let rwWatchA = rwUser("대결자", 30, inMatch: true, character: "fox", center: "서울")
private let rwWatchB = rwUser("상대", 60, inMatch: true, character: "ghost", center: "부산")

/// 관전 상태 하나. `server: false` 는 첫 응답 전(두 얼굴만, 색 없음 — C15), true 는 서버가 흑·백을 말한 뒤.
@MainActor
private func rwWatch(server: Bool, turn: GomokuColor? = .black, deadline: Date? = Date().addingTimeInterval(18),
                     finished: Bool = false, winner: GomokuColor? = nil, reason: GomokuEndReason? = nil,
                     stones: Bool = true, faces: Int = 2, blackStreak: Int = 0) -> GomokuSpectateState {
    var watch = GomokuSpectateState(id: "watch-1", faces: Array([rwWatchA, rwWatchB].prefix(faces)), stake: 5)
    if stones {
        var board = GomokuBoard()
        for notation in ["H8", "I9", "G7", "J10", "F6"] { if let p = GomokuPoint(notation: notation) { board[p] = .black } }
        for notation in ["H9", "H10", "I8", "G8"] { if let p = GomokuPoint(notation: notation) { board[p] = .white } }
        watch.board = board
        watch.lastMove = GomokuPoint(notation: "F6")
        watch.moveCount = 9
        watch.appliedSeq = 9
    }
    if server {
        watch.black = rwWatchA
        watch.white = rwWatchB
        watch.turn = finished ? nil : turn
        watch.deadline = finished ? nil : deadline
        watch.startedAt = Date(timeIntervalSince1970: 2_000_000_000)
        watch.isFinished = finished
        watch.winner = winner
        watch.endReason = reason
        watch.blackAutoStreak = blackStreak
    }
    return watch
}

private let rwMe = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

@MainActor
private func rwPanel(_ store: GomokuStore) -> some View {
    GomokuPanel(store: store, me: { rwMe }, clipsOverflowInsteadOfScroll: true)
}

/// 관전 화면 한 장. 받은·보낸 신청과 안내는 관전 중에도 살아 있어야 한다(C12) — 그 자리를 채우는 문이 여기다.
@MainActor
private func rwSpectateBitmap(_ watch: GomokuSpectateState, incoming: [GomokuInvite] = [], outgoing: GomokuInvite? = nil,
                              notice: String? = nil, busy: Bool = false) throws -> NSBitmapImageRep {
    let store = rwLobbyStore()
    store.spectating = watch
    store.incoming = incoming
    store.outgoing = outgoing
    store.notice = notice
    store.isBusy = busy
    return try rwBitmap(rwPanel(store))
}

/// 대국 화면(채팅 카드·[기권] 이 있는 기준선).
@MainActor
private func rwPlayingBitmap() throws -> NSBitmapImageRep {
    let store = GomokuStore()
    store.phase = .playing
    store.rubyBalance = 32
    store.record = GomokuRecord(wins: 7, losses: 3, draws: 1)
    store.match = GomokuMatchState(
        id: "match-1", stake: 10, myColor: .black, opponent: rwWatchA, board: rwWatch(server: true).board,
        lastMove: GomokuPoint(notation: "F6"), moveCount: 9, turn: .black,
        deadline: Date().addingTimeInterval(18), isFinished: false, outcome: nil, endReason: nil,
        rubyDelta: nil, blackPassed: false
    )
    return try rwBitmap(rwPanel(store))
}

private let rwFrozenExpiry = Date(timeIntervalSince1970: 2_000_000_000)

private func rwInvite(_ id: String, _ name: String, _ suffix: Int, stake: Int = 5) -> GomokuInvite {
    GomokuInvite(id: id, peer: rwUser(name, suffix, character: "fox"), stake: stake, expiresAt: rwFrozenExpiry)
}

// MARK: - 사각형(레이아웃 상수에서만)

private var rwBodyTop: CGFloat {
    GomokuWindowLayout.contentPadding + GomokuWindowLayout.headerHeight + GomokuWindowLayout.headerSpacing
}

/// 로비 상대 목록 열(420).
private var rwUsersColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding, y: rwBodyTop,
           width: GomokuWindowLayout.lobbyUsersWidth, height: GomokuWindowLayout.bodyHeight)
}

/// 로비 순위 열(340).
private var rwRankColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding + GomokuWindowLayout.lobbyUsersWidth + GomokuWindowLayout.columnSpacing,
           y: rwBodyTop, width: GomokuWindowLayout.lobbyRankWidth, height: GomokuWindowLayout.bodyHeight)
}

/// 로비 오른쪽 열(400) — 순위 열이 생겨도 한 픽셀도 안 움직여야 한다.
private var rwLobbySideColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding + GomokuWindowLayout.lobbyListWidth + GomokuWindowLayout.columnSpacing,
           y: rwBodyTop, width: GomokuWindowLayout.lobbySideWidth, height: GomokuWindowLayout.bodyHeight)
}

/// 머리글 오른쪽 절반(전적 캡슐 · 루비 · 버튼들).
private var rwHeaderRight: CGRect {
    CGRect(x: GomokuWindowLayout.contentSize.width / 2, y: GomokuWindowLayout.contentPadding,
           width: GomokuWindowLayout.contentSize.width / 2 - GomokuWindowLayout.contentPadding,
           height: GomokuWindowLayout.headerHeight)
}

/// 창 아래 여백 띠(마지막 20pt 중 안쪽 16pt) — 어느 칸도 여기까지 자라면 안 된다.
private var rwBottomBand: CGRect {
    let size = GomokuWindowLayout.contentSize
    return CGRect(x: 0, y: size.height - GomokuWindowLayout.contentPadding + 2,
                  width: size.width, height: GomokuWindowLayout.contentPadding - 4)
}

/// 판(관전·대국 같은 자리).
private var rwBoardRect: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding, y: rwBodyTop,
           width: GomokuWindowLayout.boardSide, height: GomokuWindowLayout.boardSide)
}

/// 관전·대국 오른쪽 열(572).
private var rwSideColumn: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding + GomokuWindowLayout.boardSide + GomokuWindowLayout.columnSpacing,
           y: rwBodyTop, width: GomokuWindowLayout.sideColumnWidth, height: GomokuWindowLayout.bodyHeight)
}

/// 두 사람 카드(84 + 10 + 84).
private var rwCardsRect: CGRect {
    CGRect(x: rwSideColumn.minX, y: rwSideColumn.minY, width: rwSideColumn.width,
           height: GomokuWindowLayout.playerCardHeight * 2 + GomokuWindowLayout.matchSideSpacing)
}

/// 두 사람 카드에서 차례 링 자리(오른쪽 12 + 54 + 12)를 뺀 부분 — 초가 흐르는 글자가 없어 두 렌더를 픽셀로 비교할 수 있다.
private var rwCardsFacesRect: CGRect {
    CGRect(x: rwCardsRect.minX, y: rwCardsRect.minY, width: rwCardsRect.width - 78, height: rwCardsRect.height)
}

/// 카드 index 의 차례 링 자리(카드 오른쪽 끝 54pt — 초 단위로 바뀌는 글자가 있는 유일한 자리).
private func rwClockSlot(card index: Int) -> CGRect {
    let y = rwSideColumn.minY + CGFloat(index) * (GomokuWindowLayout.playerCardHeight + GomokuWindowLayout.matchSideSpacing)
    return CGRect(x: rwSideColumn.maxX - 12 - 54, y: y + 8, width: 54, height: GomokuWindowLayout.playerCardHeight - 16)
}

/// 관전 상태 상자(판돈 칩 오른쪽 · 두 카드 아래 · 높이 44).
private var rwWatchStatusBox: CGRect {
    CGRect(x: rwSideColumn.minX + GomokuWindowLayout.stakeChipWidth + GomokuWindowLayout.matchSideSpacing,
           y: rwCardsRect.maxY + GomokuWindowLayout.matchSideSpacing,
           width: GomokuWindowLayout.sideColumnWidth - GomokuWindowLayout.stakeChipWidth - GomokuWindowLayout.matchSideSpacing,
           height: GomokuWindowLayout.spectateStatusMinHeight)
}

/// 관전 남는 자리(322 — 받은 신청 · 보낸 신청 · 안내줄 · 관전 안내 카드).
private var rwWatchInfoArea: CGRect {
    CGRect(x: rwSideColumn.minX, y: rwWatchStatusBox.maxY + GomokuWindowLayout.matchSideSpacing,
           width: GomokuWindowLayout.sideColumnWidth, height: GomokuWindowLayout.spectateInfoHeight)
}

/// [나가기] 띠(열 맨 아래 34).
private var rwLeaveBand: CGRect {
    CGRect(x: rwSideColumn.minX, y: rwSideColumn.maxY - GomokuWindowLayout.spectateLeaveHeight,
           width: GomokuWindowLayout.sideColumnWidth, height: GomokuWindowLayout.spectateLeaveHeight)
}

/// 대국 화면의 채팅 카드 자리(V0327 의 gpChatCard 와 같은 산식) — 관전에는 이 자리에 채팅이 없어야 한다.
private var rwChatCardRect: CGRect {
    let top = rwSideColumn.minY + GomokuWindowLayout.playerCardHeight * 2 + GomokuWindowLayout.matchSideSpacing * 3 + 44
    let bottom = rwSideColumn.maxY - 34 - GomokuWindowLayout.matchSideSpacing
    return CGRect(x: rwSideColumn.minX, y: top, width: rwSideColumn.width, height: bottom - top)
}

// MARK: - 로비: 순위 열

/// 없으면: 순위 열이 카드 크롬만 그리고 행이 안 보여도, 14행이 아니라 3행만 서도, 열이 오른쪽 400 열을 밀어내도, 21행이 창 아래로
/// 뚫고 나가도 컴파일과 스토어 테스트는 초록이다.
@MainActor
@Test
func rankColumnDrawsItsStatesAndFourteenRowsWithoutMovingTheOtherColumns() throws {
    let loading = rwLobbyStore()                                        // ranking nil · 아직 못 받음
    let unavailable = rwLobbyStore()
    unavailable.rankingUnavailable = true
    unavailable.hasLoadedRanking = true
    let failed = rwLobbyStore()
    failed.rankingLoadFailed = true
    let empty = rwLobbyStore()
    empty.ranking = rwBoard(0)
    empty.hasLoadedRanking = true
    let full = rwLobbyStore()
    full.ranking = rwBoard(21, since: rwSinceDate)                      // 14행 예산을 넘긴다(클립 갈래)
    full.hasLoadedRanking = true
    let noSince = rwLobbyStore()
    noSince.ranking = rwBoard(21)
    noSince.hasLoadedRanking = true
    let few = rwLobbyStore()
    few.ranking = rwBoard(5)
    few.hasLoadedRanking = true

    let loadingBitmap = try rwBitmap(rwPanel(loading))
    let unavailableBitmap = try rwBitmap(rwPanel(unavailable))
    let failedBitmap = try rwBitmap(rwPanel(failed))
    let emptyBitmap = try rwBitmap(rwPanel(empty))
    let fullBitmap = try rwBitmap(rwPanel(full))
    let noSinceBitmap = try rwBitmap(rwPanel(noSince))
    let fewBitmap = try rwBitmap(rwPanel(few))
    rwSave(fullBitmap, name: "lobby-rank-full")
    rwSave(fewBitmap, name: "lobby-rank-few")
    rwSave(emptyBitmap, name: "lobby-rank-empty")
    rwSave(failedBitmap, name: "lobby-rank-failed")
    rwSave(unavailableBitmap, name: "lobby-rank-unavailable")
    rwSave(loadingBitmap, name: "lobby-rank-loading")
    let states: [(String, NSBitmapImageRep)] = [
        ("loading", loadingBitmap), ("unavailable", unavailableBitmap), ("failed", failedBitmap),
        ("empty", emptyBitmap), ("full", fullBitmap), ("few", fewBitmap)
    ]
    for (name, bitmap) in states {
        #expect(bitmap.pixelsWide == Int(GomokuWindowLayout.contentSize.width) * 2
                && bitmap.pixelsHigh == Int(GomokuWindowLayout.contentSize.height) * 2, "\(name) 이 고정 창 크기가 아니다")
        #expect(rwYellowPixels(bitmap) == 0, "\(name) 에 노란 상자가 있다 — Picker/Menu/TextField 가 섞였다")
    }

    // ① 네 상태 + 목록이 순위 열 안에서 **서로** 다르게 그려진다(둘이 같으면 한 상태가 다른 상태로 위장한다).
    let distinct: [(String, NSBitmapImageRep)] = [
        ("loading", loadingBitmap), ("unavailable", unavailableBitmap), ("failed", failedBitmap), ("empty", emptyBitmap), ("full", fullBitmap)
    ]
    for i in distinct.indices {
        for j in distinct.indices where j > i {
            #expect(rwMaxChannelDifference(distinct[i].1, distinct[j].1, rect: rwRankColumn) > 60,
                    "순위 열에서 \(distinct[i].0) 과 \(distinct[j].0) 이 똑같이 보인다")
        }
    }

    // ② 행을 **직접 센다** — 21행이면 예산(14)만큼 보이고, 5행이면 5행이다(넓은 중성 획 짝 = 행 상자).
    let fullRows = rwBoxTops(fullBitmap, rect: rwRankColumn, height: Int(GomokuWindowLayout.rankRowHeight), minimum: 500)
    let fewRows = rwBoxTops(fewBitmap, rect: rwRankColumn, height: Int(GomokuWindowLayout.rankRowHeight), minimum: 500)
    #expect(fullRows.count == GomokuWindowLayout.rankVisibleRows,
            "21행에서 보이는 행이 \(fullRows.count)장이다(예산 \(GomokuWindowLayout.rankVisibleRows)) — 윗변 \(fullRows) · 넓은 획 행 \(rwWideRows(fullBitmap, rect: rwRankColumn, minimum: 500))")
    #expect(fewRows.count == 5, "5행인데 \(fewRows.count)장이 보인다(윗변 \(fewRows))")
    // 행 간격이 상수 그대로다(34 + 5).
    if fullRows.count >= 2 {
        #expect(fullRows[1] - fullRows[0] == Int(GomokuWindowLayout.rankRowHeight + GomokuWindowLayout.rankRowSpacing),
                "행 간격이 \(fullRows[1] - fullRows[0])pt 다")
    }

    // ③ 컷 캡션("10월 6일부터")이 제목 줄에 글자로 선다 — 툴팁에만 두지 않는다.
    let header = CGRect(x: rwRankColumn.minX, y: rwRankColumn.minY,
                        width: rwRankColumn.width, height: GomokuWindowLayout.cardPadding + GomokuWindowLayout.rankHeaderHeight + 4)
    #expect(rwMaxChannelDifference(fullBitmap, noSinceBitmap, rect: header) > 60, "컷이 있는데 순위 제목 줄 캡션이 그대로다")
    // 캡션 말고는 두 장이 같다(캡션이 행을 밀지 않는다).
    let below = CGRect(x: rwRankColumn.minX, y: header.maxY, width: rwRankColumn.width, height: rwRankColumn.maxY - header.maxY)
    #expect(rwMaxChannelDifference(fullBitmap, noSinceBitmap, rect: below) <= 2, "컷 캡션이 순위 행을 밀었다")

    // ④ 순위 열은 제 자리 밖을 침범하지 않는다 — 상대 열 · 오른쪽 열 · 창 아래 띠가 순위 유무와 무관하게 같다.
    for (name, bitmap) in states where name != "loading" {
        #expect(rwMaxChannelDifference(loadingBitmap, bitmap, rect: rwUsersColumn) <= 2, "\(name): 순위 열이 상대 목록을 흔들었다")
        #expect(rwMaxChannelDifference(loadingBitmap, bitmap, rect: rwLobbySideColumn) <= 2, "\(name): 순위 열이 오른쪽 열을 흔들었다")
        #expect(rwMaxChannelDifference(loadingBitmap, bitmap, rect: rwBottomBand) <= 2, "\(name): 순위 열이 창 아래 여백까지 자란다")
    }

    // ⑤ [도전] 은 상대 열(420) 오른쪽 끝에서 끝난다 — 780 을 그대로 쓰면 771 언저리다.
    let challenge = rwAccentBounds(fullBitmap, rect: rwUsersColumn)
    #expect(challenge.count > 1000, "상대 목록에 [도전] 이 안 보인다")
    #expect(challenge.box.maxX > GomokuWindowLayout.lobbyUsersWidth - 60 && challenge.box.maxX < rwUsersColumn.maxX,
            "[도전] 이 x \(challenge.box.maxX)pt 에서 끝난다 — 상대 열이 420 이 아니다")
}

/// 없으면: 내 행이 남의 행과 똑같이 그려져도, 머리글 캡슐이 순위 응답이 로비 전적과 어긋나는데도 순위를 붙여 "8승 3패 · 승점 +4" 를
/// 만들어도(C16), 내 판 카드에 [관전] 칩이 서서 내 판을 관전하려 들어도 초록이다. 세션이 있어야 '나' 를 알아서 WorkTimerStore 를 세운다.
@MainActor
@Test(.gomokuDefaultsCleanup)
func myRankRowAndHeaderCapsuleFollowTheSessionUserAndOneSource() throws {
    let (store, _) = makeMessageReadStore("v0341-rank-me")
    let gomoku = store.gomoku
    gomoku.users = rwLobbyStore().users
    gomoku.hasLoadedLobby = true
    gomoku.rubyBalance = 42
    gomoku.record = GomokuRecord(wins: 3, losses: 1, draws: 2)
    let mine = MessageReadFixture.me
    var entries = rwBoard(5).entries
    let other = entries[1]
    let meEntry = GomokuRankEntry(id: mine, rank: other.rank, user: GomokuUser(
        id: mine, displayName: "나", avatarURL: nil, characterID: "shiba", isWorking: false, isCapable: false, inMatch: false, center: "서울"
    ), wins: 3, losses: 1, draws: 2, points: 2)
    entries[1] = meEntry
    let meRank = GomokuMyRank(rank: 2, wins: 3, losses: 1, draws: 2, points: 2)
    func render(_ board: GomokuRankingBoard?) throws -> NSBitmapImageRep {
        gomoku.ranking = board
        gomoku.hasLoadedRanking = board != nil
        return try rwBitmap(rwPanel(gomoku))
    }
    let withMe = try render(GomokuRankingBoard(entries: entries, me: meRank, recordSince: nil))
    let withoutMe = try render(GomokuRankingBoard(entries: rwBoard(5).entries, me: meRank, recordSince: nil))
    rwSave(withMe, name: "lobby-rank-me")
    #expect(rwYellowPixels(withMe) == 0)

    // ① 내 행(둘째 줄)만 다르다 — 첫째 줄은 같다.
    let rowTops = rwBoxTops(withMe, rect: rwRankColumn, height: Int(GomokuWindowLayout.rankRowHeight), minimum: 500)
    #expect(rowTops.count == 5, "내 행이 있는 순위표의 행이 \(rowTops.count)장이다(윗변 \(rowTops)) — 내 행 테두리가 중성이 아니어서 안 세어진다")
    let first = CGRect(x: rwRankColumn.minX, y: CGFloat(rowTops[0]) + 1, width: rwRankColumn.width, height: GomokuWindowLayout.rankRowHeight - 2)
    let second = CGRect(x: rwRankColumn.minX, y: CGFloat(rowTops[1]) + 1, width: rwRankColumn.width, height: GomokuWindowLayout.rankRowHeight - 2)
    #expect(rwMaxChannelDifference(withMe, withoutMe, rect: first) <= 2, "남의 행이 나에 따라 바뀌었다")
    #expect(rwMaxChannelDifference(withMe, withoutMe, rect: second) > 20, "내 행이 남의 행과 똑같이 그려진다 — 강조가 없다")

    // ② 머리글 캡슐: 순위 응답의 전적이 로비 전적과 **같을 때만** "2위 · 승점 +2" 가 붙는다(C16 — 한 출처).
    let mismatch = try render(GomokuRankingBoard(entries: entries, me: GomokuMyRank(rank: 2, wins: 4, losses: 1, draws: 2, points: 3), recordSince: nil))
    let noRanking = try render(nil)
    #expect(rwMaxChannelDifference(withMe, noRanking, rect: rwHeaderRight) > 60, "순위를 받았는데 머리글 캡슐에 순위·승점이 안 붙는다")
    #expect(rwMaxChannelDifference(mismatch, noRanking, rect: rwHeaderRight) <= 2,
            "순위 응답의 전적(4승)이 로비 전적(3승)과 다른데 머리글이 순위를 붙였다 — 자기모순 문장이 뜬다")
    // 순위 밖(0판 · rank nil)이면 전적만.
    let outside = try render(GomokuRankingBoard(entries: [], me: GomokuMyRank(rank: nil, wins: 3, losses: 1, draws: 2, points: 2), recordSince: nil))
    #expect(rwMaxChannelDifference(outside, noRanking, rect: rwHeaderRight) <= 2, "순위 밖인데 머리글에 순위가 붙었다")

    // ③ 내 판 카드는 [관전] 칩 대신 "내 판" 캡션이다.
    gomoku.ranking = nil
    gomoku.hasLoadedRanking = false
    let others = rwLiveMatches(2)
    gomoku.liveMatches = others
    let chipped = try rwBitmap(rwPanel(gomoku))
    gomoku.liveMatches = [
        GomokuLiveMatch(id: others[0].id, a: GomokuUser(id: mine, displayName: "나", avatarURL: nil, characterID: "shiba",
                                                       isWorking: true, isCapable: true, inMatch: true),
                        b: others[0].b, stake: others[0].stake, startedAt: others[0].startedAt),
        others[1]
    ]
    let mineCard = try rwBitmap(rwPanel(gomoku))
    rwSave(mineCard, name: "lobby-live-my-match")
    let cardTops = rwBoxTops(chipped, rect: rwLobbySideColumn, height: 53)
    #expect(cardTops.count == 2, "대결 카드가 \(cardTops.count)장이다 — 칩이 카드 높이를 바꿨다")
    if let top = cardTops.first {
        let chipBand = CGRect(x: rwLobbySideColumn.minX + rwLobbySideColumn.width / 2, y: CGFloat(top) + 4,
                              width: rwLobbySideColumn.width / 2, height: 24)
        #expect(rwMaxChannelDifference(chipped, mineCard, rect: chipBand) > 60, "내 판 카드의 첫째 줄이 남의 판 카드와 같다 — '내 판' 캡션이 없다")
        #expect(rwAccentInk(mineCard, rect: chipBand) < rwAccentInk(chipped, rect: chipBand), "내 판 카드에도 [관전] 칩이 선다")
    }
}

// MARK: - 순위 열: 0행 + 조회 실패

/// 없으면: **빈 순위표를 받은 뒤 조회가 실패하면 화면에 실패 띠도 [다시 불러오기]도 없다.** "아직 전적이 없어요"만 남아
/// 사용자는 서버가 멀쩡한 줄 안다(2026-10-01 모바일 세션 제보 — 실패 띠가 "비어 있지 않은" 갈래 안에만 있었다).
/// 전적을 컷으로 초기화한 직후에는 **실제로 0행**이라 가장 닿기 쉬운 자리다.
@MainActor
@Test
func emptyRankingStillShowsTheFailureStripWhenTheReloadFailed() throws {
    let store = rwLobbyStore()
    store.hasLoadedRanking = true
    store.ranking = GomokuRankingBoard(entries: [], me: nil, recordSince: nil)
    let quiet = try rwBitmap(rwPanel(store))
    store.rankingLoadFailed = true
    let failed = try rwBitmap(rwPanel(store))
    rwSave(failed, name: "lobby-rank-empty-failed")
    #expect(rwYellowPixels(failed) == 0)

    // 실패 띠는 pending(주황) 이다 — 빈 순위표의 "아직 전적이 없어요"·깃발 아이콘에는 주황이 없다.
    #expect(rwOrangeInk(quiet, rect: rwRankColumn) == 0, "실패가 아닌데 순위 열에 주황이 있다 — 감지기가 다른 것을 센다")
    #expect(rwOrangeInk(failed, rect: rwRankColumn) > 40,
            "0행 + 조회 실패인데 실패 띠가 없다 — 사용자는 서버가 멀쩡한 줄 안다")
    #expect(rwMaxChannelDifference(quiet, failed, rect: rwRankColumn) > 60, "실패가 순위 열을 한 픽셀도 안 바꿨다")
    // 오른쪽 400 열(상대 목록·받은 신청)은 순위 열의 실패와 무관하다.
    #expect(rwMaxChannelDifference(quiet, failed, rect: rwLobbySideColumn) <= 2, "순위 조회 실패가 오른쪽 열을 바꿨다")
}

// MARK: - 순위 행: 승·패·무 줄

/// 없으면: 행 꼬리에서 **전적 줄(N승 N패 N무)이 통째로 사라져도 초록이다.** 다른 행 단언은 userID·characterHint·금지어와
/// 행 상자 개수·간격만 보고 꼬리(`rankTrailingWidth`)를 겨냥한 사각형이 없었다(2026-10-01 모바일 세션이 뮤테이션으로 제보).
/// 사용자가 "승점으로 나누면서도 몇승 몇패인지 뜨게" 라고 명시한 그 줄이라 감지기가 없으면 요구가 조용히 사라진다.
///
/// 어떻게 잡는가: **승점이 같고 무만 다른** 두 판을 그려 그 행의 꼬리를 맞대어 본다. 승점 줄은 둘이 글자까지 같으므로
/// (둘 다 −1) 꼬리가 같아지는 경우는 전적 줄이 없을 때뿐이다. 기준선과 비교군의 입력이 **다르다** — 같은 입력을 두 번
/// 그리는 비교는 영원히 초록이라 아무것도 증명하지 않는다.
/// (승점 줄 자체는 이 방식으로 따로 못 가른다 — 승점은 승−패라 전적을 안 바꾸고 승점만 바꿀 수 없다. 머리글 캡슐의
///  승점은 `myRankRowAndHeaderCapsuleFollowTheSessionUserAndOneSource` 가 본다.)
@MainActor
@Test
func rankRowShowsWinsLossesDrawsNotJustPoints() throws {
    let store = rwLobbyStore()
    func board(secondRowDraws draws: Int) -> GomokuRankingBoard {
        GomokuRankingBoard(entries: [
            rwEntry(1, "가", 1, wins: 3, losses: 0, draws: 0),
            rwEntry(2, "나", 2, wins: 1, losses: 2, draws: draws),   // 승점 −1 고정 · 무만 바뀐다
        ], me: nil, recordSince: nil)
    }
    func render(_ value: GomokuRankingBoard) throws -> NSBitmapImageRep {
        store.ranking = value
        store.hasLoadedRanking = true
        return try rwBitmap(rwPanel(store))
    }
    let withDraw = try render(board(secondRowDraws: 1))
    let withoutDraw = try render(board(secondRowDraws: 0))
    rwSave(withDraw, name: "lobby-rank-record-line")
    #expect(rwYellowPixels(withDraw) == 0)

    let tops = rwBoxTops(withDraw, rect: rwRankColumn, height: Int(GomokuWindowLayout.rankRowHeight), minimum: 500)
    #expect(tops.count == 2, "두 행이 안 세어진다(윗변 \(tops))")
    guard tops.count == 2 else { return }
    // 꼬리 = 카드 안쪽 오른쪽 끝에서 rankTrailingWidth + 여백. 순위 배지·아바타·이름은 앞쪽이라 안 들어온다.
    func trailing(row index: Int) -> CGRect {
        let width = GomokuWindowLayout.rankTrailingWidth + 12
        return CGRect(x: rwRankColumn.maxX - GomokuWindowLayout.cardPadding - width, y: CGFloat(tops[index]),
                      width: width, height: GomokuWindowLayout.rankRowHeight)
    }
    #expect(rwMaxChannelDifference(withDraw, withoutDraw, rect: trailing(row: 1)) > 20,
            "무가 1 → 0 인데 둘째 행 꼬리가 같다 — 승·패·무 줄이 없다(승점만 그린다)")
    #expect(rwMaxChannelDifference(withDraw, withoutDraw, rect: trailing(row: 0)) <= 2,
            "무를 안 바꾼 첫째 행 꼬리가 달라졌다 — 감지기가 행을 잘못 겨냥했거나 레이아웃이 흔들린다")
}

// MARK: - 로비: 대결 카드의 [관전] 칩

/// 없으면: [관전] 칩이 카드를 55 로 키워 카드를 세는 두 렌더 시험이 0장으로 세어도(C18), 칩이 아예 없어도, 서버에 관전이 없는 창에서
/// 칩이 또렷하게 눌려도 초록이다.
@MainActor
@Test
func liveMatchCardsCarryAWatchChipAndStayFiftyThreeTall() throws {
    let store = rwLobbyStore()
    store.liveMatches = rwLiveMatches(3)
    let bitmap = try rwBitmap(rwPanel(store))
    rwSave(bitmap, name: "lobby-live-watch-chips")
    #expect(rwYellowPixels(bitmap) == 0)
    let cardTops = rwBoxTops(bitmap, rect: rwLobbySideColumn, height: 53)
    #expect(cardTops.count == 3,
            "카드가 \(cardTops.count)장 보인다(기대 3) — [관전] 칩이 카드 높이 53 을 바꿨다. 넓은 획 행: \(rwWideRows(bitmap, rect: rwLobbySideColumn, minimum: 300))")

    // 칩(테두리 accent + 글자 accent)이 각 카드 첫째 줄 오른쪽에 실제 픽셀을 만든다.
    let locked = rwLobbyStore()
    locked.liveMatches = rwLiveMatches(3)
    locked.rankingUnavailable = true
    locked.hasLoadedRanking = true
    let lockedBitmap = try rwBitmap(rwPanel(locked))
    for top in cardTops {
        let chipBand = CGRect(x: rwLobbySideColumn.minX + rwLobbySideColumn.width / 2, y: CGFloat(top) + 4,
                              width: rwLobbySideColumn.width / 2, height: 24)
        let ink = rwAccentInk(bitmap, rect: chipBand)
        #expect(ink > 40, "카드(윗변 \(top)) 첫째 줄 오른쪽에 [관전] 칩이 없다(accent \(ink)px)")
        // 서버에 관전이 아직 없으면(rankingUnavailable) 칩이 흐려진다 — 눌러도 아무 일도 안 생기는 칩을 또렷하게 두지 않는다.
        #expect(rwAccentInk(lockedBitmap, rect: chipBand) < ink, "관전이 닫힌 창인데 [관전] 칩이 또렷하다")
    }
    // 칩이 아랫줄(판돈·경과)을 밀지 않는다 — 칩 유무와 무관하게 카드 아랫줄이 같다(잠긴 칩은 흐려질 뿐 자리가 같다).
    for top in cardTops {
        let bottomRow = CGRect(x: rwLobbySideColumn.minX, y: CGFloat(top) + 32, width: rwLobbySideColumn.width, height: 20)
        #expect(rwMaxChannelDifference(bitmap, lockedBitmap, rect: bottomRow) <= 2, "카드(윗변 \(top)) 아랫줄이 칩 상태에 따라 움직인다")
    }
}

// MARK: - 관전

/// 없으면: 관전 화면에 채팅 입력칸이 서서 관전자가 대국 채팅에 글을 보낼 길이 열려도, [기권] 이 서도, 판이 안 그려져도, 첫 응답 전에
/// 흑·백을 추측해 배지를 그려도(C15), 마감이 지난 상태와 끝난 상태가 진행 중과 똑같이 보여도 컴파일과 스토어 테스트는 초록이다.
@MainActor
@Test
func spectateScreenDrawsTheBoardCardsAndStatusWithoutChatOrResign() throws {
    let live = try rwSpectateBitmap(rwWatch(server: true))
    let loading = try rwSpectateBitmap(rwWatch(server: false))
    let seedless = try rwSpectateBitmap(rwWatch(server: false, faces: 0))
    let emptyBoard = try rwSpectateBitmap(rwWatch(server: true, stones: false))
    let overdue = try rwSpectateBitmap(rwWatch(server: true, deadline: Date().addingTimeInterval(-40)))
    let ended = try rwSpectateBitmap(rwWatch(server: true, finished: true, winner: .black, reason: .five))
    let drawn = try rwSpectateBitmap(rwWatch(server: true, finished: true, winner: nil, reason: .boardFull))
    let warned = try rwSpectateBitmap(rwWatch(server: true, blackStreak: GomokuStore.autoPlaceLossStreak - 1))
    let lobby = try rwBitmap(rwPanel(rwLobbyStore()))
    let playing = try rwPlayingBitmap()
    rwSave(live, name: "spectate")
    rwSave(loading, name: "spectate-loading")
    rwSave(overdue, name: "spectate-overdue")
    rwSave(ended, name: "spectate-ended")
    rwSave(warned, name: "spectate-streak-warning")
    for (name, bitmap) in [("live", live), ("loading", loading), ("seedless", seedless), ("overdue", overdue), ("ended", ended), ("drawn", drawn), ("warned", warned)] {
        #expect(rwYellowPixels(bitmap) == 0, "\(name) 에 노란 상자가 있다 — 관전 화면에 AppKit 입력 위젯이 섰다")
    }

    // ① 로비 자리에 판이 선다 — 돌이 그려진다.
    #expect(rwMaxChannelDifference(live, lobby, rect: rwBoardRect) > 60, "관전인데 왼쪽이 여전히 상대 목록이다")
    #expect(rwMaxChannelDifference(live, emptyBoard, rect: rwBoardRect) > 60, "관전 판에 돌이 안 그려진다")

    // ② 채팅 카드·[기권] 이 없다 — 대국 화면의 채팅 자리와 다르고, 열 아래 40pt 에 빨간 면이 없다.
    #expect(rwMaxChannelDifference(live, playing, rect: rwChatCardRect) > 60, "관전 오른쪽 열이 대국 화면의 채팅 카드 자리와 같다")
    #expect(rwRedFill(live, rect: rwLeaveBand) == 0, "관전 화면 아래에 [기권](빨강)이 있다")
    // [나가기]는 테두리 accent 버튼 — 그 띠에 accent 잉크가 있다.
    #expect(rwAccentInk(live, rect: rwLeaveBand) > 200, "[나가기] 가 안 보인다")

    // ③ 차례 링: 흑 차례라 흑 카드(첫 카드)에만 초록 링, 백 카드엔 없다. 첫 응답 전에는 둘 다 없다(색·차례를 모른다).
    #expect(rwGreenInk(live, rect: rwClockSlot(card: 0)) > 20, "흑 차례인데 흑 카드에 차례 링이 없다")
    #expect(rwGreenInk(live, rect: rwClockSlot(card: 1)) == 0, "백 카드에도 링이 있다")
    #expect(rwGreenInk(loading, rect: rwClockSlot(card: 0)) == 0 && rwGreenInk(loading, rect: rwClockSlot(card: 1)) == 0,
            "첫 응답 전인데 차례 링이 있다 — 색을 추측했다(C15)")
    // 첫 응답 전 카드는 응답 뒤 카드와 다르다(돌 색 줄 없음). 씨앗이 없으면 얼굴도 없다.
    #expect(rwMaxChannelDifference(loading, live, rect: rwCardsRect) > 60, "첫 응답 전 카드가 응답 뒤와 똑같다")
    #expect(rwMaxChannelDifference(loading, seedless, rect: rwCardsRect) > 60, "씨앗 없는 판인데 얼굴이 그려진다")

    // ④ 상태 상자: 진행 중 · 마감 지남 · 끝(승) · 끝(무) 이 서로 다르다. 마감이 지나도 판·카드는 그대로다(패배가 아니다).
    #expect(rwMaxChannelDifference(live, overdue, rect: rwWatchStatusBox) > 60, "마감이 지났는데 상태 상자가 그대로다")
    #expect(rwMaxChannelDifference(live, ended, rect: rwWatchStatusBox) > 60, "끝났는데 상태 상자가 진행 중과 같다")
    #expect(rwMaxChannelDifference(overdue, ended, rect: rwWatchStatusBox) > 60, "마감 지남과 끝이 같은 상자다")
    #expect(rwMaxChannelDifference(ended, drawn, rect: rwWatchStatusBox) > 60, "승과 무승부가 같은 상자다")
    #expect(rwMaxChannelDifference(live, overdue, rect: rwBoardRect) <= 2, "마감이 지나자 판이 바뀌었다")
    // 끝난 판: 링이 없다(두 카드 모두).
    #expect(rwGreenInk(ended, rect: rwClockSlot(card: 0)) == 0 && rwRedFill(ended, rect: rwClockSlot(card: 0)) == 0, "끝난 판에 링이 남았다")
    // 자동 착수가 한 번 남은 사람의 경고가 상태 줄에 **글자로** 선다(툴팁 아님 — 관전 판에는 호버 자리도 없다).
    let statusRow = CGRect(x: rwWatchStatusBox.minX, y: rwWatchStatusBox.minY, width: rwWatchStatusBox.width, height: rwWatchStatusBox.height + 24)
    #expect(rwRedFill(warned, rect: statusRow) > rwRedFill(live, rect: statusRow) + 50, "한 번 더 놓치면 지는 사람의 경고가 안 보인다")

    // ⑤ 창 아래 여백 띠는 로비·대국과 같다(열이 창 밖으로 안 자란다).
    #expect(rwMaxChannelDifference(live, lobby, rect: rwBottomBand) <= 2, "관전 오른쪽 열이 창 아래 여백까지 자란다")

    // ⑥ 마감이 지난 관전 링은 **pending 색 0초**다 — 문구는 "곧 자동으로 놓여요"인데 링만 대국의 ≤5초 빨강(danger)이면 색만으로 패배로 읽힌다.
    //    5초 남은 링은 대국과 같은 빨강(감지기의 기준선 — 같은 입력이면 이 시험은 영원히 초록이다).
    let closing = try rwSpectateBitmap(rwWatch(server: true, deadline: Date().addingTimeInterval(3)))
    #expect(rwDangerInk(closing, rect: rwClockSlot(card: 0)) > 20, "3초 남은 관전 링이 빨갛지 않다(감지기 기준선)")
    #expect(rwDangerInk(overdue, rect: rwClockSlot(card: 0)) == 0, "마감이 지난 관전 링이 빨갛다(danger) — 색만으로 패배로 읽힌다")
    #expect(rwOrangeInk(overdue, rect: rwClockSlot(card: 0)) > 20, "마감이 지난 관전 링이 pending 색이 아니다")
    #expect(rwOrangeInk(closing, rect: rwClockSlot(card: 0)) == 0, "3초 남은 링에 pending 색이 섞였다")
}

/// 없으면(C12 — P1): 관전 화면이 로비 오른쪽 열을 통째로 덮어 받은 신청 카드·[수락]/[거절]·보낸 신청 [취소]·안내줄이 전부 사라져도
/// 초록이다 — 60초 동안 신청을 거둘 길이 없고, 배너 [보기]가 여는 창도 관전 화면이다.
@MainActor
@Test
func spectateKeepsInvitesOutgoingLineAndNoticeAlive() throws {
    let watch = rwWatch(server: true)
    let plain = try rwSpectateBitmap(watch)
    let invited = try rwSpectateBitmap(watch, incoming: [rwInvite("in-1", "민수", 11)])
    let sent = try rwSpectateBitmap(watch, outgoing: rwInvite("out-1", "준호", 12, stake: 10))
    let noticed = try rwSpectateBitmap(watch, notice: "준호님이 수락하면 대결이 시작돼요")
    let crowded = try rwSpectateBitmap(
        watch, incoming: [rwInvite("in-1", "민수", 11), rwInvite("in-2", "서연", 16), rwInvite("in-3", "지영", 13)],
        outgoing: rwInvite("out-1", "준호", 12, stake: 10), notice: "준호님이 수락하면 대결이 시작돼요"
    )
    let crowdedBusy = try rwSpectateBitmap(
        watch, incoming: [rwInvite("in-1", "민수", 11), rwInvite("in-2", "서연", 16), rwInvite("in-3", "지영", 13)],
        outgoing: rwInvite("out-1", "준호", 12, stake: 10), notice: "준호님이 수락하면 대결이 시작돼요", busy: true
    )
    // 보낸 신청이 **없는** 꽉 찬 경우(받은 3건 + 안내줄) — 카드 두 장이 들어간다.
    let crowdedFree = try rwSpectateBitmap(
        watch, incoming: [rwInvite("in-1", "민수", 11), rwInvite("in-2", "서연", 16), rwInvite("in-3", "지영", 13)],
        notice: "준호님이 수락하면 대결이 시작돼요"
    )
    let crowdedFreeBusy = try rwSpectateBitmap(
        watch, incoming: [rwInvite("in-1", "민수", 11), rwInvite("in-2", "서연", 16), rwInvite("in-3", "지영", 13)],
        notice: "준호님이 수락하면 대결이 시작돼요", busy: true
    )
    rwSave(invited, name: "spectate-invite")
    rwSave(crowded, name: "spectate-crowded")
    rwSave(crowdedFree, name: "spectate-crowded-free")
    for (name, bitmap) in [("invited", invited), ("sent", sent), ("noticed", noticed), ("crowded", crowded), ("crowdedFree", crowdedFree)] {
        #expect(rwYellowPixels(bitmap) == 0, "\(name) 에 노란 상자가 있다")
    }

    // ① 받은 신청 카드의 [수락](채운 accent 30pt) 이 남는 자리에 선다.
    #expect(rwAccentInk(invited, rect: rwWatchInfoArea) > rwAccentInk(plain, rect: rwWatchInfoArea) + 1_000,
            "관전 중 받은 신청 카드의 [수락] 이 안 보인다")
    // ② 보낸 신청 [취소] 줄과 안내줄도 선다.
    #expect(rwMaxChannelDifference(plain, sent, rect: rwWatchInfoArea) > 60, "관전 중 보낸 신청 줄이 안 보인다")
    #expect(rwMaxChannelDifference(plain, noticed, rect: rwWatchInfoArea) > 60, "관전 중 안내줄이 안 보인다")
    // ③ 가장 꽉 찬 경우(받은 3건 + 보낸 신청 + 안내줄)에도 **[취소]가 잘리지 않는다**. busy 로 버튼만 흐려진 장과 비교하면 달라지는
    //    행이 곧 버튼들이고, 그 마지막 행이 남는 자리 아랫변보다 위여야 한다(아랫변에 닿으면 잘린 것이다).
    let extent = try #require(rwDiffRowExtent(crowded, crowdedBusy, rect: rwWatchInfoArea), "꽉 찬 관전 열에서 신청 버튼이 하나도 안 보인다")
    #expect(extent.maxY < rwWatchInfoArea.maxY - 2,
            "보낸 신청 [취소] 가 남는 자리 아랫변(\(Int(rwWatchInfoArea.maxY)))에 잘렸다 — 마지막 버튼 행 \(Int(extent.maxY))")
    // 세 카드 중 하나만 + "외 2건" — 카드가 셋 다 서면 [취소]가 잘린다(세로 예산 주석). 카드 [수락]의 accent 면이 한 장 분량이다.
    let single = rwAccentInk(invited, rect: rwWatchInfoArea) - rwAccentInk(plain, rect: rwWatchInfoArea)
    let many = rwAccentInk(crowded, rect: rwWatchInfoArea) - rwAccentInk(plain, rect: rwWatchInfoArea)
    #expect(many < single * 2, "보낸 신청이 있는 꽉 찬 관전 열에 받은 신청 카드가 두 장 이상 섰다(accent \(many) vs 한 장 \(single))")
    // ③′ 보낸 신청이 없으면 **두 장**이 선다 — 상수 1 이면 둘째 신청의 60초가 "외 1건" 뒤에서 거둘 길 없이 흐른다(2026-09-30 반증).
    //    그래도 둘째 카드의 [수락]/[거절] 행이 남는 자리 아랫변 위여야 한다(잘리면 상한을 올린 뜻이 없다).
    let two = rwAccentInk(crowdedFree, rect: rwWatchInfoArea) - rwAccentInk(plain, rect: rwWatchInfoArea)
    #expect(two > single + single / 2 && two < single * 3,
            "보낸 신청이 없는데 관전 열에 받은 신청 카드가 두 장이 아니다(accent \(two) vs 한 장 \(single))")
    let freeExtent = try #require(rwDiffRowExtent(crowdedFree, crowdedFreeBusy, rect: rwWatchInfoArea), "보낸 신청 없는 꽉 찬 열에서 신청 버튼이 하나도 안 보인다")
    #expect(freeExtent.maxY < rwWatchInfoArea.maxY - 2,
            "둘째 카드의 [수락]/[거절] 이 남는 자리 아랫변(\(Int(rwWatchInfoArea.maxY)))에 잘렸다 — 마지막 버튼 행 \(Int(freeExtent.maxY))")
    // 버튼 행 범위: 한 장이면 [수락]/[거절] 한 줄(≈30), 두 장이면 첫 카드 버튼부터 둘째 카드 버튼까지(≈130). 보낸 줄 갈래의 `extent` 와 비교하면 안 된다 —
    // 그쪽 마지막 행은 첫 카드 아래 [취소] 줄이라 둘째 카드 버튼과 높이가 같다(2026-09-30 실측으로 기준선을 바꿨다).
    #expect(freeExtent.maxY - freeExtent.minY > 100,
            "둘째 카드의 버튼 행이 첫 카드 아래에 서지 않았다(버튼 행 범위 \(Int(freeExtent.minY))~\(Int(freeExtent.maxY)) — 한 장이면 약 30)")
    // 자리가 0 인 관전 안내 카드가 위로 넘쳐 "외 N건" 줄을 덮지 않는다 — 넘치면 흰 굵은 글자("관전 중")가 남는 자리 아랫띠에 걸린다(2026-09-30 스냅숏).
    // 아랫띠(마지막 16pt)에는 둘째 카드의 아래 여백·테두리(어두운 면·푸른 획)뿐이라 밝은 픽셀이 0 이어야 한다.
    let bottomSlice = CGRect(x: rwWatchInfoArea.minX, y: rwWatchInfoArea.maxY - 16, width: rwWatchInfoArea.width, height: 16)
    #expect(rwBrightInk(crowdedFree, rect: bottomSlice) == 0, "자리 없는 관전 안내 카드가 위로 넘쳐 받은 신청 칸을 덮는다(밝은 픽셀 \(rwBrightInk(crowdedFree, rect: bottomSlice)))")
    // 감지기 기준선(같은 입력이면 영원히 초록이다): 자리가 넉넉한 안내 카드의 흰 글자는 카드 위쪽(topLeading)에 있어 아랫띠가 아니라 영역 전체에서 잡힌다.
    #expect(rwBrightInk(plain, rect: rwWatchInfoArea) > 0 && rwBrightInk(plain, rect: bottomSlice) == 0,
            "감지기 기준선: 자리가 넉넉한 관전 안내 카드의 글자를 영역 전체에서 못 보거나 아랫띠에서 본다")
    // ④ 신청·안내가 서도 [나가기] 와 창 아래 띠는 그대로다(남는 자리 안에서만 접힌다).
    for (name, bitmap) in [("invited", invited), ("sent", sent), ("noticed", noticed), ("crowded", crowded), ("crowdedFree", crowdedFree)] {
        #expect(rwMaxChannelDifference(plain, bitmap, rect: rwLeaveBand) <= 2, "\(name): [나가기] 가 밀렸다")
        #expect(rwMaxChannelDifference(plain, bitmap, rect: rwBottomBand) <= 2, "\(name): 관전 열이 창 아래 여백까지 자란다")
        // 링 자리는 뺀다 — 두 렌더 사이에 초가 바뀐다(배선이 끊겨도 초록을 만드는 픽셀은 재지 않는다).
        #expect(rwMaxChannelDifference(plain, bitmap, rect: rwCardsFacesRect) <= 2, "\(name): 두 사람 카드가 밀렸다")
    }
}

// MARK: - 순수 규칙 · 소스 계약

/// 없으면: 상태 상자가 스토어 값으로 문구를 골라 마감이 지나도 "흑 차례" 인 채 서 있거나, 마감이 지났다고 "졌다" 고 말해도(C19) 초록이다.
@MainActor
@Test
func watchStatusRuleDecidesByTheLeafClockAndNeverDeclaresALoss() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let active = rwWatch(server: true, deadline: now.addingTimeInterval(12))
    #expect(GomokuWatchStatusRule.kind(for: active, now: now) == .turn(.black))
    #expect(GomokuWatchStatusRule.kind(for: active, now: now.addingTimeInterval(11.9)) == .turn(.black))
    #expect(GomokuWatchStatusRule.kind(for: active, now: now.addingTimeInterval(12)) == .overdue, "마감 순간부터 자동 착수 대기다")
    #expect(GomokuWatchStatusRule.kind(for: active, now: now.addingTimeInterval(600)) == .overdue, "10분이 지나도 관전자는 결과를 단정하지 않는다")
    let overdueText = GomokuWatchStatusRule.text(for: active, now: now.addingTimeInterval(600))
    #expect(overdueText == GomokuText.watchAutoPending)
    #expect(!overdueText.contains("졌") && !overdueText.contains("패"), "마감이 지났다고 패배를 말한다: '\(overdueText)'")
    // 첫 응답 전에는 시각과 무관하게 '불러오는 중'.
    #expect(GomokuWatchStatusRule.kind(for: rwWatch(server: false), now: now.addingTimeInterval(600)) == .loading)
    // 끝난 판은 시각과 무관하게 끝 — 이긴 사람 이름, 없으면 무승부.
    let won = rwWatch(server: true, finished: true, winner: .white, reason: .resign)
    #expect(GomokuWatchStatusRule.text(for: won, now: now) == "대국이 끝났어요 · 상대 승 (기권)")
    let draw = rwWatch(server: true, finished: true, winner: nil, reason: .boardFull)
    #expect(GomokuWatchStatusRule.text(for: draw, now: now) == "무승부 · 판이 가득 찼어요")
    // 이긴 색은 있는데 사람 행이 없으면 색 이름으로 — 무승부로 읽히면 안 된다.
    var orphan = won
    orphan.white = nil
    orphan.black = nil
    #expect(GomokuWatchStatusRule.winnerName(of: orphan) == "백")
    // 경고는 임계 − 1 에서만, 끝난 판에는 없다.
    let threshold = GomokuStore.autoPlaceLossStreak
    #expect(GomokuWatchStatusRule.streakWarning(for: rwWatch(server: true, blackStreak: threshold - 1), lossStreak: threshold)
            == GomokuText.watchStreakWarning(name: "대결자"))
    #expect(GomokuWatchStatusRule.streakWarning(for: rwWatch(server: true, blackStreak: threshold - 2), lossStreak: threshold) == nil)
    #expect(GomokuWatchStatusRule.streakWarning(for: rwWatch(server: true, finished: true, blackStreak: threshold - 1), lossStreak: threshold) == nil)
    #expect(GomokuWatchStatusRule.streakWarning(for: rwWatch(server: false, blackStreak: threshold - 1), lossStreak: threshold) == nil)
}

/// 없으면: 누가 편의로 관전 판에 탭 제스처·호버·금수 표시를 되살리거나, 관전 열에 채팅 카드를 세우거나, [나가기]에 `stopWatching` 을
/// 물려 로비·순위 재조회가 빠지거나, 상태 상자 본문이 `Date()` 를 읽어 창 전체가 매초 다시 그려져도 픽셀 시험은 초록일 수 있다.
@Test
func spectatorViewsKeepInputsChatAndClocksOut() throws {
    let panel = rwStripped(try rwSource("GomokuPanel.swift"))

    // 새 뷰 블록(순위 열 → 관전) — 규칙 보기 앞까지.
    let block = try #require(rwRegion(panel, from: "private struct GomokuRankColumn: View {",
                                      to: "struct GomokuRuleExample: Identifiable, Equatable {"))
    for forbidden in ["GomokuChatCard(", "CheckTextEditor(", "SpatialTapGesture", "onContinuousHover", "store.place(", "resignArea",
                      "isMe: true", "remainingSeconds(", "store.stopWatching(", "Date()", "forbidden:", "preview:", "GomokuStakeButton("] {
        #expect(!block.contains(forbidden), "순위·관전 뷰 블록에 '\(forbidden)' 이 있다")
    }
    for required in ["ScrollView", "clipsOverflowInsteadOfScroll", "minHeight: 0", "store.leaveWatch()", "TimelineView",
                     "GomokuInviteCard(store: store, invite: invite)", "GomokuOutgoingLine(store: store, invite: outgoing)",
                     "GomokuNoticeLine(text: notice)", "store.visibleIncoming", "Task { await store.loadRanking() }",
                     "GomokuWatchInfoCard(watch: watch, isLive: store.isWindowVisible) .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity) .clipped()",
                     "GomokuWatchStatusRule.kind(for: watch, now: context.date)", "GomokuWatchStatusRule.text(for: watch, now: context.date)",
                     ".accessibilityElement(children: .combine)"] {
        #expect(block.contains(required), "순위·관전 뷰 블록에 '\(required)' 가 없다")
    }
    // 순위 열은 재정렬하지 않는다(서버 순서 그대로).
    let rankColumn = try #require(rwRegion(block, from: "", to: "private struct GomokuRankRowView: View {"))
    #expect(!rankColumn.contains(".sorted") && !rankColumn.contains(".sort("), "순위 열이 행을 다시 정렬한다")
    // 순위 행은 사람 행의 착용 캐릭터를 넘기고, isCapable 로 흐리게 하지 않는다(경계에서 전부 false 다).
    let rankRow = try #require(rwRegion(block, from: "private struct GomokuRankRowView: View {", to: "private struct GomokuSpectateSide: View {"))
    #expect(rankRow.contains("userID: entry.user.id") && rankRow.contains("characterHint: entry.user.characterID"))
    #expect(!rankRow.contains("isCapable") && !rankRow.contains("isWorking") && !rankRow.contains("inMatch"), "순위 행이 근무·가능·대국 중을 본다 — 전원이 흐려진다")
    // 상태 상자의 시각 판정은 TimelineView **안**에서만(C19) — 규칙 호출이 TimelineView( 뒤에 온다.
    let statusBox = try #require(rwRegion(block, from: "private struct GomokuWatchStatusBox: View {", to: "private struct GomokuWatchInfoCard: View {"))
    let timeline = try #require(statusBox.range(of: "TimelineView("))
    let decision = try #require(statusBox.range(of: "GomokuWatchStatusRule.kind(for: watch, now: context.date)"))
    #expect(timeline.lowerBound < decision.lowerBound, "상태 상자가 TimelineView 밖에서 문구를 고른다")
    #expect(!statusBox.contains("Date()"), "상태 상자가 Date() 를 읽는다")
    // 관전 링은 마감을 직접 받아 context.date 로 센다(스토어 remainingSeconds 는 내 판만 안다).
    let watchClock = try #require(rwRegion(block, from: "struct GomokuWatchClock: View {", to: "private struct GomokuStakeChip: View {"))
    #expect(watchClock.contains("deadline.timeIntervalSince(context.date)"))
    #expect(watchClock.contains("GomokuClockRing(remaining:"))

    // 창 루트: 관전 분기 · 관전 함수는 시계를 읽지 않는다(V0327 의 루트 영역 검사와 같은 잣대).
    let root = try #require(rwRegion(panel, from: "struct GomokuPanel: View {", to: "private struct GomokuHeader: View {"))
    #expect(root.contains("if let watch = store.spectating { spectate(watch) } else { lobby }"), "로비 자리에 관전 분기가 없다")
    let spectate = try #require(rwRegion(root, from: "private func spectate(_ watch: GomokuSpectateState) -> some View {", to: "private struct GomokuHeader"))
    for clock in ["TimelineView", "Date()", "remainingSeconds", "deadline"] {
        #expect(!spectate.contains(clock), "관전 함수(창 루트)가 '\(clock)' 를 읽는다")
    }
    #expect(spectate.contains("GomokuBoardView(") && spectate.contains("GomokuSpectateSide(store: store, watch: watch)"))
    #expect(spectate.contains(".accessibilityLabel(GomokuText.watchBoardAccessibility(watch))"), "관전 판에 보이스오버 라벨이 없다")
    // 로비 세 열 — 상대 420 · 순위 340 · 오른쪽 400.
    let lobby = try #require(rwRegion(root, from: "private var lobby: some View {", to: "private func spectate("))
    #expect(lobby.contains("GomokuWindowLayout.lobbyUsersWidth") && lobby.contains("GomokuWindowLayout.lobbyRankWidth")
            && lobby.contains("GomokuRankColumn(store: store, clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)"))
    #expect(!lobby.contains("GomokuWindowLayout.lobbyListWidth"), "로비가 아직 780 을 상대 목록 하나에 준다")

    // 머리글 캡슐은 한 출처(C16) — `myRankConsistentWithRecord` 만 읽고 `ranking?.me` 를 직접 안 읽는다. [AI와 두기]는 관전 중 숨긴다.
    let header = try #require(rwRegion(panel, from: "private struct GomokuHeader: View {", to: "private struct GomokuOpponentList: View {"))
    #expect(header.contains("store.myRankConsistentWithRecord"), "머리글이 순위 일치 가드를 안 지난다")
    #expect(!header.contains("ranking?.me") && !header.contains("ranking!.me"), "머리글이 순위 응답의 me 를 직접 읽는다 — 두 출처가 섞인다")
    #expect(header.contains("if store.phase == .lobby, store.spectating == nil {"), "관전 중에도 [AI와 두기] 가 선다")

    // 대결 카드: [관전] 칩은 18 상수 · 내 판 캡션 · 스토어 문 두 개.
    let liveColumn = try #require(rwRegion(panel, from: "private struct GomokuLiveMatchColumn: View {", to: "private struct GomokuLiveMatchCard: View {"))
    #expect(liveColumn.contains("onWatch: { store.startWatching(matchID: live.id) }"), "[관전] 이 스토어를 안 부른다")
    #expect(liveColumn.contains("isMine: store.isMine(live)"), "내 판 카드에도 [관전] 이 선다")
    #expect(liveColumn.contains("canWatch: !store.rankingUnavailable"), "관전이 닫힌 창에서 칩이 잠기지 않는다")
    let liveCard = try #require(rwRegion(panel, from: "private struct GomokuLiveMatchCard: View {", to: "struct GomokuElapsedText: View {"))
    #expect(liveCard.contains("height: GomokuWindowLayout.liveWatchChipHeight"), "[관전] 칩이 레이아웃 상수(18)를 안 쓴다 — 카드가 55 로 자란다")
    #expect(liveCard.contains("GomokuText.myMatch"))

    // 대국 링과 관전 링이 같은 그림을 쓴다 — 보이스오버 라벨은 그림 한 곳에.
    let ring = try #require(rwRegion(panel, from: "struct GomokuClockRing: View {", to: "private struct GomokuResultCard: View {"))
    #expect(ring.contains(".accessibilityLabel(GomokuText.clockAccessibility(remaining))"))
    #expect(panel.components(separatedBy: "GomokuClockRing(remaining:").count - 1 == 2, "링 그림을 두 잎이 같이 쓰지 않는다")
    // 대국 카드의 마감 주입은 맨 끝 기본값 — 대국 호출부는 그대로다.
    let card = try #require(rwRegion(panel, from: "private struct GomokuPlayerCard: View {", to: "private struct GomokuSpeechBubbleSlot: View {"))
    #expect(card.contains("var deadline: Date? = nil"))
    #expect(card.contains("} else if let deadline { GomokuWatchClock(deadline: deadline, isLive: store.isWindowVisible) } else { GomokuTurnClock(store: store) }"))
    // 노란 상자 금지 목록은 새 블록에서도 그대로다.
    for forbidden in ["Picker(", "Menu(", "TextField(", ".help("] {
        #expect(!block.contains(forbidden), "새 블록에 \(forbidden) 가 있다")
    }
    // 창 상수: 창 크기·판·오른쪽 열은 그대로(넓히지 않았다).
    let window = rwStripped(try rwSource("CheckGomokuWindow.swift"))
    #expect(window.contains("static let contentSize = CGSize(width: 1240, height: 700)"), "창을 넓혔다 — 13\" 맥에 안 들어간다")
    #expect(window.contains("static let lobbyUsersWidth: CGFloat = 420") && window.contains("static let liveWatchChipHeight: CGFloat = 18"))
}

// MARK: - 헬퍼(V0327 렌더 하네스와 같은 규칙)

private enum RWRenderError: Error { case failed }

@MainActor
private func rwBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw RWRenderError.failed }
    return bitmap
}

private func rwSave(_ bitmap: NSBitmapImageRep, name: String) {
    MiniGameSnapshots.save(bitmap, name: "v0341-\(name).png", sub: "gomoku")
}

/// ImageRenderer 가 AppKit 기반 컨트롤을 대신 그리는 노란 상자(255,204,0)의 픽셀 수.
private func rwYellowPixels(_ bitmap: NSBitmapImageRep) -> Int {
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

/// 사각형(pt) 안에서 두 비트맵의 채널 최대 차(0 이면 한 바이트도 다르지 않다).
private func rwMaxChannelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
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

/// 두 장이 채널 차 30 을 넘게 다른 행들의 세로 범위(pt). 다른 행이 없으면 nil.
private func rwDiffRowExtent(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> (minY: CGFloat, maxY: CGFloat)? {
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

/// 푸른 accent 잉크(CheckTheme.accent 계열) 픽셀 수와 그 상자(pt).
private func rwAccentBounds(_ bitmap: NSBitmapImageRep, rect: CGRect) -> (count: Int, box: CGRect) {
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

private func rwAccentInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    rwAccentBounds(bitmap, rect: rect).count
}

/// 초록 잉크(CheckTheme.working — 차례 링·진행 중 상태) 픽셀 수.
private func rwGreenInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            let r = Int(data[o]), g = Int(data[o + 1])
            if g > r + 80 && g > 150 { count += 1 }
        }
    }
    return count
}

/// danger(255,115,117) 계열 핵심 픽셀 수 — g≈b 인 분홍빨강. pending(255,184,84)은 g 가 커서 안 잡힌다(`rwRedFill` 은 둘 다 "빨강"으로 세므로 링 색 구분엔 못 쓴다).
private func rwDangerInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    rwCount(bitmap, rect: rect) { r, g, b in r > 200 && g > 80 && g < 150 && b > 80 && b < 150 && abs(g - b) < 25 }
}

/// pending(255,184,84) 계열 핵심 픽셀 수 — 주황. danger 는 g 가 작아서, working 은 r 이 작아서 안 잡힌다.
private func rwOrangeInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    rwCount(bitmap, rect: rect) { r, g, b in r > 200 && g > 140 && g < 215 && b < 120 && g > b + 60 }
}

/// 밝은(흰 계열 글자) 픽셀 수.
private func rwBrightInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    rwCount(bitmap, rect: rect) { r, g, b in r > 200 && g > 200 && b > 200 }
}

private func rwCount(_ bitmap: NSBitmapImageRep, rect: CGRect, _ matches: (Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if matches(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) { count += 1 }
        }
    }
    return count
}

/// 채운 빨강(CheckTheme.danger 면 · 링 5초 이하) 픽셀 수.
private func rwRedFill(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
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
            if r > 170 && r > g + 60 && r > b + 60 { count += 1 }
        }
    }
    return count
}

/// 사각형 안에서 **중성(흰 계열) 테두리 획이 가로로 넓게 깔린** pt 행 목록 — 상자를 세는 자(V0327 과 같은 판정식).
private func rwWideRows(_ bitmap: NSBitmapImageRep, rect: CGRect, minimum: Int) -> [Int] {
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
private func rwBoxTops(_ bitmap: NSBitmapImageRep, rect: CGRect, height: Int, minimum: Int = 300) -> [Int] {
    let wide = rwWideRows(bitmap, rect: rect, minimum: minimum)
    return wide.filter { wide.contains($0 + height) }
}

private func rwSource(_ name: String) throws -> String {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check", isDirectory: true)
    return try String(contentsOf: directory.appendingCheckSourcePath(name), encoding: .utf8)
}

/// `from` 부터 그 뒤 첫 `to` 직전까지(없으면 nil). `from` 이 빈 문자열이면 처음부터.
private func rwRegion(_ source: String, from start: String, to end: String) -> String? {
    let head: Range<String.Index>
    if start.isEmpty {
        head = source.startIndex..<source.startIndex
    } else {
        guard let found = source.range(of: start) else { return nil }
        head = found
    }
    let tail = source.range(of: end, range: head.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
    return String(source[head.upperBound..<tail])
}

/// 주석을 걷어내고 공백을 한 칸으로 접는다(C22 — 안 걷으면 설명을 지워야만 초록이 된다).
private func rwStripped(_ source: String) -> String {
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
