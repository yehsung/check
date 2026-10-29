// 원본: Sources/check/CheckMenuView.swift:1351-1396·1298 @ a90d8623 (MenuBarDotReasons) — ★1 점은 하나 · ★2 글 순서 · ⚠️6 근무 무관
//       · W-3 #7(대결 깃발) · #14(신고 점 false)
package com.yehsung.aingcheck.desktop.shell.tray

import com.yehsung.aingcheck.desktop.shellapi.DesktopUpdateState
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TrayDotReasonsTest {
    /** 맥 소스(주석 걷고)에서 MenuBarDotReasons 의 글·순서·구분자를 뽑는다 — 기대값을 Kotlin 상수에서 가져오지 않는다. */
    private data class MacDots(val order: List<Pair<String, String>>, val separator: String)

    private fun macDots(): MacDots {
        val repo = System.getProperty("aingcheck.repoRoot") ?: error("aingcheck.repoRoot 시스템 속성이 없다(aingcheck.test-seal 밖 실행)")
        val swift = File(repo, "Sources/check/CheckMenuView.swift").readText()
        val code = swift.replace(Regex("""/\*[\s\S]*?\*/"""), "").lines().joinToString("\n") { it.replace(Regex("""//.*$"""), "") }
        val start = code.indexOf("struct MenuBarDotReasons")
        val end = code.indexOf("#if", start + 1)
        check(start >= 0 && end > start) { "맥 소스에서 MenuBarDotReasons 선언을 못 찾았다" }
        val body = code.substring(start, end)
        val texts = Regex("""static\s+let\s+(\w+)\s*=\s*"([^"]+)"""").findAll(body).associate { it.groupValues[1] to it.groupValues[2] }
        val updateText = Regex("""static\s+let\s+updateDotAccessibilityDescription\s*=\s*"([^"]+)"""").find(code)?.groupValues?.get(1)
            ?: error("맥 updateDotAccessibilityDescription 을 못 찾았다")
        val desc = body.substring(body.indexOf("var accessibilityDescription"))
        val order = Regex("""if\s+(\w+)\s*\{\s*parts\.append\(([^)]+)\)\s*\}""").findAll(desc).map { m ->
            val flag = m.groupValues[1]
            val expr = m.groupValues[2].trim()
            val text = when {
                expr.startsWith("Self.") -> texts[expr.removePrefix("Self.")] ?: error("맥 글 상수 $expr 를 못 찾았다")
                expr == "MenuBarStatusLabel.updateDotAccessibilityDescription" -> updateText
                else -> error("모르는 맥 식: $expr")
            }
            flag to text
        }.toList()
        val sep = Regex("""joined\(separator:\s*"([^"]+)"\)""").find(desc)?.groupValues?.get(1) ?: error("맥 구분자를 못 찾았다")
        return MacDots(order, sep)
    }

    private fun only(flag: String): TrayDotReasons = when (flag) {
        "unreadMessages" -> TrayDotReasons(unreadMessages = true)
        "gomokuInvite" -> TrayDotReasons(gomokuInvite = true)
        "chessInvite" -> TrayDotReasons(chessInvite = true)
        "tetrisInvite" -> TrayDotReasons(tetrisInvite = true)
        "openReports" -> TrayDotReasons(openReports = true)
        "updateAvailable" -> TrayDotReasons(updateAvailable = true)
        else -> error("맥에 새 사유가 생겼다: $flag — Kotlin TrayDotReasons 에도 옮겨라")
    }

    @Test
    fun star2TextsAndOrderMatchTheMacSource() {
        val mac = macDots()
        assertEquals(6, mac.order.size, "맥 사유는 여섯이다: ${mac.order}")
        assertEquals(mac.separator, TrayDotReasons.SEPARATOR)
        val all = TrayDotReasons(true, true, true, true, true, true)
        assertEquals(mac.order.joinToString(mac.separator) { it.second }, all.accessibilityDescription)
        for ((flag, text) in mac.order) assertEquals(text, only(flag).accessibilityDescription, flag)
    }

    @Test
    fun star1OneDotAnyReasonNoneMeansNoDescription() {
        assertTrue(TrayDotReasons().isEmpty)
        assertNull(TrayDotReasons().accessibilityDescription)
        for (flag in listOf("unreadMessages", "gomokuInvite", "chessInvite", "tetrisInvite", "openReports", "updateAvailable")) {
            assertFalse(only(flag).isEmpty, flag)
        }
    }

    @Test
    fun duelInvitesOnlyWhenDuelsFlagW3n7AndReportsAlwaysOffW3n14() {
        val off = DesktopAppConfig()
        val on = DesktopAppConfig(duels = true)
        val r1 = TrayDotReasons.of(off, unreadMessageCount = 0, gomokuInvite = true, chessInvite = true, tetrisInvite = true)
        assertTrue(r1.isEmpty, "duels 꺼짐이면 신청 점 0: $r1")
        val r2 = TrayDotReasons.of(on, unreadMessageCount = 0, gomokuInvite = true, chessInvite = true, tetrisInvite = true)
        assertEquals(TrayDotReasons(gomokuInvite = true, chessInvite = true, tetrisInvite = true), r2)
        assertFalse(TrayDotReasons.of(on, 5).openReports)
    }

    @Test
    fun unreadAndUpdateInputs() {
        val f = DesktopAppConfig()
        assertFalse(TrayDotReasons.of(f, 0).unreadMessages)
        assertTrue(TrayDotReasons.of(f, 1).unreadMessages)
        assertTrue(TrayDotReasons.of(f, 0, update = DesktopUpdateState(currentBuild = 10, latestBuild = 11)).updateAvailable)
        assertFalse(TrayDotReasons.of(f, 0, update = DesktopUpdateState(currentBuild = 10, latestBuild = 10)).updateAvailable)
        assertFalse(TrayDotReasons.of(f, 0, update = DesktopUpdateState(currentBuild = 10)).updateAvailable)
        assertFalse(TrayDotReasons.of(f, 0, update = null).updateAvailable)
    }
}
