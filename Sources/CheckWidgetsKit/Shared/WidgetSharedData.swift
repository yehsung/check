import CheckCore
import CheckMobileShared
import Foundation

/// 위젯 확장이 앱과 나눠 보는 것 — **읽기 전용 창구**(D-base 소유 · 위젯 작업자 D8 이 쓴다).
///
/// 규칙(SPEC-ios §4 · R5)
/// - 위젯은 스냅샷(`WidgetSnapshot`)만 그린다. 네트워크는 할 일 체크 인텐트의 `todo_sync` **한 번**뿐이다.
/// - **토큰 갱신은 절대 하지 않는다.** refresh token 을 읽지도 않는다 — 앱 프로세스만 회전시킨다(두 프로세스가 돌리면
///   GoTrue 재사용 감지로 강제 로그아웃). access token 이 60초 이상 유효할 때만 쓰고, 아니면 앱이 다음에 올린다.
package struct WidgetSharedData {
    package let storage: AingSharedStorage
    private let vault: TokenVault
    private let now: () -> Date

    /// 인텐트가 access token 을 쓸 수 있는 최소 남은 시간(초).
    package static let minimumTokenValiditySeconds: TimeInterval = 60

    package init(storage: AingSharedStorage, vault: TokenVault, now: @escaping () -> Date = { Date() }) {
        self.storage = storage
        self.vault = vault
        self.now = now
    }

    /// 위젯 프로세스 조립: App Group + 공유 키체인(앱과 같은 service·group).
    package static func live() -> WidgetSharedData {
        WidgetSharedData(
            storage: .live(),
            vault: KeychainTokenVault(service: AingKeychain.service, accessGroup: AingKeychain.accessGroup)
        )
    }

    /// 앱이 마지막으로 쓴 스냅샷. nil = 로그아웃(또는 아직 한 번도 안 씀) → "앱에서 로그인해 주세요".
    package func snapshot() -> WidgetSnapshot? {
        guard signedInUserID != nil else { return nil }
        return WidgetSnapshotCodec.read(from: storage.widgetSnapshotURL)
    }

    /// 로그인한 사용자 id(앱이 공용 suite 에 적는다). 로그아웃이면 nil.
    package var signedInUserID: String? {
        guard let id = storage.defaults.string(forKey: AingSharedKeys.userID), !id.isEmpty else { return nil }
        return id
    }

    /// 이 사용자의 할 일 파일(`TodoSharedFile.coordinatedUpdate` 로 고친다). 로그아웃이면 nil.
    package var todoFileURL: URL? {
        signedInUserID.map { storage.todoFileURL(userID: $0) }
    }

    /// 지금 바로 쓸 수 있는 access token(만료까지 60초 이상 남았을 때만). exp 를 못 읽으면 nil — 모르면 쓰지 않는다.
    package func usableAccessToken() -> String? {
        guard signedInUserID != nil, let token = vault.read(AingKeychain.accessTokenKey), !token.isEmpty,
              let expiry = JWTClaims.expiry(accessToken: token),
              expiry.timeIntervalSince(now()) >= Self.minimumTokenValiditySeconds
        else { return nil }
        return token
    }
}
