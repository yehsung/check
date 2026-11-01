// 원본: Tests/CheckMobileKitTests/V1017RummyResultTests.swift:96-175 @ ios-1017-cube 614d98bd · Tests/checkTests/V0369RummyPanelRenderTests.swift 의 뜻 — 픽셀 대신 수명 · 시계 · 보내는 요청으로 잰다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.runDesktopComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.realtime.IdleReason
import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStoreHost
import com.yehsung.aingcheck.core.stores.rummy.RummyReactionEvent
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.sendReaction
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
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

private const val MATCH = "7e7e0000-0000-4000-8000-000000000069"
private const val USER = UiFixtures.USER
private const val PEER = "7e7e0000-0000-4000-8000-0000000000b2"
private const val NOW_SECONDS = 1_800_000_000.0
private const val NOW_MS = 1_800_000_000_000L

@OptIn(ExperimentalTestApi::class)
class GamesRummyReactionsTest {
    private class Rig(val scope: TestScope, val h: UiGamesHarness, val rummy: RummyStore) {
        var time: SwiftDate = SwiftDate(NOW_SECONDS)

        fun count(rpc: String): Int = h.server.requests.count { it.rpcName == rpc }
    }

    private fun state(): RummyMatchState = SwiftJson.decode(
        RummyMatchState.serializer(),
        """{"id":"$MATCH","status":"active","host_id":"$USER","stake":3,"seat_count":2,"seq":1,"pool_count":50,""" +
            """"seats":[{"seat_no":0,"user_id":"$USER","display_name":"나","state":"playing","rack_count":2,"initial_done":true},""" +
            """{"seat_no":1,"user_id":"$PEER","display_name":"비","state":"playing","rack_count":9,"initial_done":true}],""" +
            """"my_seat_no":0,"my_rack":["A4","C1"],"my_initial_done":true,"table":[],"turn_seat_no":0}""",
    )

    private fun rig(): Rig {
        val scope = TestScope()
        val config = AppConfig(duelsEnabled = true)
        val replies = mapOf("rummy_react" to """{"status":"ok","server_now_ms":$NOW_MS}""")
        val h = UiGamesHarness(scope, config) { r -> r.rpcName?.let { replies[it] }?.let { it to 200 } }
        runBlocking { h.signIn() }
        lateinit var rig: Rig
        val rummy = RummyStore(h.storeScope, UiRummyHost(h.sessionStore, config) { rig.time }).also {
            it.clock = { rig.time }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.heartbeatEnabled = false
            it.deadlineWakeEnabled = false
        }
        rig = Rig(scope, h, rummy)
        rummy.applyState(state())
        return rig
    }

    private fun event(seat: Long, sticker: AingSticker = AingSticker.joy) = RummyReactionEvent(1, seat, sticker, false, SwiftDate(NOW_SECONDS))

    // MARK: 수명

    /** ★ 맥 0.3.69 CPU 120%: 말풍선이 2.5초 뒤 사라지고, 그 뒤에는 **시계를 한 번도 더 부르지 않는다**. 없으면: 빈 층이 프레임을 돌린다. */
    @Test
    fun aBubbleLivesItsLifetimeThenTheClockStops() = runDesktopComposeUiTest(393, 759) {
        val anchors = GamesRummyReactionAnchors()
        anchors.rects[1L] = Rect(0f, 300f, 100f, 400f)
        var clockCalls = 0
        val start = mainClock.currentTime
        val now: () -> SwiftDate = {
            clockCalls += 1
            SwiftDate(NOW_SECONDS + (mainClock.currentTime - start) / 1000.0)
        }
        val feed = listOf(event(1))
        setContent {
            AingTheme(dark = false) { GamesRummyReactionOverlay(feed, { "비" }, anchors, false, now, Modifier.fillMaxSize()) }
        }
        waitForIdle()
        mainClock.autoAdvance = false
        onNodeWithTag(GamesRummyReactionTags.bubble(1)).assertExists()
        mainClock.advanceTimeBy(2_200)
        onNodeWithTag(GamesRummyReactionTags.bubble(1)).assertExists()
        mainClock.advanceTimeBy(500)
        onNodeWithTag(GamesRummyReactionTags.bubble(1)).assertDoesNotExist()
        val settled = clockCalls
        mainClock.advanceTimeBy(5_000)
        assertEquals(settled, clockCalls, "말풍선이 끝났는데 시계가 돈다")
    }

    /** 기준선: 말풍선이 없으면 시계는 처음 한두 번뿐이다. */
    @Test
    fun anEmptyFeedNeverRunsTheClock() = runDesktopComposeUiTest(393, 759) {
        var clockCalls = 0
        val now: () -> SwiftDate = {
            clockCalls += 1
            SwiftDate(NOW_SECONDS)
        }
        setContent {
            AingTheme(dark = false) { GamesRummyReactionOverlay(emptyList(), { "?" }, GamesRummyReactionAnchors(), false, now, Modifier.fillMaxSize()) }
        }
        waitForIdle()
        val settled = clockCalls
        assertTrue(settled <= 2, "빈 층이 시계를 $settled 번 불렀다")
        mainClock.advanceTimeBy(3_000)
        assertEquals(settled, clockCalls)
    }

    // MARK: 자리

    @Test
    fun aSeatWithoutAnAnchorDrawsNoBubble() = runDesktopComposeUiTest(393, 759) {
        setContent {
            AingTheme(dark = false) {
                GamesRummyReactionOverlay(listOf(event(2)), { "비" }, GamesRummyReactionAnchors(), true, { SwiftDate(NOW_SECONDS) }, Modifier.fillMaxSize())
            }
        }
        waitForIdle()
        onNodeWithTag(GamesRummyReactionTags.bubble(2)).assertDoesNotExist()
    }

    @Test
    fun aBubbleStandsBelowAnAnchorAtTheTopOfTheScreen() = runDesktopComposeUiTest(393, 759) {
        val anchors = GamesRummyReactionAnchors()
        val d = density.density
        anchors.rects[1L] = Rect(0f, 44f * d, 100f * d, 100f * d)
        setContent {
            AingTheme(dark = false) {
                GamesRummyReactionOverlay(listOf(event(1)), { "비" }, anchors, true, { SwiftDate(NOW_SECONDS) }, Modifier.fillMaxSize())
            }
        }
        waitForIdle()
        val bounds = onNodeWithTag(GamesRummyReactionTags.bubble(1)).getBoundsInRoot()
        assertTrue(bounds.top >= 100.dp, "말풍선이 자리를 가린다: ${bounds.top}")
    }

    /** 뷰가 사라진 자리는 지운다 — 결과의 [최종 판]을 보는 동안 온 말풍선이 안 보이는 줄 자리에 뜨면 안 된다. */
    @Test
    fun aVanishedSeatForgetsItsAnchor() = runDesktopComposeUiTest(393, 759) {
        val anchors = GamesRummyReactionAnchors()
        var shown by mutableStateOf(true)
        setContent {
            AingTheme(dark = false) {
                if (shown) Box(Modifier.size(50.dp).rummyReactionAnchor(anchors, 3L))
            }
        }
        waitForIdle()
        assertTrue(anchors.rects.containsKey(3L), "자리가 안 적혔다")
        shown = false
        waitForIdle()
        assertFalse(anchors.rects.containsKey(3L), "사라진 자리가 남았다")
    }

    // MARK: 보내기

    @Test
    fun pickingSendsOnceThenCoolsDownForTwoSeconds() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        var picked = 0
        setContent {
            AingTheme(dark = false) { GamesRummyReactionPicker(x.rummy, { x.time }, onPicked = { picked += 1 }) }
        }
        waitForIdle()
        onNodeWithTag(GamesRummyReactionTags.cell(AingSticker.heart.rawValue)).assertIsEnabled().performClick()
        waitForIdle()
        x.scope.testScheduler.advanceUntilIdle()
        assertEquals(1, picked, "고른 뒤 시트가 안 닫힌다")
        assertEquals(1, x.count("rummy_react"))
        val mine = x.rummy.reactionFeed.single()
        assertEquals(AingSticker.heart, mine.sticker)
        assertTrue(mine.isMine)
        mainClock.advanceTimeBy(300)
        onNodeWithTag(GamesRummyReactionTags.cell(AingSticker.joy.rawValue)).assertIsNotEnabled()
        x.time = x.time.addingTimeInterval(2.1)
        mainClock.advanceTimeBy(300)
        onNodeWithTag(GamesRummyReactionTags.cell(AingSticker.joy.rawValue)).assertIsEnabled()
        x.h.close()
    }

    /** 스토어 → 층: 내가 보낸 반응이 내 자리에 바로 선다(메아리를 안 기다린다). */
    @Test
    fun theLayerDrawsWhatTheStoreEmits() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        val anchors = GamesRummyReactionAnchors()
        anchors.rects[0L] = Rect(0f, 300f, 100f, 400f)
        setContent {
            AingTheme(dark = false) {
                CompositionLocalProvider(LocalGamesRummyReactionAnchors provides anchors) {
                    GamesRummyReactionLayer(x.rummy, true, { x.time }, Modifier.fillMaxSize())
                }
            }
        }
        waitForIdle()
        onNodeWithTag(GamesRummyReactionTags.bubble(0)).assertDoesNotExist()
        assertTrue(x.rummy.sendReaction(AingSticker.sad))
        waitForIdle()
        onNodeWithTag(GamesRummyReactionTags.bubble(0)).assertExists()
        x.scope.testScheduler.advanceUntilIdle()
        x.h.close()
    }

    @Test
    fun theButtonOpensTheSheetOnlyWithAMatch() = runDesktopComposeUiTest(393, 759) {
        val x = rig()
        setContent {
            AingTheme(dark = false) { GamesRummyReactionButton(x.rummy, { x.time }) }
        }
        waitForIdle()
        onNodeWithTag(GamesRummyReactionTags.BUTTON).assertIsEnabled().performClick()
        waitForIdle()
        onNodeWithTag(GamesRummyReactionTags.PICKER).assertExists()
        x.h.close()
    }
}
