// 원본: Sources/check/Characters · Sources/check/Resources · Sources/CheckMobileKit/Resources/Art · Sources/CheckCore/Resources/Stickers @ 862be0f
//
// W1-e 완료 기준 ④(데스크톱): Sources/check/Characters 를 Gradle Sync(aingcheckSyncCharacterArt)로 읽어 Compose 리소스로 연다.
// 0.3.62 아잉이 이모티콘(Sources/CheckCore/Resources/Stickers)도 같은 Sync 로 files/stickers 에 싣는다(G §8-2).
// 리소스로 연 바이트가 맥 원본과 같다(사본을 따로 두지 않았으니 같을 수밖에 없다 — 다르면 다른 그림이 실렸다).
// 이 시험은 ui/build.gradle.kts 의 Sync·customDirectory(조정자 패치 w1e-ui-build)가 있어야 돈다.
package com.yehsung.aingcheck.ui.components

import com.yehsung.aingcheck.ui.resources.Res
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.jetbrains.compose.resources.ExperimentalResourceApi
import java.io.File
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

@OptIn(ExperimentalResourceApi::class)
class CharacterArtSyncDesktopTest {
    private val repo = DesktopSnapshots.repoRoot

    @Test
    fun foxManifestLoadsThroughComposeResources() {
        val bytes = runBlocking { Res.readBytes(CharacterArt.manifestPath("fox")) }
        assertContentEquals(File(repo, "Sources/check/Characters/fox/manifest.json").readBytes(), bytes, "리소스 매니페스트 ≠ 원본")
        val json = Json.parseToJsonElement(bytes.decodeToString()).jsonObject
        assertEquals("fox", json.getValue("id").jsonPrimitive.content)
        assertEquals("sprite", json.getValue("kind").jsonPrimitive.content)
        for (id in CharacterArt.spriteIds) {
            val m = Json.parseToJsonElement(runBlocking { Res.readBytes(CharacterArt.manifestPath(id)) }.decodeToString()).jsonObject
            assertEquals(id, m.getValue("id").jsonPrimitive.content)
        }
    }

    @Test
    fun everyPortraitAndArtDecodesAndEqualsTheMacOriginal() {
        for (id in CharacterArt.portraitIds) for (e in CharacterExpression.entries) {
            val path = CharacterArt.portraitPath(id, e)
            val original = if (id.startsWith("aing")) File(repo, "Sources/check/Resources/$id-${e.fileSuffix}.png")
            else File(repo, "Sources/check/Characters/$id/portrait-${e.fileSuffix}.png")
            assertContentEquals(original.readBytes(), runBlocking { Res.readBytes(path) }, "$path ≠ ${original.relativeTo(repo)}")
            val img = assertNotNull(runBlocking { CharacterArt.decode(path) }, "$path 디코드 실패")
            assertEquals(192 to 192, img.width to img.height, path)
        }
        for (name in listOf("ruby", "ruby-48", "ruby-96") + CharacterArt.spriteIds.map { "stage-$it-neutral" }) {
            val original = File(repo, "Sources/CheckMobileKit/Resources/Art/$name.png")
            assertContentEquals(original.readBytes(), runBlocking { Res.readBytes("files/art/$name.png") }, name)
        }
        // 아틀라스는 싣지 않는다(살아 있는 캐릭터는 구운 자산).
        assertNull(runBlocking { CharacterArt.readBytesOrNull("files/characters/fox/atlas.png") })
    }

    /** 이모티콘 그림 전부(main 트리의 sticker-*.png — 862be0f 기준 6장)가 Compose 리소스로 열리고 원본과 바이트가 같다. */
    @Test
    fun everyStickerLoadsAndEqualsTheMacOriginal() {
        val originals = File(repo, CharacterArt.STICKER_SOURCE_DIR).listFiles().orEmpty()
            .filter { it.isFile && it.name.startsWith("sticker-") && it.name.endsWith(".png") }.sortedBy { it.name }
        assertEquals(6, originals.size, "이모티콘 원본: ${originals.map { it.name }}")
        for (f in originals) {
            val name = f.name.removePrefix("sticker-").removeSuffix(".png")
            val path = CharacterArt.stickerPath(name)
            assertContentEquals(f.readBytes(), runBlocking { Res.readBytes(path) }, "$path ≠ ${f.relativeTo(repo)}")
            val img = assertNotNull(runBlocking { CharacterArt.decode(path) }, "$path 디코드 실패")
            assertEquals(512 to 512, img.width to img.height, path)
        }
        // 없는 이름은 null(그림이 빠진 빌드를 화면이 글자로 접을 수 있게).
        assertNull(runBlocking { CharacterArt.readBytesOrNull(CharacterArt.stickerPath("nope")) })
    }
}
