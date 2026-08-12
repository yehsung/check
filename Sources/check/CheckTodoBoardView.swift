import AppKit
import SwiftUI

// MARK: - 문구

/// 보드에 쓰이는 모든 문구. 뷰 밖 순수 enum 으로 둔 이유는 CheckMenuView 의 *EmptyMessage 들과 같다 —
/// 문구는 제품 결정이라 뷰를 그리지 않고도 값 하나로 리뷰·회귀 검증이 되어야 한다.
enum TodoBoardStrings {
    static let title = "오늘 할 일"
    static let close = "닫기"
    static let placeholder = "할 일 추가"
    /// 빈 상태를 2줄로 쪼갠 이유: 첫 줄은 사실(비었다), 둘째 줄은 다음 행동(적고 Enter).
    /// 한 줄로 합치면 처음 여는 사용자가 위쪽 입력 행을 못 찾는다 — 이 보드에는 다른 안내가 없다.
    static let emptyTitle = "오늘 할 일이 비어 있어요"
    static let emptyHint = "위에 적고 Enter를 누르세요"
    static let deleted = "삭제됨"
    static let undo = "되돌리기"
    /// 하단 캡션은 항상 떠 있는다. 같은 앱 안에서 근무 기록은 팀으로 나가기 때문에, 이 목록만은
    /// 서버로 가지 않는다는 사실을 매번 보여 줘야 사용자가 사적인 메모를 마음 놓고 적는다.
    static let footer = "이 목록은 내 맥에만 저장돼요"
    static let markDone = "완료로 표시"
    static let markUndone = "완료 취소"
    static let deleteItem = "삭제"
    static let editTitle = "할 일 수정"

    static func oldSection(count: Int) -> String {
        "오래된 항목 (\(count))"
    }

    /// 입력 카운터. 분모를 TodoRules.maxTitleLength 에서 읽어 문구와 실제 제한이 갈라지지 않게 한다.
    static func counter(current: Int) -> String {
        "\(current)/\(TodoRules.maxTitleLength)"
    }
}

// MARK: - 입력 길이 판정(순수)

/// 제목 입력 길이 제한 판정. 뷰에서 떼어 낸 이유는 '막는다 vs 자른다'가 사용자가 직접 확정한 제품 결정이라
/// 렌더 없이 값으로 지켜져야 하기 때문이다.
enum TodoDraftInput {
    /// 새 입력(proposed)을 실제로 반영할지 고른다. 반영하지 않을 땐 이전 값(current)을 그대로 돌려준다.
    static func accepted(current: String, proposed: String) -> String {
        // 지우는 방향(길이가 줄어듦)은 무조건 통과시킨다. 어떤 경로로든 100자를 넘긴 값이 필드에 들어와도
        // 이 예외가 없으면 사용자가 한 글자도 못 지우고 갇힌다.
        if proposed.count <= current.count { return proposed }
        // 늘리는 방향은 100자까지. 초과분만 잘라 넣는 게 아니라 변경 자체를 되돌린다 —
        // 자동 절단은 붙여넣은 문장 끝이 소리 없이 사라져 '분명 적었는데 없어졌다'로 읽힌다.
        return proposed.count <= TodoRules.maxTitleLength ? proposed : current
    }

    /// 카운터 문구. 한계에서 멀 땐 nil 이라 숫자가 아예 안 뜬다 — 평소에 늘 떠 있으면 글자 수를 세는 도구처럼
    /// 보여서, 짧게 적어야 한다는 압박을 준다.
    static func counterText(_ text: String) -> String? {
        let count = text.count
        guard count >= TodoRules.counterVisibleFrom else { return nil }
        return TodoBoardStrings.counter(current: count)
    }
}

// MARK: - 반투명 배경

/// 창 뒤 바탕화면을 흐리는 블러 레이어. 보드가 '떠 있는 쪽지'처럼 보이게 하는 유일한 재료다.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        // .followsWindowActiveState 로 두면 다른 앱을 클릭하는 순간 블러가 꺼져 보드가 회색 판으로 죽는다.
        // 이 보드는 작업 중인 다른 앱 위에 계속 떠 있는 게 목적이라 항상 .active 로 고정한다.
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // 재적용하는 이유: 창 이동·화면 전환으로 뷰가 다시 붙을 때 AppKit 이 state 를 되돌리는 경우가 있다.
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

// MARK: - 보드

/// 근무 중 떠 있는 캐릭터를 클릭하면 열리는 할 일 보드(300×400). 서버를 모르고 store 도 모른다 —
/// 값 + 클로저만 받아, 렌더 테스트가 픽스처만으로 모든 상태(편집 중·삭제 대기·오래된 항목 펼침)를 재현한다.
struct CheckTodoBoardView: View {
    /// 이미 필터·정렬된 '활성' 목록(오늘 완료한 항목 포함). 뷰는 순서를 바꾸지 않는다.
    let items: [TodoItem]
    /// 7일 이상 이월된 미완료 항목. 비어 있지 않을 때만 하단 접힘 영역이 생긴다.
    let oldItems: [TodoItem]
    let todayKey: String
    let isOldSectionExpanded: Bool
    let editingID: UUID?
    let pendingDeleteID: UUID?
    @Binding var draft: String
    let onSubmitDraft: () -> Void
    let onToggleDone: (UUID) -> Void
    let onBeginEdit: (UUID) -> Void
    let onCommitEdit: (UUID, String) -> Void
    let onCancelEdit: () -> Void
    let onDelete: (UUID) -> Void
    let onUndoDelete: (UUID) -> Void
    let onToggleOldSection: () -> Void
    let onClose: () -> Void

    // 저장 프로퍼티는 위 계약이 전부다(포커스 상태는 TodoBoardDraftField 가 들고 있다).
    // private 저장 프로퍼티를 여기 두면 메모리와이즈 이니셜라이저가 private 로 내려앉아,
    // 보드를 띄우는 컨트롤러(다른 파일)가 이 뷰를 만들지 못한다.
    private static let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PanelDivider().padding(.vertical, 8)
            draftRow
            list.padding(.top, 6)
            footer
        }
        .padding(12)
        // 크기는 보드를 띄우는 쪽(패널)이 정한다. 여기서 300×400을 박으면 크기 상수가 두 파일로 갈라진다.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(boardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    /// 블러 → 패널색 순서가 핵심이다. 블러만 쓰면 밝은 바탕화면 위에서 흰 글자가 그대로 사라지고,
    /// 불투명하게 덮으면 '떠 있는 쪽지'라는 정체성이 사라진다. 72%가 두 요구를 동시에 만족한 값이다.
    private var boardBackground: some View {
        ZStack {
            VisualEffectBackground()
            CheckTheme.panel.opacity(0.72)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(TodoBoardStrings.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            TodoBoardCloseButton(action: onClose)
        }
        .frame(height: 24)
    }

    private var draftRow: some View {
        TodoBoardDraftField(
            draft: $draft,
            // 편집 중인 행이 있는 채로 열렸다면(보드 재열기 등) 그쪽 포커스를 빼앗지 않는다.
            autoFocuses: editingID == nil,
            onSubmit: onSubmitDraft
        )
    }

    /// 목록은 스크롤 영역 안에 들어간다. 스크롤 밖으로 넘치는 만큼은 ImageRenderer 가 그리지 못하므로
    /// 그림으로 확인해야 할 알맹이는 TodoBoardRowStack 으로 빼 놨다(테스트는 그쪽을 직접 그린다).
    private var list: some View {
        ScrollView(.vertical, showsIndicators: true) {
            TodoBoardRowStack(
                items: items,
                oldItems: oldItems,
                todayKey: todayKey,
                isOldSectionExpanded: isOldSectionExpanded,
                editingID: editingID,
                pendingDeleteID: pendingDeleteID,
                onToggleDone: onToggleDone,
                onBeginEdit: onBeginEdit,
                onCommitEdit: onCommitEdit,
                onCancelEdit: onCancelEdit,
                onDelete: onDelete,
                onUndoDelete: onUndoDelete,
                onToggleOldSection: onToggleOldSection
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        Text(TodoBoardStrings.footer)
            .font(.caption2)
            .foregroundStyle(CheckTheme.secondaryText.opacity(0.75))
            .lineLimit(1)
            .padding(.top, 6)
    }
}

// MARK: - 목록 본문

/// 스크롤 영역 안에 들어가는 목록 본문(활성 행 + 빈 상태 + 오래된 항목 접기). 보드에서 떼어 낸 이유는
/// ImageRenderer 가 ScrollView 안쪽을 그리지 못하기 때문이다 — 스크롤을 벗기고 이 뷰만 그리면
/// 행 배치·말줄임·배지를 그림으로 확인할 수 있다(CheckMenuView 의 clipsOverflowInsteadOfScroll 과 같은 목적).
struct TodoBoardRowStack: View {
    let items: [TodoItem]
    let oldItems: [TodoItem]
    let todayKey: String
    let isOldSectionExpanded: Bool
    let editingID: UUID?
    let pendingDeleteID: UUID?
    let onToggleDone: (UUID) -> Void
    let onBeginEdit: (UUID) -> Void
    let onCommitEdit: (UUID, String) -> Void
    let onCancelEdit: () -> Void
    let onDelete: (UUID) -> Void
    let onUndoDelete: (UUID) -> Void
    let onToggleOldSection: () -> Void
    /// 스냅샷 전용: hover 로만 뜨는 ✕ 를 모든 행에 강제로 그린다. 앱에서는 항상 false.
    var previewHovering: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if items.isEmpty {
                // oldItems 가 있어도 빈 상태를 보인다 — '오늘 할 일'이 비었다는 건 사실이고,
                // 아래 접힌 영역은 오늘의 목록이 아니라 따로 모아 둔 것이다.
                emptyState
            } else {
                ForEach(items) { item in
                    row(item)
                }
            }
            if !oldItems.isEmpty {
                oldSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ item: TodoItem) -> some View {
        TodoBoardRowView(
            item: item,
            todayKey: todayKey,
            isEditing: editingID == item.id,
            isPendingDelete: pendingDeleteID == item.id,
            onToggleDone: onToggleDone,
            onBeginEdit: onBeginEdit,
            onCommitEdit: onCommitEdit,
            onCancelEdit: onCancelEdit,
            onDelete: onDelete,
            onUndoDelete: onUndoDelete,
            previewHovering: previewHovering
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TodoBoardStrings.emptyTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            Text(TodoBoardStrings.emptyHint)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    /// 7일 넘게 끌고 온 미완료를 조용히 모아 두는 자리. 지우거나 옮기지 않고 접기만 하는 이유는
    /// 사용자가 자동 삭제·자동 이동을 명시적으로 뺐기 때문이다 — 목록에서 시야만 덜어 준다.
    private var oldSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            PanelDivider().padding(.vertical, 4)
            Button(action: onToggleOldSection) {
                HStack(spacing: 6) {
                    Image(systemName: isOldSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text(TodoBoardStrings.oldSection(count: oldItems.count))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TodoBoardStrings.oldSection(count: oldItems.count))
            if isOldSectionExpanded {
                ForEach(oldItems) { item in
                    row(item)
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - 입력 행

/// 새 할 일 입력 행(32pt). 보드 본체에서 떼어 낸 이유는 포커스 상태 때문이다 — @FocusState 같은 private
/// 저장 프로퍼티가 CheckTodoBoardView 안에 있으면 그쪽 메모리와이즈 이니셜라이저 접근 수준이 흔들린다.
struct TodoBoardDraftField: View {
    @Binding var draft: String
    /// 보드가 열리는 순간 커서를 여기에 둘지. 열자마자 바로 적을 수 있어야 캐릭터를 누른 흐름이 끊기지 않는다.
    let autoFocuses: Bool
    let onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                // 플레이스홀더를 직접 깐다(CredentialField 와 같은 방식) — 기본 TextField 플레이스홀더는
                // 이 팔레트에서 너무 밝게 나와 이미 입력된 글자처럼 보인다.
                if draft.isEmpty {
                    Text(TodoBoardStrings.placeholder)
                        .font(.subheadline)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(CheckTheme.primaryText)
                    .tint(CheckTheme.accent)
                    .lineLimit(1)
                    .focused($focused)
                    .accessibilityLabel(TodoBoardStrings.placeholder)
                    .onSubmit(onSubmit)
            }
            // 카운터는 90자부터만 나타난다. 늘 떠 있으면 글자 수를 세는 도구처럼 보여 짧게 쓰라는 압박이 된다.
            if let counter = TodoDraftInput.counterText(draft) {
                Text(counter)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CheckTheme.fieldFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CheckTheme.border, lineWidth: 1)
                )
        )
        .onChange(of: draft) { previous, next in
            let accepted = TodoDraftInput.accepted(current: previous, proposed: next)
            // != 가드 없이 매번 되쓰면 한글 IME 조합 중간 상태에서 대입 루프가 돈다(CredentialField 와 같은 이유).
            if accepted != next { draft = accepted }
        }
        .onAppear {
            if autoFocuses { focused = true }
        }
    }
}

// MARK: - 헤더 닫기 버튼

/// 헤더 전용 닫기 버튼. IconButton 을 쓰지 않은 이유는 그쪽 히트영역이 27pt 라 24pt 헤더를 위아래로 밀어
/// 구분선까지 겹치기 때문이다. 생김새(원형 호버 배경 + secondaryText)는 IconButton 과 맞춘다.
struct TodoBoardCloseButton: View {
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? CheckTheme.primaryText : CheckTheme.secondaryText)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.14 : 0.06)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(TodoBoardStrings.close)
        .accessibilityLabel(TodoBoardStrings.close)
    }
}

// MARK: - 항목 행

/// 할 일 한 줄. 세 모습(평소 / 편집 중 / 삭제 대기)이 **같은 높이**를 쓰도록 숫자를 맞춰 놨다 —
/// 상태가 바뀔 때마다 행이 커졌다 작아지면 아래 행들이 밀려 다음 클릭 목표가 손끝에서 도망간다.
/// 내부 치수: 세로 패딩 6 + (체크 16 / 편집 필드 18 / 되돌리기 버튼 22) ≤ minHeight 34.
struct TodoBoardRowView: View {
    let item: TodoItem
    let todayKey: String
    let isEditing: Bool
    let isPendingDelete: Bool
    let onToggleDone: (UUID) -> Void
    let onBeginEdit: (UUID) -> Void
    let onCommitEdit: (UUID, String) -> Void
    let onCancelEdit: () -> Void
    let onDelete: (UUID) -> Void
    let onUndoDelete: (UUID) -> Void
    /// 스냅샷 전용: 마우스 없이도 hover ✕ 를 그린다(ImageRenderer 엔 포인터가 없다). 앱에서는 항상 false.
    var previewHovering: Bool = false

    static let minHeight: CGFloat = 34

    /// 완료한 줄의 글자색. secondaryText(0.68)보다 더 흐리다 — 남아 있되 시선을 끌지 않는 게 목적이라
    /// 미완료(0.94)와 두 단계 벌려 놨다.
    private static let doneText = Color.white.opacity(0.42)

    @State private var hovering = false

    var body: some View {
        Group {
            if isPendingDelete {
                pendingDeleteBody
            } else {
                normalBody
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.minHeight, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var normalBody: some View {
        HStack(alignment: .top, spacing: 8) {
            checkButton
            if let badge = carryBadge {
                carryBadgeView(badge)
            }
            if isEditing {
                // 편집 필드는 남는 폭을 전부 먹는다. 여기에 Spacer 를 같이 두면 둘 다 '늘어나는 뷰'라
                // HStack 이 남은 폭을 반씩 나눠 주고, 필드가 행의 절반으로 쪼그라든다.
                TodoBoardTitleEditor(
                    initialTitle: item.title,
                    onCommit: { onCommitEdit(item.id, $0) },
                    onCancel: onCancelEdit
                )
            } else {
                titleText
                Spacer(minLength: 4)
            }
            deleteButton
        }
        .padding(.vertical, 6)
    }

    /// 삭제 직후 5초간 그 자리에 남는 모습. 행이 즉시 사라지면 실수로 지운 걸 되돌릴 자리 자체가 없어진다.
    private var pendingDeleteBody: some View {
        HStack(spacing: 8) {
            Text(TodoBoardStrings.deleted)
                .font(.subheadline)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                onUndoDelete(item.id)
            } label: {
                Text(TodoBoardStrings.undo)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.accent)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(CheckTheme.accent.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(CheckTheme.accent.opacity(0.35), lineWidth: 1)
                            )
                    )
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TodoBoardStrings.undo)
        }
        .padding(.vertical, 6)
    }

    private var checkButton: some View {
        Button {
            onToggleDone(item.id)
        } label: {
            ZStack {
                Circle()
                    .stroke(
                        item.isDone ? CheckTheme.working.opacity(0.75) : Color.white.opacity(0.32),
                        lineWidth: 1.5
                    )
                if item.isDone {
                    Circle().fill(CheckTheme.working.opacity(0.20))
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(CheckTheme.working)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(item.isDone ? TodoBoardStrings.markUndone : TodoBoardStrings.markDone)
        .accessibilityLabel(item.isDone ? TodoBoardStrings.markUndone : TodoBoardStrings.markDone)
    }

    private var titleText: some View {
        Text(item.title)
            .font(.subheadline)
            .foregroundStyle(item.isDone ? Self.doneText : CheckTheme.primaryText)
            .strikethrough(item.isDone, color: Self.doneText)
            .lineLimit(2)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            // 체크 원(16pt)의 중심과 첫 줄 글자의 중심을 맞추는 1pt. 이게 없으면 원이 글자보다 위로 뜬다.
            .padding(.top, 1)
            // 더블클릭만 편집으로 들어간다. 한 번 클릭으로 열리면 목록을 훑다가 눌린 손짓이 전부
            // 편집 모드가 되고, 그 상태에서 다음 줄을 누르면 방금 연 편집이 소리 없이 닫힌다.
            .onTapGesture(count: 2) { onBeginEdit(item.id) }
    }

    /// 이월 배지 문구. 완료한 항목에는 붙이지 않는다 — 배지는 '아직 안 끝냈다'는 신호라,
    /// 끝낸 줄에 남으면 이미 한 일을 두고 잔소리하는 것처럼 읽힌다.
    private var carryBadge: String? {
        guard !item.isDone else { return nil }
        let days = TodoRules.carriedDays(originDayKey: item.originDayKey, todayKey: todayKey)
        return TodoRules.carryBadge(days: days)
    }

    /// 무채색 캡슐. 빨강·주황 같은 경고색은 미룬 일을 실패로 낙인찍어서 보드를 열기 싫게 만든다.
    private func carryBadgeView(_ badge: String) -> some View {
        Text(badge)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(CheckTheme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.10)))
            .fixedSize()
            .accessibilityLabel("\(badge)부터 이월됨")
    }

    private var deleteButton: some View {
        Button {
            onDelete(item.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 자리는 늘 잡아 두고 보임 여부만 opacity 로 바꾼다. 마우스가 들어올 때 ✕ 가 '생기면' 제목 폭이
        // 그만큼 줄어 글자가 다시 흐르고, 그 리플로우가 방금 겨눈 클릭 목표를 옆으로 밀어낸다.
        .opacity(isDeleteVisible ? 1 : 0)
        // 보이지 않아도 접근성 트리에는 남긴다 — hover 로만 뜨는 버튼을 AX 에서까지 감추면
        // 포인터를 못 쓰는 사용자에게는 삭제 경로가 아예 없어진다.
        .help(TodoBoardStrings.deleteItem)
        .accessibilityLabel(TodoBoardStrings.deleteItem)
    }

    private var isDeleteVisible: Bool {
        hovering || previewHovering
    }
}

// MARK: - 인라인 제목 편집

/// 제목 자리에 그대로 뜨는 편집 필드. 편집 중 텍스트를 **자기 안에** 들고 있는 이유: 중간 입력이 store 로
/// 새어 나가면 Esc 로 되돌릴 원본이 이미 덮어써진 뒤다. 부모는 커밋된 값 또는 취소만 받는다.
/// 높이 18은 행이 평소(체크 16 + 여백)와 같은 34pt 로 유지되도록 고른 값이다.
struct TodoBoardTitleEditor: View {
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(initialTitle: String, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self._text = State(initialValue: initialTitle)
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(CheckTheme.primaryText)
            .tint(CheckTheme.accent)
            .lineLimit(1)
            .focused($focused)
            .accessibilityLabel(TodoBoardStrings.editTitle)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(CheckTheme.fieldFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1)
                    )
            )
            .onSubmit { onCommit(text) }
            // Esc 취소. onExitCommand 는 cancelOperation 을 여기서 삼켜, 같은 키가 패널까지 올라가
            // 보드째로 닫히는 일을 막는다.
            .onExitCommand(perform: onCancel)
            .onChange(of: text) { previous, next in
                // 입력 행과 같은 제한을 그대로 건다. 편집으로 들어오면 100자를 넘길 수 있다면
                // '막는다'는 규칙이 경로 하나로 우회된다.
                let accepted = TodoDraftInput.accepted(current: previous, proposed: next)
                if accepted != next { text = accepted }
            }
            .onAppear {
                // 더블클릭한 순간 바로 고칠 수 있어야 한다 — 한 번 더 클릭해서 커서를 넣게 하면 인라인 편집의 의미가 없다.
                focused = true
            }
    }
}
