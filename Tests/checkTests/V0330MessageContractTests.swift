import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.30 — 메시지 읽음 서버↔앱 **응답 계약**(실제 SQL 출력). 모바일 1차 묶음 X1.
//
// 픽스처 `Fixtures/message-rpc/*.json` 은 스텁 추측이 아니다. 로컬 하네스(마이그레이션 체인 ≤ 20260916220000 +
// S1 최종 SQL 20260917100000_messages_anytime_read_receipts.sql)에 harness.login 으로 authenticated 를 흉내 내
// RPC 를 **실제로 부른 출력 그대로**다. 직렬화는 PostgREST 와 같다(표 반환 = json_agg, jsonb 반환 = 값 그대로).
// 생성기는 `_generate.sh.txt`, 시나리오·호출자·메시지 id·시각은 `_manifest.json` 에 있다.
//
// 시나리오(사람 셋, **아무도 근무 안 함**):
//   S0  C→A c1·c2 · C→B c3             ┐
//   S1  B→A b1·b2·b3                    │ 각 묶음은 **같은 초 안에서 마이크로초만** 다르다(created_epoch 이 같다).
//   S2  A→B a1·a2·a3                    │ 그리고 묶음 안의 **id 사전순은 시간순의 반대**다 — 서버 순서와
//   S3  B→A b4 · A→B a4 · B→A b5        ┘ 클라 화면 정렬(초 → id)이 갈리는 자리를 실제 출력으로 드러낸다.
//   읽음(커밋): A 는 B 를 b2 까지 · B 는 A 를 a2 까지 · B 는 C 를 최신까지.
//   흐름(롤백): A 가 B 를 b5 까지 읽음 / A 가 다른 기기에서 B·C 를 전부 읽음.
//
// 여기서 보는 것: 스텁이 픽스처 **바이트 그대로**를 돌려줄 때 M1 의 서비스 디코드 → 스토어 파생값
// (readByPeer · isUnread · unreadMessagePeerIDs · hasUnreadMessages · 읽음 경계 · drain 말풍선 필터)이
// 시나리오의 사실과 같은가. 기대값은 시나리오에서 손으로 적었다(픽스처에서 뽑지 않는다) — 서버가 바뀌어도, 앱이 바뀌어도 빨개진다.
// 불일치는 고치지 않고 보고한다(X1 명세). 알려진 불일치는 `withKnownIssue` 로 남긴다 — 고쳐지면 그 테스트가 "기록 안 됨"으로 빨개진다.

// MARK: - 픽스처 도구

private struct MessageContractError: Error, CustomStringConvertible {
    let description: String
}

private let messageContractDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/message-rpc", isDirectory: true)

private func messageContractData(_ name: String) throws -> Data {
    try Data(contentsOf: messageContractDirectory.appendingPathComponent("\(name).json"))
}

/// 스텁 응답 본문. 픽스처는 UTF-8 이라 `String` 을 거쳐도 스텁이 내보내는 바이트가 파일과 같다(아래 첫 테스트가 잰다).
private func messageContractText(_ name: String) throws -> String {
    String(decoding: try messageContractData(name), as: UTF8.self)
}

private func messageContractJSON(_ name: String) throws -> Any {
    try JSONSerialization.jsonObject(with: messageContractData(name))
}

private func messageContractObject(_ name: String) throws -> [String: Any] {
    guard let object = try messageContractJSON(name) as? [String: Any] else {
        throw MessageContractError(description: "\(name) 는 JSON 객체가 아니다")
    }
    return object
}

private func messageContractRows(_ name: String) throws -> [[String: Any]] {
    guard let rows = try messageContractJSON(name) as? [[String: Any]] else {
        throw MessageContractError(description: "\(name) 는 JSON 객체 배열이 아니다")
    }
    return rows
}

/// NSNull·키 없음 → nil.
private func messageContractBool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber, !(value is NSNull) else { return nil }
    return number.boolValue
}

/// 매니페스트가 말하는 시나리오의 사실(사람 · 메시지 라벨 ↔ id · 캡처 시각).
private struct MessageContractScenario {
    let a: String
    let b: String
    let c: String
    let idByLabel: [String: String]
    let labelByID: [String: String]
    let createdMicros: [String: Int64]
    let displayNames: [String: String]
    let manifest: [String: Any]

    init() throws {
        manifest = try messageContractObject("_manifest")
        guard let users = manifest["users"] as? [String: String],
              let a = users["A"], let b = users["B"], let c = users["C"],
              let messages = manifest["messages"] as? [String: [String: Any]],
              let preconditions = manifest["preconditions"] as? [String: Any],
              let names = preconditions["display_names"] as? [String: String]
        else { throw MessageContractError(description: "매니페스트 모양이 아니다") }
        self.a = a
        self.b = b
        self.c = c
        var idByLabel: [String: String] = [:]
        var micros: [String: Int64] = [:]
        for (label, fact) in messages {
            guard let id = fact["id"] as? String, let us = (fact["created_at_us"] as? NSNumber)?.int64Value else {
                throw MessageContractError(description: "매니페스트 messages.\(label) 에 id·created_at_us 가 없다")
            }
            idByLabel[label] = id
            micros[id] = us
        }
        self.idByLabel = idByLabel
        labelByID = Dictionary(uniqueKeysWithValues: idByLabel.map { ($0.value, $0.key) })
        createdMicros = micros
        displayNames = names
    }

    func id(_ label: String) -> String { idByLabel[label] ?? "<\(label) 없음>" }
    func label(_ id: String) -> String { labelByID[id] ?? "<모르는 id \(id)>" }
    func labels(_ ids: [String]) -> [String] { ids.map(label) }

    /// "A"·"B"·"C" → uuid.
    func user(_ key: String) -> String {
        switch key {
        case "A": return a
        case "B": return b
        default: return c
        }
    }

    var takePokesServerNow: Date {
        let ms = (manifest["take_pokes_server_now_ms"] as? NSNumber)?.doubleValue ?? 0
        return Date(timeIntervalSince1970: ms / 1000)
    }

    func realtimeRowsAdded(_ key: String) -> Int? {
        ((manifest["realtime_rows_added"] as? [String: Any])?[key] as? NSNumber)?.intValue
    }
}

// MARK: - 조립

@MainActor
private func messageContractService(
    _ label: String,
    handler: @escaping MessageReadStubProtocol.Handler
) -> (SupabaseWorkService, String) {
    let host = "v0330-x1-svc-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    MessageReadStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: MessageReadStubProtocol.session()
    )
    return (service, host)
}

/// 스텁 네트워크에 물린 **로그인·비근무** 스토어(M1 의 조립을 쓰고 세션 사용자만 시나리오 사람으로 바꾼다).
@MainActor
private func messageContractStore(
    _ label: String,
    as userID: String,
    handler: @escaping MessageReadStubProtocol.Handler
) -> (store: WorkTimerStore, host: String) {
    let (store, host) = makeMessageReadStore("x1-\(label)", handler: handler)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    return (store, host)
}

@MainActor
private func messageContractCount(_ host: String, _ rpc: String) -> Int {
    MessageReadStubProtocol.count(host: host, rpc: rpc)
}

/// 이력 픽스처 하나의 기대(시나리오에서 손으로 적은 것). 행 순서는 **서버 순서**다.
struct MessageContractHistoryCase: Sendable, CustomTestStringConvertible {
    /// (라벨, is_mine, readByPeer, isUnread)
    typealias Row = (label: String, isMine: Bool, readByPeer: Bool?, isUnread: Bool?)
    let fixture: String
    let caller: String
    let rows: [Row]
    /// "A"·"B"·"C"
    let unreadPeers: Set<String>

    var testDescription: String { fixture }

    static let baseA: [Row] = [
        ("c1", false, nil, true), ("c2", false, nil, true),
        ("b1", false, nil, false), ("b2", false, nil, false), ("b3", false, nil, true),
        ("a1", true, true, nil), ("a2", true, true, nil), ("a3", true, false, nil),
        ("b4", false, nil, true), ("a4", true, false, nil), ("b5", false, nil, true)
    ]
    static let baseB: [Row] = [
        ("c3", false, nil, false),
        ("b1", true, true, nil), ("b2", true, true, nil), ("b3", true, false, nil),
        ("a1", false, nil, false), ("a2", false, nil, false), ("a3", false, nil, true),
        ("b4", true, false, nil), ("a4", false, nil, true), ("b5", true, false, nil)
    ]

    static func replacing(_ rows: [Row], _ labels: Set<String>, readByPeer: Bool? = nil, isUnread: Bool? = nil) -> [Row] {
        rows.map { row in
            guard labels.contains(row.label) else { return row }
            return (row.label, row.isMine, readByPeer ?? row.readByPeer, isUnread ?? row.isUnread)
        }
    }

    static let all: [MessageContractHistoryCase] = [
        .init(fixture: "message_history_with_reads__a", caller: "A", rows: baseA, unreadPeers: ["B", "C"]),
        .init(fixture: "message_history_with_reads__b", caller: "B", rows: baseB, unreadPeers: ["A"]),
        // A 가 B 를 b5 까지 읽은 뒤 — A 쪽 b3·b4·b5 는 읽음, B 쪽 b3·b4·b5 는 상대가 읽음.
        .init(fixture: "flow_a_reads_b__with_reads_a", caller: "A",
              rows: replacing(baseA, ["b3", "b4", "b5"], isUnread: false), unreadPeers: ["C"]),
        .init(fixture: "flow_a_reads_b__with_reads_b", caller: "B",
              rows: replacing(baseB, ["b3", "b4", "b5"], readByPeer: true), unreadPeers: ["A"]),
        // A 가 다른 기기에서 전부 읽은 뒤.
        .init(fixture: "flow_a_reads_all__with_reads_a", caller: "A",
              rows: replacing(baseA, ["c1", "c2", "b3", "b4", "b5"], isUnread: false), unreadPeers: [])
    ]
}

// MARK: - 0. 픽스처 자체

@Test
func 메시지_계약_픽스처는_매니페스트와_짝이_맞고_시나리오_전제가_참이다() throws {
    let scenario = try MessageContractScenario()
    let listed = Set((scenario.manifest["fixtures"] as? [String: Any])?.keys.map { $0 } ?? [])
    let onDisk = Set(try FileManager.default.contentsOfDirectory(atPath: messageContractDirectory.path)
        .filter { $0.hasSuffix(".json") && !$0.hasPrefix("_") }
        .map { String($0.dropLast(5)) })
    #expect(!listed.isEmpty)
    #expect(listed == onDisk, "매니페스트와 폴더의 픽스처 목록이 다르다: \(listed.symmetricDifference(onDisk).sorted())")
    for name in onDisk.sorted() {
        let data = try messageContractData(name)
        #expect((try? JSONSerialization.jsonObject(with: data)) != nil, "\(name) 가 JSON 이 아니다")
        // 스텁은 String 을 거쳐 바이트를 내보낸다 — 왕복해도 파일 바이트와 같아야 "바이트 그대로"다.
        #expect(Data(try messageContractText(name).utf8) == data, "\(name) 가 UTF-8 왕복에서 바이트가 바뀐다")
    }
    // 시나리오 전제: 셋 다 근무 안 함 · 보관 24시간 · 열두 메시지.
    let preconditions = try #require(scenario.manifest["preconditions"] as? [String: Any])
    #expect((preconditions["open_work_sessions"] as? NSNumber)?.intValue == 0)
    #expect(messageContractBool(preconditions["blackout_active"]) == false)
    #expect((preconditions["message_retention_hours"] as? NSNumber)?.intValue == WorkTimerStore.messageHistoryHours)
    #expect(scenario.idByLabel.count == 12)
    // 같은 초 묶음 안에서 id 사전순이 시간순의 반대라는 전제(이게 거짓이면 아래 서버 순서 테스트들이 공허해진다).
    for group in [["b1", "b2", "b3"], ["a1", "a2", "a3"], ["c1", "c2"]] {
        let ids = group.map(scenario.id)
        #expect(ids.sorted(by: >) == ids, "\(group) 의 id 가 시간순의 역순이 아니다")
        let micros = ids.compactMap { scenario.createdMicros[$0] }
        #expect(micros == micros.sorted() && Set(micros.map { $0 / 1_000_000 }).count == 1, "\(group) 이 같은 초가 아니다")
    }
}

// MARK: - 1. with_reads 디코드(서비스)

@MainActor
@Test(arguments: MessageContractHistoryCase.all)
func with_reads_실제_출력은_행을_잃지_않고_읽음_칸이_시나리오와_같다(_ testCase: MessageContractHistoryCase) async throws {
    let scenario = try MessageContractScenario()
    let body = try messageContractText(testCase.fixture)
    let raw = try messageContractRows(testCase.fixture)
    let (service, host) = messageContractService("hist") { call, _ in
        call.rpc == "message_history_with_reads" ? MessageReadStubProtocol.Reply(body: body) : nil
    }
    let entries = try await service.fetchMessageHistoryWithReads(
        accessToken: "t", hours: WorkTimerStore.messageHistoryHours, limit: WorkTimerStore.messageHistoryLimit
    )

    // 픽스처는 (24, 200) 으로 떴다 — 앱이 같은 인자로 부를 때만 이 모양이 온다.
    let sent = MessageReadStubProtocol.calls(host: host, rpc: "message_history_with_reads").first?.json
    #expect(sent?["p_hours"] as? Int == 24)
    #expect(sent?["p_limit"] as? Int == 200)

    // 행을 하나도 버리지 않고 서버 순서 그대로.
    #expect(entries.map(\.id) == raw.compactMap { $0["id"] as? String }, "서비스가 행을 버렸거나 순서를 바꿨다")
    #expect(scenario.labels(entries.map(\.id)) == testCase.rows.map(\.label), "서버 순서가 시나리오와 다르다")

    let me = scenario.user(testCase.caller)
    for (entry, (expected, row)) in zip(entries, zip(testCase.rows, raw)) {
        let label = expected.label
        #expect(entry.isMine == expected.isMine, "\(label) is_mine")
        #expect(entry.readByPeer == expected.readByPeer, "\(label) readByPeer: \(String(describing: entry.readByPeer))")
        #expect(entry.isUnread == expected.isUnread, "\(label) isUnread: \(String(describing: entry.isUnread))")
        // 서버 칸과 옮긴 값의 대조(뜻을 갖는 쪽에만 싣는다).
        let isMine = messageContractBool(row["is_mine"]) ?? false
        #expect(entry.readByPeer == (isMine ? messageContractBool(row["read_by_peer"]) : nil), "\(label) read_by_peer 옮김")
        #expect(entry.isUnread == (isMine ? nil : messageContractBool(row["unread"])), "\(label) unread 옮김")
        // 상대 · 이름 · 시각(epoch 초)
        let peer = isMine ? row["to_user"] as? String : row["from_user"] as? String
        #expect(entry.peerUserID == peer && entry.peerUserID != me, "\(label) 상대")
        #expect(entry.peerName == scenario.displayNames[entry.peerUserID], "\(label) 상대 이름")
        #expect(entry.createdAt == Date(timeIntervalSince1970: TimeInterval((row["created_epoch"] as? NSNumber)?.intValue ?? -1)))
        #expect(entry.body == row["body"] as? String, "\(label) 본문")
    }
}

@MainActor
@Test
func with_reads_의_ISO_시각_폴백은_서버의_소수초_4자리_오프셋_모양을_읽는다() async throws {
    // created_epoch 이 정본이지만 빠진 서버에서는 created_at(ISO)로 접는다. 서버는 끝 0 을 떼어 "…40.1001+00:00" 처럼 준다.
    let scenario = try MessageContractScenario()
    let (service, _) = messageContractService("iso") { _, _ in nil }
    for row in try messageContractRows("message_history_with_reads__a") {
        let text = try #require(row["created_at"] as? String)
        let id = try #require(row["id"] as? String)
        let micros = try #require(scenario.createdMicros[id])
        let parsed = await service.parseDate(text)
        #expect(parsed != nil, "서버 시각 문자열을 못 읽는다: \(text)")
        if let parsed {
            #expect(abs(parsed.timeIntervalSince1970 - Double(micros) / 1_000_000) < 0.001, "\(text) → \(parsed.timeIntervalSince1970)")
        }
    }
}

@MainActor
@Test
func 옛_message_history_실제_출력은_with_reads_에서_읽음_칸만_뺀_것과_같다() async throws {
    let withReadsBody = try messageContractText("message_history_with_reads__a")
    let legacyBody = try messageContractText("message_history__a")
    // 서버: 앞 10칸이 글자 그대로 같다.
    let withReadsRaw = try messageContractRows("message_history_with_reads__a")
    let legacyRaw = try messageContractRows("message_history__a")
    #expect(withReadsRaw.count == legacyRaw.count)
    for (lhs, rhs) in zip(withReadsRaw, legacyRaw) {
        var stripped = lhs
        stripped["read_by_peer"] = nil
        stripped["unread"] = nil
        #expect(NSDictionary(dictionary: stripped).isEqual(to: rhs), "with_reads 앞 10칸이 message_history 와 다르다: \(rhs["id"] ?? "?")")
    }
    // 앱: 두 옮김 경로가 같은 표시값을 만든다(읽음 칸만 다르다).
    let (service, _) = messageContractService("legacy") { call, _ in
        switch call.rpc {
        case "message_history_with_reads": return MessageReadStubProtocol.Reply(body: withReadsBody)
        case "message_history": return MessageReadStubProtocol.Reply(body: legacyBody)
        default: return nil
        }
    }
    let withReads = try await service.fetchMessageHistoryWithReads(accessToken: "t", hours: 24, limit: 200)
    let legacy = try await service.fetchMessageHistory(accessToken: "t", hours: 24, limit: 200)
    let stripped = withReads.map { entry -> MessageHistoryEntry in
        var copy = entry
        copy.readByPeer = nil
        copy.isUnread = nil
        return copy
    }
    #expect(stripped == legacy)
    #expect(legacy.allSatisfy { $0.readByPeer == nil && $0.isUnread == nil }, "옛 이력인데 읽음 칸이 생겼다")
}

// MARK: - 2. 스토어 파생값

@MainActor
@Test(.gomokuDefaultsCleanup, arguments: MessageContractHistoryCase.all)
func 스토어는_실제_이력으로_안읽음_상대와_점을_서버_판정대로_세운다(_ testCase: MessageContractHistoryCase) async throws {
    let scenario = try MessageContractScenario()
    let body = try messageContractText(testCase.fixture)
    let (store, host) = messageContractStore("store-hist", as: scenario.user(testCase.caller)) { call, _ in
        call.rpc == "message_history_with_reads" ? MessageReadStubProtocol.Reply(body: body) : nil
    }
    await store.performLoadMessageHistory()

    #expect(messageContractCount(host, "message_history") == 0, "읽음 함수가 있는데 옛 이력으로 접었다")
    #expect(store.messageReadReceiptsAvailable)
    #expect(!store.messageHistoryFailed)
    #expect(store.messageHistory.count == testCase.rows.count)
    // 서버 순서는 스냅샷이 그대로 들고 있어야 한다(같은 초 안의 선후를 아는 유일한 근거).
    let snapshot = try #require(store.messageHistoryReadSnapshot)
    for (index, row) in testCase.rows.enumerated() {
        #expect(snapshot.serverOrder[scenario.id(row.label)] == index, "\(row.label) 의 서버 자리")
    }
    let byID = Dictionary(uniqueKeysWithValues: store.messageHistory.map { ($0.id, $0) })
    for row in testCase.rows {
        let entry = byID[scenario.id(row.label)]
        #expect(entry?.readByPeer == row.readByPeer, "\(row.label) readByPeer")
        #expect(entry?.isUnread == row.isUnread, "\(row.label) isUnread")
    }
    let expectedPeers = Set(testCase.unreadPeers.map(scenario.user))
    #expect(store.unreadMessagePeerIDs == expectedPeers,
            "안 읽음 상대: \(store.unreadMessagePeerIDs.map { $0.prefix(8) }.sorted()) 기대 \(testCase.unreadPeers.sorted())")
    #expect(store.hasUnreadMessages == !expectedPeers.isEmpty)
}

// MARK: - 3. 요약

@MainActor
@Test(.gomokuDefaultsCleanup)
func 요약_실제_출력은_count_0_상대를_빼고_최근순으로_스토어_점이_된다() async throws {
    let scenario = try MessageContractScenario()
    // (픽스처, 호출자, 기대 상대 순서, 기대 개수, 기대 total, 상대별 마지막으로 받은 안 읽은 메시지 라벨)
    let cases: [(String, String, [String], [Int], Int, [String])] = [
        ("message_unread_summary__a", "A", ["B", "C"], [3, 2], 5, ["b5", "c2"]),
        ("message_unread_summary__b", "B", ["A"], [2], 2, ["a4"]),     // C→B c3 는 읽어서 빠진다
        ("flow_a_reads_b__summary", "A", ["C"], [2], 2, ["c2"]),
        ("flow_a_reads_all__summary", "A", [], [], 0, [])
    ]
    for (fixture, caller, peers, counts, total, lastLabels) in cases {
        let body = try messageContractText(fixture)
        let (service, _) = messageContractService("summary") { _, _ in MessageReadStubProtocol.Reply(body: body) }
        let response = try await service.fetchMessageUnreadSummary(accessToken: "t")
        let summary = try #require(response.summary, "\(fixture): ok 인데 요약이 nil")
        #expect(summary.peers.map(\.peerUserID) == peers.map(scenario.user), "\(fixture) 상대 순서")
        #expect(summary.peers.map(\.count) == counts, "\(fixture) 개수")
        #expect(summary.total == total, "\(fixture) total")
        for (peer, label) in zip(summary.peers, lastLabels) {
            let micros = try #require(scenario.createdMicros[scenario.id(label)])
            let expectedMs = Double(micros / 1000)
            #expect(peer.lastMessageAt == Date(timeIntervalSince1970: expectedMs / 1000), "\(fixture) \(label) 시각")
        }

        let (store, _) = messageContractStore("store-summary", as: scenario.user(caller)) { call, _ in
            call.rpc == "message_unread_summary" ? MessageReadStubProtocol.Reply(body: body) : nil
        }
        await store.performLoadMessageUnreadSummary()
        #expect(store.messageUnreadSummary?.summary == summary)
        #expect(store.unreadMessagePeerIDs == Set(peers.map(scenario.user)), "\(fixture) 스토어 점")
        #expect(store.hasUnreadMessages == !peers.isEmpty)
    }

    // 미로그인 응답은 "안 읽은 것 0"이 아니라 **스냅샷 없음**이다.
    let unauthorized = try messageContractText("message_unread_summary__unauthorized")
    let (service, _) = messageContractService("summary-unauth") { _, _ in MessageReadStubProtocol.Reply(body: unauthorized) }
    let response = try await service.fetchMessageUnreadSummary(accessToken: "t")
    #expect(response.status == "unauthorized")
    #expect(response.summary == nil)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 다른_기기에서_전부_읽은_실제_요약이_오면_맥의_점이_꺼진다() async throws {
    let scenario = try MessageContractScenario()
    let before = try messageContractText("message_history_with_reads__a")
    let after = try messageContractText("flow_a_reads_all__with_reads_a")
    let summary = try messageContractText("flow_a_reads_all__summary")
    let (store, _) = messageContractStore("other-device", as: scenario.a) { call, index in
        switch call.rpc {
        case "message_history_with_reads": return MessageReadStubProtocol.Reply(body: index == 0 ? before : after)
        case "message_unread_summary": return MessageReadStubProtocol.Reply(body: summary)
        default: return nil
        }
    }
    await store.performLoadMessageHistory()
    #expect(store.unreadMessagePeerIDs == [scenario.b, scenario.c])

    await store.performLoadMessageUnreadSummary()
    #expect(store.messageUnreadSummary?.summary.total == 0)
    #expect(store.unreadMessagePeerIDs.isEmpty, "폰에서 다 읽었는데 맥의 점이 남았다")
    #expect(!store.hasUnreadMessages)

    await store.performLoadMessageHistory()
    #expect(store.unreadMessagePeerIDs.isEmpty)
}

// MARK: - 4. 읽음 처리

@MainActor
@Test
func 읽음_처리_실제_응답은_status_advanced_unread_를_그대로_옮긴다() async throws {
    // (픽스처, status, advanced, unread)
    let cases: [(String, String, Bool?, Int?)] = [
        ("mark_messages_read__advanced", "ok", true, 3),
        ("mark_messages_read__advanced_b_through_a2", "ok", true, 2),
        ("mark_messages_read__advanced_latest", "ok", true, 0),
        ("mark_messages_read__not_advanced", "ok", false, 3),
        ("mark_messages_read__not_advanced_own_message", "ok", false, 3),
        ("mark_messages_read__invalid_self", "invalid", nil, nil),
        ("mark_messages_read__invalid_null_peer", "invalid", nil, nil),
        ("mark_messages_read__unauthorized", "unauthorized", nil, nil),
        ("flow_a_reads_b__mark", "ok", true, 0)
    ]
    for (fixture, status, advanced, unread) in cases {
        let body = try messageContractText(fixture)
        let raw = try messageContractObject(fixture)
        let (service, _) = messageContractService("mark") { _, _ in MessageReadStubProtocol.Reply(body: body) }
        let response = try await service.markMessagesRead(accessToken: "t", peerUserID: "peer", throughMessageID: "x")
        #expect(response == MessageReadMarkResponse(status: status, advanced: advanced, unread: unread), "\(fixture): \(response)")
        #expect(response.status == raw["status"] as? String)
        #expect(response.advanced == messageContractBool(raw["advanced"]))
        #expect(response.unread == (raw["unread"] as? NSNumber)?.intValue)
        #expect(response.isOK == (status == "ok"), "\(fixture) isOK")
    }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 대화를_열면_서버_순서의_마지막_받은_메시지까지_읽고_실제_응답으로_서버_판정에_넘어간다() async throws {
    let scenario = try MessageContractScenario()
    let before = try messageContractText("message_history_with_reads__a")
    let after = try messageContractText("flow_a_reads_b__with_reads_a")
    let mark = try messageContractText("flow_a_reads_b__mark")
    let summary = try messageContractText("flow_a_reads_b__summary")
    let (store, host) = messageContractStore("flow-read-b", as: scenario.a) { call, index in
        switch call.rpc {
        case "message_history_with_reads": return MessageReadStubProtocol.Reply(body: index == 0 ? before : after)
        // 응답을 늦춰 날아가는 동안의 낙관 읽음을 본다.
        case "mark_messages_read": return MessageReadStubProtocol.Reply(body: mark, delay: 0.8)
        case "message_unread_summary": return MessageReadStubProtocol.Reply(body: summary)
        default: return nil
        }
    }
    store.isMenuPresented = true
    store.isMessagePanelVisible = true
    store.selectedMessagePeerID = scenario.b

    await store.performLoadMessageHistory()
    await messageReadWait { messageContractCount(host, "mark_messages_read") >= 1 }

    // 경계 = 서버 순서로 그 대화의 마지막 받은 메시지(b5). 같은 초 안에서 b4·a4·b5 가 오갔고 id 사전순은 b5 < b4 다.
    let sent = try #require(MessageReadStubProtocol.calls(host: host, rpc: "mark_messages_read").first?.json)
    #expect(sent["p_peer"] as? String == scenario.b)
    #expect((sent["p_through"] as? String).map(scenario.label) == "b5", "경계가 서버 순서의 마지막 받은 메시지가 아니다")
    // 날아가는 동안: 낙관 읽음이 서버 순서로 b3·b4·b5 를 덮어 B 의 점이 곧바로 꺼진다(C 는 남는다).
    #expect(store.messageReadRuntime.markInFlight.contains(scenario.b), "전제: 응답(0.8초 지연) 전이다")
    #expect(store.unreadMessagePeerIDs == [scenario.c], "낙관 읽음이 같은 초 안의 받은 메시지를 못 덮었다")

    await messageReadWait {
        messageContractCount(host, "message_unread_summary") >= 1
            && messageContractCount(host, "message_history_with_reads") >= 2
            && messageReadIdle(store)
    }
    #expect(messageContractCount(host, "mark_messages_read") == 1, "같은 경계로 두 번 올렸다")
    #expect(messageContractCount(host, "message_unread_summary") == 1)
    #expect(messageContractCount(host, "message_history_with_reads") == 2)
    #expect(store.messageOptimisticReads[scenario.b]?.settledSerial != nil)
    #expect(store.messageOptimisticReads[scenario.b]?.failed == false)
    #expect(store.unreadMessagePeerIDs == [scenario.c])
    #expect(store.hasUnreadMessages)
    let byID = Dictionary(uniqueKeysWithValues: store.messageHistory.map { ($0.id, $0) })
    for label in ["b3", "b4", "b5"] {
        #expect(byID[scenario.id(label)]?.isUnread == false, "\(label) 가 서버 판정으로 읽음이 되지 않았다")
    }
}

@Test
func 읽음_신호_실제_행은_보낸_사람과_읽은_사람_채널로_앱이_가르는_이벤트_이름으로_간다() throws {
    let scenario = try MessageContractScenario()
    let rows = try messageContractRows("realtime__message_read_rows")
    // 커밋된 읽음 셋: A 가 B 를 · B 가 A 를 · B 가 C 를.
    let expected: [(reader: String, sender: String)] = [(scenario.a, scenario.b), (scenario.b, scenario.a), (scenario.b, scenario.c)]
    // 신호는 **보낸 사람 채널**(명세 §1.1)과 — 부록 B-1(m-fix2 결정) 뒤로는 — **읽은 사람 자신의 채널**에 같은 payload 로 간다.
    // 이 픽스처는 X1 이 S1 초안(B-1 전)으로 뽑았다. S1 수리본으로 다시 뽑으면 읽은 사람 채널 행이 읽음마다 하나씩 붙는다 —
    // 그래서 읽은 사람 채널 행은 "없거나(B-1 전) 읽음마다 정확히 하나(B-1 뒤)"로 잰다. 섞인 개수·남의 채널·다른 payload 는 결함이다.
    // (행 순서는 inserted_at·topic 이라 한 커밋의 두 행 순서는 사용자 id 사전순에 달렸다 — 순서가 아니라 짝으로 맞춘다.)
    let senderRows = rows.filter { row in
        expected.contains { RealtimeLinkConstants.pokeChannel(userID: $0.sender) == row["topic"] as? String
            && ($0.reader == ((row["payload_without_id"] as? [String: Any])?["r"] as? String)) }
    }
    let selfRows = rows.filter { row in
        let reader = (row["payload_without_id"] as? [String: Any])?["r"] as? String
        return reader.map { RealtimeLinkConstants.pokeChannel(userID: $0) } == row["topic"] as? String
    }
    #expect(senderRows.count == expected.count, "보낸 사람 채널 신호가 읽음마다 하나가 아니다")
    #expect(selfRows.isEmpty || selfRows.count == expected.count,
            "읽은 사람 채널 신호가 읽음마다 하나가 아니다(\(selfRows.count)건 — B-1 은 advanced 마다 정확히 한 번)")
    #expect(rows.count == senderRows.count + selfRows.count, "보낸 사람·읽은 사람 채널이 아닌 곳으로 간 신호가 있다")
    for pair in expected {
        let sender = RealtimeLinkConstants.pokeChannel(userID: pair.sender)
        #expect(senderRows.filter { $0["topic"] as? String == sender && messageContractReader($0) == pair.reader }.count == 1)
    }
    if !selfRows.isEmpty {
        // 읽은 사람 채널 행은 (채널, payload) 가 같아 읽음끼리 구별되지 않는다(B 가 A 를·C 를 읽은 두 행은 똑같다) — 사람별 개수로 잰다.
        for reader in Set(expected.map(\.reader)) {
            let channel = RealtimeLinkConstants.pokeChannel(userID: reader)
            #expect(selfRows.filter { $0["topic"] as? String == channel }.count == expected.filter { $0.reader == reader }.count,
                    "읽은 사람 채널 신호 수가 그 사람의 읽음 수와 다르다")
        }
    }

    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    for row in rows {
        let event = try #require(row["event"] as? String)
        let topic = try #require(row["topic"] as? String)
        #expect(event == RealtimeLinkConstants.messageReadBroadcastEvent)
        #expect(messageContractBool(row["private"]) == true)
        let payload = try #require(row["payload_without_id"] as? [String: Any])
        #expect((payload["v"] as? NSNumber)?.intValue == 1)
        #expect(Set(payload.keys) == ["v", "r"])
        #expect(messageContractBool(row["payload_has_id"]) == true, "realtime.send 가 id 를 덧붙이는 모양이 아니다(셰임 확인)")

        // 그 채널을 구독한 맥이 받는 Phoenix 프레임(payload 에 id 가 붙은 모양)으로 전선에서 잰다: 이름만 넘기고 payload 는 안 본다.
        var delivered = payload
        delivered["id"] = "00000000-0000-4000-8000-0000000000ff"
        let frame = MessageReadFixture.json([
            "event": "broadcast",
            "topic": RealtimeFrame.wireTopic(channel: topic),
            "payload": ["event": event, "payload": delivered, "type": "broadcast"],
            "ref": NSNull()
        ])
        #expect(RealtimeFrame.decode(text: frame, channel: topic, joinRef: "1") == .broadcast(event: event))
        // 남의 채널 프레임은 우리 것으로 오인하지 않는다.
        #expect(RealtimeFrame.decode(text: frame, channel: RealtimeLinkConstants.pokeChannel(userID: "someone-else"), joinRef: "1") == nil)

        var link = RealtimeLink(transportAvailable: true)
        _ = link.apply(.signedIn(accessToken: "tok"), now: t0, jitter: { $0 })
        _ = link.apply(.transport(.joined), now: t0, jitter: { $0 })
        #expect(link.apply(.transport(.broadcast(event: event)), now: t0 + 1, jitter: { $0 }) == [.messageReadSignal])
    }
    // 경계가 안 커진 호출(작은 p_through · 내가 보낸 id)은 신호 0건, 흐름의 읽음 한 번은 채널 수만큼(B-1 전 1 · 뒤 2).
    #expect(scenario.realtimeRowsAdded("not_advanced_calls") == 0)
    #expect(scenario.realtimeRowsAdded("flow_a_reads_b") == (selfRows.isEmpty ? 1 : 2))
}

/// 신호 행 payload 의 읽은 사람(`r`).
private func messageContractReader(_ row: [String: Any]) -> String? {
    (row["payload_without_id"] as? [String: Any])?["r"] as? String
}

// MARK: - 5. 보내기 · drain 말풍선

@MainActor
@Test(.gomokuDefaultsCleanup)
func 근무_안_하는_사람의_보내기는_실제_ok_응답으로_보냈어요가_된다() async throws {
    let scenario = try MessageContractScenario()
    let body = try messageContractText("send_message__ok_not_working")
    let raw = try messageContractObject("send_message__ok_not_working")
    let draft = "  근무 안 해도 보내져요  "

    let (service, _) = messageContractService("send") { call, _ in
        call.rpc == "send_message" ? MessageReadStubProtocol.Reply(body: body) : nil
    }
    let response = try await service.sendMessage(accessToken: "t", to: scenario.b, body: draft)
    #expect(MessageSendOutcome(response: response) == .ok)
    #expect(response.ring == raw["ring"] as? String)

    let (store, host) = messageContractStore("send", as: scenario.a) { call, _ in
        call.rpc == "send_message" ? MessageReadStubProtocol.Reply(body: body) : nil
    }
    #expect(store.startedAt == nil, "전제: 근무 안 함")
    store.sendMessage(to: scenario.b, body: draft)
    await messageReadWait { messageContractCount(host, "send_message") >= 1 && !store.isSendingMessage }
    #expect(messageContractCount(host, "send_message") == 1, "근무 선게이트가 전송을 막았다")
    #expect(store.messageNotice == WorkTimerStore.messageSentNotice)
    let sent = try #require(MessageReadStubProtocol.calls(host: host, rpc: "send_message").first?.json)
    #expect(sent["p_to"] as? String == scenario.b)
    // 클라 정규화와 서버 정규화가 같은 글자를 만든다(서버가 돌려준 저장값과 클라가 보낸 값).
    #expect(sent["p_body"] as? String == raw["body"] as? String)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 근무_시작_drain_은_실제_take_pokes_중_서버가_읽었다고_한_메시지를_말풍선으로_안_띄운다() async throws {
    let scenario = try MessageContractScenario()
    let history = try messageContractText("message_history_with_reads__a")
    let taken = try messageContractText("take_pokes__a")
    let (store, _) = messageContractStore("drain", as: scenario.a) { call, _ in
        switch call.rpc {
        case "message_history_with_reads": return MessageReadStubProtocol.Reply(body: history)
        case "take_pokes": return MessageReadStubProtocol.Reply(body: taken)
        default: return nil
        }
    }
    await store.performLoadMessageHistory()
    let rows = try await store.service.takePokes(accessToken: "t")
    #expect(scenario.labels(rows.map(\.id)) == ["c1", "c2", "b1", "b2", "b3", "b4", "b5"])
    // take_pokes 의 id 와 이력의 id 는 같은 공간이다(필터가 id 로 맞춘다).
    #expect(Set(rows.map(\.id)).isSubset(of: Set(store.messageHistory.map(\.id))))

    // drainReceivedPokes 는 신선도(5분)를 벽시계로 재므로 픽스처 시각에는 전부 낡는다 — 같은 두 함수를 캡처 시각으로 잇는다.
    let fresh = WorkTimerStore.freshReceivedMessages(rows: rows, now: scenario.takePokesServerNow)
    #expect(fresh.count == 7, "캡처 시각 기준으로도 5분 안이어야 한다")
    let bubbles = fresh.filter { !store.isMessageAlreadyReadForBubble($0) }
    #expect(Set(scenario.labels(bubbles.map(\.id))) == ["c1", "c2", "b3", "b4", "b5"],
            "서버가 읽었다고 한 b1·b2 만 빠져야 한다: \(scenario.labels(bubbles.map(\.id)))")
}

// MARK: - 6. 같은 초 안의 표시 순서 (X1 이 찾고 m-fix F7 이 고쳤다)

@MainActor
@Test(.gomokuDefaultsCleanup)
func 같은_초_안에서_오간_대화의_표시_순서는_서버_순서와_같아야_한다() async throws {
    let scenario = try MessageContractScenario()
    let body = try messageContractText("message_history_with_reads__a")
    let (store, _) = messageContractStore("display-order", as: scenario.a) { call, _ in
        call.rpc == "message_history_with_reads" ? MessageReadStubProtocol.Reply(body: body) : nil
    }
    await store.performLoadMessageHistory()
    store.selectedMessagePeerID = scenario.b
    // 화면이 실제로 읽는 길(`selectedMessageThread` → `messageThreads`)로 잰다.
    let thread = try #require(store.selectedMessageThread)
    let shown = scenario.labels(thread.messages.map(\.id))
    let server = ["b1", "b2", "b3", "a1", "a2", "a3", "b4", "a4", "b5"]
    // created_epoch 은 초(반올림)라 같은 초 안의 말은 동률이다. 동률을 **id 사전순**으로 깨면 실제 출력으로
    // [b3 b2 b1 a3 a2 a1 a4 b5 b4] 로 그려졌다(답장이 질문보다 위 — X1). 동률은 서버 순서로 깬다.
    #expect(shown == server, "화면 순서 \(shown)")
    #expect(scenario.labels(store.messageHistory.filter { $0.peerUserID == scenario.b }.map(\.id)) == server)
}
