// 원본: 없음 — Android 스냅숏 하네스(시험 도구).
//
// Android(폰) 스냅숏 하네스: Robolectric NATIVE 그래픽 + Compose 시험 규칙으로 그리고 android.graphics 로 PNG 를 읽고 쓴다.
// 배율 2 = xhdpi(시험 클래스의 @Config qualifiers). 에뮬레이터·창 없음.
package com.yehsung.aingcheck.ui.components

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import java.io.File

object AndroidSnapshots {
    const val DENSITY = 2f

    val mpRoot: File get() = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 없음 — Gradle 시험 작업으로 돌린다" })
    val repoRoot: File get() = File(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 없음" })

    fun golden(group: String, name: String): File = File(mpRoot, "ui/snapshots/$group/android/$name.png")
    fun outDir(): File = File(mpRoot, "ui/build/aingcheck-snapshots/android").apply { mkdirs() }

    fun repoImage(path: String): ImageBitmap {
        val file = File(repoRoot, path)
        require(file.isFile) { "원본 그림이 없다: $file" }
        val options = BitmapFactory.Options().apply { inScaled = false; inPreferredConfig = Bitmap.Config.ARGB_8888 }
        return requireNotNull(BitmapFactory.decodeFile(file.path, options)) { "PNG 디코드 실패: $file" }.asImageBitmap()
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

    fun pixels(image: ImageBitmap): PixelImage {
        val bitmap = image.asAndroidBitmap().copy(Bitmap.Config.ARGB_8888, false)
        val out = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(out, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        return PixelImage(bitmap.width, bitmap.height, out)
    }

    fun readPng(file: File): PixelImage {
        val options = BitmapFactory.Options().apply { inScaled = false; inPreferredConfig = Bitmap.Config.ARGB_8888; inPremultiplied = false }
        val bitmap = requireNotNull(BitmapFactory.decodeFile(file.path, options)) { "PNG 디코드 실패: $file" }
        val out = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(out, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        return PixelImage(bitmap.width, bitmap.height, out)
    }

    fun writePng(image: PixelImage, file: File) {
        file.parentFile.mkdirs()
        val bitmap = Bitmap.createBitmap(image.argb, image.width, image.height, Bitmap.Config.ARGB_8888)
        file.outputStream().use { require(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) { "PNG 인코딩 실패" } }
    }

    fun recording(): Boolean = System.getenv(SnapshotCompare.RECORD_ENV) == "1"
}
