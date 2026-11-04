import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 판 진행 엔진(갈래 E)의 불변식 — SPEC §6.3 E 줄 · §3.7 (i) '불변식이 깨지면'.
// 걸음마다: 136장 보존(손 + 강(울려 간 패 제외) + 부로 + 남은 산 + 왕패 14) · seq 가 1씩 단조 · 점수 합 + 공탁 = 100000 ·
// 자리마다 손 + 3 × 부로 = 13 또는 14(차례 자리 14). 판은 replay 경계 레코드(울기·깡·창깡·책임 지불)와 씨앗 고정 자체 대국 두 갈래.

enum MahjongEngineInvariant {
    /// 강에서 울려 간 패를 빼고 센 판 위 136장(payload 공개 칸만 — 손은 장수).
    static func tileTotal(_ p: MahjongStatePayload) -> Int {
        let seats = p.seats ?? []
        let inPlay = seats.reduce(0) { acc, s in
            acc + (s.handCount ?? 0) + (s.discards ?? []).filter { $0.taken != true }.count
                + (s.melds ?? []).reduce(0) { $0 + $1.tiles.count }
        }
        return inPlay + (p.match?.wallRemaining ?? 0) + 14
    }

    /// 기준선: 강을 다 세는 순진한 셈(울린 패를 강과 부로에서 두 번 센다).
    static func naiveTileTotal(_ p: MahjongStatePayload) -> Int {
        let seats = p.seats ?? []
        let inPlay = seats.reduce(0) { acc, s in
            acc + (s.handCount ?? 0) + (s.discards ?? []).count + (s.melds ?? []).reduce(0) { $0 + $1.tiles.count }
        }
        return inPlay + (p.match?.wallRemaining ?? 0) + 14
    }

    /// 걸음 하나 뒤의 불변식 — 어긋나면 글.
    /// 왕패 밖으로 나와 아직 자리에 없는 패: 깡이 성립해 산 끝은 줄었는데 영상 쯔모를 다음 걸음으로 미룬 동안의 영상패(깡 수 − 영상 쯔모 수)
    /// · 창깡으로 뺏긴 가깡 패(화료자의 화료패 — `last_hand.wins[].win_tile` 에만 있다).
    static func inTransit(_ e: MahjongTableEngine) -> Int {
        var n = e.kans - e.rinshanUsed
        if e.stage == .handEnd || e.stage == .finished, let lastKan = e.log.lastIndex(where: { $0.kind == "kan" }),
           e.log[lastKan].type == "kakan", e.log[lastKan...].contains(where: { $0.kind == "win" }),
           !e.log[lastKan...].contains(where: { $0.kind == "draw" }) {
            n += 1
        }
        return n
    }

    static func violations(_ e: MahjongTableEngine) -> [String] {
        var out: [String] = []
        let p = e.payload(for: nil, since: 0, now: Date(timeIntervalSince1970: 0))
        let total = tileTotal(p) + inTransit(e)
        if total != 136 { out.append("136장 보존 \(total)") }
        let seqs = e.log.map(\.seq)
        if seqs != Array(stride(from: 1, through: seqs.count, by: 1)) { out.append("seq 가 1씩 오르지 않음") }
        if p.match?.seq != e.seq || e.seq != seqs.count { out.append("match.seq \(p.match?.seq ?? -1) ≠ 사건 수 \(seqs.count)") }
        let sum = e.scores.reduce(0, +) + 1000 * e.kyotaku
        if sum != 100_000 { out.append("점수 합 + 공탁 \(sum)") }
        for s in p.seats ?? [] {
            let n = (s.handCount ?? 0) + 3 * (s.melds ?? []).count
            if n != 13 && n != 14 { out.append("자리 \(s.seatNo) 손 + 3×부로 = \(n)") }
            if case .turn(let t) = e.phase, t == s.seatNo, n != 14 { out.append("차례 자리 \(t) 가 14장이 아님(\(n))") }
        }
        return out
    }

    /// 걸음마다 불변식을 재며 레코드를 돈다 — (어긋남, 순진한 셈이 136 이 아니던 걸음 수).
    static func replayWithInvariants(_ id: String) -> (failures: [String], naiveOff: Int) {
        guard let rec = MahjongReplay.record(id) else { return (["\(id): 레코드 없음"], 0) }
        var failures: [String] = []
        var naiveOff = 0
        let run = MahjongReplay.run(rec) { e, i in
            failures += violations(e).map { "\(id) 걸음 \(i): \($0)" }
            if naiveTileTotal(e.payload(for: nil, since: 0, now: Date(timeIntervalSince1970: 0))) + inTransit(e) != 136 { naiveOff += 1 }
        }
        if let f = run.failure { failures.append(f) }
        return (failures, naiveOff)
    }

    static func shuffledWall(_ rng: inout GomokuAISplitMix64) -> [Int] {
        var w = Array(0..<136)
        w.shuffle(using: &rng)
        return w
    }

    /// 씨앗 고정 자체 대국: 결정을 무작위로(합법만) 고르고, 자리 3 은 늘 시간 초과(→ 비움 → 자동). 걸음마다 each.
    static func selfPlay(seed: UInt64, maxSteps: Int, each: (MahjongTableEngine) -> Void) -> MahjongTableEngine {
        var rng = GomokuAISplitMix64(seed: seed)
        var e = MahjongTableEngine(format: .tonpuu, seats: [nil, nil, nil, nil])
        _ = e.deal(wall: shuffledWall(&rng))
        each(e)
        for _ in 0..<maxSteps {
            if e.isFinished { break }
            let pending = e.pendingSeats
            guard let seat = pending.first else {
                if case .handEnd = e.phase {
                    _ = e.startNextHand(wall: shuffledWall(&rng))
                } else {
                    _ = e.step(.wait)
                }
                each(e)
                continue
            }
            let op: MahjongEngineStep
            switch e.decision(for: seat) {
            case .turn(let t)? where seat == 3:
                op = t.tsumo ? .act(seat: seat, .tsumo) : .timeout(seat: seat)
            case .turn(let t)?:
                let r = Int.random(in: 0..<10, using: &rng)
                if t.tsumo {
                    op = .act(seat: seat, .tsumo)
                } else if t.kyuushu && r < 5 {
                    op = .act(seat: seat, .kyuushu)
                } else if !t.ankan.isEmpty && r < 6 {
                    op = .act(seat: seat, .ankan(t.ankan[0]))
                } else if !t.kakan.isEmpty && r < 6 {
                    op = .act(seat: seat, .kakan(t.kakan[0]))
                } else if !t.riichi.isEmpty && r < 7 {
                    op = .act(seat: seat, .riichi(t.riichi.randomElement(using: &rng) ?? t.riichi[0]))
                } else {
                    op = .act(seat: seat, .discard(t.discard.randomElement(using: &rng) ?? t.discard[0]))
                }
            case .call(let c)?:
                let r = Int.random(in: 0..<10, using: &rng)
                if c.ron {
                    op = .call(seat: seat, .ron)
                } else if !c.pon.isEmpty && r < 5 {
                    op = .call(seat: seat, .pon(c.pon[0]))
                } else if !c.minkan.isEmpty && r < 6 {
                    op = .call(seat: seat, .minkan(c.minkan[0]))
                } else if !c.chi.isEmpty && r < 4 {
                    op = .call(seat: seat, .chi(c.chi[0]))
                } else {
                    op = r == 9 ? .timeout(seat: seat) : .call(seat: seat, .pass)
                }
            case nil:
                op = .wait
            }
            _ = e.step(op)
            each(e)
        }
        return e
    }
}

@Suite struct MahjongTableEngineInvariantTests {
    /// 울기·깡·창깡·책임 지불·더블론·자리 비움이 든 경계 레코드.
    static let callHeavyIDs = ["R-CHANKAN", "R-RIICHI-CALLED", "R-RINSHAN-MINKAN", "R-KAKAN-CHAIN-DORA", "R-SUUKAIKAN-CALLED",
                               "R-PAO-COMPOUND", "R-DOUBLE-RON", "R-NAGASHI-CALLED", "R-KUIKAE-SUJI-TIMEOUT", "R-AWAY-STREAK"]

    // 없으면: 울린 패를 강과 부로에서 두 번 세거나(CC-08) 가깡 창 동안 더한 패가 사라지고, seq 가 건너뛰거나, 리치봉이 점수에서
    // 빠지지 않아도 사건 요약 대조만으로는 못 잡는다(요약은 사건만 본다).
    @Test(arguments: callHeavyIDs)
    func boundaryRecordKeepsInvariantsEveryStep(_ id: String) {
        let (failures, naiveOff) = MahjongEngineInvariant.replayWithInvariants(id)
        #expect(failures.isEmpty, "\(failures.prefix(3).joined(separator: " | "))")
        // 기준선: 울기가 성립한 레코드에서는 강을 다 세는 셈이 136 을 넘는 걸음이 있다(셈이 갈린다).
        let called = ((MahjongReplay.record(id)?["expect"] as? [String: Any])?["events"] as? [[Any]] ?? []).contains { $0.first as? String == "call" }
        if called { #expect(naiveOff > 0, "\(id): 순진한 셈과 갈리는 걸음이 없다") }
    }

    // 없으면: 대본에 없는 흐름(무작위 울기·리치·깡·자리 비움 자동·다음 국)에서 판 위 장수·점수가 새어도 replay 만으로는 못 잡는다.
    @Test(arguments: [UInt64(20_261_103), 7, 42])
    func seededSelfPlayKeepsInvariants(_ seed: UInt64) {
        var failures: [String] = []
        var steps = 0
        let e = MahjongEngineInvariant.selfPlay(seed: seed, maxSteps: 220) { e in
            steps += 1
            failures += MahjongEngineInvariant.violations(e).map { "씨앗 \(seed) 걸음 \(steps): \($0)" }
        }
        #expect(failures.isEmpty, "\(failures.prefix(3).joined(separator: " | "))")
        #expect(steps > 150)
        #expect(e.isAway(3), "늘 시간 초과하는 자리 3 이 비움으로 가지 않았다")
        #expect(e.log.contains { $0.kind == "away" && $0.seat == 3 && $0.reason == "timeouts" })
    }

    // 없으면: '보이는 장수'(상태 줄 · 봇 유효패)가 울린 패를 강과 부로에서 두 번 세도(CC-08) 엔진 원문으로 확인할 길이 없다.
    @Test func visibleCountsDoNotDoubleCountAPonnedTile() throws {
        let rec = try #require(MahjongReplay.record("R-CHANKAN"))
        var seen: MahjongStatePayload?
        _ = MahjongReplay.run(rec) { e, i in
            if i == 1 { seen = e.payload(for: 2, since: 0, now: Date(timeIntervalSince1970: 0)) }   // 자리 1 이 0 의 20(5만)을 퐁한 뒤
        }
        let p = try #require(seen)
        let kind = 5
        #expect(p.seats?[1].melds?.first?.tiles.map(\.id) == [20, 21, 22])
        #expect(p.seats?[0].discards?.last?.taken == true)
        #expect(MahjongVisibleTiles.counts(of: p)[kind] == 3)
        // 기준선: 강을 다 세면 4.
        var naive = 0
        for s in p.seats ?? [] {
            naive += (s.discards ?? []).filter { $0.tile.kind == kind }.count
            naive += (s.melds ?? []).flatMap(\.tiles).filter { $0.kind == kind }.count
        }
        naive += (p.myHand ?? []).filter { $0.kind == kind }.count
        #expect(naive == 4)
    }

    // 없으면: 14장 샹텐으로 리치 계산을 건너뛰는 지름길이 '버리면 텐파이'인 손을 놓쳐도(리치 단추가 사라져도) 모른다 —
    // R 의 riichiDiscards 를 그대로 부른 값과 같아야 한다. 텐파이 언저리 손이 많게 xval 13장 꼴에 한 장씩 더한다.
    @Test func riichiShortcutEqualsRulesRiichiDiscards() {
        var rng = GomokuAISplitMix64(seed: 1103)
        var checked = 0
        var withRiichi = 0
        // 화료 손(13장 텐파이)의 13장 + 아무 패 · 13장 무작위 꼴 + 아무 패 — 리치 되는 손과 먼 손이 섞인다.
        let tenpai = (MahjongXval.gate["win"]?.array ?? []).filter { ($0["input"]?["melds"]?.array ?? []).isEmpty }.prefix(16)
            .map { MahjongXval.tiles($0["input"]?["closed"]) }
        let far = (MahjongXval.gate["shape13"]?.array ?? []).prefix(10).map { MahjongXval.tiles($0["closed"]) }
        for hand in tenpai + far {
            guard hand.count == 13 else { continue }
            let used = Set(hand.map(\.id))
            let free = (0..<136).filter { !used.contains($0) }
            guard let extra = free.randomElement(using: &rng) else { continue }
            let c14 = hand.map(\.id) + [extra]
            let want = MahjongRules.riichiDiscards(closed14: MahjongTableEngine.tiles(c14), ankans: 0, score: 1000, liveLeft: 4,
                                                   menzen: true, already: false)
            #expect(MahjongTableEngine.riichiKinds(c14, ankans: 0) == want, "\(c14)")
            checked += 1
            if !want.isEmpty { withRiichi += 1 }
        }
        #expect(checked >= 24)
        #expect(withRiichi >= 8, "리치 되는 손이 너무 적어 기준선이 서지 않는다(\(withRiichi))")
    }
}
