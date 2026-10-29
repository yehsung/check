// 원본: Sources/CheckMobileKit/Me/MeAILimitsCard.swift @ 3bd04bd (나 탭 「AI 리밋」 카드 · 표 · 제공자 줄 · 바 · 열 색)
// 원본: Sources/CheckMobileShared/AILimitColumnStyle.swift @ 3bd04bd (AILimitColumnPalette 값 · AILimitUsageStage · AILimitBarFill)
// 원본: Sources/CheckMobileShared/AILimitSurfaceRules.swift:51-78 @ 3bd04bd (AILimitFloorFill)
//
// 승인된 문법(2026-10-07 — 맥 팝오버·위젯 미디움과 같은 문법): ① 한 제공자 = 한 줄, 5시간·주간이 그 줄 안에 나란히 ② 열 머리는 카드 맨 위에
// 한 번만 ③ 짝 단서 셋(열 머리 글자 · 색 · 좌우 자리) ④ 제공자 사이 1px 구분선은 카드 안쪽 여백 **바깥까지** ⑥ 퍼센트는 고정폭 칸·오른쪽 정렬.
// 숫자·캡션·표시여부는 전부 스토어(AILimitsStore.displayGroups — 코어 AILimitFreshnessRule)에서 온다. 이 파일은 반올림·나이·"이상"을 다시 만들지 않는다.
// 가로 예산은 뷰 밖(core/stores MeAILimitCardBudget)이다.
//
// ⚠️ 두 벌 위험(보고): 열 색·채움 산식·사용량 단계는 Swift 에서 CheckMobileShared(폰 + 위젯 공용)에 있다. Kotlin 에서 위젯(W2-f feature/phone)이
//   같은 것을 옮기면 ui 는 feature/phone 을 볼 수 없어(의존 방향) 두 벌이 된다 — 8차 접기에서 core/rules …/ailimit 한 곳으로 모은다.
package com.yehsung.aingcheck.ui.screens.me

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.layout
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceNameParts
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDisplay
import com.yehsung.aingcheck.core.rules.ailimit.AILimitFreshnessRule
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.stores.me.AILimitColumnText
import com.yehsung.aingcheck.core.stores.me.AILimitDeviceDisplayGroup
import com.yehsung.aingcheck.core.stores.me.AILimitDisplayRow
import com.yehsung.aingcheck.core.stores.me.AILimitsStore
import com.yehsung.aingcheck.core.stores.me.MeAILimitCardBudget
import com.yehsung.aingcheck.core.stores.me.MeAILimitsText
import com.yehsung.aingcheck.ui.screens.settingscommon.LoadFailureRow
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.math.max
import kotlin.math.min

/** 「AI 리밋」 카드 한 장(스토어를 읽는다). 제목 · 표(또는 빈 줄) · 캡션 · 토큰 줄(다른 축). */
@Composable
fun MeAILimitsCard(limits: AILimitsStore, retryLabel: String, onRetry: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val groups = limits.displayGroups
    val (today, recent) = limits.phoneTokenTotals()
    Column(
        modifier
            .fillMaxWidth()
            .background(colors.surface, RoundedCornerShape(AingDimens.groupRadius))
            .padding(AingDimens.cardPadding),
        verticalArrangement = Arrangement.spacedBy(AingDimens.space3),
    ) {
        MeAILimitsTitle(limits.fiveHourSummary)
        if (groups.isEmpty()) {
            MeAILimitsEmptyLine(limits.state.hasLoaded, limits.state.hasFailed, limits.state.isLoading, retryLabel, onRetry)
        } else {
            // INV-MeAILimitsCard-c9cd84c4 이식: 대체 맥 한 줄은 표 **앞**이다 — 아래 숫자를 어떻게 읽을지 말하는 줄이라 숫자를 다 본 뒤면 늦다
            //   (보이스오버·톡백은 위에서 아래로 한 번 읽는다).
            if (limits.isShowingSubstituteDevice) {
                Text(MeAILimitsText.aiLimitsSubstitutedDevice, style = MaterialTheme.typography.bodySmall, color = colors.pending)
            }
            MeAILimitsTable(groups, showsDeviceNames = limits.showsDeviceNames)
            Text(MeAILimitsText.aiLimitsCaption, style = MaterialTheme.typography.bodySmall, color = colors.label2)
        }
        MeAITokenBlock(today, recent)
    }
}

/** 제목 한 줄. 화면에는 칩이 없고, 소리로만 5시간 요약을 한 번 말한다(같은 수가 두 번 서지 않게). */
@Composable
internal fun MeAILimitsTitle(summary: AILimitDisplay?) {
    val label = summary?.let { "${MeAILimitsText.aiLimitsTitle}, ${MeAILimitsText.aiLimitsFiveHourPeak} ${it.valueText}" } ?: MeAILimitsText.aiLimitsTitle
    Text(
        MeAILimitsText.aiLimitsTitle,
        style = MaterialTheme.typography.titleMedium,
        color = AingTheme.colors.label,
        modifier = Modifier.clearAndSetSemantics { contentDescription = label; heading() },
    )
}

/**
 * 아직 그릴 줄이 없다: 불러오는 중 · 실패 · **그릴 줄 0건**. 셋을 섞지 않는다 — "줄 0건"을 실패로 말하면 맥을 안 쓰는 사람에게 고장으로 읽힌다.
 * INV-MeAILimitsCard-e86f529e 이식: 줄이 사라지는 판정은 스토어의 '보이는 창이 0개인가'다(이 뷰에는 설정을 아는 코드가 한 줄도 없다) —
 *   '5시간 창이 있나'로 재면 주간만 오는 안티그래비티가 함께 사라진다. 그래서 여기는 빈 묶음만 보고 문장을 고른다.
 */
@Composable
internal fun MeAILimitsEmptyLine(hasLoaded: Boolean, hasFailed: Boolean, isLoading: Boolean, retryLabel: String, onRetry: () -> Unit) {
    val colors = AingTheme.colors
    when {
        hasLoaded -> Text(MeAILimitsText.aiLimitsNoProviders, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
        hasFailed -> LoadFailureRow(MeAILimitsText.aiLimitsFailed, retryLabel, isRetrying = isLoading, onRetry = onRetry)
        else -> Text(MeAILimitsText.aiLimitsLoading, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
    }
}

/** 기존 토큰 사용량(다른 축). 모르면(수집 꺼짐 · 아직 못 받음) **줄을 만들지 않는다** — 0 은 "안 썼다"는 거짓이다. */
@Composable
internal fun MeAITokenBlock(today: Long?, recent: Long?) {
    if (today == null) return
    val colors = AingTheme.colors
    Box(Modifier.fillMaxWidth().height(1.dp).background(colors.separator))
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(MeAILimitsText.aiTokenTodayTitle, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
            Text(MeAILimitsText.aiTokenValue(today), style = MaterialTheme.typography.labelLarge, color = colors.label, maxLines = 1)
        }
        if (recent != null) {
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(MeAILimitsText.aiTokenRecentTitle, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                Text(MeAILimitsText.aiTokenCompact(recent), style = MaterialTheme.typography.labelLarge, color = colors.label, maxLines = 1)
            }
        }
    }
}

/**
 * 열 머리 한 줄 + **기기 묶음들**(평평한 한 줄기 — 묶음이 '카드 안의 카드'가 되지 않게).
 * INV-MeAILimitsCard-842f4856 이식: 열 머리는 **카드당 한 번**이다(묶음마다 되풀이하지 않는다). 근거 넷 — 세로 길이 · 격자가 구조적으로 고정
 *   (이름 칸 108 → 5시간 → 주간이 모든 묶음에서 같은 자리) · 짝 단서 셋 중 둘(색·자리)이 모든 줄에 있다 · 세 화면(맥 팝오버·위젯)이 같은 문법.
 * INV-MeAILimitsCard-428036ee 이식: 그래서 **맥 한 대인 사람의 카드는 글자 하나 안 바뀐다**(제목 → 열 머리 → 제공자 줄들). 두 대가 되면
 *   그 사이에 머리글 줄만 끼어든다 — [showsDeviceNames] 가 거짓이면 이 함수는 0.3.46 모양 그대로다.
 * INV-MeAILimitsCard-fa0f04a9 이식: 키는 묶음 = **기기**, 줄 = 그 묶음 **안에서만** 제공자다. 맥 두 대가 같은 Claude 를 올리면 제공자 id 가
 *   카드 안에서 두 번 나온다 — 한 목록에 펼쳐 제공자로 키를 잡으면 Compose 가 같은 키 둘을 보고 줄을 뒤섞는다(key() 를 묶음·줄 두 층으로 건다).
 */
@Composable
fun MeAILimitsTable(groups: List<AILimitDeviceDisplayGroup>, showsDeviceNames: Boolean, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth()) {
        MeAILimitsColumnHeader()
        groups.forEachIndexed { groupIndex, group ->
            androidx.compose.runtime.key(group.id) {
                // 묶음 경계에는 이름을 그리든 안 그리든 선이 있다(죽은 분기를 만들지 않는다).
                if (groupIndex > 0) MeAILimitSeparator()
                if (showsDeviceNames) MeAILimitDeviceNameRow(group.nameParts, isFirst = groupIndex == 0)
                group.rows.forEachIndexed { index, row ->
                    androidx.compose.runtime.key(row.id) {
                        if (index > 0) MeAILimitSeparator()
                        MeAILimitRow(row, deviceName = if (showsDeviceNames) group.name else null, modifier = Modifier.padding(vertical = AingDimens.space1))
                    }
                }
            }
        }
    }
}

/**
 * 기기 묶음 머리글 한 줄(12 semibold label2 — 구획 표시라 제공자 이름보다 조용하다).
 * INV-MeAILimitsCard-54a8727b 이식: 겹침 꼬리 `(A1B2)` 는 **이름과 따로** 그린다(v0.3.47 P2) — 상한 길이(64 스칼라) 이름 두 대는 두 줄에도 안 들어가고,
 *   합쳐 적으면 말줄임이 꼬리부터 먹어 두 머리글이 똑같아진다.
 * INV-MeAILimitsCard-f469fdde 이식: 그래서 이름은 두 줄까지 접히고 넘치면 잘리되, 꼬리는 **언제나 제 폭을 먼저 가져간다**. 잘리는 쪽은 겹쳐도
 *   같은 글자(이름)이고 남는 쪽은 가르는 글자(꼬리)다.
 * INV-MeAILimitsCard-10274229 이식: Swift 의 `fixedSize` + `layoutPriority` 두 겹 → Compose 는 꼬리를 weight 없는 자식으로 **먼저** 재고(제 폭 그대로,
 *   maxLines 1 · 말줄임 없음) 이름이 weight(1f, fill=false) 로 남는 폭만 받는다. 하나만 두면 이름이 긴 날 꼬리가 0 으로 눌리거나 "…" 가 된다.
 * INV-MeAILimitsCard-0b84a634 이식: 소리는 이 줄을 **머리글 하나로** 읽는다(합친 글자 · heading) — 두 Text 로 나뉜 것은 그리기 사정이다.
 */
@Composable
internal fun MeAILimitDeviceNameRow(parts: AILimitDeviceNameParts, isFirst: Boolean) {
    val colors = AingTheme.colors
    val style = MaterialTheme.typography.labelMedium.copy(fontSize = MeAILimitCardBudget.deviceNameFontSize.sp, fontWeight = FontWeight.SemiBold)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = if (isFirst) 0.dp else MeAILimitCardBudget.deviceNameTopGap.dp, bottom = MeAILimitCardBudget.deviceNameBottomGap.dp)
            .clearAndSetSemantics { contentDescription = parts.combined; heading() },
        horizontalArrangement = Arrangement.spacedBy(MeAILimitCardBudget.deviceTailGap.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(parts.base, style = style, color = colors.label2, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        val tail = parts.tail
        if (tail != null) Text(AILimitDeviceNameParts.tailText(tail), style = style, color = colors.label2, maxLines = 1, softWrap = false)
    }
}

/**
 * 열 머리 줄. 데이터 줄과 **같은 격자**다 — 왼쪽 칸을 비우고 두 머리 칸이 남는 폭을 똑같이 나눠 가진다(측정 상수가 아니라 항등식).
 * INV-MeAILimitsCard-507e5684 이식: **카드당 한 번**이다 — 기기 묶음마다 되풀이하지 않는다([MeAILimitsTable] 이 맨 위에서 한 번 부른다).
 */
@Composable
internal fun MeAILimitsColumnHeader() {
    Row(Modifier.fillMaxWidth().padding(bottom = AingDimens.space1).clearAndSetSemantics { }) {
        Spacer(Modifier.width((MeAILimitCardBudget.nameColumnWidth + MeAILimitCardBudget.nameGap).dp))
        MeAILimitColumnHeaderCell(AILimitWindow.fiveHour, Modifier.weight(1f))
        Spacer(Modifier.width(MeAILimitCardBudget.columnGap.dp))
        MeAILimitColumnHeaderCell(AILimitWindow.weekly, Modifier.weight(1f))
    }
}

@Composable
private fun MeAILimitColumnHeaderCell(window: AILimitWindow, modifier: Modifier) {
    val colors = AingTheme.colors
    Text(
        window.displayName,
        // INV-MeAILimitsCard-a1a5d158 이식: 열 머리 글자를 **그 열의 색으로 물들인다** — 글자 · 색 · 자리 셋이 같은 짝을 말하게 하는 것이 요점이다
        //   (색만으로 가르지 않는 것과 모순이 아니다).
        color = MeAILimitColumnColor.header(window, colors),
        style = MaterialTheme.typography.labelSmall.copy(fontSize = MeAILimitCardBudget.headerFontSize.sp),
        textAlign = TextAlign.End,
        maxLines = 1,
        modifier = modifier,
    )
}

/**
 * 제공자 사이 구분선. 카드 안쪽 여백 **바깥까지** 긋는다(승인된 문법 ④) — 레이아웃이 측정 폭보다 좌우 cardPadding 만큼 넓게 그린다.
 * INV-MeAILimitsCard-5024dd25 이식: **여기만 공유 팔레트를 쓰지 않는다** — 그 값(#2C3037)은 맥 팝오버·위젯 바탕에서 고른 것이라 한 단 밝은 폰 카드
 *   바탕(surface 다크 #2B2E3D) 위에서 1.01:1 로 안 보인다. 그래서 이 앱이 모든 카드에서 쓰는 구분선 토큰(separator)을 쓴다.
 */
@Composable
internal fun MeAILimitSeparator() {
    val color = AingTheme.colors.separator
    val extra = AingDimens.cardPadding
    Box(
        Modifier
            .fillMaxWidth()
            .layout { measurable, constraints ->
                val extraPx = extra.roundToPx()
                val width = constraints.maxWidth + extraPx * 2
                val placeable = measurable.measure(constraints.copy(minWidth = width, maxWidth = width))
                layout(constraints.maxWidth, placeable.height) { placeable.place(-extraPx, 0) }
            }
            .height(MeAILimitCardBudget.separatorHeight.dp)
            .background(color),
    )
}

/**
 * `[마크 이름/요금제][5시간 바 %][주간 바 %]` 한 줄. 소리는 한 문장(`MeAILimitsText.aiLimitRowAccessibility`).
 * INV-MeAILimitsCard-ebca93c9 이식: 라벨에 **기기 이름**을 넣는다(맥이 여럿일 때) — 머리글을 지나쳐 셋째 줄에 바로 닿은 사람에게 "Claude 5시간 91%" 는
 *   어느 맥인지 말하지 않는다. 화면에는 묶음 머리글이 이미 적었으므로 소리에만 싣는다.
 * INV-MeAILimitsCard-62fc0888 이식: 한 문장을 만드는 일은 **뷰 밖**이다(core/stores MeAILimitsText — 공용 시험이 순서·누락을 잰다).
 * INV-MeAILimitsCard-db3571ae 이식: 큰 글자(글꼴 배율 ≥ 1.5 — iOS AX 크기 자리)에서는 **격자를 접고 세로로 쌓는다**. 고정폭 격자는 기본 글자에서
 *   재어 만든 것이라 큰 글자에선 바가 사라지거나 숫자가 읽히지 않는다. 쌓은 모양에서도 정보는 하나도 빠지지 않는다(없는 창은 `없음`).
 */
@Composable
internal fun MeAILimitRow(row: AILimitDisplayRow, deviceName: String?, modifier: Modifier = Modifier) {
    val label = MeAILimitsText.aiLimitRowAccessibility(deviceName, row)
    val stacked = androidx.compose.ui.platform.LocalDensity.current.fontScale >= MeAILimitRowLayout.STACK_FONT_SCALE
    Box(modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = label }) {
        if (stacked) MeAILimitRowStacked(row) else MeAILimitRowGrid(row)
    }
}

object MeAILimitRowLayout {
    /** 이 글꼴 배율부터 격자를 접는다(iOS `isAccessibilitySize` ≈ 시스템 글자 크기 최대 단계 이상). */
    const val STACK_FONT_SCALE: Float = 1.5f
}

@Composable
private fun MeAILimitRowGrid(row: AILimitDisplayRow) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        MeAILimitNameColumn(row, Modifier.width(MeAILimitCardBudget.nameColumnWidth.dp))
        Spacer(Modifier.width(MeAILimitCardBudget.nameGap.dp))
        MeAILimitCell(row, AILimitWindow.fiveHour, Modifier.weight(1f))
        Spacer(Modifier.width(MeAILimitCardBudget.columnGap.dp))
        MeAILimitCell(row, AILimitWindow.weekly, Modifier.weight(1f))
    }
}

/** 왼쪽 고정 칸: [마크][이름 / 요금제]. 요금제를 모르면 이름만(빈 줄을 만들지 않는다). */
@Composable
private fun MeAILimitNameColumn(row: AILimitDisplayRow, modifier: Modifier) {
    val colors = AingTheme.colors
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(MeAILimitCardBudget.markGap.dp), verticalAlignment = Alignment.CenterVertically) {
        AIProviderMark(row.provider)
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(
                row.provider.displayName,
                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold, fontSize = MeAILimitCardBudget.nameFontSize.sp),
                color = colors.label,
                maxLines = 1,
            )
            val plan = row.planLabel
            if (plan != null) {
                Text(plan, style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal), color = colors.label2, maxLines = 1)
            }
        }
    }
}

/**
 * 한 칸 = 바 + 숫자. 세 모양: ① 값이 있다 ② 창은 있는데 판정 불가(`—`) ③ **그 창이 없다**(더 어두운 트랙 + `없음`).
 * INV-MeAILimitsCard-a1328eef 이식: 5시간 창이 **없는** 제공자는 그 칸을 `없음` 으로 비운다 — `—` 를 쓰지 않는다. 그 글자는 코어 규칙이
 *   '판정 불가(= 못 읽었다)'로 못 박았다(AILimitFreshnessRule.unknownValueText). 둘은 다른 사실이다.
 */
@Composable
private fun MeAILimitCell(row: AILimitDisplayRow, window: AILimitWindow, modifier: Modifier) {
    val colors = AingTheme.colors
    val display = row.display(window)
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(MeAILimitCardBudget.barValueGap.dp)) {
        MeAILimitBar(
            percent = display?.percent,
            floorOnly = display?.floorOnly ?: false,
            tint = MeAILimitColumnColor.bar(window, colors),
            track = if (display == null) MeAILimitColumnColor.absentTrack(colors) else MeAILimitColumnColor.emptyTrack(colors),
            modifier = Modifier.weight(1f),
        )
        MeAILimitValueText(display, Modifier.width(MeAILimitCardBudget.valueWidth.dp))
    }
}

/**
 * 숫자 글자. 사용량 단계는 이 글자가 말한다(바는 열 색을 쥐었다).
 * INV-AILimitColumnStyle-e5af3df9 이식: 창이 없는 칸은 `—` 가 아니라 `없음`(AILimitColumnText.absentValueText) — `—` 는 코어가 '판정 불가'로 못 박은 글자다.
 */
@Composable
private fun MeAILimitValueText(display: AILimitDisplay?, modifier: Modifier) {
    val colors = AingTheme.colors
    Text(
        display?.valueText ?: AILimitColumnText.absentValueText,
        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold, fontSize = MeAILimitCardBudget.valueFontSize.sp),
        color = if (display == null) MeAILimitColumnColor.absentText(colors) else MeAILimitColumnColor.usage(display.percent, colors),
        textAlign = TextAlign.End,
        maxLines = 1,
        modifier = modifier,
    )
}

@Composable
private fun MeAILimitRowStacked(row: AILimitDisplayRow) {
    val colors = AingTheme.colors
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(AingDimens.space2)) {
        Row(horizontalArrangement = Arrangement.spacedBy(MeAILimitCardBudget.markGap.dp), verticalAlignment = Alignment.CenterVertically) {
            AIProviderMark(row.provider)
            Text(
                row.planLabel?.let { "${row.provider.displayName} · $it" } ?: row.provider.displayName,
                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                color = colors.label,
            )
        }
        for (window in AILimitWindow.entries.sortedBy { it.sortOrder }) {
            val display = row.display(window)
            Column(verticalArrangement = Arrangement.spacedBy(AingDimens.space1)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(window.displayName, style = MaterialTheme.typography.labelSmall, color = MeAILimitColumnColor.header(window, colors), modifier = Modifier.weight(1f))
                    MeAILimitValueText(display, Modifier)
                }
                MeAILimitBar(
                    percent = display?.percent,
                    floorOnly = display?.floorOnly ?: false,
                    tint = MeAILimitColumnColor.bar(window, colors),
                    track = if (display == null) MeAILimitColumnColor.absentTrack(colors) else MeAILimitColumnColor.emptyTrack(colors),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

/**
 * 리밋 진행바(트랙 + 채움). [percent] null 이면 **트랙만** — 0% 로 그리면 "하나도 안 썼다"는 거짓이다.
 * INV-MeAILimitsCard-0d95dced 이식: 하한("27% 이상")은 채움을 **흐리게** 그린다 — 수단은 색이 아니라 **불투명도**다(AILimitFloorFill — 위젯 틴트·
 *   투명 모드는 색을 버리고 알파만 남긴다. 세 화면이 같은 수를 쓴다).
 */
@Composable
fun MeAILimitBar(percent: Double?, floorOnly: Boolean, tint: Color, track: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.height(MeAILimitCardBudget.barHeight.dp)) {
        val radius = CornerRadius(size.height / 2f)
        drawRoundRect(track, cornerRadius = radius)
        if (percent != null) {
            val fill = AILimitBarFill.width(size.width.toDouble(), percent).toFloat()
            if (fill > 0f) drawRoundRect(tint.copy(alpha = AILimitFloorFill.opacity(floorOnly).toFloat()), size = Size(fill, size.height), cornerRadius = radius)
        }
    }
}

/**
 * 제공자 마크(26 dp 타일). 로고 벡터(Swift `AIProviderTile` — 지시적 사용, 기억 third-party-logo-nominative-decision)는 이번 판에서 옮기지 않았다:
 * 제공자 첫 글자 타일로 대신한다(보고 — 로고 벡터는 W2-h 데스크톱 리밋과 한 벌로 옮길 일).
 */
@Composable
internal fun AIProviderMark(provider: AILimitProvider) {
    val colors = AingTheme.colors
    Box(
        Modifier
            .size(MeAILimitCardBudget.markSide.dp)
            .background(colors.fill, RoundedCornerShape(7.dp)),
        contentAlignment = Alignment.Center,
    ) {
        Text(provider.displayName.take(1), style = MaterialTheme.typography.labelMedium, color = colors.label)
    }
}

/**
 * 두 열의 색(Swift `AILimitColumnPalette` 값 — **어두운 쪽이 승인본 16진수 그대로**, 밝은 쪽은 같은 색상에서 명도만 뒤집은 값).
 * 색이 뜻하는 것은 **창 종류**다(제공자가 아니다).
 */
object MeAILimitColumnColor {
    private data class Pair(val light: Long, val dark: Long) {
        fun pick(colors: AingColors): Color = Color(if (colors.isDark) dark else light)
    }

    private val fiveHourBar = Pair(0xFF3B7BE8, 0xFF5B8DEF)
    private val fiveHourHeader = Pair(0xFF1F62C9, 0xFF7FA8F5)
    private val weeklyBar = Pair(0xFF7A5FD6, 0xFF8A76E0)
    private val weeklyHeader = Pair(0xFF5A42B8, 0xFFA796E8)
    // INV-AILimitColumnStyle-57d6a56f 이식: 라이트 값은 승인본(어두운 한 벌)을 그대로 쓰지 않는다 — #30343B 트랙은 흰 카드 위에서 검은 막대(= 100% 찬 바)로
    //   읽히고 #7FA8F5 머리는 흰 바탕에서 3.2:1 이다. 그래서 어두운 쪽만 승인본 16진수, 밝은 쪽은 같은 색상에서 명도를 뒤집은 값이다.
    private val emptyTrack = Pair(0xFFE3E5EA, 0xFF30343B)

    // INV-AILimitColumnStyle-3275413f 이식: 창이 없는 칸의 트랙은 승인본(어두운 팝오버·위젯 바탕 전제) 그대로다 — 폰 카드(surface 다크 #2B2E3D)에서는 '조금 어두운 홈'으로
    //   보이지만 채움으로 읽히지 않고 같은 칸의 `없음` 글자가 사실을 말한다. 세 화면이 한 표를 쓰는 편이 바탕마다 값을 가르는 것보다 안전하다.
    private val absentTrack = Pair(0xFFF1F2F5, 0xFF22262C)

    // INV-AILimitColumnStyle-27be8c98 이식: `없음` 글자는 줄에서 **가장 조용하다**(대비 2.1:1 수준 — 승인된 선택). 값이 아니라 '값이 없다는 사실'이라 숫자보다 먼저
    //   눈에 들어오면 안 되고, 사실은 더 어두운 트랙 · 채움 없음이 같이 말한다. 글자를 올리려면 승인본을 먼저 고친다.
    private val absentText = Pair(0xFF9BA1AC, 0xFF595E67)

    // INV-AILimitColumnStyle-1694c631 이식: 창이 **셋**이 되는 날 새 창이 조용히 5시간 열(파랑)로 떨어지지 않게 빠짐없는 when 이다(else 없음 —
    //   AILimitWindow 를 넓히면 여기가 컴파일로 막힌다).
    fun bar(window: AILimitWindow, colors: AingColors): Color = when (window) {
        AILimitWindow.fiveHour -> fiveHourBar
        AILimitWindow.weekly -> weeklyBar
    }.pick(colors)

    fun header(window: AILimitWindow, colors: AingColors): Color = when (window) {
        AILimitWindow.fiveHour -> fiveHourHeader
        AILimitWindow.weekly -> weeklyHeader
    }.pick(colors)
    fun emptyTrack(colors: AingColors): Color = emptyTrack.pick(colors)
    fun absentTrack(colors: AingColors): Color = absentTrack.pick(colors)
    fun absentText(colors: AingColors): Color = absentText.pick(colors)

    /**
     * 사용량 단계 색 — 경계는 [AILimitUsageStage], 반올림은 **코어 규칙**(글자가 `90%` 라고 적으면 색도 거기서 갈린다).
     * INV-AILimitColumnStyle-83cfeb85 이식: 단계는 **글자가 쓰는 수**(반올림한 정수 퍼센트 — AILimitFreshnessRule.wholePercent)로 가른다. 날것 double 로 90 을 가르면
     *   89.5% 에서 글자는 `90%` 인데 색은 평온해 같은 자리가 다른 단계를 말한다(맥 2026-10-07 결함).
     */
    fun usage(percent: Double?, colors: AingColors): Color = when (AILimitUsageStage.stage(percent?.let(AILimitFreshnessRule::wholePercent))) {
        AILimitUsageStage.calm -> colors.label
        AILimitUsageStage.warn -> colors.pending
        AILimitUsageStage.danger -> colors.danger
    }
}

/** 사용량 단계(Swift `AILimitUsageStage`). nil(판정 불가 · 창 없음)은 calm — 모르는 값에 경고를 붙이지 않는다. */
@Suppress("EnumEntryName")
enum class AILimitUsageStage {
    calm, warn, danger;

    companion object {
        const val warnPercent = 70
        const val dangerPercent = 90

        fun stage(wholePercent: Int?): AILimitUsageStage = when {
            wholePercent == null -> calm
            wholePercent >= dangerPercent -> danger
            wholePercent >= warnPercent -> warn
            else -> calm
        }
    }
}

/** 바 채움 폭(Swift `AILimitBarFill` — 폰·위젯·맥이 같은 산식). 0 보다 큰 사용량은 바 폭의 8%(최소 2) 이상 보인다. */
object AILimitBarFill {
    fun minimumFill(barWidth: Double): Double = max(2.0, barWidth * 0.08)

    fun width(barWidth: Double, percent: Double?): Double {
        if (barWidth <= 0 || percent == null) return 0.0
        val clamped = min(100.0, max(0.0, percent))
        if (clamped <= 0) return 0.0
        return min(barWidth, max(minimumFill(barWidth), barWidth * clamped / 100))
    }
}

/**
 * 하한 채움 불투명도(Swift `AILimitFloorFill`).
 * INV-AILimitSurfaceRules-ef8028d4 이식: 하한은 색이 아니라 **불투명도**로 말한다 — 위젯 틴트·투명 모드는 색을 통째로 버리고 알파만 남긴다.
 */
object AILimitFloorFill {
    const val floorOpacity: Double = 0.55

    fun opacity(floorOnly: Boolean): Double = if (floorOnly) floorOpacity else 1.0
}

/**
 * 스냅숏·미리보기 장면이 쓰는 묶음 만들기.
 * INV-MeAILimitsCard-0b2615db 이식: 스토어와 **같은 두 함수**를 지난다(기기 묶기 → 그릴 묶음). 장면이 이름 가르기·코어 규칙을 자기 손으로 다시 적으면
 *   사람이 보는 그림이 화면과 다른 규칙으로 서고, 그 그림으로 승인을 받으면 틀린 것이 굳는다.
 * INV-MeAILimitsCard-f50d3b6f 이식: 장면 목록에 **맥 두 대**(묶음 머리글 · 열 머리 한 번 · 둘째 묶음이 카드 속 카드로 안 보이는지)를 둔다 — ui 스냅숏
 *   (`ui/snapshots/screens/me`) 의 `me-ailimits-two-devices`.
 * INV-MeAILimitsCard-39975ad9 이식: **이름이 겹치는** 맥 두 대(꼬리가 붙은 가장 넓은 머리글이 한 줄에 드는지) — `me-ailimits-twin-names`.
 * INV-MeAILimitsCard-c6d050c8 이식: 좁은 기기 + 두 대 — 폰 스냅숏 폭(360dp)이 iOS 가장 좁은 375 보다 좁아 그 자리를 덮는다.
 * INV-MeAILimitsCard-664f60e2 이식: **상한 길이(64 스칼라) 이름이 겹친 맥 두 대** — 이름은 두 줄에서 잘려도 꼬리 둘이 남아 두 머리글이 달라 보이는지
 *   (`me-ailimits-twin-long-names`).
 */
object MeAILimitsScenes {
    fun fold(rows: List<com.yehsung.aingcheck.core.stores.me.AILimitFetchedRow>, now: com.yehsung.aingcheck.core.wire.SwiftDate): List<AILimitDeviceDisplayGroup> =
        AILimitsStore.displayGroups(AILimitsStore.groups(rows, now), now)
}
