import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.44 체스 화면의 **그물 없던 자리** — 2026-10-05 뮤테이션 실측으로 드러난 것만 담는다.
//
// 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다(관례). 그리고 **기준선이 갈리는지**
// 매 시험에서 함께 잰다 — 두 분기가 동시에 참인 입력이 없으면 그 단언은 영원히 초록이다.
//
// 여기서 메우는 구멍:
//   ③ 관전 결과 문장이 1인칭 패자 어휘였다("흑 승리 / 기권했어요")           — M15 SURVIVED
//   ④⑬ 관전 시계가 스스로 흐르지 않았다(잎 TimelineView 가 없었다)          — M16 SURVIVED
//   ⑨ 체크 덮개가 **어느 왕인가**에 그물이 없었다                            — M13 SURVIVED
//   ⑩ 관전 판돈 칩이 "이기면 +n" 을 말해도 초록이었다                        — M20 SURVIVED
//   ⑭ 받은/보낸 신청 칸이 200pt 예산을 넘쳐 안내 줄 아래가 잘렸다            — 렌더 프로브 실측
//   ⑮ 고른 칸·갈 수 있는 칸·체크 왕 강조를 전부 지워도 체스 40건이 초록이었다
//   ⑯ 기보 줄수 단언이 상수끼리의 산수라 실제 렌더와 묶여 있지 않았다

// MARK: - 픽스처 (다른 파일의 것은 private 이라 복사 — 저장소 규칙)

private func cgUser(_ name: String, _ suffix: Int, character: String? = "shiba") -> ChessUser {
    ChessUser(id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))",
              displayName: name, avatarURL: nil, characterID: character,
              isWorking: true, isCapable: true, inMatch: false, center: nil)
}

private let cgMinsu = cgUser("민수", 11, character: "fox")
private let cgJunho = cgUser("준호", 12, character: "squirrel")
private let cgMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

/// **`turnStartedAt` 을 nil 로 둔다** — 보간이 꺼져 렌더가 결정적이 된다(흐르는 시계를 재면 매번 다른 그림이다).
private func cgFrozenClock(white: Int, black: Int, running: ChessColor? = .white) -> ChessServerClock {
    ChessServerClock(whiteMsLeft: white, blackMsLeft: black, incrementMs: 3_000,
                     turnStartedAt: nil, running: running)
}

private func cgRecord(_ seq: Int, _ color: ChessColor, _ from: String, _ to: String, _ san: String) -> ChessMoveRecord {
    ChessMoveRecord(seq: seq, color: color,
                    move: ChessMove(from: ChessSquare(from)!, to: ChessSquare(to)!),
                    san: san, fen: "x", msLeft: 290_000, msSpent: 3_200)
}

/// 수 n 개의 기보(색이 번갈아 선다 — `ChessMoveLog` 가 색으로 짝을 짓는다).
private func cgMoves(_ count: Int) -> [ChessMoveRecord] {
    (1...max(1, count)).map { seq in
        cgRecord(seq, seq % 2 == 1 ? .white : .black, "e2", "e4", "e4")
    }
}

@MainActor
private func cgPlayingStore(
    fen: String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    myColor: ChessColor = .white,
    turn: ChessColor? = .white,
    moves: [ChessMoveRecord] = [],
    inCheck: Bool = false,
    isWindowVisible: Bool = false,
    clock: ChessServerClock? = nil
) -> ChessStore {
    let store = ChessStore()
    store.pollStepSeconds = 3_600
    store.phase = .playing
    store.isWindowVisible = isWindowVisible
    store.rubyBalance = 32
    store.record = ChessRecord(wins: 7, losses: 3, draws: 1)
    let position = ChessPosition(fen: fen)
    store.match = ChessMatchState(
        id: "match-1", stake: 10, myColor: myColor, opponent: cgMinsu, fen: fen,
        position: position, plyCount: moves.count, turn: turn, lastMove: nil, moves: moves,
        clock: clock ?? cgFrozenClock(white: 300_000, black: 300_000, running: turn),
        isInCheck: inCheck,
        legalMoves: (position.map { ChessRules.legalMoves(in: $0) } ?? []),
        isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil,
        drawOfferBy: nil, drawOfferedByMe: false)
    return store
}

@MainActor
private func cgLobbyStore() -> ChessStore {
    let store = ChessStore()
    store.pollStepSeconds = 3_600
    store.hasLoadedLobby = true
    store.hasLoadedRanking = true
    store.spectatorFeaturesEnabled = true
    store.rubyBalance = 42
    store.record = ChessRecord(wins: 7, losses: 3, draws: 1)
    store.users = [cgMinsu, cgJunho]
    return store
}

/// 관전 상태 한 벌. `running`·`turnStartedAt` 은 호출자가 고른다 — 흐르는 시계를 재는 시험이 그것을 쓴다.
@MainActor
private func cgWatchStore(
    clock: ChessServerClock,
    turn: ChessColor? = .white,
    isWindowVisible: Bool = false
) -> ChessStore {
    let store = cgLobbyStore()
    let fen = "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
    var watch = ChessSpectateState(id: "live-1", faces: [cgMinsu, cgJunho], stake: 5)
    watch.black = cgJunho
    watch.white = cgMinsu
    watch.fen = fen
    watch.position = ChessPosition(fen: fen)
    watch.plyCount = 6
    watch.appliedSeq = 6
    watch.moves = cgMoves(6)
    watch.turn = turn
    watch.clock = clock
    watch.startedAt = Date(timeIntervalSince1970: 1_790_000_000)
    store.spectating = watch
    store.isWindowVisible = isWindowVisible
    return store
}

@MainActor
private func cgPanel(_ store: ChessStore) -> some View {
    ChessPanel(store: store, me: { cgMe }, clipsOverflowInsteadOfScroll: true)
}

// MARK: - 창 좌표 (레이아웃 상수에서만 뽑는다)

private var cgBoardOrigin: CGPoint {
    CGPoint(x: ChessWindowLayout.contentPadding,
            y: ChessWindowLayout.contentPadding + ChessWindowLayout.headerHeight + ChessWindowLayout.headerSpacing)
}

private var cgMatchSideColumn: CGRect {
    CGRect(x: cgBoardOrigin.x + ChessWindowLayout.boardSide + ChessWindowLayout.columnSpacing,
           y: cgBoardOrigin.y, width: ChessWindowLayout.sideColumnWidth, height: ChessWindowLayout.bodyHeight)
}

/// 두 사람 카드 안 시계 칸(창 좌표). index 0 = 위 · 1 = 아래.
private func cgClockRect(card index: Int) -> CGRect {
    let column = cgMatchSideColumn
    let cardTop = column.minY
        + CGFloat(index) * (ChessWindowLayout.playerCardHeight + ChessWindowLayout.matchSideSpacing)
    return CGRect(
        x: column.maxX - ChessWindowLayout.cardInsetX - ChessWindowLayout.clockWidth,
        y: cardTop + (ChessWindowLayout.playerCardHeight - ChessWindowLayout.clockHeight) / 2,
        width: ChessWindowLayout.clockWidth, height: ChessWindowLayout.clockHeight)
}

/// 기보 목록의 **i 번째 줄 자리**(창 좌표). 카드 위 = 카드 둘 + 판돈 줄 + 간격 셋.
private func cgMoveRowRect(_ index: Int) -> CGRect {
    let column = cgMatchSideColumn
    let cardTop = column.minY + ChessWindowLayout.playerCardHeight * 2
        + ChessWindowLayout.matchSideSpacing * 3 + ChessWindowLayout.stakeStatusMinHeight
    let rowsTop = cardTop + ChessWindowLayout.cardPadding
        + ChessWindowLayout.moveHeaderHeight + ChessWindowLayout.moveHeaderSpacing
    return CGRect(x: column.minX + ChessWindowLayout.cardPadding,
                  y: rowsTop + CGFloat(index) * (ChessWindowLayout.moveRowHeight + ChessWindowLayout.moveRowSpacing),
                  width: column.width - ChessWindowLayout.cardPadding * 2,
                  height: ChessWindowLayout.moveRowHeight)
}

/// 그 칸의 가운데 50% 상자(창 좌표).
private func cgSquareProbe(_ square: ChessSquare, _ geometry: ChessBoardGeometry) -> CGRect {
    let box = geometry.rect(of: square).offsetBy(dx: cgBoardOrigin.x, dy: cgBoardOrigin.y)
    return box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)
}

// MARK: - ③ 관전 결과 문장은 3인칭이다

/// 없으면: 관전 상태 상자가 "흑 승리 / 기권했어요" 라는 자기모순을 그려도 초록이다(M15 가 살아남은 자리).
@MainActor
@Test
func theSpectateStatusBoxSpeaksInThirdPersonNotTheLoserVoice() throws {
    // 흑이 이겼다 = **백이** 기권했다.
    var blackWon = ChessSpectateState(id: "m", faces: [cgMinsu, cgJunho], stake: 5)
    blackWon.black = cgJunho
    blackWon.white = cgMinsu
    blackWon.isFinished = true
    blackWon.winner = .black
    blackWon.endReason = .resign
    var whiteWon = blackWon
    whiteWon.winner = .white

    #expect(ChessWatchStatusText.headline(blackWon) == "흑 승리")
    #expect(ChessWatchStatusText.detail(blackWon, notice: nil) == "백이 기권했어요")
    // ★ 기준선이 갈린다: 승자가 반대면 **다른 문장**이 나온다. 안 갈리면 아래 단언이 영원히 초록이다.
    #expect(ChessWatchStatusText.headline(whiteWon) == "백 승리")
    #expect(ChessWatchStatusText.detail(whiteWon, notice: nil) == "흑이 기권했어요")
    #expect(ChessWatchStatusText.detail(blackWon, notice: nil) != ChessWatchStatusText.detail(whiteWon, notice: nil))

    // ★ 1인칭 함수의 **그 값**이 아니다. 옛 코드는 `endReason(_, outcome: nil)` 을 넘겨 언제나 패자 문장이었다.
    #expect(ChessText.endReason(.resign, outcome: nil) == "기권했어요", "전제: 1인칭 함수는 패자 어휘다")
    #expect(ChessWatchStatusText.detail(blackWon, notice: nil) != ChessText.endReason(.resign, outcome: nil))

    // 머리글과 설명이 **같은 사람**을 가리킨다: 승자 이름이 설명의 주어로 오면 안 된다.
    for winner in ChessColor.allCases {
        var state = blackWon
        state.winner = winner
        let head = ChessWatchStatusText.headline(state)
        let body = ChessWatchStatusText.detail(state, notice: nil)
        #expect(head.hasPrefix(ChessText.stoneName(winner)), "머리글이 승자를 안 말한다: \(head)")
        #expect(body.hasPrefix(ChessText.stoneName(winner.opponent)),
                "설명의 주어가 패자가 아니다 — 관전자가 '\(head) / \(body)' 를 읽는다")
    }

    // 사람이 읽는 **갈래 전부**를 값으로 되묻는다. 1인칭 축의 흔적('상대가'·'당했어요' 의 주어 없는 꼴)이 남으면 안 된다.
    let winnerIsBlack = ChessEndReason.allCases.map { ($0, ChessText.watchEndReason($0, winner: .black)) }
    for (reason, text) in winnerIsBlack {
        #expect(!text.contains("상대"), "\(reason.rawValue): 관전 문장에 '상대' 가 있다 — 관전자에겐 주어가 없다")
        #expect(!text.isEmpty, "\(reason.rawValue): 관전 문장이 비었다")
    }
    // 승패가 있는 넷은 주어가 붙고, 무승부 갈래는 안 붙는다(두 갈래가 다르다 = 기준선 갈림).
    #expect(ChessText.watchEndReason(.checkmate, winner: .black) == "백이 체크메이트를 당했어요")
    #expect(ChessText.watchEndReason(.timeout, winner: .white) == "흑의 시간이 다 됐어요")
    #expect(ChessText.watchEndReason(.abandoned, winner: .black) == "백이 더 둘 수 없게 됐어요")
    #expect(ChessText.watchEndReason(.agreement, winner: nil) == "무승부에 합의했어요")
    #expect(ChessText.watchEndReason(.resign, winner: nil) == "기권으로 끝났어요")
    #expect(ChessText.watchEndReason(nil, winner: .black) == "")

    // 안 끝난 판은 안내줄·기본 문구다(끝난 판 갈래가 아무것도 안 먹는 경우를 가른다).
    var live = blackWon
    live.isFinished = false
    live.winner = nil
    live.endReason = nil
    live.turn = .white
    #expect(ChessWatchStatusText.headline(live) == "백 차례")
    #expect(ChessWatchStatusText.detail(live, notice: nil) == ChessText.watchPaused)
    #expect(ChessWatchStatusText.detail(live, notice: "안내 한 줄") == "안내 한 줄")
}

// MARK: - ④⑬ 관전 시계가 **살아 있는 창에서 스스로** 흐른다

/// 없으면: 관전 시계가 `spectating` 이 갈릴 때만 다시 그려져 2초 폴링 눈금으로 튀고, 폴링이 멈추는 순간
/// (가림 통지·세션·주 스위치·연속 실패) 창이 보이는데도 통째로 정지해도 초록이다(M16 이 살아남은 자리).
///
/// ★ `ImageRenderer` 로는 못 잰다. 그것은 부를 때마다 처음부터 그리므로, 본문이 `Date()` 를 **상수로** 넘겨도
///   매번 다른 값이 나와 "스스로 흐르는 것" 과 구별되지 않는다. 재야 하는 것은 **얹혀 있는 동안 스스로 다시
///   그리는가** 이고, 그것은 살아 있는 `NSHostingView` 만 안다.
///
/// 기준선 셋이 갈린다: ① 대국 화면의 **흐르는 쪽**은 바뀐다(캡처 장치가 멀쩡하다는 대조)
///                     ② 대국 화면의 **멈춘 쪽**은 안 바뀐다(설계대로)
///                     ③ 관전 화면의 **흐르는 쪽**도 바뀐다(이 수리의 본론)
@MainActor
@Test
func theSpectateClockRunsOnItsOwnInsideALiveWindow() throws {
    // 마지막 10초는 소수 한 자리로 그려지므로(ChessText.clock) 0.1초마다 글자가 바뀐다 — 짧게 재도 결정이 난다.
    // 멈춘 쪽은 3분대라 재는 창 동안 한 글자도 바뀔 수 없다.
    let running = 8_400, stopped = 192_000
    let now = Date()

    // ① 대국: 내가 백이고 백이 흐른다 → 아래 카드(1)가 흐르고 위 카드(0)는 멈춘다.
    let play = cgPlayingStore(
        turn: .white, isWindowVisible: true,
        clock: ChessServerClock(whiteMsLeft: running, blackMsLeft: stopped, incrementMs: 3_000,
                                turnStartedAt: now, running: .white))
    let playFlow = try cgLiveFlow(cgPanel(play), probes: [cgClockRect(card: 1), cgClockRect(card: 0)])
    print("[시계] 대국 흐르는 쪽 \(playFlow[0])px 변화 · 멈춘 쪽 \(playFlow[1])px 변화")
    #expect(playFlow[0] > 0,
            "대국 화면의 흐르는 시계가 1.5초 동안 한 바이트도 안 바뀐다 — 캡처 장치가 죽었다(이 시험은 아무것도 못 잰다)")
    #expect(playFlow[1] == 0, "멈춘 쪽 시계가 바뀐다 — 두 시계가 같은 값을 읽는다")

    // ③ 관전: 흑이 흐른다 → 위 카드(0 = 흑)가 흐르고 아래(1 = 백)는 멈춘다.
    let watch = cgWatchStore(
        clock: ChessServerClock(whiteMsLeft: stopped, blackMsLeft: running, incrementMs: 3_000,
                                turnStartedAt: now, running: .black),
        turn: .black, isWindowVisible: true)
    let watchFlow = try cgLiveFlow(cgPanel(watch), probes: [cgClockRect(card: 0), cgClockRect(card: 1)])
    print("[시계] 관전 흐르는 쪽 \(watchFlow[0])px 변화 · 멈춘 쪽 \(watchFlow[1])px 변화")
    #expect(watchFlow[0] > 0,
            "관전 시계가 살아 있는 창에서 한 바이트도 안 바뀐다 — 잎 TimelineView 가 없어 폴링 눈금에만 튄다")
    #expect(watchFlow[1] == 0, "관전의 멈춘 쪽 시계가 바뀐다 — 두 시계가 같은 값을 읽는다")

    // ★ 흐름이 **폴링과 무관**하다: 관전 폴링이 돌 수 없는 상태(주 스위치 꺼짐)에서도 시계는 흐른다.
    //   창 쪽 불변식("가림 통지가 틀려도 보이는 창의 시계가 멈추면 안 된다")이 관전에도 선다.
    let unpollable = cgWatchStore(
        clock: ChessServerClock(whiteMsLeft: stopped, blackMsLeft: running, incrementMs: 3_000,
                                turnStartedAt: Date(), running: .black),
        turn: .black, isWindowVisible: true)
    unpollable.spectatorFeaturesEnabled = false
    #expect(!unpollable.canPollSpectatorFeatures, "전제: 이 상태에서는 관전 폴링이 한 건도 못 나간다")
    #expect(!unpollable.shouldPollWatch)
    let stillFlows = try cgLiveFlow(cgPanel(unpollable), probes: [cgClockRect(card: 0)])
    print("[시계] 폴링이 멈춘 관전 \(stillFlows[0])px 변화")
    #expect(stillFlows[0] > 0, "폴링이 멈추자 보이는 창의 관전 시계가 통째로 정지했다")

    // 창이 안 보이면 둘 다 멈춘다(규약 — 보이지 않는 창에서 매초 그리지 않는다).
    let hidden = cgWatchStore(
        clock: ChessServerClock(whiteMsLeft: stopped, blackMsLeft: running, incrementMs: 3_000,
                                turnStartedAt: Date(), running: .black),
        turn: .black, isWindowVisible: false)
    let hiddenFlow = try cgLiveFlow(cgPanel(hidden), probes: [cgClockRect(card: 0)])
    print("[시계] 창이 안 보이는 관전 \(hiddenFlow[0])px 변화")
    #expect(hiddenFlow[0] == 0, "창이 안 보이는데 관전 시계가 돈다 — 안 보이는 창에서 매초 그린다")
}

// MARK: - ⑨ 체크 덮개는 **차례인 쪽** 왕에 선다

/// 없으면: `kingSquare(of: turn)` 을 `turn.opponent` 로 바꿔도 전부 초록이다(M13 이 살아남은 자리) —
/// 화면이 서버가 말한 것과 **정반대** 왕에 빨간 덮개를 그린다.
@MainActor
@Test
func theCheckTintMarksTheKingWhoseTurnItIs() throws {
    // 백 차례 · 백이 체크(h1 룩이 1랭크를 쏜다). 두 왕이 멀리 떨어져 있어 두 자리를 따로 잴 수 있다.
    let fen = "4k3/8/8/8/8/8/8/4K2r w - - 0 1"
    let position = try #require(ChessPosition(fen: fen))
    let whiteKing = try #require(position.kingSquare(of: .white))
    let blackKing = try #require(position.kingSquare(of: .black))
    #expect(whiteKing.notation == "e1" && blackKing.notation == "e8", "전제: 두 왕이 e1·e8 이다")
    #expect(ChessRules.isInCheck(position), "전제: 이 국면에서 **차례인 백**이 체크다")

    let checked = try cgBitmap(cgPanel(cgPlayingStore(fen: fen, turn: .white, inCheck: true)))
    let plain = try cgBitmap(cgPanel(cgPlayingStore(fen: fen, turn: .white, inCheck: false)))
    cgSave(checked, name: "check-tint")

    let g = ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: .white)
    let onTurnKing = cgMaxChannelDifference(checked, plain, rect: cgSquareProbe(whiteKing, g))
    let otherKing = cgMaxChannelDifference(checked, plain, rect: cgSquareProbe(blackKing, g))
    print("[체크] 차례쪽 왕(e1) \(onTurnKing) · 반대편 왕(e8) \(otherKing)")
    #expect(onTurnKing > 15, "체크인데 **차례쪽** 왕 칸이 한 픽셀도 안 바뀐다 — 덮개가 안 그려졌다")
    #expect(otherKing == 0, "체크가 아닌 왕에 덮개가 그려졌다 — 서버가 말한 것과 정반대다")

    // 덮개는 **빨강 쪽**이다(파랑 선택 덮개와 뒤바뀌면 사용자는 '고른 칸' 으로 읽는다).
    let before = try #require(cgAverage(plain, rect: cgSquareProbe(whiteKing, g)))
    let after = try #require(cgAverage(checked, rect: cgSquareProbe(whiteKing, g)))
    print("[체크] e1 평균색 \(before) → \(after)")
    #expect(after.r - before.r > after.b - before.b,
            "체크 덮개가 빨강 쪽으로 안 간다 — 고른 칸(파랑) 덮개와 구별되지 않는다")

    // ★ 기준선 갈림: 차례가 흑인 같은 국면이면 덮개가 **e8 쪽**으로 옮긴다(함수가 `turn` 을 실제로 읽는다).
    let blackTurnFEN = "4k2R/8/8/8/8/8/8/4K3 b - - 0 1"
    let blackPosition = try #require(ChessPosition(fen: blackTurnFEN))
    #expect(ChessRules.isInCheck(blackPosition), "전제: 이 국면에서 차례인 흑이 체크다")
    let blackChecked = try cgBitmap(cgPanel(cgPlayingStore(fen: blackTurnFEN, turn: .black, inCheck: true)))
    let blackPlain = try cgBitmap(cgPanel(cgPlayingStore(fen: blackTurnFEN, turn: .black, inCheck: false)))
    let blackKing2 = try #require(blackPosition.kingSquare(of: .black))
    let whiteKing2 = try #require(blackPosition.kingSquare(of: .white))
    let onTurn2 = cgMaxChannelDifference(blackChecked, blackPlain, rect: cgSquareProbe(blackKing2, g))
    let other2 = cgMaxChannelDifference(blackChecked, blackPlain, rect: cgSquareProbe(whiteKing2, g))
    print("[체크] 흑 차례: 차례쪽 왕(e8) \(onTurn2) · 반대편(e1) \(other2)")
    #expect(onTurn2 > 15 && other2 == 0, "차례가 흑인데 덮개가 안 옮겼다 — 덮개가 색을 박아 두고 있다")

    // 끝난 판에는 덮개가 없다(결과 화면에서 빨간 왕이 남으면 "아직 체크다" 로 읽힌다).
    let over = cgPlayingStore(fen: fen, turn: .white, inCheck: true)
    var finished = try #require(over.match)
    finished.isFinished = true
    finished.outcome = .lost
    finished.endReason = .checkmate
    over.match = finished
    over.phase = .result
    let overBitmap = try cgBitmap(cgPanel(over))
    #expect(cgMaxChannelDifference(overBitmap, try cgBitmap(cgPanel(cgResultStore(fen: fen))),
                                  rect: cgSquareProbe(whiteKing, g)) == 0,
            "끝난 판에 체크 덮개가 남았다")
}

@MainActor
private func cgResultStore(fen: String) -> ChessStore {
    let store = cgPlayingStore(fen: fen, turn: .white, inCheck: false)
    var finished = store.match!
    finished.isFinished = true
    finished.outcome = .lost
    finished.endReason = .checkmate
    store.match = finished
    store.phase = .result
    return store
}

// MARK: - ⑩ 관전 판돈 칩은 **보상을 약속하지 않는다**

/// 없으면: 관전 칩을 `showsReward: true` 로 바꿔도 전부 초록이다(M20) — 0ba552d 가 오목에서 고친
/// "관전자에게 '이기면 +10' 이라 말했다" 가 체스에서 조용히 되돌아온다.
@MainActor
@Test
func theSpectateStakeChipNeverPromisesAReward() throws {
    // 값으로 되묻는다(칩은 순수 함수로 글자를 뗀다).
    #expect(ChessStakeChip.text(stake: 10, showsReward: true) == "10 · 이기면 +10")
    #expect(ChessStakeChip.text(stake: 10, showsReward: false) == "10")
    // ★ 기준선 갈림: 같은 판돈인데 두 갈래가 **다른 글자**다(같으면 아래 단언이 영원히 초록이다).
    #expect(ChessStakeChip.text(stake: 10, showsReward: true) != ChessStakeChip.text(stake: 10, showsReward: false))
    #expect(ChessStakeChip.text(stake: nil, showsReward: false) == ChessText.stakeUnknown)

    // ★ 그리고 **화면이** 그렇게 그린다. 대국 화면과 관전 화면의 **같은 자리**(판돈 칩 190×44)를 같은 판돈으로
    //   견준다 — 두 화면은 같은 열 기하·같은 배경이라 그 사각형에서 다른 것은 칩의 글자뿐이다.
    //   관전이 `showsReward: true` 로 되돌아가면 두 그림이 같아지고 잉크 차가 0 이 되어 아래 둘이 빨개진다.
    let watchPanel = try cgBitmap(cgPanel(cgWatchStore(clock: cgFrozenClock(white: 274_000, black: 192_000))))
    let playPanel = try cgBitmap(cgPanel(cgPlayingStore(moves: cgMoves(6))))
    let chipRect = CGRect(x: cgMatchSideColumn.minX,
                          y: cgMatchSideColumn.minY + ChessWindowLayout.playerCardHeight * 2
                            + ChessWindowLayout.matchSideSpacing * 3,
                          width: 190, height: ChessWindowLayout.stakeStatusMinHeight)
    let watchChipInk = cgInk(watchPanel, rect: chipRect)
    let playChipInk = cgInk(playPanel, rect: chipRect)
    print("[관전 칩] 관전 \(watchChipInk)px · 대국 \(playChipInk)px (같은 자리 · 같은 칩 부품)")
    #expect(watchChipInk > 120, "관전 판돈 칩 자리가 비어 있다 — 아래 대조가 아무것도 안 잰다")
    #expect(playChipInk > 120, "대국 판돈 칩 자리가 비어 있다")
    // 대국 칩은 "· 이기면 +n" 을 더 그리므로 같은 자리의 잉크가 더 많다. 관전이 같은 문구로 돌아가면 차가 사라진다.
    #expect(playChipInk > watchChipInk + 150,
            "관전 칩이 대국 칩과 같은 양을 그린다(관전 \(watchChipInk) vs 대국 \(playChipInk)) — 관전자에게 '이기면 +n' 을 약속하고 있다")
    #expect(cgMaxChannelDifference(watchPanel, playPanel, rect: chipRect) > 60,
            "관전·대국의 판돈 칩이 같은 픽셀이다 — showsReward 가 그림까지 안 간다")
}

// MARK: - ⑭ 받은/보낸 신청 칸이 세로 예산 안에 든다

/// 없으면: 예산이 칸의 실제 높이를 못 덮어도 초록이다. 옛 값 200pt 는 **처음부터 모자랐다**(실측 209pt) —
/// `.frame(maxHeight:)` 는 가운데 정렬이라 모자란 만큼 내용이 위로 밀려 위 칸("지금 대결 중")과 붙고,
/// 아래로도 같은 양이 새어 부모 열의 `.clipped()`(하단 680pt)가 카드의 아래 여백·테두리를 자른다.
/// 근거 주석이 `chessCard` 여백 16×2 와 "받은 신청" 제목 줄 20 을 안 세서 생긴 일이다.
@MainActor
@Test
func theLobbyInvitesBoxFitsInsideItsVerticalBudget() throws {
    let store = cgLobbyStore()
    store.incoming = ChessInvite(id: "in-1", peer: cgMinsu, stake: 5,
                                 expiresAt: Date(timeIntervalSince1970: 1_790_000_048))
    store.outgoing = ChessInvite(id: "out-1", peer: cgJunho, stake: 10,
                                 expiresAt: Date(timeIntervalSince1970: 1_790_000_031))
    // 두 줄로 접히는 안내(평범한 상태다: 내가 A에게 신청 + B가 나에게 신청 + 안내 한 줄).
    store.setNotice("상대의 루비가 모자라서 지금은 대결을 시작할 수 없어요. 잠시 뒤에 다시 신청해 주세요.")

    let width = ChessWindowLayout.lobbySideWidth
    let natural = try cgBitmap(ChessLobbyInvitesBox(store: store).frame(width: width))
    let naturalHeight = Double(natural.pixelsHigh) / 2
    print("[신청 칸] 자연 높이 \(naturalHeight)pt · 예산 \(ChessWindowLayout.lobbyInvitesMaxHeight)pt")
    #expect(naturalHeight > 200,
            "전제: 받은+보낸+두 줄 안내가 옛 예산 200pt 를 넘는다(\(naturalHeight)pt) — 안 넘으면 이 시험이 아무것도 안 잰다")
    #expect(naturalHeight <= Double(ChessWindowLayout.lobbyInvitesMaxHeight),
            "신청 칸의 실제 높이 \(naturalHeight)pt 가 예산 \(ChessWindowLayout.lobbyInvitesMaxHeight)pt 를 넘는다 — 아래가 잘린다")

    // ★ 결과로 잰다. 앱의 칸은 `.frame(maxHeight:)` 라 **가운데 정렬**이다 — 예산이 모자라면 카드가 위아래로
    //   같은 양씩 삐져나가고 부모 열의 `.clipped()` 가 그만큼을 자른다. 사용자가 보는 것은 **끊긴 상자**다:
    //   둥근 위·아래 테두리가 사라지고 카드가 위 칸("지금 대결 중")에 붙는다.
    //   그래서 "예산 높이로 자른 그림에서 카드의 위·아래 테두리가 **그림 안쪽**에 있는가" 를 잰다.
    let fitted = try cgCardEdges(store, width: width, box: ChessWindowLayout.lobbyInvitesMaxHeight)
    let squeezed = try cgCardEdges(store, width: width, box: 200)
    print("[신청 칸] 카드 위·아래 끝: 예산 안 \(fitted) · 옛 예산 200pt \(squeezed)")
    #expect(fitted.top > 0 && fitted.bottom < Double(ChessWindowLayout.lobbyInvitesMaxHeight) - 1,
            "예산 \(ChessWindowLayout.lobbyInvitesMaxHeight)pt 안에서 카드 테두리가 잘린다(\(fitted)) — 상자가 끊겨 보인다")
    // ★ 기준선이 갈린다: 옛 예산 200pt 에서는 **같은 내용**의 위·아래가 둘 다 그림 경계에 닿는다(= 잘렸다).
    #expect(squeezed.top == 0 && squeezed.bottom >= 199,
            "옛 예산 200pt 에서도 카드가 온전하다(\(squeezed)) — 이 시험의 측정이 죽었다")

    // 예산은 조각의 합이다(주석이 아니라 코드) — 조각 하나를 바꾸면 합도 따라 바뀐다.
    let L = ChessWindowLayout.self
    #expect(L.lobbyInvitesMaxHeight == L.cardPadding * 2 + L.lobbyInvitesTitleHeight + L.lobbyInviteCardHeight
            + L.lobbyOutgoingLineHeight + L.lobbyNoticeLineHeight + L.lobbyInvitesSpacing * 3)
    #expect(L.lobbyRecordHeight + L.lobbyLiveHeight + L.lobbyInvitesMaxHeight
            + L.lobbySideSpacing * 2 == L.bodyHeight, "로비 오른쪽 열의 세로 예산이 안 맞는다")
}

/// 신청 칸을 앱과 **같은 모양**(`.frame(maxHeight:)` = 가운데 정렬)으로 `box` 높이에 넣고 자른 뒤,
/// 카드(배경이 깔린 영역)의 위·아래 끝 줄을 돌려준다. 잘렸으면 그 끝이 그림 경계에 닿는다.
@MainActor
private func cgCardEdges(_ store: ChessStore, width: CGFloat,
                         box: CGFloat) throws -> (top: Double, bottom: Double) {
    let bitmap = try cgBitmap(
        ChessLobbyInvitesBox(store: store)
            .frame(width: width)
            .frame(maxHeight: box)
            .clipped()
            .frame(width: width, height: box)
            .background(Color.black)
    )
    var top: Double? = nil
    var bottom: Double? = nil
    for y in 0..<bitmap.pixelsHigh {
        let band = CGRect(x: 0, y: Double(y) / 2, width: Double(bitmap.pixelsWide) / 2, height: 0.5)
        // 카드 배경(CheckTheme.panel 0.85)은 검정 위에서 어느 채널이든 20 을 넘는다.
        guard cgCount(bitmap, rect: band, where: { r, g, b in max(r, max(g, b)) > 20 }) > 4 else { continue }
        if top == nil { top = Double(y) / 2 }
        bottom = Double(y) / 2
    }
    guard let top, let bottom else { throw CGRenderError.failed }
    return (top, bottom)
}

// MARK: - ⑮ 입력 2단의 '보이는 절반'

/// 없으면: 고른 칸 덮개 · 갈 수 있는 칸 점/고리 · 체크 왕 덮개를 **통째로 지워도** 체스 40건이 전부 초록이다
/// (렌더 테스트 전체에 `selected`·`targets`·`checkSquare` 문자열이 0회였다 — 말을 골라도 아무 칸도 밝아지지 않는 회귀가 그냥 나간다).
@MainActor
@Test
func thePlayBoardLightsTheSelectedSquareAndItsTargets() throws {
    let store = cgPlayingStore()                     // 초기 배치 · 백 차례 · 내 차례
    let e2 = try #require(ChessSquare("e2"))
    let e3 = try #require(ChessSquare("e3"))
    let e4 = try #require(ChessSquare("e4"))
    let idle = try cgBitmap(cgPanel(store))

    store.selection = ChessSelection(from: e2, targets: [e3, e4])
    let picked = try cgBitmap(cgPanel(store))
    cgSave(picked, name: "playing-selected")

    let g = ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: .white)
    let onSelected = cgMaxChannelDifference(idle, picked, rect: cgSquareProbe(e2, g))
    let onTargetEmpty = cgMaxChannelDifference(idle, picked, rect: cgSquareProbe(e3, g))
    let onTargetFar = cgMaxChannelDifference(idle, picked, rect: cgSquareProbe(e4, g))
    let elsewhere = cgMaxChannelDifference(idle, picked, rect: cgSquareProbe(try #require(ChessSquare("a5")), g))
    print("[고르기] e2 \(onSelected) · e3 \(onTargetEmpty) · e4 \(onTargetFar) · a5 \(elsewhere)")
    #expect(onSelected > 15, "말을 골랐는데 그 칸이 안 밝아진다 — 사용자는 무엇을 집었는지 모른다")
    #expect(onTargetEmpty > 15, "갈 수 있는 빈 칸에 점이 안 찍힌다")
    #expect(onTargetFar > 15, "갈 수 있는 칸 둘 중 하나만 그려진다")
    // ★ 기준선 갈림: **고르지 않은 칸은 한 픽셀도 안 바뀐다**(안 갈리면 위 셋은 화면 전체가 바뀌어도 초록이다).
    #expect(elsewhere == 0, "고르기와 무관한 칸이 바뀐다 — 화면 전체가 다시 그려지고 있다")

    // 덮개는 **중간 톤**이라 '말 잉크' 감지기를 멀게 하지 않는다(32칸 단언을 지키는 규칙).
    #expect(cgPieceInk(picked, rect: cgSquareProbe(e3, g)) == 0,
            "도착 점이 '말 잉크' 로 세어진다 — 32칸 단언이 쓸모없어진다")
    #expect(cgPieceInk(picked, rect: cgSquareProbe(e2, g)) > 0, "고른 칸의 말이 덮개에 가려 사라졌다")

    // 잡는 칸은 **고리**이고 빈 칸은 **점**이다(점을 말 위에 찍으면 무엇을 잡는지 가린다).
    //   d5 에 흑 폰이 있는 국면에서 c4→d5(잡기)와 c4→c5(빈 칸)를 함께 켜고 두 자리를 견준다.
    let capture = cgPlayingStore(fen: "rnbqkbnr/ppp1pppp/8/3p4/2B5/8/PPPPPPPP/RNBQK1NR w KQkq - 0 2")
    let c4 = try #require(ChessSquare("c4"))
    let d5 = try #require(ChessSquare("d5"))
    let c5 = try #require(ChessSquare("c5"))
    let beforeCapture = try cgBitmap(cgPanel(capture))
    capture.selection = ChessSelection(from: c4, targets: [d5, c5])
    let afterCapture = try cgBitmap(cgPanel(capture))
    let ringCenter = cgSquareProbe(d5, g).insetBy(dx: 14, dy: 14)   // 고리 **안쪽**(말이 보여야 한다)
    let dotCenter = cgSquareProbe(c5, g).insetBy(dx: 14, dy: 14)
    let ringDelta = cgMaxChannelDifference(beforeCapture, afterCapture, rect: ringCenter)
    let dotDelta = cgMaxChannelDifference(beforeCapture, afterCapture, rect: dotCenter)
    print("[고르기] 잡는 칸 가운데 \(ringDelta) · 빈 칸 가운데 \(dotDelta)")
    #expect(dotDelta > 15, "빈 칸 가운데에 점이 없다")
    #expect(ringDelta < dotDelta,
            "잡는 칸 가운데도 빈 칸처럼 칠해졌다(\(ringDelta) vs \(dotDelta)) — 점이 잡을 말을 가린다")
}

// MARK: - ⑯ 기보 줄수는 **실제로 그려지는** 줄수다

/// 없으면: `moveVisibleRows` 단언이 상수끼리의 산수라 실제 렌더와 묶여 있지 않다 — 상태 상자 안내가 두 줄로
/// 자라 판돈 줄이 커지면 실제로는 10줄만 들어가는데 아무 단언도 그것을 말하지 않는다.
@MainActor
@Test
func theMoveListDrawsExactlyTheRowsItsBudgetClaims() throws {
    let rows = ChessWindowLayout.moveVisibleRows
    #expect(rows == 11, "전제: 예산이 11줄을 주장한다")

    // 11줄을 꽉 채우는 수 = 22(한 줄에 백·흑 둘).
    let full = try cgBitmap(cgPanel(cgPlayingStore(moves: cgMoves(rows * 2))))
    cgSave(full, name: "movelist-full")
    var inks: [Int] = []
    for index in 0...rows { inks.append(cgInk(full, rect: cgMoveRowRect(index))) }
    print("[기보] \(rows * 2)수 줄별 잉크 \(inks)")
    // 마지막 수가 있는 줄은 **채운 배경**으로 강조되므로(ChessMoveLine) 잉크가 훨씬 많다 — 바닥만 본다.
    #expect(inks.prefix(rows).allSatisfy { $0 > 100 },
            "주장한 \(rows)줄 중 일부가 안 그려졌다(줄별 잉크 \(Array(inks.prefix(rows))))")
    // ★ 기준선 갈림: **한 줄 더 들어갈 자리는 비어 있다**(안 갈리면 위 단언은 몇 줄이든 초록이다).
    #expect(inks[rows] == 0,
            "\(rows + 1)번째 자리에 잉크가 \(inks[rows])px 있다 — 예산이 실제 줄수를 모자라게 세고 있다")
    // 강조 줄이 실제로 더 진하다(아래 대조의 기준값이 그 줄이다).
    let highlighted = inks[rows - 1]
    #expect(highlighted > 1_000, "마지막 수 강조가 안 그려졌다(\(highlighted)px) — 아래 대조의 기준이 사라진다")

    // 한 줄 더 쌓으면 그 자리가 **부분만** 그려진다(= 거기가 바로 클립 경계다).
    // 강조 줄이 그 자리로 옮겨 가므로 온전했을 때의 잉크는 위 `highlighted` 와 같아야 한다.
    let over = try cgBitmap(cgPanel(cgPlayingStore(moves: cgMoves((rows + 1) * 2))))
    let spill = cgInk(over, rect: cgMoveRowRect(rows))
    print("[기보] \((rows + 1) * 2)수 \(rows + 1)번째 줄 잉크 \(spill)px (온전한 강조 줄 \(highlighted)px)")
    #expect(spill > 0, "\(rows + 1)번째 줄이 통째로 사라졌다 — 클립 경계가 주장한 자리와 다르다")
    #expect(spill < highlighted * 3 / 4,
            "\(rows + 1)번째 줄이 온전히 그려진다(\(spill) vs \(highlighted)) — 예산이 실제보다 적게 세고 있다")

    // 사장된 상수를 다시 들이지 않는다: 관전 기보는 대국과 같은 자리·같은 높이를 **공간 흡수**로 얻는다.
    let watch = try cgBitmap(cgPanel(cgWatchStore(clock: cgFrozenClock(white: 274_000, black: 192_000))))
    #expect(cgInk(watch, rect: cgMoveRowRect(0)) > 0, "관전 기보 첫 줄이 대국과 다른 자리에 선다")
    #expect(cgInk(watch, rect: cgMoveRowRect(rows)) == 0, "관전 기보가 대국보다 한 줄 더 그린다")
}

// MARK: - 헬퍼

private enum CGRenderError: Error { case failed }

@MainActor
private func cgBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw CGRenderError.failed }
    return bitmap
}

private func cgSave(_ bitmap: NSBitmapImageRep, name: String) {
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "chess")
}

/// 살아 있는 창에 얹은 뷰가 **스스로 다시 그리는가**를 재는 프로브.
///
/// 알파 0 창에 `NSHostingView` 를 올리고(테스트가 사용자 클릭을 훔치지 않게 — `test-panels-steal-user-clicks`),
/// `RunLoop` 를 실제로 돌린 뒤 같은 자리를 두 번 떠서 사각형별로 **달라진 픽셀 수**를 돌려준다.
/// `ImageRenderer` 로는 이것을 잴 수 없다(부를 때마다 처음부터 그린다 — 머리 주석 ★).
@MainActor
private func cgLiveFlow(_ view: some View, probes: [CGRect], seconds: TimeInterval = 1.5) throws -> [Int] {
    let size = ChessWindowLayout.contentSize
    let host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.alphaValue = 0
    // ★ 클릭을 삼키지 않게 못 박는다(알파 0 패널이 사용자 클릭을 먹는 사고가 이 저장소에 있었다).
    window.ignoresMouseEvents = true
    window.contentView = host
    window.orderFrontRegardless()
    defer {
        window.orderOut(nil)
        window.contentView = nil
    }
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    let first = try cgSnapshot(host, size: size)
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    let second = try cgSnapshot(host, size: size)
    return probes.map { cgChangedPixels(first, second, rect: $0) }
}

@MainActor
private func cgSnapshot(_ host: NSView, size: CGSize) throws -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else { throw CGRenderError.failed }
    rep.size = NSSize(width: size.width, height: size.height)   // 1x — 글자 한 자 변화면 충분하다
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    host.displayIgnoringOpacity(host.bounds, in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// 사각형(pt, 1x) 안에서 달라진 픽셀 수.
private func cgChangedPixels(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else { return -1 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX))
    let y0 = max(0, Int(rect.minY)), y1 = min(lhs.pixelsHigh - 1, Int(rect.maxY))
    guard x0 <= x1, y0 <= y1 else { return -1 }
    var changed = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let offset = y * bpr + x * spp
            for channel in 0..<min(3, spp) where abs(Int(a[offset + channel]) - Int(b[offset + channel])) > 8 {
                changed += 1
                break
            }
        }
    }
    return changed
}

/// 사각형(pt) 안의 **잉크** 픽셀 수 — 유채색(채널 폭 ≥ 40)이거나 밝은 글자(최대 ≥ 150).
private func cgInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    cgCount(bitmap, rect: rect) { r, g, b in
        let high = max(r, max(g, b)), low = min(r, min(g, b))
        return (high - low) >= 40 || high >= 150
    }
}

/// 사각형(pt) 안의 **말 잉크** — 아주 밝거나(≥ 235) 아주 어두운(≤ 55) 픽셀.
private func cgPieceInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    cgCount(bitmap, rect: rect) { r, g, b in
        max(r, max(g, b)) >= 235 || min(r, min(g, b)) <= 55
    }
}

private func cgCount(_ bitmap: NSBitmapImageRep, rect: CGRect,
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

/// 사각형(pt) 안 평균 색(2x 비트맵 기준). nil 이면 그 자리가 비트맵 밖이다.
private func cgAverage(_ bitmap: NSBitmapImageRep, rect: CGRect) -> (r: Double, g: Double, b: Double)? {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return nil }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return nil }
    var sum = (0, 0, 0)
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            sum.0 += Int(data[o]); sum.1 += Int(data[o + 1]); sum.2 += Int(data[o + 2])
            count += 1
        }
    }
    guard count > 0 else { return nil }
    return (Double(sum.0) / Double(count), Double(sum.1) / Double(count), Double(sum.2) / Double(count))
}

private func cgMaxChannelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
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
