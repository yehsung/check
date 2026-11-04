import Foundation

// 아잉 마작 연습 봇 — 위협 판단 · 안전패(현물) · 패별 위험도(SPEC §4.3 · UX §3.3.3~3.3.4).
// 직접 작성, 외부 엔진·가중치 없음 — 근거는 공개 논문·일반 전략 서술(UX §3.1)과 rules.md MJ-24(후리텐)뿐이다.
//
// 입력은 그 자리 시야(`MahjongStatePayload` — 엔진 `payload(for: 봇 자리)` · 서버 state 와 같은 모양)뿐이다. 남의 손·패산은 형에 없다.
// 보이는 장수는 `MahjongVisibleTiles.counts` 한 곳만 쓴다(울린 패를 강에서 두 번 세지 않는다, CC-08).
//
// 위험도 표(UX §3.3.4 — 비율만 뜻이 있는 설계 상수):
//   현물·남은 장수 0 인 자패 0 · 노찬스 1·9 · 3장 보인 자패 1 · 스지 1·9 3 · 2장 보인 자패 3 · 노찬스 2~8 · 스지 2·8 5 ·
//   1장 보인 자패 6 · 원찬스 · 스지 3·7 7 · 안 보인 자패 · 온전한 스지 4~6 8 · 무스지 1·9 10 · 반스지 4~6 11 ·
//   무스지 2·8 13 · 무스지 3·7 15 · 무스지 4~6 18 · 도라 배율 중장패 ×1.5 · 노두패·자패 ×1.8 · 적5 ×1.5.
// 현물(MJ-24 후리텐에서 나온다): 그 상대의 강 전부(울려 간 패 포함) · 그 상대의 리치 선언 뒤 누가 버린 패 · 그 상대가 마지막으로
// 버리거나 뽑은 뒤에 나온 패(동순). 사건 꼬리(`events` — 최대 80)에 없는 옛 버림은 모르는 것으로 친다(보수적으로 덜 안전).

/// 위협 하나(UX §3.3.3). 리치 = 완전 위협(가중 1.0), 울음 셋 · 울음 둘 + 역패/도라 = 반 위협(0.4).
package nonisolated struct MahjongBotThreat: Equatable, Sendable {
    package let seat: Int
    /// 리치한 상대인가(완전 위협).
    package let riichi: Bool
    /// 위험도 합의 가중치.
    package let weight: Double
    /// 그 상대에게 현물인 종류(0~33).
    package let safeKinds: Set<Int>

    package static let riichiWeight = 1.0
    package static let openWeight = 0.4
}

package nonisolated enum MahjongBotRisk {
    // MARK: - 위험도 표(설계 상수)

    package static let genbutsu = 0.0
    package static let noChanceTerminal = 1.0
    package static let honorThreeSeen = 1.0
    package static let sujiTerminal = 3.0
    package static let honorTwoSeen = 3.0
    package static let noChanceMiddle = 5.0
    package static let sujiTwoEight = 5.0
    package static let honorOneSeen = 6.0
    package static let oneChance = 7.0
    package static let sujiThreeSeven = 7.0
    package static let honorUnseen = 8.0
    package static let sujiMiddle = 8.0
    package static let musujiTerminal = 10.0
    package static let halfSujiMiddle = 11.0
    package static let musujiTwoEight = 13.0
    package static let musujiThreeSeven = 15.0
    package static let musujiMiddle = 18.0
    package static let doraMiddleFactor = 1.5
    package static let doraEdgeFactor = 1.8
    package static let redFactor = 1.5
    /// '위험 높은 패'(반 위협만일 때 피하는 패) 문턱 — 무스지 2·8 이상.
    package static let highDanger = 13.0

    // MARK: - 위협

    /// 시야에서 위협 목록(나는 빼고, 자리 번호 순).
    package static func threats(in view: MahjongStatePayload) -> [MahjongBotThreat] {
        guard let me = view.mySeat else { return [] }
        let doraKinds = Set((view.match?.doraIndicators ?? []).map { MahjongTiles.doraKind(ofIndicator: $0.kind) })
        let roundWind = 27 + (view.match?.round ?? 0) % 4
        let tail = currentHandEvents(view)
        var out: [MahjongBotThreat] = []
        for seat in view.seats ?? [] where seat.seatNo != me {
            let melds = (seat.melds ?? []).compactMap(\.meld)
            let isRiichi = seat.riichi == true
            let open = melds.filter { $0.type != .ankan }
            var weight = 0.0
            if isRiichi {
                weight = MahjongBotThreat.riichiWeight
            } else if open.count >= 3 {
                weight = MahjongBotThreat.openWeight
            } else if open.count >= 2 {
                let seatWind = windKind(seat.wind)
                let yakuhaiShown = melds.contains { m in
                    m.type != .chi && isYakuhai(m.tiles[0].kind, seatWind: seatWind, roundWind: roundWind)
                }
                let doraShown = melds.contains { m in m.tiles.contains { doraKinds.contains($0.kind) || $0.isRed } }
                if yakuhaiShown || doraShown { weight = MahjongBotThreat.openWeight }
            }
            guard weight > 0 else { continue }
            out.append(MahjongBotThreat(
                seat: seat.seatNo, riichi: isRiichi, weight: weight,
                safeKinds: safeKinds(of: seat.seatNo, in: view, tail: tail)
            ))
        }
        return out
    }

    /// 그 자리에게 현물인 종류 — 강 전부 · 리치 선언 뒤 나온 패 · 마지막 버림/쯔모 뒤 나온 패(동순 후리텐).
    package static func safeKinds(of seat: Int, in view: MahjongStatePayload) -> Set<Int> {
        safeKinds(of: seat, in: view, tail: currentHandEvents(view))
    }

    static func safeKinds(of seat: Int, in view: MahjongStatePayload, tail: [MahjongEvent]) -> Set<Int> {
        let row = view.seats?.first { $0.seatNo == seat }
        var safe = Set((row?.discards ?? []).map(\.tile.kind))
        let discards = tail.filter { $0.kind == "discard" && $0.tile != nil }
        if row?.riichi == true {
            if let declared = tail.lastIndex(where: { $0.kind == "discard" && $0.seat == seat && $0.riichi == true }) {
                for e in tail[(declared + 1)...] where e.kind == "discard" { if let t = e.tile { safe.insert(t.kind) } }
            } else {
                // 선언이 꼬리보다 옛날이다 — 꼬리의 버림은 모두 선언 뒤다.
                for e in discards { if let t = e.tile { safe.insert(t.kind) } }
            }
        }
        // 동순: 그 자리가 마지막으로 버리거나 뽑은 뒤에 나온 패.
        if let mark = tail.lastIndex(where: { ($0.kind == "discard" || $0.kind == "draw") && $0.seat == seat }) {
            for e in tail[(mark + 1)...] where e.kind == "discard" { if let t = e.tile { safe.insert(t.kind) } }
        }
        return safe
    }

    /// 사건 꼬리 가운데 이 국 것만(마지막 deal 뒤). 꼬리에 deal 이 없으면 꼬리 전부가 이 국이다(꼬리는 지금까지 이어져 있다).
    static func currentHandEvents(_ view: MahjongStatePayload) -> [MahjongEvent] {
        let events = (view.events ?? []).sorted { $0.seq < $1.seq }
        guard let deal = events.lastIndex(where: { $0.kind == "deal" }) else { return events }
        return Array(events[(deal + 1)...])
    }

    // MARK: - 위험도

    /// 한 상대에 대한 종류 k 의 위험도(도라·적5 배율 전). visible = 34칸 보이는 장수(내 손 포함).
    package static func baseDanger(kind k: Int, safe: Set<Int>, visible: [Int]) -> Double {
        if safe.contains(k) { return genbutsu }
        if k >= 27 {
            switch max(0, 4 - visible[k]) {
            case 0: return genbutsu
            case 1: return honorThreeSeen
            case 2: return honorTwoSeen
            case 3: return honorOneSeen
            default: return honorUnseen
            }
        }
        let base = k - k % 9
        let n = k % 9 + 1
        func seen(_ m: Int) -> Int { (1...9).contains(m) ? visible[base + m - 1] : 0 }
        func gen(_ m: Int) -> Bool { (1...9).contains(m) && safe.contains(base + m - 1) }
        // 양면 꼴 둘: 아래 (n−2, n−1) — n ≥ 4 · 위 (n+1, n+2) — n ≤ 6. 그 꼴을 막는 것: 그 꼴 패가 4장 보임(노찬스) · 스지 현물.
        enum Side { case none, wall, suji, oneChance, open }
        func side(exists: Bool, a: Int, b: Int, suji: Int) -> Side {
            guard exists else { return .none }
            if seen(a) >= 4 || seen(b) >= 4 { return .wall }
            if gen(suji) { return .suji }
            if seen(a) == 3 || seen(b) == 3 { return .oneChance }
            return .open
        }
        let low = side(exists: n >= 4, a: n - 2, b: n - 1, suji: n - 3)
        let high = side(exists: n <= 6, a: n + 1, b: n + 2, suji: n + 3)
        let sides = [low, high].filter { $0 != .none }
        let edge = n == 1 || n == 9
        let twoEight = n == 2 || n == 8
        let threeSeven = n == 3 || n == 7
        if sides.allSatisfy({ $0 == .wall }) { return edge ? noChanceTerminal : noChanceMiddle }
        var best: Double
        switch (edge, twoEight, threeSeven) {
        case (true, _, _): best = musujiTerminal
        case (_, true, _): best = musujiTwoEight
        case (_, _, true): best = musujiThreeSeven
        default: best = musujiMiddle
        }
        if sides.allSatisfy({ $0 == .wall || $0 == .suji }) {
            let suji: Double = edge ? sujiTerminal : twoEight ? sujiTwoEight : threeSeven ? sujiThreeSeven : sujiMiddle
            best = min(best, suji)
        } else if sides.count == 2 && sides.contains(where: { $0 == .wall || $0 == .suji }) && !sides.contains(.oneChance) {
            best = min(best, halfSujiMiddle)
        }
        if sides.allSatisfy({ $0 != .open }) { best = min(best, oneChance) }
        return best
    }

    /// 도라·적5 배율을 곱한 한 상대 위험도.
    package static func danger(tile: MahjongTile, safe: Set<Int>, visible: [Int], doraKinds: Set<Int>) -> Double {
        let k = tile.kind
        var d = baseDanger(kind: k, safe: safe, visible: visible)
        if doraKinds.contains(k) {
            let n = k % 9 + 1
            d *= (k >= 27 || n == 1 || n == 9) ? doraEdgeFactor : doraMiddleFactor
        }
        if tile.isRed { d *= redFactor }
        return d
    }

    /// 위협들에 대한 가중 합(접을 때 고르는 값)과 가장 큰 날 값(반 위협 '위험 높은 패' 판정).
    package static func weighted(tile: MahjongTile, threats: [MahjongBotThreat], visible: [Int], doraKinds: Set<Int>)
        -> (sum: Double, worst: Double) {
        var sum = 0.0, worst = 0.0
        for t in threats {
            let d = danger(tile: tile, safe: t.safeKinds, visible: visible, doraKinds: doraKinds)
            sum += t.weight * d
            worst = max(worst, d)
        }
        return (sum, worst)
    }

    // MARK: - 작은 도우미

    /// 와이어 바람 글자 → 바람패 종류(27~30). 모르면 nil.
    static func windKind(_ letter: String?) -> Int? {
        switch letter {
        case "E": 27
        case "S": 28
        case "W": 29
        case "N": 30
        default: nil
        }
    }

    /// 역패 종류인가 — 삼원패 · 그 자리 바람 · 장풍.
    static func isYakuhai(_ kind: Int, seatWind: Int?, roundWind: Int) -> Bool {
        kind >= 31 || kind == seatWind || kind == roundWind
    }
}
