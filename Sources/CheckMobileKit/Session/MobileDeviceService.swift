import CheckCore
import Foundation

// 폰 전용 서버 호출(서버 계약 W1/SPEC.md §1.4). **폰만 부르는 RPC 라 코어가 아니라 여기 둔다** —
// 맥 바이너리에 register_device 경로가 실릴 이유가 없다. 같은 패키지라 서비스의 package 헬퍼(send)를 그대로 쓴다.
//
// 응답 필드는 전부 옵셔널이다(앱이 먼저 나가고 db push 가 늦은 창 · 옛 서버). 함수가 없는 서버(404 PGRST202 →
// `.databaseSchemaMissing`)는 호출부가 조용히 접는다 — `MobileDeviceRPC.isMissingFunction(_:)`.

/// `client_release(p_platform)` 응답. anon 으로 부른다(로그인 전 확인).
package struct ClientReleaseResponse: Decodable, Equatable, Sendable {
    package let status: String?
    package let platform: String?
    package let minBuild: Int?
    package let latestBuild: Int?
    package let notes: String?

    package init(status: String?, platform: String?, minBuild: Int?, latestBuild: Int?, notes: String?) {
        self.status = status
        self.platform = platform
        self.minBuild = minBuild
        self.latestBuild = latestBuild
        self.notes = notes
    }
}

/// `register_device` · `set_push_prefs` 가 돌려주는 알림 종류별 켜짐. 모르는 키는 무시, 없는 키는 켜짐(서버 기본값).
package struct PushPrefs: Codable, Equatable, Sendable {
    package var message: Bool
    package var gomokuInvite: Bool
    package var feedbackReply: Bool

    package init(message: Bool = true, gomokuInvite: Bool = true, feedbackReply: Bool = true) {
        self.message = message
        self.gomokuInvite = gomokuInvite
        self.feedbackReply = feedbackReply
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = (try? c.decodeIfPresent(Bool.self, forKey: .message)) ?? true
        gomokuInvite = (try? c.decodeIfPresent(Bool.self, forKey: .gomokuInvite)) ?? true
        feedbackReply = (try? c.decodeIfPresent(Bool.self, forKey: .feedbackReply)) ?? true
    }
}

package struct RegisterDeviceResponse: Decodable, Equatable, Sendable {
    package let status: String?
    package let deviceId: String?
    package let pushPrefs: PushPrefs?
}

package struct UnregisterDeviceResponse: Decodable, Equatable, Sendable {
    package let status: String?
    package let removed: Bool?
}

package struct SetPushPrefsResponse: Decodable, Equatable, Sendable {
    package let status: String?
    package let pushPrefs: PushPrefs?
}

/// register_device 본문. nil 인 칸은 키가 빠진다(합성 Encodable) → 서버 기본값 null — **토큰이 nil 이면 서버가 기존 토큰을 유지한다.**
struct RegisterDeviceRequest: Encodable {
    let pInstallationId: String
    let pPlatform: String
    let pAppBuild: Int
    let pAppVersion: String?
    let pApnsToken: String?
    let pApnsEnv: String?
}

struct InstallationRequest: Encodable {
    let pInstallationId: String
}

struct SetPushPrefsRequest: Encodable {
    let pInstallationId: String
    let pPrefs: PushPrefs
}

struct ClientReleaseRequest: Encodable {
    let pPlatform: String
}

package enum MobileDeviceRPC {
    /// 폰 플랫폼 이름(서버 check 제약 어휘와 같은 글자).
    package static let platform = "ios"

    /// 함수가 없는 서버(마이그레이션 미적용)인가. 그때는 조용히 옛 동작(등록 없음·업데이트 검사 없음)으로 접는다.
    package static func isMissingFunction(_ error: Error) -> Bool {
        guard let serviceError = error as? SupabaseWorkServiceError else { return false }
        switch serviceError {
        case .databaseSchemaMissing, .invalidResponse(404):
            return true
        default:
            return false
        }
    }
}

extension SupabaseWorkService {
    /// 폰 최소·최신 빌드. anon Bearer.
    package func fetchClientRelease(platform: String = MobileDeviceRPC.platform) async throws -> ClientReleaseResponse {
        let data = try await send(
            path: "/rest/v1/rpc/client_release",
            method: "POST",
            body: ClientReleaseRequest(pPlatform: platform),
            accessToken: nil,
            prefer: nil
        )
        return try decoder.decode(ClientReleaseResponse.self, from: data)
    }

    /// 기기 등록(설치마다 한 행 upsert). **profiles.app_build 를 쓰지 않는다** — 서버가 단언한다(계약 1.4).
    package func registerDevice(
        accessToken: String,
        installationID: String,
        appBuild: Int,
        appVersion: String?,
        apnsToken: String?,
        apnsEnvironment: String?
    ) async throws -> RegisterDeviceResponse {
        let data = try await send(
            path: "/rest/v1/rpc/register_device",
            method: "POST",
            body: RegisterDeviceRequest(
                pInstallationId: installationID,
                pPlatform: MobileDeviceRPC.platform,
                pAppBuild: appBuild,
                pAppVersion: appVersion,
                // 토큰과 환경은 **함께** 싣거나 함께 뺀다(서버 제약: 둘 다 null 이거나 둘 다 값).
                pApnsToken: apnsEnvironment == nil ? nil : apnsToken,
                pApnsEnv: apnsToken == nil ? nil : apnsEnvironment
            ),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(RegisterDeviceResponse.self, from: data)
    }

    /// 이 설치의 기기 행 삭제(로그아웃 · 알림 끄기).
    package func unregisterDevice(accessToken: String, installationID: String) async throws -> UnregisterDeviceResponse {
        let data = try await send(
            path: "/rest/v1/rpc/unregister_device",
            method: "POST",
            body: InstallationRequest(pInstallationId: installationID),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(UnregisterDeviceResponse.self, from: data)
    }

    /// 알림 종류별 켜기·끄기(아는 키의 boolean 만 병합 — 서버). 행이 없으면 status "not_found".
    package func setPushPrefs(accessToken: String, installationID: String, prefs: PushPrefs) async throws -> SetPushPrefsResponse {
        let data = try await send(
            path: "/rest/v1/rpc/set_push_prefs",
            method: "POST",
            body: SetPushPrefsRequest(pInstallationId: installationID, pPrefs: prefs),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(SetPushPrefsResponse.self, from: data)
    }
}
