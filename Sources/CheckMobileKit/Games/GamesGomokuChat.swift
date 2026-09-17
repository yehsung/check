#if os(iOS)
import CheckCore
import SwiftUI

/// 대국·결과 화면 아래 **반쯤 올라온 대화 서랍**(시안 B 09 `.b-chatpeek`) — 판과 함께 보인다(비평: 채팅하려면 판을 화면 밖으로 밀어야 했다).
///
/// - 접힘: 끌개 · 머리(대화 · [대화 끄기]) · 최근 말 둘 · 빠른 문구 가로 줄 + [키보드].
/// - 펼침(끌개·[키보드]·머리 누름): 대화 전체(스크롤) · 빠른 문구 · 상태 줄 · 입력칸(100자, 80자부터 카운터).
///
/// 맥 `GomokuChatCard` 와 같은 규칙: 음소거는 서버가 아는 판 상태라 상대에게도 표시된다 · 실패한 말은 초안에 남는다 ·
/// 상대가 껐다/옛 버전이다는 **조건이 참인 동안** 서 있다 · 채팅 왕복은 착수·기권을 잠그지 않는다.
/// 말풍선(둥근 네모 · 받은 회색/보낸 파랑)과 빠른 문구(회색 알약)는 모양을 갈라 둔다(비평: 둘이 거의 같아 헷갈렸다).
struct GamesGomokuChatDrawer: View {
    @Bindable var store: GomokuStore
    @Binding var isExpanded: Bool

    @FocusState private var inputFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme

    private static let bottomAnchor = "gomoku-phone-chat-bottom"

    private var length: Int { store.chatDraftLength }
    private var isOverflowing: Bool { length > store.chatMaxLength }
    private var showsCounter: Bool { Double(length) >= Double(store.chatMaxLength) * GomokuPhoneText.chatCounterFromRatio }

    /// 접근성 글자 크기 + 접힘 = **머리 한 줄만**. 최근 말·빠른 문구까지 그리면 서랍이 판과 '내 차례 · 남은 초' 카드를 통째로 덮었다
    /// (w15 검증 medium 6 — AX 실측: 초록 테두리 카드의 윗선만 남았다). 대국에서 가장 중요한 상태가 가려지는 것보다, 말하려면 한 번 펴는 쪽이 낫다.
    private var isCompact: Bool { typeSize.isAccessibilitySize && !isExpanded }

    /// 접힌 서랍에 남기는 최근 말 수 — 글자가 커질수록 줄인다(XL 이상은 한 줄).
    private var collapsedLogCount: Int { typeSize >= .xxLarge ? 1 : 2 }

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            grabber
            header
            if !isCompact {
                log
                    .padding(.top, 4)
                quickPhrases
                    .padding(.top, 6)
            }
            statusLines
            if isExpanded {
                composer
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 14)
        .background {
            GlassBackground(shape: shape)
                .ignoresSafeArea(edges: .bottom)
        }
        .padding(.horizontal, 8)
        .animation(.easeOut(duration: 0.2), value: isExpanded)
        .onChange(of: inputFocused) { _, focused in
            if focused { isExpanded = true }
        }
    }

    // MARK: 머리

    private var grabber: some View {
        Button {
            toggle()
        } label: {
            Capsule()
                .fill(MobileTheme.label3)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity, minHeight: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? GomokuPhoneText.chatClose : GomokuPhoneText.chatOpen)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(GomokuPhoneText.chatTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MobileTheme.label)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MobileTheme.label2)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: GamesTouchTarget.minimum)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(isExpanded ? GomokuPhoneText.chatClose : GomokuPhoneText.chatOpen)
            Spacer(minLength: 8)
            // 접혀서 빠른 문구 줄이 없는 동안에도 쓰는 길은 한 번에 — 머리 안으로 들인다.
            if isCompact { keyboardButton }
            Button {
                store.setChatMuted(!store.isMuted)
            } label: {
                Label(store.isMuted ? GomokuPhoneText.chatUnmuteAction : GomokuPhoneText.chatMuteAction,
                      systemImage: store.isMuted ? "bell" : "bell.slash")
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.accent)
                    .frame(minHeight: GamesTouchTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.isSendingChat)
            .accessibilityHint(store.isMuted ? "상대 말을 다시 받아요" : "상대 말을 꺼요 · 상대에게도 표시돼요")
        }
        .frame(minHeight: 32)
        .padding(.top, -6)
        .padding(.bottom, -6)
    }

    private func toggle() {
        isExpanded.toggle()
        if !isExpanded { inputFocused = false }
    }

    // MARK: 대화

    @ViewBuilder
    private var log: some View {
        if store.isMuted {
            centered(GomokuNoticeText.chatMutedByMe)
        } else if store.chat.isEmpty {
            centered(GomokuPhoneText.chatEmpty)
        } else if isExpanded {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.chat) { message in
                            GamesGomokuChatBubble(message: message)
                        }
                        Color.clear.frame(height: 1).id(Self.bottomAnchor)
                    }
                }
                .defaultScrollAnchor(.bottom)
                .frame(minHeight: 60, maxHeight: 220)
                .onAppear { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
                .onChange(of: store.chat.last?.seq) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
                }
            }
        } else {
            // 접힘: 최근 둘만(판을 가리지 않는 높이) · 글자가 크면 하나만.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.chat.suffix(collapsedLogCount)) { message in
                    GamesGomokuChatBubble(message: message)
                }
            }
        }
    }

    private func centered(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(MobileTheme.label2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    // MARK: 빠른 문구

    @ViewBuilder
    private var quickPhrases: some View {
        // 접근성 글자 크기 + 펼침: 알약을 세로로 쌓는다(가로 한 줄에서는 한 번에 하나만 보였다) — 높이 상한 안에서 스크롤.
        // 접힘은 글자 크기와 무관하게 가로 한 줄이다(세로로 쌓으면 서랍이 판을 통째로 덮었다 — AX3 스크린샷 실측).
        if typeSize.isAccessibilitySize, isExpanded {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(GomokuQuickPhrase.allCases, id: \.rawValue) { phrase in quickChip(phrase) }
                }
            }
            .frame(maxHeight: 200)
        } else {
            HStack(spacing: 6) {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(GomokuQuickPhrase.allCases, id: \.rawValue) { phrase in quickChip(phrase) }
                    }
                }
                .scrollIndicators(.hidden)
                if !isExpanded { keyboardButton }
            }
        }
    }

    private func quickChip(_ phrase: GomokuQuickPhrase) -> some View {
        Button {
            store.sendQuick(phrase)
        } label: {
            Text(phrase.text)
                .font(.subheadline)
                .foregroundStyle(MobileTheme.label)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(Capsule().fill(MobileTheme.fill))
                // 보이는 알약은 32 · 누르는 곳은 44.
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isSendingChat)
    }

    private var keyboardButton: some View {
        Button {
            isExpanded = true
            Task { @MainActor in inputFocused = true }
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MobileTheme.label)
                .frame(width: 32, height: 32)
                .background(Circle().fill(MobileTheme.fill))
                .frame(width: GamesTouchTarget.minimum, height: GamesTouchTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GomokuPhoneText.chatWrite)
    }

    // MARK: 상태 · 입력

    @ViewBuilder
    private var statusLines: some View {
        if let notice = store.chatNotice, !notice.isEmpty {
            statusLine(notice, tint: MobileTheme.pending)
        }
        if store.isOpponentMuted {
            statusLine(GomokuNoticeText.chatMutedByOpponent, tint: MobileTheme.pending)
        }
        if !store.opponentChatCapable {
            statusLine(GomokuNoticeText.chatOpponentOutdated, tint: MobileTheme.label2)
        }
    }

    private func statusLine(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            // 한 줄 입력칸 — 키보드의 보내기 키가 곧 전송이다(여러 줄 입력칸은 ↩ 가 줄바꿈이라 onSubmit 이 오지 않는다).
            // 한글 조합 중에는 보내기 키가 먼저 조합을 확정하고 onSubmit 이 온다(마지막 음절이 빠지지 않는다).
            TextField(text: $store.chatDraft) {
                Text(GomokuPhoneText.chatPlaceholder).foregroundStyle(MobileTheme.label3Text)
            }
            .font(.body)
            .foregroundStyle(MobileTheme.label)
            .submitLabel(.send)
            .focused($inputFocused)
            .onSubmit { store.sendChatDraft() }
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Capsule().fill(MobileTheme.fill))
            .overlay(Capsule().strokeBorder(isOverflowing ? MobileTheme.danger : Color.clear, lineWidth: 1))
            if showsCounter {
                Text("\(length)/\(store.chatMaxLength)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isOverflowing ? MobileTheme.danger : MobileTheme.label2)
            }
            Button {
                store.sendChatDraft()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MobileTheme.onAccentFill)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(MobileTheme.accentFill))
                    .opacity(store.canSendChatNow ? 1 : 0.38)
                    .frame(width: GamesTouchTarget.minimum, height: GamesTouchTarget.minimum)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.canSendChatNow)
            .accessibilityLabel(GomokuPhoneText.chatSend)
        }
    }
}

/// 말풍선 하나(내 것 오른쪽 파랑 · 받은 것 왼쪽 회색 — 시안 `.b-chat-msgs .b-bub`).
private struct GamesGomokuChatBubble: View {
    let message: GomokuChatMessage

    var body: some View {
        HStack(spacing: 0) {
            if message.isMine { Spacer(minLength: 48) }
            Text(message.body)
                .font(.subheadline)
                .foregroundStyle(message.isMine ? MobileTheme.onAccentFill : MobileTheme.label)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(message.isMine ? MobileTheme.accentFill : MobileTheme.bubbleIn)
                )
            if !message.isMine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel((message.isMine ? "나: " : "상대: ") + message.body)
    }
}
#endif
