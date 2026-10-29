// 원본: Sources/CheckMobileKit/Me/MeTab.swift @ 3bd04bd (MeStageCard.stage — 무대 자리 · 크기) — W5-c 완료 ③ 탭하면 hit 반응(화면 위 실제 탭 · 실제 픽셀)
package com.yehsung.aingcheck.android.screens.stage

import android.graphics.Bitmap
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h640dp-xhdpi")
class AingStageComposeTest {
    @get:Rule
    val compose = createComposeRule()

    private val assets = StageAssets(StageBundleFiles.Files(StageBundleFiles.bundle()))
    private val clock = StageClock { compose.mainClock.currentTime / 1000.0 }

    private fun awaitLive(handle: StageHandle) {
        compose.waitForIdle() // 시험 스레드에서 바꾼 상태(id · key)를 적용 알림으로 내보낸다 — waitUntil 은 알림을 보내지 않는다(실측)
        try {
            compose.waitUntil(60_000) {
                compose.mainClock.advanceTimeByFrame()
                handle.store != null && handle.placement != null && handle.lastFrame != null
            }
        } catch (e: Throwable) {
            throw AssertionError("무대가 서지 않았다: id=${handle.characterId} baked=${handle.bakedIds} mode=${handle.mode} store=${handle.store} director=${handle.director} placement=${handle.placement} " +
                "frames=${handle.framesPublished} 자산 실패=${assets.failureReason} 쥔 저장소=${assets.heldStores()}", e)
        }
    }

    /** 공개는 한 바퀴의 S 스핀 칸을 배경에서 데운 뒤에 걸린다(AingStage) — 진짜 시간으로 기다린다. */
    private fun awaitReveals(handle: StageHandle, n: Int) {
        compose.waitForIdle()
        compose.waitUntil(60_000) {
            compose.mainClock.advanceTimeByFrame()
            (handle.director?.reveals ?: 0) >= n
        }
    }

    private fun frames(ms: Long) {
        var left = ms
        while (left > 0) { compose.mainClock.advanceTimeByFrame(); left -= 16 }
        compose.waitForIdle()
    }

    /** 노드 안 좌표(px): 틀 좌표 (x, y) → 노드 좌표. */
    private fun StageHandle.toNode(x: Double, y: Double): Offset {
        val p = placement!!
        return Offset((p.originX + x * p.scale).toFloat(), (p.originY + y * p.scale).toFloat())
    }

    private fun opaque(bmp: Bitmap): Int {
        var n = 0
        val px = IntArray(bmp.width * bmp.height)
        bmp.getPixels(px, 0, bmp.width, 0, 0, bmp.width, bmp.height)
        return px.count { (it ushr 24) == 0xFF }
    }

    private fun meanAbsDiff(a: Bitmap, b: Bitmap): Double {
        val pa = IntArray(a.width * a.height).also { a.getPixels(it, 0, a.width, 0, 0, a.width, a.height) }
        val pb = IntArray(b.width * b.height).also { b.getPixels(it, 0, b.width, 0, 0, b.width, b.height) }
        var s = 0L
        for (i in pa.indices) for (sh in intArrayOf(0, 8, 16)) s += abs(((pa[i] ushr sh) and 0xFF) - ((pb[i] ushr sh) and 0xFF))
        return s.toDouble() / (pa.size * 3)
    }

    private fun save(bmp: Bitmap, name: String) {
        val dir = File("build/aingcheck-stage/robolectric").apply { mkdirs() }
        File(dir, name).outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Test
    fun 아잉을_두드리면_hit_로_찌부러지고_몸_밖은_빗나간다() {
        compose.mainClock.autoAdvance = false
        val handle = StageHandle()
        compose.setContent {
            AingTheme(dark = false) {
                AingStage(CharacterCatalog.builtInAingID, CharacterMood.Working, assets = assets, clock = clock, handle = handle)
            }
        }
        awaitLive(handle)
        assertEquals(StageMode.Live(CharacterCatalog.builtInAingID, folded = false), handle.mode)
        frames(200)
        val node = compose.onNodeWithTag(STAGE_LIVE_TAG)
        val idle = node.captureToImage().asAndroidBitmap()
        save(idle, "aing-idle.png")
        assertTrue(opaque(idle) > 3000, "살아 있는 아잉이가 그려졌다(불투명 ${opaque(idle)})")
        // 몸 가운데를 실제로 두드린다(틀 280×340 의 정면 몸 상자 가운데).
        node.performTouchInput { click(handle.toNode(137.5, 137.5)) }
        compose.waitForIdle()
        assertEquals(TapOutcome.hit, handle.lastTap)
        assertEquals(StagePolicy.TAP_REACTION, handle.director!!.player.activeReaction)
        frames(80) // hit 정점(0.08s) 근처
        val squash = node.captureToImage().asAndroidBitmap()
        save(squash, "aing-hit.png")
        val d = meanAbsDiff(idle, squash)
        println("AINGCHECK-W5C-TAP idle→hit 평균 차 ${"%.2f".format(d)} 불투명 ${opaque(idle)}→${opaque(squash)}")
        assertTrue(d > 2.0, "탭 뒤 그림이 바뀌지 않았다($d)")
        // 몸 밖(그림 칸 왼쪽 위 구석)은 빗나간다 — 그림은 쿨다운이 지나도 hit 를 걸지 않는다.
        frames(800)
        node.performTouchInput { click(Offset(2f, 2f)) }
        compose.waitForIdle()
        assertEquals(TapOutcome.missed, handle.lastTap)
        assertEquals(1, handle.director!!.hits)
        // 탭 좌표는 틀 원점을 빼서 뷰포트로 옮긴다: 맞게 옮기면 몸 · 노드 좌표를 그대로 쓰면 몸 밖인 점을 골라 두드린다.
        val nodeSize = node.fetchSemanticsNode().size
        val probe = discriminatingPoint(handle, nodeSize.width, nodeSize.height)
        node.performTouchInput { click(probe) }
        compose.waitForIdle()
        assertEquals(TapOutcome.hit, handle.lastTap, "틀 원점을 쓰는 탭 판정(점 $probe)")
        assertEquals(2, handle.director!!.hits)
        // 접근성 동작(두드리기)도 같은 hit 를 건다.
        frames(800)
        node.assert(SemanticsMatcher.keyIsDefined(SemanticsActions.OnClick))
        node.performSemanticsAction(SemanticsActions.OnClick)
        compose.waitForIdle()
        assertEquals(TapOutcome.hit, handle.lastTap)
        assertEquals(3, handle.director!!.hits)
    }

    /** 지금 프레임에서 "노드 − 틀 원점"으로는 몸(±4px 모두 알파 > 32)이고 "노드 그대로"로는 몸 밖(±4px 모두)인 노드 좌표. */
    private fun discriminatingPoint(handle: StageHandle, width: Int, height: Int): Offset {
        val p = handle.placement!!
        val f = handle.lastFrame!!
        val store = handle.store!!
        fun hit(x: Double, y: Double) = synchronized(store.lock) { store.hitTest(f, Vec2(x, y), 0.0) }
        fun solid(x: Double, y: Double, want: Boolean) = listOf(-4.0, 0.0, 4.0).all { dx -> listOf(-4.0, 0.0, 4.0).all { dy -> hit(x + dx, y + dy) == want } }
        for (fy in 0 until 340 step 4) for (fx in 0 until 280 step 4) {
            val vx = fx * p.scale; val vy = fy * p.scale
            val nx = vx + p.originX; val ny = vy + p.originY
            if (nx < 6 || ny < 6 || nx > width - 6 || ny > height - 6) continue
            if (solid(vx, vy, true) && solid(nx, ny, false)) return Offset(nx.toFloat(), ny.toFloat())
        }
        error("가르는 점이 없다(원점 ${p.originX}, ${p.originY})")
    }

    @Test
    fun 스프라이트는_초상_케이크는_아잉으로_접혀_산다() {
        compose.mainClock.autoAdvance = false
        var id by mutableStateOf("fox")
        val handle = StageHandle()
        compose.setContent {
            AingTheme(dark = false) { AingStage(id, CharacterMood.Off, assets = assets, clock = clock, handle = handle) }
        }
        compose.waitUntil(60_000) { compose.mainClock.advanceTimeByFrame(); handle.mode == StageMode.Portrait && assets.libraryOrNull() != null }
        frames(100)
        assertEquals(StageMode.Portrait, handle.mode)
        compose.onNodeWithTag(STAGE_LIVE_TAG).assertDoesNotExist()
        compose.onNodeWithTag(STAGE_TAG).assertExists()
        id = CharacterCatalog.cakeStrawberryAingID
        awaitLive(handle)
        assertEquals(StageMode.Live(CharacterCatalog.builtInAingID, folded = true), handle.mode)
        assertEquals(CharacterCatalog.builtInAingID, handle.director!!.player.currentCharacterId)
        val desc = compose.onNodeWithTag(STAGE_LIVE_TAG).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        assertTrue("(아잉 모습)" in desc, desc)
        save(compose.onNodeWithTag(STAGE_TAG).captureToImage().asAndroidBitmap(), "cake-strawberry-folded.png")
    }

    @Test
    fun 공개_열쇠가_바뀔_때만_한_번() {
        compose.mainClock.autoAdvance = false
        var key by mutableStateOf<Int?>(null)
        var mood by mutableStateOf(CharacterMood.Working)
        var shown by mutableStateOf(true)
        val handle = StageHandle()
        compose.setContent {
            // 내비게이션 백스택과 같은 꼴: 화면이 빠질 때 저장하고 돌아올 때 복원한다(SaveableStateHolder).
            val holder = rememberSaveableStateHolder()
            if (shown) holder.SaveableStateProvider("stage") {
                AingTheme(dark = true) { AingStage(CharacterCatalog.goldAingID, mood, revealKey = key, assets = assets, clock = clock, handle = handle) }
            }
        }
        awaitLive(handle)
        frames(100)
        assertEquals(0, handle.director!!.reveals)
        key = 1
        awaitReveals(handle, 1)
        assertEquals(1, handle.director!!.reveals)
        assertEquals(StagePolicy.REVEAL_REACTION, handle.director!!.player.activeReaction)
        mood = CharacterMood.Off // 다른 상태가 바뀌어도(다시 그림) 같은 열쇠는 다시 하지 않는다
        frames(1200)
        assertEquals(1, handle.director!!.reveals)
        // 화면을 뺐다가 다시 세운다(백스택 복귀 — 저장 상태 복원): 새 감독이 서도 이미 한 열쇠는 다시 하지 않는다.
        val before = handle.director
        shown = false
        frames(100)
        handle.lastFrame = null
        shown = true
        awaitLive(handle)
        frames(100)
        assertTrue(handle.director !== before, "복원 뒤 새 감독이어야 한다")
        assertEquals(0, handle.director!!.reveals, "복원 뒤 같은 열쇠(1)로 공개를 되풀이했다")
        key = 2
        awaitReveals(handle, 1)
        assertEquals(1, handle.director!!.reveals)
    }

    @Test
    fun 화면이_멈추면_장면_시계도_멈춘다() {
        compose.mainClock.autoAdvance = false
        val owner = object : LifecycleOwner {
            val registry = LifecycleRegistry.createUnsafe(this).apply { currentState = Lifecycle.State.RESUMED }
            override val lifecycle: Lifecycle get() = registry
        }
        val handle = StageHandle()
        compose.setContent {
            CompositionLocalProvider(LocalLifecycleOwner provides owner) {
                AingTheme(dark = false) { AingStage(CharacterCatalog.rainbowAingID, null, assets = assets, clock = clock, handle = handle) }
            }
        }
        awaitLive(handle)
        frames(100)
        assertTrue(!handle.director!!.isSuspended)
        val published = handle.framesPublished
        owner.registry.currentState = Lifecycle.State.STARTED // ON_PAUSE
        frames(100)
        assertTrue(handle.director!!.isSuspended)
        val scene = handle.director!!.player.sceneTime(clock.now())
        val stillPublished = handle.framesPublished
        frames(2000)
        assertEquals(scene, handle.director!!.player.sceneTime(clock.now()), "정지 중 장면 시계")
        assertEquals(stillPublished, handle.framesPublished, "정지 중 그리지 않는다")
        owner.registry.currentState = Lifecycle.State.RESUMED
        frames(400)
        assertTrue(!handle.director!!.isSuspended)
        assertTrue(handle.framesPublished > stillPublished && stillPublished >= published)
    }

    @Test
    fun 유휴는_초당_6장_안팎으로만_내보낸다() {
        compose.mainClock.autoAdvance = false
        val handle = StageHandle()
        compose.setContent { AingTheme(dark = false) { AingStage(CharacterCatalog.builtInAingID, null, assets = assets, clock = clock, handle = handle) } }
        awaitLive(handle)
        frames(300)
        // 깜빡임이 끼지 않는 2초 구간(첫 깜빡임은 무대가 선 뒤 3초 이후 — 그 전에 끝나는 구간만 센다).
        val firstBlink = handle.director!!.nextBlinkTime
        val start = handle.framesPublished
        frames(2000)
        val n = handle.framesPublished - start
        println("AINGCHECK-W5C-FPS 유휴 2초 내보낸 프레임 $n (첫 깜빡임 ${"%.2f".format(firstBlink)} · 지금 ${"%.2f".format(clock.now())})")
        assertTrue(firstBlink > clock.now(), "구간 안에 깜빡임이 끼었다 — 구간을 줄여라")
        // 유휴 6fps = 60Hz 에서 10 vsync 마다(2초 12장). 0.25px 미만 이동은 다시 그리지 않아(F §5.4) 그보다 적을 수 있다. 활성 30fps(60장)와 갈린다.
        assertTrue(n in 6..14, "유휴 2초 프레임 $n")
        // 같은 무대를 두드리면 활성 30fps 로 오른다(같은 2초 창 기준 hit 0.6s 동안 약 18장).
        val beforeTap = handle.framesPublished
        compose.onNodeWithTag(STAGE_LIVE_TAG).performTouchInput { click(handle.toNode(137.5, 137.5)) }
        compose.waitForIdle()
        frames(600)
        val active = handle.framesPublished - beforeTap
        println("AINGCHECK-W5C-FPS hit 0.6초 내보낸 프레임 $active")
        assertTrue(active >= 12, "hit 동안 활성 fps: $active")
    }

    @Test
    fun 틀은_초상과_같은_비율로_몸을_앉힌다() {
        // 앱 Canvas 와 같은 그리기 함수(drawStageFrame)로 132dp(xhdpi 264px) 그림 칸에 정면 idle 을 그려 몸 알파 상자를 잰다.
        val files = StageBundleFiles.Files(StageBundleFiles.bundle())
        val st = StageAssets(files)
        val lib = st.libraryOrNull()!!
        val store = st.acquire(lib.finish(CharacterCatalog.builtInAingID)!!)!!
        try {
            val side = 264.0
            val p = StageFraming.place(18.0, 40.0, side)
            val d = StageDirector(lib, store.finish, 10.0)
            val frame = d.frame(10.0, p.viewportWidth, p.viewportHeight)!!
            val img = ImageBitmap(300, 330)
            CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, androidx.compose.ui.graphics.Canvas(img), Size(300f, 330f)) {
                drawStageFrame(frame, p.originX, p.originY, store)
            }
            val bmp = img.asAndroidBitmap()
            val px = IntArray(300 * 330).also { bmp.getPixels(it, 0, 300, 0, 0, 300, 330) }
            var minX = 300; var maxX = -1; var maxY = -1
            for (y in 0 until 330) for (x in 0 until 300) if ((px[y * 300 + x] ushr 24) > 0) { minX = minOf(minX, x); maxX = maxOf(maxX, x); maxY = maxOf(maxY, y) }
            // 초상(192px) 알파 상자 x 14–178 · 바닥 173 을 264px 칸으로: x 19.3–244.8 · 바닥 237.9 (칸 원점 (18, 40)).
            val tol = side * 0.04
            println("AINGCHECK-W5C-FRAMING 몸 상자 x $minX–$maxX 바닥 $maxY (기대 ${18 + 19.3}–${18 + 244.8} 바닥 ${40 + 237.9})")
            assertTrue(abs(minX - (18 + 19.3)) <= tol && abs(maxX - (18 + 244.8)) <= tol, "몸 가로: $minX–$maxX")
            assertTrue(abs(maxY - (40 + 237.9)) <= tol, "몸 바닥: $maxY")
            save(bmp, "framing-aing-264.png")
        } finally {
            st.release(store)
            st.trim()
        }
        assertNull(st.heldStores()[CharacterCatalog.builtInAingID], "쓰는 화면이 없으면 닫힌다")
    }

    @Test
    fun 저장소는_마감마다_하나_쓰지_않으면_마지막_하나만_남긴다() {
        val st = StageAssets(StageBundleFiles.Files(StageBundleFiles.bundle()))
        val lib = st.libraryOrNull()!!
        val a = st.acquire(lib.finish(CharacterCatalog.builtInAingID)!!)!!
        val a2 = st.acquire(lib.finish(CharacterCatalog.builtInAingID)!!)!!
        assertTrue(a === a2)
        assertEquals(mapOf(CharacterCatalog.builtInAingID to 2), st.heldStores())
        val g = st.acquire(lib.finish(CharacterCatalog.goldAingID)!!)!!
        st.release(a); st.release(a2)
        assertEquals(mapOf(CharacterCatalog.builtInAingID to 0, CharacterCatalog.goldAingID to 1), st.heldStores())
        st.release(g)
        // 둘 다 쉬면 가장 최근(황금) 하나만 남는다.
        assertEquals(mapOf(CharacterCatalog.goldAingID to 0), st.heldStores())
        st.trim()
        assertEquals(emptyMap(), st.heldStores())
        assertNotNull(lib.finish(CharacterCatalog.rainbowAingID))
    }
}
