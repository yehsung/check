// 원본: 없음 — G6 디코드 덤프 대조(G §2-3 W1-d ② · C§5.2). 골든은 Tests/CheckMobileKitTests/GoldenExport/wire/GoldenExportWireDecode.swift 가 쓴다
package com.yehsung.aingcheck.core.wire

import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.models.ClientReleaseResponse
import com.yehsung.aingcheck.testkit.dump.GoldenDump
import com.yehsung.aingcheck.testkit.dump.GoldenDumpDiff
import com.yehsung.aingcheck.testkit.dump.GoldenScrub
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import com.yehsung.aingcheck.testkit.golden.GoldenFile
import com.yehsung.aingcheck.testkit.golden.array
import com.yehsung.aingcheck.testkit.golden.string
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.test.fail

class WireDecodeGoldenTest {
    companion object {
        /** Swift `Date` → `{"$date": 비트}`(core/wire 의 SwiftDate). */
        val dumper = GoldenDump(leaf = { v ->
            when (v) {
                is SwiftDate -> GoldenDump.date(v.timeIntervalSince1970)
                is SwiftURL -> JsonObject(mapOf("\$url" to JsonPrimitive(v.absoluteString)))
                is ClientReleaseResponse -> swiftShape(v)
                else -> null
            }
        })

        /**
         * Swift `ClientReleaseResponse` 에 없는 Kotlin 칸(서버 20261101100000 이 더 주는 셋 — 모델 주석). Swift 덤프와 맞출 때 **이 셋만** 뺀다.
         * 칸 이름은 속성 참조라 이름을 바꾸면 컴파일이 깨진다. 세 칸의 디코드 자체는 `ClientReleaseResponseDecodeTest` 가 잰다.
         */
        val clientReleaseKotlinOnly: Set<String> = setOf(
            ClientReleaseResponse::latestVersion.name, ClientReleaseResponse::downloadUrl.name, ClientReleaseResponse::updatedAt.name,
        )

        fun swiftShape(v: ClientReleaseResponse): JsonElement = JsonObject((GoldenDump().dump(v) as JsonObject) - clientReleaseKotlinOnly)

        /** 디코드 + 정규 덤프. 던지면 null(Swift `try?` 와 같은 자리). */
        fun dumpOrNull(type: String, element: JsonElement): JsonElement? {
            val deserializer: DeserializationStrategy<*> = WireDecodeRegistry.decoders[type] ?: error("미이식 타입 $type")
            val value = try {
                SwiftJson.decode(deserializer, element)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                return null
            }
            return dumper.dump(value)
        }

        /** 골든 한 벌 대조 → 불일치 문구 목록. */
        fun check(golden: GoldenFile): List<String> {
            val problems = mutableListOf<String>()
            var variants = 0
            for (case in golden.cases) {
                val id = case.string("id")
                val type = case.string("type")
                if (type !in WireDecodeRegistry.decoders) {
                    problems += golden.failure(id, "미이식 타입 $type")
                    continue
                }
                val text = (case["json"] as? JsonPrimitive)?.content ?: RepoFiles.readText(id)
                val tree = SwiftJson.parse(text)
                val base = dumpOrNull(type, tree)
                val want = case["dump"]!!
                val got = GoldenScrub.json(base ?: JsonPrimitive("\$error"))
                if (GoldenCanonical.text(want) != GoldenCanonical.text(got)) {
                    problems += golden.failure(id, "원본 덤프가 다르다\n  Swift : ${GoldenCanonical.text(want).take(1500)}\n  Kotlin: ${GoldenCanonical.text(got).take(1500)}")
                }
                for (v in case.array("variants")) {
                    variants++
                    val o = v as JsonObject
                    val path = o.string("path")
                    val op = o.string("op")
                    val changed = WireVariant.apply(tree, path, op)
                    val r = dumpOrNull(type, changed)
                    val result: JsonElement = GoldenScrub.json(when {
                        r == null -> JsonPrimitive("error")
                        base == null -> r
                        else -> GoldenDumpDiff.diff(base, r)
                    })
                    if (GoldenCanonical.text(o["result"]!!) != GoldenCanonical.text(result)) {
                        problems += golden.failure(id, "변형 $path $op 결과가 다르다\n  Swift : ${GoldenCanonical.text(o["result"]!!).take(800)}\n  Kotlin: ${GoldenCanonical.text(result).take(800)}")
                    }
                }
            }
            println("AINGCHECK-G6 ${golden.golden} cases=${golden.cases.size} variants=$variants problems=${problems.size}")
            return problems
        }

        fun assertGolden(golden: GoldenFile) {
            val problems = check(golden)
            if (problems.isNotEmpty()) fail("G6 불일치 ${problems.size}건(처음 15):\n" + problems.take(15).joinToString("\n\n"))
        }
    }

    @Test fun chessFixtures() = assertGolden(Golden.load("wire/decode-fixtures-chess"))
    @Test fun gomokuFixtures() = assertGolden(Golden.load("wire/decode-fixtures-gomoku"))
    @Test fun messageTodoFixtures() = assertGolden(Golden.load("wire/decode-fixtures-message-todo"))
    @Test fun demoGames() = assertGolden(Golden.load("wire/decode-demo-games"))
    @Test fun demoMe() = assertGolden(Golden.load("wire/decode-demo-me"))
    @Test fun demoOther() = assertGolden(Golden.load("wire/decode-demo-other"))
    @Test fun synthetic() = assertGolden(Golden.load("wire/decode-synthetic"))

    /** 골든이 비어 있지 않고 변형이 실제로 실렸다(조용히 0건 대조로 초록이 되지 않게). */
    @Test
    fun goldensCarryCasesAndVariants() {
        val names = listOf(
            Golden.load("wire/decode-fixtures-chess"), Golden.load("wire/decode-fixtures-gomoku"),
            Golden.load("wire/decode-fixtures-message-todo"), Golden.load("wire/decode-demo-games"),
            Golden.load("wire/decode-demo-me"), Golden.load("wire/decode-demo-other"), Golden.load("wire/decode-synthetic"),
        )
        val cases = names.sumOf { it.cases.size }
        val variants = names.sumOf { g -> g.cases.sumOf { it.array("variants").size } }
        println("AINGCHECK-G6 total cases=$cases variants=$variants")
        // 시험 픽스처 224 + 데모(case 로 들어간 것) 160 + 합성 22 — Swift 쪽 everyFixtureIsClassified 가 모수를 잠근다.
        assertTrue(cases >= 400, "G6 case 가 너무 적다($cases)")
        assertTrue(variants >= 5000, "G6 변형이 너무 적다($variants)")
    }
}
