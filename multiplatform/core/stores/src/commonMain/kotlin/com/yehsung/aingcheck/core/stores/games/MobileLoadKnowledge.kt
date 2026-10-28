// 원본: Sources/CheckMobileKit/Components/MobileComponentRules.swift:1-46(MobileLoadKnowledge · MobileLoadText) @ 1b8260d
package com.yehsung.aingcheck.core.stores.games

/**
 * 빈 목록을 "없다"로 말해도 되는가 — 탭 공통 규칙(Swift `MobileLoadKnowledge`). 게임 허브·테트리스 순위가 쓴다.
 *
 * 이 파일은 공용 부품(Swift `Components/MobileComponentRules.swift` — W2 배정표 밖)의 **판정 두 줄만** 옮긴 것이다. 다른 스토어 갈래
 * (W2-b 순위·W2-c 나)가 같은 규칙을 따로 옮기면 c-fold 가 한 자리로 모은다 — 글자·판정이 Swift 한 벌과 같아야 한다.
 */
object MobileLoadKnowledge {
    /** 빈 자리를 무엇으로 채우는가. */
    enum class Placeholder {
        /** 줄이 있다 — 줄을 그린다. */
        rows,

        /** 받았고 비어 있다 — "없어요" 문구. */
        empty,

        /** 모르고, 마지막 조회가 실패했다 — "불러오지 못했어요" + 다시 시도. */
        failed,

        /** 아직 모른다(첫 조회가 돌거나 아직 안 나갔다). */
        loading,
    }

    /** 개수(0 포함)를 안다. */
    fun knowsCount(hasRows: Boolean, hasLoaded: Boolean, lastFailed: Boolean): Boolean = hasRows || (hasLoaded && !lastFailed)

    fun placeholder(hasRows: Boolean, hasLoaded: Boolean, lastFailed: Boolean): Placeholder {
        if (hasRows) return Placeholder.rows
        if (knowsCount(hasRows, hasLoaded, lastFailed)) return Placeholder.empty
        return if (lastFailed) Placeholder.failed else Placeholder.loading
    }
}

/** 조회 실패 화면의 공용 문구(Swift `MobileLoadText`). */
object MobileLoadText {
    const val retry: String = "다시 시도"

    /** 코어 오목 문구와 같은 문장(`GomokuNoticeText.checkConnection`). */
    const val checkConnection: String = "연결을 확인하고 다시 시도해 주세요"
    const val retrying: String = "불러오는 중…"
}
