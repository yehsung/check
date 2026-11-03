import Foundation

// MARK: - 말풍선이 그릴 조각 · 복사할 글 (맥·폰 한 벌 — 폰 1.0.17 이식 때 맥 `ChatMarkdownText` · `ChatBubbleTextView` 에서 옮겼다)
//
// 해석(`ChatMarkdown.parse`)은 줄과 조각을 돌려준다. 그리는 쪽은 그 줄들을 **그릴 조각 목록 하나**로 옮겨 글꼴·색만 입힌다:
//   · 맥 말풍선 — `ChatMarkdownText.pieces` / `nsAttributed`(Sources/check) · 크기는 pt 표(10/13/15/17).
//   · 폰 말풍선 — `MessagesBubbleMarkdown.attributed`(Sources/CheckMobileKit) · 크기는 Dynamic Type 글자 스타일.
// 무엇을 그리는가(글자 · 제목 단계 · 굵게 · 링크 · 호스트 꼬리표)는 **여기 한 곳**이 정하고, 두 기기는 크기와 색만 정한다.
// 갈라 두면 언젠가 한 기기만 꼬리표를 빠뜨린다 — 꼬리표는 "보이는 글과 여는 곳이 다른 링크"를 알리는 안전장치다.
//
// 복사도 같다(대표 결정 "받은 말풍선도 드래그" · 2026-11-03 검토 P2): 고른 구간에 `[글](주소)` 링크가 걸치면 호스트 꼬리표 대신
// **실제 주소**를 담고, 글자는 서식 없이 담는다. 맥 ⌘C · [복사] · 끌어 놓기와 폰의 고른 글 복사(다음 판 — 모양을 대표에게 묻는 중)가
// 이 함수 하나(`ChatMarkdownCopy.text`)를 쓴다. 고른 것이 없는 [복사]는 두 기기 모두 **원문**이다(마크다운 기호·이모티콘 토큰 그대로 —
// 붙여넣어 다시 보내면 같은 꾸밈·그림이 된다). 그 규칙은 `ChatMarkdownCopy.menuText` 다.

/// 말풍선이 그리는 조각 하나. 이어 붙이면 말풍선에 보이는 글자 전부다.
package struct ChatMarkdownPiece: Equatable, Sendable {
    package enum Kind: Equatable, Sendable {
        /// 해석 조각(본문 · 굵게 · 링크).
        case span
        /// 줄 사이 "\n".
        case lineBreak
        /// `[글](주소)` 뒤에 붙이는 실제 호스트 " (호스트)" — 링크가 아니다(누르는 자리는 글 그대로다).
        case disclosure
    }

    package let kind: Kind
    package let text: String
    /// 이 조각이 놓인 줄의 종류(크기를 정하는 값). 줄 사이 "\n" 은 본문(`.paragraph`)이다.
    package let line: ChatMarkdownLineKind
    /// 굵게 그리는가. 제목 줄의 조각은 언제나 굵다. 꼬리표 · 줄바꿈은 굵지 않다.
    package let isBold: Bool
    /// 누르면 열 주소(해석이 `ChatMarkdown.openableLink` 로 거른 http·https 뿐). 꼬리표 · 줄바꿈은 nil.
    package let link: URL?

    package init(kind: Kind, text: String, line: ChatMarkdownLineKind, isBold: Bool, link: URL?) {
        self.kind = kind
        self.text = text
        self.line = line
        self.isBold = isBold
        self.link = link
    }

    /// 크기 단계: 0 = 본문, 1 = `#`, 2 = `##`, 3 = `###` 이하(`####`~`######` 도 3 — 크기는 3단계에서 멈춘다).
    package var headingStep: Int { ChatMarkdownPieces.headingStep(line) }
}

package enum ChatMarkdownPieces {
    /// 줄 종류 → 크기 단계(`ChatMarkdownPiece.headingStep`).
    package static func headingStep(_ kind: ChatMarkdownLineKind) -> Int {
        guard case .heading(let level) = kind else { return 0 }
        return min(max(level, 1), 3)
    }

    /// 본문 → 그릴 조각들. **이모티콘 폴백은 부르는 쪽이 먼저 거친다**(`AingStickerText.preview` → 여기).
    package static func pieces(_ body: String) -> [ChatMarkdownPiece] {
        var out: [ChatMarkdownPiece] = []
        for (index, line) in ChatMarkdown.parse(body).enumerated() {
            if index > 0 {
                out.append(ChatMarkdownPiece(kind: .lineBreak, text: "\n", line: .paragraph, isBold: false, link: nil))
            }
            let isHeading: Bool
            if case .heading = line.kind { isHeading = true } else { isHeading = false }
            // `[글](주소)` 는 글 뒤에 실제 호스트를 붙인다(`ChatMarkdown.linkDisclosures` — 보이는 글과 여는 곳이 다른 링크).
            let disclosures = ChatMarkdown.linkDisclosures(line)
            for (spanIndex, span) in line.spans.enumerated() {
                out.append(ChatMarkdownPiece(
                    kind: .span, text: span.text, line: line.kind, isBold: isHeading || span.isBold, link: span.link
                ))
                if let host = disclosures[spanIndex] {
                    out.append(ChatMarkdownPiece(kind: .disclosure, text: " (\(host))", line: line.kind, isBold: false, link: nil))
                }
            }
        }
        return out
    }

    /// 한 줄에 그리는 쪽이 **덧붙이는** 글자 수(호스트 꼬리표 " (호스트)"). 말풍선 높이 추정이 같은 글자로 세게 한다.
    package static func addedCharacters(_ line: ChatMarkdownLine) -> Int {
        ChatMarkdown.linkDisclosures(line).values.reduce(0) { $0 + $1.count + 3 }
    }

    /// 조각 위치 → 복사에 담을 실제 주소. 같은 주소로 이어진 링크 조각들이 한 링크이고(`ChatMarkdown.linkDisclosures` 와 같은 묶음),
    /// 그 글이 주소 자체가 아니면(`[자료](https://a.example/doc)` · `[a.example](https://a.example/doc)`) 글 조각들과 바로 뒤 꼬리표에 표시한다.
    /// 맨 주소 · `[https://a.com/](https://a.com)` 처럼 글이 곧 주소인 링크는 표시하지 않는다(보이는 글자가 이미 주소다).
    package static func copyLinks(_ pieces: [ChatMarkdownPiece]) -> [Int: URL] {
        var result: [Int: URL] = [:]
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
            if ChatMarkdown.comparableAddress(label) != ChatMarkdown.comparableAddress(url.absoluteString) {
                for spot in index..<end { result[spot] = url }
                if end < pieces.count, pieces[end].kind == .disclosure { result[end] = url }
            }
            index = end
        }
        return result
    }
}

// MARK: - 복사할 글

package enum ChatMarkdownCopy {
    /// 고른 글자를 복사할 때 **실제 주소를 덧붙일 링크**의 표시(값: 그 주소). 글이 주소와 다른 링크의 글 조각과 그 뒤 꼬리표에 붙는다
    /// (`ChatMarkdownPieces.copyLinks`). 그림에는 안 보인다 — 맥 · 폰 말풍선 글자가 같은 이 키를 싣는다.
    package static let linkKey = NSAttributedString.Key("check.chatBubble.copyLink")
    /// 호스트 꼬리표 " (호스트)" 조각의 표시 — 복사할 때 이 글자 대신 실제 주소를 담는다.
    package static let disclosureKey = NSAttributedString.Key("check.chatBubble.disclosure")

    /// 그린 글자의 한 구간 → 복사할 글자(서식 없음). 보이는 글자 그대로이되 **`[글](주소)` 링크만 다르다**(2026-11-03 검토 P2):
    /// 보이는 것은 `글 (호스트)` 인데 그대로 담으면 실제 주소는 빠지고 보낸 사람이 치지 않은 꼬리표가 들어간다. 그래서
    /// 글이 주소와 다른 링크(`linkKey` 가 붙은 조각)는 고른 글 뒤에 ` (실제 주소)` 를 한 번 담고, 꼬리표 글자는
    /// 그 자리로 갈음한다. 꼬리표만 골라도 주소를 담는다. 맨 주소(글 = 주소)는 보이는 그대로다.
    package static func text(_ text: NSAttributedString, range: NSRange) -> String {
        let source = text.string as NSString
        var out = ""
        var pending: URL?
        func flush() {
            guard let url = pending else { return }
            out += (out.isEmpty ? "" : " ") + "(\(url.absoluteString))"
            pending = nil
        }
        text.enumerateAttributes(in: range) { attributes, run, _ in
            let url = attributes[linkKey] as? URL
            if attributes[disclosureKey] != nil {
                // 꼬리표 " (호스트)" — 글자 대신 실제 주소. 고른 것이 꼬리표에서 시작했으면 그 주소를 여기서 집는다.
                if pending == nil { pending = url }
                flush()
                return
            }
            if pending != url { flush() }
            out += source.substring(with: run)
            if let url { pending = url }
        }
        flush()
        return out
    }

    /// 고른 구간들 → 복사할 글자(여러 구간이면 줄바꿈으로 잇는다). 빈 구간 · 글자 밖 구간은 버리고, 남는 것이 없으면 nil(아무것도 안 골랐다).
    package static func text(_ text: NSAttributedString, ranges: [NSRange]) -> String? {
        let parts = ranges
            .filter { $0.length > 0 && NSMaxRange($0) <= text.length }
            .map { self.text(text, range: $0) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// 말풍선 메뉴 [복사]가 담을 글자 — 고른 글자가 있으면 그것(`text(_:ranges:)`), 없으면 **원문**.
    /// 원문은 마크다운 기호 · 이모티콘 토큰 그대로다: 붙여넣어 다시 보내면 같은 꾸밈 · 같은 그림이 된다.
    /// 폰 [복사]는 고르는 길이 없는 메뉴라 언제나 원문이다(`selection` 이 늘 nil).
    package static func menuText(selection: String?, raw: String) -> String {
        selection ?? raw
    }
}
