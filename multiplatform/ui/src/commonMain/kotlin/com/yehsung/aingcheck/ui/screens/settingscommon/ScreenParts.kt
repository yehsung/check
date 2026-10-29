// 원본: Sources/CheckMobileKit/Components/MobileComponents.swift @ 3bd04bd (InsetGroup · GroupRow · SectionHeader · InlineNotice · LoadFailureRow · LoadingRow · AingChip — 이름·치수만)
//
// W3-b 화면(순위 · 나 · 설정 · 계정 삭제)이 같이 쓰는 작은 부품. iOS 의 공용 부품(MobileComponents)과 같은 치수 · 같은 뜻 색이다.
// 판정은 품지 않는다(E§3 끝 — Composable 은 그리기만). 색은 AingTheme.colors 로만 받는다(D5 · G §8-15).
// W3-a 도 같은 이름의 부품을 자기 패키지에 둘 수 있다 — 두 벌은 8차 접기(c-fold) 몫이다(§8-18 9).
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 인셋 그룹 한 장(카드 면 · 모서리 22). 안의 행이 구분선을 스스로 긋는다. */
@Composable
fun InsetGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .background(AingTheme.colors.surface, RoundedCornerShape(AingDimens.groupRadius)),
        content = content,
    )
}

/** 행 아래 구분선: 없음 · 시작 여백만큼 들여 긋기. */
sealed interface RowDivider {
    data object None : RowDivider
    data class Inset(val start: Dp) : RowDivider

    companion object {
        /** 카드 안쪽 여백만큼 들인 기본 구분선. */
        val Card: RowDivider = Inset(AingDimens.cardPadding)
    }
}

/** 그룹 안 행 한 줄. 최소 높이 44(한 줄) · 56(두 줄). */
@Composable
fun GroupRow(
    modifier: Modifier = Modifier,
    divider: RowDivider = RowDivider.Card,
    minHeight: Dp = AingDimens.rowHeight,
    padding: PaddingValues = PaddingValues(horizontal = AingDimens.cardPadding, vertical = 10.dp),
    onClick: (() -> Unit)? = null,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = AingTheme.colors
    Column(modifier.fillMaxWidth()) {
        val click = if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier
        Row(
            Modifier.fillMaxWidth().then(click).heightIn(min = minHeight).padding(padding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
            content = content,
        )
        if (divider is RowDivider.Inset) {
            Box(
                Modifier
                    .padding(start = divider.start)
                    .fillMaxWidth()
                    .heightIn(min = AingDimens.hairline, max = AingDimens.hairline)
                    .background(colors.separator),
            )
        }
    }
}

/** 절 머리(19~20 bold · 좌우 20 — 카드 여백 16 안에서 4 더 들인다). */
@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier, trailing: (@Composable RowScope.() -> Unit)? = null) {
    Row(
        modifier
            .fillMaxWidth()
            .padding(start = AingDimens.titleMargin - AingDimens.sideMargin, end = AingDimens.titleMargin - AingDimens.sideMargin, top = AingDimens.space3),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.titleLarge,
            color = AingTheme.colors.label,
            modifier = Modifier.weight(1f).semantics { heading() },
        )
        if (trailing != null) trailing()
    }
}

/** 안내 한 줄의 뜻(색이 뜻이다). */
enum class NoticeKind { Info, Warning, Error }

/** 안내 한 줄(기호 + 글자). 경고 = 앰버 · 오류 = 빨강 · 안내 = 회색. */
@Composable
fun InlineNotice(text: String, kind: NoticeKind, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val (icon, tint) = when (kind) {
        NoticeKind.Info -> AppIcon.InfoFill to colors.label2
        NoticeKind.Warning -> AppIcon.WarningFill to colors.pending
        NoticeKind.Error -> AppIcon.ErrorFill to colors.danger
    }
    Row(
        modifier.fillMaxWidth().padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.Top,
    ) {
        AingIcon(icon, contentDescription = null, size = 16.dp, tint = tint, modifier = Modifier.padding(top = 1.dp))
        Text(text, style = MaterialTheme.typography.bodySmall, color = if (kind == NoticeKind.Info) colors.label2 else tint)
    }
}

/** 조회 실패 한 줄 + [다시 시도](누름 영역 44). [isRetrying] 이면 단추 대신 돌이. */
@Composable
fun LoadFailureRow(text: String, retryLabel: String, isRetrying: Boolean = false, modifier: Modifier = Modifier, onRetry: () -> Unit) {
    val colors = AingTheme.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        AingIcon(AppIcon.WarningFill, contentDescription = null, size = 16.dp, tint = colors.pending)
        Text(text, style = MaterialTheme.typography.bodySmall, color = colors.label2, modifier = Modifier.weight(1f))
        if (isRetrying) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
        } else {
            TextButton(onClick = onRetry, modifier = Modifier.heightIn(min = AingDimens.minimumTarget)) { Text(retryLabel) }
        }
    }
}

/** 불러오는 중 한 줄(돌이 + 글자). */
@Composable
fun LoadingRow(text: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
        Text(text, style = MaterialTheme.typography.bodyMedium, color = AingTheme.colors.label2)
    }
}

/** 작은 칩(11 semibold · 높이 20). [tint] 글자색 · [background] 바탕(null 이면 [tint] 의 옅은 칠). */
@Composable
fun AingChipLabel(text: String, tint: Color, background: Color? = null, modifier: Modifier = Modifier) {
    Box(
        modifier
            .background(background ?: tint.copy(alpha = 0.14f), CircleShape)
            .heightIn(min = 20.dp)
            .padding(horizontal = 8.dp, vertical = 2.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = MaterialTheme.typography.labelSmall, color = tint, maxLines = 1, overflow = TextOverflow.Clip)
    }
}

/** 제목 + 아래 한 줄 + 스위치(M3 Switch — 주요색 파랑, G §8-15). [enabled] 가 거짓이면 흐린 꺼진 모양. */
@Composable
fun ToggleRow(
    title: String,
    detail: String?,
    checked: Boolean,
    enabled: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = AingTheme.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = colors.label)
            if (detail != null) Text(detail, style = MaterialTheme.typography.bodySmall, color = colors.label2)
        }
        Spacer(Modifier.width(AingDimens.space2))
        Switch(checked = checked, onCheckedChange = if (enabled) onCheckedChange else null, enabled = enabled)
    }
}

/** 오른쪽 › 가 붙은 목록 행 글자(행 전체가 누름 영역이다 — GroupRow 의 onClick). */
@Composable
fun RowScope.ChevronRowContent(
    title: String,
    detail: String? = null,
    titleColor: Color = AingTheme.colors.label,
    trailingIcon: AppIcon = AppIcon.ChevronRight,
) {
    val colors = AingTheme.colors
    Text(title, style = MaterialTheme.typography.bodyLarge, color = titleColor, modifier = Modifier.weight(1f))
    if (detail != null) Text(detail, style = MaterialTheme.typography.bodyMedium, color = colors.label2, maxLines = 1)
    AingIcon(trailingIcon, contentDescription = null, size = 16.dp, tint = colors.label3)
}

/** 큰 제목(34 bold) + 선택 부제(15 보조 글자). 화면 맨 위 첫 줄 — 스크롤하면 같이 올라간다. */
@Composable
fun LargeTitle(title: String, subtitle: String? = null, modifier: Modifier = Modifier, trailing: (@Composable RowScope.() -> Unit)? = null) {
    val colors = AingTheme.colors
    Column(modifier.fillMaxWidth().padding(horizontal = AingDimens.titleMargin - AingDimens.sideMargin)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                title,
                style = MaterialTheme.typography.headlineLarge,
                color = colors.label,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            if (trailing != null) trailing()
        }
        if (subtitle != null) {
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = colors.label2, modifier = Modifier.padding(top = 1.dp))
        }
    }
}

/** 굵은 글자 무게(숫자 칸). */
internal val SemiBold: FontWeight = FontWeight.SemiBold

// ---------------------------------------------------------------- 사람 부품(원본: Sources/CheckMobileKit/Components/PersonComponents.swift @ 3bd04bd)

/** 센터 배지(서버값 → "서울"·"부산"). 모르는 값이면 아무것도 그리지 않는다. */
@Composable
fun CenterBadge(serverValue: String?, modifier: Modifier = Modifier) {
    val label = com.yehsung.aingcheck.core.wire.CenterLabel.display(serverValue) ?: return
    val colors = AingTheme.colors
    Box(
        modifier
            .background(colors.fill, CircleShape)
            .heightIn(min = 18.dp)
            .padding(horizontal = 6.dp)
            .semantics { contentDescription = "${label}센터" },
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = MaterialTheme.typography.labelSmall, color = colors.label2, maxLines = 1)
    }
}

/** 이니셜 원(해시색 틴트 원 + 진한 글자). [colorSeed] 가 없으면 이름으로 색을 고른다. */
@Composable
fun InitialAvatar(name: String, size: Dp, modifier: Modifier = Modifier, colorSeed: String = name) {
    val (ink, tint) = AingTheme.colors.avatar(colorSeed)
    Box(modifier.size(size).background(tint, CircleShape), contentAlignment = Alignment.Center) {
        Text(
            PersonInitial.of(name),
            color = ink,
            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold, fontSize = androidx.compose.ui.unit.TextUnit(size.value * 0.44f, androidx.compose.ui.unit.TextUnitType.Sp)),
            maxLines = 1,
        )
    }
}

/** 이니셜 한 글자(Swift `InitialAvatar.initial(of:)` — 앞뒤 공백을 걷고 첫 글자, 비면 "?"). */
object PersonInitial {
    fun of(name: String): String {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return "?"
        // 첫 '글자'(서로게이트 짝을 쪼개지 않는다).
        val pair = trimmed.length >= 2 && trimmed[0].isHighSurrogate() && trimmed[1].isLowSurrogate()
        return trimmed.substring(0, if (pair) 2 else 1)
    }
}
