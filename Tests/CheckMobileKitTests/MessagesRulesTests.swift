import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 메시지 탭의 순수 규칙(`MessagesRules.swift`): 배지 숫자 · 자리 말풍선 정리 · 보내기 문구 · 입력 카운터 · 사람 찾기 · 대화 줄 · 바닥 따라가기 · 라우트.
@Suite struct MessagesRulesTests {
    static let now = MobileClock.demoInstant

    static func entry(
        _ id: String, peer: String = "p", mine: Bool = false, at offset: TimeInterval,
        unread: Bool? = nil, readByPeer: Bool? = nil, body: String? = nil
    ) -> MessageHistoryEntry {
        MessageHistoryEntry(id: id, peerUserID: peer, peerName: peer.uppercased(), peerAvatarURL: nil, body: body ?? id,
                            createdAt: now.addingTimeInterval(offset), isMine: mine, readByPeer: readByPeer, isUnread: unread)
    }

    /// 코어 요약 값은 멤버와이즈 init 이 모듈 안(internal)이라 전선 모양(JSON)에서 만든다 — 서비스가 받는 것과 같은 길.
    static func summary(_ json: String) -> MessageUnreadSummary {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(MessageUnreadSummaryResponse.self, from: Data(json.utf8)).summary!
    }

    // MARK: 배지

    @Test("배지 숫자는 점과 같은 재료·같은 선택 규칙: 이력이 새것이면 안 읽은 받은 말 수, 요약이 새것이면 요약 개수 합, 낙관 읽음은 뺀다")
    func badgeCountMatchesUnreadPeers() {
        let history = [
            Self.entry("a1", peer: "a", at: -300, unread: true),
            Self.entry("a2", peer: "a", at: -200, unread: true),
            Self.entry("m1", peer: "a", mine: true, at: -100, readByPeer: false),
            Self.entry("b1", peer: "b", at: -50, unread: false),
            Self.entry("c1", peer: "c", at: -10, unread: true),
        ]
        let order = ["a1": 0, "a2": 1, "m1": 2, "b1": 3, "c1": 4]
        let historySnap = MessageHistoryReadSnapshot(serial: 5, serverOrder: order)
        let summary = Self.summary(#"{"status":"ok","total":7,"peers":[{"peer_user_id":"a","count":4,"last_epoch_ms":1},{"peer_user_id":"d","count":3,"last_epoch_ms":1}]}"#)
        let olderSummary = MessageUnreadSummarySnapshot(serial: 3, summary: summary)
        let newerSummary = MessageUnreadSummarySnapshot(serial: 9, summary: summary)

        func check(_ snapshot: MessageHistoryReadSnapshot?, _ summary: MessageUnreadSummarySnapshot?,
                   _ optimistic: [String: MessageOptimisticRead], expect count: Int, _ peers: Set<String>) {
            let got = MessagesBadgeRules.unreadCount(history: history, historySnapshot: snapshot, summary: summary,
                                                     optimistic: optimistic, legacyStamps: [:])
            let unread = MessageUnreadRules.unreadPeerIDs(history: history, historySnapshot: snapshot, summary: summary,
                                                          optimistic: optimistic, legacyStamps: [:])
            #expect(got == count)
            #expect(unread == peers)
            #expect((got > 0) == !unread.isEmpty, "점과 배지가 갈렸다")
        }
        check(historySnap, olderSummary, [:], expect: 3, ["a", "c"])
        check(historySnap, newerSummary, [:], expect: 7, ["a", "d"])
        // 스냅샷이 모르는 낙관 읽음(a2 까지) → a 의 두 말이 빠진다.
        let pendingRead = MessageOptimisticRead(throughID: "a2", recordedSerial: 6)
        check(historySnap, olderSummary, ["a": pendingRead], expect: 1, ["c"])
        check(historySnap, newerSummary, ["a": MessageOptimisticRead(throughID: "a2", recordedSerial: 10)], expect: 3, ["d"])
        // 정산 뒤에 띄운 요약은 사실을 말한다(낙관을 빼지 않는다).
        let settled = MessageOptimisticRead(throughID: "a2", recordedSerial: 6, settledSerial: 7)
        check(historySnap, newerSummary, ["a": settled], expect: 7, ["a", "d"])
        // 요약만.
        check(nil, newerSummary, [:], expect: 7, ["a", "d"])
        // 둘 다 없음(옛 서버) → 도장 규칙: 도장이 없으면 받은 말이 있는 대화 전부(a 2 · b 1 · c 1).
        check(nil, nil, [:], expect: 4, ["a", "b", "c"])
    }

    @Test("옛 서버(읽음 모름): 도장보다 나중에 받은 말만 센다 — 도장이 없으면 받은 말 전부")
    func badgeCountLegacy() {
        let history = [
            Self.entry("a1", peer: "a", at: -300),
            Self.entry("a2", peer: "a", at: -100),
            Self.entry("b1", peer: "b", at: -50),
        ]
        let stamps = ["a": Self.now.addingTimeInterval(-200)]
        #expect(MessagesBadgeRules.unreadCount(history: history, historySnapshot: nil, summary: nil, optimistic: [:], legacyStamps: stamps) == 2)
        #expect(MessagesBadgeRules.unreadCount(history: history, historySnapshot: nil, summary: nil, optimistic: [:],
                                               legacyStamps: ["a": Self.now, "b": Self.now]) == 0)
    }

    // MARK: 자리 말풍선

    @Test("자리 말풍선: 응답 뒤에 띄운 이력이 오면 지우고, 먼저 띄운 이력이 새 행을 들고 오면 본문으로 짝지어 지운다(같은 말 두 번 안 보임)")
    func pendingReconcile() {
        let t0 = Self.now
        let sending = MessagesPendingOutgoing(id: "l1", peerUserID: "p", body: "안녕", createdAt: t0, state: .sending)
        let sent = MessagesPendingOutgoing(id: "l2", peerUserID: "p", body: "또", createdAt: t0, state: .sent(settledSerial: 10))
        // 1) 응답(10) 뒤에 띄운 이력(11) → sent 는 사라진다. sending 은 행이 없으니 남는다.
        #expect(MessagesPendingRules.reconcile(pending: [sending, sent], previousHistoryIDs: [], applied: [], appliedSerial: 11) == [sending])
        // 응답보다 먼저 띄운 이력(9)은 sent 를 못 지운다.
        #expect(MessagesPendingRules.reconcile(pending: [sent], previousHistoryIDs: [], applied: [], appliedSerial: 9) == [sent])
        // 2) 처음 나타난 내 말(같은 본문) → 짝지어 지운다.
        let row = Self.entry("s1", mine: true, at: 1, readByPeer: false, body: "안녕")
        #expect(MessagesPendingRules.reconcile(pending: [sending], previousHistoryIDs: [], applied: [row], appliedSerial: 5).isEmpty)
        // 이미 있던 같은 본문(아침의 "안녕")은 새 말이 아니다.
        #expect(MessagesPendingRules.reconcile(pending: [sending], previousHistoryIDs: ["s1"], applied: [row], appliedSerial: 5) == [sending])
        // 시각 창 밖의 같은 본문도 아니다.
        let old = Self.entry("s0", mine: true, at: -3600, readByPeer: true, body: "안녕")
        #expect(MessagesPendingRules.reconcile(pending: [sending], previousHistoryIDs: [], applied: [old], appliedSerial: 5) == [sending])
        // 받은 말·다른 상대는 짝이 아니다.
        let received = Self.entry("r1", at: 1, unread: true, body: "안녕")
        let other = Self.entry("o1", peer: "q", mine: true, at: 1, readByPeer: false, body: "안녕")
        #expect(MessagesPendingRules.reconcile(pending: [sending], previousHistoryIDs: [], applied: [received, other], appliedSerial: 5) == [sending])
        // 같은 말 두 번 보내면 행 하나에 하나씩만 짝짓는다.
        let twin = MessagesPendingOutgoing(id: "l3", peerUserID: "p", body: "안녕", createdAt: t0, state: .sending)
        #expect(MessagesPendingRules.reconcile(pending: [sending, twin], previousHistoryIDs: [], applied: [row], appliedSerial: 5) == [twin])
    }

    // MARK: 보내기 문구

    @Test("보내기 결과 문구는 코어 MessageNoticeText(맥과 같은 문장) — 성공은 문구 없음, flood 는 일반 안내로 접는다")
    func sendNotices() {
        #expect(MessagesSendRules.notice(for: .ok, maxLength: nil) == nil)
        #expect(MessagesSendRules.notice(for: .targetFocused, maxLength: nil) == "지금 집중 중이에요. 나중에 보내 주세요")
        #expect(MessagesSendRules.notice(for: .targetFocused, maxLength: nil) == MessageNoticeText.targetFocused)
        #expect(MessagesSendRules.notice(for: .tooLong, maxLength: 150) == "메시지는 150자까지예요. 줄여서 보내 주세요")
        #expect(MessagesSendRules.notice(for: .tooLong, maxLength: nil) == MessageNoticeText.tooLong(maxLength: 200))
        #expect(MessagesSendRules.notice(for: .notText, maxLength: nil) == MessageNoticeText.notText)
        #expect(MessagesSendRules.notice(for: .blackout, maxLength: nil) == MessageNoticeText.blackout)
        #expect(MessagesSendRules.notice(for: .notWorking, maxLength: nil) == MessageNoticeText.notWorking)
        #expect(MessagesSendRules.notice(for: .targetNotWorking, maxLength: nil) == MessageNoticeText.targetNotWorking)
        #expect(MessagesSendRules.notice(for: .flood, maxLength: nil) == MessageNoticeText.invalid)
        #expect(MessagesSendRules.notice(for: MessageSendOutcome(response: PokeSendResponse(status: "cooldown")), maxLength: nil) == MessageNoticeText.invalid)
        #expect(MessageNoticeText.expiry == "24시간이 지난 메시지는 사라져요")
    }

    // MARK: 입력칸

    @Test("카운터는 코드포인트 180부터 · 200 초과는 넘침 · 조합 중 [보내기]는 확정 먼저")
    func composerRules() {
        #expect(MessagesComposerRules.counterText(for: String(repeating: "가", count: 179)) == nil)
        #expect(MessagesComposerRules.counterText(for: String(repeating: "가", count: 180)) == "180/200")
        #expect(MessagesComposerRules.counterText(for: "  " + String(repeating: "a", count: 185) + "\n") == "185/200", "앞뒤 공백은 세지 않는다")
        // 👨‍👩‍👧‍👦 는 자소 1 · 코드포인트 7 — 서버 char_length 눈금.
        let family = "👨‍👩‍👧‍👦"
        #expect(MessageBody.length(family) == 7)
        #expect(MessagesComposerRules.counterText(for: String(repeating: family, count: 26)) == "182/200")
        #expect(!MessagesComposerRules.isOverflowing(String(repeating: "a", count: 200)))
        #expect(MessagesComposerRules.isOverflowing(String(repeating: "a", count: 201)))
        // NFD 로 들어온 한글도 NFC 로 센다.
        let nfd = "한글".decomposedStringWithCanonicalMapping
        #expect(nfd.unicodeScalars.count == 6 && MessageBody.length(nfd) == 2)

        #expect(MessagesComposerRules.sendAction(isComposing: true, canSendCommittedDraft: false) == .commitThenSend)
        #expect(MessagesComposerRules.sendAction(isComposing: true, canSendCommittedDraft: true) == .commitThenSend)
        #expect(MessagesComposerRules.sendAction(isComposing: false, canSendCommittedDraft: true) == .send)
        #expect(MessagesComposerRules.sendAction(isComposing: false, canSendCommittedDraft: false) == .none)
    }

    // MARK: 사람 찾기

    @Test("사람 찾기: 빈 검색어는 근무 중 먼저·이름순, 부분 일치는 대소문자 무시, 자음만 치면 초성 검색")
    func directoryFilter() {
        func person(_ id: String, _ name: String, working: Bool) -> PokeDirectoryEntry {
            [PokeDirectoryRow(userId: id, displayName: name, avatarUrl: nil, isWorking: working)].toPokeDirectoryEntries()[0]
        }
        let entries = [person("1", "한결", working: false), person("2", "소라", working: true),
                       person("3", "Mina", working: false), person("4", "하린", working: true)]
        let all = MessagesDirectoryRules.filter(entries, query: "")
        #expect(all.prefix(2).map(\.name) == ["소라", "하린"], "근무 중 먼저, 그 안에서 이름순")
        #expect(Set(all.suffix(2).map(\.name)) == ["Mina", "한결"])
        #expect(MessagesDirectoryRules.filter(entries, query: "  min ").map(\.name) == ["Mina"])
        #expect(MessagesDirectoryRules.filter(entries, query: "결").map(\.name) == ["한결"])
        #expect(MessagesDirectoryRules.filter(entries, query: "ㅎㄱ").map(\.name) == ["한결"])
        #expect(MessagesDirectoryRules.filter(entries, query: "ㅎ").map(\.name) == ["하린", "한결"])
        #expect(MessagesDirectoryRules.filter(entries, query: "없는사람").isEmpty)
        #expect(MessagesDirectoryRules.initials(of: "김 지우A") == "ㄱㅈㅇA")
    }

    // MARK: 대화 줄

    @Test("대화 줄: 날짜 구분선(KST) · 같은 쪽 같은 분은 마지막에만 시각 · 받은 묶음 첫 줄에만 아바타 · 1 은 읽음을 아는 서버의 안 읽힌 내 말에만")
    func conversationItems() {
        // 어제 23:59 KST 에 받은 말 하나, 오늘 14:00 에 받은 말 둘(같은 분), 14:01 내 말 둘(읽음·안 읽음).
        let messages = [
            Self.entry("y1", at: -(14 * 3600 + 6 * 60), unread: false),
            Self.entry("t1", at: -300, unread: false),
            Self.entry("t2", at: -290, unread: true),
            Self.entry("m1", mine: true, at: -240, readByPeer: true),
            Self.entry("m2", mine: true, at: -235, readByPeer: false),
        ]
        let items = MessagesConversationRules.items(messages: messages, pending: [], receiptsAvailable: true, now: Self.now)
        #expect(items.count == 7)
        guard case .day(_, let yesterday) = items[0], case .day(_, let today) = items[2] else {
            Issue.record("구분선 자리가 틀렸다: \(items.map(\.id))")
            return
        }
        #expect(yesterday == "어제" && today == "오늘")
        func line(_ index: Int) -> MessagesBubbleLine? {
            if case .bubble(let line) = items[index] { return line }
            return nil
        }
        #expect(line(1)?.clockText == "23:59")
        #expect(line(3)?.showsTime == false && line(4)?.showsTime == true, "같은 분의 받은 말은 마지막에만 시각")
        #expect(line(3)?.showsAvatar == true && line(4)?.showsAvatar == false)
        #expect(line(5)?.showsTime == false && line(6)?.showsTime == true)
        #expect(line(5)?.showsUnreadOne == false && line(6)?.showsUnreadOne == true)
        #expect(line(6)?.showsAvatar == false)
        // 읽음을 모르는 서버면 1 이 없다.
        let unknown = MessagesConversationRules.items(messages: messages, pending: [], receiptsAvailable: false, now: Self.now)
        #expect(!unknown.contains { if case .bubble(let l) = $0 { return l.showsUnreadOne } else { return false } })

        // 자리 말풍선: 마지막 날짜가 어제면 오늘 구분선을 먼저 세운다.
        let pending = MessagesPendingOutgoing(id: "l1", peerUserID: "p", body: "지금", createdAt: Self.now, state: .sending)
        let onlyYesterday = MessagesConversationRules.items(messages: [messages[0]], pending: [pending], receiptsAvailable: true, now: Self.now)
        #expect(onlyYesterday.map(\.id) == ["day-" + MessageThreadBuilder.dayKey(messages[0].createdAt, calendar: MobileRelativeTime.kst),
                                            "y1", "day-" + MessageThreadBuilder.dayKey(Self.now, calendar: MobileRelativeTime.kst), "pending-l1"])
        let withToday = MessagesConversationRules.items(messages: messages, pending: [pending], receiptsAvailable: true, now: Self.now)
        #expect(withToday.last?.id == "pending-l1" && withToday.count == 8)
        let empty = MessagesConversationRules.items(messages: [], pending: [pending], receiptsAvailable: true, now: Self.now)
        #expect(empty.count == 2)
    }

    @Test("빈 자리 문구: 실패 · 불러오는 중 · 없음(맥과 같은 문장)")
    func emptyStates() {
        #expect(MessagesConversationRules.emptyState(loaded: false, failed: true).title == "대화를 불러오지 못했어요")
        #expect(MessagesConversationRules.emptyState(loaded: false, failed: true).showsRetry)
        #expect(MessagesConversationRules.emptyState(loaded: false, failed: false).title == "불러오는 중…")
        #expect(MessagesConversationRules.emptyState(loaded: true, failed: true).title == "아직 주고받은 메시지가 없어요")
    }

    // MARK: 바닥 따라가기

    @Test("바닥 따라가기: 바닥 근처면 따라가고, 위로 올렸으면 버튼만, 내 말은 언제나 따라가고, 내용이 자란 측정은 '올림'이 아니다")
    func scrollFollow() {
        var follow = MessagesScrollFollow()
        follow.measured(contentHeight: 1000, distanceToBottom: 0)
        var follows = follow.lastItemChanged(isMine: false)
        #expect(follows)
        #expect(!follow.showsNewMessageButton)
        // 내용이 자라 바닥이 멀어졌다 → 올린 것이 아니다.
        follow.measured(contentHeight: 1080, distanceToBottom: 80)
        #expect(follow.isNearBottom)
        follows = follow.lastItemChanged(isMine: false)
        #expect(follows)
        // 같은 내용에서 멀어짐 = 사람이 올렸다.
        follow.measured(contentHeight: 1080, distanceToBottom: 400)
        #expect(!follow.isNearBottom)
        follows = follow.lastItemChanged(isMine: false)
        #expect(!follows)
        #expect(follow.showsNewMessageButton)
        follows = follow.lastItemChanged(isMine: true)
        #expect(follows, "내가 보낸 말은 따라간다")
        #expect(!follow.showsNewMessageButton)
        follow.measured(contentHeight: 1080, distanceToBottom: 400)
        _ = follow.lastItemChanged(isMine: false)
        follow.measured(contentHeight: 1080, distanceToBottom: 30)
        #expect(!follow.showsNewMessageButton, "스스로 바닥에 닿으면 버튼이 내려간다")
        // 키보드·입력칸이 틀을 줄여 바닥이 멀어졌다 → 올린 것이 아니다(따라가기 유지).
        follow.measured(contentHeight: 1080, distanceToBottom: 320, viewportChanged: true)
        #expect(follow.isNearBottom, "틀이 줄어든 것을 사람이 올린 것으로 읽었다")
        follows = follow.lastItemChanged(isMine: false)
        #expect(follows)
    }

    // MARK: 라우트 · 미리보기

    @Test("딥링크 → 메시지 탭 경로, 목록 미리보기는 줄바꿈을 한 칸으로 접는다")
    func routesAndPreview() {
        #expect(MessagesListRules.destinations(for: .messages) == [])
        #expect(MessagesListRules.destinations(for: .message(peerID: "p-1")) == [.conversation(peerID: "p-1")])
        #expect(MessagesListRules.destinations(for: .now) == nil)
        #expect(MessagesListRules.destinations(for: AingRoute(url: URL(string: "aingcheck://message/abc-1")!)!) == [.conversation(peerID: "abc-1")])
        #expect(MessagesListRules.preview("안녕\n\n  잘 지내?\t응") == "안녕 잘 지내? 응")
    }
}
