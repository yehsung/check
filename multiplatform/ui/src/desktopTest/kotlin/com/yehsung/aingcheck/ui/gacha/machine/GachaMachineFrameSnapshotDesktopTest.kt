// 원본: Tests/checkTests/V0354GachaMachineTests.swift @ 3bd04bd (대기 화면 밝음·어두움 · 중복 조각 비행 · 건너뛰기 대비 — 그림으로 잰 몫)
//
// G §2-3 W4-c ① 기계 연출 프레임 스냅숏(데스크톱 배율 2). 감독을 손 시계로 몰아 세운 열두 순간(MachineFrames)을 그려 골든과 대조한다.
// 기계 그림 다섯 장은 저장소 원본(Sources/CheckCore/Resources/GachaMachine)을 그대로 쓴다 — 앱은 ui Gradle Sync 패치(0001)가 같은 그림을 싣는다.
// 음성 기준선: 같은 순간 · 루비 칩 숫자 한 자리만 다른 장면(120 → 121).
package com.yehsung.aingcheck.ui.gacha.machine

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import com.yehsung.aingcheck.ui.shop.MeArtPaths
import com.yehsung.aingcheck.ui.shop.W4cDesktopSnapshots
import kotlin.test.Test
import kotlin.test.assertTrue

class GachaMachineFrameSnapshotDesktopTest {
    private val art get() = W4cDesktopSnapshots.art

    private fun machineArt(): GachaMachineArt {
        val n = GachaMachineArt.resourceNames
        return GachaMachineArt(
            art.peek(MeArtPaths.machine(n[0])), art.peek(MeArtPaths.machine(n[1])), art.peek(MeArtPaths.machine(n[2])),
            art.peek(MeArtPaths.machine(n[3])), art.peek(MeArtPaths.machine(n[4])),
        )
    }

    private fun scene(name: String, balance: Long): @Composable () -> Unit {
        return W4cDesktopSnapshots.frame(name.endsWith("-dark"), W, H) {
            val machine = remember { machineArt() }
            val f = remember { MachineFrames.build(name, balance, machine) }
            val sprites = remember { GachaCapsuleSprites(machine) }
            GachaMachineScaler {
                GachaMachineStage(
                    f.d, f.env, GachaMachineTheme.of(f.dark), sprites, f.now,
                    portrait = { id -> art.peek(MeArtPaths.portrait(id)) },
                    ruby = art.peek(MeArtPaths.ruby(24f, 2f)),
                )
            }
        }
    }

    private fun check(name: String) = W4cDesktopSnapshots.check("gacha", "machine-$name", W, H, scene(name, 120), scene(name, 121))

    @Test fun artIsComplete() = assertTrue(machineArt().isComplete, "저장소 기계 그림 다섯 장 중 빠진 것이 있다(${GachaMachineArt.SOURCE_DIR})")

    @Test fun idle() = check("idle")
    @Test fun idleDark() = check("idle-dark")
    @Test fun short() = check("short")
    @Test fun shaking() = check("shaking")
    @Test fun dropping() = check("dropping")
    @Test fun tapping() = check("tapping")
    @Test fun revealNew() = check("reveal-new")
    @Test fun revealDuplicate() = check("reveal-duplicate")
    @Test fun revealGold() = check("reveal-gold")
    @Test fun revealRainbowDark() = check("reveal-rainbow-dark")
    @Test fun reducedReveal() = check("reduced-reveal")
    @Test fun failed() = check("failed")

    private companion object {
        const val W = 380
        const val H = 460
    }
}
