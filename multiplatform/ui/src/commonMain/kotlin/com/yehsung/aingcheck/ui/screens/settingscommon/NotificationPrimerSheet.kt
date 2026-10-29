// 원본: Sources/CheckMobileKit/Push/PushPermissionPrimerView.swift @ 3bd04bd (알림 권한 설명 시트 — 종 든 아잉 · 가운데 제목 · 알림 종류 인셋 그룹 · 아래 막대 [알림 켜기] + [나중에])
//
// 시스템 권한 창은 한 번만 뜨므로 무엇을 알려 주는지 먼저 말하고 고르게 한다(SPEC-ios §5 "설명 시트 먼저").
// **글자와 종류 표는 받는다** — 푸시 문구(PhonePushText)와 종류(PhonePushKind · 이름 · 설명)는 W2-f feature/phone 의 것이고(ui 는 그 모듈을 못 본다),
// 같은 글자를 이 갈래에 또 적으면 두 벌이 된다. 조립(K11)이 [NotificationPrimerContent] 를 그 상수로 채운다(assembly.md). 기호만 이 갈래가 고른다.
// 기호 원은 모두 파랑 틴트 — 종류를 색으로 가르지 않는다(초록·보라는 근무·AI 토큰 뜻이라 쓰지 않는다).
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.CharacterPortrait
import com.yehsung.aingcheck.ui.components.PortraitBadge
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 설명 시트가 말할 것(조립이 W2-f PhonePushText · PhonePushKind 로 채운다). */
data class NotificationPrimerContent(
    val title: String,
    val body: String,
    val macNote: String,
    val settingsNote: String,
    val allow: String,
    val later: String,
    /** 알림 종류 줄(서버 kind 글자 · 이름 · 설명). 순서는 받은 그대로. */
    val kinds: List<Kind>,
) {
    data class Kind(val raw: String, val title: String, val detail: String)
}

object NotificationPrimerTags {
    const val ALLOW = "primer-allow"
    const val LATER = "primer-later"
    fun kind(raw: String) = "primer-kind:$raw"
}

/** 종류 → 기호(Swift `PushKind.systemImage` · Android 에만 있는 체스 신청은 체스 기호). 모르는 종류는 종. */
object NotificationPrimerIcons {
    fun of(raw: String): AppIcon = when (raw) {
        "message" -> AppIcon.ChatBubbleFill
        "gomoku_invite" -> AppIcon.AppsFill
        "chess_invite" -> AppIcon.Chess
        "feedback_reply" -> AppIcon.DraftsFill
        "work_check" -> AppIcon.ScheduleFill
        else -> AppIcon.NotificationsFill
    }

    /** 원 36 + 간격 12 + 좌 16 = 글자 시작점(구분선 시작). */
    const val TEXT_LEADING = 64
}

/**
 * @param isRequesting 권한 창이 떠 있는 동안 두 단추를 막는다(두 번 눌러 두 번 묻지 않게).
 */
@Composable
fun NotificationPrimerSheet(
    content: NotificationPrimerContent,
    isRequesting: Boolean,
    onAllow: () -> Unit,
    onLater: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = AingTheme.colors
    Column(modifier.fillMaxSize().background(colors.background)) {
        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.space4),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 520.dp).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                CharacterPortrait(
                    LocalScreenArt.current.portrait("aing", null),
                    CharacterMood.Plain,
                    88.dp,
                    badge = PortraitBadge.Symbol(AppIcon.NotificationsFill),
                    ringGap = colors.background,
                    framed = false,
                )
                Spacer(Modifier.height(AingDimens.space4))
                Text(
                    content.title,
                    style = MaterialTheme.typography.titleLarge,
                    color = colors.label,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.semantics { heading() },
                )
                Spacer(Modifier.height(AingDimens.space2))
                Text(content.body, style = MaterialTheme.typography.bodyLarge, color = colors.label2, textAlign = TextAlign.Center)
                Spacer(Modifier.height(AingDimens.space6))
                InsetGroup {
                    content.kinds.forEachIndexed { index, kind ->
                        GroupRow(
                            divider = if (index == content.kinds.lastIndex) RowDivider.None else RowDivider.Inset(NotificationPrimerIcons.TEXT_LEADING.dp),
                            minHeight = 60.dp,
                            modifier = Modifier.testTag(NotificationPrimerTags.kind(kind.raw)),
                        ) {
                            AingIcon(
                                NotificationPrimerIcons.of(kind.raw),
                                contentDescription = null,
                                size = 18.dp,
                                tint = colors.accent,
                                modifier = Modifier.size(36.dp).background(colors.accentTint, CircleShape).padding(9.dp),
                            )
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(kind.title, style = MaterialTheme.typography.bodyLarge, color = colors.label)
                                Text(kind.detail, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                            }
                        }
                    }
                }
                Column(
                    Modifier.fillMaxWidth().padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin).padding(top = AingDimens.space3),
                    verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
                ) {
                    PrimerNote(AppIcon.DesktopWindows, content.macNote)
                    PrimerNote(AppIcon.Settings, content.settingsNote)
                }
            }
        }
        // 아래 막대: 채운 [알림 켜기] 하나 + 글자 [나중에].
        Column(
            Modifier.fillMaxWidth().background(colors.background).padding(horizontal = AingDimens.sideMargin).padding(top = AingDimens.space3, bottom = AingDimens.space2),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(AingDimens.space1),
        ) {
            AingButton(content.allow, AingButtonKind.Filled, onClick = onAllow, enabled = !isRequesting, fillsWidth = true, modifier = Modifier.widthIn(max = 520.dp).testTag(NotificationPrimerTags.ALLOW))
            AingButton(content.later, AingButtonKind.Plain, onClick = onLater, enabled = !isRequesting, fillsWidth = true, modifier = Modifier.widthIn(max = 520.dp).testTag(NotificationPrimerTags.LATER))
        }
    }
}

@Composable
private fun PrimerNote(icon: AppIcon, text: String) {
    val colors = AingTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
        AingIcon(icon, contentDescription = null, size = 14.dp, tint = colors.label2, modifier = Modifier.padding(top = 2.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = colors.label2)
    }
}
