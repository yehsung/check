import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 생각 시간 5초 + 예비 20초(MJ-53, DEC:11) — SQL `mahjong_clock_deadline`·`mahjong_clock_charge` 쌍둥이 표와
// 시간 초과 자동 동작(MJ-54, SPEC §2.3 K-1 — v1.0.1 정정: 론·쯔모 선택지가 있으면 자동 화료).
// 서버는 timestamptz(µs 정수)에서 `floor(extract(epoch from 도착 − 시작) * 1000)` 로 ms 를 잰다(체스 시계 틀, CD:837).

@Suite("아잉 마작 시계 — 5+20 · 유예는 마감만 · ms 자르기 · 시간 초과 동작")
struct MahjongClockTests {
    /// 소수 초가 정확히 떨어지지 않는 시작 시각(실제 now 와 같은 꼴).
    private static let start = Date(timeIntervalSince1970: 1_762_150_000.123_456)

    private static func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    // 없으면: 예비 차감·유예·시간 초과 경계가 서버와 갈려, 서버가 받은 답을 연습판(로컬)은 시간 초과로 보거나 남은 예비가 다르게 보인다.
    @Test("시계 표 — 4.9s 예비 그대로 · 5.1s 예비 19.9 · 25.9s 유예 안(예비 0) · 26.1s 시간 초과 · 음수 경과 0")
    func chargeTable() {
        let rows: [(Double, Int, Int, Int, Bool)] = [
            // (경과 초, 남은 예비 입력, 기대 bankLeft, 기대 usedMs, 기대 timedOut)
            (4.9, 20_000, 20_000, 4_900, false),
            (5.0, 20_000, 20_000, 5_000, false),
            (5.1, 20_000, 19_900, 5_100, false),
            (25.0, 20_000, 0, 25_000, false),
            (25.9, 20_000, 0, 25_900, false),   // 유예(1초) 안 — 받고 예비는 0
            (26.0, 20_000, 0, 26_000, false),   // 판정 마감과 같으면 받는다
            (26.1, 20_000, 0, 26_100, true),
            (7.5, 3_000, 500, 7_500, false),
            (8.9, 3_000, 0, 8_900, false),
            (9.1, 3_000, 0, 9_100, true),
            (5.9, 0, 0, 5_900, false),
            (6.1, 0, 0, 6_100, true),
            (-2.0, 20_000, 20_000, 0, false),    // 시계 역행 — 경과 0
        ]
        for (elapsed, bank, left, used, out) in rows {
            let r = MahjongClock.charge(started: Self.start, arrived: Self.at(elapsed), bankMs: bank)
            #expect(r.bankLeft == left && r.usedMs == used && r.timedOut == out, "\(elapsed)s bank \(bank) → \(r)")
        }
        // 마감은 유예를 넣지 않는다(유예는 판정에만 — D8).
        #expect(MahjongClock.deadline(started: Self.start, bankMs: 20_000) == Self.at(25))
        #expect(MahjongClock.deadline(started: Self.start, bankMs: -5) == Self.at(5), "음수 예비는 0")
    }

    // 없으면: Double 초를 바로 ×1000 해 버리면 5.1초가 5099ms 로 떨어져 서버(µs 정수)보다 1ms 적게 깎인다 — 경계에서 쌍둥이가 갈린다.
    @Test("ms 자르기 = 서버 µs 정수 꼴 · 기준선: Double 초를 바로 버리면 1ms 모자라는 경계가 있다")
    func millisecondTruncation() {
        var naiveShort = 0
        for k in 0..<2_000 {
            let micros = 4_000_000 + k * 1_000   // ms 경계에 딱 떨어지는 도착 — 서버(µs 정수)는 그 ms 를 그대로 센다
            let arrived = Self.start.addingTimeInterval(Double(micros) / 1_000_000)
            let r = MahjongClock.charge(started: Self.start, arrived: arrived, bankMs: 20_000)
            #expect(r.usedMs == micros / 1000, "\(micros)µs")
            let naive = Int((arrived.timeIntervalSince(Self.start) * 1000).rounded(.down))
            if naive != micros / 1000 { naiveShort += 1 }
        }
        #expect(naiveShort > 0, "기준선: Double 초를 바로 버리는 셈은 어딘가에서 1ms 모자란다")
    }

    // 없으면: 화면의 남은 시간(기본 → 예비 순으로 줄어듦)이 서버 시계와 다른 순서로 줄어든다.
    @Test("remaining — 기본 5초가 먼저 줄고 그다음 예비 · 음수 없음")
    func remainingDisplay() {
        let a = MahjongClock.remaining(started: Self.start, bankMs: 20_000, now: Self.at(3))
        #expect(abs(a.baseLeft - 2) < 1e-6 && abs(a.bankLeft - 20) < 1e-6)
        let b = MahjongClock.remaining(started: Self.start, bankMs: 20_000, now: Self.at(8))
        #expect(b.baseLeft == 0 && abs(b.bankLeft - 17) < 1e-6)
        let c = MahjongClock.remaining(started: Self.start, bankMs: 20_000, now: Self.at(40))
        #expect(c.baseLeft == 0 && c.bankLeft == 0)
        let d = MahjongClock.remaining(started: Self.start, bankMs: 20_000, now: Self.at(-1))
        #expect(d.baseLeft == 5 && d.bankLeft == 20, "시계 역행은 0초 경과")
    }

    private static func tile(_ id: Int) -> MahjongTile { MahjongTile(id: id)! }

    // 없으면: 시간 초과 자동 동작이 서버 mahjong__timeout_action 과 갈린다 — 쯔모기리 · 쿠이카에 뒤 오른쪽 끝 · 넘김(치·퐁·깡 안 함).
    // 자동 화료(K-1)는 timeoutAutoWin 한 곳에 있고, 자리 비움 자리의 화료 끄기(rules C-18)는 판 진행 몫이다.
    @Test("timeoutAction 셋 — 쯔모기리 · 오른쪽 끝 · 넘김 · 화료는 선택지가 있을 때만(K-1)")
    func timeoutActions() {
        let turn = MahjongDecision.Turn(seq: 3, decisionSeq: 3, startedMs: 0, deadlineMs: 25_000, bankMs: 20_000,
                                        discard: [Self.tile(9), Self.tile(70), Self.tile(33), Self.tile(101)])
        // ① 쯔모기리 — 방금 뽑은 패를 버릴 수 있으면 그 패(오른쪽 끝 101 이 아니라).
        #expect(MahjongRules.timeoutAction(.turn(turn), drawn: Self.tile(33)) == .discard(Self.tile(33)))
        // ② 오른쪽 끝 — 치·퐁 직후(뽑은 패 없음)거나 뽑은 패가 금지면 허용 패 가운데 id 최대.
        #expect(MahjongRules.timeoutAction(.turn(turn), drawn: nil) == .discard(Self.tile(101)))
        #expect(MahjongRules.timeoutAction(.turn(turn), drawn: Self.tile(34)) == .discard(Self.tile(101)), "뽑은 패가 허용 목록 밖")
        // ③ 넘김 — 울기 창에 퐁·치·깡만 있으면 하지 않는다.
        let call = MahjongDecision.Call(windowId: 4, windowKind: "discard", tile: Self.tile(40), fromSeat: 2, startedMs: 0, deadlineMs: 25_000,
                                        bankMs: 20_000, pon: [[Self.tile(41), Self.tile(42)]], minkan: [[Self.tile(41), Self.tile(42), Self.tile(43)]],
                                        chi: [[Self.tile(44), Self.tile(48)]])
        #expect(MahjongRules.timeoutAction(.call(call), drawn: nil) == .pass)
        // 화료(K-1, v1.0.1): 선택지가 있을 때만. 기준선은 위 두 줄(선택지 없음 → 버림·넘김).
        var tsumo = turn
        tsumo.tsumo = true
        var ron = call
        ron.ron = true
        #expect(MahjongRules.timeoutAction(.turn(tsumo), drawn: Self.tile(33)) == (MahjongRules.timeoutAutoWin ? .tsumo : .discard(Self.tile(33))))
        #expect(MahjongRules.timeoutAction(.call(ron), drawn: nil) == (MahjongRules.timeoutAutoWin ? .ron : .pass))
        #expect(MahjongRules.timeoutAutoWin, "v1.0.1 — 켜짐")
        // 암깡·가깡·리치·구종구패 선택지가 있어도 하지 않는다.
        var rich = turn
        rich.riichi = [Self.tile(9)]
        rich.ankan = [[Self.tile(0), Self.tile(1), Self.tile(2), Self.tile(3)]]
        rich.kakan = [Self.tile(70)]
        rich.kyuushu = true
        #expect(MahjongRules.timeoutAction(.turn(rich), drawn: Self.tile(33)) == .discard(Self.tile(33)))
    }
}
