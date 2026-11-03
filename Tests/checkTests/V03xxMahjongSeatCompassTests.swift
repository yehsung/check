@testable import check
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

    @Test("기준선 — 큐브 방위(RummySeatCompass)에 같은 입력을 넣으면 하가(1)가 왼쪽이다 · 마작은 오른쪽")
    func cubeCompassDiffersFromMahjong() {
        // 없으면: 큐브 방위 함수를 그대로 빌려 써도 '하가 오른쪽' 시험이 같은 값을 재는지 알 수 없다(갈리는 기준선).
        #expect(RummySeatCompass.of(seatNo: 1, mySeatNo: 0, seatNos: [0, 1, 2, 3]) == .left)
        #expect(MahjongSeatCompass.of(seat: 1, mySeat: 0) == .right)
        #expect(RummySeatCompass.of(seatNo: 3, mySeatNo: 2, seatNos: [0, 1, 2, 3]) == .left)
        #expect(MahjongSeatCompass.of(seat: 3, mySeat: 2) == .right)
    }

    @Test("치 단추는 상가(왼쪽) 버림에만 — 네 자리 모두에서")
    func chiOnlyFromTheLeft() {
        // 없으면: 하가·대면 버림에도 치 단추가 떠 서버가 illegal 로 거절한다.
        for me in 0..<4 {
            let allowed = (0..<4).filter { MahjongSeatCompass.canChi(fromSeat: $0, mySeat: me) }
            #expect(allowed == [(me + 3) % 4])
            #expect(MahjongSeatCompass.of(seat: allowed[0], mySeat: me) == .left)
        }
    }
}
