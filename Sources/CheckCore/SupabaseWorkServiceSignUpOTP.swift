import Foundation

// MARK: - 가입 이메일 인증코드 (맥·폰 공용 — OS 게이트 없음)
//
// 비밀번호 재설정 OTP(SupabaseWorkService.swift 끝의 확장)와 **같은 모양**으로 만든다. verify 는 같은 엔드포인트에
// `type` 만 "signup" 이고 응답은 로그인과 같은 모양이라 SignInResponse 를 그대로 쓴다. 오류 재분류도 같은
// `passwordRecoveryError` 를 지난다 — 실측한 거절 본문(otp_expired · rate limit · bad_jwt)이 두 흐름에서 글자 그대로 같고,
// 재분류를 한 벌 더 두면 문구가 갈리는 날이 온다.
//
// **왜 코드인가**(SPEC-signup-otp, 2026-09-18 프로덕션 실측): 확인 메일의 링크는 `check://auth` 로 리다이렉트되는데
// 그 스킴을 등록한 앱이 없어 죽은 링크다 — 비밀번호 재설정이 OTP 로 간 이유와 같다.
//
// **두 서버 모드**: 지금 서버(`enable_confirmations = false`)는 가입 즉시 세션을 주므로 이 파일의 두 함수는 불리지 않는다.
// 설정을 켠 뒤에는 `signUp` 이 nil 을 돌려주고, **그때만** 스토어가 이 파일을 탄다. 서버 상태를 따로 묻지 않는다 — nil 이 신호다.
extension SupabaseWorkService {
    /// 가입 확인 6자리 코드를 검증하고 **로그인 세션**을 받는다. 이 세션은 일반 로그인과 같은 JWT 라 스토어가 그대로
    /// 팀 합류/만들기를 이어 간다(재설정의 recovery 세션과 달리 영속해도 된다 — 사용자가 가입을 마친 것이다).
    ///
    /// 틀린 코드·만료·이미 인증된 계정의 코드는 전부 같은 403 otp_expired 로 온다(재설정과 같은 실측 — GoTrue 는
    /// 계정/코드 존재를 흘리지 않는다). 그래서 스토어 문구도 하나다.
    package func verifySignUpCode(email: String, code: String) async throws -> SupabaseSession {
        do {
            let data = try await send(
                path: "/auth/v1/verify",
                method: "POST",
                body: VerifyOTPRequest(email: email, token: code, type: "signup"),
                accessToken: nil,
                prefer: nil
            )
            let response = try decoder.decode(SignInResponse.self, from: data)
            return SupabaseSession(
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                userID: response.user.id
            )
        } catch let error as SupabaseWorkServiceError {
            throw Self.passwordRecoveryError(error)
        }
    }

    /// 가입 확인 코드를 **다시** 보낸다(`POST /auth/v1/resend`, type signup). 첫 메일은 가입 요청 자체가 보낸다.
    ///
    /// **조용히 200 인 경우가 둘 있다**: 계정이 없을 때, 그리고 **이미 인증된 계정**일 때(GoTrue 가 존재 여부를 흘리지
    /// 않으려고 둘 다 빈 200 이다). 설정이 꺼진 지금 서버에서는 모든 계정이 인증된 상태라 이 요청은 늘 200 이고 메일은
    /// 가지 않는다 — 그러니 성공을 "메일이 갔다"로 단정하는 문구를 쓰면 안 된다(스토어 문구가 그 점을 말한다).
    /// 429(발송 간격)는 공용 매핑이 `.rateLimited(남은 초)` 로 접고, 그 밖의 거절은 재설정과 같은 재분류를 지난다.
    package func resendSignUpCode(email: String) async throws {
        do {
            _ = try await send(
                path: "/auth/v1/resend",
                method: "POST",
                body: ResendOTPRequest(type: "signup", email: email),
                accessToken: nil,
                prefer: nil
            )
        } catch let error as SupabaseWorkServiceError {
            throw Self.passwordRecoveryError(error)
        }
    }
}

/// POST /auth/v1/resend 본문. 필드명이 모두 한 단어라 convertToSnakeCase 로도 type/email 그대로 나간다.
/// SupabaseWorkModels.swift 가 아니라 여기 두는 이유: 이 요청은 이 파일의 함수 하나만 쓰고, 모델 파일은 여러 갈래가
/// 동시에 고치는 파일이라 줄을 더하지 않는다(병합 충돌 최소화).
package struct ResendOTPRequest: Encodable {
    package let type: String
    package let email: String
}
