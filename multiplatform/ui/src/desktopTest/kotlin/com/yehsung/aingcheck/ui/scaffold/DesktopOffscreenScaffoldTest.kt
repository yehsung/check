package com.yehsung.aingcheck.ui.scaffold

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.v2.runDesktopComposeUiTest
import androidx.compose.ui.unit.Density
import io.github.takahirom.roborazzi.captureRoboImage
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
    private fun renderPng(side: Int = 160): ByteArray {
        val scene = ImageComposeScene(width = side, height = side, density = Density(2f)) { ScaffoldProbe() }
        try {
            val image = scene.render()
            return requireNotNull(image.encodeToData(EncodedImageFormat.PNG)) { "PNG 인코딩 실패" }.bytes
        } finally {
            scene.close()
        }
    }

    @Test
    fun threeOffscreenRendersAreByteIdentical() {
        val pngs = List(3) { renderPng() }
        val digests = pngs.map { sha256(it) }
        // 러너 간 비교용(맥·ubuntu·windows 로그를 대조한다 — 같지 않으면 CI 는 compare 만 한다, A§4-3)
        println("AINGCHECK-AX6 os=${System.getProperty("os.name")} arch=${System.getProperty("os.arch")} sha256=${digests.joinToString(",")} bytes=${pngs.map { it.size }}")
        assertContentEquals(pngs[0], pngs[1], "1장과 2장이 다르다")
        assertContentEquals(pngs[0], pngs[2], "1장과 3장이 다르다")
        // 기준선은 다른 입력이어야 한다(기억 comparison-baseline-must-differ): 다른 장면은 다른 바이트여야 비교가 산다.
        assertFalse(renderPng(side = 120).contentEquals(pngs[0]), "다른 장면인데 같은 바이트 — 비교가 비어 있다")
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

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }.take(16)
}
