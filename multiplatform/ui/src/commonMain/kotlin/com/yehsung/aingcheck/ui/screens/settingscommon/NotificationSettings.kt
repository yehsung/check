// 원본: Sources/CheckMobileKit/Me/MeSettingsView.swift @ 3bd04bd (pushSection — 권한 머리 줄 · 알림 켜기 · 설정 앱 · 종류별 토글 · 모름 안내 · 저장 실패)
// 원본: Sources/CheckMobileKit/Me/MeText.swift:833-960 @ 3bd04bd (pushDetail · PushAuthorizationStatus.meTitle/meDetail) · Push/PushPayload.swift(settingTitle · PushText)
//
// 알림 절 — **두 겹 스위치**(E§6.5): 앱 안 토글은 **서버 선호값**(set_push_prefs — 안 보내기), 시스템 채널 끔은 **기기**(안 보이기)다.
// 두 겹은 서로를 덮지 않는다: 서버 토글을 켜 둔 채 채널이 꺼져 있으면 토글은 켜진 채로 두고 그 행에 "시스템에서 꺼짐 · 설정 열기" 를 단다
// (토글을 끈 모양으로 바꾸면 사용자는 토글을 다시 켜고, 서버는 이미 켜져 있으니 아무 일도 안 일어난다). 반대로 서버에서 껐는데 채널은 켜져 있으면
// 토글만 꺼져 보인다(시스템 안내 없음). 권한(POST_NOTIFICATIONS)이 없으면 iOS 처럼 토글은 **꺼진 모양으로 흐리게** 선다 — 알림이 오지 않는다는
// 사실 그대로이고 서버 선호값은 건드리지 않는다.
// 판정은 [NotificationTwoLayer](순수 — 공용 시험)에 있다. 플랫폼 상태(권한 · 채널 중요도)를 읽고 저장을 부르는 일은 [NotificationSettingsModel]
// 구현(Android 껍데기 androidApp …/screens/settings — W2-f 푸시 조정자를 감싼다)이 한다.
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.wire.models.PushPrefs
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 알림 권한(플랫폼 값을 접은 넷). Android 는 provisional·ephemeral 이 없다. API 26~32 는 언제나 [Granted](런타임 권한이 없다). */
enum class NotificationPermission {
    /** 아직 못 읽었다. */
    Unknown,

    /** 한 번도 묻지 않았다(또는 다시 물을 수 있다) — [알림 켜기]. */
    NotDetermined,

    /** 거절됐다(두 번 거절이면 시스템이 다시 묻지 않는다) — [설정 앱에서 켜기]. */
    Denied,
    Granted,
    ;

    val allowsDelivery: Boolean get() = this == Granted
}

/** 알림 종류 하나(채널 id = 서버 kind 글자). [prefsKey] null = 앱 안 토글이 없다(서버가 받지 않거나 이 앱의 선호값 전선에 칸이 없다). */
data class NotificationKind(val raw: String, val title: String, val prefsKey: String?)

/** 종류별 한 행의 두 겹 상태. */
data class NotificationRowState(
    val kind: NotificationKind,
    val detail: String?,
    /** 앱 안 토글이 서는가(서버 선호값 키가 있다). */
    val hasAppToggle: Boolean,
    /** 토글 모양(권한이 없거나 선호값을 모르면 **꺼진 모양**). */
    val appOn: Boolean,
    /** 토글을 누를 수 있는가(권한 있음 + 서버값을 앎). */
    val appEnabled: Boolean,
    /** 시스템에서 이 채널이 꺼져 있다 → "시스템에서 꺼짐 · 설정 열기". 권한이 없을 때는 머리 줄이 말하므로 행마다 달지 않는다. */
    val systemBlocked: Boolean,
)

object NotificationTwoLayer {
    /**
     * Android 의 종류 다섯(E§6.5 채널 표 순서 — 근무 확인은 끌 수 없어 앱 토글이 없다).
     * ⚠️ 체스 신청은 서버가 끌 수 있는 키지만(E§6.1) 이 앱의 선호값 전선(core/wire PushPrefs)에 `chess_invite` 칸이 없다 —
     *   그래서 앱 토글을 세우지 않고 시스템 채널 한 겹만 둔다(보고: 전선에 칸을 더하면 [prefsKey] 를 채운다).
     */
    val androidKinds: List<NotificationKind> = listOf(
        NotificationKind("message", "메시지", "message"),
        NotificationKind("gomoku_invite", "오목 신청", "gomoku_invite"),
        NotificationKind("chess_invite", "체스 신청", null),
        NotificationKind("feedback_reply", "제보 답장", "feedback_reply"),
        NotificationKind("work_check", "근무 확인", null),
    )

    /** 서버 선호값의 한 칸. 모르는 키는 null(지어내지 않는다). */
    fun serverValue(prefs: PushPrefs, prefsKey: String): Boolean? = when (prefsKey) {
        "message" -> prefs.message
        "gomoku_invite" -> prefs.gomokuInvite
        "feedback_reply" -> prefs.feedbackReply
        else -> null
    }

    /** 한 칸만 바꾼 새 선호값(모르는 키면 null — 보낼 것이 없다). */
    fun withValue(prefs: PushPrefs, prefsKey: String, enabled: Boolean): PushPrefs? = when (prefsKey) {
        "message" -> prefs.copy(message = enabled)
        "gomoku_invite" -> prefs.copy(gomokuInvite = enabled)
        "feedback_reply" -> prefs.copy(feedbackReply = enabled)
        else -> null
    }

    fun rows(
        kinds: List<NotificationKind>,
        permission: NotificationPermission,
        prefs: PushPrefs?,
        blockedChannels: Set<String>,
    ): List<NotificationRowState> = kinds.map { kind ->
        val key = kind.prefsKey
        val server = if (key != null && prefs != null) serverValue(prefs, key) else null
        val hasToggle = key != null
        NotificationRowState(
            kind = kind,
            detail = MeText.pushDetail(kind.raw) ?: kindDetail(kind.raw),
            hasAppToggle = hasToggle,
            appOn = hasToggle && permission.allowsDelivery && server == true,
            appEnabled = hasToggle && permission.allowsDelivery && server != null,
            systemBlocked = permission.allowsDelivery && kind.raw in blockedChannels,
        )
    }

    /** 공용 문구에 없는 종류의 한 줄(체스 신청 — iOS 에는 아직 없는 종류다). */
    private fun kindDetail(raw: String): String? = when (raw) {
        "chess_invite" -> "1:1 체스 대결 신청이 오면 알려 줘요."
        else -> null
    }

    /** 권한 머리 줄(Swift `PushAuthorizationStatus.meTitle` 의 Android 판). */
    fun headerTitle(permission: NotificationPermission): String = when (permission) {
        NotificationPermission.Unknown -> "알림 권한 확인 중…"
        NotificationPermission.NotDetermined -> "알림 허용을 아직 정하지 않았어요"
        NotificationPermission.Denied -> "알림이 꺼져 있어요"
        NotificationPermission.Granted -> "알림이 켜져 있어요"
    }

    /** 머리 아래 한 줄(설정 앱에 뜨는 줄은 **표시 이름**이다 — 옛 이름을 가리키면 사람이 못 찾는다). */
    fun headerDetail(permission: NotificationPermission): String? = when (permission) {
        NotificationPermission.Denied -> "설정 › 앱 › ${MeText.appDisplayName} › 알림에서 켤 수 있어요."
        NotificationPermission.NotDetermined -> "허용하면 아래 종류별로 고를 수 있어요."
        NotificationPermission.Unknown, NotificationPermission.Granted -> null
    }

    /** 머리 아래 단추: 묻기 전 [알림 켜기] · 거절됨 [설정 앱에서 켜기] · 그 밖 없음. */
    fun headerAction(permission: NotificationPermission): NotificationHeaderAction? = when (permission) {
        NotificationPermission.NotDetermined -> NotificationHeaderAction.RequestPermission
        NotificationPermission.Denied -> NotificationHeaderAction.OpenSystemSettings
        NotificationPermission.Unknown, NotificationPermission.Granted -> null
    }

    /** 서버값을 모르는데 권한은 있다 → "아직 못 읽었어요" 안내(토글은 흐린 꺼짐). */
    fun showsPrefsUnknown(permission: NotificationPermission, prefs: PushPrefs?): Boolean = permission.allowsDelivery && prefs == null

    const val enableLabel = "알림 켜기"
    const val systemBlockedLabel = "시스템에서 꺼짐"
    const val openChannelSettingsLabel = "설정 열기"

    /** 근무 확인 채널이 꺼졌을 때 그 행에 다는 사실(E§6.4 — 데이터 위험은 없고 '안내'만 잃는다). */
    const val workCheckBlockedNote = "근무 확인 알림이 꺼져 있으면 2시간 30분 뒤 안내 없이 마감돼요"
}

enum class NotificationHeaderAction { RequestPermission, OpenSystemSettings }

/** 알림 절이 읽고 부르는 것(플랫폼 구현이 W2-f 푸시 조정자 · 시스템 알림 관리자를 감싼다). */
interface NotificationSettingsModel {
    val permission: NotificationPermission

    /** 서버 선호값(기기 등록 응답) — null 은 아직 모른다. */
    val prefs: PushPrefs?

    /** 시스템에서 꺼진 채널 id 들(두 번째 겹). */
    val blockedChannels: Set<String>
    val isSavingPrefs: Boolean
    val isRequestingPermission: Boolean

    /** 저장 실패 한 줄(없으면 null). */
    val prefsNotice: String?
    val kinds: List<NotificationKind> get() = NotificationTwoLayer.androidKinds

    /** 앱 안 토글(첫 겹) — 서버 선호값만 바꾼다. 채널은 건드리지 않는다. */
    fun setEnabled(kind: NotificationKind, enabled: Boolean)

    fun requestPermission()

    /** 앱의 알림 설정 화면(권한 거절됨). */
    fun openSystemSettings()

    /** 그 채널의 시스템 설정 화면(두 번째 겹 — Android `ACTION_CHANNEL_NOTIFICATION_SETTINGS`). */
    fun openChannelSettings(kind: NotificationKind)
}

/** 알림 절(인셋 그룹 한 장): 권한 머리 줄 + 단추 → 종류별 행 → 모름 안내 → 저장 실패. */
@Composable
fun NotificationSettingsSection(model: NotificationSettingsModel, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val permission = model.permission
    val rows = NotificationTwoLayer.rows(model.kinds, permission, model.prefs, model.blockedChannels)
    val showsUnknown = NotificationTwoLayer.showsPrefsUnknown(permission, model.prefs)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        SectionTitle(MeText.pushSection)
        InsetGroup {
            GroupRow(minHeight = AingDimens.rowHeightTwoLine) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        AingIcon(
                            if (permission.allowsDelivery) AppIcon.NotificationsUnreadFill else AppIcon.NotificationsOffFill,
                            contentDescription = null,
                            size = 22.dp,
                            tint = if (permission.allowsDelivery) colors.accent else colors.label2,
                        )
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(NotificationTwoLayer.headerTitle(permission), style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold), color = colors.label)
                            NotificationTwoLayer.headerDetail(permission)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.label2) }
                        }
                        if (model.isSavingPrefs) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    }
                    when (NotificationTwoLayer.headerAction(permission)) {
                        NotificationHeaderAction.RequestPermission -> Button(
                            onClick = model::requestPermission,
                            enabled = !model.isRequestingPermission,
                            modifier = Modifier.fillMaxWidth().testTag(NotificationTags.ENABLE),
                        ) { Text(NotificationTwoLayer.enableLabel) }
                        NotificationHeaderAction.OpenSystemSettings -> FilledTonalButton(
                            onClick = model::openSystemSettings,
                            modifier = Modifier.fillMaxWidth().testTag(NotificationTags.OPEN_SYSTEM),
                        ) { Text(MeText.openSystemSettings) }
                        null -> {}
                    }
                }
            }
            rows.forEachIndexed { index, row ->
                val isLast = index == rows.lastIndex && !showsUnknown && model.prefsNotice == null
                GroupRow(divider = if (isLast) RowDivider.None else RowDivider.Card, minHeight = AingDimens.rowHeightTwoLine) {
                    NotificationKindRow(row, onToggle = { model.setEnabled(row.kind, it) }, onOpenChannel = { model.openChannelSettings(row.kind) })
                }
            }
            if (showsUnknown) {
                GroupRow(divider = if (model.prefsNotice == null) RowDivider.None else RowDivider.Card) {
                    InlineNotice(MeText.pushPrefsUnknown, NoticeKind.Info)
                }
            }
            model.prefsNotice?.let { notice ->
                GroupRow(divider = RowDivider.None) { InlineNotice(notice, NoticeKind.Error) }
            }
        }
    }
}

object NotificationTags {
    const val ENABLE = "notification-enable"
    const val OPEN_SYSTEM = "notification-open-system"
    fun row(raw: String) = "notification-row:$raw"
    fun systemBlocked(raw: String) = "notification-system-blocked:$raw"
}

@Composable
private fun NotificationKindRow(row: NotificationRowState, onToggle: (Boolean) -> Unit, onOpenChannel: () -> Unit) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth().testTag(NotificationTags.row(row.kind.raw)), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (row.hasAppToggle) {
            ToggleRow(row.kind.title, row.detail, checked = row.appOn, enabled = row.appEnabled, onCheckedChange = onToggle)
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(row.kind.title, style = MaterialTheme.typography.bodyLarge, color = colors.label)
                row.detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.label2) }
            }
        }
        if (row.systemBlocked) {
            Row(
                Modifier.fillMaxWidth().testTag(NotificationTags.systemBlocked(row.kind.raw)),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                AingIcon(AppIcon.NotificationsOffFill, contentDescription = null, size = 16.dp, tint = colors.pending)
                Text(
                    if (row.kind.raw == "work_check") "${NotificationTwoLayer.systemBlockedLabel} — ${NotificationTwoLayer.workCheckBlockedNote}" else NotificationTwoLayer.systemBlockedLabel,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.pending,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = onOpenChannel, modifier = Modifier.heightIn(min = AingDimens.minimumTarget)) { Text(NotificationTwoLayer.openChannelSettingsLabel) }
            }
        }
    }
}
