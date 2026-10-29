// 원본: Sources/CheckMobileKit/Games/GamesComponents.swift:86-107(GamesMeIdentity.current) @ 3bd04bd
//
// 대국·결과 화면 '나' 얼굴의 출처 — 7차 e2e: 오목 기권 결과에서 근무 중인 내 캐릭터가 '연결 끊김'(접근성 '내 캐릭터, 연결 끊김').
// 표정은 지금 탭 내 카드에서만 '연결 끊김'이 나오고, 카드를 모르면 스냅숏 → 표정 없음(iOS 와 같은 사슬)이다.
package com.yehsung.aingcheck.android.nav

import com.yehsung.aingcheck.core.stores.now.NowMyCard
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import org.junit.Assert.assertEquals
import org.junit.Test

class BoardGameMeRuleTest {
    private val working = NowMyCard(isWorking = true, isStale = false, sessionStartedAt = null, todaySeconds = 0, weekSeconds = 0, goalHours = 40)

    private fun me(
        card: NowMyCard? = working,
        snapshotMood: CharacterMood? = null,
        loaded: Boolean = true,
        meName: String? = "나",
        teamName: String? = null,
    ): BoardGameMe = BoardGameMeRule.of(meName, teamName, loaded, "fox", "ghost", card, snapshotMood)

    @Test
    fun workingCardIsWorkingNotLost() {
        assertEquals(CharacterMood.Working, me().mood)
        // 스냅숏이 '끊김'이라고 남아 있어도 지금 카드가 이긴다.
        assertEquals(CharacterMood.Working, me(snapshotMood = CharacterMood.Lost).mood)
        assertEquals(CharacterMood.Lost, me(card = working.copy(isStale = true)).mood)
        assertEquals(CharacterMood.Off, me(card = working.copy(isWorking = false)).mood)
    }

    @Test
    fun unknownCardFallsBackToSnapshotThenPlain() {
        assertEquals(CharacterMood.Working, me(card = null, snapshotMood = CharacterMood.Working).mood)
        assertEquals("모르면 '근무 안 함'으로 말하지 않는다", CharacterMood.Plain, me(card = null).mood)
    }

    @Test
    fun characterAndNameFollowIos() {
        assertEquals("fox", me().characterID)
        assertEquals("착용을 아직 못 읽었으면 스냅숏의 지난 값", "ghost", me(loaded = false).characterID)
        assertEquals("소라", me(meName = null, teamName = " 소라 ").name)
        assertEquals(null, me(meName = "  ", teamName = "소라").name)
    }
}
