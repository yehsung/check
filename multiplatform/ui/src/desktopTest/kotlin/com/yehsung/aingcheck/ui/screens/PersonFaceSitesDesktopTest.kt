// 원본: Sources/CheckMobileKit/Me/MeProfileView.swift:23 · Rankings/RankingsBoardSections.swift:352,655 · Components/RankBoardParts.swift:155 · Me/MeBlockedPeopleView.swift:100 · Sources/check/CheckBlockReportViews.swift:592
//
// 사람 얼굴 자리: 서버가 준 사진 주소가 **그 자리까지 닿는지**를 잰다 — 사진 읽개가 받은 주소를 본다(픽셀이 아니라 "이 줄이 사진을 청했는가").
// 기준선: 사진이 없는 응답이면 읽개를 부르지 않는다(읽개가 늘 불린다면 이 시험은 아무것도 재지 않는다).
// 게임 화면 자리는 GameAvatarCallSiteContractTest(소스) · 스토어 값 시험(core PersonFaceValuesTest)이 맡는다.
package com.yehsung.aingcheck.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.loadBlocks
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard
import com.yehsung.aingcheck.core.stores.rankings.RankingsStore
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.screens.me.ProfileScreen
import com.yehsung.aingcheck.ui.screens.rankings.RankingsMyFace
import com.yehsung.aingcheck.ui.screens.rankings.RankingsScreen
import com.yehsung.aingcheck.ui.screens.session.kit.AvatarPhotoLoader
import com.yehsung.aingcheck.ui.screens.session.kit.LocalScreenArt as LocalKitScreenArt
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenArt as KitScreenArt
import com.yehsung.aingcheck.ui.screens.settingscommon.BlockedPeopleScreen
import com.yehsung.aingcheck.ui.screens.settingscommon.DemoFixture
import com.yehsung.aingcheck.ui.screens.settingscommon.DemoFixtures
import com.yehsung.aingcheck.ui.screens.settingscommon.RepoScreenArt
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenHarness
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenScene
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenTestCollation
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class, ExperimentalCoroutinesApi::class)
class PersonFaceSitesDesktopTest {
    private val art = RepoScreenArt(DesktopSnapshots.DENSITY) { DesktopSnapshots.repoImage(it) }
    private val asked = java.util.Collections.synchronizedList(ArrayList<String>())
    private val kitArt = KitScreenArt(AvatarPhotoLoader { url -> asked += url; ImageBitmap(4, 4) })

    @BeforeTest
    fun headless() {
        System.setProperty("java.awt.headless", "true")
    }

    private fun ComposeUiTest.show(content: @Composable () -> Unit) {
        setContent {
            ScreenScene(false, art, Modifier) {
                CompositionLocalProvider(LocalKitScreenArt provides kitArt) { Box(Modifier.size(380.dp, 1400.dp)) { content() } }
            }
        }
    }

    private fun TestScope.profile(avatar: String?): ScreenHarness {
        val json = if (avatar == null) "null" else "\"$avatar\""
        val h = ScreenHarness(this, DemoFixtures(DemoFixtures.me), scenario = "me", override = { r ->
            if (r.path == "/rest/v1/profiles" && r.query.any { it.second == "display_name,avatar_url" }) """[{"display_name":"새벽","avatar_url":$json}]""" else null
        })
        h.signIn()
        return h
    }

    /** 사진을 올린 사람의 큰 아바타는 그 사진을 청한다(옛 판은 이름 첫 글자 원). */
    @Test
    fun profileBigAvatarAsksForTheUploadedPhoto() = runTest {
        val h = profile("https://example.com/me.jpg")
        advanceUntilIdle()
        val store = h.meStore()
        store.loadHeader()
        advanceUntilIdle()
        assertEquals("https://example.com/me.jpg", store.avatarURL?.absoluteString)
        runComposeUiTest {
            show { ProfileScreen(store, h.storeScope, onPickPhoto = {}, openCharacters = {}) }
            testScheduler.advanceUntilIdle()
            waitForIdle()
        }
        assertEquals(listOf("https://example.com/me.jpg"), asked.toList())
    }

    @Test
    fun profileWithoutPhotoAsksNothing() = runTest {
        val h = profile(null)
        advanceUntilIdle()
        val store = h.meStore()
        store.loadHeader()
        advanceUntilIdle()
        runComposeUiTest {
            show { ProfileScreen(store, h.storeScope, onPickPhoto = {}, openCharacters = {}) }
            testScheduler.advanceUntilIdle()
            waitForIdle()
        }
        assertEquals(emptyList(), asked.toList())
    }

    private fun TestScope.rankings(board: RankingsBoard, override: (String) -> String?): RankingsStore {
        val scenario = if (board == RankingsBoard.tokens) "rankings-tokens" else "rankings-minigame"
        val h = ScreenHarness(this, DemoFixtures(DemoFixtures.rankings), scenario, override = { r -> r.rpcName?.let(override) })
        h.signIn()
        advanceUntilIdle()
        val store = RankingsStore(h.context, h.storeScope, ScreenTestCollation)
        store.tabDidAppear()
        advanceUntilIdle()
        store.select(board)
        advanceUntilIdle()
        return store
    }

    /** [순위] 탭 토큰 줄: 나 말고 다른 사람은 사진을 청한다(옛 판은 전원 이니셜). */
    @Test
    fun rankingsTokenRowsAskForOtherPeoplesPhotos() = runTest {
        val json = DemoFixture("rankings/rpc.token_usage_board.json").read()
        val photo = "https://example.com/token.jpg"
        val store = rankings(RankingsBoard.tokens) { rpc -> if (rpc == "token_usage_board") withPhotos(json, photo) else null }
        renderRankings(store)
        assertTrue(photo in asked, "토큰 줄이 사진을 청하지 않았다: $asked")
    }

    /** [순위] 탭 미니게임 줄도 같다. */
    @Test
    fun rankingsMiniGameRowsAskForOtherPeoplesPhotos() = runTest {
        val json = DemoFixture("rankings/_rankings-minigame/rpc.minigame_board.json").read()
        val photo = "https://example.com/minigame.jpg"
        val store = rankings(RankingsBoard.minigame) { rpc -> if (rpc == "minigame_board") withPhotos(json, photo) else null }
        renderRankings(store)
        assertTrue(photo in asked, "미니게임 줄이 사진을 청하지 않았다: $asked")
    }

    @Test
    fun rankingsWithoutPhotosAskNothing() = runTest {
        val store = rankings(RankingsBoard.tokens) { null }
        renderRankings(store)
        assertEquals(emptyList(), asked.toList())
    }

    private fun TestScope.renderRankings(store: RankingsStore) {
        runComposeUiTest {
            show { RankingsScreen(store, me = RankingsMyFace(null, CharacterMood.Plain), scope = rememberCoroutineScope(), onSelectBoard = {}, scrollable = false) }
            testScheduler.advanceUntilIdle()
            waitForIdle()
        }
    }

    /** 응답의 null 사진을 전부 [photo] 로(픽스처 줄 모양은 그대로). */
    private fun withPhotos(json: String, photo: String): String =
        Regex("\"avatar_url\"\\s*:\\s*null").replace(json, "\"avatar_url\":\"$photo\"")

    /** 차단 목록: list_blocks 의 사진까지 닿는다. 사진 없는 줄은 묻지 않는다. */
    @Test
    fun blockedRowsAskForThePhotoListBlocksGave() = runTest {
        val photo = "https://example.com/blocked.jpg"
        val h = ScreenHarness(this, DemoFixtures(DemoFixtures.me), scenario = "me", override = { r ->
            if (r.path == "/rest/v1/rpc/list_blocks") {
                """[{"user_id":"d0000000-0000-4000-8000-0000000000b9","display_name":"민트","avatar_url":"$photo","created_at":"2026-09-16T03:00:00+00:00"},""" +
                    """{"user_id":"d0000000-0000-4000-8000-0000000000c1","display_name":"노을","avatar_url":null,"created_at":"2026-09-10T03:00:00+00:00"}]"""
            } else {
                null
            }
        })
        h.signIn()
        advanceUntilIdle()
        val store = MessagesStore(h.context, h.storeScope, ScreenTestCollation)
        store.loadBlocks(force = true)
        advanceUntilIdle()
        assertEquals(2, store.blockedPeople.size)
        runComposeUiTest {
            show { BlockedPeopleScreen(store, scrollable = false) }
            testScheduler.advanceUntilIdle()
            waitForIdle()
        }
        assertEquals(listOf(photo), asked.toList())
    }
}
