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

    /// 사람에게 보이는 앱 이름(홈 화면·설정 앱·스토어). **`CFBundleDisplayName` 과 글자 그대로 같아야 한다** —
    /// 앱이 스스로 이름을 말하는 자리(설정 앱 경로 안내·로그인 머리·버전 줄)가 홈 화면과 갈리면
    /// "설정 앱 › aing-check" 처럼 **없는 곳을 가리키는 안내**가 되고, 심사원은 약관의 서비스명과 앱 이름이 다르면
    /// 같은 서비스인지 묻는다(`docs/terms.md` · `docs/index.md` 도 이 이름을 쓴다).
    /// 번들 ID·brew cask·저장소 이름(`aing-check`)은 식별자라 그대로다 — 바뀌는 것은 **표시 이름**뿐이다.
    public static let appDisplayName = "아잉체크"
}
