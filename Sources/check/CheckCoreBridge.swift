import AppKit
import CheckCore
import Foundation

// B3: 코어로 옮긴 타입 중 AppKit·맥 스토어에 닿는 조각을 맥 타깃에 남긴 자리.
// (코어는 iOS 에서도 빌드되므로 NSWindow·NSPanel·CheckMascotAssets 를 모른다.)

extension WorkTimerStore: GomokuStoreHost {}

extension MiniGameFrameRate {
    /// 이 창이 선 화면의 주사율. 창이 아직 화면에 없으면 주 화면, 그것도 없으면(헤드리스·테스트) 폴백.
    /// `NSScreen.maximumFramesPerSecond` 는 macOS 12+ 다(이 앱은 14+).
    @MainActor
    static func refreshRate(of window: NSWindow?) -> Int {
        guard let screen = window?.screen ?? NSScreen.main else { return baselineFPS }
        return screen.maximumFramesPerSecond
    }
}

extension CheckPanelVisibility {
    /// 패널 생성 경로가 마지막에 부르는 한 줄. **창 알파를 만지는 곳은 여기뿐이어야 한다** —
    /// 다른 곳에서 만지면 "투명하게 했더니 글자가 안 보인다" 신고가 그대로 되살아난다.
    ///
    /// `@MainActor` 인 이유는 `NSWindow.alphaValue` 가 메인 액터 격리라서다(두 호출자 모두 이미
    /// 메인 액터의 `makePanel` 이다). 안 붙이면 Swift 6 가 경고만 내고 통과시키는데, 그 경고는
    /// 언젠가 오류가 되는 종류다.
    @MainActor
    static func apply(to panel: NSPanel) {
        panel.alphaValue = panelAlpha
    }
}

extension CharacterCatalog {
    /// 메뉴바·팝오버용 초상 PNG 의 절대 URL. 내장 아잉·3D 캐릭터는 nil(호출부는 종전 `aing-*.png` 경로를 쓴다).
    func portraitURL(for id: String, mood: CheckMascotAssets.Mood) -> URL? {
        guard let entry = entry(id: id), let directory = entry.directory,
              let portrait = entry.manifest.portrait else { return nil }
        let file = mood == .neutral ? portrait.neutral : portrait.negative
        return directory.appendingPathComponent(file)
    }
}

extension CharacterCatalog {
    /// 번들에서 카탈로그를 만든다. 폴더가 없으면(아직 캐릭터를 안 실은 빌드) 아잉만 담긴 카탈로그.
    static func load(
        bundle: Bundle = CheckResources.bundle,
        subdirectory: String = charactersSubdirectory,
        fileManager: FileManager = .default
    ) -> CharacterCatalog {
        load(charactersDirectory: directoryURL(in: bundle, named: subdirectory, fileManager: fileManager),
             fileManager: fileManager)
    }
}

extension CodexAccountUsageStore {
    /// 프로덕션 조립: 실홈 + 로그인 셸의 CODEX_HOME + 실제 프로브. **CheckApp 한 곳에서만** 만든다(소스 계약 테스트가 되묻는다).
    static func live(defaults: UserDefaults = .standard) -> CodexAccountUsageStore {
        let version = UpdateCheckStore.bundleShortVersion()
        return CodexAccountUsageStore(
            defaults: defaults,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            codexHome: { await CodexAccountUsageProbe.resolveCodexHome() },
            runner: { home, now in
                await CodexAccountUsageProbe.fetch(homeDirectory: home, appVersion: version, now: now)
            }
        )
    }
}
