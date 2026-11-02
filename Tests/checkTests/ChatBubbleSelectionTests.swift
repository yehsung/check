import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 고를 수 있는 말풍선(대표 요청 2026-11-03 ④ · 대표 결정 "받은 말풍선도 드래그, 우클릭에 신고 유지").
//
// 앱의 말풍선 본문은 AppKit 글자 뷰(`ChatBubbleTextView`)다. 이 스위트는 **창을 화면에 올리지 않고** 그 뷰를 잰다:
//  ① 메뉴 — 진짜 대화 뷰(`MessageConversationView`)를 호스팅해 그 안의 말풍선이 받은/내 것에 따라 다른 메뉴를 세우고,
//     [신고]가 대화 뷰에 넘긴 `onReport` 를 **그 메시지로** 부르는지 본다(부르는 자리를 잰다 — 모양이 아니라).
//  ② 우클릭 — 메뉴만 띄우고 입력칸 포커스와 고른 것을 건드리지 않는다. 기준선: 평범한 NSTextView 의 기본 메뉴는 낱말을 고른다.
//  ③ 복사 — 고른 글자를 [복사]·⌘C 가 담고(서식 없이), 고른 것이 없으면 원문을 담는다. 시험 전용 붙여넣기판을 쓴다.
//     끌기가 말풍선에 닿는지는 호스팅한 대화의 적중 판정(`hitTest`)으로 본다.
//  ④ 링크 — 링크 글자 자리를 누르면 그 링크가 말풍선에 닿고, 여는 자리의 스킴 검사가 javascript: 등을 막는다. 브라우저 문은 기록기다.
//  ⑤ 글자 — AppKit 글자가 SwiftUI 대체 경로(스냅샷)와 글자·크기·굵기·링크·색이 같다(같은 조각 목록 `ChatMarkdownText.pieces`).
//  ⑥ 크기 — 높이는 줄 수·제목에 따라 자라고 폭이 좁으면 접힌다. 앱 갈래 말풍선이 스냅샷 갈래와 같은 자리·같은 크기다(AppKit 픽셀).
//  ⑦ 강조색 · 보이스오버 · 스크롤 휠.
//
// ★ **앱 이벤트 대기열(`NSApp.postEvent` · `nextEvent`)을 쓰지 않는다.** 2026-11-03 실측: 시험이 대기열에 누름을 넣고 NSTextView 의 누름
//   추적을 돌리면, 시험 프로세스의 바깥 런루프가 멈춰 `swift_task_asyncMainDrainQueue` 가 **exit(0)** 한다 — 요약 줄 없이 "초록"으로 끝난다
//   (atexit 백트레이스로 확인). 중첩 런루프로 감싸도 뒤 시험에서 같은 퇴장이 다시 났다(남은 주기 이벤트 등). 전체 스위트를 소리 없이 반토막 내는
//   위험이라, 누름 추적(끌어 고르기 · 링크 한 번 누름)은 AppKit 자체 동작으로 두고 여기서는 **그 추적이 닿는 자리와 그 뒤의 문**을 잰다:
//   적중 판정 · 선택 가능 · 링크 속성 · `clicked(onLink:at:)` · 누름 뒤 포커스 정리(`settleFocusAfterClick`). 끌어 고르기 실화면은 미확인이다.
// 같은 이유로 진짜 메뉴 팝업(메뉴 추적 루프)도 띄우지 않는다 — `presentMenu` 를 기록기로 갈아 끼운다.

private let cbNow = MessageReadFixture.now
private let cbPeer = MessageReadFixture.peerA

private func cbEntry(_ id: String, _ body: String, isMine: Bool, minutesAgo: Double = 1) -> MessageHistoryEntry {
    MessageHistoryEntry(
        id: id, peerUserID: cbPeer, peerName: "민수", peerAvatarURL: nil, body: body,
        createdAt: cbNow.addingTimeInterval(-minutesAgo * 60), isMine: isMine, readByPeer: nil, isUnread: nil
    )
}

/// 시험 전용 붙여넣기판 — 사용자의 일반 판을 덮지 않는다. 끝나면 놓는다.
@MainActor
private func cbWithBoard<T>(_ body: (NSPasteboard) throws -> T) rethrows -> T {
    let board = NSPasteboard(name: NSPasteboard.Name("check.test.chatbubble.\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    board.clearContents()
    return try body(board)
}

/// 기록기 — 브라우저 문 · 메뉴 문 · 신고 문을 갈아 끼울 때 쓴다.
@MainActor
private final class CBRecorder {
    var opened: [URL] = []
    var menus: [[String]] = []
    var reported: [String] = []
}

/// 말풍선 글자 뷰 하나(창 없이). `width` 에서 잰 크기로 틀을 세운다. 브라우저·메뉴 문은 **진짜를 못 쓰게** 막아 둔다.
@MainActor
private func cbBubble(_ shown: String, raw: String? = nil, isMine: Bool = false, width: CGFloat = 190) -> ChatBubbleTextView {
    let view = ChatBubbleTextView.make()
    view.show(shown, isMine: isMine)
    view.rawBody = raw ?? shown
    view.openLink = { url in Issue.record("시험이 진짜 브라우저 문을 열려 했다: \(url)") }
    view.presentMenu = { _, _, _ in Issue.record("시험이 진짜 메뉴를 띄우려 했다") }
    let size = ChatBubbleTextLayout.fittingSize(view.attributedString(), width: width)
    view.frame = NSRect(origin: NSPoint(x: 10, y: 20), size: size)
    return view
}

/// 화면에 올리지 않는 창 + 입력칸(편집 가능한 글자 뷰) + 말풍선.
@MainActor
private final class CBStage {
    let window: NSWindow
    let composer: NSTextView
    let bubble: ChatBubbleTextView

    init(_ bubble: ChatBubbleTextView) {
        _ = NSApplication.shared
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        window.contentView = content
        composer = NSTextView(frame: NSRect(x: 0, y: 190, width: 300, height: 40))
        composer.isEditable = true
        content.addSubview(composer)
        content.addSubview(bubble)
        self.bubble = bubble
    }

    /// 입력칸에 포커스를 둔다(대화 패널을 막 연 상태).
    func focusComposer() {
        window.makeFirstResponder(composer)
    }
}

@MainActor
private func cbMouse(
    _ type: NSEvent.EventType, at point: NSPoint, in view: NSView, flags: NSEvent.ModifierFlags = [], clickCount: Int = 1
) -> NSEvent {
    NSEvent.mouseEvent(
        with: type, location: view.convert(point, to: nil), modifierFlags: flags,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: view.window?.windowNumber ?? 0,
        context: nil, eventNumber: 0, clickCount: clickCount, pressure: type == .leftMouseUp ? 0 : 1
    )!
}

@MainActor
private func cbKey(_ characters: String, ignoring: String, in view: NSView) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: view.window?.windowNumber ?? 0, context: nil, characters: characters,
        charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: 8
    )!
}

private func cbTitles(_ menu: NSMenu?) -> [String] { menu?.items.map(\.title) ?? [] }

/// 글자 구간의 가운데 점(뷰 좌표 — 글자 뷰는 뒤집힌 좌표다).
@MainActor
private func cbPoint(of substring: String, in view: ChatBubbleTextView) throws -> NSPoint {
    let range = (view.string as NSString).range(of: substring)
    try #require(range.location != NSNotFound, "\"\(substring)\" 가 말풍선에 없다")
    let layout = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
    return NSPoint(x: rect.midX + view.textContainerOrigin.x, y: rect.midY + view.textContainerOrigin.y)
}

// MARK: 호스팅(앱 갈래 — AppKit 이 그린다)

@MainActor
private final class CBHost {
    let window: NSWindow
    let host: NSView

    init(_ view: some View, width: CGFloat, height: CGFloat) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: AnyView(view.frame(width: width, height: height).background(CheckTheme.background)))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        self.host = host
        settle()
    }

    func settle() {
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
    }

    func bubbles() -> [ChatBubbleTextView] { cbSubviews(of: host) }

    /// AppKit 이 그린 픽셀(2x).
    func bitmap() throws -> NSBitmapImageRep {
        settle()
        let size = host.bounds.size
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = size
        let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        host.displayIgnoringOpacity(host.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}

@MainActor
private func cbSubviews<T: NSView>(of root: NSView) -> [T] {
    var found: [T] = []
    if let match = root as? T { found.append(match) }
    for child in root.subviews { found += cbSubviews(of: child) }
    return found
}

/// 바탕과 다른 픽셀의 경계(픽셀). 잉크가 없으면 nil.
private func cbInk(_ bitmap: NSBitmapImageRep, against blank: NSBitmapImageRep) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
    guard bitmap.pixelsWide == blank.pixelsWide, bitmap.pixelsHigh == blank.pixelsHigh,
          let a = bitmap.bitmapData, let b = blank.bitmapData else { return nil }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            let d = abs(Int(a[o]) - Int(b[o])) + abs(Int(a[o + 1]) - Int(b[o + 1])) + abs(Int(a[o + 2]) - Int(b[o + 2]))
            guard d > 6 else { continue }
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return maxX < 0 ? nil : (minX, maxX, minY, maxY)
}

/// 흰 글자의 심(세 채널 모두 215 넘는 픽셀)의 경계(픽셀). 받은 말풍선은 왼쪽 아바타(흰 이니셜)를 피해 `avoidingLeft` 픽셀부터 본다.
/// 말풍선 바탕 · 흐린 시각 글자는 심에 안 걸린다.
private func cbGlyphCore(_ bitmap: NSBitmapImageRep, avoidingLeft: Int) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
    guard let data = bitmap.bitmapData else { return nil }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    for y in 0..<bitmap.pixelsHigh {
        for x in avoidingLeft..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            guard data[o] > 215, data[o + 1] > 215, data[o + 2] > 215 else { continue }
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return maxX < 0 ? nil : (minX, maxX, minY, maxY)
}

/// 그림을 `by` 픽셀 아래로 민 사본(맨 위는 첫 줄을 되풀이한다) — 무게중심 눈금의 기준선용.
private func cbShiftedDown(_ bitmap: NSBitmapImageRep, by rows: Int) -> NSBitmapImageRep? {
    guard let copy = bitmap.copy() as? NSBitmapImageRep, let src = bitmap.bitmapData, let dst = copy.bitmapData else { return nil }
    let bpr = bitmap.bytesPerRow
    for y in 0..<bitmap.pixelsHigh {
        let from = max(0, y - rows)
        memcpy(dst + y * bpr, src + from * bpr, bpr)
    }
    return copy
}

/// 말풍선 한 줄짜리 대화(날짜 구분선 없이 — 잉크가 말풍선 행뿐이게).
@MainActor
private func cbSingleBubble(_ entry: MessageHistoryEntry, plain: Bool) -> MessageConversationView {
    MessageConversationView(
        lines: [.bubble(entry)], peerUserID: cbPeer, lastMessageID: entry.id,
        clipsInsteadOfScrolling: true, rendersPlainText: plain
    )
}

private func cbRGB(_ color: NSColor) -> (Double, Double, Double, Double) {
    let c = color.usingColorSpace(.sRGB) ?? color
    return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
}

private func cbSameColor(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
    guard let lhs, let rhs else { return false }
    let a = cbRGB(lhs), b = cbRGB(rhs)
    return abs(a.0 - b.0) < 0.01 && abs(a.1 - b.1) < 0.01 && abs(a.2 - b.2) < 0.01 && abs(a.3 - b.3) < 0.01
}

/// `top` 을 `bottom` 위에 알파로 얹은 색(0...1).
private func cbOver(_ top: NSColor, _ bottom: (Double, Double, Double)) -> (Double, Double, Double) {
    let t = cbRGB(top)
    return (t.0 * t.3 + bottom.0 * (1 - t.3), t.1 * t.3 + bottom.1 * (1 - t.3), t.2 * t.3 + bottom.2 * (1 - t.3))
}

private func cbLuminance(_ c: (Double, Double, Double)) -> Double {
    func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
}

private func cbContrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
    let la = cbLuminance(a), lb = cbLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

private func cbDistance(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
    (abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)) * 255
}

@MainActor
@Suite("ChatBubbleSelection", .serialized)
struct ChatBubbleSelectionTests {

    // MARK: ① 메뉴 — 진짜 대화 뷰가 넘긴 문을 부른다

    /// 받은 말풍선: [복사] · [이 메시지 신고하기]. 내 말풍선: [복사]. [신고]는 **대화 뷰에 넘긴 `onReport` 를 그 메시지로** 부른다.
    /// 기준선: 같은 대화를 신고 문 없이(nil) 세우면 받은 말풍선에도 [복사]만 선다.
    @Test func 대화_뷰의_받은_말풍선은_복사와_신고를_띄우고_신고는_그_메시지를_넘긴다() throws {
        let entries = [
            cbEntry("r1", "**안녕** 하세요", isMine: false, minutesAgo: 3),
            cbEntry("m1", "네 [자료](https://a.example/doc) 봐요", isMine: true, minutesAgo: 2),
        ]
        let recorder = CBRecorder()
        func mount(report: Bool) -> CBHost {
            CBHost(
                MessageConversationView(
                    items: MessageThreadBuilder.timeline(entries, now: cbNow), peerUserID: cbPeer, lastMessageID: "m1",
                    clipsInsteadOfScrolling: true,
                    onReport: report ? { recorder.reported.append($0.id) } : nil
                ),
                width: MessagePanelLayout.contentWidth, height: 200
            )
        }
        let stage = mount(report: true)
        let bubbles = stage.bubbles()
        try #require(bubbles.count == 2, "앱 갈래 대화에 고를 수 있는 말풍선이 \(bubbles.count)개다(2개여야 한다)")
        let received = try #require(bubbles.first { $0.string == "안녕 하세요" }, "받은 말풍선이 마크다운을 지난 글자가 아니다: \(bubbles.map(\.string))")
        let mine = try #require(bubbles.first { $0.string == "네 자료 (a.example) 봐요" }, "\(bubbles.map(\.string))")

        let report = BlockReportText.reportMessageAction
        #expect(cbTitles(received.bubbleMenu()) == [ChatBubbleMenuText.copy, report])
        #expect(cbTitles(mine.bubbleMenu()) == [ChatBubbleMenuText.copy], "내 말풍선에 신고가 선다")
        // 메뉴를 묻는 문(`menu(for:)`)도 같은 메뉴다.
        let click = cbMouse(.rightMouseDown, at: NSPoint(x: 3, y: 3), in: received)
        let menu = try #require(received.menu(for: click))
        #expect(cbTitles(menu) == [ChatBubbleMenuText.copy, report])

        // [신고] → 대화 뷰에 넘긴 문이 **그 메시지 id** 로 불린다.
        menu.performActionForItem(at: 1)
        #expect(recorder.reported == ["r1"], "신고가 그 메시지로 안 불렸다: \(recorder.reported)")

        // [복사](고른 것 없음) → 원문 그대로(마크다운 기호째).
        try cbWithBoard { board in
            received.pasteboard = board
            received.bubbleMenu().performActionForItem(at: 0)
            #expect(board.string(forType: .string) == "**안녕** 하세요", "고른 것 없는 [복사]가 원문이 아니다")
            mine.pasteboard = board
            mine.bubbleMenu().performActionForItem(at: 0)
            #expect(board.string(forType: .string) == "네 [자료](https://a.example/doc) 봐요")
        }

        // 기준선: 신고 문이 없는 대화.
        let bare = mount(report: false)
        let bareReceived = try #require(bare.bubbles().first { $0.string == "안녕 하세요" })
        #expect(cbTitles(bareReceived.bubbleMenu()) == [ChatBubbleMenuText.copy])
        withExtendedLifetime((stage, bare)) {}
    }

    // MARK: ② 우클릭 · ⌃클릭

    /// 우클릭·⌃클릭은 메뉴만 띄운다 — 입력칸 포커스를 뺏지 않고 눌린 낱말을 고르지 않는다.
    /// (이 시험이 **멈추면** `rightMouseDown` 이 super 를 부르는 것이다 — 기본 구현은 진짜 메뉴 추적 루프를 돈다.)
    /// 기준선: 평범한 NSTextView 의 기본 메뉴(`menu(for:)`)는 눌린 낱말을 **고른다**(그러면 [복사]가 원문 대신 그 낱말을 담는다).
    @Test func 우클릭과_컨트롤_클릭은_메뉴만_띄우고_포커스와_고른_것을_건드리지_않는다() throws {
        let text = "hello world 안녕하세요 반가워요"
        let bubble = cbBubble(text, width: 260)
        bubble.onReport = {}
        let stage = CBStage(bubble)
        let recorder = CBRecorder()
        bubble.presentMenu = { menu, _, view in
            #expect(view === bubble)
            recorder.menus.append(cbTitles(menu))
        }
        stage.focusComposer()
        try #require(stage.window.firstResponder === stage.composer)
        let word = try cbPoint(of: "안녕하세요", in: bubble)

        bubble.rightMouseDown(with: cbMouse(.rightMouseDown, at: word, in: bubble))
        #expect(recorder.menus == [[ChatBubbleMenuText.copy, BlockReportText.reportMessageAction]])
        #expect(stage.window.firstResponder === stage.composer, "우클릭이 입력칸 포커스를 가져갔다")
        #expect(bubble.selectedText == nil, "우클릭이 낱말을 골랐다")
        #expect(bubble.menu(for: cbMouse(.rightMouseDown, at: word, in: bubble)) != nil)
        #expect(bubble.selectedText == nil, "메뉴를 묻는 문이 낱말을 골랐다")

        // ⌃클릭도 우클릭이다(맥의 우클릭 대용). 누름 추적을 돌리지 않으려고 판정만 잰다(머리 주석의 ★) — `mouseDown` 은 이 판정이 참이면
        // super(누름 추적)를 부르기 전에 같은 메뉴 문으로 간다.
        #expect(ChatBubbleTextView.isContextClick(cbMouse(.leftMouseDown, at: word, in: bubble, flags: .control)))
        #expect(!ChatBubbleTextView.isContextClick(cbMouse(.leftMouseDown, at: word, in: bubble)))
        #expect(!ChatBubbleTextView.isContextClick(cbMouse(.leftMouseDown, at: word, in: bubble, flags: .command)))

        // 기준선: 같은 글자 · 같은 배치(TextKit 1)의 평범한 NSTextView.
        let storage = NSTextStorage(attributedString: bubble.attributedString())
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: bubble.frame.width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let plain = NSTextView(frame: bubble.frame, textContainer: container)
        plain.isEditable = false
        stage.window.contentView?.addSubview(plain)
        plain.setSelectedRange(NSRange(location: 0, length: 0))
        _ = plain.menu(for: cbMouse(.rightMouseDown, at: word, in: plain))
        #expect(plain.selectedRange().length > 0, "기준선이 낱말을 안 골랐다 — 위 단언이 재는 것이 없다")
    }

    // MARK: ③ 복사

    /// 고른 글자를 [복사]·⌘C 가 담는다(서식 없이). 고른 것이 없으면 [복사]는 원문이다. 포커스가 떠나면 고른 것이 지워진다
    /// (여러 말풍선에 강조가 남지 않게). ⌘C 는 첫 응답자일 때만 받는다 — 기준선: 포커스 없는 말풍선은 입력칸의 ⌘C 를 가로채지 않는다.
    @Test func 고른_글자를_복사하고_고른_것이_없으면_원문을_복사한다() throws {
        let raw = "**굵게** 보기 그리고 더 긴 문장"
        let bubble = cbBubble(AingStickerText.preview(for: raw), raw: raw, width: 260)
        let stage = CBStage(bubble)
        try #require(bubble.string == "굵게 보기 그리고 더 긴 문장")
        #expect(bubble.isSelectable && !bubble.isEditable, "말풍선이 고를 수 없거나 고쳐 쓸 수 있다")

        // 끌어 고른 상태(누름 추적이 끝난 뒤): "보기 그리고 더" 를 고르고, 누름 뒤 정리가 포커스를 말풍선에 쥐여 준다.
        stage.focusComposer()
        let range = (bubble.string as NSString).range(of: "보기 그리고 더")
        bubble.setSelectedRange(range)
        bubble.settleFocusAfterClick(previous: stage.composer)
        let selected = try #require(bubble.selectedText)
        #expect(selected == "보기 그리고 더")
        #expect(stage.window.firstResponder === bubble, "고른 말풍선이 포커스를 안 가졌다 — ⌘C 가 입력칸으로 간다")

        try cbWithBoard { board in
            bubble.pasteboard = board
            // [복사]
            bubble.bubbleMenu().performActionForItem(at: 0)
            #expect(board.string(forType: .string) == selected)
            let rich: Set<NSPasteboard.PasteboardType> = [.rtf, .rtfd, .html]
            #expect(Set(board.types ?? []).isDisjoint(with: rich), "복사가 서식째 들어갔다(흰 글자가 흰 문서에 붙는다): \(board.types ?? [])")
            // 기준선: NSTextView 기본 쓰기는 서식(RTF)을 같이 싣는다 — 위 단언이 재는 차이다.
            board.clearContents()
            #expect(bubble.writeSelection(to: board, types: bubble.writablePasteboardTypes))
            #expect(!Set(board.types ?? []).isDisjoint(with: rich), "기준선이 서식을 안 실었다 — 위 단언이 재는 것이 없다")
            // ⌘C — 한글 자판(ignoring 'ㅊ')에서도.
            board.clearContents()
            #expect(bubble.performKeyEquivalent(with: cbKey("c", ignoring: "ㅊ", in: bubble)))
            #expect(board.string(forType: .string) == selected, "⌘C 가 고른 글자를 안 담았다")
            #expect(Set(board.types ?? []).isDisjoint(with: rich))
            // ⌘A 는 이 말풍선 전체를 고른다.
            #expect(bubble.performKeyEquivalent(with: cbKey("a", ignoring: "ㅁ", in: bubble)))
            #expect(bubble.selectedText == bubble.string)

            // 포커스가 떠나면 고른 것이 지워지고, [복사]는 원문으로 돌아간다.
            stage.focusComposer()
            #expect(bubble.selectedText == nil, "포커스가 떠났는데 강조가 남았다")
            bubble.bubbleMenu().performActionForItem(at: 0)
            #expect(board.string(forType: .string) == raw, "고른 것 없는 [복사]가 원문이 아니다")

            // 기준선: 첫 응답자가 아닌 말풍선은 ⌘C 를 가로채지 않는다(입력칸의 ⌘C 가 살아야 한다).
            bubble.setSelectedRange(NSRange(location: 0, length: 2))
            board.clearContents()
            #expect(!bubble.performKeyEquivalent(with: cbKey("c", ignoring: "c", in: bubble)), "포커스 없는 말풍선이 ⌘C 를 가로챘다")
            #expect(board.string(forType: .string) == nil)
        }
    }

    /// 끌기가 **말풍선 글자 뷰에 닿는다** — 호스팅한 진짜 대화에서 말풍선 글자 자리의 적중 판정이 그 글자 뷰다(위에 덮인 SwiftUI 층이
    /// 누름을 먹으면 끌어 고르기 · 링크 누름이 통째로 죽는다). 기준선: 같은 대화의 스냅샷 갈래(SwiftUI `Text`)에는 닿을 글자 뷰가 없다.
    @Test func 끌기와_링크_누름은_말풍선_글자_뷰에_닿는다() throws {
        let entries = [
            cbEntry("r1", "받은 말 [여기](https://a.example/x) 보기", isMine: false, minutesAgo: 3),
            cbEntry("m1", "내가 보낸 긴 말 한 줄", isMine: true, minutesAgo: 2),
        ]
        func mount(plain: Bool) -> CBHost {
            CBHost(
                MessageConversationView(
                    items: MessageThreadBuilder.timeline(entries, now: cbNow), peerUserID: cbPeer, lastMessageID: "m1",
                    clipsInsteadOfScrolling: true, rendersPlainText: plain
                ),
                width: MessagePanelLayout.contentWidth, height: 200
            )
        }
        let stage = mount(plain: false)
        let bubbles = stage.bubbles()
        try #require(bubbles.count == 2)
        for (bubble, word) in [(bubbles[0], "받은"), (bubbles[1], "보낸")] {
            let local = try cbPoint(of: word, in: bubble)
            let inHost = bubble.convert(local, to: stage.host)
            let hit = stage.host.hitTest(stage.host.superview?.convert(inHost, from: stage.host) ?? inHost)
            #expect(hit === bubble, "\(word) 자리를 누르면 말풍선 글자 뷰가 아니라 \(String(describing: hit)) 가 받는다")
        }
        // 링크 글자 자리에는 링크가 있고, 그 링크를 누르는 문은 검사를 지나 연다.
        let received = try #require(bubbles.first { $0.string.hasPrefix("받은") })
        let point = try cbPoint(of: "여기", in: received)
        let index = received.characterIndexForInsertion(at: point)
        let link = try #require(received.textStorage?.attribute(.link, at: min(index, (received.string as NSString).length - 1), effectiveRange: nil),
                                "링크 글자 자리에 링크가 없다")
        let recorder = CBRecorder()
        received.openLink = { recorder.opened.append($0) }
        received.clicked(onLink: link, at: index)
        #expect(recorder.opened.map(\.absoluteString) == ["https://a.example/x"], "링크 자리를 누른 링크가 안 열렸다: \(recorder.opened)")

        // 기준선.
        let snapshot = mount(plain: true)
        #expect(snapshot.bubbles().isEmpty, "스냅샷 갈래에 글자 뷰가 있다 — 위 적중 판정이 공허하다")
        withExtendedLifetime((stage, snapshot)) {}
    }

    /// 끌지 않고 누르기만 하면 쓰던 입력칸에 포커스를 돌려주고, 끌어 골랐으면 말풍선이 포커스를 쥔다(⌘C 가 와야 한다).
    /// 누름이 끝난 뒤의 정리(`settleFocusAfterClick` — `mouseDown` 이 super 의 누름 추적 뒤에 부른다)를 출발 상태별로 잰다.
    /// 기준선: 입력칸이 아니었던 출발(창 자신 · 다른 말풍선)은 돌려줄 곳이 없다.
    @Test func 끌지_않고_누르면_쓰던_입력칸에_포커스를_돌려준다() throws {
        let bubble = cbBubble("그냥 누르기만 하는 말풍선", width: 260)
        let stage = CBStage(bubble)

        // 누름 추적이 말풍선에 포커스를 준 뒤(키 창에서의 모습) — 고른 것 없음: 입력칸으로 돌려준다.
        stage.focusComposer()
        stage.window.makeFirstResponder(bubble)
        bubble.settleFocusAfterClick(previous: stage.composer)
        #expect(stage.window.firstResponder === stage.composer, "끌지 않은 누름 뒤 입력칸 포커스를 안 돌려준다")
        // 고른 것 있음: 말풍선이 쥔다(출발이 입력칸이어도, 추적이 포커스를 안 줬어도).
        bubble.setSelectedRange(NSRange(location: 0, length: 2))
        bubble.settleFocusAfterClick(previous: stage.composer)
        #expect(stage.window.firstResponder === bubble, "끌어 고른 뒤 말풍선이 포커스를 안 쥔다 — ⌘C 가 입력칸으로 간다")
        #expect(bubble.selectedText == "그냥", "포커스를 쥐며 고른 것을 잃었다")
        // 기준선: 출발이 입력칸이 아니면(창 자신) 돌려줄 곳이 없다.
        bubble.setSelectedRange(NSRange(location: 0, length: 0))
        bubble.settleFocusAfterClick(previous: stage.window)
        #expect(stage.window.firstResponder === bubble)
        // 편집 불가 글자 뷰(다른 말풍선)로도 돌려주지 않는다.
        let other = cbBubble("다른 말풍선")
        stage.window.contentView?.addSubview(other)
        bubble.settleFocusAfterClick(previous: other)
        #expect(stage.window.firstResponder === bubble, "다른 말풍선으로 포커스를 넘겼다")
    }

    // MARK: ④ 링크

    /// 링크를 누르면 여는 자리에서 스킴을 다시 본다 — javascript: · file: · ftp: 는 안 열린다. 대리자는 언제나 "처리했다"(true)를
    /// 돌려준다 — false 면 NSTextView 가 검사 없이 NSWorkspace 로 연다. 기준선: 같은 문에 https 는 열린다.
    @Test func 링크는_여는_자리에서_스킴을_다시_본다() throws {
        let bubble = cbBubble("[여기](https://a.example/x) 보기", width: 260)
        let recorder = CBRecorder()
        bubble.openLink = { recorder.opened.append($0) }
        let gate = try #require(bubble.delegate, "말풍선에 링크 대리자가 없다")
        let ask = { (link: Any) -> Bool? in gate.textView?(bubble, clickedOnLink: link, at: 0) }

        for bad: Any in [
            URL(string: "javascript:alert(1)")!, "javascript:alert(1)", URL(string: "file:///etc/passwd")!,
            URL(string: "ftp://a.example/f")!, URL(string: "https://")!,
        ] {
            #expect(ask(bad) == true, "대리자가 \(bad) 를 NSTextView 에 넘겼다(검사 없이 열린다)")
        }
        #expect(recorder.opened.isEmpty, "막아야 할 링크가 열렸다: \(recorder.opened)")
        try #require(ask(URL(string: "https://b.example")!) == true)
        #expect(recorder.opened.map(\.absoluteString) == ["https://b.example"])

        // NSTextView 의 링크 문(`clicked(onLink:at:)` — 누름 추적이 링크 위에서 손을 떼면 부르는 문)으로 들어와도 같은 검사를 지난다.
        // ★ 그 문은 대리자가 false 를 주면 **진짜 NSWorkspace 로 연다** — 대리자가 막는 링크에 true 를 주는지 먼저 못 박고 들어간다.
        recorder.opened = []
        try #require(ask(URL(string: "javascript:alert(2)")!) == true, "대리자가 막는 링크를 NSTextView 에 넘긴다 — 아래 호출이 진짜로 연다")
        bubble.clicked(onLink: URL(string: "javascript:alert(2)")!, at: 0)
        #expect(recorder.opened.isEmpty)
        bubble.clicked(onLink: URL(string: "https://a.example/x")!, at: 0)
        #expect(recorder.opened.map(\.absoluteString) == ["https://a.example/x"])
        // 붙인 호스트 꼬리표는 링크가 아니다.
        let tail = (bubble.string as NSString).range(of: "a.example")
        #expect(bubble.textStorage?.attribute(.link, at: tail.location, effectiveRange: nil) == nil, "호스트 꼬리표가 링크다")
        // 링크 색 — 내 말풍선(강조색 바탕)은 흰색, 받은 말풍선은 강조색.
        #expect(cbSameColor(bubble.linkTextAttributes?[.foregroundColor] as? NSColor, NSColor(CheckTheme.accent)))
        let mine = cbBubble("[여기](https://a.example/x)", isMine: true)
        #expect(cbSameColor(mine.linkTextAttributes?[.foregroundColor] as? NSColor, .white), "내 말풍선 링크가 바탕(강조색)에 묻힌다")
        #expect(mine.linkTextAttributes?[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue, "링크에 밑줄이 없다")
    }

    // MARK: ⑤ 글자 — 두 그리기가 같다

    /// AppKit 글자(앱)와 SwiftUI 글자(스냅샷)가 **같은 조각 목록**을 옮긴다: 글자 · 크기 · 굵기 · 링크 · 색.
    /// 표 + 시드 고정 무작위 300개. 조각 목록을 거치지 않고 따로 지으면 어느 한쪽이 갈려 빨개진다.
    @Test func AppKit_글자는_SwiftUI_글자와_같은_글자_크기_굵기_링크_색이다() throws {
        var bodies = [
            "안녕", "# 큰 제목", "## 중간 제목\n본문 **굵게** 끝", "### 작은\n\n빈 줄 뒤", "#### 넷째도 제목",
            "[여기](https://evil.example/login) 와 https://a.com/x", "**굵게**와 *기울임*과 ~~취소~~ `코드`",
            "[아잉:기쁨]", "줄\n바꿈\n셋", "ㅋㅋㅋ 🎉 **축하**",
        ]
        let tokens = ["**", "*", "#", "## ", "[", "](", ")", "https://a.co", "가", "a", " ", "\n", "🎉", "~~", "`", "_"]
        var seed: UInt64 = 0x00C4_A7B0_0B1E
        func next() -> UInt64 {
            seed &+= 0x9E37_79B9_7F4A_7C15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        for _ in 0..<300 {
            let length = Int(next() % 30) + 1
            bodies.append((0..<length).map { _ in tokens[Int(next() % UInt64(tokens.count))] }.joined())
        }

        for body in bodies {
            for isMine in [false, true] {
                let pieces = ChatMarkdownText.pieces(body)
                let ns = ChatMarkdownText.nsAttributed(body, isMine: isMine)
                let sw = ChatMarkdownText.attributed(body, isMine: isMine)
                #expect(ns.string == String(sw.characters), "글자가 갈렸다 — \(body.debugDescription)")
                #expect(ns.string == pieces.map(\.text).joined(), "AppKit 글자가 조각 목록과 다르다 — \(body.debugDescription)")
                let palette = ChatMarkdownText.AppKitPalette(isMine: isMine)
                var nsOffset = 0, scalarOffset = 0
                for piece in pieces {
                    let length = (piece.text as NSString).length
                    let scalars = piece.text.unicodeScalars.count
                    guard length > 0 else { continue }
                    defer { nsOffset += length; scalarOffset += scalars }
                    let what = "\(body.debugDescription) 조각 \(piece.text.debugDescription) mine=\(isMine)"

                    // AppKit — 조각 전체가 한 덩어리 속성이다.
                    var effective = NSRange()
                    let attributes = ns.attributes(at: nsOffset, longestEffectiveRange: &effective,
                                                   in: NSRange(location: nsOffset, length: length))
                    #expect(effective.length == length, "AppKit 조각이 갈렸다: \(what)")
                    let font = attributes[.font] as? NSFont
                    #expect(font?.pointSize == piece.size, "AppKit 크기: \(what)")
                    #expect((font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false) == piece.isBold, "AppKit 굵기: \(what)")
                    #expect((attributes[.link] as? URL) == piece.link, "AppKit 링크: \(what)")
                    let expectedColor: NSColor = switch piece.kind {
                    case .span: piece.link == nil ? palette.text : palette.link
                    case .lineBreak: palette.text
                    case .disclosure: palette.disclosure
                    }
                    #expect(cbSameColor(attributes[.foregroundColor] as? NSColor, expectedColor), "AppKit 색: \(what)")

                    // SwiftUI — 같은 자리의 조각.
                    let start = sw.unicodeScalars.index(sw.startIndex, offsetBy: scalarOffset)
                    let end = sw.unicodeScalars.index(start, offsetBy: scalars)
                    let runs = sw[start..<end].runs
                    #expect(runs.count == 1, "SwiftUI 조각이 갈렸다: \(what)")
                    guard let run = runs.first else { continue }
                    let expectedFont = piece.kind == .span
                        ? Font.system(size: piece.size, weight: piece.isBold ? .bold : .regular)
                        : Font.system(size: piece.size)
                    #expect(run[AttributeScopes.SwiftUIAttributes.FontAttribute.self] == expectedFont, "SwiftUI 글꼴: \(what)")
                    #expect(run.link == piece.link, "SwiftUI 링크: \(what)")
                    let swColor = run[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self]
                    switch piece.kind {
                    case .span where piece.link != nil:
                        #expect(cbSameColor(swColor.map { NSColor($0) }, palette.link), "SwiftUI 링크 색이 AppKit 과 다르다: \(what)")
                    case .disclosure:
                        #expect(cbSameColor(swColor.map { NSColor($0) }, palette.disclosure), "SwiftUI 꼬리표 색이 AppKit 과 다르다: \(what)")
                    default:
                        // 본문 색은 SwiftUI 쪽에서 `.foregroundStyle(ChatMarkdownText.bodyColor)` 가 칠한다(조각에는 없다).
                        #expect(swColor == nil, "SwiftUI 본문 조각에 색이 박혔다: \(what)")
                    }
                }
            }
        }

        // 제목 크기는 그 표 그대로 AppKit 글꼴에 실린다(앱 말풍선에서도 # 17 · ## 15 · ### 13 · 본문 10).
        for (body, size) in [("# 가", 17.0), ("## 가", 15.0), ("### 가", 13.0), ("가", 10.0)] {
            let font = ChatMarkdownText.nsAttributed(body, isMine: false).attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            #expect(font?.pointSize == CGFloat(size), "\(body) 가 \(font?.pointSize ?? 0)pt")
            #expect((font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false) == (size > 10), "\(body) 굵기")
        }
        // 색은 SwiftUI 쪽 색을 그대로 옮긴 값이다.
        #expect(cbSameColor(ChatMarkdownText.AppKitPalette(isMine: true).link, NSColor(ChatMarkdownText.linkColor(isMine: true))))
        #expect(cbSameColor(ChatMarkdownText.AppKitPalette(isMine: false).link, NSColor(CheckTheme.accent)))
        #expect(cbSameColor(ChatMarkdownText.AppKitPalette(isMine: false).text, NSColor(CheckTheme.primaryText)))
        #expect(cbSameColor(ChatMarkdownText.AppKitPalette(isMine: true).text, .white))
    }

    // MARK: ⑥ 크기

    /// 높이는 줄 수·제목에 따라 자라고, 폭이 좁으면 접힌다. 짧은 말은 글자만큼만 넓다.
    /// 기준선: TextKit 에 폭 0 을 그대로 주면 "제한 없음"으로 읽어 한 줄로 펼친다 — 그래서 0 은 1 로 고쳐 준다.
    @Test func 높이는_줄_수와_제목에_따라_자라고_폭이_좁으면_접힌다() throws {
        func size(_ body: String, _ width: CGFloat? = 190) -> CGSize {
            ChatBubbleTextLayout.fittingSize(
                ChatMarkdownText.nsAttributed(body, isMine: false), width: ChatBubbleTextLayout.containerWidth(for: width)
            )
        }
        #expect(size("가").height < size("가\n나").height && size("가\n나").height < size("가\n나\n다").height, "줄 수만큼 안 자란다")
        #expect(size("## 가").height > size("가").height + 3, "제목 줄이 본문 줄보다 높지 않다")
        #expect(size("# 가").height > size("### 가").height)
        let long = String(repeating: "오늘 회의는 세 시에 시작합니다 ", count: 3)
        #expect(size(long, 100).height > size(long, 190).height, "좁은 폭에서 안 접힌다")
        #expect(size(long, 100).width <= 100 && size(long, 190).width <= 190, "제안 폭을 넘는다")
        #expect(size("안녕").width < 40, "짧은 말이 말풍선을 넓힌다(\(size("안녕").width)pt)")
        #expect(size("안녕", nil) == size("안녕"), "폭 제한 없는 크기가 한 줄 크기와 다르다")

        // 폭 0 제안.
        #expect(ChatBubbleTextLayout.containerWidth(for: 0) == 1)
        #expect(ChatBubbleTextLayout.containerWidth(for: nil) == ChatBubbleTextLayout.unboundedWidth)
        #expect(ChatBubbleTextLayout.containerWidth(for: .infinity) == ChatBubbleTextLayout.unboundedWidth)
        let text = ChatMarkdownText.nsAttributed("가나 다라", isMine: false)
        let oneLine = ChatBubbleTextLayout.fittingSize(text, width: ChatBubbleTextLayout.unboundedWidth)
        #expect(ChatBubbleTextLayout.fittingSize(text, width: 0) == oneLine, "기준선이 바뀌었다 — TextKit 이 폭 0 을 다르게 읽는다")
        #expect(size("가나 다라", 0).height > oneLine.height, "가장 좁은 폭에서도 한 줄로 펼친다 — 말풍선이 안 접힌다")

        // 말풍선 뷰 자신의 배치가 잰 크기 안에 다 들어간다(잘리는 글자가 없다).
        for body in ["가\n나\n다", "## 회의 안건이 길어서 두 줄로 넘어가는 제목입니다", long] {
            let bubble = cbBubble(body)
            let layout = try #require(bubble.layoutManager), container = try #require(bubble.textContainer)
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            #expect(used.height <= bubble.frame.height + 0.5 && used.width <= bubble.frame.width + 0.5,
                    "말풍선 틀(\(bubble.frame.size))보다 글자(\(used.size))가 크다 — \(body.debugDescription)")
            #expect(layout.glyphRange(for: container).length == layout.numberOfGlyphs, "배치 안 된 글자가 있다")
        }
    }

    /// ★ **앱 갈래 말풍선은 스냅샷 갈래와 같은 자리·같은 크기다**(AppKit 이 그린 픽셀). 렌더 시험들은 스냅샷 갈래(SwiftUI `Text`)를 그리므로,
    /// 두 갈래의 말풍선 틀이 같아야 그 시험들이 앱 화면을 말한다. 같은 렌더러(호스팅 뷰)로 두 갈래를 그려 잉크 경계를 맞춘다.
    /// 기준선: 다른 본문(한 줄 더)은 경계가 확실히 다르다 — 이 비교가 공허하지 않다.
    @Test func 앱_갈래_말풍선은_스냅샷_갈래와_같은_자리_같은_크기다() throws {
        let bodies = [
            "안녕하세요",
            "오늘 회의는 세 시에 시작합니다. 자료는 미리 올려 두었으니 확인 부탁드려요",
            "## 제목\n본문 한 줄",
            "**굵게** 와 [링크](https://a.example/doc)",
            // 긴 한글 낱말 — 낱말 단위로 접어야 SwiftUI 와 같은 줄이 된다(AppKit 기본 접기는 낱말 가운데서 잘라 첫 줄이 꽉 찬다).
            "가나다라마바사아자차카타 파하가나다라마바사아자차 끝",
        ]
        let blank = try CBHost(Color.clear, width: MessagePanelLayout.contentWidth, height: 120).bitmap()
        func render(_ entry: MessageHistoryEntry, plain: Bool) throws -> NSBitmapImageRep {
            let host = CBHost(cbSingleBubble(entry, plain: plain), width: MessagePanelLayout.contentWidth, height: 120)
            if !plain { try #require(host.bubbles().count == 1, "앱 갈래에 글자 뷰가 없다") }
            return try host.bitmap()
        }
        func ink(_ bitmap: NSBitmapImageRep) throws -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
            try #require(cbInk(bitmap, against: blank), "아무것도 안 그려졌다")
        }
        for body in bodies {
            for isMine in [false, true] {
                let entry = cbEntry("b1", body, isMine: isMine)
                let appBitmap = try render(entry, plain: false), snapshotBitmap = try render(entry, plain: true)
                let app = try ink(appBitmap), snapshot = try ink(snapshotBitmap)
                let deltas = [app.minX - snapshot.minX, app.maxX - snapshot.maxX, app.minY - snapshot.minY, app.maxY - snapshot.maxY]
                #expect(deltas.allSatisfy { $0 == 0 },
                        "앱 갈래(\(app))와 스냅샷 갈래(\(snapshot))의 말풍선 틀이 다르다 — \(body.debugDescription) mine=\(isMine) Δ\(deltas)")
                // 글자의 세로 자리(기준선 · 줄 간격)까지 같다 — 말풍선 안 흰 글자 심(세 채널 모두 밝은 픽셀)의 위아래 경계의 **가운데**를 맞춘다.
                // 화면 전체 픽셀 차이 · 무게중심 · 가로 경계로 재지 않는 이유(실측): 호스팅 뷰에 AppKit 글자 뷰가 끼면 같은 SwiftUI 글자(시각 ·
                // 아바타)까지 다듬기(안티에일리어싱)가 달라져 획이 0.5~1px 굵어진다. 굵어짐은 위아래로 고르게 번지므로 경계의 가운데는 제자리다.
                // 가로 자리는 말풍선 틀 폭(위 단언 — 글자 폭 + 여백)이 이미 같다. 링크가 든 본문은 밑줄 자리(엔진마다 ±1pt)가 심에 섞여 뺀다.
                guard !body.contains("](") else { continue }
                let appGlyphs = try #require(cbGlyphCore(appBitmap, avoidingLeft: isMine ? 0 : 60), "앱 갈래 글자가 안 그려졌다")
                let snapshotGlyphs = try #require(cbGlyphCore(snapshotBitmap, avoidingLeft: isMine ? 0 : 60))
                let middle = Double(appGlyphs.minY + appGlyphs.maxY - snapshotGlyphs.minY - snapshotGlyphs.maxY) / 2
                #expect(abs(middle) <= 1,
                        "글자 세로 자리가 다르다(가운데 Δ\(middle)px) — 앱 \(appGlyphs) · 스냅샷 \(snapshotGlyphs) — \(body.debugDescription) mine=\(isMine)")
            }
        }
        // 기준선: 한 줄 더한 본문은 틀이 확실히 높고 픽셀도 크게 다르다 — 위 두 눈금이 공허하지 않다.
        let oneBitmap = try render(cbEntry("b1", "안녕하세요", isMine: false), plain: false)
        let twoBitmap = try render(cbEntry("b1", "안녕하세요\n한 줄 더", isMine: false), plain: false)
        #expect(try ink(twoBitmap).minY < (try ink(oneBitmap).minY) - 10, "한 줄 더한 본문이 더 높지 않다 — 앱 갈래가 줄 수만큼 안 자란다")
        // 기준선: 같은 그림을 2px(1pt) 아래로 민 사본은 이 눈금에 걸린다(기준선 1pt 어긋남을 가른다).
        let snapshotOne = try render(cbEntry("b1", "안녕하세요", isMine: false), plain: true)
        let shifted = try #require(cbShiftedDown(snapshotOne, by: 2))
        let base = try #require(cbGlyphCore(snapshotOne, avoidingLeft: 60))
        let moved = try #require(cbGlyphCore(shifted, avoidingLeft: 60))
        #expect(Double(moved.minY + moved.maxY - base.minY - base.maxY) / 2 > 1, "세로 자리 눈금이 1pt 어긋남을 못 가른다(\(base) → \(moved))")
    }

    // MARK: ⑦ 강조색 · 보이스오버 · 스크롤

    /// 고른 영역 강조가 **파란 내 말풍선에서도 보이고**, 흰 글자가 그 위에서 읽힌다. 받은 말풍선도 같다.
    /// 기준선: 같은 계열(강조색)을 깔면 내 말풍선에서 거의 안 보인다 — 이 거리 눈금이 그 차이를 가른다.
    @Test func 고른_영역_강조는_파란_내_말풍선에서도_보인다() {
        let panel = (0.10, 0.11, 0.15)
        let mineBubble = cbOver(NSColor(CheckTheme.accent).withAlphaComponent(0.85), panel)
        let receivedBubble = cbOver(NSColor.white.withAlphaComponent(0.10), panel)
        let mineSelected = cbOver(ChatMarkdownText.nsSelectionColor(isMine: true), mineBubble)
        let receivedSelected = cbOver(ChatMarkdownText.nsSelectionColor(isMine: false), receivedBubble)
        #expect(cbDistance(mineSelected, mineBubble) >= 60, "내 말풍선 강조가 바탕과 구별이 안 된다")
        #expect(cbDistance(receivedSelected, receivedBubble) >= 60, "받은 말풍선 강조가 바탕과 구별이 안 된다")
        #expect(cbContrast((1, 1, 1), mineSelected) >= 3, "고른 흰 글자가 강조 위에서 안 읽힌다")
        #expect(cbContrast((0.94, 0.94, 0.94), receivedSelected) >= 3)
        // 기준선.
        let sameHue = cbOver(NSColor(CheckTheme.accent).withAlphaComponent(0.45), mineBubble)
        #expect(cbDistance(sameHue, mineBubble) < 60, "기준선이 바뀌었다 — 눈금이 재는 것이 없다")
        // 뷰가 실제로 그 색을 쓴다.
        let mine = cbBubble("내 말", isMine: true)
        #expect(cbSameColor(mine.selectedTextAttributes[.backgroundColor] as? NSColor, ChatMarkdownText.nsSelectionColor(isMine: true)))
        #expect(mine.selectedTextAttributes[.foregroundColor] == nil, "강조가 글자색을 바꾼다")
    }

    /// 보이스오버는 말풍선에 **보이는 글자**(기호를 벗긴 본문 + 호스트 꼬리표)를 그대로 읽는다 — 앱 갈래 대화의 AX 트리에서 잰다.
    @Test func 보이스오버는_말풍선_글자를_그대로_읽는다() throws {
        let key = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        let app = NSApplication.shared
        app.accessibilitySetValue(true, forAttribute: key)
        defer { app.accessibilitySetValue(false, forAttribute: key) }
        let entries = [cbEntry("r1", "**안녕** [자료](https://a.example/doc)", isMine: false)]
        let host = CBHost(
            MessageConversationView(
                items: MessageThreadBuilder.timeline(entries, now: cbNow), peerUserID: cbPeer, lastMessageID: "r1",
                clipsInsteadOfScrolling: true
            ),
            width: MessagePanelLayout.contentWidth, height: 120
        )
        var values: [String] = []
        func walk(_ node: Any, depth: Int) {
            guard depth < 14, let object = node as? NSObject else { return }
            for selector in ["accessibilityValue", "accessibilityLabel"] {
                let sel = NSSelectorFromString(selector)
                if object.responds(to: sel), let text = object.perform(sel)?.takeUnretainedValue() as? String, !text.isEmpty {
                    values.append(text)
                }
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: children), let list = object.perform(children)?.takeUnretainedValue() as? [Any] {
                for child in list { walk(child, depth: depth + 1) }
            }
        }
        walk(host.host, depth: 0)
        #expect(values.contains("안녕 자료 (a.example)"), "말풍선 글자가 보이스오버에 없다: \(values)")
        #expect(!values.contains { $0.contains("**") || $0.contains("](") }, "보이스오버가 마크다운 기호를 읽는다: \(values)")
    }

    /// 말풍선 위에서 굴린 스크롤 휠이 **대화의 스크롤 뷰에 닿는다**(글자 뷰가 휠을 삼키면 말풍선이 빽빽한 대화는 스크롤이 안 된다).
    /// 휠을 진짜 스크롤 뷰까지 굴리지는 않는다 — 스크롤 뷰의 휠 처리는 앱 이벤트 대기열을 건드린다(머리 주석의 ★). 대신 두 사실을 잰다:
    /// (가) 말풍선은 받은 휠을 다음 응답자에게 넘긴다(기록기를 다음 응답자로 꽂아 본다), (나) 대화 안 말풍선의 응답자 사슬에 대화 스크롤 뷰가 있다.
    @Test func 말풍선_위의_휠은_대화_스크롤_뷰로_간다() throws {
        final class WheelRecorder: NSResponder {
            var wheels = 0
            override func scrollWheel(with event: NSEvent) { wheels += 1 }
        }
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 80, wheel2: 0, wheel3: 0))
        let wheel = try #require(NSEvent(cgEvent: cg))
        // (가)
        let loose = cbBubble("휠 시험")
        let recorder = WheelRecorder()
        loose.nextResponder = recorder
        loose.scrollWheel(with: wheel)
        #expect(recorder.wheels == 1, "말풍선이 휠을 삼켰다")
        // (나)
        let entries = (0..<24).map { index in
            cbEntry("s\(index)", "스크롤 시험 말풍선 \(index) — 대화가 틀보다 길어야 한다", isMine: index % 2 == 0, minutesAgo: Double(60 - index))
        }
        let host = CBHost(
            MessageConversationView(items: MessageThreadBuilder.timeline(entries, now: cbNow), peerUserID: cbPeer, lastMessageID: "s23"),
            width: MessagePanelLayout.contentWidth, height: 200
        )
        let scroll = try #require(cbSubviews(of: host.host).first as NSScrollView?, "대화에 스크롤 뷰가 없다")
        let bubble = try #require(host.bubbles().first, "앱 갈래 대화에 글자 뷰가 없다")
        var responder: NSResponder? = bubble.nextResponder
        var reaches = false
        while let current = responder {
            if current === scroll { reaches = true; break }
            responder = current.nextResponder
        }
        #expect(reaches, "말풍선의 응답자 사슬에 대화 스크롤 뷰가 없다 — 넘긴 휠이 대화에 안 닿는다")
        #expect(bubble.enclosingScrollView === scroll)
        withExtendedLifetime(host) {}
    }
}
