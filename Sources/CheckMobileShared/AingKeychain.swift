import Foundation

/// 폰 앱·위젯의 키체인 설정(SPEC-ios §2). 값은 코어 `KeychainTokenVault(service:accessGroup:)` 에 주입한다 —
/// 이 모듈은 코어를 모른다(위젯·앱 공용의 가장 아래 층이라 의존을 두지 않는다).
///
/// 맥은 service `kingcheck` · 그룹 없음이다. 폰은 **다른 service** 를 쓴다 — 같은 Apple ID 로 iCloud 키체인이
/// 동기화돼도 맥 토큰과 폰 토큰이 섞이지 않게(서로 다른 refresh token 을 돌리는 두 주체가 한 칸을 덮으면 회전 경합이다).
public enum AingKeychain {
    /// generic password 의 service.
    public static let service = "aingcheck-ios"
    /// 앱·위젯 공용 접근 그룹(엔타이틀먼트 `keychain-access-groups` 와 같은 글자).
    public static let accessGroup = CheckMobileIdentifiers.keychainAccessGroup

    /// access token 의 account 이름.
    public static let accessTokenKey = "aingcheck.session.accessToken"
    /// refresh token 의 account 이름. **위젯은 읽기만 하고 절대 쓰지 않는다**(갱신은 앱 프로세스만 — R5).
    public static let refreshTokenKey = "aingcheck.session.refreshToken"
    /// 설치 식별자(`InstallationID`)의 account 이름. 로그아웃해도 지우지 않는다(기기 값).
    public static let installationIDKey = "aingcheck.device.installationID"
}

/// 문자열 비밀 금고의 최소 계약. 코어 `TokenVault` 와 모양이 같다 — 앱 모듈이 `KeychainTokenVault` 를 여기에 적합시킨다.
/// (이 모듈이 코어에 의존하지 않으려고 따로 둔다.)
public protocol AingSecretStore: AnyObject {
    func read(_ key: String) -> String?
    func write(_ value: String, key: String)
    func delete(_ key: String)
}

/// 앱 설치마다 하나인 식별자(`register_device(p_installation_id)`). 키체인에 없으면 만든다.
public enum InstallationID {
    /// 있으면 그 값, 없거나 UUID 모양이 아니면 새 UUID(소문자)를 만들어 저장하고 돌려준다.
    /// 저장이 실패해도 이번 실행에는 같은 값을 돌려준다 — 다음 실행에 새 값이 나오면 서버에 기기 행이 하나 더 생길 뿐이다
    /// (서버가 사용자당 10대를 넘으면 오래된 것부터 지운다).
    public static func current(store: AingSecretStore, makeUUID: () -> UUID = UUID.init) -> String {
        if let existing = store.read(AingKeychain.installationIDKey), let uuid = UUID(uuidString: existing) {
            return uuid.uuidString.lowercased()
        }
        let fresh = makeUUID().uuidString.lowercased()
        store.write(fresh, key: AingKeychain.installationIDKey)
        return fresh
    }
}
