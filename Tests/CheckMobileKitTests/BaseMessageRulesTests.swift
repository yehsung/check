import CheckCore
import Foundation
import Testing

/// 코어로 옮긴 메시지 읽음 규칙을 **폰 테스트에서도** 지킨다(맥 `V0330MessageReadRulesTests` 와 같은 표 한 줄).
///
/// 이 표가 막는 것(dbase-verify M7): `effectiveOrder` 가 서버 순서가 모르는 즉시 삽입분의 번호를 0 부터 매기면, 앞 말(a) 까지 올린
/// 낙관 읽음 경계가 나중에 도착한 새 말(c)까지 덮어 점이 꺼진다. 맥 467건 · 폰 48건이 그 변이에서 초록이었다.
@Suite struct BaseMessageRulesTests {
    static let now = Date(timeIntervalSince1970: 1_789_621_500)

    static func entry(_ id: String, unread: Bool?, at offset: TimeInterval) -> MessageHistoryEntry {
        MessageHistoryEntry(id: id, peerUserID: "p", peerName: "P", peerAvatarURL: nil, body: id,
                            createdAt: now.addingTimeInterval(offset), isMine: false, readByPeer: nil, isUnread: unread)
    }

    @Test("서버 순서가 모르는 즉시 삽입분은 서버 순서 뒤에 서서, 앞 말까지 올린 낙관 경계에 덮이지 않는다")
    func insertedArrivalStaysBehindServerOrder() {
        // a·b 는 서버가 아는 말(b 는 이미 읽음), c 는 이력 응답 뒤에 즉시 삽입된 새 말.
        let a = Self.entry("a", unread: true, at: 0)
        let b = Self.entry("b", unread: false, at: 1)
        let c = Self.entry("c", unread: true, at: 2)
        let history = [a, b, c]
        let snapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["a": 0, "b": 1])
        let order = MessageUnreadRules.effectiveOrder(history: history, serverOrder: snapshot.serverOrder)
        #expect(order == ["a": 0, "b": 1, "c": 2])

        let boundary = MessageOptimisticRead(throughID: "a", recordedSerial: 2)   // 스냅샷(1)이 모르는 낙관 경계
        #expect(MessageUnreadRules.isCovered(a, by: boundary, order: order))
        #expect(!MessageUnreadRules.isCovered(c, by: boundary, order: order), "경계 뒤에 온 새 말을 읽음으로 덮었다")
        #expect(MessageUnreadRules.unreadPeerIDs(history: history, historySnapshot: snapshot, summary: nil,
                                                 optimistic: ["p": boundary], legacyStamps: [:]) == ["p"])
        #expect(!MessageUnreadRules.isAlreadyRead(messageID: "c", history: history, snapshot: snapshot, optimistic: ["p": boundary]))
        #expect(MessageUnreadRules.markTarget(peer: "p", history: history, snapshot: snapshot, optimistic: boundary) == "c",
                "새 경계는 삽입분 c 다")

        // 대조: 경계가 삽입분 자신이면 덮인다(점이 꺼지는 것이 맞다).
        let through = MessageOptimisticRead(throughID: "c", recordedSerial: 2)
        #expect(MessageUnreadRules.unreadPeerIDs(history: history, historySnapshot: snapshot, summary: nil,
                                                 optimistic: ["p": through], legacyStamps: [:]).isEmpty)
    }
}
