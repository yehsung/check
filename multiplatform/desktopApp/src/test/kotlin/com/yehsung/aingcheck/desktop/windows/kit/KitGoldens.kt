// 원본: 없음(새 시험 도우미) — platform/windows/support/Goldens.kt 와 같은 규약을 W4-d 자리(windows/kit/golden/)에 둔다
package com.yehsung.aingcheck.desktop.windows.kit

import java.io.File
import kotlin.test.assertEquals
import kotlin.test.fail

/**
 * 기록: AINGCHECK_GOLDEN_RECORD=1 로 돌리면 파일을 다시 쓰고 **실패로 끝난다**(기록한 실행을 초록으로 치지 않는다).
 * 대조: 줄 끝(CRLF — Windows 체크아웃)만 맞춘 뒤 바이트로 같아야 한다.
 */
object KitGoldens {
    fun mpRoot(): File = File(System.getProperty("aingcheck.mpRoot") ?: fail("aingcheck.mpRoot 시스템 속성이 없다(aingcheck.test-seal 밖 실행)"))

    fun dir(): File = File(mpRoot(), "desktopApp/src/test/kotlin/com/yehsung/aingcheck/desktop/windows/kit/golden")

    /** desktopApp main 의 windows/ 뿌리(갈래 W4-d·e·f 의 창 소스). */
    fun windowsMainRoot(): File = File(mpRoot(), "desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/windows")

    fun assertText(relative: String, actual: String) {
        val f = File(dir(), relative)
        if (System.getenv("AINGCHECK_GOLDEN_RECORD") == "1") {
            f.parentFile.mkdirs()
            f.writeText(actual)
            fail("골든을 기록했다($f) — 기록 실행은 실패로 끝난다. 변수를 빼고 다시 돌려라")
        }
        if (!f.isFile) fail("골든이 없다: $f (AINGCHECK_GOLDEN_RECORD=1 로 기록)")
        assertEquals(f.readText().replace("\r\n", "\n"), actual, "골든과 다르다: $relative")
    }
}
