import Foundation

/// Production uses the existing session recovery and shared duel RPC implementation.
@MainActor
private final class AlkkagiLiveService: AlkkagiServing {
    private weak var host: (any GomokuStoreHost)?
    private weak var store: AlkkagiOnlineStore?

    init(host: any GomokuStoreHost, store: AlkkagiOnlineStore) {
        self.host = host
        self.store = store
    }

    func call(_ call: AlkkagiCall) async throws -> AlkkagiResponse {
        guard let host, let store, let userID = host.session?.userID else {
            throw AlkkagiServiceError.unavailable
        }
        let sessionGeneration = host.sessionGeneration
        let resetGeneration = store.resetGeneration
        let service = host.service
        let parameters = call.parameters
        do {
            let response: AlkkagiResponse = try await host.withSessionRetry { session in
                guard host.sessionGeneration == sessionGeneration, session.userID == userID,
                      store.resetGeneration == resetGeneration, !Task.isCancelled else {
                    throw CancellationError()
                }
                return try await service.duelRPC(call.rpcName, body: parameters,
                                                 accessToken: session.accessToken,
                                                 retriesDeadlockOnce: true)
            }
            guard host.sessionGeneration == sessionGeneration, host.session?.userID == userID,
                  store.resetGeneration == resetGeneration, !Task.isCancelled else {
                throw CancellationError()
            }
            return response
        } catch {
            guard host.sessionGeneration == sessionGeneration, host.session?.userID == userID,
                  store.resetGeneration == resetGeneration, !Task.isCancelled else {
                throw CancellationError()
            }
            if (error as? SupabaseWorkServiceError) == .databaseSchemaMissing {
                throw AlkkagiServiceError.serverMissing
            }
            if case .cancelled = host.classifyAuthError(error) { throw CancellationError() }
            if (error as? SupabaseWorkServiceError) == .sessionExpired {
                throw AlkkagiServiceError.notSignedIn
            }
            throw error
        }
    }
}

extension AlkkagiOnlineStore {
    package func attach(host: any GomokuStoreHost) {
        reset()
        service = AlkkagiLiveService(host: host, store: self)
    }
}
