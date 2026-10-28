// 원본: Tests/CheckMobileKitTests/RankingsRedesignTests.swift @ 3bd04bd (빈 카드 갈림 · 칩 · 나 얼굴 · 상품·정족수) — 복원(⑥)·오늘만(§8-18 #7)은 원본 없음
package com.yehsung.aingcheck.ui.screens.rankings

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenTestCollation
import com.yehsung.aingcheck.core.stores.now.NowMyCard
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard
import com.yehsung.aingcheck.core.stores.rankings.RankingsLoadState
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.screens.settingscommon.DemoFixtures
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenHarness
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class RankingsScreenRulesTest {
    @Test
    fun emptyCardSaysLoadingFailedOrEmptyNeverMixed() {
        val loading = RankingsLoadState(isLoading = true)
        assertEquals(RankingsEmptyCardState("불러오는 중…", showsRetry = false, isLoading = true), RankingsScreenRules.tokenEmpty(loading, isCurrentMonth = true))
        val failed = RankingsLoadState(hasFailed = true)
        assertEquals(RankingsEmptyCardState("순위를 불러오지 못했어요", showsRetry = true, isLoading = false), RankingsScreenRules.tokenEmpty(failed, true))
        val empty = RankingsLoadState(hasLoaded = true)
        assertEquals(RankingsEmptyCardState("아직 이번 달 소모량을 올린 사용자가 없어요", false, false), RankingsScreenRules.tokenEmpty(empty, true))
        assertEquals("이 달에는 기록이 없어요", RankingsScreenRules.tokenEmpty(empty, false).text)
        assertEquals(RankingsEmptyCardState("리그를 불러오지 못했어요", true, false), RankingsScreenRules.leagueEmpty(failed, 0, isPastWeek = false, leagueIsEmpty = true))
        assertFalse(RankingsScreenRules.leagueEmpty(failed, 0, false, leagueIsEmpty = false).showsRetry, "받아 둔 리그가 있으면 빈 카드에 다시 시도를 세우지 않는다")
        assertEquals("아직 이번 주 근무한 팀이 없어요", RankingsScreenRules.leagueEmpty(empty, 3, false, false).text, "0시간 팀만 있다")
        assertEquals("그 주엔 근무한 팀이 없었어요", RankingsScreenRules.leagueEmpty(empty, 0, isPastWeek = true, leagueIsEmpty = true).text)
        assertEquals(RankingsEmptyCardState("아직 기록이 없어요 — 첫 기록의 주인공이 되세요", false, false), RankingsScreenRules.miniGameEmpty(empty))
        assertTrue(RankingsScreenRules.miniGameEmpty(failed).showsRetry)
        assertFalse(RankingsScreenRules.miniGameEmpty(RankingsLoadState(hasLoaded = true, hasFailed = true)).showsRetry, "받은 적이 있으면 다시 시도 대신 빈 문구")
    }

    @Test
    fun chipsMedalsAndMe() {
        assertEquals(listOf(RankingsChip.Me, RankingsChip.PrivateUsage), RankingsScreenRules.tokenChips(isMe = true, myTokenUsagePublic = false))
        assertEquals(listOf(RankingsChip.Me), RankingsScreenRules.tokenChips(isMe = true, myTokenUsagePublic = null), "공개 여부를 모르면 비공개 칩을 붙이지 않는다")
        assertEquals(emptyList(), RankingsScreenRules.tokenChips(isMe = false, myTokenUsagePublic = false))
        assertFalse(RankingsScreenRules.isMe("u-1", null), "내 id 를 모르면 아무도 '나'가 아니다")
        assertTrue(RankingsScreenRules.isMe("u-1", "u-1"))
        assertEquals(listOf(RankingsMedal.Gold, RankingsMedal.Silver, RankingsMedal.Bronze, null), (1..4).map(RankingsScreenRules::medal))
    }

    @Test
    fun myFaceComesFromKnownValuesOnly() {
        val working = NowMyCard(isWorking = true, isStale = false, sessionStartedAt = null, todaySeconds = 0, weekSeconds = 0, goalHours = 40)
        val stale = working.copy(isStale = true)
        val off = working.copy(isWorking = false)
        assertEquals(RankingsMyFace("fox", CharacterMood.Working), RankingsScreenRules.myFace(true, "fox", "ghost", working, CharacterMood.Off))
        assertEquals(RankingsMyFace("ghost", CharacterMood.Lost), RankingsScreenRules.myFace(false, "fox", "ghost", stale, null), "나 탭이 아직 모르면 위젯 스냅숏의 지난 값")
        assertEquals(RankingsMyFace(null, CharacterMood.Off), RankingsScreenRules.myFace(false, null, null, off, null))
        assertEquals(RankingsMyFace(null, CharacterMood.Lost), RankingsScreenRules.myFace(false, null, null, null, CharacterMood.Lost), "카드가 없으면 스냅숏 상태")
        assertEquals(CharacterMood.Off, RankingsScreenRules.myFace(false, null, null, null, null).mood, "모르면 근무 안 함")
    }

    @Test
    fun centerBadgeAcceptsDisplayOrServerValue() {
        assertEquals("seoul", RankingsScreenRules.centerServerValue("서울"), "토큰판(화면 글자)")
        assertEquals("busan", RankingsScreenRules.centerServerValue("busan"), "리그·미니게임(서버값)")
        assertNull(RankingsScreenRules.centerServerValue("jeju"), "모르는 값은 배지 없음")
        assertNull(RankingsScreenRules.centerServerValue(null))
    }

    /** §8-18 #7: 폰 첫 판 = iOS 1.0.14 바닥 — 길건너 아잉이는 메뉴에 없다. */
    @Test
    fun miniGameMenuIsPhoneCasesOnlyWithoutCrossy() {
        assertEquals(listOf(MiniGameKind.timingBar, MiniGameKind.flappy, MiniGameKind.tetris), RankingsScreenRules.miniGameKinds)
        assertFalse(MiniGameKind.crossy in RankingsScreenRules.miniGameKinds)
    }

    @Test
    fun prizeLineAndQuorum() {
        assertNull(RankingsScreenRules.quorumLine(knowsPlayerCount = false, players = 0), "모르는 사람 수를 '아무도 안 했어요'로 말하지 않는다")
        assertEquals("오늘은 아직 아무도 안 했어요 · 5명부터 지급", RankingsScreenRules.quorumLine(true, 0))
        assertEquals("오늘 7명 참여 · 지급 조건 충족", RankingsScreenRules.quorumLine(true, 7))
        assertEquals(20, RankingsScreenRules.championAward(true))
        assertNull(RankingsScreenRules.championAward(false))
    }

    /** ⑥ 복원 규칙: 저장한 선택이 인자(딥링크)를 이긴다 · 저장이 없으면 인자 · 모르는 글자는 건드리지 않는다. */
    @Test
    fun boardRestorePrefersSavedSelectionThenNavArg() {
        assertEquals(RankingsBoard.tokens, RankingsBoardRestore.boardToApply(navArgRaw = "tokens", saved = null))
        assertEquals(RankingsBoard.minigame, RankingsBoardRestore.boardToApply(navArgRaw = "tokens", saved = "minigame"))
        assertNull(RankingsBoardRestore.boardToApply(navArgRaw = "crossy", saved = null))
        assertEquals(RankingsBoard.league, RankingsBoardRestore.boardToApply(navArgRaw = "league", saved = null))
    }

    /** 데모 픽스처로 돈 스토어 위에서 화면 판정이 맞는 값을 본다(내 행 · 우리 팀 · 비공개 칩 — 서버값 그대로). */
    @Test
    fun demoStoreFeedsScreenRules() = runTest {
        val h = ScreenHarness(this, DemoFixtures(DemoFixtures.rankings), scenario = "rankings-tokens")
        h.signIn()
        advanceUntilIdle()
        val store = RankingsStore(h.context, h.storeScope, ScreenTestCollation)
        store.tabDidAppear()
        advanceUntilIdle()
        assertEquals("d0000000-0000-4000-8000-000000007ea1", store.myTeamID, "소속 픽스처의 우리 팀")
        assertTrue(store.leagueDisplay.any { it.id == store.myTeamID })
        store.select(RankingsBoard.tokens)
        advanceUntilIdle()
        val mine = store.tokenBoard.single { RankingsScreenRules.isMe(it.userID, store.myUserID) }
        assertEquals("새벽", mine.name)
        assertEquals(listOf(RankingsChip.Me, RankingsChip.PrivateUsage), RankingsScreenRules.tokenChips(true, store.myTokenUsagePublic), "픽스처는 token_usage_public=false")
        assertTrue(h.missing.none { it.startsWith("rpc.team_weekly") || it.startsWith("rpc.token_usage") }, "픽스처 없는 조회: ${h.missing}")
    }
}
