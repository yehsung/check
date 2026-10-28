// 원본: 없음 — G §8-17 #1: 판돈 대결 빌드 깃발은 빌드 N 전까지 꺼져 있고, 앱 구성 계약이 BuildConfig 를 그대로 옮긴다.
package com.yehsung.aingcheck.android.app

import com.yehsung.aingcheck.android.BuildConfig
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 이 빌드의 판돈 진입 **기대값**. 빌드 N(판돈 e2e 통과)은 build.gradle.kts 의 `DUELS_ENABLED` 와 **이 값을 함께** true 로 바꾼다 —
 * 한쪽만 바뀌면 아래 시험이 게이트를 막는다(의도된 이중 확인: 실수로 켠 빌드가 트랙에 오르지 않게).
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
