// 원본: Tests/checkTests/GoldenExport/games-tetris-minigame/GoldenGamesSupport.swift · Tests/CheckGoldenSupport/GoldenBits.swift(GoldenFNV1a64) @ 1b8260d
package com.yehsung.aingcheck.core.rules.minigame

import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenFile

/**
 * W1-a 대본 골든(C§5.2 G3)을 Kotlin 에서 다시 도는 도구. Swift 쪽 `GoldenGamesSupport.swift` 와 같은 정의다:
 *  - FNV-1a 64: 64비트 값 하나를 작은 끝부터 8바이트로 접는다(Int 는 Int64 비트, Double 은 IEEE 비트, Bool 은 1/0).
 *  - 대본 RLE: "개수:연산들" 을 쉼표로, 연산 사이는 공백.
 *  - frameBytes: 프레임마다 그 프레임 몫만 접은 FNV 의 아래 1바이트(16진 2자) — 첫 불일치 **프레임 번호**를 짚는다.
 */
class Fnv1a64 {
    var value: ULong = OFFSET_BASIS
        private set

    fun add(x: ULong) {
        var v = value
        for (shift in 0 until 64 step 8) {
            v = v xor ((x shr shift) and 0xFFuL)
            v *= PRIME
        }
        value = v
    }

    fun add(x: Long) = add(x.toULong())
    fun add(x: Int) = add(x.toLong())
    fun add(x: Double) = add(x.toRawBits().toULong())
    fun add(x: Boolean) = add(if (x) 1uL else 0uL)

    companion object {
        const val OFFSET_BASIS: ULong = 0xCBF29CE484222325uL
        const val PRIME: ULong = 0x00000100000001B3uL
    }
}

/** 누적 해시와 프레임 해시에 같은 값을 함께 접는다(Swift `GoldenDualFold`). */
class DualFold {
    val total = Fnv1a64()
    var frame = Fnv1a64()
        private set

    fun beginFrame() {
        frame = Fnv1a64()
    }

    fun add(x: ULong) { total.add(x); frame.add(x) }
    fun add(x: Long) { total.add(x); frame.add(x) }
    fun add(x: Int) { total.add(x); frame.add(x) }
    fun add(x: Double) { total.add(x); frame.add(x) }
    fun add(x: Boolean) { total.add(x); frame.add(x) }

    /** null 이면 0 하나, 있으면 1 과 값(Swift `add(_: Double?)`). */
    fun addOptional(x: Double?) {
        if (x != null) { add(true); add(x) } else add(false)
    }

    fun addOptional(x: Int?) {
        if (x != null) { add(true); add(x) } else add(false)
    }
}

object GoldenOps {
    fun decode(text: String): List<List<String>> {
        if (text.isEmpty()) return emptyList()
        val frames = ArrayList<List<String>>()
        for (entry in text.split(',')) {
            val colon = entry.indexOf(':')
            require(colon > 0) { "RLE 항목이 깨졌다: $entry" }
            val count = entry.substring(0, colon).toInt()
            require(count > 0) { "RLE 개수가 0 이하: $entry" }
            val body = entry.substring(colon + 1)
            val ops = if (body.isEmpty()) emptyList() else body.split(' ').filter { it.isNotEmpty() }
            repeat(count) { frames.add(ops) }
        }
        return frames
    }

    fun ints(text: String): List<Int> = if (text.isEmpty()) emptyList() else text.split(' ').map { it.toInt() }
    fun bits(text: String): List<Double> = if (text.isEmpty()) emptyList() else text.split(' ').map { Golden.bits(it) }
    fun bools(text: String): List<Boolean> = text.map {
        when (it) {
            '1' -> true
            '0' -> false
            else -> error("불 글자는 0/1 이다: '$it'")
        }
    }
    fun hexes(text: String): List<ULong> = if (text.isEmpty()) emptyList() else text.split(' ').map { Golden.hex64(it) }

    fun byteHex(value: ULong): String = (value and 0xFFuL).toString(16).padStart(2, '0')
}

/** 프레임 바이트 · 체크포인트를 모으고 Swift 값과 견준다. 실패 문구는 첫 불일치 프레임과 체크포인트 구간을 말한다. */
class ReplayTrace(private val checkpointEvery: Int) {
    val checkpoints = ArrayList<ULong>()
    private val bytes = StringBuilder()
    var frames: Int = 0
        private set

    fun endFrame(fold: DualFold) {
        frames += 1
        bytes.append(GoldenOps.byteHex(fold.frame.value))
        if (frames % checkpointEvery == 0) checkpoints.add(fold.total.value)
    }

    val frameBytes: String get() = bytes.toString()

    /**
     * 첫 불일치 설명(같으면 null). 프레임 바이트가 처음 갈린 프레임 f(1부터) · 처음 갈린 체크포인트 구간 [f₀, f₁] ·
     * 프레임 수 · 끝 해시를 차례로 본다.
     */
    fun firstMismatch(wantBytes: String, wantCheckpoints: List<ULong>, wantFrames: Int, wantHash: ULong, gotHash: ULong): String? {
        val gotBytes = frameBytes
        var firstFrame: Int? = null
        val n = minOf(gotBytes.length, wantBytes.length) / 2
        for (i in 0 until n) {
            if (gotBytes.regionMatches(i * 2, wantBytes, i * 2, 2)) continue
            firstFrame = i + 1
            break
        }
        val firstCheckpoint = checkpoints.indices.firstOrNull { it >= wantCheckpoints.size || checkpoints[it] != wantCheckpoints[it] }
        val problems = mutableListOf<String>()
        if (firstFrame != null) problems += "처음 갈린 프레임 $firstFrame (Swift 바이트 ${wantBytes.substring((firstFrame - 1) * 2, firstFrame * 2)} · Kotlin ${gotBytes.substring((firstFrame - 1) * 2, firstFrame * 2)})"
        if (firstCheckpoint != null) problems += "처음 갈린 체크포인트 구간 [${firstCheckpoint * checkpointEvery}, ${(firstCheckpoint + 1) * checkpointEvery}]"
        if (frames != wantFrames || gotBytes.length != wantBytes.length) problems += "프레임 수 Kotlin $frames · Swift $wantFrames"
        if (checkpoints.size != wantCheckpoints.size) problems += "체크포인트 수 Kotlin ${checkpoints.size} · Swift ${wantCheckpoints.size}"
        if (gotHash != wantHash) problems += "끝 해시 Kotlin ${Golden.hex64Text(gotHash)} · Swift ${Golden.hex64Text(wantHash)}"
        return if (problems.isEmpty()) null else problems.joinToString(" · ")
    }
}

/** 골든 case 실패를 하나로 모아 던진다(첫 불일치만이 아니라 모든 case 를 돌아 몇 개가 갈렸는지 함께 말한다). */
class GoldenFailures(private val golden: GoldenFile) {
    private val failures = ArrayList<String>()
    var compared: Int = 0
        private set

    fun check(caseId: String, ok: Boolean, detail: () -> String) {
        compared += 1
        if (!ok) failures += golden.failure(caseId, detail())
    }

    fun fail(caseId: String, detail: String) {
        compared += 1
        failures += golden.failure(caseId, detail)
    }

    fun assertNone() {
        if (failures.isNotEmpty()) {
            throw AssertionError("골든 ${golden.golden}: ${failures.size}건 불일치(대조 $compared)\n" + failures.take(8).joinToString("\n\n"))
        }
    }
}
