// 원본: 없음 — G §8-17 #1: 판돈 대결 빌드 깃발은 빌드 N 전까지 꺼져 있고, 앱 구성 계약이 BuildConfig 를 그대로 옮긴다.
// W6-a 패치 01: release 의 깃발은 출시 인자(release-android.sh --duels on|off → Gradle 속성 aingcheck.release.duelsEnabled)로 정하되,
// 커밋된 version.properties 의 androidDuelsFromBuild=N(≤ androidVersionCode)과 맞아야 한다(이중 확인 — Gradle 과 출시 스크립트 둘 다 잰다).
// 출시 스크립트가 산출물 dex 의 BuildConfig.DUELS_ENABLED 를 다시 읽어 요청과 대조한다. 이 시험(호스트 = debug 변형)은 그와 별개로
// "debug·stub 은 언제나 꺼짐"을 잰다 — 판돈을 켠 빌드 N 에서도 이 값은 false 그대로다.
package com.yehsung.aingcheck.android.app

import com.yehsung.aingcheck.android.BuildConfig
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 시험 변형(debug)의 판돈 진입 **기대값** — 언제나 false. release 는 build.gradle.kts 가 aingcheck.release.duelsEnabled 와 커밋된
 * androidDuelsFromBuild 가 함께 있을 때만 켠다(기본 꺼짐). defaultConfig 의 false 를 누가 true 로 바꾸면 아래 시험이 게이트를 막는다(실수로 켠 시험 판이 퍼지지 않게).
 * 공용 기본값(`AppConfig.DUELS_ENABLED_DEFAULT` = false — 데스크톱·시험 몫)은 core/session AppConfigTest 가 따로 잰다. 빌드 N 에서도 그대로다.
 */
private const val THIS_BUILD_DUELS_ENABLED = false

class DuelsBuildFlagTest {
    @Test
    fun duelsFlagMatchesThisBuildsDecision() {
        assertEquals(THIS_BUILD_DUELS_ENABLED, BuildConfig.DUELS_ENABLED)
    }

    /** 앱 구성은 BuildConfig 를 그대로 옮긴다 — 스토어가 읽는 값(AppConfig)이 이 빌드의 결정과 갈리지 않는다. */
    @Test
    fun appConfigCarriesTheBuildFlag() {
        assertEquals(THIS_BUILD_DUELS_ENABLED, AndroidAppConfig.fromBuildConfig().duelsEnabled)
    }
}
