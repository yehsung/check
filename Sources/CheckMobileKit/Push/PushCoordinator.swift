import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 푸시 받기(SPEC-ios §5 · SPEC-ios-build D9). **Foundation · Observation 만** 쓴다 — 시스템 일은 `PushNotificationSystem`
/// (iOS 는 `PushNotificationCenterAdapter`)에 시키고, 판단은 여기서 해서 macOS `swift test` 로 검증한다.
///
/// 자리 API(기반이 부르는 것 — 이름·모양을 지킨다)
/// - `init(context:)` · `appDidBecomeActive()` · `appDidEnterBackground()` · `reset()` — 탭 스토어와 같은 수명 규칙.
/// - `sessionDidSignIn()` — 로그인 상태가 된 순간(실행 복원 포함).
/// - `didRegisterForRemoteNotifications(deviceToken:)` / `didFailToRegisterForRemoteNotifications(error:)`.
///
/// 하는 일
/// 1. **권한**: 로그인 뒤 앱이 앞에 있고 권한을 아직 묻지 않았으면 설명 시트를 먼저 띄운다("나중에"는 7일 쉰다).
///    허락이면(또는 이미 허락돼 있으면) 실행마다 한 번 원격 등록 → 토큰 hex → `session.updateAPNsToken`(바뀌면 즉시 register_device,
///    환경은 Info.plist `AingAPNsEnvironment` — Debug sandbox / Release production, 세션 스토어가 싣는다).
/// 2. **포그라운드 표시**: 지금 보고 있는 대화의 메시지면 숨기고, 아니면 배너. 어느 쪽이든 해당 스토어를 새로고침한다.
///    앱이 띄운 안내 알림(답장 실패 — `userInfo` 에 대화 상대가 실려 누르면 그 대화가 열린다)은 숨기지 않는다.
/// 3. **응답**(앱 프로세스 — 401 이면 세션 조정자 경유 갱신 허용): 탭 → 라우트 · 답장 → send_message + mark_messages_read ·
///    읽음 → mark · 수락 → gomoku_respond(accept) 후 대국 열기 · 거절 → gomoku_respond(decline).
///    알림 액션으로 앱이 깨어났으면 실행 복원(`.launching`)이 끝날 때까지 기다린다.
/// 4. **앱 배지** = 메시지 안 읽은 수 + 받은 오목 신청 수. **모르면 적지 않는다**(push-verify 발견 2): 이번 세대에 서버 값을 받기 전
///    (실행 복원 중 · 업데이트 필요 · 알림 액션으로 뒤에서 켜져 탭 스토어가 아무것도 안 읽은 실행)에는 아이콘을 건드리지 않는다.
///    - 앱이 앞: 서버 확인(`message_unread_summary`) 한 번이 지나면 탭 배지 합(`context.links.badges.appBadgeTotal`)을 관찰해 적는다.
///    - 앱이 뒤(알림 액션): 액션 끝에 요약 · 오목 받은함을 직접 읽어 합을 적는다(끝날 때까지 기다린다 — 시스템이 곧 앱을 재운다).
///    - 로그아웃(확정된 `.signedOut`) · 치명 만료: 0.
/// 5. **알림 설정 공개 API**(나 탭 설정 화면이 쓰는 유일한 구현 — 통합 w4/int 에서 나 탭의 `session.savePushPrefs` 직접 저장을 걷어냈다):
///    `authorization` · `authorizationText` · `prefs` · `knowsPrefs` · `isEnabled(_:)` · `isSavingPrefs` · `prefsNotice` ·
///    `setPreference(_:enabled:)` · `enableNotifications()`(권한 요청 진입점) · `refreshAuthorization()` · `openSystemSettings()`.
///    설정 저장은 직렬이다(겹쳐 누르면 끝난 뒤 최신 값으로 한 번 더). 서버값을 모르면 보내지 않는다(`knowsPrefs`).
///
/// 폰 금지 호출 없음: 이 파일이 부르는 서버 함수는 send_message · mark_messages_read · message_history(_with_reads) ·
/// message_unread_summary(배지 확인) · gomoku_respond · gomoku_inbox(오목 스토어 경유) · register_device/set_push_prefs(세션 경유)뿐이다.
@MainActor
@Observable
package final class PushCoordinator {
    @ObservationIgnored package let context: MobileContext
    @ObservationIgnored package private(set) var system: PushNotificationSystem?

    // MARK: 관찰 상태(나 탭 · 설명 시트가 읽는다)

    /// 시스템 알림 권한(마지막으로 읽은 값).
    package private(set) var authorization: PushAuthorizationStatus = .unknown
    /// 설명 시트가 떠 있는가.
    package private(set) var isPrimerPresented = false
    /// 시스템 권한 창을 기다리는 중(버튼 잠금).
    package private(set) var isRequestingAuthorization = false
    /// 알림 설정을 저장하는 중. 저장 중에는 `prefs` 가 누른 값을 먼저 보여 준다.
    package private(set) var isSavingPrefs = false
    /// 알림 설정 저장 실패 한 줄.
    package var prefsNotice: String?

    // MARK: 설정값

    /// 설명 시트에서 "나중에"를 누르면 이만큼 다시 묻지 않는다.
    package nonisolated static let primerCooldownSeconds: TimeInterval = 7 * 24 * 3600
    /// 공용 suite 키(기기 값 — 로그아웃해도 남는다).
    package nonisolated static let primerDismissedAtKey = "aingcheck.push.primerDismissedAt"
    /// 알림 액션으로 깨어난 앱이 실행 복원을 기다리는 상한(초). 시스템이 주는 백그라운드 시간(약 30초) 안이어야 한다.
    @ObservationIgnored package var sessionSettleTimeoutSeconds: TimeInterval = 10
    /// 다른 오목 요청이 끝나기를 기다리는 상한(초).
    @ObservationIgnored package var gomokuBusyTimeoutSeconds: TimeInterval = 3

    // MARK: 내부

    @ObservationIgnored private var isAppActive = false
    @ObservationIgnored private var registeredThisLaunch = false
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var statusCheckAgain = false
    @ObservationIgnored private var statusCheckWantsPrimer = false

    /// 사용자가 마지막으로 누른 알림 설정(저장이 끝날 때까지 화면이 이 값을 그린다). **관찰한다** — 저장 중에 다른 토글을 눌러도
    /// `isSavingPrefs` 는 그대로라, 이 값이 관찰되지 않으면 화면이 새로 누른 값을 그리지 않는다.
    private var desiredPrefs: PushPrefs?
    /// 알림 설정 저장은 **한 번에 하나**(push-verify 발견 4). 도는 동안 누른 값은 `desiredPrefs` 에 쌓이고 끝난 뒤 한 번 더 보낸다.
    @ObservationIgnored private var prefsSaveTask: Task<Bool, Never>?
    @ObservationIgnored private var prefsSaveAgain = false

    /// 앱 배지의 앎(관찰한다 — 바뀌면 배지 관찰이 다시 계산한다).
    private var badgeKnowledge: BadgeKnowledge = .unknown
    @ObservationIgnored private var isTrackingBadges = false
    /// 이번 세대에 탭 스토어가 활성화됐는가(앱이 로그인 상태로 한 번이라도 앞에 왔다). 뒤에서 켜진 실행의 스토어는 아무것도 안 읽었다.
    @ObservationIgnored private var storesActivated = false
    @ObservationIgnored private var badgeConfirmTask: Task<Void, Never>?
    @ObservationIgnored private var badgeConfirmAgain = false
    @ObservationIgnored package private(set) var lastAppliedBadge: Int?
    /// 마지막 원격 등록 실패(진단). 시뮬레이터 · 엔타이틀먼트 없는 빌드에서 온다.
    @ObservationIgnored package private(set) var lastRegistrationError: String?

    #if DEBUG
    /// 데모: 권한 상태와 무관하게 로그인 뒤 설명 시트를 한 번 띄운다(`-AingCheckDemoPushPrimer YES`).
    @ObservationIgnored package var demoForcesPrimer = false
    #endif

    /// 앱 배지 합의 출처(기본: 메시지 · 게임 탭 배지 합). 관찰 가능한 값을 읽어야 한다 — 바뀌면 다시 적는다. 테스트가 바꾼다.
    /// 앱이 앞에 있고 서버 확인이 끝난 뒤에만 읽는다(`badgeTarget`).
    @ObservationIgnored package var badgeTotalSource: @MainActor () -> Int

    /// 앱 배지를 얼마나 아는가.
    package enum BadgeKnowledge: Equatable, Sendable {
        /// 이번 세대에 서버 값을 아직 모른다 — 아이콘을 건드리지 않는다(앞 실행이 적은 값을 둔다).
        case unknown
        /// 앱이 뒤에 있을 때 코디네이터가 서버에서 직접 읽어 적었다. 탭 스토어는 아직 안 읽었을 수 있어 관찰값을 적지 않는다.
        case server
        /// 앱이 앞에서 서버 확인을 마쳤다 — 탭 배지 합을 관찰해 적는다.
        case stores
    }

    /// 지금 앎(테스트 · 진단).
    package var badgeState: BadgeKnowledge { badgeKnowledge }

    package init(context: MobileContext) {
        self.context = context
        let links = context.links
        badgeTotalSource = { [weak links] in links?.badges.appBadgeTotal ?? 0 }
    }

    /// iOS 어댑터를 붙인다(앱 델리게이트 didFinishLaunching — `MobileAppModel.installPushNotifications()`).
    /// 배지 관찰만 건다 — 실행 복원 중에는 모르는 값이라 아무것도 적지 않는다.
    package func attach(system: PushNotificationSystem) {
        self.system = system
        startBadgeTracking()
    }

    // MARK: - 수명

    package func appDidBecomeActive() {
        isAppActive = true
        storesActivated = true
        startBadgeTracking()
        if badgeKnowledge == .stores {
            applyBadge()
        } else {
            // 탭 스토어가 방금 새로고침을 띄웠다. 서버가 한 번 답한 뒤부터 합을 적는다(오프라인이면 앞 실행 값을 둔다).
            confirmBadge()
        }
        requestStatusCheck(allowPrimer: true)
    }

    package func appDidEnterBackground() {
        isAppActive = false
    }

    /// 로그아웃 · 치명 만료(세대가 바뀐 직후).
    /// - 설명 시트를 내리고 배지를 0 으로.
    /// - 알림 센터의 이 앱 알림을 지운다: 앞 계정의 보낸 사람 · 본문이 남고, 그 알림에 다음 계정으로 답장하는 길이 생기기 때문이다.
    /// - 원격 등록을 끊고 저장된 토큰을 잊는다: 치명 만료는 서버에 알릴 토큰이 없어 기기 행이 남고(D-base 위험 3-1), 로그아웃 정리도
    ///   실패할 수 있다. 끊긴 토큰은 APNs 가 410 으로 거절해 서버 발송기가 비운다. 다음 로그인에서 권한이 있으면 다시 등록한다.
    package func reset() {
        statusTask?.cancel()
        statusTask = nil
        statusCheckAgain = false
        statusCheckWantsPrimer = false
        if isPrimerPresented {
            isPrimerPresented = false
            system?.dismissPermissionPrimer()
        }
        isRequestingAuthorization = false
        desiredPrefs = nil
        prefsSaveTask = nil
        prefsSaveAgain = false
        isSavingPrefs = false
        prefsNotice = nil
        badgeConfirmTask?.cancel()
        badgeConfirmTask = nil
        badgeConfirmAgain = false
        storesActivated = false
        badgeKnowledge = .unknown
        // 로그아웃의 0 은 확정값이다(다음 계정 값을 모르는 채 앞 계정 숫자를 남기지 않는다).
        apply(badge: 0)
        if let system {
            system.removeAllDeliveredNotifications()
            system.unregisterForRemoteNotifications()
        }
        registeredThisLaunch = false
        context.session.updateAPNsToken(nil)
    }

    package func sessionDidSignIn() {
        startBadgeTracking()
        // 앱이 앞에 있으면 앱 모델이 곧바로 appDidBecomeActive 를 부른다(설명 시트는 그쪽에서) — 여기서는 등록만.
        requestStatusCheck(allowPrimer: false)
    }

    package func didRegisterForRemoteNotifications(deviceToken: Data) {
        lastRegistrationError = nil
        context.session.updateAPNsToken(PushTokenFormatter.hex(deviceToken))
    }

    package func didFailToRegisterForRemoteNotifications(error: Error) {
        // 시뮬레이터 · aps-environment 없는 빌드 · 오프라인에서 온다. 조용히 두고 다음 active 때 다시 시도한다.
        lastRegistrationError = String(describing: error)
        registeredThisLaunch = false
    }

    // MARK: - 권한 · 원격 등록

    /// 진행 중 확인(테스트가 기다린다).
    package var pendingStatusCheck: Task<Void, Never>? { statusTask }

    /// 권한을 읽고, 받을 수 있으면 등록, 아직 안 물었으면(허락 시) 설명 시트. 겹치면 뒤따르는 한 번으로 합친다.
    private func requestStatusCheck(allowPrimer: Bool) {
        statusCheckWantsPrimer = statusCheckWantsPrimer || allowPrimer
        guard system != nil else { return }
        if statusTask != nil {
            statusCheckAgain = true
            return
        }
        statusTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.statusCheckAgain = false
                let wantsPrimer = self.statusCheckWantsPrimer
                self.statusCheckWantsPrimer = false
                await self.performStatusCheck(allowPrimer: wantsPrimer)
                if Task.isCancelled { return }
            } while self.statusCheckAgain
            self.statusTask = nil
        }
    }

    private func performStatusCheck(allowPrimer: Bool) async {
        guard let system, context.session.isSignedIn else { return }
        let generation = context.generation
        let status = await system.authorizationStatus()
        guard generation == context.generation, context.session.isSignedIn else { return }
        if authorization != status { authorization = status }
        // 시트 판정이 먼저다(실제로는 미결정일 때만 참이라 순서가 갈리지 않는다 — 데모 강제 시트가 허락된 기기에서도 뜨게).
        if allowPrimer, shouldPresentPrimer(status: status) {
            presentPrimer()
        } else if status.allowsDelivery {
            registerIfNeeded()
        }
    }

    /// 설명 시트를 띄울 때인가: 로그인 · 앱이 앞 · 권한 미결정 · 시트 없음 · "나중에"에서 7일 지남 · 데모 아님.
    package func shouldPresentPrimer(status: PushAuthorizationStatus) -> Bool {
        guard context.session.isSignedIn, isAppActive, !isPrimerPresented else { return false }
        #if DEBUG
        if demoForcesPrimer { return true }
        #endif
        // 데모 스크린샷(다른 탭)이 시트에 가리지 않게 — 데모에서는 명시한 경우에만 띄운다.
        guard !context.isDemo, status == .notDetermined else { return false }
        if let dismissed = context.storage.defaults.object(forKey: Self.primerDismissedAtKey) as? Date {
            let elapsed = context.clock.now().timeIntervalSince(dismissed)
            // 시계가 뒤로 간 경우(elapsed < 0)도 쉬는 중으로 본다.
            guard elapsed >= Self.primerCooldownSeconds else { return false }
        }
        return true
    }

    private func presentPrimer() {
        #if DEBUG
        demoForcesPrimer = false
        #endif
        isPrimerPresented = true
        system?.presentPermissionPrimer(self)
    }

    /// 실행마다 한 번(애플 권장 — 토큰은 바뀔 수 있다). 결과는 앱 델리게이트 콜백으로 온다.
    private func registerIfNeeded() {
        guard !registeredThisLaunch, let system else { return }
        registeredThisLaunch = true
        system.registerForRemoteNotifications()
    }

    /// 설명 시트 "알림 켜기": 시스템 권한 창 → 허락이면 원격 등록.
    package func primerAllow() async {
        guard isPrimerPresented, !isRequestingAuthorization, let system else { return }
        isRequestingAuthorization = true
        let generation = context.generation
        _ = await system.requestAuthorization()
        isRequestingAuthorization = false
        guard generation == context.generation else { return }
        isPrimerPresented = false
        system.dismissPermissionPrimer()
        await refreshAuthorization()
    }

    /// 설명 시트 "나중에"(또는 끌어내려 닫음): 7일 쉰다.
    package func primerLater() {
        guard isPrimerPresented, !isRequestingAuthorization else { return }
        context.storage.defaults.set(context.clock.now(), forKey: Self.primerDismissedAtKey)
        isPrimerPresented = false
        system?.dismissPermissionPrimer()
    }

    /// 시트가 사용자 제스처로 사라졌다(어댑터가 부른다). "나중에"와 같다 — 권한 창을 기다리는 중이면 무시.
    package func primerDidDisappear() {
        guard isPrimerPresented, !isRequestingAuthorization else { return }
        context.storage.defaults.set(context.clock.now(), forKey: Self.primerDismissedAtKey)
        isPrimerPresented = false
    }

    /// 띄울 창이 끝내 없었다(어댑터가 부른다). 사용자가 거절한 것이 아니므로 쉬는 기간을 적지 않는다 — 다음 active 에 다시 본다.
    package func primerCouldNotPresent() {
        isPrimerPresented = false
    }

    // MARK: - 알림 설정 공개 API(나 탭)

    /// 지금 보여 줄 종류별 설정. 저장 중이면 마지막으로 누른 값, 아니면 서버가 마지막으로 알려 준 값(모르면 전부 켜짐 — 서버 기본값).
    package var prefs: PushPrefs {
        desiredPrefs ?? context.session.pushPrefs ?? PushPrefs()
    }

    package func isEnabled(_ kind: PushKind) -> Bool {
        kind.isEnabled(in: prefs)
    }

    /// 이 설치의 종류별 설정을 서버에서 받은 적이 있는가(register_device · set_push_prefs 응답, 또는 저장 중인 값).
    /// **모르면 토글을 잠그고 `setPreference` 도 보내지 않는다** — set_push_prefs 는 세 칸을 통째로 보내므로, 모르는 칸을 기본값(전부 켜짐)으로
    /// 채워 보내면 이 기기에서 꺼 둔 알림을 되살린다(나 탭 rankme 규칙을 한 구현으로 옮김).
    package var knowsPrefs: Bool {
        desiredPrefs != nil || context.session.pushPrefs != nil
    }

    /// 권한 한 줄("켜짐" · "꺼짐 — 설정 앱에서 켤 수 있어요" …).
    package var authorizationText: String {
        switch authorization {
        case .authorized, .ephemeral: return PushText.settingsAuthorized
        case .provisional: return PushText.settingsProvisional
        case .denied: return PushText.settingsDenied
        case .notDetermined: return PushText.settingsNotDetermined
        case .unknown: return PushText.settingsUnknown
        }
    }

    /// 권한 다시 읽기(설정 화면 표시 · 설정 앱에서 돌아왔을 때). 받을 수 있으면 등록도 한다.
    package func refreshAuthorization() async {
        guard let system else { return }
        let generation = context.generation
        let status = await system.authorizationStatus()
        guard generation == context.generation else { return }
        if authorization != status { authorization = status }
        if status.allowsDelivery, context.session.isSignedIn { registerIfNeeded() }
    }

    /// "알림 켜기" 버튼: 아직 안 물었으면 시스템 권한 창, 거절돼 있으면 설정 앱.
    package func enableNotifications() async {
        guard let system else { return }
        // 아직 한 번도 안 읽었으면 먼저 읽는다 — 이미 거절된 기기에서 권한 창(뜨지 않는다)을 부르고 끝나지 않게.
        if authorization == .unknown { await refreshAuthorization() }
        switch authorization {
        case .denied:
            system.openSystemSettings()
        case .unknown, .notDetermined:
            guard !isRequestingAuthorization else { return }
            isRequestingAuthorization = true
            _ = await system.requestAuthorization()
            isRequestingAuthorization = false
            await refreshAuthorization()
        case .authorized, .provisional, .ephemeral:
            await refreshAuthorization()
        }
    }

    package func openSystemSettings() {
        system?.openSystemSettings()
    }

    /// 종류 하나를 켜고 끈다 → set_push_prefs. 이 설치의 기기 행이 아직 없으면(not_found) 등록을 한 번 기다려 다시 저장한다.
    ///
    /// **저장은 직렬이다**(push-verify 발견 4). 예전에는 겹친 저장이 각자 그때의 3키를 보내고, 먼저 끝난 쪽이 "저장 중"을 내리고,
    /// 늦게 온 앞 응답이 뒤 값을 덮었다(서버가 앞 요청을 나중에 처리하면 서버 값까지 되돌아갔다). 이제
    /// - 도는 저장이 있으면 누른 값을 `desiredPrefs` 에 합쳐 두고 그 저장이 끝난 뒤 **최신 값으로 한 번 더** 보낸다(요청이 겹치지 않으니
    ///   서버 처리 순서 = 누른 순서, 응답도 순서대로 `session.pushPrefs` 에 앉는다).
    /// - `isSavingPrefs` 는 보낼 것이 모두 끝났을 때만 내린다. 돌려주는 값은 마지막 저장의 성공 여부(함께 기다린 호출 모두 같은 값).
    @discardableResult
    package func setPreference(_ kind: PushKind, enabled: Bool) async -> Bool {
        guard context.session.isSignedIn, knowsPrefs else { return false }
        desiredPrefs = kind.setting(enabled, in: prefs)
        if !isSavingPrefs { isSavingPrefs = true }
        prefsNotice = nil
        if let running = prefsSaveTask {
            prefsSaveAgain = true
            return await running.value
        }
        let generation = context.generation
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            return await self.runPrefsSaves(generation: generation)
        }
        prefsSaveTask = task
        return await task.value
    }

    private enum PrefsSaveOutcome {
        case saved
        case failed
        /// 취소 · 세대 바뀜 — 안내하지 않는다.
        case cancelled
    }

    private func runPrefsSaves(generation: Int) async -> Bool {
        var outcome = PrefsSaveOutcome.cancelled
        repeat {
            prefsSaveAgain = false
            guard let target = desiredPrefs else { break }
            outcome = await savePrefsOnce(target, generation: generation)
            // 세대가 바뀌었으면 reset 이 상태를 이미 비웠다 — 새 세대의 저장을 건드리지 않고 나간다.
            guard generation == context.generation else { return false }
        } while prefsSaveAgain
        prefsSaveTask = nil
        desiredPrefs = nil
        isSavingPrefs = false
        switch outcome {
        case .saved:
            return true
        case .failed:
            prefsNotice = PushText.settingsSaveFailed
            return false
        case .cancelled:
            return false
        }
    }

    private func savePrefsOnce(_ target: PushPrefs, generation: Int) async -> PrefsSaveOutcome {
        for attempt in 0..<2 {
            do {
                if try await context.session.savePushPrefs(target) != nil { return .saved }
            } catch {
                guard generation == context.generation else { return .cancelled }
                return AuthErrorRules.classify(error) == .cancelled ? .cancelled : .failed
            }
            guard generation == context.generation else { return .cancelled }
            guard attempt == 0 else { break }
            // not_found: 기기 행이 없다(첫 등록이 실패했거나 아직 안 끝났다) — 등록을 끝까지 기다린 뒤 한 번 더.
            context.session.requestDeviceRegistration(.signIn)
            await context.session.pendingDeviceRegistration?.value
            guard generation == context.generation else { return .cancelled }
        }
        return .failed
    }

    // MARK: - 포그라운드 표시

    /// 앱이 앞에 있을 때 알림이 왔다(`willPresent`). 해당 스토어를 새로고침하고 보일지 정한다.
    /// 앱이 띄운 안내 알림(답장 실패)은 언제나 보인다 — 지금 그 대화를 보고 있어도 보내지 못했다는 말은 숨기지 않는다.
    package func presentation(for payload: PushPayload?) -> PushPresentation {
        guard let payload, !payload.isLocalNotice else { return .banner }
        guard context.session.isSignedIn else { return .banner }
        refreshStores(for: payload)
        settleBadgeInForeground()
        if let peer = payload.messagePeerID, isAppActive,
           let visible = context.router.visibleConversationPeerID, visible.lowercased() == peer {
            return .hidden
        }
        return .banner
    }

    private func refreshStores(for payload: PushPayload) {
        switch payload.content {
        case .message(let peer, _):
            notifyMessages(peerID: peer)
        case .gomokuInvite:
            // 실시간 오목 신호와 같은 문(직렬화된 재조회 — 받은 신청이 로비·탭 배지에 곧 온다).
            context.gomoku.handleSignal()
        case .feedbackReply(let report):
            if let me = context.links.me { notifyFeedback(me, reportID: report) }
        }
    }

    private func notifyMessages(peerID: String) {
        guard let messages = context.links.messages else { return }
        deliverMessagePush(messages, peerID: peerID)
    }

    /// 요구 서명(`PushMessageRefreshing`)으로 부른다 — 기본 구현이 없으니 증인은 언제나 메시지 탭 스토어의 문이다.
    private func deliverMessagePush<Store: PushMessageRefreshing>(_ store: Store, peerID: String) {
        store.didReceiveMessagePush(peerID: peerID)
    }

    private func notifyFeedback<Store: PushFeedbackRefreshing>(_ store: Store, reportID: String?) {
        store.didReceiveFeedbackReplyPush(reportID: reportID)
    }

    // MARK: - 응답(탭 · 액션)

    /// 사용자가 알림을 누르거나 액션을 골랐다(`didReceive`). 끝날 때까지 기다린 뒤 어댑터가 시스템 완료 콜백을 부른다.
    package func handleResponse(_ payload: PushPayload?, action: PushAction) async {
        guard let payload, action != .ignore else { return }

        let signedIn = await waitForSessionSettled()
        guard signedIn else {
            if case .reply = action, let peer = payload.messagePeerID {
                postReplyFailure(PushText.replyNeedsSignIn, peerID: peer)
            }
            return
        }

        switch (action, payload.content) {
        case (.open, _):
            // 앱이 앞으로 온다 — 배지는 활성화(appDidBecomeActive)의 서버 확인이 맡는다.
            context.router.open(payload.route)
            refreshStores(for: payload)
        case (.reply(let text), .message(let peer, let messageID)):
            // 안 읽은 수가 바뀌는 것은 읽음이 올라갔을 때뿐이다(보내기는 내 안 읽은 수를 바꾸지 않는다).
            if await reply(text: text, peerID: peer, messageID: messageID) {
                await settleBadgeAfterBackgroundAction()
            }
        case (.markRead, .message(let peer, let messageID)):
            if await markRead(peerID: peer, messageID: messageID) {
                notifyMessagesIfActivated(peerID: peer)
                await settleBadgeAfterBackgroundAction()
            }
        case (.acceptInvite, .gomokuInvite(let match)):
            // 수락은 앱을 연다(카테고리 옵션 foreground) — 배지는 활성화가 맡는다.
            await respondInvite(matchID: match, accept: true)
        case (.declineInvite, .gomokuInvite(let match)):
            await respondInvite(matchID: match, accept: false)
            await settleBadgeAfterBackgroundAction()
        default:
            // 카테고리와 맞지 않는 액션(서버·앱 버전이 어긋난 경우) — 아무것도 하지 않는다.
            break
        }
    }

    /// 뒤에서 한 액션(답장 · 읽음) 뒤 메시지 탭 새로고침. 탭 스토어가 이번 세대에 활성화된 적이 없으면(알림 액션으로 켜진 실행)
    /// 부르지 않는다 — 그 스토어는 화면도 앎도 없고, 배지는 `settleBadgeAfterBackgroundAction` 이 서버에서 직접 읽는다.
    private func notifyMessagesIfActivated(peerID: String) {
        guard storesActivated else { return }
        notifyMessages(peerID: peerID)
    }

    /// 실행 복원이 끝날 때까지(상한) 기다린 뒤 로그인 상태인지. 벽시계가 아니라 단조 시계로 잰다(데모 시계는 멈춰 있다).
    private func waitForSessionSettled() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(Int(sessionSettleTimeoutSeconds * 1000)))
        while context.session.phase == .launching, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return context.session.isSignedIn
    }

    /// 답장: ① 이 계정에 온 메시지인지 확인 ② send_message ③ 읽음(답장했다는 것은 읽었다는 뜻 — 보내기가 거절돼도).
    ///
    /// ①이 필요한 이유: 알림 센터에 남은 **앞 계정의** 메시지 알림에 다른 계정으로 로그인한 뒤 답장하면, 페이로드에 받는 사람이 없어
    /// 지금 계정 이름으로 그 사람에게 보내진다. 지금 계정의 24시간 이력에서 그 메시지 id 를 받은 메시지로 찾을 때만 보낸다.
    ///
    /// **적은 글이 말없이 사라지지 않게**: 보내졌다는 것을 모르는 채로 끝나는 모든 갈래가 안내 알림을 남긴다. 답장 도중 세션이 치명 만료돼
    /// 세대가 바뀐 경우도 마찬가지다(push-verify 발견 3 — 예전에는 세대 가드에서 그냥 돌아갔다). 그 경우 `reset()` 이 이미 알림 센터를
    /// 비운 뒤라 안내가 지워지지 않는다(`expireSession` 은 `onSignedOut` 을 동기로 부른 뒤에 던진다).
    ///
    /// 돌려주는 값: 읽음 경계가 올라갔는가(앱 배지를 다시 읽을 이유).
    private func reply(text: String, peerID: String, messageID: String?) async -> Bool {
        let generation = context.generation
        guard let messageID else {
            postReplyFailure(PushText.replyMessageGone, peerID: peerID)
            return false
        }
        let verification = await verifyReceivedMessage(peerID: peerID, messageID: messageID)
        guard generation == context.generation else {
            postReplyLostSession(peerID: peerID)
            return false
        }
        switch verification {
        case .confirmed:
            break
        case .notFound:
            postReplyFailure(PushText.replyMessageGone, peerID: peerID)
            return false
        case .failed:
            postReplyFailure(PushText.connectionUnstable, peerID: peerID)
            return false
        }

        if case .empty = MessageBody.validate(text) {
            // 빈 답장은 보내지 않는다(서버 왕복 없이 invalid) — 읽음만.
        } else {
            do {
                let response = try await context.withMobileSessionRetry { session in
                    try await context.service.sendMessage(accessToken: session.accessToken, to: peerID, body: text)
                }
                let failure = Self.sendFailureNotice(response)
                guard generation == context.generation else {
                    // 서버가 받았으면(ok) 할 말이 없다. 거절됐는데 그 사이 세션이 끝났으면 다시 로그인하라고 남긴다.
                    if failure != nil { postReplyLostSession(peerID: peerID) }
                    return false
                }
                if let failure {
                    postReplyFailure(failure, peerID: peerID)
                }
            } catch {
                guard generation == context.generation else {
                    postReplyLostSession(peerID: peerID)
                    return false
                }
                if AuthErrorRules.classify(error) != .cancelled {
                    postReplyFailure(PushText.connectionUnstable, peerID: peerID)
                }
            }
        }
        guard generation == context.generation else { return false }
        let marked = await markRead(peerID: peerID, messageID: messageID)
        guard generation == context.generation else { return false }
        notifyMessagesIfActivated(peerID: peerID)
        return marked
    }

    /// 답장이 보내졌는지 모르는 채 세대가 바뀌었다(답장 안의 치명 만료 · 그 사이 로그아웃·재로그인). 로그인이 풀려 있으면 로그인 안내,
    /// 다른 세션이 이미 서 있으면(앞 세션의 알림이다) 대화를 열어 보내라는 안내.
    private func postReplyLostSession(peerID: String) {
        let body = context.session.isSignedIn ? PushText.replyMessageGone : PushText.replyNeedsSignIn
        postReplyFailure(body, peerID: peerID)
    }

    /// 보내기 결과 → 실패 문구(성공이면 nil). 맥 `WorkTimerStore.sendMessage` 의 분기와 같은 문장(코어 `MessageNoticeText`).
    package nonisolated static func sendFailureNotice(_ response: PokeSendResponse) -> String? {
        switch MessageSendOutcome(response: response) {
        case .ok: return nil
        case .notWorking: return MessageNoticeText.notWorking
        case .targetNotWorking: return MessageNoticeText.targetNotWorking
        case .targetFocused: return MessageNoticeText.targetFocused
        case .tooLong: return MessageNoticeText.tooLong(maxLength: response.maxLength)
        case .notText: return MessageNoticeText.notText
        case .blackout: return MessageNoticeText.blackout
        case .flood, .invalid: return MessageNoticeText.invalid
        }
    }

    package enum MessageVerification: Equatable, Sendable {
        case confirmed
        case notFound
        case failed
    }

    /// 지금 계정의 24시간 이력에 그 메시지가 **그 상대에게서 받은 것**으로 있는가. 읽음 칸 함수가 없는 서버면 옛 이력으로 접는다.
    private func verifyReceivedMessage(peerID: String, messageID: String) async -> MessageVerification {
        let hours = MessageNoticeText.historyHours
        let limit = MessageNoticeText.historyLimit
        do {
            let entries: [MessageHistoryEntry]
            do {
                entries = try await context.withMobileSessionRetry { session in
                    try await context.service.fetchMessageHistoryWithReads(accessToken: session.accessToken, hours: hours, limit: limit)
                }
            } catch SupabaseWorkServiceError.databaseSchemaMissing {
                entries = try await context.withMobileSessionRetry { session in
                    try await context.service.fetchMessageHistory(accessToken: session.accessToken, hours: hours, limit: limit)
                }
            }
            let found = entries.contains { entry in
                entry.id.lowercased() == messageID && !entry.isMine && entry.peerUserID.lowercased() == peerID
            }
            return found ? .confirmed : .notFound
        } catch {
            return .failed
        }
    }

    /// 읽음 경계를 **그 알림의 메시지까지** 올린다. id 가 없으면 올리지 않는다(최신까지 올리면 못 본 말까지 읽음이 된다).
    private func markRead(peerID: String, messageID: String?) async -> Bool {
        guard let messageID else { return false }
        let generation = context.generation
        do {
            let response = try await context.withMobileSessionRetry { session in
                try await context.service.markMessagesRead(accessToken: session.accessToken, peerUserID: peerID, throughMessageID: messageID)
            }
            return generation == context.generation && response.isOK
        } catch {
            return false
        }
    }

    /// 오목 신청 수락·거절 — 코어 오목 스토어로(루비·판 상태·받은 신청 목록이 한 곳에서 바뀐다).
    /// 수락이면 판이 열렸을 때 대국으로, 못 열렸으면(만료·잔액 부족 등) 그 신청 화면으로 연다(스토어 안내 한 줄이 이유를 말한다).
    private func respondInvite(matchID: String, accept: Bool) async {
        let gomoku = context.gomoku
        let generation = context.generation
        // 다른 오목 요청이 떠 있으면 스토어가 겹친 요청을 조용히 버린다 — 잠깐 기다린다.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(Int(gomokuBusyTimeoutSeconds * 1000)))
        while gomoku.isBusy, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard generation == context.generation else { return }
        guard !gomoku.isBusy else {
            if accept { context.router.open(.gomokuInvite(matchID: matchID)) }
            return
        }
        await gomoku.respond(inviteID: matchID, accept: accept)
        guard generation == context.generation, accept else { return }
        if gomoku.match?.id.lowercased() == matchID {
            context.router.open(.gomokuMatch(matchID: matchID))
        } else {
            context.router.open(.gomokuInvite(matchID: matchID))
        }
    }

    /// 답장 실패 안내 알림. 누르면 그 대화가 열린다(push-verify 발견 6 — 본문이 "앱에서 대화를 열어 보내 주세요"다):
    /// `type`=message · `peer_id` 만 싣는다. `message_id` 는 싣지 않고 카테고리도 없다(안내에서 답장·읽음을 다시 하지 않는다).
    private func postReplyFailure(_ body: String, peerID: String) {
        system?.postLocalNotice(
            identifier: PushIdentifiers.localNoticePrefix + "reply." + peerID,
            title: PushText.replyFailedTitle,
            body: body,
            threadID: "message-\(peerID)",
            userInfo: Self.replyFailureUserInfo(peerID: peerID)
        )
    }

    /// 안내 알림 본문(`PushPayload(userInfo:)` 가 `.message(peerID:, messageID: nil)` · 안내 표지로 읽는다).
    package nonisolated static func replyFailureUserInfo(peerID: String) -> [String: String] {
        ["type": PushKind.message.rawValue, "peer_id": peerID, PushIdentifiers.localNoticeKey: "1"]
    }

    // MARK: - 앱 배지

    /// 배지 관찰을 건다(한 번). 적을지는 `badgeTarget` 이 정한다 — 모르면 적지 않는다.
    private func startBadgeTracking() {
        guard !isTrackingBadges, system != nil else { return }
        isTrackingBadges = true
        observeBadges()
    }

    private func observeBadges() {
        let target = withObservationTracking {
            badgeTarget
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeBadges() }
        }
        if let target { apply(badge: target) }
    }

    /// 지금 아이콘에 적을 값. nil = 모른다(적지 않는다 — 앞 실행이 적은 값을 둔다).
    /// - 실행 복원 중 · 업데이트 필요: 계정도 숫자도 모른다.
    /// - 확정된 로그아웃: 0.
    /// - 로그인: 앱이 앞에서 서버 확인을 마친 뒤(`.stores`)에만 탭 배지 합. 뒤에서 직접 읽어 적은 값(`.server`)은 관찰로 덮지 않는다.
    private var badgeTarget: Int? {
        switch context.session.phase {
        case .signedOut:
            return 0
        case .launching, .needsUpdate:
            return nil
        case .signedIn:
            guard badgeKnowledge == .stores else { return nil }
            return max(0, badgeTotalSource())
        }
    }

    private func applyBadge() {
        if let target = badgeTarget { apply(badge: target) }
    }

    private func apply(badge total: Int) {
        guard let system, lastAppliedBadge != total else { return }
        lastAppliedBadge = total
        system.setBadgeCount(total)
    }

    /// 포그라운드 알림 뒤: 아직 서버 확인을 못 했으면(오프라인이었다) 다시 해 본다. 확인이 끝났으면 관찰이 적는다.
    private func settleBadgeInForeground() {
        guard isAppActive, badgeKnowledge != .stores else { return }
        confirmBadge()
    }

    /// 뒤에서 한 알림 액션(답장 · 읽음 · 거절)의 끝: 앱이 뒤에 있으면 서버에서 직접 읽어 적고 **끝날 때까지 기다린다**
    /// (완료 콜백 뒤 시스템이 곧 앱을 재운다). 앱이 앞이면 스토어가 새로고침했고 관찰이 적는다.
    private func settleBadgeAfterBackgroundAction() async {
        guard system != nil, context.session.isSignedIn else { return }
        if isAppActive {
            settleBadgeInForeground()
            return
        }
        await confirmBadge()?.value
    }

    /// 진행 중인 배지 확인(테스트가 기다린다).
    package var pendingBadgeConfirmation: Task<Void, Never>? { badgeConfirmTask }

    /// 서버에서 배지 재료를 읽어 앎을 세운다. 도는 중이면 뒤따르는 한 번으로 합치고 그 작업을 돌려준다(기다릴 수 있다).
    @discardableResult
    private func confirmBadge() -> Task<Void, Never>? {
        guard system != nil, context.session.isSignedIn else { return nil }
        if let running = badgeConfirmTask {
            badgeConfirmAgain = true
            return running
        }
        let generation = context.generation
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.badgeConfirmAgain = false
                await self.performBadgeConfirmation(generation: generation)
                // 세대가 바뀌었으면 reset 이 작업 칸을 이미 비웠다.
                guard generation == self.context.generation else { return }
            } while self.badgeConfirmAgain
            self.badgeConfirmTask = nil
        }
        badgeConfirmTask = task
        return task
    }

    private enum BadgeSummaryRead {
        case total(Int)
        /// 요약 함수가 없는 서버(404 PGRST202) — 서버는 답했다. 메시지 탭이 옛 이력 규칙으로 접는다.
        case serverLacksSummary
        case failed
    }

    /// 한 번의 확인.
    /// - 앱이 앞: 요약이 한 번 답하면(`.stores`) 그때부터 탭 배지 합을 적는다. 탭 스토어는 활성화 때 같은 요약을 띄웠으므로 이 응답이
    ///   올 즈음에는 합이 서버 값을 담고 있다. 실패(오프라인)면 아무것도 적지 않는다 — 다음 활성화 · 포그라운드 알림이 다시 한다.
    /// - 앱이 뒤: 요약 total + 오목 받은함을 읽은 뒤 게임 탭 배지를 더해 적는다(`.server`). 요약을 못 읽으면 적지 않는다.
    ///   메시지 몫에 요약 total 을 쓰는 이유: 이 실행의 메시지 탭은 아무것도 안 읽었고, 읽었다면 같은 요약에서 같은 수를 낸다.
    private func performBadgeConfirmation(generation: Int) async {
        guard context.session.isSignedIn else { return }
        let read: BadgeSummaryRead
        do {
            let response = try await context.withMobileSessionRetry { session in
                try await context.service.fetchMessageUnreadSummary(accessToken: session.accessToken)
            }
            read = response.summary.map { .total($0.total) } ?? .failed
        } catch SupabaseWorkServiceError.databaseSchemaMissing {
            read = .serverLacksSummary
        } catch {
            read = .failed
        }
        guard generation == context.generation, context.session.isSignedIn else { return }

        if isAppActive {
            if case .failed = read { return }
            badgeKnowledge = .stores
            applyBadge()
            return
        }

        guard case .total(let messages) = read else { return }
        await context.gomoku.loadInbox()
        guard generation == context.generation, context.session.isSignedIn else { return }
        // 기다리는 사이 앱이 앞으로 왔으면 활성화의 확인이 맡는다(탭 스토어 합을 적는다).
        guard !isAppActive else { return }
        badgeKnowledge = .server
        apply(badge: messages + max(0, context.links.games?.badgeCount ?? 0))
    }
}
