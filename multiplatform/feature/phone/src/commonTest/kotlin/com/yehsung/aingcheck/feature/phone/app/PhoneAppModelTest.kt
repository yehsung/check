// 원본: Tests/CheckMobileKitTests/BaseAppModelTests.swift · GamesGomokuSpectateWiringTests.swift · GamesChessWiringTests.swift ·
//       GamesTetrisDuelWiringTests.swift · MeDailyMissionStoreTests.swift(판 끝 배선) · BaseRouterTests.swift:99-107(배지 합성) ·
//       MeCakeGiftTests.swift(탭 이동의 케이크 시트) @ 3bd04bd
// 6차 int-h 미결 [착수 W2-f] ①: links 의 테트리스 자리 · badges = messages+games+missions · appBadgeTotal = messages+games.
package com.yehsung.aingcheck.feature.phone.app

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesRouteRequest
import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.me.MeRoute
import com.yehsung.aingcheck.core.stores.me.dismissCakeGiftSheet
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStake
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ChessLobbyResponse
import com.yehsung.aingcheck.core.wire.games.GomokuLobbyResponse
import com.yehsung.aingcheck.core.wire.games.TetrisLobbyResponse
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.feature.phone.MemoryWidgetFile
import com.yehsung.aingcheck.feature.phone.PhoneHarness
import com.yehsung.aingcheck.feature.phone.Reply
import com.yehsung.aingcheck.feature.phone.routing.PhoneBadges
import com.yehsung.aingcheck.feature.phone.routing.PhoneNavRequest
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget
import com.yehsung.aingcheck.feature.phone.routing.PhoneTab
import com.yehsung.aingcheck.feature.phone.widget.WidgetSnapshot
import com.yehsung.aingcheck.feature.phone.widget.WidgetSnapshotCodec
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.golden.Golden
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class PhoneAppModelTest {
    @Test
    fun assemblyTurnsOnSpectatorSwitchesAndWiresEveryLink() = runTest {
        val h = PhoneHarness(this)
        val app = h.app
        // 주 스위치 넷 — 기본이 꺼짐이라 빠지면 순위·관전 요청이 한 번도 안 나간다(화면이 죽는데 빨간 시험이 없다 — Swift 머리말).
        assertTrue(app.gomoku.spectatorFeaturesEnabled)
        assertTrue(app.chess.spectatorFeaturesEnabled)
        assertTrue(app.tetris.rankingEnabled)
        assertTrue(app.tetris.spectatorFeaturesEnabled)
        assertNotNull(app.realtime.gomoku)
        assertNotNull(app.realtime.tetris, "테트리스 초인종 자리 — 빠지면 방해 줄이 1초 늦고 조인 따라잡기도 안 돈다")
        assertSame(app.work, app.now.phoneWork)
        assertSame(app.widgetSink, app.now.widgetSink)
        assertSame(app.router, app.messages.router)
        assertSame(app.now, app.messages.nowStore)
        assertSame(app.tetris, app.gamesContext.tetris, "게임 탭의 테트리스 자리는 조립의 그 스토어(int-h ① links.tetris)")
        assertSame(app.context.tetris, app.tetris)
        listOf(app.links.now, app.links.messages, app.links.rankings, app.links.games, app.links.me, app.links.push, app.links.work, app.links.widgetSink)
            .forEach { assertNotNull(it, "스토어 고리가 비었다") }
        // 루비 칸은 하나다(타입도 Long 하나 — G §8-18 #4) — 테트리스 호스트 · 게임 탭 · 확성기 · 나 탭이 같은 칸을 본다.
        app.ruby.rubyBalance = 42
        assertEquals(42L, app.gamesContext.sharedRubyBalance)
        assertEquals(42L, app.context.ruby.rubyBalance)
        app.ruby.rubyBalance = 5_000_000_000
        assertEquals(5_000_000_000L, app.gamesContext.sharedRubyBalance, "Int 범위를 넘어도 자르지 않는다(8차 fold — 칸은 Long 하나)")
    }

    @Test
    fun badgesAddMissionsToTheTabButNeverToTheAppIcon() {
        val badges = PhoneBadges(messages = 3, games = 2, missions = 4)
        assertEquals(5, badges.appBadgeTotal, "앱 아이콘 = 메시지 + 게임(미션은 더하지 않는다 — v0.3.58)")
        assertEquals(3, badges.badge(PhoneTab.messages))
        assertEquals(2, badges.badge(PhoneTab.games))
        assertEquals(4, badges.badge(PhoneTab.me), "나 탭 배지 = 받을 보상 수")
        assertNull(badges.badge(PhoneTab.now))
        assertNull(badges.badge(PhoneTab.rankings))
        val clamped = PhoneBadges(messages = -1, games = 0, missions = -7)
        assertEquals(0, clamped.appBadgeTotal)
        assertNull(clamped.badge(PhoneTab.messages), "0 이면 배지 없음")
        assertNull(clamped.badge(PhoneTab.me))
        assertEquals(PhoneBadges(1, 2, 3), PhoneBadges(1, 2, 3))
        assertTrue(PhoneBadges(1, 2, 3) != PhoneBadges(1, 2, 4))
    }

    @Test
    fun linksComposeBadgesFromTheRealStores() = runTest {
        val h = PhoneHarness(this) { r ->
            when (r.rpcName) {
                "message_unread_summary" -> Reply.Json("""{"status":"ok","total":3,"peers":[{"peer_user_id":"p-1","count":3}]}""")
                "message_history_with_pokes", "message_history_with_reads", "message_history" -> Reply.missingFunction
                else -> null
            }
        }
        h.signIn()
        h.app.messages.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(3, h.app.messages.badgeCount)
        assertEquals(PhoneBadges(3, 0, 0), h.app.badges)
        assertEquals(3, h.app.badges.appBadgeTotal)
    }

    /** 데모 계정의 achievements_status(Swift 픽스처 — 골든 missions/achievements 가 그대로 실어 온다). 오늘: 오목 ✓ · 체스 · 1:1 테트리스 ✗. */
    private fun achievementsFixture(mutate: (JsonObject) -> JsonObject = { it }): String {
        val text = Golden.load("missions/achievements").case("fixture-_me/rpc.achievements_status.json")["json"]!!.jsonPrimitive.content
        return mutate(Json.parseToJsonElement(text).jsonObject).toString()
    }

    private fun withDaily(root: JsonObject, game: String, achieved: Boolean): JsonObject {
        val daily = root["daily"]!!.jsonObject
        val missions = JsonArray(
            daily["missions"]!!.jsonArray.map { m ->
                val row = m.jsonObject
                if (row["game"]!!.jsonPrimitive.content == game) JsonObject(row + ("achieved" to JsonPrimitive(achieved))) else row
            },
        )
        return JsonObject(root + ("daily" to JsonObject(daily + ("missions" to missions))))
    }

    @Test
    fun matchFinishedAsksDailyMissionsWithServerGameNames() = runTest {
        // 1:1 테트리스는 오늘 채웠고 솔로 테트리스는 아직 — 배선이 이름을 `tetris` 로 잘못 넘기면 요청이 나간다(솔로 줄은 미달성).
        val fixture = achievementsFixture { withDaily(withDaily(it, "tetris_duel", true), "tetris", false) }
        val h = PhoneHarness(this) { r -> if (r.rpcName == "achievements_status") Reply.Json(fixture) else null }
        h.signIn()
        h.app.me.appDidBecomeActive()
        advanceUntilIdle()
        val loaded = h.count("achievements_status")
        assertTrue(loaded >= 1, "나 탭이 미션을 읽었다")
        h.app.gomoku.onMatchFinished!!.invoke()
        advanceUntilIdle()
        assertEquals(loaded, h.count("achievements_status"), "오늘 오목 줄을 이미 채웠다 — 이름이 'gomoku' 면 요청 0건")
        h.app.tetris.onMatchFinished!!.invoke()
        advanceUntilIdle()
        assertEquals(loaded, h.count("achievements_status"), "1:1 테트리스는 'tetris_duel'(솔로 'tetris' 가 아니다)")
        h.app.chess.onMatchFinished!!.invoke()
        advanceUntilIdle()
        assertEquals(loaded + 1, h.count("achievements_status"), "체스 줄은 아직 — 한 번 묻는다")
    }

    @Test
    fun signOutResetsRouterRubyWidgetAndStores() = runTest {
        val seeded = WidgetSnapshot(generatedAt = SwiftDate(1_789_621_000.0), characterID = "fox")
        val h = PhoneHarness(this, widgetFile = MemoryWidgetFile(WidgetSnapshotCodec.encode(seeded)))
        h.signIn()
        h.app.ruby.rubyBalance = 30
        h.app.router.open(PhoneRouteTarget.Message("p-1"))
        h.app.router.visibleConversationPeerID = "p-1"
        h.app.session.signOut()
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedOut, h.app.session.phase)
        assertNull(h.app.ruby.rubyBalance, "루비 미러를 비운다(다음 계정에 앞 사람 잔액이 남지 않게)")
        assertEquals(PhoneTab.now, h.app.router.selectedTab)
        assertEquals(emptyList(), h.app.router.pendingRequests)
        assertNull(h.app.router.visibleConversationPeerID)
        assertNull(h.widgetFile.bytes, "위젯 스냅숏을 지운다")
        assertTrue(h.widgetReloads >= 1, "위젯을 바로 새로 그린다(로그인해 주세요)")
    }

    @Test
    fun launchRouteIsHeldUntilSignInAndDroppedWhenLaunchEndsSignedOut() = runTest {
        // 복원이 로그인으로 끝난다 → 붙잡은 링크를 연다.
        val h = PhoneHarness(this)
        h.vault.write(h.jwt(PhoneHarness.ME), com.yehsung.aingcheck.core.session.SessionVaultKeys.accessToken)
        h.vault.write("r0", com.yehsung.aingcheck.core.session.SessionVaultKeys.refreshToken)
        h.prefs.putString(com.yehsung.aingcheck.core.session.SessionPrefsKeys.userID, PhoneHarness.ME)
        assertEquals(SessionPhase.Launching, h.app.session.phase)
        assertTrue(h.app.handleOpenRoute(PhoneRouteTarget.Message("p-9")), "실행 복원 중에는 붙잡는다")
        assertEquals(PhoneRouteTarget.Message("p-9"), h.app.pendingLaunchRoute)
        h.app.start()
        advanceUntilIdle()
        assertNull(h.app.pendingLaunchRoute)
        assertEquals(listOf<PhoneNavRequest>(PhoneNavRequest.Open(PhoneRouteTarget.Message("p-9"))), h.app.router.drainRequests())
        assertEquals(PhoneTab.messages, h.app.router.selectedTab)
        // 복원이 로그아웃으로 끝난다 → 붙잡은 링크를 버리고, 로그인 화면 뒤에 남의 대화를 열지 않는다.
        val out = PhoneHarness(this)
        assertTrue(out.app.handleOpenRoute(PhoneRouteTarget.Message("p-9")))
        out.app.start()
        advanceUntilIdle()
        assertEquals(SessionPhase.SignedOut, out.app.session.phase)
        assertNull(out.app.pendingLaunchRoute, "로그아웃으로 끝난 복원은 링크를 버린다")
        assertEquals(false, out.app.handleOpenRoute(PhoneRouteTarget.Message("p-9")))
        assertEquals(emptyList(), out.app.router.drainRequests())
    }

    @Test
    fun deepLinkTargetsAreResolvedByTheTabStoresRules() = runTest {
        val h = PhoneHarness(this) { r -> if (r.rpcName == "gomoku_state" || r.rpcName == "gomoku_inbox") Reply.Offline else null }
        h.signIn()
        val app = h.app
        // INV-MobileAppModel-14155396(딥링크 몫): `games/tetris` 한 토막은 **솔로** 테트리스 링크다 — 대결로 가로채면 이미 나간 솔로 딥링크가
        //   조용히 사라진다. 대상 해석은 미니게임 요청을 그대로 게임 탭 규칙(routeStep)에 넘긴다.
        app.openRoute(PhoneRouteTarget.Games(GamesRouteRequest.MiniGame(MiniGameKind.tetris)))
        assertEquals(listOf<PhoneNavRequest>(PhoneNavRequest.Open(PhoneRouteTarget.Games(GamesRouteRequest.MiniGame(MiniGameKind.tetris)))), app.router.drainRequests())
        // 이 빌드에 보이지 않는 미니게임(길건너 — §8-18 #7)은 화면을 쌓지 않고 게임 탭 첫 화면에.
        app.openRoute(PhoneRouteTarget.Games(GamesRouteRequest.MiniGame(MiniGameKind.crossy)))
        assertEquals(listOf<PhoneNavRequest>(PhoneNavRequest.Open(PhoneRouteTarget.Games(GamesRouteRequest.Games))), app.router.drainRequests())
        // 제보 링크: 나 탭을 뿌리로 열고 제보 화면을 쌓으며 그 제보에 초점.
        app.openRoute(PhoneRouteTarget.Me(MeRoute.Feedback("r-1")))
        assertEquals(
            listOf(PhoneNavRequest.Open(PhoneRouteTarget.Me(MeRoute.Me)), PhoneNavRequest.PushMe(MeDestination.Feedback)),
            app.router.drainRequests(),
        )
        assertEquals("r-1", app.me.focusedReportID)
        assertEquals(PhoneTab.me, app.router.selectedTab)
        // 순위: 판을 고른다.
        app.openRoute(PhoneRouteTarget.Rankings(RankingsBoard.tokens))
        assertEquals(RankingsBoard.tokens, app.rankings.board)
        assertEquals(PhoneTab.rankings, app.router.selectedTab)
        app.router.drainRequests()
        // 오목 판이 흐르는 동안 온 체스 링크(Android 체스 신청 푸시)는 열지 않는다 — 한 사람 한 판(세 방향).
        app.openRoute(PhoneRouteTarget.ChessInvite("c-1"))
        assertEquals(listOf<PhoneNavRequest>(PhoneNavRequest.Open(PhoneRouteTarget.ChessInvite("c-1"))), app.router.drainRequests())
        app.gomoku.applyLobby(SwiftJson.decode(GomokuLobbyResponse.serializer(), """{"status":"ok","me":{"active_match_id":"G-1"}}"""))
        assertTrue(app.games.hasLiveGomokuMatch)
        app.openRoute(PhoneRouteTarget.ChessInvite("c-1"))
        assertEquals(listOf<PhoneNavRequest>(PhoneNavRequest.Open(PhoneRouteTarget.Games(GamesRouteRequest.Games))), app.router.drainRequests())
    }

    /** 체스·테트리스 판과 로비가 로그아웃 사슬에서 비워진다(W2-f 검증 7차 V4·V4b — 같은 사슬의 오목은 따로 잰다). */
    @Test
    fun signOutChainResetsChessAndTetrisToo() = runTest {
        val h = PhoneHarness(this, appConfig = AppConfig(duelsEnabled = true)) { r ->
            val name = r.rpcName ?: return@PhoneHarness null
            if (name.startsWith("chess_") || name.startsWith("tetris_")) Reply.Offline else null
        }
        h.signIn()
        val app = h.app
        val chessUser = """{"user_id":"u-1","display_name":"솜사탕","capable":true}"""
        val tetrisUser = """{"id":"u-1","display_name":"솜사탕","capable":true,"is_working":true}"""
        app.chess.applyLobby(SwiftJson.decode(ChessLobbyResponse.serializer(), """{"status":"ok","users":[$chessUser],"me":{"active_match_id":"C-1"}}"""))
        app.tetris.applyLobby(SwiftJson.decode(TetrisLobbyResponse.serializer(), """{"status":"ok","users":[$tetrisUser],"me":{"active_match_id":"T-1"}}"""))
        advanceUntilIdle()
        assertEquals("c-1", app.chess.activeMatchID?.lowercase(), "전제: 체스 판 id 를 든다")
        assertEquals("t-1", app.tetris.activeMatchID?.lowercase(), "전제: 테트리스 판 id 를 든다")
        assertTrue(app.chess.users.isNotEmpty(), "전제: 체스 로비에 사람이 있다")
        assertTrue(app.tetris.users.isNotEmpty(), "전제: 테트리스 로비에 사람이 있다")
        app.session.signOut()
        advanceUntilIdle()
        assertNull(app.chess.activeMatchID, "다음 사람의 로비에 앞 사람의 체스 판이 남는다")
        assertEquals(emptyList(), app.chess.users)
        assertNull(app.tetris.activeMatchID, "로그아웃한 사람의 테트리스 판이 남는다(새 계정 토큰으로 보고가 나간다)")
        assertEquals(emptyList(), app.tetris.users)
        assertFalse(app.games.hasLiveChessMatch || app.games.hasLiveTetrisMatch, "다음 계정의 입구가 앞 사람 판에 막힌다")
    }

    /** §8-17 #1: 테트리스 대결의 판돈 깃발이 폰 조립(PhoneTetrisHost)을 거쳐 스토어에 닿는다 — 꺼진 빌드는 신청 RPC 0, 켠 빌드(기준선)는 1. */
    @Test
    fun tetrisDuelFlagReachesTheStoreThroughTheAssembly() = runTest {
        fun TestScope.challengeCount(appConfig: AppConfig): Pair<Boolean, Int> {
            val h = PhoneHarness(this, appConfig = appConfig) { r ->
                when (r.rpcName) {
                    "tetris_challenge" -> Reply.Json("""{"status":"busy"}""")
                    "tetris_lobby", "tetris_state" -> Reply.Offline
                    else -> null
                }
            }
            h.signIn()
            launch { h.app.tetris.challenge("u-9", TetrisDuelStake.three) }
            advanceUntilIdle()
            return h.app.tetris.duelsEnabled to h.count("tetris_challenge")
        }
        assertEquals(false to 0, challengeCount(AppConfig()), "깃발이 꺼진 빌드가 테트리스 판돈 신청을 냈다")
        assertEquals(true to 1, challengeCount(AppConfig(duelsEnabled = true)), "기준선: 켠 빌드는 신청 한 건")
    }

    /**
     * 탭을 옮길 때 생일 선물 시트를 띄운다 — 단, **게임 탭으로 들어갈 때는 띄우지 않는다**(그 탭의 대국 화면이 곧 선다 · 30초 수·15초 침묵이 걸린
     * 판을 시트가 덮으면 진다). 기준선(다른 입력): 나 탭으로 옮기면 띄운다.
     */
    @Test
    fun cakeGiftSheetRisesOnTabChangeExceptIntoTheGamesTab() = runTest {
        val pending = RepoFiles.readText("Sources/CheckMobileKit/Demo/Fixtures/me/rpc.character_gift_pending@demo-gift.json")
        val portraits = listOf(
            "aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco",
            "fox", "ghost", "jellyfish", "robot", "shiba", "squirrel",
        )
        val h = PhoneHarness(this, drawableCharacters = portraits) { r -> if (r.rpcName == "character_gift_pending") Reply.Json(pending) else null }
        h.signIn()
        val app = h.app
        app.me.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(1, h.count("character_gift_pending"), "전제: 앞으로 올 때 선물을 묻는다(케이크를 그리는 빌드)")
        assertNotNull(app.me.cakeGiftSheet, "전제: 열린 선물이 스스로 선다")
        // 화면에 서기 전에 닫혔다(띄운 것으로 세지 않는다) — 다음 기회에 다시 선다.
        app.me.dismissCakeGiftSheet()
        assertNull(app.me.cakeGiftSheet)
        app.tabDidChange(PhoneTab.games)
        advanceUntilIdle()
        assertNull(app.me.cakeGiftSheet, "게임 탭으로 들어갈 때 케이크 시트를 띄웠다")
        app.tabDidChange(PhoneTab.me)
        advanceUntilIdle()
        assertNotNull(app.me.cakeGiftSheet, "다른 탭으로 옮기면 띄운다")
    }

    @Test
    fun tabChangeRefreshesCharactersOnlyWhenSignedIn() = runTest {
        val h = PhoneHarness(this)
        h.app.tabDidChange(PhoneTab.me)
        assertEquals(PhoneTab.me, h.app.router.selectedTab)
        assertEquals(0, h.server.requests.size, "로그인 전에는 아무것도 묻지 않는다")
        h.signIn()
        h.clockShift += 3600.0
        h.app.tabDidChange(PhoneTab.games)
        advanceUntilIdle()
        assertTrue(h.count("app_user_characters") >= 1, "탭을 바꾸면 캐릭터 표를 스로틀로 다시 묻는다")
    }
}
