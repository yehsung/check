// 원본: Sources/CheckCore/MahjongClock.swift · MahjongSeatCompass.swift @ e4995a3a — Android 판 8
//
// 생각 시간 5초 + 예비 20초(MJ-53) — SQL `mahjong_clock_deadline` · `mahjong_clock_charge` 쌍둥이. 유예 1000ms 는 마감에만 더하고 차감에는 안 더한다.
// 화면 방위: 늘 내가 아래, **하가(다음 차례)가 오른쪽**, 대면 위, 상가 왼쪽. 차례는 0→1→2→3. 치는 상가(왼쪽)의 버림에만 뜬다(MJ-14).
package com.yehsung.aingcheck.core.rules.mahjong

import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

object MahjongClock {
    const val baseMs: Int = 5_000
    const val bankFullMs: Int = 20_000
    const val graceMs: Int = 1_000

    /** 마감 = 시작 + 기본 + 남은 예비(유예 제외). */
    fun deadline(started: SwiftDate, bankMs: Int): SwiftDate = started.addingTimeInterval((baseMs + max(bankMs, 0)).toDouble() / 1000)

    data class Charge(val bankLeft: Int, val usedMs: Int, val timedOut: Boolean)

    /**
     * 도착한 답의 차감. 경과 ms = **µs 로 맞춘 뒤 ms 아래를 버린다**(서버 timestamptz µs 정수 → floor(×1000) 와 같게 — 5.1초가 5099.99… 로 떨어지지 않게).
     * 음수 경과는 0. timedOut = 도착이 마감 + 유예를 넘었다(같으면 받는다).
     */
    fun charge(started: SwiftDate, arrived: SwiftDate, bankMs: Int): Charge {
        val bank = max(bankMs, 0)
        val micros = (arrived.timeIntervalSince(started) * 1_000_000).let { if (it.isFinite()) swiftRounded(it) else 0L }
        val usedLong = max(if (micros >= 0) micros / 1000 else -((-micros + 999) / 1000), 0L)
        val used = min(usedLong, Int.MAX_VALUE.toLong()).toInt()
        val bankLeft = bank - min(max(used - baseMs, 0), bank)
        val timedOut = used > baseMs + bank + graceMs
        return Charge(bankLeft, used, timedOut)
    }

    data class Remaining(val baseLeft: Double, val bankLeft: Double)

    /** 표시용 두 칸(초) — 남은 기본 시간 · 남은 예비. 유예는 보이지 않는다. */
    fun remaining(started: SwiftDate, bankMs: Int, now: SwiftDate): Remaining {
        val elapsed = max(now.timeIntervalSince(started), 0.0)
        val base = baseMs.toDouble() / 1000
        val bank = max(bankMs, 0).toDouble() / 1000
        return Remaining(max(base - elapsed, 0.0), max(bank - max(elapsed - base, 0.0), 0.0))
    }

    /** Swift `Double.rounded()`(.toNearestOrAwayFromZero) → 정수. */
    private fun swiftRounded(v: Double): Long = if (v < 0) -kotlin.math.floor(-v + 0.5).toLong() else kotlin.math.floor(v + 0.5).toLong()
}

/** 화면 방위. rawValue = 내 자리에서 차례 순으로 몇 칸 뒤인가(0 나 · 1 하가 · 2 대면 · 3 상가). */
enum class MahjongCompass(val rawValue: Int) { bottom(0), right(1), top(2), left(3) }

object MahjongSeatCompass {
    /** `seat` 자리가 `mySeat` 기준 어느 방위에 앉는가. 0~3 밖이어도 4 로 감아 읽는다. */
    fun of(seat: Int, mySeat: Int): MahjongCompass = MahjongCompass.entries[(((seat - mySeat) % 4) + 4) % 4]

    /** 방위 → 자리 번호. */
    fun seat(at: MahjongCompass, mySeat: Int): Int = (((mySeat + at.rawValue) % 4) + 4) % 4

    /** 치 단추가 뜰 수 있는 버림인가(상가 = 왼쪽의 버림만). */
    fun canChi(fromSeat: Int, mySeat: Int): Boolean = of(fromSeat, mySeat) == MahjongCompass.left
}
