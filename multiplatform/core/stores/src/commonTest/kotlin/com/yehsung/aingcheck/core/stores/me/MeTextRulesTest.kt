// 원본: Tests/CheckMobileKitTests/MeTextTests.swift · MeWeeklyWorkTests.swift(규칙 몫) · MeDailyMissionViewTests.swift · MeRainbowViewTests.swift(타일 상태) · V1013MissionPageTests.swift(미션 줄 글자) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.rules.achievements.AchievementStatus
import com.yehsung.aingcheck.core.rules.achievements.DailyMissionStatus
import com.yehsung.aingcheck.core.rules.character.gift.CakeGiftText
import com.yehsung.aingcheck.core.rules.weekly.WeeklyWorkStatus
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MeTextRulesTest {
    private fun mission(key: String, achieved: Boolean, claimed: Boolean, reward: Long = 5, progress: Long = 0) = AchievementStatus.Mission.of(
        key = key, series = key, tier = 1, title = "$key 한 판", detail = "보조", reward = reward, target = 1, progress = progress,
        achieved = achieved, claimed = claimed, achievedAtMs = null, claimedAtMs = null, sort = 1,
    )

    @Test
    fun missionsRowDetailNamesTheThreeGroupsInOrder() {
        val heads = listOf(MeText.dailyMissionsTitle, MeText.weeklyTitle, MeText.missionsTitle).map { it.split(' ').first() }
        assertEquals(listOf("일일", "이번", "누적"), heads)
        var from = 0
        for (head in heads) {
            val at = MeText.missionsRowDetail.indexOf(head, from)
            assertTrue(at >= from, "'$head' 가 순서대로 있어야 한다: ${MeText.missionsRowDetail}")
            from = at + head.length
        }
        assertTrue("도전 미션" !in MeText.missionsRowDetail, "1.0.13 에 「누적 미션」으로 개명됐다")
    }

    @Test
    fun dailyRowContentHasThreeShapesAndShowsFailureOnlyWhereTheButtonIs() {
        val progress = MeDailyMissionRowContent.make(DailyMissionStatus.Mission("tetris", mission("daily_tetris", achieved = false, claimed = false)))
        assertEquals("+5", progress.rewardChip)
        assertNull(progress.claimAmount)
        assertEquals("0/1", progress.progress)
        val claimable = MeDailyMissionRowContent.make(DailyMissionStatus.Mission("gomoku", mission("daily_gomoku", true, false, progress = 1)), failed = true)
        assertNull(claimable.rewardChip, "칩 '+5' 옆 버튼 '+5' 는 헷갈린다 — 칩을 감춘다")
        assertEquals(5L, claimable.claimAmount)
        assertEquals(MeText.claimFailed, claimable.caption)
        assertTrue(claimable.showsFailure)
        assertEquals("circle.grid.3x3.fill", claimable.icon)
        val claimed = MeDailyMissionRowContent.make(DailyMissionStatus.Mission("flappy", mission("daily_flappy", true, true, progress = 1)), failed = true)
        assertEquals(MeText.claimedMark, claimed.claimedMark)
        assertEquals("보조", claimed.caption, "버튼이 없는 줄은 실패를 말하지 않는다")
        assertEquals(MeText.missionFallbackIcon, MeText.dailyMissionIcon("새게임"))
    }

    @Test
    fun tileStatusNeverShowsARubyPriceForGachaOrGiftOnlyCharacters() {
        assertEquals(MeCharacterTileStatus.Content.Acquire("뽑기 · 조각 20"), MeCharacterTileStatus.GachaOnly(20).content)
        assertEquals(MeCharacterTileStatus.Content.Acquire("뽑기 전용"), MeCharacterTileStatus.GachaOnly(null).content)
        assertEquals(MeCharacterTileStatus.Content.Locked(CakeGiftText.lockedCaption), MeCharacterTileStatus.GiftOnly.content)
        assertEquals(MeCharacterTileStatus.Content.Ruby(60, 10), MeCharacterTileStatus.Price(60, 10).content)
        assertEquals("무지개 아잉이", MeCharacterName.display("aing_rainbow"))
        assertEquals("future_id", MeCharacterName.display("future_id"), "모르는 캐릭터는 id 그대로(이름을 지어내지 않는다)")
    }

    @Test
    fun knownIDsFollowTheBuiltInOrderThenSorted() {
        assertEquals(
            listOf("aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco", "fox", "ghost", "jellyfish", "robot", "shiba", "squirrel"),
            MeCharacterCards.knownIDs,
        )
        assertEquals("aing", MeCharacterCards.equippedID(" "), "빈 착용값 = 아잉")
        assertEquals("aing", MeCharacterCards.equippedID("future_id"), "모르는 착용값 = 아잉(서버 값은 건드리지 않는다)")
        assertEquals("robot", MeCharacterCards.equippedID(" robot\n"))
    }

    @Test
    fun displayNameNormalizationMirrorsTheServer() {
        // NFC · 제어/서식 문자 제거(ZWJ 는 남긴다) · 연속 공백 한 칸 · 앞뒤 공백 제거.
        assertEquals("가 나", MeText.normalizedDisplayName("  가\u0000  ​나\t"))
        assertEquals("👩‍💻 코드", MeText.normalizedDisplayName("👩‍💻　　코드"))
        assertEquals(5, MeText.displayNameLength("\uD83D\uDC69\u200D\uD83D\uDCBB  a"), "서버 눈금 = 코드포인트(👩 · ZWJ · 💻 · 공백 하나 · a)")
        assertEquals("유령을", "유령" + MeText.particle("유령", "을", "를"))
        assertEquals("여우를", "여우" + MeText.particle("여우", "을", "를"))
        assertEquals("fox를", "fox" + MeText.particle("fox", "을", "를"))
    }

    @Test
    fun percentRoundsHalfAwayFromZeroAndShortfallStaysBelowOneHundred() {
        assertEquals(13, MeText.percent(workedSeconds = 1, goalSeconds = 8), "12.5 → 13(Swift .rounded())")
        assertEquals(99, MeText.shortfallPercent(workedSeconds = 9_995, goalSeconds = 10_000), "99.95 → 100 이 아니라 99")
        assertEquals(999, MeText.percent(workedSeconds = 1_000_000, goalSeconds = 1))
    }

    @Test
    fun versionAndFeedbackLinesUseThePlatformName() {
        val android = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 7, "0.2.0"), "Android 15")
        assertEquals("아잉체크 Android 0.2.0 (7)", MeText.versionLine(android))
        assertEquals("앱 0.2.0 (7) · Android 15", MeText.feedbackVersionLine(android.feedbackAppVersion, android.osVersion))
        assertEquals("앱 0.2.0 (7) · Android 15 정보가 함께 전송돼요", MeText.feedbackAutoAttach(android.feedbackAppVersion, android.osVersion))
        assertEquals("앱 0.1.0 (1)", MeText.feedbackVersionLine("iOS 0.1.0 (1)", null))
    }

    @Test
    fun weeklySeenRoundTripsAndLegacyServersAnnounceNewlyClaimedTiers() {
        val seen = WeeklyWorkSeen("2026-09-14", setOf(40L, 20L))
        assertEquals("2026-09-14|20,40", seen.encoded)
        assertEquals(seen, WeeklyWorkSeen.decode(seen.encoded))
        assertEquals(WeeklyWorkSeen("2026-09-14", emptySet()), WeeklyWorkSeen.decode("2026-09-14|"))
        assertNull(WeeklyWorkSeen.decode("|20"))
        assertNull(WeeklyWorkSeen.decode("2026-09-14"))
        assertEquals(setOf(20L), WeeklyWorkSeen.decode("2026-09-14|20,x, 40")?.claimedHours, "숫자가 아닌 조각은 버린다")

        val tiers = listOf(WeeklyWorkStatus.Tier(20, 20, claimed = true), WeeklyWorkStatus.Tier(40, 50, claimed = true), WeeklyWorkStatus.Tier(60, 200, claimed = false))
        val legacy = WeeklyWorkStatus.of(weekStart = "2026-09-14", workedSeconds = 150_000, tiers = tiers)
        assertEquals(emptyList(), WeeklyWorkRules.newGrants(null, legacy), "첫 조회는 기준만 잡는다")
        assertEquals(listOf(40L), WeeklyWorkRules.newGrants(WeeklyWorkSeen("2026-09-14", setOf(20L)), legacy).map { it.hours })
        assertEquals(listOf(20L, 40L), WeeklyWorkRules.newGrants(WeeklyWorkSeen("2026-09-07", setOf(20L, 40L)), legacy).map { it.hours }, "지난주 기록이면 이번 주 칸은 다 처음")
        val claimServer = WeeklyWorkStatus.of(weekStart = "2026-09-14", workedSeconds = 150_000, tiers = tiers, claimableRuby = 0, pending = emptyList())
        assertEquals(emptyList(), WeeklyWorkRules.newGrants(WeeklyWorkSeen("2026-09-14", emptySet()), claimServer), "받기 서버는 본 기록과 비교하지 않는다")
        assertEquals(WeeklyWorkGrantNotice(70, listOf(20L, 40L)), WeeklyWorkRules.notice(WeeklyWorkRules.newGrants(WeeklyWorkSeen("2026-09-07", emptySet()), legacy)))
        assertTrue(WeeklyWorkRules.shouldApplyRuby(10, 3, 3))
        assertTrue(!WeeklyWorkRules.shouldApplyRuby(10, 3, 4), "떠난 뒤 한 번이라도 쓰였으면 쓰지 않는다")
        assertTrue(!WeeklyWorkRules.shouldApplyRuby(null, 3, 3))
        assertTrue(WeeklyWorkRules.weekHasRolled(legacy.copy(nextWeekStart = "2026-09-21"), SwiftDate(1_790_182_800.0)), "다음 주 월 0시(KST) 이후")
    }

    @Test
    fun planLabelAndCardBudget() {
        assertEquals("plus", AILimitPlanLabelContract.normalized(" plus\n"))
        assertNull(AILimitPlanLabelContract.normalized("   "))
        assertEquals("가".repeat(32), AILimitPlanLabelContract.normalized("가".repeat(32)))
        assertNull(AILimitPlanLabelContract.normalized("가".repeat(33)))
        val inner = MeAILimitCardBudget.innerWidth(MeAILimitCardBudget.narrowestScreenWidth)
        assertEquals(311.0, inner)
        assertTrue(MeAILimitCardBudget.barWidth(inner) >= MeAILimitCardBudget.minimumBarWidth, "가장 좁은 기기에서도 바가 하한 위")
        assertEquals(MeAILimitCardBudget.cellWidth(inner) * 2 + MeAILimitCardBudget.nameColumnWidth + MeAILimitCardBudget.nameGap + MeAILimitCardBudget.columnGap, inner)
        assertTrue(MeAILimitCardBudget.valueFits(MeAILimitCardBudget.worstValueWidth))
        assertTrue(MeAILimitCardBudget.deviceTailAlwaysFits(MeAILimitCardBudget.worstDeviceTailWidth, MeAILimitCardBudget.narrowestScreenWidth))
    }
}
