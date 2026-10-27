// 원본: Sources/CheckCore/DuelFee.swift @ 1b8260d (골든 생성기 — W1-b)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// W1-b 골든(판돈 수수료, C§5.1 E10 · G1 함수 표): 판돈 −5…100 → 수수료 · 승자 수령 · 순이익.
// v0.3.64(2026-10-22 사용자 결정 "멀티 미니게임 수수료 다시 제거해줘")부터 수수료는 0 이다 — 이 표는 **지금 Swift 값 그대로**다.
// 생성기는 손으로 적은 명세(수수료 0 · 수령 2×판돈 · 순이익 = 판돈, 음수 판돈은 0)와 먼저 대조한다(V0354DuelFeeTests 와 같은 기준).

@Suite("GoldenExport games-board — 판돈 수수료(duel-fee/fee)")
struct GoldenExportGamesBoardDuelFee {
    @Test("duel-fee/fee — 판돈 −5…100: 수수료 · 승자 수령 · 순이익 + 비율 상수")
    func duelFee() {
        var cases: [GoldenJSON] = []
        for stake in -5...100 {
            let fee = DuelFee.fee(stake: stake)
            let payout = DuelFee.winnerPayout(stake: stake)
            let net = DuelFee.winnerNet(stake: stake)
            // 손으로 적은 명세(식에서 기대값을 만들지 않는다).
            #expect(fee == 0, "판돈 \(stake) 수수료 \(fee)")
            #expect(payout == (stake > 0 ? 2 * stake : 0), "판돈 \(stake) 수령 \(payout)")
            #expect(net == (stake > 0 ? stake : 0), "판돈 \(stake) 순이익 \(net)")
            cases.append([
                "id": .string("stake-\(stake < 0 ? "m\(-stake)" : "\(stake)")"),
                "stake": .int(stake),
                "fee": .int(fee),
                "payout": .int(payout),
                "net": .int(net),
            ])
        }
        cases.append(["id": "percent", "percent": .int(DuelFee.percent)])
        goldenEmit(GoldenFile(
            golden: "duel-fee/fee",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/DuelFee.swift"],
            spec: [
                "fee": "DuelFee.fee(stake:) = 2·max(0, stake)·percent / 100(정수, 0 쪽 버림). percent 는 0(v0.3.64 — 서버 duel_fee 도 0, 20261023132000_duel_fee_off.sql).",
                "payout": "DuelFee.winnerPayout(stake:) = 2·max(0, stake) − fee — 승자가 정산 때 받는 루비(수락 때 판돈을 이미 냈다).",
                "net": "DuelFee.winnerNet(stake:) = max(0, stake) − fee — 결과 카드의 \"+N\".",
                "range": "판돈 −5…100(G1 판돈 0~100 + 음수 방어선). 서버 판돈은 3·5·10 뿐이다.",
            ],
            cases: cases
        ))
    }
}
