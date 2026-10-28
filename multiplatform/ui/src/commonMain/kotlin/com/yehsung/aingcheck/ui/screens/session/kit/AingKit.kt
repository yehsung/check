// 원본: Sources/CheckMobileKit/Components/MobileComponents.swift @ 3bd04bd (AingCard · InlineNotice · RetryButton · LoadFailureRow · LoadingRow · EmptyStateView)
// 원본: Sources/CheckMobileKit/Session/MobileSessionViews.swift @ 3bd04bd (MobileCenteredScreen · MobileBrandHeader · MobileLoginMetrics)
//
// 폰 화면 공용 부품(세션·지금·메시지 화면이 같이 쓴다 — W3-a). iOS 의 `Components/*`(기반 공용 부품)는 W1-e 디자인 시스템이 브랜드 부품만
// 옮겼고, 줄·단추·안내 같은 뼈대는 화면 갈래 몫으로 남았다. 여기 한 벌로 두고 W3-b·W4 가 쓰면 조정자가 ui/components 로 올린다(c-fold 후보).
//
// 색은 언제나 AingTheme.colors(iOS 토큰)·MaterialTheme(아잉 색 체계)에서 받는다 — 리터럴 금지(D5 의 정신, ui 는 팔레트 계약이 잰다).
// 불투명도에 이징을 쓰지 않는다(D2): 이 파일에는 흐려짐 애니메이션이 없다.
package com.yehsung.aingcheck.ui.screens.session.kit

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.messages.MobileLoadText
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.CharacterPortrait
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.icons.SfSymbols
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** SF 기호 이름 → 기호(대응표 SfSymbols). 표에 없으면 [fallback] — 화면이 빈 칸이 되지 않게. */
fun sf(name: String, fallback: AppIcon = AppIcon.Info): AppIcon = SfSymbols.toAppIcon[name] ?: fallback

/**
 * 시각에 따라 다시 그리는 자리(1초 타이머 · 상대 시각)를 켤지. 앱은 켬, 스냅숏 시험은 끈다 — 무한 타이머가 있으면 Compose 시험의 '쉼'이
 * 오지 않는다(시험이 시계를 멈춘 값으로 그린다).
 */
val LocalScreenTicking = staticCompositionLocalOf { true }

/** 카드(시안 B 인셋 그룹 한 장: 반경 22 · surface · 안쪽 여백 16). */
@Composable
fun AingCard(
    modifier: Modifier = Modifier,
    padding: Dp = AingDimens.cardPadding,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier
            .fillMaxWidth()
            .background(AingTheme.colors.surface, RoundedCornerShape(AingDimens.groupRadius))
            .padding(padding),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
        content = content,
    )
}

/** 인셋 그룹(줄 묶음 카드). 줄은 [GroupRow] 로 쌓는다. */
@Composable
fun InsetGroup(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .background(AingTheme.colors.surface, RoundedCornerShape(AingDimens.groupRadius)),
        content = content,
    )
}

/** 그룹 한 줄. [dividerInset] 이 null 이 아니면 아래에 그만큼 들인 구분선을 긋는다(마지막 줄은 null). */
@Composable
fun GroupRow(
    modifier: Modifier = Modifier,
    dividerInset: Dp? = AingDimens.cardPadding,
    minHeight: Dp = AingDimens.rowHeight,
    content: @Composable RowScope.() -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        Row(
            modifier
                .fillMaxWidth()
                .heightIn(min = minHeight)
                .padding(horizontal = AingDimens.cardPadding, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
            content = content,
        )
        if (dividerInset != null) {
            HorizontalDivider(Modifier.padding(start = dividerInset), thickness = AingDimens.hairline, color = AingTheme.colors.separator)
        }
    }
}

/** 안내 한 줄의 뜻(색·기호). */
enum class NoticeKind { Info, Warning, Error }

/** 안내 한 줄(옅은 틴트 바탕 · 기호 · 글자). */
@Composable
fun InlineNotice(text: String, kind: NoticeKind = NoticeKind.Info, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val tint = when (kind) {
        NoticeKind.Info -> colors.accent
        NoticeKind.Warning -> colors.pending
        NoticeKind.Error -> colors.danger
    }
    val icon = when (kind) {
        NoticeKind.Info -> sf("info.circle.fill")
        NoticeKind.Warning -> sf("exclamationmark.triangle.fill", AppIcon.Info)
        NoticeKind.Error -> sf("xmark.octagon.fill", AppIcon.Info)
    }
    Row(
        modifier
            .fillMaxWidth()
            .background(tint.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .semantics(mergeDescendants = true) {}
            .testTag(KitTags.NOTICE),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        AingIcon(icon, contentDescription = null, size = 18.dp, tint = tint)
        Text(text, style = MaterialTheme.typography.bodySmall, color = colors.label, modifier = Modifier.weight(1f))
    }
}

enum class AingButtonKind { Filled, Gray, Plain, Destructive, Tinted }

/** 보이는 높이(iOS AingButtonStyle size): sm 34 · md 44 · lg 50. 누르는 칸은 언제나 44 이상이다. */
enum class AingButtonSize(val height: Dp) { Sm(34.dp), Md(44.dp), Lg(50.dp) }

/**
 * 단추(iOS `AingButton`). 채운 단추는 화면당 하나(accentFill · 흰 글자). [isBusy] 면 글자 앞에 작은 돌림표를 세우고 누름을 막는다.
 * 글자 단추([AingButtonKind.Plain])는 바탕 없이 accent 글자.
 */
@Composable
fun AingButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: AingButtonKind = AingButtonKind.Filled,
    size: AingButtonSize = AingButtonSize.Md,
    fillsWidth: Boolean = false,
    enabled: Boolean = true,
    isBusy: Boolean = false,
    icon: AppIcon? = null,
) {
    val colors = AingTheme.colors
    val (fill, ink) = when (kind) {
        AingButtonKind.Filled -> colors.accentFill to colors.onAccentFill
        AingButtonKind.Gray -> colors.fill to colors.label
        AingButtonKind.Plain -> Color.Transparent to colors.accent
        AingButtonKind.Destructive -> colors.danger to colors.onAccentFill
        AingButtonKind.Tinted -> colors.accentTint to colors.accent
    }
    val active = enabled && !isBusy
    val shape = CircleShape
    Box(
        modifier
            .then(if (fillsWidth) Modifier.fillMaxWidth() else Modifier)
            .sizeIn(minWidth = AingDimens.minimumTarget, minHeight = AingDimens.minimumTarget)
            .clickable(enabled = active, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier
                .then(if (fillsWidth) Modifier.fillMaxWidth() else Modifier)
                .heightIn(min = size.height)
                .background(fill, shape)
                .alpha(if (enabled || isBusy) 1f else 0.5f)
                .padding(horizontal = if (kind == AingButtonKind.Plain) 8.dp else 20.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (isBusy) {
                CircularProgressIndicator(Modifier.size(16.dp), color = ink, strokeWidth = 2.dp)
            } else if (icon != null) {
                AingIcon(icon, contentDescription = null, size = 18.dp, tint = ink)
            }
            Text(
                text,
                style = if (size == AingButtonSize.Sm) MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold)
                else MaterialTheme.typography.labelLarge,
                color = ink,
                maxLines = 2,
                textAlign = TextAlign.Center,
            )
        }
    }
}

/** "불러오는 중…" 한 줄. */
@Composable
fun LoadingRow(text: String = MobileLoadText.retrying, modifier: Modifier = Modifier) {
    Row(
        modifier.fillMaxWidth().padding(vertical = 8.dp).semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(Modifier.size(18.dp), color = AingTheme.colors.label2, strokeWidth = 2.dp)
        Text(text, style = MaterialTheme.typography.bodyMedium, color = AingTheme.colors.label2)
    }
}

/** 불러오지 못한 자리: 경고 한 줄 + [다시 시도](없으면 글자만). */
@Composable
fun LoadFailureRow(text: String, isRetrying: Boolean = false, retry: (() -> Unit)?, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        AingIcon(sf("exclamationmark.triangle.fill"), contentDescription = null, size = 18.dp, tint = colors.pending)
        Text(text, style = MaterialTheme.typography.bodyMedium, color = colors.label2, modifier = Modifier.weight(1f))
        if (retry != null) {
            AingButton(
                if (isRetrying) MobileLoadText.retrying else MobileLoadText.retry, retry,
                kind = AingButtonKind.Tinted, size = AingButtonSize.Sm, enabled = !isRetrying, icon = sf("arrow.clockwise"),
            )
        }
    }
}

/** 빈 상태(기호 · 제목 · 설명 · 선택 단추). */
@Composable
fun EmptyStateView(
    icon: AppIcon,
    title: String,
    message: String? = null,
    actionTitle: String? = null,
    action: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val colors = AingTheme.colors
    Column(
        modifier.fillMaxWidth().padding(vertical = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        AingIcon(icon, contentDescription = null, size = 34.dp, tint = colors.accent)
        Text(title, style = MaterialTheme.typography.titleMedium, color = colors.label, textAlign = TextAlign.Center)
        if (message != null) {
            Text(message, style = MaterialTheme.typography.bodyMedium, color = colors.label2, textAlign = TextAlign.Center)
        }
        if (actionTitle != null && action != null) {
            AingButton(actionTitle, action, kind = AingButtonKind.Filled, modifier = Modifier.padding(top = 4.dp))
        }
    }
}

/** 시트 머리: 왼쪽 ✕(닫는 길 하나) · 가운데 제목. */
@Composable
fun SheetHeader(title: String, onClose: () -> Unit, closeLabel: String = "닫기", enabled: Boolean = true) {
    val colors = AingTheme.colors
    Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 8.dp)) {
        Box(
            Modifier
                .align(Alignment.CenterStart)
                .size(AingDimens.minimumTarget)
                .clickable(enabled = enabled, role = Role.Button, onClick = onClose)
                .semantics { contentDescription = closeLabel }
                .testTag(KitTags.SHEET_CLOSE),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(32.dp).background(colors.fill, CircleShape), contentAlignment = Alignment.Center) {
                AingIcon(sf("xmark", AppIcon.Close), contentDescription = null, size = 18.dp, tint = colors.label2)
            }
        }
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            color = colors.label,
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 52.dp).semantics { heading() },
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** 목록 절 머리(19~20 bold 제목 + 오른쪽 보조 글자). */
@Composable
fun SectionHeader(title: String, trailing: String? = null, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Row(
        modifier.fillMaxWidth().padding(start = AingDimens.titleMargin, end = AingDimens.titleMargin, top = 16.dp, bottom = 8.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge, color = colors.label, modifier = Modifier.weight(1f).semantics { heading() })
        if (trailing != null) Text(trailing, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
    }
}

/**
 * 화면 높이 안에서 가운데로 모으고(짧은 화면의 아래 절반이 비지 않게), 넘치면 스크롤한다. [footer] 는 맨 아래에 붙는다.
 * 폭은 520 상한(sw600dp 에서 입력 줄이 화면 폭으로 늘어나지 않게 — iOS `MobileCenteredScreen` 과 같은 값).
 */
@Composable
fun CenteredScreen(
    modifier: Modifier = Modifier,
    footer: @Composable ColumnScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    BoxWithConstraints(modifier.fillMaxSize().background(AingTheme.colors.background)) {
        val viewport = maxHeight
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                Modifier
                    .widthIn(max = 520.dp)
                    .fillMaxWidth()
                    .heightIn(min = viewport)
                    .padding(horizontal = AingDimens.sideMargin)
                    .padding(bottom = AingDimens.space4),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Spacer(Modifier.weight(1f).heightIn(min = AingDimens.space6))
                content()
                Spacer(Modifier.weight(1f).heightIn(min = AingDimens.space6))
                footer()
            }
        }
    }
}

/** 로그인 계열 화면의 머리: 아잉(표정 = 상태) · 큰 제목 · 설명. 아잉 그림은 104(원본 192px — 크게 키우면 흐려진다). */
@Composable
fun BrandHeader(mood: CharacterMood, title: String, message: String, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val art = rememberPortrait(BRAND_CHARACTER, mood.expression)
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(AingDimens.space3)) {
        CharacterPortrait(art = art, mood = mood, size = BRAND_ART, framed = false)
        Text(title, style = MaterialTheme.typography.headlineLarge, color = colors.label, textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() })
        Text(message, style = MaterialTheme.typography.bodyMedium, color = colors.label2, textAlign = TextAlign.Center)
    }
}

/** 로그인 단추(채움 50 · 캡슐 · 시작 그라디언트 — 로그인 전용). 글자는 브랜드 남색(흰 글자는 그라디언트 위 2:1 안팎). */
@Composable
fun StartGradientButton(text: String, onClick: () -> Unit, enabled: Boolean, isBusy: Boolean, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 50.dp)
            .alpha(if (enabled) 1f else 0.6f)
            .background(Brush.horizontalGradient(colors.startStops), CircleShape)
            .clickable(enabled = enabled && !isBusy, role = Role.Button, onClick = onClick)
            .padding(horizontal = 22.dp, vertical = 4.dp)
            .testTag(KitTags.START_BUTTON),
        contentAlignment = Alignment.Center,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (isBusy) CircularProgressIndicator(Modifier.size(16.dp), color = colors.brandNavy, strokeWidth = 2.dp)
            Text(text, style = MaterialTheme.typography.titleSmall, color = colors.brandNavy)
        }
    }
}

/** 화면 바깥 여백이 있는 단(카드·그룹을 담는 세로 단 — 화면 좌우 16). */
@Composable
fun ScreenColumn(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().padding(horizontal = AingDimens.sideMargin), verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing), content = content)
}

/** 화면 폭 상한(sw600dp 에서 한 단이 지나치게 넓어지지 않게 — 읽는 폭 600). 가운데 정렬. */
@Composable
fun ReadableWidth(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = READABLE_WIDTH).fillMaxWidth(), content = content)
    }
}

/** 단의 위아래 기본 여백. */
val ScreenPadding = PaddingValues(top = AingDimens.space2, bottom = AingDimens.space6)

private const val BRAND_CHARACTER = "aing"
private val BRAND_ART = 104.dp
val READABLE_WIDTH = 600.dp

/** 부품 시험 표식(계측·스냅숏이 찾는다). */
object KitTags {
    const val NOTICE = "kit-notice"
    const val SHEET_CLOSE = "kit-sheet-close"
    const val START_BUTTON = "kit-start-button"
}

/** 브랜드 아잉 초상의 그림 경로(시험이 원본 파일과 대조한다). */
fun brandPortraitPath(mood: CharacterMood): String = CharacterArt.portraitPath(BRAND_CHARACTER, mood.expression)

/** 숨는 칸(높이 0) — 자리만 맞춘다. */
@Composable
fun HSpace(width: Dp) = Spacer(Modifier.width(width))

/** 얇은 선 테두리(입력칸 · 확성기 글 칸). */
fun Modifier.hairlineBorder(color: Color, radius: Dp, width: Dp = AingDimens.hairline): Modifier =
    border(width, color, RoundedCornerShape(radius))
