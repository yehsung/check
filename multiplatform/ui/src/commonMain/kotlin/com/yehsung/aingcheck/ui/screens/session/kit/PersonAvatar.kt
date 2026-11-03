// 원본: Sources/CheckMobileKit/Components/PersonComponents.swift @ 3bd04bd (AppUserAvatarFace · PersonCharacterFace · StatusDot · PersonAvatar · PersonName · InitialAvatar)
//
// 사람 얼굴: ① 올린 사진 → ② 그 사람의 착용 캐릭터(neutral 초상 · 원형) → ③ 캐릭터를 **모를 때만** 이니셜(판정 정본은 와이어
// `AppUserCharacterDirectory.avatar`). 사진을 불러오는 중이거나 실패하면 이니셜이 아니라 캐릭터로 떨어진다(`afterPhotoFailure`).
// 호출부는 **사용자 id** 만 넘긴다 — 표는 조립이 [LocalAppUserCharacters] 로 흘린다(없으면 빈 표 = 이니셜).
package com.yehsung.aingcheck.ui.screens.session.kit

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.text.Graphemes
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.stores.messages.MessagesFocusText
import com.yehsung.aingcheck.core.stores.messages.PresenceStatus
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.models.AppUserAvatar
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterDirectory
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.math.max
import kotlin.math.roundToInt

/** 착용 캐릭터 표(조립이 `AppUserCharacterStore.directory` 를 흘린다). 기본은 빈 표 — 모두 이니셜이다. */
val LocalAppUserCharacters = compositionLocalOf { AppUserCharacterDirectory(CharacterArt.portraitIds) }

/** 근무 점 색(초록 · 앰버 · 청회색). */
@Composable
fun presenceDotColor(status: PresenceStatus): Color = when (status) {
    PresenceStatus.working -> AingTheme.colors.workingDot
    PresenceStatus.pending -> AingTheme.colors.pendingDot
    PresenceStatus.off -> AingTheme.colors.offWorkDot
}

@Composable
fun StatusDot(status: PresenceStatus, size: Dp = 8.dp, modifier: Modifier = Modifier) {
    Box(modifier.size(size).background(presenceDotColor(status), CircleShape))
}

/** 이니셜 한 글자(앞뒤 공백 걷고 첫 글자 — 없으면 "?"). Swift `InitialAvatar.initial(of:)`. */
fun initialOf(name: String): String {
    val trimmed = TextScalars.trimmingWhitespacesAndNewlines(name)
    return if (trimmed.isEmpty()) "?" else Graphemes.clusters(trimmed).first()
}

/** 보이스오버(TalkBack) 문구: "소라, 근무 중" · "소라, 연결 끊김" · "소라". */
fun avatarDescription(name: String, status: PresenceStatus?): String = when (status) {
    PresenceStatus.working -> "$name, 근무 중"
    PresenceStatus.pending -> "$name, 연결 끊김"
    PresenceStatus.off, null -> name
}

/**
 * 사람 아바타 + 오른쪽 아래 근무 점(working·pending 만). [ringColor] 는 점 둘레 틈 색(아바타가 놓인 면).
 * [url] 은 서버가 준 사진 주소(없으면 캐릭터 → 이니셜).
 */
@Composable
fun PersonAvatar(
    name: String,
    userID: String?,
    url: String?,
    size: Dp,
    modifier: Modifier = Modifier,
    status: PresenceStatus? = null,
    ringColor: Color = AingTheme.colors.surface,
    characterHint: String? = null,
) {
    val directory = LocalAppUserCharacters.current
    val avatar = directory.avatar(userID, url?.let { SwiftURL.parse(it) }, characterHint)
    Box(modifier.size(size).clearAndSetSemantics { contentDescription = avatarDescription(name, status) }) {
        AvatarFace(avatar, name, size)
        if (status != null && status != PresenceStatus.off) {
            val dot = min(13.dp, max(9f, size.value * 0.3f).dp)
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .offset(1.dp, 1.dp)
                    .size(dot + 4.dp)
                    .background(ringColor, CircleShape),
                contentAlignment = Alignment.Center,
            ) { StatusDot(status, dot) }
        }
    }
}

/** 얼굴만(사진 → 캐릭터 → 이니셜). */
@Composable
fun AvatarFace(avatar: AppUserAvatar, name: String, size: Dp, colorSeed: String = name) {
    when (avatar) {
        is AppUserAvatar.Photo -> {
            val art = LocalScreenArt.current
            val photo = rememberCached(art.photos, avatar.url.absoluteString)
            if (photo != null) PhotoFace(photo, size) else StillFace(avatar.afterPhotoFailure, name, size, colorSeed)
        }
        else -> StillFace(avatar, name, size, colorSeed)
    }
}

@Composable
private fun StillFace(avatar: AppUserAvatar, name: String, size: Dp, colorSeed: String) {
    if (avatar is AppUserAvatar.Character) CharacterFace(avatar.id, size) else InitialFace(name, size, colorSeed)
}

@Composable
private fun PhotoFace(photo: ImageBitmap, size: Dp) {
    Canvas(Modifier.size(size).clip(CircleShape)) {
        // 가운데를 잘라 원을 채운다(scaledToFill).
        val side = minOf(photo.width, photo.height)
        val srcOffset = IntOffset((photo.width - side) / 2, (photo.height - side) / 2)
        drawImage(
            photo, srcOffset, IntSize(side, side), IntOffset.Zero,
            IntSize(this.size.width.roundToInt(), this.size.height.roundToInt()), filterQuality = FilterQuality.Medium,
        )
    }
}

/** 착용 캐릭터 얼굴(surface2 원 위 neutral 초상 88% · 아래로 5%). */
@Composable
fun CharacterFace(id: String, size: Dp) {
    val surface2 = AingTheme.colors.surface2
    val art = rememberCharacterFace(id)
    Canvas(Modifier.size(size).clip(CircleShape)) {
        drawCircle(surface2)
        if (art != null) {
            val side = this.size.minDimension * 0.88f
            val dx = (this.size.width - side) / 2f
            val dy = (this.size.height - side) / 2f + this.size.height * 0.05f
            drawImage(
                art, IntOffset.Zero, IntSize(art.width, art.height), IntOffset(dx.roundToInt(), dy.roundToInt()),
                IntSize(side.roundToInt(), side.roundToInt()), filterQuality = FilterQuality.Medium,
            )
        }
    }
}

/** 이니셜 원(해시 색 — 맥 `avatarColor(for:)` 와 같은 규칙). */
@Composable
fun InitialFace(name: String, size: Dp, colorSeed: String = name) {
    val (ink, tint) = AingTheme.colors.avatar(colorSeed)
    Box(Modifier.size(size).background(tint, CircleShape), contentAlignment = Alignment.Center) {
        Text(initialOf(name), style = TextStyle(fontSize = (size.value * 0.44f).sp, fontWeight = FontWeight.Bold), color = ink, maxLines = 1)
    }
}

/**
 * 이름 + 이름 뒤 센터 배지("서울") · '나' 칩([isMe]) · '집중' 칩([focusChip] — 판 7, null 이면 없음). 이름이 넘치면 꼬리 줄임.
 * [stacked] 는 큰 글자 줄 — 배지가 이름 아랫줄로 내려가고 이름은 꺾인다(Swift `PersonName.stacked`).
 */
@Composable
fun PersonName(
    name: String,
    center: String?,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.titleSmall,
    color: Color = AingTheme.colors.label,
    isMe: Boolean = false,
    stacked: Boolean = false,
    focusChip: String? = null,
) {
    val centerText = CenterLabel.display(center)
    if (stacked) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(name, style = style, color = color)
            if (centerText != null || isMe || focusChip != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    centerText?.let { CenterChip(it) }
                    if (isMe) MeChip()
                    focusChip?.let { FocusChip(it) }
                }
            }
        }
    } else {
        Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(name, style = style, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            centerText?.let { CenterChip(it) }
            if (isMe) MeChip()
            focusChip?.let { FocusChip(it) }
        }
    }
}

/**
 * 집중 칩(판 7 · 대표 요청 5 "콕/메세지 창에서부터 집중 모드인 사람들은 표시") — 보라(`aiToken`) 글자 + 같은 빛 테두리. 맥 콕 목록 '집중' 칩 ·
 * 대화 머리 '집중 중' 칩 · iOS 1.0.17 `FocusChip` 과 같은 색 계열이다.
 *
 * **테두리형인 까닭**(iOS 와 같은 계산): 칠한 칩(글자 색 14% 바탕)이면 라이트에서 글자가 4.3:1 로 4.5:1 에 못 미친다(aiToken #7A4FE0).
 * 테두리형은 글자가 줄 바탕(흰 카드 · 유리 이름표) 위에 바로 앉는다. 다크는 aiToken 다크값(밝은 보라)이라 넉넉하다.
 *
 * **한 조각으로 둔다**: 사람 줄 셋(새 대화 시트 · 메시지 탭 대화 목록 · 지금 탭 근무 중 — `PersonName(focusChip = personFocusChip(..))`)과
 * 대화 이름표가 이 부품 하나를 부른다(대표 답 #d_6A32rmcoJZZd "말 걸 수 있는 줄 전부" · 글자는 코어 `MessagesFocusText`). 얼굴 띠는 칩 없이 TalkBack 만 잇는다.
 * TalkBack: 줄을 한 덩이로 읽는 자리(clearAndSetSemantics — 새 대화 · 대화 목록 · 이름표)는 줄이 자기 문장에 `MessagesFocusText.accessibility` 를 잇는다
 * (그 자리에서는 이 칩의 의미가 지워진다). 줄의 조각을 하나씩 읽는 자리(지금 탭 근무 중 줄)는 이 칩이 "집중"이 아니라 "집중 중"으로 읽힌다
 * (iOS 1.0.17 1776440d `FocusChip.accessibilityLabel` 과 같은 꼴).
 */
@Composable
fun FocusChip(text: String, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Box(
        modifier
            .heightIn(min = 18.dp)
            .border(1.dp, colors.aiToken, CircleShape)
            .padding(horizontal = 6.dp)
            .clearAndSetSemantics { contentDescription = MessagesFocusText.accessibility },
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = MaterialTheme.typography.labelSmall, color = colors.aiToken, maxLines = 1)
    }
}

/**
 * 사람 줄 이름 뒤 칩 글자 — 집중 중이면 '집중' 하나(아니면 null = 칩 없음). 사람 줄 셋(새 대화 시트 · 메시지 탭 대화 목록 · 지금 탭 근무 중)이
 * 이것 하나를 부른다(iOS 1.0.17 `PersonName.focusChips` 의 Android 짝).
 */
fun personFocusChip(isFocused: Boolean): String? = if (isFocused) MessagesFocusText.personChip else null

/** '나' 칩(Swift `MeChip` — 파랑 틴트 · 높이 18). */
@Composable
fun MeChip() {
    val colors = AingTheme.colors
    Box(
        Modifier.heightIn(min = 18.dp).background(colors.accentTint, CircleShape).padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text("나", style = MaterialTheme.typography.labelSmall, color = colors.accent, maxLines = 1)
    }
}

/** 센터 배지(회색 칩 11pt). */
@Composable
fun CenterChip(text: String) {
    val colors = AingTheme.colors
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        color = colors.label2,
        modifier = Modifier
            .background(colors.fill, RoundedCornerShape(6.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}
