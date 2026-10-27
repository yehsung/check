// 원본: Sources/CheckCore/GomokuRules.swift · Sources/CheckCore/GomokuTurnWarning.swift @ 1b8260d (골든 생성기 — W1-b)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// W1-b 골든(렌주 판정): Kotlin `core/rules/…/renju` 가 이 값들과 비트로 대조한다(C§5.1 E7 — 판정과 **노드 수**).
//
//  · renju/cases            코퍼스 91건(Tests/checkTests/Fixtures/renju-cases.json)의 입력 → Swift 판정 · 노드 수.
//                           생성기가 코퍼스 기대값(expected · nodes)과 Swift 결과를 먼저 대조한다(골든이 틀린 Swift 를 옮겨 적지 않게).
//  · renju/forbidden-points 무작위 국면(G1)의 빈칸마다 흑 판정·노드 수, 백 판정, `forbiddenPoints` 목록. 작은 예산 판 셋은 예산 초과 길.
//  · renju/inputs           좌표 표기 · 색 rawValue · 서버 금수 사유 · 서버 판 문자열 · 차례 경고(문턱·세기 비트) 표 ·
//                           차례 경고가 서는 판(watchesMyClock 전수) · 끝난 사유·결과·탭 거절 열거(GomokuStore.swift 의 rawValue 어휘).
//
// 글자 입력은 코드 포인트 16진 목록(`cps`)으로 싣는다(contract/README §2-2 — 전각·공백 글자가 편집기에서 바뀌어도 값이 안 변한다).

@Suite("GoldenExport games-board — 렌주 판정(renju/cases · renju/forbidden-points · renju/inputs)")
struct GoldenExportGamesBoardRenju {
    static let sources = ["Sources/CheckCore/GomokuRules.swift"]

    // MARK: renju/cases

    @Test("renju/cases — 코퍼스 91건: 입력 → 판정 · 노드 수(코퍼스 기대값과 먼저 대조)")
    func renjuCases() throws {
        let data = try Data(contentsOf: GoldenRepo.url("Tests/checkTests/Fixtures/renju-cases.json"))
        let corpus = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(corpus.count == 91, "코퍼스가 91건이 아니다: \(corpus.count)")
        var cases: [GoldenJSON] = []
        var parsedCount = 0
        var nodeChecks = 0
        for item in corpus {
            let id = try #require(item["id"] as? String)
            let black = try #require(item["black"] as? [String])
            let white = try #require(item["white"] as? [String])
            let player = try #require(item["player"] as? String)
            let point = try #require(item["point"] as? String)
            let expected = try #require(item["expected"] as? String)
            let corpusNodes = item["nodes"] as? Int
            let budget = (item["node_budget"] as? Int) ?? GomokuRules.nodeBudget

            var judgement: GoldenJSON = .null
            var nodes: GoldenJSON = .null
            if let (board, color, target) = Self.corpusBoard(black: black, white: white, player: player, point: point) {
                parsedCount += 1
                let result = GomokuRules.judgeCounting(board: board, point: target, color: color, budget: budget)
                #expect(Self.corpusLabel(result.judgement) == expected, "\(id): Swift \(Self.corpusLabel(result.judgement)) ≠ 코퍼스 \(expected)")
                if let corpusNodes {
                    nodeChecks += 1
                    #expect(result.nodes == corpusNodes, "\(id): Swift 노드 \(result.nodes) ≠ 코퍼스 \(corpusNodes)")
                }
                judgement = .string(Self.label(result.judgement))
                nodes = .int(result.nodes)
            } else {
                #expect(expected == "error:invalid-input", "\(id): 입력 검증에서 막혔는데 기대값은 \(expected)")
            }
            cases.append([
                "id": .string(id),
                "black": .array(black.map { .string(Self.cps($0)) }),
                "white": .array(white.map { .string(Self.cps($0)) }),
                "player": .string(Self.cps(player)),
                "point": .string(Self.cps(point)),
                "budget": .int(budget),
                "parsed": .bool(judgement != .null),
                "judgement": judgement,
                "nodes": nodes,
            ])
        }
        let invalidInputs = corpus.filter { ($0["expected"] as? String) == "error:invalid-input" }.count
        #expect(parsedCount >= corpus.count - invalidInputs && nodeChecks >= 60, "파싱 \(parsedCount) · 노드 대조 \(nodeChecks)")
        goldenEmit(GoldenFile(
            golden: "renju/cases",
            equivalence: .bit,
            swiftSources: Self.sources + ["Tests/checkTests/Fixtures/renju-cases.json"],
            spec: [
                "input": "black·white·player·point 는 코드 포인트 16진 목록(cps). 판은 black 먼저, white 다음으로 놓는다. 좌표는 GomokuPoint(notation:) 정규형만(^[A-O]([1-9]|1[0-5])$, 스칼라로 판정), player 는 GomokuColor(rawValue:) 그대로(대소문자 정규화 없음). 좌표가 하나라도 정규형이 아니거나, 같은 칸에 두 번 놓이거나, player 가 색이 아니면 parsed=false(판정 없음).",
                "judge": "GomokuRules.judgeCounting(board:point:color:budget:) — budget 은 코퍼스 node_budget, 없으면 nodeBudget(10000). judgement 는 legal · win · forbidden-double-three · forbidden-double-four · forbidden-overline · forbidden-budget · occupied · out-of-range, nodes 는 §4.2 계수(judgeBlack 진입마다 1, 백 1, 이미 돌 0).",
                "order": "방향 가로→세로→/→\\, 전환점 +d 먼저, 3 판정 단락 평가 · threes==2 즉시 · 남은 수로 못 채우면 조기 legal. 이 순서가 노드 수를 정한다(서버 gomoku_judge 와 예산 초과 여부가 같아야 한다).",
            ],
            cases: cases
        ))
    }

    // MARK: renju/forbidden-points

    @Test("renju/forbidden-points — 무작위 국면 칸마다 흑 판정·노드 · 백 판정 · 금수 표시 목록(작은 예산 판 포함)")
    func renjuForbiddenPoints() throws {
        var rng = GomokuAISplitMix64(seed: 0x0B1B_2026_1028_0001)
        var boards: [(String, GomokuBoard, Int)] = []
        for index in 0..<64 {
            boards.append((String(format: "board-%02d", index), Self.randomBoard(&rng, index: index), GomokuRules.nodeBudget))
        }
        // 작은 예산 — 노드가 많은 칸이 예산 초과(forbidden-budget)로 접히는 길. 같은 판을 다른 예산으로 다시 본다.
        for (index, budget) in [(1, 2), (5, 3), (9, 5), (13, 8)] {
            boards.append((String(format: "budget-%02d-%d", index, budget), boards[index].1, budget))
        }

        var cases: [GoldenJSON] = []
        var seen: [Character: Int] = [:]
        var multiNode = 0
        var mismatches: [String] = []
        for (id, board, budget) in boards {
            var black = ""
            var white = ""
            var nodeList: [GoldenJSON] = []
            var expectedShown: [Int: String] = [:]
            for index in 0..<GomokuBoard.cellCount {
                let point = GomokuPoint(x: index % GomokuBoard.size, y: index / GomokuBoard.size)!
                guard board[point] == nil else {
                    black.append(".")
                    white.append(".")
                    continue
                }
                let result = GomokuRules.judgeCounting(board: board, point: point, color: .black, budget: budget)
                let code = Self.code(result.judgement)
                black.append(code)
                seen[code, default: 0] += 1
                if result.nodes != 1 {
                    nodeList.append([.int(index), .int(result.nodes)])
                    multiNode += 1
                }
                if case .forbidden(let reason) = result.judgement { expectedShown[index] = reason.rawValue }
                white.append(Self.code(GomokuRules.judge(board: board, point: point, color: .white)))
            }
            let shown = GomokuRules.forbiddenPoints(board: board, budget: budget)
            let shownList = shown.map { (key: $0.key.y * GomokuBoard.size + $0.key.x, value: $0.value.rawValue) }
                .sorted { $0.key < $1.key }
            if Dictionary(uniqueKeysWithValues: shownList.map { ($0.key, $0.value) }) != expectedShown { mismatches.append(id) }
            cases.append([
                "id": .string(id),
                "board": .string(board.serverString),
                "budget": .int(budget),
                "black": .string(black),
                "blackNodes": .array(nodeList),
                "white": .string(white),
                "forbidden": .array(shownList.map { .string("\(GomokuPoint(x: $0.key % 15, y: $0.key / 15)!.notation):\($0.value)") }),
            ])
        }
        #expect(mismatches.isEmpty, "forbiddenPoints 와 judgeCounting 이 갈린 판: \(mismatches)")
        // 골든이 공허하지 않다: 판정 종류가 전부 나오고, 재귀(노드 2 이상)와 예산 초과가 실제로 있다.
        for code in ["L", "W", "T", "F", "O", "B"] as [Character] {
            #expect((seen[code] ?? 0) > 0, "무작위 국면에 \(code) 판정이 한 번도 없다: \(seen)")
        }
        #expect(multiNode > 20, "노드 2 이상인 칸이 \(multiNode)개뿐이다")
        goldenEmit(GoldenFile(
            golden: "renju/forbidden-points",
            equivalence: .bit,
            // 판을 GomokuAISplitMix64(GomokuAIEngine.swift)로 만든다 — 난수가 바뀌면 판이 바뀐다.
            swiftSources: Self.sources + ["Sources/CheckCore/GomokuAIEngine.swift"],
            spec: [
                "board": "GomokuBoard.serverString(225자, 인덱스 = y*15 + x, '.'·'b'·'w'). 판은 생성기의 무작위 국면(SplitMix64 + Swift Int.random)이라 Kotlin 은 판을 다시 만들지 않고 이 글자에서 읽는다.",
                "black": "칸마다 흑 judgeCounting(budget) 의 판정 글자: '.' 돌 있음 · L legal · W win · T forbidden-double-three · F forbidden-double-four · O forbidden-overline · B forbidden-budget.",
                "blackNodes": "노드 수가 1 이 아닌 빈칸만 [인덱스, 노드] — 나머지 빈칸은 1.",
                "white": "칸마다 백 judge 판정 글자('.' · L · W).",
                "forbidden": "GomokuRules.forbiddenPoints(board:budget:) 의 결과를 인덱스 순으로 '<좌표>:<rawValue>'. 사전이라 순서는 생성기가 정한다.",
            ],
            cases: cases
        ))
    }

    // MARK: renju/inputs

    @Test("renju/inputs — 좌표 표기 · 색 · 서버 금수 사유 · 서버 판 문자열 · 차례 경고 표")
    func renjuInputs() throws {
        var cases: [GoldenJSON] = []

        let notations = [
            "H8", "A1", "O15", "J10", "A15", "O1", "H15", "I9", "B2", "N14",
            "h8", "H08", " H8", "H8 ", "H8\n", "P8", "H16", "H0", "H", "", "8H", "H\u{FF11}", "\u{FF28}8", "HH8", "H100",
            "@1", "[1", "A01", "A10", "O16", "A\u{0661}", "H8\u{0301}", "I\u{0300}9", "\u{1D400}1",
        ]
        for (index, text) in notations.enumerated() {
            let point = GomokuPoint(notation: text)
            if let point { #expect(GomokuPoint(notation: point.notation) == point) }
            cases.append([
                "id": .string(String(format: "notation-%02d", index)),
                "kind": "notation",
                "input": .string(Self.cps(text)),
                "x": point.map { .int($0.x) } ?? .null,
                "y": point.map { .int($0.y) } ?? .null,
                "notation": point.map { .string($0.notation) } ?? .null,
            ])
        }
        #expect(cases.filter { $0["x"] != .null }.count == 11, "정규형 열한 개만 읽혀야 한다")

        for (index, text) in ["black", "white", "Black", "WHITE", "", " black", "black\n"].enumerated() {
            cases.append([
                "id": .string(String(format: "color-%02d", index)),
                "kind": "color",
                "input": .string(Self.cps(text)),
                "color": GomokuColor(rawValue: text).map { .string($0.rawValue) } ?? .null,
            ])
        }

        let reasons: [String?] = [
            nil, "", "   ", "double-three", "forbidden-double-four", "overline", "budget", "double_three",
            " Budget\n", "FORBIDDEN-OVERLINE", "forbidden_double_three", "nonsense", "forbidden-", "forbidden-forbidden-budget",
            "\u{3000}overline\u{00A0}", "\tdouble-four\r\n", "double three", "\u{200B}budget",
            "\u{180E}budget", "\u{FEFF}budget", "budget\u{2028}", "\u{1680}overline\u{205F}",
        ]
        for (index, text) in reasons.enumerated() {
            cases.append([
                "id": .string(String(format: "reason-%02d", index)),
                "kind": "serverReason",
                "input": text.map { .string(Self.cps($0)) } ?? .null,
                "reason": GomokuForbiddenReason(serverReason: text).map { .string($0.rawValue) } ?? .null,
            ])
        }

        var sample = GomokuBoard()
        sample[GomokuPoint(x: 7, y: 7)!] = .black
        sample[GomokuPoint(x: 1, y: 0)!] = .white
        sample[GomokuPoint(x: 0, y: 14)!] = .black
        let dots224 = String(repeating: ".", count: 224)
        let boardTexts = [
            String(repeating: ".", count: 225), dots224, dots224 + "B", dots224 + "w", dots224 + "b", sample.serverString,
            dots224 + "\u{E9}", String(repeating: ".", count: 223) + "\u{E9}", dots224 + "x", String(repeating: ".", count: 226),
            dots224 + " ", String(repeating: "w", count: 225),
        ]
        for (index, text) in boardTexts.enumerated() {
            let board = GomokuBoard(serverString: text)
            if let board { #expect(board.serverString == text) }
            cases.append([
                "id": .string(String(format: "board-%02d", index)),
                "kind": "serverString",
                "input": .string(Self.cps(text)),
                "valid": .bool(board != nil),
                "stoneCount": board.map { .int($0.stoneCount) } ?? .null,
            ])
        }

        let remainders: [Double?] = [
            nil, .nan, .infinity, -.infinity, 3.0, 3.0.nextUp, 3.0000001, 2.4, 1.5, 0.1, 0, -0.0, -1, -1000,
            2.9999999, 1.0 / 3.0, 0.0001, 1e-300, 2.0, 2.5,
        ]
        for (index, remaining) in remainders.enumerated() {
            cases.append([
                "id": .string(String(format: "warning-%02d", index)),
                "kind": "turnWarning",
                "remainingBits": remaining.map { .bits($0) } ?? .null,
                "active": .bool(GomokuTurnWarning.isActive(remaining: remaining)),
                "intensityBits": .bits(GomokuTurnWarning.intensity(remaining: remaining)),
            ])
        }
        // 차례 경고가 **설 수 있는** 판 — watchesMyClock 전수(끝남 × 마감 × 차례 × 내 색) + 판 없음.
        // AI 판은 AI 차례에 마감이 언제나 nil 이라 renju/ai-game 에 (안 끝남 · 마감 있음 · 상대 차례)가 한 번도 없다 — 1:1 판(상대 차례에도
        // 마감이 돈다)의 그 갈래를 여기서 잰다(Swift V0351GomokuLowTimeGlowTests.turnWarningWatchesOnlyMyRunningClock 과 같은 갈래).
        let watchNow = Date(timeIntervalSince1970: 1_800_000_000)
        var watchIndex = 0
        for finished in [false, true] {
            for hasDeadline in [false, true] {
                for turn in [nil, GomokuColor.black, GomokuColor.white] {
                    for myColor in GomokuColor.allCases {
                        let state = GomokuMatchState(
                            id: "m", stake: 5, myColor: myColor, opponent: .gomokuAI, board: GomokuBoard(), lastMove: nil, moveCount: 0,
                            turn: turn, deadline: hasDeadline ? watchNow.addingTimeInterval(2) : nil, isFinished: finished,
                            outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false
                        )
                        cases.append([
                            "id": .string(String(format: "watch-%02d", watchIndex)),
                            "kind": "turnWatches",
                            "match": true,
                            "finished": .bool(finished),
                            "deadline": .bool(hasDeadline),
                            "turn": turn.map { .string($0.rawValue) } ?? .null,
                            "myColor": .string(myColor.rawValue),
                            "watches": .bool(GomokuTurnWarning.watchesMyClock(state)),
                        ])
                        watchIndex += 1
                    }
                }
            }
        }
        cases.append(["id": "watch-none", "kind": "turnWatches", "match": false, "watches": .bool(GomokuTurnWarning.watchesMyClock(nil))])
        let watching = cases.filter { $0["kind"] == .string("turnWatches") && $0["watches"] == .bool(true) }.count
        #expect(watching == 2, "켜지는 판은 (안 끝남 · 마감 있음 · 차례 = 내 색) 둘뿐이어야 한다: \(watching)")

        // 끝난 사유 · 결과 · 탭 거절 — 서버·로그 어휘(rawValue)와 케이스 순서. 셋 다 GomokuStore.swift 에 선언돼 있고 Kotlin 은 rules 의
        // GomokuMatchTypes.kt 에 둔다(스토어 갈래가 그대로 가져다 쓴다). 목록이 손으로 적은 것이 아니게 전수 스위치로 순서를 잰다.
        #expect(Self.endReasons.enumerated().allSatisfy { Self.endReasonOrdinal($0.element) == $0.offset }, "끝난 사유 목록이 전수 스위치와 다르다")
        #expect(Self.outcomes.enumerated().allSatisfy { Self.outcomeOrdinal($0.element) == $0.offset }, "결과 목록이 전수 스위치와 다르다")
        cases.append([
            "id": "enum-end-reason",
            "kind": "endReasonCases",
            "rawValues": .array(Self.endReasons.map { .string($0.rawValue) }),
        ])
        cases.append([
            "id": "enum-outcome",
            "kind": "outcomeCases",
            "names": .array(Self.outcomes.map { .string(String(describing: $0)) }),
        ])
        cases.append([
            "id": "enum-tap-refusal",
            "kind": "tapRefusalCases",
            "rawValues": .array(GomokuTapRefusal.allCases.map { .string($0.rawValue) }),
        ])
        let rawInputs = [
            "five", "timeout", "resign", "board_full", "abandoned", "boardFull", "board-full", "Five", " five", "five\n", "",
            "not-your-turn", "busy", "occupied", "finished", "signed-out", "no-match", "forbidden", "notYourTurn", "signed_out",
            "no_match", "BUSY", "forbidden-overline",
        ]
        for (index, text) in rawInputs.enumerated() {
            cases.append([
                "id": .string(String(format: "raw-%02d", index)),
                "kind": "enumRawValue",
                "input": .string(Self.cps(text)),
                "endReason": GomokuEndReason(rawValue: text).map { .string($0.rawValue) } ?? .null,
                "tapRefusal": GomokuTapRefusal(rawValue: text).map { .string($0.rawValue) } ?? .null,
            ])
        }

        cases.append([
            "id": "warning-constants",
            "kind": "turnWarningConstants",
            "lowTimeSecondsBits": .bits(GomokuTurnWarning.lowTimeSeconds),
            "minimumIntensityBits": .bits(GomokuTurnWarning.minimumIntensity),
            "maximumIntensityBits": .bits(GomokuTurnWarning.maximumIntensity),
            "tintBits": .array([.bits(GomokuTurnWarning.tintRed), .bits(GomokuTurnWarning.tintGreen), .bits(GomokuTurnWarning.tintBlue)]),
            "depthRatioBits": .bits(Double(GomokuTurnWarning.depthRatio)),
            "cornerRatioBits": .bits(Double(GomokuTurnWarning.cornerRatio)),
            "layerCount": .int(GomokuTurnWarning.layerCount),
            "peakOpacityBits": .bits(GomokuTurnWarning.peakOpacity),
            "nodeBudget": .int(GomokuRules.nodeBudget),
        ])

        goldenEmit(GoldenFile(
            golden: "renju/inputs",
            equivalence: .bit,
            // GomokuStore.swift: 끝난 사유·결과·탭 거절 열거와 GomokuMatchState(watchesMyClock 의 입력)가 거기 있다.
            swiftSources: Self.sources + ["Sources/CheckCore/GomokuTurnWarning.swift", "Sources/CheckCore/GomokuStore.swift"],
            spec: [
                "input": "글자 입력은 코드 포인트 16진 목록(공백 구분, 빈 글자는 \"\"). null 은 nil 입력.",
                "notation": "GomokuPoint(notation:) → x·y·notation(실패면 null). 정규형만 받는다 — 스칼라 둘·셋, 첫 스칼라 A…O, 나머지 ASCII 숫자, 0 채움 금지, 행 1…15.",
                "color": "GomokuColor(rawValue:) — 글자가 정확히 같을 때만.",
                "serverReason": "GomokuForbiddenReason(serverReason:) — 앞뒤 Foundation whitespacesAndNewlines(유니코드 White_Space + U+200B — 맥에서 전수로 잰 집합) 걷고 lowercased, 'forbidden-' 접두가 없으면 붙이고 '_' → '-', rawValue 로 읽는다. U+180E·U+FEFF 는 공백이 아니다.",
                "serverString": "GomokuBoard(serverString:) — UTF-8 바이트가 정확히 225개이고 전부 '.'·'b'·'w' 일 때만 valid, stoneCount 는 돌 수. valid 면 serverString 왕복이 같다.",
                "turnWarning": "GomokuTurnWarning.isActive(remaining:) · intensity(remaining:) — null·NaN·±무한은 꺼짐(0), remaining ≤ 3 이면 켜짐, 세기 = 0.55 + 0.45 × (1 − min(1, max(0, r/3))) (Swift max/min: max(x,y) = y >= x ? y : x).",
                "turnWarningConstants": "문턱·세기·그림 상수(Double 비트) · 겹 수 · 렌주 노드 예산(서버 gomoku_judge 와 같은 상수).",
                "turnWatches": "GomokuTurnWarning.watchesMyClock(GomokuMatchState?) 전수 — finished × deadline(있음/없음) × turn(null·black·white) × myColor. 켜짐은 안 끝남 · 마감 있음 · turn == myColor 뿐. match=false 는 판 없음(nil) — 언제나 false(Kotlin 은 원시 인자 서명이라 부르는 스토어가 판 없음을 false 로 접는다).",
                "endReasonCases": "GomokuEndReason 케이스 순서대로 rawValue(서버 어휘 — timeout 은 옛 어휘라 지우지 않는다).",
                "outcomeCases": "GomokuOutcome 케이스 순서대로 이름.",
                "tapRefusalCases": "GomokuTapRefusal.allCases 순서대로 rawValue(로그 어휘).",
                "enumRawValue": "GomokuEndReason(rawValue:) · GomokuTapRefusal(rawValue:) — 글자가 정확히 같을 때만(대소문자·공백·'_'↔'-' 정규화 없음).",
            ],
            cases: cases
        ))
    }

    // MARK: - 도우미

    /// 끝난 사유 전 케이스(선언 순서). Swift 열거가 CaseIterable 이 아니라 손으로 적는다 — [endReasonOrdinal] 의 전수 스위치가
    /// 케이스가 늘면 컴파일을 깨서 이 목록을 고치게 한다.
    static let endReasons: [GomokuEndReason] = [.five, .timeout, .resign, .boardFull, .abandoned]
    static func endReasonOrdinal(_ reason: GomokuEndReason) -> Int {
        switch reason {
        case .five: return 0
        case .timeout: return 1
        case .resign: return 2
        case .boardFull: return 3
        case .abandoned: return 4
        }
    }

    static let outcomes: [GomokuOutcome] = [.won, .lost, .draw]
    static func outcomeOrdinal(_ outcome: GomokuOutcome) -> Int {
        switch outcome {
        case .won: return 0
        case .lost: return 1
        case .draw: return 2
        }
    }

    /// 코드 포인트 16진 목록(소문자, 4자리 이상, 공백 구분).
    static func cps(_ text: String) -> String {
        text.unicodeScalars.map { scalar -> String in
            let hex = String(scalar.value, radix: 16)
            return hex.count >= 4 ? hex : String(repeating: "0", count: 4 - hex.count) + hex
        }.joined(separator: " ")
    }

    static func label(_ judgement: GomokuJudgement) -> String {
        switch judgement {
        case .legal: return "legal"
        case .win: return "win"
        case .forbidden(let reason): return reason.rawValue
        case .occupied: return "occupied"
        case .outOfRange: return "out-of-range"
        }
    }

    /// 코퍼스 어휘(V0327GomokuRulesTests 와 같은 접기).
    static func corpusLabel(_ judgement: GomokuJudgement) -> String {
        switch judgement {
        case .legal: return "legal"
        case .win: return "win"
        case .forbidden(.budget): return "error:budget-exceeded"
        case .forbidden(let reason): return reason.rawValue
        case .occupied, .outOfRange: return "error:invalid-input"
        }
    }

    static func code(_ judgement: GomokuJudgement) -> Character {
        switch judgement {
        case .legal: return "L"
        case .win: return "W"
        case .forbidden(.doubleThree): return "T"
        case .forbidden(.doubleFour): return "F"
        case .forbidden(.overline): return "O"
        case .forbidden(.budget): return "B"
        case .occupied, .outOfRange: return "?"
        }
    }

    /// 코퍼스 입력 → 앱 타입(V0327GomokuRulesTests.corpusBoard 와 같은 검증).
    static func corpusBoard(black: [String], white: [String], player: String, point: String)
        -> (GomokuBoard, GomokuColor, GomokuPoint)? {
        guard let color = GomokuColor(rawValue: player) else { return nil }
        var board = GomokuBoard()
        for (list, stone) in [(black, GomokuColor.black), (white, GomokuColor.white)] {
            for notation in list {
                guard let target = GomokuPoint(notation: notation), board[target] == nil else { return nil }
                board[target] = stone
            }
        }
        guard let target = GomokuPoint(notation: point) else { return nil }
        return (board, color, target)
    }

    /// 국면 생성기 넷(균일 · 빽빽한 상자 · 군집 성장 · 중앙 쏠림) — V0327 무작위 국면과 같은 모양(재귀 3-3 을 부르려고 흑을 많이 둔다).
    static func randomBoard(_ rng: inout GomokuAISplitMix64, index: Int) -> GomokuBoard {
        var board = GomokuBoard()
        var stones: [(Int, Int)] = []
        func place(_ x: Int, _ y: Int, _ color: GomokuColor) {
            guard let point = GomokuPoint(x: x, y: y), board[point] == nil else { return }
            board[point] = color
            stones.append((x, y))
        }
        switch index % 4 {
        case 0:
            let count = Int.random(in: 8...110, using: &rng)
            let bias = Double.random(in: 0.5...0.65, using: &rng)
            var guardCount = 0
            while stones.count < count, guardCount < 5_000 {
                guardCount += 1
                place(Int.random(in: 0..<15, using: &rng), Int.random(in: 0..<15, using: &rng),
                      Double.random(in: 0..<1, using: &rng) < bias ? .black : .white)
            }
        case 1:
            let size = Int.random(in: 7...9, using: &rng)
            let ox = Int.random(in: 0...(15 - size), using: &rng)
            let oy = Int.random(in: 0...(15 - size), using: &rng)
            let fill = Double.random(in: 0.35...0.7, using: &rng)
            let bias = Double.random(in: 0.55...0.8, using: &rng)
            for y in oy..<(oy + size) {
                for x in ox..<(ox + size) where Double.random(in: 0..<1, using: &rng) < fill {
                    place(x, y, Double.random(in: 0..<1, using: &rng) < bias ? .black : .white)
                }
            }
        case 2:
            let count = Int.random(in: 20...70, using: &rng)
            place(Int.random(in: 0..<15, using: &rng), Int.random(in: 0..<15, using: &rng), .black)
            var guardCount = 0
            while stones.count < count, guardCount < 10_000 {
                guardCount += 1
                let base = stones[Int.random(in: 0..<stones.count, using: &rng)]
                place(base.0 + Int.random(in: -2...2, using: &rng), base.1 + Int.random(in: -2...2, using: &rng),
                      Double.random(in: 0..<1, using: &rng) < 0.62 ? .black : .white)
            }
        default:
            let count = Int.random(in: 15...90, using: &rng)
            var guardCount = 0
            while stones.count < count, guardCount < 5_000 {
                guardCount += 1
                let x = (0..<3).reduce(0) { acc, _ in acc + Int.random(in: 0...4, using: &rng) } + 1
                let y = (0..<3).reduce(0) { acc, _ in acc + Int.random(in: 0...4, using: &rng) } + 1
                place(x, y, Double.random(in: 0..<1, using: &rng) < 0.6 ? .black : .white)
            }
        }
        return board
    }
}
