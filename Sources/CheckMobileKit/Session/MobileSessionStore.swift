import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 세션 단계(SPEC-ios §2). 화면은 이 값 하나로 로그인·업데이트 필요·탭을 가른다.
package enum MobileSessionPhase: Equatable, Sendable {
    /// 실행 직후(client_release · 키체인 복원 · 만료 토큰 갱신 중).
    case launching
    /// 이 빌드가 서버 최소 빌드보다 낮다 — TestFlight 로 보낸다.
    case needsUpdate(minBuild: Int)
    case signedOut
    case signedIn
}

/// 로그인한 사람의 최소 정보. 탭이 더 필요한 것은 각자 읽는다(이름·아바타·센터는 지금/나 탭 몫).
package struct MobileProfile: Equatable, Sendable {
    package var userID: String
    package var email: String?
    package var teamID: String?
    package var teamName: String?
    package var teamGoalHours: Int?
    package var teamRole: String?

    package init(userID: String, email: String?, teamID: String? = nil, teamName: String? = nil, teamGoalHours: Int? = nil, teamRole: String? = nil) {
        self.userID = userID
        self.email = email
        self.teamID = teamID
        self.teamName = teamName
        self.teamGoalHours = teamGoalHours
        self.teamRole = teamRole
    }
}

/// register_device 를 부르는 이유. 로그인 직후는 스로틀을 무시하고, 포그라운드는 1시간 스로틀, APNs 토큰이 바뀌면 즉시.
package enum DeviceRegistrationReason: Equatable, Sendable {
    case signIn
    case foreground
    case apnsTokenChanged
}

/// 폰 세션의 **유일한 주인**(SPEC-ios §2 전부).
///
/// 지키는 것
/// - 갱신 주체는 이 스토어의 `SessionRefreshCoordinator` 하나다(401 재시도 · 실행 직후 만료 토큰 · 실시간 선제 갱신이 모두 같은 문).
///   위젯은 갱신하지 않는다(R5 — 두 프로세스가 refresh token 을 돌리면 GoTrue 재사용 감지로 강제 로그아웃).
/// - **치명 오류만 로그아웃**한다(`AuthErrorRules.classify` — 맥과 같은 판정). 네트워크·5xx·429 는 세션을 유지한다.
/// - 세대(`generation`)는 로그아웃·치명 만료 때 오른다. 모든 스토어가 응답을 적용하기 전에 캡처한 세대와 비교한다.
/// - 이 스토어는 **폰 금지 호출을 하지 않는다**: app_build PATCH·ultra_wallet_sync·캐릭터 밀어넣기·근무 루프 없음
///   (맥 `completeSignIn` 이 하던 일은 하나도 가져오지 않았다 — ios-inventory R1·R8·R10).
@MainActor
@Observable
package final class MobileSessionStore {
    package private(set) var phase: MobileSessionPhase = .launching
    package private(set) var session: SupabaseSession?
    package private(set) var profile: MobileProfile?
    /// 로그아웃·치명 만료마다 +1. 늦게 도착한 응답을 버리는 기준.
    package private(set) var generation = 0
    /// 로그인 화면 한 줄(실패 원인 · "다시 로그인 필요").
    package var notice: String?
    package private(set) var isSigningIn = false
    /// 마지막으로 받은 알림 설정(register_device 응답). 나 탭 설정 화면이 읽는다.
    package private(set) var pushPrefs: PushPrefs?
    /// 서버가 알려 준 최신 빌드(업데이트 안내 — 최소 빌드 이상이면 막지는 않는다).
    package private(set) var latestBuild: Int?

    @ObservationIgnored package let service: SupabaseWorkService
    @ObservationIgnored package let appInfo: MobileAppInfo
    @ObservationIgnored package let storage: AingSharedStorage
    @ObservationIgnored package let installationID: String
    @ObservationIgnored private let vault: TokenVault
    @ObservationIgnored private let clock: MobileClock
    @ObservationIgnored package let refreshCoordinator = SessionRefreshCoordinator()

    /// 위젯 타임라인 새로고침(iOS 조립이 `WidgetCenter.reloadAllTimelines` 를 넣는다). 로그아웃 뒤 부른다.
    @ObservationIgnored package var reloadWidgetTimelines: @MainActor () -> Void = {}
    /// 로그인 상태가 된 순간(실행 복원 포함). 앱 모델이 실시간·탭 스토어를 깨운다.
    @ObservationIgnored package var onSignedIn: (@MainActor () -> Void)?
    /// 로그아웃·치명 만료로 세대가 바뀐 순간. 앱 모델이 모든 스토어를 `reset()` 한다.
    @ObservationIgnored package var onSignedOut: (@MainActor () -> Void)?
    /// 토큰이 갱신된 순간(어느 경로든). 실시간 러너가 채널에 새 토큰을 민다.
    @ObservationIgnored package var onAccessTokenChanged: (@MainActor (String) -> Void)?

    /// 1시간 스로틀(SPEC-ios §2).
    package nonisolated static let deviceRegistrationThrottleSeconds: TimeInterval = 3600
    /// 실행 직후 이 초 안에 만료되는 토큰은 먼저 갱신한다.
    package nonisolated static let launchRefreshLeadSeconds: TimeInterval = 60

    @ObservationIgnored private var registrationTask: Task<Void, Never>?
    @ObservationIgnored private var registrationQueued: DeviceRegistrationReason?

    package init(
        service: SupabaseWorkService,
        vault: TokenVault,
        storage: AingSharedStorage,
        appInfo: MobileAppInfo,
        installationID: String,
        clock: MobileClock
    ) {
        self.service = service
        self.vault = vault
        self.storage = storage
        self.appInfo = appInfo
        self.installationID = installationID
        self.clock = clock
    }

    package var isSignedIn: Bool { phase == .signedIn && session != nil }
    package var userID: String? { session?.userID }
    /// 마지막으로 받은 APNs 토큰(hex 소문자). 실행 사이에 공용 suite 에 남는다.
    package var apnsToken: String? { storage.defaults.string(forKey: AingSharedKeys.apnsToken) }

    // MARK: - 실행

    /// 실행 순서: client_release(anon) → 빌드 < 최소면 업데이트 화면 → 키체인 복원 → 곧 만료면 갱신 → 로그인 상태.
    package func launch() async {
        phase = .launching
        let startGeneration = generation

        do {
            let release = try await service.fetchClientRelease()
            guard startGeneration == generation else { return }
            latestBuild = release.latestBuild
            if release.status == "ok", let minBuild = release.minBuild, appInfo.build < minBuild {
                phase = .needsUpdate(minBuild: minBuild)
                return
            }
        } catch {
            // 함수가 없는 서버·네트워크 실패는 **막지 않는다**. 모르는 채로 사람을 가두는 편이 더 나쁘다
            // (최소 빌드 검사는 서버가 기능을 바꿀 때를 위한 안전장치이지, 로그인의 조건이 아니다).
        }
        guard startGeneration == generation else { return }

        guard let restored = restoredSession() else {
            phase = .signedOut
            return
        }
        session = restored

        if let expiry = JWTClaims.expiry(accessToken: restored.accessToken),
           expiry.timeIntervalSince(clock.now()) < Self.launchRefreshLeadSeconds {
            do {
                _ = try await refreshViaCoordinator(generation: generation)
            } catch {
                guard startGeneration == generation else { return }
                switch AuthErrorRules.classify(error) {
                case .fatal:
                    expireSession(message: AuthErrorRules.message(for: error, fallback: "다시 로그인 필요"))
                    return
                case .cancelled, .transient:
                    // 세션을 유지한다 — 다음 요청의 401 재시도가 다시 갱신한다(비행기 모드로 켠 폰이 로그아웃되지 않게).
                    break
                }
            }
        }
        guard startGeneration == generation, session != nil else { return }
        enterSignedIn()
    }

    // MARK: - 로그인 · 로그아웃

    package func signIn(email: String, password: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            notice = MobileSessionText.missingCredentials
            return
        }
        guard !isSigningIn else { return }
        isSigningIn = true
        notice = nil
        let startGeneration = generation
        defer { isSigningIn = false }
        do {
            let signedIn = try await service.signIn(email: trimmedEmail, password: password)
            guard startGeneration == generation else { return }
            persist(signedIn)
            storage.defaults.set(trimmedEmail, forKey: AingSharedKeys.email)
            session = signedIn
            enterSignedIn(registrationReason: .signIn)
        } catch {
            guard startGeneration == generation else { return }
            switch AuthErrorRules.classify(error) {
            case .cancelled:
                return
            case .transient:
                notice = MobileSessionText.network
            case .fatal:
                notice = AuthErrorRules.message(for: error, fallback: MobileSessionText.signInFailed)
            }
        }
    }

    /// 로그아웃(SPEC-ios §2): 세대를 올리고 **로컬을 먼저 비운 뒤** 서버에 unregister_device → logout?scope=local 순서로 알린다.
    ///
    /// 로컬을 먼저 비우는 이유: 두 요청을 기다리는 동안 화면은 이미 로그인 화면이어야 하고, 그 사이에 다시 로그인하면
    /// 늦게 끝난 정리가 **새 계정의 키체인을 지우는** 창이 생긴다. 서버 요청은 캡처한 토큰으로 나가므로 순서만 지키면 된다.
    package func signOut() async {
        guard let current = session else {
            phase = .signedOut
            return
        }
        generation += 1
        refreshCoordinator.invalidate()
        registrationTask?.cancel()
        registrationTask = nil
        registrationQueued = nil
        clearLocalUserData()
        session = nil
        profile = nil
        pushPrefs = nil
        notice = nil
        phase = .signedOut
        onSignedOut?()

        // 서버 정리 — 실패는 삼킨다(토큰이 이미 죽었어도 로컬은 이미 비었다).
        _ = try? await service.unregisterDevice(accessToken: current.accessToken, installationID: installationID)
        await service.signOut(accessToken: current.accessToken)
    }

    /// 치명 만료(refresh token 무효 등). 서버에 알릴 토큰이 없으므로 로컬만 정리한다.
    package func expireSession(message: String = MobileSessionText.signInAgain) {
        guard session != nil || phase == .signedIn else { return }
        generation += 1
        refreshCoordinator.invalidate()
        registrationTask?.cancel()
        registrationTask = nil
        registrationQueued = nil
        clearLocalUserData()
        session = nil
        profile = nil
        pushPrefs = nil
        notice = message
        phase = .signedOut
        onSignedOut?()
    }

    // MARK: - 401 재시도

    /// 맥 `withSessionRetry` 와 같은 모양: 세션 가드 → 세대 캡처 → 호출 → `.sessionExpired` 면 조정자 경유 갱신 1회 → 재시도.
    /// 갱신이 **치명**으로 실패할 때만 로그아웃하고, 일시 실패면 세션을 유지한 채 원래 오류를 던진다.
    package func withMobileSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let current = session else {
            throw SupabaseWorkServiceError.sessionExpired
        }
        let startGeneration = generation
        do {
            return try await operation(current)
        } catch let originalError as SupabaseWorkServiceError where originalError == .sessionExpired {
            guard startGeneration == generation else { throw originalError }
            guard current.refreshToken != nil else {
                expireSession()
                throw originalError
            }
            let refreshed: SupabaseSession
            do {
                refreshed = try await refreshViaCoordinator(generation: startGeneration)
            } catch {
                guard startGeneration == generation else { throw originalError }
                if AuthErrorRules.classify(error) == .fatal {
                    expireSession()
                }
                throw originalError
            }
            guard startGeneration == generation else { throw originalError }
            return try await operation(refreshed)
        }
    }

    /// 실시간 선제·강제 갱신. 성공하면 새 access token, 실패하면 (fatal 여부) — fatal 이면 세션도 여기서 만료시킨다.
    package func refreshForRealtime() async -> Result<String, RealtimeRefreshFailure> {
        guard session?.refreshToken != nil else { return .failure(RealtimeRefreshFailure(fatal: session == nil)) }
        let startGeneration = generation
        do {
            let refreshed = try await refreshViaCoordinator(generation: startGeneration)
            guard startGeneration == generation else { return .failure(RealtimeRefreshFailure(fatal: true)) }
            return .success(refreshed.accessToken)
        } catch {
            guard startGeneration == generation else { return .failure(RealtimeRefreshFailure(fatal: true)) }
            switch AuthErrorRules.classify(error) {
            case .fatal:
                expireSession()
                return .failure(RealtimeRefreshFailure(fatal: true))
            case .cancelled, .transient:
                return .failure(RealtimeRefreshFailure(fatal: false))
            }
        }
    }

    package struct RealtimeRefreshFailure: Error, Equatable {
        package let fatal: Bool
    }

    private func refreshViaCoordinator(generation startGeneration: Int) async throws -> SupabaseSession {
        try await refreshCoordinator.refresh(
            generation: startGeneration,
            // 호출 시점에 읽는다 — 합류하지 못한 순차 호출이 이미 회전된 옛 토큰을 재사용하지 않게(조정자 주석 ①).
            tokenProvider: { [weak self] in self?.session?.refreshToken },
            refresh: { [service] token in try await service.refreshSession(refreshToken: token) },
            apply: { [weak self] refreshed in
                guard let self, startGeneration == self.generation else { return }
                self.session = refreshed
                self.persist(refreshed)
                self.onAccessTokenChanged?(refreshed.accessToken)
            }
        )
    }

    // MARK: - 기기 등록

    /// 포그라운드 진입. 로그인 상태면 1시간 스로틀로 register_device.
    package func appDidBecomeActive() {
        guard isSignedIn else { return }
        requestDeviceRegistration(.foreground)
    }

    /// APNs 토큰(hex 소문자)이 새로 왔다(푸시 코디네이터가 부른다). 값이 바뀌었으면 즉시 등록한다.
    package func updateAPNsToken(_ hex: String?) {
        let normalized = hex?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = normalized.flatMap { $0.range(of: "^[0-9a-f]{32,200}$", options: .regularExpression) != nil ? $0 : nil }
        guard valid != apnsToken else { return }
        if let valid {
            storage.defaults.set(valid, forKey: AingSharedKeys.apnsToken)
        } else {
            storage.defaults.removeObject(forKey: AingSharedKeys.apnsToken)
        }
        guard isSignedIn else { return }
        requestDeviceRegistration(.apnsTokenChanged)
    }

    /// 등록 요청. 진행 중이면 한 번만 줄 세운다(연달아 온 사건이 요청을 쌓지 않게).
    package func requestDeviceRegistration(_ reason: DeviceRegistrationReason) {
        guard isSignedIn else { return }
        if registrationTask != nil {
            // 로그인·토큰 변경은 스로틀을 무시해야 하므로 더 강한 이유가 이긴다.
            if registrationQueued == nil || reason != .foreground { registrationQueued = reason }
            return
        }
        registrationTask = Task { [weak self] in
            await self?.performDeviceRegistration(reason)
            guard let self else { return }
            self.registrationTask = nil
            if let queued = self.registrationQueued {
                self.registrationQueued = nil
                self.requestDeviceRegistration(queued)
            }
        }
    }

    /// 테스트가 기다릴 수 있게 진행 중 등록을 돌려준다.
    package var pendingDeviceRegistration: Task<Void, Never>? { registrationTask }

    private func registrationSignature(userID: String) -> String {
        [userID, String(appInfo.build), appInfo.version, apnsToken ?? "-", appInfo.apnsEnvironment ?? "-"].joined(separator: "|")
    }

    private func performDeviceRegistration(_ reason: DeviceRegistrationReason) async {
        guard let current = session else { return }
        let defaults = storage.defaults
        let signature = registrationSignature(userID: current.userID)
        let now = clock.now()
        if reason == .foreground,
           defaults.string(forKey: AingSharedKeys.deviceRegisteredSignature) == signature,
           let last = defaults.object(forKey: AingSharedKeys.deviceRegisteredAt) as? Date,
           now.timeIntervalSince(last) < Self.deviceRegistrationThrottleSeconds,
           now >= last {
            return
        }
        let startGeneration = generation
        let token = apnsToken
        let env = appInfo.apnsEnvironment
        do {
            let response = try await withMobileSessionRetry { [service, installationID, appInfo] session in
                try await service.registerDevice(
                    accessToken: session.accessToken,
                    installationID: installationID,
                    appBuild: appInfo.build,
                    appVersion: appInfo.version,
                    apnsToken: token,
                    apnsEnvironment: env
                )
            }
            guard startGeneration == generation else { return }
            if response.status == "ok" {
                defaults.set(now, forKey: AingSharedKeys.deviceRegisteredAt)
                defaults.set(signature, forKey: AingSharedKeys.deviceRegisteredSignature)
                if let prefs = response.pushPrefs { pushPrefs = prefs }
            }
        } catch {
            // 함수가 없는 서버·일시 실패는 조용히 — 다음 포그라운드가 다시 시도한다(스탬프를 안 찍었으므로).
        }
    }

    /// 알림 설정 저장(나 탭 → PushCoordinator 공개 API 가 부른다). 성공하면 새 설정.
    package func savePushPrefs(_ prefs: PushPrefs) async throws -> PushPrefs? {
        let startGeneration = generation
        let response = try await withMobileSessionRetry { [service, installationID] session in
            try await service.setPushPrefs(accessToken: session.accessToken, installationID: installationID, prefs: prefs)
        }
        guard startGeneration == generation else { return nil }
        if response.status == "ok", let saved = response.pushPrefs {
            pushPrefs = saved
            return saved
        }
        return nil
    }

    // MARK: - 프로필

    /// 팀 소속을 읽어 프로필을 채운다(읽기만). 실패는 조용히 — 탭이 다시 부를 수 있다.
    package func refreshProfile() async {
        guard let current = session else { return }
        let startGeneration = generation
        do {
            let membership = try await withMobileSessionRetry { [service] session in
                try await service.fetchOwnMembership(accessToken: session.accessToken, userID: session.userID)
            }
            guard startGeneration == generation else { return }
            var next = profile ?? MobileProfile(userID: current.userID, email: storedEmail)
            next.teamID = membership?.teamID
            next.teamName = membership?.teamName
            next.teamGoalHours = membership?.goalHours
            next.teamRole = membership?.role
            profile = next
        } catch {
            // 조용히.
        }
    }

    // MARK: - 저장

    package var storedEmail: String? { storage.defaults.string(forKey: AingSharedKeys.email) }

    private func enterSignedIn(registrationReason: DeviceRegistrationReason = .foreground) {
        guard let current = session else { return }
        if profile?.userID != current.userID {
            profile = MobileProfile(userID: current.userID, email: storedEmail)
        }
        notice = nil
        phase = .signedIn
        onSignedIn?()
        requestDeviceRegistration(registrationReason)
        Task { [weak self] in await self?.refreshProfile() }
    }

    private func restoredSession() -> SupabaseSession? {
        guard let userID = storage.defaults.string(forKey: AingSharedKeys.userID), !userID.isEmpty,
              let access = vault.read(AingKeychain.accessTokenKey), !access.isEmpty
        else { return nil }
        let refresh = vault.read(AingKeychain.refreshTokenKey)
        return SupabaseSession(accessToken: access, refreshToken: refresh, userID: userID)
    }

    private func persist(_ session: SupabaseSession) {
        vault.write(session.accessToken, key: AingKeychain.accessTokenKey)
        if let refresh = session.refreshToken {
            vault.write(refresh, key: AingKeychain.refreshTokenKey)
        } else {
            vault.delete(AingKeychain.refreshTokenKey)
        }
        storage.defaults.set(session.userID, forKey: AingSharedKeys.userID)
    }

    /// 키체인 토큰 · 공용 suite 의 사용자 키 · 위젯 스냅샷을 지우고 위젯을 새로 그리게 한다.
    /// 할 일 파일(`todos.<uid>.json`)은 남긴다 — 사용자별 파일이고 아직 못 올린 변경이 들어 있을 수 있다(맥과 같은 관용).
    /// 위젯은 userID 키가 없으면 할 일을 그리지 않는다.
    private func clearLocalUserData() {
        vault.delete(AingKeychain.accessTokenKey)
        vault.delete(AingKeychain.refreshTokenKey)
        for key in AingSharedKeys.userScopedKeys {
            storage.defaults.removeObject(forKey: key)
        }
        WidgetSnapshotCodec.remove(at: storage.widgetSnapshotURL)
        reloadWidgetTimelines()
    }
}

/// 세션 화면 문구. 맥과 뜻이 같은 것은 코어 `AuthErrorRules` 의 문장을 그대로 쓴다.
package enum MobileSessionText {
    package static let missingCredentials = "이메일과 비밀번호를 입력해 주세요"
    package static let signInFailed = "로그인 실패"
    package static let signInAgain = "다시 로그인 필요"
    package static let network = "네트워크를 확인하고 다시 시도해 주세요"
    package static let signUpOnMac = "가입은 맥 앱에서 해요"
    package static let passwordResetOnMac = "비밀번호를 잊었다면 맥 앱의 로그인 화면에서 재설정해 주세요"
    package static let updateTitle = "새 버전이 필요해요"
    package static let updateBody = "이 버전은 더 이상 서버와 맞지 않아요. TestFlight 에서 최신 버전으로 업데이트해 주세요."
    package static let updateButton = "TestFlight 열기"
    /// TestFlight 앱 열기(설치돼 있지 않으면 시스템이 아무것도 하지 않는다).
    package static let testFlightURL = URL(string: "itms-beta://")!
}
