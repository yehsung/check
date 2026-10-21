package com.yehsung.aingcheck.testkit.structure

import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 구조 시험(A§4-6 + §8-5). ① 실제 multiplatform/ 트리에 위반 0 ② 규칙마다 심은 위반을 잡는다(빈 초록 방지).
 * 판정 대상 목록이 비어 초록이 되지 않게, 꼭 있어야 할 파일을 실제로 읽었는지도 센다.
 */
class StructureTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 가 없다" })

    private fun listing(name: String): List<String> =
        requireNotNull(javaClass.getResource("/structure/$name")) { "목록 파일이 없다: $name" }
            .readText().lines().map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("#") }

    private fun config() = StructureRules.Config(
        roundingAllowlist = listing("rounding-allowlist.txt").toSet(),
        slowListing = listing("slow-tests.txt"),
        extraProdHosts = listOfNotNull(
            System.getProperty("aingcheck.prodUrlForScan")?.takeIf { it.isNotBlank() }?.let { java.net.URI(it).host },
        ),
    )

    @Test
    fun realTreeHasNoStructureViolations() {
        val files = StructureRules.collect(mpRoot)
        val paths = files.map { it.relPath }.toSet()
        for (must in listOf(
            "settings.gradle.kts",
            "androidApp/build.gradle.kts",
            "feature/phone/build.gradle.kts",
            "core/foundation/src/commonMain/kotlin/com/yehsung/aingcheck/core/foundation/platform/PlatformContracts.kt",
        )) {
            assertTrue(must in paths, "구조 시험이 '$must' 를 읽지 않았다(수집 범위가 비었나?) — 읽은 파일 ${files.size}개")
        }
        val generated = StructureRules.collectGenerated(mpRoot)
        val violations = StructureRules.check(files, generated, config())
        println("AINGCHECK-STRUCTURE files=${files.size} generated=${generated.size} violations=${violations.size}")
        assertEquals(emptyList(), violations.map { it.toString() }, "구조 위반")
    }

    // ---------- 심은 위반 ----------

    private fun plant(files: Map<String, String>, generated: Map<String, String> = emptyMap(), cfg: StructureRules.Config = StructureRules.Config()): Set<String> {
        val dir = Files.createTempDirectory("aingcheck-structure").toFile()
        try {
            for ((rel, body) in files) File(dir, rel).apply { parentFile.mkdirs(); writeText(body) }
            for ((rel, body) in generated) File(dir, rel).apply { parentFile.mkdirs(); writeText(body) }
            return StructureRules.check(StructureRules.collect(dir), StructureRules.collectGenerated(dir), cfg).map { it.rule }.toSet()
        } finally {
            dir.deleteRecursively()
        }
    }

    private val main = "core/stores/src/commonMain/kotlin/com/yehsung/aingcheck/core/stores/X.kt"
    private val rules = "core/rules/src/commonMain/kotlin/com/yehsung/aingcheck/core/rules/X.kt"
    private val phone = "feature/phone/src/commonMain/kotlin/com/yehsung/aingcheck/feature/phone/X.kt"
    private val appMain = "desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/X.kt"
    private val prodHost = "abcd" + ".supa" + "base.co"

    @Test
    fun eachRuleCatchesAPlantedViolation() {
        val cases: List<Pair<String, Map<String, String>>> = listOf(
            StructureRules.R_PREFS to mapOf(main to "val p = java.util." + "prefs.Preferences.userRoot()"),
            StructureRules.R_CLOCK to mapOf(main to "val t = Clock." + "System.now()"),
            StructureRules.R_CLOCK to mapOf(main to "val t = System." + "currentTimeMillis()"),
            StructureRules.R_OKHTTP to mapOf(main to "import okhttp3" + ".OkHttpClient"),
            StructureRules.R_RETRY to mapOf(appMain to "val c = OkHttpClient" + ".Builder().build()"),
            StructureRules.R_ROUND to mapOf(rules to "val r = x.round" + "ToInt()"),
            StructureRules.R_PROD to mapOf(main to "// https://$prodHost/rest/v1"),
            StructureRules.R_PRODCFG to mapOf(main to "val u = Prod" + "Config.SUPABASE_URL"),
            StructureRules.R_ENV to mapOf(main to "val f = File(\".env" + ".local\")"),
            StructureRules.R_PHONE to mapOf(phone to "rpc(\"take" + "_pokes\")"),
            StructureRules.R_PHONE to mapOf(phone to "put(\"app" + "_build\", 3)"),
            StructureRules.R_PHONE to mapOf("androidApp/build.gradle.kts" to "dependencies { implementation(project(\":feature:" + "desktop\")) }"),
            StructureRules.R_CANARY to mapOf(main to "NetworkTripwire.canary" + "Bypass { }"),
            StructureRules.R_SLOW to mapOf("ui/src/desktopTest/kotlin/X.kt" to "@Tag(\"slow\") class X"),
            StructureRules.R_SPIKES to mapOf("settings.gradle.kts" to "include(\":spikes:windows\")"),
        )
        for ((rule, files) in cases) {
            val found = plant(files)
            assertTrue(rule in found, "규칙 $rule 이 심은 위반을 못 잡았다: $files → $found")
        }
        // 생성 소스: ProdConfig.kt 밖의 생성 파일에 운영 주소가 있으면 빨강, ProdConfig.kt 안이면 통과.
        val gen = "desktopApp/build/generated/aingcheck/prodConfig/main/com/yehsung/aingcheck/desktop/generated"
        assertTrue(StructureRules.R_PROD in plant(emptyMap(), mapOf("$gen/Other.kt" to "const val U = \"https://$prodHost\"")))
        assertEquals(emptySet(), plant(emptyMap(), mapOf("$gen/ProdConfig.kt" to "const val U = \"https://$prodHost\"")))
    }

    @Test
    fun allowedPlacesAndCommentsDoNotTrip() {
        val ok = mapOf(
            // 주석 속 설명은 코드 규칙에 걸리지 않는다(운영 주소 R5 만 주석까지 본다).
            main to "// java.util." + "prefs 는 금지 · Clock." + "System 금지\n/* okhttp3" + ". 설명 */ val a = 1",
            // 조립 지점(앱 main)은 벽시계·OkHttp(retry 끔)를 쓸 수 있다.
            appMain to "val t = Clock." + "System\nval c = OkHttpClient" + ".Builder().retryOnConnectionFailure(false).build()",
            // 시험 쪽 OkHttp(localhost 실험)는 허용.
            "core/net/src/desktopTest/kotlin/X.kt" to "import okhttp3" + ".OkHttpClient",
            // 폰 모듈의 p_app_build 는 금지 칸이 아니다.
            phone to "put(\"p_app" + "_build\", 3)",
            rules to "val s = \"// not a comment\"",
        )
        assertEquals(emptySet(), plant(ok), "허용된 자리가 걸렸다")
        assertEquals(emptySet(), plant(mapOf(rules to "val r = x.round" + "ToInt()"), cfg = StructureRules.Config(roundingAllowlist = setOf(rules))))
    }

    @Test
    fun commentStripperKeepsStringsAndLines() {
        val src = "val a = \"// keep\" // drop\n/* drop\n /* nested */ still */ val b = '/'\nval c = \"\"\"/* keep */\"\"\""
        val out = StructureRules.stripComments(src)
        assertTrue("\"// keep\"" in out && "drop" !in out && "nested" !in out && "/* keep */" in out && "'/'" in out, out)
        assertEquals(src.count { it == '\n' }, out.count { it == '\n' }, "줄 수가 바뀌었다")
    }
}
