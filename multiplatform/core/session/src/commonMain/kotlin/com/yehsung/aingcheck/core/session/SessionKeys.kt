// 원본: Sources/CheckMobileShared/AingKeychain.swift · Sources/CheckMobileShared/AingAppGroup.swift:84-102(AingSharedKeys) @ 1b8260d
package com.yehsung.aingcheck.core.session

/**
 * 금고([com.yehsung.aingcheck.core.foundation.platform.TokenVault])에 두는 칸 — 비밀(토큰)만. Swift `AingKeychain` 의 account 이름과
 * 같은 글자다(기기마다 따로 저장되므로 값이 섞일 일은 없지만, 이름을 맞춰 두면 두 앱의 진단 기록이 같은 말을 한다).
 *
 * 설치 식별자는 여기 없다 — foundation `InstallationIdentity`(Android: 백업 제외 파일, Windows: UUIDv5 재계산)가 쥔다(C§4 #41).
 */
object SessionVaultKeys {
    const val accessToken: String = "aingcheck.session.accessToken"

    /** refresh token. 갱신 주체는 앱 프로세스의 세션 스토어 하나다(위젯·백그라운드 작업은 읽기만 — C§4 #4). */
    const val refreshToken: String = "aingcheck.session.refreshToken"

    /** 로그아웃 때 서버에 다 알리지 못한 정리의 장부(JSON 배열 — 옛 세션 토큰이 들어 있어 금고에 둔다). */
    const val signOutCleanup: String = "aingcheck.session.signOutCleanup"
}

/** 비밀 아닌 설정([com.yehsung.aingcheck.core.foundation.platform.KeyValueStore])에 두는 칸(Swift `AingSharedKeys`). */
object SessionPrefsKeys {
    /** 로그인한 사용자 id. 위젯이 할 일 파일을 고를 때 읽는다. */
    const val userID: String = "aingcheck.session.userID"

    /** 로그인 이메일(만료 뒤 로그인 칸 채우기 · 계정 삭제 재인증). 스스로 로그아웃하면 지운다. */
    const val email: String = "aingcheck.session.email"

    /** 마지막 기기 등록 성공 시각(1970 기준 초, Double 글자 — 1시간 스로틀). */
    const val deviceRegisteredAt: String = "aingcheck.device.registeredAt"

    /** 마지막 기기 등록에 실은 값의 서명(빌드·푸시 토큰이 바뀌면 스로틀을 무시하고 다시 보낸다). */
    const val deviceRegisteredSignature: String = "aingcheck.device.registeredSignature"

    /** 마지막으로 받은 FCM 토큰(Swift `apnsToken` 자리). 기기 값이라 로그아웃해도 남긴다. */
    const val pushToken: String = "aingcheck.push.fcmToken"

    /** 로그아웃·만료 때 지우는 칸. 이메일은 만료 뒤 다시 들어올 때 채우려고 빼고, 스스로 로그아웃할 때만 따로 지운다. */
    val userScopedKeys: List<String> = listOf(userID, deviceRegisteredAt, deviceRegisteredSignature)
}
