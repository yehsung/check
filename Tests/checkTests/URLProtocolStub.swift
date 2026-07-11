import Foundation

extension URLSessionConfiguration {
    static var stubbed: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return configuration
    }
}

final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodiesByHost: [String: [String]] = [:]
    nonisolated(unsafe) static var patchWorkSessionsShouldFail = false
    nonisolated(unsafe) static var delayedHosts: Set<String> = []
    nonisolated(unsafe) static var responseDelay: TimeInterval = 0.15

    private var isStopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodiesByHost[request.url?.host ?? "", default: []].append(Self.bodyText(from: request))

        let responseData = Self.responseData(for: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode(for: request),
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!

        let delivery = StubDelivery(proto: self, response: response, data: responseData)
        if let host = request.url?.host, Self.delayedHosts.contains(host) {
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.responseDelay) {
                delivery.run()
            }
        } else {
            delivery.run()
        }
    }

    override func stopLoading() {
        isStopped = true
    }

    private final class StubDelivery: @unchecked Sendable {
        let proto: URLProtocolStub
        let response: HTTPURLResponse
        let data: Data

        init(proto: URLProtocolStub, response: HTTPURLResponse, data: Data) {
            self.proto = proto
            self.response = response
            self.data = data
        }

        func run() {
            guard !proto.isStopped else { return }
            proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: data)
            proto.client?.urlProtocolDidFinishLoading(proto)
        }
    }

    static func requests(forHost host: String) -> [URLRequest] {
        requests.filter { $0.url?.host == host }
    }

    static func bodyText(forHost host: String) -> String {
        bodiesByHost[host, default: []].joined(separator: "\n")
    }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8) ?? ""
        }

        guard let stream = request.httpBodyStream else {
            return ""
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func statusCode(for request: URLRequest) -> Int {
        if request.url?.host == "invalid-key" {
            return 401
        }
        if request.url?.host == "invalid-login" && request.url?.path == "/auth/v1/token" {
            return 400
        }
        if request.url?.host == "email-not-confirmed" && request.url?.path == "/auth/v1/token" {
            return 400
        }
        if request.url?.host == "schema-missing" && request.url?.path.hasPrefix("/rest/v1/") == true {
            return 404
        }
        if request.url?.host == "expired-token",
           request.url?.path.hasPrefix("/rest/v1/") == true,
           request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access-token" {
            return 401
        }
        if request.url?.host == "stop-fails",
           request.url?.path == "/rest/v1/work_sessions",
           request.httpMethod == "PATCH" {
            return 500
        }
        if request.url?.host == "retry-toggle",
           request.url?.path == "/rest/v1/work_sessions",
           request.httpMethod == "PATCH" {
            return patchWorkSessionsShouldFail ? 500 : 200
        }

        return request.url?.path == "/rest/v1/work_sessions" ? 201 : 200
    }

    private static func responseData(for request: URLRequest) -> Data {
        if request.url?.host == "invalid-key" {
            return Data(
                """
                {"message":"Invalid API key","hint":"Double check your Supabase `anon` or `service_role` API key."}
                """.utf8
            )
        }
        if request.url?.host == "invalid-login" && request.url?.path == "/auth/v1/token" {
            return Data(#"{"msg":"Invalid login credentials","code":400}"#.utf8)
        }
        if request.url?.host == "email-not-confirmed" && request.url?.path == "/auth/v1/token" {
            return Data(#"{"msg":"Email not confirmed","code":400}"#.utf8)
        }
        if request.url?.host == "schema-missing" && request.url?.path.hasPrefix("/rest/v1/") == true {
            return Data(#"{"code":"PGRST205","message":"Could not find the table 'public.work_statuses' in the schema cache"}"#.utf8)
        }
        if request.url?.host == "expired-token",
           request.url?.path.hasPrefix("/rest/v1/") == true,
           request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access-token" {
            return Data(#"{"code":"PGRST301","message":"JWT expired"}"#.utf8)
        }
        if request.url?.path == "/rest/v1/work_statuses" {
            return workStatusesData(for: request)
        }
        if request.url?.path == "/rest/v1/work_sessions", request.httpMethod == "GET" {
            return workSessionsData(for: request)
        }
        if request.url?.path == "/auth/v1/token",
           request.url?.query?.contains("grant_type=refresh_token") == true
        {
            return Data(
                """
                {
                  "access_token": "refreshed-token",
                  "refresh_token": "next-refresh-token",
                  "user": { "id": "00000000-0000-0000-0000-000000000002" }
                }
                """.utf8
            )
        }
        if request.url?.path == "/auth/v1/token" {
            return Data(
                """
                {
                  "access_token": "signed-in-token",
                  "refresh_token": "signed-in-refresh-token",
                  "user": { "id": "00000000-0000-0000-0000-000000000002" }
                }
                """.utf8
            )
        }

        guard request.url?.path == "/auth/v1/signup" else {
            return Data()
        }

        return Data(
            """
            {
              "access_token": "signed-up-token",
              "refresh_token": "signed-up-refresh-token",
              "user": { "id": "00000000-0000-0000-0000-000000000002" }
            }
            """.utf8
        )
    }

    private static func workStatusesData(for request: URLRequest) -> Data {
        if request.url?.host == "today-hours-test" {
            return Data(
                """
                [
                  {
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "status": "off_work",
                    "updated_at": "2026-07-10T04:00:00Z",
                    "active_session_id": null,
                    "profiles": { "display_name": "영식", "email": "member@example.com" }
                  }
                ]
                """.utf8
            )
        }

        if Self.hasTeamFixture(for: request) == false {
            return Data("[]".utf8)
        }

        return Data(
            """
            [
              {
                "user_id": "00000000-0000-0000-0000-000000000002",
                "status": "working",
                "updated_at": "2026-07-01T01:00:00Z",
                "active_session_id": "30000000-0000-0000-0000-000000000001",
                "profiles": { "display_name": "영식", "email": "member@example.com" }
              }
            ]
            """.utf8
        )
    }

    private static func workSessionsData(for request: URLRequest) -> Data {
        if request.url?.host == "today-hours-test" {
            if request.url?.query?.contains("ended_at=is.null") == true {
                return Data("[]".utf8)
            }
            return Data(
                """
                [
                  {
                    "id": "40000000-0000-0000-0000-000000000001",
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "started_at": "2026-07-10T04:00:00Z",
                    "ended_at": "2026-07-10T05:00:00Z",
                    "duration_seconds": 3600
                  },
                  {
                    "id": "40000000-0000-0000-0000-000000000002",
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "started_at": "2026-07-08T04:00:00Z",
                    "ended_at": "2026-07-08T04:30:00Z",
                    "duration_seconds": 1800
                  }
                ]
                """.utf8
            )
        }

        guard Self.hasTeamFixture(for: request) else {
            return Data("[]".utf8)
        }

        if request.url?.query?.contains("ended_at=is.null") == true {
            return Data(
                """
                [
                  {
                    "id": "30000000-0000-0000-0000-000000000001",
                    "user_id": "00000000-0000-0000-0000-000000000002",
                    "started_at": "2026-07-01T01:00:00Z",
                    "ended_at": null,
                    "duration_seconds": null
                  }
                ]
                """.utf8
            )
        }

        return Data(
            """
            [
              {
                "id": "30000000-0000-0000-0000-000000000000",
                "user_id": "00000000-0000-0000-0000-000000000002",
                "started_at": "2026-07-01T00:00:00Z",
                "ended_at": "2026-07-01T02:00:00Z",
                "duration_seconds": 7200
              }
            ]
            """.utf8
        )
    }

    private static func hasTeamFixture(for request: URLRequest) -> Bool {
        let host = request.url?.host
        return host == "team-hours-test"
            || host == "expired-token"
            || host == "stop-fails"
            || host == "signout-refresh-race"
            || host?.hasPrefix("korean-week-") == true
    }
}
