import Foundation
import Testing
@testable import check
@testable import CheckCore

// 아잉 마작 반응 공급기(SPEC §5.3 — 큐브 덮개를 그대로 쓰고, 처음 보는 반응만 받은 때부터 2.5초).
// 서버 state 는 최근 10초 반응을 싣고(`mahjong_reactions` 주석), `mahjong_react` ok 응답엔 state 가 없다(실응답 픽스처).

@MainActor
@Suite("아잉 마작 반응 공급기")
struct V03xxMahjongReactionFeedTests {
    private let now = Date(timeIntervalSince1970: 1_793_699_167)

    @Test
    func freshReactionsShowOnceAtTheSenderSeatFromWhenTheyArrive() throws {
        // 없으면: 폴링마다 같은 반응이 또 뜨거나(중복), 말풍선 2.5초를 서버 시각부터 재서 폴링이 3초 늦으면 안 보이거나,
        // 창을 늦게 열어 지난 반응이 한꺼번에 떠도 초록이다.
        let feed = MahjongReactionFeed()
        let payload = try mjFeedPayload(matchID: "m-1", reactions: [(3, "joy", -3.0), (1, "heart", -0.5), (2, "sad", -8.0)])
        feed.ingest(payload, now: now, serverOffset: 0)
        #expect(feed.bubbles.map(\.seatNo) == [3, 1], "8초 지난 반응은 그리지 않는다 · 오래된 것부터")
        #expect(feed.bubbles.allSatisfy { !$0.isMine && $0.receivedAt == now }, "보이는 시간은 받은 때부터다")
        // 3초 늦게 받은 반응도 2초 뒤에 아직 보인다(서버 시각 기준이면 5초 — 이미 사라졌다).
        #expect(RummyReactionOverlay.visible(feed.bubbles, at: now.addingTimeInterval(2)).map(\.seatNo) == [1, 3])
        feed.ingest(payload, now: now.addingTimeInterval(0.5), serverOffset: 0)
        #expect(feed.bubbles.count == 2, "같은 반응이 또 떴다")
        // 기준선(결과가 다른): 5초 된 반응은 아직 '처음 보는 새 반응'이다.
        let late = try mjFeedPayload(matchID: "m-1", reactions: [(2, "angry", -5.0)])
        feed.ingest(late, now: now, serverOffset: 0)
        #expect(feed.bubbles.map(\.seatNo) == [3, 1, 2])
        // 서버 시계 보정을 쓴다: 기기가 서버보다 7초 늦으면(offset −7) 3초 된 반응도 10초 된 것이다.
        let skewed = MahjongReactionFeed()
        skewed.ingest(try mjFeedPayload(matchID: "m-1", reactions: [(3, "joy", -3.0)]), now: now, serverOffset: -7)
        #expect(skewed.bubbles.isEmpty)
    }

    @Test
    func myReactionShowsAtOnceAndItsEchoIsSwallowedOnce() throws {
        // 없으면: 내 반응이 응답·폴링을 기다려서야 뜨거나, 서버 메아리로 내 말풍선이 두 번 뜨거나, 2초 쿨다운 안에 또 보내져도 초록이다.
        let feed = MahjongReactionFeed()
        #expect(feed.noteSent(.joy, seat: 0, matchID: "m-1", now: now))
        #expect(feed.bubbles.count == 1 && feed.bubbles[0].isMine && feed.bubbles[0].seatNo == 0)
        #expect(!feed.noteSent(.heart, seat: 0, matchID: "m-1", now: now.addingTimeInterval(1.9)), "쿨다운 안에 또 보냈다")
        #expect(feed.noteSent(.heart, seat: 0, matchID: "m-1", now: now.addingTimeInterval(2.0)))
        feed.ingest(try mjFeedPayload(matchID: "m-1", reactions: [(0, "joy", 0.3)]), now: now.addingTimeInterval(1), serverOffset: 0)
        #expect(feed.bubbles.count == 2, "메아리가 또 떴다")
        // 메아리는 한 번만 삼킨다 — 같은 키의 둘째 줄(다른 시각)은 새 반응이다(다른 기기에서 같은 계정이 보낸 것).
        feed.ingest(try mjFeedPayload(matchID: "m-1", reactions: [(0, "joy", 0.3), (0, "joy", 1.4)]), now: now.addingTimeInterval(2),
                    serverOffset: 0)
        #expect(feed.bubbles.count == 3 && feed.bubbles.last?.isMine == true)
    }

    @Test
    func aNewMatchStartsOver() throws {
        // 없으면: 앞 판의 말풍선·본 기록이 다음 판에 남아(같은 자리·키·시각이면) 새 판 반응을 삼켜도 초록이다.
        let feed = MahjongReactionFeed()
        feed.ingest(try mjFeedPayload(matchID: "m-1", reactions: [(2, "joy", -1)]), now: now, serverOffset: 0)
        #expect(feed.bubbles.count == 1)
        feed.ingest(try mjFeedPayload(matchID: "m-2", reactions: [(2, "joy", -1)]), now: now, serverOffset: 0)
        #expect(feed.bubbles.count == 1 && feed.bubbles[0].id == 2, "새 판에서 처음부터 다시 세지 않았다")
        // 판 없는 state(방)는 아무것도 안 바꾼다.
        feed.ingest(MahjongStatePayload(), now: now, serverOffset: 0)
        #expect(feed.bubbles.count == 1)
    }

    @Test
    func compassAndEdgesFollowTheTableLayout() {
        // 없으면: 하가(오른쪽) 반응이 큐브 방위(하가 왼쪽)로 서거나, 위 카드 말풍선이 창 밖(위)으로 서도 초록이다.
        #expect(MahjongReactionCompass.of(seat: 1, mySeat: 0) == .right)
        #expect(MahjongReactionCompass.of(seat: 3, mySeat: 0) == .left)
        #expect(MahjongReactionCompass.of(seat: 2, mySeat: 0) == .top)
        #expect(MahjongReactionCompass.of(seat: 0, mySeat: 2) == .top && MahjongReactionCompass.of(seat: 2, mySeat: 2) == .bottom)
        #expect(MahjongReactionCompass.edge(.top) == .bottom && MahjongReactionCompass.edge(.left) == .trailing
                && MahjongReactionCompass.edge(.right) == .leading && MahjongReactionCompass.edge(.bottom) == .top)
    }
}

/// state 하나(판 id · 내 자리 0 · 반응 줄 (자리, 키, now 기준 초)).
private func mjFeedPayload(matchID: String, reactions: [(Int, String, Double)]) throws -> MahjongStatePayload {
    let base = 1_793_699_167_000.0
    let object: [String: Any] = [
        "match": ["id": matchID, "status": "active", "phase": "turn"],
        "my_seat": 0,
        "reactions": reactions.map { ["seat_no": $0.0, "key": $0.1, "at_ms": base + $0.2 * 1_000, "user_id": "u-\($0.0)"] },
    ]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(MahjongStatePayload.self, from: JSONSerialization.data(withJSONObject: object))
}
