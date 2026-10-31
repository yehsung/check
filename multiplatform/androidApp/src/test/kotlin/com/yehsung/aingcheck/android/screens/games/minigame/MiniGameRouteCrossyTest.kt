// 원본: 없음 — 길건너 폰 노출의 **부르는 자리**(androidApp 경로): 라우트 글자 → 화면 → 허브 판 → 폰 조작 문구. 스토어만 있고 화면에 안 붙는 일이 없게 앱 모듈에서 잰다.
package com.yehsung.aingcheck.android.screens.games.minigame

import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.semantics.SemanticsProperties
import com.yehsung.aingcheck.android.screens.games.hub.GamesAndroidRig
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.ui.games.minigame.GamesMiniGameScreen
import com.yehsung.aingcheck.ui.games.minigame.MiniGameArt
import com.yehsung.aingcheck.ui.games.minigame.MiniGameScreenTags
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h740dp-xhdpi")
class MiniGameRouteCrossyTest {
    @get:Rule
    val compose = createComposeRule()

    private fun described(text: String) = SemanticsMatcher("contentDescription == $text") { node ->
        SemanticsProperties.ContentDescription in node.config && text in node.config[SemanticsProperties.ContentDescription]
    }

    /** 앱 라우트가 길건너를 열고 폰 조작 문구를 켠다. */
    @Test
    fun theRouteOpensCrossyWithPhoneControls() {
        GamesAndroidRig().use { rig ->
            var backs = 0
            compose.setContent { AingTheme(dark = false) { MiniGameRoute(rig.store, "crossy", null, onBack = { backs += 1 }) } }
            compose.waitForIdle()
            assertEquals(MiniGameKind.crossy, rig.store.miniGames.controller?.kind)
            assertEquals("보이는 게임이면 돌아가지 않는다", 0, backs)
            compose.onNodeWithTag(MiniGameScreenTags.CANVAS).assert(described(GamesMiniGameText.canvasAccessibility(MiniGameKind.crossy)))
            assertTrue("쓸어서" in GamesMiniGameText.canvasAccessibility(MiniGameKind.crossy))
        }
    }

    /** 기준선: 모르는 글자는 화면을 세우지 않고 돌아간다 — 위 단언이 늘 참인 게 아니다. */
    @Test
    fun anUnknownGameGoesBack() {
        GamesAndroidRig().use { rig ->
            var backs = 0
            compose.setContent { AingTheme(dark = false) { MiniGameRoute(rig.store, "chess", null, onBack = { backs += 1 }) } }
            compose.waitForIdle()
            assertNull(rig.store.miniGames.controller)
            assertEquals(1, backs)
        }
    }

    /** 기준선: 켜는 인자를 안 주면(Windows 경로) 데스크톱 문구다 — 라우트가 정말 켜고 있다는 뜻이다. */
    @Test
    fun theDefaultIsTheDesktopCopy() {
        GamesAndroidRig().use { rig ->
            compose.setContent { AingTheme(dark = false) { GamesMiniGameScreen(rig.store, MiniGameKind.crossy, 60, MiniGameArt.empty, null) } }
            compose.waitForIdle()
            compose.onNodeWithTag(MiniGameScreenTags.CANVAS).assert(described(GamesMiniGameText.crossyDesktopCanvasAccessibility()))
            assertFalse("쓸어서" in GamesMiniGameText.crossyDesktopCanvasAccessibility())
        }
    }
}
