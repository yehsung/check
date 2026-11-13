import Foundation
import AlkkagiCore

/// Only generated local preview bundles carry this configuration. It contains fixture accounts.
struct AlkkagiPreviewConfiguration: Decodable {
    let baseURL: URL
    let accessToken: String
    let title: String

    static func load() -> Self? {
        guard let url = Bundle.main.url(forResource: "AlkkagiOnlinePreview", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(Self.self, from: data),
              configuration.baseURL.host == "127.0.0.1" || configuration.baseURL.host == "localhost" else { return nil }
        return configuration
    }
}

@MainActor
final class AlkkagiPreviewService: AlkkagiServing {
    private let configuration: AlkkagiPreviewConfiguration
    init(configuration: AlkkagiPreviewConfiguration) { self.configuration = configuration }

    func call(_ call: AlkkagiCall) async throws -> AlkkagiResponse {
        let url = configuration.baseURL.appendingPathComponent("rpc").appendingPathComponent(call.rpcName)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(configuration.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(call.parameters)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AlkkagiServiceError.unavailable }
        if response.statusCode == 404 { throw AlkkagiServiceError.serverMissing }
        guard (200..<300).contains(response.statusCode) else { throw AlkkagiServiceError.unavailable }
        return try JSONDecoder().decode(AlkkagiResponse.self, from: data)
    }
}
