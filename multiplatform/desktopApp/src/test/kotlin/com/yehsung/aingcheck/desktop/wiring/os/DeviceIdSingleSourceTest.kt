// W-13 #12 구조 시험: work_tick · ai_limits · 토큰 업로드가 받는 device_id 는 AppGraph.deviceId **한 곳**에서 나오고, 소문자 'win:'+uuid 다.
// 근거: 모바일 계약(W-11) — 맥 기기 id 는 대문자 UUID(접두 없음)라 'win:' 소문자와 글자 공간이 겹치지 않는다(순위표·기기 행 이중 계상 금지,
// 기억 device-identity-must-not-be-invented). 소스 계약은 주석을 걷고 본다(기억 source-contract-tests-need-comment-stripping).
@file:OptIn(ExperimentalTime::class, ExperimentalCoroutinesApi::class)

package com.yehsung.aingcheck.desktop.wiring.os

import com.yehsung.aingcheck.desktop.platform.windows.identity.WindowsDeviceIdentity
import com.yehsung.aingcheck.desktop.wiring.WiringTestRig
import com.yehsung.aingcheck.desktop.wiring.WorkDeps
import com.yehsung.aingcheck.desktop.wiring.WorkWiring
import com.yehsung.aingcheck.feature.desktop.work.policy.toSwiftDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.extension
import kotlin.io.path.readText
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.ExperimentalTime

class DeviceIdSingleSourceTest {
    private val mainRoot: Path = listOf(Path.of("src/main/kotlin"), Path.of("desktopApp/src/main/kotlin")).first { Files.isDirectory(it) }
    private val pkg: Path = mainRoot.resolve("com/yehsung/aingcheck/desktop")

    /** 줄 주석·블록 주석·KDoc 을 걷는다(문자열 안의 // 는 남긴다 — 'https://' 같은 것). */
    private fun code(path: Path): String {
        val src = path.readText()
        val noBlock = Regex("""/\*[\s\S]*?\*/""").replace(src, " ")
        return noBlock.lines().joinToString("\n") { line ->
            var inStr = false
            var i = 0
            var cut = line.length
            while (i < line.length - 1) {
                val c = line[i]
                if (c == '"' && (i == 0 || line[i - 1] != '\\')) inStr = !inStr
                if (!inStr && c == '/' && line[i + 1] == '/') { cut = i; break }
                i++
            }
            line.substring(0, cut)
        }
    }

    private val macDeviceId = Regex("^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$")

    @Test
    fun 기기_id_는_소문자_win_접두이고_맥_대문자_UUID_와_겹치지_않는다() {
        val id = WindowsDeviceIdentity.deviceId("AABBCCDD-1111-4222-8333-444455556666")!!
        assertEquals("win:aabbccdd-1111-4222-8333-444455556666", id)
        assertFalse(macDeviceId.matches(id))
        assertFalse(macDeviceId.matches(id.removePrefix("win:")), "접두를 떼도 소문자라 맥 꼴이 아니다")
        assertEquals(null, WindowsDeviceIdentity.deviceId(null), "신원이 없으면 짓지 않는다")
    }

    @Test
    fun 기기_id_를_만드는_곳은_AppGraph_deviceId_한_곳() {
        val files = Files.walk(mainRoot).use { s -> s.filter { it.extension == "kt" }.toList() }
        val makers = files.filter { "WindowsDeviceIdentity.deviceId(" in code(it) }
        assertEquals(listOf("AppGraph.kt"), makers.map { it.fileName.toString() }, "기기 id 를 다시 짓는 곳 — $makers")
        val appGraph = code(pkg.resolve("AppGraph.kt"))
        assertEquals(1, Regex("""val\s+deviceId\s*:\s*String\?\s*get\(\)\s*=\s*WindowsDeviceIdentity\.deviceId\(""").findAll(appGraph).count())
        // 'win:' 글자를 직접 적는 곳은 접두 상수 하나뿐.
        val literal = files.filter { "\"win:" in code(it) }.map { it.fileName.toString() }
        assertEquals(listOf("Uuid5.kt"), literal)
    }

    @Test
    fun work_tick_ai_limits_토큰_업로드가_같은_한_곳을_받는다() {
        val appGraph = code(pkg.resolve("AppGraph.kt"))
        // WorkDeps(work_tick p_device_id) · TokensWiringDeps(토큰 업로드·ai_limits) — 둘 다 graph.deviceId.
        val workDeps = Regex("""WorkDeps\(([\s\S]*?)\n\s*\),""").find(appGraph)?.groupValues?.get(1).orEmpty()
        assertTrue(Regex("""deviceId\s*=\s*graph\.deviceId\b""").containsMatchIn(workDeps), "WorkDeps.deviceId = graph.deviceId")
        val tokensDeps = Regex("""TokensWiringDeps\(([\s\S]*?)\n\s*\),""").find(appGraph)?.groupValues?.get(1).orEmpty()
        assertTrue(Regex("""deviceId\s*=\s*\{\s*graph\.deviceId\s*\}""").containsMatchIn(tokensDeps), "TokensWiringDeps.deviceId = { graph.deviceId }")
        val tokens = code(pkg.resolve("wiring/TokensWiring.kt"))
        val upload = Regex("""TokenUploadCoordinator\(([\s\S]*?)\n\s*\)""").find(tokens)?.groupValues?.get(1).orEmpty()
        val limits = Regex("""DesktopAILimitSync\(([\s\S]*?)\n\s*\)""").find(tokens)?.groupValues?.get(1).orEmpty()
        assertTrue(Regex("""deviceId\s*=\s*deps\.deviceId\b""").containsMatchIn(upload), "토큰 업로드 — $upload")
        assertTrue(Regex("""deviceId\s*=\s*deps\.deviceId\b""").containsMatchIn(limits), "ai_limits — $limits")
    }

    /** 실행 경로: work_tick 인자의 기기 id 가 WorkDeps 로 받은 그 값 그대로(다시 다듬거나 대문자로 바꾸지 않는다). */
    @Test
    fun work_tick_인자_기기_id_는_받은_값_그대로() = runTest {
        val rig = WiringTestRig(this)
        val deviceId = WindowsDeviceIdentity.deviceId(WiringTestRig.INSTALLATION)
        val work = WorkWiring(
            WorkDeps(
                sessionStore = rig.sessionStore, kv = rig.kv, clock = rig.clock, deviceId = deviceId,
                idle = rig.idle, power = rig.power, session = rig.sessionEvents, teamId = { WiringTestRig.TEAM },
            ),
        )
        try {
            rig.signIn()
            work.start(rig.scope)
            runCurrent()
            work.commands.start()
            runCurrent()
            val args = work.store.planWorkTick(rig.clock.now().toSwiftDate())
            assertEquals(deviceId, args?.deviceId)
            assertEquals(WiringTestRig.DEVICE, args?.deviceId)
        } finally {
            work.stop()
            rig.close()
        }
    }
}
