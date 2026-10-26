import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 콕/메시지 — **데이터 레인**(폰 1.0.13 · 인수인계 `message-poke-log-mobile-handoff.md`).
///
/// 이 스위트가 지키는 계약
///  ① 이력은 `message_history_with_pokes` 로 받고, 옛 서버(404/PGRST202)면 `message_history_with_reads` → `message_history`
///     사슬로 접는다. 접힌 창에서는 찌르기 줄이 없을 뿐 대화는 그대로 돈다.
///  ② 읽음은 `mark_conversation_read(p_peer, p_through_message, p_through_poke)` **한 번**이고, 찌르기 경계는
///     **화면에 보인 마지막 받은 찌르기 id** 다(보낸 것·지금 시각이 아니다). 옛 서버면 옛 `mark_messages_read` 로 접는다.
///  ③ 찌르기만 있는 사람도 대화 목록에 **행이 선다**(사용자 결정 2026-10-23 (가)) — 미리보기·최근 시각은 찌르기를 포함한다.
///  ④ 정렬은 4단(① 근무중+안읽음 → ② 근무안함+안읽음 → ③ 근무중+다읽음 → ④ 근무안함+다읽음)이고 **안 읽음은 메시지 ∪ 찌르기**다.
///     근무 여부를 모르는 창에서는 근무 축을 쓰지 않는다. `.pending`(연결 끊김)은 근무중이다.
///  ⑤ "안 읽은 메시지 N" 한 줄·탭 배지·줄 개수는 **메시지 전용**이다 — 합친 집합을 먹이지 않는다.
@MainActor
@Suite(.serialized) struct MessagesPokeLogStoreTests {
    typealias Row = MessagesStubServer.Row
    static let peerA = "peer-a"
    static let peerB = "peer-b"

    // MARK: - 스텁 재료

    /// 찌르기 행 하나(서버 `message_history_with_pokes` 의 13칸 — 메시지 12칸 + `kind`).
    struct Poke {
        var id: String
        var peer: String
        var name: String = "상대"
        var epoch: Int
        var mine: Bool
        /// 받은 찌르기에만 값이 있다(보낸 것은 서버가 null 을 준다).
        var unread: Bool?
        var kind: String = "poke"

        var json: String {
            func text(_ value: String) -> String { "\"\(value)\"" }
            func flag(_ value: Bool?) -> String { value.map { $0 ? "true" : "false" } ?? "null" }
            return """
            {"id":\(text(id)),"from_user":\(text(mine ? MessagesHarness.me : peer)),"to_user":\(text(mine ? peer : MessagesHarness.me)),\
            "body":null,"created_at":null,"is_mine":\(mine),"peer_user_id":\(text(peer)),"peer_display_name":\(text(name)),\
            "peer_avatar_url":null,"created_epoch":\(epoch),"read_by_peer":null,"unread":\(flag(mine ? nil : unread)),\
            "kind":\(text(kind))}
            """
        }
    }

    /// 메시지 행에 `kind` 칸을 붙인다(서버는 메시지 행을 `message_history_with_reads` 와 **한 글자도 다르지 않게** 준다 + kind).
    static func messageJSON(_ row: Row) -> String {
        String(row.json.dropLast()) + #","kind":"message"}"#
    }

    /// `message_history_with_pokes` 를 서버에 켠다. 행은 서버 순서(created_at asc, id asc)대로 준다.
    static func servePokes(_ server: MessagesStubServer, messages: [Row], pokes: [Poke]) {
        let text = "[" + (messages.map(messageJSON) + pokes.map(\.json)).joined(separator: ",") + "]"
        server.override("message_history_with_pokes") { _ in .json(text) }
    }

    /// `mark_conversation_read` 를 서버에 켠다.
    static func serveConversationRead(_ server: MessagesStubServer) {
        server.override("mark_conversation_read") { _ in
            .json(#"{"status":"ok","advanced":true,"unread":0,"poke_advanced":true,"poke_unread":0}"#)
        }
    }

    static func directoryJSON(_ people: [(id: String, name: String, working: Bool)]) -> String {
        "[" + people.map {
            #"{"user_id":"\#($0.id)","display_name":"\#($0.name)","avatar_url":null,"is_working":\#($0.working),"message_capable":true,"center":"seoul"}"#
        }.joined(separator: ",") + "]"
    }

    // MARK: - ① 이력 조회

    @Test("이력은 새 RPC 하나로 — 메시지와 찌르기가 함께 서고 옛 조회는 부르지 않는다")
    func historyComesFromPokesRPC() async {
        let h = await MessagesHarness.make { server in
            Self.servePokes(
                server,
                messages: [.received("a1", from: Self.peerA, at: 0, unread: false)],
                pokes: [
                    Poke(id: "p1", peer: Self.peerA, epoch: MessagesHarness.base + 5, mine: false, unread: false),
                    Poke(id: "p2", peer: Self.peerA, epoch: MessagesHarness.base + 9, mine: true, kind: "ultra"),
                ]
            )
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()

        #expect(h.count("message_history_with_pokes") >= 1)
        #expect(h.count("message_history_with_reads") == 0, "새 RPC 가 있는데 옛 이력을 또 불렀다")
        #expect(h.count("message_history") == 0)
        #expect(h.store.readReceiptsAvailable)
        #expect(h.store.pokeLogAvailable)
        #expect(h.store.history.map(\.id) == ["a1"], "찌르기 행이 메시지 배열로 샜다")
        #expect(h.store.pokeLog.map(\.id) == ["p1", "p2"])
        #expect(h.store.pokeLog.map(\.kind) == [.poke, .ultra])
        #expect(h.store.pokeLog(for: Self.peerA).map(\.id) == ["p1", "p2"])
        #expect(h.store.pokeChronology["a1"] != nil && h.store.pokeChronology["p2"] != nil, "선후 표에 두 갈래가 다 없다")
        h.expectNoForbiddenCalls()
    }

    @Test("옛 서버: 새 RPC 가 404 면 with_reads 로 접고 찌르기만 없다 — 그것도 없으면 옛 이력")
    func oldServerFallsBackThroughTheChain() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0), .sent("m1", to: Self.peerA, at: 5)])
            // 요약과 이력을 **같은 사실로** 맞춘다 — 둘은 나란히 날아가고 늦게 띄운 쪽이 이긴다(스토어 규칙).
            server.setSummary(MessagesStubServer.summary([(Self.peerA, 1)]))
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()

        #expect(h.count("message_history_with_pokes") >= 1, "새 RPC 를 아예 안 불렀다")
        #expect(h.count("message_history_with_reads") >= 1, "폴백 사슬이 끊겼다")
        #expect(h.store.history.map(\.id) == ["a1", "m1"], "접힌 서버에서 대화가 사라졌다")
        #expect(h.store.readReceiptsAvailable)
        #expect(!h.store.pokeLogAvailable)
        #expect(h.store.pokeLog.isEmpty)
        #expect(h.store.unreadPeerIDs == [Self.peerA])

        // 두 번째 칸도 없는 서버 — 옛 `message_history` 까지 간다.
        h.server.setWithReadsMissing(true)
        h.clock.advance(16)
        h.store.listDidDisappear()
        h.store.listDidAppear()
        await h.settle()
        #expect(h.count("message_history") >= 1)
        #expect(h.store.history.map(\.id) == ["a1", "m1"])
        #expect(!h.store.readReceiptsAvailable)
        #expect(!h.store.pokeLogAvailable)
        h.expectNoForbiddenCalls()
    }

    @Test("새 RPC 를 알던 서버가 다시 모르게 되면 찌르기 기록을 비운다(유령 줄·유령 정렬 금지)")
    func pokeLogIsClearedWhenServerForgets() async {
        let h = await MessagesHarness.make { server in
            Self.servePokes(
                server, messages: [],
                pokes: [Poke(id: "p1", peer: Self.peerA, epoch: MessagesHarness.base + 1, mine: false, unread: true)]
            )
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()
        #expect(h.store.pokeLog.map(\.id) == ["p1"])
        #expect(h.store.unreadPokePeerIDs == [Self.peerA])

        h.server.override("message_history_with_pokes") { _ in .missingFunction("message_history_with_pokes") }
        h.clock.advance(16)
        h.store.listDidDisappear()
        h.store.listDidAppear()
        await h.settle()
        #expect(h.store.pokeLog.isEmpty)
        #expect(!h.store.pokeLogAvailable)
        #expect(h.store.pokeChronology.isEmpty)
        #expect(h.store.unreadPokePeerIDs.isEmpty)
        h.expectNoForbiddenCalls()
    }

    // MARK: - ② 읽음 올리기

    @Test("읽음은 mark_conversation_read 한 번 — 경계는 마지막 받은 메시지·마지막 **받은** 찌르기")
    func markConversationReadCarriesBothBoundaries() async {
        let h = await MessagesHarness.make { server in
            Self.serveConversationRead(server)
            Self.servePokes(
                server,
                messages: [
                    .received("a1", from: Self.peerA, at: 0, unread: false),
                    .received("a2", from: Self.peerA, at: 10, unread: true),
                ],
                pokes: [
                    Poke(id: "p1", peer: Self.peerA, epoch: MessagesHarness.base + 12, mine: false, unread: true),
                    Poke(id: "p2", peer: Self.peerA, epoch: MessagesHarness.base + 14, mine: false, unread: true),
                    // 내가 보낸 것은 경계가 아니다(서버도 "그 사람이 나에게 보낸" 찌르기만 경계로 받는다).
                    Poke(id: "p3", peer: Self.peerA, epoch: MessagesHarness.base + 20, mine: true, kind: "ultra"),
                    // 다른 사람의 더 새 찌르기도 이 대화의 경계가 아니다.
                    Poke(id: "q1", peer: Self.peerB, epoch: MessagesHarness.base + 30, mine: false, unread: true),
                ]
            )
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()

        #expect(h.count("mark_conversation_read") == 1)
        #expect(h.count("mark_messages_read") == 0, "새 서버인데 옛 함수를 불렀다")
        let body = h.bodies("mark_conversation_read").first ?? ""
        #expect(body.contains(#""p_peer":"peer-a""#))
        #expect(body.contains(#""p_through_message":"a2""#))
        #expect(body.contains(#""p_through_poke":"p2""#), "찌르기 경계가 화면에 보인 마지막 받은 찌르기가 아니다: \(body)")
        #expect(!body.contains("p3"), "내가 보낸 찌르기를 경계로 올렸다")
        #expect(!body.contains("q1"), "다른 사람의 찌르기를 이 대화의 경계로 올렸다")
        // 올린 뒤에는 그 사람의 찌르기 안 읽음이 꺼지고, 아직 안 연 사람은 그대로다.
        #expect(h.store.unreadPokePeerIDs == [Self.peerB])
        h.expectNoForbiddenCalls()
    }

    @Test("안 본 찌르기만 있어도 대화를 열면 올린다 — 메시지 경계는 비우지 않는다")
    func pokeOnlyConversationStillMarks() async {
        let h = await MessagesHarness.make { server in
            Self.serveConversationRead(server)
            Self.servePokes(
                server,
                messages: [.received("a1", from: Self.peerA, at: 0, unread: false)],
                pokes: [Poke(id: "p1", peer: Self.peerA, epoch: MessagesHarness.base + 4, mine: false, unread: true)]
            )
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()

        #expect(h.count("mark_conversation_read") == 1, "찌르기만 안 봤는데 아무것도 안 올렸다")
        let body = h.bodies("mark_conversation_read").first ?? ""
        #expect(body.contains(#""p_through_poke":"p1""#))
        // 메시지 갈래는 **키 자체를 싣지 않는다**(코어 `MessageConversationReadMarkRequest` 의 encodeIfPresent ·
        // 인수인계 §2-2 "null 인 갈래는 움직이지 않는다"). 옛 `mark_messages_read` 와 달리 빈 경계가 "최신까지"가 아니다.
        #expect(!body.contains("p_through_message"), "안 움직여야 할 메시지 갈래에 값을 실었다: \(body)")
        #expect(h.store.unreadPokePeerIDs.isEmpty)
        h.expectNoForbiddenCalls()
    }

    @Test("옛 서버: mark_conversation_read 가 404 면 옛 mark_messages_read 로 접는다(본문은 옛 모양 그대로)")
    func markFallsBackToLegacyFunction() async {
        let h = await MessagesHarness.make { server in
            server.setRows([.received("a1", from: Self.peerA, at: 0), .received("a2", from: Self.peerA, at: 10)])
        }
        defer { h.tearDown() }
        h.store.conversationDidAppear(peerID: Self.peerA, token: UUID())
        await h.settle()

        #expect(h.count("mark_conversation_read") == 1, "새 함수를 먼저 시도하지 않았다")
        #expect(h.count("mark_messages_read") == 1)
        let body = h.bodies("mark_messages_read").first ?? ""
        #expect(body.contains(#""p_peer":"peer-a""#))
        #expect(body.contains(#""p_through":"a2""#))
        #expect(!body.contains("p_through_message"), "옛 함수에 새 칸 이름을 실었다")
        #expect(!body.contains("p_through_poke"))
        #expect(h.store.unreadPeerIDs.isEmpty)
        h.expectNoForbiddenCalls()
    }

    // MARK: - ③ 찌르기만 있는 사람도 행이 선다

    @Test("찌르기만 있는 사람도 대화 목록에 행이 선다 — 미리보기는 찌르기 문구, 최근 시각은 찌르기 시각")
    func pokeOnlyPeerGetsARow() async {
        let h = await MessagesHarness.make { server in
            Self.servePokes(
                server,
                messages: [.received("a1", from: Self.peerA, name: "가나", at: 0, unread: false)],
                pokes: [
                    Poke(id: "q1", peer: Self.peerB, name: "다라", epoch: MessagesHarness.base + 60, mine: false, unread: true),
                    Poke(id: "q2", peer: Self.peerB, name: "다라", epoch: MessagesHarness.base + 90, mine: true, kind: "ultra"),
                ]
            )
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()

        // 코어 묶음(메시지)만 보면 그 사람은 없다 — 행을 세우는 것은 폰 목록 규칙이다.
        #expect(h.store.threads.map(\.peerUserID) == [Self.peerA])
        let items = h.store.threadItems(now: h.clock.clock.now())
        #expect(Set(items.map(\.peerUserID)) == [Self.peerA, Self.peerB], "찌르기만 있는 사람의 행이 없다")
        let b = items.first { $0.peerUserID == Self.peerB }
        #expect(b?.peerName == "다라")
        #expect(b?.thread.messages.isEmpty == true)
        #expect(b?.previewText == "내가 울트라 찔렀어요", "미리보기가 마지막 항목의 문구가 아니다: \(b?.previewText ?? "-")")
        #expect(b?.lastActivityAt == Date(timeIntervalSince1970: TimeInterval(MessagesHarness.base + 90)))
        #expect(b?.lastIsMine == true)
        #expect(b?.previewNeedsMinePrefix == false, "찌르기 문구 앞에 '나: ' 를 또 붙였다")
        // 받은 찌르기가 마지막이면 상대 이름이 붙는다.
        #expect(MessagesSortRules.pokePreview(h.store.pokeLog(for: Self.peerB)[0]) == "다라님이 콕 찔렀어요")
        // 대화 머리도 그 사람을 안다(메시지가 한 줄도 없어도).
        #expect(h.store.peerName(for: Self.peerB) == "다라")
        h.expectNoForbiddenCalls()
    }

    @Test("미리보기 문구는 대화 줄과 같은 글자에서 시각만 뗀 것이다(두 벌로 갈리지 않는다)")
    func pokePreviewMatchesConversationLine() {
        let at = Date(timeIntervalSince1970: 1_789_621_000)
        for (kind, mine) in [(MessagePokeLogKind.poke, false), (.ultra, false), (.poke, true), (.ultra, true)] {
            let entry = MessagePokeLogEntry(
                id: "x", peerUserID: "p", peerName: "소라", createdAt: at, isMine: mine, kind: kind
            )
            let full = MessagePokeLogText.line(for: entry, calendar: MobileRelativeTime.kst)
            let preview = MessagesSortRules.pokePreview(entry)
            #expect(full.hasPrefix(preview))
            #expect(!preview.contains("·"), "목록 미리보기에 시각 꼬리가 남았다: \(preview)")
            #expect(preview.hasSuffix("찔렀어요"))
        }
    }

    // MARK: - ④ 4단 정렬

    @Test("정렬 원시 함수: 무리 번호 표 · .pending(앰버 점 · 연결 끊김)은 근무중 · 판을 모르면 근무 집합은 빈 집합")
    func sortPrimitives() {
        // 무리 표 — 근무를 **모르는 동안**에는 근무 축이 답을 못 바꾼다.
        #expect(MessagesSortRules.rank(isUnread: true, isWorking: true, workKnown: true) == 0)
        #expect(MessagesSortRules.rank(isUnread: true, isWorking: false, workKnown: true) == 1)
        #expect(MessagesSortRules.rank(isUnread: false, isWorking: true, workKnown: true) == 2)
        #expect(MessagesSortRules.rank(isUnread: false, isWorking: false, workKnown: true) == 3)
        #expect(MessagesSortRules.rank(isUnread: true, isWorking: false, workKnown: false)
            == MessagesSortRules.rank(isUnread: true, isWorking: true, workKnown: false))
        #expect(MessagesSortRules.rank(isUnread: false, isWorking: false, workKnown: false)
            == MessagesSortRules.rank(isUnread: false, isWorking: true, workKnown: false))

        let board = MessagesPresenceBoard(
            isKnown: true,
            peers: [
                "w": MessagesPeerPresence(status: .working, center: nil),
                "p": MessagesPeerPresence(status: .pending, center: nil),
                "o": MessagesPeerPresence(status: .off, center: nil),
            ],
            working: []
        )
        #expect(MessagesSortRules.workingPeerIDs(board) == ["w", "p"])
        #expect(MessagesSortRules.isWorking(nil) == false)
        #expect(MessagesSortRules.workingPeerIDs(.unknown).isEmpty)
    }

    @Test("정렬의 안 읽음에는 **안 본 찌르기**가 들어간다 — 메시지를 다 읽은 사람도 위로 올라온다")
    func unreadPokeLiftsThePeer() async {
        let h = await MessagesHarness.make { server in
            server.setDirectory(Self.directoryJSON([
                (Self.peerA, "가나", true), (Self.peerB, "다라", true),
            ]))
            Self.servePokes(
                server,
                messages: [
                    // A 의 말은 다 읽었고 더 오래됐다. B 의 말이 더 새것이다 — 최근순만 보면 B 가 위다.
                    .received("a1", from: Self.peerA, name: "가나", at: 0, unread: false),
                    .received("b1", from: Self.peerB, name: "다라", at: 100, unread: false),
                ],
                pokes: [Poke(id: "p1", peer: Self.peerA, name: "가나", epoch: MessagesHarness.base + 5, mine: false, unread: true)]
            )
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        h.store.loadDirectory()
        await h.settle()

        #expect(h.store.unreadPeerIDs.isEmpty, "메시지는 다 읽었는데 메시지 안 읽음이 섰다")
        #expect(h.store.unreadPokePeerIDs == [Self.peerA])
        #expect(h.store.sortUnreadPeerIDs == [Self.peerA])
        // 최근순 기준선은 거꾸로다 — 정렬이 실제로 일을 해야 통과한다.
        #expect(h.store.threads.map(\.peerUserID) == [Self.peerB, Self.peerA])
        let order = h.store.threadItems(now: h.clock.clock.now()).map(\.peerUserID)
        #expect(order == [Self.peerA, Self.peerB], "안 본 찌르기가 정렬을 올리지 못했다: \(order)")

        // ⑤ 배지·한 줄은 **메시지 전용**이다 — 찌르기뿐인 안 읽음을 "안 읽은 메시지"라고 말하지 않는다.
        #expect(h.store.badgeCount == 0)
        #expect(MessagesListRules.subtitle(unreadCount: h.store.badgeCount) == nil)
        #expect(h.store.unreadCountsByPeer.isEmpty)
        #expect(MessagesListRules.countBadge(isUnread: h.store.unreadPeerIDs.contains(Self.peerA), count: nil) == nil)
        h.expectNoForbiddenCalls()
    }

    @Test("사람 찾기 명부도 같은 안 읽음 집합으로 — 무리 안은 이름순(근무 축은 명부가 스스로 안다)")
    func directoryUsesTheSameUnreadSet() async {
        let h = await MessagesHarness.make { server in
            // 셋 다 근무중이라 가르는 축은 안 읽음과 이름뿐이다.
            server.setDirectory(Self.directoryJSON([
                ("peer-ga", "가나", true), ("peer-na", "나나", true), ("peer-da", "다나", true),
            ]))
            Self.servePokes(
                server, messages: [],
                pokes: [Poke(id: "p1", peer: "peer-da", name: "다나", epoch: MessagesHarness.base + 5, mine: false, unread: true)]
            )
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        h.store.loadDirectory(force: true)
        await h.settle()

        #expect(h.store.sortUnreadPeerIDs == ["peer-da"])
        // 안 읽음이 없으면 이름순이었을 자리에서, 안 본 찌르기가 '다나'를 맨 위로 올린다.
        #expect(h.store.filteredDirectory(query: "").map(\.name) == ["다나", "가나", "나나"])
        // 검색(초성 "ㄴ" — 셋 다 걸린다) 결과 안에서도 같은 순서다.
        #expect(h.store.filteredDirectory(query: "ㄴ").map(\.name) == ["다나", "가나", "나나"])
        h.expectNoForbiddenCalls()
    }

    // MARK: - ⑥ 대화창 줄 · ⑦ 차단 관문

    @Test("대화창 줄: 스토어를 지나 찌르기가 말풍선 사이에 끼고 · 찌르기만 있는 사람의 대화도 줄이 선다")
    func conversationItemsCarryPokes() async {
        let h = await MessagesHarness.make { server in
            Self.servePokes(
                server,
                messages: [
                    .received("a1", from: Self.peerA, name: "가나", body: "먼저 온 말", at: 0, unread: false),
                    .received("a2", from: Self.peerA, name: "가나", body: "나중 온 말", at: 120, unread: false),
                ],
                pokes: [
                    Poke(id: "p1", peer: Self.peerA, name: "가나", epoch: MessagesHarness.base + 60, mine: false, unread: false),
                    Poke(id: "q1", peer: Self.peerB, name: "다라", epoch: MessagesHarness.base + 30, mine: true, kind: "ultra"),
                ]
            )
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()

        let items = h.store.conversationItems(for: Self.peerA)
        #expect(items.map(\.id) == ["day-2026-9-17", "a1", "poke-p1", "a2"],
                "찌르기 줄이 말풍선 사이에 안 들어갔다: \(items.map(\.id))")
        let line = items.compactMap { item -> MessagesPokeLogLine? in
            if case .poke(let line) = item { return line } else { return nil }
        }.first
        #expect(line?.text == "가나님이 콕 찔렀어요 · 13:57")
        #expect(line?.symbol == "hand.point.right.fill")

        // 메시지가 한 줄도 없는 사람의 대화도 찌르기 줄만으로 선다(목록에서 그 행을 눌러 들어온 화면).
        let onlyPoke = h.store.conversationItems(for: Self.peerB)
        #expect(onlyPoke.map(\.id) == ["day-2026-9-17", "poke-q1"])
        #expect(onlyPoke.last?.isMine == true)
        h.expectNoForbiddenCalls()
    }

    @Test("차단한 사람의 찌르기는 기록·목록·정렬·대화에서 전부 사라진다(메시지와 같은 관문)")
    func blockedPeerPokesVanish() async {
        let h = await MessagesHarness.make { server in
            server.override("block_user") { _ in .json("null") }
            Self.servePokes(
                server,
                messages: [.received("a1", from: Self.peerA, name: "가나", at: 0, unread: false)],
                pokes: [
                    Poke(id: "q1", peer: Self.peerB, name: "다라", epoch: MessagesHarness.base + 60, mine: false, unread: true),
                    Poke(id: "p1", peer: Self.peerA, name: "가나", epoch: MessagesHarness.base + 70, mine: false, unread: true),
                ]
            )
        }
        defer { h.tearDown() }
        h.store.listDidAppear()
        await h.settle()

        // 차단 전: 찌르기만 있는 '다라'가 행을 세우고 안 읽음으로 위에 선다.
        #expect(h.store.threadItems(now: h.clock.clock.now()).map(\.peerUserID).contains(Self.peerB))
        #expect(h.store.unreadPokePeerIDs == [Self.peerA, Self.peerB])

        h.store.blockPeer(Self.peerB)
        await h.settle()

        #expect(h.store.visiblePokeLog.map(\.id) == ["p1"], "차단한 사람의 찌르기가 기록에 남았다")
        #expect(h.store.pokeLog(for: Self.peerB).isEmpty)
        #expect(h.store.unreadPokePeerIDs == [Self.peerA], "차단한 사람의 안 본 찌르기가 정렬용 안 읽음에 남았다")
        #expect(!h.store.sortUnreadPeerIDs.contains(Self.peerB))
        let rows = h.store.threadItems(now: h.clock.clock.now())
        #expect(rows.map(\.peerUserID) == [Self.peerA], "차단한 사람이 찌르기만으로 목록에 다시 섰다")
        #expect(h.store.conversationItems(for: Self.peerB).isEmpty, "차단한 사람의 대화창에 찌르기 줄이 남았다")
        #expect(h.store.peerName(for: Self.peerB) == nil, "차단한 사람의 이름을 찌르기 기록이 되살렸다")
        h.expectNoForbiddenCalls()
    }
}
