import AppKit
import Foundation
import SceneKit
import Testing
@testable import check

// MARK: - 투두 보드 ↔ 오버레이 배선 계약
//
// 조각별 테스트(모델·뷰·패널)는 각자 파일이 맡는다. 여기서 지키는 것은 **둘을 잇는 규약**이다:
// 클릭이 누구에게 가는가, 격발·근무종료가 보드를 어떻게 다루는가, 졸기가 보드를 존중하는가,
// 캐릭터가 어느 쪽을 보는가, 캐릭터를 끌면 보드가 따라오는가.
// 이 계약이 없으면 세 조각이 각자 초록불인 채로 앱에서는 아무 일도 안 일어난다.
//
// ★ 이 파일은 **프로덕션 배선(TodoBoardWiring.connect)** 을 그대로 부른다. 예전에는 여기서 같은 규약을
//   다시 써 놓고(거울 배선) 통과시켰는데, 그러면 앱 쪽 클로저를 통째로 지워도 스위트가 초록이었다.
//   배선을 검증하려면 배선을 불러야 한다 — 새 테스트를 추가할 때도 이 규칙을 깨지 말 것.

@MainActor
private func makeOverlay() -> (WorkTimerStore, CheckOverlayController) {
    let suite = "check-todo-int-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    let controller = CheckOverlayController(
        store: store,
        notificationCenter: NotificationCenter(),
        engine: ReactionEngine(clock: { Date(timeIntervalSince1970: 700_000) }),
        defaults: defaults,
        workspaceNotifications: nil
    )
    return (store, controller)
}

@MainActor
private func makeBoard() -> (TodoListStore, CheckTodoBoardController) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("todo-int-\(UUID().uuidString).json")
    let list = TodoListStore(fileURL: url)
    return (list, CheckTodoBoardController(store: list))
}

/// 화면 좌표를 쓰는 가상 데스크톱. 클릭으로 보드를 여는 경로에만 쓰이며(드래그 경로는 오버레이가 자기가
/// 클램프에 쓴 화면을 함께 넘긴다), 실제 모니터 배치와 무관하게 좌우 뒤집힘을 결정적으로 재현하기 위한 값이다.
private let integrationVisibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)

/// **프로덕션 배선**을 그대로 건다(거울 배선 금지 — 파일 상단 주석 참고).
@MainActor
private func wire(
    _ overlay: CheckOverlayController,
    _ board: CheckTodoBoardController,
    _ store: WorkTimerStore,
    visible: NSRect = integrationVisibleFrame
) {
    TodoBoardWiring.connect(
        overlay: overlay,
        board: board,
        isTodoEnabled: { store.isTodoEnabled },
        visibleFrame: { _ in visible }
    )
}

/// 캐릭터 패널을 원하는 자리에 놓는다(방향·뒤집힘 판정은 전부 이 좌표에서 나온다).
@MainActor
private func placeCharacter(_ overlay: CheckOverlayController, at origin: NSPoint) {
    overlay.panel.setFrame(
        NSRect(origin: origin, size: CheckOverlayController.panelSize),
        display: false
    )
}

/// 드래그 경로가 쓰는 **실제** 화면 visibleFrame. 오버레이는 드래그 중 커서가 놓인 화면으로 클램프하므로,
/// 그 경로를 검증하는 테스트는 가상 좌표를 쓸 수 없다(클램프가 모든 이동을 삼켜 버린다).
@MainActor
private func realVisibleFrame() -> NSRect {
    NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? integrationVisibleFrame
}

/// 근무중·캐릭터 표시 상태로 만들고 등장 리액션을 걷어낸다(클릭/드래그 경로의 선행 조건).
///
/// 근무중을 **스토어에서부터** 세운다. `updateWorking(true)` 만 부르면 컨트롤러는 '표시 중'인데
/// `store.snapshot` 은 '비근무'인, 프로덕션에 없는 조합이 된다 — 그 상태에서 패널 프레임이 바뀌면
/// NSHostingView 가 그 자리에서 SwiftUI 를 재평가하고 `.onChange(of: isWorking, initial: true)` 가
/// `onWorkingChange(false)` 를 흘려 **테스트만의 유령 근무종료**가 난다(격발 테스트에서 실제로 겪었다).
@MainActor
private func makeVisible(_ overlay: CheckOverlayController, _ store: WorkTimerStore) {
    store.setOverlayEnabled(true)
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
    overlay.updateWorking(true)
    overlay.engine.cancelActiveReaction()
}

// MARK: 클릭의 뜻은 설정 하나로 갈린다

@MainActor
@Test
func characterTapOpensBoardWhenTodoEnabled() {
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)
    defer { board.close() }
    // 왼쪽에 보드(300pt)가 넉넉히 들어가는 자리 — 기본 배치(캐릭터 왼쪽)가 나온다.
    placeCharacter(overlay, at: NSPoint(x: 1_000, y: 600))

    store.setTodoEnabled(true)
    #expect(overlay.onCharacterTapped?() == true)   // true = 보드가 클릭을 가져갔다 → 아파하기 없음
    #expect(board.isBoardOpen)
    // 보드가 실제로 캐릭터 왼쪽에 놓였고, 캐릭터도 그쪽을 본다.
    #expect(board.panel.frame.midX < overlay.panel.frame.midX)
    #expect(overlay.engine.currentDragFacing == -1)

    #expect(overlay.onCharacterTapped?() == true)
    #expect(board.isBoardOpen == false)             // 다시 누르면 닫힌다
    #expect(overlay.engine.currentDragFacing == 0)  // 정면 복귀
}

@MainActor
@Test
func characterTapFacesRightWhenBoardFlipsToTheOtherSide() {
    // ★ 방향을 -1 로 못 박으면 여기서 죽는다. 화면 왼쪽 가장자리에서는 보드가 **오른쪽으로 뒤집히고**,
    //   그때 캐릭터가 왼쪽을 보면 정확히 반대쪽(빈 화면)을 응시한다.
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)
    defer { board.close() }
    placeCharacter(overlay, at: NSPoint(x: integrationVisibleFrame.minX, y: 600))

    store.setTodoEnabled(true)
    #expect(overlay.onCharacterTapped?() == true)
    #expect(board.isBoardOpen)
    // 왼쪽에 자리가 없어 오른쪽으로 뒤집혔다.
    #expect(board.panel.frame.minX == overlay.panel.frame.maxX + TodoBoardAnchor.gap)
    #expect(overlay.engine.currentDragFacing == 1)
}

@MainActor
@Test
func characterTapFallsBackToHitWhenTodoDisabled() {
    // 기능을 끈 사람에게 클릭은 예전 그대로 '아얏'이어야 한다. 배선이 false 를 돌려주면
    // 오버레이가 engine.request(.hit) 을 재생한다 — 그 분기가 살아 있는지 값으로 고정한다.
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)

    store.setTodoEnabled(false)
    #expect(overlay.onCharacterTapped?() == false)
    #expect(board.isBoardOpen == false)
    #expect(overlay.engine.currentDragFacing == 0)   // 볼 보드가 없으니 정면 그대로
}

@MainActor
@Test
func todoEnabledDefaultsOnAndPersists() {
    let suite = "check-todo-pref-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    func make() -> WorkTimerStore {
        WorkTimerStore(
            environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
            defaults: defaults, workspaceNotifications: nil
        )
    }
    let first = make()
    defer { first.tickerTask?.cancel(); first.refreshTask?.cancel() }
    #expect(first.isTodoEnabled)         // 기본은 켬(새 기능을 발견하게)
    // 설정 창 토글이 실제로 부르는 경로로 뒤집는다(옛 toggleTodoEnabled 는 호출부가 사라져 v0.2.32 에 삭제).
    first.setTodoEnabled(false)
    #expect(first.isTodoEnabled == false)

    let relaunched = make()              // 앱을 껐다 켜도 선택이 유지된다
    defer { relaunched.tickerTask?.cancel(); relaunched.refreshTask?.cancel() }
    #expect(relaunched.isTodoEnabled == false)
}

// MARK: 방향이 실제로 **살아남는가** — 신고 ①

@MainActor
@Test
func boardFacingSurvivesTheMouseUpThatOpenedTheBoard() {
    // ★ 이 신고의 정확한 재현: 클릭은 down→up 두 이벤트다. handleClick 이 보드를 열며 방향을 세우자마자
    //   handleMouseUp 꼬리가 무조건 setDragFacing(0) 을 불러, "보드 쪽을 본다"가 한 프레임도 못 살고 죽었다.
    //   onCharacterTapped 만 직접 부르는 테스트로는 이 구멍이 **절대** 안 보인다 — 실제 마우스 경로로 친다.
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)
    store.setTodoEnabled(true)
    makeVisible(overlay, store)
    defer { overlay.updateWorking(false) }
    placeCharacter(overlay, at: NSPoint(x: 1_000, y: 600))

    let center = NSPoint(x: overlay.panel.frame.midX, y: overlay.panel.frame.midY)
    overlay.handleMouseDown(at: center)
    #expect(overlay.engine.currentDragFacing == 0)   // 제스처 시작은 정면
    overlay.handleMouseUp(at: center)                // 이동 없음 → 클릭 판정

    #expect(board.isBoardOpen)
    #expect(overlay.engine.currentDragFacing == -1)  // ★ 업 이후에도 보드 쪽을 보고 있어야 한다

    // 같은 자리를 한 번 더 누르면 닫히고 정면으로 돌아온다(닫힌 뒤에는 꼬리의 정면 복귀가 다시 유효하다).
    overlay.handleMouseDown(at: center)
    overlay.handleMouseUp(at: center)
    #expect(board.isBoardOpen == false)
    #expect(overlay.engine.currentDragFacing == 0)
}

// MARK: 드래그하면 보드가 따라온다 — 신고 ②

@MainActor
@Test
func boardFollowsCharacterWhileDragging() {
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    let visible = realVisibleFrame()
    wire(overlay, board, store, visible: visible)
    store.setTodoEnabled(true)
    makeVisible(overlay, store)
    defer { overlay.updateWorking(false) }

    // 오른쪽 위 근처(보드가 왼쪽에 들어가는 자리)에서 시작해 **오른쪽으로** 끈다.
    let origin = NSPoint(x: visible.maxX - 200, y: visible.maxY - 200)
    placeCharacter(overlay, at: origin)
    let center = NSPoint(x: overlay.panel.frame.midX, y: overlay.panel.frame.midY)
    overlay.handleClick(at: center)
    #expect(board.isBoardOpen)
    #expect(board.panel.frame.maxX == overlay.panel.frame.minX - TodoBoardAnchor.gap)

    let moved = NSPoint(x: center.x + 40, y: center.y - 30)
    overlay.handleMouseDown(at: center)
    overlay.handleMouseDragged(at: moved)

    // ① 캐릭터가 실제로 움직였고 ② 보드가 **드래그 중에** 그 옆에 붙어 따라왔다(이게 신고의 핵심).
    #expect(overlay.panel.frame.origin.x == origin.x + 40)
    #expect(overlay.panel.frame.origin.y == origin.y - 30)
    #expect(board.panel.frame.maxX == overlay.panel.frame.minX - TodoBoardAnchor.gap)
    #expect(board.panel.frame.maxY == overlay.panel.frame.maxY)
    // 끄는 동안에는 '가는 방향'(오른쪽)을 본다 — 보드는 왼쪽이지만 드래그 방향이 이긴다.
    #expect(overlay.engine.currentDragFacing == 1)

    overlay.handleMouseUp(at: moved)
    #expect(board.isBoardOpen)                       // 드래그는 보드를 토글하지 않는다
    #expect(board.panel.frame.maxX == overlay.panel.frame.minX - TodoBoardAnchor.gap)
    #expect(overlay.engine.currentDragFacing == -1)  // 손을 떼면 다시 보드 쪽
}

@MainActor
@Test
func draggingToTheEdgeFlipsBoardAndFacingTogether() {
    // 왼쪽 끝까지 끌면 보드가 오른쪽으로 뒤집힌다. 그때 방향도 같이 뒤집혀야 한다 —
    // 뒤집힘 이후의 방향을 정하는 유일한 지점이 handleMouseUp 의 마지막 프레임 통지다.
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    let visible = realVisibleFrame()
    wire(overlay, board, store, visible: visible)
    store.setTodoEnabled(true)
    makeVisible(overlay, store)
    defer { overlay.updateWorking(false) }

    placeCharacter(overlay, at: NSPoint(x: visible.minX + 400, y: visible.maxY - 200))
    let center = NSPoint(x: overlay.panel.frame.midX, y: overlay.panel.frame.midY)
    overlay.handleClick(at: center)
    #expect(board.isBoardOpen)
    #expect(board.panel.frame.maxX == overlay.panel.frame.minX - TodoBoardAnchor.gap)  // 처음엔 왼쪽
    #expect(overlay.engine.currentDragFacing == -1)

    // 왼쪽 화면 끝으로(클램프에 닿도록 넉넉히) 끈다.
    let moved = NSPoint(x: center.x - 400, y: center.y)
    overlay.handleMouseDown(at: center)
    overlay.handleMouseDragged(at: moved)
    #expect(overlay.panel.frame.minX == visible.minX)   // 클램프에 닿았다
    overlay.handleMouseUp(at: moved)

    // 왼쪽에 자리가 없어 보드가 오른쪽으로 넘어갔고, 캐릭터도 오른쪽을 본다(끌던 방향은 왼쪽이었다).
    #expect(board.panel.frame.minX == overlay.panel.frame.maxX + TodoBoardAnchor.gap)
    #expect(overlay.engine.currentDragFacing == 1)
}

@MainActor
@Test
func closedBoardIsNotNotifiedWhileDragging() {
    // 드래그는 60Hz 경로다. 보드가 닫혀 있으면 받는 쪽이 어차피 조기 반환하므로 **아예 부르지 않는다** —
    // 부르면 배선이 프레임마다 '보드 없음 → 정면'을 계산해 드래그 방향과 번갈아 쓰며 헛 회전을 남긴다.
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    let visible = realVisibleFrame()
    wire(overlay, board, store, visible: visible)
    store.setTodoEnabled(true)
    makeVisible(overlay, store)
    defer { overlay.updateWorking(false) }
    placeCharacter(overlay, at: NSPoint(x: visible.maxX - 200, y: visible.maxY - 200))

    // 프로덕션 배선을 감싸 통지 횟수만 센다(배선 자체는 그대로 살려 둔다).
    let counter = CallCounter()
    let production = overlay.onCharacterFrameChanged
    overlay.onCharacterFrameChanged = { frame, screenVisible in
        counter.count += 1
        production?(frame, screenVisible)
    }

    let center = NSPoint(x: overlay.panel.frame.midX, y: overlay.panel.frame.midY)
    let moved = NSPoint(x: center.x - 50, y: center.y - 20)
    overlay.handleMouseDown(at: center)
    overlay.handleMouseDragged(at: moved)
    overlay.handleMouseUp(at: moved)
    #expect(counter.count == 0)          // 닫힌 보드에게는 한 번도 알리지 않는다

    // 열고 같은 드래그를 하면 매 프레임 + 놓는 순간까지 알린다.
    overlay.handleClick(at: NSPoint(x: overlay.panel.frame.midX, y: overlay.panel.frame.midY))
    #expect(board.isBoardOpen)
    let opened = NSPoint(x: overlay.panel.frame.midX, y: overlay.panel.frame.midY)
    overlay.handleMouseDown(at: opened)
    overlay.handleMouseDragged(at: NSPoint(x: opened.x - 20, y: opened.y))
    overlay.handleMouseDragged(at: NSPoint(x: opened.x - 40, y: opened.y))
    overlay.handleMouseUp(at: NSPoint(x: opened.x - 40, y: opened.y))
    #expect(counter.count == 3)          // dragged 2 + mouseUp 1
}

/// 클로저 안에서 세는 카운터(값 타입 캡처 대신 참조로 둬 배선 교체 전후 계산을 헷갈리지 않게).
@MainActor
private final class CallCounter {
    var count = 0
}

// MARK: 캐릭터 뷰를 다시 만들어도 방향이 살아남는가 — 재-attach facing 고착

/// 캐릭터 SCNView 한 번의 마운트(씬 + 뷰 + facing 노드). 엔진은 이 셋을 **전부 weak** 로 잡으므로
/// 테스트가 붙들고 있지 않으면 attach 직후 통째로 해제돼 아무것도 관찰할 수 없다.
@MainActor
private struct CharacterMount {
    let scene: SCNScene
    let view: SCNView
    let facing: SCNNode
    /// facing 노드가 **실제로** 돌아간 각(y). 엔진이 값만 들고 노드를 안 돌리면 여기가 0 으로 남는다.
    var yaw: CGFloat { facing.eulerAngles.y }
}

/// 캐릭터 뷰를 새로 마운트한다 — `makeNSView` 가 하는 일 그대로다(새 씬을 만들고 그 wrapper 를 attach).
@MainActor
private func mountCharacter(into engine: ReactionEngine) throws -> CharacterMount {
    let scene = try #require(CheckCharacter3DScene.makeScene(animated: false))
    let wrapper = try #require(
        scene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)
    )
    let facing = try #require(
        wrapper.childNode(withName: CheckCharacter3DScene.facingWrapperName, recursively: false)
    )
    let view = SCNView()
    engine.attach(node: wrapper, sceneRoot: scene.rootNode, view: view)
    return CharacterMount(scene: scene, view: view, facing: facing)
}

@MainActor
@Test
func boardFacingSurvivesACharacterViewRemount() throws {
    // ☠︎ 잠재 결함: attach 가 새 facing 노드를 찾은 뒤 **보관 중인 방향을 다시 적용하지 않으면**,
    //   재-attach 한 번에 "값은 -1, 노드는 정면"으로 갈라진다. 그리고 setDragFacing 의 `==` 가드가
    //   같은 방향 재요청을 삼키므로 그 어긋남은 **그 실행 내내 복구되지 않는다** — 보드를 열어도
    //   캐릭터가 영원히 안 쳐다본다. 지금은 SCNView 아이덴티티가 고정돼 attach 가 실행당 1회뿐이라
    //   화면에 드러나지 않을 뿐이고, 그 래치는 이 결함과 무관한 이유로 언제든 풀린다.
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)
    defer { board.close() }
    store.setTodoEnabled(true)
    placeCharacter(overlay, at: NSPoint(x: 1_000, y: 600))

    let first = try mountCharacter(into: overlay.engine)
    #expect(overlay.onCharacterTapped?() == true)
    #expect(overlay.engine.currentDragFacing == -1)
    #expect(abs(first.yaw + ReactionEngine.dragFacingAngle) < 1e-6)   // 왼쪽(-40°)을 본다

    // 캐릭터 뷰가 다시 만들어진다(makeNSView 재실행) — 씬도 facing 노드도 새것이다.
    let second = try mountCharacter(into: overlay.engine)
    #expect(second.facing !== first.facing)
    // ★ 보관 중인 방향이 새 노드에 다시 적용돼야 한다. attach 의 재적용 한 줄을 지우면 여기서 죽는다.
    #expect(abs(second.yaw + ReactionEngine.dragFacingAngle) < 1e-6)

    // ★ 그리고 그건 영구 고착이다: 값이 이미 -1 이라 배선이 같은 -1 을 다시 계산해 넣어도
    //   `==` 가드가 그 갱신을 삼킨다(재적용이 없으면 여기서도 노드는 정면인 채 남는다).
    TodoBoardWiring.faceTheBoard(overlay: overlay, board: board)
    #expect(abs(second.yaw + ReactionEngine.dragFacingAngle) < 1e-6)

    // 방향 전환 자체는 그대로 살아 있다 — 보드를 닫으면 **새** 노드가 정면으로 돌아온다.
    #expect(overlay.onCharacterTapped?() == true)
    #expect(board.isBoardOpen == false)
    #expect(overlay.engine.currentDragFacing == 0)
    #expect(abs(second.yaw) < 1e-6)
}

// MARK: 생명주기 — 보드가 화면에서 비켜야 하는 순간들

@MainActor
@Test
func ultraTakeoverClosesTheBoard() {
    // 전체화면 격발 위에 보드가 겹칠 수는 없다. 입력 중이던 글은 컨트롤러가 들고 있으므로 사라지지 않는다.
    // ★ onUltraBegan 을 직접 부르지 않는다 — **실제 수신 경로**(handleReceivedPokes)로 쳐야
    //   beginUltraTakeover 가 그 훅을 부르는지까지 함께 고정된다.
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)
    store.setTodoEnabled(true)
    makeVisible(overlay, store)
    defer { overlay.updateWorking(false) }
    placeCharacter(overlay, at: NSPoint(x: 1_000, y: 600))

    overlay.handleClick(at: NSPoint(x: overlay.panel.frame.midX, y: overlay.panel.frame.midY))
    #expect(board.isBoardOpen)
    #expect(overlay.engine.currentDragFacing == -1)

    board.setDraft("적다 만 할 일")
    overlay.handleReceivedPokes([
        ReceivedPoke(id: "u1", fromName: "김철수", createdAt: Date(timeIntervalSince1970: 700_000), kind: .ultra)
    ])
    #expect(overlay.isUltraActive)
    #expect(board.isBoardOpen == false)
    // 전체화면 연출 중에 캐릭터가 옆을 보고 서 있으면 안 된다.
    #expect(overlay.engine.currentDragFacing == 0)
    // ★ 초안은 살아남는다 — 뷰 @State 였다면 여기서 통째로 날아간다.
    #expect(board.draft == "적다 만 할 일")
}

@MainActor
@Test
func workEndClosesTheBoardAndFacesForward() {
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)
    store.setTodoEnabled(true)
    makeVisible(overlay, store)
    placeCharacter(overlay, at: NSPoint(x: 1_000, y: 600))
    let center = NSPoint(x: overlay.panel.frame.midX, y: overlay.panel.frame.midY)

    overlay.handleClick(at: center)
    #expect(board.isBoardOpen)
    #expect(overlay.engine.currentDragFacing == -1)

    // ① 훅 **자체**의 계약: 보드를 닫고 정면으로 돌린다.
    //    실제 종료 경로에는 removeMouseMoveMonitor 의 정면 복귀가 하나 더 있어서, 아래 ②만으로는
    //    이 훅이 방향을 놓아 버려도 초록불이다(뮤테이션 M8 로 실증). 두 번째 방어선은 여기서만 고정된다.
    overlay.onWorkEnded?()
    #expect(board.isBoardOpen == false)
    #expect(overlay.engine.currentDragFacing == 0)

    // ② 실제 경로: updateWorking(false) 가 그 훅을 부르는가(배선만 확인하면 호출 지점이 사라져도 초록불).
    overlay.handleClick(at: center)
    #expect(board.isBoardOpen)
    #expect(overlay.engine.currentDragFacing == -1)
    overlay.updateWorking(false)
    #expect(board.isBoardOpen == false)
    #expect(overlay.engine.currentDragFacing == 0)
}

@MainActor
@Test
func drowsySchedulerRespectsAnOpenBoard() {
    // ★ 오버레이의 **실제 판정 프로퍼티**를 부른다. 배선 클로저만 확인하면 졸기 가드에서 조건이
    //   통째로 사라져도 테스트는 초록불이다(뮤테이션으로 실제로 겪었다).
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)
    makeVisible(overlay, store)              // 표시 중으로 만든다(졸기의 선행 조건)
    defer { overlay.updateWorking(false) }

    #expect(overlay.canEnterDrowsy)          // 보드가 닫혀 있으면 존다

    store.setTodoEnabled(true)
    overlay.handleClick(at: overlay.panel.frame.center)
    #expect(board.isBoardOpen)
    #expect(overlay.canEnterDrowsy == false) // 보드가 열려 있으면 안 존다

    board.close()
    #expect(overlay.canEnterDrowsy)
}

/// 할 일 스위치 감시자는 값이 **바뀐 뒤**(Observation 의 onChange 는 willSet 이라 한 틱 뒤에 움직인다)
/// 일하므로, 그 한 틱을 실제로 흘려 준다. 동기 테스트는 이 지점을 아예 못 본다.
private func settleTodoSwitch() async {
    for _ in 0..<10 { await Task.yield() }
}

@MainActor
@Test
func turningTodoOffReleasesTheBoardThatCanNoLongerBeReached() async {
    // ★ 할 일을 끄면 캐릭터 클릭이 `isTodoEnabled()` 가드에 걸려 `board.toggle()` 까지 가지 못한다.
    //   그래서 열어 둔 채로 끄면 보드를 닫을 손잡이가 사라지고(헤더 ✕·근무 종료뿐), 캐릭터는 계속 보드
    //   쪽을 보고 서 있고, 졸기가 `!isBoardOpen` 가드에 막혀 영구히 멈춘다. 끄는 순간 놓아 줘야 한다.
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)
    makeVisible(overlay, store)
    defer { overlay.updateWorking(false) }

    store.setTodoEnabled(true)
    overlay.handleClick(at: overlay.panel.frame.center)
    #expect(board.isBoardOpen)
    #expect(overlay.engine.currentDragFacing != 0)   // 보드 쪽을 보고 있다
    #expect(overlay.canEnterDrowsy == false)         // 보드가 열려 있으니 못 존다

    store.setTodoEnabled(false)
    await settleTodoSwitch()

    #expect(board.isBoardOpen == false)              // 갇히지 않는다
    #expect(overlay.engine.currentDragFacing == 0)   // 없는 보드를 바라보고 있지 않다
    // 한 틱을 흘려 주는 사이 SwiftUI 재통지가 표시 전환 리액션(commuteStart)을 다시 건다 — 졸기의
    // 나머지 두 조건(표시 중·리액션 없음)에 얹히는 잡음이라 걷어 내고, 이번에 고친 조건만 남겨 묻는다.
    overlay.engine.cancelActiveReaction()
    #expect(overlay.canEnterDrowsy)                  // 졸기가 다시 가능하다

    // 다시 켜는 건 아무 일도 아니다 — 보드는 사용자가 캐릭터를 눌러 여는 것이다.
    store.setTodoEnabled(true)
    await settleTodoSwitch()
    #expect(board.isBoardOpen == false)
    #expect(overlay.engine.currentDragFacing == 0)
}

// MARK: 실제 클릭 경로 — handleClick 이 보드로 가는가, 아파하기로 가는가

@MainActor
@Test
func realClickPathRoutesToBoardAndSkipsHit() {
    // ★ 배선 클로저가 아니라 **오버레이의 handleClick** 을 직접 부른다.
    //   보드가 클릭을 가져가면 아파하기 리액션이 재생되지 않아야 한다(두 연출이 겹치지 않게).
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)
    store.setTodoEnabled(true)
    makeVisible(overlay, store)
    defer { overlay.updateWorking(false) }
    #expect(overlay.engine.state == .idle)

    overlay.handleClick(at: overlay.panel.frame.center)
    #expect(board.isBoardOpen)
    #expect(overlay.engine.state == .idle)   // 아파하기가 재생되지 않았다
}

@MainActor
@Test
func realClickPathPlaysHitWhenTodoDisabled() {
    // 기능을 끈 사람에게는 같은 클릭이 예전 그대로 '아얏'이어야 한다.
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)
    store.setTodoEnabled(false)
    makeVisible(overlay, store)
    defer { overlay.updateWorking(false) }

    overlay.handleClick(at: overlay.panel.frame.center)
    #expect(board.isBoardOpen == false)
    #expect(overlay.engine.state == .playing(.hit))
    #expect(overlay.engine.currentDragFacing == 0)
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}

// MARK: 투명도 설정 — 스토어는 앱 전체에 **하나**여야 한다

/// 패널 계층에서 블러 뷰를 찾는다. 컨트롤러는 설정 스토어를 private 로 들고 있으므로 "같은 인스턴스인가"를
/// 직접 물을 수 없다 — 대신 **값이 화면까지 도달하는가**로 묻는다(스토어가 둘이면 여기서 끊긴다).
@MainActor
private func firstBlurView(in view: NSView?) -> NSVisualEffectView? {
    guard let view else { return nil }
    if let effect = view as? NSVisualEffectView { return effect }
    for sub in view.subviews {
        if let found = firstBlurView(in: sub) { return found }
    }
    return nil
}

/// 투명도가 사는 임시 저장소. 실제 사용자 설정(.standard)을 건드리지 않는다.
private func makeAppearanceDefaults() -> UserDefaults {
    let suite = "check-todo-appearance-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// 계정별 할 일 파일 자리(계정이 갈리면 이 URL 이 갈린다).
private func makeTodoFileURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("todo-int-\(UUID().uuidString).json")
}

@MainActor
@Test
func assembledBoardHangsOnTheSameAppearanceStore() throws {
    // ★ 앱이 실제로 부르는 조립 함수(TodoBoardWiring.assemble)를 그대로 부른다 — 여기서 다시 조립하면
    //   "AppDelegate 는 스토어를 두 개 만드는데 테스트만 하나로 조립해 초록"이 된다.
    //   스토어가 둘이면(컨트롤러 init 의 appearance 기본값을 그냥 두면 정확히 그렇게 된다) 값은 움직이는데
    //   창은 그대로다. 그래서 인스턴스 개수를 **화면까지 도달하는가**로 묻는다.
    let (store, overlay) = makeOverlay()
    let parts = TodoBoardWiring.assemble(
        overlay: overlay,
        listFileURL: makeTodoFileURL(),
        defaults: makeAppearanceDefaults(),
        isTodoEnabled: { store.isTodoEnabled },
        visibleFrame: { _ in integrationVisibleFrame }
    )
    defer { parts.board.close() }
    store.setTodoEnabled(true)
    placeCharacter(overlay, at: NSPoint(x: 1_000, y: 600))

    // 조립이 배선까지 걸었다 — 조립만 하고 잇지 않으면 캐릭터를 눌러도 아무 일도 일어나지 않는다.
    #expect(overlay.onCharacterTapped?() == true)
    #expect(parts.board.isBoardOpen)

    let blur = try #require(firstBlurView(in: parts.board.panel.contentView))
    #expect(abs(blur.alphaValue - CGFloat(parts.appearance.appearance.blurAlpha)) < 1e-6)

    // 슬라이더를 끝까지 내린다(블러가 완전히 걷히는 값). 스토어가 하나면 창이 그 자리에서 따라온다.
    parts.appearance.setOpacity(TodoBoardAppearance.minOpacity)
    #expect(parts.appearance.appearance.blurAlpha == 0)
    #expect(abs(blur.alphaValue) < 1e-6)
}

@MainActor
@Test
func opacityFollowsTheMacAcrossRestartsAndAccountSwitches() throws {
    // 사용자가 맞춘 투명도는 **이 맥의 화면 사정**(바탕화면 밝기·모니터·조명)에 대한 답이다 —
    // 앱을 껐다 켜도, 계정을 갈아타도 그대로여야 한다. 할 일 '목록'은 반대로 계정별 파일이고,
    // 두 성격이 갈리는 지점이라 한 테스트에서 나란히 못 박는다.
    let defaults = makeAppearanceDefaults()
    let (storeA, overlayA) = makeOverlay()
    let first = TodoBoardWiring.assemble(
        overlay: overlayA, listFileURL: makeTodoFileURL(), defaults: defaults,
        isTodoEnabled: { storeA.isTodoEnabled }, visibleFrame: { _ in integrationVisibleFrame }
    )
    defer { first.board.close() }
    first.appearance.setOpacity(0.30)

    // 앱 재시작 근사 ①: 같은 저장소에서 새로 만든 스토어가 그 값을 읽는다.
    #expect(TodoBoardAppearanceStore(defaults: defaults).appearance.opacity == 0.30)

    // 앱 재시작 근사 ② + 계정 전환: 다른 계정 파일로 다시 조립해도 투명도는 따라온다.
    let (storeB, overlayB) = makeOverlay()
    let second = TodoBoardWiring.assemble(
        overlay: overlayB, listFileURL: makeTodoFileURL(), defaults: defaults,
        isTodoEnabled: { storeB.isTodoEnabled }, visibleFrame: { _ in integrationVisibleFrame }
    )
    defer { second.board.close() }
    #expect(second.list !== first.list)                     // 목록은 갈렸는데
    #expect(second.appearance.appearance.opacity == 0.30)   // 투명도는 그대로다

    // 그리고 **처음 여는 창**부터 그 값으로 선다(통지는 값이 바뀔 때만 오므로 창이 스스로 읽어야 한다).
    let blur = try #require(firstBlurView(in: second.board.panel.contentView))
    #expect(second.appearance.appearance.blurAlpha < 1)     // 0.30 은 무릎점 아래 — 블러가 걷힌 값이다
    #expect(abs(blur.alphaValue - CGFloat(second.appearance.appearance.blurAlpha)) < 1e-6)
}

// MARK: 목록 규칙 — 사용자가 확정한 이월 계약

@MainActor
@Test
func completedItemsStayTodayAndVanishTomorrow() {
    // 사용자 확정 규칙: 완료는 **그날 안에는 계속 보이고**, 자정을 넘기면 사라진다.
    // 미완료는 이월되며 '어제' 배지가 붙는다.
    let today = Date(timeIntervalSince1970: 1_800_000)
    let todayKey = TodoRules.dayKey(today)
    let tomorrowKey = TodoRules.dayKey(today.addingTimeInterval(24 * 3600))

    var done = TodoItem(
        id: UUID(), title: "스탠드업", createdAt: today, updatedAt: today,
        completedAt: today, deletedAt: nil, originDayKey: todayKey
    )
    let open = TodoItem(
        id: UUID(), title: "배포 스크립트 정리", createdAt: today, updatedAt: today,
        completedAt: nil, deletedAt: nil, originDayKey: todayKey
    )

    // 오늘: 둘 다 보인다(완료를 접지 않는다).
    #expect(TodoRules.isVisible(done, todayKey: todayKey))
    #expect(TodoRules.isVisible(open, todayKey: todayKey))

    // 내일: 완료는 사라지고 미완료만 남는다.
    #expect(TodoRules.isVisible(done, todayKey: tomorrowKey) == false)
    #expect(TodoRules.isVisible(open, todayKey: tomorrowKey))
    #expect(TodoRules.carryBadge(
        days: TodoRules.carriedDays(originDayKey: open.originDayKey, todayKey: tomorrowKey)
    ) == "어제")

    // 완료 취소하면 그 항목도 다시 이월 대상이 된다(완료 시각만 지워지고 귀속일은 그대로).
    done.completedAt = nil
    #expect(TodoRules.isVisible(done, todayKey: tomorrowKey))
}
