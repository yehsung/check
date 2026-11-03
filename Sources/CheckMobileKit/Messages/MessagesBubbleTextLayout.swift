#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 말풍선 본문의 **한글 어절 단위 줄바꿈**(시안 B 04 — "10분만 / 가능할까요?").
///
/// 실측(iOS 26.5 시뮬레이터 · ko-KR):
/// - SwiftUI `Text` 는 한글을 음절 사이에서 끊는다("10분만 가능 / 할까요?"). `typesettingLanguage(ko)` 로도 안 바뀐다.
/// - 음절 사이에 단어 잇기 문자(U+2060)를 넣어도 SwiftUI 조판은 듣지 않았고 오히려 "봤어요 / !"로 끊었다.
/// - `UILabel` 은 `lineBreakStrategy = .hangulWordPriority`(라벨 속성 · 문단 스타일 둘 다)를 줘도 음절에서 끊었다.
/// - TextKit(`NSLayoutManager`)은 문단 스타일의 전략을 지킨다 — 그래서 말풍선 본문은 TextKit 으로 재고 그린다
///   (`MessagesBubbleTextUIView`). 이 파일의 재기·줄 나누기는 맥에서도 같은 API 라 `swift test` 가 잰다.
///
/// 전략은 **`hangulWordPriority` 하나만** 쓴다. `.standard` 를 섞으면 그 안의 `pushOut`(마지막 줄 외톨이 막기)이
/// "오후에 디자인 리뷰 10 / 분만 가능할까요?"처럼 숫자와 한글 사이를 끊었다(TextKit 실측 · 폭 180~240pt 모두).
/// `hangulWordPriority` 는 **한글과 한글 사이**만 막는다 — "봤어요! 2 / 번이"처럼 숫자·기호와 한글 사이는 여전히 끊겨서,
/// 배치 대리자가 "한글이 든 어절 안"의 끊기를 한 번 더 거른다(`allowsWordBreak`). 폭보다 긴 어절은 TextKit 이 글자 단위로 접는다.
///
/// 1.0.17: 글은 서식(제목 · 굵게 · 링크 — `MessagesBubbleMarkdown.attributed`)째 들어온다. 글꼴이 섞여도 재기 · 줄바꿈은 이 엔진 그대로이고,
/// 링크 누름 판정(`Engine.link(at:width:)`)도 그린 배치 그대로 잰다.
package enum MessagesBubbleTextLayout {
    package static let lineBreakStrategy: NSParagraphStyle.LineBreakStrategy = [.hangulWordPriority]

    package static func paragraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineBreakStrategy = lineBreakStrategy
        return paragraph
    }

    /// `index` 글자 **앞**에서 줄을 끊어도 되는가(단어 단위 끊기 후보를 거른다).
    /// 앞 글자가 공백·줄바꿈이면 된다. 아니면 그 자리를 둘러싼 어절(공백 사이)에 한글이 있으면 안 된다 — 어절 안에서 끊지 않는다.
    /// 한글이 없는 어절(링크·영문)은 시스템 판단 그대로(슬래시 뒤 등).
    package static func allowsWordBreak(before index: Int, in text: NSString) -> Bool {
        guard index > 0, index < text.length else { return true }
        if isSpace(text.character(at: index - 1)) { return true }
        var start = index
        while start > 0, !isSpace(text.character(at: start - 1)) { start -= 1 }
        var end = index
        while end < text.length, !isSpace(text.character(at: end)) { end += 1 }
        for offset in start..<end where isHangul(text.character(at: offset)) {
            return false
        }
        return true
    }

    static func isSpace(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    /// 한글 음절 · 자모(호환 자모 포함). 모두 BMP 라 UTF-16 한 단위로 본다.
    static func isHangul(_ unit: unichar) -> Bool {
        switch unit {
        case 0xAC00...0xD7A3, 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xD7B0...0xD7FF: true
        default: false
        }
    }

    /// TextKit 한 벌(글 · 배치 · 틀 · 끊기 대리자). 말풍선 뷰가 하나씩 들고 재기·그리기에 같이 쓴다.
    package final class Engine: NSObject, NSLayoutManagerDelegate {
        package let storage = NSTextStorage()
        package let layoutManager = NSLayoutManager()
        package let container = NSTextContainer(size: .zero)

        override package init() {
            super.init()
            container.lineFragmentPadding = 0
            container.lineBreakMode = .byWordWrapping
            layoutManager.addTextContainer(container)
            layoutManager.delegate = self
            storage.addLayoutManager(layoutManager)
        }

        package func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
            MessagesBubbleTextLayout.allowsWordBreak(before: charIndex, in: storage.string as NSString)
        }

        /// 글을 바꿨는가(같으면 false — 다시 그릴 필요 없음).
        @discardableResult
        package func set(_ attributed: NSAttributedString) -> Bool {
            guard !storage.isEqual(to: attributed) else { return false }
            storage.setAttributedString(attributed)
            return true
        }

        /// 폭 `width` 안에 배치했을 때 글이 차지하는 크기(올림). 한 줄이면 그 줄 폭 — 말풍선이 글에 맞게 줄어든다.
        package func fittingSize(width: CGFloat) -> CGSize {
            layout(width: width)
            let used = layoutManager.usedRect(for: container)
            return CGSize(width: min(ceil(used.width), width), height: ceil(used.height))
        }

        /// 폭 `width` 에서 줄마다 끊긴 글(테스트 · 진단용).
        package func lines(width: CGFloat) -> [String] {
            layout(width: width)
            let text = storage.string as NSString
            var result: [String] = []
            layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: container)) { _, _, _, glyphs, _ in
                let characters = self.layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                result.append(text.substring(with: characters))
            }
            return result
        }

        package func layout(width: CGFloat) {
            let size = CGSize(width: max(width, 1), height: .greatestFiniteMagnitude)
            if container.size != size { container.size = size }
            layoutManager.ensureLayout(for: container)
        }

        /// 손가락 오차(pt). 링크 글자 상자를 이만큼 넓혀 본다 — 줄 끝 너머 멀리 · 빈 곳은 여전히 아니다.
        package static let touchSlop: CGFloat = 4

        /// 폭 `width` 로 배치한 글에서 `point`(글 칸 좌표 — 말풍선 본문 뷰가 그리는 자리 그대로)를 누르면 열 링크.
        /// 판정: 링크 구간마다 **줄 조각별 글자 상자**(`boundingRect` — 그 줄에 놓인 링크 글자만 감싼다)를 구해 `touchSlop` 만큼 넓혀 본다.
        /// 상자 안에 바로 든 링크가 먼저이고, 없으면 넓힌 상자에 든 것 가운데 가장 가까운 링크다.
        /// 링크 위가 아니면 nil — 호스트 꼬리표(링크가 아니다) · 평범한 글자 · 줄 끝 너머 · 글 아래 빈 곳.
        /// 여는 것은 이 값이 아니라 `MessagesBubbleMarkdown.follow` 를 지난 값이다(스킴 검사 두 겹).
        ///
        /// ★ "가장 가까운 글자 하나의 상자 + 오차"로 재던 첫 판(2026-11-03 검토 minor)은 링크 옆에 다른 글리프가 있으면 오차가 듣지 않았다 —
        ///   링크 뒤 줄바꿈 글리프(상자가 칸 끝까지 이어진다) · 꼬리표 앞 공백이 가장 가까운 글자가 되어, 링크 끝 바로 옆을 눌러도 nil 이었다.
        package func link(at point: CGPoint, width: CGFloat) -> URL? {
            layout(width: width)
            guard storage.length > 0, layoutManager.numberOfGlyphs > 0 else { return nil }
            var nearest: (url: URL, distance: CGFloat)?
            let whole = NSRange(location: 0, length: storage.length)
            storage.enumerateAttribute(MessagesBubbleMarkdown.linkKey, in: whole) { value, range, stop in
                guard let url = value as? URL else { return }
                for box in linkBoxes(characterRange: range) {
                    if box.contains(point) {
                        nearest = (url, 0)
                        stop.pointee = true
                        return
                    }
                    guard box.insetBy(dx: -Self.touchSlop, dy: -Self.touchSlop).contains(point) else { continue }
                    let dx = max(box.minX - point.x, 0, point.x - box.maxX)
                    let dy = max(box.minY - point.y, 0, point.y - box.maxY)
                    let distance = (dx * dx + dy * dy).squareRoot()
                    if distance < (nearest?.distance ?? .greatestFiniteMagnitude) { nearest = (url, distance) }
                }
            }
            return nearest?.url
        }

        /// 링크 한 구간의 줄 조각별 글자 상자(여러 줄로 접히면 줄마다 하나). 빈 상자는 뺀다.
        private func linkBoxes(characterRange: NSRange) -> [CGRect] {
            let glyphs = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return [] }
            var boxes: [CGRect] = []
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, lineGlyphs, _ in
                let part = NSIntersectionRange(glyphs, lineGlyphs)
                guard part.length > 0 else { return }
                let box = self.layoutManager.boundingRect(forGlyphRange: part, in: self.container)
                if !box.isEmpty { boxes.append(box) }
            }
            return boxes
        }
    }
}
