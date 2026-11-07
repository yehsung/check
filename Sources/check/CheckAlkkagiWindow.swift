import AppKit
import SwiftUI
import CheckCore

/// 로컬 2인 알까기 창 하나를 재사용한다. 네트워크 게임 스토어는 필요하지 않다.
@MainActor
final class CheckAlkkagiWindowController: NSObject, NSWindowDelegate {
    static let shared = CheckAlkkagiWindowController()
    static let windowTitle = "알까기"
    static let frameAutosaveName = "check.alkkagi.window"
    static let fixedContentSize = BoardGameLayout.contentSize

    private var windowStorage: NSWindow?
    private(set) var isOpen = false
    var currentWindow: NSWindow? { windowStorage }
    var onClosed: (@MainActor (_ byUser: Bool) -> Void)?

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
            let hosting = NSHostingView(rootView: AlkkagiGameView(onReturn: { [weak self] in
                self?.closeFromUser()
            }, me: me))
            hosting.autoresizingMask = [.width, .height]
            window.contentView = hosting
        }
        window.setContentSize(Self.fixedContentSize)
        if !CheckPanelVisibility.isRunningTests { NSApp.activate() }
        if window.isMiniaturized { window.deminiaturize(nil) }
        isOpen = true
        window.makeKeyAndOrderFront(nil)
    }

    /// 로그아웃과 계정 전환은 목록을 다시 열지 않는다. 숨은 게임의 타이머도 함께 거둔다.
    func close() {
        guard isOpen else { return }
        windowStorage?.orderOut(nil)
        isOpen = false
        windowStorage?.contentView = nil
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
        onClosed?(true)
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
