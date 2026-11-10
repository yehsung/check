import Foundation

// MARK: - 비공개 버킷 도우미 (11-11 "남는 서버 자리")
//
// 제보 화면 캡처(`feedback-shots`)와 메시지 사진(`message-photos`, 다음 판)이 **같이 쓰는** 저장소 왕복 넷이다:
// 올리기 · 로그인 토큰으로 받기 · 서명 URL 만들기 · 지우기(최선 노력). 지금까지 저장소 코드는 공개 버킷(avatars)
// 하나뿐이라 서명 URL·인증 받기 경로가 없었다.
//
// ── 이 파일이 지키는 것 ──
// ① **공용 오류 매핑(`serviceError`)을 지나지 않는다.** 그 함수는 사람 로그인 응답을 위해 짜여 있어서
//    저장소 409 본문("The resource already exists")의 `exists` 를 `.emailAlreadyRegistered` 로 접는다 —
//    캡처를 다시 올리다 부딪히면 제보 화면에 "이미 가입된 이메일"이 뜬다. 그래서 상태코드와 본문을 여기서 직접 본다.
// ② **만료 토큰은 `.sessionExpired` 로 올린다.** `withSessionRetry` 가 갱신하는 갈래는 그 하나뿐인데, 저장소는
//    만료를 `401 jwt expired` 가 아니라 `400`/`403` + `"exp" claim timestamp check failed` 로 말하는 판이 있다.
//    그 문장을 못 알아보면 오래 켜 둔 맥에서 캡처 올리기만 매번 실패하고 갱신은 한 번도 안 일어난다.
// ③ **버킷이 없으면 `.databaseSchemaMissing`** 이다(서버 2단계 전 — "아직 안 열린 기능"). 메시지 읽음 RPC 와 같은
//    판정 표(`BlockReportRules.isMissingFunction`)에 그대로 걸린다. 개체 하나가 없는 것(지워졌거나 30일이 지났다)은
//    그와 다른 뜻이라 `PrivateStorageError.objectMissing` 으로 가른다 — 둘을 섞으면 지워진 사진 한 장이 기능 문을 닫는다.
// ④ **올린 바이트·받은 바이트를 로그로 흘리지 않는다.** 화면 캡처와 사진은 남의 이름·대화가 찍혀 있을 수 있다.
//
// 경로 모양(`<소유자 uid 소문자>/<새 uuid 소문자>.jpg`)과 버킷 이름은 **기능 파일이** 정한다(제보는 FeedbackShotWire).
// 이 파일은 버킷도 경로도 모른다 — 받은 것을 그대로 쓰되, 이상한 경로(`..`, 빈 조각, 허용 밖 글자)는 문 앞에서 막는다.

/// 비공개 버킷 왕복이 사람 말로 갈려야 하는 실패들. 나머지(만료 · 버킷 없음 · 5xx · 429)는 공용
/// `SupabaseWorkServiceError` 로 올린다 — 세션 갱신·"아직 안 열림" 판정이 이미 그 값을 읽는다.
package enum PrivateStorageError: Error, Equatable, Sendable {
    /// 그 경로에 개체가 없다(지워졌거나 기간이 지났다). 버킷은 있다 — 기능 문을 닫을 일이 아니다.
    case objectMissing
    /// 같은 경로가 이미 있다(409). 새 uuid 로 다시 올리면 된다. **`.emailAlreadyRegistered` 로 접히면 안 된다.**
    case alreadyExists
    /// 권한 밖이다(정책 위반 403 — 남의 폴더에 올리기 · 읽을 수 없는 개체).
    case forbidden
    /// 버킷 상한보다 크다(413).
    case tooLarge
    /// 경로 모양이 이상하다(빈 조각 · `..` · 허용 밖 글자). 요청을 보내지 않았다.
    case invalidPath
}

/// 비공개 버킷 경로 규칙(순수). 버킷마다 다른 것은 **이름과 첫 폴더의 뜻**뿐이고 모양 규칙은 하나다.
package enum PrivateStorage {
    package static let jpegContentType = "image/jpeg"

    /// `<소유자 소문자>/<이름 소문자>.<확장자>`. 서버 정책은 첫 폴더를 `auth.uid()::text` 와 **글자 그대로** 견준다 —
    /// Swift `UUID().uuidString` 은 대문자라 그대로 쓰면 자기 폴더에 못 올린다(403).
    package static func objectPath(owner: String, name: String, ext: String = "jpg") -> String {
        "\(owner.lowercased())/\(name.lowercased()).\(ext.lowercased())"
    }

    /// 요청에 실어도 되는 경로인가. 빈 조각 · `.`/`..` · 앞뒤 `/` · 소문자 영숫자와 `-_.` 밖의 글자를 막는다.
    /// 서버가 준 경로(목록 행의 `shot_path`)도 이 문을 지난다 — 이상한 값이 URL 을 엉뚱한 곳으로 돌리지 못하게.
    package static func isSafeObjectPath(_ path: String) -> Bool {
        guard !path.isEmpty, path.count <= 512 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_.")
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        for segment in segments {
            if segment.isEmpty || segment == "." || segment == ".." { return false }
            if !segment.allSatisfy({ allowed.contains($0) }) { return false }
        }
        return true
    }

    /// 버킷 이름도 같은 글자만 받는다(소문자 · 숫자 · `-`).
    package static func isSafeBucket(_ bucket: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        return !bucket.isEmpty && bucket.allSatisfy { allowed.contains($0) }
    }
}

extension SupabaseWorkService {
    /// 비공개 버킷에 올린다. `POST /storage/v1/object/<bucket>/<path>` · **`x-upsert` 없음**(같은 경로를 덮지 않는다 —
    /// 덮어쓰기가 열려 있으면 경로를 아는 누군가가 남의 캡처를 갈아 끼울 수 있다). 시도마다 새 uuid 경로를 쓰는 것은 호출부 몫이다.
    /// - Returns: 올린 개체 경로(버킷 이름 없이). 서버 RPC 에 그대로 넘긴다.
    @discardableResult
    package func uploadPrivateObject(
        bucket: String,
        path: String,
        data: Data,
        contentType: String,
        accessToken: String
    ) async throws -> String {
        try Self.requireSafe(bucket: bucket, path: path)
        _ = try await privateStorageRequest(
            method: "POST",
            path: "/storage/v1/object/\(bucket)/\(path)",
            body: data,
            contentType: contentType,
            accept: "application/json",
            accessToken: accessToken,
            operation: .upload
        )
        return path
    }

    /// 로그인 토큰으로 받는다. `GET /storage/v1/object/authenticated/<bucket>/<path>` — 읽기 판정은 서버 정책
    /// (제보 캡처: 본인 · 운영자)이다. 공개 URL·`URLSession.shared`(아바타 캐시)로는 이 버킷을 못 읽는다.
    package func downloadPrivateObject(bucket: String, path: String, accessToken: String) async throws -> Data {
        try Self.requireSafe(bucket: bucket, path: path)
        return try await privateStorageRequest(
            method: "GET",
            path: "/storage/v1/object/authenticated/\(bucket)/\(path)",
            body: nil,
            contentType: nil,
            accept: "*/*",
            accessToken: accessToken,
            operation: .read
        )
    }

    /// 서명 URL 을 만든다. `POST /storage/v1/object/sign/<bucket>/<path>` 본문 `{"expiresIn": N}` →
    /// `{"signedURL": "/object/sign/…?token=…"}`(판에 따라 `signedUrl`, 절대 URL 도 받는다).
    ///
    /// ★ 본문은 **스네이크 인코더를 지나지 않는다** — 서비스 인코더(`convertToSnakeCase`)는 `expiresIn` 을 `expires_in` 으로
    ///   바꾸고, 저장소는 그 키를 몰라 400 을 준다. 키 하나짜리라 직접 만든다.
    package func createSignedObjectURL(
        bucket: String,
        path: String,
        expiresIn: Int,
        accessToken: String
    ) async throws -> URL {
        try Self.requireSafe(bucket: bucket, path: path)
        let body = try JSONSerialization.data(withJSONObject: ["expiresIn": max(1, expiresIn)])
        let data = try await privateStorageRequest(
            method: "POST",
            path: "/storage/v1/object/sign/\(bucket)/\(path)",
            body: body,
            contentType: "application/json",
            accept: "application/json",
            accessToken: accessToken,
            operation: .read
        )
        guard let url = Self.signedURL(from: data, projectURL: projectURL) else {
            throw SupabaseWorkServiceError.invalidResponse(200)
        }
        return url
    }

    /// 지운다(최선 노력). `DELETE /storage/v1/object/<bucket>/<path>`. **던지지 않는다** — 고아 정리(올렸는데 제출이
    /// 실패한 캡처)는 실패해도 사용자가 할 일이 없다. 돌려주는 값은 "더는 없다"(2xx · 404 · not_found)인가.
    @discardableResult
    package func deletePrivateObject(bucket: String, path: String, accessToken: String) async -> Bool {
        guard PrivateStorage.isSafeBucket(bucket), PrivateStorage.isSafeObjectPath(path) else { return false }
        do {
            _ = try await privateStorageRequest(
                method: "DELETE",
                path: "/storage/v1/object/\(bucket)/\(path)",
                body: nil,
                contentType: nil,
                accept: "application/json",
                accessToken: accessToken,
                operation: .delete
            )
            return true
        } catch PrivateStorageError.objectMissing {
            return true
        } catch {
            return false
        }
    }

    // MARK: 내부

    /// 오류를 가를 때 "무엇을 하던 중이었나". 올리기에서의 404 는 개체가 아니라 **버킷**이 없다는 뜻이다.
    package enum PrivateStorageOperation: Sendable {
        case upload
        case read
        case delete
    }

    private static func requireSafe(bucket: String, path: String) throws {
        guard PrivateStorage.isSafeBucket(bucket), PrivateStorage.isSafeObjectPath(path) else {
            throw PrivateStorageError.invalidPath
        }
    }

    private func privateStorageRequest(
        method: String,
        path: String,
        body: Data?,
        contentType: String?,
        accept: String,
        accessToken: String,
        operation: PrivateStorageOperation
    ) async throws -> Data {
        guard let anonKey else { throw SupabaseWorkServiceError.missingAnonKey }
        var request = URLRequest(url: try url(path: path, queryItems: []))
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard 200..<300 ~= status else {
            throw Self.privateStorageError(statusCode: status, data: data, operation: operation)
        }
        return data
    }

    /// 저장소 실패 → 오류 값. **순수 함수**라 테스트가 본문 모양별로 직접 묻는다.
    ///
    /// 저장소는 판에 따라 HTTP 400 에 진짜 상태를 본문 `statusCode`(문자열)로 싣는다 — HTTP 가 400 이면 본문 값을 믿는다.
    package static func privateStorageError(
        statusCode: Int,
        data: Data,
        operation: PrivateStorageOperation
    ) -> Error {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let bodyStatus: Int? = {
            if let text = object?["statusCode"] as? String { return Int(text) }
            return object?["statusCode"] as? Int
        }()
        let effective = (statusCode == 400 ? bodyStatus : nil) ?? statusCode
        let text = [object?["error"], object?["message"], object?["code"], object?["msg"]]
            .compactMap { $0 as? String }
            .joined(separator: " ")
            .lowercased()
        let raw = object == nil ? String(decoding: data.prefix(512), as: UTF8.self).lowercased() : text

        if statusCode >= 500 || effective >= 500 { return SupabaseWorkServiceError.invalidResponse(max(statusCode, effective)) }
        if statusCode == 429 || effective == 429 { return SupabaseWorkServiceError.rateLimited(retryAfterSeconds: nil) }
        if raw.contains("invalid api key") { return SupabaseWorkServiceError.invalidAPIKey }
        // ② 만료 토큰 — 문장이 판마다 다르다("jwt expired" · "\"exp\" claim timestamp check failed" · InvalidJWT).
        let jwtWords = raw.contains("jwt") || raw.contains("\"exp\" claim") || raw.contains("exp claim")
            || raw.contains("token is expired") || raw.contains("invalidjwt")
        if jwtWords, [400, 401, 403].contains(effective) || [400, 401, 403].contains(statusCode) {
            return SupabaseWorkServiceError.sessionExpired
        }
        if effective == 401 { return SupabaseWorkServiceError.sessionExpired }
        // ③ 버킷이 없다 = 기능이 아직 안 열렸다.
        if raw.contains("bucket not found") || raw.contains("nosuchbucket") {
            return SupabaseWorkServiceError.databaseSchemaMissing
        }
        // ① 이미 있다 — `exists` 가 들어 있어도 가입 오류로 접지 않는다.
        if effective == 409 || raw.contains("already exists") || raw.contains("duplicate") {
            return PrivateStorageError.alreadyExists
        }
        if effective == 413 || raw.contains("payload too large") || raw.contains("entitytoolarge")
            || raw.contains("maximum allowed size") {
            return PrivateStorageError.tooLarge
        }
        let notFound = effective == 404 || raw.contains("not_found") || raw.contains("not found") || raw.contains("nosuchkey")
        if notFound {
            // 올리기의 404 는 개체 탓일 수 없다 — 버킷(또는 저장소 경로 자체)이 없다.
            return operation == .upload ? SupabaseWorkServiceError.databaseSchemaMissing : PrivateStorageError.objectMissing
        }
        if effective == 403 { return PrivateStorageError.forbidden }
        return SupabaseWorkServiceError.invalidResponse(effective)
    }

    /// 서명 응답 → 받을 URL. 상대 경로(`/object/sign/…`)면 `<projectURL>/storage/v1` 를 앞에 붙인다.
    package static func signedURL(from data: Data, projectURL: URL) -> URL? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        guard let value = (object["signedURL"] as? String) ?? (object["signedUrl"] as? String), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return URL(string: value) }
        var base = projectURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        let tail = value.hasPrefix("/") ? value : "/" + value
        let prefix = tail.hasPrefix("/storage/v1/") ? "" : "/storage/v1"
        return URL(string: base + prefix + tail)
    }
}
