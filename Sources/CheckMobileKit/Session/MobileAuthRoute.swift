import Foundation

/// 로그인 화면 아래에 쌓이는 화면(w16 — 앱스토어 정식 출시 준비): 가입 · 가입 인증코드 · 비밀번호 재설정.
/// 로그인 뷰의 `NavigationStack` 경로 원소이고, 데모 실행 인자(`-AingCheckDemoRoute signup|signup/create|signup/confirm|reset`)도
/// 이 값으로 연다. 탭 딥링크(`AingRoute`)와 섞지 않는다 — 저쪽은 로그인 **뒤** 화면이고 라우터가 쥔다.
package enum MobileAuthRoute: Hashable, Sendable {
    /// 가입. `createTeam` 이면 팀 만들기 모드로 시작한다(스크린샷용 — 사용자는 항상 코드 입력으로 시작한다, 맥과 같다).
    case signUp(createTeam: Bool)
    /// 미확인 계정의 **출구**(SPEC-signup-otp 작업 P): 가입 화면을 코드 입력 단계로 바로 연다 — 들어가면서 코드를 다시 보낸다.
    /// 가입 도중 앱을 닫은 사람은 계정만 만들어진 채 미확인이라, 로그인하면 "이메일 확인 필요" · 다시 가입하면 "이미 가입된 이메일"이
    /// 뜬다. 그 두 문구에서 이 라우트로 오지 못하면 그 계정은 운영자가 Admin API 로 풀어 주기 전까지 영영 못 쓴다.
    case signUpConfirm(email: String)
    case passwordReset

    /// 데모 실행이 코드 화면을 열 때 쓰는 주소. 이 파일은 릴리스 빌드에도 들어가고 `MobileDemo` 는 DEBUG 전용이라
    /// 거꾸로 참조할 수 없어 값이 여기 산다(`MobileDemo.email` 이 이 상수를 읽는다 — 두 곳에 적지 않는다).
    package static let demoEmail = "demo@aing-check.invalid"

    /// 데모 라우트 → 로그인 아래 화면. `signup` · `signup/create` · `signup/confirm` · `reset`. 그 밖(로그인 자체 · 탭 라우트)은 nil.
    package static func demo(_ raw: String?) -> MobileAuthRoute? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        switch parts.first {
        case "signup":
            guard parts.count >= 2 else { return .signUp(createTeam: false) }
            switch parts[1] {
            case "create": return .signUp(createTeam: true)
            case "confirm": return .signUpConfirm(email: demoEmail)
            default: return .signUp(createTeam: false)
            }
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
