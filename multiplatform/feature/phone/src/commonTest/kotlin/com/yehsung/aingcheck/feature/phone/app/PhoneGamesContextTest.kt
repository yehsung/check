// 원본: Tests/CheckMobileKitTests/GamesStoreTests.swift(창 문 · 차단 거르기 · AI 선택기 허락 · 탭 배지) ·
//       Sources/CheckMobileKit/App/MobileContext.swift · Games/GamesStore.swift:153-180 @ 3bd04bd
// 6차 int-h 미결 [착수 W2-f] ③: W2-e 문(GamesRouter · GamesBoardGameLink · GamesGomokuLink · GamesLobbyRoster · GamesContext)의 폰 구현을
// 진짜 오목·체스·테트리스·메시지 스토어로 잰다.
package com.yehsung.aingcheck.feature.phone.app

import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesDestination
import com.yehsung.aingcheck.core.stores.messages.blockPeer
import com.yehsung.aingcheck.core.wire.games.ChessLobbyResponse
import com.yehsung.aingcheck.core.wire.games.GomokuInboxResponse
import com.yehsung.aingcheck.core.wire.games.GomokuLobbyResponse
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.feature.phone.routing.PhoneNavRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class PhoneGamesContextTest {
    private fun TestScope.rig(appConfig: AppConfig = AppConfig()): PhoneHarness {
        val h = PhoneHarness(this, appConfig = appConfig) { r ->
            when (r.rpcName) {
                "block_user" -> Reply.Json("""{"status":"ok"}""")
                "gomoku_inbox", "gomoku_lobby", "gomoku_state", "chess_lobby", "chess_state", "tetris_lobby", "tetris_state" -> Reply.Offline
                else -> null
            }
        }
        h.signIn()
        return h
    }

    private fun users(vararg ids: String) = ids.joinToString(",") { """{"user_id":"$it","display_name":"$it","capable":true}""" }

    @Test
    fun matchStartDoorsPresentEachGameThroughTheRouter() = runTest {
        val h = rig()
        val app = h.app
        app.games.appDidBecomeActive()
        advanceUntilIdle()
        app.router.drainRequests()
        // 코어가 '판이 막 시작됐다'고 부르는 문 셋 — 게임 탭 스토어가 W2-e 문으로 달고, 폰 라우터가 셸 요청으로 바꾼다.
        app.gomoku.presentWindow!!.invoke()
        app.chess.presentWindow!!.invoke()
        app.tetris.presentWindow!!.invoke()
        assertEquals(
            listOf(
                PhoneNavRequest.PresentGames(GamesDestination.Gomoku),
                PhoneNavRequest.PresentGames(GamesDestination.Chess),
                PhoneNavRequest.PresentGames(GamesDestination.TetrisDuel),
            ),
            app.router.drainRequests(),
        )
        // 화면이 이미 떠 있으면 다시 쌓지 않는다.
        app.games.gomokuScreenDidAppear()
        app.router.drainRequests()
        app.gomoku.presentWindow!!.invoke()
        assertEquals(emptyList(), app.router.drainRequests())
    }

    @Test
    fun lobbiesHideBlockedPeersFromTheMessagesStore() = runTest {
        val h = rig()
        val app = h.app
        app.gomoku.applyLobby(SwiftJson.decode(GomokuLobbyResponse.serializer(), """{"status":"ok","users":[${users("u-1", "u-2", "u-3")}]}"""))
        app.chess.applyLobby(SwiftJson.decode(ChessLobbyResponse.serializer(), """{"status":"ok","users":[${users("u-1", "u-2")}]}"""))
        val gomokuLink = app.gamesContext.gomoku
        val chessLink = app.gamesContext.chess
        assertEquals(listOf("u-1", "u-2", "u-3"), app.games.gomokuLobbyUsers(gomokuLink).map { it.id })
        app.messages.blockPeer("u-2")
        advanceUntilIdle()
        assertEquals(setOf("u-2"), app.gamesContext.hiddenBlockedPeerIDs, "메시지 탭의 차단 집합을 그대로 본다")
        assertEquals(listOf("u-1", "u-3"), app.games.gomokuLobbyUsers(gomokuLink).map { it.id }, "오목 로비에서 차단한 사람을 거른다")
        assertEquals(listOf("u-1"), app.games.chessLobbyUsers(chessLink).map { it.id }, "체스 로비에서도")
    }

    @Test
    fun aiThinkerOnlyThinksWhileGomokuScreenIsVisibleAndAppActive() = runTest {
        val h = rig()
        val thinker = h.app.gamesContext.gomoku.aiThinker
        assertFalse(thinker.isAllowed)
        h.app.games.appDidBecomeActive()
        h.app.games.gomokuScreenDidAppear()
        runCurrent() // 오목 화면이 보이면 폴링이 돈다 — 가상 시간을 끝까지 밀지 않는다
        assertTrue(thinker.isAllowed, "오목 화면이 보이고 앱이 active 면 생각한다")
        h.app.games.appDidEnterBackground()
        assertFalse(thinker.isAllowed, "뒤로 가면 끊는다")
        h.app.games.appDidBecomeActive()
        h.app.games.gomokuScreenDidDisappear()
        runCurrent() // 오목 화면이 보이면 폴링이 돈다 — 가상 시간을 끝까지 밀지 않는다
        assertFalse(thinker.isAllowed, "화면을 떠나면 끊는다")
    }

    @Test
    fun gomokuInviteCountFeedsTheGamesBadgeOnlyWhenDuelsAreEnabled() = runTest {
        val inbox = """{"status":"ok","incoming":[{"match_id":"m-1","challenger":{"user_id":"u-9","display_name":"솜사탕","capable":true},"stake":3,"invite_expires_ms":1789622100000}]}"""
        val open = rig(AppConfig(duelsEnabled = true))
        open.app.gomoku.applyInbox(SwiftJson.decode(GomokuInboxResponse.serializer(), inbox))
        assertEquals(1, open.app.gamesContext.gomoku.pendingIncomingInviteCount)
        assertEquals(1, open.app.badges.games)
        assertEquals(1, open.app.badges.appBadgeTotal)
        // 깃발이 꺼진 빌드(§8-17 #1)는 받은 신청으로 배지·점이 서지 않는다(코어가 비운다 — 수락할 수 없는 신청).
        val locked = rig()
        locked.app.gomoku.applyInbox(SwiftJson.decode(GomokuInboxResponse.serializer(), inbox))
        assertEquals(0, locked.app.badges.games)
    }
}
