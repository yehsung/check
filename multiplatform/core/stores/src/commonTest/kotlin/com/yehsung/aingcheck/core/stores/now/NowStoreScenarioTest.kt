// 원본: Tests/CheckMobileKitTests/NowStoreTests.swift:15-520(읽기 · 끊김 판정 · 오프라인 · 소속 · 목표 · 한 번에 하나 · 탭 · 주기 · 세대 가드 · 실패) @ 1b8260d
// 위젯 스냅숏 파일(쓰기 창구 · AingWidgetMyTodayState)은 W2-f 몫이라 여기서는 "언제 쓰라고 했는가"([RecordingWidgetSink])와 판정 값만 잰다.
// 문구 기대값은 Swift 원문 글자 그대로다.
package com.yehsung.aingcheck.core.stores.now

import com.yehsung.aingcheck.core.stores.messages.Reply
import com.yehsung.aingcheck.core.stores.messages.StoreHarness
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 지금 탭 한 벌: 스텁 서버 · 메모리 할 일 파일 · 손으로 미는 타이머 · 위젯 쓰기 기록(Swift `NowHarness`). */
@OptIn(ExperimentalCoroutinesApi::class)
class NowRig(val h: StoreHarness, val server: NowStubServer, val files: InMemoryTodoFileSystem, val scheduler: ManualScheduler, val store: NowStore) {
    val sink = RecordingWidgetSink().also { store.widgetSink = it }
    val storage: NowTodoStorage get() = store.todoStorage

    fun activate() {
        store.appDidBecomeActive()
        h.scope.advanceUntilIdle()
    }

    fun settle() = h.scope.advanceUntilIdle()

    fun requests(key: String) = h.server.requests.filter { NowStubServer.key(it) == key }

    companion object {
        suspend fun TestScope.nowRig(runsPeriodicRefresh: Boolean = true, setup: (NowStubServer) -> Unit = {}): NowRig {
            val server = NowStubServer().also(setup)
            val h = StoreHarness(this) { server.route(it) }
            h.signIn()
            val files = InMemoryTodoFileSystem()
            val scheduler = ManualScheduler()
            val store = NowStore(h.context, h.storeScope, NowTodoStorage("/mem/aing", files), runsPeriodicRefresh, scheduler)
            return NowRig(h, server, files, scheduler, store)
        }
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class NowStoreScenarioTest {
    private fun at(iso: String) = SwiftISO8601.parse(iso)!!

    @Test
    fun readFlowCardsPeopleAndNoWrites() = runTest {
        val rig = with(NowRig) { nowRig() }
        val (h, store) = rig.h to rig.store
        rig.activate()
        assertEquals(NowMembership(NowStubServer.TEAM, "지금팀", 40, "member"), store.membership)
        val card = store.myCard(h.now())!!
        assertTrue(card.isWorking && !card.isStale)
        assertEquals(at("2026-09-17T01:20:00Z"), card.sessionStartedAt)
        assertEquals(18_600, card.todaySeconds)
        assertEquals(89_280, card.weekSeconds)
        assertEquals("이번 주 24.8시간 · 목표 40시간 · 62%", card.weekLine)
        assertEquals("5:10:00", NowFormat.clock(card.todaySeconds))
        // 1초마다 폰이 센다(서버 세션 시작 시각 기준).
        val later = store.myCard(h.now().addingTimeInterval(61.0))!!
        assertEquals(18_661, later.todaySeconds)
        assertEquals(89_341, later.weekSeconds)

        val people = store.workingPeople(h.now())
        assertEquals(
            listOf(NowStubServer.MINT, NowStubServer.BORI, NowStubServer.LIME, NowStubServer.MORAE, NowStubServer.CORAL, NowStubServer.HANEUL),
            people.map { it.id }, "우리 팀(오래 일한 순) → 다른 팀(이름순), 나·비근무 제외",
        )
        assertTrue(people.take(3).all { it.isTeammate } && people.drop(3).none { it.isTeammate })
        assertEquals(15_000, people[0].elapsedSeconds)
        assertEquals("seoul", people[0].center)
        assertTrue(people[1].isStale)
        assertEquals(10_320, people[1].elapsedSeconds, "끊긴 신호는 마지막 신호에서 멈춘다")
        assertEquals("https://x.invalid/lime.jpg", people[2].avatarURL?.absoluteString)
        assertTrue(people.drop(3).all { it.elapsedSeconds == null && it.startedAt == null }, "다른 팀은 시간이 없다")
        assertEquals("https://x.invalid/morae.jpg", people[3].avatarURL?.absoluteString)

        assertNull(store.notice)
        assertTrue(rig.requests("work_statuses").all { it.method == "GET" })
        val tableWrites = h.storeRequests.filter { it.rpcName == null && it.method != "GET" }
        assertEquals(emptyList(), tableWrites.map { "${it.method} ${it.path}" }, "근무 표는 읽기만")
        assertTrue(h.storeRequests.none { it.rpcName == "take_pokes" || it.rpcName == "work_tick" })
        assertTrue(rig.sink.writes.isNotEmpty(), "active 진입·새로고침 끝에서 위젯 쓰기를 부르지 않았다")
        h.assertClean()
    }

    @Test
    fun othersWaitForTeamStatus() = runTest {
        val rig = with(NowRig) { nowRig { it.override("work_statuses", Reply.Offline) } }
        rig.activate()
        val store = rig.store
        assertTrue(store.hasLoadedDirectory && !store.hasLoadedTeam)
        assertEquals(emptyList(), store.workingPeople(rig.h.now()), "우리 팀원이 시간 없이 '다른 팀'에 섞였다")
        assertEquals("연결을 확인하고 다시 시도해 주세요", store.notice)
        assertNull(store.myCard(rig.h.now()))
        rig.h.assertClean()
    }

    @Test
    fun noTeamShowsOthersAndSkipsTeamStatus() = runTest {
        val rig = with(NowRig) { nowRig { it.override("memberships", Reply.Json("[]")) } }
        rig.activate()
        val store = rig.store
        assertTrue(store.hasNoTeam && store.membership == null)
        assertNull(store.myCard(rig.h.now()))
        assertEquals(emptyList(), rig.requests("work_statuses"), "팀이 없으면 팀 상태를 부르지 않는다")
        val people = store.workingPeople(rig.h.now())
        assertTrue(people.size == 6 && people.none { it.isTeammate })
        assertEquals(NowLoadState.loaded, store.teamLoadState)
        assertEquals(NowLoadState.loaded, store.workingLoadState)
        rig.h.assertClean()
    }

    @Test
    fun presenceHeldAcrossForegroundUntilResponse() = runTest {
        val rig = with(NowRig) { nowRig() }
        val (h, store) = rig.h to rig.store
        rig.activate()
        val before = store.myCard(h.now())!!
        assertTrue(!before.isStale && before.todaySeconds == 18_600)

        store.appDidEnterBackground()
        rig.settle()
        h.clockShift += 300.0   // 폰만 5분 잠겼다(맥은 계속 근무 · 30초 하트비트)
        val gate = CompletableDeferred<Unit>()
        rig.server.override("work_statuses", Reply.Gate(gate, Reply.Json(NowStubServer.statuses(meSeen = "2026-09-17T05:09:50Z"))))
        val writesBefore = rig.sink.writes.size
        store.appDidBecomeActive()
        runCurrent()
        assertNotNull(store.refreshTask)
        // 응답 전: 받은 시각(05:05:00)의 판정을 유지하고 now 까지 센다.
        val during = store.myCard(h.now())!!
        assertFalse(during.isStale, "응답을 기다리는 동안 멀쩡한 맥이 '연결 끊김'으로 뒤집혔다")
        assertEquals(18_900, during.todaySeconds, "오늘 누적이 마지막 신호 지점으로 뒤로 뛰었다")
        val people = store.workingPeople(h.now())
        assertEquals(false, people.first { it.id == NowStubServer.MINT }.isStale)
        assertEquals(15_300, people.first { it.id == NowStubServer.MINT }.elapsedSeconds, "민트 경과가 마지막 신호에서 멈췄다")
        assertEquals(true, people.first { it.id == NowStubServer.BORI }.isStale, "받을 때 이미 끊겼던 사람은 그대로 멈춘다")
        // 응답 전 추정(몇 분 전 판정)으로 위젯을 쓰지 않게 — 미룰 수 있는 쓰기만 불렀고, 판정은 '미룬다'다.
        assertEquals(listOf(true), rig.sink.writes.drop(writesBefore), "응답 전에 미룰 수 없는 쓰기를 불렀다")
        assertTrue(store.shouldDeferWidgetWrite(h.now()))

        gate.complete(Unit)
        runCurrent()
        rig.settle()
        val after = store.myCard(h.now())!!
        assertTrue(!after.isStale && after.todaySeconds == 18_900)
        assertFalse(store.shouldDeferWidgetWrite(h.now()))
        assertEquals(false, rig.sink.writes.last(), "응답 뒤에 쓰기를 부르지 않았다")
        h.assertClean()
    }

    @Test
    fun presenceHeldBetweenRefreshesThenFreezesOnNextResponse() = runTest {
        val rig = with(NowRig) { nowRig { it.override("work_statuses", Reply.Json(NowStubServer.statuses(meSeen = "2026-09-17T05:04:31Z"))) } }
        val (h, store) = rig.h to rig.store
        rig.activate()
        assertEquals(false, store.myCard(h.now())?.isStale)
        // 60초 주기 새로고침이 떠났다. 그사이 맥이 멈췄다 — 다음 응답은 90초 넘게 끊긴 신호(05:04:20)를 싣고 온다.
        rig.server.override("work_statuses", Reply.Json(NowStubServer.statuses(meSeen = "2026-09-17T05:04:20Z")))
        h.clockShift += 60.0
        rig.scheduler.advance(60.0)
        assertNotNull(store.refreshTask, "60초 주기 새로고침이 떠나지 않았다")
        for (step in 1..4) {
            h.clockShift += 0.5
            val card = store.myCard(h.now())!!
            assertFalse(card.isStale, "응답 전 t+${60 + step * 0.5}초에 끊김으로 뒤집혔다")
            assertEquals(18_660 + step / 2, card.todaySeconds, "오늘 누적이 뒤로 뛰었다")
        }
        rig.settle()
        val card = store.myCard(h.now())!!
        assertTrue(card.isStale, "다음 응답의 신호가 90초 넘게 끊겼는데 계속 셌다")
        assertEquals(5_100 + 13_460, card.todaySeconds, "마지막 신호(05:04:20)에서 멈춘다")
        h.assertClean()
    }

    @Test
    fun presenceFallsBackToNowAfterTeamStatusFailure() = runTest {
        val rig = with(NowRig) { nowRig() }
        val (h, store) = rig.h to rig.store
        rig.activate()
        h.clockShift += 120.0
        rig.server.override("work_statuses", Reply.Offline)
        store.refreshNow()
        assertTrue(store.teamStatusFailedSinceFetch)
        assertEquals(h.now(), store.presenceJudgedAt(h.now()))
        val card = store.myCard(h.now())!!
        assertTrue(card.isStale)
        assertEquals(5_100 + 13_480, card.todaySeconds, "나: 마지막 신호 05:04:40 에서 멈춘다")

        rig.server.override("work_statuses", Reply.Json(NowStubServer.statuses(meSeen = "2026-09-17T05:06:50Z")))
        store.refreshNow()
        assertFalse(store.teamStatusFailedSinceFetch)
        val fresh = store.myCard(h.now())!!
        assertFalse(fresh.isStale)
        assertEquals(5_100 + 13_620, fresh.todaySeconds, "05:07:00 까지 다시 센다")
        h.assertClean()
    }

    @Test
    fun offlineColdStartIsNotLoadingForever() = runTest {
        val keys = listOf("memberships", "rpc.app_user_directory", "work_statuses")
        val rig = with(NowRig) { nowRig { server -> keys.forEach { server.override(it, Reply.Offline) } } }
        val store = rig.store
        assertEquals(NowLoadState.loading, store.teamLoadState, "시도 전은 불러오는 중")
        assertEquals(NowLoadState.loading, store.workingLoadState)
        rig.activate()
        assertEquals("연결을 확인하고 다시 시도해 주세요", store.notice)
        assertTrue(!store.isRefreshing && store.refreshTask == null, "도는 요청이 없다")
        assertEquals(NowLoadState.failed, store.teamLoadState, "도는 요청이 없는데 내 카드 자리가 '불러오는 중'이다")
        assertEquals(NowLoadState.failed, store.workingLoadState)

        keys.forEach { rig.server.override(it, null) }
        store.refresh()
        assertEquals(NowLoadState.failed, store.teamLoadState, "다시 시도하는 동안 실패 줄 ↔ 스피너로 깜빡인다")
        rig.settle()
        assertEquals(NowLoadState.loaded, store.teamLoadState)
        assertEquals(NowLoadState.loaded, store.workingLoadState)
        assertTrue(store.myCard(rig.h.now()) != null && store.notice == null)

        store.reset()
        assertEquals(NowLoadState.loading, store.teamLoadState, "세대가 바뀌면 처음부터")
        rig.h.assertClean()
    }

    @Test
    fun noTeamWithoutDirectoryIsUnknownNotEmpty() = runTest {
        val rig = with(NowRig) {
            nowRig {
                it.override("memberships", Reply.Json("[]"))
                it.override("rpc.app_user_directory", Reply.Json("""{"message":"boom"}""", 503))
            }
        }
        rig.activate()
        assertEquals(NowLoadState.loaded, rig.store.teamLoadState, "내 카드 자리는 소속 없음 안내")
        assertEquals(NowLoadState.failed, rig.store.workingLoadState)
        assertEquals("지금 상태를 불러오지 못했어요. 아래로 당겨 다시 시도해 주세요", rig.store.notice)
        rig.h.assertClean()
    }

    @Test
    fun teamToNoTeamClearsTeammatesAndRejoinIsUnknown() = runTest {
        val rig = with(NowRig) { nowRig() }
        val (h, store) = rig.h to rig.store
        rig.activate()
        assertEquals(3, store.workingPeople(h.now()).count { it.isTeammate })
        rig.server.override("memberships", Reply.Json("[]"))
        store.refreshNow()
        assertTrue(store.hasNoTeam && store.teamMembers.isEmpty() && !store.hasLoadedTeam)
        val people = store.workingPeople(h.now())
        assertTrue(people.size == 6 && people.all { !it.isTeammate && it.elapsedSeconds == null }, "옛 팀원이 '우리 팀'으로 남았다")
        // 다시 팀에 들어왔는데 팀 상태는 아직 못 받았다 — 모름.
        rig.server.override("memberships", null)
        rig.server.override("work_statuses", Reply.Offline)
        store.refreshNow()
        assertTrue(store.membership != null && !store.hasLoadedTeam)
        assertNull(store.myCard(h.now()))
        rig.server.override("work_statuses", null)
        store.refreshNow()
        assertNotNull(store.myCard(h.now()))
        h.assertClean()
    }

    @Test
    fun lateGoalSaveAfterAccountSwitchIsDropped() = runTest {
        val rig = with(NowRig) { nowRig() }
        val (h, store) = rig.h to rig.store
        rig.activate()
        val gate = CompletableDeferred<Unit>()
        rig.server.override("rpc.set_team_weekly_goal", Reply.Gate(gate, Reply.Json("""[{"weekly_goal_hours":45}]""")))
        val save = async { store.saveGoal(45) }
        runCurrent()
        h.session.signOut()
        store.reset()
        rig.server.override("memberships", Reply.Json("""[{"team_id":"team-other","role":"member","teams":{"name":"다른팀","weekly_goal_hours":30}}]"""))
        h.signInAs("u-other", idle = false)
        store.appDidBecomeActive()
        runCurrent()
        assertEquals("team-other", store.membership?.teamID)
        assertEquals(30, store.goalHours)
        val startedAt = testScheduler.currentTime
        gate.complete(Unit)
        assertFalse(save.await(), "앞 계정 저장 응답에 시트를 닫았다")
        assertEquals(startedAt, testScheduler.currentTime, "멈춘 저장이 시한에 걸렸다(늦은 응답을 재지 못했다)")
        assertEquals(30, store.goalHours, "앞 계정의 늦은 저장 응답이 새 계정 목표를 바꿨다")
        rig.settle()
        h.assertClean()
    }

    @Test
    fun refreshIsSingleFlight() = runTest {
        val gate = CompletableDeferred<Unit>()
        val rig = with(NowRig) { nowRig(runsPeriodicRefresh = false) { it.override("rpc.app_user_directory", Reply.Gate(gate, Reply.Json(NowStubServer.DIRECTORY))) } }
        val store = rig.store
        store.refresh()
        runCurrent()
        store.refresh()
        store.refresh()
        assertEquals(1, store.refreshCount)
        gate.complete(Unit)
        rig.server.override("rpc.app_user_directory", null)
        rig.settle()
        assertNull(store.refreshTask)
        assertEquals(2, store.refreshCount, "겹친 새로고침이 하나로 합쳐지지 않았다")
        assertEquals(2, rig.requests("rpc.app_user_directory").size)
        rig.h.assertClean()
    }

    @Test
    fun tabAppearSkipsFreshData() = runTest {
        val rig = with(NowRig) { nowRig(runsPeriodicRefresh = false) }
        val (h, store) = rig.h to rig.store
        rig.activate()
        val count = store.refreshCount
        h.clockShift += 29.0
        store.tabDidAppear()
        rig.settle()
        assertEquals(count, store.refreshCount, "30초 안에 받은 값을 다시 받았다")
        h.clockShift += 2.0
        store.tabDidAppear()
        rig.settle()
        assertEquals(count + 1, store.refreshCount)
        h.assertClean()
    }

    @Test
    fun periodicRefreshNeedsOptIn() = runTest {
        val off = with(NowRig) { nowRig(runsPeriodicRefresh = false) }
        off.activate()
        val count = off.store.refreshCount
        off.scheduler.advance(180.0)
        off.settle()
        assertEquals(count, off.store.refreshCount, "끈 조립이 스스로 새로고침했다")
        off.h.assertClean()
    }

    @Test
    fun periodicRefreshRunsEveryMinuteWhileActiveWhenOn() = runTest {
        val on = with(NowRig) { nowRig(runsPeriodicRefresh = true) }
        on.activate()
        val count = on.store.refreshCount
        on.scheduler.advance(59.0)
        on.settle()
        assertEquals(count, on.store.refreshCount, "60초 전에 새로고침했다")
        on.scheduler.advance(1.0)
        on.settle()
        assertEquals(count + 1, on.store.refreshCount)
        on.scheduler.advance(60.0)
        on.settle()
        assertEquals(count + 2, on.store.refreshCount, "60초 주기가 첫 번만 돌고 멈췄다")
        on.store.appDidEnterBackground()
        on.scheduler.advance(600.0)
        on.settle()
        assertEquals(count + 2, on.store.refreshCount, "background 에서 60초 주기가 돌았다")
        on.h.assertClean()
    }

    @Test
    fun lateResponseAfterSignOutIsDroppedAndNothingIsWrittenAfter() = runTest {
        val gate = CompletableDeferred<Unit>()
        val rig = with(NowRig) { nowRig { it.override("work_statuses", Reply.Gate(gate, Reply.Json(NowStubServer.STATUSES))) } }
        val (h, store) = rig.h to rig.store
        store.appDidBecomeActive()
        assertTrue(store.addTodo("로그아웃 전 할 일"), "reset 이 목록을 비우며 위젯 쓰기를 깨우게 한 줄 둔다")
        runCurrent()
        h.session.signOut()
        val writesAtSignOut = rig.sink.writes.size
        store.reset()
        gate.complete(Unit)
        runCurrent()
        rig.settle()
        assertEquals(emptyList(), store.todos.items)
        assertTrue(store.teamMembers.isEmpty() && store.teamFetchedAt == null)
        assertTrue(store.membership == null && store.directory.isEmpty())
        assertNull(store.myCard(h.now()))
        assertFalse(store.canEditTodos)
        assertEquals(writesAtSignOut, rig.sink.writes.size, "로그아웃 뒤 위젯 쓰기를 불렀다 — 위젯이 앞 계정을 그린다")
        h.assertClean()
    }

    @Test
    fun failuresKeepDataAndMissingDirectoryFoldsQuietly() = runTest {
        val rig = with(NowRig) { nowRig { it.override("rpc.app_user_directory", Reply.missingFunction) } }
        val (h, store) = rig.h to rig.store
        rig.activate()
        assertNull(store.notice, "함수 없는 서버는 안내 없이 접는다")
        assertEquals(listOf(NowStubServer.MINT, NowStubServer.BORI, NowStubServer.LIME), store.workingPeople(h.now()).map { it.id })

        rig.server.override("work_statuses", Reply.Offline)
        store.refreshNow()
        assertEquals("연결을 확인하고 다시 시도해 주세요", store.notice)
        assertEquals(5, store.teamMembers.size, "실패가 받아 둔 팀 상태를 지우지 않는다")

        rig.server.override("work_statuses", Reply.Json("""{"message":"boom"}""", 500))
        store.refreshNow()
        assertEquals("지금 상태를 불러오지 못했어요. 아래로 당겨 다시 시도해 주세요", store.notice)

        rig.server.override("work_statuses", null)
        store.refreshNow()
        assertNull(store.notice)
        h.assertClean()
    }

    @Test
    fun weeklyGoalRangeSaveAndLateMembershipCannotRevert() = runTest {
        val rig = with(NowRig) { nowRig() }
        val (h, store) = rig.h to rig.store
        rig.activate()
        assertFalse(store.saveGoal(0))
        assertFalse(store.saveGoal(169))
        assertEquals(emptyList(), rig.requests("rpc.set_team_weekly_goal"))

        val gate = CompletableDeferred<Unit>()
        rig.server.override("memberships", Reply.Gate(gate, Reply.Json("""[{"team_id":"team-now","role":"member","teams":{"name":"지금팀","weekly_goal_hours":40}}]""")))
        store.refresh()
        runCurrent()
        val writes = rig.sink.writes.size
        assertTrue(store.saveGoal(45))
        assertTrue("45" in rig.requests("rpc.set_team_weekly_goal").last().bodyText)
        assertEquals(45, store.goalHours)
        assertEquals(listOf(true), rig.sink.writes.drop(writes), "저장 뒤 위젯 쓰기를 부르지 않았다")
        gate.complete(Unit)
        runCurrent()
        rig.server.override("memberships", null)
        rig.settle()
        assertEquals(45, store.goalHours, "저장 전에 떠난 조회가 목표를 40 으로 되돌렸다")
        assertEquals("이번 주 24.8시간 · 목표 45시간 · 55%", store.myCard(h.now())?.weekLine)

        rig.server.override("rpc.set_team_weekly_goal", Reply.Json("""{"message":"boom"}""", 500))
        assertFalse(store.saveGoal(50))
        assertEquals("목표 변경 실패", store.goalNotice)
        rig.server.override("rpc.set_team_weekly_goal", Reply.Offline)
        assertFalse(store.saveGoal(50))
        assertEquals("연결을 확인하고 다시 시도해 주세요", store.goalNotice)
        assertEquals(45, store.goalHours, "실패는 목표를 바꾸지 않는다")
        store.clearGoalNotice()
        assertNull(store.goalNotice)
        h.assertClean()
    }

    /**
     * 팀원 정렬(검증 V11 · 이름 같음 판정): 시작 이른 순 → 시작을 모르면 뒤 → 같은 시작이면 이름 → 이름이 **정준 동치**(NFC·NFD 만 다름)면 id.
     * Swift `lhs.name == rhs.name` 은 정준 동치라, 입력 순서(id 큰 쪽 먼저)를 남기면 iOS 와 갈린다.
     */
    @Test
    fun teammateOrderStartThenCanonicalNameThenID() = runTest {
        val nfc = "한결"          // 한결(완성형)
        val nfd = "한결"   // 한결(자모 분해)
        fun status(id: String, name: String, seen: String) =
            """{"user_id":"$id","status":"working","updated_at":"$seen","last_seen_at":"$seen","profiles":{"display_name":"$name","avatar_url":null}}"""
        val statuses = "[" + listOf(
            status(StoreHarness.ME, "나", "2026-09-17T05:04:50Z"),
            status("u-z", nfd, "2026-09-17T05:04:50Z"),
            status("u-a", nfc, "2026-09-17T05:04:50Z"),
            status("u-late", "가가", "2026-09-17T05:04:50Z"),
            status("u-early", "하하", "2026-09-17T05:04:50Z"),
            status("u-unknown", "다다", "2026-09-17T05:04:50Z"),
        ).joinToString(",") + "]"
        val sessions = """
            [{"id":"s1","user_id":"u-z","started_at":"2026-09-17T02:00:00Z","ended_at":null},
             {"id":"s2","user_id":"u-a","started_at":"2026-09-17T02:00:00Z","ended_at":null},
             {"id":"s3","user_id":"u-late","started_at":"2026-09-17T03:00:00Z","ended_at":null},
             {"id":"s4","user_id":"u-early","started_at":"2026-09-17T01:00:00Z","ended_at":null}]
        """.trimIndent()
        val rig = with(NowRig) {
            nowRig {
                it.override("work_statuses", Reply.Json(statuses))
                it.override("work_sessions.active", Reply.Json(sessions))
                it.override("rpc.app_user_directory", Reply.Json("[]"))
            }
        }
        rig.activate()
        val order = rig.store.workingPeople(rig.h.now()).map { it.id }
        assertEquals(listOf("u-early", "u-a", "u-z", "u-late", "u-unknown"), order,
            "시작 이른 순 · 같은 시작의 정준 동치 이름은 id 순 · 시작 모름은 맨 뒤")
        rig.h.assertClean()
    }
}
