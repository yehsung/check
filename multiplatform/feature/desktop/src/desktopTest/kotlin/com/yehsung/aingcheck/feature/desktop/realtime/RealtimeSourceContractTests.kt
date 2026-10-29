// 소스 계약(주석을 걷고 잰다 — 주석에 적힌 숫자·이름이 판정을 흔들지 않게). 규약: R1 문 셋 · R7 화면 값 대입 · C§4 #18 하트비트 25≠30.
package com.yehsung.aingcheck.feature.desktop.realtime

import com.yehsung.aingcheck.core.net.realtime.RealtimeLinkConstants
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

internal object SourceText {
    /** multiplatform/ 뿌리(settings.gradle.kts 가 있는 곳). */
    val root: File = generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "settings.gradle.kts").exists() }

    val realtimeMainDir: File =
        File(root, "feature/desktop/src/desktopMain/kotlin/com/yehsung/aingcheck/feature/desktop/realtime")

    fun realtimeSources(): List<File> =
        realtimeMainDir.listFiles { f -> f.isFile && f.extension == "kt" }.orEmpty().sortedBy { it.name }

    // 문자열 안의 줄 주석·덩어리 주석 기호는 주석이 아니다(Kotlin·Swift 공통 최소 규칙).
    fun stripComments(src: String): String {
        val out = StringBuilder()
        var i = 0
        var inString = false
        while (i < src.length) {
            val c = src[i]
            if (inString) {
                out.append(c)
                if (c == '\\' && i + 1 < src.length) { out.append(src[i + 1]); i += 2; continue }
                if (c == '"') inString = false
                i++
                continue
            }
            if (c == '"') { inString = true; out.append(c); i++; continue }
            if (src.startsWith("//", i)) { while (i < src.length && src[i] != '\n') i++; continue }
            if (src.startsWith("/*", i)) { val end = src.indexOf("*/", i + 2); i = if (end < 0) src.length else end + 2; continue }
            out.append(c)
            i++
        }
        return out.toString()
    }

    fun count(code: String, needle: String): Int = Regex(Regex.escape(needle)).findAll(code).count()
}

/** C§4 #18 · R7: 실시간 하트비트 25초와 근무 하트비트 30초는 다른 상수다. 데스크톱 실시간 층은 어느 쪽 숫자도 맨손으로 쓰지 않는다. */
class HeartbeatConstantsSourceTest {
    @Test
    fun realtimeHeartbeat25IsNotTheWorkHeartbeat30() {
        val swiftLink = SourceText.stripComments(RepoFiles.readText("Sources/CheckCore/RealtimeLink.swift"))
        val swiftWork = SourceText.stripComments(RepoFiles.readText("Sources/check/WorkTimerStore.swift"))
        val decl = Regex("""static let heartbeatIntervalSeconds: TimeInterval = (\d+(?:\.\d+)?)""")
        val realtime = decl.findAll(swiftLink).map { it.groupValues[1].toDouble() }.toList()
        val work = decl.findAll(swiftWork).map { it.groupValues[1].toDouble() }.toList()
        assertEquals(listOf(25.0), realtime, "Swift 실시간 하트비트 선언(RealtimeLink.swift)")
        assertEquals(listOf(30.0), work, "Swift 근무 하트비트 선언(WorkTimerStore.swift)")
        assertNotEquals(realtime.single(), work.single(), "25 ≠ 30")
        assertEquals(realtime.single(), RealtimeLinkConstants.heartbeatIntervalSeconds, "Kotlin 링 상수가 Swift 실시간 값과 같다")
        assertTrue(
            DesktopRealtimeRunner.TICK_INTERVAL_SECONDS < RealtimeLinkConstants.heartbeatIntervalSeconds,
            "티커(${DesktopRealtimeRunner.TICK_INTERVAL_SECONDS})는 하트비트 눈금보다 촘촘해야 한다",
        )

        val sources = SourceText.realtimeSources()
        assertTrue(sources.size >= 3, "데스크톱 실시간 소스를 못 찾았다: ${SourceText.realtimeMainDir}")
        val heartbeatDecl = Regex("""\b(?:val|var)\s+\w*[Hh]eartbeat\w*""")
        val bareNumber = Regex("""(?<![\w.])(25|30)(?:\.0+)?(?![\w.])""")
        val problems = mutableListOf<String>()
        for (f in sources) {
            val code = SourceText.stripComments(f.readText())
            heartbeatDecl.findAll(code).forEach { problems += "${f.name}: 하트비트 이름의 선언 '${it.value}' — 실시간 값은 RealtimeLinkConstants 한 곳" }
            bareNumber.findAll(code).forEach { m ->
                problems += "${f.name}: 맨 숫자 ${m.value} — '${code.substring(maxOf(0, m.range.first - 30), minOf(code.length, m.range.last + 10)).replace("\n", " ")}'"
            }
        }
        assertTrue(problems.isEmpty(), problems.joinToString("\n"))
    }
}

/** ★ R1 문 셋 · R7 화면 값: 러너 소스에서 링 apply · 상태 대입 · take_pokes 문이 각각 한 자리다. */
class RealtimeDoorsSourceTest {
    private val runner: String by lazy {
        SourceText.stripComments(File(SourceText.realtimeMainDir, "DesktopRealtimeRunner.kt").readText())
    }

    @Test
    fun linkApplyHasOneDoor() {
        assertEquals(1, SourceText.count(runner, "link.apply("), "링에 시각을 주는 문은 하나(R1 ①)")
        val others = SourceText.realtimeSources().filter { it.name != "DesktopRealtimeRunner.kt" }
            .filter { SourceText.count(SourceText.stripComments(it.readText()), "link.apply(") > 0 }
        assertTrue(others.isEmpty(), "러너 밖에서 링을 움직인다: ${others.map { it.name }}")
        assertTrue(!runner.contains("Clock.System") && !runner.contains("currentTimeMillis"), "러너가 벽시계를 직접 읽는다(시계는 주입)")
    }

    @Test
    fun stateIsAssignedOnlyInApplyBehindInequalityGuard() {
        val assigns = Regex("""_state\.value\s*=(?!=)""").findAll(runner).toList()
        assertEquals(1, assigns.size, "realtimeState 대입은 apply 한 곳(R7)")
        val line = runner.lineSequence().first { Regex("""_state\.value\s*=(?!=)""").containsMatchIn(it) }
        assertTrue(Regex("""if \(_state\.value != after\)""").containsMatchIn(line), "`!=` 가드가 없다: $line")
    }

    @Test
    fun takePokesDoorsPassTheOneGate() {
        assertEquals(1, SourceText.count(runner, "gate.mayConsume("), "판정 호출은 mayConsumePokes 한 곳(R1 ③)")
        assertEquals(1, SourceText.count(runner, ".requestDrain()"), "requestDrain 은 .drain 가지 한 곳")
        assertEquals(1, SourceText.count(runner, ".drainOnce()"), "drainOnce 는 따라잡기 한 곳")
        // 두 문 모두 mayConsumePokes 를 먼저 본다.
        val drainBranch = runner.substringAfter("RealtimeEffect.Drain ->").substringBefore("RealtimeEffect.MessageReadSignal")
        assertTrue(drainBranch.contains("mayConsumePokes(now)") && drainBranch.indexOf("mayConsumePokes") < drainBranch.indexOf("requestDrain"), drainBranch)
        val catchUp = runner.substringAfter("private suspend fun catchUpAfterSubscribe()")
        assertTrue(catchUp.indexOf("mayConsumePokes(") in 0 until catchUp.indexOf("drainOnce()"), "따라잡기가 게이트보다 먼저 drainOnce 를 부른다")
    }
}
