// 원본: 없음 — G §2-3 W4-a ②③⑤ · §8-17 #1 · 6차 int-h '[조립 K11]' 의 화면 시험(오목). 스토어 시험(core/stores GomokuFlowContractTest)과 같은 픽스처·같은 끝 상태를 잰다.
//
// ⑤ 픽스처 흐름을 **화면으로** 몬다: 받은 신청 카드의 [수락]을 누르고, 판을 두 번씩 눌러(미리보기 → 착수) 흑의 다섯 수를 둔다. 끝 상태(9수 · 흑 5목 승 · +5 · 루비 105 ·
//    끝남 고리 1회 · 전적 1승)와 스토어가 낸 요청 인자(p_expected_seq · p_x · p_y · p_protocol 2)가 스토어 시험과 같다.
// ② 한 화면 안 탭(순위 펼침 · 규칙 · AI 돌 색 · 관전)을 오가도 창 표시 · 폴링이 산다 — 기준선: 화면을 컴포지션에서 빼면(자식 목적지를 민 것과 같다) 폴링이 죽는다.
// ③ 대국 중 뒤로가기 — 사람과의 판이면 확인이 서고 떠나지 않는다 / 확인하면 떠난다 / 로비·AI 판은 바로 떠난다 / 관전 중이면 관전만 나간다.
// §8-17 #1 — 깃발 꺼짐: [도전] · [수락] 없음 · 접힌 한 줄 · AI · 순위 · 관전은 그대로 / 켜짐: [도전] · [수락] 있음.
// K11 차단 약속 — 로비는 `games.gomokuLobbyUsers` 만 읽는다(메시지 탭이 차단한 사람이 코어 `users` 에 있어도 화면에 없다).
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
import androidx.compose.ui.test.runDesktopComposeUiTest
import androidx.compose.ui.test.DesktopComposeUiTest
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.rules.renju.GomokuOutcome
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.stores.gomoku.GomokuMatchState
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhase
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneBoardGeometry
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRecord
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.core.stores.gomoku.startAIMatch
import com.yehsung.aingcheck.ui.components.CharacterMood
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class GomokuScreenFlowTest {
    private fun JsonObject.s(key: String): String? = this[key]?.jsonPrimitive?.takeIf { it.isString }?.content
    private fun JsonObject.l(key: String): Long? = this[key]?.jsonPrimitive?.longOrNull
    private fun JsonObject.o(key: String): JsonObject? = this[key] as? JsonObject

    /** 서버가 내준 받은함(초대 하나) — 화면이 그 카드에서 [수락]을 누른다. 만료는 서버 지금 + 50초. */
    private fun inboxWithInvite(matchID: String, challengerID: String, name: String): String {
        val now = 1_789_547_568_000L
        return """{"status":"ok","incoming":[{"stake":5,"match_id":"$matchID","challenger":{"user_id":"$challengerID","character":"aing","avatar_url":null,"display_name":"$name"},"invite_expires_ms":${now + 50_000}}],"outgoing":null,"ruby_balance":100,"last_finished":null,"server_now_ms":$now,"active_match_id":null}"""
    }

    private fun DesktopComposeUiTest.tapBoard(point: GomokuPoint) {
        onNodeWithTag(GomokuScreenTags.board).performTouchInput {
            val location = GomokuPhoneBoardGeometry(side = width.toDouble()).location(point)
            click(Offset(location.x.toFloat(), location.y.toFloat()))
        }
        waitForIdle()
    }

    private fun DesktopComposeUiTest.settle(rig: BoardGameRig) {
        waitForIdle()
        rig.settle()
        waitForIdle()
    }

    @Test
    fun blackFlowDrivenThroughTheScreenEndsWhereTheStoreTestEnds() = runDesktopComposeUiTest(420, 2600) {
        val manifest = fixtureJSON(GOMOKU_FIXTURES, "_manifest")
        val flow = manifest["flow_m1"]!!.jsonArray.map { it.jsonObject }.filter { it.s("perspective") == "black" }
        val acceptMatch = fixtureJSON(GOMOKU_FIXTURES, "gomoku_respond__accept_ok").o("match")!!
        val m1 = acceptMatch.s("id")!!
        val blackID = acceptMatch.s("black")!!
        val whiteID = acceptMatch.s("white")!!
        val rig = BoardGameRig(me = blackID) {
            // 화면이 나타나며 내는 두 조회(openWindow): 받은함(초대 한 건)과 로비. 끝난 순간의 로비 재조회는 승리 뒤 전적을 싣는다.
            respondWith("gomoku_inbox") { _, index -> if (index == 0) inboxWithInvite(m1, whiteID, "흰돌") else null }
            respondWith("gomoku_lobby") { _, index ->
                fixtureText(GOMOKU_FIXTURES, if (index == 0) "gomoku_lobby__ok_no_matches" else "gomoku_lobby__ok_after_win_black")
            }
            for (entry in flow) {
                val rpc = when (entry.s("kind")) {
                    "respond" -> "gomoku_respond"
                    "state" -> "gomoku_state"
                    else -> "gomoku_move"
                }
                queueFixtures(rpc, GOMOKU_FIXTURES, entry.s("file")!!)
            }
        }
        var finishedCalls = 0
        rig.gomoku.onMatchFinished = { finishedCalls += 1 }
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe("나검정", "fox", CharacterMood.Working), onLeave = {}) } }
        settle(rig)
        // 받은 신청이 화면에 섰다(서버 받은함 → 카드). [수락]은 화면 단추로 누른다.
        onNodeWithTag(GomokuScreenTags.accept(m1)).performClick()
        settle(rig)
        assertEquals(true, rig.server.last("gomoku_respond").body["p_accept"]?.jsonPrimitive?.content?.toBoolean())
        onNodeWithTag(GomokuScreenTags.match).assertExists()

        var moves = 0
        var states = 0
        for (entry in flow.drop(1)) {
            val file = entry.s("file")!!
            when (entry.s("kind")) {
                "state" -> {
                    // 상대 수는 폴링이 읽는다 — 화면 몫이 아니므로 스토어 문을 그대로 부른다(같은 since 를 내는지 잰다).
                    rig.gomoku.scope.launch { rig.gomoku.refreshMatch() }
                    settle(rig)
                    states += 1
                    assertEquals(entry.l("since"), rig.server.last("gomoku_state").long("p_since_seq"), "$file since")
                }
                else -> {
                    val point = GomokuPoint.at(entry.l("x")!!.toInt(), entry.l("y")!!.toInt())!!
                    // 첫 탭은 미리보기(요청 0), 같은 칸 둘째 탭이 착수.
                    tapBoard(point)
                    assertEquals(moves, rig.server.count("gomoku_move"), "$file — 미리보기 탭이 수를 냈다")
                    tapBoard(point)
                    settle(rig)
                    moves += 1
                    val body = rig.server.last("gomoku_move")
                    assertEquals(entry.l("expected"), body.long("p_expected_seq"), "$file expected")
                    assertEquals(point.x.toLong(), body.long("p_x"))
                    assertEquals(point.y.toLong(), body.long("p_y"))
                }
            }
            assertEquals(moves, rig.server.count("gomoku_move"), "$file move 호출 수")
            assertEquals(states, rig.server.count("gomoku_state"), "$file state 호출 수")
            val facts = fixtureJSON(GOMOKU_FIXTURES, file)
            val serverMatch = facts.o("match")!!
            val match = assertNotNull(rig.gomoku.match, file)
            assertEquals(serverMatch.s("board"), match.board.serverString, "$file 판")
            assertEquals(serverMatch.l("move_count")!!.toInt(), match.moveCount, "$file 수")
            assertNull(rig.gomoku.notice, "$file 안내: ${rig.gomoku.notice}")
        }
        // 끝 상태 = 스토어 시험(GomokuFlowContractTest.flowM1ReplayFromBlackMatchesServer)의 끝 상태.
        val final: GomokuMatchState = assertNotNull(rig.gomoku.match)
        assertTrue(final.isFinished)
        assertEquals(9, final.moveCount)
        assertEquals(GomokuColor.black, final.myColor)
        assertEquals(GomokuOutcome.won, final.outcome)
        assertEquals(GomokuEndReason.five, final.endReason)
        assertEquals(5L, final.rubyDelta)
        assertEquals(105L, rig.gomoku.rubyBalance)
        assertEquals(1, finishedCalls)
        assertEquals(GomokuPhase.result, rig.gomoku.phase)
        assertEquals(2, rig.server.count("gomoku_lobby"), "화면 열기 1 + 끝난 순간 재조회 1")
        assertEquals(GomokuRecord(1, 0, 0), rig.gomoku.record)
        for (call in rig.server.calls) assertEquals(2L, call.long("p_protocol"), "${call.rpc} 본문에 p_protocol 2 가 없다")
        // 화면도 같은 끝을 말한다: 결과 카드 · "이겼어요!" · +5.
        onNodeWithTag(GomokuScreenTags.result).assertExists()
        onNodeWithText("이겼어요!").assertExists()
        onNodeWithContentDescription("루비 +5").assertExists()
        rig.close()
    }

    @Test
    fun pollingStaysAliveAcrossInScreenTabsAndDiesWhenTheScreenLeaves() = runDesktopComposeUiTest(420, 2600) {
        val live = fixtureJSON(GOMOKU_FIXTURES, "gomoku_lobby__ok_matches")["matches"]!!.jsonArray.first().jsonObject.s("match_id")!!
        val watchBody = fixtureText(GOMOKU_FIXTURES, "gomoku_watch__ok_since0").replace("0a7c0000-0000-4000-8000-00000000a7c1", live)
        val rig = BoardGameRig(me = "00000000-0000-4000-8000-0000000000aa") {
            respondWith("gomoku_lobby") { _, _ -> fixtureText(GOMOKU_FIXTURES, "gomoku_lobby__ok_matches") }
            // 보낸 신청이 없는 받은함(보낸 신청이 있으면 AI 입구가 닫힌다 — canStartAIMatch).
            respondWith("gomoku_inbox") { _, _ -> """{"status":"ok","incoming":[],"outgoing":null,"ruby_balance":100,"last_finished":null,"server_now_ms":1789547568000,"active_match_id":null}""" }
            respondWith("gomoku_ranking") { _, _ -> rankingWithSevenRows() }
            respondWith("gomoku_watch_live") { _, _ -> watchBody }
        }
        // 조립 배선과 같게 켠다(MobileAppModel 의 주 스위치 — assembly.md).
        rig.gomoku.spectatorFeaturesEnabled = true
        rig.games.appDidBecomeActive()
        var shown by mutableStateOf(true)
        setContent { BoardTestTheme { if (shown) GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}) } }
        settle(rig)
        fun assertAlive(label: String) {
            assertTrue(rig.games.isGomokuScreenVisible, "$label: 화면 표시가 꺼졌다")
            assertTrue(rig.gomoku.isWindowVisible, "$label: 창 표시가 꺼졌다")
            assertEquals(true, rig.gomoku.pollTask?.isActive, "$label: 폴링이 죽었다")
        }
        assertAlive("로비")
        // 탭 ① 순위표 펼침(제자리 절).
        onNodeWithTag(GomokuScreenTags.rankingToggle).performClick()
        settle(rig)
        assertTrue(onAllNodesWithTag("gomoku-ranking").fetchSemanticsNodes().isNotEmpty())
        assertAlive("순위 펼침")
        // 탭 ② 규칙 시트(덮개).
        onNodeWithTag(GomokuScreenTags.rules).performClick()
        settle(rig)
        onNodeWithTag(GomokuScreenTags.rulesSheet).assertExists()
        assertAlive("규칙 시트")
        rig.gomoku.isRulesVisible = false
        settle(rig)
        // 탭 ③ AI 돌 색 시트.
        onNodeWithTag(GomokuScreenTags.aiEntry).performClick()
        settle(rig)
        onNodeWithTag(GomokuScreenTags.aiSheet).assertExists()
        assertAlive("AI 시트")
        // 시트를 닫는다(왼쪽 위 ✕).
        onNodeWithContentDescription("닫기").performClick()
        settle(rig)
        onNodeWithTag(GomokuScreenTags.aiSheet).assertDoesNotExist()
        // 탭 ④ 관전 — 로비 자리에 선다. 관전 폴링(2초)이 실제로 나간다.
        onNodeWithTag(GomokuScreenTags.watch(live)).performClick()
        settle(rig)
        onNodeWithTag(GomokuScreenTags.watch).assertExists()
        assertAlive("관전")
        val watchCallsBefore = rig.server.count("gomoku_watch_live")
        rig.advance(4.5)
        settle(rig)
        assertTrue(rig.server.count("gomoku_watch_live") > watchCallsBefore, "관전 중 폴링이 관전 조회를 안 냈다")

        // 기준선: 화면을 컴포지션에서 빼면(자식 목적지를 밀었을 때와 같다) 창이 내려가고 폴링이 죽는다 — 위 단언들이 '늘 참'이 아니다.
        shown = false
        settle(rig)
        assertFalse(rig.games.isGomokuScreenVisible)
        assertFalse(rig.gomoku.isWindowVisible, "화면이 빠졌는데 창 표시가 남았다")
        assertNull(rig.gomoku.pollTask, "화면이 빠졌는데 폴링이 남았다")
        assertNull(rig.gomoku.spectating, "폰에서 화면을 떠나면 관전을 내린다(stopWatching — 요청 0건)")
        val callsAfterLeave = rig.server.calls.size
        rig.advance(10.0)
        settle(rig)
        assertEquals(callsAfterLeave, rig.server.calls.size, "화면이 빠졌는데 조회가 나갔다")
        rig.close()
    }

    @Test
    fun backDuringALiveHumanMatchAsksFirstAndOnlyConfirmLeaves() = runDesktopComposeUiTest(420, 2000) {
        val rig = BoardGameRig(me = null)
        var leaves = 0
        val state = GomokuScreenState()
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = { leaves += 1 }, state = state) } }
        settle(rig)
        // 기준선: 로비에서 뒤로 — 바로 떠난다(확인 없음).
        onNodeWithTag(GomokuScreenTags.back).performClick()
        waitForIdle()
        assertEquals(1, leaves, "로비 뒤로가기가 떠나지 않았다")
        onNodeWithTag(GomokuScreenTags.leaveConfirm).assertDoesNotExist()

        // 사람과의 판이 흐른다(서버 판 — AI 아님).
        rig.gomoku.applyState(handGomokuState(myColor = "black", turn = "white", moveCount = 1))
        settle(rig)
        onNodeWithTag(GomokuScreenTags.match).assertExists()
        onNodeWithTag(GomokuScreenTags.back).performClick()
        waitForIdle()
        assertEquals(1, leaves, "대국 중 뒤로가기가 확인 없이 떠났다")
        onNodeWithTag(GomokuScreenTags.leaveConfirm).assertExists()
        onNodeWithText(GomokuScreenText.leaveConfirmMessage).assertExists()
        // 뒤로 한 번 더 = 확인 닫기(계속 두기). 판은 그대로.
        assertTrue(state.handleBack(rig.gomoku))
        waitForIdle()
        onNodeWithTag(GomokuScreenTags.leaveConfirm).assertDoesNotExist()
        assertEquals(1, leaves)
        assertNotNull(rig.gomoku.match)
        // 다시 뒤로 → 확인 → [나가기] 를 눌러야 떠난다. 기권 요청은 나가지 않는다(나가기는 기권이 아니다).
        onNodeWithTag(GomokuScreenTags.back).performClick()
        waitForIdle()
        onNodeWithTag("${GomokuScreenTags.leaveConfirm}-confirm").performClick()
        waitForIdle()
        assertEquals(2, leaves)
        assertEquals(0, rig.server.count("gomoku_resign"))
        rig.close()
    }

    @Test
    fun backDuringAnAIMatchLeavesWithoutAskingAndBackWhileWatchingOnlyLeavesTheWatch() = runDesktopComposeUiTest(420, 2000) {
        val rig = BoardGameRig(me = null)
        var leaves = 0
        val state = GomokuScreenState()
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = { leaves += 1 }, state = state) } }
        settle(rig)
        rig.gomoku.startAIMatch(GomokuColor.black)
        settle(rig)
        assertTrue(rig.gomoku.match != null && !rig.gomoku.match!!.isFinished)
        assertEquals(BoardBackStep.Leave, GomokuBackPlan.step(state, rig.gomoku), "AI 판은 확인하지 않는다(떠나면 AI 시계가 멈춘다)")
        // 관전 중이면 관전만 나간다(로비로) — 순수 계획으로 잰다(관전 상태는 스토어 문으로만 선다).
        assertEquals(BoardBackStep.LeaveWatch, GomokuBackPlan.step(hasOverlay = false, hasLiveHumanMatch = false, isSpectating = true))
        assertEquals(BoardBackStep.ConfirmLeave, GomokuBackPlan.step(hasOverlay = false, hasLiveHumanMatch = true, isSpectating = false))
        assertEquals(BoardBackStep.CloseOverlay, GomokuBackPlan.step(hasOverlay = true, hasLiveHumanMatch = true, isSpectating = false))
        rig.close()
    }

    @Test
    fun duelsFlagOffHidesChallengeAndAcceptButKeepsAIRankingAndWatch() {
        val (offChallenge, offAccept, offFolded) = lobbyEntries(duelsEnabled = false)
        assertEquals(0, offChallenge, "깃발이 꺼졌는데 [도전]이 섰다")
        assertEquals(0, offAccept, "깃발이 꺼졌는데 [수락]이 섰다")
        assertTrue(offFolded, "깃발이 꺼졌는데 받은 신청 접힌 한 줄이 없다")
        val (onChallenge, onAccept, onFolded) = lobbyEntries(duelsEnabled = true)
        assertTrue(onChallenge > 0, "깃발이 켜졌는데 [도전]이 없다 — 위 0 이 빈 단언이 된다")
        assertTrue(onAccept > 0, "깃발이 켜졌는데 [수락]이 없다")
        assertFalse(onFolded)
    }

    /** (도전 단추 수, 수락 단추 수, 접힌 한 줄 유무) — AI 입구·순위·관전 입구가 서는지도 같은 장면에서 잰다. */
    private fun lobbyEntries(duelsEnabled: Boolean): Triple<Int, Int, Boolean> {
        var out: Triple<Int, Int, Boolean>? = null
        runDesktopComposeUiTest(420, 3000) {
            val rig = BoardGameRig(me = null, duelsEnabled = duelsEnabled)
            seedLobby(rig)
            setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}) } }
            waitForIdle()
            onNodeWithTag(GomokuScreenTags.aiEntry).assertExists()
            assertTrue(onAllNodesWithTag("gomoku-ranking").fetchSemanticsNodes().isNotEmpty(), "순위 절이 없다")
            assertTrue(onAllNodesWithTag(GomokuScreenTags.watch(SEED_LIVE_ID)).fetchSemanticsNodes().isNotEmpty(), "관전 입구가 없다")
            val challenge = SEED_USERS.count { onAllNodesWithTag(GomokuScreenTags.challenge(it.id)).fetchSemanticsNodes().isNotEmpty() }
            val accept = onAllNodesWithTag(GomokuScreenTags.accept(SEED_INVITE_ID)).fetchSemanticsNodes().size
            val folded = onAllNodesWithTag(GomokuScreenTags.incomingNotice).fetchSemanticsNodes().isNotEmpty()
            out = Triple(challenge, accept, folded)
            rig.close()
        }
        return requireNotNull(out)
    }

    @Test
    fun lobbyReadsOnlyTheBlockFilteredRosterFromTheGamesStore() = runDesktopComposeUiTest(420, 3000) {
        val rig = BoardGameRig(me = null)
        seedLobby(rig)
        val blocked = SEED_USERS[0]
        rig.hiddenBlocked = setOf(blocked.id)
        setContent { BoardTestTheme { GomokuScreen(rig.games, rig.gomoku, BoardGameMe.unknown, onLeave = {}) } }
        waitForIdle()
        // 코어 목록에는 그대로 있다(차단이 실패하면 그대로 돌아와야 하므로 코어는 거르지 않는다).
        assertTrue(rig.gomoku.users.any { it.id == blocked.id })
        onNodeWithTag(GomokuScreenTags.opponent(blocked.id)).assertDoesNotExist()
        onNodeWithTag(GomokuScreenTags.challenge(blocked.id)).assertDoesNotExist()
        onNodeWithTag(GomokuScreenTags.opponent(SEED_USERS[1].id)).assertExists()
        // 머리 "N명"도 숨긴 사람을 빼고 센다.
        onNodeWithText("${SEED_USERS.size - 1}명", useUnmergedTree = true).assertExists()
        // 기준선: 차단을 풀면 그 사람이 선다(위 단언이 빈 단언이 아니다).
        rig.hiddenBlocked = emptySet()
        waitForIdle()
        onNodeWithTag(GomokuScreenTags.opponent(blocked.id)).assertExists()
        onNodeWithTag(GomokuScreenTags.challenge(blocked.id)).assertExists()
        onNodeWithText("${SEED_USERS.size}명", useUnmergedTree = true).assertExists()
        rig.close()
    }

    /** 순위 응답(픽스처 5행 + 아래로 두 행 — [전체 보기] 줄이 서려면 접힌 줄 수 5 보다 많아야 한다). */
    private fun rankingWithSevenRows(): String {
        val json = fixtureJSON(GOMOKU_FIXTURES, "gomoku_ranking__ok")
        val rows = json["rows"]!!.jsonArray.toMutableList()
        for (i in 6..7) {
            rows += kotlinx.serialization.json.Json.parseToJsonElement(
                """{"rank":$i,"wins":0,"draws":0,"center":null,"losses":${i},"points":-${i},"user_id":"99999999-0000-4000-8000-00000000000$i","character":null,"avatar_url":null,"display_name":"아래$i"}""",
            )
        }
        return JsonObject(json + ("rows" to kotlinx.serialization.json.JsonArray(rows))).toString()
    }

    companion object {
        const val SEED_INVITE_ID = "11111111-0000-4000-8000-0000000000a1"
        const val SEED_LIVE_ID = "22222222-0000-4000-8000-0000000000b2"
        val SEED_USERS = listOf(
            GomokuUser("aaaaaaaa-0000-4000-8000-000000000001", "솜사탕", null, "fox", isWorking = true, isCapable = true, inMatch = false, center = "서울"),
            GomokuUser("aaaaaaaa-0000-4000-8000-000000000002", "구름빵", null, null, isWorking = false, isCapable = true, inMatch = false),
            GomokuUser("aaaaaaaa-0000-4000-8000-000000000003", "달토끼", null, "aing", isWorking = true, isCapable = true, inMatch = true),
        )

        /** 로비 장면(서버 호출 없이 스토어 칸을 직접 채운다 — 세션 없는 호스트라 화면 열기가 조회를 안 낸다). */
        fun seedLobby(rig: BoardGameRig) {
            val g = rig.gomoku
            g.users = SEED_USERS
            g.hasLoadedLobby = true
            g.hasLoadedInbox = true
            g.record = GomokuRecord(6, 2, 1)
            g.spectatorFeaturesEnabled = true
            g.incoming = listOf(
                com.yehsung.aingcheck.core.stores.gomoku.GomokuInvite(SEED_INVITE_ID, SEED_USERS[1], 5, boardClock.addingTimeInterval(42.0)),
            )
            g.liveMatches = listOf(
                com.yehsung.aingcheck.core.stores.gomoku.GomokuLiveMatch(SEED_LIVE_ID, SEED_USERS[2], SEED_USERS[0], com.yehsung.aingcheck.core.stores.gomoku.GomokuStake.ten,
                    boardClock.addingTimeInterval(-95.0), watchers = 3),
            )
            g.ranking = com.yehsung.aingcheck.core.stores.gomoku.GomokuRankingBoard(
                entries = listOf(
                    com.yehsung.aingcheck.core.stores.gomoku.GomokuRankEntry(SEED_USERS[0].id, 1, SEED_USERS[0], 6, 2, 1, 4),
                    com.yehsung.aingcheck.core.stores.gomoku.GomokuRankEntry(SEED_USERS[2].id, 2, SEED_USERS[2], 3, 3, 0, 0),
                ),
                me = null, recordSince = null,
            )
            g.hasLoadedRanking = true
        }
    }
}
