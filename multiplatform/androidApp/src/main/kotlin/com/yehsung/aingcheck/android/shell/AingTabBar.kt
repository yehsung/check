// 원본: Sources/CheckMobileKit/App/MobileRootView.swift @ 39199b0 (MobileTabsView — 탭 다섯 · .badge · meLabel)
// 원본: Sources/CheckMobileShared/AingRoute.swift @ 39199b0 (AingTab.systemImage) · Sources/CheckMobileKit/Components/CharacterTabIcon.swift
// 원본: Sources/CheckMobileKit/Now/NowStore.swift @ 39199b0 (displayedCharacterID · displayedMood — 나 탭 얼굴)
//
// 셸 탭 막대(iOS UITabBar 모양을 AingTheme 안에서). M3 NavigationBar 를 쓰지 않는다 — 고른 탭 받침 알약(indicator)·80dp 높이가
// iOS 막대와 다르고, 배지가 아이콘을 덮지 않게 자리를 직접 잡는다.
//  · 기호: SF Symbols(clock.fill …) → Material Symbols 채움 짝(SfSymbols 표 — 같은 이름 대응). '나' 탭은 착용 캐릭터 초상 + 근무 링
//    (CharacterTabIcon — 틴트 없음), 그림이 없으면 사람 기호로 접는다.
//  · 색: 고른 탭 = tabSelected(colorScheme.secondary — iOS 탭 선택색, 라이트는 accent 와 같은 #1864CF), 안 고른 탭 = label2 를 카드 위에
//    겹친 회색(onSurfaceVariant). 파랑은 '선택'만 뜻한다(G §8-15 — ShellTabColorsTest).
//  · 배지: 빨간 숫자(iOS 시스템 빨강 #FF3B30)를 기호 **오른쪽 위**에 얹는다 — 기호를 대신하지 않는다. 0 이면 없다.
//  · 막대 면 = 유리(colorScheme.surfaceContainer) + 위 머리카락 선(separator). 높이 56dp(+ 제스처 영역 인셋), 칸마다 터치 56dp.
package com.yehsung.aingcheck.android.shell

import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.android.routing.AingTab
import com.yehsung.aingcheck.core.stores.now.NowMyCard
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.AvatarFraming
import com.yehsung.aingcheck.ui.components.CharacterTabIcon
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.icons.SfSymbols
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 탭 기호(iOS AingTab.systemImage 그대로 — SF 이름 → Material Symbols 채움 짝). */
object ShellTabIcons {
    /** iOS AingTab.systemImage. */
    fun systemImage(tab: AingTab): String = when (tab) {
        AingTab.NOW -> "clock.fill"
        AingTab.MESSAGES -> "bubble.left.and.bubble.right.fill"
        AingTab.RANKINGS -> "trophy.fill"
        AingTab.GAMES -> "gamecontroller.fill"
        AingTab.ME -> "person.crop.circle.fill"
    }

    /** 대응표(SfSymbols)에 없으면 시험이 빨개진다 — 여기서 대신 그리지 않는다. */
    fun icon(tab: AingTab): AppIcon = requireNotNull(SfSymbols.toAppIcon[systemImage(tab)]) { "SF ${systemImage(tab)} 대응 없음" }
}

/**
 * '나' 탭 얼굴(착용 캐릭터 초상 + 표정). [art] 가 null 이면 사람 기호로 접는다(iOS meLabel).
 * [characterID] 는 아바타 틀([AvatarFraming.of] — 케이크 둘만 몸을 아잉 크기로 되돌린다, iOS CharacterTabIcon)을 고르는 데만 쓴다. null = 아잉.
 */
data class MeTabFace(val art: ImageBitmap?, val mood: CharacterMood, val characterID: String? = null)

/**
 * '나' 탭 얼굴 규칙(iOS NowStore.displayedCharacterID · displayedMood). **새 서버 호출 없음**.
 *  - 캐릭터: 나 탭이 알아 온 착용값 → 위젯 스냅숏의 지난 값 → 둘 다 없으면 null(= 기본 아잉).
 *  - 표정: 지금 탭 내 카드(근무 중 · 끊김 · 안 함) → 스냅숏 상태 → 모르면 링 없는 기본 얼굴(Plain).
 */
object ShellTabFace {
    data class Face(val characterID: String?, val mood: CharacterMood)

    fun of(
        equippedLoaded: Boolean,
        equippedCharacterID: String?,
        snapshotCharacterID: String?,
        nowCard: NowMyCard?,
        snapshotMood: CharacterMood?,
    ): Face {
        val id = (if (equippedLoaded) equippedCharacterID else null) ?: snapshotCharacterID
        val mood = when {
            nowCard != null -> if (nowCard.isWorking) (if (nowCard.isStale) CharacterMood.Lost else CharacterMood.Working) else CharacterMood.Off
            snapshotMood != null -> snapshotMood
            else -> CharacterMood.Plain
        }
        return Face(id, mood)
    }
}

/** 시험 태그(기기 시험 · 셸 시험이 쓰는 이름 — 바꾸지 않는다). */
object ShellTabTags {
    const val BAR = "tab-bar"
    fun tab(tab: AingTab) = "tab:${tab.name.lowercase()}"
    fun badge(tab: AingTab) = "tab-badge:${tab.name.lowercase()}"
    fun icon(tab: AingTab) = "tab-icon:${tab.name.lowercase()}"
}

/** 탭 막대 치수(iOS 49pt 막대 · 기호 칸 약 28pt · 이름 10pt — 안드로이드 터치 48dp 바닥에 맞춰 칸을 56dp 로). */
object ShellTabMetrics {
    val barHeight = 56.dp
    val iconBox = 28.dp
    val symbolSize = 24.dp
    val badgeHeight = 18.dp
    /** 배지 왼쪽 끝 = 기호 칸 왼쪽에서 16dp(가운데보다 2dp 오른쪽) — 숫자가 늘면 오른쪽으로 자란다. 위로 5dp 올린다. */
    val badgeX = 16.dp
    val badgeY = (-5).dp
}

/**
 * @param selected 고른 탭인지(셸이 내비게이션 계층으로 판정).
 * @param badge 탭 배지 수(0 이면 없음).
 * @param meFace '나' 탭 얼굴. null 이면 사람 기호.
 */
@Composable
fun AingTabBar(
    selected: (AingTab) -> Boolean,
    badge: (AingTab) -> Int,
    meFace: MeTabFace?,
    onSelect: (AingTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    Column(modifier.fillMaxWidth().background(scheme.surfaceContainer).testTag(ShellTabTags.BAR)) {
        // iOS 막대 위 머리카락 선.
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(AingTheme.colors.separator))
        Row(
            Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars).height(ShellTabMetrics.barHeight).selectableGroup(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AingTab.entries.forEach { tab ->
                val isSelected = selected(tab)
                AingTabItem(
                    tab = tab,
                    selected = isSelected,
                    badge = badge(tab),
                    face = if (tab == AingTab.ME) meFace?.takeIf { it.art != null } else null,
                    tint = if (isSelected) scheme.secondary else scheme.onSurfaceVariant,
                    onClick = { onSelect(tab) },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun AingTabItem(
    tab: AingTab,
    selected: Boolean,
    badge: Int,
    face: MeTabFace?,
    tint: Color,
    onClick: () -> Unit,
    modifier: Modifier,
) {
    val interaction = remember { MutableInteractionSource() }
    Column(
        modifier
            .fillMaxHeight()
            .selectable(
                selected = selected,
                onClick = onClick,
                role = Role.Tab,
                interactionSource = interaction,
                indication = ripple(bounded = false, radius = ShellTabMetrics.barHeight / 2),
            )
            .testTag(ShellTabTags.tab(tab)),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(Modifier.size(ShellTabMetrics.iconBox).testTag(ShellTabTags.icon(tab)), contentAlignment = Alignment.Center) {
            // 기호는 읽지 않는다 — 탭 이름(아래 글자)이 이 칸의 이름이다(얼굴 초상의 "내 캐릭터, 근무 중"도 탭 이름을 덮지 않게).
            if (face != null) {
                CharacterTabIcon(face.art, face.mood, Modifier.clearAndSetSemantics {}, framing = AvatarFraming.of(face.characterID))
            } else {
                AingIcon(ShellTabIcons.icon(tab), contentDescription = null, size = ShellTabMetrics.symbolSize, tint = tint)
            }
            if (badge > 0) TabBadge(badge, Modifier.align(Alignment.TopStart).offset(ShellTabMetrics.badgeX, ShellTabMetrics.badgeY).testTag(ShellTabTags.badge(tab)))
        }
        Spacer(Modifier.height(2.dp))
        Text(
            tab.title,
            color = tint,
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, lineHeight = 13.sp, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium, textAlign = TextAlign.Center, letterSpacing = 0.sp),
            maxLines = 1,
        )
    }
}

/** iOS 탭 배지: 빨간 둥근 칸 + 흰 숫자(최소 18dp 원, 숫자가 늘면 옆으로). */
@Composable
private fun TabBadge(count: Int, modifier: Modifier) {
    Box(
        modifier
            .defaultMinSize(minWidth = ShellTabMetrics.badgeHeight, minHeight = ShellTabMetrics.badgeHeight)
            .background(AingTheme.colors.badge, RoundedCornerShape(50))
            .padding(horizontal = 5.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "$count",
            color = AingTheme.colors.onAccentFill, // 흰색(두 모드) — 셸은 색을 손으로 만들지 않는다(D5)
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, letterSpacing = 0.sp),
            maxLines = 1,
        )
    }
}
