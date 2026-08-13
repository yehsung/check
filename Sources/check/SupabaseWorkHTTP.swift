import Foundation

extension SupabaseWorkService {
    func sendNoBody<Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Body,
        accessToken: String,
        prefer: String?
    ) async throws {
        _ = try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            body: body,
            accessToken: accessToken,
            prefer: prefer
        )
    }

    func sendData(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data,
        contentType: String,
        accessToken: String,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard let anonKey else {
            throw SupabaseWorkServiceError.missingAnonKey
        }

        var request = URLRequest(url: try url(path: path, queryItems: queryItems))
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw serviceError(statusCode: statusCode, data: data)
        }
        return data
    }

    func send<Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Body?,
        accessToken: String?,
        prefer: String?
    ) async throws -> Data {
        guard let anonKey else {
            throw SupabaseWorkServiceError.missingAnonKey
        }

        var request = URLRequest(url: try url(path: path, queryItems: queryItems))
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw serviceError(statusCode: statusCode, data: data)
        }
        return data
    }

    func serviceError(statusCode: Int, data: Data) -> SupabaseWorkServiceError {
        // Postgres 유니크 위반 코드(23505)는 GoTrue 의 정수 code 와 타입이 섞여 안전하게 디코드할 수 없으므로
        // 원문 본문에서 직접 식별한다(제약명 또는 SQLSTATE). 디코드 성패와 무관하게 우선 판정한다.
        let rawBody = String(decoding: data, as: UTF8.self).lowercased()
        if rawBody.contains("work_sessions_one_open_per_user")
            || rawBody.contains("23505")
            || (rawBody.contains("duplicate key") && rawBody.contains("work_sessions")) {
            return .sessionAlreadyOpen
        }

        guard let response = try? decoder.decode(SupabaseErrorResponse.self, from: data) else {
            return statusCode == 401 ? .sessionExpired : .invalidResponse(statusCode)
        }

        let message = [
            response.message,
            response.msg,
            response.errorDescription,
            response.error
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        let lowercased = [message, response.errorCode]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if lowercased.contains("schema cache") || lowercased.contains("could not find the table") {
            return .databaseSchemaMissing
        }
        if lowercased.contains("invalid api key") {
            return .invalidAPIKey
        }
        if lowercased.contains("jwt expired") || lowercased.contains("pgrst301")
            || (statusCode == 401 && (lowercased.contains("jwt") || lowercased.contains("expired"))) {
            return .sessionExpired
        }
        // 리프레시 토큰 만료/재사용은 "Invalid Refresh Token: Already Used" 로 오는데, 아래 "already" 가드가
        // 이걸 먼저 삼켜 로그인 화면에 "이미 가입된 이메일"로 뜬다(사용자는 계정이 잠긴 줄 안다). 반드시 그 앞에서
        // 세션 만료로 분류한다 — 가입 응답엔 refresh token 문구가 없으므로 중복 가입 분류는 그대로 살아 있다.
        if lowercased.contains("refresh token") || lowercased.contains("refresh_token")
            || lowercased.contains("invalid_grant") {
            return .sessionExpired
        }
        if lowercased.contains("invalid login credentials") {
            return .invalidLoginCredentials
        }
        if lowercased.contains("email not confirmed") || lowercased.contains("email_not_confirmed") {
            return .emailNotConfirmed
        }
        if lowercased.contains("already") || lowercased.contains("registered") || lowercased.contains("exists") {
            return .emailAlreadyRegistered
        }
        if lowercased.contains("signup") && lowercased.contains("disable") {
            return .signupDisabled
        }
        // ★ 아래 "password" 가드보다 **먼저** 걸러야 한다. GoTrue 의 "New password should be different from
        //   the old password." 도 password 를 포함하므로, 순서가 바뀌면 재사용 거절이 통째로 .weakPassword 로
        //   뭉개져 사용자는 "예전과 같은 비밀번호는 안 돼요" 대신 "비밀번호 조건 확인"을 본다(무엇을 고쳐야
        //   하는지 알 수 없는 안내다). 여기서 판정하지 못하면 페이로드가 사라져 사후 복구도 불가능하다.
        if lowercased.contains("different from the old password") || lowercased.contains("same_password") {
            return .samePasswordReuse
        }
        if lowercased.contains("password") {
            return .weakPassword
        }
        if let message {
            return .authMessage(message)
        }
        return .invalidResponse(statusCode)
    }

    func url(path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents(url: projectURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw URLError(.badURL)
        }
        return url
    }
}
