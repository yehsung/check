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
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

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
        request.url?.host == "team-hours-test" || request.url?.host?.hasPrefix("korean-week-") == true
    }
}
