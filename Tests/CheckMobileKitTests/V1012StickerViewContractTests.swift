@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

/// 1.0.12 폰 아잉이 이모티콘 — **화면 계약**(말풍선 · 입력줄 그리드 · 신고 인용).
///
/// ── 왜 소스 글자를 재는가 ──
/// 메시지 뷰는 전부 `#if os(iOS)` 안이라 맥 스위트가 그 파일을 **컴파일조차 하지 않는다**(저장소 메모
/// '폰 뷰는 맥 스위트가 못 본다'). 그래서 값으로 잴 수 있는 것(토큰·전송·미리보기)은 `V1012StickerMobileTests`
/// 가 재고, 이 파일은 **뷰가 그 판정을 안 지나는 길**만 막는다. 재는 자리는 전부 **선언 블록 안**으로 좁힌다 —
/// 글자 수로 자른 창은 다음 블록으로 새어 남의 줄을 읽고, 그 탓에 살아남은 뮤테이션이 이 저장소에 있다.
/// 주석은 **걷어내고** 본다(안 걷으면 설명문을 지워야만 초록이 되는 테스트가 된다 — 하우스 규칙).
///
/// 이 파일이 지키려는 것은 맥에서 **실제로 데인** 자리들이다:
///   · 말풍선과 자리 말풍선이 각자 판정하면(한쪽은 `parse`, 한쪽은 `drawable`) 번들이 깨진 배포본에서
///     둘이 갈려 회색 빈 판이 쌓인다 — 판정하는 자리는 `AingStickerArt.drawable` **하나**다.
///   · 이모티콘 전송이 입력칸 초안을 건드리면 "쓰던 글이 사라진다"(맥 결함).
///   · 복사·신고로 **서버에 가는** 본문은 날것이어야 하고, **사람이 읽는** 자리는 이름이어야 한다.
@MainActor
@Suite(.serialized) struct V1012StickerViewContractTests {
    // MARK: - 1. 판정하는 자리는 하나다

    @Test("말풍선과 자리 말풍선이 같은 한 판정(drawable)을 지난다 · parse 를 직접 보는 자리는 없다")
    func bubblesShareOneDecision() throws {
        let code = try Self.conversation()
        #expect(code.components(separatedBy: "AingStickerArt.drawable(").count - 1 == 2,
                "그림 판정이 두 자리(말풍선 · 자리 말풍선)가 아니다")
        #expect(!code.contains("AingSticker.parse("),
                "뷰가 판정을 직접 한다 — 번들이 깨진 배포본에서 두 자리가 갈린다")

        let bubble = try Self.block(of: "private var bubbleContent", in: code)
        #expect(bubble.contains("AingStickerArt.drawable(for: line.entry.body)"), "말풍선이 판정을 안 지난다")
        #expect(bubble.contains("MessagesStickerBubble(art: drawn.art)"), "말풍선이 그림을 안 그린다")
        #expect(bubble.contains("MessagesBubbleText(text: line.entry.body"),
                "그림을 못 읽을 때 접을 글자 말풍선이 없다 — 빈 말풍선이 된다")

        let pending = try Self.block(of: "struct MessagesPendingBubbleRow", in: code)
        #expect(pending.contains("AingStickerArt.drawable(for: item.body)"), "자리 말풍선이 판정을 안 지난다")
        #expect(pending.contains("MessagesStickerBubble(art: drawn.art, isPending: true)"),
                "자리 말풍선의 그림이 흐려지지 않는다(글자 말풍선과 모양이 갈린다)")
        #expect(pending.contains("MessagesBubbleText(text: item.body"), "자리 말풍선에 글자 폴백이 없다")
    }

    // MARK: - 2. 보이스오버는 이름으로 읽는다

    @Test("줄 보이스오버는 이모티콘을 이름으로 읽는다(날것 토큰이 아니다)")
    func rowAccessibilityReadsName() throws {
        let code = try Self.conversation()
        let ax = try Self.block(of: "private var accessibilityText", in: code)
        #expect(ax.contains("AingStickerText.preview(for: entry.body)"),
                "줄 라벨이 본문을 날것으로 읽는다 — 그림 안에 구운 라벨은 children: .ignore 에 묻힌다")
        #expect(!ax.contains("+ entry.body"), "줄 라벨이 아직 본문을 날것으로 잇는다")

        let pending = try Self.block(of: "struct MessagesPendingBubbleRow", in: code)
        #expect(pending.contains("AingStickerText.preview(for: item.body)"), "자리 말풍선 라벨이 날것이다")
        #expect(!pending.contains(#"\(item.body)"#), "자리 말풍선 라벨이 아직 본문을 날것으로 끼운다")
    }

    // MARK: - 3. 복사는 원문이다

    @Test("복사(길게 누름 · 보이스오버 동작)는 원문 토큰이다 — 미리보기를 지나지 않는다")
    func copyKeepsRawBody() throws {
        let code = try Self.conversation()
        let calls = Self.arguments(of: "MessagesBubbleCopy.copy(", in: code)
        #expect(calls.sorted() == ["entry.body", "line.entry.body"],
                "복사 인자가 원문이 아니다(붙여넣어 다시 보내면 그림이 되어야 한다): \(calls)")
    }

    // MARK: - 4. 입력줄은 초안을 건드리지 않는다

    @Test("입력줄: 이모티콘 문은 sendSticker 하나 · 초안을 읽지도 쓰지도 않는다 · 닫을 길이 있다")
    func composerNeverTouchesDraft() throws {
        let code = try Self.composer()
        #expect(code.contains("AingStickerText.buttonLabel"), "이모티콘 버튼의 보이스오버 문구가 없다")
        #expect(code.contains("AingStickerText.gridTitle"), "그리드 제목이 없다")
        #expect(code.contains("AingStickerText.sendingNowNotice"), "못 보낸 까닭 한 줄이 없다")

        let pick = try Self.block(of: "private func pick(", in: code)
        #expect(pick.contains("store.sendSticker(sticker, to: peerID)"), "보내는 문이 스토어 하나가 아니다")
        #expect(pick.contains("dismiss()"), "보냈는데 시트가 안 닫힌다")
        #expect(pick.contains("AingStickerText.sendingNowNotice"),
                "못 보냈을 때 까닭을 안 세운다 — 조용히 닫히면 사용자는 나간 줄 안다")

        let sheet = try Self.block(of: "private struct MessagesStickerSheet", in: code)
        #expect(sheet.contains("ForEach(AingSticker.allCases"), "칸 순서가 열거 선언 순서가 아니다")
        #expect(sheet.contains("SheetHeader(AingStickerText.gridTitle"),
                "명시적으로 닫는 손잡이가 없다 — 맥에서 탈출구가 0 이 된 적이 있다")

        // 이모티콘 길(버튼 · 시트 · 칸) 어디에도 초안이 없다 — 맥 결함 "이모티콘을 보내면 쓰던 글이 사라진다".
        for marker in ["private func stickerButton(", "private struct MessagesStickerSheet", "private struct MessagesStickerCell"] {
            let scope = try Self.block(of: marker, in: code)
            #expect(!scope.contains("setDraft("), "\(marker) 가 초안을 쓴다")
            #expect(!scope.contains("drafts"), "\(marker) 가 초안 저장소를 본다")
            #expect(!scope.contains(".draft("), "\(marker) 가 초안을 읽는다")
        }

        let cell = try Self.block(of: "private struct MessagesStickerCell", in: code)
        #expect(cell.contains("Text(sticker.label)"), "그림이 없는 칸이 빈 칸이 된다 — 고를 수가 없다")
        #expect(cell.contains("AingStickerText.accessibilityLabel(sticker)"), "칸에 보이스오버 문구가 없다")
    }

    // MARK: - 5·6. 신고: 보는 글자와 보내는 글자

    @Test("신고 시트 인용은 이름으로 읽힌다(사람이 보는 자리)")
    func reportQuoteReadsName() throws {
        let sheets = try Self.code("Sources/CheckMobileKit/Messages/MessagesBlockSheets.swift")
        let quoted = try Self.block(of: "private func quotedMessage(", in: sheets)
        #expect(quoted.contains("Text(AingStickerText.preview(for: body))"),
                "신고 인용이 날것 토큰이다 — 신고하는 사람에게 '깨진 메시지'로 보인다")
    }

    @Test("서버로 가는 신고 본문은 원문 그대로다(운영자가 날것을 본다)")
    func reportPayloadStaysRaw() throws {
        let report = try Self.block(of: "private func reportMessage(", in: try Self.conversation())
        #expect(report.contains("messageBody: entry.body"), "신고 본문이 원문이 아니다")
        #expect(!report.contains("preview"), "신고 본문이 화면 글자로 바뀌었다 — 운영자가 원문을 못 본다")
    }

    // MARK: - 도우미

    private static func conversation() throws -> String {
        try code("Sources/CheckMobileKit/Messages/MessagesConversationView.swift")
    }

    private static func composer() throws -> String {
        try code("Sources/CheckMobileKit/Messages/MessagesComposerView.swift")
    }

    /// 주석을 걷어낸 소스(읽는 자리는 `IntegrationContractTests.code` 하나다 — 경로 기준이 두 벌이면 한쪽이 낡는다).
    private static func code(_ relative: String) throws -> String {
        try IntegrationContractTests.code(relative)
    }

    /// 선언 머리부터 **중괄호가 닫히는 곳까지**. 글자 수로 자르는 창은 다음 블록으로 새어 남의 줄을 읽는다
    /// (`GamesChessSpectateTests.block` 머리말의 그 사고 — 거기서 뮤테이션 하나가 살아남았다).
    private static func block(of marker: String, in source: String) throws -> String {
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

    /// `call` 로 시작하는 호출마다 **첫 닫는 괄호까지의 인자 글자**. 인자에 괄호가 없는 호출에만 쓴다.
    private static func arguments(of call: String, in source: String) -> [String] {
        var out: [String] = []
        var rest = Substring(source)
        while let hit = rest.range(of: call) {
            let tail = rest[hit.upperBound...]
            if let close = tail.firstIndex(of: ")") {
                out.append(String(tail[tail.startIndex..<close]))
            }
            rest = tail
        }
        return out
    }
}
