import Foundation

/// 로그인 화면 아래에 쌓이는 화면(w16 — 앱스토어 정식 출시 준비): 가입 · 비밀번호 재설정.
/// 로그인 뷰의 `NavigationStack` 경로 원소이고, 데모 실행 인자(`-AingCheckDemoRoute signup|signup/create|reset`)도 이 값으로 연다.
/// 탭 딥링크(`AingRoute`)와 섞지 않는다 — 저쪽은 로그인 **뒤** 화면이고 라우터가 쥔다.
package enum MobileAuthRoute: Hashable, Sendable {
    /// 가입. `createTeam` 이면 팀 만들기 모드로 시작한다(스크린샷용 — 사용자는 항상 코드 입력으로 시작한다, 맥과 같다).
    case signUp(createTeam: Bool)
    case passwordReset

    /// 데모 라우트 → 로그인 아래 화면. `signup` · `signup/create` · `reset`. 그 밖(로그인 자체 · 탭 라우트)은 nil.
    package static func demo(_ raw: String?) -> MobileAuthRoute? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        switch parts.first {
        case "signup":
            return .signUp(createTeam: parts.count >= 2 && parts[1] == "create")
        case "reset":
            return parts.count == 1 ? .passwordReset : nil
        default:
            return nil
        }
    }

    /// 로그아웃 상태로 시작하는 데모 라우트인가(`login` · 가입 · 재설정). 데모 조립이 세션을 심을지 여기서 가른다.
    package static func startsSignedOut(demoRoute raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespaces).lowercased() == "login" || demo(raw) != nil
    }
}
