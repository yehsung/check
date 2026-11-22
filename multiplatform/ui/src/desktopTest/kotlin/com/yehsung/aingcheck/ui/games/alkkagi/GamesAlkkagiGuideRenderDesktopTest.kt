// 원본: Tests/CheckMobileKitTests/V1019AlkkagiGuideTests.swift 의 뜻(판 위 안내가 실제로 그려진다) — 판 9.
// 그림은 빌드 폴더(ui/build/aingcheck-snapshots/desktop/alkkagi-guide-*.png)에만 쓴다 — 골든 비교가 아니라 사람이 볼 렌더와 '그려졌다' 단언.
package com.yehsung.aingcheck.ui.games.alkkagi

import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiGame
import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiVector
import com.yehsung.aingcheck.core.stores.alkkagi.GamesAlkkagiBoardModel
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.theme.AingTheme
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

class GamesAlkkagiGuideRenderDesktopTest {
    /** 파란 진영(강조색 55%) 픽셀 수 — 판 나무색 위에 칠해진 파랑. */
    private fun bluish(argb: IntArray): Int = argb.count { p ->
        val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF
        b > 150 && b > r + 40 && b > g + 10
    }

    /** 없으면: 진영 칸 · 가운데 띠 · 손 안내가 빠져도(그리기 결함) 값 시험은 초록이다. 숨겨 놓기와 쏘기 차례 두 장면을 그린다. */
    @Test
    fun placingZonesAndPullHintRender() {
        val model = GamesAlkkagiBoardModel()
        val placing = DesktopSnapshots.render(393, 520) {
            AingTheme(dark = false) { GamesAlkkagiPracticeView(refreshHz = 60, reduceMotion = true, onExit = {}) }
        }
        DesktopSnapshots.writePng(placing, File(DesktopSnapshots.outDir(), "alkkagi-guide-placing.png"))
        assertTrue(bluish(placing.argb) > 8_000, "내 진영(파란 칸)이 안 보인다(${bluish(placing.argb)})")

        for (x in listOf(80.0, 190.0, 300.0, 410.0, 520.0)) { model.aim(AlkkagiVector(x, 470.0), AlkkagiVector.zero); model.release() }
        model.confirmPlacement()
        for (x in listOf(80.0, 190.0, 300.0, 410.0, 520.0)) { model.aim(AlkkagiVector(x, 130.0), AlkkagiVector.zero); model.release() }
        model.confirmPlacement()
        assertTrue(model.game.phase == AlkkagiGame.Phase.aiming && model.pullHintStone != null, "전제: 쏘기 차례 · 손 안내")
        val aiming = DesktopSnapshots.render(393, 393) {
            AingTheme(dark = false) { GamesAlkkagiBoardView(model, null, refreshHz = 60, reduceMotion = true) }
        }
        DesktopSnapshots.writePng(aiming, File(DesktopSnapshots.outDir(), "alkkagi-guide-aiming.png"))
        assertTrue(bluish(aiming.argb) < bluish(placing.argb), "쏘기 차례인데 진영 칸이 그대로 칠해졌다")
    }
}
