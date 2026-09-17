#if os(iOS)
import CheckCore
import SwiftUI

/// 대국·결과 화면의 채팅 카드: 머리글(대화 · 끄기/켜기) · 대화 로그(최신이 아래) · 빠른 문구 여덟 · 입력(100자, 80자부터 카운터).
///
/// 맥 `GomokuChatCard` 와 같은 규칙: 음소거는 서버가 아는 판 상태라 상대에게도 표시된다 · 실패한 말은 초안에 남는다 ·
/// 상대가 껐다/옛 버전이다는 **조건이 참인 동안** 입력칸 위에 서 있다 · 채팅 왕복은 착수·기권을 잠그지 않는다.
struct GamesGomokuChatCard: View {
    @Bindable var store: GomokuStore

    @FocusState private var inputFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let bottomAnchor = "gomoku-phone-chat-bottom"

    private var length: Int { store.chatDraftLength }
    private var isOverflowing: Bool { length > store.chatMaxLength }
    private var showsCounter: Bool { Double(length) >= Double(store.chatMaxLength) * GomokuPhoneText.chatCounterFromRatio }

    var body: some View {
        AingCard(padding: 12) {
            header
            log
            quickPhrases
            statusLines
            composer
        }
    }

    private var header: some View {
        HStack {
            Text(GomokuPhoneText.chatTitle)
                .font(.headline)
                .foregroundStyle(MobileTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                store.setChatMuted(!store.isMuted)
            } label: {
                Label(store.isMuted ? GomokuPhoneText.chatUnmute : GomokuPhoneText.chatMute,
                      systemImage: store.isMuted ? "bell.slash.fill" : "bell.fill")
            }
            .buttonStyle(GamesCompactButtonStyle(kind: store.isMuted ? .filled : .outline))
            .disabled(store.isSendingChat)
            .accessibilityHint(store.isMuted ? "상대 말을 다시 받아요" : "상대 말을 꺼요 · 상대에게도 표시돼요")
        }
    }

    @ViewBuilder
    private var log: some View {
        if store.isMuted {
            centered(GomokuNoticeText.chatMutedByMe)
        } else if store.chat.isEmpty {
            centered(GomokuPhoneText.chatEmpty)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(store.chat) { message in
                            GamesGomokuChatBubble(message: message)
                        }
                        Color.clear.frame(height: 1).id(Self.bottomAnchor)
                    }
                }
                .defaultScrollAnchor(.bottom)
                .frame(minHeight: 60, maxHeight: 180)
                .onAppear { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
                .onChange(of: store.chat.last?.seq) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
                }
            }
        }
    }

    private func centered(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(MobileTheme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }

    /// 빠른 문구 열 — 접근성 글자 크기에서는 한 열(세 열에 두면 "한 수 부탁…"처럼 잘렸다, AX5 스크린샷 실측).
    private var quickPhraseColumns: [GridItem] {
        typeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 6)]
            : [GridItem(.adaptive(minimum: 104), spacing: 6)]
    }

    private var quickPhrases: some View {
        let wraps = typeSize.isAccessibilitySize
        return LazyVGrid(columns: quickPhraseColumns, spacing: 6) {
            ForEach(GomokuQuickPhrase.allCases, id: \.rawValue) { phrase in
                Button {
                    store.sendQuick(phrase)
                } label: {
                    Text(phrase.text)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(MobileTheme.primaryText)
                        .lineLimit(wraps ? nil : 2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(wraps ? 1 : 0.85)
                        .fixedSize(horizontal: false, vertical: wraps)
                        .frame(maxWidth: .infinity, minHeight: GamesTouchTarget.minimum)
                        .padding(.horizontal, 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(MobileTheme.cardElevated))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(MobileTheme.separator, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(store.isSendingChat)
            }
        }
    }

    @ViewBuilder
    private var statusLines: some View {
        if let notice = store.chatNotice, !notice.isEmpty {
            statusLine(notice, tint: MobileTheme.pending)
        }
        if store.isOpponentMuted {
            statusLine(GomokuNoticeText.chatMutedByOpponent, tint: MobileTheme.pending)
        }
        if !store.opponentChatCapable {
            statusLine(GomokuNoticeText.chatOpponentOutdated, tint: MobileTheme.secondaryText)
        }
    }

    private func statusLine(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            // 한 줄 입력칸 — 키보드의 보내기 키가 곧 전송이다(여러 줄 입력칸은 ↩ 가 줄바꿈이라 onSubmit 이 오지 않는다).
            // 한글 조합 중에는 보내기 키가 먼저 조합을 확정하고 onSubmit 이 온다(마지막 음절이 빠지지 않는다).
            TextField(GomokuPhoneText.chatPlaceholder, text: $store.chatDraft)
                .font(.body)
                .submitLabel(.send)
                .focused($inputFocused)
                .onSubmit { store.sendChatDraft() }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MobileTheme.cardElevated))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isOverflowing ? MobileTheme.danger : MobileTheme.separator, lineWidth: 1))
            VStack(alignment: .trailing, spacing: 2) {
                if showsCounter {
                    Text("\(length)/\(store.chatMaxLength)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isOverflowing ? MobileTheme.danger : MobileTheme.secondaryText)
                }
                Button {
                    store.sendChatDraft()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .accessibilityLabel(GomokuPhoneText.chatSend)
                }
                .buttonStyle(GamesCompactButtonStyle(kind: .filled))
                .disabled(!store.canSendChatNow)
            }
        }
    }
}

/// 말풍선 하나(내 것 오른쪽 accent · 받은 것 왼쪽).
private struct GamesGomokuChatBubble: View {
    let message: GomokuChatMessage

    var body: some View {
        HStack(spacing: 0) {
            if message.isMine { Spacer(minLength: 48) }
            Text(message.body)
                .font(.subheadline)
                .foregroundStyle(message.isMine ? MobileTheme.onAccent : MobileTheme.primaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(message.isMine ? MobileTheme.accent : MobileTheme.cardElevated)
                )
            if !message.isMine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel((message.isMine ? "나: " : "상대: ") + message.body)
    }
}
#endif
