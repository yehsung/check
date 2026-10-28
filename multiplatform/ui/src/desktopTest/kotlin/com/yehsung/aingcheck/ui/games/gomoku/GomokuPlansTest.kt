// 원본: 없음 — 오목 화면 문구(GomokuScreenText — Swift GamesText.swift · GamesGomokuRankingText.swift 와 같은 문장)와 순수 판정(GomokuRankingPlan · 뒤로가기 · 탭 막대)의
// 이식 시험. 기대 문장은 Swift 원문에서 손으로 옮겨 적었다(구현을 거울처럼 다시 쓰지 않는다).
package com.yehsung.aingcheck.ui.games.gomoku

import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.rules.renju.GomokuOutcome
import com.yehsung.aingcheck.core.stores.gomoku.GomokuLiveMatch
import com.yehsung.aingcheck.core.stores.gomoku.GomokuMyRank
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhase
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneMatchChrome
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRecord
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStake
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.test.Test
import kotlin.test.assertEquals

class GomokuPlansTest {
    private fun user(id: String, name: String, inMatch: Boolean = false, capable: Boolean = true, working: Boolean = true) =
        GomokuUser(id, name, null, null, isWorking = working, isCapable = capable, inMatch = inMatch)

    @Test
    fun textTableMatchesTheSwiftSentences() {
        assertEquals("6승 2패 1무", GomokuScreenText.record(GomokuRecord(6, 2, 1)))
        assertEquals("전적 —", GomokuScreenText.record(null))
        assertEquals("6승 2패 1무", GomokuScreenText.record(6, 2, 1))
        assertEquals("+4", GomokuScreenText.signedPoints(4))
        assertEquals("−3", GomokuScreenText.signedPoints(-3), "음수는 U+2212")
        assertEquals("0", GomokuScreenText.signedPoints(0))
        assertEquals("12위 · 승점 +4 · 6승 2패 1무", GomokuScreenText.myRankLine(GomokuMyRank(12, 6, 2, 1, 4)))
        assertEquals("순위 밖 · 0승 0패 0무", GomokuScreenText.myRankLine(GomokuMyRank(null, 0, 0, 0, 0)))
        assertEquals("5목을 완성했어요", GomokuScreenText.endReason(GomokuEndReason.five, GomokuOutcome.won))
        assertEquals("상대가 5목을 완성했어요", GomokuScreenText.endReason(GomokuEndReason.five, GomokuOutcome.lost))
        assertEquals("판이 가득 찼어요 · 건 루비는 돌려받아요", GomokuScreenText.endReason(GomokuEndReason.boardFull, GomokuOutcome.draw))
        assertEquals("AI가 5목을 완성했어요", GomokuScreenText.aiEndReason(GomokuEndReason.five, GomokuOutcome.lost))
        assertEquals("판이 가득 찼어요", GomokuScreenText.aiEndReason(GomokuEndReason.boardFull, GomokuOutcome.draw), "AI 판 문구는 루비를 말하지 않는다")
    }

    @Test
    fun opponentStatusNamesThePartnerWithTheRightParticle() {
        val a = user("a", "달토끼", inMatch = true)
        val b = user("b", "민트별", inMatch = true)
        val c = user("c", "솜사탕", inMatch = true)
        val live = listOf(
            GomokuLiveMatch("m", a, b, GomokuStake.five, SwiftDate(1_900_000_000.0)),
            GomokuLiveMatch("n", c, user("d", "abc"), GomokuStake.three, SwiftDate(1_900_000_000.0)),
        )
        assertEquals("대국 중 · 민트별과", GomokuScreenText.opponentStatus(a, live), "받침 있음 → 과")
        assertEquals("대국 중 · 달토끼와", GomokuScreenText.opponentStatus(b, live), "받침 없음 → 와")
        assertEquals("대국 중 · abc와", GomokuScreenText.opponentStatus(c, live), "한글이 아니면 와")
        assertEquals("앱 업데이트가 필요해요", GomokuScreenText.opponentStatus(user("x", "x", capable = false), live))
        assertEquals("근무 안 함", GomokuScreenText.opponentStatus(user("y", "y", working = false), live))
    }

    @Test
    fun rankSinceIsAKstCalendarDay() {
        // 전적 컷 2026-10-01 00:00 KST = 2026-09-30 15:00 UTC. 기기 시간대로 조립하면 비KST 기기에서 "9월 30일부터"가 된다.
        val cut = SwiftDate(1_790_780_400.0)
        assertEquals("10월 1일부터", GomokuScreenText.rankSince(cut))
        assertEquals("9월 30일부터", GomokuScreenText.rankSince(cut.addingTimeInterval(-1.0)), "KST 자정 직전은 전날")
    }

    @Test
    fun matchChromeTextSplitsHumanAndAI() {
        val human = GomokuPhoneMatchChrome(isAI = false)
        val ai = GomokuPhoneMatchChrome(isAI = true)
        assertEquals("앱을 나가도 차례 시간은 흘러요", GomokuScreenText.clockLine(human))
        assertEquals("화면을 떠나거나 앱을 나가면 내 시계가 멈춰요 · 한 수 30초가 지나면 자동으로 놓여요", GomokuScreenText.clockLine(ai))
        assertEquals("같은 판돈으로 다시 신청", GomokuScreenText.rematchTitle(human))
        assertEquals("같은 색으로 다시 두기", GomokuScreenText.rematchTitle(ai))
        assertEquals("흑 · AI가 생각 중이에요", GomokuScreenText.waitingLine(ai, GomokuColor.black))
        assertEquals("흑 · 상대 차례예요", GomokuScreenText.waitingLine(human, GomokuColor.black))
        assertEquals("상대 · AI", GomokuScreenText.opponentLine(ai, "누구"))
    }

    @Test
    fun rankingBranchOrderKeepsHeldRowsAndPutsSoonBeforeEmpty() {
        assertEquals(GomokuRankingPlan.Content.rows, GomokuRankingPlan.content(hasRows = true, rankingUnavailable = true, hasLoaded = true, lastFailed = true), "행을 들고 있는데 버렸다")
        assertEquals(GomokuRankingPlan.Content.soon, GomokuRankingPlan.content(hasRows = false, rankingUnavailable = true, hasLoaded = true, lastFailed = false), "곧 열려요가 아니라 빈 목록이 됐다")
        assertEquals(GomokuRankingPlan.Content.empty, GomokuRankingPlan.content(hasRows = false, rankingUnavailable = false, hasLoaded = true, lastFailed = false))
        assertEquals(GomokuRankingPlan.Content.failed, GomokuRankingPlan.content(hasRows = false, rankingUnavailable = false, hasLoaded = false, lastFailed = true))
        assertEquals(GomokuRankingPlan.Content.loading, GomokuRankingPlan.content(hasRows = false, rankingUnavailable = false, hasLoaded = false, lastFailed = false))
    }

    @Test
    fun tabBarHidesOnlyWhileAMatchOrResultIsUp() {
        assertEquals(false, GomokuTabBarPolicy.hidesTabBar(GomokuPhase.lobby, hasMatch = false))
        assertEquals(true, GomokuTabBarPolicy.hidesTabBar(GomokuPhase.playing, hasMatch = true))
        assertEquals(true, GomokuTabBarPolicy.hidesTabBar(GomokuPhase.result, hasMatch = true))
        assertEquals(false, GomokuTabBarPolicy.hidesTabBar(GomokuPhase.playing, hasMatch = false), "판이 없으면 로비가 선다")
    }
}
