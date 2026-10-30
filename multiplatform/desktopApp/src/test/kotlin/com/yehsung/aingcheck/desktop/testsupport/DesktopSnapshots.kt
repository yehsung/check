// 임시 사본 — 공용 패치 7 때 지움(W-windows-resume W-3 #19 · W-1 8③: testkit 으로 옮기면 이 파일을 지우고 import 를 바꾼다).
// 원본: multiplatform/ui/src/desktopTest/kotlin/com/yehsung/aingcheck/ui/components/DesktopSnapshots.kt @ c4e0ebfc — ui 원본은 건드리지 않는다. 패키지만 desktop.testsupport 로 바꿨다.
// 원본: 없음 — 데스크톱 스냅숏 하네스(시험 도구).
//
// 데스크톱 스냅숏 하네스: ImageComposeScene(오프스크린, java.awt.headless=true) 로 그리고 Skia 로 PNG 를 읽고 쓴다.
package com.yehsung.aingcheck.desktop.testsupport

import androidx.compose.runtime.Composable
import com.yehsung.aingcheck.ui.components.CharacterExpression
import com.yehsung.aingcheck.ui.components.CharacterStageMetrics
import com.yehsung.aingcheck.ui.components.GalleryArt
import com.yehsung.aingcheck.ui.components.RubyGlyph
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.unit.Density
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image
import org.jetbrains.skia.ImageInfo
import java.io.File

object DesktopSnapshots {
    const val DENSITY = 2f

    val mpRoot: File get() = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 없음 — Gradle 시험 작업으로 돌린다" })
    val repoRoot: File get() = File(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 없음" })

    fun golden(group: String, name: String): File = File(mpRoot, "ui/snapshots/$group/desktop/$name.png")
    fun outDir(): File = File(mpRoot, "ui/build/aingcheck-snapshots/desktop").apply { mkdirs() }

    /** 저장소 원본 그림(PNG) — git 사본이 아니라 맥 원본을 제자리에서 읽는다. */
    fun repoImage(path: String): ImageBitmap {
        val file = File(repoRoot, path)
        require(file.isFile) { "원본 그림이 없다: $file" }
        return Image.makeFromEncoded(file.readBytes()).toComposeImageBitmap()
    }

    fun galleryArt(): GalleryArt {
        val stagePath = if (CharacterStageMetrics.prefersStageArt("fox", CharacterExpression.Neutral, 120f, DENSITY))
            "Sources/CheckMobileKit/Resources/Art/stage-fox-neutral.png" else "Sources/check/Characters/fox/portrait-neutral.png"
        return GalleryArt(
            portraitNeutral = repoImage("Sources/check/Characters/fox/portrait-neutral.png"),
            portraitNegative = repoImage("Sources/check/Characters/fox/portrait-negative.png"),
            stage = repoImage(stagePath),
            ruby = repoImage("Sources/CheckMobileKit/Resources/Art/${RubyGlyph.assetName(24f, DENSITY)}.png"),
        )
    }

    /** 새 장면을 만들어 [frames] 번 그리고 마지막 장을 돌려준다(리소스 글꼴이 늦게 오면 다음 장에 반영된다). */
    @OptIn(ExperimentalComposeUiApi::class)
    fun render(widthDp: Int, heightDp: Int, frames: Int = 3, content: @Composable () -> Unit): PixelImage {
        val w = (widthDp * DENSITY).toInt()
        val h = (heightDp * DENSITY).toInt()
        val scene = ImageComposeScene(width = w, height = h, density = Density(DENSITY), content = content)
        try {
            var image: Image? = null
            for (i in 0 until frames) {
                image?.close()
                image = scene.render(i * 16_666_667L)
            }
            val bitmap = Bitmap.makeFromImage(requireNotNull(image))
            val pixels = IntArray(w * h)
            for (y in 0 until h) for (x in 0 until w) pixels[y * w + x] = bitmap.getColor(x, y)
            bitmap.close()
            image.close()
            return PixelImage(w, h, pixels)
        } finally {
            scene.close()
        }
    }

    fun readPng(file: File): PixelImage {
        val image = Image.makeFromEncoded(file.readBytes())
        val bitmap = Bitmap.makeFromImage(image)
        val pixels = IntArray(bitmap.width * bitmap.height)
        for (y in 0 until bitmap.height) for (x in 0 until bitmap.width) pixels[y * bitmap.width + x] = bitmap.getColor(x, y)
        val out = PixelImage(bitmap.width, bitmap.height, pixels)
        bitmap.close()
        image.close()
        return out
    }

    fun writePng(image: PixelImage, file: File) {
        file.parentFile.mkdirs()
        val bitmap = Bitmap()
        bitmap.allocPixels(ImageInfo(image.width, image.height, ColorType.BGRA_8888, ColorAlphaType.UNPREMUL))
        val bytes = ByteArray(image.argb.size * 4)
        for (i in image.argb.indices) {
            val c = image.argb[i]
            bytes[i * 4] = (c and 0xFF).toByte()
            bytes[i * 4 + 1] = ((c ushr 8) and 0xFF).toByte()
            bytes[i * 4 + 2] = ((c ushr 16) and 0xFF).toByte()
            bytes[i * 4 + 3] = ((c ushr 24) and 0xFF).toByte()
        }
        bitmap.installPixels(bytes)
        val png = requireNotNull(Image.makeFromBitmap(bitmap).encodeToData(EncodedImageFormat.PNG)) { "PNG 인코딩 실패" }
        file.writeBytes(png.bytes)
        bitmap.close()
    }

    fun recording(): Boolean = System.getenv(SnapshotCompare.RECORD_ENV) == "1"
}
