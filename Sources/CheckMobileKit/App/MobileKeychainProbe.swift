#if DEBUG
import CheckMobileShared
import Foundation
import Security

/// 개발 빌드 진단(dbase-fix): **엔타이틀먼트가 안 실린 빌드**를 콘솔 한 줄로 알린다.
///
/// `xcodebuild … CODE_SIGNING_ALLOWED=NO` 로 만든 시뮬레이터 앱에는 `keychain-access-groups`·App Group 이 없다. 그러면 키체인이
/// 전부 -34018(errSecMissingEntitlement)로 실패해 로그인이 실행 사이에 남지 않고, App Group 대신 앱 자신의 폴더로 접혀 위젯과
/// 나누지 못한다 — 화면에는 아무 표시가 없어 실서버 e2e 가 "로그인이 풀린다"로만 보인다. 실서버 e2e 는 서명을 켠 빌드
/// (`ios/scripts/build-sim.sh`)로 한다. Release 에는 컴파일되지 않는다.
enum MobileKeychainProbe {
    static let missingEntitlementWarning = "[AingCheck] 경고: 키체인 엔타이틀먼트가 없는 빌드다(-34018) — 로그인이 실행 사이에 남지 않는다. "
        + "서명 없는 빌드(CODE_SIGNING_ALLOWED=NO)는 데모 모드 전용이다. 실서버 확인은 ios/scripts/build-sim.sh 로 서명을 켜서 빌드하라."
    static let missingAppGroupWarning = "[AingCheck] 경고: App Group 컨테이너가 없다(" + AingAppGroup.identifier
        + ") — 위젯과 데이터를 나누지 못하고 앱 폴더로 접었다."

    static func warnIfEntitlementsMissing(storage: AingSharedStorage) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AingKeychain.service,
            kSecAttrAccessGroup as String: AingKeychain.accessGroup,
            kSecAttrAccount as String: "aingcheck.debug.entitlementProbe",
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecMissingEntitlement {
            NSLog("%@", missingEntitlementWarning)   // 통합 로그에 남는다(simctl spawn … log show 로 보인다)
        }
        if !storage.isAppGroup {
            NSLog("%@", missingAppGroupWarning)
        }
    }
}
#endif
