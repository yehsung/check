// 원본: Sources/CheckMobileKit/Me/MeStoreSettings.swift @ 1b8260d (화면 모드 `context.appearance` 는 기기 설정이라 ui 테마 쪽 — W3-b)
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.fetchMiniGamePublic
import com.yehsung.aingcheck.core.net.fetchMyInviteCode
import com.yehsung.aingcheck.core.net.fetchTokenUsageSettings
import com.yehsung.aingcheck.core.net.updateMiniGamePublic
import com.yehsung.aingcheck.core.net.updateTokenUsagePublic
import com.yehsung.aingcheck.core.session.AccountDeletionFailure
import com.yehsung.aingcheck.core.session.AccountDeletionOutcome

// 설정: 공개 설정 2개(profiles 자기 행 PATCH — token_usage_public · minigame_public) · 알림(푸시 코디네이터 — W2-f) · 팀 코드 ·
// 로그아웃(세션) · 계정 삭제(세션) · 버전. 공개 토글은 맥과 같은 **낙관 반영 → 실패 시 원복**이다. 공개 설정 GET 에 딸려 오는 focus_mode 는
// 읽고 버린다(폰은 집중 모드를 바꾸지 않는다).

fun MeStore.settingsDidAppear() {
    if (!context.sessionStore.isSignedIn) return
    launch { loadSettings() }
}

fun MeStore.settingsDidDisappear() {
    settingsNotice = null
    context.meLinks.clearPushPrefsNotice()
}

/**
 * 공개 설정 두 칸 + 팀 코드. 셋은 독립 실패다. 공개 설정은 **떠날 때 찍은 표**가 그대로일 때만 스위치에 옮긴다. 실패는 칸마다 깃발로 남겨
 * 화면이 '불러오는 중…'·죽은 스위치에 머물지 않고 원인과 [다시 시도]를 말한다.
 */
suspend fun MeStore.loadSettings() {
    if (!context.sessionStore.isSignedIn) return
    val serial = nextSerial("settings")
    val generation = context.generation
    val service = context.service
    isLoadingSettings = true
    tokenUsagePublicLoadFailed = false
    miniGamePublicLoadFailed = false
    inviteCodeLoadFailed = false
    try {
        val tokenStamp = privacyReadStamp("token")
        val token = attempt { s -> service.fetchTokenUsageSettings(s.accessToken, s.userID) }
        if (generation != context.generation || !isCurrent("settings", serial)) return
        token.fold(
            onSuccess = { value ->
                if (canApplyPrivacyRead("token", tokenStamp)) {
                    tokenUsagePublic = value.isPublic
                    tokenUsagePublicLoaded = true
                }
            },
            onFailure = { e ->
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
                tokenUsagePublicLoadFailed = true
            },
        )

        val miniGameStamp = privacyReadStamp("minigame")
        val miniGame = attempt { s -> service.fetchMiniGamePublic(s.accessToken, s.userID) }
        if (generation != context.generation || !isCurrent("settings", serial)) return
        miniGame.fold(
            onSuccess = { value ->
                if (canApplyPrivacyRead("minigame", miniGameStamp)) {
                    // 칼럼·행이 없으면 null → 공개로 본다.
                    miniGamePublic = value ?: true
                    miniGamePublicLoaded = true
                }
            },
            onFailure = { e ->
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
                miniGamePublicLoadFailed = true
            },
        )

        val code = attempt { s -> service.fetchMyInviteCode(s.accessToken) }
        if (generation != context.generation || !isCurrent("settings", serial)) return
        code.fold(
            onSuccess = { value ->
                inviteCode = value
                inviteCodeLoaded = true
            },
            onFailure = { e ->
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
                inviteCodeLoadFailed = true
            },
        )
    } finally {
        if (isCurrent("settings", serial)) isLoadingSettings = false
    }
}

/** 공개 설정을 **아직 한 번도** 못 읽었고 마지막 조회가 실패했다. */
val MeStore.privacyLoadFailed: Boolean
    get() = (tokenUsagePublicLoadFailed && !tokenUsagePublicLoaded) || (miniGamePublicLoadFailed && !miniGamePublicLoaded)

val MeStore.inviteCodeFailed: Boolean get() = inviteCodeLoadFailed && !inviteCodeLoaded

/** [다시 시도] — 떠 있는 조회가 있으면 새로 내지 않는다. 누르는 즉시 '불러오는 중'으로 바꿔 연타가 요청을 겹치지 않게 한다. */
fun MeStore.retrySettings() {
    if (!context.sessionStore.isSignedIn || isLoadingSettings) return
    isLoadingSettings = true
    launch { loadSettings() }
}

// MARK: 공개 설정

fun MeStore.setTokenUsagePublic(isPublic: Boolean) {
    if (tokenUsagePublic == isPublic || !context.sessionStore.isSignedIn) return
    val previous = tokenUsagePublic
    tokenUsagePublic = isPublic
    tokenUsagePublicLoaded = true
    settingsNotice = null
    val generation = context.generation
    val service = context.service
    val serial = nextSerial("privacy.token")
    launch {
        try {
            context.withSessionRetry { s -> service.updateTokenUsagePublic(s.accessToken, s.userID, isPublic) }
            if (generation == context.generation) context.meLinks.noteTokenUsagePublic(isPublic)
        } catch (e: Throwable) {
            if (generation == context.generation && isCurrent("privacy.token", serial) &&
                AuthErrorRules.classify(e) != AuthErrorDisposition.cancelled
            ) {
                tokenUsagePublic = previous
                settingsNotice = MeText.privacySaveFailed
            }
        }
        if (isCurrent("privacy.token", serial)) savingPrivacyKeys.remove("token")
    }
    savingPrivacyKeys.add("token")
}

fun MeStore.setMiniGamePublic(isPublic: Boolean) {
    if (miniGamePublic == isPublic || !context.sessionStore.isSignedIn) return
    val previous = miniGamePublic
    miniGamePublic = isPublic
    miniGamePublicLoaded = true
    settingsNotice = null
    val generation = context.generation
    val service = context.service
    val serial = nextSerial("privacy.minigame")
    launch {
        try {
            context.withSessionRetry { s -> service.updateMiniGamePublic(s.accessToken, s.userID, isPublic) }
        } catch (e: Throwable) {
            if (generation == context.generation && isCurrent("privacy.minigame", serial) &&
                AuthErrorRules.classify(e) != AuthErrorDisposition.cancelled
            ) {
                miniGamePublic = previous
                settingsNotice = MeText.privacySaveFailed
            }
        }
        if (isCurrent("privacy.minigame", serial)) savingPrivacyKeys.remove("minigame")
    }
    savingPrivacyKeys.add("minigame")
}

// MARK: 계정

suspend fun MeStore.signOut() {
    if (!context.sessionStore.isSignedIn || isSigningOut) return
    isSigningOut = true
    context.sessionStore.signOut()
    // 세션이 세대를 올리며 앱 모델이 reset() 을 불렀다 — 깃발은 거기서 이미 내려갔다.
    isSigningOut = false
}

/** [영구 삭제] 를 누를 수 있는가 — 비밀번호를 쳤고 · 도는 중이 아니고 · 로그인 상태. */
val MeStore.canDeleteAccount: Boolean
    get() = accountDeletionPassword.isNotEmpty() && !isDeletingAccount && context.sessionStore.isSignedIn

/**
 * 영구 삭제. 재인증 → RPC → 로컬 정리는 전부 세션 스토어가 한다 — 나 탭은 문구와 깃발만. 성공하면 true, 실패하면 로그인 상태 그대로 + 이유 한 줄.
 */
suspend fun MeStore.deleteAccount(): Boolean {
    if (!context.sessionStore.isSignedIn || isDeletingAccount) return false
    val password = accountDeletionPassword
    if (password.isEmpty()) {
        accountDeletionNotice = MeText.deleteAccountFailure(AccountDeletionFailure.PasswordRequired)
        return false
    }
    isDeletingAccount = true
    accountDeletionNotice = null
    return when (val outcome = context.sessionStore.deleteAccount(password)) {
        AccountDeletionOutcome.Deleted -> true
        is AccountDeletionOutcome.Failed -> {
            isDeletingAccount = false
            accountDeletionNotice = MeText.deleteAccountFailure(outcome.reason)
            false
        }
    }
}

/** 시트가 닫혔다 — 비밀번호와 실패 문구를 비운다. */
fun MeStore.accountDeletionDidDisappear() {
    accountDeletionPassword = ""
    accountDeletionNotice = null
}

val MeStore.versionLine: String get() = MeText.versionLine(context.appInfo)
