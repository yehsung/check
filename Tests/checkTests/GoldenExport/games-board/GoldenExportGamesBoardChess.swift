// 원본: Sources/CheckCore/ChessRules.swift · ChessFEN.swift · ChessNotation.swift @ 1b8260d (골든 생성기 — W1-b)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// W1-b 골든(체스 규칙): Kotlin `core/rules/…/chess` 가 이 값들과 비트로 대조한다(C§5.1 E8 — 합법수·종국·50수·반복·FEN·UCI).
//
//  · chess/perft     공표 여섯 국면 + 종국 잎 셋(Tests/checkTests/Fixtures/chess-perft.json) — Swift 가 센 깊이별 노드 수와 divide(깊이 2).
//                    생성기가 픽스처 기대값과 먼저 대조한다(골든이 틀린 Swift 를 옮겨 적지 않게).
//  · chess/fen       FEN 입력(정규·무작위 걷기·공백 변형·거절해야 할 모양) → 받았나 · 정규 FEN · 반복 키 · 판정 · 기물 판정.
//  · chess/moves     국면마다 합법 수 **생성 순서 그대로** + SAN + 효과(잡힌 칸 · 룩 길 · 앙파상 · 두 칸 · 캐슬링 · 승격) + 둔 뒤 FEN.
//  · chess/notation  SAN 읽기(정규·과다 명시·기호·공백 변형·모호·불법) · UCI 읽기 표 · 수순 재생(replay · sanLine) · 반복 장부.
//  · chess/outcome   손으로 놓은 국면(엔진 가드: 왕 없음·둘·카운터 범위·위조 앙파상·룩 없는 권리·왕 잡기) · 사국·50수·3회 · 시계(FIDE 6.9).

@Suite("GoldenExport games-board — 체스 규칙(chess/perft · fen · moves · notation · outcome)")
struct GoldenExportGamesBoardChess {
    static let rules = "Sources/CheckCore/ChessRules.swift"
    static let fenSource = "Sources/CheckCore/ChessFEN.swift"
    static let notation = "Sources/CheckCore/ChessNotation.swift"
    /// 무작위 걷기의 난수(GomokuAISplitMix64)가 사는 곳.
    static let splitMix = "Sources/CheckCore/GomokuAIEngine.swift"

    // MARK: chess/perft

    @Test("chess/perft — 공표 여섯 + 잎 셋: 깊이별 노드 수 · divide(깊이 2) · 경계(깊이 0 · 음수)")
    func chessPerft() throws {
        let data = try Data(contentsOf: GoldenRepo.url("Tests/checkTests/Fixtures/chess-perft.json"))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let positions = try #require(root["positions"] as? [[String: Any]])
        let leaves = try #require(root["leaves"] as? [[String: Any]])
        #expect(positions.count == 6 && leaves.count == 3)
        var cases: [GoldenJSON] = []
        for (index, item) in (positions + leaves).enumerated() {
            let fen = try #require(item["fen"] as? String)
            let label = try #require(item["label"] as? String)
            let fixture = try #require(item["counts"] as? [Int])
            let position = try #require(ChessPosition(fen: fen), "FEN \(fen)")
            // Swift 기본 게이트와 같은 깊이: 여섯 국면 d1~d3 · ①③ d4 · 잎 셋 전부(ChessPerftTests).
            let depthLimit = index < 6 ? ((index == 0 || index == 2) ? 4 : 3) : fixture.count
            var counts: [GoldenJSON] = []
            for depth in 1...depthLimit {
                let nodes = ChessRules.perft(position, depth: depth)
                #expect(nodes == fixture[depth - 1], "\(label) 깊이 \(depth): Swift \(nodes) ≠ 픽스처 \(fixture[depth - 1])")
                counts.append(.int(nodes))
            }
            let divide = ChessRules.perftDivide(position, depth: 2).map { GoldenJSON.array([.string($0.move.uci), .int($0.nodes)]) }
            cases.append([
                "id": .string("p\(index + 1)"),
                "label": .string(label),
                "fen": .string(fen),
                "counts": .array(counts),
                "divide2": .array(divide),
                "outcome": Self.outcomeLabel(ChessRules.outcome(position: position)),
            ])
        }
        let standard = ChessPosition.standard
        cases.append([
            "id": "edges",
            "fen": .string(standard.fen),
            "depth0": .int(ChessRules.perft(standard, depth: 0)),
            "depthMinus1": .int(ChessRules.perft(standard, depth: -1)),
            "divide0": .int(ChessRules.perftDivide(standard, depth: 0).count),
            "divide1": .array(ChessRules.perftDivide(standard, depth: 1).map { .array([.string($0.move.uci), .int($0.nodes)]) }),
        ])
        goldenEmit(GoldenFile(
            golden: "chess/perft",
            equivalence: .bit,
            swiftSources: [Self.rules, Self.fenSource, Self.notation, "Tests/checkTests/Fixtures/chess-perft.json"],
            spec: [
                "counts": "ChessRules.perft(position, depth:) 깊이 1 부터. 여섯 공표 국면은 d1~d3(①③ 은 d4 까지), 잎 셋은 픽스처 깊이 전부. 생성기가 픽스처(공표값)와 대조했다 — 어긋나면 엔진이 틀린 것이다.",
                "divide2": "ChessRules.perftDivide(position, depth: 2) — [UCI, 노드] 를 UCI 사전 순으로. 갈린 첫 수를 한 줄로 짚는 표준 도구.",
                "edges": "깊이 0 은 1, 음수는 0, divide 깊이 0 은 빈 목록, divide 깊이 1 은 수마다 1.",
                "outcome": "ChessRules.outcome(position:) — checkmate:<승자> · stalemate · insufficientMaterial · fiftyMoveRule · threefoldRepetition · null.",
            ],
            cases: cases
        ))
    }

    // MARK: chess/fen

    @Test("chess/fen — FEN 입력 → 받았나 · 정규형 · 반복 키 · 판정 · 기물 판정(정규·걷기·공백 변형·거절)")
    func chessFen() throws {
        var inputs: [(String, String)] = []   // (id 머리, 입력)
        var fenDivergence: [String: String] = [:]
        for (index, fen) in Self.perftFens.enumerated() { inputs.append(("perft-\(index + 1)", fen)) }
        for (index, fen) in Self.walkFens(walks: 8, plies: 36, seed: 0xFE_2026_1028).enumerated() {
            inputs.append((String(format: "walk-%03d", index), fen))
        }
        for (index, fen) in Self.contractFens.enumerated() { inputs.append((String(format: "contract-%03d", index), fen)) }
        let base = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
        let spaced: [String] = [
            base.replacingOccurrences(of: " ", with: "\t"),
            base.replacingOccurrences(of: " ", with: "  "),
            " " + base + "\r\n",
            base.replacingOccurrences(of: " ", with: "\u{00A0}"),
            base.replacingOccurrences(of: " ", with: "\u{3000}"),
            base.replacingOccurrences(of: " ", with: "\u{2028}"),
            base.replacingOccurrences(of: " ", with: "\u{0085}"),
            base.replacingOccurrences(of: " ", with: "\u{200B}"),
            base + "\n",
            "r3k2r/8/8/8/8/8/8/R3K2R w KQkq -",
            "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0",
            "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1 extra",
            "r3k2r/8/8/8/8/8/8/R3K2R w KQkq",
            "r3k2r/8/8/8/8/8/8/R3K2R W KQkq - 0 1",
            "r3k2r/8/8/8/8/8/8/R3K2R w kqKQ - 0 1",
            "r3k2r/8/8/8/8/8/8/R3K2R w Kk - 0 1",
            "r3k2r/8/8/8/8/8/8/R3K2R w KQkq e3 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 \u{FF11}",
            "rnbqkbnr/pppppppp/\u{FF18}/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 10000",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 1234567890 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 12345678901 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 2147483648",
            "",
            "   ",
            "8/8/8/8/8/8/8/8/8 w - - 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR/ w KQkq - 0 1",
            "rnbqkbnr//8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
            "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e4 0 1",
            "rnbqkbnr/pppppppp/8/8/4P3/4P3/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
            "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2",
            "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 1 2",
            "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e6 0 2",
        ]
        for (index, text) in spaced.enumerated() { inputs.append((String(format: "shape-%03d", index), text)) }
        // 글자 경계 변형 — Swift 는 Character(확장 그래핌)를 돌며 **첫 스칼라**가 White_Space 인 글자에서 가르고, Kotlin 은 코드 포인트로 가른다.
        // 공백 바로 뒤에 붙는 결합 글자(Extend · ZWJ · SpacingMark)는 Swift 에선 공백 묶음의 일부(구분자)이고 Kotlin 에선 다음 칸의 첫 글자다.
        // 갈리는 줄은 knownDivergence 로 **정확히** 적는다(G §8-16 ① 의 잠금 꼴 — Kotlin 시험이 갈리는 줄 집합이 이 목록과 같아야 초록).
        // Prepend 뒤 공백 · 제어 글자 뒤 결합 부호는 두 쪽 다 거절이라 같은 줄로 함께 싣는다(경계가 넓어지지 않았음을 잰다).
        for (index, (text, divergence)) in Self.graphemeFens.enumerated() {
            let id = String(format: "grapheme-%02d", index)
            inputs.append((id, text))
            if let divergence { fenDivergence[id] = divergence }
        }

        var cases: [GoldenJSON] = []
        var accepted = 0
        var seenOutcome = Set<String>()
        for (id, text) in inputs {
            var item: [String: GoldenJSON] = ["id": .string(id), "input": .string(Self.cps(text))]
            if let divergence = fenDivergence[id] { item["knownDivergence"] = .string(divergence) }
            if let position = ChessPosition(fen: text) {
                accepted += 1
                // 왕복: 정규 FEN 을 다시 읽으면 같은 국면이다.
                #expect(ChessPosition(fen: position.fen) == position, "\(id): 정규 FEN 왕복이 깨졌다")
                for (key, value) in Self.summary(position) { item[key] = value }
                if case .string(let label) = item["outcome"] ?? .null { seenOutcome.insert(label) }
            } else {
                item["parsed"] = false
            }
            cases.append(.object(item))
        }
        #expect(accepted > 250 && accepted < inputs.count, "받은 \(accepted) / \(inputs.count)")
        // 알려진 차이 줄은 Swift 가 받는 줄이다(Kotlin 은 거절) — 그 사실이 바뀌면 목록을 다시 본다.
        for id in fenDivergence.keys {
            let text = try #require(inputs.first { $0.0 == id }?.1)
            #expect(ChessPosition(fen: text) != nil, "\(id): knownDivergence 줄인데 Swift 도 거절한다")
        }
        #expect(seenOutcome.contains("stalemate") && seenOutcome.contains { $0.hasPrefix("checkmate") } && seenOutcome.contains("insufficientMaterial"),
                "판정 종류가 모자란다: \(seenOutcome)")
        goldenEmit(GoldenFile(
            golden: "chess/fen",
            equivalence: .bit,
            // walk-* 를 GomokuAISplitMix64(GomokuAIEngine.swift)로 걷는다 — 난수가 바뀌면 국면이 바뀐다.
            swiftSources: [Self.rules, Self.fenSource, Self.splitMix],
            spec: [
                "input": "코드 포인트 16진 목록. 칸은 White_Space 스칼라로 가른다(빈 조각은 버린다), 4~6칸.",
                "parsed": "ChessPosition(fen:) 이 받았나. 거절(null)이면 다른 칸이 없다.",
                "fields": "fen(정규 6칸) · boardFEN · side · castling(fenText) · enPassant(칸 또는 null) · halfmove · fullmove · repetitionKey(앙파상은 실제로 잡을 수 있을 때만) · inCheck(차례인 쪽) · legal(합법 수 개수) · outcome(반복 표 없이) · insufficient(hasInsufficientMaterial) · noMating{White,Black}(hasNoMatingMaterial) · legalEnPassant(hasLegalEnPassantCapture) · kings[백,흑](kingSquare) · ascii(asciiBoard 를 FNV-1a 64 로 접은 값 — UTF-8 바이트를 하나씩 add).",
                "walk": "walk-* 는 표준·공표 국면에서 SplitMix64 무작위 합법 수로 걸어간 국면의 정규 FEN(생성기 전용 — Kotlin 은 글자에서 읽는다).",
                "knownDivergence": "grapheme-* 중 이 칸이 있는 줄만 Kotlin 이 Swift 와 다르다(Swift 는 받고 Kotlin 은 거절) — 공백 스칼라 바로 뒤에 결합 글자(Extend·ZWJ·SpacingMark)가 붙은 FEN. Swift 는 확장 그래핌의 첫 스칼라로 공백을 보고 Kotlin 은 코드 포인트로 본다(유니코드 판에 기대는 그래핌 경계를 피한 선택). 갈리는 줄 집합이 정확히 이 목록이어야 한다.",
            ],
            cases: cases
        ))
    }

    // MARK: chess/moves

    @Test("chess/moves — 합법 수 생성 순서 + SAN + 효과 + 둔 뒤 FEN")
    func chessMoves() throws {
        var fens: [(String, String)] = []
        for (index, fen) in Self.perftFens.enumerated() { fens.append(("perft-\(index + 1)", fen)) }
        for (index, fen) in Self.specialFens.enumerated() { fens.append((String(format: "special-%02d", index), fen)) }
        let walk = Self.walkFens(walks: 6, plies: 40, seed: 0x5A_2026_1028)
        for (index, fen) in walk.enumerated() where index % 5 == 0 { fens.append((String(format: "walk-%03d", index), fen)) }

        var cases: [GoldenJSON] = []
        var flags: [String: Int] = [:]
        for (id, fen) in fens {
            let position = try #require(ChessPosition(fen: fen), "\(id): \(fen)")
            let legal = ChessRules.legalMoves(in: position)
            var moves: [GoldenJSON] = []
            for move in legal {
                let effect = try #require(ChessRules.effect(of: move, in: position))
                let san = try #require(ChessRules.san(for: move, in: position))
                #expect(ChessRules.move(san: san, in: position) == move, "\(id): SAN \(san) 이 \(move.uci) 로 되읽히지 않는다")
                if effect.isEnPassant { flags["ep", default: 0] += 1 }
                if effect.isCastling { flags["castling", default: 0] += 1 }
                if effect.isPromotion { flags["promotion", default: 0] += 1 }
                if effect.isDoublePawnPush { flags["double", default: 0] += 1 }
                if san.hasSuffix("#") { flags["mate", default: 0] += 1 }
                moves.append([
                    "uci": .string(move.uci),
                    "san": .string(san),
                    "piece": .string(String(effect.piece.fenCharacter)),
                    "captured": effect.captured.map { .string(String($0.fenCharacter)) } ?? .null,
                    "capturedSquare": effect.capturedSquare.map { .string($0.notation) } ?? .null,
                    "rook": effect.rookMove.map { .string($0.uci) } ?? .null,
                    "flags": .string((effect.isEnPassant ? "e" : "") + (effect.isDoublePawnPush ? "d" : "")
                                     + (effect.isCastling ? "c" : "") + (effect.isPromotion ? "p" : "")),
                    "after": .string(effect.after.fen),
                ])
            }
            cases.append(["id": .string(id), "fen": .string(fen), "moves": .array(moves)])
        }
        for key in ["ep", "castling", "promotion", "double", "mate"] {
            #expect((flags[key] ?? 0) > 0, "효과 \(key) 가 한 번도 안 나왔다: \(flags)")
        }
        goldenEmit(GoldenFile(
            golden: "chess/moves",
            equivalence: .bit,
            swiftSources: [Self.rules, Self.fenSource, Self.notation, Self.splitMix],
            spec: [
                "moves": "ChessRules.legalMoves(in:) 의 **순서 그대로**(칸 a1→h8 · 방향 고정 순서 · 승격 Q R B N — AI·서버가 이 순서를 믿는다).",
                "san": "ChessRules.san(for:in:) — 동형 중복 해소는 판에서 직접(파일 → 랭크 → 칸), 폰 잡기는 출발 파일, 승격 '=X', 체크 '+' · 메이트 '#'. 생성기가 move(san:) 왕복을 단언했다.",
                "effect": "ChessRules.effect(of:in:) — piece(움직인 말 FEN 글자) · captured · capturedSquare(앙파상은 도착 칸이 아니다) · rook(캐슬링 룩 길 UCI) · flags(e 앙파상 · d 두 칸 · c 캐슬링 · p 승격) · after(정규 FEN).",
            ],
            cases: cases
        ))
    }

    // MARK: chess/notation

    @Test("chess/notation — SAN 읽기 변형 표 · UCI 읽기 표 · 수순 재생 · 반복 장부")
    func chessNotation() throws {
        var cases: [GoldenJSON] = []
        // SAN 읽기 — 국면마다 합법 수의 정규형 + 변형, 그리고 손으로 고른 모호·불법 입력.
        let sanPositions: [(String, String, [String])] = [
            ("standard", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", ["Pe4", "e5", "Ke2", "O-O", "nf3", "N3", "", "  ", "e4!!", "e2-e4"]),
            ("kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", ["Nd2", "Rd1", "Bd1", "O-O-O+", "0-0", "o-o", "Qxf6+?"]),
            ("knights", "4k3/8/8/2N5/8/2N3N1/8/4K3 w - - 0 1", ["Ne4", "Nce4", "Nc3e4", "N3e4", "N5e4", "Nge4", "Na4"]),
            ("queens", "7k/8/8/3Q1Q2/8/3Q4/8/K7 w - - 0 1", ["Qe4", "Qde4", "Q5e4", "Qd5e4", "Qd5-e4", "Qdxe4"]),
            ("rooks", "4k3/8/8/8/R6R/8/8/4K3 w - - 0 1", ["Rd4", "Rad4", "Rhd4", "R4d4", "Ra4d4"]),
            ("promotion", "1n4k1/P7/8/8/8/8/8/4K3 w - - 0 1", ["a8=Q", "a8Q", "a8=K", "axb8=N", "axb8N", "a7b8n", "a7xb8=R+", "b8=Q"]),
            ("enpassant", "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", ["dxe3", "dxe3 e.p.", "dxe3e.p.", "de3", "d4e3", "exd3"]),
            ("castling", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", ["O-O", "O-O-O", "0-0-0", "Kg1", "e1g1", "OO", "O–O"]),
            ("mate", "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", ["Ra8#", "Ra8", "Ra8+", "Ra1a8", "Rxa8"]),
        ]
        for (name, fen, extras) in sanPositions {
            let position = try #require(ChessPosition(fen: fen), "\(name)")
            var inputs: [String] = []
            for move in ChessRules.legalMoves(in: position) {
                let san = try #require(ChessRules.san(for: move, in: position))
                let bare = san.filter { $0 != "+" && $0 != "#" }
                inputs.append(san)
                inputs.append(bare + "!?")
                inputs.append(" " + bare + "\r\n")
                inputs.append(move.uci.count == 5 ? String(move.uci.prefix(4)) + move.uci.suffix(1).uppercased() : move.uci)
                if san.hasPrefix("O") { inputs.append(san.replacingOccurrences(of: "O", with: "0")) }
            }
            inputs.append(contentsOf: extras)
            var entries: [GoldenJSON] = []
            var seen = Set<String>()
            for input in inputs where seen.insert(input).inserted {
                let move = ChessRules.move(san: input, in: position)
                entries.append(.array([.string(Self.cps(input)), move.map { .string($0.uci) } ?? .null]))
            }
            cases.append(["id": .string("san-\(name)"), "kind": "san", "fen": .string(fen), "entries": .array(entries)])
        }

        // SAN 글자 경계 — Swift 는 글자(확장 그래핌)를 돌며 기호·공백 글자를 걷고, Kotlin 은 코드 포인트를 돈다. 공백(첫 스칼라) 뒤에 결합 글자가
        // 붙은 묶음은 Swift 가 통째로 걷고 Kotlin 은 결합 글자를 남긴다. 갈리는 줄은 entries 의 셋째 칸(knownDivergence)에 적는다 — 정확한 잠금.
        for (name, fen, rows) in Self.graphemeSans {
            let position = try #require(ChessPosition(fen: fen), "\(name)")
            var entries: [GoldenJSON] = []
            for (input, divergence) in rows {
                let move = ChessRules.move(san: input, in: position)
                if divergence != nil { #expect(move != nil, "\(name) '\(input)': knownDivergence 줄인데 Swift 도 null 이다") }
                entries.append(.array([.string(Self.cps(input)), move.map { .string($0.uci) } ?? .null, divergence.map { .string($0) } ?? .null]))
            }
            cases.append(["id": .string("san-\(name)"), "kind": "san", "fen": .string(fen), "entries": .array(entries)])
        }

        // UCI 읽기(모양만).
        let ucis = ["e2e4", "e7e8q", "e7e8Q", "e7e8k", "e7e8p", "e7e8n", "h2h1r", "a1a1", "i1a2", "e2e", "e2e4qq", "E2E4",
                    "e2e4 ", " e2e4", "e2e4\u{0301}", "e9e4", "e0e4", "a7a8b", "", "e2\u{FF45}4", "e2e4x"]
        var uciEntries: [GoldenJSON] = []
        for text in ucis {
            let move = ChessMove(uci: text)
            uciEntries.append(.array([.string(Self.cps(text)), move.map { .string($0.uci) } ?? .null]))
        }
        cases.append(["id": "uci", "kind": "uci", "entries": .array(uciEntries)])

        // 수순 재생 · SAN 기보 · 반복 장부.
        let lines: [(String, String, [String])] = [
            ("scholar", ChessPosition.standard.fen, ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6", "h5f7"]),
            ("enpassant", ChessPosition.standard.fen, ["e2e4", "g8f6", "e4e5", "d7d5", "e5d6", "e7d6", "g1f3", "f8e7", "f1c4", "e8g8", "e1g1"]),
            ("promotion", "1n4k1/P7/8/8/8/8/8/4K3 w - - 0 1", ["a7b8q", "g8h7", "b8b1", "h7g6"]),
            ("shuffle", ChessPosition.standard.fen, ["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8", "b1c3"]),
            ("ep-not-possible", "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1", ["e2e4", "e8d8", "e1d1", "d8e8", "d1e1", "e8d8", "e1d1", "d8e8", "d1e1"]),
            ("illegal", ChessPosition.standard.fen, ["e2e4", "e7e5", "e4e5"]),
            ("malformed", ChessPosition.standard.fen, ["e2e4", "e7e9"]),
        ]
        for (name, fen, uci) in lines {
            let start = try #require(ChessPosition(fen: fen))
            let trail = ChessRules.replay(uciLine: uci, from: start)
            let san = ChessRules.sanLine(uciLine: uci, from: start)
            var ledgerRows: [GoldenJSON] = []
            if let trail {
                var ledger = ChessRepetitionLedger()
                for position in trail {
                    ledger.record(position)
                    ledgerRows.append([
                        "count": .int(ledger.count(of: position)),
                        "outcome": Self.outcomeLabel(ChessRules.outcome(position: position, repetitionCounts: ledger.repetitionCounts)),
                    ])
                }
            }
            cases.append([
                "id": .string("line-\(name)"),
                "kind": "line",
                "fen": .string(fen),
                "uci": .array(uci.map(GoldenJSON.string)),
                "trail": trail.map { .array($0.map { .string($0.fen) }) } ?? .null,
                "san": san.map { .array($0.map(GoldenJSON.string)) } ?? .null,
                "ledger": trail == nil ? .null : .array(ledgerRows),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "chess/notation",
            equivalence: .bit,
            swiftSources: [Self.rules, Self.fenSource, Self.notation],
            spec: [
                "san": "entries = [입력 cps, ChessRules.move(san:in:) 의 UCI 또는 null(, knownDivergence)]. 받는 흔들림: + # ! ? 기호 · '=' 생략 · 0-0 · e.p. · 공백(White_Space) · '-' · 과다 명시(출발 파일·랭크·칸, x 생략, 폰 장형). 모호(둘 이상)·불법이면 null. san-grapheme* 의 셋째 칸이 글자인 줄만 Kotlin 이 다르다(Swift 는 수, Kotlin 은 null — 공백 스칼라 뒤 결합 글자). 갈리는 줄 집합이 정확히 그 목록이어야 한다.",
                "uci": "entries = [입력 cps, ChessMove(uci:) 의 정규 UCI 또는 null] — 4·5글자, 칸 정규형, 승격은 소문자 q·r·b·n 만.",
                "line": "ChessRules.replay(uciLine:from:) 의 trail(시작 포함 정규 FEN) · sanLine · ledger(국면마다 ChessRepetitionLedger.record 뒤 count(of:) 와 outcome(position:repetitionCounts:)). 불법 수가 하나라도 있으면 trail·san·ledger 가 null.",
            ],
            cases: cases
        ))
    }

    // MARK: chess/outcome

    @Test("chess/outcome — 손으로 놓은 국면(엔진 가드) · 사국 · 50수 · 3회 반복 · 시간패 판정 · 시계")
    func chessOutcome() throws {
        var cases: [GoldenJSON] = []
        // 손으로 놓은 국면: 파서를 거치지 않는 package API(빈 판 + subscript + 카운터) — 엔진 가드가 지키는 자리.
        let built: [(String, [String], ChessColor, UInt8, String?, Int, Int)] = [
            ("empty", [], .white, 0, nil, 0, 1),
            ("kings-only", ["e1K", "e8k"], .white, 0, nil, 0, 1),
            ("white-king-missing", ["e8k", "d1Q"], .white, 0, nil, 0, 1),
            ("two-white-kings", ["e1K", "a1K", "e8k"], .white, 0, nil, 0, 1),
            ("halfmove-negative", ["e1K", "e8k", "a1R"], .white, 0, nil, -1, 1),
            ("halfmove-max", ["e1K", "e8k", "a1R"], .white, 0, nil, 1_000_000_000, 1),
            ("halfmove-over", ["e1K", "e8k", "a1R"], .white, 0, nil, 1_000_000_001, 1),
            ("fullmove-zero", ["e1K", "e8k", "a1R"], .white, 0, nil, 0, 0),
            ("fullmove-max", ["e1K", "e8k", "a1R"], .black, 0, nil, 99, 1_000_000_000),
            ("forged-ep", ["e1K", "e8k", "d5P", "e5N"], .white, 0, "e6", 0, 1),
            ("forged-ep-king", ["e1K", "e5k", "d5P"], .white, 0, "e6", 0, 1),
            ("rights-without-rook", ["e1K", "e8k"], .white, 15, nil, 0, 1),
            ("rights-king-moved", ["f1K", "e8k", "h1R", "a1R"], .white, 3, nil, 0, 1),
            ("king-capturable", ["e1K", "e8k", "e2Q"], .white, 0, nil, 0, 1),
            ("king-capturable-pawn", ["e1K", "d7k", "e6P"], .white, 0, nil, 0, 1),
            ("pawn-last-rank", ["e1K", "e8k", "a8P", "h1p"], .white, 0, nil, 0, 1),
            ("pawn-last-rank-black", ["e1K", "e8k", "a8P", "h1p"], .black, 0, nil, 0, 1),
            ("mate-at-100", ["g1K", "g8k", "f7p", "g7p", "h7p", "a8R"], .black, 0, nil, 100, 60),
            ("fifty", ["g1K", "g8k", "f7p", "g7p", "h7p", "a1R"], .white, 0, nil, 100, 60),
        ]
        for (id, pieces, side, rights, ep, halfmove, fullmove) in built {
            var position = ChessPosition.empty
            for text in pieces {
                let square = try #require(ChessSquare(String(text.prefix(2))))
                position[square] = try #require(ChessPiece(fenCharacter: text.last!))
            }
            position.sideToMove = side
            position.castlingRights = ChessCastlingRights(rawValue: rights)
            position.enPassantTarget = ep.flatMap { ChessSquare($0) }
            position.halfmoveClock = halfmove
            position.fullmoveNumber = fullmove
            var item: [String: GoldenJSON] = [
                "id": .string("built-\(id)"),
                "kind": "built",
                "pieces": .array(pieces.map(GoldenJSON.string)),
                "side": .string(side.rawValue),
                "castlingBits": .int(Int(rights)),
                "enPassant": ep.map(GoldenJSON.string) ?? .null,
                "halfmove": .int(halfmove),
                "fullmove": .int(fullmove),
            ]
            for (key, value) in Self.summary(position, built: true) { item[key] = value }
            cases.append(.object(item))
        }

        // FEN 국면 — 반복 표를 넘긴 판정(3회 반복 · 메이트가 먼저) · 사국 · 시간패.
        let repeated: [(String, String, Int)] = [
            ("rep-2", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 7 40", 2),
            ("rep-3", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 7 40", 3),
            ("rep-3-fifty", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 100 90", 3),
            ("rep-3-mate", "R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1", 3),
            ("rep-3-insufficient", "8/8/4k3/8/8/3K1B2/8/8 w - - 0 1", 3),
            ("rep-4-ep", "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", 4),
        ]
        for (id, fen, count) in repeated {
            let position = try #require(ChessPosition(fen: fen), "\(id)")
            cases.append([
                "id": .string(id),
                "kind": "repetition",
                "fen": .string(fen),
                "count": .int(count),
                "outcome": Self.outcomeLabel(ChessRules.outcome(position: position, repetitionCounts: [position.repetitionKey: count])),
                "outcomeOtherKey": Self.outcomeLabel(ChessRules.outcome(position: position, repetitionCounts: [position.fen: count])),
            ])
        }

        // 시계(초 단위 Double).
        let clocks: [(String, ChessClock)] = [("default", ChessClock()), ("short", ChessClock(initialSeconds: 30, incrementSeconds: 3)),
                                              ("no-increment", ChessClock(initialSeconds: 1.5, incrementSeconds: 0))]
        let elapsed: [Double] = [0, -0.0, 1.5, 29.999, 30, 30.000001, 599.999, 600, 600.0001, -1, .nan, .infinity, -.infinity, 1e-9, 0.1 + 0.2]
        for (name, clock) in clocks {
            var rows: [GoldenJSON] = []
            for color in [ChessColor.white, .black] {
                for value in elapsed {
                    let step = clock.afterMove(by: color, elapsed: value)
                    let kind: String
                    var white: GoldenJSON = .null
                    var black: GoldenJSON = .null
                    switch step {
                    case .ticked(let next):
                        kind = "ticked"
                        white = .bits(next.whiteSeconds)
                        black = .bits(next.blackSeconds)
                    case .flagged: kind = "flagged"
                    case .invalidElapsed: kind = "invalid"
                    }
                    rows.append([
                        "color": .string(color.rawValue),
                        "elapsedBits": .bits(value),
                        "step": .string(kind),
                        "whiteBits": white,
                        "blackBits": black,
                        "hasFlagged": clock.hasFlagged(color, elapsed: value).map(GoldenJSON.bool) ?? .null,
                    ])
                }
            }
            cases.append([
                "id": .string("clock-\(name)"),
                "kind": "clock",
                "whiteBits": .bits(clock.whiteSeconds),
                "blackBits": .bits(clock.blackSeconds),
                "incrementBits": .bits(clock.incrementSeconds),
                "rows": .array(rows),
            ])
        }
        cases.append([
            "id": "clock-constants",
            "kind": "clockConstants",
            "initialSecondsBits": .bits(ChessClock.initialSeconds),
            "incrementSecondsBits": .bits(ChessClock.incrementSeconds),
            "initialMs": .int(ChessClock.initialMs),
            "maxFullmoveNumber": .int(ChessPosition.maxFullmoveNumber),
            "maxCountableCounter": .int(ChessPosition.maxCountableCounter),
        ])
        goldenEmit(GoldenFile(
            golden: "chess/outcome",
            equivalence: .bit,
            swiftSources: [Self.rules, Self.fenSource, Self.notation],
            spec: [
                "built": "ChessPosition.empty 에 pieces('<칸><FEN 글자>')를 놓고 side · castlingBits(rawValue 비트 K=1 Q=2 k=4 q=8) · enPassant · halfmove · fullmove 를 그대로 넣은 국면(파서를 거치지 않는다). 칸은 summary 와 같다(perft1·perft2 는 깊이 1·2, timeout{White,Black} 은 그 색 깃발이 떨어졌을 때 timeoutRuling — loss:<깃발 색> 또는 draw).",
                "repetition": "ChessRules.outcome(position:repetitionCounts:) — 표는 {repetitionKey: count}(outcome) 와 {fen: count}(outcomeOtherKey — 키가 다르면 반복으로 안 센다).",
                "clock": "ChessClock.afterMove(by:elapsed:) → ticked(가산 붙은 두 시계, Double 비트) · flagged · invalid(음수·NaN·무한, -0.0 은 0 이다) · hasFlagged(by:) — null 은 성립하지 않는 입력.",
                "clockConstants": "초기 600초 · 가산 3초 · initialMs 600000(서버 chess_initial_ms() 와 같은 숫자) · FEN 수 번호 상한 · 엔진 카운터 상한.",
            ],
            cases: cases
        ))
    }

    // MARK: - 도우미

    /// FEN 글자 경계 변형(입력, 알려진 차이 사유 또는 nil). 사유가 있는 줄은 Swift 가 받고 Kotlin 이 거절한다.
    static let graphemeFens: [(String, String?)] = {
        let base = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
        return [
            (base.replacingOccurrences(of: " ", with: " \u{0301}"), "space+Extend(U+0301)"),
            (base + " \u{0301}", "trailing space+Extend(U+0301)"),
            (" \u{0301}" + base, "leading space+Extend(U+0301)"),
            (base.replacingOccurrences(of: " ", with: " \u{200D}"), "space+ZWJ(U+200D)"),
            (base.replacingOccurrences(of: " ", with: "\u{00A0}\u{0301}"), "NBSP+Extend(U+0301)"),
            (base.replacingOccurrences(of: " ", with: " \u{0903}"), "space+SpacingMark(U+0903)"),
            (base.replacingOccurrences(of: " ", with: " \u{FE0F}"), "space+Extend(U+FE0F)"),
            (base.replacingOccurrences(of: " ", with: "\t\u{0301}"), nil),
            ("\u{0600} " + base, nil),
            (base.replacingOccurrences(of: "R3K2R w", with: "R3K2R\u{0600} w"), nil),
            (base.replacingOccurrences(of: " ", with: "\r\n"), nil),
            (base.replacingOccurrences(of: " w ", with: " w\u{0301} "), nil),
            (base.replacingOccurrences(of: "R3K2R w", with: "R3K2R\u{0301} w"), nil),
            (base + "\u{0301}", nil),
        ]
    }()

    /// SAN 글자 경계 변형(국면 이름, FEN, [(입력, 알려진 차이 사유 또는 nil)]). 사유가 있는 줄은 Swift 가 수를 찾고 Kotlin 은 null 이다.
    static let graphemeSans: [(String, String, [(String, String?)])] = [
        ("grapheme", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", [
            ("Nf3 \u{0301}", "space+Extend(U+0301)"),
            (" \u{0301}Nf3", "leading space+Extend(U+0301)"),
            ("e4\u{00A0}\u{0301}", "NBSP+Extend(U+0301)"),
            ("e4 \u{200D}", "space+ZWJ(U+200D)"),
            ("Nf3\u{0301}", nil),
            ("Nf3+\u{0301}", nil),
            ("Nf3\t\u{0301}", nil),
            ("Nf3\u{0600} ", nil),
            ("N\u{0600} f3", nil),
            ("N\u{0301}f3", nil),
            ("Nf3\r\n", nil),
        ]),
        ("grapheme-castling", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", [
            ("O-O \u{0903}", "space+SpacingMark(U+0903)"),
            ("O-O\u{0301}", nil),
            ("O-O-O\u{2028}", nil),
        ]),
    ]

    static var perftFens: [String] {
        guard let data = try? Data(contentsOf: GoldenRepo.url("Tests/checkTests/Fixtures/chess-perft.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let positions = root["positions"] as? [[String: Any]], let leaves = root["leaves"] as? [[String: Any]] else { return [] }
        return (positions + leaves).compactMap { $0["fen"] as? String }
    }

    /// 특수 국면: 동형 중복 해소 · 승격 · 앙파상(핀 포함) · 캐슬링(경유 칸 공격) · 메이트 · 스테일메이트.
    static let specialFens: [String] = [
        "4k3/8/8/2N5/8/2N3N1/8/4K3 w - - 0 1",
        "7k/8/8/3Q1Q2/8/3Q4/8/K7 w - - 0 1",
        "4k3/8/8/8/R6R/8/8/4K3 w - - 0 1",
        "R7/8/8/8/8/8/8/R3K2k w - - 0 1",
        "1n4k1/P7/8/8/8/8/8/4K3 w - - 0 1",
        "4k3/8/8/8/8/8/1p6/R3K3 b Q - 0 1",
        "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
        "8/8/8/8/k2pP2R/8/8/4K3 b - e3 0 1",
        "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1",
        "r3k2r/8/8/8/8/5r2/8/R3K2R w KQkq - 0 1",
        "r3k2r/8/8/8/8/1r6/8/R3K2R w KQkq - 0 1",
        "r3k2r/8/8/8/8/8/7q/R3K2R b KQkq - 0 1",
        // 캐슬링 칸마다 공격: 도착 칸(g1·c1) · 경유 칸(d1) · 킹이 안 지나는 b1(되어야 한다) · 흑 쪽 도착 칸(g8 · c8).
        "r3k2r/8/8/8/8/6r1/8/R3K2R w KQkq - 0 1",
        "r3k2r/8/8/8/8/2r5/8/R3K2R w KQkq - 0 1",
        "r3k2r/8/8/8/8/3r4/8/R3K2R w KQkq - 0 1",
        "r3k2r/8/6R1/8/8/8/8/R3K2R b KQkq - 0 1",
        "r3k2r/8/2R5/8/8/8/8/R3K2R b KQkq - 0 1",
        "r3k2r/8/1R6/8/8/8/8/R3K2R b KQkq - 0 1",
        "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1",
        "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1",
        "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3",
        "4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1",
        "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4",
    ]

    /// ChessContractTests · ChessRulesTests 에 흩어진 FEN(받아야 할 것과 거절해야 할 것이 섞였다).
    static let contractFens: [String] = [
        "1n6/P7/8/8/8/8/8/K6k w - - 0 1", "22k3/8/8/8/8/8/8/4K3 w - - 0 1", "2b5/8/4k3/8/8/4K3/8/2B5 w - - 0 1",
        "4k2P/8/8/8/8/8/8/4K3 w - - 0 1", "4k3/0/8/8/8/8/8/4K3 w - - 0 1", "4k3/11111111/8/8/8/8/8/4K3 w - - 0 1",
        "4k3/332/8/8/8/8/8/4K3 w - - 0 1", "4k3/44/8/8/8/8/8/4K3 w - - 0 1", "4k3/8/8/2N5/8/2N3N1/8/4K3 w - - 0 1",
        "4k3/8/8/44/8/8/8/4K3 w - - 0 1", "4k3/8/8/4p3/8/8/8/4K3 w - e3 0 1", "4k3/8/8/6N1/8/8/8/4K1N1 w - - 0 1",
        "4k3/8/8/8/2Pn4/8/8/4K3 w - - 0 1", "4k3/8/8/8/8/3p4/8/3QK3 w - - 0 1", "4k3/8/8/8/8/4r3/8/4K2R w K - 0 1",
        "4k3/8/8/8/8/5N2/8/1N2K3 w - - 0 1", "4k3/8/8/8/8/5N2/8/4K3 w - - 0 1", "4k3/8/8/8/8/8/8/1N2KN2 b - - 0 1",
        "4k3/8/8/8/8/8/8/2N1K3 b - - 0 1", "4k3/8/8/8/8/8/8/3QK3 w - - 0 1", "4k3/8/8/8/8/8/8/4K3 w - - -1 1",
        "4k3/8/8/8/8/8/8/4K3 w - - +0 +1", "4k3/8/8/8/8/8/8/4K3 w - - 0 01", "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
        "4k3/8/8/8/8/8/8/4K3 w - - 00 1", "4k3/8/8/8/8/8/8/4K3 w - e6 0 1", "4k3/8/8/8/8/8/8/4K3 w K - 0 1",
        "4k3/8/8/8/8/8/8/4KK2 w - - 0 1", "4k3/8/8/8/8/8/8/R2rK3 w - - 40 60", "4k3/8/8/8/8/8/8/R3K3 b - - 0 1",
        "4k3/8/8/8/8/8/8/R3K3 b - - 0 9223372036854775807", "4k3/8/8/8/8/8/8/R3K3 b Q - 1 1", "4k3/8/8/8/8/8/8/R3K3 b Q - 2 1",
        "4k3/8/8/8/8/8/8/R3K3 w - - 0 10000", "4k3/8/8/8/8/8/8/R3K3 w - - 0 10001", "4k3/8/8/8/8/8/8/R3K3 w - - 0 9223372036854775806",
        "4k3/8/8/8/8/8/8/R3K3 w - - 0 99999999999999999999", "4k3/8/8/8/8/8/8/R3K3 w - - 150 120",
        "4k3/8/8/8/8/8/8/R3K3 w - - 9223372036854775807 1", "4k3/8/8/8/8/8/8/R3K3 w K - 0 1", "4k3/8/8/8/8/8/8/R3K3 w Q - 0 1",
        "4k3/8/8/8/8/8/8/R3K3 w Q - 100 1", "4k3/8/8/8/8/8/8/R3K3 w Q - 100 60", "4k3/8/8/8/8/8/8/R3K3 w Q - 99 100",
        "4k3/8/8/8/8/8/P7/R3K3 w Q - 99 100", "4k3/8/8/8/8/B3B3/8/2B1K3 w - - 0 1", "4k3/8/8/8/8/B7/4P3/2B1K3 w - - 0 1",
        "4k3/8/8/8/8/B7/8/2B1K3 w - - 0 1", "4k3/8/8/8/8/B7/8/2B1KN2 w - - 0 1", "4k3/8/8/8/8/B7/8/3BK3 w - - 0 1",
        "4k3/9/8/8/8/8/8/4K3 w - - 0 1", "4kb2/8/8/8/8/8/8/4K3 w - - 0 1", "4kb2/8/8/8/8/B7/8/2B1K3 w - - 0 1",
        "4R3/4k3/8/8/8/8/8/4K3 w - - 0 1", "5b2/8/4k3/8/8/4K3/8/2B5 w - - 0 1", "5b2/8/4k3/8/8/4K3/8/8 w - - 0 1",
        "6k1/5ppp/8/8/8/8/8/R5K1 w - - 99 60", "7k/2p5/8/KP5r/8/8/8/8 b - - 0 1", "7k/2p5/8/KP6/8/8/8/8 b - - 0 1",
        "8/8/4k3/8/8/3K1B2/8/8 w - - 0 1", "8/8/4k3/8/8/3K1BB1/8/8 w - - 0 1", "8/8/4k3/8/8/3K1BN1/8/8 w - - 0 1",
        "8/8/4k3/8/8/3K1N2/8/8 w - - 0 1", "8/8/4k3/8/8/3K1NN1/8/8 w - - 0 1", "8/8/4k3/8/8/3K1Q2/8/8 w - - 0 1",
        "8/8/4k3/8/8/3K1R2/8/8 w - - 0 1", "8/8/4k3/8/8/3K4/4P3/8 w - - 0 1", "8/8/4k3/8/8/3K4/8/8 w - - 0 1",
        "8/8/8/8/2Pk4/8/8/K7 w - - 0 1", "8/8/8/8/8/5K2/8/4k2R b - - 13 77", "8/8/8/8/8/8/8/8 w - - 0 1",
        "K6k/8/8/8/8/8/p7/1N6 b - - 0 1", "r3k2r/8/8/8/8/1r6/8/R3K2R w KQkq - 0 1", "r3k2r/8/8/8/8/4r3/8/R3K2R w KQkq - 0 1",
        "r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 33 90", "r3k2r/8/8/8/8/8/8/R3KB1R w KQkq - 0 1",
        "R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1", "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2",
        "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR b KQkq e3 99 1", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBN w KQkq - 0 1",
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KKqq - 0 1", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w",
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
        "rnbqkbnrr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1",
    ]

    /// 표준·공표 국면에서 SplitMix64 무작위 합법 수로 걸어간 국면들의 정규 FEN(시작 국면 제외, 끝나면 멈춘다).
    static func walkFens(walks: Int, plies: Int, seed: UInt64) -> [String] {
        var rng = GomokuAISplitMix64(seed: seed)
        let starts = [ChessPosition.standard.fen] + perftFens.prefix(6)
        var out: [String] = []
        for walk in 0..<walks {
            guard var position = ChessPosition(fen: starts[walk % starts.count]) else { continue }
            for _ in 0..<plies {
                let legal = ChessRules.legalMoves(in: position)
                guard !legal.isEmpty else { break }
                let move = legal[Int.random(in: 0..<legal.count, using: &rng)]
                guard let next = ChessRules.apply(move, to: position) else { break }
                position = next
                out.append(position.fen)
            }
        }
        return out
    }

    /// 국면 요약(chess/fen · chess/outcome 공용).
    static func summary(_ position: ChessPosition, built: Bool = false) -> [String: GoldenJSON] {
        var out: [String: GoldenJSON] = [
            "parsed": .bool(true),
            "fen": .string(position.fen),
            "boardFEN": .string(position.boardFEN),
            "side": .string(position.sideToMove.rawValue),
            "castling": .string(position.castlingRights.fenText),
            "enPassant": position.enPassantTarget.map { .string($0.notation) } ?? .null,
            "halfmove": .int(position.halfmoveClock),
            "fullmove": .int(position.fullmoveNumber),
            "repetitionKey": .string(position.repetitionKey),
            "inCheck": .bool(ChessRules.isInCheck(position)),
            "legal": .int(ChessRules.legalMoves(in: position).count),
            "outcome": outcomeLabel(ChessRules.outcome(position: position)),
            "insufficient": .bool(ChessRules.hasInsufficientMaterial(position)),
            "noMatingWhite": .bool(ChessRules.hasNoMatingMaterial(position, color: .white)),
            "noMatingBlack": .bool(ChessRules.hasNoMatingMaterial(position, color: .black)),
            "legalEnPassant": .bool(ChessRules.hasLegalEnPassantCapture(in: position)),
            "kings": .array([ChessColor.white, .black].map { position.kingSquare(of: $0).map { .string($0.notation) } ?? .null }),
            "ascii": .string(fnvText(position.asciiBoard)),
        ]
        if built {
            out.removeValue(forKey: "parsed")
            out["inCheckWhite"] = .bool(ChessRules.isInCheck(position, color: .white))
            out["inCheckBlack"] = .bool(ChessRules.isInCheck(position, color: .black))
            out["moves"] = .array(ChessRules.legalMoves(in: position).map { .string($0.uci) })
            out["perft1"] = .int(ChessRules.perft(position, depth: 1))
            out["perft2"] = .int(ChessRules.perft(position, depth: 2))
            out["timeoutWhite"] = .string(timeoutLabel(ChessRules.timeoutRuling(position: position, flagged: .white)))
            out["timeoutBlack"] = .string(timeoutLabel(ChessRules.timeoutRuling(position: position, flagged: .black)))
            out["reachable"] = .bool(position.hasReachableCounters)
            out["pieces"] = .array(position.pieces.map { .string($0.square.notation + String($0.piece.fenCharacter)) })
        }
        return out
    }

    static func outcomeLabel(_ outcome: ChessOutcome?) -> GoldenJSON {
        guard let outcome else { return .null }
        switch outcome {
        case .checkmate(let winner): return .string("checkmate:\(winner.rawValue)")
        case .stalemate: return "stalemate"
        case .insufficientMaterial: return "insufficientMaterial"
        case .fiftyMoveRule: return "fiftyMoveRule"
        case .threefoldRepetition: return "threefoldRepetition"
        }
    }

    static func timeoutLabel(_ ruling: ChessTimeoutRuling) -> String {
        switch ruling {
        case .loss(let flagged): return "loss:\(flagged.rawValue)"
        case .drawByInsufficientMaterial: return "draw"
        }
    }

    static func fnvText(_ text: String) -> String {
        var hasher = GoldenFNV1a64()
        for byte in text.utf8 { hasher.add(UInt64(byte)) }
        return hasher.hex
    }

    static func cps(_ text: String) -> String { GoldenExportGamesBoardRenju.cps(text) }
}
