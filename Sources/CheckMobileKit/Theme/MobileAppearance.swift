import Foundation
import Observation

/// 화면 모드(나 → 설정 → 화면 모드). **기본은 다크다**(사용자 결정 2026-09-18).
///
/// 왜 시스템 따르기가 아닌가: 이 앱의 그림이 어두운 바탕에서 만들어졌다 — 캐릭터 무대·잔디·순위판·오목판이
/// 전부 어두운 배경을 전제로 색을 골랐고, 아이콘도 어두운 바탕이다. 시스템을 따르면 낮에 앱을 처음 연 사람은
/// 우리가 의도하지 않은 밝은 화면을 본다. 고른 적 없는 사람에게 무엇을 보일지의 문제이지 선택지를 줄이는 것이
/// 아니다 — 라이트·시스템 따르기는 설정에 그대로 있다.
///
/// 목록 순서는 `allCases` 다. 기본이 맨 위다(고른 적 없는 사람이 지금 보고 있는 것이 무엇인지 먼저 읽히게).
package enum MobileAppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case system

    package var id: String { rawValue }

    /// 저장값 → 모드. 값이 없거나, 문자열이 아니거나, 모르는 값(다음 버전이 더한 값 · 손상)이면 **기본(다크)**.
    /// 모르는 값을 라이트로 접지 않는 이유: 그 저장값을 쓴 다음 버전이 무엇을 뜻했든, 구버전이 보여 줄 수 있는
    /// 가장 안전한 화면은 우리가 설계한 화면이다.
    package init(storedValue: Any?) {
        guard let raw = storedValue as? String, let mode = MobileAppearanceMode(rawValue: raw) else {
            self = .dark
            return
        }
        self = mode
    }
}

/// 화면 모드 저장소. 계정과 무관한 **이 기기의 설정**이다.
///
/// - 저장: 앱 자신의 `UserDefaults.standard`(프로덕션 — `MobileEnvironment.live()`). App Group 공용 suite 에 두지 않는다:
///   위젯은 이 값을 따르지 않고(홈 화면 모드로 그린다) 읽을 까닭이 없으며, 공용 suite 는 계정 값(userID · 이메일)을 두고 로그아웃이 치우는 곳이다.
/// - 로그아웃 · 세션 만료 · 세대 변경과 무관하다 — 앱 모델의 `reset()` 사슬에 들어가지 않는다. 서버에 올리지 않는다.
/// - 적용: iOS 는 `MobileAppearanceWindows` 가 앱의 모든 창에 `overrideUserInterfaceStyle` 을 건다(로그인 화면 · 시트 · UIKit 으로 띄운 화면 포함).
///   이 파일은 플랫폼 무관(macOS `swift test` 로 저장 · 복원을 잰다).
@MainActor
@Observable
package final class MobileAppearanceStore {
    package nonisolated static let defaultsKey = "aingcheck.appearance.mode"

    package private(set) var mode: MobileAppearanceMode
    @ObservationIgnored private let defaults: UserDefaults
    /// 모드가 바뀔 때마다(같은 값을 다시 골라도 부르지 않는다). iOS 창 적용기가 건다.
    @ObservationIgnored package var onChange: (@MainActor (MobileAppearanceMode) -> Void)?

    package init(defaults: UserDefaults) {
        self.defaults = defaults
        mode = MobileAppearanceMode(storedValue: defaults.object(forKey: Self.defaultsKey))
    }

    /// 고른 모드를 곧바로 저장하고 알린다. 모르는 저장값이 있어도 사용자가 고르면 덮어쓴다(고르기 전에는 지우지 않는다).
    package func select(_ newMode: MobileAppearanceMode) {
        defaults.set(newMode.rawValue, forKey: Self.defaultsKey)
        guard newMode != mode else { return }
        mode = newMode
        onChange?(newMode)
    }
}
