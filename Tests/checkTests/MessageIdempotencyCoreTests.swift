import Foundation
import Testing
@testable import CheckCore

// send_message 전송 멱등 키(20261102200000)의 CheckCore 계약.
//  ① 키가 있으면 `p_client_message_id` 로 나가고, 없으면 키 자체가 빠진다(옛 서버에 옛 모양 그대로).
//  ② 3인자 서명이 없는 서버(404 PGRST202)에는 **한 번만** 옛 모양으로 되묻는다.
//  ③ 응답의 message_id · created_at · duplicate 는 **JSON 을 실제로 통과시켜** 읽힌다 —
//     PokeSendResponse 는 커스텀 init(from:) 이라 CodingKey 만 더하면 값이 영원히 nil 이다.

/// 호스트별로 요청 본문을 전부 쌓고, `legacy-` 로 시작하는 호스트는 3인자 본문에 404 PGRST202 를 돌려주는 스텁.
final class MessageIdempotencyURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var okJSONByHost: [String: String] = [:]
    private nonisolated(unsafe) static var bodiesByHost: [String: [String]] = [:]

    static func prepare(host: String, okJSON: String) {
        lock.lock(); defer { lock.unlock() }
        okJSONByHost[host] = okJSON
        bodiesByHost[host] = []
    }

    static func bodies(forHost host: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return bodiesByHost[host] ?? []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MessageIdempotencyURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody { return String(data: body, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let body = Self.bodyText(from: request)
        Self.lock.lock()
        Self.bodiesByHost[host, default: []].append(body)
        let okJSON = Self.okJSONByHost[host] ?? #"{"status":"ok"}"#
        Self.lock.unlock()

        let legacyRejects = host.hasPrefix("legacy-") && body.contains("p_client_message_id")
        let status = legacyRejects ? 404 : 200
        let json = legacyRejects
            ? #"{"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.send_message(p_body, p_client_message_id, p_to) in the schema cache"}"#
            : okJSON
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func idempotencyService(host: String) -> SupabaseWorkService {
    SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: MessageIdempotencyURLProtocol.session()
    )
}

@Test
func sendMessageCarriesClientMessageIDAndOmitsItWhenNil() async throws {
    let host = "msg-idem-shape"
    MessageIdempotencyURLProtocol.prepare(host: host, okJSON: #"{"status":"ok","body":"가나다","ring":"sent"}"#)
    let service = idempotencyService(host: host)

    _ = try await service.sendMessage(
        accessToken: "t", to: "peer", body: "가나다", clientMessageID: "0b6e6f0e-3f7a-4a51-9d55-6f0b8a1e2c33")
    _ = try await service.sendMessage(accessToken: "t", to: "peer", body: "가나다")

    let bodies = MessageIdempotencyURLProtocol.bodies(forHost: host)
    #expect(bodies.count == 2)
    #expect(bodies[0].contains(#""p_client_message_id":"0b6e6f0e-3f7a-4a51-9d55-6f0b8a1e2c33""#))
    #expect(!bodies[0].contains("pClientMessageId"), "카멜케이스가 나가면 서버가 인자를 못 찾는다")
    // nil 은 **키 자체가 없어야** 한다 — `"p_client_message_id":null` 로 나가도 옛 서버는 PGRST202 로 죽는다.
    #expect(!bodies[1].contains("p_client_message_id"))
    #expect(bodies[1].contains(#""p_to":"peer""#))
}

@Test
func sendMessageFallsBackOnceToLegacyShapeWhenServerLacksThreeArgSignature() async throws {
    let host = "legacy-msg-idem"
    MessageIdempotencyURLProtocol.prepare(host: host, okJSON: #"{"status":"ok","body":"가나다","ring":"sent"}"#)

    let response = try await idempotencyService(host: host)
        .sendMessage(accessToken: "t", to: "peer", body: "가나다", clientMessageID: "c1")

    #expect(MessageSendOutcome(response: response) == .ok)
    let bodies = MessageIdempotencyURLProtocol.bodies(forHost: host)
    // 정확히 두 번: 3인자(404) → 옛 모양(200). 세 번째가 있으면 되묻기가 고리를 돈다.
    #expect(bodies.count == 2)
    #expect(bodies[0].contains("p_client_message_id"))
    #expect(!bodies[1].contains("p_client_message_id"))
}

@Test
func sendMessageDecodesServerRowConfirmationThroughJSON() async throws {
    let host = "msg-idem-decode"
    MessageIdempotencyURLProtocol.prepare(
        host: host,
        okJSON: #"{"status":"ok","body":"가나다","ring":"duplicate","message_id":"7f1c2d3e-0000-4000-8000-000000000001","created_at":"2026-10-30T02:36:27.435997+00:00","duplicate":true}"#
    )

    let response = try await idempotencyService(host: host)
        .sendMessage(accessToken: "t", to: "peer", body: "가나다", clientMessageID: "c2")

    #expect(MessageSendOutcome(response: response) == .ok)
    #expect(response.messageId == "7f1c2d3e-0000-4000-8000-000000000001")
    #expect(response.createdAt == "2026-10-30T02:36:27.435997+00:00")
    #expect(response.duplicate == true)
    #expect(response.ring == "duplicate")

    // 키를 안 싣는 옛 서버 응답에서는 셋 다 nil(= 모름)이다.
    MessageIdempotencyURLProtocol.prepare(host: "msg-idem-old", okJSON: #"{"status":"ok","body":"가나다","ring":"sent"}"#)
    let old = try await idempotencyService(host: "msg-idem-old")
        .sendMessage(accessToken: "t", to: "peer", body: "가나다", clientMessageID: "c3")
    #expect(old.messageId == nil)
    #expect(old.createdAt == nil)
    #expect(old.duplicate == nil)
}
