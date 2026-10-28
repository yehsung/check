// 원본: 없음 — G §8-17 #1(판돈 대결 Android 빌드 깃발). W2-a 앱 구성 계약 AppConfig 의 Android 조립.
package com.yehsung.aingcheck.android.app

import com.yehsung.aingcheck.android.BuildConfig
import com.yehsung.aingcheck.core.session.app.AppConfig

/**
 * BuildConfig → 앱 구성 계약. 판돈 대결 깃발을 읽는 곳은 이 함수 하나다(스토어·화면이 BuildConfig 를 직접 읽지 않는다 —
 * 시험이 AppConfig 를 주입해 켜짐·꺼짐을 둘 다 재야 하므로).
 */
object AndroidAppConfig {
    fun fromBuildConfig(): AppConfig = AppConfig(duelsEnabled = BuildConfig.DUELS_ENABLED)
}
