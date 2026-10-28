// 원본: Tests/CheckMobileKitTests/NowRedesignTests.swift(문구·서식) · NowStoreTests.swift:783-816(timeMath · draftRules) @ 1b8260d
// 기대값은 Swift 시험의 글자 리터럴 그대로다(구현 상수로 기대값을 쓰지 않는다 — 문구 오타가 거울로 초록이 되지 않게).
package com.yehsung.aingcheck.core.stores.now

import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import kotlinx.coroutines.CancellationException
import kotlinx.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class NowModelsTest {
    private val now = SessionClock.demoInstant
    private fun date(iso: String): SwiftDate = SwiftISO8601.parse(iso)!!

    @Test
    fun hoursMinutesTextFloorsAndDropsZeroParts() {
        assertEquals("24시간 48분", NowFormat.hoursMinutesText(89_280))
        assertEquals("4시간 10분", NowFormat.hoursMinutesText(15_000))
        assertEquals("1시간", NowFormat.hoursMinutesText(3_600))
        assertEquals("49분", NowFormat.hoursMinutesText(2_999))
        assertEquals("0분", NowFormat.hoursMinutesText(59))
        assertEquals("0분", NowFormat.hoursMinutesText(-5))
        // 39시간 59분 59초를 "40시간"으로 올리지 않는다(목표를 채운 것처럼 보이지 않게).
        assertEquals("39시간 59분", NowFormat.hoursMinutesText(40 * 3600 - 1))
    }

    @Test
    fun kstClockAndDateIndependentOfDeviceZone() {
        assertEquals("10:20", NowFormat.clockTime(date("2026-09-17T01:20:00Z")))
        assertEquals("0:05", NowFormat.clockTime(date("2026-09-16T15:05:00Z")))
        assertEquals("9월 17일 목요일", NowFormat.longDate(now))
        // UTC 로는 17일 16시지만 KST 로는 18일 금요일 새벽이다.
        assertEquals("9월 18일 금요일", NowFormat.longDate(date("2026-09-17T16:00:00Z")))
        assertEquals("9월 21일 월요일", NowFormat.longDate(date("2026-09-20T15:00:00Z")), "요일 표의 월요일 자리")
        assertEquals("9월 20일 일요일", NowFormat.longDate(date("2026-09-20T14:59:59Z")), "요일 표의 일요일 자리(isoDayNumber 7 → 0)")
    }

    @Test
    fun headerSubtitles() {
        assertEquals("9월 17일 목요일 · 아잉 데모팀", NowText.expandedSubtitle("9월 17일 목요일", "아잉 데모팀"))
        assertEquals("9월 17일 목요일", NowText.expandedSubtitle("9월 17일 목요일", null))
        assertEquals("9월 17일 목요일", NowText.expandedSubtitle("9월 17일 목요일", ""))
        assertEquals("5:10:00 · 이번 주 62%", NowText.collapsedSubtitle("5:10:00", 62))
    }

    @Test
    fun workingRowTexts() {
        assertEquals("연결 끊김 · 마지막 확인 13분 전", NowText.staleLastSeen("13분 전"))
        assertEquals("연결 끊김", NowText.staleLastSeen(null))
        assertEquals("6명", NowText.peopleCount(6))
        assertEquals("모래에게 말 걸기", NowText.talkTo("모래"))
        assertEquals("근무는 맥이나 이 탭 맨 위 버튼으로 시작하고 끝내요", NowText.workingFooter)
        assertEquals("근무 시작과 종료는 맥 앱에서 해요", NowText.workingFooterMacOnly)
        assertEquals("이번 세션 10:20부터", NowText.sessionSince("10:20"))
        assertEquals("/ 40시간", NowText.goalSuffix(40))
        assertEquals("지금 근무 중", NowText.workingTitle(null), "모를 때 '지금 근무 중 0' 이라고 하지 않는다")
        assertEquals("지금 근무 중 3", NowText.workingTitle(3))
    }

    /** 카드 상태 글자(출처별) — Swift `NowMyCard.stateText` 의 갈래 셋 + 비근무. 문구는 Swift 원문 리터럴. */
    @Test
    fun myCardStateTextPerOrigin() {
        fun card(working: Boolean, origin: NowWorkOrigin) = NowMyCard(working, false, null, 0, 0, 40, origin)
        assertEquals("근무 안 함", card(false, NowWorkOrigin.phone).stateText)
        assertEquals("폰에서 근무 중", card(true, NowWorkOrigin.phone).stateText)
        assertEquals("맥에서 근무 중", card(true, NowWorkOrigin.mac).stateText)
        assertEquals("근무 중", card(true, NowWorkOrigin.unknown).stateText)
        assertEquals("지금 상태를 불러오지 못했어요. 아래로 당겨 다시 시도해 주세요", NowText.loadFailed)
        assertEquals("연결을 확인하고 다시 시도해 주세요", NowText.networkFailed)
    }

    /** 이번 주 줄 · 퍼센트 · 진행(Swift `readFlow` 의 값과 weeklyGoal 의 55%). */
    @Test
    fun weekLineAndPercent() {
        val card = NowMyCard(true, false, null, 18_600, 89_280, 40)
        assertEquals("이번 주 24.8시간 · 목표 40시간 · 62%", card.weekLine)
        assertEquals("이번 주 24.8시간 · 목표 45시간 · 55%", card.copy(goalHours = 45).weekLine)
        assertEquals(144_000, card.goalSeconds)
        assertEquals(3600, card.copy(goalHours = 0).goalSeconds, "목표 0 은 1시간으로 접는다(0 으로 나누지 않는다)")
        assertEquals(false, card.isGoalComplete)
        assertEquals(true, card.copy(weekSeconds = 144_000).isGoalComplete)
    }

    @Test
    fun timeMathCutsAtKstMidnightAndDropsYesterdaySums() {
        val midnight = TeamWeeklyGoal.koreanDayStart(now)
        var member = TeamMemberStatus(
            id = "x", name = "x", status = WorkStatus.working, updatedAt = null,
            currentSessionStartedAt = midnight.addingTimeInterval(-3_600.0),
            weeklyDurationSeconds = 1_000, todayDurationSeconds = 100,
        )
        val at = midnight.addingTimeInterval(1_800.0)
        assertEquals(100 + 1_800, NowTimeMath.todaySeconds(member, at, at), "어제 몫 1시간은 오늘이 아니다")
        assertEquals(100L + 5_400, member.liveTodayDurationSeconds(at), "대조: 코어 식은 자정 전 몫까지 더한다")
        assertEquals(1_800, NowTimeMath.todaySeconds(member, midnight.addingTimeInterval(-60.0), at), "받은 뒤 날이 바뀌었다")
        val weekStart = TeamWeeklyGoal.koreanWeekStart(now)
        assertEquals(5_400, NowTimeMath.weekSeconds(member, weekStart.addingTimeInterval(-10.0), at))
        // 같은 주 안에 받았으면 끝난 세션 합(1,000) + 진행 세션의 이번 주 몫(5,400).
        assertEquals(1_000 + 5_400, NowTimeMath.weekSeconds(member, at, at))
        member = member.copy(status = WorkStatus.offWork)
        assertEquals(100, NowTimeMath.todaySeconds(member, at, at))
        assertEquals(1_000, NowTimeMath.weekSeconds(member, at, at))
    }

    /** 진행 세션 경과: 살아 있으면 now 까지, 끊겼으면 마지막 신호에서 멈춘다(Swift readFlow 의 민트 15,000 · 보리 10,320). */
    @Test
    fun elapsedSecondsFreezesAtLastSignal() {
        val mint = TeamMemberStatus("u-mint", "민트", WorkStatus.working, date("2026-09-17T05:04:10Z"), date("2026-09-17T00:55:00Z"),
            lastSeenAt = date("2026-09-17T05:04:10Z"))
        val bori = TeamMemberStatus("u-bori", "보리", WorkStatus.working, date("2026-09-17T04:52:00Z"), date("2026-09-17T02:00:00Z"),
            lastSeenAt = date("2026-09-17T04:52:00Z"))
        assertEquals(15_000, NowTimeMath.elapsedSeconds(mint, now))
        assertEquals(10_320, NowTimeMath.elapsedSeconds(bori, now))
        assertEquals(false, NowTimeMath.isStale(mint, now))
        assertEquals(true, NowTimeMath.isStale(bori, now))
        // 끊김 판정 시각을 받은 시각에 두면(5분 뒤 화면) 민트는 계속 센다.
        assertEquals(15_300, NowTimeMath.elapsedSeconds(mint, now.addingTimeInterval(300.0), presenceAt = now))
        // 진행 세션 기여도 끊긴 사람은 마지막 신호까지만(보리: 02:00 → 04:52 = 10,320).
        assertEquals(10_320L, NowTimeMath.currentContribution(bori, TeamWeeklyGoal.koreanDayStart(now), now))
        assertEquals(0, NowTimeMath.elapsedSeconds(mint.copy(status = WorkStatus.offWork), now))
    }

    @Test
    fun formatsFloorAndClamp() {
        assertEquals("39.9", NowFormat.hoursOneDecimal(143_999), "내림 — 40.0 으로 올리지 않는다")
        assertEquals("24.8", NowFormat.hoursOneDecimal(89_280))
        assertEquals("0.0", NowFormat.hoursOneDecimal(-10))
        assertEquals(62, NowFormat.percent(89_280, 144_000))
        assertEquals(999, NowFormat.percent(10_000_000, 3_600))
        assertEquals(0, NowFormat.percent(-5, 3_600))
        assertEquals(1, NowFormat.percent(1_800, 360_000), "반올림(0.5 → 1, 0 에서 먼 쪽)")
        assertEquals("4:10", NowFormat.hoursMinutes(15_000))
        assertEquals("1:02:05", NowFormat.clock(3_725))
        assertEquals("5:10:00", NowFormat.clock(18_600))
        assertEquals("0:00:00", NowFormat.clock(-1))
        assertEquals("3시간 25분", NowFormat.spokenDuration(12_300))
        assertEquals("25분", NowFormat.spokenDuration(1_500))
    }

    @Test
    fun draftRulesRevertGrowthPastLimitAndAlwaysAllowShrinking() {
        val ninetyNine = "가".repeat(99)
        assertEquals(ninetyNine + "나", NowTodoDraft.accepted(ninetyNine, ninetyNine + "나"))
        assertEquals(ninetyNine + "나", NowTodoDraft.accepted(ninetyNine + "나", ninetyNine + "나다"))
        val over = "가".repeat(120)
        assertEquals(over.dropLast(1), NowTodoDraft.accepted(over, over.dropLast(1)))
        assertNull(NowTodoDraft.counterText("a".repeat(89)))
        assertEquals("90/100", NowTodoDraft.counterText("a".repeat(90)))
        assertEquals("100/100", NowTodoDraft.counterText("a".repeat(100)))
    }

    @Test
    fun noticeFoldsCancellationAndPrefersConnection() {
        assertNull(NowStore.notice(listOf(CancellationException("x"))))
        assertEquals("연결을 확인하고 다시 시도해 주세요", NowStore.notice(listOf(IOException("timeout"), SupabaseWorkServiceError.InvalidResponse(500))))
        assertEquals("지금 상태를 불러오지 못했어요. 아래로 당겨 다시 시도해 주세요", NowStore.notice(listOf(SupabaseWorkServiceError.InvalidResponse(500))))
    }
}
