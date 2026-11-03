// 원본: Sources/CheckCore/ReversiBitboard.swift @ 12624739
package com.yehsung.aingcheck.core.rules.reversi

// 아잉 뒤집기(내부 이름 reversi) 규칙의 **안 표현** — 비트보드(ULong 둘). 설계: flip/SPEC.md §4.1.
//
// 공개 표면(`ReversiRules` · `ReversiBoard`)은 idx·문자열 기반으로 고정이고, 이 파일은 그 밑의 계산만 한다.
// AI 엔진(ReversiAIEngine.kt)이 같은 계산을 노드마다 부르므로 할당 없이 비트 연산만 쓴다.
//
// ── 비트 배치 ──
// 비트 i = 칸 idx i (idx = row*8 + col, row 0 = 1행 위, col 0 = a열 왼쪽 — rules.md V-01).
// 그래서 열 +1 은 비트 +1, 행 +1 은 비트 +8 이다.
//
// ── 판 끝 넘김 막기(사례 C04~C07) ──
// 1차원 비트 이동은 행 끝에서 다음 행 첫 칸으로 감아 넘어간다(h4 +1 = a5). 그래서 열이 바뀌는 여섯 방향은 이동한 뒤
// **도착한 칸이 반대쪽 끝 열이면 지운다**(가면 mask): 동쪽 계열(+1·+9·−7)은 a열 도착을, 서쪽 계열(−1·+7·−9)은 h열 도착을 지운다.
// 위아래(±8)는 64비트 밖으로 밀려 나가 저절로 0 이 된다(Kotlin `ULong` 의 shl·shr 은 부호 없는 이동이라 Swift 와 같다).

/** Swift `ReversiBits` — 비트보드 계산(할당 없음). */
object ReversiBits {
    /** a열(col 0) 비트를 뺀 가면 — 동쪽으로 옮긴 뒤 a열에 도착했다면 h열에서 감아 넘어온 것이다. */
    const val notAFile: ULong = 0xFEFE_FEFE_FEFE_FEFEuL

    /** h열(col 7) 비트를 뺀 가면 — 서쪽으로 옮긴 뒤 h열에 도착했다면 a열에서 감아 넘어온 것이다. */
    const val notHFile: ULong = 0x7F7F_7F7F_7F7F_7F7FuL

    /** 8방향 한 칸 이동. `direction` 0…7 = 동·서·남·북·남동·남서·북동·북서(순서는 결과에 영향이 없다). */
    fun shift(bits: ULong, direction: Int): ULong = when (direction) {
        0 -> (bits shl 1) and notAFile // 동(col+1)
        1 -> (bits shr 1) and notHFile // 서(col−1)
        2 -> bits shl 8 // 남(row+1)
        3 -> bits shr 8 // 북(row−1)
        4 -> (bits shl 9) and notAFile // 남동(row+1, col+1)
        5 -> (bits shl 7) and notHFile // 남서(row+1, col−1)
        6 -> (bits shr 7) and notAFile // 북동(row−1, col+1)
        else -> (bits shr 9) and notHFile // 북서(row−1, col−1)
    }

    /**
     * `own` 이 둘 수 있는 칸들(빈칸 중 상대 돌을 한 방향 이상 끼우는 칸, V-06).
     * 방향마다 "내 돌 → 상대 돌 1~6개 → 빈칸"을 한꺼번에 민다(한 줄에 끼울 수 있는 상대 돌은 최대 6개).
     */
    fun moves(own: ULong, opp: ULong): ULong {
        val empty = (own or opp).inv()
        var result = 0uL
        for (direction in 0 until 8) {
            var run = shift(own, direction) and opp
            run = run or (shift(run, direction) and opp)
            run = run or (shift(run, direction) and opp)
            run = run or (shift(run, direction) and opp)
            run = run or (shift(run, direction) and opp)
            run = run or (shift(run, direction) and opp)
            result = result or (shift(run, direction) and empty)
        }
        return result
    }

    /**
     * `square` 에 `own` 을 두면 뒤집힐 상대 돌(V-07·V-08). 빈칸이 아니거나 하나도 못 끼우면 0.
     * 방향마다 상대 돌이 이어지는 동안 모으고, 바로 다음 칸이 내 돌일 때만 그 줄을 뒤집는다 — 빈칸·판 끝(이동 결과 0)이면 그 줄은 없다.
     * 새로 뒤집힌 돌이 또 끼우는 연쇄는 없다(V-08). `square` 는 0~63 이어야 한다(부르는 쪽이 거른다).
     */
    fun flips(own: ULong, opp: ULong, square: Int): ULong {
        val placed = 1uL shl square
        if ((own or opp) and placed != 0uL) return 0uL
        var all = 0uL
        for (direction in 0 until 8) {
            var line = 0uL
            var cursor = shift(placed, direction)
            while (cursor and opp != 0uL) {
                line = line or cursor
                cursor = shift(cursor, direction)
            }
            if (cursor and own != 0uL) all = all or line
        }
        return all
    }

    /** 수 세기(V-17, `ply_pass` 관례): 패스도 한 수(깊이 1)로 세고, depth 전에 끝난 판은 세지 않는다. */
    fun perft(own: ULong, opp: ULong, depth: Int): Long {
        if (depth == 0) return 1
        val available = moves(own, opp)
        if (available == 0uL) {
            // 둘 곳이 없다: 상대가 둘 수 있으면 자동 패스(한 수), 아니면 끝난 판(0).
            if (moves(opp, own) == 0uL) return 0
            return perft(opp, own, depth - 1)
        }
        if (depth == 1) return available.countOneBits().toLong()
        var total = 0L
        var rest = available
        while (rest != 0uL) {
            val square = rest.countTrailingZeroBits()
            rest = rest and (rest - 1uL)
            val flipped = flips(own, opp, square)
            val mine = own or flipped or (1uL shl square)
            total += perft(opp and flipped.inv(), mine, depth - 1)
        }
        return total
    }

    /** 비트 집합 → idx 오름차순 목록. */
    fun indices(bits: ULong): List<Int> {
        val result = ArrayList<Int>(bits.countOneBits())
        var rest = bits
        while (rest != 0uL) {
            result.add(rest.countTrailingZeroBits())
            rest = rest and (rest - 1uL)
        }
        return result
    }
}
