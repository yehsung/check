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
        Section {
            inputRow
            if rows.main.isEmpty && rows.old.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NowText.todoEmptyTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MobileTheme.primaryText)
                    Text(NowText.todoEmptyHint)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.secondaryText)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            ForEach(rows.main) { row in
                todoRow(row)
            }
            if !rows.old.isEmpty {
                DisclosureGroup(isExpanded: $isOldExpanded) {
                    ForEach(rows.old) { row in
                        todoRow(row)
                    }
                } label: {
                    Text(NowText.todoOldSection(count: rows.old.count))
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.secondaryText)
                }
                .tint(MobileTheme.secondaryText)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(NowText.todoTitle)
                    .font(.headline)
                    .foregroundStyle(MobileTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if remaining > 0 {
                    Text(NowText.todoRemaining(count: remaining))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.secondaryText)
                }
            }
            .textCase(nil)
        } footer: {
            Text(NowText.todoFooter)
                .font(.footnote)
                .foregroundStyle(MobileTheme.secondaryText)
        }
        .listRowBackground(MobileTheme.card)
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

    private var inputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(store.canEditTodos ? MobileTheme.accent : MobileTheme.secondaryText)
                .accessibilityHidden(true)
            TextField(NowText.todoPlaceholder, text: $draft)
                .font(.body)
                .foregroundStyle(MobileTheme.primaryText)
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
                    .foregroundStyle(draft.count >= TodoRules.maxTitleLength ? MobileTheme.pending : MobileTheme.secondaryText)
                    .fixedSize()
            }
            if !TodoRules.normalizedTitle(draft).isEmpty {
                Button(NowText.todoAdd, action: submitDraft)
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.accent)
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    private func submitDraft() {
        guard store.addTodo(draft) else { return }
        draft = ""
        // 연달아 적을 수 있게 입력칸에 남는다.
        focus = .draft
    }

    private func todoRow(_ row: NowTodoRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                store.toggleTodo(row.id)
            } label: {
                Image(systemName: row.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.isDone ? MobileTheme.working : MobileTheme.secondaryText)
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(row.isDone ? NowText.todoMarkUndone : NowText.todoMarkDone))
            .accessibilityValue(Text(row.title))

            if store.editingTodoID == row.id {
                TextField(NowText.todoEditPlaceholder, text: $editingText)
                    .font(.body)
                    .foregroundStyle(MobileTheme.primaryText)
                    .focused($focus, equals: .edit(row.id))
                    .submitLabel(.done)
                    .onSubmit { store.commitEditing(row.id, title: editingText) }
                    .onChange(of: editingText) { old, new in
                        let accepted = NowTodoDraft.accepted(current: old, proposed: new)
                        if accepted != new { editingText = accepted }
                    }
            } else {
                Text(row.title)
                    .font(.body)
                    .strikethrough(row.isDone)
                    .foregroundStyle(row.isDone ? MobileTheme.secondaryText : MobileTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing(row) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text(NowText.todoEdit))
            }
            if let badge = row.carryBadge {
                NowChip(text: badge, tint: MobileTheme.pending)
            }
        }
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
                    .foregroundStyle(MobileTheme.secondaryText)
                    .accessibilityHidden(true)
                Text(NowText.todoDeleted)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.primaryText)
                Spacer(minLength: 8)
                Button(NowText.todoUndo) {
                    store.undoDelete()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(MobileTheme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MobileTheme.cardElevated)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MobileTheme.separator, lineWidth: 1)
            )
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
                                    .foregroundStyle(MobileTheme.secondaryText)
                                Text("\(hours)시간")
                                    .font(MobileTheme.number(.title2, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(MobileTheme.primaryText)
                            }
                        }
                        .accessibilityValue(Text("\(hours)시간"))
                    }
                    InlineNotice(text: NowText.goalExplain, kind: .info)
                    if let notice = store.goalNotice {
                        InlineNotice(text: notice, kind: .error)
                    }
                    Button {
                        Task { @MainActor in
                            if await store.saveGoal(hours: hours) { dismiss() }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if store.isSavingGoal { ProgressView().tint(MobileTheme.onAccent) }
                            Text(NowText.goalSave)
                        }
                    }
                    .buttonStyle(AingPrimaryButtonStyle())
                    .disabled(store.isSavingGoal)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.vertical, MobileTheme.rowSpacing)
            }
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(NowText.goalSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NowText.close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { store.clearGoalNotice() }
    }
}
#endif
