// 원본: Sources/CheckMobileKit/Me/MeTab.swift(MeStageCard.stage · artSize 132 · 칸 artSize+6 × artSize+12) ·
//       Sources/CheckMobileKit/Me/MeCharacterViews.swift(heroArt · 칸 100×104 · 그림 92) @ 3bd04bd
//
// 무대 자리 크기 계약(W3-b ↔ W5-c). 나 탭 무대 칸과 캐릭터 고르기 머리 칸은 **화면이 크기를 정해** 내용(정지 초상 · W5-c 살아 있는 미리보기)에
// 넘긴다. 잰다: ① 칸 크기(138×144 · 100×104 dp) ② 내용에 넘기는 값(착용 id · 근무 상태 · 그림 크기 132 · 92)
// ③ 내용이 칸보다 크게 그리려 해도(300dp) 칸과 카드 배치가 그대로다(W5-c 가 무엇을 세우든 이름표 · 단추가 흔들리지 않는다).
package com.yehsung.aingcheck.ui.screens.me

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.DpRect
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeStageMood
import com.yehsung.aingcheck.core.stores.me.equippedCharacterID
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.screens.settingscommon.RepoScreenArt
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenScene
import com.yehsung.aingcheck.ui.screens.settingscommon.ScreenScenes
import kotlin.math.abs
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@OptIn(ExperimentalTestApi::class)
class MeStageSlotContractDesktopTest {
    private val art = RepoScreenArt(DesktopSnapshots.DENSITY) { DesktopSnapshots.repoImage(it) }

    @BeforeTest
    fun headless() {
        System.setProperty("java.awt.headless", "true")
    }

    private fun SemanticsNodeInteraction.bounds(): DpRect = getUnclippedBoundsInRoot()

    private fun assertSize(what: String, w: Float, h: Float, r: DpRect) {
        val rw = (r.right - r.left).value
        val rh = (r.bottom - r.top).value
        assertTrue(abs(rw - w) < 0.5f && abs(rh - h) < 0.5f, "$what: ${rw}×$rh dp — ${w}×$h 이어야 한다")
    }

    private fun assertSame(what: String, a: DpRect, b: DpRect) {
        val d = listOf(a.left - b.left, a.top - b.top, a.right - b.right, a.bottom - b.bottom).maxOf { abs(it.value) }
        assertTrue(d < 0.5f, "$what: 내용을 바꿨더니 배치가 움직였다($a → $b)")
    }

    @Test
    fun meTabStageSlotIs138x144AndCarriesTheEquippedCharacter() {
        val store = ScreenScenes.me()
        val seen = mutableListOf<MeStageSpec>()
        var greedy by mutableStateOf(false)
        runComposeUiTest {
            setContent {
                ScreenScene(false, art, Modifier) {
                    Box(Modifier.size(380.dp, 1400.dp)) {
                        val scope = rememberCoroutineScope()
                        MeHomeScreen(
                            store, MeStageMood.working, open = {}, scope = scope, scrollable = false,
                            stage = { spec, m ->
                                seen += spec
                                if (greedy) Spacer(m.size(300.dp)) else MeStageDefaults.Static(spec, m)
                            },
                        )
                    }
                }
            }
            waitForIdle()
            val slot = onNodeWithTag(MeStageTags.SLOT).bounds()
            val header = onNodeWithTag(MeAnchor.Header.tag).bounds()
            assertSize("나 탭 무대 칸", 138f, 144f, slot)
            greedy = true
            waitForIdle()
            assertSame("무대 칸", slot, onNodeWithTag(MeStageTags.SLOT).bounds())
            assertSame("무대 카드", header, onNodeWithTag(MeAnchor.Header.tag).bounds())
        }
        val spec = seen.last()
        assertEquals(132f, spec.artSize.value, "그림 크기 = iOS artSize 132")
        assertEquals(138f, spec.slotWidth.value)
        assertEquals(144f, spec.slotHeight.value)
        assertEquals(store.equippedCharacterID, spec.characterId, "착용 캐릭터를 넘긴다")
        assertEquals(CharacterMood.Working, spec.mood, "근무 상태(presence)를 넘긴다")
    }

    @Test
    fun pickerHeroSlotIs100x104WithArt92() {
        val store = ScreenScenes.me(subScreens = true)
        val seen = mutableListOf<MeStageSpec>()
        var greedy by mutableStateOf(false)
        runComposeUiTest {
            setContent {
                ScreenScene(false, art, Modifier) {
                    Box(Modifier.size(380.dp, 1000.dp)) {
                        CharacterPickerScreen(
                            store, openShop = {}, openGachaMachine = {}, scrollable = false,
                            hero = { spec, m ->
                                seen += spec
                                if (greedy) Spacer(m.size(300.dp)) else CharacterPickerHero.Static(spec, m)
                            },
                        )
                    }
                }
            }
            waitForIdle()
            val slot = onNodeWithTag(CharacterPickerTags.HERO_SLOT).bounds()
            val card = onNodeWithTag(CharacterPickerTags.HERO).bounds()
            assertSize("고르기 머리 칸", 100f, 104f, slot)
            greedy = true
            waitForIdle()
            assertSame("머리 칸", slot, onNodeWithTag(CharacterPickerTags.HERO_SLOT).bounds())
            assertSame("머리 카드", card, onNodeWithTag(CharacterPickerTags.HERO).bounds())
        }
        val spec = seen.last()
        assertEquals(92f, spec.artSize.value, "그림 크기 = iOS heroArt 92")
        assertEquals(store.equippedCharacterID, spec.characterId)
        assertEquals(null, spec.mood, "고르기 머리는 근무 상태를 모른다(발밑 빛 회색)")
    }
}
