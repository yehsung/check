import CheckCore
import Foundation

/// 폰 아잉 뒤집기(1.0.17 · 대표 답 #d_DdwzmxPClGqk "다 넣기 (루비 걸기 포함)") 문구 표.
///
/// ── 어디까지가 이 표의 몫인가 ───────────────────────────────────────────────────────────────
/// **안내·결과 사유는 코어가 쥔다**(`ReversiNoticeText` — 신청·취소·수락·착수·기권 응답 · 패스 · 자동 착수 · 관전 · 배포 창).
/// 맥과 폰이 같은 서버 응답을 같은 말로 옮겨야 하므로 그 표를 **다시 쓰지 마라.** 게임 이름 글자도 그 표 한 곳이다(`gameName`).
/// 이 표는 **화면에 붙는 글자**(제목·탭·버튼·라벨·빈 상태·규칙)만 쥔다. 맥 `ReversiText`(Sources/check — 폰 빌드에 안 들어간다)는
/// 배치·낱말 참고로만 쓴다 — 맥 표를 코어로 옮기면 맥 시험이 흔들린다(조사 impl_notes).
///
/// ── 상표 ──
/// 게임 이름은 '아잉 뒤집기'뿐이다. '리버시'는 **규칙 설명**으로만 쓴다(맥 `ReversiText.subtitle` 과 같은 자리). 다른 상표 낱말은
/// 저장소 어디에도 쓰지 않는다(`V03xxReversiTrademarkTests` 가 저장소 전역을 훑는다).
///
/// 레인 규약: 키를 더할 때는 **자기 절 끝**에만 더한다(화면 갈래들이 같은 줄을 고치지 않게).
/// 이 파일에 `#if os(iOS)` 를 두지 마라 — 맥 스위트가 값으로 재는 자리라야 폰 화면의 글자가 검증된다.
package enum ReversiPhoneText {

    // MARK: - 공용 · 게임 탭 카드 (배선 갈래 1/4)

    package static let title = ReversiNoticeText.gameName
    /// 게임 탭 카드 부제 · 로비 머리글 부제(맥 `ReversiText.subtitle` 과 같은 한 줄 — 규칙 · 선공 · 한 수 시간).
    package static let subtitle = "리버시 규칙 · 흑 선공 · 한 수 30초"
    package static let cardSubtitle = subtitle
    /// 게임 탭 카드의 보이스오버 힌트(막히지 않았을 때).
    package static let cardOpenHint = "\(ReversiNoticeText.gameName) 대결 화면을 열어요"
    /// 카드 칩: 받은 신청이 있다(몇 건인지는 칩이 말한다 — 탭 배지와 같은 수).
    package static func incomingChip(_ count: Int) -> String { "받은 신청 \(count)건" }
    /// 카드 보조 줄: 보낸 신청의 답을 기다린다.
    package static let outgoingLine = "보낸 신청의 답을 기다리고 있어요"
    /// 칩도 보조 줄 재료도 없을 때의 카드 한 줄(= 할 일을 말한다). AI 연습이 있다는 것도 함께 말한다(체스 카드 부제와 같은 자리).
    package static let idleLine = "사람을 골라 신청하거나 로봇과 연습해 보세요"

    package static let recordTitle = "내 전적"
    package static func record(wins: Int, losses: Int, draws: Int) -> String { "\(wins)승 \(losses)패 \(draws)무" }

    package static func record(_ record: ReversiRecord?) -> String {
        guard let record else { return self.record(wins: 0, losses: 0, draws: 0) }
        return self.record(wins: record.wins, losses: record.losses, draws: record.draws)
    }

    // MARK: - 판 · 결과 · 로봇 연습 (판 갈래 2/4)
    //
    // 맥 `ReversiText` 의 대국·결과·AI 절과 **같은 사실을 같은 말로** 옮겼다. 폰에서 달라진 자리는 셋이다:
    //  · 연습 상대 이름이 '로봇'이다 — 코어 `ReversiUser.reversiAI`(이름 "로봇" · 캐릭터 robot)와 게임 탭 카드 한 줄
    //    ("…로봇과 연습해 보세요")이 이미 그 이름을 쓴다. 맥은 같은 자리에 'AI'를 그린다(맥 화면 표의 몫).
    //  · 끝난 까닭의 '상대'는 로봇 판에서 '로봇'이다(한 함수가 주어만 바꾼다 — 두 벌을 두면 한쪽만 고쳐진다).
    //  · 호버 툴팁이 없으므로 시계 규칙을 판 밑 한 줄로 말한다(1:1 은 서버 시계 · 로봇 판은 화면을 떠나면 멈춘다).

    package static let me = "나"
    /// 별명을 모르는 상대(탈퇴·익명화·옛 응답).
    package static let opponentFallbackName = "상대"
    package static let myTurn = "내 차례예요"
    package static let opponentTurn = "상대 차례예요"
    /// 1:1 판의 내 마감 + 서버 유예가 지났다 — 서버가 합법 수 가운데 하나를 대신 두는 중이다(폰이 정한 것이 아니다).
    package static let mySettling = "시간이 지나 자동으로 놓이는 중이에요"
    package static let opponentSettling = "상대 시간이 지나 자동으로 놓이는 중이에요"

    package static func stoneName(_ color: ReversiColor) -> String { color == .black ? "흑" : "백" }
    /// 카드의 돌 수 줄 "흑 · 12개".
    package static func discLine(_ color: ReversiColor, count: Int) -> String { "\(stoneName(color)) · \(count)개" }
    /// 판 위 돌 수 한 줄 "흑 2 · 백 2 · 빈칸 60".
    package static func counts(_ counts: ReversiCounts) -> String {
        "흑 \(counts.black) · 백 \(counts.white) · 빈칸 \(counts.empty)"
    }
    /// 연달아 자동으로 놓인 횟수(카드 꼬리). 0 이면 말하지 않는다.
    package static func autoStreak(_ streak: Int, limit: Int) -> String? {
        streak > 0 ? "자동 \(streak)/\(limit)" : nil
    }
    /// 한 번 더 놓치면 지는 순간(빨강 한 줄). 맥 `ReversiText.autoStreakWarning` 과 같은 말.
    package static func autoStreakWarning(_ streak: Int, limit: Int) -> String? {
        guard limit > 1, streak == limit - 1 else { return nil }
        return "한 번 더 시간이 지나면 져요"
    }
    /// 판 위 회색 점이 말하는 것을 글자로도(폰엔 툴팁이 없다).
    package static func autoPlacedCount(_ count: Int) -> String { "시간이 지나 자동으로 놓인 돌 \(count)개 · 회색 점" }

    /// 판 밑 시계 규칙 한 줄. **숫자는 서버가 말한 값**(로비 `turn_seconds` · 판의 `auto_abandon_streak`)에서 만든다.
    /// 1:1 은 앱을 나가도 서버 시계가 흐르고, 로봇 판은 화면을 떠나면 사람 시계가 멈춘다(**정반대 사실** — 한 줄이 둘을 가른다).
    package static func clockLine(isAI: Bool, turnSeconds: Int, lossStreak: Int) -> String {
        let rule = "한 수 \(turnSeconds)초가 지나면 자동으로 놓이고 \(lossStreak)번 이어지면 져요"
        return (isAI ? "화면을 떠나거나 앱을 나가면 내 시계가 멈춰요" : "앱을 나가도 차례 시간은 흘러요") + " · " + rule
    }

    /// 남은 초("12초").
    package static func remaining(_ seconds: Double) -> String { "\(Int(max(0, seconds).rounded(.up)))초" }
    package static func clockAccessibility(_ seconds: Double) -> String { "남은 시간 \(remaining(seconds))" }

    package static let movesTitle = "수 기록"
    package static let noMoves = "아직 둔 수가 없어요"
    /// 수 기록의 패스 칸.
    package static let pass = "넘김"
    /// 칸 표기("d3"). 범위 밖이면 "—".
    package static func coordinate(_ idx: Int?) -> String {
        guard let idx, let point = ReversiPoint(idx: idx) else { return "—" }
        return point.coord
    }
    /// 수 한 칸 글자: 돌이면 "d3"(자동이면 "d3 · 자동"), 패스면 "넘김".
    package static func plyText(_ ply: ReversiPly) -> String {
        switch ply.kind {
        case .pass: return pass
        case .stone: return ply.auto ? "\(coordinate(ply.idx)) · 자동" : coordinate(ply.idx)
        }
    }

    package static let resign = "기권"
    package static let resignConfirmTitle = "기권하면 건 루비를 잃어요"
    package static let resignConfirmMessage = "지금 기권하면 이 판은 상대가 이겨요."
    package static let resignNow = "기권하기"
    package static let keepPlaying = "계속 두기"
    package static let backToLobby = "로비로"

    // 결과.
    package static func outcomeTitle(_ outcome: ReversiMatchOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요"
        case .lost?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대국이 끝났어요"
        }
    }

    /// 끝난 까닭 한 줄(**내 기준**). 끝 사유 여섯 갈래를 빠짐없이 말한다(`default:` 로 접지 않는다 — 돈이 갈리는 문장이다).
    /// `opponent` 는 주어 낱말이다(1:1 '상대' · 로봇 판 '로봇'). `lossStreak` 는 그 판의 서버 값(자동 착수 연속 패 횟수).
    package static func endReason(
        _ reason: ReversiEndReason?, outcome: ReversiMatchOutcome?, opponent: String, lossStreak: Int
    ) -> String {
        guard let reason else { return "" }
        switch reason {
        case .wipeout: return outcome == .lost ? "내 돌이 모두 뒤집혔어요" : "\(opponent) 돌을 모두 뒤집었어요"
        case .boardFull: return "판이 가득 찼어요"
        case .noMoves: return "둘 다 둘 곳이 없어요"
        case .resign: return outcome == .won ? "\(opponent)\(subjectParticle(opponent)) 기권했어요" : "기권했어요"
        case .abandoned:
            return outcome == .won ? "\(opponent) 시간이 \(lossStreak)번 이어서 지났어요"
                                   : "시간이 \(lossStreak)번 이어서 지나 졌어요"
        case .unknown: return "대국이 끝났어요"
        }
    }

    /// 자연 종료 점수 줄 — **흑 : 백 고정**(내 색 먼저가 아니다). 빈칸이 있으면 판 위 돌 수를 괄호로 함께(빈칸은 이긴 쪽 점수다).
    package static func scoreLine(_ score: ReversiScore, counts: ReversiCounts) -> String {
        let main = "흑 : 백  \(score.black) : \(score.white)"
        guard counts.empty > 0 else { return main }
        return "\(main) (판 위 \(counts.black) : \(counts.white))"
    }
    /// 기권·자리 비움 판(점수 없음) — 점수 줄 대신 판 위 돌 수만.
    package static func boardOnlyLine(_ counts: ReversiCounts) -> String { "판 위 흑 \(counts.black) : 백 \(counts.white)" }

    /// 루비 변화(+5 / −5 / ±0).
    package static func rubyDelta(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(-delta)" }
        return "±0"
    }
    package static func rubyDeltaAccessibility(_ text: String) -> String { "루비 \(text)" }
    /// 무승부 판의 루비 — 건 판돈이 그대로 돌아왔다.
    package static func drawRefund(stake: Int) -> String { "판돈 \(stake) 루비를 돌려받았어요" }
    /// " · 이기면 +5"(내비 부제 판돈 줄 꼬리 — 순이익).
    package static func stakeGainSuffix(_ stake: Int) -> String { " · 이기면 +\(DuelFee.winnerNet(stake: stake))" }

    /// 판 전체 보이스오버 한 줄(돌 수 · 차례 · 둘 수 있는 칸 수).
    package static func boardAccessibility(counts: ReversiCounts, turn: ReversiColor?, legalCount: Int) -> String {
        var text = "\(title) 판, \(self.counts(counts))"
        if let turn { text += ", \(stoneName(turn)) 차례" }
        if legalCount > 0 { text += ", 둘 수 있는 칸 \(legalCount)곳" }
        return text
    }

    /// 칸 하나의 보이스오버("d3, 흑 돌, 마지막 수" · "c4, 빈칸, 둘 수 있어요"). 칸 이름이 먼저다 — 판을 훑는 사람은 이름으로 찾는다.
    package static func cellAccessibility(
        idx: Int, stone: ReversiColor?, isLegal: Bool, isLast: Bool, isAuto: Bool
    ) -> String {
        var parts = [coordinate(idx)]
        if let stone {
            parts.append("\(stoneName(stone)) 돌")
            if isLast { parts.append("마지막 수") }
            if isAuto { parts.append("자동으로 놓임") }
        } else {
            parts.append("빈칸")
            if isLegal { parts.append("둘 수 있어요") }
        }
        return parts.joined(separator: ", ")
    }

    // 로봇 연습(맥 'AI와 두기' 와 같은 단계: 돌 색 고르기 → 곧바로 판 → 결과에서 같은 색으로 다시).
    package static let aiName = ReversiUser.reversiAI.displayName
    package static let aiButton = "로봇과 연습하기"
    package static let aiButtonHelp = "루비·전적 없이 로봇과 둬요"
    package static let aiPromptTitle = "어느 돌로 둘까요"
    package static let aiPromptCaption = "고르면 바로 시작해요"
    package static let aiPlayBlack = "흑 · 먼저 둬요"
    package static let aiPlayWhite = "백 · 나중에 둬요"
    package static let aiPlayRandom = "무작위"
    package static let aiNoRecord = "로봇과 둔 판은 루비·전적·순위에 남지 않아요"
    package static let aiStakeChip = "로봇과 연습 · 기록 없음"
    package static let aiThinking = "로봇이 생각 중이에요"
    package static let aiThinkingShort = "생각 중"
    package static let aiResignConfirmTitle = "기권하면 이 판은 로봇이 이겨요"
    package static let aiRematch = "같은 색으로 다시 두기"
    package static let aiOpponentLine = "상대 · 로봇"
    package static func opponentLine(_ name: String) -> String { "상대 · \(name)" }

    /// 로봇 연습 입구가 닫힌 까닭(맥은 버튼만 흐린다 — 폰엔 툴팁이 없어 **언제 풀리는지**를 글자로 말한다).
    package enum AIBlock: Equatable, Sendable, CaseIterable {
        /// 1:1 판이 서 있다(같은 계정 다른 기기의 판 포함).
        case playing
        /// 보낸 신청이 떠 있다 — 수락되는 순간 1:1 이 연습 판을 이긴다.
        case outgoingInvite
        /// 요청이 오가는 중.
        case busy
    }

    package static func aiBlock(_ reason: AIBlock) -> String {
        switch reason {
        case .playing: return "두고 있는 판이 끝나면 연습할 수 있어요"
        case .outgoingInvite: return "보낸 신청을 취소하면 연습할 수 있어요"
        case .busy: return "잠시 후 다시 눌러 주세요"
        }
    }

    /// 받침 고르기(이/가). 끝 글자에 받침이 있으면 "이", 없으면 "가"(한글이 아니면 "가").
    private static func subjectParticle(_ word: String) -> String {
        guard let last = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return "가" }
        return (last.value - 0xAC00) % 28 == 0 ? "가" : "이"
    }
}
