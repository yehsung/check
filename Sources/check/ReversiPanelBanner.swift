import AppKit
import SwiftUI
import CheckCore

// 아잉 뒤집기(내부 이름 reversi) — **맥 화면 문구 한 곳**(`ReversiText`)과 창 밖 표면 두 조각(입구 아이콘 · 팝오버 신청 배너).
//
// 문구 집이 여기인 까닭(설계서 FLIP/SPEC.md §1 · §5.6, v1.1 CCT M4): 메뉴바 점 · 팝오버 배너 · 캐릭터 말풍선 · 미니게임
// 사이드바 입구를 꽂는 통합 갈래(T)는 이 이름만 부른다 — 같은 사실은 한 문구다(큐브 `RummyInviteText` 선례).
// 게임 이름 글자는 코어 `ReversiNoticeText.gameName` 한 곳이고 여기는 그 값을 받는다.
// 진단 어휘(서버·상태·동기화·프로토콜)는 쓰지 않는다 — 사용자가 **할 수 있는 일**을 말한다.

/// 아잉 뒤집기 맥 화면의 사용자 문구(순수 — 값으로 검증한다).
enum ReversiText {
    // MARK: 이름 · 입구

    /// 게임 이름(창 제목 · 사이드바 입구 제목). 글자는 코어 한 곳에서 온다.
    static let gameName = ReversiNoticeText.gameName
    static let title = gameName
    /// 머리글 캡션. 시간 수치는 서버 기본값(30초)과 같은 상수 `turnSeconds` 에서 만든다.
    static let subtitle = "리버시 규칙 · 흑 선공 · 한 수 \(Int(turnSeconds))초"
    /// 미니게임 사이드바 입구 도움말(오목 '렌주룰 1:1 오목…' · 체스 'FIDE 규칙 1:1 체스…' 꼴).
    static let sidebarHelp = "리버시 규칙 1:1 대결 창을 열어요"
    /// 메뉴바 점 보이스오버 사유.
    static let dotReason = "\(gameName) 신청"

    /// 한 수 제한(초). 서버 `turn_seconds` 와 짝인 상수다 — 링이 몇 초에서 가득 차는지만 정한다(남은 시간은 서버 마감에서 온다).
    /// 30초 링 그림(`GomokuClockRing`)은 오목 상수(`GomokuText.turnSeconds`)를 읽는다 — 두 값이 갈리면 창 시험이 빨개진다.
    static let turnSeconds: Double = 30

    static let rulesButton = "규칙"
    static let rulesTitle = "\(gameName) 규칙"
    static let rulesHelp = "\(gameName) 규칙을 봐요"
    static let close = "닫기"
    static let myRubyHelp = "내 루비"

    // MARK: 로비

    static let lobbyTitle = "상대 고르기"
    static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    static let challenge = "도전"
    static let needsUpdate = "앱 업데이트 필요"
    static let inMatch = "대결 중"
    static let focusMode = "집중 모드"
    static let working = "근무 중"
    static let challengeLockedHelp = "지금은 신청할 수 없는 상대예요"

    static let stakeTitle = "판돈"
    static let stakeUnknown = "—"
    /// 판돈 줄. 이기면 **순이익**(`DuelFee.winnerNet` — 수수료 0) — 결과 카드의 루비 변화와 같은 숫자다.
    static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    static let stakePromptCaption = "판돈을 고르세요"
    static func stakePromptChosen(_ stake: Int) -> String { "판돈 \(stakeLine(stake))" }
    static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 도전하기" }
    static let stakeShortfall = CheckCoreShared.shortfallNotice(need: nil, have: nil)

    static let incomingTitle = "받은 신청"
    static let outgoingTitle = "보낸 신청"
    static let noIncoming = "받은 신청이 없어요"
    static let accept = "수락"
    static let decline = "거절"
    static let cancel = "취소"
    static func incomingLine(name: String) -> String { "\(name)님의 신청" }

    static let recordTitle = "내 전적"
    static let liveTitle = "지금 대결 중"
    static let noLive = "지금 진행 중인 대결이 없어요"
    static let watch = "관전"
    static let myMatch = "내 판"
    static let leaveWatch = "나가기"
    static let watchLoading = "판을 불러오고 있어요"
    static let watchPaused = "창을 열어 두면 판이 계속 따라와요"

    static let rankTitle = "\(gameName) 순위"
    static let rankLoading = "순위를 불러오고 있어요"
    static let rankEmpty = "아직 순위가 없어요"
    static let rankSoon = "순위는 곧 열려요"
    static let rankHelp = "승점 = 승 − 패"
    static func rankSince(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일부터"
        return formatter.string(from: date)
    }

    static func record(_ record: ReversiRecord?) -> String {
        guard let record else { return "0승 0패 0무" }
        return self.record(wins: record.wins, losses: record.losses, draws: record.draws)
    }

    static func record(wins: Int, losses: Int, draws: Int) -> String { "\(wins)승 \(losses)패 \(draws)무" }
    static func myRank(rank: Int, points: Int) -> String { "\(rank)위 · \(self.points(points))" }
    static func points(_ value: Int) -> String { "승점 \(value >= 0 ? "+" : "")\(value)" }

    // MARK: 팝오버 배너 · 말풍선 · 차례 알림

    static func inviteBannerTitle(name: String) -> String { "\(name)님이 \(gameName) 대결을 신청했어요" }
    static let inviteBannerSubtitle = "1분 안에 응답하세요"
    static let acceptHelp = "수락하고 \(gameName) 창을 열어요"
    static let viewInvite = "보기"
    static let viewInviteHelp = "\(gameName) 창에서 이 신청을 봐요"

    /// 캐릭터 말풍선의 신청 문구(순수). 체스·큐브 말풍선과 **같은 접기 규칙**(캡슐에 들어갈 때까지 세 단계).
    static func bubbleText(name: String, stake: Int) -> String {
        let shortName = OverlayMessageBubble.clippedName(name)
        if !shortName.isEmpty {
            let full = "\(shortName)님이 \(gameName) 대결을 신청했어요 · 루비 \(stake)"
            if OverlayMessageBubble.fitsCapsule(full) { return full }
            let short = "\(shortName)님의 \(gameName) 신청 · 루비 \(stake)"
            if OverlayMessageBubble.fitsCapsule(short) { return short }
        }
        return "\(gameName) 대결 신청 · 루비 \(stake)"
    }

    /// 창이 안 보이는 사람에게 띄우는 차례 말풍선 문구(순수). 한 수 30초라 이 길이 없으면 자동 착수 3번으로 판돈을 잃는다.
    static func attentionText(_ attention: ReversiAttention) -> String {
        let fallback = "\(gameName) — 내 차례예요"
        switch attention.kind {
        case .matchStarted:
            let full = "\(gameName) 대결이 시작됐어요 · 내 차례예요"
            return OverlayMessageBubble.fitsCapsule(full) ? full : fallback
        case .myTurn:
            let name = OverlayMessageBubble.clippedName(attention.opponentName)
            if !name.isEmpty {
                let full = "\(name)님이 뒀어요 · \(gameName) 내 차례예요"
                if OverlayMessageBubble.fitsCapsule(full) { return full }
            }
            return fallback
        }
    }

    // MARK: 대국

    static let myTurn = "내 차례예요"
    static let opponentTurn = "상대 차례예요"
    static let resign = "기권"
    static let confirmResign = "기권하기"
    static let keepPlaying = "계속 두기"
    static let resignHelp = "한 번 더 확인한 뒤 기권해요"
    static let backToLobby = "로비로"
    static let playAgain = "다시 두기"

    static func stoneName(_ color: ReversiColor) -> String { color == .black ? "흑" : "백" }
    /// 카드의 "흑 · 12개" 줄.
    static func discLine(_ color: ReversiColor, count: Int) -> String { "\(stoneName(color)) · \(count)개" }
    /// 돌 수 줄(돌 수·수 기록 카드 제목 줄).
    static func counts(_ counts: ReversiCounts) -> String {
        "흑 \(counts.black) · 백 \(counts.white) · 빈칸 \(counts.empty)"
    }

    /// 연달아 자동으로 놓인 횟수(카드 둘째 줄). 0 이면 말하지 않는다.
    static func autoStreak(_ streak: Int, limit: Int) -> String? {
        streak > 0 ? "자동 \(streak)/\(limit)" : nil
    }
    /// 한 번 더 놓치면 지는 순간의 경고(상태 상자).
    static func autoStreakWarning(_ streak: Int, limit: Int) -> String? {
        guard limit > 1, streak == limit - 1 else { return nil }
        return "한 번 더 시간이 지나면 져요"
    }
    /// 판 위 회색 점이 말하는 것을 글자로도(툴팁만 두지 않는다).
    static func autoPlacedCount(_ count: Int) -> String { "시간이 지나 자동으로 놓인 돌 \(count)개 · 회색 점" }
    static let autoPlacedStoneHelp = "시간이 지나 자동으로 놓인 돌이에요"

    static let movesTitle = "수 기록"
    static let noMoves = "아직 둔 수가 없어요"
    /// 수 목록의 패스 칸.
    static let pass = "넘김"
    /// 수 목록의 자동 착수 꼬리.
    static let autoTag = "자동"
    /// 칸 표기("d3"). 범위 밖이면 "—".
    static func coordinate(_ idx: Int?) -> String {
        guard let idx, let point = ReversiPoint(idx: idx) else { return "—" }
        return point.coord
    }
    /// 수 한 칸 글자: 돌이면 "d3"(자동이면 "d3 · 자동"), 패스면 "넘김".
    static func plyText(_ ply: ReversiPly) -> String {
        switch ply.kind {
        case .pass: return pass
        case .stone:
            let coord = coordinate(ply.idx)
            return ply.auto ? "\(coord) · \(autoTag)" : coord
        }
    }

    // MARK: AI

    static let aiButton = "AI와 두기"
    static let aiButtonHelp = "루비·전적 없이 AI와 연습해요"
    static let aiPromptTitle = "AI와 두기"
    static let aiPromptCaption = "돌 색을 고르면 바로 시작해요"
    static let aiPlayBlack = "흑 · 먼저 둬요"
    static let aiPlayWhite = "백 · 나중에 둬요"
    static let aiPlayRandom = "무작위"
    static let aiInfo = "AI와 둔 판은 루비·전적·순위에 남지 않아요"
    static let aiOpponentName = "AI"
    static let aiThinking = "AI가 생각 중이에요"
    static let aiThinkingShort = "생각 중"
    static let aiStakeChip = "AI 대국 · 기록 없음"

    // MARK: 결과

    static func outcomeTitle(_ outcome: ReversiMatchOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요"
        case .lost?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대국이 끝났어요"
        }
    }

    /// 끝난 까닭 한 줄(**내 기준**). 끝 사유 여섯 갈래를 빠짐없이 말한다(`default:` 로 접지 않는다).
    static func endReason(_ reason: ReversiEndReason?, outcome: ReversiMatchOutcome?) -> String {
        guard let reason else { return "" }
        switch reason {
        case .wipeout: return outcome == .lost ? "내 돌이 모두 뒤집혔어요" : "상대 돌을 모두 뒤집었어요"
        case .boardFull: return "판이 가득 찼어요"
        case .noMoves: return "둘 다 둘 곳이 없어요"
        case .resign: return outcome == .won ? "상대가 기권했어요" : "기권했어요"
        case .abandoned: return "자리 비움 3번으로 끝났어요"
        case .unknown: return "대국이 끝났어요"
        }
    }

    /// **관전** 결과 한 줄 — 3인칭(주어가 '흑'·'백'). 내 기준 `endReason` 을 남의 판에 쓰면 자기모순 문장이 된다.
    static func watchEndReason(_ reason: ReversiEndReason?, winner: ReversiColor?) -> String {
        guard let reason else { return "" }
        let loser = winner.map { stoneName($0.opponent) }
        switch reason {
        case .wipeout: return loser.map { "\($0) 돌이 모두 뒤집혔어요" } ?? "한쪽 돌이 모두 뒤집혔어요"
        case .boardFull: return "판이 가득 찼어요"
        case .noMoves: return "둘 다 둘 곳이 없어요"
        case .resign: return loser.map { "\($0)이 기권했어요" } ?? "기권으로 끝났어요"
        case .abandoned: return loser.map { "\($0)이 자리 비움 3번으로 끝났어요" } ?? "자리 비움 3번으로 끝났어요"
        case .unknown: return "대국이 끝났어요"
        }
    }

    /// 자연 종료 점수 줄 — **흑 : 백 고정**(내 색 먼저가 아니다, V-12). 빈칸이 있으면 판 위 돌 수를 괄호로 함께,
    /// 빈칸 0이면 점수 하나만(점수 = 판 위 돌 수).
    static func scoreLine(_ score: ReversiScore, counts: ReversiCounts) -> String {
        let main = "\(score.black) : \(score.white)"
        guard counts.empty > 0 else { return main }
        return "\(main) (판 위 \(counts.black) : \(counts.white))"
    }
    /// 점수 줄 앞 이름표.
    static let scoreLabel = "흑 : 백"
    /// 기권·자리 비움 판(WOF 점수 없음, V-15) — 점수 줄 대신.
    static func boardOnlyLine(_ counts: ReversiCounts) -> String { "판 위 흑 \(counts.black) : 백 \(counts.white)" }

    /// 결과 카드 루비 줄(순수익). 승 `+N` · 패 `−N` · 무 `0 · 판돈을 돌려받았어요`.
    static func rubyLine(outcome: ReversiMatchOutcome?, stake: Int) -> String {
        switch outcome {
        case .won?: return "+\(DuelFee.winnerNet(stake: stake))"
        case .lost?: return "−\(stake)"
        case .draw?: return "0 · 판돈을 돌려받았어요"
        case nil: return "0"
        }
    }

    /// 판 전체를 읽는 보이스오버 한 줄.
    static func boardAccessibility(counts: ReversiCounts, turn: ReversiColor?, legalCount: Int) -> String {
        var text = "\(gameName) 판, \(Self.counts(counts))"
        if let turn { text += ", \(stoneName(turn)) 차례" }
        if legalCount > 0 { text += ", 둘 수 있는 칸 \(legalCount)곳" }
        return text
    }
}

// MARK: - 아이콘 한 출처

/// 아잉 뒤집기를 가리키는 **아이콘 한 출처**. 창 머리글 · 미니게임 입구 · 팝오버 배너 · 일일 미션 줄이 같은 기호를 쓴다.
/// 이름이 없으면 `Image(systemName:)` 는 아무것도 안 그린다(자리만 빈다) — 그래서 이 맥에서 실제로 풀리는 이름만 쓴다.
enum ReversiEntryIcon {
    /// 반은 흑, 반은 백인 원 — 뒤집히는 돌.
    static let symbol = "circle.lefthalf.filled"
    static let fallbackSymbol = "circle.fill"

    @MainActor
    static var resolved: String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : fallbackSymbol
    }
}

// MARK: - 팝오버 신청 배너

/// 팝오버 배너의 남은 초 — **잎**이다. 팝오버가 닫혀 창이 비활성이면 멈춘다.
struct ReversiInviteBannerCountdown: View {
    let invite: ReversiInvite
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        ChessCountdownText(expiresAt: invite.expiresAt, isLive: controlActiveState != .inactive)
    }
}

/// 팝오버의 **받은 아잉 뒤집기 신청 배너**. 체스 배너(`ChessInviteBanner`)를 베끼고 문구·아이콘만 바꿨다 — 모양·높이가 같다.
/// 꽂는 것(후보·수락·거절·열기·`topBannerHeight`)은 통합 갈래(T)가 `CheckMenuView` 에서 한다.
struct ReversiInviteBanner: View {
    let invite: ReversiInvite
    let onAccept: () -> Void
    let onDecline: () -> Void
    /// [보기] — 창을 열어 이 신청을 보여 준다.
    var onOpen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: ReversiEntryIcon.resolved)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ReversiText.inviteBannerTitle(name: invite.peer.displayName))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 3) {
                        Text(ReversiText.stakeTitle)
                        RubyIcon(size: 11)
                        Text("\(invite.stake) · \(ReversiText.inviteBannerSubtitle)")
                    }
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
                ReversiInviteBannerCountdown(invite: invite)
            }
            HStack(spacing: 8) {
                Button(action: onAccept) {
                    Text(ReversiText.accept)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CheckTheme.accent))
                }
                .buttonStyle(.plain)
                .checkTooltip(ReversiText.acceptHelp)
                Button(action: onDecline) {
                    Text(ReversiText.decline)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(CheckTheme.accent.opacity(0.14))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                if let onOpen {
                    Button(action: onOpen) {
                        Text(ReversiText.viewInvite)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(CheckTheme.accent.opacity(0.14))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .checkTooltip(ReversiText.viewInviteHelp)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.accent.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckTheme.accent.opacity(0.55), lineWidth: 1)
                )
        )
    }
}
