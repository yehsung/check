import Foundation

// MARK: - 판돈 수수료 — v0.3.64 에 없앴다(0)
//
// 역사: v0.3.54(2026-10-15)에 1:1 대국 승자 상금 2×판돈에서 반올림 10% 를 뗐다(서버 `duel_fee` = `(2*p_stake*10 + 50) / 100`).
// **2026-10-22 사용자 결정(원문): "멀티 미니게임 수수료 다시 제거해줘"** — 서버 `20261022142000_duel_fee_off.sql` 이 `duel_fee` 를
// 0 으로 바꿨다. 정산 함수 셋(오목 · 체스 · 테트리스)은 그대로 `2*판돈 − duel_fee(판돈)` 를 주므로 이긴 사람은 **2×판돈**을 받는다.
//
//   판돈  수수료  승자 수령(2×판돈)  순이익(결과 카드 눈금)
//     3      0          6               +3
//     5      0         10               +5
//    10      0         20              +10
//
// 이 타입을 지우지 않고 0 으로 남긴 이유: 맥 · 폰 화면의 "이기면 +N" · 결과 카드 대체값이 전부 `winnerNet` 한 자리에서 읽는다 —
// 지우면 그 자리마다 `+판돈` 을 다시 적게 되고, 다음에 수수료가 생기는 날 화면마다 따로 고쳐야 한다(v0.3.54 가 그 일을 했다).
// 서버는 상금 금액을 응답에 싣지 않으므로(대국 RPC 응답에 prize · fee 키가 없다) 이 숫자는 여전히 클라가 계산한다.
//
// ⚠️ **두 식이 갈리면 결과 카드와 잔량 칩이 한 화면에서 다른 숫자를 말한다**(잔량은 서버 값이다). 서버 `duel_fee` 를 바꾸는 날
//    이 값도 같이 바꾸고, `V0354DuelFeeTests` 의 표(**손으로 적은 값**)를 같이 고친다.

package nonisolated enum DuelFee {
    /// 수수료 비율(%). **0**(2026-10-22 사용자 결정). 맥 화면은 이 값을 문장에 쓰지 않는다 — "수수료" 글자 자체를 뺐다.
    package static let percent = 0

    /// 이 판돈의 수수료(루비). 서버 `duel_fee` 와 같은 값 — 지금은 언제나 0 이다.
    package static func fee(stake: Int) -> Int {
        let pot = 2 * max(0, stake)
        return pot * percent / 100
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
