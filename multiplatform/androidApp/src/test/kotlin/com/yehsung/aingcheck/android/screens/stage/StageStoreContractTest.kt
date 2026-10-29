// 원본: 없음 (W5-c 무대 칸 저장소 ↔ 재생기 BakeImageStore · ImpostorRenderer · CharacterFrames.hitTest 같음 계약 — 페이지를 놓는 저장소가 재생기와 갈리면 빨강)
package com.yehsung.aingcheck.android.screens.stage

import com.yehsung.aingcheck.character.bake.BakeFiles
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.character.player.CharacterFrames
import com.yehsung.aingcheck.character.render.AndroidImage
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.DrawableImage
import com.yehsung.aingcheck.character.render.ImpostorRenderer
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import com.yehsung.aingcheck.ui.components.CharacterMood
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.nio.ByteBuffer
import kotlin.random.Random
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36])
class StageStoreContractTest {
    @get:Rule
    val compose = createComposeRule()

    private val files = StageBundleFiles.Files(StageBundleFiles.bundle())
    private val library: BakeLibrary by lazy { BakeLibrary.load(files) }

    private fun pixels(img: DrawableImage): ByteArray {
        val bmp = (img as AndroidImage).bitmap
        val buf = ByteBuffer.allocate(bmp.width * bmp.height * 4)
        bmp.copyPixelsToBuffer(buf)
        return buf.array()
    }

    @Test
    fun 칸_바이트는_재생기와_같다_L단_57칸_뜬눈_감은눈() {
        for (id in library.bakedIds) {
            val finish = library.finish(id)!!
            val ref = BakeImageStore(finish, files, PlatformRaster)
            val store = StageStore(finish, files, PlatformRaster)
            try {
                val cells = finish.cells("L")!!.cells
                assertEquals(57, cells.size)
                assertEquals(57 + cells.count { it.closedPatch != null }, store.bake(cells))
                assertEquals(2, store.pageDecodes, "$id: 페이지마다 한 번(쉬는 행 · 패치)")
                for (cell in cells) for (closed in listOf(false, true)) {
                    val want = ref.cellRgba(cell, closed)
                    val art = store.cellArt(cell, closed)
                    assertContentEquals(want.px, pixels(art.image), "$id ${cell.id} closed=$closed 칸 바이트")
                    val refMask = ref.cellMask(cell, closed)
                    for (y in 0 until want.height step 3) for (x in 0 until want.width step 3) {
                        if (refMask.isOpaque(x, y) != art.mask.isOpaque(x, y)) error("$id ${cell.id} closed=$closed 마스크 ($x, $y)")
                    }
                }
            } finally {
                ref.close(); store.close()
            }
        }
    }

    @Test
    fun 그리기와_클릭_판정은_재생기와_같다() {
        val assets = StageAssets(files)
        for (id in library.bakedIds) {
            val finish = library.finish(id)!!
            val ref = BakeImageStore(finish, files, PlatformRaster)
            val store = assets.acquire(finish)!!
            try {
                val frames = ArrayList<Pair<String, CharacterFrame>>()
                run {
                    val d = StageDirector(library, finish, 10.0, Random(1))
                    frames += "idle" to d.frame(11.3, 280.0, 340.0)!!
                    check(d.player.blink(12.0)); frames += "blink" to d.frame(12.05, 280.0, 340.0)!!
                    assertEquals(TapOutcome.hit, d.tap(Vec2(137.5, 137.5), d.frame(13.0, 280.0, 340.0), 24.0, store, 13.0))
                    frames += "hit-peak" to d.frame(13.08, 280.0, 340.0)!!
                    frames += "hit-end" to d.frame(13.4, 280.0, 340.0)!!
                    check(d.reveal(14.0)); frames += "reveal-spin" to d.frame(14.3, 280.0, 340.0)!!
                }
                var opaqueHits = 0
                for ((label, frame) in frames) {
                    val a = PlatformRaster.newSurface(280, 340); val b = PlatformRaster.newSurface(280, 340)
                    try {
                        a.clear(); b.clear()
                        ImpostorRenderer.draw(a, (frame as CharacterFrame.Impostor).frame, ref)
                        store.draw(b, frame)
                        assertContentEquals(a.readPixels().px, b.readPixels().px, "$id $label 그림")
                    } finally {
                        a.close(); b.close()
                    }
                    for (y in 0 until 340 step 5) for (x in 0 until 280 step 5) {
                        val p = Vec2(x + 0.5, y + 0.5)
                        val want = CharacterFrames.hitTest(frame, p, 24.0) { ref }
                        assertEquals(want, store.hitTest(frame, p, 24.0), "$id $label 클릭 ($x, $y)")
                        if (want) opaqueHits++
                    }
                }
                assertTrue(opaqueHits > 1000, "판정이 몸을 거의 못 잡는다: $opaqueHits")
            } finally {
                ref.close(); assets.release(store)
            }
        }
        assets.trim()
    }

    @Test
    fun 데운_뒤_무대_리액션은_페이지를_다시_풀지_않는다() {
        val assets = StageAssets(files)
        val finish = library.finish(CharacterCatalog.goldAingID)!!
        val store = assets.acquire(finish)!!
        try {
            val warmed = store.cellCount
            assertEquals(2, store.pageDecodes)
            val d = StageDirector(library, finish, 0.0, Random(3))
            val surface = PlatformRaster.newSurface(280, 340)
            var t = 0.0
            var spinCells = 0
            while (t < 30.0) { // 30초: 살랑 두 바퀴 · 깜빡임 · hit · 공개 한 바퀴
                d.tick(t)
                if (t in 5.0..5.05) d.tap(Vec2(137.5, 137.5), d.frame(t, 280.0, 340.0), 24.0, store, t)
                if (t in 9.0..9.05) {
                    // AingStage 와 같은 순서: 한 바퀴의 S 스핀 칸을 먼저 데운다(스핀 페이지마다 한 번 — 4 · 5). 그리는 동안엔 페이지를 풀지 않는다.
                    assertTrue(store.prewarmSpin(d.spinPrewarmCells()))
                    spinCells = d.spinPrewarmCells().size
                    d.reveal(t)
                }
                surface.clear()
                store.draw(surface, d.frame(t, 280.0, 340.0)!!)
                store.hitTest(d.frame(t, 280.0, 340.0)!!, Vec2(137.5, 137.5), 24.0)
                t += 1.0 / 30
            }
            surface.close()
            println("AINGCHECK-W5C-STORE 데운 칸 $warmed · 30초 뒤 칸 ${store.cellCount} · 페이지 디코드 ${store.pageDecodes}")
            assertEquals(2 + 2, store.pageDecodes, "무대 리액션이 데운 칸 밖으로 나가 페이지를 다시 풀었다(쉬는 행 · 패치 + 스핀 페이지 둘)")
            assertEquals(warmed + spinCells, store.cellCount)
            assertTrue(d.hits == 1 && d.reveals == 1)
        } finally {
            assets.release(store); assets.trim()
        }
    }

    /** 페이지를 읽는 순간 메모리가 모자란 자산(48MB 힙 API 26 에뮬레이터 실측과 같은 갈래). */
    private class OomFiles(private val inner: BakeFiles) : BakeFiles {
        override fun read(path: String): ByteArray? = if (path.endsWith("L-rest-0.webp")) throw OutOfMemoryError("시험: 페이지 할당 실패") else inner.read(path)
        override fun readHalo(fileName: String): ByteArray? = inner.readHalo(fileName)
    }

    @Test
    fun 메모리가_모자라면_죽지_않고_초상으로_선다() {
        val assets = StageAssets(OomFiles(files))
        val lib = assets.libraryOrNull()!!
        assertNull(assets.acquire(lib.finish(CharacterCatalog.builtInAingID)!!))
        assertTrue(assets.failureReason!!.contains("메모리 부족"), assets.failureReason!!)
        assertEquals(emptyMap(), assets.heldStores())
        // 화면: 무대는 살아 있는 칸 없이 초상 무대로 선다(앱이 죽지 않는다).
        compose.mainClock.autoAdvance = false
        val handle = StageHandle()
        compose.setContent { AingStage(CharacterCatalog.builtInAingID, CharacterMood.Working, assets = assets, handle = handle) }
        compose.waitForIdle()
        compose.waitUntil(30_000) { compose.mainClock.advanceTimeByFrame(); handle.bakedIds != null }
        repeat(30) { compose.mainClock.advanceTimeByFrame() }
        compose.waitForIdle()
        assertEquals(StageMode.Live(CharacterCatalog.builtInAingID, folded = false), handle.mode)
        assertNull(handle.store)
        compose.onNodeWithTag(STAGE_LIVE_TAG).assertDoesNotExist()
        compose.onNodeWithTag(STAGE_TAG).assertExists()
    }
}
