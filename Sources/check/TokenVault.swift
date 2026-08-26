import Foundation
import Security

/// access/refresh 토큰의 보관 계약. v0.2.36 까지 토큰이 UserDefaults 평문
/// (~/Library/Preferences/kingcheck.plist)에 남아 같은 맥의 비샌드박스 프로세스·Time Machine 백업·
/// 공용 맥에서 refresh token 만 집어 가면 영구 계정 탈취가 가능했다(전면 감사 P0). v0.2.37 부터
/// 비밀값(access/refresh 토큰)은 이 계약 뒤의 금고로만 드나든다 — userID/email 같은 비밀 아닌 값은
/// 여전히 defaults 에 남는다(WorkTimerStore.persistSession).
///
/// 에러 규약: **삼킨다**(throw 없음 — 토큰 저장 실패로 앱을 죽이지 않는다). 대신 write 가 실패한 키는
/// read 가 반드시 nil 을 돌려준다 — 실패를 삼키고 **낡은 토큰**을 돌려주면 회전 전의 refresh token 으로
/// grant 를 치게 되고, GoTrue reuse-detection 이 근무 중 강제 로그아웃을 만든다. '없다'는 재로그인
/// 화면으로 이어질 뿐이지만 '낡았다'는 사고로 이어진다.
protocol TokenVault {
    func read(_ key: String) -> String?
    func write(_ value: String, key: String)
    func delete(_ key: String)
}

/// 프로덕션 금고: macOS 로그인 키체인의 generic password(service "kingcheck", account = 키 이름).
///
/// 파일 키체인(로그인 키체인)을 쓰고 **kSecUseDataProtectionKeychain 은 절대 켜지 않는다** — 이 앱은
/// Developer ID 서명에 entitlements 파일이 없어(scripts/package-notarized.sh) data protection 키체인이
/// errSecMissingEntitlement(-34018)로 거절된다(이 맥에서 실측). 켜는 순간 38명 전원이 재시작마다
/// 로그아웃된다. kSecAttrAccessibleAfterFirstUnlock 은 add 속성에 함께 넣는다 — 파일 키체인 add 에서
/// 에러 없이 수용됨을 같은 프로브로 실측했고(status 0 + 왕복 성공), 항목이 언젠가 data protection
/// 키체인으로 옮겨질 때의 접근 등급 의도를 지금 남겨 둔다.
///
/// 단위테스트는 이 타입을 절대 만들지 않는다(서명 안 된 테스트 러너가 실제 키체인을 오염시킨다) —
/// 테스트 프로세스의 기본 금고 선택은 WorkTimerStore.defaultTokenVault 가 한다.
final class KeychainTokenVault: TokenVault {
    private let service: String

    init(service: String = "kingcheck") {
        self.service = service
    }

    /// 세 연산이 공유하는 식별 쿼리. 식별을 한곳에 두어 read 가 찾는 항목과 write 가 만드는 항목이
    /// 어긋나지 않게 한다(service/account 가 한 글자라도 갈리면 '저장은 되는데 복원이 안 되는' 금고가 된다).
    private func identity(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func read(_ key: String) -> String? {
        var query = identity(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, key: String) {
        let data = Data(value.utf8)
        // 업데이트 우선, 없으면(errSecItemNotFound, 이 맥 실측 -25300) add 폴백. add 를 먼저 치면
        // 기존 항목에서 errSecDuplicateItem 이 나 매 회전마다 삭제-재생성을 하게 된다.
        let updateStatus = SecItemUpdate(
            identity(key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var attributes = identity(key)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess { return }
        }
        // 실패는 삼키되 계약을 지킨다: 낡은 값이 남아 있으면 read 가 회전 전 토큰을 돌려주므로 지운다
        // (write 실패 ⇒ read nil). 프로토콜 주석의 '없다 > 낡았다' 규약이 이 한 줄의 근거다.
        SecItemDelete(identity(key) as CFDictionary)
    }

    func delete(_ key: String) {
        // errSecItemNotFound 포함 모든 결과를 무시한다 — 삭제는 멱등이어야 한다
        // (clearPersistedSession 이 강제 로그아웃 경로에서 몇 번이고 탈 수 있다).
        SecItemDelete(identity(key) as CFDictionary)
    }
}

/// 테스트용 금고. 실제 키체인을 건드리지 않고 계약(왕복/삭제/write 실패 ⇒ read nil)을 그대로 흉내 낸다.
final class InMemoryTokenVault: TokenVault {
    private var storage: [String: String] = [:]
    /// true 면 write 가 키체인 고장 환경처럼 행동한다: 값이 저장되지 않고, 그 키의 기존 값도 지워진다
    /// (KeychainTokenVault.write 의 실패 분기와 같은 계약 — 낡은 토큰을 돌려주지 않는다).
    var failsWrites = false

    func read(_ key: String) -> String? {
        storage[key]
    }

    func write(_ value: String, key: String) {
        guard !failsWrites else {
            storage[key] = nil
            return
        }
        storage[key] = value
    }

    func delete(_ key: String) {
        storage[key] = nil
    }
}

/// 레거시 호환 금고: 토큰을 v0.2.36 이하와 **똑같이** 주입받은 defaults 에 둔다.
///
/// **테스트 프로세스 전용이다.** 존재 이유: 이 저장소의 기존 스위트(LaunchActivationTests·
/// WorkTimerStoreTests 등)는 defaults 에 토큰을 시딩하고 **defaults 에서 토큰을 단언**하는 계약으로
/// 굳어 있고, 그 파일들은 이번 작업에서 손댈 수 없다. 테스트 기본 금고를 InMemory 로 두면 그 단언들이
/// 전부 빨개지고, Keychain 으로 두면 서명 안 된 테스트 러너가 실제 로그인 키체인을 오염시킨다.
/// 이 금고는 두 함정을 모두 피하면서 기존 계약을 바이트 단위로 보존한다(같은 키, 같은 defaults).
///
/// 프로덕션이 이 금고를 잡는 일은 없다 — 선택 지점은 WorkTimerStore.defaultTokenVault 한 곳뿐이고,
/// 그 분기는 CheckPanelVisibility.isRunningTests(테스트 번들 로드 여부, 프로덕션에서 상시 false — 그 파일
/// 주석의 실측 근거 참조)로만 갈린다. V0237KeychainTests 의 소스 계약 테스트가 이 사실을 되묻는다.
final class UserDefaultsTokenVault: TokenVault {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func read(_ key: String) -> String? {
        defaults.string(forKey: key)
    }

    func write(_ value: String, key: String) {
        defaults.set(value, forKey: key)
    }

    func delete(_ key: String) {
        defaults.removeObject(forKey: key)
    }
}
