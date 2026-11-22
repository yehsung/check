import CheckCore
import Foundation
#if os(iOS)
import SwiftUI

// MARK: - 지난 확성기 페이지(폰 1.0.19 — 맥 0.3.86 `CheckMegaphoneFeedPanel` 의 폰 짝 · 대표 #d_xygj8oZRFlfH 4번 메시지 묶음)
//
// 문은 확성기 작성 시트의 설명 아래 '지난 확성기 ›' 하나다(`MessagesMegaphoneSheet`). 같은 시트의 NavigationStack 에 쌓는다.
// 판정(문 세 갈래 · 커서 · 중복 · 세대 가드)은 전부 코어 `MegaphoneFeedStore`(맥과 한 벌)에 있고, 이 파일은 그리기와 누름만 한다.
// 부르는 자리: 페이지가 서면 `open()`(첫 쪽) · [이전 확성기 더 보기] · [다시 시도] · 당겨서 새로 고침 · 떠 있는 동안 실시간 신호(러너).
// 줄: 얼굴 · 이름 · '내가 보낸' · 시각 · 받은 사람 수 · 본문(마크다운 기호를 벗긴 글 3줄, 넘치면 [더 보기]/[접기]) · ···(남의 글: 신고 · 차단 —
// 시트를 **열기만** 한다). 줄에는 메시지 id 가 없어서 신고는 보낸 사람 신고다(맥 `MegaphoneFeedSafetyRule` 과 같다).
// 맥과 다른 것: 운영자 [내리기]는 폰에 없다(맥에서만 — 운영자는 맥을 쓴다).
struct MessagesMegaphoneFeedView: View {
    let store: MessagesStore

    @State private var expandedIDs: Set<String> = []
    @State private var truncatedIDs: Set<String> = []
    @State private var reportTarget: MessagesReportTarget?
    @State private var blockTarget: MessagesFeedBlockTarget?

    var body: some View {
        let feed = store.megaphoneFeed
        let items = store.visibleMegaphoneFeed
        let now = store.context.clock.now()
        List {
            Text(MegaphoneFeedText.windowNote)
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
                .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                .cardListPlainRow(top: 8, bottom: 4)
            if let notice = store.blockNotice {
                InlineNotice(text: notice, kind: store.blockNoticeIsError ? .error : .info)
                    .cardListPlainRow()
            }
            if items.isEmpty {
                emptyState(feed)
                    .cardListPlainRow()
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                    row(item, now: now)
                        .cardSegmentRow(.of(index: offset, count: items.count),
                                        padding: EdgeInsets(top: 10, leading: MobileTheme.cardPadding, bottom: 10,
                                                            trailing: MobileTheme.cardPadding),
                                        dividerLeading: MobileTheme.cardPadding + Self.avatarSize + 10)
                }
                footer(feed)
                    .cardListPlainRow(top: 10, bottom: 20)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollContentBackground(.hidden)
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(MegaphoneFeedText.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await feed.refresh()?.value }
        .onAppear { feed.open() }
        .onDisappear { feed.close() }
        .sheet(item: $reportTarget) { target in
            MessagesReportSheet(store: store, target: target, onSent: { _ in reportTarget = nil }, onClose: { reportTarget = nil })
        }
        .sheet(item: $blockTarget) { target in
            MessagesBlockConfirmSheet(
                peerName: target.peerName,
                onConfirm: {
                    blockTarget = nil
                    store.blockPeer(target.peerID)
                },
                onClose: { blockTarget = nil }
            )
        }
    }

    static let avatarSize: CGFloat = 32

    @ViewBuilder
    private func emptyState(_ feed: MegaphoneFeedStore) -> some View {
        if feed.isAvailable == false {
            EmptyStateView(systemImage: "megaphone", title: MegaphoneFeedText.unavailable, message: nil)
        } else if feed.loadFailed {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: MegaphoneFeedText.failed,
                           message: MobileLoadText.checkConnection, actionTitle: MobileLoadText.retry,
                           action: { feed.refresh() })
        } else if !feed.hasLoaded || feed.isLoading {
            LoadingRow()
        } else {
            EmptyStateView(systemImage: "megaphone", title: MegaphoneFeedText.empty, message: nil)
        }
    }

    @ViewBuilder
    private func footer(_ feed: MegaphoneFeedStore) -> some View {
        HStack {
            Spacer(minLength: 0)
            if feed.isLoadingMore {
                ProgressView()
            } else if feed.loadMoreFailed {
                Button(MegaphoneFeedText.loadMoreFailed) { feed.loadMore() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.pending)
            } else if feed.hasMore {
                Button(MegaphoneFeedText.loadMore) { feed.loadMore() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.accent)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 28)
    }

    private func row(_ item: MegaphoneFeedItem, now: Date) -> some View {
        let expanded = expandedIDs.contains(item.id)
        let me = store.context.gomokuHost.session?.userID
        let target = MessagesMegaphoneFeedRules.actionTarget(for: item, me: me)
        let text = ChatMarkdown.plainPreview(item.body)
        return HStack(alignment: .top, spacing: 10) {
            PersonAvatar(name: item.senderName, url: item.senderAvatarURL, userID: item.senderID, size: Self.avatarSize)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.senderName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MobileTheme.label)
                        .lineLimit(1)
                    if item.isOwn {
                        Text(MegaphoneFeedText.ownBadge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MobileTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(MobileTheme.accentTint))
                            .fixedSize()
                    }
                    Spacer(minLength: 4)
                    Text(MessagesMegaphoneFeedRules.metaText(item, now: now))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label2)
                        .lineLimit(1)
                        .fixedSize()
                    if let target {
                        Menu {
                            Button(BlockReportText.reportAction) {
                                reportTarget = MessagesReportTarget(peerID: target.peerID, peerName: target.peerName)
                            }
                            Button(BlockReportText.blockAction, role: .destructive) {
                                blockTarget = MessagesFeedBlockTarget(peerID: target.peerID, peerName: target.peerName)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(MobileTheme.label2)
                                .frame(width: 28, height: 22)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(Text("\(item.senderName) 신고 · 차단"))
                    }
                }
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label)
                    .lineLimit(expanded ? nil : MegaphoneFeedRules.collapsedLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 넘침 판정: 줄 제한 없는 같은 글의 높이와 견준다(보이지 않는 쌍둥이 — 맥은 글꼴로 재고, 폰은 높이로 잰다).
                    .background(alignment: .topLeading) {
                        if !expanded {
                            Text(text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                                .hidden()
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full in
                                    noteTruncation(item.id, fullHeight: full)
                                }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shown in
                        if !expanded { shownHeights[item.id] = shown; recheck(item.id) }
                    }
                if expanded || truncatedIDs.contains(item.id) {
                    Button(expanded ? MegaphoneFeedText.collapse : MegaphoneFeedText.expand) {
                        if expanded { expandedIDs.remove(item.id) } else { expandedIDs.insert(item.id) }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.accent)
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // 넘침 판정의 두 높이(보이는 글 · 제한 없는 쌍둥이). 둘 다 알 때 판정한다.
    @State private var shownHeights: [String: CGFloat] = [:]
    @State private var fullHeights: [String: CGFloat] = [:]

    private func noteTruncation(_ id: String, fullHeight: CGFloat) {
        fullHeights[id] = fullHeight
        recheck(id)
    }

    private func recheck(_ id: String) {
        guard let shown = shownHeights[id], let full = fullHeights[id] else { return }
        let truncated = full > shown + 1
        if truncated != truncatedIDs.contains(id) {
            if truncated { truncatedIDs.insert(id) } else { truncatedIDs.remove(id) }
        }
    }
}

/// 차단 확인 시트의 대상(사람 하나).
struct MessagesFeedBlockTarget: Identifiable, Equatable {
    let peerID: String
    let peerName: String
    var id: String { peerID }
}
#endif

/// 지난 확성기 줄의 순수 규칙(맥 `MegaphoneFeedSafetyRule` · `metaText` 와 같다 — 시험이 값으로 잰다).
package enum MessagesMegaphoneFeedRules {
    /// 머리 줄 오른쪽의 작은 글씨: 시각 · 받은 사람 수(모르면 시각만).
    package static func metaText(_ item: MegaphoneFeedItem, now: Date) -> String {
        let time = MegaphoneFeedText.timeLabel(item.createdAt, now: now)
        guard let recipients = item.recipients, recipients > 0 else { return time }
        return "\(time) · \(MegaphoneFeedText.recipients(recipients))"
    }

    /// 신고 · 차단할 사람(내 글이거나 보낸 사람을 모르면 nil — 나를 신고 · 차단하는 문은 없다). 서버가 `is_mine` 을 잘못 말해도 내 id 면 내 글.
    package static func actionTarget(for item: MegaphoneFeedItem, me: String?) -> (peerID: String, peerName: String)? {
        guard !item.isOwn, let sender = item.senderID, !sender.isEmpty else { return nil }
        if let me, sender.lowercased() == me.lowercased() { return nil }
        return (sender, item.senderName)
    }
}
