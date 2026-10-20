import Foundation

// 1:1 대결 RPC 의 **공용 몸통**(v0.3.60) — `/rest/v1/rpc/<name>` POST 한 번 + 교착(40P01) 한 번 재시도.
//
// ── 왜 새로 두는가 ──
// 오목 `gomokuRPC`(SupabaseWorkService.swift)와 체스 `chessRPC`(ChessWire.swift)는 이미 **글자 그대로 두 벌**이고
// 둘 다 `private` 라 다른 파일에서 부를 수 없다. 세 번째 사본을 만들면 "고칠 일이 생기면 세 곳을 같이" 가 되므로,
// 몸통을 `package` 로 한 번 더 두고 **테트리스만** 이것을 쓴다. 오목·체스는 손대지 않는다 — 그쪽 소스 계약을
// 흔들 이유가 없고, 두 함수를 이 위로 옮기는 정리는 별도 작업이다(그때 이 머리말을 고쳐라).
//
// ── 교착 재시도 규약(오목·체스와 같다) ──
// 교착으로 죽은 트랜잭션은 Postgres 가 통째로 되돌리므로(차감·원장·초인종 전부 0) 재시도는 첫 시도와 **같은 요청**이다.
// 그사이 판이 바뀌었으면 서버 가드가 멱등하게 거절한다(stale · not_pending · not_active · already_pending).
// 교착은 상금 cron 의 등수 순 지갑 잠금과 대결의 uuid 순 지갑 잠금이 엇갈릴 때 난다. 재시도는 **한 번뿐**이다 —
// 두 번째도 교착이면 그 오류를 그대로 던진다(무한 재시도는 서버를 더 바쁘게 할 뿐이다).

extension SupabaseWorkService {
    /// 대결 RPC 한 번. 2xx 면 `Response` 로 디코드하고, 아니면 `serviceError` 로 접어 던진다
    /// (PGRST202 → `.databaseSchemaMissing` — 앱이 db push 보다 먼저 나간 창).
    ///
    /// - Parameter retriesDeadlockOnce: 첫 시도가 40P01 이면 한 번 더 보낸다. 쓰기 RPC 와 서버가 판정을 쓰는 조회
    ///   (`tetris_state` — 시간 판정을 돌린다)에 켠다. 읽기 전용(로비·순위)은 끈다 — 실패하면 다음 계기가 다시 읽는다.
    package func duelRPC<Body: Encodable, Response: Decodable>(
        _ name: String, body: Body, accessToken: String, retriesDeadlockOnce: Bool = false
    ) async throws -> Response {
        guard let anonKey else { throw SupabaseWorkServiceError.missingAnonKey }
        var request = URLRequest(url: try url(path: "/rest/v1/rpc/\(name)", queryItems: []))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if 200..<300 ~= statusCode {
                return try decoder.decode(Response.self, from: data)
            }
            if retriesDeadlockOnce, attempt == 1,
               postgrestErrorCode(in: data) == SupabaseWorkService.gomokuDeadlockCode {
                continue
            }
            throw serviceError(statusCode: statusCode, data: data)
        }
    }
}
