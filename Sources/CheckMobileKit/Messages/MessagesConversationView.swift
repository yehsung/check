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
/// 신고는 사유 시트를 지나야 서버로 나간다(소스 계약). 받은 말풍선을 길게 누르면 그 **메시지 한 건**을 신고한다
/// (1.0.17 부터 글 말풍선은 iOS 고르기 뒤 편집 메뉴의 [신고], 이모티콘 말풍선은 예전 길게 누름 메뉴의 [신고] — 같은 `reportMessage`).
///
/// 1.0.13: 말풍선 사이에 **찌르기 줄**(가운데 정렬 작은 회색 줄)이 시간 순서로 낀다 — 줄 만들기는
/// `MessagesStore.conversationItems`(→ `MessagesConversationRules.items` → 코어 `MessageConversationTimeline`),
/// 모양은 `MessagesPokeLogRow` 다.
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
        // 상대가 집중 중인가(1.0.17 · 대표 요청 5) — 이름표 '집중 중' 칩. 판(`board`)이 아니라 스토어 판정이다: 입력줄 잠금과 같은 값이어야 하고,
        // 판은 이름을 알 때만 계산한다(이름 모르는 대화도 잠금은 선다). 내 집중은 칩이 아니라 입력줄 사유 줄이 말한다(칩은 상대의 상태다).
        let peerFocused = store.isPeerFocused(peerID)
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
                // 찌르기 줄도 "마지막 줄"이다 — 내가 맥에서 찌른 줄이 들어오면 바닥을 따라간다(`MessagesConversationItem.isMine`).
                let isMine = items.last?.isMine ?? false
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
                MessagesConversationNameplate(header: header, presence: presence, statusMessage: statusMessage, isFocused: peerFocused)
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
        case .poke(let line):
            // 찌르기 줄 — 말풍선이 아니라 가운데 작은 회색 줄이다. 답장·읽음 표시·신고 대상이 아니다.
            MessagesPokeLogRow(line: line)
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
    /// 상대가 집중 중인가(1.0.17 · 대표 요청 5 — `MessagesStore.isPeerFocused`). 이름 옆 '집중 중' 칩(맥 대화 머리 `MessagePeerFocusChip` 의 폰 짝).
    /// **이름표 높이를 늘리지 않는다** — 칩은 이름 줄 안에 서고(small 18pt ≈ 이름 줄 높이), 폭은 이름이 양보한다(꼬리 줄임표).
    var isFocused: Bool = false

    var body: some View {
        let line = MessagesPresenceRules.headerLine(presence)
        VStack(spacing: 1) {
            HStack(spacing: 6) {
                Text(header.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .lineLimit(1)
                if isFocused {
                    FocusChip(text: MessagesFocusText.conversationChip)
                }
            }
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
        .accessibilityLabel(Text([header.accessibilityLabel, isFocused ? MessagesFocusText.accessibility : nil, line,
                                  statusMessage.map { "상태메시지 \($0)" }]
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
                bubbleContent
            } else {
                bubbleContent
                meta
                Spacer(minLength: oppositeInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: entry.isMine ? .trailing : .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAction(named: Text(MessagesBubbleCopy.title)) { MessagesBubbleCopy.copy(entry.body) }
        // 보이스오버는 길게 누름 메뉴를 못 연다 — 신고도 동작으로 단다(복사와 같은 자리).
        // 줄이 요소 하나(children: .ignore)라 링크 글자에 닿을 수 없다 — 링크마다 "링크 열기: 글 (호스트)" 동작을 단다(1.0.17).
        // 여는 문은 손가락 누름과 같은 한 곳이다(`MessagesBubbleLinkDoor` — 스킴 검사 두 겹).
        .accessibilityActions {
            ForEach(linkActions, id: \.self) { link in
                Button(link.title) { MessagesBubbleLinkDoor.open(link.url) }
            }
            if let onReport {
                Button(BlockReportText.reportMessageAction, action: onReport)
            }
        }
    }

    /// 이 말풍선의 링크들(보이스오버 동작). 그림 말풍선은 글이 "아잉이 기쁨"이라 링크가 없다.
    private var linkActions: [MessagesBubbleMarkdown.LinkAction] {
        MessagesBubbleMarkdown.linkActions(AingStickerText.preview(for: line.entry.body))
    }

    /// 이모티콘 말풍선의 길게 누름 메뉴 — [복사](원문 토큰 그대로 — 붙여넣어 다시 보내면 그림이 된다) · [신고](받은 말풍선만).
    /// 1.0.16 까지는 모든 말풍선의 메뉴였다. 1.0.17 부터 **글 말풍선에는 이 메뉴가 없다**(대표 답 #d_M9wR9l9VLNvx "말풍선에서 바로 길게 눌러 고르기"):
    /// 글 칸이 길게 누르기를 iOS 고르기로 받고, [복사] · [전체 선택] · [번역] + [신고]는 그 편집 메뉴에 선다(`MessagesBubbleTextUIView`).
    /// 들어 올림 미리보기도 이모티콘 말풍선에만 남는다.
    @ViewBuilder
    private var stickerMenu: some View {
        Button {
            MessagesBubbleCopy.copy(line.entry.body)
        } label: {
            Label(MessagesBubbleCopy.title, systemImage: "doc.on.doc")
        }
        if let onReport {
            Button(role: .destructive, action: onReport) {
                Label(BlockReportText.reportMessageAction, systemImage: MessagesBubbleSelection.reportSymbol)
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
    /// 길게 누르기는 갈래마다 다르다: 그림은 SwiftUI 메뉴(`stickerMenu` · 그림 사각형 미리보기), 글자는 글 칸의 iOS 고르기 · 편집 메뉴다.
    @ViewBuilder
    private var bubbleContent: some View {
        if let drawn = AingStickerArt.drawable(for: line.entry.body) {
            MessagesStickerBubble(art: drawn.art)
                .contentShape(.contextMenuPreview, Rectangle())
                .contextMenu { stickerMenu }
        } else {
            // 그림 길이 아니면 글자 말풍선이다. ★ 번들 그림을 못 읽은 이모티콘은 **날것 토큰이 아니라**
            // "아잉이 기쁨"으로 접는다 — `AingStickerArt` 머리말의 계약이고 맥이 하는 것과 같다(`[아잉:기쁨]` 은
            // "깨진 메시지"로 읽힌다). 평범한 본문은 `preview` 가 **손대지 않고** 그대로 돌려준다.
            // 고른 글 복사는 보이는 글자(꼬리표 대신 실제 주소)이고, 보이스오버 [복사]는 `entry.body` 원문 그대로다 — 이 줄은 **보여 주는 글자**만 바꾼다.
            // 받은 말풍선이면 `onReport` 가 편집 메뉴의 [신고]가 된다(내 말풍선은 nil — 메뉴에 없다).
            // 그림을 못 읽은 이모티콘은 글 전체를 골라 [복사]하면 원문 토큰을 담는다(`wholeCopyRaw` — 1.0.16 길게 누름 [복사]와 같은 값).
            MessagesBubbleText(text: AingStickerText.preview(for: line.entry.body), isMine: line.entry.isMine, onReport: onReport,
                               wholeCopyRaw: MessagesBubbleSelection.wholeCopyRaw(body: line.entry.body))
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
    ///   보이스오버가 대괄호 토큰을 또박또박 읽는다. 평범한 한 줄 본문은 한 글자도 안 바뀐다.
    /// 1.0.17: 서식 기호(`## ` · `**` · `[글](주소)`)도 벗겨 읽는다 — `ChatMarkdown.plainPreview`(이모티콘 규칙을 먼저 거친다 · 맥 한 줄 자리와 같은 함수).
    ///   링크가 여는 곳은 링크마다 단 동작 이름이 말한다("링크 열기: 글 (호스트)").
    private var accessibilityText: String {
        let entry = line.entry
        var parts = [(entry.isMine ? "나" : entry.peerName) + ": " + ChatMarkdown.plainPreview(entry.body), line.clockText]
        if line.showsUnreadOne { parts.append(MessagesConversationRules.unreadOneAccessibilityLabel) }
        return parts.joined(separator: ", ")
    }
}

/// 고른 것 없는 말풍선 복사(이모티콘 말풍선의 길게 누름 메뉴 · 보이스오버 동작). 늘 원문을 담는다 — 맥 [복사]의 "고른 글자가 없으면 원문"과
/// 같은 규칙이다(`ChatMarkdownCopy.menuText`). 원문은 서식 기호 · 이모티콘 토큰 그대로라 붙여넣어 다시 보내면 같은 꾸밈 · 같은 그림이 된다.
/// 붙여넣기판에는 서식 없는 글자만 쓴다(`string`). 글 말풍선에서 **고른 글자**의 복사는 글 칸 몫이다(`MessagesBubbleTextUIView.copy` —
/// 보이는 글자 · 링크는 실제 주소째).
enum MessagesBubbleCopy {
    static let title = "복사"

    @MainActor
    static func copy(_ body: String) {
        UIPasteboard.general.string = body
    }
}

/// 말풍선 링크를 여는 **한 문**(손가락 누름 · 보이스오버 동작). 스킴 검사(`MessagesBubbleMarkdown.follow` → `ChatMarkdown.isOpenable`)를
/// 지난 http·https 만 시스템에 넘긴다 — 기본 브라우저(유니버설 링크면 그 앱)가 연다.
@MainActor
enum MessagesBubbleLinkDoor {
    static func open(_ url: URL) {
        MessagesBubbleMarkdown.follow(url) { UIApplication.shared.open($0) }
    }
}

/// 링크 누름 인식기의 대리자 — **링크 글자 위에서, 고르는 중이 아닐 때만** 누름을 시작시킨다. 그 밖의 누름은 인식기가 아예 시작하지 않아
/// 스크롤 · 길게 누르기(iOS 고르기) · 고른 것을 지우는 누름 · 다른 손짓이 글 칸 그대로다.
///
/// ★ 말풍선 뷰의 `UIView.gestureRecognizerShouldBegin(_:)` 를 재정의하지 않는다 — 그 메서드는 이 뷰를 지나는 **다른 인식기**(바깥 스크롤
///   끌기 · 글 칸의 고르기 인식기)에도 불릴 수 있어, 링크 밖에서 false 를 주면 말풍선 위 스크롤 · 고르기까지 막힐 수 있다. 이 인식기 하나만 따로 묻는다.
/// ★ 고르는 중(고른 글자가 있다)엔 시작하지 않는다(`MessagesBubbleSelection.linkToOpen`) — 그때 링크 위 한 번 누름은 고른 것을 지우는 누름이다.
@MainActor
final class MessagesBubbleLinkTapGate: NSObject, UIGestureRecognizerDelegate {
    weak var bubble: MessagesBubbleTextUIView?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let bubble else { return false }
        return MessagesBubbleSelection.linkToOpen(
            selectedLength: bubble.selectedRange.length,
            linkAtTap: bubble.link(at: gestureRecognizer.location(in: bubble))
        ) != nil
    }
}

/// 말풍선 글자 + 바탕(시안 `.b-bub`: 16pt · 안쪽 8/13/9 · 반경 19). 보내는 중 자리 말풍선도 같은 모양을 흐리게 쓴다.
/// 1.0.17: 안쪽 여백은 SwiftUI padding 이 아니라 **글 칸 안**이다(`MessagesBubbleTextLayout.bubbleInsets` — 값은 예전 그대로) —
/// 여백 띠를 길게 눌러도 고르기 · 편집 메뉴가 뜬다. 바탕(둥근 판)만 SwiftUI 가 그린다.
private struct MessagesBubbleText: View {
    static let cornerRadius: CGFloat = 19

    let text: String
    let isMine: Bool
    var isPending = false
    /// 편집 메뉴의 [신고](받은 말풍선만). 내 말풍선 · 보내는 중 말풍선은 nil — 메뉴에 없다.
    var onReport: (() -> Void)?
    /// 글 전체를 골라 복사할 때 대신 담을 원문(보이는 글자가 원문과 다른 말풍선 — `MessagesBubbleSelection.wholeCopyRaw`). 평범한 글은 nil.
    var wholeCopyRaw: String?

    var body: some View {
        MessagesBubbleLabel(text: text, isMine: isMine, onReport: onReport, wholeCopyRaw: wholeCopyRaw)
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
///
/// 1.0.17: 서식(제목 · 굵게 · 링크 + 호스트 꼬리표 — 대표 결정 "제목·굵게·링크만")을 그린다. 무엇을 그리는가는 코어 조각(맥과 한 벌),
/// 폰 글꼴 · 색은 `MessagesBubbleMarkdown` 이 입힌다. `text` 는 이모티콘 폴백을 지난 본문이다(마크다운 해석은 그 뒤 — 맥과 같은 순서).
/// 1.0.17 골라 복사: 이 칸은 고를 수 있는 글 칸이다(`MessagesBubbleTextUIView`). 크기는 **말풍선 한 장**(안쪽 여백 포함)이다.
private struct MessagesBubbleLabel: UIViewRepresentable {
    let text: String
    let isMine: Bool
    var onReport: (() -> Void)?
    var wholeCopyRaw: String?

    func makeUIView(context: Context) -> MessagesBubbleTextUIView {
        MessagesBubbleTextUIView()
    }

    /// 글은 **보이는 것이 바뀔 때만** 다시 박는다(`show` 가 열쇠로 견준다) — SwiftUI 는 대화 화면이 다시 그려질 때마다(명부 · 새 메시지 · 틱)
    /// 이 함수를 부르고, 그때마다 글을 박으면 고르던 구간이 날아간다(외관별 색 객체는 매번 새것이라 글 비교로는 못 거른다).
    func updateUIView(_ view: MessagesBubbleTextUIView, context: Context) {
        view.onReport = onReport
        view.wholeCopyRaw = wholeCopyRaw
        view.show(MessagesBubbleTextUIView.Shown(text: text, isMine: isMine, dynamicTypeSize: context.environment.dynamicTypeSize)) {
            MessagesBubbleMarkdown.attributed(
                text,
                fonts: MessagesBubbleMarkdown.fonts(for: context.environment.dynamicTypeSize),
                colors: MessagesBubbleMarkdown.colors(isMine: isMine)
            )
        }
    }

    /// 말풍선 한 장 크기 = 여백 뺀 폭에서 잰 글 크기 + 여백(1.0.16 의 padding + `fittingSize` 와 같은 값). 재는 것은 **재기 전용 엔진**이다 —
    /// SwiftUI 가 여러 폭(0 포함)을 물어도 그려 놓은 배치를 흔들지 않는다.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: MessagesBubbleTextUIView, context: Context) -> CGSize? {
        view.measure.bubbleFittingSize(proposedWidth: proposal.width)
    }
}

/// 말풍선 본문 글 칸 — **고를 수 있는(편집 불가) `UITextView`**(1.0.17 · 대표 답 #d_M9wR9l9VLNvx "말풍선에서 바로 길게 눌러 고르기").
/// 보이스오버는 줄 전체 라벨 · 동작이 읽는다(이 칸은 요소가 아니다 — 줄이 `children: .ignore`).
///
/// ## 줄바꿈 · 크기는 예전 엔진 그대로
/// TextKit 1 틀째 `MessagesBubbleTextLayout.Engine` 의 것을 넘겨 짓는다(`init(frame:textContainer:)` — TextKit 2 가 아니다). 줄을 나누는 것은
/// 그 엔진의 배치 관리자와 어절 끊기 대리자이고, 줄 조각 여백 0 · 안쪽 여백(`bubbleInsets`)은 예전 SwiftUI padding 과 같은 값이다.
/// 크기는 같은 글을 넣은 **재기 전용 엔진**(`measure`)이 잰다(`Engine.bubbleFittingSize`).
///
/// ## 길게 누르기 → iOS 고르기 · 편집 메뉴
/// 메뉴는 iOS 가 제안한 것 가운데 [복사] · [전체 선택] · [번역]만 남기고, 받은 말풍선이면 [이 메시지 신고하기]를 끝에 단다
/// (`MessagesBubbleSelection.menu` — 공유 · 찾아보기 등은 거른다). [복사]는 고른 글자를 서식 없이, 링크는 실제 주소째 담는다(`copy`).
/// 들어 올림 미리보기는 없다(바깥 `.contextMenu` 를 걷었다). 고르는 동안 이 칸이 첫 응답자가 되어 입력칸 키보드가 내려간다(iOS 고르기의 성질).
///
/// ## 링크
/// 링크는 **한 번 눌러** 연다(대표 요청 "링크같은건 클릭해서 실제 해당 링크로 브라우저 열리게"). 누름 인식기는 링크 글자 위에서, 고르는 중이 아닐 때만
/// 시작한다(`MessagesBubbleLinkTapGate`). 링크는 시스템 `.link` 속성이 아니라 직접 정한 키라 이 글 칸에 링크 항목이 없다 — 시스템의
/// 검사 없는 열기 · 길게 눌러 웹 미리보기가 생기지 않는다. 혹시 생겨도 링크 항목 대리자 둘이 nil(막음)을 돌려준다. 자료 감지도 끈다.
final class MessagesBubbleTextUIView: UITextView, UITextViewDelegate {
    /// 보이는 글의 열쇠 — 같으면 글을 다시 박지 않는다(고르던 구간이 날아간다).
    struct Shown: Equatable {
        let text: String
        let isMine: Bool
        let dynamicTypeSize: DynamicTypeSize
    }

    /// 그리는 배치 — 이 글 칸의 TextKit 1 틀(어절 끊기 대리자째). 링크 누름도 이 배치로 잰다.
    let engine: MessagesBubbleTextLayout.Engine
    /// 크기 재기 전용 엔진(같은 글). SwiftUI 가 묻는 여러 폭이 그리는 배치를 흔들지 않게 따로 둔다.
    let measure = MessagesBubbleTextLayout.Engine()
    /// 편집 메뉴의 [이 메시지 신고하기]. nil 이면 메뉴에 신고가 없다(내 말풍선 · 보내는 중).
    var onReport: (() -> Void)?
    /// 글 전체를 골라 [복사]하면 대신 담을 원문(그림을 못 읽은 이모티콘의 토큰). nil 이면 보이는 글자다(`MessagesBubbleSelection.copyText`).
    var wholeCopyRaw: String?

    private var shown: Shown?
    private let linkTapGate = MessagesBubbleLinkTapGate()

    init() {
        let engine = MessagesBubbleTextLayout.Engine()
        engine.prepareForTextView()
        self.engine = engine
        super.init(frame: .zero, textContainer: engine.container)
        // 넘긴 틀은 글 칸이 그대로 쓴다 — 혹시 바뀌어도 재는 엔진과 같은 값으로 되돌린다(어절 끊기 대리자 · 줄 조각 여백 0).
        if engine.layoutManager.delegate !== engine { engine.layoutManager.delegate = engine }
        engine.container.lineFragmentPadding = 0
        isEditable = false
        isSelectable = true
        isScrollEnabled = false
        // 말풍선마다 이 글 칸(UIScrollView)이 있다 — 켜 두면 화면에 scrollsToTop 후보가 여럿이라 상태 막대 누름(맨 위로)이 듣지 않을 수 있다.
        // 맨 위로 가는 것은 대화의 바깥 스크롤 하나다.
        scrollsToTop = false
        backgroundColor = .clear
        // 고르기 손잡이가 말풍선 가장자리에서 잘리지 않게(글자는 늘 글 칸 안이다).
        clipsToBounds = false
        let insets = MessagesBubbleTextLayout.bubbleInsets
        textContainerInset = UIEdgeInsets(top: insets.top, left: insets.horizontal, bottom: insets.bottom, right: insets.horizontal)
        contentInset = .zero
        contentInsetAdjustmentBehavior = .never
        adjustsFontForContentSizeCategory = false
        dataDetectorTypes = []
        isFindInteractionEnabled = false
        writingToolsBehavior = .none
        // 끌어 놓기는 보이는 글자(꼬리표째 · 서식째)를 싣는다 — 고른 글은 [복사]로만 나간다.
        textDragInteraction?.isEnabled = false
        isAccessibilityElement = false
        // 하위 요소(글자 줄 · 링크)까지 숨긴다 — `isAccessibilityElement = false` 만으로는 UITextView 의 접근성 컨테이너가 남아, 줄 라벨과 따로
        // 말풍선 글이 한 번 더 읽힐 수 있다. 줄(`children: .ignore`)이 라벨 · [복사] · [신고] · 링크 열기 동작을 따로 들고 있어 잃는 것이 없다.
        accessibilityElementsHidden = true
        delegate = self
        // 외관(라이트·다크 · 앱 화면 모드 설정)이 바뀌면 테마 색을 다시 풀어 그린다.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MessagesBubbleTextUIView, _: UITraitCollection) in
            view.redrawText()
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tappedLink(_:)))
        linkTapGate.bubble = self
        tap.delegate = linkTapGate
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 보일 글을 바꾼다. 열쇠가 같으면 아무것도 안 한다(고르던 구간 · 편집 메뉴가 그대로다). 바뀌면 고른 것을 지우고
    /// 그리는 엔진 · 재는 엔진에 **같은 글**을 넣는다.
    func show(_ next: Shown, drawn: () -> NSAttributedString) {
        guard shown != next else { return }
        shown = next
        let text = drawn()
        if selectedRange.length > 0 { selectedRange = NSRange(location: 0, length: 0) }
        engine.set(text)
        measure.set(text)
        tintColor = MobileTheme.uiColor(MessagesBubbleSelection.selectionTint(isMine: next.isMine))
    }

    private func redrawText() {
        engine.layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: engine.storage.length))
        setNeedsDisplay()
    }

    // MARK: 링크

    /// 이 칸의 `point`(뷰 좌표 — 안쪽 여백 포함)에 있는 링크. 그린 폭 그대로 배치해 잰다.
    func link(at point: CGPoint) -> URL? {
        engine.link(atBubblePoint: point, bubbleWidth: bounds.width)
    }

    @objc private func tappedLink(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let url = MessagesBubbleSelection.linkToOpen(selectedLength: selectedRange.length, linkAtTap: link(at: recognizer.location(in: self)))
        else { return }
        MessagesBubbleLinkDoor.open(url)
    }

    // MARK: 복사

    /// 편집 메뉴 [복사] · 키보드 ⌘C. **고른 글자만**, **서식 없이** 쓴다 — `[글](주소)` 는 꼬리표 대신 실제 주소째(코어 `ChatMarkdownCopy.text` —
    /// 맥 ⌘C 와 한 함수). 서식째 쓰면 내 말풍선의 흰 글자가 흰 문서에 붙는다. 고른 것이 없으면 아무것도 안 쓴다.
    override func copy(_ sender: Any?) {
        guard let text = MessagesBubbleSelection.copyText(engine.storage, selected: selectedTextRanges, wholeTextRaw: wholeCopyRaw) else { return }
        UIPasteboard.general.string = text
    }

    /// 고른 구간들. iOS 26 부터 여러 구간 선택이 있고 `selectedRange` 는 그 **합집합**이다(SDK 27.2 머리말) — 합집합을 담으면 고르지 않은
    /// 사이 글이 섞인다. iOS 18~25 는 한 구간이다.
    private var selectedTextRanges: [NSRange] {
        if #available(iOS 26.0, *) { return selectedRanges }
        return [selectedRange]
    }

    /// 편집 메뉴 밖의 길(키보드 단축키 등)에서도 공유는 거절한다(보이는 글자를 꼬리표째 다른 앱으로 넘긴다).
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if MessagesBubbleSelection.refuses(actionNamed: NSStringFromSelector(action)) { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    /// 포커스가 떠나면 고른 것을 지운다 — 다른 말풍선 · 입력칸으로 옮긴 뒤 옛 강조가 남아 여러 말풍선이 함께 골라진 것처럼 보이지 않게(맥과 같다).
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, selectedRange.length > 0 { selectedRange = NSRange(location: 0, length: 0) }
        return resigned
    }

    // MARK: 편집 메뉴

    /// 고른 뒤 뜨는 편집 메뉴. **언제나 메뉴를 돌려준다** — nil 은 "시스템 기본 메뉴"(공유 · 찾아보기 포함)라는 뜻이다.
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        UIMenu(children: MessagesBubbleSelection.menu(suggested: Self.leaves(suggestedActions), report: reportMenuItem(),
                                                      fallbackCopy: ownCopyMenuItem(range: range)))
    }

    /// 보험 [복사] — 제안에서 [복사]를 못 알아봤을 때만 메뉴에 선다(`MessagesBubbleSelection.menu` 의 `fallbackCopy`). 이 글 칸의 `copy(_:)` 를
    /// 그대로 부르므로 담는 글자 규칙이 같다. 고른 글자가 없으면 세우지 않는다.
    private func ownCopyMenuItem(range: NSRange) -> UIMenuElement? {
        guard range.length > 0 else { return nil }
        return UIAction(title: MessagesBubbleCopy.title, image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
            self?.copy(nil)
        }
    }

    /// 제안 메뉴를 펼친 낱 항목(이름 · 항목). 묶음 메뉴는 속까지 펼친다. 이름을 모르는 항목(미뤄 짓는 항목 등)은 버린다.
    private static func leaves(_ elements: [UIMenuElement]) -> [(name: String, element: UIMenuElement)] {
        elements.flatMap { element -> [(name: String, element: UIMenuElement)] in
            if let menu = element as? UIMenu { return leaves(menu.children) }
            if let command = element as? UICommand { return [(NSStringFromSelector(command.action), command)] }
            if let action = element as? UIAction { return [(action.identifier.rawValue, action)] }
            return []
        }
    }

    /// [이 메시지 신고하기](받은 말풍선만 — `onReport` 가 있을 때). 맥 · 이모티콘 메뉴와 같은 신고 흐름(메시지 한 건 · 사유 시트)이다.
    private func reportMenuItem() -> UIMenuElement? {
        guard onReport != nil else { return nil }
        return UIAction(
            title: BlockReportText.reportMessageAction,
            image: UIImage(systemName: MessagesBubbleSelection.reportSymbol),
            attributes: .destructive
        ) { [weak self] _ in
            self?.reportFromMenu()
        }
    }

    private func reportFromMenu() {
        if selectedRange.length > 0 { selectedRange = NSRange(location: 0, length: 0) }
        _ = resignFirstResponder()
        onReport?()
    }

    // MARK: 링크 항목 — 막음(이 칸에는 `.link` · 자료 감지가 없어 불리지 않는다. 생겨도 검사 없는 열기 · 웹 미리보기가 없게)

    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        nil
    }

    func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
        nil
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
                // 자리 말풍선도 같은 폴백을 쓴다(위 말풍선 주석).
                MessagesBubbleText(text: AingStickerText.preview(for: item.body), isMine: true, isPending: true,
                                   wholeCopyRaw: MessagesBubbleSelection.wholeCopyRaw(body: item.body))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        // 줄 라벨은 서식 기호를 벗겨 읽는다(위 말풍선 줄 라벨과 같은 함수).
        .accessibilityLabel(Text("나: \(ChatMarkdown.plainPreview(item.body)), " + (item.state == .sending ? "보내는 중" : "보냄")))
    }
}
#endif
