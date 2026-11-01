// 원본: Tests/checkTests/V0369RummyPanelRenderTests.swift 의 뜻(단계 → 화면 · 나가기 확인) — 픽셀 대신 값·상호작용으로 잰다. 그림 자원은 CharacterArtSync 꼴로 원본과 바이트 비교한다.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.runComposeUiTest
import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummySeatFace
import com.yehsung.aingcheck.core.rules.rummy.RummyTileSize
import com.yehsung.aingcheck.core.session.app.AppConfig
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.applyState
import com.yehsung.aingcheck.core.stores.rummy.markEngaged
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.games.minigame.UiGamesHarness
import com.yehsung.aingcheck.ui.games.minigame.MiniGameArt
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubBoardFactsSnapshot
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubScreen
import com.yehsung.aingcheck.ui.games.minigame.hub.GamesHubTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import java.io.File
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val MATCH = "7e7e0000-0000-4000-8000-000000000068"
private const val USER = "7e7e0000-0000-4000-8000-0000000000a1"
private const val PEER = "7e7e0000-0000-4000-8000-0000000000b2"
private val ME = RummySeatFace("나", null, null)

/** 저장소 뿌리(CharacterArtSyncDesktopTest 와 같은 값). */
private val repo: File get() = DesktopSnapshots.repoRoot

@OptIn(ExperimentalTestApi::class)
class GamesRummyScreenTest {
    private class Rig(val h: UiGamesHarness, val rummy: RummyStore, val games: GamesStore)

    /** 호스트 없는 스토어 — 네트워크 0. 내 자리는 `my_seat_no` 로 안다(코어 규약). */
    private fun rig(): Rig {
        val h = UiGamesHarness(TestScope(), AppConfig(duelsEnabled = true)) { null }
        val rummy = RummyStore(h.storeScope).also {
            it.clock = { SwiftDate(1_800_000_000.0) }
            it.pollStepSeconds = Double.POSITIVE_INFINITY
            it.heartbeatEnabled = false
            it.deadlineWakeEnabled = false
        }
        h.rummy = rummy
        return Rig(h, rummy, GamesStore(h.context))
    }

    private fun state(status: String, mine: String): RummyMatchState = SwiftJson.decode(
        RummyMatchState.serializer(),
        """{"id":"$MATCH","status":"$status","host_id":"$USER","seq":1,"seats":[{"seat_no":0,"user_id":"$USER","display_name":"나","state":"$mine"},""" +
            """{"seat_no":1,"user_id":"$PEER","display_name":"비","state":"playing"}],"my_seat_no":0,"my_rack":${if (status == "active") "[\"A1\"]" else "null"},"table":[]}""",
    )

    @Test
    fun phasePicksTheView() = runComposeUiTest {
        val x = rig()
        setContent { AingTheme(dark = false) { GamesRummyScreen(x.games, USER, ME) } }
        onNodeWithTag(GamesRummyTags.LOBBY).assertExists()
        x.rummy.applyState(state("forming", "joined"))
        waitForIdle()
        onNodeWithTag(GamesRummyTags.ROOM).assertExists()
        onNodeWithTag(GamesRummyTags.LOBBY).assertDoesNotExist()
        x.rummy.applyState(state("active", "playing").copy(seq = 2))
        waitForIdle()
        onNodeWithTag(GamesRummyTags.MATCH).assertExists()
        x.rummy.applyState(state("finished", "done").copy(seq = 3))
        waitForIdle()
        onNodeWithTag(GamesRummyTags.RESULT).assertExists()
        x.h.close()
    }

    /** 수명: 화면이 뜨면 폴링 문이 열리고 내려가면 닫힌다. 없으면: 판이 신호를 놓쳤을 때의 그물이 없어 화면이 굳는다. */
    @Test
    fun screenLifetimeDrivesTheStore() = runComposeUiTest {
        val x = rig()
        var shown by mutableStateOf(true)
        setContent { AingTheme(dark = false) { if (shown) GamesRummyScreen(x.games, USER, ME) } }
        waitForIdle()
        assertTrue(x.games.isRummyScreenVisible)
        shown = false
        waitForIdle()
        assertFalse(x.games.isRummyScreenVisible)
        assertFalse(x.rummy.isWindowVisible)
        x.h.close()
    }

    /** 뒤로 표: 쥔 판 = 확인을 묻고, 놀던 기기 = 그냥 나간다(`rummy_leave` 를 보낼 판이 아니다). */
    @Test
    fun backAsksOnlyForAHeldMatch() {
        val x = rig()
        x.rummy.applyState(state("active", "playing"))
        val back = GamesRummyBackState()
        var left = 0
        // ★ 기준선: 손댄 적 없는 판(놀던 기기)은 바로 나간다.
        back.handleBack(x.rummy) { left += 1 }
        assertEquals(1, left)
        assertNull(back.asking)
        // 손댄 판은 묻고, 떠나지 않는다.
        x.rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        back.handleBack(x.rummy) { left += 1 }
        assertEquals(RummyCloseDecision.confirmForfeit, back.asking)
        assertEquals(1, left)
        // 한 번 더 누르면 확인을 닫는다(계속하기) — 시스템 뒤로로 기권이 나가면 안 된다.
        back.handleBack(x.rummy) { left += 1 }
        assertNull(back.asking)
        assertEquals(1, left)
        x.h.close()
    }

    @Test
    fun confirmLeavesAndFinishedMatchDropsTheQuestion() {
        val x = rig()
        x.rummy.applyState(state("active", "playing"))
        x.rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        val back = GamesRummyBackState()
        var left = 0
        back.handleBack(x.rummy) { left += 1 }
        // 묻는 사이 판이 끝났다 — 질문이 남으면 "기권" 버튼이 끝난 판 위에 선다.
        x.rummy.applyState(state("finished", "done").copy(seq = 2))
        back.sync(x.rummy)
        assertNull(back.asking)
        assertEquals(0, left)
        x.h.close()
    }

    /** 나가기 확인 덮개: 표의 글자가 뜨고 [계속하기]가 닫는다. */
    @Test
    fun exitDialogSpeaksTheTable() = runComposeUiTest {
        val x = rig()
        x.rummy.applyState(state("active", "playing"))
        x.rummy.markEngaged(SwiftUUID.parse(MATCH)!!)
        val back = GamesRummyBackState()
        setContent { AingTheme(dark = false) { GamesRummyScreen(x.games, USER, ME, back = back) } }
        back.handleBack(x.rummy) { }
        waitForIdle()
        val copy = assertNotNull(RummyPhoneText.exit(RummyCloseDecision.confirmForfeit))
        onNodeWithText(copy.detail).assertExists()
        onNodeWithTag(GamesRummyTags.EXIT_KEEP).performClick()
        waitForIdle()
        onNodeWithText(copy.detail).assertDoesNotExist()
        assertNull(back.asking)
        x.h.close()
    }

    @Test
    fun rulesSheetFollowsTheStoreFlag() = runComposeUiTest {
        val x = rig()
        setContent { AingTheme(dark = false) { GamesRummyScreen(x.games, USER, ME) } }
        onNodeWithTag(GamesRummyTags.RULES).assertDoesNotExist()
        x.rummy.rulesShown = true
        waitForIdle()
        onNodeWithTag(GamesRummyTags.RULES).assertExists()
        x.h.close()
    }

    /** 허브 카드: 스토어가 있으면 서고 눌러 큐브로 간다, 없으면(Windows 조립) 안 선다. */
    @Test
    fun hubCardStandsOnlyWithAStore() = runComposeUiTest {
        val x = rig()
        val opened = mutableListOf<Any>()
        setContent {
            AingTheme(dark = false) {
                GamesHubScreen(x.games, GamesHubBoardFactsSnapshot(), MiniGameArt.empty, { SwiftDate(1_800_000_000.0) }, { opened += it }, {}, {})
            }
        }
        onNodeWithTag(GamesHubTags.RUMMY).performScrollTo().performClick()
        assertEquals(listOf<Any>(com.yehsung.aingcheck.core.stores.games.GamesDestination.Rummy), opened)
        x.h.close()
    }

    @Test
    fun hubCardIsAbsentWithoutAStore() = runComposeUiTest {
        val h = UiGamesHarness(TestScope(), AppConfig()) { null }
        val games = GamesStore(h.context)
        setContent {
            AingTheme(dark = false) {
                GamesHubScreen(games, GamesHubBoardFactsSnapshot(), MiniGameArt.empty, { SwiftDate(1_800_000_000.0) }, {}, {}, {})
            }
        }
        onNodeWithTag(GamesHubTags.TETRIS_DUEL).assertExists()
        onNodeWithTag(GamesHubTags.RUMMY).assertDoesNotExist()
        h.close()
    }

    /** 타일: 색 이름으로 읽힌다(색약·보이스오버). 조커는 그림이 없어도 글자로 선다(판이 빈 칸을 그리면 안 된다). */
    @Test
    fun tileReadsItsFace() = runComposeUiTest {
        setContent {
            AingTheme(dark = false) {
                androidx.compose.foundation.layout.Row {
                    GamesRummyTile(RummyFace.of("B7")!!, RummyTileSize.phoneRack)
                    GamesRummyTile(RummyFace.joker, RummyTileSize.table)
                    GamesRummyTile(RummyFace.of("D13")!!, RummyTileSize.canvas(0.5), highlighted = true, dimmed = true)
                    GamesRummyTileBack()
                    Text("타일 끝")
                }
            }
        }
        onNodeWithContentDescription("파랑 7").assertExists()
        onNodeWithContentDescription("조커").assertExists()
        onNodeWithContentDescription("주황 13").assertExists()
    }

    /** 번들 그림 두 장이 Compose 리소스로 열리고 맥 원본과 바이트가 같다(git 사본 0 — ui Gradle Sync). */
    @Test
    fun bundledArtIsTheMacOriginal() {
        for (kind in com.yehsung.aingcheck.core.rules.rummy.RummyArtKind.entries) {
            val original = File(repo, "Sources/check/Resources/${kind.bundleName}.png").readBytes()
            assertContentEquals(original, runBlocking { CharacterArt.readBytesOrNull(GamesRummyArt.bundlePath(kind)) }, kind.rawValue)
        }
    }
}
