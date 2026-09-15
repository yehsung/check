// GOMOKU-UI-STUB
// ui 트랙 worktree 전용 스텁이다. 통합 때 core 트랙의 GomokuStore.swift 가 이 파일을 **통째로 덮는다**.
//
// 선언은 설계서 §6.3 을 글자 그대로 옮겼다. 네트워크·폴링·실시간은 없다(동작은 전부 빈 흉내) —
// 렌더 테스트와 미리보기는 상태 프로퍼티를 직접 채운다(§6.3 "전부 internal set").
// ★ 여기에 선언에 없는 공개 API 를 더하지 마라 — 뷰가 그걸 쓰는 순간 통합 때 컴파일이 깨진다.
//
// 맨 아래 `WorkTimerStore.gomoku` extension 과 `GomokuStubHolder` 도 **스텁 전용**이다. core 트랙은
// `WorkTimerStore` 에 `let gomoku: GomokuStore` 를 직접 두므로, 이 파일이 사라지면 CheckApp 의
// `store.gomoku` 배선이 그 저장 프로퍼티를 그대로 가리키게 된다.

import Foundation
import Observation

nonisolated enum GomokuStake: Int, CaseIterable, Sendable { case three = 3, five = 5, ten = 10 }

nonisolated struct GomokuUser: Identifiable, Equatable, Sendable {
    let id: String                 // user uuid 소문자 문자열
    let displayName: String
    let avatarURL: String?
    let characterID: String?
    let isWorking: Bool
    let isCapable: Bool            // 상대 앱이 오목을 아는 버전
    let inMatch: Bool
}

nonisolated struct GomokuRecord: Equatable, Sendable { let wins: Int; let losses: Int; let draws: Int }

nonisolated struct GomokuInvite: Identifiable, Equatable, Sendable {
    let id: String                 // match id
    let peer: GomokuUser           // 받은 신청이면 신청자, 보낸 신청이면 상대
    let stake: Int
    let expiresAt: Date            // 기기 시계로 보정된 시각
}

nonisolated enum GomokuEndReason: String, Sendable { case five, timeout, resign, boardFull = "board_full" }

nonisolated enum GomokuOutcome: Equatable, Sendable { case won, lost, draw }

nonisolated struct GomokuMatchState: Identifiable, Equatable, Sendable {
    let id: String
    var stake: Int
    var myColor: GomokuColor
    var opponent: GomokuUser
    var board: GomokuBoard
    var lastMove: GomokuPoint?
    var moveCount: Int
    var turn: GomokuColor?         // 끝나면 nil
    var deadline: Date?            // 차례 마감(기기 시계로 보정), 끝나면 nil
    var isFinished: Bool
    var outcome: GomokuOutcome?
    var endReason: GomokuEndReason?
    var rubyDelta: Int?            // 이 판으로 내 루비가 변한 양(승 +stake, 패 -stake, 무 0)
    var blackPassed: Bool          // 직전에 흑 자동 패스가 있었다
}

nonisolated enum GomokuPhase: Equatable, Sendable { case lobby, playing, result }

@MainActor @Observable final class GomokuStore {
    init(host: WorkTimerStore? = nil) {
        self.host = host
    }

    @ObservationIgnored private weak var host: WorkTimerStore?

    // 화면 상태 — 전부 internal set(렌더 테스트가 직접 채운다)
    var phase: GomokuPhase = .lobby
    var users: [GomokuUser] = []
    var record: GomokuRecord?
    var selectedStake: GomokuStake = .three
    var incoming: [GomokuInvite] = []
    var outgoing: GomokuInvite?
    var match: GomokuMatchState?
    var notice: String?                              // 사용자 어휘 안내 한 줄
    var isBusy = false
    var isWindowVisible = false
    var isRulesVisible = false
    var rubyBalance: Int?                            // 서버 응답으로만 갱신(host 에도 반영)

    /// 팝오버 배너·말풍선이 쓰는 대표 신청(만료 안 된 받은 신청 중 가장 오래된 것).
    var bannerInvite: GomokuInvite? {
        incoming.min(by: { $0.expiresAt < $1.expiresAt })
    }

    // UI 트랙이 CheckApp 에서 물리는 문
    @ObservationIgnored var presentWindow: (@MainActor () -> Void)?      // 창 띄우기(컨트롤러 show)
    @ObservationIgnored var onInviteArrived: (@MainActor (GomokuInvite) -> Void)?   // 새 받은 신청(처음 본 id 한 번)

    // 동작(스텁 — 서버를 부르지 않는다)
    func openWindow(focusMatchID: String?) { presentWindow?() }
    func windowDidShow() { isWindowVisible = true }
    func windowDidHide() { isWindowVisible = false }
    func refreshLobby() async {}
    func loadInbox() async {}
    func challenge(userID: String) async {}
    func cancelChallenge() async {}
    func respond(inviteID: String, accept: Bool) async {}
    func place(_ point: GomokuPoint) async {}
    func resign() async {}
    func refreshMatch() async {}
    func backToLobby() {
        match = nil
        phase = .lobby
    }
    func rematch() async {}
    func handleSignal() {}
    func reset() {
        phase = .lobby
        users = []
        record = nil
        incoming = []
        outgoing = nil
        match = nil
        notice = nil
        isBusy = false
        isRulesVisible = false
        rubyBalance = nil
    }

    /// 대국 창의 남은 시간(초, 0 이상). 잎 뷰 TimelineView 가 now 를 넘겨 부른다.
    func remainingSeconds(now: Date) -> Double? {
        guard let match, !match.isFinished, let deadline = match.deadline else { return nil }
        return max(0, deadline.timeIntervalSince(now))
    }
}

// MARK: - 스텁 전용 연결(통합 때 이 파일과 함께 사라진다)

/// ui worktree 에는 `WorkTimerStore.gomoku`(core 소유)가 없다. CheckApp·팝오버·미니게임 입구가 **통합 뒤와 같은 글자**
/// (`store.gomoku`)로 컴파일되게 하는 임시 다리다.
@MainActor
enum GomokuStubHolder {
    static let shared = GomokuStore()
}

extension WorkTimerStore {
    var gomoku: GomokuStore { GomokuStubHolder.shared }
}
