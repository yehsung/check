import Foundation

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
    /// 표준형·치또이·국사 중 작은 값(치또이·국사는 울기 없을 때만). 색마다 파레토 후보를 합친다(UX:268).
    // R2 가 채운다 — 지금은 화료 꼴이면 −1, 대기가 있으면 0, 아니면 8(임시: 봇·보조가 쓰기 전에 코퍼스로 채운다).
    package static func shanten(_ counts: [Int], melds: Int) -> Int {
        guard counts.count == 34 else { return 8 }
        let total = counts.reduce(0, +)
        if total % 3 == 2 && isComplete(counts, melds: melds) { return -1 }
        if total % 3 == 1 && !waits(counts, melds: melds).isEmpty { return 0 }
        return 8
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
