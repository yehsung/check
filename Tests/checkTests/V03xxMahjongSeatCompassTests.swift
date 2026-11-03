@testable import CheckCore
import Testing

// 아잉 마작 자리 → 화면 방위(SPEC §4.5 '방위' · §5.3). 큐브 `RummySeatCompass` 와 갈리는 기준선은 U·C2 렌더 시험이 더한다.

@Suite("아잉 마작 방위 — 내 자리 아래 · 하가 오른쪽")
struct V03xxMahjongSeatCompassTests {
    @Test("방위 — 하가가 오른쪽 · 대면 위 · 상가 왼쪽(내 자리 0 과 2) · 치는 상가 버림에만")
    func seatCompassPutsNextSeatOnTheRight() {
        // 없으면: 큐브 방위(하가 왼쪽)를 베껴 차례가 화면에서 거꾸로 돈다.
        #expect([0, 1, 2, 3].map { MahjongSeatCompass.of(seat: $0, mySeat: 0) } == [.bottom, .right, .top, .left])
        #expect([2, 3, 0, 1].map { MahjongSeatCompass.of(seat: $0, mySeat: 2) } == [.bottom, .right, .top, .left])
        #expect(MahjongCompass.allCases.map { MahjongSeatCompass.seat(at: $0, mySeat: 2) } == [2, 3, 0, 1])
        #expect(MahjongSeatCompass.canChi(fromSeat: 1, mySeat: 2))
        #expect(!MahjongSeatCompass.canChi(fromSeat: 3, mySeat: 2))
    }
}
