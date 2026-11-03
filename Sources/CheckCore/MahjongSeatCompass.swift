import Foundation

// 아잉 마작 자리 → 화면 방위(SPEC §4.5 '방위' · §5.3). 화면은 늘 내가 아래, **하가(다음 차례)가 오른쪽**, 대면 위, 상가 왼쪽.
// 차례는 0→1→2→3(반시계, MJ-03) — 아래에서 오른쪽으로 돈다. 큐브 `RummySeatCompass` 는 하가가 왼쪽이라 쓰지 않는다(MCL:216).
// 치는 상가(왼쪽)의 버림에만 뜬다(MJ-14).

/// 화면 방위. raw 값 = 내 자리에서 차례 순으로 몇 칸 뒤인가(0 나 · 1 하가 · 2 대면 · 3 상가).
package nonisolated enum MahjongCompass: Int, CaseIterable, Equatable, Hashable, Sendable {
    case bottom = 0
    case right = 1
    case top = 2
    case left = 3
}

package nonisolated enum MahjongSeatCompass {
    /// `seat` 자리가 `mySeat` 기준 어느 방위에 앉는가. 자리 번호는 0~3 밖이어도 4 로 감아 읽는다.
    package static func of(seat: Int, mySeat: Int) -> MahjongCompass {
        MahjongCompass(rawValue: ((seat - mySeat) % 4 + 4) % 4) ?? .bottom
    }

    /// 방위 → 자리 번호(`of` 의 역).
    package static func seat(at compass: MahjongCompass, mySeat: Int) -> Int {
        ((mySeat + compass.rawValue) % 4 + 4) % 4
    }

    /// 치 단추가 뜰 수 있는 버림인가(상가 = 왼쪽의 버림만).
    package static func canChi(fromSeat discarder: Int, mySeat: Int) -> Bool {
        of(seat: discarder, mySeat: mySeat) == .left
    }
}
