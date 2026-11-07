import AppKit
import SwiftUI
import AlkkagiCore

@main
struct AlkkagiPlaygroundApp: App {
    @NSApplicationDelegateAdaptor(AlkkagiAppDelegate.self) private var delegate
    private let configuration: AlkkagiPreviewConfiguration?
    private let online: AlkkagiOnlineStore?
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        let configuration = AlkkagiPreviewConfiguration.load()
        self.configuration = configuration
        self.online = configuration.map { AlkkagiOnlineStore(service: AlkkagiPreviewService(configuration: $0), pollSeconds: 0.35) }
    }

    var body: some Scene {
        WindowGroup(configuration?.title ?? "알까기 · 로컬 테스트") {
            Group {
                if let online { AlkkagiOnlinePanel(store: online) }
                else { AlkkagiGameView() }
            }
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
