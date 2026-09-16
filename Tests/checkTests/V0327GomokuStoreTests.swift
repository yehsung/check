import Foundation
import Testing
@testable import check

// v0.3.27 — 1:1 오목 스토어(GomokuStore) 계약.
//
// 서버는 스텁이다(호스트별 스크립트 응답 — 테스트마다 고유 호스트라 병렬 스위트가 서로의 기록·응답을 덮지 않는다).
// 스텁이 못 잡는 것(서버 정규화·자기 쓰기 에코·실제 시간 경과·배달)은 통합자의 두 계정 e2e 몫이다 — 여기서
// 지키는 것은 스토어가 **응답을 어떻게 옮기는가**와 **언제 요청을 내는가**다.

// MARK: - 스텁

/// 호스트별로 RPC 응답을 스크립트하는 URLProtocol. 요청은 도착 순서대로 기록한다.
final class GomokuStubProtocol: URLProtocol {
    struct Reply: Sendable {
        var status: Int = 200
        var body: String
        var delay: TimeInterval = 0
    }

    struct Call: Sendable {
        /// `/rest/v1/rpc/<name>` 이면 name, 아니면 경로 그대로.
        let rpc: String
        let body: String

        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        }
    }

    /// (rpc, 본문, 같은 rpc 의 몇 번째 호출인가 0부터) → 응답. nil 이면 `[]`(200).
    typealias Handler = @Sendable (_ rpc: String, _ body: String, _ index: Int) -> Reply?

    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [String: Handler] = [:]
    private nonisolated(unsafe) static var callsByHost: [String: [Call]] = [:]

    static func register(host: String, handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[host] = handler
        callsByHost[host] = []
    }

    static func calls(host: String) -> [Call] {
        lock.lock()
        defer { lock.unlock() }
        return callsByHost[host] ?? []
    }

    static func calls(host: String, rpc: String) -> [Call] {
        calls(host: host).filter { $0.rpc == rpc }
    }

    static func count(host: String, rpc: String) -> Int {
        calls(host: host, rpc: rpc).count
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GomokuStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let prefix = "/rest/v1/rpc/"
        let rpc = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        let body = Self.bodyText(from: request)
        Self.lock.lock()
        let index = (Self.callsByHost[host] ?? []).filter { $0.rpc == rpc }.count
        Self.callsByHost[host, default: []].append(Call(rpc: rpc, body: body))
        let handler = Self.handlers[host]
        Self.lock.unlock()

        let reply = handler?(rpc, body, index) ?? Reply(body: "[]")
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let delivery = Delivery(proto: self, response: response, data: Data(reply.body.utf8))
        if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { delivery.run() }
        } else {
            delivery.run()
        }
    }

    override func stopLoading() {}

    private final class Delivery: @unchecked Sendable {
        let proto: GomokuStubProtocol
        let response: HTTPURLResponse
        let data: Data

        init(proto: GomokuStubProtocol, response: HTTPURLResponse, data: Data) {
            self.proto = proto
            self.response = response
            self.data = data
        }

        func run() {
            proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: data)
            proto.client?.urlProtocolDidFinishLoading(proto)
        }
    }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: size)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - 픽스처

private let me = "00000000-0000-0000-0000-0000000000a1"
private let rival = "00000000-0000-0000-0000-0000000000b2"
private let matchID = "11111111-2222-3333-4444-555555555555"

private struct Mv: Sendable {
    let seq: Int
    let color: String
    let x: Int?
    let y: Int?
}

private func jsonText(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

private func userObject(_ id: String, _ name: String) -> [String: Any] {
    ["user_id": id, "display_name": name, "avatar_url": NSNull(), "character": "aing"]
}

/// gomoku_state 의 ok 묶음(최상위 모양). 쓰기 RPC 는 이것을 `state` 키에 싣는다.
private func statePayload(
    matchStatus: String = "active",
    myColor: String = "black",
    moves: [Mv] = [],
    moveCount: Int? = nil,
    turn: String? = "black",
    deadlineMs: Double? = nil,
    serverNowMs: Double? = nil,
    result: String? = nil,
    endReason: String? = nil,
    stake: Int = 5,
    ruby: Int? = nil
) -> [String: Any] {
    let match: [String: Any] = [
        "id": matchID,
        "status": matchStatus,
        "stake": stake,
        "black": myColor == "black" ? me : rival,
        "white": myColor == "black" ? rival : me,
        "challenger": rival,
        "opponent": me,
        "move_count": moveCount ?? moves.count,
        "turn": turn ?? NSNull(),
        "deadline_ms": deadlineMs ?? NSNull(),
        "result": result ?? NSNull(),
        "end_reason": endReason ?? NSNull(),
        "winner": NSNull(),
        "invite_expires_ms": NSNull()
    ]
    return [
        "status": "ok",
        "match": match,
        "moves": moves.map { move -> [String: Any] in
            [
                "seq": move.seq, "color": move.color,
                "x": move.x.map { $0 as Any } ?? NSNull(), "y": move.y.map { $0 as Any } ?? NSNull(),
                "kind": move.x == nil ? "pass" : "stone"
            ]
        },
        "my_color": myColor,
        "opponent": userObject(rival, "라이벌"),
        "ruby_balance": ruby.map { $0 as Any } ?? NSNull(),
        "server_now_ms": serverNowMs ?? NSNull()
    ]
}

private func reply(_ object: [String: Any], delay: TimeInterval = 0) -> GomokuStubProtocol.Reply {
    GomokuStubProtocol.Reply(body: jsonText(object), delay: delay)
}

private func decodePayload(_ object: [String: Any]) -> GomokuStatePayload {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(GomokuStatePayload.self, from: Data(jsonText(object).utf8))
}

private func snakeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}

@MainActor
private func makeGomokuStore(
    _ label: String,
    handler: @escaping GomokuStubProtocol.Handler = { _, _, _ in nil }
) -> (WorkTimerStore, GomokuStore, String) {
    let host = "v0327-g-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: GomokuStubProtocol.session()
    )
    // 테스트가 끝나면 지운다(@Test(.gomokuDefaultsCleanup)) — 안 지우면 실행마다 plist 가 쌓인다.
    let defaults = GomokuTestDefaults.make("v0327-gomoku")
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    GomokuTestRetention.stores.append(store)
    return (store, store.gomoku, host)
}

/// WorkTimerStore 가 오목 스토어를 소유하고, 오목 스토어는 WorkTimerStore 를 **약참조**한다(제품 계약 — 순환 참조 금지).
/// 그래서 테스트가 튜플에서 WorkTimerStore 를 `_` 로 버리면 곧바로 해제되어 host 가 nil 이 되고 요청이 한 건도
/// 안 나간다(실제로 그렇게 빨개졌다). 테스트 프로세스 동안 붙잡아 둔다.
@MainActor
private enum GomokuTestRetention {
    static var stores: [WorkTimerStore] = []
}

@MainActor
private func gomokuWait(_ timeout: TimeInterval = 60, _ condition: @MainActor () -> Bool) async {
    // 상한은 벽시계가 아니라 **재개 횟수**다(5ms 한 번 = 한 차례). 전체 스위트에서는 렌더 테스트가 메인 액터를 수십 초씩 쥐어
    // 벽시계 상한이 스토어의 Task 가 차례를 받기도 전에 끝났다(0.3.27 전체 실행: 690초 지점에서 20초 대기 실패, 격리 3/3 초록).
    // V0325TooltipTests.waitUntil 과 같은 해법 — 재개마다 메인 액터 차례를 거치므로 스토어의 Task 도 같은 줄에서 순서를 받는다.
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private final class Tally {
    var count = 0
    var ids: [String] = []
}

/// 흑 차례, 흑이 H8(7,7)·백이 I8(8,7)을 둔 판(내가 흑).
@MainActor
private func seedTwoMoveMatch(_ gomoku: GomokuStore, stake: Int = 5, myColor: String = "black", turn: String = "black") {
    gomoku.applyState(decodePayload(statePayload(
        myColor: myColor,
        moves: [Mv(seq: 1, color: "black", x: 7, y: 7), Mv(seq: 2, color: "white", x: 8, y: 7)],
        turn: turn, stake: stake
    )))
}

private let diagnosticWords = ["서버", "상태", "동기화", "토큰", "세션", "RPC", "status", "_", "오류", "에러", "unknown", "실패", "stale"]

private let allStatuses: [GomokuRPCStatus] = [
    .ok, .unauthorized, .unsupportedClient, .invalid, .blackout, .notWorking, .targetNotWorking, .targetFocused,
    .targetOutdated, .busy, .targetBusy, .alreadyPending, .insufficient, .notFound, .notPending, .expired, .notActive,
    .timeout, .notYourTurn, .stale, .forbidden, .unknown
]

// MARK: - 1. 문구 표 · 디코드 · 본문 모양

@Test(.gomokuDefaultsCleanup)
func 오목_안내_문구표는_상태마다_사용자_어휘다() {
    #expect(GomokuNoticeText.challenge(.targetOutdated) == "상대가 앱을 업데이트해야 해요")
    #expect(GomokuNoticeText.challenge(.targetFocused) == "상대가 집중 모드라 신청할 수 없어요")
    #expect(GomokuNoticeText.challenge(.targetNotWorking) == "상대가 근무 중이 아니에요")
    #expect(GomokuNoticeText.challenge(.notWorking) == "근무 중일 때만 신청할 수 있어요")
    #expect(GomokuNoticeText.challenge(.targetBusy) == "상대가 다른 대국 중이에요")
    #expect(GomokuNoticeText.challenge(.insufficient, need: 10, have: 4) == "루비 6개 더 필요해요")
    #expect(GomokuNoticeText.challenge(.insufficient) == "루비가 모자라요")
    #expect(GomokuNoticeText.challenge(.unsupportedClient) == "앱을 업데이트해야 대결할 수 있어요")
    #expect(GomokuNoticeText.challenge(.unknown) == GomokuNoticeText.tryAgain)
    #expect(GomokuNoticeText.respond(accept: true, .ok) == nil)
    #expect(GomokuNoticeText.respond(accept: true, .insufficient, side: "challenger") == "상대의 루비가 모자라요")
    #expect(GomokuNoticeText.respond(accept: true, .insufficient, side: "me", need: 5, have: 2) == "루비 3개 더 필요해요")
    #expect(GomokuNoticeText.respond(accept: true, .expired) == "신청 시간이 지났어요")
    #expect(GomokuNoticeText.move(.forbidden, reason: "double-three") == "3-3 금수라 둘 수 없어요")
    #expect(GomokuNoticeText.move(.forbidden, reason: "forbidden-double-four") == "4-4 금수라 둘 수 없어요")
    #expect(GomokuNoticeText.move(.forbidden, reason: "overline") == "장목 금수라 둘 수 없어요")
    #expect(GomokuNoticeText.move(.forbidden, reason: "budget") == "판정할 수 없는 자리예요")
    #expect(GomokuNoticeText.move(.forbidden, reason: nil) == "둘 수 없는 자리예요")
    #expect(GomokuNoticeText.move(.timeout) == "시간이 지나 대국이 끝났어요")
    #expect(GomokuNoticeText.move(.stale) == nil)

    var texts: [String] = []
    for status in allStatuses {
        texts.append(GomokuNoticeText.challenge(status))
        texts.append(GomokuNoticeText.cancel(status))
        texts.append(contentsOf: [true, false].compactMap { GomokuNoticeText.respond(accept: $0, status) })
        texts.append(contentsOf: [GomokuNoticeText.move(status), GomokuNoticeText.resign(status)].compactMap { $0 })
    }
    texts.append(contentsOf: [GomokuForbiddenReason.doubleThree, .doubleFour, .overline, .budget].map(GomokuNoticeText.forbidden))
    texts.append(GomokuNoticeText.inviteTimedOut)
    for text in texts {
        #expect(!text.isEmpty)
        for word in diagnosticWords {
            #expect(!text.contains(word), "안내 문구에 진단 어휘 '\(word)': \(text)")
        }
    }
}

@Test(.gomokuDefaultsCleanup)
func 모르는_status_는_unknown_으로_접고_status_만_필수다() throws {
    let decoder = snakeDecoder()
    let action = try decoder.decode(GomokuActionResponse.self, from: Data(#"{"status":"brand_new_thing"}"#.utf8))
    #expect(action.status == .unknown)
    #expect(action.state == nil)
    let lobby = try decoder.decode(GomokuLobbyResponse.self, from: Data(#"{"status":"ok"}"#.utf8))
    #expect(lobby.status == .ok)
    #expect(lobby.users == nil && lobby.me == nil)
    let state = try decoder.decode(GomokuStateResponse.self, from: Data(#"{"status":"not_found"}"#.utf8))
    #expect(state.status == .notFound)
    #expect(state.state.match == nil)
    #expect(throws: (any Error).self) {
        try decoder.decode(GomokuInboxResponse.self, from: Data(#"{"incoming":[]}"#.utf8))
    }
    // 쓰기 RPC 의 상태는 `state` 키 안이 설계서 모양이고, 최상위 match 도 상태로 읽는다.
    let nested = try decoder.decode(GomokuActionResponse.self, from: Data(jsonText([
        "status": "timeout", "state": statePayload(matchStatus: "finished")
    ]).utf8))
    #expect(nested.status == .timeout)
    #expect(nested.state?.match?.status == "finished")
    let flat = try decoder.decode(GomokuActionResponse.self, from: Data(jsonText(statePayload()).utf8))
    #expect(flat.state?.match?.id == matchID)
    // 밀리초는 정수로 오든 소수로 오든 읽는다.
    let fractional = try decoder.decode(GomokuInboxResponse.self, from: Data(#"{"status":"ok","server_now_ms":1789000000000.5}"#.utf8))
    #expect(fractional.serverNowMs == 1_789_000_000_000.5)
}

@Test(.gomokuDefaultsCleanup)
func 오목_RPC_열은_p_protocol_2_와_p_snake_키를_싣는다() async throws {
    let host = "v0327-g-shape-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host) { _, _, _ in GomokuStubProtocol.Reply(body: #"{"status":"ok"}"#) }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    _ = try await service.gomokuLobby(accessToken: "t")
    _ = try await service.gomokuInbox(accessToken: "t")
    _ = try await service.gomokuChallenge(accessToken: "t", opponentID: rival, stake: 10)
    _ = try await service.gomokuCancel(accessToken: "t", matchID: matchID)
    _ = try await service.gomokuRespond(accessToken: "t", matchID: matchID, accept: true)
    _ = try await service.gomokuMove(accessToken: "t", matchID: matchID, expectedSeq: 4, x: 7, y: 8)
    _ = try await service.gomokuResign(accessToken: "t", matchID: matchID)
    _ = try await service.gomokuState(accessToken: "t", matchID: matchID, sinceSeq: 3, sinceChatSeq: 1)
    _ = try await service.gomokuChatSend(accessToken: "t", matchID: matchID, kind: .text, body: "안녕")
    _ = try await service.gomokuChatMute(accessToken: "t", matchID: matchID, muted: true)

    let expected: [String: Set<String>] = [
        "gomoku_lobby": ["p_protocol"],
        "gomoku_inbox": ["p_protocol"],
        "gomoku_challenge": ["p_protocol", "p_opponent", "p_stake"],
        "gomoku_cancel": ["p_protocol", "p_match_id"],
        "gomoku_respond": ["p_protocol", "p_match_id", "p_accept"],
        "gomoku_move": ["p_protocol", "p_match_id", "p_expected_seq", "p_x", "p_y"],
        "gomoku_resign": ["p_protocol", "p_match_id"],
        "gomoku_state": ["p_protocol", "p_match_id", "p_since_seq", "p_since_chat_seq"],
        "gomoku_chat_send": ["p_protocol", "p_match_id", "p_kind", "p_body"],
        "gomoku_chat_mute": ["p_protocol", "p_match_id", "p_muted"]
    ]
    let calls = GomokuStubProtocol.calls(host: host)
    #expect(Set(calls.map(\.rpc)) == Set(expected.keys))
    for call in calls {
        #expect(Set(call.json.keys) == expected[call.rpc], "\(call.rpc) 본문: \(call.body)")
        // 0.3.28 부터 2 다. 서버 `gomoku_protocol()` 은 1 그대로라 **기존 여덟도 그대로 통과한다**
        // (2 < 1 이 거짓) — 채팅 두 개만 자기 게이트 `gomoku_chat_protocol() = 2` 를 지난다.
        #expect(call.json["p_protocol"] as? Int == 2, "\(call.rpc) 의 p_protocol")
    }
    let state = try #require(calls.first { $0.rpc == "gomoku_state" }).json
    #expect(state["p_since_seq"] as? Int == 3 && state["p_since_chat_seq"] as? Int == 1)
    let move = try #require(calls.first { $0.rpc == "gomoku_move" }).json
    #expect(move["p_expected_seq"] as? Int == 4 && move["p_x"] as? Int == 7 && move["p_y"] as? Int == 8)
    let challenge = try #require(calls.first { $0.rpc == "gomoku_challenge" }).json
    #expect(challenge["p_opponent"] as? String == rival && challenge["p_stake"] as? Int == 10)
    let respond = try #require(calls.first { $0.rpc == "gomoku_respond" }).json
    #expect(respond["p_accept"] as? Bool == true)
}

// MARK: - 2. 신청 · 수락

@MainActor
@Test(.gomokuDefaultsCleanup)
func 신청_거절은_안내로_옮기고_성공은_서버시계로_보정한_만료를_든다() async {
    let (_, gomoku, host) = makeGomokuStore("challenge") { rpc, _, index in
        switch rpc {
        case "gomoku_challenge":
            if index == 0 { return reply(["status": "target_outdated"]) }
            let serverNow = nowMs() + 100_000          // 서버 시계가 기기보다 100초 빠르다
            return reply(["status": "ok", "match_id": matchID.uppercased(),
                          "invite_expires_ms": serverNow + 60_000, "server_now_ms": serverNow])
        case "gomoku_lobby":
            return reply(["status": "ok", "users": [userObject(rival, "라이벌")]])
        default:
            return nil
        }
    }
    gomoku.selectedStake = .ten

    await gomoku.challenge(userID: rival)
    #expect(gomoku.notice == "상대가 앱을 업데이트해야 해요")
    #expect(gomoku.outgoing == nil)
    #expect(gomoku.isBusy == false)
    // 칩이 틀렸다는 뜻이라 목록을 다시 읽었다.
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_lobby") == 1)

    await gomoku.challenge(userID: rival)
    #expect(gomoku.notice == "신청을 보냈어요")
    let outgoing = gomoku.outgoing
    #expect(outgoing?.id == matchID)
    #expect(outgoing?.stake == 10)
    #expect(outgoing?.peer.id == rival)
    #expect(outgoing?.peer.displayName == "라이벌")
    // 서버가 100초 빠른데도 기기 시계로는 **지금부터 60초** 뒤다.
    let remaining = (outgoing?.expiresAt.timeIntervalSinceNow) ?? -1
    #expect(abs(remaining - 60) < 3, "보정된 만료까지 \(remaining)초")
    let body = GomokuStubProtocol.calls(host: host, rpc: "gomoku_challenge").last?.json ?? [:]
    #expect(body["p_stake"] as? Int == 10)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 수락하면_루비를_서버값으로_반영하고_판을_연다() async {
    let (store, gomoku, _) = makeGomokuStore("accept") { rpc, body, _ in
        guard rpc == "gomoku_respond" else { return nil }
        let serverNow = nowMs()
        // 서버 잔액(11)은 일부러 '로컬 20 − 판돈 3 = 17' 과 다르다 — 같으면 로컬에서 빼는 구현도 초록이다(뮤턴트 S7).
        return reply([
            "status": "ok", "ruby_balance": 11,
            "state": statePayload(myColor: "white", turn: "black", deadlineMs: serverNow + 30_000,
                                  serverNowMs: serverNow, stake: 3)
        ])
    }
    store.rubyBalance = 20
    let tally = Tally()
    gomoku.presentWindow = { tally.count += 1 }
    let peer = GomokuUser(id: rival, displayName: "라이벌", avatarURL: nil, characterID: nil,
                          isWorking: true, isCapable: true, inMatch: false)
    gomoku.incoming = [GomokuInvite(id: matchID, peer: peer, stake: 3, expiresAt: Date().addingTimeInterval(50))]

    await gomoku.respond(inviteID: matchID, accept: true)

    #expect(gomoku.rubyBalance == 11, "낙관적 차감(20 − 3)이 아니라 서버값이어야 한다")
    #expect(store.rubyBalance == 11, "호스트의 루비 칩에도 서버값이 들어가야 한다")
    #expect(gomoku.phase == .playing)
    #expect(gomoku.match?.myColor == .white)
    #expect(gomoku.match?.turn == .black)
    #expect(gomoku.match?.stake == 3)
    #expect(gomoku.incoming.isEmpty)
    #expect(gomoku.bannerInvite == nil)
    #expect(tally.count == 1, "창이 안 보이면 수락한 판을 띄운다")
    #expect(gomoku.notice == nil)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 신청자_잔액_부족_수락은_판을_열지_않고_루비도_안_뺀다() async {
    let (store, gomoku, _) = makeGomokuStore("accept-short") { rpc, _, _ in
        rpc == "gomoku_respond"
            ? reply(["status": "insufficient", "side": "challenger", "need": 10, "have": 3, "ruby_balance": 25])
            : nil
    }
    store.rubyBalance = 25
    let peer = GomokuUser(id: rival, displayName: "라이벌", avatarURL: nil, characterID: nil,
                          isWorking: true, isCapable: true, inMatch: false)
    gomoku.incoming = [GomokuInvite(id: matchID, peer: peer, stake: 10, expiresAt: Date().addingTimeInterval(50))]

    await gomoku.respond(inviteID: matchID, accept: true)

    #expect(gomoku.notice == "상대의 루비가 모자라요")
    #expect(gomoku.match == nil)
    #expect(gomoku.phase == .lobby)
    #expect(store.rubyBalance == 25)
    #expect(gomoku.incoming.count == 1, "신청은 아직 살아 있다")
}

// MARK: - 3. 착수

@MainActor
@Test(.gomokuDefaultsCleanup)
func stale_이면_since_seq_로_다시_읽어_새_수를_얹는다() async {
    let (_, gomoku, host) = makeGomokuStore("stale") { rpc, body, _ in
        switch rpc {
        case "gomoku_move":
            return reply(["status": "stale"])
        case "gomoku_state":
            let since = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["p_since_seq"] as? Int ?? -1
            let all = [Mv(seq: 1, color: "black", x: 7, y: 7), Mv(seq: 2, color: "white", x: 8, y: 7),
                       Mv(seq: 3, color: "black", x: 6, y: 6), Mv(seq: 4, color: "white", x: 5, y: 5)]
            return reply(statePayload(moves: all.filter { $0.seq > since }, moveCount: 4, turn: "black"))
        default:
            return nil
        }
    }
    seedTwoMoveMatch(gomoku)
    #expect(gomoku.match?.moveCount == 2)

    await gomoku.place(GomokuPoint(x: 0, y: 0)!)

    let states = GomokuStubProtocol.calls(host: host, rpc: "gomoku_state")
    #expect(states.count == 1, "stale 뒤에는 반드시 다시 읽는다")
    #expect(states.first?.json["p_since_seq"] as? Int == 2, "들고 있는 판 뒤의 수만 받는다")
    #expect(GomokuStubProtocol.calls(host: host, rpc: "gomoku_move").first?.json["p_expected_seq"] as? Int == 2)
    let match = gomoku.match
    #expect(match?.moveCount == 4)
    #expect(match?.board[GomokuPoint(x: 6, y: 6)!] == .black)
    #expect(match?.board[GomokuPoint(x: 5, y: 5)!] == .white)
    #expect(match?.board[GomokuPoint(x: 7, y: 7)!] == .black)
    #expect(match?.lastMove == GomokuPoint(x: 5, y: 5))
    #expect(match?.board[GomokuPoint(x: 0, y: 0)!] == nil, "서버가 안 받은 수는 판에 없다(낙관적 착수 금지)")
    #expect(gomoku.notice == nil)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 기록에_구멍이_나면_처음부터_한_번_더_받는다() async {
    let (_, gomoku, host) = makeGomokuStore("gap") { rpc, body, _ in
        guard rpc == "gomoku_state" else { return nil }
        let since = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["p_since_seq"] as? Int ?? -1
        let all = [Mv(seq: 1, color: "black", x: 7, y: 7), Mv(seq: 2, color: "white", x: 8, y: 7),
                   Mv(seq: 3, color: "black", x: 6, y: 6), Mv(seq: 4, color: "white", x: 5, y: 5)]
        // since 2 를 물었는데 3이 빠진 채 온다(구멍) → 처음부터 다시 받아야 한다.
        let moves = since > 0 ? all.filter { $0.seq == 4 } : all
        return reply(statePayload(moves: moves, moveCount: 4, turn: "black"))
    }
    seedTwoMoveMatch(gomoku)

    await gomoku.refreshMatch()

    let sinces = GomokuStubProtocol.calls(host: host, rpc: "gomoku_state").map { $0.json["p_since_seq"] as? Int }
    #expect(sinces == [2, 0])
    #expect(gomoku.match?.moveCount == 4)
    #expect(gomoku.match?.board[GomokuPoint(x: 6, y: 6)!] == .black, "구멍 난 판을 그리면 이 돌이 빠진다")
    #expect(gomoku.match?.board.stoneCount == 4)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 시간_초과_응답은_결과로_옮기고_판돈만큼_잃었다고_말한다() async {
    let (store, gomoku, _) = makeGomokuStore("timeout") { rpc, _, _ in
        guard rpc == "gomoku_move" else { return nil }
        return reply([
            "status": "timeout",
            "state": statePayload(
                matchStatus: "finished",
                moves: [Mv(seq: 1, color: "black", x: 7, y: 7), Mv(seq: 2, color: "white", x: 8, y: 7)],
                turn: nil, result: "white_win", endReason: "timeout", stake: 10, ruby: 30)
        ])
    }
    seedTwoMoveMatch(gomoku, stake: 10)

    await gomoku.place(GomokuPoint(x: 0, y: 0)!)

    let match = gomoku.match
    #expect(match?.isFinished == true)
    #expect(match?.outcome == .lost)
    #expect(match?.endReason == .timeout)
    #expect(match?.rubyDelta == -10)
    #expect(match?.turn == nil)
    #expect(match?.deadline == nil)
    #expect(gomoku.remainingSeconds(now: Date()) == nil)
    #expect(gomoku.phase == .result)
    #expect(gomoku.notice == "시간이 지나 대국이 끝났어요")
    #expect(gomoku.rubyBalance == 30)
    #expect(store.rubyBalance == 30)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 흑_금수는_보내기_전에_막고_서버_금수는_사유로_말한다() async {
    let (_, gomoku, host) = makeGomokuStore("forbidden") { rpc, _, _ in
        rpc == "gomoku_move" ? reply(["status": "forbidden", "reason": "overline"]) : nil
    }
    // 가로 F8·G8, 세로 H6·H7 → H8 은 열린 3 두 개가 만나는 3-3.
    var moves: [Mv] = []
    var seq = 0
    for (color, x, y) in [("black", 5, 7), ("white", 0, 0), ("black", 6, 7), ("white", 14, 14),
                          ("black", 7, 5), ("white", 0, 14), ("black", 7, 6), ("white", 14, 0)] {
        seq += 1
        moves.append(Mv(seq: seq, color: color, x: x, y: y))
    }
    gomoku.applyState(decodePayload(statePayload(moves: moves, turn: "black")))
    let board = gomoku.match!.board
    #expect(GomokuRules.judge(board: board, point: GomokuPoint(x: 7, y: 7)!, color: .black) == .forbidden(.doubleThree))

    await gomoku.place(GomokuPoint(x: 7, y: 7)!)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_move") == 0, "금수 자리를 서버에 보냈다")
    #expect(gomoku.notice == "3-3 금수라 둘 수 없어요")

    // 앱 판정으로는 둘 수 있는 자리를 서버가 거절하면(예: 버전 차이) 서버의 사유를 말한다.
    await gomoku.place(GomokuPoint(x: 10, y: 10)!)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_move") == 1)
    #expect(gomoku.notice == "장목 금수라 둘 수 없어요")
    #expect(gomoku.match?.board[GomokuPoint(x: 10, y: 10)!] == nil)
    #expect(gomoku.isBusy == false)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 흑_자동_패스는_차례를_백에게_남기고_마지막_돌은_백의_수다() async {
    let (_, gomoku, _) = makeGomokuStore("pass") { rpc, _, _ in
        guard rpc == "gomoku_move" else { return nil }
        return reply([
            "status": "ok", "black_passed": true,
            "state": statePayload(
                myColor: "white",
                moves: [Mv(seq: 1, color: "black", x: 7, y: 7), Mv(seq: 2, color: "white", x: 8, y: 7),
                        Mv(seq: 3, color: "black", x: 6, y: 6), Mv(seq: 4, color: "white", x: 3, y: 3),
                        Mv(seq: 5, color: "black", x: nil, y: nil)],
                moveCount: 5, turn: "white")
        ])
    }
    gomoku.applyState(decodePayload(statePayload(
        myColor: "white",
        moves: [Mv(seq: 1, color: "black", x: 7, y: 7), Mv(seq: 2, color: "white", x: 8, y: 7),
                Mv(seq: 3, color: "black", x: 6, y: 6)],
        turn: "white")))
    #expect(gomoku.match?.blackPassed == false)

    await gomoku.place(GomokuPoint(x: 3, y: 3)!)

    #expect(gomoku.match?.blackPassed == true)
    #expect(gomoku.match?.turn == .white)
    #expect(gomoku.match?.moveCount == 5)
    #expect(gomoku.match?.lastMove == GomokuPoint(x: 3, y: 3))
    #expect(gomoku.match?.board.stoneCount == 4)
}

// MARK: - 4. 시계 보정

@MainActor
@Test(.gomokuDefaultsCleanup)
func 남은_시간은_서버_시계와의_차이를_지운_기기_시각으로_잰다() {
    let gomoku = GomokuStore()
    let local = Date(timeIntervalSince1970: 1_800_000_000)
    gomoku.clock = { local }
    let serverNow = (local.timeIntervalSince1970 + 250) * 1000       // 서버가 250초 빠르다
    gomoku.applyState(decodePayload(statePayload(
        turn: "black", deadlineMs: serverNow + 30_000, serverNowMs: serverNow)))

    #expect(abs((gomoku.remainingSeconds(now: local) ?? -1) - 30) < 0.001)
    #expect(abs((gomoku.remainingSeconds(now: local.addingTimeInterval(12)) ?? -1) - 18) < 0.001)
    #expect(gomoku.remainingSeconds(now: local.addingTimeInterval(40)) == 0, "0 아래로 내려가지 않는다")
    #expect(gomoku.match?.deadline == local.addingTimeInterval(30))
}

// MARK: - 5. 세대 가드 · 리셋

@MainActor
@Test(.gomokuDefaultsCleanup)
func 로그아웃_뒤에_도착한_앞_계정의_판은_버린다() async {
    let (store, gomoku, host) = makeGomokuStore("gen-logout") { rpc, _, _ in
        rpc == "gomoku_state" ? reply(statePayload(turn: "white"), delay: 0.4) : nil
    }
    let pending = Task { await gomoku.refreshMatch(id: matchID) }
    await gomokuWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 1 }
    store.clearPersistedSession()
    await pending.value

    #expect(gomoku.match == nil, "로그아웃 뒤 도착한 응답이 판을 세웠다")
    #expect(gomoku.phase == .lobby)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 리셋_뒤에_도착한_응답도_버린다() async {
    let (_, gomoku, host) = makeGomokuStore("gen-reset") { rpc, _, _ in
        switch rpc {
        case "gomoku_inbox":
            return reply(["status": "ok", "ruby_balance": 44, "incoming": [[
                "match_id": matchID, "challenger": userObject(rival, "라이벌"), "stake": 5,
                "invite_expires_ms": nowMs() + 60_000
            ]], "server_now_ms": nowMs()], delay: 0.4)
        default:
            return nil
        }
    }
    let pending = Task { await gomoku.loadInbox() }
    await gomokuWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == 1 }
    gomoku.reset()
    await pending.value

    #expect(gomoku.incoming.isEmpty)
    #expect(gomoku.rubyBalance == nil)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 로그아웃은_창을_닫고_오목_상태를_전부_비운다() async throws {
    let (store, gomoku, _) = makeGomokuStore("logout-reset")
    seedTwoMoveMatch(gomoku)
    let peer = GomokuUser(id: rival, displayName: "라이벌", avatarURL: nil, characterID: nil,
                          isWorking: true, isCapable: true, inMatch: false)
    gomoku.users = [peer]
    gomoku.record = GomokuRecord(wins: 3, losses: 1, draws: 0)
    gomoku.selectedStake = .ten
    gomoku.incoming = [GomokuInvite(id: "x1", peer: peer, stake: 5, expiresAt: Date().addingTimeInterval(40))]
    gomoku.outgoing = GomokuInvite(id: "x2", peer: peer, stake: 5, expiresAt: Date().addingTimeInterval(40))
    gomoku.notice = "상대 차례예요"
    gomoku.isRulesVisible = true
    gomoku.rubyBalance = 9
    gomoku.pollStepSeconds = 60
    gomoku.windowDidShow()
    #expect(gomoku.pollTask != nil)
    let tally = Tally()
    gomoku.dismissWindow = { tally.count += 1 }

    store.signOut()

    #expect(tally.count >= 1, "로그아웃했는데 대국 창을 닫지 않았다")
    #expect(gomoku.phase == .lobby)
    #expect(gomoku.match == nil)
    #expect(gomoku.users.isEmpty)
    #expect(gomoku.record == nil)
    #expect(gomoku.selectedStake == .three)
    #expect(gomoku.incoming.isEmpty)
    #expect(gomoku.outgoing == nil)
    #expect(gomoku.notice == nil)
    #expect(gomoku.isRulesVisible == false)
    #expect(gomoku.isWindowVisible == false)
    #expect(gomoku.rubyBalance == nil)
    #expect(gomoku.pollTask == nil)
    #expect(gomoku.seenInviteIDs.isEmpty)

    // 계정 전환(로그아웃 없이 다른 계정으로 확정)도 같은 리셋을 탄다.
    store.adoptWorkStateOwner(me)
    gomoku.rubyBalance = 5
    store.adoptWorkStateOwner("00000000-0000-0000-0000-0000000000c3")
    #expect(gomoku.rubyBalance == nil)

    // 배선은 소스로도 못 박는다(주석을 걷어낸 뒤).
    let code = gomokuCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("WorkTimerStore.swift")))
    #expect(gomokuBody(of: "func clearPersistedSession()", in: code)?.contains("gomoku.reset()") == true)
    #expect(gomokuBody(of: "func adoptWorkStateOwner(", in: code)?.contains("gomoku.reset()") == true)
    #expect(code.contains("gomoku.attach(host: self)"))
    let storeCode = gomokuCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("GomokuStore.swift")))
    let reset = gomokuBody(of: "func reset()", in: storeCode) ?? ""
    #expect(reset.contains("dismissWindow?()") && reset.contains("stopPolling()"))
}

// MARK: - 6. 폴링 게이트

@MainActor
@Test(.gomokuDefaultsCleanup)
func 폴링은_창이_보일_때만_돌고_차례_구독_여부로_주기가_갈린다() async {
    let (store, gomoku, host) = makeGomokuStore("poll-gate") { rpc, _, _ in
        switch rpc {
        case "gomoku_state":
            return reply(statePayload(myColor: "black",
                                      moves: [Mv(seq: 1, color: "black", x: 7, y: 7)], turn: "white"))
        case "gomoku_inbox":
            return reply(["status": "ok", "incoming": [], "outgoing": NSNull(), "active_match_id": matchID])
        case "gomoku_lobby":
            return reply(["status": "ok", "users": []])
        default:
            return nil
        }
    }
    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_800_000_000) }
    let clock = Clock()
    let t0 = clock.now
    gomoku.clock = { clock.now }
    gomoku.applyState(decodePayload(statePayload(
        myColor: "black", moves: [Mv(seq: 1, color: "black", x: 7, y: 7)], turn: "white")))
    #expect(gomoku.match?.turn == .white)

    // 창이 안 보이면 상대 차례여도 아무것도 안 나간다(무료 플랜 예산).
    await gomoku.pollTick(at: t0.addingTimeInterval(1_000))
    #expect(GomokuStubProtocol.calls(host: host).isEmpty)

    gomoku.isWindowVisible = true
    func tick(_ offset: TimeInterval) async {
        clock.now = t0.addingTimeInterval(offset)
        await gomoku.pollTick(at: clock.now)
    }
    func states() -> Int { GomokuStubProtocol.count(host: host, rpc: "gomoku_state") }

    // 미구독: 1.5초.
    await tick(0)
    #expect(states() == 1)
    await tick(1.0)
    #expect(states() == 1)
    await tick(1.6)
    #expect(states() == 2)
    // 구독 중: 3초.
    store.realtimeState = .subscribed(since: t0, lastHeardAt: t0)
    await tick(3.0)
    #expect(states() == 2)
    await tick(4.7)
    #expect(states() == 3)
    // 대국 중엔 로비 목록을 돌리지 않는다.
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_lobby") == 0)

    // 내 차례면(마감 전) 상태를 묻지 않는다.
    gomoku.applyState(decodePayload(statePayload(
        myColor: "black",
        moves: [Mv(seq: 1, color: "black", x: 7, y: 7), Mv(seq: 2, color: "white", x: 8, y: 8)],
        turn: "black")))
    await tick(20)
    #expect(states() == 3)

    // 보낸 신청이 있으면 5초마다 인박스(판이 없는 로비).
    let peer = GomokuUser(id: rival, displayName: "라이벌", avatarURL: nil, characterID: nil,
                          isWorking: true, isCapable: true, inMatch: false)
    gomoku.match = nil
    gomoku.phase = .lobby
    GomokuStubProtocol.register(host: host) { rpc, _, _ in
        switch rpc {
        case "gomoku_inbox":
            return reply(["status": "ok", "incoming": [], "server_now_ms": nowMs(), "outgoing": [
                "match_id": "o1", "opponent": userObject(rival, "라이벌"), "stake": 5,
                "invite_expires_ms": nowMs() + 3_600_000
            ]])
        case "gomoku_lobby":
            return reply(["status": "ok", "users": []])
        default:
            return nil
        }
    }
    gomoku.outgoing = GomokuInvite(id: "o1", peer: peer, stake: 5, expiresAt: Date().addingTimeInterval(3_600))
    func inboxes() -> Int { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") }
    func lobbies() -> Int { GomokuStubProtocol.count(host: host, rpc: "gomoku_lobby") }
    await tick(100)
    #expect(inboxes() == 1)
    #expect(lobbies() == 1, "로비를 보고 있으면 목록도 돈다")
    await tick(103)
    #expect(inboxes() == 1)
    await tick(105.5)
    #expect(inboxes() == 2)
    #expect(lobbies() == 1)
    await tick(131)
    #expect(lobbies() == 2)

    // 창을 내리면 다시 조용하다.
    gomoku.windowDidHide()
    let quiet = GomokuStubProtocol.calls(host: host).count
    await tick(10_000)
    #expect(GomokuStubProtocol.calls(host: host).count == quiet)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실제_폴링_루프는_창이_보이는_동안만_살아_있다() async {
    let (_, gomoku, host) = makeGomokuStore("poll-loop") { rpc, _, _ in
        rpc == "gomoku_state"
            ? reply(statePayload(myColor: "black", moves: [Mv(seq: 1, color: "black", x: 7, y: 7)], turn: "white"))
            : nil
    }
    gomoku.applyState(decodePayload(statePayload(
        myColor: "black", moves: [Mv(seq: 1, color: "black", x: 7, y: 7)], turn: "white")))
    gomoku.pollStepSeconds = 0.02
    #expect(gomoku.pollTask == nil)

    gomoku.windowDidShow()
    #expect(gomoku.isWindowVisible)
    #expect(gomoku.pollTask != nil)
    await gomokuWait(20) { GomokuStubProtocol.count(host: host, rpc: "gomoku_state") >= 1 }
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") >= 1, "보이는 창에서 상대 차례를 묻지 않았다")

    gomoku.windowDidHide()
    #expect(gomoku.pollTask == nil)
    #expect(gomoku.match != nil, "창을 내려도 대국은 계속된다")
    // 창을 내린 순간 이미 나가던 조회 한 건은 끝까지 간다(스텁이 요청을 세는 시점은 전송 시점이라, 부하 중에는
    // 150ms 안에 안 셀 수 있다 — 2026-09-16 전체 스위트 부하에서 이 자리가 빨갰다). 그 조회가 끝난 뒤를 기준으로 잰다.
    await gomokuWait(20) { gomoku.stateInFlightID == nil }
    try? await Task.sleep(for: .milliseconds(150))
    let settled = GomokuStubProtocol.count(host: host, rpc: "gomoku_state")
    try? await Task.sleep(for: .milliseconds(1_800))       // 미구독 주기(1.5초)를 넘겨 기다린다
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == settled, "창이 안 보이는데 폴링했다")
}

// MARK: - 7. 받은 신청 · 계기

@MainActor
@Test(.gomokuDefaultsCleanup)
func 새_받은_신청은_처음_본_id_에_한_번만_알린다() async {
    let (_, gomoku, _) = makeGomokuStore("arrival") { rpc, _, index in
        guard rpc == "gomoku_inbox" else { return nil }
        let serverNow = nowMs()
        var incoming: [[String: Any]] = [[
            "match_id": "a1", "challenger": userObject(rival, "라이벌"), "stake": 5,
            "invite_expires_ms": serverNow + 40_000
        ]]
        if index >= 2 {
            incoming.append(["match_id": "b2", "challenger": userObject("00000000-0000-0000-0000-0000000000c3", "셋째"),
                             "stake": 10, "invite_expires_ms": serverNow + 55_000])
        }
        return reply(["status": "ok", "incoming": incoming, "outgoing": NSNull(), "server_now_ms": serverNow])
    }
    let tally = Tally()
    gomoku.onInviteArrived = { tally.ids.append($0.id) }

    await gomoku.loadInbox()
    await gomoku.loadInbox()
    #expect(tally.ids == ["a1"])
    await gomoku.loadInbox()
    #expect(tally.ids == ["a1", "b2"])
    #expect(gomoku.incoming.count == 2)
    #expect(gomoku.bannerInvite?.id == "a1", "가장 오래된(먼저 만료되는) 신청이 대표다")
    #expect(gomoku.incoming.first { $0.id == "b2" }?.peer.displayName == "셋째")

    // 만료 시각이 지나면 스토어가 걷는다(배너는 시계를 읽지 않는다).
    gomoku.pruneExpiredInvites(now: Date().addingTimeInterval(45))
    #expect(gomoku.incoming.map(\.id) == ["b2"])
    #expect(gomoku.bannerInvite?.id == "b2")

    // 로그아웃·계정 전환 뒤에는 다시 처음 보는 신청이다.
    gomoku.reset()
    await gomoku.loadInbox()
    #expect(tally.ids == ["a1", "b2", "a1", "b2"])
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 인박스가_진행_중_대국을_말하면_판을_열고_보낸_신청을_걷는다() async {
    let (_, gomoku, host) = makeGomokuStore("inbox-active") { rpc, _, _ in
        switch rpc {
        case "gomoku_inbox":
            return reply(["status": "ok", "incoming": [], "outgoing": NSNull(), "active_match_id": matchID.uppercased()])
        case "gomoku_state":
            return reply(statePayload(myColor: "white", turn: "black"))
        default:
            return nil
        }
    }
    let peer = GomokuUser(id: rival, displayName: "라이벌", avatarURL: nil, characterID: nil,
                          isWorking: true, isCapable: true, inMatch: false)
    gomoku.outgoing = GomokuInvite(id: matchID, peer: peer, stake: 5, expiresAt: Date().addingTimeInterval(30))

    await gomoku.loadInbox()

    #expect(GomokuStubProtocol.calls(host: host, rpc: "gomoku_state").first?.json["p_since_seq"] as? Int == 0)
    #expect(gomoku.phase == .playing)
    #expect(gomoku.match?.id == matchID)
    #expect(gomoku.outgoing == nil)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 팝오버_열림_인박스는_60초_스로틀이다() async throws {
    let (_, gomoku, host) = makeGomokuStore("menu-throttle") { rpc, _, _ in
        rpc == "gomoku_inbox" ? reply(["status": "ok", "incoming": []]) : nil
    }
    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_800_000_000) }
    let clock = Clock()
    gomoku.clock = { clock.now }

    gomoku.menuDidOpen()
    await gomokuWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == 1 }
    clock.now = clock.now.addingTimeInterval(30)
    gomoku.menuDidOpen()
    try? await Task.sleep(for: .milliseconds(200))
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == 1)
    clock.now = clock.now.addingTimeInterval(31)
    gomoku.menuDidOpen()
    await gomokuWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == 2 }
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == 2)

    // 근무 시작은 스로틀 없이 한 번 본다.
    gomoku.workDidStart()
    await gomokuWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == 3 }
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == 3)

    // 세션이 없으면 계기가 와도 요청을 내지 않는다.
    let bare = GomokuStore()
    bare.menuDidOpen()
    bare.workDidStart()
    bare.handleSignal()
    #expect(bare.syncTask == nil)

    // 호출 자리는 소스로 못 박는다 — 계기가 호출되지 않으면 위 동작은 코드에만 있고 앱엔 없다.
    let code = gomokuCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("WorkTimerStore.swift")))
    #expect(gomokuBody(of: "func setMenuPresented(", in: code)?.contains("gomoku.menuDidOpen()") == true)
    #expect(gomokuBody(of: "func start(now: Date = Date())", in: code)?.contains("gomoku.workDidStart()") == true)
}

// MARK: - 소스 도구

/// 공백을 한 칸으로 접는다(줄바꿈·들여쓰기와 무관하게 조각을 찾기 위해).
func gomokuCollapsed(_ code: String) -> String {
    code.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// 선언 조각 뒤 첫 `{` 부터 짝이 맞는 `}` 까지.
func gomokuBody(of signature: String, in code: String) -> String? {
    guard let start = code.range(of: signature),
          let open = code[start.upperBound...].firstIndex(of: "{") else { return nil }
    var depth = 0
    var index = open
    while index < code.endIndex {
        if code[index] == "{" { depth += 1 }
        if code[index] == "}" {
            depth -= 1
            if depth == 0 { return String(code[open...index]) }
        }
        index = code.index(after: index)
    }
    return nil
}
