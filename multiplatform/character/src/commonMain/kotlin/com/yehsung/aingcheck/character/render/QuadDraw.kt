// 원본: 없음 (설계 F §5.1 QuadDraw(expect) — Android `Matrix.setPolyToPoly` 4점 / 데스크톱 Skia `Matrix33`(원근 항 포함). K10: 출력은 Skia 래스터 표면)
package com.yehsung.aingcheck.character.render

import com.yehsung.aingcheck.character.bake.PixelRect
import com.yehsung.aingcheck.character.math.Homography
import com.yehsung.aingcheck.character.math.Vec2

/** 플랫폼 그림 한 장(데스크톱 Skia `Image` · Android `Bitmap`). 메모리는 프리멀티. */
interface DrawableImage {
    val width: Int
    val height: Int
    fun close()
}

/** 원근 사각형 그리기 하나만 아는 표면(F §5.1). 칸 · 패치 · 후광 · 스프라이트가 **같은 그리기 함수 하나**를 지난다. */
interface QuadCanvas {
    /**
     * [image] 의 [srcRect](그림 좌표)를 [srcToDst](그림 연속 좌표 → 표면 픽셀) 원근 사상으로 src-over 한다.
     * 사각형 밖 텍셀은 읽지 않는다(이웃 칸 · 매크로블록 번짐 차단 — Skia `strict` · Android 잘라 낸 사본).
     * @param linear false 면 최근접(픽셀아트 스프라이트).
     * @param alpha 전체 불투명도 0..1(💤 글리프 페이드).
     */
    fun drawImageQuad(image: DrawableImage, srcRect: PixelRect, srcToDst: Homography, linear: Boolean = true, alpha: Float = 1f)

    /**
     * 단색 사각형(입자 — SceneKit 기본 입자 그림 없음 = 채운 판). [color] 는 **직선** sRGB ARGB(0xAARRGGBB).
     * @param additive 참이면 더하기 섞기(스파크 · 보상 흡수), 거짓이면 src-over(색종이).
     */
    fun fillQuad(quad: List<Vec2>, color: Int, additive: Boolean)
}

/** 오프스크린 래스터 표면(창 없음). 시험 · 오버레이 표면 · Android 미리보기 비트맵. */
interface RasterSurface : QuadCanvas {
    val width: Int
    val height: Int
    fun clear()
    /** 표면 바이트(프리멀티 RGBA8, 행 0 = 위). */
    fun readPixels(): RgbaImage
    fun close()
}

/** 그림 만들기 · 디코드 입구. 구운 페이지는 **곱하지 않고** 디코드해 프리멀티 표면에 그대로 넘긴다(G §8-12). */
interface RasterFactory {
    /** 이미 프리멀티인 바이트 → 그림(복사). Android: premultiplied Bitmap 에 `copyPixelsFromBuffer`. */
    fun imageFromPremultiplied(rgba: RgbaImage): DrawableImage

    /** 보통 그림(PNG · 직선 알파) → 그림. 디코더가 알파를 곱한다(후광 원본 PNG · legacy 스프라이트). */
    fun decodeStraight(encoded: ByteArray): DrawableImage

    /**
     * 곱하지 않고 디코드한 바이트 그대로(RGBA8). 구운 페이지 · 💤 글리프 · 골든은 이 바이트가 **이미 프리멀티**다 —
     * 결과는 `premultiplied = false` 로 표시해 돌려주고, 해석은 호출부(역할별 알파 표 `bake.alpha`)가 정한다.
     */
    fun decodeRaw(encoded: ByteArray): RgbaImage

    fun newSurface(width: Int, height: Int): RasterSurface
}

/** 플랫폼 래스터(데스크톱 Skia · Android Canvas). */
expect object PlatformRaster : RasterFactory

/** CPU 경로 래스터 — 디코드만 [decoder] 에 맡기고 그리기는 [CpuWarp]. */
class CpuRaster(private val decoder: RasterFactory) : RasterFactory {
    override fun imageFromPremultiplied(rgba: RgbaImage): DrawableImage = CpuImage(rgba)
    override fun decodeStraight(encoded: ByteArray): DrawableImage = CpuImage(decoder.decodeRaw(encoded).toPremultiplied())
    override fun decodeRaw(encoded: ByteArray): RgbaImage = decoder.decodeRaw(encoded)
    override fun newSurface(width: Int, height: Int): RasterSurface = CpuSurface(width, height)
}

/** 곱하지 않고 디코드한 구운 바이트를 "프리멀티로 읽는다"로 다시 표시한다(바이트는 그대로). */
fun RgbaImage.asPremultiplied(): RgbaImage = if (premultiplied) this else RgbaImage(width, height, px, true)

/** CPU 경로 표면 — F-1(원근 그리기)이 실패한 플랫폼의 대안이자 시험의 독립 기준. */
class CpuSurface(override val width: Int, override val height: Int) : RasterSurface {
    var image: RgbaImage = RgbaImage.transparent(width, height)
        private set

    override fun clear() { image = RgbaImage.transparent(width, height) }
    override fun readPixels(): RgbaImage = RgbaImage(width, height, image.px.copyOf(), true)
    override fun close() {}

    override fun drawImageQuad(image: DrawableImage, srcRect: PixelRect, srcToDst: Homography, linear: Boolean, alpha: Float) {
        val cpu = image as? CpuImage ?: error("CPU 표면에는 CpuImage 만 그린다")
        CpuWarp.drawQuad(this.image, cpu.rgba, srcRect, srcToDst, linear, alpha)
    }

    override fun fillQuad(quad: List<Vec2>, color: Int, additive: Boolean) = CpuWarp.fillQuad(image, quad, color, additive)
}

/** CPU 경로 그림(프리멀티 바이트). */
class CpuImage(val rgba: RgbaImage) : DrawableImage {
    init {
        require(rgba.premultiplied) { "CpuImage 는 프리멀티다" }
    }
    override val width: Int get() = rgba.width
    override val height: Int get() = rgba.height
    override fun close() {}
}

/** Compose 캔버스(`DrawScope.drawIntoCanvas { … }`) → 원근 사각형 표면. 데스크톱 = Skia `nativeCanvas`, Android = HWUI `nativeCanvas`. */
expect fun quadCanvasOf(canvas: androidx.compose.ui.graphics.Canvas): QuadCanvas
