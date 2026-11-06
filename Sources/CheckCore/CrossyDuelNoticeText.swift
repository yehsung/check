import Foundation

// 1:1 길건너 사용자 문구 — **코어 한 곳**(SPEC v1.3 §8.3 · §9.4 · v1.1 CC-27①). 맥 `CrossyDuelText.gameName` 은 이 값을 받는다.
// 공용 status 줄은 테트리스 `TetrisDuelNoticeText` 글자 그대로이고 게임 이름만 바꿨다. 진단 어휘(세션·서버·RPC) 금지.

package nonisolated enum CrossyDuelNoticeText {
    /// 게임 이름(SPEC §1 맥 문구). 13바이트라 Release 바이트 검사에 쓰지 마라(메모리 short-korean-literals-vanish-in-release).
    package static let gameName = "1:1 길건너"

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
    /// `target_outdated` — 상대 앱이 이 게임을 모른다(SPEC §8.3).
    package static let targetOutdated = "상대 앱이 1:1 길건너를 아직 몰라요"
    /// 서버에 길건너 1:1 이 아직 없다(PGRST202 — 배포 중간 창).
    package static let unavailable = "1:1 길건너는 곧 열려요"
    /// 한 판 한 기기 — 이 판은 같은 계정의 다른 기기가 두고 있다.
    package static let otherDevice = "다른 기기에서 대결 중이에요"

    /// 신청 결과. 근무 조건은 없다 — 클라가 근무를 보고 미리 막는 선게이트를 만들지 마라.
    package static func challenge(_ status: CrossyDuelRPCStatus, need: Int? = nil, have: Int? = nil) -> String {
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
        default: return common(status)
        }
    }

    package static func cancel(_ status: CrossyDuelRPCStatus) -> String {
        switch status {
        case .ok: return "신청을 취소했어요"
        case .notFound, .notPending, .expired: return finishedInvite
        default: return common(status)
        }
    }

    /// 수락·거절 결과. **수락 성공은 판이 곧바로 열리므로 말하지 않는다**(nil).
    package static func respond(
        accept: Bool, _ status: CrossyDuelRPCStatus, side: String? = nil, need: Int? = nil, have: Int? = nil
    ) -> String? {
        switch status {
        case .ok: return accept ? nil : "신청을 거절했어요"
        case .notFound, .notPending: return finishedInvite
        case .expired: return "신청 시간이 지났어요"
        case .invalid: return "받을 수 없는 신청이에요"
        case .busy: return busy
        case .targetBusy: return targetBusy
        case .insufficient:
            if side == "challenger" { return "상대의 루비가 모자라요" }
            return CheckCoreShared.shortfallNotice(need: need, have: have)
        default: return common(status)
        }
    }

    /// 기권 결과. 성공은 결과 화면이 말한다(nil).
    package static func resign(_ status: CrossyDuelRPCStatus) -> String? {
        switch status {
        case .ok: return nil
        case .notActive, .notFound: return finishedMatch
        case .otherDevice: return otherDevice
        default: return common(status)
        }
    }

    /// 결과 카드의 사유 한 줄(**내 기준**, SPEC §9.4). 사유를 모르면 빈 문자열.
    /// - Parameters:
    ///   - meReady / opponentReady: 끝난 state 의 `me.ready`·`opponent.ready` — `no_show` 를 가른다(v1.1 CC-12).
    package static func endReason(
        _ reason: CrossyDuelEndReason?, outcome: CrossyDuelOutcome?, meReady: Bool? = nil, opponentReady: Bool? = nil
    ) -> String {
        guard let reason else { return "" }
        switch reason {
        case .goal:
            switch outcome {
            case .win: return "먼저 100점에 닿았어요"
            case .loss: return "상대가 먼저 100점에 닿았어요"
            case .draw, nil: return "동시에 100점 — 비겼어요"
            }
        case .timeCap:
            switch outcome {
            case .win: return "3분 끝 — 점수가 더 높아요"
            case .loss: return "3분 끝 — 상대 점수가 더 높아요"
            case .draw, nil: return "3분 끝 — 점수가 같아 비겼어요"
            }
        case .resign:
            return outcome == .win ? "상대가 기권했어요" : "기권했어요"
        case .disconnect:
            switch outcome {
            case .win: return "상대 연결이 끊겼어요"
            case .loss: return "연결이 끊겨 이번 판은 졌어요"
            case .draw, nil: return "둘 다 연결이 끊겨 비겼어요"
            }
        case .noShow:
            switch (meReady ?? false, opponentReady ?? false) {
            case (true, false): return "상대가 준비하지 않아 판돈을 돌려받았어요"
            case (false, true): return "준비하지 않아 판이 열리지 않았어요 · 판돈은 돌려받았어요"
            default: return "둘 다 준비하지 않아 판돈을 돌려받았어요"
            }
        case .abandoned:
            return outcome == .win ? "상대가 떠났어요" : "대결을 떠났어요"
        case .void:
            return "판이 무효가 되어 판돈을 돌려받았어요"
        case .unknown:
            return ""
        }
    }

    package static func common(_ status: CrossyDuelRPCStatus) -> String {
        switch status {
        case .unsupportedClient: return updateMine
        case .notSignedIn: return signInAgain
        default: return tryAgain
        }
    }
}
