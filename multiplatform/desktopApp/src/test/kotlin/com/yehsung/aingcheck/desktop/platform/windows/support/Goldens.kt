package com.yehsung.aingcheck.desktop.platform.windows.support

import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO
import kotlin.test.assertEquals
import kotlin.test.fail

/**
 * W1-f 골든 파일(이 갈래 소유 경로 안 — desktopApp/src/test/kotlin/…/platform/windows/golden/).
 * 기록: 환경 변수 AINGCHECK_GOLDEN_RECORD=1 로 돌리면 파일을 다시 쓰고 **실패로 끝난다**(기록한 실행을 초록으로 치지 않는다 —
 * W0-b CHECK_GOLDEN_WRITE 와 같은 규약). 대조: 바이트(글)·픽셀(그림)로 정확히 같아야 한다.
 */
object Goldens {
    private val recording: Boolean get() = System.getenv("AINGCHECK_GOLDEN_RECORD") == "1"

    fun dir(): File {
        val mp = System.getProperty("aingcheck.mpRoot") ?: fail("aingcheck.mpRoot 시스템 속성이 없다(aingcheck.test-seal 밖 실행)")
        return File(mp, "desktopApp/src/test/kotlin/com/yehsung/aingcheck/desktop/platform/windows/golden")
    }

    fun assertText(relative: String, actual: String) {
        val f = File(dir(), relative)
        if (recording) {
            f.parentFile.mkdirs()
            f.writeText(actual)
            fail("골든을 기록했다($f) — 기록 실행은 실패로 끝난다. 변수를 빼고 다시 돌려라")
        }
        if (!f.isFile) fail("골든이 없다: $f (AINGCHECK_GOLDEN_RECORD=1 로 기록)")
        // Windows 체크아웃(core.autocrlf=true)은 글 파일을 CRLF 로 바꿔 놓는다(windows-latest 실측) — 줄 끝만 맞춰 대조한다.
        assertEquals(f.readText().replace("\r\n", "\n"), actual, "골든과 다르다: $relative")
    }

    /** ARGB 픽셀 배열을 PNG 골든과 대조한다. 다르면 처음 어긋난 픽셀 좌표·값을 알린다. */
    fun assertImage(relative: String, width: Int, height: Int, argb: IntArray) {
        val f = File(dir(), relative)
        if (recording) {
            f.parentFile.mkdirs()
            val img = BufferedImage(width, height, BufferedImage.TYPE_INT_ARGB)
            img.setRGB(0, 0, width, height, argb, 0, width)
            ImageIO.write(img, "png", f)
            return
        }
        if (!f.isFile) fail("골든이 없다: $f (AINGCHECK_GOLDEN_RECORD=1 로 기록)")
        val img = ImageIO.read(f) ?: fail("PNG 를 못 읽었다: $f")
        assertEquals(width, img.width, "$relative 폭")
        assertEquals(height, img.height, "$relative 높이")
        val expected = IntArray(width * height)
        img.getRGB(0, 0, width, height, expected, 0, width)
        for (i in expected.indices) {
            // 완전히 투명한 픽셀은 색을 따지지 않는다(PNG 저장기가 투명 픽셀의 색을 버릴 수 있다). 렌더러는 0 으로 낸다.
            val e = if (expected[i] ushr 24 == 0) 0 else expected[i]
            if (e != argb[i]) {
                fail("$relative: (${i % width},${i / width}) 기대 0x${Integer.toHexString(e)} 실제 0x${Integer.toHexString(argb[i])}")
            }
        }
    }

    /** 그림 여러 장을 기록했으면 마지막에 한 번 실패시킨다. */
    fun failIfRecording() {
        if (recording) fail("골든 그림을 기록했다(${dir()}) — 기록 실행은 실패로 끝난다")
    }
}
