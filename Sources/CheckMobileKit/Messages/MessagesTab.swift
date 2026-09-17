#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 메시지 탭 화면(SPEC-ios §3.3). 목록 → 대화(경로 push) · 오른쪽 위 "새 대화" → 사람 찾기 시트.
///
/// - 경로는 `router.pathBinding(for: .messages)` 이고 원소는 `MessagesDestination` 이다.
/// - 딥링크(`aingcheck://message/<peer>` · 푸시 탭)는 `routeSerial` 이 바뀔 때마다 `consumePendingRoute(for: .messages)` 로 꺼내
///   그 대화를 쌓는다(라우터가 경로를 먼저 비운다). 사람 찾기 시트가 떠 있으면 닫는다.
struct MessagesTab: View {
    let store: MessagesStore
    @State private var showsNewConversation = false

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .messages)) {
            MessagesListView(
                store: store,
                onOpen: { peer in router.push(MessagesDestination.conversation(peerID: peer), on: .messages) },
                onNewConversation: { showsNewConversation = true }
            )
            .navigationTitle(AingTab.messages.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsNewConversation = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(Text("새 대화"))
                }
            }
            .navigationDestination(for: MessagesDestination.self) { destination in
                switch destination {
                case .conversation(let peerID):
                    MessagesConversationView(store: store, peerID: peerID)
                }
            }
        }
        .sheet(isPresented: $showsNewConversation) {
            MessagesNewConversationSheet(store: store) { peer in
                showsNewConversation = false
                router.push(MessagesDestination.conversation(peerID: peer), on: .messages)
            }
        }
        .onAppear {
            consumeRoute()
            #if DEBUG
            if MessagesDemoLaunch.opensNewConversation(isDemo: store.context.isDemo) { showsNewConversation = true }
            #endif
        }
        .onChange(of: router.routeSerial) { consumeRoute() }
    }

    private func consumeRoute() {
        let router = store.context.router
        guard let route = router.consumePendingRoute(for: .messages),
              let destinations = MessagesListRules.destinations(for: route)
        else { return }
        showsNewConversation = false
        for destination in destinations {
            router.push(destination, on: .messages)
        }
    }
}

// MARK: - 목록

/// 대화 목록: 상대 아바타 · 이름 · 마지막 문장 한 줄 · 상대 시각 · 안 읽음 점. 당겨서 새로고침.
struct MessagesListView: View {
    let store: MessagesStore
    let onOpen: (String) -> Void
    let onNewConversation: () -> Void

    var body: some View {
        let threads = store.threads
        let unread = store.unreadPeerIDs
        let now = store.context.clock.now()
        List {
            if store.historyFailed, !threads.isEmpty {
                InlineNotice(text: "새 메시지를 불러오지 못했어요. 당겨서 다시 시도해 주세요", kind: .error)
                    .cardListPlainRow()
            }
            if threads.isEmpty {
                emptyContent
                    .cardListPlainRow()
            } else {
                Section {
                    ForEach(Array(threads.enumerated()), id: \.element.id) { offset, thread in
                        Button {
                            onOpen(thread.peerUserID)
                        } label: {
                            MessagesThreadRow(thread: thread, isUnread: unread.contains(thread.peerUserID), now: now)
                        }
                        .buttonStyle(.plain)
                        // 카드 모양은 다른 탭의 `AingCard` 와 같게(반경 16 · 1px 테두리) — 시스템 절 모양을 쓰지 않는다.
                        .cardSegmentRow(.of(index: offset, count: threads.count), dividerLeading: MessagesThreadRow.dividerLeading)
                    }
                } footer: {
                    Text(MessageNoticeText.expiry)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.secondaryText)
                }
            }
        }
        // grouped(셀이 화면 폭) — 카드는 행이 `cardSegmentRow` 로 직접 그린다(insetGrouped 는 셀을 시스템 반경으로 잘랐다).
        .listStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(MobileTheme.background.ignoresSafeArea())
        .refreshable { await store.refreshNow() }
        .onAppear { store.listDidAppear() }
        .onDisappear { store.listDidDisappear() }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if store.historyFailed {
            AingCard {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "메시지를 불러오지 못했어요",
                    message: MobileLoadText.checkConnection,
                    actionTitle: MobileLoadText.retry,
                    action: { Task { await store.refreshNow() } }
                )
            }
        } else if !store.historyLoaded {
            AingCard { LoadingRow() }
        } else {
            AingCard {
                EmptyStateView(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "아직 주고받은 메시지가 없어요",
                    message: "\(MessageNoticeText.expiry). 새 대화로 먼저 말을 걸어 보세요",
                    actionTitle: "새 대화",
                    action: onNewConversation
                )
            }
        }
    }
}

/// 목록 한 줄.
struct MessagesThreadRow: View {
    /// 줄 사이 구분선이 시작하는 곳(카드 왼쪽에서) — 이름 글자 줄에 맞춘다(카드 안쪽 여백 16 + 아바타 48 + 사이 12).
    static let dividerLeading: CGFloat = MobileTheme.cardPadding + 48 + 12

    let thread: MessageThread
    let isUnread: Bool
    let now: Date

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 미리보기는 한 줄이 원칙이지만, 큰 글자에서는 두 줄까지 — 한 줄이면 네 글자 뒤 말줄임이 됐다(AX3 실측).
    private var previewLines: Int { dynamicTypeSize.isAccessibilitySize ? 2 : 1 }

    var body: some View {
        let last = thread.lastMessage
        HStack(alignment: .center, spacing: 12) {
            AvatarView(name: thread.peerName, url: thread.peerAvatarURL, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(thread.peerName)
                        .font(.headline)
                        .foregroundStyle(MobileTheme.primaryText)
                        .lineLimit(previewLines)
                    Spacer(minLength: 4)
                    if let last {
                        RelativeTimeText(last.createdAt, now: now)
                            .font(.caption)
                            .foregroundStyle(MobileTheme.secondaryText)
                    }
                }
                HStack(alignment: .center, spacing: 8) {
                    Text(last.map { MessagesListRules.preview($0.body) } ?? "")
                        .font(.subheadline.weight(isUnread ? .semibold : .regular))
                        .foregroundStyle(isUnread ? MobileTheme.primaryText : MobileTheme.secondaryText)
                        .lineLimit(previewLines)
                    Spacer(minLength: 4)
                    if isUnread {
                        Circle()
                            .fill(MobileTheme.accent)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [thread.peerName]
        if isUnread { parts.append("안 읽은 메시지 있음") }
        if let last = thread.lastMessage {
            parts.append((last.isMine ? "나: " : "") + MessagesListRules.preview(last.body))
            parts.append(MobileRelativeTime.text(for: last.createdAt, now: now))
        }
        return parts.joined(separator: ", ")
    }
}
#endif
