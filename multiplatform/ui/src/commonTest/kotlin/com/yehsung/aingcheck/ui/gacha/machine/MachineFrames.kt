// 원본: 없음 — 기계 연출 프레임 장면(G §2-3 W4-c ① "기계 연출 프레임 스냅숏"). 감독을 손 시계로 몰아 한 순간에 세운다.
//
// 장면마다 **진짜 감독 경로**(autoTurn → advance → commit → pull → arrive → press …)를 지난다 — 상태를 손으로 꽂지 않는다.
// 씨앗 · 반전 주사위를 고정해 같은 장면은 언제나 같은 그림이다. pull 은 바로 답하거나(Unconfined 범위에서 그 자리에서 끝난다) 영영 기다린다.
package com.yehsung.aingcheck.ui.gacha.machine

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job

object MachineFrames {
    class Frame(val d: GachaMachineDirector, val env: GachaMachineEnv, val now: Double, val dark: Boolean)

    val fox = GachaRevealOutcome("fox", "여우", GachaRevealKind.New, shardCount = 23)
    val squirrel = GachaRevealOutcome("squirrel", "다람쥐", GachaRevealKind.Duplicate, shardCount = 24, shardsGainedOrNull = 1)
    val gold = GachaRevealOutcome("aing_gold", "황금 아잉이", GachaRevealKind.Gold, shardCount = 23)
    val rainbow = GachaRevealOutcome("aing_rainbow", "무지개 아잉이", GachaRevealKind.Rainbow, shardCount = 23)

    /** 장면 이름 → 프레임. [balance] 는 음성 기준선이 한 군데만 바꾸는 값(루비 칩 숫자). */
    fun build(name: String, balance: Long = 120, art: GachaMachineArt = GachaMachineArt.Vector): Frame {
        val t0 = 100.0
        var clock = t0
        val scope = CoroutineScope(Dispatchers.Unconfined + Job())
        val (outcome: GachaRevealOutcome?, mode: String) = when (name) {
            "idle", "idle-dark", "short" -> null to "idle"
            "shaking" -> null to "hang"
            "failed" -> null to "fail"
            "dropping" -> fox to "drop"
            "tapping" -> squirrel to "tap"
            "reveal-new" -> fox to "reveal"
            "reveal-duplicate" -> squirrel to "reveal"
            "reveal-gold" -> gold to "reveal"
            "reveal-rainbow-dark" -> rainbow to "reveal"
            "reduced-reveal" -> squirrel to "reduced"
            else -> error("모르는 장면: $name")
        }
        val reduce = mode == "reduced"
        val never = CompletableDeferred<GachaRevealOutcome>()
        val d = GachaMachineDirector(clock = { clock }, scope = scope, seedSource = { 0x5EED_CAFEuL }, random = { 0.9 })
        d.autoSchedule = false
        val env = GachaMachineEnv(
            balance = if (name == "short") balance - 90 else balance, cost = 50, shards = 23, art = art, teaseChance = 0.0,
            haptics = GachaMachineHaptics.None,
            pull = {
                when (mode) {
                    "hang" -> never.await()
                    "fail" -> throw GachaRevealFailure("지금은 뽑을 수 없어요")
                    else -> requireNotNull(outcome)
                }
            },
            reduceMotion = reduce,
        )
        d.update(env)
        d.touched(clock)
        if (mode == "idle") return Frame(d, env, t0 + 1.3, dark = name == "idle-dark")
        d.autoTurn(clock)
        clock += d.autoTurnDuration
        d.advance(clock)
        val commit = clock
        when (mode) {
            "hang" -> return Frame(d, env, commit + 1.1, dark = false)
            "fail" -> return Frame(d, env, commit + 0.5, dark = false)
        }
        val ds = requireNotNull(d.dropStart) { "낙하가 없다 — 결과가 안 왔다" }
        if (mode == "drop") return Frame(d, env, ds + 0.6, dark = false)
        if (reduce) {
            val b = requireNotNull(d.burstTime)
            return Frame(d, env, b + 0.5, dark = false)
        }
        clock = ds + d.drop.total + 0.05
        d.advance(clock)
        d.press(clock)
        clock += 0.2
        d.press(clock)
        if (mode == "tap") return Frame(d, env, clock + 0.1, dark = false)
        clock += 0.2
        d.press(clock)
        val b = requireNotNull(d.burstTime) { "세 번째 톡에 터지지 않았다" }
        val rt = when (name) {
            "reveal-new" -> 0.6
            "reveal-duplicate" -> 2.0
            else -> 1.5
        }
        return Frame(d, env, b + d.goldBuild + rt, dark = name.endsWith("-dark"))
    }

    val names = listOf(
        "idle", "idle-dark", "short", "shaking", "dropping", "tapping", "reveal-new", "reveal-duplicate", "reveal-gold",
        "reveal-rainbow-dark", "reduced-reveal", "failed",
    )
}
