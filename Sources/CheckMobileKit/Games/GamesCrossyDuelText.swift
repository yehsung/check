import CheckCore
import Foundation

// 1:1 길건너 폰 문구(1.0.18 — 대표 지시 11-10 "맥만 구현해놓고 폰 구현 안된거 … 다 구현해서 넣자" · 루비 그대로 #d_t103CxfPGinB).
// 맥 0.3.78 `CrossyDuelText`(Sources/check/CrossyDuelPanelBanner.swift)와 같은 글자다 — 폰에서 다른 것은 조작 안내뿐이다(키 대신 쓸기 · 탭).
// 판정 · 끝난 까닭 문구는 코어 `CrossyDuelNoticeText` 한 곳에서 받는다.
package enum CrossyDuelPhoneText {
    package static let title = CrossyDuelNoticeText.gameName
    package static let cardSubtitle = "100점에 먼저 닿으면 이겨요"
    package static let cardOpenHint = "1:1 길건너 로비를 열어요"
    package static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    package static let usersTitle = "상대 고르기"
    package static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    package static let loadingUsers = "상대 목록을 불러오고 있어요"
    package static let usersLoadFailed = CrossyDuelNoticeText.checkConnection
    package static let reloadUsers = MobileLoadText.retry
    package static let challenge = "신청"
    package static let needsUpdate = "앱 업데이트 필요"
    package static let inMatch = "대결 중"
    package static let working = "근무 중"
    package static let focused = "집중 모드"
    package static let available = "대결할 수 있어요"
    package static let stakeTitle = "판돈"
    package static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    package static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    package static let stakePromptCaption = "판돈을 고르세요"
    package static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 신청하기" }
    package static let stakeShortfall = CheckCoreShared.shortfallNotice(need: nil, have: nil)
    package static let incomingTitle = "받은 신청"
    package static func incomingFrom(_ name: String) -> String { "\(name)님의 신청" }
    package static let outgoingTitle = "보낸 신청"
    package static func outgoingTo(_ name: String) -> String { "\(name)님에게 보낸 신청" }
    package static let accept = "수락"
    package static let decline = "거절"
    package static let cancel = "취소"
    package static let recordTitle = "내 전적"
    package static let howTitle = "이렇게 겨뤄요"
    package static let howLines: [String] = [
        "두 사람이 같은 길을 달려요",
        "죽으면 3초 뒤 그 줄에서 다시 서요",
        "3분이 지나면 점수가 높은 쪽이 이겨요",
    ]
    package static let rankTitle = "순위"
    package static let rankLoading = "순위를 불러오고 있어요"
    package static let rankEmpty = "아직 순위가 없어요"
    package static let rankHelp = "승점 = 승 − 패"
    package static func record(_ record: CrossyDuelRecord?) -> String {
        guard let record else { return "—" }
        return "\(record.wins)승 \(record.losses)패 \(record.draws)무"
    }
    package static func points(_ value: Int) -> String { "승점 \(value >= 0 ? "+" : "")\(value)" }
    package static func remaining(_ seconds: Int) -> String { "\(max(0, seconds))초 남음" }

    // 판
    package static let me = "나"
    package static let opponentTitle = "상대"
    package static func deathsLine(me: Int, opponent: Int) -> String { "죽은 횟수 나 \(me) · 상대 \(opponent)" }
    package static func goalLine(_ goal: Int) -> String { "\(goal)점 먼저" }
    package static let waitingTitle = "상대를 기다리는 중"
    package static func waitingSubtitle(seconds: Int) -> String { "\(seconds)초 안에 둘 다 들어오면 시작해요" }
    package static let otherDeviceSubtitle = "신청하거나 수락한 기기에서만 할 수 있어요"
    /// 폰 조작 안내(맥 `keysLine` · `clickLine` 의 폰 꼴) — 혼자 하는 길건너와 같은 손짓이다.
    package static let touchLine = "쓸어서 그 방향으로 한 칸 · 탭하면 앞으로 한 칸"
    package static let goalWaiting = "100점! 판정 기다리는 중"
    package static let timeWaiting = "시간 끝! 판정 기다리는 중"
    package static let opponentQuiet = "상대 연결 확인 중"
    package static let resign = "기권"
    package static let confirmResign = "기권하기"
    package static let keepPlaying = "계속하기"
    package static let resignWarning = "기권하면 판돈을 잃어요"
    package static let backToLobby = "로비로"
    package static func outcomeTitle(_ outcome: CrossyDuelOutcome?) -> String {
        switch outcome {
        case .win?: return "이겼어요"
        case .loss?: return "졌어요"
        case .draw?: return "비겼어요"
        case nil: return "대결이 끝났어요"
        }
    }
    package static func finalScoreLine(me: Int, opponent: Int) -> String { "나 \(me) : 상대 \(opponent)" }
    package static func rubyLine(_ delta: Int) -> String { delta > 0 ? "+\(delta)" : (delta < 0 ? "\(delta)" : "±0") }
    package static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    package static func countdownDigit(_ seconds: TimeInterval) -> String { String(max(1, Int(seconds.rounded(.up)))) }

    /// 결과 루비 변화 — 서버 값이 있으면 그것, 없으면 판돈 규칙(맥 `CrossyDuelResultCard.delta` 와 같다).
    package static func rubyDelta(_ match: CrossyDuelMatchState) -> Int {
        if let rubyDelta = match.rubyDelta { return rubyDelta }
        switch match.outcome {
        case .win?: return DuelFee.winnerNet(stake: match.stake)
        case .loss?: return -match.stake
        default: return 0
        }
    }

    /// 로비 상대 줄의 아래 줄 · 단추 글자.
    package static func userStatus(_ user: CrossyDuelUser) -> (subtitle: String, canChallenge: Bool) {
        if !user.isCapable { return (needsUpdate, false) }
        if user.inMatch { return (inMatch, false) }
        if user.isFocused { return (focused, false) }
        return (user.isWorking ? working : available, true)
    }
}

/// 캔버스 위 겹 하나(맥 `CrossyDuelCanvasOverlay` 와 같은 우선순위: 결과 > 판정 기다림 > 부활 카운트 > 시작 카운트다운).
package enum CrossyDuelPhoneOverlay: Equatable {
    case result(CrossyDuelOutcome?)
    case waiting(goal: Bool)
    case respawn(String)
    case countdown(String)

    package static func resolve(phase: CrossyDuelPhase, isFinished: Bool, outcome: CrossyDuelOutcome?,
                                snapshot: CrossyDuelRaceSnapshot?) -> CrossyDuelPhoneOverlay? {
        if isFinished || phase == .finished { return .result(outcome) }
        guard let snapshot, phase == .countdown || phase == .playing else { return nil }
        let reachedGoal = snapshot.myScore >= snapshot.goal
        let timeUp = phase == .playing && (snapshot.remaining.map { $0 <= 0 } ?? false)
        if snapshot.waitingForResult || snapshot.frozen || reachedGoal || timeUp { return .waiting(goal: reachedGoal) }
        if let respawn = snapshot.respawnIn, respawn > 0 { return .respawn(CrossyDuelPhoneText.countdownDigit(respawn)) }
        if let countdown = snapshot.countdown, countdown > 0 { return .countdown(CrossyDuelPhoneText.countdownDigit(countdown)) }
        return nil
    }
}
