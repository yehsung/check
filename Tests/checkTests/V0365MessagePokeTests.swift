import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.65 — 콕/메시지 목록 정렬 · 대화창 찌르기 기록(맥).
//
// 사용자 결정(2026-10-23, 원문):
//   "콕/메세지 창에서 메세지 안읽은 사람들이 제일 상단에 떴으면 좋겠어. 상단 정렬 순위가 1. 근무중이면서 메세지 아직 안읽은 사람,
//    2. 근무중 아니면서 메세지 아직 안읽은 사람, 3. 근무중이면서 메세지 다 읽거나 없는사람, 4. 근무중 아니면서 메세지 다 읽거나 없는 사람."
//   "사람들이 서로 찌르거나 울트라 찌르기 한거 메세지창에 기록으로 남게끔 해줘. 물론 이것도 24시간 뒤에 기록 사라지는건 동일하고."
//   묻고 정한 것: 안 본 찌르기도 '안 읽음'으로 친다 · 맥 먼저(폰은 다음 판).
//
// 이 파일이 재는 것: ① 정렬 네 무리 · 이름 동률 · 안 읽음 합집합 · 메뉴바 점은 메시지만 ② 디코드(새 칸 없음 · 깨짐 · 모르는 종류)
// ③ 대화창 끼워 넣기 순서(같은 초 동률)·문구 ④ 읽음 올리기 호출 본문 ⑤ 옛 서버 폴백 ⑥ 새로 고침 박자(왕복 수) ⑦ 렌더(목록 · 대화)
// ⑧ 서버 정의와 클라 전선의 짝(마이그레이션 — CHECK_MIGRATIONS_DIR) ⑨ 버전 · CHANGELOG 게이트.
//
// 네트워크는 `MessageReadStubProtocol`(호스트별 스크립트)이다 — 스크립트하지 않은 새 함수는 **없는 서버**(404 PGRST202)가 기본이다.

private typealias Fx = MessageReadFixture

private let v365Now = MessageReadFixture.now
private let v365Epoch = Int(MessageReadFixture.now.timeIntervalSince1970)

// MARK: - 픽스처

private enum V365Fx {
    /// 새 조회의 메시지 행(= with_reads 행 + kind 'message').
    static func messageRow(
        id: String, peer: String, isMine: Bool, body: String = "안녕", epoch: Int = v365Epoch,
        readByPeer: Bool? = nil, unread: Bool? = nil, name: String = "상대", createdAt: String? = nil
    ) -> [String: Any] {
        var row = Fx.readsRow(id: id, peer: peer, isMine: isMine, body: body, epoch: epoch,
                              readByPeer: readByPeer, unread: unread, name: name)
        row["kind"] = "message"
        if let createdAt { row["created_at"] = createdAt }
        return row
    }

    /// 새 조회의 찌르기 행(서버 계약: body·read_by_peer null · unread 는 받은 것만).
    static func pokeRow(
        id: String, peer: String, isMine: Bool, kind: String = "poke", epoch: Int = v365Epoch,
        unread: Bool? = nil, name: String = "상대", createdAt: String = "2026-09-21T12:00:00.123456+00:00"
    ) -> [String: Any] {
        [
            "id": id,
            "from_user": isMine ? Fx.me : peer,
            "to_user": isMine ? peer : Fx.me,
            "body": NSNull(),
            "created_at": createdAt,
            "is_mine": isMine,
            "peer_user_id": peer,
            "peer_display_name": name,
            "peer_avatar_url": NSNull(),
            "created_epoch": epoch,
            "read_by_peer": NSNull(),
            "unread": unread.map { $0 as Any } ?? NSNull(),
            "kind": kind
        ]
    }

    /// take_pokes 찌르기 행.
    static func takenPokeRow(id: String, from peer: String, epoch: Int, kind: String = "normal", name: String = "상대") -> [String: Any] {
        [
            "id": id, "from_user": peer, "from_display_name": name, "from_avatar_url": NSNull(),
            "created_epoch": epoch, "kind": kind, "body": NSNull(), "from_character": NSNull()
        ]
    }

    static func reply(_ rows: [[String: Any]]) -> MessageReadStubProtocol.Reply {
        Fx.historyReply(rows)
    }

    static func conversationMarkReply() -> MessageReadStubProtocol.Reply {
        MessageReadStubProtocol.Reply(body: Fx.json([
            "status": "ok", "advanced": true, "unread": 0, "poke_advanced": true, "poke_unread": 0
        ]))
    }

    static let kst: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    static func entry(_ id: String, _ name: String, working: Bool) -> PokeDirectoryEntry {
        PokeDirectoryEntry(userID: id, name: name, avatarURL: nil, isWorking: working)
    }

    static func message(
        _ id: String, peer: String = Fx.peerA, isMine: Bool = false, secondsAgo: TimeInterval, isUnread: Bool? = nil,
        body: String = "점심 드셨어요?"
    ) -> MessageHistoryEntry {
        MessageHistoryEntry(
            id: id, peerUserID: peer, peerName: "민수", peerAvatarURL: nil, body: body,
            createdAt: v365Now.addingTimeInterval(-secondsAgo), isMine: isMine, isUnread: isMine ? nil : isUnread
        )
    }

    static func poke(
        _ id: String, peer: String = Fx.peerA, isMine: Bool = false, kind: MessagePokeLogKind = .poke,
        secondsAgo: TimeInterval, isUnread: Bool? = nil, name: String = "민수"
    ) -> MessagePokeLogEntry {
        MessagePokeLogEntry(
            id: id, peerUserID: peer, peerName: name, createdAt: v365Now.addingTimeInterval(-secondsAgo),
            isMine: isMine, kind: kind, isUnread: isMine ? nil : isUnread
        )
    }
}

@MainActor
private func v365Count(_ host: String, _ rpc: String) -> Int {
    MessageReadStubProtocol.count(host: host, rpc: rpc)
}

@MainActor
private func v365OpenConversation(_ store: WorkTimerStore, peer: String = Fx.peerA) async {
    store.isMenuPresented = true
    store.messageConversationViewDidAppear(UUID())
    store.openMessagePanel(peer: peer)
    await messageReadWait { store.messageHistoryLoaded && messageReadIdle(store) }
}

private func v365Service(host: String) -> SupabaseWorkService {
    SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: MessageReadStubProtocol.session()
    )
}

/// 스텁 서버의 한 비트 상태(읽음이 올랐는가 · 찌르기가 소비됐는가 — 다음 조회가 그 사실을 반영하게).
private final class V365Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

/// `from` 뒤부터 그 뒤 첫 `to` 직전까지.
private func v365Region(_ source: String, from start: String, to end: String) -> String? {
    guard let head = source.range(of: start) else { return nil }
    let tail = source.range(of: end, range: head.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
    return String(source[head.upperBound..<tail])
}

/// 마지막 같은 rpc 호출 본문의 키 집합과 값.
@MainActor
private func v365LastBody(_ host: String, _ rpc: String) -> [String: Any] {
    MessageReadStubProtocol.calls(host: host, rpc: rpc).last?.json ?? [:]
}

// MARK: - ① 정렬 · 합집합 · 메뉴바 점

@MainActor
@Suite("V0365MessagePokeSort")
struct V0365MessagePokeSortTests {
    /// 네 무리 + 같은 무리 안 이름(자연 순서 "사람2" < "사람10") + **이름이 같으면 id**.
    @Test func 네_무리_순서와_이름_동률() {
        let entries = [
            V365Fx.entry("u-d2", "라온", working: false),             // ④
            V365Fx.entry("u-c1", "다온", working: true),              // ③
            V365Fx.entry("u-b1", "나래", working: false),             // ②
            V365Fx.entry("u-a2", "사람10", working: true),            // ①
            V365Fx.entry("u-a1", "사람2", working: true),             // ①
            V365Fx.entry("u-d1", "같은이름", working: false),          // ④ (id 로 깬다)
            V365Fx.entry("u-d0", "같은이름", working: false),          // ④
            V365Fx.entry("u-b0", "가람", working: false),             // ②
        ]
        let unread: Set<String> = ["u-a1", "u-a2", "u-b0", "u-b1"]
        let order = entries.sortedForPokeDisplay(unreadPeerIDs: unread, workKnown: true).map(\.userID)
        #expect(order == ["u-a1", "u-a2", "u-b0", "u-b1", "u-c1", "u-d0", "u-d1", "u-d2"], "\(order)")
        // 입력 순서를 뒤집어도 같은 답(전순서 — 새로고침마다 행이 자리를 바꾸지 않는다).
        #expect(entries.reversed().sortedForPokeDisplay(unreadPeerIDs: unread, workKnown: true).map(\.userID) == order)
        // 명시적 빈 집합(스토어의 저장 순서 · 폰 두 자리)은 예전 그대로 근무중 → 이름.
        #expect(entries.sortedForPokeDisplay(unreadPeerIDs: [], workKnown: true).map(\.userID)
                == ["u-c1", "u-a1", "u-a2", "u-b0", "u-d0", "u-d1", "u-b1", "u-d2"])
    }

    /// 근무 여부를 모르면(`workKnown: false`) 근무 축을 건너뛴다 — 안 읽음 → 이름 **두 무리**(합의: 모름 = 안 읽음 → 이름).
    /// 근무 칸 값이 무엇이든 순서가 같아야 한다(모르는 값을 근무 축에 태우면 "근무중 아님"이 아래로 밀린다).
    @Test func 근무_여부를_모르면_안_읽음과_이름_두_무리() {
        let entries = [
            V365Fx.entry("u-d2", "라온", working: false),
            V365Fx.entry("u-c1", "다온", working: true),
            V365Fx.entry("u-b1", "나래", working: false),
            V365Fx.entry("u-a2", "사람10", working: true),
            V365Fx.entry("u-a1", "사람2", working: true),
            V365Fx.entry("u-d1", "같은이름", working: false),
            V365Fx.entry("u-d0", "같은이름", working: false),
            V365Fx.entry("u-b0", "가람", working: false),
        ]
        let unread: Set<String> = ["u-a1", "u-a2", "u-b0", "u-b1"]
        let order = entries.sortedForPokeDisplay(unreadPeerIDs: unread, workKnown: false).map(\.userID)
        // 안 읽음 무리: 가람 · 나래 · 사람2 · 사람10(근무중인 사람10·사람2 가 앞으로 오지 않는다). 나머지: 같은이름(id) · 다온 · 라온.
        #expect(order == ["u-b0", "u-b1", "u-a1", "u-a2", "u-d0", "u-d1", "u-c1", "u-d2"], "\(order)")
        // 근무 칸을 전부 뒤집어도 같은 답(근무 축을 정말 안 쓴다).
        let flipped = entries.map { V365Fx.entry($0.userID, $0.name, working: !$0.isWorking) }
        #expect(flipped.sortedForPokeDisplay(unreadPeerIDs: unread, workKnown: false).map(\.userID) == order)
        // 안 읽음이 없으면 이름 하나(id 로 동률을 깬다).
        #expect(entries.sortedForPokeDisplay(unreadPeerIDs: [], workKnown: false).map(\.userID)
                == ["u-b0", "u-d0", "u-d1", "u-b1", "u-c1", "u-d2", "u-a1", "u-a2"])
    }

    /// 정렬 입력 둘 다 **기본값이 없다**(명세 §3.0) — 기본값을 주면 인자를 안 넘긴 호출부(폰 두 자리 · 스토어)가 조용히 옛 2단으로 남고
    /// 시험은 초록이다. 기본값이 없으면 컴파일러가 부르는 자리를 다 세운다.
    @Test func 정렬_입력에_기본값이_없다() throws {
        let source = try v0331Source("SupabaseWorkModels.swift")   // 주석을 걷어낸 소스
        let parameters = try #require(v365Region(source, from: "func sortedForPokeDisplay(", to: ")"))
        #expect(parameters.replacingOccurrences(of: " ", with: "") == "unreadPeerIDs:Set<String>,workKnown:Bool", "\(parameters)")
        #expect(!parameters.contains("="), "정렬 입력에 기본값이 붙었다: \(parameters)")
    }

    /// 목록 순서와 행의 점은 **같은 두 집합**(메시지 ∪ 찌르기)을 본다. 찌르기만 있는 사람도 맨 위 무리다.
    @Test func 안_읽음_합집합이_순서와_점을_정한다() {
        let entries = [
            V365Fx.entry("m", "메시지만", working: false),
            V365Fx.entry("n", "없음", working: true),
            V365Fx.entry("p", "찌르기만", working: false),
        ]
        let sorted = PokePanelOrder.sorted(entries, unreadMessagePeerIDs: ["m"], unreadPokePeerIDs: ["p"]).map(\.userID)
        #expect(sorted == ["m", "p", "n"], "\(sorted)")

        #expect(PokeRowUnreadMark.of("m", unreadMessagePeerIDs: ["m"], unreadPokePeerIDs: ["m"]) == .messages)
        #expect(PokeRowUnreadMark.of("p", unreadMessagePeerIDs: ["m"], unreadPokePeerIDs: ["p"]) == .pokesOnly)
        #expect(PokeRowUnreadMark.of("n", unreadMessagePeerIDs: ["m"], unreadPokePeerIDs: ["p"]) == .none)
        #expect(PokeRowUnreadMark.pokesOnly.showsDot && PokeRowUnreadMark.messages.showsDot && !PokeRowUnreadMark.none.showsDot)
        // 찌르기만 있을 때 "메시지" 라고 말하지 않는다(보이스오버 = 툴팁).
        #expect(PokeRowUnreadMark.pokesOnly.help(name: "민수") == "민수님과의 대화 — 안 본 찌르기가 있어요")
        #expect(PokeRowUnreadMark.messages.help(name: "민수") == "민수님과의 대화 — 안 읽은 메시지가 있어요")
        #expect(PokeRowUnreadMark.none.help(name: "민수") == "민수님과의 대화 열기")
    }

    /// 스토어: 안 본 찌르기는 목록 합집합에만 든다 — 메뉴바 빨간 점(`hasUnreadMessages`)은 **메시지만**.
    @Test(.gomokuDefaultsCleanup)
    func 메뉴바_점은_메시지만_센다() {
        let store = makeMessageReadStore("v365-dot").store
        store.messagePokeLog = [V365Fx.poke("p1", peer: Fx.peerB, secondsAgo: 30, isUnread: true)]
        store.messagePokeLogSnapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["p1": 0])
        store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: [:])
        #expect(store.unreadPokePeerIDs == [Fx.peerB])
        #expect(store.unreadConversationPeerIDs == [Fx.peerB])
        #expect(store.unreadMessagePeerIDs.isEmpty)
        #expect(!store.hasUnreadMessages, "안 본 찌르기가 메뉴바 빨간 점을 켰다")

        store.messageHistory = [V365Fx.message("m1", peer: Fx.peerA, secondsAgo: 10, isUnread: true)]
        store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(serial: 2, serverOrder: ["m1": 0])
        #expect(store.hasUnreadMessages)
        #expect(store.unreadConversationPeerIDs == [Fx.peerA, Fx.peerB])

        // 차단으로 걷어낸 사람의 찌르기는 목록에도 없다.
        store.blockHiddenPeerIDs = [Fx.peerB]
        #expect(store.unreadPokePeerIDs.isEmpty)
        // 서버가 찌르기 기록을 모르면(스냅샷 nil) 찌르기 안 읽음도 없다.
        store.blockHiddenPeerIDs = []
        store.messagePokeLogSnapshot = nil
        #expect(store.unreadPokePeerIDs.isEmpty)
    }

    /// 목록 화면 배선(소스): 스토어의 찌르기 집합이 패널로 가고, 패널은 정렬 한 번에 두 집합을 넘긴다.
    @Test func 목록_배선() throws {
        let source = try v0331Source("CheckMenuView.swift")   // 주석을 걷어낸 소스
        #expect(source.contains("unreadPokePeerIDs: store.unreadPokePeerIDs,"), "스토어의 안 본 찌르기가 목록에 안 간다")
        let panel = try #require(v365Region(source, from: "private struct PokePanel: View {", to: "static func listContentHeight(rowCount:"))
        #expect(panel.components(separatedBy: "Self.sortedForDisplay(").count - 1 == 1, "정렬 호출이 body 당 한 번이 아니다")
        #expect(panel.contains("PokeRowUnreadMark.of("), "행의 점이 합집합 판정을 안 지난다")
        #expect(!panel.contains("hasUnreadMessages:"), "행이 옛 메시지 전용 깃발을 받는다")
    }
}

// MARK: - ② 디코드

@MainActor
@Suite("V0365MessagePokeDecode")
struct V0365MessagePokeDecodeTests {
    /// 종류 칸이 없는 서버(= with_reads 모양)면 메시지는 with_reads 와 **똑같이** 옮기고, 찌르기 기록은 비어 있다.
    @Test(.gomokuDefaultsCleanup)
    func 새_칸이_없으면_메시지는_그대로_찌르기는_없다() async throws {
        let rows: [[String: Any]] = [
            Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 60, unread: true),
            Fx.readsRow(id: "m2", peer: Fx.peerA, isMine: true, epoch: v365Epoch - 30, readByPeer: false),
            // 찌르기처럼 생겼지만 종류 칸이 없는 행 — 본문이 없어 메시지 옮김에서 저절로 빠진다.
            V365Fx.pokeRow(id: "p1", peer: Fx.peerA, isMine: false, unread: true).filter { $0.key != "kind" },
        ]
        let host = "v365-nokind-\(UUID().uuidString.prefix(8))".lowercased()
        let body = Fx.json(rows)
        MessageReadStubProtocol.register(host: host) { call, _ in
            ["message_history_with_pokes", "message_history_with_reads"].contains(call.rpc)
                ? MessageReadStubProtocol.Reply(body: body) : nil
        }
        let service = v365Service(host: host)
        let withPokes = try await service.fetchMessageHistoryWithPokes(accessToken: "t", hours: 24, limit: 200)
        let withReads = try await service.fetchMessageHistoryWithReads(accessToken: "t", hours: 24, limit: 200)
        #expect(withPokes.messages == withReads)
        #expect(withPokes.messages.map(\.id) == ["m1", "m2"])
        #expect(withPokes.pokes.isEmpty)
        // 요청 본문은 옛 이력과 같은 두 인자다.
        let sent = try #require(MessageReadStubProtocol.calls(host: host, rpc: "message_history_with_pokes").first?.json)
        #expect(sent["p_hours"] as? Int == 24 && sent["p_limit"] as? Int == 200 && sent.count == 2)
    }

    /// 칸 하나가 깨져도 **그 칸만** 비고, 원소 하나가 객체가 아니어도 **그 원소만** 버린다. 모르는 종류는 버린다.
    @Test(.gomokuDefaultsCleanup)
    func 깨진_칸과_모르는_종류는_그_행만_버린다() async throws {
        var stringEpoch = V365Fx.pokeRow(id: "p-str", peer: Fx.peerA, isMine: false, unread: true)
        stringEpoch["created_epoch"] = "\(v365Epoch - 5)"
        var badUnread = V365Fx.pokeRow(id: "p-badunread", peer: Fx.peerA, isMine: false)
        badUnread["unread"] = "yes"
        var numberKind = V365Fx.pokeRow(id: "p-numkind", peer: Fx.peerA, isMine: false, unread: true)
        numberKind["kind"] = 5
        var noPeer = V365Fx.pokeRow(id: "p-nopeer", peer: Fx.peerA, isMine: false, unread: true)
        noPeer["peer_user_id"] = NSNull()
        let rows: [Any] = [
            V365Fx.messageRow(id: "m1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 60, unread: true),
            7,                                                            // 객체가 아닌 원소
            stringEpoch,                                                  // epoch 가 문자열
            badUnread,                                                    // unread 가 문자열 → 모름
            numberKind,                                                   // 종류가 숫자 → 모름 → 메시지로 읽음 → 본문 없음 → 버림
            noPeer,                                                       // 상대 없음 → 버림
            V365Fx.pokeRow(id: "p-sticker", peer: Fx.peerA, isMine: false, kind: "sticker", unread: true),
            V365Fx.pokeRow(id: "p-normal", peer: Fx.peerA, isMine: false, kind: "normal", unread: false),
            V365Fx.pokeRow(id: "p-ultra-mine", peer: Fx.peerB, isMine: true, kind: "ultra", unread: true),
        ]
        let host = "v365-broken-\(UUID().uuidString.prefix(8))".lowercased()
        let body = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        MessageReadStubProtocol.register(host: host) { call, _ in
            call.rpc == "message_history_with_pokes" ? MessageReadStubProtocol.Reply(body: body) : nil
        }
        let result = try await v365Service(host: host).fetchMessageHistoryWithPokes(accessToken: "t", hours: 24, limit: 200)
        #expect(result.messages.map(\.id) == ["m1"])
        #expect(result.pokes.map(\.id) == ["p-str", "p-badunread", "p-normal", "p-ultra-mine"], "\(result.pokes.map(\.id))")
        let byID = Dictionary(uniqueKeysWithValues: result.pokes.map { ($0.id, $0) })
        #expect(byID["p-str"]?.createdAt == Date(timeIntervalSince1970: TimeInterval(v365Epoch - 5)))
        #expect(byID["p-str"]?.isUnread == true)
        #expect(byID["p-badunread"]?.isUnread == nil, "깨진 unread 를 안 읽음으로 지어냈다")
        #expect(byID["p-normal"]?.kind == .poke, "표의 글자 'normal' 을 일반 찌르기로 못 읽었다")
        // 내가 보낸 찌르기에는 서버가 unread 를 실어도 버린다(받은 것에만 뜻이 있다).
        #expect(byID["p-ultra-mine"]?.kind == .ultra && byID["p-ultra-mine"]?.isMine == true
                && byID["p-ultra-mine"]?.isUnread == nil)
    }

    /// 서버 시각(마이크로초)을 직접 읽는다 — 소수 자릿수 · 시간대 표기와 무관하게 같은 순간은 같은 값.
    @Test func 서버_시각을_마이크로초까지_읽는다() {
        // 초 부분은 주입한 파서가 읽는다(앱은 서비스의 `parseDate` — 여기서는 같은 ISO 규칙의 포매터).
        let formatter = ISO8601DateFormatter()
        let parse: (String) -> Date? = { formatter.date(from: $0) }
        let a = MessagePokeLogRules.microsecondsSinceEpoch("2026-10-23T01:02:03.123456+00:00", wholeSeconds: parse)
        let b = MessagePokeLogRules.microsecondsSinceEpoch("2026-10-23T10:02:03.123456+09:00", wholeSeconds: parse)
        let c = MessagePokeLogRules.microsecondsSinceEpoch("2026-10-23T01:02:03.1234+00:00", wholeSeconds: parse)
        let d = MessagePokeLogRules.microsecondsSinceEpoch("2026-10-23T01:02:03+00:00", wholeSeconds: parse)
        let e = MessagePokeLogRules.microsecondsSinceEpoch("2026-10-23T01:02:03.5Z", wholeSeconds: parse)
        #expect(a != nil && a == b)
        #expect(c.map { $0 % 1_000_000 } == 123_400)
        #expect(d.map { $0 % 1_000_000 } == 0)
        #expect(e.map { $0 % 1_000_000 } == 500_000)
        #expect(a.map { $0 - (d ?? 0) } == 123_456)
        // 같은 밀리초 안의 두 순간도 가른다(ISO 포매터는 밀리초에서 자른다).
        let early = MessagePokeLogRules.microsecondsSinceEpoch("2026-10-23T01:02:03.123401+00:00", wholeSeconds: parse)
        let late = MessagePokeLogRules.microsecondsSinceEpoch("2026-10-23T01:02:03.123499+00:00", wholeSeconds: parse)
        #expect((early ?? 0) < (late ?? 0))
    }
}

// MARK: - ③ 대화창 끼워 넣기 · 문구

@Suite("V0365MessagePokeTimeline")
struct V0365MessagePokeTimelineTests {
    /// 시간 순서로 끼운다. 같은 초면 서버 시각 순위, 순위를 모르는 즉시 삽입분은 아는 쪽 **뒤**. 메시지끼리 순서는 안 건드린다.
    @Test func 끼워_넣기_순서와_같은_초_동률() {
        let messages = [
            V365Fx.message("m1", secondsAgo: 60),
            V365Fx.message("m2", isMine: true, secondsAgo: 10),
            V365Fx.message("m3", secondsAgo: 10),          // m2 와 같은 초 — 메시지끼리는 들어온 순서 그대로
        ]
        let pokes = [
            V365Fx.poke("p1", secondsAgo: 30),
            V365Fx.poke("p2", kind: .ultra, secondsAgo: 10),   // 같은 초 — 서버 순위로 m2 앞
            V365Fx.poke("p3", secondsAgo: 10),                 // 같은 초 — 순위 없음(즉시 삽입) → 아는 줄들 뒤
            V365Fx.poke("p4", isMine: true, secondsAgo: 2),
        ]
        let chronology = ["m1": 0, "p1": 1, "p2": 2, "m2": 3, "m3": 4, "p4": 5]
        let lines = MessageConversationTimeline.lines(
            messages: messages, pokes: pokes, chronology: chronology, now: v365Now, calendar: V365Fx.kst
        )
        let ids = lines.map(\.id)
        #expect(ids.dropFirst().map { $0 } == ["m1", "poke-p1", "poke-p2", "m2", "m3", "poke-p3", "poke-p4"], "\(ids)")
        #expect(ids.first?.hasPrefix("day-") == true, "첫 줄 앞에 날짜 구분선이 없다")

        // 서버 순위가 반대면 반대로(같은 초 안에서 메시지가 먼저였다).
        let flipped = MessageConversationTimeline.lines(
            messages: messages, pokes: pokes, chronology: ["m1": 0, "p1": 1, "m2": 2, "m3": 3, "p2": 4, "p4": 5],
            now: v365Now, calendar: V365Fx.kst
        ).map(\.id)
        #expect(Array(flipped.dropFirst()) == ["m1", "poke-p1", "m2", "m3", "poke-p2", "poke-p3", "poke-p4"], "\(flipped)")

        // 찌르기가 없으면 예전 타임라인과 줄 단위로 같다(옛 서버 · 찌르기 없는 대화의 화면이 한 픽셀도 안 바뀐다).
        let legacy = MessageThreadBuilder.timeline(messages, now: v365Now, calendar: V365Fx.kst).map(\.id)
        #expect(MessageConversationTimeline.lines(messages: messages, pokes: [], now: v365Now, calendar: V365Fx.kst).map(\.id) == legacy)
        // 찌르기만 있어도 줄이 선다(한 번도 말을 안 섞은 사람이 찌른 경우).
        #expect(MessageConversationTimeline.lines(messages: [], pokes: [pokes[0]], now: v365Now, calendar: V365Fx.kst).count == 2)
    }

    /// 자정을 넘긴 찌르기는 새 날짜 구분선 아래에 선다(날짜 판정이 말풍선과 같은 하나).
    @Test func 날짜가_바뀌면_구분선() {
        let midnightKST = Date(timeIntervalSince1970: 1_790_002_800)   // 2026-09-22 00:00 KST
        let before = MessagePokeLogEntry(id: "p0", peerUserID: Fx.peerA, peerName: "민수",
                                         createdAt: midnightKST.addingTimeInterval(-60), isMine: false, kind: .poke)
        let after = MessageHistoryEntry(id: "m0", peerUserID: Fx.peerA, peerName: "민수", peerAvatarURL: nil, body: "굿모닝",
                                        createdAt: midnightKST.addingTimeInterval(60), isMine: false)
        let lines = MessageConversationTimeline.lines(
            messages: [after], pokes: [before], now: midnightKST.addingTimeInterval(3600), calendar: V365Fx.kst
        )
        let shape = lines.map { line -> String in
            switch line {
            case .day(_, let label): return "day:\(label)"
            case .bubble(let entry): return entry.id
            case .poke(let entry): return "poke:\(entry.id)"
            }
        }
        #expect(shape == ["day:어제", "poke:p0", "day:오늘", "m0"], "\(shape)")
    }

    /// 문구: 받은 것 "○○님이 콕 찔렀어요 · 15:12", 보낸 울트라 "내가 울트라 찔렀어요 · 15:15". 시각은 말풍선 옆 시각과 같은 눈금.
    @Test func 문구와_아이콘() {
        let at1512 = Date(timeIntervalSince1970: 1_790_057_520)   // 2026-09-22 15:12 KST
        let received = MessagePokeLogEntry(id: "p", peerUserID: Fx.peerA, peerName: "민수", createdAt: at1512,
                                           isMine: false, kind: .poke, isUnread: true)
        let sentUltra = MessagePokeLogEntry(id: "u", peerUserID: Fx.peerA, peerName: "민수",
                                            createdAt: at1512.addingTimeInterval(180), isMine: true, kind: .ultra)
        #expect(MessagePokeLogText.line(for: received, calendar: V365Fx.kst) == "민수님이 콕 찔렀어요 · 15:12")
        #expect(MessagePokeLogText.line(for: sentUltra, calendar: V365Fx.kst) == "내가 울트라 찔렀어요 · 15:15")
        #expect(MessagePokeLogText.predicate(for: received, calendar: V365Fx.kst).hasSuffix(MessageThreadBuilder.clockText(at1512, calendar: V365Fx.kst)))
        // 아이콘은 레일 [콕] 손가락과 울트라 번개 그대로.
        #expect(MessagePokeLogText.symbol(.poke) == "hand.point.right.fill")
        #expect(MessagePokeLogText.symbol(.ultra) == "bolt.fill")
    }

    /// 디코드가 세운 서버 시각 순위가 같은 초의 끼움을 정한다 — 응답이 메시지를 먼저 실어도 더 이른 찌르기가 위다.
    @Test func 같은_초의_선후는_서버_시각이_정한다() async {
        let service = v365Service(host: "v365-chrono")
        let rows = [
            MessageHistoryWithPokesRow(
                id: "m-late", fromUser: Fx.peerA, toUser: Fx.me, body: "늦은 말", createdAt: "2026-09-21T12:00:00.700000+00:00",
                isMine: false, peerUserId: Fx.peerA, peerDisplayName: "민수", createdEpoch: v365Epoch, unread: false, kind: "message"
            ),
            MessageHistoryWithPokesRow(
                id: "p-early", fromUser: Fx.peerA, toUser: Fx.me, createdAt: "2026-09-21T12:00:00.300000+00:00",
                isMine: false, peerUserId: Fx.peerA, peerDisplayName: "민수", createdEpoch: v365Epoch, unread: true, kind: "poke"
            ),
        ]
        let result = await service.messageHistoryWithPokes(fromRows: rows)
        #expect((result.chronology["p-early"] ?? 9) < (result.chronology["m-late"] ?? -1))
        let lines = MessageConversationTimeline.lines(
            messages: result.messages, pokes: result.pokes, chronology: result.chronology, now: v365Now, calendar: V365Fx.kst
        )
        #expect(Array(lines.map(\.id).dropFirst()) == ["poke-p-early", "m-late"])
    }
}

// MARK: - ④⑤⑥ 스토어 — 읽음 올리기 · 옛 서버 · 박자

@MainActor
@Suite("V0365MessagePokeStore")
struct V0365MessagePokeStoreTests {
    /// 새 서버: 대화를 열면 이력은 **새 조회 하나**(왕복 1) — with_reads·옛 이력은 안 부른다.
    @Test(.gomokuDefaultsCleanup)
    func 새_서버는_조회_박자당_한_번() async {
        let (store, host) = makeMessageReadStore("v365-one") { call, _ in
            switch call.rpc {
            case "message_history_with_pokes":
                return V365Fx.reply([
                    V365Fx.messageRow(id: "m1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 60, unread: false),
                    V365Fx.pokeRow(id: "p1", peer: Fx.peerA, isMine: true, epoch: v365Epoch - 30),
                ])
            case "message_unread_summary": return Fx.summaryReply([])
            default: return nil
            }
        }
        await v365OpenConversation(store)
        #expect(v365Count(host, "message_history_with_pokes") == 1)
        #expect(v365Count(host, "message_history_with_reads") == 0, "새 함수가 있는데 옛 읽음 이력까지 불렀다")
        #expect(v365Count(host, "message_history") == 0)
        #expect(store.selectedMessagePokeLog.map(\.id) == ["p1"])
        #expect(store.messagePokeLogSnapshot != nil)
        // 내가 보낸 찌르기만 있으면 올릴 것이 없다(읽음 호출 0).
        #expect(v365Count(host, "mark_conversation_read") == 0 && v365Count(host, "mark_messages_read") == 0)
    }

    /// 대화를 열면 찌르기도 읽음 — `mark_conversation_read {p_peer, p_through_message, p_through_poke}` 한 번.
    @Test(.gomokuDefaultsCleanup)
    func 열면_메시지와_찌르기를_한_번에_올린다() async {
        let marked = V365Flag()
        let (store, host) = makeMessageReadStore("v365-both") { call, _ in
            switch call.rpc {
            case "message_history_with_pokes":
                let read = marked.isSet   // 읽음이 오른 뒤의 조회는 A 의 줄을 읽음으로 준다(실서버와 같게)
                return V365Fx.reply([
                    V365Fx.pokeRow(id: "p0", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 90, unread: !read),
                    V365Fx.messageRow(id: "m1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 60, unread: !read),
                    V365Fx.pokeRow(id: "p1", peer: Fx.peerA, isMine: false, kind: "ultra", epoch: v365Epoch - 30, unread: !read),
                    V365Fx.pokeRow(id: "p2", peer: Fx.peerA, isMine: true, epoch: v365Epoch - 10),
                    V365Fx.pokeRow(id: "pb", peer: Fx.peerB, isMine: false, epoch: v365Epoch - 5, unread: true),
                ])
            case "mark_conversation_read":
                marked.set()
                return V365Fx.conversationMarkReply()
            case "message_unread_summary": return Fx.summaryReply([])
            default: return nil
            }
        }
        await v365OpenConversation(store)
        await messageReadWait { v365Count(host, "mark_conversation_read") >= 1 && messageReadIdle(store) }
        #expect(v365Count(host, "mark_conversation_read") == 1)
        #expect(v365Count(host, "mark_messages_read") == 0, "옛 함수와 새 함수를 둘 다 불렀다")
        let body = v365LastBody(host, "mark_conversation_read")
        #expect(Set(body.keys) == ["p_peer", "p_through_message", "p_through_poke"], "\(body)")
        #expect(body["p_peer"] as? String == Fx.peerA)
        #expect(body["p_through_message"] as? String == "m1")
        // 화면에 보인 **마지막 받은** 찌르기(내가 보낸 p2 · 다른 사람의 pb 가 아니다).
        #expect(body["p_through_poke"] as? String == "p1")
        // 낙관 읽음이 곧바로 점을 끈다 — A 는 빠지고 B 는 남는다(B 의 대화는 안 열었다).
        #expect(store.unreadPokePeerIDs == [Fx.peerB])
        #expect(store.messagePokeOptimisticReads[Fx.peerA]?.failed == false)
    }

    /// 찌르기만 안 읽음이면 메시지 경계는 **싣지 않는다** — 서버는 null 갈래를 안 움직인다(화면에 안 그린 말까지 읽음이 되면 안 된다).
    @Test(.gomokuDefaultsCleanup)
    func 찌르기만_안_읽음이면_메시지_경계는_싣지_않는다() async {
        let (store, host) = makeMessageReadStore("v365-pokeonly") { call, _ in
            switch call.rpc {
            case "message_history_with_pokes":
                return V365Fx.reply([
                    V365Fx.messageRow(id: "m1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 60, unread: false),
                    V365Fx.pokeRow(id: "p1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 30, unread: true),
                ])
            case "mark_conversation_read": return V365Fx.conversationMarkReply()
            case "message_unread_summary": return Fx.summaryReply([])
            default: return nil
            }
        }
        await v365OpenConversation(store)
        await messageReadWait { v365Count(host, "mark_conversation_read") >= 1 && messageReadIdle(store) }
        let body = v365LastBody(host, "mark_conversation_read")
        #expect(Set(body.keys) == ["p_peer", "p_through_poke"], "\(body)")
        #expect(body["p_through_poke"] as? String == "p1")
        // 찌르기만 올렸으면 요약·이력을 다시 받지 않는다(찌르기 한 번에 왕복 둘을 더 쓰지 않는다).
        #expect(v365Count(host, "message_history_with_pokes") == 1)
        #expect(store.unreadPokePeerIDs.isEmpty)
    }

    /// 메시지만 안 읽음이면 **옛 호출 그대로**(`mark_messages_read {p_peer, p_through}`).
    @Test(.gomokuDefaultsCleanup)
    func 메시지만_안_읽음이면_옛_호출_그대로() async {
        let (store, host) = makeMessageReadStore("v365-msgonly") { call, _ in
            switch call.rpc {
            case "message_history_with_pokes":
                return V365Fx.reply([
                    V365Fx.pokeRow(id: "p1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 90, unread: false),
                    V365Fx.messageRow(id: "m1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 60, unread: true),
                ])
            case "mark_messages_read": return Fx.markReply()
            case "message_unread_summary": return Fx.summaryReply([])
            default: return nil
            }
        }
        await v365OpenConversation(store)
        await messageReadWait { v365Count(host, "mark_messages_read") >= 1 && messageReadIdle(store) }
        #expect(v365Count(host, "mark_conversation_read") == 0)
        let body = v365LastBody(host, "mark_messages_read")
        #expect(Set(body.keys) == ["p_peer", "p_through"], "\(body)")
        #expect(body["p_through"] as? String == "m1")
    }

    /// 옛 서버(새 조회 없음 — 404 PGRST202): 예전 조회로 접고 찌르기 기록·찌르기 안 읽음 없이 **지금처럼** 동작한다.
    @Test(.gomokuDefaultsCleanup)
    func 옛_서버면_지금처럼() async {
        let (store, host) = makeMessageReadStore("v365-legacy") { call, _ in
            switch call.rpc {
            case "message_history_with_reads":
                return Fx.historyReply([Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 60, unread: true)])
            case "mark_messages_read": return Fx.markReply()
            case "message_unread_summary": return Fx.summaryReply([])
            default: return nil   // message_history_with_pokes · mark_conversation_read 는 없는 서버(스텁 기본값)
            }
        }
        // 서버가 되돌아간 날: 들고 있던 찌르기 기록·점은 옛 조회 한 번에 내려간다(낡은 점이 목록 맨 위를 붙들지 않게).
        store.messagePokeLog = [V365Fx.poke("stale", peer: Fx.peerB, secondsAgo: 5, isUnread: true)]
        store.messagePokeLogSnapshot = MessageHistoryReadSnapshot(serial: 0, serverOrder: ["stale": 0])
        #expect(store.unreadPokePeerIDs == [Fx.peerB])
        await v365OpenConversation(store)
        await messageReadWait { v365Count(host, "mark_messages_read") >= 1 && messageReadIdle(store) }
        // 조회마다 새 함수를 먼저 묻고(없음) 옛 읽음 이력으로 접는다 — 폴백을 캐시하지 않는다(db push 는 앱이 떠 있는 동안 끝난다).
        #expect(v365Count(host, "message_history_with_pokes") >= 1)
        #expect(v365Count(host, "message_history_with_reads") == v365Count(host, "message_history_with_pokes"))
        #expect(v365Count(host, "message_history") == 0)
        #expect(store.selectedMessageThread?.messages.map(\.id) == ["m1"], "옛 서버에서 대화가 사라졌다")
        #expect(store.messagePokeLogSnapshot == nil && store.messagePokeLog.isEmpty)
        #expect(store.unreadPokePeerIDs.isEmpty)
        #expect(store.messageReadReceiptsAvailable, "옛 서버로 접었더니 읽음 1 까지 꺼졌다")
        #expect(v365Count(host, "mark_conversation_read") == 0)
        #expect(Set(v365LastBody(host, "mark_messages_read").keys) == ["p_peer", "p_through"])

        // 옛 서버에서 받은 찌르기는 기록에 넣지 않는다(다음 이력에서 사라질 줄을 만들지 않는다).
        #expect(store.insertConsumedPokesIntoLog(rows: [
            TakenPokeRow(id: "tp", fromUser: Fx.peerA, fromDisplayName: "민수", fromAvatarUrl: nil, createdEpoch: v365Epoch, kind: "normal")
        ]) == 0)
    }

    /// 일시 장애(5xx)는 "함수 없음"이 아니다 — 옛 조회로 접지 않고 실패로 남긴다(장애 한 번에 찌르기 기록이 꺼지면 안 된다).
    @Test(.gomokuDefaultsCleanup)
    func 일시_장애는_옛_조회로_접지_않는다() async {
        let (store, host) = makeMessageReadStore("v365-5xx") { call, _ in
            switch call.rpc {
            case "message_history_with_pokes": return MessageReadStubProtocol.Reply(status: 500, body: #"{"message":"boom"}"#)
            case "message_unread_summary": return Fx.summaryReply([])
            default: return nil
            }
        }
        await store.performLoadMessageHistory()
        #expect(v365Count(host, "message_history_with_pokes") >= 1)
        #expect(v365Count(host, "message_history_with_reads") == 0 && v365Count(host, "message_history") == 0,
                "5xx 를 '함수 없음'으로 접었다")
        #expect(store.messageHistoryFailed)
    }

    /// 새 이력은 있는데 새 읽음 함수가 없는 서버(반쯤 배포): 메시지 경계만 옛 함수로 한 번 더 — 상대의 1 은 꺼진다.
    @Test(.gomokuDefaultsCleanup)
    func 새_읽음_함수가_없으면_메시지만_옛_함수로() async {
        let (store, host) = makeMessageReadStore("v365-halfway") { call, _ in
            switch call.rpc {
            case "message_history_with_pokes":
                return V365Fx.reply([
                    V365Fx.messageRow(id: "m1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 60, unread: true),
                    V365Fx.pokeRow(id: "p1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 30, unread: true),
                ])
            case "mark_messages_read": return Fx.markReply()
            case "message_unread_summary": return Fx.summaryReply([])
            default: return nil
            }
        }
        await v365OpenConversation(store)
        await messageReadWait { v365Count(host, "mark_messages_read") >= 1 && messageReadIdle(store) }
        #expect(v365Count(host, "mark_conversation_read") >= 1)
        // 메시지 경계는 옛 함수로 **한 번만** 올린다(그 뒤 찌르기만 다시 묻는 호출은 없는 함수라 던지고 끝난다 — 되풀이 없음).
        #expect(v365Count(host, "mark_messages_read") == 1)
        let body = v365LastBody(host, "mark_messages_read")
        #expect(Set(body.keys) == ["p_peer", "p_through"] && body["p_through"] as? String == "m1", "\(body)")
        #expect(store.messageOptimisticReads[Fx.peerA]?.failed == false)
        #expect(store.messagePokeOptimisticReads[Fx.peerA]?.failed == true, "못 올린 찌르기를 올렸다고 정산했다")
    }

    /// 받은 찌르기(take_pokes 소비)는 **왕복 없이** 목록 맨 위 무리에 들고, 그 사람과의 대화가 떠 있으면 그 자리에 줄이 서고 읽음이 오른다.
    @Test(.gomokuDefaultsCleanup)
    func 받은_찌르기는_왕복_없이_목록과_대화에() async {
        let (store, host) = makeMessageReadStore("v365-take") { call, index in
            switch call.rpc {
            case "message_history_with_pokes":
                // 첫 조회 뒤에는 서버도 B 의 찌르기(tb)를 안다(소비는 표시와 무관 — 기록은 24시간 남는다).
                var rows = [V365Fx.messageRow(id: "m1", peer: Fx.peerA, isMine: false, epoch: v365Epoch - 600, unread: false)]
                if index >= 1 {
                    rows.append(V365Fx.pokeRow(id: "tb", peer: Fx.peerB, isMine: false, epoch: v365Epoch - 20, unread: true, name: "지수"))
                }
                return V365Fx.reply(rows)
            case "take_pokes":
                let rows: [[String: Any]] = index == 0
                    ? [V365Fx.takenPokeRow(id: "tb", from: Fx.peerB, epoch: v365Epoch - 20, name: "지수")]
                    : [V365Fx.takenPokeRow(id: "ta", from: Fx.peerA, epoch: v365Epoch - 5, kind: "ultra", name: "민수"),
                       V365Fx.takenPokeRow(id: "old", from: Fx.peerA, epoch: v365Epoch - 25 * 3600, name: "민수")]
                return MessageReadStubProtocol.Reply(body: Fx.json(rows))
            case "mark_conversation_read": return V365Fx.conversationMarkReply()
            case "message_unread_summary": return Fx.summaryReply([])
            default: return nil
            }
        }
        await store.performLoadMessageHistory()
        #expect(store.messagePokeLogSnapshot != nil)
        let historyBefore = v365Count(host, "message_history_with_pokes")

        // ① 대화가 안 떠 있다 — 목록 합집합에 곧바로(왕복 0).
        _ = await store.drainReceivedPokes()
        #expect(store.unreadPokePeerIDs == [Fx.peerB], "받은 찌르기가 목록 안 읽음에 안 들었다")
        #expect(store.messagePokeLog.map(\.id) == ["tb"])
        #expect(v365Count(host, "message_history_with_pokes") == historyBefore, "받은 찌르기 하나에 이력을 다시 받았다")

        // ② A 와의 대화가 떠 있다 — 그 자리에 줄이 서고, 그 찌르기까지 읽음이 오른다. 24시간 밖의 것은 안 넣는다.
        await v365OpenConversation(store)
        // 이력은 이미 받아 둔 상태라 위 기다림이 곧바로 풀린다 — 대화를 여는 문이 띄운 조회가 **끝날 때까지** 기다린다.
        await messageReadWait { v365Count(host, "message_history_with_pokes") == historyBefore + 1 && messageReadIdle(store) }
        let historyOpen = v365Count(host, "message_history_with_pokes")
        #expect(historyOpen == historyBefore + 1)
        _ = await store.drainReceivedPokes()
        #expect(store.selectedMessagePokeLog.map(\.id) == ["ta"], "\(store.selectedMessagePokeLog.map(\.id))")
        #expect(store.selectedMessagePokeLog.first?.kind == .ultra)
        await messageReadWait { v365Count(host, "mark_conversation_read") >= 1 && messageReadIdle(store) }
        #expect(v365LastBody(host, "mark_conversation_read")["p_through_poke"] as? String == "ta")
        #expect(v365Count(host, "message_history_with_pokes") == historyOpen, "보이는 대화의 찌르기가 이력 왕복을 불렀다")
        #expect(store.unreadPokePeerIDs == [Fx.peerB])
    }

    /// 즉시 넣은 찌르기는 그보다 **먼저 띄운** 이력 응답에 지워지지 않고, 나중에 띄운 응답이 오면 서버 행이 이긴다.
    @Test(.gomokuDefaultsCleanup)
    func 즉시_넣은_찌르기는_나중_이력만_덮는다() async {
        let store = makeMessageReadStore("v365-survive").store
        let pokes: [MessagePokeLogEntry] = []
        store.applyMessagePokeLog(MessageConversationLoad(history: MessageHistoryLoad(entries: [], hasReadReceipts: true), pokes: pokes), serial: 1)
        let earlySerial = store.messageReadRuntime.nextHistorySerial()   // 넣기 **전에** 띄운 조회
        #expect(store.insertConsumedPokesIntoLog(rows: [
            TakenPokeRow(id: "tp", fromUser: Fx.peerA, fromDisplayName: "민수", fromAvatarUrl: nil, createdEpoch: v365Epoch - 3, kind: "normal")
        ]) == 1)
        store.applyMessagePokeLog(MessageConversationLoad(history: MessageHistoryLoad(entries: [], hasReadReceipts: true), pokes: []), serial: earlySerial)
        #expect(store.messagePokeLog.map(\.id) == ["tp"], "먼저 띄운 조회가 방금 넣은 찌르기를 지웠다")
        let lateSerial = store.messageReadRuntime.nextHistorySerial()
        let server = V365Fx.poke("tp", secondsAgo: 3, isUnread: false)
        store.applyMessagePokeLog(MessageConversationLoad(history: MessageHistoryLoad(entries: [], hasReadReceipts: true), pokes: [server]), serial: lateSerial)
        #expect(store.messagePokeLog == [server], "나중에 띄운 조회의 서버 행이 안 이겼다")
        #expect(store.unreadPokePeerIDs.isEmpty)
    }

    /// take_pokes 즉시 삽입은 **이력 디코더와 같은 종류 규칙**이다 — 'message' · 모르는 종류는 넣지 않는다. 넣으면 다음 이력(서버는
    /// normal · ultra 만 내려 준다)에서 사라질 줄이 그동안 "콕 찔렀어요" 로 서고, 그 사람을 목록 맨 위 안 읽음에 붙든다.
    /// kind 가 없는 행(종류 칸이 생기기 전 옛 서버)만 일반 찌르기다.
    @Test(.gomokuDefaultsCleanup)
    func 받은_찌르기의_종류는_이력과_같은_규칙() async {
        let store = makeMessageReadStore("v365-kind").store
        store.applyMessagePokeLog(
            MessageConversationLoad(history: MessageHistoryLoad(entries: [], hasReadReceipts: true), pokes: []),
            serial: store.messageReadRuntime.nextHistorySerial()
        )
        func taken(_ id: String, _ kind: String?) -> TakenPokeRow {
            TakenPokeRow(id: id, fromUser: Fx.peerA, fromDisplayName: "민수", fromAvatarUrl: nil, createdEpoch: v365Epoch - 3, kind: kind)
        }
        // ① 모르는 종류 · 3글자 메시지: 기록에도, 목록 안 읽음에도 안 든다.
        #expect(store.insertConsumedPokesIntoLog(rows: [taken("t-sticker", "sticker"), taken("t-message", "message")]) == 0)
        #expect(store.messagePokeLog.isEmpty, "모르는 종류를 콕 기록에 넣었다: \(store.messagePokeLog.map { MessagePokeLogText.line(for: $0) })")
        #expect(store.unreadPokePeerIDs.isEmpty, "모르는 종류가 목록 맨 위 안 읽음으로 셌다: \(store.unreadPokePeerIDs)")

        // ② 같은 글자를 두 길(즉시 삽입 · 이력 디코더)이 같은 쪽으로 가른다.
        let service = v365Service(host: "v365-kind-decode")
        for kind in ["sticker", "message", "normal", "ultra"] {
            let decoded = await service.messageHistoryWithPokes(fromRows: [MessageHistoryWithPokesRow(
                id: "d-\(kind)", fromUser: Fx.peerA, toUser: Fx.me, createdAt: "2026-09-21T12:00:00.000000+00:00", isMine: false,
                peerUserId: Fx.peerA, peerDisplayName: "민수", createdEpoch: v365Epoch, unread: true, kind: kind
            )])
            let id = "p-\(kind)"
            let inserted = store.insertConsumedPokesIntoLog(rows: [taken(id, kind)])
            let insertedKind = inserted == 1 ? store.messagePokeLog.first(where: { $0.id == id })?.kind : nil
            #expect(insertedKind == decoded.pokes.first?.kind, "'\(kind)': 즉시 삽입 \(String(describing: insertedKind)) ≠ 이력 \(String(describing: decoded.pokes.first?.kind))")
        }
        #expect(store.messagePokeLog.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.poke, .ultra])

        // ③ 종류 칸이 없는 옛 행은 일반 찌르기다.
        #expect(store.insertConsumedPokesIntoLog(rows: [taken("t-legacy", nil)]) == 1)
        #expect(store.messagePokeLog.first(where: { $0.id == "t-legacy" })?.kind == .poke)
    }

    /// 보낸 찌르기(일반 · 울트라): 그 사람과의 대화가 **떠 있을 때만** 이력을 한 번 받는다(새 타이머 없음 — 성공 이벤트 1회).
    @Test(.gomokuDefaultsCleanup)
    func 보낸_찌르기는_그_대화가_떠_있을_때만_이력_한_번() async {
        let (store, host) = makeMessageReadStore("v365-send") { call, _ in
            switch call.rpc {
            case "message_history_with_pokes": return V365Fx.reply([])
            case "poke_user": return MessageReadStubProtocol.Reply(body: #"{"status":"ok"}"#)
            case "ultra_poke_user": return MessageReadStubProtocol.Reply(body: #"{"status":"ok"}"#)
            case "message_unread_summary": return Fx.summaryReply([])
            default: return nil
            }
        }
        store.startedAt = v365Now.addingTimeInterval(-600)
        await v365OpenConversation(store)
        var before = v365Count(host, "message_history_with_pokes")
        store.sendPoke(to: Fx.peerA)
        await messageReadWait { v365Count(host, "message_history_with_pokes") > before && messageReadIdle(store) }
        #expect(v365Count(host, "message_history_with_pokes") == before + 1, "보이는 대화의 상대를 찔렀는데 기록을 안 받았다")

        // 울트라도 같다(명세 §3.4 '보내면 곧 보이게'는 울트라 포함).
        before = v365Count(host, "message_history_with_pokes")
        store.sendUltraPoke(to: Fx.peerA)
        await messageReadWait { v365Count(host, "message_history_with_pokes") > before && messageReadIdle(store) }
        #expect(v365Count(host, "ultra_poke_user") == 1)
        #expect(v365Count(host, "message_history_with_pokes") == before + 1, "보이는 대화의 상대에게 울트라를 썼는데 기록을 안 받았다")

        // 다른 사람을 찌르면 이 대화를 다시 받지 않는다.
        store.sendPoke(to: Fx.peerB)
        await messageReadWait { v365Count(host, "poke_user") >= 2 }
        await messageReadWait(2) { false }   // 혹시 나갈 조회가 있으면 나갈 시간을 준다(부정형 단언)
        #expect(v365Count(host, "message_history_with_pokes") == before + 1)

        // 대화를 닫은 뒤 찌르면 받지 않는다(대화를 여는 문이 언제나 받는다).
        store.closeMessagePanel()
        store.sendPoke(to: Fx.peerA)
        await messageReadWait { v365Count(host, "poke_user") >= 3 }
        await messageReadWait(2) { false }
        #expect(v365Count(host, "message_history_with_pokes") == before + 1)
    }

    /// 로그아웃이 찌르기 기록을 지운다(다음 계정 목록 맨 위에 앞 사람을 찌른 사람이 뜨면 안 된다).
    @Test(.gomokuDefaultsCleanup)
    func 로그아웃이_찌르기_기록을_지운다() throws {
        let store = makeMessageReadStore("v365-signout").store
        store.messagePokeLog = [V365Fx.poke("p1", secondsAgo: 5, isUnread: true)]
        store.messagePokeLogSnapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["p1": 0])
        store.messagePokeChronology = ["p1": 0]
        store.messagePokeOptimisticReads = [Fx.peerA: MessageOptimisticRead(throughID: "p1", recordedSerial: 1)]
        store.messageReadRuntime.pokeLocalArrivalSerials = ["p1": 1]
        store.clearPersistedSession()
        #expect(store.messagePokeLog.isEmpty && store.messagePokeLogSnapshot == nil)
        #expect(store.messagePokeChronology.isEmpty && store.messagePokeOptimisticReads.isEmpty)
        #expect(store.messageReadRuntime.pokeLocalArrivalSerials.isEmpty)
    }
}

// MARK: - ⑦ 렌더 (ImageRenderer — 창 없음)

@MainActor
private func v365Bitmap(_ view: some View) throws -> NSBitmapImageRep {
    try #require(CheckRenderSettle.bitmap(view.fixedSize(), scale: 2))
}

/// 두 그림이 다른 픽셀 수와 경계(pt). 크기가 다르면 count = -1.
private func v365Diff(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> (count: Int, box: CGRect) {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
          let a = lhs.bitmapData, let b = rhs.bitmapData else { return (-1, .null) }
    let bpr = lhs.bytesPerRow, spp = lhs.samplesPerPixel
    var count = 0
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<lhs.pixelsHigh {
        for x in 0..<lhs.pixelsWide {
            let o = y * bpr + x * spp
            let d = abs(Int(a[o]) - Int(b[o])) + abs(Int(a[o + 1]) - Int(b[o + 1])) + abs(Int(a[o + 2]) - Int(b[o + 2]))
            guard d > 24 else { continue }
            count += 1
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard count > 0 else { return (0, .null) }
    return (count, CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2,
                          width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2))
}

/// 목록 네 무리 픽스처(입력 순서는 일부러 섞었다).
private let v365ListEntries: [PokeDirectoryEntry] = [
    V365Fx.entry("u-d", "라온", working: false),      // ④
    V365Fx.entry("u-b", "나래", working: false),      // ② 안 본 찌르기
    V365Fx.entry("u-c", "다온", working: true),       // ③
    V365Fx.entry("u-a", "가람", working: true),       // ① 안 읽은 메시지
    V365Fx.entry("u-e", "마루", working: true),       // ① 안 본 찌르기
    V365Fx.entry("u-f", "바다", working: false),      // ② 안 읽은 메시지
]

/// 콕찌르기 목록이 열린 팝오버(스텁 네트워크 — 렌더의 `.task` 가 운영에 닿지 않게).
@MainActor
private func v365ListStore(
    _ label: String, messages: Set<String>, pokes: Set<String>, function: String = #function
) -> WorkTimerStore {
    let store = makeMessageReadStore(label, function: function).store
    store.isMenuPresented = true
    store.displayNow = v365Now
    store.teamMembers = []
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    store.pokeDirectory = v365ListEntries
    store.pokeDirectoryLoaded = true
    store.isPokePanelVisible = true
    store.messageHistory = messages.sorted().enumerated().map { index, peer in
        MessageHistoryEntry(id: "m-\(peer)", peerUserID: peer, peerName: "상대", peerAvatarURL: nil, body: "안녕",
                            createdAt: v365Now.addingTimeInterval(TimeInterval(-60 - index)), isMine: false, isUnread: true)
    }
    store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(
        serial: 1, serverOrder: Dictionary(uniqueKeysWithValues: store.messageHistory.enumerated().map { ($1.id, $0) })
    )
    store.messagePokeLog = pokes.sorted().enumerated().map { index, peer in
        MessagePokeLogEntry(id: "p-\(peer)", peerUserID: peer, peerName: "상대",
                            createdAt: v365Now.addingTimeInterval(TimeInterval(-30 - index)), isMine: false, kind: .poke, isUnread: true)
    }
    store.messagePokeLogSnapshot = MessageHistoryReadSnapshot(
        serial: 1, serverOrder: Dictionary(uniqueKeysWithValues: store.messagePokeLog.enumerated().map { ($1.id, $0) })
    )
    return store
}

/// 대화 패널(스텁 갈래 — 스크롤 대신 클립, 입력칸은 순수 글자).
@MainActor
private func v365ConversationStore(_ label: String, pokes: Bool, function: String = #function) -> WorkTimerStore {
    let store = makeMessageReadStore(label, function: function).store
    store.messageHistory = [
        V365Fx.message("m1", secondsAgo: 300, isUnread: false, body: "점심 뭐 먹을까요?"),
        V365Fx.message("m2", isMine: true, secondsAgo: 200, body: "김치찌개 어때요"),
        V365Fx.message("m3", secondsAgo: 40, isUnread: false, body: "좋아요 지금 갈게요"),
    ]
    store.messageHistoryLoaded = true
    store.messageReadReceiptsAvailable = true
    store.selectedMessagePeerID = Fx.peerA
    store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["m1": 0, "m2": 1, "m3": 2])
    if pokes {
        store.messagePokeLog = [
            V365Fx.poke("p1", secondsAgo: 360, isUnread: false),
            V365Fx.poke("p2", isMine: true, kind: .ultra, secondsAgo: 120),
            V365Fx.poke("p3", kind: .ultra, secondsAgo: 20, isUnread: false),
        ]
        store.messagePokeLogSnapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["p1": 0, "p2": 1, "p3": 2])
    }
    return store
}

@MainActor
private func v365ConversationView(_ store: WorkTimerStore) -> some View {
    CheckMessageView(store: store, rendersPlainTextEditor: true, clipsOverflowInsteadOfScroll: true, now: v365Now, onBack: {})
        .frame(width: CheckMenuView.contentColumnWidth)
        .background(CheckTheme.background)
}

@MainActor
@Suite("V0365MessagePokeRender", .serialized)
struct V0365MessagePokeRenderTests {
    /// 안 본 찌르기 하나가 생기면 그 사람이 **맨 위로 옮겨 간다**(점만 붙는 것이 아니다 — 목록 여러 줄이 바뀐다).
    /// 그리고 찌르기 안 읽음과 메시지 안 읽음은 목록에서 **똑같이** 그려진다(다른 것은 레일의 메시지 점뿐이다).
    @Test(.gomokuDefaultsCleanup)
    func 안_본_찌르기가_있는_사람이_맨_위로_그려진다() throws {
        let plain = try v365Bitmap(CheckMenuView(store: v365ListStore("v365-l0", messages: [], pokes: [])))
        let poked = try v365Bitmap(CheckMenuView(store: v365ListStore("v365-l1", messages: [], pokes: ["u-d"])))
        let messaged = try v365Bitmap(CheckMenuView(store: v365ListStore("v365-l2", messages: ["u-d"], pokes: [])))

        let moved = v365Diff(plain, poked)
        // 라온(④ 맨 끝)이 맨 위로 — 목록 여섯 줄이 다 밀린다(점 하나면 7pt 상자다).
        #expect(moved.count > 2_000 && moved.box.height > 4 * 48, "안 본 찌르기가 순서를 안 바꿨다: \(moved)")

        let same = v365Diff(poked, messaged)
        #expect(same.count >= 0, "두 그림의 크기가 다르다")
        // 다른 곳은 레일의 메시지 점 하나뿐이어야 한다(그 점은 메시지만 센다 — 찌르기 쪽에는 없다).
        #expect(same.box.isNull || (same.box.width < 16 && same.box.height < 16),
                "찌르기 안 읽음과 메시지 안 읽음이 목록에서 다르게 그려진다: \(same)")
        #expect(!same.box.isNull, "레일 메시지 점이 찌르기에도 켜졌다(메뉴바·레일 점은 메시지만)")
    }

    /// 대화창에 찌르기 줄이 **선다** — 같은 대화에 찌르기 기록을 더하면 패널이 자라고 그림이 바뀐다. 찌르기만 있는 대화도 빈 화면이 아니다.
    @Test(.gomokuDefaultsCleanup)
    func 대화창에_찌르기_줄이_선다() throws {
        let without = try v365Bitmap(v365ConversationView(v365ConversationStore("v365-c0", pokes: false)))
        let with = try v365Bitmap(v365ConversationView(v365ConversationStore("v365-c1", pokes: true)))
        #expect(with.pixelsHigh > without.pixelsHigh, "찌르기 줄 세 개를 더했는데 대화 틀이 안 자랐다")

        let onlyPokes = v365ConversationStore("v365-c2", pokes: true)
        onlyPokes.messageHistory = []
        let empty = v365ConversationStore("v365-c3", pokes: false)
        empty.messageHistory = []
        let pokeOnly = try v365Bitmap(v365ConversationView(onlyPokes))
        let emptyState = try v365Bitmap(v365ConversationView(empty))
        let diff = v365Diff(pokeOnly, emptyState)
        #expect(diff.count != 0, "찌르기만 있는 대화가 '아직 주고받은 메시지가 없어요' 빈 화면으로 그려졌다")

        // 줄이 **그려진다**(자리만 차지하는 빈 줄이 아니다): 같은 자리의 찌르기를 일반 ↔ 울트라로 바꾸면 그 줄의 글자·아이콘이 바뀐다.
        let normal = v365ConversationStore("v365-c4", pokes: true)
        let ultra = v365ConversationStore("v365-c5", pokes: true)
        ultra.messagePokeLog = ultra.messagePokeLog.map { entry in
            MessagePokeLogEntry(id: entry.id, peerUserID: entry.peerUserID, peerName: entry.peerName, createdAt: entry.createdAt,
                                isMine: entry.isMine, kind: entry.kind == .poke ? .ultra : .poke, isUnread: entry.isUnread)
        }
        let kindDiff = v365Diff(try v365Bitmap(v365ConversationView(normal)), try v365Bitmap(v365ConversationView(ultra)))
        #expect(kindDiff.count > 50, "찌르기 줄이 그려지지 않는다(종류를 바꿔도 그림이 같다): \(kindDiff)")
        // 바뀐 곳은 줄 안이다 — 말풍선 자리(가로 전체)가 아니라 가운데 좁은 띠들.
        #expect(kindDiff.box.minX > 20 && kindDiff.box.maxX < CheckMenuView.contentColumnWidth - 20, "\(kindDiff.box)")
    }

    /// 미리보기 PNG(CHECK_V0365_STILLS_DIR 가 있을 때만 — 창은 띄우지 않는다): 목록 네 무리 · 대화창 찌르기 줄, 어둡게/밝게.
    @Test(.gomokuDefaultsCleanup)
    func stills() throws {
        guard let dir = ProcessInfo.processInfo.environment["CHECK_V0365_STILLS_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func save(_ name: String, _ view: some View, scheme: ColorScheme) throws {
            let bitmap = try v365Bitmap(view.environment(\.colorScheme, scheme))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
        }
        for scheme in [ColorScheme.dark, .light] {
            let tag = scheme == .dark ? "d" : "l"
            try save("v0365-list-four-groups",
                     CheckMenuView(store: v365ListStore("v365-s-list-\(tag)", messages: ["u-a", "u-f"], pokes: ["u-b", "u-e"])),
                     scheme: scheme)
            try save("v0365-conversation-pokes", v365ConversationView(v365ConversationStore("v365-s-conv-\(tag)", pokes: true)),
                     scheme: scheme)
        }
    }
}

// MARK: - ⑧ 서버 정의와 클라 전선의 짝 (CHECK_MIGRATIONS_DIR)

private struct V365Error: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func v365MigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw V365Error("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
        }
        return url
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        directory = directory.deletingLastPathComponent()
    }
    throw V365Error("supabase/migrations 를 못 찾았다(CHECK_MIGRATIONS_DIR 로 가리켜라)")
}

/// 번호는 push 때 다시 잡힐 수 있다 — 이름이 아니라 **내용**(새 조회 함수를 정의하는 가장 나중 파일)으로 찾는다.
private func v365MigrationText() throws -> (name: String, sql: String) {
    let directory = try v365MigrationsDirectory()
    let names = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sql" }.map(\.lastPathComponent).sorted()
    for name in names.reversed() {
        let sql = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
        if sql.lowercased().contains("create or replace function public.message_history_with_pokes(") { return (name, sql) }
    }
    throw V365Error("message_history_with_pokes 를 정의하는 마이그레이션이 없다(\(directory.path))")
}

@Suite("V0365MessagePokeMigrationContract")
struct V0365MessagePokeMigrationContractTests {
    @Test func 서버_정의와_클라_전선이_짝이다() throws {
        let (name, raw) = try v365MigrationText()
        let sql = raw.lowercased().replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // 경로 = 함수 이름.
        #expect(SupabaseWorkService.messageHistoryWithPokesPath == "/rest/v1/rpc/message_history_with_pokes")
        #expect(SupabaseWorkService.markConversationReadPath == "/rest/v1/rpc/mark_conversation_read")
        // 조회: 인자 둘(클라가 싣는 두 키) · 반환 12칸 + kind · 종류 글자 셋.
        #expect(sql.contains("function public.message_history_with_pokes(p_hours integer default 24, p_limit integer default 200)"), "\(name)")
        #expect(sql.contains("read_by_peer boolean, unread boolean, kind text)"), "반환 끝 칸이 kind text 가 아니다(\(name))")
        #expect(sql.contains("'message'::text as kind"), "메시지 행의 종류 글자가 'message' 가 아니다")
        #expect(sql.contains("then 'ultra' else 'poke' end"), "찌르기 행의 종류 글자가 'ultra'/'poke' 가 아니다")
        for word in ["message", "poke", "ultra"] {
            #expect(word == "message" || MessagePokeLogKind(serverKind: word) != nil, "클라가 '\(word)' 를 못 읽는다")
        }
        // 읽음: 세 인자 이름 = 클라 요청 키(스네이크 변환 뒤) · 모두 DEFAULT.
        #expect(sql.contains("function public.mark_conversation_read(p_peer uuid default null, p_through_message uuid default null, p_through_poke uuid default null)"),
                "mark_conversation_read 서명이 클라 키와 다르다(\(name))")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(MessageConversationReadMarkRequest(pPeer: "a", pThroughMessage: "m", pThroughPoke: "p"))
        let keys = Set(((try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]).keys)
        #expect(keys == ["p_peer", "p_through_message", "p_through_poke"])
        // 응답 키 = 클라 디코드 칸.
        for key in ["'status', 'ok'", "'advanced'", "'unread'", "'poke_advanced'", "'poke_unread'"] {
            #expect(sql.contains(key), "응답에 \(key) 가 없다")
        }
        // 옛 함수는 그대로 산다(옛 맥 · 폰) — 이 파일이 옛 서명을 다시 만들지 않는다.
        #expect(!sql.contains("function public.mark_messages_read(p_peer uuid, p_through uuid default null, p_through_poke"),
                "옛 mark_messages_read 의 서명을 넓혔다 — 클라는 새 함수를 부른다")
    }
}

// MARK: - ⑨ 릴리스 게이트 (v0.3.65)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(0.3.60 → … → 0.3.64 → 여기).
// 다음 릴리스가 오면 이 둘을 그쪽 파일로 옮기고, 여기는 0.3.65 섹션의 **내용**만 남겨라.
// 줄 수는 **박지 않는다**: 같은 판에 "버그 개선" 세션의 AI 리밋 줄이 더해질 수 있다(명세 §3.5) — 필수 낱말 + 배너 상한 4줄로 잰다.
@Test("버전 0.3.65 / 118 · CHANGELOG 0.3.65 가 맨 위(목록 정렬 · 대화창 찌르기 기록 · 4줄 이하 · 배너 폭 안)")
func v0365VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot
    let build = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let squashed = build.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    #expect(squashed.contains("<key>CFBundleShortVersionString</key><string>0.3.65</string>"))
    #expect(squashed.contains("<key>CFBundleVersion</key><string>118</string>"))

    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.65\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect((2...4).contains(items.count), "항목 \(items)")
    let font = NSFont.preferredFont(forTextStyle: .caption2)
    for item in items {
        let width = ceil((String(item.dropFirst(2)) as NSString).size(withAttributes: [.font: font]).width)
        print("[v0365] 체인지로그 '\(item)' — \(width)pt")
        #expect(width <= 300, "배너 폭에서 잘릴 줄: \(item) (\(width)pt)")
    }
    for banned in ["토큰", "서버", "테스트", "CheckCore", "RPC", "마이그레이션", "💎"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    // 두 변화가 각자 한 줄로 있는가 — 목록 정렬(맨 위) · 대화창 찌르기 기록.
    #expect(items.contains { $0.contains("맨 위") && $0.contains("찌르기") }, "목록 정렬 줄이 없다")
    #expect(items.contains { $0.contains("대화창") && $0.contains("찌른 기록") }, "대화창 찌르기 기록 줄이 없다")
    #expect(changelog.range(of: "## 0.3.65")!.lowerBound < changelog.range(of: "## 0.3.64")!.lowerBound,
            "0.3.65 가 맨 위 섹션이 아니다(릴리스 스크립트가 맨 위 버전을 쓴다)")
}
