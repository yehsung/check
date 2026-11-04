import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 판 진행 엔진(갈래 E)의 숨은 정보 — SPEC §4.2 '봇도 사람 화면도 payload 투영만 받는다' · §3.6 거르는 규칙 · §3.7 (d) 누출 표.
// ① payload(for: v) 의 모든 패 id 가 v 의 시야(내 손·내가 뽑은 패 + 이 국의 공개 패) 안 ② 울기 선택지가 있는 판과 없는 판에서
// 선택지 없는 자리들의 payload 가 글자 하나 다르지 않다(멈춤 전 '누가 고민 중'이 안 보인다) ③ 숨은 패만 다른 두 판을 payload 만 읽는
// 결정자로 몰면 공개 흐름이 같다(봇 비간섭).

enum MahjongEngineSight {
    static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    /// 이 국의 공개 패 + 보는 자리의 손·뽑은 패(엔진 원문 사건 기록에서 — payload 를 거치지 않는다).
    static func vision(_ e: MahjongTableEngine, _ v: Int) -> Set<Int> {
        let start = e.log.lastIndex { $0.kind == "deal" } ?? 0
        var out = Set(e.seatState[v].hand)
        if let d = e.seatState[v].drawn { out.insert(d) }
        for ev in e.log[start...] {
            switch ev.kind {
            case "deal": ev.dora?.forEach { out.insert($0.id) }
            case "draw": if ev.seat == v, let t = ev.tile { out.insert(t.id) }
            case "discard": if let t = ev.tile { out.insert(t.id) }
            case "call", "kan": ev.tiles?.forEach { out.insert($0.id) }
            case "dora": if let t = ev.indicator { out.insert(t.id) }
            default: break
            }
        }
        return out
    }

    /// payload 안 패 id(지난 국 결과 `last_hand` 는 지난 패산이라 따로 — 그 국 끝 공개분이다). 사건은 이 국 것만.
    static func tileIDs(_ p: MahjongStatePayload) -> Set<Int> {
        var out = Set<Int>()
        func add(_ ts: [MahjongTile]?) { ts?.forEach { out.insert($0.id) } }
        add(p.myHand)
        if let d = p.myDrawn { out.insert(d.id) }
        add(p.match?.doraIndicators)
        for s in p.seats ?? [] {
            add(s.discards?.map(\.tile))
            s.melds?.forEach { add($0.tiles) }
        }
        let events = p.events ?? []
        let start = events.lastIndex { $0.kind == "deal" } ?? 0
        for ev in events.isEmpty ? [] : Array(events[start...]) {
            if let t = ev.tile { out.insert(t.id) }
            add(ev.tiles)
            if let t = ev.called { out.insert(t.id) }
            if let t = ev.indicator { out.insert(t.id) }
            add(ev.dora)
            if let t = ev.priv?.tile { out.insert(t.id) }
        }
        switch p.myDecision {
        case .turn(let t)?:
            add(t.discard); add(t.riichi); add(t.kakan); t.ankan.forEach(add)
        case .call(let c)?:
            out.insert(c.tile.id); c.pon.forEach(add); c.minkan.forEach(add); c.chi.forEach(add)
        case nil:
            break
        }
        return out
    }

    /// 걸음마다 네 자리 모두 시야를 잰다 — 어긋난 글.
    static func leaks(_ e: MahjongTableEngine, step: Int) -> [String] {
        guard e.stage != .idle else { return [] }
        var out: [String] = []
        for v in 0..<4 {
            let p = e.payload(for: v, since: 0, now: epoch)
            let extra = tileIDs(p).subtracting(vision(e, v))
            if !extra.isEmpty { out.append("걸음 \(step) 자리 \(v) 시야 밖 패 \(extra.sorted())") }
            for ev in p.events ?? [] where ev.seat != v && (ev.priv != nil || (ev.kind == "draw" && ev.tile != nil)) {
                out.append("걸음 \(step) 자리 \(v) 가 남의 사건 숨은 칸을 본다(seq \(ev.seq))")
            }
        }
        return out
    }

    /// 패산 하나: 씨앗 순열에서 haku(31 — id 124~127)를 친 쯔모(52)·깊은 산(100~102)에만 둔다.
    static func baseWall() -> [Int] {
        var rng = GomokuAISplitMix64(seed: 3_141_592)
        var w = Array(0..<136).filter { !(124...127).contains($0) }
        w.shuffle(using: &rng)
        w.insert(124, at: 52)
        w.insert(125, at: 100)
        w.insert(126, at: 101)
        w.insert(127, at: 102)
        return w
    }

    /// payload 만 읽는 결정자(시간 초과 동작 — 뽑은 패나 오른쪽 끝, 울기는 넘김).
    static func decide(_ view: MahjongStatePayload, seat: Int) -> MahjongEngineStep {
        switch view.myDecision {
        case let d?:
            switch MahjongRules.timeoutAction(d, drawn: view.myDrawn) {
            case .discard(let t): return .act(seat: seat, .discard(t))
            case .tsumo: return .act(seat: seat, .tsumo)
            case .ron: return .call(seat: seat, .ron)
            case .pass: return .call(seat: seat, .pass)
            }
        case nil:
            return .wait
        }
    }
}

@Suite struct MahjongTableEngineHiddenTests {
    // 없으면: 남의 뽑은 패(draw.tile)·자동 버림 표지·손·뒷도라가 사건이나 칸에 실려 화면·봇으로 새도(§3.6) 아무 시험도 빨개지지 않는다.
    @Test(arguments: ["R-CHANKAN", "R-RINSHAN-ANKAN", "R-KAKAN-CHAIN-DORA", "R-AWAY-NO-WIN", "R-TIMEOUT-AUTO-RON", "R-PAO-RON"])
    func everyPayloadTileIsInsideThatSeatsSight(_ id: String) throws {
        let rec = try #require(MahjongReplay.record(id))
        var leaks: [String] = []
        var checked = 0
        let run = MahjongReplay.run(rec) { e, i in
            leaks += MahjongEngineSight.leaks(e, step: i)
            checked += 1
        }
        #expect(run.failure == nil)
        #expect(leaks.isEmpty, "\(id): \(leaks.prefix(3).joined(separator: " | "))")
        #expect(checked == ((rec["script"] as? [Any])?.count ?? 0) + 1)
    }

    // 없으면: 자체 대국(무작위 울기·리치·깡·자리 비움 자동)의 걸음에서 새는 칸을 replay 몇 개로는 못 덮는다.
    @Test func seededSelfPlayNeverLeaksHiddenTiles() {
        var leaks: [String] = []
        var steps = 0
        _ = MahjongEngineInvariant.selfPlay(seed: 99, maxSteps: 120) { e in
            steps += 1
            leaks += MahjongEngineSight.leaks(e, step: steps)
        }
        #expect(leaks.isEmpty, "\(leaks.prefix(3).joined(separator: " | "))")
        #expect(steps > 100)
    }

    // 없으면: 선택지 있는 사람이 고민하는 동안의 공개 칸(phase·사건·산 장수·seq)이 '아무도 못 운다'와 갈려 남이 그 손을 읽는다
    // (§3.7 (d) — 창이 열리자마자 닫혀도 쯔모는 다음 걸음이어야 같다).
    @Test func thirdSeatsPayloadIsTheSameWhetherSomeoneCanCallOrNot() throws {
        let base = MahjongEngineSight.baseWall()
        var withPon = base
        withPon.swapAt(13, 100)   // 자리 1 손에 haku 둘 → 친이 버리는 haku 를 퐁할 수 있다
        withPon.swapAt(14, 101)
        var a = MahjongTableEngine(format: .tonpuu, seats: [nil, nil, nil, nil])
        var b = MahjongTableEngine(format: .tonpuu, seats: [nil, nil, nil, nil])
        _ = a.deal(wall: withPon)
        _ = b.deal(wall: base)
        let haku = try #require(MahjongTile(id: 124))
        let ra = a.act(seat: 0, .discard(haku)), rb = b.act(seat: 0, .discard(haku))
        #expect((try? ra.get()) != nil && (try? rb.get()) != nil)
        // 판이 정말 갈렸다(기준선): a 의 자리 1 만 울기 결정이 있고, 그 자리 화면은 둘이 다르다.
        guard case .call(let c)? = a.decision(for: 1) else { Issue.record("a 자리 1 에 울기 결정이 없다"); return }
        #expect(!c.pon.isEmpty)
        #expect(b.decision(for: 1) == nil)
        #expect(a.phase == .claim(1))
        #expect(b.phase == .drawWait(1))
        let now = MahjongEngineSight.epoch
        #expect(a.payload(for: 1, since: 0, now: now) != b.payload(for: 1, since: 0, now: now))
        for v in [0, 2, 3] {
            #expect(a.decision(for: v) == nil && b.decision(for: v) == nil)
            #expect(a.payload(for: v, since: 0, now: now) == b.payload(for: v, since: 0, now: now), "자리 \(v) 화면이 갈린다")
        }
        #expect(a.payload(for: nil, since: 0, now: now) == b.payload(for: nil, since: 0, now: now))
        // 넘긴 뒤(a 는 답으로 닫혀 바로 쯔모 · b 는 다음 걸음의 따라잡기로 쯔모)에도 남 셋의 화면은 같다.
        let pa = a.call(seat: 1, .pass), pb = b.step(.wait)
        #expect((try? pa.get())?.last?.kind == "draw" && (try? pb.get())?.last?.kind == "draw")
        for v in [0, 2, 3] {
            #expect(a.payload(for: v, since: 0, now: now) == b.payload(for: v, since: 0, now: now), "넘긴 뒤 자리 \(v) 화면이 갈린다")
        }
    }

    // 없으면: 봇·화면이 payload 밖(패산·남의 손·뒷도라)을 읽는 길이 생겨도 모른다 — 숨은 패만 다른 두 판을 payload 만 읽는 결정자로
    // 몰면 모든 자리의 화면과 결정이 걸음마다 같아야 한다.
    @Test func hiddenOnlyDifferencesNeverChangeAnyViewOrDecision() {
        let base = MahjongEngineSight.baseWall()
        var other = base
        other.swapAt(110, 111)   // 깊은 산(이 시험 동안 아무도 안 뽑는다)
        other.swapAt(131, 132)   // 뒷도라 표시패
        other.swapAt(127, 128)   // 아직 안 열린 깡도라 표시패
        #expect(base != other)
        var a = MahjongTableEngine(format: .tonpuu, seats: [nil, nil, nil, nil])
        var b = MahjongTableEngine(format: .tonpuu, seats: [nil, nil, nil, nil])
        _ = a.deal(wall: base)
        _ = b.deal(wall: other)
        let now = MahjongEngineSight.epoch
        var steps = 0
        for _ in 0..<40 {
            let seat = a.pendingSeats.first ?? 0
            let va = a.payload(for: seat, since: 0, now: now)
            let vb = b.payload(for: seat, since: 0, now: now)
            #expect(va == vb, "걸음 \(steps) 자리 \(seat) 화면이 갈린다")
            let op = MahjongEngineSight.decide(va, seat: seat)
            #expect(op == MahjongEngineSight.decide(vb, seat: seat))
            _ = a.step(op)
            _ = b.step(op)
            steps += 1
        }
        for v in 0..<4 {
            #expect(a.payload(for: v, since: 0, now: now) == b.payload(for: v, since: 0, now: now), "끝에 자리 \(v) 화면이 갈린다")
        }
        #expect(a.seq > 40)
        #expect(a.wall != b.wall)
    }
}
