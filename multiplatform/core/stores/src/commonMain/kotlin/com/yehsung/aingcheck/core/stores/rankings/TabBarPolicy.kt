// 원본: Sources/CheckMobileKit/Components/MobileComponentModels.swift:445-477(TabBarPolicy) @ 1b8260d
// 배정표 round5-lane-map.md:49 — `.tetrisMatch` 갈래 하나(W2-b · core/stores/…/rankings/ 또는 ui 모델). 탭 막대 규칙은 화면 갈래(W3)가 읽는다.
package com.yehsung.aingcheck.core.stores.rankings

/**
 * 탭 막대를 숨기는 화면(시안 B: **목록 화면에만** 탭 막대 — 자체 하단 막대·몰입 화면은 숨긴다). 규칙이 한 곳이어야 화면마다 갈리지 않는다 —
 * 화면이 탭 막대를 직접 숨기면 안 된다(게임 폴더 계약).
 */
object TabBarPolicy {
    enum class Screen(val rawValue: String) {
        conversation("conversation"),
        gomokuMatch("gomokuMatch"),

        /** 체스 대국·결과 — 시계가 서버에서 흐르고 자동 착수가 없어 탭을 잘못 눌러 빠져나가는 것이 곧 시간패 쪽으로 가는 길이다. */
        chessMatch("chessMatch"),

        /** 1:1 테트리스 판·결과(1.0.11) — 판 시간이 **단조 시계**로 흐르고 루비가 걸려 있다(빠져나가면 보이지 않는 채로 조각이 떨어진다). */
        tetrisMatch("tetrisMatch"),
        shop("shop"),
        miniGamePlay("miniGamePlay"),

        /** 잔디 상세 — 자체 하단 값 막대를 가진다. */
        grassDetail("grassDetail"),
    }

    /**
     * 이 화면에서 탭 막대를 숨기는가. [Screen] 은 **'숨기는 화면 목록' 그 자체**라 전부 참이다.
     */
    // INV-MobileComponentModels-d28152c7 이식: 값으로 되묻는 자리를 둔다 — 갈래만 더해 놓고 숨기기 호출을 잊으면 목록만 는다(체스 실제 사례).
    //   화면 층(W3)의 탭 막대 숨김은 **이 답을 지나서** 숨긴다(모양이 아니라 결과를 재는 자리). 시험 TabBarPolicyTest.
    fun hidesTabBar(screen: Screen): Boolean = screen in Screen.entries
}
