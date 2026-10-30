// 원본: Sources/check/WorkTimerStoreInsights.swift 12-14 · 207-261(retroBannerShownWeekKey · retroBannerShownWeekKeyForCurrentUser ·
//       evaluateRetroBanner · markRetroBannerDisplayed · markRetroBannerSeen) · Sources/check/WorkTimerStore.swift 381-386(팝오버 닫힘)
//       · Sources/CheckCore/CheckWorkInsights.swift 674-683(RetroWeekKey) @ db93317f
// 공용 패치 19 — 맥 팝오버 상단 '지난주 근무 기록이 준비됐어요' 배너의 판정. **데스크톱 홈 전용**(폰 호출처 0, 폰은 회고를 기록 화면에만 그린다).
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.rules.insights.RetroWeekKey
import com.yehsung.aingcheck.core.wire.SwiftDate

/**
 * '이번 주 회고 배너 봤음' 저장 키의 앞자리 — 맥 `WorkTimerStore.retroBannerShownWeekKey` 와 **같은 문자열**.
 * 값은 그 배너를 소비한 주의 KST 월요일 `YYYY-MM-DD`([RetroWeekKey.current]). 같은 값이면 그 주는 다시 띄우지 않는다.
 */
const val RETRO_BANNER_SHOWN_WEEK_KEY: String = "check.retro.shownForWeek"

/**
 * 이 계정의 '봤음' 키(맥 `retroBannerShownWeekKeyForCurrentUser`, 207-216). 계정별 접미사 `.<userID>` — 전역 키 하나면 같은 기기에서
 * A 가 소비하고 로그아웃한 뒤 같은 주에 B 로 들어오면 B 가 그 주 내내 배너를 못 받는다. 로그인 전(또는 빈 userID)은 접미사 없는 옛 키.
 */
val MeStore.retroBannerShownWeekKeyForCurrentUser: String
    get() {
        val userID = context.sessionStore.userID
        return if (userID.isNullOrEmpty()) RETRO_BANNER_SHOWN_WEEK_KEY else "$RETRO_BANNER_SHOWN_WEEK_KEY.$userID"
    }

/**
 * 배너를 띄울지 판정한다(맥 `evaluateRetroBanner`, 218-245 — 주당 1회, 지난주 회고가 있을 때만).
 * 맥은 팝오버를 열 때(기록 재조회가 필요 없으면) · 기록 계산이 끝났을 때 · 개인 기록 패널을 열 때 부른다.
 *
 * - [isInsightsPanelVisible]: 개인 기록 화면을 이미 보고 있다(맥 `isInsightsPanelVisible`) — 배너 대신 회고가 있으면 '봤음'으로 소비한다.
 * - [isMenuPresented]: 플라이아웃(맥 팝오버)이 지금 열려 있다(맥 `isMenuPresented`) — 이번 주 몫을 이미 소비했어도 지금 떠 있는 그 노출은 걷지 않는다.
 */
fun MeStore.evaluateRetroBanner(isInsightsPanelVisible: Boolean, isMenuPresented: Boolean, now: SwiftDate = context.clock.now()) {
    if (isInsightsPanelVisible) {
        // 회고가 실제로 있을 때만 소비한다(빈 패널을 열어 둔 것만으로 이번 주 안내를 잃지 않게).
        if (retro != null) {
            markRetroBannerSeen(now)
        } else if (showsRetroBanner) {
            showsRetroBanner = false
        }
        return
    }
    if (retro == null) {
        if (showsRetroBanner) showsRetroBanner = false
        return
    }
    if (context.keyValueStore.getString(retroBannerShownWeekKeyForCurrentUser) == RetroWeekKey.current(now.timeIntervalSince1970)) {
        // 이번 주 몫은 이미 소비됐다. 지금 떠 있는 배너가 바로 그 노출이면(표시 직후) 도중에 걷지 않는다 — 닫힐 때 내려간다.
        if (showsRetroBanner && isMenuPresented) return
        if (showsRetroBanner) showsRetroBanner = false
        return
    }
    if (!showsRetroBanner) showsRetroBanner = true
}

/**
 * 배너가 **실제로 그려진** 순간 이번 주 몫을 소비한다(맥 `markRetroBannerDisplayed`, 247-255 — 뷰의 onAppear).
 * 판정이 아니라 표시 시점에 소비해야 더 급한 배너에 밀려 뜨지도 못한 열림에서 이번 주 안내를 잃지 않는다. 배너는 내리지 않는다.
 */
fun MeStore.markRetroBannerDisplayed(now: SwiftDate = context.clock.now()) {
    if (!showsRetroBanner) return
    context.keyValueStore.putString(retroBannerShownWeekKeyForCurrentUser, RetroWeekKey.current(now.timeIntervalSince1970))
}

/** 이번 주에 본 것으로 적고 감춘다(맥 `markRetroBannerSeen`, 257-261 — 배너 X · 개인 기록 패널 진입 공통). */
fun MeStore.markRetroBannerSeen(now: SwiftDate = context.clock.now()) {
    context.keyValueStore.putString(retroBannerShownWeekKeyForCurrentUser, RetroWeekKey.current(now.timeIntervalSince1970))
    if (showsRetroBanner) showsRetroBanner = false
}

/**
 * 플라이아웃(맥 팝오버)이 닫혔다(맥 setMenuPresented(false), WorkTimerStore.swift 381-386) — 배너는 '이번 열림의 안내'라 내린다.
 * 표시 때 이미 소비했으므로 다음 열림의 판정은 다시 올리지 않는다. 그려지지 못한 배너는 키가 남아 다음 열림에 다시 올라온다.
 */
fun MeStore.retroBannerMenuDidClose() {
    if (showsRetroBanner) showsRetroBanner = false
}
