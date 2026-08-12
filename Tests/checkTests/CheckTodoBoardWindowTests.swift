import AppKit
import SwiftUI
import Testing
@testable import check

// MARK: - 헬퍼

/// 실홈 파일을 건드리지 않는 격리 스토어(파일명이 매번 다르므로 테스트끼리도 섞이지 않는다).
@MainActor
private func makeTodoBoardStore() -> TodoListStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("check-todo-board-\(UUID().uuidString).json")
    return TodoListStore(fileURL: url)
}

/// 보드가 실제로 그리게 될 목록(표시 규칙 통과분)의 id 들. '삭제가 확정됐는가'를 store 내부 표현
/// (하드 삭제인지 deletedAt 인지)에 기대지 않고 **사용자가 보는 화면 기준**으로 판정하기 위한 것.
@MainActor
private func todoBoardVisibleIDs(_ store: TodoListStore) -> [UUID] {
    TodoRules.visible(store.items, todayKey: store.todayKey).map(\.id)
}

/// 어느 맥에서 돌려도 화면 안에 들어오는 가상 visibleFrame(패널 프레임 비교가 화면 클램프에 걸리지 않게).
private let todoBoardTestVisibleFrame = NSRect(x: 0, y: 0, width: 1_280, height: 800)
/// 캐릭터 기본 크기(140×170)의 앵커. 보드는 이 왼쪽 (490, 170)-(790, 570) 에 선다.
private let todoBoardTestAnchor = NSRect(x: 800, y: 400, width: 140, height: 170)

// MARK: - 1) 패널 설정 못 박기

@MainActor
@Test
func todoBoardPanelCanBecomeKeyAndIsExcludedFromScreenSharing() {
    let panel = CheckTodoBoardController.makePanel()

    // ★ 키를 받을 수 있어야 한다. borderless + nonactivatingPanel 은 기본 구현이 키를 거부하고,
    //   그 상태에서는 보드가 보여도 글자가 한 자도 안 들어간다.
    #expect(panel.canBecomeKey == true)
    // ★ 화면공유·녹화 제외. 투두 본문은 업무 정보라 이 값이 프라이버시 방어선 그 자체다.
    #expect(panel.sharingType == .none)

    // 키를 받되 앱을 활성화하지는 않는다(사용자가 쓰던 창이 비활성이 되면 안 된다).
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.styleMask.contains(.borderless))

    #expect(panel.level == .floating)
    // 캐릭터 패널과 반대 — 이 창은 클릭을 받아야 체크/수정/삭제가 된다.
    #expect(panel.ignoresMouseEvents == false)
    // 반투명 보드가 뒤 창과 뒤섞이지 않게 그림자를 세운다(캐릭터 패널은 false).
    #expect(panel.hasShadow == true)

    #expect(panel.isOpaque == false)
    #expect(panel.backgroundColor == NSColor.clear)
    // NSPanel 기본값(true)을 반드시 뒤집어야 한다 — 안 그러면 남의 앱이 활성인 동안 보드가 저절로 숨는다.
    #expect(panel.hidesOnDeactivate == false)
    #expect(panel.isFloatingPanel == true)
    // 위치는 앵커 계산이 소유한다(사용자가 끌어 옮기면 캐릭터와 어긋난 채 남는다).
    #expect(panel.isMovable == false)

    let behavior = panel.collectionBehavior
    #expect(behavior.contains(.canJoinAllSpaces))
    #expect(behavior.contains(.fullScreenAuxiliary))
    #expect(behavior.contains(.stationary))
    #expect(behavior.contains(.ignoresCycle))

    #expect(panel.frame.size == TodoBoardAnchor.boardSize)
    #expect(TodoBoardAnchor.boardSize == NSSize(width: 300, height: 400))
    #expect(TodoBoardAnchor.gap == 10)
}

/// 위 보장들이 **실제로 뜨는 창**에도 걸려 있는지(컨트롤러가 다른 경로로 패널을 만들지 않는지) 확인한다.
@MainActor
@Test
func todoBoardControllerPanelCarriesTheSameGuarantees() {
    let controller = CheckTodoBoardController(store: makeTodoBoardStore())
    let panel = controller.panel

    #expect(panel.canBecomeKey == true)
    #expect(panel.sharingType == .none)
    #expect(panel.ignoresMouseEvents == false)
    #expect(panel.level == .floating)
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    // 콘텐츠(NSHostingView)가 실제로 얹혀 있어야 보드가 그려진다.
    #expect(panel.contentView != nil)
}

// MARK: - 2) 배치(순수 함수) 4케이스

@Test
func todoBoardAnchorSitsLeftOfCharacterAndTopAligned() {
    // 화면이 넉넉하면 언제나 캐릭터 왼쪽 · 상단 정렬이다.
    let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    let anchor = NSRect(x: 1_200, y: 600, width: 140, height: 170)
    let frame = TodoBoardAnchor.frame(anchor: anchor, in: visible)

    #expect(frame.size == TodoBoardAnchor.boardSize)
    #expect(frame.maxX == anchor.minX - TodoBoardAnchor.gap)   // 1190
    #expect(frame.minX == 890)
    #expect(frame.maxY == anchor.maxY)                          // 상단 정렬(770)
    #expect(frame.minY == 370)
}

@Test
func todoBoardAnchorFlipsToRightWhenLeftSideIsOffScreen() {
    // 캐릭터를 화면 왼쪽 끝으로 끌어다 둔 경우: 왼쪽이 화면 밖 → 오른쪽으로 뒤집는다.
    let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    let anchor = NSRect(x: 20, y: 600, width: 140, height: 170)
    let frame = TodoBoardAnchor.frame(anchor: anchor, in: visible)

    #expect(frame.minX == anchor.maxX + TodoBoardAnchor.gap)    // 170
    #expect(frame.maxX == 470)
    #expect(frame.maxY == anchor.maxY)                          // 세로 규칙은 그대로
    #expect(frame.minX >= visible.minX)
    #expect(frame.maxX <= visible.maxX)
}

@Test
func todoBoardAnchorClampsInsteadOfFlippingWhenNeitherSideFits() {
    // 폭 400 짜리 좁은 화면 한복판의 캐릭터: 왼쪽도 오른쪽도 300 폭을 못 담는다.
    // 이때는 뒤집지 않고 화면 안으로 당긴다 — 보드가 잘려 글자를 못 읽느니 캐릭터를 가리는 게 낫다.
    let visible = NSRect(x: 0, y: 0, width: 400, height: 900)
    let anchor = NSRect(x: 150, y: 600, width: 60, height: 170)
    let frame = TodoBoardAnchor.frame(anchor: anchor, in: visible)

    #expect(frame.minX == visible.minX)                          // 0 으로 클램프
    #expect(frame.maxX == 300)
    #expect(frame.size == TodoBoardAnchor.boardSize)             // 크기는 줄이지 않는다
    // 뒤집기가 아니다(뒤집었다면 minX 는 anchor.maxX + gap = 220 이었을 것).
    #expect(frame.minX != anchor.maxX + TodoBoardAnchor.gap)
    // 그리고 실제로 캐릭터를 덮는다 — 의도된 맞바꿈이다.
    #expect(frame.intersects(anchor))
}

@Test
func todoBoardAnchorClampsVerticallyWithoutFlippingUpward() {
    // 원점이 음수인 보조 모니터 + 캐릭터가 화면 아래쪽: 상단 정렬대로면 보드가 화면 아래로 삐져나간다.
    let visible = NSRect(x: -1_600, y: 200, width: 1_440, height: 900)
    let anchor = NSRect(x: -400, y: 250, width: 140, height: 170)   // maxY = 420
    let frame = TodoBoardAnchor.frame(anchor: anchor, in: visible)

    #expect(frame.minY == visible.minY)                           // 200 으로 클램프
    #expect(frame.maxY == 600)
    // 위로 뒤집지 않는다(뒤집었다면 minY 는 anchor.maxY + gap = 430 이었을 것).
    #expect(frame.minY != anchor.maxY + TodoBoardAnchor.gap)
    // 가로는 평소대로 왼쪽(화면 원점이 음수여도 visible.minX 기준으로 판정한다).
    #expect(frame.maxX == anchor.minX - TodoBoardAnchor.gap)      // -410
    #expect(frame.minX >= visible.minX)
}

// MARK: - 3) 열기/닫기 멱등 · isBoardOpen 전이

@MainActor
@Test
func todoBoardOpenCloseAreIdempotentAndTrackIsBoardOpen() {
    let controller = CheckTodoBoardController(store: makeTodoBoardStore())

    // 시작은 닫힘. 패널도 아직 만들지 않는다 — 근무 내내 한 번도 안 열 수 있는 창이다.
    #expect(controller.isBoardOpen == false)
    #expect(controller.hasPanel == false)

    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.isBoardOpen == true)
    #expect(controller.hasPanel == true)
    #expect(
        controller.panel.frame
            == TodoBoardAnchor.frame(anchor: todoBoardTestAnchor, in: todoBoardTestVisibleFrame)
    )

    // 멱등: 열린 채로 또 열어도 상태가 뒤집히지 않는다(위치만 다시 잡는다).
    let moved = NSRect(x: 600, y: 500, width: 140, height: 170)
    controller.open(anchor: moved, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.isBoardOpen == true)
    #expect(
        controller.panel.frame == TodoBoardAnchor.frame(anchor: moved, in: todoBoardTestVisibleFrame)
    )

    controller.close()
    #expect(controller.isBoardOpen == false)
    #expect(controller.panel.isVisible == false)

    // 멱등: 닫힌 채로 또 닫아도 아무 일도 없다.
    controller.close()
    #expect(controller.isBoardOpen == false)

    // 토글은 같은 판정을 뒤집기만 한다.
    controller.toggle(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.isBoardOpen == true)
    controller.toggle(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.isBoardOpen == false)
}

// MARK: - 4) 닫아도 패널·입력 상태를 파괴하지 않는다

@MainActor
@Test
func todoBoardKeepsPanelAndDraftAcrossClose() {
    let controller = CheckTodoBoardController(store: makeTodoBoardStore())
    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    let panel = controller.panel

    controller.setDraft("적다 만 문장")
    controller.toggleOldSection()
    #expect(controller.isOldSectionExpanded == true)

    controller.close()
    // 패널은 살아 있다(NSHostingView 재생성 비용·포커스 튐 회피).
    #expect(controller.hasPanel == true)

    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    // 같은 창 · 같은 초안 — 울트라로 잠깐 내렸다 돌아와도 적던 글이 남아 있어야 한다.
    #expect(controller.panel === panel)
    #expect(controller.draft == "적다 만 문장")
    #expect(controller.isOldSectionExpanded == true)
}

// MARK: - 5) 닫힌 동안의 재배치는 창을 만들지도, 띄우지도 않는다

@MainActor
@Test
func todoBoardRepositionIsNoOpWhileClosed() {
    let controller = CheckTodoBoardController(store: makeTodoBoardStore())

    // 캐릭터를 드래그해도 보드가 닫혀 있으면 아무 일도 없어야 한다(여기서 패널을 만들어 버리면
    // 지연 생성이 무의미해지고, 최악에는 닫아 둔 보드가 화면에 뜬다).
    controller.reposition(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.hasPanel == false)
    #expect(controller.isBoardOpen == false)

    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    let moved = NSRect(x: 500, y: 300, width: 140, height: 170)
    controller.reposition(anchor: moved, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(
        controller.panel.frame == TodoBoardAnchor.frame(anchor: moved, in: todoBoardTestVisibleFrame)
    )
    #expect(controller.isBoardOpen == true)   // 재배치는 표시 상태를 건드리지 않는다
}

// MARK: - 6) 삭제 유예 5초: 그 자리에 남았다가, 되돌리면 그대로

@MainActor
@Test
func todoBoardDeleteKeepsRowUntilUndoWindowClosesAndUndoRestoresIt() throws {
    let store = makeTodoBoardStore()
    let controller = CheckTodoBoardController(store: store)
    let item = try #require(store.add("되돌릴 수 있어야 한다"))

    controller.requestDelete(item.id)
    // 아직 지우지 않는다 — 지워 버리면 '삭제됨 [되돌리기]' 행이 설 자리(목록)가 사라진다.
    #expect(controller.pendingDeleteID == item.id)
    #expect(todoBoardVisibleIDs(store).contains(item.id))

    controller.undoDelete(item.id)
    #expect(controller.pendingDeleteID == nil)
    #expect(todoBoardVisibleIDs(store).contains(item.id))   // 되돌리면 아무 일도 없었던 것과 같다
}

// MARK: - 7) 보드를 닫으면 대기 중인 삭제는 즉시 확정된다

@MainActor
@Test
func todoBoardCloseConfirmsPendingDeleteImmediately() throws {
    let store = makeTodoBoardStore()
    let controller = CheckTodoBoardController(store: store)
    let item = try #require(store.add("닫으면 확정된다"))

    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    controller.requestDelete(item.id)
    #expect(controller.pendingDeleteID == item.id)

    controller.close()
    // 보이지 않는 곳에서 5초를 세는 것은 사용자가 누를 수 없는 유령 약속이다 — 닫는 순간 확정한다.
    #expect(controller.pendingDeleteID == nil)
    #expect(todoBoardVisibleIDs(store).contains(item.id) == false)

    // 다시 열어도 유령 '삭제됨' 행이 남지 않는다.
    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.pendingDeleteID == nil)
}

// MARK: - 8) 두 번째 삭제는 첫 번째를 확정하고 들어온다(대기는 언제나 한 줄)

@MainActor
@Test
func todoBoardSecondDeleteConfirmsTheFirstPendingOne() throws {
    let store = makeTodoBoardStore()
    let controller = CheckTodoBoardController(store: store)
    let first = try #require(store.add("첫 번째"))
    let second = try #require(store.add("두 번째"))

    controller.requestDelete(first.id)
    controller.requestDelete(second.id)

    // 되돌리기 버튼은 한 개뿐이고 타이머도 한 개다 — 두 줄이 동시에 '삭제됨'으로 서면 안 된다.
    #expect(controller.pendingDeleteID == second.id)
    #expect(todoBoardVisibleIDs(store).contains(first.id) == false)
    #expect(todoBoardVisibleIDs(store).contains(second.id))
}

// MARK: - 9) 유예 타이머가 **스스로** 깨어나 확정한다

@MainActor
@Test
func todoBoardUndoTimerConfirmsDeleteWithNoOnePushingIt() async throws {
    let store = makeTodoBoardStore()
    // 5초를 실제로 기다리면 아무도 안 돌리는 테스트가 된다 — 유예만 짧게 주입한다.
    let controller = CheckTodoBoardController(store: store, undoSeconds: 0.05)
    let item = try #require(store.add("가만히 두면 사라진다"))

    controller.requestDelete(item.id)
    #expect(controller.pendingDeleteID == item.id)

    var confirmed = false
    for _ in 0..<200 {
        if controller.pendingDeleteID == nil {
            confirmed = true
            break
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(confirmed)
    #expect(todoBoardVisibleIDs(store).contains(item.id) == false)
}

// MARK: - 10) 100자 초과 입력은 자르지 않고 막는다

@MainActor
@Test
func todoBoardBlocksOverlongDraftInsteadOfTruncating() {
    let controller = CheckTodoBoardController(store: makeTodoBoardStore())
    let full = String(repeating: "가", count: TodoRules.maxTitleLength)

    controller.setDraft(full)
    #expect(controller.draft.count == TodoRules.maxTitleLength)

    // 한 자 더: 거부된다(잘린 채 저장되지도, 마지막 글자가 소리 없이 사라지지도 않는다).
    controller.setDraft(full + "나")
    #expect(controller.draft == full)

    // 붙여넣기처럼 통째로 넘치는 입력도 통째로 거부한다.
    controller.setDraft(String(repeating: "다", count: TodoRules.maxTitleLength + 50))
    #expect(controller.draft == full)

    // 지우는 방향은 언제나 열려 있다(막힌 채 갇히지 않는다).
    controller.setDraft(String(full.dropLast()))
    #expect(controller.draft.count == TodoRules.maxTitleLength - 1)
}

// MARK: - 11) 입력 상태의 주인은 컨트롤러다(추가/수정 흐름)

@MainActor
@Test
func todoBoardOwnsDraftAndEditingState() throws {
    let store = makeTodoBoardStore()
    let controller = CheckTodoBoardController(store: store)

    controller.setDraft("우유 사기")
    controller.submitDraft()
    #expect(controller.draft == "")                       // 성공했을 때만 비운다
    let item = try #require(store.items.first { $0.title == "우유 사기" })
    #expect(todoBoardVisibleIDs(store).contains(item.id))

    // 공백만 친 입력은 store 가 거절한다 — 그때는 초안을 지우지 않는다(친 것이 이유 없이 증발하면 안 된다).
    controller.setDraft("   ")
    controller.submitDraft()
    #expect(controller.draft == "   ")

    controller.setDraft("")
    controller.beginEdit(item.id)
    #expect(controller.editingID == item.id)
    controller.cancelEdit()
    #expect(controller.editingID == nil)

    // 커밋하면 수정 모드는 반드시 닫힌다(열린 채 남으면 사용자는 저장이 안 된 줄 안다).
    controller.beginEdit(item.id)
    controller.commitEdit(item.id, to: "우유랑 빵 사기")
    #expect(controller.editingID == nil)
    #expect(store.items.first { $0.id == item.id }?.title == "우유랑 빵 사기")
}
