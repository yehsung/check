// W1-e 완료 기준 ②: Swift 가 쓰는 SF Symbols → Material Symbols 대응표에서 빠진 이름 0.
//
// Swift 원문(Sources/**/*.swift — 맥 check·CheckCore + 폰 CheckMobileKit·CheckMobileShared·CheckWidgetsKit)을 주석을 걷어 읽고 기호 이름을 모은다:
//  (1) 기호 문맥: 같은 줄에서 systemName·systemImage·systemSymbolName·symbol·icon·glyph 뒤에 오는 기호 꼴 글자(`cond ? "a" : "b"` 도 둘 다)
//  (2) 점 붙은 기호 꼴 글자 전부(`case .x: return "clock.fill"` 처럼 문맥 낱말이 없는 줄) — 기호가 아닌 점 글자는 NOT_SYMBOLS 에 이유와 함께 적는다
//  (3) 문맥 낱말도 점도 없는 간접 기호(낱말 하나 — 지금은 없다)는 INDIRECT 에 적고, 원문에 아직 있는지 되묻는다
// 판정: 모은 이름 전부가 SfSymbols.toAppIcon 에 있다(빠짐 0) · 표의 이름 전부가 원문에 있다(고아 0).
// 기준 집합은 이 맥의 CoreGlyphs 이름표(name_availability.plist 9,524개)로 저장소 밖에서 한 번 대조해 161개로 확정했다(보고서 근거).
package com.yehsung.aingcheck.ui.icons

import com.yehsung.aingcheck.ui.theme.SwiftPalette
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SfSymbolCoverageTest {
    private val repoRoot = File(requireNotNull(System.getProperty("aingcheck.repoRoot")))

    private fun swiftSources(): List<Pair<String, String>> {
        val root = File(repoRoot, "Sources")
        val files = root.walkTopDown().filter { it.isFile && it.name.endsWith(".swift") }.sortedBy { it.path }.toList()
        return files.map { it.relativeTo(repoRoot).invariantSeparatorsPath to SwiftPalette.stripComments(it.readText()) }
    }

    @Test
    fun everySymbolUsedInSwiftIsMappedAndNoMappingIsOrphan() {
        val sources = swiftSources()
        assertTrue(sources.size > 300, "Swift 원문을 ${sources.size}개만 읽었다 — 저장소 뿌리를 못 찾는다")
        val used = SfSymbolScan.scan(sources)
        assertTrue(used.size >= 150, "모은 기호가 ${used.size}개뿐 — 수집기가 원문을 못 읽는다")
        val missing = used.keys - SfSymbols.toAppIcon.keys
        assertTrue(
            missing.isEmpty(),
            "대응표에 빠진 SF 기호 ${missing.size}개(아이콘이면 SfSymbols 에, 기호가 아니면 SfSymbolScan.NOT_SYMBOLS 에):\n" +
                missing.sorted().joinToString("\n") { "$it  ← ${used.getValue(it).first()}" },
        )
        val orphan = SfSymbols.toAppIcon.keys - used.keys
        assertTrue(orphan.isEmpty(), "Swift 가 더는 쓰지 않는 대응(고아): ${orphan.sorted()}")
        val staleIndirect = SfSymbolScan.INDIRECT.filter { name -> sources.none { (_, code) -> code.contains("\"$name\"") } }
        assertTrue(staleIndirect.isEmpty(), "간접 기호 목록에 원문에서 사라진 이름: $staleIndirect")
        println("AINGCHECK-SFSYMBOLS swift=${sources.size} used=${used.size} mapped=${SfSymbols.toAppIcon.size} icons=${AppIcon.entries.size}")
    }

    /** 수집기가 실제로 새 기호를 잡는다(심은 결함): 문맥 줄 · 문맥 없는 점 글자 · 삼항 양쪽 · 주석 속은 무시. */
    @Test
    fun scannerCatchesPlantedSymbols() {
        val planted = listOf(
            "A.swift" to SwiftPalette.stripComments(
                """
                Image(systemName: "star.circle")
                Label("x", systemImage: on ? "bolt.slash" : "bolt.badge.clock")
                case .later: return "calendar.day.timeline.left"
                // Image(systemName: "commented.out")
                fieldIcon("tortoise")
                let key = "aingcheck.appearance.mode"
                """.trimIndent(),
            ),
        )
        val got = SfSymbolScan.scan(planted).keys
        assertEquals(setOf("star.circle", "bolt.slash", "bolt.badge.clock", "calendar.day.timeline.left", "tortoise"), got)
        assertTrue((got - SfSymbols.toAppIcon.keys).isNotEmpty(), "심은 기호가 표에 이미 있다 — 이 단언은 빠짐을 재지 못한다")
    }

    @Test
    fun everyIconHasAVectorFileAndEveryVectorFileIsAnIcon() {
        val dir = File(requireNotNull(System.getProperty("aingcheck.mpRoot")), "ui/src/commonMain/composeResources/drawable")
        val files = dir.listFiles().orEmpty().filter { it.name.startsWith("ms_") && it.name.endsWith(".xml") }.map { it.name.removeSuffix(".xml") }.toSet()
        val icons = AppIcon.entries.map { it.resourceName }.toSet()
        assertEquals(icons, files, "아이콘 열거 ↔ 벡터 파일이 짝이 안 맞는다")
        assertEquals(AppIcon.entries.size, AppIcon.entries.map { it.materialName to it.filled }.toSet().size, "같은 그림이 두 번 있다")
        // 출처 표(material-symbols-source.tsv)와도 짝: 리소스 이름 · sha256 · SF 이름.
        val tsv = File(requireNotNull(System.getProperty("aingcheck.mpRoot")), "ui/snapshots/icons/material-symbols-source.tsv")
            .readLines().filter { it.isNotBlank() && !it.startsWith("#") }.map { it.split('\t') }
        assertEquals(icons, tsv.map { it[0] }.toSet(), "출처 표 ↔ 아이콘")
        val sfFromTsv = tsv.flatMap { it[4].split(' ') }.toSet()
        assertEquals(SfSymbols.toAppIcon.keys, sfFromTsv, "출처 표의 SF 이름 ↔ 대응표")
        for (row in tsv) {
            val icon = AppIcon.entries.first { it.resourceName == row[0] }
            for (sf in row[4].split(' ')) assertEquals(icon, SfSymbols.toAppIcon[sf], "$sf → ${row[0]}")
            assertTrue(Regex("^[0-9a-f]{64}$").matches(row[3]), "sha256 꼴: ${row[3]}")
        }
    }
}

internal object SfSymbolScan {
    /** 점 붙은 기호 꼴이지만 기호가 아닌 글자(설정 키·파일 이름·번들 id·PostgREST 연산자·판 표기). 이유는 원문 자리. */
    val NOT_SYMBOLS: Set<String> = setOf(
        // 파일 이름
        "agy.log", "auth.json", "entries.json", "manifest.json", "state.json",
        // 설정 키·식별자
        "aingcheck.appearance.mode", "aingcheck.session.email", "check.character.selected", "check.chess.window", "check.facing",
        "check.gacha.window", "check.gomoku.window", "check.minigame.kind", "check.reaction", "check.reaction.confetti",
        "check.reaction.goalspark", "check.reaction.ultracharge", "check.reaction.ultracharge.collapse", "check.reaction.zzz",
        "minigame.mascot", "now.working", "privacy.minigame", "privacy.token", "write.avatar", "kingcheck.mas",
        // 번들 id·주소
        "com.apple.coreservices.launchservicesd", "com.yehsung.aingcheck", "com.yehsung.aingcheck.widgets",
        "group.com.yehsung.aingcheck", "demo.aingcheck.invalid",
        // PostgREST 연산자·정렬
        "day.desc", "eq.abandoned", "is.null", "not.is.null",
        // 판 표기
        "v0.3.0",
    )

    /** 문맥 낱말도 점도 없이 쓰이는 간접 기호(낱말 하나). 지금은 없다 — 생기면 여기 적고 원문 대조가 따라온다. */
    val INDIRECT: Set<String> = emptySet()

    // 소유 한정자(*+ ++)로 되돌아가기 없이 — 긴 줄에서 Java 정규식이 스택을 넘쳤다(실측 StackOverflowError).
    private val literal = Regex(""""((?:[^"\\\n]++|\\.)*+)"""")
    private val symbolShape = Regex("""^[a-z][a-z0-9]*(?:\.[a-z0-9]+)*$""")
    private val dotted = Regex("""^[a-z][a-z0-9]*(?:\.[a-z0-9]+)+$""")
    private val context = Regex("""(?i)systemname|systemimage|systemsymbolname|symbol|icon|glyph""")

    /** 기호 이름 → 처음 본 자리들. */
    fun scan(sources: List<Pair<String, String>>): Map<String, List<String>> {
        val out = linkedMapOf<String, MutableList<String>>()
        for ((path, code) in sources) {
            code.lineSequence().forEachIndexed { i, line ->
                for (m in literal.findAll(line)) {
                    val s = m.groupValues[1]
                    if (!symbolShape.matches(s)) continue
                    val inContext = context.containsMatchIn(line.substring(0, m.range.first))
                    val isDotted = dotted.matches(s) && s !in NOT_SYMBOLS
                    if (inContext || isDotted || s in INDIRECT) out.getOrPut(s) { mutableListOf() } += "$path:${i + 1}"
                }
            }
        }
        return out
    }
}
