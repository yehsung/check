// 원본: 없음(조립) — 구운 아잉이 재생기가 엔진 문(CharacterSink)과 그리기 층을 같은 플레이어로 잇는지, 굽기 뿌리가 없으면 그리지 않는 자리.
// 자산은 저장소 제자리(multiplatform/assets/aing-bake, aingcheck.repoRoot) — 복사 0.
package com.yehsung.aingcheck.desktop.overlay.assembly

import com.yehsung.aingcheck.desktop.overlay.engine.FrameIntent
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayMode
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayView
import com.yehsung.aingcheck.desktop.overlay.render.OverlayCompositor
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class BakedCharacterTest {
    private val bakeRoot = File(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 가 없다" }, "multiplatform/assets/aing-bake")

    private fun view(mode: OverlayMode) = OverlayView(
        mode = mode, characterId = "aing", bubble = null, activeReaction = null, reactionStartedAt = null, sleeping = false,
        facing = 0, walking = false, particles = emptyList(), frame = FrameIntent.Default(0), renderSuspended = false,
    )

    private fun opaqueCount(bytes: ByteArray): Int { var n = 0; var i = 3; while (i < bytes.size) { if (bytes[i].toInt() != 0) n++; i += 4 }; return n }

    @Test
    fun repoBakeDrawsTheCharacterInsideThePanelAndTheSinkDrivesTheSamePlayer() {
        val c = assertNotNull(BakedCharacter.loadOrNull(bakeRoot), "저장소 굽기 묶음을 못 읽었다")
        c.use {
            assertEquals("aing", c.sink.currentCharacterId)
            OverlayCompositor().use { comp ->
                val scale = 1.5
                val w = (140 * scale).toInt()
                val h = (170 * scale).toInt()
                val frame = comp.compose(view(OverlayMode.Normal), w, h, scale, 0.0, c.layer)
                val n = opaqueCount(frame.rgbaPremultiplied)
                assertTrue(n > w * h / 10, "캐릭터 픽셀이 너무 적다($n / ${w * h})")
                assertEquals(0, frame.alphaAt(0, 0), "모서리는 투명(클릭이 뒤 창으로)")
                assertTrue(frame.alphaAt(w / 2, h * 2 / 3) > 0, "몸 가운데는 불투명")
                // 숨김이면 같은 층이라도 전부 투명.
                assertEquals(0, opaqueCount(comp.compose(view(OverlayMode.Hidden), w, h, scale, 0.0, c.layer).rgbaPremultiplied))
            }
            // 엔진 문으로 갈아입히면 그리는 플레이어도 바뀐다(울트라 보낸 사람 캐릭터).
            c.sink.swapCharacter("aing_gold", 1.0)
            assertEquals("aing_gold", c.player.currentCharacterId)
            c.sink.swapCharacter(null, 2.0)
            assertEquals("aing", c.player.currentCharacterId, "null 은 아잉(맥 applyUltraCharacter)")
        }
    }

    @Test
    fun missingOrBrokenBakeRootFallsBackToNoCharacter() {
        assertNull(BakedCharacter.loadOrNull(null))
        val empty = Files.createTempDirectory("aing-bake-empty").toFile()
        try {
            assertNull(BakedCharacter.loadOrNull(empty), "camera.json 없는 뿌리")
            File(empty, "camera.json").writeText("{ 깨진 json")
            assertNull(BakedCharacter.loadOrNull(empty), "깨진 묶음")
        } finally {
            empty.deleteRecursively()
        }
    }

    @Test
    fun directoryBakeFilesRefusesPathsOutsideTheRoot() {
        val files = DirectoryBakeFiles(bakeRoot)
        assertNotNull(files.read("camera.json"))
        assertNull(files.read("../aing-bake/../../settings.gradle.kts"), "뿌리 밖")
        assertNull(files.read("no-such-file.json"))
    }
}
