import Foundation
import Testing
@testable import check

// v0.3.30 — 착용 캐릭터를 **서버 기준**으로(폰과 공존).
//
// 재현하는 결함(R8): 0.3.29 의 맥은 실행·로그인 때마다 로컬 선택을 `set_character` 로 밀었다. 폰에서 캐릭터를
// 바꾸면 맥이 다음에 켜질 때 **말없이 되돌린다**. 서버값을 읽는 길도 없었다.
//
// 여기서 고정하는 것: 실행·로그인·팝오버는 **읽기만** 한다(옮겨 가기 1회 예외) · 서버값으로 로컬이 바뀌고 방송이
// 한 번 운다 · 조회가 실패하면 로컬도 서버도 안 건드린다 · 팝오버는 60초 스로틀 · 로그아웃 뒤 늦은 응답과
// 사용자 고르기와 겹친 낡은 응답은 버린다 · 가지지 않은/모르는 캐릭터는 아잉.
// 스텁이 못 잡는 것(실서버의 행 가시성·컬럼 권한)은 통합자의 두 기기 확인 몫이다.

// MARK: - 스텁

private final class CharacterSyncStubProtocol: URLProtocol {
    struct Reply: Sendable {
        var status: Int = 200
        var body: String = "[]"
        var delay: TimeInterval = 0
        /// true 면 응답 대신 연결 실패(오프라인)를 낸다.
        var fails = false
        /// 있으면 테스트가 `open()` 할 때까지 응답을 붙든다. 고정 지연(초)은 병렬 스위트 부하에서 메인 액터가
        /// 늦게 돌면 "응답이 먼저 도착"으로 순서가 뒤집혀 흔들린다 — 순서를 테스트가 쥔다.
        var gate: CSGate?
    }

    struct Call: Sendable {
        let method: String
        let path: String
        let query: String
        let body: String

        var isCharacterGET: Bool {
            method == "GET" && path == "/rest/v1/profiles" && query.contains("select=character")
        }
        var isSetCharacter: Bool { path == "/rest/v1/rpc/set_character" }
    }

    typealias Handler = @Sendable (_ call: Call) -> Reply

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var callsByHost: [String: [Call]] = [:]

    static func register(host: String, handler: @escaping Handler) {
        lock.withLock {
            handlers[host] = handler
            callsByHost[host] = []
        }
    }

    static func calls(host: String) -> [Call] {
        lock.withLock { callsByHost[host] ?? [] }
    }

    static func characterGETs(host: String) -> [Call] { calls(host: host).filter(\.isCharacterGET) }
    static func setCharacters(host: String) -> [Call] { calls(host: host).filter(\.isSetCharacter) }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CharacterSyncStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let call = Call(
            method: request.httpMethod ?? "GET",
            path: request.url?.path ?? "",
            query: request.url?.query?.removingPercentEncoding ?? "",
            body: Self.bodyText(from: request)
        )
        let handler: Handler? = Self.lock.withLock {
            Self.callsByHost[host, default: []].append(call)
            return Self.handlers[host]
        }
        let reply = handler?(call) ?? Reply()
        let delivery = Delivery(proto: self, reply: reply)
        if let gate = reply.gate {
            DispatchQueue.global().async {
                // 상한을 둔다 — 테스트가 열기 전에 실패로 끝나도 스레드가 프로세스 끝까지 묶이지 않게.
                _ = gate.group.wait(timeout: .now() + 30)
                delivery.run()
            }
        } else if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { delivery.run() }
        } else {
            delivery.run()
        }
    }

    override func stopLoading() {}

    private final class Delivery: @unchecked Sendable {
        let proto: CharacterSyncStubProtocol
        let reply: Reply

        init(proto: CharacterSyncStubProtocol, reply: Reply) {
            self.proto = proto
            self.reply = reply
        }

        func run() {
            if reply.fails {
                proto.client?.urlProtocol(proto, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let response = HTTPURLResponse(
                url: proto.request.url!, statusCode: reply.status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: Data(reply.body.utf8))
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

/// 응답 붙들기. 한 번 열면 붙든 것과 이후 것이 전부 지나간다.
private final class CSGate: @unchecked Sendable {
    let group = DispatchGroup()
    private let lock = NSLock()
    private var opened = false

    init() { group.enter() }

    func open() {
        lock.withLock {
            guard !opened else { return }
            opened = true
            group.leave()
        }
    }
}

/// 서버의 `profiles.character` 한 칸을 흉내낸다. `set_character` 가 ok 면 값이 바뀐다(폰의 변경은 테스트가 직접 쓴다).
private final class CSServer: @unchecked Sendable {
    private let lock = NSLock()
    private var _character: String?
    /// 착용값 GET 에 줄 응답을 통째로 바꾼다(실패·지연 재현). nil 이면 정상 1행.
    private var _characterReply: CharacterSyncStubProtocol.Reply?
    private var _setCharacterReply: CharacterSyncStubProtocol.Reply?

    init(character: String?) { _character = character }

    var character: String? {
        get { lock.withLock { _character } }
        set { lock.withLock { _character = newValue } }
    }
    var characterReply: CharacterSyncStubProtocol.Reply? {
        get { lock.withLock { _characterReply } }
        set { lock.withLock { _characterReply = newValue } }
    }
    var setCharacterReply: CharacterSyncStubProtocol.Reply? {
        get { lock.withLock { _setCharacterReply } }
        set { lock.withLock { _setCharacterReply = newValue } }
    }

    func handle(_ call: CharacterSyncStubProtocol.Call) -> CharacterSyncStubProtocol.Reply {
        if call.path == "/auth/v1/token" {
            return .init(body: #"{"access_token":"refreshed-token","refresh_token":"next-refresh","user":{"id":"\#(csUserA)"}}"#)
        }
        if call.isCharacterGET {
            if let reply = characterReply { return reply }
            let value = character.map { "\"\($0)\"" } ?? "null"
            return .init(body: #"[{"character":\#(value)}]"#)
        }
        if call.isSetCharacter {
            if let reply = setCharacterReply { return reply }
            let object = (try? JSONSerialization.jsonObject(with: Data(call.body.utf8))) as? [String: Any]
            let id = object?["p_id"] as? String
            character = id
            let value = id.map { "\"\($0)\"" } ?? "null"
            return .init(body: #"{"status":"ok","character":\#(value)}"#)
        }
        return .init()
    }
}

// MARK: - 픽스처

private let csUserA = "00000000-0000-0000-0000-0000000000c1"
private let csUserB = "00000000-0000-0000-0000-0000000000c2"
private let aing = CharacterCatalog.builtInAingID

/// 번들 캐릭터 둘(아잉 아님). 기준선이 아잉과 달라야 "바뀌었다"를 물을 수 있다.
@MainActor
private func csTwoCharacters() throws -> (String, String) {
    let ids = CheckCharacter3DScene.catalog.allIDs.filter { $0 != aing }
    try #require(ids.count >= 2, "번들에 아잉 말고 캐릭터가 둘 이상 없다 — 이 스위트는 공허하다")
    return (ids[0], ids[1])
}

private func csDefaults() -> UserDefaults {
    let suiteName = "check-v0330-character-sync-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func csInertTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    let tag = UUID().uuidString
    return TokenUsageStore(
        defaults: csDefaults(),
        homeDirectory: tmp.appendingPathComponent("check-v0330-cs-home-\(tag)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("check-v0330-cs-cache-\(tag).json", isDirectory: false)
    )
}

private final class CSClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

/// 로그인된 스토어. **착용 선택·방송 통로·도장이 전부 격리**다 — 전역을 흔들면 오버레이를 재는 병렬 스위트가 빨개진다.
@MainActor
private func csStore(
    host: String,
    server: CSServer,
    defaults: UserDefaults = csDefaults(),
    characterDefaults: UserDefaults = csDefaults(),
    signedIn: Bool = true,
    local: String? = nil,
    migrated: Bool = true
) -> WorkTimerStore {
    CharacterSyncStubProtocol.register(host: host) { server.handle($0) }
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!,
                                      anonKey: "anon-test-key",
                                      session: CharacterSyncStubProtocol.session())
    let store = WorkTimerStore(service: service,
                               environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: defaults,
                               workspaceNotifications: nil,
                               tokenUsage: csInertTokenStore())
    if signedIn {
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: csUserA)
    }
    store.characterDefaults = characterDefaults
    store.characterSync.broadcast = CharacterSelectionBroadcast()
    if let local { characterDefaults.set(local, forKey: CharacterSelection.defaultsKey) }
    if migrated { defaults.set(true, forKey: CharacterSyncDecision.migrationDefaultsKey) }
    return store
}

@MainActor
private func csSelected(_ store: WorkTimerStore) -> String {
    CharacterSelection(defaults: store.characterDefaults, catalog: CheckCharacter3DScene.catalog).selectedID
}

@MainActor
private func csCancelLoops(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.pokePollTask?.cancel()
}

@MainActor
private func csWait(timeout: TimeInterval = 30, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// 지금 스레드를 **동기로** 막는다(메인 액터 테스트에서 줄 선 작업이 못 돌게). async 문맥에선 Thread.sleep 이
/// 막혀 있어 동기 함수로 한 번 감싼다.
private func csBlockCurrentThread(seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}

/// "안 일어났다"를 물을 때 — 뒤늦게 뜨는 Task 가 요청을 낼 틈을 준다.
private func csSettle() async {
    try? await Task.sleep(for: .milliseconds(200))
}

private func csUnique(_ name: String) -> String {
    "v0330-cs-\(name)-\(UUID().uuidString.lowercased().prefix(8))"
}

// MARK: - ① 서비스

@Suite("v0.3.30 캐릭터 동기화 — 서비스")
struct V0330CharacterSyncServiceTests {
    @MainActor
    @Test("착용값 GET — profiles?select=character&id=eq.<uid>, 값·null·0행·옛 서버")
    func fetchEquippedCharacterShapes() async throws {
        let host = csUnique("service")
        let server = CSServer(character: "fox")
        CharacterSyncStubProtocol.register(host: host) { server.handle($0) }
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!,
                                          anonKey: "anon-test-key",
                                          session: CharacterSyncStubProtocol.session())

        let value = try await service.fetchEquippedCharacter(accessToken: "t", userID: csUserA)
        #expect(value == "fox")
        let call = try #require(CharacterSyncStubProtocol.calls(host: host).last)
        #expect(call.method == "GET")
        #expect(call.path == "/rest/v1/profiles")
        #expect(call.query.contains("select=character"), Comment(rawValue: call.query))
        #expect(call.query.contains("id=eq.\(csUserA)"), Comment(rawValue: call.query))
        // 다른 컬럼을 끼우지 않는다 — 컬럼 없는 서버에서 42703 이 그 컬럼들까지 같이 죽인다.
        #expect(!call.query.contains(","), Comment(rawValue: "select 에 다른 컬럼이 끼었다: \(call.query)"))

        server.character = nil
        #expect(try await service.fetchEquippedCharacter(accessToken: "t", userID: csUserA) == nil)

        // 0행은 "기본"이 아니라 이상 상태다 — 로컬을 근거 없이 지우지 않게 throw.
        server.characterReply = .init(body: "[]")
        await #expect(throws: CharacterSyncFetchError.noProfileRow) {
            _ = try await service.fetchEquippedCharacter(accessToken: "t", userID: csUserA)
        }

        // 컬럼이 없는 옛 서버(42703 → 400)는 throw — 호출부가 "로컬 그대로"로 접는다.
        server.characterReply = .init(status: 400, body: #"{"code":"42703","message":"column profiles.character does not exist"}"#)
        await #expect(throws: (any Error).self) {
            _ = try await service.fetchEquippedCharacter(accessToken: "t", userID: csUserA)
        }
    }
}

// MARK: - ② 순수 판정

@Suite("v0.3.30 캐릭터 동기화 — 판정")
struct V0330CharacterSyncDecisionTests {
    private static func decide(_ server: String?, local: String, migrated: Bool,
                               known: Set<String> = ["aing", "fox", "ghost"],
                               unlocked: Set<String> = ["aing", "fox", "ghost"]) -> CharacterSyncDecision {
        CharacterSyncDecision.decide(serverID: server, localID: local, migrated: migrated,
                                     isKnown: { known.contains($0) }, isUnlocked: { unlocked.contains($0) })
    }

    @Test("판정 표")
    func decisionTable() {
        // 서버를 따른다.
        #expect(Self.decide("fox", local: "aing", migrated: true) == .adopt("fox"))
        #expect(Self.decide("fox", local: "ghost", migrated: false) == .adopt("fox"))
        #expect(Self.decide("fox", local: "fox", migrated: true) == .keep)
        // 서버 null = 기본. 도장이 있으면 로컬 비기본도 아잉으로.
        #expect(Self.decide(nil, local: "fox", migrated: true) == .adopt("aing"))
        #expect(Self.decide(nil, local: "aing", migrated: true) == .keep)
        // 옮겨 가기: 도장 없음 + 서버 null + 로컬 비기본일 때만.
        #expect(Self.decide(nil, local: "fox", migrated: false) == .migrate("fox"))
        #expect(Self.decide(nil, local: "aing", migrated: false) == .keep)
        #expect(Self.decide("  ", local: "fox", migrated: false) == .migrate("fox"), "공백은 null 과 같은 '기본'이다")
        #expect(Self.decide("", local: "fox", migrated: true) == .adopt("aing"))
        // 모르는 캐릭터(폰이 먼저 받은 새 캐릭터)·가지지 않은 캐릭터는 아잉.
        #expect(Self.decide("brandnew", local: "fox", migrated: true) == .adopt("aing"))
        #expect(Self.decide("brandnew", local: "aing", migrated: true) == .keep)
        #expect(Self.decide("ghost", local: "fox", migrated: true, unlocked: ["aing", "fox"]) == .adopt("aing"))
        #expect(Self.decide("ghost", local: "ghost", migrated: true, unlocked: ["aing"]) == .adopt("aing"))
        // 서버에 값이 있으면 도장과 무관하게 옮겨 가기가 아니다.
        #expect(Self.decide("ghost", local: "fox", migrated: false, unlocked: ["aing", "fox"]) == .adopt("aing"))
    }

    @Test("옮겨 가기 도장은 서버가 대답했을 때만")
    func migrationSettledTable() {
        for status in ["ok", "not_owned", "unknown_character", "no_profile"] {
            #expect(CharacterSyncDecision.migrationSettled(byStatus: status), Comment(rawValue: status))
        }
        for status in [nil, "unauthorized", "weird"] as [String?] {
            #expect(!CharacterSyncDecision.migrationSettled(byStatus: status), Comment(rawValue: String(describing: status)))
        }
    }
}

// MARK: - ③ 스토어

@Suite("v0.3.30 캐릭터 동기화 — 스토어")
struct V0330CharacterSyncStoreTests {

    // MARK: 실행 · 로그인은 읽는다

    @MainActor
    @Test("실행(저장 세션 활성화) — set_character 0회, 서버값으로 로컬이 바뀌고 방송 1회")
    func launchReadsInsteadOfPushing() async throws {
        let (x, _) = try csTwoCharacters()
        let host = csUnique("launch")
        let server = CSServer(character: x)
        let defaults = csDefaults()
        defaults.set("old-access-token", forKey: WorkTimerStore.accessTokenKey)
        defaults.set("old-refresh-token", forKey: WorkTimerStore.refreshTokenKey)
        defaults.set(csUserA, forKey: WorkTimerStore.userIDKey)
        let store = csStore(host: host, server: server, defaults: defaults, signedIn: false, local: aing)
        defer { csCancelLoops(store) }
        #expect(store.shouldActivateOnLaunch, "준비 실패 — 저장 세션이 복원되지 않았다")
        #expect(csSelected(store) == aing)

        await store.activateStoredSessionOnLaunch()?.value
        await store.characterSync.lastTask?.value
        await csSettle()

        #expect(CharacterSyncStubProtocol.characterGETs(host: host).count == 1, "실행 때 착용값을 안 읽었다")
        #expect(CharacterSyncStubProtocol.setCharacters(host: host).isEmpty,
                "실행 때 set_character 를 불렀다 — 폰에서 바꾼 캐릭터를 되돌린다(R8)")
        #expect(csSelected(store) == x, "서버값을 안 따랐다")
        #expect(store.characterSync.broadcast.revision == 1, "방송이 \(store.characterSync.broadcast.revision)회")
        #expect(store.characterSync.broadcast.selectedID == x)
    }

    @MainActor
    @Test("로그인 마무리 — set_character 0회, 서버값으로 로컬이 바뀐다")
    func signInReadsInsteadOfPushing() async throws {
        let (x, y) = try csTwoCharacters()
        let host = csUnique("signin")
        let server = CSServer(character: y)
        let store = csStore(host: host, server: server, signedIn: false, local: x)
        defer { csCancelLoops(store) }

        await store.completeSignIn(SupabaseSession(accessToken: "signed-in", refreshToken: "r", userID: csUserA),
                                   email: "a@example.com")
        await store.characterSync.lastTask?.value
        await csSettle()

        #expect(CharacterSyncStubProtocol.characterGETs(host: host).count == 1)
        #expect(CharacterSyncStubProtocol.setCharacters(host: host).isEmpty, "로그인 때 set_character 를 불렀다")
        #expect(csSelected(store) == y)
        #expect(store.characterSync.broadcast.revision == 1)
    }

    @MainActor
    @Test("서버값이 로컬과 같으면 방송하지 않는다 — 기준선이 실제로 다르다")
    func sameValueDoesNotBroadcast() async throws {
        let (x, _) = try csTwoCharacters()
        let host = csUnique("same")
        let store = csStore(host: host, server: CSServer(character: x), local: x)
        await store.syncEquippedCharacterFromServer(reason: .launch)?.value
        #expect(csSelected(store) == x)
        #expect(store.characterSync.broadcast.revision == 0)
        #expect(CharacterSyncStubProtocol.setCharacters(host: host).isEmpty)
    }

    // MARK: 실패는 아무것도 안 바꾼다

    @MainActor
    @Test("조회 실패(5xx·오프라인·옛 서버 400·행 없음) — 로컬 유지, set_character 0회, 도장 없음",
          arguments: ["500", "offline", "old-server", "no-row"])
    func fetchFailureKeepsLocalAndDoesNotPush(kind: String) async throws {
        let (x, _) = try csTwoCharacters()
        let host = csUnique("fail-\(kind)")
        let server = CSServer(character: nil)
        switch kind {
        case "500": server.characterReply = .init(status: 500, body: #"{"message":"boom"}"#)
        case "offline": server.characterReply = .init(fails: true)
        case "old-server":
            server.characterReply = .init(status: 400, body: #"{"code":"42703","message":"column profiles.character does not exist"}"#)
        default: server.characterReply = .init(body: "[]")
        }
        // 도장 없음 + 로컬 비기본: 실패를 "서버 null"로 잘못 읽으면 옮겨 가기 밀기가 나가는 조합이다.
        let store = csStore(host: host, server: server, local: x, migrated: false)

        await store.syncEquippedCharacterFromServer(reason: .launch)?.value
        await csSettle()

        #expect(CharacterSyncStubProtocol.characterGETs(host: host).count == 1, "준비 실패 — 조회가 안 나갔다")
        #expect(csSelected(store) == x, "조회 실패인데 로컬을 바꿨다")
        #expect(CharacterSyncStubProtocol.setCharacters(host: host).isEmpty, "조회 실패인데 밀었다")
        #expect(store.characterSync.broadcast.revision == 0)
        #expect(!store.defaults.bool(forKey: CharacterSyncDecision.migrationDefaultsKey),
                "조회 실패인데 옮겨 가기 도장을 찍었다 — 다음 실행이 기존 선택을 지운다")
        #expect(store.session != nil, "조회 실패가 세션을 지웠다")
    }

    // MARK: 옮겨 가기

    @MainActor
    @Test("옮겨 가기 — 서버 null · 로컬 비기본 · 도장 없음이면 한 번 밀고, 두 번째 실행은 0회")
    func migrationPushesExactlyOnce() async throws {
        let (x, _) = try csTwoCharacters()
        let host = csUnique("migrate")
        let server = CSServer(character: nil)
        let defaults = csDefaults()
        let characterDefaults = csDefaults()
        let first = csStore(host: host, server: server, defaults: defaults,
                            characterDefaults: characterDefaults, local: x, migrated: false)

        await first.syncEquippedCharacterFromServer(reason: .launch)?.value
        let pushes = CharacterSyncStubProtocol.setCharacters(host: host)
        #expect(pushes.count == 1, "옮겨 가기 밀기가 \(pushes.count)회")
        #expect(pushes.first?.body.contains(x) == true, Comment(rawValue: pushes.first?.body ?? "-"))
        #expect(csSelected(first) == x, "옮겨 가기가 로컬을 바꿨다")
        #expect(server.character == x)
        #expect(defaults.bool(forKey: CharacterSyncDecision.migrationDefaultsKey), "도장이 안 찍혔다")

        // 폰에서 기본으로 되돌렸다(서버 null). 같은 맥의 다음 실행은 **밀지 않고** 따라간다.
        server.character = nil
        let second = csStore(host: host, server: server, defaults: defaults,
                             characterDefaults: characterDefaults, migrated: false)
        CharacterSyncStubProtocol.register(host: host) { server.handle($0) }   // 기록을 비운다
        #expect(defaults.bool(forKey: CharacterSyncDecision.migrationDefaultsKey))
        await second.syncEquippedCharacterFromServer(reason: .launch)?.value
        await csSettle()
        #expect(CharacterSyncStubProtocol.setCharacters(host: host).isEmpty,
                "두 번째 실행이 또 밀었다 — 폰의 '기본으로 되돌리기'를 되돌린다")
        #expect(csSelected(second) == aing)
    }

    @MainActor
    @Test("옮겨 가기 밀기가 네트워크로 실패하면 도장을 안 찍어 다음에 다시 민다")
    func failedMigrationRetriesNextTime() async throws {
        let (x, _) = try csTwoCharacters()
        let host = csUnique("migrate-retry")
        let server = CSServer(character: nil)
        server.setCharacterReply = .init(fails: true)
        let store = csStore(host: host, server: server, local: x, migrated: false)

        await store.syncEquippedCharacterFromServer(reason: .launch)?.value
        #expect(CharacterSyncStubProtocol.setCharacters(host: host).count == 1)
        #expect(!store.defaults.bool(forKey: CharacterSyncDecision.migrationDefaultsKey),
                "밀기가 실패했는데 도장을 찍었다 — 다음 실행이 서버 null 을 '기본'으로 읽어 선택을 지운다")
        #expect(csSelected(store) == x)

        server.setCharacterReply = nil
        await store.syncEquippedCharacterFromServer(reason: .signIn)?.value
        #expect(CharacterSyncStubProtocol.setCharacters(host: host).count == 2)
        #expect(store.defaults.bool(forKey: CharacterSyncDecision.migrationDefaultsKey))
        #expect(server.character == x)
    }

    // MARK: 사용자 고르기

    @MainActor
    @Test("이 맥에서 고르면 즉시 민다")
    func userChoicePushesImmediately() async throws {
        let (_, y) = try csTwoCharacters()
        let host = csUnique("choose")
        let server = CSServer(character: aing)
        let store = csStore(host: host, server: server, local: aing)
        let selection = CharacterSelection(defaults: store.characterDefaults, catalog: CheckCharacter3DScene.catalog)

        #expect(CheckCharacterPicker.choose(y, selection: selection, broadcast: store.characterSync.broadcast))
        store.pushSelectedCharacter(announcesFailure: true)

        #expect(await csWait { CharacterSyncStubProtocol.setCharacters(host: host).count == 1 },
                "고른 캐릭터를 안 밀었다 — 남에게는 옛 캐릭터로 보인다")
        #expect(CharacterSyncStubProtocol.setCharacters(host: host).first?.body.contains(y) == true)
        #expect(await csWait { server.character == y })
    }

    @MainActor
    @Test("not_owned 되돌리기는 그대로 — 로컬 아잉 + 안내")
    func notOwnedRevertStillWorks() async throws {
        let (x, _) = try csTwoCharacters()
        let host = csUnique("not-owned")
        let server = CSServer(character: nil)
        server.setCharacterReply = .init(body: #"{"status":"not_owned","id":"\#(x)"}"#)
        let store = csStore(host: host, server: server, local: x)

        await store.pushCharacter(x, announcesFailure: true)
        #expect(csSelected(store) == aing)
        #expect(store.syncMessage == WorkTimerStore.notOwnedRevertNotice)
        #expect(store.characterSync.broadcast.revision == 1)
    }

    // MARK: 팝오버 — 폰의 변경이 맥에 반영되는 길

    @MainActor
    @Test("팝오버 열기 — 60초 스로틀, 지나면 다시 읽어 폰의 변경을 따른다")
    func popoverThrottlesAndFollowsPhone() async throws {
        let (x, y) = try csTwoCharacters()
        let host = csUnique("popover")
        let server = CSServer(character: x)
        let store = csStore(host: host, server: server, local: aing)
        defer { csCancelLoops(store) }
        let clock = CSClock()
        store.clock = { clock.now }

        store.setMenuPresented(true)
        #expect(await csWait { CharacterSyncStubProtocol.characterGETs(host: host).count == 1 },
                "팝오버를 열어도 착용값을 안 읽는다 — setMenuPresented 배선이 없다")
        await store.characterSync.lastTask?.value
        #expect(csSelected(store) == x)

        // 30초 뒤 다시 열기 — 읽지 않는다.
        store.setMenuPresented(false)
        clock.now = clock.now.addingTimeInterval(30)
        server.character = y   // 그 사이 폰에서 바꿨다
        let seedBefore = store.characterSync.tokenSeed
        store.setMenuPresented(true)
        // 발사 여부는 setMenuPresented 안에서 **동기로** 정해진다 — 시간 창(settle)에 기대지 않고 그 자리에서 잰다.
        #expect(store.characterSync.tokenSeed == seedBefore, "60초 안에 또 읽었다 — 스로틀이 없다")
        await csSettle()
        #expect(CharacterSyncStubProtocol.characterGETs(host: host).count == 1, "60초 안에 또 읽었다 — 스로틀이 없다")
        #expect(csSelected(store) == x)

        // 60초가 지나면 읽고 따라간다.
        store.setMenuPresented(false)
        clock.now = clock.now.addingTimeInterval(31)
        store.setMenuPresented(true)
        #expect(await csWait { CharacterSyncStubProtocol.characterGETs(host: host).count == 2 })
        await store.characterSync.lastTask?.value
        #expect(csSelected(store) == y, "폰에서 바꾼 캐릭터를 안 따랐다")
        #expect(store.characterSync.broadcast.revision == 2)
        #expect(CharacterSyncStubProtocol.setCharacters(host: host).isEmpty)
    }

    @MainActor
    @Test("팝오버 — 조회가 떠 있으면 스로틀이 지나도 겹쳐 쏘지 않는다")
    func popoverDoesNotOverlap() async throws {
        let (x, _) = try csTwoCharacters()
        let host = csUnique("overlap")
        let server = CSServer(character: x)
        let gate = CSGate()
        defer { gate.open() }
        server.characterReply = .init(body: #"[{"character":"\#(x)"}]"#, gate: gate)
        let store = csStore(host: host, server: server, local: aing)
        let clock = CSClock()
        store.clock = { clock.now }

        store.refreshEquippedCharacterIfStale()
        #expect(await csWait { CharacterSyncStubProtocol.characterGETs(host: host).count == 1 })
        clock.now = clock.now.addingTimeInterval(120)
        let seedBefore = store.characterSync.tokenSeed
        store.refreshEquippedCharacterIfStale()
        #expect(store.characterSync.tokenSeed == seedBefore, "떠 있는 조회 위에 또 쐈다")
        await csSettle()
        #expect(CharacterSyncStubProtocol.characterGETs(host: host).count == 1, "떠 있는 조회 위에 또 쐈다")
        gate.open()
        await store.characterSync.lastTask?.value
        #expect(csSelected(store) == x)
    }

    @MainActor
    @Test("실행·로그인은 스로틀과 무관하게 읽는다")
    func launchIgnoresPopoverThrottle() async throws {
        let (x, _) = try csTwoCharacters()
        let host = csUnique("no-throttle")
        let store = csStore(host: host, server: CSServer(character: x), local: aing)
        let clock = CSClock()
        store.clock = { clock.now }
        await store.syncEquippedCharacterFromServer(reason: .popover)?.value
        await store.syncEquippedCharacterFromServer(reason: .signIn)?.value
        #expect(CharacterSyncStubProtocol.characterGETs(host: host).count == 2)
        // 그 직후의 팝오버는 스로틀에 걸린다(실행 직후 여닫이에서 두 번 읽지 않는다).
        #expect(store.syncEquippedCharacterFromServer(reason: .popover) == nil)
    }

    // MARK: 늦은 응답

    @MainActor
    @Test("로그아웃 뒤 늦게 온 조회는 다음 계정의 선택을 바꾸지 않는다")
    func lateResponseAfterSignOutIsDropped() async throws {
        let (x, y) = try csTwoCharacters()
        let host = csUnique("generation")
        let server = CSServer(character: x)
        let gate = CSGate()
        defer { gate.open() }
        server.characterReply = .init(body: #"[{"character":"\#(x)"}]"#, gate: gate)
        let store = csStore(host: host, server: server, local: y)
        defer { csCancelLoops(store) }

        let task = store.syncEquippedCharacterFromServer(reason: .launch)
        #expect(await csWait { CharacterSyncStubProtocol.characterGETs(host: host).count == 1 })
        // A 로그아웃 → B 로그인(같은 맥, 같은 착용 선택 도메인). 그 뒤에야 A 의 응답이 도착한다.
        store.clearPersistedSession()
        store.session = SupabaseSession(accessToken: "b-token", refreshToken: nil, userID: csUserB)
        gate.open()
        await task?.value

        #expect(csSelected(store) == y, "앞 계정의 늦은 응답이 다음 계정의 선택을 바꿨다")
        #expect(store.characterSync.broadcast.revision == 0)
        #expect(store.characterSync.fetchingToken == nil)
    }

    @MainActor
    @Test("조회가 떠 있는 동안 이 맥에서 고르면 그 응답은 버린다")
    func userChoiceDuringFetchWins() async throws {
        let (x, y) = try csTwoCharacters()
        let host = csUnique("write-race")
        let server = CSServer(character: x)
        // 조회는 **고르기 전의** 서버값(x)을 읽은 채 늦게 도착한다.
        let gate = CSGate()
        defer { gate.open() }
        server.characterReply = .init(body: #"[{"character":"\#(x)"}]"#, gate: gate)
        let store = csStore(host: host, server: server, local: aing)
        let selection = CharacterSelection(defaults: store.characterDefaults, catalog: CheckCharacter3DScene.catalog)

        let task = store.syncEquippedCharacterFromServer(reason: .popover)
        #expect(await csWait { CharacterSyncStubProtocol.characterGETs(host: host).count == 1 })
        #expect(CheckCharacterPicker.choose(y, selection: selection, broadcast: store.characterSync.broadcast))
        store.pushSelectedCharacter(announcesFailure: true)
        #expect(await csWait { CharacterSyncStubProtocol.setCharacters(host: host).count == 1 })
        gate.open()
        await task?.value
        await csSettle()

        #expect(csSelected(store) == y, "방금 고른 캐릭터가 낡은 서버값으로 튀었다")
    }

    /// 위 테스트의 더 좁은 창: 응답이 **이미 도착해 메인 액터 차례를 기다리는 중**에 고른다. 선택기는
    /// `choose` → `onChosen`(= pushSelectedCharacter) 를 한 동기 구간에서 부르고, 밀기 Task 의 첫 줄은 그 뒤에
    /// 돈다 — 그 사이에 줄 서 있던 조회 응답이 먼저 돌면 밀기 시작 표시(beginPush)를 못 본다.
    /// 그래서 pushSelectedCharacter 가 Task 를 띄우기 **전에** 쓰기를 적는다.
    ///
    /// 메인 스레드를 잠깐 막아(Thread.sleep) 응답의 이어달리기가 먼저 줄 서게 만든다. 부하가 커서 0.5초 안에
    /// 줄을 못 서면 이 테스트는 **공허하게 초록**이 될 수는 있어도 거짓 빨강은 되지 않는다(가드가 있으면 어느
    /// 순서든 y 다).
    @MainActor
    @Test("응답이 이미 줄 서 있는 순간에 골라도 그 응답은 버린다")
    func userChoiceBeatsQueuedResponse() async throws {
        let (x, y) = try csTwoCharacters()
        let host = csUnique("queued-race")
        let server = CSServer(character: x)
        let gate = CSGate()
        defer { gate.open() }
        server.characterReply = .init(body: #"[{"character":"\#(x)"}]"#, gate: gate)
        server.setCharacterReply = .init(body: #"{"status":"ok","character":"\#(y)"}"#)
        let store = csStore(host: host, server: server, local: aing)
        let selection = CharacterSelection(defaults: store.characterDefaults, catalog: CheckCharacter3DScene.catalog)

        let task = store.syncEquippedCharacterFromServer(reason: .popover)
        #expect(await csWait { CharacterSyncStubProtocol.characterGETs(host: host).count == 1 })
        gate.open()
        csBlockCurrentThread(seconds: 0.5)
        #expect(CheckCharacterPicker.choose(y, selection: selection, broadcast: store.characterSync.broadcast))
        store.pushSelectedCharacter(announcesFailure: true)
        await task?.value
        #expect(await csWait { CharacterSyncStubProtocol.setCharacters(host: host).count == 1 })

        #expect(csSelected(store) == y, "줄 서 있던 낡은 응답이 방금 고른 캐릭터를 덮었다")
    }

    // MARK: 소유 · 모르는 캐릭터

    @MainActor
    @Test("가지지 않은 캐릭터가 서버에 있으면 기본 — 가졌으면 그대로(기준선)")
    func unownedServerValueFoldsToDefault() async throws {
        let (x, _) = try csTwoCharacters()
        for owned in [false, true] {
            let host = csUnique("owned-\(owned)")
            let store = csStore(host: host, server: CSServer(character: x), local: x)
            store.shopLoaded = true
            store.ownedCharacterIDs = owned ? [aing, x] : [aing]
            await store.syncEquippedCharacterFromServer(reason: .launch)?.value
            #expect(csSelected(store) == (owned ? x : aing), Comment(rawValue: "owned=\(owned)"))
            #expect(store.characterSync.broadcast.revision == (owned ? 0 : 1), Comment(rawValue: "owned=\(owned)"))
            #expect(CharacterSyncStubProtocol.setCharacters(host: host).isEmpty, Comment(rawValue: "owned=\(owned)"))
        }
    }

    @MainActor
    @Test("이 빌드가 모르는 캐릭터(폰이 먼저 받은 새 캐릭터)면 기본")
    func unknownServerValueFoldsToDefault() async throws {
        let (x, _) = try csTwoCharacters()
        let host = csUnique("unknown")
        let store = csStore(host: host, server: CSServer(character: "zz-not-in-this-build"), local: x)
        await store.syncEquippedCharacterFromServer(reason: .launch)?.value
        #expect(csSelected(store) == aing)
        #expect(store.characterSync.broadcast.revision == 1)
        #expect(CharacterSyncStubProtocol.setCharacters(host: host).isEmpty)
    }

    @MainActor
    @Test("비로그인이면 아무것도 안 한다")
    func signedOutDoesNothing() async throws {
        let host = csUnique("signed-out")
        let store = csStore(host: host, server: CSServer(character: "fox"), signedIn: false, local: aing)
        #expect(store.syncEquippedCharacterFromServer(reason: .launch) == nil)
        store.refreshEquippedCharacterIfStale()
        await csSettle()
        #expect(CharacterSyncStubProtocol.calls(host: host).isEmpty)
    }
}
