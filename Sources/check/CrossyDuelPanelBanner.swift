import AppKit
import SwiftUI
import CheckCore

// MARK: - 1:1 길건너 — 문구 · 아이콘 · 창 밖 부품 (SPEC v1.3 §9.4 · v1.1 CC-27②)
//
// 맥 화면 문구는 **이 파일 한 곳**(`CrossyDuelText`)에 있다. 끝 사유 · 신청 결과 같은 안내 글자는 코어
// `CrossyDuelNoticeText` 한 곳이고 여기서는 받아 쓰기만 한다(같은 사실을 두 벌로 적지 않는다). 진단 어휘 금지.
// 창 밖 부품(팝오버 배너 `CrossyDuelInviteBanner` · 입구 아이콘 `CrossyDuelEntryIcon` · 사이드바 줄
// `MiniGameCrossyDuelEntryButton`)도 여기 둔다 — 꽂는 일(팝오버 자리 · 메뉴바 점 · 말풍선 · 사이드바 순서)은 통합 갈래(T)가
// 공용 접점 파일에서 한다(§9.5).

/// 1:1 길건너 화면 문구(순수 — 값으로 검증한다).
enum CrossyDuelText {
    /// 게임 이름 — 코어 한 곳(`CrossyDuelNoticeText.gameName`)에서 받는다. 13바이트라 Release 바이트 검사에 쓰지 마라.
    static let gameName = CrossyDuelNoticeText.gameName
    static let title = gameName
    static let subtitle = "100점에 먼저 닿으면 이겨요"
    /// 사이드바 도움말(SPEC §1 맥 문구).
    static let sidebarHelp = "100점에 먼저 닿으면 이기는 1:1 길건너 대결 창을 열어요"
    /// 메뉴바 점 보이스오버 사유(SPEC §1).
    static let dotReason = "1:1 길건너 신청"

    // ── 로비 ──
    static let usersTab = "상대 고르기"
    static let rankTab = "순위"
    static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    static let loadingUsers = "상대 목록을 불러오고 있어요"
    static let usersLoadFailed = CrossyDuelNoticeText.checkConnection
    static let reloadUsers = "다시 불러오기"
    static let challenge = "신청"
    static let needsUpdate = "앱 업데이트 필요"
    static let inMatch = "대결 중"
    static let working = "근무 중"
    static let focused = "집중 모드"

    static let stakeTitle = "판돈"
    /// 판돈 줄. 이기면 **순이익**(`DuelFee.winnerNet`) — 결과 카드의 루비 변화와 같은 숫자다.
    static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    /// 판 화면 머리글 칩(시안 그대로 "판돈 5 · 이기면 +5").
    static func stakeChip(_ stake: Int) -> String { "\(stakeTitle) \(stakeLine(stake))" }
    static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    static let stakePromptCaption = "판돈을 고르세요"
    static func stakePromptChosen(_ stake: Int) -> String { "\(stakeTitle) \(stakeLine(stake))" }
    static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 신청하기" }
    static let stakeShortfall = CheckCoreShared.shortfallNotice(need: nil, have: nil)

    static let incomingTitle = "받은 신청"
    static func incomingMore(_ count: Int) -> String { "외 \(count)건" }
    static func incomingFrom(_ name: String) -> String { "\(name)님의 신청" }
    static let outgoingTitle = "보낸 신청"
    static let noIncoming = "받은 신청이 없어요"
    static let accept = "수락"
    static let decline = "거절"
    static let cancel = "취소"

    static let recordTitle = "내 전적"
    static let howTitle = "이렇게 겨뤄요"
    /// 로비 오른쪽 열의 규칙 요약(결정 DEC:10-14 그대로).
    static let howLines: [String] = [
        "두 사람이 같은 길을 달려요",
        "죽으면 3초 뒤 그 줄에서 다시 서요",
        "3분이 지나면 점수가 높은 쪽이 이겨요",
    ]

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

    static func record(_ record: CrossyDuelRecord?) -> String {
        guard let record else { return "0승 0패 0무" }
        return self.record(wins: record.wins, losses: record.losses, draws: record.draws)
    }

    static func record(wins: Int, losses: Int, draws: Int) -> String { "\(wins)승 \(losses)패 \(draws)무" }
    static func points(_ value: Int) -> String { "승점 \(value >= 0 ? "+" : "")\(value)" }

    // ── 창 밖(배너 · 말풍선 · 알림) ──
    static func inviteBannerTitle(name: String) -> String { "\(name)님이 \(gameName) 대결을 신청했어요" }
    static let inviteBannerSubtitle = "1분 안에 응답하세요"
    static let acceptHelp = "수락하고 1:1 길건너 창을 열어요"
    static let viewInvite = "보기"
    static let viewInviteHelp = "1:1 길건너 창에서 이 신청을 봐요"
    static let someone = "누군가"

    /// 받은 신청 말풍선(3단 줄임 — 체스·테트리스와 같은 접기 규칙): 이름 있는 꼴 → 짧은 꼴 → 이름 없는 꼴.
    static func inviteBubbleText(name: String?, stake: Int) -> String {
        let shortName = OverlayMessageBubble.clippedName(displayName(name))
        let full = "\(shortName)님이 \(gameName) 대결을 신청했어요 · 루비 \(stake)"
        if OverlayMessageBubble.fitsCapsule(full) { return full }
        let short = "\(shortName)님의 \(gameName) 신청 · 루비 \(stake)"
        if OverlayMessageBubble.fitsCapsule(short) { return short }
        return "\(gameName) 대결 신청 · 루비 \(stake)"
    }

    /// 시작 알림(차례가 없는 게임이라 알림은 이 하나뿐이다).
    static let matchStarted = "1:1 길건너 대결이 시작됐어요"

    static func displayName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? someone : trimmed
    }

    // ── 판 화면 ──
    static let me = "나"
    static let opponentTitle = "상대"
    static let deathsTitle = "죽은 횟수"
    static func deathsLine(me: Int, opponent: Int) -> String { "나 \(me) · 상대 \(opponent)" }
    static let goalTitle = "목표"
    static func goalLine(_ goal: Int) -> String { "\(goal)점 먼저" }
    static let running = "달리는 중"
    static let ready = "준비 완료"
    static let notReady = "들어오는 중"
    static let finishedPresence = "대결 끝"
    /// 상대 last_seen 이 8초 넘음(`opponentQuiet`, SPEC §9.3).
    static let opponentQuiet = "상대 연결 확인 중"
    static let connectionTrouble = "연결 확인 중"
    static let waitingTitle = "상대를 기다리는 중"
    static let waitingAction = "창을 열어 두세요"
    static func waitingSubtitle(seconds: Int) -> String { "\(seconds)초 안에 둘 다 들어오면 시작해요" }
    static let otherDeviceSubtitle = "신청하거나 수락한 기기에서만 할 수 있어요"
    static let startingSoon = "곧 시작해요"
    /// 조작 안내(v1.1 CC-8 — 시안 두 줄).
    static let keysLine = "↑↓←→ · WASD · 스페이스"
    static let clickLine = "클릭 = 앞으로 한 칸"
    /// SPEC §9.3 한 줄 꼴(보이스오버).
    static var keysAccessibility: String { "\(keysLine) · 클릭 = 앞으로" }
    static let gameHint = "창을 가리거나 내려도 판은 계속 흘러가요"

    // 캔버스 겹(SPEC §9.3).
    static let goalWaiting = "100점! 판정 기다리는 중"
    static let timeWaiting = "시간 끝! 판정 기다리는 중"
    static let respawnCaption = "다시 서는 중"
    static let countdownCaption = "곧 시작해요"

    static let resign = "기권"
    static let confirmResign = "기권하기"
    static let keepPlaying = "계속하기"
    static let resignWarning = "기권하면 판돈을 잃어요"
    static let resignHelp = "기권하면 이번 판은 져요"
    static let backToLobby = "로비로"

    static func outcomeTitle(_ outcome: CrossyDuelOutcome?) -> String {
        switch outcome {
        case .win?: return "이겼어요"
        case .loss?: return "졌어요"
        case .draw?: return "비겼어요"
        case nil: return "대결이 끝났어요"
        }
    }

    /// 결과 카드 굳은 점수 "나 100 : 상대 87".
    static func finalScoreLine(me: Int, opponent: Int) -> String { "나 \(me) : 상대 \(opponent)" }

    /// 결과 카드 루비 줄(SPEC §9.3): 승 `+N` · 패 `−N` · 무 `0 · 판돈을 돌려받았어요`.
    static func rubyLine(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(-delta)" }
        return "0 · 판돈을 돌려받았어요"
    }

    /// 판 시계 글자(`m:ss`). 음수는 0 으로.
    static func clock(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// 겹 숫자(3 · 2 · 1) — 남은 초를 올림.
    static func countdownDigit(_ seconds: TimeInterval) -> String { String(max(1, Int(seconds.rounded(.up)))) }

    /// 결과 카드 '나' 숫자 — **Q3 답 (가)(v1.2 확정 · CC-4)**: goal 로 **진** 판만 `max(final.me, 로컬 점수)`,
    /// 그 밖은 `final.me`. 기록·순위는 서버 값 그대로다(이 숫자는 결과 카드에만 쓴다).
    static func resultMyScore(finalMe: Int?, local: Int?, reason: CrossyDuelEndReason?, outcome: CrossyDuelOutcome?) -> Int {
        let server = finalMe ?? local ?? 0
        guard reason == .goal, outcome == .loss, let local else { return server }
        return max(server, local)
    }
}

// MARK: - 아이콘 한 출처

/// 1:1 길건너 입구·배너·머리글 아이콘. 이 맥에서 실제로 풀리는 이름만 쓴다(없으면 대체).
/// 경주 트랙 끝(100) 깃발도 **같은 그림**이다(SPEC §9.2).
enum CrossyDuelEntryIcon {
    static let symbol = "flag.checkered"
    static let fallbackSymbol = "flag.fill"

    @MainActor
    static var resolved: String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : fallbackSymbol
    }
}

// MARK: - 팝오버 배너

/// 팝오버 배너의 남은 초 — **잎**(팝오버가 닫혀 창이 비활성이면 멈춘다 — 체스·테트리스 배너와 같은 규약).
struct CrossyDuelInviteBannerCountdown: View {
    let invite: CrossyDuelInvite
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        TetrisDuelCountdownText(expiresAt: invite.expiresAt, isLive: controlActiveState != .inactive)
    }
}

/// 팝오버의 **받은 1:1 길건너 신청 배너**. 테트리스 배너(`TetrisDuelInviteBanner`)와 모양·높이가 같다(높이 92 — T 가 자리를 잡는다).
struct CrossyDuelInviteBanner: View {
    let invite: CrossyDuelInvite
    let onAccept: () -> Void
    let onDecline: () -> Void
    var onOpen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: CrossyDuelEntryIcon.resolved)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CrossyDuelText.inviteBannerTitle(name: CrossyDuelText.displayName(invite.peer.displayName)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 3) {
                        Text(CrossyDuelText.stakeTitle)
                        RubyIcon(size: 11)
                        Text("\(invite.stake) · \(CrossyDuelText.inviteBannerSubtitle)")
                    }
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
                CrossyDuelInviteBannerCountdown(invite: invite)
            }
            HStack(spacing: 8) {
                CrossyDuelBannerButton(title: CrossyDuelText.accept, primary: true, action: onAccept)
                    .checkTooltip(CrossyDuelText.acceptHelp)
                CrossyDuelBannerButton(title: CrossyDuelText.decline, primary: false, action: onDecline)
                if let onOpen {
                    CrossyDuelBannerButton(title: CrossyDuelText.viewInvite, primary: false, action: onOpen)
                        .checkTooltip(CrossyDuelText.viewInviteHelp)
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

private struct CrossyDuelBannerButton: View {
    let title: String
    let primary: Bool
    let action: () -> Void

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
    }
}

// MARK: - 미니게임 사이드바 줄

/// 미니게임 사이드바 '같이 하기' 일곱째 줄(SPEC §9.5 #18 — 꽂는 일은 T). 마작 줄과 같은 꼴.
struct MiniGameCrossyDuelEntryButton: View {
    static let title = CrossyDuelText.gameName
    static let help = CrossyDuelText.sidebarHelp

    var hasInvite: Bool = false
    let action: () -> Void

    var body: some View {
        MiniGameSidebarRow(title: Self.title, icon: CrossyDuelEntryIcon.resolved, tint: CheckTheme.accent, opensWindow: true,
                           hasInvite: hasInvite, help: Self.help, action: action)
    }
}
