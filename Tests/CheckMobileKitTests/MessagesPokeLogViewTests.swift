@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰 1.0.13 **콕/메시지 화면 규칙** — 대화창 찌르기 줄 · 대화 목록 네 무리 정렬 · 찌르기만 있는 사람의 행 · 데모 픽스처 모양.
///
/// 재는 것은 **결과**다: 무슨 줄이 어떤 차례로, 어떤 글자로 서는가. 모양(함수를 부르는지)만 재는 단언은
/// 화면 파일이 `#if os(iOS)` 라 맥 스위트가 컴파일조차 못 하는 자리(저장소 메모 '폰 뷰는 맥 스위트가 못 본다')에만 쓴다.
///
/// ★ **앱 경로**(데모 픽스처 → 스토어 → 줄)를 지나는 장면 시험은 `MessagesDemoFixtureTests` 에 있다
///   (`pokeSceneGoesThroughTheStore` · `listScene`). 여기 있는 것은 그 아래의 순수 규칙이다.
@Suite struct MessagesPokeLogViewTests {
    static let now = MobileClock.demoInstant   // 2026-09-17 14:05 KST
    static let kst = MobileRelativeTime.kst
    static let me = "d0000000-0000-4000-8000-000000000001"

    static func message(
        _ id: String, peer: String, name: String? = nil, mine: Bool = false, at offset: TimeInterval,
        body: String? = nil, unread: Bool? = nil, readByPeer: Bool? = nil
    ) -> MessageHistoryEntry {
        MessageHistoryEntry(
            id: id, peerUserID: peer, peerName: name ?? peer.uppercased(), peerAvatarURL: nil,
            body: body ?? id, createdAt: now.addingTimeInterval(offset), isMine: mine,
            readByPeer: readByPeer, isUnread: unread
        )
    }

    static func poke(
        _ id: String, peer: String, name: String, mine: Bool = false, at offset: TimeInterval,
        kind: MessagePokeLogKind = .poke, unread: Bool? = nil
    ) -> MessagePokeLogEntry {
        MessagePokeLogEntry(
            id: id, peerUserID: peer, peerName: name, peerAvatarURL: nil,
            createdAt: now.addingTimeInterval(offset), isMine: mine, kind: kind,
            isUnread: mine ? nil : unread
        )
    }

    /// 안 본 찌르기가 있는 상대 — **코어 규칙**(`MessagePokeLogRules.unreadPeerIDs`)으로 센다.
    /// 화면이 서버 깃발만 보고 세면 방금 읽은 대화가 잠깐 다시 '안 읽음'으로 올라온다(낙관 읽음을 못 뺀다).
    static func pokeUnread(
        _ pokes: [MessagePokeLogEntry],
        chronology: [String: Int] = [:],
        optimistic: [String: MessageOptimisticRead] = [:],
        serial: Int = 10
    ) -> Set<String> {
        MessagePokeLogRules.unreadPeerIDs(
            log: pokes,
            snapshot: MessageHistoryReadSnapshot(serial: serial, serverOrder: chronology),
            optimistic: optimistic
        )
    }

    /// 줄 하나를 글자로 — 비교가 "무엇이 그려지는가"를 그대로 말하게.
    static func describe(_ items: [MessagesConversationItem]) -> [String] {
        items.map { item in
            switch item {
            case .day(_, let label): return "day:\(label)"
            case .poke(let line): return "poke:\(line.symbol):\(line.text)"
            case .pending(let pending): return "pending:\(pending.id)"
            case .bubble(let line):
                return "bubble:\(line.entry.id):\(line.clockText):time=\(line.showsTime):gap=\(line.startsGroup):one=\(line.showsUnreadOne)"
            }
        }
    }

    // MARK: - 1. 찌르기 줄 글자 · 아이콘

    @Test("찌르기 줄: 주어 + 술어 + 말풍선과 같은 눈금의 시각 · 아이콘은 콕 손가락/울트라 번개 · 미리보기는 시각을 뗀다")
    func pokeLineText() {
        // 2026-09-17 15:12 KST · 15:15 KST
        let received = Self.poke("p1", peer: "b1", name: "한결", at: 67 * 60, unread: true)
        let sentUltra = Self.poke("p2", peer: "b1", name: "한결", mine: true, at: 70 * 60, kind: .ultra)

        let one = MessagesConversationRules.pokeLine(for: received, calendar: Self.kst)
        let two = MessagesConversationRules.pokeLine(for: sentUltra, calendar: Self.kst)
        #expect(one.text == "한결님이 콕 찔렀어요 · 15:12")
        #expect(two.text == "내가 울트라 찔렀어요 · 15:15")
        #expect(one.symbol == "hand.point.right.fill")
        #expect(two.symbol == "bolt.fill")
        #expect(one.id == "poke-p1", "줄 id 가 말풍선 id 와 겹치면 ForEach 가 둘을 한 줄로 묶는다")

        // 목록 미리보기는 같은 문구에서 **시각만** 뗀다(행 오른쪽에 이미 시각이 있다).
        #expect(MessagesSortRules.pokePreview(received, calendar: Self.kst) == "한결님이 콕 찔렀어요")
        #expect(MessagesSortRules.pokePreview(sentUltra, calendar: Self.kst) == "내가 울트라 찔렀어요")
        #expect(!MessagesSortRules.pokePreview(received, calendar: Self.kst).contains("·"))
    }

    // MARK: - 2. 대화창: 말풍선 사이에 끼는 줄

    @Test("대화창: 찌르기가 시간 순서로 끼고 · 묶음을 끊어 앞 말풍선에 시각을 찍고 · 찌르기 뒤 말풍선은 추가 틈을 두지 않는다")
    func conversationInterleavesPokes() {
        let messages = [
            Self.message("m1", peer: "b1", name: "한결", at: -600, body: "먼저 보낸 말"),
            Self.message("m2", peer: "b1", name: "한결", mine: true, at: -120, body: "내 말 하나"),
            Self.message("m3", peer: "b1", name: "한결", mine: true, at: -110, body: "내 말 둘"),
        ]
        let pokes = [Self.poke("p1", peer: "b1", name: "한결", at: -115, unread: true)]
        let chronology = ["m1": 0, "m2": 1, "p1": 2, "m3": 3]

        let items = MessagesConversationRules.items(
            messages: messages, pokes: pokes, chronology: chronology, pending: [],
            receiptsAvailable: true, now: Self.now, calendar: Self.kst
        )
        #expect(Self.describe(items) == [
            "day:오늘",
            "bubble:m1:13:55:time=true:gap=false:one=false",
            "bubble:m2:14:03:time=true:gap=true:one=false",
            "poke:hand.point.right.fill:한결님이 콕 찔렀어요 · 14:03",
            "bubble:m3:14:03:time=true:gap=false:one=false",
        ])

        // 찌르기가 없으면 m2 는 m3 와 한 묶음이라 시각이 **m3 에만** 찍힌다 — 끼어든 줄이 묶음을 끊었다는 증거.
        let withoutPokes = MessagesConversationRules.items(
            messages: messages, pokes: [], chronology: [:], pending: [], receiptsAvailable: true,
            now: Self.now, calendar: Self.kst
        )
        #expect(Self.describe(withoutPokes) == [
            "day:오늘",
            "bubble:m1:13:55:time=true:gap=false:one=false",
            "bubble:m2:14:03:time=false:gap=true:one=false",
            "bubble:m3:14:03:time=true:gap=false:one=false",
        ])
    }

    @Test("찌르기 배열이 시간순이 아니어도 줄은 시간순이다 — 코어 병합은 '이미 정렬됐다'를 전제한다")
    func unsortedPokesAreSortedBeforeMerging() {
        let messages = [Self.message("m1", peer: "b1", name: "한결", at: -600, body: "말 하나")]
        // 일부러 거꾸로 넣는다(서버 순서를 믿지 않는다 · take_pokes 즉시 삽입은 꼬리에 붙는다).
        let shuffled = [
            Self.poke("p3", peer: "b1", name: "한결", mine: true, at: -60, kind: .ultra),
            Self.poke("p1", peer: "b1", name: "한결", at: -500),
            Self.poke("p2", peer: "b1", name: "한결", at: -300),
        ]
        let items = MessagesConversationRules.items(
            messages: messages, pokes: shuffled, chronology: [:], pending: [],
            receiptsAvailable: true, now: Self.now, calendar: Self.kst
        )
        #expect(items.map(\.id) == ["day-2026-9-17", "m1", "poke-p1", "poke-p2", "poke-p3"],
                "찌르기를 정렬 없이 병합에 넘겼다: \(items.map(\.id))")
    }

    @Test("찌르기가 없으면 날짜 줄·자리 말풍선까지 예전 그대로다")
    func noPokesKeepsTheOldShape() {
        let messages = [
            Self.message("y1", peer: "b1", name: "한결", at: -26 * 3600, body: "어제 말"),
            Self.message("m1", peer: "b1", name: "한결", at: -600, body: "오늘 말"),
            Self.message("m2", peer: "b1", name: "한결", mine: true, at: -300, body: "내 답", readByPeer: false),
        ]
        let pending = [MessagesPendingOutgoing(id: "s1", peerUserID: "b1", body: "보내는 중", createdAt: Self.now, state: .sending)]
        let items = MessagesConversationRules.items(
            messages: messages, pokes: [], chronology: [:], pending: pending, receiptsAvailable: true,
            now: Self.now, calendar: Self.kst
        )
        #expect(Self.describe(items) == [
            "day:어제",
            "bubble:y1:12:05:time=true:gap=false:one=false",
            "day:오늘",
            "bubble:m1:13:55:time=true:gap=false:one=false",
            "bubble:m2:14:00:time=true:gap=true:one=true",
            "pending:s1",
        ])
        // 읽음을 모르는 서버에서는 1 이 사라진다(그 조건은 찌르기와 무관하다).
        let noReceipts = MessagesConversationRules.items(
            messages: messages, pokes: [], chronology: [:], pending: pending, receiptsAvailable: false,
            now: Self.now, calendar: Self.kst
        )
        #expect(!Self.describe(noReceipts).contains { $0.contains("one=true") })
    }

    @Test("마지막 줄이 찌르기면 '내 것인가'는 그 찌르기를 따른다(바닥 따라가기)")
    func lastLineOwnership() {
        let messages = [Self.message("m1", peer: "b1", name: "한결", at: -600)]
        func last(mine: Bool) -> Bool? {
            MessagesConversationRules.items(
                messages: messages, pokes: [Self.poke("p1", peer: "b1", name: "한결", mine: mine, at: -60)],
                chronology: [:], pending: [], receiptsAvailable: true, now: Self.now, calendar: Self.kst
            ).last?.isMine
        }
        #expect(last(mine: true) == true)
        #expect(last(mine: false) == false)
    }

    // MARK: - 3. 대화 목록: 찌르기만 있는 사람도 행이 선다

    static func board(_ working: [String: PresenceStatus], known: Bool = true) -> MessagesPresenceBoard {
        guard known else { return .unknown }
        return MessagesPresenceBoard(
            isKnown: true,
            peers: working.mapValues { MessagesPeerPresence(status: $0, center: nil) },
            working: []
        )
    }

    static func thread(_ peer: String, name: String, _ messages: [MessageHistoryEntry]) -> MessageThread {
        MessageThread(peerUserID: peer, peerName: name, peerAvatarURL: nil, messages: messages)
    }

    /// 목록 줄 — 화면이 지나는 그 규칙 하나(`MessagesStore.threadItems` 가 부르는 것과 같은 함수·같은 인자).
    static func rows(
        threads: [MessageThread],
        pokes: [MessagePokeLogEntry],
        chronology: [String: Int] = [:],
        messageUnreadPeerIDs: Set<String> = [],
        unreadCounts: [String: Int] = [:],
        presence: MessagesPresenceBoard
    ) -> [MessagesThreadItem] {
        MessagesThreadListRules.rows(
            threads: threads, pokes: pokes, chronology: chronology,
            messageUnreadPeerIDs: messageUnreadPeerIDs,
            pokeUnreadPeerIDs: pokeUnread(pokes, chronology: chronology),
            unreadCounts: unreadCounts,
            workingPeerIDs: MessagesSortRules.workingPeerIDs(presence),
            workKnown: presence.isKnown,
            now: now, calendar: kst
        )
    }

    @Test("찌르기만 있는 사람: 행이 서고 · 미리보기가 찌르기 문구 · 시각이 그 찌르기 · 숫자 배지는 안 단다")
    func pokeOnlyPeerGetsRow() throws {
        let threads = [Self.thread("b1", name: "한결", [Self.message("m1", peer: "b1", name: "한결", at: -600, body: "오늘 말")])]
        let pokes = [
            Self.poke("p1", peer: "b5", name: "하린", at: -300, unread: true),
            Self.poke("p2", peer: "b5", name: "하린", at: -120, kind: .ultra, unread: true),
        ]
        let rows = Self.rows(
            threads: threads, pokes: pokes, chronology: ["p1": 0, "p2": 1],
            presence: Self.board(["b1": .working, "b5": .off])
        )
        #expect(rows.map(\.peerUserID) == ["b5", "b1"], "찌르기만 있는 사람의 행이 없거나 안 읽음이 위로 안 간다")
        let harin = rows[0]
        #expect(harin.peerName == "하린")
        #expect(harin.thread.messages.isEmpty)
        #expect(harin.previewText == "하린님이 울트라 찔렀어요", "미리보기가 그 스레드의 가장 최근 항목이 아니다")
        #expect(harin.timeText == "14:03", "스레드 '최근' 시각이 찌르기를 포함한 마지막 활동이 아니다")
        #expect(harin.isUnread)
        #expect(harin.countBadge == nil, "안 읽음이 찌르기뿐인데 '안 읽은 메시지' 숫자가 섰다")
        #expect(!harin.previewNeedsMinePrefix)

        // 보이스오버도 거짓말하지 않는다(인수인계 §6-4).
        let label = MessagesThreadListRules.accessibilityText(row: harin, presenceLine: nil)
        #expect(label == "하린, 안 본 찌르기, 하린님이 울트라 찔렀어요, 14:03")
        #expect(!label.contains("안 읽은 메시지"))

        // 메시지 안 읽음이 있는 행은 지금처럼 숫자를 단다.
        let withMessages = Self.rows(
            threads: threads, pokes: pokes, chronology: ["p1": 0, "p2": 1],
            messageUnreadPeerIDs: ["b1"], unreadCounts: ["b1": 3],
            presence: Self.board(["b1": .working, "b5": .off])
        )
        let hangyeol = try #require(withMessages.first { $0.peerUserID == "b1" })
        #expect(hangyeol.countBadge == "3")
        #expect(MessagesThreadListRules.accessibilityText(row: hangyeol, presenceLine: "근무 중")
            == "한결, 근무 중, 안 읽은 메시지 3개, 오늘 말, 13:55")
    }

    @Test("내가 찌른 것만 있는 사람도 행은 서지만 안 읽음은 아니다 · 미리보기는 '내가'")
    func myOwnPokeMakesRowButNotUnread() {
        let rows = Self.rows(
            threads: [], pokes: [Self.poke("p1", peer: "b7", name: "태오", mine: true, at: -60, kind: .ultra)],
            presence: Self.board(["b7": .off])
        )
        #expect(rows.map(\.previewText) == ["내가 울트라 찔렀어요"])
        #expect(rows.map(\.isUnread) == [false])
        #expect(rows.map(\.lastIsMine) == [true])
        #expect(!rows[0].previewNeedsMinePrefix, "찌르기 문구는 주어를 이미 말한다 — '나: 내가 울트라 찔렀어요'")

        // 서버가 **보낸** 찌르기에 안 읽음을 실어 보내도 세지 않는다(그 칸은 받은 것에만 뜻이 있다 — 코어 규약).
        // 안 그러면 내가 맥에서 찌른 사람이 폰 목록 맨 위에 '안 읽음'으로 올라온다.
        let mineButFlagged = MessagePokeLogEntry(
            id: "x1", peerUserID: "b7", peerName: "태오", createdAt: Self.now.addingTimeInterval(-60),
            isMine: true, kind: .ultra, isUnread: true
        )
        #expect(Self.pokeUnread([mineButFlagged]).isEmpty)
        let flaggedRows = Self.rows(threads: [], pokes: [mineButFlagged], presence: Self.board(["b7": .off]))
        #expect(flaggedRows.map(\.isUnread) == [false])
    }

    @Test("낙관 읽음: 방금 연 대화의 안 본 찌르기는 서버가 그 사실을 보기 전까지 '안 읽음'으로 되돌아오지 않는다")
    func optimisticReadKeepsThePeerDown() {
        let pokes = [
            Self.poke("p1", peer: "b5", name: "하린", at: -300, unread: true),
            Self.poke("q1", peer: "b6", name: "은비", at: -200, unread: true),
        ]
        let chronology = ["p1": 0, "q1": 1]
        // 서버 깃발만 보면 둘 다 안 읽음이다.
        #expect(Self.pokeUnread(pokes, chronology: chronology) == ["b5", "b6"])

        // 하린 대화를 열어 p1 까지 올렸다(아직 서버 조회가 그 사실을 모른다 — 정산 번호가 스냅샷보다 뒤).
        let optimistic = ["b5": MessageOptimisticRead(throughID: "p1", recordedSerial: 11, settledSerial: 12)]
        #expect(Self.pokeUnread(pokes, chronology: chronology, optimistic: optimistic, serial: 10) == ["b6"],
                "낙관 읽음을 안 빼서 방금 읽은 대화가 다시 '안 읽음'으로 올라온다")

        let rows = MessagesThreadListRules.rows(
            threads: [], pokes: pokes, chronology: chronology,
            messageUnreadPeerIDs: [],
            pokeUnreadPeerIDs: Self.pokeUnread(pokes, chronology: chronology, optimistic: optimistic, serial: 10),
            unreadCounts: [:],
            workingPeerIDs: ["b5", "b6"], workKnown: true, now: Self.now, calendar: Self.kst
        )
        #expect(rows.map(\.peerUserID) == ["b6", "b5"])
        #expect(rows.map(\.isUnread) == [true, false])
    }

    @Test("목록 재료도 찌르기 배열의 순서를 믿지 않는다 — 미리보기·최근 시각은 **진짜** 마지막 찌르기다")
    func listRowSortsPokesItself() {
        // 일부러 거꾸로 넣는다(묶음의 `last` 를 그냥 믿으면 가운데 것이 마지막 활동이 된다).
        let shuffled = [
            Self.poke("p3", peer: "b5", name: "하린", mine: true, at: -60, kind: .ultra),
            Self.poke("p1", peer: "b5", name: "하린", at: -500, unread: true),
            Self.poke("p2", peer: "b5", name: "하린", at: -300, unread: true),
        ]
        let rows = Self.rows(threads: [], pokes: shuffled, presence: Self.board(["b5": .off]))
        #expect(rows.map(\.previewText) == ["내가 울트라 찔렀어요"],
                "미리보기가 진짜 마지막 찌르기가 아니다: \(rows.map(\.previewText))")
        #expect(rows[0].lastActivityAt == Self.now.addingTimeInterval(-60))
        #expect(rows[0].timeText == "14:04")
        #expect(rows[0].pokes.map(\.id) == ["p1", "p2", "p3"], "줄이 들고 있는 기록이 시간순이 아니다")
    }

    @Test("마지막 활동이 메시지면 미리보기는 본문 그대로(찌르기가 더 오래됐을 때)")
    func latestActivityWins() {
        let rows = Self.rows(
            threads: [Self.thread("b1", name: "한결", [Self.message("m1", peer: "b1", name: "한결", at: -60, body: "가장 최근 말")])],
            pokes: [Self.poke("p1", peer: "b1", name: "한결", at: -600)],
            presence: Self.board(["b1": .working])
        )
        #expect(rows.map(\.previewText) == ["가장 최근 말"])
        #expect(rows[0].timeText == "14:04")
    }

    // MARK: - 4. 네 무리 정렬

    /// 다섯 사람: 근무/안함 × 안읽음/다읽음 네 무리 + 같은 무리 안의 최근순을 한 판에서 잰다.
    static func sortingFixture() -> [MessageThread] {
        [
            Self.thread("w-unread-old", name: "근무안읽음옛", [Self.message("a", peer: "w-unread-old", at: -900)]),
            Self.thread("w-unread-new", name: "근무안읽음새", [Self.message("b", peer: "w-unread-new", at: -60)]),
            Self.thread("o-unread", name: "비번안읽음", [Self.message("c", peer: "o-unread", at: -30)]),
            Self.thread("w-read", name: "근무다읽음", [Self.message("d", peer: "w-read", at: -10)]),
            Self.thread("o-read", name: "비번다읽음", [Self.message("e", peer: "o-read", at: -5)]),
        ]
    }

    @Test("정렬: ① 근무중+안읽음 ② 근무안함+안읽음 ③ 근무중+다읽음 ④ 근무안함+다읽음 · 같은 무리 안은 최근순")
    func fourGroupOrder() {
        let threads = Self.sortingFixture()
        let rows = Self.rows(
            threads: threads, pokes: [],
            messageUnreadPeerIDs: ["w-unread-old", "w-unread-new", "o-unread"],
            presence: Self.board([
                "w-unread-old": .working, "w-unread-new": .working, "o-unread": .off,
                "w-read": .working, "o-read": .off,
            ])
        )
        #expect(rows.map(\.peerUserID) == ["w-unread-new", "w-unread-old", "o-unread", "w-read", "o-read"])
        #expect(rows.map(\.group) == [0, 0, 1, 2, 3])
        // 최근순만으로 세우면 거꾸로다 — 무리가 실제로 먼저 쓰인다는 증거.
        #expect(rows.map(\.peerUserID) != threads.sorted { ($0.lastMessage?.createdAt ?? .distantPast) > ($1.lastMessage?.createdAt ?? .distantPast) }.map(\.peerUserID))
    }

    @Test(".pending(앰버 · 연결 끊김)은 근무중으로 친다")
    func pendingCountsAsWorking() {
        let threads = [
            Self.thread("amber", name: "앰버", [Self.message("a", peer: "amber", at: -900)]),
            Self.thread("off", name: "비번", [Self.message("b", peer: "off", at: -10)]),
        ]
        let rows = Self.rows(
            threads: threads, pokes: [], messageUnreadPeerIDs: ["amber", "off"],
            presence: Self.board(["amber": .pending, "off": .off])
        )
        #expect(rows.map(\.peerUserID) == ["amber", "off"])
        #expect(rows.map(\.group) == [0, 1])
        #expect(MessagesSortRules.workingPeerIDs(Self.board(["amber": .pending])) == ["amber"])
    }

    @Test("근무를 모르는 동안(팀 로드 전)에는 근무 축을 아예 안 쓴다 — 안 읽음만으로 두 무리")
    func unknownPresenceUsesTwoGroups() {
        let rows = Self.rows(
            threads: Self.sortingFixture(), pokes: [],
            messageUnreadPeerIDs: ["w-unread-old", "w-unread-new", "o-unread"],
            presence: .unknown
        )
        #expect(rows.map(\.group) == [0, 0, 0, 2, 2])
        #expect(rows.map(\.peerUserID) == ["o-unread", "w-unread-new", "w-unread-old", "o-read", "w-read"])
        #expect(MessagesSortRules.rank(isUnread: true, isWorking: false, workKnown: false)
            == MessagesSortRules.rank(isUnread: true, isWorking: true, workKnown: false))
        #expect(MessagesSortRules.rank(isUnread: false, isWorking: false, workKnown: false)
            == MessagesSortRules.rank(isUnread: false, isWorking: true, workKnown: false))
    }

    @Test("정렬 '안 읽음' 은 메시지 ∪ 찌르기다 — 둘 중 하나만 있어도 위로 간다")
    func unreadUnion() {
        #expect(MessagesSortRules.combinedUnreadPeerIDs(
            messages: ["a"],
            pokes: Self.pokeUnread([Self.poke("p", peer: "b", name: "B", at: -10, unread: true),
                                    Self.poke("q", peer: "c", name: "C", at: -10, unread: false)])
        ) == ["a", "b"])

        let threads = [
            Self.thread("msg", name: "메시지", [Self.message("m", peer: "msg", at: -10)]),
            Self.thread("poke", name: "찌르기", [Self.message("n", peer: "poke", at: -20)]),
            Self.thread("none", name: "없음", [Self.message("o", peer: "none", at: -5)]),
        ]
        let rows = Self.rows(
            threads: threads, pokes: [Self.poke("p", peer: "poke", name: "찌르기", at: -15, unread: true)],
            messageUnreadPeerIDs: ["msg"], unreadCounts: ["msg": 2],
            presence: Self.board(["msg": .off, "poke": .off, "none": .off])
        )
        // 안 읽음 무리(msg · poke)가 먼저, 그 안에서 최근순(msg 의 메시지 -10 > poke 의 찌르기 -15), 다 읽은 none 이 꼴찌.
        #expect(rows.map(\.peerUserID) == ["msg", "poke", "none"])
        #expect(rows.map(\.isUnread) == [true, true, false])
        #expect(rows.map(\.countBadge) == ["2", nil, nil])
        #expect(rows.map(\.group) == [1, 1, 3])
    }

    // MARK: - 5. 데모 픽스처 (심사원이 보는 장면의 재료)

    static let fixtureIndex = MobileDemoFixtures.load()

    static func fixtureData(_ key: String, scenario: String?) throws -> Data {
        let request = MobileStubRequest(method: "POST", host: MobileDemo.host,
                                        path: "/rest/v1/rpc/\(key)", query: "", headers: [:], bodyText: "{}")
        let entry = try #require(fixtureIndex.entry(for: request, scenario: scenario), "픽스처 rpc.\(key) 를 못 찾았다")
        return entry.data
    }

    @Test("데모 픽스처: rpc.message_history_with_pokes 가 색인에 있고 · kind='message' 행이 옛 조회와 값·순서가 한 글자도 다르지 않다")
    func demoFixtureKeepsMessageRowsIdentical() throws {
        let pokesData = try Self.fixtureData("message_history_with_pokes", scenario: "messages")
        let readsData = try Self.fixtureData("message_history_with_reads", scenario: "messages")
        let withPokes = try #require(JSONSerialization.jsonObject(with: pokesData) as? [[String: Any]])
        let withReads = try #require(JSONSerialization.jsonObject(with: readsData) as? [[String: Any]])

        let messageRows = withPokes.filter { ($0["kind"] as? String) == "message" }
        #expect(messageRows.count == withReads.count)
        for (lhs, rhs) in zip(messageRows, withReads) {
            var stripped = lhs
            stripped.removeValue(forKey: "kind")
            #expect(NSDictionary(dictionary: stripped) == NSDictionary(dictionary: rhs),
                    "kind='message' 행이 옛 조회와 갈렸다: \(lhs["id"] ?? "?")")
        }
        // 찌르기 행의 전선 규약: 본문·읽음 없음 · 받은 것에만 안 읽음.
        let pokeRows = withPokes.filter { ($0["kind"] as? String) != "message" }
        #expect(pokeRows.count == 4)
        for row in pokeRows {
            #expect(row["body"] is NSNull, "찌르기 행에 본문이 있다")
            #expect(row["read_by_peer"] is NSNull, "찌르기 행에 읽음 표시가 있다")
            #expect(["poke", "ultra"].contains(row["kind"] as? String ?? ""))
            if row["is_mine"] as? Bool == true { #expect(row["unread"] is NSNull, "보낸 찌르기에 안 읽음이 실렸다") }
        }
        // 이력 실패 장면(c1)도 새 조회에서 같이 실패해야 "다시 시도" 화면이 산다.
        let failing = try Self.fixtureData("message_history_with_pokes", scenario: "messages-d0000000-0000-4000-8000-0000000000c1")
        #expect((try? JSONSerialization.jsonObject(with: failing) as? [String: Any])??["__status"] as? Int == 500)
    }

    // MARK: - 6. 화면이 그 판정을 안 지나는 길을 막는다(소스 계약 — iOS 뷰는 맥이 컴파일조차 못 한다)

    @Test("대화창은 찌르기 줄을 **말풍선이 아닌** 전용 줄로 그린다 · 답장·복사·신고 메뉴가 안 붙는다")
    @MainActor func conversationDrawsPokeAsItsOwnRow() throws {
        let code = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesConversationView.swift")
        #expect(code.contains("store.conversationItems(for: peerID)"), "대화창이 스토어의 줄을 안 쓴다")
        #expect(code.contains("case .poke(let line):"), "찌르기 줄 갈래가 없다")
        #expect(code.contains("MessagesPokeLogRow(line: line)"), "찌르기를 전용 줄로 안 그린다")

        let rows = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesPokeLogView.swift")
        let row = try Self.block(of: "struct MessagesPokeLogRow", in: rows)
        #expect(row.contains("frame(maxWidth: .infinity)"), "찌르기 줄이 가운데로 안 퍼진다")
        #expect(row.contains("MobileTheme.label2"), "찌르기 줄이 회색이 아니다")
        #expect(!row.contains("contextMenu"), "찌르기 줄에 길게 누름 메뉴가 붙었다(신고·복사 대상이 아니다)")
        #expect(!row.contains("onReport"), "찌르기 줄이 신고 대상이 됐다")
        #expect(!row.contains("MessagesBubble"), "찌르기가 말풍선으로 그려진다")
    }

    @Test("목록은 정렬·미리보기·배지를 **규칙 하나**에서 받는다(뷰가 다시 세지 않는다)")
    @MainActor func listDoesNotReDecide() throws {
        let code = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesTab.swift")
        #expect(code.contains("store.threadItems(now: now)"),
                "목록이 새 줄 규칙을 안 쓴다 — 찌르기만 있는 사람의 행이 사라진다")
        let list = try Self.block(of: "struct MessagesListView", in: code)
        #expect(!list.contains("store.threads"), "목록이 스레드를 직접 써서 찌르기만 있는 사람을 빠뜨린다")
        #expect(!list.contains("MessagesListRules.countBadge("), "뷰가 배지를 다시 센다 — 찌르기뿐인 행에 '안 읽은 메시지' 숫자가 선다")
        #expect(!list.contains("unreadPeerIDs"), "뷰가 안 읽음을 다시 센다")
        let rowView = try Self.block(of: "struct MessagesThreadRow", in: code)
        #expect(!rowView.contains("MessagesListRules.preview("), "줄이 미리보기를 다시 만든다 — 찌르기 문구가 본문으로 읽힌다")
        #expect(!rowView.contains("MessagesListRules.timeText("), "줄이 시각을 다시 만든다 — 찌르기가 마지막 활동일 때 갈린다")
        #expect(rowView.contains("Text(row.previewText)"))
        #expect(rowView.contains("Text(row.timeText)"))
    }

    @Test("화면 레인 복제본은 남아 있지 않다 — 같은 일을 두 벌로 하면 한쪽만 고치는 날이 온다")
    @MainActor func noDuplicateDisplayLane() throws {
        for name in ["MessagesPokeDisplayRules", "MessagesPokeConversationAssembly", "MessagesPokeLogBridge",
                     "MessagesPokeConversationItem", "MessagesPokeListRow", "MessagesReadWire",
                     "MessagesConversationReadRequest"] {
            let hits = try IntegrationContractTests.files(containing: [name], under: "Sources/CheckMobileKit")
            #expect(hits.isEmpty, "걷어낸 복제본 '\(name)' 가 \(hits) 에 되살아났다")
        }
        // 읽음은 코어 전선 하나로 나간다(폰이 자기 모양을 또 만들지 않는다).
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MessagesStore.swift")
        #expect(store.contains("service.markConversationRead("), "읽음이 코어 `markConversationRead` 를 안 쓴다")
        #expect(!store.contains("/rest/v1/rpc/mark_conversation_read"), "폰이 전선 경로를 또 적었다")
    }

    /// 선언 머리부터 중괄호가 닫히는 곳까지(글자 수로 자른 창은 남의 줄을 읽는다).
    private static func block(of marker: String, in source: String) throws -> String {
        let hit = try #require(source.range(of: marker), "대조: '\(marker)' 를 못 찾았다(이름이 바뀌었나)")
        var depth = 0
        var started = false
        var out = ""
        for character in source[hit.upperBound...] {
            if character == "{" {
                depth += 1
                started = true
            }
            if started { out.append(character) }
            if character == "}" {
                depth -= 1
                if depth == 0 { break }
            }
        }
        #expect(started, "대조: '\(marker)' 뒤에 블록이 없다")
        return out
    }
}
