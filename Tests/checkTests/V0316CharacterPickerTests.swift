import AppKit
import Foundation
import SceneKit
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.15 2-D 캐릭터 선택기 + 초기 마운트 배선
//
// 이 스위트가 지키는 것은 다섯이다. 전부 **초록인 채로 틀릴 수 있는** 자리다:
//  ① 선택기는 관리자에게만 보인다(상점이 없으므로). 게이트가 사라져도 화면은 멀쩡해 보인다.
//  ② 선택기가 **픽셀로 실제로 그려진다**. Picker/Menu 로 만들면 ImageRenderer 가 그 자리에 노란 상자를
//     박고, 그 자리의 픽셀 커버리지는 0이 된다 — 스냅샷 검증이 통째로 눈이 먼다(이 저장소가 겪은 눈가리개).
//  ③ 누르면 **저장된다**. 저장 호출이 빠져도 로컬 칩은 옮겨 갈 수 있어 눈으로는 멀쩡하다.
//  ④ 앱을 다시 켜면 착용 캐릭터로 돌아온다(= `makeNSView` 가 선택을 읽는다). 교체만 되고 마운트가
//     아잉 고정이면 "골랐는데 재시작하면 아잉"이 되고, 그건 아무 테스트도 안 빨개진다.
//  ⑤ 설정 창 높이 계약(470pt)이 비관리자 화면에서 **1pt 도 안 움직인다**.
//
// ⚠️ 이 파일은 `UserDefaults.standard` 에 **한 글자도 쓰지 않는다.** 같은 순간 병렬로 도는 스위트가
//    아잉 픽셀을 재고 있어서, 표준 도메인에 선택값을 남기면 그쪽이 간헐적으로 빨개진다. 전부 임시 suite 를
//    쓰고 `defer` 로 지운다. `CharacterSelectionBroadcast` 도 `.shared` 를 쓰지 않고 새 인스턴스를 만든다.

// MARK: - ① 관리자 전용

@MainActor
@Test
func 캐릭터_선택기는_관리자에게만_보인다() throws {
    // 판정은 **높이**다. 이 창의 행들은 세로로 쌓이므로, 행 하나가 생기면 콘텐츠가 그만큼 자란다.
    // 게이트를 지우면 두 렌더가 같은 높이가 되어 이 비교가 즉시 빨개진다(= 일반 사용자에게 열렸다).
    let plain = try v0316SettingsBitmap(admin: false)
    let admin = try v0316SettingsBitmap(admin: true)

    let plainHeight = CGFloat(plain.pixelsHigh) / 2
    let adminHeight = CGFloat(admin.pixelsHigh) / 2

    #expect(adminHeight > plainHeight + 40,
            "관리자 화면이 \(adminHeight)pt, 일반 \(plainHeight)pt — 선택기 행이 자리를 안 차지했다")
    // 반대 방향도 못 박는다: 게이트가 사라지면 여기가 아니라 위가 먼저 빨개지지만, 일반 사용자의
    // 화면 높이가 **예전 그대로**라는 사실을 숫자로 남겨 둬야 회귀가 어느 쪽인지 읽힌다.
    #expect(plainHeight <= CheckSettingsWindowController.defaultContentSize.height,
            "일반 사용자 설정 콘텐츠 \(plainHeight)pt 가 창 470pt 를 넘었다")
    #expect(plainHeight >= 440, "일반 사용자 화면이 \(plainHeight)pt 뿐이다 — 기존 행이 사라졌는지 보라")

    // ★ 관리자 화면의 높이를 **숫자로 고정한다.** 이 값이 창 계약(470)보다 크다는 사실 자체가 인수인계다 —
    //   잇는 쪽(CheckSettingsWindow.swift 는 이 갈래 소유가 아니다)이 관리자일 때 창을 이만큼 열어야 한다.
    //   여기 고정해 두면 선택기가 조용히 더 자라는 회귀도 함께 잡힌다.
    #expect(adminHeight == CheckSettingsView.adminContentHeight,
            "관리자 화면이 \(adminHeight)pt 다 — 선언값 \(CheckSettingsView.adminContentHeight)pt 와 갈렸다")
    #expect(CheckSettingsView.adminContentHeight > CheckSettingsWindowController.defaultContentSize.height,
            "창이 관리자 화면을 담을 만큼 커졌다면 이 줄과 adminContentHeight 주석을 같이 지워라")

    v0316Save(plain, name: "v0316-settings-plain.png")
    v0316Save(admin, name: "v0316-settings-admin.png")
}

// MARK: - ② 픽셀로 보이는 선택기 (Picker/Menu 금지)

@MainActor
@Test
func 선택기는_노란_상자가_아니라_진짜_칩으로_그려진다() throws {
    // ImageRenderer 는 Menu·Picker·TextField 를 못 그리고 자리에 (255,204,0) 상자를 박는다.
    // 그 상자가 하나라도 있으면 이 행은 스냅샷에서 **보이지 않는 것과 같다** — 잘림·겹침을 영영 못 잡는다.
    let suite = v0316Suite()
    defer { v0316Drop(suite) }
    let bitmap = try v0316RowBitmap(defaults: suite.defaults)

    #expect(v0316YellowPixelCount(bitmap) == 0,
            "선택기 자리에 '못 그림' 노란 상자가 있다 — Picker/Menu 로 만들면 스냅샷이 눈이 먼다")

    // 고른 칩은 켜짐 그라디언트(초록→파랑)로 칠해진다. 그 색이 한 톨도 없으면 칩이 전부 회색이거나
    // 아무것도 안 그려진 것이다 — "무엇을 고르고 있는지 안 보이는 선택기"를 이 한 줄이 막는다.
    #expect(v0316GaugeTintedPixelCount(bitmap) > 200,
            "고른 칩의 켜짐 그라디언트가 안 보인다(칠해진 픽셀 \(v0316GaugeTintedPixelCount(bitmap))개)")

    // 행 하나가 창을 잡아먹지 않는지도 함께 잰다(설명 한 줄 + 칩 한 줄).
    let height = CGFloat(bitmap.pixelsHigh) / 2
    #expect(height <= 90, "선택기 행이 \(height)pt 다 — 한 행이 창 높이 예산을 먹는다")

    v0316Save(bitmap, name: "v0316-character-row.png")
}

// MARK: - ③ 아잉이 항상 첫 번째

@MainActor
@Test
func 목록은_아잉을_첫째로_카탈로그_순서를_그대로_따른다() throws {
    let catalog = CheckCharacter3DScene.catalog
    #expect(catalog.allIDs.first == CharacterCatalog.builtInAingID,
            "아잉이 첫 칸이 아니다 — 폴백 대상이 첫 칸이라는 규약이 깨졌다")

    // 뷰가 그 순서를 **다시 정렬하지 않는지**도 소스로 못 박는다. 여기서 한 번 더 정렬하면 "아잉 먼저"가
    // 두 곳에 적히고, 갈리는 날 조용히 어긋난다(카탈로그만 고쳐도 화면은 안 바뀐다).
    let source = v0316Stripped(try v0316SettingsSource())
    #expect(source.contains("ForEach(catalog.allIDs, id: \\.self)"),
            "선택기가 catalog.allIDs 를 그대로 순회하지 않는다")
    #expect(!source.contains("catalog.allIDs.sorted()"), "뷰에서 목록을 다시 정렬하지 마라")
}

// MARK: - ④ 고르면 저장된다

@MainActor
@Test
func 고르면_저장되고_되그릴_쪽에_알린다() throws {
    let suite = v0316Suite()
    defer { v0316Drop(suite) }

    let catalog = CheckCharacter3DScene.catalog
    let target = try #require(catalog.allIDs.first { $0 != CharacterCatalog.builtInAingID },
                              "번들에 아잉 말고 캐릭터가 없다 — 이 스위트는 에셋이 있어야 의미가 있다")
    let selection = CharacterSelection(defaults: suite.defaults, catalog: catalog)
    let broadcast = CharacterSelectionBroadcast()

    #expect(selection.selectedID == CharacterCatalog.builtInAingID, "빈 도메인의 기본은 아잉이다")

    #expect(CheckCharacterPicker.choose(target, selection: selection, broadcast: broadcast))
    // 영속: 이 한 줄이 빠지면 앱을 다시 켤 때 선택이 사라진다.
    #expect(suite.defaults.string(forKey: CharacterSelection.defaultsKey) == target)
    #expect(selection.selectedID == target)
    // 방송: 이 한 줄이 빠지면 저장은 되는데 **화면이 그대로**다(2-C 가 남긴 인수인계).
    #expect(broadcast.selectedID == target)
    #expect(broadcast.revision == 1)

    // 같은 캐릭터를 다시 골라도 revision 은 오른다 — 되그릴 쪽은 id 가 아니라 이 값을 읽는다.
    #expect(CheckCharacterPicker.choose(target, selection: selection, broadcast: broadcast))
    #expect(broadcast.revision == 2)

    // 모르는 id 는 **아무것도 하지 않는다**. 옛 저장값을 모르는 값으로 덮으면 그 캐릭터가 돌아오는
    // 빌드에서 선택이 되살아나지 않는다(CharacterSelection.select 의 규약).
    #expect(CheckCharacterPicker.choose("no-such-character", selection: selection, broadcast: broadcast) == false)
    #expect(suite.defaults.string(forKey: CharacterSelection.defaultsKey) == target)
    #expect(broadcast.revision == 2, "거절된 선택이 화면 갱신을 일으켰다")
}

@MainActor
@Test
func 선택기_버튼이_저장_함수를_실제로_부른다() throws {
    // ③·④ 가 전부 초록인데 **버튼이 그 함수를 안 부르는** 조합이 만들어진다(먹통 선택기).
    // 주석은 걷어내고 센다 — 이 저장소는 "왜"를 길게 적는 관례라 설명문에 호출 이름이 자주 나온다(하우스 규칙).
    let source = v0316Stripped(try v0316SettingsSource())
    #expect(source.contains("CheckCharacterPicker.choose(id, selection: selection, broadcast: broadcast)"),
            "칩 버튼이 저장 경로를 안 부른다 — 눌러도 아무 일도 안 일어난다")
    // 저장이 거절되면 칩도 안 움직여야 한다(화면만 바뀌었다가 조용히 되돌아가는 거짓말 금지).
    #expect(source.contains("if CheckCharacterPicker.choose(id, selection: selection, broadcast: broadcast) { selectedID = id onChosen(id) }"),
            "저장 성공 여부와 무관하게 칩이 움직이면 화면이 거짓말을 한다")
    // ★ `onChosen(id)` 이 **같은 가지 안**에 있어야 한다 — 저장이 거절됐는데 서버에 밀면
    //   로컬과 서버가 갈린다(내 화면은 옛 캐릭터, 남에게는 새 캐릭터).
    // 관리자 게이트도 소스로 한 번 더 못 박는다(렌더 비교가 흔들려도 이 줄은 정확하다).
    #expect(source.contains("if store.ultraUnlimited { PanelDivider() CheckCharacterSettingsRow("),
            "선택기가 ultraUnlimited 게이트 밖으로 나왔다")
}

// MARK: - ⑤ 초기 마운트가 착용 캐릭터를 읽는다

@MainActor
@Test
func 초기_마운트가_저장된_착용_캐릭터를_세운다() throws {
    let catalog = CheckCharacter3DScene.catalog
    let sprite = try #require(catalog.allIDs.first {
        catalog.manifest(id: $0)?.kind == .sprite
    }, "번들에 스프라이트 캐릭터가 없다 — 이 검사는 에셋이 있어야 의미가 있다")

    // (a) 빈 도메인 = 아잉. 지금까지의 동작이 그대로인지 먼저 확인한다.
    let empty = v0316Suite()
    defer { v0316Drop(empty) }
    let aingScene = try v0316MountedScene(defaults: empty.defaults)
    #expect(v0316CharacterNodeName(in: aingScene) != SpriteCharacterNode.nodeName,
            "아무것도 안 골랐는데 스프라이트가 섰다")

    // (b) 저장된 선택 = 스프라이트. **여기가 이 갈래의 본론이다** — 이 검사가 없으면 "고르면 바뀌는데
    //     재시작하면 아잉으로 돌아온다"가 아무 테스트도 안 빨갛게 한 채 배포된다.
    let worn = v0316Suite()
    defer { v0316Drop(worn) }
    worn.defaults.set(sprite, forKey: CharacterSelection.defaultsKey)
    let spriteScene = try v0316MountedScene(defaults: worn.defaults)
    #expect(v0316CharacterNodeName(in: spriteScene) == SpriteCharacterNode.nodeName,
            "착용 캐릭터가 \(sprite) 인데 마운트가 아잉을 세웠다")

    // 골격은 캐릭터 종류와 무관하게 같아야 한다(리액션 wrapper → facing → 캐릭터).
    #expect(spriteScene.rootNode.childNode(withName: CheckCharacter3DScene.reactionWrapperName,
                                           recursively: false) != nil)
}

@MainActor
@Test
func 마운트의_UserDefaults_읽기는_한_곳뿐이다() throws {
    // `makeNSView` 안에 `.standard` 를 직접 적으면 이 뷰를 지나는 아잉 계약 테스트 네 벌이 **보이지 않는
    // 전역 하나**를 공유하게 된다. 주입점을 지우는 회귀를 소스로 막는다(주석은 걷어낸다).
    let source = v0316Stripped(try v0316Source("CheckCharacter3DView.swift"))
    #expect(source.contains("var characterDefaults: UserDefaults = .standard"),
            "주입점이 사라졌다 — 테스트가 자기 도메인을 넣을 방법이 없어진다")
    #expect(source.contains("CheckCharacter3DScene.selectedCharacter(defaults: characterDefaults)"),
            "마운트가 주입된 도메인을 안 읽는다")

    // ★ 진짜 계약: **`makeNSView` 본문에는 `UserDefaults` 라는 글자가 없다.** 주입점을 두고도 그 안에서
    //   `.standard` 를 다시 읽으면 주입은 장식이 되고, 숨은 전역은 그대로 남는다.
    //   (이 파일에 `= .standard` 기본값은 둘이다 — 이 뷰의 `characterDefaults` 와 2-A 가 만든
    //    `selectedCharacter(defaults:)`. 둘 다 **주입 가능한 기본값**이라 세어서 막을 일이 아니다.)
    let start = try #require(source.range(of: "func makeNSView(context: Context) -> SCNView {"))
    let end = try #require(source.range(of: "func updateNSView(", range: start.upperBound..<source.endIndex))
    let body = String(source[start.upperBound..<end.lowerBound])
    #expect(!body.contains("UserDefaults"),
            "makeNSView 안에서 UserDefaults 를 직접 읽는다 — 주입점이 장식이 됐다")
    #expect(body.contains("characterDefaults"), "makeNSView 가 주입된 도메인을 안 쓴다")
}

// MARK: - 헬퍼

private struct V0316Suite {
    let name: String
    let defaults: UserDefaults
}

/// 임시 도메인. **표준 도메인을 절대 건드리지 않는다** — 병렬 스위트가 아잉 픽셀을 재고 있다.
private func v0316Suite() -> V0316Suite {
    let name = "v0316-picker-\(UUID().uuidString)"
    return V0316Suite(name: name, defaults: UserDefaults(suiteName: name)!)
}

/// 쓴 것을 되돌린다. `removePersistentDomain` 은 디스크의 plist 까지 지운다.
private func v0316Drop(_ suite: V0316Suite) {
    suite.defaults.removePersistentDomain(forName: suite.name)
    UserDefaults.standard.removeSuite(named: suite.name)
}

@MainActor
private func v0316Store(admin: Bool) -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon"],
        defaults: UserDefaults(suiteName: "v0316-store-\(UUID().uuidString)")!
    )
    // 센터 행을 **시드한다**: 안 주면 서버 GET 도착 시점에 따라 '불러오는 중…' → '미지정' 으로 바뀌어
    // 이 비교가 선택기와 무관한 줄에서 흔들린다(CheckMenuRenderTests 가 같은 이유로 같은 조치를 한다).
    store.myCenterLoaded = true
    store.myCenter = CenterLabel.seoul
    store.ultraUnlimited = admin
    return store
}

private enum V0316Error: Error { case renderFailed }

@MainActor
private func v0316Bitmap(_ view: some View, width: CGFloat, scale: CGFloat = 2) throws -> NSBitmapImageRep {
    // 배율은 **언제나 명시한다** — 기본값은 주 디스플레이 backingScaleFactor 라 기계마다 갈린다.
    let renderer = ImageRenderer(content: view.frame(width: width))
    renderer.scale = scale
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { throw V0316Error.renderFailed }
    return bitmap
}

@MainActor
private func v0316SettingsBitmap(admin: Bool) throws -> NSBitmapImageRep {
    let suite = v0316Suite()
    defer { v0316Drop(suite) }
    // launchAtLoginSeed 를 반드시 준다 — 안 주면 렌더가 실제 로그인 항목(SMAppService)을 읽어
    // 테스트가 이 맥의 시스템 상태에 의존한다.
    return try v0316Bitmap(
        CheckSettingsView(store: v0316Store(admin: admin),
                          launchAtLoginSeed: false,
                          characterDefaults: suite.defaults),
        width: CheckSettingsView.preferredWidth
    )
}

/// 선택기 행 **하나만** 그린다. 설정 화면 전체에는 별명 입력칸(TextField)이 있어 노란 상자가 이미 있고,
/// 그러면 "이 행에 노란 상자가 없는가"를 물을 수 없다.
@MainActor
private func v0316RowBitmap(defaults: UserDefaults) throws -> NSBitmapImageRep {
    let catalog = CheckCharacter3DScene.catalog
    let row = CheckCharacterSettingsRow(
        catalog: catalog,
        selection: CharacterSelection(defaults: defaults, catalog: catalog),
        broadcast: CharacterSelectionBroadcast()
    )
    // 카드 안쪽 폭(창 380 − 바깥 여백 14×2 − 카드 여백 12×2). 실제로 놓이는 폭에서 재야 줄바꿈이 같다.
    return try v0316Bitmap(row.padding(8).background(CheckTheme.panel), width: 328)
}

/// ImageRenderer 의 "못 그림" 표식(샛노란 상자, 실측 255/204/0) 픽셀 수.
/// 파랑 성분이 0 인 게 결정적이다 — 다른 주황·노랑 계열은 파랑이 남아 걸리지 않는다.
private func v0316YellowPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
    v0316Count(bitmap) { r, g, b in r >= 240 && g >= 195 && b <= 40 }
}

/// 켜짐 그라디언트(초록→파랑)로 칠해진 픽셀 수. 두 끝 어느 쪽이든 **채도가 분명한 유채색**이라
/// 이 창의 회색 팔레트(trackFill·panel·border)와 겹치지 않는다.
private func v0316GaugeTintedPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
    v0316Count(bitmap) { r, g, b in
        let maxC = max(r, max(g, b)), minC = min(r, min(g, b))
        // 회색(채도 낮음)과 흰 글자를 뺀다. 빨강이 가장 센 색은 이 화면에 없다(danger 는 이 행에 안 쓴다).
        return maxC - minC >= 60 && maxC >= 90 && r < max(g, b)
    }
}

private func v0316Count(_ bitmap: NSBitmapImageRep, _ match: (Int, Int, Int) -> Bool) -> Int {
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

/// 실제로 마운트된 SCNView 의 씬. `makeNSView` 를 직접 부를 방법이 없으므로 호스팅 계층을 세워
/// **SwiftUI 가 만든 그것**을 집어 온다(V0238CharacterTests 와 같은 수법 — 그래야 배선을 정말 잰다).
@MainActor
private func v0316MountedScene(defaults: UserDefaults) throws -> SCNScene {
    let hosting = NSHostingView(
        rootView: CheckCharacter3DView(isActive: true, engine: nil, characterDefaults: defaults)
    )
    hosting.frame = NSRect(x: 0, y: 0, width: 140, height: 170)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    // 절대 화면에 올리지 않는 알파 0 창(V0238 의 규약).
    window.alphaValue = 0
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    defer { window.contentView = nil }

    let scnView = try #require(v0316FirstSCNView(in: hosting), "호스팅 계층에 SCNView 가 없다")
    return try #require(scnView.scene, "마운트된 SCNView 에 씬이 없다")
}

@MainActor
private func v0316FirstSCNView(in view: NSView) -> SCNView? {
    if let scn = view as? SCNView { return scn }
    for sub in view.subviews {
        if let found = v0316FirstSCNView(in: sub) { return found }
    }
    return nil
}

/// `root → wrapper → facing` 아래 캐릭터 노드의 이름. 스프라이트면 `check.spriteCharacter`.
@MainActor
private func v0316CharacterNodeName(in scene: SCNScene) -> String? {
    scene.rootNode
        .childNode(withName: CheckCharacter3DScene.reactionWrapperName, recursively: false)?
        .childNode(withName: CheckCharacter3DScene.facingWrapperName, recursively: false)?
        .childNodes.first?.name
}

// MARK: - 소스 읽기

private func v0316SourcesDirectory() -> URL {
    URL(fileURLWithPath: #filePath)          // Tests/checkTests/V0316CharacterPickerTests.swift
        .deletingLastPathComponent()          // Tests/checkTests
        .deletingLastPathComponent()          // Tests
        .deletingLastPathComponent()          // repo root
        .appendingPathComponent("Sources/check", isDirectory: true)
}

private func v0316Source(_ name: String) throws -> String {
    try String(contentsOf: v0316SourcesDirectory().appendingPathComponent(name), encoding: .utf8)
}

private func v0316SettingsSource() throws -> String {
    try v0316Source("CheckSettingsView.swift")
}

/// 주석을 걷어내고 공백을 한 칸으로 접은 코드. 안 걷어내면 **설명을 지워야만 초록이 되는** 테스트가 된다.
/// 문자열 리터럴 안의 `//` 는 보존해야 하므로 따옴표 상태를 추적한다(하우스 규칙 · V0313CenterTests 와 같은 기계).
private func v0316Stripped(_ source: String) -> String {
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

/// 세션 전용 절대 경로를 소스에 박지 않는다 — 퍼블릭 저장소에 개인 머신 경로가 남는다.
private func v0316Save(_ bitmap: NSBitmapImageRep, name: String) {
    let dir = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-v0316", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: dir.appendingPathComponent(name))
}
