import SwiftUI

// MARK: - 메시지 창 내용 (v0.2.49)
//
// 2단이다: 왼쪽 대화 상대 목록(180pt) · 오른쪽 그 사람과의 대화 + 입력줄.
//
// 사용자 요구는 한 문장이었다 — **"진짜 메신저 앱처럼."** 그 말이 이 파일의 배치를 전부 정한다:
//   · 말풍선은 **시간순**(오래된 것 위 → 최신 아래). 받은 것은 왼쪽, 보낸 것은 오른쪽(`is_mine`).
//   · 날짜가 바뀌는 자리에 **구분선**. 그 판정은 뷰가 아니라 `MessageThreadBuilder.timeline` 이 한다
//     (뷰가 그리면서 "앞 항목과 날짜가 다른가"를 보면 그 규칙을 헤드리스로 잴 수 없다).
//   · 처음 열면 **맨 아래(최신)** 다. 위에서 시작하면 사용자가 매번 스크롤을 내려야 하고,
//     그건 메신저에서 아무도 하지 않는 동작이다.
//   · Enter 는 **줄바꿈**, 전송은 **⌘Enter**. 200자를 쓰는 창에서 Enter 전송은 문장을 반토막 낸다.
//
// ★ 이 파일이 그리는 문자열은 **두 사람이 주고받은 문장**이다. 어떤 경로로도 로그·진단 문자열로 흘리지 마라.
//
// ── ImageRenderer 눈가리개(렌더 테스트 전용 대체 경로) ──
// `ImageRenderer` 는 ScrollView 안쪽과 `TextEditor` 를 못 그린다(제보 창이 겪은 함정, 그전엔 `Menu` 가
// 노란 상자로 나왔다). 그대로 두면 스냅샷이 헤더만 남은 빈 화면이 되어 "잘림·겹침을 눈으로 본다"는
// 렌더 테스트의 목적이 통째로 사라진다. 그래서 **렌더 테스트만** 같은 자리·같은 치수의 순수 SwiftUI
// 대체 경로를 쓴다. **앱은 언제나 진짜 위젯이다**(두 스위치의 기본값이 false 이고 프로덕션에 true 를 주는 자리는 없다).

/// 메시지 창의 치수. **한 곳에서만 온다** — 뷰마다 숫자를 적으면 창 최소 크기(460×420)와 조용히 어긋나고,
/// 그 어긋남은 사용자가 창을 줄였을 때만 드러난다(테스트는 자연 크기로 그려서 못 잡는다).
enum MessageLayout {
    /// 왼쪽 대화 목록 폭. 아바타(26) + 이름 + "14:05" 한 줄이 말줄임 없이 서는 최소치다.
    static let listWidth: CGFloat = 180
    static let contentPadding: CGFloat = 12
    /// 말풍선 **반대쪽에 반드시 남기는 여백**(pt). 말풍선 폭을 이걸로 제한하는 것이 요점이다.
    ///
    /// ★ `.frame(maxWidth:)` 를 쓰면 안 된다(2026-09-10 실측). 그 수식어는 부모가 폭을 주는 만큼
    ///   **끝까지 늘어나서**, "안녕" 두 글자짜리 말풍선이 창 절반을 차지한다. 배경을 프레임 뒤에 붙이든
    ///   앞에 붙이든 둘 중 하나가 반드시 깨진다(캡슐이 260 이 되거나, 글자가 260 이 되거나).
    ///   그래서 상한을 **여백으로** 만든다: 짧은 말은 글자를 따라 줄어들고, 긴 말은 이 여백에 막혀 접힌다.
    static let bubbleOppositeInset: CGFloat = 44
    /// 대화 목록 한 행 높이(아바타 + 이름/미리보기 두 줄).
    static let threadRowHeight: CGFloat = 52
    /// 입력 에디터 높이. 캡션 글자로 세 줄 남짓 — 200자를 한눈에 보기엔 모자라지만, 대화를 덮지 않는 값이다.
    ///
    /// **최소치가 아니라 고정값인 이유**는 제보 창과 같다: 이 블록 위가 스크롤이라, 높이가 안 정해지면
    /// 에디터가 창 절반을 삼킨다. 넘치는 글은 에디터가 자기 안에서 스크롤한다.
    static let editorHeight: CGFloat = 68
    static let corner: CGFloat = 10
}

// MARK: - 창 내용

struct CheckMessageView: View {
    @Bindable var store: WorkTimerStore
    /// 스냅샷 전용 대체 경로(파일 머리 주석). **앱은 언제나 false** 다.
    var rendersPlainTextEditor: Bool = false
    /// 스냅샷 전용: 본문을 ScrollView 대신 클립으로 그린다. **앱은 언제나 false** 다.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 상대 시각·날짜 라벨의 기준. 기본은 지금이고 렌더 테스트가 고정값을 준다 — 스냅샷이 실행 시각에
    /// 흔들리면 사람이 눈으로 비교할 수 없다.
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PanelDivider()
            if store.messageThreads.isEmpty {
                // 대화가 하나도 없을 때는 2단을 그리지 않는다 — 빈 목록과 빈 대화를 나란히 두면
                // 사용자는 "무엇을 골라야 하나"를 두 번 묻게 된다. 할 일을 한 문장으로 말한다.
                emptyState
            } else {
                HStack(spacing: 0) {
                    MessageThreadListView(store: store, now: now, clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll)
                        .frame(width: MessageLayout.listWidth)
                    Rectangle().fill(CheckTheme.border).frame(width: 1)
                    conversationPane
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: 헤더(사라지는 규칙 + 새로고침)

    /// 상단 한 줄. **"12시간이 지나면 사라진다"를 여기서 말하는 것이 이 줄의 존재 이유다** —
    /// 규칙을 모르면 사용자는 어제 대화가 없는 것을 버그로 읽고, 그 오해는 제보로 온다.
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            Text(WorkTimerStore.messageExpiryNotice)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 4)
            if store.messageHistoryLoading {
                Text("불러오는 중…")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize()
            }
            IconButton(icon: "arrow.clockwise", help: "새로고침") { store.loadMessageHistory() }
        }
        .padding(.horizontal, MessageLayout.contentPadding)
        .padding(.vertical, 8)
    }

    // MARK: 빈 상태

    /// 대화가 하나도 없을 때. **"상대를 안 골랐을 때"와 갈라 두는 것이 핵심이다** — 두 상태의 답이 다르다.
    /// 여기서 할 일은 '고르기'가 아니라 '시작하기'이고, 시작하는 문이 어디인지 말해 주지 않으면
    /// 사용자는 이 창에서 아무것도 할 수 없다(이 창에는 사람 목록이 없다 — 그건 콕찌르기 패널의 것이다).
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(CheckTheme.secondaryText.opacity(0.55))
            Text(store.messageHistoryFailed ? "대화를 불러오지 못했어요" : "아직 주고받은 메시지가 없어요")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
            Text(
                store.messageHistoryFailed
                    ? "잠시 후 [새로고침]을 눌러 주세요"
                    : "콕 찌르기에서 말풍선 버튼을 누르면 여기서 대화가 시작돼요"
            )
            .font(.caption)
            .foregroundStyle(CheckTheme.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(MessageLayout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 오른쪽(대화 + 입력줄)

    @ViewBuilder
    private var conversationPane: some View {
        VStack(spacing: 0) {
            if let thread = store.selectedMessageThread {
                MessageConversationView(
                    thread: thread,
                    now: now,
                    clipsInsteadOfScrolling: clipsOverflowInsteadOfScroll
                )
            } else {
                // 상대를 안 골랐을 때. 위 빈 상태와 **다른 문장이어야 한다** — 여기서 할 일은 '고르기'다.
                VStack(spacing: 6) {
                    Spacer(minLength: 0)
                    Text("왼쪽에서 대화를 골라 주세요")
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            PanelDivider()
            MessageComposerView(store: store, rendersPlainText: rendersPlainTextEditor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - 왼쪽: 대화 상대 목록

/// 대화 상대 목록. `message_history` **한 번**으로 받은 것을 클라에서 묶은 결과를 그린다
/// (상대마다 조회하면 26명 규모에서 요청이 26배다 — 무료 플랜).
struct MessageThreadListView: View {
    @Bindable var store: WorkTimerStore
    var now: Date = Date()
    var clipsInsteadOfScrolling: Bool = false

    var body: some View {
        MessageScrollContainer(clipsInsteadOfScrolling: clipsInsteadOfScrolling) {
            LazyVStack(spacing: 0) {
                ForEach(store.messageThreads) { thread in
                    MessageThreadRow(
                        thread: thread,
                        now: now,
                        isSelected: store.selectedMessagePeerID == thread.peerUserID,
                        hasUnread: store.unreadMessagePeerIDs.contains(thread.peerUserID)
                    ) {
                        store.selectMessagePeer(thread.peerUserID)
                    }
                    Rectangle().fill(CheckTheme.border.opacity(0.5)).frame(height: 1)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.12))
    }
}

/// 한 대화 상대 = 아바타 + 이름 + 마지막 메시지 한 줄 미리보기 + 마지막 시각 (+ 안 읽음 점).
private struct MessageThreadRow: View {
    let thread: MessageThread
    let now: Date
    let isSelected: Bool
    let hasUnread: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                CheckAvatarView(name: thread.peerName, avatarURL: thread.peerAvatarURL, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(thread.peerName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CheckTheme.primaryText)
                            .lineLimit(1)
                        // 안 읽은 것이 있으면 점. **이름 옆이지 행 끝이 아니다** — 행 끝은 시각의 자리라
                        // 둘을 겹치면 좁은 폭(180)에서 시각이 먼저 잘린다.
                        if hasUnread {
                            Circle().fill(CheckTheme.accent).frame(width: 6, height: 6)
                        }
                        Spacer(minLength: 0)
                        if let last = thread.lastMessage {
                            Text(MessageThreadBuilder.listStampText(last.createdAt, now: now))
                                .font(.system(size: 9))
                                .foregroundStyle(CheckTheme.secondaryText)
                                .fixedSize()
                        }
                    }
                    // 미리보기. **`fixedSize` 를 붙이지 마라** — 200자 본문이 이상 폭을 요구해 행을 밀어낸다
                    // (팝오버 수신 줄이 정확히 그 결함이었다). 한 줄 말줄임이 이 자리의 계약이다.
                    Text(MessageThreadBuilder.previewText(thread.lastMessage?.body ?? ""))
                        .font(.system(size: 10))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: MessageLayout.threadRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? CheckTheme.accent.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(thread.peerName)님과의 대화\(hasUnread ? " · 안 읽음" : "")")
    }
}

// MARK: - 오른쪽: 대화

/// 한 사람과의 대화. 말풍선을 **시간순으로 쌓고**, 처음 열면 맨 아래(최신)에 있다.
struct MessageConversationView: View {
    let thread: MessageThread
    var now: Date = Date()
    var clipsInsteadOfScrolling: Bool = false

    /// 맨 아래로 보낼 앵커. 마지막 말풍선 id 를 쓰지 않는 이유는 **날짜 구분선이 마지막일 수 없기 때문**이
    /// 아니라, 빈 대화에서도 앵커가 있어야 하기 때문이다(그리고 마지막 말풍선의 아래 여백까지 보이게 된다).
    private static let bottomAnchorID = "message-thread-bottom"

    private var items: [MessageTimelineItem] {
        MessageThreadBuilder.timeline(thread.messages, now: now)
    }

    var body: some View {
        if clipsInsteadOfScrolling {
            // 스냅샷 전용(ImageRenderer 는 ScrollView 안쪽을 못 그린다). **아래쪽이 최신이므로 위를 자른다** —
            // 앱에서 처음 보이는 것이 최신 쪽이라, 위를 남기고 아래를 자르면 스냅샷과 화면이 다른 것을 보여 준다.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { content.fixedSize(horizontal: false, vertical: true) }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    content
                    Color.clear.frame(height: 1).id(Self.bottomAnchorID)
                }
                // 내용이 창보다 짧아도 **아래에 붙인다**(메신저의 기본 감각이고, 스냅샷의 클립 갈래와
                // 같은 그림이 되게 하는 값이기도 하다 — 두 그림이 다르면 스냅샷으로 아무것도 확인할 수 없다).
                // 스크롤 초기 위치도 이것이 정한다: 길어지면 곧바로 최신 쪽에 서 있다.
                .defaultScrollAnchor(.bottom)
                // 처음 열 때 · 상대를 바꿀 때 · 새 말이 도착할 때 전부 맨 아래로. 셋을 한 함수로 모은 이유는
                // 세 자리가 갈리면 그중 하나만 고쳐지는 날이 오기 때문이다.
                .onAppear { scrollToBottom(proxy, animated: false) }
                .onChange(of: thread.peerUserID) { _, _ in scrollToBottom(proxy, animated: false) }
                .onChange(of: thread.messages.last?.id) { _, _ in scrollToBottom(proxy, animated: true) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard animated else {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                switch item {
                case .day(_, let label):
                    MessageDaySeparator(label: label)
                case .bubble(let entry):
                    MessageBubbleRow(entry: entry)
                }
            }
        }
        .padding(.horizontal, MessageLayout.contentPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 날짜 구분선("오늘" / "어제" / "9월 8일"). 가운데 캡슐 + 양옆 실선.
private struct MessageDaySeparator: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(CheckTheme.border).frame(height: 1)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .fixedSize()
            Rectangle().fill(CheckTheme.border).frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}

/// 말풍선 한 줄. 받은 것은 왼쪽(아바타 있음), 보낸 것은 오른쪽(아바타 없음 — 내 얼굴은 내가 안다).
private struct MessageBubbleRow: View {
    let entry: MessageHistoryEntry

    private var clockText: String { MessageThreadBuilder.clockText(entry.createdAt) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            if entry.isMine {
                // 보낸 것: 왼쪽을 비우고 시각을 말풍선 **왼쪽**에 둔다(오른쪽 끝은 창 가장자리다).
                Spacer(minLength: MessageLayout.bubbleOppositeInset)
                timeLabel
                bubble
            } else {
                CheckAvatarView(name: entry.peerName, avatarURL: entry.peerAvatarURL, size: 22)
                bubble
                timeLabel
                Spacer(minLength: MessageLayout.bubbleOppositeInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: entry.isMine ? .trailing : .leading)
    }

    private var timeLabel: some View {
        Text(clockText)
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(CheckTheme.secondaryText.opacity(0.8))
            .fixedSize()
    }

    /// 본문. **폭을 프레임으로 못 박지 않는다** — 그 이유는 `bubbleOppositeInset` 주석에 있다.
    /// 여기서 하는 일은 둘뿐이다: 세로로만 자라게 두고(`fixedSize(vertical:)`), 글자를 감싸는 캡슐을 그린다.
    /// 짧은 말은 캡슐이 글자를 따라 줄어들고, 긴 말은 반대쪽 여백(HStack 의 Spacer)에 막혀 여러 줄로 접힌다.
    ///
    /// **`fixedSize(horizontal: true)` 는 금지다** — 200자가 한 줄을 요구해 창 밖으로 넘친다.
    private var bubble: some View {
        Text(entry.body)
            .font(.caption)
            .foregroundStyle(entry.isMine ? .white : CheckTheme.primaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: MessageLayout.corner, style: .continuous)
                    .fill(entry.isMine ? CheckTheme.accent.opacity(0.85) : Color.white.opacity(0.10))
            )
            .textSelection(.enabled)
    }
}

// MARK: - 입력줄

/// 여러 줄 입력 + 글자 수(N/200, **코드포인트**) + [보내기].
///
/// **Enter 는 줄바꿈이고 전송은 ⌘Enter 다**(200자를 쓰는 창이라 Enter 전송은 문장을 반토막 낸다).
/// 그래서 [보내기] 버튼이 `⌘↩` 단축키를 직접 들고 있다 — 단축키와 버튼이 같은 문(`sendDraftMessage`)을
/// 지나야 두 경로가 갈리지 않는다.
struct MessageComposerView: View {
    @Bindable var store: WorkTimerStore
    var rendersPlainText: Bool = false

    private var length: Int { store.messageDraftLength }
    private var isOverflowing: Bool { length > MessageBody.maxLength }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 전송 결과 한 줄. **성공만 초록**이고 나머지는 경고색이다 — 사유별로 색을 더 가르면
            // 사용자가 외워야 할 색만 늘어난다(제보 창과 같은 규약).
            if let notice = store.messageNotice, !notice.isEmpty {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(
                        notice == WorkTimerStore.messageSentNotice ? CheckTheme.working : CheckTheme.pending
                    )
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MessageDraftEditor(
                text: $store.messageDraft,
                height: MessageLayout.editorHeight,
                isOverflowing: isOverflowing,
                rendersPlainText: rendersPlainText
            )
            HStack(spacing: 8) {
                Text("⌘↩ 로 보내요")
                    .font(.system(size: 9))
                    .foregroundStyle(CheckTheme.secondaryText.opacity(0.7))
                    .fixedSize()
                Spacer(minLength: 4)
                // 글자 수는 **코드포인트**다(MessageBody.length) — 자소로 세면 이모지에서 서버와 눈금이 갈린다.
                Text("\(length)/\(MessageBody.maxLength)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isOverflowing ? CheckTheme.danger : CheckTheme.secondaryText)
                    .fixedSize()
                Button(action: { store.sendDraftMessage() }) {
                    Text(store.isSendingMessage ? "보내는 중…" : "보내기")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(
                            Capsule().fill(CheckTheme.accent.opacity(store.canSendMessageNow ? 1 : 0.35))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!store.canSendMessageNow)
                .keyboardShortcut(.return, modifiers: .command)
                .help(sendHelp)
            }
        }
        .padding(.horizontal, MessageLayout.contentPadding)
        .padding(.vertical, 8)
    }

    /// 왜 못 보내는지. **쿨타임 문구는 여기 없다**(v0.2.49 — 메시지에 쿨타임이 없다).
    /// 남은 사유는 셋뿐이고, 셋 다 사용자가 지금 고칠 수 있는 것이다.
    private var sendHelp: String {
        if store.isSendingMessage { return "보내는 중이에요" }
        if store.selectedMessagePeerID == nil { return "왼쪽에서 대화를 골라 주세요" }
        switch MessageBody.validate(store.messageDraft) {
        case .ok: return "보내기 (⌘↩)"
        case .empty: return "보낼 말을 입력해 주세요"
        case .tooLong(let maxLength): return WorkTimerStore.messageTooLongNotice(maxLength: maxLength)
        }
    }
}

/// 입력 에디터.
///
/// **`rendersPlainText` 가 있는 이유**: `ImageRenderer` 는 AppKit 을 감싼 뷰를 못 그린다
/// (이 저장소에서 `Menu` 는 노란 상자로 그려졌고, 제보 창의 `TextEditor`/`TextField(axis:)` 도 같았다).
/// 스냅샷이 빈 상자만 남기면 잘림·겹침을 눈으로 확인한다는 렌더 테스트의 목적이 통째로 사라진다.
/// **앱은 언제나 진짜 `TextEditor` 다** — 기본값이 false 이고 프로덕션에서 true 를 주는 자리는 없다.
struct MessageDraftEditor: View {
    @Binding var text: String
    var height: CGFloat
    var isOverflowing: Bool = false
    var rendersPlainText: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: MessageLayout.corner, style: .continuous)
                .fill(CheckTheme.fieldFill)
                .overlay(
                    RoundedRectangle(cornerRadius: MessageLayout.corner, style: .continuous)
                        // 초과는 테두리까지 빨갛게 — 카운터 숫자만으로는 못 보고 지나친다.
                        .stroke(isOverflowing ? CheckTheme.danger : CheckTheme.border, lineWidth: 1)
                )
            // placeholder — 비었을 때만. TextEditor 에는 placeholder 가 없다.
            if text.isEmpty {
                Text("메시지를 입력하세요")
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if rendersPlainText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
            } else {
                // ⚠︎ 입력 시점 필터를 붙이지 마라. 3글자 시절엔 이모지를 지우는 필터가 있었지만
                //   (자소/코드포인트 눈금 차이 때문에), 지금은 이모지가 정상 입력이고 길이는 코드포인트로 센다.
                //   그리고 조합 중인 한글을 코드가 되쓰면 마지막 글자가 씹힌다 — 그 회귀는 헤드리스로 못 잡는다.
                TextEditor(text: $text)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.primaryText)
                    // 에디터가 자기 배경(흰 판)을 그리면 다크 화면에 흰 상자가 뚫린다.
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
        }
        .frame(height: height, alignment: .topLeading)
    }
}

// MARK: - 스크롤 컨테이너(스냅샷 대체 경로 포함)

/// 제보 창의 같은 이름 컨테이너와 **같은 근거**로 존재한다(그쪽 주석에 실측 세 줄이 있다):
/// `ImageRenderer` 는 ScrollView 안쪽을 못 그리므로, 렌더 테스트만 빈 판 + `.top` 오버레이로 바꾼다.
/// `.fixedSize(vertical:)` 이 없으면 스냅샷이 **없는 겹침을 그린다**(자식이 바탕 높이에 욱여넣어진다).
struct MessageScrollContainer<Content: View>: View {
    let clipsInsteadOfScrolling: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if clipsInsteadOfScrolling {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) { content().fixedSize(horizontal: false, vertical: true) }
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                content()
            }
        }
    }
}
