import Foundation
import Testing
@testable import check

// v0.3.30 — 안 읽음·읽음 경계·말풍선 필터의 **순수 규칙**(MessageUnreadRules). 네트워크 0, 시계 0.
//
// 여기 표가 곧 계약이다: 스토어의 `unreadMessagePeerIDs` · `evaluateMessageReadMarking` · drain 말풍선 필터가 이 함수들만 부른다.

private let rulesNow = Date(timeIntervalSince1970: 1_790_000_000)

private func rulesEntry(
    _ id: String, peer: String, mine: Bool = false, unread: Bool? = nil, readByPeer: Bool? = nil,
    at offset: TimeInterval = 0
) -> MessageHistoryEntry {
    MessageHistoryEntry(
        id: id, peerUserID: peer, peerName: peer, peerAvatarURL: nil, body: "본문",
        createdAt: rulesNow.addingTimeInterval(offset), isMine: mine, readByPeer: readByPeer, isUnread: unread
    )
}

private func rulesSummary(serial: Int, _ peers: [(String, Int)]) -> MessageUnreadSummarySnapshot {
    MessageUnreadSummarySnapshot(
        serial: serial,
        summary: MessageUnreadSummary(
            total: peers.reduce(0) { $0 + $1.1 },
            peers: peers.map { MessageUnreadPeer(peerUserID: $0.0, count: $0.1, lastMessageAt: nil) }
        )
    )
}

@Test
func 서버_스냅샷이_없으면_옛_도장_규칙이다() {
    let history = [rulesEntry("a", peer: "u1", at: -60), rulesEntry("b", peer: "u2", at: -30), rulesEntry("c", peer: "u2", mine: true)]
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: history, historySnapshot: nil, summary: nil, optimistic: [:], legacyStamps: [:]
    ) == ["u1", "u2"])
    // 도장이 마지막 받은 것 이후면 읽음, 같으면 읽음(경계 포함), 이전이면 안 읽음.
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: history, historySnapshot: nil, summary: nil, optimistic: [:],
        legacyStamps: ["u1": rulesNow.addingTimeInterval(-60), "u2": rulesNow.addingTimeInterval(-31)]
    ) == ["u2"])
    // 내가 보낸 것만 있는 대화는 점이 없다.
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: [rulesEntry("m", peer: "u3", mine: true)], historySnapshot: nil, summary: nil, optimistic: [:], legacyStamps: [:]
    ).isEmpty)
}

@Test
func 이력과_요약_중_나중에_띄운_쪽이_이긴다() {
    let history = [rulesEntry("a", peer: "u1", unread: true), rulesEntry("b", peer: "u2", unread: false)]
    let snapshot = MessageHistoryReadSnapshot(serial: 5, serverOrder: ["a": 0, "b": 1])
    // 이력만 → 이력 판정. 도장은 무시된다(서버가 읽음을 안다).
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: history, historySnapshot: snapshot, summary: nil, optimistic: [:], legacyStamps: ["u1": rulesNow.addingTimeInterval(3600)]
    ) == ["u1"])
    // 요약이 더 나중(6) → 요약 판정(다른 기기에서 u1 을 읽었고 u2 에게 새 말이 왔다).
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: history, historySnapshot: snapshot, summary: rulesSummary(serial: 6, [("u2", 1)]), optimistic: [:], legacyStamps: [:]
    ) == ["u2"])
    // 요약이 더 먼저(4) → 이력 판정.
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: history, historySnapshot: snapshot, summary: rulesSummary(serial: 4, [("u2", 1)]), optimistic: [:], legacyStamps: [:]
    ) == ["u1"])
    // 요약만 → 요약 판정(count 0 인 상대는 요약 모델이 이미 뺐다).
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: [], historySnapshot: nil, summary: rulesSummary(serial: 1, [("u9", 2)]), optimistic: [:], legacyStamps: [:]
    ) == ["u9"])
    // 이력의 isUnread 가 nil(모름)인 받은 메시지는 안 읽음으로 치지 않는다.
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: [rulesEntry("x", peer: "u7", unread: nil)], historySnapshot: MessageHistoryReadSnapshot(serial: 1, serverOrder: ["x": 0]),
        summary: nil, optimistic: [:], legacyStamps: [:]
    ).isEmpty)
}

@Test
func 낙관_읽음은_그것을_모르는_스냅샷에만_적용된다() {
    let history = [rulesEntry("a1", peer: "u1", unread: true), rulesEntry("a2", peer: "u1", unread: true)]
    let order = ["a1": 0, "a2": 1]
    // 경계 a2 로 올리는 중(정산 전) — 이력(3)이 모르므로 점이 꺼진다.
    let inFlight = MessageOptimisticRead(throughID: "a2", recordedSerial: 4)
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: history, historySnapshot: MessageHistoryReadSnapshot(serial: 3, serverOrder: order),
        summary: nil, optimistic: ["u1": inFlight], legacyStamps: [:]
    ).isEmpty)
    // 경계 a1 까지만 — 그 뒤에 온 a2 는 남는다(새 메시지는 다시 점을 켠다).
    let partial = MessageOptimisticRead(throughID: "a1", recordedSerial: 4)
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: history, historySnapshot: MessageHistoryReadSnapshot(serial: 3, serverOrder: order),
        summary: nil, optimistic: ["u1": partial], legacyStamps: [:]
    ) == ["u1"])
    // 정산(5)보다 **나중에** 띄운 이력(6)은 서버가 안다 — 낙관을 무시하고 서버 판정을 따른다(실패해 서버가 여전히 안 읽음이면 켜진다).
    var settled = MessageOptimisticRead(throughID: "a2", recordedSerial: 4)
    settled.settledSerial = 5
    settled.failed = true
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: history, historySnapshot: MessageHistoryReadSnapshot(serial: 6, serverOrder: order),
        summary: nil, optimistic: ["u1": settled], legacyStamps: [:]
    ) == ["u1"])
    // 정산보다 **먼저** 띄운 이력(5 = 정산과 같은 번호는 모른다)에는 여전히 적용된다.
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: history, historySnapshot: MessageHistoryReadSnapshot(serial: 5, serverOrder: order),
        summary: nil, optimistic: ["u1": settled], legacyStamps: [:]
    ).isEmpty)
    // 요약은 id 를 모른다 — 모르는 요약에서는 그 상대를 통째로 뺀다.
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: [], historySnapshot: nil, summary: rulesSummary(serial: 4, [("u1", 2), ("u2", 1)]),
        optimistic: ["u1": inFlight], legacyStamps: [:]
    ) == ["u2"])
    #expect(MessageUnreadRules.unreadPeerIDs(
        history: [], historySnapshot: nil, summary: rulesSummary(serial: 6, [("u1", 2), ("u2", 1)]),
        optimistic: ["u1": settled], legacyStamps: [:]
    ) == ["u1", "u2"])
}

@Test
func 경계는_서버_순서의_마지막_받은_메시지이고_같은_경계는_다시_올리지_않는다() {
    // 화면 정렬(초 → id)로는 c 가 마지막이지만 서버 순서로는 a 가 마지막이다.
    let history = [
        rulesEntry("a", peer: "u1", unread: true), rulesEntry("b", peer: "u1", unread: true),
        rulesEntry("c", peer: "u1", unread: true), rulesEntry("m", peer: "u1", mine: true, readByPeer: false),
        rulesEntry("z", peer: "u2", unread: true)
    ]
    let snapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["c": 0, "b": 1, "m": 2, "a": 3, "z": 4])
    #expect(MessageUnreadRules.markTarget(peer: "u1", history: history, snapshot: snapshot, optimistic: nil) == "a")
    // 올리는 중·올린 경계와 같으면 nil.
    #expect(MessageUnreadRules.markTarget(
        peer: "u1", history: history, snapshot: snapshot, optimistic: MessageOptimisticRead(throughID: "a", recordedSerial: 2)
    ) == nil)
    // 실패로 정산된 기록은 다시 올린다.
    var failed = MessageOptimisticRead(throughID: "a", recordedSerial: 2)
    failed.settledSerial = 3
    failed.failed = true
    #expect(MessageUnreadRules.markTarget(peer: "u1", history: history, snapshot: snapshot, optimistic: failed) == "a")
    // 옛 경계(b)보다 새 말(a)이 있으면 새 경계로.
    #expect(MessageUnreadRules.markTarget(
        peer: "u1", history: history, snapshot: snapshot, optimistic: MessageOptimisticRead(throughID: "b", recordedSerial: 2)
    ) == "a")
    // 서버 기준 안 읽은 받은 메시지가 없으면 nil(내가 보낸 것만 안 읽혔어도 nil).
    let allRead = [rulesEntry("a", peer: "u1", unread: false), rulesEntry("m", peer: "u1", mine: true, readByPeer: false)]
    #expect(MessageUnreadRules.markTarget(peer: "u1", history: allRead, snapshot: snapshot, optimistic: nil) == nil)
    // 대화가 없는 상대도 nil.
    #expect(MessageUnreadRules.markTarget(peer: "nobody", history: history, snapshot: snapshot, optimistic: nil) == nil)
}

@Test
func 말풍선_필터는_서버_읽음과_낙관_경계만_거른다() {
    let history = [
        rulesEntry("r", peer: "u1", unread: false), rulesEntry("o1", peer: "u2", unread: true),
        rulesEntry("o2", peer: "u2", unread: true), rulesEntry("mine", peer: "u2", mine: true)
    ]
    let snapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["r": 0, "o1": 1, "o2": 2, "mine": 3])
    let optimistic = ["u2": MessageOptimisticRead(throughID: "o1", recordedSerial: 2)]
    func read(_ id: String, snapshot: MessageHistoryReadSnapshot? = snapshot) -> Bool {
        MessageUnreadRules.isAlreadyRead(messageID: id, history: history, snapshot: snapshot, optimistic: optimistic)
    }
    #expect(read("r"), "서버 기준 읽은 메시지를 말풍선으로 띄운다")
    #expect(read("o1"), "낙관 읽음 경계 안의 메시지를 말풍선으로 띄운다")
    #expect(!read("o2"), "경계 뒤에 온 새 메시지를 말풍선에서 뺐다")
    #expect(!read("unknown"), "이력에 없는(더 새) 메시지를 뺐다")
    #expect(!read("mine"))
    // 읽음을 모르는 서버(스냅샷 없음)면 옛 동작 — 아무것도 거르지 않는다.
    #expect(!read("r", snapshot: nil))
}

@Test
func 요약_응답은_ok_일_때만_스냅샷이고_0_인_상대는_뺀다() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let ok = try decoder.decode(MessageUnreadSummaryResponse.self, from: Data(#"""
    {"status":"ok","total":3,"peers":[{"peer_user_id":"u1","count":2,"last_epoch_ms":1790000000123},
     {"peer_user_id":"u2","count":0,"last_epoch_ms":1790000000000},{"peer_user_id":null,"count":1},
     {"peer_user_id":"u3","count":1,"last_epoch_ms":1789999999000.0}]}
    """#.utf8))
    let summary = try #require(ok.summary)
    #expect(summary.total == 3)
    #expect(summary.peers.map(\.peerUserID) == ["u1", "u3"], "서버 순서를 지키고 0·id 없음을 뺀다")
    // 표시용 시각이다(판정에 쓰지 않는다) — 부동소수 마지막 비트까지 재지 않는다.
    #expect(abs((summary.peers.first?.lastMessageAt?.timeIntervalSince1970 ?? 0) - 1_790_000_000.123) < 0.0005)
    let unauthorized = try decoder.decode(MessageUnreadSummaryResponse.self, from: Data(#"{"status":"unauthorized"}"#.utf8))
    #expect(unauthorized.summary == nil, "미로그인 응답을 '안 읽은 것 0'으로 읽었다")
    // 키가 빠져도 디코드가 죽지 않는다(전부 옵셔널).
    let bare = try decoder.decode(MessageUnreadSummaryResponse.self, from: Data(#"{"status":"ok"}"#.utf8))
    #expect(bare.summary == MessageUnreadSummary(total: 0, peers: []))
}
