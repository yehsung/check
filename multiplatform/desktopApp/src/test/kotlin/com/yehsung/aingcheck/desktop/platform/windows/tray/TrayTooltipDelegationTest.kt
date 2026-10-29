// 원본: Sources/CheckCore/MenuBarStatusFormatter.swift @ a63fea2(titleDuration·localizedStatus·우선순위) — 이식본 core/rules
//       MenuBarStatusFormatter(G §8-13). 시험은 새 코드: shell.md §6 조정자 패치 3(TrayTooltip.hhmm → titleDuration 위임, 시:분 판정 두 벌 제거)
//       · 핀 조정 ⑩(트레이가 읽는 근무 값 = core/rules WorkStatusSnapshot)
package com.yehsung.aingcheck.desktop.platform.windows.tray

import com.yehsung.aingcheck.core.rules.format.MenuBarStatusFormatter
import com.yehsung.aingcheck.core.rules.format.WorkStatus
import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TrayTooltipDelegationTest {
    /** 경계 전수: 0·59·60·3599·3600·하루·99시간+·음수·Int 최대. 기대값은 core/rules 판정 그 자체(두 벌이면 언젠가 갈린다). */
    @Test
    fun hhmmIsTheCoreTitleDurationForEveryBoundary() {
        val samples = listOf(Int.MIN_VALUE, -3600, -1, 0, 1, 59, 60, 61, 3599, 3600, 3660, 86_399, 86_400, 99 * 3600 + 59 * 60 + 59, 360_000, Int.MAX_VALUE)
        for (s in samples) assertEquals(MenuBarStatusFormatter.titleDuration(s.toLong()), TrayTooltip.hhmm(s), "hhmm($s)")
        // 손으로 적은 맥 규칙 몇 칸(위임 대상이 틀려도 같이 초록이 되지 않게).
        assertEquals("00:00", TrayTooltip.hhmm(-5))
        assertEquals("00:59", TrayTooltip.hhmm(3599))
        assertEquals("100:00", TrayTooltip.hhmm(360_000))
    }

    /** 소스 계약: TrayTooltip 안에 시:분 산수가 없고 core 위임 한 줄만 있다(주석은 걷고 본다 — 기억 source-contract-tests-need-comment-stripping). */
    @Test
    fun tooltipHasNoOwnClockArithmetic() {
        val repo = System.getProperty("aingcheck.repoRoot") ?: error("aingcheck.repoRoot 시스템 속성이 없다(aingcheck.test-seal 밖 실행)")
        val src = File(repo, "multiplatform/desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/platform/windows/tray/TrayIconRenderer.kt").readText()
        val code = src.replace(Regex("""/\*[\s\S]*?\*/"""), "").lines().joinToString("\n") { it.replace(Regex("""//.*$"""), "") }
        val start = code.indexOf("object TrayTooltip")
        val end = code.indexOf("object TrayIconRenderer", start + 1)
        check(start >= 0 && end > start) { "TrayTooltip 선언을 못 찾았다" }
        val body = code.substring(start, end)
        assertTrue("MenuBarStatusFormatter.titleDuration(" in body, "titleDuration 위임이 없다")
        for (token in listOf("3600", "/ 60", "% 60", "padStart")) assertFalse(token in body, "TrayTooltip 에 시:분 판정이 남았다: '$token'")
        // 상태 글자도 core 의 localizedStatus 를 쓴다(글자 상수 '근무중' 등을 다시 적지 않는다).
        for (word in listOf("근무중", "근무종료", "동기화 대기")) assertFalse(word in body, "상태 글자를 다시 적었다: $word")
    }

    /** 조정 ⑩: core WorkStatusSnapshot 에서 바로 상태로. 맥 우선순위(동기화 대기 > 근무 중 > 오프)는 그대로. */
    @Test
    fun statusFromCoreSnapshotKeepsMacPriority() {
        assertEquals(TrayIconStatus.Pending, TrayIconStatus.of(WorkStatusSnapshot(WorkStatus.working, 600, pendingSync = true)))
        assertEquals(TrayIconStatus.Pending, TrayIconStatus.of(WorkStatusSnapshot(WorkStatus.offWork, 0, pendingSync = true)))
        assertEquals(TrayIconStatus.Working(5025), TrayIconStatus.of(WorkStatusSnapshot(WorkStatus.working, 5025)))
        assertEquals(TrayIconStatus.Off, TrayIconStatus.of(WorkStatusSnapshot(WorkStatus.offWork, 5025)))
        // Long → Int 접기: 음수 0, 넘침은 Int 최대.
        assertEquals(TrayIconStatus.Working(0), TrayIconStatus.of(WorkStatusSnapshot(WorkStatus.working, -30)))
        assertEquals(TrayIconStatus.Working(Int.MAX_VALUE), TrayIconStatus.of(WorkStatusSnapshot(WorkStatus.working, Long.MAX_VALUE)))
        // 툴팁 글자 = core localizedStatus + titleDuration.
        val snap = WorkStatusSnapshot(WorkStatus.working, 5025)
        assertEquals("아잉체크 · ${snap.localizedStatus} ${MenuBarStatusFormatter.titleDuration(5025)}", TrayTooltip.text(TrayIconStatus.of(snap)))
        assertEquals("아잉체크 · 근무중 01:23", TrayTooltip.text(TrayIconStatus.of(snap)))
    }
}
