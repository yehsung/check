import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.53 앱스토어 판이 설치된 맥에서 brew·DMG 판이 물러난다
//
// 기본 `swift test` 는 Developer ID 판이라 물러남 코드가 전부 컴파일된다. 이 스위트가 재는 것:
//  ① 판정(A) — 가짜 번들을 스크래치 폴더에 **실제로** 만들어 읽힌다(영수증 · 휴지통 · 시동 볼륨 · 아이폰 래퍼 · 번들 ID · 탈출구 · 판).
//     실제 실행의 조립(`AppStoreRetirementState.live`)은 가짜 후보 문을 넣어 **그 함수를 그대로** 부른다.
//  ② 실행 인자 · 상태 · 감시자(C) — 사적인 NotificationCenter 로 켜짐 통지를 흘리고, 실제로 움직이는 KVO 길의 처리 함수를 부른다.
//  ③ 지우기 계획(D) — 계획(순수 값)과 가짜 효과로 잰 실행 순서 · 누른 순간 다시 판정(`AppStoreRetireRemoval.live`) · 창의 기본 동작.
//     실제 휴지통·SMAppService·Process·brew·NSApp 은 건드리지 않는다.
//  ④ 스토어 방어 게이트 — 물러난 스토어가 서버를 **0회** 부른다(스텁 요청 목록으로 잰다 · 대조군은 같은 호출이 실제로 나간다).
//     물러나는 중(실행 중 물러남의 마무리 대기)에는 근무가 새로 열리지 않는다.
//  ⑤ 소스 계약 — 실행 시점 판정이 세션 활성화보다 앞 · 물러남이면 배선을 건너뜀 · 메뉴바 아이콘이 물러남에 묶임 · 실행 중 감시 배선 ·
//     전부 `#if !CHECK_MAS` 안(주석은 걷어내고 본다).
// 창은 띄우지 않는다(알파 0 창이 남으면 사용자의 클릭을 먹는다) — 본문은 ImageRenderer 로 재고, 고르기 규칙은 컨트롤러를 직접 부른다.

@Suite("V0353 앱스토어 판 물러남")
@MainActor
struct V0353AppStoreRetireTests {

    // MARK: ① 판정표

    @Test func 판정표는_Developer_ID_판만_물러나게_한다() {
        #expect(MacEdition.developerID.retiresWhenAppStoreEditionInstalled)
        #expect(!MacEdition.appStore.retiresWhenAppStoreEditionInstalled, "앱스토어 판이 물러나면 두 판이 다 꺼진다")
        #expect(AppStoreEditionRetirement.appStoreBundleIdentifier == "com.yehsung.aingcheck")
        #expect(AppStoreEditionRetirement.conventionalInstallURL.path == "/Applications/AingCheck.app",
                "관례 자리가 패키징 스크립트의 APP_NAME(AingCheck)과 갈렸다")
    }

    // MARK: ① 판정 — 설치된 앱스토어 판인가

    @Test func 영수증_MacOS_번들ID가_다_있으면_설치된_앱스토어_판이다() throws {
        let root = CheckTestScratch.directory()
        let app = try v0353MakeBundle(in: root)
        #expect(AppStoreEditionRetirement.isInstalledAppStoreEdition(app))
        #expect(AppStoreEditionRetirement.installedAppStoreEdition(among: [app]) == app)
    }

    @Test func 영수증이_없거나_비었거나_폴더면_아니다() throws {
        let root = CheckTestScratch.directory()
        let none = try v0353MakeBundle(in: root, name: "None", receipt: .missing)
        let empty = try v0353MakeBundle(in: root, name: "Empty", receipt: .empty)
        let folder = try v0353MakeBundle(in: root, name: "Folder", receipt: .directory)
        for app in [none, empty, folder] {
            #expect(!AppStoreEditionRetirement.isInstalledAppStoreEdition(app),
                    "영수증 없는 사본(\(app.lastPathComponent))을 앱스토어 판으로 봤다 — 개발 맥의 스크래치 빌드가 brew 판을 끈다")
        }
        // 대조군: 같은 폴더에 영수증만 있는 사본은 맞다(위 거짓이 폴더 탓이 아니다).
        #expect(AppStoreEditionRetirement.isInstalledAppStoreEdition(try v0353MakeBundle(in: root, name: "Real")))
    }

    @Test func 휴지통의_사본은_아니다() throws {
        let root = CheckTestScratch.directory()
        let trash = root.appendingPathComponent(".Trash", isDirectory: true)
        let trashed = try v0353MakeBundle(in: trash)
        #expect(!AppStoreEditionRetirement.isInstalledAppStoreEdition(trashed), "휴지통의 앱스토어 판에 반응했다")
        let volumeTrash = root.appendingPathComponent(".Trashes/501", isDirectory: true)
        #expect(!AppStoreEditionRetirement.isInstalledAppStoreEdition(try v0353MakeBundle(in: volumeTrash)))
        // 휴지통 밖 심링크가 휴지통 안을 가리켜도 아니다(실제 자리로 본다).
        let link = root.appendingPathComponent("Linked.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: trashed)
        #expect(!AppStoreEditionRetirement.isInstalledAppStoreEdition(link))
        // 후보 목록에서 휴지통 사본을 건너뛰고 진짜를 고른다.
        let real = try v0353MakeBundle(in: root.appendingPathComponent("Applications", isDirectory: true))
        #expect(AppStoreEditionRetirement.installedAppStoreEdition(among: [trashed, link, real]) == real)
    }

    @Test func 아이폰_앱_래퍼는_아니다() throws {
        let root = CheckTestScratch.directory()
        // 래퍼 모양: Contents/MacOS 가 없고 Wrapper/ · WrappedBundle 이 있다(같은 번들 ID).
        let wrapper = try v0353MakeBundle(in: root, name: "Wrapped", macOS: false)
        try FileManager.default.createDirectory(at: wrapper.appendingPathComponent("Wrapper/AingCheck.app"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: wrapper.appendingPathComponent("WrappedBundle").path,
                                                   withDestinationPath: "Wrapper/AingCheck.app")
        #expect(!AppStoreEditionRetirement.isInstalledAppStoreEdition(wrapper))
        // MacOS 폴더가 있어도 래퍼 표지가 있으면 아니다(모호하면 '없음').
        let hybrid = try v0353MakeBundle(in: root, name: "Hybrid")
        try FileManager.default.createDirectory(at: hybrid.appendingPathComponent("Wrapper"), withIntermediateDirectories: true)
        #expect(!AppStoreEditionRetirement.isInstalledAppStoreEdition(hybrid))
        // MacOS 폴더만 없어도 아니다.
        #expect(!AppStoreEditionRetirement.isInstalledAppStoreEdition(try v0353MakeBundle(in: root, name: "NoMacOS", macOS: false)))
    }

    @Test func 번들ID가_정확히_같지_않으면_아니다() throws {
        let root = CheckTestScratch.directory()
        for (name, identifier) in [("Brew", "kingcheck"), ("Longer", "com.yehsung.aingcheck.helper"),
                                   ("Upper", "com.yehsung.AingCheck"), ("NoID", nil)] as [(String, String?)] {
            let app = try v0353MakeBundle(in: root, name: name, bundleIdentifier: identifier)
            #expect(!AppStoreEditionRetirement.isInstalledAppStoreEdition(app), "\(identifier ?? "nil") 을 앱스토어 판으로 봤다")
        }
        // Info.plist 가 깨졌으면 아니다(읽기 오류 = 없음).
        let broken = try v0353MakeBundle(in: root, name: "Broken")
        try Data("not a plist".utf8).write(to: broken.appendingPathComponent("Contents/Info.plist"))
        #expect(!AppStoreEditionRetirement.isInstalledAppStoreEdition(broken))
        // 없는 자리도 아니다.
        #expect(!AppStoreEditionRetirement.isInstalledAppStoreEdition(root.appendingPathComponent("Nowhere.app")))
    }

    @Test func 시동_볼륨_밖의_사본은_영수증이_있어도_아니다() throws {
        let root = CheckTestScratch.directory()
        let app = try v0353MakeBundle(in: root)
        // 볼륨 판정만 가른다: 같은 번들이 외장 디스크 · 복제 백업(영수증까지 복사돼 있다)에 있다고 치면 아니다.
        let probe = V0353WatchProbe()
        #expect(!AppStoreEditionRetirement.isInstalledAppStoreEdition(app, isOnStartupVolume: { probe.launched.append($0); return false }),
                "다른 볼륨의 앱스토어 판 사본에 반응했다 — 백업 디스크를 꽂아 두면 brew 판이 매번 물러난다")
        #expect(probe.launched == [app], "볼륨 판정에 후보 자리를 그대로 넘기지 않는다")
        #expect(AppStoreEditionRetirement.isInstalledAppStoreEdition(app, isOnStartupVolume: { _ in true }))
        // 실제 볼륨 판정: 스크래치(시동 볼륨) · /Applications 는 참, 못 읽는 자리는 거짓(못 찾음 쪽으로 기운다).
        #expect(AppStoreEditionRetirement.isOnStartupVolume(app), "시동 볼륨의 사본을 밖으로 봤다 — 실제 설치를 놓친다")
        #expect(AppStoreEditionRetirement.isOnStartupVolume(URL(fileURLWithPath: "/Applications", isDirectory: true)))
        #expect(!AppStoreEditionRetirement.isOnStartupVolume(root.appendingPathComponent("Nowhere.app")))
        // 기본 판정도 같은 볼륨 판정을 쓴다(기본 인자로 스크래치 번들이 맞다 = 볼륨 판정이 참을 돌려준다).
        #expect(AppStoreEditionRetirement.isInstalledAppStoreEdition(app))
        // 이 맥에 마운트된 다른 볼륨(디스크 이미지 · 외장)이 있으면 그 자리는 거짓이어야 한다.
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsRootFileSystemKey],
                                                            options: [.skipHiddenVolumes]) ?? []
        for volume in volumes where volume.path.hasPrefix("/Volumes/") && volume.resolvingSymlinksInPath().path != "/" {
            #expect(!AppStoreEditionRetirement.isOnStartupVolume(volume), "마운트된 볼륨 \(volume.path) 을 시동 볼륨으로 봤다")
        }
    }

    // MARK: ① 판정 — 실제 실행의 조립(`AppStoreRetirementState.live`)

    @Test func 실행_시점_live_는_인자의_힌트와_후보를_조립해_물러남_모드로_뜬다() throws {
        let root = CheckTestScratch.directory()
        let app = try v0353MakeBundle(in: root)
        let defaults = CheckTestScratch.defaults()
        let probe = V0353SourcesProbe()

        // ① 다시 띄운 인스턴스: 후보는 힌트 하나뿐이어도 물러남 모드로 뜨고, "근무를 마무리했다" 를 들고 온다.
        let relaunched = AppStoreRetirementState.live(
            edition: .developerID,
            arguments: ["/x/check"] + AppStoreEditionRetirement.relaunchArguments(finishedWork: true, appStoreEdition: app),
            defaults: defaults, sources: probe.sources()
        )
        #expect(relaunched.launchAppStoreEdition?.standardizedFileURL == app.standardizedFileURL, "다시 띄운 인스턴스가 힌트를 안 본다")
        #expect(relaunched.isRetiredAtLaunch)
        #expect(!relaunched.menuBarInserted, "물러남 모드인데 메뉴바 아이콘이 들어간다 — 팝오버를 열면 세션이 살아난다")
        #expect(relaunched.finishedWorkBeforeRelaunch, "창에 '하던 근무는 여기서 마무리했어요' 가 안 나온다")
        #expect(probe.registeredAsked == ["com.yehsung.aingcheck"] && probe.runningAsked == ["com.yehsung.aingcheck"],
                "후보를 앱스토어 판 번들 ID 로 묻지 않는다: \(probe.registeredAsked) \(probe.runningAsked)")
        // 근무 표식 없이 다시 띄웠으면 그 줄이 없다.
        let quiet = AppStoreRetirementState.live(
            edition: .developerID,
            arguments: ["/x/check"] + AppStoreEditionRetirement.relaunchArguments(finishedWork: false, appStoreEdition: app),
            defaults: defaults, sources: probe.sources()
        )
        #expect(quiet.isRetiredAtLaunch && !quiet.finishedWorkBeforeRelaunch)

        // ② 보통 실행(힌트 없음): LaunchServices · 실행 중 앱 · 관례 자리 — 어느 한 갈래에서만 찾아도 물러난다.
        for (label, sources) in [("registered", probe.sources(registered: [app])), ("running", probe.sources(running: [app])),
                                 ("fixed", probe.sources(fixed: [app]))] {
            let state = AppStoreRetirementState.live(edition: .developerID, arguments: ["/x/check"], defaults: defaults, sources: sources)
            #expect(state.launchAppStoreEdition == app, "\(label) 갈래의 사본을 후보에 넣지 않는다")
            #expect(!state.finishedWorkBeforeRelaunch)
        }
        // 대조군: 어디에도 없으면 평소대로 뜬다.
        let normal = AppStoreRetirementState.live(edition: .developerID, arguments: ["/x/check"], defaults: defaults,
                                                  sources: probe.sources())
        #expect(!normal.isRetiredAtLaunch && normal.menuBarInserted)

        // ③ 기본 판(`edition` 생략)은 이 바이너리의 판이다 — 기본 `swift test` 는 Developer ID 판이라 물러난다.
        #expect(MacEdition.current == .developerID)
        let byDefault = AppStoreRetirementState.live(arguments: ["/x/check"], defaults: defaults, sources: probe.sources(fixed: [app]))
        #expect(byDefault.isRetiredAtLaunch, "기본 판으로 물러나지 않는다")

        // ④ 탈출구가 서면 후보를 묻지도 않는다.
        defaults.set(true, forKey: AppStoreEditionRetirement.allowAlongsideKey)
        let asked = probe.registeredAsked.count
        let allowed = AppStoreRetirementState.live(edition: .developerID, arguments: ["/x/check"], defaults: defaults,
                                                   sources: probe.sources(registered: [app]))
        #expect(!allowed.isRetiredAtLaunch && probe.registeredAsked.count == asked)
    }

    @Test func 실제_후보_문과_델리게이트의_판정_자리는_그대로_있다() throws {
        // 가짜 후보로 재는 위 테스트가 닿지 않는 두 자리: 실제 문(.live)의 조립과 델리게이트가 판정을 만드는 줄.
        let helper = v0353Collapsed(try v0353Source("AppStoreEditionRetirement.swift"))
        let live = try #require(v0353Block(after: "static var live: CandidateSources", in: helper))
        #expect(live.contains("registered: { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }"),
                "LaunchServices 가 아는 사본을 후보에 안 넣는다")
        #expect(live.contains("NSWorkspace.shared.runningApplications .filter { $0.bundleIdentifier == identifier } .compactMap(\\.bundleURL)"))
        #expect(live.contains("fixed: [AppStoreEditionRetirement.conventionalInstallURL]"))
        let state = try #require(v0353Block(after: "static func live( edition: MacEdition = .current,", in: helper))
        #expect(state.contains("AppStoreEditionRetirement.candidates(hint: parsed.appStoreEditionHint, sources: sources)"))
        #expect(state.contains("finishedWorkBeforeRelaunch: parsed.finishedWork"))
        #expect(helper.contains("sources: AppStoreEditionRetirement.CandidateSources = .live ) -> AppStoreRetirementState"),
                "실제 실행의 기본 후보 문이 .live 가 아니다")
        let app = v0353Collapsed(try v0353Source("CheckApp.swift"))
        let delegate = try #require(v0353Block(after: "final class AppDelegate: NSObject, NSApplicationDelegate", in: app))
        #expect(delegate.contains("let retirement = AppStoreRetirementState.live()"), "델리게이트가 실제 실행의 판정을 만들지 않는다")
    }

    // MARK: ① 판정 — 실행 시점 · 실행 중

    @Test func 실행_시점_판정은_Developer_ID_판에서_설치된_사본을_찾는다() throws {
        let root = CheckTestScratch.directory()
        let app = try v0353MakeBundle(in: root)
        let scratch = try v0353MakeBundle(in: root, name: "Scratch", receipt: .missing)
        let defaults = CheckTestScratch.defaults()
        var asked = 0
        let found = AppStoreEditionRetirement.launchDecision(
            edition: .developerID, defaults: defaults, candidates: { asked += 1; return [scratch, app] }
        )
        #expect(found == app)
        #expect(asked == 1)
        // 후보에 스크래치 빌드만 있으면 물러나지 않는다.
        #expect(AppStoreEditionRetirement.launchDecision(edition: .developerID, defaults: defaults, candidates: { [scratch] }) == nil)
    }

    @Test func 탈출구_키가_서면_물러나지_않고_후보도_묻지_않는다() throws {
        let root = CheckTestScratch.directory()
        let app = try v0353MakeBundle(in: root)
        let defaults = CheckTestScratch.defaults()
        defaults.set(true, forKey: AppStoreEditionRetirement.allowAlongsideKey)
        #expect(AppStoreEditionRetirement.allowAlongsideKey == "check.allowAlongsideAppStoreEdition", "문서에 적은 키와 갈렸다")
        var asked = 0
        #expect(AppStoreEditionRetirement.launchDecision(edition: .developerID, defaults: defaults,
                                                         candidates: { asked += 1; return [app] }) == nil)
        #expect(asked == 0, "탈출구가 섰는데 LaunchServices 를 물었다")
        #expect(AppStoreEditionRetirement.midRunDecision(
            launchedBundleIdentifier: "com.yehsung.aingcheck", launchedBundleURL: app, edition: .developerID, defaults: defaults
        ) == nil)
        // 대조군: 키를 내리면 같은 입력이 물러남이다.
        defaults.set(false, forKey: AppStoreEditionRetirement.allowAlongsideKey)
        #expect(AppStoreEditionRetirement.launchDecision(edition: .developerID, defaults: defaults, candidates: { [app] }) == app)
    }

    @Test func 앱스토어_판은_언제나_물러나지_않는다() throws {
        let root = CheckTestScratch.directory()
        let app = try v0353MakeBundle(in: root)
        let defaults = CheckTestScratch.defaults()
        var asked = 0
        #expect(AppStoreEditionRetirement.launchDecision(edition: .appStore, defaults: defaults,
                                                         candidates: { asked += 1; return [app] }) == nil)
        #expect(asked == 0)
        #expect(AppStoreEditionRetirement.midRunDecision(
            launchedBundleIdentifier: "com.yehsung.aingcheck", launchedBundleURL: app, edition: .appStore, defaults: defaults
        ) == nil)
        let state = AppStoreRetirementState.live(edition: .appStore, arguments: ["check"], defaults: defaults)
        #expect(!state.isRetiredAtLaunch)
        #expect(state.menuBarInserted)
    }

    @Test func 실행_중_판정은_켜진_앱이_설치된_앱스토어_판일_때만() throws {
        let root = CheckTestScratch.directory()
        let app = try v0353MakeBundle(in: root)
        let scratch = try v0353MakeBundle(in: root, name: "Scratch", receipt: .missing)
        let defaults = CheckTestScratch.defaults()
        func decide(_ id: String?, _ url: URL?) -> URL? {
            AppStoreEditionRetirement.midRunDecision(launchedBundleIdentifier: id, launchedBundleURL: url,
                                                     edition: .developerID, defaults: defaults)
        }
        #expect(decide("com.yehsung.aingcheck", app) == app)
        #expect(decide("com.yehsung.aingcheck", scratch) == nil, "개발 맥의 스크래치 빌드를 켜자 brew 판이 물러났다")
        #expect(decide("com.apple.Safari", app) == nil)
        #expect(decide(nil, app) == nil)
        #expect(decide("com.yehsung.aingcheck", nil) == nil)
    }

    @Test func 실행_중_물러남의_근무_마무리는_종료_훅과_같은_조건이다() {
        let now = Date()
        #expect(AppStoreEditionRetirement.shouldFinishWorkBeforeRetiring(isSignedIn: true, startedAt: now, adoptedRemoteSession: false))
        #expect(!AppStoreEditionRetirement.shouldFinishWorkBeforeRetiring(isSignedIn: false, startedAt: now, adoptedRemoteSession: false))
        #expect(!AppStoreEditionRetirement.shouldFinishWorkBeforeRetiring(isSignedIn: true, startedAt: nil, adoptedRemoteSession: false))
        #expect(!AppStoreEditionRetirement.shouldFinishWorkBeforeRetiring(isSignedIn: true, startedAt: now, adoptedRemoteSession: true),
                "흡수 세션(다른 기기가 연 근무)을 이 맥이 끝냈다")
    }

    // MARK: ② 실행 인자 · 상태

    @Test func 다시_띄우기_인자는_근무_마무리와_경로를_그대로_나른다() {
        let path = URL(fileURLWithPath: "/Applications/Aing Check's \"copy\"; $HOME.app", isDirectory: true)
        let finished = AppStoreEditionRetirement.relaunchArguments(finishedWork: true, appStoreEdition: path)
        #expect(finished == ["--check-retire-finished-work", "--check-retire-app-store-edition", path.path])
        let parsed = AppStoreEditionRetirement.parseLaunchArguments(["/x/check", "-NSDocumentRevisionsDebugMode", "YES"] + finished)
        #expect(parsed.finishedWork)
        #expect(parsed.appStoreEditionHint?.path == path.path)
        let plain = AppStoreEditionRetirement.parseLaunchArguments(
            ["/x/check"] + AppStoreEditionRetirement.relaunchArguments(finishedWork: false, appStoreEdition: path))
        #expect(!plain.finishedWork)
        #expect(plain.appStoreEditionHint?.path == path.path)
        // 맨 끝에 경로 없이 오거나 상대 경로면 힌트가 없다.
        #expect(AppStoreEditionRetirement.parseLaunchArguments(["check", "--check-retire-app-store-edition"]).appStoreEditionHint == nil)
        #expect(AppStoreEditionRetirement.parseLaunchArguments(["check", "--check-retire-app-store-edition", "x.app"]).appStoreEditionHint == nil)
        #expect(AppStoreEditionRetirement.parseLaunchArguments(["check"]) == .init())
    }

    @Test func 다시_띄운_인스턴스는_힌트를_다시_판정해_물러남_모드로_뜬다() throws {
        let root = CheckTestScratch.directory()
        let app = try v0353MakeBundle(in: root)
        let defaults = CheckTestScratch.defaults()
        // 실제 실행이 넘기는 인자 그대로. 후보는 힌트가 맨 앞이다(LaunchServices 가 아직 모르는 사본도 찾는다).
        let arguments = ["check"] + AppStoreEditionRetirement.relaunchArguments(finishedWork: true, appStoreEdition: app)
        let parsed = AppStoreEditionRetirement.parseLaunchArguments(arguments)
        let found = AppStoreEditionRetirement.launchDecision(edition: .developerID, defaults: defaults,
                                                             candidates: { [parsed.appStoreEditionHint].compactMap { $0 } })
        #expect(found?.standardizedFileURL == app.standardizedFileURL)
        let state = AppStoreRetirementState(launchAppStoreEdition: found, finishedWorkBeforeRelaunch: parsed.finishedWork)
        #expect(state.isRetiredAtLaunch)
        #expect(!state.menuBarInserted, "물러남 모드인데 메뉴바 아이콘이 들어간다 — 팝오버를 열면 세션이 살아난다")
        #expect(state.finishedWorkBeforeRelaunch)
        // 힌트가 영수증 없는 사본을 가리키면 다시 판정에서 떨어진다(힌트는 판정이 아니다).
        let scratch = try v0353MakeBundle(in: root, name: "Scratch", receipt: .missing)
        #expect(AppStoreEditionRetirement.launchDecision(edition: .developerID, defaults: defaults, candidates: { [scratch] }) == nil)
    }

    @Test func 물러나지_않은_실행은_아이콘을_넣고_실행_중_물러남은_한_번만_아이콘을_내린다() {
        let normal = AppStoreRetirementState(launchAppStoreEdition: nil, finishedWorkBeforeRelaunch: true)
        #expect(normal.menuBarInserted)
        #expect(!normal.isRetiredAtLaunch)
        #expect(!normal.finishedWorkBeforeRelaunch, "물러나지 않은 실행이 '근무를 마무리했다'를 들고 있다")
        #expect(normal.beginMidRunRetirement())
        #expect(!normal.menuBarInserted)
        #expect(normal.isRetiringMidRun)
        #expect(!normal.beginMidRunRetirement(), "실행 중 물러남이 두 번 시작됐다 — 근무 마무리·재실행이 겹친다")

        let retired = AppStoreRetirementState(launchAppStoreEdition: URL(fileURLWithPath: "/Applications/AingCheck.app"))
        #expect(!retired.beginMidRunRetirement(), "처음부터 물러난 실행이 실행 중 물러남을 또 시작했다")
    }

    // MARK: ② 실행 중 감시자

    @Test func 감시자는_켜짐_통지를_판정에_넘기고_참일_때만_부른다() async {
        let center = NotificationCenter()
        let target = URL(fileURLWithPath: "/Applications/AingCheck.app", isDirectory: true)
        let probe = V0353WatchProbe()
        let watcher = AppStoreEditionLaunchWatcher(
            center: center,
            decide: { id, _ in probe.asked.append(id); return probe.answer },
            onAppStoreEditionLaunched: { probe.launched.append($0) }
        )
        let note = Notification(name: NSWorkspace.didLaunchApplicationNotification, object: nil,
                                userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        center.post(note)
        await v0353Settle { probe.asked.count == 1 }
        #expect(probe.asked == [NSRunningApplication.current.bundleIdentifier])
        #expect(probe.launched.isEmpty, "판정이 거짓인데 물러났다")

        probe.answer = target
        center.post(note)
        await v0353Settle { probe.launched.count == 1 }
        #expect(probe.launched == [target])

        // 다른 통지에는 반응하지 않고, 멈춘 감시자는 아무것도 받지 않는다.
        center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil,
                    userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        watcher.stop()
        center.post(note)
        await v0353Settle { false }
        #expect(probe.asked.count == 2, "멈춘 감시자가 통지를 받았다 / 다른 통지를 받았다")
        #expect(probe.launched.count == 1)
    }

    /// 앱스토어 판은 LSUIElement 라 켜짐 통지가 오지 않는다(2026-10-15 실측) — 실제로 움직이는 길은 실행 중 앱 목록 KVO 다.
    /// 그 길의 처리(번들 ID 거르기 → 판정 → 첫 참 하나)를 그대로 부른다.
    @Test func 실행_중_앱_목록의_새_앱은_앱스토어_판만_골라_판정에_넘긴다() throws {
        typealias Launch = AppStoreEditionLaunchWatcher.Launch
        let first = URL(fileURLWithPath: "/Applications/AingCheck.app", isDirectory: true)
        let second = URL(fileURLWithPath: "/Users/x/Applications/AingCheck.app", isDirectory: true)
        let launched = [
            Launch(bundleIdentifier: "com.apple.Safari", bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")),
            Launch(bundleIdentifier: "com.yehsung.aingcheck", bundleURL: first),
            Launch(bundleIdentifier: nil, bundleURL: nil),
            Launch(bundleIdentifier: "kingcheck", bundleURL: URL(fileURLWithPath: "/Applications/aing-check.app")),
            Launch(bundleIdentifier: "com.yehsung.aingcheck", bundleURL: second),
        ]
        #expect(AppStoreEditionLaunchWatcher.appStoreEditionLaunches(launched) == [launched[1], launched[4]])
        #expect(AppStoreEditionLaunchWatcher.appStoreEditionLaunches([launched[0], launched[3]]).isEmpty)

        let probe = V0353WatchProbe()
        let watcher = AppStoreEditionLaunchWatcher(
            center: NotificationCenter(),
            decide: { id, url in probe.asked.append(id); return url == second ? second : nil },
            onAppStoreEditionLaunched: { probe.launched.append($0) }
        )
        defer { watcher.stop() }
        watcher.report(AppStoreEditionLaunchWatcher.appStoreEditionLaunches(launched))
        #expect(probe.asked == ["com.yehsung.aingcheck", "com.yehsung.aingcheck"])
        #expect(probe.launched == [second], "판정이 참인 켜짐을 놓쳤다")
        watcher.report([launched[1]])
        #expect(probe.launched == [second], "판정이 거짓인데 물러났다")

        // 실제 배선: KVO 가 삽입된 새 앱(.new)을 같은 거르기 → 같은 처리로 넘긴다.
        let helper = v0353Collapsed(try v0353Source("AppStoreEditionRetirement.swift"))
        let watch = try #require(v0353Block(after: "final class AppStoreEditionLaunchWatcher", in: helper))
        #expect(watch.contains("workspace?.observe(\\.runningApplications, options: [.new])"), "KVO 가 새로 들어온 앱을 받지 않는다")
        #expect(watch.contains("Self.appStoreEditionLaunches( (change.newValue ?? []).map { Launch(bundleIdentifier: $0.bundleIdentifier, bundleURL: $0.bundleURL) } )"))
        #expect(watch.contains("Task { @MainActor in self?.report(launched) }"))
    }

    // MARK: ③ 지우기 계획

    @Test func brew_가_관리하면_떼어_낸_셸로_uninstall_하고_값은_argv_로만_간다() {
        let hostile = "/Applications/Yesung's \"Apps\"; rm -rf ~ $(id) `whoami`/AingCheck.app"
        let appStore = URL(fileURLWithPath: hostile, isDirectory: true)
        let own = URL(fileURLWithPath: "/Applications/aing-check.app", isDirectory: true)
        let log = "/Users/x/Library/Logs/it's \"log\".log"
        let state = "/Users/x/Library/Caches/king check/re`tire`.state"
        let plan = AppStoreRetireRemoval.plan(
            installSource: .brew, brewPath: "/opt/homebrew/bin/brew", ownBundle: own, ownBundleIsApp: true,
            appStoreEdition: appStore, processID: 4242, logPath: log, statePath: state
        )
        let arguments = [
            "-c", AppStoreRetireRemoval.spawnWrapper, "aing-check-retire", AppStoreRetireRemoval.brewUninstallScript,
            "/opt/homebrew/bin/brew", "aing-check", appStore.path, "4242", state, log,
        ]
        #expect(plan.steps == [.unregisterLoginItem, .spawnBrewUninstall(arguments: arguments), .terminate])
        // 셸 본문(래퍼 · 스크립트)은 상수다 — 어떤 값도 끼워 넣지 않는다.
        for text in [AppStoreRetireRemoval.spawnWrapper, AppStoreRetireRemoval.brewUninstallScript,
                     AppStoreRetireRemoval.openSpawnWrapper, AppStoreRetireRemoval.openAfterExitScript] {
            for value in [appStore.path, "/opt/homebrew", "4242", log, state, "aing-check.app", "AingCheck", "Library"] {
                #expect(!text.contains(value), "셸 본문에 값 [\(value)] 이 보간됐다")
            }
        }
        // 래퍼가 전개하는 위치 인자 수와 넘기는 인자 수가 맞는다($0 꼬리표 + $1…$7).
        #expect(arguments.count - 3 == 7)
        for index in 1...7 { #expect(AppStoreRetireRemoval.spawnWrapper.contains("\"$\(index)\"")) }
        #expect(!AppStoreRetireRemoval.spawnWrapper.contains("$8"))
        // 스크립트의 위치 인자 뜻: brew · cask · 앱스토어 판 · PID · 상태 파일.
        let script = AppStoreRetireRemoval.brewUninstallScript
        #expect(script.contains(#"BREW="$1"; CASK="$2"; APP_STORE="$3"; APP_PID="$4"; STATE="$5""#))
        #expect(script.contains(#"if "$BREW" uninstall --cask "$CASK"; then"#))
        #expect(script.contains(#"printf 'brew-failed\n' > "$STATE""#), "brew 실패가 다음 창에 닿지 않는다 — 로그에만 남는다")
        #expect(AppStoreRetireRemoval.brewFailedState == "brew-failed")
        #expect(script.contains(#"open "$APP_STORE""#))
        #expect(script.contains(#"kill -0 "$APP_PID""#), "이 앱이 끝나기를 기다리지 않는다 — cask 의 quit 가 Apple Event 권한 창을 띄울 수 있다")
        // 셸은 무엇도 직접 지우지 않는다(지우는 것은 brew 가 자기 기록대로).
        for banned in ["rm ", "rm\t", "mv ", "trash", "set -e", "brew upgrade"] {
            for text in [script, AppStoreRetireRemoval.spawnWrapper, AppStoreRetireRemoval.openAfterExitScript,
                         AppStoreRetireRemoval.openSpawnWrapper] {
                #expect(!text.contains(banned), "셸에 [\(banned)] 가 있다")
            }
        }
        // 주석 시작처럼 보이는 글자가 셸에 있으면 소스를 읽는 계약 테스트(앱스토어 판 금지 문자열 게이트 등)의 주석 걷어내기가
        // 파일 뒷부분을 통째로 지운다 — 그 게이트가 `uninstall --cask` 를 못 찾아 헛돈다.
        for text in [script, AppStoreRetireRemoval.spawnWrapper, AppStoreRetireRemoval.openAfterExitScript, AppStoreRetireRemoval.openSpawnWrapper] {
            // 표지는 글자를 이어 붙여 만든다 — 이 파일을 읽는 걷어내기도 같은 함정에 빠지지 않게.
            for marker in ["/" + "*", "*" + "/", "/" + "/"] { #expect(!text.contains(marker), "셸에 [\(marker)] 가 있다") }
        }
        #expect(UpdateRunner.caskName == "aing-check")
        #expect(AppStoreRetireRemoval.statePath.hasSuffix("/Library/Caches/kingcheck/retire.state"),
                "상태 파일이 cask 의 zap 폴더 밖이다 — 지워지지 않는 잔재가 된다")
    }

    @Test func 직접_설치한_사본은_자기_번들만_휴지통으로_보내고_끝난_뒤에_앱스토어_판을_연다() {
        let appStore = URL(fileURLWithPath: "/Applications/AingCheck.app", isDirectory: true)
        let own = URL(fileURLWithPath: "/Users/x/Applications/aing-check.app", isDirectory: true)
        let opener = AppStoreRetireRemoval.Step.spawnOpenAfterExit(arguments: v0353OpenArguments(appStore: appStore, pid: 1))
        let standalone = AppStoreRetireRemoval.plan(installSource: .standalone, brewPath: nil, ownBundle: own,
                                                    ownBundleIsApp: true, appStoreEdition: appStore, processID: 1)
        #expect(standalone.steps == [.unregisterLoginItem, .moveToTrashOrReveal(own), opener, .terminate])
        // 여는 셸: 이 앱(PID)이 끝나기를 기다렸다가 연다 — 살아 있는 채로 열면 앱스토어 판이 이 앱을 보고 한 번뿐인 경고를 쓴다.
        let open = AppStoreRetireRemoval.openAfterExitScript
        #expect(open.contains(#"APP_STORE="$1"; APP_PID="$2""#))
        #expect(open.contains(#"kill -0 "$APP_PID""#), "앱스토어 판을 이 앱이 끝나기 전에 연다")
        #expect(open.contains(#"open "$APP_STORE""#))
        for index in 1...4 { #expect(AppStoreRetireRemoval.openSpawnWrapper.contains("\"$\(index)\"")) }
        #expect(!AppStoreRetireRemoval.openSpawnWrapper.contains("$5"))
        // brew 출처인데 brew 경로가 없으면(판정이 갈렸다) 직접 설치처럼 간다.
        let brewWithoutPath = AppStoreRetireRemoval.plan(installSource: .brew, brewPath: nil, ownBundle: own,
                                                         ownBundleIsApp: true, appStoreEdition: appStore, processID: 1)
        #expect(brewWithoutPath.steps == standalone.steps)
        // 우리 .app 이 아니면(`swift run` — 빌드 폴더) 아무것도 지우지도 보여 주지도 않는다.
        let devFolder = URL(fileURLWithPath: "/Users/x/check/.build/debug", isDirectory: true)
        for source in [InstallSource.standalone, .brew] {
            let dev = AppStoreRetireRemoval.plan(installSource: source, brewPath: "/opt/homebrew/bin/brew", ownBundle: devFolder,
                                                 ownBundleIsApp: false, translocatedOriginal: own,
                                                 previousBrewUninstallFailed: true, appStoreEdition: appStore, processID: 1)
            #expect(dev.steps == [.unregisterLoginItem, opener, .terminate])
        }
    }

    @Test func 번역_경로에서는_원래_자리를_보여_주기만_하고_지난번_brew_실패면_자기_번들을_먼저_보여_준다() {
        let appStore = URL(fileURLWithPath: "/Applications/AingCheck.app", isDirectory: true)
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/T/AppTranslocation/ABCD/d/aing-check.app", isDirectory: true)
        let original = URL(fileURLWithPath: "/Users/x/Downloads/aing-check.app", isDirectory: true)
        let opener = AppStoreRetireRemoval.Step.spawnOpenAfterExit(arguments: v0353OpenArguments(appStore: appStore, pid: 9))
        let plan = AppStoreRetireRemoval.plan(installSource: .standalone, brewPath: nil, ownBundle: translocated, ownBundleIsApp: true,
                                              translocatedOriginal: original, appStoreEdition: appStore, processID: 9)
        #expect(plan.steps == [.unregisterLoginItem, .revealInFinder(original), opener, .terminate],
                "번역 경로의 임시 사본을 휴지통으로 보내려 했다(실패하고 임시 자리를 보여 준다 — 원래 사본은 남는다)")
        // 번역 판정: 번역 경로가 아니면 묻지도 않고 nil. 묻는 함수는 이 맥에 있다(이름으로 찾는다).
        #expect(AppStoreEditionRetirement.translocationOriginal(of: URL(fileURLWithPath: "/Applications/aing-check.app")) == nil)
        #expect(AppStoreEditionRetirement.translocationOriginalFunction != nil, "SecTranslocateCreateOriginalPathForURL 을 못 찾는다")

        let own = URL(fileURLWithPath: "/Applications/aing-check.app", isDirectory: true)
        let retry = AppStoreRetireRemoval.plan(installSource: .brew, brewPath: "/opt/homebrew/bin/brew", ownBundle: own,
                                               ownBundleIsApp: true, previousBrewUninstallFailed: true,
                                               appStoreEdition: appStore, processID: 9)
        #expect(retry.steps.first == .unregisterLoginItem)
        #expect(retry.steps.dropFirst().first == .revealInFinder(own), "지난번 brew 가 못 지웠는데 남은 자리를 보여 주지 않는다")
        #expect(retry.steps.contains { if case .spawnBrewUninstall = $0 { return true } else { return false } })
        // 상태 파일 읽기: 실패 표식만 참이다(없음 · ok · 엉뚱한 글자는 거짓).
        let probe = V0353WatchProbe()
        #expect(AppStoreRetireRemoval.previousBrewUninstallFailed(readState: { probe.asked.append($0); return "brew-failed\n" }))
        #expect(probe.asked == [AppStoreRetireRemoval.statePath])
        for content in [nil, "ok\n", "", "brew-failed-ish"] as [String?] {
            #expect(!AppStoreRetireRemoval.previousBrewUninstallFailed(readState: { _ in content }), "\(content ?? "nil")")
        }
    }

    @Test func 어느_계획이든_로그인_항목_해제가_먼저고_자기_번들_말고는_지우지_않는다() {
        let appStore = URL(fileURLWithPath: "/Applications/AingCheck.app", isDirectory: true)
        let own = URL(fileURLWithPath: "/Applications/aing-check.app", isDirectory: true)
        let original = URL(fileURLWithPath: "/Users/x/Downloads/aing-check.app", isDirectory: true)
        for source in [InstallSource.brew, .standalone] {
            for brew in ["/usr/local/bin/brew", nil] as [String?] {
                for isApp in [true, false] {
                    for translocated in [nil, original] as [URL?] {
                        for failedBefore in [false, true] {
                            let plan = AppStoreRetireRemoval.plan(installSource: source, brewPath: brew, ownBundle: own,
                                                                  ownBundleIsApp: isApp, translocatedOriginal: translocated,
                                                                  previousBrewUninstallFailed: failedBefore,
                                                                  appStoreEdition: appStore, processID: 7)
                            let label = "\(source) \(brew ?? "-") \(isApp) \(translocated?.path ?? "-") \(failedBefore)"
                            #expect(plan.steps.first == .unregisterLoginItem, "\(label): 로그인 항목 해제가 먼저가 아니다")
                            #expect(plan.steps.last == .terminate)
                            let deleted = plan.steps.compactMap { step -> URL? in
                                if case let .moveToTrashOrReveal(url) = step { return url }
                                return nil
                            }
                            #expect(deleted.allSatisfy { $0 == own }, "\(label): 자기 번들이 아닌 것을 지운다: \(deleted)")
                            #expect(deleted.count <= 1)
                            // 앱스토어 판을 여는 길은 정확히 하나(brew 셸 또는 끝난 뒤 열기 셸).
                            let openers = plan.steps.filter {
                                switch $0 {
                                case .spawnBrewUninstall, .spawnOpenAfterExit: return true
                                default: return false
                                }
                            }
                            #expect(openers.count == 1, "\(label): 앱스토어 판을 여는 길이 \(openers.count)개")
                        }
                    }
                }
            }
        }
    }

    @Test func 금지_문자열이_brew_셸의_명령을_잰다() throws {
        // 앱스토어 판 바이너리에 이 문자열이 있으면 패키징이 멈춘다 — 기준선이 같으면 헛돈다: 그 문자열이 **실제로 셸 본문에** 있어야 한다.
        let script = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent("scripts/package-mas.sh"),
                                encoding: .utf8)
        #expect(script.contains("\n  \"uninstall --cask\""), "package-mas.sh 의 FORBIDDEN_STRINGS 에 uninstall --cask 가 없다")
        #expect("uninstall --cask".utf8.count >= 16, "15바이트 이하는 코드에 인라인돼 바이트 검색으로 못 찾는다")
        #expect(AppStoreRetireRemoval.brewUninstallScript.contains("uninstall --cask"))
    }

    // MARK: ③ 지우기 실행(가짜 효과)

    @Test func 실행은_계획_순서대로_가고_휴지통_실패는_Finder_로_바뀐다() async {
        let appStore = URL(fileURLWithPath: "/Applications/AingCheck.app", isDirectory: true)
        let own = URL(fileURLWithPath: "/Applications/aing-check.app", isDirectory: true)
        let standalone = AppStoreRetireRemoval.plan(installSource: .standalone, brewPath: nil, ownBundle: own,
                                                    ownBundleIsApp: true, appStoreEdition: appStore, processID: 1)
        let ok = V0353EffectLog(trashSucceeds: true)
        await standalone.run(effects: ok.effects)
        #expect(ok.entries == ["unregister", "trash \(own.path)", "spawn 7", "terminate"], "이 앱이 살아 있는 채로 앱스토어 판을 열었다")
        #expect(ok.spawned == [v0353OpenArguments(appStore: appStore, pid: 1)])

        let denied = V0353EffectLog(trashSucceeds: false)
        await standalone.run(effects: denied.effects)
        #expect(denied.entries == ["unregister", "trash \(own.path)", "reveal \(own.path)", "spawn 7", "terminate"],
                "읽기 전용 볼륨에서 휴지통이 실패했는데 Finder 로 보여 주지 않는다")

        // 여는 셸을 못 띄우면 살아 있는 채로라도 직접 연다(안 열리는 것보다 낫다).
        let noShell = V0353EffectLog(trashSucceeds: true, spawnSucceeds: false)
        await standalone.run(effects: noShell.effects)
        #expect(noShell.entries == ["unregister", "trash \(own.path)", "spawn 7", "open \(appStore.path)", "terminate"])

        // 번역 경로: 원래 자리를 보여 주기만 한다(휴지통을 부르지 않는다).
        let original = URL(fileURLWithPath: "/Users/x/Downloads/aing-check.app", isDirectory: true)
        let translocated = AppStoreRetireRemoval.plan(installSource: .standalone, brewPath: nil, ownBundle: own, ownBundleIsApp: true,
                                                      translocatedOriginal: original, appStoreEdition: appStore, processID: 1)
        let reveal = V0353EffectLog(trashSucceeds: true)
        await translocated.run(effects: reveal.effects)
        #expect(reveal.entries == ["unregister", "reveal \(original.path)", "spawn 7", "terminate"])
    }

    @Test func brew_셸을_못_띄우면_지우지_않고_보여_주고_앱스토어_판을_연다() async {
        let appStore = URL(fileURLWithPath: "/Applications/AingCheck.app", isDirectory: true)
        let own = URL(fileURLWithPath: "/Applications/aing-check.app", isDirectory: true)
        let plan = AppStoreRetireRemoval.plan(installSource: .brew, brewPath: "/opt/homebrew/bin/brew", ownBundle: own,
                                              ownBundleIsApp: true, appStoreEdition: appStore, processID: 1)
        let spawned = V0353EffectLog(trashSucceeds: true, spawnSucceeds: true)
        await plan.run(effects: spawned.effects)
        #expect(spawned.entries == ["unregister", "spawn 10", "terminate"], "brew 경로가 앱에서 따로 지우거나 연다")
        #expect(spawned.spawned.first.map { Array($0.prefix(2)) } == ["-c", AppStoreRetireRemoval.spawnWrapper])

        let failed = V0353EffectLog(trashSucceeds: true, spawnSucceeds: false)
        await plan.run(effects: failed.effects)
        #expect(failed.entries == ["unregister", "spawn 10", "reveal \(own.path)", "open \(appStore.path)", "terminate"])
        #expect(!failed.entries.contains { $0.hasPrefix("trash") }, "brew 가 관리하는 사본을 앱이 직접 휴지통으로 보냈다")
    }

    // MARK: ③ 누른 순간의 계획(`AppStoreRetireRemoval.live`)

    @Test func 지우기는_누른_순간_앱스토어_판을_다시_판정하고_없으면_아무것도_안_지운다() throws {
        let root = CheckTestScratch.directory()
        let installed = try v0353MakeBundle(in: root.appendingPathComponent("Applications", isDirectory: true))
        let own = try v0353MakeBundle(in: root, name: "aing-check", bundleIdentifier: "kingcheck", receipt: .missing)
        let probe = V0353SourcesProbe()
        func live(_ sources: AppStoreEditionRetirement.CandidateSources) -> AppStoreRetireRemoval? {
            AppStoreRetireRemoval.live(appStoreEdition: installed, sources: sources, ownBundle: own,
                                       runner: v0353StandaloneRunner(own), processID: 42,
                                       readState: { _ in nil }, translocationOriginal: { _ in nil })
        }
        // 그대로 있으면 그 자리를 연다(창이 처음 찾은 자리가 맨 앞 후보다).
        let plan = try #require(live(probe.sources()))
        #expect(plan.appStoreEdition == installed)
        #expect(plan.steps == [.unregisterLoginItem, .moveToTrashOrReveal(own),
                               .spawnOpenAfterExit(arguments: v0353OpenArguments(appStore: installed, pid: 42)), .terminate])
        // 창이 떠 있는 동안 지웠다 → 아무것도 지우지 않는다(두 판이 다 없는 맥이 되지 않게).
        try FileManager.default.removeItem(at: installed)
        #expect(live(probe.sources()) == nil, "앱스토어 판이 없어졌는데 이 판을 지운다")
        // 다른 사본(LaunchServices 가 아는)이 있으면 그것을 연다.
        let other = try v0353MakeBundle(in: root.appendingPathComponent("Other", isDirectory: true))
        #expect(live(probe.sources(registered: [other]))?.appStoreEdition == other)
        // 영수증 없는 사본뿐이면 없음이다(다시 판정은 같은 조건이다).
        let scratch = try v0353MakeBundle(in: root, name: "Scratch", receipt: .missing)
        #expect(live(probe.sources(registered: [scratch])) == nil)
    }

    @Test func live_계획은_우리_app_이_아니면_brew_가_관리해도_아무것도_지우지_않는다() throws {
        let root = CheckTestScratch.directory()
        let appStore = try v0353MakeBundle(in: root.appendingPathComponent("Applications", isDirectory: true))
        let none = V0353SourcesProbe().sources()
        // `swift run` 같은 개발 실행: 번들 자리가 빌드 폴더(.app 아님). 그 폴더를 brew 가 관리한다고 쳐도 지우면 안 된다.
        let folder = root.appendingPathComponent("debug", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try v0353WritePlist(["CFBundleIdentifier": "kingcheck"], to: folder.appendingPathComponent("Contents/Info.plist"))
        let folderRunner = v0353BrewRunner(folder)
        #expect(folderRunner.installSource == .brew && folderRunner.brewPath == "/opt/homebrew/bin/brew", "대조: 출처는 brew 여야 한다")
        let dev = try #require(AppStoreRetireRemoval.live(appStoreEdition: appStore, sources: none, ownBundle: folder, runner: folderRunner,
                                                          processID: 5, readState: { _ in "brew-failed" },
                                                          translocationOriginal: { _ in folder }))
        #expect(dev.steps == [.unregisterLoginItem, .spawnOpenAfterExit(arguments: v0353OpenArguments(appStore: appStore, pid: 5)), .terminate],
                "개발 실행에서 빌드 폴더를 지우거나 brew 로 지우려 한다: \(dev.steps)")
        // 대조군: 같은 출처의 진짜 우리 .app 이면 brew 셸로 지운다(지난번 실패 표식이면 자리를 먼저 보여 준다).
        let own = try v0353MakeBundle(in: root, name: "aing-check", bundleIdentifier: "kingcheck", receipt: .missing)
        let brew = try #require(AppStoreRetireRemoval.live(appStoreEdition: appStore, sources: none, ownBundle: own,
                                                           runner: v0353BrewRunner(own), processID: 5,
                                                           readState: { _ in "brew-failed\n" }, translocationOriginal: { _ in nil }))
        #expect(brew.steps.count == 4)
        #expect(brew.steps[1] == .revealInFinder(own))
        guard case let .spawnBrewUninstall(arguments) = brew.steps[2] else { Issue.record("brew 셸이 없다: \(brew.steps)"); return }
        #expect(Array(arguments.suffix(6)) == ["/opt/homebrew/bin/brew", "aing-check", appStore.path, "5",
                                               AppStoreRetireRemoval.statePath, AppStoreRetireRemoval.logPath])
        // 번역 경로면 원래 자리를 보여 주기만 한다(live 가 번역 판정을 계획에 넘긴다).
        let original = root.appendingPathComponent("Downloads/aing-check.app", isDirectory: true)
        let translocated = try #require(AppStoreRetireRemoval.live(appStoreEdition: appStore, sources: none, ownBundle: own,
                                                                   runner: v0353StandaloneRunner(own), processID: 5,
                                                                   readState: { _ in nil }, translocationOriginal: { _ in original }))
        #expect(translocated.steps[1] == .revealInFinder(original))
        #expect(!translocated.steps.contains(.moveToTrashOrReveal(own)))
    }

    // MARK: ③ 자기 번들 판정

    @Test func 자기_번들은_kingcheck_app_일_때만_지울_수_있다() throws {
        let root = CheckTestScratch.directory()
        let own = try v0353MakeBundle(in: root, name: "aing-check", bundleIdentifier: "kingcheck", receipt: .missing)
        #expect(AppStoreEditionRetirement.isOwnDeveloperIDBundle(own))
        let other = try v0353MakeBundle(in: root, name: "Other", bundleIdentifier: "com.example.other", receipt: .missing)
        #expect(!AppStoreEditionRetirement.isOwnDeveloperIDBundle(other))
        let folder = root.appendingPathComponent("debug", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try v0353WritePlist(["CFBundleIdentifier": "kingcheck"], to: folder.appendingPathComponent("Contents/Info.plist"))
        #expect(!AppStoreEditionRetirement.isOwnDeveloperIDBundle(folder), ".app 이 아닌 폴더를 자기 번들로 봤다")
        // 테스트 프로세스의 번들은 우리 앱이 아니다.
        #expect(!AppStoreEditionRetirement.isOwnDeveloperIDBundle(Bundle.main.bundleURL))
    }

    // MARK: ③ 창

    @Test func 창_문구는_결정한_글자_그대로다() {
        #expect(AppStoreRetireText.title == "이 맥에 앱스토어 판 아잉체크가 있어요")
        #expect(AppStoreRetireText.remove == "이 판 지우고 앱스토어 판 열기")
        #expect(AppStoreRetireText.later == "나중에")
        #expect(AppStoreRetireText.paragraphs(finishedWork: false) == [AppStoreRetireText.body])
        #expect(AppStoreRetireText.paragraphs(finishedWork: true) == [AppStoreRetireText.body, AppStoreRetireText.finishedWork])
        #expect(AppStoreRetireText.paragraphs(finishedWork: false, previousRemovalFailed: true)
                == [AppStoreRetireText.body, AppStoreRetireText.previousRemovalFailed])
        #expect(AppStoreRetireText.paragraphs(finishedWork: true, previousRemovalFailed: true)
                == [AppStoreRetireText.body, AppStoreRetireText.finishedWork, AppStoreRetireText.previousRemovalFailed])
        // 남는 것과 안 넘어가는 것을 함께 말한다 — "그대로예요" 만 말하면 단축키·자동 시작이 꺼진 앱스토어 판에서 약속이 깨진다.
        let body = AppStoreRetireText.body
        #expect(body.contains("기록·루비·팀·할 일은 계정에 있어"))
        #expect(body.contains("이 맥의 설정은 앱스토어 판에서 새로 맞춰 주세요"))
        #expect(body.contains("홈페이지나 brew 로 받은 이 판"), "터미널에서 brew 로 깐 사람에게 '홈페이지에서 받은' 은 사실이 아니다")
        for text in [AppStoreRetireText.title, AppStoreRetireText.body, AppStoreRetireText.finishedWork,
                     AppStoreRetireText.previousRemovalFailed] {
            for jargon in ["번들", "영수증", "kingcheck", "판정", "LaunchServices", "Developer ID", "cask", "상태 파일"] {
                #expect(!text.contains(jargon), "사용자 문구에 내부 용어 [\(jargon)]")
            }
        }
    }

    @Test func 창_본문은_작은_창에_들고_덧붙는_줄은_실제로_그려진다() throws {
        func height(_ finished: Bool, _ failed: Bool) throws -> CGFloat {
            try #require(v0353Height(CheckAppStoreRetireView(finishedWork: finished, previousRemovalFailed: failed, onRemove: {}, onLater: {}),
                                     width: CheckAppStoreRetireView.width))
        }
        let plain = try height(false, false)
        let finished = try height(true, false)
        let failed = try height(false, true)
        let both = try height(true, true)
        #expect(plain > 120, "물러남 창이 거의 안 그려졌다(\(plain)pt)")
        #expect(both <= 420, "물러남 창이 \(both)pt — 작은 화면에서 버튼이 밀려난다")
        #expect(finished > plain + 10, "근무를 마쳤다는 줄이 그려지지 않는다(\(plain) → \(finished))")
        #expect(failed > plain + 10, "지난번에 못 지웠다는 줄이 그려지지 않는다(\(plain) → \(failed))")
        #expect(both > finished + 10)
    }

    @Test func 창은_처음_고른_것만_따르고_닫기는_나중에다() {
        let count = V0353WatchProbe()
        let remove = AppStoreRetireWindowController(appStoreEdition: URL(fileURLWithPath: "/Applications/AingCheck.app"),
                                                    finishedWork: false, onRemove: { count.removed += 1 }, onLater: { count.later += 1 })
        remove.choose(.remove)
        remove.choose(.remove)
        remove.choose(.later)   // 지우는 중에 창이 닫혀도 [나중에]로 읽지 않는다
        #expect(count.removed == 1 && count.later == 0)
        #expect(remove.choice == .remove)
        #expect(remove.window == nil, "고르기만 했는데 창이 생겼다")

        let close = AppStoreRetireWindowController(appStoreEdition: URL(fileURLWithPath: "/Applications/AingCheck.app"),
                                                   finishedWork: true, onRemove: { count.removed += 1 }, onLater: { count.later += 1 })
        close.choose(.later)
        close.choose(.remove)
        #expect(count.removed == 1 && count.later == 1)

        // 창을 버튼 없이 닫았다(빨간 단추) = [나중에]. 실제로 오는 길(창 델리게이트)을 그대로 부른다 — 창은 띄우지 않는다
        // (그래서 창 칸도 통지의 대상도 nil 이다).
        let closing = AppStoreRetireWindowController(appStoreEdition: URL(fileURLWithPath: "/Applications/AingCheck.app"),
                                                     finishedWork: false, onRemove: { count.removed += 1 }, onLater: { count.later += 1 })
        closing.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: nil))
        #expect(closing.choice == .later && count.later == 2, "창을 닫았는데 [나중에]가 아니다 — 아이콘도 창도 없는 프로세스가 남는다")
        closing.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: nil))
        #expect(count.later == 2 && count.removed == 1)
        // 지우는 중에 창이 닫혀도 [나중에]로 읽지 않는다.
        remove.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: nil))
        #expect(count.later == 2 && remove.choice == .remove)
    }

    @Test func 창의_기본_동작은_나중에면_종료고_지우기는_누른_순간의_계획을_효과로_실행한다() async {
        let appStore = URL(fileURLWithPath: "/Applications/AingCheck.app", isDirectory: true)
        let own = URL(fileURLWithPath: "/Applications/aing-check.app", isDirectory: true)
        // [나중에](주입 안 함) → 종료 효과 한 번, 그 밖엔 아무것도.
        let later = V0353EffectLog(trashSucceeds: true)
        let laterWindow = AppStoreRetireWindowController(appStoreEdition: appStore, finishedWork: false, effects: later.effects,
                                                         makeRemoval: { _ in Issue.record("나중에가 지우기 계획을 만들었다"); return nil })
        laterWindow.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: nil))
        #expect(later.entries == ["terminate"], "[나중에]·창 닫기가 앱을 끝내지 않는다: \(later.entries)")

        // [지우기] — 누른 순간 앱스토어 판이 없으면(계획 nil) 아무것도 안 지우고 끝낸다.
        let gone = V0353EffectLog(trashSucceeds: true)
        let probe = V0353WatchProbe()
        let goneWindow = AppStoreRetireWindowController(appStoreEdition: appStore, finishedWork: false, effects: gone.effects,
                                                        makeRemoval: { probe.launched.append($0); return nil })
        goneWindow.choose(.remove)
        await v0353Settle { !gone.entries.isEmpty }
        #expect(probe.launched == [appStore], "누른 순간 처음 찾은 자리로 다시 판정하지 않는다")
        #expect(gone.entries == ["terminate"], "앱스토어 판이 없는데 무언가를 했다: \(gone.entries)")

        // [지우기] — 계획이 있으면 그 계획을 같은 효과로 실행한다.
        let removal = AppStoreRetireRemoval.plan(installSource: .standalone, brewPath: nil, ownBundle: own, ownBundleIsApp: true,
                                                 appStoreEdition: appStore, processID: 3)
        let run = V0353EffectLog(trashSucceeds: true)
        let runWindow = AppStoreRetireWindowController(appStoreEdition: appStore, finishedWork: false, effects: run.effects,
                                                       makeRemoval: { _ in removal })
        runWindow.choose(.remove)
        await v0353Settle { run.entries.last == "terminate" }
        #expect(run.entries == ["unregister", "trash \(own.path)", "spawn 7", "terminate"])
    }

    @Test func 다시_띄우기는_새_인스턴스로_인자를_넘긴다() throws {
        let appStore = URL(fileURLWithPath: "/Applications/AingCheck.app", isDirectory: true)
        let arguments = AppStoreEditionRetirement.relaunchArguments(finishedWork: true, appStoreEdition: appStore)
        let configuration = AppStoreRetireEffects.relaunchConfiguration(arguments: arguments)
        #expect(configuration.createsNewApplicationInstance, "새 인스턴스가 아니면 곧 끝날 지금 인스턴스만 깨어나고 물러남 창이 안 뜬다")
        #expect(configuration.arguments == arguments)
        let helper = v0353Collapsed(try v0353Source("AppStoreEditionRetirement.swift"))
        let relaunch = try #require(v0353Block(after: "static func relaunchSelf(arguments: [String]) async", in: helper))
        #expect(relaunch.contains("openApplication(at: Bundle.main.bundleURL, configuration: relaunchConfiguration(arguments: arguments))"))
    }

    // MARK: ③ 메뉴바 아이콘 쓰기

    @Test func 사용자가_아이콘을_빼면_예전처럼_앱을_끝내고_물러남이_내린_것은_아니다() {
        let normal = AppStoreRetirementState(launchAppStoreEdition: nil)
        #expect(normal.shouldQuitAfterMenuBarWrite(inserted: false), "⌘-끌기로 뺐는데 앱이 남는다 — 아이콘 없는 앱이 보이지 않게 돈다")
        #expect(!normal.shouldQuitAfterMenuBarWrite(inserted: true))
        normal.beginMidRunRetirement()
        #expect(!normal.shouldQuitAfterMenuBarWrite(inserted: false), "실행 중 물러남이 내린 것을 사용자가 뺀 것으로 읽었다")
        let retired = AppStoreRetirementState(launchAppStoreEdition: URL(fileURLWithPath: "/Applications/AingCheck.app"))
        #expect(!retired.shouldQuitAfterMenuBarWrite(inserted: false))
    }

    // MARK: ④ 스토어 방어 게이트 — 결과(서버 호출 수)로 잰다

    @Test func 물러난_스토어는_저장_세션을_살리지_않는다() async {
        let retiredHost = "v0353-activate-retired"
        let retired = v0353SignedInStore(host: retiredHost)
        retired.retiredForAppStoreEdition = true
        defer { v0353Stop(retired) }
        #expect(retired.isSignedIn)
        #expect(retired.activateStoredSessionOnLaunch() == nil, "물러난 실행이 실행 킥을 쐈다")
        await retired.activateStoredSession()   // 팝오버의 `.task` 길(아이콘 게이트가 뚫렸다고 치고)
        #expect(URLProtocolStub.requests(forHost: retiredHost).isEmpty, "물러난 실행이 서버를 쳤다(토큰 회전·팀 확정)")
        #expect(retired.refreshTask == nil, "물러난 실행이 상태 폴링을 띄웠다")

        // 대조군: 같은 저장 세션 · 게이트만 내리면 실제로 나간다.
        let controlHost = "v0353-activate-control"
        let control = v0353SignedInStore(host: controlHost)
        defer { v0353Stop(control) }
        await control.activateStoredSessionOnLaunch()?.value
        let paths = URLProtocolStub.requests(forHost: controlHost).compactMap { $0.url?.path }
        #expect(paths.contains("/auth/v1/token") && paths.contains("/rest/v1/memberships"), "대조군이 헛돈다: \(paths)")
    }

    @Test func 물러난_스토어는_근무를_열지_않는다() async {
        let retiredHost = "v0353-start-retired"
        let retired = v0353SessionStore(host: retiredHost)
        retired.retiredForAppStoreEdition = true
        defer { v0353Stop(retired) }
        retired.start()
        retired.toggle()
        await retired.syncTask?.value
        #expect(retired.startedAt == nil, "물러난 실행이 근무를 열었다 — 같은 맥이 근무를 두 번 센다")
        #expect(!retired.snapshot.isWorking)
        #expect(URLProtocolStub.requests(forHost: retiredHost).isEmpty)

        let controlHost = "v0353-start-control"
        let control = v0353SessionStore(host: controlHost)
        defer { v0353Stop(control) }
        control.start()
        await control.syncTask?.value
        #expect(control.startedAt != nil)
        #expect(!URLProtocolStub.requests(forHost: controlHost).isEmpty, "대조군이 헛돈다 — 근무 시작이 서버에 안 갔다")
    }

    /// 실행 중 물러남은 마무리 동기화(최대 3초)를 기다린 뒤에야 물러남 표식을 세운다. 그 틈에 단축키·넛지가 새 근무를 열면
    /// 그 세션은 곧 `.terminateNow` 로 마무리 없이 버려진다 — 물러나는 중 표식이 근무 시작만 막는다(업로드는 막지 않는다).
    @Test func 물러나는_중에는_마무리_뒤_새_근무가_열리지_않고_업로드는_막지_않는다() async {
        let host = "v0353-retiring"
        let store = v0353SessionStore(host: host)
        defer { v0353Stop(store) }
        store.start()
        await store.syncTask?.value
        #expect(store.startedAt != nil)
        store.retiringForAppStoreEdition = true
        #expect(store.aiToolDataAllowed, "물러나는 중인데 AI 기록 읽기가 꺼졌다 — 마무리 경로의 마지막 업로드가 막힌다")
        await store.finishWorkBeforeQuit()
        #expect(store.startedAt == nil)
        let before = URLProtocolStub.requests(forHost: host).count
        store.start()       // 단축키
        store.toggle()      // 팝오버 · 넛지
        await store.syncTask?.value
        #expect(store.startedAt == nil, "물러나는 중에 새 근무가 열렸다 — 곧 버려져 서버에 유령 근무가 남는다")
        #expect(URLProtocolStub.requests(forHost: host).count == before)

        // 대조군: 표식 없이 같은 순서면 마무리 뒤에 새 근무가 실제로 열린다(이 테스트가 헛돌지 않는다).
        let controlHost = "v0353-retiring-control"
        let control = v0353SessionStore(host: controlHost)
        defer { v0353Stop(control) }
        control.start()
        await control.syncTask?.value
        await control.finishWorkBeforeQuit()
        control.start()
        await control.syncTask?.value
        #expect(control.startedAt != nil, "대조군이 헛돈다 — 마무리 뒤 근무 시작이 원래 막혀 있다")
    }

    @Test func 물러난_스토어는_토큰을_읽지도_올리지도_않는다() async throws {
        let host = "v0353-upload-gate"
        let home = CheckTestScratch.directory("home")
        try v0353WriteClaudeLog(into: home, input: 2_468)
        let tokens = TokenUsageStore(defaults: CheckTestScratch.defaults("tokens"), homeDirectory: home,
                                     cacheURL: home.appendingPathComponent("cache/v0353.json"),
                                     notificationCenter: NotificationCenter(), codexHomeResolver: { nil },
                                     edition: .developerID)
        let store = v0353SessionStore(host: host, tokenUsage: tokens)
        defer { v0353Stop(store) }
        store.retiredForAppStoreEdition = true
        store.startedAt = Date().addingTimeInterval(-600)   // 배경 스캔의 다른 가드(근무 중)를 연다
        #expect(store.macEdition == .developerID)
        #expect(!store.aiToolDataAllowed, "물러났는데 AI 기록 읽기가 허용이다")
        try #require(store.hasDeviceIdentity)

        let usage = TokenUsageMonthly(month: TokenUsageMonthKey.current(), claudeInput: 100, codexInput: 5_000)
        await store.uploadTokenUsageIfNeeded(usage: usage, now: Date())
        await store.refreshTokenUsageInBackgroundIfDue(now: Date())
        await store.sendTokenScanHeartbeatIfNeeded(now: Date())
        #expect(tokens.scanCount == 0, "물러난 실행이 AI 도구 기록을 읽었다")
        #expect(URLProtocolStub.requests(forHost: host).isEmpty, "물러난 실행이 토큰 숫자를 올렸다")

        // 대조군: 게이트 하나만 내리면 같은 스토어가 읽고 올린다.
        store.retiredForAppStoreEdition = false
        #expect(store.aiToolDataAllowed)
        await store.refreshTokenUsageInBackgroundIfDue(now: Date())
        #expect(tokens.scanCount == 1)
        #expect(URLProtocolStub.requests(forHost: host).contains {
            $0.httpMethod == "POST" && $0.url?.path == "/rest/v1/token_usage_device_monthly"
        }, "대조군이 헛돈다 — 게이트를 내려도 안 올렸다")
    }

    /// 물러난 실행도 스토어는 살아 있고 잠자기/깨어남 통지를 받는다. 깨어남은 미니게임 인편(디스크에 남은 점수)을 밀어 서버에 보낸다 —
    /// 물러남 창을 띄운 채 덮개를 여닫아도 아무것도 안 나가야 한다.
    @Test func 물러난_스토어는_깨어나도_서버를_치지_않는다() async throws {
        let userID = "00000000-0000-0000-0000-000000000002"
        let pending = MiniGamePendingSubmit(id: UUID(), kind: .flappy, score: 7, token: "tok-wake",
                                            tokenIssuedAt: Date(), recordedAt: Date(), attempts: 0)
        let seed = try JSONEncoder().encode([pending])

        let retiredHost = "v0353-wake-retired"
        let retired = v0353SessionStore(host: retiredHost)
        defer { v0353Stop(retired) }
        retired.defaults.set(seed, forKey: WorkTimerStore.miniGamePendingKey(userID: userID))
        retired.retiredForAppStoreEdition = true
        retired.handleWake(at: Date())
        await v0353Settle { false }
        #expect(URLProtocolStub.requests(forHost: retiredHost).isEmpty, "물러난 실행이 깨어나며 서버를 쳤다")

        // 대조군: 같은 인편 · 게이트만 내리면 깨어남이 인편을 실제로 민다.
        let controlHost = "v0353-wake-control"
        let control = v0353SessionStore(host: controlHost)
        defer { v0353Stop(control) }
        control.defaults.set(seed, forKey: WorkTimerStore.miniGamePendingKey(userID: userID))
        control.handleWake(at: Date())
        await v0353Settle { URLProtocolStub.requests(forHost: controlHost).contains { $0.url?.path == "/rest/v1/rpc/minigame_submit_score" } }
        #expect(URLProtocolStub.requests(forHost: controlHost).contains { $0.url?.path == "/rest/v1/rpc/minigame_submit_score" },
                "대조군이 헛돈다 — 깨어남이 인편을 안 밀었다")
    }

    // MARK: ⑤ 소스 계약 — 배선

    @Test func 실행_시점_판정은_어느_배선보다도_앞이고_물러나면_돌아간다() throws {
        let app = v0353Collapsed(try v0353Source("CheckApp.swift"))
        let launch = try #require(v0353Block(after: "func applicationDidFinishLaunching(_ notification: Notification)", in: app))
        let body = launch
        let signal = try #require(body.range(of: "GracefulTerminationSignal.install()"))
        let branch = try #require(body.range(of: "if let appStoreEdition = retirement.launchAppStoreEdition {"),
                                  "실행 시점 물러남 판정이 앱 시작에 없다")
        #expect(signal.upperBound <= branch.lowerBound, "SIGTERM 마무리보다 물러남 판정이 먼저다")
        let branchBody = try #require(v0353Block(after: "if let appStoreEdition = retirement.launchAppStoreEdition", in: body))
        #expect(branchBody == "{ enterRetiredMode(appStoreEdition: appStoreEdition) return }",
                "물러남 갈래가 창만 띄우고 곧장 돌아가지 않는다: \(branchBody)")
        for wiring in [
            "overlayController = CheckOverlayController(", "store.menuPopoverOnScreenProbe =", "wireTodoBoard()",
            "wireSettingsWindow()", "wireGomoku()", "wireChess()",
            "workShortcut = WorkShortcutCoordinator(store: store, registrar: CarbonWorkShortcutRegistrar())",
            "updateCheck.noticeFetcher =", "updateCheck.startServerWatch()", "LoginItemRegistrar.registerIfNeeded(",
            "store.activateStoredSessionOnLaunch()", "masOnboarding = MacAppStoreOnboardingController(store: store)",
            "startWatchingForAppStoreEdition()",
        ] {
            let site = try #require(body.range(of: wiring), "앱 시작에 [\(wiring)] 가 없다")
            #expect(branch.upperBound <= site.lowerBound, "[\(wiring)] 가 물러남 판정보다 먼저다 — 물러날 실행에서도 돈다")
        }
        // 물러남 모드가 하는 일: 스토어 게이트 + 창 하나. 다른 배선은 없다.
        let enter = try #require(v0353Block(after: "private func enterRetiredMode(appStoreEdition: URL)", in: app))
        #expect(enter.contains("store.retiredForAppStoreEdition = true"))
        #expect(enter.contains("AppStoreRetireWindowController(") && enter.contains(".present()"))
        // 창이 실제 상태를 그대로 받는다(근무 마무리 · 지난번 brew 실패) — 상수로 바뀌면 창이 그 줄을 영영 안 그린다.
        #expect(enter.contains("appStoreEdition: appStoreEdition, finishedWork: retirement.finishedWorkBeforeRelaunch, previousRemovalFailed: AppStoreRetireRemoval.previousBrewUninstallFailed()"),
                "물러남 창에 근무 마무리 · 지난번 실패 표식이 그대로 가지 않는다: \(enter)")
        for banned in ["activateStoredSession", "WorkShortcutCoordinator", "LoginItemRegistrar", "startServerWatch",
                       "CheckOverlayController", "TodoSyncWiring", "wireGomoku", "wireChess", "masOnboarding"] {
            #expect(!enter.contains(banned), "물러남 모드가 [\(banned)] 를 한다")
        }
    }

    @Test func 메뉴바_아이콘_삽입은_물러남_상태에_묶여_있다() throws {
        let raw = try v0353Source("CheckApp.swift")
        let lines = raw.components(separatedBy: "\n")
        let excluded = V0351IfConfig.linesExcludedUnderMAS(raw)
        let inserted = lines.indices.filter { lines[$0].contains("MenuBarExtra(isInserted:") }
        #expect(inserted.count == 1, "isInserted 로 가르는 MenuBarExtra 가 하나가 아니다")
        for index in inserted {
            #expect(lines[index].contains("appDelegate.retirement.menuBarInserted"), "아이콘 삽입이 물러남 상태를 읽지 않는다: \(lines[index])")
            #expect(excluded.contains(index), "isInserted 갈래가 앱스토어 판에서도 컴파일된다")
        }
        // 쓰기(사용자가 ⌘-끌기로 뺐다)는 예전처럼 앱을 끝낸다 — 판단은 상태가, 종료는 다음 틱에.
        let collapsed = v0353Collapsed(raw)
        // v0.3.69: 하나만 실행의 대기 중(아이콘을 빼 둔 동안)에 온 쓰기는 사용자가 뺀 것이 아니라 함께 거른다(SingleInstanceGuardTests).
        #expect(collapsed.contains("set: { inserted in guard appDelegate.singleInstance.menuBarInserted, appDelegate.retirement.shouldQuitAfterMenuBarWrite(inserted: inserted) else { return } DispatchQueue.main.async { NSApp.terminate(nil) } }"),
                "아이콘을 빼면 아이콘 없는 앱이 남는다")
        // 앱스토어 판은 `MenuBarExtra {`(아이콘을 늘 넣는 0.3.52 의 생성자) 갈래이고 그 판에서만 컴파일된다. 본문·라벨은 두 판이 함께
        // 쓰는 속성(`menuContent` · `menuLabel`)으로 뺐다 — 그래서 앱스토어 판 소스 모양은 0.3.52 와 다르지만 그리는 것은 같다.
        let plain = lines.indices.filter { lines[$0].trimmingCharacters(in: .whitespaces) == "MenuBarExtra {" }
        #expect(plain.count == 1)
        let ifMAS = try #require(lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "#if CHECK_MAS" })
        let elseLine = try #require(lines.indices.first { $0 > ifMAS && lines[$0].trimmingCharacters(in: .whitespaces) == "#else" })
        let endLine = try #require(lines.indices.first { $0 > elseLine && lines[$0].trimmingCharacters(in: .whitespaces) == "#endif" })
        #expect(plain.allSatisfy { ifMAS < $0 && $0 < elseLine }, "아이콘을 늘 넣는 MenuBarExtra 가 Developer ID 판에서도 컴파일된다")
        #expect(inserted.allSatisfy { elseLine < $0 && $0 < endLine })
        // 본문·라벨은 한 벌이다(두 판의 MenuBarExtra 가 같은 것을 쓴다).
        #expect(raw.components(separatedBy: "MenuBarStatusLabel(").count - 1 == 1)
        #expect(raw.components(separatedBy: "menuContent\n").count - 1 >= 2 && raw.components(separatedBy: "menuLabel\n").count - 1 >= 2)
        // 함께 쓰는 속성은 울타리 밖이라 앱스토어 판에도 컴파일된다 — 물러남 코드나 판 갈래가 들어오면 그 판으로 샌다.
        for property in ["private var menuContent: some View", "private var menuLabel: some View"] {
            let block = try #require(v0353Block(after: property, in: raw), "\(property) 가 없다")
            for banned in ["retire", "Retire", "#if", "AppStoreEdition", "CHECK_MAS"] {
                #expect(!block.contains(banned), "\(property) 에 [\(banned)] 가 있다 — 앱스토어 판의 메뉴바가 바뀐다")
            }
        }
    }

    @Test func 실행_중_감시가_배선돼_있고_근무를_마친_뒤에_다시_띄운다() throws {
        let app = v0353Collapsed(try v0353Source("CheckApp.swift"))
        let watch = try #require(v0353Block(after: "private func startWatchingForAppStoreEdition()", in: app))
        #expect(watch.contains("appStoreLaunchWatcher = AppStoreEditionLaunchWatcher("))
        #expect(watch.contains("center: NSWorkspace.shared.notificationCenter"), "감시가 실제 워크스페이스 통지를 안 본다")
        #expect(watch.contains("workspace: NSWorkspace.shared"), "실행 중 앱 목록(KVO) 보험이 빠졌다")
        #expect(watch.contains("AppStoreEditionRetirement.midRunDecision("), "감시가 설치 판정을 거치지 않는다 — 스크래치 빌드에 물러난다")
        #expect(watch.contains("retireMidRun(appStoreEdition: appStoreEdition)"))
        let retire = try #require(v0353Block(after: "private func retireMidRun(appStoreEdition: URL) async", in: app))
        var previous = retire.startIndex
        for step in [
            "guard retirement.beginMidRunRetirement() else { return }",
            "store.retiringForAppStoreEdition = true",
            "AppStoreEditionRetirement.shouldFinishWorkBeforeRetiring( isSignedIn: store.isSignedIn, startedAt: store.startedAt, adoptedRemoteSession: store.adoptedRemoteSession )",
            "if finishedWork { await store.finishWorkBeforeQuit() }",
            "store.retiredForAppStoreEdition = true",
            "AppStoreRetireEffects.relaunchSelf(",
            "AppStoreEditionRetirement.relaunchArguments(finishedWork: finishedWork, appStoreEdition: appStoreEdition)",
            "NSApp.terminate(nil)",
        ] {
            let found = try #require(retire.range(of: step, range: previous..<retire.endIndex), "실행 중 물러남에 [\(step)] 가 없거나 순서가 틀렸다")
            previous = found.upperBound
        }
        // 종료 훅: 물러난 실행은 퇴근 동기화를 다시 하지 않는다 — 그리고 원래 가드(내가 연 근무)는 그대로 있다.
        let terminate = try #require(v0353Block(after: "func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply", in: app))
        let retiredGuard = try #require(terminate.range(of: "if store.retiredForAppStoreEdition { return .terminateNow }"))
        let ownGuard = try #require(terminate.range(of: "guard store.isSignedIn, store.startedAt != nil, !store.adoptedRemoteSession else {"))
        #expect(retiredGuard.upperBound <= ownGuard.lowerBound)
        // 실행 중 물러남의 조건은 그 가드와 같은 세 칸이다.
        let helper = v0353Collapsed(try v0353Source("AppStoreEditionRetirement.swift"))
        #expect(helper.contains("isSignedIn && startedAt != nil && !adoptedRemoteSession"))
        // 앱이 활성화될 때(물러남 창을 띄우며) 미니게임 인편을 밀지 않는다.
        let active = try #require(v0353Block(after: "func applicationDidBecomeActive(_ notification: Notification)", in: app))
        let activeGuard = try #require(active.range(of: "guard !store.retiredForAppStoreEdition else { return }"))
        let retry = try #require(active.range(of: "store.retryMiniGamePendingSubmitIfAny()"))
        #expect(activeGuard.upperBound <= retry.lowerBound)
    }

    @Test func 물러남은_전부_앱스토어_판_울타리_안에_있다() throws {
        let needles = ["retirement", "retiredForAppStoreEdition", "retiringForAppStoreEdition", "AppStoreEditionRetirement",
                       "AppStoreRetire", "AppStoreEditionLaunchWatcher", "retireMidRun", "enterRetiredMode",
                       "startWatchingForAppStoreEdition", "uninstall --cask", "allowAlongside", "shouldQuitAfterMenuBarWrite",
                       "CandidateSources", "translocationOriginal", "previousBrewUninstallFailed"]
        var hits = 0
        var files = Set<String>()
        for (name, source) in try v0353AllSources() {
            let excluded = V0351IfConfig.linesExcludedUnderMAS(source)
            for (index, line) in source.components(separatedBy: "\n").enumerated() where needles.contains(where: line.contains) {
                hits += 1
                files.insert(name)
                #expect(excluded.contains(index), "앱스토어 판에서도 컴파일되는 물러남 코드: \(name):\(index + 1) \(line)")
            }
        }
        #expect(hits >= 40, "검사가 헛돈다(\(hits)곳)")
        #expect(files.isSuperset(of: ["CheckApp.swift", "AppStoreEditionRetirement.swift", "WorkTimerStore.swift",
                                       "WorkTimerStoreAuth.swift", "WorkTimerStoreMacEdition.swift"]), "\(files.sorted())")
        // 새 파일은 import 와 울타리 말고는 **전부** 울타리 안이다.
        let file = try v0353Source("AppStoreEditionRetirement.swift")
        let excluded = V0351IfConfig.linesExcludedUnderMAS(file)
        for (index, line) in file.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("import "), !trimmed.hasPrefix("#if"), !trimmed.hasPrefix("#endif") else { continue }
            #expect(excluded.contains(index), "AppStoreEditionRetirement.swift:\(index + 1) 이 앱스토어 판에서 컴파일된다: \(line)")
        }
        // 판정표 한 줄은 울타리 밖이다(표는 두 판이 같다) — 값은 앱스토어 판에서 거짓.
        try #require(v0353Source("MacEdition.swift").contains("package var retiresWhenAppStoreEditionInstalled: Bool { self == .developerID }"))
    }
}

// MARK: - 헬퍼

private enum V0353Receipt { case present, missing, empty, directory }

/// 클로저가 부른 것을 담는 상자(메인 액터 — 관찰자·창 클로저가 같은 스레드에서 쓴다).
@MainActor
private final class V0353WatchProbe {
    var asked: [String?] = []
    var answer: URL?
    var launched: [URL] = []
    var removed = 0
    var later = 0
}

/// 가짜 후보 문(LaunchServices · 실행 중 앱 · 관례 자리) — 무엇을 물었는지 남긴다. 실제 LaunchServices 는 묻지 않는다.
@MainActor
private final class V0353SourcesProbe {
    var registeredAsked: [String] = []
    var runningAsked: [String] = []

    func sources(registered: [URL] = [], running: [URL] = [], fixed: [URL] = []) -> AppStoreEditionRetirement.CandidateSources {
        AppStoreEditionRetirement.CandidateSources(
            registered: { [self] identifier in registeredAsked.append(identifier); return registered },
            running: { [self] identifier in runningAsked.append(identifier); return running },
            fixed: fixed
        )
    }
}

/// 끝난 뒤 앱스토어 판을 여는 셸에 넘길 인자(계획이 만들어야 하는 그대로).
private func v0353OpenArguments(appStore: URL, pid: Int32, log: String = AppStoreRetireRemoval.logPath) -> [String] {
    ["-c", AppStoreRetireRemoval.openSpawnWrapper, "aing-check-retire", AppStoreRetireRemoval.openAfterExitScript,
     appStore.path, String(pid), log]
}

/// brew 가 관리하지 않는 출처(파일 시스템 · brew 를 묻지 않는다).
@MainActor
private func v0353StandaloneRunner(_ bundle: URL) -> UpdateRunner {
    UpdateRunner(fileExists: { _ in false }, directoryContents: { _ in [] }, resolvePath: { $0 }, isWritable: { _ in false },
                 bundlePath: bundle.path, currentBuild: nil, readState: { _ in nil }, clearState: { _ in },
                 spawn: { _ in Issue.record("brew 를 띄웠다"); return false },
                 spawnDMG: { _ in Issue.record("DMG 스크립트를 띄웠다"); return false })
}

/// `/opt/homebrew` 가 **이 번들을** 관리하는 출처(Caskroom 의 0.3.53 사본이 이 번들을 가리킨다).
@MainActor
private func v0353BrewRunner(_ bundle: URL) -> UpdateRunner {
    UpdateRunner(fileExists: { $0 == "/opt/homebrew/bin/brew" },
                 directoryContents: { $0 == "/opt/homebrew/Caskroom/aing-check" ? ["0.3.53"] : [] },
                 resolvePath: { $0.hasPrefix("/opt/homebrew/Caskroom/") ? bundle.path : $0 }, isWritable: { _ in false },
                 bundlePath: bundle.path, currentBuild: nil, readState: { _ in nil }, clearState: { _ in },
                 spawn: { _ in Issue.record("brew 를 띄웠다"); return false },
                 spawnDMG: { _ in Issue.record("DMG 스크립트를 띄웠다"); return false })
}

/// 스크래치 폴더에 가짜 앱 번들을 만든다(`<dir>/<name>.app`). 기본은 '앱스토어가 설치한 앱스토어 판' 모양이다.
private func v0353MakeBundle(
    in directory: URL,
    name: String = "AingCheck",
    bundleIdentifier: String? = "com.yehsung.aingcheck",
    receipt: V0353Receipt = .present,
    macOS: Bool = true
) throws -> URL {
    let fm = FileManager.default
    let app = directory.appendingPathComponent("\(name).app", isDirectory: true)
    let contents = app.appendingPathComponent("Contents", isDirectory: true)
    try fm.createDirectory(at: contents, withIntermediateDirectories: true)
    var plist: [String: Any] = ["CFBundleName": name, "CFBundlePackageType": "APPL"]
    if let bundleIdentifier { plist["CFBundleIdentifier"] = bundleIdentifier }
    try v0353WritePlist(plist, to: contents.appendingPathComponent("Info.plist"))
    if macOS {
        let bin = contents.appendingPathComponent("MacOS", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: bin.appendingPathComponent(name))
    }
    let receiptDir = contents.appendingPathComponent("_MASReceipt", isDirectory: true)
    switch receipt {
    case .present:
        try fm.createDirectory(at: receiptDir, withIntermediateDirectories: true)
        try Data([0x30, 0x82, 0x01, 0x00]).write(to: receiptDir.appendingPathComponent("receipt"))
    case .empty:
        try fm.createDirectory(at: receiptDir, withIntermediateDirectories: true)
        try Data().write(to: receiptDir.appendingPathComponent("receipt"))
    case .directory:
        try fm.createDirectory(at: receiptDir.appendingPathComponent("receipt"), withIntermediateDirectories: true)
    case .missing:
        break
    }
    return app
}

private func v0353WritePlist(_ plist: [String: Any], to url: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: url)
}

/// 가짜 효과 — 부른 순서를 글자로 남긴다(실제 휴지통·SMAppService·Process·NSWorkspace·NSApp 은 건드리지 않는다).
@MainActor
private final class V0353EffectLog {
    private(set) var entries: [String] = []
    private(set) var spawned: [[String]] = []
    let trashSucceeds: Bool
    let spawnSucceeds: Bool

    init(trashSucceeds: Bool, spawnSucceeds: Bool = true) {
        self.trashSucceeds = trashSucceeds
        self.spawnSucceeds = spawnSucceeds
    }

    var effects: AppStoreRetireEffects {
        AppStoreRetireEffects(
            unregisterLoginItem: { [self] in entries.append("unregister") },
            spawnDetached: { [self] arguments in
                entries.append("spawn \(arguments.count)")
                spawned.append(arguments)
                return spawnSucceeds
            },
            moveToTrash: { [self] url in entries.append("trash \(url.path)"); return trashSucceeds },
            revealInFinder: { [self] url in entries.append("reveal \(url.path)") },
            openApplication: { [self] url in entries.append("open \(url.path)") },
            terminate: { [self] in entries.append("terminate") }
        )
    }
}

/// 조건이 설 때까지(최대 1초) 메인 런루프를 돌린다 — `.main` 큐 관찰자의 블록이 돌 틈을 준다.
@MainActor
private func v0353Settle(_ done: () -> Bool) async {
    for _ in 0..<50 {
        if done() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// 저장 세션이 있는 스토어(실행 킥이 토큰 회전·팀 확정을 하는 상태).
@MainActor
private func v0353SignedInStore(host: String, function: String = #function) -> WorkTimerStore {
    let defaults = CheckTestScratch.defaults(host, function: function)
    defaults.set("old-access-token", forKey: WorkTimerStore.accessTokenKey)
    defaults.set("old-refresh-token", forKey: WorkTimerStore.refreshTokenKey)
    defaults.set("00000000-0000-0000-0000-000000000002", forKey: WorkTimerStore.userIDKey)
    return WorkTimerStore(
        service: SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                     session: URLSession(configuration: .stubbed)),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
}

/// 세션·팀을 직접 넣은 스토어(근무 시작·업로드가 바로 서버로 가는 상태).
@MainActor
private func v0353SessionStore(host: String, tokenUsage: TokenUsageStore = .shared, function: String = #function) -> WorkTimerStore {
    let store = WorkTimerStore(
        service: SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                     session: URLSession(configuration: .stubbed)),
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: CheckTestScratch.defaults(host, function: function),
        workspaceNotifications: nil,
        tokenUsage: tokenUsage
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000002")
    store.currentTeamID = URLProtocolStub.stubTeamID
    // 빌드를 모르게 둔다 — 알면 업로드가 Codex 진단(실제 ~/.codex 순회)을 하루 1회 계산한다(V0351 과 같은 이유).
    store.appVersionProvider = { nil }
    return store
}

@MainActor
private func v0353Stop(_ store: WorkTimerStore) {
    store.tickerTask?.cancel()
    store.refreshTask?.cancel()
    store.pokePollTask?.cancel()
}

/// 이번 달 Claude 기록 한 줄을 임시 홈의 `~/.claude/projects` 에 쓴다.
private func v0353WriteClaudeLog(into home: URL, input: Int) throws {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let line = "{\"type\":\"assistant\",\"timestamp\":\"\(formatter.string(from: Date()))\","
        + "\"requestId\":\"req_v0353\",\"message\":{\"id\":\"msg_v0353\",\"usage\":{\"input_tokens\":\(input)}}}\n"
    let file = home.appendingPathComponent(".claude/projects/p/session.jsonl")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(line.utf8).write(to: file)
}

@MainActor
private func v0353Height(_ view: some View, width: CGFloat) -> CGFloat? {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return CGFloat(bitmap.pixelsHigh) / 2
}

// MARK: 소스 읽기

private func v0353Source(_ name: String) throws -> String {
    let directory = FileManager.default.fileExists(atPath: CheckCoreSourceLayout.macDirectory.appendingPathComponent(name).path)
        ? CheckCoreSourceLayout.macDirectory : CheckCoreSourceLayout.coreDirectory
    return V0351IfConfig.strippingComments(try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8))
}

private func v0353AllSources() throws -> [(String, String)] {
    var out: [(String, String)] = []
    for directory in [CheckCoreSourceLayout.macDirectory, CheckCoreSourceLayout.coreDirectory] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".swift") }
        for name in names.sorted() {
            let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            out.append((name, V0351IfConfig.strippingComments(text)))
        }
    }
    return out
}

private func v0353Collapsed(_ source: String) -> String {
    source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// `anchor` 뒤 첫 `{` 부터 짝이 맞는 `}` 까지(양 끝 포함). 문자열 리터럴 안의 괄호는 건너뛴다.
private func v0353Block(after anchor: String, in source: String) -> String? {
    guard let hit = source.range(of: anchor), let open = source[hit.upperBound...].firstIndex(of: "{") else { return nil }
    var depth = 0
    var inString = false
    var index = open
    while index < source.endIndex {
        let c = source[index]
        if inString {
            if c == "\\" {
                index = source.index(after: index)
                if index == source.endIndex { break }
            } else if c == "\"" {
                inString = false
            }
        } else if c == "\"" {
            inString = true
        } else if c == "{" {
            depth += 1
        } else if c == "}" {
            depth -= 1
            if depth == 0 { return String(source[open...index]) }
        }
        index = source.index(after: index)
    }
    return nil
}
