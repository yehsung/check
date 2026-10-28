// 원본: Tests/CheckMobileKitTests/IntegrationFixTests.swift:38-58(허브 카드 실패 문구) · GamesAIMatchTests.swift:585-596(AI 판은 신청을
//       가리지 않는다) · GamesRedesignTests.swift:66-80('오늘 내 순위' 부제) · Sources/CheckMobileKit/Components/MobileComponentRules.swift
//       (MobileLoadKnowledge 판정 — 표로 잰다) @ 1b8260d
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.stores.games.MobileLoadKnowledge.Placeholder
import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameBoard
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardEntry
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class GamesTextTest {
    /**
     * 빈 자리 판정(탭 공통): 줄이 있으면 줄 · 받았고 실패하지 않았으면 "없어요" · 모르고 마지막이 실패면 실패 · 아직 모르면 불러오는 중.
     * 불러오지 못한 목록을 "없다"로 말하지 않는 것이 핵심이다(오프라인에서 '오늘 기록 없음' 이라 말하던 결함). 8 갈래 전수.
     */
    @Test
    fun theEmptyPlaceholderNeverCallsAFailureEmpty() {
        val table = listOf(
            Triple(Triple(true, true, true), Placeholder.rows, true),
            Triple(Triple(true, false, true), Placeholder.rows, true),
            Triple(Triple(true, true, false), Placeholder.rows, true),
            Triple(Triple(true, false, false), Placeholder.rows, true),
            Triple(Triple(false, true, false), Placeholder.empty, true),
            Triple(Triple(false, true, true), Placeholder.failed, false),
            Triple(Triple(false, false, true), Placeholder.failed, false),
            Triple(Triple(false, false, false), Placeholder.loading, false),
        )
        for ((input, placeholder, knows) in table) {
            val (rows, loaded, failed) = input
            assertEquals(placeholder, MobileLoadKnowledge.placeholder(rows, loaded, failed), "rows=$rows loaded=$loaded failed=$failed")
            assertEquals(knows, MobileLoadKnowledge.knowsCount(rows, loaded, failed), "knows rows=$rows loaded=$loaded failed=$failed")
        }
    }

    /** 허브 카드: 순위표를 못 불러왔으면 '오늘 기록 없음' 대신 실패 · 모르면 불러오는 중 · 알고 없으면 기록 없음 · 내 줄을 알면 실패여도 그대로. */
    @Test
    fun theHubCardSaysFailureNotEmpty() {
        assertEquals(GamesText.recordLoadFailed, GamesText.todayLine(null, null, GamesMiniGameBoard(failed = true)))
        assertEquals(GamesMiniGameText.loadingCaption, GamesText.todayLine(null, null, GamesMiniGameBoard()))
        assertEquals(GamesMiniGameText.noRankToday, GamesText.todayLine(null, null, GamesMiniGameBoard(loaded = true)))
        assertEquals("오늘 최고 12점 · 2위", GamesText.todayLine(12, 2, GamesMiniGameBoard(loaded = true, failed = true)), "내 줄을 알면 실패여도 그대로")
        assertEquals("오늘 최고 1000점", GamesText.todayLine(1000, null, GamesMiniGameBoard(loaded = true)), "자리수 구분 없이 · 순위 밖이면 최고만")
        assertNull(GamesMiniGameText.rankLine(null, knowsBoard = false))
        assertEquals(GamesMiniGameText.noRankToday, GamesMiniGameText.rankLine(null, knowsBoard = true))
        assertEquals("오늘 3위", GamesMiniGameText.rankLine(3, knowsBoard = false))
        // 오목 카드: 받은함을 못 불러왔으면 "상대를 골라…"(= 받은 게 없다)로 접지 않는다. 진행 판·받은 신청이 있으면 그것이 먼저.
        assertEquals(GamesText.inboxLoadFailed, GamesText.gomokuLine(0, hasActiveMatch = false, hasOutgoing = false, inboxFailed = true))
        assertEquals("상대를 골라 대결을 신청해요", GamesText.gomokuLine(0, hasActiveMatch = false, hasOutgoing = false))
        assertEquals("받은 신청 2건", GamesText.gomokuLine(2, hasActiveMatch = false, hasOutgoing = false, inboxFailed = true))
        assertEquals("진행 중인 대국이 있어요", GamesText.gomokuLine(0, hasActiveMatch = true, hasOutgoing = false, inboxFailed = true))
        assertEquals("보낸 신청을 기다리고 있어요", GamesText.gomokuLine(0, hasActiveMatch = false, hasOutgoing = true))
    }

    /** 허브 오목 카드: 두던 AI 판이 사람의 1:1 신청을 가리지 않는다(루비가 걸린 신청을 놓친다) · 사람 대국은 늘 먼저다. */
    @Test
    fun anAIGameDoesNotHideAnIncomingInvite() {
        assertEquals(false, GamesText.hubShowsActiveMatch(active = true, isAIMatch = true, incoming = 1), "AI 판이 받은 신청을 가렸다")
        assertEquals(true, GamesText.hubShowsActiveMatch(active = true, isAIMatch = true, incoming = 0), "받은 신청이 없으면 두던 AI 판을 말한다")
        assertEquals(true, GamesText.hubShowsActiveMatch(active = true, isAIMatch = false, incoming = 3), "사람 대국은 신청보다 먼저다")
        assertEquals(false, GamesText.hubShowsActiveMatch(active = false, isAIMatch = false, incoming = 2))
        val line = GamesText.gomokuLine(1, hasActiveMatch = GamesText.hubShowsActiveMatch(true, true, 1), hasOutgoing = false)
        assertEquals("받은 신청 1건", line)
    }

    /** '오늘 내 순위' 부제: 1등 · 참여 수 — 모르면 불러오는 중 · 실패 · 빈 순위는 아무도 안 했다. */
    @Test
    fun theHubRankSubtitleNamesTheLeader() {
        assertEquals(GamesMiniGameText.loadingCaption, GamesText.hubRankSubtitle(GamesMiniGameBoard()))
        assertEquals(GamesMiniGameText.failedCaption, GamesText.hubRankSubtitle(GamesMiniGameBoard(failed = true)))
        assertEquals("오늘은 아직 아무도 안 했어요", GamesText.hubRankSubtitle(GamesMiniGameBoard(loaded = true)))
        val board = GamesMiniGameBoard(
            entries = listOf(
                MiniGameBoardEntry("a", "민트별", null, 962, null, 3),
                MiniGameBoardEntry("b", "구름빵", null, 918, null, 2),
            ),
            loaded = true,
        )
        assertEquals("1위 민트별 962점 · 2명 참여", GamesText.hubRankSubtitle(board))
        assertEquals("1위 민트별 962점 · 2명 참여", GamesText.hubRankSubtitle(board.copy(failed = true)), "줄이 있으면 실패여도 줄")
    }
}
