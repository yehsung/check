import SwiftUI

@main
struct CheckApp: App {
    @State private var store = WorkTimerStore()

    var body: some Scene {
        MenuBarExtra {
            CheckMenuView(store: store)
                .frame(width: 340)
        } label: {
            MenuBarStatusLabel(snapshot: store.snapshot)
        }
        .menuBarExtraStyle(.window)
    }
}
