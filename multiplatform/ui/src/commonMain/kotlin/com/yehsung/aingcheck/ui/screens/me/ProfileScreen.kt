// 원본: Sources/CheckMobileKit/Me/MeProfileView.swift @ 3bd04bd (프로필 편집 — 사진 · 별명(12자 · 7일 쿨타임) · 상태메시지 40자 · 내 화면엔 착용 캐릭터)
//
// 채운 버튼은 [저장](별명) 하나 — 드물게 쓰는 [사진 바꾸기]·상태 [저장]은 틴트, [지우기]는 회색(Swift 디자인 계약 w15 · 비평 28).
// 판정(잠김 · 저장 가능 · 글자 수 · 쿨타임 문구)은 전부 스토어(W2-c MeStoreProfile · MeStoreStatusMessage)다. 이 화면은 그리기만 한다.
// 사진 고르기와 256px JPEG 줄이기는 플랫폼 몫이라 [onPickPhoto] 로 받는다(Android: 사진 선택기 → AvatarJpeg — androidApp screens/me).
// 글자를 자르지 않는다(조합 중 한글이 깨진다 — E§8). 넘친 값은 저장 단추가 막는다.
package com.yehsung.aingcheck.ui.screens.me

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.StatusMessageText
import com.yehsung.aingcheck.core.stores.me.AvatarRemovalNoticeTone
import com.yehsung.aingcheck.core.stores.me.AvatarRemovalText
import com.yehsung.aingcheck.core.stores.me.beginAvatarRemoval
import com.yehsung.aingcheck.core.stores.me.performAvatarRemoval
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.me.canClearStatusMessage
import com.yehsung.aingcheck.core.stores.me.canSaveDisplayName
import com.yehsung.aingcheck.core.stores.me.canSaveStatusMessage
import com.yehsung.aingcheck.core.stores.me.clearStatusMessage
import com.yehsung.aingcheck.core.stores.me.displayNameDraftLength
import com.yehsung.aingcheck.core.stores.me.displayNameMaxLength
import com.yehsung.aingcheck.core.stores.me.equippedCharacterID
import com.yehsung.aingcheck.core.stores.me.isDisplayNameLocked
import com.yehsung.aingcheck.core.stores.me.profileDidAppear
import com.yehsung.aingcheck.core.stores.me.profileDidDisappear
import com.yehsung.aingcheck.core.stores.me.saveDisplayName
import com.yehsung.aingcheck.core.stores.me.saveStatusMessage
import com.yehsung.aingcheck.core.stores.me.statusMessageDraftLength
import com.yehsung.aingcheck.core.stores.me.statusMessageMaxLength
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.AppUserAvatar
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.CharacterPortrait
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.LocalDesktopWording
import com.yehsung.aingcheck.ui.screens.session.kit.AvatarFace
import com.yehsung.aingcheck.ui.screens.settingscommon.AingButton
import com.yehsung.aingcheck.ui.screens.settingscommon.AingButtonKind
import com.yehsung.aingcheck.ui.screens.settingscommon.AingCard
import com.yehsung.aingcheck.ui.screens.settingscommon.CountedTextField
import com.yehsung.aingcheck.ui.screens.settingscommon.InlineNotice
import com.yehsung.aingcheck.ui.screens.settingscommon.LocalScreenArt
import com.yehsung.aingcheck.ui.screens.settingscommon.NoticeKind
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

object ProfileTags {
    const val PICK_PHOTO = "profile-pick-photo"
    const val NAME_FIELD = "profile-name-field"
    const val NAME_SAVE = "profile-name-save"
    const val STATUS_FIELD = "profile-status-field"
    const val STATUS_SAVE = "profile-status-save"
    const val STATUS_CLEAR = "profile-status-clear"
    const val CHARACTER_ROW = "profile-character-row"
    const val AVATAR_REMOVE = "profile-avatar-remove"
    const val AVATAR_REMOVE_CONFIRM = "profile-avatar-remove-confirm"
    const val AVATAR_REMOVE_CANCEL = "profile-avatar-remove-cancel"
    const val AVATAR_REMOVE_NOTICE = "profile-avatar-remove-notice"
}

/** 프로필 화면 판정(순수 — 스토어 값을 화면 모양으로만 옮긴다). */
object ProfileScreenRules {
    const val AVATAR_SIZE = 96

    fun noticeKind(isError: Boolean): NoticeKind = if (isError) NoticeKind.Error else NoticeKind.Info

    fun pickerTitle(uploading: Boolean): String = if (uploading) MeText.avatarUploading else MeText.avatarChange

    /** 저장된 상태메시지가 있을 때만 [지우기]가 선다. */
    fun showsClear(statusMessage: String?): Boolean = statusMessage != null

    /** 큰 아바타 자리(Swift `AvatarView(url:userID:)`): 올린 사진 → 착용 캐릭터. 사진을 읽는 동안 · 못 읽으면 착용 캐릭터로 떨어진다(이름 첫 글자 원이 아니다). */
    fun avatar(photoURL: SwiftURL?, equippedCharacterID: String): AppUserAvatar =
        if (photoURL != null) AppUserAvatar.Photo(photoURL, equippedCharacterID) else AppUserAvatar.Character(equippedCharacterID)
}

/**
 * @param onPickPhoto 사진 고르기(플랫폼 선택기 → 스토어 uploadAvatar). 올리는 중에는 부르지 않는다.
 * @param openCharacters 착용 캐릭터 줄 → 캐릭터 고르기.
 * @param showsAvatarRemoval [기본 캐릭터로 되돌리기] 행(맥 `AvatarRemovalSettingsRow`). Android 경로만 켠다 — Windows 는 사진을 올리는 자리도 없고(onPickPhoto 빈 값) 기능 동결이다.
 */
@Composable
fun ProfileScreen(
    store: MeStore,
    scope: CoroutineScope,
    onPickPhoto: () -> Unit,
    openCharacters: () -> Unit,
    modifier: Modifier = Modifier,
    scrollable: Boolean = true,
    showsAvatarRemoval: Boolean = false,
) {
    val colors = AingTheme.colors
    val focus = LocalFocusManager.current
    DisposableEffect(store) {
        store.profileDidAppear()
        onDispose { store.profileDidDisappear() }
    }
    fun save() {
        if (!store.canSaveDisplayName) return
        focus.clearFocus()
        scope.launch { store.saveDisplayName() }
    }
    fun saveStatus() {
        if (!store.canSaveStatusMessage) return
        focus.clearFocus()
        scope.launch { store.saveStatusMessage() }
    }
    val scroll = if (scrollable) Modifier.verticalScroll(rememberScrollState()) else Modifier
    Column(
        modifier.fillMaxWidth().background(colors.background).then(scroll).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.rowSpacing),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
    ) {
        AingCard {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing)) {
                Box(contentAlignment = Alignment.Center) {
                    ProfileAvatar(store, ProfileScreenRules.AVATAR_SIZE.dp)
                    if (store.isUploadingAvatar) {
                        Box(Modifier.size(ProfileScreenRules.AVATAR_SIZE.dp).clip(CircleShape).background(colors.label.copy(alpha = 0.35f)), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(24.dp), color = colors.onAccentFill, strokeWidth = 2.dp)
                        }
                    }
                }
                Text(MeText.avatarRoleNote, style = MaterialTheme.typography.bodySmall, color = colors.label2, textAlign = TextAlign.Center)
                AingButton(
                    ProfileScreenRules.pickerTitle(store.isUploadingAvatar),
                    AingButtonKind.Tinted,
                    onClick = onPickPhoto,
                    enabled = !store.isUploadingAvatar && !store.isRemovingAvatar,
                    icon = AppIcon.PhotoLibrary,
                    modifier = Modifier.testTag(ProfileTags.PICK_PHOTO),
                )
                store.avatarNotice?.let { InlineNotice(it, ProfileScreenRules.noticeKind(store.isAvatarNoticeError)) }
            }
        }

        if (showsAvatarRemoval) AvatarRemovalCard(store, scope)

        AingCard {
            Text(MeText.displayNameLabel, style = MaterialTheme.typography.titleSmall, color = colors.label)
            Text(MeText.displayNameHelp, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            CountedTextField(
                value = store.displayNameDraft,
                onValueChange = { store.displayNameDraft = it },
                placeholder = MeText.displayNameLabel,
                count = store.displayNameDraftLength,
                max = MeStore.displayNameMaxLength.toInt(),
                accessibilityLabel = MeText.displayNameLabel,
                enabled = !store.isDisplayNameLocked && !store.isUpdatingDisplayName,
                onDone = ::save,
                fieldModifier = Modifier.testTag(ProfileTags.NAME_FIELD),
            )
            store.displayNameNotice?.let { InlineNotice(it, ProfileScreenRules.noticeKind(store.isDisplayNameNoticeError)) }
            AingButton(
                MeText.displayNameSave,
                AingButtonKind.Filled,
                onClick = ::save,
                enabled = store.canSaveDisplayName,
                busy = store.isUpdatingDisplayName,
                fillsWidth = true,
                modifier = Modifier.testTag(ProfileTags.NAME_SAVE),
            )
        }

        // 상태메시지(v0.3.51) — 40자 한 줄 · 비우고 저장하면 지워진다 · 쿨타임 없음.
        AingCard {
            Text(StatusMessageText.title, style = MaterialTheme.typography.titleSmall, color = colors.label)
            Text(StatusMessageText.hint, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            CountedTextField(
                value = store.statusMessageDraft,
                onValueChange = { store.statusMessageDraft = it },
                placeholder = StatusMessageText.placeholder,
                count = store.statusMessageDraftLength,
                max = MeStore.statusMessageMaxLength,
                accessibilityLabel = StatusMessageText.title,
                enabled = !store.isUpdatingStatusMessage,
                onDone = ::saveStatus,
                fieldModifier = Modifier.testTag(ProfileTags.STATUS_FIELD),
            )
            store.statusMessageNotice?.let { InlineNotice(it, ProfileScreenRules.noticeKind(store.isStatusMessageNoticeError)) }
            Row(horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                if (ProfileScreenRules.showsClear(store.statusMessage)) {
                    AingButton(
                        StatusMessageText.clear,
                        AingButtonKind.Gray,
                        onClick = {
                            focus.clearFocus()
                            scope.launch { store.clearStatusMessage() }
                        },
                        enabled = store.canClearStatusMessage,
                        modifier = Modifier.weight(1f).testTag(ProfileTags.STATUS_CLEAR),
                    )
                }
                AingButton(
                    StatusMessageText.save,
                    AingButtonKind.Tinted,
                    onClick = ::saveStatus,
                    enabled = store.canSaveStatusMessage,
                    busy = store.isUpdatingStatusMessage,
                    modifier = Modifier.weight(1f).testTag(ProfileTags.STATUS_SAVE),
                )
            }
        }

        CharacterRoleCard(store, openCharacters)
    }
}

/** 사진이 없으면 착용 캐릭터 초상, 있으면 올린 사진(못 읽는 동안은 공용 아바타가 착용 캐릭터를 그린다). */
@Composable
private fun ProfileAvatar(store: MeStore, size: Dp) {
    val avatar = ProfileScreenRules.avatar(store.avatarURL, store.equippedCharacterID)
    if (avatar is AppUserAvatar.Character) {
        CharacterPortrait(LocalScreenArt.current.portrait(avatar.id, null), CharacterMood.Plain, size)
    } else {
        AvatarFace(avatar, store.displayName ?: MeScreenText.tabTitle, size)
    }
}

/**
 * 사진을 지워 착용 캐릭터로 되돌리는 한 장(맥 `AvatarRemovalSettingsRow` — 2단 확인 · 설명 줄이 곧 결과 줄). 평소 [기본 캐릭터로 되돌리기] → 같은 자리가 [취소]+[되돌리기].
 * 사진 유무로 감추거나 잠그지 않는다 — 서버 사진과 화면 사진이 어긋난 사람이 탈출구를 잃는다. 폭이 좁아 맥의 옆 칸 단추를 설명 아래 줄로 내렸다.
 */
@Composable
private fun AvatarRemovalCard(store: MeStore, scope: CoroutineScope) {
    val colors = AingTheme.colors
    val signedIn = store.context.sessionStore.isSignedIn
    val notice = AvatarRemovalText.notice(store.avatarRemovalNotice, signedIn, store.isConfirmingAvatarRemoval)
    val noticeColor = when {
        store.avatarRemovalNotice == null -> colors.label2
        store.avatarRemovalNoticeTone == AvatarRemovalNoticeTone.success -> colors.working
        store.avatarRemovalNoticeTone == AvatarRemovalNoticeTone.warning -> colors.pending
        else -> colors.danger
    }
    AingCard {
        Text(AvatarRemovalText.title, style = MaterialTheme.typography.titleSmall, color = colors.label)
        Text(notice, style = MaterialTheme.typography.bodySmall, color = noticeColor, modifier = Modifier.testTag(ProfileTags.AVATAR_REMOVE_NOTICE))
        if (store.isConfirmingAvatarRemoval) {
            Row(horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
                AingButton(
                    AvatarRemovalText.cancel,
                    AingButtonKind.Gray,
                    onClick = { store.isConfirmingAvatarRemoval = false },
                    modifier = Modifier.weight(1f).testTag(ProfileTags.AVATAR_REMOVE_CANCEL),
                )
                // 되돌릴 수 없는 동작이라 빨강(차단 확인과 같은 규약).
                AingButton(
                    AvatarRemovalText.confirm,
                    AingButtonKind.Danger,
                    onClick = { scope.launch { store.performAvatarRemoval() } },
                    enabled = !store.isRemovingAvatar,
                    modifier = Modifier.weight(1f).testTag(ProfileTags.AVATAR_REMOVE_CONFIRM),
                )
            }
        } else {
            AingButton(
                if (store.isRemovingAvatar) AvatarRemovalText.inFlight else AvatarRemovalText.action,
                AingButtonKind.Gray,
                onClick = store::beginAvatarRemoval,
                enabled = !store.isRemovingAvatar && !store.isUploadingAvatar && signedIn,
                fillsWidth = true,
                modifier = Modifier.testTag(ProfileTags.AVATAR_REMOVE),
            )
        }
    }
}

/** 내 화면에 서는 것은 착용 캐릭터 — 초상 + 한 줄 + [캐릭터 바꾸기]. */
@Composable
private fun CharacterRoleCard(store: MeStore, openCharacters: () -> Unit) {
    val colors = AingTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AingDimens.groupRadius))
            .background(colors.surface)
            .clickable(role = Role.Button, onClick = openCharacters)
            .padding(AingDimens.cardPadding)
            .testTag(ProfileTags.CHARACTER_ROW),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
    ) {
        CharacterPortrait(LocalScreenArt.current.portrait(store.equippedCharacterID, null), CharacterMood.Plain, 52.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(MeText.characterRoleTitle, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.label)
            Text(if (LocalDesktopWording.current) MeText.characterRoleNoteDesktop else MeText.characterRoleNote, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            Text(MeText.changeCharacter, style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold), color = colors.accent, modifier = Modifier.padding(top = 2.dp))
        }
        AingIcon(AppIcon.ChevronRight, contentDescription = null, size = 16.dp, tint = colors.label3)
    }
}
