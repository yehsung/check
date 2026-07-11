import AppKit
import SwiftUI

@main
struct CheckApp: App {
    // 앱 종료 시점을 가로채기 위해 AppDelegate를 붙인다. store는 델리게이트가 단일 인스턴스로 소유해
    // 메뉴바 라벨·팝오버와 종료 훅이 같은 상태를 공유한다(생성이 두 번 되지 않게 하는 지점).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            CheckMenuView(store: appDelegate.store)
                .frame(width: 340)
        } label: {
            MenuBarStatusLabel(snapshot: appDelegate.store.snapshot)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 종료(⌘Q·푸터 종료 버튼의 NSApplication.terminate 포함)를 가로채 근무중이면 퇴근 동기화를 끝낸 뒤 종료한다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = WorkTimerStore()
    // 근무중 3D 캐릭터 오버레이. 패널은 여기서 1회 생성하고 숨김으로 시작하며, 루트 뷰가
    // store.snapshot.isWorking을 관찰해 표시/숨김을 전환한다(store는 읽기 전용으로만 참조).
    private var overlayController: CheckOverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayController = CheckOverlayController(store: store)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 로그인 안 됨/키 없음/근무중 아님 → 지연할 이유가 없으므로 즉시 종료.
        guard store.isSignedIn, store.startedAt != nil else {
            return .terminateNow
        }
        // 근무중이면 종료 동기화를 시작하고, 마무리(최대 3초)될 때까지 종료를 늦춘다.
        // 타임아웃이 걸려도 finishWorkBeforeQuit가 리턴하므로 반드시 종료로 이어진다.
        Task { @MainActor in
            await store.finishWorkBeforeQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
