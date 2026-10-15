import Foundation
import Testing
@testable import check
@testable import CheckCore

/// v0.3.54 판돈 수수료 10% — 승자 상금 2×판돈에서 반올림 10% 를 뗀다(서버 `duel_fee`).
///
/// ★ 기대값은 **손으로 적은 표**다(설계서: 판돈 3/5/10 → 수수료 1/1/2 · 승자 수령 5/9/18 · 순이익 +2/+4/+8).
///   `DuelFee` 식이나 서버 정수식으로 기대값을 만들면 식이 틀려도 초록이다.
///
/// ★ 스토어 단언은 **실서버 픽스처 원문**(수수료 전 서버의 녹화본)에 판돈·내 색만 바꿔 먹인다 — 응답 모양은 실물이고,
///   결과 카드 숫자(`rubyDelta`)는 클라 계산이라 서버 녹화 시점과 무관하다. 픽스처의 `ruby_balance` 는 녹화 당시 값(수수료 전)이라
///   여기서는 재지 않는다 — 잔량은 서버 값을 옮기는 칸이고, 재생 하네스로 다시 녹화하는 날 V0327 계약 테스트가 그 숫자를 고친다.
@Suite("v0.3.54 판돈 수수료")
struct V0354DuelFeeTests {

    // MARK: - 식

    @Test("수수료 표: 3/5/10 → 1/1/2 · 수령 5/9/18 · 순이익 +2/+4/+8 · 0 과 음수는 0")
    func feeTable() {
        let table: [(stake: Int, fee: Int, payout: Int, net: Int)] = [
            (3, 1, 5, 2),
            (5, 1, 9, 4),
            (10, 2, 18, 8),
            (0, 0, 0, 0),      // AI·로봇 대국(판돈 0)
            (-5, 0, 0, 0),     // 방어선 — 서버에 그런 판은 없다
            (1, 0, 2, 1),      // 0.2 → 0
            (2, 0, 4, 2),      // 0.4 → 0
            (13, 3, 23, 10),   // 2.6 → 3
            (25, 5, 45, 20),   // 5.0 → 5
            (15, 3, 27, 12),   // 3.0 → 3
            (7, 1, 13, 6),     // 1.4 → 1
            (8, 2, 14, 6),     // 1.6 → 2
        ]
        for row in table {
            #expect(DuelFee.fee(stake: row.stake) == row.fee, "판돈 \(row.stake) 수수료")
            #expect(DuelFee.winnerPayout(stake: row.stake) == row.payout, "판돈 \(row.stake) 승자 수령")
            #expect(DuelFee.winnerNet(stake: row.stake) == row.net, "판돈 \(row.stake) 순이익")
        }
        #expect(DuelFee.percent == 10)
    }

    /// 서버는 `(2*s*10 + 50) / 100`(0.5 올림)이다. 정수 판돈에서는 2s×0.1 = s/5 라 소수부가 0·.2·.4·.6·.8 뿐이고 **.5 가 생기지
    /// 않는다** — 그래서 올림/짝수 반올림이 갈리는 자리가 없고, 정수식은 "가장 가까운 정수"와 같아야 한다. 부동소수 반올림을
    /// 독립 기준선으로 1~100 전부 잰다(정수식을 다시 적어 기대값을 만들지 않는다).
    @Test("정수 판돈 1~100: 수수료 = 상금 10% 의 가장 가까운 정수 · .5 경계는 생기지 않는다")
    func roundsToNearest() {
        for stake in 1...100 {
            let exact = Double(2 * stake) * 0.1
            #expect(abs(exact.truncatingRemainder(dividingBy: 1) - 0.5) > 1e-9, "판돈 \(stake) 에서 .5 경계가 생겼다")
            #expect(DuelFee.fee(stake: stake) == Int(exact.rounded(.toNearestOrAwayFromZero)), "판돈 \(stake)")
            #expect(DuelFee.winnerNet(stake: stake) + DuelFee.fee(stake: stake) == stake, "순이익 + 수수료 = 판돈")
            #expect(DuelFee.winnerPayout(stake: stake) == stake + DuelFee.winnerNet(stake: stake), "수령 = 낸 판돈 + 순이익")
        }
    }

    // MARK: - 오목 스토어 — 결과 카드 숫자

    @MainActor
    @Test("오목: 판돈 3/5/10 승리 → +2/+4/+8 · 패배 → −판돈 · 무승부 → 0 (실서버 픽스처)")
    func gomokuWinnerSeesNet() throws {
        let winBase = try Self.fixture("gomoku-rpc", "gomoku_state__finished_since9")   // black_win · 녹화 시점 내 색 white
        for (stake, net) in [(3, 2), (5, 4), (10, 8)] {
            let won = GomokuStore(host: nil)
            won.applyState(try Self.gomokuPayload(winBase, stake: stake, myColor: "black"))
            #expect(won.match?.outcome == .won)
            #expect(won.match?.rubyDelta == net, "오목 판돈 \(stake) 승리: \(won.match?.rubyDelta.map(String.init) ?? "nil")")
            // 기준선: 수수료 전 식(+판돈)이면 여기서 갈린다.
            #expect(won.match?.rubyDelta != stake)

            let lost = GomokuStore(host: nil)
            lost.applyState(try Self.gomokuPayload(winBase, stake: stake, myColor: "white"))
            #expect(lost.match?.outcome == .lost)
            #expect(lost.match?.rubyDelta == -stake, "패배는 낸 판돈 그대로 — 수수료와 무관")
        }
        let drawBase = try Self.fixture("gomoku-rpc", "gomoku_move__board_full_draw")
        let drawn = GomokuStore(host: nil)
        drawn.applyState(try Self.gomokuPayload(drawBase, stake: 10, myColor: nil))
        #expect(drawn.match?.outcome == .draw)
        #expect(drawn.match?.rubyDelta == 0, "무승부엔 수수료가 없다(환불)")
    }

    // MARK: - 체스 스토어

    @MainActor
    @Test("체스: 판돈 3/5/10 승리 → +2/+4/+8 · 패배 → −판돈 · 무승부(시간패 불충분) → 0 (실서버 픽스처)")
    func chessWinnerSeesNet() throws {
        let winBase = try Self.fixture("chess-rpc-clock10", "chess_state__ok_finished_winner")   // white_win · 내 색 white
        for (stake, net) in [(3, 2), (5, 4), (10, 8)] {
            let won = ChessStore(host: nil)
            won.applyState(try Self.chessPayload(winBase, stake: stake, myColor: "white"))
            #expect(won.match?.outcome == .won)
            #expect(won.match?.rubyDelta == net, "체스 판돈 \(stake) 승리: \(won.match?.rubyDelta.map(String.init) ?? "nil")")
            #expect(won.match?.rubyDelta != stake)

            let lost = ChessStore(host: nil)
            lost.applyState(try Self.chessPayload(winBase, stake: stake, myColor: "black"))
            #expect(lost.match?.outcome == .lost)
            #expect(lost.match?.rubyDelta == -stake)
        }
        let drawBase = try Self.fixture("chess-rpc", "chess_state__end_timeout_insufficient")
        let drawn = ChessStore(host: nil)
        drawn.applyState(try Self.chessPayload(drawBase, stake: 10, myColor: nil))
        #expect(drawn.match?.outcome == .draw)
        #expect(drawn.match?.rubyDelta == 0)
    }

    // MARK: - 헬퍼

    static let fixtureRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    static func fixture(_ folder: String, _ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: fixtureRoot.appendingPathComponent("\(folder)/\(name).json"))
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else { throw V0354RulesError("\(name) 는 객체가 아니다") }
        // 쓰기 RPC 응답은 판 묶음을 `state` 에 싣는다(최상위에도 같은 것을 싣는 녹화본도 있다).
        if dict["match"] == nil, let state = dict["state"] as? [String: Any] { return state }
        return dict
    }

    /// 판돈·내 색만 바꾼다(nil 이면 녹화 그대로). 나머지 글자는 서버가 낸 그대로다.
    static func mutated(_ base: [String: Any], stake: Int, myColor: String?) throws -> Data {
        var payload = base
        guard var match = payload["match"] as? [String: Any] else { throw V0354RulesError("match 가 없다") }
        match["stake"] = stake
        payload["match"] = match
        if let myColor { payload["my_color"] = myColor }
        payload.removeValue(forKey: "state")
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func gomokuPayload(_ base: [String: Any], stake: Int, myColor: String?) throws -> GomokuStatePayload {
        try V0354GachaWireTests.decoder().decode(GomokuStatePayload.self, from: try mutated(base, stake: stake, myColor: myColor))
    }

    static func chessPayload(_ base: [String: Any], stake: Int, myColor: String?) throws -> ChessStatePayload {
        try V0354GachaWireTests.decoder().decode(ChessStatePayload.self, from: try mutated(base, stake: stake, myColor: myColor))
    }
}
