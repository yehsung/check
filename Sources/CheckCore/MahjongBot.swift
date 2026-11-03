import Foundation

// 아잉 마작 연습 봇 — 혼자 연습판(혼자 + 봇 셋)의 봇 결정(SPEC §4.3 · UX §3.3~3.4). 난이도 하나.
// 직접 작성, 외부 엔진·가중치 없음 — 근거는 공개 논문·일반 전략 서술(UX §3.1: 결정점 나누기 · 위협 = 텐파이 여부 × 패별 위험 × 손 값 ·
// 공격과 접기를 가른다 · 샹텐 = 결손수)과 rules.md MJ-nn 뿐이다. GPL·AGPL 봇의 코드·가중치·문서는 보지 않았다.
//
// 계약(§4.3):
//  · 입력은 **그 자리 시야**(`payload(for: 봇 자리)` — 서버 state 와 같은 모양)뿐이다. 남의 손·패산은 형에 없다.
//  · 고르는 것은 `view.myDecision` 안에서만이다(엔진이 합법만 준다 — 역 없는 론·후리텐 론은 오지 않는다). 결정이 없으면 `.none`.
//  · 계산 상한 200ms: 1샹텐 2단 보기는 마감(`deadline`)을 넘기면 멈추고 1단 결과를 쓴다. 시계는 주입할 수 있다(시험 — 느린 시계).
//  · 같은 점수(유효패 차 ≤ 1 · 가치 같음 · 위험 같음)끼리만 주입 RNG 로 고른다. **일부러 틀리는 수는 없다.**
//  · 스토어(C3)는 이 함수를 `Task.detached` 에서 부른다(CC-09) — 순수 함수라 메인 액터에 묶인 것이 없다.
//
// 정책(UX §3.3): 화료는 늘 · 리치 중이면 쯔모기리(대기 불변 안깡만) · 구종구패(요구패 10종 이상이면 국사를 노림) ·
// 안깡(샹텐 불변) · 가깡(위협 없고 샹텐 불변) · 대명깡 안 함 · 위협 표에 따라 밀기/접기 · 멘젠 텐파이면 리치(가라텐·만관 다마·
// 후리텐 저장수 제외) · 샹텐 → 유효패(1샹텐만 2단) → 가치 순 버림 · 역 확보형 울기만(역패·쿠이탄·혼일색) · 역패 또이츠 퐁.
// 위협·위험도는 `MahjongBotRisk`(같은 갈래 파일). 유효패 장수는 `MahjongVisibleTiles.counts` 로만 센다(CC-08).

/// 봇이 고른 것. 차례면 `.act`, 울기 창이면 `.call`(창 번호를 함께 — 늦은 결과를 스토어가 버리는 데 쓴다), 내 몫 결정이 없으면 `.none`.
package nonisolated enum MahjongBotMove: Equatable, Hashable, Sendable {
    case act(MahjongTurnAction)
    case call(windowId: Int, MahjongCallAnswer)
    case none
}

/// 봇 정책 스위치 — 앱은 늘 `.standard`. `.efficiencyOnly` 는 접기·위험 피하기를 끈 비교 상대(SLOW 듀플리케이트, UX §3.6),
/// `calls: false` 는 울지 않는 멘젠 봇(시험이 '리치 중' 결정점을 모을 때).
package nonisolated struct MahjongBotPolicy: Equatable, Sendable {
    /// 위협을 보고 접거나 위험한 패를 피하는가.
    package var defends: Bool
    /// 퐁·치를 하는가(론은 늘 한다).
    package var calls: Bool

    package init(defends: Bool, calls: Bool = true) {
        self.defends = defends
        self.calls = calls
    }

    package static let standard = MahjongBotPolicy(defends: true)
    package static let efficiencyOnly = MahjongBotPolicy(defends: false)
}

package nonisolated enum MahjongBot {
    /// 계산 상한(§4.3). 스토어는 `ContinuousClock.now + computeBudget` 을 마감으로 넘긴다.
    package static let computeBudget: Duration = .milliseconds(200)
    /// 보여 주는 생각 시간(초) — 버림 0.6~1.2 균등 · 리치 뒤 쯔모기리 0.4 · 최대 1.5(UX §3.4).
    package static let thinkRange: ClosedRange<Double> = 0.6...1.2
    package static let riichiTsumogiriThink = 0.4
    package static let maxThink = 1.5
    /// 밀기·접기 문턱(UX §3.3.3 표 — 설계 상수).
    package static let pushValue = 7_700
    package static let weakTenpaiValue = 2_000
    package static let weakTenpaiWaits = 3
    package static let pushUkeire = 16
    /// 1샹텐으로 밀 때 버릴 수 있는 패의 위험 상한('스지' 급 — 온전한 스지 4~6 = 8).
    package static let pushDangerCap = MahjongBotRisk.sujiMiddle
    /// 구종구패를 선언하지 않고 국사를 노리는 요구패 종류 수.
    package static let kokushiAim = 10

    // MARK: - 계약 표면

    /// 그 자리 시야에서 한 수를 고른다(§4.3). 시계는 실제 `ContinuousClock`.
    package static func decide(
        view: MahjongStatePayload, rng: inout some RandomNumberGenerator, deadline: ContinuousClock.Instant
    ) -> MahjongBotMove {
        decide(view: view, rng: &rng, deadline: deadline, now: { ContinuousClock.now }, policy: .standard)
    }

    /// 시계·정책 주입판(시험 — 느린 시계 · 비교 상대).
    package static func decide(
        view: MahjongStatePayload, rng: inout some RandomNumberGenerator, deadline: ContinuousClock.Instant,
        now: () -> ContinuousClock.Instant, policy: MahjongBotPolicy = .standard
    ) -> MahjongBotMove {
        guard let decision = view.myDecision, let me = view.mySeat else { return .none }
        // 시계는 이 호출 안에서만 산다(결정 값이 들고 있다가 호출이 끝나면 버린다).
        return withoutActuallyEscaping(now) { clock in
            var mind = MahjongBotMind(view: view, me: me, policy: policy, deadline: deadline, now: clock)
            switch decision {
            case .turn(let turn):
                return .act(mind.turn(turn, rng: &rng))
            case .call(let call):
                return .call(windowId: call.windowId, mind.call(call, rng: &rng))
            }
        }
    }

    /// 보여 주는 생각 시간(§4.3 — 버림 0.6~1.2초 · 리치 뒤 쯔모기리 0.4초 · 울기 답은 0(창 멈춤 0.5~1.0초에 묻는다) · 최대 1.5초).
    package static func thinkSeconds(for move: MahjongBotMove, view: MahjongStatePayload, rng: inout some RandomNumberGenerator) -> Double {
        switch move {
        case .none, .call:
            return 0
        case .act(let action):
            if view.mySeatRow?.riichi == true, case .discard = action { return riichiTsumogiriThink }
            return min(maxThink, Double.random(in: thinkRange, using: &rng))
        }
    }
}

// MARK: - 한 결정의 계산(값 — 한 호출 안에서만 산다)

/// 버림 후보 하나의 평가.
struct MahjongBotDiscard {
    let tile: MahjongTile
    var kind: Int { tile.kind }
    /// 버린 뒤 샹텐.
    let shanten: Int
    /// 유효패 남은 장수(텐파이면 대기 남은 장수). 가장 낮은 샹텐 무리만 잰다(나머지는 0).
    var ukeire = 0
    /// 유효패 종류(텐파이면 대기 종류).
    var kinds: [Int] = []
    /// 순위 점수(유효패 + 1샹텐 2단 보기 · 텐파이면 후리텐·역 없음 감점).
    var score: Double
    /// 낮을수록 먼저 버린다(동률 깨기 — UX §3.3.2 4).
    let keep: Int
    /// 위협 가중 합 · 가장 큰 날 값.
    let danger: Double
    let worst: Double
    /// 텐파이 버림의 손 값(론, 리치 가정은 `valueRiichi`).
    var value: Int = 0
    var valueRiichi: Int = 0
    /// 텐파이 버림이 역 없이(리치 없이) 모든 대기로 날 수 있고 만관 이상인가.
    var damaMangan = false
    var furiten = false
    var hasYakuDama = false

    /// 순위용 샹텐 — 날 수 없는 텐파이(가라텐 · 울은 손 역 없음)는 1샹텐으로 친다.
    var rankShanten: Int { shanten == 0 && score <= 0 ? 1 : shanten }
}

/// 짧은 수명의 결정 상태(시야에서 한 번 뽑아 둔 값 + 샹텐 기억).
struct MahjongBotMind {
    let view: MahjongStatePayload
    let me: Int
    let policy: MahjongBotPolicy
    let deadline: ContinuousClock.Instant
    let now: () -> ContinuousClock.Instant

    /// 손 안 패(차례면 뽑은 패 포함).
    let hand: [MahjongTile]
    let drawn: MahjongTile?
    let counts: [Int]
    let melds: [MahjongMeld]
    let visible: [Int]
    let unseen: [Int]
    let doraIndicators: [MahjongTile]
    let doraKinds: Set<Int>
    let seatWind: MahjongWind
    let roundWind: MahjongWind
    let seatWindKind: Int
    let roundWindKind: Int
    let isDealer: Bool
    let wallLeft: Int
    let ownDiscardKinds: Set<Int>
    let menzen: Bool
    let inRiichi: Bool
    let threats: [MahjongBotThreat]
    /// 샹텐 셈(색 표 기억) · 2단 보기의 텐파이 대기 장수 기억.
    var calc = MahjongBotShanten()
    var waitMemo: [MahjongBotKey: Int] = [:]
    /// 2단 보기를 마감 때문에 멈췄는가.
    var lookaheadCut = false
    /// 2단 보기를 하는 1샹텐 버림 수(유효패 많은 순).
    static let lookaheadWidth = 4

    init(view: MahjongStatePayload, me: Int, policy: MahjongBotPolicy, deadline: ContinuousClock.Instant,
         now: @escaping () -> ContinuousClock.Instant) {
        self.view = view
        self.me = me
        self.policy = policy
        self.deadline = deadline
        self.now = now
        let row = view.mySeatRow
        drawn = view.myDrawn
        hand = ((view.myHand ?? []) + (view.myDrawn.map { [$0] } ?? [])).sorted()
        counts = MahjongTiles.counts34(hand)
        melds = (row?.melds ?? []).compactMap(\.meld)
        visible = MahjongVisibleTiles.counts(of: view)
        unseen = visible.map { max(0, 4 - $0) }
        doraIndicators = view.match?.doraIndicators ?? []
        doraKinds = Set(doraIndicators.map { MahjongTiles.doraKind(ofIndicator: $0.kind) })
        let dealerSeat = view.match?.dealerSeat ?? view.match?.handNo ?? 0
        seatWind = row?.wind.flatMap(MahjongWind.init(rawValue:)) ?? MahjongWind.allCases[(me - dealerSeat + 4) % 4]
        roundWind = MahjongWind.allCases[(view.match?.round ?? 0) % 4]
        seatWindKind = 27 + (MahjongWind.allCases.firstIndex(of: seatWind) ?? 0)
        roundWindKind = 27 + (MahjongWind.allCases.firstIndex(of: roundWind) ?? 0)
        isDealer = row?.isDealer ?? (me == dealerSeat)
        wallLeft = view.match?.wallRemaining ?? 70
        ownDiscardKinds = Set((row?.discards ?? []).map(\.tile.kind))
        menzen = melds.allSatisfy { $0.type == .ankan }
        inRiichi = row?.riichi == true
        threats = policy.defends ? MahjongBotRisk.threats(in: view) : []
    }

    // MARK: 샹텐

    mutating func shanten(_ c: [Int], melds m: Int) -> Int { calc.base(c, melds: m).shanten }

    var pastDeadline: Bool { now() >= deadline }

    // MARK: - 차례

    mutating func turn<R: RandomNumberGenerator>(_ t: MahjongDecision.Turn, rng: inout R) -> MahjongTurnAction {
        // 화료는 늘(UX §3.3.7).
        if t.tsumo { return .tsumo }
        let fallback = t.discard.first.map(MahjongTurnAction.discard) ?? .tsumo
        // 리치 중: 엔진이 대기 불변일 때만 안깡을 준다 — 그것만 하고 나머지는 쯔모기리.
        if inRiichi {
            if let four = t.ankan.first { return .ankan(four) }
            if let d = drawn, t.discard.contains(d) { return .discard(d) }
            return fallback
        }
        // 구종구패: 요구패 종류가 10 이상이면 국사를 노린다.
        if t.kyuushu {
            let yaochuKinds = MahjongTiles.yaochu.filter { counts[$0] > 0 }.count
            if yaochuKinds < MahjongBot.kokushiAim { return .kyuushu }
        }
        let cands = evaluateDiscards(t.discard)
        guard !cands.isEmpty else { return fallback }
        let bestShanten = cands.map(\.rankShanten).min() ?? 8

        // 안깡: 4장을 빼도 샹텐이 그대로(위협 중에도 — 방총 위험이 없다).
        for four in t.ankan {
            guard let k = four.first?.kind else { continue }
            var c = counts
            c[k] -= 4
            if c[k] >= 0, shanten(c, melds: melds.count + 1) <= bestShanten { return .ankan(four) }
        }
        // 가깡: 위협이 없고 샹텐이 그대로.
        if threats.isEmpty {
            for tile in t.kakan {
                var c = counts
                c[tile.kind] -= 1
                if c[tile.kind] >= 0, shanten(c, melds: melds.count) <= bestShanten { return .kakan(tile) }
            }
        }

        let riichiKinds = Set(t.riichi.map(\.kind))
        switch stance(cands, bestShanten: bestShanten) {
        case .fold:
            return .discard(pickSafest(cands, rng: &rng).tile)
        case .weakTenpai(let safe):
            if riichiKinds.contains(safe.kind), let r = riichiTile(t.riichi, kind: safe.kind), riichiAllowed(safe) {
                return .riichi(r)
            }
            return .discard(safe.tile)
        case .attack(let capWorst):
            var pool = cands
            if let capWorst {
                let capped = cands.filter { $0.rankShanten == bestShanten && $0.worst <= capWorst }
                if !capped.isEmpty { pool = capped }
            }
            let choice = pickAttack(pool, rng: &rng)
            // 멘젠 텐파이면 리치(가라텐·만관 다마·후리텐 저장수 제외).
            if choice.shanten == 0, riichiKinds.contains(choice.kind), riichiAllowed(choice),
               let r = riichiTile(t.riichi, kind: choice.kind) {
                return .riichi(r)
            }
            return .discard(choice.tile)
        }
    }

    /// 리치할 수 있는 텐파이 버림인가(UX §3.3.5): 대기 남은 장수 0(가라텐) · 만관 다마 · 후리텐이고 남은 장수 4 미만이면 안 한다.
    func riichiAllowed(_ d: MahjongBotDiscard) -> Bool {
        guard d.shanten == 0, d.ukeire > 0 else { return false }
        if d.damaMangan { return false }
        if d.furiten && d.ukeire < 4 { return false }
        return true
    }

    /// 리치 선언패 id — 그 종류 가운데 뽑은 패 · 적5 가 아닌 패 순.
    func riichiTile(_ options: [MahjongTile], kind: Int) -> MahjongTile? {
        Self.representative(options.filter { $0.kind == kind }, drawn: drawn)
    }

    /// 같은 종류 여러 id 가운데 버릴 한 장: 뽑은 패(쯔모기리) → 적5 아닌 패 → 아무거나.
    static func representative(_ ids: [MahjongTile], drawn: MahjongTile?) -> MahjongTile? {
        if let d = drawn, ids.contains(d), !d.isRed { return d }
        return ids.filter { !$0.isRed }.max() ?? ids.max()
    }

    // MARK: 버림 평가

    mutating func evaluateDiscards(_ options: [MahjongTile]) -> [MahjongBotDiscard] {
        let m = melds.count
        var byKind: [Int: [MahjongTile]] = [:]
        for t in options { byKind[t.kind, default: []].append(t) }
        var c = counts
        let b14 = calc.base(c, melds: m)
        var out: [MahjongBotDiscard] = []
        for kind in byKind.keys.sorted() where c[kind] > 0 {
            guard let tile = Self.representative(byKind[kind] ?? [], drawn: drawn) else { continue }
            let sh = calc.shanten(b14, &c, kind: kind, delta: -1)
            let risk = MahjongBotRisk.weighted(tile: tile, threats: threats, visible: visible, doraKinds: doraKinds)
            out.append(MahjongBotDiscard(
                tile: tile, shanten: sh, score: 0, keep: keepValue(tile), danger: risk.sum, worst: risk.worst
            ))
        }
        // 유효패는 가장 낮은 샹텐 무리만 잰다. 그 무리가 모두 날 수 없는 텐파이(가라텐·역 없음)면 1샹텐 무리도.
        let low = out.map(\.shanten).min() ?? 8
        let pr = calc.pairs(b14)
        fillUkeire(&out, tier: low, b14: b14, pairs: pr)
        if low == 0 && !out.contains(where: { $0.shanten == 0 && $0.score > 0 }) {
            fillUkeire(&out, tier: 1, b14: b14, pairs: pr)
        }
        lookahead(&out)
        return out
    }

    mutating func fillUkeire(_ out: inout [MahjongBotDiscard], tier: Int, b14: MahjongBotShanten.Base, pairs pr: MahjongBotShanten.Pairs) {
        var c = counts
        for i in out.indices where out[i].shanten == tier {
            let b = calc.removing(b14, pr, &c, kind: out[i].kind)
            c[out[i].kind] -= 1
            let (uke, kinds) = calc.ukeire(b, &c, unseen: unseen)
            out[i].ukeire = uke
            out[i].kinds = kinds
            out[i].score = Double(uke)
            if tier == 0 { scoreTenpai(&out[i], base: b) }
            c[out[i].kind] += 1
        }
    }

    /// 텐파이 버림: 후리텐(버린 패 포함 내 강에 대기 종류)이면 감점 · 울은 손은 역 있는 대기만 센다 · 손 값.
    /// 손 계산은 대기마다 한 번(멘젠은 리치를 가정해 부르고 리치 1판을 빼서 다마 값을 얻는다 — 역 판정은 리치 말고 남은 역으로).
    mutating func scoreTenpai(_ d: inout MahjongBotDiscard, base b: MahjongBotShanten.Base) {
        let closed = removing(d.tile, from: hand)
        let rivers = ownDiscardKinds.union([d.kind])
        var c = counts
        c[d.kind] -= 1
        // 후리텐은 남은 장수 0 인 대기까지 모두로 잰다(MJ-24 — 대기 하나라도 내 강에 있으면 론 못 한다).
        d.furiten = (0..<34).contains { w in
            rivers.contains(w) && c[w] < 4 && calc.shanten(b, &c, kind: w, delta: 1) < 0
        }
        var dama: [(value: Int, limit: String)] = []
        var withRiichi: [Int] = []
        var winnable = 0
        for w in d.kinds {
            guard let win = syntheticTile(kind: w, used: closed),
                  let s = evaluate(closed: closed, win: win, riichi: menzen), s.agari else { continue }
            let full = s.total - s.honbaBonus - s.kyoutakuBonus
            if !menzen {
                dama.append((full, s.limit))
                winnable += unseen[w]
                continue
            }
            withRiichi.append(full)
            if s.yakuman > 0 {
                dama.append((full, s.limit))
            } else if let r = s.yaku.first(where: { $0.yaku == .riichi }), s.yaku.count > 1 {
                let sc = MahjongScoring.scoreOf(han: s.han - r.han, fu: s.fu, dealer: isDealer, tsumo: false)
                dama.append((sc.total, sc.limit))
            }
        }
        d.hasYakuDama = !dama.isEmpty && dama.count == d.kinds.count
        d.damaMangan = d.hasYakuDama && dama.allSatisfy { !$0.limit.isEmpty }
        d.value = dama.isEmpty ? 0 : dama.map(\.value).reduce(0, +) / dama.count
        d.valueRiichi = withRiichi.isEmpty ? d.value : withRiichi.reduce(0, +) / withRiichi.count
        if !menzen { d.score = Double(winnable) }
        if d.furiten { d.score *= 0.3 }
    }

    /// 1샹텐에서만 2단 보기(유효패 많은 넷까지) — 유효패가 들어와 텐파이가 될 때 가장 좋은 대기 남은 장수를 그 유효패 장수로 가중해
    /// 더한다(좋은 대기 선호). 마감을 넘기면 멈추고 1단 결과로 되돌린다(더한 것을 모두 버린다).
    mutating func lookahead(_ cands: inout [MahjongBotDiscard]) {
        let m = melds.count
        let ones = cands.indices.filter { cands[$0].shanten == 1 && cands[$0].ukeire > 0 }
            .sorted { (cands[$0].ukeire, cands[$1].kind) > (cands[$1].ukeire, cands[$0].kind) }
            .prefix(Self.lookaheadWidth)
        var extra: [(Int, Double)] = []
        for i in ones {
            var c = counts
            c[cands[i].kind] -= 1
            var sum = 0.0
            for k in cands[i].kinds {
                if pastDeadline {
                    lookaheadCut = true
                    return
                }
                c[k] += 1
                let b14 = calc.base(c, melds: m)
                var best = 0
                for e in 0..<34 where c[e] > 0 && calc.shanten(b14, &c, kind: e, delta: -1) == 0 {
                    c[e] -= 1
                    best = max(best, waitCount(c, melds: m))
                    c[e] += 1
                }
                c[k] -= 1
                sum += Double(unseen[k] * best)
            }
            extra.append((i, sum / 10))
        }
        for (i, x) in extra { cands[i].score += x }
    }

    /// 텐파이 13장 꼴의 대기 남은 장수(기억). 남은 장수는 지금 시야 기준(들어온 유효패 한 장은 빼지 않는다 — 기억을 나누려고).
    mutating func waitCount(_ c: [Int], melds m: Int) -> Int {
        let key = MahjongBotKey(c, melds: m)
        if let v = waitMemo[key] { return v }
        var cc = c
        let b = calc.base(cc, melds: m)
        let v = calc.ukeire(b, &cc, unseen: unseen).count
        waitMemo[key] = v
        return v
    }

    /// 동률 깨기 가치(낮을수록 먼저 버린다): 손님풍 단독 0 · 역패 단독 1 · 노두패 2 · 2·8 3 · 3~7 4 · 자패 둘 이상 6 · 도라 +5 · 적5 +5.
    func keepValue(_ tile: MahjongTile) -> Int {
        let k = tile.kind
        var v: Int
        if k >= 27 {
            let yakuhai = MahjongBotRisk.isYakuhai(k, seatWind: seatWindKind, roundWind: roundWindKind)
            v = counts[k] >= 2 ? 6 : (yakuhai ? 1 : 0)
        } else {
            let n = k % 9 + 1
            v = (n == 1 || n == 9) ? 2 : (n == 2 || n == 8) ? 3 : 4
        }
        if doraKinds.contains(k) { v += 5 }
        if tile.isRed { v += 5 }
        return v
    }

    // MARK: 밀기·접기

    enum Stance {
        /// 공격 — capWorst 가 있으면 그 위험 아래 패만(1샹텐 밀기 · 반 위협 피하기).
        case attack(capWorst: Double?)
        /// 약한 텐파이 + 리치 1명: 텐파이를 지키는 현물.
        case weakTenpai(MahjongBotDiscard)
        case fold
    }

    /// UX §3.3.3 표.
    func stance(_ cands: [MahjongBotDiscard], bestShanten: Int) -> Stance {
        guard policy.defends, !threats.isEmpty else { return .attack(capWorst: nil) }
        let riichiCount = threats.filter(\.riichi).count
        let tenpai = cands.filter { $0.rankShanten == 0 }
        let bestTenpai = tenpai.max { ($0.ukeire, $0.valueRiichi) < ($1.ukeire, $1.valueRiichi) }
        let value = bestTenpai.map { menzen ? $0.valueRiichi : $0.value } ?? estimateValue()
        let bestUke = cands.filter { $0.rankShanten == bestShanten }.map(\.ukeire).max() ?? 0
        if riichiCount >= 2 {
            return bestShanten == 0 && value >= MahjongBot.pushValue ? .attack(capWorst: nil) : .fold
        }
        if riichiCount == 1 {
            switch bestShanten {
            case 0:
                if let b = bestTenpai, b.ukeire <= MahjongBot.weakTenpaiWaits, value < MahjongBot.weakTenpaiValue {
                    if let safe = tenpai.filter({ $0.danger == 0 }).max(by: { $0.ukeire < $1.ukeire }) { return .weakTenpai(safe) }
                    return .fold
                }
                return .attack(capWorst: nil)
            case 1:
                guard value >= MahjongBot.pushValue, bestUke >= MahjongBot.pushUkeire,
                      cands.contains(where: { $0.rankShanten == 1 && $0.worst <= MahjongBot.pushDangerCap }) else { return .fold }
                return .attack(capWorst: MahjongBot.pushDangerCap)
            default:
                return .fold
            }
        }
        // 반 위협만.
        if bestShanten == 0 { return .attack(capWorst: nil) }
        return .attack(capWorst: MahjongBotRisk.highDanger - 0.5)
    }

    /// 텐파이 전 손 값 어림: 확정 역 + 도라(적5 포함) + 멘젠이면 리치 1판, 30부 론(UX §3.3.3). 울은 손에 확정 역이 없으면 0.
    func estimateValue() -> Int {
        var han = 0
        let all = hand + melds.flatMap(\.tiles)
        han += all.filter { doraKinds.contains($0.kind) }.count
        han += all.filter(\.isRed).count
        var yaku = 0
        for k in 27..<34 where MahjongBotRisk.isYakuhai(k, seatWind: seatWindKind, roundWind: roundWindKind) {
            let inMeld = melds.contains { $0.type != .chi && $0.tiles[0].kind == k }
            if inMeld || counts[k] >= 3 {
                yaku += (k == seatWindKind && k == roundWindKind) ? 2 : 1
            }
        }
        han += yaku
        if menzen { han += 1 } else if yaku == 0 { return 0 }
        return MahjongScoring.scoreOf(han: max(1, han), fu: 30, dealer: isDealer, tsumo: false).total
    }

    // MARK: 고르기

    /// 공격: 순위 샹텐 → 점수(유효패) → 같은 점수(차 ≤ 1)끼리 가치 낮은 것 → 그 가운데 무작위.
    func pickAttack<R: RandomNumberGenerator>(_ cands: [MahjongBotDiscard], rng: inout R) -> MahjongBotDiscard {
        let sh = cands.map(\.rankShanten).min() ?? 0
        let tier = cands.filter { $0.rankShanten == sh }
        let top = tier.map(\.score).max() ?? 0
        var near = tier.filter { $0.score >= top - 1 }
        if sh == 0 {
            // 텐파이끼리: 대기가 같으면 손 값이 큰 쪽.
            let bestValue = near.map { menzen ? $0.valueRiichi : $0.value }.max() ?? 0
            near = near.filter { (menzen ? $0.valueRiichi : $0.value) >= bestValue }
        }
        let low = near.map(\.keep).min() ?? 0
        let pool = near.filter { $0.keep == low }.sorted { $0.tile < $1.tile }
        return pool[pool.count == 1 ? 0 : Int.random(in: 0..<pool.count, using: &rng)]
    }

    /// 접기: 위협 가중 위험 → 순위 샹텐 → 점수 → 가치 → 무작위.
    func pickSafest<R: RandomNumberGenerator>(_ cands: [MahjongBotDiscard], rng: inout R) -> MahjongBotDiscard {
        let low = cands.map(\.danger).min() ?? 0
        let safest = cands.filter { $0.danger <= low + 1e-9 }
        return pickAttack(safest, rng: &rng)
    }

    // MARK: - 울기 창

    mutating func call<R: RandomNumberGenerator>(_ c: MahjongDecision.Call, rng: inout R) -> MahjongCallAnswer {
        // 화료는 늘.
        if c.ron { return .ron }
        if inRiichi || !policy.calls || (c.pon.isEmpty && c.chi.isEmpty) { return .pass }
        let m = melds.count
        let cur = shanten(counts, melds: m)
        let calledKind = c.tile.kind
        // (c) 멘젠 텐파이(리치할 수 있음) · 리치 상대 + 2샹텐 이상이면 울지 않는다.
        if menzen && cur == 0 { return .pass }
        if threats.contains(where: \.riichi) && cur >= 2 { return .pass }
        // 역패 또이츠 퐁 — 위협이 없으면 늘.
        if threats.isEmpty, MahjongBotRisk.isYakuhai(calledKind, seatWind: seatWindKind, roundWind: roundWindKind),
           let pair = c.pon.min(by: { Self.redCount($0) < Self.redCount($1) }) {
            return .pon(pair)
        }
        var best: [CallOption] = []
        func consider(_ type: MahjongMeldType, _ fromHand: [MahjongTile]) {
            var after = counts
            for t in fromHand { after[t.kind] -= 1 }
            guard after.allSatisfy({ $0 >= 0 }) else { return }
            let newMeld = MahjongMeld(type: type, tiles: (fromHand + [c.tile]).sorted(), called: c.tile, fromSeat: c.fromSeat)
            guard confirmedYaku(after: after, melds: melds + [newMeld], calledKind: calledKind) else { return }
            let banned = Set(MahjongRules.kuikaeForbidden(call: type, called: c.tile, fromHand: fromHand))
            let b = calc.base(after, melds: m + 1)
            var bestSh = 9
            var bestDiscards: [Int] = []
            for d in 0..<34 where after[d] > 0 && !banned.contains(d) {
                let sh = calc.shanten(b, &after, kind: d, delta: -1)
                if sh < bestSh {
                    bestSh = sh
                    bestDiscards = [d]
                } else if sh == bestSh {
                    bestDiscards.append(d)
                }
            }
            guard bestSh < cur else { return }   // (b) 울어서 샹텐이 준다
            var bestUke = 0
            for d in bestDiscards {
                after[d] -= 1
                let b2 = calc.base(after, melds: m + 1)
                bestUke = max(bestUke, calc.ukeire(b2, &after, unseen: unseen).count)
                after[d] += 1
            }
            let option = CallOption(
                answer: type == .pon ? .pon(fromHand) : .chi(fromHand), shanten: bestSh, ukeire: bestUke,
                red: Self.redCount(fromHand)
            )
            best.append(option)
        }
        for pair in c.pon { consider(.pon, pair) }
        for pair in c.chi { consider(.chi, pair) }
        guard !best.isEmpty else { return .pass }
        let sh = best.map(\.shanten).min() ?? 0
        let tier = best.filter { $0.shanten == sh }
        let top = tier.map(\.ukeire).max() ?? 0
        let near = tier.filter { $0.ukeire >= top - 1 }
        let fewRed = near.map(\.red).min() ?? 0
        let pool = near.filter { $0.red == fewRed }
        return pool[pool.count == 1 ? 0 : Int.random(in: 0..<pool.count, using: &rng)].answer
    }

    /// 울기 후보 하나(울고 난 뒤 가장 좋은 버림의 샹텐·유효패).
    struct CallOption {
        let answer: MahjongCallAnswer
        let shanten: Int
        let ukeire: Int
        let red: Int
    }

    static func redCount(_ tiles: [MahjongTile]) -> Int { tiles.filter(\.isRed).count }

    /// 울고 난 손에 확정 역이 있는가(UX §3.3.6 (a)): 역패 커쯔 · 쿠이탄(요구패 1장 이하) · 혼일색(한 색 + 자패 11장 이상).
    func confirmedYaku(after: [Int], melds all: [MahjongMeld], calledKind: Int) -> Bool {
        func yakuhai(_ k: Int) -> Bool { MahjongBotRisk.isYakuhai(k, seatWind: seatWindKind, roundWind: roundWindKind) }
        // 역패
        if all.contains(where: { $0.type != .chi && yakuhai($0.tiles[0].kind) }) { return true }
        if (27..<34).contains(where: { yakuhai($0) && after[$0] >= 3 }) { return true }
        // 쿠이탄
        let yaochu = Set(MahjongTiles.yaochu)
        let meldKinds = all.flatMap { $0.tiles.map(\.kind) }
        if !meldKinds.contains(where: { yaochu.contains($0) }) {
            let left = yaochu.reduce(0) { $0 + after[$1] }
            if left <= 1 { return true }
        }
        // 혼일색
        for s in 0..<3 {
            func inColor(_ k: Int) -> Bool { k >= 27 || k / 9 == s }
            guard inColor(calledKind), meldKinds.allSatisfy(inColor) else { continue }
            let handIn = (0..<34).filter(inColor).reduce(0) { $0 + after[$1] }
            let meldIn = all.count * 3
            if handIn + meldIn >= 11 { return true }
        }
        return false
    }

    // MARK: - 손 계산 도우미

    func removing(_ tile: MahjongTile, from tiles: [MahjongTile]) -> [MahjongTile] {
        var out = tiles
        if let i = out.firstIndex(of: tile) { out.remove(at: i) }
        return out
    }

    /// 대기 종류 w 의 가상 화료패 — 내 손·부로에 없는 id(적5 를 피해 c 3·2·1·0 순).
    func syntheticTile(kind w: Int, used closed: [MahjongTile]) -> MahjongTile? {
        let taken = Set((closed + melds.flatMap(\.tiles)).map(\.id))
        for c in [3, 2, 1, 0] where !taken.contains(w * 4 + c) { return MahjongTile(id: w * 4 + c) }
        return nil
    }

    func evaluate(closed: [MahjongTile], win: MahjongTile, riichi: Bool) -> MahjongScore? {
        let ctx = MahjongWinContext(
            closed: closed, melds: melds, win: win, tsumo: false, seatWind: seatWind, roundWind: roundWind,
            riichi: riichi, doraIndicators: doraIndicators
        )
        if case .success(let s) = MahjongScoring.evaluate(ctx) { return s }
        return nil
    }
}

/// 34칸 장수(각 0~4) + 손 밖 몸통 수를 두 낱말로 접은 샹텐 기억 열쇠.
struct MahjongBotKey: Hashable {
    let a: UInt64
    let b: UInt64

    init(_ c: [Int], melds: Int) {
        var a: UInt64 = 0, b = UInt64(melds & 7)
        for i in 0..<20 { a = a << 3 | UInt64(c[i] & 7) }
        for i in 20..<34 { b = b << 3 | UInt64(c[i] & 7) }
        self.a = a
        self.b = b
    }
}

/// 봇 전용 샹텐 셈. 값은 `MahjongHand.shanten` 과 같다 — R 의 색 비용 표(`ShantenTable.suitCost`·`honorCost`)를 그대로 쓰고
/// 합치는 길만 다르다(시험 MahjongBotShantenTests 가 무작위 손으로 R 과 잰다). 한 결정 안에서 색 표를 기억하고, 한 종류만 바뀐 손은
/// 나머지 셋의 합을 미리 둔 `Base` 에 그 색 표 하나만 맞춰 잰다(유효패 34칸 · 버림 14칸). 표 10칸(몸통 m × 2 + 머리 p)은 칸마다
/// 6비트로 `UInt64` 하나에 접는다(63 = 없음) — R 의 공용 셈은 부를 때마다 배열 표 열 개를 새로 합쳐 디버그 빌드에서 한 번에
/// 0.1ms 남짓 들고, 봇은 한 결정에 수백 번 부른다(기본 게이트의 자체 대국 1만 결정이 디버그 빌드에서 돈다).
struct MahjongBotShanten {
    var suits: [Int: UInt64] = [:]
    var honors: [Int: UInt64] = [:]

    static let none = 63
    static let allNone: UInt64 = (0..<10).reduce(0) { $0 | (UInt64(none) << UInt64(6 * $1)) }
    /// 색 안 자리 i(0~8) → 5^(8−i) · 자패 j(0~6) → 5^(6−j). 색 표 기억 열쇠 = 장수의 5진수.
    static let pow5: [Int] = [390_625, 78_125, 15_625, 3_125, 625, 125, 25, 5, 1]
    static let pow5h: [Int] = [15_625, 3_125, 625, 125, 25, 5, 1]
    static let isYaochu: [Bool] = (0..<34).map { MahjongTiles.yaochu.contains($0) }

    /// 한 손의 부분 합. t* = 색·자패 표 · rest* = 그것을 뺀 나머지 셋의 합 · code* = 표 열쇠.
    struct Base {
        let melds: Int
        let target: Int
        let t0, t1, t2, th: UInt64
        let code0, code1, code2, codeH: Int
        let rest0, rest1, rest2, restH: UInt64
        let pairs: Int
        let kinds: Int
        let yaochuKinds: Int
        let yaochuPairs: Int
        let shanten: Int
        /// 치또이·국사 꼴이 샹텐을 정하는가 — 그때만 손에서 먼 패도 유효패일 수 있다.
        let wide: Bool
        let valid: Bool

        static let invalid = Base(
            melds: 0, target: 1, t0: 0, t1: 0, t2: 0, th: 0, code0: 0, code1: 0, code2: 0, codeH: 0, rest0: 0, rest1: 0,
            rest2: 0, restH: 0, pairs: 0, kinds: 0, yaochuKinds: 0, yaochuPairs: 0, shanten: 8, wide: false, valid: false
        )
    }

    /// 14장 꼴의 두 부분씩 합(버림 후보마다 13장 Base 를 세 번의 합으로 얻으려고).
    struct Pairs {
        let k01, k02, k12, k0h, k1h, k2h: UInt64
    }

    static func pack(_ t: [Int]) -> UInt64 {
        var out: UInt64 = 0
        for i in 0..<10 { out |= UInt64(min(t[i], none)) << UInt64(6 * i) }
        return out
    }

    /// 접은 표 두 개의 배낭 합(R `ShantenTable.knap` 과 같은 뜻). 칸 번호 i1 + i2 = (m1 + m2) × 2 + p1 + p2(머리는 둘이 함께 1 이하).
    static func knap(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var out = allNone
        var i1 = 0
        while i1 < 10 {
            let x = Int((a >> UInt64(6 * i1)) & 63)
            if x < none {
                var i2 = 0
                while i1 + i2 < 10 {
                    if i1 & i2 & 1 == 0 {
                        let y = Int((b >> UInt64(6 * i2)) & 63)
                        if y < none {
                            let shift = UInt64(6 * (i1 + i2))
                            if x + y < Int((out >> shift) & 63) {
                                out = (out & ~(UInt64(63) << shift)) | (UInt64(x + y) << shift)
                            }
                        }
                    }
                    i2 += 1
                }
            }
            i1 += 1
        }
        return out
    }

    /// knap(a, b)[target] 한 칸만(target = 몸통 M × 2 + 머리 1 — 홀수라 머리는 늘 한쪽에만).
    static func pick(_ a: UInt64, _ b: UInt64, target: Int) -> Int {
        var best = 2 * none
        var i1 = 0
        while i1 <= target {
            let x = Int((a >> UInt64(6 * i1)) & 63)
            let y = Int((b >> UInt64(6 * (target - i1))) & 63)
            if x < none && y < none && x + y < best { best = x + y }
            i1 += 1
        }
        return best
    }

    /// 색 s 의 표(열쇠 code 는 c 의 그 색 장수와 맞아야 한다).
    mutating func suitTable(_ c: [Int], _ s: Int, code: Int) -> UInt64 {
        if let t = suits[code] { return t }
        let t = Self.pack(ShantenTable.suitCost(c, from: s * 9))
        suits[code] = t
        return t
    }

    mutating func honorTable(_ c: [Int], code: Int) -> UInt64 {
        if let t = honors[code] { return t }
        var acc = ShantenTable.identity
        for k in 27..<34 { acc = ShantenTable.knap(acc, ShantenTable.honorCost(c[k])) }
        let t = Self.pack(acc)
        honors[code] = t
        return t
    }

    static func code(_ c: [Int], suit s: Int) -> Int {
        var code = 0
        var i = s * 9
        while i < s * 9 + 9 {
            code = code * 5 + min(max(c[i], 0), 4)
            i += 1
        }
        return code
    }

    static func honorCode(_ c: [Int]) -> Int {
        var code = 0
        var k = 27
        while k < 34 {
            code = code * 5 + min(max(c[k], 0), 4)
            k += 1
        }
        return code
    }

    static func forms(_ c: [Int]) -> (pairs: Int, kinds: Int, yk: Int, yp: Int) {
        var pairs = 0, kinds = 0, yk = 0, yp = 0
        var k = 0
        while k < 34 {
            let n = c[k]
            if n >= 2 { pairs += 1 }
            if n >= 1 { kinds += 1 }
            if isYaochu[k] {
                if n >= 1 { yk += 1 }
                if n >= 2 { yp += 1 }
            }
            k += 1
        }
        return (pairs, kinds, yk, yp)
    }

    static func other(pairs: Int, kinds: Int, yk: Int, yp: Int) -> Int {
        min(6 - pairs + max(0, 7 - kinds), 13 - yk - (yp > 0 ? 1 : 0))
    }

    mutating func base(_ c: [Int], melds m: Int) -> Base {
        guard c.count == 34, (0...4).contains(m) else { return .invalid }
        let c0 = Self.code(c, suit: 0), c1 = Self.code(c, suit: 1), c2 = Self.code(c, suit: 2), ch = Self.honorCode(c)
        let t0 = suitTable(c, 0, code: c0), t1 = suitTable(c, 1, code: c1), t2 = suitTable(c, 2, code: c2)
        let h = honorTable(c, code: ch)
        let k01 = Self.knap(t0, t1)
        let restH = Self.knap(k01, t2)
        let target = (4 - m) * 2 + 1
        let f = Self.forms(c)
        var sh = Self.pick(restH, h, target: target) - 1
        var wide = false
        if m == 0 {
            let o = Self.other(pairs: f.pairs, kinds: f.kinds, yk: f.yk, yp: f.yp)
            wide = o <= sh
            sh = min(sh, o)
        }
        return Base(
            melds: m, target: target, t0: t0, t1: t1, t2: t2, th: h, code0: c0, code1: c1, code2: c2, codeH: ch,
            rest0: Self.knap(Self.knap(t1, t2), h), rest1: Self.knap(Self.knap(t0, t2), h), rest2: Self.knap(k01, h),
            restH: restH, pairs: f.pairs, kinds: f.kinds, yaochuKinds: f.yk, yaochuPairs: f.yp, shanten: sh, wide: wide,
            valid: true
        )
    }

    func pairs(_ b: Base) -> Pairs {
        Pairs(
            k01: Self.knap(b.t0, b.t1), k02: Self.knap(b.t0, b.t2), k12: Self.knap(b.t1, b.t2),
            k0h: Self.knap(b.t0, b.th), k1h: Self.knap(b.t1, b.th), k2h: Self.knap(b.t2, b.th)
        )
    }

    /// 종류 k 를 delta 만큼 바꾼 그 부분의 (표, 열쇠). c 는 바뀌지 않은 손.
    mutating func changedTable(_ b: Base, _ c: inout [Int], kind k: Int, delta: Int) -> (UInt64, Int) {
        if k < 27 {
            let s = k / 9
            let code = (s == 0 ? b.code0 : s == 1 ? b.code1 : b.code2) + delta * Self.pow5[k - s * 9]
            if let t = suits[code] { return (t, code) }
            c[k] += delta
            let t = suitTable(c, s, code: code)
            c[k] -= delta
            return (t, code)
        }
        let code = b.codeH + delta * Self.pow5h[k - 27]
        if let t = honors[code] { return (t, code) }
        c[k] += delta
        let t = honorTable(c, code: code)
        c[k] -= delta
        return (t, code)
    }

    /// base 의 손 c 에서 종류 k 를 delta(±1)만큼 바꾼 손의 샹텐. c 는 그대로 둔다.
    mutating func shanten(_ b: Base, _ c: inout [Int], kind k: Int, delta: Int) -> Int {
        guard b.valid else { return 8 }
        let old = c[k]
        let new = old + delta
        if new < 0 || new > 4 { return 8 }
        let (table, _) = changedTable(b, &c, kind: k, delta: delta)
        let rest = k < 9 ? b.rest0 : k < 18 ? b.rest1 : k < 27 ? b.rest2 : b.restH
        var v = Self.pick(rest, table, target: b.target) - 1
        if b.melds == 0 {
            let pairs = b.pairs + (new >= 2 ? 1 : 0) - (old >= 2 ? 1 : 0)
            let kinds = b.kinds + (new >= 1 ? 1 : 0) - (old >= 1 ? 1 : 0)
            var yk = b.yaochuKinds, yp = b.yaochuPairs
            if Self.isYaochu[k] {
                yk += (new >= 1 ? 1 : 0) - (old >= 1 ? 1 : 0)
                yp += (new >= 2 ? 1 : 0) - (old >= 2 ? 1 : 0)
            }
            v = min(v, Self.other(pairs: pairs, kinds: kinds, yk: yk, yp: yp))
        }
        return v
    }

    /// 14장 꼴 b(부분 합 pr)에서 종류 d 한 장을 뺀 13장 꼴의 Base — 바뀐 부분 표 하나 + 나머지 합 세 번.
    mutating func removing(_ b: Base, _ pr: Pairs, _ c: inout [Int], kind d: Int) -> Base {
        guard b.valid, c[d] > 0 else { return .invalid }
        let (t, code) = changedTable(b, &c, kind: d, delta: -1)
        var t0 = b.t0, t1 = b.t1, t2 = b.t2, th = b.th
        var c0 = b.code0, c1 = b.code1, c2 = b.code2, ch = b.codeH
        var r0 = b.rest0, r1 = b.rest1, r2 = b.rest2, rh = b.restH
        switch d {
        case 0..<9:
            t0 = t; c0 = code
            r1 = Self.knap(t, pr.k2h); r2 = Self.knap(t, pr.k1h); rh = Self.knap(t, pr.k12)
        case 9..<18:
            t1 = t; c1 = code
            r0 = Self.knap(t, pr.k2h); r2 = Self.knap(t, pr.k0h); rh = Self.knap(t, pr.k02)
        case 18..<27:
            t2 = t; c2 = code
            r0 = Self.knap(t, pr.k1h); r1 = Self.knap(t, pr.k0h); rh = Self.knap(t, pr.k01)
        default:
            th = t; ch = code
            r0 = Self.knap(t, pr.k12); r1 = Self.knap(t, pr.k02); r2 = Self.knap(t, pr.k01)
        }
        let old = c[d], new = old - 1
        let pairs = b.pairs + (new >= 2 ? 1 : 0) - (old >= 2 ? 1 : 0)
        let kinds = b.kinds + (new >= 1 ? 1 : 0) - (old >= 1 ? 1 : 0)
        var yk = b.yaochuKinds, yp = b.yaochuPairs
        if Self.isYaochu[d] {
            yk += (new >= 1 ? 1 : 0) - (old >= 1 ? 1 : 0)
            yp += (new >= 2 ? 1 : 0) - (old >= 2 ? 1 : 0)
        }
        var sh = Self.pick(rh, th, target: b.target) - 1
        var wide = false
        if b.melds == 0 {
            let o = Self.other(pairs: pairs, kinds: kinds, yk: yk, yp: yp)
            wide = o <= sh
            sh = min(sh, o)
        }
        return Base(
            melds: b.melds, target: b.target, t0: t0, t1: t1, t2: t2, th: th, code0: c0, code1: c1, code2: c2, codeH: ch,
            rest0: r0, rest1: r1, rest2: r2, restH: rh, pairs: pairs, kinds: kinds, yaochuKinds: yk, yaochuPairs: yp,
            shanten: sh, wide: wide, valid: true
        )
    }

    /// 13장 꼴(base 의 손 c)의 유효패 — 샹텐을 줄이는 종류마다 남은 장수 u. c 는 그대로 둔다.
    /// 표준형만이 샹텐을 정하면(wide 거짓) 손의 패에서 두 칸 넘게 떨어진 종류(자패는 안 쥔 종류)는 몸통·머리의 첫 장이 될 수 없어 건너뛴다.
    mutating func ukeire(_ b: Base, _ c: inout [Int], unseen u: [Int]) -> (count: Int, kinds: [Int]) {
        var total = 0
        var kinds: [Int] = []
        var k = 0
        while k < 34 {
            if c[k] < 4 && u[k] > 0 && (b.wide || Self.near(c, k)) && shanten(b, &c, kind: k, delta: 1) < b.shanten {
                total += u[k]
                kinds.append(k)
            }
            k += 1
        }
        return (total, kinds)
    }

    static func near(_ c: [Int], _ k: Int) -> Bool {
        if c[k] > 0 { return true }
        if k >= 27 { return false }
        let n = k % 9
        var i = k - min(n, 2)
        let hi = k + min(8 - n, 2)
        while i <= hi {
            if c[i] > 0 { return true }
            i += 1
        }
        return false
    }
}
