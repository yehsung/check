import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.44 1:1 체스 **화면** 렌더 — 로비 · 대국 · 관전 · 승격 창 · 미니게임 헤더 입구 둘.
//
// 전부 ImageRenderer(scale 2)로 그리고 `CHECK_SNAPSHOT_DIR/chess/` 에 PNG 를 남긴다(사람이 직접 열어 본다 —
// 디자인 작업에서 초록 테스트는 아무것도 증명하지 않는다).
//
// ★ **감지기를 "노란 상자 0" 으로 두지 않는다.** 2026-10-05 실측: `Menu` 와 기본 `Picker` 는 ImageRenderer 에서
//   노란 상자를 **안 그린다** — 아무것도 안 그린다(픽셀 커버리지 0). 그러니 "노란 상자가 없다"는 "화면이 그려졌다"를
//   한 글자도 뜻하지 않는다. 그래서 여기서는 **"그 자리에 잉크가 있는가"**(유채색·밝은 글자 픽셀)로 재고,
//   노랑은 `TextField`·분절 `Picker` 전용 보조 감지기로만 남긴다(체스 화면에는 둘 다 없어야 한다).
//
// ★ **판은 "말 잉크" 로 잰다.** 칸 색과 덮개(마지막 수·선택·체크·도착 점)는 전부 중간 톤이고 **말만 극단**
//   (아주 밝거나 아주 어둡다)이라는 규칙을 `ChessBoardView` 가 지킨다. 그래서 "칸 가운데 50% 상자에 극단 픽셀이
//   있는가" 가 곧 "그 칸에 말이 섰는가" 다 — 초기 배치에서 **정확히 32칸**이 참이어야 한다.
//
// 스토어는 네트워크 없는 `ChessStore()` 를 만들어 상태를 직접 채운다. 공유 인스턴스는 건드리지 않는다.

// MARK: - 픽스처

private func cpUser(_ name: String, _ suffix: Int, working: Bool = true, capable: Bool = true,
                    inMatch: Bool = false, character: String? = "shiba", center: String? = nil) -> ChessUser {
    ChessUser(
        id: "00000000-0000-0000-0000-\(String(format: "%012d", suffix))",
        displayName: name, avatarURL: nil, characterID: character,
        isWorking: working, isCapable: capable, inMatch: inMatch, center: center
    )
}

private let cpMinsu = cpUser("민수", 11, character: "fox")
private let cpJunho = cpUser("준호", 12, character: "squirrel")
private let cpSeoyeon = cpUser("서연", 16, character: "ghost")

private func cpUsers() -> [ChessUser] {
    [
        cpUser("지영", 13, working: false),
        cpMinsu,
        cpUser("태화", 14, inMatch: true),
        cpUser("옛버전사용자", 15, capable: false),
        cpJunho,
        cpSeoyeon,
        cpUser("하늘", 17, working: false),
        cpUser("바다", 18),
        cpUser("가장긴별명열두글자입니다", 19),
        cpUser("산", 20, working: false)
    ]
}

private let cpMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

/// 서버 시계 네 값 — **`turnStartedAt` 을 nil 로 둔다**: 보간이 꺼져 남은 시간이 `now` 와 무관해지고
/// 렌더가 결정적이 된다(흐르는 시계를 재면 같은 화면이 매번 다르게 찍힌다).
private func cpClock(white: Int, black: Int, running: ChessColor? = .white) -> ChessServerClock {
    ChessServerClock(whiteMsLeft: white, blackMsLeft: black, incrementMs: 3_000,
                     turnStartedAt: nil, running: running)
}

private func cpRecord(_ seq: Int, _ color: ChessColor, _ from: String, _ to: String, _ san: String) -> ChessMoveRecord {
    ChessMoveRecord(seq: seq, color: color,
                    move: ChessMove(from: ChessSquare(from)!, to: ChessSquare(to)!),
                    san: san, fen: "x", msLeft: 290_000, msSpent: 3_200)
}

/// 이탈리안 오프닝 6수 뒤(1.e4 e5 2.Nf3 Nc6 3.Bc4 Nf6) — **백 차례**.
/// g8·f1·g1 이 비어 있어 "마지막 수의 출발 칸은 빈 칸" 을 그 자리에서 잴 수 있다.
private let cpMidFEN = "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"

private func cpMidMoves() -> [ChessMoveRecord] {
    [
        cpRecord(1, .white, "e2", "e4", "e4"),
        cpRecord(2, .black, "e7", "e5", "e5"),
        cpRecord(3, .white, "g1", "f3", "Nf3"),
        cpRecord(4, .black, "b8", "c6", "Nc6"),
        cpRecord(5, .white, "f1", "c4", "Bc4"),
        cpRecord(6, .black, "g8", "f6", "Nf6")
    ]
}

@MainActor
private func cpLobbyStore(populated: Bool = true) -> ChessStore {
    let store = ChessStore()
    store.pollStepSeconds = 3_600
    store.hasLoadedLobby = true
    store.hasLoadedRanking = true
    store.spectatorFeaturesEnabled = true
    store.rubyBalance = 42
    store.record = ChessRecord(wins: 7, losses: 3, draws: 1)
    guard populated else { return store }
    store.users = cpUsers()
    store.liveMatches = [
        ChessLiveMatch(id: "live-1", a: cpMinsu, b: cpJunho, stake: .five,
                       startedAt: Date(timeIntervalSince1970: 1_790_000_000)),
        ChessLiveMatch(id: "live-2", a: cpSeoyeon, b: cpUser("바다", 18), stake: .ten,
                       startedAt: Date(timeIntervalSince1970: 1_790_000_100)),
        ChessLiveMatch(id: "live-3", a: cpUser("산", 20), b: cpUser("하늘", 17), stake: .three,
                       startedAt: Date(timeIntervalSince1970: 1_790_000_200))
    ]
    store.incoming = ChessInvite(id: "in-1", peer: cpMinsu, stake: 5,
                                 expiresAt: Date().addingTimeInterval(48))
    store.outgoing = ChessInvite(id: "out-1", peer: cpJunho, stake: 10,
                                expiresAt: Date().addingTimeInterval(31))
    store.ranking = ChessRankingBoard(
        entries: cpUsers().enumerated().map { index, user in
            ChessRankEntry(id: user.id, rank: index + 1, user: user,
                           wins: 12 - index, losses: index, draws: 1, points: 12 - index * 2)
        },
        me: ChessMyRank(rank: 4, wins: 7, losses: 3, draws: 1, points: 4),
        recordSince: Date(timeIntervalSince1970: 1_780_000_000))
    return store
}

@MainActor
private func cpPlayingStore(
    fen: String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
    myColor: ChessColor = .white,
    turn: ChessColor? = .white,
    whiteMs: Int = 300_000,
    blackMs: Int = 300_000,
    moves: [ChessMoveRecord] = [],
    lastMove: ChessMove? = nil,
    inCheck: Bool = false
) -> ChessStore {
    let store = ChessStore()
    store.pollStepSeconds = 3_600
    store.phase = .playing
    store.isWindowVisible = false
    store.rubyBalance = 32
    store.record = ChessRecord(wins: 7, losses: 3, draws: 1)
    let position = ChessPosition(fen: fen)
    store.match = ChessMatchState(
        id: "match-1", stake: 10, myColor: myColor, opponent: cpMinsu, fen: fen,
        position: position, plyCount: moves.count, turn: turn, lastMove: lastMove, moves: moves,
        clock: cpClock(white: whiteMs, black: blackMs, running: turn),
        isInCheck: inCheck,
        legalMoves: (position.map { ChessRules.legalMoves(in: $0) } ?? []),
        isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil,
        drawOfferBy: nil, drawOfferedByMe: false)
    return store
}

@MainActor
private func cpWatchStore(loaded: Bool = true) -> ChessStore {
    let store = cpLobbyStore()
    var watch = ChessSpectateState(id: "live-1", faces: [cpMinsu, cpJunho], stake: 5)
    if loaded {
        watch.black = cpJunho
        watch.white = cpMinsu
        watch.fen = cpMidFEN
        watch.position = ChessPosition(fen: cpMidFEN)
        watch.plyCount = 6
        watch.appliedSeq = 6
        watch.moves = cpMidMoves()
        watch.lastMove = ChessMove(from: ChessSquare("g8")!, to: ChessSquare("f6")!)
        watch.turn = .white
        watch.clock = cpClock(white: 274_000, black: 192_000, running: .white)
        watch.startedAt = Date(timeIntervalSince1970: 1_790_000_000)
    }
    store.spectating = watch
    return store
}

@MainActor
private func cpPanel(_ store: ChessStore, me: ChessPlayerFace = cpMe) -> some View {
    ChessPanel(store: store, me: { me }, clipsOverflowInsteadOfScroll: true)
}

// MARK: - 창 좌표(레이아웃 상수에서만 뽑는다)

private var cpBoardOrigin: CGPoint {
    CGPoint(x: ChessWindowLayout.contentPadding,
            y: ChessWindowLayout.contentPadding + ChessWindowLayout.headerHeight + ChessWindowLayout.headerSpacing)
}

private var cpBoardRect: CGRect {
    CGRect(origin: cpBoardOrigin,
           size: CGSize(width: ChessWindowLayout.boardSide, height: ChessWindowLayout.boardSide))
}

/// 말 잉크를 세는 판 영역 — **테두리 4pt 를 뺀다.** 판의 맨 바깥 픽셀은 창 배경(어두운 그라데이션)과 섞여
/// '아주 어두움' 으로 읽히고, 그 한 줄만으로 2,400px 이 잡혀 "빈 판에 말이 있다" 가 된다(실측).
/// 말은 칸 안쪽으로 7% 들어가 있어(`ChessPieceArt.fillFraction`) 4pt 를 빼도 한 조각도 잃지 않는다.
private var cpBoardInkRect: CGRect { cpBoardRect.insetBy(dx: 4, dy: 4) }

private var cpMatchSideColumn: CGRect {
    CGRect(x: cpBoardOrigin.x + ChessWindowLayout.boardSide + ChessWindowLayout.columnSpacing,
           y: cpBoardOrigin.y, width: ChessWindowLayout.sideColumnWidth, height: ChessWindowLayout.bodyHeight)
}

private var cpLobbyUsersColumn: CGRect {
    CGRect(x: cpBoardOrigin.x, y: cpBoardOrigin.y,
           width: ChessWindowLayout.lobbyUsersWidth, height: ChessWindowLayout.bodyHeight)
}

private var cpLobbyRankColumn: CGRect {
    CGRect(x: cpLobbyUsersColumn.maxX + ChessWindowLayout.columnSpacing, y: cpBoardOrigin.y,
           width: ChessWindowLayout.lobbyRankWidth, height: ChessWindowLayout.bodyHeight)
}

private var cpLobbySideColumn: CGRect {
    CGRect(x: cpLobbyRankColumn.maxX + ChessWindowLayout.columnSpacing, y: cpBoardOrigin.y,
           width: ChessWindowLayout.lobbySideWidth, height: ChessWindowLayout.bodyHeight)
}

/// 두 사람 카드 안 **시계 칸**의 창 좌표. index 0 = 위(상대) · 1 = 아래(나).
/// 카드 HStack 은 가운데 정렬이라 시계는 카드 안에서 위아래로 (84−44)/2 = 20pt 들어간 자리에 선다.
private func cpClockRect(card index: Int) -> CGRect {
    let column = cpMatchSideColumn
    let cardTop = column.minY
        + CGFloat(index) * (ChessWindowLayout.playerCardHeight + ChessWindowLayout.matchSideSpacing)
    return CGRect(
        x: column.maxX - ChessWindowLayout.cardInsetX - ChessWindowLayout.clockWidth,
        y: cardTop + (ChessWindowLayout.playerCardHeight - ChessWindowLayout.clockHeight) / 2,
        width: ChessWindowLayout.clockWidth, height: ChessWindowLayout.clockHeight)
}

/// 그 칸의 **가운데 50% 상자**(창 좌표). 말 잉크를 세는 자리 — 칸 테두리·좌표 글자를 뺀다.
private func cpSquareProbe(_ square: ChessSquare, _ geometry: ChessBoardGeometry) -> CGRect {
    let box = geometry.rect(of: square).offsetBy(dx: cpBoardOrigin.x, dy: cpBoardOrigin.y)
    return box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)
}

// MARK: - ① 세 화면이 실제로 그려지는가

@MainActor
@Test
func theLobbyDrawsInkInAllThreeColumns() throws {
    let full = try cpBitmap(cpPanel(cpLobbyStore()))
    let bare = try cpBitmap(cpPanel(cpLobbyStore(populated: false)))
    cpSave(full, name: "lobby")
    cpSave(bare, name: "lobby-empty")

    let size = ChessWindowLayout.contentSize
    #expect(full.pixelsWide == Int(size.width) * 2 && full.pixelsHigh == Int(size.height) * 2,
            "로비가 \(full.pixelsWide)×\(full.pixelsHigh)px 다 — 고정 창을 넘치거나 모자란다")
    #expect(cpYellowPixels(full) == 0, "로비에 노란 상자가 있다 — TextField·분절 Picker 가 섞였다")

    // ★ 각 열이 **내용을 그린다**. 기준선은 '빈 가게' 다 — 크롬(카드 테두리·제목)은 두 장에서 같으므로
    //   차이는 오직 내용(사람 목록 · 순위 행 · 지금 대결 중 · 받은/보낸 신청)에서 온다.
    //   "노란 상자 0" 만 보면 세 열이 전부 비어 있어도 초록이다(Menu·Picker 는 노란 상자를 안 그린다).
    for (label, rect, minimum) in [("상대 목록", cpLobbyUsersColumn, 4_000),
                                   ("순위", cpLobbyRankColumn, 4_000),
                                   ("오른쪽(전적·대결·신청)", cpLobbySideColumn, 2_000)] {
        let withContent = cpInk(full, rect: rect)
        let withoutContent = cpInk(bare, rect: rect)
        print("[로비] \(label): 잉크 \(withContent)px (빈 가게 \(withoutContent)px)")
        #expect(withContent > withoutContent + minimum,
                "\(label) 열이 내용을 안 그린다(잉크 \(withContent) vs 빈 가게 \(withoutContent))")
    }

    // 세 열은 **서로 다른 것**을 그린다(한 열을 세 번 그린 화면이 아니다).
    #expect(cpMaxChannelDifference(full, bare, rect: cpLobbyUsersColumn) > 60)
    #expect(cpMaxChannelDifference(full, bare, rect: cpLobbyRankColumn) > 60)
    #expect(cpMaxChannelDifference(full, bare, rect: cpLobbySideColumn) > 60)
}

@MainActor
@Test
func thePlayingScreenDrawsTheBoardAndTheSideColumn() throws {
    let store = cpPlayingStore(fen: cpMidFEN, myColor: .white, turn: .white,
                               whiteMs: 274_000, blackMs: 192_000, moves: cpMidMoves(),
                               lastMove: ChessMove(from: ChessSquare("g8")!, to: ChessSquare("f6")!))
    let bitmap = try cpBitmap(cpPanel(store))
    cpSave(bitmap, name: "playing")
    #expect(cpYellowPixels(bitmap) == 0, "대국 화면에 노란 상자가 있다")

    // 판 자리에 말 잉크가 넉넉히 있다(판이 통째로 안 그려지면 0 이다).
    #expect(cpPieceInk(bitmap, rect: cpBoardInkRect) > 20_000,
            "판에 말 잉크가 \(cpPieceInk(bitmap, rect: cpBoardInkRect))px 뿐이다 — 판이 안 그려졌다")
    // 오른쪽 열(두 카드·판돈·상태·기보·동작 줄)이 비어 있지 않다. 기준선은 **판이 없는 로비** 가 아니라
    // **기보가 비어 있는 같은 대국**이다 — 기보 칸만 달라지므로 차이가 그 칸에서 온다.
    let noMoves = try cpBitmap(cpPanel(cpPlayingStore(fen: cpMidFEN, whiteMs: 274_000, blackMs: 192_000)))
    #expect(cpMaxChannelDifference(bitmap, noMoves, rect: cpMatchSideColumn) > 60,
            "기보가 쌓였는데 오른쪽 열이 한 픽셀도 안 바뀐다 — 기보 칸이 안 그려졌다")
    #expect(cpInk(bitmap, rect: cpMatchSideColumn) > 3_000,
            "오른쪽 열에 잉크가 \(cpInk(bitmap, rect: cpMatchSideColumn))px 뿐이다")

    // 마지막 수 덮개는 **중간 톤**이어야 한다(말 감지기를 멀게 하지 않는다 — 규칙 ★).
    let g = ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: .white)
    let emptyLast = try #require(ChessSquare("g8"))      // 마지막 수의 출발 칸 = 비어 있다
    #expect(cpPieceInk(bitmap, rect: cpSquareProbe(emptyLast, g)) == 0,
            "마지막 수 덮개가 '말 잉크' 로 세어진다 — 32개 단언이 쓸모없어진다")
    // 그래도 덮개는 **보인다**(픽셀이 바뀐다).
    let noHighlight = try cpBitmap(cpPanel(cpPlayingStore(fen: cpMidFEN, whiteMs: 274_000, blackMs: 192_000)))
    #expect(cpMaxChannelDifference(bitmap, noHighlight, rect: cpSquareProbe(emptyLast, g)) > 15,
            "마지막 수 덮개가 아무 픽셀도 안 바꾼다")
}

@MainActor
@Test
func theSpectateScreenStandsInTheLobbySlotAndDrawsTheBoard() throws {
    let watching = try cpBitmap(cpPanel(cpWatchStore()))
    let lobby = try cpBitmap(cpPanel(cpLobbyStore()))
    let loading = try cpBitmap(cpPanel(cpWatchStore(loaded: false)))
    cpSave(watching, name: "spectate")
    cpSave(loading, name: "spectate-loading")
    #expect(cpYellowPixels(watching) == 0, "관전 화면에 노란 상자가 있다")

    // 관전은 로비 자리에 선다 — 같은 phase(.lobby) 인데 화면이 통째로 다르다.
    #expect(cpMaxChannelDifference(watching, lobby, rect: cpBoardRect) > 60,
            "관전이 로비 자리에 안 선다 — 판이 안 그려졌다")
    #expect(cpPieceInk(watching, rect: cpBoardInkRect) > 20_000,
            "관전 판에 말이 안 그려졌다(말 잉크 \(cpPieceInk(watching, rect: cpBoardInkRect))px)")
    // 첫 응답 전(흑·백 모름)과 받은 뒤가 다르다 — 로딩 화면이 실제로 다른 그림이다.
    #expect(cpMaxChannelDifference(watching, loading, rect: cpMatchSideColumn) > 60,
            "관전 첫 응답 전과 뒤가 같은 그림이다 — 이름·색·기보가 안 그려졌다")
    #expect(cpPieceInk(loading, rect: cpBoardInkRect) == 0,
            "판을 아직 모르는데 말이 그려졌다")
}

// MARK: - ② 판이 실제로 말을 그리는가 (정확히 32칸)

@MainActor
@Test
func theInitialPositionDrawsExactlyThirtyTwoPiecesAndNothingOnEmptySquares() throws {
    let store = cpPlayingStore()                           // 초기 배치 · 백 차례 · 선택 없음
    let bitmap = try cpBitmap(cpPanel(store))
    cpSave(bitmap, name: "playing-initial")

    let g = ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: .white)
    let position = ChessPosition.standard
    var inked: Set<String> = [], blank: Set<String> = []
    for index in 0..<64 {
        let square = try #require(ChessSquare(index: index))
        let ink = cpPieceInk(bitmap, rect: cpSquareProbe(square, g))
        if ink > 0 { inked.insert(square.notation) } else { blank.insert(square.notation) }
    }
    let occupied = Set(position.pieces.map { $0.square.notation })
    #expect(occupied.count == 32, "전제: 초기 배치는 32칸이다")
    let extra = inked.subtracting(occupied).sorted(), missing = occupied.subtracting(inked).sorted()
    #expect(inked == occupied,
            "말이 선 칸이 어긋난다 — 잉크만 있는 칸 \(extra) · 말인데 잉크 없는 칸 \(missing)")
    #expect(blank.count == 32)

    // ★ 기준선이 갈린다: **빈 판**에는 어느 칸에도 말 잉크가 없다. 감지기가 칸 색·좌표 글자·테두리를
    //   잉크로 세고 있으면 여기서 빨개진다(그 상태로는 위 32칸 단언이 아무것도 안 잰다).
    let emptyBoard = try cpBitmap(
        ChessBoardView(position: ChessPosition.empty,
                       geometry: g).frame(width: g.side, height: g.side))
    for index in 0..<64 {
        let square = try #require(ChessSquare(index: index))
        let box = g.rect(of: square)
        let probe = box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)
        #expect(cpPieceInk(emptyBoard, rect: probe) == 0,
                "빈 판의 \(square.notation) 에 말 잉크가 \(cpPieceInk(emptyBoard, rect: probe))px 있다")
    }

    // 흑으로 두면 판이 뒤집힌다 — a1 자리에 흑 말이 아니라 **백 룩**이 선다(방향 배선이 그림까지 간다).
    let asBlack = try cpBitmap(cpPanel(cpPlayingStore(myColor: .black, turn: .white)))
    cpSave(asBlack, name: "playing-initial-black")
    let flipped = ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: .black)
    let a1 = try #require(ChessSquare("a1"))
    #expect(cpPieceInk(asBlack, rect: cpSquareProbe(a1, flipped)) > 0, "뒤집은 판에서 a1 의 룩이 사라졌다")
    #expect(cpMaxChannelDifference(bitmap, asBlack, rect: cpBoardRect) > 60,
            "흑으로 두는데 판이 그대로다 — orientation 이 그림에 안 간다")
}

/// 여섯 말이 **여섯 가지 모양**으로 그려진다. 한 가지로 떨어지면(switch 가 한 갈래로 새면) 판에서
/// 폰과 비숍을 못 가린다 — 위 32칸 단언은 그래도 초록이다(잉크가 있기만 하면 되므로).
@MainActor
@Test
func allSixPieceKindsDrawDistinctShapes() throws {
    var bitmaps: [ChessPieceKind: NSBitmapImageRep] = [:]
    for kind in ChessPieceKind.allCases {
        let bitmap = try cpBitmap(ChessPieceTile(kind: kind, color: .white))
        bitmaps[kind] = bitmap
        cpSave(bitmap, name: "piece-\(kind.rawValue)")
        let box = CGRect(x: 0, y: 0, width: ChessWindowLayout.promotionTileSide,
                         height: ChessWindowLayout.promotionTileSide)
        #expect(cpPieceInk(bitmap, rect: box.insetBy(dx: box.width * 0.25, dy: box.height * 0.25)) > 0,
                "\(kind.rawValue) 가 칸 가운데를 안 덮는다 — 판에서 '말이 없다' 와 구분되지 않는다")
    }
    let kinds = ChessPieceKind.allCases
    for (i, lhs) in kinds.enumerated() {
        for rhs in kinds[(i + 1)...] {
            let difference = cpMaxChannelDifference(bitmaps[lhs]!, bitmaps[rhs]!,
                                                    rect: CGRect(x: 0, y: 0,
                                                                 width: ChessWindowLayout.promotionTileSide,
                                                                 height: ChessWindowLayout.promotionTileSide))
            #expect(difference > 60, "\(lhs.rawValue) 와 \(rhs.rawValue) 가 같은 모양으로 그려진다")
        }
    }
    // 흑·백은 같은 모양이지만 **다른 색**이다(색을 안 가르면 판에서 누구 말인지 모른다).
    let whiteKing = try cpBitmap(ChessPieceTile(kind: .king, color: .white))
    let blackKing = try cpBitmap(ChessPieceTile(kind: .king, color: .black))
    let tile = CGRect(x: 0, y: 0, width: ChessWindowLayout.promotionTileSide,
                      height: ChessWindowLayout.promotionTileSide)
    #expect(cpMaxChannelDifference(whiteKing, blackKing, rect: tile) > 100, "흑 킹과 백 킹이 같은 색이다")
}

// MARK: - ③ 시계 둘이 서로 다른 값을 보인다

/// 시계가 **둘**이고 각자 자기 색의 남은 시간을 읽는다.
///
/// 없으면: 시계를 하나만 그려도, 두 시계가 같은 값을 읽어도 초록이다. 그 화면에서 사용자는 상대가 1분
/// 남았는데 5분으로 보고 느긋하게 둔다.
///
/// 재는 법(기준선이 갈리게): 같은 화면을 **흑만 줄여서** 한 장, **백만 줄여서** 한 장 더 그린다.
/// 흑을 줄이면 **위 카드 시계만**, 백을 줄이면 **아래 카드 시계만** 바뀌어야 한다 —
/// 한쪽이 안 그려졌거나 둘이 같은 값을 읽으면 네 단언 중 하나가 깨진다.
@MainActor
@Test
func theTwoClocksShowTheirOwnSideAndDifferFromEachOther() throws {
    let both = try cpBitmap(cpPanel(cpPlayingStore(whiteMs: 300_000, blackMs: 300_000)))
    let blackLow = try cpBitmap(cpPanel(cpPlayingStore(whiteMs: 300_000, blackMs: 123_000)))
    let whiteLow = try cpBitmap(cpPanel(cpPlayingStore(whiteMs: 123_000, blackMs: 300_000)))
    cpSave(blackLow, name: "playing-clocks")

    // 내가 백이므로 위 카드(index 0)가 **상대 = 흑**, 아래 카드(index 1)가 **나 = 백**이다.
    let opponentClock = cpClockRect(card: 0)
    let myClock = cpClockRect(card: 1)

    #expect(cpMaxChannelDifference(both, blackLow, rect: opponentClock) > 60,
            "흑 시간을 줄였는데 **상대 시계**가 안 바뀐다 — 위 시계가 흑을 안 읽는다")
    #expect(cpMaxChannelDifference(both, blackLow, rect: myClock) <= 2,
            "흑 시간을 줄였는데 **내 시계**가 바뀐다 — 두 시계가 같은 값을 읽는다")
    #expect(cpMaxChannelDifference(both, whiteLow, rect: myClock) > 60,
            "백 시간을 줄였는데 **내 시계**가 안 바뀐다 — 아래 시계가 백을 안 읽는다")
    #expect(cpMaxChannelDifference(both, whiteLow, rect: opponentClock) <= 2,
            "백 시간을 줄였는데 **상대 시계**가 바뀐다 — 두 시계가 같은 값을 읽는다")

    // 두 시계 칸에 실제로 잉크(숫자)가 있다 — 자리는 있는데 글자가 없는 경우를 가른다.
    #expect(cpInk(blackLow, rect: opponentClock) > 120, "상대 시계 칸이 비어 있다")
    #expect(cpInk(blackLow, rect: myClock) > 120, "내 시계 칸이 비어 있다")

    // 글자 산식도 값으로 되묻는다(픽셀만 보면 "무엇이 쓰였는가"를 모른다).
    #expect(ChessText.clock(300) == "5:00")
    #expect(ChessText.clock(123) == "2:03")
    #expect(ChessText.clock(9.4) == "9.4", "마지막 10초는 소수 한 자리로 — 1초 단위로는 안 읽힌다")
    #expect(ChessText.clock(0) == "0.0")
    #expect(ChessText.clock(-5) == "0.0", "음수가 화면에 샌다")

    // 관전 화면의 시계도 둘이다(같은 부품 · 서버가 말한 색으로).
    let watch = try cpBitmap(cpPanel(cpWatchStore()))
    #expect(cpInk(watch, rect: cpClockRect(card: 0)) > 120, "관전 흑 시계가 비어 있다")
    #expect(cpInk(watch, rect: cpClockRect(card: 1)) > 120, "관전 백 시계가 비어 있다")
}

// MARK: - ④ 승격 창

@MainActor
@Test
func thePromotionSheetCoversTheBoardAndOffersFourPieces() throws {
    let store = cpPlayingStore(fen: "8/4P3/8/8/8/8/8/K6k w - - 0 1")
    store.promotion = ChessPromotionPrompt(from: ChessSquare("e7")!, to: ChessSquare("e8")!)
    let open = try cpBitmap(cpPanel(store))
    let closed = try cpBitmap(cpPanel(cpPlayingStore(fen: "8/4P3/8/8/8/8/8/K6k w - - 0 1")))
    cpSave(open, name: "playing-promotion")
    #expect(cpYellowPixels(open) == 0, "승격 창에 노란 상자가 있다")

    // 덮개가 뒤를 어둡게 덮는다(판 자리 픽셀이 바뀐다).
    #expect(cpMaxChannelDifference(open, closed, rect: cpBoardRect) > 60, "승격 창을 열었는데 판이 그대로다")
    #expect(ChessPieceKind.promotionChoices == [.queen, .rook, .bishop, .knight],
            "고를 수 있는 말이 넷이 아니다")
    // 네 칸은 판과 **같은 칸 색**(`lightSquare`)으로 깔린다. 그 색은 체스 화면에서 판과 승격 칸에만 있으므로
    // "그 색 픽셀이 어디에 있는가" 가 곧 "판이 보이는가 / 승격 칸이 섰는가" 다.
    // (`cpPieceInk` 를 여기 쓰면 안 된다 — 판 밖의 어두운 배경이 전부 '극단' 으로 읽혀 아무것도 안 가른다.)
    let band = CGRect(x: (ChessWindowLayout.contentSize.width - ChessWindowLayout.promotionPromptWidth) / 2,
                      y: ChessWindowLayout.contentSize.height / 2 - ChessWindowLayout.promotionTileSide,
                      width: ChessWindowLayout.promotionPromptWidth,
                      height: ChessWindowLayout.promotionTileSide * 2)
    // 띠와 겹치지 않는 판 왼쪽(x 20~400) — 덮개가 판을 **덮었는가**를 재는 자리다.
    let boardLeft = CGRect(x: cpBoardRect.minX, y: cpBoardRect.minY, width: 380, height: cpBoardRect.height)
    #expect(band.minX > boardLeft.maxX, "전제: 승격 띠와 판 왼쪽이 겹치지 않는다")
    let tiles = cpBoardTone(open, rect: band)
    print("[승격] 가운데 띠 칸 색 \(tiles)px · 판 왼쪽 \(cpBoardTone(open, rect: boardLeft))px"
          + " (창을 안 열면 판 왼쪽 \(cpBoardTone(closed, rect: boardLeft))px)")
    #expect(tiles > 20_000, "승격 창에 말 칸 넷이 \(tiles)px 뿐이다 — 글자만 있고 칸이 없다")
    #expect(cpBoardTone(closed, rect: boardLeft) > 50_000, "전제: 창을 안 열면 판의 밝은 칸이 보인다")
    #expect(cpBoardTone(open, rect: boardLeft) == 0, "승격 창이 판을 안 덮는다 — 뒤가 그대로 보인다")
    // 네 칸은 말 넷을 **서로 다르게** 그린다(`allSixPieceKindsDrawDistinctShapes` 가 모양을, 여기서는 자리를 본다).
    let third = band.width / 4
    for index in 0..<4 {
        let slot = CGRect(x: band.minX + third * CGFloat(index), y: band.minY, width: third, height: band.height)
        #expect(cpBoardTone(open, rect: slot) > 3_000, "승격 창 \(index + 1)번째 자리가 비었다")
    }
}

// MARK: - ⑤ 미니게임 헤더 입구 둘

@MainActor
@Test
func theMiniGameHeaderShowsBothDuelEntries() throws {
    defer { MiniGameSpaceKey.remove() }
    let now = Date(timeIntervalSince1970: 1_784_000_000)
    let store = cpTeamStore(now: now)
    store.isMiniGamePanelVisible = true
    store.miniGameBoardLoaded = true
    let idle = try cpBitmap(
        CheckMiniGameWindowView(store: store, clipsOverflowInsteadOfScroll: true)
            .background(CheckTheme.background))
    cpSave(idle, name: "minigame-header-entries")
    #expect(cpYellowPixels(idle) == 0)

    let band = CGRect(x: MiniGameWindowLayout.contentPadding, y: MiniGameWindowLayout.contentPadding,
                      width: MiniGameWindowLayout.canvasSize.width, height: MiniGameWindowLayout.headerHeight)
    let green = cpGreenBounds(idle, rect: band)
    print("[입구] 헤더 초록 \(green.count)px · 상자 \(green.box)")
    #expect(green.count > 60, "미니게임 헤더에 대결 입구가 안 보인다(초록 \(green.count)px)")
    // 입구가 **둘**이라 초록 잉크가 두 캡슐에 걸쳐 넓게 퍼진다(하나뿐이면 26pt 캡슐 한 폭 안이다).
    #expect(green.box.width > 40,
            "초록 잉크가 \(green.box.width)pt 폭에만 있다 — 입구가 하나뿐이다")
    #expect(green.box.maxX <= band.maxX, "입구가 게임 열(344pt) 밖으로 넘친다(maxX \(green.box.maxX)pt)")

    // ★ 기준선이 갈린다: 판이 도는 중에는 입구 자리에 [일시정지](주황)가 서므로 초록이 거의 사라진다.
    //   이 대비가 없으면 "초록이 있다"가 헤더의 다른 무엇(칩 테두리 등)을 세고 있어도 초록이다.
    //   머리글 뷰를 단독으로 그린다 — 창 화면의 `isPlaying` 은 잎 뷰의 @State 라 밖에서 못 채운다.
    let headerBox = CGRect(x: 0, y: 0, width: 400, height: MiniGameWindowLayout.headerHeight)
    let idleHeader = try cpBitmap(
        MiniGameGameHeader(selected: .flappy, isPlaying: false, isFrozen: false,
                           onSelect: { _ in }, onPause: {}, onGomoku: {}, onChess: {})
            .background(CheckTheme.background))
    let busyHeader = try cpBitmap(
        MiniGameGameHeader(selected: .flappy, isPlaying: true, isFrozen: false,
                           onSelect: { _ in }, onPause: {}, onGomoku: {}, onChess: {})
            .background(CheckTheme.background))
    let idleGreen = cpGreenBounds(idleHeader, rect: headerBox).count
    let busyGreen = cpGreenBounds(busyHeader, rect: headerBox).count
    print("[입구] 머리글 초록: 입구 둘 \(idleGreen)px · 판이 도는 중 \(busyGreen)px")
    #expect(idleGreen > 60, "머리글 단독에서 입구의 초록이 \(idleGreen)px 뿐이다")
    #expect(busyGreen * 2 < idleGreen,
            "판이 도는 중에도 같은 양의 초록이 있다(\(busyGreen) vs \(idleGreen)) — 세고 있는 초록이 입구가 아니다")

    // 입구 둘은 **서로 다른 아이콘**을 그린다(같으면 어느 문이 어느 게임인지 모른다).
    let gomoku = try cpBitmap(MiniGameGomokuEntryButton(showsTitle: false) {})
    let chess = try cpBitmap(MiniGameChessEntryButton(showsTitle: false) {})
    cpSave(chess, name: "minigame-entry-chess")
    #expect(abs(gomoku.pixelsWide - chess.pixelsWide) < 20, "두 입구 캡슐의 폭이 크게 다르다")
    let icon = CGRect(x: 0, y: 0,
                      width: Double(min(gomoku.pixelsWide, chess.pixelsWide)) / 2,
                      height: Double(min(gomoku.pixelsHigh, chess.pixelsHigh)) / 2)
    #expect(cpMaxChannelDifference(gomoku, chess, rect: icon) > 60, "두 입구가 같은 아이콘을 그린다")
    #expect(Double(chess.pixelsWide) / 2 <= 40,
            "아이콘 전용 체스 입구가 \(Double(chess.pixelsWide) / 2)pt 다 — 344pt 예산에서 이름 달린 폭이다")

    // ★ 심볼 이름이 이 맥에서 실제로 풀린다. 없으면 `Image(systemName:)` 는 **아무것도 안 그린다**
    //   (두부도 안 뜬다) — 자리만 비어 조용히 고장난다.
    #expect(NSImage(systemSymbolName: ChessEntryIcon.resolved, accessibilityDescription: nil) != nil,
            "체스 아이콘 이름(\(ChessEntryIcon.resolved))이 이 맥에서 안 풀린다")
    print("[입구] 체스 아이콘 = \(ChessEntryIcon.resolved)")
}

// MARK: - 헬퍼

private enum CPRenderError: Error { case failed }

@MainActor
private func cpBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw CPRenderError.failed }
    return bitmap
}

private func cpSave(_ bitmap: NSBitmapImageRep, name: String) {
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "chess")
}

/// `TextField`·분절 `Picker` 가 섞였을 때 ImageRenderer 가 그리는 노란 상자(255,204,0)의 픽셀 수.
/// **이것만으로는 아무것도 증명되지 않는다**(`Menu`·기본 `Picker` 는 아무것도 안 그린다 — 머리 주석 ★).
private func cpYellowPixels(_ bitmap: NSBitmapImageRep) -> Int {
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

/// 사각형(pt) 안의 **잉크** 픽셀 수 — 유채색(채널 폭 ≥ 40)이거나 밝은 글자(최대 ≥ 150).
///
/// 어두운 배경·카드 바닥·테두리는 둘 다 아니다(배경 (26~36,28~38,38~51) 채널 폭 ≤ 15 · 최대 ≤ 57 ·
/// 카드 (40,43,57) · 테두리 ≈ (70,72,84)). 그러니 이 수가 0 에 가까우면 **그 자리가 비어 있다**.
private func cpInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    cpCount(bitmap, rect: rect) { r, g, b in
        let high = max(r, max(g, b)), low = min(r, min(g, b))
        return (high - low) >= 40 || high >= 150
    }
}

/// 사각형(pt) 안의 **말 잉크** 픽셀 수 — 아주 밝거나(최대 ≥ 235) 아주 어두운(최소 ≤ 55) 픽셀.
/// `ChessBoardView` 가 "칸 색·덮개는 중간 톤, 말만 극단" 을 지키므로 이 수가 곧 "그 칸에 말이 섰는가" 다.
private func cpPieceInk(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    cpCount(bitmap, rect: rect) { r, g, b in
        max(r, max(g, b)) >= 235 || min(r, min(g, b)) <= 55
    }
}

/// 사각형(pt) 안 초록 잉크(`CheckTheme.working` 글자·아이콘)의 픽셀 수와 그 잉크를 감싸는 상자(pt).
private func cpGreenBounds(_ bitmap: NSBitmapImageRep, rect: CGRect) -> (count: Int, box: CGRect) {
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
            // ★ `g > r + 80 && g > 150` 만으로는 **accent(84,171,255)도 걸린다**(g−r = 87) — 그러면 고른 종류 칩의
            //   파란 글자가 '입구의 초록' 으로 세어져 입구를 지워도 수가 거의 안 줄어든다(실측 777 vs 1325).
            //   `g > b + 30` 을 더해 working(89,224,161 — g−b = 63)만 남긴다.
            if g > r + 80 && g > b + 30 && g > 150 {
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

/// 사각형(pt) 안에서 **판 밝은 칸 색**(`ChessBoardView.lightSquare` = 204,184,153)에 가까운 픽셀 수.
/// 이 색은 체스 화면에서 판과 승격 칸에만 있다 — 덮개(scrim 0.93)가 깔리면 (64,65,80) 쯤으로 내려가 걸리지 않는다.
private func cpBoardTone(_ bitmap: NSBitmapImageRep, rect: CGRect) -> Int {
    cpCount(bitmap, rect: rect) { r, g, b in
        abs(r - 204) <= 14 && abs(g - 184) <= 14 && abs(b - 153) <= 14
    }
}

private func cpCount(_ bitmap: NSBitmapImageRep, rect: CGRect,
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

/// 사각형(pt) 안에서 두 비트맵의 채널 최대 차(0 이면 한 바이트도 다르지 않다).
private func cpMaxChannelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
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
private func cpTeamStore(now: Date) -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: cpDefaults("check-v0344-chess-render-tests"),
        tokenUsage: cpInertTokenStore()
    )
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil,
                                    userID: "00000000-0000-0000-0000-000000000002")
    store.displayNow = now
    store.teamMembers = [
        TeamMemberStatus(id: "00000000-0000-0000-0000-000000000002", name: "영식", status: .working, updatedAt: nil,
                         currentSessionStartedAt: now.addingTimeInterval(-3_661), weeklyDurationSeconds: 14_400,
                         avatarURL: CheckMascotAssets.url(for: .neutral)),
        TeamMemberStatus(id: "00000000-0000-0000-0000-000000000003", name: "민수", status: .working,
                         updatedAt: now.addingTimeInterval(-420), currentSessionStartedAt: now.addingTimeInterval(-7_620),
                         weeklyDurationSeconds: 28_800, lastSeenAt: now.addingTimeInterval(-420))
    ]
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    return store
}

/// 고정 이름 스위트. 그 이름 그대로는 ~/Library/Preferences 에 항목을 만들므로 $TMPDIR 절대 경로로 옮긴다.
private func cpDefaults(_ suiteName: String) -> UserDefaults {
    let path = CheckTestScratch.suitePath(named: suiteName)
    let defaults = UserDefaults(suiteName: path)!
    defaults.removePersistentDomain(forName: path)
    return defaults
}

@MainActor
private func cpInertTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    return TokenUsageStore(
        defaults: cpDefaults("check-v0344-chess-render-token-tests"),
        homeDirectory: tmp.appendingPathComponent("check-v0344-chess-token-home", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-v0344-chess-token-cache.json", isDirectory: false)
    )
}
