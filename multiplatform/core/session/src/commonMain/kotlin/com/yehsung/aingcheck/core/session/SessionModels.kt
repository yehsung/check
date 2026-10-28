// 원본: Sources/CheckMobileKit/Session/MobileSessionStore.swift:1-40·428-439·748-812(단계 · 프로필 · 등록 이유 · 삭제 결과 · 문구) @ 1b8260d
package com.yehsung.aingcheck.core.session

import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform

/** 세션 단계(Swift `MobileSessionPhase`). 셸은 이 값 하나로 로그인·업데이트 필요·탭을 가른다. */
sealed interface SessionPhase {
    /** 실행 직후(client_release · 금고 복원 · 만료 토큰 갱신 중). */
    data object Launching : SessionPhase

    /** 이 빌드가 서버 최소 빌드보다 낮다 — 스토어로 보낸다([com.yehsung.aingcheck.core.session.app.AppLinks.updateDestination]). */
    data class NeedsUpdate(val minBuild: Long) : SessionPhase

    data object SignedOut : SessionPhase

    data object SignedIn : SessionPhase

    /**
     * 단일 실행 가드를 다른 실행이 쥐고 있다 — **세션을 시작하지 않는다**(G §2-3 W2-a ⑦ · C§9-10: 두 실행이면 갱신 주체가 둘이 되어
     * refresh token 회전 경합 → 강제 로그아웃). Windows 몫이다. Android 는 프로세스가 하나라 가드가 늘 잡혀 이 단계가 오지 않는다.
     */
    data object AnotherInstanceRunning : SessionPhase
}

/** 로그인한 사람의 최소 정보(Swift `MobileProfile`). 탭이 더 필요한 것은 각자 읽는다. */
data class SessionProfile(
    val userID: String,
    val email: String?,
    val teamID: String? = null,
    val teamName: String? = null,
    val teamGoalHours: Long? = null,
    val teamRole: String? = null,
)

/** 기기 등록을 부르는 이유(Swift `DeviceRegistrationReason`). 로그인 직후는 스로틀 무시, 포그라운드는 1시간 스로틀, 토큰이 바뀌면 즉시. */
@Suppress("EnumEntryName")
enum class DeviceRegistrationReason { signIn, foreground, pushTokenChanged }

/** 계정 삭제 한 번의 결과(Swift `MobileAccountDeletionOutcome`). 문장은 여기 없다(나 탭 문구가 고른다 — W2-c). */
sealed interface AccountDeletionOutcome {
    /** 서버가 지웠고 이 기기도 비웠다(로그인 화면). */
    data object Deleted : AccountDeletionOutcome

    /** 지우지 않았다 — 로그인 상태 그대로. */
    data class Failed(val reason: AccountDeletionFailure) : AccountDeletionOutcome
}

/** 계정 삭제가 멈춘 이유(Swift `MobileAccountDeletionFailure`). 원문 서버 예외는 싣지 않는다. */
sealed interface AccountDeletionFailure {
    /** 로그인 상태가 아니다(그 사이 로그아웃·치명 만료). */
    data object NotSignedIn : AccountDeletionFailure

    /** 이미 한 번 도는 중(재탭). */
    data object AlreadyRunning : AccountDeletionFailure

    data object PasswordRequired : AccountDeletionFailure

    /** 재인증에 쓸 이메일이 없다(없으면 지어내지 않는다). */
    data object EmailUnknown : AccountDeletionFailure

    /** 재인증 거절 — 비밀번호가 틀렸다. RPC 는 나가지 않았다. */
    data object WrongPassword : AccountDeletionFailure

    /** 재인증이 다른 이유로 거절됐다(맥과 같은 문장 — `AuthErrorRules.message`). RPC 는 나가지 않았다. */
    data class ReauthRejected(val message: String) : AccountDeletionFailure

    /** 네트워크 · 5xx · 429 · 취소. */
    data object Network : AccountDeletionFailure

    /** 서버에 `delete_my_account` 가 아직 없다(앱이 db push 보다 먼저 나간 창). */
    data object ServerNotReady : AccountDeletionFailure

    /** 서버가 거절했다(그 밖의 4xx). */
    data object Rejected : AccountDeletionFailure
}

/** 실시간 선제·강제 갱신의 결과(Swift `Result<String, RealtimeRefreshFailure>`). */
sealed interface RealtimeRefreshResult {
    data class Refreshed(val accessToken: String) : RealtimeRefreshResult

    /**
     * 실패. [fatal] 이면 세션도 이미 만료시켰다. [stale] 이면 갱신을 띄운 세대가 끝났다 — 결과를 어디에도 반영하지 않는다(fatal 도 아니다).
     * 예전 iOS 는 stale 을 fatal 로 돌려줘 새 세션의 소켓을 내렸다(dbase-fix · 검증 V3).
     */
    data class Failed(val fatal: Boolean, val stale: Boolean = false) : RealtimeRefreshResult {
        companion object {
            val Stale: Failed = Failed(fatal = false, stale = true)
        }
    }
}

/**
 * 세션 화면 문구(Swift `MobileSessionText`). 맥·iOS 와 뜻이 같은 것은 같은 글자다. 업데이트 화면만 플랫폼마다 다르다(Android 새 문구).
 */
object SessionText {
    const val missingCredentials: String = "이메일과 비밀번호를 입력해 주세요"
    const val signInFailed: String = "로그인 실패"
    const val signInAgain: String = "다시 로그인 필요"

    /** 탭 공용 연결 안내(Swift `MobileLoadText.checkConnection` 과 같은 글자 — 로그인·가입·재설정·팀 칸이 이 한 곳을 쓴다). */
    const val network: String = "연결을 확인하고 다시 시도해 주세요"

    /** 로그인 화면 맨 아래 두 길. */
    const val signUpPrompt: String = "계정이 없나요?"
    const val signUpAction: String = "가입하기"
    const val forgotPassword: String = "비밀번호를 잊었어요"

    const val updateTitle: String = "새 버전이 필요해요"

    /** Windows: 다른 실행이 이미 있다(단일 실행 가드). */
    const val anotherInstanceRunning: String = "아잉체크가 이미 실행 중이에요"

    /** 업데이트 화면 본문 — iOS "App Store 에서 …" 자리를 플랫폼 스토어로. */
    fun updateBody(platform: ClientPlatform): String = when (platform) {
        ClientPlatform.ANDROID -> "이 버전은 더 이상 서버와 맞지 않아요. Play 스토어에서 최신 버전으로 업데이트해 주세요."
        ClientPlatform.WINDOWS -> "이 버전은 더 이상 서버와 맞지 않아요. 최신 버전을 설치해 주세요."
    }

    /** 업데이트 버튼 글자. 목적지가 없으면(Windows 보류) 버튼도 없다. */
    fun updateButton(platform: ClientPlatform): String? = when (platform) {
        ClientPlatform.ANDROID -> "Play 스토어 열기"
        ClientPlatform.WINDOWS -> null
    }
}
