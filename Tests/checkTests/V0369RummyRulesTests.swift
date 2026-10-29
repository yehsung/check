// 없으면 어떤 결함이 초록으로 통과하는가: 조커 값(R-07)·첫 등록 30(R-11)·판 보존(R-16)·막힘 정산(R-23·R-24)·등수 분배(§2.1)를
// Swift 와 서버가 각자 다르게 셈해도, 편집기가 판 타일을 랙으로 받아도(R-14) 아무 시험도 빨개지지 않는다.
import Foundation
import Testing
@testable import CheckCore

// v0.3.69 아잉 큐브(rummy) — 규칙 판정과 차례 작업 상태 편집기.
//
// 기대값의 집은 `Fixtures/rummy/cases.json`(research 의 코퍼스를 그대로 복사, meld 74 · turn 64 · score 16) 과
// 설계서 §2.1 P01~P10 표다. 서버 마이그레이션의 코퍼스 프로브도 같은 두 곳을 옮긴다 — 여기서 숫자를 따로 지어 적지 마라.
// 코퍼스 154건은 건수까지 잰다: 파일이 비거나 잘려도 "어긋남 0" 으로 초록이 되지 않게.

// MARK: - 코퍼스

private struct RummyCorpus: Decodable {
    struct Meld: Decodable {
        let id: String
        let tiles: [String]
        let valid: Bool
        let kind: String?
        let points: Int?
    }

    struct Turn: Decodable {
        let id: String
        let initialDone: Bool
        let tableBefore: [[String]]
        let rackBefore: [String]
        let tableAfter: [[String]]
        let valid: Bool
        let reason: String
    }

    struct Score: Decodable {
        let id: String
        let racks: [String: [String]]
        let expected: [String: Int]
        let winners: [String]?
    }

    let meld: [Meld]
    let turn: [Turn]
    let score: [Score]
}

private struct RummyFixtureError: Error, CustomStringConvertible {
    let description: String
}

private func rummyCorpus() throws -> RummyCorpus {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/rummy/cases.json")
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw RummyFixtureError(description: "픽스처가 없다: \(url.path) — 기대값의 집이 하나뿐이라 이게 없으면 잴 것이 없다")
    }
    return try JSONDecoder().decode(RummyCorpus.self, from: Data(contentsOf: url))
}

/// 면 글자 → RummyFace. 하나라도 R-01 밖이면 nil(= 그 입력은 Swift 타입으로 만들 수조차 없다).
private func faces(_ texts: [String]) -> [RummyFace]? {
    let parsed = texts.compactMap(RummyFace.init(text:))
    return parsed.count == texts.count ? parsed : nil
}

private func table(_ texts: [[String]]) -> [[RummyFace]]? {
    let parsed = texts.compactMap(faces)
    return parsed.count == texts.count ? parsed : nil
}

private func f(_ text: String) -> RummyFace {
    guard let face = RummyFace(text: text) else { preconditionFailure("시험 면 오타: \(text)") }
    return face
}

private func fs(_ text: String) -> [RummyFace] {
    text.split(separator: " ").map { f(String($0)) }
}

/// "p1".."p4" → 0-기반 자리.
private func seatIndex(_ key: String) -> Int {
    Int(key.dropFirst())! - 1
}

// MARK: - §2.1 payouts 표(설계서 그대로)

private struct PayoutCase {
    let id: String
    let n: Int
    let stake: Int
    let seats: [RummyPayoutSeat]
    let payouts: [Int]
    let ranks: [Int]?
}

private func a(_ seat: Int, _ score: Int, _ tiles: Int) -> RummyPayoutSeat {
    RummyPayoutSeat(active: true, score: score, tiles: tiles, seat: seat)
}

private func x(_ seat: Int, _ order: Int) -> RummyPayoutSeat {
    RummyPayoutSeat(active: false, score: 0, tiles: 0, seat: seat, forfeitOrder: order)
}

private let payoutCases: [PayoutCase] = [
    PayoutCase(id: "P01", n: 2, stake: 5, seats: [a(0, 20, 0), a(1, -20, 3)], payouts: [10, 0], ranks: nil),
    PayoutCase(id: "P02", n: 4, stake: 5, seats: [a(0, 30, 0), a(1, -5, 2), a(2, -10, 3), a(3, -15, 4)],
               payouts: [15, 5, 0, 0], ranks: nil),
    PayoutCase(id: "P03", n: 4, stake: 3, seats: [a(0, 22, 0), a(1, -5, 2), a(2, -5, 3), a(3, -12, 4)],
               payouts: [9, 2, 1, 0], ranks: [1, 2, 2, 4]),
    PayoutCase(id: "P04", n: 4, stake: 10, seats: [a(0, 11, 3), a(1, 11, 1), a(2, -12, 5), a(3, -10, 4)],
               payouts: [20, 20, 0, 0], ranks: [1, 1, 4, 3]),
    PayoutCase(id: "P05", n: 3, stake: 5, seats: [a(0, 7, 0), a(1, -7, 2), x(2, 1)], payouts: [10, 5, 0], ranks: nil),
    PayoutCase(id: "P06", n: 4, stake: 5, seats: [a(0, 0, 6), x(1, 1), x(2, 2), x(3, 3)],
               payouts: [20, 0, 0, 0], ranks: [1, 4, 3, 2]),
    PayoutCase(id: "P07", n: 4, stake: 3, seats: [a(0, -10, 3), a(1, 25, 0), a(2, -15, 4), x(3, 1)],
               payouts: [3, 9, 0, 0], ranks: nil),
    PayoutCase(id: "P08", n: 3, stake: 10, seats: [a(0, 0, 2), a(1, 0, 1), a(2, 0, 1)], payouts: [10, 10, 10], ranks: nil),
    PayoutCase(id: "P09", n: 4, stake: 5, seats: [a(0, -3, 1), a(1, 9, 0), a(2, -3, 2), a(3, -3, 1)],
               payouts: [2, 15, 1, 2], ranks: [2, 1, 2, 2]),
    PayoutCase(id: "P10", n: 2, stake: 3, seats: [a(0, 0, 5), x(1, 1)], payouts: [6, 0], ranks: nil),
]

// MARK: - 시험

@Suite struct V0369RummyRulesTests {
    @Test func corpusHasAll154Cases() throws {
        let corpus = try rummyCorpus()
        #expect(corpus.meld.count == 74)
        #expect(corpus.turn.count == 64)
        #expect(corpus.score.count == 16)
        #expect(corpus.meld.count + corpus.turn.count + corpus.score.count == 154)
    }

    @Test func meldCorpusMatchesAnalyze() throws {
        let corpus = try rummyCorpus()
        var checked = 0
        for c in corpus.meld {
            guard let meld = faces(c.tiles) else {
                // R-01 밖 면이 든 세트는 만들 수 없다 = 무효.
                #expect(!c.valid, "\(c.id) 면 파싱 실패인데 기대가 유효")
                checked += 1
                continue
            }
            let got = RummyRules.analyze(meld)
            #expect(got.valid == c.valid, "\(c.id) \(c.tiles) valid")
            #expect(got.kind?.rawValue == c.kind, "\(c.id) \(c.tiles) kind")
            #expect(got.points == c.points, "\(c.id) \(c.tiles) points")
            // 세트 안 순서는 판정에 의미 없다(R-09): 뒤집어도 같은 답.
            #expect(RummyRules.analyze(meld.reversed()) == got, "\(c.id) 순서 무관")
            checked += 1
        }
        #expect(checked == 74)
    }

    @Test func turnCorpusMatchesJudge() throws {
        let corpus = try rummyCorpus()
        var checked = 0
        for c in corpus.turn {
            let got: RummyTurnReason
            if let after = table(c.tableAfter) {
                // 형식 검사는 tableAfter 만 본다(R-16 0단계, v1.1). 랙·이전 판의 이상한 면은 판정 입력에서 빠진다.
                let before = table(c.tableBefore.map { $0.filter { RummyFace(text: $0) != nil } }) ?? []
                let rack = c.rackBefore.compactMap(RummyFace.init(text:))
                got = RummyRules.judgeTurn(initialDone: c.initialDone, tableBefore: before, rackBefore: rack, tableAfter: after)
            } else {
                // tableAfter 에 R-01 밖 면이 있다 → RummyFace 가 거절한다 = 서버의 malformed.
                got = .malformed
            }
            #expect(got.rawValue == c.reason, "\(c.id) 기대 \(c.reason) 받음 \(got.rawValue)")
            #expect((got == .ok) == c.valid, "\(c.id) valid")
            checked += 1
        }
        #expect(checked == 64)
        // 코퍼스가 reason 9개를 다 밟는가(어휘 하나가 통째로 안 재지는 일 방지).
        let reasons = Set(corpus.turn.map(\.reason))
        #expect(reasons == Set(RummyTurnReason.allCases.filter { $0 != .unknown }.map(\.rawValue)))
    }

    @Test func scoreCorpusMatchesFinalScores() throws {
        let corpus = try rummyCorpus()
        var checked = 0
        for c in corpus.score {
            let keys = c.racks.keys.sorted { seatIndex($0) < seatIndex($1) }
            #expect(keys.map(seatIndex) == Array(0..<keys.count), "\(c.id) 자리 키 p1..pn")
            let racks = keys.map { faces(c.racks[$0]!)! }
            let got = RummyRules.finalScores(racks: racks)
            #expect(got.scores == keys.map { c.expected[$0]! }, "\(c.id) scores \(got.scores)")
            #expect(got.scores.reduce(0, +) == 0, "\(c.id) 영합")
            let winners = try #require(c.winners, "\(c.id) winners 없음")
            #expect(got.winners == winners.map(seatIndex), "\(c.id) winners \(got.winners)")
            checked += 1
        }
        #expect(checked == 16)
    }

    @Test func payoutTableP01toP10() {
        #expect(payoutCases.count == 10)
        for c in payoutCases {
            let got = RummyRules.payouts(seatCount: c.n, stake: c.stake, seats: c.seats)
            #expect(got.payouts == c.payouts, "\(c.id) payouts \(got.payouts)")
            #expect(got.payouts.reduce(0, +) == c.n * c.stake, "\(c.id) 제로섬")
            if let ranks = c.ranks {
                #expect(got.ranks == ranks, "\(c.id) ranks \(got.ranks)")
            }
        }
    }

    @Test func payoutRanksForEveryCase() {
        // 표에 등수가 적히지 않은 여섯 건도 §2.1 ⑤ 정의로 손계산한 값.
        let expected: [String: [Int]] = [
            "P01": [1, 2], "P02": [1, 2, 3, 4], "P05": [1, 2, 3], "P07": [2, 1, 3, 4], "P08": [1, 1, 1], "P10": [1, 2],
        ]
        for c in payoutCases {
            guard let ranks = expected[c.id] else { continue }
            #expect(RummyRules.payouts(seatCount: c.n, stake: c.stake, seats: c.seats).ranks == ranks, "\(c.id)")
        }
    }

    @Test func settlementP11CoWinnersShareRubyAndRank() {
        // 설계서 §2.1 0번 · P11(V1-01): 막힘 끝 최소 집단은 분배 점수를 ⌊P/m⌋ 로 같게 — 화면 점수의 나머지 1점이
        // 묶음을 가르면 같은 값 두 사람이 15/5 · 1위/2위로 갈린다(서버 tests/f_fix2.sql F1 과 같은 값).
        func settle(_ racks: [[RummyFace]], stake: Int) -> (scores: [Int], payouts: [Int], ranks: [Int], winners: [Int]) {
            let final = RummyRules.finalScores(racks: racks)
            let paid = RummyRules.payoutScores(racks: racks)
            let got = RummyRules.payouts(seatCount: racks.count, stake: stake, seats: racks.indices.map {
                RummyPayoutSeat(active: true, score: paid[$0], tiles: racks[$0].count, seat: $0, forfeitOrder: nil)
            })
            return (final.scores, got.payouts, got.ranks, final.winners)
        }
        let p11 = settle([fs("A2"), fs("B2"), fs("C5"), fs("D6")], stake: 5)
        #expect(p11.scores == [4, 3, -3, -4], "화면 점수는 R-24 그대로")
        #expect(RummyRules.payoutScores(racks: [fs("A2"), fs("B2"), fs("C5"), fs("D6")]) == [3, 3, -3, -4])
        #expect(p11.payouts == [10, 10, 0, 0])
        #expect(p11.ranks == [1, 1, 3, 4])
        #expect(p11.winners == [0, 1])
        // 장수가 다른 최소 집단(F1b): 점수 [2,3,−5] · 승자 s1 만 · 상금은 한 묶음 [7,8,0](나머지는 장수 적은 쪽) · 등수 [1,1,3]
        let b = settle([fs("A1 B1"), fs("C2"), fs("D7")], stake: 5)
        #expect(b.scores == [2, 3, -5] && b.winners == [1])
        #expect(b.payouts == [7, 8, 0] && b.ranks == [1, 1, 3])
        // 빈 랙 끝(R-22)·혼자 남음은 그대로.
        #expect(RummyRules.payoutScores(racks: [fs("A2"), [], fs("B3")]) == RummyRules.finalScores(racks: [fs("A2"), [], fs("B3")]).scores)
        #expect(RummyRules.payoutScores(racks: [fs("A2 B2")]) == [0])
    }

    @Test func displayOrderPutsJokerInItsRunSlot() throws {
        #expect(RummyRules.displayOrder(fs("A5 A6 J")) == fs("A5 A6 J"))      // J = A7
        #expect(RummyRules.displayOrder(fs("J A5 A6")) == fs("A5 A6 J"))      // 왼쪽에 놓아도 A7(R-07 주의)
        #expect(RummyRules.displayOrder(fs("A12 A13 J")) == fs("J A12 A13"))  // J = A11
        #expect(RummyRules.displayOrder(fs("A5 A7 J")) == fs("A5 J A7"))      // J = A6
        #expect(RummyRules.displayOrder(fs("J D9 B9 A9")) == fs("A9 B9 D9 J")) // 그룹: 색 A→D, 조커 끝
        #expect(RummyRules.displayOrder(fs("A3 B3")) == fs("A3 B3"))          // 무효 조각은 놓은 순서 그대로
        // 코퍼스의 유효 런 전부: 표시 순서는 같은 다중집합이고, 숫자 타일이 s, s+1, … 자리에 정확히 앉는다.
        for c in try rummyCorpus().meld where c.valid && c.kind == "run" {
            let meld = faces(c.tiles)!
            let shown = RummyRules.displayOrder(meld.shuffled())
            #expect(RummyRules.compareKey(shown) == RummyRules.compareKey(meld), "\(c.id)")
            let numbered = shown.enumerated().filter { !$0.element.isJoker }
            let start = numbered[0].element.number! - numbered[0].offset
            #expect(numbered.allSatisfy { $0.element.number! == start + $0.offset }, "\(c.id) \(shown)")
            // 표시 점수 = 자리 숫자 합 = R-08 점수.
            #expect((start..<(start + meld.count)).reduce(0, +) == c.points, "\(c.id) 표시 구간 점수")
        }
    }

    @Test func sameTableIgnoresOrderButCountsDuplicates() {
        let base = [fs("A1 A2 A3"), fs("B7 C7 D7")]
        #expect(RummyRules.sameTable(base, [fs("D7 B7 C7"), fs("A3 A1 A2")]))
        #expect(!RummyRules.sameTable(base, [fs("A1 A2 A3"), fs("B7 C7 D7"), fs("A1 A2 A3")]))
        #expect(!RummyRules.sameTable([fs("A1 A2 A3"), fs("A1 A2 A3")], [fs("A1 A2 A3"), fs("B1 B2 B3")]))
        #expect(!RummyRules.sameTable(base, [fs("A1 A2 A3 B7 C7 D7")]))
    }

    @Test func newMeldPointsCountsOnlyNewMelds() {
        let before = [fs("A1 A2 A3")]
        #expect(RummyRules.newMeldPoints(tableBefore: before, tableAfter: before) == 0)
        #expect(RummyRules.newMeldPoints(tableBefore: before, tableAfter: before + [fs("B5 C5 D5")]) == 15)
        #expect(RummyRules.newMeldPoints(tableBefore: before, tableAfter: before + [fs("B12 J J")]) == 36)
        #expect(RummyRules.newMeldPoints(tableBefore: before, tableAfter: before + [fs("B5 C5")]) == 0)  // 무효 조각 0점
        #expect(RummyRules.newMeldPoints(tableBefore: [], tableAfter: [fs("C10 C11 C12"), fs("A1 A2 A3")]) == 39)
    }

    // MARK: 편집기

    /// `move` 를 부르고 받아들임 여부를 잰다(변경 메서드를 `#expect` 안에서 부르지 않으려고).
    private func move(_ editor: inout RummyTurnEditor, _ tileID: Int, _ target: RummyDropTarget, expect accepted: Bool = true,
                      sourceLocation: SourceLocation = #_sourceLocation) {
        let got = editor.move(tileID, to: target)
        #expect(got == accepted, "move \(tileID) → \(target)", sourceLocation: sourceLocation)
    }

    /// 판 [A1 A2 A3] · 랙 [B10 C10 D10 A4 J].
    private func sampleEditor(initialDone: Bool = true) -> RummyTurnEditor {
        RummyTurnEditor(table: [fs("A1 A2 A3")], rack: fs("B10 C10 D10 A4 J"), initialDone: initialDone)
    }

    private func id(_ editor: RummyTurnEditor, rack face: String) -> Int {
        editor.rack.first { $0.face == f(face) }!.id
    }

    @Test func editorInitNumbersTableFirstAndShowsRunJokerInPlace() {
        let editor = RummyTurnEditor(table: [fs("A5 A7 J")], rack: fs("B1 B2"), initialDone: true)
        #expect(editor.melds.map { $0.map(\.face) } == [fs("A5 J A7")])
        #expect(editor.melds[0].map(\.id).sorted() == [0, 1, 2])
        #expect(editor.rack.map(\.id) == [3, 4])
        #expect(editor.melds[0].allSatisfy { editor.isFromTable($0.id) })
        #expect(!editor.rack.contains { editor.isFromTable($0.id) })
        #expect(!editor.isChanged && editor.playedCount == 0 && editor.reason == .noTilePlayed)
    }

    @Test func editorRejectsTableTileToRack() {
        var editor = sampleEditor()
        let before = editor
        let tableTile = editor.melds[0][0].id
        move(&editor, tableTile, .rack(index: nil), expect: false)
        move(&editor, tableTile, .rack(index: 0), expect: false)
        #expect(editor == before)  // 거절은 아무것도 안 바꾼다
        // 판 → 판은 된다.
        move(&editor, tableTile, .newMeld)
        #expect(editor.melds.count == 2)
        // 이번 차례 낸 내 타일은 랙으로 돌아온다.
        let mine = id(editor, rack: "A4")
        move(&editor, mine, .meld(0, index: nil))
        move(&editor, mine, .rack(index: 0))
        #expect(editor.rack.first?.face == f("A4"))
        // 모르는 id · 없는 세트 번호도 거절.
        move(&editor, 999, .newMeld, expect: false)
        move(&editor, mine, .meld(7, index: nil), expect: false)
    }

    @Test func editorRemovesEmptiedMelds() {
        var editor = sampleEditor()
        let b10 = id(editor, rack: "B10")
        move(&editor, b10, .newMeld)
        #expect(editor.melds.count == 2 && editor.playedCount == 1)
        move(&editor, b10, .rack(index: nil))
        #expect(editor.melds.count == 1 && editor.playedCount == 0)
        // 판 세트를 통째로 다른 세트로 옮기면 빈 원래 세트가 사라진다.
        let tableIDs = editor.melds[0].map(\.id)
        move(&editor, b10, .newMeld)
        for tile in tableIDs { move(&editor, tile, .meld(1, index: nil)) }
        #expect(editor.melds.count == 1)
        #expect(editor.melds[0].count == 4)
        #expect(!editor.melds.contains { $0.isEmpty })
    }

    @Test func editorMovesWithinMeldUsingPreRemovalSlots() {
        var editor = RummyTurnEditor(table: [fs("A1 A2 A3 A4")], rack: [], initialDone: true)
        let first = editor.melds[0][0].id
        move(&editor, first, .meld(0, index: 1))  // 자기 바로 뒤 슬롯 = 제자리
        #expect(editor.melds[0].map(\.face) == fs("A1 A2 A3 A4"))
        move(&editor, first, .meld(0, index: 3))  // A4 앞
        #expect(editor.melds[0].map(\.face) == fs("A2 A3 A1 A4"))
        move(&editor, first, .meld(0, index: nil))  // 끝
        #expect(editor.melds[0].map(\.face) == fs("A2 A3 A4 A1"))
        move(&editor, first, .meld(0, index: 0))  // 맨 앞
        #expect(editor.melds[0].map(\.face) == fs("A1 A2 A3 A4"))
        #expect(!editor.isChanged)
    }

    @Test func editorReorderInsideRack() {
        var editor = sampleEditor()
        let j = id(editor, rack: "J")
        move(&editor, j, .rack(index: 0))
        #expect(editor.rackFaces == fs("J B10 C10 D10 A4"))
        let b10 = id(editor, rack: "B10")
        move(&editor, b10, .rack(index: 4))  // A4 앞
        #expect(editor.rackFaces == fs("J C10 D10 B10 A4"))
        #expect(!editor.isChanged)
    }

    @Test func editorResetRestoresTableAndKeepsRackOrder() {
        var editor = sampleEditor()
        editor.sortRack(.color)  // A4 B10 C10 D10 J
        #expect(editor.rackFaces == fs("A4 B10 C10 D10 J"))
        let c10 = id(editor, rack: "C10"), j = id(editor, rack: "J")
        move(&editor, c10, .newMeld)
        move(&editor, j, .meld(0, index: nil))
        let tableTile = editor.melds[0][0].id
        move(&editor, tableTile, .meld(1, index: 0))
        #expect(editor.isChanged)
        editor.reset()
        #expect(editor.submissionTable == [fs("A1 A2 A3")])
        #expect(editor.rackFaces == fs("A4 B10 C10 D10 J"))  // 정렬한 배치 그대로, 낸 타일은 제자리
        #expect(!editor.isChanged && editor.playedCount == 0)
        // 시작 판 id 도 그대로라 판 타일은 계속 랙으로 못 간다.
        #expect(editor.melds[0].allSatisfy { editor.isFromTable($0.id) })
        #expect(editor == { var fresh = sampleEditor(); fresh.sortRack(.color); return fresh }())
    }

    @Test func editorSortRackByNumberAndByColor() {
        var editor = RummyTurnEditor(table: [], rack: fs("C9 J A7 B8 A9 B7 A7"), initialDone: false)
        editor.sortRack(.number)  // 777: 숫자 → 색, 조커 끝
        #expect(editor.rackFaces == fs("A7 A7 B7 B8 A9 C9 J"))
        editor.sortRack(.color)   // 789: 색 → 숫자, 조커 끝
        #expect(editor.rackFaces == fs("A7 A7 A9 B7 B8 C9 J"))
        // 같은 면 둘은 id 순(안정) — 두 번 정렬해도 id 배치가 흔들리지 않는다.
        let ids = editor.rack.map(\.id)
        editor.sortRack(.number); editor.sortRack(.color)
        #expect(editor.rack.map(\.id) == ids)
    }

    @Test func editorPreservesPreviousRackOrder() {
        // 서버 랙 순서는 아무렇게나 온다. 앞 차례 배치(C3 A1 …)를 면 순서로 맞추고, 새로 받은 D4 는 끝에.
        let editor = RummyTurnEditor(table: [], rack: fs("A1 B2 C3 A1 D4"), initialDone: true,
                                     rackOrder: fs("C3 A1 B5 B2 A1"))
        #expect(editor.rackFaces == fs("C3 A1 B2 A1 D4"))
        let noOrder = RummyTurnEditor(table: [], rack: fs("A1 B2 C3"), initialDone: true)
        #expect(noOrder.rackFaces == fs("A1 B2 C3"))
        let partial = RummyTurnEditor(table: [], rack: fs("A1 B2 C3 D4"), initialDone: true, rackOrder: fs("D4"))
        #expect(partial.rackFaces == fs("D4 A1 B2 C3"))
    }

    @Test func editorIsChangedComparesKMultisets() {
        var editor = RummyTurnEditor(table: [fs("A1 A2 A3 A4 A5 A6")], rack: fs("B9"), initialDone: true)
        let tiles = editor.melds[0].map(\.id)
        // 쪼개면 바뀜.
        for tile in tiles[3...] { move(&editor, tile, tile == tiles[3] ? .newMeld : .meld(1, index: nil)) }
        #expect(editor.melds.count == 2 && editor.isChanged)
        // 다시 합치면(순서는 섞여도) 안 바뀜 — R-19 "쪼갰다 원래대로 돌려놓은 것".
        for tile in tiles[3...].reversed() { move(&editor, tile, .meld(0, index: 0)) }
        #expect(editor.melds.count == 1)
        #expect(editor.submissionTable[0] != fs("A1 A2 A3 A4 A5 A6"))
        #expect(!editor.isChanged)
        // 내 타일을 내면 바뀜, 거두면 다시 안 바뀜.
        let b9 = id(editor, rack: "B9")
        move(&editor, b9, .newMeld)
        #expect(editor.isChanged)
        move(&editor, b9, .rack(index: nil))
        #expect(!editor.isChanged)
    }

    @Test func editorJudgesInitialMeldProgress() {
        var editor = sampleEditor(initialDone: false)
        let b10 = id(editor, rack: "B10"), c10 = id(editor, rack: "C10"), d10 = id(editor, rack: "D10")
        move(&editor, b10, .newMeld)
        #expect(editor.reason == .invalidMeld && !editor.canSubmit)
        #expect(editor.initialPoints == 0)
        move(&editor, c10, .meld(1, index: nil))
        move(&editor, d10, .meld(1, index: nil))
        #expect(editor.initialPoints == 30 && editor.reason == .ok && editor.canSubmit)
        #expect(editor.submissionTable == [fs("A1 A2 A3"), fs("B10 C10 D10")])
        #expect(editor.playedCount == 3)
        #expect(editor.analysis(ofMeld: 1) == RummyMeldAnalysis(valid: true, kind: .group, points: 30))
        #expect(editor.analysis(ofMeld: 9) == .invalid)
        // 첫 등록 차례에 판 세트를 건드리면 판정이 막는다(편집기는 막지 않는다).
        let a4 = id(editor, rack: "A4")
        move(&editor, a4, .meld(0, index: nil))
        #expect(editor.reason == .initialTableTouched)
        // 30 미만.
        var small = RummyTurnEditor(table: [], rack: fs("A5 B5 C5"), initialDone: false)
        for tile in small.rack.map(\.id) {
            let target: RummyDropTarget = small.melds.isEmpty ? .newMeld : .meld(0, index: nil)
            move(&small, tile, target)
        }
        #expect(small.initialPoints == 15 && small.reason == .initialUnder30)
    }
}
