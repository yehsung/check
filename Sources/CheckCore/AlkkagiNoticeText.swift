import Foundation

// 1:1 알까기 사용자 문구 — **코어 한 곳**(SPEC v1.1 §4.4 · VC-17). 맥 `AlkkagiText.gameName` 은 이 값을 받는다.
// 출처 하나 = 길건너 `CrossyDuelNoticeText` — 글자 그대로 옮기고 게임 이름만 바꿨다(낱말은 '대결'·'신청' — '대전'·'초대' 금지).
// 알까기에만 있는 `forbidden` 은 함수별로 접는다(취소 · 응답 · 한 수). 진단 어휘(세션·서버·RPC) 금지.

package nonisolated enum AlkkagiNoticeText {
    /// 게임 이름(SPEC §1 맥 문구). 13바이트라 Release 바이트 검사에 쓰지 마라(메모리 short-korean-literals-vanish-in-release).
    package static let gameName = "1:1 알까기"

    package static let tryAgain = "잠시 후 다시 시도해 주세요"
    package static let checkConnection = "연결을 확인하고 다시 시도해 주세요"
    package static let updateMine = "앱을 업데이트해야 대결할 수 있어요"
    package static let signInAgain = "다시 로그인해 주세요"
    package static let inviteTimedOut = "상대가 응답하지 않았어요"
    /// 보낸 신청이 만료 전에 사라졌다(거절·취소·상대가 다른 대결을 시작함).
    package static let inviteDeclined = "상대가 신청을 받지 않았어요"
    package static let finishedInvite = "이미 끝난 신청이에요"
    package static let finishedMatch = "이미 끝난 대결이에요"
    package static let busy = "이미 진행 중인 대결이 있어요"
    package static let targetBusy = "상대가 다른 대결 중이에요"
    /// `target_outdated` — 상대 앱이 이 게임을 모른다. 내 availability 는 바꾸지 않는다(DF#29).
    package static let targetOutdated = "상대 앱이 1:1 알까기를 아직 몰라요"
    /// 서버에 v2 가 아직 없다 · 문이 닫혔다(`.serverMissing`, VC-8).
    package static let unavailable = "1:1 알까기는 곧 열려요"
    /// `forbidden`(한 수 — 내 차례 아님).
    package static let notYourTurn = "상대 차례예요"

    // MARK: 기권 확인 줄(U 가 쓴다 — 길건너 CK/CrossyDuelPanelBanner.swift:144-148 꼴)

    package static let resign = "기권"
    package static let confirmResign = "기권하기"
    package static let keepPlaying = "계속하기"
    /// 판돈 판의 확인 단계 경고.
    package static let resignWarning = "기권하면 판돈을 잃어요"
    /// 옛 판(판돈 nil)의 확인 단계 경고.
    package static let resignHelp = "기권하면 이번 판은 져요"

    /// 신청 결과. 근무 조건은 없다 — 클라가 근무를 보고 미리 막는 선게이트를 만들지 마라.
    /// - Parameter doorOpen: `unsupported_client` 봉투의 `door_open`. false 면 '곧 열려요'(내 앱 탓이 아니다, VC-8).
    package static func challenge(_ status: AlkkagiRPCStatus, need: Int? = nil, have: Int? = nil,
                                  doorOpen: Bool? = nil) -> String {
        switch status {
        case .ok: return "신청을 보냈어요"
        case .invalid: return "신청할 수 없는 상대예요"
        case .blackout: return "지금은 조용한 기간이라 신청할 수 없어요"
        case .targetFocused: return "상대가 집중 모드라 신청할 수 없어요"
        case .targetOutdated: return targetOutdated
        case .busy: return busy
        case .targetBusy: return targetBusy
        case .alreadyPending: return "이미 보낸 신청이 있어요"
        case .insufficient: return CheckCoreShared.shortfallNotice(need: need, have: have)
        case .unsupportedClient where doorOpen == false: return unavailable
        default: return common(status)
        }
    }

    /// 취소 결과. `forbidden`(신청자 아님)은 실제로는 수락과 엇갈린 취소다 — 끝난 신청으로 접는다(VC-13).
    package static func cancel(_ status: AlkkagiRPCStatus) -> String {
        switch status {
        case .ok: return "신청을 취소했어요"
        case .notFound, .notPending, .expired, .stale, .forbidden: return finishedInvite
        default: return common(status)
        }
    }

    /// 수락·거절 결과. **수락 성공은 판이 곧바로 열리므로 말하지 않는다**(nil).
    /// `forbidden`(받는 사람 아님 · 숨김 · 차단)은 "받을 수 없는 신청이에요".
    package static func respond(
        accept: Bool, _ status: AlkkagiRPCStatus, side: String? = nil, need: Int? = nil, have: Int? = nil,
        doorOpen: Bool? = nil
    ) -> String? {
        switch status {
        case .ok: return accept ? nil : "신청을 거절했어요"
        case .notFound, .notPending: return finishedInvite
        case .expired: return "신청 시간이 지났어요"
        case .invalid, .forbidden: return "받을 수 없는 신청이에요"
        case .busy: return busy
        case .targetBusy: return targetBusy
        case .targetOutdated: return targetOutdated
        case .insufficient:
            if side == "challenger" { return "상대의 루비가 모자라요" }
            return CheckCoreShared.shortfallNotice(need: need, have: have)
        case .unsupportedClient where doorOpen == false: return unavailable
        default: return common(status)
        }
    }

    /// 한 수(놓기 · 준비 · 쏘기) 결과. ok · stale 은 실려 온 state 가 답한다(nil).
    package static func move(_ status: AlkkagiRPCStatus) -> String? {
        switch status {
        case .ok, .stale: return nil
        case .forbidden: return notYourTurn
        case .notActive, .notFound: return finishedMatch
        case .rateLimited: return tryAgain
        default: return common(status)
        }
    }

    /// 기권 결과. 성공은 결과 카드가 말한다(nil).
    package static func resign(_ status: AlkkagiRPCStatus) -> String? {
        switch status {
        case .ok: return nil
        case .notActive, .notFound: return finishedMatch
        default: return common(status)
        }
    }

    /// 결과 카드의 사유 한 줄(**내 기준**). 사유를 모르면 빈 문자열.
    /// `abandoned` 는 표에 두지만 cascade 로 판이 지워져 화면에 닿지 않는다(§3.6 · VC-16).
    package static func endReason(_ reason: AlkkagiEndReason?, outcome: AlkkagiOutcome?) -> String {
        guard let reason else { return "" }
        switch reason {
        case .ringOut:
            switch outcome {
            case .win: return "상대 돌을 모두 판 밖으로 밀어냈어요"
            case .loss: return "내 돌이 모두 판 밖으로 나갔어요"
            case .draw, nil: return "마지막 돌이 함께 나가 무승부예요"
            }
        case .timeout:
            return outcome == .win ? "상대가 차례를 세 번 넘겼어요" : "차례를 세 번 넘겨 졌어요"
        case .resign:
            return outcome == .win ? "상대가 기권했어요" : "기권했어요"
        case .abandoned:
            return outcome == .win ? "상대가 떠났어요" : "대결을 떠났어요"
        case .void:
            return "판이 무효가 되어 판돈을 돌려받았어요"
        case .unknown:
            return ""
        }
    }

    /// 놓친 차례 경고(내가 1번 이상 놓쳤을 때). 남은 횟수 = `forfeitAfter − mine`. 경고가 아니면 nil.
    package static func missedTurn(mine: Int, forfeitAfter: Int) -> String? {
        let left = forfeitAfter - mine
        guard mine >= 1, left >= 1 else { return nil }
        switch left {
        case 1: return "시간이 지나 차례가 넘어갔어요 · 한 번 더 넘기면 져요"
        case 2: return "시간이 지나 차례가 넘어갔어요 · 두 번 더 넘기면 져요"
        default: return "시간이 지나 차례가 넘어갔어요 · \(left)번 더 넘기면 져요"
        }
    }

    package static func common(_ status: AlkkagiRPCStatus) -> String {
        switch status {
        case .unsupportedClient: return updateMine
        case .notSignedIn: return signInAgain
        default: return tryAgain
        }
    }
}
