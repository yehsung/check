import CheckCore
import CheckMobileShared
import Foundation

/// 설정: 공개 설정 2개(`profiles` 자기 행 PATCH — token_usage_public · minigame_public) · 알림(**푸시 코디네이터 공개 API 하나** —
/// 시스템 권한 상태 · 권한 요청 · 종류별 3토글 → 직렬화된 `set_push_prefs`) · 화면 모드(기기 설정 — 서버 없음) · 팀 코드(`my_team_invite_code`) ·
/// 로그아웃(세션) · 버전.
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
        context.links.push?.prefsNotice = nil
    }

    /// 공개 설정 두 칸 + 팀 코드. 셋은 독립 실패다.
    ///
    /// 공개 설정은 **떠날 때 찍은 표**(`privacyReadStamp`)가 그대로일 때만 스위치에 옮긴다 — 저장 중에 도착한 응답도, 저장이 끝난 뒤
    /// 도착한 옛 응답도 방금 바꾼 스위치를 되돌리지 않는다. 실패는 칸마다 깃발로 남겨 화면이 '불러오는 중…'·죽은 스위치에 머물지 않고
    /// 원인과 [다시 시도]를 말한다(SPEC-ios §0.5 · rankme-verify 낮음 3).
    package func loadSettings() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("settings")
        let generation = context.generation
        let service = context.service
        isLoadingSettings = true
        tokenUsagePublicLoadFailed = false
        miniGamePublicLoadFailed = false
        inviteCodeLoadFailed = false
        defer { if isCurrent("settings", serial) { isLoadingSettings = false } }

        let tokenStamp = privacyReadStamp("token")
        let token = await attempt { session in
            try await service.fetchTokenUsageSettings(accessToken: session.accessToken, userID: session.userID)
        }
        guard generation == context.generation, isCurrent("settings", serial) else { return }
        switch token {
        case .success(let value):
            if canApplyPrivacyRead("token", stamp: tokenStamp) {
                tokenUsagePublic = value.isPublic
                tokenUsagePublicLoaded = true
            }
        case .failure(let error):
            if AuthErrorRules.classify(error) == .cancelled { return }
            tokenUsagePublicLoadFailed = true
        }

        let miniGameStamp = privacyReadStamp("minigame")
        let miniGame = await attempt { session in
            try await service.fetchMiniGamePublic(accessToken: session.accessToken, userID: session.userID)
        }
        guard generation == context.generation, isCurrent("settings", serial) else { return }
        switch miniGame {
        case .success(let value):
            if canApplyPrivacyRead("minigame", stamp: miniGameStamp) {
                // 컬럼·행이 없으면 nil → 공개로 본다(맥 fetchMiniGamePublic 주석).
                miniGamePublic = value ?? true
                miniGamePublicLoaded = true
            }
        case .failure(let error):
            if AuthErrorRules.classify(error) == .cancelled { return }
            miniGamePublicLoadFailed = true
        }

        let code = await attempt { session in
            try await service.fetchMyInviteCode(accessToken: session.accessToken)
        }
        guard generation == context.generation, isCurrent("settings", serial) else { return }
        switch code {
        case .success(let value):
            inviteCode = value
            inviteCodeLoaded = true
        case .failure(let error):
            if AuthErrorRules.classify(error) == .cancelled { return }
            inviteCodeLoadFailed = true
        }
    }

    /// 공개 설정을 **아직 한 번도** 못 읽었고 마지막 조회가 실패했다(스위치가 죽어 있는 이유를 말한다).
    package var privacyLoadFailed: Bool {
        (tokenUsagePublicLoadFailed && !tokenUsagePublicLoaded) || (miniGamePublicLoadFailed && !miniGamePublicLoaded)
    }

    /// 팀 코드를 아직 못 읽었고 마지막 조회가 실패했다.
    package var inviteCodeFailed: Bool {
        inviteCodeLoadFailed && !inviteCodeLoaded
    }

    /// [다시 시도] — 떠 있는 조회가 있으면 새로 내지 않는다. 누르는 즉시 '불러오는 중'으로 바꿔 연타가 요청을 겹치지 않게 한다.
    package func retrySettings() {
        guard context.session.isSignedIn, !isLoadingSettings else { return }
        isLoadingSettings = true
        launch { [weak self] in await self?.loadSettings() }
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

    // MARK: 알림

    /// 알림 설정의 유일한 구현(푸시 코디네이터). 권한 상태 · 권한 요청 · 종류별 저장(직렬) · 저장 실패 문구를 모두 거기서 읽고 부른다 —
    /// 나 탭은 따로 저장하지 않는다(예전 `session.savePushPrefs` 직접 저장은 통합에서 걷어냈다). 앱 모델이 만든 뒤에만 채워진다.
    package var push: PushCoordinator? { context.links.push }

    // MARK: 화면 모드

    /// 화면 모드(기기 설정 — `context.appearance`). 계정 값이 아니라 `reset()` 이 건드리지 않고, 서버 요청도 없다.
    package var appearanceMode: MobileAppearanceMode { context.appearance.mode }

    /// 고르는 즉시 저장하고 앱 전체(모든 창)에 건다 — 재실행 없음.
    package func selectAppearance(_ mode: MobileAppearanceMode) {
        context.appearance.select(mode)
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
