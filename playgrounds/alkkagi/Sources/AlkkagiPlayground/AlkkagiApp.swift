import AppKit
import SwiftUI

@main
struct AlkkagiPlaygroundApp: App {
    @NSApplicationDelegateAdaptor(AlkkagiAppDelegate.self) private var delegate
    init() { NSApplication.shared.setActivationPolicy(.regular) }

    var body: some Scene {
        WindowGroup("알까기 · 로컬 테스트") {
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
