import Foundation

// 아잉 뒤집기(내부 이름 reversi) 규칙의 **안 표현** — 비트보드(UInt64 둘). 설계: flip/SPEC.md §4.1.
//
// 공개 표면(`ReversiRules` · `ReversiBoard`)은 idx·문자열 기반으로 고정이고, 이 파일은 그 밑의 계산만 한다.
// AI(R2 엔진)가 같은 계산을 노드마다 부르므로 할당 없이 비트 연산만 쓴다.
//
// ── 비트 배치 ──
// 비트 i = 칸 idx i (idx = row*8 + col, row 0 = 1행 위, col 0 = a열 왼쪽 — rules.md V-01).
// 그래서 열 +1 은 비트 +1, 행 +1 은 비트 +8 이다.
//
// ── 판 끝 넘김 막기(사례 C04~C07) ──
// 1차원 비트 이동은 행 끝에서 다음 행 첫 칸으로 감아 넘어간다(h4 +1 = a5). 그래서 열이 바뀌는 여섯 방향은 이동한 뒤
// **도착한 칸이 반대쪽 끝 열이면 지운다**(가면 mask): 동쪽 계열(+1·+9·−7)은 a열 도착을, 서쪽 계열(−1·+7·−9)은 h열 도착을 지운다.
// 위아래(±8)는 64비트 밖으로 밀려 나가 저절로 0 이 된다(음수 idx 로 감아 읽는 결함이 원천적으로 없다).

nonisolated enum ReversiBits {
    /// a열(col 0) 비트를 뺀 가면 — 동쪽으로 옮긴 뒤 a열에 도착했다면 h열에서 감아 넘어온 것이다.
    static let notAFile: UInt64 = 0xFEFE_FEFE_FEFE_FEFE
    /// h열(col 7) 비트를 뺀 가면 — 서쪽으로 옮긴 뒤 h열에 도착했다면 a열에서 감아 넘어온 것이다.
    static let notHFile: UInt64 = 0x7F7F_7F7F_7F7F_7F7F

    /// 8방향 한 칸 이동. `direction` 0…7 = 동·서·남·북·남동·남서·북동·북서(순서는 결과에 영향이 없다).
    @inline(__always)
    static func shift(_ bits: UInt64, _ direction: Int) -> UInt64 {
        switch direction {
        case 0: return (bits << 1) & notAFile   // 동(col+1)
        case 1: return (bits >> 1) & notHFile   // 서(col−1)
        case 2: return bits << 8                // 남(row+1)
        case 3: return bits >> 8                // 북(row−1)
        case 4: return (bits << 9) & notAFile   // 남동(row+1, col+1)
        case 5: return (bits << 7) & notHFile   // 남서(row+1, col−1)
        case 6: return (bits >> 7) & notAFile   // 북동(row−1, col+1)
        default: return (bits >> 9) & notHFile  // 북서(row−1, col−1)
        }
    }

    /// `own` 이 둘 수 있는 칸들(빈칸 중 상대 돌을 한 방향 이상 끼우는 칸, V-06).
    /// 방향마다 "내 돌 → 상대 돌 1~6개 → 빈칸"을 한꺼번에 민다(한 줄에 끼울 수 있는 상대 돌은 최대 6개).
    static func moves(own: UInt64, opp: UInt64) -> UInt64 {
        let empty = ~(own | opp)
        var result: UInt64 = 0
        for direction in 0..<8 {
            var run = shift(own, direction) & opp
            run |= shift(run, direction) & opp
            run |= shift(run, direction) & opp
            run |= shift(run, direction) & opp
            run |= shift(run, direction) & opp
            run |= shift(run, direction) & opp
            result |= shift(run, direction) & empty
        }
        return result
    }

    /// `square` 에 `own` 을 두면 뒤집힐 상대 돌(V-07·V-08). 빈칸이 아니거나 하나도 못 끼우면 0.
    /// 방향마다 상대 돌이 이어지는 동안 모으고, 바로 다음 칸이 내 돌일 때만 그 줄을 뒤집는다 —
    /// 빈칸·판 끝(이동 결과 0)이면 그 줄은 없다. 새로 뒤집힌 돌이 또 끼우는 연쇄는 없다(V-08).
    static func flips(own: UInt64, opp: UInt64, square: Int) -> UInt64 {
        let placed: UInt64 = 1 << UInt64(square)
        guard (own | opp) & placed == 0 else { return 0 }
        var all: UInt64 = 0
        for direction in 0..<8 {
            var line: UInt64 = 0
            var cursor = shift(placed, direction)
            while cursor & opp != 0 {
                line |= cursor
                cursor = shift(cursor, direction)
            }
            if cursor & own != 0 { all |= line }
        }
        return all
    }

    /// 수 세기(V-17, `ply_pass` 관례): 패스도 한 수(깊이 1)로 세고, depth 전에 끝난 판은 세지 않는다.
    static func perft(own: UInt64, opp: UInt64, depth: Int) -> Int {
        if depth == 0 { return 1 }
        let available = moves(own: own, opp: opp)
        if available == 0 {
            // 둘 곳이 없다: 상대가 둘 수 있으면 자동 패스(한 수), 아니면 끝난 판(0).
            guard moves(own: opp, opp: own) != 0 else { return 0 }
            return perft(own: opp, opp: own, depth: depth - 1)
        }
        if depth == 1 { return available.nonzeroBitCount }
        var total = 0
        var rest = available
        while rest != 0 {
            let square = rest.trailingZeroBitCount
            rest &= rest - 1
            let flipped = flips(own: own, opp: opp, square: square)
            let mine = own | flipped | (1 << UInt64(square))
            total += perft(own: opp & ~flipped, opp: mine, depth: depth - 1)
        }
        return total
    }

    /// 비트 집합 → idx 오름차순 배열.
    static func indices(_ bits: UInt64) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(bits.nonzeroBitCount)
        var rest = bits
        while rest != 0 {
            result.append(rest.trailingZeroBitCount)
            rest &= rest - 1
        }
        return result
    }
}
