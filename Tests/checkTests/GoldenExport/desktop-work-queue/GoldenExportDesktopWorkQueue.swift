// 원본: Sources/check/WorkTimerStoreSync.swift 1717-1968(retryPendingSync · enqueueSync · runPendingSync · resolveStartBlockedByOpenSession ·
//       performPendingOperation) · WorkTimerStore.swift 76(scavengeThrottleSeconds) · 1819(lastScavengeAt) @ a90d8623
import CheckGoldenSupport
import Foundation
import Testing
@testable import check
@testable import CheckCore

// W2-g1 데스크톱 근무 큐 시나리오 골든(xplat-w1/briefs/work.md §5 — V0345StartConflictStubTests · V0236SyncTests 를 본뜬다).
// 맥 `WorkTimerStore` 의 오프라인 큐 드레인(⑪ 순서 보존·실패 자리 멈춤)과 23505 해소기(⑫ 1 · 2(5분 스로틀 경계) · 3a · 3b · 3c · 3d)를
// 스크립트 응답 위에서 **실제로 돌려** 녹음한다. Kotlin `DesktopWorkQueueSwiftGoldenTest` 가 같은 입력·같은 응답으로
// `DesktopWorkQueue` 를 돌려 요청열·남은 항목·도장·실패 여부·실패 문구를 대조한다(기대값을 손으로 옮기지 않는다).
//
// 드레인 끝의 `refreshTeamStatus()`(Kotlin 은 host.onDrained)는 스크립트가 다 쓰인 **뒤**의 읽기 요청이다 — 503 으로 돌려보내고
// 골든에는 `drainedRefresh`(그런 요청이 있었는가)만 남긴다. 스크립트 뒤에 쓰기·내 겹침 조회가 나오면 스크립트가 모자란 것이라 빨강.
// UserDefaults 는 절대경로 격리 스위트(CheckTestScratch)만 쓰고 지운다 · 네트워크는 이 파일의 URLProtocol 이 다 받는다.

final class DesktopWorkQueueScriptProtocol: URLProtocol {
    struct Recorded {
        let method: String
        let path: String
        let query: [(String, String)]
        let body: GoldenJSON
        let afterScript: Bool
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var scripts: [String: [(Int, String)]] = [:]
    private nonisolated(unsafe) static var recorded: [String: [Recorded]] = [:]
    static let afterScriptBody = #"{"message":"golden: after script"}"#

    static func install(host: String, script: [(Int, String)]) {
        lock.lock(); defer { lock.unlock() }
        scripts[host] = script
        recorded[host] = []
    }

    static func take(host: String) -> [Recorded] {
        lock.lock(); defer { lock.unlock() }
        let out = recorded[host] ?? []
        scripts[host] = nil
        recorded[host] = nil
        return out
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let host = url.host ?? ""
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body = Self.body(Self.bodyData(request))
        Self.lock.lock()
        let script = Self.scripts[host] ?? []
        let index = Self.recorded[host, default: []].count
        let after = index >= script.count
        let (status, text) = after ? (503, Self.afterScriptBody) : script[index]
        Self.recorded[host, default: []].append(Recorded(
            method: request.httpMethod ?? "GET", path: url.path, query: items.map { ($0.name, $0.value ?? "") }, body: body, afterScript: after))
        Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func bodyData(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    /// 본문 → 정규 JSON(정수는 int, 그 밖의 수는 {"$num"} — Kotlin GoldenRecorder.canonical 과 같은 꼴) + 벽시계 키 표식.
    static func body(_ data: Data?) -> GoldenJSON {
        guard let data, !data.isEmpty else { return .null }
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return .object(["$bytes": .string(data.base64EncodedString())])
        }
        return maskWall(convert(parsed))
    }

    private static func convert(_ v: Any) -> GoldenJSON {
        if v is NSNull { return .null }
        if let n = v as? NSNumber, !(v is String) {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            let d = n.doubleValue
            if d.rounded() == d, abs(d) <= 9_007_199_254_740_991 { return .int(Int(d)) }
            return .object(["$num": .string(n.stringValue)])
        }
        if let s = v as? String { return .string(s) }
        if let a = v as? [Any] { return .array(a.map(convert)) }
        if let o = v as? [String: Any] { return .object(o.mapValues(convert)) }
        return .string("\(v)")
    }

    static let wallClockKeys: Set<String> = ["last_seen_at", "updated_at", "auto_closed_at"]

    private static func maskWall(_ v: GoldenJSON) -> GoldenJSON {
        switch v {
        case .object(let o):
            var out: [String: GoldenJSON] = [:]
            for (k, x) in o {
                if wallClockKeys.contains(k), case .string = x { out[k] = .string("<WALL>") } else { out[k] = maskWall(x) }
            }
            return .object(out)
        case .array(let a): return .array(a.map(maskWall))
        default: return v
        }
    }
}

@Suite("GoldenExport W2-g1 데스크톱 근무 큐 — 시나리오 골든")
struct GoldenExportDesktopWorkQueue {
    static let user = "aa000000-0000-4000-8000-0000000000a1"
    static let team = "ee000000-0000-4000-8000-0000000000e5"
    static let sid = "ab000000-0000-4000-8000-0000000000f6"
    static let other = "cd000000-0000-4000-8000-0000000000c7"
    /// 2026-09-17T05:05:00Z — Kotlin GOLDEN_NOW 와 같다.
    static let now = Date(timeIntervalSince1970: 1_789_621_500)
    /// 04:05:00Z · 05:04:00Z
    static let mineStart = now.addingTimeInterval(-3600)
    static let stopEnd = now.addingTimeInterval(-60)

    struct Item {
        let id: String
        let stopDuration: Int?
        let sessionID: String
        let startedAt: Date?
        let endedAt: Date?
        let owner: String?

        var swift: PendingWorkItem {
            PendingWorkItem(id: UUID(uuidString: id)!, operation: stopDuration.map { .stop(durationSeconds: $0) } ?? .start,
                            sessionID: sessionID, sessionStartedAt: startedAt, endedAt: endedAt, ownerUserID: owner)
        }

        var golden: GoldenJSON {
            func at(_ d: Date?) -> GoldenJSON { d.map { .int(Int($0.timeIntervalSince1970)) } ?? .null }
            return .object([
                "id": .string(id), "op": .string(stopDuration == nil ? "start" : "stop"),
                "durationSeconds": stopDuration.map { .int($0) } ?? .null, "sessionID": .string(sessionID),
                "sessionStartedAtSince1970": at(startedAt), "endedAtSince1970": at(endedAt), "ownerUserID": owner.map { .string($0) } ?? .null,
            ])
        }
    }

    struct Case {
        let id: String
        let items: [Item]
        /// 근무 중이면 그 currentSessionID(startedAt = mineStart). nil = 근무 중 아님.
        var live: String? = nil
        /// 마지막 스캐빈저 발사가 지금보다 몇 초 앞인가. nil = 이 실행에서 아직 안 쏨(.distantPast).
        var lastScavengeAgo: Int? = nil
        /// 드레인 전 도장(confirmedServerSessionID). 찍지 않은 것과 nil 을 찍은 것을 가르려고 둔다.
        var confirmedBefore: String? = nil
        let script: [(Int, String)]
    }

    static func start(_ id: String = sid, item: String = "0A000000-0000-4000-8000-000000000001") -> Item {
        Item(id: item, stopDuration: nil, sessionID: id, startedAt: mineStart, endedAt: nil, owner: user)
    }

    static func stop(_ id: String = sid, item: String = "0B000000-0000-4000-8000-000000000002") -> Item {
        Item(id: item, stopDuration: 3540, sessionID: id, startedAt: mineStart, endedAt: stopEnd, owner: user)
    }

    static func row(_ id: String, _ started: String, _ ended: String? = nil) -> String {
        #"{"id":"\#(id)","user_id":"\#(user)","started_at":"\#(started)","ended_at":\#(ended.map { "\"\($0)\"" } ?? "null")}"#
    }

    static let conflict = (409, #"{"code":"23505","details":null,"hint":null,"message":"duplicate key value violates unique constraint \"work_sessions_one_open_per_user\""}"#)
    static let ok = (200, "{}")
    static let otherOpen = (200, "[\(row(other, "2026-09-17T04:35:00Z"))]")
    static let mineOpen = (200, "[\(row(sid, "2026-09-17T04:05:00Z"))]")

    static var cases: [Case] {
        [
            // ⑪ 순서 보존: 오프라인으로 쌓인 시작→종료가 로그인 뒤 그 순서로 나간다. 서버 행(대문자 id)은 정규화해 도장.
            Case(id: "drain/start-then-stop", items: [start(), stop()],
                 script: [(200, "[\(row(sid.uppercased(), "2026-09-17T04:05:00Z"))]"), ok,
                          (200, "[\(row(sid, "2026-09-17T04:05:00Z", "2026-09-17T05:04:00Z"))]"), ok]),
            // ⑪ 실패 자리 멈춤: 첫 항목 500 → 뒤 항목을 보내지 않고 둘 다 남는다.
            // 도장 규칙 (a): 0행(이미 있다)은 찍지 않는다 — 앞 도장이 그대로 남는다.
            Case(id: "drain/start-zero-rows-keeps-stamp", items: [start()], confirmedBefore: other, script: [(200, "[]"), ok]),
            Case(id: "drain/failure-stops-in-place", items: [start(), stop()], script: [(500, #"{"message":"boom"}"#)]),
            // ⑫(1) 막은 행이 내 것(ack 유실 뒤 재발사) → 끝.
            Case(id: "resolver/1-blocker-is-mine", items: [start()], script: [conflict, (200, "[\(row(sid.uppercased(), "2026-09-17T04:05:00Z"))]")]),
            // ⑫(1) 열린 행이 안 보인다 → 한 번만 다시 연다.
            Case(id: "resolver/1-blocker-invisible-retry-once", items: [start()], script: [conflict, (200, "[]"), mineOpen, ok]),
            // ⑫(2) 스캐빈저(처음은 언제나) → 재시작 성공.
            Case(id: "resolver/2-scavenge-then-retry", items: [start()], script: [conflict, otherOpen, (200, "1"), mineOpen, ok]),
            // ⑫(2) 5분 스로틀 경계: 4분 59초 → 쏘지 않고 (3-d) 되던짐 · 5분 정각 → 다시 쏜다.
            Case(id: "resolver/2-throttle-4m59s", items: [start()], lastScavengeAgo: 299, script: [conflict, otherOpen]),
            Case(id: "resolver/2-throttle-5m00s", items: [start()], lastScavengeAgo: 300, script: [conflict, otherOpen, (200, "1"), mineOpen, ok]),
            // ⑫(3-a) 같은 세션 Stop 이 줄에 있다 → 시작 항목은 끝, 종료의 0행 폴백이 정본 닫힌 행.
            Case(id: "resolver/3a-stop-queued", items: [start(), stop()], lastScavengeAgo: 0,
                 script: [conflict, otherOpen, (200, "[]"), ok, otherOpen]),
            // ⑫(3-b) 지금 그 세션을 산다 → [내 시작, 덮기 시작) 만 닫힌 행. ★ 끝 시각을 고르지 않는다(C#24).
            Case(id: "resolver/3b-coverage-earliest-row", items: [start()], live: sid, lastScavengeAgo: 0,
                 script: [conflict, (200, "[\(row(other, "2026-09-17T04:35:00Z")),\(row("x", "2026-09-17T04:20:00Z", "2026-09-17T04:30:00Z"))]"), ok]),
            Case(id: "resolver/3b-coverage-open-row", items: [start()], live: sid, lastScavengeAgo: 0, confirmedBefore: sid, script: [conflict, otherOpen, ok]),
            // ⑫(3-b) 1초 미만 구간은 쓰지 않는다.
            Case(id: "resolver/3b-sub-second", items: [start()], live: sid, lastScavengeAgo: 0,
                 script: [conflict, (200, "[\(row(other, "2026-09-17T04:05:00.500Z"))]")]),
            // ⑫(3-c) 낡은 초안(지금 다른 세션을 산다) → 버린다.
            Case(id: "resolver/3c-stale-draft", items: [start()], live: other, lastScavengeAgo: 0, script: [conflict, otherOpen]),
            // ⑫(3-d) 그 밖 → 되던진다(순서 그대로).
            Case(id: "resolver/3d-rethrow", items: [start(), stop(other)], lastScavengeAgo: 0, script: [conflict, otherOpen]),
        ]
    }

    @MainActor
    static func run(_ c: Case, index: Int) async -> GoldenJSON {
        let host = "desktop-work-queue-\(index).invalid"
        DesktopWorkQueueScriptProtocol.install(host: host, script: c.script)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DesktopWorkQueueScriptProtocol.self]
        let now = Self.now
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "golden-anon-key",
                                          session: URLSession(configuration: configuration), clock: { now })
        let suite = CheckTestScratch.uniqueSuitePath("desktop-work-queue-\(index)")
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "golden-anon-key"], defaults: defaults)
        store.clock = { now }
        store.session = SupabaseSession(accessToken: "golden-access-token", refreshToken: nil, userID: user)
        store.currentTeamID = team
        if let live = c.live {
            store.startedAt = mineStart
            store.currentSessionID = live
        }
        if let ago = c.lastScavengeAgo { store.lastScavengeAt = now.addingTimeInterval(-Double(ago)) }
        store.confirmedServerSessionID = c.confirmedBefore
        store.pendingItems = c.items.map(\.swift)

        await store.retryPendingSync()

        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
        store.pokePollTask?.cancel()
        let recorded = DesktopWorkQueueScriptProtocol.take(host: host)
        let scripted = recorded.filter { !$0.afterScript }
        let after = recorded.filter(\.afterScript)
        #expect(scripted.count == c.script.count, "\(c.id): 스크립트 응답이 남았다(요청 \(scripted.count) / 응답 \(c.script.count))")
        let strayWrites = after.filter { $0.method != "GET" || $0.query.contains { $0.0 == "or" } }
        #expect(strayWrites.isEmpty, "\(c.id): 스크립트 뒤에 큐 요청이 나왔다 — 스크립트를 늘려라: \(strayWrites.map { "\($0.method) \($0.path)" })")

        let failed = store.snapshot.pendingSync
        return .object([
            "id": .string(c.id),
            "input": .object([
                "items": .array(c.items.map(\.golden)),
                "liveSessionID": c.live.map { .string($0) } ?? .null,
                "lastScavengeAgoSeconds": c.lastScavengeAgo.map { .int($0) } ?? .null,
                "confirmedBeforeSessionID": c.confirmedBefore.map { .string($0) } ?? .null,
                "script": .array(c.script.map { .object(["status": .int($0.0), "body": .string($0.1)]) }),
            ]),
            "requests": .array(scripted.map { r in
                .object([
                    "method": .string(r.method), "path": .string(r.path),
                    "query": .array(r.query.map { .array([.string($0.0), .string($0.1)]) }), "body": r.body,
                ])
            }),
            "remaining": .array(store.pendingItems.map { .string($0.id.uuidString) }),
            "confirmedServerSessionID": store.confirmedServerSessionID.map { .string($0) } ?? .null,
            "failed": .bool(failed),
            "syncMessage": failed ? .string(store.syncMessage) : .null,
            "drainedRefresh": .bool(!after.isEmpty),
        ])
    }

    @Test("데스크톱 근무 큐 시나리오 골든")
    @MainActor
    func desktopWorkQueue() async throws {
        var out: [GoldenJSON] = []
        for (i, c) in Self.cases.enumerated() {
            out.append(await Self.run(c, index: i))
        }
        let ids = Self.cases.map(\.id)
        #expect(Set(ids).count == ids.count, "case id 중복")
        #expect(WorkTimerStore.scavengeThrottleSeconds == 300)
        goldenEmit(GoldenFile(
            golden: "desktop-work-queue/scenarios",
            equivalence: .bit,
            swiftSources: ["Sources/check/WorkTimerStoreSync.swift", "Sources/check/WorkTimerStore.swift", "Sources/CheckCore/SupabaseWorkServiceMacOnly.swift"],
            spec: [
                "values": .object([
                    "userID": .string(Self.user), "teamID": .string(Self.team), "sessionID": .string(Self.sid), "otherSessionID": .string(Self.other),
                    "nowSince1970": .int(Int(Self.now.timeIntervalSince1970)), "scavengeThrottleSeconds": .int(Int(WorkTimerStore.scavengeThrottleSeconds)),
                ]),
                "wallClockKeys": .array(DesktopWorkQueueScriptProtocol.wallClockKeys.sorted().map { .string($0) }),
                "run": .string("pendingItems = input.items(오프라인으로 쌓인 줄) → retryPendingSync. 시계는 nowSince1970 고정. liveSessionID 가 있으면 startedAt = 첫 항목 시작 · currentSessionID = 그 값(Kotlin WorkQueueHost.liveSessionId). lastScavengeAgoSeconds 가 있으면 마지막 스캐빈저 = now − 그 값(Kotlin scavenge.tryAcquire 로 미리 씀). confirmedBeforeSessionID = 드레인 전 도장."),
                "requests": .string("스크립트 응답을 쓴 요청만(method · path · 디코드한 query 쌍 · 정규 JSON 본문, wallClockKeys 값은 \"<WALL>\"). 스크립트 뒤의 요청(드레인 끝 refreshTeamStatus 읽기)은 503 을 받고 drainedRefresh 로만 남는다."),
                "outcome": .string("remaining = 남은 항목 id 순서 · confirmedServerSessionID = 끝의 도장 · failed = 드레인이 실패로 멈췄는가(pendingSync) · syncMessage = 그때 문구"),
            ],
            cases: out
        ))
    }
}
