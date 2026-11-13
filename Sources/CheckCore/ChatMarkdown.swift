import Foundation

// MARK: - 채팅 마크다운 해석기 (대표 요청 2026-11-03 ③④ · 범위는 대표 결정 "제목·굵게·링크만")
//
// 요청 원문: "채팅에 마크다운 형식으로 작성한것도 반영되게 개선해줘. 시프트 엔터로 줄바꿈이나 ## 글자 로 글자 크기
// 키우거나 등등." · "링크같은건 클릭해서 실제 해당 링크로 브라우저 열리게도 해줘."
// 범위 결정(대표 답 원문): "제목·굵게·링크만" — 나머지 문법은 **기호 그대로** 보인다.
//
//  · 받는 것 셋: 줄 머리 `# ` · `## ` · `### ` 제목 · `**굵게**` · 링크(`[글](주소)` 와 맨 http·https 주소).
//  · 안 받는 것(입력한 글자 그대로): `*기울임*` · `_기울임_` · `__굵게__` · `~~취소~~` · `` `코드` `` · ``` 울타리 ·
//    글머리(`- ` · `* ` · `+ `) · 번호(`1. ` · `1) `) · 인용(`> `). 이 갈래들은 끄는 스위치 없이 **아예 없다** —
//    다시 받기로 하면 새로 짓는다(2026-11-03 첫 판의 해석기는 git 이력 44995f49 에 있다).
//
// 여기는 **해석만** 한다(순수 함수 · Foundation 만). 그리는 것은 맥 말풍선(`ChatMarkdownText` — Sources/check)이고,
// 한 줄 미리보기 자리(팝오버 수신 줄 · 캐릭터 도착 말풍선 · 신고 인용 · 확성기 배너)는 `plainPreview` 를 쓴다.
// 폰도 같은 해석을 쓴다(1.0.17 — 말풍선 `MessagesBubbleMarkdown` · 한 줄 자리 넷도 `plainPreview`). 그릴 조각 · 복사 글은 `ChatMarkdownPieces`.
//
// ## 왜 직접 해석하는가 — `AttributedString(markdown:)` 을 안 쓴 이유
//  · 그 파서는 기울임·코드·목록·인용까지 다 해석한다. 받는 문법을 셋으로 좁히려면 결과를 되돌려 기호를 다시 지어내야 한다.
//  · 제목(`## `)은 그 파서가 `presentationIntent` 로만 남기고 SwiftUI `Text` 는 크기를 바꾸지 않는다. 줄 단위는 어차피 직접 한다.
//  · 줄 안에서도 **글자가 바뀌는 길**이 있다: HTML 개체(`&amp;` → `&`) · 백슬래시 이스케이프(`\*` → `*`).
//    "해석 실패로 글자가 사라지는 일이 절대 없어야 한다"를 남의 파서 동작에 걸어 둘 수 없다.
//  · "모양은 링크인데 http·https 가 아니면 **원문 그대로**"는 원문 위치를 알아야 한다 — 그 파서는 위치를 안 준다.
//
// ## 지키는 규약 넷 (ChatMarkdownTests 가 하나씩 잰다)
//  ① **글자 보존.** 빠지는 것은 제목 `#` 과 그 뒤 공백 · 짝이 맞은 `**` · 링크의 `[` `](주소)` 뿐이다. 내용 글자는
//     하나도 안 빠지고, 없는 글자를 만들지도 않는다. 닫히지 않은 `**` 는 **원문 글자 그대로**다.
//  ② **한 번의 줄바꿈은 줄바꿈이다.** 표준 마크다운은 홑 줄바꿈을 공백으로 접지만, ⇧↩ 로 친 줄이 사라지면
//     그건 "내 말이 화면에서 달라지는" 버그다. 원문 한 줄 = 해석한 한 줄(예외 없다).
//  ③ **링크는 http·https 만.** `javascript:` · `file:` · 사용자 정의 스킴은 글자로만 남는다. 남이 보낸 글이다.
//  ④ **채팅 손버릇을 깨지 않는다.** `-_-` · `>_<` · `*^^*` · `^_^ … ^_^` · `ㅎㅎ~~고마워~~` · `snake_case` · `2*3*4` ·
//     `#해시태그` · `- 항목` · `> 인용` 은 그대로 글자다. 홑 `*` · `_` · `~` · `` ` `` · `>` · `-` 는 아예 기호가 아니고,
//     제목 `#` 은 뒤에 공백을 요구한다. `**` 만 단어 안에서도 켜진다 — `이건**중요**해`(`ChatInlineParser.boldClose`).

/// 한 줄의 종류. **원문 한 줄 = 하나다**(규약 ②).
package enum ChatMarkdownLineKind: Equatable, Sendable {
    case paragraph
    /// `# ` · `## ` · `### ` (넷~여섯 개도 받는다 — 크기는 그리는 쪽이 3단계에서 멈춘다).
    case heading(level: Int)
    /// 빈 줄(공백만 있는 줄 포함 — 문단 간격).
    case blank
}

/// 같은 굵기·같은 링크로 이어지는 글자 한 덩어리.
package struct ChatMarkdownSpan: Equatable, Sendable {
    package var text: String
    /// `**굵게**` 안의 글자. 제목 줄은 이 값과 상관없이 그리는 쪽이 굵게 그린다.
    package var isBold: Bool
    /// 누르면 열 주소. **http·https 뿐이다**(`ChatMarkdown.openableLink` 를 지난 것만 여기 온다).
    package var link: URL?

    package init(text: String, isBold: Bool = false, link: URL? = nil) {
        self.text = text
        self.isBold = isBold
        self.link = link
    }
}

/// 해석한 한 줄.
package struct ChatMarkdownLine: Equatable, Sendable {
    package var kind: ChatMarkdownLineKind
    package var spans: [ChatMarkdownSpan]

    package init(kind: ChatMarkdownLineKind, spans: [ChatMarkdownSpan] = []) {
        self.kind = kind
        self.spans = spans
    }

    /// 이 줄의 해석 글자(조각들). 미리보기 · 틀 높이 추정 · 글자 보존 시험이 **같은 이것**을 센다.
    /// 그리는 쪽이 덧붙이는 것은 링크 호스트 꼬리표 하나뿐이다(`linkDisclosures`).
    package var text: String { spans.map(\.text).joined() }
}

package enum ChatMarkdown {
    // MARK: 줄 — 제목만 줄 머리 기호다

    /// 본문 → 줄들. 줄바꿈은 `isNewline` 전부로 자른다(`"\r\n"` 은 Swift 에서 한 글자라 `"\n"` 으로 자르면 안 잘린다).
    ///
    /// 빈 말풍선은 생기지 않는다: 공백 아닌 글자가 있는 줄은 해석 글자도 비지 않는다(제목은 기호 뒤 내용을 요구하고,
    /// `**` 짝은 한 글자 이상을 감싸고, 링크는 빈 글을 받지 않는다 — 무작위 시험이 잰다).
    package static func parse(_ body: String) -> [ChatMarkdownLine] {
        body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { line(String($0)) }
    }

    /// 한 줄. 줄 머리 `#` 은 **뒤에 공백이 있어야** 제목이다(규약 ④ — `#해시태그`).
    static func line(_ row: String) -> ChatMarkdownLine {
        if row.allSatisfy(\.isWhitespace) { return ChatMarkdownLine(kind: .blank) }
        let chars = Array(row)
        let parser = ChatInlineParser(chars: chars)
        let hashes = chars.prefix(while: { $0 == "#" }).count
        if (1...6).contains(hashes), let start = contentStart(chars, after: hashes) {
            return ChatMarkdownLine(kind: .heading(level: hashes), spans: parser.spans(start..<chars.count))
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
    /// 인코딩(국제화 도메인 · 퍼센트 인코딩)을 사용자가 모르는 채 거치지 않게 한다. 호스트의 퍼센트 인코딩은 `isOpenable` 이 막는다
    /// (원문은 ASCII 여도 `n%D0%B0ver.com` 은 키릴 문자 호스트다 — 2026-11-03 폰 1.0.17 검토).
    package static func openableLink(_ raw: String) -> URL? {
        guard !raw.isEmpty, raw.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) else { return nil }
        guard let url = URL(string: raw), isOpenable(url) else { return nil }
        return url
    }

    /// 열어도 되는 주소인가 — 스킴이 http·https 이고 호스트가 있고 **사용자 정보(`…@`)가 없다**. 말풍선이 링크를 **누를 때 한 번 더**
    /// 묻는 자리다(해석이 이미 걸렀어도 여는 문에서 다시 본다 — 두 겹이어야 한쪽이 풀린 날에도 `javascript:` 가 안 열린다).
    ///
    /// ★ 사용자 정보가 든 주소는 받지 않는다(2026-11-03 검토 P2): `https://naver.com:443@evil.com` 은 naver.com 으로 읽히지만 실제로는
    ///   evil.com 을 연다. 맨 주소는 "글 = 주소"라 호스트 꼬리표(`disclosedHost`)도 안 붙어 속임수가 그대로 통한다. 채팅에서 주소에
    ///   아이디·비밀번호를 실어 보낼 일은 없으므로 링크로 만들지 않고 **친 글자 그대로** 둔다(`[글](주소)` 도 같다 — 원문 기호째 보인다).
    ///   `user` 는 비어 있어도(`https://@evil.com`) nil 이 아니다 — 빈 사용자 정보도 막힌다.
    ///
    /// ★ **호스트에 `%` 가 있으면 받지 않는다**(2026-11-03 폰 1.0.17 검토 critical·major). 원문 글자가 ASCII 여도 호스트를 퍼센트 인코딩하면
    ///   ① `[naver.com](https://n%D0%B0ver.com)` — 꼬리표가 풀린 키릴 'а' 로 "naver.com (nаver.com)" 이 되어 진짜 도메인처럼 보이고, 브라우저는
    ///   `xn--nver-53d.com` 을 연다. ② 맨 주소 `https://naver.com%2Eevil.com` — 글 = 주소라 꼬리표가 없는데 실제 호스트는 `naver.com.evil.com` 이다.
    ///   보이는 호스트와 여는 호스트가 갈리는 길이라 링크로 만들지 않고 **친 글자 그대로** 둔다. 경로 · 질의의 `%`(브라우저에서 복사한 한글 경로)는
    ///   호스트가 아니라 그대로 링크다. Foundation 이 원문에 없던 `%` 를 호스트에 만드는 경우(`|` 같은 글자의 자동 인코딩)도 같이 막힌다.
    package static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let host = url.host(percentEncoded: true), !host.isEmpty, !host.contains("%") else { return false }
        guard url.user(percentEncoded: true) == nil, url.password(percentEncoded: true) == nil else { return false }
        return true
    }

    /// `[https://은행.com](https://딴곳.com)` 처럼 **글이 주소 흉내를 내는데 실제 주소와 다르면** 링크로 만들지 않는다.
    /// 남이 보낸 글이라, 보이는 주소와 여는 주소가 다른 링크는 그 자체로 속임수다. 원문 그대로 두면 둘 다 보인다.
    static func isDisguisedAddress(_ label: String, destination: String) -> Bool {
        let shown = label.trimmingCharacters(in: .whitespaces).lowercased()
        guard shown.contains("://") || shown.hasPrefix("www.") else { return false }
        // 스킴·끝 빗금만 다른 것은 같은 주소다 — `[www.naver.com](https://www.naver.com)` 을 막던 오탐(2026-11-03 검토)을 걷는다.
        return comparableAddress(shown) != comparableAddress(destination)
    }

    /// 주소 비교용 모양: 소문자 · 앞뒤 공백 없음 · `http(s)://` 없음 · 끝 `/` 없음.
    package static func comparableAddress(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespaces).lowercased()
        for scheme in ["https://", "http://"] where value.hasPrefix(scheme) {
            value.removeFirst(scheme.count)
            break
        }
        if value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// `[글](주소)` 링크 뒤에 **실제로 열리는 곳의 호스트**를 붙여 보인다(2026-11-03 검토 P2).
    /// 말풍선에는 마우스를 올려 주소를 볼 길이 없다. 그래서 `[naver.com](https://evil.example)` 은 보이는 글과 여는 곳이 달라도
    /// 알아챌 수 없었다 — 글자 흉내 검사(`isDisguisedAddress`)는 폭 없는 공백 · 전각 쌍점 · 방향 문자로 쉽게 비켜 간다.
    /// 그래서 막는 대신 **보여 준다**: 글이 주소 그 자체이거나(맨 주소) 호스트와 같을 때만 생략하고, 나머지는 `글 (호스트)` 로 그린다.
    /// 반환: 줄의 조각 위치 → 그 조각 뒤에 붙일 호스트(한 링크가 여러 조각이면 마지막 조각 뒤 한 번).
    /// 호스트는 ASCII 다: `openableLink` 가 비ASCII 원문을, `isOpenable` 이 퍼센트 인코딩 호스트(`n%D0%B0ver.com` — 풀면 키릴 문자)를 링크로
    /// 만들지 않는다. 그래서 국제화 도메인은 `xn--` 모양 그대로 보인다(2026-11-03 폰 1.0.17 검토 전에는 이 말이 사실이 아니었다 — 꼬리표가
    /// 퍼센트 인코딩을 풀어 닮은꼴 도메인을 진짜처럼 보였다).
    package static func linkDisclosures(_ line: ChatMarkdownLine) -> [Int: String] {
        var result: [Int: String] = [:]
        var label = ""
        for (index, span) in line.spans.enumerated() {
            guard let url = span.link else {
                label = ""
                continue
            }
            label += span.text
            let nextLink = index + 1 < line.spans.count ? line.spans[index + 1].link : nil
            guard nextLink != url else { continue }
            if let host = disclosedHost(label: label, url: url) { result[index] = host }
            label = ""
        }
        return result
    }

    /// 한 링크의 글과 주소 → 따로 보일 호스트(nil = 글이 이미 그것을 말한다).
    /// 호스트는 **인코딩된 그대로** 읽는다 — 풀어서 보이면 `%D0%B0` 가 키릴 'а' 로 바뀌어 닮은꼴이 진짜처럼 찍힌다(`isOpenable` 이 이미 막지만 두 겹).
    package static func disclosedHost(label: String, url: URL) -> String? {
        guard let host = url.host(percentEncoded: true)?.lowercased(), !host.isEmpty else { return nil }
        let shown = comparableAddress(label)
        if shown == comparableAddress(url.absoluteString) || shown == host { return nil }
        return host
    }

    // MARK: 한 줄 미리보기

    /// 글자만 들어가는 한 줄 자리의 문구 — 받는 세 문법의 기호만 벗기고 줄바꿈은 공백 하나로.
    /// (`## 제목` → `제목` · `**굵게**` → `굵게` · `[글](주소)` → `글`. `` `코드` `` · `- 항목` · `> 인용` 은 말풍선처럼 그대로다.)
    ///
    /// ★ **이모티콘 규칙이 먼저다**(`AingStickerText.preview`). 토큰 본문은 "아잉이 기쁨"으로 바뀐 뒤에 여기를 지난다 —
    ///   순서를 뒤집으면 `[아잉:기쁨]` 이 링크 모양 검사부터 받는다(지금은 같은 답이지만 그건 우연이다).
    /// 평범한 한 줄 본문은 **글자 하나도** 바뀌지 않는다(앞뒤 공백만 걷는다).
    package static func plainPreview(_ body: String) -> String {
        parse(AingStickerText.preview(for: body))
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - 줄 안 해석

/// 한 줄 안의 꾸밈. 글자 배열 위를 왼쪽부터 한 번 훑고, 여는 기호를 만나면 **같은 줄 안에서** 닫는 짝을 찾는다.
/// 짝이 없으면 그 기호는 글자다(규약 ①). 우선순위: 링크 → 맨 주소 → 굵게.
/// 링크가 굵게보다 먼저인 이유: 주소 안의 `*` 를 굵게 짝으로 쓰지 않는다(`[글](https://a.com/**x**)` 의 주소는 통째로 주소다).
/// 여는 `**` 가 링크 **앞**에 있어도 같다 — 닫는 짝을 찾을 때 링크 모양 · 맨 주소는 통째로 건너뛴다(`boldClose` · 2026-11-03 검토 nit:
/// 예전엔 `**a [글](https://x.com/**) b**` 의 닫는 짝을 주소 안에서 찾아 주소가 `https://x.com/` 으로 바뀌었다).
struct ChatInlineParser {
    let chars: [Character]

    func spans(
        _ range: Range<Int>,
        isBold: Bool = false,
        link: URL? = nil,
        allowsLinks: Bool = true
    ) -> [ChatMarkdownSpan] {
        var out: [ChatMarkdownSpan] = []
        var plain = ""
        func flush() {
            guard !plain.isEmpty else { return }
            out.append(ChatMarkdownSpan(text: plain, isBold: isBold, link: link))
            plain = ""
        }

        var index = range.lowerBound
        let end = range.upperBound
        while index < end {
            let char = chars[index]

            if allowsLinks, char == "[", let shape = linkShape(at: index, end: end) {
                let label = String(chars[shape.label])
                if !shape.label.isEmpty,
                   let url = ChatMarkdown.openableLink(shape.destination),
                   !ChatMarkdown.isDisguisedAddress(label, destination: shape.destination) {
                    flush()
                    out += spans(shape.label, isBold: isBold, link: url, allowsLinks: false)
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
                out.append(ChatMarkdownSpan(text: String(chars[index..<urlEnd]), isBold: isBold, link: url))
                index = urlEnd
                continue
            }

            if char == "*", let close = boldClose(openAt: index, end: end, allowsLinks: allowsLinks) {
                flush()
                out += spans(index + 2..<close, isBold: true, link: link, allowsLinks: allowsLinks)
                index = close + 2
                continue
            }

            plain.append(char)
            index += 1
        }
        flush()
        return out
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
    /// · 꼬리 문장부호는 주소가 아니다(`…a.com.` 의 마침표 · `(https://a.com)` 의 짝 없는 닫는 괄호 ·
    ///   `**https://a.com**` 의 굵게 기호 · `https://a.com~~` 의 물결 손버릇).
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

    // MARK: 굵게

    /// `index` 의 `**` 를 닫는 `**` 의 자리. 짝이 없으면 nil — 그 `*` 는 글자다(규약 ①). 받는 꾸밈은 이것 하나다.
    ///
    /// · 여는 `**` 바로 뒤가 공백이면 여는 기호가 아니다(`** 굵게**`). 닫는 `**` 바로 앞이 공백이면 닫는 기호가 아니다.
    /// · **단어 안에서도 켜진다** — 조사가 붙는 한국어에서 `이건**중요**해` 가 굵게 되어야 한다.
    /// · 문장부호를 감싸도 켜진다 — `**"인용"**` · `**(중요)**`.
    /// · `*` 가 셋 이상 이어진 닫는 묶음은 마지막 둘이 짝이다: `***둘 다***` 는 굵은 `*둘 다*` 다(홑 `*` 는 글자다).
    /// · 안쪽은 한 글자 이상이다(`****` 는 글자 그대로).
    /// 홑 `*` 는 여기 오지 않는다 — `*^^*` · `2*3*4` · 가림표 `시*발` 은 짝을 찾을 일이 없다.
    /// · 닫는 짝은 **링크 밖에서만** 찾는다: 사이에 든 링크 모양(`[글](주소)` — 열 수 없는 것도 통째로 원문 한 덩어리다) · 맨 주소는
    ///   건너뛴다(`linkSkip`). 안쪽을 다시 해석할 때(`spans`) 같은 자리에서 같은 링크가 잡힌다 — 판정이 같은 함수라서.
    func boldClose(openAt index: Int, end: Int, allowsLinks: Bool = true) -> Int? {
        let first = index + 2
        guard first < end, chars[index + 1] == "*", !chars[first].isWhitespace else { return nil }
        var cursor = first
        while cursor < end {
            if allowsLinks, let next = linkSkip(at: cursor, end: end) {
                cursor = next
                continue
            }
            // 여는 `**` 바로 뒤 글자(`first`)는 닫는 묶음의 시작이 아니다(`****` 는 글자 · `***둘 다***` 의 셋째 `*` 는 안쪽 글자).
            guard cursor > first, chars[cursor] == "*" else {
                cursor += 1
                continue
            }
            let run = runLength(at: cursor, end: end)
            if run >= 2, !chars[cursor - 1].isWhitespace { return cursor + run - 2 }
            cursor += run
        }
        return nil
    }

    /// `index` 에서 링크가 시작하면(`spans` 가 링크 → 맨 주소 순으로 잡는 그 판정) 그 링크가 끝난 자리. 아니면 nil.
    /// 링크 모양은 열 수 있든 없든 건너뛴다 — `spans` 가 둘 다 통째로 한 덩어리로 다룬다(링크이거나, 원문 글자이거나).
    /// 맨 주소는 링크가 될 때만 건너뛴다 — 링크가 못 되면 `spans` 에서도 평범한 글자다.
    func linkSkip(at index: Int, end: Int) -> Int? {
        let char = chars[index]
        if char == "[", let shape = linkShape(at: index, end: end) { return shape.next }
        if char == "h" || char == "H", let urlEnd = bareURLEnd(at: index, end: end),
           ChatMarkdown.openableLink(String(chars[index..<urlEnd])) != nil {
            return urlEnd
        }
        return nil
    }

    /// `index` 에서 시작하는 같은 글자 묶음의 길이.
    func runLength(at index: Int, end: Int) -> Int {
        var cursor = index
        while cursor < end, chars[cursor] == chars[index] { cursor += 1 }
        return cursor - index
    }
}
