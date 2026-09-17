import Foundation
import Testing

@testable import CheckMobileKit

/// 통합 I 가 탭 폴더에서 Components 로 **승격한 부품**이 다시 갈라지지 않게 묶는다.
///
/// 재디자인을 여섯 갈래로 나눠 그리자, 두 탭 이상이 같은 부품을 각자 만들었다(비평 4 "같은 데이터 다른 부품"):
/// 어제 1등 행, 순위 한 행, 이름 줄, 이름 줄 키 18pt 칩, 도구 막대 루비 알약, 오른쪽에 뷰가 오는 섹션 머리.
/// 여기서 지키는 건 하나다 — **그 부품을 그리는 코드가 Components 한 곳에만 있고, 탭은 그것을 쓴다**.
@MainActor
@Suite("승격 부품(통합 I)")
struct PromotedComponentsTests {
    /// 승격 부품이 사는 곳.
    static let rankBoardParts = "Sources/CheckMobileKit/Components/RankBoardParts.swift"
    static let personComponents = "Sources/CheckMobileKit/Components/PersonComponents.swift"
    static let rubyComponents = "Sources/CheckMobileKit/Components/RubyComponents.swift"
    static let insetGroup = "Sources/CheckMobileKit/Components/InsetGroup.swift"
    static let rankComponents = "Sources/CheckMobileKit/Components/MobileRankComponents.swift"

    @Test("어제 1등·순위 행·행 치수는 Components 한 곳에서 정의되고, 순위 탭과 게임 탭이 그것을 쓴다")
    func rankBoardPartsArePromoted() throws {
        let parts = try IntegrationContractTests.code(Self.rankBoardParts)
        for declaration in ["struct ChampionRow", "struct RankRow<", "struct RankRowBody<", "struct RankRowFace",
                            "struct RankRowScaledMetrics", "enum RankRowMetrics"] {
            #expect(parts.contains(declaration), "승격 부품 선언이 사라졌다: \(declaration)")
        }
        // 같은 이름의 부품을 다시 만든 탭이 없다(승격 파일 밖에 선언이 없다).
        for declaration in ["struct ChampionRow", "struct RankRow<", "struct RankRowBody<", "struct RankRowFace"] {
            let owners = try IntegrationContractTests.files(containing: [declaration], under: "Sources/CheckMobileKit")
            #expect(owners == [Self.rankBoardParts], "\(declaration) 이 두 곳에 있다: \(owners)")
        }
        // 어제 1등을 그리는 곳은 승격 부품 하나 — 두 탭은 문구·점수만 넘긴다.
        let crownDrawers = try IntegrationContractTests.files(containing: ["CrownBadge()"], under: "Sources/CheckMobileKit")
        #expect(crownDrawers.sorted() == [Self.rankBoardParts, "Sources/CheckMobileKit/Components/MobileComponentsGallery.swift"].sorted()
                || crownDrawers == [Self.rankBoardParts],
                "왕관 행을 Components 밖에서 또 그린다: \(crownDrawers)")
        let championCallers = try IntegrationContractTests.files(containing: ["ChampionRow("], under: "Sources/CheckMobileKit")
        for folder in ["Rankings", "Games"] {
            #expect(championCallers.contains { $0.hasPrefix("Sources/CheckMobileKit/\(folder)/") },
                    "\(folder) 탭이 공용 어제 1등 행을 쓰지 않는다")
        }
    }

    @Test("이름 줄은 공용 `PersonName` 한 벌 — 탭이 제 이름 줄을 다시 만들지 않는다")
    func nameLineIsPromoted() throws {
        let person = try IntegrationContractTests.code(Self.personComponents)
        #expect(person.contains("enum Chip") && person.contains("case accent(String)") && person.contains("case muted(String)"),
                "이름 줄 칩(우리 팀·비공개)이 공용 부품으로 들어오지 않았다")
        #expect(person.contains("onTint && colorScheme == .dark"),
                "틴트 행 안 파랑 칩이 다크에서 테두리형으로 바뀌지 않는다(틴트 위 틴트 3.5:1)")
        // '나' 칩을 그리는 곳은 공용 이름 줄 하나(탭이 제 칩·제 이름 줄을 다시 만들지 않는다 — 비평 4b).
        // 견본 화면(Gallery)은 부품을 보여 주는 자리라 예외다.
        let meChipUsers = try IntegrationContractTests.files(containing: ["MeChip("], under: "Sources/CheckMobileKit")
            .filter { !$0.hasSuffix("MobileComponentsGallery.swift") }
        #expect(meChipUsers == [Self.personComponents], "'나' 칩을 Components 밖에서 또 붙인다: \(meChipUsers)")
        // 순위 탭의 이름 줄은 공용 부품에 그대로 넘긴다(자기 배지·칩을 다시 조립하지 않는다).
        let rankingsTab = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsTab.swift")
        #expect(rankingsTab.contains("struct RankingsNameLine") && rankingsTab.contains("PersonName("),
                "순위 탭 이름 줄이 공용 부품을 거치지 않는다")
        #expect(!rankingsTab.contains("CenterBadge("), "순위 탭이 센터 배지를 다시 직접 붙인다")
    }

    @Test("이름 줄 키 18pt 칩은 `AingChip.Size.small` 하나 — 탭이 제 18pt 칩을 만들지 않는다")
    func smallChipIsPromoted() throws {
        let chip = try IntegrationContractTests.code(Self.rankComponents)
        #expect(chip.contains("enum Size") && chip.contains("case small"), "칩 높이 두 벌이 공용 부품에 없다")
        #expect(chip.contains("case .small: return 18") && chip.contains("case .regular: return 22"),
                "칩 높이 18/22 가 공용 부품 밖으로 나갔다")
        // 18pt 캡슐을 직접 만든 곳은 Components 안뿐이다(`CenterBadge` — 옛 `RankingsSmallChip` 같은 탭 갈래가 다시 생기지 않게).
        let handmade = try IntegrationContractTests.files(containing: ["frame(minHeight: 18)"], under: "Sources/CheckMobileKit")
        #expect(handmade.allSatisfy { $0.hasPrefix("Sources/CheckMobileKit/Components/") },
                "18pt 칩을 탭 폴더에서 손으로 또 만든다: \(handmade)")
    }

    @Test("도구 막대 루비 알약은 `RubyBalanceChip(.toolbar)` 하나 — 유리 이중 겹침 분기가 탭마다 갈리지 않는다")
    func toolbarRubyPillIsPromoted() throws {
        let ruby = try IntegrationContractTests.code(Self.rubyComponents)
        #expect(ruby.contains("glass, toolbar"), "도구 막대 style 이 없다")
        #expect(ruby.contains("if #available(iOS 26, *)") && ruby.contains("GlassBackground(shape: Capsule())"),
                "iOS 26 유리 이중 겹침 분기가 공용 부품 안에 없다")
        // 잔량 알약을 도구 막대에 두는 두 화면(게임 탭·상점)이 그 부품을 쓰고, 유리 캡슐을 자기 손으로 두르지 않는다.
        for file in ["Sources/CheckMobileKit/Games/GamesComponents.swift", "Sources/CheckMobileKit/Me/MeCharacterViews.swift"] {
            let code = try IntegrationContractTests.code(file)
            #expect(code.contains("style: .toolbar"), "\(file) 가 공용 도구 막대 알약을 쓰지 않는다")
            #expect(!code.contains("GlassBackground(shape: Capsule())"),
                    "\(file) 가 잔량 알약에 유리 캡슐을 다시 손으로 두른다(iOS 26 이중 겹침)")
        }
    }

    @Test("오른쪽에 뷰가 오는 섹션 머리는 `SectionHeaderBar` 하나")
    func sectionHeaderBarIsPromoted() throws {
        let group = try IntegrationContractTests.code(Self.insetGroup)
        #expect(group.contains("struct SectionHeaderBar<Trailing: View>"), "trailing 뷰 빌더 섹션 머리가 Components 에 없다")
        let owners = try IntegrationContractTests.files(containing: ["struct SectionHeaderBar"], under: "Sources/CheckMobileKit")
        #expect(owners == [Self.insetGroup], "섹션 머리가 두 곳에 있다: \(owners)")
        let rankings = try IntegrationContractTests.code("Sources/CheckMobileKit/Rankings/RankingsTab.swift")
        #expect(rankings.contains("SectionHeaderBar(title, topPadding: 18)"), "순위 판 머리가 공용 부품을 쓰지 않는다")
    }
}
