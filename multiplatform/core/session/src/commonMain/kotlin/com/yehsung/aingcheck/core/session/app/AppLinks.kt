// 원본: Sources/CheckCore/CheckAppLinks.swift · Sources/CheckMobileKit/Session/MobileSessionStore.swift:777-811(MobileSessionText 업데이트 목적지) @ 1b8260d
package com.yehsung.aingcheck.core.session.app

import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform

/**
 * 앱 밖으로 가는 주소 — **여기 한 곳에만** 있다(Swift `CheckAppLinks` 와 같은 규칙).
 *
 * INV-MobileSessionStore-f754b3e3 이식: 업데이트 화면의 목적지·처리방침·약관 주소는 이 파일 한 곳에서 온다. 화면·문구 쪽에 글자로
 * 다시 적으면 주소 규칙이 바뀌는 날 한쪽만 고쳐진다(시험 `AppLinksTest` 가 Play 주소 모양과 applicationId 일치를 잰다).
 */
object AppLinks {
    /** Play 에 한 번 올리면 바꿀 수 없는 영구 식별자(build-logic `aingcheck.android-app` 의 applicationId 와 같은 글자 — 시험이 대조). */
    const val androidApplicationId: String = "com.yehsung.aingcheck"

    /**
     * 업데이트 필요 화면의 Android 목적지.
     *
     * INV-MobileSessionStore-cc0d4cc0 이식: iOS 는 `itms-beta://`(TestFlight)가 스토어 사용자에게 막다른 길이었다. Android 의 같은 함정은
     *   `market://` 스킴이다 — Play 스토어 앱이 없는 기기(사이드로드·일부 태블릿)에서는 처리할 앱이 없어 **아무 일도 안 일어나고**,
     *   서버 최소 빌드를 올리는 순간 버튼을 눌러도 화면이 그대로인 자리에 갇힌다.
     * INV-MobileSessionStore-a846909f 이식: 그래서 `market://` 가 아니라 `https://` 다. Play 앱이 있으면 앱 링크로 Play 가 열리고,
     *   없어도 브라우저가 같은 페이지를 보여 준다 — 무반응으로 되돌아갈 갈래가 없다.
     * INV-MobileSessionStore-68eea3ec 이식: 지역·언어 꼬리(`hl=`·`gl=`)를 넣지 않는다 — Play 가 보는 사람 지역·언어로 보낸다.
     *   쿼리는 앱 id 하나뿐이다.
     */
    const val playStore: String = "https://play.google.com/store/apps/details?id=$androidApplicationId"

    /** 개인정보 처리방침(Swift `CheckAppLinks.privacyPolicy` 와 같은 주소). 가입 화면의 동의 한 줄과 나 → 설정이 쓴다. */
    const val privacyPolicy: String = "https://yehsung.github.io/check/privacy"

    /** 이용약관(Swift `CheckAppLinks.termsOfService` 와 같은 주소). */
    const val termsOfService: String = "https://yehsung.github.io/check/terms"

    /**
     * 업데이트 필요 화면의 목적지. Android = Play. Windows 는 보류(§8-16) — 서버 `client_release('windows').download_url`(K5) 을 읽는
     * 갈래가 생기면 그쪽 값을 쓴다. 지금은 null(화면은 버튼 없이 문구만 둔다).
     */
    fun updateDestination(platform: ClientPlatform): String? = when (platform) {
        ClientPlatform.ANDROID -> playStore
        ClientPlatform.WINDOWS -> null
    }
}
