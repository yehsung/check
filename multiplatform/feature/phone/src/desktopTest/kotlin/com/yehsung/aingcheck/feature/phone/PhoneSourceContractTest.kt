// 원본: Tests/CheckMobileKitTests/IntegrationContractTests.swift:16-32(widgetSnapshotHasSingleWriter) @ 3bd04bd — 주석을 걷은 소스 계약
//       (기억 source-contract-tests-need-comment-stripping: 설명문에 이름이 들어 있어도 계약이 흔들리지 않게).
// W2-f 검증 7차 지적 둘을 잠근다: ① 위젯 스냅숏 쓰기 주체는 지금 탭 싱크 하나 ② 푸시 조정자는 라우터를 바로 부르지 않고 딥링크 대상 해석 한 문을 지난다.
package com.yehsung.aingcheck.feature.phone

import com.yehsung.aingcheck.testkit.structure.StructureRules
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PhoneSourceContractTest {
    private val mpRoot = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 가 없다 — Gradle 시험 작업으로 돌린다" })
    private val phonePkg = "feature/phone/src/commonMain/kotlin/com/yehsung/aingcheck/feature/phone"

    private fun code(rel: String): String = StructureRules.stripComments(File(mpRoot, "$phonePkg/$rel").readText())

    /** multiplatform 아래 제품 소스(`src` 아래 이름이 Main 으로 끝나는 소스 세트의 .kt, build 밖) 전부 — mpRoot 기준 상대 경로 → 주석 걷은 코드. */
    private fun mainSources(under: String = ""): Map<String, String> {
        val root = File(mpRoot, under)
        return root.walkTopDown()
            .onEnter { it.name != "build" && it.name != ".gradle" && it.name != ".kotlin" }
            .filter { file ->
                if (!file.isFile || file.extension != "kt") return@filter false
                val parts = file.relativeTo(mpRoot).invariantSeparatorsPath.split('/')
                val src = parts.indexOf("src")
                src >= 0 && src + 1 < parts.size && parts[src + 1].endsWith("Main")
            }
            .associate { it.relativeTo(mpRoot).invariantSeparatorsPath to StructureRules.stripComments(it.readText()) }
    }

    /** 몸통(첫 `{` 부터 짝 `}` 까지). */
    private fun body(source: String, signature: String): String {
        val start = source.indexOf(signature)
        check(start >= 0) { "서명 '$signature' 이 없다" }
        val open = source.indexOf('{', start)
        var depth = 0
        for (i in open until source.length) {
            when (source[i]) {
                '{' -> depth += 1
                '}' -> {
                    depth -= 1
                    if (depth == 0) return source.substring(open, i + 1)
                }
            }
        }
        error("몸통이 닫히지 않는다: $signature")
    }

    @Test
    fun widgetSnapshotHasSingleWriter() {
        val sources = mainSources()
        // 쓰기 창구(WidgetSnapshotWriter)의 쓰는 문 셋을 부르는 파일 — 지금 탭 싱크 하나여야 한다(두 주체가 각자 칸을 들고 쓰면 늦게 쓴 쪽이 덮는다).
        val writeCall = Regex("""\b(writer|widgets)\s*\.\s*(update|patchTodoPreview|touchGeneratedAt)\b""")
        val writers = sources.filterValues { writeCall.containsMatchIn(it) }.keys
        assertTrue(writers.isNotEmpty(), "대조: 쓰는 곳을 하나도 못 찾았다(이름이 바뀌었나)")
        assertEquals(setOf("$phonePkg/widget/NowWidgetSnapshotSink.kt"), writers, "위젯 스냅숏을 지금 탭 싱크 밖에서 쓴다 — 서로 덮는다")
        // 파일에 바이트를 내는 자리(인코드)는 쓰기 창구 하나다 — 창구를 건너뛴 두 번째 쓰기 길이 없다.
        val encoders = sources.filterValues { "WidgetSnapshotCodec.encode(" in it }.keys
        assertEquals(setOf("$phonePkg/widget/WidgetSnapshotWriter.kt"), encoders, "스냅숏 바이트를 쓰기 창구 밖에서 만든다")
    }

    @Test
    fun pushCoordinatorOpensOnlyThroughTheDeepLinkResolver() {
        val push = code("push/PhonePushCoordinator.kt")
        assertEquals(0, Regex("""\brouter\s*\.\s*open\s*\(""").findAll(push).count(), "푸시 조정자가 라우터를 바로 연다 — 탭 스토어 규칙을 건너뛴다")
        assertTrue(Regex("""\bcontext\.openRoute\(""").findAll(push).count() >= 5, "대조: 조정자는 대상 해석 문으로 연다(탭 · 수락 대체 길 · 대국 열기)")
        // 폰 로직에서 라우터를 바로 여는 자리는 앱 모델의 대상 해석(openRoute 몸통) 하나다.
        val opens = mainSources("feature/phone").filterValues { Regex("""\brouter\s*\.\s*open\s*\(""").containsMatchIn(it) }.keys
        assertEquals(setOf("$phonePkg/app/PhoneAppModel.kt"), opens, "앱 모델 밖에서 라우터를 바로 연다")
        val app = code("app/PhoneAppModel.kt")
        val resolver = body(app, "fun openRoute(target: PhoneRouteTarget)")
        val all = Regex("""\brouter\s*\.\s*open\s*\(""").findAll(app).count()
        val inside = Regex("""\brouter\s*\.\s*open\s*\(""").findAll(resolver).count()
        assertTrue(all > 0 && all == inside, "앱 모델의 라우터 열기는 전부 대상 해석 몸통 안이어야 한다($inside/$all)")
        assertTrue("links.routeResolver = " in app, "조정자가 지나는 고리를 앱 모델이 잇는다")
    }
}
