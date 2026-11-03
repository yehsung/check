#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import CheckCore
import Foundation
import SwiftUI

// MARK: - 폰 말풍선 서식 (1.0.17 · 맥 0.3.74 대표 요청 2026-11-03 ③④의 폰 짝 · 범위는 대표 결정 "제목·굵게·링크만")
//
// 무엇을 그리는가(글자 · 제목 단계 · 굵게 · 링크 · 호스트 꼬리표 · 복사 표시)는 코어 `ChatMarkdownPieces` 한 곳이 정한다 — 맥 말풍선과 한 벌이다.
// 여기는 그 조각에 **폰 글꼴과 색**을 입혀 TextKit 글 한 장(`NSAttributedString`)으로 옮긴다. 그 글을 말풍선 본문 뷰
// (`MessagesBubbleTextUIView` — 한글 어절 줄바꿈 때문에 SwiftUI `Text` 가 아니라 TextKit 으로 직접 그린다)가 그대로 그린다.
//
// 이 파일은 UIKit · AppKit 양쪽에서 컴파일된다(`MessagesBubbleTextLayout` 과 같은 까닭) — 맥 `swift test` 가 NSFont 로 글꼴을 넣어
// 글자 · 크기 · 굵기 · 링크 · 색 · 누름 판정 · 복사 글을 잰다. 폰 글꼴을 짓는 자리(Dynamic Type)만 iOS 전용이다(맨 아래).
//
// ## 링크는 직접 정한 키로 싣는다 — `.link` 를 쓰지 않는다
// TextKit 1 은 `.link` 속성 글자를 시스템 링크 색으로 덮어 그릴 수 있다(받은 말풍선 · 파란 내 말풍선 모두 우리 색이 아니게 된다).
// 그래서 링크 주소는 `linkKey` 에 싣고, 색 · 밑줄은 글자 속성으로 **직접 박는다**. 누름은 말풍선 뷰가 `Engine.link(at:width:)` 로 판정한다.
//
// ## 색 — 모든 글자 4.5:1 (MobileThemePalette 머리 규칙)
//  · 받은 말풍선(bubbleIn): 본문 label · 링크 accent(밑줄) · 꼬리표 label2.
//  · 내 말풍선(accentFill): 본문 · 링크 · 꼬리표 모두 onAccentFill(흰색) — 링크는 밑줄로 가른다. 맥은 꼬리표를 흰색 75% 로 흐리지만
//    폰 다크 accentFill 위 흰색은 꽉 찬 흰색이 겨우 4.5:1 이라 조금만 흐려도 무너진다(75% 3.2:1 · 90% 4.0:1 — 계산은 시험이 잰다).
package enum MessagesBubbleMarkdown {
    #if canImport(UIKit)
    package typealias PlatformFont = UIFont
    package typealias PlatformColor = UIColor
    #else
    package typealias PlatformFont = NSFont
    package typealias PlatformColor = NSColor
    #endif

    /// 링크 글자의 주소(값: URL). 말풍선 뷰의 누름 판정과 보이스오버 동작이 이 값을 연다(`follow` 를 지나서).
    package static let linkKey = NSAttributedString.Key("check.bubble.link")

    // MARK: 글꼴 · 색

    /// 단계별 글꼴. 단계 0 = 본문, 1 = `#`, 2 = `##`, 3 = `###` 이하(`ChatMarkdownPiece.headingStep`).
    package struct Fonts {
        package var regular: [PlatformFont]
        package var bold: [PlatformFont]

        /// `regular` · `bold` 는 단계 0~3 넷씩이다(모자라면 마지막 단계로 접는다).
        package init(regular: [PlatformFont], bold: [PlatformFont]) {
            precondition(!regular.isEmpty && regular.count == bold.count, "단계별 글꼴 짝이 안 맞는다")
            self.regular = regular
            self.bold = bold
        }

        /// 시스템 글꼴 크기 표(단계 0~3, pt)로 짓는다. 시험과 iOS 의 제목 글꼴이 쓴다.
        package static func system(sizes: [CGFloat]) -> Fonts {
            Fonts(
                regular: sizes.map { PlatformFont.systemFont(ofSize: $0, weight: .regular) },
                bold: sizes.map { PlatformFont.systemFont(ofSize: $0, weight: .bold) }
            )
        }

        package func font(step: Int, isBold: Bool) -> PlatformFont {
            let index = min(max(step, 0), regular.count - 1)
            return isBold ? bold[index] : regular[index]
        }

        /// 조각 → 글꼴. 꼬리표는 그 줄 크기의 보통 굵기, 줄 사이 "\n" 은 본문이다(맥 `ChatMarkdownText.Piece` 와 같은 표).
        package func font(for piece: ChatMarkdownPiece) -> PlatformFont {
            switch piece.kind {
            case .span: font(step: piece.headingStep, isBold: piece.isBold)
            case .lineBreak: font(step: 0, isBold: false)
            case .disclosure: font(step: piece.headingStep, isBold: false)
            }
        }
    }

    /// 말풍선 바탕별 색 토큰(외관별 쌍). 색 객체는 부르는 쪽이 짓는다(iOS `MobileTheme.uiColor` · 시험은 아무 색).
    package struct Palette: Equatable {
        package let text: MobileThemePalette.Pair
        package let link: MobileThemePalette.Pair
        package let disclosure: MobileThemePalette.Pair
        /// 이 글자들이 놓이는 말풍선 바탕(대비 시험이 잰다).
        package let bubble: MobileThemePalette.Pair

        package static func of(isMine: Bool) -> Palette {
            isMine
                ? Palette(text: MobileThemePalette.onAccentFill, link: MobileThemePalette.onAccentFill,
                          disclosure: MobileThemePalette.onAccentFill, bubble: MobileThemePalette.accentFill)
                : Palette(text: MobileThemePalette.label, link: MobileThemePalette.accent,
                          disclosure: MobileThemePalette.label2, bubble: MobileThemePalette.bubbleIn)
        }
    }

    /// 실제 색 객체 셋.
    package struct Colors {
        package var text: PlatformColor
        package var link: PlatformColor
        package var disclosure: PlatformColor

        package init(text: PlatformColor, link: PlatformColor, disclosure: PlatformColor) {
            self.text = text
            self.link = link
            self.disclosure = disclosure
        }
    }

    // MARK: 글 한 장

    /// 말풍선에 보일 글(`shown` — **이모티콘 폴백을 이미 지난** 본문, `AingStickerText.preview`) → TextKit 글 한 장.
    ///
    /// · 조각마다 글꼴 · 색을 **명시**한다(뷰에 기본 글꼴 · 색이 없다 — TextKit 이 그리는 것은 이 속성뿐이다).
    /// · 문단 스타일은 어절 줄바꿈(`MessagesBubbleTextLayout.paragraphStyle()`) 하나다 — 서식이 생겨도 줄바꿈 규칙은 그대로다.
    /// · 링크 글자: `linkKey`(주소) + 링크 색 + 밑줄. 꼬리표 " (호스트)": 꼬리표 색 · 밑줄 없음 · 누름 없음.
    /// · 복사 표시(`ChatMarkdownCopy.linkKey` · `disclosureKey`)를 맥 말풍선과 같은 자리에 싣는다 — 고른 글을 복사할 때
    ///   `ChatMarkdownCopy.text` 가 꼬리표 대신 실제 주소를 담는다(폰 '골라 복사'는 다음 판 — 그때 이 글을 그대로 쓴다).
    package static func attributed(_ shown: String, fonts: Fonts, colors: Colors) -> NSAttributedString {
        let paragraph = MessagesBubbleTextLayout.paragraphStyle()
        let pieces = ChatMarkdownPieces.pieces(shown)
        let copyLinks = ChatMarkdownPieces.copyLinks(pieces)
        let result = NSMutableAttributedString()
        for (index, piece) in pieces.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: fonts.font(for: piece),
                .foregroundColor: colors.text,
                .paragraphStyle: paragraph,
            ]
            if let url = copyLinks[index] { attributes[ChatMarkdownCopy.linkKey] = url }
            switch piece.kind {
            case .span:
                if let link = piece.link {
                    attributes[linkKey] = link
                    attributes[.foregroundColor] = colors.link
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
            case .lineBreak:
                break
            case .disclosure:
                attributes[ChatMarkdownCopy.disclosureKey] = true
                attributes[.foregroundColor] = colors.disclosure
            }
            result.append(NSAttributedString(string: piece.text, attributes: attributes))
        }
        return result
    }

    // MARK: 제목 크기 — 큰 글자 설정에서 상한

    /// 제목 단계(1~3)의 Dynamic Type 글자 스타일. 맥 배율(1.7 · 1.5 · 1.3)은 폰 말풍선 폭에서 너무 커서 시스템 스타일 셋을 쓴다
    /// (기본 크기 기준 본문 callout 16 → title2 22 · title3 20 · headline 17).
    package static let headingTextStyles: [PlatformFont.TextStyle] = [.title2, .title3, .headline]

    /// 제목 글꼴은 이 크기 설정에서 더 자라지 않는다. 본문은 계속 자란다 — 큰 글자(AX2 이상)에서 제목이 본문보다 작아지면
    /// 본문 크기의 굵은 글자가 된다(`headingPointSize`). 그래야 AX5 에서 `#` 한 줄이 말풍선 폭을 몇 글자로 쪼개지 않는다.
    package static let headingSizeCap: DynamicTypeSize = .accessibility1

    /// 제목에 쓸 크기 설정 — 지금 설정과 상한 중 작은 쪽.
    package static func headingDynamicTypeSize(_ size: DynamicTypeSize) -> DynamicTypeSize {
        min(size, headingSizeCap)
    }

    /// 제목 한 단계의 크기(pt): 그 스타일의 크기(상한 설정에서 잰 것)이되 **본문보다 작지 않다**.
    package static func headingPointSize(styleSize: CGFloat, bodySize: CGFloat) -> CGFloat {
        max(styleSize, bodySize)
    }

    // MARK: 링크 — 여는 문 · 보이스오버 동작

    /// 링크를 여는 문. **여는 자리에서 `ChatMarkdown.isOpenable` 을 한 번 더 본다** — 해석이 이미 http·https 만 링크로 만들지만,
    /// 이 문을 지나는 값은 글자 속성에서 온 것이라 해석 밖의 길이 생겨도 여기서 막힌다(맥 `ChatBubbleTextView.followLink` 와 같은 두 겹).
    /// 열었으면 true.
    @discardableResult
    package static func follow(_ url: URL, open: (URL) -> Void) -> Bool {
        guard ChatMarkdown.isOpenable(url) else { return false }
        open(url)
        return true
    }

    /// 보이스오버 동작 하나(말풍선 줄은 요소 하나라 링크 글자에 닿을 수 없다 — 링크마다 동작을 단다).
    package struct LinkAction: Hashable, Sendable {
        package let url: URL
        /// "링크 열기: 자료 (a.example)" — 화면에 보이는 링크 글 + 꼬리표 그대로다(여는 곳이 글과 다르면 이름에 호스트가 든다).
        package let title: String
    }

    package static let openLinkActionPrefix = "링크 열기: "

    /// 말풍선 글의 링크들 → 보이스오버 동작(보이는 차례 · 같은 글 · 같은 주소는 한 번).
    package static func linkActions(_ shown: String) -> [LinkAction] {
        let pieces = ChatMarkdownPieces.pieces(shown)
        var out: [LinkAction] = []
        var index = 0
        while index < pieces.count {
            guard pieces[index].kind == .span, let url = pieces[index].link else {
                index += 1
                continue
            }
            var end = index
            var label = ""
            while end < pieces.count, pieces[end].kind == .span, pieces[end].link == url {
                label += pieces[end].text
                end += 1
            }
            if end < pieces.count, pieces[end].kind == .disclosure { label += pieces[end].text }
            let action = LinkAction(url: url, title: openLinkActionPrefix + label.trimmingCharacters(in: .whitespaces))
            if !out.contains(action) { out.append(action) }
            index = end
        }
        return out
    }
}

#if os(iOS)
extension MessagesBubbleMarkdown {
    /// 지금 글자 크기 설정의 말풍선 글꼴. 본문은 예전 그대로 `.callout` 이고, 제목은 `headingTextStyles` 를 상한 설정에서 잰 크기다.
    static func fonts(for size: DynamicTypeSize) -> Fonts {
        func traits(_ size: DynamicTypeSize) -> UITraitCollection {
            UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
        }
        let body = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: traits(size))
        let headingTraits = traits(headingDynamicTypeSize(size))
        let headingSizes = headingTextStyles.map {
            headingPointSize(styleSize: UIFont.preferredFont(forTextStyle: $0, compatibleWith: headingTraits).pointSize, bodySize: body.pointSize)
        }
        let headings = Fonts.system(sizes: headingSizes)
        return Fonts(
            regular: [body] + headings.regular,
            bold: [UIFont.systemFont(ofSize: body.pointSize, weight: .bold)] + headings.bold
        )
    }

    /// 말풍선 바탕에 맞는 색 객체(외관별 — 라이트·다크가 바뀌면 다시 풀린다).
    static func colors(isMine: Bool) -> Colors {
        let palette = Palette.of(isMine: isMine)
        return Colors(
            text: MobileTheme.uiColor(palette.text),
            link: MobileTheme.uiColor(palette.link),
            disclosure: MobileTheme.uiColor(palette.disclosure)
        )
    }
}
#endif
