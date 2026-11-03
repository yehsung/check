import Foundation

// MARK: - 문구 표 (사용자 어휘 — 이 표 밖에서 문구를 만들지 마라, SPEC §4.5 ⑤ · §5.6)

/// 아잉 마작 안내 한 줄의 **유일한 출처**. 게임 이름 글자도 여기 한 곳이다(맥 `MahjongInviteText.gameName` 은 이 값을 받는다).
/// 진단 어휘(서버·상태·동기화·seq·프로토콜)는 쓰지 않는다 — 사용자가 **할 수 있는 일**을 말한다.
/// 공용 거절(busy·target_busy·target_focused·blackout·insufficient·already_in_room·room_full·…)은 `RummyNoticeText` 의
/// 같은 줄을 글자 그대로 쓰고 게임 이름만 바꾼다. 규칙이 다른 줄(넷이 모여야 시작 · 빠진 까닭)만 마작 글로 바꿨다.
package nonisolated enum MahjongNoticeText {
    /// 어느 동작의 응답인가(같은 status 라도 동작마다 말이 다른 자리 — `invalid`·`stale`·`not_found`·`too_fast`).
    package enum Action: String, Sendable, CaseIterable {
        case lobby, create, invite, join, decline, leave, start, state, act, call, back, react, ranking
    }

    /// 게임 이름(카드 ① 답 "아잉 마작", #d_oLYeZqKqLOJU). 13바이트 — Release 바이트 검사에 못 쓰므로 값 비교로 잰다(§5.6).
    package static let gameName = "아잉 마작"

    package static let tryAgain = "잠시 후 다시 시도해 주세요"
    package static let checkConnection = "연결을 확인하고 다시 시도해 주세요"
    /// 내 앱이 옛 버전이다(`unsupported_client` · Availability `.updateRequired`).
    package static let updateRequired = "앱을 업데이트해 주세요"
    package static let signInAgain = "다시 로그인해 주세요"
    /// 서버에 아잉 마작이 아직 없다(PGRST202 — 배포 중간 창).
    package static let unavailable = "\(gameName)은 곧 열려요"
    package static let invited = "초대를 보냈어요"
    package static let roomClosed = "방이 닫혔어요"
    package static let turnPassed = "차례가 이미 넘어갔어요"
    package static let finishedMatch = "이미 끝난 판이에요"
    /// 선택지 밖 패(`illegal` — 화면이 선택지만 보여 주므로 드물다).
    package static let notAnOption = "지금은 낼 수 없는 패예요"

    // 시간 초과(내 `my_decision` 마감이 지났는데 내 `priv.auto` 버림이 왔거나 창이 닫혔다, UX:144).
    package static let timeoutDiscarded = "시간이 지나 방금 뽑은 패를 버렸어요"
    package static let timeoutPassed = "시간이 지나 넘겼어요"

    // 자리 비움(카드 ⑨ 답 — 판은 자동으로 끝까지, 손패를 한 번 누르면 돌아온다).
    package static let away = "자리 비움 — 차례가 오면 저절로 버려요 · 손패를 누르면 돌아와요"
    /// [돌아왔어요]를 나가기 뒤 10초 안에 눌렀다(`too_fast` + `retry_ms`).
    package static let backTooFast = "잠시 뒤에 다시 눌러 주세요"

    // 방.
    /// 시작 검사에서 **내가** 90초 넘게 안 보여 빠졌다(`seats_dropped{reasons: unseen}`, CS-03).
    package static let droppedUnseen = "자리를 비워 방에서 빠졌어요"
    /// 시작 검사에서 **내가** 루비가 모자라 빠졌다(`seats_dropped{reasons: insufficient}`).
    package static let droppedInsufficient = "루비가 모자라 방에서 빠졌어요"
    /// 넷째가 앉았다(방 띠 강조 · 방장은 [시작]).
    package static let fourGathered = "4명이 모였어요"

    // 연습판.
    /// 연습 중 루비 판이 섰다.
    package static let practiceClosed = "루비 판이 시작돼 연습판을 닫았어요"
    /// '넉넉히' 연습판의 론 아닌 울기 프롬프트가 5초 넘게 서 있다(CC-28).
    package static let practiceIdleCallHint = "[넘기기]를 누르면 계속돼요"

    // 덮개 말풍선(창이 탁자를 안 보일 때 — `MahjongAttention`).
    package static let myTurnAttention = "\(gameName) — 내 차례예요"
    package static let matchStartedAttention = "\(gameName) 판이 시작됐어요"
    package static let awayAttention = "\(gameName) — 자리 비움이 됐어요 · 차례가 오면 저절로 버려요"
    /// 사람이 창을 닫았고 이 기기가 연 판이 진행 중이다(판마다 1회, CC-22 — 확인 아님).
    package static let closedWhilePlaying = "창을 닫아도 판은 계속돼요 — 차례가 오면 자동으로 처리돼요"

    /// 모르는 역 id(규칙 2판의 새 역 — CC-07).
    package static let newYaku = "새 역"

    /// 역 이름. 모르는 역은 "새 역"(§4.4 — 와이어 역 id 는 원문 문자열).
    package static func yakuName(_ id: String) -> String {
        MahjongYaku(rawValue: id)?.koreanName ?? newYaku
    }

    /// 판 말풍선 문구(덮개 말풍선 하나 — §4.5 알림 정책).
    package static func attention(_ attention: MahjongAttention) -> String {
        switch attention.kind {
        case .matchStarted: return matchStartedAttention
        case .myTurn: return myTurnAttention
        case .away: return awayAttention
        case .closedWhilePlaying: return closedWhilePlaying
        }
    }

    /// 시작 검사에서 빠진 까닭(내 uuid 의 `reasons` 원문) → 문구.
    package static func dropped(reason: String?) -> String {
        reason == "insufficient" ? droppedInsufficient : droppedUnseen
    }

    /// RPC 거절 한 줄. **nil = 말하지 않는다** — 성공 · `stale`(결정 동작) · `window_closed` · `too_early` · 반응 쿨다운은
    /// 실려 온 state 로 화면이 답한다(§4.5 늦은 응답 가드 (e) · ⑤).
    package static func status(
        _ status: MahjongRPCStatus, for action: Action, need: Int? = nil, have: Int? = nil
    ) -> String? {
        switch status {
        case .ok: return nil
        case .busy: return "이미 다른 게임 중이에요"
        case .targetBusy: return "상대가 다른 게임 중이에요"
        case .targetOutdated: return "상대 앱이 \(gameName)을 아직 몰라요"
        case .targetFocused: return "상대가 집중 모드예요"
        case .insufficient: return CheckCoreShared.shortfallNotice(need: need, have: have)
        case .roomFull: return "방이 가득 찼어요"
        case .roomClosed: return roomClosed
        case .notEnoughPlayers: return "4명이 모여야 시작할 수 있어요"
        case .seatsDropped: return "자리를 비웠거나 루비가 모자란 사람이 빠졌어요"
        case .unsupportedClient: return updateRequired
        case .unauthorized: return signInAgain
        case .alreadyInRoom: return "이미 들어가 있는 방이 있어요"
        case .notHost: return "방장만 할 수 있어요"
        case .blackout: return "지금은 조용한 기간이라 초대할 수 없어요"
        case .tooManyInvites: return "한 번에 6명까지 초대할 수 있어요"
        case .alreadyInvited: return "이미 초대한 사람이에요"
        case .notInvited: return "초대받지 않은 방이에요"
        case .notFound:
            switch action {
            case .act, .call, .back, .react, .state: return finishedMatch
            default: return roomClosed
            }
        case .notYourTurn: return turnPassed
        case .stale:
            // 결정 동작의 stale 은 문구 없이 실려 온 state 로 맞춘다. 시작의 stale 은 지갑 키 경합 — 다시 시도.
            switch action {
            case .act, .call, .back: return nil
            default: return tryAgain
            }
        case .notActive: return finishedMatch
        case .illegal: return notAnOption
        case .windowClosed, .tooEarly: return nil
        case .tooFast: return action == .back ? backTooFast : nil
        case .invalid:
            switch action {
            case .create: return "고를 수 없는 판돈이에요"
            case .invite: return "초대할 수 없는 사람이에요"
            case .join: return "참가할 수 없는 방이에요"
            default: return tryAgain
            }
        case .unknown: return tryAgain
        }
    }
}
