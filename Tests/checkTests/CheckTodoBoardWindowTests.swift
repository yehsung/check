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

/// 레이어 트리에 `CABackdropLayer`(뒤 화면을 표본 삼는 레이어)가 있는지. **behind-window 블러가
/// 실제로 살아 있다는 유일한 런타임 증거**다 — `state` 를 `.inactive` 로 두면 AppKit 이 이 레이어를 빼고
/// 알파 1.0 단색 레이어로 갈아치운다(실측). 클래스가 비공개라 이름으로 찾는다.
private func todoBoardHasBackdropLayer(_ layer: CALayer) -> Bool {
    if String(describing: type(of: layer)).contains("Backdrop") { return true }
    for sub in layer.sublayers ?? [] where todoBoardHasBackdropLayer(sub) { return true }
    return false
}

/// 뷰 트리에서 '보드를 통째로 덮는 불투명 배경'을 하나라도 찾는다. 블러 위에 이런 뷰가 한 장이라도 있으면
/// 창은 반투명이어도 사용자 눈에는 불투명 판이다(신고된 그림 그대로).
@MainActor
private func todoBoardOpaqueCoveringViews(_ view: NSView, boardBounds: NSRect) -> [String] {
    var found: [String] = []
    for sub in view.subviews {
        let inBoard = sub.convert(sub.bounds, to: nil)
        let covers = inBoard.width >= boardBounds.width - 1 && inBoard.height >= boardBounds.height - 1
        if covers {
            if sub.isOpaque { found.append("\(type(of: sub)).isOpaque") }
            if let bg = sub.layer?.backgroundColor, bg.alpha >= 1 {
                found.append("\(type(of: sub)).layer.bg alpha=\(bg.alpha)")
            }
        }
        found.append(contentsOf: todoBoardOpaqueCoveringViews(sub, boardBounds: boardBounds))
    }
    return found
}

/// 창을 실제로 띄우고 합성이 한 번 돌게 런루프를 돌린다. 레이어 트리는 창이 화면에 올라간 뒤에야 세워진다.
@MainActor
private func todoBoardPump(_ seconds: Double = 0.35) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

/// 실사용 설정(UserDefaults.standard)을 건드리지 않는 격리 투명도 스토어.
/// `opacity` 를 주면 "앱을 껐다 켰더니 저장돼 있던 값"을 재현한다.
@MainActor
private func makeTodoBoardAppearanceStore(opacity: Double? = nil) -> TodoBoardAppearanceStore {
    let suiteName = "check-todo-board-window-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    if let opacity { defaults.set(opacity, forKey: TodoBoardAppearanceStore.defaultsKey) }
    return TodoBoardAppearanceStore(defaults: defaults)
}

/// 보드 창의 세 겹을 한 번에 꺼낸다. **꺼내는 경로 자체가 계약**이다 —
/// contentView 는 투명 컨테이너, 그 아래 블러와 호스팅 뷰가 이 순서(=아래에서 위)로 형제로 선다.
@MainActor
private func todoBoardLayers(
    _ panel: TodoBoardPanel
) throws -> (container: NSView, blur: NSVisualEffectView, hosting: NSView) {
    let container = try #require(panel.contentView)
    // 컨테이너가 블러이면 옛 배치다(그 배치에서는 블러 알파가 글자까지 먹는다).
    #expect(container as? NSVisualEffectView == nil, "contentView 가 블러다 — 형제 배치가 무너졌다")
    #expect(container.subviews.count == 2, "컨테이너 자식이 \(container.subviews.count)개다(블러+호스팅이어야 한다)")
    let blur = try #require(container.subviews.first as? NSVisualEffectView)
    let hosting = try #require(container.subviews.last)
    #expect(String(describing: type(of: hosting)).contains("NSHostingView"))
    return (container, blur, hosting)
}

/// `view` 가 화면에 실제로 나오는 진하기 — 루트까지 거슬러 올라가며 알파를 전부 곱한다.
/// 알파를 어느 조상에 걸었든 여기서 드러나므로, "글자는 언제나 100%"를 **한 숫자로** 못 박을 수 있다.
@MainActor
private func todoBoardEffectiveAlpha(_ view: NSView, upTo root: NSView) -> Double {
    var alpha = Double(view.alphaValue)
    var current: NSView? = view.superview
    while let node = current {
        alpha *= Double(node.alphaValue)
        if node === root { break }
        current = node.superview
    }
    return alpha
}

/// 호스팅 뷰가 자기 백킹스토어에 그린 픽셀의 알파(화면 녹화 권한 없이 되는 유일한 실측).
@MainActor
private func todoBoardPixelAlpha(_ view: NSView, x: Int, y: Int) throws -> Double {
    view.layoutSubtreeIfNeeded()
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    let color = try #require(rep.colorAt(x: x, y: y))
    return Double((color.usingColorSpace(.sRGB) ?? color).alphaComponent)
}

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

    // ★ 닫은 **뒤**로도 따라오지 않는다. 여기서 패널은 이미 만들어져 있으므로 `let panelStorage` 만으로는
    //   못 막는다 — `isBoardOpen` 가드가 실제로 일하는 지점이 여기다. 근무 중에는 캐릭터를 계속 끌고 다니고
    //   그때마다 이 경로가 60Hz 로 불리므로, 닫힌 보드가 조용히 따라다니면 다음 열기 위치가 앵커 계산이
    //   아니라 '마지막으로 따라간 자리'에서 정해진다.
    controller.close()
    let applied = controller.repositionAppliedCount
    let frameWhenClosed = controller.panel.frame
    for x in stride(from: 100.0, through: 1_100.0, by: 100.0) {
        controller.reposition(
            anchor: NSRect(x: x, y: 200, width: 140, height: 170),
            screenVisibleFrame: todoBoardTestVisibleFrame
        )
    }
    #expect(controller.repositionAppliedCount == applied, "닫힌 보드가 캐릭터를 따라다녔다")
    #expect(controller.panel.frame == frameWhenClosed)
    #expect(controller.panel.isVisible == false)
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

// MARK: - 12) 반투명 체인 — 블러와 글자는 형제다

/// 신고 두 개가 이 배치 하나에 걸려 있다.
/// (1) "반투명 하지가 않아. 뒤를 완전 가려버려" — 블러를 SwiftUI `.background` 로 넣어 호스팅 뷰 레이어에
///     파묻었던 옛 버그. 블러는 **창의 콘텐츠 계층에 직접** 서야 한다.
/// (2) "투명하게 했더니 글자가 안 보인다" — 호스팅 뷰가 블러의 **자식**이면 `effect.alphaValue` 가
///     글자·체크박스·버튼까지 그대로 먹는다. 그래서 둘은 투명 컨테이너 아래 **형제**여야 한다.
@MainActor
@Test
func todoBoardBlurAndHostingAreSiblingsUnderTransparentContainer() throws {
    let controller = CheckTodoBoardController(
        store: makeTodoBoardStore(), appearance: makeTodoBoardAppearanceStore()
    )
    let panel = controller.panel
    let (container, blur, hosting) = try todoBoardLayers(panel)

    #expect(blur.blendingMode == .behindWindow)   // .withinWindow 면 '뒤'가 아니라 '자기 창 안'을 흐린다
    #expect(blur.state == .active)                // .followsWindowActiveState 면 남의 앱 클릭 시 회색 판
    #expect(blur.material == .hudWindow)

    // 호스팅 뷰는 블러의 자식이 아니다(자식이면 알파를 같이 먹는다).
    #expect(hosting.superview === container)
    #expect(blur.superview === container)
    #expect(hosting.isDescendant(of: blur) == false, "호스팅 뷰가 블러 아래 있다 — 글자까지 흐려진다")
    // 순서 = z-순서. 블러가 뒤, 글자가 앞이어야 한다.
    #expect(container.subviews.firstIndex(of: blur) == 0)
    #expect(container.subviews.firstIndex(of: hosting) == 1)

    // 컨테이너는 **아무것도 그리지 않는 투명 판**이다. 여기에 배경이 깔리면 블러가 무슨 짓을 해도 회색 판이다.
    #expect(container.isOpaque == false)
    if let bg = container.layer?.backgroundColor { #expect(bg.alpha == 0) }
    #expect(hosting.isOpaque == false)
    if let bg = hosting.layer?.backgroundColor { #expect(bg.alpha < 1) }

    // 창 자체의 투명도 문도 열려 있어야 한다(하나라도 닫히면 아래 블러가 화면에 못 나온다).
    #expect(panel.isOpaque == false)
    #expect(panel.backgroundColor == NSColor.clear)
    // 창 전체를 흐리는 게 아니다 — 알파는 콘텐츠(블러 뷰)가 정한다. 창 알파는 오직
    // CheckPanelVisibility 만 정하고(테스트 0 / 프로덕션 1), 그 값이 여기 그대로 서 있어야 한다.
    #expect(panel.alphaValue == CheckPanelVisibility.panelAlpha)

    // 블러 위 어디에도 보드를 통째로 덮는 불투명 배경이 없어야 한다.
    let culprits = todoBoardOpaqueCoveringViews(container, boardBounds: container.bounds)
    #expect(culprits.isEmpty, "블러를 덮는 불투명 뷰: \(culprits)")
}

/// 형제로 갈라 놓고도 **뒤를 실제로 표본 삼는지**를 런타임 레이어 트리로 확인한다.
/// AppKit 은 `state == .active` 인 behind-window 재질에만 `CABackdropLayer` 를 세우고, `.inactive` 면
/// 그 자리를 알파 1.0 단색 레이어로 바꾼다(실측) — 즉 이 단언이 신고된 "완전히 가림"을 직접 잡는다.
/// (형제 배치로 옮기기 전 두 배치를 나란히 세워 덤프한 결과: 둘 다 backdrop 이 섰고, 형제 배치에서만
///  블러 백킹 레이어에 opacity 가 걸리고 호스팅 백킹 레이어는 1.0 그대로였다.)
@MainActor
@Test
func todoBoardBackdropLayerExistsOnScreen() throws {
    let controller = CheckTodoBoardController(
        store: makeTodoBoardStore(), appearance: makeTodoBoardAppearanceStore()
    )
    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    defer { controller.close() }
    todoBoardPump()

    let (_, blur, _) = try todoBoardLayers(controller.panel)
    let layer = try #require(blur.layer)
    #expect(todoBoardHasBackdropLayer(layer), "뒤 화면을 표본 삼는 CABackdropLayer 가 없다 = 블러가 죽었다")

    // 모서리는 **블러 레이어가** 깎는다. 재질은 자기 bounds 를 꽉 채운 사각형이라 레이어가 자르지 않으면
    // 네 귀퉁이가 각진 채 삐져나온다(호스팅 뷰 쪽은 SwiftUI 가 같은 반지름·같은 곡선으로 이미 자른다).
    // 곡선이 갈리면 두 클립의 경계가 몇 px 어긋나 모서리에 실선이 남는다.
    #expect(layer.cornerRadius == CheckTodoBoardView.cornerRadius)
    #expect(layer.cornerCurve == .continuous)
    #expect(layer.masksToBounds)
}

/// 보드가 **자기 백킹스토어에 그리는 픽셀**이 불투명하지 않은지 직접 잰다(화면 녹화 권한 없이 되는 유일한 실측).
/// 블러는 윈도우 서버가 창 뒤에 합성하므로, 우리 콘텐츠가 알파 1 로 덮어 버리면 아무리 블러가 살아 있어도
/// 사용자에게는 불투명 판이다.
///
/// 모서리 픽셀도 같이 잰다 — 컨테이너에 masksToBounds 를 걸지 **않기로** 한 근거가 여기다.
/// 호스팅 뷰는 SwiftUI 가 스스로 자르므로 컨테이너가 한 번 더 자를 필요가 없다.
@MainActor
@Test
func todoBoardContentPixelsAreNotOpaqueAndCornersAreClipped() throws {
    let controller = CheckTodoBoardController(
        store: makeTodoBoardStore(), appearance: makeTodoBoardAppearanceStore()
    )
    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    defer { controller.close() }
    todoBoardPump()

    let (_, _, hosting) = try todoBoardLayers(controller.panel)
    let width = Int(hosting.bounds.width)
    let height = Int(hosting.bounds.height)
    let center = try todoBoardPixelAlpha(hosting, x: width / 2, y: height / 2)
    // 뭔가는 그려야 한다(0 이면 보드가 아예 안 그려진 것 — 검증이 성립하지 않는다).
    #expect(center > 0.05, "보드가 아무것도 그리지 않았다(alpha=\(center))")
    // 그리고 그것이 불투명해선 안 된다.
    #expect(center < 0.95, "보드 콘텐츠가 불투명하다(alpha=\(center)) — 뒤가 비칠 수 없다")

    // 좌상단 꼭짓점 픽셀은 라운드 밖이라 비어 있어야 한다.
    let corner = try todoBoardPixelAlpha(hosting, x: 0, y: 0)
    #expect(corner < center / 2, "모서리가 안 잘렸다(corner=\(corner), center=\(center))")
}

/// 보드는 어두운 테마 전용으로 그려진다(흰 글자 + CheckTheme 어두운 틴트). 재질은 시스템 외관을 따라가므로
/// 밝은 테마에서는 같은 hudWindow 가 흰 틴트로 바뀌어 대비가 무너진다(실측: 0.965@0.48 + 0.96).
/// 사용자 외관과 무관하게 창을 어둡게 고정한다.
@MainActor
@Test
func todoBoardPanelPinsDarkAppearance() {
    let panel = CheckTodoBoardController.makePanel()
    #expect(panel.appearance?.name == .darkAqua)
}

// MARK: - 13) 재배치는 창을 띄우지도, 포커스를 훔치지도 않는다

/// 드래그 중 60Hz 로 불리는 경로다. 여기서 orderFront/makeKey 계열이 한 번이라도 돌면 사용자가 쓰던 앱에서
/// 포커스가 튀고 우리 창이 앞으로 튀어나온다.
@MainActor
@Test
func todoBoardRepositionNeverShowsOrFocusesThePanel() {
    let controller = CheckTodoBoardController(store: makeTodoBoardStore())
    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)

    // 창을 화면에서 내린 채로 둔다(표시 의도는 살아 있다 — 스페이스 전환·미션컨트롤 등으로 실제로 생긴다).
    // 이 상태에서 재배치가 창을 도로 띄우면 그건 orderFront 계열을 부른 것이다.
    controller.panel.orderOut(nil)
    #expect(controller.panel.isVisible == false)

    for x in stride(from: 200.0, through: 900.0, by: 50.0) {
        controller.reposition(
            anchor: NSRect(x: x, y: 400, width: 140, height: 170),
            screenVisibleFrame: todoBoardTestVisibleFrame
        )
    }

    #expect(controller.panel.isVisible == false, "재배치가 창을 띄웠다 — orderFront 계열이 들어갔다")
    #expect(controller.panel.isKeyWindow == false, "재배치가 키를 가져갔다 — makeKey 계열이 들어갔다")
    // 그래도 위치는 따라가 있어야 한다(마지막 앵커 기준).
    let last = NSRect(x: 900, y: 400, width: 140, height: 170)
    #expect(controller.panel.frame == TodoBoardAnchor.frame(anchor: last, in: todoBoardTestVisibleFrame))
    controller.close()
}

/// 같은 자리로 오는 호출은 창을 건드리지 않는다. 캐릭터가 화면 가장자리에서 흔들릴 때 보드는 클램프에 걸려
/// 같은 좌표에 머무는데, 그 구간에서 매 프레임 창을 다시 옮기면 값만 다시 쓰는 낭비다.
@MainActor
@Test
func todoBoardRepositionSkipsRedundantMoves() {
    let controller = CheckTodoBoardController(store: makeTodoBoardStore())
    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.repositionAppliedCount == 0)

    // open 이 이미 이 자리에 놓았다 — 같은 앵커로 60프레임을 보내도 창은 한 번도 안 움직여야 한다.
    for _ in 0..<60 {
        controller.reposition(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    }
    #expect(controller.repositionAppliedCount == 0)

    // 실제로 움직이면 그때 한 번.
    let moved = NSRect(x: 700, y: 400, width: 140, height: 170)
    controller.reposition(anchor: moved, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.repositionAppliedCount == 1)
    for _ in 0..<60 {
        controller.reposition(anchor: moved, screenVisibleFrame: todoBoardTestVisibleFrame)
    }
    #expect(controller.repositionAppliedCount == 1)

    // 화면 왼쪽 끝으로 계속 밀어붙이면 보드는 클램프에 걸려 같은 자리에 선다 → 그 뒤로는 다시 0회.
    let edge = NSRect(x: 0, y: 400, width: 140, height: 170)
    controller.reposition(anchor: edge, screenVisibleFrame: todoBoardTestVisibleFrame)
    let afterEdge = controller.repositionAppliedCount
    controller.reposition(anchor: edge, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.repositionAppliedCount == afterEdge)

    controller.close()
}

/// 크기는 언제나 boardSize 고정이라 재배치는 원점만 옮긴다. 크기가 바뀌면 그건 계약 위반이다
/// (창이 자라면 안쪽 스크롤이 존재 이유를 잃는다).
@MainActor
@Test
func todoBoardRepositionNeverChangesSize() {
    let controller = CheckTodoBoardController(store: makeTodoBoardStore())
    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    for x in stride(from: -100.0, through: 1_400.0, by: 37.0) {
        controller.reposition(
            anchor: NSRect(x: x, y: 400, width: 140, height: 170),
            screenVisibleFrame: todoBoardTestVisibleFrame
        )
        #expect(controller.panel.frame.size == TodoBoardAnchor.boardSize)
    }
    controller.close()
}

// MARK: - 14) 가장자리 뒤집힘 — 드래그로 좌→우를 훑는다

/// 캐릭터를 화면 왼쪽 끝에서 오른쪽 끝까지 1pt 씩 끌고 가며, 보드가 **정확히 한 번** 뒤집히고
/// 그 어느 지점에서도 화면 밖으로 나가지 않는지 훑는다.
@Test
func todoBoardFlipsExactlyOnceAcrossAFullDragSweep() {
    let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    let width: CGFloat = 140
    var sides: [Bool] = []          // true = 캐릭터 오른쪽에 섰다
    var transitions = 0

    for step in 0...1_300 {
        let anchor = NSRect(x: CGFloat(step), y: 600, width: width, height: 170)
        let frame = TodoBoardAnchor.frame(anchor: anchor, in: visible)

        // 어느 지점에서도 화면 밖으로 나가지 않는다(상하 포함).
        #expect(frame.minX >= visible.minX)
        #expect(frame.maxX <= visible.maxX)
        #expect(frame.minY >= visible.minY)
        #expect(frame.maxY <= visible.maxY)
        #expect(frame.size == TodoBoardAnchor.boardSize)

        let isRight = frame.minX >= anchor.maxX
        if let previous = sides.last, previous != isRight { transitions += 1 }
        sides.append(isRight)
    }

    // 왼쪽 끝에서는 오른쪽에, 오른쪽으로 갈수록 왼쪽에. 그 사이 전환은 딱 한 번이어야 한다 —
    // 두 번 이상이면 드래그 중 보드가 좌우로 오락가락한다.
    #expect(sides.first == true)
    #expect(sides.last == false)
    #expect(transitions == 1, "드래그 한 번에 보드가 \(transitions)회 뒤집혔다")
}

/// 뒤집힘 경계는 1pt 단위로 날카로워야 한다. 왼쪽 자리가 화면 안에 **꼭 들어맞는** 순간까지는 왼쪽,
/// 1pt 라도 모자라면 오른쪽이다.
@Test
func todoBoardFlipBoundaryIsExact() {
    let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    let size = TodoBoardAnchor.boardSize
    let gap = TodoBoardAnchor.gap
    // 왼쪽이 딱 맞는 최소 위치: anchor.minX == visible.minX + gap + width
    let exact = visible.minX + gap + size.width      // 310

    let fits = TodoBoardAnchor.frame(
        anchor: NSRect(x: exact, y: 600, width: 140, height: 170), in: visible
    )
    #expect(fits.minX == visible.minX)               // 왼쪽에 딱 붙어 선다
    #expect(fits.maxX == exact - gap)

    let doesNotFit = TodoBoardAnchor.frame(
        anchor: NSRect(x: exact - 1, y: 600, width: 140, height: 170), in: visible
    )
    #expect(doesNotFit.minX == (exact - 1) + 140 + gap)   // 1pt 모자라면 곧바로 오른쪽으로

    // 반대편 경계: 뒤집은 자리가 **온전히** 들어갈 때만 뒤집는다.
    // 폭 705 짜리 좁은 화면(= 300 + 10 + 90 + 10 + 300 보다 5pt 모자람)이라 캐릭터를 조금만 옮겨도
    // 양쪽 다 못 담는 구간이 생긴다 — 뒤집기와 클램프의 경계를 1pt 로 가른다.
    let narrow = NSRect(x: 0, y: 0, width: 705, height: 900)
    let justFlips = NSRect(x: 305, y: 600, width: 90, height: 170)   // 왼쪽 5pt 부족, 오른쪽은 딱 맞음
    let flipped = TodoBoardAnchor.frame(anchor: justFlips, in: narrow)
    #expect(flipped.minX == justFlips.maxX + gap)    // 405 — 딱 맞으니 뒤집는다
    #expect(flipped.maxX == narrow.maxX)             // 705 에 정확히 붙는다

    let cannotFlip = NSRect(x: 306, y: 600, width: 90, height: 170) // 오른쪽도 1pt 넘침
    let clamped = TodoBoardAnchor.frame(anchor: cannotFlip, in: narrow)
    #expect(clamped.minX == narrow.minX)             // 뒤집지 않고 왼쪽으로 클램프
    #expect(clamped.minX != cannotFlip.maxX + gap)   // 뒤집힌 게 아니다
    #expect(clamped.maxX <= narrow.maxX)
}

/// 음수 좌표 보조 모니터에서도 같은 규칙이 걸린다(왼쪽 끝 → 뒤집기, 오른쪽 끝 → 왼쪽 유지).
/// 화면 원점이 음수일 때 0 을 기준으로 판정하는 버그가 있으면 여기서 죽는다.
@Test
func todoBoardFlipsOnNegativeOriginSecondMonitor() {
    let visible = NSRect(x: -1_600, y: 200, width: 1_440, height: 900)   // maxX = -160, maxY = 1100

    // 왼쪽 끝으로 끌고 간 캐릭터 → 오른쪽으로 뒤집힌다.
    let atLeft = NSRect(x: -1_590, y: 600, width: 140, height: 170)
    let flipped = TodoBoardAnchor.frame(anchor: atLeft, in: visible)
    #expect(flipped.minX == atLeft.maxX + TodoBoardAnchor.gap)    // -1440
    #expect(flipped.maxX <= visible.maxX)
    #expect(flipped.minX >= visible.minX)

    // 오른쪽 끝 → 평소대로 왼쪽.
    let atRight = NSRect(x: -300, y: 600, width: 140, height: 170)
    let left = TodoBoardAnchor.frame(anchor: atRight, in: visible)
    #expect(left.maxX == atRight.minX - TodoBoardAnchor.gap)      // -310
    #expect(left.minX >= visible.minX)
}

/// 캐릭터가 화면 위쪽(메뉴바 영역 등)으로 올라가 상단 정렬 자리가 화면 위로 삐져나가는 경우.
/// 위쪽 클램프가 없으면 보드 머리가 화면 밖으로 잘린다.
@Test
func todoBoardClampsBelowTopEdge() {
    let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    // 앵커가 화면 위로 걸쳐 있다 → 상단 정렬대로면 보드 maxY 가 950 이 되어 잘린다.
    let anchor = NSRect(x: 1_000, y: 880, width: 140, height: 170)     // maxY = 1050
    let frame = TodoBoardAnchor.frame(anchor: anchor, in: visible)

    #expect(frame.maxY == visible.maxY)     // 900 으로 당겨진다
    #expect(frame.minY == 500)
    #expect(frame.minY >= visible.minY)
}

/// 재배치를 통해 **실제 창**이 뒤집히는지(순수 함수만 맞고 창은 안 따라오는 일이 없게).
@MainActor
@Test
func todoBoardPanelActuallyFlipsWhenDraggedToTheEdge() {
    let visible = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    let controller = CheckTodoBoardController(store: makeTodoBoardStore())

    let right = NSRect(x: 1_200, y: 600, width: 140, height: 170)
    controller.open(anchor: right, screenVisibleFrame: visible)
    #expect(controller.panel.frame.maxX == right.minX - TodoBoardAnchor.gap)

    // 드래그로 왼쪽 끝까지 끌고 간다(중간 프레임도 전부 화면 안).
    for x in stride(from: 1_200.0, through: 0.0, by: -20.0) {
        let anchor = NSRect(x: x, y: 600, width: 140, height: 170)
        controller.reposition(anchor: anchor, screenVisibleFrame: visible)
        let f = controller.panel.frame
        #expect(f.minX >= visible.minX)
        #expect(f.maxX <= visible.maxX)
    }

    let left = NSRect(x: 0, y: 600, width: 140, height: 170)
    #expect(controller.panel.frame.minX == left.maxX + TodoBoardAnchor.gap)   // 뒤집혀 오른쪽에 섰다
    #expect(controller.panel.frame == TodoBoardAnchor.frame(anchor: left, in: visible))
    controller.close()
}


// MARK: - 15) 투명도 배선 — 흐려지는 건 배경뿐, 글자는 언제나 100%

/// **이 파일에서 가장 중요한 단언이다.** 사용자가 투명도를 끝까지 내려도 글자·체크박스·버튼은
/// 한 톨도 흐려지면 안 된다("투명하게 했더니 아무것도 안 보인다"가 이 기능을 죽이는 방식이다).
///
/// 알파를 어느 조상에 걸었는지를 이름이 아니라 **화면에 나오는 진하기**로 잰다 — 컨테이너에 걸든
/// 패널에 걸든 호스팅 뷰의 실효 알파가 1 아래로 내려가는 순간 여기서 죽는다.
@MainActor
@Test
func todoBoardOpacityDimsOnlyTheBlurNeverTheText() throws {
    let appearance = makeTodoBoardAppearanceStore()
    let controller = CheckTodoBoardController(store: makeTodoBoardStore(), appearance: appearance)
    let (container, blur, hosting) = try todoBoardLayers(controller.panel)

    // 가장 투명한 끝(블러가 완전히 걷히는 지점)까지 내려도…
    appearance.setOpacity(TodoBoardAppearance.minOpacity)
    #expect(appearance.appearance.blurAlpha == 0)
    #expect(Double(blur.alphaValue) == 0)

    // …글자는 100% 그대로다.
    #expect(todoBoardEffectiveAlpha(hosting, upTo: container) == 1.0, "글자가 흐려졌다")
    #expect(container.alphaValue == 1, "컨테이너에 알파가 걸렸다 — 글자까지 같이 흐려진다")
    #expect(hosting.alphaValue == 1)
    // 창 알파를 만지는 곳은 CheckPanelVisibility 한 곳뿐이다(테스트 실행이라 0, 프로덕션은 1).
    // 여기에 투명도 값(예: 0.55)이 새어 들어오면 그 순간 이 단언이 빨개진다 — "패널에 알파가 걸렸다 =
    // 창 전체가 유령이 된다" 회귀는 그대로 잡히고, 스위트가 사용자 화면을 덮지 않는 것도 함께 지킨다.
    #expect(controller.panel.alphaValue == CheckPanelVisibility.panelAlpha,
            "패널에 알파가 걸렸다 — 창 전체가 유령이 된다")
    #expect(CheckPanelVisibility.productionAlpha == 1)

    // 되돌리면 블러도 그대로 돌아온다(단방향으로 죽지 않는다).
    appearance.setOpacity(TodoBoardAppearance.maxOpacity)
    #expect(Double(blur.alphaValue) == 1)
    #expect(todoBoardEffectiveAlpha(hosting, upTo: container) == 1.0)
}

/// 중간 구간도 설정 모델이 계산한 값과 **정확히** 같아야 한다(창이 자기 나름의 곡선을 다시 만들면 안 된다).
@MainActor
@Test
func todoBoardBlurAlphaFollowsTheModelExactly() throws {
    let appearance = makeTodoBoardAppearanceStore()
    let controller = CheckTodoBoardController(store: makeTodoBoardStore(), appearance: appearance)
    let (_, blur, _) = try todoBoardLayers(controller.panel)

    for opacity in stride(from: TodoBoardAppearance.minOpacity, through: TodoBoardAppearance.maxOpacity, by: 0.05) {
        appearance.setOpacity(opacity)
        let expected = TodoBoardAppearance(opacity: opacity).blurAlpha
        #expect(abs(Double(blur.alphaValue) - expected) < 1e-6, "opacity=\(opacity)")
    }
}

/// 앱을 껐다 켠 뒤 **처음 여는 창**에도 저장값이 서 있어야 한다. 통지는 값이 바뀔 때만 오므로,
/// 패널을 만들 때 한 번 읽지 않으면 사용자가 슬라이더를 만지기 전까지 창만 기본값으로 남는다.
@MainActor
@Test
func todoBoardFirstPanelStartsFromTheStoredOpacity() throws {
    let stored = 0.30
    let appearance = makeTodoBoardAppearanceStore(opacity: stored)
    #expect(appearance.appearance.opacity == stored)   // 복원부터 됐는지 먼저 확인
    let controller = CheckTodoBoardController(store: makeTodoBoardStore(), appearance: appearance)

    let (_, blur, _) = try todoBoardLayers(controller.panel)
    let expected = TodoBoardAppearance(opacity: stored).blurAlpha
    #expect(expected < 1.0)                            // 기본값과 구별되는 값이어야 검증이 성립한다
    #expect(abs(Double(blur.alphaValue) - expected) < 1e-6, "첫 창이 저장값을 무시했다")
}

/// 보드를 한 번도 안 연 상태에서 설정을 만져도 **창이 생기면 안 된다**.
/// 여기서 `panel` 을 읽는 구현이면 설정 슬라이더를 미는 것만으로 열지도 않은 보드가 만들어진다
/// (`todoBoardRepositionIsNoOpWhileClosed` 와 같은 계약 — 지연 생성은 이 기능이 깨도 되는 게 아니다).
@MainActor
@Test
func todoBoardOpacityChangeWhileClosedDoesNotCreateThePanel() {
    let appearance = makeTodoBoardAppearanceStore()
    let controller = CheckTodoBoardController(store: makeTodoBoardStore(), appearance: appearance)
    #expect(controller.hasPanel == false)

    appearance.setOpacity(0.25)
    appearance.nudge(by: TodoBoardAppearance.step)
    #expect(controller.hasPanel == false, "설정 조작이 열지도 않은 보드를 만들었다")
    #expect(controller.isBoardOpen == false)
}

// MARK: - 16) ⌥ + 스크롤 — 조합 판정

/// ⌥ 없는 스크롤은 **반드시 그냥 흘러가야 한다**(목록 스크롤이 죽는다).
/// ⌘·⌃ 는 시스템/앱이 이미 쓰는 조합이라 비켜 준다. CapsLock 같은 나머지 플래그는 무시한다 —
/// `flags == .option` 로 못 박으면 CapsLock 켠 사용자에게만 기능이 통째로 죽는다.
@Test
func todoBoardOptionScrollGateAcceptsOnlyOption() {
    let gate = CheckTodoBoardController.adjustsOpacity

    #expect(gate(.option))
    #expect(gate([.option, .capsLock]))
    #expect(gate([.option, .function]))

    #expect(gate([]) == false)
    #expect(gate(.shift) == false)
    #expect(gate(.command) == false)
    #expect(gate([.option, .command]) == false)    // ⌘+스크롤은 앱마다 확대/축소다
    #expect(gate([.option, .control]) == false)    // ⌃+스크롤은 시스템 화면 확대다
    #expect(gate([.option, .shift]) == false)      // ⇧ 는 스크롤을 가로로 돌린다(deltaY 가 0으로 온다)
}

// MARK: - 17) ⌥ + 스크롤 — 누적 규칙(순수)

private func todoBoardTrackpad(_ deltaY: Double, inverted: Bool = true) -> TodoBoardScrollSample {
    TodoBoardScrollSample(deltaY: deltaY, isPrecise: true, isInverted: inverted, isMomentum: false)
}

private func todoBoardWheel(_ deltaY: Double, inverted: Bool = false) -> TodoBoardScrollSample {
    TodoBoardScrollSample(deltaY: deltaY, isPrecise: false, isInverted: inverted, isMomentum: false)
}

/// 트랙패드는 한 번 쓸어도 잘게 수십 번 온다. 그대로 곱하면 레일(15스텝)을 순식간에 왕복한다 —
/// 문턱을 넘을 때만 한 스텝이 나가야 "한 틱 = 한 스텝"으로 읽힌다.
@Test
func todoBoardScrollAccumulatesInsteadOfFiringEveryEvent() {
    var gesture = TodoBoardScrollOpacityGesture()
    let step = TodoBoardScrollOpacityGesture.stepDistance

    // 문턱의 1/4 씩 세 번 — 아직 한 칸도 안 나간다.
    for _ in 0..<3 {
        #expect(gesture.steps(for: todoBoardTrackpad(-step / 4)) == 0)
    }
    // 네 번째에 정확히 한 칸.
    #expect(gesture.steps(for: todoBoardTrackpad(-step / 4)) == 1)
    // 잔여는 0 이므로 다시 처음부터 모은다(한 번 넘겼다고 그 뒤가 헐거워지지 않는다).
    #expect(gesture.steps(for: todoBoardTrackpad(-step / 2)) == 0)
    #expect(gesture.steps(for: todoBoardTrackpad(-step / 2)) == 1)
}

/// 방향의 기준은 문서 방향(deltaY 부호)이 아니라 **손가락·휠의 물리적 위쪽**이다.
/// 자연스러운 스크롤은 장치별로 따로 켜지므로, 문서 방향을 쓰면 같은 맥에서 같은 손동작이
/// 트랙패드와 마우스에서 **반대로** 동작한다. 위로 밀면 진해진다(값 증가) — 슬라이더와 같은 은유.
@Test
func todoBoardScrollDirectionIsPhysicalNotDocument() {
    let step = TodoBoardScrollOpacityGesture.stepDistance

    // 자연스러운 스크롤 ON(트랙패드 기본): 손가락을 위로 = deltaY 음수 → 값 증가.
    var natural = TodoBoardScrollOpacityGesture()
    #expect(natural.steps(for: todoBoardTrackpad(-step, inverted: true)) == 1)
    natural.reset()
    #expect(natural.steps(for: todoBoardTrackpad(step, inverted: true)) == -1)

    // 자연스러운 스크롤 OFF(외장 마우스에서 흔한 설정): 같은 '위로'가 deltaY 양수로 온다 → 역시 값 증가.
    var classic = TodoBoardScrollOpacityGesture()
    #expect(classic.steps(for: todoBoardTrackpad(step, inverted: false)) == 1)
    classic.reset()
    #expect(classic.steps(for: todoBoardTrackpad(-step, inverted: false)) == -1)
}

/// 걸림쇠 휠은 장치가 이미 끊어서 준다. 한 칸이 몇 '줄'로 오는지는 드라이버마다 달라(1 또는 3)
/// 거리로 환산해 문턱과 견주면 기기에 따라 한 칸이 세 칸이 된다 — **이벤트 하나 = 한 스텝**으로 센다.
@Test
func todoBoardWheelDetentIsExactlyOneStepRegardlessOfMagnitude() {
    var gesture = TodoBoardScrollOpacityGesture()
    #expect(gesture.steps(for: todoBoardWheel(1)) == 1)
    #expect(gesture.steps(for: todoBoardWheel(3)) == 1)
    #expect(gesture.steps(for: todoBoardWheel(0.1)) == 1)
    #expect(gesture.steps(for: todoBoardWheel(-1)) == -1)
    #expect(gesture.steps(for: todoBoardWheel(-120)) == -1)
    // 자연스러운 스크롤을 켠 마우스에서도 물리 방향 기준은 같다.
    #expect(gesture.steps(for: todoBoardWheel(1, inverted: true)) == -1)
}

/// 손을 뗀 뒤 관성으로 흘러오는 이벤트는 버린다. 값이 혼자 흘러가면 멈출 방법이 없고,
/// 사용자는 자기가 놓은 자리가 아닌 곳에서 끝난 값을 보게 된다.
@Test
func todoBoardScrollIgnoresMomentumAndDropsLeftoverWithIt() {
    var gesture = TodoBoardScrollOpacityGesture()
    let step = TodoBoardScrollOpacityGesture.stepDistance

    #expect(gesture.steps(for: todoBoardTrackpad(-step * 0.9)) == 0)   // 잔여 0.9칸
    let momentum = TodoBoardScrollSample(deltaY: -step * 10, isPrecise: true, isInverted: true, isMomentum: true)
    #expect(gesture.steps(for: momentum) == 0, "관성이 값을 밀었다")
    // 관성은 제스처가 끝났다는 뜻 — 잔여도 같이 털었으므로 다음 제스처는 처음부터 모은다.
    #expect(gesture.steps(for: todoBoardTrackpad(-step * 0.9)) == 0)
}

/// 방향을 꺾으면 반대편 잔여를 버린다. 남겨 두면 되돌리는 조작만 유독 둔해진다
/// (+0.9칸 쌓다 꺾으면 1.9칸을 밀어야 한 칸 내려간다).
@Test
func todoBoardScrollDropsLeftoverWhenDirectionFlips() {
    var gesture = TodoBoardScrollOpacityGesture()
    let step = TodoBoardScrollOpacityGesture.stepDistance

    #expect(gesture.steps(for: todoBoardTrackpad(-step * 0.9)) == 0)
    #expect(gesture.steps(for: todoBoardTrackpad(step * 0.9)) == 0)    // 꺾었다 — 여기서 -1 이 나오면 안 된다
    #expect(gesture.steps(for: todoBoardTrackpad(step * 0.2)) == -1)   // 새로 모아 한 칸
}

/// 드라이버가 튀는 값(무한대·NaN·거대한 델타)을 흘리는 일이 실제로 있다.
/// 무한대를 그대로 나누면 `Int` 변환에서 붕괴하고, 살짝 굴린 한 번에 값이 끝으로 순간이동한다.
@Test
func todoBoardScrollSurvivesGarbageDeltas() {
    var gesture = TodoBoardScrollOpacityGesture()
    #expect(gesture.steps(for: todoBoardTrackpad(.nan)) == 0)
    #expect(gesture.steps(for: todoBoardTrackpad(.infinity)) == 0)
    #expect(gesture.steps(for: todoBoardTrackpad(-.infinity)) == 0)
    #expect(gesture.steps(for: todoBoardTrackpad(0)) == 0)

    let huge = gesture.steps(for: todoBoardTrackpad(-1e18))
    #expect(huge <= Int(TodoBoardScrollOpacityGesture.maxStepsPerEvent))
    // 그리고 한도에 걸린 이벤트의 잔여는 남지 않는다(다음 이벤트가 곧바로 또 튀면 안 된다).
    #expect(gesture.steps(for: todoBoardTrackpad(-1)) == 0)
}

/// 감도 계약: **한 번 쓸기 = 레일의 절반**. 스텝 크기는 설정 모델이 언제든 바꿀 수 있으므로
/// 스텝 수를 박지 않고 그때의 레일에 견줘 잰다(박아 두면 모델이 스텝을 잘게 바꾸는 순간 조용히 굼떠진다).
@Test
func todoBoardScrollSweepMovesAboutHalfTheRail() {
    var gesture = TodoBoardScrollOpacityGesture()
    var total = 0
    // 한 번 쓸기를 4pt 짜리 이벤트로 잘게 흘린다(트랙패드가 실제로 보내는 모양이다).
    let events = Int(TodoBoardScrollOpacityGesture.sweepDistance / 4)
    for _ in 0..<events {
        total += gesture.steps(for: todoBoardTrackpad(-4))
    }
    let rail = TodoBoardScrollOpacityGesture.railSteps
    #expect(abs(Double(total) - rail / 2) <= 1, "한 번 쓸기에 \(total)스텝(레일 \(rail)스텝)")
    // 값으로도 확인 — 한 번 쓸기에 대략 레일 폭의 절반이 움직인다.
    let moved = Double(total) * TodoBoardAppearance.step
    let span = TodoBoardAppearance.maxOpacity - TodoBoardAppearance.minOpacity
    #expect(moved > span * 0.35 && moved < span * 0.65, "한 번 쓸기에 \(moved) 이동")
}

/// 잘게 오는 이벤트를 그대로 곱하면 어떻게 되는지 반대편에서 못 박는다 — 이벤트마다 한 스텝을 쐈다면
/// 위 쓸기 한 번에 60스텝이 나가 레일을 몇 바퀴 왕복한다. 누적기의 존재 이유가 이 숫자 차이다.
@Test
func todoBoardScrollNeverFiresOncePerEvent() {
    var gesture = TodoBoardScrollOpacityGesture()
    var fired = 0
    for _ in 0..<60 where gesture.steps(for: todoBoardTrackpad(-4)) != 0 { fired += 1 }
    #expect(fired < 60)
}

// MARK: - 18) 모니터 수명 — 열려 있는 동안에만

/// 로컬 모니터는 **앱 전체**의 스크롤을 본다. 보드를 안 쓰는 내내 켜 둘 이유가 없고,
/// 닫을 때 떼지 않으면 죽은 클로저가 모든 스크롤을 거쳐 간다.
@MainActor
@Test
func todoBoardScrollMonitorLivesOnlyWhileTheBoardIsOpen() {
    let controller = CheckTodoBoardController(
        store: makeTodoBoardStore(), appearance: makeTodoBoardAppearanceStore()
    )
    #expect(controller.hasScrollMonitor == false, "열지도 않았는데 전역 훅이 걸렸다")

    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.hasScrollMonitor)

    // 멱등: 열린 채로 또 열어도 훅은 하나뿐이다(두 번 걸면 한 틱에 두 스텝이 나간다).
    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.hasScrollMonitor)

    controller.close()
    #expect(controller.hasScrollMonitor == false, "닫았는데 훅이 남았다")

    // 토글로 여닫아도 같다.
    controller.toggle(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.hasScrollMonitor)
    controller.toggle(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    #expect(controller.hasScrollMonitor == false)
}




// MARK: - 17) 스위트가 사용자 화면을 덮지 않는다

/// 캐릭터 패널 쪽 짝(`overlayPanelStaysInvisibleToTheUserWhileTesting`)의 보드 버전이다.
/// 보드는 캐릭터보다 더 자주 열리고(이 파일만 해도 수십 번), 300×400 짜리 불투명해 보이는 판이라
/// 사용자 화면에 그대로 뜨면 눈에 가장 먼저 걸린다.
///
/// **핵심은 이 파일의 블러 검증이 여전히 산다는 것이다.** 알파 0 은 합성 단계에서만 지우므로
/// `orderFrontRegardless` 로 창이 화면에 올라간 사실도, 그 위에 서는 `CABackdropLayer` 도,
/// `cacheDisplay` 로 뜬 백킹스토어 픽셀도 그대로다(같은 머신 실측: 알파 1 일 때와 알파 0 일 때
/// 중앙 0.5686 / 모서리 0.000 이 **소수점까지 동일**했고 backdrop 도 양쪽 다 존재했다).
@MainActor
@Test
func todoBoardPanelStaysInvisibleToTheUserWhileTesting() throws {
    #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 죽었다 — 보드가 사용자 화면에 뜬다")
    #expect(CheckTodoBoardController.makePanel().alphaValue == 0)

    let controller = CheckTodoBoardController(
        store: makeTodoBoardStore(), appearance: makeTodoBoardAppearanceStore()
    )
    controller.open(anchor: todoBoardTestAnchor, screenVisibleFrame: todoBoardTestVisibleFrame)
    defer { controller.close() }
    todoBoardPump()

    #expect(controller.isBoardOpen)
    #expect(controller.panel.alphaValue == 0, "보드가 사용자 화면에 보인다")
    // 창은 **실제로 화면에 올라가 있어야 한다** — 여기서 물러났다면 블러 검증이 함께 죽는다.
    #expect(controller.panel.isVisible, "창을 아예 안 띄웠다 — CABackdropLayer 가 서지 않는다")
    // 그리고 위치·크기는 한 톨도 안 건드렸다(화면 밖으로 밀어내는 방식을 배제한 이유).
    #expect(controller.panel.frame
        == TodoBoardAnchor.frame(anchor: todoBoardTestAnchor, in: todoBoardTestVisibleFrame))

    // 블러 체인이 알파 0 아래에서도 그대로 산다는 것을 같은 테스트 안에서 확인한다.
    let (_, blur, hosting) = try todoBoardLayers(controller.panel)
    #expect(todoBoardHasBackdropLayer(try #require(blur.layer)))
    let center = try todoBoardPixelAlpha(hosting, x: Int(hosting.bounds.width) / 2,
                                         y: Int(hosting.bounds.height) / 2)
    #expect(center > 0.05 && center < 0.95, "cacheDisplay 픽셀 실측이 죽었다(alpha=\(center))")
}
