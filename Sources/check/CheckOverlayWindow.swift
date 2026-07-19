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

    /// 넛지 말풍선 클릭 없이 자동으로 사라지기까지의 상한(초). 테스트는 짧은 값을 주입한다.
    /// 25초는 구석에 떠서 놓치기 쉽다는 실사용 피드백으로 60초로 늘렸다(쿨다운 60분은 그대로).
    static let defaultNudgeTimeout: TimeInterval = 60

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

    // MARK: - 근무 시작 제안(넛지)
    /// 넛지 감지 스케줄러(비근무·로그인 상태일 때만 가동). onNudge → showNudge.
    private var nudgeScheduler: NudgeScheduler!
    /// 넛지 말풍선을 현재 표시 중인지. 헤드리스 검증 지점(자격 판정·중복 표시 방지에 쓴다).
    private(set) var isShowingNudge = false
    /// 넛지 자동 사라짐 워치독.
    private var nudgeTimeoutTask: Task<Void, Never>?
    /// 넛지 자동 사라짐 상한(초). 주입 가능.
    private let nudgeTimeout: TimeInterval
    /// 넛지 말풍선 부분만 클릭을 받는 hitTest 호스팅 뷰(패널 contentView). 클릭 영역 갱신에 참조한다.
    /// (자기 참조 클로저를 담은 루트 뷰를 얹은 뒤 대입하므로 init 순서상 IUO var 로 둔다.)
    private var contentHostingView: BubbleHitTestingView<CheckOverlayRootView>!

    // 때리면 아파하기·드래그 이동: 패널 표시 중에만 켜지는 전역 좌클릭 모니터 3종(down/dragged/up).
    // 전역 모니터는 이벤트를 소비하지 않으므로 클릭 통과가 유지된다.
    private var mouseMonitors: [Any] = []
    // 드래그 임시 상태(다운~업 사이에만 유효).
    private var dragAnchor: NSPoint = .zero        // 좌클릭 다운 시점의 마우스 좌표.
    private var originAtDragStart: NSPoint = .zero // 다운 시점의 패널 origin.
    private var isDragCandidate = false            // 패널 안에서 다운되어 드래그 후보가 됨.
    private var didDrag = false                    // 임계를 넘겨 실제 이동으로 확정됨.
    // 근무 종료 인사 후 숨김을 보장하는 워치독.
    private var farewellTask: Task<Void, Never>?
    // 밤샘 졸기 스케줄러(패널 표시 중에만 90±30초 간격으로 시간창을 확인).
    private var drowsyTask: Task<Void, Never>?

    init(
        store: WorkTimerStore,
        notificationCenter: NotificationCenter = .default,
        engine: ReactionEngine? = nil,
        defaults: UserDefaults = .standard,
        nudgeTimeout: TimeInterval = CheckOverlayController.defaultNudgeTimeout,
        workspaceNotifications: NotificationCenter? = NSWorkspace.shared.notificationCenter
    ) {
        self.notificationCenter = notificationCenter
        self.store = store
        self.defaults = defaults
        self.nudgeTimeout = nudgeTimeout
        self.engine = engine ?? ReactionEngine()
        panel = Self.makePanel(size: Self.panelSize)

        let engineRef = self.engine
        let root = CheckOverlayRootView(
            store: store,
            engine: engineRef,
            onWorkingChange: { [weak self] working in self?.updateWorking(working) },
            onNudgeTap: { [weak self] in self?.acceptNudge() },
            onNudgeBubbleFrame: { [weak self] rect in self?.setNudgeBubbleFrame(rect) }
        )
        let hosting = BubbleHitTestingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        contentHostingView = hosting
        panel.contentView = hosting

        // 스토어(소유 파일)가 감지한 마일스톤/팀원 인사 트리거를 엔진으로 흘린다. 표시 중일 때만 반응한다
        // (숨겨진 패널에 파티클/애니메이션을 남기지 않기 위해).
        store.onReactionTrigger = { [weak self] kind in
            guard let self, self.shouldBeVisible else { return }
            self.engine.request(kind)
        }

        // 넛지 스케줄러: 자격은 store 로 구성(로그인·팀·비근무·오버레이 켜짐·표시중 아님), 발동은 showNudge 로.
        nudgeScheduler = NudgeScheduler(
            isEligible: { [weak self] in self?.isNudgeEligible ?? false },
            onNudge: { [weak self] in self?.showNudge() },
            workspaceNotifications: workspaceNotifications
        )

        reposition()
        observeScreenChanges()
    }

    /// 넛지를 띄워도 되는 상태인지: 로그인됨·팀 있음·비근무·오버레이 켜짐·현재 넛지 표시 중 아님.
    private var isNudgeEligible: Bool {
        store.isSignedIn
            && store.currentTeamID != nil
            && store.snapshot.isWorking == false
            && store.isOverlayEnabled
            && isShowingNudge == false
    }

    /// 근무 상태 변화에 따라 패널을 표시/숨김한다. 표시 직전 항상 우상단으로 재배치한다.
    /// 사용자가 캐릭터 표시를 꺼두면(isOverlayEnabled=false) 근무중이어도 표시하지 않는다.
    ///
    /// 표시 시: 폴짝 점프+스핀(commuteStart). 숨김 시: 앞으로 꾸벅 인사(commuteEnd) 후 패널을 내린다.
    /// 인사 완료 콜백은 렌더 루프가 돌 때 오고, 워치독이 최대 `farewellHideDeadline` 내 숨김을 보장한다.
    func updateWorking(_ isWorking: Bool) {
        // 넛지 중 근무 상태/자격 변화가 오면 먼저 넛지를 정리한다(근무 시작이면 아래에서 패널을 그대로 유지).
        if isShowingNudge { dismissNudge() }
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
            installMouseMonitors()
            startDrowsyScheduler()
            engine.request(.commuteStart)
        } else {
            stopDrowsyScheduler()
            removeMouseMonitors()
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

    // MARK: - 근무 시작 제안(넛지)

    /// 넛지 스케줄러를 현재 store 상태에 맞춰 가동/정지한다(비근무·로그인이면 가동, 아니면 정지·카운트 리셋).
    private func syncNudgeScheduler() {
        if store.isSignedIn && store.snapshot.isWorking == false {
            nudgeScheduler.start()
        } else {
            nudgeScheduler.stop()
        }
    }

    /// 넛지 말풍선을 띄운다(스케줄러 발동 콜백). 우상단 재배치 후 패널을 올리고, 클릭을 받도록 통과를 잠시 해제한다
    /// (hitTest 는 말풍선 프레임 안으로만 제한). 가벼운 인사 모션으로 시선을 끌고, 상한(nudgeTimeout) 뒤 자동으로 사라진다.
    func showNudge() {
        guard isShowingNudge == false, store.snapshot.isWorking == false, store.isOverlayEnabled else { return }
        isShowingNudge = true
        reposition()
        engine.renderActive = true
        engine.nudgePromptActive = true
        panel.orderFrontRegardless()
        // 넛지 동안만 클릭 통과 해제(말풍선 안만 hitTest 로 받고 나머지는 통과 — clickableRect 갱신 전엔 nil 이라 통과).
        panel.ignoresMouseEvents = false
        engine.playNudgeNod()
        let timeout = nudgeTimeout
        nudgeTimeoutTask?.cancel()
        nudgeTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self, !Task.isCancelled else { return }
            self.dismissNudge()
        }
    }

    /// dismissNudge/acceptNudge 가 공유하는 넛지 상태 정리. 말풍선/타임아웃/클릭 영역/클릭 통과를 원복한다.
    private func clearNudgeState() {
        isShowingNudge = false
        nudgeTimeoutTask?.cancel()
        nudgeTimeoutTask = nil
        engine.nudgePromptActive = false
        contentHostingView.clickableRect = nil
        panel.ignoresMouseEvents = true
    }

    /// 넛지를 거둔다(타임아웃/자격 상실/근무 상태 변화). 근무중이 아니면 렌더를 멈추고 패널을 내린다
    /// (근무 시작으로 인한 정리라면 이후 updateWorking(true) 가 패널을 그대로 유지하므로 여기서 내리지 않는다).
    func dismissNudge() {
        guard isShowingNudge else { return }
        clearNudgeState()
        if store.snapshot.isWorking == false {
            engine.stopSleeping()
            engine.renderActive = false
            panel.orderOut(nil)
        }
    }

    /// 말풍선 탭 → 명시적 근무 시작. 먼저 store.start() 로 근무를 시작하면 isWorking 이 true 가 되어, 이어지는
    /// dismissNudge 가 패널을 내리지 않고 넛지 상태만 정리한다(이후 updateWorking(true) 가 등장 폴짝을 자연 처리).
    func acceptNudge() {
        guard isShowingNudge else { return }
        store.start()
        dismissNudge()
    }

    /// 넛지 말풍선 프레임(SwiftUI 좌표)을 받아 AppKit 좌표(y 반전)로 뒤집어 hitTest 클릭 영역을 갱신한다.
    /// nil 이면 클릭 영역 제거(말풍선 없음).
    func setNudgeBubbleFrame(_ swiftUIRect: CGRect?) {
        guard let swiftUIRect else {
            contentHostingView.clickableRect = nil
            return
        }
        contentHostingView.clickableRect = BubbleHitGeometry.appKitRect(
            fromSwiftUI: swiftUIRect,
            containerHeight: contentHostingView.bounds.height
        )
    }

    // MARK: - 때리면 아파하기 · 드래그 이동 (전역 마우스 모니터)

    /// 전역 좌클릭 모니터 3종(down/dragged/up)을 켠다. 전역 모니터는 이벤트를 소비하지 않으므로
    /// 클릭 통과(작업 방해 0)가 유지되고, 손쉬운 제어(Accessibility) 권한도 필요 없다.
    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.handleMouseDown(at: NSEvent.mouseLocation) }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            Task { @MainActor in self?.handleMouseDragged(at: NSEvent.mouseLocation) }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in self?.handleMouseUp(at: NSEvent.mouseLocation) }
        }
        mouseMonitors = [down, dragged, up].compactMap { $0 }
    }

    /// 전역 마우스 모니터를 끄고 드래그 상태를 리셋한다(숨김 중 mouseUp 유실 대비).
    private func removeMouseMonitors() {
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitors = []
        isDragCandidate = false
        didDrag = false
    }

    /// 좌클릭 다운: 표시 중이고 패널 안이면 드래그 후보로 삼는다(리액션은 아직 발화하지 않고 업 시점에 판정).
    func handleMouseDown(at location: NSPoint) {
        guard shouldBeVisible, panel.frame.contains(location) else { return }
        isDragCandidate = true
        didDrag = false
        dragAnchor = location
        originAtDragStart = panel.frame.origin
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
    }

    /// 클릭 좌표가 패널 프레임 안이면 리액션을 요청한다(좌표 주입 가능 — 테스트용).
    /// 자는 중이면 hit 대신 wake(화들짝 + "깜빡 졸았다!")로 깨우고, 아니면 평소처럼 아파하기(hit).
    func handleClick(at location: NSPoint) {
        guard shouldBeVisible, panel.frame.contains(location) else { return }
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

/// 넛지 말풍선 부분만 클릭을 받는 NSHostingView 서브클래스.
///
/// `clickableRect`(뷰 좌표계, bottom-left)가 설정돼 있고 클릭 지점이 그 안이면 SwiftUI(super)로 넘겨 말풍선
/// 버튼이 눌리게 하고, 밖이면 nil 을 돌려 클릭을 뒤(작업 창)로 통과시킨다. 넛지가 아닐 때는 clickableRect=nil
/// 이라 항상 통과하며, 패널 `ignoresMouseEvents=true`(넛지 아닐 때)와 이중 안전을 이룬다.
final class BubbleHitTestingView<Content: View>: NSHostingView<Content> {
    /// 클릭을 받을 영역(뷰 좌표계). nil 이면 모든 클릭을 통과시킨다.
    var clickableRect: NSRect?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let clickableRect else { return nil }
        // point 는 superview 좌표계 → 내 좌표계로 변환해 클릭 영역과 비교한다.
        let local = convert(point, from: superview)
        return clickableRect.contains(local) ? super.hitTest(point) : nil
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
