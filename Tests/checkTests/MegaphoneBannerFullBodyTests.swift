import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 제보(11-08, 맥 0.3.79) "아니 열심히 198자 써서 확성기 썼는데 잘렸어요" — 맥 배너 본문이 4줄까지만 보여 긴 확성기가 '…'로 잘렸다.
// 대표 결정(2026-11-10): "확성기가 한번에 나타낼 수 있는 글자수 넘어가면 표시를 안하는게 아니라 뒤에 내용들 볼 수 있는 버튼을 둬서
// 그거 누르면 전체 내용으로 뜨게끔 팝업창에 추가하자." → 배너는 4줄로 접고, 넘치면 [더 보기] → 누르면 전체 글로 펼친다.
// 확성기 최대 글자 수는 서버 max_length 198 이다 — 그 198자가 펼친 배너에서 언제나 다 보여야 한다.

private let mbfMaxLength = 198

/// 198자 최악의 경우들 — 띄어쓰기 있는 한글 · 띄어쓰기 없는 한글 · 자모 연타 · 영문 대문자(가장 넓다).
private let mbfSamples: [(String, String)] = {
    func fill(_ seed: String) -> String {
        var s = ""
        while s.count < mbfMaxLength { s += seed }
        return String(s.prefix(mbfMaxLength))
    }
    return [
        ("한글 띄어쓰기", fill("열심히 확성기 썼는데 잘렸어요 지난 확성기도 보고 싶어요 ")),
        ("한글 붙여쓰기", fill("갉")),
        ("자모 연타", fill("ㅋ")),
        ("영문 대문자", fill("W")),
    ]
}()

private func mbfLines(_ text: String, width: CGFloat) -> Double {
    let font = MegaphoneBannerLayout.bodyFont()
    let lineHeight = ceil(font.ascender - font.descender + font.leading)
    let rect = (text as NSString).boundingRect(with: NSSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin],
                                               attributes: [.font: font])
    return Double(rect.height / lineHeight)
}

private func mbfBanner(_ body: String) -> MegaphoneBanner {
    MegaphoneBanner(messageID: nil, megaphoneID: "mbf", senderID: nil, senderName: "보낸 사람", senderAvatarURL: nil,
                    body: body, createdAt: Date(timeIntervalSince1970: 1_790_000_000))
}

@MainActor
@Suite struct MegaphoneBannerFullBodyTests {
    @Test("넘침 판정: 198자 최악의 경우는 넓은 화면(520) · 좁은 화면(352) 모두 [더 보기] · 짧은 글 · 세 줄 글은 아니다")
    func overflowDecision() {
        #expect(MegaphoneBannerLayout.bodyMaxWidth == 444, "본문 폭이 바뀌었다 — 카드 여백 · 아바타 · 간격을 다시 보라")
        #expect(MegaphoneBannerLayout.bodyWidth(cardWidth: MegaphoneBannerLayout.maxWidth) == MegaphoneBannerLayout.bodyMaxWidth)
        for (label, text) in mbfSamples {
            #expect(MegaphoneBannerLayout.needsMore(text, cardWidth: 520), "\(label) 198자(520)에 [더 보기] 가 안 선다")
            #expect(MegaphoneBannerLayout.needsMore(text, cardWidth: 352), "\(label) 198자(352)에 [더 보기] 가 안 선다")
        }
        #expect(!MegaphoneBannerLayout.needsMore("라운지에 간식 있어요", cardWidth: 520))
        let threeLines = String(repeating: "확성기 시험 ", count: 9)          // 520 폭에서 두세 줄
        #expect(mbfLines(threeLines, width: 444) <= 3.01, "기준선: 시험 글이 세 줄을 넘는다")
        #expect(!MegaphoneBannerLayout.needsMore(threeLines, cardWidth: 520), "세 줄 글에 [더 보기] 가 섰다")
    }

    @Test("높이: 접힌 198자 배너는 4줄에서 멈추고, 펼친 198자 배너는 전체 글만큼 자란다(한 줄 배너보다 (줄 − 1) × 19pt 이상)")
    func foldedStopsAndExpandedGrows() {
        let width = MegaphoneBannerLayout.maxWidth
        let short = MegaphoneBannerWindowController.measureCardHeight(banner: mbfBanner("안녕"), width: width)
        for (label, text) in mbfSamples {
            let folded = MegaphoneBannerWindowController.measureCardHeight(banner: mbfBanner(text), width: width)
            let opened = MegaphoneBannerWindowController.measureCardHeight(banner: mbfBanner(text), width: width, expanded: true)
            let lines = mbfLines(text, width: MegaphoneBannerLayout.bodyMaxWidth).rounded(.up)
            print("[megaphone-more] \(label): 한 줄 \(short) · 접힘 \(folded) · 펼침 \(opened)pt · \(lines)줄")
            #expect(folded - short <= 3 * 21 + 2, "\(label): 접힌 배너가 4줄을 넘게 자랐다(\(folded - short)pt)")
            #expect(opened - short >= (lines - 1) * 19, "\(label): 펼친 배너가 \(opened - short)pt 만 높다 — 글이 잘렸다")
            #expect(opened > folded, "\(label): 펼쳐도 높이가 안 바뀐다")
        }
    }
}
