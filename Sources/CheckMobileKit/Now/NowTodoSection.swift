#if os(iOS)
import CheckCore
import SwiftUI

/// 오늘 할 일(SPEC-ios §3.2): 추가 입력칸(100자, 90자부터 카운터) · 체크 · 눌러서 수정 · 밀어서 삭제(5초 되돌리기 토스트) · 이월 배지.
/// 규칙은 전부 코어(`TodoRules` · `TodoListStore`)와 스토어가 쥐고, 이 뷰는 입력 상태(초안·편집 글자·포커스)만 든다.
struct NowTodoSection: View {
    let store: NowStore
    @State private var draft = ""
    @State private var editingText = ""
    @State private var isOldExpanded = false
    @FocusState private var focus: Field?

    enum Field: Hashable {
        case draft
        case edit(UUID)
    }

    var body: some View {
        let rows = store.todoRows()
        let remaining = store.remainingTodoCount
        // 행 자리(카드 조각 — 다른 탭 `AingCard` 와 같은 모양): 입력 · (빈 안내) · 오늘 줄… · (오래된 항목 머리 · 펼친 줄…).
        let isEmpty = rows.main.isEmpty && rows.old.isEmpty
        let mainStart = isEmpty ? 2 : 1
        let oldHeader = mainStart + rows.main.count
        let rowCount = oldHeader + (rows.old.isEmpty ? 0 : 1 + (isOldExpanded ? rows.old.count : 0))
        Section {
            inputRow
                .cardSegmentRow(.of(index: 0, count: rowCount), dividerLeading: Self.textLeading)
            if isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NowText.todoEmptyTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MobileTheme.label)
                    Text(NowText.todoEmptyHint)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .cardSegmentRow(.of(index: 1, count: rowCount))
            }
            ForEach(Array(rows.main.enumerated()), id: \.element.id) { offset, row in
                // 오래된 항목 머리 바로 위 줄의 구분선은 왼쪽 끝(16)부터 — 머리 줄은 체크가 없는 줄이다(시안 `--inset:16px`).
                let isLastBeforeOld = offset == rows.main.count - 1 && !rows.old.isEmpty
                todoRow(row)
                    .cardSegmentRow(
                        .of(index: mainStart + offset, count: rowCount),
                        padding: Self.todoRowPadding,
                        dividerLeading: isLastBeforeOld ? MobileTheme.cardPadding : Self.textLeading
                    )
            }
            if !rows.old.isEmpty {
                // 시스템 DisclosureGroup 대신 머리 줄 + 펼친 줄 — 펼친 줄도 같은 카드 조각으로 이어 그리려면 행 자리를 알아야 한다.
                oldHeaderRow(count: rows.old.count)
                    .cardSegmentRow(
                        .of(index: oldHeader, count: rowCount),
                        padding: EdgeInsets(top: 0, leading: MobileTheme.cardPadding, bottom: 0, trailing: MobileTheme.cardPadding),
                        dividerLeading: MobileTheme.cardPadding
                    )
                if isOldExpanded {
                    ForEach(Array(rows.old.enumerated()), id: \.element.id) { offset, row in
                        todoRow(row)
                            .cardSegmentRow(
                                .of(index: oldHeader + 1 + offset, count: rowCount),
                                padding: Self.todoRowPadding,
                                dividerLeading: Self.textLeading
                            )
                    }
                }
            }
        } header: {
            NowSectionHeader(title: NowText.todoTitle, trailing: remaining > 0 ? NowText.todoRemaining(count: remaining) : nil)
        }
        .onChange(of: focus) { old, new in
            // 고치던 줄에서 포커스가 떠나면(다른 곳 탭 · 키보드 내림) 확정한다 — iOS 목록 편집의 관례.
            if case .edit(let id)? = old, new != .edit(id), store.editingTodoID == id {
                store.commitEditing(id, title: editingText)
            }
        }
        .onChange(of: store.editingTodoID) { _, id in
            if id == nil, case .edit? = focus { focus = nil }
        }
        #if DEBUG
        .task {
            let stages = NowDemoStage.stages()
            guard store.context.isDemo, stages.contains("edit") || stages.contains("old"),
                  await NowDemoStage.waitForData(store) else { return }
            if stages.contains("old") { isOldExpanded = true }
            if stages.contains("edit"), let row = store.todoRows().main.dropFirst().first { beginEditing(row) }
        }
        #endif
    }

    /// 체크 원(22) 오른쪽 글자 시작점 = 구분선 시작점(16 + 22 + 12 — 시안 `--inset:50px`).
    static let textLeading: CGFloat = 50
    /// 할 일 줄 여백(최소 높이 46 — 시안 `.b-todo`).
    static let todoRowPadding = EdgeInsets(top: 10, leading: MobileTheme.cardPadding, bottom: 10, trailing: MobileTheme.cardPadding)

    private var inputRow: some View {
        HStack(spacing: 12) {
            NowAddGlyph(isEnabled: store.canEditTodos)
            // 자리표시는 3단 글자(회색) — 파랑이면 미리 채운 값이나 링크처럼 보인다.
            TextField(text: $draft, prompt: Text(NowText.todoPlaceholder).foregroundStyle(MobileTheme.label3Text)) {
                Text(NowText.todoPlaceholder)
            }
                .font(.callout)
                .foregroundStyle(MobileTheme.label)
                .focused($focus, equals: .draft)
                .submitLabel(.done)
                .onSubmit(submitDraft)
                .onChange(of: draft) { old, new in
                    let accepted = NowTodoDraft.accepted(current: old, proposed: new)
                    if accepted != new { draft = accepted }
                }
                .disabled(!store.canEditTodos)
            if let counter = NowTodoDraft.counterText(draft) {
                Text(counter)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(draft.count >= TodoRules.maxTitleLength ? MobileTheme.pending : MobileTheme.label2)
                    .fixedSize()
            }
            if !TodoRules.normalizedTitle(draft).isEmpty {
                Button(NowText.todoAdd, action: submitDraft)
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.accent)
                    .frame(minHeight: 44)
                    .padding(.vertical, -10)
                    .fixedSize()
            }
        }
        .frame(minHeight: 24)
    }

    /// "오래된 항목 · 1 ›" 머리 줄(누르면 펼치고 접는다). 누르는 칸은 줄 전체(44pt 이상).
    private func oldHeaderRow(count: Int) -> some View {
        Button {
            withAnimation(.snappy) { isOldExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(NowText.todoOldTitle)
                    .font(.callout)
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(MobileTheme.label2)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.label3)
                    .rotationEffect(.degrees(isOldExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(NowText.todoOldSection(count: count)))
        .accessibilityValue(Text(isOldExpanded ? "펼침" : "접힘"))
    }

    private func submitDraft() {
        guard store.addTodo(draft) else { return }
        draft = ""
        // 연달아 적을 수 있게 입력칸에 남는다.
        focus = .draft
    }

    private func todoRow(_ row: NowTodoRow) -> some View {
        // 체크 칸은 44pt(원 22pt)이고 제목과 붙여 둔다 — 작은 칸 + 넓은 틈이면 체크를 조금 빗맞은 손가락이 제목의
        // "눌러서 수정"에 떨어져 키보드가 떴다. 누르는 칸만 키우고 자리(레이아웃)는 원 크기를 지킨다: 넘치는 만큼은 줄 여백 쪽으로 내민다.
        HStack(alignment: .center, spacing: 12) {
            NowCheckButton(isOn: row.isDone) {
                store.toggleTodo(row.id)
            }
            .accessibilityLabel(Text(row.isDone ? NowText.todoMarkUndone : NowText.todoMarkDone))
            .accessibilityValue(Text(row.title))

            if store.editingTodoID == row.id {
                TextField(NowText.todoEditPlaceholder, text: $editingText)
                    .font(.callout)
                    .foregroundStyle(MobileTheme.label)
                    .focused($focus, equals: .edit(row.id))
                    .submitLabel(.done)
                    .onSubmit { store.commitEditing(row.id, title: editingText) }
                    .onChange(of: editingText) { old, new in
                        let accepted = NowTodoDraft.accepted(current: old, proposed: new)
                        if accepted != new { editingText = accepted }
                    }
            } else {
                Text(row.title)
                    .font(.callout)
                    .strikethrough(row.isDone, color: MobileTheme.label3Text)
                    .foregroundStyle(row.isDone ? MobileTheme.label3Text : MobileTheme.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing(row) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text(NowText.todoEdit))
            }
            if let badge = row.carryBadge {
                // 이월 배지는 회색 칩(앰버는 연결 끊김 전용 — 시안 B 01).
                AingChip(text: badge, tint: MobileTheme.label2, background: MobileTheme.fill)
            }
        }
        .frame(minHeight: 26)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                store.deleteTodo(row.id)
            } label: {
                Label(NowText.todoDelete, systemImage: "trash")
            }
        }
        .accessibilityAction(named: Text(NowText.todoDelete)) {
            store.deleteTodo(row.id)
        }
    }

    private func beginEditing(_ row: NowTodoRow) {
        guard store.canEditTodos else { return }
        if let current = store.editingTodoID, current != row.id {
            store.commitEditing(current, title: editingText)
        }
        editingText = row.title
        store.beginEditing(row.id)
        Task { @MainActor in focus = .edit(row.id) }
    }
}

/// "삭제됨 · 되돌리기" 토스트(5초 — 스토어가 닫는다).
struct NowUndoToast: View {
    let store: NowStore

    var body: some View {
        if store.undoTodoID != nil {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .foregroundStyle(MobileTheme.label2)
                    .accessibilityHidden(true)
                Text(NowText.todoDeleted)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                Spacer(minLength: 8)
                // 5초만 뜨는 토스트라 누르기 쉬워야 한다 — 글자만이면 높이 20pt 안팎이었다. 칸을 44pt 로 키우고 토스트 위아래 여백을 그만큼 줄였다.
                Button {
                    store.undoDelete()
                } label: {
                    Text(NowText.todoUndo)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MobileTheme.accent)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .padding(.trailing, -12)
            }
            .padding(.leading, 18)
            .padding(.trailing, 18)
            .padding(.vertical, 4)
            .background(GlassBackground(shape: Capsule()))
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// 주간 목표 시트: 1~168시간 스테퍼 · 팀 전체 1인당 목표라는 안내 · 저장(성공하면 닫힘, 실패하면 문구와 함께 남음).
struct NowGoalSheet: View {
    let store: NowStore
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Int

    init(store: NowStore) {
        self.store = store
        _hours = State(initialValue: min(NowStore.goalRange.upperBound, max(NowStore.goalRange.lowerBound, store.goalHours)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    AingCard {
                        Stepper(value: $hours, in: NowStore.goalRange) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NowText.goalStepperLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(MobileTheme.label2)
                                Text("\(hours)시간")
                                    .font(MobileTheme.number(.title2, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(MobileTheme.label)
                            }
                        }
                        .accessibilityValue(Text("\(hours)시간"))
                    }
                    InlineNotice(text: NowText.goalExplain, kind: .info)
                    if let notice = store.goalNotice {
                        InlineNotice(text: notice, kind: .error)
                    }
                    AingButton(NowText.goalSave, kind: .filled, size: .lg, fillsWidth: true, isBusy: store.isSavingGoal) {
                        Task { @MainActor in
                            if await store.saveGoal(hours: hours) { dismiss() }
                        }
                    }
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.vertical, MobileTheme.rowSpacing)
            }
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(NowText.goalSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            // 닫기는 왼쪽 위 ✕ 하나(공용 시트 머리 규칙).
            .sheetCloseButton { dismiss() }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { store.clearGoalNotice() }
    }
}
#endif

#if os(iOS)
/// 할 일 체크 원 크기(시안 22pt · 글자 크기를 따라 34pt 까지).
enum NowGlyphSide {
    static let base: CGFloat = 22
    static let maximum: CGFloat = 34
}

/// 할 일 체크 버튼: 보이는 원은 22pt(큰 글자에서 34pt 까지), 누르는 칸은 44pt — 넘치는 만큼은 줄 여백 쪽으로 내밀어 자리는 원 크기만 쓴다.
struct NowCheckButton: View {
    let isOn: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = NowGlyphSide.base

    var body: some View {
        let side = min(scaled, NowGlyphSide.maximum)
        let target = max(44, side)
        Button(action: action) {
            NowCheckCircle(isOn: isOn, side: side)
                .frame(width: target, height: target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(-(target - side) / 2)
    }
}

/// 할 일 추가 줄 앞 기호(체크 원과 같은 크기 · 같은 열).
struct NowAddGlyph: View {
    let isEnabled: Bool
    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = NowGlyphSide.base

    var body: some View {
        let side = min(scaled, NowGlyphSide.maximum)
        Image(systemName: "plus.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(isEnabled ? MobileTheme.accent : MobileTheme.label3)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// 할 일 체크 원(시안 `.b-check`): 빈 원은 3단 선(label3) · 끝낸 원은 파랑 채움 + 흰 체크. 초록 금지(색 뜻 — 초록은 근무 중·달성).
struct NowCheckCircle: View {
    let isOn: Bool
    let side: CGFloat

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(MobileTheme.accentFill)
                Image(systemName: "checkmark")
                    .font(.system(size: side * 0.55, weight: .bold))
                    .foregroundStyle(MobileTheme.onAccentFill)
            } else {
                Circle().strokeBorder(MobileTheme.label3, lineWidth: 1.8)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
#endif
