import AppKit
@testable import CheckCore
import Foundation
import SwiftUI
import Testing
@testable import CheckMobileKit

// 폰 1.0.17 — 채팅 서식 · 링크 이식. 맥 `Tests/checkTests/ChatMarkdownTests.swift` · `ChatBubbleSelectionTests.swift` 를 본으로 한 폰판이다.
//
// 대표 결정(되묻지 말 것): 서식은 "제목·굵게·링크만"(코어 `ChatMarkdown` 그대로) · 링크 뒤에 실제 도메인을 붙이고 겉과 속이 다른 주소는
// 링크로 만들지 않는다 · 링크를 누르면 브라우저로 열린다. 골라 복사는 V1017BubbleSelectionMobileTests(대표 답 "말풍선에서 바로 길게 눌러 고르기").
//
// 폰 말풍선 본문은 SwiftUI `Text` 가 아니라 TextKit 1 글 칸이다(한글 어절 줄바꿈 — 1.0.17 부터 고를 수 있는 UITextView). 그 뷰는 `#if os(iOS)` 라 맥 `swift test` 가
// 컴파일하지 않는다(메모리 '폰 뷰는 맥 스위트가 못 본다') — 그래서 이 파일은 둘로 잰다:
//  ① **값**: 뷰가 그리는 글 한 장(`MessagesBubbleMarkdown.attributed` — UIKit·AppKit 양쪽 컴파일)을 NSFont 로 지어 글자 · 크기 · 굵기 ·
//     링크 · 색 · 줄바꿈 규칙을 재고, 같은 TextKit 엔진(`MessagesBubbleTextLayout.Engine`)에 넣어 **누름 판정**을 그린 배치 그대로 잰다.
//     복사 글(코어 `ChatMarkdownCopy.text` — 맥과 한 함수)은 맥 시험 표 열세 칸을 폰 글 위에서 그대로 돌린다.
//  ② **배선**: 뷰가 그 값을 부르는지 — 주석을 걷은 소스 계약(메모리 source-contract-tests-need-comment-stripping). 블록은 중괄호로 자른다.
// 기준선을 늘 같이 둔다(메모리 comparison-baseline-must-differ): 서식을 안 지난 평문 · 보이는 글자 그대로의 복사 · 흐린 흰 꼬리표가 다르게 나와야
// 단언이 무언가를 잰다.

// MARK: - 길잡이

@MainActor
private enum CM17 {
    /// 시험 글꼴 표(단계 0~3, pt) — 폰 기본 크기(callout 16 · title2 22 · title3 20 · headline 17)와 같은 모양.
    static let sizes: [CGFloat] = [16, 22, 20, 17]
    static var fonts: MessagesBubbleMarkdown.Fonts { .system(sizes: sizes) }
    /// 구별되는 색 셋(실제 색은 iOS `MobileTheme.uiColor` — 여기서는 어느 자리에 어느 색이 가는지만 잰다).
    static var colors: MessagesBubbleMarkdown.Colors {
        MessagesBubbleMarkdown.Colors(
            text: NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1),
            link: NSColor(srgbRed: 0, green: 0.3, blue: 0.9, alpha: 1),
            disclosure: NSColor(srgbRed: 0.9, green: 0.5, blue: 0, alpha: 1)
        )
    }

    static func drawn(_ shown: String) -> NSAttributedString {
        MessagesBubbleMarkdown.attributed(shown, fonts: fonts, colors: colors)
    }

    static func engine(_ shown: String) -> MessagesBubbleTextLayout.Engine {
        let engine = MessagesBubbleTextLayout.Engine()
        engine.set(drawn(shown))
        return engine
    }

    static func isBold(_ font: NSFont?) -> Bool {
        font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    }

    /// `part` 가 그려진 글자들 가운데 하나(`at` 번째 글자 — 기본은 가운데)의 상자 가운데(글 칸 좌표).
    static func center(of part: String, in engine: MessagesBubbleTextLayout.Engine, width: CGFloat, at offset: Int? = nil) throws -> CGPoint {
        engine.layout(width: width)
        let range = (engine.storage.string as NSString).range(of: part)
        try #require(range.location != NSNotFound, "\(part) 가 글에 없다")
        let character = range.location + (offset ?? range.length / 2)
        let glyphs = engine.layoutManager.glyphRange(forCharacterRange: NSRange(location: character, length: 1), actualCharacterRange: nil)
        let box = engine.layoutManager.boundingRect(forGlyphRange: glyphs, in: engine.container)
        return CGPoint(x: box.midX, y: box.midY)
    }

    /// 주석을 걷은 소스(읽는 자리는 `IntegrationContractTests.code` 하나).
    static func code(_ relative: String) throws -> String {
        try IntegrationContractTests.code(relative)
    }

    static let conversationPath = "Sources/CheckMobileKit/Messages/MessagesConversationView.swift"
    static let markdownPath = "Sources/CheckMobileKit/Messages/MessagesBubbleMarkdown.swift"

    /// 선언 머리부터 **중괄호가 닫히는 곳까지**(글자 수로 자르는 창은 다음 블록으로 샌다 — V1012StickerViewContractTests.block 과 같은 방식).
    static func block(of marker: String, in source: String) throws -> String {
        let hit = try #require(source.range(of: marker), "대조: '\(marker)' 를 못 찾았다(이름이 바뀌었나)")
        var depth = 0
        var started = false
        var out = ""
        for character in source[hit.upperBound...] {
            if character == "{" {
                depth += 1
                started = true
            }
            if started { out.append(character) }
            if character == "}" {
                depth -= 1
                if depth == 0 { break }
            }
        }
        #expect(started, "대조: '\(marker)' 뒤에 블록이 없다")
        return out
    }

    static func count(_ needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }
}

// MARK: - ① 글 한 장 — 글자 · 크기 · 굵기 · 링크 · 색

@MainActor
@Suite("V1017ChatMarkdownAttributed")
struct V1017ChatMarkdownAttributedTests {
    /// 제목 · 굵게 · 링크가 **값으로** 그려진다: 기호가 사라지고, 제목은 단계 크기의 굵은 글꼴, 링크는 주소 키 + 링크 색 + 밑줄,
    /// 꼬리표는 꼬리표 색 · 밑줄 없음 · 링크 아님. 기준선: 서식을 안 지난 평문(1.0.16 의 그림)은 기호째 보인다.
    @Test func 제목_굵게_링크가_속성으로_그려지고_기호는_사라진다() throws {
        let body = "## 회의\n**굵게** 와 [자료](https://a.example/doc) 끝"
        let drawn = CM17.drawn(body)
        #expect(drawn.string == "회의\n굵게 와 자료 (a.example) 끝")
        // 기준선: 1.0.16 은 이 본문을 평문 한 덩어리로 그렸다 — 기호가 그대로 보였다.
        #expect(NSAttributedString(string: body).string != drawn.string)

        func attributes(of part: String) throws -> [NSAttributedString.Key: Any] {
            let range = (drawn.string as NSString).range(of: part)
            try #require(range.location != NSNotFound, "\(part) 가 없다")
            var effective = NSRange()
            let attributes = drawn.attributes(at: range.location, longestEffectiveRange: &effective, in: NSRange(location: 0, length: drawn.length))
            #expect(NSIntersectionRange(effective, range).length == range.length, "\(part) 가 한 덩어리 속성이 아니다")
            return attributes
        }

        let heading = try attributes(of: "회의")
        #expect((heading[.font] as? NSFont)?.pointSize == 20, "## 는 2단계(title3) 크기다")
        #expect(CM17.isBold(heading[.font] as? NSFont), "제목이 굵지 않다")

        let bold = try attributes(of: "굵게")
        #expect((bold[.font] as? NSFont)?.pointSize == 16 && CM17.isBold(bold[.font] as? NSFont))
        #expect(bold[MessagesBubbleMarkdown.linkKey] == nil)

        let plain = try attributes(of: " 와 ")
        #expect((plain[.font] as? NSFont)?.pointSize == 16 && !CM17.isBold(plain[.font] as? NSFont))
        #expect((plain[.foregroundColor] as? NSColor) == CM17.colors.text)

        let link = try attributes(of: "자료")
        #expect((link[MessagesBubbleMarkdown.linkKey] as? URL)?.absoluteString == "https://a.example/doc")
        #expect((link[.foregroundColor] as? NSColor) == CM17.colors.link, "링크 색을 직접 박지 않았다")
        #expect((link[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue, "링크에 밑줄이 없다")

        let disclosure = try attributes(of: " (a.example)")
        #expect((disclosure[.foregroundColor] as? NSColor) == CM17.colors.disclosure)
        #expect(disclosure[MessagesBubbleMarkdown.linkKey] == nil, "꼬리표가 링크다 — 누르는 자리는 글 그대로여야 한다")
        #expect(disclosure[.underlineStyle] == nil)
        #expect(disclosure[ChatMarkdownCopy.disclosureKey] != nil, "꼬리표 복사 표시가 없다")

        // 시스템 `.link` 속성은 어디에도 없다 — TextKit 이 링크 색을 덮어 그리지 못하게(직접 키로만 싣는다).
        drawn.enumerateAttribute(.link, in: NSRange(location: 0, length: drawn.length)) { value, _, _ in
            #expect(value == nil, "시스템 .link 속성이 실렸다")
        }
    }

    /// 제목은 세 단계로 커지고 넷째 이하는 셋째에서 멈춘다. 본문만 있는 말풍선은 1.0.16 과 같은 본문 글꼴 한 가지다.
    @Test func 제목은_단계별로_커지고_본문은_예전_그대로다() {
        func size(_ body: String) -> CGFloat? {
            (CM17.drawn(body).attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
        }
        #expect(size("# 제목") == 22 && size("## 제목") == 20 && size("### 제목") == 17)
        #expect(size("###### 제목") == 17, "#### 이하가 ### 보다 커졌다")
        #expect(size("#해시태그") == 16, "#해시태그 가 제목이 됐다")

        let plain = CM17.drawn("오후에 디자인 리뷰 10분만 가능할까요?")
        #expect(plain.string == "오후에 디자인 리뷰 10분만 가능할까요?", "평범한 본문 글자가 바뀌었다")
        var runs = 0
        plain.enumerateAttributes(in: NSRange(location: 0, length: plain.length)) { attributes, _, _ in
            runs += 1
            #expect((attributes[.font] as? NSFont)?.pointSize == 16 && !CM17.isBold(attributes[.font] as? NSFont))
        }
        #expect(runs == 1, "평범한 본문이 여러 덩어리로 갈렸다")
    }

    /// 어절 줄바꿈 규칙(문단 스타일)이 **모든 글자**에 그대로 있다 — 서식이 생겨도 "10분만 / 가능할까요?" 가 지켜진다.
    /// 원문 줄 수 = 그린 줄 수(⇧↩ · return 줄바꿈이 그대로다 — 코어 규약 ②).
    @Test func 어절_줄바꿈과_원문_줄바꿈이_그대로다() {
        let body = "# 공지\n\n**오후에** 디자인 리뷰 10분만 가능할까요?\n[자료](https://a.example)"
        let drawn = CM17.drawn(body)
        drawn.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: drawn.length)) { value, _, _ in
            #expect((value as? NSParagraphStyle)?.lineBreakStrategy == MessagesBubbleTextLayout.lineBreakStrategy, "어절 줄바꿈 규칙이 빠진 글자가 있다")
        }
        #expect(drawn.string.components(separatedBy: "\n").count == body.components(separatedBy: "\n").count)

        // 서식 글도 같은 엔진 · 같은 대리자로 끊는다 — 굵게가 섞여도 "10분만 / 가능할까요?".
        let engine = CM17.engine("**오후에** 디자인 리뷰 10분만 가능할까요?")
        for width in stride(from: 190.0, through: 230.0, by: 20.0) {
            let lines = engine.lines(width: width).map { $0.trimmingCharacters(in: .whitespaces) }
            #expect(lines.last == "가능할까요?", "폭 \(width): \(lines)")
        }
    }

    /// 열 수 없는 링크 · 주소 흉내 링크는 **링크가 아니고** 원문 그대로 보인다(코어 규칙 그대로).
    @Test func 나쁜_스킴과_주소_흉내는_링크가_아니다() {
        // 뒤 넷: 호스트를 퍼센트 인코딩한 주소(2026-11-03 검토 critical·major) — 꼬리표가 키릴 닮은꼴을 진짜처럼 보였고, 맨 주소는 다른 호스트를 열었다.
        for body in ["[나쁜](javascript:alert(1))", "[글](file:///etc/passwd)", "[https://bank.com](https://evil.com)", "https://naver.com:443@evil.com",
                     "[naver.com](https://n%D0%B0ver.com)", "[apple.com](https://%D0%B0pple.com/login)",
                     "[애플 로그인](https://%D0%B0%D1%80%D1%80%D3%8F%D0%B5.com/id)", "확인 https://naver.com%2E%65%76%69%6C%2E%63%6F%6D/login"] {
            let drawn = CM17.drawn(body)
            #expect(drawn.string == body, "\(body) 원문이 바뀌었다: \(drawn.string)")
            drawn.enumerateAttribute(MessagesBubbleMarkdown.linkKey, in: NSRange(location: 0, length: drawn.length)) { value, _, _ in
                #expect(value == nil, "\(body) 가 링크가 됐다")
            }
        }
    }

    /// 그린 글은 **코어 조각 목록을 그대로 옮긴다**(맥 말풍선과 한 벌): 글자 · 단계 크기 · 굵기 · 링크 · 색. 표 + 시드 고정 무작위 300개.
    @Test func 그린_글은_코어_조각_목록과_같다() {
        var bodies = [
            "안녕", "# 큰 제목", "## 중간 제목\n본문 **굵게** 끝", "### 작은\n\n빈 줄 뒤", "#### 넷째도 제목",
            "[여기](https://evil.example/login) 와 https://a.com/x", "**굵게**와 *기울임*과 ~~취소~~ `코드`",
            "아잉이 기쁨", "줄\n바꿈\n셋", "ㅋㅋㅋ 🎉 **축하**", "## [제목 링크](https://a.example/x) 뒤",
        ]
        let tokens = ["**", "*", "#", "## ", "[", "](", ")", "https://a.co", "가", "a", " ", "\n", "🎉", "~~", "`", "_"]
        var seed: UInt64 = 0x0001_0017_C4A7
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
        var linked = 0
        for body in bodies {
            let pieces = ChatMarkdownPieces.pieces(body)
            let drawn = CM17.drawn(body)
            #expect(drawn.string == pieces.map(\.text).joined(), "글자가 조각 목록과 다르다 — \(body.debugDescription)")
            var offset = 0
            for piece in pieces {
                let length = (piece.text as NSString).length
                guard length > 0 else { continue }
                defer { offset += length }
                let what = "\(body.debugDescription) 조각 \(piece.text.debugDescription)"
                var effective = NSRange()
                let attributes = drawn.attributes(at: offset, longestEffectiveRange: &effective, in: NSRange(location: offset, length: length))
                #expect(effective.length == length, "조각이 갈렸다: \(what)")
                let font = attributes[.font] as? NSFont
                let step = piece.kind == .lineBreak ? 0 : piece.headingStep
                #expect(font?.pointSize == CM17.sizes[step], "크기: \(what)")
                #expect(CM17.isBold(font) == (piece.kind == .span && piece.isBold), "굵기: \(what)")
                #expect((attributes[MessagesBubbleMarkdown.linkKey] as? URL) == piece.link, "링크: \(what)")
                let color: NSColor = switch piece.kind {
                case .span: piece.link == nil ? CM17.colors.text : CM17.colors.link
                case .lineBreak: CM17.colors.text
                case .disclosure: CM17.colors.disclosure
                }
                #expect((attributes[.foregroundColor] as? NSColor) == color, "색: \(what)")
                if let link = piece.link {
                    linked += 1
                    #expect(ChatMarkdown.isOpenable(link), "열 수 없는 링크가 실렸다: \(what)")
                }
            }
        }
        #expect(linked > 50, "링크 갈래를 \(linked)번만 지났다 — 무작위가 링크를 안 만든다")
    }
}

// MARK: - ① 색 · 제목 크기 상한

@MainActor
@Suite("V1017ChatMarkdownPalette")
struct V1017ChatMarkdownPaletteTests {
    /// 받은 말풍선(bubbleIn)과 내 말풍선(accentFill) 위 본문 · 링크 · 꼬리표가 라이트 · 다크 모두 **4.5:1** 이다(폰 색 규칙).
    /// 내 말풍선 링크는 강조색 바탕에 묻히지 않게 흰색(밑줄로 가른다). 기준선: 맥처럼 꼬리표를 흰색 75% 로 흐리면 다크에서 무너진다.
    @Test func 말풍선_위_글자는_모두_4_5_대_1이다() {
        for isMine in [false, true] {
            let palette = MessagesBubbleMarkdown.Palette.of(isMine: isMine)
            for (name, pair) in [("본문", palette.text), ("링크", palette.link), ("꼬리표", palette.disclosure)] {
                #expect(pair.light.contrast(against: palette.bubble.light) >= 4.5, "\(name) 라이트 mine=\(isMine)")
                #expect(pair.dark.contrast(against: palette.bubble.dark) >= 4.5, "\(name) 다크 mine=\(isMine)")
            }
        }
        #expect(MessagesBubbleMarkdown.Palette.of(isMine: true).link != MessagesBubbleMarkdown.Palette.of(isMine: false).link)
        #expect(MessagesBubbleMarkdown.Palette.of(isMine: false).link == MobileThemePalette.accent)
        #expect(MessagesBubbleMarkdown.Palette.of(isMine: true).bubble == MobileThemePalette.accentFill)
        // 기준선: 흐린 흰 꼬리표(맥 75%)는 폰 다크 accentFill 위에서 4.5 를 못 넘는다 — 위 단언이 색을 실제로 잰다.
        let dimmed = MobileThemePalette.onAccentFill.dark.opacity(0.75)
        #expect(dimmed.contrast(against: MobileThemePalette.accentFill.dark) < 4.5)
    }

    /// 제목 크기 상한: 제목 스타일은 AX1 에서 멈추고, 본문보다 작아지지 않는다(큰 글자에서 본문이 더 크면 본문 크기의 굵은 글자).
    @Test func 제목은_큰_글자에서_상한이_있고_본문보다_작지_않다() {
        #expect(MessagesBubbleMarkdown.headingTextStyles == [.title2, .title3, .headline])
        #expect(MessagesBubbleMarkdown.headingDynamicTypeSize(.large) == .large)
        #expect(MessagesBubbleMarkdown.headingDynamicTypeSize(.accessibility1) == .accessibility1)
        #expect(MessagesBubbleMarkdown.headingDynamicTypeSize(.accessibility5) == .accessibility1, "AX5 에서 제목이 계속 자란다")
        #expect(MessagesBubbleMarkdown.headingDynamicTypeSize(.xxxLarge) == .xxxLarge)
        #expect(MessagesBubbleMarkdown.headingPointSize(styleSize: 22, bodySize: 16) == 22)
        #expect(MessagesBubbleMarkdown.headingPointSize(styleSize: 34, bodySize: 51) == 51, "큰 글자에서 제목이 본문보다 작아졌다")
    }
}

// MARK: - ② 링크 누름 판정 · 여는 문 · 보이스오버 동작

@MainActor
@Suite("V1017ChatMarkdownLinkTap")
struct V1017ChatMarkdownLinkTapTests {
    /// 링크 글자 위를 누르면 그 주소, 꼬리표 · 평범한 글자 · 줄 끝 너머 · 글 아래 빈 곳은 nil. **그린 배치 그대로** 잰다(같은 엔진).
    @Test func 링크_글자를_누르면_그_주소이고_꼬리표와_빈_곳은_아니다() throws {
        let width: CGFloat = 520
        let engine = CM17.engine("보세요 [자료](https://a.example/doc) 와 https://b.example/x 끝")
        #expect(engine.lines(width: width).count == 1, "한 줄 기준선이 접혔다: \(engine.lines(width: width))")
        let a = try CM17.center(of: "자료", in: engine, width: width)
        #expect(engine.link(at: a, width: width)?.absoluteString == "https://a.example/doc")
        let b = try CM17.center(of: "b.example", in: engine, width: width)
        #expect(engine.link(at: b, width: width)?.absoluteString == "https://b.example/x")
        // 꼬리표 " (a.example)" 는 링크가 아니다 — 누르는 자리는 글 그대로다(맥과 같다).
        #expect(engine.link(at: try CM17.center(of: "(a.example)", in: engine, width: width), width: width) == nil)
        #expect(engine.link(at: try CM17.center(of: "보세요", in: engine, width: width), width: width) == nil)
        // 끝 글자 "끝" 바로 뒤 · 아주 먼 오른쪽 · 글 아래 — 가장 가까운 글자가 링크여도 상자 밖이면 아니다.
        engine.layout(width: width)
        let used = engine.layoutManager.usedRect(for: engine.container)
        #expect(engine.link(at: CGPoint(x: used.midX, y: used.maxY + 30), width: width) == nil, "글 아래 빈 곳이 링크로 열린다")

        // 링크로 끝나는 줄: 마지막 글자 위 · 손가락 오차 안은 링크, 그 너머는 아니다(가장 가까운 글자가 링크여도).
        let tail = CM17.engine("끝에 https://c.example/z")
        tail.layout(width: width)
        let lastGlyph = tail.layoutManager.glyphRange(for: tail.container).length - 1
        let box = tail.layoutManager.boundingRect(forGlyphRange: NSRange(location: lastGlyph, length: 1), in: tail.container)
        let slop = MessagesBubbleTextLayout.Engine.touchSlop
        #expect(tail.link(at: CGPoint(x: box.midX, y: box.midY), width: width)?.absoluteString == "https://c.example/z")
        #expect(tail.link(at: CGPoint(x: box.maxX + slop - 1, y: box.midY), width: width) != nil, "손가락 오차 안쪽이 안 열린다")
        #expect(tail.link(at: CGPoint(x: box.maxX + slop + 2, y: box.midY), width: width) == nil, "손가락 오차 너머가 링크로 열린다")
        #expect(tail.link(at: CGPoint(x: box.maxX + 60, y: box.midY), width: width) == nil, "줄 끝 너머가 링크로 열린다")
    }

    /// 손가락 오차는 **링크 옆에 다른 글리프가 있어도** 듣는다(2026-11-03 검토 minor). 첫 판은 가장 가까운 글자 하나의 상자만 봐서,
    /// 링크 뒤 줄바꿈 글리프(상자가 칸 끝까지 이어진다) · 꼬리표 앞 공백이 가장 가까운 글자가 되면 링크 끝 바로 옆이 nil 이었다.
    /// 기준선: 같은 자리에서 오차 너머 · 다음 줄 · 꼬리표 가운데는 여전히 nil 이다(넓히기가 링크를 줄 전체로 키우지 않았다).
    @Test func 손가락_오차는_링크_뒤_줄바꿈과_꼬리표_옆에서도_듣는다() throws {
        let width: CGFloat = 300
        let slop = MessagesBubbleTextLayout.Engine.touchSlop
        func lastBox(of part: String, in engine: MessagesBubbleTextLayout.Engine) throws -> CGRect {
            engine.layout(width: width)
            let range = (engine.storage.string as NSString).range(of: part)
            try #require(range.location != NSNotFound, "\(part) 가 글에 없다")
            let glyphs = engine.layoutManager.glyphRange(forCharacterRange: NSRange(location: range.location + range.length - 1, length: 1),
                                                         actualCharacterRange: nil)
            return engine.layoutManager.boundingRect(forGlyphRange: glyphs, in: engine.container)
        }

        // ① 링크로 끝나는 줄 다음에 줄바꿈 — 가장 가까운 글리프가 줄바꿈이어도 오차 안쪽은 링크다.
        let newline = CM17.engine("보세요 https://a.example/x\n다음 줄은 평범한 글자가 꽤 길게 이어집니다")
        let x = try lastBox(of: "a.example/x", in: newline)
        #expect(newline.link(at: CGPoint(x: x.maxX + 2, y: x.midY), width: width)?.absoluteString == "https://a.example/x", "줄바꿈 옆 +2pt 가 안 열린다")
        #expect(newline.link(at: CGPoint(x: x.maxX + slop - 0.5, y: x.midY), width: width) != nil)
        #expect(newline.link(at: CGPoint(x: x.maxX + slop + 2, y: x.midY), width: width) == nil, "오차 너머가 열린다")
        #expect(newline.link(at: CGPoint(x: x.maxX + 60, y: x.midY), width: width) == nil, "줄 끝 너머가 열린다")
        #expect(newline.link(at: try CM17.center(of: "평범한", in: newline, width: width), width: width) == nil, "다음 줄 글자가 열린다")

        // ② `[자료](…) 끝` — 꼬리표 앞 공백이 가장 가까운 글리프여도 라벨 끝 +2pt 는 링크다. 꼬리표 가운데 · 뒤 글자는 아니다.
        let tail = CM17.engine("[자료](https://a.example/doc) 끝")
        #expect(tail.storage.string == "자료 (a.example) 끝", "전제: 꼬리표가 붙은 글이 아니다: \(tail.storage.string)")
        let label = try lastBox(of: "자료", in: tail)
        #expect(tail.link(at: CGPoint(x: label.maxX + 2, y: label.midY), width: width)?.absoluteString == "https://a.example/doc",
                "꼬리표 공백 옆 +2pt 가 안 열린다")
        #expect(tail.link(at: CGPoint(x: label.maxX + slop + 2, y: label.midY), width: width) == nil, "오차 너머(꼬리표)가 열린다")
        #expect(tail.link(at: try CM17.center(of: "(a.example)", in: tail, width: width), width: width) == nil)
        #expect(tail.link(at: try CM17.center(of: "끝", in: tail, width: width), width: width) == nil)

        // ③ 링크 둘이 가까우면 바로 위에 놓인 쪽이 이긴다(넓힌 상자가 겹쳐도 옆 링크로 새지 않는다).
        let pair = CM17.engine("https://a.example/x https://b.example/y")
        #expect(pair.link(at: try CM17.center(of: "b.example", in: pair, width: width, at: 0), width: width)?.absoluteString == "https://b.example/y")
        #expect(pair.link(at: try CM17.center(of: "a.example/x", in: pair, width: width, at: 10), width: width)?.absoluteString == "https://a.example/x")
    }

    /// 좁은 폭에서 여러 줄로 접힌 링크도 **어느 줄을 눌러도** 같은 주소다. 같은 글을 넓은 폭에서 재면 다른 자리다(배치를 따른다).
    @Test func 접힌_링크는_어느_줄을_눌러도_같은_주소다() throws {
        let label = "자료실 문서 모음 바로가기 링크"
        let engine = CM17.engine("앞 [\(label)](https://a.example/docs) 뒤")
        let width: CGFloat = 110
        try #require(engine.lines(width: width).count >= 3, "기준선: 좁은 폭에서 접히지 않았다")
        for (offset, _) in label.enumerated() where label[label.index(label.startIndex, offsetBy: offset)] != " " {
            let point = try CM17.center(of: label, in: engine, width: width, at: offset)
            #expect(engine.link(at: point, width: width)?.absoluteString == "https://a.example/docs", "\(offset) 번째 글자")
        }
        #expect(engine.link(at: try CM17.center(of: "뒤", in: engine, width: width), width: width) == nil)
        // 접힌 줄의 오른쪽 빈 곳(칸 끝 너머)은 링크가 아니다 — 줄 조각별 상자가 줄 끝 빈칸까지 늘지 않는다.
        engine.layout(width: width)
        let firstLine = engine.layoutManager.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
        #expect(engine.link(at: CGPoint(x: width + 20, y: firstLine.midY), width: width) == nil, "칸 너머가 링크로 열린다")
    }

    /// 열 수 없는 링크 모양은 누를 자리가 없다(속성이 없다). 빈 글도 nil.
    @Test func 나쁜_링크와_빈_글은_누를_자리가_없다() throws {
        let engine = CM17.engine("[나쁜](javascript:alert(1)) 끝")
        let width: CGFloat = 300
        #expect(engine.link(at: try CM17.center(of: "나쁜", in: engine, width: width), width: width) == nil)
        #expect(CM17.engine("").link(at: .zero, width: width) == nil)
    }

    /// 여는 문은 **여는 자리에서 스킴을 다시 본다**(두 겹): http·https 만 연다. 해석 밖에서 온 값(javascript · file · 사용자 정보)은 막힌다.
    @Test func 여는_문은_http_https_만_연다() throws {
        var opened: [String] = []
        for raw in ["https://a.example/doc", "http://b.example"] {
            let url = try #require(URL(string: raw))
            let ok = MessagesBubbleMarkdown.follow(url) { opened.append($0.absoluteString) }
            #expect(ok, "\(raw) 가 안 열렸다")
        }
        for raw in ["javascript:alert(1)", "file:///etc/passwd", "https://naver.com:443@evil.com", "aingcheck://message/x", "tel:01012345678",
                    "https://n%D0%B0ver.com", "https://%D0%B0pple.com/login", "https://%D0%B0%D1%80%D1%80%D3%8F%D0%B5.com/id",
                    "https://naver.com%2E%65%76%69%6C%2E%63%6F%6D/login"] {
            let url = try #require(URL(string: raw))
            let ok = MessagesBubbleMarkdown.follow(url) { opened.append($0.absoluteString) }
            #expect(!ok, "\(raw) 가 열렸다")
        }
        #expect(opened == ["https://a.example/doc", "http://b.example"])
    }

    /// 보이스오버 동작: 링크마다 "링크 열기: 보이는 글 (호스트)" — 여는 곳이 글과 다르면 이름에 호스트가 든다. 그림 말풍선 · 평문은 없다.
    @Test func 보이스오버_동작은_링크마다_보이는_글과_꼬리표로_이름짓는다() {
        let actions = MessagesBubbleMarkdown.linkActions("[자료](https://a.example/doc) 와 https://b.example/x 그리고 [naver.com](https://evil.example) [자료](https://a.example/doc)")
        #expect(actions.map(\.title) == ["링크 열기: 자료 (a.example)", "링크 열기: https://b.example/x", "링크 열기: naver.com (evil.example)"])
        #expect(actions.map(\.url.absoluteString) == ["https://a.example/doc", "https://b.example/x", "https://evil.example"])
        #expect(MessagesBubbleMarkdown.linkActions("[a.example](https://a.example)").map(\.title) == ["링크 열기: a.example"])
        #expect(MessagesBubbleMarkdown.linkActions("평범한 글").isEmpty)
        #expect(MessagesBubbleMarkdown.linkActions("[나쁜](javascript:alert(1))").isEmpty)
        // 퍼센트 인코딩 호스트는 링크가 아니라 보이스오버 동작도 없다(이름에 풀린 키릴 호스트가 들던 길).
        #expect(MessagesBubbleMarkdown.linkActions("[naver.com](https://n%D0%B0ver.com) 와 https://naver.com%2Eevil.com/login").isEmpty)
        for sticker in AingSticker.allCases {
            #expect(MessagesBubbleMarkdown.linkActions(AingStickerText.preview(for: sticker.token)).isEmpty)
        }
    }
}

// MARK: - ③ 복사 글 — 맥 표 그대로(코어 한 함수)

@MainActor
@Suite("V1017ChatMarkdownCopy")
struct V1017ChatMarkdownCopyTests {
    /// 고른 구간에 `[글](주소)` 링크가 걸치면 꼬리표 대신 **실제 주소**를 담는다 — 맥 ChatBubbleSelectionTests `고른_링크는_실제_주소째_복사한다`
    /// 열세 칸을 **폰 말풍선 글** 위에서 그대로 돌린다(폰 골라 복사 1.0.17 이 이 함수를 쓴다). 기준선: 보이는 글자 그대로면 꼬리표가 들어간다.
    @Test func 고른_링크는_실제_주소째_복사한다() throws {
        let drawn = CM17.drawn("**굵게** [자료](https://a.example/doc) 끝")
        try #require(drawn.string == "굵게 자료 (a.example) 끝")
        let cases: [(String, String)] = [
            ("굵게 자료 (a.example) 끝", "굵게 자료 (https://a.example/doc) 끝"),
            ("자료", "자료 (https://a.example/doc)"),
            ("자", "자 (https://a.example/doc)"),
            ("(a.example)", "(https://a.example/doc)"),
            ("굵게 자", "굵게 자 (https://a.example/doc)"),
            ("굵게", "굵게"),
            (" 끝", " 끝"),
        ]
        for (part, expected) in cases {
            let range = (drawn.string as NSString).range(of: part)
            try #require(range.location != NSNotFound)
            #expect(ChatMarkdownCopy.text(drawn, range: range) == expected, "\(part.debugDescription) 를 고른 복사")
        }
        let whole = NSRange(location: 0, length: drawn.length)
        #expect((drawn.string as NSString).substring(with: whole) == "굵게 자료 (a.example) 끝", "기준선: 보이는 글자에는 꼬리표가 있다")

        for (body, expected) in [
            ("[a.example](https://a.example/doc) 봐", "a.example (https://a.example/doc) 봐"),
            ("https://a.example/doc 봐", "https://a.example/doc 봐"),
            ("[https://a.example/](https://a.example) 봐", "https://a.example/ 봐"),
            ("[가](https://a.example)와 [나](https://b.example)", "가 (https://a.example)와 나 (https://b.example)"),
            ("**[굵은 링크](https://a.example/x)**", "굵은 링크 (https://a.example/x)"),
            ("줄 하나\n[둘](https://b.example/y)", "줄 하나\n둘 (https://b.example/y)"),
        ] {
            let other = CM17.drawn(body)
            #expect(ChatMarkdownCopy.text(other, ranges: [NSRange(location: 0, length: other.length)]) == expected, "\(body.debugDescription) 전체")
        }
        // 고른 것이 없거나 글 밖이면 nil — [복사]는 원문으로 접는다(`menuText`).
        #expect(ChatMarkdownCopy.text(drawn, ranges: []) == nil)
        #expect(ChatMarkdownCopy.text(drawn, ranges: [NSRange(location: 0, length: 0), NSRange(location: drawn.length, length: 3)]) == nil)
        #expect(ChatMarkdownCopy.menuText(selection: nil, raw: "**굵게** [자료](https://a.example/doc)") == "**굵게** [자료](https://a.example/doc)")
        #expect(ChatMarkdownCopy.menuText(selection: "굵게", raw: "**굵게**") == "굵게")
    }

    /// 폰 [복사](길게 누름 메뉴 · 보이스오버 동작)는 **원문**이다 — 맥 [복사]의 "고른 글자가 없으면 원문"과 같다(서식 기호 · 이모티콘 토큰 그대로 —
    /// 붙여넣어 다시 보내면 같은 꾸밈 · 같은 그림). 붙여넣기판에는 글자(`string`)만 쓴다. 신고는 받은 말풍선에만 있고, 서버로 가는 신고 본문도 원문이다.
    @Test func 폰_복사는_원문이고_신고는_받은_말풍선에만_있다() throws {
        let code = try CM17.code(CM17.conversationPath)
        let copy = try CM17.block(of: "enum MessagesBubbleCopy", in: code)
        #expect(copy.contains("UIPasteboard.general.string = body"), "붙여넣기판에 서식 없는 글자만 쓰지 않는다")
        #expect(!copy.contains("setItems") && !copy.contains("attributedString"), "붙여넣기판에 서식이 실린다")
        // 1.0.17: 길게 누름 메뉴는 이모티콘 말풍선에만 남는다(글 말풍선은 편집 메뉴 — V1017BubbleSelectionContract).
        let menu = try CM17.block(of: "private var stickerMenu: some View", in: code)
        #expect(menu.contains("MessagesBubbleCopy.copy(line.entry.body)"), "[복사]가 원문이 아니다")
        #expect(menu.contains("if let onReport {"), "[신고]가 신고 문이 있을 때만 뜨지 않는다")
        #expect(code.contains("MessagesBubbleRow(line: line, onReport: line.entry.isMine ? nil : { reportMessage(line.entry) })"),
                "[신고]가 받은 말풍선에만 있지 않다")
        let report = try CM17.block(of: "private func reportMessage(", in: code)
        #expect(report.contains("messageBody: entry.body") && !report.contains("plainPreview"), "서버로 가는 신고 본문이 원문이 아니다")
    }
}

// MARK: - ④ 기호가 날것으로 보이던 네 자리

@MainActor
@Suite("V1017ChatMarkdownPlainSpots")
struct V1017ChatMarkdownPlainSpotsTests {
    /// 대화 목록 미리보기 · 확성기 배너(글 · 보이스오버) · 신고 인용 · 말풍선 줄 보이스오버가 **같은 한 함수**(`ChatMarkdown.plainPreview`)를 지난다 —
    /// 서식 기호와 이모티콘 토큰을 벗긴다. 평범한 한 줄 본문은 한 글자도 안 바뀐다.
    @Test func 목록_배너_보이스오버가_기호와_토큰을_벗긴다() {
        let body = "## 공지\n**회의** [자료](https://a.example) 봐요"
        #expect(MessagesListRules.preview(body) == "공지 회의 자료 봐요")
        #expect(MegaphoneBannerPhoneText.shownBody(body) == "공지 회의 자료 봐요")
        #expect(MegaphoneBannerPhoneText.accessibilityLabel(name: "민수", body: "**점심** 드세요") == "민수님의 확성기, 점심 드세요")
        // 배너는 1.0.16 까지 이모티콘 토큰까지 날것이었다 — 이제 이름으로 읽힌다.
        for sticker in AingSticker.allCases {
            #expect(MegaphoneBannerPhoneText.shownBody(sticker.token) == "아잉이 \(sticker.label)")
            #expect(MegaphoneBannerPhoneText.accessibilityLabel(name: "민수", body: sticker.token) == "민수님의 확성기, 아잉이 \(sticker.label)")
            #expect(MessagesListRules.preview(sticker.token) == "아잉이 \(sticker.label)")
            #expect(ChatMarkdown.plainPreview(sticker.token) == "아잉이 \(sticker.label)", "줄 라벨 · 신고 인용이 이모티콘 규칙을 안 거친다")
        }
        // 기준선: 원문 그대로였던 1.0.16 배너 라벨은 기호 · 토큰째였다.
        #expect("민수님의 확성기, **점심** 드세요" != MegaphoneBannerPhoneText.accessibilityLabel(name: "민수", body: "**점심** 드세요"))

        // 평범한 본문은 그대로 · 받지 않는 문법도 그대로 · 열 수 없는 링크는 원문 그대로.
        for plain in ["화이팅", "점심 드셨어요?", "-_-", "*기울임*", "`코드`", "- 항목", "> 인용", "#해시태그", "https://a.com", "[아잉:기쁨] 좋아요"] {
            #expect(MessagesListRules.preview(plain) == plain, "\(plain) 목록")
            #expect(MegaphoneBannerPhoneText.shownBody(plain) == plain, "\(plain) 배너")
        }
        #expect(MessagesListRules.preview("[글](javascript:alert(1))") == "[글](javascript:alert(1))")
        // 목록 접기는 그대로다(줄 안 연속 공백 · 탭까지 한 칸).
        #expect(MessagesListRules.preview("안녕\n\n  잘 지내?\t응") == "안녕 잘 지내? 응")
    }

    /// 화면 배선(주석 걷은 소스): 네 자리가 그 함수를 부르고, 날것 호출은 남지 않았다.
    @Test func 네_자리가_plainPreview_를_부른다() throws {
        let overlay = try CM17.code("Sources/CheckMobileKit/Messages/MegaphoneBannerOverlay.swift")
        let card = try CM17.block(of: "private struct MegaphoneBannerCard", in: overlay)
        #expect(card.contains("Text(MegaphoneBannerPhoneText.shownBody(banner.body))"), "배너 글이 기호를 안 벗긴다")
        #expect(!card.contains("Text(banner.body)"), "배너 글이 아직 원문이다")
        #expect(card.contains("MegaphoneBannerPhoneText.accessibilityLabel(name: banner.senderName, body: banner.body)"))
        let rules = try CM17.code("Sources/CheckMobileKit/Messages/MegaphoneBannerPhoneRules.swift")
        let label = try CM17.block(of: "package static func accessibilityLabel(name: String, body: String)", in: rules)
        #expect(label.contains("shownBody(body)"), "배너 보이스오버가 화면과 다른 글을 읽는다")
        let shown = try CM17.block(of: "package static func shownBody(", in: rules)
        #expect(shown.contains("ChatMarkdown.plainPreview(body)"))

        let sheets = try CM17.code("Sources/CheckMobileKit/Messages/MessagesBlockSheets.swift")
        let quoted = try CM17.block(of: "private func quotedMessage(", in: sheets)
        #expect(quoted.contains("Text(ChatMarkdown.plainPreview(body))"), "신고 인용이 기호를 안 벗긴다")

        let rulesCode = try CM17.code("Sources/CheckMobileKit/Messages/MessagesRules.swift")
        let preview = try CM17.block(of: "package static func preview(_ body: String) -> String", in: rulesCode)
        #expect(preview.contains("ChatMarkdown.plainPreview(body)"), "목록 미리보기가 기호를 안 벗긴다")

        let conversation = try CM17.code(CM17.conversationPath)
        let ax = try CM17.block(of: "private var accessibilityText", in: conversation)
        #expect(ax.contains("ChatMarkdown.plainPreview(entry.body)"), "말풍선 줄 보이스오버가 기호를 읽는다")
        let pending = try CM17.block(of: "struct MessagesPendingBubbleRow", in: conversation)
        #expect(pending.contains(#"\(ChatMarkdown.plainPreview(item.body))"#), "보내는 중 줄 보이스오버가 기호를 읽는다")
    }
}

// MARK: - 화면 배선 — 말풍선 본문 · 누름 · 여는 문 (주석 걷은 소스 계약)

@MainActor
@Suite("V1017ChatMarkdownViewContract")
struct V1017ChatMarkdownViewContractTests {
    /// 말풍선 본문은 여전히 TextKit 글 칸이고(SwiftUI `Text` 로 바꾸지 않는다 — 어절 줄바꿈), 그 글은 서식 글 한 장이다.
    /// 이모티콘 폴백이 먼저다(말풍선 · 자리 말풍선이 `AingStickerText.preview` 를 지난 글을 넘긴다 — V1012 계약 그대로).
    @Test func 말풍선은_TextKit_글칸에_서식_글을_넣는다() throws {
        let code = try CM17.code(CM17.conversationPath)
        let label = try CM17.block(of: "private struct MessagesBubbleLabel: UIViewRepresentable", in: code)
        let update = try CM17.block(of: "func updateUIView(", in: label)
        #expect(update.contains("MessagesBubbleMarkdown.attributed("), "말풍선이 서식을 안 그린다")
        #expect(update.contains("fonts: MessagesBubbleMarkdown.fonts(for: context.environment.dynamicTypeSize)"), "글자 크기 설정을 안 따른다")
        #expect(update.contains("colors: MessagesBubbleMarkdown.colors(isMine: isMine)"))
        #expect(!update.contains("NSAttributedString(string:"), "평문 한 덩어리로 되돌아갔다")
        #expect(label.contains("MessagesBubbleTextUIView()"), "TextKit 글 칸이 아니다")
        #expect(!code.contains("Text(text)") && !code.contains(".textSelection("), "SwiftUI Text 로 바꾸면 한글이 음절에서 끊긴다")
        // 1.0.17 골라 복사(대표 답 #d_M9wR9l9VLNvx): 글 칸은 고를 수 있는 UITextView 다 — 엔진의 TextKit 1 틀째 짓고(TextKit 2 아님),
        // 링크 기본 동작(검사 없는 열기 · 웹 미리보기)은 막는다. 그 배선은 V1017BubbleSelectionContract 가 잰다.
        #expect(code.contains("final class MessagesBubbleTextUIView: UITextView") && !code.contains("textLayoutManager"),
                "글 칸이 엔진 틀째 지은 TextKit 1 UITextView 가 아니다")

        let markdown = try CM17.code(CM17.markdownPath)
        let attributed = try CM17.block(of: "package static func attributed(", in: markdown)
        #expect(attributed.contains("MessagesBubbleTextLayout.paragraphStyle()"), "어절 줄바꿈 문단 스타일이 빠졌다")
        #expect(attributed.contains("ChatMarkdownPieces.pieces(shown)"), "코어 조각 목록(맥과 한 벌)을 안 지난다")
        #expect(!markdown.contains("[.link]") && !markdown.contains(".link:"), "시스템 .link 속성을 싣는다 — TextKit 이 색을 덮는다")
    }

    /// 링크 한 번 누르기: 누름 인식기는 링크 글자 위에서만 시작하고(대리자), 누른 자리 → 엔진 판정 → 여는 문. 여는 문은 하나이고 스킴 검사를 지난다.
    /// 말풍선 뷰는 `gestureRecognizerShouldBegin` 을 재정의하지 않는다(조상 인식기 — 스크롤 · 메뉴 — 까지 막는다).
    @Test func 링크_누름은_판정을_지나_한_문으로_연다() throws {
        let code = try CM17.code(CM17.conversationPath)
        let view = try CM17.block(of: "final class MessagesBubbleTextUIView: UITextView", in: code)
        #expect(view.contains("UITapGestureRecognizer(target: self, action: #selector(tappedLink(_:)))"))
        #expect(view.contains("tap.delegate = linkTapGate") && view.contains("addGestureRecognizer(tap)"))
        #expect(!view.contains("gestureRecognizerShouldBegin"), "말풍선 뷰가 조상 인식기의 시작까지 막는다")
        let at = try CM17.block(of: "func link(at point: CGPoint) -> URL?", in: view)
        #expect(at.contains("engine.link(atBubblePoint: point, bubbleWidth: bounds.width)"), "그린 폭 · 여백과 다른 배치로 판정한다")
        let tapped = try CM17.block(of: "@objc private func tappedLink(", in: view)
        #expect(tapped.contains("link(at: recognizer.location(in: self))") && tapped.contains("MessagesBubbleLinkDoor.open(url)"))

        let gate = try CM17.block(of: "final class MessagesBubbleLinkTapGate", in: code)
        #expect(gate.contains("linkAtTap: bubble.link(at: gestureRecognizer.location(in: bubble))") && gate.contains(") != nil"),
                "링크 밖에서도 누름이 시작한다")

        let door = try CM17.block(of: "enum MessagesBubbleLinkDoor", in: code)
        #expect(door.contains("MessagesBubbleMarkdown.follow(url) { UIApplication.shared.open($0) }"), "여는 문 앞의 스킴 검사가 없다")
        #expect(CM17.count("UIApplication.shared.open", in: code) == 1, "여는 길이 문 밖에 또 있다")
        #expect(!code.contains("openURL"), "검사 없는 SwiftUI openURL 길이 있다")
        let markdown = try CM17.code(CM17.markdownPath)
        let follow = try CM17.block(of: "package static func follow(", in: markdown)
        #expect(follow.contains("ChatMarkdown.isOpenable(url)"))
    }

    /// 보이스오버: 줄은 요소 하나라 링크마다 동작을 단다(같은 여는 문). 복사 · 신고 동작은 그대로다.
    @Test func 보이스오버_링크_동작은_같은_문으로_연다() throws {
        let code = try CM17.code(CM17.conversationPath)
        let row = try CM17.block(of: "struct MessagesBubbleRow: View", in: code)
        #expect(row.contains("ForEach(linkActions, id: \\.self)"), "링크 동작이 없다 — 보이스오버로는 링크에 닿지 못한다")
        #expect(row.contains("Button(link.title) { MessagesBubbleLinkDoor.open(link.url) }"))
        #expect(row.contains("MessagesBubbleMarkdown.linkActions(AingStickerText.preview(for: line.entry.body))"),
                "동작이 말풍선에 보이는 글(이모티콘 폴백 뒤)과 다른 글에서 나온다")
        #expect(row.contains(".accessibilityAction(named: Text(MessagesBubbleCopy.title)) { MessagesBubbleCopy.copy(entry.body) }"))
        #expect(row.contains("Button(BlockReportText.reportMessageAction, action: onReport)"))
    }
}
