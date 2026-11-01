// 원본: Tests/checkTests/V0370RummyPanelRenderTests.swift · V0369RummyPanelRenderTests.swift 의 뜻(사람 정렬 · 접기 · 한 목록 · 입구 막기 · 탁자 · 시작 · 나가기) — 픽셀 대신 값·상호작용으로 잰다 @ 1a5eeca6 · ios-1017 설계서 §5
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.centerRight
import androidx.compose.ui.test.click
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onLast
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.rules.rummy.RummyTableSeatingText
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStoreHost
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyLobbyTab
import com.yehsung.aingcheck.core.stores.rummy.RummyLobbyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyNoticeText
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyLobby
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.createRoom
import com.yehsung.aingcheck.core.stores.rummy.markEngaged
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyLobby
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.games.minigame.UiFixtures
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private const val USER = UiFixtures.USER
private const val READY = "7e7e0000-0000-4000-8000-0000000000a1"
private const val BUSY = "7e7e0000-0000-4000-8000-0000000000a2"
private const val FOCUS = "7e7e0000-0000-4000-8000-0000000000a3"
private const val OUTDATED = "7e7e0000-0000-4000-8000-0000000000a4"
private const val HOST = "7e7e0000-0000-4000-8000-0000000000b1"
private const val INVITE_ROOM = "7e7e0000-0000-4000-8000-000000000071"
private const val PUBLIC_ROOM = "7e7e0000-0000-4000-8000-000000000072"
private const val MY_ROOM = "7e7e0000-0000-4000-8000-000000000073"
private const val NOW_MS = 1_800_000_000_000L
private val NOW = SwiftDate(1_800_000_000.0)
private val ME = RummySeatFace("나", null, null)

private fun uuid(text: String): SwiftUUID = SwiftUUID.parse(text)!!

private fun roomJson(id: String, stake: Int = 5): String =
    """{"id":"$id","host":{"id":"$HOST","display_name":"방장"},"stake":$stake,"is_public":true,"expires_at_ms":${NOW_MS + 600_000},"max_seats":4,""" +
        """"seats":[{"user_id":"$HOST","display_name":"방장","state":"joined","seat_no":0}]}"""

private fun lobbyJson(ruby: Long = 120, invites: List<String> = emptyList(), publicRooms: List<String> = emptyList()): String =
    """{"status":"ok","server_now_ms":$NOW_MS,"stakes":[3,5,10],"me":{"ruby_balance":$ruby,"games":4,"wins":1},""" +
        """"invites":[${invites.joinToString(",")}],"public_rooms":[${publicRooms.joinToString(",")}],"users":[""" +
        // 서버 순서에서 일부러 구버전·바쁜 사람을 앞에 둔다 — 화면이 무리를 나누는지 재려고.
        """{"id":"$OUTDATED","display_name":"라온","capable":false},""" +
        """{"id":"$BUSY","display_name":"나래","capable":true,"in_match":true},""" +
        """{"id":"$READY","display_name":"가은","capable":true,"is_working":true},""" +
        """{"id":"$FOCUS","display_name":"다솜","capable":true,"focus_mode":true}]}"""

private fun seat(no: Int?, user: String, name: String, state: String) =
    """{"seat_no":${no ?: "null"},"user_id":"$user","display_name":"$name","state":"$state"}"""

private fun formingJson(mySeat: Int = 0, host: String = USER, seats: List<String> = listOf(seat(0, USER, "나", "joined"), seat(1, READY, "가은", "joined"))): String =
    """{"id":"$MY_ROOM","status":"forming","host_id":"$host","stake":5,"is_public":false,"max_seats":4,"server_now_ms":$NOW_MS,"seq":1,"expires_at_ms":${NOW_MS + 600_000},""" +
        """"seats":[${seats.joinToString(",")}],"my_seat_no":$mySeat,"table":[]}"""

private fun decodeState(text: String): RummyMatchState = SwiftJson.decode(RummyMatchState.serializer(), text)

/** 코어 StoresTestKit `TestRummyHost` 와 같은 꼴(시험 소스셋은 모듈 사이에서 나눌 수 없다). */
internal class UiRummyHost(private val store: SessionStore, override val appConfig: AppConfig, private val clockNow: () -> SwiftDate) : GomokuStoreHost {
    override val session: SupabaseSession? get() = store.session
    override val sessionGeneration: Int get() = store.sessionGeneration
    override val service: SupabaseWorkService get() = store.service
    override val realtimeState: RealtimeState = RealtimeState.Idle(IdleReason.disabled)
    override var rubyBalance: Long? = null
    override fun now(): SwiftDate = clockNow()
    override suspend fun <T> withSessionRetry(operation: suspend (SupabaseSession) -> T): T = store.withSessionRetry(operation)
}

@OptIn(ExperimentalTestApi::class)
class GamesRummyLobbyViewTest {
    private class Rig(val scope: TestScope, val h: UiGamesHarness, val rummy: RummyStore, val games: GamesStore, val replies: MutableMap<String, String>) {
        fun count(rpc: String): Int = h.server.requests.count { it.rpcName == rpc }

        /** rpc 열 — 세션 복원 요청은 뺀다. */
        fun rummyCalls(): List<String> = h.server.requests.mapNotNull { it.rpcName }.filter { it.startsWith("rummy_") }

        fun settle() = scope.testScheduler.advanceUntilIdle()
    }

    /** [signIn] 이 거짓이면 세션이 없어 망이 0건이다(스토어가 요청을 내지 않는다). 그림·값만 잴 때 쓴다. */
    private fun rig(duels: Boolean = true, signIn: Boolean = false, ranking: Boolean = true): Rig {
        val scope = TestScope()
        val replies = mutableMapOf("rummy_lobby" to lobbyJson())
        val config = AppConfig(duelsEnabled = duels)
        val h = UiGamesHarness(scope, config) { r -> r.rpcName?.let { replies[it] }?.let { it to 200 } }
        if (signIn) runBlocking { h.signIn() }
        val rummy = RummyStore(h.storeScope, UiRummyHost(h.sessionStore, config) { NOW }).also {
            it.clock = { NOW }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.heartbeatEnabled = false
            it.deadlineWakeEnabled = false
            it.rankingEnabled = ranking
        }
        h.rummy = rummy
        return Rig(scope, h, rummy, GamesStore(h.context), replies)
    }

    private fun Rig.lobby(text: String) = runBlocking { rummy.applyLobby(SwiftJson.decode(RummyLobby.serializer(), text)) }

    private fun ComposeUiTest.lobbyView(x: Rig) = setContent {
        AingTheme(dark = false) { GamesRummyLobbyView(x.games, x.rummy, USER, ME, onRules = {}, onBack = {}, now = { NOW }) }
    }

    private fun ComposeUiTest.roomView(x: Rig, me: String = USER, onBack: () -> Unit = {}) = setContent {
        AingTheme(dark = false) { GamesRummyRoomView(x.rummy, me, ME, onRules = {}, onBack = onBack, now = { NOW }) }
    }

    private fun ComposeUiTest.top(tag: String) = onNodeWithTag(tag).getBoundsInRoot().top

    // MARK: 사람 탭

    @Test
    fun peopleAreReadyThenBusyThenFoldedOutdated() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.lobby(lobbyJson())
        lobbyView(x)
        waitForIdle()
        val ready = GamesRummyLobbyTags.person(uuid(READY))
        val busy = GamesRummyLobbyTags.person(uuid(BUSY))
        val focus = GamesRummyLobbyTags.person(uuid(FOCUS))
        val outdated = GamesRummyLobbyTags.person(uuid(OUTDATED))
        // 서버는 구버전·바쁜 사람을 앞에 줬다 — 초대할 수 있는 사람이 위로 와야 한다.
        assertTrue(top(ready) < top(busy))
        assertTrue(top(busy) < top(focus), "무리 안 순서는 서버 그대로")
        onNodeWithTag(outdated).assertDoesNotExist()
        onNodeWithText(RummyPhoneText.outdatedFold(1, expanded = false)).assertExists()
        onNodeWithTag(GamesRummyLobbyTags.OUTDATED_FOLD).performClick()
        waitForIdle()
        onNodeWithTag(outdated).assertExists()
        assertTrue(top(focus) < top(outdated))
        onNodeWithText(RummyPhoneText.outdatedFold(1, expanded = true)).assertExists()
        // 눌러서 다시 접는다.
        onNodeWithTag(GamesRummyLobbyTags.OUTDATED_FOLD).performClick()
        waitForIdle()
        onNodeWithTag(outdated).assertDoesNotExist()
        x.h.close()
    }

    @Test
    fun onlyFreePeopleCanBeInvited() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.lobby(lobbyJson())
        lobbyView(x)
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.invite(uuid(READY))).assertIsEnabled()
        onNodeWithTag(GamesRummyLobbyTags.invite(uuid(BUSY))).assertIsNotEnabled()
        onNodeWithTag(GamesRummyLobbyTags.invite(uuid(FOCUS))).assertIsNotEnabled()
        onNodeWithText(RummyPhoneText.peopleCaptionNoRoom).assertExists()
        x.h.close()
    }

    // MARK: 받은 초대 + 공개 방

    @Test
    fun invitesAndPublicRoomsAreOneListInvitesFirst() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.lobby(lobbyJson(invites = listOf(roomJson(INVITE_ROOM)), publicRooms = listOf(roomJson(PUBLIC_ROOM), roomJson(INVITE_ROOM))))
        lobbyView(x)
        waitForIdle()
        onNodeWithText(RummyLobbyPhoneText.joinHeader).assertExists()
        assertTrue(top(GamesRummyLobbyTags.join(uuid(INVITE_ROOM))) < top(GamesRummyLobbyTags.join(uuid(PUBLIC_ROOM))))
        // 공개 방에는 [거절]이 없다. 같은 방이 공개 목록에 있어도 한 번만 선다.
        onNodeWithTag(GamesRummyLobbyTags.decline(uuid(INVITE_ROOM))).assertIsEnabled()
        onNodeWithTag(GamesRummyLobbyTags.decline(uuid(PUBLIC_ROOM))).assertDoesNotExist()
        assertEquals(1, onAllNodesWithText(RummyPhoneText.called("방장"), useUnmergedTree = true).fetchSemanticsNodes().size)
        onNodeWithText(RummyPhoneText.publicTable("방장"), useUnmergedTree = true).assertExists()
        x.h.close()
    }

    /** 수명이 지난 초대에 [참가]를 세우지 않는다 — 폴링이 30초라 로비에 남아 있을 수 있다. */
    @Test
    fun expiredRoomsDoNotStand() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.lobby(lobbyJson(invites = listOf(roomJson(INVITE_ROOM))))
        setContent {
            AingTheme(dark = false) {
                GamesRummyLobbyView(x.games, x.rummy, USER, ME, onRules = {}, onBack = {}, now = { SwiftDate(1_800_000_000.0 + 601) })
            }
        }
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.join(uuid(INVITE_ROOM))).assertDoesNotExist()
        onNodeWithText(RummyPhoneText.joinEmpty).assertExists()
        x.h.close()
    }

    // MARK: 잔액 · 다른 게임 · 잠금

    @Test
    fun shortOfRubyTurnsOffTheEntriesAndSaysWhy() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        // 잔액 4: 판돈 3 은 낼 수 있고 5·10 은 못 낸다. 초대 판돈은 5.
        x.lobby(lobbyJson(ruby = 4, invites = listOf(roomJson(INVITE_ROOM))))
        lobbyView(x)
        waitForIdle()
        // ★ 기준선: 낼 수 있는 판돈이면 다 살아 있다.
        onNodeWithTag(GamesRummyLobbyTags.OPEN_TABLE).assertIsEnabled()
        onNodeWithTag(GamesRummyLobbyTags.invite(uuid(READY))).assertIsEnabled()
        onNodeWithTag(GamesRummyLobbyTags.stake(3)).assertIsEnabled()
        // 초대는 판돈이 5 라 못 앉는다. [거절]은 된다.
        onNodeWithTag(GamesRummyLobbyTags.join(uuid(INVITE_ROOM))).assertIsNotEnabled()
        onNodeWithTag(GamesRummyLobbyTags.decline(uuid(INVITE_ROOM))).assertIsEnabled()
        assertEquals(1, onAllNodesWithText(RummyPhoneText.insufficient).fetchSemanticsNodes().size, "초대 카드 한 곳만")
        // 모자란 판돈도 **고를 수는 있다** — 카드가 까닭과 푸는 길을 말하고 탁자만 안 열린다. 막으면 잔액이 줄어 이미 모자란 값에서 빠져나올 말이 없다.
        onNodeWithTag(GamesRummyLobbyTags.stake(5)).assertIsEnabled().performClick()
        waitForIdle()
        onNodeWithText(RummyLobbyPhoneText.stakeShort(5, 4)).assertExists()
        onNodeWithTag(GamesRummyLobbyTags.OPEN_TABLE).assertIsNotEnabled()
        onNodeWithTag(GamesRummyLobbyTags.stake(3)).performClick()
        waitForIdle()
        onNodeWithText(RummyLobbyPhoneText.stakeShort(5, 4)).assertDoesNotExist()
        onNodeWithTag(GamesRummyLobbyTags.OPEN_TABLE).assertIsEnabled()
        // 잔액이 줄어 고른 판돈을 못 내게 되면 입구가 닫히고 까닭이 선다. [초대]는 산다 — 판돈은 시트에서 고른다.
        x.lobby(lobbyJson(ruby = 1, invites = listOf(roomJson(INVITE_ROOM))))
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.OPEN_TABLE).assertIsNotEnabled()
        onNodeWithTag(GamesRummyLobbyTags.invite(uuid(READY))).assertIsEnabled()
        onNodeWithText(RummyLobbyPhoneText.stakeShort(3, 1)).assertExists()
        x.h.close()
    }

    @Test
    fun anotherGameBlocksEntriesWithTheReason() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.h.chess.activeMatchID = "chess-1"
        x.lobby(lobbyJson(invites = listOf(roomJson(INVITE_ROOM))))
        lobbyView(x)
        waitForIdle()
        onNodeWithText(GamesBusyText.entryBlockNotice(GamesBusyGame.chess, GamesBusyGame.rummy)!!).assertExists()
        onNodeWithTag(GamesRummyLobbyTags.OPEN_TABLE).assertIsNotEnabled()
        onNodeWithTag(GamesRummyLobbyTags.invite(uuid(READY))).assertIsNotEnabled()
        onNodeWithTag(GamesRummyLobbyTags.join(uuid(INVITE_ROOM))).assertIsNotEnabled()
        onNodeWithTag(GamesRummyLobbyTags.decline(uuid(INVITE_ROOM))).assertIsEnabled()
        x.h.close()
    }

    /** 깃발이 꺼진 빌드: 입구를 그리지 않고 한 줄로 말한다. 거절 · 순위 · 전적은 그대로다. */
    @Test
    fun lockedBuildDrawsNoEntry() = runDesktopComposeUiTest(390, 2000) {
        val x = rig(duels = false)
        x.lobby(lobbyJson(invites = listOf(roomJson(INVITE_ROOM)), publicRooms = listOf(roomJson(PUBLIC_ROOM))))
        lobbyView(x)
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.OPEN_TABLE).assertDoesNotExist()
        onNodeWithTag(GamesRummyLobbyTags.stake(3)).assertDoesNotExist()
        onNodeWithTag(GamesRummyLobbyTags.invite(uuid(READY))).assertDoesNotExist()
        onNodeWithTag(GamesRummyLobbyTags.join(uuid(INVITE_ROOM))).assertDoesNotExist()
        onNodeWithTag(GamesRummyLobbyTags.join(uuid(PUBLIC_ROOM))).assertDoesNotExist()
        onNodeWithTag(GamesRummyLobbyTags.decline(uuid(INVITE_ROOM))).assertIsEnabled()
        assertEquals(1, onAllNodesWithText(RummyNoticeText.updateRequired).fetchSemanticsNodes().size)
        onNodeWithTag(GamesRummyLobbyTags.tab(GamesRummyLobbyTab.ranking)).assertExists()
        x.h.close()
    }

    /** availability 안내는 껍데기가 로비 대신 세운다 — 로비의 [탁자 열기]가 남으면 전부 거절될 단추다. */
    @Test
    fun unavailableReplacesTheLobby() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        // 서버 거절이 스토어를 '업데이트 필요'로 돌린다(availability 를 쓰는 문은 코어 안에만 있다).
        x.lobby("""{"status":"unsupported_client"}""")
        setContent { AingTheme(dark = false) { GamesRummyScreen(x.games, USER, ME) } }
        waitForIdle()
        onNodeWithTag(GamesRummyTags.UNAVAILABLE).assertExists()
        onNodeWithTag(GamesRummyLobbyTags.OPEN_TABLE).assertDoesNotExist()
        onNodeWithText(RummyPhoneText.updateRequired).assertExists()
        x.h.close()
    }

    // MARK: 새 탁자

    @Test
    fun stakeAndPublicSwitchWriteTheStore() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.lobby(lobbyJson())
        lobbyView(x)
        waitForIdle()
        assertEquals(3L, x.rummy.selectedStake)
        onNodeWithText(RummyPhoneText.stakeCaption(3)).assertExists()
        onNodeWithTag(GamesRummyLobbyTags.stake(5)).performClick()
        waitForIdle()
        assertEquals(5L, x.rummy.selectedStake)
        onNodeWithText(RummyPhoneText.stakeCaption(5)).assertExists()
        assertFalse(x.rummy.createPublic)
        onNodeWithText(RummyPhoneText.publicOff, useUnmergedTree = true).assertExists()
        onNodeWithTag(GamesRummyLobbyTags.PUBLIC).performClick()
        waitForIdle()
        assertTrue(x.rummy.createPublic)
        onNodeWithText(RummyPhoneText.publicOn, useUnmergedTree = true).assertExists()
        x.h.close()
    }

    /** ★ 운영 시험 결함: '공개 방' 글자를 눌러도 안 켜졌다. 줄 어디를 눌러도 한 번만 뒤집히고(글자 · 설명 · 스위치 자리) 읽는 쪽엔 스위치 하나로 읽힌다. */
    @Test
    fun thePublicRowTogglesFromAnywhereAndReadsAsOneSwitch() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.lobby(lobbyJson())
        lobbyView(x)
        waitForIdle()
        val row = onNodeWithTag(GamesRummyLobbyTags.PUBLIC)
        row.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch)).assertIsOff()
        // 글자가 스위치 한 덩이로 읽힌다(따로 읽는 칸이 없다).
        onNodeWithText(RummyPhoneText.publicLabel, substring = true).assertHasClickAction()

        onNodeWithText(RummyPhoneText.publicLabel, useUnmergedTree = true).performClick()
        waitForIdle()
        assertTrue(x.rummy.createPublic, "'공개 방' 글자를 눌렀는데 안 켜졌다")
        row.assertIsOn()

        onNodeWithText(RummyPhoneText.publicOn, useUnmergedTree = true).performClick()
        waitForIdle()
        assertFalse(x.rummy.createPublic, "설명 줄을 눌렀는데 안 꺼졌다")

        row.performTouchInput { click(centerRight - Offset(20f, 0f)) }
        waitForIdle()
        assertTrue(x.rummy.createPublic, "스위치 자리를 눌렀는데 안 뒤집혔다 — 두 번 뒤집히면 그대로다")
        x.h.close()
    }

    /** 동작이 도는 동안엔 줄 전체가 잠긴다(글자로 돌아가는 길이 없다). */
    @Test
    fun thePublicRowIsLockedWhileWorking() = runDesktopComposeUiTest(390, 2000) {
        val x = rig(signIn = true)
        x.lobby(lobbyJson())
        lobbyView(x)
        waitForIdle()
        x.rummy.createRoom()
        waitForIdle()
        assertTrue(x.rummy.isWorking)
        onNodeWithTag(GamesRummyLobbyTags.PUBLIC).assertIsNotEnabled()
        onNodeWithText(RummyPhoneText.publicLabel, useUnmergedTree = true).performClick()
        waitForIdle()
        assertFalse(x.rummy.createPublic, "도는 중에 글자로 뒤집혔다")
        x.h.close()
    }

    /** 방 없이 [초대]: 판돈 시트를 먼저 연다 — 시트에서 고른 판돈·공개 여부로 탁자를 **먼저** 열고, 그 응답 뒤에 그 사람을 부른다. 거꾸로면 서버가 방 없는 초대를 거절한다. */
    @Test
    fun inviteWithoutARoomOpensTheSheetThenTheTableThenCalls() = runDesktopComposeUiTest(390, 2000) {
        val x = rig(signIn = true)
        x.replies["rummy_create"] = """{"status":"ok","match_id":"$MY_ROOM","state":${formingJson(seats = listOf(seat(0, USER, "나", "joined")))},"server_now_ms":$NOW_MS}"""
        x.replies["rummy_invite"] = """{"status":"ok","state":${formingJson(seats = listOf(seat(0, USER, "나", "joined"), seat(null, READY, "가은", "invited")))},"server_now_ms":$NOW_MS}"""
        x.lobby(lobbyJson())
        lobbyView(x)
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.invite(uuid(READY))).performClick()
        waitForIdle()
        // 시트만 떴다 — 아직 아무것도 안 나갔다.
        onNodeWithTag(GamesRummyLobbyTags.INVITE_SHEET).assertExists()
        x.settle()
        assertEquals(emptyList(), x.rummyCalls().filter { it != "rummy_lobby" }, "시트를 열기만 했는데 탁자가 열렸다")
        onNodeWithText(RummyLobbyPhoneText.inviteSheetPrompt("가은"), useUnmergedTree = true).assertExists()
        // 뒤의 새 탁자 카드와 시트가 같은 값을 고친다 — 시트 것(나중에 놓인 쪽)을 누른다.
        onAllNodesWithTag(GamesRummyLobbyTags.stake(5)).onLast().performClick()
        onAllNodesWithTag(GamesRummyLobbyTags.PUBLIC).onLast().performClick()
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.OPEN_AND_CALL).assertExists().performClick()
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.INVITE_SHEET).assertDoesNotExist()
        // 응답이 오기 전: 누른 것이 받아졌다는 표시.
        onNodeWithText(RummyPhoneText.calling).assertExists()
        x.settle()
        waitForIdle()
        assertEquals(listOf("rummy_create", "rummy_invite"), x.rummyCalls())
        val create = x.h.server.bodies("rummy_create").single()
        assertTrue("\"p_stake\":5" in create, create)
        assertTrue("\"p_public\":true" in create, create)
        assertTrue(READY in x.h.server.bodies("rummy_invite").single())
        assertTrue(x.rummy.callingPeerIDs.isEmpty(), "줄이 비어야 한다")
        x.h.close()
    }

    /** ★ 탭이 위다 — 절 아래에 두면 받은 초대 · 새 탁자에 밀려 [순위]가 첫 화면에서 안 보인다. [순위] 탭에는 순위만 선다. */
    @Test
    fun tabsStandAboveTheEntriesAndRankingHidesThem() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.lobby(lobbyJson(invites = listOf(roomJson(INVITE_ROOM))))
        lobbyView(x)
        waitForIdle()
        val tabs = GamesRummyLobbyTags.tab(GamesRummyLobbyTab.ranking)
        assertTrue(top(tabs) < top(GamesRummyLobbyTags.join(uuid(INVITE_ROOM))))
        assertTrue(top(tabs) < top(GamesRummyLobbyTags.OPEN_TABLE))
        onNodeWithText(RummyLobbyPhoneText.peopleTabWithInvites(1), useUnmergedTree = true).assertExists()
        onNodeWithTag(tabs).performClick()
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.join(uuid(INVITE_ROOM))).assertDoesNotExist()
        onNodeWithTag(GamesRummyLobbyTags.OPEN_TABLE).assertDoesNotExist()
        x.h.close()
    }

    @Test
    fun openTableSendsTheChosenStake() = runDesktopComposeUiTest(390, 2000) {
        val x = rig(signIn = true)
        x.replies["rummy_create"] = """{"status":"ok","match_id":"$MY_ROOM","state":${formingJson(seats = listOf(seat(0, USER, "나", "joined")))},"server_now_ms":$NOW_MS}"""
        x.lobby(lobbyJson())
        lobbyView(x)
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.stake(10)).performClick()
        onNodeWithTag(GamesRummyLobbyTags.OPEN_TABLE).performClick()
        x.settle()
        waitForIdle()
        assertEquals(listOf("rummy_create"), x.rummyCalls())
        assertTrue("\"p_stake\":10" in x.h.server.bodies("rummy_create").single())
        x.h.close()
    }

    // MARK: 방

    @Test
    fun hostRoomShowsFourChairsPotSplitAndCountdown() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.rummy.applyState(decodeState(formingJson(seats = listOf(seat(0, USER, "나", "joined"), seat(1, READY, "가은", "joined"), seat(null, BUSY, "나래", "invited")))))
        roomView(x)
        waitForIdle()
        for (index in 0..3) onNodeWithTag(GamesRummyRoomTags.chair(index)).assertExists()
        // 나는 아래. 위 의자가 아래 의자보다 위에 있다.
        assertTrue(top(GamesRummyRoomTags.chair(2)) < top(GamesRummyRoomTags.chair(0)))
        onNodeWithText("나 · 방장", useUnmergedTree = true).assertExists()
        assertEquals(RummyPhoneText.invited, RummyPhoneText.waitingAnswer, "같은 상태를 의자 카드와 사람 행이 다른 낱말로 부른다")
        assertTrue(onAllNodesWithText(RummyPhoneText.waitingAnswer, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        // 판돈 × 앉은 인원(초대 중은 세지 않는다) · 분배는 순수익.
        onNodeWithText("10", useUnmergedTree = true).assertExists()
        onNodeWithText("판돈 5 × 2명", useUnmergedTree = true).assertExists()
        onNodeWithText("1등 +5", useUnmergedTree = true).assertExists()
        onNodeWithText(RummyPhoneText.closesIn(600), useUnmergedTree = true).assertExists()
        // 빈 의자는 방장에게 초대 자리다.
        onNodeWithText(RummyPhoneText.invite, useUnmergedTree = true).assertExists()
        onNodeWithTag(GamesRummyRoomTags.START).assertIsEnabled()
        onNodeWithText(RummyPhoneText.startWith(2)).assertExists()
        x.h.close()
    }

    @Test
    fun startNeedsTwoSeated() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.rummy.applyState(decodeState(formingJson(seats = listOf(seat(0, USER, "나", "joined"), seat(null, READY, "가은", "invited")))))
        roomView(x)
        waitForIdle()
        onNodeWithTag(GamesRummyRoomTags.START).assertIsNotEnabled()
        onNodeWithText(RummyPhoneText.start).assertExists()
        onNodeWithText(RummyPhoneText.startHintHost).assertExists()
        x.h.close()
    }

    @Test
    fun startSendsOneRequest() = runDesktopComposeUiTest(390, 2000) {
        val x = rig(signIn = true)
        x.replies["rummy_start"] = """{"status":"ok","server_now_ms":$NOW_MS}"""
        x.replies["rummy_state"] = """{"status":"ok","state":${formingJson()},"server_now_ms":$NOW_MS}"""
        x.lobby(lobbyJson())
        x.rummy.applyState(decodeState(formingJson()))
        roomView(x)
        waitForIdle()
        onNodeWithTag(GamesRummyRoomTags.START).performClick()
        x.settle()
        waitForIdle()
        assertEquals(1, x.count("rummy_start"))
        x.h.close()
    }

    /** 손님: [시작]이 없고 기다린다는 말이 선다. 빈 의자는 '빈자리'이고 초대 절이 없다. */
    @Test
    fun guestRoomHasNoStartAndNoInvites() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.lobby(lobbyJson())
        x.rummy.applyState(decodeState(formingJson(mySeat = 1, host = HOST, seats = listOf(seat(0, HOST, "방장", "joined"), seat(1, USER, "나", "joined")))))
        roomView(x)
        waitForIdle()
        onNodeWithTag(GamesRummyRoomTags.START).assertDoesNotExist()
        onNodeWithTag(GamesRummyRoomTags.LEAVE).assertIsEnabled()
        onNodeWithText(RummyPhoneText.startHintGuest).assertExists()
        assertEquals(2, onAllNodesWithText(RummyPhoneText.emptySeat, useUnmergedTree = true).fetchSemanticsNodes().size)
        onNodeWithTag(GamesRummyLobbyTags.invite(uuid(BUSY))).assertDoesNotExist()
        x.h.close()
    }

    /** 방장 방: 초대 절이 방 아래에 서고, 앉은 사람은 '참가함', 부른 사람은 '초대함'이다. */
    @Test
    fun hostRoomListsPeopleWithSeatTags() = runDesktopComposeUiTest(390, 3000) {
        val x = rig()
        x.lobby(lobbyJson())
        x.rummy.applyState(decodeState(formingJson(seats = listOf(seat(0, USER, "나", "joined"), seat(1, READY, "가은", "joined"), seat(null, FOCUS, "다솜", "invited")))))
        roomView(x)
        waitForIdle()
        onNodeWithText(RummyPhoneText.peopleCaptionHost).assertExists()
        // 의자 카드와 사람 행이 같은 낱말을 쓴다 — 앉은 사람 · 부른 사람이 양쪽에 다 있다.
        assertEquals(2, onAllNodesWithText(RummyPhoneText.joined, useUnmergedTree = true).fetchSemanticsNodes().size)
        assertEquals(2, onAllNodesWithText(RummyPhoneText.invited, useUnmergedTree = true).fetchSemanticsNodes().size)
        onNodeWithTag(GamesRummyLobbyTags.invite(uuid(READY))).assertDoesNotExist()
        onNodeWithTag(GamesRummyLobbyTags.invite(uuid(BUSY))).assertIsNotEnabled()
        x.h.close()
    }

    /** [나가기]: 방장은 "방이 닫혀요" 확인을 지나고(요청 전에 떠나지 않는다), 손님은 묻지 않고 나간다. */
    @Test
    fun hostLeaveAsksAndGuestLeaveDoesNot() = runDesktopComposeUiTest(390, 2000) {
        val host = rig()
        host.rummy.applyState(decodeState(formingJson()))
        host.rummy.markEngaged(uuid(MY_ROOM))
        var hostLeft = 0
        setContent { AingTheme(dark = false) { GamesRummyScreen(host.games, USER, ME, onLeave = { hostLeft += 1 }) } }
        waitForIdle()
        onNodeWithTag(GamesRummyRoomTags.LEAVE).performClick()
        waitForIdle()
        val copy = RummyPhoneText.exit(RummyCloseDecision.confirmCloseRoom)!!
        onNodeWithText(copy.detail).assertExists()
        assertEquals(0, hostLeft)
        onNodeWithTag(GamesRummyTags.EXIT_KEEP).performClick()
        waitForIdle()
        onNodeWithText(copy.detail).assertDoesNotExist()
        assertEquals(0, hostLeft)
        host.h.close()
    }

    @Test
    fun guestLeaveGoesStraightOut() = runDesktopComposeUiTest(390, 2000) {
        val x = rig()
        x.rummy.applyState(decodeState(formingJson(mySeat = 1, host = HOST, seats = listOf(seat(0, HOST, "방장", "joined"), seat(1, USER, "나", "joined")))))
        x.rummy.markEngaged(uuid(MY_ROOM))
        var left = 0
        setContent { AingTheme(dark = false) { GamesRummyScreen(x.games, USER, ME, onLeave = { left += 1 }) } }
        waitForIdle()
        onNodeWithTag(GamesRummyRoomTags.LEAVE).performClick()
        waitForIdle()
        assertEquals(1, left)
        x.h.close()
    }

    // MARK: 순위

    private val rankingJson =
        """{"status":"ok","server_now_ms":$NOW_MS,"rows":[{"id":"$HOST","display_name":"방장","games":9,"wins":5,"rank":1},""" +
            """{"id":"$USER","display_name":"나","games":4,"wins":1,"rank":2}],"me":{"games":4,"wins":1,"rank":2}}"""

    /** 탭을 처음 볼 때 한 번만 읽고, 내 줄과 내 행을 그린다. 탭을 오가도 다시 읽지 않는다(주기 갱신은 폴링 몫). */
    @Test
    fun rankingTabLoadsOnceAndShowsMyLine() = runDesktopComposeUiTest(390, 2000) {
        val x = rig(signIn = true)
        x.replies["rummy_ranking"] = rankingJson
        x.lobby(lobbyJson())
        lobbyView(x)
        waitForIdle()
        assertEquals(0, x.count("rummy_ranking"), "전제: 탭을 고르기 전")
        onNodeWithTag(GamesRummyLobbyTags.tab(GamesRummyLobbyTab.ranking)).performClick()
        waitForIdle()
        x.settle()
        waitForIdle()
        assertEquals(1, x.count("rummy_ranking"))
        onNodeWithText(RummyPhoneText.rankHeader).assertExists()
        onNodeWithText("내 순위 2위 · 판 수 4 · 1등 1").assertExists()
        onNodeWithContentDescription(RummyLobbyPhoneText.rankRowAccessibility(1, "방장", 9, 5, isMe = false)).assertExists()
        onNodeWithContentDescription(RummyLobbyPhoneText.rankRowAccessibility(2, "나", 4, 1, isMe = true)).assertExists()
        // 사람 탭이 사라졌다.
        onNodeWithTag(GamesRummyLobbyTags.person(uuid(READY))).assertDoesNotExist()
        onNodeWithTag(GamesRummyLobbyTags.tab(GamesRummyLobbyTab.people)).performClick()
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.tab(GamesRummyLobbyTab.ranking)).performClick()
        waitForIdle()
        x.settle()
        waitForIdle()
        assertEquals(1, x.count("rummy_ranking"))
        x.h.close()
    }

    /** ★ 기준선: 순위 스위치가 꺼진 조립은 요청 0건이고, 영영 도는 표시 대신 실패를 말한다. 없으면: 배선이 빠진 빌드의 순위 탭이 말없이 돈다. */
    @Test
    fun rankingSwitchOffSendsNothingAndSaysSo() = runDesktopComposeUiTest(390, 2000) {
        val x = rig(signIn = true, ranking = false)
        x.replies["rummy_ranking"] = rankingJson
        x.lobby(lobbyJson())
        lobbyView(x)
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.tab(GamesRummyLobbyTab.ranking)).performClick()
        waitForIdle()
        x.settle()
        waitForIdle()
        mainClock.advanceTimeBy(2000)
        waitForIdle()
        assertEquals(0, x.count("rummy_ranking"))
        onNodeWithText(RummyLobbyPhoneText.rankingFailed, useUnmergedTree = true).assertExists()
        x.h.close()
    }

    @Test
    fun emptyRankingSaysNoGamesYet() = runDesktopComposeUiTest(390, 2000) {
        val x = rig(signIn = true)
        x.replies["rummy_ranking"] = """{"status":"ok","server_now_ms":$NOW_MS,"rows":[],"me":{"games":0,"wins":0}}"""
        x.lobby(lobbyJson())
        lobbyView(x)
        waitForIdle()
        onNodeWithTag(GamesRummyLobbyTags.tab(GamesRummyLobbyTab.ranking)).performClick()
        waitForIdle()
        x.settle()
        waitForIdle()
        onNodeWithText(RummyPhoneText.emptyRanking).assertExists()
        x.h.close()
    }
}
