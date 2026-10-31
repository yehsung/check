import Foundation

// MARK: - 문구 표 (사용자 어휘 — 이 표 밖에서 문구를 만들지 마라)

/// 아잉 큐브 안내 한 줄의 **유일한 출처**(설계서 §4.3 문구표). 진단 어휘(서버·상태·동기화·seq)는 쓰지 않는다.
/// 화면·말풍선·배너가 모두 여기서 문구를 가져간다 — 맥 배선이 말풍선 글자를 따로 짓지 않게.
package nonisolated enum RummyNoticeText {
    /// 어느 동작의 응답인가(같은 status 라도 동작마다 말이 다른 자리 — `invalid` 등).
    package enum Action: String, Sendable {
        case lobby, create, invite, join, decline, leave, start, state, draft, play, draw, ranking
    }

    package static let tryAgain = "잠시 후 다시 시도해 주세요"
    package static let checkConnection = "연결을 확인하고 다시 시도해 주세요"
    package static let updateRequired = "앱을 업데이트해 주세요"
    package static let signInAgain = "다시 로그인해 주세요"
    /// 서버에 아잉 큐브가 아직 없다(PGRST202 — 배포 중간 창).
    package static let unavailable = "아잉 큐브는 곧 열려요"
    package static let invited = "초대를 보냈어요"
    package static let roomClosed = "방이 닫혔어요"
    /// 시작 검사에서 **내가** 빠졌다.
    package static let droppedFromRoom = "루비가 모자라거나 다른 게임 중이라 방에서 빠졌어요"
    package static let turnPassed = "차례가 이미 넘어갔어요"
    /// 완료·뽑기가 stale 인데 차례는 아직 내 것이다(남의 기권 등으로 판의 seq 가 올랐다 — 시간은 남아 있다).
    package static let tableChanged = "판이 바뀌었어요. 확인하고 다시 눌러 주세요"
    package static let finishedMatch = "이미 끝난 판이에요"
    /// 말풍선 — 창이 안 보일 때 내 차례가 왔다(설계서 §5).
    package static let myTurnAttention = "아잉 큐브 — 내 차례예요"
    /// 말풍선 — 창이 안 보일 때 판이 시작됐다(내 차례가 아니면).
    package static let matchStartedAttention = "아잉 큐브가 시작됐어요"

    /// 초대 말풍선·배너 한 줄(설계서 §5): "OO님이 아잉 큐브에 초대했어요 · 판돈 N".
    package static func invitation(_ room: RummyRoom) -> String {
        let name = room.host?.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "친구"
        guard let stake = room.stake else { return "\(name)님이 아잉 큐브에 초대했어요" }
        return "\(name)님이 아잉 큐브에 초대했어요 · 판돈 \(stake)"
    }

    /// 첫 등록 진행 표시("첫 등록 18/30점").
    package static func initialProgress(_ points: Int) -> String {
        "첫 등록 \(points)/30점"
    }

    /// 판정 이유 한 줄(설계서 §4.3). 통과(`ok`)·모름(`unknown`)은 nil — 부르는 쪽이 `tryAgain` 으로 메운다.
    package static func reason(_ reason: RummyTurnReason, initialPoints: Int?) -> String? {
        switch reason {
        case .ok, .unknown: return nil
        case .malformed: return "타일 모양이 이상해요. 되돌리고 다시 놓아 주세요."
        case .jokerNotReused: return "가져온 조커는 이번 차례에 판에 써야 해요."
        case .tableTileRemoved: return "판에 있던 타일은 내 랙으로 가져올 수 없어요."
        case .tileNotOwned: return "내 랙에 없는 타일이에요."
        case .noTilePlayed: return "내 타일을 1개 이상 내야 해요."
        case .invalidMeld: return "맞지 않는 묶음이 있어요."
        case .initialTableTouched: return "첫 등록 차례에는 판에 있던 묶음을 건드릴 수 없어요."
        case .initialUnder30:
            guard let initialPoints else { return "첫 등록은 30점 이상이어야 해요." }
            return "첫 등록은 30점 이상이어야 해요(지금 \(initialPoints)점)."
        }
    }

    /// RPC 거절 한 줄(설계서 §4.3 상태 문구 + 동작별 보충). `ok` 는 부르지 않는다.
    package static func status(_ status: RummyRPCStatus, for action: Action) -> String {
        switch status {
        case .busy: return "이미 다른 게임 중이에요"
        case .targetBusy: return "상대가 다른 게임 중이에요"
        case .targetOutdated: return "상대 앱이 아잉 큐브를 아직 몰라요"
        case .targetFocused: return "상대가 집중 모드예요"
        case .insufficient: return "루비가 모자라요"
        case .roomFull: return "방이 가득 찼어요"
        case .roomClosed: return roomClosed
        case .notEnoughPlayers: return "2명 이상 모여야 시작할 수 있어요"
        case .seatsDropped: return "루비가 모자라거나 다른 게임 중인 사람이 빠졌어요"
        case .unsupportedClient: return updateRequired
        case .unauthorized: return signInAgain
        case .alreadyInRoom: return "이미 들어가 있는 방이 있어요"
        case .notHost: return "방장만 할 수 있어요"
        case .blackout: return "지금은 조용한 기간이라 초대할 수 없어요"
        case .tooManyInvites: return "한 번에 6명까지 초대할 수 있어요"
        case .alreadyInvited: return "이미 초대한 사람이에요"
        case .notInvited: return "초대받지 않은 방이에요"
        case .notFound: return action == .play || action == .draw ? finishedMatch : roomClosed
        case .notYourTurn: return turnPassed
        case .stale:
            // 차례 동작의 stale 만 "차례가 넘어갔다" 쪽이다. 시작의 stale 은 지갑 키 경합(30_room.sql) — 다시 시도.
            switch action {
            case .play, .draw, .draft: return turnPassed
            default: return tryAgain
            }
        case .notActive: return finishedMatch
        case .malformed: return reason(.malformed, initialPoints: nil) ?? tryAgain
        case .invalid:
            switch action {
            case .create: return "고를 수 없는 판돈이에요"
            case .invite: return "초대할 수 없는 사람이에요"
            case .join: return "참가할 수 없는 방이에요"
            default: return tryAgain
            }
        // v2 반응 쿨다운 — 화면은 이 문구를 띄우지 않는다(조용히 버린다). 표를 빠짐없이 두려고만 있다.
        case .tooFast: return "조금 천천히 보내 주세요"
        case .ok, .rejected, .unknown: return tryAgain
        }
    }
}
