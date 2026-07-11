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

    /// 근무 종료 인사(꾸벅, 0.4s) 후 패널을 숨기기까지의 상한(초). 인사가 끝난 직후 내려가고, 최대 1초를 넘지 않는다.
    static let farewellHideDeadline: TimeInterval = ReactionKind.commuteEnd.duration + 0.15

    let panel: NSPanel
    /// 리액션 조율기. 표시 중일 때만 이벤트를 받아 캐릭터 wrapper 에 SCNAction 을 건다.
    let engine: ReactionEngine
    /// 표시 의도 상태. 헤드리스 환경에서도 결정적으로 검증할 수 있는 지점(실제 표시 여부는 `panel.isVisible`).
    private(set) var shouldBeVisible = false

    private let notificationCenter: NotificationCenter
    private var screenObserver: NSObjectProtocol?
    private let store: WorkTimerStore

    // 때리면 아파하기: 패널 표시 중에만 켜지는 전역 좌클릭 모니터(이벤트를 소비하지 않아 클릭 통과 유지).
    private var clickMonitor: Any?
    // 근무 종료 인사 후 숨김을 보장하는 워치독.
    private var farewellTask: Task<Void, Never>?
    // 밤샘 졸기 스케줄러(패널 표시 중에만 90±30초 간격으로 시간창을 확인).
    private var drowsyTask: Task<Void, Never>?

    init(store: WorkTimerStore, notificationCenter: NotificationCenter = .default, engine: ReactionEngine? = nil) {
        self.notificationCenter = notificationCenter
        self.store = store
        self.engine = engine ?? ReactionEngine()
        panel = Self.makePanel(size: Self.panelSize)

        let engineRef = self.engine
        let root = CheckOverlayRootView(store: store, engine: engineRef) { [weak self] working in
            self?.updateWorking(working)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // 스토어(소유 파일)가 감지한 마일스톤/팀원 인사 트리거를 엔진으로 흘린다. 표시 중일 때만 반응한다
        // (숨겨진 패널에 파티클/애니메이션을 남기지 않기 위해).
        store.onReactionTrigger = { [weak self] kind in
            guard let self, self.shouldBeVisible else { return }
            self.engine.request(kind)
        }

        reposition()
        observeScreenChanges()
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
        if visible {
            farewellTask?.cancel()
            farewellTask = nil
            engine.renderActive = true
            reposition()
            panel.orderFrontRegardless()
            installClickMonitor()
            startDrowsyScheduler()
            engine.request(.commuteStart)
        } else {
            stopDrowsyScheduler()
            removeClickMonitor()
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

    // MARK: - 때리면 아파하기 (전역 클릭 모니터)

    /// 전역 좌클릭 모니터를 켠다. 전역 모니터는 이벤트를 소비하지 않으므로 클릭 통과(작업 방해 0)가 유지된다.
    /// 마우스 이벤트 전역 모니터는 손쉬운 제어(Accessibility) 권한이 필요 없다(키보드 모니터만 필요).
    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.handleGlobalClick() }
        }
    }

    private func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    /// 전역 클릭 좌표(마우스 위치)를 판정한다.
    func handleGlobalClick() {
        handleClick(at: NSEvent.mouseLocation)
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
                try? await Task.sleep(for: .seconds(interval))
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

    /// 메인 스크린 visibleFrame 우상단(여백 `edgeMargin`)으로 패널을 옮긴다.
    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = Self.overlayFrame(in: screen.visibleFrame, size: Self.panelSize, margin: Self.edgeMargin)
        panel.setFrame(frame, display: shouldBeVisible)
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
