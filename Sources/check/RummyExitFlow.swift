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
// **위 표는 이 기기가 손댄 판(engaged — 설계서 v2 §6)에만 선다.** 놀던 맥(같은 계정의 다른 맥이 판을 하는 중, 이 맥은 초인종으로
// 판을 읽기만 했다)에서는 창 닫기가 그냥 닫히고 앱 종료·로그아웃·업데이트가 `rummy_leave` 를 보내지 않는다.
// 남는 빈틈(알고 둔다): 맥 A 에서 시작해 맥 B 에서 이어 하던 판은 A 도 engaged 라, A 를 끄면 그 판이 기권된다.
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
    /// 창 닫기(사람이 누른 닫기만). 순수 판단 — 시험이 표로 잰다. `engaged` = 이 기기가 그 판에 손댔다(§6).
    static func closeDecision(phase: RummyStore.Phase, mySeatState: RummySeatState?, amHost: Bool,
                              engaged: Bool = true) -> RummyCloseDecision {
        guard engaged else { return .close }
        switch phase {
        case .playing: return mySeatState == .playing ? .confirmForfeit : .close
        case .room: return amHost ? .confirmCloseRoom : .leaveRoom
        case .lobby, .finished: return .close
        }
    }

    /// 앱 종료·로그아웃 앞에 `rummy_leave` 를 보낼 판·방이 있는가. 이미 기권한 관전자는 보낼 것이 없다.
    static func needsExitLeave(phase: RummyStore.Phase, mySeatState: RummySeatState?, engaged: Bool = true) -> Bool {
        guard engaged else { return false }
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
        closeDecision(phase: store.phase, mySeatState: mySeat(store)?.state, amHost: amHost(store),
                      engaged: store.isEngagedInCurrentMatch)
    }

    @MainActor
    static func needsExitLeave(_ store: RummyStore) -> Bool {
        needsExitLeave(phase: store.phase, mySeatState: mySeat(store)?.state, engaged: store.isEngagedInCurrentMatch)
    }

    /// 앱 업데이트([지금 업데이트]) 판단. 순수 판단 — 시험이 표로 잰다.
    static func updateDecision(phase: RummyStore.Phase, mySeatState: RummySeatState?, engaged: Bool) -> RummyUpdateDecision {
        guard engaged else { return .proceed }
        switch phase {
        case .playing: return mySeatState == .playing ? .confirmForfeit : .proceed
        case .room: return .confirmLeaveRoom
        case .lobby, .finished: return .proceed
        }
    }

    @MainActor
    static func updateDecision(for store: RummyStore) -> RummyUpdateDecision {
        updateDecision(phase: store.phase, mySeatState: mySeat(store)?.state, engaged: store.isEngagedInCurrentMatch)
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

// MARK: - 판 중 앱 업데이트 확인(§6 후속)

/// [지금 업데이트] 판단. 업데이트는 앱을 끄고 새로 켠다 — 이 기기가 쥔 판이면 앱 종료와 같은 이탈이다.
enum RummyUpdateDecision: Equatable {
    /// 쥔 판·방이 없다(또는 놀던 기기다) — 곧바로 업데이트.
    case proceed
    /// 판 중(내 자리 playing) — "업데이트하면 지금 판이 기권돼요" 확인.
    case confirmForfeit
    /// 방(forming) — "업데이트하면 방에서 나가요" 확인.
    case confirmLeaveRoom
}

enum RummyUpdateText {
    static let forfeitTitle = "업데이트하면 지금 판이 기권돼요"
    static let forfeitDetail = "아잉 큐브 판 중이에요. 업데이트하면 앱이 다시 켜지면서 바로 기권으로 처리돼요. 꼴찌가 되고 판돈을 잃어요."
    static let forfeitButton = "기권하고 업데이트"
    static let roomTitle = "업데이트하면 방에서 나가요"
    static let roomDetail = "아잉 큐브 방에서 나간 뒤 업데이트해요. 방장이면 방이 닫혀요. 루비는 그대로예요."
    static let roomButton = "나가고 업데이트"
    static let keep = "계속하기"
    static let leaving = "판에서 나가는 중…"
}

/// 업데이트 배너의 확인 상태. 배너가 들고(`@State`), [지금 업데이트]가 `request` 를 부른다.
/// 확인을 고르면 **지금 판단**을 다시 본다(묻는 사이 판이 끝났으면 그냥 업데이트, 방이 판으로 시작됐으면 기권 문구로 다시 묻는다 —
/// 창 닫기 확인 `confirmClose` 와 같은 원칙: "루비는 그대로예요" 를 읽고 고른 버튼이 판돈을 잃는 기권이 되면 안 된다).
@MainActor
@Observable
final class RummyUpdateGate {
    private(set) var pending: RummyUpdateDecision?
    /// 확인 뒤 이탈이 도는 중(최대 2초 — 코어 상한). 배너는 버튼을 잠그고 한 줄을 보인다.
    private(set) var isLeaving = false
    @ObservationIgnored private var proceed: (() -> Void)?
    @ObservationIgnored private weak var store: RummyStore?
    /// 확인 뒤 이탈 + 업데이트(시험이 `await gate.leaveTask?.value` 로 기다린다).
    @ObservationIgnored private(set) var leaveTask: Task<Void, Never>?

    init(previewPending: RummyUpdateDecision? = nil) {
        pending = previewPending
    }

    /// [지금 업데이트]. 이 기기가 쥔 판·방이 없으면 곧바로 `proceed`, 있으면 확인을 띄우고 기다린다.
    func request(store: RummyStore?, proceed: @escaping () -> Void) {
        guard !isLeaving else { return }
        guard let store else {
            proceed()
            return
        }
        let decision = RummyExitPolicy.updateDecision(for: store)
        guard decision != .proceed else {
            proceed()
            return
        }
        ask(decision, store: store, proceed: proceed)
    }

    /// [계속하기] — 아무것도 보내지 않고 업데이트도 안 한다.
    func cancel() {
        pending = nil
        proceed = nil
        store = nil
    }

    /// [기권하고 업데이트] · [나가고 업데이트].
    func confirm() {
        guard let asked = pending, let proceed else { return }
        let store = self.store
        pending = nil
        self.proceed = nil
        self.store = nil
        guard let store else {
            proceed()
            return
        }
        let now = RummyExitPolicy.updateDecision(for: store)
        switch now {
        case .proceed:
            // 묻는 사이 판이 끝났다(또는 이미 나갔다) — 보낼 것 없이 업데이트.
            proceed()
        case asked:
            isLeaving = true
            leaveTask = Task { @MainActor [weak self] in
                if now == .confirmLeaveRoom {
                    // 방 나가기 — 그새 시작됐으면(이 기기에 시작이 닿기 전) 나가지 않고 판을 든다(`leaveRoomForExit`).
                    _ = await store.leaveRoomForExit(reason: .appUpdate)
                    if RummyExitPolicy.updateDecision(for: store) == .confirmForfeit {
                        self?.isLeaving = false
                        self?.ask(.confirmForfeit, store: store, proceed: proceed)
                        return
                    }
                } else {
                    _ = await store.leaveForExit(reason: .appUpdate)
                }
                self?.isLeaving = false
                proceed()
            }
        case .confirmForfeit, .confirmLeaveRoom:
            // 판단이 바뀌었다(방 → 판) — 새 문구로 다시 묻는다.
            ask(now, store: store, proceed: proceed)
        }
    }

    private func ask(_ decision: RummyUpdateDecision, store: RummyStore, proceed: @escaping () -> Void) {
        self.store = store
        self.proceed = proceed
        pending = decision
    }
}

/// 업데이트 배너 안의 확인 줄(버튼 줄 자리를 대신한다). 340pt 팝오버 폭에 맞춘 작은 글씨.
struct RummyUpdateConfirmRow: View {
    let decision: RummyUpdateDecision
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var copy: (title: String, detail: String, button: String, icon: String) {
        decision == .confirmLeaveRoom
            ? (RummyUpdateText.roomTitle, RummyUpdateText.roomDetail, RummyUpdateText.roomButton, "door.left.hand.open")
            : (RummyUpdateText.forfeitTitle, RummyUpdateText.forfeitDetail, RummyUpdateText.forfeitButton, "flag.fill")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: copy.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CheckTheme.danger)
                Text(copy.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Text(copy.detail)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text(RummyUpdateText.keep)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.06))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.border, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                Button(action: onConfirm) {
                    Text(copy.button)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CheckTheme.danger))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(CheckTheme.danger.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(CheckTheme.danger.opacity(0.35), lineWidth: 1))
        )
    }
}

// MARK: - App Nap(§6 후속 — 맥 전용 배선)

/// 이 기기가 쥔 판(engaged · room/playing — 코어 `isHoldingMatch`) 동안 `ProcessInfo` 활동을 쥔다.
/// 창이 가려지거나 다른 앱이 앞에 있으면 macOS 가 App Nap 으로 타이머를 합쳐 늦춘다 — 하트비트(10초)가 밀려 서버의
/// 90초 끊김 기권에 걸리거나, 작업 상태 전송·마감 깨우기가 늦는다. `.userInitiatedAllowingIdleSystemSleep` 이라
/// 시스템 잠자기(뚜껑 닫기·유휴 잠자기)는 막지 않는다 — 깨어나면 앱 델리게이트가 하트비트를 바로 한 번 보낸다.
/// 놓는 자리: 판 끝 · 이탈(창 닫기·종료·업데이트) · 로그아웃·계정 전환(코어 `reset`) — 모두 코어가 `false` 를 알린다.
@MainActor
final class RummyActivityHold {
    static let reason = "아잉 큐브 판 진행 중 — 하트비트·차례 마감을 제때 보낸다"
    private let begin: @MainActor (String) -> NSObjectProtocol
    private let end: @MainActor (NSObjectProtocol) -> Void
    private(set) var token: NSObjectProtocol?

    init(
        begin: @escaping @MainActor (String) -> NSObjectProtocol = { reason in
            ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: reason)
        },
        end: @escaping @MainActor (NSObjectProtocol) -> Void = { ProcessInfo.processInfo.endActivity($0) }
    ) {
        self.begin = begin
        self.end = end
    }

    var isHolding: Bool { token != nil }

    /// 코어 `onHoldingMatchChange` 가 부른다. 같은 값이 두 번 와도 활동은 하나만 쥔다.
    func set(_ holding: Bool) {
        if holding {
            guard token == nil else { return }
            token = begin(Self.reason)
        } else if let held = token {
            token = nil
            end(held)
        }
    }
}
