#if os(iOS)
import CheckCore
import SwiftUI

/// 새 대화 → 사람 찾기(`app_user_directory`, 이름·초성 검색, 근무 여부 표시). 고르면 시트를 닫고 그 사람과의 대화를 연다.
/// 근무 여부는 **정보일 뿐이다** — 메시지는 근무 밖에서도 주고받는다(v0.3.30 서버 규칙). 막는 것은 서버의 집중 모드뿐이다.
struct MessagesNewConversationSheet: View {
    let store: MessagesStore
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let people = store.filteredDirectory(query: query)
        NavigationStack {
            List {
                if store.directoryFailed, store.directory.isEmpty {
                    AingCard {
                        EmptyStateView(
                            systemImage: "exclamationmark.triangle",
                            title: "사람 목록을 불러오지 못했어요",
                            message: MobileLoadText.checkConnection,
                            actionTitle: MobileLoadText.retry,
                            action: { store.loadDirectory(force: true) }
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if !store.directoryLoaded {
                    LoadingRow()
                        .listRowBackground(MobileTheme.surface)
                } else if people.isEmpty {
                    EmptyStateView(
                        systemImage: "person.crop.circle.badge.questionmark",
                        title: query.isEmpty ? "대화할 사람이 아직 없어요" : "‘\(query)’ 이름을 찾지 못했어요",
                        message: query.isEmpty ? nil : "이름이나 초성(예: ㅎㄱ)으로 찾아보세요"
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(people) { person in
                            Button {
                                onSelect(person.userID)
                            } label: {
                                MessagesPersonRow(person: person)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(MobileTheme.surface)
                            .listRowSeparatorTint(MobileTheme.separator)
                        }
                    } footer: {
                        Text("근무 중이 아니어도 메시지를 보낼 수 있어요")
                            .font(.footnote)
                            .foregroundStyle(MobileTheme.label2)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle("새 대화")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("이름 검색"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .refreshable { store.loadDirectory(force: true) }
        }
        .onAppear { store.loadDirectory() }
    }
}

/// 사람 한 줄: 아바타 · 이름 · 센터 · 근무 여부.
struct MessagesPersonRow: View {
    let person: PokeDirectoryEntry

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: person.name, url: person.avatarURL, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.headline)
                        .foregroundStyle(MobileTheme.label)
                        .lineLimit(1)
                    if let center = person.center {
                        Text(center)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MobileTheme.label2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(MobileTheme.fill))
                            .overlay(Capsule().stroke(MobileTheme.separator, lineWidth: 0.5))
                            .fixedSize()
                    }
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(person.isWorking ? MobileTheme.working : MobileTheme.offWork)
                        .frame(width: 8, height: 8)
                    Text(person.isWorking ? "근무 중" : "근무 안 함")
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MobileTheme.label2)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([person.name, person.center.map { "\($0)센터" }, person.isWorking ? "근무 중" : "근무 안 함"]
            .compactMap { $0 }.joined(separator: ", ")))
        .accessibilityHint(Text("대화 열기"))
        .accessibilityAddTraits(.isButton)
    }
}
#endif
