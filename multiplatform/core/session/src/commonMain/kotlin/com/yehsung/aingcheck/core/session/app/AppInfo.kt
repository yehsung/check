// 원본: Sources/CheckMobileKit/App/MobileAppInfo.swift @ 1b8260d
package com.yehsung.aingcheck.core.session.app

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.wire.SwiftDate

/**
 * 이 설치의 앱 정보(Swift `MobileAppInfo`). (platform, build, version) 은 K4 [ClientIdentity] — `version.properties` 한 곳에서
 * 조립 지점이 만든 값이다. 여기서 숫자를 짓지 않는다(Android versionCode 와 Windows MSI BUILD 는 서로 다른 축 — W-나).
 *
 * iOS 의 `apnsEnvironment` 는 옮기지 않는다 — FCM 토큰은 환경 짝이 없다(K5 `register_device_fcm` 인자 넷).
 */
data class AppInfo(
    val identity: ClientIdentity,
    /** 제보에 싣는 OS 표시값("Android 15" · "Windows 11"). 조립 지점이 넣는다. */
    val osVersion: String,
) {
    val platform: ClientPlatform get() = identity.platform

    /** Android versionCode · Windows BUILD. `client_release(platform).min_build` 와 비교한다. */
    val build: Long get() = identity.build

    val version: String get() = identity.version

    /** 표시용 플랫폼 이름(Swift 의 "iOS" 자리). */
    val platformLabel: String
        get() = when (platform) {
            ClientPlatform.ANDROID -> "Android"
            ClientPlatform.WINDOWS -> "Windows"
        }

    /** 제보에 싣는 앱 버전 문자열 — Swift `feedbackAppVersion`("iOS 0.1.0 (1)")과 같은 꼴: "Android 0.1.0 (1)". */
    val feedbackAppVersion: String get() = "$platformLabel $version ($build)"
}

/**
 * 세션·로그인 아래 화면이 시각을 읽는 **유일한 문**(Swift `MobileClock`). 벽시계는 앱 조립 지점에서만 만든다(구조 시험 R2) —
 * 시험은 가상 시간(`TestScope.testScheduler`)에서 나온 시계를 넣는다.
 */
fun interface SessionClock {
    fun now(): SwiftDate

    companion object {
        /** 한 순간에 멈춘 시계(Swift `MobileClock.fixed`). */
        fun fixed(date: SwiftDate): SessionClock = SessionClock { date }

        /** 데모 기준 시각: 2026-09-17 14:05:00 KST = 05:05:00 UTC(Swift `MobileClock.demoInstant`). */
        val demoInstant: SwiftDate = SwiftDate(1_789_621_500.0)
    }
}
