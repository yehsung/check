import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 제보(11-08, 맥 0.3.79) "아니 열심히 198자 써서 확성기 썼는데 잘렸어요" — 맥 배너 본문이 4줄까지만 보여 긴 확성기가 '…'로 잘렸다.
// 확성기 최대 글자 수는 서버 max_length 198 이다. 배너는 그 198자가 **언제나 다 보이는** 줄 수를 가져야 한다.

private let mbfMaxLength = 198
/// 배너 본문 글꼴(MegaphoneBannerView 의 본문 Text 와 같은 값).
private func mbfFont() -> NSFont { NSFont.systemFont(ofSize: 17, weight: .semibold) }

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
    let lineHeight = ceil(mbfFont().ascender - mbfFont().descender + mbfFont().leading)
    let rect = (text as NSString).boundingRect(with: NSSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin],
                                               attributes: [.font: mbfFont()])
    return Double(rect.height / lineHeight)
}

private func mbfBanner(_ body: String) -> MegaphoneBanner {
    MegaphoneBanner(messageID: nil, megaphoneID: "mbf", senderID: nil, senderName: "보낸 사람", senderAvatarURL: nil,
                    body: body, createdAt: Date(timeIntervalSince1970: 1_790_000_000))
}

@MainActor
@Suite struct MegaphoneBannerFullBodyTests {
    @Test("198자의 가장 넓은 경우도 배너 본문 폭에서 줄 수 안에 든다 — 기준선: 옛 4줄로는 모자란다")
    func maxLengthFitsTheLineLimit() {
        let width = MegaphoneBannerLayout.bodyMaxWidth
        #expect(width == 444, "본문 폭이 바뀌었다(\(width)) — 카드 여백 · 아바타 · 간격을 다시 보라")
        var widest = 0.0
        for (label, text) in mbfSamples {
            let lines = mbfLines(text, width: width)
            widest = max(widest, lines)
            print(String(format: "[megaphone-lines] %@ 198자 → %.1f줄", label, lines))
            #expect(lines <= Double(MegaphoneBannerLayout.bodyLineLimit) + 0.01,
                    "\(label) 198자가 \(lines)줄 — 배너가 \(MegaphoneBannerLayout.bodyLineLimit)줄에서 자른다")
        }
        #expect(widest > 4, "기준선: 198자 최악의 경우가 4줄 안에 들면 이 시험은 아무것도 재지 않는다(\(widest))")
    }

    @Test("실제 배너 높이: 198자 배너는 한 줄 배너보다 (줄 수 − 1) × 줄 높이만큼 높다 — 4줄에서 잘리면 모자란다")
    func renderedCardGrowsForTheWholeBody() {
        let short = MegaphoneBannerWindowController.measureCardHeight(banner: mbfBanner("안녕"), width: MegaphoneBannerLayout.maxWidth)
        // SwiftUI 가 그리는 한 줄은 20pt 다(NSFont 줄 높이 21 보다 낮다) — 하한 19pt 로 잰다. 옛 4줄이면 덧높이가 3줄(약 60pt)에 멈춘다.
        let lineHeight: CGFloat = 19
        for (label, text) in mbfSamples {
            let long = MegaphoneBannerWindowController.measureCardHeight(banner: mbfBanner(text), width: MegaphoneBannerLayout.maxWidth)
            let need = (mbfLines(text, width: MegaphoneBannerLayout.bodyMaxWidth).rounded(.up) - 1) * lineHeight
            print("[megaphone-lines] \(label): 짧은 배너 \(short)pt · 198자 배너 \(long)pt · 필요한 덧높이 \(need)pt")
            #expect(long - short >= need, "\(label): 198자 배너가 \(long - short)pt 만 높다(필요 \(need)) — 본문이 잘렸다")
        }
    }
}
