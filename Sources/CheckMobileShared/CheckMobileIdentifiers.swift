import Foundation

/// 폰 앱과 위젯 확장이 함께 쓰는 식별자(D1 골격 — SPEC-ios §1 `CheckMobileShared`).
///
/// 이 모듈은 플랫폼 무관(Foundation 만)이라 macOS 에서도 빌드된다. App Group 경로 · 키체인 설정 · 위젯 스냅샷 모델 ·
/// 할 일 파일 위치 · 기기 식별자는 D2~D8 에서 여기에 더한다.
/// 값은 `ios/project.yml` 의 번들·엔타이틀먼트와 **글자 그대로 같아야 한다**(다르면 위젯이 앱의 파일·토큰을 못 읽는다).
public enum CheckMobileIdentifiers {
    /// 앱 번들 ID.
    public static let appBundleID = "com.yehsung.aingcheck"
    /// 위젯 확장 번들 ID.
    public static let widgetsBundleID = "com.yehsung.aingcheck.widgets"
    /// 앱·위젯 공용 컨테이너(스냅샷·할 일 파일).
    public static let appGroupID = "group.com.yehsung.aingcheck"
    /// 앱·위젯 공용 키체인 그룹(팀 접두어 포함 — `keychain-access-groups` 엔타이틀먼트 값).
    public static let keychainAccessGroup = "MQ2KQK37WD.com.yehsung.aingcheck.shared"
}
