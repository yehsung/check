// 원본: Sources/check/CheckMenuView.swift:2229(sortedMembers) · :2271(TeamMemberLiveRow) · :2322(primaryDetail) · :2333(secondaryDetail) · CheckComponents.swift:75(PresenceChip) · :295(goalBar %)
// 기대값은 맥 글자 리터럴 그대로다(구현 상수로 기대값을 쓰지 않는다). 맥 쪽에 이 규칙만 재는 단위 시험이 없어 뜻을 여기서 처음 못 박는다.
package com.yehsung.aingcheck.core.stores.now

import com.yehsung.aingcheck.core.rules.text.NaturalKoCollation
import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.messages.Reply
import com.yehsung.aingcheck.core.stores.messages.StoreHarness
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.MemberPresence
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryRow
import com.yehsung.aingcheck.core.wire.models.TeamMemberStatus
import com.yehsung.aingcheck.core.wire.models.WorkStatus
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NowTeamRosterTest {
    private val now = SessionClock.demoInstant
    private fun ago(seconds: Int): SwiftDate = now.addingTimeInterval(-seconds.toDouble())
    private val goal40 = 40L * 3600
    private val natural = object : Collation {
        override fun compare(a: String, b: String): Int = NaturalKoCollation.compare(a, b)
    }

    private fun member(
        id: String,
        name: String,
        working: Boolean = false,
        startedAgo: Int? = null,
        seenAgo: Int? = null,
        weekly: Long = 0,
        avatar: String? = null,
    ) = TeamMemberStatus(
        id = id, name = name, status = if (working) WorkStatus.working else WorkStatus.offWork,
        updatedAt = ago(seenAgo ?: 30), currentSessionStartedAt = if (working) ago(startedAgo ?: 60) else null,
        weeklyDurationSeconds = weekly, lastSeenAt = if (working) ago(seenAgo ?: 30) else null,
        avatarURL = SwiftURL.parse(avatar),
    )

    private fun rows(members: List<TeamMemberStatus>, directory: List<PokeDirectoryRow> = emptyList(), me: String? = null, fetchedAt: SwiftDate = now) =
        NowTeamRoster.rows(members, directory, me, goal40, fetchedAt, now, now, natural)

    /** 근무(원장 status — 끊김 포함) 먼저, 같은 무리는 localizedStandardCompare(숫자 덩어리: 팀원2 < 팀원10). 쉬는 사람도 줄이 있다. */
    @Test
    fun sortsWorkingFirstThenNaturalNameAndKeepsPeopleOffWork() {
        val names = rows(
            listOf(
                member("a", "팀원10"),
                member("b", "팀원2"),
                member("c", "하늘", working = true),
                member("d", "가람", working = true, seenAgo = 600),
            ),
        ).map { it.name }
        assertEquals(listOf("가람", "하늘", "팀원2", "팀원10"), names)
    }

    /** 이름이 같으면 입력 순서가 아니라 id 로 고정한다 — 받을 때마다 줄이 바뀌지 않게. */
    @Test
    fun sameNameOrdersByIdRegardlessOfInput() {
        val forward = rows(listOf(member("a", "같음"), member("b", "같음"))).map { it.id }
        val reversed = rows(listOf(member("b", "같음"), member("a", "같음"))).map { it.id }
        assertEquals(listOf("a", "b"), forward)
        assertEquals(forward, reversed)
    }

    @Test
    fun presenceLabelsAreMacWords() {
        assertEquals("근무중", NowTeamRoster.presenceLabel(MemberPresence.ActiveWorking))
        assertEquals("연결 끊김", NowTeamRoster.presenceLabel(MemberPresence.StaleWorking(0)))
        assertEquals("근무종료", NowTeamRoster.presenceLabel(MemberPresence.OffWork))
    }

    /** 쉬는 사람 "주 H시간 MM분"(0 도 그렇게) · 근무 중 "현재 MM:SS · 주 …" · 1시간 넘으면 "현재 HH:MM". */
    @Test
    fun primaryDetailFormulas() {
        val (off, zero, live, long) = rows(
            listOf(
                member("a", "가", weekly = 12 * 3600L + 5 * 60),
                member("b", "나"),
                member("c", "다", working = true, startedAgo = 25 * 60, weekly = 3600),
                member("d", "라", working = true, startedAgo = 2 * 3600 + 3 * 60),
            ),
        ).sortedBy { it.id }
        assertEquals("주 12시간 05분", off.primaryDetail)
        assertEquals("주 0시간 00분", zero.primaryDetail)
        assertEquals("현재 25:00 · 주 1시간 25분", live.primaryDetail)
        assertEquals("현재 02:03 · 주 2시간 03분", long.primaryDetail)
        assertNull(off.secondaryDetail)
        assertNull(live.secondaryDetail)
    }

    /** 끊긴 사람: 경과는 마지막 신호에서 멈추고 "마지막 확인 N분 전"(최소 1분). */
    @Test
    fun staleFreezesAndSaysLastSeen() {
        val (stale, justStale) = rows(
            listOf(
                member("a", "가", working = true, startedAgo = 2 * 3600, seenAgo = 10 * 60 + 30),
                member("b", "나", working = true, startedAgo = 30 * 60, seenAgo = 91),
            ),
        ).sortedBy { it.id }
        assertTrue(stale.presence is MemberPresence.StaleWorking)
        assertEquals("현재 01:49 · 주 1시간 49분", stale.primaryDetail, "경과와 주간 기여 둘 다 마지막 신호까지만")
        assertEquals("마지막 확인 10분 전", stale.secondaryDetail)
        assertEquals("마지막 확인 1분 전", justStale.secondaryDetail)
    }

    /** 목표 막대: 비율 0~1 · %는 반올림 · 채우면 ✓ · 넘어도 100%. 목표 경계는 "이상". */
    @Test
    fun goalFractionPercentAndCheck() {
        val (half, justUnder, exact, over) = rows(
            listOf(
                member("a", "가", weekly = 20 * 3600L),
                member("b", "나", weekly = goal40 - 1),
                member("c", "다", weekly = goal40),
                member("d", "라", weekly = 90 * 3600L),
            ),
        ).sortedBy { it.id }
        assertEquals(0.5, half.goalFraction)
        assertEquals(50, half.goalPercent)
        assertFalse(half.meetsWeeklyGoal)
        assertFalse(justUnder.meetsWeeklyGoal)
        assertEquals(100, justUnder.goalPercent, "39시간 59분 59초의 막대 글자는 반올림으로 100 — 맥 goalBar 와 같다. ✓ 만 안 붙는다")
        assertTrue(exact.meetsWeeklyGoal)
        assertEquals(1.0, over.goalFraction)
        assertEquals(100, over.goalPercent)
    }

    /** 사진은 팀 상태 → 사람 목록 순, 센터·상태메시지는 사람 목록에서. 내 줄 표시. */
    @Test
    fun faceCenterStatusAndMe() {
        val directory = listOf(
            PokeDirectoryRow(userId = "a", displayName = "가", avatarUrl = "https://example.com/dir-a.jpg", isWorking = false, center = "seoul", statusMessage = "  집중  "),
            PokeDirectoryRow(userId = "b", displayName = "나", avatarUrl = "https://example.com/dir-b.jpg", isWorking = false),
        )
        val (a, b, c) = rows(
            listOf(member("a", "가"), member("b", "나", avatar = "https://example.com/own-b.jpg"), member("c", "다")),
            directory, me = "b",
        ).sortedBy { it.id }
        assertEquals("https://example.com/dir-a.jpg", a.avatarURL?.absoluteString)
        assertEquals("seoul", a.center)
        assertEquals("집중", a.statusMessage)
        assertEquals("https://example.com/own-b.jpg", b.avatarURL?.absoluteString, "팀 상태의 사진이 먼저")
        assertTrue(b.isMe)
        assertFalse(a.isMe)
        assertNull(c.avatarURL)
        assertNull(c.center)
    }

    /** 지난주에 받은 값이면 닫힌 주간 합을 버린다 — 월요일 0시를 넘겨도 지난주 시간을 '이번 주'로 말하지 않는다(내 카드와 같은 셈). */
    @Test
    fun closedWeeklyIsDroppedWhenFetchedLastWeek() {
        val row = rows(listOf(member("a", "가", weekly = 30 * 3600L)), fetchedAt = now.addingTimeInterval(-8 * 86_400.0)).single()
        assertEquals("주 0시간 00분", row.primaryDetail)
    }

    @Test
    fun workingCountIsLiveOnly() {
        val r = rows(listOf(member("a", "가", working = true), member("b", "나", working = true, seenAgo = 600), member("c", "다")))
        assertEquals(1, NowTeamRoster.workingCount(r))
        assertEquals("1명 근무중", NowTeamRoster.workingCountLabel(1))
    }
}

/** 스토어 부르는 자리: 받은 팀 상태 → 명단. */
@OptIn(ExperimentalCoroutinesApi::class)
class NowStoreTeamRosterTest {
    private val me = StoreHarness.ME

    private fun routes(r: RecordedRequest): Reply? = when {
        r.path == "/rest/v1/work_statuses" -> Reply.Json(
            """[{"user_id":"$me","status":"working","updated_at":"2026-09-17T05:04:30Z","last_seen_at":"2026-09-17T05:04:30Z","active_session_id":"S-1","profiles":{"display_name":"나","avatar_url":null}},""" +
                """{"user_id":"mate-off","status":"off_work","updated_at":"2026-09-17T01:00:00Z","last_seen_at":null,"active_session_id":null,"profiles":{"display_name":"쉬는 민트","avatar_url":"https://example.com/m.jpg"}}]""",
        )
        r.path == "/rest/v1/work_sessions" && r.query.any { it.second == "is.null" } -> Reply.Json(
            """[{"id":"S-1","user_id":"$me","started_at":"2026-09-17T04:00:00Z","ended_at":null,"duration_seconds":null}]""",
        )
        r.path == "/rest/v1/work_sessions" -> Reply.Json(
            """[{"user_id":"mate-off","started_at":"2026-09-16T23:00:00Z","ended_at":"2026-09-17T01:00:00Z"}]""",
        )
        r.path == "/rest/v1/work_status_devices" -> Reply.Json("[]")
        r.rpcName == "todo_sync" -> Reply.Json("""{"status":"ok","items":[],"watermark_ms":1789621500000,"rejected":[],"full":true}""")
        r.rpcName == "app_user_directory" -> Reply.Json("""[{"user_id":"mate-off","display_name":"쉬는 민트","avatar_url":null,"is_working":false,"message_capable":true,"center":"busan","status_message":"휴가"}]""")
        else -> null
    }

    @Test
    fun rosterKeepsMeAndPeopleOffWorkThatWorkingPeopleDrops() = runTest {
        val h = StoreHarness(this, ::routes)
        h.signIn()
        val store = NowStore(h.context, h.storeScope, NowTodoStorage("/mem/now", InMemoryTodoFileSystem()), timers = ManualScheduler())
        assertEquals(emptyList(), store.teamRoster(h.now()), "받기 전엔 빈 명단 — 화면은 teamLoadState 로 가른다")
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(emptyList(), store.workingPeople(h.now()).map { it.id }, "지금 근무 중 절은 나와 쉬는 사람을 뺀다")
        val rows = store.teamRoster(h.now())
        assertEquals(listOf(me, "mate-off"), rows.map { it.id }, "근무 중인 내가 먼저, 쉬는 팀원이 다음")
        assertTrue(rows[0].isMe)
        assertEquals("근무중", NowTeamRoster.presenceLabel(rows[0].presence))
        val mate = rows[1]
        assertEquals(MemberPresence.OffWork, mate.presence)
        assertEquals("주 2시간 00분", mate.primaryDetail)
        assertEquals("https://example.com/m.jpg", mate.avatarURL?.absoluteString)
        assertEquals("busan", mate.center)
        assertEquals("휴가", mate.statusMessage)
        assertEquals(0.05, mate.goalFraction, 1e-9, "목표 40시간 중 2시간")
        // 내 줄과 내 카드는 같은 셈이다.
        val card = store.myCard(h.now())!!
        assertEquals(card.progress, rows[0].goalFraction, 1e-9)
        store.reset()
        assertEquals(emptyList(), store.teamRoster(h.now()), "로그아웃 뒤 앞 사람 명단을 남기지 않는다")
        h.assertClean()
    }
}
