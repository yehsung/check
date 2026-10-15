import Foundation

// MARK: - 판돈 수수료 (v0.3.54 맥 · 1.0.8 폰)
//
// 오목·체스 1:1 대국의 승자 상금 2×판돈에서 **반올림 10%** 를 뗀다(사장님 결정 2026-10-15).
// 서버 정본은 `public.duel_fee(p_stake int)` = `(2*p_stake*10 + 50) / 100` (마이그레이션 20261015120000_duel_fee.sql)이고,
// 이 타입은 그 식을 **글자 그대로** 한 벌 더 들고 있다 — 서버는 상금 금액을 응답에 싣지 않으므로(대국 RPC 응답에
// prize·fee 키가 없다) 결과 카드의 "+N" 과 판돈 고르기의 "이기면 +N" 은 클라가 계산한다.
//
//   판돈  수수료  승자 수령(2×판돈−수수료)  순이익(결과 카드 눈금)
//     3      1          5                    +2
//     5      1          9                    +4
//    10      2         18                    +8
//
// 무승부·환불·취소엔 수수료가 없다(그 갈래는 이 타입을 부르지 않는다). AI·로봇 대국은 판돈 0 이라 수수료도 0 이다.
//
// ⚠️ **두 식이 갈리면 결과 카드와 잔량 칩이 한 화면에서 다른 숫자를 말한다**(잔량은 서버 값이다). 서버 식을 바꾸는 날
//    이 식도 같이 바꾸고, `V0354DuelFeeTests` 의 표(서버와 같은 정수식이 아니라 **손으로 적은 값**)를 같이 고친다.

package nonisolated enum DuelFee {
    /// 수수료 비율(%). 문구("수수료 10%")가 이 값을 쓴다 — 숫자를 문장마다 다시 적지 않는다.
    package static let percent = 10

    /// 이 판돈의 수수료(루비). 상금 2×판돈의 10% 를 **반올림**(0.5 는 올림)한다 — 서버 `duel_fee` 와 같은 정수식.
    /// 음수 판돈은 0 으로 접는다(서버에 그런 판은 없다 — 방어선일 뿐이다).
    package static func fee(stake: Int) -> Int {
        let pot = 2 * max(0, stake)
        return (pot * percent + 50) / 100
    }

    /// 이긴 사람이 정산 때 받는 루비(2×판돈 − 수수료). 수락 때 이미 판돈을 냈으므로 **순이익이 아니다**.
    package static func winnerPayout(stake: Int) -> Int {
        2 * max(0, stake) - fee(stake: stake)
    }

    /// 이긴 사람의 순이익(판돈 − 수수료). 결과 카드의 "+N" 과 "이기면 +N" 이 이 값이다.
    package static func winnerNet(stake: Int) -> Int {
        max(0, stake) - fee(stake: stake)
    }
}
