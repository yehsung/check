// 원본: 없음 — G §2-3 W2-b ③ "순위의 공유 Codex 비율은 서버값만 쓴다"의 구조 짝(동작 짝은 RankingsStoreTest.sharedCodexShareUsesServerValuesOnly).
// 기억 shared-codex-split-lives-only-in-the-server: 클라가 비율을 다시 재면 최대 19배가 갈린다(관측 분모 1.6% 사례).
package com.yehsung.aingcheck.core.stores.rankings

import com.yehsung.aingcheck.testkit.structure.StructureRules
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class RankingsServerShareTest {
    /** 비율·버킷을 다시 재는 규칙(데스크톱 로컬 스캐너 몫 — W1-c token)과 로컬 Codex 합 — 순위 스토어 패키지가 부르면 안 되는 이름. */
    private val forbidden = listOf(
        "accountShareRatio", "scaledAccountBucket", "shareRatioMonthIsYoung", "TokenRowDisplayRule", "codexLocalTotal", "codexInput", "codexOutput",
    )

    @Test
    fun rankingsPackageNeverRecomputesTheSharedCodexSplit() {
        val root = System.getProperty("aingcheck.repoRoot") ?: error("aingcheck.repoRoot 가 없다 — Gradle 시험 작업으로 돌린다")
        val dir = File(root, "multiplatform/core/stores/src/commonMain/kotlin/com/yehsung/aingcheck/core/stores/rankings")
        val files = dir.listFiles { f -> f.name.endsWith(".kt") }?.sortedBy { it.name } ?: emptyList()
        assertTrue(files.any { it.name == "RankingsStore.kt" }, "순위 스토어 소스를 못 찾았다: $dir")
        val hits = ArrayList<String>()
        for (file in files) {
            // 주석은 걷는다(규약 설명에 이름이 나온다 — 기억 source-contract-tests-need-comment-stripping).
            val code = StructureRules.stripComments(file.readText(Charsets.UTF_8))
            for (name in forbidden) {
                if (Regex("""\b${Regex.escape(name)}\b""").containsMatchIn(code)) hits += "${file.name}: $name"
            }
        }
        assertEquals(emptyList(), hits, "순위 패키지가 공유 Codex 몫을 다시 쟀다 — 서버 행(codex_effective · codex_account_month · total)만 그린다")
    }
}
