// 원본: 없음(시험) — int-w2 배선 social-games-shell 이 채운 고리: 대결 신청 글(onInviteNotice) · 실시간 게임 몫(DesktopRealtimeGamesOf) ·
// 게임 창의 착용 캐릭터 표(WithCharacters) · 소셜 훅(DesktopSocialHooks — 맥 WorkTimerStorePoke.swift:270-277·415-432 ·
// WorkTimerStoreAchievements.swift:85-93) · 울트라 안내 지우기(W3-c3 nice). 가짜만(MockEngine 녹음 · 합성 픽스처). 창 0.
package com.yehsung.aingcheck.desktop.windows.games.minigame

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.runDesktopComposeUiTest
import com.yehsung.aingcheck.core.stores.gomoku.GomokuInvite
import com.yehsung.aingcheck.core.stores.me.RubyBalanceCell
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterDirectory
import com.yehsung.aingcheck.desktop.windows.games.minigame.rig.BoardGameRig
import com.yehsung.aingcheck.desktop.windows.kit.DuelInviteNotice
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.wiring.DesktopRealtimeGamesOf
import com.yehsung.aingcheck.desktop.wiring.DesktopSocialHooks
import com.yehsung.aingcheck.feature.desktop.work.lap.LapWalletJudge
import com.yehsung.aingcheck.desktop.wiring.SocialDeps
import com.yehsung.aingcheck.desktop.wiring.SocialWiring
import com.yehsung.aingcheck.desktop.wiring.WiringTestRig
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.poke.PokeSendHooks
import com.yehsung.aingcheck.feature.desktop.realtime.DesktopRealtimeGame
import com.yehsung.aingcheck.feature.desktop.realtime.DesktopRealtimeGames
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraSyncReason
import com.yehsung.aingcheck.feature.desktop.work.DesktopWorkSnapshot
import com.yehsung.aingcheck.feature.desktop.work.InMemoryDesktopWorkState
import com.yehsung.aingcheck.feature.desktop.socialapi.PokeConsumeFacts
import com.yehsung.aingcheck.feature.desktop.work.PokeFactsSource
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.games.gomoku.boardClock
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.ui.screens.session.kit.LocalAppUserCharacters
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class IntW2GamesSocialHooksTest {
    private class Rig(config: DesktopAppConfig, onNotice: (DuelInviteNotice) -> Unit) {
        val board = BoardGameRig(me = null, duelsEnabled = config.toAppConfig().duelsEnabled)
        val games = UiGamesHarness(TestScope(), config.toAppConfig()) { null }
        val host = GameWindowScenes.host(GamesWindowsHost.OWN_KINDS.associateWith { FakeGameWindowShell() })
        init { GameWindowWiring.wire(board.gomoku, board.chess, games.tetris, host, config, onInviteNotice = onNotice) }
    }

    /** 받은 신청 → 이름·판돈을 실은 글 하나(맥 :1268). duels 꺼짐이면 0, 서버 요청 0. */
    @Test
    fun inviteNoticeCarriesPeerAndStakeOnlyWhenDuelsOn() {
        val invite = GomokuInvite("11111111-0000-4000-8000-0000000000a1", GameWindowScenes.SEED_USERS[0], 5, boardClock)
        val off = mutableListOf<DuelInviteNotice>()
        val offRig = Rig(DesktopAppConfig(duels = false)) { off += it }
        requireNotNull(offRig.board.gomoku.onInviteArrived).invoke(invite)
        assertEquals(emptyList(), off, "duels 꺼진 빌드가 신청 글을 냈다")
        offRig.board.settle()
        assertEquals(0, offRig.board.server.calls.size, "신청 글이 서버를 불렀다")

        val on = mutableListOf<DuelInviteNotice>()
        val onRig = Rig(DesktopAppConfig(duels = true)) { on += it }
        requireNotNull(onRig.board.gomoku.onInviteArrived).invoke(invite)
        // 글 + 신청 id(int-w4a — 셸 알림이 ShellNotice.ref 로 실어 오버레이 구조 신청과 id 로 짝짓는다)
        assertEquals(listOf(DuelInviteNotice(GameWindowKind.Gomoku, invite.peer.displayName, 5, invite.id)), on, "켠 빌드인데 글이 없다 — 꺼짐 단언이 헛돈다")
        assertTrue(on.single().body.startsWith("${invite.peer.displayName}님이 오목 대결을 신청했어요"))
        offRig.board.close()
        onRig.board.close()
    }

    /** 실시간 게임 몫: duels 꺼짐 = NONE(게임 조회 0) · 켬 = 오목 → 체스 → 테트리스 순서로 같은 신호. */
    @Test
    fun realtimeGamesAreNoneWhileDuelsOffAndOrderedWhenOn() {
        val calls = mutableListOf<String>()
        fun game(name: String) = object : DesktopRealtimeGame {
            override fun handleSignal() { calls += "$name.signal" }
            override fun realtimeDidJoin() { calls += "$name.join" }
            override fun systemDidWake() { calls += "$name.wake" }
        }
        assertSame(DesktopRealtimeGames.NONE, DesktopRealtimeGamesOf.of(DesktopAppConfig(duels = false), game("g"), game("c"), game("t")))
        val on = DesktopRealtimeGamesOf.of(DesktopAppConfig(duels = true), game("g"), game("c"), game("t"))
        listOf(on.gomoku, on.chess, on.tetris).forEach { assertNotNull(it).handleSignal() }
        assertEquals(listOf("g.signal", "c.signal", "t.signal"), calls)
    }

    /** 게임 창 내용이 착용 캐릭터 표를 받는다(기본 빈 표가 아니라 조립이 준 그 표). */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun gameWindowContentSeesAssembledCharacterDirectory() = runDesktopComposeUiTest {
        val directory = AppUserCharacterDirectory(CharacterArt.portraitIds)
        var seen: AppUserCharacterDirectory? = null
        setContent { WithCharacters({ directory }) { seen = LocalAppUserCharacters.current } }
        waitForIdle()
        assertSame(directory, seen, "게임 창이 조립한 캐릭터 표를 못 받았다")
    }

    /** 지갑 박자 → 도전 미션: 미션 화면 panelOpen · periodic · signIn 만. 주간은 모든 박자(그쪽 60초 창이 거른다). */
    @Test
    fun walletCadenceFollowsMacAchievementsReason() {
        var weekly = 0
        var achievements = 0
        var missionVisible = false
        val cadence = DesktopSocialHooks.walletCadence({ weekly++ }, { achievements++ }, { missionVisible })
        cadence.onWalletCadence(UltraSyncReason.MissionCandidate)
        cadence.onWalletCadence(UltraSyncReason.PanelOpen)
        assertEquals(2 to 0, weekly to achievements, "미션 화면이 아닌 panelOpen · missionCandidate 가 미션을 물었다")
        missionVisible = true
        cadence.onWalletCadence(UltraSyncReason.PanelOpen)
        cadence.onWalletCadence(UltraSyncReason.Periodic)
        cadence.onWalletCadence(UltraSyncReason.SignIn)
        assertEquals(5 to 3, weekly to achievements)
    }

    /** 폴링 박자: 주가 바뀐 박자에만 주간 한 번(아니면 0) · 케이크 10분 문은 매 박자(스토어가 스로틀). */
    @Test
    fun beatOthersAskWeeklyOnlyWhenWeekRolled() = runTest {
        var rolled = false
        var weekly = 0
        var cake = 0
        val hooks = DesktopSocialHooks.beatOthers({ rolled }, { weekly++ }, { cake++ })
        val now = SwiftDate(1_789_623_900.0)
        hooks.forEach { it(now) }
        assertEquals(0 to 1, weekly to cake, "주가 안 바뀌었는데 주간을 물었다")
        rolled = true
        hooks.forEach { it(now) }
        assertEquals(1 to 2, weekly to cake)
    }

    /** 발신 훅 위임 · 상점 다시 읽기는 구매 반영 **뒤** 차례(즉시 0 → 다음 차례 1). */
    @Test
    fun sendHooksDelegateAndShopReloadRunsAfterApply() = runTest {
        val seen = mutableListOf<String>()
        val hooks: PokeSendHooks = DesktopSocialHooks.sendHooks({ seen += "dir" }) { seen += "conv:$it" }
        hooks.reloadDirectory()
        hooks.refreshConversationAfterPokeSent("peer-1")
        assertEquals(listOf("dir", "conv:peer-1"), seen)

        var reloads = 0
        val mutation = DesktopSocialHooks.shopMutation(backgroundScope) { reloads++ }
        mutation()
        assertEquals(0, reloads, "구매 반영 전에 상점을 다시 읽었다")
        testScheduler.runCurrent()
        assertEquals(1, reloads)
    }

    private fun TestScope.social(config: DesktopAppConfig, rig: WiringTestRig): SocialWiring {
        val start = SwiftDate.fromEpochMillis(WiringTestRig.BASE_MS)
        val facts = PokeFactsSource {
            PokeConsumeFacts(
                localSessionOpen = true, adoptedRemoteSession = false, canonicalSessionID = "s-1", ownOpenSessionID = "s-1",
                ownDeviceClaims = null, deviceID = WiringTestRig.DEVICE, lastMeaningfulInputAt = start,
            )
        }
        return SocialWiring(
            SocialDeps(
                sessionStore = rig.sessionStore, httpClient = rig.httpClient, desktopConfig = config, kv = rig.kv, clock = rig.clock,
                workState = InMemoryDesktopWorkState(DesktopWorkSnapshot(isWorking = true, startedAt = start, sessionId = "s-1")),
                pokeFacts = facts, lapJudgment = LapWalletJudge, ruby = RubyBalanceCell(), runningTests = rig.runningTests,
                environment = emptyMap(),
            ),
        )
    }

    /** W3-c3 nice: 울트라 화면을 떠나거나 로그아웃하면 구매 안내를 지우고 화면 훅(고른 개수 풀기)을 부른다. ultra 꺼짐 = 구매기 없음 · 구매 요청 0. */
    @Test
    fun ultraNoticeClearsOnLeaveAndSignOut() = runTest {
        val rig = WiringTestRig(this) { path ->
            when {
                path.endsWith("/rpc/take_pokes") -> "[]"
                path.endsWith("/rpc/buy_ultra") -> """{"status":"ok","ruby_balance":40,"ultra_balance":2}"""
                else -> null
            }
        }
        try {
            val s = social(DesktopAppConfig(poke = true, ultra = true), rig)
            var resets = 0
            s.addSignedOutListener { resets++ }
            s.start(rig.scope)
            rig.signIn()
            testScheduler.runCurrent()
            val purchase = assertNotNull(s.purchase)
            purchase.buy(1)
            testScheduler.runCurrent()
            assertEquals("울트라 1개를 샀어요!", purchase.notice.value)
            s.onUltraPageLeft()
            assertNull(purchase.notice.value, "울트라 화면을 떠났는데 안내가 남았다")

            purchase.buy(1)
            testScheduler.runCurrent()
            assertNotNull(purchase.notice.value)
            rig.sessionStore.signOut()
            testScheduler.runCurrent()
            assertNull(purchase.notice.value, "로그아웃했는데 안내가 남았다")
            assertEquals(1, resets, "로그아웃 훅(고른 것 풀기)이 안 불렸다")
            s.shutdown()
        } finally {
            rig.close()
        }

        val offRig = WiringTestRig(this)
        try {
            val off = social(DesktopAppConfig(poke = true, ultra = false), offRig)
            off.start(offRig.scope)
            offRig.signIn()
            testScheduler.runCurrent()
            assertNull(off.purchase, "ultra 꺼진 빌드가 구매기를 지었다")
            off.onUltraPageLeft()
            offRig.sessionStore.signOut()
            testScheduler.runCurrent()
            assertEquals(0, offRig.countContaining("buy_ultra") + offRig.countContaining("shop_state"), "ultra 꺼짐인데 구매·상점 요청")
            off.shutdown()
        } finally {
            offRig.close()
        }
    }
}
