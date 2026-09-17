import Foundation
import Testing
@testable import CheckMobileKit

/// 나 탭 w15 재디자인 계약(소스 — 주석은 걷어내고 본다). 뷰는 iOS 전용이라 macOS `swift test` 가 그릴 수 없다 — 모양을 되돌리는
/// 흔한 실수(잔디를 한 줄로 접기 · 초록 토글 · 자물쇠 가격표 · 상점 탭 막대)만 글자로 막는다.
@MainActor
@Suite("나 탭 디자인 계약(w15)")
struct MeDesignContractTests {
    @Test("기록: 잔디는 늘 격자(자리 문구로 절을 접지 않는다) · 근무·토큰 두 벌은 한 카드 안(ContributionGridPair) · 토큰은 수집 여부로만 뺀다")
    func grassAlwaysVisible() throws {
        let records = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeRecordsViews.swift")
        #expect(!records.contains("recordsPlaceholder"), "기록 절이 다시 자리 문구 한 줄로 접힌다")
        #expect(records.contains("ContributionGridPair"), "잔디 두 벌이 한 카드에 나란히 서지 않는다")
        #expect(records.contains("axis: .work") && records.contains("axis: .token"))
        #expect(records.contains("store.showsTokenGrid"), "토큰 잔디를 수집 여부 말고 다른 것으로 뺀다")
        #expect(records.contains(".blank()"), "못 받았을 때 빈 격자 자리를 지키지 않는다")
        let home = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeTab.swift")
        let stage = try #require(home.range(of: "MeStageCard(store: store)"))
        let grass = try #require(home.range(of: "MeRecordsCard(store: store)"))
        let menu = try #require(home.range(of: "MeMenuGroup(store: store)"))
        #expect(stage.lowerBound < grass.lowerBound && grass.lowerBound < menu.lowerBound, "첫 화면 순서: 무대 → 기록(잔디) → 메뉴")
    }

    @Test("무대: 착용 캐릭터 초상(원 없이 전신) · 큰 루비 칩 → 상점 · 이니셜 원 머리 없음")
    func stageUsesCharacter() throws {
        let home = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeTab.swift")
        #expect(home.contains("CharacterPortrait(id: id, mood: mood ?? .plain, size: artSize, framed: false)"))
        #expect(home.contains("RubyBalanceChip(store.rubyBalance, style: .large)"))
        #expect(!home.contains("AvatarView("), "나 탭 머리가 다시 이니셜·사진 원이다(나 = 착용 캐릭터)")
        #expect(!home.contains("RubyLabel("), "옛 루비 표기")
    }

    @Test("상점·고르기: 가격은 RubyPrice(자물쇠 없음) · 두 화면이 같은 타일 · 상점은 탭 막대 숨김 · 채운 버튼은 구매 하나")
    func shopAndPicker() throws {
        let views = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeCharacterViews.swift")
        #expect(views.contains("RubyPrice("))
        #expect(!views.contains("lock.fill"), "잠긴 캐릭터 가격을 자물쇠로 표기한다")
        #expect(views.contains(".hidesTabBar(for: .shop)"))
        #expect(views.components(separatedBy: "MeCharacterTile(id:").count - 1 == 2, "상점·고르기가 같은 타일을 쓰지 않는다")
        #expect(views.components(separatedBy: ".filled").count - 1 == 1, "상점·고르기 화면에 채운 버튼이 둘 이상이다")
        #expect(!views.contains("AingPrimaryButtonStyle"), "옛 전폭 채운 버튼")
    }

    @Test("설정·제보·프로필: 토글·제보 칩에 초록 없음 · 채운 버튼 화면당 하나")
    func meaningColors() throws {
        let settings = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeSettingsView.swift")
        #expect(!settings.contains("tint(MobileTheme.working)"), "토글 켜짐이 근무 초록이다")
        #expect(settings.contains("togglesEnabled && push.isEnabled(kind)"), "권한이 없을 때 토글이 켜진 모양으로 흐리게 선다")
        #expect(settings.components(separatedBy: "kind: .filled").count - 1 == 1)
        let feedback = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeFeedbackView.swift")
        #expect(!feedback.contains("MobileTheme.working"), "제보 상태 칩에 초록")
        #expect(feedback.contains("MeText.feedbackStatusTone"))
        let profile = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeProfileView.swift")
        #expect(profile.components(separatedBy: ".filled").count - 1 == 1, "프로필에 채운 버튼이 둘 이상이다(사진 바꾸기는 틴트)")
    }
}
