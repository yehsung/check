// 원본: Sources/check/CheckMenuView.swift:59-96(TopBanner 선언 순) · 130-133(isMainScreen) · 270-287(topBanner 고르기)
// W3-c2 BannerQueueTest — 맥 순위 전수 표(9칸의 모든 부분집합 512개) + 음성(이웃 두 칸을 바꾼 고르기는 반드시 빨강) + 맥 소스 대조.
package com.yehsung.aingcheck.desktop.pages.banners

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.AppNotice
import com.yehsung.aingcheck.desktop.pages.work.HomeTestKit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BannerQueueTest {
    /** 맥 270-284 의 줄 순서를 손으로 옮긴 표(구현을 읽어 만들지 않았다). */
    private val macOrder = listOf(
        TopBanner.LONG_SESSION, TopBanner.GOMOKU_INVITE, TopBanner.CHESS_INVITE, TopBanner.TETRIS_INVITE, TopBanner.RETRO,
        TopBanner.FEEDBACK_REPLY, TopBanner.CAKE_GIFT, TopBanner.UPDATE, TopBanner.APP_NOTICE,
    )

    private val invite = DuelInviteBanner("m-1", "합성상대", 5, SwiftDate(1_800_000_000.0))
    private val notice = AppNotice(id = "n-1", title = "합성 공지", body = "본문")

    /** 부분집합 하나 → 후보(로그인 · 소속 · 대결 깃발 켬 — 문은 모두 열고 순위만 잰다). */
    private fun candidatesOf(present: Set<TopBanner>) = BannerCandidates(
        isSignedIn = true,
        isTeamless = false,
        longSessionPrompt = TopBanner.LONG_SESSION in present,
        gomoku = invite.takeIf { TopBanner.GOMOKU_INVITE in present },
        chess = invite.takeIf { TopBanner.CHESS_INVITE in present },
        tetris = invite.takeIf { TopBanner.TETRIS_INVITE in present },
        retroDue = TopBanner.RETRO in present,
        feedbackReplyUnseen = TopBanner.FEEDBACK_REPLY in present,
        cakeGiftOpen = TopBanner.CAKE_GIFT in present,
        updateAvailable = TopBanner.UPDATE in present,
        appNotice = notice.takeIf { TopBanner.APP_NOTICE in present },
        duelsEnabled = true,
    )

    private fun subsets(): Sequence<Set<TopBanner>> = (0 until (1 shl macOrder.size)).asSequence().map { mask ->
        macOrder.filterIndexed { i, _ -> mask and (1 shl i) != 0 }.toSet()
    }

    /** 고르기 하나를 전수 표와 대조해 어긋난 부분집합을 돌려준다(빈 목록 = 맥과 같다). */
    private fun violations(picker: (BannerCandidates) -> TopBanner?, order: List<TopBanner> = macOrder): List<String> =
        subsets().mapNotNull { present ->
            val expected = order.firstOrNull { it in present }
            val actual = picker(candidatesOf(present))
            if (expected == actual) null else "present=$present expected=$expected actual=$actual"
        }.toList()

    /** 순서 목록대로 고르는 돌연변이 고르기(음성 대조용). */
    private fun orderedPicker(order: List<TopBanner>): (BannerCandidates) -> TopBanner? = { c ->
        order.firstOrNull { b ->
            when (b) {
                TopBanner.LONG_SESSION -> c.longSessionPrompt
                TopBanner.GOMOKU_INVITE -> c.gomoku != null
                TopBanner.CHESS_INVITE -> c.chess != null
                TopBanner.TETRIS_INVITE -> c.tetris != null
                TopBanner.RETRO -> c.retroDue
                TopBanner.FEEDBACK_REPLY -> c.feedbackReplyUnseen
                TopBanner.CAKE_GIFT -> c.cakeGiftOpen
                TopBanner.UPDATE -> c.updateAvailable
                TopBanner.APP_NOTICE -> c.appNotice != null
            }
        }
    }

    @Test
    fun everySubsetPicksTheMostUrgentInMacOrder() {
        val bad = violations(BannerQueue::pick)
        assertTrue(bad.isEmpty(), "맥 순위와 어긋남 ${bad.size}건: ${bad.take(5)}")
        assertNull(BannerQueue.pick(candidatesOf(emptySet())), "후보 없으면 배너 없음")
    }

    /** 음성: 이웃 두 칸을 하나씩 바꾼 여덟 돌연변이 모두 전수 표가 잡는다(표가 순서를 실제로 잰다는 증거). */
    @Test
    fun swappingAnyAdjacentPairTurnsTheTableRed() {
        for (k in 0 until macOrder.size - 1) {
            val mutant = macOrder.toMutableList().also { val t = it[k]; it[k] = it[k + 1]; it[k + 1] = t }
            assertTrue(violations(orderedPicker(mutant)).isNotEmpty(), "${macOrder[k]}↔${macOrder[k + 1]} 바꿈을 못 잡았다")
        }
        assertTrue(violations(orderedPicker(macOrder)).isEmpty(), "맥 순서 그대로의 고르기는 초록이어야 한다")
    }

    /** 맥 270·283·284: 12시간은 메인 화면(로그인·소속)만, 업데이트만 로그인 없이, 나머지는 로그인 필요. */
    @Test
    fun gatesFollowMacSignInAndMainScreen() {
        val all = candidatesOf(macOrder.toSet())
        assertEquals(TopBanner.UPDATE, BannerQueue.pick(all.copy(isSignedIn = false)), "로그아웃이면 업데이트만")
        assertEquals(TopBanner.GOMOKU_INVITE, BannerQueue.pick(all.copy(isTeamless = true)), "무소속이면 12시간은 빠지고 대결 신청부터")
        assertNull(BannerQueue.pick(candidatesOf(setOf(TopBanner.APP_NOTICE)).copy(isSignedIn = false)), "공지는 로그인한 사람에게만")
        assertTrue(BannerQueue.isMainScreen(all) && !BannerQueue.isMainScreen(all.copy(isTeamless = true)))
    }

    /** W-3 #7 · W-6 #1: duels=false 면 대결 신청 배너 0 — 다음 후보로 넘어간다. */
    @Test
    fun duelsFlagOffHidesAllThreeInvites() {
        val duelsOnly = candidatesOf(setOf(TopBanner.GOMOKU_INVITE, TopBanner.CHESS_INVITE, TopBanner.TETRIS_INVITE))
        assertNull(BannerQueue.pick(duelsOnly.copy(duelsEnabled = false)))
        val withRetro = candidatesOf(setOf(TopBanner.GOMOKU_INVITE, TopBanner.CHESS_INVITE, TopBanner.TETRIS_INVITE, TopBanner.RETRO))
        assertEquals(TopBanner.RETRO, BannerQueue.pick(withRetro.copy(duelsEnabled = false)))
        assertNull(BannerQueue.duelInvite(TopBanner.RETRO, withRetro))
        assertEquals(invite, BannerQueue.duelInvite(TopBanner.CHESS_INVITE, withRetro))
    }

    /** 업데이트와 공지는 절대 같이 뜨지 않는다 — 둘 다면 업데이트(맥 89-91 · V0340). */
    @Test
    fun updateAndNoticeNeverTogether() {
        assertEquals(TopBanner.UPDATE, BannerQueue.pick(candidatesOf(setOf(TopBanner.UPDATE, TopBanner.APP_NOTICE))))
    }

    /** 그리는 자리(맥 466-531 위 · 554 형제 · 566-572 헤더 아래). */
    @Test
    fun slotsMatchMacPlacement() {
        assertEquals(BannerQueue.Slot.HEADER_SIBLING, BannerQueue.slotOf(TopBanner.LONG_SESSION))
        for (b in listOf(TopBanner.GOMOKU_INVITE, TopBanner.CHESS_INVITE, TopBanner.TETRIS_INVITE)) assertEquals(BannerQueue.Slot.BELOW_HEADER, BannerQueue.slotOf(b))
        for (b in listOf(TopBanner.RETRO, TopBanner.FEEDBACK_REPLY, TopBanner.CAKE_GIFT, TopBanner.UPDATE, TopBanner.APP_NOTICE)) {
            assertEquals(BannerQueue.Slot.ABOVE_HEADER, BannerQueue.slotOf(b))
        }
    }

    /** 맥 소스 대조: topBanner 의 `return .x` 순서 = enum 선언 순서 = 코틀린 TopBanner 순서 = 손 표. 맥이 배너를 더하면 여기가 빨강. */
    @Test
    fun macSourceOrderMatches() {
        val src = HomeTestKit.stripLineComments(HomeTestKit.swiftSource("Sources/check/CheckMenuView.swift"))
        val pickBlock = src.substringAfter("private var topBanner: TopBanner? {").substringBefore("return nil")
        val picked = Regex("""return \.(\w+)""").findAll(pickBlock).map { it.groupValues[1] }.toList()
        val enumBlock = src.substringAfter("enum TopBanner {").substringBefore("static let inlineBannerHeight")
        val declared = Regex("""case (\w+)""").findAll(enumBlock).map { it.groupValues[1] }.toList()
        val kotlin = TopBanner.entries.map { it.swiftCase }
        assertEquals(macOrder.map { it.swiftCase }, picked, "맥 topBanner 고르기 순서")
        assertEquals(picked, declared, "맥 enum 선언 순서")
        assertEquals(picked, kotlin, "코틀린 TopBanner 순서")
    }
}
