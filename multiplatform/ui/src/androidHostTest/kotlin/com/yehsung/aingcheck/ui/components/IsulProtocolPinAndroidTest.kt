// 원본: Tests/CheckMobileKitTests/MeIsulProtocolPinTests.swift @ 12624739 (폰 번호 4 고정 → 이 판에서 Android 는 5 로 연다)
//
// Android 판 7(대표 결재 "판 7에 전부 넣기"): 이슬 아잉이 초상 두 장이 APK 자산으로 실리고, 상점 능력 번호가 **저절로 5** 가 된다(손으로 적는 숫자가
// 없다 — 실린 초상 목록 portraits.txt 에서 파생). 데스크톱(Windows v1 — 기능 동결)은 같은 묶음에서도 4 다(CharacterArtPortraitIndexTest).
// 함정(설계서 isul-aing/SPEC.md §2): 케이크 뜻 목록(cakeCharacterIDs)에 이슬을 섞으면 이슬 한 장이 빠진 빌드가 3 으로 떨어져 케이크 선물까지 잃는다.
package com.yehsung.aingcheck.ui.components

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.runComposeUiTest
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import com.yehsung.aingcheck.core.rules.gacha.ShopWire
import com.yehsung.aingcheck.core.stores.me.MeCharacterCards
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftKind
import com.yehsung.aingcheck.ui.resources.Res
import kotlinx.coroutines.runBlocking
import org.jetbrains.compose.resources.ExperimentalResourceApi
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h640dp-xhdpi")
@OptIn(ExperimentalResourceApi::class, ExperimentalTestApi::class)
class IsulProtocolPinAndroidTest {
    @Test
    fun androidShipsIsulPortraitsAndSaysProtocolFive() = runComposeUiTest {
        assertTrue("Android 문은 참이어야 한다", CharacterArt.takesDrinkGift)
        // 이슬 초상 두 장이 APK 자산이고 맥 원본과 바이트가 같다(ui/build.gradle.kts isulPortraitSource — 지금은 맥 그림 그대로).
        val repo = AndroidSnapshots.repoRoot
        for (e in CharacterExpression.entries) {
            val bytes = runBlocking { Res.readBytes(CharacterArt.portraitPath(CharacterCatalog.isulAingID, e)) }
            assertArrayEquals(e.name, File(repo, "Sources/check/Resources/aing_isul-${e.fileSuffix}.png").readBytes(), bytes)
        }
        val drawable = runBlocking { CharacterArt.drawableCharacterIDs() }
        assertTrue("$drawable", CharacterCatalog.isulAingID in drawable)
        val derived = ShopWire.protocolVersion(drawable)
        assertEquals("실린 초상 $drawable → $derived", ShopWire.isulProtocol, derived)
        assertTrue(ShopWire.supportsCakeGift(derived))
        assertTrue(ShopWire.supportsDrinkGift(derived))
        assertTrue(CharacterGiftKind.drink.isSupported(derived))
        assertEquals(drawable, runBlocking { CharacterArt.drawableCharacterSource.drawableCharacterIDs() })
        assertTrue("스토어의 이슬 접기 문도 같은 플랫폼 문(검토 ISUL-1)", CharacterArt.drawableCharacterSource.takesDrinkGift)
        // 카드 목록(고르기 · 상점 자리표시 · 착용값 접기)에도 이슬이 선다 — 케이크 뒤, 스프라이트 앞(내장 순서).
        val known = MeCharacterCards.knownIDs(CharacterArt.drawableCharacterSource.takesDrinkGift)
        assertEquals(known.indexOf(CharacterCatalog.cakeChocoAingID) + 1, known.indexOf(CharacterCatalog.isulAingID))
        assertEquals(CharacterCatalog.isulAingID, MeCharacterCards.equippedID(CharacterCatalog.isulAingID, CharacterArt.drawableCharacterSource.takesDrinkGift))
        // 반대 방향(함정 §2): 이슬 한 장이 빠진 빌드는 4(케이크 선물은 그대로 산다) — 3 으로 떨어지지 않는다.
        assertEquals(ShopWire.cakeProtocol, ShopWire.protocolVersion(drawable - CharacterCatalog.isulAingID))
    }
}
