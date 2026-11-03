import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 규칙 표면(갈래 R1)의 계약 — 이름·서명이 설계서(mj/SPEC.md §2.1 · §4.1)와 같은가.
//
// 판 진행·봇·스토어·화면 갈래가 이 표면 위에 선다. 서명은 **컴파일로** 잰다: 각 함수를 정해진 함수 타입 변수에 담으므로
// 이름표·인자 타입·반환 튜플 이름이 하나라도 바뀌면 이 파일이 컴파일되지 않는다. 값 약속(상수·raw 값·Codable 모양)은
// 실행으로 재고, 각 단언에는 결과가 갈리는 기준선을 같이 둔다(같은 입력이면 영원히 초록).
// 판정 몸통(역·부·샹텐)의 정답은 코퍼스 시험(MahjongScoringCorpusTests 등, R2)이 잰다 — 여기는 표면만.

@Suite("아잉 마작 규칙 표면 계약 — SPEC §2.1·§4.1 서명 · 상수 · 와이어 모양")
struct MahjongContractTests {
    private static func tile(_ id: Int) -> MahjongTile { MahjongTile(id: id)! }

    // 없으면: 다른 갈래가 쓰는 이름표·인자 타입이 조용히 바뀌어 합칠 때 갈래마다 컴파일이 깨진다.
    @Test("§4.1 서명 — 함수 타입 변수에 담겨 컴파일된다")
    func signaturesCompile() {
        let parse: (String) -> [MahjongTile]? = MahjongTiles.parse(_:)
        let counts34: ([MahjongTile]) -> [Int] = MahjongTiles.counts34(_:)
        let doraKind: (Int) -> Int = MahjongTiles.doraKind(ofIndicator:)
        let text: ([Int]) -> String = MahjongTiles.text(kinds:)
        let isComplete: ([Int], Int) -> Bool = MahjongHand.isComplete(_:melds:)
        let waits: ([Int], Int) -> [Int] = MahjongHand.waits(_:melds:)
        let shanten: ([Int], Int) -> Int = MahjongHand.shanten(_:melds:)
        let evaluate: (MahjongWinContext) -> Result<MahjongScore, MahjongInputError> = MahjongScoring.evaluate(_:)
        let scoreOf: (Int, Int, Bool, Bool, Int) -> (base: Int, limit: String, points: MahjongPoints, total: Int) =
            MahjongScoring.scoreOf(han:fu:dealer:tsumo:yakuman:)
        let kuikae: (MahjongMeldType, MahjongTile, [MahjongTile]) -> [Int] = MahjongRules.kuikaeForbidden(call:called:fromHand:)
        let callAllowed: (MahjongMeldType, MahjongTile, [MahjongTile], [MahjongTile]) -> Bool =
            MahjongRules.callAllowed(call:called:fromHand:closedAfter:)
        let resolve: (Int, [Int: [MahjongClaimKind]], [Int: MahjongClaimAnswer]) -> MahjongClaimResolution =
            MahjongRules.resolveClaims(discarder:eligible:answers:)
        let riichi: ([MahjongTile], Int, Int, Int, Bool, Bool) -> [Int] =
            MahjongRules.riichiDiscards(closed14:ankans:score:liveLeft:menzen:already:)
        let riichiAnkan: ([MahjongTile], MahjongTile, Int?, Int) -> Bool = MahjongRules.riichiAnkanOK(closed13:drawn:kanKind:melds:)
        let kyuushu: ([MahjongTile], Bool) -> Bool = MahjongRules.kyuushuOK(_:firstTurnUninterrupted:)
        let suufon: ([Int], Bool) -> Bool = MahjongRules.suufonRenda(firstDiscardKinds:anyCall:)
        let suukaikan: ([Int]) -> Bool = MahjongRules.suukaikan(kanSeats:)
        let nagashi: ([Int], Bool) -> Bool = MahjongRules.nagashiOK(discardKinds:calledAway:)
        let exhaustive: (Int, [Bool], [Bool]) -> (deltas: [Int], renchan: Bool) = MahjongRules.settleExhaustive(dealer:tenpai:nagashi:)
        let settleWin: (Int, Int, MahjongScore, Int?, Int, Int, MahjongPao?, Bool) -> [Int] =
            MahjongRules.settleWin(winner:dealer:score:discarder:honba:kyoutaku:pao:getsBonus:)
        let ronMulti: (Int, Int, [(seat: Int, score: MahjongScore, pao: MahjongPao?)], Int, Int) -> (deltas: [Int], bonusTo: Int, renchan: Bool) =
            MahjongRules.settleRonMulti(discarder:dealer:wins:honba:kyoutaku:)
        let advance: (MahjongFormat, Int, Int, Int, [Int], MahjongHandOutcome) -> MahjongAdvance =
            MahjongRules.advance(format:round:handNo:honba:scores:outcome:)
        let finalResult: ([Int], Int) -> (order: [Int], ranks: [Int], finalScores: [Int]) = MahjongRules.finalResult(scores:kyoutaku:)
        let payouts: (Int) -> [Int] = MahjongRules.payouts(stake:)
        let timeout: (MahjongDecision, MahjongTile?) -> MahjongTimeoutAction = MahjongRules.timeoutAction(_:drawn:)
        let deadline: (Date, Int) -> Date = MahjongClock.deadline(started:bankMs:)
        let charge: (Date, Date, Int) -> (bankLeft: Int, usedMs: Int, timedOut: Bool) = MahjongClock.charge(started:arrived:bankMs:)
        let remaining: (Date, Int, Date) -> (baseLeft: Double, bankLeft: Double) = MahjongClock.remaining(started:bankMs:now:)
        // 값 타입 표면 — 칸 이름·타입.
        let tile = Self.tile(16)
        let _: (Int, Bool, MahjongSuit, Int?, String) = (tile.kind, tile.isRed, tile.suit, tile.number, tile.token)
        let meld = MahjongMeld(type: .pon, tiles: [Self.tile(0), Self.tile(1), Self.tile(2)], called: Self.tile(2), fromSeat: 3)
        let _: (MahjongMeldType, [MahjongTile], MahjongTile?, Int?) = (meld.type, meld.tiles, meld.called, meld.fromSeat)
        var furiten = MahjongFuriten()
        furiten.ownDiscard(3); furiten.declareRiichi(); furiten.drawLive(); furiten.missed()
        let _: ([MahjongFuriten.Kind], Bool) = (furiten.kinds([3]), furiten.canRon([3]))
        var timer = MahjongDoraTimer()
        timer.kan(.minkan); timer.discard()
        let _: (Int, Int) = (timer.open, timer.pending)
        let _: (Bool, Int) = (MahjongRules.timeoutAutoWin, MahjongRules.rankingMinGames)
        let _: (Int, Int, Int) = (MahjongClock.baseMs, MahjongClock.bankFullMs, MahjongClock.graceMs)
        let _: ([MahjongYaku], String) = (MahjongYaku.order, MahjongYaku.heavenly.koreanName)
        let all: [Any] = [parse, counts34, doraKind, text, isComplete, waits, shanten, evaluate, scoreOf, kuikae, callAllowed,
                          resolve, riichi, riichiAnkan, kyuushu, suufon, suukaikan, nagashi, exhaustive, settleWin, ronMulti,
                          advance, finalResult, payouts, timeout, deadline, charge, remaining]
        #expect(all.count == 28, "§2.1 표 + §4.1 함수 28개를 모두 담았다")
    }

    // 없으면: 서버 상수(mahjong_timeout_auto_win · mahjong_ranking_min_games · 5+20+1초)와 클라 짝이 갈려 순위 컷·자동 화료·시계가 어긋난다.
    @Test("상수 — 자동 화료 켜짐(v1.0.1) · 순위 10판(v1.0.2) · 시계 5000/20000/1000ms · 루비 [3N, N, 0, 0]")
    func constants() {
        #expect(MahjongRules.timeoutAutoWin == true)
        #expect(MahjongRules.rankingMinGames == 10)
        #expect(MahjongClock.baseMs == 5_000 && MahjongClock.bankFullMs == 20_000 && MahjongClock.graceMs == 1_000)
        #expect(MahjongRules.payouts(stake: 5) == [15, 5, 0, 0], "카드 ② 판돈 5 → +10 · 0 · −5 · −5 의 지급")
        #expect(MahjongRules.payouts(stake: 3) == [9, 3, 0, 0], "기준선: 판돈이 바뀌면 지급도 바뀐다")
        #expect(MahjongRules.payouts(stake: 10).reduce(0, +) == 40, "네 사람 판돈 합 = 지급 합")
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(MahjongClock.deadline(started: start, bankMs: 20_000) == start.addingTimeInterval(25))
        #expect(MahjongClock.deadline(started: start, bankMs: 0) == start.addingTimeInterval(5), "기준선: 예비 0")
    }

    // 없으면: 패 id ↔ 종류 · 적5 · 범위가 서버(smallint 0~135, id/4)와 갈려 대기·후리텐이 조용히 틀린다(SPEC §2.2).
    @Test("MahjongTile — 0~135 만 · kind = id/4 · 적5 = 16·52·88 · token · Codable 은 정수 하나")
    func tileSurface() throws {
        #expect(MahjongTile(id: -1) == nil && MahjongTile(id: 136) == nil)
        #expect(MahjongTile(id: 0) != nil && MahjongTile(id: 135) != nil, "기준선: 양 끝은 받는다")
        #expect((0...135).filter { Self.tile($0).isRed } == [16, 52, 88])
        #expect(Self.tile(16).kind == 4 && Self.tile(17).kind == 4 && Self.tile(135).kind == 33)
        #expect(Self.tile(16).token == "0m" && Self.tile(17).token == "5m" && Self.tile(52).token == "0p" && Self.tile(135).token == "7z")
        #expect(Self.tile(108).suit == .honor && Self.tile(108).number == nil && Self.tile(72).suit == .sou && Self.tile(72).number == 1)
        let data = try JSONEncoder().encode([Self.tile(16), Self.tile(135)])
        #expect(String(decoding: data, as: UTF8.self) == "[16,135]")
        #expect(try JSONDecoder().decode([MahjongTile].self, from: data) == [Self.tile(16), Self.tile(135)])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([MahjongTile].self, from: Data("[136]".utf8)) }
        #expect(Self.tile(3) < Self.tile(4), "Comparable = id 순")
    }

    // 없으면: 코퍼스 문자열의 id 배정이 reference physical_ids 와 갈려 적5 사례가 엉뚱한 id 로 들어간다.
    @Test("MahjongTiles.parse — reference 와 같은 id 배정(적5 c0 · 보통 5 c1~3) · 잘못된 글자는 nil")
    func parseAssignsPhysicalIDs() {
        #expect(MahjongTiles.parse("0m55m")?.map(\.id) == [16, 17, 18])
        #expect(MahjongTiles.parse("555m")?.map(\.id) == [17, 18, 19], "보통 5 는 c1 부터")
        #expect(MahjongTiles.parse("5555m") == nil, "보통 5 는 셋까지 — 넷째는 적5 자리")
        #expect(MahjongTiles.parse("1111m")?.map(\.id) == [0, 1, 2, 3], "기준선: 5 가 아니면 넷")
        #expect(MahjongTiles.parse("11111m") == nil)
        #expect(MahjongTiles.parse("1z7z")?.map(\.id) == [108, 132])
        for bad in ["0z", "8z", "9z", "m", "12", "1x", "１m"] { #expect(MahjongTiles.parse(bad) == nil, "\(bad)") }
        #expect(MahjongTiles.parse("")?.isEmpty == true)
        #expect(MahjongTiles.text(kinds: [33, 4, 0, 9, 4]) == "155m1p7z")
        #expect(MahjongTiles.counts34(MahjongTiles.parse("0m5m1z")!)[4] == 2, "적5 는 종류로 5")
        #expect(MahjongTiles.doraKind(ofIndicator: 8) == 0 && MahjongTiles.doraKind(ofIndicator: 30) == 27 && MahjongTiles.doraKind(ofIndicator: 33) == 31)
        #expect(MahjongTiles.doraKind(ofIndicator: 4) == 5, "기준선: 가운데 수패는 +1")
    }

    // 없으면: 역 id 가 서버(mahjong_yaku_order)·코퍼스와 갈려 역 표시가 "새 역"으로 떨어지거나 해석 고르기가 갈린다.
    // 천화·지화는 heavenly·earthly 다(D5 — 흔한 로마자는 상표 시험 패턴과 같은 글자라 쓰지 않는다).
    @Test("MahjongYaku — raw 값 45개 · order = 역만 먼저 · 천화·지화는 heavenly·earthly")
    func yakuVocabulary() {
        let expected = [
            "heavenly", "earthly", "kokushi", "kokushi_13", "suuankou", "suuankou_tanki", "daisangen", "shousuushii",
            "daisuushii", "tsuuiisou", "ryuuiisou", "chinroutou", "suukantsu", "chuuren", "junsei_chuuren",
            "riichi", "double_riichi", "ippatsu", "menzen_tsumo", "pinfu", "iipeikou", "tanyao", "yakuhai_haku",
            "yakuhai_hatsu", "yakuhai_chun", "bakaze", "jikaze", "chankan", "rinshan", "haitei", "houtei", "chiitoitsu",
            "sanshoku", "ittsu", "chanta", "toitoi", "sanankou", "sanshoku_doukou", "sankantsu", "honroutou",
            "shousangen", "honitsu", "junchan", "ryanpeikou", "chinitsu",
        ]
        #expect(MahjongYaku.order.map(\.rawValue) == expected)
        #expect(Set(MahjongYaku.allCases) == Set(MahjongYaku.order) && MahjongYaku.allCases.count == 45)
        #expect(MahjongYaku.heavenly.koreanName == "천화" && MahjongYaku.earthly.koreanName == "지화")
        #expect(MahjongYaku(rawValue: "kokushi_13") == .kokushi13 && MahjongYaku(rawValue: "kokushi13") == nil)
        #expect(MahjongWind.allCases.map(\.rawValue) == ["E", "S", "W", "N"])
        #expect(MahjongFormat.allCases.map(\.rawValue) == ["tonpuu", "hanchan"])
        #expect(MahjongClaimKind.allCases.map(\.rawValue) == ["ron", "pon", "minkan", "chi"])
        #expect(MahjongFuriten.Kind.allCases.map(\.rawValue) == ["discard", "temporary", "riichi"])
    }

    // 없으면: 서버 my_decision(§3.6 DECISION)을 못 읽거나 연습판 엔진이 다른 모양을 내 같은 화면 길이 갈린다.
    @Test("MahjongDecision — 스네이크 와이어(§3.6)를 kind 로 갈라 읽고 같은 모양으로 쓴다")
    func decisionWireShape() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let turnJSON = #"{"kind":"turn","seq":12,"decision_seq":11,"started_ms":1000,"deadline_ms":26000,"not_before_ms":null,"bank_ms":20000,"discard":[16,40],"riichi":[16],"tsumo":false,"ankan":[],"kakan":[],"kyuushu":false}"#
        let turn = try decoder.decode(MahjongDecision.self, from: Data(turnJSON.utf8))
        guard case .turn(let t) = turn else { Issue.record("turn 이 아니다"); return }
        #expect(t.decisionSeq == 11 && t.discard == [Self.tile(16), Self.tile(40)] && t.riichi == [Self.tile(16)] && t.notBeforeMs == nil)
        let callJSON = #"{"kind":"call","window_id":7,"window_kind":"discard","tile":17,"from_seat":2,"started_ms":1,"deadline_ms":2,"bank_ms":3,"ron":true,"pon":[[18,19]],"minkan":[],"chi":[],"answered":null}"#
        let call = try decoder.decode(MahjongDecision.self, from: Data(callJSON.utf8))
        guard case .call(let c) = call else { Issue.record("call 이 아니다"); return }
        #expect(c.windowId == 7 && c.windowKind == "discard" && c.fromSeat == 2 && c.pon == [[Self.tile(18), Self.tile(19)]])
        #expect(turn.kind == "turn" && call.kind == "call", "기준선: 두 갈래가 갈린다")
        // 왕복 — kind 칸과 스네이크 키가 그대로 나간다.
        for decision in [turn, call] {
            let data = try encoder.encode(decision)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["kind"] as? String == decision.kind)
            #expect(try decoder.decode(MahjongDecision.self, from: data) == decision)
        }
        #expect(throws: DecodingError.self) { try decoder.decode(MahjongDecision.self, from: Data(#"{"kind":"wait"}"#.utf8)) }
    }

    // 없으면: 시간 초과 자동 동작(SPEC §2.3 K-1)이 서버 mahjong__timeout_action 과 갈려 연습판·서버 판의 결과가 다르다.
    @Test("timeoutAction — 쯔모 > 쯔모기리 > 허용 패 중 id 최대 · 론 > 넘김")
    func timeoutAction() {
        let base = MahjongDecision.Turn(seq: 1, decisionSeq: 1, startedMs: 0, deadlineMs: 0, bankMs: 0,
                                        discard: [Self.tile(5), Self.tile(40), Self.tile(90)])
        var tsumo = base
        tsumo.tsumo = true
        #expect(MahjongRules.timeoutAction(.turn(tsumo), drawn: Self.tile(40)) == .tsumo)
        #expect(MahjongRules.timeoutAction(.turn(base), drawn: Self.tile(40)) == .discard(Self.tile(40)), "기준선: 쯔모 없으면 쯔모기리")
        #expect(MahjongRules.timeoutAction(.turn(base), drawn: nil) == .discard(Self.tile(90)), "뽑은 패 없음 = 오른쪽 끝")
        #expect(MahjongRules.timeoutAction(.turn(base), drawn: Self.tile(41)) == .discard(Self.tile(90)), "뽑은 패를 못 버림(쿠이카에)")
        let call = MahjongDecision.Call(windowId: 1, windowKind: "discard", tile: Self.tile(7), fromSeat: 0,
                                        startedMs: 0, deadlineMs: 0, bankMs: 0, ron: true, pon: [[Self.tile(4), Self.tile(5)]])
        var noRon = call
        noRon.ron = false
        #expect(MahjongRules.timeoutAction(.call(call), drawn: nil) == .ron)
        #expect(MahjongRules.timeoutAction(.call(noRon), drawn: nil) == .pass, "기준선: 퐁만 있으면 넘김")
    }
}
