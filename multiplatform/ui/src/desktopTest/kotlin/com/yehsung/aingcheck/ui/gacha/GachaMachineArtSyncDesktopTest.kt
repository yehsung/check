// 원본: Tests/checkTests/V0354GachaMachineTests.swift @ 3bd04bd ("CheckCore 번들에 기계 그림 다섯 장이 GachaMachine/ 폴더째 실린다 — 원본과 같은 바이트" ·
// "배포 그림 묶음(.bundled)은 다섯 칸이 다 찬다 — 벡터는 안전망일 뿐")
//
// W4-c 조정자 패치 0001(ui/build.gradle.kts Sync 에 기계 그림 다섯 장): 앱이 Compose 리소스(files/gacha)로 연 바이트가 맥 원본과 같고,
// 다섯 장이 다 풀리며, multiplatform/ 아래에 사본이 없다(Sync 출력은 build/ 아래). 이 시험은 그 패치와 함께만 돈다.
package com.yehsung.aingcheck.ui.gacha

import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineArt
import com.yehsung.aingcheck.ui.resources.Res
import kotlinx.coroutines.runBlocking
import org.jetbrains.compose.resources.ExperimentalResourceApi
import java.io.File
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalResourceApi::class)
class GachaMachineArtSyncDesktopTest {
    private val repo = DesktopSnapshots.repoRoot

    @Test
    fun fiveMachineImagesLoadAndEqualTheMacOriginals() {
        assertEquals(listOf("gacha_body", "gacha_knob", "gacha_capsule", "gacha_capsule_gold", "gacha_cap"), GachaMachineArt.resourceNames)
        for (name in GachaMachineArt.resourceNames) {
            val original = File(repo, "${GachaMachineArt.SOURCE_DIR}/$name.png")
            assertTrue(original.isFile, "원본이 없다: $original")
            val path = GachaMachineArt.resourcePath(name)
            assertContentEquals(original.readBytes(), runBlocking { Res.readBytes(path) }, "$path ≠ ${original.relativeTo(repo)}")
            assertNotNull(runBlocking { CharacterArt.decode(path) }, "$path 디코드 실패")
        }
        // 없는 이름은 null(그림이 빠진 빌드는 그 칸만 벡터로 그린다).
        assertNull(runBlocking { CharacterArt.readBytesOrNull(GachaMachineArt.resourcePath("gacha_nope")) })
    }

    @Test
    fun noCopyOfMachineArtUnderMultiplatform() {
        fun sha(f: File) = MessageDigest.getInstance("SHA-256").digest(f.readBytes()).joinToString("") { "%02x".format(it) }
        val originals = GachaMachineArt.resourceNames.map { File(repo, "${GachaMachineArt.SOURCE_DIR}/$it.png") }.associateBy { sha(it) }
        assertEquals(5, originals.size)
        val root = DesktopSnapshots.mpRoot
        val copies = root.walkTopDown()
            .onEnter { it == root || (it.name != "build" && it.name != ".gradle" && it.name != ".kotlin" && it.name != "spikes") }
            .filter { it.isFile && it.name.endsWith(".png") }
            .mapNotNull { f -> originals[sha(f)]?.let { "${f.relativeTo(root).invariantSeparatorsPath} = ${it.name}" } }
            .toList()
        assertTrue(copies.isEmpty(), "multiplatform/ 에 기계 그림 사본이 있다(Gradle Sync 로 읽어야 한다):\n" + copies.joinToString("\n"))
    }
}
