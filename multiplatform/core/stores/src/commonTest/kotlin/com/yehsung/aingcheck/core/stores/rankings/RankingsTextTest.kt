// 원본: Tests/CheckMobileKitTests/RankingsRedesignTests.swift(문구) · RankingsStoreTests.swift:317-337(texts) ·
//       RankingsLeagueWeekTests.swift:452-547(pastWeekTexts · displayPageFacts) @ 1b8260d
// 기대값은 Swift 시험의 글자 리터럴 그대로다(RankingsText 상수로 기대값을 쓰지 않는다 — 문구 오타가 거울로 초록이 되지 않게).
package com.yehsung.aingcheck.core.stores.rankings

import com.yehsung.aingcheck.core.rules.insights.TeamLeagueWeekNavigator
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardEntry
import com.yehsung.aingcheck.core.wire.models.TeamLeaderboardEntry
import com.yehsung.aingcheck.core.wire.models.TokenBoardEntry
import com.yehsung.aingcheck.core.wire.models.leagueDisplay
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RankingsTextTest {
    /** 2026-09-24 14:05 KST(목). 이번 주 월요일 = 2026-09-21 → 한 주 과거가 9월 14일 주. */
    private val thursday = SwiftISO8601.parse("2026-09-24T05:05:00Z")!!

    private fun weekKey(offset: Int) = TeamLeagueWeekNavigator.key(offset, thursday.timeIntervalSince1970)

    private fun team(total: Long, members: Long, working: Long = 0, goalHours: Long = 40) =
        TeamLeaderboardEntry("t", "팀", goalHours, total, working, members)

    private fun weekTeam(
        id: String = "t",
        total: Long = 51L * 3600 + 12 * 60,
        members: Long = 5,
        working: Long = 3,
        weekStart: String? = null,
        participants: Long? = 4,
    ) = TeamLeaderboardEntry(id, "팀", 40, total, working, members, null, weekStart, participants)

    private fun tokens(total: Long, today: Long = 0, todayDate: String = "2026-09-17") =
        TokenBoardEntry("u", "사람", null, total, total, 0, 0, 0, 0, 0, today, todayDate)

    @Test
    fun boardSubtitles() {
        assertEquals("이번 주 · 월요일 0시에 새로 시작해요", RankingsText.boardSubtitle(RankingsBoard.league))
        assertEquals("이번 달 · 1일에 새로 시작해요", RankingsText.boardSubtitle(RankingsBoard.tokens))
        assertEquals("오늘 · 자정에 마감해요", RankingsText.boardSubtitle(RankingsBoard.minigame))
        assertEquals("팀 리그", RankingsText.segmentTitle(RankingsBoard.league))
        assertEquals("AI 토큰", RankingsText.segmentTitle(RankingsBoard.tokens))
        assertEquals("미니게임", RankingsText.segmentTitle(RankingsBoard.minigame))
    }

    @Test
    fun leagueRowTexts() {
        val now = SessionClock.demoInstant
        val busy = team(total = 5L * (25 * 3600 + 7 * 60), members = 5, working = 3)
        assertEquals("25시간 07분", RankingsText.leagueValue(busy))
        assertEquals("63%", RankingsText.leaguePercentText(busy))
        assertEquals("5명 · 3명 근무 중 · 목표 40시간", RankingsText.leagueSubtitle(busy, now))
        assertEquals("1인당 평균", RankingsText.leagueAverageHint)
        assertEquals("평균 25시간 07분", RankingsText.leagueAverage(busy))

        val idle = team(total = 3L * 3600, members = 3, goalHours = 45)
        assertEquals("3명 · 근무 중 없음 · 목표 45시간", RankingsText.leagueSubtitle(idle, now))

        val empty = team(total = 0, members = 3)
        assertEquals("—", RankingsText.leagueValue(empty))
        assertEquals("—", RankingsText.leaguePercentText(empty))
        assertEquals("3명 · 이번 주 기록 없음 · 목표 40시간", RankingsText.leagueSubtitle(empty, now))
        for (subtitle in listOf(busy, idle, empty).map { RankingsText.leagueSubtitle(it, now) }) {
            assertFalse(subtitle.endsWith("·") || subtitle.endsWith("· ") || subtitle.startsWith("·"), subtitle)
            assertFalse("근무중" in subtitle, "붙여 쓴 '근무중'이 남았다: $subtitle")
        }
    }

    @Test
    fun leagueBarKinds() {
        val halfway = team(total = 2L * 20 * 3600, members = 2)
        assertEquals(RankingsText.LeagueBarKind.gauge, RankingsText.leagueBarKind(halfway, isMyTeam = true))
        assertEquals(RankingsText.LeagueBarKind.accent, RankingsText.leagueBarKind(halfway, isMyTeam = false))
        val done = team(total = 2L * 41 * 3600, members = 2)
        assertEquals(RankingsText.LeagueBarKind.done, RankingsText.leagueBarKind(done, isMyTeam = false))
        assertEquals(RankingsText.LeagueBarKind.done, RankingsText.leagueBarKind(done, isMyTeam = true))
    }

    @Test
    fun tokenRowTexts() {
        val top = tokens(total = 5_014_407_391, today = 184_523_456)
        assertEquals("50.1억", RankingsText.tokenTotalCompact(top))
        assertEquals("오늘 +1.8억", RankingsText.tokenTodayCompact(top, "2026-09-17"))
        assertEquals("Claude 50.1억", TokenBoardText.toolUsageLabel(top), "도구 줄과 큰 숫자가 같은 말로 읽힌다")
        assertEquals("638만", RankingsText.tokenTotalCompact(tokens(total = 6_382_702)))
        assertEquals("8,432", RankingsText.tokenTotalCompact(tokens(total = 8_432)))
        assertEquals("오늘 +0", RankingsText.tokenTodayCompact(tokens(total = 900, today = 99, todayDate = "2026-09-10"), "2026-09-17"),
            "지난 날짜의 증가량은 오늘이 아니다")
        // 정확한 값은 보이스오버가 읽는다(단위 축약은 화면만).
        val spoken = RankingsText.tokenRowAccessibility(1, top, isMe = false, isPrivate = false, todayKey = null)
        assertEquals("1위, 사람, 5,014,407,391 토큰, Claude 50.1억", spoken)
        assertEquals("1위, 사람, 나, 비공개, 5,014,407,391 토큰, Claude 50.1억, 오늘 +184,523,456 토큰",
            RankingsText.tokenRowAccessibility(1, top, isMe = true, isPrivate = true, todayKey = "2026-09-17"))

        assertEquals(1.0, RankingsText.tokenBarFraction(5_014_407_391, 5_014_407_391))
        assertTrue(abs(RankingsText.tokenBarFraction(6_382_702, 5_014_407_391) - 0.00127) < 0.0001)
        assertEquals(0.0, RankingsText.tokenBarFraction(10, 0))
        assertEquals(1.0, RankingsText.tokenBarFraction(20, 10))
    }

    /** 상금·정족수(0.3.64 에 두 번 뒤집힌 상수 — 사용자 결정 20·10·5, 정족수 5명). 경계 4·5·6 을 다 본다. */
    @Test
    fun prizeAndQuorumTexts() {
        assertEquals(listOf(20, 10, 5), RankingsText.rubyPrizes)
        assertEquals("자정에 1·2·3등에게 루비 20·10·5", RankingsText.prizeCaption)
        assertEquals("루비 +20 받음", RankingsText.awardedChip)
        assertEquals("오늘은 아직 아무도 안 했어요 · 5명부터 지급", RankingsText.quorumCaption(0))
        assertEquals("오늘 3명 참여 · 5명부터 지급", RankingsText.quorumCaption(3))
        assertEquals("오늘 4명 참여 · 5명부터 지급", RankingsText.quorumCaption(4))
        assertEquals("오늘 5명 참여 · 지급 조건 충족", RankingsText.quorumCaption(5), "정족수 경계(>=)")
        assertEquals("오늘 6명 참여 · 지급 조건 충족", RankingsText.quorumCaption(6))
        assertEquals("1000점", RankingsText.score(1000))
        assertEquals("953점", RankingsText.score(953))
    }

    @Test
    fun emptyAndFailureTexts() {
        assertEquals("불러오는 중…", RankingsText.tokenEmpty(hasLoaded = false, isLoading = true, hasFailed = false, isCurrentMonth = true))
        assertEquals("순위를 불러오지 못했어요", RankingsText.tokenEmpty(hasLoaded = false, isLoading = false, hasFailed = true, isCurrentMonth = true))
        assertEquals("아직 이번 달 소모량을 올린 사용자가 없어요", RankingsText.tokenEmpty(hasLoaded = true, isLoading = false, hasFailed = false, isCurrentMonth = true))
        assertEquals("이 달에는 기록이 없어요", RankingsText.tokenEmpty(hasLoaded = true, isLoading = false, hasFailed = false, isCurrentMonth = false))
        assertEquals("아직 이번 주 근무한 팀이 없어요", RankingsText.leagueEmpty(hasLoaded = true, isLoading = false, hasFailed = false, unfilteredCount = 3))
        assertEquals("리그를 불러오지 못했어요", RankingsText.leagueEmpty(hasLoaded = false, isLoading = false, hasFailed = true, unfilteredCount = 0))
        assertEquals("불러오는 중…", RankingsText.leagueEmpty(hasLoaded = false, isLoading = true, hasFailed = false, unfilteredCount = 0))
        assertEquals("아직 이번 주 근무한 팀이 없어요", RankingsText.leagueEmpty(hasLoaded = true, isLoading = false, hasFailed = false, unfilteredCount = 0))
        assertEquals("아직 기록이 없어요 — 첫 기록의 주인공이 되세요", RankingsText.miniGameEmptyText(hasLoaded = true, hasFailed = false))
        assertEquals("순위를 불러오지 못했어요", RankingsText.miniGameEmptyText(hasLoaded = false, hasFailed = true))
        assertEquals("불러오는 중…", RankingsText.miniGameEmptyText(hasLoaded = false, hasFailed = false))
        assertEquals("2025년 12월 AI 토큰 소모량", RankingsText.tokenTitle("2025-12", SessionClock.demoInstant))
    }

    @Test
    fun pastWeekTexts() {
        val now = thursday
        val past = weekKey(1)
        assertEquals("5명 중 4명 참여", RankingsText.leagueParticipation(weekTeam(weekStart = past)))
        assertEquals("5명 중 참여 인원 모름", RankingsText.leagueParticipation(weekTeam(weekStart = past, participants = null)))

        assertNull(RankingsText.leagueWeekNote(isPastWeek = false, myTeamMissing = false))
        assertNull(RankingsText.leagueWeekNote(isPastWeek = false, myTeamMissing = true))
        assertEquals("인원은 그 주 기준이에요", RankingsText.leagueWeekNote(isPastWeek = true, myTeamMissing = false))
        assertEquals("그 주엔 아직 우리 팀이 없었어요", RankingsText.leagueWeekNote(isPastWeek = true, myTeamMissing = true))

        assertEquals("불러오는 중…", RankingsText.leagueEmpty(hasLoaded = false, isLoading = true, hasFailed = false, unfilteredCount = 0, isPastWeek = true))
        assertEquals("순위를 불러오지 못했어요", RankingsText.leagueEmpty(hasLoaded = false, isLoading = false, hasFailed = true, unfilteredCount = 0, isPastWeek = true))
        assertEquals("불러오는 중…", RankingsText.leagueEmpty(hasLoaded = false, isLoading = false, hasFailed = false, unfilteredCount = 0, isPastWeek = true),
            "취소된 조회가 '그 주엔 근무한 팀이 없었어요'로 둔갑했다")
        assertEquals("그 주엔 근무한 팀이 없었어요", RankingsText.leagueEmpty(hasLoaded = true, isLoading = false, hasFailed = false, unfilteredCount = 0, isPastWeek = true))
        assertEquals("순위를 불러오지 못했어요", RankingsText.leagueFailedText(isPastWeek = true))
        assertEquals("리그를 불러오지 못했어요", RankingsText.leagueFailedText(isPastWeek = false))

        val pastTeam = weekTeam(weekStart = past)
        assertTrue(pastTeam.isPastWeek(now))
        assertEquals("각자 목표 40시간 · 총 51시간 12분 · 5명 중 4명 참여", RankingsText.leagueCaption(pastTeam, now))
        assertEquals("5명 중 4명 참여 · 목표 40시간", RankingsText.leagueSubtitle(pastTeam, now))
        assertEquals(2, RankingsText.leagueSubtitle(pastTeam, now).split(" · ").size, "과거 주 부제 조각은 둘이다")
        assertFalse("근무" in RankingsText.leagueSubtitle(weekTeam(weekStart = past, participants = null), now))
        val row = RankingsText.leagueRowAccessibility(2, pastTeam, isMyTeam = false, now = now)
        assertEquals("2위, 팀, 평균 10시간 14분, 목표 대비 26%, 각자 목표 40시간 · 총 51시간 12분 · 5명 중 4명 참여", row)
        assertFalse("주 " in row || row.endsWith("주"), "행 라벨에 주 이름이 들어갔다")
        assertEquals("1위, 팀, 우리 팀, 평균 10시간 14분, 목표 대비 26%, 각자 목표 40시간 · 총 51시간 12분 · 5명 · 3명 근무중",
            RankingsText.leagueRowAccessibility(1, weekTeam(weekStart = weekKey(0)), isMyTeam = true, now = now))

        val thisWeek = weekTeam(weekStart = weekKey(0))
        assertFalse(thisWeek.isPastWeek(now))
        assertEquals("5명 · 3명 근무 중 · 목표 40시간", RankingsText.leagueSubtitle(thisWeek, now))
        assertEquals("각자 목표 40시간 · 총 51시간 12분 · 5명 · 3명 근무중", RankingsText.leagueCaption(weekTeam(weekStart = null), now),
            "구버전 RPC(week_start 없음)는 이번 주로 읽는다")
        assertFalse(weekTeam(weekStart = "not-a-week").isPastWeek(now), "읽을 수 없는 week_start 는 이번 주로 본다")

        assertEquals("팀별 이번 주", RankingsText.leagueTitle(weekKey(0), now))
        assertEquals("팀별 9월 14일 주", RankingsText.leagueTitle(past, now))
        assertEquals("9월 14일 주", RankingsText.leagueWeekName(past, now))
        assertEquals("이전 주", RankingsText.previousWeek)
        assertEquals("다음 주", RankingsText.nextWeek)
        assertEquals("6주 전까지만 볼 수 있어요", RankingsText.noEarlierWeek)
        assertEquals("이번 주가 가장 최근이에요", RankingsText.noLaterWeek)
        assertEquals("이번 달이 가장 최근이에요", RankingsText.noLaterMonth)
    }

    @Test
    fun displayPageFacts() {
        val past = weekKey(1)
        val rows = listOf(
            weekTeam(id = "t-high", total = 288_000, weekStart = past),
            weekTeam(id = "mine", total = 0, weekStart = past),
            weekTeam(id = "t-zero", total = 0, weekStart = past),
        )
        val page = rows.leagueDisplay("mine", NaturalKoNameCollation)
        assertEquals(listOf("t-high", "mine"), page.entries.map { it.id })
        assertEquals(3L, page.unfilteredCount)
        assertFalse(page.myTeamMissing)
        assertTrue(rows.leagueDisplay("gone", NaturalKoNameCollation).myTeamMissing, "그 주엔 아직 우리 팀이 없었다")
        assertFalse(emptyList<TeamLeaderboardEntry>().leagueDisplay("mine", NaturalKoNameCollation).myTeamMissing,
            "로드 전/실패(원본 0건)를 '그 주엔 팀이 없었다'로 읽으면 안 된다")
    }

    @Test
    fun miniGameRowAccessibility() {
        val entry = MiniGameBoardEntry(userID = "u-a", name = "먼저", avatarURL = null, bestScore = 900, bestAt = null, plays = 3, center = "서울")
        assertEquals("1위, 먼저, 서울센터, 900점, 나", RankingsText.miniGameRowAccessibility(1, entry, isMe = true))
        assertEquals("2위, 먼저, 900점", RankingsText.miniGameRowAccessibility(2, entry.copy(center = null), isMe = false))
    }
}
