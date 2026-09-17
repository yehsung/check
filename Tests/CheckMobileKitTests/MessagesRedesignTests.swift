#if canImport(AppKit)
import AppKit
#endif
import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// w15 메시지 탭 재디자인(시안 B 03·04)의 순수 규칙과 계약: 상대별 개수 배지 · 목록 시각 · 근무 판(새 서버 호출 없음) · 대화 머리 한 줄 ·
/// 입력칸 안 보내기 원 · 탭 막대 숨김·시트 머리 통일(소스 계약).
@Suite struct MessagesRedesignTests {
    static let now = MobileClock.demoInstant

    static func entry(_ id: String, peer: String, mine: Bool = false, at offset: TimeInterval, unread: Bool? = nil) -> MessageHistoryEntry {
        MessageHistoryEntry(id: id, peerUserID: peer, peerName: peer.uppercased(), peerAvatarURL: nil, body: id,
                            createdAt: now.addingTimeInterval(offset), isMine: mine, readByPeer: nil, isUnread: unread)
    }

    static func row(_ id: String, _ name: String, working: Bool, center: String? = nil) -> PokeDirectoryRow {
        PokeDirectoryRow(userId: id, displayName: name, avatarUrl: nil, isWorking: working, center: center)
    }

    // MARK: 개수 배지

    @Test("상대별 개수: 합은 탭 배지와 같고, 키는 점 집합 안 — 이력 · 요약 · 낙관 읽음 · 옛 도장 모든 갈래")
    func perPeerCountsAgreeWithBadge() {
        let history = [
            Self.entry("a1", peer: "a", at: -300, unread: true),
            Self.entry("a2", peer: "a", at: -200, unread: true),
            Self.entry("m1", peer: "a", mine: true, at: -100),
            Self.entry("b1", peer: "b", at: -50, unread: false),
            Self.entry("c1", peer: "c", at: -10, unread: true),
        ]
        let order = ["a1": 0, "a2": 1, "m1": 2, "b1": 3, "c1": 4]
        let snapshot = MessageHistoryReadSnapshot(serial: 5, serverOrder: order)
        let summary = MessagesRulesTests.summary(#"{"status":"ok","total":7,"peers":[{"peer_user_id":"a","count":4,"last_epoch_ms":1},{"peer_user_id":"d","count":3,"last_epoch_ms":1},{"peer_user_id":"z","count":0,"last_epoch_ms":1}]}"#)
        let older = MessageUnreadSummarySnapshot(serial: 3, summary: summary)
        let newer = MessageUnreadSummarySnapshot(serial: 9, summary: summary)
        let cases: [(MessageHistoryReadSnapshot?, MessageUnreadSummarySnapshot?, [String: MessageOptimisticRead], [String: Date], [String: Int])] = [
            (snapshot, older, [:], [:], ["a": 2, "c": 1]),
            (snapshot, newer, [:], [:], ["a": 4, "d": 3]),
            (snapshot, older, ["a": MessageOptimisticRead(throughID: "a2", recordedSerial: 6)], [:], ["c": 1]),
            (snapshot, newer, ["a": MessageOptimisticRead(throughID: "a2", recordedSerial: 10)], [:], ["d": 3]),
            (nil, newer, [:], [:], ["a": 4, "d": 3]),
            (nil, nil, [:], [:], ["a": 2, "b": 1, "c": 1]),
            (nil, nil, [:], ["a": Self.now.addingTimeInterval(-250), "b": Self.now], ["a": 1, "c": 1]),
        ]
        for (historySnapshot, summary, optimistic, stamps, expected) in cases {
            let counts = MessagesBadgeRules.unreadCountsByPeer(history: history, historySnapshot: historySnapshot, summary: summary,
                                                               optimistic: optimistic, legacyStamps: stamps)
            let total = MessagesBadgeRules.unreadCount(history: history, historySnapshot: historySnapshot, summary: summary,
                                                       optimistic: optimistic, legacyStamps: stamps)
            let dots = MessageUnreadRules.unreadPeerIDs(history: history, historySnapshot: historySnapshot, summary: summary,
                                                        optimistic: optimistic, legacyStamps: stamps)
            #expect(counts == expected)
            #expect(counts.values.reduce(0, +) == total, "줄 배지 합이 탭 배지와 갈렸다")
            #expect(Set(counts.keys).isSubset(of: dots), "점이 없는 줄에 개수가 섰다")
        }
        // 요약이 개수 0 행을 보내면 점 집합에는 있다 → 화면은 최소 1.
        #expect(MessagesListRules.countBadge(isUnread: true, count: nil) == "1")
        #expect(MessagesListRules.countBadge(isUnread: true, count: 2) == "2")
        #expect(MessagesListRules.countBadge(isUnread: true, count: 120) == "99+")
        #expect(MessagesListRules.countBadge(isUnread: false, count: 3) == nil)
    }

    @Test("목록 시각은 대화 말풍선과 같은 눈금: 오늘은 24시간제 시각, 어제는 '어제' · 부제는 0 이면 없음")
    func listTimeAndSubtitle() {
        let calendar = MobileRelativeTime.kst
        let todayMorning = calendar.date(bySettingHour: 9, minute: 5, second: 0, of: Self.now)!
        #expect(MessagesListRules.timeText(todayMorning, now: Self.now) == "09:05")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayMorning)!
        #expect(MessagesListRules.timeText(yesterday, now: Self.now) == "어제")
        #expect(MessagesListRules.subtitle(unreadCount: 3) == "안 읽은 메시지 3")
        #expect(MessagesListRules.subtitle(unreadCount: 0) == nil)
        #expect(MessagesComposerRules.placeholder == "메시지 입력")
    }

    // MARK: 근무 판

    @Test("근무 판: 못 받았으면 모름(점·줄 없음) · 지금 탭 목록이 새 대화 목록을 덮고 · 우리 팀 상태가 목록을 이기고 · 끊김은 앰버 · 나는 뺀다")
    func presenceBoardMerge() {
        #expect(MessagesPresenceRules.board(nowWorking: [], teamMemberIDs: [], nowDirectory: nil, messagesDirectory: nil, me: "me") == .unknown)
        let empty = MessagesPresenceRules.board(nowWorking: [], teamMemberIDs: [], nowDirectory: [], messagesDirectory: nil, me: "me")
        #expect(empty.isKnown && empty.working.isEmpty, "받았는데 아무도 없으면 '아무도 없음'을 말할 수 있다")

        let messagesDirectory = [
            Self.row("x", "엑스", working: true, center: "busan"),
            Self.row("y", "와이", working: false, center: "seoul"),
            Self.row("me", "나", working: true),
        ].toPokeDirectoryEntries()
        let nowDirectory = [
            Self.row("y", "와이", working: true, center: nil),
            Self.row("t1", "팀원하나", working: true, center: "seoul"),
            Self.row("t2", "팀원둘", working: true, center: "busan"),
            Self.row("o", "가나다", working: true, center: "seoul"),
            Self.row("me", "나", working: true),
        ]
        let board = MessagesPresenceRules.board(
            nowWorking: [MessagesPresenceRules.Working(id: "t2", name: "팀원둘", avatarURL: nil, center: "busan", isStale: true)],
            teamMemberIDs: ["t1", "t2", "me"],
            nowDirectory: nowDirectory,
            messagesDirectory: messagesDirectory,
            me: "me"
        )
        #expect(board.isKnown)
        #expect(board.peers["me"] == nil && !board.working.contains { $0.id == "me" }, "나는 판에 없다")
        #expect(board.peers["x"] == MessagesPeerPresence(status: .working, center: "busan"), "지금 탭 목록에 없으면 새 대화 목록 값(센터는 서버값으로)")
        #expect(board.peers["y"] == MessagesPeerPresence(status: .working, center: "seoul"), "지금 탭 목록이 덮고, 모르는 센터는 앞 값을 지킨다")
        #expect(board.peers["t1"]?.status == .off, "우리 팀원은 팀 상태가 이긴다(목록은 근무 중이라 해도)")
        #expect(board.peers["t2"]?.status == .pending, "끊긴 우리 팀원은 앰버")
        #expect(board.working.map(\.id) == ["t2", "o", "x", "y"], "우리 팀(지금 탭 순서) 먼저, 그다음 이름순")
        #expect(board.working.first?.status == .pending)
    }

    @Test("대화 머리 한 줄: '근무 중 · 서울' · 끊김 · 근무 안 함 · 모르는 센터는 빼고 · 모르면 줄 없음")
    func headerLine() {
        #expect(MessagesPresenceRules.headerLine(MessagesPeerPresence(status: .working, center: "seoul")) == "근무 중 · 서울")
        #expect(MessagesPresenceRules.headerLine(MessagesPeerPresence(status: .pending, center: nil)) == "연결 끊김")
        #expect(MessagesPresenceRules.headerLine(MessagesPeerPresence(status: .off, center: "busan")) == "근무 안 함 · 부산")
        #expect(MessagesPresenceRules.headerLine(MessagesPeerPresence(status: .working, center: "jeju")) == "근무 중")
        #expect(MessagesPresenceRules.headerLine(nil) == nil)
    }

    // MARK: 입력칸

    @Test("보내기: 보이는 원은 입력칸 안의 작은 원(시안 30pt 안팎)이고 누르는 자리는 44pt 그대로 · 화살표는 보이는 원의 절반 이하")
    func sendButtonVisibleCircle() {
        for size in [14.0, 17, 23, 33, 53] {
            let metrics = MessagesComposerRules.sendButtonMetrics(scaledDiameter: 44 * size / 17)
            #expect(metrics.diameter >= MessagesComposerRules.minimumTouchTarget)
            #expect(metrics.visibleDiameter < metrics.diameter)
            #expect(metrics.visibleDiameter >= 30 && metrics.visibleDiameter <= 40)
            #expect(metrics.visibleGlyphSize <= metrics.visibleDiameter * 0.5)
            #expect(metrics.visibleGlyphSize >= 14, "화살표가 너무 작다")
        }
    }

    // MARK: 말풍선 줄바꿈

    @MainActor
    @Test("말풍선 줄바꿈: 한글은 어절 사이에서만 끊는다('10분만 / 가능할까요?') · 숫자와 한글 사이·느낌표 앞을 끊지 않는다 · 전략에 standard(pushOut)를 섞지 않는다")
    func bubbleWordWrap() {
        #expect(MessagesBubbleTextLayout.lineBreakStrategy == [.hangulWordPriority])
        /// `strategy`·`delegate` 는 기준선용 — 전략을 바꾸거나 끊기 대리자를 뗀 배치.
        func engine(_ text: String, strategy: NSParagraphStyle.LineBreakStrategy? = nil, delegate: Bool = true) -> MessagesBubbleTextLayout.Engine {
            let paragraph: NSParagraphStyle
            if let strategy {
                let custom = NSMutableParagraphStyle()
                custom.lineBreakMode = .byWordWrapping
                custom.lineBreakStrategy = strategy
                paragraph = custom
            } else {
                paragraph = MessagesBubbleTextLayout.paragraphStyle()
            }
            let engine = MessagesBubbleTextLayout.Engine()
            if !delegate { engine.layoutManager.delegate = nil }
            engine.set(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 16), .paragraphStyle: paragraph]))
            return engine
        }
        func trimmed(_ lines: [String]) -> [String] { lines.map { $0.trimmingCharacters(in: .whitespaces) } }

        let question = "오후에 디자인 리뷰 10분만 가능할까요?"
        let wrapped = engine(question)
        for width in stride(from: 180.0, through: 240.0, by: 10.0) {
            #expect(trimmed(wrapped.lines(width: width)) == ["오후에 디자인 리뷰 10분만", "가능할까요?"], "폭 \(width)")
            #expect(wrapped.fittingSize(width: width).width < 190, "말풍선 폭은 끊긴 긴 줄에 맞춰 줄어든다")
        }
        // 기준선: 전략이 없으면 음절에서 끊고, standard 를 섞으면 숫자와 한글 사이를 끊는다 — 위 단언이 전략에 달려 있다는 증거.
        #expect(trimmed(engine(question, strategy: [], delegate: false).lines(width: 210)) == ["오후에 디자인 리뷰 10분만 가능", "할까요?"])
        #expect(trimmed(engine(question, strategy: [.standard, .hangulWordPriority], delegate: false).lines(width: 210)) != ["오후에 디자인 리뷰 10분만", "가능할까요?"])
        #expect(trimmed(engine("어제 공유해 주신 시안 잘 봤어요! 2번이 제일", delegate: false).lines(width: 220)).first?.hasSuffix("2") == true,
                "기준선: 대리자 없이는 숫자와 한글 사이('2 / 번이')를 끊는다")

        // 한글·숫자 사이("2 / 번이")도 어절 안이면 끊지 않는다(hangulWordPriority 만으로는 폭 220·240 에서 끊겼다 — TextKit 실측).
        #expect(MessagesBubbleTextLayout.allowsWordBreak(before: 21, in: "어제 공유해 주신 시안 잘 봤어요! 2번이" as NSString) == false)
        #expect(MessagesBubbleTextLayout.allowsWordBreak(before: 20, in: "어제 공유해 주신 시안 잘 봤어요! 2번이" as NSString) == true)
        #expect(MessagesBubbleTextLayout.allowsWordBreak(before: 19, in: "https://github.com/yehsung" as NSString) == true, "한글 없는 링크는 시스템 판단")
        // 폭보다 긴 한글 덩어리·링크는 글자 단위로 접힌다(넘치지 않는다).
        let run = String(repeating: "가나다라마바사아자차카타파하", count: 3)
        let runLines = engine(run).lines(width: 120)
        #expect(runLines.count > 1 && runLines.joined() == run)
        let link = "https://github.com/yehsung/check/pull/1234/files#diff-abcdef 링크예요"
        #expect(engine(link).lines(width: 150).count > 1)

        let long = "어제 공유해 주신 시안 잘 봤어요! 2번이 제일 좋았어요. 색 대비만 조금 올리면 모바일에서도 잘 보일 것 같아요."
        let words = Set(long.split(separator: " ").map(String.init))
        for width in stride(from: 200.0, through: 280.0, by: 20.0) {
            let lines = trimmed(engine(long).lines(width: width))
            #expect(lines.joined(separator: " ") == long, "줄은 공백에서만 나뉜다(폭 \(width))")
            for line in lines {
                #expect(line.split(separator: " ").allSatisfy { words.contains(String($0)) }, "어절이 잘렸다: \(line)")
            }
        }
    }

    // MARK: 소스 계약

    @MainActor
    @Test("소스 계약: 대화는 공용 탭 막대 숨김 · 새 대화 시트는 공용 닫기 · 목록 줄은 꺾쇠·상대 시각·아바타 원 없이 공용 사람 부품")
    func sourceContracts() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesTab.swift")
        let conversation = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesConversationView.swift")
        let sheet = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesNewConversationSheet.swift")
        let composer = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesComposerView.swift")
        #expect(tab.contains("MessagesConversationView(store: store, peerID: peerID)\n                        .hidesTabBar(for: .conversation)"))
        for code in [tab, conversation, sheet, composer] {
            #expect(!code.contains("toolbar(.hidden, for: .tabBar)"), "탭 막대 숨김은 공용 hidesTabBar(for:) 로")
            #expect(!code.contains("AvatarView("), "사람은 PersonAvatar(점 · 이니셜 틴트)로")
        }
        #expect(sheet.contains(".sheetCloseButton {") && !sheet.contains("Button(\"닫기\")"), "시트 머리: 왼쪽 위 유리 ✕ 하나")
        #expect(!sheet.contains("chevron.right"), "사람 줄에 꺾쇠(설정 목록처럼 보였다)")
        #expect(tab.contains("PersonName(") && sheet.contains("PersonName("), "센터 배지는 이름 뒤(공용 PersonName)")
        #expect(!tab.contains("RelativeTimeText("), "목록 시각은 대화와 같은 눈금(timeText)")
        #expect(conversation.contains("MobileTheme.bubbleIn") && !conversation.contains(".stroke(line.entry.isMine"), "받은 말풍선은 bubbleIn 칠 · 테두리 없음")
        #expect(!composer.contains("MobileTheme.surface.ignoresSafeArea"), "입력 막대에 흰 띠를 깔지 않는다(비평 04)")
        #expect(conversation.contains("MessagesBubbleTextLayout.paragraphStyle()") && !conversation.contains("Text(text)"),
                "말풍선 본문은 TextKit 어절 줄바꿈(SwiftUI Text 는 음절에서 끊는다)")
        #expect(conversation.contains("UIPasteboard.general.string = body"), "복사는 원문 그대로(길게 눌러 메뉴 · 보이스오버 동작)")
        #expect(conversation.contains(".defaultScrollAnchor(.bottom, for: .alignment)"), "짧은 대화는 입력칸 쪽에 붙는다")
    }
}

/// 데모 장면(메시지 탭 라우트)에서 근무 판이 **지금 탭이 받아 둔 값**으로 채워지고, 메시지 탭이 사람 목록을 따로 부르지 않는다.
@MainActor
@Suite(.serialized) struct MessagesRedesignDemoTests {
    @Test("목록 장면: 소라 2 · 도윤 1 개수 · 한결·소라 초록 점 + 센터 · 지금 근무 중 셋 · 메시지 탭의 사람 목록 호출 0 · 금지 호출 0")
    func listPresenceFromNowStore() async {
        let demo = await MessagesDemoFixtureTests.make(route: "messages")
        defer { demo.tearDown() }
        _ = await baseWaitUntil { demo.model.now.hasFinishedRefreshAttempt && demo.model.now.refreshTask == nil }
        demo.store.listDidAppear()
        await demo.settle()
        #expect(demo.store.unreadCountsByPeer == [MessagesDemoFixtureTests.sora: 2, MessagesDemoFixtureTests.doyun: 1])
        let directoryCallsBefore = demo.requests.filter { $0.rpcName == "app_user_directory" }.count
        let board = demo.store.presenceBoard(now: demo.model.context.clock.now())
        #expect(board.isKnown)
        #expect(board.peers[MessagesDemoFixtureTests.hangyeol] == MessagesPeerPresence(status: .working, center: "seoul"))
        #expect(board.peers[MessagesDemoFixtureTests.sora] == MessagesPeerPresence(status: .working, center: "busan"))
        #expect(board.peers[MessagesDemoFixtureTests.minjae]?.status == .off)
        #expect(Set(board.working.map(\.name)) == ["한결", "소라", "하린"])
        #expect(!demo.store.directoryLoaded, "목록은 사람 목록을 따로 받지 않는다(지금 탭 값을 읽는다)")
        #expect(demo.requests.filter { $0.rpcName == "app_user_directory" }.count == directoryCallsBefore, "판을 읽는 것은 서버를 부르지 않는다")
        #expect(MobileForbiddenCalls.violations(in: demo.requests).isEmpty)
    }
}
