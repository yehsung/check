// 원본: Sources/CheckCore/RummyRules.swift · Tests/checkTests/Fixtures/rummy/cases.json @ 1a5eeca6 (골든 생성기 — 아잉 큐브 규칙)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// 아잉 큐브 규칙 골든(rummy/rules): 기대값의 집 cases.json 154건을 Swift 로 먼저 대조하고(골든이 틀린 Swift 를 옮겨 적지 않게) 그 값을 싣는다.
// payouts P01~P11(설계서 §2.1 — 손으로 적은 표)·무작위 표 · prizeTable · displayOrder · compareKey · isChainable · sameTable · newMeldPoints · 면 받기·거절.

@Suite("GoldenExport rummy — 규칙(rummy/rules)")
struct GoldenExportRummyRules {
    private struct Corpus: Decodable {
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

    private func parsed(_ texts: [String]) -> [RummyFace]? {
        let faces = texts.compactMap(RummyFace.init(text:))
        return faces.count == texts.count ? faces : nil
    }

    /// "1:run:12" · "0:-:-".
    private func analysisText(_ a: RummyMeldAnalysis) -> GoldenJSON {
        .string("\(a.valid ? 1 : 0):\(a.kind?.rawValue ?? "-"):\(a.points.map(String.init) ?? "-")")
    }

    private func seatText(_ s: RummyPayoutSeat) -> String {
        "\(s.active ? "a" : "x"),\(s.score),\(s.tiles),\(s.seat),\(s.forfeitOrder.map(String.init) ?? "-")"
    }

    private func ints(_ values: [Int]) -> GoldenJSON { .string(GoldenRummyText.ids(values)) }

    @Test("rummy/rules — 코퍼스 154건 · payouts · 표시 순서 · 이어짐 · 면 받기")
    func rules() throws {
        let data = try Data(contentsOf: GoldenRepo.url("Tests/checkTests/Fixtures/rummy/cases.json"))
        let corpus = try JSONDecoder().decode(Corpus.self, from: data)
        #expect(corpus.meld.count == 74 && corpus.turn.count == 64 && corpus.score.count == 16)
        var cases: [GoldenJSON] = []

        // meld 74.
        for c in corpus.meld {
            var row: [String: GoldenJSON] = ["id": .string(c.id), "kind_": "meld", "tiles": .array(c.tiles.map { .string($0) })]
            if let meld = parsed(c.tiles) {
                let got = RummyRules.analyze(meld)
                #expect(got.valid == c.valid && got.kind?.rawValue == c.kind && got.points == c.points, "\(c.id)")
                row["analysis"] = analysisText(got)
                row["compareKey"] = .string(GoldenRummyText.text(RummyRules.compareKey(meld)))
                row["displayOrder"] = .string(GoldenRummyText.text(RummyRules.displayOrder(meld)))
                row["chainable"] = .bool(RummyRules.isChainable(meld))
            } else {
                #expect(!c.valid, "\(c.id) 면 파싱 실패인데 기대가 유효")
                row["analysis"] = .null
            }
            row["valid"] = .bool(c.valid)
            cases.append(.object(row))
        }

        // turn 64 — 형식 검사는 tableAfter 만 본다(R-16 0단계). tableAfter 에 R-01 밖 면이 있으면 RummyFace 가 거절한다 = 서버의 malformed.
        var reasons = Set<String>()
        for c in corpus.turn {
            let got: RummyTurnReason
            let after = c.tableAfter.compactMap(parsed)
            if after.count == c.tableAfter.count {
                let before = c.tableBefore.map { $0.compactMap(RummyFace.init(text:)) }
                let rack = c.rackBefore.compactMap(RummyFace.init(text:))
                got = RummyRules.judgeTurn(initialDone: c.initialDone, tableBefore: before, rackBefore: rack, tableAfter: after)
            } else {
                got = .malformed
            }
            #expect(got.rawValue == c.reason && (got == .ok) == c.valid, "\(c.id) 기대 \(c.reason) 받음 \(got.rawValue)")
            reasons.insert(got.rawValue)
            cases.append([
                "id": .string(c.id), "kind_": "turn", "initialDone": .bool(c.initialDone),
                "tableBefore": .array(c.tableBefore.map { .array($0.map { .string($0) }) }),
                "rackBefore": .array(c.rackBefore.map { .string($0) }),
                "tableAfter": .array(c.tableAfter.map { .array($0.map { .string($0) }) }),
                "reason": .string(got.rawValue),
            ])
        }
        #expect(reasons == Set(RummyTurnReason.allCases.filter { $0 != .unknown }.map(\.rawValue)), "코퍼스가 reason 9개를 다 밟아야 한다")

        // score 16.
        for c in corpus.score {
            let keys = c.racks.keys.sorted { Int($0.dropFirst())! < Int($1.dropFirst())! }
            let racks = keys.map { parsed(c.racks[$0]!)! }
            let got = RummyRules.finalScores(racks: racks)
            #expect(got.scores == keys.map { c.expected[$0]! }, "\(c.id)")
            #expect(got.winners == (c.winners ?? []).map { Int($0.dropFirst())! - 1 }, "\(c.id)")
            cases.append([
                "id": .string(c.id), "kind_": "score", "racks": .string(GoldenRummyText.sets(racks)),
                "scores": ints(got.scores), "winners": ints(got.winners), "payoutScores": ints(RummyRules.payoutScores(racks: racks)),
                "rackValues": ints(racks.map(RummyRules.rackValue)),
            ])
        }

        // payouts — 설계서 §2.1 표(손으로 적은 값으로 먼저 대조).
        func a(_ seat: Int, _ score: Int, _ tiles: Int) -> RummyPayoutSeat { RummyPayoutSeat(active: true, score: score, tiles: tiles, seat: seat) }
        func x(_ seat: Int, _ order: Int) -> RummyPayoutSeat { RummyPayoutSeat(active: false, score: 0, tiles: 0, seat: seat, forfeitOrder: order) }
        let table: [(String, Int, Int, [RummyPayoutSeat], [Int], [Int])] = [
            ("P01", 2, 5, [a(0, 20, 0), a(1, -20, 3)], [10, 0], [1, 2]),
            ("P02", 4, 5, [a(0, 30, 0), a(1, -5, 2), a(2, -10, 3), a(3, -15, 4)], [15, 5, 0, 0], [1, 2, 3, 4]),
            ("P03", 4, 3, [a(0, 22, 0), a(1, -5, 2), a(2, -5, 3), a(3, -12, 4)], [9, 2, 1, 0], [1, 2, 2, 4]),
            ("P04", 4, 10, [a(0, 11, 3), a(1, 11, 1), a(2, -12, 5), a(3, -10, 4)], [20, 20, 0, 0], [1, 1, 4, 3]),
            ("P05", 3, 5, [a(0, 7, 0), a(1, -7, 2), x(2, 1)], [10, 5, 0], [1, 2, 3]),
            ("P06", 4, 5, [a(0, 0, 6), x(1, 1), x(2, 2), x(3, 3)], [20, 0, 0, 0], [1, 4, 3, 2]),
            ("P07", 4, 3, [a(0, -10, 3), a(1, 25, 0), a(2, -15, 4), x(3, 1)], [3, 9, 0, 0], [2, 1, 3, 4]),
            ("P08", 3, 10, [a(0, 0, 2), a(1, 0, 1), a(2, 0, 1)], [10, 10, 10], [1, 1, 1]),
            ("P09", 4, 5, [a(0, -3, 1), a(1, 9, 0), a(2, -3, 2), a(3, -3, 1)], [2, 15, 1, 2], [2, 1, 2, 2]),
            ("P10", 2, 3, [a(0, 0, 5), x(1, 1)], [6, 0], [1, 2]),
        ]
        for (id, n, stake, seats, payouts, ranks) in table {
            let got = RummyRules.payouts(seatCount: n, stake: stake, seats: seats)
            #expect(got.payouts == payouts && got.ranks == ranks, "\(id)")
            cases.append(payoutCase(id, n, stake, seats, got))
        }
        // 무작위 표 + 분배 불가 경계(인원 2~4 밖 · active 없음).
        var r = GoldenRummyRNG(seed: 0x1234_5678)
        for i in 0..<100 {
            let n = r.range(2, 4)
            let stake = r.pick([1, 3, 5, 10])
            var order = r.shuffled(Array(1...n))
            var seats: [RummyPayoutSeat] = []
            let forfeits = r.below(n)
            for seat in 0..<n {
                if seat >= n - forfeits {
                    seats.append(x(seat, order.removeLast()))
                } else {
                    seats.append(a(seat, r.range(-4, 4) * 3, r.below(4)))
                }
            }
            cases.append(payoutCase("pay-\(i)", n, stake, seats, RummyRules.payouts(seatCount: n, stake: stake, seats: seats)))
        }
        let edges: [(String, Int, Int, [RummyPayoutSeat])] = [
            ("pay-edge-seat1", 1, 5, [a(0, 3, 1)]), ("pay-edge-seat5", 5, 5, [a(0, 3, 1), a(1, 1, 1)]),
            ("pay-edge-allforfeit", 3, 5, [x(0, 1), x(1, 2), x(2, 3)]), ("pay-edge-noorder", 2, 5, [a(0, 1, 0), RummyPayoutSeat(active: false, score: 0, tiles: 0, seat: 1)]),
            ("pay-edge-empty", 2, 5, []), ("pay-edge-many", 2, 5, [a(0, 3, 1), a(1, 2, 1), a(2, 1, 1), a(3, 0, 1)]),
        ]
        for (id, n, stake, seats) in edges {
            cases.append(payoutCase(id, n, stake, seats, RummyRules.payouts(seatCount: n, stake: stake, seats: seats)))
        }
        // P11(V1-01): 막힘 끝 최소 집단 — 화면 점수 · 정산 점수.
        let scoreRacks = ["A2|B2|C5|D6", "A1 B1|C2|D7", "A2||B3", "A2 B2", ""]
        for (i, text) in scoreRacks.enumerated() {
            let racks = text.isEmpty ? [] : text.split(separator: "|", omittingEmptySubsequences: false).map { GoldenRummyText.faces(String($0)) }
            let got = RummyRules.finalScores(racks: racks)
            cases.append([
                "id": .string("P11-\(i)"), "kind_": "score", "racks": .string(GoldenRummyText.sets(racks)),
                "scores": ints(got.scores), "winners": ints(got.winners), "payoutScores": ints(RummyRules.payoutScores(racks: racks)),
                "rackValues": ints(racks.map(RummyRules.rackValue)),
            ])
        }

        for seats in 0...5 { cases.append(["id": .string("prize-\(seats)"), "kind_": "prize", "seatCount": .int(seats), "prizes": ints(RummyRules.prizeTable(seatCount: seats))]) }

        // 무작위 묶음 표(맞는 후보 · 아무 면 섞음).
        for i in 0..<100 {
            var meld = r.flip() ? r.meld() : (0..<r.range(0, 6)).map { _ in r.face() }
            if r.below(3) == 0, !meld.isEmpty { meld = r.shuffled(meld) }
            cases.append([
                "id": .string("meld-r\(i)"), "kind_": "meld", "faces": .string(GoldenRummyText.text(meld)), "analysis": analysisText(RummyRules.analyze(meld)),
                "compareKey": .string(GoldenRummyText.text(RummyRules.compareKey(meld))),
                "displayOrder": .string(GoldenRummyText.text(RummyRules.displayOrder(meld))),
                "chainable": .bool(RummyRules.isChainable(meld)),
            ])
        }

        // 면 받기·거절(R-01) — RummyFace(text:) 와 비교 순서.
        for (i, text) in ["A1", "A13", "D9", "J", "A0", "A14", "E1", "a1", "J1", "", "A", "A01", "A-1", " A1", "A1 ", "A１", "B10", "C7"].enumerated() {
            let face = RummyFace(text: text)
            cases.append(["id": .string("face-\(i)"), "kind_": "face", "text": .string(text), "accepted": .bool(face != nil), "rackValue": face.map { .int($0.rackValue) } ?? .null])
        }

        // sameTable · newMeldPoints(표 그대로).
        let tables: [(String, String, String)] = [
            ("same-order", "A1 A2 A3|B7 C7 D7", "D7 B7 C7|A3 A1 A2"),
            ("same-dup", "A1 A2 A3|B7 C7 D7", "A1 A2 A3|B7 C7 D7|A1 A2 A3"),
            ("same-count", "A1 A2 A3|A1 A2 A3", "A1 A2 A3|B1 B2 B3"),
            ("same-merge", "A1 A2 A3|B7 C7 D7", "A1 A2 A3 B7 C7 D7"),
            ("new-none", "A1 A2 A3", "A1 A2 A3"), ("new-group", "A1 A2 A3", "A1 A2 A3|B5 C5 D5"),
            ("new-joker", "A1 A2 A3", "A1 A2 A3|B12 J J"), ("new-invalid", "A1 A2 A3", "A1 A2 A3|B5 C5"),
            ("new-two", "", "C10 C11 C12|A1 A2 A3"),
        ]
        for (id, a, b) in tables {
            let before = a.isEmpty ? [] : a.split(separator: "|").map { GoldenRummyText.faces(String($0)) }
            let after = b.split(separator: "|").map { GoldenRummyText.faces(String($0)) }
            cases.append([
                "id": .string(id), "kind_": "tables", "before": .string(a), "after": .string(b), "same": .bool(RummyRules.sameTable(before, after)),
                "newPoints": .int(RummyRules.newMeldPoints(tableBefore: before, tableAfter: after)),
            ])
        }

        goldenEmit(GoldenFile(
            golden: "rummy/rules",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/RummyRules.swift", "Sources/CheckCore/RummyRackLayout.swift", "Tests/checkTests/Fixtures/rummy/cases.json"],
            spec: [
                "corpus": "Tests/checkTests/Fixtures/rummy/cases.json 154건(meld 74 · turn 64 · score 16)을 Swift 로 대조한 뒤 싣는다. R-01 밖 면이 든 meld 는 analysis null(만들 수 없다 = 무효). tableAfter 에 R-01 밖 면이 있으면 판정은 malformed, 랙·이전 판의 이상한 면은 입력에서 뺀다.",
                "kind_": "칸 kind_ 가 이 case 의 종류다 — meld · turn · score · payouts · prize · face · tables.",
                "payouts": "seats 는 공백 구분, 한 칸 = 'a|x,score,tiles,seat,forfeitOrder|-'. P01~P10 은 설계서 §2.1 손 표와 대조했다.",
                "text": "analysis 'valid(0/1):kind|-:points|-' · 정수 목록 '1,2' · 묶음 목록 'A1 A2|B1'(racks 의 빈 칸은 빈 랙, 글자 전체가 비면 자리 없음) · 무작위 묶음은 tiles 대신 faces 글자.",
            ],
            cases: cases
        ))
    }

    private func payoutCase(_ id: String, _ n: Int, _ stake: Int, _ seats: [RummyPayoutSeat], _ got: (payouts: [Int], ranks: [Int])) -> GoldenJSON {
        ["id": .string(id), "kind_": "payouts", "seatCount": .int(n), "stake": .int(stake), "seats": .string(seats.map(seatText).joined(separator: " ")), "payouts": ints(got.payouts), "ranks": ints(got.ranks)]
    }
}
