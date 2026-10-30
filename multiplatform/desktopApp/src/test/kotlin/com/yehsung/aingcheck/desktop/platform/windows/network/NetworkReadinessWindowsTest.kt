// 원본: 없음(새 시험) — 설계 G §2-3(러너 2종에서 실제 OS 로 잰다) · 기억 comparison-baseline-must-differ(다른 구현으로 대조)
// 러너는 java.exe 아웃바운드가 방화벽으로 막혀 있다(mp-ci windows 잡) — 이 시험은 망에 나가지 않는다. 연결 힌트는 OS(NCSI)가 낸다.
package com.yehsung.aingcheck.desktop.platform.windows.network

import com.sun.jna.Native
import com.yehsung.aingcheck.desktop.platform.windows.runner.RunnerSupport
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.jupiter.api.condition.EnabledOnOs
import org.junit.jupiter.api.condition.OS
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@EnabledOnOs(OS.WINDOWS)
class NetworkReadinessWindowsTest {
    @Test
    fun hintStructureIsTwelveBytesAndTheCallSucceeds() {
        assertEquals(NL_NETWORK_CONNECTIVITY_HINT.EXPECTED_SIZE, NL_NETWORK_CONNECTIVITY_HINT().size())
        val p = WindowsConnectivityHint.probe()
        // 러너(Server 2022+/Windows 11 arm)는 build 19041 이상 — 함수가 있어야 한다.
        val level = assertIs<ConnectivityProbe.Level>(p, "GetNetworkConnectivityHint 실패: $p").level
        assertTrue(level in 0..5, "문서에 없는 수준: $level")
    }

    @Test
    fun readinessAgreesWithPowerShellConnectionProfiles() {
        // 다른 구현(NetConnectionProfile CIM)으로 '연결된 망이 있다'를 잰다. 둘 다 있다고 하면 우리 판정은 READY 여야 한다.
        val out = RunnerSupport.runTool(
            "powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
            "@(Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { \$_.IPv4Connectivity -ne 'Disconnected' -or \$_.IPv6Connectivity -ne 'Disconnected' }).Count",
        ).trim().lines().last().trim()
        val profiles = out.toIntOrNull()
        assertNotNull(profiles, "PowerShell 출력: $out")
        val p = WindowsConnectivityHint.probe()
        if (profiles > 0) {
            assertEquals(Readiness.READY, ConnectivityLevels.classify(p), "연결 프로필 $profiles 개인데 힌트는 $p")
        }
    }

    @Test
    fun awaitReadyReturnsQuicklyOnARunnerWithANetwork() = runBlocking {
        val r = PolledNetworkReadiness(WindowsConnectivityHint::probe)
        val started = System.nanoTime()
        val ok = withTimeoutOrNull(10_000) { r.awaitReady(); true }
        assertEquals(true, ok, "10초 안에 준비되지 않았다: ${r.lastProbe} · lastError=${Native.getLastError()}")
        assertTrue((System.nanoTime() - started) / 1_000_000 < 10_000)
    }
}
