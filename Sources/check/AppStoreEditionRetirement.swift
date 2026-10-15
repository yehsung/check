import AppKit
import CheckCore
import ServiceManagement
import SwiftUI
import os

// MARK: - 앱스토어 판이 설치된 맥에서 이 판(brew·DMG)이 물러난다 (v0.3.53)
//
// 2026-10-15 결정("추천대로 해줘"): 같은 맥에 **맥 앱스토어 판**(번들 `com.yehsung.aingcheck`)이 설치돼 있으면 **Developer ID 판**
// (번들 `kingcheck`, brew·DMG)이 물러난다. 두 판이 함께 돌면 같은 맥이 서버에 기기 두 대로 잡혀 토큰이 두 번 집계되고, 전역 단축키
// 하나에 두 앱이 함께 근무를 토글한다. 설치 자체는 못 막으니(앱스토어 설치기 · DMG 드래그) **실행을 막는다.**
//
//  · 실행 시점(B): 델리게이트가 만들어지는 순간 판정한다(`AppStoreRetirementState.live()`). 참이면 메뉴바 아이콘을 **넣지 않고**
//    (첫 렌더부터 — `CheckApp.body` 의 `MenuBarExtra(isInserted:)`), 세션 활성화·단축키·로그인 항목·감시·오버레이·할 일·오목/체스
//    배선을 **하나도** 하지 않고, 물러남 창 하나만 띄운다. 스토어에도 2차 게이트가 있다(`WorkTimerStore.retiredForAppStoreEdition`).
//  · 실행 중(C): 앱스토어 판이 켜지는 것을 보면(`AppStoreEditionLaunchWatcher` — 주 경로는 실행 중 앱 목록 KVO) 근무 시작을
//    막고, 내가 연 근무를 평소 종료처럼 마무리하고, 자기를 새 인스턴스로 다시 띄워 물러남 모드로 들어가게 한 뒤 이 인스턴스는
//    끝난다(재실행이 실패해도 끝난다).
//  · 창(D): [이 판 지우고 앱스토어 판 열기] — 누른 순간 앱스토어 판을 **다시 판정**하고(없으면 아무것도 안 지우고 끝) →
//    로그인 항목 해제 → (brew 가 관리하면) 떼어 낸 셸로 `brew uninstall --cask`(결과는 상태 파일에), (그 밖이면) 자기 번들을
//    휴지통으로(실패하면 Finder 로 보여 주기 · 번역 경로면 원래 자리를 보여 주기만) → 이 앱이 끝난 뒤 앱스토어 판 열기 → 종료.
//    **자기 번들 말고는 아무것도 지우지 않는다.** [나중에]·창 닫기는 그냥 종료(로그인 항목은 그대로 — 다음 로그인에 다시 묻는
//    것이 의도다).
//
// ★ 판정은 **못 찾음 쪽으로 기운다.** 오탐은 사용자의 근무를 멈추지만, 미탐은 지금 상태(앱스토어 판의 경고 한 번)로 돌아갈 뿐이다.
//   개발 맥에는 같은 번들 ID 의 앱이 여럿 있다(`scripts/package-mas.sh` 산출물 · 스크래치 빌드 — 영수증이 없다). 그래서 **앱스토어가
//   설치한 사본에만 있는 영수증**(`Contents/_MASReceipt/receipt`)을 요구하고, 영수증까지 복사된 외장·백업 사본에 반응하지 않게
//   **시동 볼륨 위의 사본만** 본다. 개발자 탈출구는 UserDefaults 키 하나다
//   (`check.allowAlongsideAppStoreEdition` — UI 없음, docs/mac-app-store-edition.md).
//
// ★ 이 파일 전체가 앱스토어 판에서 **컴파일되지 않는다** — 그 판(0.3.52, 심사 중)의 동작·바이너리는 바뀌면 안 된다.
//   그 판의 패키징 게이트가 `uninstall --cask` 를 금지 문자열로 잰다(scripts/package-mas.sh).
#if !CHECK_MAS

/// 물러남 판정(순수 함수 + 실제 파일 시스템 읽기). 화면·프로세스·LaunchServices 는 여기서 건드리지 않는다(후보 목록은 호출자가 준다).
enum AppStoreEditionRetirement {
    /// 앱스토어 판의 번들 식별자(판정표 한 곳에서 가져온다).
    static let appStoreBundleIdentifier = MacEdition.appStore.bundleIdentifier
    /// 앱스토어 판이 설치되는 자리(패키징 스크립트의 `APP_NAME`). LaunchServices 가 아직 모르는 직후에도 찾게 후보에 늘 넣는다.
    static let conventionalInstallURL = URL(fileURLWithPath: "/Applications/AingCheck.app", isDirectory: true)
    /// 개발자 탈출구 — 참이면 물러나지 않는다(UI 없음 · `defaults write kingcheck check.allowAlongsideAppStoreEdition -bool true`).
    static let allowAlongsideKey = "check.allowAlongsideAppStoreEdition"
    /// 실행 중 물러남이 다시 띄운 인스턴스에 넘기는 인자: "하던 근무를 여기서 마무리했다".
    static let finishedWorkArgument = "--check-retire-finished-work"
    /// 실행 중 물러남이 다시 띄운 인스턴스에 넘기는 인자: 그때 본 앱스토어 판의 번들 경로(다음 인자). 판정은 다시 한다(힌트일 뿐이다).
    static let appStoreEditionArgument = "--check-retire-app-store-edition"

    static let logger = Logger(subsystem: "kingcheck", category: "retire")

    // MARK: A. 설치된 앱스토어 판인가

    /// 이 번들이 **이 맥에 앱스토어가 설치한 앱스토어 판**인가. 전부 참이어야 한다(하나라도 못 읽으면 거짓):
    ///  1. 휴지통 안이 아니다(LaunchServices 는 휴지통의 앱도 기억한다).
    ///  2. 시동 볼륨 위다(`isOnStartupVolume`) — 외장 디스크 · 복제 백업 · 마운트된 디스크 이미지의 사본은 '이 맥에 설치된' 것이
    ///     아니다. LaunchServices 는 마운트된 볼륨의 앱도 기억하고, 복제 백업에는 영수증까지 복사돼 있다.
    ///  3. `Contents/Info.plist` 의 `CFBundleIdentifier` 가 정확히 `com.yehsung.aingcheck`.
    ///  4. `Contents/_MASReceipt/receipt` 가 비어 있지 않은 파일로 있다 — 앱스토어가 설치한 사본에만 있다.
    ///  5. `Contents/MacOS` 가 있다 — 아이폰 앱을 맥에서 돌리는 래퍼(`Wrapper/` · `WrappedBundle`, 같은 번들 ID)는 아니다.
    static func isInstalledAppStoreEdition(
        _ url: URL,
        fileManager: FileManager = .default,
        isOnStartupVolume: (URL) -> Bool = AppStoreEditionRetirement.isOnStartupVolume
    ) -> Bool {
        let paths = [url.standardizedFileURL.path, url.resolvingSymlinksInPath().path]
        guard !paths.contains(where: isInTrash) else { return false }
        guard isOnStartupVolume(url) else { return false }
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        guard infoPlistBundleIdentifier(contents.appendingPathComponent("Info.plist")) == appStoreBundleIdentifier else {
            return false
        }
        guard isNonEmptyFile(contents.appendingPathComponent("_MASReceipt/receipt"), fileManager: fileManager) else {
            return false
        }
        guard isDirectory(contents.appendingPathComponent("MacOS", isDirectory: true), fileManager: fileManager) else {
            return false
        }
        // 래퍼 표지가 하나라도 있으면 아이폰 앱이다(MacOS 폴더 판정의 짝 — 모호하면 '없음'으로 기운다).
        for marker in ["Wrapper", "WrappedBundle"]
        where fileManager.fileExists(atPath: url.appendingPathComponent(marker).path) {
            return false
        }
        return true
    }

    /// 후보 중 첫 번째 '설치된 앱스토어 판'. 같은 자리는 한 번만 본다.
    static func installedAppStoreEdition(among candidates: [URL], fileManager: FileManager = .default) -> URL? {
        var seen = Set<String>()
        for url in candidates where seen.insert(url.standardizedFileURL.path).inserted {
            if isInstalledAppStoreEdition(url, fileManager: fileManager) { return url }
        }
        return nil
    }

    /// 이 판이 물러날 수 있는가 — 판정표(앱스토어 판은 **언제나** 아니다) + 개발자 탈출구.
    static func retirementApplies(edition: MacEdition, defaults: UserDefaults) -> Bool {
        edition.retiresWhenAppStoreEditionInstalled && !defaults.bool(forKey: allowAlongsideKey)
    }

    /// **실행 시점 판정**(B). 물러나야 하면 찾은 앱스토어 판의 번들 URL, 아니면 nil.
    /// 후보는 물러날 수 있을 때만 묻는다 — 앱스토어 판·탈출구에서는 LaunchServices 를 건드리지도 않는다.
    static func launchDecision(
        edition: MacEdition,
        defaults: UserDefaults,
        candidates: () -> [URL],
        fileManager: FileManager = .default
    ) -> URL? {
        guard retirementApplies(edition: edition, defaults: defaults) else { return nil }
        return installedAppStoreEdition(among: candidates(), fileManager: fileManager)
    }

    /// **실행 중 판정**(C). 막 켜진 앱이 앱스토어 판이고 그 번들이 설치된 사본이면 그 URL, 아니면 nil
    /// (개발 맥의 스크래치 빌드 · 휴지통에서 띄운 사본에는 반응하지 않는다).
    static func midRunDecision(
        launchedBundleIdentifier: String?,
        launchedBundleURL: URL?,
        edition: MacEdition,
        defaults: UserDefaults,
        fileManager: FileManager = .default
    ) -> URL? {
        guard retirementApplies(edition: edition, defaults: defaults),
              launchedBundleIdentifier == appStoreBundleIdentifier,
              let launchedBundleURL,
              isInstalledAppStoreEdition(launchedBundleURL, fileManager: fileManager)
        else { return nil }
        return launchedBundleURL
    }

    /// 실행 중 물러남에서 근무를 평소 종료처럼 마무리하는가 — `AppDelegate.applicationShouldTerminate` 의 가드와 **같은 조건**이다
    /// (로그인 · 근무 중 · 내가 연 세션). 흡수 세션(다른 기기가 연 세션)은 이 맥이 끝내지 않는다.
    ///
    /// 넘기지 않고 끝내는 이유: 끄기만 하면 앱스토어 판이 그 세션을 흡수해도 이 맥의 기기 주장 행 때문에 되찾지 않고, 스캐빈저가
    /// 10분 뒤 마지막 신호 시각으로 닫는다 — 결과는 같고 더 헷갈린다.
    static func shouldFinishWorkBeforeRetiring(isSignedIn: Bool, startedAt: Date?, adoptedRemoteSession: Bool) -> Bool {
        isSignedIn && startedAt != nil && !adoptedRemoteSession
    }

    // MARK: 다시 띄우기 인자

    /// 실행 중 물러남이 새 인스턴스에 넘기는 인자.
    static func relaunchArguments(finishedWork: Bool, appStoreEdition: URL) -> [String] {
        (finishedWork ? [finishedWorkArgument] : []) + [appStoreEditionArgument, appStoreEdition.path]
    }

    /// 실행 인자에서 읽어 낸 것. 앱스토어 판 경로는 **힌트**다 — 판정은 같은 조건으로 다시 한다.
    struct LaunchArguments: Equatable {
        var finishedWork = false
        var appStoreEditionHint: URL?
    }

    static func parseLaunchArguments(_ arguments: [String]) -> LaunchArguments {
        var parsed = LaunchArguments()
        parsed.finishedWork = arguments.contains(finishedWorkArgument)
        if let index = arguments.firstIndex(of: appStoreEditionArgument), arguments.indices.contains(index + 1) {
            let path = arguments[index + 1]
            if path.hasPrefix("/") { parsed.appStoreEditionHint = URL(fileURLWithPath: path, isDirectory: true) }
        }
        return parsed
    }

    // MARK: 자기 번들

    /// 지금 도는 번들이 **우리 Developer ID 앱 번들**인가(`.app` 이고 번들 ID 가 `kingcheck`). 지우기는 이 판정이 참일 때만
    /// 자기 번들을 휴지통으로 보낸다 — `swift run` 같은 개발 실행에서는 `Bundle.main.bundleURL` 이 빌드 폴더라, 이 판정 없이
    /// 지우면 엉뚱한 폴더가 사라진다.
    static func isOwnDeveloperIDBundle(_ url: URL) -> Bool {
        url.pathExtension == "app"
            && infoPlistBundleIdentifier(url.appendingPathComponent("Contents/Info.plist"))
                == MacEdition.developerID.bundleIdentifier
    }

    // MARK: 파일 읽기(실패 = 거짓)

    static func isInTrash(_ path: String) -> Bool {
        path.contains("/.Trash/") || path.contains("/.Trashes/")
    }

    /// 실제 자리(심링크를 걷은 곳)가 **시동 볼륨**(`/` 와 그 데이터 볼륨 — `/Applications` · 홈)인가. 못 읽으면 거짓.
    /// 2026-10-15 실측: `/Applications` · `/Users/…` · 임시 폴더 · `/Volumes/Macintosh HD`(→ `/`) → 참,
    /// 마운트된 디스크 이미지 `/Volumes/<이름>` → 거짓. 외장 디스크 · 복제 백업 · Time Machine 도 `/Volumes/` 아래라 거짓이다.
    static func isOnStartupVolume(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        return (try? resolved.resourceValues(forKeys: [.volumeIsRootFileSystemKey]))?.volumeIsRootFileSystem == true
    }

    /// Info.plist 의 `CFBundleIdentifier`. `Bundle(url:)` 은 경로별로 캐시해서 같은 자리의 바뀐 내용을 못 본다 — 파일을 직접 읽는다.
    static func infoPlistBundleIdentifier(_ plist: URL) -> String? {
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any]
        else { return nil }
        return dictionary["CFBundleIdentifier"] as? String
    }

    private static func isNonEmptyFile(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        else { return false }
        return size.intValue > 0
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    // MARK: 후보(LaunchServices · 실행 중 앱 · 관례 자리)

    /// 후보를 묻는 문. 실제로는 `.live`(LaunchServices · 실행 중 앱 목록 · 관례 자리)이고 테스트는 가짜를 넣는다 —
    /// 실행 시점 판정(`AppStoreRetirementState.live`)과 지우기 직전 다시 판정(`AppStoreRetireRemoval.live`)이 같은 문을 쓴다.
    struct CandidateSources {
        /// LaunchServices 가 아는 그 번들 ID 의 사본들.
        var registered: @MainActor (_ bundleIdentifier: String) -> [URL]
        /// 지금 돌고 있는 그 번들 ID 의 사본들.
        var running: @MainActor (_ bundleIdentifier: String) -> [URL]
        /// 늘 보는 자리(LaunchServices 가 아직 모르는 설치 직후에도 찾게).
        var fixed: [URL]

        @MainActor
        static var live: CandidateSources {
            CandidateSources(
                registered: { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) },
                running: { identifier in
                    NSWorkspace.shared.runningApplications
                        .filter { $0.bundleIdentifier == identifier }
                        .compactMap(\.bundleURL)
                },
                fixed: [AppStoreEditionRetirement.conventionalInstallURL]
            )
        }
    }

    /// 후보 목록: 힌트(실행 중 물러남이 넘긴 경로 · 창이 처음 찾은 자리) · LaunchServices 가 아는 사본들 · 지금 돌고 있는 사본 · 관례 자리.
    @MainActor
    static func candidates(hint: URL?, sources: CandidateSources = .live) -> [URL] {
        (hint.map { [$0] } ?? [])
            + sources.registered(appStoreBundleIdentifier)
            + sources.running(appStoreBundleIdentifier)
            + sources.fixed
    }

    // MARK: App Translocation

    /// App Translocation(격리 표시가 붙은 앱을 끌어다 놓지 않고 바로 연 경우 macOS 가 읽기 전용 임시 자리로 옮겨 띄운다)으로
    /// 도는 번들의 **원래 자리**. 번역 경로가 아니거나 못 물으면 nil.
    /// `SecTranslocateCreateOriginalPathForURL`(Security, macOS 10.12+)은 SDK 머리 파일에 없어 이름으로 찾는다
    /// (2026-10-15 이 맥에서 기호가 있음을 실측). 못 찾으면 nil 로 기운다 — 그러면 임시 자리를 보여 준다(예전과 같다).
    static func translocationOriginal(of url: URL) -> URL? {
        guard url.path.contains("/AppTranslocation/"), let original = translocationOriginalFunction else { return nil }
        guard let result = original(url as CFURL, nil)?.takeRetainedValue() else { return nil }
        let path = (result as URL).path
        guard path.hasPrefix("/"), !path.contains("/AppTranslocation/") else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    typealias TranslocationOriginalFunction =
        @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    /// Security 의 `SecTranslocateCreateOriginalPathForURL`(없으면 nil).
    static var translocationOriginalFunction: TranslocationOriginalFunction? {
        guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL")
        else { return nil }
        return unsafeBitCast(symbol, to: TranslocationOriginalFunction.self)
    }
}

// MARK: - 이 실행의 물러남 상태 (관찰 가능 — 메뉴바 아이콘이 읽는다)

/// 이 실행이 물러났는가와 메뉴바 아이콘을 넣는가. **델리게이트가 만들어지는 순간** 정해진다 — `CheckApp.body` 가 첫 렌더부터
/// `menuBarInserted` 를 읽어야 해서 `applicationDidFinishLaunching` 까지 기다릴 수 없다.
@Observable
@MainActor
final class AppStoreRetirementState {
    /// 실행 시점에 찾은 앱스토어 판(있으면 이 실행은 처음부터 물러남 모드다).
    let launchAppStoreEdition: URL?
    /// 실행 중 물러남이 하던 근무를 마무리하고 다시 띄운 인스턴스인가(창에 한 줄 더 쓴다).
    let finishedWorkBeforeRelaunch: Bool
    /// 메뉴바 아이콘을 넣는가. 물러남 모드는 첫 렌더부터 거짓이고, 실행 중 물러남도 마무리하는 동안 내린다.
    private(set) var menuBarInserted: Bool
    /// 실행 중 물러남이 시작됐다(두 번 시작하지 않는다).
    private(set) var isRetiringMidRun = false

    init(launchAppStoreEdition: URL?, finishedWorkBeforeRelaunch: Bool = false) {
        self.launchAppStoreEdition = launchAppStoreEdition
        self.finishedWorkBeforeRelaunch = launchAppStoreEdition != nil && finishedWorkBeforeRelaunch
        self.menuBarInserted = launchAppStoreEdition == nil
    }

    /// 이 실행이 처음부터 물러남 모드인가.
    var isRetiredAtLaunch: Bool { launchAppStoreEdition != nil }

    /// 실제 실행의 판정(이 프로세스의 판 · 실행 인자 · 표준 UserDefaults · LaunchServices). 테스트는 `sources` 에 가짜를 넣어
    /// **이 함수를 그대로** 부른다(인자 해석 · 힌트 · 후보 조립 · 근무 마무리 표식이 한 줄도 빠지지 않았는지).
    static func live(
        edition: MacEdition = .current,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        defaults: UserDefaults = .standard,
        sources: AppStoreEditionRetirement.CandidateSources = .live
    ) -> AppStoreRetirementState {
        let parsed = AppStoreEditionRetirement.parseLaunchArguments(arguments)
        let found = AppStoreEditionRetirement.launchDecision(
            edition: edition,
            defaults: defaults,
            candidates: { AppStoreEditionRetirement.candidates(hint: parsed.appStoreEditionHint, sources: sources) }
        )
        if let found {
            AppStoreEditionRetirement.logger.notice("앱스토어 판이 설치돼 있어 물러남 모드로 시작한다: \(found.path, privacy: .private)")
        }
        return AppStoreRetirementState(launchAppStoreEdition: found, finishedWorkBeforeRelaunch: parsed.finishedWork)
    }

    /// 실행 중 물러남을 시작한다 — 아이콘을 내린다. 이미 시작했거나 처음부터 물러남이면 거짓(아무것도 안 한다).
    @discardableResult
    func beginMidRunRetirement() -> Bool {
        guard !isRetiredAtLaunch, !isRetiringMidRun else { return false }
        isRetiringMidRun = true
        menuBarInserted = false
        return true
    }

    /// `MenuBarExtra(isInserted:)` 에 쓰기가 왔다 — 앱을 끝내야 하는가. 참이면 **사용자가 ⌘-끌기로 아이콘을 뺀 것**이다
    /// (우리가 내린 경우 — 물러남 — 에는 이미 거짓이라 여기서 거짓).
    ///
    /// 왜 끝내는가(2026-10-15 실측): 0.3.52 의 `MenuBarExtra { }` 가 만든 상태 항목은 behavior 가
    /// `removalAllowed | terminationOnRemoval` 이라 빼면 앱이 끝났다. `isInserted` 갈래는 `removalAllowed` 뿐이라 그대로 두면
    /// 아이콘 없는 앱이 남는다 — LSUIElement 라 다시 열어도 기존 인스턴스만 깨어나고, 근무·단축키는 보이지 않게 돈다.
    /// 그래서 같은 결과(종료 — 근무 중이면 평소처럼 마무리)를 낸다.
    func shouldQuitAfterMenuBarWrite(inserted: Bool) -> Bool {
        !inserted && menuBarInserted
    }
}

// MARK: - 실행 중 감지 (C)

/// 앱스토어 판이 **켜지는 순간**을 본다. 판정은 주입한 `decide` 가 하고(실제로는 `AppStoreEditionRetirement.midRunDecision`),
/// 참이면 `onAppStoreEditionLaunched` 를 부른다. 앱 수명 동안 하나다.
///
/// ★ **주 경로는 `NSWorkspace.runningApplications` 의 KVO 다**(`workspace` 를 줄 때만 — 테스트는 주지 않고 같은 처리 함수
///   `report` · `appStoreEditionLaunches` 를 직접 부른다). 앱스토어 판은 메뉴바 전용 앱(LSUIElement)인데, 2026-10-15 실측으로
///   LSUIElement 앱이 켜질 때 `didLaunchApplicationNotification` 은 **오지 않았고** KVO 삽입 변경만 왔다(스크래치 더미 앱).
///   켜짐 통지 관찰은 일반 앱 모양으로 바뀔 때를 위한 보조 길로 남긴다. 두 길이 같은 켜짐을 두 번 알려도
///   받는 쪽(`retireMidRun`)은 한 번만 움직인다.
@MainActor
final class AppStoreEditionLaunchWatcher {
    /// 켜진 앱 하나의 사실. `NSRunningApplication` 은 테스트에서 만들 수 없어 값으로 옮긴다.
    struct Launch: Equatable {
        var bundleIdentifier: String?
        var bundleURL: URL?
    }

    private let center: NotificationCenter
    private let decide: @MainActor (_ bundleIdentifier: String?, _ bundleURL: URL?) -> URL?
    private let onAppStoreEditionLaunched: @MainActor (URL) -> Void
    private var token: NSObjectProtocol?
    private var runningObservation: NSKeyValueObservation?

    init(
        center: NotificationCenter,
        workspace: NSWorkspace? = nil,
        decide: @escaping @MainActor (_ bundleIdentifier: String?, _ bundleURL: URL?) -> URL?,
        onAppStoreEditionLaunched: @escaping @MainActor (URL) -> Void
    ) {
        self.center = center
        self.decide = decide
        self.onAppStoreEditionLaunched = onAppStoreEditionLaunched
        token = center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let launch = Launch(bundleIdentifier: app?.bundleIdentifier, bundleURL: app?.bundleURL)
            MainActor.assumeIsolated { self?.report([launch]) }
        }
        runningObservation = workspace?.observe(\.runningApplications, options: [.new]) { [weak self] _, change in
            // 삽입 변경이면 newValue 가 **새로 들어온 앱들**이다(빠지는 변경은 nil). 번들 ID 로 먼저 걸러 메인으로 넘긴다.
            let launched = Self.appStoreEditionLaunches(
                (change.newValue ?? []).map { Launch(bundleIdentifier: $0.bundleIdentifier, bundleURL: $0.bundleURL) }
            )
            guard !launched.isEmpty else { return }
            Task { @MainActor in self?.report(launched) }
        }
    }

    /// KVO 삽입 변경의 새 앱들 중 **앱스토어 판 번들 ID** 인 것만(다른 앱이 켜질 때마다 메인으로 넘기지 않게).
    nonisolated static func appStoreEditionLaunches(_ launched: [Launch]) -> [Launch] {
        launched.filter { $0.bundleIdentifier == AppStoreEditionRetirement.appStoreBundleIdentifier }
    }

    /// 켜진 앱들을 차례로 판정에 넘기고, 처음 참인 것 하나로 `onAppStoreEditionLaunched` 를 부른다(두 길이 함께 쓴다).
    func report(_ launched: [Launch]) {
        for launch in launched {
            guard let found = decide(launch.bundleIdentifier, launch.bundleURL) else { continue }
            onAppStoreEditionLaunched(found)
            return
        }
    }

    /// 감시를 끈다(멱등).
    func stop() {
        if let token { center.removeObserver(token) }
        token = nil
        runningObservation?.invalidate()
        runningObservation = nil
    }
}

// MARK: - 지우기 계획 (D)

/// [이 판 지우고 앱스토어 판 열기]가 할 일 한 벌. **계획(순수 값)과 실행(주입한 효과)을 가른다** — 테스트는 계획을 그대로 보고,
/// 가짜 효과로 실행 순서를 잰다(실제 휴지통·SMAppService·Process·brew 는 건드리지 않는다).
struct AppStoreRetireRemoval: Equatable {
    enum Step: Equatable {
        /// 로그인 항목 해제 — **먼저.** 안 하면 휴지통의 앱이 로그인 때 다시 뜰 수 있다.
        case unregisterLoginItem
        /// 떼어 낸 셸로 `brew uninstall --cask` 를 돌린다(끝나면 그 셸이 앱스토어 판을 연다). `zsh` 에 넘길 인자 전부.
        case spawnBrewUninstall(arguments: [String])
        /// 자기 번들을 휴지통으로 — 실패하면(읽기 전용 볼륨 · 권한) Finder 에서 보여 준다.
        case moveToTrashOrReveal(URL)
        /// Finder 에서 보여 주기만 한다(번역 경로의 원래 자리 · 지난번 brew 가 못 지운 자기 번들). 아무것도 지우지 않는다.
        case revealInFinder(URL)
        /// 떼어 낸 셸이 **이 앱이 끝난 뒤에** 앱스토어 판을 연다. 이 앱이 살아 있을 때 열면 앱스토어 판의 첫 실행이 이 앱을 보고
        /// "다른 아잉체크가 켜져 있어요" 경고(한 번뿐)를 써 버린다. 셸을 못 띄우면 직접 연다. `zsh` 에 넘길 인자 전부.
        case spawnOpenAfterExit(arguments: [String])
        /// 이 앱을 끝낸다.
        case terminate
    }

    let steps: [Step]
    /// 자기 번들(brew 셸을 못 띄웠을 때 Finder 로 보여 줄 자리).
    let ownBundle: URL
    /// 앱스토어 판(셸을 못 띄웠을 때 직접 연다).
    let appStoreEdition: URL

    /// 셸 꼬리표(로그 줄 머리 · `$0`). 업데이트 스크립트의 꼬리표와 다르다(그 판의 금지 문자열과 섞이지 않게).
    static let scriptLabel = "aing-check-retire"
    /// 셸의 로그(이 맥에만 남는다 — 전송 없음).
    static let logPath = NSString(string: "~/Library/Logs/aing-check-retire.log").expandingTildeInPath
    /// brew 셸이 결과를 적는 상태 파일(`ok` · `brew-failed`). 다음 물러남 창이 읽어 "지난번에 못 지웠다"를 알린다.
    /// 자리는 `~/Library/Caches/kingcheck/` — cask 의 `zap trash:` 목록에 그 폴더가 있다(업데이트 상태 파일과 같은 이유).
    static let statePath = NSString(string: "~/Library/Caches/kingcheck/retire.state").expandingTildeInPath
    /// 상태 파일에서 "brew 가 못 지웠다"를 뜻하는 글자.
    static let brewFailedState = "brew-failed"

    /// brew 분리 스폰 래퍼. **순수 상수다 — 어떤 값도 끼워 넣지 않는다**(`UpdateRunner.dmgSpawnWrapper` 와 같은 이유: 경로에
    /// `'`·`"`·`$`·`;` 가 있어도 데이터로만 남는다). 바깥 셸이 전개하는 것은 `$1`…`$7` 뿐이고 전개 결과는 다시 파싱되지 않는다.
    /// `$1` 스크립트 · `$2` brew · `$3` cask 이름 · `$4` 앱스토어 판 경로 · `$5` 이 앱의 PID · `$6` 상태 파일 · `$7` 로그 파일.
    static let spawnWrapper = #"nohup zsh -c "$1" aing-check-retire "$2" "$3" "$4" "$5" "$6" >>"$7" 2>&1 &"#

    /// brew 로 이 판을 지우는 스크립트. **상수**이고 값은 전부 위치 인자다:
    /// `$1` brew · `$2` cask · `$3` 앱스토어 판 · `$4` 이 앱의 PID · `$5` 상태 파일.
    ///  · 이 앱이 먼저 끝나기를 잠깐(최대 10초) 기다린다 — cask 의 `uninstall quit:` 가 끝낼 앱이 없게(Apple Event 권한 창이 끼지 않게).
    ///  · `set -e` 를 쓰지 않는다(zsh 의 errexit 은 `||` 목록에서 실패를 흘린다) — 실패는 로그와 상태 파일에 남기고 앱스토어 판은 그래도 연다.
    ///  · 무엇도 지우지 않는다 — 지우는 것은 brew 가 자기 기록대로 하는 일뿐이다(이 판의 앱 · Caskroom 기록).
    ///  · 본문에 슬래시-별표 · 슬래시 두 개를 쓰지 않는다 — 소스를 읽는 계약 테스트의 주석 걷어내기가 그것을 주석 시작으로 읽고
    ///    파일 뒷부분을 통째로 지운다(그러면 앱스토어 판 금지 문자열 게이트가 이 명령을 못 찾는다). 폴더는 `dirname` 으로 뽑는다.
    static let brewUninstallScript = """
        BREW="$1"; CASK="$2"; APP_STORE="$3"; APP_PID="$4"; STATE="$5"
        M="[aing-check-retire]"
        echo "$M ---- 시작 $(date +%Y-%m-%dT%H:%M:%S)"
        mkdir -p "$(dirname "$STATE")"
        i=0
        while [ -n "$APP_PID" ] && [ "$i" -lt 50 ] && kill -0 "$APP_PID" 2>/dev/null; do sleep 0.2; i=$((i+1)); done
        if "$BREW" uninstall --cask "$CASK"; then
          printf 'ok\\n' > "$STATE"
        else
          echo "$M 경고: brew 가 지우지 못했습니다(code $?)"
          printf 'brew-failed\\n' > "$STATE"
        fi
        open "$APP_STORE" || echo "$M 경고: 앱스토어 판을 열지 못했습니다"
        echo "$M ---- 끝"
        """

    /// 앱스토어 판 열기 분리 스폰 래퍼(상수). `$1` 스크립트 · `$2` 앱스토어 판 경로 · `$3` 이 앱의 PID · `$4` 로그 파일.
    static let openSpawnWrapper = #"nohup zsh -c "$1" aing-check-retire "$2" "$3" >>"$4" 2>&1 &"#

    /// 이 앱이 끝나기를 잠깐(최대 10초) 기다렸다가 앱스토어 판을 여는 스크립트(상수). `$1` 앱스토어 판 · `$2` 이 앱의 PID.
    static let openAfterExitScript = """
        APP_STORE="$1"; APP_PID="$2"
        M="[aing-check-retire]"
        i=0
        while [ -n "$APP_PID" ] && [ "$i" -lt 50 ] && kill -0 "$APP_PID" 2>/dev/null; do sleep 0.2; i=$((i+1)); done
        open "$APP_STORE" || echo "$M 경고: 앱스토어 판을 열지 못했습니다"
        """

    /// 지난번 [지우기]에서 brew 가 이 판을 지우지 못했는가(상태 파일 — 없거나 못 읽으면 거짓).
    static func previousBrewUninstallFailed(
        readState: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }
    ) -> Bool {
        readState(statePath)?.trimmingCharacters(in: .whitespacesAndNewlines) == brewFailedState
    }

    /// 설치 출처에 따라 계획을 만든다. 출처 판정은 업데이트와 같은 것을 쓴다(`UpdateRunner.installSource` · `brewPath` —
    /// brew 가 **이 번들을** 관리할 때만 `.brew`).
    ///  · `.brew`(+ brew 경로) → [로그인 항목 해제, (지난번 brew 가 실패했으면 자기 번들 보여 주기), brew 셸, 종료]
    ///  · 그 밖 → [로그인 항목 해제, 자기 번들 휴지통(또는 Finder — 번역 경로면 원래 자리를 보여 주기만), 끝난 뒤 열기 셸, 종료]
    ///  · 자기 번들이 우리 `.app` 이 아니면(`swift run` 같은 개발 실행) 아무것도 지우지도 보여 주지도 않는다.
    static func plan(
        installSource: InstallSource,
        brewPath: String?,
        ownBundle: URL,
        ownBundleIsApp: Bool,
        translocatedOriginal: URL? = nil,
        previousBrewUninstallFailed: Bool = false,
        appStoreEdition: URL,
        processID: Int32,
        logPath: String = AppStoreRetireRemoval.logPath,
        statePath: String = AppStoreRetireRemoval.statePath
    ) -> AppStoreRetireRemoval {
        var steps: [Step] = [.unregisterLoginItem]
        if installSource == .brew, let brewPath, ownBundleIsApp {
            // 지난번에 brew 가 못 지웠다(권한 · 잠금) — 이번에도 못 지우면 사용자가 직접 옮길 수 있게 그 자리를 먼저 보여 준다.
            if previousBrewUninstallFailed { steps.append(.revealInFinder(ownBundle)) }
            steps.append(.spawnBrewUninstall(arguments: [
                "-c", spawnWrapper,
                scriptLabel,
                brewUninstallScript,
                brewPath,
                UpdateRunner.caskName,
                appStoreEdition.path,
                String(processID),
                statePath,
                logPath,
            ]))
        } else {
            if ownBundleIsApp {
                // 번역 경로의 번들은 임시 읽기 전용 사본이다 — 휴지통 이동은 실패하고 원래 사본은 그대로 남는다.
                // 원래 자리를 보여 주기만 한다(거기도 지우지 않는다 — 자기 번들 말고는 아무것도 지우지 않는다).
                if let translocatedOriginal {
                    steps.append(.revealInFinder(translocatedOriginal))
                } else {
                    steps.append(.moveToTrashOrReveal(ownBundle))
                }
            }
            steps.append(.spawnOpenAfterExit(arguments: [
                "-c", openSpawnWrapper,
                scriptLabel,
                openAfterExitScript,
                appStoreEdition.path,
                String(processID),
                logPath,
            ]))
        }
        steps.append(.terminate)
        return AppStoreRetireRemoval(steps: steps, ownBundle: ownBundle, appStoreEdition: appStoreEdition)
    }

    /// [지우기]를 **누른 순간**의 계획(설치 출처 · brew 경로 · 자기 번들 · PID 를 실제로 읽는다). 테스트는 인자를 넣어 그대로 부른다.
    ///
    /// ★ 앱스토어 판을 **다시 판정한다.** 물러남 창은 몇 시간이고 떠 있을 수 있고, 그 사이 사용자가 본문 안내대로 앱스토어 판을
    ///   지웠을 수 있다(그러고 Return 으로 창을 닫으면 기본 버튼이 눌린다). 그때 지우기를 그대로 하면 두 판이 다 없는 맥이 된다 —
    ///   설치된 앱스토어 판이 없으면 nil(아무것도 지우지 않는다). 처음 찾은 자리가 사라졌어도 다른 사본이 있으면 그것을 연다.
    @MainActor
    static func live(
        appStoreEdition: URL,
        sources: AppStoreEditionRetirement.CandidateSources = .live,
        ownBundle: URL = Bundle.main.bundleURL,
        runner: UpdateRunner? = nil,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        readState: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) },
        translocationOriginal: (URL) -> URL? = AppStoreEditionRetirement.translocationOriginal(of:)
    ) -> AppStoreRetireRemoval? {
        guard let target = AppStoreEditionRetirement.installedAppStoreEdition(
            among: AppStoreEditionRetirement.candidates(hint: appStoreEdition, sources: sources)
        ) else {
            AppStoreEditionRetirement.logger.notice("지우기 직전 다시 보니 설치된 앱스토어 판이 없어 아무것도 지우지 않는다")
            return nil
        }
        let runner = runner ?? UpdateRunner(bundlePath: ownBundle.path)
        return plan(
            installSource: runner.installSource,
            brewPath: runner.brewPath,
            ownBundle: ownBundle,
            ownBundleIsApp: AppStoreEditionRetirement.isOwnDeveloperIDBundle(ownBundle),
            translocatedOriginal: translocationOriginal(ownBundle),
            previousBrewUninstallFailed: previousBrewUninstallFailed(readState: readState),
            appStoreEdition: target,
            processID: processID
        )
    }

    /// 계획을 순서대로 실행한다. 실패는 삼키지 않고 로그에 남긴다(효과 쪽이 남긴다).
    @MainActor
    func run(effects: AppStoreRetireEffects) async {
        for step in steps {
            switch step {
            case .unregisterLoginItem:
                effects.unregisterLoginItem()
            case let .spawnBrewUninstall(arguments):
                guard !effects.spawnDetached(arguments) else { continue }
                // 셸을 못 띄웠다. brew 가 관리하는 사본을 우리가 직접 지우면 brew 기록이 낡고 다음 `brew upgrade` 가 되살린다 —
                // 지우지 않고 Finder 로 보여 주고, 앱스토어 판은 연다.
                AppStoreEditionRetirement.logger.error("brew 셸을 띄우지 못해 Finder 로 보여 준다")
                effects.revealInFinder(ownBundle)
                await effects.openApplication(appStoreEdition)
            case let .moveToTrashOrReveal(url):
                if !effects.moveToTrash(url) { effects.revealInFinder(url) }
            case let .revealInFinder(url):
                effects.revealInFinder(url)
            case let .spawnOpenAfterExit(arguments):
                guard !effects.spawnDetached(arguments) else { continue }
                // 셸을 못 띄웠다 — 이 앱이 살아 있는 채로라도 연다(앱스토어 판이 경고 한 번을 보여 줄 수 있지만 열리지 않는 것보다 낫다).
                AppStoreEditionRetirement.logger.error("열기 셸을 띄우지 못해 앱스토어 판을 직접 연다")
                await effects.openApplication(appStoreEdition)
            case .terminate:
                effects.terminate()
            }
        }
    }
}

/// 지우기의 바깥 효과(주입 가능 — 테스트는 기록만 하는 가짜를 넣는다). `live` 만 실제 시스템을 건드린다.
@MainActor
struct AppStoreRetireEffects {
    var unregisterLoginItem: @MainActor () -> Void
    var spawnDetached: @MainActor ([String]) -> Bool
    var moveToTrash: @MainActor (URL) -> Bool
    var revealInFinder: @MainActor (URL) -> Void
    var openApplication: @MainActor (URL) async -> Void
    var terminate: @MainActor () -> Void

    static var live: AppStoreRetireEffects {
        AppStoreRetireEffects(
            unregisterLoginItem: {
                do {
                    try SMAppService.mainApp.unregister()
                } catch {
                    AppStoreEditionRetirement.logger.error("로그인 항목 해제 실패: \(error.localizedDescription, privacy: .public)")
                }
            },
            spawnDetached: { arguments in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = arguments
                do {
                    try process.run()
                    return true
                } catch {
                    AppStoreEditionRetirement.logger.error("brew 셸 실행 실패: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            },
            moveToTrash: { url in
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    return true
                } catch {
                    AppStoreEditionRetirement.logger.error("휴지통으로 옮기지 못했다: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            },
            revealInFinder: { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            },
            openApplication: { url in
                await AppStoreRetireEffects.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            },
            terminate: {
                NSApp.terminate(nil)
            }
        )
    }

    /// 앱을 열고 결과를 기다린다(최대 `timeout` 초 — LaunchServices 가 답을 안 줘도 종료가 막히지 않게). 실패는 로그에 남긴다.
    static func openApplication(
        at url: URL, configuration: NSWorkspace.OpenConfiguration, timeout: TimeInterval = 5
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = AppStoreRetireOnce()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    AppStoreEditionRetirement.logger.error("앱을 열지 못했다: \(error.localizedDescription, privacy: .public)")
                }
                if once.claim() { continuation.resume() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if once.claim() {
                    AppStoreEditionRetirement.logger.error("앱 열기 응답이 \(timeout, privacy: .public)초 안에 오지 않았다")
                    continuation.resume()
                }
            }
        }
    }

    /// 실행 중 물러남(C): 이 앱을 **새 인스턴스로** 다시 띄운다(인자로 근무 마무리 여부와 앱스토어 판 경로를 넘긴다).
    static func relaunchSelf(arguments: [String]) async {
        await openApplication(at: Bundle.main.bundleURL, configuration: relaunchConfiguration(arguments: arguments))
    }

    /// 다시 띄우기 설정(순수 — 테스트가 그대로 잰다). **새 인스턴스**여야 한다 — 아니면 LaunchServices 가 곧 끝날 지금 인스턴스만
    /// 깨우고 새 인스턴스는 뜨지 않아, 사용자에게는 근무 중이던 앱이 아무 안내 없이 사라진 것으로 보인다.
    static func relaunchConfiguration(arguments: [String]) -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        return configuration
    }
}

/// 한 번만 참을 내주는 표식(두 갈래 — 완료 · 시한 — 중 먼저 온 쪽만 continuation 을 깨운다).
private final class AppStoreRetireOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

// MARK: - 물러남 창 (D)

/// 물러남 창의 문구 한 벌(순수 값 — 테스트가 글자 그대로 되묻는다). 내부 용어(번들·판정·영수증)는 쓰지 않는다.
enum AppStoreRetireText {
    static let windowTitle = "아잉체크"
    static let title = "이 맥에 앱스토어 판 아잉체크가 있어요"
    /// 남는 것(계정의 기록·루비·팀·할 일)과 안 넘어가는 것(이 맥의 설정 — 앱스토어 판은 다른 저장 자리에서 빈 상태로 시작한다)을
    /// 함께 말한다. 출처는 "홈페이지나 brew" — 터미널로 깐 사람에게 "홈페이지에서 받은"은 사실이 아니다.
    static let body = "같은 맥에서 두 판이 함께 돌면 근무와 토큰이 두 번 집계될 수 있어서, 홈페이지나 brew 로 받은 이 판은 더 켜지지 않아요. 기록·루비·팀·할 일은 계정에 있어 앱스토어 판에서 다시 로그인하면 그대로예요. 단축키 같은 이 맥의 설정은 앱스토어 판에서 새로 맞춰 주세요. 이 판을 계속 쓰려면 앱스토어 판을 지워 주세요."
    static let finishedWork = "하던 근무는 여기서 마무리했어요. 앱스토어 판에서 다시 시작해 주세요."
    /// 지난번 [지우기]에서 brew 가 이 판을 지우지 못했을 때(상태 파일 — `AppStoreRetireRemoval.previousBrewUninstallFailed`).
    static let previousRemovalFailed = "지난번에 이 판을 다 지우지 못했어요. 이번에도 남아 있으면 Finder 에서 직접 휴지통으로 옮겨 주세요."
    static let remove = "이 판 지우고 앱스토어 판 열기"
    static let later = "나중에"

    /// 본문 문단들(실행 중 물러남이 근무를 마무리했으면 한 줄 더 · 지난번에 못 지웠으면 한 줄 더).
    static func paragraphs(finishedWork: Bool, previousRemovalFailed: Bool = false) -> [String] {
        [body]
            + (finishedWork ? [Self.finishedWork] : [])
            + (previousRemovalFailed ? [Self.previousRemovalFailed] : [])
    }
}

/// 물러남 창의 본문. 창 없이도 그릴 수 있어(`ImageRenderer`) 테스트가 크기를 잰다.
struct CheckAppStoreRetireView: View {
    let finishedWork: Bool
    var previousRemovalFailed = false
    let onRemove: () -> Void
    let onLater: () -> Void

    static let width: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppStoreRetireText.title, systemImage: "arrow.down.app.fill")
                .font(.headline)
                .foregroundStyle(CheckTheme.primaryText)
            ForEach(AppStoreRetireText.paragraphs(finishedWork: finishedWork, previousRemovalFailed: previousRemovalFailed),
                    id: \.self) { paragraph in
                Text(paragraph)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(AppStoreRetireText.later, action: onLater)
                    .keyboardShortcut(.cancelAction)
                Button(AppStoreRetireText.remove, action: onRemove)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: Self.width, alignment: .topLeading)
        .background(CheckTheme.background)
    }
}

/// 물러남 창 하나를 띄우고 지킨다(물러남 모드에서만 — AppDelegate 가 앱 수명 동안 든다). 창 띄우기는 첫 실행 안내
/// (`MacAppStoreOnboardingController`)와 같은 결이다: 다크 고정 · 지금 보는 Space · 테스트에서는 활성화하지 않는다.
@MainActor
final class AppStoreRetireWindowController: NSObject, NSWindowDelegate {
    enum Choice: Equatable { case remove, later }

    private let finishedWork: Bool
    private let previousRemovalFailed: Bool
    private let onRemove: @MainActor () -> Void
    private let onLater: @MainActor () -> Void
    private(set) var window: NSWindow?
    /// 고른 것(처음 하나만 따른다 — 두 번 눌러도 지우기가 두 번 돌지 않고, 지우는 중에 창이 닫혀도 [나중에]로 읽지 않는다).
    private(set) var choice: Choice?

    /// - Parameters:
    ///   - previousRemovalFailed: 지난번 [지우기]에서 brew 가 못 지웠다(창에 한 줄 더).
    ///   - onRemove: [이 판 지우고 앱스토어 판 열기]. 기본은 실제 지우기 — 누른 순간 `makeRemoval` 로 **다시 판정해** 계획을 만들고
    ///     `effects` 로 실행한다. 설치된 앱스토어 판이 더는 없으면(창이 떠 있는 동안 지웠다) 아무것도 지우지 않고 끝낸다.
    ///   - onLater: [나중에] · 창 닫기. 기본은 그냥 종료(`effects.terminate` — 로그인 항목은 그대로).
    ///   - effects: 바깥 효과(기본 `.live`). 테스트는 기록만 하는 가짜를 넣는다.
    ///   - makeRemoval: 누른 순간의 계획(기본 `AppStoreRetireRemoval.live`). nil 이면 지울 대상이 없다.
    init(
        appStoreEdition: URL,
        finishedWork: Bool,
        previousRemovalFailed: Bool = false,
        onRemove: (@MainActor () -> Void)? = nil,
        onLater: (@MainActor () -> Void)? = nil,
        effects: AppStoreRetireEffects = .live,
        makeRemoval: @escaping @MainActor (URL) -> AppStoreRetireRemoval? = { AppStoreRetireRemoval.live(appStoreEdition: $0) }
    ) {
        self.finishedWork = finishedWork
        self.previousRemovalFailed = previousRemovalFailed
        self.onRemove = onRemove ?? {
            guard let removal = makeRemoval(appStoreEdition) else {
                // 앱스토어 판이 사라졌다 — 사용자는 이 판을 계속 쓰려는 것이다. 아무것도 지우지 않고 [나중에]처럼 끝낸다
                // (다음 실행은 판정이 '없음'이라 평소대로 뜬다).
                effects.terminate()
                return
            }
            Task { @MainActor in await removal.run(effects: effects) }
        }
        self.onLater = onLater ?? effects.terminate
    }

    /// 창을 띄우고 앱을 앞으로 가져온다(테스트 프로세스에서는 활성화하지 않는다).
    func present() {
        let view = CheckAppStoreRetireView(
            finishedWork: finishedWork,
            previousRemovalFailed: previousRemovalFailed,
            onRemove: { [weak self] in self?.choose(.remove) },
            onLater: { [weak self] in self?.choose(.later) }
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = AppStoreRetireText.windowTitle
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.alphaValue = CheckPanelVisibility.panelAlpha
        window.delegate = self
        window.center()
        if !CheckPanelVisibility.isRunningTests {
            NSApp.activate()
        }
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    /// 사용자가 골랐다. 처음 하나만 따른다.
    func choose(_ choice: Choice) {
        guard self.choice == nil else { return }
        self.choice = choice
        switch choice {
        case .remove: onRemove()
        case .later: onLater()
        }
    }

    /// 창을 버튼 없이 닫았다 = **나중에**.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        choose(.later)
    }
}

#endif
