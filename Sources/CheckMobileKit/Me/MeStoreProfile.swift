import CheckCore
import CheckMobileShared
import Foundation

/// 프로필 편집: 사진(`storage` 업로드 + `profiles.avatar_url` PATCH — 코어 `uploadAvatar`) · 별명(`set_display_name`, 12자 · 7일 쿨타임).
///
/// 맥은 성공 뒤 `refreshTeamStatus()` 를 부르는데 그 반영 경로가 근무 세션 쓰기(R2)로 이어진다 — 폰은 머리만 서버 응답으로 바꾼다.
extension MeStore {
    package static var displayNameMaxLength: Int { CheckCoreShared.displayNameMaxLength }

    /// 편집 화면을 열 때: 지금 이름으로 입력을 채우고, 쿨타임 기준 시각을 다시 읽는다.
    package func profileDidAppear() {
        isProfileVisible = true
        if displayNameDraft.isEmpty, let displayName { displayNameDraft = displayName }
        refreshDisplayNameLockNotice()
        guard context.session.isSignedIn else { return }
        launch { [weak self] in await self?.loadDisplayNameCooldown() }
    }

    package func profileDidDisappear() {
        isProfileVisible = false
        displayNameDraft = ""
        if !isUpdatingDisplayName {
            displayNameNotice = nil
            isDisplayNameNoticeError = false
        }
        if !isUploadingAvatar { avatarNotice = nil }
    }

    package func loadDisplayNameCooldown() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("nameCooldown")
        let generation = context.generation
        let service = context.service
        // 컬럼이 없는 서버·네트워크 실패는 조용히(맥과 같다 — 서버가 set_display_name 에서 어차피 거른다).
        guard case .success(let changedAt) = await attempt({ session in
            try await service.fetchDisplayNameChangedAt(accessToken: session.accessToken, userID: session.userID)
        }) else { return }
        guard generation == context.generation, isCurrent("nameCooldown", serial), !isUpdatingDisplayName else { return }
        displayNameChangedAt = changedAt
        displayNameAvailableAt = changedAt.map { MeText.displayNameUnlockDate(changedAt: $0) }
        refreshDisplayNameLockNotice()
    }

    /// 지금 별명을 바꿀 수 없는가(쿨타임).
    package var isDisplayNameLocked: Bool {
        guard let availableAt = displayNameAvailableAt else { return false }
        return context.clock.now() < availableAt
    }

    package var displayNameDraftLength: Int { MeText.displayNameLength(displayNameDraft) }

    /// 저장 버튼을 살릴 조건: 잠기지 않았고, 비지 않았고, 상한 이하이고, 지금 이름과 다르다.
    package var canSaveDisplayName: Bool {
        let name = MeText.normalizedDisplayName(displayNameDraft)
        return !isUpdatingDisplayName && !isDisplayNameLocked && !name.isEmpty
            && name.unicodeScalars.count <= Self.displayNameMaxLength && name != displayName
    }

    private func refreshDisplayNameLockNotice() {
        if isDisplayNameLocked, let availableAt = displayNameAvailableAt {
            // 잠겨 있으면 여는 그 자리에서 언제 가능한지 말한다(버튼만 죽이면 왜 못 누르는지 모른다 — 맥 beginEditingDisplayName).
            displayNameNotice = MeText.displayNameCooldownMessage(availableAt: availableAt)
            isDisplayNameNoticeError = false
        }
    }

    /// 별명 저장(맥 `updateDisplayName` 과 같은 사전 검증·결과 문구). 성공이면 true.
    @discardableResult
    package func saveDisplayName() async -> Bool {
        guard context.session.isSignedIn, !isUpdatingDisplayName else { return false }
        let name = MeText.normalizedDisplayName(displayNameDraft)
        guard !name.isEmpty else {
            displayNameNotice = MeText.displayNameEmpty
            isDisplayNameNoticeError = true
            return false
        }
        guard name.unicodeScalars.count <= Self.displayNameMaxLength else {
            displayNameNotice = MeText.displayNameTooLong(Self.displayNameMaxLength)
            isDisplayNameNoticeError = true
            return false
        }
        isUpdatingDisplayName = true
        let generation = context.generation
        defer { if generation == context.generation { isUpdatingDisplayName = false } }
        let service = context.service
        do {
            let response = try await context.withMobileSessionRetry { session in
                try await service.setDisplayName(accessToken: session.accessToken, name: name)
            }
            guard generation == context.generation else { return false }
            switch DisplayNameChangeOutcome(response: response) {
            case .ok(let applied):
                let stored = applied.isEmpty ? name : applied
                displayName = stored
                displayNameDraft = stored
                let now = context.clock.now()
                displayNameChangedAt = now
                displayNameAvailableAt = MeText.displayNameUnlockDate(changedAt: now)
                displayNameNotice = MeText.displayNameSaved
                isDisplayNameNoticeError = false
                return true
            case .unchanged:
                displayNameNotice = nil
                isDisplayNameNoticeError = false
                return true
            case .taken:
                displayNameNotice = MeText.displayNameTaken
                isDisplayNameNoticeError = true
                return false
            case .cooldown(let retryAfterSeconds):
                let availableAt = context.clock.now().addingTimeInterval(TimeInterval(retryAfterSeconds))
                displayNameAvailableAt = availableAt
                displayNameNotice = MeText.displayNameCooldownMessage(availableAt: availableAt)
                isDisplayNameNoticeError = false // 쿨타임은 오류가 아니라 상태다.
                return false
            case .tooLong(let maxLength):
                displayNameNotice = MeText.displayNameTooLong(maxLength)
                isDisplayNameNoticeError = true
                return false
            case .empty:
                displayNameNotice = MeText.displayNameEmpty
                isDisplayNameNoticeError = true
                return false
            case .invalid:
                displayNameNotice = MeText.displayNameInvalid
                isDisplayNameNoticeError = true
                return false
            }
        } catch {
            guard generation == context.generation else { return false }
            if AuthErrorRules.classify(error) == .cancelled { return false }
            displayNameNotice = MeText.displayNameNetwork
            isDisplayNameNoticeError = true
            return false
        }
    }

    /// 사진 올리기. `imageData` 는 PhotosPicker 가 준 원본 — 여기서 256px JPEG 로 줄인다(메인 액터 밖).
    package func uploadAvatar(imageData: Data) async {
        guard context.session.isSignedIn, !isUploadingAvatar else { return }
        isUploadingAvatar = true
        avatarNotice = nil
        isAvatarNoticeError = false
        let generation = context.generation
        defer { if generation == context.generation { isUploadingAvatar = false } }
        let jpeg = await Task.detached(priority: .userInitiated) { MeAvatarImage.jpegData(from: imageData) }.value
        guard generation == context.generation else { return }
        guard let jpeg else {
            avatarNotice = MeText.avatarUnreadable
            isAvatarNoticeError = true
            return
        }
        let service = context.service
        do {
            let url = try await context.withMobileSessionRetry { session in
                try await service.uploadAvatar(accessToken: session.accessToken, userID: session.userID, imageData: jpeg)
            }
            guard generation == context.generation else { return }
            avatarURL = URL(string: url)
            avatarNotice = MeText.avatarSaved
            isAvatarNoticeError = false
        } catch {
            guard generation == context.generation else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            avatarNotice = AuthErrorRules.message(for: error, fallback: MeText.avatarFailed)
            isAvatarNoticeError = true
        }
    }
}
