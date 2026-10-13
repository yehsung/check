import AppKit
import CheckCore
import SwiftUI

// MARK: - 맥 앱스토어 판: 첫 실행 안내 · 다른 판 동시 실행 경고 (v0.3.51)
//
// 두 창 모두 **맥 앱스토어 판에서만** 뜬다(판정은 `MacEdition` — Developer ID 판에서는 여기 어떤 창도 만들어지지 않는다).
//
// ① 첫 실행 안내 — 묻는 것이 둘이고 **한 화면**에서 묻는다(심사 지침이 둘 다 요구한다):
//    · 로그인 시 자동 실행: 2.4.5(iii) "동의 없이 로그인 때 자동 실행하지 않는다". 기본 **꺼짐**, 사용자가 체크해야 켠다.
//    · AI 도구 기록 읽기: 5.1.1(ii) 남의 앱이 남긴 사용 기록을 읽어 순위판에 올리려면 동의와 거두는 길이 있어야 한다.
//      [허용하고 시작]이 곧 동의이고, [나중에]·창 닫기는 거절이다. 어느 쪽이든 설정에서 언제든 바꿀 수 있다.
//    덤으로 2.5.14(입력 활동 기록)를 한 줄로 밝히고, 메뉴바 전용 앱이라 "앱이 안 떴다"로 읽히지 않게 아이콘 자리를 알린다.
//    **한 번만** 묻는다: 어느 버튼을 누르든·창을 닫든 `firstRunCompletedKey` 가 선다.
//
// ② 다른 판 동시 실행 경고 — 같은 맥에서 brew·DMG 판(번들 `kingcheck`)이 함께 돌면 기기가 두 대로 잡히고(기기 ID 가
//    컨테이너마다 따로다) 전역 단축키 한 번에 두 앱이 함께 근무를 토글한다. 막지는 않는다 — **한 번** 알리고 끝이다.

/// 첫 실행 안내의 문구 한 벌(순수 값 — 테스트가 글자 그대로 되묻는다).
enum FirstRunText {
    static let windowTitle = "아잉체크 시작하기"
    static let title = "시작하기 전에 두 가지만 정해 주세요"
    static let menuBarHint = "아잉체크는 화면 맨 위 메뉴 막대에 있어요. 아잉 아이콘을 누르면 열려요."
    static let aiTitle = "AI 사용량을 팀 순위에 올릴까요?"
    static let aiBody = "AI 코딩 도구가 이 맥에 남긴 사용 기록(~/.claude · ~/.codex · ~/.gemini · Orca 폴더)을 읽기만 해서 토큰 숫자를 세요. 대화 내용·프롬프트·파일 경로는 보내지 않고 숫자만 올라가요."
    static let aiLimitsNote = "Codex 를 쓰면 사용 한도(%)를 보여 주려고 그 로그인 파일도 읽어요. 폴더에 아무것도 쓰지 않아요."
    static let loginTitle = "맥에 로그인하면 자동으로 켜기"
    static let loginDetail = "켜 두면 근무 시작을 놓치지 않아요."
    static let activityNote = "근무 중에는 자리 비움을 알아채려고 마지막으로 키보드·마우스를 쓴 시각만 기록해요. 무엇을 입력했는지는 기록하지 않아요."
    static let settingsNote = "둘 다 설정에서 언제든 바꿀 수 있어요."
    static let later = "나중에"
    static let allow = "허용하고 시작"
}

/// 다른 판 경고의 문구 한 벌.
enum OtherEditionText {
    static let windowTitle = "아잉체크"
    static let title = "다른 아잉체크가 켜져 있어요"
    static let body = "홈페이지(brew·DMG)에서 받은 아잉체크가 이 맥에서 함께 돌고 있어요. 둘을 같이 켜 두면 같은 맥이 두 대로 집계되고, 단축키 한 번에 근무가 두 번 바뀔 수 있어요. 하나만 켜 두세요."
    static let ok = "알겠어요"
}

/// 첫 실행 안내·다른 판 경고의 **순수 판정**(테스트가 두 판을 다 넣어 되묻는다).
enum MacAppStoreOnboarding {
    /// 첫 실행 안내를 마쳤다(어느 버튼이든 · 창을 닫았든).
    static let firstRunCompletedKey = "check.mas.firstRunCompleted"
    /// 다른 판 경고를 이미 한 번 보여 줬다.
    static let otherEditionWarnedKey = "check.mas.otherEditionWarned"

    /// 첫 실행 안내를 띄울 때인가: 이 판이 묻는 판이고, 아직 한 번도 끝내지 않았다.
    static func shouldShowFirstRun(edition: MacEdition, defaults: UserDefaults) -> Bool {
        edition.showsFirstRunConsent && !defaults.bool(forKey: firstRunCompletedKey)
    }

    /// 다른 판 경고를 띄울 때인가: 이 판에 '다른 판'이 있고, 그 판이 지금 돌고 있고, 아직 경고한 적이 없다.
    static func shouldWarnAboutOtherEdition(
        edition: MacEdition, runningBundleIdentifiers: [String], alreadyWarned: Bool
    ) -> Bool {
        guard !alreadyWarned else { return false }
        let others = Set(edition.otherEditionBundleIdentifiers)
        return !others.isEmpty && runningBundleIdentifiers.contains(where: others.contains)
    }

    /// 사용자가 첫 실행 안내를 끝냈다. **세 갈래가 모두 이 함수 하나**를 지난다([허용하고 시작] · [나중에] · 창 닫기).
    ///  - allowAITools: AI 도구 기록 읽기 동의(닫기·[나중에]는 false).
    ///  - launchAtLogin: 체크 상자의 값. 켰을 때만 등록한다(`LoginItemRegistrar.applyUserToggle` — 의도 키까지 남긴다).
    ///    끈 채로 끝내면 **아무것도 하지 않는다** — 기본이 꺼짐이고, 등록된 적도 없다.
    @MainActor
    static func complete(
        store: WorkTimerStore,
        allowAITools: Bool,
        launchAtLogin: Bool,
        defaults: UserDefaults = .standard,
        applyLaunchAtLogin: (Bool) -> Void = { LoginItemRegistrar.applyUserToggle($0) }
    ) {
        defaults.set(true, forKey: firstRunCompletedKey)
        store.setAIToolDataConsent(allowAITools)
        if launchAtLogin { applyLaunchAtLogin(true) }
    }
}

// MARK: - 첫 실행 안내 화면

/// 첫 실행 안내의 본문. 창 없이도 그릴 수 있어(`ImageRenderer`) 테스트가 문구·버튼이 실제로 그려지는지 잰다.
struct CheckFirstRunView: View {
    /// 끝냈을 때(AI 동의 여부, 로그인 시 자동 실행 체크).
    let onFinish: (_ allowAITools: Bool, _ launchAtLogin: Bool) -> Void
    /// 체크 상자 기본값은 **꺼짐**이다(2.4.5(iii)). 렌더 테스트만 켜진 모습을 그리려고 넘긴다.
    @State private var launchAtLogin: Bool

    static let width: CGFloat = 440

    init(launchAtLoginSeed: Bool = false, onFinish: @escaping (_ allowAITools: Bool, _ launchAtLogin: Bool) -> Void) {
        self.onFinish = onFinish
        _launchAtLogin = State(initialValue: launchAtLoginSeed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(FirstRunText.title)
                    .font(.headline)
                    .foregroundStyle(CheckTheme.primaryText)
                Label(FirstRunText.menuBarHint, systemImage: "menubar.arrow.up.rectangle")
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(FirstRunText.aiTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                Text(FirstRunText.aiBody)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(FirstRunText.aiLimitsNote)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelStyle()
            CheckSettingsToggleRow(
                title: FirstRunText.loginTitle,
                detail: FirstRunText.loginDetail,
                isOn: $launchAtLogin
            )
            .padding(12)
            .panelStyle()
            VStack(alignment: .leading, spacing: 4) {
                Text(FirstRunText.activityNote)
                Text(FirstRunText.settingsNote)
            }
            .font(.caption2)
            .foregroundStyle(CheckTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(FirstRunText.later) { onFinish(false, launchAtLogin) }
                    .keyboardShortcut(.cancelAction)
                Button(FirstRunText.allow) { onFinish(true, launchAtLogin) }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: Self.width, alignment: .topLeading)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
    }
}

/// 다른 판 경고의 본문.
struct CheckOtherEditionNoticeView: View {
    let onDismiss: () -> Void
    static let width: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(OtherEditionText.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(CheckTheme.primaryText)
            Text(OtherEditionText.body)
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button(OtherEditionText.ok, action: onDismiss)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(20)
        .frame(width: Self.width, alignment: .topLeading)
        .background(CheckTheme.background)
    }
}

// MARK: - 창

/// 맥 앱스토어 판의 안내 창 둘(첫 실행 · 다른 판 경고)을 띄우고 지키는 배선. **앱 수명 동안 하나**다(AppDelegate 가 든다).
@MainActor
final class MacAppStoreOnboardingController: NSObject, NSWindowDelegate {
    private let store: WorkTimerStore
    private let defaults: UserDefaults
    private var firstRunWindow: NSWindow?
    private var otherEditionWindow: NSWindow?
    private var launchObserver: NSObjectProtocol?
    /// 첫 실행 창이 버튼으로 끝났는가(창 닫기와 가르는 표식 — 닫기는 '나중에'로 읽는다).
    private var firstRunFinishedByButton = false

    init(store: WorkTimerStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    /// 실행 직후 한 번. 판이 묻지 않는 판(Developer ID)이면 아무것도 하지 않는다.
    func start() {
        guard store.macEdition.showsFirstRunConsent || !store.macEdition.otherEditionBundleIdentifiers.isEmpty else { return }
        if MacAppStoreOnboarding.shouldShowFirstRun(edition: store.macEdition, defaults: defaults) {
            showFirstRun()
        }
        checkOtherEdition(running: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        guard !store.macEdition.otherEditionBundleIdentifiers.isEmpty, launchObserver == nil else { return }
        // 이 앱이 켜진 **뒤에** 다른 판이 켜지는 경우도 본다(로그인 항목 순서는 정해져 있지 않다).
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.checkOtherEdition(running: id.map { [$0] } ?? []) }
        }
    }

    private func checkOtherEdition(running: [String]) {
        guard MacAppStoreOnboarding.shouldWarnAboutOtherEdition(
            edition: store.macEdition,
            runningBundleIdentifiers: running,
            alreadyWarned: defaults.bool(forKey: MacAppStoreOnboarding.otherEditionWarnedKey)
        ) else { return }
        defaults.set(true, forKey: MacAppStoreOnboarding.otherEditionWarnedKey)
        let view = CheckOtherEditionNoticeView { [weak self] in self?.otherEditionWindow?.close() }
        otherEditionWindow = present(view, title: OtherEditionText.windowTitle)
    }

    private func showFirstRun() {
        let view = CheckFirstRunView { [weak self] allow, launchAtLogin in
            guard let self else { return }
            self.firstRunFinishedByButton = true
            MacAppStoreOnboarding.complete(
                store: self.store, allowAITools: allow, launchAtLogin: launchAtLogin, defaults: self.defaults
            )
            self.firstRunWindow?.close()
        }
        firstRunWindow = present(view, title: FirstRunText.windowTitle)
    }

    /// 작은 안내 창 하나를 띄운다(설정 창과 같은 결 — 다크 고정 · 지금 보는 Space · 테스트에서는 활성화하지 않는다).
    private func present(_ view: some View, title: String) -> NSWindow {
        let hosting = NSHostingController(rootView: view)
        // 창 크기는 본문이 정한다(폭은 뷰가 못 박고, 높이는 문구 줄 수에 따라 — 창이 내용보다 작아 버튼이 잘리지 않게).
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = title
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
        return window
    }

    /// 첫 실행 창을 버튼 없이 닫았다 = **나중에**(AI 기록은 읽지 않고, 자동 실행도 켜지 않는다). 한 번 물었으니 다시 묻지 않는다.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === firstRunWindow {
            if !firstRunFinishedByButton {
                MacAppStoreOnboarding.complete(store: store, allowAITools: false, launchAtLogin: false, defaults: defaults)
            }
            firstRunWindow = nil
        } else if closing === otherEditionWindow {
            otherEditionWindow = nil
        }
    }
}
