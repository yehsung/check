import CheckCore
import CheckMobileShared
import Foundation

/// 로그아웃 때 서버에 다 알리지 못한 정리 한 건(dbase-fix · 검증 V2).
///
/// 왜 남기는가: 서버 `client_devices` 행은 `unregister_device` 로만 지워진다. 만료된 access token(401)이나 오프라인으로 로그아웃하면
/// 행이 APNs 토큰을 든 채 남아, **로그아웃한 폰의 잠금 화면에 앞 계정의 메시지(보낸 사람·본문)가 계속 뜬다**
/// (push_pipeline: 제목 = 보낸 사람 display_name, 본문 = 메시지). 다른 계정이 같은 폰에서 토큰을 다시 등록하기 전에는 서버가 스스로
/// 비우지 않는다(register_device 의 토큰 이동). 그래서 못 한 정리를 옛 세션 토큰과 함께 키체인 장부에 적어 두고, 앱이 네트워크를 가질
/// 기회(실행 · active · 로그인)마다 갚는다.
package struct MobileSignOutCleanup: Codable, Equatable, Sendable {
    package var id: String
    package var userID: String
    package var accessToken: String
    package var refreshToken: String?
    /// unregister_device 를 마쳤다(또는 할 필요가 없다) — 남은 일은 logout?scope=local 뿐.
    package var deviceUnregistered: Bool
    package var createdAt: Date

    package init(id: String = UUID().uuidString.lowercased(), userID: String, accessToken: String, refreshToken: String?,
                 deviceUnregistered: Bool = false, createdAt: Date) {
        self.id = id
        self.userID = userID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.deviceUnregistered = deviceUnregistered
        self.createdAt = createdAt
    }
}

/// 정리 장부(키체인 한 칸의 JSON 배열). 토큰이 들어 있어 공용 suite 에 두지 않는다. 위젯은 이 칸을 읽지 않는다.
package enum MobileSignOutCleanupLedger {
    /// 장부 상한. 넘으면 오래된 것부터 버린다(오프라인 로그아웃이 쌓여도 키체인 한 칸이 끝없이 크지 않게).
    package static let maxEntries = 8
    /// 이보다 오래된 정리는 버린다 — 그 사이 서버가 사용자당 10대 상한·토큰 이동으로 행을 치웠을 가능성이 크고,
    /// 몇 주 묵은 refresh token 으로 계속 두드릴 이유가 없다.
    package static let maxAgeSeconds: TimeInterval = 30 * 86_400

    package static func load(_ vault: TokenVault) -> [MobileSignOutCleanup] {
        guard let text = vault.read(AingKeychain.signOutCleanupKey), let data = text.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([MobileSignOutCleanup].self, from: data)) ?? []
    }

    package static func save(_ entries: [MobileSignOutCleanup], to vault: TokenVault) {
        let kept = Array(entries.suffix(maxEntries))
        guard !kept.isEmpty else {
            vault.delete(AingKeychain.signOutCleanupKey)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(kept), let text = String(data: data, encoding: .utf8) else { return }
        vault.write(text, key: AingKeychain.signOutCleanupKey)
    }

    /// 장부를 읽어 고치고 다시 쓴다(늘 새로 읽는다 — 정리 도중 로그아웃이 새 줄을 더했을 수 있다).
    package static func update(_ vault: TokenVault, _ body: (inout [MobileSignOutCleanup]) -> Void) {
        var entries = load(vault)
        body(&entries)
        save(entries, to: vault)
    }
}

/// 정리 한 건을 한 번 시도한 결과.
package enum MobileSignOutCleanupOutcome: Equatable, Sendable {
    /// 끝났다(서버에 알렸거나 · 더 알릴 방법이 없다) — 장부에서 뺀다.
    case settled
    /// 일시 실패(네트워크 · 5xx · 429) — 고친 상태(회전한 토큰 · 끝난 단계)로 남기고, 이번 차례의 나머지도 멈춘다.
    case retryLater(MobileSignOutCleanup)
}

extension SupabaseWorkService {
    /// `POST /auth/v1/logout?scope=local` — **실패를 던지는** 판(코어 `signOut(accessToken:)` 은 삼킨다). 정리 장부가
    /// "일시 실패면 다음에 다시"를 가르려면 결과를 봐야 한다. scope=local 이라 이 세션만 끊고 맥 세션은 그대로다.
    package func logoutLocalScope(accessToken: String) async throws {
        _ = try await send(
            path: "/auth/v1/logout",
            method: "POST",
            queryItems: [URLQueryItem(name: "scope", value: "local")],
            body: Optional<EmptyBody>.none,
            accessToken: accessToken,
            prefer: nil
        )
    }
}
