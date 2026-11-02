import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 채팅 마크다운(대표 요청 2026-11-03 ③④ — "## 글자 로 글자 크기 키우거나" · "링크는 클릭해서 브라우저 열리게").
// 범위는 대표 결정 "제목·굵게·링크만"(나머지 문법은 기호 그대로)이다.
//
// 이 스위트가 지키는 것:
//  ① **해석 결과를 값으로 잰다** — 줄 종류 · 조각의 글자 · 굵기 · 링크. 표 하나에 입력과 기대를 나란히 둔다.
//     받지 않는 문법(기울임 · 취소선 · 코드 · 울타리 · 글머리 · 번호 · 인용)은 "그대로 남는다"를 **글자 값으로** 잰다.
//  ② **링크는 http·https 만**이다. `javascript:` · `file:` · 사용자 정의 스킴은 원문 글자 그대로다.
//  ③ **글자 보존**: 해석이 어떤 입력에서도 내용 글자를 버리거나 지어내지 않고, 받지 않는 기호는 한 글자도 안 건드린다 —
//     손으로 고른 표 + 시드 고정 무작위 3천 개.
//  ④ **화면이 해석을 지난다**: 말풍선을 실제로 그려 `##` 가 더 높게 그려지는지(픽셀) · 기호가 사라졌는지(폭)를 본다.
//     규칙만 재면 뷰가 그 규칙을 안 부르는 결함이 초록으로 지나간다(이 저장소의 "두 겹 게이트" 함정).
//
// 소스 계약은 주석을 걷어낸 뒤 잰다.

// MARK: - 길잡이

private let cmNow = Date(timeIntervalSince1970: 1_790_000_000)
private let cmPeer = MessageReadFixture.peerA

/// 줄 하나의 (글자, 굵게, 링크) 목록 — 표의 기대값 모양.
private typealias CMRun = (text: String, bold: Bool, link: String?)

private func cmRuns(_ line: ChatMarkdownLine) -> [CMRun] {
    line.spans.map { ($0.text, $0.isBold, $0.link?.absoluteString) }
}

private func cmSame(_ lhs: [CMRun], _ rhs: [CMRun]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.text == $1.text && $0.bold == $1.bold && $0.link == $1.link }
}

private func cmDescribe(_ runs: [CMRun]) -> String {
    runs.map { "(\"\($0.text)\", \($0.bold ? "굵게" : "-"), \($0.link ?? "-"))" }.joined(separator: " ")
}

/// 한 줄짜리 본문을 해석한 조각들.
private func cmInline(_ body: String) -> [CMRun] {
    let lines = ChatMarkdown.parse(body)
    #expect(lines.count == 1, "\"\(body)\" 가 한 줄로 해석되지 않았다(\(lines.count)줄)")
    return lines.first.map(cmRuns) ?? []
}

/// 해석이 그리는 글자 전부(줄 사이는 "\n"). 그리는 쪽이 덧붙이는 것은 링크 호스트 꼬리표뿐이다(여기 없다).
private func cmVisible(_ body: String) -> String {
    ChatMarkdown.parse(body).map(\.text).joined(separator: "\n")
}

/// 원문 줄들 — 해석과 같은 자르기(`isNewline`).
private func cmRows(_ body: String) -> [String] {
    body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
}

/// 받는 세 문법의 기호(빠져도 되는 글자). 이것과 공백을 뺀 나머지가 **내용 글자**다.
/// `_` · `~` · `` ` `` · `>` · `-` · `+` 는 기호가 아니다 — 내용으로 센다(대표 결정 "나머지 문법은 기호 그대로").
private let cmSyntax: Set<Character> = ["#", "*", "[", "]", "(", ")"]

private func cmContent(_ text: String) -> [Character: Int] {
    var bag: [Character: Int] = [:]
    for char in text where !char.isWhitespace && !cmSyntax.contains(char) { bag[char, default: 0] += 1 }
    return bag
}

/// `needle` 의 글자가 `haystack` 에 **같은 차례로** 다 들어 있는가(빠질 수는 있어도 새로 생기거나 순서가 바뀌지 않는다).
private func cmIsSubsequence(_ needle: String, of haystack: String) -> Bool {
    var cursor = haystack.startIndex
    for char in needle {
        guard let found = haystack[cursor...].firstIndex(of: char) else { return false }
        cursor = haystack.index(after: found)
    }
    return true
}

/// 시드 고정 난수(SplitMix64) — 무작위 시험이 돌 때마다 같은 입력을 만든다(빨강이 재현된다).
private struct CMRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let cmFuzzTokens = [
    "*", "**", "_", "__", "~", "~~", "`", "``", "```", "[", "]", "(", ")", "](", "#", "## ", "> ", "- ", "1. ",
    " ", "\n", "\n", "가", "나", "a", "b", "7", ".", ":", "/", "!", "ㅋ", "🎉",
    "https://a.co", "http://b.io/x_y", "javascript:", "file:", "snake_case",
]

private func cmFuzzBodies(seed: UInt64, count: Int) -> [String] {
    var random = CMRandom(state: seed)
    return (0..<count).map { _ in
        let length = Int.random(in: 1...40, using: &random)
        return (0..<length).map { _ in cmFuzzTokens.randomElement(using: &random)! }.joined()
    }
}

private enum CMRenderError: Error { case failed }

@MainActor
private func cmBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw CMRenderError.failed }
    return bitmap
}

/// 말풍선을 그리는 두 갈래(2026-11-03 ④ 뒤). 픽셀 시험은 **둘 다** 돈다 — 한 갈래만 재면 다른 갈래의 회귀가 초록으로 지나간다.
///  · `snapshot` — 스냅샷·렌더 시험이 그리는 SwiftUI `Text` 갈래(`rendersPlainText`), `ImageRenderer` 로 굽는다.
///  · `app` — 앱이 그리는 AppKit 글자 뷰 갈래(`ChatBubbleText`). `ImageRenderer` 는 NSView 를 못 그리므로 화면에 올리지 않는 창의
///    호스팅 뷰를 AppKit 이 직접 그린 픽셀로 받는다.
enum CMPath: String, CaseIterable, Sendable {
    case snapshot, app
}

/// AppKit 이 그린 픽셀(2x) — 화면에 올리지 않는 창에 붙인 호스팅 뷰.
@MainActor
private func cmAppKitBitmap(_ view: some View, width: CGFloat, height: CGFloat) throws -> NSBitmapImageRep {
    let host = NSHostingView(rootView: AnyView(view))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    host.layoutSubtreeIfNeeded()
    let rep = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    rep.size = NSSize(width: width, height: height)
    let context = try #require(NSGraphicsContext(bitmapImageRep: rep))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    host.displayIgnoringOpacity(host.bounds, in: context)
    NSGraphicsContext.restoreGraphicsState()
    withExtendedLifetime(window) {}
    return rep
}

/// 말풍선 하나짜리 대화 한 판(진짜 `MessageConversationView` — 말풍선 행이 해석을 지나는지까지 함께 잰다).
@MainActor
private func cmConversation(body: String, isMine: Bool = false, height: CGFloat = 160, path: CMPath = .snapshot) throws -> NSBitmapImageRep {
    let entries = [MessageHistoryEntry(
        id: "md1", peerUserID: cmPeer, peerName: "민수", peerAvatarURL: nil, body: body,
        createdAt: cmNow.addingTimeInterval(-60), isMine: isMine, readByPeer: nil, isUnread: nil
    )]
    let view = MessageConversationView(
        items: MessageThreadBuilder.timeline(entries, now: cmNow),
        peerUserID: cmPeer,
        lastMessageID: entries.last?.id,
        clipsInsteadOfScrolling: true,
        rendersPlainText: path == .snapshot
    )
    .frame(width: MessagePanelLayout.contentWidth, height: height)
    .background(CheckTheme.background)
    switch path {
    case .snapshot: return try cmBitmap(view)
    case .app: return try cmAppKitBitmap(view, width: MessagePanelLayout.contentWidth, height: height)
    }
}

@MainActor
private func cmBlank(matching bitmap: NSBitmapImageRep, path: CMPath = .snapshot) throws -> NSBitmapImageRep {
    let width = CGFloat(bitmap.pixelsWide) / 2, height = CGFloat(bitmap.pixelsHigh) / 2
    let blank = Color.clear.frame(width: width, height: height).background(CheckTheme.background)
    switch path {
    case .snapshot: return try cmBitmap(blank)
    case .app: return try cmAppKitBitmap(blank, width: width, height: height)
    }
}

/// 바탕과 다른 픽셀의 경계(픽셀 — scale 2). 잉크가 없으면 nil. `bottomRows` 를 주면 그림 **아래쪽 그만큼의 줄만** 본다 —
/// 대화는 아래에 붙으므로 맨 아래가 말풍선 행이고, 그 위의 날짜 구분선(폭 전체를 긋는 선)을 빼고 잴 때 쓴다.
private func cmInk(
    _ bitmap: NSBitmapImageRep,
    against blank: NSBitmapImageRep,
    bottomRows: Int? = nil
) -> (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
    guard bitmap.pixelsWide == blank.pixelsWide, bitmap.pixelsHigh == blank.pixelsHigh,
          let a = bitmap.bitmapData, let b = blank.bitmapData else { return nil }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    for y in max(0, bitmap.pixelsHigh - (bottomRows ?? bitmap.pixelsHigh))..<bitmap.pixelsHigh {
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

private func cmSource(_ name: String) throws -> String {
    cmStripComments(try String(
        contentsOf: CheckCoreSourceLayout.repoRoot
            .appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)"),
        encoding: .utf8
    ))
}

/// `//`·`/* */` 주석을 걷어낸다(문자열 안의 `//` 는 남긴다).
private func cmStripComments(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out
}

private func cmRegion(_ source: String, from start: String, to end: String) -> String? {
    guard let head = source.range(of: start) else { return nil }
    let tail = source.range(of: end, range: head.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
    return String(source[head.upperBound..<tail])
}

// MARK: - ① 해석 — 값으로 잰다

@Suite("ChatMarkdownParser")
struct ChatMarkdownParserTests {

    /// 제목은 단계마다 커진다 — `##` 는 본문의 1.5배다. 줄 머리 `#` 뒤에 공백이 없으면 제목이 아니다(`#해시태그`).
    @Test func 제목은_단계마다_커지고_해시태그는_글자다() {
        let kinds = ChatMarkdown.parse("# 하나\n## 둘\n### 셋\n#### 넷").map(\.kind)
        #expect(kinds == [.heading(level: 1), .heading(level: 2), .heading(level: 3), .heading(level: 4)])
        #expect(ChatMarkdown.parse("## 둘").first?.text == "둘", "제목 기호가 글자에 남았다")

        let base = ChatMarkdownText.baseSize
        let h1 = ChatMarkdownText.fontSize(for: .heading(level: 1))
        let h2 = ChatMarkdownText.fontSize(for: .heading(level: 2))
        let h3 = ChatMarkdownText.fontSize(for: .heading(level: 3))
        #expect(h1 > h2 && h2 > h3 && h3 > base, "제목 크기가 단계적이지 않다: \(h1) \(h2) \(h3) \(base)")
        #expect(h2 >= base * 1.4, "## 가 눈에 띄게 크지 않다(\(h2)pt · 본문 \(base)pt)")
        #expect(ChatMarkdownText.fontSize(for: .heading(level: 6)) == h3, "#### 이하가 ### 보다 커졌다")
        #expect(ChatMarkdownText.fontSize(for: .paragraph) == base)

        // 대조군: 기호 뒤 공백이 없거나 내용이 없으면 제목이 아니다 — 글자 그대로다.
        for body in ["#해시태그", "##", "## ", "####### 일곱"] {
            let line = ChatMarkdown.parse(body).first
            #expect(line?.kind == .paragraph || line?.kind == .blank, "\"\(body)\" 가 \(String(describing: line?.kind)) 로 해석됐다")
            if line?.kind == .paragraph { #expect(line?.text == body, "\"\(body)\" 의 글자가 바뀌었다") }
        }
    }

    /// 받는 줄 안 문법은 **굵게와 링크 둘뿐**이다 — 입력 하나하나에 대해 나온 조각(글자 · 굵기 · 링크)이 무엇인가.
    @Test func 받는_줄_안_문법은_굵게와_링크_둘뿐이다() {
        let table: [(String, [CMRun])] = [
            ("**굵게**", [("굵게", true, nil)]),
            ("앞 **굵게** 뒤", [("앞 ", false, nil), ("굵게", true, nil), (" 뒤", false, nil)]),
            // 조사가 붙는 한국어 — `**` 는 단어 안에서도 켜진다(홑 `*` 는 아예 기호가 아니다 — 아래 `2*3*4` · 가림표).
            ("이건**중요**해", [("이건", false, nil), ("중요", true, nil), ("해", false, nil)]),
            ("**\"인용\"** 과 **(중요)**", [("\"인용\"", true, nil), (" 과 ", false, nil), ("(중요)", true, nil)]),
            // `*` 셋 묶음은 마지막 둘이 짝이다 — 남은 홑 `*` 는 기울임이 아니라 글자다.
            ("***둘 다***", [("*둘 다*", true, nil)]),
            ("[글](https://a.com)", [("글", false, "https://a.com")]),
            ("[**굵은 글**](https://a.com/x?y=1)", [("굵은 글", true, "https://a.com/x?y=1")]),
            ("https://a.com 보세요", [("https://a.com", false, "https://a.com"), (" 보세요", false, nil)]),
            ("**https://a.com**", [("https://a.com", true, "https://a.com")]),
            ("**[글](https://a.com)** 봐", [("글", true, "https://a.com"), (" 봐", false, nil)]),
        ]
        for (body, expected) in table {
            let runs = cmInline(body)
            #expect(cmSame(runs, expected), "\"\(body)\" → \(cmDescribe(runs)) · 기대 \(cmDescribe(expected))")
        }
    }

    /// ★ **받지 않는 문법은 입력한 글자 그대로다**(대표 결정 "제목·굵게·링크만 — 나머지 문법은 기호 그대로").
    /// 해석 글자 · 줄 종류 · 굵기 · 링크, 그리고 **말풍선이 그리는 글자**까지 값으로 잰다. 그린 글이 한 덩어리(run 하나)면
    /// 기울임 · 취소선 · 고정폭 · 바탕색 같은 꾸밈 속성도 하나 안 붙은 것이다(붙으면 그 자리에서 덩어리가 갈린다).
    @Test(arguments: [
        "*기울임*",
        "_기울임_",
        "__굵게 아님__",
        "~~취소~~",
        "`코드`",
        "``a`b``",
        "```let x```",
        "```swift",
        "- 사과",
        "* 배",
        "+ 감",
        "  - 안쪽",
        "1. 하나",
        "12) 열둘",
        "> 인용",
        ">> 겹 인용",
        "    들여쓴 줄",
        "*a* _b_ ~~c~~ `d`",
    ])
    func 받지_않는_문법은_입력한_글자_그대로다(body: String) {
        let lines = ChatMarkdown.parse(body)
        #expect(lines.map(\.kind) == [.paragraph], "\"\(body)\" 가 \(lines.map(\.kind)) 로 해석됐다")
        #expect(cmVisible(body) == body, "\"\(body)\" → \"\(cmVisible(body))\"")
        let spans = lines.flatMap(\.spans)
        #expect(spans.allSatisfy { !$0.isBold && $0.link == nil }, "\"\(body)\" 에 굵게·링크가 생겼다: \(spans)")

        let drawn = ChatMarkdownText.attributed(body, isMine: false)
        #expect(String(drawn.characters) == body, "말풍선이 \"\(body)\" 를 \"\(String(drawn.characters))\" 로 그린다")
        #expect(drawn.runs.count == 1, "\"\(body)\" 의 말풍선 글자가 \(drawn.runs.count) 덩어리로 갈렸다 — 꾸밈이 붙었다")
        // 기준선: 기호 없는 평문 한 글자의 속성. 글 **전체**에 꾸밈(기울임 · 취소선 · 고정폭 · 바탕색)이 붙어도 덩어리는 하나라
        // 위 단언만으로는 못 본다 — 속성 묶음 자체가 평문과 같아야 한다.
        let plain = ChatMarkdownText.attributed("가", isMine: false)
        #expect(drawn.runs.first?.attributes == plain.runs.first?.attributes, "\"\(body)\" 의 말풍선 글자에 평문에 없는 꾸밈이 붙었다")
    }

    /// 받지 않는 기호 **옆과 안**에서도 받는 문법(굵게 · 링크)은 평소대로 켜진다. 백틱 · 울타리는 이제 안쪽을 지키지 않는다 —
    /// 글자일 뿐이다(첫 판은 `` `**x**` `` 를 코드로 지켰다).
    @Test func 받지_않는_기호_옆에서도_굵게와_링크는_켜진다() {
        #expect(cmSame(cmInline("- **자료** 정리"), [("- ", false, nil), ("자료", true, nil), (" 정리", false, nil)]))
        #expect(cmSame(cmInline("> [글](https://a.com) 봐"),
                       [("> ", false, nil), ("글", false, "https://a.com"), (" 봐", false, nil)]))
        #expect(cmSame(cmInline("1. https://a.com"), [("1. ", false, nil), ("https://a.com", false, "https://a.com")]))
        #expect(cmSame(cmInline("`**x**`"), [("`", false, nil), ("x", true, nil), ("`", false, nil)]))
        #expect(cmSame(cmInline("`https://a.com`"), [("`", false, nil), ("https://a.com", false, "https://a.com"), ("`", false, nil)]))
        #expect(cmSame(cmInline("*a **b** c*"), [("*a ", false, nil), ("b", true, nil), (" c*", false, nil)]))

        // 울타리는 닫혀도 글자이고, 그 사이 줄은 평소대로 해석된다(원문 한 줄 = 한 줄 — 울타리 줄도 빠지지 않는다).
        let fence = ChatMarkdown.parse("```swift\n**x** [글](https://a.com)\n\n_y_\n```")
        #expect(fence.map(\.kind) == [.paragraph, .paragraph, .blank, .paragraph, .paragraph])
        #expect(fence.map(\.text) == ["```swift", "x 글", "", "_y_", "```"])
        #expect(cmSame(cmRuns(fence[1]), [("x", true, nil), (" ", false, nil), ("글", false, "https://a.com")]))
        // 내용 없는 울타리 한 쌍도 빈 말풍선이 아니라 원문 그대로다.
        #expect(cmVisible("```\n```") == "```\n```")
    }

    /// 대조군: 기울임 · 취소선 자리의 기호는 **단어 경계에서도** 글자이고, 같은 자리의 `**` 는 켜진다
    /// (위 시험들이 "해석을 아예 안 해서 초록"이 아니다). 첫 판에서는 위 셋이 기울임 · 취소선으로 켜졌다.
    @Test func 기울임_취소선_자리는_글자이고_같은_자리의_굵게는_켜진다() {
        #expect(cmSame(cmInline("이건 _기울임_ 이다"), [("이건 _기울임_ 이다", false, nil)]))
        #expect(cmSame(cmInline("이건 ~~취소~~ 됐어"), [("이건 ~~취소~~ 됐어", false, nil)]))
        #expect(cmSame(cmInline("*진짜* 좋아 *진짜*"), [("*진짜* 좋아 *진짜*", false, nil)]))
        #expect(cmSame(cmInline("이건 **굵게** 이다"), [("이건 ", false, nil), ("굵게", true, nil), (" 이다", false, nil)]))
        #expect(cmSame(cmInline("**진짜** 좋아 **진짜**"), [("진짜", true, nil), (" 좋아 ", false, nil), ("진짜", true, nil)]))
    }

    /// 링크는 **http·https 만**이다. 그 밖 스킴은 링크가 아니고, `[글](주소)` 모양이면 **원문 글자 그대로**다.
    @Test(arguments: [
        "[글](javascript:alert(1))",
        "[글](file:///etc/passwd)",
        "[글](check://open/settings)",
        "[글](mailto:a@b.com)",
        "[글](ftp://a.com/x)",
        "[글](https://a.com/한글)",       // 비ASCII 주소 — 보이는 것과 여는 것이 달라지는 자동 인코딩을 거치지 않는다
        "[](https://a.com)",              // 빈 글 — 누를 자리가 없는 링크
        "[https://bank.com](https://evil.com)",   // 주소 흉내 글 — 보이는 주소와 여는 주소가 다르다
    ])
    func 열_수_없는_링크는_원문_글자_그대로다(body: String) {
        let lines = ChatMarkdown.parse(body)
        #expect(lines.count == 1)
        let spans = lines.first?.spans ?? []
        #expect(spans.allSatisfy { $0.link == nil }, "\"\(body)\" 가 링크가 됐다: \(spans.compactMap(\.link))")
        #expect(lines.first?.text == body, "\"\(body)\" 의 원문이 바뀌었다: \(lines.first?.text ?? "nil")")
    }

    @Test func 맨_주소는_http_https_만_링크다() {
        let table: [(String, [CMRun])] = [
            ("주소는 https://a.com/x.", [("주소는 ", false, nil), ("https://a.com/x", false, "https://a.com/x"), (".", false, nil)]),
            ("(https://a.com)", [("(", false, nil), ("https://a.com", false, "https://a.com"), (")", false, nil)]),
            ("https://ko.wikipedia.org/wiki/Foo_(bar)", [("https://ko.wikipedia.org/wiki/Foo_(bar)", false, "https://ko.wikipedia.org/wiki/Foo_(bar)")]),
            // 조사가 붙어도 주소는 ASCII 에서 멈춘다.
            ("https://a.com에서 봐요", [("https://a.com", false, "https://a.com"), ("에서 봐요", false, nil)]),
            ("여기https://a.com", [("여기", false, nil), ("https://a.com", false, "https://a.com")]),
            ("HTTPS://A.COM", [("HTTPS://A.COM", false, "HTTPS://A.COM")]),
            ("[https://a.com](https://a.com)", [("https://a.com", false, "https://a.com")]),
            ("http://b.io/x_y_z", [("http://b.io/x_y_z", false, "http://b.io/x_y_z")]),
            // 물결 손버릇은 주소가 아니다(취소선이 아니어도 꼬리 `~~` 는 주소 밖이다).
            ("https://a.com~~ 봐줘~~", [("https://a.com", false, "https://a.com"), ("~~ 봐줘~~", false, nil)]),
        ]
        for (body, expected) in table {
            let runs = cmInline(body)
            #expect(cmSame(runs, expected), "\"\(body)\" → \(cmDescribe(runs)) · 기대 \(cmDescribe(expected))")
        }
        // 대조군: 링크가 되면 안 되는 글자.
        for body in ["javascript:alert(1)", "file:///etc/passwd", "xhttps://a.com", "https://", "http:// a.com", "www.a.com", "check://open"] {
            let spans = ChatMarkdown.parse(body).flatMap(\.spans)
            #expect(spans.allSatisfy { $0.link == nil }, "\"\(body)\" 가 링크가 됐다")
            #expect(cmVisible(body) == body, "\"\(body)\" 의 글자가 바뀌었다")
        }
        // 여는 문의 두 번째 검사(말풍선이 누를 때 묻는 자리).
        #expect(ChatMarkdown.isOpenable(URL(string: "https://a.com")!))
        #expect(ChatMarkdown.isOpenable(URL(string: "HTTP://a.com/x")!))
        for raw in ["javascript:alert(1)", "file:///etc/passwd", "check://open", "mailto:a@b.com", "https://"] {
            if let url = URL(string: raw) { #expect(!ChatMarkdown.isOpenable(url), "\(raw) 를 열 수 있다고 한다") }
        }
    }

    /// 망가진 문법은 **원문 글자 그대로**다 — 닫히지 않은 `**`, 앞뒤에 공백이 붙은 `**`, 반쪽 링크.
    @Test(arguments: [
        "**열고 안 닫음",
        "안 열고 닫음**",
        "** 앞에 공백**",
        "**뒤에 공백 **",
        "`홀로 선 백틱",
        "a ` b",
        "~~열림",
        "x * 앞에 공백 *",
        "2 * 3 = 6",
        "[글](https://a.com",
        "[글] (https://a.com)",
        "**",
        "****",
        "``",
        "***",
        "_",
        "[",
        "](",
        "> ",
        "- ",
    ])
    func 망가진_문법은_원문_글자_그대로다(body: String) {
        #expect(cmVisible(body) == body, "\"\(body)\" → \"\(cmVisible(body))\"")
        let styled = ChatMarkdown.parse(body).flatMap(\.spans).filter(\.isBold)
        #expect(styled.isEmpty, "\"\(body)\" 에 굵게가 생겼다: \(styled)")
    }

    /// 채팅 손버릇은 글자 그대로다 — 이모티콘 · 곱셈 · 가림표 · snake_case · 물결.
    /// 이모티콘은 **한 메시지에 두 번** 넣는다 — 한 번만 넣으면 짝이 없어 결함이 있어도 초록이다(첫 판에서 `^_^ … ^_^` 가 기울임 짝이 됐다).
    @Test(arguments: [
        "snake_case_name",
        "foo_bar_",
        "a_b_c 그리고 x_y",
        "ㅎㅎ~~고마워~~",
        "안녕~~ 반가워~~",
        "-_-",
        ">_<",
        ">ㅅ<",
        "#해시태그",
        "+1 동의",
        "1.5배",
        "고마워요 *^^*",
        "*^^* 고마워요 *^^*",
        "^_^ 좋아 ^_^",
        "-_- 아 진짜 -_-",
        ">_< 헐 >_<",
        "^__^ 좋아 ^__^",
        "*_* 와 *_*",
        "*.* 와 *.*",
        "*^_^* 굿 *^_^*",
        "(*´▽`*)",
        "2*3*4",
        "x*2 와 y*3",
        "시*발 진짜 시*발",
        "_진짜_ 좋아 _진짜_",
        "~~진짜~~ 좋아 ~~진짜~~",
        "ㅋㅋ `진짜` ㅋㅋ `진짜`",
    ])
    func 채팅_손버릇은_글자_그대로다(body: String) {
        let lines = ChatMarkdown.parse(body)
        #expect(lines.map(\.kind) == [.paragraph], "\"\(body)\" 가 \(lines.map(\.kind)) 로 해석됐다")
        #expect(cmVisible(body) == body, "\"\(body)\" → \"\(cmVisible(body))\"")
        #expect(lines.flatMap(\.spans).allSatisfy { !$0.isBold }, "\"\(body)\" 에 굵게가 생겼다")
    }

    /// ★ **이모티콘 무작위 1천 개(시드 고정).** 채팅 이모티콘 · 곱셈 · 가림표를 띄어 섞은 본문은 **글자 하나 안 바뀐다**.
    /// 위 표는 사람이 고른 조합뿐이다 — 여기서는 서로 다른 이모티콘이 한 메시지에서 짝이 되는 조합(`^_^ … -_-`)까지 훑는다.
    @Test func 이모티콘을_섞은_무작위_본문은_글자_그대로다() {
        let tokens = [
            "^_^", "^^", "-_-", "-_-;;", ">_<", "*^^*", "*^_^*", "*.*", "*_*", "^__^", "ㅠ_ㅠ", "T_T",
            "2*3", "3*4=12", "시*발", "좋아", "고마워", "ㅋㅋ", "진짜", "ㅎㅎ~~", "snake_case", "!", "?",
        ]
        var random = CMRandom(state: 0x5EED_0F_E3)
        var paired = 0
        for _ in 0..<1_000 {
            let count = Int.random(in: 1...10, using: &random)
            let body = (0..<count).map { _ in tokens.randomElement(using: &random)! }.joined(separator: " ")
            if body.filter({ $0 == "*" || $0 == "_" }).count >= 4 { paired += 1 }
            let lines = ChatMarkdown.parse(body)
            #expect(cmVisible(body) == body, "\(body.debugDescription) → \(cmVisible(body).debugDescription)")
            #expect(lines.flatMap(\.spans).allSatisfy { !$0.isBold }, "\(body.debugDescription) 에 굵게가 생겼다")
        }
        // 짝이 될 만한 기호가 넷 이상인 본문을 실제로 많이 지났다(공허한 초록이 아니다).
        #expect(paired > 300, "기호 넷 이상인 본문이 \(paired)개뿐이다")
    }

    /// 한 번의 줄바꿈은 줄바꿈이다(⇧↩) · 빈 줄은 빈 줄이다. 그린 글자에도 줄바꿈이 그대로 있다.
    @Test func 줄바꿈은_그대로_줄바꿈이다() {
        let lines = ChatMarkdown.parse("첫 줄\n둘째 줄\n\n넷째 줄")
        #expect(lines.map(\.kind) == [.paragraph, .paragraph, .blank, .paragraph])
        #expect(lines.map(\.text) == ["첫 줄", "둘째 줄", "", "넷째 줄"])
        #expect(ChatMarkdown.parse("가\r\n나").map(\.text) == ["가", "나"], "\\r\\n 이 줄을 안 나눴다")

        let drawn = ChatMarkdownText.attributed("첫 줄\n**둘째** 줄\n\n넷째 줄", isMine: false)
        #expect(String(drawn.characters) == "첫 줄\n둘째 줄\n\n넷째 줄")
        let mine = ChatMarkdownText.attributed("안녕\n반가워", isMine: true)
        #expect(String(mine.characters) == "안녕\n반가워", "내 말풍선의 줄바꿈이 사라졌다")
    }

    /// 글머리 · 번호 · 인용 · 울타리 줄은 **말풍선에도 친 그대로** 그려진다 — 글머리 •·인용 막대를 덧붙이지 않고, 기호도 안 뺀다.
    /// 줄마다 원문 한 줄이고(⇧↩ 그대로), 그 안의 `**굵게**` 만 기호가 빠진다.
    @Test func 목록_번호_인용_울타리는_말풍선에도_친_그대로다() {
        let body = "- 사과\n* 배\n+ 감\n  - 안쪽\n1. 하나\n12) 열둘\n> 인용 **굵게**\n```\n코드\n```"
        #expect(ChatMarkdown.parse(body).map(\.kind) == Array(repeating: ChatMarkdownLineKind.paragraph, count: 10))
        let drawn = String(ChatMarkdownText.attributed(body, isMine: false).characters)
        #expect(drawn == "- 사과\n* 배\n+ 감\n  - 안쪽\n1. 하나\n12) 열둘\n> 인용 굵게\n```\n코드\n```", "그린 글자: \(drawn)")
    }

    /// **200자 경계**(서버 상한 · `MessageBody.maxLength`). 상한 길이 본문도 해석되고, 기호뿐인 상한 본문도 글자를 잃지 않는다.
    @Test func 상한_200자_본문도_해석되고_글자를_잃지_않는다() {
        let heading = "## " + String(repeating: "가", count: MessageBody.maxLength - 3)
        #expect(heading.unicodeScalars.count == MessageBody.maxLength)
        let line = ChatMarkdown.parse(heading).first
        #expect(line?.kind == .heading(level: 2))
        #expect(line?.text.count == MessageBody.maxLength - 3)

        for unit in ["*", "`", "_", "~", "[", "**a", "*a ", "[a](", "`a", "~~a", "https://a.co/", "- ", "> ", "1. ", "```\n"] {
            let body = String(String(repeating: unit, count: MessageBody.maxLength).prefix(MessageBody.maxLength))
            let visible = cmVisible(body)
            #expect(cmIsSubsequence(visible, of: body), "\"\(unit)\" × 200 이 글자를 지어냈다")
            #expect(cmContent(visible) == cmContent(body), "\"\(unit)\" × 200 에서 내용 글자가 빠졌다")
            // `**` 도 제목도 링크 모양도 없는 단위는 한 글자도 안 바뀐다.
            if !body.contains("**"), !body.contains("]("), !body.hasPrefix("#") {
                #expect(visible == body, "\"\(unit)\" × 200 의 글자가 바뀌었다")
            }
        }

        // 꾸밈 없는 한 줄 본문의 틀 높이 추정은 **예전 산식과 같다**(⌈글자 수/15⌉ × 15 + 10).
        for count in [1, 14, 15, 16, 100, MessageBody.maxLength] {
            let body = String(repeating: "가", count: count)
            let old = CGFloat(max(1, Int((Double(count) / 15).rounded(.up)))) * 15 + 10
            #expect(MessagePanelLayout.textBubbleHeight(body) == old, "\(count)자 본문의 추정이 바뀌었다")
        }
        // 제목·줄바꿈은 더 높게 센다(잘림 없는 틀을 위해).
        #expect(MessagePanelLayout.textBubbleHeight("## 제목") > MessagePanelLayout.textBubbleHeight("제목"))
        #expect(MessagePanelLayout.textBubbleHeight("가\n나\n다") >= MessagePanelLayout.textBubbleHeight("가") + 30)
    }

    /// ★ **틀 높이 추정은 말풍선이 그리는 글자를 그대로 센다.** 그린 글자(`ChatMarkdownText.attributed` — 호스트 꼬리표 포함)를
    /// 줄마다 그 줄의 글자 크기로 세어 쌓은 값이 `textBubbleHeight` 와 **같아야** 한다. 그리는 쪽이 글자를 덧붙이거나(글머리 •)
    /// 추정이 없는 글자를 세면(옛 글머리 두 칸) 여기서 갈린다. 손으로 고른 본문 + 시드 고정 무작위 500 개.
    @Test func 틀_높이_추정은_그리는_글자를_그대로_센다() {
        let bodies = [
            "- 하나\n- 둘", "> 인용 한 줄", "## 제목\n본문 **굵게**", "`코드` 와 ~~취소~~ 와 _기울임_",
            "[여기](https://a-very-long-host-name.example) 봐요", "# 공지\n[가](https://a.example) 와 [나](https://b.example)",
        ] + cmFuzzBodies(seed: 0x4E16_47E5, count: 500)
        var withDisclosure = 0
        for body in bodies {
            let lines = ChatMarkdown.parse(body)
            let drawn = String(ChatMarkdownText.attributed(body, isMine: false).characters)
                .split(separator: "\n", omittingEmptySubsequences: false)
            #expect(drawn.count == lines.count, "\(body.debugDescription) 의 그린 줄 수가 해석 줄 수와 다르다")
            var expected: CGFloat = 10
            for (line, row) in zip(lines, drawn) {
                if row.count != line.text.count { withDisclosure += 1 }
                let scale = Double(ChatMarkdownText.fontSize(for: line.kind) / ChatMarkdownText.baseSize)
                let perRow = max(1, Int((Double(MessagePanelLayout.charactersPerBubbleLine) / scale).rounded(.down)))
                expected += CGFloat(Double(max(1, Int((Double(row.count) / Double(perRow)).rounded(.up)))) * 15 * scale)
            }
            #expect(MessagePanelLayout.textBubbleHeight(body) == expected,
                    "\(body.debugDescription): 추정 \(MessagePanelLayout.textBubbleHeight(body)) · 그린 글자로 센 값 \(expected)")
        }
        // 그린 글자가 해석 글자보다 긴 줄(호스트 꼬리표)을 실제로 지났다 — 덧붙인 글자 갈래가 공허하지 않다.
        #expect(withDisclosure >= 2, "호스트 꼬리표가 붙은 줄이 \(withDisclosure)개뿐이다")
    }

    /// ★ **글자 보존 — 무작위 3천 개(시드 고정).** 어떤 입력에서도:
    ///   ⓐ 그린 글자는 원문의 **부분 수열**이다(새 글자를 지어내거나 순서를 바꾸지 않는다).
    ///   ⓑ `](` 가 없는 입력(= 링크 주소가 숨을 수 없는 입력)에서는 **내용 글자의 개수가 정확히 같다**(받는 기호와 공백만 빠진다 —
    ///      `_` · `~` · `` ` `` · `>` · `-` · `+` 는 내용으로 센다).
    ///   ⓒ 나온 링크는 전부 http·https 다.
    ///   ⓓ `**` · `](` · 줄 머리 `#` 이 없는 입력은 **글자 하나 안 바뀐다**(공백뿐인 줄이 빈 줄이 되는 것 말고).
    ///      홑 `*` · 울타리 · 글머리 · 번호 · 인용이 섞여 있어도다 — 대표 결정 "나머지 문법은 기호 그대로".
    ///   ⓔ 공백 아닌 글자가 있는 줄은 해석 글자도 비지 않는다(빈 말풍선 금지).
    @Test func 무작위_입력에서도_받는_기호만_빠지고_나머지는_그대로다() {
        var checkedContent = 0, checkedExact = 0, linked = 0
        for body in cmFuzzBodies(seed: 0x0C4E_C4ED, count: 3_000) {
            let lines = ChatMarkdown.parse(body)
            let rows = cmRows(body)
            let visible = lines.map(\.text).joined(separator: "\n")
            #expect(cmIsSubsequence(visible, of: body), "글자를 지어냈다: \(body.debugDescription) → \(visible.debugDescription)")
            #expect(visible.count <= body.count)
            if !body.contains("](") {
                checkedContent += 1
                #expect(cmContent(visible) == cmContent(body), "내용 글자가 빠졌다: \(body.debugDescription) → \(visible.debugDescription)")
            }
            if !body.contains("**"), !body.contains("]("), !rows.contains(where: { $0.hasPrefix("#") }) {
                checkedExact += 1
                let expected = rows.map { $0.allSatisfy(\.isWhitespace) ? "" : $0 }.joined(separator: "\n")
                #expect(visible == expected, "받지 않는 기호가 바뀌었다: \(body.debugDescription) → \(visible.debugDescription)")
            }
            #expect(lines.count == rows.count, "원문 \(rows.count)줄이 \(lines.count)줄이 됐다: \(body.debugDescription)")
            for (row, line) in zip(rows, lines) where row.contains(where: { !$0.isWhitespace }) {
                #expect(!line.text.isEmpty && line.kind != .blank, "글자 있는 줄이 비었다: \(row.debugDescription)")
            }
            for link in lines.flatMap(\.spans).compactMap(\.link) {
                linked += 1
                #expect(ChatMarkdown.isOpenable(link), "열 수 없는 링크가 생겼다: \(link) ← \(body.debugDescription)")
            }
        }
        // 무작위가 실제로 갈래를 지났다(공허한 초록이 아니다).
        #expect(checkedContent > 1_000, "내용 비교를 한 입력이 \(checkedContent)개뿐이다")
        #expect(checkedExact > 500, "글자 그대로 비교를 한 입력이 \(checkedExact)개뿐이다")
        #expect(linked > 100, "링크가 \(linked)개뿐이다 — 링크 갈래를 안 지났다")
    }
}

// MARK: - ② 한 줄 미리보기

@Suite("ChatMarkdownPreview")
struct ChatMarkdownPreviewTests {
    /// 미리보기는 받는 세 문법(제목 · 굵게 · 링크)의 기호만 벗기고 줄바꿈을 공백으로 접는다. 나머지 문법은 말풍선처럼 그대로다.
    @Test func 미리보기는_세_문법의_기호만_벗기고_줄바꿈을_공백으로_접는다() {
        #expect(ChatMarkdown.plainPreview("## 제목\n**굵게** 와 [글](https://a.com) 그리고 `코드`")
                == "제목 굵게 와 글 그리고 `코드`")
        #expect(ChatMarkdown.plainPreview("- 사과\n- 배\n\n> 인용") == "- 사과 - 배 > 인용")
        #expect(ChatMarkdown.plainPreview("```swift\nlet a = 1\n```") == "```swift let a = 1 ```")
        #expect(ChatMarkdown.plainPreview("1. 하나\n2. 둘") == "1. 하나 2. 둘")
        #expect(ChatMarkdown.plainPreview("*기울임* _밑줄_ ~~취소~~") == "*기울임* _밑줄_ ~~취소~~")
        // 열 수 없는 링크는 원문 그대로다(말풍선과 같은 판정).
        #expect(ChatMarkdown.plainPreview("[글](javascript:alert(1))") == "[글](javascript:alert(1))")
    }

    /// 평범한 한 줄 본문은 **글자 하나도** 안 바뀐다 — 바뀌면 그게 "내 말이 화면에서 달라지는" 버그다.
    @Test(arguments: [
        "화이팅", "오늘 고생했어요", "점심 드셨어요?", "고마워요 :)", "👍🏻🎉🇰🇷", "snake_case", "-_-", "2 * 3 = 6", "https://a.com",
        "*기울임*", "`코드`", "- 항목", "> 인용", "~~취소~~",
    ])
    func 평범한_본문은_그대로다(body: String) {
        #expect(ChatMarkdown.plainPreview(body) == body)
    }

    /// 이모티콘 규칙이 **먼저**다 — 토큰 본문은 "아잉이 기쁨"으로 읽힌다(마크다운 링크 모양 검사보다 앞).
    @Test func 이모티콘_토큰은_이름으로_읽힌다() {
        for sticker in AingSticker.allCases {
            #expect(ChatMarkdown.plainPreview(sticker.token) == "아잉이 \(sticker.label)")
        }
        #expect(ChatMarkdown.plainPreview("  [아잉:놀람]\n") == "아잉이 놀람")
        #expect(ChatMarkdown.plainPreview("") == "")
    }

    /// 네 자리(팝오버 수신 줄 · 캐릭터 도착 말풍선 · 신고 인용 · 확성기 배너)가 **같은 한 함수**를 부른다.
    @Test func 한_줄_자리는_전부_plainPreview_를_지난다() throws {
        #expect(CheckOverlayController.messageBubbleText(name: "민수", body: "**화이팅**") == "민수님: 화이팅")
        #expect(CheckOverlayController.messageBubbleText(name: "민수", body: "## 공지\n[링크](https://a.com) 봐요")
                == "민수님: 공지 링크 봐요")

        let menu = try cmSource("CheckMenuView.swift")
        let strip = try #require(cmRegion(menu, from: "struct PokeMessageReceiptStrip: View {", to: "\n}\n"))
        #expect(strip.contains("Text(ChatMarkdown.plainPreview(message.body))"), "수신 한 줄이 기호를 안 벗긴다")

        let report = try cmSource("CheckBlockReportViews.swift")
        #expect(report.contains("Text(ChatMarkdown.plainPreview(quoted))"), "신고 인용 상자가 기호를 안 벗긴다")
        #expect(!report.contains("Text(quoted)"))

        let banner = try cmSource("CheckMegaphoneBannerWindow.swift")
        #expect(banner.contains("Text(ChatMarkdown.plainPreview(banner.body))"), "확성기 배너가 기호를 안 벗긴다")
        #expect(!banner.contains("Text(banner.body)"))

        // 쪼갠 파일(맥 화면 + 코어 CheckPanelVisibility)이라 두 조각을 이어 읽는다 — CheckCoreSourceLayoutTests 의 반쪽 읽기 금지.
        let overlay = cmStripComments(try CheckCoreSourceLayout.joinedSplitSource("CheckOverlayWindow.swift"))
        let spoken = try #require(cmRegion(overlay, from: "static func messageBubbleText(", to: "\n    }"))
        #expect(spoken.contains("ChatMarkdown.plainPreview(body)"), "캐릭터 말풍선이 기호를 안 벗긴다(변환은 이 함수 안이어야 한다)")
    }
}

// MARK: - ③ 말풍선 — 그린 결과로 잰다

@MainActor
@Suite("ChatMarkdownBubble")
struct ChatMarkdownBubbleTests {

    /// 링크 글자는 **링크 속성을 값으로** 갖는다. 열 수 없는 스킴은 링크가 없고 원문이 그대로 보인다.
    @Test func 링크_글자는_링크_속성을_갖고_나쁜_스킴은_글자다() {
        let body = "[글](https://a.com) 와 [나쁜](javascript:alert(1)) 그리고 https://b.com/x"
        let drawn = ChatMarkdownText.attributed(body, isMine: false)
        let links: [(String, String)] = drawn.runs.compactMap { run in
            run.link.map { (String(drawn[run.range].characters), $0.absoluteString) }
        }
        #expect(links.map(\.0) == ["글", "https://b.com/x"], "링크 글자: \(links)")
        #expect(links.map(\.1) == ["https://a.com", "https://b.com/x"])
        #expect(String(drawn.characters).contains("[나쁜](javascript:alert(1))"), "열 수 없는 링크의 원문이 사라졌다")

        // 링크는 밑줄과 바탕에 맞는 색을 갖는다 — 내 말풍선(강조색 바탕)에서는 흰색이다.
        func linkColor(_ isMine: Bool) -> Color? {
            let text = ChatMarkdownText.attributed("[글](https://a.com)", isMine: isMine)
            let run = text.runs.first { $0.link != nil }
            #expect(run?[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] != nil, "링크에 밑줄이 없다")
            return run?[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self]
        }
        #expect(linkColor(true) == Color.white, "내 말풍선 링크가 바탕(강조색)에 묻힌다")
        #expect(linkColor(false) == CheckTheme.accent)
        #expect(ChatMarkdownText.linkColor(isMine: true) != CheckTheme.accent)
    }

    /// ★ **`##` 가 실제로 더 크게 그려진다**(픽셀 높이). 진짜 대화 뷰를 그려 말풍선 행이 해석을 지나는지까지 잰다.
    /// 대조군은 같은 글자의 평문이다 — 해석을 안 지나면 `## ` 는 본문 크기 글자로 그려져 높이가 같다. 두 갈래(스냅샷 · 앱) 모두.
    @Test(arguments: CMPath.allCases)
    func 제목은_말풍선에서_실제로_더_높게_그려진다(path: CMPath) throws {
        func inkHeight(_ body: String) throws -> Int {
            let bitmap = try cmConversation(body: body, path: path)
            let ink = try #require(cmInk(bitmap, against: try cmBlank(matching: bitmap, path: path)), "\"\(body)\" 가 아무것도 안 그렸다")
            return ink.maxY - ink.minY
        }
        let plain = try inkHeight("큰 제목")
        let h3 = try inkHeight("### 큰 제목")
        let h2 = try inkHeight("## 큰 제목")
        let h1 = try inkHeight("# 큰 제목")
        #expect(h2 - plain >= 6, "## 가 본문보다 높지 않다(## \(h2)px · 본문 \(plain)px)")
        #expect(h1 > h2 && h2 > h3 && h3 > plain, "제목 높이가 단계적이지 않다: # \(h1) · ## \(h2) · ### \(h3) · 본문 \(plain)")
    }

    /// 기호는 말풍선에서 **사라진다**: `**굵게**` 와 `굵게` 의 말풍선 폭은 굵기 차이만큼만 다르다.
    /// 해석을 안 지나면 별표 넷(≈ 20pt)만큼 넓어진다.
    ///
    /// 재는 자리는 그림 **아래 30pt**(말풍선 한 줄 행)뿐이다 — 그 위 날짜 구분선은 폭 전체를 긋는 선이라 오른쪽 끝을 가린다.
    @Test(arguments: CMPath.allCases)
    func 굵게_기호는_말풍선에서_사라진다(path: CMPath) throws {
        func inkRight(_ body: String) throws -> Int {
            let bitmap = try cmConversation(body: body, path: path)
            return try #require(cmInk(bitmap, against: try cmBlank(matching: bitmap, path: path), bottomRows: 60)).maxX
        }
        let plain = try inkRight("굵게 보기")
        let bold = try inkRight("**굵게** 보기")
        // 대조군: 별표가 **글자로** 남는 망가진 본문은 확실히 넓다(이 차이를 못 재면 위 단언은 공허하다).
        let literal = try inkRight("** 굵게** 보기")
        #expect(abs(bold - plain) < 12, "**굵게** 가 기호째 그려졌다(\(bold)px · 평문 \(plain)px)")
        #expect(literal - plain > 20, "기호가 글자로 남는 대조군이 평문과 같은 폭이다(\(literal)px · \(plain)px)")
    }

    /// ★ **잘림 없는 틀**: 틀 높이 추정(`conversationContentHeight`)이 실제로 그려진 말풍선보다 작지 않다.
    /// 작으면 스냅샷(클립 갈래)에서 위가 잘리고, 앱에서는 짧은 대화인데도 스크롤이 붙는다.
    /// 예전 산식(전체 글자 수 / 15)은 줄바꿈·제목을 몰라서 아래 본문들을 한두 줄로 셌다. 두 갈래(스냅샷 · 앱) 모두.
    @Test(arguments: CMPath.allCases)
    func 틀_높이_추정은_그려진_말풍선보다_작지_않다(path: CMPath) throws {
        let bodies = [
            "# 큰 제목\n## 중간 제목\n### 작은 제목\n- 하나\n- 둘",
            "## 회의 안건이 길어서 두 줄로 넘어가는 제목입니다",
            "```\nlet a = 1\nlet b = 2\nlet c = 3\n```",
            "> 인용 한 줄\n> 인용 두 줄\n\n본문",
            "가\n나\n다\n라\n마",
        ]
        for body in bodies {
            let entry = MessageHistoryEntry(
                id: "md1", peerUserID: cmPeer, peerName: "민수", peerAvatarURL: nil, body: body,
                createdAt: cmNow.addingTimeInterval(-60), isMine: false, readByPeer: nil, isUnread: nil
            )
            let estimate = MessagePanelLayout.conversationContentHeight(MessageThreadBuilder.timeline([entry], now: cmNow))
            let bitmap = try cmConversation(body: body, height: 420, path: path)
            let ink = try #require(cmInk(bitmap, against: try cmBlank(matching: bitmap, path: path)), "\(body.debugDescription) 가 안 그려졌다")
            let drawn = CGFloat(ink.maxY - ink.minY) / 2
            #expect(estimate >= drawn, "추정 \(estimate)pt < 그려진 \(drawn)pt — \(body.debugDescription) (\(path))")
        }
    }

    /// 소스 계약 — 말풍선이 **이모티콘 폴백을 먼저** 거친 뒤 마크다운을 그리고(두 갈래 모두), 링크 문에 스킴 검사를 세운다.
    /// 우클릭 [복사]·[신고]와 끌어 고르기는 앱 갈래 글자 뷰가 맡는다 — 그 동작은 ChatBubbleSelectionTests 가 진짜 이벤트로 잰다.
    /// 여기서는 **배선**만 본다: 앱 갈래는 원문(`raw: entry.body`)과 신고 문을 글자 뷰에 넘기고, SwiftUI 선택(`textSelection`)은 어디에도 없다
    /// (그것이 우클릭을 시스템 메뉴로 가져가 신고를 지운 v0.3.34 의 원인이다).
    @Test func 말풍선은_이모티콘_폴백_뒤에_마크다운을_그린다() throws {
        let view = try cmSource("CheckMessageView.swift")
        let bubble = try #require(cmRegion(view, from: "private var textBubble: some View {", to: "\n    }"))
        // 스냅샷 갈래.
        #expect(bubble.contains("Text(ChatMarkdownText.attributed(AingStickerText.preview(for: entry.body), isMine: entry.isMine))"))
        #expect(bubble.contains(".environment(\\.openURL, OpenURLAction(handler: ChatMarkdownText.openAction))"),
                "스냅샷 갈래 링크 문 앞의 스킴 검사가 없다")
        #expect(bubble.contains(".tint(ChatMarkdownText.linkColor(isMine: entry.isMine))"))
        // 앱 갈래 — 보이는 글자는 폴백을 지난 본문, 고른 것 없는 [복사]는 원문, 신고 문은 행이 받은 그대로.
        let app = try #require(cmRegion(bubble, from: "ChatBubbleText(", to: ".fixedSize"), "앱 갈래가 글자 뷰를 안 세운다")
        #expect(app.contains("shown: AingStickerText.preview(for: entry.body)"), "앱 갈래가 폴백을 안 지난다")
        #expect(app.contains("raw: entry.body"), "앱 갈래 [복사]가 원문이 아니다")
        #expect(app.contains("onReport: onReport"), "앱 갈래가 신고 문을 안 넘긴다")
        // 두 갈래를 가르는 스위치는 스냅샷 전용이고, 패널은 입력칸과 같은 스위치를 넘긴다.
        #expect(bubble.contains("if rendersPlainText {"))
        #expect(view.contains("rendersPlainText: rendersPlainTextEditor"), "패널이 스냅샷 스위치를 대화에 안 넘긴다")

        let row = try #require(cmRegion(view, from: "private struct MessageBubbleRow: View {", to: "// MARK: - 입력줄"))
        // 그림 말풍선의 SwiftUI 메뉴 하나만 남는다(글자 말풍선 메뉴는 글자 뷰가 짓는다).
        #expect(row.components(separatedBy: ".contextMenu {").count - 1 == 1)
        #expect(!row.contains(".textSelection("), "SwiftUI 글자 선택이 돌아왔다 — 우클릭이 시스템 메뉴로 가서 [신고]가 사라진다")
        #expect(view.contains("CheckPasteboard.copy(entry.body)"), "그림 말풍선 우클릭 복사가 원문이 아니다")

        // 앱 갈래 링크 문의 스킴 검사.
        let textView = try cmSource("ChatBubbleTextView.swift")
        let follow = try #require(cmRegion(textView, from: "func followLink(_ link: Any) -> Bool {", to: "\n    }"))
        #expect(follow.contains("ChatMarkdown.isOpenable(url)"), "앱 갈래 링크 문 앞의 스킴 검사가 없다")

        // 틀 높이 추정도 말풍선과 같은 글자(이모티콘 폴백 → 마크다운)로 센다.
        let estimate = try #require(cmRegion(view, from: "static func conversationContentHeight(", to: "\n    }"))
        #expect(estimate.contains("textBubbleHeight(AingStickerText.preview(for: entry.body))"))
    }
}

/// `[글](주소)` 의 **실제 호스트를 글 뒤에 보인다**(2026-11-03 검토 P2). 말풍선엔 주소를 볼 길(호버)이 없어서, 보이는 글과 여는 곳이
/// 다른 링크를 알아챌 수 없었다. 글자 흉내 검사(`isDisguisedAddress`)는 폭 없는 공백 · 전각 쌍점 · 방향 문자로 비켜 간다 — 그래서 막는 대신 보인다.
@MainActor
@Suite("ChatMarkdownLinkDisclosure")
struct ChatMarkdownLinkDisclosureTests {
    private func drawn(_ body: String) -> String {
        String(ChatMarkdownText.attributed(body, isMine: false).characters)
    }

    @Test func 글과_여는_곳이_다른_링크는_실제_호스트를_붙여_보인다() {
        #expect(drawn("[naver.com](https://evil.example)") == "naver.com (evil.example)")
        #expect(drawn("[여기](https://evil.example/login)") == "여기 (evil.example)")
        // 검토가 찾은 우회 셋 — 글자 흉내 검사는 비켜 가도 호스트는 그대로 보인다.
        #expect(drawn("[https:/\u{200B}/good.com](https://evil.com)").hasSuffix(" (evil.com)"))
        #expect(drawn("[https\u{FF1A}//good.com](https://evil.com)").hasSuffix(" (evil.com)"))
        #expect(drawn("[\u{202E}moc.doog//:sptth](https://evil.com)").hasSuffix(" (evil.com)"))
        // 붙인 호스트는 링크가 아니다 — 누르는 자리는 글 그대로다.
        let text = ChatMarkdownText.attributed("[여기](https://evil.example)", isMine: false)
        let linked = text.runs.filter { $0.link != nil }.map { String(text[$0.range].characters) }
        #expect(linked == ["여기"])
    }

    @Test func 글이_이미_주소를_말하면_붙이지_않는다() {
        // 기준선: 같은 링크 모양 · 글이 주소나 호스트와 같다.
        #expect(drawn("https://a.com/x 보세요") == "https://a.com/x 보세요")
        #expect(drawn("[naver.com](https://naver.com)") == "naver.com")
        #expect(drawn("[https://a.com/](https://a.com)") == "https://a.com/")
        #expect(drawn("[www.naver.com](https://www.naver.com)") == "www.naver.com")
    }

    @Test func www_글의_같은_주소는_링크가_된다() {
        // 예전엔 스킴 차이만으로 '주소 흉내'로 보고 원문 기호째 남겼다(오탐).
        let spans = ChatMarkdown.parse("[www.naver.com](https://www.naver.com)").first?.spans ?? []
        #expect(spans.compactMap(\.link).map(\.absoluteString) == ["https://www.naver.com"])
        #expect(ChatMarkdown.parse("[https://bank.com](https://evil.com)").first?.spans.allSatisfy { $0.link == nil } == true,
                "글이 다른 주소를 말하는 링크는 여전히 원문 그대로다")
    }

    @Test func 한_줄에_링크가_둘이면_각자_뒤에_붙는다() {
        let shown = drawn("[가](https://a.example) 와 [나](https://b.example)")
        #expect(shown == "가 (a.example) 와 나 (b.example)")
        #expect(shown.components(separatedBy: "(a.example)").count == 2)
    }

    @Test func 높이_추정이_꼬리표까지_센다() throws {
        let line = try #require(ChatMarkdown.parse("[여기](https://a-very-long-host-name.example)").first)
        #expect(ChatMarkdownText.addedCharacters(line) == " (a-very-long-host-name.example)".count)
        let bare = try #require(ChatMarkdown.parse("https://a.com").first)
        #expect(ChatMarkdownText.addedCharacters(bare) == 0)
        #expect(MessagePanelLayout.textBubbleHeight("[여기](https://a-very-long-host-name.example)") > MessagePanelLayout.textBubbleHeight("여기"))
    }
}
