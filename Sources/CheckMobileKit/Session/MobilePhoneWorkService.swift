import CheckCore
import Foundation

// 폰에서 근무 시작 · 종료 · 생존 신호(0.3.51 / iOS 1.0.7 — 서버 20261014130000_phone_work.sql).
//
// **폰만 부르는 RPC 라 코어가 아니라 여기 둔다**(MobileDeviceService 와 같은 자리 — 맥 바이너리에 실을 이유가 없다).
// 맥의 근무 쓰기(MacOnly 조각: 세션 POST/PATCH · 상태 upsert · 하트비트)는 **하나도 풀지 않는다** — 폰은 서버 RPC 셋만 부른다.
// 본문에 시각·길이를 싣지 않는다: 시작·종료 시각은 서버 now() 하나뿐이다(근무 시간 위조 경로를 폰에 열지 않는다).
// 이름에 맥 메서드 글자를 쓰지 않는다(BaseIsolationContractTests 의 폰 소스 금지 글자 — 시작·종료·하트비트).
//
// 응답 필드는 전부 옵셔널이다(앱이 db push 보다 먼저 나가는 창 · 옛 서버). 함수가 없는 서버(404 PGRST202)는
// `MobileDeviceRPC.isMissingFunction(_:)` 으로 가려 호출부가 '기능 없음'으로 접는다(버튼을 숨긴다).

/// 세션 한 건(`session` · `last`). 시각은 서버 문자열 그대로 — 스토어가 서비스의 `parseDate` 로 읽는다.
package struct PhoneWorkSessionInfo: Decodable, Equatable, Sendable {
    package let id: String?
    package let startedAt: String?
    package let endedAt: String?
    /// "phone"(폰이 연 세션) · "mac"(그 밖 — 맥이 연 세션).
    package let origin: String?
    /// `last` 에만: "manual" · "idle"(확인 알림 뒤 유예가 지나 서버가 소급 마감) · "ended_elsewhere".
    package let reason: String?

    package init(id: String?, startedAt: String?, endedAt: String?, origin: String?, reason: String?) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.origin = origin
        self.reason = reason
    }
}

/// 같은 트랜잭션의 지갑 정산 결과(3시간 랩). 루비 잔액만 읽는다(나머지 키는 맥 지갑 응답과 같은 모양 — 폰은 쓰지 않는다).
package struct PhoneWorkWallet: Decodable, Equatable, Sendable {
    package let rubyBalance: Int?
}

/// `work_phone_start` · `work_phone_stop` · `work_phone_touch` 응답.
package struct PhoneWorkResponse: Decodable, Equatable, Sendable {
    package let status: String?
    package let session: PhoneWorkSessionInfo?
    package let last: PhoneWorkSessionInfo?
    package let serverNow: String?
    package let checkAt: String?
    package let checkAfterSeconds: Int?
    package let graceSeconds: Int?
    package let wallet: PhoneWorkWallet?

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 한 칸의 모양이 틀려도 나머지는 산다(status 만 있으면 판정할 수 있다).
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        session = try? c.decodeIfPresent(PhoneWorkSessionInfo.self, forKey: .session)
        last = try? c.decodeIfPresent(PhoneWorkSessionInfo.self, forKey: .last)
        serverNow = try? c.decodeIfPresent(String.self, forKey: .serverNow)
        checkAt = try? c.decodeIfPresent(String.self, forKey: .checkAt)
        checkAfterSeconds = try? c.decodeIfPresent(Int.self, forKey: .checkAfterSeconds)
        graceSeconds = try? c.decodeIfPresent(Int.self, forKey: .graceSeconds)
        wallet = try? c.decodeIfPresent(PhoneWorkWallet.self, forKey: .wallet)
    }

    private enum CodingKeys: String, CodingKey {
        case status, session, last, serverNow, checkAt, checkAfterSeconds, graceSeconds, wallet
    }
}

/// 응답의 뜻(스토어가 이것으로만 가른다). 모르는 status 는 `.failed` — 지어내지 않는다.
package enum PhoneWorkOutcome: Equatable, Sendable {
    /// 근무 중(시작 ok · 이미 근무 중 · touch ok). `alreadyWorking` = 시작을 눌렀는데 이미 열린 세션이 있었다.
    case working(PhoneWorkSessionInfo, alreadyWorking: Bool)
    /// 종료가 닫았다.
    case stopped(PhoneWorkSessionInfo?)
    /// 근무 중이 아니다(touch · 종료). `last` = 최근 12시간 안에 닫힌 내 폰 세션.
    case notWorking(last: PhoneWorkSessionInfo?)
    /// 종료가 가리킨 세션이 지금 열린 세션이 아니다(그 사이 맥이 닫고 새로 열었다).
    case mismatch
    case noTeam
    case unauthorized
    case failed

    package static func from(_ response: PhoneWorkResponse) -> PhoneWorkOutcome {
        switch response.status {
        case "ok":
            if let session = response.session {
                // 종료 응답은 ended_at 이 찍힌 세션을 싣는다. 시작 · touch 는 열린 세션이다.
                return session.endedAt == nil ? .working(session, alreadyWorking: false) : .stopped(session)
            }
            return .failed
        case "already_working":
            guard let session = response.session else { return .failed }
            return .working(session, alreadyWorking: true)
        case "not_working": return .notWorking(last: response.last)
        case "mismatch": return .mismatch
        case "no_team": return .noTeam
        case "unauthorized": return .unauthorized
        default: return .failed
        }
    }
}

/// 종료 본문. `p_session_id` 는 폰이 보던 세션(없으면 키가 빠진다 → 서버 기본값 null = 지금 열린 세션).
struct PhoneWorkStopRequest: Encodable {
    let pSessionId: String?
}

/// 시작 · 생존 신호 본문 `{}`(인자 없음 — PostgREST 는 본문의 키 집합으로 함수를 고른다).
struct PhoneWorkEmptyRequest: Encodable {}

extension SupabaseWorkService {
    /// 폰 근무 시작. 본문 `{}`(인자 없음 — PostgREST 는 키 집합으로 함수를 고른다).
    package func startPhoneWork(accessToken: String) async throws -> PhoneWorkResponse {
        let data = try await send(
            path: "/rest/v1/rpc/work_phone_start",
            method: "POST",
            body: PhoneWorkEmptyRequest(),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(PhoneWorkResponse.self, from: data)
    }

    /// 폰 근무 종료 — **내 열린 세션**(누가 열었든). 시각은 서버가 정한다.
    package func stopPhoneWork(accessToken: String, sessionID: String?) async throws -> PhoneWorkResponse {
        let data = try await send(
            path: "/rest/v1/rpc/work_phone_stop",
            method: "POST",
            body: PhoneWorkStopRequest(pSessionId: sessionID?.lowercased()),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(PhoneWorkResponse.self, from: data)
    }

    /// 폰 앱 활동 신호(앱이 앞으로 올 때). 폰이 연 세션이면 서버가 확인 대기를 풀고 생존을 민다.
    package func touchPhoneWork(accessToken: String) async throws -> PhoneWorkResponse {
        let data = try await send(
            path: "/rest/v1/rpc/work_phone_touch",
            method: "POST",
            body: PhoneWorkEmptyRequest(),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(PhoneWorkResponse.self, from: data)
    }
}
