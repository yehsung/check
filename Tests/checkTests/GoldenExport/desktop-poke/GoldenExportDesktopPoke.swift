// 원본: 없음(W2-g2 골든 생성기 — Sources/check/WorkTimerStorePoke.swift 1-64·668-684·749-807 · Sources/CheckCore/SupabaseWorkServiceMacOnly.swift 808-835·864-904 를 잰다)
import CheckGoldenSupport
import Foundation
import Testing
@testable import check
@testable import CheckCore

// W2-g2 데스크톱 찌르기 골든. Kotlin 은 feature/desktop/…/poke(DesktopPokeRules · poke/net).
//
//   · desktop-poke/fresh        take_pokes 행(JSON 원문) → freshReceivedPokes(P9: message 빼기 · 3600 · 120 넘은 ultra 강등)
//                               · freshReceivedMessages(P13: message 만 · 5분 · 본문 정규화 · 시각순)
//   · desktop-poke/send-notice  ultraSentNotice(P3) · 안내 상수 · 박자 상수(P11 · P13) · 발사 응답 → PokeSendOutcome
//   · desktop-poke/requests     poke_user · ultra_poke_user · take_pokes 의 경로 · 본문 바이트, PGRST202 → `{}` 한 번(P12, 캐시 없음)
// 시각은 1970 기준 정수 초(행의 created_epoch 가 정수다). 네트워크·UserDefaults·창을 쓰지 않는다(요청은 아래 URLProtocol 이 받는다).

@Suite("GoldenExport desktop-poke — 찌르기 신선도 · 안내 · 요청 본문", .serialized)
struct GoldenExportDesktopPoke {
    static func s(_ value: String?) -> GoldenJSON { value.map(GoldenJSON.string) ?? .null }
    static func n(_ value: Int?) -> GoldenJSON { value.map(GoldenJSON.int) ?? .null }

    static func whole(_ value: Double) -> GoldenJSON {
        #expect(Double(Int(value)) == value, "정수 초가 아니다: \(value)")
        return .int(Int(value))
    }

    static let now = 1_790_000_000

    /// (case id, take_pokes 응답 원문). created_epoch 는 now 기준 나이로 적는다.
    static func rowSets() -> [(String, String)] {
        func row(_ id: String, age: Int, kind: String?, body: String? = nil, character: String? = nil, avatar: String? = nil,
                 from: String = "peer-1", name: String = "보낸이") -> String {
            var parts = ["\"id\":\"\(id)\"", "\"from_user\":\"\(from)\"", "\"from_display_name\":\"\(name)\"",
                         "\"created_epoch\":\(now - age)"]
            if let kind { parts.append("\"kind\":\"\(kind)\"") }
            if let body { parts.append("\"body\":\(body)") }
            if let character { parts.append("\"from_character\":\"\(character)\"") }
            if let avatar { parts.append("\"from_avatar_url\":\"\(avatar)\"") }
            return "{" + parts.joined(separator: ",") + "}"
        }
        let boundaries = [
            row("p-age0", age: 0, kind: "normal", character: "aing_gold"),
            row("p-age3600", age: 3600, kind: "normal"),
            row("p-age3601", age: 3601, kind: "normal"),
            row("u-age120", age: 120, kind: "ultra", character: "robot"),
            row("u-age121", age: 121, kind: "ultra"),
            row("u-age3601", age: 3601, kind: "ultra"),
            row("k-nil", age: 10, kind: nil),
            row("k-unknown", age: 10, kind: "zap"),
            row("m-in-pokes", age: 10, kind: "message", body: "\" 밥?\\n\""),
            row("p-future", age: -30, kind: "normal", name: ""),
        ]
        let messages = [
            row("m-age300", age: 300, kind: "message", body: "\"a\"", from: "peer-a"),
            row("m-age301", age: 301, kind: "message", body: "\"늦음\""),
            row("m-blank", age: 20, kind: "message", body: "\"  \\n \""),
            row("m-nil", age: 20, kind: "message"),
            row("m-nfd", age: 5, kind: "message", body: "\"\\u1112\\u1161 \""),
            row("m-age100", age: 100, kind: "message", body: "\" 점심 \"", avatar: "https://example.invalid/a.png", from: "peer-b"),
            row("p-normal", age: 50, kind: "normal"),
            row("u-ultra", age: 50, kind: "ultra"),
        ]
        return [
            ("boundaries", "[" + boundaries.joined(separator: ",") + "]"),
            ("messages", "[" + messages.joined(separator: ",") + "]"),
            ("empty", "[]"),
        ]
    }

    // MARK: desktop-poke/fresh

    @Test("desktop-poke/fresh — freshReceivedPokes · freshReceivedMessages")
    func fresh() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let nowDate = Date(timeIntervalSince1970: TimeInterval(Self.now))
        var cases: [GoldenJSON] = []
        for (id, text) in Self.rowSets() {
            let rows = try decoder.decode([TakenPokeRow].self, from: Data(text.utf8))
            let pokes = WorkTimerStore.freshReceivedPokes(rows: rows, now: nowDate)
            let messages = WorkTimerStore.freshReceivedMessages(rows: rows, now: nowDate)
            cases.append([
                "id": .string(id),
                "now": .int(Self.now),
                "rowsJSON": .string(text),
                "pokes": .array(pokes.map { poke in
                    [
                        "id": .string(poke.id), "fromName": .string(poke.fromName),
                        "createdAt": Self.whole(poke.createdAt.timeIntervalSince1970),
                        "kind": .string(poke.kind.rawValue), "fromCharacterID": Self.s(poke.fromCharacterID),
                    ]
                }),
                "messages": .array(messages.map { message in
                    [
                        "id": .string(message.id), "fromName": .string(message.fromName), "body": .string(message.body),
                        "createdAt": Self.whole(message.createdAt.timeIntervalSince1970),
                        "fromUserID": Self.s(message.fromUserID), "fromAvatarURL": Self.s(message.fromAvatarURL?.absoluteString),
                    ]
                }),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "desktop-poke/fresh",
            equivalence: .bit,
            swiftSources: ["Sources/check/WorkTimerStorePoke.swift", "Sources/CheckCore/SupabaseWorkModels.swift"],
            platformSensitive: false,
            spec: [
                "pokes": "P9: message 행은 빠진다 · 나이 ≤ 3600 만 · ultra 는 나이 > 120 이면 normal 로 강등(버리지 않는다) · kind nil·모르는 값은 normal · 순서는 행 순서",
                "messages": "P13: message 행만 · 본문 MessageBody.sanitized 뒤 비면 버린다 · 나이 ≤ 300 · createdAt 오름차순",
                "time": "createdAt 은 1970 기준 정수 초 · now 도 같다",
            ],
            cases: cases
        ))
    }

    // MARK: desktop-poke/send-notice

    @MainActor
    @Test("desktop-poke/send-notice — ultraSentNotice · 안내 · 상수 · 발사 응답 → 결과")
    func sendNotice() throws {
        var cases: [GoldenJSON] = []
        cases.append([
            "id": "ultra-sent",
            "rows": .array([nil, -1, 0, 1, 2, 99].map { (balance: Int?) -> GoldenJSON in
                ["balance": Self.n(balance), "notice": .string(WorkTimerStore.ultraSentNotice(balance: balance))]
            }),
        ])
        cases.append([
            "id": "constants",
            "ultraEmptyNotice": .string(WorkTimerStore.ultraEmptyNotice),
            "targetFocusedNotice": .string(WorkTimerStore.targetFocusedNotice),
            "targetOnPhoneNotice": .string(WorkTimerStore.targetOnPhoneNotice),
            "pokePollIntervalSeconds": Self.whole(WorkTimerStore.pokePollIntervalSeconds),
            "pokePollIntervalSecondsWhileSubscribed": Self.whole(WorkTimerStore.pokePollIntervalSecondsWhileSubscribed),
            "pokeDisplayFreshnessSeconds": Self.whole(WorkTimerStore.pokeDisplayFreshnessSeconds),
            "ultraDisplayFreshnessSeconds": Self.whole(WorkTimerStore.ultraDisplayFreshnessSeconds),
            "pokeCooldownSeconds": Self.whole(WorkTimerStore.pokeCooldownSeconds),
            "adoptedPokeConsumerInputWindowSeconds": Self.whole(WorkTimerStore.adoptedPokeConsumerInputWindowSeconds),
            "messageQueueLimit": .int(WorkTimerStore.messageQueueLimit),
            "messageDisplayFreshnessSeconds": Self.whole(WorkTimerStore.messageDisplayFreshnessSeconds),
            "pollingKeepsRunningAlongsideRealtime": .bool(WorkTimerStore.pollingKeepsRunningAlongsideRealtime),
        ])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let responses = [
            #"{"status":"ok"}"#, #"{"status":"ok","ultra_balance":3}"#, #"{"status":"ok","ultra_remaining":-2}"#,
            #"{"status":"ok","ultra_balance":0,"ultra_remaining":5}"#,
            #"{"status":"cooldown","retry_after_seconds":42}"#, #"{"status":"cooldown"}"#, #"{"status":"cooldown","retry_after_seconds":0}"#,
            #"{"status":"not_working"}"#, #"{"status":"target_not_working"}"#, #"{"status":"target_focused"}"#,
            #"{"status":"target_on_phone"}"#, #"{"status":"ultra_used_today"}"#, #"{"status":"ultra_used_today","reset_after_seconds":120,"ultra_balance":0}"#,
            #"{"status":"invalid"}"#, #"{"status":"weird"}"#,
        ]
        var outcomes: [GoldenJSON] = []
        for text in responses {
            let response = try decoder.decode(PokeSendResponse.self, from: Data(text.utf8))
            let outcome: String
            switch PokeSendOutcome(response: response) {
            case .ok: outcome = "ok"
            case .cooldown(let seconds): outcome = "cooldown:\(seconds)"
            case .notWorking: outcome = "notWorking"
            case .targetNotWorking: outcome = "targetNotWorking"
            case .ultraUsedToday(let reset): outcome = "ultraUsedToday:\(reset)"
            case .targetFocused: outcome = "targetFocused"
            case .targetOnPhone: outcome = "targetOnPhone"
            case .invalid: outcome = "invalid"
            }
            outcomes.append(["response": .string(text), "outcome": .string(outcome),
                             "ultraBalanceForDisplay": Self.n(response.ultraBalanceForDisplay)])
        }
        cases.append(["id": "outcomes", "rows": .array(outcomes)])
        goldenEmit(GoldenFile(
            golden: "desktop-poke/send-notice",
            equivalence: .bit,
            swiftSources: ["Sources/check/WorkTimerStorePoke.swift", "Sources/CheckCore/SupabaseWorkModels.swift"],
            platformSensitive: false,
            spec: [
                "ultra-sent": "P3: 잔량을 모르면(nil) 숫자를 지어내지 않는다 · 0 이하는 '이제 0개예요'",
                "constants": "P11 폴링 15/60 · 신선도 3600/120/300 · 쿨타임 60 · 흡수 입력 창 900(서버 600 보다 넓다) · 큐 상한 20 · 폴링은 링과 함께 돈다",
                "outcomes": "발사 응답 원문 → PokeSendOutcome(cooldown 은 max(1, ?? 60) · ultra_used_today 는 max(1, ?? 3600)) · ultraBalanceForDisplay(ultra_balance ?? ultra_remaining, 음수는 0)",
            ],
            cases: cases
        ))
    }

    // MARK: desktop-poke/requests

    @Test("desktop-poke/requests — poke_user · ultra_poke_user · take_pokes 경로 · 본문 · PGRST202 재호출")
    func requests() async throws {
        let missing = #"{"code":"PGRST202","message":"Could not find the function public.take_pokes in the schema cache"}"#
        let row = #"[{"id":"p-1","from_user":"peer-1","from_display_name":"보낸이","created_epoch":1790000000,"kind":"normal"}]"#
        let scenarios: [(String, [(Int, String)], (SupabaseWorkService) async throws -> String)] = [
            ("poke-user", [(200, #"{"status":"ok"}"#)], { service in
                try await service.sendPoke(accessToken: "token", to: "user-1").status
            }),
            ("ultra-poke-user", [(200, #"{"status":"ok","ultra_balance":2}"#)], { service in
                try await service.sendUltraPoke(accessToken: "token", to: "user-2").status
            }),
            ("take-pokes", [(200, row)], { service in
                "rows:\(try await service.takePokes(accessToken: "token").count)"
            }),
            ("take-pokes-fallback-then-new-shape", [(404, missing), (200, row), (200, "[]")], { service in
                let first = try await service.takePokes(accessToken: "token").count
                let second = try await service.takePokes(accessToken: "token").count
                return "rows:\(first),\(second)"
            }),
        ]
        var cases: [GoldenJSON] = []
        for (id, script, call) in scenarios {
            GoldenPokeURLProtocol.reset(script: script)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [GoldenPokeURLProtocol.self]
            let service = SupabaseWorkService(projectURL: URL(string: "https://golden.invalid")!, anonKey: "k",
                                              session: URLSession(configuration: configuration))
            let result = try await call(service)
            cases.append([
                "id": .string(id),
                "script": .array(script.map { ["status": .int($0.0), "body": .string($0.1)] }),
                "result": .string(result),
                "requests": .array(GoldenPokeURLProtocol.recorded().map { ["method": .string($0.0), "path": .string($0.1), "body": .string($0.2)] }),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "desktop-poke/requests",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkServiceMacOnly.swift", "Sources/CheckCore/SupabaseWorkModels.swift"],
            platformSensitive: false,
            spec: [
                "bodies": "본문 바이트 그대로(JSONEncoder convertToSnakeCase) — poke_user·ultra_poke_user 는 {p_to}, take_pokes 는 언제나 {p_message_capable:true}",
                "fallback": "P12: PGRST202(404) 이면 같은 경로에 {} 로 한 번 더 · 그 판정을 캐시하지 않는다(다음 호출은 다시 새 모양)",
                "result": "응답 status 또는 디코드한 행 수(시나리오 확인용)",
            ],
            cases: cases
        ))
    }
}

/// 이 스위트 전용 가짜 전송(대본 순서대로 응답하고 method·path·본문을 적는다). 스위트가 .serialized 라 정적 상태를 나눠 쓰지 않는다.
final class GoldenPokeURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var script: [(Int, String)] = []
    private nonisolated(unsafe) static var log: [(String, String, String)] = []

    static func reset(script: [(Int, String)]) {
        lock.lock(); defer { lock.unlock() }
        Self.script = script
        log = []
    }

    static func recorded() -> [(String, String, String)] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        let (status, text): (Int, String) = {
            Self.lock.lock(); defer { Self.lock.unlock() }
            Self.log.append((request.httpMethod ?? "", request.url?.path ?? "", String(decoding: body, as: UTF8.self)))
            return Self.script.isEmpty ? (200, "{}") : Self.script.removeFirst()
        }()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
