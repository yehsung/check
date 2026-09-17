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
/// 3. **응답**(앱 프로세스 — 401 이면 세션 조정자 경유 갱신 허용): 탭 → 라우트 · 답장 → send_message + mark_messages_read ·
///    읽음 → mark · 수락 → gomoku_respond(accept) 후 대국 열기 · 거절 → gomoku_respond(decline).
///    알림 액션으로 앱이 깨어났으면 실행 복원(`.launching`)이 끝날 때까지 기다린다.
/// 4. **앱 배지** = 메시지 안 읽은 수 + 받은 오목 신청 수(`context.links.badges.appBadgeTotal`)를 관찰해 바뀔 때마다 적는다.
/// 5. **알림 설정 공개 API**(나 탭): `authorization` · `prefs` · `setPreference(_:enabled:)` · `enableNotifications()` ·
///    `refreshAuthorization()` · `openSystemSettings()`.
///
/// 폰 금지 호출 없음: 이 파일이 부르는 서버 함수는 send_message · mark_messages_read · message_history(_with_reads) ·
/// gomoku_respond(오목 스토어 경유) · register_device/set_push_prefs(세션 경유)뿐이다.
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
    @ObservationIgnored private var pendingPrefs: PushPrefs?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var statusCheckAgain = false
    @ObservationIgnored private var statusCheckWantsPrimer = false
    @ObservationIgnored private var isTrackingBadges = false
    @ObservationIgnored package private(set) var lastAppliedBadge: Int?
    /// 마지막 원격 등록 실패(진단). 시뮬레이터 · 엔타이틀먼트 없는 빌드에서 온다.
    @ObservationIgnored package private(set) var lastRegistrationError: String?

    #if DEBUG
    /// 데모: 권한 상태와 무관하게 로그인 뒤 설명 시트를 한 번 띄운다(`-AingCheckDemoPushPrimer YES`).
    @ObservationIgnored package var demoForcesPrimer = false
    #endif

    /// 앱 배지 합의 출처(기본: 메시지 · 게임 탭 배지 합). 관찰 가능한 값을 읽어야 한다 — 바뀌면 다시 적는다. 테스트가 바꾼다.
    @ObservationIgnored package var badgeTotalSource: @MainActor () -> Int

    package init(context: MobileContext) {
        self.context = context
        let links = context.links
        badgeTotalSource = { [weak links] in links?.badges.appBadgeTotal ?? 0 }
    }

    /// iOS 어댑터를 붙인다(앱 델리게이트 didFinishLaunching — `MobileAppModel.installPushNotifications()`).
    package func attach(system: PushNotificationSystem) {
        self.system = system
        startBadgeTracking()
    }

    // MARK: - 수명

    package func appDidBecomeActive() {
        isAppActive = true
        startBadgeTracking()
        applyBadge()
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
        pendingPrefs = nil
        isSavingPrefs = false
        prefsNotice = nil
        applyBadge()
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

    /// 지금 보여 줄 종류별 설정. 저장 중이면 누른 값, 아니면 서버가 마지막으로 알려 준 값(모르면 전부 켜짐 — 서버 기본값).
    package var prefs: PushPrefs {
        pendingPrefs ?? context.session.pushPrefs ?? PushPrefs()
    }

    package func isEnabled(_ kind: PushKind) -> Bool {
        kind.isEnabled(in: prefs)
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
    @discardableResult
    package func setPreference(_ kind: PushKind, enabled: Bool) async -> Bool {
        guard context.session.isSignedIn else { return false }
        let generation = context.generation
        let next = kind.setting(enabled, in: prefs)
        pendingPrefs = next
        isSavingPrefs = true
        prefsNotice = nil
        defer {
            if generation == context.generation {
                pendingPrefs = nil
                isSavingPrefs = false
            }
        }
        for attempt in 0..<2 {
            do {
                if try await context.session.savePushPrefs(next) != nil { return true }
            } catch {
                guard generation == context.generation else { return false }
                if AuthErrorRules.classify(error) != .cancelled { prefsNotice = PushText.settingsSaveFailed }
                return false
            }
            guard generation == context.generation else { return false }
            guard attempt == 0 else { break }
            // not_found: 기기 행이 없다(첫 등록이 실패했거나 아직 안 끝났다) — 등록을 끝까지 기다린 뒤 한 번 더.
            context.session.requestDeviceRegistration(.signIn)
            await context.session.pendingDeviceRegistration?.value
            guard generation == context.generation else { return false }
        }
        prefsNotice = PushText.settingsSaveFailed
        return false
    }

    // MARK: - 포그라운드 표시

    /// 앱이 앞에 있을 때 알림이 왔다(`willPresent`). 해당 스토어를 새로고침하고 보일지 정한다.
    package func presentation(for payload: PushPayload?) -> PushPresentation {
        guard let payload else { return .banner }
        guard context.session.isSignedIn else { return .banner }
        refreshStores(for: payload)
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

    /// 제네릭으로 부른다 — 증인 테이블을 지나 메시지 탭의 같은 이름 메서드(있으면)가 불린다.
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
            context.router.open(payload.route)
            refreshStores(for: payload)
        case (.reply(let text), .message(let peer, let messageID)):
            await reply(text: text, peerID: peer, messageID: messageID)
        case (.markRead, .message(let peer, let messageID)):
            if await markRead(peerID: peer, messageID: messageID) {
                notifyMessages(peerID: peer)
            }
        case (.acceptInvite, .gomokuInvite(let match)):
            await respondInvite(matchID: match, accept: true)
        case (.declineInvite, .gomokuInvite(let match)):
            await respondInvite(matchID: match, accept: false)
        default:
            // 카테고리와 맞지 않는 액션(서버·앱 버전이 어긋난 경우) — 아무것도 하지 않는다.
            break
        }
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
    private func reply(text: String, peerID: String, messageID: String?) async {
        let generation = context.generation
        guard let messageID else {
            postReplyFailure(PushText.replyMessageGone, peerID: peerID)
            return
        }
        switch await verifyReceivedMessage(peerID: peerID, messageID: messageID) {
        case .confirmed:
            break
        case .notFound:
            guard generation == context.generation else { return }
            postReplyFailure(PushText.replyMessageGone, peerID: peerID)
            return
        case .failed:
            guard generation == context.generation else { return }
            postReplyFailure(PushText.connectionUnstable, peerID: peerID)
            return
        }
        guard generation == context.generation else { return }

        if case .empty = MessageBody.validate(text) {
            // 빈 답장은 보내지 않는다(서버 왕복 없이 invalid) — 읽음만.
        } else {
            do {
                let response = try await context.withMobileSessionRetry { session in
                    try await context.service.sendMessage(accessToken: session.accessToken, to: peerID, body: text)
                }
                guard generation == context.generation else { return }
                if let failure = Self.sendFailureNotice(response) {
                    postReplyFailure(failure, peerID: peerID)
                }
            } catch {
                guard generation == context.generation else { return }
                if AuthErrorRules.classify(error) != .cancelled {
                    postReplyFailure(PushText.connectionUnstable, peerID: peerID)
                }
            }
        }
        guard generation == context.generation else { return }
        _ = await markRead(peerID: peerID, messageID: messageID)
        guard generation == context.generation else { return }
        notifyMessages(peerID: peerID)
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

    private func postReplyFailure(_ body: String, peerID: String) {
        system?.postLocalNotice(
            identifier: PushIdentifiers.localNoticePrefix + "reply." + peerID,
            title: PushText.replyFailedTitle,
            body: body,
            threadID: "message-\(peerID)"
        )
    }

    // MARK: - 앱 배지

    /// 메시지·게임 배지 합을 관찰해 바뀔 때마다 아이콘에 적는다(로그아웃이면 0).
    private func startBadgeTracking() {
        guard !isTrackingBadges, system != nil else { return }
        isTrackingBadges = true
        observeBadges()
    }

    private func observeBadges() {
        let total = withObservationTracking {
            currentBadgeTotal
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeBadges() }
        }
        apply(badge: total)
    }

    private var currentBadgeTotal: Int {
        context.session.isSignedIn ? max(0, badgeTotalSource()) : 0
    }

    private func applyBadge() {
        apply(badge: currentBadgeTotal)
    }

    private func apply(badge total: Int) {
        guard let system, lastAppliedBadge != total else { return }
        lastAppliedBadge = total
        system.setBadgeCount(total)
    }
}
