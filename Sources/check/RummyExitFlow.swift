import AppKit
import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 의도적 이탈 (2판 설계서 §3 · ⑨)
//
// 사용자 요구(10-30): "창 닫거나 나가버리면 바로 기권하고 나간걸로 처리해야지. 인터넷 연결 잠깐 끊기는거랑 아예 나가버리는거랑은
// 구분해야지". 연결 끊김은 서버 하트비트(90초)가 맡고, **사람이 고른 이탈**은 여기 세 문이 곧바로 `leaveForExit` 를 부른다.
//
// | 행동                        | 판(active, 내 자리 playing)        | 방(forming)                          | 그 밖(로비·결과·관전) |
// |----------------------------|-----------------------------------|--------------------------------------|----------------------|
// | 창 닫기(빨간 점 · ⌘W)        | "닫으면 기권돼요" 확인 → 기권        | 손님 = 그냥 나감 · 방장 = "방이 닫혀요" 확인 | 그냥 닫힘             |
// | 앱 종료(applicationShouldTerminate) | 기권 후 종료(최대 2초)        | 나간 뒤 종료(최대 2초)                  | 즉시 종료             |
// | 로그아웃(메뉴 바닥 버튼)      | 기권 후 로그아웃(최대 2초)          | 나간 뒤 로그아웃(최대 2초)               | 즉시 로그아웃         |
//
// RPC 는 셋 다 `rummy_leave` 하나다(코어 `leaveForExit(reason:)` — 서버 답과 2초 중 먼저 오는 것, 못 닿아도 이 기기에선 판을 접는다).
// 프로그램이 내리는 닫기(`CheckRummyWindowController.close()` — 로그아웃 정리·계정 전환)는 `windowShouldClose` 를 거치지 않아
// 여기 확인이 뜨지 않는다(그 길은 이미 위 표의 로그아웃 줄을 지났다).

/// 창 닫기 판단.
enum RummyCloseDecision: Equatable {
    /// 그냥 닫는다(이탈할 판·방이 없다).
    case close
    /// 손님이 방에서 닫는다 — 묻지 않고 나간다.
    case leaveRoom
    /// 판 중 — "닫으면 기권돼요" 확인.
    case confirmForfeit
    /// 방장이 방에서 닫는다 — "방이 닫혀요" 확인.
    case confirmCloseRoom
}

enum RummyExitPolicy {
    /// 창 닫기(사람이 누른 닫기만). 순수 판단 — 시험이 표로 잰다.
    static func closeDecision(phase: RummyStore.Phase, mySeatState: RummySeatState?, amHost: Bool) -> RummyCloseDecision {
        switch phase {
        case .playing: return mySeatState == .playing ? .confirmForfeit : .close
        case .room: return amHost ? .confirmCloseRoom : .leaveRoom
        case .lobby, .finished: return .close
        }
    }

    /// 앱 종료·로그아웃 앞에 `rummy_leave` 를 보낼 판·방이 있는가. 이미 기권한 관전자는 보낼 것이 없다.
    static func needsExitLeave(phase: RummyStore.Phase, mySeatState: RummySeatState?) -> Bool {
        switch phase {
        case .room: return true
        case .playing: return mySeatState == .playing
        case .lobby, .finished: return false
        }
    }

    @MainActor
    static func mySeat(_ store: RummyStore) -> RummyMatchSeat? {
        guard let match = store.match, let mine = match.mySeatNo else { return nil }
        return match.seats?.first { $0.seatNo == mine }
    }

    /// 방장인가 — 판 state 의 방장 id 와 내 자리의 사람 id(화면 `RummyScene.amHost` 와 같은 갈래).
    @MainActor
    static func amHost(_ store: RummyStore) -> Bool {
        guard let hostID = store.match?.hostId, let seat = mySeat(store) else { return false }
        return seat.userId == hostID
    }

    @MainActor
    static func closeDecision(for store: RummyStore) -> RummyCloseDecision {
        closeDecision(phase: store.phase, mySeatState: mySeat(store)?.state, amHost: amHost(store))
    }

    @MainActor
    static func needsExitLeave(_ store: RummyStore) -> Bool {
        needsExitLeave(phase: store.phase, mySeatState: mySeat(store)?.state)
    }

    /// 앱 종료 문: 보낼 판·방이 있으면 이탈을 **지금** 띄운 Task(최대 2초 — 코어 상한), 없으면 nil.
    /// 근무 마무리(`finishWorkBeforeQuit`, 최대 3초)와 **나란히** 돈다 — 종료가 2+3초로 늘지 않게.
    @MainActor
    static func startQuitLeave(_ store: RummyStore) -> Task<Bool, Never>? {
        guard needsExitLeave(store) else { return nil }
        return Task { @MainActor in await store.leaveForExit(reason: .appQuit) }
    }
}

// MARK: - 창 닫기 확인(패널 안 덮개)

/// 창 닫기 확인의 상태. 창 컨트롤러가 들고, 패널이 환경으로 받아 덮개를 그린다.
/// 확인을 고르면 컨트롤러가 준 일(창 내리기 + 이탈)을 한 번만 한다.
@MainActor
@Observable
final class RummyExitPrompt {
    private(set) var pending: RummyCloseDecision?
    @ObservationIgnored private var onConfirm: (() -> Void)?

    func ask(_ decision: RummyCloseDecision, onConfirm: @escaping () -> Void) {
        pending = decision
        self.onConfirm = onConfirm
    }

    func confirm() {
        let action = onConfirm
        pending = nil
        onConfirm = nil
        action?()
    }

    func cancel() {
        pending = nil
        onConfirm = nil
    }
}

enum RummyExitText {
    static let closeForfeitTitle = "창을 닫으면 기권돼요"
    static let closeForfeitDetail = "판 중에 창을 닫으면 바로 기권으로 처리돼요. 꼴찌가 되고 판돈을 잃어요. 남은 사람끼리 계속해요."
    static let closeForfeitButton = "기권하고 닫기"
    static let closeRoomTitle = "창을 닫으면 방이 닫혀요"
    static let closeRoomDetail = "방장이 나가면 방이 닫히고 모두 로비로 돌아가요. 루비는 그대로예요."
    static let closeRoomButton = "방 닫고 닫기"
    static let keep = "계속하기"
}

/// 창 닫기 확인 덮개(창 전체를 덮는다). 패널 안 다른 덮개(규칙·기권)와 같은 모양이다.
struct RummyExitConfirmOverlay: View {
    let decision: RummyCloseDecision
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var copy: (title: String, detail: String, button: String) {
        decision == .confirmCloseRoom
            ? (RummyExitText.closeRoomTitle, RummyExitText.closeRoomDetail, RummyExitText.closeRoomButton)
            : (RummyExitText.closeForfeitTitle, RummyExitText.closeForfeitDetail, RummyExitText.closeForfeitButton)
    }

    var body: some View {
        ZStack {
            CheckTheme.panelElevated.opacity(0.94)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: decision == .confirmCloseRoom ? "door.left.hand.closed" : "flag.fill")
                        .foregroundStyle(CheckTheme.danger)
                    Text(copy.title).font(.headline)
                }
                Text(copy.detail)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TetrisDuelActionButton(title: RummyExitText.keep, style: .outline, height: 34, fullWidth: true,
                                           action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    TetrisDuelActionButton(title: copy.button, tint: CheckTheme.danger, height: 34, fullWidth: true,
                                           action: onConfirm)
                }
            }
            .padding(22)
            .frame(width: 420, alignment: .leading)
            .tetrisDuelCard(padding: 0)
        }
        .frame(width: RummyWindowLayout.contentSize.width, height: RummyWindowLayout.contentSize.height)
    }
}

// MARK: - 로그아웃

extension WorkTimerStore {
    /// 메뉴 바닥의 [로그아웃]. 아잉 큐브 판·방 중이면 `rummy_leave`(최대 2초)를 먼저 보내고 기존 `signOut()` 으로 간다 —
    /// `signOut()` 이 세션을 먼저 지우면 이탈 요청이 토큰 없이 떠나 판이 '플레이 중'으로 남는다.
    /// 그 밖의 로그아웃(토큰 만료 강제 로그아웃 · 계정 삭제)은 서버에 닿을 세션이 없어 하트비트 90초가 맡는다.
    func signOutLeavingRummy() {
        guard RummyExitPolicy.needsExitLeave(rummy) else {
            signOut()
            return
        }
        let generation = sessionGeneration
        Task { @MainActor [weak self] in
            _ = await self?.rummy.leaveForExit(reason: .signOut)
            // 그 2초 사이 다른 길(강제 로그아웃·계정 전환)이 이미 세션을 바꿨으면 두 번 내리지 않는다.
            guard let self, self.sessionGeneration == generation else { return }
            self.signOut()
        }
    }
}
