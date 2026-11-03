// 원본: 없음 — 검토 F5(판 7 뒤집기 코어). Swift 접근 수준 대조: Sources/CheckCore/ReversiBitboard.swift:17(`enum ReversiBits` — internal) ·
//       ReversiRules.swift:94-102(`bits` · `sides` · `init(own:opp:color:)` — internal) · 349-375(`isOver` · `endKindOfFinished` · `wofScore` — internal) @ 12624739
package com.yehsung.aingcheck.core.rules.reversi

import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.structure.StructureRules
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * 판정 내부가 모듈(core/rules) 밖에 보이지 않는다 — Swift 에서 internal 인 것은 Kotlin 에서도 internal.
 *
 * 왜 재나: `ReversiBits.flips` 는 칸 범위를 보지 않는다(부르는 쪽이 거른다). Kotlin `shl` 은 이동 수를 64 로 나눈 나머지만큼 밀어
 * 칸 64 를 a1(비트 0)로 읽는다 — Swift 의 과대 이동은 0 이다. `wofScore` 는 끝났는지 보지 않고 점수를 낸다. 스토어·화면 갈래가 공개
 * 표면(`ReversiRules.flips` · `score` · `endKind`) 대신 이것들을 부르면 맥과 다른 판이 그려진다. 같은 모듈의 엔진·시험만 부를 수 있어야 한다.
 */
class ReversiVisibilityTest {
    @Test
    fun ruleInternalsAreModuleInternal() {
        // 없으면: 다른 모듈이 범위 검사 없는 비트 계산이나 "끝났는지 안 보는" 점수를 바로 불러도 컴파일이 막지 않는다.
        val bits = code(BITS)
        val rules = code(RULES)
        val problems = buildList {
            if (!Regex("""(?m)^internal object ReversiBits\b""").containsMatchIn(bits)) add("ReversiBits 가 internal object 가 아니다")
            for (decl in listOf("fun ReversiBoard.sides(", "fun ReversiBoard.bits(", "fun reversiBoardOf(")) {
                if (!Regex("""(?m)^internal ${Regex.escape(decl)}""").containsMatchIn(rules)) add("최상위 `$decl` 가 internal 이 아니다")
            }
            for (name in listOf("isOver", "endKindOfFinished", "wofScore")) {
                if (!Regex("""(?m)^\s+internal fun $name\(""").containsMatchIn(rules)) add("ReversiRules.$name 이 internal 이 아니다")
            }
        }
        assertTrue(problems.isEmpty(), problems.joinToString("\n"))
    }

    private fun code(path: String): String = StructureRules.stripComments(RepoFiles.readText(path))

    private companion object {
        const val DIR = "multiplatform/core/rules/src/commonMain/kotlin/com/yehsung/aingcheck/core/rules/reversi"
        const val BITS = "$DIR/ReversiBits.kt"
        const val RULES = "$DIR/ReversiRules.kt"
    }
}
