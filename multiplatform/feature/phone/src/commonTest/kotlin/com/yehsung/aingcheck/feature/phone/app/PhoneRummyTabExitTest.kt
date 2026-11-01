// 원본: Tests/CheckMobileKitTests/V1017RummyTabExitTests.swift @ ios-1017-cube dba0c647 (사용자 답 "맥처럼 방을 나가기")
//
// 재는 것은 요청 건수와 탭 · 라우터 · 단계 값이다. `tap` 은 셸의 탭 막대가 부르는 문(`router.departing`) 그대로이고, 탭이 옮겨 가면 Compose 가 부르는 화면 사라짐은 시험이 대신 부른다(셸 NavHost 쪽은 androidApp ShellDepartureTest).
// iOS 와 다른 것: iOS 의 '탭 재선택(경로 줄기)' · '안 뜬 확인 다시 띄우기' 시험은 대상이 없다 — 이 앱의 탭 재선택은 그 화면에 머물고(ShellDepartureTest), Compose 확인은 값이 그대로면 그대로 떠 있다.
package com.yehsung.aingcheck.feature.phone.app

import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummyPhase
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.me.MeRoute
import com.yehsung.aingcheck.core.stores.me.signOut
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyCard
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyRoomPlan
import com.yehsung.aingcheck.core.stores.rummy.RummyExitReason
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyRoomDeparture
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.departRoom
import com.yehsung.aingcheck.core.stores.rummy.isEngagedInCurrentMatch
import com.yehsung.aingcheck.core.stores.rummy.leaveRoomForExit
import com.yehsung.aingcheck.core.stores.rummy.markEngaged
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.feature.phone.push.PhonePushAuthorization
import com.yehsung.aingcheck.feature.phone.routing.PhoneNavRequest
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget
import com.yehsung.aingcheck.feature.phone.routing.PhoneTab
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class PhoneRummyTabExitTest {
    private companion object {
        const val ROOM = "7e7e0000-0000-4000-8000-000000000069"
        const val PEER = "bbbbbbbb-0000-4000-8000-000000000002"
        const val NOW_MS = 1_789_621_500_000L
        val OK = Reply.Json("""{"status":"ok"}""")
        val DOWN = Reply.Json("""{"message":"down"}""", 500)
    }

    private enum class Seat { host, guest }

    /** 스텁: 큐브 RPC 답을 시험이 고른다. */
    private inner class Rig(val h: PhoneHarness, val seat: Seat) {
        var leave: Reply = OK
        var state: Reply = stateReply("forming", "joined", seat)
        var lobby: Reply = Reply.Json(lobbyText())
        val app get() = h.app
        val router get() = h.app.router
        val games get() = h.app.games
        val rummy get() = h.app.rummy

        fun route(r: RecordedRequest): Reply? = when (r.rpcName) {
            "rummy_lobby" -> lobby
            "rummy_leave" -> leave
            "rummy_state" -> state
            "rummy_heartbeat" -> OK
            "message_unread_summary" -> Reply.Json("""{"status":"ok","total":0,"peers":[]}""")
            "message_history_with_pokes", "message_history_with_reads", "message_history" -> Reply.missingFunction
            "app_user_directory", "message_blocks", "my_blocked_users", "blocked_users" -> Reply.Json("[]")
            "gomoku_lobby", "gomoku_inbox", "tetris_lobby", "chess_lobby" -> Reply.missingFunction
            "work_phone_touch" -> Reply.Json("""{"status":"not_working"}""")
            else -> null
        }

        /** 사람이 탭 막대를 눌렀다(셸과 같은 문) — 옮겨 갔으면 화면을 내린다. */
        fun tap(tab: PhoneTab) {
            router.departing {
                app.tabDidChange(tab)
                if (tab != PhoneTab.games) games.rummyScreenDidDisappear()
            }
        }

        fun comeBack() {
            app.tabDidChange(PhoneTab.games)
            games.rummyScreenDidAppear()
        }

        val leaves: Int get() = h.count("rummy_leave")

        fun apply(status: String = "active", mine: String = "playing") {
            rummy.applyState(room(status, mine, seat))
        }
    }

    private fun lobbyText() = """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10},"invites":[],"public_rooms":[],"users":[]}"""

    private fun roomText(status: String, mine: String, seat: Seat): String {
        val host = if (seat == Seat.host) PhoneHarness.ME else PEER
        return """{"id":"$ROOM","status":"$status","host_id":"$host","stake":5,"seq":${if (status == "forming") 0 else 1},"server_now_ms":$NOW_MS,""" +
            """"seats":[{"seat_no":0,"user_id":"${PhoneHarness.ME}","state":"$mine"},{"seat_no":1,"user_id":"$PEER","state":"${if (status == "forming") "joined" else "playing"}"}],"my_seat_no":0,""" +
            (if (status == "active") """"my_rack":["A1","B2"],"table":[],"turn_seat_no":1,"turn_started_ms":$NOW_MS,"turn_deadline_ms":${NOW_MS + 60_000},"grace_ms":2000""" else """"grace_ms":2000""") + "}"
    }

    private fun room(status: String, mine: String, seat: Seat): RummyMatchState = SwiftJson.decode(RummyMatchState.serializer(), roomText(status, mine, seat))

    private fun stateReply(status: String, mine: String, seat: Seat): Reply = Reply.Json("""{"status":"ok","server_now_ms":$NOW_MS,"state":${roomText(status, mine, seat)}}""")

    /** 게임 탭 큐브 화면에 앉은 방까지 간다. 서버 rummy_state 도 그 방을 말한다. */
    private fun TestScope.seated(seat: Seat, engaged: Boolean = true, retries: List<Double> = emptyList()): Rig {
        lateinit var rig: Rig
        val h = PhoneHarness(this) { rig.route(it) }
        rig = Rig(h, seat)
        h.signIn()
        h.app.rummy.heartbeatEnabled = false
        h.app.games.rummyLeaveRetrySeconds = retries
        h.app.tabDidChange(PhoneTab.games)
        h.app.games.rummyScreenDidAppear()
        runCurrent()
        val id = SwiftUUID.parse(ROOM)!!
        if (engaged) h.app.rummy.markEngaged(id)
        h.app.rummy.applyState(room("forming", "joined", seat))
        assertEquals(RummyPhase.room, h.app.rummy.phase, "전제: 방에 앉았다")
        h.markRequests()
        return rig
    }

    /** 앞에서 돈 왕복 · 2초 상한이 끝난다. */
    private fun TestScope.settle(millis: Long = 5_000) {
        advanceTimeBy(millis)
        runCurrent()
    }

    // MARK: - 손님

    @Test
    fun guestMovesAtOnceAndLeavesInTheBackground() = runTest {
        val r = seated(Seat.guest)
        r.tap(PhoneTab.messages)
        assertEquals(PhoneTab.messages, r.router.selectedTab, "응답을 기다리느라 탭이 안 옮겨 갔다")
        settle()
        assertEquals(1, r.leaves)
        assertEquals(RummyPhase.lobby, r.rummy.phase)
        assertFalse(r.rummy.isEngagedInCurrentMatch)
        assertNotEquals(GamesRummyCard.Line.inRoom, GamesRummyCard.line(r.games))
        assertEquals(RummyPhoneText.tabLeftNotice, r.games.rummyLeftByTabNotice)
        assertNull(r.rummy.notice, "코어 안내줄에 들어가면 방 · 판 화면까지 따라간다")
        r.comeBack()
        assertEquals(RummyPhoneText.tabLeftNotice, r.games.rummyLeftByTabNotice, "돌아온 사람이 안내를 못 본다")
        r.tap(PhoneTab.me)
        assertNull(r.games.rummyLeftByTabNotice, "안내 줄이 다음 방문까지 남는다")
        assertEquals(1, r.leaves)
    }

    // MARK: - 나가는 전환(화면은 기본 700ms 동안 합성에 남아 '보임'이 참이다 — 시험 밖 Compose 는 사라짐을 늦게 부른다)

    /** 평소 경우: 응답이 전환보다 빠르다. 사라짐 앞에 온 응답이 안내를 '봤음'으로 적으면 돌아온 사람이 설명 없는 로비를 본다. */
    @Test
    fun tabNoticeSurvivesAFastAnswerDuringTheExitTransition() = runTest {
        val r = seated(Seat.guest)
        r.router.departing { r.app.tabDidChange(PhoneTab.messages) }
        settle(500)
        assertEquals(1, r.leaves, "전제: 전환이 끝나기 전에 응답이 왔다")
        assertTrue(r.games.isRummyScreenVisible, "전제: 화면이 아직 합성에 있다")
        r.games.rummyScreenDidDisappear()
        assertEquals(RummyPhoneText.tabLeftNotice, r.games.rummyLeftByTabNotice, "안내가 보이기도 전에 지워졌다")
        r.comeBack()
        assertEquals(RummyPhoneText.tabLeftNotice, r.games.rummyLeftByTabNotice)
        r.tap(PhoneTab.me)
        assertNull(r.games.rummyLeftByTabNotice, "본 안내는 다음에 떠날 때 지운다")
    }

    /** 비행기 모드 · 서버의 빠른 오류: 실패가 전환보다 빠르다. '보고 있다'로 쳐서 되보내기를 끊으면 망이 돌아와도 자리가 90초 남고, 그사이 시작되면 모르는 사이 판돈이 걷힌다. */
    @Test
    fun retriesSurviveAFastFailureDuringTheExitTransition() = runTest {
        val r = seated(Seat.guest, retries = listOf(3.0, 10.0))
        r.leave = DOWN
        r.router.departing { r.app.tabDidChange(PhoneTab.messages) }
        settle(500)
        assertEquals(1, r.leaves, "전제: 전환이 끝나기 전에 실패했다")
        assertTrue(r.games.isRummyScreenVisible, "전제: 화면이 아직 합성에 있다")
        r.games.rummyScreenDidDisappear()
        r.leave = OK
        settle(3_000)
        assertEquals(2, r.leaves, "되보내기가 끊겼다")
        assertEquals(RummyPhase.lobby, r.rummy.phase)
        assertEquals(RummyPhoneText.tabLeftNotice, r.games.rummyLeftByTabNotice)
    }

    /** 뒤로로 나간 손님도 같다(부르는 쪽이 곧바로 화면을 내린다 — GamesRummyBackState.handleBack). */
    @Test
    fun backRetriesSurviveAFastFailureDuringTheExitTransition() = runTest {
        val r = seated(Seat.guest, retries = listOf(3.0))
        r.leave = DOWN
        r.games.leaveRummyRoomFromScreen(personIsLeaving = true)
        settle(500)
        assertEquals(1, r.leaves)
        r.games.rummyScreenDidDisappear()
        r.leave = OK
        settle(3_000)
        assertEquals(2, r.leaves, "뒤로 나간 손님의 되보내기가 끊겼다")
    }

    /** 방장: [방 닫고 나가기] 뒤 응답 전에 다른 탭을 눌렀고, 응답이 전환 안에 왔다. onLeft 가 돌면 이미 옮겨 간 탭의 맨 위 화면을 뺀다. */
    @Test
    fun hostMovedDuringTheExitTransitionIsNotPopped() = runTest {
        val r = seated(Seat.host)
        val gate = CompletableDeferred<Unit>()
        r.leave = Reply.Gate(gate, OK)
        var left = 0
        r.games.leaveRummyRoomFromScreen(onLeft = { left += 1 })
        runCurrent()
        r.router.departing { r.app.tabDidChange(PhoneTab.messages) }
        assertEquals(PhoneTab.messages, r.router.selectedTab)
        gate.complete(Unit)
        settle(500)
        assertTrue(r.games.isRummyScreenVisible, "전제: 화면이 아직 합성에 있다")
        assertEquals(0, left, "옮겨 간 탭의 화면을 뺐다")
    }

    /** 기준선: 사람이 안 떠났으면 화면이 보이는 동안 전과 같다 — 되보내지 않고 사람에게 맡긴다 · onLeft 가 돈다. 떠났다가 돌아오면 깃발이 내려 다시 맡긴다. */
    @Test
    fun aPersonStillOnTheScreenStaysInCharge() = runTest {
        val r = seated(Seat.guest, retries = listOf(3.0))
        r.leave = DOWN
        r.games.leaveRummyRoomFromScreen()
        settle(10_000)
        assertEquals(1, r.leaves, "방을 보고 있는 사람을 되보냈다")

        val host = seated(Seat.host)
        var left = 0
        host.games.leaveRummyRoomFromScreen(onLeft = { left += 1 })
        settle(500)
        assertEquals(1, left)

        val back = seated(Seat.guest, retries = listOf(3.0))
        back.leave = DOWN
        back.router.departing { back.app.tabDidChange(PhoneTab.messages) }
        settle(500)
        back.games.rummyScreenDidDisappear()
        back.comeBack()
        settle(10_000)
        assertEquals(1, back.leaves, "돌아와 방을 보는 사람을 내보냈다")

        // 전환이 끝나기 전에 돌아왔다(옛 화면의 사라짐보다 새 화면의 나타남이 먼저 온다).
        val quick = seated(Seat.guest, retries = listOf(3.0))
        quick.leave = DOWN
        quick.router.departing { quick.app.tabDidChange(PhoneTab.messages) }
        settle(500)
        quick.comeBack()
        settle(10_000)
        assertEquals(1, quick.leaves, "전환 중에 돌아온 사람을 내보냈다")
    }

    /** 뒤로 경쟁과 같은 뿌리: 나가는 중에 탭을 또 옮기고 푸시가 와도 rummy_leave 는 1건. */
    @Test
    fun guestSendsOnceWhileMovingAround() = runTest {
        val r = seated(Seat.guest)
        r.router.departing { r.app.tabDidChange(PhoneTab.messages) }
        r.router.departing { r.app.tabDidChange(PhoneTab.me) }
        r.app.openRoute(PhoneRouteTarget.Now)
        assertEquals(PhoneTab.now, r.router.selectedTab)
        r.games.rummyScreenDidDisappear()
        settle()
        r.tap(PhoneTab.rankings)
        settle()
        assertEquals(1, r.leaves)
    }

    // MARK: - 방장

    @Test
    fun hostAsksAndStays() = runTest {
        val r = seated(Seat.host)
        var moved = false
        r.router.departing { moved = true }
        settle(100)
        assertFalse(moved, "확인 전에 탭이 옮겨 갔다")
        assertEquals(0, r.leaves)
        assertEquals(RummyCloseDecision.confirmCloseRoom, r.games.rummyDeparturePrompt)
        assertEquals(RummyPhase.room, r.rummy.phase)
        assertEquals(PhoneTab.games, r.router.selectedTab)
    }

    @Test
    fun hostConfirmLeavesThenGoes() = runTest {
        val r = seated(Seat.host)
        r.tap(PhoneTab.me)
        r.games.confirmRummyDeparture()
        r.games.confirmRummyDeparture()
        assertNull(r.games.rummyDeparturePrompt)
        assertEquals(PhoneTab.games, r.router.selectedTab, "응답 전에 옮겨 갔다 — 안 닫혔으면 남들이 빈 방에서 기다린다")
        settle()
        assertEquals(1, r.leaves, "두 번 눌러 두 번 나갔다")
        assertEquals(PhoneTab.me, r.router.selectedTab, "수락했는데 가려던 탭으로 안 갔다")
        assertEquals(RummyPhase.lobby, r.rummy.phase)
    }

    @Test
    fun hostCancelSendsNothing() = runTest {
        val r = seated(Seat.host)
        r.tap(PhoneTab.me)
        r.games.cancelRummyDeparture()
        r.games.confirmRummyDeparture()
        settle()
        assertEquals(0, r.leaves)
        assertEquals(PhoneTab.games, r.router.selectedTab)
        assertEquals(RummyPhase.room, r.rummy.phase)
        assertNull(r.games.rummyDeparturePrompt)
    }

    @Test
    fun hostConfirmFailureStaysAndCanTryAgain() = runTest {
        val r = seated(Seat.host)
        r.leave = DOWN
        r.tap(PhoneTab.me)
        r.games.confirmRummyDeparture()
        settle()
        assertEquals(1, r.leaves)
        assertEquals(PhoneTab.games, r.router.selectedTab, "방이 안 닫혔는데 탭을 옮겼다 — 남들이 빈 방에서 기다린다")
        assertEquals(RummyPhase.room, r.rummy.phase)
        assertTrue(r.games.isRummyLeaveUnconfirmed)
        assertNull(r.rummy.notice, "판 화면이 읽는 줄에 넣었다 — 그새 시작되면 [나가기](기권)를 권한다")
        r.leave = OK
        r.tap(PhoneTab.me)
        r.games.confirmRummyDeparture()
        settle()
        assertEquals(2, r.leaves)
        assertEquals(PhoneTab.me, r.router.selectedTab)
        assertEquals(RummyPhase.lobby, r.rummy.phase)
    }

    /** 수락 후 응답을 기다리는 사이 다른 탭으로 갔다(푸시 등) — 끌고 가지 않는다 · 1건. */
    @Test
    fun hostMovedWhileLeavingIsNotDraggedBack() = runTest {
        val r = seated(Seat.host)
        val gate = CompletableDeferred<Unit>()
        r.leave = Reply.Gate(gate, OK)
        r.tap(PhoneTab.me)
        r.games.confirmRummyDeparture()
        runCurrent()
        assertEquals(1, r.leaves)
        r.tap(PhoneTab.messages)
        assertEquals(PhoneTab.messages, r.router.selectedTab)
        gate.complete(Unit)
        settle()
        assertEquals(PhoneTab.messages, r.router.selectedTab, "사람이 고른 탭에서 수락 때 탭으로 끌고 갔다")
        assertEquals(1, r.leaves)
        assertEquals(RummyPhase.lobby, r.rummy.phase)
    }

    @Test
    fun hostMovedAndFailedRetriesAlone() = runTest {
        val r = seated(Seat.host, retries = listOf(1.0))
        val gate = CompletableDeferred<Unit>()
        r.leave = Reply.Gate(gate, DOWN)
        r.tap(PhoneTab.me)
        r.games.confirmRummyDeparture()
        runCurrent()
        r.tap(PhoneTab.messages)
        r.leave = OK
        gate.complete(Unit)
        settle()
        assertEquals(2, r.leaves, "화면 밖에 방이 열린 채 남았다")
        assertEquals(RummyPhase.lobby, r.rummy.phase)
        assertEquals(PhoneTab.messages, r.router.selectedTab)
    }

    /** 나간 뒤 로비 조회를 기다리지 않고 간다 — 늦은 조회에 빈 로비로 묶이지 않는다. */
    @Test
    fun hostResumeDoesNotWaitForTheLobby() = runTest {
        val r = seated(Seat.host)
        val gate = CompletableDeferred<Unit>()
        r.lobby = Reply.Gate(gate, Reply.Json(lobbyText()))
        r.tap(PhoneTab.me)
        r.games.confirmRummyDeparture()
        settle()
        assertEquals(1, r.leaves)
        assertEquals(PhoneTab.me, r.router.selectedTab, "로비 응답을 기다리느라 탭이 안 옮겨 갔다")
        gate.complete(Unit)
        settle()
    }

    // MARK: - 이탈이 아닌 것

    @Test
    fun idleDeviceSendsNothingAndAsksNothing() = runTest {
        for (seat in listOf(Seat.guest, Seat.host)) {
            val r = seated(seat, engaged = false)
            r.tap(PhoneTab.now)
            settle()
            assertEquals(PhoneTab.now, r.router.selectedTab)
            assertNull(r.games.rummyDeparturePrompt)
            assertEquals(0, r.leaves, "놀던 기기가 나갔다")
            assertEquals(0, r.h.count("rummy_state"), "놀던 기기가 방을 읽었다")
            assertEquals(RummyPhase.room, r.rummy.phase)
        }
    }

    @Test
    fun backgroundSendsNothing() = runTest {
        for (seat in listOf(Seat.guest, Seat.host)) {
            val r = seated(seat)
            r.games.appDidEnterBackground()
            settle()
            assertEquals(0, r.leaves)
            assertNull(r.games.rummyDeparturePrompt)
            assertEquals(RummyPhase.room, r.rummy.phase)
            assertTrue(r.games.isRummyScreenVisible)
        }
    }

    @Test
    fun playingIsUntouched() = runTest {
        val r = seated(Seat.host)
        r.state = stateReply("active", "playing", Seat.host)
        r.apply()
        assertEquals(RummyPhase.playing, r.rummy.phase)
        r.tap(PhoneTab.now)
        settle()
        assertEquals(PhoneTab.now, r.router.selectedTab)
        r.comeBack()
        r.app.openRoute(PhoneRouteTarget.Messages)
        r.games.rummyScreenDidDisappear()
        settle()
        assertEquals(PhoneTab.messages, r.router.selectedTab)
        assertNull(r.games.rummyDeparturePrompt)
        assertEquals(0, r.leaves, "판 중 탭 이동이 기권이 됐다")
        assertEquals(RummyPhase.playing, r.rummy.phase)
    }

    @Test
    fun rulesSheetIsNotDeparture() = runTest {
        val r = seated(Seat.guest)
        r.rummy.rulesShown = true
        runCurrent()
        r.rummy.rulesShown = false
        settle()
        assertEquals(0, r.leaves)
        assertEquals(RummyPhase.room, r.rummy.phase)
    }

    @Test
    fun hostPromptClosesTheRulesSheet() = runTest {
        val r = seated(Seat.host)
        r.rummy.rulesShown = true
        r.app.openRoute(PhoneRouteTarget.Messages)
        assertEquals(RummyCloseDecision.confirmCloseRoom, r.games.rummyDeparturePrompt)
        assertFalse(r.rummy.rulesShown)
    }

    @Test
    fun offScreenMovesAreNotDeparture() = runTest {
        val r = seated(Seat.host)
        r.games.rummyScreenDidDisappear()
        r.app.tabDidChange(PhoneTab.now)
        r.tap(PhoneTab.me)
        settle()
        assertEquals(PhoneTab.me, r.router.selectedTab)
        assertNull(r.games.rummyDeparturePrompt)
        assertEquals(0, r.leaves)
    }

    // MARK: - 판 시작과의 경쟁

    @Test
    fun guestRaceWithStartHoldsTheMatchAndComesBack() = runTest {
        val r = seated(Seat.guest)
        r.state = stateReply("active", "playing", Seat.guest)
        r.tap(PhoneTab.messages)
        settle()
        assertEquals(0, r.leaves, "시작된 판에 나가기를 보내 기권됐다")
        assertEquals(RummyPhase.playing, r.rummy.phase)
        // 시작 알림(applyState → presentWindow)이 화면을 연다 — 앱이 앞이면. 이 조립은 sceneDidBecomeActive 를 안 불러 조용히 넘어간다 — 아래 시험이 그 문을 잰다.
        assertFalse(r.games.isRummyLeaveUnconfirmed)
    }

    @Test
    fun guestRaceReopensTheScreenWhenTheAppIsActive() = runTest {
        val r = seated(Seat.guest)
        r.games.appDidBecomeActive()
        r.state = stateReply("active", "playing", Seat.guest)
        r.tap(PhoneTab.messages)
        settle()
        assertEquals(0, r.leaves)
        assertEquals(PhoneTab.games, r.router.selectedTab, "시작된 판 앞으로 안 돌아왔다")
        assertTrue(r.router.pendingRequests.any { it == PhoneNavRequest.PresentGames(GamesDestination.Rummy) }, "${r.router.pendingRequests}")
        r.games.appDidEnterBackground()
    }

    @Test
    fun hostRaceAtConfirmStaysPut() = runTest {
        val r = seated(Seat.host)
        r.tap(PhoneTab.messages)
        r.state = stateReply("active", "playing", Seat.host)
        r.games.confirmRummyDeparture()
        settle()
        assertEquals(0, r.leaves)
        assertEquals(RummyPhase.playing, r.rummy.phase)
        assertEquals(PhoneTab.games, r.router.selectedTab)
    }

    @Test
    fun hostStaleConfirmAfterStartSendsNothing() = runTest {
        val r = seated(Seat.host)
        r.tap(PhoneTab.messages)
        r.apply()
        r.games.confirmRummyDeparture()
        settle()
        assertEquals(0, r.leaves)
        assertEquals(PhoneTab.games, r.router.selectedTab)
    }

    @Test
    fun hostConfirmAfterRoomGoneJustGoes() = runTest {
        val r = seated(Seat.host)
        r.tap(PhoneTab.messages)
        r.rummy.applyState(room("cancelled", "joined", Seat.host))
        assertEquals(RummyPhase.lobby, r.rummy.phase)
        r.games.confirmRummyDeparture()
        settle()
        assertEquals(0, r.leaves)
        assertEquals(PhoneTab.messages, r.router.selectedTab)
    }

    // MARK: - 다른 길

    @Test
    fun guestRouteLeavesAndOpens() = runTest {
        val r = seated(Seat.guest)
        r.app.openRoute(PhoneRouteTarget.Message(PEER))
        r.games.rummyScreenDidDisappear()
        settle()
        assertEquals(1, r.leaves)
        assertEquals(PhoneTab.messages, r.router.selectedTab)
        assertEquals(PhoneRouteTarget.Message(PEER), r.router.lastOpenedTarget)
        // 위젯 · 딥링크도 같은 문이다.
        val widget = seated(Seat.guest)
        assertTrue(widget.app.handleOpenRoute(PhoneRouteTarget.Now))
        widget.games.rummyScreenDidDisappear()
        settle()
        assertEquals(1, widget.leaves)
        assertEquals(PhoneTab.now, widget.router.selectedTab)
    }

    @Test
    fun hostRouteWaitsAndOpensAfterConfirm() = runTest {
        val r = seated(Seat.host)
        val before = r.router.lastOpenedTarget
        r.app.openRoute(PhoneRouteTarget.Message(PEER))
        settle(100)
        assertEquals(0, r.leaves)
        assertEquals(PhoneTab.games, r.router.selectedTab)
        assertEquals(before, r.router.lastOpenedTarget, "확인 전에 라우트가 열렸다")
        assertEquals(RummyCloseDecision.confirmCloseRoom, r.games.rummyDeparturePrompt)
        r.games.confirmRummyDeparture()
        settle()
        assertEquals(1, r.leaves)
        assertEquals(PhoneTab.messages, r.router.selectedTab)
        assertEquals(PhoneRouteTarget.Message(PEER), r.router.lastOpenedTarget)

        val cancelled = seated(Seat.host)
        assertTrue(cancelled.app.handleOpenRoute(PhoneRouteTarget.Now))
        cancelled.games.cancelRummyDeparture()
        settle()
        assertEquals(PhoneTab.games, cancelled.router.selectedTab)
        assertEquals(0, cancelled.leaves)
    }

    /** 나 탭 라우트는 router.open 뒤에 쌓기를 더 한다 — 방장이 멈춰 묻는 동안 그 쌓기가 먼저 나가면 묻는 사이 나 탭으로 옮겨 간다. */
    @Test
    fun hostRouteToMeStacksNothingBeforeConfirm() = runTest {
        val r = seated(Seat.host)
        r.router.drainRequests()
        r.app.openRoute(PhoneRouteTarget.Me(MeRoute.Shop))
        assertEquals(emptyList(), r.router.pendingRequests, "확인 전에 이동 요청이 쌓였다")
        r.games.confirmRummyDeparture()
        settle()
        assertEquals(1, r.leaves)
        assertEquals(2, r.router.pendingRequests.size, "수락 뒤엔 나 탭 + 상점: ${r.router.pendingRequests}")
    }

    /** 다른 대결 화면 열기(오목 · 체스 · 테트리스 시작)도 문을 지난다 — iOS 는 체스 · 테트리스가 안 지나지만, 이 앱은 present 한 문이라 자리가 남는 길을 둘 까닭이 없다. */
    @Test
    fun presentingAnotherGameGoesThroughTheDoor() = runTest {
        val guest = seated(Seat.guest)
        guest.router.present(GamesDestination.Chess)
        guest.games.rummyScreenDidDisappear()
        settle()
        assertEquals(1, guest.leaves)
        assertEquals(PhoneNavRequest.PresentGames(GamesDestination.Chess), guest.router.pendingRequests.last())

        val host = seated(Seat.host)
        host.router.drainRequests()
        host.router.present(GamesDestination.Chess)
        assertEquals(emptyList(), host.router.pendingRequests)
        assertEquals(RummyCloseDecision.confirmCloseRoom, host.games.rummyDeparturePrompt)
    }

    // MARK: - 실패

    /**
     * 결함 ①(iOS 검토): 실패 후 **화면 밖에서 자리가 되살아나면** 모르는 사이 방장이 시작해 판돈이 걷힌다. 되돌린 방은 화면 밖이면 하트비트가 안 돈다 — 서버가 시작 검사에서 뺀다. 되보내기 합은 끊김 기준 90초를 넘긴다.
     */
    @Test
    fun failedLeaveDoesNotReviveTheSeatOffScreen() = runTest {
        val fresh = PhoneHarness(this).app.games.rummyLeaveRetrySeconds
        assertEquals(listOf(3.0, 10.0, 30.0, 60.0), fresh, "되보내기 기본값이 바뀌었다")
        assertTrue(fresh.sum() > 90, "되보내기가 끝난 뒤 서버가 빼 주기 전까지 빈틈이 남는다")

        val r = seated(Seat.guest)
        r.rummy.heartbeatSeconds = 10.0
        r.rummy.heartbeatEnabled = true
        r.rummy.applyState(room("forming", "joined", Seat.guest)) // 하트비트 값을 다시 계산한다.
        assertEquals(SwiftUUID.parse(ROOM), r.rummy.heartbeatMatchID, "전제: 방 화면에서는 돈다")
        r.leave = DOWN
        r.tap(PhoneTab.messages)
        settle()
        assertEquals(1, r.leaves)
        assertEquals(RummyPhase.room, r.rummy.phase, "전제: 자리가 남아 방을 되돌렸다")
        assertNull(r.rummy.heartbeatMatchID, "화면 밖 자리가 살아났다 — 모르는 사이 판돈이 걷힌다")
        val beats = r.h.count("rummy_heartbeat")
        settle(120_000)
        assertEquals(beats, r.h.count("rummy_heartbeat"), "화면 밖에서 하트비트가 나갔다")
    }

    /**
     * 결함 ②(iOS 검토): **방을 못 읽었는데 나가기를 보내면** 그새 시작된 판을 기권시킨다. 못 읽으면 rummy_leave 0건 · 방 그대로 · 자리 있음을 말한다.
     */
    @Test
    fun unreadRoomSendsNoLeaveSoAStartedMatchIsNotForfeited() = runTest {
        val r = seated(Seat.guest)
        r.state = Reply.Offline
        r.tap(PhoneTab.messages)
        settle()
        assertEquals(1, r.h.count("rummy_state"), "전제: 읽어 봤다")
        assertEquals(0, r.leaves, "방인지 판인지 모른 채 나가기를 보냈다")
        assertEquals(PhoneTab.messages, r.router.selectedTab)
        assertEquals(RummyPhase.room, r.rummy.phase)
        assertTrue(r.games.isRummyLeaveUnconfirmed)
        assertEquals(RummyPhoneText.leaveUnconfirmedDetail, GamesRummyCard.detail(r.games))
        // 응답이 안 오는 읽기도 같다(2초 상한).
        val hung = seated(Seat.guest)
        hung.state = Reply.Gate(CompletableDeferred(), Reply.Offline)
        hung.tap(PhoneTab.messages)
        settle()
        assertEquals(0, hung.leaves, "읽기가 늦어 나가기를 보냈다")
        assertEquals(RummyPhase.room, hung.rummy.phase)
    }

    @Test
    fun unreadThenRetryReadsThenLeaves() = runTest {
        val r = seated(Seat.guest, retries = listOf(1.0))
        val room = r.state
        r.state = Reply.Offline
        r.tap(PhoneTab.messages)
        runCurrent()
        r.state = room
        settle()
        assertEquals(1, r.leaves)
        assertEquals(RummyPhase.lobby, r.rummy.phase)
        assertFalse(r.games.isRummyLeaveUnconfirmed)
    }

    @Test
    fun retryFindingAStartedMatchHoldsIt() = runTest {
        val r = seated(Seat.guest, retries = listOf(1.0))
        r.state = Reply.Offline
        r.tap(PhoneTab.messages)
        runCurrent()
        r.state = stateReply("active", "playing", Seat.guest)
        settle()
        assertEquals(0, r.leaves, "되보내기가 시작된 판을 기권시켰다")
        assertEquals(RummyPhase.playing, r.rummy.phase)
        assertFalse(r.games.isRummyLeaveUnconfirmed)
    }

    @Test
    fun heldMatchIsNotLeft() = runTest {
        val r = seated(Seat.guest)
        r.apply()
        assertEquals(RummyRoomDeparture.startedMatch, r.rummy.departRoom(RummyExitReason.windowClosed))
        assertEquals(0, r.leaves)
        assertEquals(RummyPhase.playing, r.rummy.phase)
    }

    /** 읽는 사이 폴링이 판을 들고 왔고 읽기는 실패했다: 다시 시도할 사람이 있는 길(폰)도, 없는 길(leavesWhenUnread)도 rummy_leave 0건. */
    @Test
    fun matchArrivingWhileReadingIsNotLeft() = runTest {
        val phone = seated(Seat.guest)
        val phoneGate = CompletableDeferred<Unit>()
        phone.state = Reply.Gate(phoneGate, Reply.Offline)
        val departing = async { phone.rummy.departRoom(RummyExitReason.windowClosed) }
        runCurrent()
        assertEquals(1, phone.h.count("rummy_state"))
        phone.apply()
        phoneGate.complete(Unit)
        runCurrent()
        assertEquals(RummyRoomDeparture.startedMatch, departing.await())
        assertEquals(0, phone.leaves, "읽기 실패 뒤 쥔 판에 나가기를 보내 기권됐다")

        val other = seated(Seat.guest)
        val otherGate = CompletableDeferred<Unit>()
        other.state = Reply.Gate(otherGate, Reply.Offline)
        val closing = async { other.rummy.leaveRoomForExit(RummyExitReason.signOut) }
        runCurrent()
        other.apply()
        otherGate.complete(Unit)
        runCurrent()
        assertFalse(closing.await())
        assertEquals(0, other.leaves)
    }

    /** 다시 시도할 사람이 없는 길(로그아웃 앞 등)은 그대로: 못 읽어도 나간다. */
    @Test
    fun noRetryPathStillLeavesWhenUnread() = runTest {
        val r = seated(Seat.guest)
        r.state = Reply.Offline
        val job = async { r.rummy.leaveRoomForExit(RummyExitReason.signOut) }
        settle()
        assertTrue(job.await())
        assertEquals(1, r.leaves)
    }

    @Test
    fun guestFailureKeepsTheSeatVisibleAndCanLeaveAgain() = runTest {
        val r = seated(Seat.guest)
        r.leave = DOWN
        r.tap(PhoneTab.messages)
        settle()
        assertEquals(1, r.leaves)
        assertEquals(PhoneTab.messages, r.router.selectedTab, "탭은 이미 옮겨 갔다")
        assertEquals(RummyPhase.room, r.rummy.phase, "서버엔 자리가 남았는데 화면은 나왔다고 말한다")
        assertTrue(r.rummy.isEngagedInCurrentMatch, "되돌린 방이 놀던 기기로 읽혀 다시 나갈 수 없다")
        assertEquals(GamesRummyCard.Line.inRoom, GamesRummyCard.line(r.games))
        assertEquals(RummyPhoneText.inRoomChip, GamesRummyCard.chip(r.games))
        assertEquals(RummyPhoneText.leaveUnconfirmedDetail, GamesRummyCard.detail(r.games))
        assertTrue(r.games.isRummyLeaveUnconfirmed)
        // 늦게 온 로비가 되돌린 방을 다시 접지 않는다.
        r.leave = OK
        r.comeBack()
        settle(100)
        assertEquals(RummyPhase.room, r.rummy.phase, "돌아온 로비 조회가 되돌린 방을 접었다")
        r.tap(PhoneTab.now)
        settle()
        assertEquals(2, r.leaves)
        assertEquals(RummyPhase.lobby, r.rummy.phase)
        assertFalse(r.games.isRummyLeaveUnconfirmed)
        assertEquals(RummyPhoneText.tabLeftNotice, r.games.rummyLeftByTabNotice)
    }

    @Test
    fun retryReachesAloneOffScreen() = runTest {
        val r = seated(Seat.guest, retries = listOf(3.0, 10.0, 30.0, 60.0))
        r.leave = DOWN
        r.tap(PhoneTab.messages)
        settle(1_000)
        assertEquals(1, r.leaves)
        r.leave = OK
        settle(3_000)
        assertEquals(2, r.leaves, "3초 뒤 되보내지 않았다")
        settle(120_000)
        assertEquals(2, r.leaves, "닿은 뒤에도 또 보냈다")
        assertEquals(RummyPhase.lobby, r.rummy.phase)
        assertEquals(RummyPhoneText.tabLeftNotice, r.games.rummyLeftByTabNotice)
    }

    @Test
    fun retryIsBoundedStopsWhenBackAndOnSignOut() = runTest {
        val bounded = seated(Seat.guest, retries = listOf(3.0, 10.0, 30.0, 60.0))
        bounded.leave = DOWN
        bounded.tap(PhoneTab.messages)
        settle(300_000)
        assertEquals(5, bounded.leaves, "상한(처음 + 3 · 10 · 30 · 60초)을 넘겼다")
        assertTrue(bounded.games.isRummyLeaveUnconfirmed)
        assertEquals(RummyPhase.room, bounded.rummy.phase)

        val back = seated(Seat.guest, retries = listOf(3.0))
        back.leave = DOWN
        back.tap(PhoneTab.messages)
        settle(1_000)
        assertTrue(back.games.isRummyLeaveUnconfirmed)
        back.comeBack()
        settle(10_000)
        assertEquals(1, back.leaves, "방을 다시 보고 있는 사람을 내보냈다")
        assertEquals(RummyPhase.room, back.rummy.phase)

        val out = seated(Seat.guest, retries = listOf(30.0))
        out.leave = DOWN
        out.tap(PhoneTab.messages)
        settle(1_000)
        assertTrue(out.games.isRummyLeaveUnconfirmed)
        out.games.reset()
        out.rummy.reset()
        settle(60_000)
        assertEquals(1, out.leaves, "로그아웃했는데 나가기가 또 나갔다")
        assertNull(out.games.rummyLeftByTabNotice)
        assertFalse(out.games.isRummyLeaveUnconfirmed)
    }

    @Test
    fun signOutTakesItsOwnRoad() = runTest {
        val r = seated(Seat.host)
        r.tap(PhoneTab.me)
        assertEquals(RummyCloseDecision.confirmCloseRoom, r.games.rummyDeparturePrompt)
        val job = launch { r.app.me.signOut() }
        settle()
        job.join()
        assertNull(r.games.rummyDeparturePrompt)
        assertEquals(PhoneTab.now, r.router.selectedTab)
    }

    // MARK: - 하트비트

    private fun TestScope.beating(seat: Seat): Rig {
        val r = seated(seat)
        r.rummy.heartbeatSeconds = 3_600.0
        r.rummy.heartbeatEnabled = true
        r.rummy.applyState(room("forming", "joined", seat))
        return r
    }

    @Test
    fun roomHeartbeatFollowsTheScreen() = runTest {
        val r = beating(Seat.guest)
        val id = SwiftUUID.parse(ROOM)
        assertEquals(id, r.rummy.heartbeatMatchID)
        r.games.rummyScreenDidDisappear()
        assertNull(r.rummy.heartbeatMatchID, "화면 밖 자리가 살아 있어 모르는 사이 판돈이 걷힌다")
        val beats = r.h.count("rummy_heartbeat")
        r.games.rummyScreenDidAppear()
        assertEquals(id, r.rummy.heartbeatMatchID)
        runCurrent()
        assertEquals(beats + 1, r.h.count("rummy_heartbeat"), "돌아온 뒤 10초 사이 시작되면 빠진다")
        r.games.rummyScreenDidDisappear()
    }

    @Test
    fun matchHeartbeatIgnoresTheScreen() = runTest {
        val r = beating(Seat.guest)
        r.games.rummyScreenDidDisappear()
        assertNull(r.rummy.heartbeatMatchID)
        r.apply()
        assertEquals(RummyPhase.playing, r.rummy.phase)
        assertEquals(SwiftUUID.parse(ROOM), r.rummy.heartbeatMatchID, "시작된 판의 하트비트가 안 돌아 끊김 기권된다")
    }

    /** 어느 문도 안 지나고 화면 밖에 앉았다(앱을 다시 켬) — 기본값이 쉼이다. */
    @Test
    fun relaunchedSeatHasNoHeartbeat() = runTest {
        lateinit var rig: Rig
        val h = PhoneHarness(this) { rig.route(it) }
        rig = Rig(h, Seat.guest)
        h.signIn()
        h.app.rummy.heartbeatSeconds = 3_600.0
        h.app.rummy.heartbeatEnabled = true
        h.app.rummy.markEngaged(SwiftUUID.parse(ROOM)!!)
        h.app.rummy.applyState(room("forming", "joined", Seat.guest))
        assertEquals(RummyPhase.room, h.app.rummy.phase)
        assertNull(h.app.rummy.heartbeatMatchID)
    }

    // MARK: - 낡은 말

    @Test
    fun unconfirmedLineDoesNotOutliveTheRoom() = runTest {
        val started = seated(Seat.guest)
        started.leave = DOWN
        started.tap(PhoneTab.messages)
        settle()
        assertTrue(started.games.isRummyLeaveUnconfirmed)
        started.comeBack()
        started.apply()
        assertEquals(RummyPhase.playing, started.rummy.phase)
        assertFalse(started.games.isRummyLeaveUnconfirmed)
        assertNull(started.rummy.notice, "판 화면 상태 줄이 차례 안내 대신 이 말을 띄운다")

        val closed = seated(Seat.guest)
        closed.leave = DOWN
        closed.tap(PhoneTab.messages)
        settle()
        closed.rummy.applyState(room("cancelled", "joined", Seat.guest))
        assertFalse(closed.games.isRummyLeaveUnconfirmed)
        assertNotEquals(GamesRummyCard.Line.inRoom, GamesRummyCard.line(closed.games))
    }

    // MARK: - 화면의 [나가기]

    @Test
    fun screenButtonDoesNotHideTheSeat() = runTest {
        val r = seated(Seat.guest)
        r.leave = DOWN
        r.games.leaveRummyRoomFromScreen()
        r.games.leaveRummyRoomFromScreen()
        settle()
        assertEquals(1, r.leaves)
        assertEquals(RummyPhase.room, r.rummy.phase, "서버엔 자리가 남았는데 로비를 보였다")
        assertTrue(r.games.isRummyLeaveUnconfirmed)
        r.leave = OK
        r.games.leaveRummyRoomFromScreen()
        settle()
        assertEquals(2, r.leaves)
        assertEquals(RummyPhase.lobby, r.rummy.phase)
        assertNull(r.games.rummyLeftByTabNotice, "스스로 누른 나가기에 탭 얘기를 했다")
    }

    @Test
    fun screenHostConfirmStaysOnFailureAndSendsNothingOnStart() = runTest {
        val failed = seated(Seat.host)
        failed.leave = DOWN
        var left = 0
        failed.games.leaveRummyRoomFromScreen(onLeft = { left += 1 })
        settle()
        assertEquals(0, left, "못 닿았는데 화면을 내렸다")
        assertEquals(RummyPhase.room, failed.rummy.phase)
        assertTrue(failed.games.isRummyLeaveUnconfirmed)
        failed.leave = OK
        failed.games.leaveRummyRoomFromScreen(onLeft = { left += 1 })
        settle()
        assertEquals(1, left)

        val started = seated(Seat.host)
        started.state = stateReply("active", "playing", Seat.host)
        started.apply()
        started.games.leaveRummyRoomFromScreen()
        settle()
        assertEquals(0, started.leaves, "지난 확인으로 시작된 판을 기권시켰다")
        assertEquals(RummyPhase.playing, started.rummy.phase)
    }

    // MARK: - 판 위에 스스로 뜨는 시트(iOS d5c9eeff)

    /** 알림 설명 시트: 판이 가로로 서 있으면 미룬다 · 세로로 돌아오면 다시 판정한다. */
    @Test
    fun primerWaitsForPortrait() = runTest {
        val r = seated(Seat.guest)
        val push = r.app.push
        push.appDidBecomeActive()
        assertTrue(push.shouldPresentPrimer(PhonePushAuthorization.notDetermined), "기준선: 방(세로)에서는 띄울 때다")
        r.apply()
        assertEquals(GamesRummyInterfaceOrientation.landscape, r.games.rummyInterfaceOrientation)
        assertFalse(push.shouldPresentPrimer(PhonePushAuthorization.notDetermined), "가로 판 위에 설명 시트가 뜬다")
        r.rummy.applyState(room("finished", "done", Seat.guest).copy(seq = 2))
        assertTrue(push.shouldPresentPrimer(PhonePushAuthorization.notDetermined), "결과(세로)인데 안 띄운다")
        r.games.setRummyFinalBoardShown(true)
        assertFalse(push.shouldPresentPrimer(PhonePushAuthorization.notDetermined), "[최종 판](가로) 위에 설명 시트가 뜬다")
        r.games.rummyScreenDidDisappear()
        assertTrue(push.shouldPresentPrimer(PhonePushAuthorization.notDetermined))
    }

    /** 생일 선물 시트: 놀던 기기의 가로 판 위에 안 뜬다(확성기는 뜬다) · 판을 떠나면 다음 기회에 뜬다. */
    @Test
    fun giftWaitsForPortraitOnAnIdleDevice() = runTest {
        val r = seated(Seat.guest, engaged = false)
        r.apply()
        assertEquals(GamesRummyInterfaceOrientation.landscape, r.games.rummyInterfaceOrientation)
        assertFalse(r.rummy.isEngagedInCurrentMatch, "전제: 놀던 기기")
        assertFalse(r.games.isAnyMatchScreenVisible, "놀던 기기는 확성기를 안 미룬다")
        assertTrue(r.app.me.context.meLinks.isAnyMatchScreenVisible, "놀던 기기의 가로 판 위에 선물 시트가 뜬다")
        r.games.rummyScreenDidDisappear()
        assertFalse(r.app.me.context.meLinks.isAnyMatchScreenVisible)
    }

    /** 확성기 미룸 값: 손댄 판은 화면 밖에서도 미루고 · 로비 · 방 화면도 미룬다. */
    @Test
    fun matchScreenVisibleMatchesIos() = runTest {
        val r = seated(Seat.guest)
        assertTrue(r.games.isAnyMatchScreenVisible, "방 화면은 다른 대결 화면과 같은 대접이다")
        r.apply()
        r.games.rummyScreenDidDisappear()
        assertTrue(r.games.isAnyMatchScreenVisible, "손댄 판은 다른 탭에서도 언제든 차례가 돌아온다")
    }

    // MARK: - 방 안내 줄

    @Test
    fun hintSpeaksOnlyWhereTabsMatter() {
        assertEquals(RummyPhoneText.tabExitHintGuest, GamesRummyRoomPlan.tabExitHint(RummyCloseDecision.leaveRoom))
        assertEquals(RummyPhoneText.tabExitHintHost, GamesRummyRoomPlan.tabExitHint(RummyCloseDecision.confirmCloseRoom))
        assertNull(GamesRummyRoomPlan.tabExitHint(RummyCloseDecision.close))
        assertNull(GamesRummyRoomPlan.tabExitHint(RummyCloseDecision.confirmForfeit))
        assertNotEquals(RummyPhoneText.tabExitHintGuest, RummyPhoneText.tabExitHintHost)
    }
}
