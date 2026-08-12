import AppKit
import SwiftUI

/// 근무중일 때만 화면 우상단(메뉴바 바로 아래)에 떠 있는 3D 캐릭터 오버레이 패널과 그 표시/숨김·재배치를 관리한다.
///
/// 패널은 앱 시작 시 1회 생성해 숨김으로 시작한다. 루트 뷰(`CheckOverlayRootView`)가 store의
/// `snapshot.isWorking`을 관찰하다가 변화를 콜백으로 전달하면 여기서 `orderFrontRegardless`/
/// `orderOut`으로 전환한다. 패널은 클릭 통과(`ignoresMouseEvents=true`)라 작업을 방해하지 않으며,
/// 모든 Space·전체화면 앱 위에서도 유지되도록 `collectionBehavior`를 설정한다.
@MainActor
final class CheckOverlayController {
    /// 오버레이 패널 크기(pt).
    static let panelSize = NSSize(width: 140, height: 170)
    /// 화면 가장자리 여백(pt).
    static let edgeMargin: CGFloat = 24
    /// 클릭(때리기)과 드래그(이동)를 가르는 이동 임계(pt). 이보다 적게 움직이면 클릭으로 본다.
    static let dragThreshold: CGFloat = 4
    /// 드래그로 옮긴 위치(우상단 앵커 오프셋 [dx, dy])를 저장하는 UserDefaults 키.
    static let overlayOffsetKey = "check.overlayOffset"

    /// 근무 종료 인사(꾸벅, 0.4s) 후 패널을 숨기기까지의 상한(초). 인사가 끝난 직후 내려가고, 최대 1초를 넘지 않는다.
    static let farewellHideDeadline: TimeInterval = ReactionKind.commuteEnd.duration + 0.15

    /// 넛지 자동 근무 시작 시 등장 말풍선에 띄우는 안내 문구/지속시간(A3). "물어보기" 대신 "안내만" 한다.
    static let nudgeAutoStartText = "일하는 것 같아서 근무 시작했어요!"
    static let nudgeAutoStartBubbleSeconds: Double = 8

    /// 오늘 팀에서 1등으로 출근했을 때의 등장 말풍선(하루 1회, store 의 dayKey 장부가 보증).
    static let firstArrivalText = "오늘 1등 출근이에요!"
    static let firstArrivalBubbleSeconds: Double = 6

    /// 깜빡임 간격(초) 범위. 사람의 자연스러운 깜빡임보다 성기게 둔다 — 메뉴바 옆 작은 캐릭터라
    /// 너무 잦으면 '깜빡임'이 아니라 '떨림'으로 읽힌다.
    static let blinkIntervalRange: ClosedRange<Double> = 3.0...7.0

    /// 새 버전 감지 시 캐릭터가 띄우는 말풍선 문구/지속시간. 버전당 1회만(도배 금지).
    static let updateBubbleText = "새 업데이트가 있어요!"
    static let updateBubbleSeconds: Double = 6

    /// 숨김 상태(비근무·오버레이 꺼짐)에서 찔림을 받으면 잠깐 나타났다 사라지는 peek 노출 시간(초).
    /// 움찔 모션(≈1.15s) + 말풍선(6s) 을 다 보여줄 만큼 두고 여유를 더한 값.
    static let pokePeekSeconds: Double = 8

    /// 울트라 격발 지속(초). ReactionKind.ultraPoked.duration · ReactionActions.ultraPoked 총 길이와
    /// **같은 값**이어야 모션이 끝나는 순간 창도 접힌다.
    static let ultraSeconds: Double = 5
    /// 격발 복원 워치독의 여유(초). 정상 경로(ultraTask)가 취소·예외·런루프 지연으로 죽어도 이 시각을 넘겨
    /// 화면이 덮인 채 남지 않도록, **메인 타이머와 독립된** 두 번째 태스크가 여기서 강제 원복한다.
    /// 격발은 가리되 막지는 않지만(클릭 통과를 못 박는다), 원복이 실패하면 화면 전체가 영영 캐릭터에 덮이고
    /// 패널 프레임이 전체화면인 채로 오염돼 다음 근무 시작 때까지 따라온다. 안전밸브다.
    static let ultraWatchdogGrace: Double = 1.0

    let panel: NSPanel
    /// 리액션 조율기. 표시 중일 때만 이벤트를 받아 캐릭터 wrapper 에 SCNAction 을 건다.
    let engine: ReactionEngine
    /// 표시 의도 상태. 헤드리스 환경에서도 결정적으로 검증할 수 있는 지점(실제 표시 여부는 `panel.isVisible`).
    private(set) var shouldBeVisible = false
    /// 넛지 스케줄러 가동 의도. NudgeScheduler 의 loopTask 는 private 이라 밖에서 볼 수 없으므로,
    /// `syncNudgeScheduler` 의 판정 결과를 여기 남겨 "실행 직후부터 감지가 돌고 있는가"를 헤드리스로 검증한다
    /// (shouldBeVisible 과 같은 성격의 검증 지점 — 실제 루프 존재가 아니라 이 클래스의 결정을 고정한다).
    private(set) var nudgeSchedulerRunning = false

    private let notificationCenter: NotificationCenter
    private var screenObserver: NSObjectProtocol?
    private let store: WorkTimerStore
    /// 드래그로 옮긴 위치를 영속하는 저장소(테스트 격리를 위해 주입 가능).
    private let defaults: UserDefaults
    /// 업데이트 감지 스토어(주입, 옵셔널). 패널 표시 중 새 버전이 감지돼 있으면 버전당 1회 말풍선을 띄운다.
    /// 네트워크 체크는 여기서 새로 치지 않는다 — 하루 1회 킥은 팝오버(CheckMenuView `.task`)가 담당하고,
    /// 컨트롤러는 이미 채워진 공유 상태를 읽어 표시만 한다(유휴 0% 불변 · 상시 루프 신설 금지).
    private let updateCheck: UpdateCheckStore?

    // MARK: - 근무 시작 제안(넛지) — 안내만 하고 즉시 자동 시작(A3)
    /// 넛지 감지 스케줄러(비근무·로그인 상태일 때만 가동). onNudge → nudgeAutoStart.
    private var nudgeScheduler: NudgeScheduler!
    /// 캐릭터 몸체 위 클릭만 우리 창이 소비하도록 hitTest 하고, 로컬 마우스 이벤트(down/dragged/up/moved)를
    /// 컨트롤러로 넘기는 호스팅 뷰(패널 contentView).
    /// (자기 참조 클로저를 담은 루트 뷰를 얹은 뒤 대입하므로 init 순서상 IUO var 로 둔다.)
    private var contentHostingView: CharacterHitTestingView<CheckOverlayRootView>!

    // A1: 커서가 캐릭터 몸체 위인지 추적하는 전역 mouseMoved 모니터(패널 표시 중에만 설치). 몸체 위면 클릭 통과를
    // 잠시 해제(ignoresMouseEvents=false)해 우리 창이 클릭을 소비·리액션/드래그로 쓰고, 몸체 밖(여백 포함)은 통과.
    private var mouseMoveMonitor: Any?
    // 드래그 임시 상태(다운~업 사이에만 유효).
    private var dragAnchor: NSPoint = .zero        // 좌클릭 다운 시점의 마우스 좌표.
    private var originAtDragStart: NSPoint = .zero // 다운 시점의 패널 origin.
    private var isDragCandidate = false            // 패널 안에서 다운되어 드래그 후보가 됨.
    private var didDrag = false                    // 임계를 넘겨 실제 이동으로 확정됨.
    private var facingHysteresis = DragFacingHysteresis() // 드래그 수평 방향 판정(미세 떨림 무시).
    // 근무 종료 인사 후 숨김을 보장하는 워치독.
    private var farewellTask: Task<Void, Never>?
    // 밤샘 졸기 스케줄러(패널 표시 중에만 90±30초 간격으로 시간창을 확인).
    private var drowsyTask: Task<Void, Never>?
    private var blinkTask: Task<Void, Never>?
    // 숨김 상태에서 찔림을 peek 로 보여주는 동안만 유효한 자동 퇴장 태스크. updateWorking 양쪽에서 취소한다.
    private var pokePeekTask: Task<Void, Never>?

    // MARK: - 할 일 보드 훅
    //
    // 오버레이는 보드를 **모른다**. 여기 뚫린 콜백으로 사실만 알리고 판단은 전부 보드 컨트롤러가 한다 —
    // 그래야 캐릭터 패널의 프레임·클릭통과·울트라 복귀 같은 이미 아픈 기계에 새 조건이 섞이지 않는다.

    /// 캐릭터 몸통을 눌렀다. **true 를 돌려주면 그 클릭은 보드가 가져간 것**이라 아파하기를 재생하지 않는다.
    /// 할 일 기능이 꺼진 사용자에게는 배선이 false 를 돌려주므로 예전 동작(아얏)이 그대로 남는다.
    var onCharacterTapped: (() -> Bool)?
    /// 울트라 격발이 시작/종료됐다. 보드는 격발 동안 화면에서 비켜야 한다(전체화면 연출 위에 겹칠 수 없다).
    var onUltraBegan: (() -> Void)?
    /// restoresVisibility 가 false 면 근무 종료 경로라 보드를 되살리지 않는다(캐릭터와 같은 규약).
    var onUltraEnded: ((Bool) -> Void)?
    /// 근무가 끝났다(표시 → 숨김 전이). 보드는 인사를 기다리지 않고 즉시 닫고 저장한다.
    var onWorkEnded: (() -> Void)?
    /// 캐릭터 패널이 새 자리로 갔다(재배치·드래그 종료·화면 구성 변경). 보드가 따라와야 한다.
    var onCharacterFrameChanged: ((NSRect) -> Void)?
    /// 보드가 열려 있는가. 졸기 스케줄러가 물어본다 — 보드를 보며 생각하는 동안 잠들면 "얘 죽었나"로 읽힌다.
    var isBoardOpen: (() -> Bool)?

    /// 울트라 격발 중에만 유효한 원복 상태. nil 이면 격발 중이 아니다(isUltraActive 의 근거).
    private struct UltraRestoreState { let frame: NSRect; let hadMouseMonitor: Bool }
    private var ultraRestoreState: UltraRestoreState?
    /// 정상 원복 타이머(5초).
    private var ultraTask: Task<Void, Never>?
    /// ★ 안전밸브: 정상 원복과 **독립된** 워치독 태스크. ultraTask 가 어떤 이유로 죽어도(취소·스케줄 유실)
    ///   deadline 이 지나면 여기서 강제로 원복한다. 격발 중 화면이 클릭을 먹으므로, 영원히 덮인 채 남으면
    ///   사용자는 화면을 되찾을 수단이 없다(메뉴바와 ⌘⌥Esc 뿐이다).
    private var ultraWatchdogTask: Task<Void, Never>?
    /// 격발이 반드시 걷혀야 하는 시각. 헤드리스 검증 지점이자 워치독의 판정 근거(한 곳에서만 계산).
    private(set) var ultraDeadline: Date?
    /// 격발 세대. 재수신으로 5초를 리셋할 때마다 오른다. 취소된 옛 워치독이 즉시 깨어나 **방금 시작한**
    /// 격발을 잘라먹는 것을 막는 유일한 수단이다(취소 여부만 봐서는 두 경우를 구분할 수 없다).
    private var ultraGeneration = 0
    /// 이 인스턴스의 격발 지속(초) = 정상 원복 타이머(ultraTask)가 자는 시간. 프로덕션은 언제나
    /// `Self.ultraSeconds` 다. **테스트만** 짧게 주입해 "타이머가 스스로 깨어나 원복하는가"를 실시간으로
    /// 검증한다. 이 주입 지점이 없으면 그 검증에 매번 5~6초가 들어 아무도 안 쓰게 되고, 실제로
    /// `ultraTask`/`ultraWatchdogTask` **생성을 통째로 지워도 스위트가 초록인** 구멍이 있었다
    /// (값 판정 함수 enforceUltraDeadline 만 밖에서 불러 검증했기 때문이다).
    let ultraDurationSeconds: Double
    /// 이 인스턴스의 강제 원복 상한(초) — **격발이 시작된 시각 기준**이다(마감 시각의 유일한 근거).
    /// 프로덕션은 `ultraSeconds + ultraWatchdogGrace`. 위와 같은 이유로 테스트에서만 짧게 주입한다.
    let ultraDeadlineSeconds: Double
    /// 클릭 통과 값 못 박기. non-nil 인 동안 `setIgnoresMouseEvents` 는 어떤 호출자가 무엇을 요구하든
    /// 이 값만 쓴다. 이게 없으면 히트-스루 기계(updateHitThrough / restorePassThroughAfterExit)가
    /// 커서 위치에 따라 값을 뒤집어 5초 격발이 "막다 말다" 하는 최악의 상태가 된다.
    private var pinnedIgnoresMouseEvents: Bool?
    /// `updateWorking` 재진입 래치. AppKit 이 우리 자신의 프레임 변경 도중에 SwiftUI 를 평가해
    /// `.onChange` → updateWorking 을 되부르는 것을 막는다(자세한 이유는 updateWorking 주석).
    private var isUpdatingWorking = false
    /// 헤드리스 검증 지점(shouldBeVisible·nudgeSchedulerRunning 과 같은 성격 — 실제 창 상태가 아니라
    /// 이 클래스의 결정을 고정한다).
    var isUltraActive: Bool { ultraRestoreState != nil }
    /// 헤드리스 검증 지점. '이 클래스가 A1 히트-스루 기계를 떼었는가'를 고정한다.
    var hasMouseMoveMonitor: Bool { mouseMoveMonitor != nil }
    /// 헤드리스 검증 지점. '클릭 통과 값을 못 박았는가'(nil = 평시 자동 토글).
    var pinnedIgnoresMouseEventsValue: Bool? { pinnedIgnoresMouseEvents }

    init(
        store: WorkTimerStore,
        notificationCenter: NotificationCenter = .default,
        engine: ReactionEngine? = nil,
        defaults: UserDefaults = .standard,
        workspaceNotifications: NotificationCenter? = NSWorkspace.shared.notificationCenter,
        updateCheck: UpdateCheckStore? = nil,
        ultraDurationSeconds: Double = CheckOverlayController.ultraSeconds,
        ultraDeadlineSeconds: Double
            = CheckOverlayController.ultraSeconds + CheckOverlayController.ultraWatchdogGrace
    ) {
        self.notificationCenter = notificationCenter
        self.store = store
        self.defaults = defaults
        self.updateCheck = updateCheck
        self.ultraDurationSeconds = ultraDurationSeconds
        self.ultraDeadlineSeconds = ultraDeadlineSeconds
        self.engine = engine ?? ReactionEngine()
        panel = Self.makePanel(size: Self.panelSize)

        let engineRef = self.engine
        let root = CheckOverlayRootView(
            store: store,
            engine: engineRef,
            onWorkingChange: { [weak self] working in self?.updateWorking(working) }
        )
        let hosting = CharacterHitTestingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        contentHostingView = hosting
        panel.contentView = hosting

        // A1: 캐릭터 몸체 위에서만 우리 창이 클릭을 받도록 hitTest 를 몸체 판정에 배선하고, 로컬 마우스 이벤트를
        // 컨트롤러의 기존 스크린 좌표 핸들러로 넘긴다(전역 클릭 모니터 삭제).
        hosting.bodyHitTest = { [weak self] screenPoint in self?.withinBody(screenPoint) ?? false }
        hosting.onMouseDown = { [weak self] location in self?.handleMouseDown(at: location) }
        hosting.onMouseDragged = { [weak self] location in self?.handleMouseDragged(at: location) }
        hosting.onMouseUp = { [weak self] location in self?.handleMouseUp(at: location) }
        // ignoresMouseEvents=false 인 동안엔 전역 모니터가 자기 창 위 이동을 못 보므로, 트래킹 영역의
        // mouseMoved/mouseExited 로 몸체 이탈을 감지해 통과(true)로 되돌린다.
        hosting.onMouseMovedInside = { [weak self] location in self?.updateHitThrough(at: location) }
        hosting.onMouseExited = { [weak self] in self?.restorePassThroughAfterExit() }

        // 스토어(소유 파일)가 감지한 마일스톤/팀원 인사 트리거를 엔진으로 흘린다. 표시 중일 때만 반응한다
        // (숨겨진 패널에 파티클/애니메이션을 남기지 않기 위해).
        store.onReactionTrigger = { [weak self] kind in
            guard let self, self.shouldBeVisible else { return }
            self.engine.request(kind)
        }

        // 수신 찔림 싱크. onReactionTrigger 와 달리 shouldBeVisible 게이트를 걸지 않는다 — 숨김 상태에서도
        // peek(잠깐 나타나 움찔+말풍선 후 사라짐)로 전달하는 것이 핵심 요구다. 캐릭터 표시를 꺼 둔 사용자에게도
        // 똑같이 peek 한다 — 서버가 이미 소비한 찔림이라 여기서 버리면 영영 전달되지 않는다.
        // 폴링/신선도 필터는 스토어가 끝냈으므로 여기선 받은 배치를 그대로 표시만 한다.
        store.onPokesReceived = { [weak self] pokes in self?.handleReceivedPokes(pokes) }

        // 넛지 스케줄러: 자격은 store 로 구성(로그인·팀·비근무·억제 아님), 발동은 자동 근무 시작(안내만)으로.
        // 공백 관측/생존 스탬프는 수동 종료 억제의 해제·영속 판정으로 잇는다(스케줄러는 store 를 모른다).
        nudgeScheduler = NudgeScheduler(
            isEligible: { [weak self] in self?.isNudgeEligible ?? false },
            onNudge: { [weak self] in self?.nudgeAutoStart() },
            onAbsenceGap: { [weak self] in self?.store.clearAutoStartSuppression() },
            onAliveTick: { [weak self] now in self?.store.recordNudgeAlive(now) },
            workspaceNotifications: workspaceNotifications
        )

        reposition()
        observeScreenChanges()
        // 넛지 스케줄러를 실행 시 여기서 한 번 가동한다. 이 줄이 없으면 유일한 기동 지점이 updateWorking 의
        // defer 뿐이고, updateWorking 은 숨겨진 패널의 SwiftUI 루트 뷰가 `.onChange(initial: true)` 를 실제로
        // 평가해 줄 때만 불린다 — 즉 자동 근무 시작 전체가 "숨긴 패널의 body 도 평가된다"는 검증 안 된 런타임
        // 가정에 매달린다. MenuBarExtra(.window) 에서 똑같은 종류의 가정이 이미 한 번 틀려(팝오버를 열기 전엔
        // 콘텐츠 뷰가 아예 생성되지 않았다) D1 킥을 만들게 했다. start() 는 loopTask 가드로 멱등이라 루트 뷰가
        // 곧바로 한 번 더 불러도 루프가 두 개 생기지 않는다.
        syncNudgeScheduler()
    }

    /// 넛지 자동 시작 자격: 로그인됨·팀 있음·비근무. (표시중 조건은 소멸 — 안내만 하고 바로 시작.)
    ///
    /// 자동 시작은 끌 수 있는 설정이 아니라 앱의 기본 동작이다 — 되돌리려면 평소처럼 '근무 종료'를 누르면 된다.
    /// 캐릭터 표시(`isOverlayEnabled`)도 자격에서 **뺀다**. 예전엔 AND 로 걸려 있어 캐릭터를 숨긴 사용자에게는
    /// 자동 시작이 영영 일어나지 않았다. 캐릭터가 숨겨져 있으면 등장 말풍선 대신 메뉴바 아이콘이 근무중으로
    /// 바뀌어 알린다 — 알림 채널은 사라지지 않는다.
    private var isNudgeEligible: Bool {
        store.isSignedIn
            && store.currentTeamID != nil
            && store.snapshot.isWorking == false
            // 수동 [근무 종료] 억제 중엔 자동 시작하지 않는다(1시간+ 부재 후 재무장 — store 가 관리).
            && !store.autoStartSuppressed
    }

    /// 근무 상태 변화에 따라 패널을 표시/숨김한다. 표시 직전 항상 우상단으로 재배치한다.
    /// 사용자가 캐릭터 표시를 꺼두면(isOverlayEnabled=false) 근무중이어도 표시하지 않는다.
    ///
    /// 표시 시: 폴짝 점프+스핀(commuteStart). 숨김 시: 앞으로 꾸벅 인사(commuteEnd) 후 패널을 내린다.
    /// 인사 완료 콜백은 렌더 루프가 돌 때 오고, 워치독이 최대 `farewellHideDeadline` 내 숨김을 보장한다.
    func updateWorking(_ isWorking: Bool) {
        // ★ 재진입 차단. 이 함수는 패널 프레임·표시를 바꾸고, 그 변경은 NSHostingView 가 SwiftUI 루트 뷰를
        //   **그 자리에서** 다시 평가하게 만든다 → `.onChange(of: store.snapshot.isWorking)` 가 이 함수를
        //   자기 실행 도중에 되부른다. 중첩 호출은 새 정보가 없다(우리 자신의 그리기가 만든 통지이고,
        //   updateWorking 은 스토어를 건드리지 않으므로 인자 값도 바깥 호출과 같다).
        //   그런데 그 중첩 호출이 먼저 끝까지 달려 orderOut 까지 해 버리면, 바깥 호출은 "이미 숨겨진 창"을
        //   보고 `wasVisible && panel.isVisible` 을 놓쳐 **근무종료 인사를 통째로 건너뛴다** —
        //   사용자는 "수고했어!" 없이 캐릭터가 사라지는 걸 본다(울트라 격발 중 종료에서 실제로 났다).
        if isUpdatingWorking { return }
        isUpdatingWorking = true
        defer { isUpdatingWorking = false }
        let visible = isWorking && store.isOverlayEnabled
        let wasVisible = shouldBeVisible
        shouldBeVisible = visible
        defer { syncNudgeScheduler() }
        // 진행 중이던 찔림 peek 는 어느 방향 전이에도 승격/무효화된다: (true) 정상 표시가 소유권을 가져가고,
        // (false) 정상 숨김 경로가 퇴장을 처리하므로 peek 의 지연 orderOut 이 뒤늦게 끼어들지 않게 취소한다.
        pokePeekTask?.cancel()
        pokePeekTask = nil
        // 격발 중 근무 상태가 바뀌면(직접 종료·자동 마감·표시 토글) 전체화면을 즉시 접는다. 이 줄이 없으면
        // 화면을 덮은 채로 근무종료 인사가 재생되고, farewell 워치독이 orderOut 해도 **프레임이 전체화면인
        // 채로 남아** 다음 근무 시작 때 캐릭터가 화면 전체로 뜬다(게다가 클릭을 먹는 채로 남는다).
        // endUltraTakeover 가 내부에서 cancelActiveReaction 을 부르므로 울트라(우선순위 4)가 비켜나
        // 아래 정상 분기의 commuteEnd(3)가 수용된다.
        //
        // **단, 실제 전이(wasVisible != visible)일 때만이다.** 이 함수는 SwiftUI 의 재통지로도 불린다 —
        // `.onChange(of: store.isSignedIn)`·`.onChange(of: store.isOverlayEnabled)` 가 근무 상태는 그대로인 채
        // onWorkingChange(store.snapshot.isWorking) 를 다시 흘린다(토큰 갱신 한 번이면 충분하다).
        // 그 재통지까지 접어 버리면 5초 격발이 아무 이유 없이 사라지고 그 위에 commuteStart 점프가 얹힌다.
        // 보낸 사람은 하루 몫을 이미 태웠으므로 이건 복구되지 않는 손실이다.
        if isUltraActive && wasVisible != visible { endUltraTakeover(restoresVisibility: false) }
        // 전이가 아닌 재통지는 여기서 물러난다. 아래 분기는 격발 중에 실행되면 안 된다 —
        // 숨김 분기의 orderOut/renderActive=false 는 전체화면 격발을 그대로 지우고,
        // 표시 분기의 reposition()+request(.commuteStart) 는 전체화면 프레임을 작은 기본 위치로 되돌린다.
        if isUltraActive { return }
        if visible {
            farewellTask?.cancel()
            farewellTask = nil
            engine.renderActive = true
            reposition()
            panel.orderFrontRegardless()
            installMouseMoveMonitor()
            startDrowsyScheduler()
            startBlinkScheduler()
            // 오늘 팀에서 1등 출근이면 등장 말풍선을 1회 갈아 끼운다. 넛지 자동 시작이 이미 오버라이드를
            // 세워 뒀으면 건드리지 않는다 — 그쪽이 "왜 저절로 시작됐는지"를 설명하는 더 급한 문구다.
            if engine.commuteStartBubbleOverride == nil, store.consumeFirstArrivalGreeting() {
                engine.setCommuteStartBubbleOverride(
                    text: Self.firstArrivalText,
                    seconds: Self.firstArrivalBubbleSeconds
                )
            }
            engine.request(.commuteStart)
        } else {
            // 근무가 끝났다. 보드는 인사(0.55초)를 기다리지 않고 **즉시** 닫고 저장한다 —
            // 사라지는 캐릭터 옆에 남은 보드는 유령이고, 자동 마감·다른 맥 흡수처럼 사용자 조작 없이
            // 오는 경로에서는 저장 시점이 특히 중요하다.
            if wasVisible { onWorkEnded?() }
            stopDrowsyScheduler()
            stopBlinkScheduler()
            removeMouseMoveMonitor()
            engine.greetingText = nil
            if wasVisible && panel.isVisible {
                // 자는 중이어도 근무종료는 즉시 인터럽트되어 꾸벅 인사 + "수고했어!" 후 퇴장한다.
                beginFarewellHide()
            } else {
                // 표시된 적 없는 경로: 혹시 남아 있을 졸기 상태를 정리하고 렌더를 멈춘다.
                engine.stopSleeping()
                engine.renderActive = false
                panel.orderOut(nil)
            }
        }
    }

    /// 근무 종료 인사(꾸벅)를 재생하고, 워치독(최대 `farewellHideDeadline`)으로 패널을 내린다.
    /// 인사 동안 렌더 루프(renderActive)를 유지해 꾸벅이 실제로 보이게 하고, 숨긴 뒤 렌더를 멈춘다.
    private func beginFarewellHide() {
        farewellTask?.cancel()
        engine.request(.commuteEnd)
        farewellTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.farewellHideDeadline))
            self?.finishHide()
        }
    }

    /// 패널을 실제로 내린다(멱등). 인사 도중 다시 근무가 시작되면(shouldBeVisible==true) 숨기지 않는다.
    private func finishHide() {
        farewellTask?.cancel()
        farewellTask = nil
        guard !shouldBeVisible else { return }
        engine.renderActive = false
        panel.orderOut(nil)
    }

    // MARK: - 근무 시작 제안(넛지) — 안내만 하고 즉시 자동 시작(A3)

    /// 넛지 스케줄러를 현재 store 상태에 맞춰 가동/정지한다(비근무·로그인이면 가동, 아니면 정지·카운트 리셋).
    ///
    /// 팀 확정 여부는 여기서 따로 배선하지 않는다 — 스케줄러는 매 tick 마다 `isEligible()` 을 다시 물어
    /// 자격 미달이면 활성 누적을 0 으로 리셋하므로, 자격을 잃는 즉시 발동이 막히고 되찾으면 0 분부터
    /// 새로 센다. 자격 변화마다 start/stop 을 흔들 이유가 없다(루프 1개는 60초 주기 유휴).
    private func syncNudgeScheduler() {
        if store.isSignedIn && store.snapshot.isWorking == false {
            nudgeScheduler.start()
            nudgeSchedulerRunning = true
        } else {
            nudgeScheduler.stop()
            nudgeSchedulerRunning = false
        }
    }

    /// 넛지 발동 콜백: 물어보지 않고 즉시 근무를 시작한다. 자격을 재확인한 뒤, 등장 말풍선을 안내 문구로 1회
    /// 덮어쓸 오버라이드를 세팅하고 store.start() 를 호출한다. 이후 store 관찰 → updateWorking(true) 경로가
    /// 패널 표시 + commuteStart 리액션을 자연 처리하고, perform(.commuteStart)이 오버라이드를 소비한다.
    ///
    /// 원치 않는 시작을 되돌리는 수단은 평소와 같은 '근무 종료' 버튼 하나다 — 전용 되돌리기 UI 는 두지 않는다.
    func nudgeAutoStart() {
        guard isNudgeEligible else { return }
        // 말풍선 오버라이드는 캐릭터가 표시될 때만 세운다 — 숨김 상태에서 세워 두면 소비되지 않은 채 남아,
        // 몇 시간 뒤 사용자가 캐릭터를 다시 켜는 순간(commuteStart) 낡은 안내가 뒤늦게 튀어나온다.
        if store.isOverlayEnabled {
            engine.setCommuteStartBubbleOverride(
                text: Self.nudgeAutoStartText,
                seconds: Self.nudgeAutoStartBubbleSeconds
            )
        }
        store.start()
    }

    // MARK: - 때리면 아파하기 · 드래그 이동 · 클릭 통과 토글 (A1)

    /// 전역 mouseMoved 모니터를 켠다(패널 표시 중에만). 핸들러는 Task 를 만들지 않고 MainActor.assumeIsolated 로
    /// 동기 처리해 60Hz churn 을 피한다(전역 모니터 콜백은 메인 런루프에서 온다).
    private func installMouseMoveMonitor() {
        guard mouseMoveMonitor == nil else { return }
        panel.acceptsMouseMovedEvents = true
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateHitThrough(at: NSEvent.mouseLocation)
            }
        }
    }

    /// 전역 mouseMoved 모니터를 끄고, 드래그 상태와 클릭 통과를 초기 상태(통과)로 되돌린다(숨김 중 유실 대비).
    private func removeMouseMoveMonitor() {
        if let mouseMoveMonitor {
            NSEvent.removeMonitor(mouseMoveMonitor)
        }
        mouseMoveMonitor = nil
        isDragCandidate = false
        didDrag = false
        // 숨김/리셋 시 정면 복귀(드래그 중 숨겨져 mouseUp 이 유실돼도 방향이 남지 않게).
        engine.setDragFacing(0)
        facingHysteresis.reset()
        setIgnoresMouseEvents(true)
    }

    /// 커서(스크린 좌표)가 몸체 위면 클릭 통과를 해제(우리 창이 클릭을 받음), 아니면 통과로 되돌린다.
    /// 드래그 중(isDragCandidate)에는 토글하지 않는다(드래그 이벤트 수신이 끊기지 않게).
    ///
    /// (테스트 진입점이라 internal 이다 — 격발 중 이 문을 두드려도 값이 안 흔들린다는 U3 못 박기를
    ///  헤드리스로 실증하려면 밖에서 부를 수 있어야 한다.)
    func updateHitThrough(at screenPoint: NSPoint) {
        guard shouldBeVisible, !isDragCandidate else { return }
        setIgnoresMouseEvents(!engine.isBodyAtScreenPoint(screenPoint))
    }

    /// 커서가 호스팅 뷰(패널) 밖으로 나갔을 때: 통과로 되돌린다(이후엔 전역 모니터가 다시 감지). 드래그 중엔 유지.
    func restorePassThroughAfterExit() {
        guard !isDragCandidate else { return }
        setIgnoresMouseEvents(true)
    }

    /// 클릭 통과 여부를 == 가드로만 바꾼다(불필요한 창 속성 변경 churn 방지).
    ///
    /// **못 박기(pin)가 걸려 있으면 인자를 무시한다.** 울트라 격발 5초 동안은 클릭을 우리가 먹어야
    /// 화면이 실제로 막히는데(U3), 히트-스루 기계는 커서가 몸체 밖으로 나가는 순간 통과로 되돌리려 든다 —
    /// 화면을 덮은 거대 몸체에서는 그 판정이 프레임마다 뒤집혀 "막다 말다" 하는 최악이 된다.
    private func setIgnoresMouseEvents(_ ignore: Bool) {
        let value = pinnedIgnoresMouseEvents ?? ignore
        if panel.ignoresMouseEvents != value {
            panel.ignoresMouseEvents = value
        }
    }

    /// 클릭 통과 값을 못 박고 즉시 적용한다(nil 이면 못 박기 해제 — 이후 평소 토글로 돌아간다).
    private func pinIgnoresMouseEvents(_ value: Bool?) {
        pinnedIgnoresMouseEvents = value
        if let value, panel.ignoresMouseEvents != value {
            panel.ignoresMouseEvents = value
        }
    }

    /// 클릭/드래그 판정의 이중 안전 가드. 뷰가 attach 된 실사용에선 몸체(지오메트리) 위인지로 강화하고,
    /// 뷰 미부착(헤드리스 테스트)에선 패널 프레임 안인지로 폴백한다. 로컬 이벤트 경로라 사실상 몸체에서만 온다.
    ///
    /// 울트라 격발 중에는 항상 거짓이다. 격발은 클릭 통과를 못 박으므로(ignoresMouseEvents=true) 애초에
    /// 이벤트가 오지 않지만, 로컬 이벤트 경로가 한 프레임 먼저 도착하는 경우까지 막아 드래그 후보가
    /// 서지 않게 한다 — 화면만 한 패널이 드래그되면 saveOffset 이 전체화면 기준 오프셋을 영속해
    /// 사용자가 캐릭터를 두었던 자리가 영영 날아간다.
    private func withinBody(_ screenPoint: NSPoint) -> Bool {
        if isUltraActive { return false }
        return engine.hasAttachedView ? engine.isBodyAtScreenPoint(screenPoint) : panel.frame.contains(screenPoint)
    }

    /// 좌클릭 다운: 표시 중이고 몸체 위면 드래그 후보로 삼는다(리액션은 아직 발화하지 않고 업 시점에 판정).
    ///
    /// 격발 중에는 아예 받지 않는다. 받으면 화면만 한 패널이 드래그 후보가 되어 마우스를 따라 움직이고,
    /// 업 시점의 saveOffset 이 **전체화면 프레임 기준 오프셋**을 영속해 사용자가 캐릭터를 두었던 자리가
    /// 영영 날아간다. 클릭은 패널이 먹되(막는 게 목적) 아무 일도 일어나지 않는 것이 맞다.
    func handleMouseDown(at location: NSPoint) {
        guard shouldBeVisible, !isUltraActive, withinBody(location) else { return }
        isDragCandidate = true
        didDrag = false
        dragAnchor = location
        originAtDragStart = panel.frame.origin
        // 새 제스처는 정면에서 시작(전역 up 유실로 직전 방향이 남아 있어도 초기화). 기준점을 다운 지점으로 잡는다.
        engine.setDragFacing(0)
        facingHysteresis.begin(at: location.x)
    }

    /// 좌클릭 드래그: 후보일 때 이동량을 반영한다. 임계를 넘기면 이동 확정(didDrag)하고 패널을 따라 옮긴다
    /// (클램프로 화면 밖 이탈은 막는다).
    func handleMouseDragged(at location: NSPoint) {
        guard isDragCandidate else { return }
        let delta = NSPoint(x: location.x - dragAnchor.x, y: location.y - dragAnchor.y)
        if !didDrag, hypot(delta.x, delta.y) > Self.dragThreshold {
            didDrag = true
        }
        guard didDrag else { return }
        let proposed = NSPoint(x: originAtDragStart.x + delta.x, y: originAtDragStart.y + delta.y)
        let visible = currentVisibleFrame(near: location)
        panel.setFrameOrigin(Self.clampedOrigin(proposed, panelSize: Self.panelSize, in: visible))
        // 드래그 확정 후, 수평 이동 방향(히스테리시스)을 캐릭터가 바라보게 한다.
        engine.setDragFacing(facingHysteresis.update(x: location.x))
    }

    /// 좌클릭 업: 드래그 후보를 종료한다. 이동이 없었으면(클릭) 기존 handleClick 판정, 이동이 있었으면
    /// 위치만 옮기고 우상단 오프셋으로 영속한다.
    func handleMouseUp(at location: NSPoint) {
        guard isDragCandidate else { return }
        isDragCandidate = false
        if didDrag {
            saveOffset()
        } else {
            handleClick(at: location)
        }
        didDrag = false
        // 놓으면 정면 복귀.
        engine.setDragFacing(0)
        facingHysteresis.reset()
    }

    /// 클릭 좌표가 몸체 위면 리액션을 요청한다(좌표 주입 가능 — 테스트용).
    /// 자는 중이면 hit 대신 wake(화들짝 + "깜빡 졸았다!")로 깨우고, 아니면 평소처럼 아파하기(hit).
    func handleClick(at location: NSPoint) {
        // 격발 중 클릭은 삼킨다(조기 해제도, 때리기도 없다 — 막는 게 목적인데 첫 클릭에 사라지면 의미가 없다).
        guard shouldBeVisible, !isUltraActive, withinBody(location) else { return }
        if engine.state == .sleeping {
            // 자는 애를 깨우는 건 그 자체로 완결된 상호작용이다. 깨우면서 보드까지 열면 두 연출이 겹치고,
            // 사용자는 "깨우려던 것"과 "열려던 것" 중 무엇을 한 건지 알 수 없다. 다음 클릭이 보드를 연다.
            engine.request(.wake)
            return
        }
        // 할 일 기능을 켠 사람에게 클릭은 **보드 여닫기**이고, 끈 사람에게는 예전 그대로 **아파하기**다.
        // 한 클릭에 두 뜻을 담으면 움찔과 '보드 쪽 돌아보기'가 같은 0.5초 안에서 부딪친다 —
        // 설정으로 가르면 각자에게 클릭의 뜻은 언제나 하나뿐이라 헷갈릴 여지가 없다.
        if onCharacterTapped?() == true { return }
        engine.request(.hit)
    }

    // MARK: - 밤샘 졸기 스케줄러

    private func startDrowsyScheduler() {
        guard drowsyTask == nil else { return }
        drowsyTask = Task { @MainActor [weak self] in
            var rng = SystemRandomNumberGenerator()
            while !Task.isCancelled {
                let interval = DrowsyWindow.nextInterval(using: &rng)
                // 졸기 진입은 정밀할 필요가 없으므로 tolerance 를 둬 타이머 coalescing(전력 절감)을 허용한다.
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                // 업데이트 감지 편승: 팝오버가 하루 1회 킥해 채워 둔 공유 상태를 읽어, 표시 중 새 버전이면
                // 버전당 1회 말풍선을 띄운다(네트워크는 새로 치지 않음 — 상시 루프/유휴 타이머 신설 금지).
                // 이번 tick 에 업데이트 말풍선을 띄웠으면 졸기는 건너뛴다(말풍선 채널 충돌 방지).
                if self.showUpdateBubbleIfNeeded() { continue }
                // 판정은 아래 프로퍼티 하나로 모은다 — 40~80분마다 한 번 도는 루프 안에 조건을 묻어 두면
                // 그 조건이 맞는지 아무도 검증할 수 없다(테스트가 그 루프를 기다릴 수 없으므로).
                guard self.canEnterDrowsy else { continue }
                self.engine.request(.drowsy)
            }
        }
    }

    /// 지금 졸아도 되는가(헤드리스 검증 지점). 조건은 셋이다:
    ///  · 표시 중(근무중 + 캐릭터 켬) — 안 보이는데 자는 건 의미가 없다,
    ///  · 다른 리액션이 없다 — 연출 도중 잠들면 그 연출이 끊긴다,
    ///  · **보드가 닫혀 있다** — 할 일을 보며 생각하는 동안 눈을 감으면 "얘 죽었나"로 읽힌다.
    var canEnterDrowsy: Bool {
        shouldBeVisible && engine.state == .idle && !(isBoardOpen?() ?? false)
    }

    private func stopDrowsyScheduler() {
        drowsyTask?.cancel()
        drowsyTask = nil
    }

    // MARK: - 깜빡임 스케줄러

    /// 표시 중일 때만 3~7초마다 한 번 깜빡인다. 엔진이 idle 이 아니면(자는 중·리액션 중) 스스로 물러나므로
    /// 여기서는 표시/격발 여부만 본다. tolerance 를 크게 둬 타이머 coalescing(전력 절감)을 허용한다 —
    /// 깜빡임은 정확한 시각이 의미 없는 앰비언트 연출이다.
    private func startBlinkScheduler() {
        guard blinkTask == nil else { return }
        blinkTask = Task { @MainActor [weak self] in
            var rng = SystemRandomNumberGenerator()
            while !Task.isCancelled {
                let interval = Double.random(in: CheckOverlayController.blinkIntervalRange, using: &rng)
                try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                // 전체화면 격발 중엔 깜빡이지 않는다 — 5초 연출의 표정을 건드리지 않는다.
                guard self.shouldBeVisible, !self.isUltraActive else { continue }
                self.engine.blink()
            }
        }
    }

    private func stopBlinkScheduler() {
        blinkTask?.cancel()
        blinkTask = nil
    }

    // MARK: - 업데이트 넛지 말풍선 (버전당 1회)

    /// 표시 중(근무중)·idle 이고, 감지된 새 버전에 대해 아직 말풍선을 안 띄웠으면 1회 띄우고 true 를 돌려준다.
    /// 조건 미충족이면 false(졸기 등 다음 로직으로 진행). shouldShowBubble 은 영속 기록으로 버전당 1회를 보장한다.
    @discardableResult
    func showUpdateBubbleIfNeeded() -> Bool {
        guard let updateCheck, shouldBeVisible, engine.state == .idle else { return false }
        guard updateCheck.shouldShowBubble() else { return false }
        updateCheck.markBubbleShown()
        engine.showBubble(Self.updateBubbleText, seconds: Self.updateBubbleSeconds)
        return true
    }

    // MARK: - 콕찌르기 수신(움찔 + 말풍선, 숨김 시 peek)

    /// 수신 찔림 배치를 하나의 말풍선 문구로 조합한다(순수 함수 — 테스트 가능). 1명이면 "…님이 콕 찔렀어요!",
    /// 2명 이상이면 "<첫이름>님 외 N명이 콕 찔렀어요!"(중복 이름은 유지, 첫 번째는 배치 순서 첫 이름).
    nonisolated static func pokeBubbleText(names: [String]) -> String {
        guard let first = names.first else { return "" }
        if names.count == 1 {
            return "\(first)님이 콕 찔렀어요!"
        }
        return "\(first)님 외 \(names.count - 1)명이 콕 찔렀어요!"
    }

    /// 스토어가 신선도 필터를 끝내 전달한 수신 찔림 배치를 표시한다(배치당 움찔 1회 + 말풍선 1개).
    /// 표시 중이면 즉시 움찔, 숨김이면 peek(잠깐 나타났다 사라짐 — 캐릭터 표시를 꺼 뒀어도 동일).
    func handleReceivedPokes(_ pokes: [ReceivedPoke]) {
        guard !pokes.isEmpty else { return } // 빈 배치 무시.
        // 같은 폴링에 울트라가 2건 와도 격발은 1회다 — 첫 울트라가 배치 전체를 대표한다.
        // 캐릭터 표시를 꺼 뒀어도 전체화면 격발은 그대로 재생한다(사용자 결정: 강등하지 않는다).
        if let ultra = pokes.first(where: { $0.kind == .ultra }) {
            beginUltraTakeover(text: Self.ultraBubbleText(name: ultra.fromName, otherCount: pokes.count - 1))
            return
        }
        // 격발 중 도착한 일반 찔림은 여기서 삼킨다. 전체화면 발광 위에 작은 움찔·다른 말풍선을 겹치면
        // 화면만 어지럽고, 엔진도 우선순위(4 > 3)로 어차피 거부한다 — 상태를 흔들기 전에 먼저 막는다.
        if isUltraActive { return }
        let text = Self.pokeBubbleText(names: pokes.map { $0.fromName })
        if shouldBeVisible && panel.isVisible {
            // 정상 표시 중: 움찔+말풍선만(정상 경로가 창 수명을 소유). request 는 진행 중 찌름을 인터럽트해 갱신한다.
            engine.request(.poked(bubbleText: text))
        } else {
            beginPokePeek(text: text)
        }
    }

    // MARK: - 울트라 찌르기 수신(전체화면 격발 5초)

    /// 울트라 말풍선 문구(순수 함수). 같은 배치에 일반 찔림이 섞여 있으면 인원수만 덧붙인다.
    nonisolated static func ultraBubbleText(name: String, otherCount: Int) -> String {
        otherCount > 0 ? "\(name)님의 울트라 찌르기! (외 \(otherCount)명)" : "\(name)님의 울트라 찌르기!"
    }

    /// 울트라가 덮을 패널 프레임(순수 함수). **visibleFrame 이 아니라 frame 이다** — 요구는 "화면 정중앙을
    /// 싹 덮는다"이고 visibleFrame 을 쓰면 메뉴바·독 자리만큼 중심이 밀려 정중앙에 안 선다.
    /// 메뉴바/독은 우리(.floating)보다 높은 레벨이라 frame 을 써도 그것들을 '가리는' 부작용은 없고,
    /// 오히려 메뉴바 아이콘이 살아 있어 클릭을 막는 5초 안에도 사용자의 탈출로가 남는다.
    nonisolated static func ultraPanelFrame(in screenFrame: NSRect) -> NSRect { screenFrame }

    /// 울트라 전 프레임으로 되돌릴 수 있는가(그 프레임이 아직 어떤 화면과 겹치는가). 5초 사이에 모니터를
    /// 뽑거나 해상도가 바뀌면 저장 프레임이 허공을 가리키므로, 겹침이 없으면 기본 재배치로 떨어진다.
    /// 이 판정이 없으면 캐릭터가 존재하지 않는 좌표로 복귀해 재실행 전까지 영영 안 보인다.
    nonisolated static func canRestore(frame: NSRect, screens: [NSRect]) -> Bool {
        screens.contains { $0.intersects(frame) }
    }

    /// 울트라 수신: 패널을 화면 전체로 넓히고 5초간 발광시킨 뒤 **정확히 원래대로** 되돌린다.
    /// 캐릭터 표시를 꺼 둔 사용자에게도 재생한다 — take_pokes 가 이미 원자 소비했고 보낸이는 하루치 몫을
    /// 태웠으므로 여기서 버리면 영영 사라진다(강등하지 않는다는 사용자 결정).
    private func beginUltraTakeover(text: String) {
        // 보드는 격발 시작과 함께 화면에서 비킨다(전체화면 연출 위에 겹칠 수 없다). 입력 중이던 글은
        // 보드 컨트롤러가 들고 있으므로 사라지지 않는다 — 그래서 여기서 닫아도 안전하다.
        onUltraBegan?()
        let isRefresh = isUltraActive
        ultraTask?.cancel()
        // peek 이 소유하던 지연 퇴장은 무효 — 울트라가 창 수명을 가져간다(안 끄면 8초 뒤 peek 의
        // orderOut 이 뒤늦게 끼어들어 격발 중인 전체화면을 지운다).
        pokePeekTask?.cancel(); pokePeekTask = nil
        // ★ farewell 워치독도 반드시 끈다. 직접 누른 근무 종료는 flushPokesOnWorkEnd 로 꼬리 찔림을 한 번 더
        //   회수하는데, 그 응답이 0.55초(farewellHideDeadline) 안에 오면 여기서 전체화면을 띄운 직후
        //   finishHide 가 orderOut 해 5초짜리 울트라가 0.5초 만에 지워진다 — 보낸 사람의 몫이 그대로 증발한다.
        farewellTask?.cancel(); farewellTask = nil
        // 드래그 중에 울트라가 오면 아래 removeMouseMoveMonitor 가 isDragCandidate 를 내려 handleMouseUp
        // 가드가 막히고 saveOffset 이 영영 안 불린다 → 방금 옮긴 자리가 영속되지 않아 다음 reposition 에서
        // 원위치로 튄다.
        if isDragCandidate && didDrag { saveOffset() }

        // ★ 마감의 기준 시각은 화면을 덮기 **직전**에 잡는다. 아래 `panel.setFrame` 은 3D 뷰가 한 번도
        //   마운트되지 않은 경로(캐릭터를 꺼 둔 사용자에게 울트라가 오는 배달 계약 — 바로 아래 doc 참고)에서
        //   USDZ 로드 + 감은눈 텍스처 생성을 **동기로** 돌려 메인 스레드를 멈춘다(같은 머신 실측:
        //   release 0.130s / debug 3.456s). 마감을 그 뒤에 잡으면 블로킹 시간만큼 상한이 통째로 밀려
        //   실측 총 8.68초 — "격발은 최대 ultraSeconds + grace" 라는 계약이 느린 기기에서만 조용히 깨진다.
        let takeoverStart = Date()

        if !isRefresh {
            ultraRestoreState = UltraRestoreState(frame: panel.frame, hadMouseMonitor: mouseMoveMonitor != nil)
            // A1 히트-스루 기계를 떼고(60Hz 토글 중단) 클릭 통과를 **true 로 못 박는다** = 가리되 막지 않는다.
            //
            // 한때 false(패널이 클릭을 먹어 화면을 실제로 막음)로 두었다가 되돌렸다. 실사용 확인 결과
            // 화면만 한 패널이 이벤트를 먹으면 **캐릭터 뒤만이 아니라 화면 전체**의 클릭과 **스크롤까지**
            // 5초 동안 죽는다 — 연출 하나가 남의 작업을 통째로 멈추는 것은 과하다는 판단.
            // 못 박기 자체는 그대로 필요하다: 화면을 덮은 거대 몸체 위에서 updateHitThrough 는 커서 위치마다
            // 값을 뒤집어 "막다 말다" 하는 최악을 만든다. 값만 반대로, 고정은 유지한다.
            removeMouseMoveMonitor()
            pinIgnoresMouseEvents(true)
            engine.invalidateBodyHitCache()   // 뷰 크기가 바뀌면 캐시된 투영 rect 는 옛 좌표계의 거짓말이다
            engine.isUltraActive = true
            engine.renderActive = true
            // ★ display: **false** 여야 한다. true 면 AppKit 이 여기서 표시 패스를 강제하고, 그 패스가
            //   SwiftUI 루트 뷰를 평가해 `.onChange(of: store.snapshot.isWorking, initial: true)` 를
            //   **이 함수 한복판에서 되부른다** → onWorkingChange → updateWorking → endUltraTakeover.
            //   즉 방금 세운 격발이 자기 자신의 그리기 때문에 즉시 철거되고(프레임·못박기·엔진 전부 원복),
            //   보낸 사람은 하루 몫을 태운 채 아무 일도 일어나지 않는다. 프레임 값은 이 줄에서 이미
            //   확정되고 다시 그리는 것만 다음 런루프로 밀리므로(한 프레임), 5초짜리 연출에는 무해하다.
            panel.setFrame(Self.ultraPanelFrame(in: ultraScreenFrame()), display: false)
            panel.orderFrontRegardless()
        }
        engine.request(.ultraPoked(bubbleText: text))
        armUltraRestore(startedAt: takeoverStart)
    }

    /// 정상 원복 타이머 + **독립 워치독**을 함께 건다(재수신이면 둘 다 리셋 = 5초 재시작).
    ///
    /// 두 태스크를 나누는 이유: 격발은 화면을 막으므로 원복 실패가 곧 "사용자가 화면을 잃는" 사고다.
    /// 한 태스크만 두면 그 태스크의 취소·유실이 곧 영구 차단이다. 워치독은 deadline 이라는 **값**을 보고
    /// 판정하므로(태스크 상태가 아니라), 늦게 깨어나도 반드시 걷어낸다.
    ///
    /// `start` 는 **격발이 시작된 시각**이다(이 함수가 불린 시각이 아니다 — beginUltraTakeover 주석 참고).
    ///
    /// 재수신마다 마감이 뒤로 밀리는 것에 **총 상한을 두지 않는다**(예: 최초 시작 + 15초). 근거 셋:
    ///  ① 격발은 가리기이지 막기가 아니다(클릭 통과를 true 로 못 박는다) — 오래 덮여도 사용자가 화면을
    ///     잃지 않는다. 즉 상한이 막아 줄 '치명 사고'가 없다.
    ///  ② 상한은 마지막 보낸이의 하루 몫을 0.x초로 잘라 **복구되지 않는 손실**을 만든다. 이 파일이
    ///     재통지·farewell 워치독·peek 퇴장을 하나씩 막아 온 이유가 전부 그 손실을 막기 위해서였다.
    ///  ③ 상한이 걷힌 직후 도착한 울트라는 **새 격발**을 시작하므로 릴레이 자체를 막지도 못한다 —
    ///     얻는 것은 짧은 '숨' 한 번뿐이다.
    /// 격발이 다시 클릭을 먹게 되면(=①이 무너지면) 그때는 총 상한을 반드시 둔다.
    private func armUltraRestore(startedAt start: Date) {
        ultraGeneration &+= 1
        let generation = ultraGeneration
        let deadline = start.addingTimeInterval(ultraDeadlineSeconds)
        ultraDeadline = deadline
        let duration = ultraDurationSeconds
        // 워치독은 고정 상수가 아니라 **마감까지 남은 시간**만 잔다. 고정 상수로 자면 마감을 앞당겨 잡아 봐야
        // 실제 원복은 (블로킹 시간 + 상수) 뒤라 상한이 그대로 밀린다 — 마감을 '기록'만 하고 '집행'하지 않는 꼴.
        // 마운트 블로킹이 이미 마감을 넘겼다면 0 이 되어 즉시 걷는다. 그 지경이면 앱이 이미 수 초 얼어 있었고,
        // "격발은 최대 6초"라는 계약이 연출보다 우선한다.
        let remaining = max(0, deadline.timeIntervalSinceNow)

        ultraTask?.cancel()
        ultraTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            self.endUltraTakeover()
        }

        ultraWatchdogTask?.cancel()
        ultraWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            // 세대 검사가 취소 검사를 대신한다. 재수신으로 갈아탄 뒤 취소된 옛 워치독은 즉시 깨어나므로
            // Task.isCancelled 를 무시하면 방금 시작한 격발을 잘라먹는다 — 세대가 다르면 조용히 물러난다.
            guard let self, self.ultraGeneration == generation, self.isUltraActive else { return }
            // 이 세대의 지속+여유는 (연속 시계 기준) 확실히 지났다. 마감 시각 판정을 먼저 태우고,
            // 벽시계가 뒤로 조정된 극단에서 그 판정이 false 를 내더라도 **무조건** 걷어낸다 —
            // 여기서 물러나면 화면이 영영 덮인 채 남는다(이 기능의 유일한 치명 사고 모드다).
            if !self.enforceUltraDeadline(now: Date()) {
                self.endUltraTakeover()
            }
        }
    }

    /// 마감 시각이 지났으면 격발을 강제로 걷는다(멱등, 순수 판정). 워치독이 부르고, 테스트가 '정상 타이머가
    /// 죽은 세계'를 재현하려고 미래 시각으로 직접 부른다. 마감 전이면 아무것도 하지 않는다.
    @discardableResult
    func enforceUltraDeadline(now: Date) -> Bool {
        guard let deadline = ultraDeadline, isUltraActive, now >= deadline else { return false }
        endUltraTakeover()
        return true
    }

    /// 격발을 끝내고 엔진 → 프레임 → 클릭통과 → 마우스 모니터 → 표시 여부 순으로 되돌린다.
    /// **이 순서가 중요하다** — 프레임을 되돌리기 전에 모니터를 켜면 그 한 프레임 동안 거대 몸체 판정으로
    /// 클릭을 먹는다. restoresVisibility=false 는 updateWorking 전용이다(그 직후 호출자가 표시 여부를 정한다).
    func endUltraTakeover(restoresVisibility: Bool = true) {
        ultraTask?.cancel(); ultraTask = nil
        ultraWatchdogTask?.cancel(); ultraWatchdogTask = nil
        ultraDeadline = nil
        // ★ 안전밸브: 못 박기 해제는 **guard 보다 위**다. 못 박기만 걸린 채 복원 상태가 없어지는 경로가
        //   하나라도 생기면 화면이 영영 클릭을 먹는다 — 격발의 유일한 치명 사고 모드다. 못 박기가
        //   안 걸려 있으면 아무것도 하지 않는다(평시 히트-스루 값을 여기서 건드리면 커서가 몸체 위에
        //   있는 동안의 클릭 수신이 깨진다).
        if pinnedIgnoresMouseEvents != nil {
            pinIgnoresMouseEvents(nil)
            setIgnoresMouseEvents(true)
        }
        guard let restore = ultraRestoreState else { return }
        ultraRestoreState = nil
        // 프레임을 줄이기 **전에** 엔진을 idle 로 못 박는다. 5초 Task 깨어남과 clock 만료(expireIfNeeded)는
        // 밀리초 차이라, 아직 .playing(.ultraPoked) 인 채로 뷰가 크기를 바꾸면 attach 의 .playing 분기가
        // 5초짜리 격발을 작은 패널에서 처음부터 다시 재생한다.
        // interruptCurrent 의 resetPose 가 포즈까지 identity 로 스냅해 잔상도 함께 지운다.
        engine.cancelActiveReaction()
        engine.isUltraActive = false
        engine.invalidateBodyHitCache()

        if Self.canRestore(frame: restore.frame, screens: NSScreen.screens.map(\.frame)) {
            // display: false 인 이유는 beginUltraTakeover 와 같다 — 표시 패스를 여기서 강제하면 SwiftUI
            // `.onChange` 가 원복 도중에 updateWorking 을 되불러, 방금 되돌린 프레임 위에 숨김 분기
            // (removeMouseMoveMonitor·orderOut)가 겹친다. 프레임 값은 이 줄에서 확정된다.
            panel.setFrame(restore.frame, display: false)
        } else {
            reposition()   // 5초 사이 모니터가 빠졌다 — 저장 오프셋으로 기본 위치 재계산.
        }
        guard restoresVisibility else {
            // 근무 종료 경로다. 캐릭터를 되살리지 않으므로 보드도 되살리지 않는다(호출자가 표시를 정한다).
            onUltraEnded?(false)
            return
        }
        if shouldBeVisible {
            panel.orderFrontRegardless()
            if restore.hadMouseMonitor { installMouseMoveMonitor() }   // 때리기·드래그 복원
        } else {
            // 울트라 전에 숨김이었다(비근무 또는 캐릭터 표시 꺼짐) → 그대로 다시 숨긴다. peek 퇴장과 동일 계약.
            engine.greetingText = nil
            engine.renderActive = false
            panel.orderOut(nil)
        }
        // 복원 사슬의 **맨 끝**이다. 캐릭터 프레임이 제자리로 돌아온 뒤라야 보드가 그 옆 정확한 자리로 돌아간다.
        onUltraEnded?(true)
    }

    /// 울트라를 어느 화면에 띄울지. **패널이 지금 놓인 화면**이다 — 사용자가 캐릭터를 끌어다 둔 그 화면이
    /// 이 앱에 대한 시선의 기준점이고, NSScreen.main 은 키 윈도우가 없는 메뉴바 앱에서 무엇을 돌려줄지
    /// 계약이 불분명하다(reposition 이 그걸 쓰는 건 '기본 위치'라는 약한 요구라 문제가 없었을 뿐이다).
    private func ultraScreenFrame() -> NSRect {
        currentScreen(near: NSPoint(x: panel.frame.midX, y: panel.frame.midY))?.frame ?? panel.frame
    }

    /// 숨김 상태(비근무)에서 찔림을 잠깐 보여준다: 렌더를 켜고 우상단에 띄워 움찔+말풍선을 재생한 뒤,
    /// pokePeekSeconds 후 그 사이 정상 표시로 승격되지 않았으면 말풍선을 정리하고 다시 숨긴다.
    ///
    /// updateWorking 경로를 타지 않으므로 mouseMove 모니터/졸기·넛지 스케줄러가 켜지지 않는다 — peek 는 마우스를
    /// 받지 않는 순수 시각 토스트다. peek 도중 또 배치가 오면 기존 타이머를 리셋하고 새 움찔+문구로 갱신한다.
    /// engine 미-attach(12시간 미접속 후 실행 직후 등) 상태여도 request(.poked)→perform 이 말풍선은 띄우고
    /// 움찔(runReaction)만 자연 no-op 이 된다.
    ///
    /// 캐릭터 표시를 꺼 둔 사용자(isOverlayEnabled=false)에게도 peek 는 그대로 재생한다(v0.2.7 계약).
    /// take_pokes RPC 가 이미 원자적으로 소비한 찔림이라 여기서 버리면 영영 사라지고, 보낸 쪽은 성공 처리되어
    /// 쿨타임만 태운 채 수신자에게는 아무 일도 일어나지 않는다 — 그래서 표시 설정과 무관하게 8초만 보여 준다.
    private func beginPokePeek(text: String) {
        pokePeekTask?.cancel()
        engine.renderActive = true
        reposition()
        panel.orderFrontRegardless()
        engine.request(.poked(bubbleText: text))
        pokePeekTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.pokePeekSeconds))
            guard let self, !Task.isCancelled else { return }
            self.pokePeekTask = nil
            // 그 사이 근무 시작 등으로 정상 표시가 됐으면 정상 경로가 창을 소유하므로 아무것도 하지 않는다.
            guard !self.shouldBeVisible else { return }
            self.engine.greetingText = nil
            self.engine.renderActive = false
            self.panel.orderOut(nil)
        }
    }

    /// 저장된 우상단 오프셋이 있으면 그 위치(클램프 보정)로, 없으면 메인 스크린 visibleFrame 우상단
    /// (여백 `edgeMargin`)으로 패널을 옮긴다.
    func reposition() {
        // ★ 격발 중에는 절대 140×170 으로 줄이지 않는다. 이 함수는 화면 구성 변경 통지(모니터 연결·해상도
        //   변경·독 자동숨김 토글)로도 불리는데, 그게 5초 안에 오면 패널만 구석으로 쪼그라들고
        //   isUltraActive 는 true 로 남아 **작은 창에 거대 레이아웃과 큰 말풍선이 갇힌다**(실측 재현).
        //   그냥 물러나지 않고 새 화면 기준으로 **다시 덮는** 이유: 모니터가 바뀌었다면 지금 캐릭터가 놓인
        //   그 화면을 덮는 것이 원래 의도이고(ultraScreenFrame 이 폴백 사슬을 다시 태워 사라진 화면도 흡수),
        //   물러나기만 하면 옛 화면 좌표에 걸친 프레임이 5초 내내 남는다.
        //   display:false 인 이유는 beginUltraTakeover 와 같다 — 표시 패스를 강제하면 SwiftUI 재통지가
        //   격발 한복판에서 updateWorking 을 되부른다.
        if isUltraActive {
            panel.setFrame(Self.ultraPanelFrame(in: ultraScreenFrame()), display: false)
            engine.invalidateBodyHitCache()   // 뷰 크기가 바뀌면 캐시된 투영 rect 는 옛 좌표계의 거짓말이다
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = Self.overlayFrame(
            offset: loadOffset(),
            in: screen.visibleFrame,
            size: Self.panelSize,
            margin: Self.edgeMargin
        )
        panel.setFrame(frame, display: shouldBeVisible)
        // 캐릭터가 움직였으면 보드도 따라온다. 여기서 알리지 않으면 모니터를 바꾼 뒤 보드만 옛 좌표에 남는다.
        onCharacterFrameChanged?(frame)
    }

    // MARK: - 위치 영속 (우상단 앵커 오프셋)

    /// 현재 패널 위치를 '패널이 놓인 화면 visibleFrame 우상단으로부터의 오프셋'으로 저장한다.
    /// 우상단 기준이라 해상도·배열이 바뀌어도 '우상단 근처' 의미가 보존된다.
    private func saveOffset() {
        let frame = panel.frame
        let visible = currentVisibleFrame(near: NSPoint(x: frame.midX, y: frame.midY))
        let dx = Double(visible.maxX - frame.maxX)
        let dy = Double(visible.maxY - frame.maxY)
        defaults.set([dx, dy], forKey: Self.overlayOffsetKey)
    }

    /// 저장된 우상단 오프셋([dx, dy])을 읽는다. 없거나 형식이 어긋나면 nil(기본 위치로 폴백).
    private func loadOffset() -> [Double]? {
        guard let raw = defaults.array(forKey: Self.overlayOffsetKey) as? [Double], raw.count == 2 else {
            return nil
        }
        return raw
    }

    /// 커서(또는 패널)가 놓인 화면을 고른다. 커서가 어느 화면에도 없으면 패널과 가장 많이 겹치는 화면을,
    /// 그것도 없으면 메인 화면을 쓴다.
    ///
    /// 울트라가 '캐릭터가 있는 화면'을 찾을 때 같은 폴백 사슬을 쓰려고 `currentVisibleFrame` 에서 뽑아냈다.
    /// **사슬을 한 글자도 바꾸지 않는다** — 바꾸면 드래그 클램프가 조용히 달라진다.
    private func currentScreen(near point: NSPoint) -> NSScreen? {
        let screens = NSScreen.screens
        if let hit = screens.first(where: { $0.frame.contains(point) }) {
            return hit
        }
        let panelFrame = panel.frame
        var best: NSScreen?
        var bestArea: CGFloat = -1
        for screen in screens {
            let inter = screen.frame.intersection(panelFrame)
            let area = inter.isNull ? 0 : inter.width * inter.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best ?? NSScreen.main ?? screens.first
    }

    /// 커서(또는 패널)가 놓인 화면의 visibleFrame. 화면을 못 찾으면 패널 프레임으로 떨어진다.
    private func currentVisibleFrame(near point: NSPoint) -> NSRect {
        currentScreen(near: point)?.visibleFrame ?? panel.frame
    }

    /// 화면 구성 변경(해상도·배열·메뉴바 높이 등) 시 우상단 위치를 다시 잡는다.
    private func observeScreenChanges() {
        screenObserver = notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    /// visibleFrame 우상단에 `size` 크기, 가장자리 `margin` 여백으로 놓일 프레임을 계산한다(순수 함수).
    ///
    /// 맥 좌표계는 아래가 minY라 상단 정렬은 `maxY`(메뉴바 바로 아래) 기준으로 잡는다.
    nonisolated static func overlayFrame(in visibleFrame: NSRect, size: NSSize, margin: CGFloat) -> NSRect {
        let x = visibleFrame.maxX - size.width - margin
        let y = visibleFrame.maxY - size.height - margin
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// 저장된 우상단 오프셋(`offset`=[dx, dy])이 있으면 visibleFrame 우상단에서 그만큼 안쪽에 놓고 클램프한다.
    /// 오프셋이 없거나 형식이 어긋나면 기본 우상단(여백 `margin`)으로 떨어진다(순수 함수).
    nonisolated static func overlayFrame(
        offset: [Double]?,
        in visibleFrame: NSRect,
        size: NSSize,
        margin: CGFloat
    ) -> NSRect {
        guard let offset, offset.count == 2 else {
            return overlayFrame(in: visibleFrame, size: size, margin: margin)
        }
        let x = visibleFrame.maxX - CGFloat(offset[0]) - size.width
        let y = visibleFrame.maxY - CGFloat(offset[1]) - size.height
        let origin = clampedOrigin(NSPoint(x: x, y: y), panelSize: size, in: visibleFrame)
        return NSRect(origin: origin, size: size)
    }

    /// `origin`(패널 좌하단)으로 놓인 패널 프레임 전체가 visibleFrame 안에 들도록 min/max 로 당긴 origin 을
    /// 돌려준다(순수 함수). 패널이 화면보다 큰 극단에서는 좌하단 정렬(minX/minY)을 우선한다.
    nonisolated static func clampedOrigin(_ origin: NSPoint, panelSize: NSSize, in visibleFrame: NSRect) -> NSPoint {
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
        let x = min(max(origin.x, visibleFrame.minX), maxX)
        let y = min(max(origin.y, visibleFrame.minY), maxY)
        return NSPoint(x: x, y: y)
    }

    /// 클릭 통과·항상 위·전(全) Space/전체화면 유지·투명 배경으로 설정된 오버레이 패널을 만든다.
    static func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // 클릭 통과 — 작업 방해 금지의 핵심.
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        // Space 전환/전체화면 앱 위에서도 유지, 창 순환(⌘`)에서 제외.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // 화면 공유·녹화에서 제외한다. 울트라는 화면 전체를 5초 덮는데, 발표·화상회의 중 근무자라면 그 장면이
        // 상대(클라이언트 포함)에게 그대로 중계된다 — 수신자가 막을 수단이 없으므로 최소한 캡처에는 안 잡히게 한다.
        panel.sharingType = .none
        return panel
    }
}

/// 캐릭터 "몸체" 위 클릭만 우리 창이 소비하도록 gate 하고, 로컬 마우스 이벤트를 컨트롤러로 넘기는 NSHostingView
/// 서브클래스(A1).
///
/// - hitTest: 주입된 `bodyHitTest`(화면 좌표 → 몸체 여부)가 true 인 지점만 super.hitTest(뷰 반환)로 클릭을
///   받고, 밖이면 nil 을 돌려 뒤(작업 창)로 통과시킨다(테스트 결정성을 위해 판정은 주입 클로저). `bodyHitTest`
///   가 없으면(초기/미배선) 항상 통과 — SCNView 지연 마운트로 몸체 판정이 불가능한 동안 안전.
/// - 마우스 이벤트: mouseDown/Dragged/Up 은 스크린 좌표(NSEvent.mouseLocation) 기반 컨트롤러 핸들러로 넘긴다
///   (기존 드래그 임계·오프셋 로직 재사용). ignoresMouseEvents=false 인 동안엔 전역 모니터가 자기 창 위 이동을
///   못 보므로, NSTrackingArea 의 mouseMoved/mouseExited 로 몸체 이탈을 감지해 컨트롤러가 통과로 되돌리게 한다.
final class CharacterHitTestingView<Content: View>: NSHostingView<Content> {
    /// 화면 좌표가 캐릭터 몸체 위인지 판정하는 주입 클로저. nil 이면 항상 통과(클릭 소비 안 함).
    var bodyHitTest: ((NSPoint) -> Bool)?
    var onMouseDown: ((NSPoint) -> Void)?
    var onMouseDragged: ((NSPoint) -> Void)?
    var onMouseUp: ((NSPoint) -> Void)?
    /// 트래킹 영역 내 mouseMoved(스크린 좌표). ignoresMouseEvents=false 동안의 몸체 이탈 감지에 쓴다.
    var onMouseMovedInside: ((NSPoint) -> Void)?
    /// 커서가 뷰 밖으로 나감. 통과 복원에 쓴다.
    var onMouseExited: (() -> Void)?

    private var bodyTrackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let bodyHitTest, let window else { return nil }
        // hitTest 의 point 는 window 콘텐츠(base) 좌표 — borderless 패널은 contentView 가 창을 꽉 채워 동일하다.
        let screenPoint = window.convertPoint(toScreen: point)
        return bodyHitTest(screenPoint) ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let bodyTrackingArea {
            removeTrackingArea(bodyTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        bodyTrackingArea = area
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?(NSEvent.mouseLocation) }
    override func mouseUp(with event: NSEvent) { onMouseUp?(NSEvent.mouseLocation) }
    override func mouseMoved(with event: NSEvent) { onMouseMovedInside?(NSEvent.mouseLocation) }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 드래그 수평 방향 판정(히스테리시스, 순수 로직). 직전 판정 지점 대비 누적 수평 이동이 `threshold` 를 넘을 때만
/// 방향을 갱신해 미세 떨림에 캐릭터가 홱홱 돌지 않게 한다. 컨트롤러가 이 판정을 엔진 setDragFacing 으로 잇는다.
struct DragFacingHysteresis {
    /// 방향을 바꾸는 최소 수평 이동(pt).
    static let threshold: CGFloat = 3

    private var referenceX: CGFloat?
    private(set) var direction = 0

    /// 드래그 시작 시 기준점을 다운 지점으로 잡는다(첫 수평 이동부터 방향 판정이 되도록). 방향은 정면.
    mutating func begin(at x: CGFloat) {
        referenceX = x
        direction = 0
    }

    /// 드래그 종료/숨김 시 초기화(기준점 비움 + 정면).
    mutating func reset() {
        referenceX = nil
        direction = 0
    }

    /// 현재 마우스 x 를 반영하고 방향(-1 왼쪽 / 0 정면 / +1 오른쪽)을 돌려준다. 기준점 대비 ±threshold 초과 시
    /// 그 부호로 방향을 바꾸고 기준점을 현재 x 로 옮긴다(다음 반전은 여기서 다시 threshold 만큼 필요 — 히스테리시스).
    mutating func update(x: CGFloat) -> Int {
        guard let ref = referenceX else {
            referenceX = x
            return direction
        }
        let dx = x - ref
        if dx > Self.threshold {
            direction = 1
            referenceX = x
        } else if dx < -Self.threshold {
            direction = -1
            referenceX = x
        }
        return direction
    }
}
