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
    val isMainSourceSet: Boolean get() = isMainSourceSetName(sourceSet)
    val isCode: Boolean get() = relPath.endsWith(".kt") || relPath.endsWith(".kts") || relPath.endsWith(".java")

    companion object {
        /**
         * 시험 소스셋이 아니면 전부 main 으로 본다(허용 목록이 아니라 거부 목록 — W0 검증: 이름 목록 밖의 `jvmSharedMain`
         * 같은 main 소스셋이 시험 쪽으로 빠져 R3·R3b·R7 이 꺼졌다). 시험 = 이름이 `test` 이거나 `Test` 로 끝난다
         * (`desktopTest`·`androidHostTest`·`androidTest`·`androidDeviceTest`…). `src/` 밖 파일(build.gradle.kts 등)은 null.
         */
        fun isMainSourceSetName(name: String?): Boolean = name != null && name != "test" && !name.endsWith("Test")

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
    const val R_FACTORY = "R3c-http-engine-outside-factory"
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

    /**
     * 앱의 HTTP 엔진을 만드는 **단일 팩토리 파일**(G §8-12, C-X6). 앱 모듈마다 한 파일이고, 그 밖의 main 에서는
     * 엔진·클라이언트를 만들지 않는다(주입받은 엔진으로 `HttpClient(engine)` 을 짓는 것은 된다).
     * 팩토리가 만든 클라이언트의 재전송 끔은 앱 시험이 **실행해서** 단언한다: 끊긴 연결 재현으로 POST 도착 수
     * (desktopApp·androidApp 호스트 `HttpEngineFactoryTest` — OkHttp·Ktor 둘 다) + 기기(ART) 위 `retryOnConnectionFailure == false`.
     */
    val HTTP_ENGINE_FACTORY_FILES: Set<String> = setOf(
        "androidApp/src/main/kotlin/com/yehsung/aingcheck/android/http/HttpEngineFactory.kt",
        "desktopApp/src/main/kotlin/com/yehsung/aingcheck/desktop/http/HttpEngineFactory.kt",
    )

    private const val KTOR_ENGINES = """(?:OkHttp|CIO|Java|Apache5?|Android|Jetty|Curl|WinHttp|Darwin)"""

    /**
     * 엔진·클라이언트를 **만드는** 모양(팩토리 밖 main 이면 빨강).
     * `OkHttpClient(`(기본 생성자 — 재전송 켜짐) · `OkHttpClient.Builder(` · `.newBuilder(`(기존 클라이언트 복제 — 설정을 바꿀 수 있다) ·
     * 인자 없는 `HttpClient {`/`HttpClient()`(Ktor 가 ServiceLoader 로 엔진을 고른다) · `HttpClient(OkHttp…)` 처럼 엔진을 고르는 꼴 ·
     * `OkHttp.create(`·`OkHttp.create {` 같은 엔진 직접 생성 · JDK `HttpClient.newHttpClient(`.
     * 반환형 자리의 `: HttpClient {`(함수 본문)는 생성이 아니다 — 앞의 `:` 로 가른다.
     */
    private val ENGINE_CREATION = Regex(
        """\bOkHttpClient\s*\(""" +
            """|\bOkHttpClient\s*\.\s*Builder\s*\(""" +
            """|\.\s*newBuilder\s*\(""" +
            """|(?<!:\s{0,4})\bHttpClient\s*\{""" +
            """|\bHttpClient\s*\(\s*\)""" +
            """|\bHttpClient\s*\(\s*""" + KTOR_ENGINES + """\b""" +
            """|\b""" + KTOR_ENGINES + """\s*\.\s*create\s*[({]""" +
            """|\bOkHttpEngine\s*\(""" +
            """|\bHttpClient\s*\.\s*newHttpClient\s*\(""",
    )

    /** OkHttp 클라이언트를 짓는 모양(R3b: 이 파일에 retryOnConnectionFailure(false) 가 있어야 한다). */
    private val OKHTTP_BUILD = Regex("""\bOkHttpClient\s*\.\s*Builder\s*\(|\bHttpClient\s*\(\s*OkHttp\b|\bOkHttp\s*\.\s*create\s*[({]""")
    /** 재전송을 끌 수 없는 기본 생성자, 또는 재전송을 켜는 꼴(R3b: 어디서든 빨강). */
    private val OKHTTP_RETRY_ON = Regex("""\bOkHttpClient\s*\(\s*\)|\bretryOnConnectionFailure\s*(?:\(\s*true\b|=\s*true\b)""")

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
                // R3b: main 에서 OkHttp 클라이언트를 지으면 같은 파일에 retryOnConnectionFailure(false) 가 있어야 하고(C-X6),
                // 재전송을 끌 수 없는 기본 생성자 `OkHttpClient()` 와 재전송을 켜는 꼴은 어디서든 빨강이다.
                // 파일 단위 판정이라 한 파일 안 여러 빌더를 하나하나 가르지 못한다 — 그 몫은 팩토리 런타임 시험이 진다.
                if (f.isMainSourceSet) {
                    if (OKHTTP_BUILD.containsMatchIn(f.code) && !Regex("""retryOnConnectionFailure\(\s*false\s*\)""").containsMatchIn(f.code)) {
                        v += Violation(R_RETRY, f.relPath, 1, "OkHttp 클라이언트를 만들면서 retryOnConnectionFailure(false) 가 없다")
                    }
                    findAll(f, OKHTTP_RETRY_ON) { v += it.copy(rule = R_RETRY) }
                }

                // R3c: HTTP 엔진·클라이언트는 앱 모듈의 단일 팩토리 파일에서만 만든다(G §8-12). 시험 소스셋은 실험(localhost)이라 뺀다.
                if (f.isMainSourceSet && f.relPath !in HTTP_ENGINE_FACTORY_FILES) {
                    findAll(f, ENGINE_CREATION) { v += it.copy(rule = R_FACTORY) }
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
                //  - RPC 이름은 문자열 리터럴 **안 어디든** 낱말로 있으면 빨강(`"take_pokes"` · `"…/rest/v1/rpc/take_pokes"` ·
                //    `"$base/rpc/take_pokes"`). W0 검증에서 경로 문자열 꼴이 빠져나갔다.
                //  - 칸 이름은 통째 문자열만 본다(`"p_app_build"`·select 목록 읽기는 금지가 아니다).
                //  다른 모듈 상수를 거쳐 부르는 꼴은 정적으로 못 잡는다 — 런타임 그물(PhoneForbiddenCalls + MockRouter)이 W2 폰 스토어 시험에 필수다.
                if (f.module in PHONE_MODULES && f.isMainSourceSet) {
                    val literals = stringLiterals(f.code)
                    for (name in PHONE_FORBIDDEN_RPCS) {
                        val word = Regex("""(?<![A-Za-z0-9_])""" + Regex.escape(name) + """(?![A-Za-z0-9_])""")
                        for ((offset, body) in literals) {
                            if (word.containsMatchIn(body)) v += violationAt(f, offset, R_PHONE)
                        }
                    }
                    for (name in PHONE_FORBIDDEN_COLUMNS) {
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

    private fun violationAt(f: SourceFile, offset: Int, rule: String): Violation {
        val line = f.code.substring(0, offset.coerceIn(0, f.code.length)).count { it == '\n' } + 1
        return Violation(rule, f.relPath, line, f.raw.lines().getOrElse(line - 1) { "" }.trim().take(160))
    }

    /**
     * 주석을 걷은 코드에서 문자열 리터럴을 (여는 따옴표 위치, 본문) 으로 낸다. Kotlin 원시 문자열(`"""`)·Java 글 블록 포함.
     * 템플릿 `${…}` 안의 글자(중첩 문자열 포함)도 본문에 든다 — 판정이 넓어질 뿐 좁아지지 않는다.
     */
    fun stringLiterals(code: String): List<Pair<Int, String>> {
        val out = mutableListOf<Pair<Int, String>>()
        var i = 0
        val n = code.length
        while (i < n) {
            val c = code[i]
            when {
                c == '"' && code.startsWith("\"\"\"", i) -> {
                    val end = code.indexOf("\"\"\"", i + 3).let { if (it < 0) n else it }
                    out += i to code.substring(i + 3, end)
                    i = minOf(n, end + 3)
                }
                c == '"' -> {
                    val end = endOfQuoted(code, i)
                    out += i to code.substring(i + 1, end).removeSuffix("\"")
                    i = maxOf(end, i + 1)
                }
                c == '\'' -> {
                    // 글자 리터럴('"' · '\'' · 'x')을 건너뛴다 — 안의 따옴표를 문자열 시작으로 읽지 않게.
                    val close = code.indexOf('\'', i + 1)
                    i = if (close in (i + 1)..(i + 8) && !code.substring(i + 1, close).contains('\n')) {
                        if (code[i + 1] == '\\' && close == i + 2) code.indexOf('\'', close + 1).let { if (it < 0) close + 1 else it + 1 } else close + 1
                    } else {
                        i + 1
                    }
                }
                else -> i++
            }
        }
        return out
    }

    /** `"` 로 여는 한 줄 문자열의 끝(닫는 따옴표 다음, 닫히지 않았으면 줄 끝). 템플릿 `${…}` 의 중괄호·중첩 문자열을 건너뛴다. */
    private fun endOfQuoted(s: String, start: Int): Int {
        var i = start + 1
        val n = s.length
        while (i < n) {
            val c = s[i]
            when {
                c == '\\' -> i += 2
                c == '"' -> return i + 1
                c == '\n' -> return i
                c == '$' && i + 1 < n && s[i + 1] == '{' -> {
                    var depth = 1
                    i += 2
                    while (i < n && depth > 0) {
                        when (s[i]) {
                            '{' -> { depth++; i++ }
                            '}' -> { depth--; i++ }
                            '"' -> i = maxOf(endOfQuoted(s, i), i + 1)
                            '\n' -> return i
                            else -> i++
                        }
                    }
                }
                else -> i++
            }
        }
        return n
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
