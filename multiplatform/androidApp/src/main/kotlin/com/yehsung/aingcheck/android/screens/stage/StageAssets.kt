// 원본: 없음 (G §8-12 Android 기본 묶음 · F §4 디코드 메모리 — 앱 자산(APK assets/aing-bake/)에서 구운 아잉이를 읽는 입구와 그림 저장소 수명)
package com.yehsung.aingcheck.android.screens.stage

import android.content.Context
import android.content.res.AssetManager
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.yehsung.aingcheck.character.bake.BakeFiles
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.bake.BakedFinish
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.character.render.RasterFactory
import java.io.IOException
import kotlin.math.abs

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

/**
 * 마감 하나의 그림 저장소(재생기 [BakeImageStore] — 페이지 디코드 · 클램프 · 칸 · 마스크 · 후광). 저장소는 스레드 안전하지 않다:
 * 데움(배경)과 그리기 · 탭 판정(주 스레드)이 모두 [lock] 을 잡는다. 화면에 내놓는 것은 데움이 끝난 뒤라 주 스레드가 기다릴 일은 없다.
 */
class StageStore internal constructor(val finish: BakedFinish, val images: BakeImageStore) {
    val lock = Any()
    internal var refs = 0

    /**
     * 데움: 이 단(L)의 칸이 쓰는 페이지를 풀고, 무대가 실제로 쓰는 칸(살랑 ±8° · 인사 · hit 가 닿는 정면 근처 |요| ≤ 9°)의 뜬 눈 · 감은 눈 그림과
     * 정면 후광을 미리 만든다 — 첫 프레임에 주 스레드가 2048×2448 페이지를 풀지 않게.
     * @return 미리 만든 칸 그림 수.
     */
    fun prewarm(tierName: String = "L", yawLimitDeg: Int = 9): Int = synchronized(lock) {
        val cells = finish.cells(tierName)?.cells ?: return 0
        var made = 0
        for (cell in cells) {
            if (abs(cell.yawDeg) > yawLimitDeg) continue
            images.cellImage(cell, closedEyes = false); made++
            if (cell.closedPatch != null) { images.cellImage(cell, closedEyes = true); made++ }
        }
        if (finish.bake.halo != null) for (i in listOf(0, 1, 35)) images.haloImage(i)
        made
    }
}

/**
 * 무대 자산 창구(프로세스에 하나 — [StageAssets.of]). 라이브러리(카메라 · 모션 · 칸 표 · 트랙)는 한 번 읽고, 그림 저장소는 **마감마다
 * 필요한 동안만** 쥔다: 페이지 두 장(L 쉬는 행 2048×2448 + 감은 눈 패치 2032×2048)이 약 37MB 라 여러 마감을 함께 쥐지 않는다.
 * 쓰는 화면이 없어진 저장소는 마지막 하나만 남겨(나 탭 ↔ 고르기 왕복에서 다시 풀지 않게) 나머지를 닫고, 앱이 뒤로 가면 그것도 닫는다.
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

    val failureReason: String? get() = synchronized(this) { failure }

    /** 그 마감의 저장소를 빌린다(배경 스레드 — 처음이면 데움까지). [release] 와 짝. */
    fun acquire(finish: BakedFinish, tierName: String = "L"): StageStore {
        val store = synchronized(this) {
            stores.remove(finish.characterId)?.also { stores[finish.characterId] = it }
                ?: StageStore(finish, BakeImageStore(finish, files, raster)).also { stores[finish.characterId] = it }
        }
        synchronized(this) { store.refs++ }
        store.prewarm(tierName)
        return store
    }

    fun release(store: StageStore) {
        val closing = synchronized(this) {
            store.refs = (store.refs - 1).coerceAtLeast(0)
            // 쓰는 화면이 없는 저장소 가운데 가장 최근 것(맨 뒤) 하나만 남긴다.
            val idle = stores.values.filter { it.refs == 0 }
            val keep = idle.lastOrNull()
            idle.filter { it !== keep }.onEach { stores.remove(it.finish.characterId) }
        }
        closing.forEach { synchronized(it.lock) { it.images.close() } }
    }

    /** 앱이 뒤로 갔다 — 쓰는 화면이 없는 저장소를 모두 닫는다. */
    fun trim() {
        val closing = synchronized(this) {
            stores.values.filter { it.refs == 0 }.onEach { stores.remove(it.finish.characterId) }
        }
        closing.forEach { synchronized(it.lock) { it.images.close() } }
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
