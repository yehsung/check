// 구조 시험(xplat-w1/briefs/work.md §5 DesktopWorkForbiddenWritesTest): Windows 는 profiles.app_build·app_version·token_usage_monthly 를
// 절대 쓰지 않는다(W-3 #11) · take_pokes 는 찌르기 갈래 몫 · deviceId null 이면 기기 단위 쓰기 0. 소스는 주석을 걷고 본다.
package com.yehsung.aingcheck.feature.desktop.work.service

import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DesktopWorkForbiddenWritesTest {
    private val forbidden = listOf("app_build", "app_version", "token_usage_monthly", "take_pokes", "updateAppVersion", "/rest/v1/profiles")

    /** 주석(줄 · 블록)을 걷는다 — 글자 리터럴 안의 `//`(URL)는 남긴다. */
    private fun stripComments(src: String): String {
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
            when {
                c == '"' -> { inString = true; out.append(c); i++ }
                src.startsWith("//", i) -> { while (i < src.length && src[i] != '\n') i++ }
                src.startsWith("/*", i) -> { val end = src.indexOf("*/", i + 2); i = if (end < 0) src.length else end + 2 }
                else -> { out.append(c); i++ }
            }
        }
        return out.toString()
    }

    private fun workSources(): List<File> {
        val roots = listOf("src/commonMain", "src/desktopMain").map { File(it, "kotlin/com/yehsung/aingcheck/feature/desktop/work") }
        assertTrue(roots.any { it.isDirectory }, "work 소스 폴더를 못 찾았다(작업 폴더 ${File(".").absolutePath})")
        return roots.filter { it.isDirectory }.flatMap { r -> r.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.toList() }
    }

    @Test
    fun workSourcesNeverNameForbiddenWrites() {
        val files = workSources()
        assertTrue(files.size >= 4, "스캔한 파일이 적다: ${files.map { it.name }}")
        val hits = files.flatMap { f ->
            val code = stripComments(f.readText())
            forbidden.filter { code.contains(it) }.map { "${f.name}: $it" }
        }
        assertEquals(emptyList(), hits)
    }

    /** 음성 대조: 걷개가 코드 속 금지 이름은 남기고(빨강) 주석 속 이름만 지운다. */
    @Test
    fun negative_stripperKeepsCodeAndDropsComments() {
        val code = stripComments("val x = \"/rest/v1/profiles\" // app_build\n/* token_usage_monthly */ val y = 1")
        assertTrue(code.contains("/rest/v1/profiles"))
        assertTrue(!code.contains("app_build") && !code.contains("token_usage_monthly"))
    }

    /** 모든 골든 case 의 Kotlin 녹음에서 profiles·app_build·app_version·token_usage_monthly 쓰기 0. */
    @Test
    fun everyRecordingWritesNothingForbidden() {
        val golden = Golden.load("desktop-work/requests")
        val registry = DesktopWorkRequestsGoldenTest().registry
        val all = mutableListOf<JsonObject>()
        for (c in golden.cases) {
            val call = registry[c.string("id")] ?: continue
            val script = c.array("responses").map { (it as JsonObject).int("status") to it.string("body") }
            all += DesktopWorkRequestsGoldenTest().record(script, call = call).requests
        }
        assertTrue(all.size >= 60, "녹음이 적다(${all.size})")
        val bad = all.filter { r ->
            val text = r.toString()
            forbidden.any { text.contains(it) }
        }
        assertEquals(emptyList(), bad)
    }

    private fun legacy(facts: LegacyHeartbeatFacts): Pair<LegacyHeartbeatPath, List<String>> {
        val recorder = GoldenRecorder(emptyList())
        val (service, client) = recorder.service()
        val host = FakeSessionHost(service)
        val path = runBlocking { host.sendLegacyHeartbeat(facts) }
        client.close()
        return path to recorder.requests.map { (it["path"] as JsonPrimitive).content }
    }

    /** deviceId null 이면 work_status_devices 요청 0(소유·흡수·미확인 모두). 기기 id 가 있으면 나간다(양성 대조). */
    @Test
    fun legacyHeartbeat_nullDeviceWritesNoDeviceRows() {
        val sid = "ab000000-0000-4000-8000-0000000000f6"
        val input = GOLDEN_NOW.addingTimeInterval(-30.0)
        val base = LegacyHeartbeatFacts("team", adopted = false, confirmedSessionId = sid, deviceId = null, ownsStrongly = true,
            awayServerSupported = true, observedInput = input)
        val variants = listOf(base, base.copy(adopted = true), base.copy(confirmedSessionId = null))
        for (v in variants) {
            val (_, paths) = legacy(v)
            assertTrue(paths.none { it.endsWith("/work_status_devices") }, "$v → $paths")
        }
        val (ownerPath, ownerPaths) = legacy(base.copy(deviceId = "win:0f000000-0000-4000-8000-0000000000a7"))
        assertEquals(LegacyHeartbeatPath.HEARTBEAT_AND_DEVICE, ownerPath)
        assertEquals(listOf("/rest/v1/work_statuses", "/rest/v1/work_status_devices"), ownerPaths)
        val (adoptedPath, adoptedPaths) = legacy(base.copy(adopted = true, deviceId = "win:x"))
        assertEquals(LegacyHeartbeatPath.INPUT_ONLY, adoptedPath)
        assertEquals(listOf("/rest/v1/work_status_devices"), adoptedPaths, "⑬ 흡수 중이면 공유 셀 0 · 입력만")
        val (noAway, noAwayPaths) = legacy(base.copy(adopted = true, deviceId = "win:x", awayServerSupported = false))
        assertEquals(LegacyHeartbeatPath.NOTHING, noAway)
        assertEquals(emptyList(), noAwayPaths)
    }

    /** ⑬ 공유 행에는 확인된 세션 id 만(하트비트 본문의 active_session_id = confirmedSessionId). */
    @Test
    fun legacyHeartbeat_carriesOnlyConfirmedSessionId() {
        val recorder = GoldenRecorder(emptyList())
        val (service, client) = recorder.service()
        val host = FakeSessionHost(service)
        runBlocking {
            host.sendLegacyHeartbeat(LegacyHeartbeatFacts("team", false, "confirmed-1", null, false, false, null))
        }
        client.close()
        val body = recorder.requests.single()["body"] as JsonObject
        assertEquals("confirmed-1", (body["active_session_id"] as JsonPrimitive).content)
        assertTrue("last_input_at" !in body, "away 서버 미지원이면 입력 칸을 싣지 않는다")
    }
}
