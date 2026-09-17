#if os(iOS)
import CheckCore
import SwiftUI

/// 새 대화 → 사람 찾기(`app_user_directory`, 이름·초성 검색, 근무 여부 표시). 고르면 시트를 닫고 그 사람과의 대화를 연다.
/// 근무 여부는 **정보일 뿐이다** — 메시지는 근무 밖에서도 주고받는다(v0.3.30 서버 규칙). 막는 것은 서버의 집중 모드뿐이다.
///
/// 모양(시안 B 부품 규칙): 닫기는 왼쪽 위 유리 ✕ 하나(`sheetCloseButton` — 시트 머리 통일) · "근무 중" / "근무 안 함" 두 그룹 ·
/// 한 줄 = 아바타(근무 중이면 초록 점) + 이름 + 센터 배지. 상태 글자·꺾쇠(›)를 두지 않는다 — 설정 목록처럼 보였다(비평 05).
struct MessagesNewConversationSheet: View {
    let store: MessagesStore
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let people = store.filteredDirectory(query: query)
        let working = people.filter(\.isWorking)
        let others = people.filter { !$0.isWorking }
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
                    .cardListPlainRow()
                } else if !store.directoryLoaded {
                    LoadingRow()
                        .cardSegmentRow(.single)
                } else if people.isEmpty {
                    EmptyStateView(
                        systemImage: "person.crop.circle.badge.questionmark",
                        title: query.isEmpty ? "대화할 사람이 아직 없어요" : "‘\(query)’ 이름을 찾지 못했어요",
                        message: query.isEmpty ? nil : "이름이나 초성(예: ㅎㄱ)으로 찾아보세요"
                    )
                    .cardListPlainRow()
                } else {
                    if !working.isEmpty {
                        group(title: "근무 중 \(working.count)", people: working, isFirst: true)
                    }
                    if !others.isEmpty {
                        group(title: "근무 안 함", people: others, isFirst: working.isEmpty)
                    }
                    Text("근무 중이 아니어도 메시지를 보낼 수 있어요")
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                        .cardListPlainRow(top: 8, bottom: 16)
                }
            }
            .listStyle(.grouped)
            .listSectionSpacing(0)
            // 검색칸과 첫 묶음 사이 빈 띠(약 60pt)를 걷는다(비평 05).
            .contentMargins(.top, 0, for: .scrollContent)
            // 묶음 머리 글자 줄이 기본 최소 44pt 로 부풀어 머리와 카드 사이가 벌어졌다 — 줄은 제 높이만.
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle("새 대화")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("이름 검색"))
            .sheetCloseButton { dismiss() }
            .refreshable { store.loadDirectory(force: true) }
        }
        .onAppear { store.loadDirectory() }
    }

    @ViewBuilder
    private func group(title: String, people: [PokeDirectoryEntry], isFirst: Bool) -> some View {
        Section {
            Text(title)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label2)
                .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                .accessibilityAddTraits(.isHeader)
                .cardListPlainRow(top: isFirst ? 2 : 14, bottom: 6)
            ForEach(Array(people.enumerated()), id: \.element.id) { offset, person in
                Button {
                    onSelect(person.userID)
                } label: {
                    MessagesPersonRow(person: person)
                }
                .buttonStyle(.plain)
                .cardSegmentRow(
                    .of(index: offset, count: people.count),
                    padding: EdgeInsets(top: 6, leading: MobileTheme.cardPadding, bottom: 6, trailing: MobileTheme.cardPadding),
                    dividerLeading: MessagesPersonRow.dividerLeading
                )
            }
        }
    }
}

/// 사람 한 줄: 아바타(근무 중이면 초록 점) · 이름 · 센터 배지.
struct MessagesPersonRow: View {
    static let avatarSize: CGFloat = 40
    /// 구분선 시작(카드 왼쪽에서) = 안쪽 여백 16 + 아바타 40 + 사이 12.
    static let dividerLeading: CGFloat = MobileTheme.cardPadding + avatarSize + 12

    let person: PokeDirectoryEntry

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatar(
                name: person.name,
                colorSeed: nil,
                status: person.isWorking ? .working : nil,
                url: person.avatarURL,
                size: Self.avatarSize
            )
            PersonName(person.name, center: CenterLabel.serverValue(forDisplay: person.center))
            Spacer(minLength: 8)
        }
        .frame(minHeight: MobileTheme.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([person.name, person.center.map { "\($0)센터" }, person.isWorking ? "근무 중" : "근무 안 함"]
            .compactMap { $0 }.joined(separator: ", ")))
        .accessibilityHint(Text("대화 열기"))
        .accessibilityAddTraits(.isButton)
    }
}
#endif
