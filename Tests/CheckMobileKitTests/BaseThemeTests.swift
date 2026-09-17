import Foundation
import Testing
@testable import CheckMobileKit

/// 테마 토큰(재디자인 방향 B — `b2.html` 토큰 표): 글자 토큰의 대비 4.5:1(라이트·다크 모두 카드와 바탕 위), 틴트 칩 위 글자,
/// 채운 버튼 위 흰 글자, 메달 잉크, 이니셜 원 글자, 다크 뜻 색 = 맥 CheckTheme 숫자.
@Suite struct BaseThemeTests {
    @Test("라이트·다크: 글자로 쓰는 토큰이 카드(surface)와 바탕(background) 위에서 모두 4.5:1 이상")
    func textContrast() {
        for (name, pair) in MobileThemePalette.textTokens {
            for (mode, text, surface, background) in [
                ("라이트", pair.light, MobileThemePalette.surface.light, MobileThemePalette.background.light),
                ("다크", pair.dark, MobileThemePalette.surface.dark, MobileThemePalette.background.dark),
            ] {
                #expect(text.contrast(against: surface) >= 4.5, "\(name) \(mode) 카드 대비 \(text.contrast(against: surface))")
                #expect(text.contrast(against: background) >= 4.5, "\(name) \(mode) 바탕 대비 \(text.contrast(against: background))")
            }
        }
    }

    @Test("틴트 칩·버튼(카드 위에 겹친 틴트) 위 같은 가족 글자가 라이트·다크 모두 4.5:1 이상")
    func tintedTextContrast() {
        for (name, text, tint) in MobileThemePalette.tintedTextPairs {
            let lightBack = tint.light.composited(over: MobileThemePalette.surface.light)
            let darkBack = tint.dark.composited(over: MobileThemePalette.surface.dark)
            #expect(text.light.contrast(against: lightBack) >= 4.5, "\(name) 라이트 \(text.light.contrast(against: lightBack))")
            #expect(text.dark.contrast(against: darkBack) >= 4.5, "\(name) 다크 \(text.dark.contrast(against: darkBack))")
        }
    }

    @Test("채운 버튼(accentFill) 위 흰 글자가 라이트·다크 모두 4.5:1 · 대조: 다크 accent(밝은 파랑) 판 위 흰 글자는 모자라다")
    func accentFillContrast() {
        let pair = MobileThemePalette.onAccentFill
        #expect(pair.light.contrast(against: MobileThemePalette.accentFill.light) >= 4.5)
        #expect(pair.dark.contrast(against: MobileThemePalette.accentFill.dark) >= 4.5,
                "다크 accentFill 위 글자 대비 \(pair.dark.contrast(against: MobileThemePalette.accentFill.dark))")
        #expect(MobileThemePalette.RGB(hex: 0xFFFFFF).contrast(against: MobileThemePalette.accent.dark) < 4.5,
                "대조: 다크 accent 위 흰 글자는 모자라다(채움 판은 accentFill 이어야 하는 이유)")
        let tab = MobileThemePalette.tabSelected.dark
        let glass = MobileThemePalette.glass.dark.composited(over: MobileThemePalette.surface.dark)
        #expect(tab.contrast(against: glass) >= 4.5, "다크 선택 탭 글자 \(tab.contrast(against: glass))")
    }

    @Test("3단 글자(label3Text)는 4.5:1 · 3단 기호(label3)는 글자 목록에 없다(대조: 라이트 34% 는 글자로 모자라다)")
    func tertiaryTokensSplit() {
        #expect(!MobileThemePalette.textTokens.contains { $0.name == "label3" })
        #expect(MobileThemePalette.label3.light.contrast(against: MobileThemePalette.surface.light) < 3)
        #expect(MobileThemePalette.label3Text.dark.alpha == 0.56, "시안 다크 보정값(흰 56%)")
    }

    @Test("메달 원 안 짙은 숫자 4.5:1 · 이니셜 원 글자는 자기 틴트 원 위 4.5:1(라이트·다크)")
    func medalAndAvatarContrast() {
        let medals: [(String, MobileThemePalette.Pair, MobileThemePalette.Pair)] = [
            ("gold", MobileThemePalette.gold, MobileThemePalette.goldInk),
            ("silver", MobileThemePalette.silver, MobileThemePalette.silverInk),
            ("bronze", MobileThemePalette.bronze, MobileThemePalette.bronzeInk),
        ]
        for (name, fill, ink) in medals {
            #expect(ink.light.contrast(against: fill.light) >= 4.5, "\(name) 라이트")
            #expect(ink.dark.contrast(against: fill.dark) >= 4.5, "\(name) 다크")
        }
        let opacity = MobileThemePalette.avatarTintOpacity
        for (index, ink) in MobileThemePalette.avatarInks.enumerated() {
            let lightBack = ink.light.opacity(opacity.light).composited(over: MobileThemePalette.surface.light)
            let darkBack = ink.dark.opacity(opacity.dark).composited(over: MobileThemePalette.surface.dark)
            #expect(ink.light.contrast(against: lightBack) >= 4.5, "이니셜 \(index) 라이트 \(ink.light.contrast(against: lightBack))")
            #expect(ink.dark.contrast(against: darkBack) >= 4.5, "이니셜 \(index) 다크 \(ink.dark.contrast(against: darkBack))")
        }
    }

    @Test("이니셜 색 칸은 맥 CheckTheme.avatarColor(for:) 와 같은 해시(유니코드 스칼라 합 mod 6)")
    func avatarHashMatchesMac() {
        for name in ["민트", "보리", "라임", "모래", "코랄", "하늘", "a", "", "Zed"] {
            let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            #expect(MobileThemePalette.avatarIndex(for: name) == sum % 6, "\(name)")
        }
        #expect(MobileThemePalette.avatarInks.count == 6)
    }

    @Test("시안 토큰 표 값: 바탕·카드·다크 남색(맥 panel) · 위젯 바탕 · 게이지 그라디언트")
    func tokenTableValues() {
        #expect(MobileThemePalette.background.light.hex == 0xF2F2F7 && MobileThemePalette.background.dark.hex == 0x1A1C26)
        #expect(MobileThemePalette.surface.light.hex == 0xFFFFFF && MobileThemePalette.surface.dark.hex == 0x2B2E3D)
        #expect(MobileThemePalette.surface2.dark.hex == 0x353848)
        #expect(MobileThemePalette.accentFill.dark.hex == 0x2A74DE, "다크 채운 버튼은 한 단계 깊은 파랑(밝은 하늘색 판 금지)")
        #expect(MobileThemePalette.widgetBackground.dark.hex == 0x232633)
        #expect(MobileThemePalette.gaugeStops.map(\.hex) == [0x59E0A1, 0x54ABFF])
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
