import Foundation
import Testing
@testable import check
@testable import CheckCore

// 역 목록 '지금 손으로 될 수 있는 역' 점(SPEC §5.7 · UX:436) — 내 손 + 공개 정보만, R `MahjongScoring.evaluate` 로.
// 텐파이(또는 쯔모 화료 꼴)일 때만 점을 찍고, 텐파이 전 추측은 하지 않는다.

@Suite("아잉 마작 지금 될 수 있는 역")
struct V03xxMahjongPossibleYakuTests {
    @Test
    func tenpaiHandMarksTheYakuItsWaitsWouldBring() throws {
        // 없으면: 점이 대기마다의 화료 역이 아니라 아무 역이나 찍히거나(탕야오 없는 1만 화료에도 탕야오만), 리치 표시를 안 읽어도 초록이다.
        let hand = "23m345p456s678s55p"
        #expect(MahjongPossibleYaku.of(try mjPossible(hand: hand)) == [.pinfu, .tanyao, .menzenTsumo])
        // 기준선(결과가 다른): 리치한 같은 손은 리치가 더해진다.
        #expect(MahjongPossibleYaku.of(try mjPossible(hand: hand, riichi: true)) == [.riichi, .pinfu, .tanyao, .menzenTsumo])
        // 서버 대기가 있으면 그것을 쓴다(1만만 — 탕야오 없음).
        #expect(MahjongPossibleYaku.of(try mjPossible(hand: hand, waits: [0])) == [.pinfu, .menzenTsumo])
    }

    @Test
    func heldDrawOnlyCountsWhenItCompletesTheHand() throws {
        // 없으면: 쯔모한 패를 쥔 14장에서 화료가 아닌데도 점이 찍히거나, 화료 꼴인데 점이 없어도 초록이다.
        let hand = "23m345p456s678s55p"
        #expect(MahjongPossibleYaku.of(try mjPossible(hand: hand, drawn: "4m")) == [.pinfu, .tanyao, .menzenTsumo])
        #expect(MahjongPossibleYaku.of(try mjPossible(hand: hand, drawn: "9p")).isEmpty)
    }

    @Test
    func noGuessesBeforeTenpaiAndOpenHandsFollowTheOpenRules() throws {
        // 없으면: 텐파이 전 손에 '될지도 모르는 역'을 찍거나(추측 — 효율 계산기 금지와 같은 선), 운 손에 멘젠 역(핑후·멘젠쯔모)을 찍어도 초록이다.
        #expect(MahjongPossibleYaku.of(try mjPossible(hand: "147m258p369s1357z")).isEmpty)
        let pon = try #require(MahjongTiles.parse("555p"))
        let open = try mjPossible(hand: "234m456s678s2p", melds: [["type": "pon", "tiles": pon.map(\.id), "called": pon[2].id,
                                                                     "from_seat": 0]])
        #expect(MahjongPossibleYaku.of(open) == [.tanyao])
        // 바람: 동장 동가(친)의 東 은 장풍·자풍 둘 다, 南 쪽 화료는 쯔모일 때만 멘젠쯔모.
        #expect(MahjongPossibleYaku.of(try mjPossible(hand: "123m456p789s1122z", wind: "E")) == [.bakaze, .jikaze, .menzenTsumo])
        #expect(MahjongPossibleYaku.of(try mjPossible(hand: "123m456p789s1122z", wind: "S")) == [.bakaze, .jikaze, .menzenTsumo])
        #expect(MahjongPossibleYaku.of(try mjPossible(hand: "123m456p789s1133z", wind: "S")) == [.bakaze, .menzenTsumo])
        // 손이 없으면(방·로비) 아무것도 없다.
        #expect(MahjongPossibleYaku.of(MahjongStatePayload()).isEmpty)
    }
}

/// 내 자리(0) state — 손 · 쯔모패 · 서버 대기 · 리치 · 바람 · 부로(동장).
private func mjPossible(hand: String, drawn: String? = nil, waits: [Int] = [], riichi: Bool = false, wind: String = "S",
                        melds: [[String: Any]] = []) throws -> MahjongStatePayload {
    let tiles = try #require(MahjongTiles.parse(hand))
    var taken = Set(tiles.map(\.id))
    for meld in melds { for id in meld["tiles"] as? [Int] ?? [] { taken.insert(id) } }
    var drawnID: Any = NSNull()
    if let drawn {
        // 같은 종류의 아직 안 쓴 패(파서는 같은 종류를 작은 c 부터 배정한다).
        let kind = try #require(MahjongTiles.parse(drawn)?.first).kind
        drawnID = try #require((0..<4).map { kind * 4 + $0 }.first { !taken.contains($0) && ![16, 52, 88].contains($0) })
    }
    let object: [String: Any] = [
        "match": ["id": "m", "status": "active", "phase": "turn", "round": 0],
        "seats": [["seat_no": 0, "wind": wind, "riichi": riichi, "melds": melds]],
        "my_seat": 0, "my_hand": tiles.map(\.id), "my_drawn": drawnID, "my_waits": waits,
    ]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(MahjongStatePayload.self, from: JSONSerialization.data(withJSONObject: object))
}
