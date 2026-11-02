import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 채팅 마크다운(대표 요청 2026-11-03 ③④ — "## 글자 로 글자 크기 키우거나" · "링크는 클릭해서 브라우저 열리게").
//
// 이 스위트가 지키는 것:
//  ① **해석 결과를 값으로 잰다** — 줄 종류 · 조각의 글자 · 꾸밈 · 링크. 표 하나에 입력과 기대를 나란히 둔다.
//  ② **링크는 http·https 만**이다. `javascript:` · `file:` · 사용자 정의 스킴은 원문 글자 그대로다.
//  ③ **글자 보존**: 해석이 어떤 입력에서도 내용 글자를 버리거나 지어내지 않는다 — 손으로 고른 표 + 시드 고정 무작위 3천 개.
//  ④ **화면이 해석을 지난다**: 말풍선을 실제로 그려 `##` 가 더 높게 그려지는지(픽셀) · 기호가 사라졌는지(폭)를 본다.
//     규칙만 재면 뷰가 그 규칙을 안 부르는 결함이 초록으로 지나간다(이 저장소의 "두 겹 게이트" 함정).
//
// 소스 계약은 주석을 걷어낸 뒤 잰다.

// MARK: - 길잡이

private let cmNow = Date(timeIntervalSince1970: 1_790_000_000)
private let cmPeer = MessageReadFixture.peerA

/// 줄 하나의 (글자, 꾸밈, 링크) 목록 — 표의 기대값 모양.
private typealias CMRun = (text: String, style: ChatMarkdownStyle, link: String?)

private func cmRuns(_ line: ChatMarkdownLine) -> [CMRun] {
    line.spans.map { ($0.text, $0.style, $0.link?.absoluteString) }
}

private func cmSame(_ lhs: [CMRun], _ rhs: [CMRun]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.text == $1.text && $0.style == $1.style && $0.link == $1.link }
}

private func cmDescribe(_ runs: [CMRun]) -> String {
    runs.map { "(\"\($0.text)\", \($0.style.rawValue), \($0.link ?? "-"))" }.joined(separator: " ")
}

/// 한 줄짜리 본문을 해석한 조각들.
private func cmInline(_ body: String) -> [CMRun] {
    let lines = ChatMarkdown.parse(body)
    #expect(lines.count == 1, "\"\(body)\" 가 한 줄로 해석되지 않았다(\(lines.count)줄)")
    return lines.first.map(cmRuns) ?? []
}

/// 해석이 그리는 글자 전부(줄 사이는 "\n"). 글머리 • · 인용 막대는 그리는 쪽이 붙이므로 여기 없다.
private func cmVisible(_ body: String) -> String {
    ChatMarkdown.parse(body).map(\.text).joined(separator: "\n")
}

/// 기호(빠져도 되는 글자). 이것과 공백을 뺀 나머지가 **내용 글자**다.
private let cmSyntax: Set<Character> = ["#", "*", "_", "~", "`", "[", "]", "(", ")", ">", "-", "+"]

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

/// 말풍선 하나짜리 대화 한 판(진짜 `MessageConversationView` — 말풍선 행이 해석을 지나는지까지 함께 잰다).
@MainActor
private func cmConversation(body: String, isMine: Bool = false, height: CGFloat = 160) throws -> NSBitmapImageRep {
    let entries = [MessageHistoryEntry(
        id: "md1", peerUserID: cmPeer, peerName: "민수", peerAvatarURL: nil, body: body,
        createdAt: cmNow.addingTimeInterval(-60), isMine: isMine, readByPeer: nil, isUnread: nil
    )]
    let view = MessageConversationView(
        items: MessageThreadBuilder.timeline(entries, now: cmNow),
        peerUserID: cmPeer,
        lastMessageID: entries.last?.id,
        clipsInsteadOfScrolling: true
    )
    .frame(width: MessagePanelLayout.contentWidth, height: height)
    .background(CheckTheme.background)
    return try cmBitmap(view)
}

@MainActor
private func cmBlank(matching bitmap: NSBitmapImageRep) throws -> NSBitmapImageRep {
    try cmBitmap(
        Color.clear
            .frame(width: CGFloat(bitmap.pixelsWide) / 2, height: CGFloat(bitmap.pixelsHigh) / 2)
            .background(CheckTheme.background)
    )
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

    /// 줄 안 문법 표 — 입력 하나하나에 대해 나온 조각(글자 · 꾸밈 · 링크)이 무엇인가.
    @Test func 줄_안_문법은_조각과_꾸밈으로_나온다() {
        let table: [(String, [CMRun])] = [
            ("**굵게**", [("굵게", .bold, nil)]),
            ("__굵게__", [("굵게", .bold, nil)]),
            ("*기울임*", [("기울임", .italic, nil)]),
            ("_기울임_", [("기울임", .italic, nil)]),
            ("~~취소~~", [("취소", .strikethrough, nil)]),
            ("`코드`", [("코드", .code, nil)]),
            ("앞 **굵게** 뒤", [("앞 ", [], nil), ("굵게", .bold, nil), (" 뒤", [], nil)]),
            ("***둘 다***", [("둘 다", [.bold, .italic], nil)]),
            ("*a **b** c*", [("a ", .italic, nil), ("b", [.italic, .bold], nil), (" c", .italic, nil)]),
            // 조사가 붙는 한국어 — `**` 는 단어 안에서도 켜진다(홑 `*` 는 안 켜진다 — 아래 `2*3*4` · 가림표).
            ("이건**중요**해", [("이건", [], nil), ("중요", .bold, nil), ("해", [], nil)]),
            ("``a`b``", [("a`b", .code, nil)]),
            ("```let x```", [("let x", .code, nil)]),
            ("[글](https://a.com)", [("글", [], "https://a.com")]),
            ("[**굵은 글**](https://a.com/x?y=1)", [("굵은 글", .bold, "https://a.com/x?y=1")]),
            ("https://a.com 보세요", [("https://a.com", [], "https://a.com"), (" 보세요", [], nil)]),
            ("**https://a.com**", [("https://a.com", .bold, "https://a.com")]),
        ]
        for (body, expected) in table {
            let runs = cmInline(body)
            #expect(cmSame(runs, expected), "\"\(body)\" → \(cmDescribe(runs)) · 기대 \(cmDescribe(expected))")
        }
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
            ("주소는 https://a.com/x.", [("주소는 ", [], nil), ("https://a.com/x", [], "https://a.com/x"), (".", [], nil)]),
            ("(https://a.com)", [("(", [], nil), ("https://a.com", [], "https://a.com"), (")", [], nil)]),
            ("https://ko.wikipedia.org/wiki/Foo_(bar)", [("https://ko.wikipedia.org/wiki/Foo_(bar)", [], "https://ko.wikipedia.org/wiki/Foo_(bar)")]),
            // 조사가 붙어도 주소는 ASCII 에서 멈춘다.
            ("https://a.com에서 봐요", [("https://a.com", [], "https://a.com"), ("에서 봐요", [], nil)]),
            ("여기https://a.com", [("여기", [], nil), ("https://a.com", [], "https://a.com")]),
            ("HTTPS://A.COM", [("HTTPS://A.COM", [], "HTTPS://A.COM")]),
            ("[https://a.com](https://a.com)", [("https://a.com", [], "https://a.com")]),
            ("http://b.io/x_y_z", [("http://b.io/x_y_z", [], "http://b.io/x_y_z")]),
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

    /// 망가진 문법은 **원문 글자 그대로**다 — 닫히지 않은 `**`, 홀로 선 백틱, 닫히지 않은 울타리.
    @Test(arguments: [
        "**열고 안 닫음",
        "안 열고 닫음**",
        "`홀로 선 백틱",
        "a ` b",
        "~~열림",
        "x * 앞에 공백 *",
        "2 * 3 = 6",
        "[글](https://a.com",
        "[글] (https://a.com)",
        "**",
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
        let styled = ChatMarkdown.parse(body).flatMap(\.spans).filter { !$0.style.isEmpty }
        #expect(styled.isEmpty, "\"\(body)\" 에 꾸밈이 생겼다: \(styled)")
    }

    /// 닫히지 않은 ``` 는 뒤 줄을 코드로 삼키지 않는다 — 여는 줄도 평범한 글자다.
    @Test func 닫히지_않은_울타리는_뒤_줄을_삼키지_않는다() {
        let lines = ChatMarkdown.parse("```\n**굵게**\n끝")
        #expect(lines.map(\.kind) == [.paragraph, .paragraph, .paragraph])
        #expect(lines.map(\.text) == ["```", "굵게", "끝"])
        #expect(lines[1].spans.first?.style == .bold, "울타리가 안 닫혔는데 다음 줄이 코드로 갔다")
        // 내용 없는 울타리 한 쌍은 **빈 말풍선**이 아니라 원문 그대로다.
        #expect(cmVisible("```\n```") == "```\n```")
    }

    /// 단어 안의 `_` · `~~` · 홑 `*` 는 꾸밈이 아니다(snake_case · `ㅎㅎ~~고마워~~` · `2*3*4` · 가림표).
    /// 줄 머리 기호는 뒤에 공백이 있어야 한다(`-_-` · `>_<`).
    /// 이모티콘은 **한 메시지에 두 번** 넣는다 — 한 번만 넣으면 짝이 없어 고치기 전에도 초록이었다(`^_^ … ^_^` 가 기울임 짝이 됐다).
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
    ])
    func 채팅_손버릇은_글자_그대로다(body: String) {
        let lines = ChatMarkdown.parse(body)
        #expect(lines.map(\.kind) == [.paragraph], "\"\(body)\" 가 \(lines.map(\.kind)) 로 해석됐다")
        #expect(cmVisible(body) == body, "\"\(body)\" → \"\(cmVisible(body))\"")
        #expect(lines.flatMap(\.spans).allSatisfy { $0.style.isEmpty }, "\"\(body)\" 에 꾸밈이 생겼다")
    }

    /// 대조군: 단어 **경계**의 `_` 와 `~~` 는 켜진다(위 시험이 "아예 안 켜서 초록"이 아니다).
    /// 안쪽이 글자면 한 메시지에 짝이 두 벌 있어도 둘 다 켜진다 — 이모티콘 시험의 "두 번 넣기"와 같은 모양이다.
    @Test func 단어_경계의_밑줄과_물결은_켜진다() {
        #expect(cmSame(cmInline("이건 _기울임_ 이다"), [("이건 ", [], nil), ("기울임", .italic, nil), (" 이다", [], nil)]))
        #expect(cmSame(cmInline("(_괄호 안_)"), [("(", [], nil), ("괄호 안", .italic, nil), (")", [], nil)]))
        #expect(cmSame(cmInline("이건 ~~취소~~ 됐어"), [("이건 ", [], nil), ("취소", .strikethrough, nil), (" 됐어", [], nil)]))
        #expect(cmSame(cmInline("*진짜* 좋아 *진짜*"), [("진짜", .italic, nil), (" 좋아 ", [], nil), ("진짜", .italic, nil)]))
        #expect(cmSame(cmInline("_a1_ 와 __b2__"), [("a1", .italic, nil), (" 와 ", [], nil), ("b2", .bold, nil)]))
    }

    /// ★ **이모티콘 무작위 1천 개(시드 고정).** 채팅 이모티콘 · 곱셈 · 가림표를 띄어 섞은 본문은 **글자 하나 안 바뀐다**.
    /// 위 표는 사람이 고른 조합뿐이다 — 여기서는 서로 다른 이모티콘이 한 메시지에서 짝이 되는 조합(`^_^ … -_-`)까지 훑는다.
    /// (글자 보존 무작위 시험은 `*` · `_` 를 기호로 빼고 세서 이 결함을 못 본다.)
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
            #expect(lines.flatMap(\.spans).allSatisfy { $0.style.isEmpty }, "\(body.debugDescription) 에 꾸밈이 생겼다")
        }
        // 짝이 될 만한 기호가 넷 이상인 본문을 실제로 많이 지났다(공허한 초록이 아니다).
        #expect(paired > 300, "기호 넷 이상인 본문이 \(paired)개뿐이다")
    }

    /// 코드 안의 기호는 꾸밈이 아니다 — 조각이든 블록이든.
    @Test func 코드_안의_별표는_굵게가_아니다() {
        #expect(cmSame(cmInline("`**x**`"), [("**x**", .code, nil)]))
        #expect(cmSame(cmInline("**a `**` b**"), [("a ", .bold, nil), ("**", [.bold, .code], nil), (" b", .bold, nil)]))
        #expect(cmSame(cmInline("`https://a.com`"), [("https://a.com", .code, nil)]), "코드 안 주소가 링크가 됐다")

        let block = ChatMarkdown.parse("```swift\n**x** [글](https://a.com)\n\n_y_\n```")
        #expect(block.map(\.kind) == [.codeLabel, .code, .code, .code])
        #expect(block.map(\.text) == ["swift", "**x** [글](https://a.com)", "", "_y_"])
        let code = block.filter { $0.kind == .code }.flatMap(\.spans)
        #expect(!code.isEmpty && code.allSatisfy { $0.style == .code && $0.link == nil }, "코드 블록 안에 꾸밈·링크가 생겼다")
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

    /// 글머리 · 번호 · 인용. 기호는 빠지고(글머리 •·인용 막대는 그리는 쪽 몫), 들여쓰기와 번호 글자는 남는다.
    @Test func 목록과_인용은_줄_머리_기호로_갈린다() {
        let lines = ChatMarkdown.parse("- 사과\n* 배\n+ 감\n  - 안쪽\n1. 하나\n12) 열둘\n> 인용 **굵게**")
        #expect(lines.map(\.kind) == [.bullet, .bullet, .bullet, .bullet, .ordered, .ordered, .quote])
        #expect(lines.map(\.lead) == ["", "", "", "  ", "1. ", "12) ", ""])
        #expect(lines.map(\.text) == ["사과", "배", "감", "  안쪽", "1. 하나", "12) 열둘", "인용 굵게"])
        #expect(lines.last?.spans.last?.style == .bold)

        let drawn = String(ChatMarkdownText.attributed("- 사과\n> 인용", isMine: false).characters)
        #expect(drawn == "• 사과\n▍ 인용", "글머리·인용 막대가 안 붙었다: \(drawn)")
    }

    /// **200자 경계**(서버 상한 · `MessageBody.maxLength`). 상한 길이 본문도 해석되고, 기호뿐인 상한 본문도 글자 그대로다.
    @Test func 상한_200자_본문도_해석되고_글자를_잃지_않는다() {
        let heading = "## " + String(repeating: "가", count: MessageBody.maxLength - 3)
        #expect(heading.unicodeScalars.count == MessageBody.maxLength)
        let line = ChatMarkdown.parse(heading).first
        #expect(line?.kind == .heading(level: 2))
        #expect(line?.text.count == MessageBody.maxLength - 3)

        for unit in ["*", "`", "_", "~", "[", "**a", "*a ", "[a](", "`a", "~~a", "https://a.co/"] {
            let body = String(String(repeating: unit, count: MessageBody.maxLength).prefix(MessageBody.maxLength))
            let visible = cmVisible(body)
            #expect(cmIsSubsequence(visible, of: body), "\"\(unit)\" × 200 이 글자를 지어냈다")
            #expect(cmContent(visible) == cmContent(body), "\"\(unit)\" × 200 에서 내용 글자가 빠졌다")
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

    /// ★ **글자 보존 — 무작위 3천 개(시드 고정).** 어떤 입력에서도:
    ///   ⓐ 그린 글자는 원문의 **부분 수열**이다(새 글자를 지어내거나 순서를 바꾸지 않는다).
    ///   ⓑ `](` 가 없는 입력(= 링크 주소가 숨을 수 없는 입력)에서는 **내용 글자의 개수가 정확히 같다**(기호와 공백만 빠진다).
    ///   ⓒ 나온 링크는 전부 http·https 다.
    @Test func 무작위_입력에서도_기호만_빠지고_내용_글자는_그대로다() {
        var checkedContent = 0, linked = 0
        for body in cmFuzzBodies(seed: 0x0C4E_C4ED, count: 3_000) {
            let lines = ChatMarkdown.parse(body)
            let visible = lines.map(\.text).joined(separator: "\n")
            #expect(cmIsSubsequence(visible, of: body), "글자를 지어냈다: \(body.debugDescription) → \(visible.debugDescription)")
            #expect(visible.count <= body.count)
            if !body.contains("](") {
                checkedContent += 1
                #expect(cmContent(visible) == cmContent(body), "내용 글자가 빠졌다: \(body.debugDescription) → \(visible.debugDescription)")
            }
            for link in lines.flatMap(\.spans).compactMap(\.link) {
                linked += 1
                #expect(ChatMarkdown.isOpenable(link), "열 수 없는 링크가 생겼다: \(link) ← \(body.debugDescription)")
            }
        }
        // 무작위가 실제로 갈래를 지났다(공허한 초록이 아니다).
        #expect(checkedContent > 1_000, "내용 비교를 한 입력이 \(checkedContent)개뿐이다")
        #expect(linked > 100, "링크가 \(linked)개뿐이다 — 링크 갈래를 안 지났다")
    }
}

// MARK: - ② 한 줄 미리보기

@Suite("ChatMarkdownPreview")
struct ChatMarkdownPreviewTests {
    @Test func 미리보기는_기호를_벗기고_줄바꿈을_공백으로_접는다() {
        #expect(ChatMarkdown.plainPreview("## 제목\n**굵게** 와 [글](https://a.com) 그리고 `코드`")
                == "제목 굵게 와 글 그리고 코드")
        #expect(ChatMarkdown.plainPreview("- 사과\n- 배\n\n> 인용") == "사과 배 인용")
        #expect(ChatMarkdown.plainPreview("```swift\nlet a = 1\n```") == "let a = 1", "코드 꼬리표가 미리보기에 섞였다")
        #expect(ChatMarkdown.plainPreview("1. 하나\n2. 둘") == "1. 하나 2. 둘", "번호 글자는 내용이다")
        // 열 수 없는 링크는 원문 그대로다(말풍선과 같은 판정).
        #expect(ChatMarkdown.plainPreview("[글](javascript:alert(1))") == "[글](javascript:alert(1))")
    }

    /// 평범한 한 줄 본문은 **글자 하나도** 안 바뀐다 — 바뀌면 그게 "내 말이 화면에서 달라지는" 버그다.
    @Test(arguments: ["화이팅", "오늘 고생했어요", "점심 드셨어요?", "고마워요 :)", "👍🏻🎉🇰🇷", "snake_case", "-_-", "2 * 3 = 6", "https://a.com"])
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
    /// 대조군은 같은 글자의 평문이다 — 해석을 안 지나면 `## ` 는 본문 크기 글자로 그려져 높이가 같다.
    @Test func 제목은_말풍선에서_실제로_더_높게_그려진다() throws {
        func inkHeight(_ body: String) throws -> Int {
            let bitmap = try cmConversation(body: body)
            let ink = try #require(cmInk(bitmap, against: try cmBlank(matching: bitmap)), "\"\(body)\" 가 아무것도 안 그렸다")
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
    @Test func 굵게_기호는_말풍선에서_사라진다() throws {
        func inkRight(_ body: String) throws -> Int {
            let bitmap = try cmConversation(body: body)
            return try #require(cmInk(bitmap, against: try cmBlank(matching: bitmap), bottomRows: 60)).maxX
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
    /// 예전 산식(전체 글자 수 / 15)은 줄바꿈·제목을 몰라서 아래 본문들을 한두 줄로 셌다.
    @Test func 틀_높이_추정은_그려진_말풍선보다_작지_않다() throws {
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
            let bitmap = try cmConversation(body: body, height: 420)
            let ink = try #require(cmInk(bitmap, against: try cmBlank(matching: bitmap)), "\(body.debugDescription) 가 안 그려졌다")
            let drawn = CGFloat(ink.maxY - ink.minY) / 2
            #expect(estimate >= drawn, "추정 \(estimate)pt < 그려진 \(drawn)pt — \(body.debugDescription)")
        }
    }

    /// 소스 계약 — 말풍선이 **이모티콘 폴백을 먼저** 거친 뒤 마크다운을 그리고, 링크 문에 스킴 검사를 세운다.
    /// 받은 말풍선의 우클릭 [복사]·[신고]와 내 말풍선의 글자 선택은 그대로다.
    @Test func 말풍선은_이모티콘_폴백_뒤에_마크다운을_그린다() throws {
        let view = try cmSource("CheckMessageView.swift")
        let bubble = try #require(cmRegion(view, from: "private var textBubble: some View {", to: "\n    }"))
        #expect(bubble.contains("Text(ChatMarkdownText.attributed(AingStickerText.preview(for: entry.body), isMine: entry.isMine))"))
        #expect(bubble.contains(".environment(\\.openURL, OpenURLAction(handler: ChatMarkdownText.openAction))"),
                "링크 문 앞의 스킴 검사가 없다")
        #expect(bubble.contains(".tint(ChatMarkdownText.linkColor(isMine: entry.isMine))"))
        #expect(view.contains("CheckPasteboard.copy(entry.body)"), "우클릭 복사가 원문이 아니다")

        let row = try #require(cmRegion(view, from: "private struct MessageBubbleRow: View {", to: "// MARK: - 입력줄"))
        #expect(row.components(separatedBy: ".contextMenu {").count - 1 == 1)
        #expect(row.components(separatedBy: ".textSelection(.enabled)").count - 1 == 1, "글자 선택 자리가 바뀌었다")

        // 틀 높이 추정도 말풍선과 같은 글자(이모티콘 폴백 → 마크다운)로 센다.
        let estimate = try #require(cmRegion(view, from: "static func conversationContentHeight(", to: "\n    }"))
        #expect(estimate.contains("textBubbleHeight(AingStickerText.preview(for: entry.body))"))
    }
}
