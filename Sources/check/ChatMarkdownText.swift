import SwiftUI
import CheckCore

// MARK: - 말풍선 마크다운 그리기 (대표 요청 2026-11-03 ③④)
//
// 해석은 `ChatMarkdown`(CheckCore — 순수 함수)이 하고, 여기는 그 줄들을 **AttributedString 한 장**으로 옮긴다.
// 말풍선(`MessageBubbleRow.textBubble`)과 틀 높이 추정(`MessagePanelLayout.textBubbleHeight`)이 이 파일의 크기 표를 같이 쓴다.
//
// ## 왜 한 장인가 — 줄마다 Text 를 세우지 않는 이유
//  · 내 말풍선의 글자 선택(`textSelection`)은 Text **하나 안에서만** 이어진다. 줄마다 Text 면 드래그가 줄 끝에서 끊긴다.
//  · 해석이 원문 한 줄을 한 줄로 돌려주므로(`ChatMarkdown` 규약 ②) 줄 사이에 "\n" 하나씩만 넣으면 ⇧↩ 줄바꿈이 그대로 산다.
//
// ## 글꼴은 조각마다 **명시**한다
// 꾸밈(굵게·기울임·코드)을 `inlinePresentationIntent` 로 맡기면 제목 줄의 큰 글꼴과 어떻게 합쳐지는지가 SwiftUI 안쪽 동작이 된다.
// 크기·굵기·고정폭을 조각마다 직접 정해 두면 "제목이 몇 pt 인가"가 이 표 하나로 정해지고, 틀 높이 추정도 같은 표를 읽는다.
//
// ## 링크
// `.link` 를 심은 Text 는 누르면 환경의 `openURL` 이 기본 브라우저로 연다 — 같은 팝오버의 선례가 `SignUpTermsNotice` 다.
// 말풍선은 그 문 앞에 `ChatMarkdown.isOpenable` 을 한 번 더 세운다(`openAction`). 링크 색은 말풍선 바탕을 따른다:
// 내 말풍선은 **강조색(파랑) 바탕**이라 강조색 링크가 바탕에 묻힌다 — 흰 글자 + 밑줄로 그린다.
enum ChatMarkdownText {
    /// 꾸밈 없는 본문 크기(pt). 말풍선이 원래 쓰던 `.caption` 의 맥 크기(10)다 — 기호가 없는 메시지는 예전과 **같은 크기**여야 한다.
    static let baseSize: CGFloat = 10

    /// 줄 종류별 글자 크기(pt). 제목은 단계마다 커지고 `##` 는 본문의 1.5배다("## 글자 로 글자 크기 키우거나").
    /// 말풍선 폭이 190pt 남짓이라 `#` 를 이보다 키우면 한글 열 자 남짓에서 접힌다.
    static func fontSize(for kind: ChatMarkdownLineKind) -> CGFloat {
        switch kind {
        case .heading(let level):
            switch level {
            case 1: return 17
            case 2: return 15
            default: return 13
            }
        case .codeLabel:
            return 9
        default:
            return baseSize
        }
    }

    /// 본문 → 말풍선에 그릴 글자. **이모티콘 폴백은 부르는 쪽이 먼저 거친다**(`AingStickerText.preview` → 여기).
    static func attributed(_ body: String, isMine: Bool) -> AttributedString {
        let palette = Palette(isMine: isMine)
        var result = AttributedString()
        for (index, line) in ChatMarkdown.parse(body).enumerated() {
            if index > 0 { result += piece("\n", size: baseSize) }
            result += render(line, palette)
        }
        return result
    }

    /// 링크 색(`.tint` 와 조각 색 둘 다 이 값). 내 말풍선 바탕이 강조색이라 거기서는 흰색이다.
    static func linkColor(isMine: Bool) -> Color { Palette(isMine: isMine).link }

    /// 말풍선 링크를 여는 문. 해석이 이미 http·https 만 링크로 만들지만, **여는 자리에서 한 번 더** 본다.
    static func openAction(_ url: URL) -> OpenURLAction.Result {
        ChatMarkdown.isOpenable(url) ? .systemAction : .discarded
    }

    // MARK: 줄 · 조각

    private static func render(_ line: ChatMarkdownLine, _ palette: Palette) -> AttributedString {
        let size = fontSize(for: line.kind)
        var out = AttributedString()
        switch line.kind {
        case .bullet:
            out += piece(line.lead + "• ", size: size, color: palette.marker)
        case .ordered:
            out += piece(line.lead, size: size, color: palette.marker)
        case .quote:
            out += piece("▍ ", size: size, color: palette.marker)
        default:
            break
        }
        for span in line.spans {
            out += render(span, in: line.kind, size: size, palette)
        }
        return out
    }

    private static func render(
        _ span: ChatMarkdownSpan,
        in kind: ChatMarkdownLineKind,
        size: CGFloat,
        _ palette: Palette
    ) -> AttributedString {
        var text = AttributedString(span.text)
        text.font = font(size: size, kind: kind, style: span.style)
        switch kind {
        case .quote:
            text.foregroundColor = palette.quote
        case .codeLabel:
            text.foregroundColor = palette.marker
        default:
            break
        }
        if span.style.contains(.code) {
            text.backgroundColor = palette.codeBackground
        }
        if span.style.contains(.strikethrough) {
            text.strikethroughStyle = Text.LineStyle.single
        }
        if let link = span.link {
            text.link = link
            text.foregroundColor = palette.link
            text.underlineStyle = Text.LineStyle.single
        }
        return text
    }

    /// 조각 글꼴. 제목 줄은 언제나 굵다. 고정폭은 코드 조각·코드 블록·꼬리표.
    static func font(size: CGFloat, kind: ChatMarkdownLineKind, style: ChatMarkdownStyle) -> Font {
        let isHeading: Bool
        if case .heading = kind { isHeading = true } else { isHeading = false }
        let monospaced = style.contains(.code) || kind == .code || kind == .codeLabel
        var font = Font.system(
            size: size,
            weight: isHeading || style.contains(.bold) ? .bold : .regular,
            design: monospaced ? .monospaced : .default
        )
        if style.contains(.italic) { font = font.italic() }
        return font
    }

    private static func piece(_ string: String, size: CGFloat, color: Color? = nil) -> AttributedString {
        var text = AttributedString(string)
        text.font = Font.system(size: size)
        if let color { text.foregroundColor = color }
        return text
    }

    /// 말풍선 바탕별 색. 받은 말풍선은 어두운 반투명 바탕, 내 말풍선은 강조색 바탕이다(`MessageBubbleRow.textBubble`).
    private struct Palette {
        let link: Color
        let marker: Color
        let quote: Color
        let codeBackground: Color

        init(isMine: Bool) {
            link = isMine ? .white : CheckTheme.accent
            marker = isMine ? Color.white.opacity(0.75) : CheckTheme.secondaryText
            quote = isMine ? Color.white.opacity(0.85) : CheckTheme.secondaryText
            codeBackground = isMine ? Color.black.opacity(0.18) : Color.white.opacity(0.10)
        }
    }
}
