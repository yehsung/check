// 원본: Sources/check/CheckApp.swift:222-241 @ a63fea2 (자동 실행: 기본 켜짐·사용자가 끈 것 존중) — 시험은 새 코드:
//       설계 D§2-4(JNA DLL 풀기)·D§2-5(패키지 신원)·D§3-3(작업 표시줄)·D§12-1(레지스트리 환경 값의 형) · E11 · G §8-12
package com.yehsung.aingcheck.desktop.platform.windows.runner

import com.sun.jna.platform.win32.Advapi32Util
import com.sun.jna.platform.win32.WinReg
import com.yehsung.aingcheck.desktop.platform.windows.env.RegistryString
import com.yehsung.aingcheck.desktop.platform.windows.env.WindowsEnvironment
import com.yehsung.aingcheck.desktop.platform.windows.flyout.FlyoutPlacer
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxPoint
import com.yehsung.aingcheck.desktop.platform.windows.flyout.TaskbarProbe
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32
import com.yehsung.aingcheck.desktop.platform.windows.login.RunKeyLoginItem
import com.yehsung.aingcheck.desktop.platform.windows.paths.PackageIdentity
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 러너에서 재는 나머지 OS 층: 패키지 신원·작업 표시줄·레지스트리 환경·자동 실행·JNA 풀기. 레지스트리는 시험 전용 키에만 쓴다. */
@EnabledOnOs(OS.WINDOWS)
class WindowsProbesWindowsTest {
    @field:TempDir
    lateinit var tmp: Path

    private fun scratchKey() = "Software\\AingCheckTest\\" + UUID.randomUUID()

    private fun deleteTree(key: String) {
        runCatching { Advapi32Util.registryDeleteKey(WinReg.HKEY_CURRENT_USER, key) }
        runCatching { Advapi32Util.registryDeleteKey(WinReg.HKEY_CURRENT_USER, key.substringBeforeLast('\\')) }
    }

    @Test
    fun unpackagedProcessHasNoPackageFamilyName() {
        // 시험 JVM 은 MSIX 밖이다 → 15700(APPMODEL_ERROR_NO_PACKAGE). 패키지 안 값은 VM 의 MSIX 실행(D-E15)에서 잰다.
        assertEquals(null to Win32.APPMODEL_ERROR_NO_PACKAGE, PackageIdentity.currentFamilyName())
    }

    @Test
    fun taskbarProbeDescribesARealScreenThatPlacementAccepts() {
        val facts = TaskbarProbe.probe()
        assertNotNull(facts, "SHAppBarMessage·GetMonitorInfo 실패")
        assertTrue(facts.monitor.contains(facts.workArea), "작업 영역이 모니터 밖: $facts")
        assertTrue(facts.dpi >= 96, "DPI ${facts.dpi}")
        assertTrue(facts.taskbar.rect.intersects(facts.monitor), "작업 표시줄이 그 모니터에 없다: $facts")
        println("AINGCHECK-SCREEN $facts")
        val anchor = PxPoint((facts.taskbar.rect.left + facts.taskbar.rect.right) / 2, (facts.taskbar.rect.top + facts.taskbar.rect.bottom) / 2)
        val p = FlyoutPlacer.place(facts.request(anchor, iconRect = null, contentHeightDip = 400.0))
        assertTrue(facts.workArea.contains(p.rect) || facts.taskbar.autoHide, "배치가 작업 영역 밖: ${p.rect}")
        assertFalse(p.rect.intersects(facts.taskbar.rect), "작업 표시줄을 덮는다: ${p.rect}")
    }

    @Test
    fun registryEnvironmentReaderKeepsTheValueType() {
        val key = scratchKey()
        try {
            Advapi32Util.registryCreateKey(WinReg.HKEY_CURRENT_USER, key)
            Advapi32Util.registrySetStringValue(WinReg.HKEY_CURRENT_USER, key, "PLAIN", "%USERPROFILE%\\plain")
            Advapi32Util.registrySetExpandableStringValue(WinReg.HKEY_CURRENT_USER, key, "EXPAND", "%USERPROFILE%\\expand")
            val reader = WindowsEnvironment.registryReader(WinReg.HKEY_CURRENT_USER, key)
            assertEquals(RegistryString("%USERPROFILE%\\plain", expandable = false), reader.read("PLAIN"))
            assertEquals(RegistryString("%USERPROFILE%\\expand", expandable = true), reader.read("EXPAND"))
            assertNull(reader.read("MISSING"))
        } finally {
            deleteTree(key)
        }
    }

    @Test
    fun runKeyLoginItemRespectsTheUserSwitchOff() {
        val base = scratchKey()
        val run = "$base\\Run"
        val approved = "$base\\StartupApproved\\Run"
        val item = RunKeyLoginItem("C:\\Program Files\\AingCheck\\AingCheck.exe", root = WinReg.HKEY_CURRENT_USER, runKey = run, approvedKey = approved)
        try {
            assertFalse(item.isEnabled())
            assertTrue(item.setEnabled(true), "켜기")
            assertEquals("\"C:\\Program Files\\AingCheck\\AingCheck.exe\" --autostart", Advapi32Util.registryGetStringValue(WinReg.HKEY_CURRENT_USER, run, "AingCheck"))
            assertTrue(item.isEnabled())
            assertFalse(item.setEnabled(true), "이미 켜져 있는데 바뀌었다고 한다")
            // 사용자가 작업 관리자에서 끔(StartupApproved 첫 바이트 홀수) → 꺼진 것으로 읽고, 되살리지 않는다.
            Advapi32Util.registryCreateKey(WinReg.HKEY_CURRENT_USER, approved.substringBeforeLast('\\'))
            Advapi32Util.registryCreateKey(WinReg.HKEY_CURRENT_USER, approved)
            Advapi32Util.registrySetBinaryValue(WinReg.HKEY_CURRENT_USER, approved, "AingCheck", byteArrayOf(0x03, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            assertFalse(item.isEnabled())
            assertTrue(item.setEnabled(false), "끄기(Run 값 지움)")
            assertFalse(item.setEnabled(true), "사용자가 끈 것을 되살렸다")
            assertFalse(Advapi32Util.registryValueExists(WinReg.HKEY_CURRENT_USER, run, "AingCheck"))
        } finally {
            runCatching { Advapi32Util.registryDeleteKey(WinReg.HKEY_CURRENT_USER, approved) }
            runCatching { Advapi32Util.registryDeleteKey(WinReg.HKEY_CURRENT_USER, approved.substringBeforeLast('\\')) }
            runCatching { Advapi32Util.registryDeleteKey(WinReg.HKEY_CURRENT_USER, run) }
            deleteTree(base)
        }
    }

    @Test
    fun jnaLoadsFromTheBootPathWithoutUnpackingIntoTemp() {
        // D§2-4 · W0-e 관측(jnidispatch 가 %TEMP%\jna--* 에 풀렸다)의 짝 실험: 같은 자식 JVM 을 두 번 —
        //  ① 기본값: 지정한 jna.tmpdir 에 jnidispatch 가 풀린다(관측기가 동작한다는 증거)
        //  ② 패키지 꼴(jna.boot.library.path + nounpack + nosys): 같은 자리가 비어 있다.
        val resource = "com/sun/jna/${com.sun.jna.Platform.RESOURCE_PREFIX}/jnidispatch.dll"
        // @TempDir 를 쓰지 않는다: 자식이 막 내려놓은 DLL 은 잠깐 지워지지 않는다(러너 실측 AccessDenied, run 39621457060) —
        // JUnit 의 정리 실패가 시험 실패로 번지지 않게 직접 만들고 재시도로 지운다.
        val work = Files.createTempDirectory("aingcheck-jna")
        try {
            jnaPair(resource, work)
        } finally {
            deleteWithRetry(work)
        }
    }

    private fun deleteWithRetry(root: Path) {
        repeat(50) {
            val left = runCatching {
                Files.walk(root).use { s -> s.sorted(Comparator.reverseOrder()).forEach { p -> runCatching { Files.deleteIfExists(p) } } }
                Files.exists(root)
            }.getOrDefault(true)
            if (!left) return
            Thread.sleep(100)
        }
        println("AINGCHECK-JNA 정리 못 한 임시 폴더(잠김): $root")
    }

    private fun jnaPair(resource: String, tmp: Path) {
        val boot = Files.createDirectories(tmp.resolve("boot"))
        javaClass.classLoader.getResourceAsStream(resource).use { input ->
            assertNotNull(input, "jna jar 에 $resource 가 없다")
            Files.copy(input, boot.resolve("jnidispatch.dll"))
        }
        val unpackDir = Files.createDirectories(tmp.resolve("unpack-default"))
        val a = RunnerSupport.runChild(listOf("jna"), listOf("-Djna.tmpdir=$unpackDir"))
        assertEquals(0, a.exitCode, a.stderr)
        val unpacked = Files.walk(unpackDir).use { s -> s.filter { Files.isRegularFile(it) }.count() }
        assertTrue(unpacked > 0, "기본값인데 풀린 파일이 없다 — 관측기가 아무것도 못 본다")

        val noUnpackDir = Files.createDirectories(tmp.resolve("unpack-packaged"))
        val b = RunnerSupport.runChild(
            listOf("jna"),
            listOf("-Djna.tmpdir=$noUnpackDir", "-Djna.boot.library.path=$boot", "-Djna.nounpack=true", "-Djna.nosys=true"),
        )
        assertEquals(0, b.exitCode, b.stderr)
        assertTrue(b.stdout.contains("pointer=8"), b.stdout)
        val leaked = Files.walk(noUnpackDir).use { s -> s.filter { Files.isRegularFile(it) }.count() }
        assertEquals(0L, leaked, "패키지 꼴인데 임시 폴더에 DLL 을 풀었다")
    }
}
