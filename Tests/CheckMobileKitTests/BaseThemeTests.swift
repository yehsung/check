import Foundation
import Testing
@testable import CheckMobileKit

/// 테마 토큰(SPEC-ios §3.1): 글자 토큰의 대비 4.5:1(라이트: 흰 카드·배경 / 다크: 카드), 다크 상태색 = 맥 CheckTheme 숫자.
@Suite struct BaseThemeTests {
    @Test("라이트: 글자로 쓰는 토큰이 흰 카드와 배경 위에서 모두 4.5:1 이상")
    func lightContrast() {
        let card = MobileThemePalette.card.light
        let background = MobileThemePalette.background.light
        for (name, pair) in MobileThemePalette.textTokens {
            #expect(pair.light.contrast(against: card) >= 4.5, "\(name) 라이트 카드 대비 \(pair.light.contrast(against: card))")
            #expect(pair.light.contrast(against: background) >= 4.5, "\(name) 라이트 배경 대비 \(pair.light.contrast(against: background))")
        }
    }

    @Test("다크: 글자로 쓰는 토큰이 다크 카드(#2B2E3D) 위에서 4.5:1 이상")
    func darkContrast() {
        let card = MobileThemePalette.card.dark
        for (name, pair) in MobileThemePalette.textTokens {
            #expect(pair.dark.contrast(against: card) >= 4.5, "\(name) 다크 대비 \(pair.dark.contrast(against: card))")
        }
    }

    @Test("accent 로 채운 버튼의 글자(onAccent)가 라이트·다크 모두 4.5:1 이상")
    func accentFillContrast() {
        let pair = MobileThemePalette.onAccent
        #expect(pair.light.contrast(against: MobileThemePalette.accent.light) >= 4.5)
        #expect(pair.dark.contrast(against: MobileThemePalette.accent.dark) >= 4.5,
                "다크 accent 위 글자 대비 \(pair.dark.contrast(against: MobileThemePalette.accent.dark))")
        #expect(MobileThemePalette.RGB(hex: 0xFFFFFF).contrast(against: MobileThemePalette.accent.dark) < 4.5,
                "대조: 다크 accent 위 흰 글자는 모자라다(이 토큰이 필요한 이유)")
    }

    @Test("대조군: 대비 계산이 실제로 가른다(흰 위 흰 = 1, 흰 위 검정 = 21)")
    func contrastFormulaControl() {
        let white = MobileThemePalette.RGB(hex: 0xFFFFFF)
        let black = MobileThemePalette.RGB(hex: 0x000000)
        #expect(abs(white.contrast(against: white) - 1) < 0.001)
        #expect(abs(white.contrast(against: black) - 21) < 0.001)
        #expect(MobileThemePalette.RGB(hex: 0x59E0A1).contrast(against: white) < 4.5, "맥 다크 초록을 라이트에 그대로 쓰면 안 된다")
    }

    @Test("다크 상태색은 맥 CheckTheme.swift 의 숫자와 같다(소스 대조)")
    func darkStatusColorsMatchMac() throws {
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Sources/CheckCore/CheckTheme.swift"), encoding: .utf8)
        let pairs: [(String, MobileThemePalette.RGB)] = [
            ("working", MobileThemePalette.working.dark), ("offWork", MobileThemePalette.offWork.dark),
            ("pending", MobileThemePalette.pending.dark), ("accent", MobileThemePalette.accent.dark),
            ("danger", MobileThemePalette.danger.dark), ("aiToken", MobileThemePalette.aiToken.dark),
        ]
        for (name, rgb) in pairs {
            let line = source.split(separator: "\n").first { $0.contains("static let \(name) = Color(") }
            let text = try #require(line.map(String.init), "\(name) 줄을 CheckTheme.swift 에서 못 찾았다")
            #expect(text.contains("red: \(format(rgb.r))") && text.contains("green: \(format(rgb.g))") && text.contains("blue: \(format(rgb.b))"),
                    "\(name): 맥 \(text) ≠ 폰 \(rgb)")
        }
    }

    @Test("상대 시각 문구(KST)")
    func relativeTime() {
        let now = MobileClockFixtures.kst(2026, 9, 17, 14, 5)
        #expect(MobileRelativeTime.text(for: now.addingTimeInterval(-30), now: now) == "방금")
        #expect(MobileRelativeTime.text(for: now.addingTimeInterval(120), now: now) == "방금", "미래는 방금으로 접는다")
        #expect(MobileRelativeTime.text(for: now.addingTimeInterval(-5 * 60), now: now) == "5분 전")
        #expect(MobileRelativeTime.text(for: now.addingTimeInterval(-3 * 3600), now: now) == "3시간 전")
        #expect(MobileRelativeTime.text(for: MobileClockFixtures.kst(2026, 9, 16, 23, 50), now: now) == "어제")
        #expect(MobileRelativeTime.text(for: MobileClockFixtures.kst(2026, 9, 1, 9, 0), now: now) == "9월 1일")
        #expect(MobileRelativeTime.text(for: MobileClockFixtures.kst(2025, 12, 31, 9, 0), now: now) == "2025. 12. 31.")
        #expect(MobileRelativeTime.headerDate(now) == "9월 17일 목")
        #expect(MobileRelativeTime.headerDate(MobileClockFixtures.kst(2026, 9, 17, 0, 30)) == "9월 17일 목", "KST 자정 직후도 그 날짜")
    }

    private func format(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text += "0" }
        return text
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}

enum MobileClockFixtures {
    static func kst(_ y: Int, _ m: Int, _ d: Int, _ hh: Int, _ mm: Int) -> Date {
        var components = DateComponents()
        components.year = y; components.month = m; components.day = d; components.hour = hh; components.minute = mm
        return MobileRelativeTime.kst.date(from: components)!
    }
}
