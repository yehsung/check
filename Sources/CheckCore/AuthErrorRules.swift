import Foundation

/// 인증 경로 에러의 **처분**과 **사용자 문구**(순수). D-base(iOS 0.1)에서 맥 스토어(`WorkTimerStoreAuth.swift`)의
/// `classifyAuthError` · `authMessage(for:fallback:)` 본문을 글자 그대로 옮겼다 — 맥 스토어의 두 메서드는 이제 여기를 부르는
/// 한 줄 전달이다. 폰 세션(`MobileSessionStore`)이 같은 판정·같은 문장을 써야 "맥에서는 세션 유지, 폰에서는 강제 로그아웃"
/// 같은 갈림이 생기지 않는다(SPEC-ios §2: 실패 문구는 맥과 같은 매핑 · 치명 오류만 로그아웃).
package enum AuthErrorRules {
    /// 인증 경로 에러 처분. 취소는 아무 상태도 바꾸지 않고, 일시 네트워크 오류는 세션을 유지하며,
    /// 진짜 만료(SupabaseWorkServiceError 등)만 로그아웃 대상이다. .task 취소로 강제 로그아웃되는 회귀를 막는다.
    package static func classify(_ error: Error) -> AuthErrorDisposition {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return .cancelled
        }
        if error is URLError {
            return .transient
        }
        // Supabase 무료플랜 일시정지(5xx)·레이트리밋(429)은 알려진 운영 이슈다. refresh grant 실패로 강제
        // 로그아웃하지 않고 세션을 유지한 채 다음 주기에 재시도한다. 400/401 계열(만료 등)은 fatal 로 남긴다.
        if case let SupabaseWorkServiceError.invalidResponse(code) = error, (500...599).contains(code) || code == 429 {
            return .transient
        }
        // 재설정 경로가 429 를 구조화해 던지는 형태(.rateLimited)도 같은 429 다 — 위 분기와 뜻이 갈리면
        // 같은 상황이 경로에 따라 세션 유지/강제 로그아웃으로 나뉜다.
        if case SupabaseWorkServiceError.rateLimited = error {
            return .transient
        }
        return .fatal
    }

    /// 인증 에러 → 사용자 문구. 서비스 에러가 아니면 fallback.
    package static func message(for error: Error, fallback: String) -> String {
        guard let serviceError = error as? SupabaseWorkServiceError else {
            return fallback
        }

        switch serviceError {
        case .missingAnonKey:
            return "Supabase 키 필요"
        case .invalidAPIKey:
            return "Supabase 키 오류"
        case .sessionExpired:
            return "다시 로그인 필요"
        case .invalidLoginCredentials:
            return "로그인 정보 오류"
        case .emailNotConfirmed:
            return "이메일 확인 필요"
        case .emailAlreadyRegistered:
            return "이미 가입된 이메일"
        case .signupDisabled:
            return "가입 비활성화됨"
        case .weakPassword:
            return "비밀번호 조건 확인"
        case .databaseSchemaMissing:
            return "DB 스키마 필요"
        case .ultraWalletUnavailable:
            // 지갑 RPC 하나만 없는 상태다. 이 문장이 메뉴바에 뜨는 일은 정상 경로에선 없다
            // (performSyncUltraWallet 이 이 오류를 삼키고 ultraBalanceFailed 만 세운다).
            // 그래도 한국어를 돌려주는 이유는 이 매퍼의 계약이다 — 빠뜨리면 다른 경로가 영문 원문을 띄운다.
            return "울트라 기능 준비 중"
        case .sessionAlreadyOpen:
            return "이미 다른 곳에서 근무 중이에요"
        // 아래 셋은 비밀번호 재설정(OTP) 경로가 만들어 낸 분류다. 그 경로는 자체 매퍼
        // (passwordReset*FailureMessage)로 더 구체적인 문장을 쓰지만, 이 공용 매퍼도 **반드시** 한국어를
        // 돌려줘야 한다 — 여기 빠지면 다른 경로가 이 오류를 만났을 때 영문 원문이 메뉴바에 그대로 뜬다.
        case .rateLimited:
            return "잠시 후 다시 시도해주세요"
        case .otpInvalidOrExpired:
            return "코드가 맞지 않거나 만료됐어요"
        case .samePasswordReuse:
            return "이전과 다른 비밀번호로 정해주세요"
        case .authMessage(let message):
            return message
        case .invalidResponse:
            return fallback
        }
    }
}
