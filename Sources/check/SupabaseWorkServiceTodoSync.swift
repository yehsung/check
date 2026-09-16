import Foundation

// MARK: - 할 일 동기화 RPC `todo_sync` (v0.3.30 · 계약 1.2)

extension SupabaseWorkService {
    /// `POST /rest/v1/rpc/todo_sync` — 보낼 항목 + 마지막 watermark 를 싣고 서버 응답을 그대로 돌려준다.
    ///
    /// 본문은 `TodoSyncRequest.rpcBody()` 가 만든 **바이트 그대로** 싣는다. 이 서비스의 공용 인코더는
    /// convertToSnakeCase 라 `createdAtMs` 를 `created_at_ms` 로 바꿔 주긴 하지만, 전선 모양의 정본은 전송과 무관한
    /// 한 곳(`TodoSyncWireItem.CodingKeys`)이어야 한다 — psql 왕복 프로브가 같은 바이트로 실제 함수를 부른다.
    ///
    /// HTTP 200 에 `{"status":"unauthorized"}` 가 오는 경우(토큰은 통과했는데 auth.uid() 가 비었다)는 여기서 판정하지
    /// 않는다 — 세션 갱신 경로를 타야 하므로 스토어 쪽 전송(`WorkTimerStoreTodoSyncTransport`)이 가른다.
    /// 함수가 아직 없는 서버는 공용 오류 매핑대로 PGRST202 → `.databaseSchemaMissing`(본문 없는 404 는 `.invalidResponse(404)`).
    func todoSync(accessToken: String, request: TodoSyncRequest) async throws -> TodoSyncResponse {
        let data = try await sendData(
            path: "/rest/v1/rpc/todo_sync",
            method: "POST",
            body: try request.rpcBody(),
            contentType: "application/json",
            accessToken: accessToken
        )
        return try TodoSyncResponse.decode(data)
    }
}
