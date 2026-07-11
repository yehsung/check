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
