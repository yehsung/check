// 원본: Tests/checkTests/V03xxReversiTrademarkTests.swift @ 12624739 (범위를 multiplatform/ 트리로 — 맥 시험은 Sources·Tests·마이그레이션을 본다)
package com.yehsung.aingcheck.core.rules.reversi

import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * 아잉 뒤집기(reversi) — **상표 글자 0**(SPEC §1 · v1.1 CCT I9 · D24). 게임 이름으로 쓰면 안 되는 상표 글자(한글 두 표기 + 로마자, 대소문자 무관)가
 * 안드로이드·윈도우 코드 · 화면 문구 · 주석 · 시험 · 자원 어디에 새어 들어가도 아무 시험도 안 보던 자리를 막는다. 화면 이름은 '아잉 뒤집기',
 * 내부 이름은 reversi, '리버시'는 설명으로만 쓴다. 파일·폴더 **이름**도 본다. 패턴은 글자 조각을 이어 만든다 — 이 파일 자신도 0건이다.
 */
class ReversiTrademarkTest {
    private val needles = listOf("오" + "델로", "오" + "셀로", "oth" + "ello")
    private val skippedDirs = setOf("build", ".gradle", ".kotlin", ".idea", "out", "node_modules")

    private fun hits(text: String): Int {
        val folded = text.lowercase()
        var count = 0
        for (needle in needles) {
            var from = folded.indexOf(needle)
            while (from >= 0) {
                count += 1
                from = folded.indexOf(needle, from + needle.length)
            }
        }
        return count
    }

    // 없으면: 상표 글자가 multiplatform/ 어디에 새어도(대문자 표기 포함) 초록이다.
    @Test
    fun noTrademarkTextAnywhereInMultiplatform() {
        val root = File(requireNotNull(System.getProperty("aingcheck.mpRoot")) { "aingcheck.mpRoot 가 없다 — Gradle 시험 작업으로 돌린다" })
        val found = ArrayList<String>()
        var textFiles = 0
        root.walkTopDown()
            .onEnter { it == root || it.name !in skippedDirs }
            .filter { it.isFile }
            .forEach { file ->
                val relative = file.relativeTo(root).invariantSeparatorsPath
                if (hits(relative) > 0) found += "$relative (경로 이름)"
                if (file.length() > 4L * 1024 * 1024) return@forEach
                val bytes = file.readBytes()
                if (bytes.any { it == 0.toByte() }) return@forEach // 그림 · 바이너리
                textFiles += 1
                val text = bytes.decodeToString()
                if (hits(text) == 0) return@forEach
                text.lines().forEachIndexed { number, line -> if (hits(line) > 0) found += "$relative:${number + 1}" }
            }
        println("[상표] multiplatform/ 글자 파일 $textFiles 개")
        assertTrue(textFiles > 1_000, "글자 파일을 ${textFiles}개만 읽었다 — 훑는 범위가 비었다(경로가 틀렸다)")
        assertTrue(found.isEmpty(), "상표 글자가 있다(대소문자 무시) — 이름 · 문구 · 주석 · 시험 어디에도 쓰지 않는다: $found")
    }

    // 기준선: 판정기가 대문자 표기와 한글 두 표기를 정말 잡는다(늘 0 을 내는 판정기면 위 시험이 영원히 초록이다).
    @Test
    fun detectorCatchesEveryForm() {
        assertTrue(hits("OTH" + "ELLO") == 1 && hits("오" + "델로") == 1 && hits("오" + "셀로") == 1 && hits("Oth" + "ello Oth" + "ello") == 2)
        assertTrue(hits("아잉 뒤집기 · reversi · 리버시") == 0)
    }
}
