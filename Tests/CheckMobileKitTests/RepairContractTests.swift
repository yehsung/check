import Foundation
import Testing
@testable import CheckMobileKit
@testable import CheckWidgetsKit

/// w15 디자인 검증(§3-3)이 찾은 결함의 수리 계약. 뷰는 iOS 전용이라 macOS `swift test` 가 그릴 수 없다 —
/// 되돌아가기 쉬운 자리만 **소스 글자와 토큰 숫자**로 묶는다(주석은 걷어내고 본다).
@MainActor
@Suite("w15 수리 계약")
struct RepairContractTests {
    // MARK: medium 2 — 비활성 채운 버튼

    @Test("비활성 버튼은 라이트·다크 모두 fill2 + label2 — 옅은 파랑 판 위 흰 글자(1.1~1.3:1)로 돌아가지 않는다")
    func disabledButtonReadsInBothSchemes() throws {
        let buttons = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/AingButtons.swift")
        #expect(buttons.contains("let disabledFill = !isEnabled && kind != .plain"),
                "비활성 판이 다시 화면 모드로 갈린다")
        #expect(!buttons.contains("colorScheme == .dark && kind != .plain"), "라이트만 흐리게 하던 갈래가 되살아났다")
        // 카드 위 · 화면 바탕 위 둘 다 4.5:1.
        for (name, surface) in [("카드", MobileThemePalette.surface), ("바탕", MobileThemePalette.background)] {
            let lightBack = MobileThemePalette.fill2.light.composited(over: surface.light)
            let darkBack = MobileThemePalette.fill2.dark.composited(over: surface.dark)
            #expect(MobileThemePalette.label2.light.contrast(against: lightBack) >= 4.5,
                    "\(name) 라이트 \(MobileThemePalette.label2.light.contrast(against: lightBack))")
            #expect(MobileThemePalette.label2.dark.contrast(against: darkBack) >= 4.5,
                    "\(name) 다크 \(MobileThemePalette.label2.dark.contrast(against: darkBack))")
        }
    }

    // MARK: 낮음 3 — 틴트 행 안 칩

    @Test("내 행(틴트) 안 파랑 칩은 칠하지 않는다 — 대조: 틴트 위 틴트는 라이트도 4.5:1 에 못 미친다")
    func meChipOnTintedRowIsOutlined() throws {
        // 내 행 칠(`RankRowSurface.highlightFill`)은 iOS 전용 뷰라 숫자를 여기서 다시 적고 소스와 대조한다.
        let highlightFill = 0.06
        let rank = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/MobileRankComponents.swift")
        #expect(rank.contains("highlightFill = \(highlightFill)"), "내 행 칠 값이 바뀌었다 — 이 테스트의 숫자도 맞춰라")
        let row = MobileThemePalette.accent.light
            .opacity(highlightFill)
            .composited(over: MobileThemePalette.surface.light)
        let chip = MobileThemePalette.accentTint.light.composited(over: row)
        #expect(MobileThemePalette.accent.light.contrast(against: chip) < 4.5,
                "대조가 깨졌다(칠한 칩이 통과한다면 테두리형이 필요 없다): \(MobileThemePalette.accent.light.contrast(against: chip))")
        #expect(MobileThemePalette.accent.light.contrast(against: row) >= 4.5,
                "테두리형 칩 글자(행 바탕 위) \(MobileThemePalette.accent.light.contrast(against: row))")
        let darkRow = MobileThemePalette.accent.dark
            .opacity(highlightFill)
            .composited(over: MobileThemePalette.surface.dark)
        #expect(MobileThemePalette.accent.dark.contrast(against: darkRow) >= 4.5,
                "다크 테두리형 칩 글자 \(MobileThemePalette.accent.dark.contrast(against: darkRow))")
    }

    // MARK: medium 4 — 탭 막대 '나'

    @Test("'나' 탭 기호는 착용 캐릭터 초상(SF 기호는 그림이 없을 때만)")
    func meTabUsesCharacterPortrait() throws {
        let root = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileRootView.swift")
        #expect(root.contains("CharacterTabIcon.image("), "탭 막대가 다시 사람 기호로 돌아갔다")
        #expect(root.contains("model.now.displayedCharacterID") && root.contains("model.now.displayedMood"),
                "탭 기호가 착용 캐릭터·근무 상태를 따라가지 않는다")
    }

    @Test("탭 아이콘은 초상 원본을 그대로 그린다(탭 막대가 제 색으로 칠하지 않게)")
    func meTabIconKeepsOriginalColors() throws {
        let icon = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/CharacterTabIcon.swift")
        #expect(icon.contains("withRenderingMode(.alwaysOriginal)"))
        #expect(icon.contains("isDark") && icon.contains("scale"), "모드·배율이 캐시 키에 없으면 화면 모드를 따라가지 못한다")
    }

    // MARK: medium 1 — 기권 확인

    @Test("기권 확인은 불투명 시트(알림창 금지 — 나무판 색을 빨아들여 1.9:1 이었다)")
    func resignConfirmIsOpaqueSheet() throws {
        let match = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuMatch.swift")
        #expect(match.contains("AingConfirmSheet("), "기권 확인이 공용 확인 시트를 쓰지 않는다")
        #expect(!match.contains(".alert("), "기권 확인이 다시 시스템 알림창이다")
        let chrome = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/SheetChrome.swift")
        #expect(chrome.contains("presentationBackground(MobileTheme.surface)"), "확인 시트 바탕이 불투명하지 않다")
        #expect(chrome.contains("kind: .destructive") && chrome.contains("kind: .gray"),
                "확인 시트 버튼이 앱 토큰(dangerTint 위 danger)이 아니다")
        // dangerTint 위 danger 는 4.5:1(시스템 빨강 대신 쓰는 이유).
        let lightBack = MobileThemePalette.dangerTint.light.composited(over: MobileThemePalette.surface.light)
        let darkBack = MobileThemePalette.dangerTint.dark.composited(over: MobileThemePalette.surface.dark)
        #expect(MobileThemePalette.danger.light.contrast(against: lightBack) >= 4.5)
        #expect(MobileThemePalette.danger.dark.contrast(against: darkBack) >= 4.5)
    }

    // MARK: medium 5 · 낮음 4 — 내비 머리

    @Test("스크롤한 내용이 접힌 내비 머리 뒤로 비치지 않는다(앱 전체에 한 번)")
    func navigationEdgeIsHard() throws {
        let root = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileRootView.swift")
        #expect(root.contains(".opaqueNavigationEdge()"), "앱 루트가 머리 가장자리를 끊지 않는다")
        let chrome = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/SheetChrome.swift")
        #expect(chrome.contains("scrollEdgeEffectStyle(.hard, for: .top)"))
        #expect(chrome.contains("toolbarBackground(.visible, for: .navigationBar)"), "iOS 18 갈래가 없다")
    }

    // MARK: medium 6 — 큰 글자 대국

    @Test("큰 글자: 판은 보이는 높이에 맞춰 줄고, 접힌 대화 서랍은 머리만 남는다('내 차례 · 남은 초'를 가리지 않게)")
    func bigTypeKeepsTurnCardVisible() throws {
        let match = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuMatch.swift")
        #expect(match.contains("func boardSide(in visible: CGSize)"), "판 크기가 보이는 높이를 모른다")
        #expect(match.contains("typeSize.isAccessibilitySize ? 0.40 : 0.52"))
        let chat = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuChat.swift")
        #expect(chat.contains("var isCompact: Bool { typeSize.isAccessibilitySize && !isExpanded }"))
        #expect(chat.contains("if !isCompact {"), "접근성 글자에서 접힌 서랍이 최근 말·빠른 문구까지 그린다")
        #expect(chat.contains("if isCompact { keyboardButton }"), "접힌 서랍에서 쓰는 길이 사라졌다")
    }

    // MARK: medium 7 — 상점 '고름' vs '착용 중'

    @Test("타일 표시는 뜻마다 다른 모양(고름 = 틴트 바탕 · 착용 = 테두리 + 체크) · 잠김 흐림은 두 화면 모두 없다")
    func tileMarksDifferByMeaning() throws {
        let views = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeCharacterViews.swift")
        #expect(views.contains("enum Mark") && views.contains("case picked") && views.contains("case equipped"))
        #expect(views.contains("mark == .picked ? MobileTheme.accent : MobileTheme.label"), "고른 타일 이름이 파랑이 아니다")
        #expect(views.contains("if mark == .picked { shape.fill(MobileTheme.accentTint) }"), "고름이 틴트 바탕으로 서지 않는다")
        #expect(views.contains("if mark == .equipped {"), "체크·테두리가 착용 전용이 아니다")
        #expect(!views.contains("isSelected:"), "고름과 착용이 다시 한 깃발이다")
        #expect(!views.contains("saturation(isLocked"), "고르기에서만 그림을 흐리게 그린다(같은 데이터가 화면마다 다르다)")
    }

    // MARK: 낮음 1 — 위젯 투명·틴트 글자

    @Test("투명·틴트 위젯 글자는 불투명도로 위계를 나누지 않는다(보조 글자 1.0)")
    func accentedWidgetTextIsFullOpacity() {
        #expect(AingWidgetPalette.Accented.secondaryText == 1.0, "보조 글자를 다시 흐리게 한다(투명 모드 1.8:1)")
        #expect(AingWidgetPalette.Accented.tertiaryText >= 0.8, "끝난 할 일 글자도 읽히는 선 위에")
        #expect(AingWidgetPalette.Accented.fill >= 0.3, "칩 바탕이 글자 뒤를 받치지 못한다")
        #expect(AingWidgetPalette.Accented.track < 0.5, "트랙이 진하면 채운 쪽(1.0)과 갈리지 않는다")
    }
}
