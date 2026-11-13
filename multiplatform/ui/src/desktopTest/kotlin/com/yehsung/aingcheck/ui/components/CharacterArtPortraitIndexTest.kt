// 원본: Sources/CheckMobileShared/AingCharacterArt.swift @ 1b8260d (`knownIDs` = 번들에 실린 초상 — K9 상점 번호의 재료)
//
// K9 배선(W2-c 조정자 패치): 상점 능력 번호는 손 목록이 아니라 **실제로 실린 초상 파일 목록**(Sync 가 쓰는 files/characters/portraits.txt)에서
// 파생한다. 목록 = Sync 출력 폴더의 portrait-*.png 그대로여야 하고(손으로 적은 목록이 아니다), 한 장이 빠진 집합은 번호가 내려간다.
package com.yehsung.aingcheck.ui.components

import com.yehsung.aingcheck.core.rules.gacha.ShopWire
import kotlinx.coroutines.runBlocking
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CharacterArtPortraitIndexTest {
    private val synced = File(DesktopSnapshots.mpRoot, "ui/build/generated/aingcheck/composeResources/commonMain/files/characters")

    /** Sync 출력 폴더에 실제로 있는 초상 파일 → `<id>-<표정>`. */
    private fun portraitsOnDisk(): List<String> = synced.listFiles().orEmpty().filter { it.isDirectory }.flatMap { dir ->
        dir.listFiles().orEmpty().mapNotNull { f -> Regex("^portrait-(.+)\\.png$").find(f.name)?.let { "${dir.name}-${it.groupValues[1]}" } }
    }.sorted()

    @Test
    fun indexListsExactlyThePortraitFilesTheBuildShipped() {
        val index = runBlocking { CharacterArt.portraitResourceNames() }
        val onDisk = portraitsOnDisk()
        assertTrue(onDisk.isNotEmpty(), "Sync 출력에 초상이 없다: $synced")
        assertEquals(onDisk, index, "목록은 실린 파일 그대로(손 목록이 아니다)")
        val expected = CharacterArt.portraitIds.flatMap { id -> CharacterExpression.entries.map { "$id-${it.fileSuffix}" } }.sorted()
        assertEquals(expected, index, "번들 = 초상 16 × 2(케이크 둘 · 이슬 · 판 8 새 아잉이 넷 포함)")
        assertEquals(32, index.size, "초상 16 × 2")
    }

    @Test
    fun shopProtocolComesFromTheShippedPortraitsAndDropsWhenOneIsMissing() {
        // 데스크톱(Windows v1 — 기능 동결)은 술 한잔 선물을 안 받는다: 이슬 초상은 실렸지만 그림 재료에서 빠져 번호가 4 그대로다.
        assertEquals(false, CharacterArt.takesDrinkGift, "데스크톱 문")
        val drawable = runBlocking { CharacterArt.drawableCharacterIDs() }
        assertEquals(CharacterArt.portraitIds.toSet() - ShopWire.isulCharacterIDs.toSet(), drawable)
        // 판 8: 새 아잉이 넷은 실렸어도 이슬이 빠진 데스크톱은 번호 4 에 머문다(번호는 누적 — 건너뛰어 말할 수 없다).
        assertEquals(ShopWire.cakeProtocol, ShopWire.protocolVersion(drawable), "데스크톱: 케이크 둘까지 → 4(이슬은 실려도 빼낸다)")
        assertEquals(drawable, runBlocking { CharacterArt.drawableCharacterSource.drawableCharacterIDs() }, "스토어에 꽂는 재료가 같은 집합")
        assertEquals(false, CharacterArt.drawableCharacterSource.takesDrinkGift, "스토어의 이슬 접기 문도 같은 플랫폼 문(검토 ISUL-1 — 데스크톱은 이슬을 아잉으로 접는다)")
        val index = runBlocking { CharacterArt.portraitResourceNames() }
        // Android(판 8) 문 = 같은 그림 묶음에서 개발 아잉이까지 → 9(지역 둘은 그림이 없어 10 은 아니다). 이슬 한 장만 빠져도 4 로 내려간다.
        assertEquals(ShopWire.devProtocol, ShopWire.protocolVersion(CharacterArt.drawableFor(index, takesDrinkGift = true)), "Android: 개발 아잉이까지 → 9")
        assertEquals(ShopWire.rubyProtocol, ShopWire.protocolVersion(CharacterArt.drawableFor(index - "aing_dev-neutral", takesDrinkGift = true)), "개발 한 장 빠지면 8")
        assertEquals(ShopWire.isulProtocol, ShopWire.protocolVersion(CharacterArt.drawableFor(index - "aing_pepero-negative", takesDrinkGift = true)), "빼빼로 빠지면 5")
        assertEquals(CharacterArt.portraitIds.toSet(), CharacterArt.drawableFor(index, takesDrinkGift = true))
        assertEquals(ShopWire.cakeProtocol, ShopWire.protocolVersion(CharacterArt.drawableFor(index - "aing_isul-negative", takesDrinkGift = true)))
        assertEquals(ShopWire.rainbowProtocol, ShopWire.protocolVersion(CharacterArt.drawableFor(index - "aing_cake_choco-neutral", takesDrinkGift = true)),
            "이슬이 있어도 케이크 하나가 빠지면 3")
        // 초코 케이크의 한 장(negative)만 빠져도 그 캐릭터는 그릴 수 없다 → 번호가 무지개(3)로 내려간다.
        assertEquals(ShopWire.rainbowProtocol, ShopWire.protocolVersion(ShopWire.drawableCharacterIDs(index - "aing_cake_choco-negative")))
        assertEquals(ShopWire.legacyProtocol, ShopWire.protocolVersion(ShopWire.drawableCharacterIDs(index - "robot-neutral")))
    }
}
