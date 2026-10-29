// 원본: 없음 — 8b reveal 갈래(사용자 결정 "첫 판부터 한 바퀴"). 뽑기 공개 자리가 살아 있는 미리보기(W5-c — LocalLiveCharacterPreview)를
// 부르는지, 결과마다 공개 번호(revealSerial)가 오르는지, 스프라이트 · 동작 줄이기 · 미리보기 없음은 지금처럼 초상 캔버스로 물러나는지 잰다.
// 기계 장면은 프레임 스냅숏과 같은 MachineFrames(손 시계로 세운 순간)를 쓴다. 미리보기는 부른 값(id · 크기 · 번호)만 적는 가짜다.
package com.yehsung.aingcheck.ui.gacha.machine

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import com.yehsung.aingcheck.ui.shop.LiveCharacterPreview
import com.yehsung.aingcheck.ui.shop.LocalLiveCharacterPreview
import com.yehsung.aingcheck.ui.shop.MeArtPaths
import com.yehsung.aingcheck.ui.shop.W4cDesktopSnapshots
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GachaRevealLiveDesktopTest {
    private class Calls {
        val live = mutableListOf<Triple<String, Float, Int>>()
        val portraits = mutableListOf<String>()
    }

    private fun render(
        name: String,
        provide: Boolean = true,
        env: (GachaMachineEnv) -> GachaMachineEnv = { it },
        then: ((MachineFrames.Frame) -> Double)? = null,
    ): Pair<MachineFrames.Frame, Calls> {
        val calls = Calls()
        val f = MachineFrames.build(name)
        val now = then?.invoke(f) ?: f.now
        val preview = LiveCharacterPreview { id, size, m, serial ->
            calls.live += Triple(id, size.value, serial)
            Box(m.size(size))
        }
        val art = W4cDesktopSnapshots.art
        W4cDesktopSnapshots.render(W, H, W4cDesktopSnapshots.frame(f.dark, W, H) {
            CompositionLocalProvider(LocalLiveCharacterPreview provides (if (provide) preview else null)) {
                GachaMachineScaler {
                    GachaMachineStage(
                        f.d, env(f.env), GachaMachineTheme.of(f.dark), GachaCapsuleSprites(GachaMachineArt.Vector), now,
                        portrait = { id -> calls.portraits += id; art.peek(MeArtPaths.portrait(id)) },
                        ruby = null,
                    )
                }
            }
        })
        return f to calls
    }

    @Test
    fun goldRevealDrawsTheLivePreviewWithTheFirstSerial() {
        val (f, calls) = render("reveal-gold")
        assertEquals(1, f.d.revealSerial, "첫 결과가 왔는데 공개 번호가 1 이 아니다")
        assertTrue(calls.live.isNotEmpty(), "황금 아잉이 공개 자리가 살아 있는 미리보기를 부르지 않았다(정적 초상)")
        assertTrue(calls.live.all { it == Triple(MachineFrames.gold.characterID, 172f, 1) }, "미리보기 호출 값이 다르다: ${calls.live}")
        assertFalse(MachineFrames.gold.characterID in calls.portraits, "미리보기가 그리는 자리에 초상 캔버스도 그렸다(겹친 그림)")
    }

    @Test
    fun rainbowRevealAlsoSpins() {
        val (_, calls) = render("reveal-rainbow-dark")
        assertTrue(calls.live.isNotEmpty() && calls.live.all { it.first == MachineFrames.rainbow.characterID && it.third == 1 }, "무지개: ${calls.live}")
    }

    @Test
    fun serialRisesByOnePerArrivedResult() {
        // [한 번 더] → 손잡이가 돌고 → 둘째 결과가 온다 → 톡톡 셋 → 공개(1.5초). 같은 감독이라 번호가 2 가 되고, 공개 자리는 그 번호로 부른다.
        val (f, calls) = render("reveal-gold", then = { fr ->
            val d = fr.d
            var c = fr.now + 5.0
            d.again(c)
            c += GTiming.againDelay
            d.autoTurn(c)
            c += d.autoTurnDuration
            d.advance(c)
            val ds = requireNotNull(d.dropStart) { "둘째 결과가 안 왔다" }
            c = ds + d.drop.total + 0.05
            d.advance(c)
            repeat(3) { d.press(c); c += 0.2 }
            requireNotNull(d.burstTime) { "둘째 판이 터지지 않았다" } + d.goldBuild + 1.5
        })
        assertEquals(2, f.d.revealSerial, "두 번째 결과에 공개 번호가 1 오르지 않았다")
        assertTrue(calls.live.isNotEmpty() && calls.live.all { it == Triple(MachineFrames.gold.characterID, 172f, 2) }, "새 결과의 번호로 미리보기를 부르지 않았다: ${calls.live}")
    }

    @Test
    fun liveStageIsWarmedHiddenBeforeTheReveal() {
        // 같은 황금 판을 공개 전(떨어지는 중)으로 그린다 — 공개 자리(172)는 아직 없고, 1dp 데움 자리만 번호 0 으로 선다.
        val (_, calls) = render("reveal-gold", then = { fr -> requireNotNull(fr.d.dropStart) + 0.1 })
        assertEquals(listOf(Triple(MachineFrames.gold.characterID, 1f, 0)), calls.live.distinct(), "공개 전 데움: ${calls.live}")
    }

    @Test
    fun spriteCharacterFallsBackToThePortrait() {
        val (_, calls) = render("reveal-new")
        assertTrue(calls.live.isEmpty(), "스프라이트(여우)에 살아 있는 미리보기를 불렀다: ${calls.live}")
        assertTrue(MachineFrames.fox.characterID in calls.portraits, "여우 공개가 초상을 그리지 않았다")
    }

    @Test
    fun reduceMotionAndNoPreviewKeepThePortrait() {
        val (_, reduced) = render("reveal-gold", env = { it.copy(reduceMotion = true) })
        assertTrue(reduced.live.isEmpty(), "동작 줄이기에 도는 미리보기를 불렀다: ${reduced.live}")
        assertTrue(MachineFrames.gold.characterID in reduced.portraits, "동작 줄이기 공개가 초상을 그리지 않았다")
        val (_, none) = render("reveal-gold", provide = false)
        assertTrue(MachineFrames.gold.characterID in none.portraits, "미리보기가 없는 판(데스크톱 · Windows)이 초상을 그리지 않았다")
    }

    @Test
    fun onlyBakedAingFamilyUsesTheLivePreview() {
        listOf("aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco").forEach { assertTrue(gachaRevealUsesLive(it), it) }
        listOf("fox", "squirrel", "shiba", "unknown_new_character", "").forEach { assertFalse(gachaRevealUsesLive(it), it) }
    }

    private companion object {
        const val W = 380
        const val H = 460
    }
}
