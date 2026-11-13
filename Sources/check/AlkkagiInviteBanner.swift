import AppKit
import SwiftUI
import CheckCore

// 1:1 알까기 — **맥 화면 문구 한 곳**(`AlkkagiText`)과 창 밖 표면 두 조각(입구 아이콘 · 팝오버 신청 배너). SPEC v1.1 §5.8.
//
// 문구 집이 여기인 까닭(뒤집기 `ReversiText` · 길건너 `CrossyDuelText` 선례): 메뉴바 점 · 팝오버 배너 · 캐릭터 말풍선 · 미니게임
// 사이드바 입구를 꽂는 통합 갈래(T)는 이 이름만 부른다 — 같은 사실은 한 문구다. 게임 이름 글자는 코어
// `AlkkagiNoticeText.gameName` 한 곳이고 여기는 그 값을 받는다. 낱말은 '대결'·'신청'(대전·초대 금지 — 렌더 문구 시험).
// 루비는 문자열에서 늘 "루비 N" 이고 그림은 `RubyIcon` 이다(💎 글자 금지 — VC-7).

/// 1:1 알까기 맥 화면의 사용자 문구(순수 — 값으로 검증한다).
enum AlkkagiText {
    // MARK: 이름 · 입구

    /// 게임 이름(창 제목 · 로비 · 판 머리 · 배너 · 사이드바). 글자는 코어 한 곳에서 온다(DF#2).
    static let gameName = AlkkagiNoticeText.gameName
    static let title = gameName
    /// 머리글 부제(DF#5). 30초 두 개는 서버 규칙(숨긴 배치 · 한 수)과 같은 수다.
    static let subtitle = "숨겨 놓기 30초 · 흑 선공 · 한 수 30초"
    /// 미니게임 사이드바 입구 도움말(SPEC §1 맥 문구).
    static let sidebarHelp = "돌을 튕겨 밀어내는 1:1 알까기 대결 창을 열어요"
    /// 메뉴바 점 보이스오버 사유(SPEC §1 — "1:1 알까기 신청").
    static let dotReason = "\(gameName) 신청"

    static let rulesButton = "규칙"
    static let rulesTitle = "\(gameName) 규칙"
    static let rulesHelp = "\(gameName) 규칙을 봐요"
    static let close = "닫기"
    static let myRubyHelp = "내 루비"
    /// 머리 [연습하기](로비에서만 — DF#14).
    static let practiceButton = "연습하기"
    static let practiceHelp = "루비·전적 없이 한 맥에서 둘이 번갈아 연습해요"
    static let practiceSubtitle = "연습 판 · 루비·전적에 남지 않아요"
    static let backToLobby = "로비로"

    // MARK: 로비

    static let lobbyTitle = "상대 고르기"
    static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    static let loadingUsers = "상대 목록을 불러오고 있어요"
    static let usersLoadFailed = AlkkagiNoticeText.checkConnection
    static let reloadUsers = "다시 불러오기"
    static let challenge = "도전"
    static let needsUpdate = "앱 업데이트 필요"
    static let inMatch = "대결 중"
    static let focusMode = "집중 모드"
    static let working = "근무 중"
    static let idle = "—"

    static let stakeTitle = "판돈"
    static let stakeUnknown = "—"
    /// 판돈 줄. 이기면 **순이익**(`DuelFee.winnerNet` — 수수료 0) — 결과 카드의 루비 변화와 같은 숫자다.
    static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    static func stakeLine(_ stake: Int?) -> String { stake.map { stakeLine($0) } ?? stakeUnknown }
    static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    static let stakePromptCaption = "판돈을 고르세요"
    static func stakePromptChosen(_ stake: Int) -> String { "\(stakeTitle) \(stakeLine(stake))" }
    static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 도전하기" }
    /// 잔액 < 판돈(잔액을 모르면 막지 않는다).
    static let stakeShortfall = CheckCoreShared.shortfallNotice(need: nil, have: nil)

    static let incomingTitle = "받은 신청"
    static func incomingMore(_ count: Int) -> String { "외 \(count)건" }
    static func incomingLine(name: String) -> String { "\(name)님의 신청" }
    static let outgoingTitle = "보낸 신청"
    static let noIncoming = "받은 신청이 없어요"
    static let accept = "수락"
    static let responding = "응답 중…"
    static let decline = "거절"
    static let cancel = "취소"
    /// 보낸 신청 한 줄 "보낸 신청 · 이름 · N"(옛 신청 — 판돈 nil — 이면 이름까지).
    static func outgoingLine(name: String, stake: Int?) -> String {
        guard let stake else { return "\(outgoingTitle) · \(name)" }
        return "\(outgoingTitle) · \(name) · \(stake)"
    }

    static let recordTitle = "내 전적"
    static let liveTitle = "지금 대결 중"
    static let noLive = "지금 진행 중인 대결이 없어요"
    static let watch = "관전"
    static let leaveWatch = "나가기"

    static let rankTitle = "알까기 순위"
    static let rankHelp = "승점 = 승 − 패"
    static let rankLoading = "순위를 불러오고 있어요"
    static let rankEmpty = "아직 순위가 없어요"
    static let rankSoon = "순위는 곧 열려요"

    static func record(_ record: AlkkagiRecord?) -> String {
        guard let record else { return "0승 0패 0무" }
        return self.record(wins: record.wins, losses: record.losses, draws: record.draws)
    }

    static func record(wins: Int, losses: Int, draws: Int) -> String { "\(wins)승 \(losses)패 \(draws)무" }
    static func myRank(rank: Int, points: Int) -> String { "\(rank)위 · \(self.points(points))" }
    static func points(_ value: Int) -> String { "승점 \(value >= 0 ? "+" : "")\(value)" }

    // MARK: 팝오버 배너 · 말풍선

    static let someone = "누군가"
    static func displayName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? someone : trimmed
    }
    static func inviteBannerTitle(name: String) -> String { "\(displayName(name))님이 \(gameName) 대결을 신청했어요" }
    static let inviteBannerSubtitle = "1분 안에 응답하세요"
    static let acceptHelp = "수락하고 \(gameName) 창을 열어요"
    static let viewInvite = "보기"
    static let viewInviteHelp = "\(gameName) 창에서 이 신청을 봐요"

    /// 받은 신청 말풍선(3단 줄임 — 체스·뒤집기·길건너와 같은 접기 규칙). 판돈은 "루비 N"(💎 금지 — VC-7).
    static func inviteBubbleText(name: String?, stake: Int?) -> String {
        let ruby = stake.map { " · 루비 \($0)" } ?? ""
        let shortName = OverlayMessageBubble.clippedName(displayName(name))
        let full = "\(shortName)님이 \(gameName) 대결을 신청했어요\(ruby)"
        if OverlayMessageBubble.fitsCapsule(full) { return full }
        let short = "\(shortName)님의 \(gameName) 신청\(ruby)"
        if OverlayMessageBubble.fitsCapsule(short) { return short }
        return "\(gameName) 대결 신청\(ruby)"
    }

    /// 시작 말풍선 — 이름을 알면 "{이름}님과 …", 모르면 이름 없는 꼴.
    static func matchStartedText(name: String?) -> String {
        let fallback = "\(gameName) 대결이 시작됐어요"
        let shortName = OverlayMessageBubble.clippedName((name ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        guard !shortName.isEmpty else { return fallback }
        let full = "\(shortName)님과 \(gameName) 대결이 시작됐어요"
        return OverlayMessageBubble.fitsCapsule(full) ? full : fallback
    }

    /// 내 차례 말풍선 — **상대가 쏴서 넘어왔을 때만** 이름을 넣는다(상대 시간 넘김 · 배치 끝 · 이름 모름은 이름 없는 꼴, VC-20).
    static func myTurnText(shooterName: String?) -> String {
        let fallback = "알까기 내 차례예요"
        let shortName = OverlayMessageBubble.clippedName((shooterName ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        guard !shortName.isEmpty else { return fallback }
        let full = "\(shortName)님이 쐈어요 · 알까기 내 차례예요"
        return OverlayMessageBubble.fitsCapsule(full) ? full : fallback
    }

    // MARK: 판

    static let myTurn = "내 차례예요"
    static func opponentTurn(name: String) -> String { "\(displayName(name))님 차례예요" }
    static let closeKeepsMatch = "창을 닫아도 대결은 계속돼요"
    static let soundOff = "소리 끄기"
    static let soundOn = "소리 켜기"

    static func outcomeTitle(_ outcome: AlkkagiOutcome?) -> String {
        switch outcome {
        case .win?: return "이겼어요"
        case .loss?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대결이 끝났어요"
        }
    }

    /// 결과 카드 루비 줄: 승 `+N` · 패 `−N` · 무(무효 포함) `0 · 판돈을 돌려받았어요`.
    static func rubyLine(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(-delta)" }
        return "0 · 판돈을 돌려받았어요"
    }

    // MARK: 관전

    static let watchLoading = "판을 불러오고 있어요"
    static let watchPlacing = "두 사람이 돌을 숨겨 놓는 중이에요"
    static let watchRolling = "돌이 멈추면 차례가 바뀌어요"
    static let watchPaused = "창을 열어 두면 판이 계속 따라와요"
    static func stoneName(_ player: AlkkagiGame.Player) -> String { player == .black ? "흑" : "백" }
    static func watchTurn(_ player: AlkkagiGame.Player) -> String { "\(stoneName(player)) 차례" }
    /// 관전 결과 제목(3인칭 — 내 기준 문장을 남의 판에 쓰지 않는다).
    static func watchOutcome(_ result: AlkkagiMatchResult?) -> String {
        switch result {
        case .black?: return "흑 승리"
        case .white?: return "백 승리"
        case .draw?: return "무승부로 끝났어요"
        case .unknown?, nil: return "대결이 끝났어요"
        }
    }

    /// 관전 결과 사유(3인칭). 내 기준 문구(`AlkkagiNoticeText.endReason`)를 쓰지 않는다 — 관전자에겐 '나'가 없다.
    static func watchEndReason(_ reason: AlkkagiEndReason?, result: AlkkagiMatchResult?) -> String {
        let loser: String? = switch result {
        case .black?: "백"
        case .white?: "흑"
        default: nil
        }
        switch reason {
        case .ringOut?:
            guard let loser else { return "마지막 돌이 함께 나가 무승부예요" }
            return "\(loser) 돌이 모두 판 밖으로 나갔어요"
        case .timeout?: return loser.map { "\($0)이 차례를 세 번 넘겼어요" } ?? ""
        case .resign?: return loser.map { "\($0)이 기권했어요" } ?? ""
        case .abandoned?: return loser.map { "\($0)이 대결을 떠났어요" } ?? ""
        case .void?: return "판이 무효가 되어 판돈을 돌려줬어요"
        case .unknown?, nil: return ""
        }
    }

    // MARK: 규칙

    /// 규칙 다섯 줄(순서·뜻 고정 — SPEC §5.4). 시험이 번호로 집는다.
    static let rulesLines: [String] = [
        "돌 다섯 개를 내 쪽에 숨겨 놓아요 — 30초, 둘 다 놓으면 함께 보여요",
        "흑이 먼저 쏴요 — 흑백은 수락할 때 정해져요",
        "내 돌을 당겼다 놓으면 반대쪽으로 날아가요 — 한 수 30초",
        "판 밖으로 나간 돌은 빠져요 — 상대 돌을 모두 밀어내면 이겨요(마지막 돌이 함께 나가면 무승부)",
        "차례를 세 번 연달아 넘기면 져요 · 이기면 판돈만큼 더 받아요",
    ]
}

// MARK: - 아이콘 한 출처

/// 1:1 알까기 입구·배너·머리글·판 머리·미션 줄 아이콘(DF#3 — 뒤집기 `circle.lefthalf.filled` 와 겹치지 않는다).
/// 이 맥에서 실제로 풀리는 이름만 쓴다(없으면 대체).
enum AlkkagiEntryIcon {
    static let symbol = "circle.hexagongrid.fill"
    static let fallback = "circle.grid.2x2.fill"

    @MainActor
    static var resolved: String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : fallback
    }
}

// MARK: - 팝오버 배너

/// 팝오버의 **받은 1:1 알까기 신청 배너** — 길건너 배너 꼴(높이 92 — 자리는 T 가 잡는다, DF#40).
/// 받은 신청과 액션만 주입한다. 응답 상태와 만료 목록은 스토어가 관리한다.
struct AlkkagiInviteBanner: View {
    let invite: AlkkagiInvite
    let isBusy: Bool
    let serverNowMs: () -> Double
    let onAccept: () -> Void
    let onDecline: () -> Void
    var onOpen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: AlkkagiEntryIcon.resolved)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AlkkagiText.inviteBannerTitle(name: invite.opponent.displayName))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 3) {
                        if let stake = invite.stake {
                            Text(AlkkagiText.stakeTitle)
                            RubyIcon(size: 11)
                            Text("\(stake) · \(AlkkagiText.inviteBannerSubtitle)")
                        } else {
                            Text(AlkkagiText.inviteBannerSubtitle)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
                AlkkagiInviteBannerCountdown(expiresAtMs: invite.expiresAtMs, serverNowMs: serverNowMs)
            }
            HStack(spacing: 8) {
                AlkkagiInviteBannerButton(
                    title: isBusy ? AlkkagiText.responding : AlkkagiText.accept,
                    primary: true,
                    action: onAccept
                )
                .checkTooltip(AlkkagiText.acceptHelp)
                .disabled(isBusy)
                AlkkagiInviteBannerButton(title: AlkkagiText.decline, primary: false, action: onDecline)
                    .disabled(isBusy)
                if let onOpen {
                    AlkkagiInviteBannerButton(title: AlkkagiText.viewInvite, primary: false, action: onOpen)
                        .checkTooltip(AlkkagiText.viewInviteHelp)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.accent.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CheckTheme.accent.opacity(0.55), lineWidth: 1))
        )
    }
}

/// 서버 보정 시계는 이 잎에서만 읽고, 팝오버가 비활성이면 기존 공용 카운트다운을 멈춘다.
private struct AlkkagiInviteBannerCountdown: View {
    let expiresAtMs: Double
    let serverNowMs: () -> Double
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        TetrisDuelCountdownText(
            expiresAt: Date(timeIntervalSince1970: expiresAtMs / 1_000),
            isLive: controlActiveState != .inactive,
            now: { Date(timeIntervalSince1970: serverNowMs() / 1_000) }
        )
    }
}

private struct AlkkagiInviteBannerButton: View {
    let title: String
    let primary: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(primary ? Color.white : CheckTheme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(primary ? CheckTheme.accent : CheckTheme.accent.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(CheckTheme.accent.opacity(primary ? 0 : 0.45), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
    }
}
