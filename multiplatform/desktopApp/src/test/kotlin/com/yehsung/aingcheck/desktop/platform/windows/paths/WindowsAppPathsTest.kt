// 원본: 없음(새 시험) — 설계 D§2-5(%LOCALAPPDATA%\aing-check, 로밍 아님) · G §8-12(MSIX 리디렉션 자리) · W0-e 러너 실측
package com.yehsung.aingcheck.desktop.platform.windows.paths

import com.yehsung.aingcheck.core.foundation.platform.desktop.EnvReader
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

/** D§2-5 저장 위치 + G §8-12(MSIX 안 %LOCALAPPDATA% 쓰기는 Packages\<PFN>\LocalCache\Local 로 간다 — W0-e 러너 실측). */
class WindowsAppPathsTest {
    private val lad = "C:\\Users\\홍길동\\AppData\\Local"
    private val profile = "C:\\Users\\홍길동"

    @Test
    fun unpackagedUsesLocalAppDataDirectly() {
        val p = WindowsAppPaths.resolve(lad, profile, packageFamilyName = null)
        assertEquals("C:\\Users\\홍길동\\AppData\\Local\\aing-check", p.dataDir)
        assertEquals("C:\\Users\\홍길동\\AppData\\Local\\aing-check\\vault", p.vaultDir)
        assertEquals("C:\\Users\\홍길동\\AppData\\Local\\aing-check\\installation-id", p.installationIdFile)
        assertEquals("C:\\Users\\홍길동\\AppData\\Local\\aing-check\\logs", p.logDir)
        assertEquals("C:\\Users\\홍길동\\AppData\\Local\\aing-check\\cache", p.cacheDir)
        assertEquals(profile, p.userHome)
        assertNull(p.packageFamilyName)
    }

    @Test
    fun packagedUsesTheRedirectTargetExplicitly() {
        val pfn = "YehSung.AingCheck_8wekyb3d8bbwe"
        val p = WindowsAppPaths.resolve(lad, profile, pfn)
        // W0-e 러너: 패키지 안에서 %LOCALAPPDATA%\X 에 쓰면 %LOCALAPPDATA%\Packages\<PFN>\LocalCache\Local\X 에 생겼다.
        assertEquals("C:\\Users\\홍길동\\AppData\\Local\\Packages\\YehSung.AingCheck_8wekyb3d8bbwe\\LocalCache\\Local\\aing-check", p.dataDir)
        assertEquals(p.dataDir + "\\vault", p.vaultDir)
        // 사용자 홈(.claude·.codex 읽기)은 리디렉션되지 않는다.
        assertEquals(profile, p.userHome)
        assertEquals(pfn, p.packageFamilyName)
    }

    @Test
    fun trailingSeparatorsAreNormalized() {
        assertEquals(
            WindowsAppPaths.resolve(lad, profile, null),
            WindowsAppPaths.resolve("$lad\\", "$profile\\", null),
        )
    }

    @Test
    fun suspiciousPackageNamesAreRefused() {
        // 경로에 끼우는 값이라 모양을 좁게 본다(..·구분자·빈 게시자 해시).
        for (bad in listOf("..\\..\\Windows_8wekyb3d8bbwe", "Name_short", "Name", "Na me_8wekyb3d8bbwe")) {
            assertFailsWith<IllegalArgumentException>(bad) { WindowsAppPaths.resolve(lad, profile, bad) }
        }
    }

    @Test
    fun environmentFallbackWhenLocalAppDataMissing() {
        val env = EnvReaderMap(mapOf("USERPROFILE" to "C:\\Users\\tester"))
        assertEquals("C:\\Users\\tester\\AppData\\Local\\aing-check", WindowsAppPaths.fromEnvironment(env, null).dataDir)
        val env2 = EnvReaderMap(mapOf("USERPROFILE" to "C:\\Users\\tester", "LOCALAPPDATA" to "D:\\Local"))
        assertEquals("D:\\Local\\aing-check", WindowsAppPaths.fromEnvironment(env2, null).dataDir)
    }
}

class EnvReaderMap(private val map: Map<String, String>) : EnvReader {
    override fun get(name: String): String? = map[name]
}
