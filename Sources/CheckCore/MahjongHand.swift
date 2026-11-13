import Foundation
import os

// 아잉 마작 규칙 — 화료 꼴·대기·샹텐(MJ-22 · MJ-26 · X-03).
// 직접 작성, 외부 판정 코드 없음 — 정본 rules.md MJ-22·MJ-26, 대조 reference.py `is_complete`·`waits`·`shanten`.
//
// 입력은 **종류 34칸 장수 배열**(`MahjongTiles.counts34`)과 손 밖 몸통 수(울기·깡 수)다. 손 안 패만 센다.
// 대기 정의는 X-03 판: 1장을 더해 화료 꼴이 되는 종류 가운데 **순수 손패에 이미 4장 쥔 종류는 뺀다**(MJ-26).
// 흔한 샹텐 공식을 그대로 옮기면 `1111m234p567p789p` 를 텐파이로 잘못 본다 — 사례 T-QUAD-NOTEN·T-DOUBLE-QUAD·T-QUAD-OK.
// 샹텐은 색마다 최선 하나로 합치지 않는다(색마다 파레토 후보를 들고 합친다, SPEC §2.2).

package nonisolated enum MahjongHand {
    /// MJ-22 화료 꼴인가(역 무관). counts = 손 안 패(화료패 포함) 종류 장수, melds = 손 밖 몸통 수.
    /// 표준형(몸통 4−melds + 머리) · 울기 없을 때 치또이(서로 다른 7쌍) · 국사.
    package static func isComplete(_ counts: [Int], melds: Int) -> Bool {
        guard counts.count == 34, (0...4).contains(melds), counts.allSatisfy({ $0 >= 0 }) else { return false }
        if melds == 0 && (isChiitoi(counts) || isKokushi(counts)) { return true }
        var c = counts
        return decomposes(&c, need: 4 - melds, havePair: false, start: 0)
    }

    /// MJ-26 대기 종류(오름차순). 1장을 더해 화료 꼴이 되는 종류 X 가운데 손에 X 를 이미 4장 쥔 X 는 뺀다(X-03).
    /// 가라텐(모두 보이는 대기)은 대기로 친다. 울기 몸통에 3장 + 손에 1장인 X 는 대기다(rules C-06 기본안).
    package static func waits(_ counts: [Int], melds: Int) -> [Int] {
        guard counts.count == 34 else { return [] }
        var c = counts
        var out: [Int] = []
        for x in 0..<34 where c[x] < 4 {
            c[x] += 1
            if isComplete(c, melds: melds) { out.append(x) }
            c[x] -= 1
        }
        return out
    }

    /// 샹텐. −1 = 화료 꼴, 0 = 텐파이(X-03 판 — 4장 쥔 종류만 기다리는 손은 텐파이가 아니다).
    /// 표준형·치또이·국사 중 작은 값(치또이·국사는 울기 없을 때만). = reference `shanten`.
    /// 표준형 정의(reference `shanten_standard`): 손 안 패에 **더 들여야 할 최소 장수 − 1**. 목표 화료 꼴의 종류마다 장수는
    /// 손 안 4장 이하(머리 2 + 커쯔 3 처럼 5장이 드는 꼴은 버린다 — MJ-26 '4장째는 대기가 아님'과 같은 뜻). 남는 패는 버린다고 친다.
    /// 색마다 (몸통 수 0~4 × 머리 0~1) 열 칸의 최소 비용 표 — 파레토 후보 전부 — 를 만들고 배낭 합으로 합친다(UX:268).
    /// 색마다 최선 하나만 골라 합치면 머리를 두 색이 서로 쓰려는 손에서 틀린다(시험 MahjongHandTests 의 기준선).
    /// counts 가 34칸이 아니거나 melds 가 0~4 밖이면 8(가장 먼 값)을 돌려준다.
    package static func shanten(_ counts: [Int], melds: Int) -> Int {
        guard counts.count == 34, (0...4).contains(melds) else { return 8 }
        var acc = ShantenTable.identity
        for s in 0..<3 {
            acc = ShantenTable.knap(acc, ShantenTable.suitCost(counts, from: s * 9))
        }
        for k in 27..<34 {
            acc = ShantenTable.knap(acc, ShantenTable.honorCost(counts[k]))
        }
        var best = acc[(4 - melds) * 2 + 1] - 1
        if melds == 0 {
            var pairs = 0, kinds = 0
            for x in counts {
                if x >= 2 { pairs += 1 }
                if x >= 1 { kinds += 1 }
            }
            let chiitoi = 6 - pairs + max(0, 7 - kinds)
            var yaochuKinds = 0, yaochuPair = false
            for k in MahjongTiles.yaochu {
                if counts[k] >= 1 { yaochuKinds += 1 }
                if counts[k] >= 2 { yaochuPair = true }
            }
            let kokushi = 13 - yaochuKinds - (yaochuPair ? 1 : 0)
            best = min(best, chiitoi, kokushi)
        }
        return best
    }

    // MARK: - 내부

    /// MJ-22-2 서로 다른 7쌍(4장을 2쌍으로 치지 않음).
    static func isChiitoi(_ c: [Int]) -> Bool {
        c.reduce(0, +) == 14 && c.filter { $0 == 2 }.count == 7
    }

    /// MJ-22-3 요구패 13종 1장씩 + 그중 하나 1장 더.
    static func isKokushi(_ c: [Int]) -> Bool {
        guard c.reduce(0, +) == 14 else { return false }
        let yaochu = MahjongTiles.yaochu
        return yaochu.allSatisfy { c[$0] >= 1 } && yaochu.reduce(0) { $0 + c[$1] } == 14
    }

    /// 표준형 분해가 하나라도 있는가(reference `_decompose` 의 존재 판정 꼴). c 는 호출 뒤 원래대로 돌아온다.
    static func decomposes(_ c: inout [Int], need: Int, havePair: Bool, start: Int) -> Bool {
        var i = start
        while i < 34 && c[i] == 0 { i += 1 }
        if i == 34 { return need == 0 && havePair }
        if !havePair && c[i] >= 2 {
            c[i] -= 2
            let ok = decomposes(&c, need: need, havePair: true, start: i)
            c[i] += 2
            if ok { return true }
        }
        if need > 0 && c[i] >= 3 {
            c[i] -= 3
            let ok = decomposes(&c, need: need - 1, havePair: havePair, start: i)
            c[i] += 3
            if ok { return true }
        }
        if need > 0 && i < 27 && i % 9 <= 6 && c[i + 1] > 0 && c[i + 2] > 0 {
            c[i] -= 1; c[i + 1] -= 1; c[i + 2] -= 1
            let ok = decomposes(&c, need: need - 1, havePair: havePair, start: i)
            c[i] += 1; c[i + 1] += 1; c[i + 2] += 1
            if ok { return true }
        }
        return false
    }
}

/// 샹텐 비용 표(reference `_suit_cost`·`_honor_cost`·`_knap`). 표 = 10칸 `[몸통 수 m × 2 + 머리 수 p]` → 더 들일 최소 장수(없으면 `inf`).
nonisolated enum ShantenTable {
    static let inf = 99

    /// 아무 패도 없을 때의 합 단위(몸통 0·머리 0 = 0).
    static let identity: [Int] = [0, inf, inf, inf, inf, inf, inf, inf, inf, inf]

    /// 두 표의 배낭 합 — m1 + m2 ≤ 4, p1 + p2 ≤ 1 에서 비용의 최소.
    static func knap(_ a: [Int], _ b: [Int]) -> [Int] {
        var out = [Int](repeating: inf, count: 10)
        for m1 in 0...4 {
            for p1 in 0...1 {
                let x = a[m1 * 2 + p1]
                if x >= inf { continue }
                for m2 in 0...(4 - m1) {
                    for p2 in 0...(1 - p1) {
                        let v = x + b[m2 * 2 + p2]
                        let i = (m1 + m2) * 2 + p1 + p2
                        if v < out[i] { out[i] = v }
                    }
                }
            }
        }
        return out
    }

    /// 자패 한 종류: 커쯔 하나(3 − h) 또는 머리 하나(2 − h). 같은 자패로 커쯔 + 머리(5장)는 없다.
    static func honorCost(_ h: Int) -> [Int] {
        var t = [Int](repeating: inf, count: 10)
        t[0] = 0
        t[2] = max(0, 3 - h)
        t[1] = max(0, 2 - h)
        return t
    }

    /// 한 색(9칸, counts[start..<start+9])의 비용 표. 같은 9칸 장수는 같은 표라 기억해 둔다(봇이 한 결정에 수천 번 부른다).
    static func suitCost(_ counts: [Int], from start: Int) -> [Int] {
        var have = [Int](repeating: 0, count: 9)
        var key = 0
        for i in 0..<9 {
            let h = min(max(counts[start + i], 0), 4)   // 한 종류에 필요한 장수는 4 이하라 4장 넘게 쥔 것은 4와 같다
            have[i] = h
            key = key * 5 + h
        }
        let code = key
        if let hit = memo.withLock({ $0[code] }) { return hit }
        let table = suitCostUncached(have)
        memo.withLock { cache in
            if cache.count >= 200_000 { cache.removeAll(keepingCapacity: true) }
            cache[code] = table
        }
        return table
    }

    private static let memo = OSAllocatedUnfairLock<[Int: [Int]]>(initialState: [:])

    /// 상태 (s1 = i−1 에서 시작한 순쯔 수, s2 = i−2 에서 시작한 순쯔 수, 몸통 수 m, 머리 수 p) → 최소 비용을 9칸 앞으로 민다.
    /// 칸 i 에서 순쯔 st 개(i ≤ 6 만)·커쯔 tr(0/1)·머리 pr(0/1)를 새로 시작하면 그 종류에 드는 장수 need = st + s1 + s2 + 3tr + 2pr ≤ 4,
    /// 비용 += max(0, need − 가진 장수). 끝에서 s1 = s2 = 0 인 상태만 센다. 상태 번호 = ((s1 * 5 + s2) * 5 + m) * 2 + p (250칸).
    /// 옮김(상태 → 다음 상태, need)은 가진 장수와 무관하므로 미리 펼쳐 두고(`Edges`), 닿은 상태의 옮김만 돈다.
    static func suitCostUncached(_ have: [Int]) -> [Int] {
        var cur = [Int](repeating: inf, count: 250)
        var nxt = [Int](repeating: inf, count: 250)
        cur[0] = 0
        for i in 0..<9 {
            let e = i <= 6 ? edgesWithSeq : edgesNoSeq
            let h = have[i]
            cur.withUnsafeBufferPointer { a in
                nxt.withUnsafeMutableBufferPointer { b in
                    e.start.withUnsafeBufferPointer { start in
                        e.to.withUnsafeBufferPointer { to in
                            e.need.withUnsafeBufferPointer { need in
                                var j = 0
                                while j < 250 { b[j] = inf; j += 1 }
                                var from = 0
                                while from < 250 {
                                    let c = a[from]
                                    if c < inf {
                                        var k = start[from]
                                        let end = start[from + 1]
                                        while k < end {
                                            let d = need[k] - h
                                            let nc = d > 0 ? c + d : c
                                            let t = to[k]
                                            if nc < b[t] { b[t] = nc }
                                            k += 1
                                        }
                                    }
                                    from += 1
                                }
                            }
                        }
                    }
                }
            }
            swap(&cur, &nxt)
        }
        return Array(cur[0..<10])   // s1 = s2 = 0 인 상태 = 앞쪽 10칸(m * 2 + p)
    }

    /// 한 칸의 옮김 목록. start[from] ..< start[from + 1] 이 그 상태의 옮김.
    struct Edges: Sendable {
        let start: [Int]
        let to: [Int]
        let need: [Int]
    }

    static let edgesWithSeq = makeEdges(stMax: 4)
    static let edgesNoSeq = makeEdges(stMax: 0)

    static func makeEdges(stMax: Int) -> Edges {
        var start: [Int] = [], to: [Int] = [], need: [Int] = []
        for from in 0..<250 {
            start.append(to.count)
            let p = from % 2, m = (from / 2) % 5, s2 = (from / 10) % 5, s1 = from / 50
            if s1 + s2 > 4 { continue }
            for st in 0...stMax where st + s1 + s2 <= 4 && m + st <= 4 {
                for tr in 0...1 where m + st + tr <= 4 {
                    for pr in 0...(1 - p) {
                        let n = st + s1 + s2 + 3 * tr + 2 * pr
                        if n > 4 { continue }
                        to.append(((st * 5 + s1) * 5 + m + st + tr) * 2 + p + pr)
                        need.append(n)
                    }
                }
            }
        }
        start.append(to.count)
        return Edges(start: start, to: to, need: need)
    }
}
