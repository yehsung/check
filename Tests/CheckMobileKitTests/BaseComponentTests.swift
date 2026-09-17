import CheckCore
import CheckMobileShared
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CheckMobileKit

/// w15 기반 부품의 순수 규칙 · 번들 에셋 · 소스 계약. 그림(렌더)은 시뮬레이터 견본(`components/1…5`)으로 따로 찍는다.
@MainActor
@Suite struct BaseComponentTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    // MARK: 에셋

    @Test("초상 12장: 6 캐릭터 × 표정 2 가 공용 번들(위젯도 읽는다)에 있고, 맥 원본과 바이트까지 같고, 알파가 있다")
    func portraitsAreBundledCopiesOfMacArt() throws {
        #expect(AingCharacterArt.knownIDs.count == 6)
        for id in AingCharacterArt.knownIDs {
            for expression in AingCharacterArt.Expression.allCases {
                let url = try #require(AingCharacterArt.portraitURL(id: id, expression: expression), "\(id)-\(expression) 초상이 번들에 없다")
                let image = try #require(AingCharacterArt.portraitImage(id: id, expression: expression), "\(id)-\(expression) 디코드 실패")
                #expect(image.width == AingCharacterArt.portraitPixelSize && image.height == AingCharacterArt.portraitPixelSize)
                #expect(image.alphaInfo != .none && image.alphaInfo != .noneSkipLast && image.alphaInfo != .noneSkipFirst, "\(id) 알파 없음")
                let mac = id == "aing"
                    ? Self.root.appendingPathComponent("Sources/check/Resources/aing-\(expression.rawValue).png")
                    : Self.root.appendingPathComponent("Sources/check/Characters/\(id)/portrait-\(expression.rawValue).png")
                // 무손실 재압축(PNG optimize)이라 파일 바이트가 아니라 **픽셀**을 대조한다.
                #expect(try Self.pixels(url) == Self.pixels(mac), "\(id)-\(expression) 이 맥 원본 그림과 다르다")
            }
        }
    }

    @Test("초상 id 목록은 앱 캐릭터 카드(MeCharacterCards)와 같고, 착용값 접기도 같다")
    func portraitIDsMatchAppCatalog() {
        #expect(AingCharacterArt.knownIDs == MeCharacterCards.knownIDs)
        for raw in [nil, "", "  ", "fox", " fox ", "ghost", "unknown-new", "aing", "FOX"] as [String?] {
            #expect(AingCharacterArt.resolvedID(raw) == MeCharacterCards.equippedID(fromServer: raw), "\(String(describing: raw))")
        }
    }

    @Test("앱 그림: 루비 원본 327px + 48/96px 축소본 · 무대용 고해상 초상 5장(420px) · 플래피 아잉 옆모습")
    func appArtIsBundled() throws {
        for name in MobileArtNames.all {
            let url = try #require(MobileArtNames.url(name), "\(name) 이 앱 번들에 없다")
            let image = try #require(Self.image(url))
            #expect(image.alphaInfo != .none, "\(name) 알파 없음")
            switch name {
            case "ruby": #expect(image.width == 327)
            case "ruby-48": #expect(image.width == 48)
            case "ruby-96": #expect(image.width == 96)
            case MobileArtNames.flappyAing: #expect(image.width == 192)
            default: #expect(image.width == 420 && image.height == 420, "\(name) 무대 그림 크기")
            }
        }
        let original = try Self.pixels(Self.root.appendingPathComponent("Sources/check/Resources/ruby.png"))
        let bundled = try Self.pixels(try #require(MobileArtNames.url("ruby")))
        #expect(original == bundled, "루비가 맥 ruby.png 와 다르다")
    }

    @Test("루비 그림 고르기: 픽셀 48 이하 48px · 96 이하 96px · 그 위 원본")
    func rubyAssetChoice() {
        #expect(RubyGlyph.assetName(pointSize: 14, displayScale: 3) == "ruby-48")
        #expect(RubyGlyph.assetName(pointSize: 17, displayScale: 3) == "ruby-96")
        #expect(RubyGlyph.assetName(pointSize: 24, displayScale: 2) == "ruby-48")
        #expect(RubyGlyph.assetName(pointSize: 24, displayScale: 3) == "ruby-96")
        #expect(RubyGlyph.assetName(pointSize: 40, displayScale: 3) == "ruby")
        #expect(RubyGlyph.assetName(pointSize: 17, displayScale: 0) == "ruby-48", "배율 0 은 1 로")
    }

    @Test("가격: 잔량이 모자랄 때만 흐림 · 잔량 모름은 모자라지 않다")
    func rubyPriceRule() {
        #expect(RubyPriceRule.isShort(price: 80, balance: 47))
        #expect(!RubyPriceRule.isShort(price: 30, balance: 47))
        #expect(!RubyPriceRule.isShort(price: 47, balance: 47), "같으면 살 수 있다")
        #expect(!RubyPriceRule.isShort(price: 80, balance: nil), "모르면 막지 않는다")
        #expect(RubyPriceRule.accessibilityText(price: 80, isShort: true) == "루비 80개, 모자라요")
    }

    @Test("기분 = 근무 상태: 표정·링 · 스냅샷 상태에서 · 무대 그림은 웃는 얼굴이 192px 를 넘을 때만")
    func characterMood() {
        #expect(CharacterMood.working.expression == .neutral && CharacterMood.working.ring == .working)
        #expect(CharacterMood.lost.expression == .neutral && CharacterMood.lost.ring == .pending)
        #expect(CharacterMood.off.expression == .negative && CharacterMood.off.ring == .off)
        #expect(CharacterMood.plain.expression == .neutral && CharacterMood.plain.ring == nil)
        #expect(CharacterMood(WidgetSnapshot.WorkState.working) == .working)
        #expect(CharacterMood(WidgetSnapshot.WorkState.disconnected) == .lost)
        #expect(CharacterMood(WidgetSnapshot.WorkState.off) == .off)
        #expect(CharacterMood.ringWidth(diameter: 25) == 2 && CharacterMood.ringWidth(diameter: 140) == 6)

        #expect(CharacterArtChoice.choose(id: "fox", expression: .neutral, pointSize: 52, displayScale: 3) == .portrait)
        #expect(CharacterArtChoice.choose(id: "fox", expression: .neutral, pointSize: 68, displayScale: 3) == .stage)
        #expect(CharacterArtChoice.choose(id: "fox", expression: .negative, pointSize: 140, displayScale: 3) == .portrait, "시무룩은 원본뿐")
        #expect(CharacterArtChoice.choose(id: "aing", expression: .neutral, pointSize: 140, displayScale: 3) == .portrait, "아잉은 192px 뿐")
        #expect(CharacterArtChoice.choose(id: "mystery", expression: .neutral, pointSize: 140, displayScale: 3) == .portrait, "모르는 id 는 아잉")
    }

    // MARK: 잔디

    @Test("잔디 단계는 나 탭(맥 ContributionGridView)과 같은 사다리")
    func contributionLevelsMatchMe() {
        for denominator in [0, 1, 4, 28_800, TokenDailyGrid.fullDayTokens] {
            for value in [-5, 0, 1, 7_200, 7_201, 14_400, 21_600, 28_800, 99_999, 12_500_000, 50_000_000, 80_000_000] {
                #expect(ContributionLevels.level(value: value, denominator: denominator) == MeText.gridLevel(value: value, denominator: denominator),
                        "\(value)/\(denominator)")
            }
        }
        #expect((0...5).map(ContributionLevels.opacity(level:)) == [0, 0.30, 0.55, 0.78, 1, 1])
    }

    @Test("잔디 칸: 원값 → 단계 · 미래 칸 nil · 빈 격자는 12주 × 7 의 0 · 활동 여부")
    func contributionGridData() {
        let values = [[0, 28_800, 7_200], [3_600]]
        let data = ContributionGridData(weeks: 2, values: values, denominator: 28_800) { week, weekday in week == 1 && weekday >= 1 }
        #expect(data.level(week: 0, weekday: 0) == 0)
        #expect(data.level(week: 0, weekday: 1) == 4)
        #expect(data.level(week: 0, weekday: 2) == 1)
        #expect(data.level(week: 0, weekday: 6) == 0, "값 없는 칸은 0")
        #expect(data.level(week: 1, weekday: 0) == 1)
        #expect(data.level(week: 1, weekday: 1) == nil, "미래")
        #expect(data.hasActivity)
        let blank = ContributionGridData.blank()
        #expect(blank.weeks == 12 && blank.levels.count == 12 && blank.levels.allSatisfy { $0 == Array(repeating: 0, count: 7) })
        #expect(!blank.hasActivity)
    }

    @Test("잔디 문구: 기록 없음은 격자 + 한 줄(섹션을 접지 않는다) · 불러오는 중 · 실패")
    func contributionGridCaptions() {
        #expect(ContributionGridPhase.ready.caption(hasActivity: true) == nil)
        #expect(ContributionGridPhase.ready.caption(hasActivity: false) == "최근 12주 기록이 없어요")
        #expect(ContributionGridPhase.loading.caption(hasActivity: false) == MobileLoadText.retrying)
        #expect(ContributionGridPhase.failed.caption(hasActivity: true) == ContributionGridText.failed)
    }

    @Test("잔디 칸 크기: 폭에 12열이 딱 맞고 · 상한 · 나 탭 카드 폭(329pt)에서 두 격자가 나란히 · 좁거나 접근성 글자면 위아래")
    func contributionGridLayout() {
        let half = (329 - ContributionGridLayout.pairSpacing) / 2
        let cell = ContributionGridLayout.cellSize(width: half, columns: 12)
        #expect(cell > 10 && cell < 11, "폰 393pt 카드 안 반 폭의 칸 \(cell)")
        let size = ContributionGridLayout.gridSize(cell: cell, columns: 12)
        #expect(abs(size.width - half) < 0.001, "칸 × 12 + 틈 × 11 = 폭")
        #expect(abs(size.height - (cell * 7 + ContributionGridLayout.spacing * 6)) < 0.001)
        #expect(ContributionGridLayout.cellSize(width: 1_000, columns: 12) == ContributionGridLayout.maximumCell)
        #expect(ContributionGridLayout.cellSize(width: 0, columns: 12) == 0)
        #expect(ContributionGridLayout.cellSize(width: 10, columns: 12) == 0, "음수가 되지 않는다")
        #expect(ContributionGridLayout.pairSideBySide(width: 329, isAccessibilitySize: false))
        #expect(!ContributionGridLayout.pairSideBySide(width: 329, isAccessibilitySize: true))
        #expect(!ContributionGridLayout.pairSideBySide(width: 200, isAccessibilitySize: false), "좁으면 쌓는다")
        // 두 격자(나란히) 높이는 폰 첫 화면에서 무대 카드 아래에 들어갈 만큼 작다(칸 약 10.8pt × 7 + 틈 6).
        #expect(size.height < 100)
    }

    // MARK: 버튼 · 막대

    @Test("버튼 3단 높이 50/40/30 · 누름 영역은 늘 44 이상 · 막대 비율 자르기")
    func buttonMetricsAndProgress() {
        #expect(AingButtonMetrics.Size.allCases.map(\.height) == [50, 40, 30])
        for size in AingButtonMetrics.Size.allCases {
            #expect(AingButtonMetrics.targetHeight(for: size) >= 44)
        }
        #expect(ProgressBarRule.clamped(-1) == 0 && ProgressBarRule.clamped(0.62) == 0.62 && ProgressBarRule.clamped(3) == 1)
        #expect(ProgressBarRule.clamped(.nan) == 0 && ProgressBarRule.clamped(.infinity) == 0)
    }

    // MARK: 소스 계약(주석을 걷어내고 본다)

    @Test("진홍 마름모(SF diamond.fill)와 진홍 루비 색 토큰이 폰 소스에서 사라졌다 · 루비는 RubyIcon 계열로만")
    func noCrimsonDiamond() throws {
        let diamonds = try IntegrationContractTests.files(containing: ["\"diamond.fill\"", "MobileTheme.ruby", "MobileThemePalette.ruby"], under: "Sources/CheckMobileKit")
        #expect(diamonds.isEmpty, "진홍 마름모·루비 색이 남았다: \(diamonds)")
        let widget = try IntegrationContractTests.files(containing: ["\"diamond.fill\""], under: "Sources/CheckWidgetsKit")
        #expect(widget.isEmpty)
        let gems = try IntegrationContractTests.files(containing: ["RubyIcon("], under: "Sources/CheckMobileKit")
        #expect(gems.contains("Sources/CheckMobileKit/Components/RubyComponents.swift"), "대조: 보석 부품을 못 찾았다")
    }

    @Test("탭 막대 숨김은 공용 수단 하나(`hidesTabBar(for:)`)가 정의한다 · 숨기는 화면 목록 넷")
    func tabBarPolicy() throws {
        #expect(Set(TabBarPolicy.Screen.allCases.map { $0.rawValue }) == ["conversation", "gomokuMatch", "shop", "miniGamePlay"])
        let chrome = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/SheetChrome.swift")
        #expect(chrome.contains("func hidesTabBar(for screen: TabBarPolicy.Screen)") && chrome.contains("toolbar(.hidden, for: .tabBar)"))
    }

    @Test("부품 견본은 DEBUG 에서만 컴파일되고 루트는 DEBUG 갈래로만 연다")
    func galleryIsDebugOnly() throws {
        let gallery = try IntegrationContractTests.code("Sources/CheckMobileKit/Components/MobileComponentsGallery.swift")
        let lines = gallery.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        #expect(lines.first == "#if DEBUG && os(iOS)" && lines.last == "#endif")
        let root = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileRootView.swift")
        let call = try #require(root.range(of: "MobileComponentsGallery(route:"))
        let before = root[root.startIndex..<call.lowerBound]
        let lastDebug = before.range(of: "#if DEBUG", options: .backwards)?.lowerBound
        let lastEnd = before.range(of: "#endif", options: .backwards)?.lowerBound
        #expect(lastDebug != nil && (lastEnd == nil || lastEnd! < lastDebug!), "견본 호출이 #if DEBUG 안에 있지 않다")
    }

    // MARK: 도우미

    static func image(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// RGBA8 프리멀티플라이드로 그린 픽셀(파일 압축과 무관한 그림 대조).
    static func pixels(_ url: URL) throws -> [UInt8] {
        let image = try #require(image(url), "\(url.lastPathComponent) 디코드 실패")
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return buffer
    }
}
