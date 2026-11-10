import Foundation
import Testing
@testable import CheckCore

// 비공개 버킷 도우미(`SupabaseWorkServicePrivateStorage.swift`) — 올리기 · 인증 받기 · 서명 URL · 지우기 · 오류 갈래.
//
// 이 스위트가 지키는 것:
//  ① 올리기는 POST · image/jpeg · 로그인 토큰 · **x-upsert 없음**(같은 경로를 덮지 않는다).
//  ② 받기는 `/object/authenticated/` 경로 + 로그인 토큰(공개 URL 로는 비공개 버킷을 못 읽는다).
//  ③ 서명 본문 키는 `expiresIn` 그대로다(스네이크 인코더가 `expires_in` 으로 바꾸면 저장소가 400 을 준다).
//  ④ 409 "already exists" 가 **`.emailAlreadyRegistered` 로 접히지 않는다** — 대조군으로 공용 매핑이 실제로 그렇게 접는다는
//     사실을 함께 잰다(대조군이 없으면 이 단언은 매핑이 바뀌어도 공짜로 초록이다).
//  ⑤ 만료 토큰은 문장이 달라도 `.sessionExpired`(세션 갱신이 도는 유일한 갈래) · 버킷 없음은 "아직 안 열림" ·
//     개체 없음은 그와 다른 값.
//  ⑥ 지우기는 던지지 않고 "더는 없나"만 돌려준다.
//
// 네트워크는 아래 스텁(테스트별 고유 호스트)으로 막는다. 픽스처 바이트는 전부 합성이다.

private let psUser = "00000000-0000-0000-0000-00000000000a"

/// 호스트 × 경로별 (상태, 본문)을 심고, 나간 요청(메서드 · 경로 · 머리 · 본문 바이트)을 그대로 적는 스텁.
final class PrivateStorageURLProtocol: URLProtocol {
    struct Sent: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var replies: [String: [String: (Int, Data)]] = [:]
    private nonisolated(unsafe) static var sent: [String: [Sent]] = [:]

    static func set(status: Int, body: String = "", host: String, path: String) {
        lock.lock(); defer { lock.unlock() }
        replies[host, default: [:]][path] = (status, Data(body.utf8))
    }

    static func set(status: Int, data: Data, host: String, path: String) {
        lock.lock(); defer { lock.unlock() }
        replies[host, default: [:]][path] = (status, data)
    }

    static func requests(host: String) -> [Sent] {
        lock.lock(); defer { lock.unlock() }
        return sent[host] ?? []
    }

    static func service(host: String) -> SupabaseWorkService {
        lock.lock()
        replies[host] = nil
        sent[host] = nil
        lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PrivateStorageURLProtocol.self]
        return SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: configuration)
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func bodyData(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let entry = Sent(
            method: request.httpMethod ?? "",
            path: path,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.bodyData(request)
        )
        Self.lock.lock()
        Self.sent[host, default: []].append(entry)
        let reply = Self.replies[host]?[path] ?? (200, Data("{}".utf8))
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.0, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func psHeader(_ sent: PrivateStorageURLProtocol.Sent, _ name: String) -> String? {
    sent.headers.first { $0.key.lowercased() == name.lowercased() }?.value
}

// MARK: - 경로 규칙(순수)

@Test
func privateStoragePathIsLowercasedOwnerSlashFreshName() {
    // 서버 정책은 첫 폴더를 auth.uid()::text(소문자)와 글자 그대로 견준다 — UUID().uuidString 은 대문자다.
    let path = PrivateStorage.objectPath(owner: "ABCDEF00-0000-0000-0000-00000000000A", name: "1234ABCD-0000-0000-0000-0000000000FF")
    #expect(path == "abcdef00-0000-0000-0000-00000000000a/1234abcd-0000-0000-0000-0000000000ff.jpg")
    #expect(PrivateStorage.isSafeObjectPath(path))
    for bad in ["", "a.jpg", "/a/b.jpg", "a/b.jpg/", "a//b.jpg", "a/../b.jpg", "./a/b.jpg", "a/b c.jpg", "A/b.jpg", "a/b?.jpg", "a/b%2e.jpg"] {
        #expect(!PrivateStorage.isSafeObjectPath(bad), "막아야 할 경로를 통과시켰다: \(bad)")
    }
    #expect(PrivateStorage.isSafeBucket("feedback-shots"))
    #expect(!PrivateStorage.isSafeBucket("feedback/shots"))
    #expect(!PrivateStorage.isSafeBucket(""))
}

// MARK: - 올리기

@Test
func privateUploadPostsJPEGWithTheBearerAndNeverUpserts() async throws {
    let host = "ps-upload-ok"
    let service = PrivateStorageURLProtocol.service(host: host)
    let path = PrivateStorage.objectPath(owner: psUser, name: "11111111-2222-3333-4444-555555555555")
    PrivateStorageURLProtocol.set(status: 200, body: #"{"Key":"feedback-shots/x.jpg"}"#, host: host,
                                  path: "/storage/v1/object/feedback-shots/\(path)")
    let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])

    let returned = try await service.uploadPrivateObject(
        bucket: "feedback-shots", path: path, data: bytes,
        contentType: PrivateStorage.jpegContentType, accessToken: "access-token"
    )

    #expect(returned == path, "올린 경로를 그대로 돌려줘야 RPC 에 같은 값이 실린다")
    let sent = try #require(PrivateStorageURLProtocol.requests(host: host).only)
    #expect(sent.method == "POST")
    #expect(sent.path == "/storage/v1/object/feedback-shots/\(path)")
    #expect(psHeader(sent, "Authorization") == "Bearer access-token")
    #expect(psHeader(sent, "apikey") == "anon-test-key")
    #expect(psHeader(sent, "Content-Type") == "image/jpeg")
    #expect(psHeader(sent, "x-upsert") == nil, "비공개 버킷 올리기가 덮어쓰기를 연다 — 경로를 아는 누군가가 남의 캡처를 갈아 끼울 수 있다")
    #expect(sent.body == bytes, "올린 바이트가 원본과 다르다")
}

@Test
func privateUploadRefusesAStrangePathWithoutSendingAnything() async {
    let host = "ps-upload-badpath"
    let service = PrivateStorageURLProtocol.service(host: host)
    await #expect(throws: PrivateStorageError.invalidPath) {
        try await service.uploadPrivateObject(
            bucket: "feedback-shots", path: "../avatars/x.jpg", data: Data([1]),
            contentType: PrivateStorage.jpegContentType, accessToken: "t"
        )
    }
    #expect(PrivateStorageURLProtocol.requests(host: host).isEmpty, "이상한 경로인데 요청이 나갔다")
}

// MARK: - 받기

@Test
func privateDownloadReadsTheAuthenticatedPathWithTheBearer() async throws {
    let host = "ps-download-ok"
    let service = PrivateStorageURLProtocol.service(host: host)
    let path = "\(psUser)/aaaaaaaa-0000-0000-0000-000000000001.jpg"
    let bytes = Data([0xFF, 0xD8, 0x01, 0x02, 0x03])
    PrivateStorageURLProtocol.set(status: 200, data: bytes, host: host,
                                  path: "/storage/v1/object/authenticated/feedback-shots/\(path)")

    let data = try await service.downloadPrivateObject(bucket: "feedback-shots", path: path, accessToken: "access-token")

    #expect(data == bytes)
    let sent = try #require(PrivateStorageURLProtocol.requests(host: host).only)
    #expect(sent.method == "GET")
    #expect(sent.path == "/storage/v1/object/authenticated/feedback-shots/\(path)")
    #expect(psHeader(sent, "Authorization") == "Bearer access-token", "로그인 토큰 없이 비공개 버킷을 읽으려 했다")
    #expect(psHeader(sent, "apikey") == "anon-test-key")
}

@Test
func privateDownloadOfAMissingObjectIsNotTheSameAsAMissingBucket() async {
    let host = "ps-download-missing"
    let service = PrivateStorageURLProtocol.service(host: host)
    let objectPath = "\(psUser)/bbbbbbbb-0000-0000-0000-000000000002.jpg"
    PrivateStorageURLProtocol.set(status: 400, body: #"{"statusCode":"404","error":"not_found","message":"Object not found"}"#,
                                  host: host, path: "/storage/v1/object/authenticated/feedback-shots/\(objectPath)")
    await #expect(throws: PrivateStorageError.objectMissing) {
        try await service.downloadPrivateObject(bucket: "feedback-shots", path: objectPath, accessToken: "t")
    }

    let host2 = "ps-download-nobucket"
    let service2 = PrivateStorageURLProtocol.service(host: host2)
    PrivateStorageURLProtocol.set(status: 404, body: #"{"statusCode":"404","error":"Bucket not found","message":"Bucket not found"}"#,
                                  host: host2, path: "/storage/v1/object/authenticated/feedback-shots/\(objectPath)")
    await #expect(throws: SupabaseWorkServiceError.databaseSchemaMissing) {
        try await service2.downloadPrivateObject(bucket: "feedback-shots", path: objectPath, accessToken: "t")
    }
}

// MARK: - 서명 URL

@Test
func signedURLSendsExpiresInVerbatimAndResolvesTheRelativeAnswer() async throws {
    let host = "ps-sign-ok"
    let service = PrivateStorageURLProtocol.service(host: host)
    let path = "\(psUser)/cccccccc-0000-0000-0000-000000000003.jpg"
    PrivateStorageURLProtocol.set(
        status: 200,
        body: #"{"signedURL":"/object/sign/feedback-shots/\#(path)?token=synthetic-token"}"#,
        host: host, path: "/storage/v1/object/sign/feedback-shots/\(path)"
    )

    let url = try await service.createSignedObjectURL(bucket: "feedback-shots", path: path, expiresIn: 600, accessToken: "access-token")

    #expect(url.absoluteString == "http://\(host)/storage/v1/object/sign/feedback-shots/\(path)?token=synthetic-token")
    let sent = try #require(PrivateStorageURLProtocol.requests(host: host).only)
    #expect(sent.method == "POST")
    #expect(psHeader(sent, "Authorization") == "Bearer access-token")
    #expect(psHeader(sent, "Content-Type") == "application/json")
    let body = try #require(try JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
    #expect(Set(body.keys) == ["expiresIn"], "서명 본문 키가 바뀌었다(스네이크 인코더를 지났나): \(body.keys.sorted())")
    #expect(body["expiresIn"] as? Int == 600)
}

@Test
func signedURLAcceptsTheOtherSpellingsOfTheAnswer() {
    let base = URL(string: "https://project.example")!
    let lower = Data(#"{"signedUrl":"/object/sign/b/u/x.jpg?token=t"}"#.utf8)
    #expect(SupabaseWorkService.signedURL(from: lower, projectURL: base)?.absoluteString
            == "https://project.example/storage/v1/object/sign/b/u/x.jpg?token=t")
    let absolute = Data(#"{"signedURL":"https://cdn.example/storage/v1/object/sign/b/u/x.jpg?token=t"}"#.utf8)
    #expect(SupabaseWorkService.signedURL(from: absolute, projectURL: base)?.absoluteString
            == "https://cdn.example/storage/v1/object/sign/b/u/x.jpg?token=t")
    let prefixed = Data(#"{"signedURL":"/storage/v1/object/sign/b/u/x.jpg?token=t"}"#.utf8)
    #expect(SupabaseWorkService.signedURL(from: prefixed, projectURL: URL(string: "https://project.example/")!)?.absoluteString
            == "https://project.example/storage/v1/object/sign/b/u/x.jpg?token=t")
    #expect(SupabaseWorkService.signedURL(from: Data("{}".utf8), projectURL: base) == nil)
    #expect(SupabaseWorkService.signedURL(from: Data("not json".utf8), projectURL: base) == nil)
}

// MARK: - 지우기(최선 노력)

@Test
func privateDeleteNeverThrowsAndSaysWhetherTheObjectIsGone() async throws {
    let path = "\(psUser)/dddddddd-0000-0000-0000-000000000004.jpg"
    let cases: [(String, Int, String, Bool)] = [
        ("ps-delete-200", 200, #"{"message":"Successfully deleted"}"#, true),
        ("ps-delete-404", 404, #"{"statusCode":"404","error":"not_found","message":"Object not found"}"#, true),
        ("ps-delete-400nf", 400, #"{"statusCode":"404","error":"not_found","message":"Object not found"}"#, true),
        ("ps-delete-403", 403, #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#, false),
        ("ps-delete-500", 500, "", false),
    ]
    for (host, status, body, expected) in cases {
        let service = PrivateStorageURLProtocol.service(host: host)
        PrivateStorageURLProtocol.set(status: status, body: body, host: host, path: "/storage/v1/object/feedback-shots/\(path)")
        let gone = await service.deletePrivateObject(bucket: "feedback-shots", path: path, accessToken: "access-token")
        #expect(gone == expected, "\(host): \(gone)")
        let sent = try #require(PrivateStorageURLProtocol.requests(host: host).only)
        #expect(sent.method == "DELETE")
        #expect(sent.path == "/storage/v1/object/feedback-shots/\(path)")
        #expect(psHeader(sent, "Authorization") == "Bearer access-token")
    }
    // 이상한 경로는 요청 없이 false.
    let host = "ps-delete-badpath"
    let service = PrivateStorageURLProtocol.service(host: host)
    #expect(await service.deletePrivateObject(bucket: "feedback-shots", path: "a/../b.jpg", accessToken: "t") == false)
    #expect(PrivateStorageURLProtocol.requests(host: host).isEmpty)
}

// MARK: - 오류 갈래

@Test
func aStorageConflictNeverFoldsIntoAnEmailThatIsAlreadyRegistered() async throws {
    let conflict = Data(#"{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}"#.utf8)
    // 대조군: 공용 매핑은 이 본문을 정말로 가입 오류로 접는다(그래서 이 파일이 그 매핑을 지나지 않는다).
    let generic = SupabaseWorkService(projectURL: URL(string: "http://ps-control")!, anonKey: "k")
    #expect(await generic.serviceError(statusCode: 409, data: conflict) == .emailAlreadyRegistered,
            "대조군이 무너졌다 — 공용 매핑이 바뀌었다면 이 테스트의 근거를 다시 적어라")

    let mapped = SupabaseWorkService.privateStorageError(statusCode: 409, data: conflict, operation: .upload)
    #expect(mapped as? PrivateStorageError == .alreadyExists)
    #expect(mapped as? SupabaseWorkServiceError != .emailAlreadyRegistered)
    // HTTP 400 에 본문 statusCode 409 로 오는 판도 같다.
    let wrapped = SupabaseWorkService.privateStorageError(statusCode: 400, data: conflict, operation: .upload)
    #expect(wrapped as? PrivateStorageError == .alreadyExists)

    // 왕복으로도 같은 값이 올라온다.
    let host = "ps-upload-conflict"
    let service = PrivateStorageURLProtocol.service(host: host)
    let path = "\(psUser)/eeeeeeee-0000-0000-0000-000000000005.jpg"
    PrivateStorageURLProtocol.set(status: 409, data: conflict, host: host, path: "/storage/v1/object/feedback-shots/\(path)")
    await #expect(throws: PrivateStorageError.alreadyExists) {
        try await service.uploadPrivateObject(bucket: "feedback-shots", path: path, data: Data([1]),
                                              contentType: PrivateStorage.jpegContentType, accessToken: "t")
    }
}

@Test
func expiredTokensComeBackAsSessionExpiredWhateverTheStorageSays() {
    let bodies: [(Int, String)] = [
        (400, #"{"statusCode":"403","error":"Unauthorized","message":"\"exp\" claim timestamp check failed"}"#),
        (403, #"{"statusCode":"403","error":"Unauthorized","message":"\"exp\" claim timestamp check failed"}"#),
        (401, #"{"statusCode":"401","error":"Unauthorized","message":"jwt expired"}"#),
        (400, #"{"statusCode":"400","error":"InvalidJWT","message":"jwt expired"}"#),
        (401, "<html>gateway</html>"),
    ]
    for (status, body) in bodies {
        for operation in [SupabaseWorkService.PrivateStorageOperation.upload, .read, .delete] {
            let error = SupabaseWorkService.privateStorageError(statusCode: status, data: Data(body.utf8), operation: operation)
            #expect(error as? SupabaseWorkServiceError == .sessionExpired, "\(status) \(body) → \(error)")
        }
    }
}

@Test
func storageFailuresLandInTheRightBucketOfMeaning() {
    func map(_ status: Int, _ body: String, _ operation: SupabaseWorkService.PrivateStorageOperation = .upload) -> Error {
        SupabaseWorkService.privateStorageError(statusCode: status, data: Data(body.utf8), operation: operation)
    }
    // 버킷이 없다 = 아직 안 열린 기능(함수 없음과 같은 판정 표에 걸린다).
    let noBucket = map(404, #"{"statusCode":"404","error":"Bucket not found","message":"Bucket not found"}"#)
    #expect(noBucket as? SupabaseWorkServiceError == .databaseSchemaMissing)
    #expect(BlockReportRules.isMissingFunction(noBucket as! SupabaseWorkServiceError))
    #expect(map(400, #"{"statusCode":"404","error":"Bucket not found","message":"Bucket not found"}"#) as? SupabaseWorkServiceError
            == .databaseSchemaMissing)
    // 올리기의 404(본문 없음 · 게이트웨이) = 저장소 경로 자체가 없다 → 아직 안 열림.
    #expect(map(404, "") as? SupabaseWorkServiceError == .databaseSchemaMissing)
    // 받기의 404 = 그 개체가 없다(버킷은 있다).
    #expect(map(404, #"{"statusCode":"404","error":"not_found","message":"Object not found"}"#, .read) as? PrivateStorageError
            == .objectMissing)
    // 정책 위반 403 은 만료가 아니다(갱신해도 소용없다).
    #expect(map(403, #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#)
            as? PrivateStorageError == .forbidden)
    #expect(map(400, #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#)
            as? PrivateStorageError == .forbidden)
    #expect(map(413, #"{"statusCode":"413","error":"Payload too large","message":"The object exceeded the maximum allowed size"}"#)
            as? PrivateStorageError == .tooLarge)
    #expect(map(500, "") as? SupabaseWorkServiceError == .invalidResponse(500))
    #expect(map(502, "<html>bad gateway</html>") as? SupabaseWorkServiceError == .invalidResponse(502))
    #expect(map(429, #"{"message":"Too many requests"}"#) as? SupabaseWorkServiceError == .rateLimited(retryAfterSeconds: nil))
    #expect(map(400, #"{"statusCode":"400","error":"InvalidKey","message":"Invalid key"}"#) as? SupabaseWorkServiceError
            == .invalidResponse(400))
}

private extension Array {
    /// 정확히 한 개면 그 값, 아니면 nil(요청이 하나만 나갔다는 단언에 쓴다).
    var only: Element? { count == 1 ? first : nil }
}
