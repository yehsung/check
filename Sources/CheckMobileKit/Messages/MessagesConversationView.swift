#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 한 사람과의 대화(SPEC-ios §3.3): 상단 "24시간이 지난 메시지는 사라져요" · 날짜 구분선 · 말풍선(받은 것 왼쪽+아바타, 보낸 것 오른쪽) ·
/// 시각 · 내 말풍선 옆 1 · 보내는 중 자리 말풍선 · 입력칸(키보드 위로 따라 올라간다).
///
/// 이 화면이 서 있는 동안 스토어는 "그 대화가 보인다"로 안다(`conversationDidAppear/Disappear` — 뷰 인스턴스 표식).
/// 읽음 처리·즉시 이력은 스토어가 그 사실로 판정한다 — 뷰는 조건을 세지 않는다.
struct MessagesConversationView: View {
    let store: MessagesStore
    let peerID: String

    @State private var token = UUID()
    @State private var follow = MessagesScrollFollow()

    private static let bottomAnchorID = "messages-bottom-anchor"

    var body: some View {
        let items = store.conversationItems(for: peerID)
        let header = store.conversationHeader(for: peerID)
        let name = header.title
        let avatarURL = store.peerAvatarURL(for: peerID)
        ScrollViewReader { proxy in
            ScrollView {
                // Lazy 가 아니다: 화면 밖 줄의 높이를 어림하면 큰 글자에서 `scrollTo` 가 바닥에 못 닿았다(AX3 실측). 이력은 24시간 · 200건 상한이다.
                VStack(spacing: 6) {
                    Text(MessageNoticeText.expiry)
                        .font(.caption)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    if items.isEmpty {
                        emptyState
                    }
                    ForEach(items) { item in
                        row(item, peerName: name, avatarURL: avatarURL)
                            .id(item.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchorID)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .scrollDismissesKeyboard(.interactively)
            .background(MobileTheme.background.ignoresSafeArea())
            .onScrollGeometryChange(for: ScrollMeasure.self) { geometry in
                ScrollMeasure(
                    contentHeight: geometry.contentSize.height,
                    distanceToBottom: geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY,
                    containerHeight: geometry.containerSize.height,
                    bottomInset: geometry.contentInsets.bottom
                )
            } action: { old, new in
                let viewportChanged = abs(old.containerHeight - new.containerHeight) > 0.5
                    || abs(old.bottomInset - new.bottomInset) > 0.5
                follow.measured(contentHeight: new.contentHeight, distanceToBottom: new.distanceToBottom, viewportChanged: viewportChanged)
                // 키보드·입력칸·안내 줄로 보이는 틀이 줄었다 — 바닥에서 보던 사람은 계속 바닥을 본다.
                if viewportChanged, follow.isNearBottom {
                    // 틀이 다 바뀐 뒤(다음 차례)에 보낸다 — 같은 차례에 보내면 옛 틀 기준으로 멈췄다.
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: items.last?.id) { _, _ in
                let isMine: Bool
                switch items.last {
                case .bubble(let line): isMine = line.entry.isMine
                case .pending: isMine = true
                default: isMine = false
                }
                if follow.lastItemChanged(isMine: isMine) {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom) }
                }
            }
            .overlay(alignment: .bottom) {
                if follow.showsNewMessageButton || demoForcesNewMessageButton {
                    Button {
                        follow.jumpedToBottom()
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom) }
                    } label: {
                        Text(MessagesScrollFollow.newMessageButtonTitle)
                            .font(.footnote.weight(.bold))
                            .lineLimit(1)
                            .fixedSize()
                            // 떠 있는 작은 버튼이다 — 가장 큰 글자에서 캡슐이 화면 폭을 채우며 말풍선을 덮었다(AX3 실측).
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .foregroundStyle(MobileTheme.onAccent)
                            .padding(.horizontal, 16)
                            // 누르는 자리 44pt 이상(예전 세로 여백 8 로는 31.7pt).
                            .frame(minHeight: CGFloat(MessagesScrollFollow.newMessageButtonMinHeight))
                            .background(Capsule().fill(MobileTheme.accent))
                            // 바탕색 테두리 + 그림자 — 같은 accent 색인 내 말풍선 위에 떠도 경계가 보인다(예전엔 '새 메시지 ↓`요'로 섞였다).
                            .padding(2)
                            .background(Capsule().fill(MobileTheme.background))
                            .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
                            .contentShape(Capsule())
                    }
                    .accessibilityLabel(Text("새 메시지로 이동"))
                    .padding(.bottom, 8)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MessagesComposerView(store: store, peerID: peerID)
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    if let avatarName = header.avatarName {
                        AvatarView(name: avatarName, url: avatarURL, size: 28, scalesWithText: false)
                    } else {
                        // 이름을 모른다 — "대" 이니셜 원을 세우면 "대화"라는 사람처럼 보였다.
                        Image(systemName: MessagesConversationHeader.unknownAvatarSymbol)
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(MobileTheme.secondaryText)
                            .frame(width: 28, height: 28)
                    }
                    Text(header.title)
                        .font(.headline)
                        .foregroundStyle(MobileTheme.primaryText)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(header.accessibilityLabel))
                .accessibilityAddTraits(.isHeader)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear { store.conversationDidAppear(peerID: peerID, token: token) }
        .onDisappear { store.conversationDidDisappear(token: token) }
        #if DEBUG
        .task { MessagesDemoLaunch.seedComposerIfRequested(store: store, peerID: peerID) }
        #endif
    }

    /// 데모 스크린샷 고리(`-AingCheckDemoMessages newbutton`). Release 에서는 늘 false.
    private var demoForcesNewMessageButton: Bool {
        #if DEBUG
        MessagesDemoLaunch.forcesNewMessageButton(isDemo: store.context.isDemo)
        #else
        false
        #endif
    }

    @ViewBuilder
    private var emptyState: some View {
        let state = MessagesConversationRules.emptyState(loaded: store.historyLoaded, failed: store.historyFailed)
        EmptyStateView(
            systemImage: state.symbol,
            title: state.title,
            message: state.hint,
            actionTitle: state.showsRetry ? MobileLoadText.retry : nil,
            action: state.showsRetry ? { Task { await store.retryConversation(peerID: peerID) } } : nil
        )
        .padding(.top, 40)
    }

    @ViewBuilder
    private func row(_ item: MessagesConversationItem, peerName: String, avatarURL: URL?) -> some View {
        switch item {
        case .day(_, let label):
            MessagesDaySeparator(label: label)
        case .bubble(let line):
            MessagesBubbleRow(line: line, peerName: peerName, avatarURL: avatarURL)
        case .pending(let pending):
            MessagesPendingBubbleRow(item: pending)
        }
    }
}

private struct ScrollMeasure: Equatable {
    var contentHeight: Double
    var distanceToBottom: Double
    var containerHeight: Double
    var bottomInset: Double
}

// MARK: - 줄 모양

/// 날짜 구분선("오늘" / "어제" / "9월 8일").
struct MessagesDaySeparator: View {
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(MobileTheme.separator).frame(height: 1)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(MobileTheme.secondaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(MobileTheme.cardElevated))
                .fixedSize()
            Rectangle().fill(MobileTheme.separator).frame(height: 1)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.isHeader)
    }
}

/// 말풍선 한 줄. 받은 것은 왼쪽(묶음 첫 줄에 아바타), 보낸 것은 오른쪽. 시각·1 은 말풍선 바깥 아래쪽 곁.
struct MessagesBubbleRow: View {
    let line: MessagesBubbleLine
    let peerName: String
    let avatarURL: URL?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let avatarSize: CGFloat = 32

    /// 말풍선 반대쪽 최소 여백. 큰 글자에서는 줄인다 — 시각 글자까지 커지면 받은 말풍선이 네 글자 폭으로 좁아졌다(데모 스크린샷 AX3 실측).
    private var oppositeInset: CGFloat { dynamicTypeSize.isAccessibilitySize ? 24 : 56 }

    var body: some View {
        let entry = line.entry
        HStack(alignment: .bottom, spacing: 6) {
            if entry.isMine {
                Spacer(minLength: oppositeInset)
                meta(alignment: .trailing)
                bubble
            } else {
                if line.showsAvatar {
                    AvatarView(name: entry.peerName, url: entry.peerAvatarURL ?? avatarURL, size: Self.avatarSize)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    AvatarSpacer(size: Self.avatarSize)
                }
                bubble
                meta(alignment: .leading)
                Spacer(minLength: oppositeInset)
            }
        }
        .padding(.top, line.showsAvatar ? 6 : 0)
        .frame(maxWidth: .infinity, alignment: entry.isMine ? .trailing : .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var bubble: some View {
        Text(line.entry.body)
            .font(.body)
            .foregroundStyle(line.entry.isMine ? MobileTheme.onAccent : MobileTheme.primaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(line.entry.isMine ? MobileTheme.accent : MobileTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(line.entry.isMine ? Color.clear : MobileTheme.separator, lineWidth: 1)
            )
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func meta(alignment: HorizontalAlignment) -> some View {
        if line.showsUnreadOne || line.showsTime {
            VStack(alignment: alignment, spacing: 0) {
                if line.showsUnreadOne {
                    Text(MessagesConversationRules.unreadOneText)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.accent)
                }
                if line.showsTime {
                    Text(line.clockText)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.secondaryText)
                }
            }
            .fixedSize()
            // 곁 글자(1 · 시각)는 본문만큼 키우지 않는다 — 본문 폭을 먹는다. 보이스오버는 줄 전체 라벨로 읽는다.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
    }

    private var accessibilityText: String {
        let entry = line.entry
        var parts = [(entry.isMine ? "나" : entry.peerName) + ": " + entry.body, line.clockText]
        if line.showsUnreadOne { parts.append(MessagesConversationRules.unreadOneAccessibilityLabel) }
        return parts.joined(separator: ", ")
    }
}

/// 보내는 중(또는 서버가 받았지만 이력이 아직 안 들고 온) 내 말풍선.
struct MessagesPendingBubbleRow: View {
    let item: MessagesPendingOutgoing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 24 : 56)
            if item.state == .sending {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
            Text(item.body)
                .font(.body)
                .foregroundStyle(MobileTheme.onAccent)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(MobileTheme.accent.opacity(0.6))
                )
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("나: \(item.body), " + (item.state == .sending ? "보내는 중" : "보냄")))
    }
}
#endif
