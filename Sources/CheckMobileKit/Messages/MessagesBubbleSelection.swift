import CheckCore
import Foundation

// MARK: - 폰 말풍선에서 글 일부를 골라 복사 (1.0.17 · 대표 답 #d_M9wR9l9VLNvx "말풍선에서 바로 길게 눌러 고르기")
//
// 대표 답 원문: "말풍선에서 바로 길게 눌러 고르기"(맥과 가장 비슷. 대신 메뉴가 iOS 기본 편집 메뉴(복사·전체 선택·번역 + 신고)로 바뀌고
// 말풍선 들어 올림 효과가 사라짐). 글 말풍선 본문은 고를 수 있는(편집 불가) `UITextView` 다(`MessagesBubbleTextUIView`).
// 길게 누르면 iOS 기본 고르기가 시작되고, 손을 떼면 편집 메뉴가 뜬다. 이 파일은 그 글 칸이 따르는 **규칙**만 둔다 —
// UIKit · AppKit 양쪽에서 컴파일되어 맥 `swift test` 가 잰다(글 칸 자체는 `#if os(iOS)` 라 맥 시험이 컴파일하지 않는다).
//
//  · 편집 메뉴: iOS 가 제안한 항목 가운데 [복사] · [전체 선택] · [번역] 만 이 순서로 남기고, 받은 말풍선이면 끝에 [신고]를 단다.
//    공유 · 찾아보기 · 웹 검색 · 말하기 · 글쓰기 도구 등은 거른다 — 공유는 보이는 글자(호스트 꼬리표째)를 다른 앱으로 넘긴다(감사 위험 3).
//  · [복사]: 고른 글자를 **서식 없이**, `[글](주소)` 링크는 꼬리표 대신 **실제 주소**째(코어 `ChatMarkdownCopy.text` — 맥 ⌘C 와 한 함수).
//    고른 것이 없는 복사(이모티콘 말풍선 메뉴 · 보이스오버 [복사])는 예전처럼 원문이다(`MessagesBubbleCopy`).
//  · 고르는 중(고른 글자가 있다)엔 한 번 누름이 링크를 열지 않는다 — 그 누름은 고른 것을 지우는 누름이다.
package enum MessagesBubbleSelection {
    /// 편집 메뉴에 남기는 iOS 항목(선언 순서가 메뉴 순서다).
    package enum MenuItem: Int, CaseIterable, Sendable {
        case copy
        case selectAll
        case translate
    }

    /// iOS 가 제안한 편집 메뉴 항목 하나의 이름 → 남길 자리. 이름은 `UICommand` 면 선택자 이름("copy:"), `UIAction` 이면 식별자다.
    /// [번역]은 공개 선택자가 없어(iOS 26 UIKitCore 실측 `_translate:`) 이름에 "translate" 가 든 것으로 알아본다 — 비공개 선택자를 코드에 박지 않는다.
    /// 그 밖의 것은 nil(거른다).
    package static func menuItem(named name: String) -> MenuItem? {
        switch name {
        case "copy:": .copy
        case "selectAll:": .selectAll
        default: name.lowercased().contains("translate") ? .translate : nil
        }
    }

    /// 편집 메뉴에 세울 항목들: 제안(`suggested` — 이름과 원래 항목, 하위 메뉴는 부르는 쪽이 펼쳐 넘긴다)에서 남길 것만 `MenuItem` 순서로
    /// 하나씩 고르고, `report` 가 있으면(받은 말풍선) 끝에 단다. iOS 가 제안하지 않은 항목은 세우지 않는다(예: 전부 고른 뒤의 [전체 선택]).
    ///
    /// ★ `fallbackCopy`: 제안에서 [복사]를 **못 알아봤을 때만** 그 자리에 세우는 글 칸 자체의 [복사](1.0.17 검토 지적). 거르기는 iOS 가
    ///   [복사]를 선택자 `copy:` 인 `UICommand` 로 준다는 데 기댄다 — iOS 26 부터 편집 메뉴 길이 바뀌는 중이라(SDK 27.2 에서
    ///   `editMenuForTextInRange` 가 `…InRanges` 로 대체 예고) 다른 식별자의 `UIAction` 으로 오면 [번역] · [신고]만 남아 기능의 핵심이 빠진다.
    ///   알아봤으면 시스템 것을 그대로 쓴다(이 값은 버린다). 부르는 쪽은 고른 글자가 있을 때만 넘긴다(빈 [복사]가 서지 않게).
    package static func menu<Element>(suggested: [(name: String, element: Element)], report: Element?, fallbackCopy: Element? = nil) -> [Element] {
        var picked: [MenuItem: Element] = [:]
        for (name, element) in suggested {
            guard let item = menuItem(named: name), picked[item] == nil else { continue }
            picked[item] = element
        }
        if picked[.copy] == nil, let fallbackCopy { picked[.copy] = fallbackCopy }
        var out = MenuItem.allCases.compactMap { picked[$0] }
        if let report { out.append(report) }
        return out
    }

    /// 편집 메뉴 밖의 길(키보드 단축키 · 응답자 사슬의 다른 질문)에서도 글 칸이 거절할 동작 — 공유(보이는 글자를 꼬리표째 다른 앱으로 넘긴다).
    package static func refuses(actionNamed name: String) -> Bool {
        name.lowercased().contains("share")
    }

    /// 고른 구간 → 붙여넣기판에 쓸 글자(서식 없음 · `[글](주소)` 는 실제 주소째). 아무것도 안 골랐으면 nil(아무것도 안 쓴다).
    package static func copyText(_ drawn: NSAttributedString, selected range: NSRange) -> String? {
        copyText(drawn, selected: [range], wholeTextRaw: nil)
    }

    /// 고른 구간들(iOS 26 여러 구간 선택 `selectedRanges` — 합집합 `selectedRange` 를 담으면 고르지 않은 글이 섞인다) → 붙여넣기판 글자.
    /// 여러 구간은 코어 규칙대로 줄바꿈으로 잇는다(`ChatMarkdownCopy.text(_:ranges:)`).
    ///
    /// `wholeTextRaw`: 보이는 글자가 원문과 다른 말풍선의 원문(`wholeCopyRaw(body:)` — 번들 그림을 못 읽어 "아잉이 기쁨"으로 접힌 이모티콘).
    /// 고른 것이 **글 전체**면 그 원문(토큰)을 담는다 — 1.0.16 의 길게 누름 [복사]와 같은 값이라 붙여넣어 다시 보내면 그림이 된다(검토 지적).
    /// 일부만 골랐으면 보이는 글자 그대로다.
    package static func copyText(_ drawn: NSAttributedString, selected ranges: [NSRange], wholeTextRaw: String?) -> String? {
        if let wholeTextRaw, coversWholeText(ranges, length: drawn.length) { return wholeTextRaw }
        return ChatMarkdownCopy.text(drawn, ranges: ranges)
    }

    /// 말풍선 원문 → 고른 것이 글 전체일 때 대신 담을 원문. 보이는 글자(`AingStickerText.preview`)가 원문과 같으면 nil(평범한 글 — 보이는 대로 담는다).
    package static func wholeCopyRaw(body: String) -> String? {
        AingStickerText.preview(for: body) == body ? nil : body
    }

    /// 구간들의 합이 글 전체(0..<length)를 빈틈없이 덮는가. 빈 글은 덮을 것이 없다(false).
    static func coversWholeText(_ ranges: [NSRange], length: Int) -> Bool {
        guard length > 0 else { return false }
        let covered = NSMutableIndexSet()
        for range in ranges where range.location != NSNotFound && range.length > 0 {
            covered.add(in: NSIntersectionRange(range, NSRange(location: 0, length: length)))
        }
        return covered.count == length
    }

    /// 한 번 누름이 열 링크 — 고른 글자가 있으면(고르는 중) 열지 않는다. 누른 자리가 링크가 아니면 nil.
    package static func linkToOpen(selectedLength: Int, linkAtTap: URL?) -> URL? {
        selectedLength == 0 ? linkAtTap : nil
    }

    /// 고르기 강조 · 손잡이 색(글 칸 `tintColor` — iOS 는 강조를 이 색을 옅게 깔아 그린다). 시스템 파랑은 파란 내 말풍선에서 안 보인다:
    /// 내 말풍선은 본문 글자색(label — 라이트 검정 · 다크 흰색)이라 파란 바탕 위 강조와 말풍선 밖으로 나온 손잡이가 둘 다 보이고,
    /// 받은 말풍선(회색 바탕)은 강조색이다. 맥(`ChatMarkdownText.nsSelectionColor`)이 내 말풍선 강조를 따로 둔 것과 같은 까닭이다.
    package static func selectionTint(isMine: Bool) -> MobileThemePalette.Pair {
        isMine ? MobileThemePalette.label : MobileThemePalette.accent
    }

    /// [신고] 그림(이모티콘 말풍선 메뉴 · 글 말풍선 편집 메뉴가 같이 쓴다).
    package static let reportSymbol = "exclamationmark.bubble"
}
