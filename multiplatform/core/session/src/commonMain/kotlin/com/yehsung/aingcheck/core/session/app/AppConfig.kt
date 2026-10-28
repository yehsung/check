// 원본: 없음 — G §8-17 #1(판돈 대결 Android 빌드 깃발). iOS 에는 같은 깃발이 없다(서버 변경 없이 클라 빌드로만 가른다).
package com.yehsung.aingcheck.core.session.app

/**
 * **앱 구성 계약** — 빌드가 정하는 기능 깃발이 사는 **한 자리**(G §8-17 #1 "깃발 자리는 W2-a 의 앱 구성 계약, 소비는 W2-d·W2-e").
 *
 * - 원천: Android 는 조립 지점(`AppContainer`)이 `BuildConfig.DUELS_ENABLED`(기본 false)를 넣는다. Windows(보류)는 기본값.
 * - 읽는 곳: 스토어는 [com.yehsung.aingcheck.core.session.context.SessionContext.appConfig] 로만 읽는다 — 깃발을 상수로 다시 적거나
 *   BuildConfig 를 스토어에서 직접 읽지 않는다(시험이 [AppConfig] 를 주입해 켜짐·꺼짐을 둘 다 잰다).
 * - 바꾸는 법: 판돈 e2e 를 통과한 빌드 N 의 Gradle 빌드 파일에서만 켠다. 서버는 바꾸지 않는다(로비 `me.capable` 추가 안 함).
 */
data class AppConfig(
    /**
     * 판돈 대결의 **신청·수락 진입**을 보일까(오목·체스·테트리스 1:1). 꺼진 빌드는 진입을 숨기고 내부 트랙에만 오른다.
     * 이 깃발은 일일 미션 목록을 가리지 않는다 — 대결 3종 미션 줄은 깃발과 무관하게 그대로 보인다(길건너 '모두에게 보이기' 선례).
     */
    val duelsEnabled: Boolean = DUELS_ENABLED_DEFAULT,
) {
    companion object {
        /** 기본은 꺼짐이다(§8-17 #1). 켜는 것은 빌드 N 의 조립 지점 몫 — 여기 기본값을 true 로 바꾸지 않는다. */
        const val DUELS_ENABLED_DEFAULT: Boolean = false
    }
}
