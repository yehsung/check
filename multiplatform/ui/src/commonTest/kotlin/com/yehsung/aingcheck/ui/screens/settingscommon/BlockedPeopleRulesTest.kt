// 원본: Sources/CheckMobileKit/Me/MeBlockedPeopleView.swift @ 3bd04bd (emptyContent 세 갈래 · 구분선 시작 = 16 + 40 + 12)
package com.yehsung.aingcheck.ui.screens.settingscommon

import kotlin.test.Test
import kotlin.test.assertEquals

class BlockedPeopleRulesTest {
    @Test
    fun emptyCardPrefersWhatWeKnow() {
        assertEquals(BlockedEmptyCard.Loading, BlockedPeopleRules.emptyCard(loading = true, failed = false, loaded = false))
        assertEquals(BlockedEmptyCard.Failed, BlockedPeopleRules.emptyCard(loading = false, failed = true, loaded = false))
        assertEquals(BlockedEmptyCard.Loading, BlockedPeopleRules.emptyCard(loading = true, failed = true, loaded = false), "다시 도는 중이면 불러오는 중")
        assertEquals(BlockedEmptyCard.Empty, BlockedPeopleRules.emptyCard(loading = true, failed = true, loaded = true), "받은 값(빈 목록)이 있으면 빈 안내")
        assertEquals(BlockedEmptyCard.Empty, BlockedPeopleRules.emptyCard(loading = false, failed = false, loaded = true))
        assertEquals(68, BlockedPeopleRules.DIVIDER_LEADING)
    }
}
