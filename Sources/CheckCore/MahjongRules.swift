import Foundation

// 아잉 마작 규칙 — 울기·리치·유국·정산·국 끝·등수·루비·시간 초과(MJ-14~MJ-21 · MJ-24~MJ-29 · MJ-41~MJ-55).
// 직접 작성, 외부 판정 코드 없음 — 정본 rules.md MJ-nn, 대조 reference.py(이름 대응은 SPEC §2.1 표).
//
// 이 파일의 타입 가운데 `MahjongFormat`·`MahjongDecision` 은 판 진행(엔진)·와이어·스토어가 같이 쓴다. §4.1 서명
// (`advance(format:)`·`timeoutAction(_:drawn:)`)이 이 둘을 받으므로 규칙 표면(R1)이 먼저 정의한다 — 다른 갈래는 다시 선언하지 않는다.
// 와이어 원문은 `MahjongDecision` 의 열린 어휘 칸(window_kind·answered)을 원문 문자열로 둔다(SPEC §4.1 끝, CC-07).

/// 판 길이. 와이어 `format` 값 그대로(엔진·화면용 — 와이어 디코드는 원문 문자열, §4.4·CC-07). 둘 다 남입·서입 연장 포함(DEC:10·14).
package nonisolated enum MahjongFormat: String, CaseIterable, Codable, Sendable { case tonpuu, hanchan }

/// 울기 창에서 고를 수 있는 것(와이어 DECISION(울기)의 선택지 이름). 대명깡은 `minkan`.
package nonisolated enum MahjongClaimKind: String, Codable, Sendable, CaseIterable {
    case ron, pon, minkan, chi
}

/// 울기 창에서 한 자리의 답(와이어 `answered` 값). 패 조합은 판 진행이 따로 쥔다 — 창 해결은 종류만 본다.
package nonisolated enum MahjongClaimAnswer: String, Codable, Sendable, CaseIterable {
    case ron, pon, minkan, chi, pass
}

/// 울기 창 해결(reference `resolve_claims`). 우선순위 론 > 퐁·대명깡 > 치(MJ-17), 론은 모두 화료(MJ-25), 치는 하가만(MJ-14).
package nonisolated enum MahjongClaimResolution: Equatable, Sendable {
    /// 더 높은 우선순위의 답을 아직 기다린다.
    case wait
    /// 아무도 울지 않고 닫힘(reference action 'none').
    case none
    /// 론 — 화료 자리들, 방총자 다음 차례부터의 순서.
    case ron(seats: [Int])
    /// 퐁·대명깡·치 — 한 자리.
    case claim(MahjongClaimKind, seat: Int)
}

/// 책임 지불(MJ-42) — 대삼원·대사희를 확정시킨 자리. 와이어 `pao{seat, yaku}`.
package nonisolated struct MahjongPao: Equatable, Hashable, Sendable, Codable {
    package let seat: Int
    /// `.daisangen` 또는 `.daisuushii`.
    package let yaku: MahjongYaku

    package init(seat: Int, yaku: MahjongYaku) {
        self.seat = seat
        self.yaku = yaku
    }
}

/// 국 끝 모양(reference `advance` 의 outcome 값 그대로).
package nonisolated enum MahjongHandOutcome: String, Codable, Sendable, CaseIterable {
    case dealerWin = "dealer_win", childWin = "child_win"
    case drawDealerTenpai = "draw_dealer_tenpai", drawDealerNoten = "draw_dealer_noten"
    case abortive
}

/// 국 끝 처리 결과 = reference `advance` 반환 `{end, reason, next{round, hand, honba}, extension}`.
package nonisolated struct MahjongAdvance: Equatable, Sendable, Codable {
    /// 판이 끝났는가.
    package let end: Bool
    /// 끝난 까닭: tobi · agari_yame · tenpai_yame · target_reached · max_round. 계속이면 nil.
    package let reason: String?
    /// 다음 국. 끝이면 nil.
    package let next: Next?
    /// 다음 국이 연장(남입·서입)의 첫 국으로 들어가는가(reference `extension` 키 — 없으면 false).
    package let isExtension: Bool

    package nonisolated struct Next: Equatable, Sendable, Codable {
        /// 0 = 동 · 1 = 남 · 2 = 서.
        package let round: Int
        /// 0~3, 친 자리 = hand.
        package let hand: Int
        package let honba: Int

        package init(round: Int, hand: Int, honba: Int) {
            self.round = round
            self.hand = hand
            self.honba = honba
        }
    }

    package init(end: Bool, reason: String? = nil, next: Next? = nil, isExtension: Bool = false) {
        self.end = end
        self.reason = reason
        self.next = next
        self.isExtension = isExtension
    }

    private enum CodingKeys: String, CodingKey {
        case end, reason, next
        case isExtension = "extension"
    }

    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            end: try c.decode(Bool.self, forKey: .end),
            reason: try c.decodeIfPresent(String.self, forKey: .reason),
            next: try c.decodeIfPresent(Next.self, forKey: .next),
            isExtension: try c.decodeIfPresent(Bool.self, forKey: .isExtension) ?? false
        )
    }
}

/// 지금 내 몫 결정 = 와이어 `my_decision`(SPEC §3.6 DECISION) — 차례·울기 두 갈래. 서버 디코드와 판 진행(연습판) 생성이 같은 타입.
/// Codable: `kind` 칸("turn"|"call") + 그 갈래의 칸들이 한 객체에 나란히(키는 카멜 — 인코더·디코더가 스네이크로 바꾼다).
/// 시각은 epoch ms `Double`, 패는 id. 열린 어휘 칸(`windowKind`·`answered`)은 원문 문자열이다(CC-07).
/// 모르는 `kind` 는 디코드 실패다 — 상태 전체가 실패하지 않게 감싸는 것은 와이어 쪽 몫.
package nonisolated enum MahjongDecision: Equatable, Hashable, Sendable, Codable {
    case turn(Turn)
    case call(Call)

    /// DECISION(차례) — 쯔모 뒤·울기 뒤·영상 뒤 내 차례.
    package nonisolated struct Turn: Equatable, Hashable, Sendable, Codable {
        package var seq: Int
        /// 결정 정체성·낡음 판정 눈금(CS-02).
        package var decisionSeq: Int
        package var startedMs: Double
        package var deadlineMs: Double
        /// 리치 중일 때 시작 + 멈춤(그 전 버림은 too_early). 아니면 nil.
        package var notBeforeMs: Double?
        package var bankMs: Int
        /// 버릴 수 있는 패 id.
        package var discard: [MahjongTile]
        /// 리치 선언패 id(같은 종류 id 모두 — CS-24). 못 하면 [].
        package var riichi: [MahjongTile]
        package var tsumo: Bool
        /// 암깡 후보(4장 id 묶음).
        package var ankan: [[MahjongTile]]
        /// 가깡 후보(더할 패 id).
        package var kakan: [MahjongTile]
        package var kyuushu: Bool

        package init(
            seq: Int, decisionSeq: Int, startedMs: Double, deadlineMs: Double, notBeforeMs: Double? = nil, bankMs: Int,
            discard: [MahjongTile], riichi: [MahjongTile] = [], tsumo: Bool = false, ankan: [[MahjongTile]] = [],
            kakan: [MahjongTile] = [], kyuushu: Bool = false
        ) {
            self.seq = seq
            self.decisionSeq = decisionSeq
            self.startedMs = startedMs
            self.deadlineMs = deadlineMs
            self.notBeforeMs = notBeforeMs
            self.bankMs = bankMs
            self.discard = discard
            self.riichi = riichi
            self.tsumo = tsumo
            self.ankan = ankan
            self.kakan = kakan
            self.kyuushu = kyuushu
        }
    }

    /// DECISION(울기) — 남의 버림·가깡·암깡에 대한 창.
    package nonisolated struct Call: Equatable, Hashable, Sendable, Codable {
        package var windowId: Int
        /// "discard" | "kakan" | "ankan"(원문 문자열, CC-07).
        package var windowKind: String
        package var tile: MahjongTile
        package var fromSeat: Int
        package var startedMs: Double
        package var deadlineMs: Double
        package var bankMs: Int
        package var ron: Bool
        /// 퐁 후보(손에서 낼 2장 id).
        package var pon: [[MahjongTile]]
        /// 대명깡 후보(손에서 낼 3장 id).
        package var minkan: [[MahjongTile]]
        /// 치 후보(손에서 낼 2장 id).
        package var chi: [[MahjongTile]]
        /// 이미 낸 답 "ron"|"pon"|"minkan"|"chi"|"pass"(원문 문자열). 아직이면 nil.
        package var answered: String?

        package init(
            windowId: Int, windowKind: String, tile: MahjongTile, fromSeat: Int, startedMs: Double, deadlineMs: Double,
            bankMs: Int, ron: Bool = false, pon: [[MahjongTile]] = [], minkan: [[MahjongTile]] = [],
            chi: [[MahjongTile]] = [], answered: String? = nil
        ) {
            self.windowId = windowId
            self.windowKind = windowKind
            self.tile = tile
            self.fromSeat = fromSeat
            self.startedMs = startedMs
            self.deadlineMs = deadlineMs
            self.bankMs = bankMs
            self.ron = ron
            self.pon = pon
            self.minkan = minkan
            self.chi = chi
            self.answered = answered
        }
    }

    private enum KindKey: String, CodingKey { case kind }

    package init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: KindKey.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "turn": self = .turn(try Turn(from: decoder))
        case "call": self = .call(try Call(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "모르는 결정 kind")
        }
    }

    package func encode(to encoder: any Encoder) throws {
        switch self {
        case .turn(let turn): try turn.encode(to: encoder)
        case .call(let call): try call.encode(to: encoder)
        }
        var c = encoder.container(keyedBy: KindKey.self)
        try c.encode(kind, forKey: .kind)
    }

    /// 와이어 kind 글자 "turn" | "call".
    package var kind: String {
        switch self {
        case .turn: "turn"
        case .call: "call"
        }
    }
}

/// 시간 초과 때 대신 둘 것(MJ-54, SPEC §2.3 K-1).
package nonisolated enum MahjongTimeoutAction: Equatable, Sendable {
    /// 쯔모기리(방금 뽑은 패) 또는 허용 패 가운데 id 가 가장 큰 것(정렬 손패 오른쪽 끝).
    case discard(MahjongTile)
    /// 쯔모 화료(`MahjongRules.timeoutAutoWin` 이 켜져 있고 쯔모 선택지가 있을 때).
    case tsumo
    /// 론(`timeoutAutoWin` 이 켜져 있고 론 선택지가 있을 때).
    case ron
    /// 넘김 — 치·퐁·깡은 하지 않는다.
    case pass
}

/// 후리텐 세 가지(MJ-24) — 한 사람 몫. reference `Furiten` 그대로. 종류(0~33)로 판정한다.
package nonisolated struct MahjongFuriten: Equatable, Sendable {
    /// 와이어 `my_furiten` 값.
    package nonisolated enum Kind: String, Codable, Sendable, CaseIterable { case discard, temporary, riichi }

    /// 내가 버린 패 종류(남이 울어 가도 남긴다).
    package private(set) var discards: Set<Int> = []
    /// 동순 후리텐.
    package private(set) var temporary = false
    /// 리치했는가.
    package private(set) var riichi = false
    /// 리치 후 후리텐(국 끝까지).
    package private(set) var riichiFuriten = false

    package init() {}

    /// 내가 버린 패 종류. 가깡 패는 부르지 않는다.
    package mutating func ownDiscard(_ kind: Int) { discards.insert(kind) }

    package mutating func declareRiichi() { riichi = true }

    /// 살아 있는 산에서 쯔모 → 동순 후리텐 풀림. 영상 쯔모·치·퐁·깡으로는 안 풀린다(MJ-24-2).
    package mutating func drawLive() { temporary = false }

    /// 내 화료패(창깡 포함, 역 없어 못 론한 것 포함 — rules C-05 기본안)가 나왔는데 론하지 않음.
    package mutating func missed() {
        temporary = true
        if riichi { riichiFuriten = true }
    }

    /// 지금 걸린 후리텐(와이어 순서 discard → temporary → riichi).
    package func kinds(_ waitKinds: [Int]) -> [Kind] {
        var out: [Kind] = []
        if waitKinds.contains(where: { discards.contains($0) }) { out.append(.discard) }
        if temporary { out.append(.temporary) }
        if riichiFuriten { out.append(.riichi) }
        return out
    }

    /// 론할 수 있는가(후리텐 없음).
    package func canRon(_ waitKinds: [Int]) -> Bool { kinds(waitKinds).isEmpty }
}

/// 깡도라 여는 때(MJ-11, rules C-02·C-03 기본안) — reference `DoraTimer`. 암깡 = 즉시, 대명깡·가깡 = 그 사람 타패 때(또는 다음 깡 선언 직전).
package nonisolated struct MahjongDoraTimer: Equatable, Sendable {
    /// 지금 열린 표시패 수(표 도라 포함).
    package var open: Int
    /// 타패 때 열 표시패 수.
    package var pending: Int

    package init(open: Int = 1, pending: Int = 0) {
        self.open = open
        self.pending = pending
    }

    /// 깡 성립(가깡은 창깡 확인이 끝난 뒤). 앞 명깡·가깡의 표시패는 새 깡 선언 직전에 연다.
    package mutating func kan(_ type: MahjongMeldType) {
        flush()
        if type == .ankan { open += 1 } else { pending += 1 }
    }

    /// 타패.
    package mutating func discard() { flush() }

    private mutating func flush() {
        open += pending
        pending = 0
    }
}

/// 울기·리치·유국·정산·국 끝·등수·루비·시간 초과 판정(SQL `mahjong_*` 쌍둥이 — SPEC §2.1 표).
package nonisolated enum MahjongRules {
    /// = SQL `mahjong_timeout_auto_win()`(SPEC §2.3 K-1, v1.0.1) — 시간 초과 때 론·쯔모 선택지가 있으면 자동 화료.
    package static let timeoutAutoWin = true

    /// = SQL `mahjong_ranking_min_games()`(v1.0.2 카드 ⑤ "평균 등수(10판 이상 한 사람만)") — 이 판 수 이상이어야 순위에 선다.
    package static let rankingMinGames = 10

    /// MJ-18 쿠이카에 금지: 울고 그 차례에 버릴 수 없는 종류(현물 + 치 양끝 스지). 종류 오름차순.
    package static func kuikaeForbidden(call: MahjongMeldType, called: MahjongTile, fromHand: [MahjongTile]) -> [Int] {
        let t = called.kind
        var out: Set<Int> = [t]
        if call == .chi, t < 27 {
            let lo = (fromHand.map(\.kind) + [t]).min() ?? t
            let number = t % 9 + 1
            if t == lo && number + 3 <= 9 {
                out.insert(t + 3)
            } else if t == lo + 2 && number - 3 >= 1 {
                out.insert(t - 3)
            }
        }
        return out.sorted()
    }

    /// MJ-18 울고 나서 버릴 수 있는 패가 하나도 없으면 그 울기는 선택지가 아니다.
    package static func callAllowed(call: MahjongMeldType, called: MahjongTile, fromHand: [MahjongTile], closedAfter: [MahjongTile]) -> Bool {
        let bad = Set(kuikaeForbidden(call: call, called: called, fromHand: fromHand))
        return closedAfter.contains { !bad.contains($0.kind) }
    }

    /// MJ-17 울기 창 해결. eligible = 자리 → 고를 수 있는 것, answers = 자리 → 낸 답(아직 답 없으면 빠짐).
    /// 하가가 아닌 자리의 치 선택지는 무시한다(MJ-14 — reference 는 예외).
    package static func resolveClaims(discarder: Int, eligible: [Int: [MahjongClaimKind]], answers: [Int: MahjongClaimAnswer]) -> MahjongClaimResolution {
        let order = [1, 2, 3].map { (discarder + $0) % 4 }
        let next = (discarder + 1) % 4
        func level(_ kind: MahjongClaimKind) -> Int {
            switch kind {
            case .ron: 3
            case .pon, .minkan: 2
            case .chi: 1
            }
        }
        func answerLevel(_ answer: MahjongClaimAnswer) -> Int {
            switch answer {
            case .ron: 3
            case .pon, .minkan: 2
            case .chi: 1
            case .pass: 0
            }
        }
        func kinds(_ seat: Int) -> [MahjongClaimKind] {
            (eligible[seat] ?? []).filter { $0 != .chi || seat == next }
        }
        for lv in [3, 2, 1] {
            let cands = order.filter { seat in kinds(seat).contains { level($0) == lv } }
            if cands.isEmpty { continue }
            if lv == 3 {
                if cands.contains(where: { answers[$0] == nil }) { return .wait }
                let rons = order.filter { answers[$0] == .ron }
                if !rons.isEmpty { return .ron(seats: rons) }
                continue
            }
            if let seat = cands.first(where: { answers[$0].map(answerLevel) == lv }), let answer = answers[seat] {
                let kind: MahjongClaimKind = switch answer {
                case .pon: .pon
                case .minkan: .minkan
                default: .chi
                }
                return .claim(kind, seat: seat)
            }
            if cands.contains(where: { answers[$0] == nil }) { return .wait }
        }
        return .none
    }

    /// MJ-27 리치할 수 있으면 버려서 텐파이가 되는 패 **종류** 목록(오름차순). 못 하면 [].
    /// (판 진행이 `turn_options.riichi` 에 담을 때는 손의 그 종류 id 모두로 펼친다, CS-24.)
    package static func riichiDiscards(closed14: [MahjongTile], ankans: Int, score: Int, liveLeft: Int, menzen: Bool, already: Bool) -> [Int] {
        guard !already, menzen, score >= 1000, liveLeft >= 4 else { return [] }
        var counts = MahjongTiles.counts34(closed14)
        var out: [Int] = []
        for k in 0..<34 where counts[k] > 0 {
            counts[k] -= 1
            if !MahjongHand.waits(counts, melds: ankans).isEmpty { out.append(k) }
            counts[k] += 1
        }
        return out
    }

    /// MJ-29 리치 뒤 암깡: 방금 쯔모한 패가 4번째(오쿠리깡 금지) + 깡 전후 대기 종류 집합이 같음(rules C-07).
    /// closed13 = 쯔모 전 13장(리치 중 손), kanKind = 깡할 종류(nil = 뽑은 패 종류), melds = 손 밖 몸통 수.
    package static func riichiAnkanOK(closed13: [MahjongTile], drawn: MahjongTile, kanKind: Int?, melds: Int) -> Bool {
        let k = kanKind ?? drawn.kind
        guard k == drawn.kind else { return false }
        var counts = MahjongTiles.counts34(closed13)
        guard counts[k] == 3 else { return false }
        let before = MahjongHand.waits(counts, melds: melds)
        counts[k] = 0
        let after = MahjongHand.waits(counts, melds: melds + 1)
        return !before.isEmpty && Set(before) == Set(after)
    }

    /// MJ-45-1 구종구패: 첫 차례·울기 없음·요구패 종류 9 이상.
    package static func kyuushuOK(_ hand14: [MahjongTile], firstTurnUninterrupted: Bool) -> Bool {
        let kinds = Set(hand14.map(\.kind))
        return firstTurnUninterrupted && MahjongTiles.yaochu.filter { kinds.contains($0) }.count >= 9
    }

    /// MJ-45-2 사풍연타: 첫 순 네 사람의 첫 타패가 같은 바람패, 울기 없음.
    package static func suufonRenda(firstDiscardKinds: [Int], anyCall: Bool) -> Bool {
        guard !anyCall, firstDiscardKinds.count == 4 else { return false }
        let kinds = Set(firstDiscardKinds)
        guard kinds.count == 1, let k = kinds.first else { return false }
        return MahjongTiles.winds.contains(k)
    }

    /// MJ-45-3 사깡유국: 합계 4번 깡이 2명 이상에게서(한 사람 4번은 계속).
    package static func suukaikan(kanSeats: [Int]) -> Bool {
        kanSeats.count >= 4 && Set(kanSeats).count >= 2
    }

    /// MJ-44 유국만관: 버림패 전부 요구패 + 한 장도 불려 가지 않음.
    package static func nagashiOK(discardKinds: [Int], calledAway: Bool) -> Bool {
        !discardKinds.isEmpty && !calledAway && discardKinds.allSatisfy { MahjongTiles.yaochu.contains($0) }
    }

    /// MJ-43·MJ-44 황패 유국 정산. 유국만관이 하나라도 있으면 노텐벌 대신 만관 쯔모 정산(본장·공탁 없음).
    package static func settleExhaustive(dealer: Int, tenpai: [Bool], nagashi: [Bool]) -> (deltas: [Int], renchan: Bool) {
        guard tenpai.count == 4, nagashi.count == 4, (0...3).contains(dealer) else { return ([0, 0, 0, 0], false) }
        var d = [0, 0, 0, 0]
        if nagashi.contains(true) {
            for s in 0..<4 where nagashi[s] {
                for o in 0..<4 where o != s {
                    let pay = (s == dealer || o == dealer) ? 4000 : 2000
                    d[o] -= pay
                    d[s] += pay
                }
            }
        } else {
            let n = tenpai.filter { $0 }.count
            if n > 0 && n < 4 {
                for s in 0..<4 { d[s] = tenpai[s] ? 3000 / n : -(3000 / (4 - n)) }
            }
        }
        return (d, tenpai[dealer])
    }

    /// MJ-41·MJ-42 화료 하나의 자리별 점수 변화. discarder nil = 쯔모. getsBonus = 본장·공탁을 받는가(MJ-25).
    package static func settleWin(winner: Int, dealer: Int, score: MahjongScore, discarder: Int?, honba: Int, kyoutaku: Int, pao: MahjongPao?, getsBonus: Bool) -> [Int] {
        var d = [0, 0, 0, 0]
        guard (0...3).contains(winner) else { return d }
        let isDealer = winner == dealer
        let hb = getsBonus ? honba : 0
        var paoMult = 0
        if let pao, score.yakuman > 0, score.yaku.contains(where: { $0.yaku == pao.yaku }) {
            paoMult = pao.yaku.yakumanMultiple
        }
        let restMult = score.yakuman - paoMult
        let value = { (mult: Int) in (isDealer ? 48000 : 32000) * mult }
        if let discarder {
            if let pao, paoMult > 0 {
                let pv = value(paoMult)
                if pao.seat == discarder {
                    d[discarder] -= pv
                } else {
                    d[discarder] -= pv / 2
                    d[pao.seat] -= pv / 2
                }
                d[winner] += pv
                if restMult > 0 {
                    let rv = value(restMult)
                    d[discarder] -= rv
                    d[winner] += rv
                }
                d[pao.seat] -= 300 * hb
                d[winner] += 300 * hb
            } else {
                let v = (score.points.ron ?? 0) + 300 * hb
                d[discarder] -= v
                d[winner] += v
            }
        } else if let pao, paoMult > 0 {
            let pv = value(paoMult)
            d[pao.seat] -= pv
            d[winner] += pv
            if restMult > 0 {
                for o in 0..<4 where o != winner {
                    let v = (isDealer || o == dealer) ? 16000 * restMult : 8000 * restMult
                    d[o] -= v
                    d[winner] += v
                }
            }
            d[pao.seat] -= 300 * hb
            d[winner] += 300 * hb
        } else {
            for o in 0..<4 where o != winner {
                var v = score.points.fromEach ?? ((o == dealer ? score.points.fromDealer : score.points.fromChild) ?? 0)
                v += 100 * hb
                d[o] -= v
                d[winner] += v
            }
        }
        if getsBonus { d[winner] += 1000 * kyoutaku }
        return d
    }

    /// MJ-25 동시 론. 본장·공탁은 방총자 다음 차례부터 처음 화료자 한 명만. 친이 화료자에 있으면 연장.
    package static func settleRonMulti(discarder: Int, dealer: Int, wins: [(seat: Int, score: MahjongScore, pao: MahjongPao?)], honba: Int, kyoutaku: Int) -> (deltas: [Int], bonusTo: Int, renchan: Bool) {
        let order = [1, 2, 3].map { (discarder + $0) % 4 }
        let seats = wins.map(\.seat)
        let first = order.first(where: { seats.contains($0) }) ?? (seats.first ?? discarder)
        var total = [0, 0, 0, 0]
        for win in wins {
            let d = settleWin(winner: win.seat, dealer: dealer, score: win.score, discarder: discarder, honba: honba,
                              kyoutaku: kyoutaku, pao: win.pao, getsBonus: win.seat == first)
            for i in 0..<4 { total[i] += d[i] }
        }
        return (total, first, seats.contains(dealer))
    }

    /// MJ-46~MJ-50 국 끝 처리 = reference `advance`. round 0 = 동 · 1 = 남 · 2 = 서, handNo 0~3(친 자리 = handNo).
    /// scores = 이 국 정산 뒤 점수(공탁 제외).
    package static func advance(format: MahjongFormat, round: Int, handNo: Int, honba: Int, scores: [Int], outcome: MahjongHandOutcome) -> MahjongAdvance {
        let target = 30000
        if scores.contains(where: { $0 < 0 }) { return MahjongAdvance(end: true, reason: "tobi") }
        let renchan = outcome == .dealerWin || outcome == .drawDealerTenpai || outcome == .abortive
        let nextHonba = outcome == .childWin ? 0 : honba + 1
        let lastRound = format == .tonpuu ? 0 : 1
        let maxRound = lastRound + 1
        let dealer = handNo
        let stay = MahjongAdvance(end: false, next: .init(round: round, hand: handNo, honba: nextHonba))
        let (nr, nh) = handNo == 3 ? (round + 1, 0) : (round, handNo + 1)
        if (round == lastRound && handNo == 3) || round > lastRound {
            if renchan && outcome != .abortive {
                if scores.count == 4, rankOrder(scores).first == dealer, scores[dealer] >= target {
                    return MahjongAdvance(end: true, reason: outcome == .dealerWin ? "agari_yame" : "tenpai_yame")
                }
                return stay
            }
            if renchan { return stay }
            if (scores.max() ?? 0) >= target { return MahjongAdvance(end: true, reason: "target_reached") }
            if round == maxRound && handNo == 3 { return MahjongAdvance(end: true, reason: "max_round") }
            return MahjongAdvance(end: false, next: .init(round: nr, hand: nh, honba: nextHonba),
                                 isExtension: nr > lastRound && handNo == 3)
        }
        if renchan { return stay }
        return MahjongAdvance(end: false, next: .init(round: nr, hand: nh, honba: nextHonba))
    }

    /// MJ-51 등수와 남은 공탁(1위에게). order = 1위부터 자리 번호, ranks = 자리마다 등수(1~4), finalScores = 공탁을 더한 점수.
    /// 같은 점수는 기가(0번)에 가까운 자리가 위(DEC:15).
    package static func finalResult(scores: [Int], kyoutaku: Int) -> (order: [Int], ranks: [Int], finalScores: [Int]) {
        guard scores.count == 4 else { return ([], [], scores) }
        let order = rankOrder(scores)
        var final = scores
        final[order[0]] += 1000 * kyoutaku
        var ranks = [0, 0, 0, 0]
        for (i, seat) in order.enumerated() { ranks[seat] = i + 1 }
        return (order, ranks, final)
    }

    /// 루비 분배 = SQL `mahjong_payouts(stake)` — 등수 1~4 의 지급 `[3N, N, 0, 0]`(카드 ② "1위 +2N · 2위 본전 · 3·4위 −N").
    package static func payouts(stake: Int) -> [Int] {
        [3 * stake, stake, 0, 0]
    }

    /// MJ-54 시간 초과 동작(SPEC §2.3 K-1): 차례 — 쯔모 선택지가 있으면 쯔모(timeoutAutoWin), 아니면 방금 뽑은 패가 버릴 수 있으면 그 패,
    /// 아니면 허용 패 가운데 id 가 가장 큰 것. 암깡·가깡·리치·구종구패는 하지 않는다. 울기 — 론 선택지가 있으면 론(timeoutAutoWin), 아니면 넘김.
    /// 자리 비움 자리의 화료 끄기(rules C-18)는 판 진행이 한다.
    package static func timeoutAction(_ decision: MahjongDecision, drawn: MahjongTile?) -> MahjongTimeoutAction {
        switch decision {
        case .turn(let turn):
            if timeoutAutoWin && turn.tsumo { return .tsumo }
            if let drawn, turn.discard.contains(drawn) { return .discard(drawn) }
            if let last = turn.discard.max() { return .discard(last) }
            return .pass
        case .call(let call):
            return timeoutAutoWin && call.ron ? .ron : .pass
        }
    }

    // MARK: - 내부

    /// MJ-51 점수 높은 순, 같으면 기가(0번)에 가까운 자리 먼저. reference `rank_order`.
    static func rankOrder(_ scores: [Int]) -> [Int] {
        scores.indices.sorted { a, b in scores[a] != scores[b] ? scores[a] > scores[b] : a < b }
    }
}

extension MahjongYaku {
    /// 역만 배수(reference `YAKUMAN` 둘째 칸). 일반 역은 0.
    var yakumanMultiple: Int {
        switch self {
        case .kokushi13, .suuankouTanki, .daisuushii, .junseiChuuren: 2
        case .heavenly, .earthly, .kokushi, .suuankou, .daisangen, .shousuushii, .tsuuiisou, .ryuuiisou,
             .chinroutou, .suukantsu, .chuuren: 1
        default: 0
        }
    }
}
