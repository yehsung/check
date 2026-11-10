import CheckCore
import Foundation

// 1:1 알까기 폰 문구(1.0.18 — 대표 판 나누기 답 "한 판에 전부" #d_xB6BJcn2nsCq · 루비 판돈 그대로 #d_t103CxfPGinB).
// 맥 0.3.82 `AlkkagiText`(Sources/check/AlkkagiInviteBanner.swift)와 같은 글자다 — 폰에서 다른 것은 손짓 안내뿐이다(끌기 · 놓기).
// 게임 이름 · 판정 · 끝난 까닭 문구는 코어 `AlkkagiNoticeText` 한 곳에서 받는다. 낱말은 '대결'·'신청'(대전·초대 금지).
// 루비는 글자로 "루비 N" 이고 그림은 `RubyIcon` 이다(💎 글자 금지).
package enum AlkkagiPhoneText {
    // MARK: 이름 · 입구

    package static let title = AlkkagiNoticeText.gameName
    /// 게임 탭 카드 아이콘 — 맥 `AlkkagiEntryIcon.symbol` 과 같은 이름(일일 미션 줄 `MeText.dailyMissionIcon(game: "alkkagi")` 도 같다).
    package static let entrySymbol = "circle.hexagongrid.fill"
    /// 카드 부제(맥 머리글 부제와 같은 사실 — 서버 규칙 30초 두 개).
    package static let cardSubtitle = "숨겨 놓기 30초 · 흑 선공 · 한 수 30초"
    package static let cardOpenHint = "1:1 알까기 로비를 열어요"

    // MARK: 로비

    package static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    package static let usersTitle = "상대 고르기"
    package static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    package static let loadingUsers = "상대 목록을 불러오고 있어요"
    package static let usersLoadFailed = AlkkagiNoticeText.checkConnection
    package static let reloadUsers = MobileLoadText.retry
    package static let challenge = "도전"
    package static let needsUpdate = "앱 업데이트 필요"
    package static let inMatch = "대결 중"
    package static let working = "근무 중"
    package static let focused = "집중 모드"
    package static let available = "대결할 수 있어요"
    package static let unavailable = AlkkagiNoticeText.unavailable

    package static let stakeTitle = "판돈"
    package static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    package static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    package static let stakePromptCaption = "판돈을 고르세요"
    package static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 도전하기" }
    package static let stakeShortfall = CheckCoreShared.shortfallNotice(need: nil, have: nil)

    package static let incomingTitle = "받은 신청"
    package static func incomingFrom(_ name: String) -> String { "\(displayName(name))님의 신청" }
    package static let outgoingTitle = "보낸 신청"
    package static func outgoingTo(_ name: String) -> String { "\(displayName(name))님에게 보낸 신청" }
    package static let accept = "수락"
    package static let decline = "거절"
    package static let cancel = "취소"
    package static func remaining(_ seconds: Int) -> String { "\(max(0, seconds))초 남음" }

    package static let recordTitle = "내 전적"
    package static let liveTitle = "지금 대결 중"
    package static let noLive = "지금 진행 중인 대결이 없어요"
    package static let watch = "관전"
    package static let leaveWatch = "나가기"
    package static func liveLine(_ match: AlkkagiLiveMatch) -> String {
        "\(displayName(match.black.displayName)) vs \(displayName(match.white.displayName))"
    }
    package static func liveDetail(_ match: AlkkagiLiveMatch) -> String {
        var parts: [String] = []
        if let stake = match.stake { parts.append("\(stakeTitle) \(stake)") }
        parts.append("\(match.shotCount)수")
        if match.watchers > 0 { parts.append("\(match.watchers)명 관전") }
        return parts.joined(separator: " · ")
    }

    package static let rankTitle = "알까기 순위"
    package static let rankHelp = "승점 = 승 − 패"
    package static let rankLoading = "순위를 불러오고 있어요"
    package static let rankEmpty = "아직 순위가 없어요"
    package static let rankSoon = "순위는 곧 열려요"

    package static func record(_ record: AlkkagiRecord?) -> String {
        guard let record else { return "0승 0패 0무" }
        return "\(record.wins)승 \(record.losses)패 \(record.draws)무"
    }
    package static func points(_ value: Int) -> String { "승점 \(value >= 0 ? "+" : "")\(value)" }

    // MARK: 연습(로비에서만 — 맥 [연습하기] 와 같은 뜻)

    package static let practiceButton = "연습하기"
    package static let practiceHelp = "루비·전적 없이 한 폰에서 둘이 번갈아 연습해요"
    package static let practiceTitle = "알까기 연습"
    package static let practiceSubtitle = "연습 판 · 루비·전적에 남지 않아요"
    package static let practiceRestart = "새 판"

    // MARK: 규칙(맥 `AlkkagiText.rulesLines` 와 같은 다섯 줄 — 순서 · 뜻 고정)

    package static let rulesTitle = "이렇게 겨뤄요"
    package static let rulesLines: [String] = [
        "돌 다섯 개를 내 쪽에 숨겨 놓아요 — 30초, 둘 다 놓으면 함께 보여요",
        "흑이 먼저 쏴요 — 흑백은 수락할 때 정해져요",
        "내 돌을 당겼다 놓으면 반대쪽으로 날아가요 — 한 수 30초",
        "판 밖으로 나간 돌은 빠져요 — 상대 돌을 모두 밀어내면 이겨요(마지막 돌이 함께 나가면 무승부)",
        "차례를 세 번 연달아 넘기면 져요 · 이기면 판돈만큼 더 받아요",
    ]

    // MARK: 판

    package static let myTurn = "내 차례예요"
    package static func opponentTurn(name: String) -> String { "\(displayName(name))님 차례예요" }
    package static let waitBusy = "잠시만 기다려 주세요"
    package static let rolling = "돌이 멈추면 차례가 바뀌어요"
    package static let placingHelpOnline = "30초 동안 동시에 숨겨 놓아요. 둘 다 준비하거나 시간이 끝날 때까지 상대 돌은 보이지 않아요."
    package static let placingHelpPractice = "내 영역에 돌 5개를 놓거나 옮겨 주세요. 시간이 끝나면 남은 돌은 자동으로 놓여요."
    package static let placingReadyWaiting = "준비 완료 · 상대를 기다리고 있어요"
    package static func placingMine(_ player: AlkkagiGame.Player) -> String { "\(stoneTitle(player)) 숨겨 놓는 중 · 내 영역을 눌러 주세요" }
    package static func placingPractice(_ player: AlkkagiGame.Player) -> String { "\(stoneTitle(player)) 놓는 중 · 내 영역을 눌러 놓아요" }
    package static func aimHint(_ player: AlkkagiGame.Player) -> String { "\(stoneTitle(player)) 차례 — 내 돌을 눌러 뒤로 당겨 보세요" }
    /// 폰 손짓 안내(맥 "놓으면 발사해요 · Esc로 취소" 의 폰 꼴 — Esc 가 없다. 돌 위로 되돌려 놓으면 힘이 0 이라 쏘지 않는다).
    package static let aimRelease = "놓으면 날아가요 · 돌 위로 되돌리면 취소"
    /// 판의 첫 수(흑)는 힘이 60%(당김 81)까지 — 선후 맞춤(대표 #d_5KuZ3DGTw6BY · 맥 0.3.84 · 서버 20261112150000 이 저장 전에 같은 값으로 줄인다).
    /// 앞 줄은 맥 `AlkkagiLocalModel.status` 와 같은 글이다.
    package static let firstShotHint = "첫 수는 힘이 60%까지예요 — 돌을 뒤로 당겨 보세요"
    package static let firstShotRelease = "첫 수는 힘 60%까지 · 놓으면 날아가요 · 돌 위로 되돌리면 취소"
    package static let placementInvalid = "내 영역 안에서 돌이 겹치지 않게 놓아 주세요"
    package static func placementDone(_ placed: Int) -> String { "배치 완료 (\(placed)/5)" }
    package static let readyDone = "준비 완료"
    package static func power(_ value: Double) -> String { "힘 \(Int((min(1, max(0, value)) * 100).rounded(.down)))%" }
    package static func stonesLeft(_ count: Int) -> String { "돌 \(count)개" }
    package static func shots(_ count: Int) -> String { "\(count)수" }
    package static func missedLine(_ missed: Int, of forfeitAfter: Int) -> String { "넘긴 차례 \(missed)/\(forfeitAfter)" }
    package static let resign = AlkkagiNoticeText.resign
    package static let confirmResign = AlkkagiNoticeText.confirmResign
    package static let keepPlaying = AlkkagiNoticeText.keepPlaying
    package static func resignWarning(stake: Int?) -> String {
        stake == nil ? AlkkagiNoticeText.resignHelp : AlkkagiNoticeText.resignWarning
    }
    package static let backToLobby = "로비로"
    package static let leaveKeepsMatch = "화면을 나가도 대결은 계속돼요"

    package static func outcomeTitle(_ outcome: AlkkagiOutcome?) -> String {
        switch outcome {
        case .win?: return "이겼어요"
        case .loss?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대결이 끝났어요"
        }
    }

    /// 결과 루비 줄: 승 `+N` · 패 `−N` · 무(무효 포함) `0 · 판돈을 돌려받았어요`(맥과 같은 글자).
    package static func rubyLine(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(-delta)" }
        return "0 · 판돈을 돌려받았어요"
    }

    /// 연습 판 결과(흑백 기준 — 연습엔 '나'가 없다).
    package static func practiceResult(_ result: AlkkagiGame.Result?) -> String {
        switch result {
        case .winner(let player)?: return "\(stoneTitle(player)) 승리!"
        case .draw?: return "멋진 한 판, 무승부!"
        case nil: return "한 판 끝!"
        }
    }

    // MARK: 관전(3인칭 — 내 기준 문장을 남의 판에 쓰지 않는다)

    package static let watchLoading = "판을 불러오고 있어요"
    package static let watchPlacing = "두 사람이 돌을 숨겨 놓는 중이에요"
    package static let watchRolling = "돌이 멈추면 차례가 바뀌어요"
    package static func stoneName(_ player: AlkkagiGame.Player) -> String { player == .black ? "흑" : "백" }
    package static func stoneTitle(_ player: AlkkagiGame.Player) -> String { player == .black ? "흑돌" : "백돌" }
    package static func watchTurn(_ player: AlkkagiGame.Player) -> String { "\(stoneName(player)) 차례" }
    package static func watchOutcome(_ result: AlkkagiMatchResult?) -> String {
        switch result {
        case .black?: return "흑 승리"
        case .white?: return "백 승리"
        case .draw?: return "무승부로 끝났어요"
        case .unknown?, nil: return "대결이 끝났어요"
        }
    }
    package static func watchEndReason(_ reason: AlkkagiEndReason?, result: AlkkagiMatchResult?) -> String {
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
    package static func watchHeadline(_ watch: AlkkagiWatchState) -> String {
        switch watch.phase {
        case .placing: return watchPlacing
        case .rolling: return watchRolling
        case .aiming: return watchTurn(watch.currentPlayer)
        case .finished: return watchOutcome(watch.result)
        case .unknown: return watchLoading
        }
    }
    /// 판 위에 남은 돌 수(나간 돌만 뺀다 — 숨긴 배치 중에도 다섯).
    package static func remaining(_ stones: [AlkkagiGame.Stone], _ player: AlkkagiGame.Player) -> Int {
        max(0, 5 - stones.filter { $0.owner == player && $0.isOut }.count)
    }

    // MARK: 도움

    package static let someone = "누군가"
    package static func displayName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? someone : trimmed
    }

    /// 로비 상대 줄의 아래 줄 · 단추가 설 수 있는가(맥 `AlkkagiOpponentRow.statusLine` 과 같은 서열).
    package static func userStatus(_ user: AlkkagiLobbyUser) -> (subtitle: String, canChallenge: Bool) {
        if !user.isCapable { return (needsUpdate, false) }
        if user.inMatch { return (inMatch, false) }
        if user.isFocused { return (focused, false) }
        return (user.isWorking ? working : available, true)
    }
}
