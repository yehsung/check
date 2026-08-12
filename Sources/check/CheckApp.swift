import AppKit
import Observation
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
    // 할 일 한 벌(목록·투명도 설정·보드 창). 오버레이와 **형제**다 — 캐릭터 패널을 키워 보드를 담으면
    // 울트라 프레임 복귀·드래그 위치 영속·클릭통과 기계가 전부 얽힌다.
    // 셋을 낱개가 아니라 한 묶음으로 드는 이유는 TodoBoardWiring.Board 주석 참고(스토어 중복 생성 방지).
    private var todoBoard: TodoBoardWiring.Board?

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

    /// 할 일 보드를 만들고 오버레이 훅에 잇는다. **판단은 전부 배선(TodoBoardWiring)이** 하고 오버레이는
    /// 사실만 알린다. 여기서는 소유(수명)만 갖는다.
    ///
    /// 목록 파일은 계정별로 나눈다 — 한 맥을 여러 사람이 쓰거나 계정을 갈아탔을 때 남의 할 일이 보이면 안 된다.
    /// 로그인 전에는 `todos.local.json` 을 쓰고, 이 실행에서 세션이 이미 복구돼 있으면 그 계정 파일로 연다.
    ///
    /// **투명도는 반대로 계정별이 아니다.** 목록은 '내가 쓴 내용'이라 남에게 보이면 안 되지만, 투명도는
    /// 이 맥의 화면 사정(바탕화면 밝기·모니터·주변 조명)에 대한 답이라 계정과 아무 상관이 없고 새는 정보도
    /// 없다(숫자 하나다). 계정을 갈아탈 때마다 0.55 로 돌아가면 사용자는 원인 모를 설정 초기화로 읽는다 —
    /// 그래서 UserDefaults 한 키(check.todoBoardOpacity)에 **맥 단위**로 남긴다.
    ///
    /// 조립은 `TodoBoardWiring.assemble` 이 한다(여기서 `new` 를 흩뿌리면 투명도 스토어가 둘이 되는
    /// 사고를 아무도 못 막는다 — 그 함수 주석 참고). 이 메서드는 실행당 1회, 수명 소유만 갖는다.
    private func wireTodoBoard() {
        guard let overlay = overlayController else { return }
        todoBoard = TodoBoardWiring.assemble(
            overlay: overlay,
            listFileURL: TodoFileStore.defaultURL(userID: store.session?.userID),
            defaults: .standard,
            isTodoEnabled: { [weak self] in self?.store.isTodoEnabled ?? false }
        )
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

// MARK: - 캐릭터 ↔ 할 일 보드 배선

/// 캐릭터가 보드 쪽을 볼 때의 방향(순수 함수). -1 왼쪽 / +1 오른쪽.
///
/// 보드는 기본이 캐릭터 **왼쪽**이지만 화면 왼쪽 가장자리에서는 오른쪽으로 뒤집힌다(TodoBoardAnchor).
/// 그래서 방향을 -1 로 못 박으면 그 순간 캐릭터가 정확히 반대쪽을 본다 — 실제로 놓인 자리에서만 뽑는다.
/// 두 중심이 같으면(보드가 캐릭터를 덮도록 클램프된 극단) 오른쪽으로 본다 — 뒤집기가 실패해 왼쪽으로
/// 클램프된 경우는 보드 중심이 캐릭터보다 왼쪽이라 -1 이 나오므로, 이 동률은 사실상 겹침뿐이다.
enum BoardFacing {
    static func direction(boardMidX: CGFloat, characterMidX: CGFloat) -> Int {
        boardMidX < characterMidX ? -1 : 1
    }
}

/// 오버레이(캐릭터)와 할 일 보드를 잇는 **유일한** 배선. AppDelegate 안의 private 메서드로 두었더니
/// 앱을 실제로 띄우지 않고는 한 줄도 검증할 수 없었고, 테스트가 같은 규약을 **다시 써서** 통과시키는
/// 최악(뮤테이션이 하나도 안 죽는 거울 테스트)이 됐다. 그래서 밖으로 꺼냈다 — 테스트는 이 함수를 그대로
/// 부르고, AppDelegate 는 여기에 실제 store/보드를 물리기만 한다.
enum TodoBoardWiring {
    /// 보드 한 벌(목록 · 투명도 설정 · 창). AppDelegate 는 이 묶음 **하나만** 붙들면 된다.
    ///
    /// 낱개로 들지 않는 이유는 정리정돈이 아니라 **투명도 스토어가 둘이 되는 사고를 구조로 막기 위해서**다.
    /// `CheckTodoBoardController` 의 `appearance` 인자에는 기본값이 있다(컨트롤러는 설정의 주인이 아니라
    /// 소비자라서 그렇게 뒀다). 그래서 조립 지점이 여러 곳으로 흩어지면 누군가는 인자를 빠뜨리고, 그 순간
    /// 컨트롤러가 자기 스토어를 하나 더 만든다 — 슬라이더는 움직이는데 블러는 꿈쩍도 않고, 껐다 켜면
    /// 저장된 값과 화면이 어긋난다. 만드는 자리를 `assemble` 한 곳으로 못 박고 결과를 묶어서 넘긴다.
    @MainActor
    struct Board {
        let list: TodoListStore
        let appearance: TodoBoardAppearanceStore
        let board: CheckTodoBoardController
    }

    /// 보드를 조립하고 오버레이에 잇는다. AppDelegate 안 private 메서드로 두면 앱을 띄우지 않고는 한 줄도
    /// 검증할 수 없다 — `connect` 를 밖으로 꺼낸 것과 같은 이유이고, 테스트는 이 함수를 그대로 부른다.
    ///
    /// - Parameters:
    ///   - listFileURL: 할 일 파일(계정별로 갈린다 — 결정은 호출자가 한다).
    ///   - defaults: 투명도가 사는 저장소. 목록과 달리 **계정이 아니라 이 맥에 붙는다**(wireTodoBoard 주석).
    @MainActor
    static func assemble(
        overlay: CheckOverlayController,
        listFileURL: URL,
        defaults: UserDefaults = .standard,
        isTodoEnabled: @escaping () -> Bool,
        visibleFrame: @escaping @MainActor (NSPanel) -> NSRect = TodoBoardWiring.screenVisibleFrame(for:)
    ) -> Board {
        let list = TodoListStore(fileURL: listFileURL)
        let appearance = TodoBoardAppearanceStore(defaults: defaults)
        let board = CheckTodoBoardController(store: list, appearance: appearance)
        connect(overlay: overlay, board: board, isTodoEnabled: isTodoEnabled, visibleFrame: visibleFrame)
        return Board(list: list, appearance: appearance, board: board)
    }

    /// - Parameters:
    ///   - isTodoEnabled: 할 일 기능을 켠 사용자인가(store 를 직접 잡지 않기 위한 주입).
    ///   - visibleFrame: 캐릭터가 놓인 화면의 visibleFrame(클릭으로 보드를 여는 순간에만 쓴다 —
    ///     드래그/재배치 경로는 오버레이가 자기가 쓴 값을 함께 넘겨 준다). 테스트가 실제 모니터 배치에
    ///     의존하지 않도록 주입 지점을 남긴다.
    @MainActor
    static func connect(
        overlay: CheckOverlayController,
        board: CheckTodoBoardController,
        isTodoEnabled: @escaping () -> Bool,
        visibleFrame: @escaping @MainActor (NSPanel) -> NSRect = TodoBoardWiring.screenVisibleFrame(for:)
    ) {
        // 클로저는 오버레이가 소유하므로 overlay/board 를 강하게 잡으면 그대로 순환 참조다(앱 수명 내내
        // 사는 객체라 실사용에선 안 드러나지만, 테스트마다 패널이 살아남는다).
        overlay.onCharacterTapped = { [weak overlay, weak board] in
            guard let overlay, let board, isTodoEnabled() else { return false }
            board.toggle(anchor: overlay.panel.frame, screenVisibleFrame: visibleFrame(overlay.panel))
            faceTheBoard(overlay: overlay, board: board)
            return true
        }
        // 격발은 전체화면 연출이라 보드가 겹칠 수 없고, 방향도 정면이어야 한다(40° 돌아본 채로 화면을 덮으면
        // 캐릭터가 옆을 보고 서 있다). 닫은 뒤 faceTheBoard 를 태우면 '닫혔으니 정면'이 한 곳에서 나온다.
        overlay.onUltraBegan = { [weak overlay, weak board] in
            guard let overlay, let board else { return }
            board.close()
            faceTheBoard(overlay: overlay, board: board)
        }
        overlay.onUltraEnded = { _ in }   // 격발 뒤 자동 복원은 하지 않는다 — 사용자가 다시 열면 된다.
        overlay.onWorkEnded = { [weak overlay, weak board] in
            guard let overlay, let board else { return }
            board.close()
            faceTheBoard(overlay: overlay, board: board)
        }
        overlay.onCharacterFrameChanged = { [weak overlay, weak board] frame, visible in
            guard let overlay, let board else { return }
            board.reposition(anchor: frame, screenVisibleFrame: visible)
            // 보드가 반대편으로 뒤집혔을 수 있다(화면 가장자리로 끌고 가면 왼쪽↔오른쪽이 바뀐다).
            // 캐릭터가 계속 엉뚱한 쪽을 보지 않도록 옮길 때마다 방향을 다시 계산한다.
            faceTheBoard(overlay: overlay, board: board)
        }
        overlay.isBoardOpen = { [weak board] in board?.isBoardOpen ?? false }
        // 할 일 스위치를 끄는 순간 열려 있던 보드를 놓아준다(아래 감시자 주석 참고 — 안 하면 보드가 갇힌다).
        TodoDisableWatcher(overlay: overlay, board: board, isTodoEnabled: isTodoEnabled).start()
    }

    /// 캐릭터가 보드 쪽을 바라보게 한다(드래그 방향 전환 기계를 그대로 재사용). 보드가 닫혀 있으면 정면.
    ///
    /// `hasPanel` 을 함께 보는 이유: `board.panel` 은 **읽는 순간 지연 생성**되므로, 열지도 않은 보드의
    /// 위치를 물어보려다 창을 만들어 버리는 일이 없어야 한다.
    @MainActor
    static func faceTheBoard(overlay: CheckOverlayController, board: CheckTodoBoardController) {
        guard board.isBoardOpen, board.hasPanel else {
            overlay.engine.setDragFacing(0)
            return
        }
        overlay.engine.setDragFacing(
            BoardFacing.direction(boardMidX: board.panel.frame.midX, characterMidX: overlay.panel.frame.midX)
        )
    }

    /// 그 패널이 놓인 화면의 visibleFrame. 캐릭터를 끌어다 둔 화면이 기준이다 —
    /// NSScreen.main 은 키 윈도우가 없는 메뉴바 앱에서 무엇을 돌려줄지 계약이 불분명하다.
    @MainActor
    static func screenVisibleFrame(for panel: NSPanel) -> NSRect {
        let screens = NSScreen.screens
        func overlap(_ screen: NSScreen) -> CGFloat {
            let r = screen.frame.intersection(panel.frame)
            return r.isNull ? 0 : r.width * r.height
        }
        let best = screens.max { overlap($0) < overlap($1) }
        return (best ?? NSScreen.main ?? screens.first)?.visibleFrame ?? .zero
    }
}

/// 할 일 스위치가 **꺼지는 순간**만 지켜보다가, 열려 있던 보드를 닫고 캐릭터를 정면으로 되돌린다.
///
/// **왜 필요한가 — 안 하면 보드가 갇힌다.** 캐릭터 클릭 경로(`onCharacterTapped`)는 맨 앞에
/// `isTodoEnabled()` 가드가 있어서, 보드를 열어 둔 채 팝오버에서 할 일을 끄면 `board.toggle()` 이
/// **아예 안 불린다**. 그 순간부터 보드는 화면에 남고, 캐릭터는 계속 보드 쪽을 보고 서 있고,
/// ⌥+스크롤 로컬 모니터는 앱 전체 스크롤을 계속 들여다보고, 졸기는 `canEnterDrowsy` 의 `!isBoardOpen`
/// 때문에 **영구히 막힌다**. 탈출로는 보드 헤더 ✕ 나 근무 종료뿐이다. 원래 있던 결함이지만 이번 릴리스가
/// 그 스위치를 숨은 전원 메뉴에서 상시 보이는 캡션 행 버튼으로 끌어올려 도달 확률을 크게 높였다.
///
/// **왜 스토어가 아니라 배선에서 보는가**: `WorkTimerStore` 는 설정의 주인일 뿐 보드를 몰라야 한다.
/// `@Observable` 이므로 배선이 값 하나만 뒤에서 추적할 수 있다 — 스토어에 콜백 구멍을 뚫지 않는다.
///
/// **켜는 방향은 아무 일도 하지 않는다.** 보드는 사용자가 캐릭터를 눌러 여는 것이지, 설정을 켰다고
/// 저절로 튀어나오면 안 된다.
@MainActor
final class TodoDisableWatcher {
    private weak var overlay: CheckOverlayController?
    private weak var board: CheckTodoBoardController?
    private let isTodoEnabled: () -> Bool

    init(
        overlay: CheckOverlayController,
        board: CheckTodoBoardController,
        isTodoEnabled: @escaping () -> Bool
    ) {
        self.overlay = overlay
        self.board = board
        self.isTodoEnabled = isTodoEnabled
    }

    /// 감시를 건다. **수명은 호출자가 들지 않아도 된다** — 등록된 onChange 가 자신을 강하게 붙들기
    /// 때문이다. 대신 오버레이나 보드가 사라지면 다시 걸지 않으므로 그 시점에 스스로 풀린다.
    func start() { arm() }

    private func arm() {
        withObservationTracking {
            _ = isTodoEnabled()
        } onChange: { [self] in
            // Observation 의 onChange 는 값이 **바뀌기 직전**(willSet)에 온다 — 여기서 읽으면 옛 값이다.
            // 게다가 스위치를 누른 그 프레임의 SwiftUI 갱신 한가운데라, 창을 내리는 일은 한 틱 미룬다.
            Task { @MainActor in self.applyThenRearm() }
        }
    }

    private func applyThenRearm() {
        // 주인이 사라졌으면 다시 걸지 않는다 — 이 감시자를 붙들던 마지막 참조가 그 자리에서 함께 풀린다.
        guard let overlay, let board else { return }
        if !isTodoEnabled() {
            board.close()
            TodoBoardWiring.faceTheBoard(overlay: overlay, board: board)
        }
        arm()
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
