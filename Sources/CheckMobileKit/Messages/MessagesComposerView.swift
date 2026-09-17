#if os(iOS)
import CheckCore
import SwiftUI
import UIKit

/// 입력줄: 전송 실패 안내 한 줄 · 여러 줄 입력칸(최대 5줄까지 자라고 그 뒤 스크롤) · 180자부터 카운터 · [보내기].
///
/// ★ **한글 조합 중에는 보내지 않는다.** 입력칸은 `UITextView` 다 — SwiftUI `TextField` 는 조합 중인 글자(marked text)를 알려 주지 않아
///   [보내기] 순간의 마지막 음절이 빠지거나, 비운 칸에 조합 중이던 글자가 되살아난다. 여기서는 조합 중이면 먼저 확정(`unmarkText`)하고
///   확정된 글로 다시 판정해 보낸다(`MessagesComposerRules.sendAction` · 스토어 `sendDraft(isComposing:)` 가 이중으로 막는다).
/// ★ 줄바꿈은 키보드의 return 이다(폰 메신저 관례). 보내기는 버튼 하나.
struct MessagesComposerView: View {
    let store: MessagesStore
    let peerID: String

    @State private var editor = MessagesComposerEditorHandle()
    @State private var isComposing = false
    @State private var editorHeight: CGFloat = 44
    /// 보내기 원 지름: 44 를 본문 글자 크기로 키운 값(상한·하한은 `MessagesComposerRules.sendButtonMetrics`).
    @ScaledMetric(relativeTo: .body) private var scaledSendDiameter: CGFloat = CGFloat(MessagesComposerRules.minimumTouchTarget)

    var body: some View {
        let draft = store.draft(for: peerID)
        let counter = MessagesComposerRules.counterText(for: draft)
        let overflowing = MessagesComposerRules.isOverflowing(draft)
        let sendMetrics = MessagesComposerRules.sendButtonMetrics(scaledDiameter: Double(scaledSendDiameter))
        VStack(alignment: .leading, spacing: 6) {
            if let notice = store.sendNotices[peerID] {
                InlineNotice(text: notice, kind: .warning)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    MessagesComposerTextView(
                        text: Binding(get: { store.draft(for: peerID) }, set: { store.setDraft($0, for: peerID) }),
                        isComposing: $isComposing,
                        height: $editorHeight,
                        handle: editor
                    )
                    .frame(height: editorHeight)
                    if draft.isEmpty && !isComposing {
                        Text("메시지를 입력하세요")
                            .font(.body)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(MobileTheme.secondaryText)
                            .padding(.horizontal, MessagesComposerTextView.horizontalInset + 5)
                            .padding(.vertical, MessagesComposerTextView.verticalInset)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(MobileTheme.cardElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(overflowing ? MobileTheme.danger : MobileTheme.separator, lineWidth: 1)
                )
                VStack(alignment: .trailing, spacing: 4) {
                    if let counter {
                        Text(counter)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(overflowing ? MobileTheme.danger : MobileTheme.secondaryText)
                            .fixedSize()
                            // 카운터는 입력칸 폭을 먹는다 — 가장 큰 글자에서 입력칸이 절반으로 줄었다(AX3 스크린샷 실측).
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            .accessibilityLabel(Text("\(counter.replacingOccurrences(of: "/", with: "자 중 "))자"))
                    }
                    Button(action: send) {
                        Group {
                            if store.isSending {
                                ProgressView().tint(MobileTheme.onAccent)
                            } else {
                                // 글리프는 원 지름에서 정한 고정 크기다 — `.body` 를 따르면 AX3 에서 화살촉이 원 밖으로 빠져 모양이 사라졌다.
                                Image(systemName: "arrow.up")
                                    .font(.system(size: CGFloat(sendMetrics.glyphSize), weight: .bold))
                            }
                        }
                        .foregroundStyle(MobileTheme.onAccent)
                        // 원 = 누르는 자리(44pt 이상). 예전 40×40 은 HIG 최소보다 작았다.
                        .frame(width: CGFloat(sendMetrics.diameter), height: CGFloat(sendMetrics.diameter))
                        .background(Circle().fill(MobileTheme.accent))
                        .contentShape(Rectangle())
                        .opacity(sendEnabled ? 1 : 0.4)
                    }
                    .disabled(!sendEnabled)
                    .accessibilityLabel(Text(store.isSending ? "보내는 중" : "보내기"))
                }
            }
        }
        .padding(.horizontal, MobileTheme.sideMargin)
        .padding(.vertical, 8)
        .background(MobileTheme.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(MobileTheme.separator).frame(height: 1)
        }
    }

    /// 버튼을 켤지: 조합 중이면 켠다(누르면 확정한 뒤 판정한다) — 아니면 스토어 판정 그대로.
    private var sendEnabled: Bool {
        guard !store.isSending else { return false }
        return isComposing || store.canSend(to: peerID)
    }

    private func send() {
        switch MessagesComposerRules.sendAction(isComposing: editor.hasMarkedText, canSendCommittedDraft: store.canSend(to: peerID)) {
        case .none:
            return
        case .send:
            store.sendDraft(to: peerID, isComposing: false)
        case .commitThenSend:
            editor.commitMarkedText()
            // 확정이 바인딩에 닿은 뒤(같은 런루프의 delegate 알림) 다시 판정한다. 여전히 조합 중이면 보내지 않는다.
            let editor = editor
            let store = store
            let peerID = peerID
            let composing = $isComposing
            Task { @MainActor in
                store.setDraft(editor.currentText ?? store.draft(for: peerID), for: peerID)
                composing.wrappedValue = editor.hasMarkedText
                guard !editor.hasMarkedText else { return }
                store.sendDraft(to: peerID, isComposing: false)
            }
        }
    }
}

/// 입력칸 `UITextView` 를 바깥(보내기 버튼)에서 만지는 손잡이 — 조합 확정과 지금 글.
@MainActor
final class MessagesComposerEditorHandle {
    weak var textView: UITextView?

    var hasMarkedText: Bool { textView?.markedTextRange != nil }
    var currentText: String? { textView?.text }

    func commitMarkedText() {
        guard let textView, textView.markedTextRange != nil else { return }
        textView.unmarkText()
    }
}

/// 여러 줄 입력칸. 글자는 Dynamic Type(`.body`)을 따라 커지고, 높이는 내용에 맞춰 1~5줄 사이에서 자란다.
struct MessagesComposerTextView: UIViewRepresentable {
    static let horizontalInset: CGFloat = 10
    /// 위아래 12 — 한 줄일 때 입력칸 높이(본문 줄 높이 + 24 ≈ 44)가 보내기 원(44)과 맞는다.
    static let verticalInset: CGFloat = 12
    static let maxLines: CGFloat = 5
    /// 손쉬운 사용 글자 크기에서는 3줄 — 5줄이면 키보드와 함께 대화가 한 줄도 안 보인다.
    static let accessibilityMaxLines: CGFloat = 3

    @Binding var text: String
    @Binding var isComposing: Bool
    @Binding var height: CGFloat
    let handle: MessagesComposerEditorHandle

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textColor = UIColor(MobileTheme.primaryText)
        view.tintColor = UIColor(MobileTheme.accent)
        view.typingAttributes = Self.textAttributes()
        view.textContainerInset = UIEdgeInsets(top: Self.verticalInset, left: Self.horizontalInset, bottom: Self.verticalInset, right: Self.horizontalInset)
        view.isScrollEnabled = false
        view.returnKeyType = .default
        view.autocorrectionType = .default
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = "메시지 입력"
        Self.setText(text, on: view)
        handle.textView = view
        return view
    }

    /// 입력 글자 속성: 본문 글꼴 · 테마 글자색 · **한글 어절 단위 줄바꿈**(기본값은 음절 중간에서 끊겨 "두/었어요"가 됐다 — 스크린샷 실측).
    static func textAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakStrategy = [.standard, .hangulWordPriority]
        return [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor(MobileTheme.primaryText),
            .paragraphStyle: paragraph,
        ]
    }

    /// 바깥 값으로 글을 바꾼다(조합 중이 아닐 때만 부른다). 비운 뒤에도 다음 타자가 같은 속성을 갖게 입력 속성을 다시 건다.
    static func setText(_ text: String, on view: UITextView) {
        let attributes = textAttributes()
        view.attributedText = NSAttributedString(string: text, attributes: attributes)
        view.typingAttributes = attributes
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        handle.textView = view
        // 조합 중에는 바깥 값으로 덮지 않는다 — 덮으면 조합이 깨지고 글자가 되살아나거나 빠진다.
        if view.markedTextRange == nil, view.text != text {
            Self.setText(text, on: view)
        }
        context.coordinator.recalculateHeight(view)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MessagesComposerTextView

        init(parent: MessagesComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            let composing = textView.markedTextRange != nil
            if parent.isComposing != composing { parent.isComposing = composing }
            if parent.text != textView.text { parent.text = textView.text }
            recalculateHeight(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let composing = textView.markedTextRange != nil
            if parent.isComposing != composing { parent.isComposing = composing }
        }

        func recalculateHeight(_ textView: UITextView) {
            let width = textView.bounds.width
            guard width > 0 else { return }
            let lineHeight = textView.font?.lineHeight ?? 20
            let insets = textView.textContainerInset.top + textView.textContainerInset.bottom
            let lines = textView.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
                ? MessagesComposerTextView.accessibilityMaxLines : MessagesComposerTextView.maxLines
            let maxHeight = ceil(lineHeight * lines + insets)
            let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
            let target = min(max(ceil(fitting), ceil(lineHeight + insets)), maxHeight)
            let scrolls = fitting > maxHeight
            if textView.isScrollEnabled != scrolls { textView.isScrollEnabled = scrolls }
            if abs(parent.height - target) > 0.5 {
                // 뷰 갱신 도중에 상태를 바꾸지 않게 다음 차례로 미룬다.
                let binding = parent.$height
                Task { @MainActor in binding.wrappedValue = target }
            }
        }
    }
}
#endif
