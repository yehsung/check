// 원본: 없음 — 게임 탭 스토어의 아잉 큐브 배선(폰 몫: 네 방향 입구 · 배지 · 화면 수명 · 화면 꺼짐). 맥은 메뉴·창이 따로 잇는다(Tests/checkTests/V0369RummyWiringTests.swift 는 소스 계약).
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.rules.rummy.RummyRackSlot
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyCard
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyLobby
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.markEngaged
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStoreTest
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLobby
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.TetrisStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class GamesRummyWiringTest {
    private companion object {
        const val MATCH = "7e7e0000-0000-4000-8000-000000000068"
        const val NOW_MS = 1_800_000_000_000L
        val WALL = SwiftDate(1_800_000_000.0)
        val lenient = Json { ignoreUnknownKeys = true }
    }

    private class Rig(val h: StoreHarness, val games: GamesStore, val rummy: RummyStore)

    private fun seats(mine: String) =
        """[{"seat_no":0,"user_id":"${StoreFixtures.USER}","display_name":"나","state":"$mine"},{"seat_no":1,"user_id":"${StoreFixtures.PEER}","display_name":"비","state":"playing"}]"""

    private fun state(status: String = "active", mine: String = if (status == "forming") "joined" else "playing"): RummyMatchState = SwiftJson.decode(
        RummyMatchState.serializer(),
        """{"id":"$MATCH","status":"$status","host_id":"${StoreFixtures.USER}","seq":1,"server_now_ms":$NOW_MS,"seats":${seats(mine)},"my_seat_no":0,""" +
            """"my_rack":${if (status == "active") """["A1","B2"]""" else "null"},"table":[],"turn_seat_no":0,"turn_started_ms":$NOW_MS,"turn_deadline_ms":${NOW_MS + 60_000},"grace_ms":2000}""",
    )

    private fun lobby(active: String? = null, invites: Int = 0): RummyLobby = SwiftJson.decode(
        RummyLobby.serializer(),
        """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10,"active_match_id":${active?.let { "\"$it\"" } ?: "null"}},""" +
            """"invites":[${(0 until invites).joinToString(",") { """{"id":"7e7e0000-0000-4000-8000-00000000007$it","host":{"id":"${StoreFixtures.PEER}"},"stake":5,"expires_at_ms":${NOW_MS + 600_000}}""" }}],"public_rooms":[],"users":[]}""",
    )

    private suspend fun TestScope.rig(enabled: Boolean = true): Rig {
        val config = AppConfig(duelsEnabled = enabled)
        val h = StoreHarness(this, config) { r ->
            when (r.rpcName) {
                "rummy_lobby" -> Reply.Json(lobbyText)
                "rummy_state" -> Reply.Offline
                "rummy_heartbeat" -> Reply.Json("""{"status":"ok"}""")
                "tetris_lobby" -> TetrisDuelStoreTest.lobby(incoming = false)
                else -> null
            }
        }
        h.signIn()
        val rummy = RummyStore(h.storeScope, TestRummyHost(h.sessionStore, config) { WALL }).also {
            it.clock = { WALL }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.deadlineWakeEnabled = false
            it.heartbeatEnabled = false
        }
        h.rummyStore = rummy
        return Rig(h, GamesStore(h.context), rummy)
    }

    private val lobbyText = """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":10},"invites":[],"public_rooms":[],"users":[]}"""

    private data class Blocks(val chess: GamesBusyGame?, val gomoku: GamesBusyGame?, val tetris: GamesBusyGame?, val rummy: GamesBusyGame?)

    private fun GamesStore.blocks() = Blocks(chessEntryBlock, gomokuEntryBlock, tetrisEntryBlock, rummyEntryBlock)

    /** ★ 한 사람 한 판은 **네 방향**이다. 큐브 방·판이 있으면 셋이 막히고 자기 입구는 열린 채다. 끝난 판·기권 뒤 구경은 막지 않는다. */
    @Test
    fun oneMatchAtATimeBlocksFourWays() = runTest {
        val r = GamesBusyGame.rummy
        val g = GamesBusyGame.gomoku
        val c = GamesBusyGame.chess
        val t = GamesBusyGame.tetris
        val table: List<Triple<String, suspend (Rig) -> Unit, Blocks>> = listOf(
            Triple("판 없음", { _ -> }, Blocks(null, null, null, null)),
            Triple("큐브 판", { x -> x.rummy.applyState(state()) }, Blocks(r, r, r, null)),
            Triple("큐브 방(서버 chess__busy 와 같다)", { x -> x.rummy.applyState(state("forming")) }, Blocks(r, r, r, null)),
            Triple("큐브 서버 id 만(판을 못 읽었다)", { x -> x.rummy.applyLobby(lobby(active = MATCH)) }, Blocks(r, r, r, null)),
            Triple("큐브 끝난 판", { x -> x.rummy.applyState(state("finished", mine = "done")) }, Blocks(null, null, null, null)),
            Triple("큐브 기권 뒤 구경", { x -> x.rummy.applyState(state(mine = "forfeit")) }, Blocks(null, null, null, null)),
            Triple("오목 사람 판", { x -> x.h.gomoku.holdMatch() }, Blocks(g, null, g, g)),
            Triple("체스 사람 판", { x -> x.h.chess.holdMatch() }, Blocks(null, c, c, c)),
            Triple("테트리스 판", { x ->
                x.h.tetris.applyState(lenient.decodeFromString(TetrisStatePayload.serializer(), TetrisDuelStoreTest.activeState()), 0.0)
            }, Blocks(t, t, null, t)),
            Triple("오목 + 큐브", { x -> x.h.gomoku.holdMatch(); x.rummy.applyState(state()) }, Blocks(g, r, g, g)),
        )
        for ((label, arrange, expected) in table) {
            val x = rig()
            arrange(x)
            assertEquals(expected, x.games.blocks(), label)
        }
    }

    /** 큐브 스토어가 없는 조립(desktopApp · 시험 조립 — `GamesContext.rummy` 기본 null)은 큐브를 모른다 — 입구·배지·화면 꺼짐이 전과 같다. */
    @Test
    fun aContextWithoutRummyBehavesAsBefore() = runTest {
        val h = StoreHarness(this, AppConfig(duelsEnabled = true)) { null }
        h.signIn()
        val games = GamesStore(h.context)
        assertNull(h.context.rummy)
        assertEquals(Blocks(null, null, null, null), games.blocks())
        assertFalse(games.hasLiveRummyMatch)
        assertEquals(0, games.badgeCount)
        games.rummyScreenDidAppear()
        assertFalse(games.isRummyScreenVisible, "스토어가 없으면 화면 수명도 서지 않는다")
    }

    @Test
    fun gamesBadgeAddsRummyInvites() = runTest {
        val open = rig()
        open.h.gomoku.pendingIncomingInviteCount = 1
        open.rummy.applyLobby(lobby(invites = 2))
        assertEquals(3, open.games.badgeCount)

        val locked = rig(enabled = false)
        locked.rummy.applyLobby(lobby(invites = 2))
        assertEquals(0, locked.games.badgeCount, "잠긴 빌드는 수락할 수 없는 초대를 안 센다")
    }

    /** 화면 수명: 나타남 = 로비 읽기 + 창(폴링 주 스위치). 사라짐 = 끝난 판만 접는다(요청 0 · 진행 중 판은 그대로). */
    @Test
    fun screenLifecycleOpensAndFolds() = runTest {
        val x = rig()
        x.games.appDidBecomeActive()
        runCurrent()
        x.games.rummyScreenDidAppear()
        runCurrent()
        assertTrue(x.games.isRummyScreenVisible)
        assertTrue(x.games.isAnyMatchScreenVisible, "확성기 미룸·선물 시트가 이 값을 본다")
        assertTrue(x.rummy.isWindowVisible)
        x.rummy.applyState(state())
        x.games.rummyScreenDidDisappear()
        assertFalse(x.rummy.isWindowVisible)
        assertEquals(MATCH, x.rummy.match?.id?.lowercased, "떠나는 것만으로는 나가지 않는다")

        x.games.rummyScreenDidAppear()
        x.rummy.applyState(state("finished", mine = "done"))
        runCurrent() // 정산을 처음 봤다 — 잔액을 맞추는 로비 한 번은 떠나기 전 몫이다
        val before = x.h.gameRpcs().size
        x.games.rummyScreenDidDisappear()
        runCurrent()
        assertNull(x.rummy.match, "끝난 판은 떠날 때 접는다 — 다시 누르면 결과가 아니라 로비")
        assertEquals(before, x.h.gameRpcs().size, "떠나는 길에 요청이 나갔다")
    }

    /** 앱 수명: 뒤로 = 가림 + 하트비트 멈춤(기권 없음) · 앞으로 = 가림 해제 + 따라잡기 + 하트비트 바로 한 번. 화면이 안 보여도 꼬리가 돈다. */
    @Test
    fun appLifecycleReachesRummyWithoutCuttingTheTail() = runTest {
        val x = rig()
        x.rummy.heartbeatEnabled = true
        x.rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        x.rummy.applyState(state())
        x.games.appDidBecomeActive()
        runCurrent()
        val heartbeats = x.h.server.count("rummy_heartbeat")
        assertEquals(1, heartbeats, "돌아오면 하트비트 한 번")
        assertTrue(x.h.server.count("rummy_lobby") >= 1, "화면이 안 보여도 systemDidWake — 배지·한 사람 한 판이 여기 달렸다")

        x.games.rummyScreenDidAppear()
        runCurrent()
        x.games.appDidEnterBackground()
        assertTrue(x.rummy.isWindowOccluded)
        assertTrue(x.rummy.isWindowVisible, "뒤로 가는 것은 닫기가 아니다")
        assertNull(x.rummy.heartbeatMatchID)
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(0, x.h.server.count("rummy_leave"))
        x.games.appDidBecomeActive()
        assertFalse(x.rummy.isWindowOccluded)
        runCurrent()
        assertEquals(heartbeats + 1, x.h.server.count("rummy_heartbeat"))
    }

    /** 화면 꺼짐: 이 기기가 쥔 판이면 어느 화면에 있든 켠다(자동잠금 = 90초 끊김 기권). 놀던 기기 · 기권 뒤 구경 · 끝난 판은 안 켠다. */
    @Test
    fun heldMatchKeepsTheScreenOn() = runTest {
        val x = rig()
        x.games.appDidBecomeActive()
        assertFalse(x.games.wantsIdleTimerDisabled)
        x.rummy.applyState(state())
        assertFalse(x.games.wantsIdleTimerDisabled, "놀던 기기가 화면을 켜 둔다")
        x.rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        assertTrue(x.games.wantsIdleTimerDisabled)
        x.rummy.applyState(state(mine = "forfeit").copy(seq = 2))
        assertFalse(x.games.wantsIdleTimerDisabled, "구경 중인데 켜 둔다")
    }

    /** 게임 탭 카드 서열: 차단 > 내 판 · 방 > 받은 초대 > 전적 > 기본 한 줄. 없으면: 판돈 걸린 판이 흐르는데 카드가 초대 수를 말하거나, 막힌 카드가 왜 막혔는지 말하지 않는다. */
    @Test
    fun hubCardSpeaksOneThingInOrder() = runTest {
        val idle = rig()
        assertEquals(GamesRummyCard.Line.idle, GamesRummyCard.line(idle.games))
        assertNull(GamesRummyCard.chip(idle.games))
        assertEquals(RummyPhoneText.idleLine, GamesRummyCard.detail(idle.games))

        val invited = rig()
        invited.rummy.applyLobby(lobby(invites = 2))
        assertEquals("받은 초대 2건", GamesRummyCard.chip(invited.games))

        val room = rig()
        room.rummy.applyLobby(lobby(invites = 2))
        room.rummy.applyState(state("forming"))
        assertEquals(GamesRummyCard.Line.inRoom, GamesRummyCard.line(room.games))
        assertEquals(RummyPhoneText.inRoomChip, GamesRummyCard.chip(room.games))

        val playing = rig()
        playing.rummy.applyLobby(lobby(invites = 2))
        playing.rummy.applyState(state())
        assertEquals(GamesRummyCard.Line.activeMatch, GamesRummyCard.line(playing.games))

        val blocked = rig()
        blocked.h.gomoku.holdMatch()
        blocked.rummy.applyLobby(lobby(invites = 2))
        assertEquals(GamesRummyCard.Line.blocked, GamesRummyCard.line(blocked.games))
        assertEquals(GamesBusyText.entryBlock(GamesBusyGame.gomoku), GamesRummyCard.chip(blocked.games))
        assertEquals(GamesBusyText.entryBlockHint(GamesBusyGame.gomoku, GamesBusyGame.rummy), GamesRummyCard.detail(blocked.games))

        val locked = rig(enabled = false)
        locked.rummy.applyLobby(lobby(invites = 2))
        assertEquals(GamesRummyCard.Line.idle, GamesRummyCard.line(locked.games), "잠긴 빌드는 수락할 수 없는 초대로 칩을 세우지 않는다")
    }

    /** 판이 처음 서면 화면을 연다. 없으면: 방장이 시작한 판이 화면 없이 흘러 시간 초과 3회로 기권(꼴찌)된다. 보이는 화면은 또 쌓지 않는다. */
    @Test
    fun matchStartOpensTheScreenOnce() = runTest {
        val x = rig()
        assertEquals(emptyList(), x.h.router.presented)
        x.games.appDidBecomeActive()
        x.rummy.applyState(state())
        assertEquals(listOf<GamesDestination>(GamesDestination.Rummy), x.h.router.presented)
        x.h.router.presented.clear()
        x.games.rummyScreenDidAppear()
        x.h.router.presented.clear()
        x.rummy.presentWindow!!.invoke()
        assertEquals(emptyList(), x.h.router.presented, "보이는 화면은 또 쌓지 않는다")
    }

    @Test
    fun busyTextSpeaksTheFourthGame() {
        assertEquals("아잉 큐브 하는 중이에요", GamesBusyText.entryBlock(GamesBusyGame.rummy))
        assertEquals("아잉 큐브 판이 끝나면 체스를 신청할 수 있어요", GamesBusyText.entryBlockHint(GamesBusyGame.rummy, GamesBusyGame.chess))
        assertEquals("오목 판이 끝나면 아잉 큐브를 할 수 있어요", GamesBusyText.entryBlockHint(GamesBusyGame.gomoku, GamesBusyGame.rummy))
        // 체스 화면의 문구 표는 rawValue 로 짝짓는다 — 짝이 없으면 ui `chessText()` 가 판 중에 죽는다.
        for (game in GamesBusyGame.entries) {
            assertTrue(com.yehsung.aingcheck.core.stores.chess.ChessPhoneText.BusyGame.entries.any { it.rawValue == game.rawValue }, game.rawValue)
        }
    }
}
