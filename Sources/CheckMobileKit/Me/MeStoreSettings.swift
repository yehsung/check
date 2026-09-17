import CheckCore
import CheckMobileShared
import Foundation

/// 설정: 공개 설정 2개(`profiles` 자기 행 PATCH — token_usage_public · minigame_public) · 알림(시스템 권한 상태 + 종류별 3토글 →
/// 세션의 `savePushPrefs` = `set_push_prefs`) · 팀 코드(`my_team_invite_code`) · 로그아웃(세션) · 버전.
///
/// 공개 토글은 맥과 같은 **낙관 반영 → 실패 시 원복**이다. 공개 설정 GET 에 딸려 오는 `focus_mode` 는 읽고 버린다(폰은 집중 모드를
/// 바꾸지 않는다 — R9 의 PATCH 경로가 여기에 없다).
extension MeStore {
    package func settingsDidAppear() {
        guard context.session.isSignedIn else { return }
        launch { [weak self] in await self?.loadSettings() }
    }

    package func settingsDidDisappear() {
        settingsNotice = nil
        pushPrefsNotice = nil
    }

    /// 공개 설정 두 칸 + 팀 코드. 셋은 독립 실패다.
    package func loadSettings() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("settings")
        let generation = context.generation
        let service = context.service
        let token = await attempt { session in
            try await service.fetchTokenUsageSettings(accessToken: session.accessToken, userID: session.userID)
        }
        guard generation == context.generation, isCurrent("settings", serial) else { return }
        if case .success(let value) = token, !isSavingPrivacy("token") {
            tokenUsagePublic = value.isPublic
            tokenUsagePublicLoaded = true
        }
        let miniGame = await attempt { session in
            try await service.fetchMiniGamePublic(accessToken: session.accessToken, userID: session.userID)
        }
        guard generation == context.generation, isCurrent("settings", serial) else { return }
        if case .success(let value) = miniGame, !isSavingPrivacy("minigame") {
            // 컬럼·행이 없으면 nil → 공개로 본다(맥 fetchMiniGamePublic 주석).
            miniGamePublic = value ?? true
            miniGamePublicLoaded = true
        }
        let code = await attempt { session in
            try await service.fetchMyInviteCode(accessToken: session.accessToken)
        }
        guard generation == context.generation, isCurrent("settings", serial) else { return }
        if case .success(let value) = code {
            inviteCode = value
            inviteCodeLoaded = true
        }
    }

    // MARK: 공개 설정

    package func setTokenUsagePublic(_ isPublic: Bool) {
        guard tokenUsagePublic != isPublic, context.session.isSignedIn else { return }
        let previous = tokenUsagePublic
        tokenUsagePublic = isPublic
        tokenUsagePublicLoaded = true
        settingsNotice = nil
        let generation = context.generation
        let service = context.service
        let serial = nextSerial("privacy.token")
        launch { [weak self] in
            guard let self else { return }
            do {
                try await self.context.withMobileSessionRetry { session in
                    try await service.updateTokenUsagePublic(accessToken: session.accessToken, userID: session.userID, isPublic: isPublic)
                }
                guard generation == self.context.generation else { return }
                self.context.links.rankings?.noteTokenUsagePublic(isPublic)
            } catch {
                guard generation == self.context.generation, self.isCurrent("privacy.token", serial) else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                self.tokenUsagePublic = previous
                self.settingsNotice = MeText.privacySaveFailed
            }
            if self.isCurrent("privacy.token", serial) { self.savingPrivacyKeys.remove("token") }
        }
        savingPrivacyKeys.insert("token")
    }

    package func setMiniGamePublic(_ isPublic: Bool) {
        guard miniGamePublic != isPublic, context.session.isSignedIn else { return }
        let previous = miniGamePublic
        miniGamePublic = isPublic
        miniGamePublicLoaded = true
        settingsNotice = nil
        let generation = context.generation
        let service = context.service
        let serial = nextSerial("privacy.minigame")
        launch { [weak self] in
            guard let self else { return }
            do {
                try await self.context.withMobileSessionRetry { session in
                    try await service.updateMiniGamePublic(accessToken: session.accessToken, userID: session.userID, isPublic: isPublic)
                }
            } catch {
                guard generation == self.context.generation, self.isCurrent("privacy.minigame", serial) else { return }
                if AuthErrorRules.classify(error) == .cancelled { return }
                self.miniGamePublic = previous
                self.settingsNotice = MeText.privacySaveFailed
            }
            if self.isCurrent("privacy.minigame", serial) { self.savingPrivacyKeys.remove("minigame") }
        }
        savingPrivacyKeys.insert("minigame")
    }

    /// 저장이 떠 있는 동안 늦게 온 GET 이 방금 바꾼 스위치를 되돌리지 않게.
    private func isSavingPrivacy(_ key: String) -> Bool {
        savingPrivacyKeys.contains(key)
    }

    // MARK: 알림

    /// iOS 어댑터(설정 화면)가 `UNUserNotificationCenter` 에서 읽은 권한 상태를 넣는다.
    package func updatePushAuthorization(_ status: MePushAuthorization) {
        if pushAuthorization != status { pushAuthorization = status }
    }

    /// 화면에 그릴 종류별 값. 저장 중이면 낙관값, 아니면 세션이 아는 서버값(register_device · set_push_prefs 응답). 모르면 nil.
    package var displayedPushPrefs: PushPrefs? {
        pushPrefsPending ?? context.session.pushPrefs
    }

    package var isSavingPushPrefs: Bool { pushPrefsPending != nil }

    /// 종류별 알림 한 칸 바꾸기. **서버값을 모르면 바꾸지 않는다** — 세 칸을 통째로 보내는 RPC 라, 모르는 칸을 기본값으로 채워 보내면
    /// 다른 기기에서 끈 알림을 되살린다. 저장이 끝날 때까지 다음 토글은 막는다(뷰가 비활성).
    package func setPushPref(_ keyPath: WritableKeyPath<PushPrefs, Bool>, to value: Bool) {
        guard context.session.isSignedIn, pushPrefsPending == nil, var next = context.session.pushPrefs else { return }
        guard next[keyPath: keyPath] != value else { return }
        next[keyPath: keyPath] = value
        pushPrefsPending = next
        pushPrefsNotice = nil
        let generation = context.generation
        let session = context.session
        launch { [weak self] in
            guard let self else { return }
            do {
                let saved = try await session.savePushPrefs(next)
                guard generation == self.context.generation else { return }
                if saved == nil { self.pushPrefsNotice = MeText.pushPrefsSaveFailed }
            } catch {
                guard generation == self.context.generation else { return }
                if AuthErrorRules.classify(error) != .cancelled {
                    self.pushPrefsNotice = MeText.pushPrefsSaveFailed
                }
            }
            self.pushPrefsPending = nil
        }
    }

    // MARK: 계정

    package func signOut() async {
        guard context.session.isSignedIn, !isSigningOut else { return }
        isSigningOut = true
        await context.session.signOut()
        // 세션이 세대를 올리며 앱 모델이 reset() 을 불렀다 — 깃발은 거기서 이미 내려갔다.
        isSigningOut = false
    }

    package var versionLine: String {
        MeText.versionLine(version: context.appInfo.version, build: context.appInfo.build)
    }
}
