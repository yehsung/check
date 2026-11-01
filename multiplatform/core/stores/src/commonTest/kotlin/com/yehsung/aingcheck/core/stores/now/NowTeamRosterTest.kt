// 원본: Tests/CheckMobileKitTests/NowTeamRosterTests.swift:1 @ 23b91326
// 기대값은 iOS 시험의 글자 리터럴 그대로다(구현 상수로 기대값을 쓰지 않는다). 라우터 · 데모 라우트 · 픽스처 · 소스 글자 시험은 옮기지 않았다 —
// 입구 · 두 번 누름 · 빈/실패/무소속 화면은 androidApp `NowScreenSnapshotTest` 가 부르는 자리에서 잰다.
package com.yehsung.aingcheck.core.stores.now

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.rules.text.NaturalKoCollation
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.stores.messages.Reply
import com.yehsung.aingcheck.core.stores.messages.StoreHarness
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftURL
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
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NowTeamRosterTest {
    private val now = SessionClock.demoInstant
    private fun ago(seconds: Int): SwiftDate = now.addingTimeInterval(-seconds.toDouble())
    private val natural = object : Collation {
        override fun compare(a: String, b: String): Int = NaturalKoCollation.compare(a, b)
    }

    private fun member(
        id: String,
        name: String,
        working: Boolean = false,
        week: Long = 0,
        seenAgo: Int = 10,
        startedAgo: Int = 3_600,
        knowsStart: Boolean = true,
        avatar: String? = null,
    ) = TeamMemberStatus(
        id = id, name = name, status = if (working) WorkStatus.working else WorkStatus.offWork,
        updatedAt = ago(seenAgo), currentSessionStartedAt = if (working && knowsStart) ago(startedAgo) else null,
        weeklyDurationSeconds = week, lastSeenAt = ago(seenAgo),
        avatarURL = SwiftURL.parse(avatar),
    )

    private fun roster(
        members: List<TeamMemberStatus>,
        directory: List<PokeDirectoryRow> = emptyList(),
        hidden: Set<String> = emptySet(),
        me: String? = "me",
        goalHours: Int = 40,
    ) = NowTeamRosterRules.build(members, directory, hidden, me, goalHours, fetchedAt = now, now = now, presenceAt = now, collation = natural)

    private fun directoryRow(id: String, status: String?, center: String? = "seoul", avatar: String? = null) =
        PokeDirectoryRow(userId = id, displayName = "이름", avatarUrl = avatar, isWorking = false, center = center, statusMessage = status)

    /** 맥 sortedMembers 와 같다: 끊긴 사람도 근무 중 쪽 · 그 안은 숫자를 아는 이름순 · 나도 이름순 자리에 · 쉬는 사람까지 전원. */
    @Test
    fun orderMatchesMac() {
        val result = roster(
            listOf(
                member("c", "하늘"),
                member("a", "팀10", working = true),
                member("me", "민트", working = true),
                member("b", "팀2", working = true, seenAgo = 600),
                member("d", "가을"),
            ),
        )
        assertEquals(listOf("민트", "팀2", "팀10"), result.working.map { it.name })
        assertEquals(listOf("가을", "하늘"), result.resting.map { it.name })
        assertEquals(5, result.count)
        assertTrue(result.working.first().isMe, "나는 맨 위 고정이 아니라 이름순 자리다 — 맥과 같다")
        assertTrue(result.working[1].isStale && result.working[1].isWorking)
    }

    /** 같은 이름은 id 로 고정 — 새로고침마다 두 줄이 자리를 바꾸지 않는다. */
    @Test
    fun tieBreakIsStable() {
        assertEquals(listOf("a", "b"), roster(listOf(member("b", "민트"), member("a", "민트"))).resting.map { it.id })
        assertEquals(listOf("a", "b"), roster(listOf(member("a", "민트"), member("b", "민트"))).resting.map { it.id })
    }

    /** 주간 누적: 쉬는 사람도 값이 있고 · 근무 중이면 진행 세션을 더하고 · 끊기면 마지막 신호에서 멈춘다. */
    @Test
    fun weekSeconds() {
        val result = roster(
            listOf(
                member("off", "쉬는", week = 7_200),
                member("live", "도는", working = true, week = 7_200, startedAgo = 1_800),
                member("lost", "끊긴", working = true, week = 7_200, seenAgo = 600, startedAgo = 1_800),
            ),
        )
        val off = result.resting.single()
        assertEquals(7_200, off.weekSeconds)
        assertNull(off.elapsedSeconds)
        assertFalse(off.isStale)
        val live = result.working.first { it.id == "live" }
        assertEquals(9_000, live.weekSeconds)
        assertEquals(1_800, live.elapsedSeconds)
        assertFalse(live.isStale)
        val lost = result.working.first { it.id == "lost" }
        assertTrue(lost.isStale)
        assertEquals(7_200 + 1_200, lost.weekSeconds, "끊긴 세션이 숫자를 부풀리지 않는다")
        assertEquals(1_200, lost.elapsedSeconds)
        assertEquals(ago(600), lost.lastSeenAt)
    }

    /** 지난주에 받은 값은 쉬는 사람 줄에서도 버린다(내 카드와 같은 경계). */
    @Test
    fun weekBoundary() {
        val fetchedLastWeek = now.addingTimeInterval(-7 * 86_400.0)
        val result = NowTeamRosterRules.build(
            listOf(member("off", "쉬는", week = 7_200)), emptyList(), emptySet(), null, 40,
            fetchedAt = fetchedLastWeek, now = now, presenceAt = fetchedLastWeek, collation = natural,
        )
        assertEquals(0, result.resting.single().weekSeconds)
    }

    /** 목표: 진행 비율 · 달성 경계 · 목표 0 이어도 나누기가 터지지 않는다. */
    @Test
    fun goal() {
        val rows = roster(listOf(member("half", "반", week = 72_000), member("done", "끝", week = 144_000), member("short", "모", week = 143_999)))
            .resting.associateBy { it.id }
        assertEquals(0.5, rows.getValue("half").goalProgress)
        assertFalse(rows.getValue("half").isGoalMet)
        assertEquals(1.0, rows.getValue("done").goalProgress)
        assertTrue(rows.getValue("done").isGoalMet)
        assertFalse(rows.getValue("short").isGoalMet, "내림 — 1초 모자라면 달성이 아니다")
        assertTrue(roster(listOf(member("x", "엑스", week = 3_600)), goalHours = 0).resting.single().isGoalMet)
    }

    /** 이름 없는 팀원: 빈 문자열 · 공백뿐이면 '팀원' — 이름순 자리도 그 글자로. */
    @Test
    fun nameFallback() {
        assertEquals("팀원", NowTeamRosterRules.displayName(""))
        assertEquals("팀원", NowTeamRosterRules.displayName("  \n"))
        assertEquals("민트", NowTeamRosterRules.displayName(" 민트 "))
        val result = roster(listOf(member("x", ""), member("y", "하늘"), member("z", "가을")))
        assertEquals(listOf("가을", "팀원", "하늘"), result.resting.map { it.name })
    }

    /** 차단: 명단에 이름과 주간은 남고(확인 시트의 약속) · 그 사람이 쓴 상태메시지만 사라진다. */
    @Test
    fun blockedKeepsNameDropsStatus() {
        val result = roster(
            listOf(member("blocked", "자두", week = 3_600), member("other", "민트", week = 3_600)),
            directory = listOf(directoryRow("blocked", "차단한 사람의 문장"), directoryRow("other", "다른 사람의 문장")),
            hidden = setOf("blocked"),
        )
        val blocked = result.resting.first { it.id == "blocked" }
        assertEquals("자두", blocked.name)
        assertEquals(3_600, blocked.weekSeconds)
        assertNull(blocked.statusMessage)
        assertFalse(blocked.spokenSummary(now).contains("차단한 사람의 문장"))
        assertEquals("다른 사람의 문장", result.resting.first { it.id == "other" }.statusMessage)
    }

    /** 사람 목록에 없는 팀원(서버가 서로 차단한 사람을 뺀다): 줄은 서고 센터 · 상태메시지가 없다. */
    @Test
    fun missingFromDirectory() {
        val row = roster(listOf(member("x", "구슬", week = 60))).resting.single()
        assertNull(row.center)
        assertNull(row.statusMessage)
        assertEquals("구슬", row.name)
    }

    /** 사진은 팀 상태 → 사람 목록 순, 센터 · 상태메시지는 사람 목록에서(상태메시지는 다듬어서). */
    @Test
    fun faceCenterAndStatusComeFromTheDirectory() {
        val rows = roster(
            listOf(member("a", "가"), member("b", "나", avatar = "https://example.com/own-b.jpg")),
            directory = listOf(
                directoryRow("a", "  집중  ", avatar = "https://example.com/dir-a.jpg"),
                directoryRow("b", null, center = null, avatar = "https://example.com/dir-b.jpg"),
            ),
        ).resting.associateBy { it.id }
        val a = rows.getValue("a")
        assertEquals("https://example.com/dir-a.jpg", a.avatarURL?.absoluteString)
        assertEquals("seoul", a.center)
        assertEquals("집중", a.statusMessage)
        assertEquals("https://example.com/own-b.jpg", rows.getValue("b").avatarURL?.absoluteString, "팀 상태의 사진이 먼저")
    }

    /** 문구: 경과 0분이라 하지 않는다 · 주 표기 · 요약 · 톡백. */
    @Test
    fun copy() {
        assertEquals("방금 시작했어요", NowText.teamRosterElapsed(59))
        assertEquals("지금 3시간 20분째", NowText.teamRosterElapsed(12_000))
        assertEquals("주 24시간 48분", NowText.teamRosterWeek(89_280))
        assertEquals("주 8시간", NowText.teamRosterWeek(28_800))
        assertEquals("주 0분", NowText.teamRosterWeek(0))
        assertEquals("아잉 데모팀 · 1인당 주 40시간", NowText.teamRosterSummary("아잉 데모팀", 40))
        assertEquals("1인당 주 40시간", NowText.teamRosterSummary(null, 40))
        assertEquals("전체 보기", NowText.teamRosterSeeAll)
        assertEquals("우리 팀 전체 보기", NowText.teamRosterSeeAllInHeader)
        val result = roster(listOf(member("me", "민트", working = true, week = 3_600, startedAgo = 1_800), member("o", "자두")))
        assertEquals("민트, 나, 근무 중, 30분째, 이번 주 1시간 30분", result.working.single().spokenSummary(now))
        assertEquals("자두, 쉬는 중, 이번 주 0분", result.resting.single().spokenSummary(now))
    }

    /** 근무 중인데 시작 시각을 모르면 경과가 없다 — '방금 시작했어요'라고 지어내지 않는다. */
    @Test
    fun workingWithoutStart() {
        val row = roster(listOf(member("u", "모름", working = true, week = 7_200, knowsStart = false))).working.single()
        assertNull(row.elapsedSeconds)
        assertEquals(7_200, row.weekSeconds)
        assertEquals("모름, 근무 중, 이번 주 2시간 0분", row.spokenSummary(now))
    }

    /** 톡백은 화면과 같은 사실: 1분 미만은 '방금 시작했어요' · 끊긴 줄은 마지막 확인 · 상태메시지는 끝에. */
    @Test
    fun spokenMatchesScreen() {
        val fresh = roster(listOf(member("f", "새싹", working = true, startedAgo = 20))).working.single()
        assertEquals("새싹, 근무 중, 방금 시작했어요, 이번 주 0분", fresh.spokenSummary(now))
        val lost = roster(listOf(member("l", "끊긴", working = true, seenAgo = 600, startedAgo = 1_800))).working.single()
        assertEquals("끊긴, 연결 끊김 · 마지막 확인 10분 전, 이번 주 20분", lost.spokenSummary(now))
        val talking = roster(listOf(member("t", "민트")), directory = listOf(directoryRow("t", "휴가 중"))).resting.single()
        assertEquals("민트, 쉬는 중, 이번 주 0분, 상태메시지 휴가 중", talking.spokenSummary(now))
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

    private fun makeStore(h: StoreHarness) = NowStore(h.context, h.storeScope, NowTodoStorage("/mem/now", InMemoryTodoFileSystem()), timers = ManualScheduler())

    /** 쉬는 사람까지 전원 · 내 줄 주간 = 내 카드 주간 · 서버를 더 부르지 않는다 · 로그아웃하면 앞 계정의 명단이 남지 않는다. */
    @Test
    fun readsWhatItHasAndClearsOnReset() = runTest {
        val h = StoreHarness(this, ::routes)
        h.signIn()
        val store = makeStore(h)
        assertNull(store.teamRoster(h.now()), "받기 전엔 명단이 없다 — 화면은 teamLoadState 로 가른다")
        assertFalse(store.showsTeamRosterEntry)
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(emptyList(), store.workingPeople(h.now()).map { it.id }, "지금 근무 중 절은 나와 쉬는 사람을 뺀다")
        assertTrue(store.showsTeamRosterEntry)
        val before = h.server.requests.size
        val roster = assertNotNull(store.teamRoster(h.now()))
        val mine = roster.working.single()
        assertEquals(me, mine.id)
        assertTrue(mine.isMe)
        assertEquals(store.myCard(h.now())!!.weekSeconds, mine.weekSeconds, "같은 사람의 주간이 두 화면에서 달라지면 안 된다")
        val mate = roster.resting.single()
        assertEquals("mate-off", mate.id)
        assertEquals(7_200, mate.weekSeconds)
        assertEquals("https://example.com/m.jpg", mate.avatarURL?.absoluteString)
        assertEquals("busan", mate.center)
        assertEquals("휴가", mate.statusMessage)
        assertEquals(0.05, mate.goalProgress, 1e-9, "목표 40시간 중 2시간")
        assertEquals(before, h.server.requests.size, "명단은 받아 둔 값만 읽는다")
        store.reset()
        assertNull(store.teamRoster(h.now()), "로그아웃 뒤 앞 사람 명단을 남기지 않는다")
        assertFalse(store.showsTeamRosterEntry)
        h.assertClean()
    }

    /** 메시지 스토어가 방금 차단한 사람 — 옛 사람 목록을 쥔 창에도 상태메시지가 안 보인다(재료를 다시 받지 않아도). */
    @Test
    fun hidesJustBlockedStatus() = runTest {
        val h = StoreHarness(this, ::routes)
        h.signIn()
        val store = makeStore(h)
        var hidden = emptySet<String>()
        store.hiddenPeerIDs = { hidden }
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals("휴가", store.teamRoster(h.now())!!.resting.single().statusMessage)
        hidden = setOf("mate-off")
        val row = store.teamRoster(h.now())!!.resting.single()
        assertEquals("쉬는 민트", row.name)
        assertNull(row.statusMessage)
    }

    /** 이름이 안 오는 행(profiles null): 명단에 '팀원'으로 선다. */
    @Test
    fun nullProfileStandsAsTeammate() = runTest {
        val route: (RecordedRequest) -> Reply? = { r ->
            if (r.path == "/rest/v1/work_statuses") {
                Reply.Json("""[{"user_id":"u-x","status":"off_work","updated_at":"2026-09-17T02:10:00Z","last_seen_at":"2026-09-17T02:10:00Z","profiles":null}]""")
            } else {
                routes(r)
            }
        }
        val h = StoreHarness(this, route)
        h.signIn()
        val store = makeStore(h)
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(listOf("팀원"), store.teamRoster(h.now())!!.resting.map { it.name })
    }

    /** 팀 없음: 입구도 명단도 없다. */
    @Test
    fun noTeamHasNoEntryAndNoRoster() = runTest {
        val route: (RecordedRequest) -> Reply? = { r -> if (r.path == "/rest/v1/memberships") Reply.Json("[]") else routes(r) }
        val h = StoreHarness(this, route)
        h.signIn()
        val store = makeStore(h)
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertTrue(store.hasNoTeam)
        assertFalse(store.showsTeamRosterEntry)
        assertNull(store.teamRoster(h.now()))
    }

    /** 로딩 → 실패: 받기 전엔 입구가 없고 스피너에 머물지 않는다 · 받아 둔 뒤 실패하면 값을 두고 안내한다. */
    @Test
    fun loadStates() = runTest {
        var failing = true
        val route: (RecordedRequest) -> Reply? = { r -> if (failing && r.path == "/rest/v1/work_statuses") Reply.Offline else routes(r) }
        val h = StoreHarness(this, route)
        h.signIn()
        val store = makeStore(h)
        assertEquals(NowLoadState.loading, store.teamLoadState)
        assertFalse(store.showsTeamRosterEntry)
        store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(NowLoadState.failed, store.teamLoadState)
        assertFalse(store.showsTeamRosterEntry)
        assertNull(store.teamRoster(h.now()))

        failing = false
        store.refreshNow()
        advanceUntilIdle()
        assertTrue(store.showsTeamRosterEntry)
        assertEquals(2, store.teamRoster(h.now())!!.count)

        failing = true
        store.refreshNow()
        advanceUntilIdle()
        assertEquals(NowText.networkFailed, store.notice)
        assertEquals(NowLoadState.loaded, store.teamLoadState)
        assertEquals(2, store.teamRoster(h.now())!!.count, "받아 둔 명단을 지우지 않는다")
    }
}
