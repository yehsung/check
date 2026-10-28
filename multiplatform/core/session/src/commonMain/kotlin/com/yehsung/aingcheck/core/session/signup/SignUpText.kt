// 원본: Sources/CheckMobileKit/Session/MobileSignUpStore.swift:539-640(MobileSignUpText) @ 1b8260d
package com.yehsung.aingcheck.core.session.signup

import com.yehsung.aingcheck.core.session.app.AppLinks
import com.yehsung.aingcheck.core.wire.models.TeamJoinPreview

/**
 * 가입 화면 문구(Swift `MobileSignUpText`). 맥과 뜻이 같은 가드 문구는 **맥 문장 그대로** — 같은 입력에 두 앱이 다른 말을 하면
 * 팀 안내 문서가 한쪽에서 틀린다. 약관 동의 한 줄의 링크 꾸미기(AttributedString)는 화면(W3-a) 몫이다 — 여기는 글자와 주소만.
 */
object SignUpText {
    const val title: String = "가입하기"
    const val subtitleJoin: String = "팀 코드로 합류해요"
    const val subtitleCreate: String = "새 팀을 만들어요"
    const val subtitleTeamless: String = "합류할 팀을 찾아요"
    const val confirmTitle: String = "이메일 인증"
    const val subtitleConfirm: String = "메일로 받은 6자리 코드를 넣어 주세요"
    const val createdTitle: String = "팀이 만들어졌어요"
    const val createdBody: String = "팀원에게 이 코드를 전달하세요"
    const val accountCreatedNotice: String = "계정은 만들어졌어요 · 합류할 팀을 정해 주세요"

    /** 약관 동의 한 줄 — 가입 버튼을 누르는 것이 곧 동의(체크박스를 늘리지 않는다). 두 링크는 글자 안에 심는다(화면 몫). */
    const val termsAgreement: String = "가입하면 이용약관과 개인정보 처리방침에 동의하는 것으로 봅니다"
    const val termsLink: String = "이용약관"
    const val privacyLink: String = "개인정보 처리방침"
    const val termsURL: String = AppLinks.termsOfService

    /** 나 → 설정의 처리방침 링크와 **같은 주소**여야 한다(AppLinks 한 곳). */
    const val privacyURL: String = AppLinks.privacyPolicy

    const val signUp: String = "가입"
    const val createAndStart: String = "팀 만들고 시작하기"
    const val join: String = "참여하기"
    const val start: String = "시작하기"
    const val copy: String = "복사"
    const val copied: String = "복사됨"
    const val noCodePrompt: String = "팀 코드가 없나요?"
    const val switchToCreate: String = "새 팀 만들기"
    const val switchToCode: String = "코드로 참여하기"

    const val displayName: String = "별명"
    const val email: String = "이메일"
    const val password: String = "비밀번호"
    const val centerLabel: String = "소속 센터"
    const val teamCode: String = "팀 코드"
    const val teamName: String = "팀 이름"
    const val weeklyGoal: String = "주간 목표"

    // 가드 문구(맥 signUp() 순서: 입력 셋 → 팀 칸 → 센터).
    const val missingFields: String = "별명, 이메일, 비밀번호를 모두 입력해 주세요"
    const val teamNameRequired: String = "팀 이름을 입력해 주세요"
    const val codeUnverified: String = "팀 코드를 확인해 주세요"
    const val centerRequired: String = "소속 센터를 골라 주세요"

    // 미리보기(맥 performPreviewTeamCode).
    const val previewChecking: String = "확인 중"
    const val previewMiss: String = "코드를 확인해 주세요"

    /** 코드는 맞았는데 합류가 0행일 때 — 맥 `teamlessJoinBlockedMessage` 와 같은 문장(서버 근거는 join_team 의 센터 게이트). */
    const val teamlessJoinBlocked: String = "다른 센터 팀이에요 — 같은 센터 코드인지 확인해 주세요"

    /** 코드 화면의 첫 안내. "메일이 안 와요"의 첫 답은 스팸함이다. */
    const val confirmSent: String = "인증 코드를 보냈어요 · 안 오면 스팸함을 확인해 주세요"

    // INV-MobileSignUpStore-65f4ca6b 이식: 재전송 성공 문구는 **재전송이 앞 코드를 무효화한다**(실측)는 사실을 말한다 — 말하지 않으면
    //   사용자는 첫 메일의 코드를 계속 넣는다.
    const val confirmResent: String = "새 코드를 보냈어요 · 앞 코드는 이제 쓸 수 없어요, 마지막 메일의 코드를 넣어 주세요"

    /** 코드 화면 고정 도움말 — resend 는 이미 인증된 계정에도 빈 200 이라(계정 존재를 흘리지 않는다) 메일이 영영 안 올 수 있다. */
    const val confirmHelp: String = "이미 인증을 마친 계정이면 메일이 오지 않아요 · 그때는 로그인해 주세요"
    const val confirmExit: String = "인증 코드 받기"
    const val verifyCode: String = "코드 확인"
    const val resend: String = "다시 받기"
    const val resendFailed: String = "코드를 보내지 못했어요 · 잠시 뒤 다시 시도해 주세요"

    /** 429(over_email_send_rate_limit)는 오류가 아니라 "몇 초 뒤 다시"다. 앞머리를 상수로 둔 이유: 안내/오류 색 판정이 초가 붙은 문장도 안내로 알아봐야 한다. */
    const val rateLimitedPrefix: String = "조금 뒤에 다시 시도해 주세요"

    fun rateLimited(seconds: Long?): String =
        if (seconds == null || seconds <= 0) rateLimitedPrefix else "$rateLimitedPrefix (${seconds}초)"

    // 실패 폴백(맥 authMessage(for:fallback:) 의 fallback 그대로).
    const val signUpFailed: String = "계정 생성 실패"
    const val createTeamFailed: String = "팀 생성 실패"
    const val joinFailed: String = "합류 실패"

    /** 맥 `TeamCodePreviewSlot` 과 같은 요약. */
    fun previewLine(preview: TeamJoinPreview): String = "팀 ${preview.name} · ${preview.memberCount}명 · 주 ${preview.weeklyGoalHours}시간"

    fun goalHours(hours: Long): String = "${hours}시간"
}
