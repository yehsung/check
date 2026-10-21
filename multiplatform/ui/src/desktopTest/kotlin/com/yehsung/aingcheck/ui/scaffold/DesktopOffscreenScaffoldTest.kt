package com.yehsung.aingcheck.ui.scaffold

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.v2.runDesktopComposeUiTest
import androidx.compose.ui.unit.Density
import io.github.takahirom.roborazzi.captureRoboImage
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.EncodedImageFormat
import java.awt.GraphicsEnvironment
import java.awt.HeadlessException
import java.io.File
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * A-X6: Compose Desktop 오프스크린 렌더가 `java.awt.headless=true` 에서 돌고, 같은 장면 세 번이 바이트로 같다.
 * 창을 띄울 수 없다는 것은 단언이 아니라 **실행 조건**이다(AWT 창을 만들면 HeadlessException).
 */
class DesktopOffscreenScaffoldTest {
    @Test
    fun headlessIsTheExecutionCondition() {
        assertTrue(GraphicsEnvironment.isHeadless(), "java.awt.headless=true 가 아니다(aingcheck.test-seal)")
        assertFailsWith<HeadlessException> { java.awt.Frame("must-not-open") }
    }

    @OptIn(ExperimentalComposeUiApi::class)
    private fun render(accent: Color = DEFAULT_ACCENT): Pair<ByteArray, Set<Int>> {
        val scene = ImageComposeScene(width = SIDE, height = SIDE, density = Density(2f)) { ScaffoldProbe(accent = accent) }
        try {
            val image = scene.render()
            val png = requireNotNull(image.encodeToData(EncodedImageFormat.PNG)) { "PNG 인코딩 실패" }.bytes
            val bitmap = Bitmap.makeFromImage(image)
            val colors = HashSet<Int>()
            for (y in 0 until bitmap.height) for (x in 0 until bitmap.width) colors += bitmap.getColor(x, y)
            bitmap.close()
            return png to colors
        } finally {
            scene.close()
        }
    }

    @Test
    fun threeOffscreenRendersAreByteIdentical() {
        val renders = List(3) { render() }
        val pngs = renders.map { it.first }
        val digests = pngs.map { sha256(it) }
        // 러너 간 비교용(맥·ubuntu·windows 로그를 대조한다 — 같지 않으면 CI 는 compare 만 한다, A§4-3)
        println("AINGCHECK-AX6 os=${System.getProperty("os.name")} arch=${System.getProperty("os.arch")} sha256=${digests.joinToString(",")} bytes=${pngs.map { it.size }}")
        assertContentEquals(pngs[0], pngs[1], "1장과 2장이 다르다")
        assertContentEquals(pngs[0], pngs[2], "1장과 3장이 다르다")
        // 내용이 실제로 그려졌다: 한 색이 아니고, 장면의 강조색이 픽셀로 있다(아무것도 안 그리면 세 장이 같아도 빈 비교다).
        val colors = renders[0].second
        assertTrue(colors.size >= 3, "렌더가 거의 한 색이다(${colors.size}색) — 장면이 그려지지 않았다")
        assertTrue(DEFAULT_ACCENT.toArgb() in colors, "강조색 픽셀이 없다 — 장면이 그려지지 않았다")
        // 기준선은 다른 입력이어야 한다(기억 comparison-baseline-must-differ): **같은 크기**에 색 하나만 다른 장면은 다른 바이트.
        // (크기만 다른 기준선은 빈 렌더도 바이트가 갈려 초록이 된다 — W0 검증 지적)
        val (otherPng, otherColors) = render(accent = OTHER_ACCENT)
        assertFalse(otherPng.contentEquals(pngs[0]), "같은 크기·다른 색 장면인데 같은 바이트 — 비교가 내용을 못 본다")
        assertTrue(OTHER_ACCENT.toArgb() in otherColors && DEFAULT_ACCENT.toArgb() !in otherColors, "기준선 장면의 색이 바뀌지 않았다")
    }

    @OptIn(ExperimentalTestApi::class)
    @Test
    fun roborazziDesktopCaptureWorksHeadless() = runDesktopComposeUiTest(width = 160, height = 160) {
        setContent { ScaffoldProbe() }
        val out = File(System.getProperty("aingcheck.mpRoot"), "ui/build/aingcheck-scaffold/desktop/scaffold_probe.png")
        onRoot().captureRoboImage(out.path)
        // Roborazzi 는 모드 속성(record·compare·verify)이 없으면 캡처하지 않는다. 기록 작업(recordRoborazziDesktop)일 때만 판정한다.
        if (System.getProperty("roborazzi.test.record") == "true") {
            assertTrue(out.isFile && out.length() > 0, "Roborazzi 데스크톱 기록이 파일을 남기지 않았다: $out")
        }
    }

    private companion object {
        const val SIDE = 160
        val DEFAULT_ACCENT = Color(0xFF6B4EFF)
        val OTHER_ACCENT = Color(0xFF1E9E5A)
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }.take(16)
}
