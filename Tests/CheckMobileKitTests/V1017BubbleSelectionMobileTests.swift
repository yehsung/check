import AppKit
@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.17 — 말풍선에서 바로 길게 눌러 글 일부를 골라 복사(대표 답 #d_M9wR9l9VLNvx "말풍선에서 바로 길게 눌러 고르기" — 되묻지 말 것).
//
// 글 말풍선 본문은 고를 수 있는(편집 불가) `UITextView` 가 되었다(`MessagesBubbleTextUIView`). 그 뷰는 `#if os(iOS)` 라 맥 `swift test` 가
// 컴파일하지 않는다(메모리 '폰 뷰는 맥 스위트가 못 본다' — build-sim 이 유일한 컴파일 그물). 그래서 셋으로 잰다:
//  ① **규칙 값**(UIKit·AppKit 양쪽 컴파일): 편집 메뉴 거르기 · 복사 글 · 고르는 중 링크 · 고르기 색.
//  ② **측정 일치**: 글 칸에 넘기는 엔진(`prepareForTextView`)이 재는 엔진과 같은 줄 · 같은 크기를 내고, 말풍선 크기가 1.0.16 의
//     "SwiftUI padding + 안쪽 글 칸 재기" 와 같다. 같은 TextKit 1 길(NSTextView 에 틀째 넘기기)의 AppKit 짝도 잰다 — UIKit 실물은 실기기 목록.
//  ③ **배선**: 주석을 걷은 소스 계약(메모리 source-contract-tests-need-comment-stripping).
// 기준선을 같이 둔다(메모리 comparison-baseline-must-differ): 거르지 않은 제안 · 보이는 글자 그대로의 복사 · 끊기 대리자를 뗀 배치 · 여백을 안 옮긴 판정.

// MARK: - 길잡이

@MainActor
private enum BS17 {
    static var fonts: MessagesBubbleMarkdown.Fonts { .system(sizes: [16, 22, 20, 17]) }
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

    /// 재는 엔진(1.0.16 글 칸과 같은 것)과 글 칸에 넘기는 엔진에 같은 글을 넣는다.
    static func engines(_ shown: String) -> (measure: MessagesBubbleTextLayout.Engine, display: MessagesBubbleTextLayout.Engine) {
        let text = drawn(shown)
        let measure = MessagesBubbleTextLayout.Engine()
        measure.set(text)
        let display = MessagesBubbleTextLayout.Engine()
        display.prepareForTextView()
        display.set(text)
        return (measure, display)
    }

    /// 말풍선에 실제로 오는 모양들 — 한글 긴 줄 · 숫자와 한글 · 제목 · 굵게 · 링크 꼬리표 · 여러 줄 · 긴 주소 · 이모티콘 폴백 · 빈 글.
    static let corpus: [String] = [
        "오후에 디자인 리뷰 10분만 가능할까요?",
        "어제 공유해 주신 시안 잘 봤어요! 2번이 제일 좋았어요. 색 대비만 조금 올리면 모바일에서도 잘 보일 것 같아요.",
        "## 회의\n**굵게** 와 [자료](https://a.example/doc) 끝",
        "# 큰 제목\n### 작은 제목\n본문 한 줄",
        "보세요 https://github.com/yehsung/check/pull/1234/files#diff-abcdef 링크예요",
        "[자료실 문서 모음 바로가기 링크](https://a.example/docs) 뒤",
        "줄 하나\n\n줄 셋 **굵은 말** 끝",
        "가나다라마바사아자차카타파하가나다라마바사아자차카타파하가나다라마바사",
        AingStickerText.preview(for: AingSticker.allCases[0].token),
        "네",
        "",
    ]

    static let conversationPath = "Sources/CheckMobileKit/Messages/MessagesConversationView.swift"

    static func code(_ relative: String) throws -> String {
        try IntegrationContractTests.code(relative)
    }

    /// 선언 머리부터 **중괄호가 닫히는 곳까지**(V1017ChatMarkdownMobileTests 의 CM17.block 과 같은 방식).
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

    static func textView() throws -> String {
        try block(of: "final class MessagesBubbleTextUIView: UITextView, UITextViewDelegate", in: try code(conversationPath))
    }
}

// MARK: - ① 규칙 값

@MainActor
@Suite("V1017BubbleSelectionRules")
struct V1017BubbleSelectionRulesTests {
    /// iOS 가 제안하는 편집 메뉴(iOS 26 UIKitCore 에서 본 선택자 이름들)에서 [복사] · [전체 선택] · [번역]만 이 순서로 남고, 받은 말풍선이면 [신고]가 끝에 붙는다.
    /// 기준선: 거르지 않은 제안에는 공유 · 찾아보기 · 웹 검색 · 글쓰기 도구가 들어 있다.
    @Test func 편집_메뉴는_복사_전체선택_번역만_남기고_받은_말풍선엔_신고를_단다() {
        let names = ["cut:", "copy:", "paste:", "delete:", "select:", "selectAll:", "_promptForReplace:", "_transliterateChinese:",
                     "_lookup:", "_define:", "_translate:", "_searchWeb:", "_share:", "_addShortcut:", "_findSelected:",
                     "showWritingTools:", "captureTextFromCamera:", "toggleBoldface:", "com.apple.menu.speech"]
        let suggested = names.map { (name: $0, element: $0) }
        #expect(MessagesBubbleSelection.menu(suggested: suggested, report: "신고") == ["copy:", "selectAll:", "_translate:", "신고"])
        #expect(MessagesBubbleSelection.menu(suggested: suggested, report: nil) == ["copy:", "selectAll:", "_translate:"], "내 말풍선에 신고가 붙었다")
        // 기준선: 제안 그대로면 남의 앱으로 넘기는 항목이 있다.
        for leak in ["_share:", "_lookup:", "_define:", "_searchWeb:", "showWritingTools:"] {
            #expect(names.contains(leak), "기준선 제안에 \(leak) 가 없다")
            #expect(!MessagesBubbleSelection.menu(suggested: suggested, report: nil).contains(leak), "\(leak) 가 남았다")
        }

        // 제안 순서가 달라도 복사 · 전체 선택 · 번역 · 신고 순서다.
        let shuffled = [(name: "_translate:", element: "번역"), (name: "_share:", element: "공유"),
                        (name: "selectAll:", element: "전체"), (name: "copy:", element: "복사")]
        #expect(MessagesBubbleSelection.menu(suggested: shuffled, report: "신고") == ["복사", "전체", "번역", "신고"])
        // 같은 자리는 하나만(첫 것).
        #expect(MessagesBubbleSelection.menu(suggested: [(name: "copy:", element: "1"), (name: "copy:", element: "2")], report: nil) == ["1"])
        // 번역이 식별자로 와도(UIAction) 알아본다 — 비공개 선택자 글자를 박지 않는다.
        #expect(MessagesBubbleSelection.menu(suggested: [(name: "com.apple.menu.Translate", element: "번역")], report: nil) == ["번역"])
        // iOS 가 제안하지 않은 항목은 세우지 않는다(전부 고른 뒤의 [전체 선택] 등).
        #expect(MessagesBubbleSelection.menu(suggested: [(name: "copy:", element: "복사")], report: "신고") == ["복사", "신고"])
        #expect(MessagesBubbleSelection.menu(suggested: [(name: "_share:", element: "공유")], report: nil).isEmpty)
        #expect(MessagesBubbleSelection.menuItem(named: "copy:") == .copy)
        #expect(MessagesBubbleSelection.menuItem(named: "selectAll:") == .selectAll)
        #expect(MessagesBubbleSelection.menuItem(named: "cut:") == nil && MessagesBubbleSelection.menuItem(named: "paste:") == nil)
    }

    /// 편집 메뉴 밖의 길에서도 공유는 거절한다. 복사 · 전체 선택 · 번역은 거절하지 않는다(메뉴에 서야 한다).
    @Test func 공유는_메뉴_밖에서도_거절한다() {
        #expect(MessagesBubbleSelection.refuses(actionNamed: "_share:"))
        for kept in ["copy:", "selectAll:", "_translate:"] {
            #expect(!MessagesBubbleSelection.refuses(actionNamed: kept), "\(kept) 를 거절한다 — 메뉴에서 사라진다")
        }
    }

    /// 보험 [복사](검토 지적): iOS 가 [복사]를 `copy:` 아닌 이름(다른 식별자의 UIAction)으로 주면 거르기가 못 알아봐 [복사]가 빠진다 —
    /// 그때만 글 칸 자체의 [복사]가 그 자리(첫째)에 선다. 알아봤으면 시스템 것을 그대로 쓰고 보험은 버린다. 보험이 없으면(고른 글 없음) 세우지 않는다.
    /// 기준선: 보험 없이는 모르는 이름의 복사가 오면 메뉴에 [번역] · [신고]만 남는다.
    @Test func 복사를_못_알아본_제안에는_글칸_복사가_첫자리에_선다() {
        let unknownCopy = [(name: "com.apple.menu.standard-edit.copy-v2", element: "낯선복사"), (name: "_translate:", element: "번역"),
                           (name: "_share:", element: "공유")]
        #expect(MessagesBubbleSelection.menu(suggested: unknownCopy, report: "신고") == ["번역", "신고"],
                "기준선: 모르는 이름의 복사가 거르기를 지났다 — 이 시험이 아무것도 안 잰다")
        #expect(MessagesBubbleSelection.menu(suggested: unknownCopy, report: "신고", fallbackCopy: "글칸복사") == ["글칸복사", "번역", "신고"],
                "[복사]를 못 알아봤는데 보험 [복사]가 안 섰다 — 메뉴에서 복사가 사라진다")
        let known = [(name: "selectAll:", element: "전체"), (name: "copy:", element: "시스템복사")]
        #expect(MessagesBubbleSelection.menu(suggested: known, report: nil, fallbackCopy: "글칸복사") == ["시스템복사", "전체"],
                "알아본 시스템 [복사]를 보험이 밀어냈다(또는 둘 다 섰다)")
        #expect(MessagesBubbleSelection.menu(suggested: unknownCopy, report: nil, fallbackCopy: nil) == ["번역"])
    }

    /// iOS 26 여러 구간 선택: 구간마다 담아 줄바꿈으로 잇는다 — 합집합(`selectedRange`)을 담으면 사이에 고르지 않은 글이 섞인다(검토 지적).
    @Test func 여러_구간을_고르면_구간만_담고_사이_글은_안_섞인다() throws {
        let drawn = BS17.drawn("가나다 라마바 사아자")
        let text = drawn.string as NSString
        let first = text.range(of: "가나다"), last = text.range(of: "사아자")
        try #require(first.location != NSNotFound && last.location != NSNotFound)
        #expect(MessagesBubbleSelection.copyText(drawn, selected: [first, last], wholeTextRaw: nil) == "가나다\n사아자")
        // 기준선: 합집합 한 구간이면 사이 글("라마바")이 들어간다.
        let union = NSUnionRange(first, last)
        #expect(MessagesBubbleSelection.copyText(drawn, selected: union)?.contains("라마바") == true, "기준선: 합집합에 사이 글이 없다")
        #expect(MessagesBubbleSelection.copyText(drawn, selected: [first, last], wholeTextRaw: nil)?.contains("라마바") == false)
    }

    /// 그림을 못 읽어 "아잉이 기쁨"으로 접힌 이모티콘: 글 전체를 골라 복사하면 **원문 토큰**(1.0.16 길게 누름 [복사]와 같은 값 — 붙여넣어 보내면 그림),
    /// 일부만 고르면 보이는 글자다. 평범한 글은 원문 대체가 없다(보이는 그대로 — 꼬리표 대신 실제 주소 규칙 그대로).
    @Test func 그림을_못_읽은_이모티콘은_전체를_고르면_원문_토큰을_담는다() throws {
        let token = AingSticker.allCases[0].token
        let shown = AingStickerText.preview(for: token)
        try #require(shown != token, "전제: 이모티콘 폴백 글자가 원문과 다르다")
        #expect(MessagesBubbleSelection.wholeCopyRaw(body: token) == token)
        #expect(MessagesBubbleSelection.wholeCopyRaw(body: "그냥 글 **굵게**") == nil, "평범한 글에 원문 대체가 붙었다")
        let drawn = BS17.drawn(shown)
        let raw = MessagesBubbleSelection.wholeCopyRaw(body: token)
        let all = NSRange(location: 0, length: drawn.length)
        #expect(MessagesBubbleSelection.copyText(drawn, selected: [all], wholeTextRaw: raw) == token, "글 전체를 골랐는데 원문 토큰이 아니다")
        // 두 구간이 빈틈없이 덮어도 전체다.
        let cut = drawn.length / 2
        #expect(MessagesBubbleSelection.copyText(drawn, selected: [NSRange(location: 0, length: cut), NSRange(location: cut, length: drawn.length - cut)],
                                                 wholeTextRaw: raw) == token)
        // 일부만 — 보이는 글자.
        let part = NSRange(location: 0, length: drawn.length - 1)
        #expect(MessagesBubbleSelection.copyText(drawn, selected: [part], wholeTextRaw: raw) == (shown as NSString).substring(with: part))
        // 기준선: 원문을 안 넘기면 전체를 골라도 보이는 글자다(1.0.17 첫 판의 구멍).
        #expect(MessagesBubbleSelection.copyText(drawn, selected: all) == shown)
        #expect(MessagesBubbleSelection.copyText(drawn, selected: [NSRange(location: 0, length: 0)], wholeTextRaw: raw) == nil, "안 골랐는데 썼다")
    }

    /// 고른 구간 → 붙여넣기판 글: 서식 없이, `[글](주소)` 는 꼬리표 대신 실제 주소째(코어 `ChatMarkdownCopy.text` — 맥 ⌘C 와 한 함수).
    /// 기준선: 보이는 글자 그대로면 꼬리표 호스트가 들어가고 실제 주소는 빠진다.
    @Test func 고른_글자는_서식_없이_링크는_실제_주소째_복사한다() throws {
        let drawn = BS17.drawn("**굵게** [자료](https://a.example/doc) 끝")
        try #require(drawn.string == "굵게 자료 (a.example) 끝")
        func copied(_ part: String) throws -> String? {
            let range = (drawn.string as NSString).range(of: part)
            try #require(range.location != NSNotFound, "\(part) 가 없다")
            return MessagesBubbleSelection.copyText(drawn, selected: range)
        }
        #expect(try copied("자료") == "자료 (https://a.example/doc)")
        #expect(try copied("굵게 자료 (a.example) 끝") == "굵게 자료 (https://a.example/doc) 끝")
        #expect(try copied("(a.example)") == "(https://a.example/doc)", "꼬리표만 골라도 실제 주소다")
        #expect(try copied("굵게") == "굵게", "굵은 글자는 기호 없이")
        // 기준선: 보이는 글자에는 꼬리표가 있다.
        #expect((drawn.string as NSString).substring(with: (drawn.string as NSString).range(of: "자료 (a.example)")) == "자료 (a.example)")
        // 고른 것이 없거나 글 밖이면 쓰지 않는다(nil).
        #expect(MessagesBubbleSelection.copyText(drawn, selected: NSRange(location: 3, length: 0)) == nil)
        #expect(MessagesBubbleSelection.copyText(drawn, selected: NSRange(location: drawn.length, length: 2)) == nil)

        // 제목 · 여러 줄 · 맨 주소: 기호 없이 보이는 줄 그대로, 맨 주소는 보이는 그대로.
        let other = BS17.drawn("## 회의\n내용 https://b.example/x")
        #expect(MessagesBubbleSelection.copyText(other, selected: NSRange(location: 0, length: other.length)) == "회의\n내용 https://b.example/x")
    }

    /// 고르는 중(고른 글자가 있다)엔 한 번 누름이 링크를 열지 않는다. 링크 밖이면 언제나 nil.
    @Test func 고르는_중엔_링크가_안_열린다() throws {
        let url = try #require(URL(string: "https://a.example/doc"))
        #expect(MessagesBubbleSelection.linkToOpen(selectedLength: 0, linkAtTap: url) == url)
        #expect(MessagesBubbleSelection.linkToOpen(selectedLength: 1, linkAtTap: url) == nil, "고르는 중 링크가 열린다")
        #expect(MessagesBubbleSelection.linkToOpen(selectedLength: 12, linkAtTap: url) == nil)
        #expect(MessagesBubbleSelection.linkToOpen(selectedLength: 0, linkAtTap: nil) == nil)
    }

    /// 고르기 색: 내 말풍선은 본문 글자색(label), 받은 말풍선은 강조색. 기준선: 시스템 기본(강조색)은 라이트에서 내 말풍선 바탕과 **같은 파랑**이라 안 보인다.
    @Test func 고르기_색은_내_말풍선에서_바탕과_다르다() {
        #expect(MessagesBubbleSelection.selectionTint(isMine: true) == MobileThemePalette.label)
        #expect(MessagesBubbleSelection.selectionTint(isMine: false) == MobileThemePalette.accent)
        #expect(MobileThemePalette.accent.light == MobileThemePalette.accentFill.light, "기준선: 강조색과 내 말풍선 바탕이 라이트에서 같다")
        #expect(MessagesBubbleSelection.selectionTint(isMine: true) != MobileThemePalette.accentFill)
    }
}

// MARK: - ② 측정 일치

@MainActor
@Suite("V1017BubbleSelectionMeasure")
struct V1017BubbleSelectionMeasureTests {
    /// 글 칸에 넘기는 엔진(`prepareForTextView`)은 재는 엔진과 **같은 줄 · 같은 크기**다 — 같은 글 · 같은 폭 · 같은 끊기 대리자.
    /// 틀 설정도 잰다: 줄 조각 여백 0 · 끊기 대리자 = 그 엔진 · 줄 수 제한 없음 · 폭은 글 칸을 따라가고 높이는 따라가지 않는다.
    /// 기준선: 끊기 대리자를 뗀 배치는 같은 글에서 다른 줄이 나온다(대조가 대리자에 달려 있다).
    @Test func 글칸_엔진은_재는_엔진과_같은_줄과_크기다() {
        let widths: [CGFloat] = [1, 40, 96, 120, 150, 180, 214, 240, 274, 300, 520]
        for body in BS17.corpus {
            let (measure, display) = BS17.engines(body)
            for width in widths {
                #expect(display.lines(width: width) == measure.lines(width: width), "\(body.debugDescription) 폭 \(width) 줄")
                #expect(display.fittingSize(width: width) == measure.fittingSize(width: width), "\(body.debugDescription) 폭 \(width) 크기")
            }
            #expect(display.container.lineFragmentPadding == 0)
            #expect(display.layoutManager.delegate === display, "끊기 대리자가 빠졌다")
            #expect(display.container.widthTracksTextView && !display.container.heightTracksTextView)
            #expect(display.container.maximumNumberOfLines == 0)
            #expect(display.container.lineBreakMode == measure.container.lineBreakMode)
            #expect(display.storage.isEqual(to: measure.storage))
        }
        // 기준선: 대리자 없이는 "2 / 번이" 처럼 숫자와 한글 사이를 끊는다.
        let (measure, bare) = BS17.engines("어제 공유해 주신 시안 잘 봤어요! 2번이 제일")
        bare.layoutManager.delegate = nil
        #expect(bare.lines(width: 220) != measure.lines(width: 220), "기준선: 대리자를 떼도 같은 줄이다 — 대조가 아무것도 안 잰다")
    }

    /// 말풍선 한 장 크기 = 1.0.16 의 셈 그대로: 바깥 SwiftUI `.padding(.horizontal, 13).padding(.top, 8).padding(.bottom, 9)` 가 안쪽 글 칸에
    /// `max(제안 − 26, 0)`(nil 은 nil · 무한대는 무한대)을 넘기고, 글 칸은 `fittingSize(width: 제안 ?? greatestFiniteMagnitude)` 로 답했다.
    /// 기준선: 여백을 한 번 더 빼면(글 칸 안 여백 + 바깥 padding 이 겹치는 실수) 같은 제안에서 줄이 더 접혀 크기가 다르다.
    @Test func 말풍선_크기는_예전_padding_과_글칸_재기의_합과_같다() {
        #expect(MessagesBubbleTextLayout.bubbleInsets == MessagesBubbleTextLayout.BubbleInsets(top: 8, horizontal: 13, bottom: 9),
                "안쪽 여백이 시안 8/13/9 가 아니다")
        func legacy(_ engine: MessagesBubbleTextLayout.Engine, _ proposal: CGFloat?) -> CGSize {
            let inner: CGFloat? = proposal.map { $0.isFinite ? max($0 - 26, 0) : $0 }
            let text = engine.fittingSize(width: inner ?? .greatestFiniteMagnitude)
            return CGSize(width: text.width + 26, height: text.height + 17)
        }
        let proposals: [CGFloat?] = [nil, 0, 10, 26, 27, 60, 120, 200, 240, 266, 300, .infinity]
        for body in BS17.corpus {
            let (measure, _) = BS17.engines(body)
            for proposal in proposals {
                #expect(measure.bubbleFittingSize(proposedWidth: proposal) == legacy(measure, proposal),
                        "\(body.debugDescription) 제안 \(String(describing: proposal))")
            }
        }
        // 기준선: 여백을 두 번 빼면 긴 한글 줄이 다른 크기가 된다.
        let (long, _) = BS17.engines(BS17.corpus[1])
        let twice = long.fittingSize(width: 240 - 52)
        #expect(CGSize(width: twice.width + 26, height: twice.height + 17) != long.bubbleFittingSize(proposedWidth: 240))
    }

    /// 말풍선 좌표(안쪽 여백 포함)의 링크 판정은 여백만큼 옮겨 여백 뺀 폭으로 잰다 — 링크 글자 위는 그 주소, 여백 띠 · 링크 끝 너머는 아니다.
    /// 기준선: 같은 글 좌표를 옮기지 않고 그대로 말풍선 좌표로 쓰면 링크 끝 글자가 꼬리표 쪽으로 밀려 nil 이다.
    @Test func 말풍선_좌표의_링크_판정은_여백만큼_옮겨_잰다() throws {
        let (_, display) = BS17.engines("보세요 [자료](https://a.example/doc) 끝")
        let bubbleWidth: CGFloat = 300
        let textWidth = bubbleWidth - 26
        display.layout(width: textWidth)
        let range = (display.storage.string as NSString).range(of: "자료")
        try #require(range.location != NSNotFound)
        let lastGlyph = display.layoutManager.glyphRange(forCharacterRange: NSRange(location: range.location + 1, length: 1), actualCharacterRange: nil)
        let box = display.layoutManager.boundingRect(forGlyphRange: lastGlyph, in: display.container)
        let insets = MessagesBubbleTextLayout.bubbleInsets
        let inBubble = CGPoint(x: box.midX + insets.horizontal, y: box.midY + insets.top)
        #expect(display.link(atBubblePoint: inBubble, bubbleWidth: bubbleWidth)?.absoluteString == "https://a.example/doc")
        // 기준선: 글 좌표를 그대로 넘긴 판정(여백을 안 옮긴 판정)은 같은 손가락 자리에서 링크가 아니다.
        #expect(display.link(at: inBubble, width: textWidth) == nil, "기준선: 여백을 안 옮겨도 열린다 — 대조가 아무것도 안 잰다")
        // 여백 띠(링크 바로 위 · 왼쪽 위 모서리)는 링크가 아니다.
        #expect(display.link(atBubblePoint: CGPoint(x: inBubble.x, y: 1), bubbleWidth: bubbleWidth) == nil, "위 여백 띠가 링크로 열린다")
        #expect(display.link(atBubblePoint: CGPoint(x: 2, y: 2), bubbleWidth: bubbleWidth) == nil)
    }

    /// 같은 TextKit 1 길의 AppKit 짝: 엔진의 틀째 글 뷰(NSTextView(frame:textContainer:))에 넘겨도 끊기 대리자 · 줄 조각 여백이 그대로이고,
    /// 틀 폭은 글 뷰 폭 − 좌우 여백을 따라가 재는 엔진과 같은 줄이 나온다. (UIKit `UITextView` 실물은 맥이 못 띄운다 — 실기기 확인 목록.)
    @Test func 글뷰에_틀째_넘겨도_대리자와_폭이_그대로다_AppKit_짝() {
        let body = BS17.corpus[1]
        let (measure, display) = BS17.engines(body)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 400), textContainer: display.container)
        view.textContainerInset = NSSize(width: MessagesBubbleTextLayout.bubbleInsets.horizontal, height: MessagesBubbleTextLayout.bubbleInsets.top)
        view.setFrameSize(NSSize(width: 266, height: 400))
        #expect(view.layoutManager === display.layoutManager, "글 뷰가 다른 배치 관리자를 쓴다(TextKit 2 로 갔다)")
        #expect(display.layoutManager.delegate === display, "글 뷰가 끊기 대리자를 가져갔다")
        #expect(display.container.lineFragmentPadding == 0)
        // 글 뷰가 내놓는 틀 폭은 부동소수 셈이라 240 에 아주 가까운 값이다(실측 240.0 으로 찍히되 == 는 거짓) — 반 pt 안이면 같은 폭이다.
        #expect(abs(display.container.size.width - (266 - 26)) < 0.5, "틀 폭이 글 뷰 폭을 안 따라간다: \(display.container.size.width)")
        #expect(display.lines(width: display.container.size.width) == measure.lines(width: 240))
    }
}

// MARK: - ③ 배선 (주석 걷은 소스 계약)

@MainActor
@Suite("V1017BubbleSelectionContract")
struct V1017BubbleSelectionContractTests {
    /// 글 말풍선 본문은 고를 수 있는(편집 불가) TextKit 1 글 칸이고, 엔진의 틀째 짓는다. 크기는 재기 전용 엔진, 여백은 글 칸 안.
    @Test func 글_말풍선은_엔진_틀째_지은_고를_수_있는_글칸이다() throws {
        let code = try BS17.code(BS17.conversationPath)
        let view = try BS17.textView()
        let made = try BS17.block(of: "init()", in: view)
        #expect(made.contains("engine.prepareForTextView()"))
        #expect(made.contains("super.init(frame: .zero, textContainer: engine.container)"), "엔진의 틀째 짓지 않는다 — 줄바꿈이 달라진다")
        #expect(!code.contains("usingTextLayoutManager") && !code.contains("textLayoutManager"), "TextKit 2 길이 들어왔다(어절 끊기 대리자가 없다)")
        for needle in [
            "isEditable = false", "isSelectable = true", "isScrollEnabled = false", "dataDetectorTypes = []",
            "textDragInteraction?.isEnabled = false", "delegate = self", "contentInsetAdjustmentBehavior = .never",
            "textContainerInset = UIEdgeInsets(top: insets.top, left: insets.horizontal, bottom: insets.bottom, right: insets.horizontal)",
            "isAccessibilityElement = false", "engine.container.lineFragmentPadding = 0",
            // 검토 지적: 말풍선마다 낀 스크롤 뷰가 상태 막대 '맨 위로' 후보가 되지 않게 · 글 칸 하위 요소가 줄 라벨과 따로 읽히지 않게.
            "scrollsToTop = false", "accessibilityElementsHidden = true",
        ] {
            #expect(made.contains(needle), "글 칸 설정에 '\(needle)' 가 없다")
        }
        #expect(!made.contains("isEditable = true"))

        let label = try BS17.block(of: "private struct MessagesBubbleLabel: UIViewRepresentable", in: code)
        let fits = try BS17.block(of: "func sizeThatFits(", in: label)
        #expect(fits.contains("view.measure.bubbleFittingSize(proposedWidth: proposal.width)"), "말풍선 크기를 재는 엔진이 아니다")
        let show = try BS17.block(of: "func show(_ next: Shown, drawn: () -> NSAttributedString)", in: view)
        #expect(show.contains("guard shown != next else { return }"), "같은 글을 다시 박아 고르던 구간이 날아간다")
        #expect(show.contains("engine.set(text)") && show.contains("measure.set(text)"), "그리는 글과 재는 글이 갈린다")
        #expect(show.contains("MessagesBubbleSelection.selectionTint(isMine: next.isMine)"))

        // 여백은 글 칸 안 하나다 — 바깥 SwiftUI padding 이 남으면 여백이 두 번 더해진다.
        let bubbleText = try BS17.block(of: "private struct MessagesBubbleText: View", in: code)
        #expect(!bubbleText.contains(".padding("), "말풍선 여백이 글 칸 밖에도 있다")
        #expect(bubbleText.contains("MessagesBubbleLabel(text: text, isMine: isMine, onReport: onReport, wholeCopyRaw: wholeCopyRaw)"))
        let update = try BS17.block(of: "func updateUIView(_ view: MessagesBubbleTextUIView, context: Context)", in: label)
        #expect(update.contains("view.wholeCopyRaw = wholeCopyRaw"), "글 칸이 이모티콘 원문을 못 받는다")
        let link = try BS17.block(of: "func link(at point: CGPoint) -> URL?", in: view)
        #expect(link.contains("engine.link(atBubblePoint: point, bubbleWidth: bounds.width)"), "누름 판정이 여백을 안 옮긴다")
    }

    /// 편집 메뉴는 규칙을 지나고 언제나 메뉴를 돌려준다(nil = 시스템 기본 메뉴). [신고]는 받은 말풍선만, 맥과 같은 신고 흐름(`onReport`)이다.
    @Test func 편집_메뉴는_규칙을_지나고_신고는_받은_말풍선만이다() throws {
        let code = try BS17.code(BS17.conversationPath)
        let view = try BS17.textView()
        let menu = try BS17.block(of: "editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu?", in: view)
        #expect(menu.contains("UIMenu(children: MessagesBubbleSelection.menu(suggested: Self.leaves(suggestedActions), report: reportMenuItem(),"))
        #expect(menu.contains("fallbackCopy: ownCopyMenuItem(range: range)"), "보험 [복사]가 메뉴에 안 이어졌다(검토 지적)")
        let ownCopy = try BS17.block(of: "private func ownCopyMenuItem(range: NSRange) -> UIMenuElement?", in: view)
        #expect(ownCopy.contains("guard range.length > 0 else { return nil }"), "고른 글이 없어도 보험 [복사]가 선다")
        #expect(ownCopy.contains("self?.copy(nil)") && ownCopy.contains("MessagesBubbleCopy.title"), "보험 [복사]가 글 칸의 복사 규칙을 안 지난다")
        #expect(!menu.contains("nil") && !menu.contains("return suggestedActions"), "시스템 기본 메뉴(공유 · 찾아보기)로 빠지는 길이 있다")
        let leaves = try BS17.block(of: "private static func leaves(", in: view)
        #expect(leaves.contains("leaves(menu.children)") && leaves.contains("NSStringFromSelector(command.action)"))

        let report = try BS17.block(of: "private func reportMenuItem()", in: view)
        #expect(report.contains("guard onReport != nil else { return nil }"), "내 말풍선에도 신고가 붙는다")
        #expect(report.contains("BlockReportText.reportMessageAction") && report.contains("attributes: .destructive"))
        let fromMenu = try BS17.block(of: "private func reportFromMenu()", in: view)
        #expect(fromMenu.contains("onReport?()"))
        #expect(code.contains("MessagesBubbleRow(line: line, onReport: line.entry.isMine ? nil : { reportMessage(line.entry) })"))
        let content = try BS17.block(of: "private var bubbleContent: some View", in: code)
        #expect(content.contains("MessagesBubbleText(text: AingStickerText.preview(for: line.entry.body), isMine: line.entry.isMine, onReport: onReport,"),
                "글 말풍선이 신고 문을 못 받는다")
        #expect(content.contains("wholeCopyRaw: MessagesBubbleSelection.wholeCopyRaw(body: line.entry.body)"),
                "그림을 못 읽은 이모티콘 말풍선이 원문 토큰 복사를 잃었다(1.0.16 [복사]의 짝 — 검토 지적)")
        let pending = try BS17.block(of: "struct MessagesPendingBubbleRow", in: code)
        #expect(!pending.contains("onReport"), "보내는 중(내) 말풍선에 신고가 붙었다")
        #expect(pending.contains("wholeCopyRaw: MessagesBubbleSelection.wholeCopyRaw(body: item.body)"))

        let can = try BS17.block(of: "override func canPerformAction(", in: view)
        #expect(can.contains("MessagesBubbleSelection.refuses(actionNamed: NSStringFromSelector(action))"))
        // 링크 항목 대리자 둘은 막는다(기본 동작 · 기본 메뉴를 돌려주지 않는다).
        let primary = try BS17.block(of: "primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction?", in: view)
        #expect(primary.contains("nil") && !primary.contains("defaultAction"), "링크 기본 동작(검사 없는 열기)을 돌려준다")
        let config = try BS17.block(of: "menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu)", in: view)
        #expect(config.contains("nil") && !config.contains("defaultMenu"), "링크 기본 메뉴(웹 미리보기)를 돌려준다")
        #expect(!code.contains("shouldInteractWith"), "옛 링크 대리자 길이 있다")
    }

    /// [복사]는 고른 글자를 코어 규칙으로, 붙여넣기판 글자로만 쓴다(시스템 복사 · 서식째 쓰기 · 끌어 놓기 없음).
    @Test func 복사는_고른_글을_서식_없이_담는다() throws {
        let view = try BS17.textView()
        let copy = try BS17.block(of: "override func copy(_ sender: Any?)", in: view)
        #expect(copy.contains("MessagesBubbleSelection.copyText(engine.storage, selected: selectedTextRanges, wholeTextRaw: wholeCopyRaw)"),
                "복사가 여러 구간(iOS 26) · 이모티콘 원문을 안 본다")
        let ranges = try BS17.block(of: "private var selectedTextRanges: [NSRange]", in: view)
        #expect(ranges.contains("if #available(iOS 26.0, *) { return selectedRanges }") && ranges.contains("return [selectedRange]"),
                "iOS 26 에서 합집합 구간을 담는다")
        #expect(copy.contains("UIPasteboard.general.string = text"))
        #expect(!copy.contains("super.copy"), "시스템 복사는 보이는 글자(꼬리표째)를 서식째 싣는다")
        #expect(!copy.contains("setItems") && !copy.contains("attributed") && !copy.contains("rtf"), "붙여넣기판에 서식이 실린다")
        let resign = try BS17.block(of: "override func resignFirstResponder() -> Bool", in: view)
        #expect(resign.contains("selectedRange = NSRange(location: 0, length: 0)"), "포커스가 떠나도 고른 것이 남는다")
    }

    /// 글 말풍선에는 길게 누름 메뉴(들어 올림 미리보기)가 없고, 이모티콘 말풍선에만 예전 메뉴 [복사](원문) · [신고]가 남는다.
    @Test func 길게누름_메뉴는_이모티콘_말풍선에만_남는다() throws {
        let code = try BS17.code(BS17.conversationPath)
        #expect(BS17.count(".contextMenu {", in: code) == 1, "길게 누름 메뉴가 이모티콘 말풍선 밖에도 있다")
        #expect(BS17.count(".contextMenuPreview", in: code) == 1, "들어 올림 미리보기 모양이 이모티콘 말풍선 밖에도 있다")
        let content = try BS17.block(of: "private var bubbleContent: some View", in: code)
        let parts = content.components(separatedBy: "} else {")
        try #require(parts.count == 2, "갈래가 둘이 아니다")
        #expect(parts[0].contains("MessagesStickerBubble(art: drawn.art)") && parts[0].contains(".contextMenu { stickerMenu }"))
        #expect(!parts[1].contains("contextMenu"), "글 말풍선에 길게 누름 메뉴(들어 올림)가 남았다 — iOS 고르기와 길게 누르기가 겹친다")
        let menu = try BS17.block(of: "private var stickerMenu: some View", in: code)
        #expect(menu.contains("MessagesBubbleCopy.copy(line.entry.body)") && menu.contains("if let onReport {"))
        #expect(!code.contains(".textSelection("), "SwiftUI 고르기는 부분 선택이 안 되고 음절에서 끊는다")
    }

    /// 링크: 고르는 중엔 안 열리고(인식기 시작 · 끝 두 자리), 시스템 `.link` 가 없으며, 여는 문은 하나다.
    @Test func 링크는_고르는_중엔_안_열리고_여는_문은_하나다() throws {
        let code = try BS17.code(BS17.conversationPath)
        let gate = try BS17.block(of: "final class MessagesBubbleLinkTapGate", in: code)
        #expect(gate.contains("MessagesBubbleSelection.linkToOpen(") && gate.contains("selectedLength: bubble.selectedRange.length"),
                "고르는 중에도 링크 누름이 시작한다")
        let view = try BS17.textView()
        let tapped = try BS17.block(of: "@objc private func tappedLink(", in: view)
        #expect(tapped.contains("MessagesBubbleSelection.linkToOpen(selectedLength: selectedRange.length"), "끝난 누름이 고르는 중인지 안 본다")
        #expect(tapped.contains("MessagesBubbleLinkDoor.open(url)"))
        #expect(BS17.count("UIApplication.shared.open", in: code) == 1, "여는 길이 문 밖에 또 있다")
        for system in ["NSAttributedString.Key.link", "[.link", ".link:", "linkTextAttributes"] {
            #expect(!code.contains(system), "시스템 링크 속성(\(system))이 들어왔다 — 검사 없는 열기 · 웹 미리보기")
        }
        #expect(!code.contains("dataDetectorTypes = .") && !code.contains("dataDetectorTypes = [."), "자료 감지가 켜졌다(전화 · 주소가 시스템 링크가 된다)")
    }
}
