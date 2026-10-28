// 원본: Sources/CheckMobileKit/Components/AingButtons.swift @ 3bd04bd (AingButtonStyle · AingButtonMetrics — 크기 50·40·30, 좌우 22·18·13, 누름 44)
// 원본: Sources/CheckMobileKit/Components/MobileComponents.swift @ 3bd04bd (AingCard · InlineNotice · LoadFailureRow · LoadingRow)
// 원본: Sources/CheckMobileKit/Components/InsetGroup.swift @ 3bd04bd (InsetGroup · GroupRow · SectionHeader · ProgressBar)
// 원본: Sources/CheckMobileKit/Components/SheetChrome.swift @ 3bd04bd (SheetHeader)
//
// 상점 · 뽑기 · 미션 · 이번 주 근무 화면이 같이 쓰는 작은 부품(이 갈래 안 — ui/components 는 조정자 몫이라 여기 둔다).
// 화면 갈래(W3-b)에도 같은 부품이 생길 수 있다 — 두 벌이면 다음 접기(c-fold)에서 ui/components 로 모은다(보고에 적는다).
// 색은 AingTheme.colors(iOS 토큰), 단추 골격은 iOS 크기 그대로. 글자는 M3 역할(Pretendard)에 iOS 스타일을 앉힌 것.
package com.yehsung.aingcheck.ui.shop

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** iOS 글자 스타일 → M3 역할(AingTypeScale 표). */
object MeType {
    val headline: TextStyle @Composable get() = MaterialTheme.typography.titleMedium
    val body: TextStyle @Composable get() = MaterialTheme.typography.bodyLarge
    val callout: TextStyle @Composable get() = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Normal)
    val rowTitle: TextStyle @Composable get() = MaterialTheme.typography.titleSmall
    val subheadline: TextStyle @Composable get() = MaterialTheme.typography.bodyMedium
    val footnote: TextStyle @Composable get() = MaterialTheme.typography.bodySmall
    val caption: TextStyle @Composable get() = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Normal)
    val caption2: TextStyle @Composable get() = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal)
    val title2: TextStyle @Composable get() = MaterialTheme.typography.headlineSmall
    val title3: TextStyle @Composable get() = MaterialTheme.typography.titleLarge

    /** 숫자(고정폭 숫자 — iOS monospacedDigit). */
    fun TextStyle.digits(): TextStyle = copy(fontFeatureSettings = "tnum")
    fun TextStyle.weight(w: FontWeight): TextStyle = copy(fontWeight = w)
}

enum class MeButtonKind { Filled, Tinted, Gray, Plain, Destructive }

enum class MeButtonSize(val height: Dp, val horizontalPadding: Dp) {
    Lg(50.dp, 22.dp),
    Md(40.dp, 18.dp),
    Sm(30.dp, 13.dp),
}

/**
 * iOS `AingButton`(캡슐). 비활성은 라이트·다크 모두 회색 판(fill2) + 보조 글자(label2) — 흐리게만 하면 옅은 파랑 판 위 흰 글자가 안 보인다.
 * 누름 영역은 보이는 높이와 상관없이 44 이상.
 */
@Composable
fun MeButton(
    text: String,
    modifier: Modifier = Modifier,
    icon: AppIcon? = null,
    kind: MeButtonKind = MeButtonKind.Filled,
    size: MeButtonSize = MeButtonSize.Lg,
    fillsWidth: Boolean = false,
    isBusy: Boolean = false,
    enabled: Boolean = true,
    contentDescription: String? = null,
    onClick: () -> Unit,
) {
    MeButtonFrame(modifier, kind, size, fillsWidth, enabled = enabled && !isBusy, contentDescription = contentDescription, onClick = onClick) { fg ->
        if (isBusy) {
            CircularProgressIndicator(Modifier.size(16.dp), color = fg, strokeWidth = 2.dp)
        } else {
            if (icon != null) AingIcon(icon, contentDescription = null, size = 18.dp, tint = fg)
            Text(text, style = buttonStyle(size), color = fg, maxLines = 2, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun buttonStyle(size: MeButtonSize): TextStyle = when (size) {
    MeButtonSize.Lg -> MeType.body.copy(fontWeight = FontWeight.SemiBold)
    MeButtonSize.Md -> MeType.callout.copy(fontWeight = FontWeight.SemiBold)
    MeButtonSize.Sm -> MeType.subheadline.copy(fontWeight = FontWeight.SemiBold)
}

/** 단추 골격(바탕 · 높이 · 누름 영역). [content] 는 글자 색을 받는다. */
@Composable
fun MeButtonFrame(
    modifier: Modifier,
    kind: MeButtonKind,
    size: MeButtonSize,
    fillsWidth: Boolean,
    enabled: Boolean,
    contentDescription: String? = null,
    onClick: () -> Unit,
    content: @Composable RowScope.(Color) -> Unit,
) {
    val c = AingTheme.colors
    val disabledFill = !enabled && kind != MeButtonKind.Plain
    val fg = if (disabledFill) c.label2 else when (kind) {
        MeButtonKind.Filled -> c.onAccentFill
        MeButtonKind.Tinted, MeButtonKind.Plain -> c.accent
        MeButtonKind.Gray -> c.label
        MeButtonKind.Destructive -> c.danger
    }
    val bg = if (disabledFill) c.fill2 else when (kind) {
        MeButtonKind.Filled -> c.accentFill
        MeButtonKind.Tinted -> c.accentTint
        MeButtonKind.Gray -> c.fill
        MeButtonKind.Plain -> Color.Transparent
        MeButtonKind.Destructive -> c.dangerTint
    }
    Box(
        modifier
            .heightIn(min = maxOf(size.height, AingDimens.minimumTarget))
            .then(if (fillsWidth) Modifier.fillMaxWidth() else Modifier)
            .clip(CircleShape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .then(if (contentDescription != null) Modifier.clearAndSetSemantics { this.contentDescription = contentDescription } else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier
                .then(if (fillsWidth) Modifier.fillMaxWidth() else Modifier)
                .defaultMinSize(minHeight = size.height)
                .background(bg, CircleShape)
                .padding(horizontal = size.horizontalPadding, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) { content(fg) }
    }
}

/** iOS `AingCard`: 표면 판(모서리 22) + 안쪽 16 + 줄 사이 12. */
@Composable
fun MeCard(modifier: Modifier = Modifier, padding: Dp = AingDimens.cardPadding, spacing: Dp = AingDimens.rowSpacing, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .background(AingTheme.colors.surface, RoundedCornerShape(AingDimens.groupRadius))
            .padding(padding),
        verticalArrangement = Arrangement.spacedBy(spacing),
        content = content,
    )
}

/** iOS `InsetGroup`: 줄 묶음 판(모서리 22, 자른다). */
@Composable
fun MeInsetGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AingDimens.groupRadius))
            .background(AingTheme.colors.surface),
        content = content,
    )
}

/** iOS `GroupRow`: 최소 44 · 좌우 16 · 위아래 10, 아래 구분선은 [dividerInset](null = 없음). */
@Composable
fun MeGroupRow(
    modifier: Modifier = Modifier,
    dividerInset: Dp? = AingDimens.cardPadding,
    minHeight: Dp = AingDimens.rowHeight,
    verticalPadding: Dp = 10.dp,
    content: @Composable RowScope.() -> Unit,
) {
    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = minHeight)
                .padding(horizontal = AingDimens.cardPadding, vertical = verticalPadding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
            content = content,
        )
        if (dividerInset != null) {
            Box(Modifier.padding(start = dividerInset).fillMaxWidth().height(AingDimens.hairline).background(AingTheme.colors.separator))
        }
    }
}

/** iOS `SectionHeader`: 제목(섹션 머리) + 오른쪽 보조 글자. */
@Composable
fun MeSectionHeader(title: String, trailing: String? = null, modifier: Modifier = Modifier) {
    val c = AingTheme.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MeType.title3, color = c.label, modifier = Modifier.weight(1f).semantics { heading() })
        if (trailing != null) Text(trailing, style = MeType.subheadline, color = c.label2)
    }
}

/** iOS `ProgressBar`(accent · done) — 높이 6, 가는 막대 4. 채움은 높이보다 작아지지 않는다. */
@Composable
fun MeProgressBar(fraction: Double, done: Boolean, thin: Boolean = false, modifier: Modifier = Modifier) {
    val c = AingTheme.colors
    val clamped = if (fraction.isNaN()) 0.0 else fraction.coerceIn(0.0, 1.0)
    val height = if (thin) 4.dp else 6.dp
    Box(modifier.fillMaxWidth().height(height).clip(CircleShape).background(c.fill)) {
        if (clamped > 0) {
            Box(
                Modifier
                    .fillMaxWidth(clamped.toFloat())
                    .defaultMinSize(minWidth = height)
                    .height(height)
                    .background(if (done) c.workingDot else c.accentFill, CircleShape),
            )
        }
    }
}

/** iOS `SheetHeader`: 가운데 제목(+ 부제) · 왼쪽 위 ✕. */
@Composable
fun MeSheetHeader(title: String, subtitle: String? = null, closeEnabled: Boolean = true, onClose: () -> Unit) {
    val c = AingTheme.colors
    Box(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = AingDimens.sideMargin)) {
        Box(
            Modifier
                .align(Alignment.CenterStart)
                .size(AingDimens.minimumTarget)
                .clip(CircleShape)
                .clickable(enabled = closeEnabled, role = Role.Button, onClick = onClose)
                .semantics { contentDescription = "닫기" },
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(30.dp).background(c.fill, CircleShape), contentAlignment = Alignment.Center) {
                AingIcon(AppIcon.Close, contentDescription = null, size = 18.dp, tint = if (closeEnabled) c.label2 else c.label3)
            }
        }
        if (title.isNotEmpty() || subtitle != null) {
            Column(
                Modifier.align(Alignment.Center).padding(horizontal = AingDimens.minimumTarget + AingDimens.space3).semantics(mergeDescendants = true) { heading() },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp),
            ) {
                Text(title, style = MeType.headline, color = c.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (subtitle != null) Text(subtitle, style = MeType.caption, color = c.label2, maxLines = 1)
            }
        }
    }
}

enum class MeNoticeKind { Info, Warning, Error }

/** iOS `InlineNotice`: 기호 + 한 줄(info 파랑 · warning 앰버 · error 빨강). */
@Composable
fun MeInlineNotice(text: String, kind: MeNoticeKind = MeNoticeKind.Info, modifier: Modifier = Modifier) {
    val c = AingTheme.colors
    val tint = when (kind) {
        MeNoticeKind.Info -> c.accent
        MeNoticeKind.Warning -> c.pending
        MeNoticeKind.Error -> c.danger
    }
    val icon = when (kind) {
        MeNoticeKind.Info -> AppIcon.InfoFill
        MeNoticeKind.Warning -> AppIcon.WarningFill
        MeNoticeKind.Error -> AppIcon.DangerousFill
    }
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
        AingIcon(icon, contentDescription = null, size = 16.dp, tint = tint, modifier = Modifier.padding(top = 1.dp))
        Text(text, style = MeType.footnote, color = c.label)
    }
}

/** iOS `LoadFailureRow`: 실패 한 줄 + [다시 시도](retry 가 null 이면 버튼 없이). */
@Composable
fun MeLoadFailureRow(text: String, isRetrying: Boolean = false, retry: (() -> Unit)?) {
    val c = AingTheme.colors
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        AingIcon(AppIcon.WarningFill, contentDescription = null, size = 16.dp, tint = c.pending)
        Text(text, style = MeType.footnote, color = c.label2, modifier = Modifier.weight(1f))
        if (retry != null) MeButton("다시 시도", kind = MeButtonKind.Tinted, size = MeButtonSize.Sm, isBusy = isRetrying, onClick = retry)
    }
}

/** iOS `LoadingRow`: 작은 돌림 + 한 줄. */
@Composable
fun MeLoadingRow(text: String) {
    val c = AingTheme.colors
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        CircularProgressIndicator(Modifier.size(14.dp), color = c.label2, strokeWidth = 2.dp)
        Text(text, style = MeType.footnote, color = c.label2)
    }
}

/** 둥근 칩(받침 + 좌우 여백) — 상태 칩 · 배지. */
@Composable
fun MeCapsule(background: Color, modifier: Modifier = Modifier, horizontal: Dp = 8.dp, minHeight: Dp = 20.dp, content: @Composable RowScope.() -> Unit) {
    Row(
        modifier.background(background, CircleShape).defaultMinSize(minHeight = minHeight).padding(horizontal = horizontal),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp), content = content,
    )
}

/** 너비만 차지하는 빈칸(Swift Spacer(minLength:) 대신 — Row 에서 weight 와 같이). */
@Composable
fun RowScope.MeFlexSpacer(min: Dp = 0.dp) {
    Spacer(Modifier.weight(1f).width(min))
}
