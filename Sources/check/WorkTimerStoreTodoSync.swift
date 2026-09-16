import AppKit
import Foundation
import CheckCore

// MARK: - 할 일 동기화 ↔ 로그인 세션 (v0.3.30)

/// 프로덕션 전송: 스토어의 세션으로 PostgREST `todo_sync` 를 부른다. 이 저장소의 세션 관용구를 그대로 따른다 —
/// **세션 가드 → 세대 캡처 → `withSessionRetry` → 세대 가드.**
///
/// · 401(JWT 만료)과 HTTP 200 의 `{"status":"unauthorized"}` 는 둘 다 `.sessionExpired` 로 접어 `withSessionRetry` 가
///   refresh 조정자를 거쳐 한 번 갱신·재시도하게 한다(직접 refresh 를 부르면 리얼타임 선제 갱신과 경합한다).
/// · 함수가 없는 서버(PGRST202 → `.databaseSchemaMissing`, 본문 없는 404)는 `.functionMissing` — 엔진이 조용히 멈춘다.
/// · 요청한 계정이 지금 세션이 아니면 **보내지 않는다**(`.accountMismatch`). 계정 전환 틈에 앞 계정의 할 일이
///   새 계정 토큰으로 올라가면 남의 목록에 섞인다.
@MainActor
final class WorkTimerStoreTodoSyncTransport: TodoSyncTransport {
    private weak var store: WorkTimerStore?

    init(store: WorkTimerStore) {
        self.store = store
    }

    func todoSync(userID: String, request: TodoSyncRequest) async throws -> TodoSyncResponse {
        // ① 세션 가드
        guard let store, let current = store.session, current.userID == userID else {
            throw TodoSyncTransportError.accountMismatch
        }
        // ② 세대 캡처
        let generation = store.sessionGeneration
        let service = store.service
        let response: TodoSyncResponse
        do {
            // ③ withSessionRetry
            // 계정 일치는 ①에서 이미 봤다. withSessionRetry 는 같은 틱에 같은 세션을 넘기고, 갱신 뒤 재시도의 세션도
            // 같은 refresh token 에서 나온 **같은 사용자**라 여기서 다시 묻지 않는다(두 번 물으면 한쪽을 지워도 초록이다).
            response = try await store.withSessionRetry { session in
                let reply = try await service.todoSync(accessToken: session.accessToken, request: request)
                if reply.status == "unauthorized" { throw SupabaseWorkServiceError.sessionExpired }
                return reply
            }
        } catch let error as SupabaseWorkServiceError where Self.isFunctionMissing(error) {
            throw TodoSyncTransportError.functionMissing
        }
        // ④ 세대 가드 — 응답을 기다리는 사이 로그아웃·재로그인이 있었으면 이 응답은 앞 세션의 것이다.
        guard generation == store.sessionGeneration else { throw TodoSyncTransportError.accountMismatch }
        return response
    }

    /// 서버에 함수가 아직 없다는 뜻인가. 새 RPC 가 없는 서버에서는 조용히 옛 동작(로컬만)으로 접는다(명세 0.4c).
    nonisolated static func isFunctionMissing(_ error: SupabaseWorkServiceError) -> Bool {
        switch error {
        case .databaseSchemaMissing, .invalidResponse(404):
            return true
        default:
            return false
        }
    }
}

/// 앱 조립 지점. AppDelegate 는 이 함수 하나만 부르고 결과를 붙든다(만드는 자리가 흩어지면 엔진이 둘이 된다 —
/// 두 엔진이 같은 파일을 번갈아 쓰면 한쪽의 pending 이 다른 쪽 저장으로 지워진다).
///
/// 파일 결정자와 깨어남 센터는 **호출자가 넘긴다**(기본값 없음). 기본값을 두면 테스트가 이 함수를 부르는 순간 실제
/// Application Support 의 할 일 파일을 열고 NSWorkspace 통지에 붙는다 — 그래서 아무도 이 조립을 테스트하지 않았고,
/// `start()` 를 지우거나 센터를 빼도 스위트가 초록이었다(a4-verify V4·V5). 프로덕션 값은 AppDelegate 가 적고
/// 소스 계약 테스트가 그 두 인자를 못 박는다(V0330TodoSyncEngineTests).
enum TodoSyncWiring {
    @MainActor
    static func live(
        board: TodoBoardWiring.Board,
        store: WorkTimerStore,
        fileURL: @escaping (String?) -> URL,
        wakeNotifications: NotificationCenter?
    ) -> TodoSyncCoordinator {
        let sync = TodoSync(list: board.list, transport: WorkTimerStoreTodoSyncTransport(store: store))
        let coordinator = TodoSyncCoordinator(
            sync: sync,
            board: board.board,
            userID: { [weak store] in store?.session?.userID },
            fileURL: fileURL,
            wakeNotifications: wakeNotifications
        )
        coordinator.start()
        return coordinator
    }
}
