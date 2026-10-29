// 원본: Sources/CheckMobileKit/Me/MeAchievementViews.swift @ 3bd04bd (MeAchievementLayout · MeClaimButton · MeClaimBurstView)
//
// [받기] 버튼 · 받기 연출 — 도전(누적) 미션 줄 · 일일 미션 줄 · 이번 주 근무 카드가 **같은 버튼 · 같은 연출**을 쓴다.
// 새로 만들면 햅틱이 두 벌이 되어 한 번 받을 때 두 번 운다(햅틱은 「미션」 화면 한 곳 — MissionsScreen).
//
// 연출은 짧고(0.9초) 꽃가루가 없으며 동작 줄이기를 따른다. **불투명도는 이징으로 깎지 않는다**(기억 easing-must-not-drive-opacity):
// 떠오름 · 커짐은 easeOut(AingMotion.moveProgress), 흐려짐은 떠오름이 거의 끝난 뒤(뒤 20%) 시작하는 **짧은 직선**(AingMotion.fadeOutOpacity).
// 진행도 자체는 직선 시계(LinearEasing) 하나다 — 움직임 곡선은 그 위에서 손으로 건다.
package com.yehsung.aingcheck.ui.missions

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.ui.components.RubyIcon
import com.yehsung.aingcheck.ui.shop.MeType
import com.yehsung.aingcheck.ui.shop.MeType.digits
import com.yehsung.aingcheck.ui.shop.rememberRuby
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingMotion
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 도전 미션 절의 크기 규약(받기 버튼 · 주간 카드가 같은 값을 쓴다). */
object MeAchievementLayout {
    /** 줄 하나의 최소 높이(아이콘 + 제목/막대/보조 세 줄). */
    val rowMinHeight: Dp = 64.dp
    val rowSpacing: Dp = AingDimens.space3

    /** [받기] 캡슐의 보이는 높이. 누름 영역은 44 로 따로 넓힌다. */
    val claimHeight: Dp = 32.dp

    /** 받기 연출이 떠오르는 높이 — 줄 안에서 끝난다. */
    val burstRise: Dp = 18.dp

    /** 연출 전체 길이(밀리초) · 흐려지는 꼬리 길이(밀리초) — 꼬리는 전체의 뒤 20%. */
    const val BURST_MS = 900
    const val BURST_FADE_MS = 180

    /** 줄을 아직 모르는 동안 절이 미리 잡아 두는 줄 수(지금 서버가 주는 계열 수 — 어긋나면 덜 흔들리는 정도만 달라진다). */
    const val PLACEHOLDER_ROWS = 9

    /** 미리 잡아 둘 본문 높이. */
    val reservedHeight: Dp get() = rowMinHeight * PLACEHOLDER_ROWS + rowSpacing * (PLACEHOLDER_ROWS - 1)

    /** 흐려짐이 시작하는 진행도(0.8). */
    val fadeHold: Float get() = 1f - BURST_FADE_MS.toFloat() / BURST_MS
}

/** [받기 💎+50]. 강조 채움 캡슐 + 흰 글자. 떠 있으면 돌림으로 바뀌고 눌리지 않는다. 누름 영역은 늘 44 이상. */
@Composable
fun MeClaimButton(amount: Long, inFlight: Boolean = false, enabled: Boolean = true, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val c = AingTheme.colors
    Box(
        modifier
            .heightIn(min = AingDimens.minimumTarget)
            .clip(CircleShape)
            .clickable(enabled = enabled && !inFlight, role = Role.Button, onClick = onClick)
            .clearAndSetSemantics {
                contentDescription = MeText.claimAccessibility(amount)
                role = Role.Button
            },
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier
                .graphicsLayer { alpha = if (inFlight) 0.6f else 1f }
                .defaultMinSize(minHeight = MeAchievementLayout.claimHeight)
                .background(c.accentFill, CircleShape)
                .padding(horizontal = AingDimens.space3),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            if (inFlight) {
                CircularProgressIndicator(Modifier.size(14.dp), color = c.onAccentFill, strokeWidth = 2.dp)
            } else {
                Text(MeText.claimButton, style = MeType.footnote.copy(fontWeight = FontWeight.Bold), color = c.onAccentFill)
                RubyIcon(rememberRuby(14f), 14.dp)
                Text(MeText.claimAmount(amount), style = MeType.footnote.copy(fontWeight = FontWeight.ExtraBold).digits(), color = c.onAccentFill)
            }
        }
    }
}

/**
 * 받기 연출 — "+N" 알약이 그 자리에서 톡 떠올랐다가 사라진다(0.9초 · 한 번 재생하고 끝). 다시 재생하려면 부르는 쪽이 [serial] 을 바꾼다.
 * [frozenProgress] 가 있으면 그 진행도로 멈춘 그림(스냅숏 · 시험).
 */
@Composable
fun MeClaimBurstView(amount: Long, serial: Int, reduceMotion: Boolean, modifier: Modifier = Modifier, frozenProgress: Float? = null) {
    val c = AingTheme.colors
    val clock = remember(serial) { Animatable(frozenProgress ?: 0f) }
    LaunchedEffect(serial, frozenProgress) {
        if (frozenProgress == null) clock.animateTo(1f, tween(MeAchievementLayout.BURST_MS, easing = LinearEasing))
    }
    val k = frozenProgress ?: clock.value
    val move = if (reduceMotion) 1f else AingMotion.moveProgress(k)
    val opacity = AingMotion.fadeOutOpacity(k, MeAchievementLayout.fadeHold)
    val rise = MeAchievementLayout.burstRise
    Row(
        modifier
            .clearAndSetSemantics { }
            .graphicsLayer {
                val s = if (reduceMotion) 1f else 0.7f + 0.3f * move
                scaleX = s
                scaleY = s
                translationY = if (reduceMotion) 0f else -rise.toPx() * move
                alpha = opacity
            }
            // 불투명 바탕 — 떠오르는 동안 아래 줄 글자("✓ 받음")와 겹쳐 읽히지 않게.
            .background(c.surface2, CircleShape)
            .border(1.dp, c.working.copy(alpha = 0.55f), CircleShape)
            .defaultMinSize(minHeight = 26.dp)
            .padding(horizontal = AingDimens.space2),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        RubyIcon(rememberRuby(14f), 14.dp)
        Text(MeText.claimAmount(amount), style = MeType.footnote.copy(fontWeight = FontWeight.ExtraBold).digits(), color = c.working)
    }
}
