// 원본: 없음 (설계 F §4 디코드 메모리 · LRU — S 칸 196×182×4 ≈ 143KB, LRU 96칸 ≈ 13.7MB)
package com.yehsung.aingcheck.character.render

import com.yehsung.aingcheck.character.bake.BakeCell
import com.yehsung.aingcheck.character.bake.BakeFiles
import com.yehsung.aingcheck.character.bake.BakedFinish
import com.yehsung.aingcheck.character.bake.PixelRect
import com.yehsung.aingcheck.character.sprite.SpriteAlphaMask

/** 아주 작은 LRU(접근 순서). 공용 코드라 java.util.LinkedHashMap(accessOrder) 를 못 쓴다. */
internal class Lru<K, V>(private val capacity: Int, private val evicted: (V) -> Unit = {}) {
    private val map = HashMap<K, V>()
    private val order = ArrayDeque<K>()

    fun get(key: K): V? {
        val v = map[key] ?: return null
        order.remove(key); order.addLast(key)
        return v
    }

    fun put(key: K, value: V) {
        map.put(key, value)?.let { old -> if (old !== value) evicted(old) }
        order.remove(key); order.addLast(key)
        while (order.size > capacity) {
            val k = order.removeFirst()
            map.remove(k)?.let(evicted)
        }
    }

    fun clear() {
        map.values.forEach(evicted)
        map.clear(); order.clear()
    }

    val size: Int get() = map.size
}

/**
 * 마감 하나의 그림 저장소: 페이지 디코드(곱하지 않고) → 클램프 → 칸 잘라 내기(감은 눈은 패치를 칸 좌표에 덮어쓴 사본) → 플랫폼 그림.
 * 칸 그림은 **칸 크기 한 장**이라 그리기 쪽 원본 사각형 = (0, 0, w, h), 좌표 = 칸 국소 픽셀(정합 H 의 입력)과 같다.
 */
class BakeImageStore(
    private val finish: BakedFinish,
    private val files: BakeFiles,
    private val raster: RasterFactory,
    pageCapacity: Int = 2,
    cellCapacity: Int = 128,
) {
    private val pages = Lru<Int, RgbaImage>(pageCapacity)
    private val cells = Lru<String, DrawableImage>(cellCapacity) { it.close() }
    private val halos = HashMap<Int, DrawableImage?>()

    /** 페이지를 디코드한 횟수(진단 · 시험). */
    var pageDecodes: Int = 0
        private set

    /** 클램프가 바꾼 채널 수 누계(진단). */
    var clampedChannels: Long = 0
        private set

    fun page(index: Int): RgbaImage {
        pages.get(index)?.let { return it }
        val bytes = files.read(finish.pagePath(index)) ?: error("페이지가 없다: ${finish.pagePath(index)}")
        val raw = raster.decodeRaw(bytes).asPremultiplied()
        clampedChannels += DecodeClamp.applyInPlace(raw, finish.bake.clamp)
        pageDecodes++
        pages.put(index, raw)
        return raw
    }

    /** 칸 바이트(프리멀티, 칸 크기). */
    fun cellRgba(cell: BakeCell, closedEyes: Boolean): RgbaImage {
        val open = page(cell.page).crop(cell.rect)
        if (!closedEyes) return open
        val patch = cell.closedPatch ?: return open
        val p = page(patch.page).crop(patch.rect)
        return open.overwritten(p, patch.atX, patch.atY)
    }

    fun cellImage(cell: BakeCell, closedEyes: Boolean): DrawableImage {
        val key = if (closedEyes && cell.closedPatch != null) "${cell.id}#closed" else cell.id
        cells.get(key)?.let { return it }
        val img = raster.imageFromPremultiplied(cellRgba(cell, closedEyes))
        cells.put(key, img)
        return img
    }

    private val masks = Lru<String, SpriteAlphaMask>(cellCapacity)

    /** 칸 알파 마스크(임계 32 — 스프라이트와 같은 판정, F §5.3). 클릭 판정용. */
    fun cellMask(cell: BakeCell, closedEyes: Boolean): SpriteAlphaMask {
        val key = if (closedEyes && cell.closedPatch != null) "${cell.id}#closed" else cell.id
        masks.get(key)?.let { return it }
        val m = SpriteAlphaMask.of(cellRgba(cell, closedEyes)) ?: error("칸 마스크를 못 굽는다: ${cell.id}")
        masks.put(key, m)
        return m
    }

    /** 후광 칸 그림(원본 PNG — 직선 알파, 디코더가 곱한다). 빠진 칸은 정면(0)으로 접는다(맥 `compensatedHaloCells` 와 같은 규칙). */
    fun haloImage(index: Int): DrawableImage? {
        val halo = finish.bake.halo ?: return null
        halos[index]?.let { return it }
        if (halos.containsKey(index)) return if (index == 0) null else haloImage(0)
        val bytes = halo.cellFiles.getOrNull(index)?.let(files::readHalo)
        val img = bytes?.let(raster::decodeStraight)
        halos[index] = img
        return img ?: if (index == 0) null else haloImage(0)
    }

    fun close() {
        cells.clear(); pages.clear(); masks.clear()
        halos.values.forEach { it?.close() }
        halos.clear()
    }

    companion object {
        fun full(image: DrawableImage) = PixelRect(0, 0, image.width, image.height)
    }
}
