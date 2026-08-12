import AppKit
import ServiceManagement
import SwiftUI

@main
struct CheckApp: App {
    // 앱 종료 시점을 가로채기 위해 AppDelegate를 붙인다. store는 델리게이트가 단일 인스턴스로 소유해
    // 메뉴바 라벨·팝오버와 종료 훅이 같은 상태를 공유한다(생성이 두 번 되지 않게 하는 지점).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            CheckMenuView(store: appDelegate.store, updateCheck: appDelegate.updateCheck)
                .frame(width: 340)
                // 팝오버 창의 위쪽 모서리를 고정 — 콘텐츠 높이 변화 시 위로 튀어 상단이 잘리는 것을 막는다
                // (동적 높이는 유지, 창은 아래로만 성장/수축). 그림은 그리지 않는 배경 뷰.
                // 창 키 획득/상실도 setMenuPresented 로 흘려 티커/폴링 게이팅의 이중 안전망을 만든다.
                .background(WindowAnchorAccessor(onVisibilityChange: { appDelegate.store.setMenuPresented($0) }))
        } label: {
            MenuBarStatusLabel(snapshot: appDelegate.store.snapshot, title: appDelegate.store.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 종료(⌘Q·푸터 종료 버튼의 NSApplication.terminate 포함)를 가로채 근무중이면 퇴근 동기화를 끝낸 뒤 종료한다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = WorkTimerStore()
    // 업데이트 감지 스토어(1개). 팝오버 배너(CheckMenuView)와 근무중 오버레이 말풍선(컨트롤러)이 같은
    // 상태를 공유하도록 델리게이트가 단일 소유한다 — 하루 1회 체크/버전당 1회 말풍선 기록이 두 표면에 일관된다.
    let updateCheck = UpdateCheckStore()
    // 근무중 3D 캐릭터 오버레이. 패널은 여기서 1회 생성하고 숨김으로 시작하며, 루트 뷰가
    // store.snapshot.isWorking을 관찰해 표시/숨김을 전환한다(store는 읽기 전용으로만 참조).
    private var overlayController: CheckOverlayController?
    // 할 일 목록(로컬 전용)과 보드 창. 오버레이와 **형제**다 — 캐릭터 패널을 키워 보드를 담으면
    // 울트라 프레임 복귀·드래그 위치 영속·클릭통과 기계가 전부 얽힌다.
    private var todoStore: TodoListStore?
    private var todoBoard: CheckTodoBoardController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 오버레이 컨트롤러를 **먼저** 만든다. 바로 아래 실행 킥이 서버에 열려 있던 세션을 흡수해 곧장 근무중으로
        // 복구할 수 있는데, 그 순간 표시 전환과 리액션/찔림 싱크(store.onReactionTrigger / onPokesReceived)가
        // 이미 배선돼 있어야 캐릭터 등장과 밀린 찔림이 통째로 유실되지 않는다.
        overlayController = CheckOverlayController(store: store, updateCheck: updateCheck)
        wireTodoBoard()
        // 로그인 시 자동 실행을 1회만 등록한다(사용자가 시스템 설정에서 끄면 다시 끼어들지 않는다).
        LoginItemRegistrar.registerIfNeeded(
            defaults: .standard,
            isNotRegistered: { SMAppService.mainApp.status == .notRegistered },
            register: { try? SMAppService.mainApp.register() }
        )
        // D1 실행 킥: 저장 세션을 실행당 1회 활성화한다(팝오버를 한 번도 열지 않아도).
        //
        // **이 한 줄이 없으면 무슨 일이 났는가**: MenuBarExtra(.window) 의 콘텐츠 뷰는 팝오버를 처음 열기 전까지
        // 생성되지 않는다(최소 재현 앱으로 실증). 저장 세션 활성화의 유일한 진입점이 CheckMenuView 의
        // `.task { await store.activateStoredSession() }` 였으므로, 메뉴바 아이콘을 한 번도 누르지 않으면 그 실행
        // 내내 토큰 회전·팀 확정·상태 폴링·하트비트·자동 근무 시작(넛지)이 전부 0회였다. 바로 위 LoginItemRegistrar
        // 로 로그인 자동 실행은 이미 켜져 있으니, 부팅 후 아이콘을 안 누르는 사용자에게는 "앱은 떠 있는데 근무가
        // 하나도 기록되지 않는" 상태가 하루 종일 지속된다.
        store.activateStoredSessionOnLaunch()
    }

    /// 할 일 보드를 만들고 오버레이 훅에 잇는다. **판단은 전부 여기서** 하고 오버레이는 사실만 알린다.
    ///
    /// 목록 파일은 계정별로 나눈다 — 한 맥을 여러 사람이 쓰거나 계정을 갈아탔을 때 남의 할 일이 보이면 안 된다.
    /// 로그인 전에는 `todos.local.json` 을 쓰고, 이 실행에서 세션이 이미 복구돼 있으면 그 계정 파일로 연다.
    private func wireTodoBoard() {
        guard let overlay = overlayController else { return }
        let listStore = TodoListStore(fileURL: TodoFileStore.defaultURL(userID: store.session?.userID))
        let board = CheckTodoBoardController(store: listStore)
        todoStore = listStore
        todoBoard = board

        // 클릭 → 보드 여닫기. **false 를 돌려주면 오버레이가 아파하기를 재생한다**(기능을 끈 사용자).
        overlay.onCharacterTapped = { [weak self] in
            guard let self, self.store.isTodoEnabled else { return false }
            board.toggle(anchor: overlay.panel.frame, screenVisibleFrame: Self.visibleFrame(for: overlay.panel))
            // 보드가 열린 동안 캐릭터가 그쪽을 바라본다(드래그 방향 전환 기계를 그대로 재사용).
            overlay.engine.setDragFacing(board.isBoardOpen ? -1 : 0)
            return true
        }
        overlay.onUltraBegan = { board.close() }
        overlay.onUltraEnded = { _ in }   // 격발 뒤 자동 복원은 하지 않는다 — 사용자가 다시 열면 된다.
        overlay.onWorkEnded = { [weak overlay] in
            board.close()
            overlay?.engine.setDragFacing(0)
        }
        overlay.onCharacterFrameChanged = { frame in
            board.reposition(anchor: frame, screenVisibleFrame: Self.visibleFrame(for: overlay.panel))
        }
        overlay.isBoardOpen = { board.isBoardOpen }
    }

    /// 그 패널이 놓인 화면의 visibleFrame. 캐릭터를 끌어다 둔 화면이 기준이다 —
    /// NSScreen.main 은 키 윈도우가 없는 메뉴바 앱에서 무엇을 돌려줄지 계약이 불분명하다.
    private static func visibleFrame(for panel: NSPanel) -> NSRect {
        let screens = NSScreen.screens
        func overlap(_ screen: NSScreen) -> CGFloat {
            let r = screen.frame.intersection(panel.frame)
            return r.isNull ? 0 : r.width * r.height
        }
        let best = screens.max { overlap($0) < overlap($1) }
        return (best ?? NSScreen.main ?? screens.first)?.visibleFrame ?? .zero
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 로그인 안 됨/키 없음/근무중 아님 → 지연할 이유가 없으므로 즉시 종료.
        // 흡수 세션(다른 맥이 연 세션)도 즉시 종료다: finishWorkBeforeQuit 이 같은 표식을 보고 즉시 반환하므로
        // 여기서 걸러 내지 않으면 .terminateLater 를 돌려놓고 아무것도 안 하는 헛왕복이 되어 종료만 한 틱 늦는다.
        guard store.isSignedIn, store.startedAt != nil, !store.adoptedRemoteSession else {
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

/// 로그인 자동 실행(SMAppService.mainApp) 1회 등록 결정. SMAppService 호출은 주입 클로저 뒤에 두어
/// 테스트가 UserDefaults 와 클로저만으로 no-op/1회성을 검증하고, 실제 시스템 등록은 건드리지 않게 한다.
enum LoginItemRegistrar {
    /// 등록 시도 여부를 기록하는 플래그 키(있으면 다시 시도하지 않는다 — 사용자 수동 제거 존중).
    static let registeredKey = "check.loginItemRegistered"

    /// 현재 로그인 자동 실행 상태(주입 가능 — 테스트/프리뷰가 실제 SMAppService 를 건드리지 않게).
    /// 푸터의 전원 메뉴가 읽는다. "껐는데 다시 켜진다"는 불만의 절반은 자동 실행을 끄는 수단이
    /// 시스템 설정 깊숙이 숨어 있던 것이라, 앱 안에서 켜고 끌 수 있어야 한다.
    @MainActor static var isLaunchAtLoginEnabled: () -> Bool = {
        SMAppService.mainApp.status == .enabled
    }

    /// 로그인 자동 실행을 켜거나 끈다. 성공하면 true. 실패는 조용히 false(다음 열람 때 실상태가 다시 읽힌다).
    @MainActor static var setLaunchAtLoginEnabled: (Bool) -> Bool = { enabled in
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    /// 플래그가 없고 아직 미등록일 때만 register 를 호출하고, 성공/실패와 무관하게 플래그를 남긴다.
    /// 이미 플래그가 있으면 아무것도 하지 않는다(재등록 강제 금지). 실제 등록 시도를 했으면 true.
    @discardableResult
    static func registerIfNeeded(
        defaults: UserDefaults,
        isNotRegistered: () -> Bool,
        register: () -> Void
    ) -> Bool {
        guard defaults.object(forKey: registeredKey) == nil else { return false }
        if isNotRegistered() { register() }
        defaults.set(true, forKey: registeredKey)
        return true
    }
}
