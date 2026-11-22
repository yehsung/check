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
    package static let placingHelpPractice = "파란 칸에 돌 5개를 놓거나 옮겨 주세요. 시간이 끝나면 남은 돌은 자동으로 놓여요."
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

// MARK: - 안내(폰 1.0.19 — 맥 0.3.86 `AlkkagiGuideText` · C안의 폰 짝)
//
// 대표 11-10 "알까기 어디다 돌 둬야되는지 판 구분도 별로 안되어있고 어떻게 할지 유도해주는게 너무 약해. 뭘 하라는건지 모르겠어"
// → 맥 #d_cjxnVZpLHWw5 "C안" → 폰 대표 #d_xygj8oZRFlfH "추천안대로 한 판(1.0.19)에 전부"(5번 알까기 안내).
// 맥과 같은 글자다. 다른 것은 손짓 꼬리 하나 — 맥 "Esc로 취소" 자리가 폰은 "돌 위로 되돌리면 취소"(1.0.18 손짓 안내와 같은 말 — 1.0.19 에 상태 글은 전부 이 묶음으로 옮겼다).
package enum AlkkagiPhoneGuideText {
    /// 판 위 '아래 · 위' — 판은 돌리지 않는다(흑은 아래, 백은 위).
    package static func sideWord(_ side: AlkkagiGame.Player) -> String { side == .black ? "아래" : "위" }

    /// 숨겨 놓기 · 판 가운데 띠.
    package static func band(side: AlkkagiGame.Player, placed: Int) -> String {
        "내 진영(\(sideWord(side)) 파란 칸)에 돌 5개를 놓으세요 · \(placed)/5"
    }

    /// 숨겨 놓기 · 상태 줄. `player` 는 연습 판(한 폰 둘이)에서만 — 흑 · 백 차례를 글에 넣는다.
    package static func placing(side: AlkkagiGame.Player, placed: Int, player: AlkkagiGame.Player?) -> String {
        let body = "\(sideWord(side)) 파란 칸에 \(player == nil ? "내 " : "")돌 5개를 놓으세요 (\(placed)/5)"
        return player.map { "\(AlkkagiPhoneText.stoneTitle($0)) 차례 — \(body)" } ?? body
    }

    package static let placedWaiting = "준비 완료 — 상대가 놓기를 기다려요"
    package static let placeRejected = "파란 칸 안에, 다른 돌과 겹치지 않게 놓아 주세요"

    package static func opponentTurn(_ name: String) -> String { "\(AlkkagiPhoneText.displayName(name))님이 쏠 차례예요 — 기다려 주세요" }

    /// 폰 취소 손짓(맥 "Esc로 취소" 자리).
    package static let cancelTail = "돌 위로 되돌리면 취소"

    /// 쏘기 차례 · 상태 줄. 첫 수(흑)는 힘 60% 를 함께 말한다(선후 맞춤).
    package static func aiming(player: AlkkagiGame.Player?, holding: Bool, firstShotLimited: Bool) -> String {
        if holding {
            return firstShotLimited ? "첫 수는 힘 60%까지 · 놓으면 반대쪽으로 날아가요 · \(cancelTail)"
                : "놓으면 반대쪽으로 날아가요 · \(cancelTail)"
        }
        let who = player.map { "\(AlkkagiPhoneText.stoneTitle($0)) 차례" } ?? "내 차례"
        return "\(who) — \(player == nil ? "내 " : "")돌을 뒤로 당겼다 놓으세요\(firstShotLimited ? " (첫 수는 힘 60%까지)" : "")"
    }

    /// 손 안내 말풍선.
    package static let handHint = "뒤로 당겼다 놓기"
    /// 판 위 진영 이름표.
    package static let mineZone = "내 진영"
    package static let theirZone = "상대 진영"
}

/// 처음 한 번 따라 하기 — 알까기 화면을 처음 열 때 로비 위에 한 번(시간이 흐르지 않는 곳). [알겠어요]로 닫으면 다시 저절로 안 뜬다.
/// 맥 `AlkkagiFirstTimeCoach` 와 같은 세 줄 · 같은 낱말.
package enum AlkkagiPhoneFirstTimeCoach {
    /// '봤음' 기억 키(앱 표준 스위트 — 화면의 `@AppStorage`).
    package static let seenKey = "alkkagi.firstTimeCoachSeen"
    package static let title = "처음 하는 알까기"
    package static let done = "알겠어요"
    package static let steps: [(icon: String, title: String, detail: String)] = [
        ("hand.tap.fill", "파란 칸(내 진영)에 내 돌 5개를 숨겨 놓아요", "상대는 둘 다 놓을 때까지 못 봐요 · 30초"),
        ("hand.draw.fill", "내 차례가 오면 내 돌을 뒤로 당겼다 놓아요", "당긴 반대쪽으로 날아가요 · 한 수 30초"),
        ("arrow.up.right.circle.fill", "상대 돌을 판 밖으로 모두 밀어내면 이겨요", "내 돌도 밖으로 나가면 빠져요"),
    ]

    /// 띄울까: 로비가 보이고 · 아직 안 봤을 때만(판 · 연습 · 관전 중엔 시간이 흐르니 로비에서만 — 화면이 로비일 때만 그린다).
    package static func shows(seen: Bool) -> Bool { !seen }
}
