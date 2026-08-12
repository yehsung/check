import AppKit
import Foundation
import Testing
@testable import check

// MARK: - 투두 보드 ↔ 오버레이 배선 계약
//
// 조각별 테스트(모델·뷰·패널)는 각자 파일이 맡는다. 여기서 지키는 것은 **둘을 잇는 규약**이다:
// 클릭이 누구에게 가는가, 격발·근무종료가 보드를 어떻게 다루는가, 졸기가 보드를 존중하는가.
// 이 계약이 없으면 세 조각이 각자 초록불인 채로 앱에서는 아무 일도 안 일어난다.

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

/// CheckApp.wireTodoBoard 와 **같은 규약**으로 잇는다(앱 배선의 거울 — 여기서만 검증 가능한 계약이다).
@MainActor
private func wire(
    _ overlay: CheckOverlayController,
    _ board: CheckTodoBoardController,
    _ store: WorkTimerStore
) {
    let frame = NSRect(x: 900, y: 600, width: 140, height: 170)
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    overlay.onCharacterTapped = {
        guard store.isTodoEnabled else { return false }
        board.toggle(anchor: frame, screenVisibleFrame: visible)
        overlay.engine.setDragFacing(board.isBoardOpen ? -1 : 0)
        return true
    }
    overlay.onUltraBegan = { board.close() }
    overlay.onWorkEnded = {
        board.close()
        overlay.engine.setDragFacing(0)
    }
    overlay.isBoardOpen = { board.isBoardOpen }
}

// MARK: 클릭의 뜻은 설정 하나로 갈린다

@MainActor
@Test
func characterTapOpensBoardWhenTodoEnabled() {
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)
    defer { board.close() }

    store.setTodoEnabled(true)
    #expect(overlay.onCharacterTapped?() == true)   // true = 보드가 클릭을 가져갔다 → 아파하기 없음
    #expect(board.isBoardOpen)
    // 보드가 열린 동안 캐릭터는 보드 쪽(왼쪽)을 바라본다.
    #expect(overlay.engine.currentDragFacing == -1)

    #expect(overlay.onCharacterTapped?() == true)
    #expect(board.isBoardOpen == false)             // 다시 누르면 닫힌다
    #expect(overlay.engine.currentDragFacing == 0)  // 정면 복귀
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
    first.toggleTodoEnabled()
    #expect(first.isTodoEnabled == false)

    let relaunched = make()              // 앱을 껐다 켜도 선택이 유지된다
    defer { relaunched.tickerTask?.cancel(); relaunched.refreshTask?.cancel() }
    #expect(relaunched.isTodoEnabled == false)
}

// MARK: 생명주기 — 보드가 화면에서 비켜야 하는 순간들

@MainActor
@Test
func ultraTakeoverClosesTheBoard() {
    // 전체화면 격발 위에 보드가 겹칠 수는 없다. 입력 중이던 글은 컨트롤러가 들고 있으므로 사라지지 않는다.
    let (store, overlay) = makeOverlay()
    let (_, board) = makeBoard()
    wire(overlay, board, store)

    store.setTodoEnabled(true)
    _ = overlay.onCharacterTapped?()
    #expect(board.isBoardOpen)

    board.setDraft("적다 만 할 일")
    overlay.onUltraBegan?()
    #expect(board.isBoardOpen == false)
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
    _ = overlay.onCharacterTapped?()
    #expect(board.isBoardOpen)
    #expect(overlay.engine.currentDragFacing == -1)

    overlay.onWorkEnded?()
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
    store.setOverlayEnabled(true)
    overlay.updateWorking(true)              // 표시 중으로 만든다(졸기의 선행 조건)
    defer { overlay.updateWorking(false) }
    // 등장 리액션(commuteStart)이 재생 중이면 졸기는 원래 막힌다 — 그건 이 테스트의 관심사가 아니므로 걷어낸다.
    overlay.engine.cancelActiveReaction()

    #expect(overlay.canEnterDrowsy)          // 보드가 닫혀 있으면 존다

    store.setTodoEnabled(true)
    overlay.handleClick(at: overlay.panel.frame.center)
    #expect(board.isBoardOpen)
    #expect(overlay.canEnterDrowsy == false) // 보드가 열려 있으면 안 존다

    board.close()
    #expect(overlay.canEnterDrowsy)
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
    store.setOverlayEnabled(true)
    store.setTodoEnabled(true)
    overlay.updateWorking(true)
    defer { overlay.updateWorking(false) }

    // 표시 전이가 만든 등장 리액션을 걷어내고 idle 에서 출발한다.
    overlay.engine.cancelActiveReaction()
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
    store.setOverlayEnabled(true)
    store.setTodoEnabled(false)
    overlay.updateWorking(true)
    defer { overlay.updateWorking(false) }
    overlay.engine.cancelActiveReaction()

    overlay.handleClick(at: overlay.panel.frame.center)
    #expect(board.isBoardOpen == false)
    #expect(overlay.engine.state == .playing(.hit))
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
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
