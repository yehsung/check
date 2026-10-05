import Foundation

// FIDE 표준 체스 룰 — 국면 · 합법 수 생성 · 적용 · 판정. **순수 · 결정적 · Sendable, 전역 가변 상태 없음**.
//
// ── 왜 이 모양인가 ──
// 이 파일은 앞으로 셋이 **같은 답**을 내야 하는 자리의 하나뿐인 근거다: 기기 AI(한 국면을 여러 스레드가 동시에 센다),
// 서버 검증(상대가 보낸 수가 합법인지), 화면(둘 수 있는 칸 표시). 그래서 전부 값 타입이고 공유 가변 상태가 없다 —
// 한쪽이 들고 있는 국면을 다른 쪽이 고칠 길이 아예 없으면 "앱은 둘 수 있다는데 서버가 거절한다"가 생기지 않는다
// (오목에서 판정 상수가 앱·서버로 갈릴 뻔한 자리와 같은 이유다).
//
// ── 합격선은 perft 다 ──
// 규칙 하나를 말로 맞게 적는 것과 **모든 국면에서** 맞게 적는 것은 다르다. 캐슬링 경유 칸, 앙파상으로 열리는 왕,
// 승격 네 갈래는 글로 읽으면 다 맞아 보이고 수를 세면 갈린다. 그래서 알려진 정답이 있는 여섯 국면의 수 세기
// (Tests/checkTests/ChessPerftTests.swift)가 이 파일의 계약이다. 숫자가 틀리면 **엔진이 틀린 것이다** —
// 기대값을 고치지 말고 `ChessRules.perftDivide` 로 어느 첫 수에서 갈리는지 좁혀라.
//
// ── 내부 표현을 감춘 까닭 ──
// 공개 타입(ChessPosition · ChessMove)은 칸 이름과 말로 말하고, 수 세기를 버티는 1바이트 표현은 아래 엔진에만 있다.
// 화면·서버가 비트 배치를 알게 되면 표현을 바꿀 때마다 저쪽이 함께 깨진다.
//
// ── perft 가 **못** 잡는 것 ──
// 수 세기는 합법 수 생성만 잰다. 50수 · 3회 동형 반복 · 불충분 기물은 수가 아니라 **이력과 배치**의 판정이라
// 깊이를 늘려도 드러나지 않는다. 그 셋은 구체 기보로 못을 박았다(ChessRulesTests).

// MARK: - 공개 타입

/// 말 색. 백 선수.
package nonisolated enum ChessColor: String, Sendable, Codable, CaseIterable {
    case white, black

    package var opponent: ChessColor { self == .white ? .black : .white }
}

/// 말 종류.
package nonisolated enum ChessPieceKind: String, Sendable, Codable, CaseIterable {
    case pawn, knight, bishop, rook, queen, king

    /// FEN 글자(백 기준 대문자). SAN 의 말 글자도 이것이다 — 폰만 글자가 없다.
    package var fenLetter: Character {
        switch self {
        case .pawn: return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }

    /// SAN 에서 앞에 붙는 글자. 폰은 nil 이다(`e4` 는 `Pe4` 가 아니다).
    package var sanLetter: Character? { self == .pawn ? nil : fenLetter }

    package init?(fenLetter: Character) {
        switch fenLetter {
        case "P", "p": self = .pawn
        case "N", "n": self = .knight
        case "B", "b": self = .bishop
        case "R", "r": self = .rook
        case "Q", "q": self = .queen
        case "K", "k": self = .king
        default: return nil
        }
    }

    /// 승격으로 고를 수 있는 넷. 폰·킹은 고를 수 없다(FIDE 3.7e) — 이 목록이 생성기의 유일한 근거다.
    package static let promotionChoices: [ChessPieceKind] = [.queen, .rook, .bishop, .knight]
}

package nonisolated struct ChessPiece: Hashable, Sendable {
    package let color: ChessColor
    package let kind: ChessPieceKind

    package init(_ color: ChessColor, _ kind: ChessPieceKind) {
        self.color = color
        self.kind = kind
    }

    /// FEN 글자. 백은 대문자, 흑은 소문자.
    package var fenCharacter: Character {
        let letter = kind.fenLetter
        return color == .white ? letter : Character(String(letter).lowercased())
    }

    package init?(fenCharacter: Character) {
        guard let kind = ChessPieceKind(fenLetter: fenCharacter) else { return nil }
        self.init(fenCharacter.isUppercase ? .white : .black, kind)
    }
}

/// 칸. index 0 = a1, 7 = h1, 56 = a8, 63 = h8. **이 타입의 값은 언제나 판 안이다** — 판정 함수가 범위를 다시 묻지 않는 근거.
package nonisolated struct ChessSquare: Hashable, Sendable, Comparable {
    package let index: Int

    package init?(index: Int) {
        guard (0..<64).contains(index) else { return nil }
        self.index = index
    }

    package init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.index = rank * 8 + file
    }

    /// "e4" 같은 표기. 정규형 `^[a-h][1-8]$` **만** 받는다 — 대문자·공백을 받아 주면 앱과 서버 중 한쪽만
    /// 정규화하게 되고, 그때부터 둘은 같은 문자열을 다르게 읽는다(오목 좌표에서 확정한 것과 같은 규약).
    package init?(_ notation: String) {
        let scalars = Array(notation.unicodeScalars)
        guard scalars.count == 2 else { return nil }
        guard scalars[0].value >= 0x61, scalars[0].value <= 0x68 else { return nil }   // a…h
        guard scalars[1].value >= 0x31, scalars[1].value <= 0x38 else { return nil }   // 1…8
        self.init(file: Int(scalars[0].value - 0x61), rank: Int(scalars[1].value - 0x31))
    }

    package var file: Int { index & 7 }
    package var rank: Int { index >> 3 }

    package var notation: String {
        let fileCharacter = Character(UnicodeScalar(UInt8(0x61 + file)))
        return "\(fileCharacter)\(rank + 1)"
    }

    /// 칸 색. 불충분 기물의 '같은 색 비숍'을 재는 자리라 계산을 한 곳에만 둔다.
    package var isLightSquare: Bool { (file + rank) % 2 == 1 }

    package static func < (lhs: ChessSquare, rhs: ChessSquare) -> Bool { lhs.index < rhs.index }
}

/// 수. 캐슬링은 **킹의 두 칸 이동**으로 적는다(e1g1) — 룩 좌표를 수에 담으면 UCI 와 어긋난다.
package nonisolated struct ChessMove: Hashable, Sendable {
    package let from: ChessSquare
    package let to: ChessSquare
    /// 승격 말. 승격이 아닌 수에서는 nil 이어야 한다 — `.queen` 이 묻은 평수는 합법 수 목록에 없으므로 거절된다.
    package let promotion: ChessPieceKind?

    package init(from: ChessSquare, to: ChessSquare, promotion: ChessPieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }
}

/// 캐슬링 권리 넷. rawValue 비트는 FEN 글자 순서(K Q k q)와 같다 — 엔진이 이 비트를 그대로 들고 다닌다.
package nonisolated struct ChessCastlingRights: OptionSet, Hashable, Sendable {
    package let rawValue: UInt8

    package init(rawValue: UInt8) { self.rawValue = rawValue }

    package static let whiteKingside = ChessCastlingRights(rawValue: 1)
    package static let whiteQueenside = ChessCastlingRights(rawValue: 2)
    package static let blackKingside = ChessCastlingRights(rawValue: 4)
    package static let blackQueenside = ChessCastlingRights(rawValue: 8)
    package static let all: ChessCastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]

    package static func kingside(_ color: ChessColor) -> ChessCastlingRights {
        color == .white ? .whiteKingside : .blackKingside
    }

    package static func queenside(_ color: ChessColor) -> ChessCastlingRights {
        color == .white ? .whiteQueenside : .blackQueenside
    }

    /// FEN 3번째 칸. 비면 "-".
    package var fenText: String {
        var text = ""
        if contains(.whiteKingside) { text += "K" }
        if contains(.whiteQueenside) { text += "Q" }
        if contains(.blackKingside) { text += "k" }
        if contains(.blackQueenside) { text += "q" }
        return text.isEmpty ? "-" : text
    }

    /// FEN 글자열을 읽는다. 중복 글자·모르는 글자·**빈 칸**은 nil — 손상된 권리를 "대충 읽으면" 둘 수 없는
    /// 캐슬링을 보여 준다. 빈 칸을 특히 막는 까닭: '권리 없음'은 `-` 로만 적는다. 빈 글자열을 [](권리 넷 다 없음)
    /// 으로 읽어 주면 DB 칸·네트워크 필드의 빈 값이 그대로 통과해, **둘 수 있는 캐슬링이 조용히 사라진다**
    /// (`ChessPosition(fen:)` 경로는 split 이 빈 칸을 지워 안 닿지만 이건 package API 다).
    package static func parse(fen text: String) -> ChessCastlingRights? {
        if text == "-" { return [] }
        guard !text.isEmpty else { return nil }
        var rights: ChessCastlingRights = []
        for character in text {
            let bit: ChessCastlingRights
            switch character {
            case "K": bit = .whiteKingside
            case "Q": bit = .whiteQueenside
            case "k": bit = .blackKingside
            case "q": bit = .blackQueenside
            default: return nil
            }
            if rights.contains(bit) { return nil }
            rights.insert(bit)
        }
        return rights
    }
}

/// 국면. 값 타입이고 Hashable 이라 사전 키로도 쓸 수 있지만, **반복 판정에는 `repetitionKey` 를 써라** —
/// 50수 카운터와 수 번호는 동형 반복 판정에 들어가지 않는다(FIDE 9.2: 배치 + 차례 + 캐슬링 권리 + 앙파상 가능성).
package nonisolated struct ChessPosition: Hashable, Sendable {
    /// 64칸 내부 표현. 읽기·쓰기는 `subscript` 로만 — 비트 배치는 이 모듈 밖으로 새지 않는다.
    var cells: ContiguousArray<UInt8>
    package var sideToMove: ChessColor
    package var castlingRights: ChessCastlingRights
    /// 앙파상으로 **잡을 수 있는 칸**(직전 두 칸 전진이 지나간 칸). FEN 4번째 칸과 같은 뜻이고, 두 칸 전진
    /// 바로 다음 수에만 값이 있다 — 그 한 수가 지나면 엔진이 nil 로 지운다("그 수 한 번만" 규칙의 전부다).
    package var enPassantTarget: ChessSquare?
    /// 50수 규칙의 반수 카운터. 폰 이동·잡기에서 0 으로 돌아간다.
    package var halfmoveClock: Int
    package var fullmoveNumber: Int

    init(cells: ContiguousArray<UInt8>,
         sideToMove: ChessColor,
         castlingRights: ChessCastlingRights,
         enPassantTarget: ChessSquare?,
         halfmoveClock: Int,
         fullmoveNumber: Int) {
        self.cells = cells
        self.sideToMove = sideToMove
        self.castlingRights = castlingRights
        self.enPassantTarget = enPassantTarget
        self.halfmoveClock = halfmoveClock
        self.fullmoveNumber = fullmoveNumber
    }

    /// 빈 판(백 차례 · 권리 없음). 테스트가 칸을 하나씩 놓아 국면을 짜는 자리다 —
    /// 여기서 만든 국면은 **검증을 거치지 않는다**(왕이 없을 수도 있다). 그럴 때 `legalMoves` 는 빈 배열이다.
    package static let empty = ChessPosition(
        cells: ContiguousArray(repeating: 0, count: 64),
        sideToMove: .white, castlingRights: [], enPassantTarget: nil,
        halfmoveClock: 0, fullmoveNumber: 1)

    /// 초기 배치. FEN 파서를 타므로 파서가 깨지면 이 값부터 죽는다 — 그게 의도다(조용히 다른 판으로 시작하는 것보다 낫다).
    package static let standard = ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")!

    package subscript(square: ChessSquare) -> ChessPiece? {
        get { ChessCode.piece(cells[square.index]) }
        set { cells[square.index] = newValue.map(ChessCode.code) ?? ChessCode.empty }
    }

    /// 그 색 왕이 선 칸. 없으면 nil(검증을 거치지 않은 국면).
    package func kingSquare(of color: ChessColor) -> ChessSquare? {
        let wanted = ChessCode.king | (color == .black ? ChessCode.blackBit : 0)
        for index in 0..<64 where cells[index] == wanted { return ChessSquare(index: index) }
        return nil
    }

    /// 판에 있는 말 전부(칸 순서 a1→h8).
    package var pieces: [(square: ChessSquare, piece: ChessPiece)] {
        (0..<64).compactMap { index in
            guard let piece = ChessCode.piece(cells[index]), let square = ChessSquare(index: index) else { return nil }
            return (square, piece)
        }
    }

    /// FEN 이 받아 주는 수 번호의 위쪽 한계. 한계가 있어야 하는 까닭은 세기가 아니라 **넘침**이다:
    /// `Int.max` 를 담은 FEN 을 받아들이면 그 국면에 수를 묻는 순간 `halfmove + 1` 이 Int 를 넘겨 프로세스가
    /// 그 자리에서 죽는다. "성립하지 않는 국면은 nil" 이라고 약속한 파서가 받아들인 뒤 죽는 건 계약 위반이다.
    /// 값은 이론상 가장 긴 대국(약 6천 수)보다 넉넉하다.
    package static let maxFullmoveNumber = 10_000

    /// 엔진이 셀 수 있는 카운터의 위쪽 한계. 파서 한계보다 훨씬 크게 둔 까닭: 손으로 짠 판이나 아주 긴 재생에서
    /// 엔진이 조용히 멈추지 않게, 그러나 더하면 넘치는 자리에서는 반드시 멈추게.
    static let maxCountableCounter = 1_000_000_000

    /// 카운터가 엔진이 **더해도 넘치지 않는** 범위인가. 엔진이 서기 전에 보는 자리다 —
    /// 손으로 짠 판은 파서를 거치지 않으므로(`halfmoveClock` 은 package var) 여기가 마지막 그물이다.
    var hasCountableCounters: Bool {
        halfmoveClock >= 0 && halfmoveClock <= Self.maxCountableCounter
            && fullmoveNumber >= 1 && fullmoveNumber <= Self.maxCountableCounter
    }

    /// 카운터가 **한 판에서 실제로 나올 수 있는 값**인가(파서가 보는 자리).
    ///
    /// 둘을 본다. ① 반수는 지금까지 둔 반수를 넘을 수 없다 — 1수째 백 차례의 반수 100 은 어떤 대국에도 없고,
    /// 그 국면은 **즉시 50수 무승부**로 판정된다. ② 앙파상 칸이 있으면 직전 수가 폰 두 칸 전진이므로 반수는 0 이다 —
    /// `… e3 99 1` 은 글자열이 자기와 어긋나는데도 읽히면 다음 조용한 수에 무승부가 된다.
    /// 거짓 반수는 **불법 무승부를 합법으로** 만든다: 파서가 거짓 앙파상 칸을 막는 것과 같은 모양의 구멍이라
    /// 같은 자리에서 함께 막는다.
    package var hasReachableCounters: Bool {
        guard halfmoveClock >= 0, fullmoveNumber >= 1, fullmoveNumber <= Self.maxFullmoveNumber else { return false }
        let playedHalfmoves = (fullmoveNumber - 1) * 2 + (sideToMove == .white ? 0 : 1)
        guard halfmoveClock <= playedHalfmoves else { return false }
        if enPassantTarget != nil, halfmoveClock != 0 { return false }
        return true
    }
}

/// 끝난 판의 결과. nil(아직 안 끝남)은 `ChessRules.outcome` 의 반환값으로 말한다.
package nonisolated enum ChessOutcome: Equatable, Sendable {
    case checkmate(winner: ChessColor)
    case stalemate
    /// 불충분 기물(FIDE 5.2.2 의 '사국'). 기준은 `ChessRules.hasInsufficientMaterial` 하나다 —
    /// 작은 말이 하나뿐이거나, 나이트가 없고 비숍이 **전부 한 색 칸**에 있을 때(개수를 묻지 않는다).
    case insufficientMaterial
    case fiftyMoveRule
    case threefoldRepetition

    package var isDraw: Bool {
        switch self {
        case .checkmate: return false
        case .stalemate, .insufficientMaterial, .fiftyMoveRule, .threefoldRepetition: return true
        }
    }

    package var winner: ChessColor? {
        if case .checkmate(let winner) = self { return winner }
        return nil
    }
}

/// 수 하나가 판에 남기는 것 전부. 화면과 서버가 이걸 보고 움직인다 —
/// **앙파상은 도착 칸이 아닌 칸의 폰을 집어가고, 캐슬링은 룩도 함께 움직인다**. 도착 칸만 보고 그리면
/// 잡힌 폰이 판에 남아 보이고 룩이 제자리에 남는다.
package nonisolated struct ChessMoveEffect: Hashable, Sendable {
    package let move: ChessMove
    package let piece: ChessPiece
    package let captured: ChessPiece?
    package let capturedSquare: ChessSquare?
    /// 캐슬링일 때 룩이 간 길.
    package let rookMove: ChessMove?
    package let isEnPassant: Bool
    package let isDoublePawnPush: Bool
    package let isCastling: Bool
    package let isPromotion: Bool
    package let after: ChessPosition
}

// MARK: - 규칙

package nonisolated enum ChessRules {
    /// 합법 수 전부. 순서는 **결정적이다**(칸 a1→h8 · 방향 고정 순서 · 승격은 Q R B N) — AI 의 수 정렬과
    /// 서버 재현이 같은 순서를 믿는다. 왕이 없는(검증 안 된) 국면이면 빈 배열이다.
    package static func legalMoves(in position: ChessPosition) -> [ChessMove] {
        guard var engine = ChessEngine(position: position) else { return [] }
        return engine.legalRawMoves().map { $0.move }
    }

    /// 차례인 쪽이 체크인가.
    package static func isInCheck(_ position: ChessPosition) -> Bool {
        isInCheck(position, color: position.sideToMove)
    }

    package static func isInCheck(_ position: ChessPosition, color: ChessColor) -> Bool {
        guard var engine = ChessEngine(position: position) else { return false }
        return engine.isAttacked(engine.kings[color == .white ? 0 : 1], byBlack: color == .white)
    }

    /// 수를 적용한 국면. **합법 수가 아니면 nil** — 서버 검증이 이 nil 하나로 끝나야 한다.
    package static func apply(_ move: ChessMove, to position: ChessPosition) -> ChessPosition? {
        guard var engine = ChessEngine(position: position), let raw = engine.matchingLegalMove(move) else { return nil }
        _ = engine.make(raw)
        return engine.position
    }

    /// 수가 판에 남기는 것 전부(불법이면 nil).
    package static func effect(of move: ChessMove, in position: ChessPosition) -> ChessMoveEffect? {
        guard var engine = ChessEngine(position: position), let raw = engine.matchingLegalMove(move) else { return nil }
        let moved = ChessCode.piece(engine.cells[raw.from])!
        let undo = engine.make(raw)
        return ChessMoveEffect(
            move: raw.move,
            piece: moved,
            captured: ChessCode.piece(undo.captured),
            capturedSquare: undo.captured == ChessCode.empty ? nil : ChessSquare(index: undo.capturedSquare),
            rookMove: undo.rookFrom < 0 ? nil : ChessMove(from: ChessSquare(index: undo.rookFrom)!,
                                                          to: ChessSquare(index: undo.rookTo)!),
            isEnPassant: raw.flags & ChessRawMove.enPassant != 0,
            isDoublePawnPush: raw.flags & ChessRawMove.doublePush != 0,
            isCastling: raw.flags & ChessRawMove.castling != 0,
            isPromotion: raw.promotion != 0,
            after: engine.position)
    }

    /// 판정. `repetitionCounts` 는 **`repetitionKey` → 그 국면이 이 판에서 나온 횟수**(지금 국면까지 포함)다 —
    /// 이력은 호출자가 들고 있으므로(서버는 수 목록, 앱은 진행 중 판) 여기서 세지 않는다. 안 넘기면 반복은 보지 않는다.
    ///
    /// 순서가 규칙이다: 수가 없으면 체크메이트/스테일메이트가 **먼저**다. 100번째 반수가 메이트면 그건 메이트다
    /// (FIDE 9.3 — 무승부 주장보다 메이트가 앞선다). 그다음 사국(불충분 기물) → 50수 → 3회 반복.
    ///
    /// 체스판으로 **성립하지 않는 판은 판정이 없다**(nil). 이 가드가 첫 줄에 있어야 하는 까닭: 엔진이 서지 않는
    /// 판에서 `legalMoves` 는 [] 이고 `isInCheck` 는 false 라, 아래 첫 분기가 '수 없음 + 체크 아님 = 스테일메이트'로
    /// 떨어진다. 그래서 왕이 없는 판·왕이 둘인 판이 **무승부**로 판정됐다 — 문서가 적은 안전망(왕이 없으면
    /// legalMoves 는 [])이 거짓 무승부를 만드는 자리였다. 성립하지 않는 입력에 '무승부'를 주는 건 nil 보다 나쁘다.
    package static func outcome(position: ChessPosition, repetitionCounts: [String: Int] = [:]) -> ChessOutcome? {
        guard ChessEngine(position: position) != nil else { return nil }
        if legalMoves(in: position).isEmpty {
            return isInCheck(position) ? .checkmate(winner: position.sideToMove.opponent) : .stalemate
        }
        if hasInsufficientMaterial(position) { return .insufficientMaterial }
        if position.halfmoveClock >= 100 { return .fiftyMoveRule }
        if (repetitionCounts[position.repetitionKey] ?? 0) >= 3 { return .threefoldRepetition }
        return nil
    }

    /// 불충분 기물 — **FIDE 5.2.2 의 사국**(어떤 수순으로도 메이트가 나올 수 없는 배치)이다. 기준은 셋이다:
    ///  · 폰·룩·퀸이 없고 작은 말이 아예 없다(왕 vs 왕)
    ///  · 작은 말이 판 전체에 하나다(왕+비숍 vs 왕 · 왕+나이트 vs 왕)
    ///  · 나이트가 없고 비숍이 **전부 한 색 칸**에 있다 — 개수와 소속을 묻지 않는다
    ///
    /// 셋째가 개수를 보지 않는 까닭: 어두운 칸 비숍은 밝은 칸의 왕을 영원히 공격할 수 없고, 왕을 가두는 데 필요한
    /// 밝은 칸들은 그 비숍들로 채울 수도 없다(왕의 직교 이웃 넷은 반대 색이다). 그래서 비숍이 둘·셋이어도,
    /// 양쪽이 나눠 가져도 메이트가 없다. 예전 구현은 `bishops == [1, 1]` 한 짝만 색을 봐서 비숍이 둘 이상이면
    /// 통째로 아니라고 답했고, 그 결과 FIDE 가 무승부라고 하는 판이 50수(100 반수)까지 끌려갔다 —
    /// 그 사이 5분+3초 시계의 깃발이 먼저 떨어지면 한쪽이 **시간패로 진다**.
    ///
    /// 나이트 둘(왕+N+N vs 왕)은 들어가지 않는다: 메이트가 나오는 자리가 있어 사국이 아니다.
    package static func hasInsufficientMaterial(_ position: ChessPosition) -> Bool {
        var knights = 0
        var lightBishops = 0
        var darkBishops = 0
        for index in 0..<64 {
            let cell = position.cells[index]
            guard cell != ChessCode.empty else { continue }
            switch cell & ChessCode.kindMask {
            case ChessCode.king: continue
            case ChessCode.knight: knights += 1
            case ChessCode.bishop:
                if ChessSquare(index: index)!.isLightSquare { lightBishops += 1 } else { darkBishops += 1 }
            default: return false   // 폰·룩·퀸이 하나라도 있으면 사국이 아니다
            }
        }
        if knights + lightBishops + darkBishops <= 1 { return true }   // 왕vs왕 · 작은 말 하나
        return knights == 0 && (lightBishops == 0 || darkBishops == 0)  // 비숍이 한 색 칸에만
    }

    /// `color` 쪽 기물로 **메이트가 나올 수 없는가**. 시간패의 FIDE 6.9 판정(`timeoutRuling`)이 묻는 질문이고,
    /// 사국(`hasInsufficientMaterial`)과 달리 **한쪽 기물만** 본다 — 깃발이 떨어졌을 때 지는지 무승부인지는
    /// 시간이 남은 쪽이 메이트를 낼 수 있는가로 갈린다.
    ///
    /// 기물만 보고 탐색하지 않는 까닭: 상대가 자기 말로 자기 왕을 막아 주는 수순(helpmate)까지 세면 판마다
    /// 탐색이 필요하고, 중재자도 기물로 가른다. 그래서 폰·룩·퀸이 없고 작은 말이 없거나(맨 왕) 나이트 하나거나
    /// 비숍이 한 색 칸에만 있을 때 "메이트할 기물이 없다"고 본다(나이트 둘·양 색 비숍·비숍+나이트는 메이트가 있다).
    package static func hasNoMatingMaterial(_ position: ChessPosition, color: ChessColor) -> Bool {
        let mine: UInt8 = color == .black ? ChessCode.blackBit : 0
        var knights = 0
        var lightBishops = 0
        var darkBishops = 0
        for index in 0..<64 {
            let cell = position.cells[index]
            guard cell != ChessCode.empty, (cell & ChessCode.blackBit) == mine else { continue }
            switch cell & ChessCode.kindMask {
            case ChessCode.king: continue
            case ChessCode.knight: knights += 1
            case ChessCode.bishop:
                if ChessSquare(index: index)!.isLightSquare { lightBishops += 1 } else { darkBishops += 1 }
            default: return false   // 폰·룩·퀸이 있으면 메이트가 있다
            }
        }
        if knights + lightBishops + darkBishops == 0 { return true }          // 맨 왕
        if knights == 1, lightBishops + darkBishops == 0 { return true }      // 왕 + 나이트 하나
        return knights == 0 && (lightBishops == 0 || darkBishops == 0)        // 왕 + 한 색 칸 비숍만
    }

    /// 지금 **실제로** 앙파상으로 잡을 수 있는가. `enPassantTarget` 이 있어도 그 폰을 잡는 수가 합법이 아니면
    /// (잡을 폰이 없거나, 잡으면 자기 왕이 열리거나) 동형 반복에서 두 국면은 **같은** 국면이다(FIDE 9.2 의 '가능성').
    package static func hasLegalEnPassantCapture(in position: ChessPosition) -> Bool {
        guard let target = position.enPassantTarget else { return false }
        guard var engine = ChessEngine(position: position) else { return false }
        return engine.legalRawMoves().contains { $0.flags & ChessRawMove.enPassant != 0 && $0.to == target.index }
    }

    /// 수 세기. depth 0 은 1(국면 자신), **음수는 0**이다.
    /// 음수를 0 으로 가르는 까닭: 깊이를 계산해서 넘기는 탐색 쪽에서 깊이가 0 아래로 내려가는 사고가 생겼을 때,
    /// 1 을 내면 '노드 하나'로 보고돼 그 자리에서 안 터지고 수 세기 합계만 틀린다. `perftDivide` 도 음수에서
    /// [] 를 내므로 둘의 경계가 같은 말을 한다.
    package static func perft(_ position: ChessPosition, depth: Int) -> Int {
        guard depth >= 0 else { return 0 }
        guard depth > 0 else { return 1 }
        guard var engine = ChessEngine(position: position) else { return 0 }
        var buffer: [ChessRawMove] = []
        buffer.reserveCapacity(64 * max(depth, 1))
        return engine.perft(depth: depth, buffer: &buffer)
    }

    /// 첫 수별 하위 노드 수(UCI 사전 순). perft 가 어긋났을 때 **어느 수에서 갈렸는지** 좁히는 표준 도구다 —
    /// 정답 엔진의 divide 와 나란히 놓으면 틀린 가지가 한 줄로 드러난다.
    package static func perftDivide(_ position: ChessPosition, depth: Int) -> [(move: ChessMove, nodes: Int)] {
        guard depth > 0, var engine = ChessEngine(position: position) else { return [] }
        var buffer: [ChessRawMove] = []
        buffer.reserveCapacity(64 * max(depth, 1))
        var rows: [(move: ChessMove, nodes: Int)] = []
        for raw in engine.legalRawMoves() {
            let undo = engine.make(raw)
            rows.append((raw.move, depth == 1 ? 1 : engine.perft(depth: depth - 1, buffer: &buffer)))
            engine.unmake(undo)
        }
        return rows.sorted { $0.move.uci < $1.move.uci }
    }
}

// MARK: - 시계 (5분 + 한 수 3초 가산 — 사용자 확정)

/// 한 수를 둔 뒤의 시계 — **세 갈래**다. 하나의 nil 로 '시간패'와 '성립하지 않는 입력'을 둘 다 말하면,
/// 음수 elapsed 한 번이 사람을 시간패로 끝낸다. 음수는 드문 값이 아니다: 서버가 `now − moveStartedAt` 을 셀 때
/// 시계 밀림·요청 재시도로 평범하게 나온다. 진짜 시간패에서는 둘이 같은 말을 하므로(경계 테스트로는 안 갈린다)
/// 타입으로 갈라 둔다.
package nonisolated enum ChessClockStep: Hashable, Sendable {
    /// 시간이 남았다 — 가산이 붙은 시계.
    case ticked(ChessClock)
    /// 남은 시간을 넘겨 썼다. 결과(패·무승부)는 기물까지 봐야 갈린다 → `ChessRules.timeoutRuling`(FIDE 6.9).
    case flagged
    /// elapsed 가 초 단위 시간이 아니다(음수 · NaN · 무한). **시간패가 아니다** — 호출자는 다시 재야 한다.
    case invalidElapsed

    /// 시간이 남았을 때의 시계(그 밖에는 nil).
    package var clock: ChessClock? {
        guard case .ticked(let clock) = self else { return nil }
        return clock
    }
}

/// 깃발이 떨어졌을 때의 결과 — **FIDE 6.9**. 시간은 시계가 재지만 결과는 기물이 가른다: 상대가 어떤 수순으로도
/// 메이트할 수 없으면 무승부다. 시계는 기물을 보지 않고 `ChessOutcome` 에는 시간이 없으므로 둘을 묶는 자리가
/// 없었고, 그래서 자연스러운 호출(깃발 → 패)이 FIDE 가 무승부라고 하는 판을 패배로 만들었다.
/// 5분+3초 블리츠에서 실제로 닿는 모양이다(한쪽이 기물을 다 잃고 상대에게 비숍·나이트 하나만 남은 끝내기).
package nonisolated enum ChessTimeoutRuling: Hashable, Sendable {
    /// 깃발이 떨어진 쪽의 패.
    case loss(flagged: ChessColor)
    /// 상대가 메이트할 기물이 없다 — 무승부(FIDE 6.9).
    case drawByInsufficientMaterial

    package var isDraw: Bool { self == .drawByInsufficientMaterial }

    package var winner: ChessColor? {
        guard case .loss(let flagged) = self else { return nil }
        return flagged.opponent
    }
}

extension ChessRules {
    /// 깃발이 떨어진 판의 판정(FIDE 6.9). `flagged` 는 시간을 다 쓴 쪽이다.
    /// `ChessOutcome` 과 따로 두는 까닭은 그대로다(판은 배치로, 시계는 흐른 시간으로 판정한다) —
    /// 다만 **그 둘을 함께 읽어야 하는 한 자리**가 여기다.
    package static func timeoutRuling(position: ChessPosition, flagged: ChessColor) -> ChessTimeoutRuling {
        hasNoMatingMaterial(position, color: flagged.opponent) ? .drawByInsufficientMaterial : .loss(flagged: flagged)
    }
}

/// 1:1 체스 시계. 값 타입이고 단위는 **초**다. 시간패는 수가 아니라 시계가 판정하므로 `ChessOutcome` 에 없다 —
/// 판정 주체가 다르다(판은 배치로, 시계는 흐른 시간으로). 섞으면 "둘 수 없는데 시간이 남았다"가 생긴다.
/// 깃발이 떨어진 뒤의 결과는 기물까지 봐야 하므로 `ChessRules.timeoutRuling` 이 그 한 자리다.
package nonisolated struct ChessClock: Hashable, Sendable {
    /// 기본 설정(사용자 확정 2026-10-05): 5분 + 한 수 3초 가산.
    package static let initialSeconds: Double = 300
    package static let incrementSeconds: Double = 3

    package var whiteSeconds: Double
    package var blackSeconds: Double
    package let incrementSeconds: Double

    package init(initialSeconds: Double = ChessClock.initialSeconds,
                 incrementSeconds: Double = ChessClock.incrementSeconds) {
        whiteSeconds = initialSeconds
        blackSeconds = initialSeconds
        self.incrementSeconds = incrementSeconds
    }

    package func remaining(_ color: ChessColor) -> Double {
        color == .white ? whiteSeconds : blackSeconds
    }

    /// `elapsed` 초를 쓰고 수를 둔 뒤의 시계. 남은 시간을 넘겨 썼으면 `.flagged`,
    /// elapsed 가 애초에 시간이 아니면 `.invalidElapsed` 다 — **둘은 다른 결과다**(`ChessClockStep` 참고).
    /// 가산을 먼저 더하지 않는 까닭: 먼저 더하면 넘겨 쓴 시간이 0 아래로 안 내려가 시간패가 가려진다
    /// (가산은 수를 **둔 뒤에만** 붙는다).
    package func afterMove(by color: ChessColor, elapsed: Double) -> ChessClockStep {
        guard elapsed.isFinite, elapsed >= 0 else { return .invalidElapsed }
        guard elapsed <= remaining(color) else { return .flagged }
        var next = self
        let left = remaining(color) - elapsed + incrementSeconds
        if color == .white { next.whiteSeconds = left } else { next.blackSeconds = left }
        return .ticked(next)
    }

    /// 아직 두지 않은 쪽이 `elapsed` 초를 썼을 때 시간패인가. **nil 은 '성립하지 않는 입력'** 이다(음수·NaN·무한).
    /// `afterMove` 와 **같은 답**을 해야 하는 자리다: 한쪽은 "시간패"라 하고 한쪽은 "살아 있다"고 하면,
    /// 둘을 함께 읽는 호출자가 어느 쪽을 믿든 한 번은 사람을 잘못 끝낸다(음수 elapsed 에서 실제로 갈렸다).
    package func hasFlagged(_ color: ChessColor, elapsed: Double) -> Bool? {
        guard elapsed.isFinite, elapsed >= 0 else { return nil }
        return elapsed > remaining(color)
    }
}

// MARK: - 내부 표현

/// 칸 값: 0 빈칸, 하위 3비트 종류(1 폰 · 2 나이트 · 3 비숍 · 4 룩 · 5 퀸 · 6 킹), 비트 3 색(0 백 · 8 흑).
/// 이 배치가 공격 판정의 한 줄 비교(`cells[t] == knight | attacker`)를 가능하게 한다 — 종류와 색을 따로 꺼내 비교하면
/// 깊이 4 수 세기에서만 수백만 번을 더 센다(이 파일에서 유일하게 속도를 보고 고른 자리다).
enum ChessCode {
    static let empty: UInt8 = 0
    static let pawn: UInt8 = 1
    static let knight: UInt8 = 2
    static let bishop: UInt8 = 3
    static let rook: UInt8 = 4
    static let queen: UInt8 = 5
    static let king: UInt8 = 6
    static let blackBit: UInt8 = 8
    static let kindMask: UInt8 = 7

    static let promotionCodes: [UInt8] = [queen, rook, bishop, knight]

    static func code(_ kind: ChessPieceKind) -> UInt8 {
        switch kind {
        case .pawn: return pawn
        case .knight: return knight
        case .bishop: return bishop
        case .rook: return rook
        case .queen: return queen
        case .king: return king
        }
    }

    static func code(_ piece: ChessPiece) -> UInt8 {
        code(piece.kind) | (piece.color == .black ? blackBit : 0)
    }

    static func kind(_ cell: UInt8) -> ChessPieceKind? {
        switch cell & kindMask {
        case pawn: return .pawn
        case knight: return .knight
        case bishop: return .bishop
        case rook: return .rook
        case queen: return .queen
        case king: return .king
        default: return nil
        }
    }

    static func piece(_ cell: UInt8) -> ChessPiece? {
        guard cell != empty, let kind = kind(cell) else { return nil }
        return ChessPiece((cell & blackBit) == 0 ? .white : .black, kind)
    }
}

/// 미리 깐 이동표. 판 경계를 **표에서 미리 뺐다** — 생성기와 공격 판정이 좌표 범위를 다시 묻지 않는다
/// (묻는 자리가 둘이면 한쪽만 틀리고, 그 틀림은 깊이 3 넘어서야 수 세기로 드러난다).
enum ChessTables {
    /// 칸당 최대 8칸, 뒤는 -1 로 끝난다.
    static let knight: [Int8] = hops([(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)])
    static let king: [Int8] = hops([(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)])

    /// 방향 0…3 직선(룩·퀸), 4…7 대각(비숍·퀸). **공격 판정이 이 순서를 믿는다**.
    static let rayDeltas: [(Int, Int)] = [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (1, -1), (-1, 1), (-1, -1)]

    /// `rays[(square * 8 + direction) * 7 + step]`. 각 줄은 -1 로 끝난다.
    static let rays: [Int8] = {
        var table = [Int8](repeating: -1, count: 64 * 8 * 7)
        for square in 0..<64 {
            let file = square & 7
            let rank = square >> 3
            for (direction, delta) in rayDeltas.enumerated() {
                var step = 0
                var nextFile = file + delta.0
                var nextRank = rank + delta.1
                while (0..<8).contains(nextFile), (0..<8).contains(nextRank) {
                    table[(square * 8 + direction) * 7 + step] = Int8(nextRank * 8 + nextFile)
                    step += 1
                    nextFile += delta.0
                    nextRank += delta.1
                }
            }
        }
        return table
    }()

    /// 폰이 잡는 두 쪽(파일 증감). 호출마다 배열을 새로 만들지 않으려고 표로 둔다.
    static let pawnCaptureSides: [Int] = [-1, 1]

    private static func hops(_ deltas: [(Int, Int)]) -> [Int8] {
        var table = [Int8](repeating: -1, count: 64 * 8)
        for square in 0..<64 {
            let file = square & 7
            let rank = square >> 3
            var slot = 0
            for delta in deltas {
                let nextFile = file + delta.0
                let nextRank = rank + delta.1
                guard (0..<8).contains(nextFile), (0..<8).contains(nextRank) else { continue }
                table[square * 8 + slot] = Int8(nextRank * 8 + nextFile)
                slot += 1
            }
        }
        return table
    }
}

/// 엔진 안에서 도는 수. 공개 `ChessMove` 로는 담을 수 없는 것(두 칸 전진·앙파상·캐슬링 표시)을 비트로 들고 다닌다 —
/// 적용할 때 "이게 앙파상이었나"를 다시 추론하면 추론 규칙이 두 군데가 된다.
struct ChessRawMove: Hashable {
    static let doublePush: UInt8 = 1
    static let enPassant: UInt8 = 2
    static let castling: UInt8 = 4

    var from: Int
    var to: Int
    var promotion: UInt8
    var flags: UInt8

    var move: ChessMove {
        ChessMove(from: ChessSquare(index: from)!, to: ChessSquare(index: to)!,
                  promotion: promotion == 0 ? nil : ChessCode.kind(promotion))
    }
}

/// 되돌리기표. 수 세기는 국면을 복사하지 않고 제자리에서 두고 되돌린다(복사하면 노드마다 64바이트 + COW 검사다).
struct ChessUndo {
    var move: ChessRawMove
    var captured: UInt8
    var capturedSquare: Int
    var castling: UInt8
    var enPassant: Int
    var halfmove: Int
    var fullmove: Int
    var rookFrom: Int
    var rookTo: Int
}

// MARK: - 엔진

struct ChessEngine {
    var cells: ContiguousArray<UInt8>
    /// 0 백 · 1 흑.
    var side: UInt8
    var castling: UInt8
    /// 앙파상 칸(없으면 -1).
    var enPassant: Int
    var halfmove: Int
    var fullmove: Int
    /// [백 왕 칸, 흑 왕 칸]. 왕을 찾는 일을 수마다 하지 않으려고 들고 다닌다 — 두고 되돌릴 때 함께 고친다.
    var kings: [Int]

    /// 왕이 양쪽에 **하나씩 있어야** 엔진이 선다. 없으면 nil 이다 — 왕 없는 판에서 공격 판정은 뜻이 없고,
    /// 범위를 벗어난 칸을 읽어 엉뚱한 값을 내는 길을 아예 막는다.
    ///
    /// 카운터도 같은 자리에서 본다: 더하면 넘치는 값(Int.max 같은)으로는 **돌지 않는다**. 받아들이면 첫 수에서
    /// `halfmove + 1` 이 Int 를 넘겨 프로세스가 죽기 때문이다 — 수를 내지 않는 쪽이 낫다. FEN 파서는 이보다
    /// 먼저, 더 좁게(한 판에서 나올 수 있는 값만) 거절하므로 여기까지 오는 건 손으로 짠 판뿐이다.
    init?(position: ChessPosition) {
        guard position.hasCountableCounters else { return nil }
        cells = position.cells
        side = position.sideToMove == .white ? 0 : 1
        castling = position.castlingRights.rawValue
        enPassant = position.enPassantTarget?.index ?? -1
        halfmove = position.halfmoveClock
        fullmove = position.fullmoveNumber
        var found = [-1, -1]
        for square in 0..<64 where (cells[square] & ChessCode.kindMask) == ChessCode.king {
            let index = (cells[square] & ChessCode.blackBit) == 0 ? 0 : 1
            guard found[index] < 0 else { return nil }   // 왕이 둘이면 판정이 뜻을 잃는다
            found[index] = square
        }
        guard found[0] >= 0, found[1] >= 0 else { return nil }
        kings = found
    }

    var position: ChessPosition {
        ChessPosition(cells: cells,
                      sideToMove: side == 0 ? .white : .black,
                      castlingRights: ChessCastlingRights(rawValue: castling),
                      enPassantTarget: enPassant >= 0 ? ChessSquare(index: enPassant) : nil,
                      halfmoveClock: halfmove,
                      fullmoveNumber: fullmove)
    }

    // MARK: 공격 판정

    /// `square` 가 `byBlack` 쪽 말에게 공격받는가. 캐슬링의 경유 칸 검사도 이 함수 하나로 한다.
    func isAttacked(_ square: Int, byBlack: Bool) -> Bool {
        let attacker: UInt8 = byBlack ? ChessCode.blackBit : 0
        let file = square & 7
        let rank = square >> 3

        // 폰: 흑 폰은 아래로 잡으므로 square 의 **윗** 줄에, 백 폰은 아랫 줄에 있다.
        let pawnRank = rank + (byBlack ? 1 : -1)
        if pawnRank >= 0, pawnRank < 8 {
            let wanted = ChessCode.pawn | attacker
            if file > 0, cells[pawnRank * 8 + file - 1] == wanted { return true }
            if file < 7, cells[pawnRank * 8 + file + 1] == wanted { return true }
        }

        let wantedKnight = ChessCode.knight | attacker
        for slot in 0..<8 {
            let target = ChessTables.knight[square * 8 + slot]
            if target < 0 { break }
            if cells[Int(target)] == wantedKnight { return true }
        }

        let wantedKing = ChessCode.king | attacker
        for slot in 0..<8 {
            let target = ChessTables.king[square * 8 + slot]
            if target < 0 { break }
            if cells[Int(target)] == wantedKing { return true }
        }

        for direction in 0..<8 {
            let slider: UInt8 = direction < 4 ? ChessCode.rook : ChessCode.bishop
            let base = (square * 8 + direction) * 7
            for step in 0..<7 {
                let target = ChessTables.rays[base + step]
                if target < 0 { break }
                let occupant = cells[Int(target)]
                if occupant == ChessCode.empty { continue }
                if (occupant & ChessCode.blackBit) == attacker {
                    let kind = occupant & ChessCode.kindMask
                    if kind == slider || kind == ChessCode.queen { return true }
                }
                break   // 말에 막혔다 — 이 줄은 끝
            }
        }
        return false
    }

    // MARK: 생성

    /// 유사 합법 수(자기 왕이 열리는지는 아직 안 본다).
    func generate(into moves: inout [ChessRawMove]) {
        let me: UInt8 = side == 0 ? 0 : ChessCode.blackBit
        for square in 0..<64 {
            let cell = cells[square]
            guard cell != ChessCode.empty, (cell & ChessCode.blackBit) == me else { continue }
            switch cell & ChessCode.kindMask {
            case ChessCode.pawn: generatePawn(square, me: me, into: &moves)
            case ChessCode.knight: generateHops(square, table: ChessTables.knight, me: me, into: &moves)
            case ChessCode.bishop: generateRays(square, directions: 4..<8, me: me, into: &moves)
            case ChessCode.rook: generateRays(square, directions: 0..<4, me: me, into: &moves)
            case ChessCode.queen: generateRays(square, directions: 0..<8, me: me, into: &moves)
            case ChessCode.king:
                generateHops(square, table: ChessTables.king, me: me, into: &moves)
                generateCastles(square, into: &moves)
            default: break
            }
        }
    }

    private func generateHops(_ square: Int, table: [Int8], me: UInt8, into moves: inout [ChessRawMove]) {
        for slot in 0..<8 {
            let target = table[square * 8 + slot]
            if target < 0 { break }
            let occupant = cells[Int(target)]
            if occupant != ChessCode.empty {
                if (occupant & ChessCode.blackBit) == me { continue }
                // **상대 왕은 집어가지 못한다.** 성립하는 국면에서는 애초에 나올 수 없는 수지만(차례가 아닌 쪽이
                // 체크인 판은 FEN 이 거절한다), 손으로 짠 판에서는 이 가드가 없으면 생성기가 왕을 집어가고
                // 그 결과 판(왕이 없다)의 판정이 거짓 무승부가 된다. 수 세기에는 영향이 없다 — 왕이 잡히는
                // 국면에서 수를 생성하는 일이 없기 때문이다.
                if (occupant & ChessCode.kindMask) == ChessCode.king { continue }
            }
            moves.append(ChessRawMove(from: square, to: Int(target), promotion: 0, flags: 0))
        }
    }

    private func generateRays(_ square: Int, directions: Range<Int>, me: UInt8, into moves: inout [ChessRawMove]) {
        for direction in directions {
            let base = (square * 8 + direction) * 7
            for step in 0..<7 {
                let target = ChessTables.rays[base + step]
                if target < 0 { break }
                let occupant = cells[Int(target)]
                if occupant == ChessCode.empty {
                    moves.append(ChessRawMove(from: square, to: Int(target), promotion: 0, flags: 0))
                    continue
                }
                // 상대 왕은 집어가지 못한다 — 줄은 그 칸에서 막히고 잡기만 빠진다(`generateHops` 의 같은 주석).
                if (occupant & ChessCode.blackBit) != me, (occupant & ChessCode.kindMask) != ChessCode.king {
                    moves.append(ChessRawMove(from: square, to: Int(target), promotion: 0, flags: 0))
                }
                break
            }
        }
    }

    private func generatePawn(_ square: Int, me: UInt8, into moves: inout [ChessRawMove]) {
        let isBlack = me != 0
        let forward = isBlack ? -8 : 8
        let startRank = isBlack ? 6 : 1
        let rankBeforePromotion = isBlack ? 1 : 6
        let rank = square >> 3
        let file = square & 7
        let one = square + forward
        // 끝 줄의 폰은 FEN 검증이 막는다. 손으로 짠 판(ChessPosition.empty + subscript)에서만 올 수 있어 여기서 한 번 더 본다.
        guard one >= 0, one < 64 else { return }

        if cells[one] == ChessCode.empty {
            if rank == rankBeforePromotion {
                for promotion in ChessCode.promotionCodes {
                    moves.append(ChessRawMove(from: square, to: one, promotion: promotion, flags: 0))
                }
            } else {
                moves.append(ChessRawMove(from: square, to: one, promotion: 0, flags: 0))
                let two = one + forward
                if rank == startRank, cells[two] == ChessCode.empty {
                    moves.append(ChessRawMove(from: square, to: two, promotion: 0, flags: ChessRawMove.doublePush))
                }
            }
        }

        for delta in ChessTables.pawnCaptureSides {
            let nextFile = file + delta
            guard nextFile >= 0, nextFile < 8 else { continue }
            let target = one + delta
            let occupant = cells[target]
            if occupant != ChessCode.empty {
                guard (occupant & ChessCode.blackBit) != me else { continue }
                // 상대 왕은 집어가지 못한다(`generateHops` 의 같은 주석).
                guard (occupant & ChessCode.kindMask) != ChessCode.king else { continue }
                if rank == rankBeforePromotion {
                    for promotion in ChessCode.promotionCodes {
                        moves.append(ChessRawMove(from: square, to: target, promotion: promotion, flags: 0))
                    }
                } else {
                    moves.append(ChessRawMove(from: square, to: target, promotion: 0, flags: 0))
                }
            } else if target == enPassant {
                // 캐슬링이 '룩이 제자리에 있는가'를 다시 보는 것과 **같은 이유로** 잡힐 폰이 실제로 뒤에 있는지
                // 다시 본다: `enPassantTarget` 은 package var 라 한 줄로 위조되고, 위조된 칸 하나가 불법 수를
                // 합법으로 만들었다 — 폰이 두 칸 전진한 적이 없는데 그 칸의 말(나이트든 **왕이든**)이 사라지고,
                // apply 가 낸 국면은 자기 FEN 으로 되읽히지도 않았다. 방어를 파서에만 두면 package API 를 쓰는
                // 호출자에게는 없는 방어다.
                let victim = isBlack ? target + 8 : target - 8
                guard victim >= 0, victim < 64,
                      cells[victim] == (ChessCode.pawn | (isBlack ? 0 : ChessCode.blackBit)) else { continue }
                moves.append(ChessRawMove(from: square, to: target, promotion: 0, flags: ChessRawMove.enPassant))
            }
        }
    }

    /// 캐슬링. 다섯 조건을 **모두** 본다: 권리가 살아 있다 · 룩이 제자리에 있다 · 사이가 비었다 ·
    /// 출발·경유·도착 칸이 공격받지 않는다(= 체크 중 금지가 출발 칸 검사에 포함된다).
    /// b1/b8 이 공격받아도 긴 쪽 캐슬링은 **된다** — 킹이 지나지 않는 칸이다(여기서 틀리면 수 세기가 2번 국면에서 갈린다).
    private func generateCastles(_ square: Int, into moves: inout [ChessRawMove]) {
        let isBlack = side == 1
        let home = isBlack ? 60 : 4
        guard square == home else { return }
        let rookCode = ChessCode.rook | (isBlack ? ChessCode.blackBit : 0)
        let kingsideBit = isBlack ? ChessCastlingRights.blackKingside.rawValue : ChessCastlingRights.whiteKingside.rawValue
        let queensideBit = isBlack ? ChessCastlingRights.blackQueenside.rawValue : ChessCastlingRights.whiteQueenside.rawValue
        let attackedByBlack = !isBlack

        if castling & kingsideBit != 0,
           cells[home + 1] == ChessCode.empty, cells[home + 2] == ChessCode.empty,
           cells[home + 3] == rookCode,
           !isAttacked(home, byBlack: attackedByBlack),
           !isAttacked(home + 1, byBlack: attackedByBlack),
           !isAttacked(home + 2, byBlack: attackedByBlack) {
            moves.append(ChessRawMove(from: home, to: home + 2, promotion: 0, flags: ChessRawMove.castling))
        }
        if castling & queensideBit != 0,
           cells[home - 1] == ChessCode.empty, cells[home - 2] == ChessCode.empty, cells[home - 3] == ChessCode.empty,
           cells[home - 4] == rookCode,
           !isAttacked(home, byBlack: attackedByBlack),
           !isAttacked(home - 1, byBlack: attackedByBlack),
           !isAttacked(home - 2, byBlack: attackedByBlack) {
            moves.append(ChessRawMove(from: home, to: home - 2, promotion: 0, flags: ChessRawMove.castling))
        }
    }

    // MARK: 두기 · 되돌리기

    mutating func make(_ move: ChessRawMove) -> ChessUndo {
        let piece = cells[move.from]
        let kind = piece & ChessCode.kindMask
        let moverIsBlack = (piece & ChessCode.blackBit) != 0
        var undo = ChessUndo(move: move, captured: cells[move.to], capturedSquare: move.to,
                             castling: castling, enPassant: enPassant,
                             halfmove: halfmove, fullmove: fullmove, rookFrom: -1, rookTo: -1)

        // 앙파상은 **도착 칸이 아닌** 칸의 폰을 집어간다.
        if move.flags & ChessRawMove.enPassant != 0 {
            let victim = moverIsBlack ? move.to + 8 : move.to - 8
            undo.captured = cells[victim]
            undo.capturedSquare = victim
            cells[victim] = ChessCode.empty
        }

        cells[move.to] = move.promotion == 0 ? piece : (move.promotion | (piece & ChessCode.blackBit))
        cells[move.from] = ChessCode.empty

        if kind == ChessCode.king {
            kings[moverIsBlack ? 1 : 0] = move.to
            if move.flags & ChessRawMove.castling != 0 {
                let kingside = move.to > move.from
                let rookFrom = kingside ? move.from + 3 : move.from - 4
                let rookTo = kingside ? move.from + 1 : move.from - 1
                cells[rookTo] = cells[rookFrom]
                cells[rookFrom] = ChessCode.empty
                undo.rookFrom = rookFrom
                undo.rookTo = rookTo
            }
        }

        // 권리 소멸: 킹이 움직였거나(그 색 둘), 네 귀퉁이 칸이 **비거나 잡혔다**. 말을 보지 않고 칸만 보는 까닭 —
        // 룩이 떠난 자리와 룩이 잡힌 자리는 같은 결과를 내고, 룩이 없던 자리에는 애초에 권리가 없다.
        if kind == ChessCode.king {
            castling &= ~(moverIsBlack
                          ? (ChessCastlingRights.blackKingside.rawValue | ChessCastlingRights.blackQueenside.rawValue)
                          : (ChessCastlingRights.whiteKingside.rawValue | ChessCastlingRights.whiteQueenside.rawValue))
        }
        castling &= ~Self.cornerRight(move.from)
        castling &= ~Self.cornerRight(move.to)

        enPassant = move.flags & ChessRawMove.doublePush != 0 ? (move.from + move.to) / 2 : -1
        halfmove = (kind == ChessCode.pawn || undo.captured != ChessCode.empty) ? 0 : halfmove + 1
        if moverIsBlack { fullmove += 1 }
        side ^= 1
        return undo
    }

    mutating func unmake(_ undo: ChessUndo) {
        side ^= 1
        let move = undo.move
        let placed = cells[move.to]
        let piece = move.promotion == 0 ? placed : (ChessCode.pawn | (placed & ChessCode.blackBit))
        cells[move.from] = piece
        // 앙파상이면 도착 칸은 비고 희생 폰이 제자리로 — 잡은 칸이 도착 칸과 같을 때도 한 벌로 맞는다.
        cells[move.to] = ChessCode.empty
        cells[undo.capturedSquare] = undo.captured

        if (piece & ChessCode.kindMask) == ChessCode.king {
            kings[(piece & ChessCode.blackBit) != 0 ? 1 : 0] = move.from
            if undo.rookFrom >= 0 {
                cells[undo.rookFrom] = cells[undo.rookTo]
                cells[undo.rookTo] = ChessCode.empty
            }
        }

        castling = undo.castling
        enPassant = undo.enPassant
        halfmove = undo.halfmove
        fullmove = undo.fullmove
    }

    private static func cornerRight(_ square: Int) -> UInt8 {
        switch square {
        case 0: return ChessCastlingRights.whiteQueenside.rawValue
        case 7: return ChessCastlingRights.whiteKingside.rawValue
        case 56: return ChessCastlingRights.blackQueenside.rawValue
        case 63: return ChessCastlingRights.blackKingside.rawValue
        default: return 0
        }
    }

    // MARK: 왕 안전 · 핀

    /// 왕과 적 장거리 말 사이에 **혼자** 끼어 있는 내 말들의 비트 마스크(핀).
    func pinnedMask(kingSquare: Int, moverIsBlack: Bool) -> UInt64 {
        let me: UInt8 = moverIsBlack ? ChessCode.blackBit : 0
        var mask: UInt64 = 0
        for direction in 0..<8 {
            let slider: UInt8 = direction < 4 ? ChessCode.rook : ChessCode.bishop
            let base = (kingSquare * 8 + direction) * 7
            var own = -1
            for step in 0..<7 {
                let target = ChessTables.rays[base + step]
                if target < 0 { break }
                let occupant = cells[Int(target)]
                if occupant == ChessCode.empty { continue }
                if own < 0 {
                    // 적 말이 먼저 나오면 핀이 아니다(체크면 체크다 — 그건 아래 inCheck 가 본다).
                    if (occupant & ChessCode.blackBit) == me { own = Int(target); continue }
                    break
                }
                if (occupant & ChessCode.blackBit) != me {
                    let kind = occupant & ChessCode.kindMask
                    if kind == slider || kind == ChessCode.queen { mask |= UInt64(1) << UInt64(own) }
                }
                break
            }
        }
        return mask
    }

    /// 두고 나서 "내 왕이 열렸는가"를 **다시 봐야 하는** 수인가.
    ///
    /// 보지 않아도 되는 근거: 왕은 제자리이므로 새 공격은 **막고 있던 줄이 열릴 때만** 생긴다. 줄을 혼자 막던 말은
    /// 정의상 핀이고, 둘이 막던 줄은 하나가 떠도 여전히 막혀 있다. 그러니 왕 자신의 수 · 핀 된 말의 수 · 체크 중의
    /// 수만 보면 된다. 여기에 **앙파상**을 더하는 까닭이 이 최적화의 유일한 함정이다: 앙파상은 도착 칸이 아닌 칸의
    /// 폰을 치우므로, 그 폰이 막고 있던 줄이 열려 내 왕이 공격받을 수 있다(수 세기 ③번 국면이 그 자리다).
    /// 이 넷 중 하나라도 빠지면 수 세기가 즉시 어긋난다 — 그게 이 지름길의 그물이다.
    @inline(__always)
    func needsKingSafetyCheck(_ move: ChessRawMove, kingSquare: Int, pins: UInt64, inCheck: Bool) -> Bool {
        inCheck
            || move.from == kingSquare
            || (pins & (UInt64(1) << UInt64(move.from))) != 0
            || (move.flags & ChessRawMove.enPassant) != 0
    }

    // MARK: 합법 수 · 수 세기

    /// 유사 합법 수에서 자기 왕이 열리는 것을 걸러낸 결과.
    mutating func legalRawMoves() -> [ChessRawMove] {
        var pseudo: [ChessRawMove] = []
        pseudo.reserveCapacity(48)
        generate(into: &pseudo)
        let moverIndex = Int(side)
        let kingSquare = kings[moverIndex]
        let byBlack = moverIndex == 0
        let inCheck = isAttacked(kingSquare, byBlack: byBlack)
        let pins = pinnedMask(kingSquare: kingSquare, moverIsBlack: moverIndex == 1)
        var legal: [ChessRawMove] = []
        legal.reserveCapacity(pseudo.count)
        for move in pseudo {
            guard needsKingSafetyCheck(move, kingSquare: kingSquare, pins: pins, inCheck: inCheck) else {
                legal.append(move)
                continue
            }
            let undo = make(move)
            if !isAttacked(kings[moverIndex], byBlack: byBlack) { legal.append(move) }
            unmake(undo)
        }
        return legal
    }

    /// 공개 `ChessMove` 와 짝이 맞는 합법 수. 승격 말까지 같아야 맞는다(`e7e8` 만으로는 승격이 결정되지 않는다).
    mutating func matchingLegalMove(_ move: ChessMove) -> ChessRawMove? {
        let promotion = move.promotion.map(ChessCode.code) ?? 0
        return legalRawMoves().first {
            $0.from == move.from.index && $0.to == move.to.index && $0.promotion == promotion
        }
    }

    /// 수 세기. 노드마다 배열을 새로 만들지 않도록 **한 버퍼를 창으로 나눠** 쓴다(자식은 내 창 뒤에 쌓고 끝나면 치운다).
    mutating func perft(depth: Int, buffer: inout [ChessRawMove]) -> Int {
        let start = buffer.count
        generate(into: &buffer)
        let end = buffer.count
        let moverIndex = Int(side)
        let kingSquare = kings[moverIndex]
        let byBlack = moverIndex == 0
        let inCheck = isAttacked(kingSquare, byBlack: byBlack)
        let pins = pinnedMask(kingSquare: kingSquare, moverIsBlack: moverIndex == 1)
        var total = 0
        var index = start
        while index < end {
            let move = buffer[index]
            let verify = needsKingSafetyCheck(move, kingSquare: kingSquare, pins: pins, inCheck: inCheck)
            let undo = make(move)
            if !verify || !isAttacked(kings[moverIndex], byBlack: byBlack) {
                total += depth == 1 ? 1 : perft(depth: depth - 1, buffer: &buffer)
            }
            unmake(undo)
            index += 1
        }
        buffer.removeLast(buffer.count - start)
        return total
    }
}
