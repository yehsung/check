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
    /**
     * **아잉 뒤집기 떼어 내기 깃발**(판 7 — 대표 답 #d_DdwzmxPClGqk "다 넣기 (루비 걸기 포함)" · 제때 안 서면 떼어 내고 다음 판으로).
     * 끄면 폰 조립이 리버시 스토어를 **만들지 않는다** — 게임 탭 카드 · 받은 신청(탭 배지 · 카드 칩) · 실시간 'reversi' 가지 · 허브 조회 ·
     * 한 사람 한 판의 다섯째 방향 · 일일 미션 줄의 '맥에서' 꼬리 숨김이 전부 스토어가 있는지 하나만 보므로 함께 사라지고, 다른 게임은 판 7 이전과
     * 같이 돈다(시험 PhoneReversiWiringTest 가 요청 기록으로 잰다). 판돈 대결 깃발([duelsEnabled])과는 **다른 축**이다 — 이 깃발이 켜져 있어도
     * 판돈 깃발이 꺼진 빌드는 리버시 신청·수락이 체스처럼 잠긴다(AI 연습 · 관전 · 순위는 열린다). Windows 조립은 이 값을 읽지 않는다.
     */
    val reversiEnabled: Boolean = REVERSI_ENABLED_DEFAULT,
) {
    companion object {
        /** 기본은 꺼짐이다(§8-17 #1). 켜는 것은 빌드 N 의 조립 지점 몫 — 여기 기본값을 true 로 바꾸지 않는다. */
        const val DUELS_ENABLED_DEFAULT: Boolean = false

        /** 기본은 켜짐이다(판 7). 떼어 낼 때는 이 한 줄을 false 로 바꾼다(또는 조립 지점이 `AppConfig(reversiEnabled = false)` 로 넣는다). */
        const val REVERSI_ENABLED_DEFAULT: Boolean = true
    }
}
