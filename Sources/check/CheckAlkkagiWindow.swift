import AppKit
import SwiftUI
import CheckCore

/// 로컬 2인 알까기 창 하나를 재사용한다. 네트워크 게임 스토어는 필요하지 않다.
@MainActor
final class CheckAlkkagiWindowController: NSObject, NSWindowDelegate {
    /// 이 창이 선 화면의 주사율 — 판 걸음 간격의 재료(길건너 1:1 과 같은 꼴: 창마다 자기 감시, 공용 값을 덮지 않는다).
    let frameRateMonitor = MiniGameFrameRateMonitor()
    /// 디스플레이 설정이 바뀌면(주사율 변경) 다시 읽는다 — 창 이동(`windowDidChangeScreen`)만 보면 절반을 놓친다.
    private var screenParametersObserver: NSObjectProtocol?
    static let shared = CheckAlkkagiWindowController()
    static let windowTitle = "알까기"
    static let frameAutosaveName = "check.alkkagi.window"
    static let fixedContentSize = BoardGameLayout.contentSize

    private var windowStorage: NSWindow?
    private var onlineStore: AlkkagiOnlineStore?
    private(set) var isOpen = false
    var currentWindow: NSWindow? { windowStorage }
    var onClosed: (@MainActor (_ byUser: Bool) -> Void)?

    func configure(store: AlkkagiOnlineStore) { onlineStore = store }

    func show(me: AlkkagiPlayerProfile = AlkkagiPlayerProfile(name: "플레이어 1")) {
        let window: NSWindow
        if let windowStorage {
            window = windowStorage
        } else {
            window = Self.makeWindow()
            window.delegate = self
            if !window.setFrameUsingName(Self.frameAutosaveName) { window.center() }
            window.setFrameAutosaveName(Self.frameAutosaveName)
            windowStorage = window
        }
        if !isOpen {
            if let onlineStore {
                var panel = AlkkagiOnlinePanel(store: onlineStore, onReturn: { [weak self] in
                    self?.closeFromUser()
                })
                panel.frameRateMonitor = frameRateMonitor
                let hosting = NSHostingView(rootView: panel)
                hosting.autoresizingMask = [.width, .height]
                window.contentView = hosting
            } else {
                var game = AlkkagiGameView(onReturn: { [weak self] in
                    self?.closeFromUser()
                }, me: me)
                game.frameRateMonitor = frameRateMonitor
                let hosting = NSHostingView(rootView: game)
                hosting.autoresizingMask = [.width, .height]
                window.contentView = hosting
            }
        }
        window.setContentSize(Self.fixedContentSize)
        frameRateMonitor.update(for: window)
        if screenParametersObserver == nil {
            screenParametersObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.frameRateMonitor.update(for: self?.windowStorage) }
            }
        }
        if !CheckPanelVisibility.isRunningTests { NSApp.activate() }
        if window.isMiniaturized { window.deminiaturize(nil) }
        isOpen = true
        window.makeKeyAndOrderFront(nil)
        onlineStore?.windowDidShow()
    }

    /// 로그아웃과 계정 전환은 목록을 다시 열지 않는다. 숨은 게임의 타이머도 함께 거둔다.
    func close() {
        guard isOpen else { return }
        windowStorage?.orderOut(nil)
        isOpen = false
        windowStorage?.contentView = nil
        onlineStore?.windowDidHide()
        onClosed?(false)
    }

    /// 화면의 돌아가기 버튼도 빨간 점과 같은 닫기 통지를 거친다.
    func closeFromUser() {
        guard isOpen else { return }
        windowStorage?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === windowStorage, isOpen else { return }
        isOpen = false
        windowStorage?.contentView = nil
        onlineStore?.windowDidClose()
        onClosed?(true)
    }

    func windowDidMiniaturize(_ notification: Notification) { onlineStore?.windowDidHide() }
    func windowDidChangeScreen(_ notification: Notification) { frameRateMonitor.update(for: windowStorage) }
    func windowDidDeminiaturize(_ notification: Notification) { onlineStore?.windowDidShow() }
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard isOpen, let window = windowStorage else { return }
        onlineStore?.windowOcclusionDidChange(visible: window.occlusionState.contains(.visible))
    }

    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: fixedContentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.identifier = NSUserInterfaceItemIdentifier(frameAutosaveName)
        window.contentMinSize = fixedContentSize
        window.contentMaxSize = fixedContentSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.alphaValue = CheckPanelVisibility.panelAlpha
        return window
    }
}
