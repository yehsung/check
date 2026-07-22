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

    /// 새 버전 감지 시 캐릭터가 띄우는 말풍선 문구/지속시간. 버전당 1회만(도배 금지).
    static let updateBubbleText = "새 업데이트가 있어요!"
    static let updateBubbleSeconds: Double = 6

    let panel: NSPanel
    /// 리액션 조율기. 표시 중일 때만 이벤트를 받아 캐릭터 wrapper 에 SCNAction 을 건다.
    let engine: ReactionEngine
    /// 표시 의도 상태. 헤드리스 환경에서도 결정적으로 검증할 수 있는 지점(실제 표시 여부는 `panel.isVisible`).
    private(set) var shouldBeVisible = false

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

    init(
        store: WorkTimerStore,
        notificationCenter: NotificationCenter = .default,
        engine: ReactionEngine? = nil,
        defaults: UserDefaults = .standard,
        workspaceNotifications: NotificationCenter? = NSWorkspace.shared.notificationCenter,
        updateCheck: UpdateCheckStore? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.store = store
        self.defaults = defaults
        self.updateCheck = updateCheck
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

        // 넛지 스케줄러: 자격은 store 로 구성(로그인·팀·비근무·오버레이 켜짐), 발동은 자동 근무 시작(안내만)으로.
        nudgeScheduler = NudgeScheduler(
            isEligible: { [weak self] in self?.isNudgeEligible ?? false },
            onNudge: { [weak self] in self?.nudgeAutoStart() },
            workspaceNotifications: workspaceNotifications
        )

        reposition()
        observeScreenChanges()
    }

    /// 넛지 자동 시작 자격: 로그인됨·팀 있음·비근무·오버레이 켜짐. (표시중 조건은 소멸 — 안내만 하고 바로 시작.)
    private var isNudgeEligible: Bool {
        store.isSignedIn
            && store.currentTeamID != nil
            && store.snapshot.isWorking == false
            && store.isOverlayEnabled
    }

    /// 근무 상태 변화에 따라 패널을 표시/숨김한다. 표시 직전 항상 우상단으로 재배치한다.
    /// 사용자가 캐릭터 표시를 꺼두면(isOverlayEnabled=false) 근무중이어도 표시하지 않는다.
    ///
    /// 표시 시: 폴짝 점프+스핀(commuteStart). 숨김 시: 앞으로 꾸벅 인사(commuteEnd) 후 패널을 내린다.
    /// 인사 완료 콜백은 렌더 루프가 돌 때 오고, 워치독이 최대 `farewellHideDeadline` 내 숨김을 보장한다.
    func updateWorking(_ isWorking: Bool) {
        let visible = isWorking && store.isOverlayEnabled
        let wasVisible = shouldBeVisible
        shouldBeVisible = visible
        defer { syncNudgeScheduler() }
        if visible {
            farewellTask?.cancel()
            farewellTask = nil
            engine.renderActive = true
            reposition()
            panel.orderFrontRegardless()
            installMouseMoveMonitor()
            startDrowsyScheduler()
            engine.request(.commuteStart)
        } else {
            stopDrowsyScheduler()
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
    private func syncNudgeScheduler() {
        if store.isSignedIn && store.snapshot.isWorking == false {
            nudgeScheduler.start()
        } else {
            nudgeScheduler.stop()
        }
    }

    /// 넛지 발동 콜백: 물어보지 않고 즉시 근무를 시작한다. 자격을 재확인한 뒤, 등장 말풍선을 안내 문구로 1회
    /// 덮어쓸 오버라이드를 세팅하고 store.start() 를 호출한다. 이후 store 관찰 → updateWorking(true) 경로가
    /// 패널 표시 + commuteStart 리액션을 자연 처리하고, perform(.commuteStart)이 오버라이드를 소비한다.
    func nudgeAutoStart() {
        guard isNudgeEligible else { return }
        engine.setCommuteStartBubbleOverride(
            text: Self.nudgeAutoStartText,
            seconds: Self.nudgeAutoStartBubbleSeconds
        )
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
    private func updateHitThrough(at screenPoint: NSPoint) {
        guard shouldBeVisible, !isDragCandidate else { return }
        setIgnoresMouseEvents(!engine.isBodyAtScreenPoint(screenPoint))
    }

    /// 커서가 호스팅 뷰(패널) 밖으로 나갔을 때: 통과로 되돌린다(이후엔 전역 모니터가 다시 감지). 드래그 중엔 유지.
    private func restorePassThroughAfterExit() {
        guard !isDragCandidate else { return }
        setIgnoresMouseEvents(true)
    }

    /// 클릭 통과 여부를 == 가드로만 바꾼다(불필요한 창 속성 변경 churn 방지).
    private func setIgnoresMouseEvents(_ ignore: Bool) {
        if panel.ignoresMouseEvents != ignore {
            panel.ignoresMouseEvents = ignore
        }
    }

    /// 클릭/드래그 판정의 이중 안전 가드. 뷰가 attach 된 실사용에선 몸체(지오메트리) 위인지로 강화하고,
    /// 뷰 미부착(헤드리스 테스트)에선 패널 프레임 안인지로 폴백한다. 로컬 이벤트 경로라 사실상 몸체에서만 온다.
    private func withinBody(_ screenPoint: NSPoint) -> Bool {
        engine.hasAttachedView ? engine.isBodyAtScreenPoint(screenPoint) : panel.frame.contains(screenPoint)
    }

    /// 좌클릭 다운: 표시 중이고 몸체 위면 드래그 후보로 삼는다(리액션은 아직 발화하지 않고 업 시점에 판정).
    func handleMouseDown(at location: NSPoint) {
        guard shouldBeVisible, withinBody(location) else { return }
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
        guard shouldBeVisible, withinBody(location) else { return }
        if engine.state == .sleeping {
            engine.request(.wake)
        } else {
            engine.request(.hit)
        }
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
                // 조건: 표시 중(근무중) && 다른 리액션 없음 — 시간대 제한 없이 조용하면 존다.
                guard self.shouldBeVisible, self.engine.state == .idle else {
                    continue
                }
                self.engine.request(.drowsy)
            }
        }
    }

    private func stopDrowsyScheduler() {
        drowsyTask?.cancel()
        drowsyTask = nil
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

    /// 저장된 우상단 오프셋이 있으면 그 위치(클램프 보정)로, 없으면 메인 스크린 visibleFrame 우상단
    /// (여백 `edgeMargin`)으로 패널을 옮긴다.
    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = Self.overlayFrame(
            offset: loadOffset(),
            in: screen.visibleFrame,
            size: Self.panelSize,
            margin: Self.edgeMargin
        )
        panel.setFrame(frame, display: shouldBeVisible)
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

    /// 커서(또는 패널)가 놓인 화면의 visibleFrame 을 고른다. 커서가 어느 화면에도 없으면 패널과 가장 많이
    /// 겹치는 화면을, 그것도 없으면 메인 화면을 쓴다.
    private func currentVisibleFrame(near point: NSPoint) -> NSRect {
        let screens = NSScreen.screens
        if let hit = screens.first(where: { $0.frame.contains(point) }) {
            return hit.visibleFrame
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
        return (best ?? NSScreen.main ?? screens.first)?.visibleFrame ?? panelFrame
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
