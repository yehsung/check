// W3-c5 완료 기준: UpdateRpcStructureTest — 구조 시험 ⑦(shell.md §5 · 조정자 메모).
// desktopApp·feature/desktop 의 시험 아닌 소스(주석 걷고)에서:
//   ⑦-a 맥 전용 RPC `app_latest_release`·`app_current_notice`(플랫폼 없는 판)와 그 Kotlin 감싸개 `fetchLatestRelease`·`appCurrentNotice` 0건.
//   ⑦-b `client_release`·`app_current_notice_for` 를 직접 치는 자리 0건 — 공용 패치 1·2 뒤 shell/update 도 공용 함수(fetchClientRelease ·
//       appCurrentNoticeFor)만 부른다(옛 허용 자리 정리).
//   ⑦-c 새 버전 판정 `latestBuild >` 는 핀 DesktopUpdateState.kt 한 줄뿐(점·배너는 updateAvailable 만 읽는다).
// 심은 줄로 스캐너가 실제로 빨개지는지, 주석 안의 같은 글자는 세지 않는지 같이 잰다(빈 목록 초록 방지 기준선 포함).
package com.yehsung.aingcheck.desktop.shell.update

import com.yehsung.aingcheck.testkit.structure.SourceFile
import com.yehsung.aingcheck.testkit.structure.StructureRules
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class UpdateRpcStructureTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 없음(test-seal)" })

    private fun mainSources(): List<Pair<String, String>> = SCANNED_SRC_ROOTS.flatMap { root ->
        File(mpRoot, root).listFiles().orEmpty()
            .filter { it.isDirectory && SourceFile.isMainSourceSetName(it.name) }
            .flatMap { set ->
                set.walkTopDown().filter { it.isFile && (it.extension == "kt" || it.extension == "java") }
                    .map { it.relativeTo(mpRoot).invariantSeparatorsPath to StructureRules.stripComments(it.readText()) }
                    .toList()
            }
    }

    @Test
    fun rule7WindowsCallsOnlyWindowsReleaseAndNoticeRpcs() {
        val files = mainSources()
        assertEquals(emptyList(), violations(files), "⑦ 위반")
    }

    @Test
    fun baselineScannerSeesThisLane() {
        val files = mainSources()
        assertTrue(files.size > 20, "스캔 대상이 너무 적다: ${files.size}")
        assertTrue(
            files.any { (path, code) -> path.startsWith(UPDATE_DIR) && Regex("""\bappCurrentNoticeFor\b""").containsMatchIn(code) },
            "shell/update 의 공용 함수 호출이 스캔에 보여야 한다",
        )
        assertTrue(files.any { (path, code) -> path == PIN_FILE && Regex("""\blatestBuild\s*>""").containsMatchIn(code) })
    }

    @Test
    fun plantedLinesTurnRed() {
        val elsewhere = "desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/pages/x/Planted.kt"
        val planted = listOf(
            """val d = service.send("/rest/v1/rpc/app_latest_release", "POST", emptyList(), null, null, null)""",
            """val d = service.send("/rest/v1/rpc/app_current_notice", "POST", emptyList(), null, null, null)""",
            """val r = service.fetchLatestRelease()""",
            """val n = service.appCurrentNotice()""",
            """val ref = SupabaseWorkService::appCurrentNotice""",
            """const val P = "/rest/v1/rpc/app_current_notice_for"""",
            """const val P = "/rest/v1/rpc/client_release"""",
            """val dot = s.latestBuild!! > s.currentBuild""",
        )
        for (line in planted) {
            val code = StructureRules.stripComments("package p\n$line\n")
            assertEquals(1, violations(listOf(elsewhere to code)).size, "심은 줄을 못 잡았다: $line")
        }
        // 주석 안의 글자는 세지 않는다(소스 계약 시험은 주석을 걷는다).
        val commented = StructureRules.stripComments("// app_latest_release · appCurrentNotice()\n/* app_current_notice */\nval x = 1\n")
        assertEquals(emptyList(), violations(listOf(elsewhere to commented)))
        // 허용된 한 곳: 핀의 판정 한 줄 · shell/update 의 공용 함수 호출. 옛 허용 자리(shell/update 의 RPC 경로 직접)는 이제 빨강이다.
        val allowed = listOf(
            "${UPDATE_DIR}Rpc.kt" to "val r = service.fetchClientRelease(platform)\nval n = service.appCurrentNoticeFor(platform)\n",
            PIN_FILE to "val u = latestBuild != null && latestBuild > currentBuild\n",
        )
        assertEquals(emptyList(), violations(allowed))
        assertEquals(2, violations(listOf("${UPDATE_DIR}Rpc.kt" to "const val A = \"/rest/v1/rpc/app_current_notice_for\"\nconst val B = \"/rest/v1/rpc/client_release\"\n")).size)
        // 허용된 자리라도 맥 전용 RPC 는 안 된다.
        assertEquals(1, violations(listOf("${UPDATE_DIR}Rpc.kt" to "val r = service.fetchLatestRelease()\n")).size)
    }

    companion object {
        val SCANNED_SRC_ROOTS: List<String> = listOf("desktopApp/src", "feature/desktop/src")
        const val UPDATE_DIR: String = "desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/shell/update/"
        const val PIN_FILE: String = "desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/shellapi/DesktopUpdateState.kt"

        /** ⑦-a: 어디에도 없어야 한다. `\b` 라 `app_current_notice_for`·`appCurrentNoticeFor` 는 걸리지 않는다. */
        val FORBIDDEN: List<Regex> = listOf(
            Regex("""\bapp_latest_release\b"""),
            Regex("""\bapp_current_notice\b"""),
            Regex("""\bfetchLatestRelease\b"""),
            Regex("""\bappCurrentNotice\b"""),
            // ⑦-b(공용 패치 1·2 뒤): RPC 경로 직접 치기 0 — 공용 함수만.
            Regex("""\bapp_current_notice_for\b"""),
            Regex("""\bclient_release\b"""),
        )

        /** ⑦-b·⑦-c: 이 글자가 나와도 되는 자리(접두사). */
        val ONE_PLACE: List<Pair<Regex, String>> = listOf(
            Regex("""\blatestBuild\s*(?:!!\s*)?>""") to PIN_FILE,
        )

        fun violations(files: List<Pair<String, String>>): List<String> {
            val out = mutableListOf<String>()
            for ((path, code) in files) {
                for (re in FORBIDDEN) re.findAll(code).forEach { out += "$path: ${it.value}" }
                for ((re, allowed) in ONE_PLACE) {
                    if (path.startsWith(allowed)) continue
                    re.findAll(code).forEach { out += "$path: ${it.value}" }
                }
            }
            return out
        }
    }
}
