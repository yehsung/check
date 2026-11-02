import AppKit
import SwiftUI
import CheckCore

// MARK: - 말풍선 마크다운 그리기 (대표 요청 2026-11-03 ③④ · 범위는 대표 결정 "제목·굵게·링크만")
//
// 해석은 `ChatMarkdown`(CheckCore — 순수 함수)이 하고, 여기는 그 줄들을 **그릴 조각 목록 하나**(`pieces`)로 옮긴다.
// 그 목록을 두 그리기가 같이 쓴다:
//   · `nsAttributed` — **앱이 그리는 쪽**. 말풍선 본문은 고를 수 있는 AppKit 글자 뷰다(`ChatBubbleTextView` — 대표 결정
//     "받은 말풍선도 드래그, 우클릭에 신고 유지"). AppKit 은 SwiftUI 의 `Font` 를 못 읽으므로 NSFont 로 따로 짓는다.
//   · `attributed` — SwiftUI `Text` 가 그리는 쪽. **렌더 시험·스냅샷 전용 대체 경로**다(`ImageRenderer` 는 NSView 를 못 그린다 —
//     `CheckMessageView` 머리 주석의 "ImageRenderer 눈가리개").
// 글자·크기·굵기·링크를 두 곳에서 따로 정하면 언젠가 갈린다 — 스냅샷이 보여 주는 것과 앱이 그리는 것이 달라진다. 그래서 정하는 곳은
// `pieces` 하나이고, 두 함수는 옮겨 적기만 한다(ChatBubbleSelectionTests 가 둘을 글자·크기·굵기·링크·색으로 맞춰 본다).
// 말풍선과 틀 높이 추정(`MessagePanelLayout.textBubbleHeight`)이 이 파일의 크기 표를 같이 쓴다.
// 그리는 꾸밈은 셋뿐이다: 제목 크기 · 굵게 · 링크(밑줄 + 색 + 호스트 꼬리표). 나머지 문법은 해석이 글자 그대로 넘긴다.
//
// ## 왜 한 장인가 — 줄마다 뷰를 세우지 않는 이유
//  · 말풍선의 글자 선택은 글자 뷰 **하나 안에서만** 이어진다. 줄마다 뷰를 세우면 드래그가 줄 끝에서 끊긴다.
//  · 해석이 원문 한 줄을 한 줄로 돌려주므로(`ChatMarkdown` 규약 ②) 줄 사이에 "\n" 하나씩만 넣으면 ⇧↩ 줄바꿈이 그대로 산다.
//
// ## 글꼴은 조각마다 **명시**한다
// 굵게를 `inlinePresentationIntent` 로 맡기면 제목 줄의 큰 글꼴과 어떻게 합쳐지는지가 SwiftUI 안쪽 동작이 된다.
// 크기·굵기를 조각마다 직접 정해 두면 "제목이 몇 pt 인가"가 이 표 하나로 정해지고, 틀 높이 추정도 같은 표를 읽는다.
//
// ## 링크
// 앱 쪽은 글자 뷰가 링크 누름을 받아 `ChatMarkdown.isOpenable` 을 **여는 자리에서 한 번 더** 본 뒤 기본 브라우저로 연다
// (`ChatBubbleTextView.followLink`). SwiftUI 쪽은 환경의 `openURL` 앞에 같은 검사를 세운다(`openAction`).
// 링크 색은 말풍선 바탕을 따른다: 내 말풍선은 **강조색(파랑) 바탕**이라 강조색 링크가 바탕에 묻힌다 — 흰 글자 + 밑줄로 그린다.
enum ChatMarkdownText {
    /// 꾸밈 없는 본문 크기(pt). 말풍선이 원래 쓰던 `.caption` 의 맥 크기(10)다 — 기호가 없는 메시지는 예전과 **같은 크기**여야 한다.
    static let baseSize: CGFloat = 10

    /// 줄 종류별 글자 크기(pt). 제목은 단계마다 커지고 `##` 는 본문의 1.5배다("## 글자 로 글자 크기 키우거나").
    /// 말풍선 폭이 190pt 남짓이라 `#` 를 이보다 키우면 한글 열 자 남짓에서 접힌다.
    static func fontSize(for kind: ChatMarkdownLineKind) -> CGFloat {
        guard case .heading(let level) = kind else { return baseSize }
        switch level {
        case 1: return 17
        case 2: return 15
        default: return 13
        }
    }

    // MARK: 그릴 조각 — 두 그리기가 같이 옮겨 적는 목록

    /// 말풍선이 그리는 조각 하나. 이어 붙이면 말풍선에 보이는 글자 전부다.
    struct Piece: Equatable {
        enum Kind: Equatable {
            /// 해석 조각(본문 · 굵게 · 링크).
            case span
            /// 줄 사이 "\n".
            case lineBreak
            /// `[글](주소)` 뒤에 붙이는 실제 호스트 " (호스트)" — 링크가 아니다(누르는 자리는 글 그대로다).
            case disclosure
        }

        let kind: Kind
        let text: String
        let size: CGFloat
        /// 굵게 그리는가. 제목 줄의 조각은 언제나 굵다.
        let isBold: Bool
        let link: URL?
    }

    /// 본문 → 그릴 조각들. **이모티콘 폴백은 부르는 쪽이 먼저 거친다**(`AingStickerText.preview` → 여기).
    static func pieces(_ body: String) -> [Piece] {
        var out: [Piece] = []
        for (index, line) in ChatMarkdown.parse(body).enumerated() {
            if index > 0 { out.append(Piece(kind: .lineBreak, text: "\n", size: baseSize, isBold: false, link: nil)) }
            let size = fontSize(for: line.kind)
            let isHeading: Bool
            if case .heading = line.kind { isHeading = true } else { isHeading = false }
            // `[글](주소)` 는 글 뒤에 실제 호스트를 작게 붙인다(`ChatMarkdown.linkDisclosures` — 보이는 글과 여는 곳이 다른 링크).
            let disclosures = ChatMarkdown.linkDisclosures(line)
            for (spanIndex, span) in line.spans.enumerated() {
                out.append(Piece(kind: .span, text: span.text, size: size, isBold: isHeading || span.isBold, link: span.link))
                if let host = disclosures[spanIndex] {
                    out.append(Piece(kind: .disclosure, text: " (\(host))", size: size, isBold: false, link: nil))
                }
            }
        }
        return out
    }

    /// 한 줄에 그리는 쪽이 **덧붙이는** 글자 수(호스트 꼬리표). 말풍선 높이 추정이 같은 글자로 세게 한다.
    static func addedCharacters(_ line: ChatMarkdownLine) -> Int {
        ChatMarkdown.linkDisclosures(line).values.reduce(0) { $0 + $1.count + 3 }
    }

    // MARK: SwiftUI — 렌더 시험·스냅샷 대체 경로

    /// 본문 → SwiftUI `Text` 에 그릴 글자. 앱의 말풍선은 이것이 아니라 `nsAttributed` 를 그린다(파일 머리 주석).
    static func attributed(_ body: String, isMine: Bool) -> AttributedString {
        let palette = Palette(isMine: isMine)
        var result = AttributedString()
        for piece in pieces(body) {
            var text = AttributedString(piece.text)
            switch piece.kind {
            case .span:
                text.font = Font.system(size: piece.size, weight: piece.isBold ? .bold : .regular)
                if let link = piece.link {
                    text.link = link
                    text.foregroundColor = palette.link
                    text.underlineStyle = Text.LineStyle.single
                }
            case .lineBreak:
                text.font = Font.system(size: piece.size)
            case .disclosure:
                text.font = Font.system(size: piece.size)
                text.foregroundColor = palette.disclosure
            }
            result += text
        }
        return result
    }

    /// 링크 색(`.tint` 와 조각 색 둘 다 이 값). 내 말풍선 바탕이 강조색이라 거기서는 흰색이다.
    static func linkColor(isMine: Bool) -> Color { Palette(isMine: isMine).link }

    /// 말풍선 링크를 여는 문(SwiftUI 대체 경로). 해석이 이미 http·https 만 링크로 만들지만, **여는 자리에서 한 번 더** 본다.
    static func openAction(_ url: URL) -> OpenURLAction.Result {
        ChatMarkdown.isOpenable(url) ? .systemAction : .discarded
    }

    // MARK: AppKit — 앱이 그리는 말풍선 본문

    /// 본문 → 앱 말풍선(`ChatBubbleTextView`)에 그릴 글자. `attributed` 와 **같은 조각 목록**을 옮긴다 — 글자·크기·굵기·링크가 같다.
    ///
    /// SwiftUI 쪽은 본문 색을 `Text` 의 `.foregroundStyle` 이 칠하지만, AppKit 글자 뷰에는 그 수식어가 없으므로 조각마다 색을 박는다
    /// (`textColor` 를 뷰에 주면 꼬리표 색까지 덮는다).
    static func nsAttributed(_ body: String, isMine: Bool) -> NSAttributedString {
        let palette = AppKitPalette(isMine: isMine)
        let paragraph = paragraphStyle
        let result = NSMutableAttributedString()
        for piece in pieces(body) {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: nsFont(size: piece.size, isBold: piece.isBold),
                .foregroundColor: palette.text,
                .paragraphStyle: paragraph,
            ]
            switch piece.kind {
            case .span:
                if let link = piece.link {
                    attributes[.link] = link
                    attributes[.foregroundColor] = palette.link
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
            case .lineBreak:
                break
            case .disclosure:
                attributes[.foregroundColor] = palette.disclosure
            }
            result.append(NSAttributedString(string: piece.text, attributes: attributes))
        }
        return result
    }

    /// AppKit 조각 글꼴. SwiftUI `Font.system(size:weight:)` 와 같은 시스템 글꼴이다.
    static func nsFont(size: CGFloat, isBold: Bool) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: isBold ? .bold : .regular)
    }

    /// 글자 뷰가 링크 구간에 덮어 그리는 속성. NSTextView 는 링크 구간의 색·밑줄을 조각 속성이 아니라 **이 값으로** 그린다 —
    /// 기본값(시스템 링크 파랑)으로 두면 파란 내 말풍선에서 링크가 바탕에 묻힌다.
    static func nsLinkAttributes(isMine: Bool) -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: AppKitPalette(isMine: isMine).link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
    }

    /// 고른 영역 강조색. **시스템 기본 강조(파랑 계열)는 파란 내 말풍선에서 안 보인다** — 내 말풍선은 바탕을 한 단 어둡게,
    /// 받은 말풍선(어두운 반투명 바탕)은 강조색을 반쯤 깐다. 글자색은 바꾸지 않는다(흰 글자가 두 강조 위에서 다 읽힌다).
    static func nsSelectionColor(isMine: Bool) -> NSColor {
        isMine ? NSColor.black.withAlphaComponent(0.32) : NSColor(CheckTheme.accent).withAlphaComponent(0.45)
    }

    /// 본문 기본 속성 — 글자 뷰의 `typingAttributes`(끝 줄바꿈 뒤 빈 줄의 높이가 이 글꼴로 정해진다).
    static func nsBaseAttributes(isMine: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: nsFont(size: baseSize, isBold: false),
            .foregroundColor: AppKitPalette(isMine: isMine).text,
            .paragraphStyle: paragraphStyle,
        ]
    }

    /// 줄 접기 규칙. `.standard` 는 SwiftUI `Text` 가 쓰는 규칙(한글은 낱말 단위로 접는다)이다 — AppKit 기본값(빈 규칙)으로 두면
    /// 한글이 글자 단위로 접혀 같은 본문의 줄 수·말풍선 폭이 스냅샷과 달라진다.
    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .natural
        style.lineBreakStrategy = .standard
        return style
    }

    // MARK: 색

    /// 말풍선 바탕별 색. 받은 말풍선은 어두운 반투명 바탕, 내 말풍선은 강조색 바탕이다(`MessageBubbleRow.textBubble`).
    private struct Palette {
        let link: Color
        /// 링크 호스트 꼬리표 색 — 본문보다 한 단 흐리다(읽으라고 있는 글자이지 누르는 자리가 아니다).
        let disclosure: Color

        init(isMine: Bool) {
            link = isMine ? .white : CheckTheme.accent
            disclosure = isMine ? Color.white.opacity(0.75) : CheckTheme.secondaryText
        }
    }

    /// `Palette` 를 AppKit 색으로 옮긴 것 + 본문 색(SwiftUI 쪽에서 `.foregroundStyle` 이 칠하던 그 값).
    /// 색을 새로 고르지 않고 **같은 SwiftUI 색을 변환**한다 — 두 그리기의 색이 갈릴 길을 없앤다.
    struct AppKitPalette {
        let text: NSColor
        let link: NSColor
        let disclosure: NSColor

        init(isMine: Bool) {
            let palette = Palette(isMine: isMine)
            text = NSColor(ChatMarkdownText.bodyColor(isMine: isMine))
            link = NSColor(palette.link)
            disclosure = NSColor(palette.disclosure)
        }
    }

    /// 본문 글자색. 내 말풍선(강조색 바탕)은 흰색, 받은 말풍선은 기본 글자색이다.
    static func bodyColor(isMine: Bool) -> Color { isMine ? .white : CheckTheme.primaryText }
}
