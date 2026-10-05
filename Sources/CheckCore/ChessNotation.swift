import Foundation

// 수 표기 — UCI(`e2e4` · `e7e8q`)와 SAN(`Nbd2` · `exd6` · `O-O` · `Qh4e1` · `e8=Q#`).
//
// ── 왜 둘 다인가 ──
// UCI 는 기계 사이의 표기다(서버·AI·실시간 전송). SAN 은 사람이 읽는 표기다(기보·대국 기록). 서버가 UCI 로만 말하고
// 화면이 SAN 으로만 보여 주면 **번역이 한 군데**여야 한다 — 양쪽이 각자 번역하면 동형 중복 해소에서 갈린다.
//
// ── SAN 파싱을 생성에 기대는 까닭 ──
// 파서를 따로 쓰면 "엔진이 만드는 SAN"과 "엔진이 읽는 SAN"이 두 규칙이 되고, 둘이 어긋나는 자리는 왕복(생성→파싱)이
// 깨지는 수뿐이라 눈에 잘 안 띈다. 그래서 파싱은 합법 수 전부의 SAN 을 만들어 **같은 것 하나**를 찾는다.
// 느린 경로지만 수 하나를 읽을 때만 돈다(수 세기 경로에는 없다).

extension ChessMove {
    /// UCI 문자열. 승격은 소문자 한 글자(`e7e8q`).
    package var uci: String {
        var text = from.notation + to.notation
        if let promotion { text.append(Character(String(promotion.fenLetter).lowercased())) }
        return text
    }

    /// UCI 문자열을 읽는다. 4글자 또는 5글자(승격)만 받고, 승격 글자는 q·r·b·n 뿐이다 —
    /// `e7e8k` 처럼 고를 수 없는 말이 든 수는 **모양 단계에서** 막는다.
    package init?(uci: String) {
        let characters = Array(uci)
        guard characters.count == 4 || characters.count == 5 else { return nil }
        guard let from = ChessSquare(String(characters[0...1])),
              let to = ChessSquare(String(characters[2...3])) else { return nil }
        var promotion: ChessPieceKind?
        if characters.count == 5 {
            guard let kind = ChessPieceKind(fenLetter: characters[4]),
                  ChessPieceKind.promotionChoices.contains(kind),
                  characters[4].isLowercase else { return nil }
            promotion = kind
        }
        self.init(from: from, to: to, promotion: promotion)
    }
}

extension ChessRules {
    /// 수의 SAN. 합법 수가 아니면 nil.
    ///
    /// 동형 중복 해소는 **파일 → 랭크 → 둘 다** 순서다(FIDE C.10): 같은 종류의 다른 말이 같은 칸으로 갈 수 있을 때,
    /// 출발 파일이 그들 중 유일하면 파일만, 아니면 랭크, 둘 다 겹치면 출발 칸 전체를 적는다.
    /// 폰은 이 사다리를 타지 않는다 — 폰이 잡을 때는 **언제나** 출발 파일을 적는다(`exd5`).
    package static func san(for move: ChessMove, in position: ChessPosition) -> String? {
        san(for: move, in: position, legalMoves: legalMoves(in: position))
    }

    /// 합법 수 목록을 **이미 들고 있을 때** 쓰는 길. 목록은 **합법성 확인에만** 쓴다 — 동형 중복 해소는 넘어온
    /// 목록을 보지 않고 판에서 직접 센다(`disambiguation`).
    ///
    /// 그렇게 바꾼 까닭: 화면이 흔히 들고 있는 건 전체 목록이 아니라 '고른 말의 수'다. 그 부분 목록을 넘기면
    /// 경쟁자가 안 보여 `Nbd2` 대신 `Nd2` 가 나왔고(nil 도 아니었다), 그 표기는 되읽히지도 않았다 —
    /// 빠른 길의 대가로 **조용히 틀린 값**을 받는 건 맞바꿀 수 있는 게 아니다.
    package static func san(for move: ChessMove, in position: ChessPosition, legalMoves legal: [ChessMove]) -> String? {
        guard legal.contains(move), let effect = effect(of: move, in: position) else { return nil }
        var text: String

        if effect.isCastling {
            text = move.to.file > move.from.file ? "O-O" : "O-O-O"
        } else if effect.piece.kind == .pawn {
            text = effect.captured == nil ? move.to.notation : "\(fileLetter(move.from.file))x\(move.to.notation)"
            if let promotion = move.promotion { text += "=\(promotion.fenLetter)" }
        } else {
            text = String(effect.piece.kind.fenLetter)
            text += disambiguation(for: move, piece: effect.piece, in: position)
            if effect.captured != nil { text += "x" }
            text += move.to.notation
        }

        if isInCheck(effect.after) {
            text += legalMoves(in: effect.after).isEmpty ? "#" : "+"
        }
        return text
    }

    /// SAN 을 수로 읽는다. 합법 수가 아니거나 **모호하면** nil(둘 이상에 맞는 표기는 수가 아니다).
    /// 받아 주는 흔들림: 체크·평가 기호(`+ # ! ?`), 승격의 `=` 생략, `0-0` 캐슬링, `e.p.` 꼬리, 앞뒤 공백·줄끝,
    /// 그리고 **과다 명시**(`Qd1d2` · `Qdd2` · `Q1d2` · `Qd1-d2` · 잡기의 `x` 생략 · 폰의 장형 `e2e4`).
    ///
    /// 과다 명시를 받는 까닭: 그렇게 적은 수들은 합법이고 모호하지도 않다 — nil 의 이유로 적은 둘("불법"·"모호")
    /// 어디에도 들지 않는데 전부 nil 이었다. PGN 수입 형식·장형 대수 표기로 적힌 기보가 그 자리에서 통째로 막힌다.
    package static func move(san: String, in position: ChessPosition) -> ChessMove? {
        let wanted = normalizedSAN(san)
        guard !wanted.isEmpty else { return nil }
        let legal = legalMoves(in: position)
        var found: ChessMove?
        for candidate in legal {
            guard let text = self.san(for: candidate, in: position, legalMoves: legal),
                  spellings(of: candidate, canonical: text, in: position).contains(wanted) else { continue }
            if found != nil { return nil }   // 모호: 합법 수 둘이 같은 표기 — 수를 내지 않는다
            found = candidate
        }
        return found
    }

    /// 이 수를 가리키는 표기 전부(정규형) — 생성한 SAN 에 과다 명시형을 더한 것이다.
    ///
    /// 글자열을 구조로 파싱하지 않고 **수에서 다시 적는** 까닭은 이 파일 머리에 적은 그대로다: 파서를 따로 쓰면
    /// "엔진이 만드는 표기"와 "엔진이 읽는 표기"가 두 규칙이 되고, 어긋나는 자리는 왕복이 깨지는 수뿐이라 눈에 잘
    /// 안 띈다. 과다 명시가 모호해지면(생략형 `Nd2` 가 둘에 맞는 자리) 호출자의 중복 검사가 그대로 nil 을 낸다.
    private static func spellings(of move: ChessMove, canonical: String, in position: ChessPosition) -> Set<String> {
        var out: Set<String> = [normalizedSAN(canonical)]
        // 캐슬링엔 과다 명시형이 없다(`O-O` 하나뿐이다).
        guard let piece = position[move.from], !canonical.hasPrefix("O") else { return out }
        let captures = canonical.contains("x")
        let promotion = move.promotion.map { String($0.fenLetter) } ?? ""
        let fileText = String(fileLetter(move.from.file))
        let heads: [String]
        if piece.kind == .pawn {
            // 폰이 잡을 때 출발 파일은 PGN 이 **요구한다**(`exd5`) — `d5` 로 줄여 적은 것은 수가 아니다.
            heads = captures ? [fileText, move.from.notation] : ["", move.from.notation]
        } else {
            let letter = String(piece.kind.fenLetter)
            heads = ["", fileText, String(move.from.rank + 1), move.from.notation].map { letter + $0 }
        }
        for head in heads {
            out.insert(normalizedSAN(head + move.to.notation + promotion))
            if captures { out.insert(normalizedSAN(head + "x" + move.to.notation + promotion)) }
        }
        return out
    }

    /// 한 수순을 차례로 적용하며 **거쳐 간 국면 전부**를 낸다(시작 국면 포함, 끝 국면까지). 하나라도 불법이면 nil.
    /// 서버가 수 목록만 받아 판을 재구성하는 자리와, 동형 반복 장부를 채우는 자리가 이 함수 하나다.
    package static func replay(uciLine: [String], from position: ChessPosition) -> [ChessPosition]? {
        var trail = [position]
        var current = position
        for text in uciLine {
            guard let move = ChessMove(uci: text), let next = apply(move, to: current) else { return nil }
            current = next
            trail.append(current)
        }
        return trail
    }

    /// 수순의 SAN 기보(기록·보고용). 하나라도 불법이면 nil.
    package static func sanLine(uciLine: [String], from position: ChessPosition) -> [String]? {
        var current = position
        var line: [String] = []
        for text in uciLine {
            guard let move = ChessMove(uci: text),
                  let notation = san(for: move, in: current, legalMoves: legalMoves(in: current)),
                  let next = apply(move, to: current) else { return nil }
            line.append(notation)
            current = next
        }
        return line
    }

    /// 동형 중복 해소. 경쟁자는 **판에서 직접** 센다 — 넘어온 목록이 전체라는 보장이 없고, 부분 목록이면
    /// 경쟁자가 없는 것처럼 보여 틀린 표기가 조용히 나온다.
    ///
    /// 겹칠 말(같은 색·같은 종류)이 판에 아예 없으면 수 생성을 하지 않는다 — 흔한 경우는 공짜다.
    private static func disambiguation(for move: ChessMove, piece: ChessPiece, in position: ChessPosition) -> String {
        let code = ChessCode.code(piece)
        var hasTwin = false
        for index in 0..<64 where index != move.from.index && position.cells[index] == code {
            hasTwin = true
            break
        }
        guard hasTwin else { return "" }

        let rivals = legalMoves(in: position).filter {
            $0 != move && $0.to == move.to && position[$0.from] == piece
        }
        if rivals.isEmpty { return "" }
        if !rivals.contains(where: { $0.from.file == move.from.file }) { return String(fileLetter(move.from.file)) }
        if !rivals.contains(where: { $0.from.rank == move.from.rank }) { return String(move.from.rank + 1) }
        return move.from.notation
    }

    private static func fileLetter(_ file: Int) -> Character {
        Character(UnicodeScalar(UInt8(0x61 + file)))
    }

    /// 비교용 정규형. `0` 은 SAN 어디에도 쓰이지 않으므로(랭크는 1…8) 통째로 `O` 로 바꿔도 캐슬링만 맞는다.
    ///
    /// 공백은 **종류를 가리지 않고** 걷는다(`isWhitespace`). 글자를 하나씩 세어 적던 예전 집합엔 CR 만 빠져 있었고,
    /// 그래서 윈도 줄끝으로 적힌 PGN·텍스트를 줄 단위로 읽어 넘기면 **모든 수가 nil** 로 떨어졌다.
    /// `-` 도 걷는다: 장형 대수 표기(`Qd1-d2`)와 캐슬링(`O-O`)이 같은 자리를 지나지만, 비교는 양쪽이 이 함수를
    /// 통과한 뒤에 하므로 캐슬링은 `OO`·`OOO` 로 여전히 갈린다.
    private static func normalizedSAN(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "e.p.", with: "")
        out = out.replacingOccurrences(of: "=", with: "")
        out = out.replacingOccurrences(of: "0", with: "O")
        return String(out.filter { !"+#!?-".contains($0) && !$0.isWhitespace })
    }
}
