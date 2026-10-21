// 원본: Sources/CheckMobileKit/Session/MobileDeviceService.swift(MobileDeviceRPC.platform = "ios") @ a63fea2
// K4: (platform, build, version) 은 multiplatform/version.properties 한 곳에서 만든다.
// 앱 모듈이 생성 파일 BuildIdentity(build/generated)를 읽어 이 값을 조립한다. 다른 곳에서 숫자를 짓지 않는다.
package com.yehsung.aingcheck.core.foundation.identity

/** 서버 `platform` 칸에 실리는 값. 맥(`mac`)·iOS(`ios`)는 이 앱들이 보내지 않는다. */
enum class ClientPlatform(val wire: String) {
    ANDROID("android"),
    WINDOWS("windows"),
}

/**
 * 이 클라의 정체. `build` 는 플랫폼마다 **다른 축**이다(W-나):
 * - Android: versionCode. 서버 app_build 범위 1..1,000,000(K5).
 * - Windows: MSI BUILD 칸. 1..65535(A§6-2).
 */
data class ClientIdentity(val platform: ClientPlatform, val build: Long, val version: String) {
    init {
        val range = when (platform) {
            ClientPlatform.ANDROID -> 1L..1_000_000L
            ClientPlatform.WINDOWS -> 1L..65_535L
        }
        require(build in range) { "${platform.wire} build $build 가 범위 $range 밖이다" }
        require(version.isNotBlank()) { "version 이 비었다" }
    }

    companion object {
        /** 생성 파일(BuildIdentity.PLATFORM·BUILD·VERSION)의 문자열에서 조립한다. */
        fun fromGenerated(platform: String, build: String, version: String): ClientIdentity {
            val p = ClientPlatform.entries.firstOrNull { it.wire == platform }
                ?: throw IllegalArgumentException("모르는 플랫폼 '$platform'")
            val b = build.toLongOrNull() ?: throw IllegalArgumentException("build '$build' 가 정수가 아니다")
            return ClientIdentity(p, b, version)
        }
    }
}
