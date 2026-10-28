// 원본: Sources/CheckMobileKit/Games/GamesTetrisCanvas.swift:341-355 @ 3bd04bd · Sources/check/MiniGameTetris.swift:466-474 @ 3bd04bd (verdict 두 벌)
//
// INV-GamesTetrisCanvas-a29fc8ba 의 요구 그대로: 판정 이름은 Swift 에 **두 벌**(폰 캔버스 · 맥 잎 뷰)이 있다 — "두 벌이 같은지 계약 테스트로 묶어라".
// Kotlin 은 한 벌(TetrisClearVerdict)이다. 이 시험은 두 Swift 원본에서 verdict 함수 몸통의 글자를 읽어 셋이 같은지 잰다.
package com.yehsung.aingcheck.ui.games.tetris

import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TetrisClearVerdictContractTest {
    private val repo = File(requireNotNull(System.getProperty("aingcheck.repoRoot")))
    private val sources = listOf("Sources/CheckMobileKit/Games/GamesTetrisCanvas.swift", "Sources/check/MiniGameTetris.swift")

    /** `static func verdict(` 부터 들여쓰기 4칸 닫는 중괄호까지. */
    private fun verdictBody(path: String): String {
        val text = File(repo, path).readText()
        val start = text.indexOf("static func verdict(")
        check(start >= 0) { "$path 에 verdict 함수가 없다 — 옮겼으면 이 시험의 자리도 옮긴다" }
        val end = text.indexOf("\n    }\n", start)
        return text.substring(start, end)
    }

    private fun clear(lines: Int, spin: TetrisGame.Spin, perfect: Boolean = false): TetrisGame.ClearEvent =
        TetrisGame.ClearEvent(lines = lines, spin = spin, backToBack = false, perfectClear = perfect, points = 100, at = 1.0)

    @Test
    fun bothSwiftCopiesSayTheSameWordsAsKotlin() {
        for (path in sources) {
            val body = verdictBody(path)
            assertTrue("\"${TetrisClearVerdict.perfectClear}\"" in body, "$path: 퍼펙트 클리어 글자")
            val names = TetrisClearVerdict.lineNames.entries.joinToString(", ", "[", "]") { (k, v) -> "$k: \"$v\"" }
            assertTrue(names in body, "$path: 줄 이름 표 $names")
            assertTrue("\"${TetrisClearVerdict.tSpinPrefix}\" + (names[clear.lines] ?? \"\")" in body, "$path: T-스핀 정식 꼴")
            assertTrue("\"${TetrisClearVerdict.tSpinMini}\"" in body, "$path: T-스핀 미니 글자")
            assertTrue("clear.lines == 4 ? \"${TetrisClearVerdict.tetrisBang}\" : nil" in body, "$path: 평범한 4줄 = 테트리스!")
        }
    }

    @Test
    fun kotlinVerdictFollowsTheSwiftBranches() {
        assertEquals("퍼펙트 클리어", TetrisClearVerdict.text(clear(4, TetrisGame.Spin.full, perfect = true)), "퍼펙트가 스핀보다 먼저")
        assertEquals("T-스핀 더블", TetrisClearVerdict.text(clear(2, TetrisGame.Spin.full)))
        assertEquals("T-스핀 ", TetrisClearVerdict.text(clear(0, TetrisGame.Spin.full)), "0줄 정식 스핀 — 이름표에 0 이 없어 빈 꼬리(Swift 와 같다)")
        assertEquals("T-스핀 미니", TetrisClearVerdict.text(clear(1, TetrisGame.Spin.mini)))
        assertEquals("테트리스!", TetrisClearVerdict.text(clear(4, TetrisGame.Spin.none)))
        assertNull(TetrisClearVerdict.text(clear(3, TetrisGame.Spin.none)), "평범한 1~3줄은 캡션 없음")
    }
}
