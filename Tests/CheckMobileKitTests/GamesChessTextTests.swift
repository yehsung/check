import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 1:1 체스 **폰 문구**의 못(`Sources/CheckMobileKit/Games/GamesChessText.swift` · `GamesChessSheets.swift`).
//
// ── 왜 이 파일이 있는가 ──
// 체스에서 돈이 갈리는 자리는 판이 아니라 **문구**다. 서버는 이미 맞게 정산하는데(운영 e2e 13판 · 서버 결함 0)
// 화면이 그 사실을 다르게 말하면 사용자는 돌려받은 루비를 잃은 것으로 읽는다. 그 자리가 넷이고 전부 여기서 잰다:
//   ① FIDE 6.9 — `timeout`(깃발 → 패)과 `timeout_insufficient`(깃발 → **무승부**)가 **다른 문장**인가.
//   ② 판돈 — "신청하면 빠진다" 고 말하지 않는가(빠지는 순간은 **수락**이고 60초 만료는 0원도 안 움직인다).
//   ③ 한 사람 한 판 — 막힌 상태를 **양방향** 모두 말하는가(한 방향만 막으면 체스 판돈을 시간패로 잃는다).
//   ④ 로봇 판 — 입구가 **로그인을 보지 않는가**(`ChessStoreAI` 는 서버를 한 번도 안 탄다).
//
// ── 재는 법(저장소 메모 '테스트가 모양을 재고 결과를 안 잰다') ──
// 단언은 **부르는 자리의 결과**를 잰다. 조각 이름이 있는지가 아니라 그 조각이 **무슨 글자를 내는지**를 보고,
// 기본값도 값으로 잰다(기본 인자로 들어오는 시계·만료 숫자가 특히 그렇다 — 상수를 베낀 채 초록이 되는 자리다).
// 소스 계약은 **주석을 걷어내고** 잰다(`stripComments`) — 안 걷으면 이 머리말에 `cancelPromotion` 이라고 적어 둔
// 것만으로 초록이 되고, 설명을 지워야 빨개지는 거꾸로 된 테스트가 된다.
@Suite("체스 폰 문구·시트 계약")
struct GamesChessTextTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private static let textPath = "Sources/CheckMobileKit/Games/GamesChessText.swift"
    private static let sheetsPath = "Sources/CheckMobileKit/Games/GamesChessSheets.swift"

    /// 결과 문구가 지나는 네 가지 '내 기준' 축(끝난 판에 outcome 이 없는 응답도 있다 — nil 도 값이다).
    static let outcomes: [ChessMatchOutcome?] = [.won, .lost, .draw, nil]

    // MARK: - 1. ★ 끝난 사유 전수 (FIDE 6.9)

    @Test("사유 열 갈래가 전부 말을 한다 · timeout 과 timeout_insufficient 는 다른 문장이고 뒤가 무승부다")
    func everyEndReasonSpeaksAndTheFlagSplitsIntoTwo() {
        // ★ 열거값이 늘면 **여기서 빨개진다**. 세 가지가 함께 지킨다:
        //   (a) 이 숫자 — 사유를 더하면 틀린다(문구를 더하고 이 숫자를 고치라는 신호).
        //   (b) 아래 전수 순회 — 새 사유의 문구가 빈칸이면 빨개진다.
        //   (c) 문구 함수의 `switch` 에 `default:` 가 없다(§5 소스 계약) — 컴파일이 먼저 막는다.
        #expect(ChessEndReason.allCases.count == 10,
                "서버 사유값이 늘었다 — `ChessPhoneText.endReason`·`robotEndReason`·`watchEndReason` 셋에 문구를 더하고 이 숫자를 고쳐라")

        for reason in ChessEndReason.allCases {
            for outcome in Self.outcomes {
                let mine = ChessPhoneText.endReason(reason, outcome: outcome)
                #expect(!mine.isEmpty, "내 기준 문구가 빈칸이다: \(reason.rawValue) / \(String(describing: outcome))")
                let robot = ChessPhoneText.robotEndReason(reason, outcome: outcome)
                #expect(!robot.isEmpty, "로봇 판 문구가 빈칸이다: \(reason.rawValue) / \(String(describing: outcome))")
            }
            for winner in [ChessColor.white, .black, nil] {
                let watch = ChessPhoneText.watchEndReason(reason, winner: winner)
                #expect(!watch.isEmpty, "관전 문구가 빈칸이다: \(reason.rawValue) / \(String(describing: winner))")
            }
        }

        // ★ 돈이 가장 크게 갈리는 단언. 깃발 둘이 **다른 문장**이고, 무승부 쪽만 '무승부' 라고 말한다.
        for outcome in Self.outcomes {
            let loss = ChessPhoneText.endReason(.timeout, outcome: outcome)
            let draw = ChessPhoneText.endReason(.timeoutInsufficient, outcome: outcome)
            #expect(loss != draw, "깃발 둘이 같은 문장이다(\(String(describing: outcome))): \(loss)")
            #expect(draw.contains("무승부"), "FIDE 6.9 문구가 무승부를 말하지 않는다: \(draw)")
            #expect(!loss.contains("무승부"), "시간패 문구가 무승부를 말한다 — 이긴 사람이 돌려받았다고 읽는다: \(loss)")
        }
        // 로봇 판·관전도 같은 갈림을 가진다(세 표 중 하나만 고치고 끝나는 길을 막는다).
        #expect(ChessPhoneText.robotEndReason(.timeout, outcome: .lost)
                != ChessPhoneText.robotEndReason(.timeoutInsufficient, outcome: .draw))
        #expect(ChessPhoneText.robotEndReason(.timeoutInsufficient, outcome: .draw).contains("무승부"))
        #expect(ChessPhoneText.watchEndReason(.timeout, winner: .white)
                != ChessPhoneText.watchEndReason(.timeoutInsufficient, winner: nil))
        #expect(ChessPhoneText.watchEndReason(.timeoutInsufficient, winner: nil).contains("무승부"))
    }

    @Test("무승부 사유 여섯은 전부 '무승부'라 말하고, 승패 사유 넷은 한 번도 그 말을 쓰지 않는다")
    func drawReasonsSayDrawAndWinLossReasonsNeverDo() {
        // iff 로 잰다. 한쪽만 재면 "전부 무승부라 말하기"(= 이긴 판도 무승부로 보이기)로도 초록이 된다.
        for reason in ChessEndReason.allCases {
            for outcome in Self.outcomes {
                let mine = ChessPhoneText.endReason(reason, outcome: outcome)
                #expect(mine.contains("무승부") == reason.isDraw,
                        "사유 \(reason.rawValue)(무승부=\(reason.isDraw)) 문구가 어긋난다: \(mine)")
            }
            for winner in [ChessColor.white, .black, nil] {
                let watch = ChessPhoneText.watchEndReason(reason, winner: winner)
                #expect(watch.contains("무승부") == reason.isDraw,
                        "관전 사유 \(reason.rawValue) 문구가 어긋난다: \(watch)")
            }
        }
        // 대조: 코어의 무승부 집합이 여섯이다(서버 CHECK 와 같은 수). 이 수가 틀어지면 위 iff 가 다른 것을 재고 있다.
        #expect(ChessEndReason.allCases.filter(\.isDraw).count == 6)
    }

    @Test("모르는 사유가 와도 빈칸이 되지 않는다(서버가 어휘를 넓히는 날)")
    func unknownReasonStillSpeaks() {
        // 코어 규약: 모르는 사유는 `ChessEndReason(rawValue:)` 가 nil 로 접는다. 그때 빈 문자열을 그리면
        // 결과 카드에 이유 줄이 사라져 "왜 끝났는지 아무 데도 없는" 화면이 된다.
        #expect(ChessEndReason(rawValue: "cosmic_ray") == nil, "전제: 모르는 사유는 nil 로 접힌다")
        for outcome in Self.outcomes {
            #expect(!ChessPhoneText.endReason(nil, outcome: outcome).isEmpty,
                    "모르는 사유가 빈칸이다(\(String(describing: outcome)))")
            #expect(!ChessPhoneText.robotEndReason(nil, outcome: outcome).isEmpty)
        }
        for winner in [ChessColor.white, .black, nil] {
            #expect(!ChessPhoneText.watchEndReason(nil, winner: winner).isEmpty)
        }
        // 무승부로 끝난 판은 **무승부라고만** 말한다(사유를 지어내지 않는다).
        #expect(ChessPhoneText.unknownEndReason(.draw) == "무승부로 끝났어요")
        #expect(ChessPhoneText.unknownEndReason(.won) == "판이 끝났어요")
        #expect(ChessPhoneText.unknownEndReason(nil) == "판이 끝났어요")
        #expect(ChessPhoneText.unknownEndReason(.draw) != ChessPhoneText.unknownEndReason(.won),
                "기준선이 같으면 이 테스트는 영원히 초록이다")
    }

    @Test("결과 머리글 넷과 루비 줄 — 무승부는 돌려받는다고 말한다")
    func outcomeTitleAndRubyCaption() {
        #expect(ChessPhoneText.outcomeTitle(.won) == "이겼어요")
        #expect(ChessPhoneText.outcomeTitle(.lost) == "졌어요")
        #expect(ChessPhoneText.outcomeTitle(.draw) == "무승부예요")
        #expect(ChessPhoneText.outcomeTitle(nil) == "대국이 끝났어요")
        // ±0 만 띄우면 잃은 것처럼 읽힌다 — 무승부에는 꼬리 한 줄이 붙는다.
        #expect(ChessPhoneText.rubyResultCaption(.draw) == "건 루비는 돌려받아요")
        #expect(ChessPhoneText.rubyResultCaption(.won) == nil)
        #expect(ChessPhoneText.rubyResultCaption(.lost) == nil)
        #expect(ChessPhoneText.rubyResultCaption(nil) == nil)
        #expect(ChessPhoneText.rubyDelta(10) == "+10")
        #expect(ChessPhoneText.rubyDelta(-10) == "−10", "음수 기호는 U+2212")
        #expect(ChessPhoneText.rubyDelta(0) == "±0")
    }

    // MARK: - 2. ★ 판돈 — 빠지는 순간은 '수락' 이다

    @Test("판돈 문구는 '신청 시점에 빠진다'고 말하지 않는다")
    func stakeTextNeverClaimsRubyLeavesOnChallenge() {
        // 참인 사실 둘을 먼저 못 박는다(없는 말을 금지하는 단언만 두면, 문장을 통째로 지워도 초록이다).
        #expect(ChessPhoneText.stakeCaption == "수락하는 순간 두 사람 모두 걸고, 이기면 판돈만큼 더 받아요")
        #expect(ChessPhoneText.stakeCaption.contains("수락"), "루비가 빠지는 순간을 말하지 않는다")
        #expect(ChessPhoneText.stakeNotHeldYet(ttlSeconds: 60)
                == "신청만 해서는 루비가 빠지지 않아요 · 60초 안에 응답이 없으면 신청이 사라져요")
        // 기본 인자도 값으로 잰다 — 서버가 말해 주기 전의 폴백이 60 이다.
        #expect(ChessPhoneText.stakeNotHeldYet() == ChessPhoneText.stakeNotHeldYet(ttlSeconds: 60))
        #expect(ChessPhoneText.inviteTtlSecondsFallback == 60)
        // 숫자가 **박혀 있지 않다**: 서버가 다른 만료를 말하면 문장이 따라 바뀐다(기준선이 달라야 한다).
        #expect(ChessPhoneText.stakeNotHeldYet(ttlSeconds: 30).contains("30초"))
        #expect(ChessPhoneText.stakeNotHeldYet(ttlSeconds: 30) != ChessPhoneText.stakeNotHeldYet(ttlSeconds: 60))

        // 금지된 주장: 신청·도전 시점에 루비가 움직인다는 말. 판돈을 말하는 모든 문구를 쓸어 본다.
        let ttl = ChessPhoneText.inviteTtlSecondsFallback
        let moneyLines: [String] = [
            ChessPhoneText.stakeCaption,
            ChessPhoneText.stakeNotHeldYet(),
            ChessPhoneText.stakeRefundOnDraw,
            ChessPhoneText.stakeTitle,
            ChessPhoneText.stakeLine(5),
            ChessPhoneText.stakeGainSuffix(5),
            ChessPhoneText.stakePromptCaption,
            ChessPhoneText.stakePromptChosen(5),
            ChessPhoneText.challengeWithStake(5),
            ChessPhoneText.stakeShortfall
        ] + ChessPhoneRuleLine.all(inviteTtlSeconds: ttl).map(\.detail)
        let forbidden = ["신청하면 빠", "신청하는 순간", "신청할 때 빠", "신청과 동시에", "도전하면 빠", "신청하면 루비가 빠"]
        for line in moneyLines {
            for phrase in forbidden {
                #expect(!line.contains(phrase), "★ 판돈이 신청 시점에 빠진다고 말한다(거짓): \(line)")
            }
        }
        #expect(ChessPhoneText.stakes == [3, 5, 10], "판돈 셋은 3·5·10 이다")
    }

    // MARK: - 3. ★ 한 사람 한 판 — 양방향

    @Test("막힌 입구는 양방향 모두 말한다 — '오목을 두는 중' 과 '체스를 두는 중'")
    func oneMatchPerPersonIsSaidInBothDirections() {
        #expect(ChessPhoneText.BusyGame.allCases.count == 2, "두 게임뿐이다 — 늘면 문구를 더해라")
        #expect(ChessPhoneText.busyTitle(.gomoku) == "오목을 두는 중이에요")
        #expect(ChessPhoneText.busyTitle(.chess) == "체스를 두는 중이에요")
        // 조사가 갈린다(오목**을** · 체스**를**) — 한 꼴로 조립하면 한쪽이 틀린 한국어가 된다.
        #expect(ChessPhoneText.objectParticle("오목") == "을")
        #expect(ChessPhoneText.objectParticle("체스") == "를")

        for game in ChessPhoneText.BusyGame.allCases {
            let title = ChessPhoneText.busyTitle(game)
            #expect(title.contains(game.gameName), "막힌 사유가 두는 게임을 말하지 않는다: \(title)")
            #expect(!title.contains(game.otherGame.gameName), "막힌 사유가 반대쪽 게임 이름을 말한다: \(title)")
            // 아래 한 줄은 **언제 풀리는지** 말한다. 두 게임 이름이 다 들어간다(무엇이 끝나면 무엇을 할 수 있는지).
            let hint = ChessPhoneText.busyHint(game)
            #expect(hint.contains(game.gameName) && hint.contains(game.otherGame.gameName), "풀리는 조건이 불분명하다: \(hint)")
            // ★ 입구 게이트는 **그 사유를 그대로** 낸다(뷰가 제 문구를 또 만들지 않는다).
            #expect(ChessPhoneText.entryBlock(playing: game) == title)
        }
        // 두는 판이 없으면 막지 않는다. 그리고 두 방향의 문장이 **서로 다르다**(한 벌로 두면 한 방향만 막은 것과 같다).
        #expect(ChessPhoneText.entryBlock(playing: nil) == nil)
        #expect(ChessPhoneText.busyTitle(.gomoku) != ChessPhoneText.busyTitle(.chess))
        #expect(ChessPhoneText.busyHint(.gomoku) != ChessPhoneText.busyHint(.chess))
    }

    // MARK: - 4. ★ 로봇 판은 로그인을 안 본다

    @Test("로봇과 두기 입구는 로그인으로 막히지 않는다(두는 판만 막는다)")
    func robotEntryIgnoresSignIn() {
        // ★ 비로그인에서 nil 이 이 테스트의 알맹이다 — `ChessStoreAI` 는 서버를 한 번도 안 탄다.
        #expect(ChessPhoneText.robotEntryBlock(signedIn: false, playing: nil) == nil,
                "★ 로그인 안 한 사람의 로봇 판 입구가 막혔다 — 비로그인 사용자도 둘 수 있어야 한다")
        #expect(ChessPhoneText.robotEntryBlock(signedIn: true, playing: nil) == nil)
        // 로그인 여부가 **답을 바꾸지 않는다**(두 값에서 같은 결과).
        for game in ChessPhoneText.BusyGame.allCases {
            let signedOut = ChessPhoneText.robotEntryBlock(signedIn: false, playing: game)
            let signedIn = ChessPhoneText.robotEntryBlock(signedIn: true, playing: game)
            #expect(signedOut == signedIn, "로그인 여부가 로봇 입구의 답을 바꿨다: \(game.gameName)")
            #expect(signedOut == ChessPhoneText.busyTitle(game), "막는 사유는 두고 있는 판이다")
        }
        // 입구 문구가 로그인을 요구하지 않는다. 로그인을 입에 올리는 줄은 **"안 해도 된다"** 는 그 한 줄뿐이다.
        let robotLines = [
            ChessPhoneText.robotButton, ChessPhoneText.robotButtonHelp, ChessPhoneText.robotPromptTitle,
            ChessPhoneText.robotPromptCaption, ChessPhoneText.robotPlayWhite, ChessPhoneText.robotPlayBlack,
            ChessPhoneText.robotNoRecord, ChessPhoneText.robotStakeChip, ChessPhoneText.robotClockPauses
        ]
        for line in robotLines {
            #expect(!line.contains("로그인"), "로봇 입구 문구가 로그인을 말한다: \(line)")
        }
        #expect(ChessPhoneText.robotNoSignIn == "로그인하지 않아도 둘 수 있어요")
        // 판돈·순위가 없다는 사실(사용자 결정 둘)을 한 줄이 다 말한다.
        #expect(ChessPhoneText.robotNoRecord.contains("루비") && ChessPhoneText.robotNoRecord.contains("순위"))
        // 1:1 과 로봇의 시계 안내는 **정반대 사실**이다 — 한 줄을 돌려 쓰면 거짓말이 된다.
        #expect(ChessPhoneText.clockRunsInBackground != ChessPhoneText.robotClockPauses)
        #expect(ChessPhoneText.clockRunsInBackground.contains("흘러요"))
        #expect(ChessPhoneText.robotClockPauses.contains("멈춰요"))
    }

    // MARK: - 5. 시계·머리글은 서버 값에서 만든다

    @Test("머리글 시계는 서버 값에서 조립한다(상수를 베끼지 않는다)")
    func clockPhraseComesFromServerValues() {
        #expect(ChessPhoneText.subtitle(initialMs: 600_000, incrementMs: 3_000) == "FIDE 규칙 · 백 선공 · 10분 + 한 수 3초")
        // 기본 인자도 값으로 잰다 — 코어 `ChessClock` 한 곳에서 와야 한다(서버 `chess_initial_ms()` 와 같은 숫자).
        #expect(ChessPhoneText.subtitle()
                == ChessPhoneText.subtitle(initialMs: ChessClock.initialMs,
                                           incrementMs: Int(ChessClock.incrementSeconds * 1000)))
        #expect(ChessClock.initialMs == 600_000, "시계가 바뀌었다 — 서버 `chess_initial_ms()` 와 맞춰라")
        #expect(ChessPhoneText.subtitle() == "FIDE 규칙 · 백 선공 · 10분 + 한 수 3초")
        // 기준선이 달라야 한다: 다른 서버 값을 주면 문장이 따라 바뀐다(5분 시절 값으로 재 본다).
        #expect(ChessPhoneText.clockPhrase(initialMs: 300_000, incrementMs: 5_000) == "5분 + 한 수 5초")
        #expect(ChessPhoneText.clockPhrase(initialMs: 300_000, incrementMs: 5_000) != ChessPhoneText.clockPhrase())
    }

    @Test("시계 글자·보이스오버·상태줄")
    func clockAndStatusLine() {
        #expect(ChessPhoneText.clock(125) == "2:05")
        #expect(ChessPhoneText.clock(9.44) == "9.4", "마지막 10초는 소수 한 자리")
        #expect(ChessPhoneText.clock(-3) == "0.0", "음수는 0 으로")
        #expect(ChessPhoneText.clockAccessibility(125) == "남은 시간 2분 5초")
        #expect(ChessPhoneText.clockAccessibility(9) == "남은 시간 9초")
        // 상태줄 네 조합. `isInCheck` 는 **차례인 쪽**이 체크인가이므로 방향이 뒤집히면 "상대가 체크" 와 "체크!" 가 바뀐다.
        #expect(ChessPhoneText.statusLine(isMyTurn: true, isInCheck: true) == "체크! 왕을 피하세요")
        #expect(ChessPhoneText.statusLine(isMyTurn: true, isInCheck: false) == "내 차례예요")
        #expect(ChessPhoneText.statusLine(isMyTurn: false, isInCheck: true) == "상대가 체크예요")
        #expect(ChessPhoneText.statusLine(isMyTurn: false, isInCheck: false) == "상대 차례예요")
        #expect(Set([
            ChessPhoneText.statusLine(isMyTurn: true, isInCheck: true),
            ChessPhoneText.statusLine(isMyTurn: true, isInCheck: false),
            ChessPhoneText.statusLine(isMyTurn: false, isInCheck: true),
            ChessPhoneText.statusLine(isMyTurn: false, isInCheck: false)
        ]).count == 4, "네 조합이 네 문장이어야 한다")
        #expect(ChessPhoneText.boardAccessibility(ply: 12, turn: .black, inCheck: true) == "체스판, 12수 진행, 흑 차례, 체크")
    }

    // MARK: - 6. 승격은 넷만 묻는다

    @Test("승격은 네 말(퀸·룩·비숍·나이트)을 코어 순서 그대로 묻는다")
    func promotionAsksExactlyFourPiecesInCoreOrder() {
        #expect(ChessPieceKind.promotionChoices == [.queen, .rook, .bishop, .knight], "전제: 코어가 넷을 이 순서로 준다")
        #expect(ChessPhoneText.promotionChoiceNames == ["퀸", "룩", "비숍", "나이트"])
        // 여섯 이름이 다 있고 **서로 다르다**(기보·보이스오버가 킹·폰도 부른다).
        let names = ChessPieceKind.allCases.map(ChessPhoneText.pieceName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == ChessPieceKind.allCases.count, "말 이름이 겹친다: \(names)")
        // 2단임을 말하는 두 줄(왜 지금 묻는지 · 닫으면 어떻게 되는지).
        #expect(ChessPhoneText.promotionTitle == "승격할 말을 고르세요")
        #expect(ChessPhoneText.promotionCaption.contains("끝 줄"), "왜 물었는지 말하지 않는다")
        #expect(ChessPhoneText.promotionCancel == "다른 수 두기")
    }

    // MARK: - 7. 무승부 제안 · 응답

    @Test("무승부 시트는 제안과 응답을 가른다(거절은 응답이고 그만두기는 아니다)")
    func drawSheetSplitsOfferFromRespond() {
        #expect(ChessPhoneText.DrawSheetMode.allCases.count == 2)
        for mode in ChessPhoneText.DrawSheetMode.allCases {
            #expect(!ChessPhoneText.drawSheetTitle(mode).isEmpty)
            #expect(!ChessPhoneText.drawSheetMessage(mode).isEmpty)
            #expect(!ChessPhoneText.drawSheetPrimary(mode).isEmpty)
            #expect(!ChessPhoneText.drawSheetSecondary(mode).isEmpty)
            // 본문은 **루비가 어떻게 되는지**를 말한다(무승부는 돌려받는다 — 승패가 아니다).
            #expect(ChessPhoneText.drawSheetMessage(mode).contains("무승부"))
            #expect(ChessPhoneText.drawSheetMessage(mode).contains(ChessPhoneText.stakeRefundOnDraw))
        }
        // 네 갈래가 서로 다른 글자다 — 한 벌로 두면 제안 화면에 [거절] 이 뜨거나 응답 화면이 그만두기만 준다.
        #expect(ChessPhoneText.drawSheetTitle(.offer) != ChessPhoneText.drawSheetTitle(.respond))
        #expect(ChessPhoneText.drawSheetPrimary(.offer) != ChessPhoneText.drawSheetPrimary(.respond))
        #expect(ChessPhoneText.drawSheetSecondary(.offer) == ChessPhoneText.keepPlaying)
        #expect(ChessPhoneText.drawSheetSecondary(.respond) == ChessPhoneText.declineDraw)
        #expect(ChessPhoneText.drawSheetSecondary(.offer) != ChessPhoneText.drawSheetSecondary(.respond))
        // 받은 제안은 **누가** 했는지 말한다. 별명을 모르면 지어내지 않고 "상대가" 로 부른다.
        #expect(ChessPhoneText.drawSheetTitle(.respond, name: "민트별") == "민트별님이 무승부를 제안했어요")
        #expect(ChessPhoneText.drawSheetTitle(.respond, name: nil) == "상대가 무승부를 제안했어요")
        #expect(ChessPhoneText.drawSheetTitle(.respond, name: "") == "상대가 무승부를 제안했어요", "빈 별명도 폴백")
        #expect(ChessPhoneText.drawOfferVanishesOnMove.contains("한 수"))
    }

    // MARK: - 8. 순위 행은 승점만 띄우지 않는다

    @Test("순위 행은 순위·이름·승점·승·패·무를 다 말한다(사용자 지시)")
    func rankRowSaysRankNameAndFullRecord() {
        #expect(ChessPhoneText.record(wins: 6, losses: 2, draws: 1) == "6승 2패 1무")
        #expect(ChessPhoneText.record(wins: 0, losses: 0, draws: 0) == "0승 0패 0무", "0 도 지우지 않는다")
        #expect(ChessPhoneText.points(4) == "승점 +4")
        #expect(ChessPhoneText.signedPoints(-2) == "−2")
        #expect(ChessPhoneText.signedPoints(0) == "0")
        #expect(ChessPhoneText.points(4) != ChessPhoneText.record(wins: 6, losses: 2, draws: 1),
                "승점 문장과 전적 문장은 다른 문장이다")

        let entry = ChessRankEntry(
            id: "p-mint", rank: 3,
            user: ChessUser(id: "p-mint", displayName: "민트별", avatarURL: nil, characterID: nil,
                            isWorking: false, isCapable: true, inMatch: false, center: "서울"),
            wins: 6, losses: 2, draws: 1, points: 4)
        let label = ChessPhoneText.rankRowAccessibility(entry, isMe: false)
        // 눈이 아닌 사람에게 '승점만' 상태가 되지 않게 — 네 조각이 다 들어 있다.
        #expect(label.contains("3위"), "순위가 없다: \(label)")
        #expect(label.contains("민트별"), "이름이 없다: \(label)")
        #expect(label.contains(ChessPhoneText.points(4)), "승점이 없다: \(label)")
        #expect(label.contains(ChessPhoneText.record(wins: 6, losses: 2, draws: 1)), "★ 전적이 없다: \(label)")
        #expect(label.contains("서울센터"))
        #expect(ChessPhoneText.rankRowAccessibility(entry, isMe: true).contains(ChessPhoneText.me))

        // 목록 밖 내 순위 줄. 0판이면 순위가 없지만(서버가 null) 전적은 남는다.
        #expect(ChessPhoneText.myRankLine(ChessMyRank(rank: 12, wins: 6, losses: 2, draws: 1, points: 4))
                == "12위 · 승점 +4 · 6승 2패 1무")
        #expect(ChessPhoneText.myRankLine(ChessMyRank(rank: nil, wins: 0, losses: 0, draws: 0, points: 0))
                == "순위 밖 · 0승 0패 0무")
        #expect(ChessPhoneText.rankZeroGamesNote.contains("순위에 들어가지 않아요"))
        // 전적 컷은 **KST 달력 값**이다(기기 시간대로 조립하면 비KST 기기에서 하루 밀린다).
        let cut = ISO8601DateFormatter().date(from: "2026-09-30T15:00:00Z") // 10/1 00:00 KST
        #expect(cut.map(ChessPhoneText.rankSince) == "10월 1일부터")
        // 기준선이 달라야 한다 — 기기 시간대로 조립했다면 UTC 기준 9월 30일이 나온다.
        #expect(cut.map(ChessPhoneText.rankSince) != "9월 30일부터")
    }

    // MARK: - 9. 관전은 판만 (대화 없음 · 3분 꼬리)

    @Test("관전 문구는 대화가 없다고 말하고 3분 꼬리를 말한다")
    func watchTextSaysNoChatAndTheThreeMinuteTail() {
        #expect(ChessPhoneText.watchCaption.contains("대화는 없어요"), "없는 기능을 기다리게 둔다: \(ChessPhoneText.watchCaption)")
        #expect(ChessPhoneText.watchTailMinutes == 3)
        #expect(ChessPhoneText.watchTailCaption.contains("3분"))
        // 꼬리가 지난 판의 문구는 **코어와 같은 말**이다(같은 사실이 화면마다 다른 말을 하지 않게).
        #expect(ChessPhoneText.watchGone == ChessNoticeText.watchGone)
        #expect(ChessPhoneText.elapsedPhrase(35) == "35초째")
        #expect(ChessPhoneText.elapsedPhrase(95) == "1분 35초째")
        #expect(ChessPhoneText.elapsedPhrase(3_720) == "1시간 2분째")
    }

    // MARK: - 10. 상대 행은 어느 게임인지 지어내지 않는다

    @Test("상대 행의 '대국 중' 은 게임 이름을 지어내지 않는다(서버가 오목 판까지 하나로 접어 준다)")
    func opponentStatusDoesNotInventTheGame() {
        func user(_ id: String, name: String, working: Bool = false, capable: Bool = true, inMatch: Bool = false) -> ChessUser {
            ChessUser(id: id, displayName: name, avatarURL: nil, characterID: nil,
                      isWorking: working, isCapable: capable, inMatch: inMatch)
        }
        let busy = user("a", name: "민트별", inMatch: true)
        #expect(ChessPhoneText.status(for: busy) == "대국 중")
        for game in ChessPhoneText.BusyGame.allCases {
            #expect(!ChessPhoneText.status(for: busy).contains(game.gameName),
                    "상대가 어느 게임을 두는지 지어냈다 — 서버는 말해 주지 않는다")
        }
        // 서열: 대국 중 > 업데이트 필요 > 근무.
        #expect(ChessPhoneText.status(for: user("b", name: "옛버전", capable: false)) == "앱 업데이트가 필요해요")
        #expect(ChessPhoneText.status(for: user("c", name: "일하는중", working: true)) == "근무 중")
        #expect(ChessPhoneText.status(for: user("d", name: "쉬는중")) == "근무 안 함")
        // 부제는 누구와 두는지까지 말한다(로비의 대결 중 목록에서 찾는다). 못 찾으면 칩과 같은 말로 접는다.
        let live = ChessLiveMatch(id: "m", a: busy, b: user("e", name: "달토끼"), stake: .five, startedAt: Date())
        #expect(ChessPhoneText.opponentStatus(for: busy, liveMatches: [live]) == "대국 중 · 달토끼와")
        #expect(ChessPhoneText.opponentStatus(for: busy, liveMatches: []) == "대국 중")
        #expect(ChessPhoneText.withParticle("민트별") == "과")
    }

    // MARK: - 11. 규칙 시트 — 돈이 갈리는 셋을 다 말한다

    @Test("규칙 줄은 FIDE 6.9 예외 · 수락 시점 · 한 사람 한 판을 다 말한다")
    func ruleLinesCoverTheMoneyFacts() throws {
        let lines = ChessPhoneRuleLine.all()
        #expect(lines.count == 8)
        #expect(Set(lines.map(\.title)).count == lines.count, "규칙 제목이 겹친다(ForEach id 가 깨진다)")
        #expect(lines.allSatisfy { !$0.detail.isEmpty })

        let time = try #require(lines.first { $0.title == "시간" }, "시간 줄이 없다")
        #expect(time.detail.contains(ChessPhoneText.clockPhrase()), "시계 수치가 서버 값에서 오지 않는다: \(time.detail)")
        #expect(time.detail.contains("무승부"), "★ FIDE 6.9 예외가 규칙 시트에 없다: \(time.detail)")
        // 기준선이 달라야 한다 — 서버가 다른 시계를 말하면 이 줄이 따라 바뀐다.
        let fiveMinute = try #require(ChessPhoneRuleLine.all(initialMs: 300_000, incrementMs: 5_000)
            .first { $0.title == "시간" })
        #expect(fiveMinute.detail != time.detail)
        #expect(fiveMinute.detail.contains("5분 + 한 수 5초"))

        let stake = try #require(lines.first { $0.title == "판돈" }, "판돈 줄이 없다")
        #expect(stake.detail.contains("수락"), "루비가 빠지는 순간을 말하지 않는다: \(stake.detail)")
        #expect(stake.detail.contains("\(ChessPhoneText.inviteTtlSecondsFallback)초"), "만료를 말하지 않는다")
        #expect(ChessPhoneRuleLine.all(inviteTtlSeconds: 30).first { $0.title == "판돈" }?.detail.contains("30초") == true)

        let oneMatch = try #require(lines.first { $0.title == "한 사람 한 판" }, "한 사람 한 판 줄이 없다")
        for game in ChessPhoneText.BusyGame.allCases {
            #expect(oneMatch.detail.contains(game.gameName), "★ 양방향 중 한쪽이 빠졌다: \(oneMatch.detail)")
        }
        let promotion = try #require(lines.first { $0.title == "승격" })
        for name in ChessPhoneText.promotionChoiceNames {
            #expect(promotion.detail.contains(name), "승격 줄에 \(name) 이 없다")
        }
    }

    // MARK: - 12. 소스 계약(주석을 걷어내고 잰다)

    @Test("문구 세 표의 switch 에 default 가 없다 — 사유를 더하면 컴파일이 먼저 막는다")
    func reasonTablesHaveNoDefaultBranch() throws {
        let code = try Self.code(Self.textPath)
        for name in ["func endReason(", "func robotEndReason(", "func watchEndReason("] {
            let body = try #require(Self.block(after: name, in: code)?.body, "`\(name)` 본문을 못 찾았다")
            #expect(!body.contains("default:"),
                    "★ \(name) 에 default 가 있다 — 서버가 사유를 늘리는 날 새 사유가 조용히 다른 말을 한다")
            // 깃발 둘이 **각자 제 갈래**를 가진다(한 갈래에 묶으면 같은 문장이 나온다).
            #expect(body.contains("case .timeout:"), "\(name) 에 timeout 갈래가 없다")
            #expect(body.contains("case .timeoutInsufficient:"), "\(name) 에 timeout_insufficient 갈래가 없다")
        }
    }

    @Test("승격 시트는 코어가 준 넷을 그리고, 닫는 두 길이 모두 스토어의 승격 단계를 접는다")
    func promotionSheetUsesCoreChoicesAndCancelsOnBothExits() throws {
        let code = try Self.code(Self.sheetsPath)
        let sheet = try #require(Self.block(after: "struct GamesChessPromotionSheet: View", in: code)?.body,
                                 "승격 시트 타입을 못 찾았다")
        // 말 목록을 **직접 적지 않는다** — 코어 `prompt.choices` 가 권위다(순서가 판 그림과 같아야 한다).
        #expect(sheet.contains("ForEach(prompt.choices"), "승격 시트가 코어가 준 넷을 안 쓴다")
        #expect(!sheet.contains("[.queen"), "승격 시트가 말 목록을 직접 적었다")
        #expect(sheet.contains("store.choosePromotion("), "탭이 수를 보내지 않는다")
        // ★ 닫는 길이 둘(머리 ✕ · 아래 버튼)이고 **둘 다** 같은 함수를 지나며 그 함수가 스토어를 접는다.
        let cancel = try #require(Self.block(after: "private func cancel()", in: sheet), "`cancel()` 이 없다")
        #expect(cancel.body.contains("store.cancelPromotion()"),
                "★ 닫기가 스토어의 승격 단계를 접지 않는다 — 끌어 놓은 폰이 도착 칸에 뜬 채 굳는다")
        #expect(sheet.contains("onClose: { cancel() }"), "머리 ✕ 가 그 길을 안 지난다")
        #expect(sheet.contains("ChessPhoneText.promotionCancel"), "아래 버튼이 문구 표를 안 쓴다")
        // 쓸어내려 닫기는 막는다(그 길은 `cancel()` 을 지나지 않는다).
        #expect(sheet.contains(".interactiveDismissDisabled()"),
                "★ 쓸어내려 닫기가 열려 있다 — 그 길은 스토어를 접지 않는다")
    }

    @Test("무승부 시트의 [거절] 은 서버로 간다 — 그냥 닫으면 상대가 기다린 채 시계만 흐른다")
    func drawSheetSendsTheDecline() throws {
        let code = try Self.code(Self.sheetsPath)
        let sheet = try #require(Self.block(after: "struct GamesChessDrawSheet: View", in: code)?.body,
                                 "무승부 시트 타입을 못 찾았다")
        let primary = try #require(Self.block(after: "private func primaryAction()", in: sheet), "`primaryAction()` 이 없다")
        #expect(primary.body.contains("store.offerDraw()"), "제안 갈래가 제안을 안 보낸다")
        #expect(primary.body.contains("store.respondDraw(accept: true)"), "응답 갈래가 수락을 안 보낸다")
        let secondary = try #require(Self.block(after: "private func secondaryAction()", in: sheet), "`secondaryAction()` 이 없다")
        #expect(secondary.body.contains("store.respondDraw(accept: false)"),
                "★ [거절] 이 서버로 가지 않는다 — 상대는 응답을 기다린 채 시계를 쓴다")
        // 제안 갈래의 보조는 **아무것도 안 보낸다**(제안한 적이 없다) — 그 가름이 살아 있어야 한다.
        #expect(secondary.body.contains("guard mode == .respond"), "제안 갈래의 [계속 두기] 가 서버를 탄다")
    }

    @Test("시트 파일은 한국어 문구를 직접 적지 않는다 — 전부 문구 표에서 온다")
    func sheetsCarryNoKoreanLiterals() throws {
        // 왜: 폰 뷰는 맥 스위트가 못 본다. 뷰가 제 문구를 적으면 **어느 테스트도 그 글자를 볼 수 없고**,
        // 같은 사실이 화면마다 다른 말을 하는 길이 열린다(체스는 그 자리가 곧 돈이다).
        let literals = Self.stringLiterals(in: try Self.code(Self.sheetsPath))
        #expect(!literals.isEmpty, "전제: 문자열 리터럴을 못 읽었다(스캐너가 헛돈다)")
        for literal in literals where literal.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) {
            Issue.record("시트가 한국어 문구를 직접 적었다: \"\(literal)\" — `ChessPhoneText` 로 옮겨라")
        }
    }

    // MARK: - 도우미

    /// 주석을 걷어낸 소스(하우스 규칙 — `GamesGomokuRankingContractTests.code(_:)` 와 같은 길).
    static func code(_ relative: String) throws -> String {
        stripComments(try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
    }

    /// `needle` **뒤** 첫 `{` 부터 짝이 맞는 `}` **앞**까지.
    static func block(after needle: String, in code: String) -> (body: String, end: String.Index)? {
        guard let hit = code.range(of: needle) else { return nil }
        guard let open = code[hit.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = open
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 { return (String(code[code.index(after: open)..<i]), code.index(after: i)) }
            }
            i = code.index(after: i)
        }
        return nil
    }

    /// 한 줄 문자열 리터럴 전부(여러 줄 리터럴 `"""` 는 이 파일들에 없다 — 있으면 위 전제 단언이 어긋난다).
    static func stringLiterals(in code: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inString = false, escaped = false
        for c in code {
            if inString {
                if escaped { escaped = false; current.append(c); continue }
                if c == "\\" { escaped = true; current.append(c); continue }
                if c == "\"" { out.append(current); current = ""; inString = false; continue }
                current.append(c)
            } else if c == "\"" {
                inString = true
            }
        }
        return out
    }
}
