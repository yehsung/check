import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.15 캐릭터 선택 패널 (팝오버 안)
//
// 이 스위트가 지키는 것은 **초록인 채로 틀릴 수 있는** 자리들이다:
//  ① 새 패널 깃발이 `isSubPanelOpen` 에 들어갔다 — 빠지면 토큰 소모량 행이 패널과 함께 그려져 창이
//     700pt 상한을 넘고 푸터(로그아웃/앱 종료)가 화면 밖으로 잘린다. 그 순간 사용자는 로그아웃할 길을 잃는다.
//     (`CheckMenuRenderTests.everyPanelFlagIsCountedInTheTokenRowGate` 가 그 두 수를 세지만, **창 높이를
//      실제로 재지는 않는다** — 여기서 픽셀로 잰다.)
//  ② 헤더가 **1pt 도 안 높아졌다**. 마스코트를 버튼으로 감싸며 패딩이 한 겹 붙으면 아무 테스트도 안
//     빨개진 채 창 높이 예산이 갉아먹힌다.
//  ③ 카드가 **픽셀로 실제로 그려진다**(Menu/Picker 의 노란 상자가 아니다).
//  ④ 누르면 **저장된다**. 저장 호출이 빠져도 로컬 카드는 옮겨 갈 수 있어 눈으로는 멀쩡하다.
//  ⑤ 관리자 게이트가 **없다** — 일반 사용자도 연다(중간 상태, 사용자 확인).
//  ⑥ 다른 패널과 상호 배타 — 양방향.
//
// ⚠️ `UserDefaults.standard` 에 한 글자도 쓰지 않는다. 같은 순간 병렬로 아잉 픽셀을 재는 스위트가 있어서,
//    표준 도메인에 선택값을 남기면 그쪽이 간헐적으로 빨개진다(V0316CharacterPickerTests 와 같은 규약).

// MARK: - ① 패널이 열려도 창은 700pt 상한 안이다

@MainActor
@Test
func 캐릭터_패널이_열려도_창이_상한_안에_선다() throws {
    let suite = cpSuite()
    defer { cpDrop(suite) }

    // 최악 조합: 팀원 8명 + 실제로 그려지는 토큰 행 + 배너 + 목표 편집 행.
    let store = cpTeamStore(members: 8, tokenUsage: cpSeededTokenStore())
    store.retro = cpSampleRetro()
    store.showsRetroBanner = true
    store.toggleCharacterPanel()
    #expect(store.isCharacterPanelVisible)

    let height = try #require(cpPopoverHeight(
        CheckMenuView(store: store, previewClipsOverflowList: true,
                      previewGoalEditing: true, characterDefaults: suite.defaults)
    ))
    #expect(height <= 700.0, "캐릭터 패널 최악 조합이 700pt 상한을 넘었다: \(height)pt")

    // ★ 토큰 소모량 행이 **함께 그려지지 않는다**는 사실을 숫자로 남긴다. 깃발을 게이트에서 빼면
    //   이 행이 살아나 창이 그만큼(53pt) 높아진다 — 그 회귀를 여기서 픽셀로 잡는다.
    #expect(CheckMenuView.subPanelFlagNames.contains("isCharacterPanelVisible"),
            "새 패널 깃발이 토큰 행 게이트 목록에 없다")
}

// MARK: - ② 헤더가 1pt 도 안 높아졌다

@MainActor
@Test
func 마스코트를_버튼으로_바꿔도_헤더가_안_높아진다() throws {
    // 진입점은 46×46 마스코트를 `Button` 으로 감싼 것이다. 라벨 크기를 그대로 쓰는 `.plain` 스타일이고
    // 표식은 전부 `.overlay`(크기 영향 없음)라 **헤더 높이가 그대로여야 한다**.
    // 감싸며 패딩이 한 겹이라도 붙으면 여기서 즉시 갈린다.
    let snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 42)
    let bare = try #require(cpHeight(
        CheckMascotView(snapshot: snapshot).frame(width: 46, height: 46), width: 46
    ))
    let store = cpTeamStore(members: 3)
    store.snapshot = snapshot
    let wrapped = try #require(cpHeight(CharacterEntryButton(store: store), width: 46))
    #expect(wrapped == bare, "마스코트 버튼이 \(wrapped)pt 다 — 맨 마스코트는 \(bare)pt")
    #expect(wrapped == 46.0)

    // 팝오버 전체로도 한 번 더 잰다. 헤더 카드가 자라면 창이 그만큼 높아진다.
    let full = try #require(cpPopoverHeight(CheckMenuView(store: cpTeamStore(members: 4))))
    #expect(full <= 700.0, "홈 화면이 \(full)pt 다")
}

// MARK: - ③ 카드가 픽셀로 그려진다 (Menu/Picker 의 노란 상자가 아니다)

@MainActor
@Test
func 카드가_노란_상자가_아니라_초상화와_이름으로_그려진다() throws {
    let suite = cpSuite()
    defer { cpDrop(suite) }
    let bitmap = try cpPanelBitmap(defaults: suite.defaults)

    // ImageRenderer 는 Menu·Picker·TextField 를 못 그리고 자리에 (255,204,0) 상자를 박는다.
    // 그 상자가 하나라도 있으면 이 패널은 스냅샷에서 **보이지 않는 것과 같다**.
    #expect(cpYellowPixelCount(bitmap) == 0,
            "카드 자리에 '못 그림' 노란 상자가 있다 — Button + Image 로만 만들어야 한다")

    // 초상화가 실제로 칠해졌는지. 캐릭터 그림은 이 화면의 회색 팔레트에 없는 **유채색 덩어리**다.
    #expect(cpColorfulPixelCount(bitmap) > 2_000,
            "초상화가 안 보인다(유채색 픽셀 \(cpColorfulPixelCount(bitmap))개) — 카드가 빈 상자다")

    // 고른 카드의 파란 테두리·체크 배지. 없으면 "무엇을 고르고 있는지 안 보이는 선택기"다.
    #expect(cpAccentPixelCount(bitmap) > 150,
            "선택됨 표시가 안 보인다(강조색 픽셀 \(cpAccentPixelCount(bitmap))개)")

    cpSave(bitmap, name: "v0316-character-panel.png")
}

// MARK: - ④ 고르면 저장되고 되그릴 쪽에 알린다

@MainActor
@Test
func 패널에서_고르면_저장된다() throws {
    let suite = cpSuite()
    defer { cpDrop(suite) }

    let catalog = CheckCharacter3DScene.catalog
    let target = try #require(catalog.allIDs.first { $0 != CharacterCatalog.builtInAingID },
                              "번들에 아잉 말고 캐릭터가 없다 — 이 스위트는 에셋이 있어야 의미가 있다")
    let selection = CharacterSelection(defaults: suite.defaults, catalog: catalog)
    let broadcast = CharacterSelectionBroadcast()

    #expect(CheckCharacterPicker.choose(target, selection: selection, broadcast: broadcast))
    #expect(suite.defaults.string(forKey: CharacterSelection.defaultsKey) == target)
    #expect(broadcast.revision == 1)

    // 카드 버튼이 **그 함수를 실제로 부르는지**는 소스로 못 박는다. ③·④ 가 전부 초록인데 버튼이
    // 저장 경로를 안 부르는 조합(먹통 선택기)이 만들어진다. 주석은 걷어내고 센다(하우스 규칙).
    let source = cpStripped(try cpSource("CheckCharacterPanel.swift"))
    #expect(source.contains("if CheckCharacterPicker.choose(id, selection: selection, broadcast: broadcast) { selectedID = id }"),
            "카드가 저장 경로를 안 부르거나, 저장 성공 여부와 무관하게 움직인다")
    // 목록 순서의 주인은 카탈로그다. 뷰에서 다시 정렬하면 "아잉 먼저"가 두 곳에 적힌다.
    #expect(source.contains("let ids = catalog.allIDs"), "패널이 catalog.allIDs 를 그대로 쓰지 않는다")
    #expect(!source.contains("catalog.allIDs.sorted()"), "뷰에서 목록을 다시 정렬하지 마라")
    // 픽셀아트는 이웃 보간으로 그린다 — `.high` 면 격자가 뭉개진다(앱 재질 필터 `.nearest` 와 같은 짝).
    #expect(source.contains("interpolation(isPixelArt ? .none : .high)"),
            "픽셀아트 초상이 이웃 보간으로 안 그려진다")
    #expect(source.contains("isPixelArt: manifest?.pixelArt == true"),
            "픽셀아트 판정의 출처가 매니페스트가 아니다")
    // ★ **`Image(nsImage:)` 는 `.interpolation` 을 무시한다**(실측). CGImage 로 내려 그려야만 먹는다 —
    //   되돌리면 위 두 줄은 그대로 초록인 채 픽셀아트가 조용히 뭉개진다.
    #expect(source.contains("Image(decorative: cgImage, scale: 1)"),
            "초상이 CGImage 로 안 그려진다 — Image(nsImage:) 는 interpolation 을 무시한다")
}

// MARK: - ④-b 픽셀아트 보간이 **실제로 픽셀을 바꾼다**

@MainActor
@Test
func 픽셀아트_초상은_이웃_보간으로_그려진다() throws {
    // 소스 계약(④)만으로는 `.interpolation(...)` 이 **장식**일 가능성이 남는다 — 두 값이 같은 그림을
    // 내면 그 분기는 영원히 초록인 채 아무 일도 안 한다(기준선이 같은 비교는 테스트가 아니다).
    // 그래서 같은 초상을 두 보간으로 굽고 **픽셀이 실제로 갈리는지** 본다.
    let id = CharacterCatalog.builtInAingID
    let smooth = try #require(cpBitmap(
        CharacterPortrait(characterID: id, isPixelArt: false).frame(width: 52, height: 52), width: 52
    ))
    let pixel = try #require(cpBitmap(
        CharacterPortrait(characterID: id, isPixelArt: true).frame(width: 52, height: 52), width: 52
    ))
    #expect(smooth.representation(using: .png, properties: [:])
            != pixel.representation(using: .png, properties: [:]),
            "두 보간이 같은 픽셀을 낸다 — pixelArt 분기가 장식이다")
    // 둘 다 실제로 그려지긴 했는지(빈 그림 두 장이 '다르다'로 통과하는 일을 막는다).
    #expect(cpColorfulPixelCount(smooth) > 300)
    #expect(cpColorfulPixelCount(pixel) > 300)
}

// MARK: - ⑤ 관리자 전용이 아니다

@MainActor
@Test
func 캐릭터_패널은_누구나_연다() throws {
    // 상점이 붙으면 카드에 잠금·가격이 얹힌다. **지금은 전원이 모든 캐릭터를 고를 수 있다**(중간 상태).
    // 게이트가 몰래 생기면 이 두 렌더의 높이가 갈린다.
    let suite = cpSuite()
    defer { cpDrop(suite) }

    let plain = cpTeamStore(members: 4)
    plain.ultraUnlimited = false
    plain.toggleCharacterPanel()
    let admin = cpTeamStore(members: 4)
    admin.ultraUnlimited = true
    admin.toggleCharacterPanel()

    let plainHeight = try #require(cpPopoverHeight(CheckMenuView(store: plain, characterDefaults: suite.defaults)))
    let adminHeight = try #require(cpPopoverHeight(CheckMenuView(store: admin, characterDefaults: suite.defaults)))
    #expect(plainHeight == adminHeight,
            "일반 \(plainHeight)pt · 관리자 \(adminHeight)pt — 캐릭터 패널에 관리자 게이트가 생겼다")

    // 소스로도 못 박는다(높이 비교가 흔들려도 이 줄은 정확하다).
    let menu = cpStripped(try cpSource("CheckMenuView.swift"))
    #expect(menu.contains("} else if store.isCharacterPanelVisible { CheckCharacterPanel("),
            "패널 분기가 사라졌거나 조건이 달라졌다")
    #expect(!menu.contains("store.ultraUnlimited { CheckCharacterPanel"),
            "캐릭터 패널이 관리자 게이트 뒤로 들어갔다")

    // 설정 창의 칩 줄은 **관리자 게이트를 그대로 달고 있어야 한다**(관리자용 빠른 경로 — 건드리면
    // V0316CharacterPickerTests 가 빨개진다).
    let settings = cpStripped(try cpSource("CheckSettingsView.swift"))
    #expect(settings.contains("if store.ultraUnlimited { PanelDivider() CheckCharacterSettingsRow("),
            "설정의 칩 줄에서 관리자 게이트가 사라졌다 — 이번 작업은 그 줄을 건드리지 않는다")
}

// MARK: - ⑥ 다른 패널과 상호 배타 (양방향)

@MainActor
@Test
func 캐릭터_패널은_다른_패널과_상호_배타다() throws {
    // (가) 캐릭터를 열면 남들이 닫힌다.
    let a = cpTeamStore(members: 3)
    a.isLeaderboardVisible = true
    a.isInsightsPanelVisible = true
    a.isFeedbackPanelVisible = true
    a.toggleCharacterPanel()
    #expect(a.isCharacterPanelVisible)
    #expect(!a.isLeaderboardVisible)
    #expect(!a.isInsightsPanelVisible)
    #expect(!a.isFeedbackPanelVisible)

    // (나) 남을 열면 캐릭터가 닫힌다. **이 방향이 빠지기 쉽다** — 빠지면 두 패널의 깃발이 동시에 서서
    //      `isSubPanelOpen` 은 여전히 true 라 창 높이 회귀는 안 나고, 화면만 디스패치 순서에 따라
    //      엉뚱한 패널을 그린다(뒤로 한 번으로는 홈에 못 돌아간다).
    for (label, open) in cpOtherPanelOpeners() {
        let store = cpTeamStore(members: 3)
        store.toggleCharacterPanel()
        #expect(store.isCharacterPanelVisible, "\(label): 사전 조건이 안 섰다")
        open(store)
        #expect(!store.isCharacterPanelVisible, "\(label) 를 열었는데 캐릭터 패널이 그대로 떠 있다")
    }

    // (다) 토글은 닫기도 한다(레일 칸들과 같은 규약).
    let c = cpTeamStore(members: 3)
    c.toggleCharacterPanel()
    c.toggleCharacterPanel()
    #expect(!c.isCharacterPanelVisible)
}

// MARK: - ⑦ 격자 높이 예산 (순수 계산)

@Test
func 격자_예산은_행이_늘면_스크롤로_넘긴다() {
    #expect(CharacterPanelGridBudget.rowCount(cardCount: 0) == 0)
    #expect(CharacterPanelGridBudget.rowCount(cardCount: 1) == 1)
    #expect(CharacterPanelGridBudget.rowCount(cardCount: 3) == 1)
    #expect(CharacterPanelGridBudget.rowCount(cardCount: 4) == 2)
    #expect(CharacterPanelGridBudget.rowCount(cardCount: 9) == 3)

    // 자연 높이 = 행×카드 + 사이 간격.
    #expect(CharacterPanelGridBudget.naturalHeight(rowCount: 0) == 0)
    #expect(CharacterPanelGridBudget.naturalHeight(rowCount: 1) == CharacterPanelGridBudget.cardHeight)
    #expect(CharacterPanelGridBudget.naturalHeight(rowCount: 3)
            == 3 * CharacterPanelGridBudget.cardHeight + 2 * CharacterPanelGridBudget.cardSpacing)

    // 크롬이 얹히면 그만큼 깎고, 아무리 깎여도 카드 한 줄은 남긴다.
    #expect(CharacterPanelGridBudget.capHeight(extraChromeHeight: 0) == CharacterPanelGridBudget.maxGridHeight)
    #expect(CharacterPanelGridBudget.capHeight(extraChromeHeight: 100)
            == CharacterPanelGridBudget.maxGridHeight - 100)
    #expect(CharacterPanelGridBudget.capHeight(extraChromeHeight: 10_000)
            == CharacterPanelGridBudget.minGridHeight)

    // 번들의 캐릭터 수로는 아직 한 행이라 스크롤이 없다(= 잘림도 없다). 상점이 붙어 캐릭터가 늘면
    // 이 비교가 먼저 뒤집히고, 그때부터 격자는 스크롤로 넘어간다.
    #expect(CharacterPanelGridBudget.maxGridHeight
            >= CharacterPanelGridBudget.naturalHeight(rowCount: 1))
}

// MARK: - ⑧ 카드가 많아져도 창은 상한 안이다

@MainActor
@Test
func 캐릭터가_늘어도_창이_상한_안에_선다() throws {
    // 상점이 붙으면 캐릭터가 5종 더 온다(DECISIONS: 시바견·판다·토끼·슬라임·아기드래곤 → 총 8종 = 3행).
    // 그때 창이 상한을 넘지 않는지 **지금** 재 둔다 — 에셋이 들어오는 날 이 검사는 이미 초록이어야 한다.
    let suite = cpSuite()
    defer { cpDrop(suite) }
    let many = CharacterCatalog(manifests: (0..<12).map {
        CharacterManifest(id: "filler-\($0)", displayName: "캐릭터\($0)", kind: .scene3D)
    })
    let panel = CheckCharacterPanel(
        catalog: many,
        selection: CharacterSelection(defaults: suite.defaults, catalog: many),
        broadcast: CharacterSelectionBroadcast(),
        extraChromeHeight: 0,
        clipsOverflowInsteadOfScroll: true,
        onBack: {}
    )
    let height = try #require(cpHeight(panel, width: CheckMenuView.contentColumnWidth))
    // 13종(아잉 + filler 12) = 5행 = 자연 512pt 인데 예산이 깎아 격자는 상한(400pt)에서 멈춘다.
    #expect(CharacterPanelGridBudget.rowCount(cardCount: many.allIDs.count) == 5)
    #expect(CharacterPanelGridBudget.naturalHeight(rowCount: 5) > CharacterPanelGridBudget.maxGridHeight,
            "이 검사는 예산을 넘기는 행 수라야 의미가 있다")

    // ★ **예산 상수를 실측과 맞댄다.** 패널 = 격자(깎인 높이) + 격자 밖 크롬. 패널 머리에 줄을 하나
    //   더하면 크롬이 커지는데 상수는 그대로라, 예산이 조용히 거짓이 되고 창이 상한을 넘는다.
    //   그 회귀를 여기서 숫자로 잡는다(다른 상수 둘은 아래 팝오버 검산이 함께 받는다).
    #expect(height == CharacterPanelGridBudget.maxGridHeight + CharacterPanelGridBudget.chromeOutsideGrid,
            "패널이 \(height)pt — 예산 \(CharacterPanelGridBudget.maxGridHeight) + 크롬 \(CharacterPanelGridBudget.chromeOutsideGrid) 과 갈렸다")

    cpSave(try #require(cpBitmap(panel, width: CheckMenuView.contentColumnWidth)),
           name: "v0316-character-panel-many.png")
}

// MARK: - ⑨ 예산 상수가 실측과 맞다 (팝오버 전체)

@MainActor
@Test
func 캐릭터_패널_높이_예산이_실측과_맞다() throws {
    let suite = cpSuite()
    defer { cpDrop(suite) }

    // (가) 팝오버에서 패널이 아닌 부분의 높이. 한 행짜리 패널이 든 팝오버 − 패널 자연 높이.
    let store = cpTeamStore(members: 8, tokenUsage: cpSeededTokenStore())
    store.toggleCharacterPanel()
    let popover = try #require(cpPopoverHeight(CheckMenuView(store: store, characterDefaults: suite.defaults)))
    let rows = CharacterPanelGridBudget.rowCount(cardCount: CheckCharacter3DScene.catalog.allIDs.count)
    let panelHeight = CharacterPanelGridBudget.naturalHeight(rowCount: rows)
        + CharacterPanelGridBudget.chromeOutsideGrid
    #expect(popover - panelHeight == CharacterPanelGridBudget.popoverChromeOutsidePanel,
            "팝오버 \(popover)pt − 패널 \(panelHeight)pt = \(popover - panelHeight)pt 인데 상수는 \(CharacterPanelGridBudget.popoverChromeOutsidePanel)pt 다")

    // (나) 배너 + 목표 편집 행이 얹히면 그 예산 상수만큼 정확히 자란다 — 그 둘이 곧 extraChromeHeight 다.
    let chromed = cpTeamStore(members: 8, tokenUsage: cpSeededTokenStore())
    chromed.retro = cpSampleRetro()
    chromed.showsRetroBanner = true
    chromed.toggleCharacterPanel()
    let withChrome = try #require(cpPopoverHeight(
        CheckMenuView(store: chromed, previewGoalEditing: true, characterDefaults: suite.defaults)
    ))
    #expect(withChrome - popover == CheckMenuView.inlineBannerHeight + CheckMenuView.goalEditorHeight,
            "크롬이 \(withChrome - popover)pt 늘었는데 예산은 \(CheckMenuView.inlineBannerHeight + CheckMenuView.goalEditorHeight)pt 로 센다")

    // (다) 그래서 어떤 조합에서도 창은 상한 안에 선다 — 격자가 예산을 다 쓴 최악까지 계산으로 확인한다.
    for extra in [CGFloat(0), 54, 92, 146, 239] {
        let grid = CharacterPanelGridBudget.capHeight(extraChromeHeight: extra)
        let total = grid + CharacterPanelGridBudget.chromeOutsideGrid
            + CharacterPanelGridBudget.popoverChromeOutsidePanel + extra
        #expect(total <= 700, "크롬 \(extra)pt 조합의 창이 \(total)pt 다")
    }

    // 팝오버 통째 스냅샷 둘(육안 확인용): 패널만, 그리고 배너·목표 편집 행까지 얹은 최악 조합.
    cpSavePopover(CheckMenuView(store: store, characterDefaults: suite.defaults),
                  name: "v0316-popover-character.png")
    cpSavePopover(CheckMenuView(store: chromed, previewClipsOverflowList: true,
                                previewGoalEditing: true, characterDefaults: suite.defaults),
                  name: "v0316-popover-character-worst.png")
}

// MARK: - ⑩ 홈 화면(진입점) 스냅샷

@MainActor
@Test
func 헤더_마스코트_진입점_스냅샷() throws {
    // 패널이 아니라 **들어가는 문**을 눈으로 본다 — 46×46 마스코트에 붓 표식이 붙었고, 헤더는 그대로다.
    let store = cpTeamStore(members: 6, tokenUsage: cpSeededTokenStore())
    cpSavePopover(CheckMenuView(store: store), name: "v0316-popover-home-entry.png")
    let height = try #require(cpPopoverHeight(CheckMenuView(store: store)))
    #expect(height <= 700.0, "홈 화면이 \(height)pt 다")
}

// MARK: - 헬퍼

private struct CPSuite {
    let name: String
    let defaults: UserDefaults
}

private func cpSuite() -> CPSuite {
    let name = "v0316-panel-\(UUID().uuidString)"
    return CPSuite(name: name, defaults: UserDefaults(suiteName: name)!)
}

private func cpDrop(_ suite: CPSuite) {
    suite.defaults.removePersistentDomain(forName: suite.name)
    UserDefaults.standard.removeSuite(named: suite.name)
}

private func cpIsolatedDefaults() -> UserDefaults {
    let name = "v0316-panel-render-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
private func cpInertTokenStore() -> TokenUsageStore {
    let tmp = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return TokenUsageStore(
        defaults: cpIsolatedDefaults(),
        homeDirectory: tmp.appendingPathComponent("cp-token-home-\(id)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("cp-token-cache-\(id).json", isDirectory: false)
    )
}

/// 토큰 소모량 행이 **실제로 그려지는** 스토어. 게이트가 빠지면 그 행이 패널과 함께 서서 창이 높아진다 —
/// 그 회귀를 재려면 행이 0pt 가 아니어야 한다.
@MainActor
private func cpSeededTokenStore() -> TokenUsageStore {
    let defaults = cpIsolatedDefaults()
    let usage = TokenUsageMonthly(
        month: TokenUsageMonthKey.current(),
        claudeInput: 8_460_869, claudeOutput: 35_849_782,
        claudeCacheRead: 4_165_692_507, claudeCacheCreation: 200_802_730,
        codexInput: 145_068_307, codexOutput: 623_160
    )
    if let data = try? JSONEncoder().encode(usage) {
        defaults.set(data, forKey: TokenUsageStore.snapshotKey)
    }
    let tmp = FileManager.default.temporaryDirectory
    let id = UUID().uuidString
    return TokenUsageStore(
        defaults: defaults,
        homeDirectory: tmp.appendingPathComponent("cp-token-home-\(id)", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("cp-token-cache-\(id).json", isDirectory: false)
    )
}

@MainActor
private func cpTeamStore(members: Int, tokenUsage: TokenUsageStore? = nil) -> WorkTimerStore {
    let now = Date()
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: cpIsolatedDefaults(),
        tokenUsage: tokenUsage ?? cpInertTokenStore()
    )
    // 렌더 결정성: onAppear 의 setMenuPresented(true) 가 != 가드로 no-op 되도록 선세팅한다.
    store.isMenuPresented = true
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil,
                                    userID: "00000000-0000-0000-0000-000000000002")
    store.displayNow = now
    store.currentTeamID = "00000000-0000-0000-0000-0000000000aa"
    store.teamName = "아잉팀"
    store.myCenterLoaded = true
    store.myCenter = CenterLabel.seoul
    let names = ["영식", "민수", "지현", "서준", "하윤", "도현", "예린", "yesung"]
    store.teamMembers = Array(names.prefix(members)).enumerated().map { index, name in
        TeamMemberStatus(
            id: "00000000-0000-0000-0000-00000000000\(index)",
            name: name,
            status: index % 3 == 2 ? .offWork : .working,
            updatedAt: nil,
            currentSessionStartedAt: index % 3 == 2 ? nil : now.addingTimeInterval(-3_600),
            weeklyDurationSeconds: 7_200 * (index + 1)
        )
    }
    return store
}

@MainActor
private func cpSampleRetro() -> WeeklyRetro {
    WeeklyRetro(
        weekStart: Date(timeIntervalSince1970: 1_784_000_000),
        totalSeconds: 144_000,
        goalSeconds: 40 * 3_600,
        previousWeekSeconds: 132_480,
        sessionCount: 12,
        busiestDayIndex: 0,
        busiestDaySeconds: 6 * 3_600 + 45 * 60
    )
}

/// 캐릭터 패널을 열어 둔 다른 패널 진입점들. (나) 방향을 한 자리에서 전부 센다.
@MainActor
private func cpOtherPanelOpeners() -> [(String, @MainActor (WorkTimerStore) -> Void)] {
    [
        ("팀 현황", { $0.toggleLeaderboard() }),
        ("토큰 순위판", { $0.toggleTokenBoard() }),
        ("콕찌르기", { $0.togglePokePanel() }),
        ("내 기록", { $0.toggleInsightsPanel() }),
        ("울트라", { $0.openUltraPanel(from: .home) }),
        ("제보", { $0.openFeedbackPanel() }),
        ("1:1 대화", { $0.openMessagePanel(peer: "00000000-0000-0000-0000-000000000003") })
    ]
}

// MARK: - 렌더

private enum CPError: Error { case renderFailed }

@MainActor
private func cpBitmap(_ view: some View, width: CGFloat) -> NSBitmapImageRep? {
    // 배율은 **언제나 명시한다** — 기본값은 주 디스플레이 backingScaleFactor 라 기계마다 갈린다.
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap
}

@MainActor
private func cpHeight(_ view: some View, width: CGFloat) -> CGFloat? {
    cpBitmap(view, width: width).map { CGFloat($0.pixelsHigh) / 2 }
}

/// 팝오버는 **자연 폭**으로 그린다(레일이 붙으면 창이 넓어진다 — 폭을 고정하면 그 사실이 지워진다).
@MainActor
private func cpPopoverHeight(_ view: CheckMenuView) -> CGFloat? {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return CGFloat(bitmap.pixelsHigh) / 2
}

/// 패널 **하나만** 그린다. 팝오버 전체에는 입력칸이 있어 노란 상자가 이미 있고,
/// 그러면 "이 패널에 노란 상자가 없는가"를 물을 수 없다.
@MainActor
private func cpPanelBitmap(defaults: UserDefaults) throws -> NSBitmapImageRep {
    let catalog = CheckCharacter3DScene.catalog
    let panel = CheckCharacterPanel(
        catalog: catalog,
        selection: CharacterSelection(defaults: defaults, catalog: catalog),
        broadcast: CharacterSelectionBroadcast(),
        onBack: {}
    )
    guard let bitmap = cpBitmap(panel, width: CheckMenuView.contentColumnWidth) else {
        throw CPError.renderFailed
    }
    return bitmap
}

/// ImageRenderer 의 "못 그림" 표식(샛노란 상자, 실측 255/204/0) 픽셀 수.
private func cpYellowPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
    cpCount(bitmap) { r, g, b in r >= 240 && g >= 195 && b <= 40 }
}

/// 이 화면의 회색 팔레트에 없는 **유채색** 픽셀 수(= 캐릭터 그림).
private func cpColorfulPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
    cpCount(bitmap) { r, g, b in
        let maxC = max(r, max(g, b)), minC = min(r, min(g, b))
        return maxC - minC >= 50 && maxC >= 80
    }
}

/// 선택됨 표시의 강조색(파랑 계열 — accent 0.33/0.67/1.0). 파랑이 확실히 앞서는 픽셀만 센다.
private func cpAccentPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
    cpCount(bitmap) { r, g, b in b >= 150 && b - r >= 50 && b >= g }
}

private func cpCount(_ bitmap: NSBitmapImageRep, _ match: (Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var count = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            if match(Int(data[o]), Int(data[o + 1]), Int(data[o + 2])) { count += 1 }
        }
    }
    return count
}

/// 팝오버 통째(자연 폭) 스냅샷을 굽는다.
@MainActor
private func cpSavePopover(_ view: CheckMenuView, name: String) {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return }
    cpSave(bitmap, name: name)
}

/// 세션 전용 절대 경로를 소스에 박지 않는다 — 퍼블릭 저장소에 개인 머신 경로가 남는다.
private func cpSave(_ bitmap: NSBitmapImageRep, name: String) {
    let dir = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-v0316", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: dir.appendingPathComponent(name))
}

// MARK: - 소스 읽기

private func cpSource(_ name: String) throws -> String {
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/checkTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Sources/check", isDirectory: true)
    return try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
}

/// 주석을 걷어내고 공백을 한 칸으로 접은 코드. 안 걷어내면 **설명을 지워야만 초록이 되는** 테스트가 된다.
/// 문자열 리터럴 안의 `//` 는 보존해야 하므로 따옴표 상태를 추적한다(하우스 규칙).
private func cpStripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let next = source.index(after: index) < source.endIndex ? source[source.index(after: index)] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = source.index(after: index) }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = source.index(after: index)
        } else if c == "/", next == "*" {
            inBlock = true; index = source.index(after: index)
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}
