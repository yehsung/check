#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 메시지 탭 화면(SPEC-ios §3.3 · 시안 B 03). 목록 → 대화(경로 push) · 오른쪽 위 유리 원 "새 대화" → 사람 찾기 시트.
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
            .modifier(MessagesListSubtitle(text: MessagesListRules.subtitle(unreadCount: store.badgeCount)))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MessagesComposeToolbarButton { showsNewConversation = true }
                }
            }
            .navigationDestination(for: MessagesDestination.self) { destination in
                switch destination {
                case .conversation(let peerID):
                    MessagesConversationView(store: store, peerID: peerID)
                        .hidesTabBar(for: .conversation)
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

/// 큰 제목 아래 "안 읽은 메시지 3"(iOS 26 내비 부제). iOS 18 은 부제 자리가 없어 목록 첫 줄이 대신 말한다(`MessagesListView`).
/// 가지는 OS 판으로만 갈린다 — 숫자가 0 이 되어도 뷰 정체성이 바뀌지 않게 빈 글자를 넘긴다.
private struct MessagesListSubtitle: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationSubtitle(text ?? "")
        } else {
            content
        }
    }
}

/// 오른쪽 위 "새 대화". iOS 26 내비 막대는 도구 버튼을 스스로 유리 원으로 감싼다(유리를 겹치지 않게 기호만) · iOS 18 은 공용 유리 원.
private struct MessagesComposeToolbarButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MobileTheme.label)
            }
            .tint(MobileTheme.label)
            .accessibilityLabel(Text(MessagesListText.newConversation))
        } else {
            GlassCircleButton(systemImage: "square.and.pencil", accessibilityLabel: MessagesListText.newConversation, action: action)
        }
    }
}

enum MessagesListText {
    static let newConversation = "새 대화"
    static let workingTitle = "지금 근무 중"
    static let workingTrailing = "바로 말 걸기"
    static let nobodyWorking = "지금 근무 중인 사람이 없어요"
}

// MARK: - 목록

/// 대화 목록(시안 B 03): 한 그룹 안의 줄(상대 아바타 + 근무 점 · 이름 + 센터 · 시각 · 두 줄 미리보기 · 개수 배지) · 보관 안내 한 줄 ·
/// "지금 근무 중 · 바로 말 걸기" 가로 줄. 당겨서 새로고침.
struct MessagesListView: View {
    let store: MessagesStore
    let onOpen: (String) -> Void
    let onNewConversation: () -> Void

    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    var body: some View {
        let threads = store.threads
        let unread = store.unreadPeerIDs
        let counts = store.unreadCountsByPeer
        let now = store.context.clock.now()
        let presence = store.presenceBoard(now: now)
        let dividerLeading = MessagesThreadRow.dividerLeading(avatarSide: MobileAvatarScale.side(base: MessagesThreadRow.avatarBase, textScale: textScale))
        List {
            if #available(iOS 26.0, *) {
                EmptyView()
            } else {
                if let subtitle = MessagesListRules.subtitle(unreadCount: store.badgeCount) {
                    Text(subtitle)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label2)
                        .cardListPlainRow(top: 0, bottom: 4)
                }
            }
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
                        let isUnread = unread.contains(thread.peerUserID)
                        Button {
                            onOpen(thread.peerUserID)
                        } label: {
                            MessagesThreadRow(
                                thread: thread,
                                isUnread: isUnread,
                                countBadge: MessagesListRules.countBadge(isUnread: isUnread, count: counts[thread.peerUserID]),
                                presence: presence.peers[thread.peerUserID],
                                now: now
                            )
                        }
                        .buttonStyle(.plain)
                        // 한 그룹 안의 줄(시안 B) — 시스템 절 모양을 쓰지 않는다. 구분선은 이름 글자 시작점부터.
                        .cardSegmentRow(
                            .of(index: offset, count: threads.count),
                            padding: EdgeInsets(top: 12, leading: MobileTheme.cardPadding, bottom: 12, trailing: MobileTheme.cardPadding),
                            dividerLeading: dividerLeading
                        )
                    }
                } footer: {
                    MessagesExpiryNote(alignment: .leading)
                        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                        .padding(.top, 8)
                }
            }
            if presence.isKnown {
                Section {
                    SectionHeader(MessagesListText.workingTitle, trailing: .text(MessagesListText.workingTrailing), padded: true)
                        .cardListPlainRow(top: 0, bottom: 0)
                    MessagesWorkingStrip(people: presence.working, onOpen: onOpen, onNewConversation: onNewConversation)
                        .cardSegmentRow(.single, padding: EdgeInsets())
                }
            }
        }
        // grouped(셀이 화면 폭) — 카드는 행이 `cardSegmentRow` 로 직접 그린다(insetGrouped 는 셀을 시스템 반경으로 잘랐다).
        .listStyle(.grouped)
        .listSectionSpacing(0)
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
                    actionTitle: MessagesListText.newConversation,
                    action: onNewConversation
                )
            }
        }
    }
}

/// 보관 규칙 한 줄("⏱ 24시간이 지난 메시지는 사라져요") — 목록 그룹 아래 · 대화 맨 위 시스템 문구가 같은 모양이다.
struct MessagesExpiryNote: View {
    let alignment: HorizontalAlignment
    var font: Font = .footnote

    var body: some View {
        Label {
            Text(MessageNoticeText.expiry)
        } icon: {
            Image(systemName: "timer")
                .accessibilityHidden(true)
        }
        .labelStyle(MessagesCompactLabelStyle())
        .font(font)
        .foregroundStyle(MobileTheme.label2)
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 기호와 글자 사이를 좁힌 라벨(시안 `.b-foot` gap 5).
private struct MessagesCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 목록 한 줄(시안 B `.b-thread-row`).
struct MessagesThreadRow: View {
    static let avatarBase: CGFloat = 48

    /// 줄 사이 구분선이 시작하는 곳(카드 왼쪽에서) — 이름 글자 줄에 맞춘다(안쪽 여백 16 + 아바타 + 사이 12).
    static func dividerLeading(avatarSide: CGFloat) -> CGFloat {
        MobileTheme.cardPadding + avatarSide + 12
    }

    let thread: MessageThread
    let isUnread: Bool
    let countBadge: String?
    let presence: MessagesPeerPresence?
    let now: Date

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 미리보기는 두 줄까지(시안 B), 손쉬운 사용 글자 크기에서는 세 줄 — 한 줄이면 네 글자 뒤 말줄임이 됐다(AX3 실측).
    private var previewLines: Int { dynamicTypeSize.isAccessibilitySize ? 3 : 2 }

    var body: some View {
        let last = thread.lastMessage
        HStack(alignment: .top, spacing: 12) {
            PersonAvatar(
                name: thread.peerName,
                status: presence?.status,
                url: thread.peerAvatarURL,
                size: Self.avatarBase
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    PersonName(thread.peerName, center: presence?.center, font: isUnread ? .callout.weight(.bold) : MobileTheme.rowTitle)
                    Spacer(minLength: 4)
                    if let last {
                        Text(MessagesListRules.timeText(last.createdAt, now: now))
                            .font(isUnread ? .subheadline.weight(.semibold) : .subheadline)
                            .monospacedDigit()
                            .foregroundStyle(isUnread ? MobileTheme.accent : MobileTheme.label2)
                            .fixedSize()
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(last.map { MessagesListRules.preview($0.body) } ?? "")
                        .font(.subheadline)
                        .foregroundStyle(isUnread ? MobileTheme.label : MobileTheme.label2)
                        .lineLimit(previewLines)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let countBadge {
                        MessagesCountBadge(text: countBadge)
                            .padding(.top, 1)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [thread.peerName]
        if let line = MessagesPresenceRules.headerLine(presence) { parts.append(line) }
        if let countBadge { parts.append("안 읽은 메시지 \(countBadge)개") }
        if let last = thread.lastMessage {
            parts.append((last.isMine ? "나: " : "") + MessagesListRules.preview(last.body))
            parts.append(MessagesListRules.timeText(last.createdAt, now: now))
        }
        return parts.joined(separator: ", ")
    }
}

/// 안 읽은 개수 배지(시안 `.b-count`): 파랑 채움 캡슐 · 흰 13pt · 최소 22. 시스템 빨강 배지는 탭 막대만 쓴다.
private struct MessagesCountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.onAccentFill)
            .padding(.horizontal, 7)
            .frame(minWidth: 22, minHeight: 22)
            .background(Capsule().fill(MobileTheme.accentFill))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// "지금 근무 중 · 바로 말 걸기" 줄(시안 B 03): 근무 중인 사람 아바타(점) + 이름을 가로로 · 끝에 "새 대화". 누르면 그 사람과의 대화를 연다.
/// 사람이 많으면 가로로 넘긴다(그룹 폭 안에서 잘린다). 아무도 없으면 한 줄 안내 + "새 대화".
private struct MessagesWorkingStrip: View {
    let people: [MessagesWorkingPerson]
    let onOpen: (String) -> Void
    let onNewConversation: () -> Void

    var body: some View {
        if people.isEmpty {
            HStack(spacing: 14) {
                newConversationTile
                Text(MessagesListText.nobodyWorking)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MobileTheme.cardPadding)
            .padding(.vertical, 14)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(people) { person in
                        Button {
                            onOpen(person.id)
                        } label: {
                            tile(title: person.name, titleColor: MobileTheme.label) {
                                PersonAvatar(name: person.name, status: person.status, url: person.avatarURL, size: 52)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(person.status == .pending ? "\(person.name), 연결 끊김" : "\(person.name), 근무 중"))
                        .accessibilityHint(Text("대화 열기"))
                        .accessibilityAddTraits(.isButton)
                    }
                    newConversationTile
                }
                .padding(.horizontal, MobileTheme.cardPadding)
                .padding(.vertical, 14)
            }
            .clipShape(RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous))
        }
    }

    private var newConversationTile: some View {
        Button(action: onNewConversation) {
            tile(title: MessagesListText.newConversation, titleColor: MobileTheme.label2) {
                MessagesNewConversationCircle(size: 52)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(MessagesListText.newConversation))
        .accessibilityAddTraits(.isButton)
    }

    private func tile<Avatar: View>(title: String, titleColor: Color, @ViewBuilder avatar: () -> Avatar) -> some View {
        VStack(spacing: 6) {
            avatar()
            Text(title)
                .font(.footnote)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: 56)
        .contentShape(Rectangle())
    }
}

/// "새 대화" 원(회색 칠 + 더하기) — 사람 아바타와 같은 크기 규칙(`MobileAvatarScale`)으로 커진다.
private struct MessagesNewConversationCircle: View {
    let size: CGFloat
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    var body: some View {
        let side = MobileAvatarScale.side(base: size, textScale: textScale)
        Image(systemName: "plus")
            .font(.system(size: side * 0.4, weight: .medium))
            .foregroundStyle(MobileTheme.label2)
            .frame(width: side, height: side)
            .background(Circle().fill(MobileTheme.fill))
            .accessibilityHidden(true)
    }
}
#endif
