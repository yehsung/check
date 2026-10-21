// 구조 시험(A§4-6 일곱 줄 + §8-5 운영 구성 + 봉인 보강). 소스를 읽어 판정한다 — 주석은 걷어 내고 본다
// (기억 source-contract-tests-need-comment-stripping: 안 그러면 설명을 지워야만 초록이 된다).
// 운영 주소 규칙만은 주석까지 본다(주석에 적힌 운영 주소도 공개 저장소 유출이다).
//
// 금지 문형 몇 개는 글자를 이어 붙여 만든다: 이 파일 자체가 저장소 비밀 검사(푸시 전 grep)와 이 규칙에 걸리지 않게.
package com.yehsung.aingcheck.testkit.structure

import java.io.File

data class Violation(val rule: String, val file: String, val line: Int, val snippet: String) {
    override fun toString(): String = "[$rule] $file:$line  $snippet"
}

/** multiplatform/ 아래 소스 한 개. [code] 는 주석을 걷어 낸 글자(줄 번호 유지). */
class SourceFile(val relPath: String, val raw: String, val code: String) {
    val module: String = moduleOf(relPath)
    val sourceSet: String? = Regex("""(?:^|/)src/([^/]+)/""").find(relPath)?.groupValues?.get(1)
    val isMainSourceSet: Boolean get() = sourceSet in MAIN_SOURCE_SETS
    val isCode: Boolean get() = relPath.endsWith(".kt") || relPath.endsWith(".kts") || relPath.endsWith(".java")

    companion object {
        val MAIN_SOURCE_SETS = setOf("commonMain", "androidMain", "desktopMain", "main")

        fun moduleOf(relPath: String): String {
            val parts = relPath.split('/')
            return when {
                parts.size >= 2 && parts[0] in setOf("core", "feature") -> parts[0] + "/" + parts[1]
                else -> parts[0]
            }
        }
    }
}

object StructureRules {
    const val R_PREFS = "R1-java-util-prefs"
    const val R_CLOCK = "R2-clock-outside-assembly"
    const val R_OKHTTP = "R3-okhttp-outside-app"
    const val R_RETRY = "R3b-okhttp-retry-on"
    const val R_ROUND = "R4-rounding-in-rules"
    const val R_PROD = "R5-prod-address"
    const val R_PRODCFG = "R5b-prodconfig-outside-app"
    const val R_ENV = "R6-env-local"
    const val R_PHONE = "R7-phone-forbidden"
    const val R_CANARY = "R8-canary-bypass"
    const val R_SLOW = "R9-slow-tag-listing"
    const val R_SPIKES = "R10-spikes-in-settings"

    private val APP_MODULES = setOf("androidApp", "desktopApp")
    private val PHONE_MODULES = setOf("androidApp", "feature/phone")
    private val SCANNED_SUFFIXES = listOf(".kt", ".kts", ".java", ".xml", ".properties", ".toml", ".yml", ".yaml", ".json", ".sh", ".sb", ".pro", ".txt", ".md")
    private val SKIPPED_DIRS = setOf("build", ".gradle", ".kotlin", ".idea", "out")

    /** 운영 주소 문형. 운영 프로젝트 주소는 저장소에 없다 — Gradle 속성으로만 들어온다(§8-5). */
    val PROD_ADDRESS_PATTERNS: List<Regex> = listOf(
        Regex("""[A-Za-z0-9-]+\.supa""" + """base\.(co|in|com)\b"""),
    )

    private val PHONE_FORBIDDEN_RPCS = listOf(
        "take_pokes", "work_tick", "close_abandoned_work_sessions", "ultra_wallet_sync", "buy_ultra",
        "poke_user", "ultra_poke_user", "away_sync",
    )
    private val PHONE_FORBIDDEN_COLUMNS = listOf("app_build", "app_version", "focus_mode")

    // ---------- 수집 ----------

    fun collect(mpRoot: File): List<SourceFile> {
        val out = mutableListOf<SourceFile>()
        mpRoot.walkTopDown()
            .onEnter { dir -> dir == mpRoot || (dir.name !in SKIPPED_DIRS && !(dir.parentFile == mpRoot && dir.name == "spikes")) }
            .filter { it.isFile && SCANNED_SUFFIXES.any { s -> it.name.endsWith(s) } }
            .forEach { file ->
                val rel = file.relativeTo(mpRoot).invariantSeparatorsPath
                val raw = file.readText()
                val code = if (rel.endsWith(".kt") || rel.endsWith(".kts") || rel.endsWith(".java")) stripComments(raw) else raw
                out += SourceFile(rel, raw, code)
            }
        return out.sortedBy { it.relPath }
    }

    /** 생성 소스(build/generated 아래) — 운영 주소는 ProdConfig.kt 에만 있을 수 있다. */
    fun collectGenerated(mpRoot: File): List<SourceFile> {
        val out = mutableListOf<SourceFile>()
        mpRoot.walkTopDown()
            .onEnter { it.name != ".gradle" && it.name != "spikes" }
            .filter { it.isFile && it.invariantSeparatorsPath.contains("/build/generated/") && (it.name.endsWith(".kt") || it.name.endsWith(".java")) }
            .forEach { out += SourceFile(it.relativeTo(mpRoot).invariantSeparatorsPath, it.readText(), it.readText()) }
        return out
    }

    // ---------- 판정 ----------

    class Config(
        /** core/rules 에서 반올림을 써도 되는 파일(상대 경로). */
        val roundingAllowlist: Set<String> = emptySet(),
        /** `@Tag("slow")` 가 붙은 자리 목록(상대 경로, 한 줄에 한 자리). */
        val slowListing: List<String> = emptyList(),
        /** 출시 속성으로 들어온 운영 주소(있으면 그 호스트도 찾는다). */
        val extraProdHosts: List<String> = emptyList(),
    )

    fun check(files: List<SourceFile>, generated: List<SourceFile>, config: Config): List<Violation> {
        val v = mutableListOf<Violation>()
        val prodPatterns = PROD_ADDRESS_PATTERNS + config.extraProdHosts.filter { it.isNotBlank() }.map { Regex(Regex.escape(it)) }
        val slowFound = mutableListOf<String>()

        for (f in files) {
            // 규칙 정의와 그 자기 시험(심은 위반 문형을 글자로 품는다)은 코드 규칙에서 뺀다. 운영 주소(R5)는 그래도 본다.
            val isStructureItself = f.relPath.contains("/com/yehsung/aingcheck/testkit/structure/")
            if (f.isCode && !isStructureItself) {
                // R1: java.util.prefs — 맥 plist·Windows HKCU 에 쓴다(시험 잔재가 cfprefsd 를 죽인 전례).
                findAll(f, Regex("""\bjava\.util\.""" + """prefs\b""")) { v += it.copy(rule = R_PREFS) }

                // R2: 벽시계는 조립 지점(앱 모듈 main)에서만 만든다. 나머지는 주입받는다.
                if (!(f.module in APP_MODULES && f.isMainSourceSet)) {
                    findAll(f, Regex("""\bClock\.""" + """System\b|\bSystem\.""" + """currentTimeMillis\b""")) { v += it.copy(rule = R_CLOCK) }
                }

                // R3: 실서버 엔진(OkHttp)은 앱 모듈 main 에만. 시험 쪽(localhost 실험)은 허용.
                if (f.isMainSourceSet && f.module !in APP_MODULES) {
                    findAll(f, Regex("""\bokhttp3\.|\bio\.ktor\.client\.engine\.okhttp\b|\bOkHttpClient\b|HttpClient\(\s*OkHttp""")) {
                        v += it.copy(rule = R_OKHTTP)
                    }
                }
                // R3b: main 에서 OkHttp 클라이언트를 만들면 같은 파일에 retryOnConnectionFailure(false) 가 있어야 한다(C-X6).
                if (f.isMainSourceSet && Regex("""OkHttpClient\.Builder\(|HttpClient\(\s*OkHttp""").containsMatchIn(f.code) &&
                    !Regex("""retryOnConnectionFailure\(\s*false\s*\)""").containsMatchIn(f.code)
                ) {
                    v += Violation(R_RETRY, f.relPath, 1, "OkHttp 클라이언트를 만들면서 retryOnConnectionFailure(false) 가 없다")
                }

                // R4: core/rules 의 반올림은 허용 목록에만(Swift .rounded() 와 Kotlin round 의 .5 처리가 다르다).
                if (f.module == "core/rules" && f.relPath !in config.roundingAllowlist) {
                    findAll(f, Regex("""\bkotlin\.math\.round\b|\.roundToInt\(|\.roundToLong\(|\bMath\.round\(|\bround\(""")) {
                        v += it.copy(rule = R_ROUND)
                    }
                }

                // R5b: 생성된 운영 구성은 앱 모듈만 읽는다.
                if (f.module !in APP_MODULES && !f.relPath.startsWith("build-logic/") && !f.relPath.startsWith("testkit/")) {
                    findAll(f, Regex("""\bProdConfig\b""")) { v += it.copy(rule = R_PRODCFG) }
                }

                // R6: .env.local 을 통째로 읽지 않는다(service 키가 같이 들어 있다 — 허용 목록 키만, A§6-1).
                findAll(f, Regex("""\.env""" + """\.local\b""")) { v += it.copy(rule = R_ENV) }

                // R7: 폰 금지 호출(RPC 8 · 칸 3)을 폰 모듈 main 이 부르지 않는다.
                if (f.module in PHONE_MODULES && f.isMainSourceSet) {
                    for (name in PHONE_FORBIDDEN_RPCS + PHONE_FORBIDDEN_COLUMNS) {
                        findAll(f, Regex("\"" + Regex.escape(name) + "\"")) { v += it.copy(rule = R_PHONE) }
                    }
                }

                // R8: 트립와이어 통로는 카나리아만 쓴다.
                if (!f.relPath.endsWith("/seal/NetworkCanary.kt") && !f.relPath.contains("/src/tripwire/")) {
                    findAll(f, Regex("""\bcanaryBypass\b""")) { v += it.copy(rule = R_CANARY) }
                }

                // R9: slow 태그 자리 세기.
                Regex("""@Tag\(\s*"slow"\s*\)""").findAll(f.code).forEach { _ -> slowFound += f.relPath }
            }

            // R7(빌드 경계): 폰 모듈·core 는 feature/desktop 에 기대지 않는다(C§3.1).
            if (f.relPath.endsWith("build.gradle.kts") && (f.module in PHONE_MODULES || f.module.startsWith("core/") || f.module == "ui" || f.module == "character")) {
                findAll(f, Regex(""":feature:""" + """desktop\b""")) { v += it.copy(rule = R_PHONE) }
            }

            // R10: spikes 는 이 빌드에 들지 않는다(W0-e 자기 완결 빌드).
            if (f.relPath == "settings.gradle.kts") {
                findAll(f, Regex("""\bspikes\b""")) { v += it.copy(rule = R_SPIKES) }
            }

            // R5: 운영 주소는 저장소 어디에도 없다(주석 포함, 원문으로 본다).
            for (p in prodPatterns) findAllRaw(f, p) { v += it.copy(rule = R_PROD) }
        }

        // R5: 생성 소스 중 ProdConfig.kt 밖에는 운영 주소가 없다.
        for (g in generated) {
            if (g.relPath.endsWith("/ProdConfig.kt")) continue
            for (p in prodPatterns) findAllRaw(g, p) { v += it.copy(rule = R_PROD) }
        }

        // R9: 목록과 실제가 같아야 한다(이름이 바뀌어 조용히 무력화되는 것을 막는다).
        if (slowFound.sorted() != config.slowListing.sorted()) {
            v += Violation(R_SLOW, "testkit/src/desktopTest/resources/structure/slow-tests.txt", 1,
                "목록 ${config.slowListing.sorted()} ≠ 실제 ${slowFound.sorted()}")
        }
        return v
    }

    private fun findAll(f: SourceFile, regex: Regex, sink: (Violation) -> Unit) = scan(f.relPath, f.code, f.raw, regex, sink)
    private fun findAllRaw(f: SourceFile, regex: Regex, sink: (Violation) -> Unit) = scan(f.relPath, f.raw, f.raw, regex, sink)

    private fun scan(rel: String, text: String, raw: String, regex: Regex, sink: (Violation) -> Unit) {
        val rawLines = raw.lines()
        for (m in regex.findAll(text)) {
            val line = text.substring(0, m.range.first).count { it == '\n' } + 1
            sink(Violation("?", rel, line, rawLines.getOrElse(line - 1) { "" }.trim().take(160)))
        }
    }

    /**
     * Kotlin·Java 주석을 걷어 낸다(줄 번호를 지키려고 줄바꿈은 남긴다). 문자열·글자 리터럴은 그대로 둔다.
     * Kotlin 블록 주석은 겹칠 수 있다.
     */
    fun stripComments(src: String): String {
        val out = StringBuilder(src.length)
        var i = 0
        val n = src.length
        while (i < n) {
            val c = src[i]
            val next = if (i + 1 < n) src[i + 1] else '\u0000'
            when {
                c == '/' && next == '/' -> {
                    while (i < n && src[i] != '\n') i++
                }
                c == '/' && next == '*' -> {
                    var depth = 1
                    i += 2
                    while (i < n && depth > 0) {
                        if (src[i] == '/' && i + 1 < n && src[i + 1] == '*') { depth++; i += 2; continue }
                        if (src[i] == '*' && i + 1 < n && src[i + 1] == '/') { depth--; i += 2; continue }
                        if (src[i] == '\n') out.append('\n')
                        i++
                    }
                }
                c == '"' && src.startsWith("\"\"\"", i) -> {
                    val end = src.indexOf("\"\"\"", i + 3).let { if (it < 0) n else it + 3 }
                    out.append(src, i, end)
                    i = end
                }
                c == '"' -> {
                    val start = i
                    i++
                    while (i < n && src[i] != '"' && src[i] != '\n') {
                        if (src[i] == '\\') i++
                        i++
                    }
                    i = minOf(i + 1, n)
                    out.append(src, start, i)
                }
                c == '\'' -> {
                    // 글자 리터럴: '\'' · 'x' · '\u0000'. 짧게 끝나지 않으면 그냥 한 글자로 본다.
                    val close = src.indexOf('\'', i + 1)
                    if (close in (i + 1)..(i + 8) && !src.substring(i + 1, close).contains('\n')) {
                        val end = if (src[i + 1] == '\\' && close == i + 2) src.indexOf('\'', close + 1).let { if (it < 0) close + 1 else it + 1 } else close + 1
                        out.append(src, i, end)
                        i = end
                    } else {
                        out.append(c)
                        i++
                    }
                }
                else -> {
                    out.append(c)
                    i++
                }
            }
        }
        return out.toString()
    }
}
