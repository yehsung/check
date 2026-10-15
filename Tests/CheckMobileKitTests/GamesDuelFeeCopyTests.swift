import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰 판돈 문구 · 결과 폴백 — v0.3.54 판돈 수수료 10%(승자 상금 2×판돈에서 반올림 10% 를 뗀다).
///
/// 서버 응답엔 상금 키가 없어 "이기면 +N" 과 결과 카드의 +N 은 **클라가 센다**(`DuelFee`). 이 파일은 사용자가 읽는 글자를 잰다 —
/// 기대값은 **손으로 적은 표**다(3/5/10 → 순이익 +2/+4/+8 · 수수료 1/1/2). `DuelFee` 로 기대값을 다시 만들면 식이 틀려도 초록이다.
@Suite("판돈 수수료 문구(폰 · v0.3.54)")
struct GamesDuelFeeCopyTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func code(_ relative: String) throws -> String {
        stripComments(try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
    }

    /// 손으로 적은 표(사장님 결정 2026-10-15): 판돈 → 이기면 순이익.
    static let netTable: [(stake: Int, net: Int)] = [(3, 2), (5, 4), (10, 8)]

    @Test("오목·체스 '이기면 +N' 은 순이익(3/5/10 → +2/+4/+8) — 줄 · 꼬리 · 칸 아래 줄 · 신청 시트 머리")
    func gainLinesShowNet() {
        for (stake, net) in Self.netTable {
            #expect(GomokuPhoneText.stakeLine(stake) == "\(stake) · 이기면 +\(net)")
            #expect(GomokuPhoneText.stakeGainSuffix(stake) == " · 이기면 +\(net)")
            #expect(GomokuPhoneText.stakeGain(stake) == "이기면 +\(net)")
            #expect(GomokuPhoneText.stakePromptChosen(stake) == "판돈 \(stake) · 이기면 +\(net)")
            #expect(ChessPhoneText.stakeLine(stake) == "\(stake) · 이기면 +\(net)")
            #expect(ChessPhoneText.stakeGainSuffix(stake) == " · 이기면 +\(net)")
            #expect(ChessPhoneText.stakeGain(stake) == "이기면 +\(net)")
            #expect(ChessPhoneText.stakePromptChosen(stake) == "판돈 \(stake) · 이기면 +\(net)")
            // 기준선: 수수료 전 문장(+판돈)과 달라야 한다 — 같으면 이 테스트는 수수료가 사라져도 초록이다.
            #expect(GomokuPhoneText.stakeGain(stake) != "이기면 +\(stake)")
        }
    }

    @Test("캡션·규칙 줄은 수수료 10% 를 한 번 말하고, 맥과 같은 '판돈만큼 더' 문장을 지킨다 · 수락 시점도 그대로")
    func captionsMentionFeeOnce() throws {
        let caption = "수락하는 순간 두 사람 모두 걸고, 이기면 판돈만큼 더 받아요(수수료 10% 빼고)"
        #expect(GomokuPhoneText.stakeCaption == caption)
        #expect(ChessPhoneText.stakeCaption == caption)
        let gomokuRule = try #require(GomokuPhoneRuleExample.ruleLines.last)
        #expect(gomokuRule == "수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고(수수료 10% 빼고), 무승부면 건 판돈을 돌려받아요.")
        // 맥 V0327GomokuPanelRenderTests 가 맥 규칙 줄[6]에 "판돈만큼 더" 를 요구한다 — 폰도 같은 말을 쓴다.
        #expect(GomokuPhoneRuleExample.ruleLines[6].contains("판돈만큼 더"))
        let chessStake = try #require(ChessPhoneRuleLine.all().first { $0.title == "판돈" })
        #expect(chessStake.detail.contains("수수료 10%"), "체스 규칙 시트의 판돈 줄이 수수료를 말하지 않는다: \(chessStake.detail)")
        for line in [GomokuPhoneText.stakeCaption, gomokuRule, chessStake.detail] {
            #expect(line.components(separatedBy: "수수료").count - 1 == 1, "수수료를 두 번 말한다: \(line)")
            for word in ["도박", "베팅"] { #expect(!line.contains(word)) }
        }
    }

    @Test("체스 결과 폴백(서버 값이 없을 때): 이기면 순이익 · 지면 −판돈 · 무승부 ±0 + 환불 줄 · 서버 값이 있으면 그 값")
    func chessResultFallback() throws {
        for (stake, net) in Self.netTable {
            let won = try #require(Self.chrome(Self.chessMatch(stake: stake, outcome: .won)).result)
            #expect(won.rubyDelta == net && won.rubyDeltaText == "+\(net)", "판돈 \(stake) 승리: \(won.rubyDeltaText)")
            let lost = try #require(Self.chrome(Self.chessMatch(stake: stake, outcome: .lost)).result)
            #expect(lost.rubyDelta == -stake, "패배엔 수수료가 없다(건 판돈만 잃는다)")
            let draw = try #require(Self.chrome(Self.chessMatch(stake: stake, outcome: .draw)).result)
            #expect(draw.rubyDelta == 0 && draw.rubyNote == ChessPhoneText.drawRefund(stake: stake), "무승부 환불엔 수수료가 없다")
        }
        let given = try #require(Self.chrome(Self.chessMatch(stake: 10, outcome: .won, rubyDelta: 10)).result)
        #expect(given.rubyDelta == 10, "서버(코어 스토어)가 준 값을 클라가 다시 셌다")
    }

    @Test("소스: 오목 판돈 시트 칸 아래 줄과 오목 대국 결과 폴백(iOS 전용 뷰)이 수수료 식을 거친다 — 숫자를 다시 적지 않는다")
    func iosOnlyViewsUseTheFee() throws {
        let sheets = try Self.code("Sources/CheckMobileKit/Games/GamesGomokuSheets.swift")
        #expect(sheets.contains("GomokuPhoneText.stakeGain(stake.rawValue)"), "판돈 칸 아래 줄이 공용 문구(순이익)를 안 쓴다")
        #expect(!sheets.contains(#"Text("이기면 +\(stake.rawValue)")"#), "판돈 칸 아래 줄이 다시 +판돈을 박았다")
        let match = try Self.code("Sources/CheckMobileKit/Games/GamesGomokuMatch.swift")
        #expect(match.contains("case .won?: return DuelFee.winnerNet(stake: match.stake)"), "오목 결과 폴백이 수수료를 안 뗀다")
        #expect(!match.contains("case .won?: return match.stake"), "오목 결과 폴백이 다시 +판돈이다")
    }

    // MARK: - 도우미

    static let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    static func chessMatch(stake: Int, outcome: ChessMatchOutcome, rubyDelta: Int? = nil) -> ChessMatchState {
        let peer = ChessUser(id: "00000000-0000-0000-0000-0000000000fe", displayName: "구름빵", avatarURL: nil,
                             characterID: "fox", isWorking: true, isCapable: true, inMatch: true, center: "seoul")
        let reason: ChessEndReason = outcome == .draw ? .agreement : (outcome == .won ? .checkmate : .resign)
        return ChessMatchState(
            id: "match-fee-\(stake)", stake: stake, myColor: .white, opponent: peer, fen: fen,
            position: ChessPosition(fen: fen), plyCount: 30, turn: nil, lastMove: nil, moves: [], clock: .initial,
            isInCheck: false, legalMoves: [], isFinished: true, outcome: outcome, endReason: reason,
            rubyDelta: rubyDelta, drawOfferBy: nil, drawOfferedByMe: false, whiteGraceMs: nil, blackGraceMs: nil)
    }

    static func chrome(_ match: ChessMatchState) -> GamesChessMatchChrome {
        GamesChessMatchChrome(match: match, promotion: nil, notice: nil, isBusy: false, isRobotMatch: false,
                              initialMs: ChessClock.initialMs)
    }
}
