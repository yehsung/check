import AppKit
import SwiftUI
import AlkkagiCore

/// 로그인 없는 한 창 연습(로컬 2인) 실행기. 온라인 1:1 은 본앱에서만 연다(SPEC v1.1 §5.10 · 설계 결정 D15).
@main
struct AlkkagiPlaygroundApp: App {
    @NSApplicationDelegateAdaptor(AlkkagiAppDelegate.self) private var delegate
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("알까기 · 로컬 연습") {
            AlkkagiGameView()
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
private final class AlkkagiAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
