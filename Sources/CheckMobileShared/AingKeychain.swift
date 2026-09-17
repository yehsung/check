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
    /// 로그아웃 때 서버에 다 알리지 못한 정리(unregister_device · logout?scope=local)의 장부(JSON 배열). 옛 세션 토큰이 들어 있어
    /// 공용 suite 가 아니라 키체인에 둔다. **위젯은 읽지 않는다.** 앱이 실행·active·로그인 때 갚고 비운다(`MobileSessionStore`).
    public static let signOutCleanupKey = "aingcheck.session.signOutCleanup"
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
    ///
    /// 키체인이 먼저다(앱을 지웠다 깔아도 남는다). **키체인 저장이 실패하는 빌드**(엔타이틀먼트가 안 실린 서명 없는 시뮬레이터 빌드 —
    /// securityd -34018, dbase-verify 실측)에서는 `fallback`(공용 suite)에 둔다 — 두지 않으면 실행마다 새 id 가 나와
    /// register_device 마다 서버에 기기 행이 하나씩 늘고(사용자당 10대 상한을 밀어낸다) 푸시 설정이 매번 기본값으로 돌아간다.
    /// id 는 비밀이 아니다(무작위 uuid) — 공용 suite 에 두어도 새는 것이 없다.
    public static func current(store: AingSecretStore, fallback: UserDefaults? = nil, makeUUID: () -> UUID = UUID.init) -> String {
        let key = AingKeychain.installationIDKey
        if let existing = store.read(key), let uuid = UUID(uuidString: existing) {
            return uuid.uuidString.lowercased()
        }
        if let fallback, let existing = fallback.string(forKey: key), let uuid = UUID(uuidString: existing) {
            let value = uuid.uuidString.lowercased()
            store.write(value, key: key)   // 키체인이 되살아났으면 그쪽으로 옮긴다(실패해도 이 값을 그대로 쓴다)
            return value
        }
        let fresh = makeUUID().uuidString.lowercased()
        store.write(fresh, key: key)
        if store.read(key) != fresh {
            fallback?.set(fresh, forKey: key)
        }
        return fresh
    }
}
