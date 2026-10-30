// 공용 패치 20 — 차단 문구의 플랫폼 갈래는 ui commonMain 의 `LocalBlockReportPlatform` 하나가 고른다.
// 원본: Sources/check/WorkTimerStoreBlocks.swift:125-126 (맥 `.mac`) · Sources/check/CheckBlockReportViews.swift:220·276·505·553 (맥 문구 자리)
//       · Sources/CheckMobileKit/Messages/MessagesBlockSheets.swift (폰 `.phone`).
//
// 차단 문구가 서는 일곱 자리를 한 화면에 모두 세운다: 메시지 차단 확인(항목 · 되돌림 줄) · 대국 채팅 차단 확인(항목 · 되돌림 줄) ·
// 차단한 사람(머리말 · 스토어 없음 빈 안내 · 스토어가 빈 목록을 받은 빈 안내). 제공이 없으면 일곱 자리 모두 폰, `.mac` 을 주면 모두 맥.
// 기대 글자는 규칙 함수를 다시 부르지 않고 박는다(길 안내 줄 · 갈래가 다른 확인 항목) — 시험이 같은 갈래로 규칙을 따라 읽으면 틀려도 초록이다.
package com.yehsung.aingcheck.ui.screens.messages

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.BlockReportPlatform
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.games.gomoku.BoardBlockConfirmSheet
import com.yehsung.aingcheck.ui.screens.settingscommon.BlockedPeopleScreen
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

@OptIn(ExperimentalTestApi::class, ExperimentalCoroutinesApi::class)
class BlockReportPlatformLocalDesktopTest {
    private val art = RepoScreenArt(DesktopSnapshots.DENSITY) { DesktopSnapshots.repoImage(it) }

    @BeforeTest
    fun headless() {
        System.setProperty("java.awt.headless", "true")
    }

    private companion object {
        const val PHONE_UNDO = "나 → 설정 → 차단한 사람에서 언제든 풀 수 있어요."
        const val MAC_UNDO = "설정 → 차단한 사람에서 언제든 풀 수 있어요."
        const val PHONE_ITEM = "이 대화가 목록에서 사라져요"
        const val MAC_ITEM = "콕 찌르기·울트라를 서로 보낼 수 없어요"
    }

    /** 차단 목록을 빈 배열로 받은 메시지 스토어 — 차단한 사람 화면이 '빈 안내(Empty)' 칸을 세우게. 픽스처는 합성. */
    private fun TestScope.emptyBlockList(): MessagesStore {
        val h = ScreenHarness(this, DemoFixtures(DemoFixtures.me), scenario = "me") { r ->
            if (r.path == "/rest/v1/rpc/list_blocks") "[]" else null
        }
        h.signIn()
        return MessagesStore(h.context, h.storeScope, ScreenTestCollation)
    }

    /** 일곱 자리 — 메시지 시트(BlockReportSheets 2) · 대국 시트(BoardGameParts 2) · 차단한 사람 둘(머리말 2 · 빈 안내 null 1 · Empty 1). */
    @Composable
    private fun EverySurface(emptyLoaded: MessagesStore) {
        Column(Modifier.size(420.dp, 6000.dp)) {
            MessagesBlockConfirmSheet("라이벌", onConfirm = {}, onClose = {})
            BoardBlockConfirmSheet("라이벌", onConfirm = {}, onClose = {})
            BlockedPeopleScreen(null, scrollable = false)
            BlockedPeopleScreen(emptyLoaded, scrollable = false)
        }
    }

    private fun ComposeUiTest.count(text: String): Int = onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().size

    @Test
    fun withoutProviderEveryBlockSurfaceSpeaksPhone() = runTest {
        val messages = emptyBlockList()
        advanceUntilIdle()
        runComposeUiTest {
            setContent { ScreenScene(false, art, Modifier) { EverySurface(messages) } }
            testScheduler.advanceUntilIdle()
            waitForIdle()
            assertEquals(2, count(PHONE_UNDO), "되돌림 줄(메시지·대국 시트)이 폰 길 안내 '나 → 설정 → 차단한 사람'이 아니다")
            assertEquals(2, count(PHONE_ITEM), "차단 확인 항목(메시지·대국 시트)이 폰 판이 아니다")
            assertEquals(2, count(BlockReportText.blockedListLede(BlockReportPlatform.phone)), "차단한 사람 머리말이 폰 판이 아니다")
            assertEquals(2, count(BlockReportText.blockedEmptyMessage(BlockReportPlatform.phone)), "빈 안내(스토어 없음 · 빈 목록)가 폰 판이 아니다")
            assertEquals(0, count(MAC_UNDO) + count(MAC_ITEM), "제공이 없는데 맥 문구가 섰다")
            assertEquals(
                0,
                count(BlockReportText.blockedListLede(BlockReportPlatform.mac)) + count(BlockReportText.blockedEmptyMessage(BlockReportPlatform.mac)),
                "제공이 없는데 차단한 사람 화면에 맥 문구가 섰다",
            )
        }
    }

    @Test
    fun macProviderTurnsEveryBlockSurfaceToMac() = runTest {
        val messages = emptyBlockList()
        advanceUntilIdle()
        runComposeUiTest {
            setContent {
                ScreenScene(false, art, Modifier) {
                    CompositionLocalProvider(LocalBlockReportPlatform provides BlockReportPlatform.mac) { EverySurface(messages) }
                }
            }
            testScheduler.advanceUntilIdle()
            waitForIdle()
            assertEquals(2, count(MAC_UNDO), "되돌림 줄(메시지·대국 시트)이 맥 길 안내 '설정 → 차단한 사람'이 아니다")
            assertEquals(2, count(MAC_ITEM), "차단 확인 항목(메시지·대국 시트)이 맥 판(콕·울트라)이 아니다")
            assertEquals(2, count("콕 찌르기 목록과 오목 신청에서 서로 보이지 않아요"), "차단 확인 셋째 항목이 맥 판이 아니다")
            assertEquals(2, count(BlockReportText.blockedListLede(BlockReportPlatform.mac)), "차단한 사람 머리말이 맥 판이 아니다")
            assertEquals(2, count(BlockReportText.blockedEmptyMessage(BlockReportPlatform.mac)), "빈 안내(스토어 없음 · 빈 목록)가 맥 판이 아니다")
            assertEquals(0, count(PHONE_UNDO) + count(PHONE_ITEM), "`.mac` 을 줬는데 폰 문구가 남았다")
            assertEquals(
                0,
                count(BlockReportText.blockedListLede(BlockReportPlatform.phone)) + count(BlockReportText.blockedEmptyMessage(BlockReportPlatform.phone)),
                "`.mac` 을 줬는데 차단한 사람 화면에 폰 문구가 남았다",
            )
        }
    }
}
