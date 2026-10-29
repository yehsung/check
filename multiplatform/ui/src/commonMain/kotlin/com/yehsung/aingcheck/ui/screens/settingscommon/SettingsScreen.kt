// 원본: Sources/CheckMobileKit/Me/MeSettingsView.swift @ 3bd04bd (공개 설정 · 안전 · 알림 · 화면 모드 · 팀 · 계정 · 처리방침 · 버전)
//
// 설정 화면(공용 한 벌 — §8-4 settings-common). 위에서 아래로: 공개 설정 → 안전(차단한 사람) → 알림(플랫폼 자리) → 화면 모드 → 팀(코드·공유) →
// 계정(이메일 · 로그아웃 · 계정 삭제 행) → 처리방침 → 버전. **이 화면은 계정 삭제를 부르지 않는다** — 행은 삭제 화면을 열기만 한다(소스 계약,
// AccountDeletionScreen 만 deleteAccount 를 부른다). 로그아웃은 확인을 한 번 거친다(isConfirmingSignOut — 껍데기가 대화상자를 띄운다).
// 플랫폼 몫(알림 절 · 링크 열기 · 공유 시트 · 로그아웃 확인 대화상자)은 인자로 받는다 — Android 껍데기 androidApp …/screens/settings.
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.inviteCodeFailed
import com.yehsung.aingcheck.core.stores.me.privacyLoadFailed
import com.yehsung.aingcheck.core.stores.me.retrySettings
import com.yehsung.aingcheck.core.stores.me.setMiniGamePublic
import com.yehsung.aingcheck.core.stores.me.setTokenUsagePublic
import com.yehsung.aingcheck.core.stores.me.versionLine
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 설정 화면이 껍데기에 맡기는 일(링크·공유·화면 이동·확인 대화상자). */
interface SettingsActions {
    fun openBlockedPeople()

    /** 계정 삭제 화면을 연다(삭제 자체는 그 화면의 [영구 삭제] 하나로만 나간다). */
    fun openAccountDeletion()

    /** 로그아웃 확인 대화상자를 띄운다(확인되면 껍데기가 `store.signOut()`). */
    fun confirmSignOut()

    fun openUrl(url: String)

    /** 팀 코드 공유(문장 하나 — MeText.inviteShareMessage). */
    fun share(text: String)
}

object SettingsTags {
    const val ACCOUNT_DELETION_ROW = "settings-account-deletion"
    const val SIGN_OUT = "settings-sign-out"
    const val VERSION = "settings-version"
    const val PRIVACY_POLICY = "settings-privacy-policy"
    fun appearance(raw: String) = "settings-appearance:$raw"
}

/** 설정 화면 판정(순수). */
object SettingsRules {
    /** 팀 코드 칸: 코드 → 그대로 · 받았거나(코드 없음) 실패가 끝났으면 "—" · 아니면 불러오는 중. */
    fun inviteCodeText(code: String?, loaded: Boolean, failed: Boolean, isLoading: Boolean): String = when {
        code != null -> code
        loaded || (failed && !isLoading) -> "—"
        else -> MeText.loading
    }

    /** 계정 절 맨 위 이메일(프로필 → 저장된 로그인 이메일). 둘 다 없으면 줄을 만들지 않는다. */
    fun email(profileEmail: String?, storedEmail: String?): String? = profileEmail ?: storedEmail

    /** 계정 삭제 행을 누를 수 있는가 — 로그아웃·삭제가 도는 동안은 잠근다. */
    fun accountDeletionEnabled(isSigningOut: Boolean, isDeletingAccount: Boolean): Boolean = !isSigningOut && !isDeletingAccount
}

@Composable
fun SettingsScreen(
    store: MeStore,
    appearance: AppearanceStore,
    actions: SettingsActions,
    modifier: Modifier = Modifier,
    notifications: (@Composable () -> Unit)? = null,
    scrollable: Boolean = true,
) {
    val colors = AingTheme.colors
    val scroll = if (scrollable) Modifier.verticalScroll(rememberScrollState()) else Modifier
    Column(
        modifier.background(colors.background).then(scroll).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.rowSpacing),
        verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
    ) {
        PrivacySection(store)
        SafetySection(actions)
        if (notifications != null) notifications()
        AppearanceSection(appearance)
        TeamSection(store, actions)
        AccountSection(store, actions)
        InsetGroup {
            GroupRow(divider = RowDivider.None, onClick = { actions.openUrl(MeText.privacyPolicyURL) }, modifier = Modifier.testTag(SettingsTags.PRIVACY_POLICY)) {
                ChevronRowContent(MeText.privacyPolicy, trailingIcon = AppIcon.NorthEast)
            }
        }
        Text(
            store.versionLine,
            style = MaterialTheme.typography.bodySmall,
            color = colors.label2,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(top = AingDimens.space4, bottom = AingDimens.space6).testTag(SettingsTags.VERSION),
        )
    }
}

@Composable
private fun PrivacySection(store: MeStore) {
    Column(verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        SectionTitle(MeText.privacySection)
        InsetGroup {
            GroupRow(minHeight = AingDimens.rowHeightTwoLine) {
                ToggleRow(MeText.tokenPublicTitle, MeText.tokenPublicDetail, store.tokenUsagePublic, store.tokenUsagePublicLoaded, onCheckedChange = store::setTokenUsagePublic)
            }
            val tail = store.privacyLoadFailed || store.settingsNotice != null
            GroupRow(divider = if (tail) RowDivider.Card else RowDivider.None, minHeight = AingDimens.rowHeightTwoLine) {
                ToggleRow(MeText.miniGamePublicTitle, MeText.miniGamePublicDetail, store.miniGamePublic, store.miniGamePublicLoaded, onCheckedChange = store::setMiniGamePublic)
            }
            if (store.privacyLoadFailed) {
                GroupRow(divider = if (store.settingsNotice != null) RowDivider.Card else RowDivider.None) {
                    LoadFailureRow(MeText.privacyLoadFailed, MeText.retry, isRetrying = store.isLoadingSettings) { store.retrySettings() }
                }
            }
            store.settingsNotice?.let { GroupRow(divider = RowDivider.None) { InlineNotice(it, NoticeKind.Error) } }
        }
    }
}

/** 안전: 차단한 사람(되돌리는 자리는 여기 하나 — 목록과 해제는 메시지 스토어가 쥔다). */
@Composable
private fun SafetySection(actions: SettingsActions) {
    Column(verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        SectionTitle(MeText.safetySection)
        InsetGroup {
            GroupRow(divider = RowDivider.None, onClick = actions::openBlockedPeople) {
                ChevronRowContent(BlockReportText.blockedListTitle, BlockReportText.blockedListMenuDetail)
            }
        }
    }
}

/** 화면 모드: 다크(기본) · 라이트 · 시스템 — 고른 행에 체크. 행 전체가 누름 영역(44 이상). */
@Composable
private fun AppearanceSection(appearance: AppearanceStore) {
    val colors = AingTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        SectionTitle(AppearanceText.section)
        InsetGroup {
            AppearanceText.modes.forEachIndexed { index, mode ->
                val selected = appearance.mode == mode
                GroupRow(
                    divider = if (index == AppearanceText.modes.lastIndex) RowDivider.None else RowDivider.Inset(AingDimens.cardPadding + 24.dp + AingDimens.space3),
                    onClick = { appearance.select(mode) },
                    modifier = Modifier.testTag(SettingsTags.appearance(mode.storedValue)).semantics { this.selected = selected },
                ) {
                    AingIcon(AppearanceText.icon(mode), contentDescription = null, tint = if (selected) colors.accent else colors.label2)
                    Text(AppearanceText.title(mode), style = MaterialTheme.typography.bodyLarge, color = colors.label, modifier = Modifier.weight(1f))
                    AingIcon(AppIcon.Check, contentDescription = null, tint = if (selected) colors.accent else androidx.compose.ui.graphics.Color.Transparent)
                }
            }
        }
        Text(AppearanceText.widgetNote, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin))
    }
}

@Composable
private fun TeamSection(store: MeStore, actions: SettingsActions) {
    val colors = AingTheme.colors
    val code = store.inviteCode
    Column(verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        SectionTitle(MeText.teamSection)
        InsetGroup {
            GroupRow {
                Text(store.teamName ?: MeText.noTeam, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold), color = colors.label)
            }
            GroupRow(divider = if (store.inviteCodeFailed || code != null) RowDivider.Card else RowDivider.None) {
                Text(MeText.inviteCodeTitle, style = MaterialTheme.typography.bodyMedium, color = colors.label2, modifier = Modifier.weight(1f))
                val text = SettingsRules.inviteCodeText(code, store.inviteCodeLoaded, store.inviteCodeFailed, store.isLoadingSettings)
                Text(text, style = if (code != null) MaterialTheme.typography.titleLarge else MaterialTheme.typography.bodyMedium, color = if (code != null) colors.label else colors.label2)
            }
            if (store.inviteCodeFailed) {
                GroupRow(divider = if (code != null) RowDivider.Card else RowDivider.None) {
                    LoadFailureRow(MeText.inviteCodeMissing, MeText.retry, isRetrying = store.isLoadingSettings) { store.retrySettings() }
                }
            }
            if (code != null) {
                GroupRow(divider = RowDivider.None) {
                    FilledTonalButton(onClick = { actions.share(MeText.inviteShareMessage(store.teamName, code)) }, modifier = Modifier.fillMaxWidth()) {
                        AingIcon(AppIcon.IosShare, contentDescription = null, size = 18.dp)
                        Spacer(Modifier.width(6.dp))
                        Text(MeText.inviteCodeShare)
                    }
                }
            }
        }
    }
}

/** 계정: 이메일 · [로그아웃](확인 대화상자) · 계정 삭제 행(글자만 빨강 — 로그아웃보다 한 단 낮은 무게, 시트만 연다). */
@Composable
private fun AccountSection(store: MeStore, actions: SettingsActions) {
    val colors = AingTheme.colors
    val session = store.context.sessionStore
    Column(verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        SectionTitle(MeText.accountSection)
        InsetGroup {
            SettingsRules.email(session.profile?.email, session.storedEmail)?.let { email ->
                GroupRow { Text(email, style = MaterialTheme.typography.bodyMedium, color = colors.label2) }
            }
            GroupRow {
                FilledTonalButton(
                    onClick = actions::confirmSignOut,
                    enabled = !store.isSigningOut,
                    modifier = Modifier.fillMaxWidth().testTag(SettingsTags.SIGN_OUT),
                ) { Text(if (store.isSigningOut) MeText.signingOut else MeText.signOut, color = colors.danger) }
            }
            val enabled = SettingsRules.accountDeletionEnabled(store.isSigningOut, store.isDeletingAccount)
            GroupRow(
                divider = RowDivider.None,
                onClick = if (enabled) actions::openAccountDeletion else null,
                modifier = Modifier.testTag(SettingsTags.ACCOUNT_DELETION_ROW),
            ) {
                ChevronRowContent(MeText.deleteAccount, titleColor = if (enabled) colors.danger else colors.label3Text)
            }
        }
    }
}

/** 화면 맨 위 제목 한 줄(시트 대신 화면으로 열 때 껍데기가 쓴다). */
@Composable
fun SettingsTitle(modifier: Modifier = Modifier) {
    Text(MeText.settingsTitle, style = MaterialTheme.typography.titleMedium, color = AingTheme.colors.label, modifier = modifier.padding(vertical = 12.dp))
}
