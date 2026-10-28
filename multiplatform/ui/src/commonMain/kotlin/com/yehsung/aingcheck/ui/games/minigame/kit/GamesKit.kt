// 원본: Sources/CheckMobileKit/Components/InsetGroup.swift @ 3bd04bd (InsetGroup · GroupRow · SectionHeader)
// 원본: Sources/CheckMobileKit/Components/MobileComponents.swift @ 3bd04bd (InlineNotice · RetryButton · LoadFailureRow · LoadingRow)
// 원본: Sources/CheckMobileKit/Components/MobileRankComponents.swift @ 3bd04bd (RankBadge · RankMedal · CrownBadge · AingChip)
// 원본: Sources/CheckMobileKit/Components/RankBoardParts.swift @ 3bd04bd (ChampionRow)
// 원본: Sources/CheckMobileKit/Games/GamesComponents.swift @ 3bd04bd (GamesStakeLine · GamesWatcherBadge · GamesTouchTarget)
//
// 게임 화면(W4-b)이 쓰는 공용 부품의 **게임 갈래 사본**. iOS 공용 부품(Components)은 Android 에서 W3-a·W3-b 가 ui/screens/* 에 옮기는 중이고
// 이 갈래는 같은 웨이브에 병렬로 돈다(G §8-18 8) — 남의 소유 경로를 기다리거나 쓰지 않으려 모양·수치를 그대로 여기 한 벌 둔다.
// 통합(c-fold)에서 W3 의 공용 부품 한 벌로 접는다(보고 unresolved). 색은 전부 AingTheme 뜻 색이다(리터럴 없음).
package com.yehsung.aingcheck.ui.games.minigame.kit

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.stores.games.GamesWatcherCount
import com.yehsung.aingcheck.core.stores.games.MobileLoadText
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.components.rememberRubyArt
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 숫자 글자(고정폭 숫자 — iOS `.monospacedDigit()`). */
const val TNUM: String = "tnum"

/** 행 제목(iOS `MobileTheme.rowTitle` = callout 16 semibold → titleSmall). */
@Composable
fun rowTitleStyle(): TextStyle = MaterialTheme.typography.titleSmall

/** 행 부제(iOS `MobileTheme.rowSubtitle` = footnote 13 → bodySmall). */
@Composable
fun rowSubtitleStyle(): TextStyle = MaterialTheme.typography.bodySmall

/** 섹션 머리(iOS `MobileTheme.sectionTitle` = title3 20 bold → titleLarge). */
@Composable
fun sectionTitleStyle(): TextStyle = MaterialTheme.typography.titleLarge

/** 목록은 카드마다 한 장이 아니라 **인셋 그룹 한 장 안의 행**(시안 B). */
@Composable
fun InsetGroup(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val shape = RoundedCornerShape(AingDimens.groupRadius)
    Column(modifier.fillMaxWidth().clip(shape).background(AingTheme.colors.surface, shape)) { content() }
}

/**
 * 그룹 안 한 행. [dividerInset] 이 null 이면 구분선 없음, 값이면 그 들여쓰기에서 0.5 구분선(글자 시작점부터).
 * 내 행 강조는 파랑 6%(테두리 없음).
 */
@Composable
fun GroupRow(
    modifier: Modifier = Modifier,
    dividerInset: Dp? = AingDimens.cardPadding,
    minHeight: Dp = AingDimens.rowHeight,
    padding: PaddingValues = PaddingValues(horizontal = AingDimens.cardPadding, vertical = 10.dp),
    isHighlighted: Boolean = false,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = AingTheme.colors
    Box(modifier.fillMaxWidth().background(if (isHighlighted) colors.accent.copy(alpha = 0.06f) else Color.Transparent)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = minHeight).padding(padding),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space3),
            content = content,
        )
        if (dividerInset != null) {
            Box(
                Modifier.align(Alignment.BottomStart).padding(start = dividerInset).fillMaxWidth().height(AingDimens.hairline)
                    .background(colors.separator),
            )
        }
    }
}

/** 섹션 머리 오른쪽 자리. */
sealed interface SectionTrailing {
    data object None : SectionTrailing
    data class Label(val text: String) : SectionTrailing
    data class Action(val label: String, val onClick: () -> Unit) : SectionTrailing
}

/** 섹션 머리(제목 + 오른쪽 글자/동작). [padded] 면 위 22 · 아래 8 · 좌우 (제목 여백 − 옆 여백). */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, trailing: SectionTrailing = SectionTrailing.None, padded: Boolean = false) {
    val colors = AingTheme.colors
    Row(
        modifier.fillMaxWidth().padding(
            start = if (padded) AingDimens.titleMargin - AingDimens.sideMargin else 0.dp,
            end = if (padded) AingDimens.titleMargin - AingDimens.sideMargin else 0.dp,
            top = if (padded) 22.dp else 0.dp,
            bottom = if (padded) 8.dp else 0.dp,
        ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(title, style = sectionTitleStyle(), color = colors.label, modifier = Modifier.semantics { heading() })
        Spacer(Modifier.weight(1f))
        when (trailing) {
            SectionTrailing.None -> Unit
            is SectionTrailing.Label -> Text(trailing.text, style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = TNUM), color = colors.label2)
            is SectionTrailing.Action -> Box(
                Modifier.heightIn(min = AingDimens.minimumTarget).clickable(role = Role.Button, onClick = trailing.onClick),
                contentAlignment = Alignment.Center,
            ) { Text(trailing.label, style = MaterialTheme.typography.bodyMedium, color = colors.accent) }
        }
    }
}

enum class NoticeKind { Info, Warning, Error }

/** 한 줄 안내(기호 + 글자 · 뜻 색 12% 바탕). 글자는 label 이고 뜻은 기호·바탕이 낸다. */
@Composable
fun InlineNotice(text: String, modifier: Modifier = Modifier, kind: NoticeKind = NoticeKind.Info) {
    val colors = AingTheme.colors
    val tint = when (kind) {
        NoticeKind.Info -> colors.accent
        NoticeKind.Warning -> colors.pending
        NoticeKind.Error -> colors.danger
    }
    val icon = when (kind) {
        NoticeKind.Info -> AppIcon.InfoFill
        NoticeKind.Warning -> AppIcon.WarningFill
        NoticeKind.Error -> AppIcon.DangerousFill
    }
    Row(
        modifier.fillMaxWidth().background(tint.copy(alpha = 0.12f), RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 10.dp)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        AingIcon(icon, contentDescription = null, size = 16.dp, tint = tint)
        Text(text, style = MaterialTheme.typography.bodySmall, color = colors.label, modifier = Modifier.weight(1f))
    }
}

/** 다시 시도 단추(파랑 틴트 캡슐 · 44 이상). */
@Composable
fun RetryButton(isRetrying: Boolean = false, onClick: () -> Unit) {
    val colors = AingTheme.colors
    Row(
        Modifier.defaultMinSize(AingDimens.minimumTarget, AingDimens.minimumTarget).clip(CircleShape).background(colors.accentTint)
            .clickable(enabled = !isRetrying, role = Role.Button, onClick = onClick).padding(horizontal = 16.dp).alpha(if (isRetrying) 0.6f else 1f),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (isRetrying) {
            CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = colors.accent)
            Text(MobileLoadText.retrying, style = MaterialTheme.typography.labelLarge, color = colors.accent)
        } else {
            AingIcon(AppIcon.Refresh, contentDescription = null, size = 16.dp, tint = colors.accent)
            Text(MobileLoadText.retry, style = MaterialTheme.typography.labelLarge, color = colors.accent)
        }
    }
}

/** 불러오기 실패 한 줄(주의 기호 + 글자 · [다시 시도]). */
@Composable
fun LoadFailureRow(text: String, modifier: Modifier = Modifier, isRetrying: Boolean = false, retry: (() -> Unit)?) {
    val colors = AingTheme.colors
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AingIcon(AppIcon.WarningFill, contentDescription = null, size = 16.dp, tint = colors.pending)
            Text(text, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
        }
        if (retry != null) RetryButton(isRetrying, retry)
    }
}

/** 불러오는 중 한 줄(돌이 + 글자). */
@Composable
fun LoadingRow(text: String, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Row(modifier.padding(vertical = 8.dp).semantics(mergeDescendants = true) { }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = colors.label2)
        Text(text, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
    }
}

/** 순위 원 24 — 1~3 금·은·동(짙은 숫자), 나머지는 원 없이 흐린 숫자. 메달 규칙은 모든 순위판에서 같다. */
@Composable
fun RankBadge(rank: Int, modifier: Modifier = Modifier, usesMedals: Boolean = true) {
    val colors = AingTheme.colors
    val medal: Pair<Color, Color>? = if (!usesMedals) null else when (rank) {
        1 -> colors.gold to colors.goldInk
        2 -> colors.silver to colors.silverInk
        3 -> colors.bronze to colors.bronzeInk
        else -> null
    }
    Box(
        modifier.size(24.dp).then(if (medal != null) Modifier.background(medal.first, CircleShape) else Modifier).clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            rank.toString(),
            style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold, fontFeatureSettings = TNUM),
            color = medal?.second ?: colors.label2,
            maxLines = 1,
        )
    }
}

/** 왕관 원 32(어제 1등). */
@Composable
fun CrownBadge(modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Box(modifier.size(32.dp).background(colors.gold, CircleShape).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        AingIcon(AppIcon.CrownFill, contentDescription = null, size = 16.dp, tint = colors.crownInk)
    }
}

/** 작은 칩(캡슐) — 뜻 색 14% 바탕 + 그 색 글자. */
@Composable
fun AingChip(text: String, modifier: Modifier = Modifier, tint: Color = AingTheme.colors.accent, small: Boolean = false) {
    Box(
        modifier.heightIn(min = if (small) 18.dp else 22.dp).background(tint.copy(alpha = 0.14f), CircleShape).padding(horizontal = if (small) 6.dp else 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = (if (small) MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold) else MaterialTheme.typography.labelMedium),
            color = tint,
            maxLines = 1,
        )
    }
}

/** 이니셜 원 아바타(+ 근무 중 점). 초상 그림 대신 이름 첫 글자 — 사진·착용 캐릭터는 공용 부품 통합(c-fold) 때 W3 의 PersonAvatar 로 접는다. */
@Composable
fun PersonAvatar(name: String, colorSeed: String, size: Dp, modifier: Modifier = Modifier, working: Boolean = false) {
    val colors = AingTheme.colors
    val (ink, tint) = colors.avatar(colorSeed)
    Box(modifier.size(size).clearAndSetSemantics { }) {
        Box(Modifier.size(size).background(tint, CircleShape), contentAlignment = Alignment.Center) {
            Text(
                name.trim().firstOrNull()?.toString() ?: "?",
                style = TextStyle(fontSize = (size.value * 0.42f).sp, fontWeight = FontWeight.SemiBold),
                color = ink,
            )
        }
        if (working) {
            val dot = (size.value * 0.28f).dp
            Box(
                Modifier.align(Alignment.BottomEnd).size(dot).border(BorderStroke(2.dp, colors.surface), CircleShape)
                    .background(colors.workingDot, CircleShape),
            )
        }
    }
}

/** 이름(+ 센터 · '나' 칩). [onTint] 면 '나' 칩을 내 행 칠 위에 맞춘다. */
@Composable
fun PersonName(name: String, modifier: Modifier = Modifier, center: String? = null, isMe: Boolean = false) {
    val colors = AingTheme.colors
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(name, style = rowTitleStyle(), color = colors.label, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        if (center != null) Text(center, style = rowSubtitleStyle(), color = colors.label2, maxLines = 1)
        if (isMe) AingChip("나", small = true)
    }
}

/** 단추 꼴(iOS AingButton.kind). 채운 단추는 화면당 하나(저장소 규약). */
enum class PillKind { Filled, Tinted, Gray, Destructive, Plain }

/** 단추 크기(iOS AingButton.size — sm 34 · md 44 · lg 52). */
enum class PillSize(val height: Dp, val horizontal: Dp) { Sm(34.dp, 14.dp), Md(44.dp, 18.dp), Lg(52.dp, 20.dp) }

/** 알약 단추(iOS `AingButton`). 비활성은 흐리게만(0.45) — 누름 영역은 그대로 44 이상(투명 여백). */
@Composable
fun PillButton(
    title: String,
    modifier: Modifier = Modifier,
    kind: PillKind = PillKind.Tinted,
    size: PillSize = PillSize.Md,
    icon: AppIcon? = null,
    fillsWidth: Boolean = false,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val colors = AingTheme.colors
    val (background, ink) = when (kind) {
        PillKind.Filled -> colors.accentFill to colors.onAccentFill
        PillKind.Tinted -> colors.accentTint to colors.accent
        PillKind.Gray -> colors.fill to colors.label
        PillKind.Destructive -> colors.dangerTint to colors.danger
        PillKind.Plain -> Color.Transparent to colors.accent
    }
    Box(
        modifier
            .heightIn(min = AingDimens.minimumTarget)
            .then(if (fillsWidth) Modifier.fillMaxWidth() else Modifier)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = title },
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier.then(if (fillsWidth) Modifier.fillMaxWidth() else Modifier).height(size.height).clip(CircleShape).background(background)
                .padding(horizontal = size.horizontal).alpha(if (enabled) 1f else 0.45f),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        ) {
            if (icon != null) AingIcon(icon, contentDescription = null, size = 16.dp, tint = ink)
            Text(title, style = MaterialTheme.typography.labelLarge, color = ink, maxLines = 1)
        }
    }
}

/** 어제 1등 한 줄(자기 그룹 — '오늘 순위' 첫 행처럼 읽히지 않게 떼어 둔다). */
@Composable
fun ChampionRow(caption: String, name: String, center: String?, score: String, awarded: Int?, modifier: Modifier = Modifier, awardedSuffix: String = "받음") {
    val colors = AingTheme.colors
    val description = buildList {
        add(caption); add(name); center?.let(::add); add(score)
        if (awarded != null) add("루비 ${awarded}개 $awardedSuffix")
    }.joinToString(", ")
    InsetGroup(modifier.semantics(mergeDescendants = true) { contentDescription = description }) {
        GroupRow(dividerInset = null, padding = PaddingValues(horizontal = AingDimens.cardPadding, vertical = 12.dp)) {
            CrownBadge()
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(caption, style = rowSubtitleStyle(), color = colors.label2)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    PersonName(name, center = center, modifier = Modifier.weight(1f, fill = false))
                    Text(score, style = rowTitleStyle().copy(fontFeatureSettings = TNUM), color = colors.label)
                }
            }
            if (awarded != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    RubyIcon(rememberRubyArt(14f), size = 14.dp)
                    Text("+$awarded $awardedSuffix", style = rowSubtitleStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.working)
                }
            }
        }
    }
}

/** 판돈 한 줄 "판돈 [보석]5 · 이기면 +5". */
@Composable
fun StakeLine(stake: Int, modifier: Modifier = Modifier, prefix: String? = null, suffix: String? = null, color: Color = AingTheme.colors.label2, style: TextStyle = rowSubtitleStyle()) {
    Row(
        modifier.semantics(mergeDescendants = true) { contentDescription = "${prefix ?: ""} 루비 $stake${suffix ?: ""}" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        if (prefix != null) Text("$prefix ", style = style, color = color)
        RubyIcon(rememberRubyArt(14f), size = 14.dp)
        Text(stake.toString() + (suffix ?: ""), style = style.copy(fontFeatureSettings = TNUM), color = color)
    }
}

/** 관전자 수 한 칸(눈 + 수). 판정은 core `GamesWatcherCount` 하나 — 0·음수면 아무것도 그리지 않는다(이 뷰가 스스로 접는다). */
@Composable
fun WatcherBadge(count: Int, modifier: Modifier = Modifier, style: TextStyle = rowSubtitleStyle(), tint: Color = AingTheme.colors.label2) {
    // INV-GamesComponents-a97937fd 이식: 그리는가를 **부르는 쪽이 또 묻지 않게** 이 부품이 스스로 접는다(shows 가 거짓이면 빈 자리) —
    //   로비 줄처럼 슬롯이 비면 줄을 접는 자리에서는 부르는 쪽도 같은 술어를 보지만, 그 술어는 **같은 한 함수**(GamesWatcherCount.shows)다.
    if (!GamesWatcherCount.shows(count)) return
    Row(
        modifier.clearAndSetSemantics { contentDescription = GamesWatcherCount.accessibilityLabel(count) },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        AingIcon(AppIcon.VisibilityFill, contentDescription = null, size = 14.dp, tint = tint)
        Text(GamesWatcherCount.text(count), style = style.copy(fontFeatureSettings = TNUM), color = tint)
    }
}

/** 빈 상태(가운데 기호 + 한 줄). */
@Composable
fun EmptyState(icon: AppIcon?, title: String, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Column(modifier.fillMaxWidth().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (icon != null) AingIcon(icon, contentDescription = null, size = 40.dp, tint = colors.label3)
        Text(title, style = MaterialTheme.typography.bodyLarge, color = colors.label2)
    }
}

/** 시트·화면 머리(가운데 제목 + 부제 · 왼쪽 닫기/뒤로). */
@Composable
fun GamesHeaderBar(title: String, modifier: Modifier = Modifier, subtitle: String? = null, onBack: (() -> Unit)? = null, backIcon: AppIcon = AppIcon.ChevronLeft, trailing: (@Composable () -> Unit)? = null) {
    val colors = AingTheme.colors
    Box(modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = 4.dp)) {
        if (onBack != null) {
            Box(
                Modifier.align(Alignment.CenterStart).size(AingDimens.minimumTarget).clickable(role = Role.Button, onClick = onBack)
                    .semantics { contentDescription = "뒤로" },
                contentAlignment = Alignment.Center,
            ) { AingIcon(backIcon, contentDescription = null, size = 24.dp, tint = colors.accent) }
        }
        Column(Modifier.align(Alignment.Center).padding(horizontal = 52.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, style = MaterialTheme.typography.titleMedium, color = colors.label, maxLines = 1, modifier = Modifier.semantics { heading() })
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Normal), color = colors.label2, maxLines = 1)
        }
        if (trailing != null) Box(Modifier.align(Alignment.CenterEnd).width(AingDimens.minimumTarget * 1.2f), contentAlignment = Alignment.CenterEnd) { trailing() }
    }
}

/** 시트(불투명 — 확인·판돈·규칙). 끌어 내려 닫을 수 있다(닫기 = [onDismiss]). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GamesSheet(onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = AingTheme.colors.background,
        dragHandle = null,
        content = content,
    )
}
