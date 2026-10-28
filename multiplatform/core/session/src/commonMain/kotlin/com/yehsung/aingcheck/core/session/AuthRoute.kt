// 원본: Sources/CheckMobileKit/Session/MobileAuthRoute.swift @ 1b8260d
package com.yehsung.aingcheck.core.session

/**
 * 로그인 화면 아래에 쌓이는 화면: 가입 · 가입 인증코드 · 비밀번호 재설정(Swift `MobileAuthRoute`). 로그인 화면의 내비게이션 경로 원소이고,
 * 데모·스텁 실행 인자(`signup|signup/create|signup/confirm|reset`)도 이 값으로 연다. 탭 딥링크(`AingRoute`)와 섞지 않는다 —
 * 저쪽은 로그인 **뒤** 화면이고 라우터가 쥔다.
 */
sealed interface AuthRoute {
    /** 가입. [createTeam] 이면 팀 만들기 모드로 시작한다(스크린샷용 — 사용자는 항상 코드 입력으로 시작한다). */
    data class SignUp(val createTeam: Boolean) : AuthRoute

    /**
     * 미확인 계정의 **출구**: 가입 화면을 코드 입력 단계로 바로 연다 — 들어가면서 코드를 다시 보낸다. 가입 도중 앱을 닫은 사람은 계정만
     * 만들어진 채 미확인이라, 이 라우트로 오지 못하면 그 계정은 운영자가 풀어 주기 전까지 영영 못 쓴다.
     */
    data class SignUpConfirm(val email: String) : AuthRoute

    data object PasswordReset : AuthRoute

    companion object {
        /** 데모 실행이 코드 화면을 열 때 쓰는 주소(한 곳에만 적는다). */
        const val demoEmail: String = "demo@aing-check.invalid"

        /** 데모 라우트 → 로그인 아래 화면. 그 밖(로그인 자체 · 탭 라우트)은 null. */
        fun demo(raw: String?): AuthRoute? {
            if (raw == null) return null
            val parts = raw.split("/").map { it.trim().lowercase() }.filter { it.isNotEmpty() }
            return when (parts.firstOrNull()) {
                "signup" -> when (parts.getOrNull(1)) {
                    null -> SignUp(createTeam = false)
                    "create" -> SignUp(createTeam = true)
                    "confirm" -> SignUpConfirm(demoEmail)
                    else -> SignUp(createTeam = false)
                }
                "reset" -> if (parts.size == 1) PasswordReset else null
                else -> null
            }
        }

        /** 로그아웃 상태로 시작하는 데모 라우트인가(`login` · 가입 · 재설정). 데모 조립이 세션을 심을지 여기서 가른다. */
        fun startsSignedOut(raw: String): Boolean = raw.trim().lowercase() == "login" || demo(raw) != null
    }
}
