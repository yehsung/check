import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 연습 봇(갈래 B) 시험 — SPEC §4.3 · §6.3 B 줄 · UX §3.6.
// ① E 엔진 자체 대국(봇 넷)에서 뽑은 결정점 1만 개 이상: 결정 ⊂ myDecision · 엔진이 받는다 · 종류별 표본 하한
//    (울기 창 ≥ 1,000 · 리치 중 ≥ 300 · 쿠이카에 직후 ≥ 100 · 남은 패 0(해저·하저) ≥ 50) — 조각마다 몫을 채울 때까지 둔다.
// ② 봇 샹텐 셈 = R `MahjongHand.shanten`(무작위 손) ③ 결정 단위 규칙(손 픽스처, 결과가 갈리는 기준선과 짝)
// ④ 느린 시계 주입 — 마감을 넘기면 2단 보기를 버리고 1단 결과 ⑤ SLOW(`MAHJONG_BOT_SLOW=1`): 봇 넷 동풍전 수백 판 끝까지 ·
//    '효율만 봇' 대비 듀플리케이트 평균 등수 · 실제 시계 결정 시간.
// 기본 게이트의 자체 대국은 결정 열에 하나만 2단 보기를 켠다(나머지는 마감 지난 시계 — 1단 결과). 고르는 범위(myDecision)는
// 2단 보기와 무관하고, 디버그 빌드에서 2단 보기가 한 결정에 수 ms 라 조각 100ms 를 넘기지 않으려는 것이다. SLOW 는 전부 켠다.

/// 자체 대국 몰이꾼 — 엔진 `pendingSeats` 의 첫 자리에 그 자리 시야(`payload(for:)`)만 주고 봇 결정을 걸음으로 넣는다.
enum MahjongBotPlay {
    static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    /// 자리마다 두는 것.
    enum Player: Equatable {
        case bot(MahjongBotPolicy)
        /// 비교·빨리 감기용: 쯔모기리 · 울기는 늘 넘김(화료도 안 한다).
        case tsumogiri
    }

    /// 결정점 종류(표본 하한 단언용) — 봇이 고른 결정만 센다.
    struct Tally: Equatable {
        var decisions = 0
        var claim = 0
        var riichi = 0
        var kuikae = 0
        var lastTile = 0
        var hands = 0
        var illegal: [String] = []
        var slowest: Duration = .zero
        var over200 = 0

        mutating func add(_ o: Tally) {
            decisions += o.decisions
            claim += o.claim
            riichi += o.riichi
            kuikae += o.kuikae
            lastTile += o.lastTile
            hands += o.hands
            illegal += o.illegal
            slowest = max(slowest, o.slowest)
            over200 += o.over200
        }

        func meets(_ q: Tally) -> Bool {
            decisions >= q.decisions && claim >= q.claim && riichi >= q.riichi && kuikae >= q.kuikae && lastTile >= q.lastTile
        }
    }

    static func wall(_ rng: inout GomokuAISplitMix64) -> [Int] {
        var w = Array(0..<136)
        w.shuffle(using: &rng)
        return w
    }

    /// 결정이 그 결정의 선택지 안인가(§4.3 '고를 수 있는 것은 myDecision 안에서만').
    static func isLegal(_ move: MahjongBotMove, _ decision: MahjongDecision?) -> Bool {
        switch (move, decision) {
        case (.none, nil): return true
        case (.act(let a), .turn(let t)?):
            switch a {
            case .discard(let x): return t.discard.contains(x)
            case .riichi(let x): return t.riichi.contains(x)
            case .tsumo: return t.tsumo
            case .ankan(let four): return t.ankan.contains(four.sorted())
            case .kakan(let x): return t.kakan.contains(x)
            case .kyuushu: return t.kyuushu
            }
        case (.call(let w, let a), .call(let c)?):
            guard w == c.windowId else { return false }
            switch a {
            case .pass: return true
            case .ron: return c.ron
            case .pon(let ts): return c.pon.contains(ts.sorted())
            case .minkan(let ts): return c.minkan.contains(ts.sorted())
            case .chi(let ts): return c.chi.contains(ts.sorted())
            }
        default:
            return false
        }
    }

    static func step(for move: MahjongBotMove, seat: Int) -> MahjongEngineStep {
        switch move {
        case .act(let a): .act(seat: seat, a)
        case .call(_, let a): .call(seat: seat, a)
        case .none: .wait
        }
    }

    static func tsumogiri(_ view: MahjongStatePayload) -> MahjongBotMove {
        switch view.myDecision {
        case .turn(let t)?:
            if let d = view.myDrawn, t.discard.contains(d) { return .act(.discard(d)) }
            return t.discard.max().map { .act(.discard($0)) } ?? .none
        case .call(let c)?:
            return .call(windowId: c.windowId, .pass)
        case nil:
            return .none
        }
    }

    /// 한 판을 끝까지(또는 stop 이 참일 때까지) 둔다. 다음 국 패산은 walls(국 번호) 또는 wallRng.
    /// fullEvery: 봇 결정 n 번에 한 번만 실제 마감(나머지는 마감 지난 시계 — 2단 보기 끔). 0 이면 모두 실제 마감.
    /// fastUntilWall: 남은 패가 이보다 많은 동안은 네 자리 모두 쯔모기리(남은 패 0 결정점을 싸게 모으는 빨리 감기).
    @discardableResult
    static func play(
        _ engine: MahjongTableEngine, seed: UInt64, players: [Player] = Array(repeating: .bot(.standard), count: 4),
        walls: ((Int) -> [Int])? = nil, fullEvery: Int = 0, fastUntilWall: Int? = nil, maxSteps: Int = 40_000,
        stop: (Tally) -> Bool = { _ in false }
    ) -> (engine: MahjongTableEngine, tally: Tally) {
        var e = engine
        var wallRng = GomokuAISplitMix64(seed: seed)
        var botRng = GomokuAISplitMix64(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
        var handNo = 0
        func nextWall() -> [Int] { walls?(handNo) ?? wall(&wallRng) }
        if case .idle = e.phase { _ = e.deal(wall: nextWall()) }
        var tally = Tally()
        let clock = ContinuousClock()
        var steps = 0
        while !e.isFinished && steps < maxSteps && !stop(tally) {
            steps += 1
            guard let seat = e.pendingSeats.first else {
                if case .handEnd = e.phase {
                    tally.hands += 1
                    if stop(tally) { break }
                    handNo += 1
                    _ = e.startNextHand(wall: nextWall())
                } else {
                    _ = e.step(.wait)
                }
                continue
            }
            let view = e.payload(for: seat, since: 0, now: epoch)
            let fast = fastUntilWall.map { (view.match?.wallRemaining ?? 0) > $0 } ?? false
            let move: MahjongBotMove
            if case .bot(let policy) = players[seat], !fast {
                let full = fullEvery <= 1 || tally.decisions % fullEvery == 0
                let started = clock.now
                move = MahjongBot.decide(
                    view: view, rng: &botRng, deadline: full ? started + MahjongBot.computeBudget : started,
                    now: { clock.now }, policy: policy
                )
                let took = clock.now - started
                tally.slowest = max(tally.slowest, took)
                if took > MahjongBot.computeBudget { tally.over200 += 1 }
                tally.decisions += 1
                switch view.myDecision {
                case .call?: tally.claim += 1
                case .turn?:
                    if view.mySeatRow?.riichi == true { tally.riichi += 1 }
                    if view.myDrawn == nil { tally.kuikae += 1 }
                case nil: break
                }
                if view.match?.wallRemaining == 0 { tally.lastTile += 1 }
                if !isLegal(move, view.myDecision) {
                    tally.illegal.append("씨앗 \(seed) 걸음 \(steps) 자리 \(seat): \(move)")
                }
            } else {
                move = tsumogiri(view)
            }
            if case .failure(let err) = e.step(step(for: move, seat: seat)) {
                tally.illegal.append("씨앗 \(seed) 걸음 \(steps) 자리 \(seat): 엔진 거절 \(err) \(move)")
                _ = e.step(.timeout(seat: seat))
            }
        }
        if e.isFinished { tally.hands += 1 }
        return (e, tally)
    }

    /// 조각 n 의 판 모양(형식 · 장 · 친 · 본장 · 점수)을 돌려 가며 — 동풍전 첫 국만이 아니라 남장·연장·낮은 점수(토비)까지.
    static func engine(_ n: Int) -> MahjongTableEngine {
        let scores: [[Int]] = [
            [25000, 25000, 25000, 25000], [32000, 18000, 26000, 24000], [8000, 41000, 30000, 21000],
            [12000, 12000, 38000, 38000],
        ]
        return MahjongTableEngine(
            format: n % 3 == 0 ? .hanchan : .tonpuu, seats: [nil, nil, nil, nil], startScores: scores[n % 4],
            round: (n / 4) % 2, handNo: n % 4, honba: n % 3, kyotaku: 0
        )
    }

    /// 판 끝 등수(1~4) — 엔진 payload 의 final_rank.
    static func ranks(_ e: MahjongTableEngine) -> [Int] {
        let seats = e.payload(for: nil, since: 0, now: epoch).seats ?? []
        return (0..<4).map { s in seats.first { $0.seatNo == s }?.finalRank ?? 0 }
    }
}

// MARK: - ① 자체 대국 결정점

/// 조각 셈의 합(조각마다 한 번 — 모든 조각이 모인 순간 합을 돌려준다). 병렬 실행·순서와 무관하고, 일부 조각만 걸러 돌리면 합 단언은 건너뛴다.
final class MahjongBotLedger: @unchecked Sendable {
    static let shared = MahjongBotLedger()
    private let lock = NSLock()
    private var total = MahjongBotPlay.Tally()
    private var seen = Set<String>()

    func add(_ n: String, _ t: MahjongBotPlay.Tally, of count: Int) -> MahjongBotPlay.Tally? {
        lock.lock()
        defer { lock.unlock() }
        guard seen.insert(n).inserted else { return nil }
        total.add(t)
        return seen.count == count ? total : nil
    }
}

@Suite struct MahjongBotSelfPlayTests {
    /// 조각 수 × 조각 몫 ≥ SPEC §6.3 B 줄 하한. 조각 하나가 디버그 빌드에서 100ms 안에 들도록 작게 나눴다.
    static let chunks = 170
    static let quota = MahjongBotPlay.Tally(decisions: 60, claim: 6)
    /// 리치 중(자연 대국의 3% 남짓)·쿠이카에 직후(4% 남짓)는 국마다 들쭉날쭉해 조각 몫으로 걸면 조각 시간이 길어진다 —
    /// 조각마다 걸지 않고 자연 조각 + 리치 조각 전부의 합으로 잰다(11-03 실측 합: 자연 조각만 리치 중 360 · 쿠이카에 375).
    static let riichiFloor = 300
    static let kuikaeFloor = 100
    static let riichiChunks = 30
    /// 리치 조각의 멈춤 조건(단언 아님): 리치 중 4 또는 국 하나 끝.
    static let riichiStop = MahjongBotPlay.Tally(riichi: 4)
    static var ledgerCount: Int { chunks + riichiChunks }
    static let lastTileChunks = 50
    static let lastTileQuota = MahjongBotPlay.Tally(lastTile: 1)
    static let maxHandsPerChunk = 8

    /// 조각 n: 판 모양을 돌려 가며 국을 이어 두어 몫을 채운다(국 상한 8 · 판 상한 4).
    static func chunk(_ n: Int) -> MahjongBotPlay.Tally {
        var total = MahjongBotPlay.Tally()
        var game = 0
        while !total.meets(quota) && total.hands < maxHandsPerChunk && game < 4 {
            let budget = maxHandsPerChunk - total.hands
            let sofar = total
            let r = MahjongBotPlay.play(MahjongBotPlay.engine(n + game), seed: UInt64(n) * 7919 + UInt64(game), fullEvery: 10) { t in
                var x = sofar
                x.add(t)
                return x.meets(quota) || t.hands >= budget
            }
            total.add(r.tally)
            game += 1
        }
        return total
    }

    /// 리치 중 조각 n: 울지 않는 봇 넷(멘젠이라 텐파이하면 리치 → 그 뒤 차례가 모두 리치 중, 남은 셋은 접는다). 리치 중 4 또는 국 하나 끝에서 멈춘다.
    static func riichiChunk(_ n: Int) -> MahjongBotPlay.Tally {
        let menzen = MahjongBotPlay.Player.bot(MahjongBotPolicy(defends: true, calls: false))
        return MahjongBotPlay.play(
            MahjongBotPlay.engine(n), seed: 800_000 + UInt64(n) * 37, players: Array(repeating: menzen, count: 4), fullEvery: 10
        ) { $0.meets(riichiStop) || $0.hands >= 1 }.tally
    }

    /// 조각 합 단언 — 모든 조각(자연 + 리치)이 모인 순간 한 번.
    static func checkLedger(_ key: String, _ total: MahjongBotPlay.Tally) {
        guard let all = MahjongBotLedger.shared.add(key, total, of: ledgerCount) else { return }
        #expect(all.decisions >= 10_000, "합: \(all.decisions)")
        #expect(all.claim >= 1_000, "합: \(all.claim)")
        #expect(all.riichi >= riichiFloor, "합: \(all.riichi)")
        #expect(all.kuikae >= kuikaeFloor, "합: \(all.kuikae)")
    }

    /// 남은 패 0 조각 n: 남은 패 8장까지 네 자리 쯔모기리로 빨리 감고 그 뒤를 봇이 둔다(국 하나씩, 판 상한 6).
    static func lastTileChunk(_ n: Int) -> MahjongBotPlay.Tally {
        var total = MahjongBotPlay.Tally()
        var game = 0
        while !total.meets(lastTileQuota) && game < 6 {
            let r = MahjongBotPlay.play(
                MahjongBotPlay.engine(n + 1), seed: 500_000 + UInt64(n) * 31 + UInt64(game), fastUntilWall: 8
            ) { $0.hands >= 1 }
            total.add(r.tally)
            game += 1
        }
        return total
    }

    // 없으면: 조각 몫을 줄이거나 조각 수를 줄여 표본 하한(1만 · 울기 1,000 · 리치 중 300 · 쿠이카에 100 · 남은 패 0 50)이 조용히 깎인다.
    @Test func quotasCoverSpecFloors() {
        #expect(Self.chunks * Self.quota.decisions >= 10_000)
        #expect(Self.chunks * Self.quota.claim >= 1_000)
        #expect(Self.riichiFloor >= 300)
        #expect(Self.kuikaeFloor >= 100)
        #expect(Self.lastTileChunks * Self.lastTileQuota.lastTile >= 50)
    }

    // 없으면: 봇이 myDecision 밖의 패·동작(쿠이카에 패 · 리치 중 손패 · 없는 울기 조합 · 낡은 창 번호)을 골라도 손 픽스처 몇 개로는
    // 안 보이고, 엔진이 거절해 연습판이 멎는다. 조각마다 울기 창·리치 중·쿠이카에 직후 몫을 채울 때까지 국을 이어 둔다.
    // 조각이 모두 모이면(마지막으로 끝난 조각이) 리치 중 · 쿠이카에 직후(치·퐁 직후 차례 — 뽑은 패 없음 · 막힌 종류 빠짐) 합의 하한을 잰다.
    @Test(arguments: 0..<MahjongBotSelfPlayTests.chunks)
    func decisionsStayInsideMyDecision(_ n: Int) {
        let total = Self.chunk(n)
        #expect(total.illegal.isEmpty, "\(total.illegal.prefix(3))")
        #expect(total.meets(Self.quota), "조각 \(n): \(total)")
        Self.checkLedger("자연 \(n)", total)
    }

    // 없으면: 리치 중 차례(쯔모기리 · 대기 불변 안깡만)에서 봇이 손패를 버리거나 대기가 바뀌는 안깡을 골라도 모른다.
    @Test(arguments: 0..<MahjongBotSelfPlayTests.riichiChunks)
    func riichiDecisionsStayInside(_ n: Int) {
        let total = Self.riichiChunk(n)
        #expect(total.illegal.isEmpty, "\(total.illegal.prefix(3))")
        Self.checkLedger("리치 \(n)", total)
    }

    // 없으면: 해저 차례·하저 창(남은 패 0)에서 봇이 리치·깡·울기처럼 그때 못 하는 것을 골라도 자연 대국에서는 판 100번에 한두 번이라
    // 표본에 안 든다.
    @Test(arguments: 0..<MahjongBotSelfPlayTests.lastTileChunks)
    func lastTileDecisionsStayInside(_ n: Int) {
        let total = Self.lastTileChunk(n)
        #expect(total.illegal.isEmpty, "\(total.illegal.prefix(3))")
        #expect(total.meets(Self.lastTileQuota), "조각 \(n): \(total)")
    }
}

// MARK: - ② 봇 샹텐 셈 = R

@Suite struct MahjongBotShantenTests {
    static func hand(_ rng: inout GomokuAISplitMix64, tiles n: Int) -> [Int] {
        MahjongTiles.counts34(MahjongBotPlay.wall(&rng).prefix(n).map { MahjongTile(id: $0)! })
    }

    // 없으면: 봇 전용 셈(색 표 기억 + 한 종류 증분)이 R 의 샹텐과 어긋나도(치또이·국사 항 · 머리 칸 · 4장 상한) 봇이 텐파이를
    // 잘못 보고 리치·접기를 엉뚱하게 해도 결정 ⊂ myDecision 시험은 초록이다. 무작위 손 + 치또이·국사 꼴을 R 과 잰다.
    @Test(arguments: 0..<6)
    func matchesRulesShanten(_ part: Int) {
        var rng = GomokuAISplitMix64(seed: 4_200 + UInt64(part))
        var calc = MahjongBotShanten()
        var hands: [([Int], Int)] = []
        for i in 0..<14 {
            let melds = i % 3
            hands.append((Self.hand(&rng, tiles: 14 - 3 * melds - (i % 2)), melds))
        }
        for text in ["1122m3344p5566s7z", "19m19p19s1234567z", "1133557799m1p2p", "11112222333m4m"] {
            hands.append((MahjongTiles.counts34(MahjongTiles.parse(text) ?? []), 0))
        }
        for (c0, m) in hands {
            var c = c0
            let b = calc.base(c, melds: m)
            #expect(b.shanten == MahjongHand.shanten(c, melds: m), "\(MahjongTiles.text(kinds: (0..<34).flatMap { Array(repeating: $0, count: c[$0]) }))")
            let delta = c.reduce(0, +) + 3 * m == 14 ? -1 : 1
            let pr = calc.pairs(b)
            for k in 0..<34 where (delta < 0 ? c[k] > 0 : c[k] < 4) && k % 4 == part % 4 {
                var x = c
                x[k] += delta
                let want = MahjongHand.shanten(x, melds: m)
                #expect(calc.shanten(b, &c, kind: k, delta: delta) == want)
                if delta < 0 {
                    // 14장 Base 에서 한 장 뺀 13장 Base(버림 후보) — 처음부터 만든 Base 와 샹텐·유효패가 같다.
                    let derived = calc.removing(b, pr, &c, kind: k)
                    #expect(derived.shanten == want)
                    var y = x
                    let fresh = calc.base(y, melds: m)
                    let u = y.map { 4 - $0 }
                    #expect(calc.ukeire(derived, &y, unseen: u).kinds == calc.ukeire(fresh, &y, unseen: u).kinds)
                }
            }
            #expect(c == c0)
        }
    }

    // 없으면: 유효패가 보이는 장수를 안 빼거나(4장 다 보인 패를 센다) 4장 쥔 종류를 세도 버림 순위가 틀린 채 초록이다.
    @Test func ukeireCountsUnseenTilesOnly() {
        var calc = MahjongBotShanten()
        // 13장 1234m 5678p 99s 東東 + 5z → 한 장 고르기 전 꼴(1샹텐 근처). 순진한 셈: R 샹텐으로 34종을 하나씩.
        let c0 = MahjongTiles.counts34(MahjongTiles.parse("1234m5678p99s11z5z") ?? [])
        var unseen = c0.map { 4 - $0 }
        unseen[MahjongTiles.parse("4m")![0].kind] = 0   // 4m 은 다 보였다
        var c = c0
        let b = calc.base(c, melds: 0)
        let got = calc.ukeire(b, &c, unseen: unseen)
        var naive = 0
        var kinds: [Int] = []
        for k in 0..<34 where c0[k] < 4 && unseen[k] > 0 {
            var x = c0
            x[k] += 1
            if MahjongHand.shanten(x, melds: 0) < MahjongHand.shanten(c0, melds: 0) {
                naive += unseen[k]
                kinds.append(k)
            }
        }
        #expect(got.count == naive)
        #expect(got.kinds == kinds)
        #expect(!got.kinds.contains(MahjongTiles.parse("4m")![0].kind))
        #expect(got.count > 0)
    }
}

// MARK: - ③ 결정 단위(손 픽스처)

/// 손 픽스처 — 토큰 문자열로 패를 받고 같은 종류는 아직 안 쓴 id 를 고른다(적5 `0` 은 c 0, 보통 5 는 c 3·2·1).
struct MahjongBotFixture {
    var used: Set<Int> = []

    mutating func take(_ text: String) -> [MahjongTile] {
        guard let parsed = MahjongTiles.parse(text) else { preconditionFailure("토큰 \(text)") }
        return parsed.map { t in
            let k = t.kind
            let order = t.isRed ? [0] : ([4, 13, 22].contains(k) ? [3, 2, 1] : [3, 2, 1, 0])
            for c in order where !used.contains(k * 4 + c) {
                used.insert(k * 4 + c)
                return MahjongTile(id: k * 4 + c)!
            }
            preconditionFailure("종류 \(k) 를 다 썼다")
        }
    }

    /// 자리 줄(강 · 부로 · 리치).
    mutating func seat(_ no: Int, discards: String = "", melds: [(MahjongMeldType, String)] = [], riichi: Bool = false,
                       dealer: Int = 0) -> MahjongStateSeat {
        var s = MahjongStateSeat(seatNo: no)
        s.wind = ["E", "S", "W", "N"][(no - dealer + 4) % 4]
        s.isDealer = no == dealer
        s.score = 25000
        s.discards = discards.isEmpty ? [] : take(discards).map { MahjongDiscard(tile: $0, tsumogiri: false, riichi: false, taken: false) }
        s.melds = melds.map { type, text in
            let ts = take(text)
            return MahjongWireMeld(type: type.rawValue, tiles: ts, called: type == .ankan ? nil : ts.last, fromSeat: type == .ankan ? nil : (no + 3) % 4)
        }
        s.riichi = riichi
        s.handCount = 13 - 3 * melds.count
        s.away = false
        return s
    }

    /// 시야 하나. me 의 손(13장, myHand)·뽑은 패·결정·다른 자리 줄.
    static func view(hand: [MahjongTile], drawn: MahjongTile?, decision: MahjongDecision?, seats: [MahjongStateSeat],
                     dora: [MahjongTile], wall: Int = 40, me: Int = 0) -> MahjongStatePayload {
        var m = MahjongStateMatch(id: "ai-fixture")
        m.status = "active"
        m.format = "tonpuu"
        m.phase = decision.map { if case .turn = $0 { "turn" } else { "wait" } } ?? "wait"
        m.round = 0
        m.handNo = 0
        m.dealerSeat = 0
        m.honba = 0
        m.kyotaku = 0
        m.wallRemaining = wall
        m.doraIndicators = dora
        var p = MahjongStatePayload(match: m, members: [], seats: seats.sorted { $0.seatNo < $1.seatNo })
        p.mySeat = me
        p.myHand = hand.sorted()
        p.myDrawn = drawn
        p.myDecision = decision
        p.events = []
        return p
    }

    /// 차례 결정 — 버림은 손 + 뽑은 패 전부, 리치 선언패는 R `riichiDiscards` 종류의 id 전부.
    static func turn(hand: [MahjongTile], drawn: MahjongTile, tsumo: Bool = false, riichiOK: Bool = true) -> MahjongDecision {
        let c14 = (hand + [drawn]).sorted()
        let kinds = riichiOK
            ? Set(MahjongRules.riichiDiscards(closed14: c14, ankans: 0, score: 25000, liveLeft: 40, menzen: true, already: false))
            : []
        return .turn(.init(
            seq: 1, decisionSeq: 1, startedMs: 0, deadlineMs: 0, bankMs: 0, discard: c14,
            riichi: c14.filter { kinds.contains($0.kind) }, tsumo: tsumo
        ))
    }

    static func decide(_ view: MahjongStatePayload, seed: UInt64 = 1) -> MahjongBotMove {
        var rng = GomokuAISplitMix64(seed: seed)
        return MahjongBot.decide(view: view, rng: &rng, deadline: .now + .seconds(5))
    }
}

@Suite struct MahjongBotDecisionTests {
    typealias F = MahjongBotFixture

    // 없으면: 리치 상대에게 접는 중이거나 울기 후보가 있을 때 봇이 론·쯔모를 넘겨도 모른다(UX §3.3.7 '화료는 늘').
    // 기준선: 같은 손에서 론·쯔모 선택지가 없으면 넘김·버림이다.
    @Test func alwaysWins() {
        var f = F()
        let hand = f.take("123m456p789s234m5p")
        let riichi = f.seat(2, discards: "1z", riichi: true)
        let dora = f.take("4z")
        let ronTile = f.take("5p")[0]
        var seat1 = f.seat(1, discards: "")
        seat1.discards = [MahjongDiscard(tile: ronTile, tsumogiri: false, riichi: false, taken: false)]
        let seats = [f.seat(0), seat1, riichi, f.seat(3)]
        func callView(ron: Bool) -> MahjongStatePayload {
            F.view(hand: hand, drawn: nil, decision: .call(.init(
                windowId: 7, windowKind: "discard", tile: ronTile, fromSeat: 1, startedMs: 0, deadlineMs: 0, bankMs: 0, ron: ron
            )), seats: seats, dora: dora)
        }
        #expect(F.decide(callView(ron: true)) == .call(windowId: 7, .ron))
        #expect(F.decide(callView(ron: false)) == .call(windowId: 7, .pass))
        var g = F()
        let h2 = g.take("123m456p789s234m5p")
        let drawn = g.take("5p")[0]
        let seats2 = [g.seat(0), g.seat(1), g.seat(2, discards: "1z", riichi: true), g.seat(3)]
        let tsumoView = F.view(hand: h2, drawn: drawn, decision: F.turn(hand: h2, drawn: drawn, tsumo: true), seats: seats2, dora: g.take("4z"))
        #expect(F.decide(tsumoView) == .act(.tsumo))
        let noTsumo = F.view(hand: h2, drawn: drawn, decision: F.turn(hand: h2, drawn: drawn, tsumo: false), seats: seats2, dora: [])
        #expect(F.decide(noTsumo) != .act(.tsumo))
    }

    /// 울기 창 하나(퐁 후보 = 손의 그 종류 두 장).
    static func ponView(_ handText: String, called: String) -> (MahjongStatePayload, [MahjongTile]) {
        var f = F()
        let hand = f.take(handText)
        let tile = f.take(called)[0]
        var s2 = f.seat(2)
        s2.discards = [MahjongDiscard(tile: tile, tsumogiri: false, riichi: false, taken: false)]
        let pair = Array(hand.filter { $0.kind == tile.kind }.prefix(2))
        let v = F.view(hand: hand, drawn: nil, decision: .call(.init(
            windowId: 3, windowKind: "discard", tile: tile, fromSeat: 2, startedMs: 0, deadlineMs: 0, bankMs: 0, pon: [pair]
        )), seats: [f.seat(0), f.seat(1), s2, f.seat(3)], dora: f.take("4z"))
        return (v, pair)
    }

    // 없으면: 역패(백) 또이츠를 퐁하지 않거나, 역 없는 손님풍 퐁을 해도 모른다(UX §3.3.6).
    // 기준선: 같은 손 꼴에서 백 대신 손님풍(남 — 동가·동장)이면 넘긴다(역이 없다).
    @Test func ponsYakuhaiPairButNotGuestWind() {
        let (haku, pair) = Self.ponView("55z13m579p2468s9s", called: "5z")
        #expect(F.decide(haku) == .call(windowId: 3, .pon(pair)))
        let (south, _) = Self.ponView("22z13m579p2468s9s", called: "2z")
        #expect(F.decide(south) == .call(windowId: 3, .pass))
    }

    /// 하가(자리 0)의 치 창 — 상가(자리 3)가 4m 을 버렸다.
    static func chiView(_ handText: String) -> (MahjongStatePayload, [MahjongTile], cur: Int, after: Int) {
        var f = F()
        let hand = f.take(handText)
        let tile = f.take("4m")[0]
        let two = [hand.first { $0.token == "2m" }!, hand.first { $0.token == "3m" }!]
        var s3 = f.seat(3)
        s3.discards = [MahjongDiscard(tile: tile, tsumogiri: false, riichi: false, taken: false)]
        let v = F.view(hand: hand, drawn: nil, decision: .call(.init(
            windowId: 5, windowKind: "discard", tile: tile, fromSeat: 3, startedMs: 0, deadlineMs: 0, bankMs: 0, chi: [two]
        )), seats: [f.seat(0), f.seat(1), f.seat(2), s3], dora: f.take("4z"))
        var c = MahjongTiles.counts34(hand)
        let cur = MahjongHand.shanten(c, melds: 0)
        c[two[0].kind] -= 1
        c[two[1].kind] -= 1
        let after = (0..<34).filter { c[$0] > 0 }.map { k -> Int in
            var x = c
            x[k] -= 1
            return MahjongHand.shanten(x, melds: 1)
        }.min() ?? 9
        return (v, two, cur, after)
    }

    // 없으면: 샹텐만 줄면 역 없이도 치해 버려(울은 손은 역이 없으면 못 난다) 연습 상대가 '날 수 없는 텐파이'로 판을 버린다.
    // 기준선: 같은 모양의 탕야오 손(요구패 0)이면 친다. 두 손 모두 치하면 1샹텐 → 텐파이(전제 단언).
    @Test func callsOnlyWithConfirmedYaku() {
        let (tanyao, two, cur1, after1) = Self.chiView("23m456p678p34s55s7s")
        #expect(cur1 == 1 && after1 == 0)
        #expect(F.decide(tanyao) == .call(windowId: 5, .chi(two)))
        let (noYaku, _, cur2, after2) = Self.chiView("23m456p678p34s11s9s")
        #expect(cur2 == 1 && after2 == 0)
        #expect(F.decide(noYaku) == .call(windowId: 5, .pass))
    }

    // 없으면: 리치 상대가 있는데 2샹텐 이상인 손이 효율대로 위험패를 밀어도 모른다(UX §3.3.3 '접는다').
    // 기준선: 같은 손에 리치가 없으면 현물(5m — 가운데 패)을 남기고 고립 자패를 버린다.
    @Test func foldsToGenbutsuAgainstRiichiWhenFar() {
        func view(riichi: Bool) -> MahjongStatePayload {
            var f = F()
            let hand = f.take("13m5m46p79p24s68s2z")
            let drawn = f.take("3z")[0]
            let s1 = f.seat(1, discards: "5m1z8m", riichi: riichi)
            return F.view(hand: hand, drawn: drawn, decision: F.turn(hand: hand, drawn: drawn),
                          seats: [f.seat(0), s1, f.seat(2), f.seat(3)], dora: f.take("4z"))
        }
        let folded = F.decide(view(riichi: true))
        guard case .act(.discard(let t)) = folded else { Issue.record("\(folded)"); return }
        #expect(t.token == "5m")
        guard case .act(.discard(let u)) = F.decide(view(riichi: false)) else { Issue.record("기준선"); return }
        #expect(u.token != "5m")
    }

    /// 리치 상대(자리 1, 강 4s 7p 2z)에게 접는 손 — 8m 네 장이 다 보여 9m 은 노찬스.
    static func noChanceView(_ handText: String) -> MahjongStatePayload {
        var f = F()
        let hand = f.take(handText)
        let drawn = f.take("8s")[0]
        let s1 = f.seat(1, discards: "4s7p2z", riichi: true)
        let s2 = f.seat(2, melds: [(.pon, "888m")])
        let s3 = f.seat(3, discards: "8m")
        return F.view(hand: hand, drawn: drawn, decision: F.turn(hand: hand, drawn: drawn),
                      seats: [f.seat(0), s1, s2, s3], dora: f.take("1z"))
    }

    // 없으면: 현물이 없을 때 위험도 표(노찬스 1·9 1 < 스지 1·9 3 < … < 무스지)를 안 따르고 아무 패나 버려도 모른다.
    // 기준선: 노찬스 9m 이 없는 손은 스지 1s(4s 현물)를 버린다. 두 손 모두 2샹텐 이상(전제 단언).
    @Test func noGenbutsuPrefersNoChanceThenSuji() {
        let a = Self.noChanceView("2m4m5m7m9m1p2p5p8p9p1s3s6s")
        let b = Self.noChanceView("1m2m4m5m7m1p2p5p8p9p1s3s6s")
        for v in [a, b] {
            let c = MahjongTiles.counts34((v.myHand ?? []) + [v.myDrawn!])
            #expect(MahjongHand.shanten(c, melds: 0) >= 2)
        }
        guard case .act(.discard(let x)) = F.decide(a) else { Issue.record("a"); return }
        #expect(x.token == "9m")
        guard case .act(.discard(let y)) = F.decide(b) else { Issue.record("b"); return }
        #expect(y.token == "1s")
    }

    /// 텐파이 손(남 버리면 2m·5m 양면 대기). seen: 다른 자리 강에 둘 패.
    static func tenpaiView(_ handText: String, drawn: String, seen: String = "") -> MahjongStatePayload {
        var f = F()
        let hand = f.take(handText)
        let d = f.take(drawn)[0]
        let s2 = f.seat(2, discards: seen)
        return F.view(hand: hand, drawn: d, decision: F.turn(hand: hand, drawn: d),
                      seats: [f.seat(0), f.seat(1), s2, f.seat(3)], dora: f.take("4z"))
    }

    // 없으면: 멘젠 텐파이에서 리치하지 않거나(다마로 역 없는 손을 들고 간다), 대기가 모두 보인 가라텐에서 리치해도 모른다(UX §3.3.5).
    // 기준선 둘: 같은 손에 2m·5m 여덟 장이 다 보이면(가라텐) 리치하지 않는다.
    @Test func riichiOnLiveTenpaiNotOnKaraten() {
        let live = Self.tenpaiView("123m456p789s34m55p", drawn: "2z")
        guard case .turn(let t) = live.myDecision else { Issue.record("결정"); return }
        #expect(!t.riichi.isEmpty)
        guard case .act(.riichi(let r)) = F.decide(live) else { Issue.record("\(F.decide(live))"); return }
        #expect(r.token == "2z")
        let dead = Self.tenpaiView("123m456p789s34m55p", drawn: "2z", seen: "222m0555m")
        let move = F.decide(dead)
        if case .act(.riichi) = move { Issue.record("가라텐 리치 \(move)") }
        guard case .act(.discard) = move else { Issue.record("\(move)"); return }
    }

    // 없으면: 리치 없이도 만관 이상인 손(청일색 일기통관 — 다마 배만)에서 리치해 대기를 드러내고 공탁을 내도 모른다(UX §3.3.5).
    // 기준선: 위 시험의 핑후 손(다마 1판)은 리치한다.
    @Test func noRiichiOnManganDama() {
        let v = Self.tenpaiView("123456789m2345m", drawn: "9p")
        guard case .turn(let t) = v.myDecision else { Issue.record("결정"); return }
        #expect(!t.riichi.isEmpty)
        let move = F.decide(v)
        if case .act(.riichi) = move { Issue.record("만관 다마 리치 \(move)") }
        guard case .act(.discard) = move else { Issue.record("\(move)"); return }
    }

    // 없으면: 리치 선언 뒤 누가 버린 패(리치 후 후리텐)·그 자리가 마지막으로 버린 뒤 나온 패(동순)를 현물로 안 쳐서 접을 때 덜 안전한
    // 패를 버려도 모른다(MJ-24). 기준선: 선언 전에 나온 패는 현물이 아니고, 그 자리가 다시 뽑으면 동순 현물이 풀린다.
    @Test func genbutsuIncludesTilesPassedAfterRiichiAndSameTurn() {
        var f = F()
        let before = f.take("3p")[0], declare = f.take("9m")[0], after = f.take("5s")[0], late = f.take("7z")[0]
        let open1 = f.take("1m")[0], passed = f.take("2m")[0]
        var s1 = f.seat(1, riichi: true)
        s1.discards = [MahjongDiscard(tile: declare, tsumogiri: false, riichi: true, taken: false)]
        func ev(_ seq: Int, _ kind: String, _ seat: Int, _ tile: MahjongTile?, riichi: Bool = false) -> MahjongEvent {
            var e = MahjongEvent(seq: seq, kind: kind, seat: seat)
            e.tile = tile
            e.riichi = riichi
            return e
        }
        var s3 = f.seat(3)
        s3.discards = [MahjongDiscard(tile: open1, tsumogiri: false, riichi: false, taken: false)]
        var v = F.view(hand: f.take("123456789s1234p"), drawn: nil, decision: nil, seats: [f.seat(0), s1, f.seat(2), s3], dora: [])
        v.events = [
            ev(1, "deal", 0, nil), ev(2, "discard", 2, before), ev(3, "discard", 1, declare, riichi: true),
            ev(4, "discard", 2, after), ev(5, "discard", 3, open1), ev(6, "discard", 0, passed), ev(7, "discard", 2, late),
        ]
        let riichiSafe = MahjongBotRisk.safeKinds(of: 1, in: v)
        #expect(riichiSafe.isSuperset(of: [declare.kind, after.kind, late.kind, passed.kind, open1.kind]))
        #expect(!riichiSafe.contains(before.kind))
        // 선언이 꼬리보다 옛날: 꼬리의 버림은 모두 선언 뒤다.
        var old = v
        old.events = [ev(10, "discard", 2, after)]
        #expect(MahjongBotRisk.safeKinds(of: 1, in: old).contains(after.kind))
        // 동순(리치 아닌 자리 3): 3 이 버린 뒤 나온 2m · 7z 는 현물, 3 이 다시 뽑으면 풀린다.
        #expect(MahjongBotRisk.safeKinds(of: 3, in: v).isSuperset(of: [passed.kind, late.kind]))
        var drew = v
        drew.events = v.events! + [ev(8, "draw", 3, nil)]
        #expect(!MahjongBotRisk.safeKinds(of: 3, in: drew).contains(passed.kind))
        #expect(!MahjongBotRisk.safeKinds(of: 3, in: v).contains(before.kind))
    }

    // 없으면: 내 몫 결정이 없는(남의 차례 · 답한 창) 시야에서 봇이 무언가를 돌려주면 스토어가 엉뚱한 걸음을 보낸다.
    @Test func noDecisionNoMove() {
        var f = F()
        let hand = f.take("123m456p789s234m5p")
        let v = F.view(hand: hand, drawn: nil, decision: nil, seats: [f.seat(0), f.seat(1), f.seat(2), f.seat(3)], dora: [])
        #expect(F.decide(v) == .none)
    }

    // 없으면: 보여 주는 생각 시간이 0.6~1.2초 · 리치 뒤 쯔모기리 0.4초 · 울기 0 · 최대 1.5초를 벗어나도 모른다(§4.3).
    @Test func thinkSecondsStayInRange() {
        var f = F()
        let hand = f.take("123m456p789s234m5p")
        let d = f.take("1z")[0]
        var me = f.seat(0)
        let v = F.view(hand: hand, drawn: d, decision: F.turn(hand: hand, drawn: d), seats: [me, f.seat(1), f.seat(2), f.seat(3)], dora: [])
        me.riichi = true
        let riichiView = F.view(hand: hand, drawn: d, decision: F.turn(hand: hand, drawn: d, riichiOK: false),
                                seats: [me, f.seat(1), f.seat(2), f.seat(3)], dora: [])
        var rng = GomokuAISplitMix64(seed: 9)
        for _ in 0..<200 {
            let s = MahjongBot.thinkSeconds(for: .act(.discard(d)), view: v, rng: &rng)
            #expect(s >= 0.6 && s <= 1.2)
        }
        #expect(MahjongBot.thinkSeconds(for: .act(.discard(d)), view: riichiView, rng: &rng) == 0.4)
        #expect(MahjongBot.thinkSeconds(for: .call(windowId: 1, .pass), view: v, rng: &rng) == 0)
        #expect(MahjongBot.thinkSeconds(for: .none, view: v, rng: &rng) == 0)
    }
}

// MARK: - ④ 느린 시계

@Suite struct MahjongBotDeadlineTests {
    /// 2단 보기가 결과를 바꾸는 손(1샹텐, 자체 대국에서 찾아 굳힌 것 — 1단은 9s, 2단은 2m 을 버린다).
    static func lookaheadMatters() -> MahjongStatePayload? {
        var f = MahjongBotFixture()
        let hand = f.take("1m2m3m5m6m7p4s0s5s6s6s7s9s")
        let drawn = f.take("2m")[0]
        return MahjongBotFixture.view(
            hand: hand, drawn: drawn, decision: MahjongBotFixture.turn(hand: hand, drawn: drawn),
            seats: [f.seat(0), f.seat(1), f.seat(2), f.seat(3)], dora: f.take("4z")
        )
    }

    // 없으면: 2단 보기가 마감을 안 보면 느린 기기·디버그 빌드에서 봇이 200ms 를 훌쩍 넘겨 연습판이 멈칫한다(§4.3 '마감 넘기면 1단 결과').
    // 느린 시계: 부를 때마다 100ms 씩 흐르는 가짜 시계 — 마감(200ms)은 두 번째 확인에서 지난다. 기준선: 마감이 멀면 2단 결과(1단과 다르다).
    @Test func slowClockFallsBackToOneStep() throws {
        let view = try #require(Self.lookaheadMatters())
        var r1 = GomokuAISplitMix64(seed: 1)
        let oneStep = MahjongBot.decide(view: view, rng: &r1, deadline: .now - .seconds(1))
        var r2 = GomokuAISplitMix64(seed: 1)
        let twoStep = MahjongBot.decide(view: view, rng: &r2, deadline: .now + .seconds(5))
        #expect(oneStep != twoStep)
        let start = ContinuousClock.now
        var ticks = 0
        let slow: () -> ContinuousClock.Instant = {
            ticks += 1
            return start + .milliseconds(100 * ticks)
        }
        var r3 = GomokuAISplitMix64(seed: 1)
        let real = ContinuousClock.now
        let move = MahjongBot.decide(view: view, rng: &r3, deadline: start + MahjongBot.computeBudget, now: slow)
        #expect(ContinuousClock.now - real < MahjongBot.computeBudget)
        #expect(move == oneStep)
        #expect(ticks >= 2 && ticks <= 3)
        #expect(MahjongBotPlay.isLegal(move, view.myDecision))
    }
}

// MARK: - ⑤ SLOW

@Suite struct MahjongBotSlowTests {
    static var slow: Bool { ProcessInfo.processInfo.environment["MAHJONG_BOT_SLOW"] == "1" }
    static var games: Int { Int(ProcessInfo.processInfo.environment["MAHJONG_BOT_GAMES"] ?? "") ?? 300 }
    static var duplicateSeeds: Int { Int(ProcessInfo.processInfo.environment["MAHJONG_BOT_DUP"] ?? "") ?? 60 }

    // 없으면: 봇 넷이 한 판을 끝까지 몰지 못하거나(엔진 거절 · 걸음 상한) 끝 조건(토비·끝 점수·남입·서입·최대 장) 가운데 하나에서
    // 멎어도 기본 게이트의 조각(국 몇 개)으로는 안 보인다. 실제 시계 결정 시간도 여기서 잰다.
    @Test(.enabled(if: MahjongBotSlowTests.slow))
    func botsFinishHundredsOfTonpuuGames() {
        var total = MahjongBotPlay.Tally()
        var finished = 0
        var reasons: [String: Int] = [:]
        var wins = 0, draws = 0, riichiDeclared = 0, calls = 0, dealIns = 0
        let clock = ContinuousClock()
        let started = clock.now
        for g in 0..<Self.games {
            let r = MahjongBotPlay.play(MahjongTableEngine(format: .tonpuu, seats: [nil, nil, nil, nil]), seed: 90_000 + UInt64(g))
            total.add(r.tally)
            if r.engine.isFinished { finished += 1 }
            let p = r.engine.payload(for: nil, since: 0, now: MahjongBotPlay.epoch)
            reasons[p.match?.endReason ?? "?", default: 0] += 1
            for ev in r.engine.log {
                switch ev.kind {
                case "win": wins += 1
                case "hand_draw": draws += 1
                case "discard" where ev.riichi == true: riichiDeclared += 1
                case "call": calls += 1
                default: break
                }
            }
            dealIns += r.engine.hands.map(\.result).flatMap { $0.wins ?? [] }.filter { $0.fromSeat != nil }.count
        }
        let elapsed = clock.now - started
        print("B SLOW 자체 대국: 판 \(Self.games) · 끝 \(finished) · 국 \(total.hands) · 결정 \(total.decisions) · 울기 창 \(total.claim) · 리치 중 \(total.riichi) · 쿠이카에 \(total.kuikae) · 남은 0 \(total.lastTile) · 거절 \(total.illegal.count)")
        print("B SLOW 끝 이유: \(reasons.sorted { $0.key < $1.key })")
        print("B SLOW 국 결과: 화료 사건 \(wins) · 유국 \(draws) · 론 \(dealIns) · 리치 선언 \(riichiDeclared) · 울기 \(calls)")
        print("B SLOW 시간: 전체 \(elapsed) · 결정 최악 \(total.slowest) · 200ms 넘음 \(total.over200)")
        #expect(finished == Self.games)
        #expect(total.illegal.isEmpty, "\(total.illegal.prefix(5))")
    }

    // 없으면: 접기·위험 피하기가 오히려 손해(효율만 봇보다 평균 등수가 나쁨)여도 모른다(UX §3.6 강도 비교).
    // 듀플리케이트: 같은 패산 열(국 번호 → 패산)을 우리 봇 자리만 돌려 네 번 — 패 운을 지운다.
    @Test(.enabled(if: MahjongBotSlowTests.slow))
    func duplicateAverageRankBeatsEfficiencyOnly() {
        var rankSum = 0, count = 0
        var vsTsumogiri = 0, tsumoCount = 0
        for s in 0..<Self.duplicateSeeds {
            var wr = GomokuAISplitMix64(seed: 70_000 + UInt64(s))
            let walls = (0..<40).map { _ in MahjongBotPlay.wall(&wr) }
            for seat in 0..<4 {
                var players = Array(repeating: MahjongBotPlay.Player.bot(.efficiencyOnly), count: 4)
                players[seat] = .bot(.standard)
                let r = MahjongBotPlay.play(
                    MahjongTableEngine(format: .tonpuu, seats: [nil, nil, nil, nil]), seed: UInt64(s),
                    players: players, walls: { walls[$0 % walls.count] }
                )
                let rank = MahjongBotPlay.ranks(r.engine)[seat]
                if rank > 0 {
                    rankSum += rank
                    count += 1
                }
            }
            if s < 10 {
                var players = Array(repeating: MahjongBotPlay.Player.tsumogiri, count: 4)
                players[s % 4] = .bot(.standard)
                let r = MahjongBotPlay.play(
                    MahjongTableEngine(format: .tonpuu, seats: [nil, nil, nil, nil]), seed: UInt64(s), players: players,
                    walls: { walls[$0 % walls.count] }
                )
                let rank = MahjongBotPlay.ranks(r.engine)[s % 4]
                if rank > 0 {
                    vsTsumogiri += rank
                    tsumoCount += 1
                }
            }
        }
        let avg = Double(rankSum) / Double(max(1, count))
        let avgT = Double(vsTsumogiri) / Double(max(1, tsumoCount))
        print("B SLOW 듀플리케이트: 우리 봇(접기) vs 효율만 봇 셋 — 판 \(count) · 평균 등수 \(avg) · 쯔모기리 셋 상대 판 \(tsumoCount) 평균 등수 \(avgT)")
        #expect(count == Self.duplicateSeeds * 4)
        #expect(avg < 2.5)
    }
}
