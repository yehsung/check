// 원본: Sources/CheckMobileKit/Games/GamesMiniGamePause.swift:32-105 @ de5c153b
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.minigame.MiniGamePauseState
import com.yehsung.aingcheck.ui.games.minigame.kit.PillButton
import com.yehsung.aingcheck.ui.games.minigame.kit.PillKind
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 판 위 글자의 상한(iOS `dynamicTypeSize(...accessibility1)` 자리). 판 폭(최소 288)을 넘지 않는 크기까지다. */
private const val MAX_PAUSE_FONT_SCALE: Float = 1.5f

/**
 * 폰 정지 화면: 캔버스를 **완전히 가리는** 스크림 + 카드(또는 3-2-1). 맥 `pauseOverlay` 의 폰판이다.
 *
 * 스크림이 불투명인 이유는 미관이 아니다 — 순위표가 걸린 게임이라 멈춰 놓고 다음 칸을 외우는 것이 이득이 되면 안 된다(맥 실측: 0.93 만 얹었더니 판이 비쳤다).
 * 판은 라이트 모드에서도 어둡다. 단추 토큰이 라이트 값을 고르면 어두운 스크림 위에 어두운 빨강이 되어 [그만두기] 가 안 읽힌다(iOS 라이트 캡처 실측) — 안쪽은 늘 다크 토큰이다.
 */
@Composable
internal fun GamesMiniGamePauseOverlay(kind: MiniGameKind, state: MiniGamePauseState, onResume: () -> Unit, onQuit: () -> Unit) {
    val density = LocalDensity.current
    Box(
        Modifier.fillMaxSize().clip(RoundedCornerShape(14.dp)).background(GamesCanvasColors.panel),
        contentAlignment = Alignment.Center,
    ) {
        CompositionLocalProvider(LocalDensity provides Density(density.density, minOf(density.fontScale, MAX_PAUSE_FONT_SCALE))) {
            AingTheme(dark = true) {
                val countdown = state.countdown
                if (state.showsCard) PauseCard(kind, onResume, onQuit)
                else if (countdown != null) PauseCountdown(countdown)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PauseCard(kind: MiniGameKind, onResume: () -> Unit, onQuit: () -> Unit) {
    Column(
        Modifier.padding(AingDimens.space4),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
    ) {
        Box(Modifier.size(34.dp).background(GamesCanvasColors.pending.copy(alpha = 0.16f), CircleShape), contentAlignment = Alignment.Center) {
            AingIcon(AppIcon.PauseFill, contentDescription = null, size = 18.dp, tint = GamesCanvasColors.pending)
        }
        Text(GamesMiniGameText.pauseTitle, style = MaterialTheme.typography.titleMedium, color = GamesCanvasColors.primaryText)
        Text(GamesMiniGameText.pauseSubtitle(kind), style = MaterialTheme.typography.bodySmall, color = GamesCanvasColors.secondaryText, textAlign = TextAlign.Center)
        // 큰 글자에서는 위아래로 접는다 — 좁은 판에서 단추 글자가 잘리면 무엇을 누르는지 모른다.
        FlowRow(
            Modifier.padding(top = AingDimens.space1),
            horizontalArrangement = Arrangement.spacedBy(AingDimens.space2, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(AingDimens.space2),
        ) {
            PillButton(GamesMiniGameText.resumeAction, Modifier.testTag(MiniGameScreenTags.RESUME), kind = PillKind.Filled, icon = AppIcon.PlayArrowFill, onClick = onResume)
            PillButton(GamesMiniGameText.quitAction, Modifier.testTag(MiniGameScreenTags.QUIT), kind = PillKind.Destructive, icon = AppIcon.Close, onClick = onQuit)
        }
    }
}

@Composable
private fun PauseCountdown(remaining: Int) {
    Column(
        Modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(remaining.toString(), style = MaterialTheme.typography.displayLarge.copy(fontSize = 68.sp, fontWeight = FontWeight.ExtraBold), color = GamesCanvasColors.accent)
        Text(GamesMiniGameText.resumeCountdownCaption, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold), color = GamesCanvasColors.secondaryText)
    }
}
