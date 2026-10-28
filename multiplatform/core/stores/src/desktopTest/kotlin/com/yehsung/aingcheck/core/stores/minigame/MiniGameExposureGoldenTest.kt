// 원본: 없음 — G §2-3 W2-e ④ "미니게임 표시 깃발: 해당 골든이 초록인 빌드에서만 켠다(B§10-5)" 의 잠금 시험.
package com.yehsung.aingcheck.core.stores.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.structure.StructureRules
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 미니게임 표시 깃발([MiniGameExposure])이 **골든 대조와 짝**인지 잰다. 깃발이 켜진 게임마다 증거 골든 전부가
 *  ① `_manifest.json` 에 있고(Swift 가 낸 계약 골든) ② 게이트가 돌리는 Kotlin 시험 소스(commonTest·desktopTest·androidHostTest·test)의
 *     주석 밖 코드에서 `Golden.load("<이름>")` 로 **대조된다**.
 * ①② 가 서면 그 대조 시험(W1-a)이 이 시험과 같은 게이트에서 돌므로 "깃발이 켜진 빌드 = 그 골든이 초록인 빌드" 다. 하나라도 빠지면 빨강이다.
 */
class MiniGameExposureGoldenTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 가 없다" })
    private val loadCall = Regex("""\bGolden\s*\.\s*load\s*\(\s*"([^"\\]+)"\s*\)""")
    private val gateSourceSets = setOf("commonTest", "desktopTest", "androidHostTest", "test")

    private fun manifestNames(): Set<String> =
        Json.parseToJsonElement(RepoFiles.readText("contract/golden/_manifest.json")).jsonObject["goldens"]!!.jsonArray
            .map { it.jsonObject["golden"]!!.jsonPrimitive.content }.toSet()

    private fun consumedNames(): Set<String> {
        val out = mutableSetOf<String>()
        for (f in StructureRules.collect(mpRoot)) {
            if (!f.relPath.endsWith(".kt")) continue
            val parts = f.relPath.split('/')
            val src = parts.indexOf("src")
            if (src < 0 || src + 1 >= parts.size || parts[src + 1] !in gateSourceSets) continue
            for (m in loadCall.findAll(f.code)) out += m.groupValues[1]
        }
        return out
    }

    /** 문제 목록(빈 목록이면 깃발과 골든이 짝이다). 보이는 게임만 본다 — 숨긴 게임의 증거는 아직 요구하지 않는다. */
    private fun problems(evidence: Map<MiniGameKind, List<String>>, listed: Set<String>, consumed: Set<String>): List<String> =
        MiniGameExposure.visibleKinds(evidence).flatMap { kind ->
            evidence[kind].orEmpty().flatMap { name ->
                listOfNotNull(
                    if (name !in listed) "${kind.rawValue}: 증거 골든 '$name' 이 _manifest.json 에 없다" else null,
                    if (name !in consumed) "${kind.rawValue}: 증거 골든 '$name' 을 대조하는 Kotlin 시험이 없다" else null,
                )
            }
        }

    @Test
    fun everyVisibleGameHasGreenGoldenEvidence() {
        val listed = manifestNames()
        val consumed = consumedNames()
        val problems = problems(MiniGameExposure.evidenceGoldens, listed, consumed)
        assertEquals(emptyList(), problems, problems.joinToString("\n"))
        assertEquals(listOf(MiniGameKind.timingBar, MiniGameKind.flappy, MiniGameKind.tetris), MiniGameExposure.visible,
            "이 빌드에 보이는 게임 — 폰 노출 규칙 ∩ 증거(길건너는 폰 1.0.15 때 W4-b 가 연다)")
    }

    /** 대조(기준선이 다른 입력): 증거가 빠진 게임은 깃발이 내려가고, 목록에 없는·대조 안 된 골든을 증거로 적으면 빨강이다. */
    @Test
    fun missingEvidenceTurnsTheFlagOffOrFailsTheLock() {
        val listed = manifestNames()
        val consumed = consumedNames()
        val withoutTetris = MiniGameExposure.evidenceGoldens - MiniGameKind.tetris
        assertEquals(listOf(MiniGameKind.timingBar, MiniGameKind.flappy), MiniGameExposure.visibleKinds(withoutTetris),
            "증거가 없는 게임은 보이지 않는다")
        val ghost = MiniGameExposure.evidenceGoldens + (MiniGameKind.flappy to listOf("flappy/rules", "flappy/ghost"))
        val found = problems(ghost, listed, consumed)
        assertTrue(found.any { "flappy/ghost" in it && "_manifest" in it }, "목록에 없는 증거를 못 잡았다: $found")
        assertTrue(found.any { "flappy/ghost" in it && "Kotlin 시험" in it }, "대조 안 된 증거를 못 잡았다: $found")
        assertTrue(consumed.containsAll(listOf("tetris/scripted", "flappy/scripted", "timing-bar/scripted")),
            "소비 스캔이 비었다(정규식·소스셋 범위 확인)")
    }
}
