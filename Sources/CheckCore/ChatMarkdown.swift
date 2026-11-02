import Foundation

// MARK: - 채팅 마크다운 해석기 (대표 요청 2026-11-03 ③④)
//
// 요청 원문: "채팅에 마크다운 형식으로 작성한것도 반영되게 개선해줘. 시프트 엔터로 줄바꿈이나 ## 글자 로 글자 크기
// 키우거나 등등." · "링크같은건 클릭해서 실제 해당 링크로 브라우저 열리게도 해줘."
//
// 여기는 **해석만** 한다(순수 함수 · Foundation 만). 그리는 것은 맥 말풍선(`ChatMarkdownText` — Sources/check)이고,
// 한 줄 미리보기 자리(팝오버 수신 줄 · 캐릭터 도착 말풍선 · 신고 인용 · 확성기 배너)는 `plainPreview` 를 쓴다.
// 폰이 나중에 같은 해석을 쓸 수 있게 코어에 둔다(지금 폰은 평문 그대로다 — 이번 범위 밖).
//
// ## 왜 직접 해석하는가 — `AttributedString(markdown:)` 을 안 쓴 이유
//  · 블록(## 제목 · 목록 · 인용 · 코드 블록)은 그 파서가 `presentationIntent` 로만 남기고 SwiftUI `Text` 는 크기를
//    바꾸지 않는다. 줄 단위는 어차피 직접 해야 한다.
//  · 줄 안에서도 **글자가 바뀌는 길**이 있다: HTML 개체(`&amp;` → `&`) · 백슬래시 이스케이프(`\*` → `*`).
//    "해석 실패로 글자가 사라지는 일이 절대 없어야 한다"를 남의 파서 동작에 걸어 둘 수 없다.
//  · "모양은 링크인데 http·https 가 아니면 **원문 그대로**"는 원문 위치를 알아야 한다 — 그 파서는 위치를 안 준다.
//
// ## 지키는 규약 넷 (ChatMarkdownTests 가 하나씩 잰다)
//  ① **글자 보존.** 빠지는 것은 기호(# * _ ~ ` [ ] ( ) > - + 와 기호 뒤 공백)뿐이다. 내용 글자는 하나도 안 빠지고,
//     없는 글자를 만들지도 않는다(글머리 • · 인용 막대는 그리는 쪽이 따로 붙인다 — 여기 `text` 에는 없다).
//     닫히지 않은 `**` · 홀로 선 `` ` `` · 닫히지 않은 ``` 울타리는 **원문 글자 그대로**다.
//  ② **한 번의 줄바꿈은 줄바꿈이다.** 표준 마크다운은 홑 줄바꿈을 공백으로 접지만, ⇧↩ 로 친 줄이 사라지면
//     그건 "내 말이 화면에서 달라지는" 버그다. 원문 한 줄 = 해석한 한 줄(빠지는 것은 ``` 울타리 줄뿐).
//  ③ **링크는 http·https 만.** `javascript:` · `file:` · 사용자 정의 스킴은 글자로만 남는다. 남이 보낸 글이다.
//  ④ **채팅 손버릇을 깨지 않는다.** `-_-` · `>_<` · `*^^*` · `^_^ … ^_^` · `ㅎㅎ~~고마워~~` · `snake_case` · `2*3*4` ·
//     `#해시태그` 는 그대로 글자다(줄 머리 기호는 뒤에 공백을 요구하고, 홑 `*` · `_` · `~~` 는 단어 안에서 켜지지 않고,
//     홑 `*` · `_` 는 안쪽이 글자·숫자일 때만 짝이다 — `ChatInlineParser.closer`).

/// 한 줄의 종류. **원문 한 줄 = 하나다**(``` 울타리 줄만 빠진다 — 규약 ②).
package enum ChatMarkdownLineKind: Equatable, Sendable {
    case paragraph
    /// `# ` · `## ` · `### ` (넷~여섯 개도 받는다 — 크기는 그리는 쪽이 3단계에서 멈춘다).
    case heading(level: Int)
    /// `- ` · `* ` · `+ ` 글머리. 기호는 그리는 쪽이 •로 바꿔 붙인다(들여쓰기는 `lead` 에 원문 그대로).
    case bullet
    /// `1. ` · `1) ` 번호. 번호 글자는 **내용이라** `lead` 에 원문 그대로 있다.
    case ordered
    /// `> ` 인용. 막대는 그리는 쪽이 붙인다.
    case quote
    /// ``` 울타리 안의 한 줄. 해석하지 않는다 — 고정폭 글자 그대로다.
    case code
    /// 여는 울타리 뒤의 꼬리표(```swift 의 `swift`). 버리면 내용 글자가 빠지므로 작은 글자로 남긴다(규약 ①).
    case codeLabel
    /// 빈 줄(문단 간격).
    case blank
}

/// 줄 안 꾸밈. 겹칠 수 있다(`***굵은 기울임***`).
package struct ChatMarkdownStyle: OptionSet, Hashable, Sendable {
    package let rawValue: UInt8
    package init(rawValue: UInt8) { self.rawValue = rawValue }

    package static let bold = ChatMarkdownStyle(rawValue: 1 << 0)
    package static let italic = ChatMarkdownStyle(rawValue: 1 << 1)
    package static let strikethrough = ChatMarkdownStyle(rawValue: 1 << 2)
    package static let code = ChatMarkdownStyle(rawValue: 1 << 3)
}

/// 같은 꾸밈·같은 링크로 이어지는 글자 한 덩어리.
package struct ChatMarkdownSpan: Equatable, Sendable {
    package var text: String
    package var style: ChatMarkdownStyle
    /// 누르면 열 주소. **http·https 뿐이다**(`ChatMarkdown.openableLink` 를 지난 것만 여기 온다).
    package var link: URL?

    package init(text: String, style: ChatMarkdownStyle = [], link: URL? = nil) {
        self.text = text
        self.style = style
        self.link = link
    }
}

/// 해석한 한 줄.
package struct ChatMarkdownLine: Equatable, Sendable {
    package var kind: ChatMarkdownLineKind
    /// 내용 앞에 **원문에서 그대로** 남기는 글자 — 글머리의 들여쓰기, 번호 목록의 `1. `. 기호가 아니라 글자라 여기 둔다.
    package var lead: String
    package var spans: [ChatMarkdownSpan]

    package init(kind: ChatMarkdownLineKind, lead: String = "", spans: [ChatMarkdownSpan] = []) {
        self.kind = kind
        self.lead = lead
        self.spans = spans
    }

    /// 이 줄에 그려지는 글자(`lead` + 조각들). 미리보기 · 틀 높이 추정 · 글자 보존 시험이 **같은 이것**을 센다.
    package var text: String { lead + spans.map(\.text).joined() }
}

package enum ChatMarkdown {
    // MARK: 블록 — 줄 단위

    /// 본문 → 줄들. 줄바꿈은 `isNewline` 전부로 자른다(`"\r\n"` 은 Swift 에서 한 글자라 `"\n"` 으로 자르면 안 잘린다).
    ///
    /// ★ **빈 말풍선 금지.** 해석 결과에 그릴 글자가 하나도 없는데 원문에는 있으면(내용 없는 ``` 울타리 한 쌍)
    ///   원문 줄을 해석 없이 그대로 돌려준다 — 사용자는 상대가 뭘 보냈는지 알아야 한다.
    package static func parse(_ body: String) -> [ChatMarkdownLine] {
        let rows = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var lines: [ChatMarkdownLine] = []
        var index = 0
        while index < rows.count {
            let row = rows[index]
            // 울타리는 **닫혀야** 울타리다. 안 닫히면 여는 줄도 평범한 글자다(규약 ① — 뒤 줄을 통째로 코드로 삼키지 않는다).
            if let info = fenceInfo(row),
               let close = rows[(index + 1)...].firstIndex(where: isFenceClosing) {
                if !info.isEmpty {
                    lines.append(ChatMarkdownLine(kind: .codeLabel, spans: [ChatMarkdownSpan(text: info)]))
                }
                for codeRow in rows[(index + 1)..<close] {
                    let spans = codeRow.isEmpty ? [] : [ChatMarkdownSpan(text: codeRow, style: .code)]
                    lines.append(ChatMarkdownLine(kind: .code, spans: spans))
                }
                index = close + 1
                continue
            }
            lines.append(block(row))
            index += 1
        }
        if lines.allSatisfy({ $0.text.isEmpty }), body.contains(where: { !$0.isWhitespace }) {
            return rows.map { $0.isEmpty ? ChatMarkdownLine(kind: .blank) : ChatMarkdownLine(kind: .paragraph, spans: [ChatMarkdownSpan(text: $0)]) }
        }
        return lines
    }

    /// 여는 울타리면 꼬리표(없으면 `""`), 아니면 nil. 꼬리표에 `` ` `` 가 있으면 울타리가 아니다 —
    /// "```let x```" 처럼 한 줄에 열고 닫은 것은 줄 안 코드 조각이다(CommonMark 와 같은 판정).
    static func fenceInfo(_ row: String) -> String? {
        let body = row.drop(while: { $0 == " " })
        guard row.count - body.count <= 3, body.hasPrefix("```") else { return nil }
        let info = body.drop(while: { $0 == "`" })
        guard !info.contains("`") else { return nil }
        return info.trimmingCharacters(in: .whitespaces)
    }

    static func isFenceClosing(_ row: String) -> Bool {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "`" }
    }

    /// 울타리 밖 한 줄. 줄 머리 기호는 **뒤에 공백이 있어야** 기호다(규약 ④ — `-_-` · `>_<` · `#해시태그`).
    static func block(_ row: String) -> ChatMarkdownLine {
        if row.allSatisfy(\.isWhitespace) { return ChatMarkdownLine(kind: .blank) }
        let chars = Array(row)
        let parser = ChatInlineParser(chars: chars)

        let hashes = chars.prefix(while: { $0 == "#" }).count
        if (1...6).contains(hashes), let start = contentStart(chars, after: hashes) {
            return ChatMarkdownLine(kind: .heading(level: hashes), spans: parser.spans(start..<chars.count))
        }
        if chars.first == ">", let start = contentStart(chars, after: 1) {
            return ChatMarkdownLine(kind: .quote, spans: parser.spans(start..<chars.count))
        }
        let indent = chars.prefix(while: { $0 == " " }).count
        if indent < chars.count, "-*+".contains(chars[indent]), let start = contentStart(chars, after: indent + 1) {
            return ChatMarkdownLine(
                kind: .bullet,
                lead: String(repeating: " ", count: indent),
                spans: parser.spans(start..<chars.count)
            )
        }
        let digits = chars[indent...].prefix(while: { $0.isASCII && $0.isNumber }).count
        if (1...9).contains(digits), indent + digits < chars.count, ".)".contains(chars[indent + digits]),
           let start = contentStart(chars, after: indent + digits + 1) {
            return ChatMarkdownLine(kind: .ordered, lead: String(chars[0..<start]), spans: parser.spans(start..<chars.count))
        }
        return ChatMarkdownLine(kind: .paragraph, spans: parser.spans(0..<chars.count))
    }

    /// `after` 자리부터 공백이 **한 칸 이상** 있고 그 뒤에 글자가 있으면 그 글자 자리. 아니면 nil(기호가 아니다).
    static func contentStart(_ chars: [Character], after: Int) -> Int? {
        var index = after
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
        guard index > after, index < chars.count else { return nil }
        return index
    }

    // MARK: 링크 — http·https 만 (규약 ③)

    /// 누를 수 있는 주소면 URL, 아니면 nil. **링크를 만드는 모든 길이 이 한 함수를 지난다**(맨 주소 · `[글](주소)`).
    ///
    /// 공백 · 제어 문자 · 비ASCII 가 섞인 주소는 받지 않는다: 보이는 글자와 실제로 여는 주소가 달라지는 자동
    /// 인코딩(국제화 도메인 · 퍼센트 인코딩)을 사용자가 모르는 채 거치지 않게 한다.
    package static func openableLink(_ raw: String) -> URL? {
        guard !raw.isEmpty, raw.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else { return nil }
        guard let url = URL(string: raw), isOpenable(url) else { return nil }
        return url
    }

    /// 열어도 되는 주소인가 — 스킴이 http·https 이고 호스트가 있다. 말풍선이 링크를 **누를 때 한 번 더** 묻는 자리다
    /// (해석이 이미 걸렀어도 여는 문에서 다시 본다 — 두 겹이어야 한쪽이 풀린 날에도 `javascript:` 가 안 열린다).
    package static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return false }
        return true
    }

    /// `[https://은행.com](https://딴곳.com)` 처럼 **글이 주소 흉내를 내는데 실제 주소와 다르면** 링크로 만들지 않는다.
    /// 남이 보낸 글이라, 보이는 주소와 여는 주소가 다른 링크는 그 자체로 속임수다. 원문 그대로 두면 둘 다 보인다.
    static func isDisguisedAddress(_ label: String, destination: String) -> Bool {
        let shown = label.trimmingCharacters(in: .whitespaces).lowercased()
        guard shown.contains("://") || shown.hasPrefix("www.") else { return false }
        func bare(_ text: String) -> String { text.hasSuffix("/") ? String(text.dropLast()) : text }
        return bare(shown) != bare(destination.lowercased())
    }

    // MARK: 한 줄 미리보기

    /// 글자만 들어가는 한 줄 자리의 문구 — 기호를 벗기고 줄바꿈은 공백 하나로.
    /// (`## 제목` → `제목` · `**굵게**` → `굵게` · `[글](주소)` → `글` · `` `코드` `` → `코드`)
    ///
    /// ★ **이모티콘 규칙이 먼저다**(`AingStickerText.preview`). 토큰 본문은 "아잉이 기쁨"으로 바뀐 뒤에 여기를 지난다 —
    ///   순서를 뒤집으면 `[아잉:기쁨]` 이 링크 모양 검사부터 받는다(지금은 같은 답이지만 그건 우연이다).
    /// 평범한 한 줄 본문은 **글자 하나도** 바뀌지 않는다(앞뒤 공백만 걷는다).
    package static func plainPreview(_ body: String) -> String {
        parse(AingStickerText.preview(for: body))
            .filter { $0.kind != .codeLabel }
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - 줄 안 해석

/// 한 줄 안의 꾸밈. 글자 배열 위를 왼쪽부터 한 번 훑고, 여는 기호를 만나면 **같은 줄 안에서** 닫는 짝을 찾는다.
/// 짝이 없으면 그 기호는 글자다(규약 ①). 우선순위: 코드 조각 → 링크 → 맨 주소 → 강조.
/// 코드 조각이 먼저인 이유: `` `**x**` `` 안의 `**` 는 굵게가 아니라 코드다.
struct ChatInlineParser {
    let chars: [Character]

    func spans(
        _ range: Range<Int>,
        style: ChatMarkdownStyle = [],
        link: URL? = nil,
        allowsLinks: Bool = true
    ) -> [ChatMarkdownSpan] {
        var out: [ChatMarkdownSpan] = []
        var plain = ""
        func flush() {
            guard !plain.isEmpty else { return }
            out.append(ChatMarkdownSpan(text: plain, style: style, link: link))
            plain = ""
        }

        var index = range.lowerBound
        let end = range.upperBound
        while index < end {
            let char = chars[index]

            if char == "`" {
                let run = runLength(at: index, end: end)
                if let close = codeClose(from: index + run, run: run, end: end) {
                    flush()
                    out.append(ChatMarkdownSpan(
                        text: String(chars[(index + run)..<close]), style: style.union(.code), link: link
                    ))
                    index = close + run
                } else {
                    // 홀로 선 백틱 묶음은 통째로 글자다(묶음 안 백틱을 하나씩 다시 시도하지 않는다).
                    plain.append(contentsOf: chars[index..<(index + run)])
                    index += run
                }
                continue
            }

            if allowsLinks, char == "[", let shape = linkShape(at: index, end: end) {
                let label = String(chars[shape.label])
                if !shape.label.isEmpty,
                   let url = ChatMarkdown.openableLink(shape.destination),
                   !ChatMarkdown.isDisguisedAddress(label, destination: shape.destination) {
                    flush()
                    out += spans(shape.label, style: style, link: url, allowsLinks: false)
                } else {
                    // 모양은 링크인데 열 수 없는 주소(javascript: · file: · 사용자 정의 스킴) · 빈 글 · 주소 흉내 글 —
                    // **통째로 원문 글자**다. 안쪽을 따로 해석하지 않는다(보낸 사람이 친 그대로 보여야 무엇인지 안다).
                    plain.append(contentsOf: chars[index..<shape.next])
                }
                index = shape.next
                continue
            }

            if allowsLinks, char == "h" || char == "H", let urlEnd = bareURLEnd(at: index, end: end),
               let url = ChatMarkdown.openableLink(String(chars[index..<urlEnd])) {
                flush()
                out.append(ChatMarkdownSpan(text: String(chars[index..<urlEnd]), style: style, link: url))
                index = urlEnd
                continue
            }

            if char == "*" || char == "_" || char == "~", let found = emphasis(at: index, end: end) {
                flush()
                out += spans(found.inner, style: style.union(found.style), link: link, allowsLinks: allowsLinks)
                index = found.next
                continue
            }

            plain.append(char)
            index += 1
        }
        flush()
        return out
    }

    // MARK: 코드 조각

    /// `index` 에서 시작하는 같은 글자 묶음의 길이.
    func runLength(at index: Int, end: Int) -> Int {
        var cursor = index
        while cursor < end, chars[cursor] == chars[index] { cursor += 1 }
        return cursor - index
    }

    /// 여는 백틱 묶음과 **길이가 같은** 닫는 묶음의 자리(``` `` a`b `` ``` 의 홑 백틱은 짝이 아니다). 내용이 비면 nil.
    func codeClose(from start: Int, run: Int, end: Int) -> Int? {
        var cursor = start
        while cursor < end {
            guard chars[cursor] == "`" else { cursor += 1; continue }
            let length = runLength(at: cursor, end: end)
            if length == run { return cursor > start ? cursor : nil }
            cursor += length
        }
        return nil
    }

    // MARK: 링크

    /// `[글](주소)` 모양이면 (글 자리, 주소 글자, 다음 자리). 글 안에 `[` 가 또 있거나 · `](` 가 아니거나 ·
    /// 주소에 공백이 있거나 · 괄호가 안 닫히면 nil(모양이 아니다 — `[` 는 글자로 남는다).
    /// 주소 안 괄호는 짝을 센다(`https://ko.wikipedia.org/wiki/Foo_(bar)`).
    func linkShape(at index: Int, end: Int) -> (label: Range<Int>, destination: String, next: Int)? {
        var close = index + 1
        while close < end, chars[close] != "]" {
            if chars[close] == "[" { return nil }
            close += 1
        }
        guard close + 1 < end, chars[close + 1] == "(" else { return nil }
        let destinationStart = close + 2
        var depth = 0
        var cursor = destinationStart
        while cursor < end {
            let char = chars[cursor]
            if char.isWhitespace { return nil }
            if char == "(" {
                depth += 1
            } else if char == ")" {
                if depth == 0 { break }
                depth -= 1
            }
            cursor += 1
        }
        guard cursor < end, cursor > destinationStart else { return nil }
        return (index + 1..<close, String(chars[destinationStart..<cursor]), cursor + 1)
    }

    /// 맨 주소(`http://` · `https://` 로 시작)의 끝 자리. 아니면 nil.
    ///
    /// · 앞 글자가 **영문·숫자면** 단어 한가운데라 주소가 아니다(`xhttps://…`). 한글 뒤는 받는다(`여기https://…`).
    /// · 주소는 **ASCII 에서 멈춘다**: `https://a.com에서` 의 `에서` 는 주소가 아니다(조사가 붙는 한국어 손버릇).
    ///   그 대가로 한글 경로를 풀어 쓴 주소는 한글 앞까지만 링크다 — 글자는 그대로 보이고, 브라우저 주소창에서
    ///   복사한 주소는 대개 퍼센트 인코딩이라 통째로 링크다.
    /// · 꼬리 문장부호는 주소가 아니다(`…a.com.` 의 마침표 · `(https://a.com)` 의 짝 없는 닫는 괄호).
    func bareURLEnd(at index: Int, end: Int) -> Int? {
        if index > 0 {
            let before = chars[index - 1]
            if before.isASCII, before.isLetter || before.isNumber { return nil }
        }
        let schemeLength: Int
        if hasPrefixIgnoringCase("https://", at: index, end: end) {
            schemeLength = 8
        } else if hasPrefixIgnoringCase("http://", at: index, end: end) {
            schemeLength = 7
        } else {
            return nil
        }
        let bodyStart = index + schemeLength
        var cursor = bodyStart
        while cursor < end, Self.isURLCharacter(chars[cursor]) { cursor += 1 }
        while cursor > bodyStart {
            let last = chars[cursor - 1]
            if ".,;:!?'\"*_~".contains(last) {
                cursor -= 1
            } else if last == ")", count("(", in: index..<cursor) < count(")", in: index..<cursor) {
                cursor -= 1
            } else if last == "]", count("[", in: index..<cursor) < count("]", in: index..<cursor) {
                cursor -= 1
            } else {
                break
            }
        }
        return cursor > bodyStart ? cursor : nil
    }

    static func isURLCharacter(_ char: Character) -> Bool {
        guard char.isASCII, let value = char.asciiValue, value > 0x20, value < 0x7F else { return false }
        return !"<>\"`".contains(char)
    }

    func hasPrefixIgnoringCase(_ prefix: String, at index: Int, end: Int) -> Bool {
        let wanted = Array(prefix)
        guard index + wanted.count <= end else { return false }
        for (offset, char) in wanted.enumerated() where chars[index + offset].lowercased() != String(char) {
            return false
        }
        return true
    }

    func count(_ char: Character, in range: Range<Int>) -> Int {
        chars[range].reduce(0) { $0 + ($1 == char ? 1 : 0) }
    }

    // MARK: 강조

    /// 강조 기호 자리에서 (안쪽 자리, 꾸밈, 다음 자리). 짝이 없으면 nil — 그 기호는 글자다.
    /// `**` 굵게 · `__` 굵게 · `~~` 취소선 · `*` 기울임 · `_` 기울임. 홑 `~` 는 꾸밈이 아니다(`안녕~`).
    func emphasis(at index: Int, end: Int) -> (inner: Range<Int>, style: ChatMarkdownStyle, next: Int)? {
        let mark = chars[index]
        if index + 1 < end, chars[index + 1] == mark, let close = closer(mark, width: 2, openAt: index, end: end) {
            return (index + 2..<close, mark == "~" ? .strikethrough : .bold, close + 2)
        }
        if mark != "~", let close = closer(mark, width: 1, openAt: index, end: end) {
            return (index + 1..<close, .italic, close + 1)
        }
        return nil
    }

    /// 닫는 짝의 자리. 여는 기호 바로 뒤가 공백이면 여는 기호가 아니고(`* 항목` · `2 * 3`),
    /// 닫는 기호 바로 앞이 공백이면 닫는 기호가 아니다. 내용은 한 글자 이상이다.
    ///
    /// **단어 안에서 안 켜진다**(규약 ④): 홑 `*` · `_` · `__` · `~~` 는 여는 기호 앞 · 닫는 기호 뒤가 글자(한글 포함)·숫자면
    /// 기호가 아니다(`snake_case` · `ㅎㅎ~~고마워~~` · `2*3*4` · 가림표 `시*발 … 시*발`).
    /// `**` 만 단어 안에서도 켜진다 — 조사가 붙는 한국어에서 `이건**중요**해` 가 굵게 되어야 한다.
    ///
    /// **안쪽이 글자여야 켜진다**: 홑 `*` 와 `_` · `__` 는 여는 기호 바로 뒤 · 닫는 기호 바로 앞이 글자·숫자일 때만 짝이다.
    /// 이모티콘(`*^^*` · `^_^` · `-_-` · `>_<` · `*.*` · `^__^`)의 기호는 안쪽이 문장부호라 글자로 남는다 — 공백 검사만으로는
    /// 한 메시지에 두 번 나온 `^_^ … ^_^` 가 기울임 짝이 되어 기호가 사라졌다(한글은 기울임이 안 보여 그냥 지워진 것으로 보인다).
    /// `**` · `~~` 는 이 검사를 하지 않는다 — `**"인용"**` · `**(중요)**` 처럼 문장부호를 감싸는 굵게가 흔하다.
    func closer(_ mark: Character, width: Int, openAt index: Int, end: Int) -> Int? {
        let first = index + width
        guard first < end, !chars[first].isWhitespace else { return nil }
        if width == 1, chars[first] == mark { return nil }
        let wordBound = !(mark == "*" && width == 2)
        let wordInside = mark == "_" || (mark == "*" && width == 1)
        if wordInside, !Self.isWordCharacter(chars[first]) { return nil }
        if wordBound, index > 0, Self.isWordCharacter(chars[index - 1]) { return nil }

        var cursor = first + 1
        while cursor < end {
            let char = chars[cursor]
            if char == "`" {
                // 코드 조각 안의 기호는 짝이 아니다(`**a `**` b**` 의 가운데 ** 는 코드다).
                let run = runLength(at: cursor, end: end)
                if let close = codeClose(from: cursor + run, run: run, end: end) {
                    cursor = close + run
                } else {
                    cursor += run
                }
                continue
            }
            guard char == mark else { cursor += 1; continue }
            let run = runLength(at: cursor, end: end)
            // 홑 기호의 짝을 찾을 때 `**` 묶음은 건너뛴다(`*a **b** c*` 의 바깥 짝은 맨 끝 `*` 다).
            if width == 1, run >= 2 { cursor += run; continue }
            if run >= width, !chars[cursor - 1].isWhitespace, !wordInside || Self.isWordCharacter(chars[cursor - 1]) {
                // `***` 는 마지막 둘(또는 하나)이 짝이다 — `***굵은 기울임***` 의 안쪽에 `*…*` 가 남는다.
                let close = cursor + run - width
                if wordBound, close + width < chars.count, Self.isWordCharacter(chars[close + width]) {
                    cursor += run
                    continue
                }
                return close
            }
            cursor += run
        }
        return nil
    }

    static func isWordCharacter(_ char: Character) -> Bool { char.isLetter || char.isNumber }
}
