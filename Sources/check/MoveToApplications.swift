import AppKit
import CheckCore
import os

// MARK: - 응용 프로그램 폴더로 옮기기 제안 (v0.3.69)
//
// 2026-10-30 '아이콘 둘' 신고의 뿌리(사용자가 직접 재현): DMG 창의 [응용 프로그램으로 끌어다 놓기] 화면에서 앱 아이콘을 그냥 누르면
// macOS 는 디스크 이미지(또는 App Translocation 임시 자리)에서 **그대로 실행한다** — 옮기라고 강제하지 않는다. 그 사본은 DMG 를 꺼내거나
// 재부팅하면 사라지고 앱 안 업데이트도 막힌다(`UpdateRunner.isRunningFromReadOnlyLocation`). 두 사본이 함께 뜨는 것은 하나만 실행
// 장치(`SingleInstanceGuard`)가 막고, 이 제안은 그 자리에서만 쓰는 사람을 설치된 자리로 데려간다(사용자 결정 2026-10-30 "옮기기 제안
// 추가" — 강제는 아니다. [나중에]면 이 실행은 그대로 쓴다).
//
//  · 판정(`MoveToApplications.plan`)은 순수 함수다. 읽기 전용 자리가 아니면 묻지 않는다. 대상 폴더는 `/Applications` 에 쓸 수 있으면
//    거기, 아니면 `~/Applications`. 두 폴더 어디든 **같거나 새 빌드**(또는 빌드를 모르는 사본)가 이미 있으면 복사하지 않고 그 사본을
//    연다(`.openExisting`). 대상 폴더에 옛 빌드가 있으면 휴지통에 넣고 복사한다(`.replace`). 없으면 복사한다(`.copy`).
//  · 복사한 사본에서 **격리 속성(`com.apple.quarantine`)을 걷는다.** 남기면 Finder 가 아닌 손으로 옮긴 격리 앱이라 macOS 가 새 자리
//    사본도 App Translocation 임시 자리로 띄운다 — 그러면 새 사본도 읽기 전용 자리라 같은 제안이 끝없이 돈다. 이 앱은 공증됐고
//    Gatekeeper 가 이미 첫 실행에서 검사를 마친 같은 바이트다(LetsMove 같은 흔한 구현도 같은 일을 한다).
//  · 옮긴 뒤 새 자리 사본을 열고 이 실행은 평소대로 끝난다(`NSApp.terminate` — 근무 마무리 포함). 새 사본의 하나만 실행 장치도
//    '설치된 자리 > 임시 자리'로 이 실행을 끝내니, 어느 쪽이 먼저 닿아도 남는 것은 설치된 사본 하나다.
//  · 실패(권한 · 공간 · 열기)하면 Finder 로 끌어다 놓으라는 안내만 하고 이 실행은 그대로 쓴다.
//  · 묻는 때: 하나만 실행 판정으로 **남기로 정해진 뒤** · 물러남이 아닐 때 · 런루프 다음 바퀴(배선을 마친 뒤). 설치본이 떠 있으면 이
//    사본은 그보다 앞서 양보해 끝났으므로 여기까지 오지 않는다.
//
// ★ 앱스토어 판에서는 컴파일되지 않는다(하나만 실행 · 물러남과 같은 울타리).
#if !CHECK_MAS

enum MoveToApplications {
    /// 옮기기 판정.
    enum Plan: Equatable, Sendable {
        /// 읽기 전용 자리가 아니다 — 묻지 않는다.
        case none
        /// 대상 자리에 사본이 없다 — 복사한다.
        case copy(to: URL)
        /// 대상 자리에 옛 빌드가 있다 — 그것을 휴지통에 넣고 복사한다.
        case replace(URL)
        /// 같거나 새 빌드(또는 빌드를 모르는 사본)가 이미 설치돼 있다 — 복사 없이 그 사본을 연다.
        case openExisting(URL)
    }

    /// 대상 자리에 이미 있는 사본.
    enum Existing: Equatable, Sendable {
        case absent
        case present(build: Int?)
    }

    static let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
    static let logger = Logger(subsystem: "kingcheck", category: "moveToApplications")

    /// 판정. `existing` 은 그 자리에 사본이 있는지와 빌드를 알려 준다(테스트는 가짜, 실제로는 `existingCopy(at:)`).
    static func plan(
        bundleURL: URL,
        myBuild: Int?,
        systemApplicationsWritable: Bool,
        homeDirectory: URL,
        existing: (URL) -> Existing
    ) -> Plan {
        guard UpdateRunner.isReadOnlyLocation(bundleURL.path) else { return .none }
        let name = bundleURL.lastPathComponent
        let system = systemApplications.appendingPathComponent(name, isDirectory: true)
        let user = homeDirectory.appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        for candidate in [system, user] {
            guard case .present(let build) = existing(candidate) else { continue }
            if let build, let myBuild, build < myBuild { continue }
            return .openExisting(candidate)
        }
        let target = systemApplicationsWritable ? system : user
        if case .present = existing(target) { return .replace(target) }
        return .copy(to: target)
    }

    /// 그 자리의 사본 — 번들 폴더가 있으면 `Info.plist` 의 빌드를 읽는다(하나만 실행과 같은 읽기).
    static func existingCopy(at url: URL) -> Existing {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .absent
        }
        return .present(build: SingleInstanceGuard.bundleBuild(at: url))
    }

    /// 이 실행의 판정(실제 파일 시스템).
    static func currentPlan(bundle: Bundle = .main) -> Plan {
        plan(
            bundleURL: bundle.bundleURL.resolvingSymlinksInPath(),
            myBuild: SingleInstanceGuard.buildNumber(bundle.object(forInfoDictionaryKey: "CFBundleVersion")),
            systemApplicationsWritable: FileManager.default.isWritableFile(atPath: systemApplications.path),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            existing: existingCopy(at:)
        )
    }

    /// 번들 안 모든 항목에서 격리 속성을 걷는다(머리 주석 — 남기면 새 자리 사본이 다시 임시 자리로 뜬다). 없는 항목은 그냥 지나간다.
    static func removeQuarantine(at bundle: URL) {
        let attribute = "com.apple.quarantine"
        var paths = [bundle.path]
        if let walker = FileManager.default.enumerator(atPath: bundle.path) {
            while let relative = walker.nextObject() as? String {
                paths.append(bundle.appendingPathComponent(relative).path)
            }
        }
        for path in paths {
            _ = removexattr(path, attribute, XATTR_NOFOLLOW)
        }
    }
}

/// 제안 창의 글자(테스트가 같은 값을 읽는다).
enum MoveToApplicationsText {
    static let title = "응용 프로그램 폴더로 옮길까요?"
    static let body = "지금 디스크 이미지에서 실행 중이에요. 이대로 쓰면 디스크 이미지를 꺼내거나 재부팅할 때 앱이 사라지고, 업데이트도 받을 수 없어요."
    static let move = "옮기기"
    static let existingTitle = "응용 프로그램 폴더에 이미 설치돼 있어요"
    static let existingBody = "지금은 디스크 이미지에서 실행 중이에요. 설치된 앱으로 다시 열게요."
    static let openExisting = "설치된 앱 열기"
    static let later = "나중에"
    static let failedTitle = "옮기지 못했어요"
    static let failedBody = "디스크 이미지 창에서 앱 아이콘을 응용 프로그램 폴더로 끌어다 놓은 뒤, 거기서 다시 열어 주세요."
}

// MARK: - 실행 (주입 가능)

/// 옮기기를 실행에 옮기는 문들. 실제로는 `.live`(NSAlert · FileManager · NSWorkspace)이고 테스트는 가짜를 넣는다.
struct MoveToApplicationsEffects {
    /// 묻는다 — 참이면 [옮기기]/[설치된 앱 열기].
    var confirm: @MainActor (MoveToApplications.Plan) -> Bool
    /// 옛 사본을 휴지통에.
    var trash: @MainActor (URL) throws -> Void
    /// 이 번들을 그 자리로 복사하고 격리 속성을 걷는다.
    var copy: @MainActor (_ from: URL, _ to: URL) throws -> Void
    /// 그 사본을 연다 — 참이면 열렸다.
    var open: @MainActor (URL) async -> Bool
    /// 실패 안내.
    var reportFailure: @MainActor () -> Void
    /// 이 실행을 끝낸다.
    var terminate: @MainActor () -> Void

    @MainActor
    static var live: MoveToApplicationsEffects { MoveToApplicationsEffects(
        confirm: { plan in
            let alert = NSAlert()
            if case .openExisting = plan {
                alert.messageText = MoveToApplicationsText.existingTitle
                alert.informativeText = MoveToApplicationsText.existingBody
                alert.addButton(withTitle: MoveToApplicationsText.openExisting)
            } else {
                alert.messageText = MoveToApplicationsText.title
                alert.informativeText = MoveToApplicationsText.body
                alert.addButton(withTitle: MoveToApplicationsText.move)
            }
            alert.addButton(withTitle: MoveToApplicationsText.later)
            // 메뉴바 앱(LSUIElement)은 늘 비활성이라 앞으로 데려오지 않으면 창이 다른 앱 뒤에 깔린다.
            NSApp.activate()
            return alert.runModal() == .alertFirstButtonReturn
        },
        trash: { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) },
        copy: { from, to in
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: from, to: to)
            MoveToApplications.removeQuarantine(at: to)
        },
        open: { url in
            await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                    if let error { MoveToApplications.logger.error("새 자리 사본을 열지 못함: \(error.localizedDescription, privacy: .public)") }
                    continuation.resume(returning: app != nil && error == nil)
                }
            }
        },
        reportFailure: {
            let alert = NSAlert()
            alert.messageText = MoveToApplicationsText.failedTitle
            alert.informativeText = MoveToApplicationsText.failedBody
            NSApp.activate()
            alert.runModal()
        },
        terminate: { NSApp.terminate(nil) }
    ) }
}

extension MoveToApplications {
    /// 판정을 실행에 옮긴다. 끝까지 가면 새 자리 사본이 열리고 이 실행은 끝난다. 묻지 않았거나 [나중에]면 false.
    @MainActor
    @discardableResult
    static func run(plan: Plan, bundleURL: URL, effects: MoveToApplicationsEffects) async -> Bool {
        guard plan != .none, effects.confirm(plan) else { return false }
        let destination: URL
        do {
            switch plan {
            case .none:
                return false
            case .openExisting(let url):
                destination = url
            case .replace(let url):
                try effects.trash(url)
                try effects.copy(bundleURL, url)
                destination = url
            case .copy(let url):
                try effects.copy(bundleURL, url)
                destination = url
            }
        } catch {
            logger.error("옮기기 실패: \(error.localizedDescription, privacy: .public)")
            effects.reportFailure()
            return false
        }
        guard await effects.open(destination) else {
            effects.reportFailure()
            return false
        }
        effects.terminate()
        return true
    }
}

#endif
