import Foundation
import Testing
@testable import CheckCore

// 체스 엔진의 **계약이 깨진 자리**들 — 적대 검증 셋이 실행으로 재현한 결함마다 그 자리 하나를 못 박는다.
//
// 여기 모인 것들의 공통점: 수 세기(perft)로는 영원히 안 잡힌다. 수 세기는 합법 수 생성만 재고,
// 아래는 전부 **입구의 계약**이다 — 성립하지 않는 입력을 받아들이는가, 받아들인 뒤 조용히 틀린 값을 내는가,
// 같은 질문에 두 함수가 다른 답을 하는가. 그래서 자리마다 ① 고장난 입력과 ② **결과가 다른 기준선**을 함께 적는다
// (기준선이 같은 입력이면 그 테스트는 영원히 초록이다).
//
// 단언은 모양이 아니라 결과를 잰다: "검증 함수가 있다"가 아니라 "이 FEN 은 nil 이고 저 FEN 은 이 국면이다".

@Suite("체스 계약 — 재현된 결함")
struct ChessContractTests {

    // MARK: - 시계

    @Test("시계 — '시간패'와 '성립하지 않는 입력'이 갈리고, 두 함수가 **같은 답**을 한다")
    func clockSeparatesFlaggedFromInvalidElapsed() {
        let clock = ChessClock()

        // 기준선: 평범한 수와 진짜 시간패에서는 둘이 같은 말을 한다.
        #expect(clock.afterMove(by: .white, elapsed: 10).clock?.remaining(.white) == 293)
        #expect(clock.hasFlagged(.white, elapsed: 10) == false)
        #expect(clock.afterMove(by: .white, elapsed: 301) == .flagged)
        #expect(clock.hasFlagged(.white, elapsed: 301) == true)

        // 음수 elapsed 는 서버가 now − moveStartedAt 을 셀 때 시계 밀림·요청 재시도로 평범하게 나온다.
        // 그걸 시간패로 읽으면 사람이 한 번에 진다 — 그래서 **시간패가 아니라 성립하지 않는 입력**이어야 한다.
        for bad in [-0.5, -1e9, Double.nan, .infinity, -.infinity] {
            #expect(clock.afterMove(by: .white, elapsed: bad) == .invalidElapsed, "\(bad)")
            #expect(clock.afterMove(by: .white, elapsed: bad).clock == nil, "\(bad)")
            #expect(clock.hasFlagged(.white, elapsed: bad) == nil, "\(bad)")
        }

        // 경계: 꼭 맞게 쓰면 살아 있고 가산을 받는다.
        #expect(clock.afterMove(by: .white, elapsed: 300).clock?.remaining(.white) == 3)
        #expect(clock.hasFlagged(.white, elapsed: 300) == false)
    }

    @Test("시간패 — 상대가 메이트할 기물이 없으면 무승부다(FIDE 6.9)")
    func timeoutIsADrawWhenTheOpponentCannotMate() throws {
        // 흑 맨 왕 · 백은 K+N: 백은 **어떤 수순으로도** 메이트할 수 없다. 시계는 '흑 시간패'라고만 말하므로
        // 자연스러운 호출(깃발 → 패)이 FIDE 가 무승부라고 하는 판을 패배로 만든다. 그 둘을 묶는 자리를 잰다.
        let knightOnly = try #require(ChessPosition(fen: "4k3/8/8/8/8/8/8/2N1K3 b - - 0 1"))
        #expect(ChessRules.hasInsufficientMaterial(knightOnly))
        #expect(ChessClock().hasFlagged(.black, elapsed: 301) == true, "시계는 깃발만 본다")
        #expect(ChessRules.timeoutRuling(position: knightOnly, flagged: .black) == .drawByInsufficientMaterial)
        #expect(ChessRules.timeoutRuling(position: knightOnly, flagged: .black).isDraw)
        #expect(ChessRules.timeoutRuling(position: knightOnly, flagged: .black).winner == nil)

        // 기준선: 룩이 하나라도 있으면 같은 깃발이 패배다.
        let withRook = try #require(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 b - - 0 1"))
        #expect(ChessRules.timeoutRuling(position: withRook, flagged: .black) == .loss(flagged: .black))
        #expect(ChessRules.timeoutRuling(position: withRook, flagged: .black).winner == .white)
        #expect(ChessRules.timeoutRuling(position: withRook, flagged: .black).isDraw == false)

        // 깃발이 떨어진 쪽이 백이면 **흑의** 기물을 본다.
        let blackBishop = try #require(ChessPosition(fen: "4kb2/8/8/8/8/8/8/4K3 w - - 0 1"))
        #expect(ChessRules.hasNoMatingMaterial(blackBishop, color: .black))
        #expect(ChessRules.hasNoMatingMaterial(blackBishop, color: .white))
        #expect(ChessRules.timeoutRuling(position: blackBishop, flagged: .white) == .drawByInsufficientMaterial)

        // 나이트 둘은 메이트가 나오는 자리가 있다 — 시간패는 패배다.
        let twoKnights = try #require(ChessPosition(fen: "4k3/8/8/8/8/8/8/1N2KN2 b - - 0 1"))
        #expect(!ChessRules.hasNoMatingMaterial(twoKnights, color: .white))
        #expect(ChessRules.timeoutRuling(position: twoKnights, flagged: .black) == .loss(flagged: .black))
    }

    // MARK: - 표기

    @Test("SAN — 윈도 줄끝(CR)이 붙은 표기도 읽는다")
    func sanStripsCarriageReturn() {
        let start = ChessPosition.standard
        #expect(ChessRules.move(san: "e4\n", in: start)?.uci == "e2e4", "기준선: LF 는 걷힌다")
        #expect(ChessRules.move(san: "e4\t", in: start)?.uci == "e2e4", "기준선: 탭도 걷힌다")
        #expect(ChessRules.move(san: "e4\r", in: start)?.uci == "e2e4")
        #expect(ChessRules.move(san: "e4\r\n", in: start)?.uci == "e2e4")
        #expect(ChessRules.move(san: "\r\n Nf3 \r\n", in: start)?.uci == "g1f3")
    }

    @Test("SAN — 과다 명시형(Qd1d2 · Qdd2 · Q1d2)도 같은 수로 읽는다")
    func sanReadsOverspecifiedNotation() throws {
        // d1d2 는 합법이고 유일하다 — 더 자세히 적은 표기가 nil 이 될 이유가 없다(PGN 수입·장형 대수 표기).
        let board = try #require(ChessPosition(fen: "4k3/8/8/8/8/8/8/3QK3 w - - 0 1"))
        #expect(ChessRules.san(for: ChessMove(uci: "d1d2")!, in: board) == "Qd2", "기준선: 생성 SAN")
        for text in ["Qd2", "Qd1d2", "Qdd2", "Q1d2", "Qd1-d2"] {
            #expect(ChessRules.move(san: text, in: board)?.uci == "d1d2", "\(text)")
        }

        // 과다 명시가 **없는 말**을 가리키면 수가 아니다(느슨하게 받아 주는 게 아니다).
        #expect(ChessRules.move(san: "Qd3d2", in: board) == nil)
        #expect(ChessRules.move(san: "Qed2", in: board) == nil)
        #expect(ChessRules.move(san: "Q2d2", in: board) == nil)
        #expect(ChessRules.move(san: "Rd1d2", in: board) == nil, "말 글자가 다르다")

        // 잡기도 같다: x 가 있어도 없어도, 출발 칸을 적어도 읽는다.
        let capture = try #require(ChessPosition(fen: "4k3/8/8/8/8/3p4/8/3QK3 w - - 0 1"))
        for text in ["Qxd3", "Qd1xd3", "Qd1d3", "Qdxd3", "Q1xd3"] {
            #expect(ChessRules.move(san: text, in: capture)?.uci == "d1d3", "\(text)")
        }

        // 폰의 장형 표기.
        #expect(ChessRules.move(san: "e2e4", in: .standard)?.uci == "e2e4")
        #expect(ChessRules.move(san: "e2-e4", in: .standard)?.uci == "e2e4")
        #expect(ChessRules.move(san: "e3e4", in: .standard) == nil, "출발 칸이 틀렸다")
    }

    @Test("SAN — 부분 합법수 목록을 넘겨도 동형 중복 해소가 같은 답을 낸다")
    func sanDisambiguationIgnoresPartialLegalLists() throws {
        // Nb1·Nf3 둘이 d2 로 간다 → b1d2 의 SAN 은 "Nbd2" 다. 화면은 흔히 '고른 말의 수'만 들고 있는데,
        // 그 부분 목록을 넘기면 경쟁자가 안 보여 조용히 "Nd2"(되읽히지도 않는 표기)가 나왔다.
        let board = try #require(ChessPosition(fen: "4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1"))
        let move = try #require(ChessMove(uci: "b1d2"))
        let all = ChessRules.legalMoves(in: board)
        #expect(ChessRules.san(for: move, in: board, legalMoves: all) == "Nbd2", "기준선: 전체 목록")

        let onlyThisPiece = all.filter { $0.from == move.from }
        #expect(onlyThisPiece.count < all.count, "기준선이 같은 입력이면 이 테스트는 헛돈다")
        let notation = try #require(ChessRules.san(for: move, in: board, legalMoves: onlyThisPiece))
        #expect(notation == "Nbd2")
        #expect(ChessRules.move(san: notation, in: board) == move, "낸 표기는 되읽힌다")

        // "Nd2" 는 둘에 맞으므로 수가 아니다(모호).
        #expect(ChessRules.move(san: "Nd2", in: board) == nil)
    }

    // MARK: - FEN 입구

    @Test("FEN — 줄끝·탭이 붙어도 읽는다(배치가 틀린 것과 구별된다)")
    func fenAcceptsSurroundingWhitespace() {
        let fen = ChessPosition.standard.fen
        #expect(ChessPosition(fen: "  \(fen)  ") == .standard, "기준선: 앞뒤 공백은 읽힌다")
        #expect(ChessPosition(fen: fen + "\n") == .standard)
        #expect(ChessPosition(fen: fen + "\r\n") == .standard)
        #expect(ChessPosition(fen: "\t\(fen)\t") == .standard)
        #expect(ChessPosition(fen: fen.replacingOccurrences(of: " ", with: "\t")) == .standard)

        // 글자가 한 개 더 붙은 것과 **배치가 틀린 것**은 여전히 갈린다 — 둘을 같은 nil 로 보고하지 않는다.
        #expect(ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBN w KQkq - 0 1") == nil)
    }

    @Test("FEN 배치 — 숫자 이어쓰기는 거절(한 판은 한 글자열이다)")
    func fenRejectsRunTogetherEmptyCounts() {
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1") != nil, "기준선")
        #expect(ChessPosition(fen: "4k3/44/8/8/8/8/8/4K3 w - - 0 1") == nil)
        #expect(ChessPosition(fen: "4k3/332/8/8/8/8/8/4K3 w - - 0 1") == nil)
        #expect(ChessPosition(fen: "4k3/11111111/8/8/8/8/8/4K3 w - - 0 1") == nil)
        #expect(ChessPosition(fen: "4k3/8/8/44/8/8/8/4K3 w - - 0 1") == nil)
        #expect(ChessPosition(fen: "22k3/8/8/8/8/8/8/4K3 w - - 0 1") == nil)

        // 카운터도 정규형만: 부호·앞자리 0 은 같은 판을 여러 글자열로 만든다.
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/4K3 w - - +0 +1") == nil)
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/4K3 w - - 00 1") == nil)
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 01") == nil)
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/4K3 w - - -1 1") == nil)

        // 기존 거절은 그대로.
        #expect(ChessPosition(fen: "4k3/9/8/8/8/8/8/4K3 w - - 0 1") == nil)
        #expect(ChessPosition(fen: "4k3/0/8/8/8/8/8/4K3 w - - 0 1") == nil)
    }

    @Test("캐슬링 권리 — 빈 칸은 '권리 넷 다 없음'이 아니라 nil")
    func castlingRightsRejectEmptyField() {
        #expect(ChessCastlingRights.parse(fen: "-") == [], "기준선: '-' 만 권리 없음이다")
        #expect(ChessCastlingRights.parse(fen: "KQkq") == .all)
        #expect(ChessCastlingRights.parse(fen: "Kq") == [.whiteKingside, .blackQueenside])
        #expect(ChessCastlingRights.parse(fen: "") == nil)
        #expect(ChessCastlingRights.parse(fen: " ") == nil)
        #expect(ChessCastlingRights.parse(fen: "-K") == nil)
        #expect(ChessCastlingRights.parse(fen: "KKqq") == nil)
    }

    @Test("FEN — 성립할 수 없는 반수 카운터는 거절(불법 무승부를 막는다)")
    func fenRejectsUnreachableHalfmoveClock() throws {
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w Q - 0 1") != nil, "기준선")
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w Q - 100 1") == nil, "백 첫 수에 반수 100 은 없다")
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 b Q - 2 1") == nil, "둔 반수가 1 뿐이다")
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 b Q - 1 1") != nil, "경계: 흑 차례면 반수 1 은 나온다")

        // 앙파상 칸이 있다는 것은 직전 수가 폰 두 칸 전진이라는 뜻이다 → 반수는 반드시 0 이다.
        #expect(ChessPosition(fen: "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1") != nil, "기준선")
        #expect(ChessPosition(fen: "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 99 1") == nil)

        // 100 반수가 **나올 수 있는** 국면은 그대로 읽히고 즉시 무승부다(기능을 지운 게 아니다).
        let drawn = try #require(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w Q - 100 60"))
        #expect(ChessRules.outcome(position: drawn) == .fiftyMoveRule)
    }

    @Test("FEN — 넘치는 카운터는 받아들이지 않는다(받아들이면 첫 legalMoves 에서 프로세스가 죽는다)")
    func fenRejectsOverflowingCounters() throws {
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 9223372036854775807 1") == nil, "반수 Int.max")
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 b - - 0 9223372036854775807") == nil, "수 번호 Int.max")
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 0 9223372036854775806") == nil, "Int.max − 1")
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 0 99999999999999999999") == nil, "Int 범위 밖")

        // 위 한계와 그 경계.
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 0 10000") != nil)
        #expect(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 0 10001") == nil)

        // 현실 값은 그대로 돈다 — 수 세기가 같은 답을 낸다(한계가 규칙을 바꾸지 않았다).
        let real = try #require(ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w - - 150 120"))
        #expect(real.halfmoveClock == 150)
        #expect(ChessRules.perft(real, depth: 3) == 1242)
    }

    // MARK: - 판정 입구

    @Test("판정 — 체스판으로 성립하지 않는 판은 무승부가 아니라 nil")
    func outcomeRefusesBrokenBoards() throws {
        var queenOnly = ChessPosition.empty
        queenOnly[ChessSquare("d4")!] = ChessPiece(.white, .queen)
        #expect(ChessRules.legalMoves(in: queenOnly).isEmpty, "문서가 약속한 안전망")
        #expect(ChessRules.outcome(position: queenOnly) == nil, "왕이 아예 없는 판")

        var blackKingMissing = ChessPosition.empty
        blackKingMissing[ChessSquare("e1")!] = ChessPiece(.white, .king)
        blackKingMissing[ChessSquare("d4")!] = ChessPiece(.white, .queen)
        #expect(ChessRules.outcome(position: blackKingMissing) == nil, "흑 왕이 없다")

        var twoWhiteKings = ChessPosition.empty
        twoWhiteKings[ChessSquare("e1")!] = ChessPiece(.white, .king)
        twoWhiteKings[ChessSquare("e2")!] = ChessPiece(.white, .king)
        twoWhiteKings[ChessSquare("e8")!] = ChessPiece(.black, .king)
        #expect(ChessRules.outcome(position: twoWhiteKings) == nil, "백 왕이 둘이다")

        // 기준선: 성립하는 판에서는 판정이 그대로 나온다(nil 을 돌려주는 가드가 판정을 먹지 않았다).
        let stalemate = try #require(ChessPosition(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        #expect(ChessRules.outcome(position: stalemate) == .stalemate)
        let mated = try #require(ChessPosition(fen: "R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1"))
        #expect(ChessRules.outcome(position: mated) == .checkmate(winner: .white))
    }

    @Test("왕을 잡는 수는 생성되지 않는다 — 손으로 짠 판에서도")
    func legalMovesNeverCaptureAKing() throws {
        // 손으로 짠 판(백 Ke1·Rh8 · 흑 Ke8 · 백 차례)은 FEN 파서가 거절하는 모양이지만 subscript 로는 짤 수 있다.
        // 여기서 "h8e8" 이 합법으로 나오면 apply 가 흑 왕을 집어가고, 그 판의 판정이 거짓 무승부가 된다.
        var board = ChessPosition.empty
        board[ChessSquare("e1")!] = ChessPiece(.white, .king)
        board[ChessSquare("h8")!] = ChessPiece(.white, .rook)
        board[ChessSquare("e8")!] = ChessPiece(.black, .king)
        let moves = Set(ChessRules.legalMoves(in: board).map(\.uci))
        #expect(!moves.contains("h8e8"), "흑 왕을 집어가는 수가 있다: \(moves.sorted())")
        #expect(moves.contains("h8h7"), "기준선: 같은 룩의 다른 수는 그대로다")
        #expect(moves.contains("h8g8"), "기준선: 왕 **앞** 칸까지는 간다")
        #expect(!moves.contains("h8d8"), "왕을 지나쳐 가지도 않는다")
        #expect(ChessRules.apply(ChessMove(uci: "h8e8")!, to: board) == nil)
        #expect(ChessRules.effect(of: ChessMove(uci: "h8e8")!, in: board) == nil)

        // 폰도 왕을 집어가지 못한다.
        var pawnBait = ChessPosition.empty
        pawnBait[ChessSquare("a1")!] = ChessPiece(.white, .king)
        pawnBait[ChessSquare("c4")!] = ChessPiece(.white, .pawn)
        pawnBait[ChessSquare("d5")!] = ChessPiece(.black, .king)
        #expect(!Set(ChessRules.legalMoves(in: pawnBait).map(\.uci)).contains("c4d5"))
    }

    @Test("엔진 — 넘치는 카운터로는 돌지 않는다(죽지 않고, 수를 내지 않는다)")
    func engineRefusesOverflowingCounters() {
        // 손으로 짠 폭탄: `halfmoveClock` 은 package var 라 FEN 을 거치지 않고도 담긴다.
        // 고치기 전에는 이 테스트가 **프로세스를 죽였다**(`halfmove + 1` 넘침 → SIGTRAP).
        var halfmoveBomb = ChessPosition.standard
        halfmoveBomb.halfmoveClock = Int.max
        #expect(ChessRules.legalMoves(in: halfmoveBomb).isEmpty)
        #expect(ChessRules.outcome(position: halfmoveBomb) == nil)
        #expect(ChessRules.apply(ChessMove(uci: "e2e4")!, to: halfmoveBomb) == nil)
        #expect(ChessRules.perft(halfmoveBomb, depth: 2) == 0)

        var fullmoveBomb = ChessPosition.standard
        fullmoveBomb.fullmoveNumber = Int.max
        #expect(ChessRules.legalMoves(in: fullmoveBomb).isEmpty)
        #expect(ChessRules.perft(fullmoveBomb, depth: 1) == 0)

        // 기준선: 현실 값은 그대로 돈다.
        var real = ChessPosition.standard
        real.halfmoveClock = 150
        #expect(ChessRules.legalMoves(in: real).count == 20)
    }

    // MARK: - 수 생성

    @Test("위조한 앙파상 칸은 수를 만들지 못한다 — 캐슬링처럼 생성기가 다시 본다")
    func forgedEnPassantTargetYieldsNoMove() throws {
        // 백 폰 c4 · 흑 나이트 d4 · d5 빈칸. `enPassantTarget` 은 package var 라 한 줄로 위조된다.
        var board = try #require(ChessPosition(fen: "4k3/8/8/8/2Pn4/8/8/4K3 w - - 0 1"))
        #expect(Set(ChessRules.legalMoves(in: board).map(\.uci).filter { $0.hasPrefix("c4") }) == ["c4c5"], "기준선")

        board.enPassantTarget = ChessSquare("d5")
        let moves = Set(ChessRules.legalMoves(in: board).map(\.uci))
        #expect(moves.filter { $0.hasPrefix("c4") } == ["c4c5"], "위조한 칸이 수를 만들었다: \(moves.sorted())")
        #expect(ChessRules.apply(ChessMove(uci: "c4d5")!, to: board) == nil, "서버 검증이 이 nil 하나로 끝나야 한다")
        #expect(ChessRules.effect(of: ChessMove(uci: "c4d5")!, in: board) == nil)

        // 왕도 집어가지 못한다(고치기 전에는 잡힌말=black/king 이 나왔다).
        var kingBait = try #require(ChessPosition(fen: "8/8/8/8/2Pk4/8/8/K7 w - - 0 1"))
        kingBait.enPassantTarget = ChessSquare("d5")
        #expect(ChessRules.apply(ChessMove(uci: "c4d5")!, to: kingBait) == nil)

        // 기준선이 달라야 한다: **진짜** 두 칸 전진 다음의 앙파상은 그대로 합법이다.
        let opening = try #require(ChessPosition(fen: "7k/2p5/8/KP6/8/8/8/8 b - - 0 1"))
        let real = try #require(ChessRules.replay(uciLine: ["c7c5"], from: opening)?.last)
        #expect(real.enPassantTarget == ChessSquare("c6"))
        #expect(Set(ChessRules.legalMoves(in: real).map(\.uci)).contains("b5c6"))
        #expect(ChessRules.effect(of: ChessMove(uci: "b5c6")!, in: real)?.capturedSquare == ChessSquare("c5"))
    }

    @Test("수 세기 — 음수 깊이는 0, 깊이 0 만 1")
    func perftSeparatesNegativeDepthFromZero() {
        #expect(ChessRules.perft(.standard, depth: 0) == 1, "기준선: 깊이 0 은 국면 자신")
        #expect(ChessRules.perft(.standard, depth: 1) == 20)
        #expect(ChessRules.perft(.standard, depth: -1) == 0, "깊이가 0 아래로 내려간 사고가 '노드 1개'로 보고된다")
        #expect(ChessRules.perft(.standard, depth: -5) == 0)
        #expect(ChessRules.perftDivide(.standard, depth: -1).isEmpty, "divide 와 경계가 어긋나지 않는다")
        #expect(ChessRules.perftDivide(.standard, depth: 0).isEmpty)
    }

    // MARK: - 불충분 기물

    @Test("불충분 기물 — 비숍이 **한 색 칸에만** 있으면 수가 몇이든 사국이다(FIDE 5.2.2)")
    func insufficientMaterialCoversSameColorBishopPiles() throws {
        // 어두운 칸 비숍만 가진 쪽은 밝은 칸의 왕을 어떤 수순으로도 공격할 수 없다 = 메이트가 불가능하다.
        // 이게 빠지면 즉시 무승부가 아니라 50수까지 끌려가고, 그 사이 깃발이 떨어지면 FIDE 가 무승부라고 하는
        // 판에서 한쪽이 **시간패로 진다**.
        let draws = [
            ("K+어두운 비숍 둘 vs 맨 왕", "4k3/8/8/8/8/B7/8/2B1K3 w - - 0 1"),
            ("K+어두운 비숍 셋 vs 맨 왕", "4k3/8/8/8/8/B3B3/8/2B1K3 w - - 0 1"),
            ("K+어두운 비숍 둘 vs K+어두운 비숍", "4kb2/8/8/8/8/B7/8/2B1K3 w - - 0 1")
        ]
        for (label, fen) in draws {
            let position = try #require(ChessPosition(fen: fen), "\(label)")
            #expect(ChessRules.hasInsufficientMaterial(position), "\(label)")
            #expect(ChessRules.outcome(position: position) == .insufficientMaterial, "\(label)")
        }

        // 기준선이 달라야 한다: 밝은 칸 비숍이 하나라도 섞이면 메이트가 가능하다.
        let mixed = try #require(ChessPosition(fen: "4k3/8/8/8/8/B7/8/3BK3 w - - 0 1"))
        #expect(ChessSquare("a3")!.isLightSquare == false)
        #expect(ChessSquare("d1")!.isLightSquare == true)
        #expect(!ChessRules.hasInsufficientMaterial(mixed))
        #expect(ChessRules.outcome(position: mixed) == nil)

        // 나이트가 섞이면 강제 메이트가 있는 자리가 있다.
        let withKnight = try #require(ChessPosition(fen: "4k3/8/8/8/8/B7/8/2B1KN2 w - - 0 1"))
        #expect(!ChessRules.hasInsufficientMaterial(withKnight))

        // 폰·룩·퀸이 하나라도 있으면 사국이 아니다(기존 기준선).
        let withPawn = try #require(ChessPosition(fen: "4k3/8/8/8/8/B7/4P3/2B1K3 w - - 0 1"))
        #expect(!ChessRules.hasInsufficientMaterial(withPawn))
    }
}
