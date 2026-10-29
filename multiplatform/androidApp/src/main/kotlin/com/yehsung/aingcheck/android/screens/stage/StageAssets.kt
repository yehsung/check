// 원본: 없음 (G §8-12 Android 기본 묶음 · F §4 디코드 메모리 — 앱 자산(APK assets/aing-bake/)에서 구운 아잉이를 읽는 입구와 칸 그림 수명)
package com.yehsung.aingcheck.android.screens.stage

import android.content.Context
import android.content.res.AssetManager
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.yehsung.aingcheck.character.bake.BakeCell
import com.yehsung.aingcheck.character.bake.BakeFiles
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.bake.BakedFinish
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.DrawableImage
import com.yehsung.aingcheck.character.render.ImpostorRenderer
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.character.render.QuadCanvas
import com.yehsung.aingcheck.character.render.RasterFactory
import com.yehsung.aingcheck.character.render.RgbaImage
import com.yehsung.aingcheck.character.sprite.SpriteAlphaMask
import java.io.IOException
import kotlin.math.abs
import kotlin.math.floor

/**
 * APK 자산의 구운 묶음. 조립 빌드(조정자 패치 01 — androidApp/build.gradle.kts)가 `bundles.androidDefault`(scripts/bake-aing/config.json)
 * 대로 고른 파일을 `assets/aing-bake/`(굽기 뿌리 상대 경로 그대로)에, 후광 원본 PNG 를 `assets/aing-bake/halo/` 에 싣는다(git 사본 0).
 * 없는 파일은 null — 묶음마다 싣는 파일이 다르다(L 단 · hit · greeting 트랙만).
 */
class AssetBakeFiles(private val assets: AssetManager, private val root: String = ROOT) : BakeFiles {
    override fun read(path: String): ByteArray? = open("$root/$path")

    override fun readHalo(fileName: String): ByteArray? = open("$root/$HALO_DIR/$fileName")

    private fun open(path: String): ByteArray? = try {
        assets.open(path).use { it.readBytes() }
    } catch (_: IOException) {
        null
    }

    companion object {
        const val ROOT = "aing-bake"
        const val HALO_DIR = "halo"
    }
}

/** 칸 하나의 그림(플랫폼 그림 — 프리멀티)과 클릭 마스크(알파 > 32). */
class StageCellArt(val image: DrawableImage, val mask: SpriteAlphaMask)

/**
 * 마감 하나의 무대 칸 그림. 재생기 [BakeImageStore] 는 페이지(L 쉬는 행 2048×2448 ≈ 20MB · 감은 눈 패치 2032×2048 ≈ 16.6MB, 자바 힙)를
 * 쥔 채 칸을 잘라 내는데, 무대는 정면 근처 칸만 쓰므로 **칸을 다 구운 뒤 페이지를 놓는다**(48MB 힙 API 26 에뮬레이터에서 두 페이지를 쥐면
 * OutOfMemoryError — 실측). 칸 바이트는 재생기 그대로다: 뜬 눈 = `BakeImageStore.cellRgba(cell, false)`(페이지 디코드 · 클램프 · 자르기),
 * 감은 눈 = 그 위에 패치 사각형 덮어쓰기(`cellRgba(cell, true)` 와 같은 식) — 같음은 시험(StageStoreContractTest)이 바이트로 잰다.
 * 그리기 · 클릭 판정도 재생기와 같은 식([ImpostorRenderer] 후광 → 몸 칸, CharacterFrames.hitTest 의 구운 갈래)이고 같음을 시험이 잰다.
 * 스레드 안전하지 않다 — 데움(배경)과 그리기 · 탭(주 스레드)이 모두 [lock] 을 잡는다. 화면에는 데움이 끝난 뒤에만 내놓는다.
 */
class StageStore internal constructor(
    val finish: BakedFinish,
    private val files: BakeFiles,
    private val raster: RasterFactory,
    val tierName: String = "L",
) {
    val lock = Any()
    internal var refs = 0
    private val cells = HashMap<String, StageCellArt>()

    /** 후광 칸(원본 PNG — 페이지와 무관). 재생기 저장소를 후광에만 쓴다(페이지를 풀지 않는다). */
    private val halos = BakeImageStore(finish, files, raster, pageCapacity = 1, cellCapacity = 1)

    /** 페이지를 디코드한 횟수 누계(시험 · 진단 — 데움 한 번에 페이지마다 1). */
    var pageDecodes: Int = 0
        private set

    val cellCount: Int get() = cells.size

    private fun key(cell: BakeCell, closed: Boolean) = if (closed) "${cell.id}#closed" else cell.id

    private fun put(key: String, rgba: RgbaImage) {
        val mask = SpriteAlphaMask.of(rgba) ?: error("칸 마스크를 못 굽는다: $key")
        cells[key] = StageCellArt(raster.imageFromPremultiplied(rgba), mask)
    }

    /**
     * 칸 무리를 굽는다: 페이지 차례로 뜬 눈 칸을 자르고(쉬는 행 페이지), 그다음 패치 페이지로 감은 눈 칸을 덮어쓴다 — 페이지는 한 번에 하나만
     * 쥐고(임시 저장소 pageCapacity 1) 끝나면 놓는다. 이미 구운 칸은 건너뛴다.
     * @return 새로 구운 칸 그림 수.
     */
    fun bake(wanted: List<BakeCell>): Int {
        val missing = wanted.filter { c -> key(c, false) !in cells || (c.closedPatch != null && key(c, true) !in cells) }
        if (missing.isEmpty()) return 0
        val before = cells.size
        // 두 단계 — 쉬는 행 페이지를 놓은 뒤에 패치 페이지를 푼다(같은 저장소에서 이어 풀면 새 페이지를 디코드하는 동안 옛 페이지가
        // 아직 살아 있어 두 장이 겹친다: 20MB + 16.6MB). 단계 사이에는 뜬 눈 칸 바이트(정면 근처 19칸 ≈ 4.9MB)만 쥔다.
        val open = LinkedHashMap<String, RgbaImage>()
        val restPhase = BakeImageStore(finish, files, raster, pageCapacity = 1, cellCapacity = 1)
        try {
            for (cell in missing.sortedBy { it.page }) {
                val rgba = restPhase.cellRgba(cell, closedEyes = false)
                open[cell.id] = rgba
                if (key(cell, false) !in cells) put(key(cell, false), rgba)
            }
            pageDecodes += restPhase.pageDecodes
        } finally {
            restPhase.close()
        }
        val patched = missing.filter { it.closedPatch != null }
        if (patched.isNotEmpty()) {
            val patchPhase = BakeImageStore(finish, files, raster, pageCapacity = 1, cellCapacity = 1)
            try {
                for (cell in patched.sortedBy { it.closedPatch!!.page }) {
                    val patch = cell.closedPatch!!
                    val closed = open.getValue(cell.id).overwritten(patchPhase.page(patch.page).crop(patch.rect), patch.atX, patch.atY)
                    put(key(cell, true), closed)
                }
                pageDecodes += patchPhase.pageDecodes
            } finally {
                patchPhase.close()
            }
        }
        return cells.size - before
    }

    /**
     * 데움: 무대가 실제로 쓰는 칸(살랑 ±8° · hit · 인사가 닿는 정면 근처 |요| ≤ 9°)의 뜬 눈 · 감은 눈과 정면 후광. 그 밖의 칸이 필요하면
     * 그때 [cellArt] 가 페이지를 다시 푼다(무대에서는 생기지 않는다 — 돌아보지 않는다).
     */
    fun prewarm(yawLimitDeg: Int = 9): Int = synchronized(lock) {
        val all = finish.cells(tierName)?.cells ?: return 0
        val made = bake(all.filter { abs(it.yawDeg) <= yawLimitDeg })
        if (finish.bake.halo != null) for (i in listOf(0, 1, 35)) halos.haloImage(i)
        made
    }

    /** 칸 그림(없으면 그 칸만 굽는다). 감은 눈인데 패치가 없는 칸은 뜬 눈(재생기 cellImage 와 같은 규칙). */
    fun cellArt(cell: BakeCell, closedEyes: Boolean): StageCellArt {
        val closed = closedEyes && cell.closedPatch != null
        cells[key(cell, closed)]?.let { return it }
        bake(listOf(cell))
        return cells.getValue(key(cell, closed))
    }

    /** 재생기 `ImpostorRenderer.draw` 와 같은 순서 · 같은 사상: 후광(금 · 무지개) → 몸 칸. 스프라이트 프레임은 무대에 없다. */
    fun draw(canvas: QuadCanvas, frame: CharacterFrame) {
        val f = (frame as? CharacterFrame.Impostor)?.frame ?: return
        ImpostorRenderer.drawHalo(canvas, f, halos)
        val art = cellArt(f.placement.cell, f.closedEyes)
        canvas.drawImageQuad(art.image, BakeImageStore.full(art.image), f.placement.cellToViewport)
    }

    /** 몸 클릭 판정(재생기 `CharacterFrames.hitTest` 의 구운 갈래 — F §5.3): 투영 상자 + 여백 → H⁻¹ → 칸 알파 > 32. 후광은 몸이 아니다. */
    fun hitTest(frame: CharacterFrame, point: Vec2, marginPx: Double): Boolean {
        val f = (frame as? CharacterFrame.Impostor)?.frame ?: return false
        val q = frame.viewportQuad
        if (point.x < q.minOf { it.x } - marginPx || point.x > q.maxOf { it.x } + marginPx ||
            point.y < q.minOf { it.y } - marginPx || point.y > q.maxOf { it.y } + marginPx
        ) return false
        val inv = f.placement.cellToViewport.inverse()
        if (inv.denominator(point) <= 0) return false
        val p = inv.map(point)
        return cellArt(f.placement.cell, f.closedEyes).mask.isOpaque(floor(p.x).toInt(), floor(p.y).toInt())
    }

    fun close() {
        cells.values.forEach { it.image.close() }
        cells.clear()
        halos.close()
    }
}

/**
 * 무대 자산 창구(프로세스에 하나 — [StageAssets.of]). 라이브러리(카메라 · 모션 · 칸 표 · 트랙)는 한 번 읽고, 칸 그림은 **마감마다
 * 필요한 동안만** 쥔다(데운 칸 38장 ≈ 10MB 비트맵 + 마스크). 쓰는 화면이 없어진 저장소는 마지막 하나만 남겨(나 탭 ↔ 고르기 왕복에서
 * 다시 굽지 않게) 나머지를 닫고, 앱이 뒤로 가면 그것도 닫는다. 굽다가 메모리가 모자라면(OutOfMemoryError) 그 마감은 초상으로 선다.
 */
class StageAssets(private val files: BakeFiles, private val raster: RasterFactory = PlatformRaster) {
    private var library: BakeLibrary? = null
    private var failure: String? = null
    private val stores = LinkedHashMap<String, StageStore>()

    /** 라이브러리 읽기(배경 스레드에서 부른다). 못 읽으면 null 이고 이유는 [failureReason] — 무대는 초상으로 선다. */
    fun libraryOrNull(): BakeLibrary? = synchronized(this) {
        library?.let { return it }
        if (failure != null) return null
        return try {
            BakeLibrary.load(files).also { library = it }
        } catch (e: Exception) {
            failure = e.message ?: e::class.simpleName
            null
        }
    }

    /** 라이브러리 · 칸 굽기 실패 이유(진단). */
    val failureReason: String? get() = synchronized(this) { failure }

    /**
     * 그 마감의 칸 그림을 빌린다(배경 스레드 — 처음이면 데움까지). [release] 와 짝.
     * 굽다가 메모리가 모자라거나 자산이 깨졌으면 null(빌린 수는 남기지 않는다) — 호출부는 초상으로 선다.
     */
    fun acquire(finish: BakedFinish, tierName: String = "L"): StageStore? {
        val store = synchronized(this) {
            val s = stores.remove(finish.characterId) ?: StageStore(finish, files, raster, tierName)
            stores[finish.characterId] = s
            s.refs++
            s
        }
        val failed: String? = try {
            store.prewarm()
            null
        } catch (e: OutOfMemoryError) {
            "메모리 부족(${finish.characterId}): ${e.message}"
        } catch (e: Exception) {
            "칸 굽기 실패(${finish.characterId}): ${e.message ?: e::class.simpleName}"
        }
        if (failed == null) return store
        synchronized(this) {
            failure = failed
            store.refs = (store.refs - 1).coerceAtLeast(0)
            if (store.refs == 0) stores.remove(finish.characterId)
        }
        if (store.refs == 0) synchronized(store.lock) { store.close() }
        return null
    }

    fun release(store: StageStore) {
        val closing = synchronized(this) {
            store.refs = (store.refs - 1).coerceAtLeast(0)
            // 쓰는 화면이 없는 저장소 가운데 가장 최근 것(맨 뒤) 하나만 남긴다.
            val idle = stores.values.filter { it.refs == 0 }
            val keep = idle.lastOrNull()
            idle.filter { it !== keep }.onEach { stores.remove(it.finish.characterId) }
        }
        closing.forEach { synchronized(it.lock) { it.close() } }
    }

    /** 앱이 뒤로 갔다 — 쓰는 화면이 없는 저장소를 모두 닫는다. */
    fun trim() {
        val closing = synchronized(this) {
            stores.values.filter { it.refs == 0 }.onEach { stores.remove(it.finish.characterId) }
        }
        closing.forEach { synchronized(it.lock) { it.close() } }
    }

    /** 지금 쥔 저장소(마감 서버 id → 빌린 수) — 시험 · 진단. */
    fun heldStores(): Map<String, Int> = synchronized(this) { stores.mapValues { it.value.refs } }

    companion object {
        @Volatile private var shared: StageAssets? = null

        /**
         * 앱 프로세스의 무대 자산(APK assets). 처음 부를 때 프로세스 수명 관찰을 걸어 앱이 뒤로 가면 [trim] 한다.
         * 조립(K11)이 AppContainer 에 옮겨도 이 함수 하나만 바꾸면 된다(assembly.md).
         */
        fun of(context: Context): StageAssets = shared ?: synchronized(this) {
            shared ?: StageAssets(AssetBakeFiles(context.applicationContext.assets)).also { assets ->
                shared = assets
                runCatching {
                    ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
                        override fun onStop(owner: LifecycleOwner) = assets.trim()
                    })
                }
            }
        }
    }
}
