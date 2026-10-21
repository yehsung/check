package com.yehsung.aingcheck.testkit.golden

import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.structure.StructureRules
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 양쪽 잠금의 Kotlin 쪽(A§4-2 · K1): `contract/golden` 의 **모든 계약 골든에 소비 시험이 있다**(미소비 금지).
 * Swift 쪽 짝은 고아 금지(GoldenExportBase.manifestMatchesFiles · scripts/golden-export.sh 의 영수증 검사)다.
 *
 * 소비 = 시험 소스셋(src 아래 이름이 Test 로 끝나는 폴더 · src/test)의 **주석 밖 코드**에 `Golden.load("<이름>")` 가 글자 그대로 있는 것.
 * 반대로 목록에 없는 이름을 읽는 시험(지운 골든을 아직 읽는 시험)도 빨강이다. 목록은 `_manifest.json`(생성물)이다.
 */
class GoldenCoverageTest {
    private val repoRoot = File(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 가 없다" })
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 가 없다" })

    private val loadCall = Regex("""\bGolden\s*\.\s*load\s*\(\s*"([^"\\]+)"\s*\)""")

    private fun manifest(): JsonObject = Json.parseToJsonElement(RepoFiles.readText("${Golden.CONTRACT_DIR}/_manifest.json")).jsonObject

    private fun manifestGoldens(m: JsonObject): Map<String, String> =
        m["goldens"]!!.jsonArray.associate { e -> e.jsonObject.string("golden") to e.jsonObject.string("path") }

    /** 시험 소스셋 이름: commonTest · desktopTest · androidHostTest · androidDeviceTest … 와 Android 앱 모듈의 test. */
    private fun isTestSource(relPath: String): Boolean {
        val parts = relPath.split('/')
        val src = parts.indexOf("src")
        if (src < 0 || src + 1 >= parts.size) return false
        val set = parts[src + 1]
        return set == "test" || set.endsWith("Test")
    }

    fun consumedNames(): Map<String, List<String>> {
        val out = mutableMapOf<String, MutableList<String>>()
        for (f in StructureRules.collect(mpRoot)) {
            if (!f.relPath.endsWith(".kt") || !isTestSource(f.relPath)) continue
            for (m in loadCall.findAll(f.code)) out.getOrPut(m.groupValues[1]) { mutableListOf() } += f.relPath
        }
        return out
    }

    companion object {
        /** 문제 목록(빈 목록이면 통과). 시험과 대조 시험이 같은 판정을 쓴다. */
        fun coverageProblems(listed: Set<String>, consumed: Set<String>): List<String> =
            (listed - consumed).sorted().map { "미소비: 골든 '$it' 를 Golden.load 하는 Kotlin 시험이 없다" } +
                (consumed - listed).sorted().map { "목록 밖: Kotlin 시험이 '$it' 를 읽는데 _manifest.json 에 없다" }
    }

    @Test
    fun everyContractGoldenHasAKotlinConsumer() {
        val listed = manifestGoldens(manifest()).keys
        assertTrue("rng/splitmix64" in listed, "견본 골든이 목록에 없다 — 목록을 못 읽었나")
        val consumed = consumedNames()
        val problems = coverageProblems(listed, consumed.keys)
        assertEquals(emptyList(), problems, problems.joinToString("\n"))
        println("AINGCHECK-GOLDEN-COVERAGE listed=${listed.size} consumed=${consumed.keys.size} " +
            consumed.entries.joinToString { "${it.key}<-${it.value.size}" })
    }

    @Test
    fun manifestListsExactlyTheGoldenFilesOnDisk() {
        val dir = File(repoRoot, Golden.CONTRACT_DIR)
        val onDisk = dir.walkTopDown().filter { it.isFile && it.name.endsWith(".json") }
            .map { it.relativeTo(repoRoot).invariantSeparatorsPath }
            .filter { !it.endsWith("/_manifest.json") && !it.endsWith("/_digests.json") }
            .toSet()
        val listed = manifestGoldens(manifest()).values.toSet()
        assertTrue(onDisk.isNotEmpty(), "contract/golden 에 골든 파일이 하나도 없다")
        assertEquals(listed, onDisk, "목록과 디스크가 다르다 — 고아 ${(onDisk - listed).sorted()} · 목록만 ${(listed - onDisk).sorted()}")
        for (name in manifestGoldens(manifest()).keys) Golden.load(name)   // 머리말까지 읽힌다
    }

    /** 대조(기준선이 다른 입력): 소비 하나를 빼거나 없는 이름을 읽으면 각각 잡힌다. 주석 속 호출은 소비가 아니다. */
    @Test
    fun plantedGapsAreCaught() {
        val listed = manifestGoldens(manifest()).keys
        val consumed = consumedNames().keys
        val dropped = coverageProblems(listed, consumed - "rng/splitmix64")
        assertTrue(dropped.any { it.startsWith("미소비") && "rng/splitmix64" in it }, "소비를 빼도 초록이다: $dropped")
        val extra = coverageProblems(listed, consumed + "rng/gone")
        assertTrue(extra.any { it.startsWith("목록 밖") && "rng/gone" in it }, "목록 밖 이름을 읽어도 초록이다: $extra")
        val commented = StructureRules.stripComments("val a = 1 // Golden.load(\"rng/x\")\n/* Golden.load(\"rng/y\") */\n")
        assertTrue(loadCall.findAll(commented).none(), "주석 속 Golden.load 를 소비로 셌다")
        assertTrue(loadCall.findAll("Golden.load(\"rng/z\")").any(), "코드의 Golden.load 를 못 셌다(정규식이 비었나)")
    }
}
