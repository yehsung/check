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
        ) + StructureRules.HTTP_ENGINE_FACTORY_FILES) {
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
    private val androidAppMain = "androidApp/src/main/kotlin/com/yehsung/aingcheck/android/X.kt"
    private val desktopFactory = "desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/http/HttpEngineFactory.kt"
    private val netMain = "core/net/src/commonMain/kotlin/com/yehsung/aingcheck/core/net/X.kt"
    private val prodHost = "abcd" + ".supa" + "base.co"
    private val okBuilder = "OkHttpClient" + ".Builder()"
    private val retryOff = ".retryOnConnectionFailure" + "(false)"

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

    /**
     * W0 검증(w0-round1 refuted ⑥·issues)이 실제로 빠져나간 모양을 그대로 심는다. 고치기 전 규칙에서는 셋 다 위반 0 이었다.
     * ① 앱 main 의 `okhttp3.OkHttpClient()`(기본 생성자) ② 엔진을 ServiceLoader 로 고르는 `io.ktor.client.HttpClient { }`
     * ③ `client.newBuilder().build()`(복제) — 단일 팩토리 밖이라 R3c, 기본 생성자는 R3b 도.
     */
    @Test
    fun httpEnginesOutsideTheSingleFactoryAreRed() {
        val planted: List<Triple<String, String, String>> = listOf(
            Triple(StructureRules.R_FACTORY, appMain, "val client = okhttp3.OkHttpClient()"),
            Triple(StructureRules.R_RETRY, appMain, "val client = okhttp3.OkHttpClient()"),
            Triple(StructureRules.R_FACTORY, appMain, "val ktor = io.ktor.client.HttpClient { }"),
            Triple(StructureRules.R_FACTORY, appMain, "val c2 = client.newBuilder().build()"),
            Triple(StructureRules.R_FACTORY, androidAppMain, "val ktor = HttpClient()"),
            Triple(StructureRules.R_FACTORY, androidAppMain, "val ktor = HttpClient(OkHttp) { engine { config { $retryOff } } }"),
            Triple(StructureRules.R_FACTORY, androidAppMain, "val e = OkHttp.create { }"),
            Triple(StructureRules.R_FACTORY, androidAppMain, "val c = $okBuilder$retryOff.build()"),
            Triple(StructureRules.R_FACTORY, netMain, "val jdk = java.net.http.HttpClient.newHttpClient()"),
            // 팩토리 안이어도: 재전송을 끌 수 없는 기본 생성자·재전송 켬·retry(false) 없는 빌더는 R3b.
            Triple(StructureRules.R_RETRY, desktopFactory, "val c = okhttp3.OkHttpClient()"),
            Triple(StructureRules.R_RETRY, desktopFactory, "val c = $okBuilder.retryOnConnectionFailure(true).build()"),
            Triple(StructureRules.R_RETRY, desktopFactory, "val c = $okBuilder.build()"),
            // main 소스셋은 허용 목록이 아니라 '시험이 아닌 것 전부'(jvmSharedMain 에 심은 OkHttp 가 빠져나갔었다).
            Triple(StructureRules.R_OKHTTP, "core/net/src/jvmSharedMain/kotlin/com/yehsung/aingcheck/core/net/X.kt", "val c = $okBuilder.build()"),
            Triple(StructureRules.R_FACTORY, "core/net/src/jvmSharedMain/kotlin/com/yehsung/aingcheck/core/net/X.kt", "val k = HttpClient(OkHttp)"),
            // 폰 금지 RPC: 문자열 안 경로·템플릿 꼴(전엔 통째 문자열 `"take_pokes"` 만 잡았다).
            Triple(StructureRules.R_PHONE, phone, "c.post(\"https://aingcheck.invalid/rest/v1/rpc/take" + "_pokes\")"),
            Triple(StructureRules.R_PHONE, phone, "c.post(\"\${base}/rpc/ultra_wallet" + "_sync\")"),
            Triple(StructureRules.R_PHONE, phone, "val p = \"\"\"rpc/poke" + "_user\"\"\""),
            Triple(StructureRules.R_PHONE, "feature/phone/src/androidRelease/kotlin/X.kt", "rpc(\"away" + "_sync\")"),
        )
        for ((rule, path, body) in planted) {
            val found = plant(mapOf(path to body))
            assertTrue(rule in found, "규칙 $rule 이 심은 위반을 못 잡았다: $path ← $body → $found")
        }
    }

    @Test
    fun theFactoryItselfAndInjectedEnginesStayGreen() {
        val ok = mapOf(
            desktopFactory to "object HttpEngineFactory {\n private val base = $okBuilder$retryOff.build()\n" +
                " fun okHttpClient() = base\n fun ktorClient(): HttpClient = HttpClient(OkHttp) { engine { preconfigured = base } }\n}",
            // core/net 은 주입받은 엔진으로 짓는다 · 반환형 자리의 `: HttpClient {` 는 생성이 아니다.
            netMain to "class Net(engine: HttpClientEngine) {\n val c = HttpClient(engine) { expectSuccess = false }\n fun make(): HttpClient {\n  return c\n }\n}",
            // 낱말 경계: 다른 이름 속의 조각·p_ 칸은 걸리지 않는다. 시험 소스셋(test·…Test)은 실험 자리다.
            phone to "val a = \"take" + "_pokes_count\"\nval b = \"p_app" + "_build\"",
            "androidApp/src/test/kotlin/X.kt" to "val c = okhttp3.OkHttpClient()\nval k = HttpClient { }",
            "androidApp/src/androidTest/kotlin/X.kt" to "val c = $okBuilder.build()",
            "core/net/src/desktopTest/kotlin/X.kt" to "val c = client.newBuilder().build()",
        )
        assertEquals(emptySet(), plant(ok), "허용된 자리가 걸렸다")
    }

    @Test
    fun stringLiteralScannerSeesPathsTemplatesAndRawStrings() {
        val code = "val a = \"x/rpc/y\" + 'q' + '\"'\nval b = \"\${f(\"in\")}/tail\"\nval c = \"\"\"raw \$x\"\"\""
        val bodies = StructureRules.stringLiterals(code).map { it.second }
        assertEquals(listOf("x/rpc/y", "\${f(\"in\")}/tail", "raw \$x"), bodies)
    }

    @Test
    fun allowedPlacesAndCommentsDoNotTrip() {
        val ok = mapOf(
            // 주석 속 설명은 코드 규칙에 걸리지 않는다(운영 주소 R5 만 주석까지 본다).
            main to "// java.util." + "prefs 는 금지 · Clock." + "System 금지\n/* okhttp3" + ". 설명 */ val a = 1",
            // 조립 지점(앱 main)은 벽시계를, 앱의 단일 HTTP 팩토리 파일은 OkHttp(retry 끔)를 쓸 수 있다.
            appMain to "val t = Clock." + "System",
            desktopFactory to "val c = OkHttpClient" + ".Builder().retryOnConnectionFailure(false).build()",
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
