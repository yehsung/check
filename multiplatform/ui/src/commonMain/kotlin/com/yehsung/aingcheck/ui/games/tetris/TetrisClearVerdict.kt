// 원본: Sources/CheckMobileKit/Games/GamesTetrisCanvas.swift:341-355 @ 3bd04bd (GamesTetrisCanvas.verdict(_:))
// 원본: Sources/check/MiniGameTetris.swift @ 3bd04bd (맥 TetrisGameView.verdict(_:) — 같은 문장의 둘째 벌)
package com.yehsung.aingcheck.ui.games.tetris

import com.yehsung.aingcheck.core.rules.tetris.TetrisGame

/**
 * 소거·스핀 판정 이름. null 이면 캡션 없이 점수만 뜬다(평범한 1~3줄 소거).
 *
 * INV-GamesTetrisCanvas-a29fc8ba 이식: Swift 는 맥 잎 뷰와 폰 캔버스가 **같은 문장을 두 벌로** 들고 있다(코어로 합치지 않았다). Kotlin 은 이
 *   한 벌만 둔다 — 대신 `TetrisClearVerdictContractTest` 가 맥·폰 두 Swift 원본의 문장을 소스에서 읽어 이 표와 **셋이 같은지** 잰다
 *   (한쪽만 고치면 맥과 폰의 판정 이름이 조용히 갈린다).
 */
object TetrisClearVerdict {
    const val perfectClear: String = "퍼펙트 클리어"
    val lineNames: Map<Int, String> = mapOf(1 to "싱글", 2 to "더블", 3 to "트리플", 4 to "테트리스")
    const val tSpinPrefix: String = "T-스핀 "
    const val tSpinMini: String = "T-스핀 미니"
    const val tetrisBang: String = "테트리스!"

    fun text(clear: TetrisGame.ClearEvent): String? {
        if (clear.perfectClear) return perfectClear
        return when (clear.spin) {
            TetrisGame.Spin.full -> tSpinPrefix + (lineNames[clear.lines] ?: "")
            TetrisGame.Spin.mini -> tSpinMini
            TetrisGame.Spin.none -> if (clear.lines == 4) tetrisBang else null
        }
    }
}
