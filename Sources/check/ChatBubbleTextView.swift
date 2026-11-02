import AppKit
import SwiftUI
import CheckCore

// MARK: - 고를 수 있는 말풍선 본문 (대표 요청 2026-11-03 ④ · 대표 결정 "받은 말풍선도 드래그, 우클릭에 신고 유지")
//
// 요청: "채팅에서 입력하는 내용 드래그 가능하게 해서 복사도 가능하게 하고 링크같은건 클릭해서 실제 해당 링크로 브라우저 열리게도 해줘."
// 결정: 받은 말풍선도 끌어 고르고, 우클릭 메뉴에는 [이 메시지 신고하기](v0.3.34)를 그대로 둔다.
//
// ## 왜 SwiftUI `Text` 가 아니라 AppKit 글자 뷰인가
// SwiftUI 의 고를 수 있는 글자(`.textSelection(.enabled)`)는 우클릭을 **자기 메뉴**(복사·찾아보기)로 가져가서 `.contextMenu` 의
// [신고] 항목이 안 뜬다(v0.3.34 — 그래서 그때는 받은 말풍선의 글자 선택을 꺼 두었다). 두 요구(끌어 고르기 + 우클릭 신고)를 함께 채우려면
// 메뉴를 **직접 세울 수 있는** 글자 뷰가 필요하다: 편집 불가 · 선택 가능한 `NSTextView` 이고, 메뉴는 `menu(for:)` 가 짓는다.
// 같은 팝오버의 입력칸(`CheckTextEditor`)이 이미 NSTextView 를 감싸 쓰는 선례다.
//
// ## 이 뷰가 지키는 것 (ChatBubbleSelectionTests 가 화면에 올리지 않는 창으로 잰다 — 누름 추적 자체(끌기 · 링크 한 번 누름)는
//    앱 이벤트 대기열을 써야 해서 시험이 돌리지 않는다: 그 시험 머리 주석의 ★. 실화면은 사람이 본다)
//  · 우클릭 메뉴 — 받은 말풍선: [복사] · [이 메시지 신고하기], 내 말풍선: [복사]. [신고]는 받은 `onReport` 를 그대로 부른다
//    (어느 말풍선에 서는지는 `MessageBubbleReportRule` 한 곳 — 대화 뷰가 거른 것만 들어온다).
//  · [복사] — 고른 글자가 있으면 **고른 글자**, 없으면 말풍선 **원문**(`rawBody` — 마크다운 기호·이모티콘 토큰 그대로).
//    고른 글자에 `[글](주소)` 링크가 걸치면 호스트 꼬리표 대신 **실제 주소**를 담는다(`copyText` — 2026-11-03 검토 P2).
//    붙여넣기판에는 **서식 없는 글자만** 쓴다: 서식째 쓰면 내 말풍선의 흰 글자가 흰 문서에 붙어 안 보인다.
//    ⌘C · [복사]뿐 아니라 끌어 놓기 · 서비스 메뉴(`writeSelection`)도 같다(검토 P2 — 그 길은 NSTextView 기본이 RTF 를 싣는다).
//  · **말풍선 전체가 이 뷰다** — 여백(좌우 8 · 위아래 5)은 SwiftUI padding 이 아니라 글자 뷰 안쪽 여백(`textContainerInset`)이다.
//    여백이 바깥 SwiftUI 몫이면 짧은 말풍선의 대부분(여백 띠)에서 우클릭 메뉴([신고])가 안 뜨고 끌기도 시작되지 않는다(2026-11-03 검토 P1 —
//    예전 `.contextMenu` 는 말풍선 전체에 붙어 있었다). 바탕(둥근 판)만 SwiftUI 가 그린다.
//  · ⌘C 는 고른 글자를 복사한다(⌘A 는 이 말풍선 전체를 고른다). 첫 응답자일 때만 받는다 — 입력칸의 ⌘C 를 가로채지 않는다.
//  · 링크는 한 번 눌러 기본 브라우저로 연다. **여는 자리에서 `ChatMarkdown.isOpenable` 을 다시 본다**(`followLink`).
//    대리자는 언제나 "처리했다"를 돌려준다 — false 면 NSTextView 가 검사 없이 NSWorkspace 로 열어 버린다.
//  · 우클릭은 **입력칸 포커스를 뺏지 않고, 눌린 낱말을 고르지 않는다**(NSTextView 기본 우클릭은 둘 다 한다 — 2026-11-03 헤드리스 실측:
//    기본 `rightMouseDown` 뒤 첫 응답자가 글자 뷰로 바뀌었고, 기본 `menu(for:)` 는 눌린 낱말 "안녕하세요"를 골랐다. 낱말이 골라지면
//    [복사]가 원문 대신 그 낱말 하나를 담는다).
//  · 끌어 고르면 그 말풍선이 포커스를 쥔다(⌘C). 끌지 않고 한 번 누르기만 했으면(링크 누름 포함) 쓰던 입력칸에 포커스를 돌려준다 —
//    받은 말풍선은 예전에 눌러도 포커스를 안 가져갔다.

/// 말풍선 우클릭 메뉴의 글자. 그림(이모티콘) 말풍선의 SwiftUI 메뉴와 글자 말풍선의 AppKit 메뉴가 같이 쓴다.
enum ChatBubbleMenuText {
    static let copy = "복사"
    static let copySymbol = "doc.on.doc"
    static let reportSymbol = "exclamationmark.bubble"
}

/// 말풍선 본문 글자 뷰. `ChatBubbleText`(SwiftUI 래퍼) 밖에서는 시험만 직접 만든다.
final class ChatBubbleTextView: NSTextView {
    /// [복사]가 **고른 글자가 없을 때** 담는 원문(마크다운 기호·이모티콘 토큰 그대로 — 붙여넣어 다시 보내면 같은 꾸밈·그림이 된다).
    var rawBody = ""
    /// [이 메시지 신고하기]. nil 이면 메뉴에 신고가 없다(내 말풍선 · 신고 문이 없는 호출부).
    var onReport: (() -> Void)?
    /// 검사를 지난 링크를 여는 문. 앱은 기본 브라우저다 — **시험은 반드시 갈아 끼운다**(진짜 브라우저가 뜬다).
    var openLink: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// 복사가 쓰는 붙여넣기판. 앱은 일반 붙여넣기판이고, 시험은 이름 붙인 별도 판을 준다(사용자의 붙여넣기판을 덮지 않게).
    var pasteboard: NSPasteboard = .general
    /// 우클릭 메뉴를 띄우는 문. 진짜 팝업은 메뉴 추적 루프라 시험을 멈춘다 — 시험은 기록기로 갈아 끼운다.
    var presentMenu: @MainActor (NSMenu, NSEvent, NSView) -> Void = { menu, event, view in
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    /// 링크 누름을 받는 대리자. NSTextView 의 `delegate` 는 약한 참조라 뷰가 붙잡는다.
    private let linkGate = ChatBubbleLinkGate()

    /// 말풍선 본문 뷰를 짓는다. TextKit 1 로 만든다(`NSTextView(frame:textContainer:)`) — 높이를 재는 `ChatBubbleTextLayout` 과
    /// **같은 배치 엔진**이어야 잰 높이와 그린 높이가 같다.
    static func make() -> ChatBubbleTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        // 줄 높이는 SwiftUI `Text` 의 규칙으로 맞춘다(`ChatBubbleLineMetrics` — 재는 쪽도 같은 대리자를 쓴다).
        layout.delegate = ChatBubbleLineMetrics.shared
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        // 줄 조각 안쪽 여백은 0 — 글자 자리는 `textContainerInset`(말풍선 여백) 하나가 정한다. 그래야 `Text` + padding 과 같은 자리에 앉는다.
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let view = ChatBubbleTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        // 바탕(둥근 판)은 SwiftUI 가 그린다. 글자 뷰가 바탕을 그리면 판 위에 흰 상자가 뚫린다.
        view.drawsBackground = false
        // 말풍선 여백을 글자 뷰 **안에** 둔다(파일 머리 주석 — 여백을 눌러도 이 뷰가 받는다). 스냅샷 갈래의 SwiftUI padding 과 같은 값이다.
        view.textContainerInset = ChatBubbleTextLayout.inset
        // 크기는 SwiftUI 가 정한다(`ChatBubbleText.sizeThatFits`). 글자 뷰가 스스로 자라면 그 틀과 어긋난다.
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.importsGraphics = false
        view.usesFindBar = false
        view.isAutomaticLinkDetectionEnabled = false
        view.delegate = view.linkGate
        return view
    }

    /// 그릴 글자를 바꾼다. `shown` 은 이모티콘 폴백을 지난 본문이다(마크다운 해석은 `ChatMarkdownText.nsAttributed`).
    func show(_ shown: String, isMine: Bool) {
        textStorage?.setAttributedString(ChatMarkdownText.nsAttributed(shown, isMine: isMine))
        typingAttributes = ChatMarkdownText.nsBaseAttributes(isMine: isMine)
        linkTextAttributes = ChatMarkdownText.nsLinkAttributes(isMine: isMine)
        selectedTextAttributes = [.backgroundColor: ChatMarkdownText.nsSelectionColor(isMine: isMine)]
        setSelectedRange(NSRange(location: 0, length: 0))
    }

    // MARK: 복사

    /// 고른 자리의 복사 글자(여러 구간이면 줄바꿈으로 잇는다 — 링크는 실제 주소째, `copyText`). 아무것도 안 골랐으면 nil.
    var selectedText: String? {
        guard let storage = textStorage else { return nil }
        let parts = selectedRanges.map(\.rangeValue)
            .filter { $0.length > 0 && NSMaxRange($0) <= storage.length }
            .map { Self.copyText(storage, range: $0) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// 그린 글자의 한 구간 → 복사할 글자. 보이는 글자 그대로이되 **`[글](주소)` 링크만 다르다**(2026-11-03 검토 P2):
    /// 보이는 것은 `글 (호스트)` 인데 그대로 담으면 실제 주소는 빠지고 보낸 사람이 치지 않은 꼬리표가 들어간다. 그래서
    /// 글이 주소와 다른 링크(`ChatMarkdownText.copyLinkKey` 가 붙은 조각)는 고른 글 뒤에 ` (실제 주소)` 를 한 번 담고, 꼬리표 글자는
    /// 그 자리로 갈음한다. 꼬리표만 골라도 주소를 담는다. 맨 주소(글 = 주소)는 보이는 그대로다.
    static func copyText(_ text: NSAttributedString, range: NSRange) -> String {
        let source = text.string as NSString
        var out = ""
        var pending: URL?
        func flush() {
            guard let url = pending else { return }
            out += (out.isEmpty ? "" : " ") + "(\(url.absoluteString))"
            pending = nil
        }
        text.enumerateAttributes(in: range) { attributes, run, _ in
            let url = attributes[ChatMarkdownText.copyLinkKey] as? URL
            if attributes[ChatMarkdownText.disclosureKey] != nil {
                // 꼬리표 " (호스트)" — 글자 대신 실제 주소. 고른 것이 꼬리표에서 시작했으면 그 주소를 여기서 집는다.
                if pending == nil { pending = url }
                flush()
                return
            }
            if pending != url { flush() }
            out += source.substring(with: run)
            if let url { pending = url }
        }
        flush()
        return out
    }

    /// [복사]가 담을 글자 — 고른 글자가 있으면 그것, 없으면 원문.
    var textToCopy: String { selectedText ?? rawBody }

    /// ⌘C · Edit 메뉴의 복사. **고른 글자만**, **서식 없이** 쓴다(파일 머리 주석). 고른 것이 없으면 아무것도 안 한다.
    override func copy(_ sender: Any?) {
        guard let selectedText else { return }
        CheckPasteboard.copy(selectedText, to: pasteboard)
    }

    /// 끌어 놓기 · 서비스 메뉴가 묻는 판 종류. **서식 없는 글자 하나**다 — NSTextView 기본은 RTF 를 앞세워 흰 글자째 싣는다(검토 P2).
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    /// 끌어 놓기 · 서비스 메뉴의 쓰기. ⌘C 와 **같은 글자**(`selectedText` — 링크는 실제 주소째)를 서식 없이 쓴다.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard types.contains(.string), let selectedText else { return false }
        pboard.declareTypes([.string], owner: nil)
        return pboard.setString(selectedText, forType: .string)
    }

    /// 한 종류씩 묻는 쓰기(끌기의 늦은 공급). 글자 말고는 쓰지 않는다.
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string, let selectedText else { return false }
        return pboard.setString(selectedText, forType: .string)
    }

    /// ⌘C · ⌘A 를 **첫 응답자일 때만** 직접 받는다. 이유는 입력칸의 같은 처리기(`CheckEditorTextView.performKeyEquivalent`)와 같다:
    /// 메뉴 막대가 안 보이는 앱이라 Edit 메뉴는 SwiftUI 의 보이지 않는 기본값이고, 그 값이 바뀌면 팝오버 안 복사가 조용히 죽는다.
    /// 첫 응답자 가드가 없으면 같은 창의 입력칸에 포커스가 있어도 이 말풍선이 ⌘C 를 가로챈다(`performKeyEquivalent` 는 뷰 계층 전체를 돈다).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option), !flags.contains(.shift) else {
            return super.performKeyEquivalent(with: event)
        }
        // 한글 자판의 ⌘C 는 `charactersIgnoringModifiers` 가 "ㅊ" 다 — 입력칸과 같은 판독을 쓴다.
        switch CheckEditorTextView.editingKey(characters: event.characters, ignoringModifiers: event.charactersIgnoringModifiers) {
        case "c": copy(nil)
        case "a": selectAll(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: 적중 판정

    /// 말풍선 틀 안이면 **어디든 이 뷰다**(여백 띠 포함 — 파일 머리 주석).
    ///
    /// ★ 2026-11-03 헤드리스 실측: NSTextView 의 기본 적중 판정은 **글자 상자 오른쪽 끝 너머**(오른쪽 여백 8pt)를 자기 것이 아니라고 답한다
    ///   (왼쪽 · 위 · 아래 여백은 받는다). 그대로 두면 오른쪽 여백의 우클릭이 바깥 호스팅 뷰로 떨어져 [신고] 메뉴가 안 뜬다.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hit = super.hitTest(point) { return hit }
        guard !isHidden, let superview else { return nil }
        return NSMouseInRect(point, frame, superview.isFlipped) ? self : nil
    }

    // MARK: 우클릭 메뉴

    /// 이 말풍선의 우클릭 메뉴. [복사]가 담을 글자는 **메뉴를 여는 순간** 정한다(`representedObject`).
    func bubbleMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let copy = NSMenuItem(title: ChatBubbleMenuText.copy, action: #selector(copyFromMenu(_:)), keyEquivalent: "")
        copy.target = self
        copy.representedObject = textToCopy
        copy.image = NSImage(systemSymbolName: ChatBubbleMenuText.copySymbol, accessibilityDescription: nil)
        menu.addItem(copy)
        if onReport != nil {
            let report = NSMenuItem(
                title: BlockReportText.reportMessageAction, action: #selector(reportFromMenu(_:)), keyEquivalent: ""
            )
            report.target = self
            report.image = NSImage(systemSymbolName: ChatBubbleMenuText.reportSymbol, accessibilityDescription: nil)
            menu.addItem(report)
        }
        return menu
    }

    @objc private func copyFromMenu(_ sender: NSMenuItem) {
        CheckPasteboard.copy(sender.representedObject as? String ?? textToCopy, to: pasteboard)
    }

    @objc private func reportFromMenu(_ sender: NSMenuItem) {
        onReport?()
    }

    /// 메뉴를 묻는 모든 길(우클릭 · 보이스오버의 메뉴 열기)이 이 메뉴를 받는다. **super 를 부르지 않는다** — 기본 구현은
    /// 눌린 자리의 낱말을 골라 버린다(파일 머리 주석의 실측).
    override func menu(for event: NSEvent) -> NSMenu? { bubbleMenu() }

    /// 우클릭. **super 를 부르지 않는다** — 기본 구현은 이 뷰를 첫 응답자로 만들어 쓰던 입력칸의 포커스를 가져간다.
    override func rightMouseDown(with event: NSEvent) {
        presentMenu(bubbleMenu(), event, self)
    }

    /// ⌃클릭도 우클릭이다. 그 밖의 누름은 NSTextView 그대로(끌어 고르기 · 두 번 눌러 낱말 · 링크) — 추적은 손을 뗄 때까지
    /// super 안에서 돈다. 끝난 뒤 포커스를 정리한다(`settleFocusAfterClick`). 갈래는 `routeMouseDown` 한 곳이다.
    override func mouseDown(with event: NSEvent) {
        routeMouseDown(event) { super.mouseDown(with: $0) }
    }

    /// 누름의 갈래 — ⌃클릭은 메뉴만, 나머지는 `track`(앱은 NSTextView 의 누름 추적) 뒤 포커스 정리.
    /// 시험은 `track` 을 기록기로 갈아 끼워 이 갈래를 **부르는 자리째** 잰다(진짜 추적은 앱 이벤트 대기열을 돌아 시험을 멈춘다).
    func routeMouseDown(_ event: NSEvent, track: (NSEvent) -> Void) {
        if Self.isContextClick(event) {
            presentMenu(bubbleMenu(), event, self)
            return
        }
        let previous = window?.firstResponder
        track(event)
        settleFocusAfterClick(previous: previous)
    }

    /// ⌃ 를 누른 채 누른 것인가(맥의 우클릭 대용).
    static func isContextClick(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.control)
    }

    /// 누름이 끝난 뒤의 포커스.
    ///  · **고른 글자가 있으면 이 말풍선이 포커스를 갖는다** — ⌘C 가 여기 와야 한다. NSTextView 의 누름 추적이 포커스를 가져가는지는
    ///    창 상태에 따라 다르므로(2026-11-03 헤드리스 실측: 키 창이 아닌 창에서는 끌어 골라도 안 가져갔다) 맡기지 않고 직접 쥔다.
    ///  · 끌지 않고 누르기만 했으면(링크 누름 포함) 쓰던 입력칸에 돌려준다. 돌려주는 상대는 **편집 중이던 글자 뷰**뿐이다
    ///    (필드 에디터·다른 말풍선은 아니다). 받은 말풍선은 예전에 눌러도 포커스를 안 가져갔다 — 그 감각을 지킨다.
    func settleFocusAfterClick(previous: NSResponder?) {
        guard let window else { return }
        if selectedText != nil {
            if window.firstResponder !== self { window.makeFirstResponder(self) }
            return
        }
        guard window.firstResponder === self else { return }
        guard let editor = previous as? NSTextView, editor !== self, editor.isEditable, !editor.isFieldEditor,
              editor.window === window else { return }
        window.makeFirstResponder(editor)
    }

    /// 포커스가 떠나면 고른 것을 지운다 — 다른 말풍선·입력칸으로 옮긴 뒤에도 옛 강조가 남아 여러 말풍선이 동시에 골라진 것처럼 보이지 않게.
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { setSelectedRange(NSRange(location: 0, length: 0)) }
        return resigned
    }

    // MARK: 링크

    /// 링크를 연다 — **여는 자리에서 스킴을 다시 본다**. 해석이 이미 http·https 만 링크로 만들지만, 이 문을 지나는 값은
    /// 글자 속성에서 온 것이라 해석 밖의 길(붙여넣은 서식 등)이 생겨도 여기서 막힌다. 열었으면 true.
    @discardableResult
    func followLink(_ link: Any) -> Bool {
        guard let url = Self.url(from: link), ChatMarkdown.isOpenable(url) else { return false }
        openLink(url)
        return true
    }

    /// 링크 속성 값은 URL 이거나 문자열이다(NSTextView 규약).
    static func url(from link: Any) -> URL? {
        if let url = link as? URL { return url }
        if let string = link as? String { return URL(string: string) }
        return nil
    }
}

/// 링크 누름을 받는 대리자 — 검사는 `ChatBubbleTextView.followLink` 한 곳이다.
@MainActor
final class ChatBubbleLinkGate: NSObject, NSTextViewDelegate {
    /// **언제나 true(처리했다)** 를 돌려준다. false 를 돌려주면 NSTextView 가 그 링크를 **검사 없이** NSWorkspace 로 연다 —
    /// 막아야 할 링크(javascript: 등)에서 false 를 주는 것이 바로 그 구멍이다.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        (textView as? ChatBubbleTextView)?.followLink(link)
        return true
    }
}

// MARK: - 줄 높이

/// 말풍선 본문의 **줄 높이와 기준선을 SwiftUI `Text` 와 같은 규칙으로** 정하는 배치 대리자. 글자 뷰와 높이 재기가 같이 쓴다.
///
/// **왜**(2026-11-03 실측 — 같은 글꼴 · 같은 폭): SwiftUI `Text` 의 한 줄은 10pt 13 · 13pt 16 · 15pt 19 · 17pt 20 인데, TextKit 1 기본은
/// 10pt 12(한글만 있는 줄은 대체 글꼴 탓에 10.3) · 15pt 18 이다. 그대로 두면 앱 말풍선이 스냅샷 · 예전 화면보다 줄마다 1~3pt 낮아진다
/// (ChatBubbleSelectionTests 의 두 갈래 픽셀 비교가 처음에 이 차이로 빨갰다: 한 줄 2pt · 제목+본문 4pt).
/// SwiftUI 의 값은 네 크기 모두 `round(ascender) + ceil(-descender)` 와 같다 — 기준선은 줄 위에서 `round(ascender)` 다.
/// 한 줄의 크기는 그 줄 글자의 가장 큰 글꼴 크기로 정하고(한 줄은 한 크기다 — 제목 줄 · 본문 줄), 지표는 **시스템 글꼴**에서 읽는다
/// (한글 대체 글꼴의 지표를 쓰면 TextKit 기본처럼 한글 줄만 낮아진다 — SwiftUI 는 한글 줄도 같은 높이다).
final class ChatBubbleLineMetrics: NSObject, NSLayoutManagerDelegate, Sendable {
    static let shared = ChatBubbleLineMetrics()

    /// 글꼴 크기 → (줄 높이, 줄 위에서 기준선까지).
    static func line(forPointSize size: CGFloat) -> (height: CGFloat, baseline: CGFloat) {
        let font = NSFont.systemFont(ofSize: size)
        let ascent = font.ascender.rounded()
        let descent = (-font.descender).rounded(.up)
        return (ascent + descent, ascent)
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        guard let storage = layoutManager.textStorage else { return false }
        let characters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var size: CGFloat = 0
        storage.enumerateAttribute(.font, in: characters) { value, _, _ in
            if let font = value as? NSFont { size = max(size, font.pointSize) }
        }
        let metrics = Self.line(forPointSize: size > 0 ? size : ChatMarkdownText.baseSize)
        lineFragmentRect.pointee.size.height = metrics.height
        lineFragmentUsedRect.pointee.size.height = metrics.height
        baselineOffset.pointee = metrics.baseline
        return true
    }
}

// MARK: - 높이 재기

/// 말풍선 본문의 크기를 잰다 — 글자 뷰와 **같은 TextKit 1 배치**(줄 조각 여백 0 · 같은 줄 높이 대리자)로. `ChatBubbleText.sizeThatFits` 가 부른다.
enum ChatBubbleTextLayout {
    /// 말풍선 여백(좌우 8 · 위아래 5pt). 앱 갈래는 글자 뷰 안쪽 여백(`textContainerInset`)으로, 스냅샷 갈래는 SwiftUI padding 으로 같은 값을 쓴다.
    /// 틀 높이 추정(`MessagePanelLayout.textBubbleHeight` 의 10)도 이 위아래 5×2 다.
    static let inset = NSSize(width: 8, height: 5)

    /// 말풍선 한 장(여백 포함)의 크기 — SwiftUI 가 제안한 말풍선 폭에서 여백을 뺀 폭에 글자를 배치하고 여백을 더한다
    /// (스냅샷 갈래의 `.padding` 이 하는 셈과 같다).
    static func bubbleSize(_ text: NSAttributedString, proposedWidth: CGFloat?) -> CGSize {
        let textWidth = proposedWidth.map { $0.isFinite ? $0 - 2 * inset.width : $0 }
        let fit = fittingSize(text, width: containerWidth(for: textWidth))
        return CGSize(width: fit.width + 2 * inset.width, height: fit.height + 2 * inset.height)
    }

    /// "폭 제한 없음"을 뜻하는 글자 상자 폭. 무한대(`.infinity`)를 그대로 주면 TextKit 이 배치를 못 한다.
    static let unboundedWidth: CGFloat = 10_000_000

    /// SwiftUI 가 제안한 폭 → 글자 상자 폭. nil·무한대는 제한 없음(한 줄로 펼친 폭).
    ///
    /// ★ **0 을 그대로 쓰지 않는다**(2026-11-03 헤드리스 실측): 폭 0 인 글자 상자는 TextKit 이 "제한 없음"으로 읽어 한 줄로 펼친다.
    ///   SwiftUI 는 가장 좁은 폭을 0 으로 물어보므로, 그대로 두면 "가장 좁아도 한 줄 전체 폭"이라고 답해 말풍선이 접히지 않는다.
    static func containerWidth(for proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite else { return unboundedWidth }
        return max(1, proposed)
    }

    /// `width` 폭에 배치했을 때 글자가 차지하는 크기(pt, 올림).
    static func fittingSize(_ text: NSAttributedString, width: CGFloat) -> CGSize {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        layout.delegate = ChatBubbleLineMetrics.shared
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return CGSize(width: ceil(used.width), height: ceil(used.height))
    }
}

// MARK: - SwiftUI 래퍼

/// 말풍선 본문(앱 갈래). 바탕(둥근 판)은 바깥(`MessageBubbleRow.textBubble`)이 그리고, **여백은 이 뷰 안**이다(파일 머리 주석 — 여백 띠의 우클릭 · 끌기).
///
/// 렌더 시험·스냅샷 갈래(`rendersPlainText`)는 이 뷰 대신 같은 조각 목록의 SwiftUI `Text` 를 그린다 — `ImageRenderer` 는 NSView 를 못 그린다.
struct ChatBubbleText: NSViewRepresentable {
    /// 말풍선에 그릴 글자(이모티콘 폴백을 지난 본문 — 마크다운 해석은 여기서 한다).
    let shown: String
    /// [복사]가 고른 글자 없이 담는 원문.
    let raw: String
    let isMine: Bool
    /// [이 메시지 신고하기]. 받은 말풍선에만 들어온다(`MessageBubbleReportRule`).
    var onReport: (() -> Void)?

    final class Coordinator {
        /// 지금 뷰가 그리는 글자. 같으면 글자를 다시 박지 않는다(고르던 구간이 날아간다).
        var shownKey: ShownKey?
        /// 폭별로 잰 크기. SwiftUI 는 한 번 배치에 같은 폭을 여러 번 묻는다.
        var measured: [CGFloat: CGSize] = [:]
    }

    struct ShownKey: Equatable {
        let shown: String
        let isMine: Bool
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ChatBubbleTextView {
        let view = ChatBubbleTextView.make()
        apply(to: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: ChatBubbleTextView, context: Context) {
        apply(to: view, coordinator: context.coordinator)
    }

    private func apply(to view: ChatBubbleTextView, coordinator: Coordinator) {
        view.rawBody = raw
        view.onReport = onReport
        let key = ShownKey(shown: shown, isMine: isMine)
        guard coordinator.shownKey != key else { return }
        coordinator.shownKey = key
        coordinator.measured = [:]
        view.show(shown, isMine: isMine)
    }

    /// 높이는 **제안된 폭에서 실제로 배치해** 잰다(줄 수 · 제목 크기에 따라 자라고, 폭이 좁으면 접힌다). 여백까지 더한 말풍선 한 장 크기다.
    /// 폭은 글자가 차지한 만큼만 돌려준다 — 짧은 말은 말풍선이 글자를 따라 줄어든다(`Text` 와 같은 감각).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChatBubbleTextView, context: Context) -> CGSize? {
        let key = proposal.width ?? -1
        if let cached = context.coordinator.measured[key] { return cached }
        let size = ChatBubbleTextLayout.bubbleSize(nsView.attributedString(), proposedWidth: proposal.width)
        context.coordinator.measured[key] = size
        return size
    }
}
