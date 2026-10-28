// 원본: Sources/CheckMobileKit/Me/MeStoreProfile.swift @ 1b8260d (사진 줄이기 `MeAvatarImage` 는 플랫폼 그림 코드라 인자로 받는다)
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.fetchDisplayNameChangedAt
import com.yehsung.aingcheck.core.net.setDisplayName
import com.yehsung.aingcheck.core.net.uploadAvatar
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.DisplayNameChangeOutcome

// 프로필 편집: 사진(storage 업로드 + profiles.avatar_url PATCH — net uploadAvatar) · 별명(`set_display_name`, 12자 · 7일 쿨타임).
// 맥은 성공 뒤 팀 상태를 다시 읽는데 그 반영 경로가 근무 세션 쓰기로 이어진다 — 폰은 머리만 서버 응답으로 바꾼다.

val MeStore.Companion.displayNameMaxLength: Long get() = DisplayNameChangeOutcome.displayNameMaxLength

/** 편집 화면을 열 때: 지금 이름으로 입력을 채우고, 쿨타임 기준 시각을 다시 읽는다. */
fun MeStore.profileDidAppear() {
    isProfileVisible = true
    val name = displayName
    if (displayNameDraft.isEmpty() && name != null) displayNameDraft = name
    refreshDisplayNameLockNotice()
    // 상태메시지 입력은 받아 둔 값으로 채운다(아직 모르면 GET 이 도착할 때 채운다).
    val status = statusMessage
    if (statusMessageDraft.isEmpty() && status != null) statusMessageDraft = status
    if (!context.sessionStore.isSignedIn) return
    launch { loadDisplayNameCooldown() }
    launch { loadStatusMessage() }
}

fun MeStore.profileDidDisappear() {
    isProfileVisible = false
    displayNameDraft = ""
    if (!isUpdatingDisplayName) {
        displayNameNotice = null
        isDisplayNameNoticeError = false
    }
    if (!isUploadingAvatar) avatarNotice = null
    statusMessageDraft = ""
    if (!isUpdatingStatusMessage) {
        statusMessageNotice = null
        isStatusMessageNoticeError = false
    }
}

suspend fun MeStore.loadDisplayNameCooldown() {
    if (!context.sessionStore.isSignedIn) return
    val serial = nextSerial("nameCooldown")
    val generation = context.generation
    val service = context.service
    val nameStamp = writeStamp(MeStore.DISPLAY_NAME_WRITE_KEY)
    // 칼럼이 없는 서버·네트워크 실패는 조용히(서버가 set_display_name 에서 어차피 거른다).
    val changedAt = attempt { s -> service.fetchDisplayNameChangedAt(s.accessToken, s.userID) }.getOrElse { return }
    // 저장 중에 도착했거나 · 떠 있는 사이 별명 저장이 성공했으면(옛 기준 시각이라 방금 생긴 잠금을 푼다) 버린다.
    if (generation != context.generation || !isCurrent("nameCooldown", serial) || isUpdatingDisplayName ||
        writeStamp(MeStore.DISPLAY_NAME_WRITE_KEY) != nameStamp
    ) return
    displayNameChangedAt = changedAt
    displayNameAvailableAt = changedAt?.let { MeText.displayNameUnlockDate(it) }
    refreshDisplayNameLockNotice()
}

/** 지금 별명을 바꿀 수 없는가(쿨타임). */
val MeStore.isDisplayNameLocked: Boolean
    get() {
        val availableAt = displayNameAvailableAt ?: return false
        return context.clock.now() < availableAt
    }

val MeStore.displayNameDraftLength: Int get() = MeText.displayNameLength(displayNameDraft)

/** 저장 버튼을 살릴 조건: 잠기지 않았고, 비지 않았고, 상한 이하이고, 지금 이름과 다르다. */
val MeStore.canSaveDisplayName: Boolean
    get() {
        val name = MeText.normalizedDisplayName(displayNameDraft)
        return !isUpdatingDisplayName && !isDisplayNameLocked && name.isNotEmpty() &&
            MeText.scalarCount(name) <= MeStore.displayNameMaxLength && name != displayName
    }

private fun MeStore.refreshDisplayNameLockNotice() {
    val availableAt = displayNameAvailableAt
    if (isDisplayNameLocked && availableAt != null) {
        // 잠겨 있으면 여는 그 자리에서 언제 가능한지 말한다(버튼만 죽이면 왜 못 누르는지 모른다).
        displayNameNotice = MeText.displayNameCooldownMessage(availableAt)
        isDisplayNameNoticeError = false
    }
}

/** 별명 저장(맥 `updateDisplayName` 과 같은 사전 검증·결과 문구). 성공이면 true. */
suspend fun MeStore.saveDisplayName(): Boolean {
    if (!context.sessionStore.isSignedIn || isUpdatingDisplayName) return false
    val name = MeText.normalizedDisplayName(displayNameDraft)
    if (name.isEmpty()) {
        displayNameNotice = MeText.displayNameEmpty
        isDisplayNameNoticeError = true
        return false
    }
    if (MeText.scalarCount(name) > MeStore.displayNameMaxLength) {
        displayNameNotice = MeText.displayNameTooLong(MeStore.displayNameMaxLength)
        isDisplayNameNoticeError = true
        return false
    }
    isUpdatingDisplayName = true
    val generation = context.generation
    try {
        val service = context.service
        val response = try {
            context.withSessionRetry { s -> service.setDisplayName(s.accessToken, name) }
        } catch (e: Throwable) {
            if (generation != context.generation) return false
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return false
            displayNameNotice = MeText.displayNameNetwork
            isDisplayNameNoticeError = true
            return false
        }
        if (generation != context.generation) return false
        return when (val outcome = DisplayNameChangeOutcome.of(response)) {
            is DisplayNameChangeOutcome.Ok -> {
                val stored = outcome.name.ifEmpty { name }
                // 떠 있던 머리·쿨타임 GET 은 저장 전 값이다 — 도착해도 이 이름·잠금을 덮지 않게 표를 올린다(rankme-verify R3).
                noteLocalWrite(MeStore.DISPLAY_NAME_WRITE_KEY)
                displayName = stored
                displayNameDraft = stored
                val now = context.clock.now()
                displayNameChangedAt = now
                displayNameAvailableAt = MeText.displayNameUnlockDate(now)
                displayNameNotice = MeText.displayNameSaved
                isDisplayNameNoticeError = false
                true
            }
            DisplayNameChangeOutcome.Unchanged -> {
                displayNameNotice = null
                isDisplayNameNoticeError = false
                true
            }
            DisplayNameChangeOutcome.Taken -> {
                displayNameNotice = MeText.displayNameTaken
                isDisplayNameNoticeError = true
                false
            }
            is DisplayNameChangeOutcome.Cooldown -> {
                val availableAt = context.clock.now().addingTimeInterval(outcome.retryAfterSeconds.toDouble())
                displayNameAvailableAt = availableAt
                displayNameNotice = MeText.displayNameCooldownMessage(availableAt)
                isDisplayNameNoticeError = false // 쿨타임은 오류가 아니라 상태다.
                false
            }
            is DisplayNameChangeOutcome.TooLong -> {
                displayNameNotice = MeText.displayNameTooLong(outcome.maxLength)
                isDisplayNameNoticeError = true
                false
            }
            DisplayNameChangeOutcome.Empty -> {
                displayNameNotice = MeText.displayNameEmpty
                isDisplayNameNoticeError = true
                false
            }
            DisplayNameChangeOutcome.Invalid -> {
                displayNameNotice = MeText.displayNameInvalid
                isDisplayNameNoticeError = true
                false
            }
        }
    } finally {
        if (generation == context.generation) isUpdatingDisplayName = false
    }
}

/**
 * 사진 올리기. [imageData] 는 사진 고르개가 준 원본 — [encodeJpeg] 가 256px JPEG 로 줄인다(Swift `MeAvatarImage.jpegData` 자리 —
 * 플랫폼 그림 코드라 화면 갈래가 넘긴다. 못 읽으면 null).
 */
suspend fun MeStore.uploadAvatar(imageData: ByteArray, encodeJpeg: suspend (ByteArray) -> ByteArray?) {
    if (!context.sessionStore.isSignedIn || isUploadingAvatar) return
    isUploadingAvatar = true
    avatarNotice = null
    isAvatarNoticeError = false
    val generation = context.generation
    try {
        val jpeg = encodeJpeg(imageData)
        if (generation != context.generation) return
        if (jpeg == null) {
            avatarNotice = MeText.avatarUnreadable
            isAvatarNoticeError = true
            return
        }
        val service = context.service
        val url = try {
            context.withSessionRetry { s -> service.uploadAvatar(s.accessToken, s.userID, jpeg) }
        } catch (e: Throwable) {
            if (generation != context.generation) return
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
            avatarNotice = AuthErrorRules.message(e, MeText.avatarFailed)
            isAvatarNoticeError = true
            return
        }
        if (generation != context.generation) return
        // 떠 있던 머리 GET 은 업로드 전 사진 URL 이다 — 도착해도 덮지 않게(rankme-verify R5).
        noteLocalWrite(MeStore.AVATAR_WRITE_KEY)
        avatarURL = SwiftURL.parse(url)
        avatarNotice = MeText.avatarSaved
        isAvatarNoticeError = false
    } finally {
        if (generation == context.generation) isUploadingAvatar = false
    }
}
