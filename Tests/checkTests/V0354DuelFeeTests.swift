import Foundation
import Testing
@testable import check
@testable import CheckCore

/// 판돈 수수료 — v0.3.54 에 10% 를 뗐고 **v0.3.64 에 없앴다**(사용자 결정 2026-10-22 "멀티 미니게임 수수료 다시 제거해줘",
/// 서버 `20261023132000_duel_fee_off.sql` 이 `duel_fee` 를 0 으로). 이긴 사람은 2×판돈을 받는다(순이익 +판돈).
///
/// ★ 기대값은 **손으로 적은 표**다(명세: 판돈 3/5/10 → 수수료 0 · 승자 수령 6/10/20 · 순이익 +3/+5/+10).
///   `DuelFee` 식이나 서버 정수식으로 기대값을 만들면 식이 틀려도 초록이다.
///
/// ★ 스토어 단언은 **실서버 픽스처 원문**(수수료 전 서버의 녹화본)에 판돈·내 색만 바꿔 먹인다 — 응답 모양은 실물이고,
///   결과 카드 숫자(`rubyDelta`)는 클라 계산이라 서버 녹화 시점과 무관하다. 픽스처의 `ruby_balance` 는 녹화 당시 값이라
///   여기서는 재지 않는다 — 잔량은 서버 값을 옮기는 칸이다.
@Suite("판돈 수수료 — v0.3.64 에 0")
struct V0354DuelFeeTests {

    // MARK: - 식

    @Test("수수료 표: 3/5/10 → 0/0/0 · 수령 6/10/20 · 순이익 +3/+5/+10 · 0 과 음수는 0")
    func feeTable() {
        let table: [(stake: Int, fee: Int, payout: Int, net: Int)] = [
            (3, 0, 6, 3),
            (5, 0, 10, 5),
            (10, 0, 20, 10),
            (0, 0, 0, 0),      // AI·로봇 대국(판돈 0)
            (-5, 0, 0, 0),     // 방어선 — 서버에 그런 판은 없다
            (1, 0, 2, 1),
            (13, 0, 26, 13),
            (25, 0, 50, 25),
        ]
        for row in table {
            #expect(DuelFee.fee(stake: row.stake) == row.fee, "판돈 \(row.stake) 수수료")
            #expect(DuelFee.winnerPayout(stake: row.stake) == row.payout, "판돈 \(row.stake) 승자 수령")
            #expect(DuelFee.winnerNet(stake: row.stake) == row.net, "판돈 \(row.stake) 순이익")
        }
        #expect(DuelFee.percent == 0)
    }

    /// 판돈 1~100 전부: 수수료 0 · 수령 = 2×판돈 · 순이익 = 판돈. 기준선으로 **옛 식**(반올림 10%)이 판돈 3 이상에서 갈리는 것을 같이 잰다 —
    /// 옛 식이 되살아나면 여기가 빨갛다.
    @Test("정수 판돈 1~100: 수수료 0 · 수령 2×판돈 · 순이익 = 판돈 (옛 반올림 10% 식과 갈린다)")
    func noFeeAnywhere() {
        for stake in 1...100 {
            #expect(DuelFee.fee(stake: stake) == 0, "판돈 \(stake)")
            #expect(DuelFee.winnerPayout(stake: stake) == 2 * stake, "판돈 \(stake) 수령")
            #expect(DuelFee.winnerNet(stake: stake) == stake, "판돈 \(stake) 순이익")
            let oldFee = (2 * stake * 10 + 50) / 100
            if stake >= 3 { #expect(oldFee > 0 && DuelFee.winnerNet(stake: stake) != stake - oldFee, "기준선: 판돈 \(stake) 에서 옛 식과 같다") }
        }
    }

    // MARK: - 오목 스토어 — 결과 카드 숫자

    @MainActor
    @Test("오목: 판돈 3/5/10 승리 → +3/+5/+10 · 패배 → −판돈 · 무승부 → 0 (실서버 픽스처)")
    func gomokuWinnerSeesNet() throws {
        let winBase = try Self.fixture("gomoku-rpc", "gomoku_state__finished_since9")   // black_win · 녹화 시점 내 색 white
        for (stake, net) in [(3, 3), (5, 5), (10, 10)] {
            let won = GomokuStore(host: nil)
            won.applyState(try Self.gomokuPayload(winBase, stake: stake, myColor: "black"))
            #expect(won.match?.outcome == .won)
            #expect(won.match?.rubyDelta == net, "오목 판돈 \(stake) 승리: \(won.match?.rubyDelta.map(String.init) ?? "nil")")
            // 기준선: 수수료 시절 식(판돈 − 반올림 10%)이면 여기서 갈린다.
            #expect(won.match?.rubyDelta != stake - (2 * stake + 5) / 10)

            let lost = GomokuStore(host: nil)
            lost.applyState(try Self.gomokuPayload(winBase, stake: stake, myColor: "white"))
            #expect(lost.match?.outcome == .lost)
            #expect(lost.match?.rubyDelta == -stake, "패배는 낸 판돈 그대로")
        }
        let drawBase = try Self.fixture("gomoku-rpc", "gomoku_move__board_full_draw")
        let drawn = GomokuStore(host: nil)
        drawn.applyState(try Self.gomokuPayload(drawBase, stake: 10, myColor: nil))
        #expect(drawn.match?.outcome == .draw)
        #expect(drawn.match?.rubyDelta == 0, "무승부는 환불")
    }

    // MARK: - 체스 스토어

    @MainActor
    @Test("체스: 판돈 3/5/10 승리 → +3/+5/+10 · 패배 → −판돈 · 무승부(시간패 불충분) → 0 (실서버 픽스처)")
    func chessWinnerSeesNet() throws {
        let winBase = try Self.fixture("chess-rpc-clock10", "chess_state__ok_finished_winner")   // white_win · 내 색 white
        for (stake, net) in [(3, 3), (5, 5), (10, 10)] {
            let won = ChessStore(host: nil)
            won.applyState(try Self.chessPayload(winBase, stake: stake, myColor: "white"))
            #expect(won.match?.outcome == .won)
            #expect(won.match?.rubyDelta == net, "체스 판돈 \(stake) 승리: \(won.match?.rubyDelta.map(String.init) ?? "nil")")
            #expect(won.match?.rubyDelta != stake - (2 * stake + 5) / 10)

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
