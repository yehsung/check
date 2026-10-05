import Foundation

// FEN 양방향(파싱 · 생성)과 **동형 반복 키**.
//
// ── 파서가 깐깐한 까닭 ──
// FEN 은 서버·AI·화면 사이를 오가는 유일한 국면 표현이다. 어긋난 FEN 을 "대충 읽어" 국면을 만들면 그 뒤의
// 모든 판정이 조용히 틀린다 — 둘 수 없는 칸을 둘 수 있다고 보여 주고, 서버는 그 수를 거절한다. 그래서
// 모양만 맞는 글자열이 아니라 **체스판으로 성립하는 국면**만 받는다:
//  · 8줄 · 줄마다 정확히 8칸 · 왕은 양쪽에 하나씩 · 끝 줄에 폰 없음
//  · 배치는 **정규형**이다: 빈 칸 수를 쪼개 적은 줄("44" · "332" · "11111111")은 거절한다 — 같은 판이 여러
//    글자열로 들어오면 '서버가 받은 원문'과 '앱이 만든 FEN'이 바이트로 어긋난다
//  · 반수·수 번호는 정규형 10진수(부호·앞자리 0 없음)이고, **한 판에서 나올 수 있는 값**이어야 한다
//    (`hasReachableCounters`: 지금까지 둔 반수보다 크면 거짓 무승부가 되고, 위 한계가 없으면 Int.max 가 들어와
//     받아들인 뒤 첫 수에서 프로세스가 죽는다)
//  · 캐슬링 권리는 킹이 제자리에 있고 그 귀퉁이에 룩이 있을 때만(거짓 권리는 둘 수 없는 캐슬링을 보여 준다)
//  · 앙파상 칸은 **차례와 맞는 줄**이고, 잡힐 폰이 실제로 뒤에 있고, 지나간 칸들이 비어 있을 때만
//    (거짓 앙파상 칸은 불법 수를 합법으로 만든다 — 파서가 막는 자리다)
//  · 차례가 **아닌** 쪽이 체크인 국면은 거절한다(왕을 잡을 수 있는 판은 체스가 아니다)
// 느슨하게 받아 주고 싶어질 때마다 떠올릴 것: 느슨한 쪽은 언제나 한 군데뿐이라 앱과 서버가 같은 글자열을
// 다르게 읽기 시작한다.

extension ChessPosition {
    /// FEN 전체. 칸은 6개(배치 · 차례 · 캐슬링 · 앙파상 · 반수 · 수 번호)이고, 뒤 두 칸은 생략해도 받는다
    /// (0 과 1 로 본다 — 수 세기 코퍼스와 기보 도구가 네 칸짜리를 흘린다).
    package init?(fen: String) {
        // 칸은 **공백 아무것**으로 가른다(스페이스·탭·CR·LF). 공백 하나만 받으면 파일·DB 칸·로그에서 떠온 FEN 의
        // 줄끝 한 글자가 '성립하지 않는 국면'과 똑같은 nil 로 보고된다 — 배치가 틀린 것과 글자가 하나 더 붙은
        // 것이 구별되지 않는다(윈도 줄끝으로 적힌 파일을 줄 단위로 읽으면 모든 국면이 nil 이 된다).
        let fields = fen.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count >= 4, fields.count <= 6 else { return nil }

        var cells = ContiguousArray<UInt8>(repeating: ChessCode.empty, count: 64)
        let rows = fields[0].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard rows.count == 8 else { return nil }
        for (rowIndex, row) in rows.enumerated() {
            let rank = 7 - rowIndex                 // FEN 은 8번째 줄부터 적는다
            var file = 0
            var previousWasEmptyCount = false
            for character in row {
                // 빈 칸 수는 ASCII '1'…'8' 만이다. `wholeNumberValue` 로 받으면 전각·타 문자 숫자가 끼어든다.
                if let ascii = character.asciiValue, ascii >= 0x31, ascii <= 0x38 {
                    // 숫자 **이어쓰기**는 거절한다: "44" · "332" · "11111111" 은 모두 8칸으로 읽혀 **한 판이
                    // 여러 글자열**이 되고, `.fen` 은 그중 하나("8")만 다시 적는다. 그러면 '서버가 받은 원문'과
                    // '앱이 만든 FEN'이 바이트로 어긋난다 — 머리 주석이 경고한 바로 그 모양이다.
                    guard !previousWasEmptyCount else { return nil }
                    previousWasEmptyCount = true
                    file += Int(ascii - 0x30)
                    continue
                }
                previousWasEmptyCount = false
                guard let piece = ChessPiece(fenCharacter: character), file < 8 else { return nil }
                cells[rank * 8 + file] = ChessCode.code(piece)
                file += 1
            }
            guard file == 8 else { return nil }
        }

        // 왕은 양쪽에 하나씩. 끝 줄의 폰은 승격을 빼먹은 국면이라 체스판이 아니다.
        var kings = [0, 0]
        for index in 0..<64 {
            let cell = cells[index]
            guard cell != ChessCode.empty else { continue }
            if (cell & ChessCode.kindMask) == ChessCode.king { kings[(cell & ChessCode.blackBit) == 0 ? 0 : 1] += 1 }
            if (cell & ChessCode.kindMask) == ChessCode.pawn, index < 8 || index >= 56 { return nil }
        }
        guard kings == [1, 1] else { return nil }

        let sideToMove: ChessColor
        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: return nil
        }

        guard let rights = ChessCastlingRights.parse(fen: fields[2]) else { return nil }
        for (right, home, corner, color) in [
            (ChessCastlingRights.whiteKingside, 4, 7, ChessColor.white),
            (ChessCastlingRights.whiteQueenside, 4, 0, ChessColor.white),
            (ChessCastlingRights.blackKingside, 60, 63, ChessColor.black),
            (ChessCastlingRights.blackQueenside, 60, 56, ChessColor.black)
        ] where rights.contains(right) {
            guard cells[home] == (ChessCode.king | (color == .black ? ChessCode.blackBit : 0)),
                  cells[corner] == (ChessCode.rook | (color == .black ? ChessCode.blackBit : 0)) else { return nil }
        }

        var enPassantTarget: ChessSquare?
        if fields[3] != "-" {
            guard let target = ChessSquare(fields[3]) else { return nil }
            // 직전 두 칸 전진이 있었어야 한다: 칸이 비고, 잡힐 폰이 뒤에 있고, 출발 칸이 비어 있다.
            let expectedRank = sideToMove == .white ? 5 : 2
            let victim = sideToMove == .white ? target.index - 8 : target.index + 8
            let origin = sideToMove == .white ? target.index + 8 : target.index - 8
            let victimCode = ChessCode.pawn | (sideToMove == .white ? ChessCode.blackBit : 0)
            guard target.rank == expectedRank,
                  cells[target.index] == ChessCode.empty,
                  cells[victim] == victimCode,
                  cells[origin] == ChessCode.empty else { return nil }
            enPassantTarget = target
        }

        guard let halfmoveClock = Self.counter(fields.count >= 5 ? fields[4] : "0"),
              let fullmoveNumber = Self.counter(fields.count >= 6 ? fields[5] : "1") else { return nil }

        self.init(cells: cells, sideToMove: sideToMove, castlingRights: rights,
                  enPassantTarget: enPassantTarget, halfmoveClock: halfmoveClock, fullmoveNumber: fullmoveNumber)

        // 카운터도 **배치와 똑같이** 본다. 거짓 반수는 '불법 무승부를 합법으로' 만들고(1수째 백 차례의 반수 100 은
        // 즉시 50수 무승부로 판정된다), 위쪽 한계가 없으면 Int.max 를 받아들인 뒤 첫 `legalMoves` 에서 프로세스가
        // 죽는다. 거짓 앙파상 칸을 막는 바로 위 자리와 같은 모양의 구멍이라 여기서 함께 막는다.
        guard hasReachableCounters else { return nil }

        // 차례가 아닌 쪽이 체크면 그 수는 애초에 둘 수 없었던 수다 — 그런 국면을 받아 주면 "왕을 잡는 수"가 생긴다.
        if ChessRules.isInCheck(self, color: sideToMove.opponent) { return nil }
    }

    /// 반수·수 번호 칸. **정규형 10진수만** 받는다 — 부호(`+0`)·앞자리 0(`00`)·빈 칸을 받아 주면 같은 판이
    /// 여러 글자열이 되고(`.fen` 은 하나만 적는다), 너무 긴 글자열은 Int 범위를 넘어 nil 이 된다.
    private static func counter(_ text: String) -> Int? {
        guard !text.isEmpty, text.count <= 10 else { return nil }
        for character in text {
            guard let ascii = character.asciiValue, ascii >= 0x30, ascii <= 0x39 else { return nil }
        }
        guard text == "0" || !text.hasPrefix("0") else { return nil }
        return Int(text)
    }

    /// FEN 6칸 전체.
    package var fen: String {
        let enPassantText = enPassantTarget?.notation ?? "-"
        return "\(boardFEN) \(sideToMove == .white ? "w" : "b") \(castlingRights.fenText) \(enPassantText) "
            + "\(halfmoveClock) \(fullmoveNumber)"
    }

    /// FEN 첫 칸(배치만).
    package var boardFEN: String {
        var text = ""
        for rowIndex in 0..<8 {
            let rank = 7 - rowIndex
            var empties = 0
            for file in 0..<8 {
                if let piece = ChessCode.piece(cells[rank * 8 + file]) {
                    if empties > 0 { text += String(empties); empties = 0 }
                    text.append(piece.fenCharacter)
                } else {
                    empties += 1
                }
            }
            if empties > 0 { text += String(empties) }
            if rank > 0 { text += "/" }
        }
        return text
    }

    /// 동형 반복(FIDE 9.2)의 국면 동일성 키. **해시가 아니라 정규 문자열**이라 충돌이 없다 —
    /// 세 번째 반복에 걸린 판이 실은 다른 국면이었다는 사고가 날 수 없다.
    ///
    /// 담는 것: 배치 + 차례 + 캐슬링 권리 + **앙파상 가능성**.
    /// 빼는 것: 50수 카운터와 수 번호(반복 판정과 무관하다 — 넣으면 세 번째 반복이 영원히 안 온다).
    ///
    /// '가능성'이 FEN 의 앙파상 칸과 다른 자리가 핵심이다: 두 칸 전진 직후라도 그 폰을 **잡는 합법 수가 없으면**
    /// 두 국면은 같은 국면이다. 그래서 키에는 실제로 잡을 수 있을 때만 칸 이름이 들어간다.
    package var repetitionKey: String {
        let enPassantText = ChessRules.hasLegalEnPassantCapture(in: self) ? (enPassantTarget?.notation ?? "-") : "-"
        return "\(boardFEN) \(sideToMove == .white ? "w" : "b") \(castlingRights.fenText) \(enPassantText)"
    }

    /// 사람이 읽는 판(수 세기가 갈렸을 때 divide 와 함께 찍는 자리).
    package var asciiBoard: String {
        var lines: [String] = []
        for rowIndex in 0..<8 {
            let rank = 7 - rowIndex
            var line = "\(rank + 1) "
            for file in 0..<8 {
                line.append(ChessCode.piece(cells[rank * 8 + file])?.fenCharacter ?? ".")
                line.append(" ")
            }
            lines.append(line)
        }
        lines.append("  a b c d e f g h")
        return lines.joined(separator: "\n")
    }
}

/// 한 판의 동형 반복 장부. 호출자가 수를 둘 때마다 국면을 넣으면 `ChessRules.outcome` 에 그대로 건넬 표가 된다.
///
/// 되돌릴 수 없는 수(폰 이동 · 잡기 · 캐슬링 권리 소멸)에서 장부를 비울 수도 있지만 **비우지 않는다** —
/// FIDE 는 '같은 국면이 세 번'만 요구하고 그 사이에 무엇이 있었는지는 묻지 않는다. 배치가 같으면
/// 되돌릴 수 없는 수 이전의 국면은 다시 나올 수 없으므로, 비우지 않아도 결과가 같고 규칙은 하나로 남는다.
package nonisolated struct ChessRepetitionLedger: Hashable, Sendable {
    private var counts: [String: Int]

    package init() { counts = [:] }

    /// 이 국면이 나왔다고 적는다. **판의 시작 국면도 넣어야 한다** — 초기 국면으로 세 번 돌아오는 수순이 있다.
    package mutating func record(_ position: ChessPosition) {
        counts[position.repetitionKey, default: 0] += 1
    }

    package func count(of position: ChessPosition) -> Int {
        counts[position.repetitionKey] ?? 0
    }

    /// `ChessRules.outcome(position:repetitionCounts:)` 에 넘기는 표.
    package var repetitionCounts: [String: Int] { counts }
}
