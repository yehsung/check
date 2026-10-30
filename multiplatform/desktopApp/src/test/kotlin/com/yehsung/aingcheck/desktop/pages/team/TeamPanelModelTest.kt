// 원본: Sources/check/CheckMenuView.swift:2124-2163(빈 행 · 정렬) · 2169-2177(근무 수 칩) · 2229-2262(현재 · 주 · 마지막 확인)
//       · CheckComponents.swift:75-84(PresenceChip) · 124(CountChip)
// W3-c2 — 팀 패널 정렬·근무 중 점·경과 표기가 맥 규칙과 같고, 글자는 core 포맷터 출력 그대로(사본 아님)인지.
package com.yehsung.aingcheck.desktop.pages.team

import com.yehsung.aingcheck.core.rules.format.MenuBarStatusFormatter
import com.yehsung.aingcheck.core.rules.text.NaturalKoCollation
import com.yehsung.aingcheck.core.wire.models.MemberPresence
import com.yehsung.aingcheck.desktop.pages.work.HomeTestKit
import com.yehsung.aingcheck.desktop.pages.work.HomeTestKit.member
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TeamPanelModelTest {
    private val now = HomeTestKit.NOW

    /** 근무(원장 status == working — 연결 끊김 포함) 먼저, 같은 무리는 localizedStandardCompare(숫자 덩어리: 2 < 10). */
    @Test
    fun sortsWorkingFirstThenNaturalName() {
        val ms = listOf(
            member("a", "팀원10", working = false),
            member("b", "팀원2", working = false),
            member("c", "하늘", working = true, startedAgo = 60),
            member("d", "가람", working = true, startedAgo = 60, lastSeenAgo = 600), // 연결 끊김 — 그래도 근무 무리
            member("e", "Bob", working = false),
        )
        val names = TeamPanelModel.sorted(ms).map { it.name }
        val off = listOf("팀원10", "팀원2", "Bob").sortedWith(NaturalKoCollation)
        assertEquals(listOf("가람", "하늘") + off, names)
        assertTrue(names.indexOf("팀원2") < names.indexOf("팀원10"), "숫자 덩어리 비교")
    }

    /** 근무 수 칩은 라이브(activeWorking)만 — 연결 끊김 제외. 점·문구 "N명 근무중". */
    @Test
    fun workingCountExcludesStale() {
        val ms = listOf(
            member("a", "가", working = true, startedAgo = 60),
            member("b", "나", working = true, startedAgo = 60, lastSeenAgo = 91),
            member("c", "다", working = false),
        )
        assertEquals(1, TeamPanelModel.workingCount(ms, now))
        assertEquals("1명 근무중", TeamPanelModel.build("팀", ms, now, 3600, null, null, null).workingCountLabel)
    }

    /** 경과 표기: 라이브 "현재 MM:SS · 주 H시간 MM분", 끊김은 동결 값 + "마지막 확인 N분 전", 종료는 "주 …"만. 글자는 core 포맷터 출력. */
    @Test
    fun detailsMatchMacFormulas() {
        val live = member("a", "가", working = true, startedAgo = 25 * 60, weekly = 3600)
        val r1 = TeamPanelModel.row(live, now, 40L * 3600, null)
        assertEquals("근무중", r1.presenceLabel)
        assertEquals("현재 25:00 · 주 1시간 25분", r1.primaryDetail)
        assertEquals(
            "현재 ${MenuBarStatusFormatter.duration(live.currentDurationSeconds(now))} · 주 ${MenuBarStatusFormatter.hoursMinutes(live.liveWeeklyDurationSeconds(now))}",
            r1.primaryDetail,
        )
        assertNull(r1.secondaryDetail)

        // 2시간 전 시작, 10분 30초 전 마지막 신호 → 동결 1:49:30 → "01:49"
        val stale = member("b", "나", working = true, startedAgo = 2 * 3600, lastSeenAgo = 630)
        val r2 = TeamPanelModel.row(stale, now, 40L * 3600, null)
        assertTrue(r2.presence is MemberPresence.StaleWorking)
        assertEquals("연결 끊김", r2.presenceLabel)
        assertEquals("현재 01:49 · 주 1시간 49분", r2.primaryDetail)
        assertEquals("마지막 확인 10분 전", r2.secondaryDetail)

        val off = member("c", "다", working = false, weekly = 41L * 3600 + 5 * 60)
        val r3 = TeamPanelModel.row(off, now, 40L * 3600, "c")
        assertEquals("근무종료", r3.presenceLabel)
        assertEquals("주 41시간 05분", r3.primaryDetail)
        assertTrue(r3.meetsWeeklyGoal && r3.isMe)
        assertEquals(1.0, r3.goalFraction)
    }

    /** 90초 경계(STALE_PRESENCE_SECONDS) 바로 안쪽은 라이브, "마지막 확인"은 최소 1분. */
    @Test
    fun staleBoundaryAndMinimumMinute() {
        assertEquals("근무중", TeamPanelModel.row(member("a", "가", true, 300, lastSeenAgo = 90), now, 3600, null).presenceLabel)
        val justStale = TeamPanelModel.row(member("b", "나", true, 300, lastSeenAgo = 91), now, 3600, null)
        assertEquals("마지막 확인 1분 전", justStale.secondaryDetail)
    }

    /** 빈 목록: "팀원" · 근무종료 · 부제 = 동기화 문구(맥 2124-2126). */
    @Test
    fun emptyListShowsPlaceholderRow() {
        val ui = TeamPanelModel.build("합성 팀", emptyList(), now, 3600, null, "불러오는 중…", null)
        assertEquals(1, ui.rows.size)
        assertEquals("팀원", ui.rows[0].name)
        assertEquals("근무종료", ui.rows[0].presenceLabel)
        assertEquals("불러오는 중…", ui.rows[0].primaryDetail)
        assertEquals("0명 근무중", ui.workingCountLabel)
    }
}
