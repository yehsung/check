import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 판정(후리텐·울기·쿠이카에·리치·리치 뒤 암깡·도라·황패·도중 유국·국 끝·등수)을 판정 코퍼스와 맞춘다 — id 로.
// 코퍼스·별칭·비교는 MahjongCorpus(MahjongScoringCorpusTests.swift). 각 사례의 입력은 reference.py `run_case` 와 같이 읽는다.

@Suite("아잉 마작 판정 코퍼스 — furiten · claim · kuikae · riichi · riichi_ankan · dora · exhaustive · abortive · advance · rank")
struct MahjongRulesCorpusTests {
    typealias V = MahjongCorpus.Value

    private static func run(_ type: String, count: Int, _ body: (MahjongCorpus.Case) -> V?) -> [String] {
        let cases = MahjongCorpus.cases(ofType: type)
        var failures: [String] = cases.count == count ? [] : ["\(type): \(cases.count)건 ≠ \(count)"]
        for c in cases {
            guard let got = body(c) else { failures.append("\(c.id): 입력을 못 읽음"); continue }
            let d = MahjongCorpus.diffs(c.expected, got)
            if !d.isEmpty { failures.append("\(c.id): " + d.joined(separator: " | ")) }
        }
        return failures
    }

    private static func n(_ x: Int) -> V { .number(Double(x)) }

    /// 한 산에서 집듯 배정하고, 장수가 넘쳐 안 되면(울기 뒤 손처럼 서로 다른 때의 패) 문자열마다 따로 배정한다.
    private static func tilesLoose(_ texts: [String]) -> [[MahjongTile]]? {
        if let joint = MahjongCorpus.tiles(texts) { return joint }
        var out: [[MahjongTile]] = []
        for t in texts {
            guard let one = MahjongTiles.parse(t) else { return nil }
            out.append(one)
        }
        return out
    }
    private static func tokens(_ kinds: [Int]) -> V { .array(kinds.map { .string(MahjongTiles.token(kind: $0)) }) }

    // 없으면: 후리텐 셋(버림·동순·리치, MJ-24)의 켜고 꺼짐이 reference 와 갈려 론 단추가 잘못 뜨거나 안 뜬다.
    @Test("furiten 8 — 버림 · 동순(산 쯔모로만 풀림) · 리치 후리텐 · 역 없어 못 론해도 동순")
    func furiten() {
        let failures = Self.run("furiten", count: 8) { c in
            var hand = c.input["closed"]?.string ?? ""
            let melds = c.input["n_melds"]?.int ?? 0
            var f = MahjongFuriten()
            var log: [V] = []
            func waits() -> [Int] { MahjongHand.waits(MahjongCorpus.counts(hand), melds: melds) }
            for event in c.input["events"]?.array ?? [] {
                guard let op = event.array?.first?.string else { return nil }
                let arg = event.array?.dropFirst().first?.string ?? ""
                switch op {
                case "discard": f.ownDiscard(MahjongCorpus.kinds(arg).first ?? -1)
                case "riichi": f.declareRiichi()
                case "draw": f.drawLive()
                case "pass": if waits().contains(MahjongCorpus.kinds(arg).first ?? -1) { f.missed() }
                case "set_hand": hand = arg
                case "call": break   // 치·퐁·대명깡은 동순 후리텐을 풀지 않는다(MJ-24-2)
                case "check":
                    let w = waits()
                    let ok = w.contains(MahjongCorpus.kinds(arg).first ?? -1) && f.canRon(w)
                    log.append(.object(["tile": .string(arg), "can_ron": .bool(ok), "furiten": .array(f.kinds(w).map { .string($0.rawValue) })]))
                default: return nil
                }
            }
            return .object(["checks": .array(log)])
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    private static func claimKind(_ s: String) -> MahjongClaimKind? { s == "kan" ? .minkan : MahjongClaimKind(rawValue: s) }
    private static func claimAnswer(_ s: String) -> MahjongClaimAnswer? { s == "kan" ? .minkan : MahjongClaimAnswer(rawValue: s) }

    // 없으면: 울기 우선순위(론 > 퐁·깡 > 치, MJ-17)·동시 론 순서(MJ-25)·더 높은 답 기다림이 서버와 갈려 창이 엉뚱하게 닫힌다.
    @Test("claim 11 — 론 먼저 · 퐁 > 치 · 높은 답 기다림 · 더블·트리플론 순서 · 모두 넘김")
    func claim() {
        let failures = Self.run("claim", count: 11) { c in
            guard let discarder = c.input["discarder"]?.int else { return nil }
            var eligible: [Int: [MahjongClaimKind]] = [:]
            for (k, v) in c.input["eligible"]?.object ?? [:] {
                guard let seat = Int(k) else { return nil }
                eligible[seat] = (v.array ?? []).compactMap { $0.string.flatMap(Self.claimKind) }
            }
            var answers: [Int: MahjongClaimAnswer] = [:]
            for (k, v) in c.input["answers"]?.object ?? [:] {
                guard let seat = Int(k), let a = v.string.flatMap(Self.claimAnswer) else { return nil }
                answers[seat] = a
            }
            switch MahjongRules.resolveClaims(discarder: discarder, eligible: eligible, answers: answers) {
            case .wait: return .object(["status": .string("wait")])
            case .none: return .object(["status": .string("done"), "action": .string("none"), "seats": .array([])])
            case .ron(let seats): return .object(["status": .string("done"), "action": .string("ron"), "seats": .array(seats.map(Self.n))])
            case .claim(let kind, let seat):
                return .object(["status": .string("done"), "action": .string(kind == .minkan ? "kan" : kind.rawValue), "seats": .array([Self.n(seat)])])
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 쿠이카에 금지(현물 + 치 양끝 스지, MJ-18)나 '버릴 패가 없으면 울기 불가'가 서버와 갈린다. 적5 는 종류로 같다.
    @Test("kuikae 8 — 퐁 현물 · 치 양끝 스지 · 가운데 치 · 울고 버릴 패 없음")
    func kuikae() {
        let failures = Self.run("kuikae", count: 8) { c in
            guard let call = c.input["call"]?.string.flatMap(MahjongMeldType.init(rawValue:)),
                  let calledText = c.input["called"]?.string, let fromText = c.input["from_hand"]?.string else { return nil }
            var texts = [calledText, fromText]
            if let after = c.input["closed_after"]?.string { texts.append(after) }
            guard let g = Self.tilesLoose(texts), let called = g[0].first else { return nil }
            var out: [String: V] = ["forbidden": .string(MahjongTiles.text(kinds: MahjongRules.kuikaeForbidden(call: call, called: called, fromHand: g[1])))]
            if texts.count == 3 {
                out["allowed"] = .bool(MahjongRules.callAllowed(call: call, called: called, fromHand: g[1], closedAfter: g[2]))
            }
            return .object(out)
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 리치 조건(1000점·남은 산 4장·멘젠·이미 리치 아님, MJ-27)과 선언패 목록이 서버와 갈려 리치 단추가 다르게 뜬다.
    @Test("riichi 7 — 선언패 종류 · 1000점 경계 · 남은 산 · 울기")
    func riichi() {
        let failures = Self.run("riichi", count: 7) { c in
            guard let text = c.input["closed14"]?.string, let tiles = MahjongTiles.parse(text),
                  let score = c.input["score"]?.int, let live = c.input["live_left"]?.int else { return nil }
            let kinds = MahjongRules.riichiDiscards(closed14: tiles, ankans: c.input["n_ankan"]?.int ?? 0, score: score, liveLeft: live,
                                                    menzen: c.input["menzen"]?.bool ?? true, already: c.input["already"]?.bool ?? false)
            return .object(["discards": Self.tokens(kinds)])
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 리치 뒤 암깡(오쿠리깡 금지 · 대기 불변, MJ-29·rules C-07)이 서버와 갈린다.
    @Test("riichi_ankan 3 — 대기 그대로면 허용 · 대기가 바뀌면 불가 · 오쿠리깡 불가")
    func riichiAnkan() {
        let failures = Self.run("riichi_ankan", count: 3) { c in
            guard let closedText = c.input["closed13"]?.string, let drawnText = c.input["drawn"]?.string,
                  let g = MahjongCorpus.tiles([closedText, drawnText]), let drawn = g[1].first else { return nil }
            let kan = c.input["kan"]?.string.flatMap { MahjongCorpus.kinds($0).first }
            let ok = MahjongRules.riichiAnkanOK(closed13: g[0], drawn: drawn, kanKind: kan, melds: c.input["n_melds"]?.int ?? 0)
            return .object(["allowed": .bool(ok)])
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 도라 감김(MJ-10)·적5 표시패·같은 표시패 두 번·깡도라 여는 때(MJ-11, rules C-02·C-03)가 서버와 갈린다.
    @Test("dora 8 — 감김 · 적5 표시패는 6 · 같은 표시패 두 번 · 깡도라 시점(암깡 즉시 · 명깡 타패 때 · 연속 깡)")
    func dora() {
        let failures = Self.run("dora", count: 8) { c in
            var out: [String: V] = [:]
            let indicators = MahjongTiles.parse(c.input["indicators"]?.string ?? "") ?? []
            if c.input["indicators"] != nil {
                out["dora_kinds"] = Self.tokens(indicators.map { MahjongTiles.doraKind(ofIndicator: $0.kind) })
            }
            if let text = c.input["tiles"]?.string {
                let tiles = MahjongTiles.parse(text) ?? []
                out["count"] = Self.n(indicators.reduce(0) { sum, ind in
                    sum + tiles.filter { $0.kind == MahjongTiles.doraKind(ofIndicator: ind.kind) }.count
                })
                out["aka"] = Self.n(tiles.filter(\.isRed).count)
            }
            if let events = c.input["events"]?.array {
                var timer = MahjongDoraTimer()
                var seen: [V] = []
                for e in events {
                    switch e.array?.first?.string {
                    case "kan":
                        guard let t = e.array?.dropFirst().first?.string.flatMap(MahjongMeldType.init(rawValue:)) else { return nil }
                        timer.kan(t)
                    case "discard": timer.discard()
                    case "look": seen.append(Self.n(timer.open))
                    default: return nil
                    }
                }
                out["open_counts"] = .array(seen)
            }
            return .object(out)
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 노텐벌 1·2·3명·유국만관(MJ-43·MJ-44)·친 텐파이 연장이 서버와 갈린다.
    @Test("exhaustive 9 — 노텐벌 · 유국만관 · 연장")
    func exhaustive() {
        let failures = Self.run("exhaustive", count: 9) { c in
            guard let dealer = c.input["dealer"]?.int, let tenpai = c.input["tenpai"]?.array?.compactMap(\.bool) else { return nil }
            let nagashi = c.input["nagashi"]?.array?.compactMap(\.bool) ?? [false, false, false, false]
            let r = MahjongRules.settleExhaustive(dealer: dealer, tenpai: tenpai, nagashi: nagashi)
            var out: [String: V] = ["deltas": .array(r.deltas.map(Self.n)), "renchan": .bool(r.renchan)]
            if let discards = c.input["discards"]?.array {
                out["nagashi_ok"] = .array(discards.map { d in
                    .bool(MahjongRules.nagashiOK(discardKinds: MahjongCorpus.kinds(d["discards"]?.string ?? ""),
                                                 calledAway: d["called_away"]?.bool ?? false))
                })
            }
            return .object(out)
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 구종구패·사풍연타·사깡유국(MJ-45, rules C-14·C-15)이 서버와 갈린다. 사가리치는 판 진행이 세는 수 하나라 코퍼스 그대로 잰다.
    @Test("abortive 10 — 구종구패 · 사풍연타 · 사깡유국 · 사가리치")
    func abortive() {
        let failures = Self.run("abortive", count: 10) { c in
            let ok: Bool
            switch c.input["check"]?.string {
            case "kyuushu":
                ok = MahjongRules.kyuushuOK(MahjongTiles.parse(c.input["hand14"]?.string ?? "") ?? [],
                                            firstTurnUninterrupted: c.input["first_turn_uninterrupted"]?.bool ?? true)
            case "suufon":
                ok = MahjongRules.suufonRenda(firstDiscardKinds: MahjongCorpus.kinds(c.input["first_discards"]?.string ?? ""),
                                              anyCall: c.input["any_call"]?.bool ?? false)
            case "suukaikan":
                ok = MahjongRules.suukaikan(kanSeats: c.input["kan_seats"]?.array?.compactMap(\.int) ?? [])
            case "suucha_riichi":
                ok = c.input["riichi_established"]?.int == 4   // reference run_case 와 같은 셈(판 진행 몫)
            default: return nil
            }
            return .object(["ok": .bool(ok)])
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 국 끝 처리(연장·본장·오라스 그만·토비·남입·서든데스·최대 국, MJ-46~MJ-50)가 서버와 갈려 판 길이가 다르다.
    @Test("advance 22 — 연장 · 본장 · 오라스 그만 · 토비 · 연장전 · 최대 국")
    func advance() {
        let failures = Self.run("advance", count: 22) { c in
            let i = c.input
            guard let format = i["length"]?.string.flatMap(MahjongFormat.init(rawValue:)), let round = i["round"]?.int, let hand = i["hand"]?.int,
                  let honba = i["honba"]?.int, let scores = i["scores"]?.array?.compactMap(\.int),
                  let outcome = i["outcome"]?.string.flatMap(MahjongHandOutcome.init(rawValue:)) else { return nil }
            let r = MahjongRules.advance(format: format, round: round, handNo: hand, honba: honba, scores: scores, outcome: outcome)
            var out: [String: V] = ["end": .bool(r.end)]
            if let reason = r.reason { out["reason"] = .string(reason) }
            if let next = r.next { out["next"] = .object(["round": Self.n(next.round), "hand": Self.n(next.hand), "honba": Self.n(next.honba)]) }
            return .object(out)
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 등수 동점(기가에 가까운 쪽 위, DEC:15)·남은 공탁 1위(MJ-51)가 서버와 갈려 루비 분배가 바뀐다.
    @Test("rank 3 — 동점은 기가에 가까운 쪽 · 남은 공탁은 1위")
    func rank() {
        let failures = Self.run("rank", count: 3) { c in
            guard let scores = c.input["scores"]?.array?.compactMap(\.int) else { return nil }
            let r = MahjongRules.finalResult(scores: scores, kyoutaku: c.input["kyoutaku"]?.int ?? 0)
            return .object(["order": .array(r.order.map(Self.n)), "ranks": .array(r.ranks.map(Self.n)),
                            "final_scores": .array(r.finalScores.map(Self.n))])
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 한 갈래의 사례가 통째로 빠져도(예: type 글자 오타) 위 시험들이 '0건 실패'로 초록이다.
    @Test("모든 사례가 어느 한 시험에 든다 — 235 = 갈래별 합")
    func everyCaseCovered() {
        let covered: [String: Int] = ["hand": 93, "score_table": 33, "settle_win": 9, "shape": 11, "furiten": 8, "claim": 11, "kuikae": 8,
                                      "riichi": 7, "riichi_ankan": 3, "dora": 8, "exhaustive": 9, "abortive": 10, "advance": 22, "rank": 3]
        #expect(covered.values.reduce(0, +) == 235)
        for (type, count) in covered { #expect(MahjongCorpus.cases(ofType: type).count == count, "\(type)") }
    }
}
