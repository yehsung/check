import Foundation
import Testing
@testable import CheckCore

// 체스 규칙 — **수 세기(perft)가 못 잡는 자리**를 구체 기보로 못 박는다.
//
// 수 세기는 합법 수 생성만 잰다. 그래서 다음은 깊이를 아무리 늘려도 드러나지 않는다:
//  · 50수 규칙(카운터가 폰 이동·잡기에서 0 으로 돌아가는가, 100 반수에 무승부인가)
//  · 3회 동형 반복(무엇을 '같은 국면'으로 보는가)
//  · 불충분 기물(네 경우만인가)
//  · 표기(FEN · UCI · SAN 과 동형 중복 해소)
//  · 수가 판에 남기는 것(앙파상의 잡힌 칸, 캐슬링의 룩, 승격한 말)
// 그리고 **왕 안전 지름길**(ChessEngine.needsKingSafetyCheck)이 맞는지는 전수 검사와 나란히 재서 못 박는다 —
// 지름길이 틀리면 수 세기도 틀리지만, 어디가 틀렸는지는 전수 대조가 더 빨리 말해 준다.
//
// 단언은 **모양이 아니라 결과**를 잰다: "앙파상 함수가 있다"가 아니라 "이 수순 다음 b5c6 은 불법이다".

// MARK: - 도우미

private func chessPosition(_ fen: String) throws -> ChessPosition {
    try #require(ChessPosition(fen: fen), "FEN 을 못 읽었다: \(fen)")
}

/// 합법 수의 UCI 집합(있다/없다를 재는 자리).
private func chessMoveSet(_ position: ChessPosition) -> Set<String> {
    Set(ChessRules.legalMoves(in: position).map(\.uci))
}

/// UCI 수순을 적용하고 거쳐 간 국면 전부를 낸다(시작 국면 포함). 불법 수가 끼면 실패.
private func chessTrail(_ line: [String], from position: ChessPosition = .standard) throws -> [ChessPosition] {
    try #require(ChessRules.replay(uciLine: line, from: position), "수순에 불법 수가 있다: \(line)")
}

private func chessFinal(_ line: [String], from position: ChessPosition = .standard) throws -> ChessPosition {
    try #require(try chessTrail(line, from: position).last)
}

/// 지름길을 **쓰지 않는** 합법 수 생성 — 유사 합법 수를 모두 두고 왕이 공격받는지 본다.
/// 이 전수 검사가 `ChessRules.legalMoves` 의 기준선이다(둘이 같은 코드를 타면 그 테스트는 영원히 초록이다).
private func chessBruteForceLegalMoves(_ position: ChessPosition) throws -> [String] {
    var engine = try #require(ChessEngine(position: position))
    var pseudo: [ChessRawMove] = []
    engine.generate(into: &pseudo)
    var legal: [String] = []
    for move in pseudo {
        let moverIndex = Int(engine.side)
        let undo = engine.make(move)
        if !engine.isAttacked(engine.kings[moverIndex], byBlack: moverIndex == 0) { legal.append(move.move.uci) }
        engine.unmake(undo)
    }
    return legal.sorted()
}

@Suite("체스 규칙")
struct ChessRulesTests {

    // MARK: - FEN 양방향

    @Test("FEN 왕복 — 읽어서 다시 적으면 글자 그대로 같다")
    func fenRoundTripsExactly() throws {
        let fens = try chessPerftFixture().all.map(\.fen) + [
            "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2",
            "8/8/8/8/8/5K2/8/4k2R b - - 13 77",
            "4k3/8/8/8/8/8/8/4K3 w - - 0 1"
        ]
        for fen in fens {
            let position = try chessPosition(fen)
            #expect(position.fen == fen)
        }

        // 판을 읽는 도우미도 같은 국면을 말한다(화면이 이걸로 그린다).
        #expect(ChessPosition.standard.kingSquare(of: .white) == ChessSquare("e1"))
        #expect(ChessPosition.standard.kingSquare(of: .black) == ChessSquare("e8"))
        #expect(ChessPosition.standard.pieces.count == 32)
        #expect(ChessPosition.standard.pieces.first?.square == ChessSquare("a1"))
        #expect(ChessPosition.standard.pieces.first?.piece == ChessPiece(.white, .rook))
        #expect(ChessPosition.standard[ChessSquare("d8")!] == ChessPiece(.black, .queen))
        #expect(ChessPosition.standard.boardFEN == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR")
        #expect(ChessPosition.standard.asciiBoard.hasSuffix("  a b c d e f g h"))
    }

    @Test("FEN 칸 넷만 와도 읽는다 — 반수 0, 수 번호 1")
    func fenAcceptsFourFields() throws {
        let position = try chessPosition("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -")
        #expect(position.halfmoveClock == 0)
        #expect(position.fullmoveNumber == 1)
        #expect(position == .standard)
    }

    @Test("FEN 이 거절하는 것 — 체스판으로 성립하지 않는 국면")
    func fenRejectsImpossiblePositions() {
        // 기준선: 아래 글자열들과 '한 군데만' 다른 성립하는 국면은 읽힌다.
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w Q - 0 1") != nil)

        #expect(ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w") == nil, "칸이 모자라다")
        #expect(ChessPosition(fen: "8/8/8/8/8/8/8/8 w - - 0 1") == nil, "왕이 없다")
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/4KK2 w - - 0 1") == nil, "백 왕이 둘이다")
        #expect(ChessPosition(fen: "rnbqkbnrr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1") == nil, "한 줄이 9칸")
        #expect(ChessPosition(fen: "4k2P/8/8/8/8/8/8/4K3 w - - 0 1") == nil, "끝 줄에 폰 — 승격을 빼먹은 국면")
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/4K3 w K - 0 1") == nil, "룩 없는 캐슬링 권리")
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w K - 0 1") == nil, "룩이 반대쪽 귀퉁이에 있다")
        #expect(ChessPosition(fen: "4R3/4k3/8/8/8/8/8/4K3 w - - 0 1") == nil, "차례가 아닌 쪽이 체크")
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/4K3 w - e6 0 1") == nil, "앙파상 칸인데 잡힐 폰이 없다")
        #expect(ChessPosition(fen: "4k3/8/8/4p3/8/8/8/4K3 w - e3 0 1") == nil, "앙파상 칸이 차례와 맞지 않는 줄")
        #expect(ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1") == nil, "차례 글자가 아니다")
        #expect(ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KKqq - 0 1") == nil, "권리 글자 중복")
    }

    @Test("칸 표기는 소문자 정규형만 — 정규화를 두 군데 두지 않는다")
    func squareNotationIsStrict() {
        #expect(ChessSquare("e4")?.index == 28)
        #expect(ChessSquare("a1")?.index == 0)
        #expect(ChessSquare("h8")?.index == 63)
        #expect(ChessSquare("E4") == nil)
        #expect(ChessSquare("e9") == nil)
        #expect(ChessSquare("i4") == nil)
        #expect(ChessSquare(" e4") == nil)
        #expect(ChessSquare("e4 ") == nil)
        #expect(ChessSquare(index: 28)?.notation == "e4")
        // 칸 색 — 불충분 기물이 이 값을 쓴다.
        #expect(ChessSquare("c1")?.isLightSquare == false)
        #expect(ChessSquare("f8")?.isLightSquare == false)
        #expect(ChessSquare("c8")?.isLightSquare == true)
    }

    // MARK: - UCI

    @Test("UCI 왕복과 거절")
    func uciRoundTripsAndRejects() throws {
        #expect(ChessMove(uci: "e2e4")?.uci == "e2e4")
        #expect(ChessMove(uci: "e7e8q")?.uci == "e7e8q")
        #expect(ChessMove(uci: "e7e8n")?.promotion == .knight)
        #expect(ChessMove(uci: "e2e9") == nil)
        #expect(ChessMove(uci: "e2e") == nil)
        #expect(ChessMove(uci: "e2e4q5") == nil)
        #expect(ChessMove(uci: "e7e8k") == nil, "킹으로는 승격할 수 없다")
        #expect(ChessMove(uci: "e7e8p") == nil, "폰으로는 승격할 수 없다")
        #expect(ChessMove(uci: "e7e8Q") == nil, "승격 글자는 소문자다")
        #expect(ChessMove(uci: "E2E4") == nil)
    }

    // MARK: - SAN

    @Test("SAN 기본형 — 폰·말·잡기·캐슬링·승격·체크·메이트")
    func sanCoversEveryShape() throws {
        let start = ChessPosition.standard
        #expect(ChessRules.san(for: ChessMove(uci: "e2e4")!, in: start) == "e4")
        #expect(ChessRules.san(for: ChessMove(uci: "g1f3")!, in: start) == "Nf3")

        // 폰이 잡으면 출발 파일을 적는다.
        let afterD5 = try chessFinal(["e2e4", "d7d5"])
        #expect(ChessRules.san(for: ChessMove(uci: "e4d5")!, in: afterD5) == "exd5")

        let castles = try chessPosition("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        #expect(ChessRules.san(for: ChessMove(uci: "e1g1")!, in: castles) == "O-O")
        #expect(ChessRules.san(for: ChessMove(uci: "e1c1")!, in: castles) == "O-O-O")

        let promotion = try chessPosition("1n6/P7/8/8/8/8/8/K6k w - - 0 1")
        #expect(ChessRules.san(for: ChessMove(uci: "a7a8n")!, in: promotion) == "a8=N")
        #expect(ChessRules.san(for: ChessMove(uci: "a7b8q")!, in: promotion) == "axb8=Q")

        let checkable = try chessPosition("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1")
        #expect(ChessRules.san(for: ChessMove(uci: "a1a8")!, in: checkable) == "Ra8+")

        let matable = try chessPosition("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
        #expect(ChessRules.san(for: ChessMove(uci: "a1a8")!, in: matable) == "Ra8#")

        // 불법 수에는 표기가 없다.
        #expect(ChessRules.san(for: ChessMove(uci: "e2e5")!, in: start) == nil)
    }

    @Test("SAN 동형 중복 해소 — 파일 → 랭크 → 둘 다")
    func sanDisambiguationLadder() throws {
        // ① 출발 파일이 갈라 준다.
        let byFile = try chessPosition("4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1")
        #expect(ChessRules.san(for: ChessMove(uci: "b1d2")!, in: byFile) == "Nbd2")
        #expect(ChessRules.san(for: ChessMove(uci: "f3d2")!, in: byFile) == "Nfd2")

        // ② 파일이 같으니 랭크로 간다.
        let byRank = try chessPosition("4k3/8/8/6N1/8/8/8/4K1N1 w - - 0 1")
        #expect(ChessRules.san(for: ChessMove(uci: "g1f3")!, in: byRank) == "N1f3")
        #expect(ChessRules.san(for: ChessMove(uci: "g5f3")!, in: byRank) == "N5f3")

        // ③ 셋이 같은 칸으로 간다: c3 은 파일도 랭크도 안 갈라 주므로 출발 칸 전체, c5 는 랭크로, g3 은 파일로 갈린다.
        let byBoth = try chessPosition("4k3/8/8/2N5/8/2N3N1/8/4K3 w - - 0 1")
        #expect(ChessRules.san(for: ChessMove(uci: "c3e4")!, in: byBoth) == "Nc3e4")
        #expect(ChessRules.san(for: ChessMove(uci: "c5e4")!, in: byBoth) == "N5e4")
        #expect(ChessRules.san(for: ChessMove(uci: "g3e4")!, in: byBoth) == "Nge4")

        // 겹치는 말이 없으면 해소가 붙지 않는다(기준선).
        let alone = try chessPosition("4k3/8/8/8/8/5N2/8/4K3 w - - 0 1")
        #expect(ChessRules.san(for: ChessMove(uci: "f3d2")!, in: alone) == "Nd2")
    }

    @Test("SAN 파싱 — 생성한 표기를 그대로 되읽고, 흔들림도 받는다")
    func sanParsingRoundTrips() throws {
        let byBoth = try chessPosition("4k3/8/8/2N5/8/2N3N1/8/4K3 w - - 0 1")
        #expect(ChessRules.move(san: "Nc3e4", in: byBoth)?.uci == "c3e4")
        #expect(ChessRules.move(san: "N5e4", in: byBoth)?.uci == "c5e4")
        #expect(ChessRules.move(san: "Nge4", in: byBoth)?.uci == "g3e4")
        #expect(ChessRules.move(san: "Ne4", in: byBoth) == nil, "셋에 맞는 표기는 수가 아니다")

        let castles = try chessPosition("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        #expect(ChessRules.move(san: "O-O", in: castles)?.uci == "e1g1")
        #expect(ChessRules.move(san: "0-0-0", in: castles)?.uci == "e1c1", "0 으로 적은 캐슬링도 읽는다")

        let promotion = try chessPosition("1n6/P7/8/8/8/8/8/K6k w - - 0 1")
        #expect(ChessRules.move(san: "a8=Q", in: promotion)?.uci == "a7a8q")
        #expect(ChessRules.move(san: "a8Q", in: promotion)?.uci == "a7a8q", "= 를 뺀 승격도 읽는다")
        #expect(ChessRules.move(san: "axb8=N", in: promotion)?.uci == "a7b8n")

        let matable = try chessPosition("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
        #expect(ChessRules.move(san: "Ra8", in: matable)?.uci == "a1a8", "메이트 표시가 없어도 읽는다")
        #expect(ChessRules.move(san: " Ra8#!! ", in: matable)?.uci == "a1a8")
        #expect(ChessRules.move(san: "Ra9", in: matable) == nil)
        #expect(ChessRules.move(san: "Qa8", in: matable) == nil, "없는 말로 적은 수")

        // 합법 수 전부가 왕복한다(캐슬링·앙파상·승격이 몰린 ②③④⑤) — 한 모양만 통과하고 다른 모양이 깨지는 일을 막는다.
        for item in try ["②", "③", "④", "⑤"].map({ try chessPerftCase($0) }) {
            let position = try chessPosition(item.fen)
            for move in ChessRules.legalMoves(in: position) {
                let notation = try #require(ChessRules.san(for: move, in: position), "\(item.label) \(move.uci)")
                #expect(ChessRules.move(san: notation, in: position) == move, "\(item.label) \(notation)")
            }
        }
    }

    @Test("SAN 기보 — 수순을 사람이 읽는 표기로")
    func sanLineRecordsAGame() throws {
        let line = try #require(ChessRules.sanLine(uciLine: ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"],
                                                   from: .standard))
        #expect(line == ["e4", "e5", "Nf3", "Nc6", "Bb5"])
    }

    // MARK: - 캐슬링

    @Test("캐슬링 — 양쪽 다 되고, 룩이 함께 가고, 권리가 사라진다")
    func castlingMovesTheRookAndClearsRights() throws {
        let white = try chessPosition("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        #expect(chessMoveSet(white).isSuperset(of: ["e1g1", "e1c1"]))

        let short = try #require(ChessRules.effect(of: ChessMove(uci: "e1g1")!, in: white))
        #expect(short.isCastling)
        #expect(short.rookMove?.uci == "h1f1")
        #expect(short.after[ChessSquare("g1")!] == ChessPiece(.white, .king))
        #expect(short.after[ChessSquare("f1")!] == ChessPiece(.white, .rook))
        #expect(short.after[ChessSquare("h1")!] == nil)
        #expect(short.after.castlingRights == [.blackKingside, .blackQueenside], "백의 권리 둘이 사라진다")

        let long = try #require(ChessRules.effect(of: ChessMove(uci: "e1c1")!, in: white))
        #expect(long.rookMove?.uci == "a1d1")
        #expect(long.after[ChessSquare("c1")!] == ChessPiece(.white, .king))
        #expect(long.after[ChessSquare("d1")!] == ChessPiece(.white, .rook))

        // 흑도 같다.
        let black = try chessPosition("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
        #expect(chessMoveSet(black).isSuperset(of: ["e8g8", "e8c8"]))
        let blackShort = try #require(ChessRules.effect(of: ChessMove(uci: "e8g8")!, in: black))
        #expect(blackShort.rookMove?.uci == "h8f8")
        #expect(blackShort.after.castlingRights == [.whiteKingside, .whiteQueenside])
    }

    @Test("캐슬링 권리 소멸 — 킹이 움직이면 둘, 룩이 떠나면 그쪽, 룩이 잡히면 그쪽")
    func castlingRightsExpire() throws {
        let board = try chessPosition("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")

        let afterKing = try #require(ChessRules.apply(ChessMove(uci: "e1e2")!, to: board))
        #expect(afterKing.castlingRights.fenText == "kq")

        let afterRookA = try #require(ChessRules.apply(ChessMove(uci: "a1a2")!, to: board))
        #expect(afterRookA.castlingRights.fenText == "Kkq")

        let afterRookH = try #require(ChessRules.apply(ChessMove(uci: "h1h2")!, to: board))
        #expect(afterRookH.castlingRights.fenText == "Qkq")

        // 룩이 **잡히면** 그 권리도 사라진다(룩이 떠난 것과 같은 결과여야 한다).
        let captureable = try chessPosition("r3k2r/8/8/8/8/8/7q/R3K2R b KQkq - 0 1")
        let afterCapture = try #require(ChessRules.apply(ChessMove(uci: "h2h1")!, to: captureable))
        #expect(afterCapture.castlingRights.fenText == "Qkq")

        // 룩이 다시 돌아와도 권리는 돌아오지 않는다.
        let returned = try chessFinal(["a1a2", "a8a7", "a2a1", "a7a8"], from: board)
        #expect(returned.castlingRights.fenText == "Kk")
    }

    @Test("캐슬링이 막히는 네 가지 — 경로 · 경유 칸 공격 · 체크 중 · b1 은 상관없다")
    func castlingIsBlockedOnlyByTheRightThings() throws {
        // ① 사이에 말이 있으면 그쪽만 막힌다.
        let blocked = try chessPosition("r3k2r/8/8/8/8/8/8/R3KB1R w KQkq - 0 1")
        #expect(!chessMoveSet(blocked).contains("e1g1"), "f1 에 말이 있다")
        #expect(chessMoveSet(blocked).contains("e1c1"))

        // ② 킹이 **지나는** 칸이 공격받으면 막힌다.
        let transit = try chessPosition("r3k2r/8/8/8/8/5r2/8/R3K2R w KQkq - 0 1")
        #expect(!chessMoveSet(transit).contains("e1g1"), "f1 이 공격받는다")
        #expect(chessMoveSet(transit).contains("e1c1"))

        // ③ 체크 중에는 양쪽 다 금지(출발 칸이 공격받는 것과 같은 조건이다).
        let inCheck = try chessPosition("r3k2r/8/8/8/8/4r3/8/R3K2R w KQkq - 0 1")
        #expect(ChessRules.isInCheck(inCheck))
        #expect(chessMoveSet(inCheck).isDisjoint(with: ["e1g1", "e1c1"]))

        // ④ b1 이 공격받아도 긴 쪽 캐슬링은 **된다** — 킹이 지나지 않는 칸이다(룩만 지난다).
        let bFileAttacked = try chessPosition("r3k2r/8/8/8/8/1r6/8/R3K2R w KQkq - 0 1")
        #expect(!ChessRules.isInCheck(bFileAttacked))
        #expect(chessMoveSet(bFileAttacked).contains("e1c1"), "b1 공격은 긴 쪽 캐슬링을 막지 않는다")

        // ⑤ 도착 칸이 공격받으면 막힌다.
        let landing = try chessPosition("r3k2r/8/8/8/8/6r1/8/R3K2R w KQkq - 0 1")
        #expect(!chessMoveSet(landing).contains("e1g1"), "g1 이 공격받는다")
    }

    // MARK: - 앙파상

    @Test("앙파상 — 두 칸 전진 **직후 한 수만**, 잡힌 폰은 도착 칸이 아닌 칸에서 사라진다")
    func enPassantIsOnlyAvailableImmediately() throws {
        let before = try chessPosition("7k/2p5/8/KP6/8/8/8/8 b - - 0 1")

        // 한 칸 전진에는 앙파상이 열리지 않는다 — b5c6 은 **평범한 잡기**가 된다(잡힌 칸이 도착 칸이다).
        let singlePush = try chessFinal(["c7c6"], from: before)
        #expect(singlePush.enPassantTarget == nil)
        let plainCapture = try #require(ChessRules.effect(of: ChessMove(uci: "b5c6")!, in: singlePush))
        #expect(!plainCapture.isEnPassant)
        #expect(plainCapture.capturedSquare == ChessSquare("c6"))

        // 두 칸 전진 직후에는 열린다.
        let doublePush = try chessFinal(["c7c5"], from: before)
        #expect(doublePush.enPassantTarget == ChessSquare("c6"))
        #expect(chessMoveSet(doublePush).contains("b5c6"))

        // 잡힌 폰은 c5 에서 사라진다(도착 칸은 c6 이다).
        let effect = try #require(ChessRules.effect(of: ChessMove(uci: "b5c6")!, in: doublePush))
        #expect(effect.isEnPassant)
        #expect(effect.capturedSquare == ChessSquare("c5"))
        #expect(effect.captured == ChessPiece(.black, .pawn))
        #expect(effect.after[ChessSquare("c5")!] == nil, "잡힌 폰이 판에 남아 있다")
        #expect(effect.after[ChessSquare("c6")!] == ChessPiece(.white, .pawn))
        #expect(effect.after.halfmoveClock == 0, "폰 이동이자 잡기 — 50수 카운터가 돌아간다")

        // 한 수 지나면 사라진다 — 폰은 그대로 c5 에 있는데도.
        let later = try chessFinal(["c7c5", "a5a4", "h8g8"], from: before)
        #expect(later[ChessSquare("c5")!] == ChessPiece(.black, .pawn))
        #expect(later.enPassantTarget == nil)
        #expect(!chessMoveSet(later).contains("b5c6"), "두 칸 전진 다음 수에만 잡을 수 있다")
    }

    @Test("앙파상으로 **자기 왕이 열리면** 불법 — 룩만 더한 판이 기준선")
    func enPassantThatExposesOwnKingIsIllegal() throws {
        // 기준선: 룩이 없으면 같은 수순에서 앙파상이 합법이다.
        let safe = try chessFinal(["c7c5"], from: try chessPosition("7k/2p5/8/KP6/8/8/8/8 b - - 0 1"))
        #expect(chessMoveSet(safe).contains("b5c6"))

        // h5 에 흑 룩을 하나 더하면: b5xc6 은 b5 와 c5 를 **둘 다** 비워 5번째 줄이 열린다 → 백 왕이 공격받는다.
        let pinned = try chessFinal(["c7c5"], from: try chessPosition("7k/2p5/8/KP5r/8/8/8/8 b - - 0 1"))
        #expect(pinned.enPassantTarget == ChessSquare("c6"), "앙파상 칸 자체는 열려 있다")
        #expect(!chessMoveSet(pinned).contains("b5c6"), "앙파상으로 왕이 열리는 수는 불법이다")
        #expect(chessMoveSet(pinned).contains("b5b6"), "같은 폰의 전진은 합법 — c5 폰이 줄을 계속 막는다")
        #expect(ChessRules.apply(ChessMove(uci: "b5c6")!, to: pinned) == nil)
    }

    // MARK: - 승격

    @Test("승격 — 네 말 전부 고를 수 있고, 잡으면서도 승격한다")
    func promotionOffersFourChoicesIncludingCaptures() throws {
        let board = try chessPosition("1n6/P7/8/8/8/8/8/K6k w - - 0 1")
        let moves = chessMoveSet(board)
        #expect(moves.isSuperset(of: ["a7a8q", "a7a8r", "a7a8b", "a7a8n"]))
        #expect(moves.isSuperset(of: ["a7b8q", "a7b8r", "a7b8b", "a7b8n"]))
        #expect(!moves.contains("a7a8"), "승격 말을 고르지 않은 수는 합법 수가 아니다")
        #expect(moves.filter { $0.hasPrefix("a7") }.count == 8, "두 도착 칸 × 네 말")
        #expect(ChessRules.apply(ChessMove(from: ChessSquare("a7")!, to: ChessSquare("a8")!), to: board) == nil)

        let queened = try #require(ChessRules.apply(ChessMove(uci: "a7a8q")!, to: board))
        #expect(queened[ChessSquare("a8")!] == ChessPiece(.white, .queen))
        #expect(queened[ChessSquare("a7")!] == nil)
        #expect(queened.halfmoveClock == 0)

        let knighted = try #require(ChessRules.effect(of: ChessMove(uci: "a7b8n")!, in: board))
        #expect(knighted.isPromotion)
        #expect(knighted.captured == ChessPiece(.black, .knight))
        #expect(knighted.after[ChessSquare("b8")!] == ChessPiece(.white, .knight))

        // 흑도 같다(1번째 줄로 간다).
        let blackPromotion = try chessPosition("K6k/8/8/8/8/8/p7/1N6 b - - 0 1")
        #expect(chessMoveSet(blackPromotion).isSuperset(of: ["a2a1q", "a2a1n", "a2b1q", "a2b1n"]))
    }

    // MARK: - 체크 · 체크메이트 · 스테일메이트

    @Test("체크메이트 — 수가 없고 체크다")
    func checkmateEndsTheGame() throws {
        let board = try chessPosition("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
        #expect(ChessRules.outcome(position: board) == nil, "두기 전에는 끝나지 않았다")

        let mated = try #require(ChessRules.apply(ChessMove(uci: "a1a8")!, to: board))
        #expect(ChessRules.isInCheck(mated))
        #expect(ChessRules.legalMoves(in: mated).isEmpty)
        #expect(ChessRules.outcome(position: mated) == .checkmate(winner: .white))
        #expect(ChessRules.outcome(position: mated)?.winner == .white)
        #expect(ChessRules.outcome(position: mated)?.isDraw == false)

        // 바보 메이트(두 수 메이트)도 같은 판정이다.
        let fools = try chessFinal(["f2f3", "e7e5", "g2g4", "d8h4"])
        #expect(ChessRules.outcome(position: fools) == .checkmate(winner: .black))
    }

    @Test("스테일메이트 — 수가 없는데 체크가 아니다")
    func stalemateIsADraw() throws {
        let board = try chessPosition("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        #expect(!ChessRules.isInCheck(board))
        #expect(ChessRules.legalMoves(in: board).isEmpty)
        #expect(ChessRules.outcome(position: board) == .stalemate)
        #expect(ChessRules.outcome(position: board)?.isDraw == true)
    }

    @Test("체크 중에는 체크를 푸는 수만 남는다")
    func checkLimitsMovesToEscapes() throws {
        // 흑 룩 e3 가 백 왕 e1 을 노린다. 왕이 피하거나, e-파일을 막거나, 룩을 잡는 수만 합법이다.
        let board = try chessPosition("4k3/8/8/8/8/4r3/8/4K2R w K - 0 1")
        #expect(ChessRules.isInCheck(board))
        let moves = chessMoveSet(board)
        #expect(moves == ["e1d1", "e1f1", "e1d2", "e1f2"], "실제 합법 수: \(moves.sorted())")
        #expect(!moves.contains("h1h3"), "체크를 두고 딴 수를 두지 못한다")
    }

    // MARK: - 50수 규칙

    @Test("50수 카운터 — 폰 이동과 잡기에서 0 으로 돌아간다")
    func halfmoveClockResetsOnPawnMovesAndCaptures() throws {
        #expect(try chessFinal(["g1f3"]).halfmoveClock == 1)
        #expect(try chessFinal(["g1f3", "g8f6"]).halfmoveClock == 2)
        #expect(try chessFinal(["g1f3", "g8f6", "f3g1"]).halfmoveClock == 3)
        #expect(try chessFinal(["g1f3", "g8f6", "d2d4"]).halfmoveClock == 0, "폰 이동")

        // 잡기(폰이 아닌 말)도 0 으로 돌린다.
        let capture = try chessPosition("4k3/8/8/8/8/8/8/R2rK3 w - - 40 60")
        #expect(capture.halfmoveClock == 40)
        #expect(try chessFinal(["a1d1"], from: capture).halfmoveClock == 0)

        // 캐슬링은 폰도 잡기도 아니다 — 카운터가 올라간다.
        let castle = try chessPosition("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 7 40")
        #expect(try chessFinal(["e1g1"], from: castle).halfmoveClock == 8)
    }

    @Test("50수 무승부 — 100 반수에 걸리고, 그 전에는 아니다")
    func fiftyMoveRuleDrawsAtOneHundredHalfmoves() throws {
        let board = try chessPosition("4k3/8/8/8/8/8/8/R3K3 w Q - 99 100")
        #expect(ChessRules.outcome(position: board) == nil, "99 에서는 끝나지 않는다")

        let drawn = try #require(ChessRules.apply(ChessMove(uci: "a1a2")!, to: board))
        #expect(drawn.halfmoveClock == 100)
        #expect(ChessRules.outcome(position: drawn) == .fiftyMoveRule)

        // 폰 이동이 끼면 카운터가 0 이라 무승부가 아니다(기준선).
        let withPawn = try chessPosition("4k3/8/8/8/8/8/P7/R3K3 w Q - 99 100")
        let pushed = try #require(ChessRules.apply(ChessMove(uci: "a2a3")!, to: withPawn))
        #expect(pushed.halfmoveClock == 0)
        #expect(ChessRules.outcome(position: pushed) == nil)
    }

    @Test("100 반수째가 메이트면 메이트다 — 무승부보다 앞선다")
    func checkmateOutranksTheFiftyMoveRule() throws {
        let board = try chessPosition("6k1/5ppp/8/8/8/8/8/R5K1 w - - 99 60")
        let mated = try #require(ChessRules.apply(ChessMove(uci: "a1a8")!, to: board))
        #expect(mated.halfmoveClock == 100, "50수 조건도 함께 찼다")
        #expect(ChessRules.outcome(position: mated) == .checkmate(winner: .white))
    }

    // MARK: - 3회 동형 반복

    @Test("3회 동형 반복 — 나이트를 왕복시키면 초기 국면이 세 번 나온다")
    func threefoldRepetitionCountsTheSamePositionThrice() throws {
        let line = ["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8"]
        let trail = try chessTrail(line)
        #expect(trail.count == 9)

        var ledger = ChessRepetitionLedger()
        var outcomes: [ChessOutcome?] = []
        for position in trail {
            ledger.record(position)
            outcomes.append(ChessRules.outcome(position: position, repetitionCounts: ledger.repetitionCounts))
        }

        #expect(ledger.count(of: .standard) == 3, "초기 국면이 세 번")
        #expect(trail[4].repetitionKey == ChessPosition.standard.repetitionKey, "한 바퀴 뒤 같은 국면")
        #expect(outcomes[4] == nil, "두 번째 등장은 아직 무승부가 아니다")
        #expect(outcomes[8] == .threefoldRepetition)
        #expect(outcomes.prefix(8).allSatisfy { $0 == nil }, "여덟 번째까지는 끝나지 않는다")

        // 50수 카운터와 수 번호는 반복 판정에 들어가지 않는다 — 그래서 같은 국면으로 센다.
        #expect(trail[8].halfmoveClock == 8)
        #expect(trail[8].fullmoveNumber == 5)
        #expect(trail[8].repetitionKey == ChessPosition.standard.repetitionKey)
    }

    @Test("국면 동일성 = 배치 + 차례 + 캐슬링 권리 + 앙파상 **가능성**")
    func repetitionKeyIgnoresClocksButNotRightsOrEnPassant() throws {
        let withRights = try chessPosition("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        let withoutRights = try chessPosition("r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1")
        #expect(withRights.repetitionKey != withoutRights.repetitionKey, "권리가 다르면 다른 국면이다")

        let laterClock = try chessPosition("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 33 90")
        #expect(withRights.repetitionKey == laterClock.repetitionKey, "카운터·수 번호는 보지 않는다")

        let blackToMove = try chessPosition("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
        #expect(withRights.repetitionKey != blackToMove.repetitionKey, "차례가 다르면 다른 국면이다")

        // 앙파상 칸이 FEN 에 있어도 **잡을 수 있는 수가 없으면** 키에는 들어가지 않는다.
        let afterE4 = try chessFinal(["e2e4"])
        #expect(afterE4.enPassantTarget == ChessSquare("e3"))
        #expect(!ChessRules.hasLegalEnPassantCapture(in: afterE4))
        #expect(afterE4.repetitionKey.hasSuffix(" -"), "실제 키: \(afterE4.repetitionKey)")
        #expect(afterE4.fen.contains(" e3 "), "FEN 에는 e3 가 남는다 — 키와 FEN 은 다른 일을 한다")

        // 잡을 수 있으면 키에 들어간다(기준선이 다르다).
        let capturable = try chessPosition("rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        #expect(ChessRules.hasLegalEnPassantCapture(in: capturable))
        #expect(capturable.repetitionKey.hasSuffix(" e3"), "실제 키: \(capturable.repetitionKey)")
    }

    // MARK: - 불충분 기물

    @Test("불충분 기물 — 작은 말 하나, 또는 한 색 칸 비숍만")
    func insufficientMaterialCoversExactlyFourCases() throws {
        // 비숍이 여럿일 때(한 색 칸에 몰린 판)는 ChessContractTests 가 따로 못 박는다 — 여기서는 기본형 넷이다.
        let draws = [
            ("왕 vs 왕", "8/8/4k3/8/8/3K4/8/8 w - - 0 1"),
            ("왕+비숍 vs 왕", "8/8/4k3/8/8/3K1B2/8/8 w - - 0 1"),
            ("왕+나이트 vs 왕", "8/8/4k3/8/8/3K1N2/8/8 w - - 0 1"),
            ("왕 vs 왕+비숍", "5b2/8/4k3/8/8/4K3/8/8 w - - 0 1"),
            ("왕+비숍 vs 왕+같은 색 비숍", "5b2/8/4k3/8/8/4K3/8/2B5 w - - 0 1")
        ]
        for (label, fen) in draws {
            let position = try chessPosition(fen)
            #expect(ChessRules.hasInsufficientMaterial(position), "\(label)")
            #expect(ChessRules.outcome(position: position) == .insufficientMaterial, "\(label)")
        }

        let alive = [
            ("왕+비숍 vs 왕+다른 색 비숍", "2b5/8/4k3/8/8/4K3/8/2B5 w - - 0 1"),
            ("왕+나이트 둘 vs 왕(강제 메이트가 있다)", "8/8/4k3/8/8/3K1NN1/8/8 w - - 0 1"),
            ("왕+**다른 색 칸** 비숍 둘 vs 왕(f3 밝음 · g3 어두움)", "8/8/4k3/8/8/3K1BB1/8/8 w - - 0 1"),
            ("왕+비숍+나이트 vs 왕", "8/8/4k3/8/8/3K1BN1/8/8 w - - 0 1"),
            ("왕+폰 vs 왕", "8/8/4k3/8/8/3K4/4P3/8 w - - 0 1"),
            ("왕+룩 vs 왕", "8/8/4k3/8/8/3K1R2/8/8 w - - 0 1"),
            ("왕+퀸 vs 왕", "8/8/4k3/8/8/3K1Q2/8/8 w - - 0 1")
        ]
        for (label, fen) in alive {
            let position = try chessPosition(fen)
            #expect(!ChessRules.hasInsufficientMaterial(position), "\(label)")
        }

        // 같은 색 비숍 둘은 칸 색으로 가른다 — c1 과 f8 은 둘 다 어두운 칸이다.
        #expect(ChessSquare("c1")!.isLightSquare == ChessSquare("f8")!.isLightSquare)
        #expect(ChessSquare("c1")!.isLightSquare != ChessSquare("c8")!.isLightSquare)

        // 수가 없으면 사국보다 스테일메이트가 앞선다(판정 순서).
        let stalemateWithBareKings = try chessPosition("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        #expect(ChessRules.outcome(position: stalemateWithBareKings) == .stalemate)
    }

    // MARK: - 시계 (5분 + 3초)

    @Test("시계 — 5분에서 시작하고, 수를 둔 뒤 3초가 붙고, 넘겨 쓰면 시간패다")
    func clockAddsIncrementOnlyAfterAMove() {
        let clock = ChessClock()
        #expect(clock.remaining(.white) == 300)
        #expect(clock.remaining(.black) == 300)

        let afterWhite = clock.afterMove(by: .white, elapsed: 10).clock
        #expect(afterWhite?.remaining(.white) == 293, "300 − 10 + 3")
        #expect(afterWhite?.remaining(.black) == 300, "상대 시계는 그대로")

        // 남은 시간을 넘겨 쓰면 가산이 붙지 않는다 — 시간패다(성립하지 않는 입력과 갈린다: ChessContractTests).
        #expect(clock.afterMove(by: .white, elapsed: 301) == .flagged)
        #expect(clock.hasFlagged(.white, elapsed: 301) == true)
        #expect(clock.hasFlagged(.white, elapsed: 299) == false)

        // 꼭 맞게 쓰면 아직 살아 있고 가산을 받는다(경계).
        #expect(clock.afterMove(by: .white, elapsed: 300).clock?.remaining(.white) == 3)
        #expect(clock.hasFlagged(.white, elapsed: 300) == false)

        // 3초보다 빨리 두면 시간이 늘어난다(가산제의 전부다).
        var running = ChessClock()
        for _ in 0..<10 { running = running.afterMove(by: .black, elapsed: 1).clock! }
        #expect(running.remaining(.black) == 320, "한 수마다 +2초 × 10")
    }

    // MARK: - 왕 안전 지름길 대조

    @Test("합법 수 = 전수 검사 결과 — 왕 안전 지름길이 수를 더하거나 빼지 않는다")
    func legalMovesAgreeWithBruteForceVerification() throws {
        // ②③④ 는 캐슬링·핀·앙파상·승격이 몰린 국면이다. 두 수까지 내려가며 **모든** 국면을 전수 검사와 맞춰 본다.
        var checked = 0
        for marker in ["②", "③", "④"] {
            var frontier = [try chessPosition(try chessPerftCase(marker).fen)]
            for level in 0..<3 {
                var next: [ChessPosition] = []
                for position in frontier {
                    let moves = ChessRules.legalMoves(in: position)
                    #expect(moves.map(\.uci).sorted() == (try chessBruteForceLegalMoves(position)), "\(position.fen)")
                    checked += 1
                    guard level < 2 else { continue }
                    for move in moves {
                        if let child = ChessRules.apply(move, to: position) { next.append(child) }
                    }
                }
                frontier = next
            }
        }
        // 기준선: 실제로 수천 국면을 돌았는지 — 0건을 돌고 "다 맞다"로 초록이 되는 일을 막는다.
        #expect(checked > 2_400, "전수 대조한 국면이 \(checked)개뿐이다 — 이 검사가 헛돈다")
    }

    @Test("왕이 없는 판은 수를 내지 않는다 — 손으로 짠 국면의 안전망")
    func handBuiltPositionsWithoutKingsYieldNoMoves() {
        var board = ChessPosition.empty
        board[ChessSquare("d4")!] = ChessPiece(.white, .queen)
        #expect(ChessRules.legalMoves(in: board).isEmpty)
        #expect(!ChessRules.isInCheck(board))
        #expect(ChessRules.perft(board, depth: 2) == 0)

        // 칸 읽기·쓰기는 그대로 된다(판을 짜는 자리다).
        #expect(board[ChessSquare("d4")!] == ChessPiece(.white, .queen))
        board[ChessSquare("d4")!] = nil
        #expect(board[ChessSquare("d4")!] == nil)
    }
}
