import AppKit
import Foundation
import CheckCore

/// SwiftPM 리소스 번들(check_check.bundle) 위치 해석기.
///s
/// 실행파일 타깃의 `Bundle.module` 생성 코드는 앱 번들의 `Contents/Resources` 를 보지 않고
/// (.app 루트와 **빌드 머신의 절대경로**만 확인) 실패 시 fatalError 로 즉사한다 — 개발 머신에서는
/// 빌드 경로가 실존해 가려지지만 배포된 다른 맥에서는 앱이 시작하자마자 죽는다.
/// 그래서 배포 앱의 실제 위치(Contents/Resources)를 먼저 보고, 개발/테스트 환경(swift run/test —ㅇ
/// 빌드 디렉토리가 실존)에서만 Bundle.module 로 폴백한다.
enum CheckResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("check_check.bundle"),
           let bundled = Bundle(url: url) {
            return bundled
        }
        return Bundle.module
    }()
}

/// 메뉴바(18pt)·팝오버(46pt)에 나가는 **착용 캐릭터 초상화**의 로딩·캐싱 헬퍼.
///
/// 근무 상태에 따라 두 가지 표정을 노출한다.
/// - 근무중(`snapshot.isWorking == true`): 웃는 얼굴(`neutral`)
/// - 근무중 아님: 시무룩(`negative`)
///
/// 판단 기준은 `snapshot.isWorking` 하나만 사용하며 `pendingSync` 여부와 무관하다.
///
/// ## 어느 캐릭터를 그리는가 — 선택 주입
///
/// 이 타입은 static enum 이고 호출부(`CheckMenuView`·`CheckMascotView`·`MiniGameFlappy`)는
/// 인스턴스를 들고 있지 않다. 그래서 선택을 **두 갈래로** 받는다.
///
/// 1. **기본: 영속 선택을 직접 읽는다**(`resolvedCharacterID`). `CharacterSelection` 과 같은 키·같은
///    접기 규칙(모르는 id → 아잉)이라 배선 없이도 착용 캐릭터가 메뉴바에 바로 나온다. 앱 어딘가가
///    `CheckMascotAssets.selection = …` 를 불러 주어야만 동작하는 설계였다면, 그 한 줄을 빠뜨린 빌드는
///    **테스트가 전부 초록인 채로** 메뉴바만 옛 아잉으로 남는다 — 눈으로만 잡히는 결함이다.
///    (`CharacterSelection` 은 `@MainActor` 인데 초상화는 아무 스레드에서나 조회되므로 인스턴스를
///    들고 있지 않다. 대신 두 접기 규칙이 갈라지지 않게 `V0316PortraitTests` 가 둘을 맞대어 본다.)
/// 2. **범위 덮어쓰기**: `$characterIDOverride.withValue(_:)`. 전역 var 를 갈아 끼우는 대신 `@TaskLocal`
///    인 이유는 **병렬 테스트 오염**이다. swift-testing 은 테스트를 동시에 돌리므로, 전역 주입점을
///    잠깐 여우로 바꾸면 같은 순간 아잉 픽셀을 재는 기존 계약 테스트(`V0246MiniGameFlappyTests` 의
///    잉크 무게중심 등)가 간헐적으로 빨개진다. TaskLocal 은 건 Task 안에서만 보인다.
///
/// ## 실패하면 아잉으로 접는다
///
/// 초상 PNG 가 없거나 열리지 않으면 **아잉 초상으로 폴백**한다. nil 을 돌려주면 메뉴바 아이콘이
/// 통째로 사라진다(`MenuBarExtra` 라벨이 빈 이미지가 된다). nil 은 아잉 PNG 마저 없는 경우에만 —
/// 그때는 호출부가 SF Symbol/그려진 얼굴로 내려간다.
enum CheckMascotAssets {
    enum Mood: Equatable {
        case neutral
        case negative
    }

    /// 캐릭터 이미지가 담긴 리소스 번들. 테스트에서 접근성 검증에 사용한다.
    static var bundle: Bundle {
        CheckResources.bundle
    }

    /// **아잉** 표정 PNG 의 번들 리소스 이름. 다른 캐릭터는 매니페스트의 `portrait` 파일명을 쓴다
    /// (`Characters/<id>/portrait-*.png` — `.copy` 라 번들 루트가 아니라 폴더 안에 있다).
    static func resourceName(for mood: Mood) -> String {
        switch mood {
        case .neutral:
            return "aing-neutral"
        case .negative:
            return "aing-negative"
        }
    }

    static func mood(for snapshot: WorkStatusSnapshot) -> Mood {
        snapshot.isWorking ? .neutral : .negative
    }

    /// **아잉** 표정 PNG 의 URL. 팀원 아바타 스텁 등 "번들에 있는 PNG 한 장"이 필요한 자리가 쓰므로
    /// 선택을 따라가지 않는다. 착용 캐릭터의 초상은 `portraitURL(for:characterID:)`.
    static func url(for mood: Mood) -> URL? {
        bundle.url(forResource: resourceName(for: mood), withExtension: "png")
    }

    // MARK: - 선택

    /// 이 흐름 동안만 다른 캐릭터로 그린다(테스트 · 울트라 찌르기의 발신자 초상 등).
    /// 건 Task 안에서만 보이므로 병렬 테스트가 서로를 오염시키지 않는다.
    @TaskLocal static var characterIDOverride: String?

    /// 초상 조회에 쓰는 카탈로그. 프로세스당 한 번 번들을 훑는다(아잉은 파일이 없어도 항상 들어 있다).
    static let catalog: CharacterCatalog = .load()

    /// 지금 그려야 할 캐릭터 id.
    static func currentCharacterID() -> String {
        characterIDOverride ?? resolvedCharacterID()
    }

    /// 영속 선택의 UserDefaults 키. **`CharacterSelection.defaultsKey` 와 같은 값이어야 한다.**
    /// 저쪽은 `@MainActor` 인데 초상화 조회는 아무 스레드에서나 불리므로 참조가 막혀 한 번 더 적는다
    /// (Swift 6: main actor-isolated static property 를 nonisolated 에서 못 읽는다).
    /// 두 값이 갈리면 `V0316PortraitTests` 의 계약 테스트가 빨개진다.
    static let selectionDefaultsKey = "check.character.selected"

    /// 영속 선택을 읽어 접는다. **`CharacterSelection.selectedID` 와 같은 규칙이어야 한다** —
    /// 저장값이 없거나 카탈로그에 없으면 아잉.
    static func resolvedCharacterID(
        defaults: UserDefaults = .standard,
        catalog: CharacterCatalog = CheckMascotAssets.catalog
    ) -> String {
        guard let stored = defaults.string(forKey: selectionDefaultsKey),
              catalog.manifest(id: stored) != nil else {
            return CharacterCatalog.builtInAingID
        }
        return stored
    }

    /// 지금 착용한 캐릭터가 픽셀아트인가. 카탈로그의 매니페스트가 **유일한 출처**다.
    ///
    /// 이 값을 쓰는 쪽은 **확대·완만한 축소**뿐이다(헤더 46pt·선택 카드 52pt). 메뉴바(18pt)는
    /// 192px 원본의 5.3배 축소라 이웃 보간이 픽셀을 너무 많이 버려 오히려 나빠진다 —
    /// 렌더 비교로 확인했다(scratchpad/pack5/interp-compare.png). 거기는 묻지 말고 부드럽게 둬라.
    static func currentCharacterIsPixelArt() -> Bool {
        catalog.manifest(id: currentCharacterID())?.pixelArt == true
    }

    /// 착용 캐릭터의 초상 PNG URL. 아잉(과 초상이 없는 3D 캐릭터)은 종전 번들 루트 경로.
    static func portraitURL(for mood: Mood, characterID: String) -> URL? {
        guard characterID != CharacterCatalog.builtInAingID else { return url(for: mood) }
        return catalog.portraitURL(for: characterID, mood: mood)
    }

    // MARK: - 이미지

    /// ⚠️ **프로덕션 호출부가 없다**(2026-09-21 실측 — `Sources/` 전체에서 이 오버로드를 부르는 곳이 0개다).
    /// 팝오버 헤더가 `CheckMascotView(mood:)` 로 표정을 박으면서 마지막 호출부가 `image(for: Mood)` 로 옮겨갔다.
    /// **지우지 않는다**: `V0316PortraitTests` 가 "근무 여부 → 표정" 접기 규칙을 이 함수로 재고,
    /// 메뉴바 쪽 짝(`menuBarImage(for: snapshot)` — `CheckMenuView` 가 쓴다)과 규칙이 갈리지 않는지도 여기서 본다.
    static func image(for snapshot: WorkStatusSnapshot) -> NSImage? {
        image(for: mood(for: snapshot))
    }

    static func image(for mood: Mood) -> NSImage? {
        image(for: mood, characterID: currentCharacterID())
    }

    static func image(for mood: Mood, characterID: String) -> NSImage? {
        if let image = cache.image(key: cacheKey(mood: mood, characterID: characterID),
                                   url: portraitURL(for: mood, characterID: characterID)) {
            return image
        }
        guard characterID != CharacterCatalog.builtInAingID else { return nil }
        return image(for: mood, characterID: CharacterCatalog.builtInAingID)
    }

    /// 메뉴바(높이 ~22pt) 전용 캐릭터 이미지.
    ///
    /// 원본 NSImage의 copy를 만들어 `size`만 18×18pt로 지정한다. 비트맵 rep은
    /// 원본 픽셀(192px) 그대로 유지되므로 레티나에서 선명하다. `MenuBarExtra` 라벨은
    /// NSImage의 intrinsic size를 그대로 쓰는 경로가 있어 SwiftUI `.frame`이
    /// 무시될 수 있으므로, 이미지 자체 크기를 줄여 잘림을 방지한다.
    static let menuBarSize = NSSize(width: 18, height: 18)

    static func menuBarImage(for snapshot: WorkStatusSnapshot) -> NSImage? {
        menuBarImage(for: mood(for: snapshot))
    }

    static func menuBarImage(for mood: Mood) -> NSImage? {
        menuBarImage(for: mood, characterID: currentCharacterID())
    }

    static func menuBarImage(for mood: Mood, characterID: String) -> NSImage? {
        if let image = cache.menuBarImage(key: cacheKey(mood: mood, characterID: characterID),
                                          url: portraitURL(for: mood, characterID: characterID),
                                          size: menuBarSize) {
            return image
        }
        guard characterID != CharacterCatalog.builtInAingID else { return nil }
        return menuBarImage(for: mood, characterID: CharacterCatalog.builtInAingID)
    }

    // MARK: - Caching

    private static let cache = ImageCache()

    /// 캐시 키. **캐릭터 id 가 반드시 들어간다** — 표정 이름만으로 키를 잡으면 캐릭터를 바꿔도
    /// 먼저 불린 캐릭터의 초상이 그대로 나온다(그리고 앱을 다시 켜야만 바뀐다).
    static func cacheKey(mood: Mood, characterID: String) -> String {
        switch mood {
        case .neutral:
            return "\(characterID)/neutral"
        case .negative:
            return "\(characterID)/negative"
        }
    }

    /// 내부 상태는 `NSLock`으로 직렬화하므로 `@unchecked Sendable`로 표시한다.
    private final class ImageCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: NSImage] = [:]
        private var menuBarStorage: [String: NSImage] = [:]

        func image(key: String, url: URL?) -> NSImage? {
            lock.lock()
            defer { lock.unlock() }
            return baseImageLocked(key: key, url: url)
        }

        func menuBarImage(key: String, url: URL?, size: NSSize) -> NSImage? {
            lock.lock()
            defer { lock.unlock() }

            if let cached = menuBarStorage[key] {
                return cached
            }
            guard let base = baseImageLocked(key: key, url: url),
                  let sized = base.copy() as? NSImage else {
                return nil
            }
            // rep(원본 픽셀)은 그대로 두고 논리 크기만 줄인다 → 다운스케일되어 선명.
            sized.size = size
            menuBarStorage[key] = sized
            return sized
        }

        /// `lock`을 이미 획득한 상태에서만 호출해야 한다.
        private func baseImageLocked(key: String, url: URL?) -> NSImage? {
            if let cached = storage[key] {
                return cached
            }
            guard let url, let image = NSImage(contentsOf: url) else {
                return nil
            }
            storage[key] = image
            return image
        }
    }
}
