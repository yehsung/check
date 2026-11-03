import Foundation

// 아잉 마작 판 진행 엔진 — 한 국의 흐름(갈래 E, SPEC §3.7 (c)(i) · rules.md MJ-08 · MJ-13~MJ-50). 직접 작성.
// 정본 대조: `MJ/fixtures/table_ref.py`(갈래 P1 — 같은 문장을 옮긴 파이썬) · replay 코퍼스 `T/Fixtures/mahjong/replay.json`.
// 판정은 갈래 R 함수만 부른다(evaluate · waits · riichiDiscards · resolveClaims · settle* · advance · finalResult).
//
// 흐름 약속(세 구현이 같은 문장을 옮긴다 — table_ref 머리):
//  · 창(버림·가깡·암깡)은 열 때 선택지를 한 번 계산하고, 자리 비움 자리의 선택지는 곧바로 pass. 답이 모여 resolveClaims 가 끝나면 닫는다.
//  · 창이 론 없이 닫히면: ① 화료패를 놓친 자리 동순 후리텐(리치 중이면 리치 후리텐 — 암깡 창은 국사 꼴로 기다리던 자리만)
//    ② 리치 선언패였으면 리치 성립(riichi 사건 · −1000 · 공탁 +1 — 울려도 성립, K-2/CS-01) → 사가리치면 유국
//    ③ 사깡유국(4번째 깡 뒤 타패, 울기보다 먼저 — rules C-15·C-20 기본안) ④ 넘김/울기 적용.
//  · 깡도라(MJ-11, C-02·C-03): 앞 깡의 미뤄 둔 표시패는 타패 순간 또는 새 깡 선언 직전(kan 사건 앞)에 연다. 암깡 표시패는
//    선언 때(kan 사건 뒤), 대명깡·가깡 표시패는 그 사람 타패 때. 창깡이 되면 그 가깡 표시패는 열지 않는다.
//  · 일발은 리치 성립 때 켜고, 그 사람의 다음 타패·누구의 울기·깡 성립(가깡은 창깡 확인 뒤, 암깡 포함)에 끈다(MJ-30, C-08).
//  · 시간 초과(MJ-54, §2.3 K-1): 차례면 쯔모 선택지가 있으면 쯔모, 아니면 뽑은 패, 뽑은 패가 없으면 허용 패 중 가장 큰 id.
//    울기 창이면 론 선택지가 있으면 론, 아니면 넘김. 자리 비움 자리는 화료하지 않는다(D7, rules C-18).
//  · 시간 초과 연속(§3.7 (b)): 자기 차례 시간 초과 +1(3 이면 'timeouts' 비움 — 그 동작 뒤), 직접 낸 act·call 은 0,
//    울기 창 시간 초과는 그대로, back 은 0.

extension MahjongTableEngine {
    // MARK: - 안쪽 타입

    enum Stage: Equatable, Sendable { case idle, turn, claim, draw, handEnd, finished }

    enum WindowKind: String, Sendable { case discard, kakan, ankan }

    struct EngineMeld: Equatable, Sendable {
        var type: MahjongMeldType
        var tiles: [Int]
        var called: Int?
        var fromSeat: Int?

        var meld: MahjongMeld {
            MahjongMeld(type: type, tiles: MahjongTableEngine.tiles(tiles), called: called.map(MahjongTableEngine.tile), fromSeat: fromSeat)
        }
    }

    struct DiscardRow: Equatable, Sendable {
        var tile: Int
        var tsumogiri: Bool
        var riichi: Bool
        var taken: Bool
    }

    struct Seat: Equatable, Sendable {
        let no: Int
        var away = false
        var awayReason: MahjongAwayReason?
        var awaySinceMs: Double?
        var streak = 0
        /// 손 안 패 id(쯔모패 제외), 오름차순.
        var hand: [Int] = []
        var drawn: Int?
        var melds: [EngineMeld] = []
        var discards: [DiscardRow] = []
        /// 리치 성립.
        var riichi = false
        /// 선언패를 버렸고 그 창이 아직 안 닫힘.
        var declared = false
        var doublePending = false
        var doubleRiichi = false
        var ippatsu = false
        var furiten = MahjongFuriten()
        /// 대기 종류(자기 버림 때 다시 잰다).
        var waits: [Int] = []
        var discardedOnce = false
        /// 쿠이카에 금지 종류(치·퐁 직후).
        var kuikae: [Int] = []
        var pao: MahjongPao?

        init(no: Int) { self.no = no }

        mutating func resetHand() {
            hand = []
            drawn = nil
            melds = []
            discards = []
            riichi = false
            declared = false
            doublePending = false
            doubleRiichi = false
            ippatsu = false
            furiten = MahjongFuriten()
            waits = []
            discardedOnce = false
            kuikae = []
            pao = nil
        }

        var closed14: [Int] { hand + (drawn.map { [$0] } ?? []) }
        var menzen: Bool { melds.allSatisfy { $0.type == .ankan } }
    }

    struct CallOptions: Equatable, Sendable {
        var ron = false
        var pon: [[Int]] = []
        var minkan: [[Int]] = []
        var chi: [[Int]] = []

        /// resolveClaims 에 넘길 고를 수 있는 것(론 > 퐁·깡 > 치 순서는 R 이 정한다).
        var kinds: [MahjongClaimKind] {
            var out: [MahjongClaimKind] = []
            if ron { out.append(.ron) }
            if !pon.isEmpty { out.append(.pon) }
            if !minkan.isEmpty { out.append(.minkan) }
            if !chi.isEmpty { out.append(.chi) }
            return out
        }
    }

    struct TurnOptions: Equatable, Sendable {
        var discard: [Int] = []
        var riichi: [Int] = []
        var tsumo = false
        var ankan: [[Int]] = []
        var kakan: [Int] = []
        var kyuushu = false
    }

    struct Window: Equatable, Sendable {
        let id: Int
        let kind: WindowKind
        let from: Int
        let tile: Int
        let houtei: Bool
        let order: [Int]
        var options: [Int: CallOptions] = [:]
        var answers: [Int: MahjongClaimAnswer] = [:]
        var chosen: [Int: [Int]] = [:]
        /// 가깡 창이면 더해질 퐁의 자리(`melds` 안 번호).
        let kakanMeld: Int?
    }

    struct PendingDraw: Equatable, Sendable {
        let seat: Int
        let rinshan: Bool
        /// 이 쯔모가 생긴 걸음 번호(그 걸음 안에서는 일어나지 않는다).
        let born: Int
    }

    struct HandRecord: Equatable, Sendable {
        let result: MahjongHandResult
        let advance: MahjongAdvance
        let kyotakuAfter: Int
    }

    struct FinalRecord: Equatable, Sendable {
        let endReason: String
        let order: [Int]
        let ranks: [Int]
        let finalScores: [Int]
        let kyotaku: Int
    }

    struct WinFlags: Sendable {
        var rinshan = false, haitei = false, houtei = false, chankan = false, heavenly = false, earthly = false
    }

    // MARK: - 작은 도우미

    var dealer: Int { handNo }

    /// 살아 있는 산 남은 장수(마지막 = 121 − 깡 수).
    var liveLeft: Int { (121 - kans) - ptr + 1 }

    var indicators: [Int] { (0..<timer.open).map { wall[126 + $0] } }

    var uraIndicators: [Int] { (0..<timer.open).map { wall[131 + $0] } }

    var allAway: Bool { seatState.allSatisfy(\.away) }

    static func counts(_ ids: [Int]) -> [Int] {
        var c = Array(repeating: 0, count: 34)
        for i in ids { c[i / 4] += 1 }
        return c
    }

    static func waits(_ ids: [Int], melds: Int) -> [Int] {
        MahjongHand.waits(counts(ids), melds: melds)
    }

    static let redIDs: Set<Int> = [16, 52, 88]

    /// 같은 종류 id 묶음에서 n 장 고르기 — 적5 여부가 같은 고르기는 하나만(작은 id 먼저, 사전순 조합 순서).
    static func uniqueCombos(_ ids: [Int], _ n: Int) -> [[Int]] {
        let s = ids.sorted()
        var out: [[Int]] = []
        var seen: [[Bool]] = []
        func walk(_ start: Int, _ pick: [Int]) {
            if pick.count == n {
                let key = pick.map { redIDs.contains($0) }
                if !seen.contains(key) {
                    seen.append(key)
                    out.append(pick)
                }
                return
            }
            guard start < s.count else { return }
            for i in start..<s.count { walk(i + 1, pick + [s[i]]) }
        }
        walk(0, [])
        return out
    }

    mutating func emit(_ kind: String, seat: Int? = nil, _ fill: (inout MahjongEvent) -> Void = { _ in }) {
        seqValue += 1
        var e = MahjongEvent(seq: seqValue, kind: kind, seat: seat, atMs: nowMs)
        fill(&e)
        log.append(e)
    }

    mutating func flushDora() {
        let old = timer.open
        timer.discard()
        for i in old..<max(old, timer.open) {
            let t = wall[126 + i]
            emit("dora") { $0.indicator = Self.tile(t) }
        }
    }

    mutating func timerKan(_ type: MahjongMeldType) {
        let old = timer.open
        timer.kan(type)
        for i in old..<max(old, timer.open) {
            let t = wall[126 + i]
            emit("dora") { $0.indicator = Self.tile(t) }
        }
    }

    mutating func clearIppatsu() {
        for i in 0..<4 { seatState[i].ippatsu = false }
    }

    // MARK: - 배패(MJ-08)

    mutating func dealHand(_ w: [Int]) {
        wall = w
        ptr = 53
        kans = 0
        kanSeats = []
        rinshanUsed = 0
        timer = MahjongDoraTimer()
        firstUninterrupted = true
        firstDiscards = []
        window = nil
        pendingDraw = nil
        for i in 0..<4 { seatState[i].resetHand() }
        for j in 0..<4 {
            let n = (dealer + j) % 4
            seatState[n].hand = Array(w[(13 * j)..<(13 * j + 13)]).sorted()
        }
        seatState[dealer].drawn = w[52]
        for n in 0..<4 where n != dealer {
            seatState[n].waits = Self.waits(seatState[n].hand, melds: 0)
        }
        let (hi, r, hn, hb, kt, d) = (handIndexValue, round, handNo, honba, kyotaku, dealer)
        emit("deal") {
            $0.handIndex = hi
            $0.round = r
            $0.handNo = hn
            $0.honba = hb
            $0.kyotaku = kt
            $0.dealerSeat = d
            $0.dora = [Self.tile(w[126])]
        }
        turnSeat = dealer
        turnRinshan = false
        stage = .turn
        decisionSeqValue = seqValue
    }

    mutating func startNext(_ w: [Int]) {
        guard stage == .handEnd, let n = nextHand else { return }
        round = n.round
        handNo = n.hand
        honba = n.honba
        handIndexValue += 1
        dealHand(w)
    }

    // MARK: - 손 계산

    func evaluate(_ seat: Int, win: Int, tsumo: Bool, _ f: WinFlags) -> MahjongScore? {
        let s = seatState[seat]
        let ctx = MahjongWinContext(
            closed: Self.tiles(s.hand), melds: s.melds.map(\.meld), win: Self.tile(win), tsumo: tsumo,
            seatWind: MahjongWind.allCases[(seat - dealer + 4) % 4], roundWind: MahjongWind.allCases[round % 4],
            riichi: s.riichi, doubleRiichi: s.doubleRiichi, ippatsu: s.ippatsu, rinshan: f.rinshan, chankan: f.chankan,
            haitei: f.haitei, houtei: f.houtei, heavenly: f.heavenly, earthly: f.earthly,
            doraIndicators: Self.tiles(indicators), uraIndicators: s.riichi ? Self.tiles(uraIndicators) : [],
            honba: honba, kyoutaku: kyotaku
        )
        if case .success(let score) = MahjongScoring.evaluate(ctx) { return score }
        return nil
    }

    func tsumoFlags(_ seat: Int) -> WinFlags {
        var f = WinFlags()
        if turnRinshan {
            f.rinshan = true
        } else if liveLeft == 0 {
            f.haitei = true
        }
        if firstUninterrupted && !seatState[seat].discardedOnce && !turnRinshan {
            if seat == dealer { f.heavenly = true } else { f.earthly = true }
        }
        return f
    }

    static func ronFlags(_ kind: WindowKind, houtei: Bool) -> WinFlags {
        var f = WinFlags()
        if kind == .kakan || kind == .ankan {
            f.chankan = true
        } else if houtei {
            f.houtei = true
        }
        return f
    }

    // MARK: - 차례 선택지(§3.7 (i) turn_options) — 동작 확인은 필요한 갈래만 잰다

    /// 버릴 수 있는 패. 치·퐁 직후는 쿠이카에 금지 종류를 뺀 손패, 리치 중이면 뽑은 패만.
    func discardOptions(_ seat: Int) -> [Int] {
        let s = seatState[seat]
        guard let drawn = s.drawn else { return s.hand.filter { !s.kuikae.contains($0 / 4) }.sorted() }
        return s.riichi ? [drawn] : s.closed14.sorted()
    }

    func tsumoOption(_ seat: Int) -> Bool {
        let s = seatState[seat]
        guard let drawn = s.drawn, Self.waits(s.hand, melds: s.melds.count).contains(drawn / 4) else { return false }
        return evaluate(seat, win: drawn, tsumo: true, tsumoFlags(seat))?.agari ?? false
    }

    func riichiOptions(_ seat: Int) -> [Int] {
        let s = seatState[seat]
        guard s.drawn != nil, !s.riichi, s.menzen, points[seat] >= 1000, liveLeft >= 4 else { return [] }
        let c14 = s.closed14
        let ks = Set(MahjongRules.riichiDiscards(closed14: Self.tiles(c14), ankans: s.melds.count, score: 1000, liveLeft: 4,
                                                 menzen: true, already: false))
        return c14.filter { ks.contains($0 / 4) }.sorted()
    }

    func ankanOptions(_ seat: Int) -> [[Int]] {
        let s = seatState[seat]
        guard let drawn = s.drawn, liveLeft >= 1, kans < 4 else { return [] }
        let c14 = s.closed14
        let cnt = Self.counts(c14)
        var out: [[Int]] = []
        for k in 0..<34 where cnt[k] == 4 {
            if s.riichi {
                guard k == drawn / 4,
                      MahjongRules.riichiAnkanOK(closed13: Self.tiles(s.hand), drawn: Self.tile(drawn), kanKind: drawn / 4,
                                                 melds: s.melds.count) else { continue }
            }
            out.append(c14.filter { $0 / 4 == k }.sorted())
        }
        return out
    }

    func kakanOptions(_ seat: Int) -> [Int] {
        let s = seatState[seat]
        guard s.drawn != nil, liveLeft >= 1, kans < 4, !s.riichi else { return [] }
        let c14 = s.closed14
        var out: [Int] = []
        for m in s.melds where m.type == .pon {
            let k = m.tiles[0] / 4
            out += c14.filter { $0 / 4 == k }
        }
        return out.sorted()
    }

    func kyuushuOption(_ seat: Int) -> Bool {
        let s = seatState[seat]
        guard s.drawn != nil, firstUninterrupted, !s.discardedOnce, !turnRinshan else { return false }
        return MahjongRules.kyuushuOK(Self.tiles(s.closed14), firstTurnUninterrupted: true)
    }

    func turnOptions(_ seat: Int) -> TurnOptions {
        var o = TurnOptions()
        o.discard = discardOptions(seat)
        guard seatState[seat].drawn != nil else { return o }
        o.tsumo = tsumoOption(seat)
        o.riichi = riichiOptions(seat)
        o.ankan = ankanOptions(seat)
        o.kakan = kakanOptions(seat)
        o.kyuushu = kyuushuOption(seat)
        return o
    }

    // MARK: - 울기 선택지(§3.7 (c)-1)

    func callOptions(_ seat: Int, kind: WindowKind, from d: Int, tile: Int, houtei: Bool) -> CallOptions {
        let s = seatState[seat]
        let k = tile / 4
        var res = CallOptions()
        if kind == .ankan {
            if s.melds.isEmpty && kokushiOn(seat, k) && s.furiten.canRon(s.waits) {
                var f = WinFlags()
                f.chankan = true
                res.ron = evaluate(seat, win: tile, tsumo: false, f)?.agari ?? false
            }
            return res
        }
        if s.waits.contains(k) && s.furiten.canRon(s.waits) {
            res.ron = evaluate(seat, win: tile, tsumo: false, Self.ronFlags(kind, houtei: houtei))?.agari ?? false
        }
        if kind != .discard || houtei || s.riichi { return res }
        let same = s.hand.filter { $0 / 4 == k }
        func rest(_ used: [Int]) -> [Int] { s.hand.filter { !used.contains($0) } }
        let called = Self.tile(tile)
        if same.count >= 2 {
            for c in Self.uniqueCombos(same, 2)
            where MahjongRules.callAllowed(call: .pon, called: called, fromHand: Self.tiles(c), closedAfter: Self.tiles(rest(c))) {
                res.pon.append(c)
            }
        }
        if same.count >= 3 && kans < 4 {
            res.minkan = Self.uniqueCombos(same, 3)
        }
        if seat == (d + 1) % 4 && k < 27 {
            let suit = k / 9
            for (a, b) in [(k - 2, k - 1), (k - 1, k + 1), (k + 1, k + 2)] {
                guard suit * 9 <= a, a < suit * 9 + 9, suit * 9 <= b, b < suit * 9 + 9 else { continue }
                let ia = s.hand.filter { $0 / 4 == a }
                let ib = s.hand.filter { $0 / 4 == b }
                for x in Self.uniqueCombos(ia, 1) {
                    for y in Self.uniqueCombos(ib, 1) {
                        let c = (x + y).sorted()
                        if MahjongRules.callAllowed(call: .chi, called: called, fromHand: Self.tiles(c), closedAfter: Self.tiles(rest(c))) {
                            res.chi.append(c)
                        }
                    }
                }
            }
        }
        return res
    }

    func kokushiOn(_ seat: Int, _ k: Int) -> Bool {
        var c = Self.counts(seatState[seat].hand)
        c[k] += 1
        return MahjongHand.isKokushi(c)
    }

    // MARK: - 따라잡기

    /// 미뤄 둔 일 가운데 '때가 된' 것만 한다: 앞 걸음에서 생긴 쯔모·다음 국 배패, 자리 비움 자리의 결정.
    /// 네 자리가 모두 비면 멈춤 0 이라 바로 한다(§3.7 (f) 모두 비움 모드).
    mutating func catchup() {
        while true {
            let aa = allAway
            switch stage {
            case .draw:
                guard let p = pendingDraw, p.born < stepNo || aa else { return }
                pendingDraw = nil
                draw(p.seat, rinshan: p.rinshan)
            case .turn where seatState[turnSeat].away:
                autoTurn(turnSeat, allowWin: false)
            case .handEnd where handEndStep < stepNo || aa:
                guard !wallQueue.isEmpty else { return }
                startNext(wallQueue.removeFirst())
            default:
                return
            }
        }
    }

    /// 창이 닫힌 뒤 쯔모: 여는 걸음 안에서 닫혔으면 다음 걸음으로 미루고, 답으로 닫혔으면(멈춤이 지났다) 바로.
    mutating func afterClose(_ seat: Int, rinshan: Bool) {
        if opening {
            pendingDraw = PendingDraw(seat: seat, rinshan: rinshan, born: stepNo)
            stage = .draw
        } else {
            draw(seat, rinshan: rinshan)
        }
    }

    mutating func draw(_ seat: Int, rinshan: Bool) {
        let t: Int
        if rinshan {
            t = wall[122 + rinshanUsed]
            rinshanUsed += 1
        } else {
            guard liveLeft > 0 else {
                // 하저 창이 닫히면 황패 유국으로 이미 끝난다 — 여기 오면 흐름 결함이다. 판을 세우지 않고 황패로 닫는다.
                exhaustive()
                return
            }
            t = wall[ptr]
            ptr += 1
            seatState[seat].furiten.drawLive()
        }
        seatState[seat].drawn = t
        emit("draw", seat: seat) {
            $0.tile = Self.tile(t)
            $0.rinshan = rinshan
        }
        turnSeat = seat
        turnRinshan = rinshan
        stage = .turn
        decisionSeqValue = seqValue
    }

    // MARK: - 차례 동작

    mutating func doAct(_ seat: Int, _ action: MahjongTurnAction) -> Result<Void, MahjongActError> {
        switch action {
        case .discard(let t):
            guard discardOptions(seat).contains(t.id) else { return .failure(.illegal) }
            discard(seat, t.id, riichi: false, auto: false)
        case .riichi(let t):
            guard riichiOptions(seat).contains(t.id) else { return .failure(.illegal) }
            discard(seat, t.id, riichi: true, auto: false)
        case .tsumo:
            guard tsumoOption(seat) else { return .failure(.illegal) }
            tsumoWin(seat)
        case .ankan(let ts):
            let ids = ts.map(\.id).sorted()
            guard ankanOptions(seat).contains(ids) else { return .failure(.illegal) }
            ankan(seat, ids)
        case .kakan(let t):
            guard kakanOptions(seat).contains(t.id) else { return .failure(.illegal) }
            kakan(seat, t.id)
        case .kyuushu:
            guard kyuushuOption(seat) else { return .failure(.illegal) }
            abortive("kyuushu")
        }
        return .success(())
    }

    /// 시간 초과·자리 비움의 차례 동작(MJ-54, §2.3) — `MahjongRules.timeoutAction`.
    mutating func autoTurn(_ seat: Int, allowWin: Bool) {
        let s = seatState[seat]
        let light = MahjongDecision.Turn(
            seq: seqValue, decisionSeq: decisionSeqValue, startedMs: 0, deadlineMs: 0, bankMs: 0,
            discard: Self.tiles(discardOptions(seat)), tsumo: allowWin && tsumoOption(seat)
        )
        switch MahjongRules.timeoutAction(.turn(light), drawn: s.drawn.map(Self.tile)) {
        case .tsumo:
            tsumoWin(seat)
        case .discard(let t):
            discard(seat, t.id, riichi: false, auto: true)
        case .ron, .pass:
            // 버릴 패가 없는 차례는 흐름 결함이다(손은 늘 1장 이상) — 손 오른쪽 끝을 버린다.
            if let last = s.closed14.max() { discard(seat, last, riichi: false, auto: true) }
        }
    }

    mutating func doTimeout(_ seat: Int) -> Result<Void, MahjongActError> {
        if seatState[seat].away { return .failure(.awayState) }
        if stage == .turn && turnSeat == seat {
            autoTurn(seat, allowWin: MahjongRules.timeoutAutoWin)
            seatState[seat].streak += 1
            if seatState[seat].streak >= Self.awayAfterTimeouts && stage != .finished {
                markAway(seat, .timeouts)
            }
            catchup()   // 시간 초과는 따라잡기 안에서 처리된다 — 그 따라잡기는 이어서 돈다
            return .success(())
        }
        if stage == .claim, let w = window, let o = w.options[seat], w.answers[seat] == nil {
            let d = MahjongDecision.Call(
                windowId: w.id, windowKind: w.kind.rawValue, tile: Self.tile(w.tile), fromSeat: w.from,
                startedMs: 0, deadlineMs: 0, bankMs: 0, ron: o.ron
            )
            let ron = MahjongRules.timeoutAction(.call(d), drawn: nil) == .ron
            _ = answer(seat, ron ? .ron : .pass)
            catchup()
            return .success(())
        }
        return .failure(.notYourTurn)
    }

    mutating func markAway(_ seat: Int, _ reason: MahjongAwayReason) {
        seatState[seat].away = true
        seatState[seat].awayReason = reason
        seatState[seat].awaySinceMs = nowMs
        emit("away", seat: seat) {
            $0.on = true
            $0.reason = reason.rawValue
        }
        if stage == .claim, var w = window, w.options[seat] != nil, w.answers[seat] == nil {
            w.answers[seat] = .pass
            window = w
            tryResolve()
        }
    }

    // MARK: - 버림

    mutating func discard(_ seat: Int, _ tile: Int, riichi: Bool, auto: Bool) {
        var s = seatState[seat]
        let tsumogiri = tile == s.drawn
        if tsumogiri {
            s.drawn = nil
        } else {
            if let i = s.hand.firstIndex(of: tile) { s.hand.remove(at: i) }
            if let d = s.drawn {
                s.hand.append(d)
                s.drawn = nil
            }
            s.hand.sort()
        }
        s.discards.append(DiscardRow(tile: tile, tsumogiri: tsumogiri, riichi: riichi, taken: false))
        s.furiten.ownDiscard(tile / 4)
        let first = !s.discardedOnce
        if riichi {
            s.declared = true
            s.doublePending = first && firstUninterrupted
            s.furiten.declareRiichi()
        } else {
            s.ippatsu = false
        }
        s.discardedOnce = true
        s.kuikae = []
        seatState[seat] = s
        emit("discard", seat: seat) {
            $0.tile = Self.tile(tile)
            $0.tsumogiri = tsumogiri
            $0.riichi = riichi
            if auto {
                var p = MahjongEventPriv()
                p.auto = true
                $0.priv = p
            }
        }
        showsLastHand = false
        flushDora()
        if first && firstUninterrupted { firstDiscards.append(tile / 4) }
        seatState[seat].waits = Self.waits(seatState[seat].hand, melds: seatState[seat].melds.count)
        if firstUninterrupted && firstDiscards.count == 4
            && MahjongRules.suufonRenda(firstDiscardKinds: firstDiscards, anyCall: false) {
            abortive("suufon")
            return
        }
        openWindow(.discard, from: seat, tile: tile, houtei: liveLeft == 0)
    }

    // MARK: - 깡 선언

    mutating func ankan(_ seat: Int, _ tiles: [Int]) {
        let hold = seatState[seat].closed14
        seatState[seat].drawn = nil
        seatState[seat].hand = hold.filter { !tiles.contains($0) }.sorted()
        flushDora()
        emit("kan", seat: seat) {
            $0.type = MahjongMeldType.ankan.rawValue
            $0.tiles = Self.tiles(tiles)
        }
        seatState[seat].melds.append(EngineMeld(type: .ankan, tiles: tiles, called: nil, fromSeat: nil))
        timerKan(.ankan)
        openWindow(.ankan, from: seat, tile: tiles.max() ?? tiles[0], houtei: false)
    }

    mutating func kakan(_ seat: Int, _ tile: Int) {
        var hold = seatState[seat].closed14
        seatState[seat].drawn = nil
        if let i = hold.firstIndex(of: tile) { hold.remove(at: i) }
        seatState[seat].hand = hold.sorted()
        guard let mi = seatState[seat].melds.firstIndex(where: { $0.type == .pon && $0.tiles[0] / 4 == tile / 4 }) else { return }
        flushDora()
        let all = (seatState[seat].melds[mi].tiles + [tile]).sorted()
        emit("kan", seat: seat) {
            $0.type = MahjongMeldType.kakan.rawValue
            $0.tiles = Self.tiles(all)
        }
        openWindow(.kakan, from: seat, tile: tile, houtei: false, kakanMeld: mi)
    }

    // MARK: - 창(§3.7 (c))

    mutating func openWindow(_ kind: WindowKind, from d: Int, tile: Int, houtei: Bool, kakanMeld: Int? = nil) {
        windowSerial += 1
        let order = [1, 2, 3].map { (d + $0) % 4 }
        var w = Window(id: windowSerial, kind: kind, from: d, tile: tile, houtei: houtei, order: order, kakanMeld: kakanMeld)
        for x in order {
            let o = callOptions(x, kind: kind, from: d, tile: tile, houtei: houtei)
            if !o.kinds.isEmpty { w.options[x] = o }
        }
        stage = .claim
        decisionSeqValue = seqValue
        for x in order where w.options[x] != nil && seatState[x].away {
            w.answers[x] = .pass
        }
        window = w
        opening = true
        tryResolve()
        opening = false
    }

    mutating func answer(_ seat: Int, _ a: MahjongCallAnswer) -> Result<Void, MahjongActError> {
        guard var w = window, let o = w.options[seat] else { return .failure(.notYourTurn) }
        switch a {
        case .pass:
            w.answers[seat] = .pass
        case .ron:
            guard o.ron else { return .failure(.illegal) }
            w.answers[seat] = .ron
        case .pon(let ts), .minkan(let ts), .chi(let ts):
            let ids = ts.map(\.id).sorted()
            let (list, ans): ([[Int]], MahjongClaimAnswer) = switch a {
            case .pon: (o.pon, .pon)
            case .minkan: (o.minkan, .minkan)
            default: (o.chi, .chi)
            }
            guard callTilesOK(seat, ids, list) else { return .failure(.illegal) }
            w.answers[seat] = ans
            w.chosen[seat] = ids
        }
        window = w
        tryResolve()
        return .success(())
    }

    /// 선택지 목록은 적5 여부로 하나씩만 보이지만, 같은 꼴(종류·적5 여부)의 다른 물리 패도 받는다.
    func callTilesOK(_ seat: Int, _ ids: [Int], _ list: [[Int]]) -> Bool {
        let hand = seatState[seat].hand
        guard Set(ids).count == ids.count, ids.allSatisfy(hand.contains) else { return false }
        func sig(_ c: [Int]) -> [Int] { c.map { $0 / 4 * 2 + (Self.redIDs.contains($0) ? 1 : 0) } }
        return list.contains { sig($0) == sig(ids) }
    }

    mutating func tryResolve() {
        guard let w = window else { return }
        let r = MahjongRules.resolveClaims(discarder: w.from, eligible: w.options.mapValues(\.kinds), answers: w.answers)
        if r == .wait { return }
        closeWindow(r)
    }

    mutating func closeWindow(_ r: MahjongClaimResolution) {
        guard let w = window else { return }
        window = nil
        let d = w.from, tile = w.tile, k = tile / 4
        if case .ron(let seats) = r {
            ronWin(seats, w)
            return
        }
        // ① 놓친 화료패 → 동순(리치면 리치) 후리텐(MJ-24, rules C-05)
        for x in w.order {
            if w.kind == .ankan {
                if seatState[x].melds.isEmpty && kokushiOn(x, k) { seatState[x].furiten.missed() }
            } else if seatState[x].waits.contains(k) {
                seatState[x].furiten.missed()
            }
        }
        // ② 리치 성립 — 론 없이 닫힘 넷 모두(K-2)
        if w.kind == .discard && seatState[d].declared {
            seatState[d].declared = false
            seatState[d].riichi = true
            seatState[d].ippatsu = true
            seatState[d].doubleRiichi = seatState[d].doublePending
            points[d] -= 1000
            kyotaku += 1
            emit("riichi", seat: d)
            if seatState.allSatisfy(\.riichi) {
                abortive("suucha_riichi")
                return
            }
        }
        // ③ 사깡유국 — 울기 적용 전(rules C-15·C-20 기본안)
        if w.kind == .discard && MahjongRules.suukaikan(kanSeats: kanSeats) {
            abortive("suukaikan")
            return
        }
        guard case .claim(let claimKind, let caller) = r else {
            // 넘김
            if w.kind == .discard {
                if w.houtei {
                    exhaustive()
                    return
                }
                afterClose((d + 1) % 4, rinshan: false)
            } else {   // 가깡·암깡 성립
                if w.kind == .kakan, let mi = w.kakanMeld {
                    seatState[d].melds[mi].type = .kakan
                    seatState[d].melds[mi].tiles = (seatState[d].melds[mi].tiles + [tile]).sorted()
                    timerKan(.kakan)
                }
                kans += 1
                kanSeats.append(d)
                firstUninterrupted = false
                clearIppatsu()
                afterClose(d, rinshan: true)
            }
            return
        }
        // ④ 퐁·대명깡·치
        let typ: MahjongMeldType = switch claimKind {
        case .pon: .pon
        case .minkan: .minkan
        default: .chi
        }
        let chosen = w.chosen[caller] ?? []
        if !seatState[d].discards.isEmpty { seatState[d].discards[seatState[d].discards.count - 1].taken = true }
        for t in chosen {
            if let i = seatState[caller].hand.firstIndex(of: t) { seatState[caller].hand.remove(at: i) }
        }
        let meldTiles = (chosen + [tile]).sorted()
        seatState[caller].melds.append(EngineMeld(type: typ, tiles: meldTiles, called: tile, fromSeat: d))
        firstUninterrupted = false
        clearIppatsu()
        emit("call", seat: caller) {
            $0.type = typ.rawValue
            $0.tiles = Self.tiles(meldTiles)
            $0.called = Self.tile(tile)
            $0.fromSeat = d
        }
        checkPao(caller, k, from: d)
        if typ == .minkan {
            timerKan(.minkan)
            kans += 1
            kanSeats.append(caller)
            draw(caller, rinshan: true)   // 대명깡은 영상 쯔모 뒤 차례 — 울기 확정 걸음 안에서 바로(§3.7 (c)-4)
            return
        }
        seatState[caller].kuikae = MahjongRules.kuikaeForbidden(call: typ, called: Self.tile(tile), fromHand: Self.tiles(chosen))
        turnSeat = caller
        turnRinshan = false
        stage = .turn
        decisionSeqValue = seqValue
    }

    /// MJ-42: 삼원 몸통 2개를 드러낸 사람에게 셋째 삼원을, 바람 3개에게 넷째 바람을 퐁·대명깡으로 준 사람(rules C-11 — 암깡 포함).
    mutating func checkPao(_ caller: Int, _ k: Int, from: Int) {
        let melds = seatState[caller].melds
        let prev = melds.dropLast().filter { [.pon, .minkan, .kakan, .ankan].contains($0.type) }.map { $0.tiles[0] / 4 }
        if (31...33).contains(k) && prev.filter({ (31...33).contains($0) }).count == 2 {
            seatState[caller].pao = MahjongPao(seat: from, yaku: .daisangen)
        }
        if (27...30).contains(k) && prev.filter({ (27...30).contains($0) }).count == 3 {
            seatState[caller].pao = MahjongPao(seat: from, yaku: .daisuushii)
        }
    }

    // MARK: - 국 끝

    func winSummary(_ seat: Int, _ res: MahjongScore, from: Int?, winTile: Int) -> MahjongWinResult {
        let s = seatState[seat]
        var w = MahjongWinResult(seat: seat)
        w.fromSeat = from
        w.hand = Self.tiles(s.hand.sorted())
        w.melds = s.melds.map { MahjongWireMeld($0.meld) }
        w.winTile = Self.tile(winTile)
        w.yaku = res.yaku.map { MahjongWireYaku($0) }
        w.yakuman = res.yakuman
        w.han = res.han
        w.fu = res.fu
        w.limit = res.limit
        w.dora = res.dora
        w.aka = res.aka
        w.ura = res.ura
        w.uraIndicators = s.riichi ? Self.tiles(uraIndicators) : nil
        w.total = res.total
        if let pao = s.pao, res.yakuman > 0, res.yaku.contains(where: { $0.yaku == pao.yaku }) {
            w.pao = MahjongWinResult.Pao(seat: pao.seat, yaku: pao.yaku.rawValue)
        }
        return w
    }

    mutating func tsumoWin(_ seat: Int) {
        guard let drawn = seatState[seat].drawn, let res = evaluate(seat, win: drawn, tsumo: true, tsumoFlags(seat)), res.agari else {
            return
        }
        let deltas = MahjongRules.settleWin(winner: seat, dealer: dealer, score: res, discarder: nil, honba: honba, kyoutaku: kyotaku,
                                            pao: seatState[seat].pao, getsBonus: true)
        var result = MahjongHandResult(handIndex: handIndexValue, kind: "win")
        result.wins = [winSummary(seat, res, from: nil, winTile: drawn)]
        result.tenpai = []
        result.nagashi = []
        result.bonusTo = seat
        emit("win") {
            $0.seats = [seat]
            $0.fromSeat = nil
        }
        finishHand(result, deltas, outcome: seat == dealer ? .dealerWin : .childWin, renchan: seat == dealer, clearKyotaku: true)
    }

    mutating func ronWin(_ winners: [Int], _ w: Window) {
        let d = w.from, tile = w.tile
        var wins: [(seat: Int, score: MahjongScore, pao: MahjongPao?)] = []
        var summaries: [MahjongWinResult] = []
        for x in winners {
            guard let res = evaluate(x, win: tile, tsumo: false, Self.ronFlags(w.kind, houtei: w.houtei)), res.agari else { continue }
            wins.append((x, res, seatState[x].pao))
            summaries.append(winSummary(x, res, from: d, winTile: tile))
        }
        seatState[d].declared = false   // 선언패가 론되면 리치 불성립(MJ-28)
        let deltas: [Int], bonusTo: Int, renchan: Bool
        if wins.count == 1 {
            let x = wins[0]
            deltas = MahjongRules.settleWin(winner: x.seat, dealer: dealer, score: x.score, discarder: d, honba: honba,
                                            kyoutaku: kyotaku, pao: x.pao, getsBonus: true)
            bonusTo = x.seat
            renchan = x.seat == dealer
        } else {
            let m = MahjongRules.settleRonMulti(discarder: d, dealer: dealer, wins: wins, honba: honba, kyoutaku: kyotaku)
            (deltas, bonusTo, renchan) = (m.deltas, m.bonusTo, m.renchan)
        }
        var result = MahjongHandResult(handIndex: handIndexValue, kind: "win")
        result.wins = summaries
        result.tenpai = []
        result.nagashi = []
        result.bonusTo = bonusTo
        emit("win") {
            $0.seats = winners
            $0.fromSeat = d
        }
        finishHand(result, deltas, outcome: renchan ? .dealerWin : .childWin, renchan: renchan, clearKyotaku: true)
    }

    mutating func exhaustive() {
        let tenpai = seatState.map { !Self.waits($0.hand, melds: $0.melds.count).isEmpty }
        let nagashi = seatState.map {
            MahjongRules.nagashiOK(discardKinds: $0.discards.map { $0.tile / 4 }, calledAway: $0.discards.contains(where: \.taken))
        }
        let st = MahjongRules.settleExhaustive(dealer: dealer, tenpai: tenpai, nagashi: nagashi)
        var result = MahjongHandResult(handIndex: handIndexValue, kind: "exhaustive")
        result.wins = []
        result.tenpai = (0..<4).filter { tenpai[$0] }.map { n in
            MahjongTenpaiResult(seat: n, hand: Self.tiles(seatState[n].hand.sorted()), melds: seatState[n].melds.map { MahjongWireMeld($0.meld) })
        }
        result.nagashi = (0..<4).filter { nagashi[$0] }
        emit("hand_draw") { $0.reason = "exhaustive" }
        finishHand(result, st.deltas, outcome: st.renchan ? .drawDealerTenpai : .drawDealerNoten, renchan: st.renchan, clearKyotaku: false)
    }

    mutating func abortive(_ reason: String) {
        var result = MahjongHandResult(handIndex: handIndexValue, kind: "abortive")
        result.reason = reason
        result.wins = []
        result.tenpai = []
        result.nagashi = []
        emit("hand_draw") { $0.reason = reason }
        finishHand(result, [0, 0, 0, 0], outcome: .abortive, renchan: true, clearKyotaku: false)
    }

    mutating func finishHand(_ partial: MahjongHandResult, _ deltas: [Int], outcome: MahjongHandOutcome, renchan: Bool, clearKyotaku: Bool) {
        window = nil
        pendingDraw = nil
        for i in 0..<4 { points[i] += deltas[i] }
        if clearKyotaku { kyotaku = 0 }
        let after = points
        emit("scores") {
            $0.deltas = deltas
            $0.scoresAfter = after
        }
        let adv = MahjongRules.advance(format: format, round: round, handNo: handNo, honba: honba, scores: points, outcome: outcome)
        var result = partial
        result.deltas = deltas
        result.scoresAfter = after
        result.renchan = renchan
        hands.append(HandRecord(result: result, advance: adv, kyotakuAfter: kyotaku))
        handEndStep = stepNo
        showsLastHand = true
        if adv.end {
            let fr = MahjongRules.finalResult(scores: points, kyoutaku: kyotaku)
            let reason = adv.reason ?? "max_round"
            finalRecord = FinalRecord(endReason: reason, order: fr.order, ranks: fr.ranks, finalScores: fr.finalScores, kyotaku: kyotaku)
            emit("end") { $0.endReason = reason }
            stage = .finished
        } else {
            nextHand = adv.next
            stage = .handEnd
        }
    }
}
