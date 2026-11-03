import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 화료 꼴·대기·샹텐(MJ-22 · MJ-26 · X-03) — 코퍼스 shape 11 과 X-03 정답지, 색별 파레토 반례.
// 샹텐·대기 정의는 X-03 판: 순수 손패에 4장 쥔 종류는 대기가 아니다. 흔한 공식(8 − 2×몸통 − 타쯔 − 머리)은
// `1111m234p567p789p` 를 텐파이로 잘못 본다(T-QUAD-NOTEN). 샹텐은 색마다 (몸통 수 × 머리 수) 비용 표 전부를 합친다(UX:268).

@Suite("아잉 마작 화료 꼴·대기·샹텐 — shape 11 · X-03 · 색별 파레토")
struct MahjongHandTests {
    private static func counts(_ text: String) -> [Int] { MahjongCorpus.counts(text) }

    // 없으면: 샹텐·대기·텐파이 정의가 reference(그리고 서버 mahjong_waits)와 갈려 봇·보조 표시·리치 선언패가 틀린다.
    @Test("shape 11 — shanten · waits(종류 글자) · tenpai")
    func shapeCases() {
        let cases = MahjongCorpus.cases(ofType: "shape")
        #expect(cases.count == 11)
        var failures: [String] = []
        for c in cases {
            guard MahjongCorpus.kindList(c.input["closed"]?.string ?? "x") != nil else { failures.append("\(c.id): 글자"); continue }
            let melds = c.input["n_melds"]?.int ?? 0
            let counts = Self.counts(c.input["closed"]?.string ?? "")
            let waits = MahjongHand.waits(counts, melds: melds)
            let got: MahjongCorpus.Value = .object([
                "shanten": .number(Double(MahjongHand.shanten(counts, melds: melds))),
                "waits": .string(MahjongTiles.text(kinds: waits)),
                "tenpai": .bool(!waits.isEmpty),
            ])
            let d = MahjongCorpus.diffs(c.expected, got)
            if !d.isEmpty { failures.append("\(c.id): " + d.joined(separator: " | ")) }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 4장 쥔 종류를 대기·머리로 치는 흔한 공식이 들어와도(X-03) 코퍼스 세 사례 말고는 잡을 데가 없다.
    @Test("X-03 셋 — 4장 쥔 손 노텐(1샹텐) · 두 벌 4장 · 4장 OK(다른 종류 대기)")
    func quadRules() throws {
        for (id, shanten, waits) in [("T-QUAD-NOTEN", 1, ""), ("T-DOUBLE-QUAD", nil as Int?, ""), ("T-QUAD-OK", 0, "4m")] {
            let c = try #require(MahjongCorpus.byID(id), "\(id)")
            let counts = Self.counts(c.input["closed"]?.string ?? "")
            let melds = c.input["n_melds"]?.int ?? 0
            #expect(MahjongTiles.text(kinds: MahjongHand.waits(counts, melds: melds)) == waits, "\(id)")
            if let shanten { #expect(MahjongHand.shanten(counts, melds: melds) == shanten, "\(id)") }
            #expect(c.expected["waits"]?.string == waits, "정답지와 같은 글자")
        }
        // 기준선: 4장째를 빼면(1111m → 111m + 다른 패) 같은 꼴이 텐파이다 — 단언이 '늘 노텐'으로 초록인 것이 아니다.
        #expect(MahjongHand.waits(Self.counts("111m9m234p567p789p"), melds: 0) == [8])
        #expect(MahjongHand.shanten(Self.counts("111m9m234p567p789p"), melds: 0) == 0)
    }

    /// 색마다 최선 하나만 고르는 순진한 합: 색(자패는 종류)마다 '이미 제자리인 장수'(3m + 2p − 비용)가 가장 큰 칸 하나를 골라 더한다.
    /// 몸통 4 · 머리 1 의 전체 예산을 보지 않아 두 색이 서로 머리를 쓰려는 손에서 텐파이로 잘못 본다.
    private static func naivePerSuitShanten(_ c: [Int], melds: Int) -> Int {
        var tables = (0..<3).map { ShantenTable.suitCost(c, from: $0 * 9) }
        tables += (27..<34).map { ShantenTable.honorCost(c[$0]) }
        var placed = 0
        for t in tables {
            var best = Int.min
            for m in 0...4 { for p in 0...1 where t[m * 2 + p] < ShantenTable.inf { best = max(best, 3 * m + 2 * p - t[m * 2 + p]) } }
            placed += best
        }
        return 3 * (4 - melds) + 2 - placed - 1
    }

    // 없으면: 샹텐을 색마다 최선 하나로 합치는 구현(SPEC §2.2 금지)이 들어와도 초록이다 — 봇이 1샹텐 손을 텐파이로 보고 리치를 노린다.
    @Test("색별 파레토 — 99m3444567p2245s 는 1샹텐(대기 없음) · 기준선: 색마다 최선 하나면 0(텐파이)")
    func paretoAcrossSuits() {
        let hand = Self.counts("99m3444567p2245s")
        #expect(MahjongHand.shanten(hand, melds: 0) == 1, "reference shanten = 1")
        #expect(MahjongHand.waits(hand, melds: 0).isEmpty)
        #expect(Self.naivePerSuitShanten(hand, melds: 0) == 0, "기준선: 순진한 합은 텐파이로 본다")
        // 반례가 아닌 손에서는 두 셈이 같다(기준선이 늘 다른 값을 내는 것이 아니다).
        let plain = Self.counts("123m456p789s1122z")
        #expect(MahjongHand.shanten(plain, melds: 0) == Self.naivePerSuitShanten(plain, melds: 0))
    }

    // 없으면: 샹텐과 대기가 따로 놀아(한쪽만 고친 결함) 보조 표시 '텐파이'와 대기 목록이 어긋난다.
    @Test("shanten 0 ⇔ waits ≠ [] — 코퍼스 shape · 대조 손 13장 꼴·울기 꼴 전부")
    func shantenZeroIffWaits() {
        var hands: [([Int], Int)] = MahjongCorpus.cases(ofType: "shape").map {
            (Self.counts($0.input["closed"]?.string ?? ""), $0.input["n_melds"]?.int ?? 0)
        }
        let xval = MahjongXval.gate
        for key in ["shape13", "shape_meld"] {
            for r in xval[key]?.array ?? [] {
                let ids = (r["closed"]?.array ?? []).compactMap { $0.int.flatMap(MahjongTile.init(id:)) }
                hands.append((MahjongTiles.counts34(ids), r["n_melds"]?.int ?? 0))
            }
        }
        #expect(hands.count == 11 + 180)
        var bad: [String] = []
        var tenpai = 0
        for (c, melds) in hands {
            let s = MahjongHand.shanten(c, melds: melds), w = MahjongHand.waits(c, melds: melds)
            if (s == 0) != !w.isEmpty { bad.append("\(MahjongTiles.text(kinds: (0..<34).flatMap { Array(repeating: $0, count: c[$0]) })) s=\(s) w=\(w)") }
            if s == 0 { tenpai += 1 }
        }
        #expect(tenpai > 30, "기준선: 텐파이 손이 충분히 있다(늘 '둘 다 아님'으로 초록이 아니다)")
        #expect(bad.isEmpty, "\(bad.prefix(5).joined(separator: "\n"))")
    }

    // 없으면: 화료 꼴 판정(MJ-22)의 세 꼴·울기 수가 틀려도 손 계산 코퍼스만으로는 어느 층이 틀렸는지 모른다.
    @Test("isComplete — 표준형 · 치또이(4장은 두 쌍 아님) · 국사 · 울기 수 · 샹텐 −1")
    func completeShapes() {
        #expect(MahjongHand.isComplete(Self.counts("123m456p789s11z222z"), melds: 0))
        #expect(MahjongHand.isComplete(Self.counts("1133557799m1122z"), melds: 0), "치또이")
        #expect(!MahjongHand.isComplete(Self.counts("1111m335577m1122z"), melds: 0), "4장은 두 쌍이 아니다(MJ-22-2)")
        #expect(MahjongHand.isComplete(Self.counts("19m19p19s12345677z"), melds: 0), "국사")
        #expect(!MahjongHand.isComplete(Self.counts("19m19p19s12345677z"), melds: 1), "울면 국사·치또이 없음")
        #expect(MahjongHand.isComplete(Self.counts("123m11z"), melds: 3), "울기 셋 + 몸통 하나 + 머리")
        #expect(!MahjongHand.isComplete(Self.counts("123m11z"), melds: 2), "기준선: 몸통이 모자란다")
        #expect(MahjongHand.shanten(Self.counts("123m456p789s11z222z"), melds: 0) == -1)
        #expect(MahjongHand.shanten(Self.counts("1133557799m1122z"), melds: 0) == -1)
        #expect(MahjongHand.shanten(Self.counts("19m19p19s1234567z"), melds: 0) == 0, "국사 13면 텐파이")
        #expect(MahjongHand.shanten(Self.counts("123m11z"), melds: 3) == -1)
        #expect(MahjongHand.shanten(Self.counts("13m11z"), melds: 3) == 0)
        #expect(MahjongHand.shanten([Int](repeating: 0, count: 33), melds: 0) == 8, "34칸이 아니면 8")
    }
}
