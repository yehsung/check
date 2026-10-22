import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰 판돈 문구 · 결과 폴백 — v0.3.54 에 판돈 수수료 10% 를 뗐고 **v0.3.64 에 없앴다**(사용자 결정 2026-10-22
/// "멀티 미니게임 수수료 다시 제거해줘" · 서버 `20261022142000_duel_fee_off.sql` 이 `duel_fee` 를 0 으로).
///
/// 서버 응답엔 상금 키가 없어 "이기면 +N" 과 결과 카드의 +N 은 **클라가 센다**(`DuelFee`). 이 파일은 사용자가 읽는 글자를 잰다 —
/// 기대값은 **손으로 적은 표**다(3/5/10 → 순이익 +3/+5/+10 · 수수료 0). `DuelFee` 로 기대값을 다시 만들면 식이 틀려도 초록이다.
/// 화면 어디에도 "수수료" 글자가 남지 않는다 — `Sources/**` 의 Swift 를 주석을 걷어내고 잰다(맥 · 코어 · 폰 · 위젯 전부).
@Suite("판돈 수수료 없음 문구(폰 · v0.3.64)")
struct GamesDuelFeeCopyTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func code(_ relative: String) throws -> String {
        stripComments(try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
    }

    /// 손으로 적은 표(사용자 결정 2026-10-22 — 수수료 없음): 판돈 → 이기면 순이익(= 판돈).
    static let netTable: [(stake: Int, net: Int)] = [(3, 3), (5, 5), (10, 10)]
    /// 기준선: 수수료 10% 시절(v0.3.54~0.3.63)의 순이익. 새 표와 **판돈마다** 달라야 한다 — 같으면 이 파일은 수수료가 돌아와도 초록이다.
    static let oldFeeNet: [Int: Int] = [3: 2, 5: 4, 10: 8]

    @Test("오목·체스·테트리스 '이기면 +N' 은 순이익 = 판돈(3/5/10 → +3/+5/+10) — 줄 · 꼬리 · 칸 아래 줄 · 신청 시트 머리")
    func gainLinesShowNet() throws {
        for (stake, net) in Self.netTable {
            #expect(GomokuPhoneText.stakeLine(stake) == "\(stake) · 이기면 +\(net)")
            #expect(GomokuPhoneText.stakeGainSuffix(stake) == " · 이기면 +\(net)")
            #expect(GomokuPhoneText.stakeGain(stake) == "이기면 +\(net)")
            #expect(GomokuPhoneText.stakePromptChosen(stake) == "판돈 \(stake) · 이기면 +\(net)")
            #expect(ChessPhoneText.stakeLine(stake) == "\(stake) · 이기면 +\(net)")
            #expect(ChessPhoneText.stakeGainSuffix(stake) == " · 이기면 +\(net)")
            #expect(ChessPhoneText.stakeGain(stake) == "이기면 +\(net)")
            #expect(ChessPhoneText.stakePromptChosen(stake) == "판돈 \(stake) · 이기면 +\(net)")
            #expect(TetrisPhoneText.stakeLine(stake) == "\(stake) · 이기면 +\(net)")
            #expect(TetrisPhoneText.stakeGainSuffix(stake) == " · 이기면 +\(net)")
            #expect(TetrisPhoneText.stakeGain(stake) == "이기면 +\(net)")
            #expect(TetrisPhoneText.stakePromptChosen(stake) == "판돈 \(stake) · 이기면 +\(net)")
            // 기준선: 수수료 시절 문장(+2/+4/+8)과 달라야 한다.
            let old = try #require(Self.oldFeeNet[stake])
            #expect(old != net && GomokuPhoneText.stakeGain(stake) != "이기면 +\(old)")
        }
    }

    @Test("캡션·규칙 줄은 수수료를 말하지 않고(맥과 같은 문장), '판돈만큼 더' 와 수락 시점을 지킨다")
    func captionsNoLongerMentionFee() throws {
        // 맥 `GomokuText.stakeCaption` · `GomokuRuleExample` · `TetrisDuelText` 규칙 줄과 **글자까지 같은** 문장(0.3.64).
        let caption = "수락하는 순간 두 사람 모두 걸고, 이기면 판돈만큼 더 받아요"
        #expect(GomokuPhoneText.stakeCaption == caption)
        #expect(ChessPhoneText.stakeCaption == caption)
        let gomokuRule = try #require(GomokuPhoneRuleExample.ruleLines.last)
        #expect(gomokuRule == "수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고, 무승부면 건 판돈을 돌려받아요.")
        // 맥 V0327GomokuPanelRenderTests 가 맥 규칙 줄[6]에 "판돈만큼 더" 를 요구한다 — 폰도 같은 말을 쓴다.
        #expect(GomokuPhoneRuleExample.ruleLines[6].contains("판돈만큼 더"))
        let chessStake = try #require(ChessPhoneRuleLine.all().first { $0.title == "판돈" })
        #expect(chessStake.detail.hasPrefix(caption + ". "), "체스 규칙 시트의 판돈 줄이 캡션을 그대로 쓰지 않는다: \(chessStake.detail)")
        let tetrisStake = try #require(TetrisPhoneText.rules.first { $0.title == "판돈" })
        #expect(tetrisStake.detail == "수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고, "
                + "무승부면 돌려받아요. 30초 안에 둘 다 들어오지 않아도 돌려받아요.")
        for line in [GomokuPhoneText.stakeCaption, gomokuRule, chessStake.detail, tetrisStake.detail] {
            #expect(!line.contains("수수료") && !line.contains("%"), "판돈 문장이 아직 수수료를 말한다: \(line)")
            #expect(line.contains("수락"), "루비가 빠지는 순간(수락)을 말하지 않는다: \(line)")
            for word in ["도박", "베팅"] { #expect(!line.contains(word)) }
        }
    }

    /// 사용자 결정 2026-10-22: 앱 화면 어디에도 "수수료" 글자가 남지 않는다. 화면 글자는 전부 Swift 문자열이므로
    /// `Sources/**` 의 Swift 를 **주석을 걷어내고** 잰다(설명 주석의 '수수료' 는 역사라 남긴다 — 걷지 않으면 설명을 지워야만 초록이다).
    @Test("소스 계약: Sources/** Swift(맥 · 코어 · 폰 · 위젯, 주석 걷음)에 '수수료' 글자가 한 번도 없다")
    func noFeeWordAnywhereOnScreen() throws {
        let sources = Self.root.appendingPathComponent("Sources", isDirectory: true)
        let modules = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { !$0.hasPrefix(".") }
        #expect(Set(["check", "CheckCore", "CheckMobileKit", "CheckMobileShared"]).isSubset(of: Set(modules)), "모듈 목록: \(modules)")
        var scanned: [String: Int] = [:]
        var offenders: [String] = []
        for module in modules {
            guard let walker = FileManager.default.enumerator(at: sources.appendingPathComponent(module, isDirectory: true),
                                                              includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walker where file.pathExtension == "swift" {
                scanned[module, default: 0] += 1
                if stripComments(try String(contentsOf: file, encoding: .utf8)).contains("수수료") {
                    offenders.append("\(module)/\(file.lastPathComponent)")
                }
            }
        }
        // 빈 검사 방지: 뿌리를 잘못 잡으면 파일 0 개로 초록이다.
        #expect((scanned["check"] ?? 0) > 50 && (scanned["CheckCore"] ?? 0) > 50 && (scanned["CheckMobileKit"] ?? 0) > 100,
                "검사한 Swift 파일 수가 너무 적다: \(scanned)")
        #expect(offenders.isEmpty, "주석 밖 '수수료' 가 남은 파일: \(offenders)")
        // 기준선: 걷어내기가 주석 안 '수수료' 는 지우고 문자열 안 '수수료' 는 남긴다(둘이 같게 나오면 이 검사는 영원히 초록이다).
        #expect(!stripComments("let a = 1 // 수수료 10%").contains("수수료"))
        #expect(stripComments(#"let a = "(수수료 0% 빼고)""#).contains("수수료"))
    }

    /// 번들 리소스도 앱의 일부다 — `Sources/**` 의 JSON(데모 픽스처)은 `check_CheckMobileKit.bundle` 에 **통째로** 실린다.
    /// 화면에 나가는 값과 설명(`__note`)을 가르지 않고 전부 잰다(2026-10-22 검증: 빌드한 앱을 바이트로 세니 Swift 는 0 인데
    /// 테트리스 이긴 장면 픽스처의 `__note` 에 1건이 남아 있었다). 글자를 `\uXXXX` 로 적어도 빠지지 않게 디코드한 값도 본다.
    @Test("소스 계약: Sources/** JSON(데모 픽스처 — 설명 __note 포함)에 '수수료' 글자가 한 번도 없다")
    func noFeeWordInBundledJSON() throws {
        func strings(in object: Any) -> [String] {
            switch object {
            case let text as String: [text]
            case let array as [Any]: array.flatMap(strings(in:))
            case let dictionary as [String: Any]: dictionary.flatMap { [$0.key] + strings(in: $0.value) }
            default: []
            }
        }
        let sources = Self.root.appendingPathComponent("Sources", isDirectory: true)
        let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var scanned = 0
        var offenders: [String] = []
        for case let file as URL in walker where file.pathExtension == "json" {
            scanned += 1
            let data = try Data(contentsOf: file)
            let raw = String(decoding: data, as: UTF8.self)
            let decoded = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])).map(strings(in:)) ?? []
            if raw.contains("수수료") || decoded.contains(where: { $0.contains("수수료") }) {
                offenders.append(file.path.replacingOccurrences(of: sources.path + "/", with: ""))
            }
        }
        // 빈 검사 방지: 뿌리를 잘못 잡으면 파일 0 개로 초록이다(2026-10-22 기준 173개).
        #expect(scanned > 100, "검사한 JSON 파일 수가 너무 적다: \(scanned)")
        #expect(offenders.isEmpty, "'수수료' 가 남은 JSON: \(offenders)")
        // 기준선: 이스케이프로 적힌 글자도 디코드 쪽에서 잡힌다(원문만 보면 놓친다).
        let escapes = "수수료".unicodeScalars.map { String(format: "\\u%04x", $0.value) }.joined()
        let escaped = Data(("{\"__note\":[\"" + escapes + " 0\"]}").utf8)
        let escapedObject = try JSONSerialization.jsonObject(with: escaped)
        #expect(!String(decoding: escaped, as: UTF8.self).contains("수수료") && strings(in: escapedObject).contains { $0.contains("수수료") })
    }

    @Test("체스 결과 폴백(서버 값이 없을 때): 이기면 +판돈 · 지면 −판돈 · 무승부 ±0 + 환불 줄 · 서버 값이 있으면 그 값")
    func chessResultFallback() throws {
        for (stake, net) in Self.netTable {
            let won = try #require(Self.chrome(Self.chessMatch(stake: stake, outcome: .won)).result)
            #expect(won.rubyDelta == net && won.rubyDeltaText == "+\(net)", "판돈 \(stake) 승리: \(won.rubyDeltaText)")
            let lost = try #require(Self.chrome(Self.chessMatch(stake: stake, outcome: .lost)).result)
            #expect(lost.rubyDelta == -stake, "패배는 건 판돈만 잃는다")
            let draw = try #require(Self.chrome(Self.chessMatch(stake: stake, outcome: .draw)).result)
            #expect(draw.rubyDelta == 0 && draw.rubyNote == ChessPhoneText.drawRefund(stake: stake), "무승부는 건 판돈을 그대로 돌려받는다")
        }
        // 서버 값(폴백 +10 과 다른 7)이 있으면 그것이 답이다 — 같은 값을 주면 다시 셌는지 가를 수 없다.
        let given = try #require(Self.chrome(Self.chessMatch(stake: 10, outcome: .won, rubyDelta: 7)).result)
        #expect(given.rubyDelta == 7, "서버(코어 스토어)가 준 값을 클라가 다시 셌다")
    }

    @Test("소스: 오목 판돈 시트 칸 아래 줄과 오목 대국 결과 폴백(iOS 전용 뷰)이 `DuelFee` 식을 거친다 — 숫자를 다시 적지 않는다")
    func iosOnlyViewsUseTheFee() throws {
        let sheets = try Self.code("Sources/CheckMobileKit/Games/GamesGomokuSheets.swift")
        #expect(sheets.contains("GomokuPhoneText.stakeGain(stake.rawValue)"), "판돈 칸 아래 줄이 공용 문구(순이익)를 안 쓴다")
        #expect(!sheets.contains(#"Text("이기면 +\(stake.rawValue)")"#), "판돈 칸 아래 줄이 다시 +판돈을 박았다")
        let match = try Self.code("Sources/CheckMobileKit/Games/GamesGomokuMatch.swift")
        // 수수료가 0 이어도 식은 한 곳(`DuelFee`)에 남긴다 — 다음에 수수료가 생기는 날 화면마다 따로 고치지 않게(`DuelFee.swift` 머리말).
        #expect(match.contains("case .won?: return DuelFee.winnerNet(stake: match.stake)"), "오목 결과 폴백이 `DuelFee` 식을 안 거친다")
        #expect(!match.contains("case .won?: return match.stake"), "오목 결과 폴백이 숫자를 다시 적었다")
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
