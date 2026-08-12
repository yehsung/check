import AppKit
import Observation
import SwiftUI

// MARK: - 패널

/// 투두 보드가 사는 패널. **`canBecomeKey` 오버라이드가 이 타입의 존재 이유 전부다.**
///
/// 보드 패널은 캐릭터 패널과 같은 `[.borderless, .nonactivatingPanel]` 조합을 쓰는데, 이 조합은
/// 기본 구현에서 키 윈도우가 **되지 못한다**(NSWindow 의 기본 `canBecomeKey` 는 타이틀바가 있거나
/// 리사이즈 가능한 창에만 true 를 준다). 그 상태로 보드를 띄우면 화면에는 보이는데 텍스트필드에
/// 캐럿이 서지 않아 **글자를 한 자도 넣을 수 없다**(실측). 캐릭터 패널은 클릭 통과 전용이라 이 문제가
/// 아예 없었지만, 보드는 '적는 것'이 존재 이유라 여기서만 뒤집는다.
///
/// `.nonactivatingPanel` 은 그대로 둔다 — 키가 되어도 **앱을 활성화하지 않는다**. 즉 사용자가 쓰던
/// 앱의 창은 계속 앞에 있고, 우리 보드만 키를 가져가 입력을 받는다.
final class TodoBoardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - 배치(순수 함수)

/// 캐릭터(앵커) 옆에 보드를 놓는 규칙. 화면·창에 손대지 않는 **값 계산만** 하므로 헤드리스로 전부 검증된다.
enum TodoBoardAnchor {
    /// 보드 크기(pt). 고정 — 내용이 늘어도 창이 자라지 않고 내부에서 스크롤한다.
    static let boardSize = NSSize(width: 300, height: 400)
    /// 캐릭터와 보드 사이 간격(pt).
    static let gap: CGFloat = 10

    /// 캐릭터 프레임(`anchor`, 스크린 좌표)과 그 화면의 `visible`(visibleFrame)로 보드 프레임을 계산한다.
    ///
    /// 규칙:
    /// · 기본은 **캐릭터 왼쪽**(보드 maxX = anchor.minX - gap), **상단 정렬**(보드 maxY = anchor.maxY).
    ///   캐릭터는 기본이 화면 우상단이라 왼쪽이 거의 항상 넉넉하고, 상단 정렬이면 보드가 메뉴바 바로 아래에서
    ///   아래로 자라 시선 이동이 짧다.
    /// · 왼쪽이 화면 밖으로 나가면 **오른쪽으로 뒤집는다**(보드 minX = anchor.maxX + gap).
    /// · 뒤집어도 안 들어가면 **뒤집지 않고 화면 안으로 클램프한다**. 보드가 잘려 글자를 못 읽는 것보다
    ///   캐릭터를 잠깐 가리는 편이 낫다(캐릭터는 장식이고 보드는 내용이다).
    /// · 세로는 클램프만 한다. **아래→위 뒤집기는 하지 않는다** — 위로 뒤집으면 보드가 캐릭터 위로 튀어올라
    ///   메뉴바를 향해 자라는 꼴이 되어, 같은 클릭에 보드가 위/아래를 오가는 정신없는 배치가 된다.
    static func frame(anchor: NSRect, in visible: NSRect) -> NSRect {
        let size = boardSize
        var x = anchor.minX - gap - size.width
        if x < visible.minX {
            let flipped = anchor.maxX + gap
            // 뒤집은 자리가 **온전히** 들어갈 때만 뒤집는다. 어차피 잘릴 자리로 옮기면 왼쪽 클램프보다
            // 나을 게 없으면서 위치만 오락가락한다.
            if flipped + size.width <= visible.maxX {
                x = flipped
            }
        }
        let y = anchor.maxY - size.height
        return NSRect(origin: clamped(NSPoint(x: x, y: y), size: size, in: visible), size: size)
    }

    /// 프레임 전체가 `visible` 안에 들도록 origin 을 당긴다. 보드가 화면보다 큰 극단에서는 좌하단 정렬을
    /// 우선한다(`CheckOverlayController.clampedOrigin` 과 같은 계약 — 두 창이 다르게 잘리면 안 된다).
    private static func clamped(_ origin: NSPoint, size: NSSize, in visible: NSRect) -> NSPoint {
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        return NSPoint(
            x: min(max(origin.x, visible.minX), maxX),
            y: min(max(origin.y, visible.minY), maxY)
        )
    }
}

// MARK: - 보드 UI 상태(컨트롤러 소유)

/// 보드의 **입력 상태**. 뷰의 `@State` 가 아니라 컨트롤러가 소유해야 하는 값들만 모았다.
///
/// 왜 뷰에 두지 않는가: 울트라 격발처럼 보드를 잠깐 내렸다 다시 올리는 경로가 이미 있고, 그때 SwiftUI 는
/// 뷰 트리를 다시 만들 수 있다 — `@State` 였다면 **적다 만 글이 통째로 사라진다**. 창을 살려 두는 것만으로는
/// 부족하다(상태의 주인이 뷰이면 뷰가 다시 만들어질 때 같이 날아간다).
///
/// 쓰기는 전부 `CheckTodoBoardController` 의 setter 를 거친다(그쪽에 `!=` 가드와 100자 차단이 있다).
/// 여기서는 저장만 한다.
@Observable
@MainActor
final class TodoBoardUIState {
    /// 입력칸 초안.
    var draft: String
    /// 인라인 수정 중인 항목. nil 이면 수정 중 아님.
    var editingID: UUID?
    /// '삭제됨 [되돌리기]' 로 자리를 지키고 있는 항목(아직 store 에서 지우지 않았다).
    var pendingDeleteID: UUID?
    /// 하단 '오래된 항목 (N)' 펼침 여부.
    var isOldSectionExpanded: Bool
    /// 보드가 기준으로 삼는 KST 하루 키. 컨트롤러가 열 때·손댈 때 갱신한다(자정 넘김 반영).
    var todayKey: String

    init(todayKey: String) {
        self.draft = ""
        self.editingID = nil
        self.pendingDeleteID = nil
        self.isOldSectionExpanded = false
        self.todayKey = todayKey
    }
}

// MARK: - 패널 콘텐츠 루트

/// 패널에 얹는 배선용 루트 뷰. 스토어와 UI 상태를 **관찰**해서 순수 뷰 `CheckTodoBoardView` 에는
/// 값과 클로저만 내려 준다 — 그래야 보드 본체가 store 를 모른 채 픽스처만으로 렌더 검증된다.
/// (캐릭터 오버레이의 `CheckOverlayRootView` 와 같은 역할이다.)
///
/// `@MainActor` 를 명시한 이유: 아래 `Binding(get:set:)` 이 받는 클로저는 `@Sendable` 이라, 붙들고 있는
/// 값들이 메인 액터에 묶여 있다는 것이 **타입 수준에서** 드러나야 캡처가 허용된다(뷰 body 는 어차피
/// 메인 액터에서만 돈다 — 사실을 적어 두는 것뿐이다).
@MainActor
private struct TodoBoardRootView: View {
    let store: TodoListStore
    let ui: TodoBoardUIState
    let onDraftChange: (String) -> Void
    let onSubmitDraft: () -> Void
    let onToggleDone: (UUID) -> Void
    let onBeginEdit: (UUID) -> Void
    let onCommitEdit: (UUID, String) -> Void
    let onCancelEdit: () -> Void
    let onDelete: (UUID) -> Void
    let onUndoDelete: (UUID) -> Void
    let onToggleOldSection: () -> Void
    let onClose: () -> Void

    var body: some View {
        let key = ui.todayKey
        // 표시 규칙(자정 지난 완료 감추기·삭제 제외)과 **정렬은 TodoRules 가 단독으로 소유한다**.
        // 여기서 한 번 더 정렬하면 순서 정책이 두 곳으로 갈라져 조용히 어긋난다. 우리는 '오래된 항목'
        // 구간만 갈라내고 원래 순서를 그대로 보존한다.
        let all = TodoRules.visible(store.items, todayKey: key)
        var active: [TodoItem] = []
        var old: [TodoItem] = []
        for item in all {
            if TodoRules.isOld(item, todayKey: key) {
                old.append(item)
            } else {
                active.append(item)
            }
        }
        // 바인딩 클로저에는 뷰 자신(self)이 아니라 필요한 둘만 넘긴다 — 붙잡는 것이 적을수록 수명이 명확하다.
        let state = ui
        let write = onDraftChange
        return CheckTodoBoardView(
            items: active,
            oldItems: old,
            todayKey: key,
            isOldSectionExpanded: ui.isOldSectionExpanded,
            editingID: ui.editingID,
            pendingDeleteID: ui.pendingDeleteID,
            // 읽기는 관찰 대상(ui.draft)에서 곧바로, 쓰기는 컨트롤러를 거친다 — 100자 차단과 `!=` 가드가
            // 거기 한 곳에만 있어야 입력칸이 어느 경로로 바뀌든 규칙이 똑같이 걸린다.
            draft: Binding(get: { state.draft }, set: { write($0) }),
            onSubmitDraft: onSubmitDraft,
            onToggleDone: onToggleDone,
            onBeginEdit: onBeginEdit,
            onCommitEdit: onCommitEdit,
            onCancelEdit: onCancelEdit,
            onDelete: onDelete,
            onUndoDelete: onUndoDelete,
            onToggleOldSection: onToggleOldSection,
            onClose: onClose
        )
    }
}

// MARK: - 컨트롤러

/// 투두 보드 패널의 수명·배치·입력 상태를 쥐는 컨트롤러.
///
/// 캐릭터 오버레이 컨트롤러와의 차이만 적는다: 이 창은 **클릭을 받고 키가 되며**(입력이 목적),
/// 화면공유·녹화에서 제외되고(`sharingType = .none`), 근무 상태가 아니라 **사용자의 클릭**으로만 뜬다.
@MainActor
final class CheckTodoBoardController {
    /// 표시 의도(헤드리스 검증 지점). 실제 표시 여부는 `panel.isVisible` 이지만 그건 헤드리스에서 흔들린다.
    private(set) var isBoardOpen = false

    private let store: TodoListStore
    /// 보드 입력 상태의 주인. 패널을 내려도, 뷰가 다시 만들어져도 여기 남는다.
    private let ui: TodoBoardUIState
    /// 지연 생성된 패널. **닫을 때 파괴하지 않는다** — NSHostingView 를 다시 만드는 비용도 비용이지만,
    /// 재생성 과정에서 3D 캐릭터 옆에 한 프레임 빈 창이 스치고 포커스가 튀는 게 더 나쁘다.
    private var panelStorage: TodoBoardPanel?
    /// '삭제됨 [되돌리기]' 창을 닫는 타이머. 이 태스크가 끝나면 삭제가 확정된다.
    private var undoTask: Task<Void, Never>?

    /// 이 인스턴스의 되돌리기 유예(초). 프로덕션은 언제나 `TodoRules.undoSeconds`(5).
    /// **테스트만** 짧게 주입해 "타이머가 스스로 깨어나 삭제를 확정하는가"를 실시간으로 검증한다.
    /// (오버레이의 `ultraDurationSeconds` 와 같은 이유 — 주입 지점이 없으면 그 검증에 매번 5초가 들어
    ///  아무도 안 쓰게 되고, 결국 타이머 생성을 통째로 지워도 스위트가 초록인 구멍이 생긴다.)
    let undoSeconds: Double

    init(store: TodoListStore, undoSeconds: Double = TodoRules.undoSeconds) {
        self.store = store
        self.undoSeconds = undoSeconds
        self.ui = TodoBoardUIState(todayKey: store.todayKey)
    }

    // MARK: - 패널

    /// 패널(첫 접근에 생성). 근무 내내 안 열 수도 있는 창이라 앱 시작 시 만들지 않는다.
    var panel: TodoBoardPanel {
        if let panelStorage { return panelStorage }
        let created = Self.makePanel()
        let hosting = NSHostingView(rootView: makeRootView())
        hosting.frame = NSRect(origin: .zero, size: TodoBoardAnchor.boardSize)
        hosting.autoresizingMask = [.width, .height]
        created.contentView = hosting
        panelStorage = created
        return created
    }

    /// 헤드리스 검증 지점 — '패널을 이미 만들었는가'. 지연 생성(열기 전엔 없음)과 닫아도 살아 있음
    /// (입력 상태 보존)을 밖에서 값으로 확인하려면 이 문이 필요하다. `panel` 을 읽으면 그 순간 만들어져
    /// 버리므로 이 프로퍼티로만 물어야 한다.
    var hasPanel: Bool { panelStorage != nil }

    /// 보드 패널을 만든다. 캐릭터 패널(`CheckOverlayController.makePanel`)과 **다른 점**:
    /// · `ignoresMouseEvents = false` — 체크·수정·삭제를 클릭으로 받는 창이다.
    /// · `hasShadow = true` — 반투명 보드가 뒤 창과 뒤섞이지 않게 경계를 세운다.
    /// · `TodoBoardPanel` — 키를 받을 수 있어야 글자가 들어간다(위 타입 주석 참고).
    /// 나머지(레벨·투명 배경·전 Space 유지·비활성화 시 숨지 않음)는 캐릭터 패널과 같은 값을 쓴다.
    static func makePanel() -> TodoBoardPanel {
        let panel = TodoBoardPanel(
            contentRect: NSRect(origin: .zero, size: TodoBoardAnchor.boardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        // NSPanel 의 기본값은 **true** 다. 그대로 두면 사용자가 원래 쓰던 앱이 활성인 동안(=거의 항상)
        // 보드가 저절로 숨는다 — 우리는 앱을 활성화하지 않는 창이므로 이 값을 반드시 뒤집어야 한다.
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // 위치는 컨트롤러가 앵커로 계산한다. 사용자가 끌어 옮기면 캐릭터와 어긋난 채 남아 다음 열기에 튄다.
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // ★ 프라이버시 방어선. 투두 본문은 업무 정보(고객명·계약·급여 같은 게 그대로 적힌다)라
        //   화면공유·녹화에 **절대** 실리면 안 된다. 발표 중 캐릭터를 눌러 보드를 여는 일은 반드시 일어나고,
        //   그때 사용자가 막을 수단은 없다 — 창 자체를 캡처 대상에서 뺀다.
        panel.sharingType = .none
        // 우리가 패널을 계속 붙들고 재사용하므로(닫기=orderOut) 닫힘에 딸린 해제가 끼어들면 안 된다.
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func makeRootView() -> TodoBoardRootView {
        // 패널 → 호스팅 뷰 → 루트 뷰 → 클로저가 컨트롤러를 도로 잡으므로 전부 weak 로 끊는다.
        TodoBoardRootView(
            store: store,
            ui: ui,
            onDraftChange: { [weak self] text in self?.setDraft(text) },
            onSubmitDraft: { [weak self] in self?.submitDraft() },
            onToggleDone: { [weak self] id in self?.toggleDone(id) },
            onBeginEdit: { [weak self] id in self?.beginEdit(id) },
            onCommitEdit: { [weak self] id, text in self?.commitEdit(id, to: text) },
            onCancelEdit: { [weak self] in self?.cancelEdit() },
            onDelete: { [weak self] id in self?.requestDelete(id) },
            onUndoDelete: { [weak self] id in self?.undoDelete(id) },
            onToggleOldSection: { [weak self] in self?.toggleOldSection() },
            onClose: { [weak self] in self?.close() }
        )
    }

    // MARK: - 열기 / 닫기 / 배치

    /// 캐릭터 클릭 진입점. 열려 있으면 닫고, 닫혀 있으면 그 자리에 연다.
    func toggle(anchor: NSRect, screenVisibleFrame: NSRect) {
        if isBoardOpen {
            close()
        } else {
            open(anchor: anchor, screenVisibleFrame: screenVisibleFrame)
        }
    }

    /// 보드를 앵커 옆에 띄운다(멱등 — 이미 열려 있으면 위치만 다시 잡는다).
    ///
    /// **`makeKey` 를 부르지 않는다.** 프로그램으로 키를 가져오면 실측상 앱이 활성화되어(nonactivating 패널도
    /// `makeKeyAndOrderFront` 경로에서는 활성화를 유발한다) 사용자가 쓰던 편집기·브라우저가 비활성이 된다 —
    /// 할 일 하나 적자고 남의 창 포커스를 뺏는 셈이다. 그래서 **2단 포커스**로 간다: 여기서는 띄우기만 하고,
    /// 사용자가 입력칸을 클릭하는 순간 nonactivating 패널이 스스로 키를 가져간다(그때는 앱이 활성화되지 않는다).
    ///
    /// `display: false` 인 이유는 캐릭터 패널과 같다 — 여기서 표시 패스를 강제하면 AppKit 이 그 자리에서
    /// SwiftUI 를 평가해 우리 콜백을 재진입시킨다. 프레임 값은 이 줄에서 이미 확정되고 그리기만 다음
    /// 런루프로 밀린다.
    func open(anchor: NSRect, screenVisibleFrame: NSRect) {
        syncTodayKey()
        let board = panel
        board.setFrame(TodoBoardAnchor.frame(anchor: anchor, in: screenVisibleFrame), display: false)
        board.orderFrontRegardless()
        isBoardOpen = true
    }

    /// 보드를 내린다(멱등). 패널과 입력 상태(초안·수정 중)는 **그대로 남는다** — 다시 열면 적다 만 글이
    /// 그 자리에 있어야 한다.
    ///
    /// 단 하나, 삭제 되돌리기만은 여기서 **확정**한다. 5초 유예는 '눈에 보이는 되돌리기 버튼'이 있을 때만
    /// 성립하는 약속이라, 보드를 내린 채 재는 카운트다운은 사용자가 볼 수도 누를 수도 없는 유령이다.
    /// 남겨 두면 다시 열었을 때 유령 '삭제됨' 행이 서 있거나, 보이지 않는 곳에서 항목이 사라진다.
    func close() {
        commitPendingDelete()
        panelStorage?.orderOut(nil)
        isBoardOpen = false
    }

    /// 캐릭터가 움직였을 때 보드를 따라 옮긴다. 닫혀 있으면 아무것도 하지 않는다 —
    /// 특히 `panel` 을 건드리지 않는다(안 그러면 열지도 않은 창을 여기서 만들어 버린다).
    func reposition(anchor: NSRect, screenVisibleFrame: NSRect) {
        guard isBoardOpen, let panelStorage else { return }
        panelStorage.setFrame(TodoBoardAnchor.frame(anchor: anchor, in: screenVisibleFrame), display: false)
    }

    // MARK: - 입력 상태(컨트롤러가 소유)

    var draft: String { ui.draft }
    var editingID: UUID? { ui.editingID }
    var pendingDeleteID: UUID? { ui.pendingDeleteID }
    var isOldSectionExpanded: Bool { ui.isOldSectionExpanded }
    /// 보드가 기준으로 삼는 KST 하루 키(헤드리스 검증 지점).
    var todayKey: String { ui.todayKey }

    /// 초안을 바꾼다. **100자를 넘기는 입력은 통째로 거부한다** — 자르지 않는다.
    /// 잘라 버리면 사용자가 방금 친 글자가 소리 없이 사라져 어디까지 들어갔는지 알 수 없다. 거부하면
    /// 화면이 그대로 멈춰 "더는 안 들어간다"가 보인다(90자부터 뜨는 카운터가 그 이유를 설명한다).
    /// 길이는 정규화 전 **사용자가 보는 글자 수**로 잰다(정규화는 저장 시점의 일이다).
    /// 짧아지는 방향은 언제나 허용되므로, 어떤 경로로 100자를 넘겨 들어왔더라도 지워서 빠져나올 수 있다.
    func setDraft(_ text: String) {
        guard text.count <= TodoRules.maxTitleLength || text.count < ui.draft.count else { return }
        if ui.draft != text { ui.draft = text }
    }

    /// 입력칸 Enter. 성공했을 때만 초안을 비운다 — 공백만 친 입력을 store 가 거절했는데 여기서 지워 버리면
    /// 사용자가 친 것이 이유 없이 증발한다.
    func submitDraft() {
        syncTodayKey()
        guard store.add(ui.draft) != nil else { return }
        setDraft("")
    }

    func toggleDone(_ id: UUID) {
        syncTodayKey()
        store.toggleDone(id)
    }

    func beginEdit(_ id: UUID) {
        if ui.editingID != id { ui.editingID = id }
    }

    /// 인라인 수정 Enter. 저장 여부(빈 제목 거절 등)는 store 의 규칙에 맡기고, 수정 모드는 어느 쪽이든 닫는다 —
    /// 커밋을 눌렀는데 행이 계속 편집 상태로 남아 있으면 사용자는 저장이 안 된 줄 안다.
    func commitEdit(_ id: UUID, to rawTitle: String) {
        syncTodayKey()
        store.rename(id, to: rawTitle)
        cancelEdit()
    }

    /// 수정 모드 종료(Esc·커밋 후 공용). 원래 제목은 store 가 계속 들고 있으므로 여기서 되돌릴 것이 없다.
    func cancelEdit() {
        if ui.editingID != nil { ui.editingID = nil }
    }

    func toggleOldSection() {
        ui.isOldSectionExpanded.toggle()
    }

    // MARK: - 삭제 · 되돌리기(5초)

    /// 삭제 요청. **store 를 아직 건드리지 않는다.**
    ///
    /// 뷰가 보는 목록은 `TodoRules.visible` 이 걸러 낸 것뿐이라, 여기서 곧바로 지우면 그 항목이 목록에서
    /// 사라져 '삭제됨 [되돌리기]' 행이 설 자리 자체가 없어진다. 그래서 5초 동안은 항목을 그대로 두고
    /// `pendingDeleteID` 로만 표시해 그 자리에서 되돌릴 수 있게 하고, 유예가 끝나면 그때 지운다.
    ///
    /// 이미 다른 항목이 대기 중이면 그것을 먼저 확정한다 — 동시에 두 줄이 '삭제됨'으로 서 있으면
    /// 어느 되돌리기가 어느 줄의 것인지 알 수 없고, 타이머도 한 개뿐이다.
    func requestDelete(_ id: UUID) {
        if let pending = ui.pendingDeleteID, pending != id {
            commitPendingDelete()
        }
        syncTodayKey()
        if ui.pendingDeleteID != id { ui.pendingDeleteID = id }
        undoTask?.cancel()
        // 유예 값은 잠들기 **전에** 꺼내 둔다(자는 동안 컨트롤러를 붙들지 않게 — weak 로 끊는 이유가 사라진다).
        let seconds = undoSeconds
        undoTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.commitPendingDelete()
        }
    }

    /// 되돌리기.
    ///
    /// 유예 중이면 아직 store 에 반영되지 않았으니 타이머를 끄는 것만으로 원상복구다.
    /// 대기 중이 아니면 **방금 확정된 직후의 늦은 클릭**이다(타이머가 먼저 깨어난 한 런루프 차이).
    /// 사용자는 분명히 되돌리기를 눌렀으므로 그 경우엔 store 에 되살리기를 부탁한다 — 여기서 조용히
    /// 물러나면 "눌렀는데 안 돌아왔다"가 된다.
    func undoDelete(_ id: UUID) {
        if ui.pendingDeleteID == id {
            undoTask?.cancel()
            undoTask = nil
            ui.pendingDeleteID = nil
            return
        }
        store.undoDelete(id)
    }

    /// 대기 중인 삭제를 지금 확정한다(멱등). 타이머 만료·보드 닫기·다른 항목 삭제가 모두 여기로 모인다.
    func commitPendingDelete() {
        undoTask?.cancel()
        undoTask = nil
        guard let id = ui.pendingDeleteID else { return }
        ui.pendingDeleteID = nil
        store.delete(id)
    }

    // MARK: - 하루 경계

    /// 보드가 쓰는 하루 키를 store 의 현재 값으로 맞춘다(값이 같으면 대입하지 않는다 — 같은 값 재대입도
    /// 관찰자를 깨워 보드 전체가 다시 그려진다).
    ///
    /// 열 때와 손댈 때마다 부른다. `store.todayKey` 는 시계를 읽는 계산 프로퍼티라 관찰 대상이 아니어서,
    /// 이 갱신이 없으면 자정을 넘겨 보드를 다시 열어도 **어제 기준 화면**이 그대로 서 있다
    /// (완료 항목이 안 사라지고 이월 배지도 안 는다).
    private func syncTodayKey() {
        let key = store.todayKey
        if ui.todayKey != key { ui.todayKey = key }
    }
}
