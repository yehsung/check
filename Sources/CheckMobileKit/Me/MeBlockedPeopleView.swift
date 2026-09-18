#if os(iOS)
import CheckCore
import SwiftUI

/// 나 → 설정 → **차단한 사람**(앱스토어 심사 지침 1.2 — 차단은 되돌릴 수 있어야 한다).
///
/// 목록·해제는 메시지 스토어가 쥔다(`MessagesStore` + `MessagesBlockStore.swift`) — 차단은 메시지 관계라 같은 사실을
/// 두 스토어가 나눠 가지면 한쪽이 낡는다. 이 화면은 그 값을 그리고 [차단 해제]만 부른다.
///
/// 서버가 아직 차단 RPC 를 모르면(앱이 db push 보다 먼저 나간 창) "고장"이 아니라 **"아직"** 이라고 말한다.
struct MeBlockedPeopleView: View {
    /// 앱 모델이 스토어를 모두 만든 뒤 채우는 약참조(`context.links.messages`). 이론상 nil 이 될 수 없지만,
    /// nil 이면 빈 상태를 그린다 — 화면이 죽지 않게.
    let messages: MessagesStore?

    @State private var pendingUnblock: BlockedUser?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                Text(MessagesBlockText.blockedListLede)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                content
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, MobileTheme.rowSpacing)
        }
        .refreshable { messages?.loadBlocks(force: true) }
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(MessagesBlockText.blockedListTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { messages?.blockedListDidAppear() }
        // 차단 해제도 확인을 지난다 — 목록에서 손가락이 스쳐 풀리면 사용자는 그 사실을 영영 모른다.
        .sheet(item: $pendingUnblock) { person in
            AingConfirmSheet(
                title: MessagesBlockText.unblockConfirmTitle(person.name),
                message: MessagesBlockText.unblockConfirmMessage,
                confirmTitle: MessagesBlockText.unblockConfirm,
                cancelTitle: MessagesBlockText.blockCancel,
                onConfirm: {
                    pendingUnblock = nil
                    messages?.unblock(person.userID)
                },
                onCancel: { pendingUnblock = nil }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if let store = messages {
            if let notice = store.blockedListNotice {
                InlineNotice(text: notice, kind: .error)
            }
            if store.blocksServerNotReady {
                InlineNotice(text: MessagesBlockText.serverNotReady, kind: .info)
            }
            if store.blockedPeople.isEmpty {
                emptyContent(store)
            } else {
                InsetGroup {
                    ForEach(Array(store.blockedPeople.enumerated()), id: \.element.id) { index, person in
                        row(store: store, person: person, isLast: index == store.blockedPeople.count - 1)
                    }
                }
            }
        } else {
            AingCard {
                EmptyStateView(systemImage: "nosign", title: MessagesBlockText.blockedEmptyTitle, message: MessagesBlockText.blockedEmptyMessage)
            }
        }
    }

    @ViewBuilder
    private func emptyContent(_ store: MessagesStore) -> some View {
        AingCard {
            if store.blocksLoading, !store.blocksLoaded {
                LoadingRow()
            } else if store.blocksFailed, !store.blocksLoaded {
                LoadFailureRow(MessagesBlockText.blockedListFailed, isRetrying: store.blocksLoading) {
                    store.loadBlocks(force: true)
                }
            } else {
                EmptyStateView(
                    systemImage: "nosign",
                    title: MessagesBlockText.blockedEmptyTitle,
                    message: MessagesBlockText.blockedEmptyMessage
                )
            }
        }
    }

    /// 한 줄: 아바타 · 이름 · 차단한 시각 · [차단 해제](틴트 · 작게).
    private func row(store: MessagesStore, person: BlockedUser, isLast: Bool) -> some View {
        let isUnblocking = store.unblockingUserIDs.contains(person.userID)
        return GroupRow(divider: isLast ? .none : .inset(MeBlockedPeopleView.dividerLeading), minHeight: MobileTheme.rowHeightTwoLine) {
            PersonAvatar(name: person.name, status: nil, url: person.avatarURL, size: MeBlockedPeopleView.avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(MobileTheme.rowTitle)
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                if let at = person.blockedAt {
                    Text(MessagesBlockText.blockedAtLine(at, now: store.context.clock.now()))
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: MobileTheme.space2)
            AingButton(MessagesBlockText.unblockAction, kind: .tinted, size: .sm, isBusy: isUnblocking) {
                pendingUnblock = person
            }
        }
        .accessibilityElement(children: .combine)
    }

    static let avatarSize: CGFloat = 40
    /// 구분선 시작(카드 왼쪽에서) = 안쪽 여백 16 + 아바타 40 + 사이 12 — 사람 줄 공통 규칙.
    static let dividerLeading: CGFloat = MobileTheme.cardPadding + avatarSize + 12
}
#endif
