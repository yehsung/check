#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI
import UIKit

/// 한 사람과의 대화(SPEC-ios §3.3 · 시안 B 04): 머리(상대 아바타 + 유리 이름표 "근무 중 · 서울") · 맨 위 "⏱ 24시간이 지난 메시지는 사라져요" ·
/// 날짜 줄 · 말풍선(받은 것 왼쪽 회색, 보낸 것 오른쪽 파랑) · 곁 "1 13:52"(같은 분 묶음의 마지막에만 시각) · 보내는 중 자리 말풍선 ·
/// 입력칸(키보드 위로 따라 올라간다). 탭 막대는 숨긴다(`MessagesTab` 이 목적지에 `hidesTabBar(for: .conversation)`).
///
/// 이 화면이 서 있는 동안 스토어는 "그 대화가 보인다"로 안다(`conversationDidAppear/Disappear` — 뷰 인스턴스 표식).
/// 읽음 처리·즉시 이력은 스토어가 그 사실로 판정한다 — 뷰는 조건을 세지 않는다.
///
/// 오른쪽 위 ··· 메뉴(앱스토어 심사 지침 1.2): [신고하기] · [차단하기]. 둘 다 **시트만 연다** — 차단은 확인 시트를,
/// 신고는 사유 시트를 지나야 서버로 나간다(소스 계약). 받은 말풍선을 길게 누르면 그 **메시지 한 건**을 신고한다.
struct MessagesConversationView: View {
    let store: MessagesStore
    let peerID: String

    @Environment(\.dismiss) private var dismiss
    @State private var token = UUID()
    @State private var follow = MessagesScrollFollow()
    @State private var showsBlockConfirm = false
    @State private var reportTarget: MessagesReportTarget?

    private static let bottomAnchorID = "messages-bottom-anchor"

    var body: some View {
        let items = store.conversationItems(for: peerID)
        let header = store.conversationHeader(for: peerID)
        let avatarURL = store.peerAvatarURL(for: peerID)
        let board = header.avatarName == nil ? nil : store.presenceBoard(now: store.context.clock.now())
        let presence = board?.peers[peerID]
        // 상대의 상태메시지(v0.3.51) — 이름을 모르면(머리가 아직 이름을 못 찾았으면) 세우지 않는다.
        let statusMessage = board?.statuses[peerID]
        ScrollViewReader { proxy in
            ScrollView {
                // Lazy 가 아니다: 화면 밖 줄의 높이를 어림하면 큰 글자에서 `scrollTo` 가 바닥에 못 닿았다(AX3 실측). 이력은 24시간 · 200건 상한이다.
                VStack(spacing: 3) {
                    MessagesExpiryNote(alignment: .center, font: .caption)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    // 차단·신고 결과 한 줄(신고 접수 · 차단 되돌림). 목록과 같은 값을 그린다 — 둘은 동시에 서지 않는다.
                    if let notice = store.blockNotice {
                        InlineNotice(text: notice, kind: store.blockNoticeIsError ? .error : .info)
                            .padding(.bottom, 4)
                    }
                    if items.isEmpty {
                        emptyState
                    }
                    ForEach(items) { item in
                        row(item)
                            .id(item.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchorID)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            // 짧은 대화는 입력칸 쪽(아래)에 붙는다 — 위에 붙이면 마지막 말풍선과 입력칸 사이가 비었다(시안 B 04 는 위가 빈다).
            .defaultScrollAnchor(.bottom, for: .alignment)
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
                            .foregroundStyle(MobileTheme.accent)
                            .padding(.horizontal, 16)
                            // 누르는 자리 44pt 이상(예전 세로 여백 8 로는 31.7pt).
                            .frame(minHeight: CGFloat(MessagesScrollFollow.newMessageButtonMinHeight))
                            // 유리 알약 — 채운 파랑은 이 화면의 보내기 하나뿐이다. 파랑 말풍선 위에 떠도 테두리·그림자로 경계가 보인다.
                            .background(GlassBackground(shape: Capsule()))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("새 메시지로 이동"))
                    .padding(.bottom, 8)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                MessagesConversationNameplate(header: header, presence: presence, statusMessage: statusMessage)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MessagesComposerView(store: store, peerID: peerID)
            }
        }
        .navigationTitle(header.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // 머리 가운데는 상대 얼굴 하나 — 이름·근무 상태는 바로 아래 유리 이름표가 말한다(보이스오버도 이름표가 읽는다).
                Group {
                    if let avatarName = header.avatarName {
                        PersonAvatar(
                            name: avatarName,
                            status: presence?.status,
                            url: avatarURL,
                            userID: peerID,
                            size: MessagesConversationNameplate.avatarSize,
                            ringColor: MobileTheme.background,
                            scalesWithText: false
                        )
                    } else {
                        // 이름을 모른다 — "대" 이니셜 원을 세우면 "대화"라는 사람처럼 보였다.
                        Image(systemName: MessagesConversationHeader.unknownAvatarSymbol)
                            .font(.system(size: MessagesConversationNameplate.avatarSize - 4, weight: .regular))
                            .foregroundStyle(MobileTheme.label2)
                            .frame(width: MessagesConversationNameplate.avatarSize, height: MessagesConversationNameplate.avatarSize)
                    }
                }
                .accessibilityHidden(true)
            }
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu
            }
        }
        // 차단 확인 — **차단을 부르는 곳은 이 시트 하나다**(메뉴는 열기만 한다).
        .sheet(isPresented: $showsBlockConfirm) {
            MessagesBlockConfirmSheet(
                peerName: store.peerName(for: peerID) ?? header.title,
                onConfirm: confirmBlock,
                onClose: { showsBlockConfirm = false }
            )
        }
        .sheet(item: $reportTarget) { target in
            MessagesReportSheet(
                store: store,
                target: target,
                onSent: { blocked in
                    reportTarget = nil
                    // 신고하면서 차단했으면 이 대화는 이미 사라졌다 — 목록으로 빠져나온다.
                    if blocked { dismiss() }
                },
                onClose: { reportTarget = nil }
            )
        }
        .onAppear { store.conversationDidAppear(peerID: peerID, token: token) }
        .onDisappear { store.conversationDidDisappear(token: token) }
        #if DEBUG
        .task { MessagesDemoLaunch.seedComposerIfRequested(store: store, peerID: peerID) }
        #endif
    }

    /// 오른쪽 위 ··· — [신고하기] · [차단하기](파괴적). 메뉴는 **시트만 연다**.
    private var moreMenu: some View {
        Menu {
            Button {
                reportTarget = MessagesReportTarget(peerID: peerID, peerName: peerDisplayName)
            } label: {
                Label(BlockReportText.reportAction, systemImage: "exclamationmark.bubble")
            }
            Button(role: .destructive) {
                showsBlockConfirm = true
            } label: {
                Label(BlockReportText.blockAction, systemImage: "nosign")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MobileTheme.label)
        }
        .tint(MobileTheme.label)
        .accessibilityLabel(Text(BlockReportText.menuAccessibilityLabel))
    }

    /// 시트·신고에 싣는 상대 이름(모르면 대화 머리 글자와 같은 폴백).
    private var peerDisplayName: String {
        store.peerName(for: peerID) ?? MessagesConversationHeader.fallbackTitle
    }

    /// 받은 말풍선을 길게 눌러 그 **메시지 한 건**을 신고한다(id 를 싣는다 — 운영자가 무엇을 볼지 정해진다).
    private func reportMessage(_ entry: MessageHistoryEntry) {
        reportTarget = MessagesReportTarget(
            peerID: peerID,
            peerName: entry.peerName,
            messageID: entry.id,
            messageBody: entry.body
        )
    }

    /// 확인 시트의 [차단하기]. 낙관적으로 지우고(스토어) 목록으로 빠져나온다 — 서버 응답을 기다리지 않는다.
    private func confirmBlock() {
        showsBlockConfirm = false
        store.blockPeer(peerID)
        dismiss()
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
    private func row(_ item: MessagesConversationItem) -> some View {
        switch item {
        case .day(_, let label):
            MessagesDaySeparator(label: label)
        case .bubble(let line):
            // 신고는 **받은 말풍선만**이다 — 내 말을 내가 신고하는 길은 만들지 않는다(그 메뉴는 뜻이 없다).
            MessagesBubbleRow(line: line, onReport: line.entry.isMine ? nil : { reportMessage(line.entry) })
                // 말한 쪽이 바뀌면 조금 더 띄운다(시안 `.b-gap` 10 = 줄 간격 3 + 7).
                .padding(.top, line.startsGroup ? 7 : 0)
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

/// 머리 아래 유리 이름표(시안 `.b-convo-name`): 이름 15 semibold + "● 근무 중 · 서울" 11pt. 뒤는 바탕색에서 투명으로 녹는 띠라
/// 위로 넘긴 말풍선이 이름표 뒤로 흐리게 사라진다(시안 `.b-edge`).
private struct MessagesConversationNameplate: View {
    static let avatarSize: CGFloat = 40
    static var topPadding: CGFloat {
        if #available(iOS 26.0, *) { -9 } else { 2 }
    }

    let header: MessagesConversationHeader
    let presence: MessagesPeerPresence?
    /// 상대의 상태메시지(v0.3.51). 있으면 근무 줄 아래 한 줄(꼬리 줄임표) — 이름표가 한 줄 자랄 뿐 머리 모양은 그대로다.
    var statusMessage: String? = nil

    var body: some View {
        let line = MessagesPresenceRules.headerLine(presence)
        VStack(spacing: 1) {
            Text(header.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MobileTheme.label)
                .lineLimit(1)
            if let line {
                HStack(spacing: 4) {
                    if let status = presence?.status, status != .off {
                        StatusDot(status, size: 6)
                    }
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(MobileTheme.label2)
                        .lineLimit(1)
                }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(MobileTheme.label2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 260)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 5)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MobileTheme.glass))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(MobileTheme.glassLine, lineWidth: 0.5))
        )
        // 이름표는 작은 머리다 — 가장 큰 글자에서 화면 위를 통째로 먹지 않게 상한을 둔다(보이스오버는 글자 그대로 읽는다).
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([header.accessibilityLabel, line, statusMessage.map { "상태메시지 \($0)" }]
            .compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(.isHeader)
        .frame(maxWidth: .infinity)
        // 얼굴 바로 아래에 붙인다(시안 B 04 틈 4pt). iOS 26 내비 막대는 유리 버튼 때문에 키가 커 얼굴 아래가 14pt 떴다(스크린샷 실측).
        .padding(.top, Self.topPadding)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                stops: [
                    .init(color: MobileTheme.background, location: 0),
                    .init(color: MobileTheme.background, location: 0.6),
                    .init(color: MobileTheme.background.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }
}

// MARK: - 줄 모양

/// 날짜 줄("오늘" / "어제" / "9월 8일") — 선·캡슐 없이 가운데 작은 글자(시안 `.b-day`).
struct MessagesDaySeparator: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(MobileTheme.label2)
            .fixedSize()
            .frame(maxWidth: .infinity)
            .padding(.top, 11)
            .padding(.bottom, 5)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 말풍선 한 줄. 받은 것은 왼쪽(회색 `bubbleIn`), 보낸 것은 오른쪽(`accentFill` · 흰 글자). 곁 글자("1 13:52")는 말풍선 바깥 아래쪽에
/// **가로로** — 세로로 쌓으면 연속 말풍선에서 어느 말풍선의 1 인지 헷갈렸다(비평 04).
struct MessagesBubbleRow: View {
    let line: MessagesBubbleLine
    /// 길게 눌러 이 메시지를 신고한다. nil 이면 메뉴에 신고가 없다(내 말풍선).
    var onReport: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 말풍선 반대쪽 최소 여백(시안 말풍선 최대 폭 약 73%). 큰 글자에서는 줄인다 — 시각 글자까지 커지면 받은 말풍선이 네 글자 폭으로 좁아졌다(AX3 실측).
    private var oppositeInset: CGFloat { dynamicTypeSize.isAccessibilitySize ? 24 : 64 }

    var body: some View {
        let entry = line.entry
        HStack(alignment: .bottom, spacing: 6) {
            if entry.isMine {
                Spacer(minLength: oppositeInset)
                meta
                bubble
            } else {
                bubble
                meta
                Spacer(minLength: oppositeInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: entry.isMine ? .trailing : .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAction(named: Text(MessagesBubbleCopy.title)) { MessagesBubbleCopy.copy(entry.body) }
        // 보이스오버는 길게 누름 메뉴를 못 연다 — 신고도 동작으로 단다(복사와 같은 자리).
        .accessibilityActions {
            if let onReport {
                Button(BlockReportText.reportMessageAction, action: onReport)
            }
        }
    }

    /// 복사는 길게 눌러 메뉴로(원문 그대로 — 붙여넣어 다시 보내면 그림이 된다). 본문이 `UILabel`(어절 줄바꿈)이라
    /// SwiftUI `textSelection` 이 닿지 않는다. 메뉴는 **이모티콘 말풍선에도 그대로 달린다**(두 갈래가 이 한 자리를 쓴다).
    private var bubble: some View {
        bubbleContent
            .contextMenu {
                Button {
                    MessagesBubbleCopy.copy(line.entry.body)
                } label: {
                    Label(MessagesBubbleCopy.title, systemImage: "doc.on.doc")
                }
                if let onReport {
                    Button(role: .destructive, action: onReport) {
                        Label(BlockReportText.reportMessageAction, systemImage: "exclamationmark.bubble")
                    }
                }
            }
    }

    /// 본문이 아잉이 이모티콘 하나면 **글자 대신 그림**이다(1.0.12). 아니면 예전 그대로 글자 말풍선이다.
    ///
    /// ★ **판정하는 자리는 `AingStickerArt.drawable` 하나다.** 자리 말풍선(`MessagesPendingBubbleRow`)도 같은 함수를
    ///   부른다 — 한쪽이 `AingSticker.parse` 만 보면 번들이 깨진 배포본에서 두 자리가 갈리고(그림을 그릴 수 있다고
    ///   센 쪽과 못 그린 쪽), 보낸 순간엔 글자였다가 이력이 오면 그림이 되는 꼴이 된다(맥 v0.3.62 의 그 사고).
    ///   그림을 못 읽으면 **빈 말풍선이 아니라 지금 그대로의 글자 말풍선**으로 접는다.
    ///
    /// 누르는 모양(`contentShape`)만 갈래마다 다르다: 그림은 배경이 없으니 그림 사각형, 글자는 말풍선 반경이다.
    @ViewBuilder
    private var bubbleContent: some View {
        if let drawn = AingStickerArt.drawable(for: line.entry.body) {
            MessagesStickerBubble(art: drawn.art)
                .contentShape(.contextMenuPreview, Rectangle())
        } else {
            MessagesBubbleText(text: line.entry.body, isMine: line.entry.isMine)
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: MessagesBubbleText.cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private var meta: some View {
        if line.showsUnreadOne || line.showsTime {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
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
                        .foregroundStyle(MobileTheme.label2)
                }
            }
            .padding(.bottom, 2)
            .fixedSize()
            // 곁 글자(1 · 시각)는 본문만큼 키우지 않는다 — 본문 폭을 먹는다. 보이스오버는 줄 전체 라벨로 읽는다.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
    }

    /// 줄 전체 보이스오버. 이모티콘이면 날것 토큰(`[아잉:기쁨]`)이 아니라 이름으로 읽힌다("아잉이 기쁨").
    ///
    /// ★ 그림 안에는 이미 문구가 구워져 있지만(`AingStickerArt.labeledImage`) 이 줄은
    ///   `accessibilityElement(children: .ignore)` 라 **그 라벨이 줄 라벨에 섞이지 않는다** — 여기를 안 바꾸면
    ///   보이스오버가 대괄호 토큰을 또박또박 읽는다. 평범한 본문은 `preview` 가 한 글자도 바꾸지 않는다.
    private var accessibilityText: String {
        let entry = line.entry
        var parts = [(entry.isMine ? "나" : entry.peerName) + ": " + AingStickerText.preview(for: entry.body), line.clockText]
        if line.showsUnreadOne { parts.append(MessagesConversationRules.unreadOneAccessibilityLabel) }
        return parts.joined(separator: ", ")
    }
}

/// 말풍선 복사(길게 누름 메뉴 · 보이스오버 동작). 늘 원문을 담는다.
enum MessagesBubbleCopy {
    static let title = "복사"

    @MainActor
    static func copy(_ body: String) {
        UIPasteboard.general.string = body
    }
}

/// 말풍선 글자 + 바탕(시안 `.b-bub`: 16pt · 안쪽 8/13/9 · 반경 19). 보내는 중 자리 말풍선도 같은 모양을 흐리게 쓴다.
private struct MessagesBubbleText: View {
    static let cornerRadius: CGFloat = 19

    let text: String
    let isMine: Bool
    var isPending = false

    var body: some View {
        MessagesBubbleLabel(text: text, isMine: isMine)
            .padding(.horizontal, 13)
            .padding(.top, 8)
            .padding(.bottom, 9)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(isMine ? MobileTheme.accentFill : MobileTheme.bubbleIn)
                    .opacity(isPending ? 0.6 : 1)
            )
    }
}

/// 이모티콘 말풍선 — **배경·테두리·안쪽 여백이 없다.** 사용자 결정이 "말풍선 한 칸을 통째로 차지하는 큰 그림"이고,
/// 읽음 표시·시각·좌우 정렬은 바깥 행이 그리므로 그 자리들은 예전과 똑같다(맥 `stickerBubble` 과 한 모양).
///
/// ★ 여기에 `.accessibilityLabel` 을 붙이지 않는다. 보이스오버 문구는 **그림 안에 구워져 있고**
///   (`AingStickerArt.labeledImage`), 꾸밈용 그림에 건 라벨은 AX 요소가 없어 **버려진다**(2026-10-21 실측).
///   이 줄을 읽는 것은 바깥 행의 줄 라벨(`accessibilityText`)이다.
private struct MessagesStickerBubble: View {
    /// 그림 한 변(pt). 맥(`MessagePanelLayout.stickerSide`)과 **같은 120** — 두 화면의 그림 크기 인상을 맞춘다.
    /// Dynamic Type 을 따라 키우지 않는다: 그림은 글자가 아니고, 큰 글자에서 화면 폭을 통째로 먹는다.
    static let side: CGFloat = 120

    let art: Image
    /// 자리 말풍선은 글자 말풍선과 **같은 투명도**로 흐려진다(`MessagesBubbleText.isPending` 와 한 값).
    var isPending = false

    var body: some View {
        art
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: Self.side, height: Self.side)
            .opacity(isPending ? 0.6 : 1)
    }
}

/// 말풍선 본문 글자 — **한글 어절 단위로 줄을 바꾼다**. SwiftUI `Text` · `UILabel` 은 음절 사이에서 끊어 TextKit 으로 재고 그린다
/// (까닭과 실측은 `MessagesBubbleTextLayout`). 글자 크기는 SwiftUI 의 `dynamicTypeSize` 를, 색은 테마(외관별 UIColor)를 따른다.
private struct MessagesBubbleLabel: UIViewRepresentable {
    let text: String
    let isMine: Bool

    func makeUIView(context: Context) -> MessagesBubbleTextUIView {
        MessagesBubbleTextUIView()
    }

    func updateUIView(_ view: MessagesBubbleTextUIView, context: Context) {
        let font = UIFont.preferredFont(
            forTextStyle: .callout,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(context.environment.dynamicTypeSize))
        )
        let color = MobileTheme.uiColor(isMine ? MobileThemePalette.onAccentFill : MobileThemePalette.label)
        view.set(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: MessagesBubbleTextLayout.paragraphStyle(),
        ]))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: MessagesBubbleTextUIView, context: Context) -> CGSize? {
        view.engine.fittingSize(width: proposal.width ?? .greatestFiniteMagnitude)
    }
}

/// TextKit 으로 그리는 글 칸(말풍선 본문 전용). 보이스오버는 줄 전체 라벨이 읽는다(이 칸은 요소가 아니다).
final class MessagesBubbleTextUIView: UIView {
    let engine = MessagesBubbleTextLayout.Engine()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isAccessibilityElement = false
        // 외관(라이트·다크 · 앱 화면 모드 설정)이 바뀌면 테마 색을 다시 풀어 그린다.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MessagesBubbleTextUIView, _: UITraitCollection) in
            view.setNeedsDisplay()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func set(_ attributed: NSAttributedString) {
        if engine.set(attributed) { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        engine.layout(width: bounds.width)
        let glyphs = engine.layoutManager.glyphRange(for: engine.container)
        engine.layoutManager.drawGlyphs(forGlyphRange: glyphs, at: .zero)
    }
}

/// 보내는 중(또는 서버가 받았지만 이력이 아직 안 들고 온) 내 말풍선.
struct MessagesPendingBubbleRow: View {
    let item: MessagesPendingOutgoing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 24 : 64)
            if item.state == .sending {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
            // 판정은 말풍선 행과 **같은 한 함수**다(갈리면 보낸 순간엔 글자, 이력이 오면 그림이 된다).
            if let drawn = AingStickerArt.drawable(for: item.body) {
                MessagesStickerBubble(art: drawn.art, isPending: true)
            } else {
                MessagesBubbleText(text: item.body, isMine: true, isPending: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("나: \(AingStickerText.preview(for: item.body)), " + (item.state == .sending ? "보내는 중" : "보냄")))
    }
}
#endif
