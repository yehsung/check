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
        assertEquals(expected, index, "1b8260d 번들 = 초상 11 × 2(케이크 둘 포함)")
    }

    @Test
    fun shopProtocolComesFromTheShippedPortraitsAndDropsWhenOneIsMissing() {
        val drawable = runBlocking { CharacterArt.drawableCharacterIDs() }
        assertEquals(CharacterArt.portraitIds.toSet(), drawable)
        assertEquals(ShopWire.cakeProtocol, ShopWire.protocolVersion(drawable), "케이크 둘까지 다 실렸다 → 4")
        assertEquals(drawable, runBlocking { CharacterArt.drawableCharacterSource.drawableCharacterIDs() }, "스토어에 꽂는 재료가 같은 집합")
        val index = runBlocking { CharacterArt.portraitResourceNames() }
        // 초코 케이크의 한 장(negative)만 빠져도 그 캐릭터는 그릴 수 없다 → 번호가 무지개(3)로 내려간다.
        assertEquals(ShopWire.rainbowProtocol, ShopWire.protocolVersion(ShopWire.drawableCharacterIDs(index - "aing_cake_choco-negative")))
        assertEquals(ShopWire.legacyProtocol, ShopWire.protocolVersion(ShopWire.drawableCharacterIDs(index - "robot-neutral")))
    }
}
