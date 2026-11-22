// 원본: Sources/CheckMobileKit/Games/GamesAlkkagiBoard.swift(GamesAlkkagiGuideDrawing · GamesAlkkagiPullHint · guideOverlay) ·
//       GamesAlkkagiScreen.swift(GamesAlkkagiCoachCard) @ faba845a (아이폰 1.0.19 — 맥 0.3.86 C안의 폰 짝)
//
// 알까기 안내(판 9 · 대표 #d_xygj8oZRFlfH 5번 — 대표 11-10 "어디다 돌 둬야되는지 판 구분도 별로 안되어있고 … 뭘 하라는건지 모르겠어").
//  · 숨겨 놓기: 둘 수 있는 **실제** 칸(흑 y ≥ 320 · 백 y ≤ 280 = canPlace)만 파랗게 + 점선 + '내 진영', 그 밖은 어둡게 · 가운데 빈 띠에 큰 안내 한 줄.
//  · 쏘기 차례: 쏠 수 있는 내 돌마다 초록 고리 · 판 가운데에 가까운 돌에 손이 뒤로 당기고 날아갈 쪽 화살(2초 한 바퀴 · 동작 줄이기면 한 장면).
//    이 기기에서 세 번 쏘면 더 안 나온다(판 모델이 센다).
//  · 처음 하는 알까기 — 로비 위 세 줄 카드 · [알겠어요].
// 값(경계 · 손 박자 · 글)은 코어(AlkkagiPhoneGuideGeometry · AlkkagiPhoneGuideText)에 있고 이 파일은 그리기만 한다.
package com.yehsung.aingcheck.ui.games.alkkagi

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiGame
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiPhoneFirstTimeCoach
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiPhoneGuideGeometry
import com.yehsung.aingcheck.core.stores.alkkagi.AlkkagiPhoneGuideText
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.AingButton
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** 안내 그림(맥 `AlkkagiGuideDrawing` · 아이폰 `GamesAlkkagiGuideDrawing` 과 같은 그림). */
object GamesAlkkagiGuideDrawing {
    /** 숨겨 놓기: 내 칸만 파랗게 + 점선 테두리 + '내 진영' 이름표, 그 밖(상대 칸 + 가운데 빈 띠)은 어둡게. */
    fun zones(scope: DrawScope, mine: AlkkagiGame.Player, accent: Color, measurer: TextMeasurer) = with(scope) {
        val s = (size.width / AlkkagiGame.boardSize).toFloat()
        val blackTop = (AlkkagiPhoneGuideGeometry.blackZoneTop * s).toFloat()
        val whiteBottom = (AlkkagiPhoneGuideGeometry.whiteZoneBottom * s).toFloat()
        val black = mine == AlkkagiGame.Player.black
        val mineTop = if (black) blackTop else 0f
        val mineHeight = if (black) size.height - blackTop else whiteBottom
        val theirTop = if (black) 0f else blackTop
        val theirHeight = if (black) whiteBottom else size.height - blackTop
        val outsideTop = if (black) 0f else whiteBottom
        val outsideHeight = if (black) blackTop else size.height - whiteBottom
        drawRect(Color.Black.copy(alpha = 0.48f), Offset(0f, outsideTop), Size(size.width, outsideHeight))
        drawRect(accent.copy(alpha = 0.55f), Offset(0f, mineTop), Size(size.width, mineHeight))
        val inset = 3.dp.toPx()
        drawRoundRect(
            accent, Offset(inset, mineTop + inset), Size(size.width - inset * 2, mineHeight - inset * 2), CornerRadius(8.dp.toPx()),
            style = Stroke(2.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(10.dp.toPx(), 5.dp.toPx()))),
        )
        val mineLabel = measurer.measure(AlkkagiPhoneGuideText.mineZone, TextStyle(color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Black))
        val labelY = if (black) mineTop + mineHeight - 18.dp.toPx() else mineTop + 18.dp.toPx()
        val pw = mineLabel.size.width + 20.dp.toPx()
        val ph = mineLabel.size.height + 8.dp.toPx()
        drawRoundRect(accent, Offset(size.width / 2 - pw / 2, labelY - ph / 2), Size(pw, ph), CornerRadius(ph / 2))
        drawText(mineLabel, topLeft = Offset(size.width / 2 - mineLabel.size.width / 2, labelY - mineLabel.size.height / 2))
        val theirLabel = measurer.measure(AlkkagiPhoneGuideText.theirZone,
            TextStyle(color = Color.White.copy(alpha = 0.6f), fontSize = 15.sp, fontWeight = FontWeight.SemiBold))
        drawText(theirLabel, topLeft = Offset(size.width / 2 - theirLabel.size.width / 2, theirTop + theirHeight / 2 - theirLabel.size.height / 2))
    }

    /** 쏘기 차례: 쏠 수 있는 내 돌마다 초록 고리(뒤집기의 '둘 수 있는 곳' 점처럼). */
    fun myStones(scope: DrawScope, scale: Float, stones: List<AlkkagiGame.Stone>, mine: AlkkagiGame.Player, working: Color) = with(scope) {
        val r = (AlkkagiGame.stoneRadius * scale).toFloat() + 4.dp.toPx()
        for (stone in stones) {
            if (stone.owner != mine || !stone.isPlaced || stone.isOut) continue
            drawCircle(working.copy(alpha = 0.9f), r, Offset((stone.position.x * scale).toFloat(), (stone.position.y * scale).toFloat()), style = Stroke(2.5.dp.toPx()))
        }
    }

    /** 손 안내의 자리(판 좌표 → 점) — 손 · 말풍선을 그릴 자리를 그림과 덮개가 같이 쓴다. */
    data class PullHintPoints(val stone: Offset, val pullEnd: Offset, val fullEnd: Offset, val back: Float)

    fun pullHintPoints(scale: Float, stone: AlkkagiGame.Stone, mine: AlkkagiGame.Player, pullFraction: Double): PullHintPoints {
        // 흑(아래)은 아래로 당겨 위로, 백(위)은 위로 당겨 아래로 쏜다. 판 밖으로 손이 나가지 않게 당김 길이를 줄인다.
        val back = if (mine == AlkkagiGame.Player.black) 1f else -1f
        val p = Offset((stone.position.x * scale).toFloat(), (stone.position.y * scale).toFloat())
        val room = if (mine == AlkkagiGame.Player.black) AlkkagiGame.boardSize - stone.position.y else stone.position.y
        val fullReach = max(24.0, min(62.0, room - 18)).toFloat()
        val f = pullFraction.toFloat()
        val pullEnd = Offset(p.x + 18 * scale * f, p.y + back * fullReach * f * scale)
        val fullEnd = Offset(p.x + 18 * scale, p.y + back * fullReach * scale)
        return PullHintPoints(p, pullEnd, fullEnd, back)
    }

    /** 손 안내 한 장면의 선 · 화살. [pullFraction] 0…1 = 손이 당긴 정도, [release] 0…1 = 놓은 뒤 화살이 밝아지는 정도. 손 · 말풍선은 덮개가 그린다. */
    fun pullHint(scope: DrawScope, scale: Float, stone: AlkkagiGame.Stone, mine: AlkkagiGame.Player, pullFraction: Double, release: Double, working: Color) =
        with(scope) {
            val pts = pullHintPoints(scale, stone, mine, pullFraction)
            val p = pts.stone
            val r = (AlkkagiGame.stoneRadius * scale).toFloat()
            if (pullFraction > 0.02) {
                drawLine(Color.White.copy(alpha = 0.95f), p, pts.pullEnd, 2.5.dp.toPx(), StrokeCap.Round,
                    PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx())))
            }
            // 날아갈 쪽(반대) 화살 — 당긴 반대 방향. 당기기 전에는 기본 방향(상대 쪽 · 조금 비스듬히).
            val dx = if (pullFraction > 0.02) p.x - pts.pullEnd.x else -18 * scale
            val dy = if (pullFraction > 0.02) p.y - pts.pullEnd.y else -pts.back * 62 * scale
            val len = max(1f, sqrt(dx * dx + dy * dy))
            val ux = dx / len
            val uy = dy / len
            val start = Offset(p.x + ux * (r + 5), p.y + uy * (r + 5))
            val tip = Offset(p.x + ux * (r + 78 * scale), p.y + uy * (r + 78 * scale))
            val arrow = working.copy(alpha = (0.55 + 0.4 * max(pullFraction, release)).toFloat())
            drawLine(arrow, start, tip, 3.5.dp.toPx(), StrokeCap.Round)
            val head = Path().apply {
                moveTo(tip.x, tip.y)
                lineTo(tip.x - ux * 11 - uy * 7, tip.y - uy * 11 + ux * 7)
                lineTo(tip.x - ux * 11 + uy * 7, tip.y - uy * 11 - ux * 7)
                close()
            }
            drawPath(head, arrow)
        }
}

/**
 * 손 안내 — 판 위 덮개(입력을 막지 않는다 · 보이스오버에 숨김). 동작 줄이기를 켜면 끝까지 당긴 한 장면으로 멈춘다.
 * [sideDp] — 판 한 변(점). 손 기호와 말풍선은 같은 셈(pullHintPoints)으로 놓는다.
 */
@Composable
fun GamesAlkkagiPullHint(stone: AlkkagiGame.Stone, mine: AlkkagiGame.Player, reduced: Boolean, sideDp: androidx.compose.ui.unit.Dp) {
    val working = AingTheme.colors.working
    var t by remember { mutableDoubleStateOf(0.0) }
    LaunchedEffect(reduced) {
        if (reduced) return@LaunchedEffect
        val start = withFrameNanos { it }
        while (true) {
            withFrameNanos { now -> t = (now - start) / 1e9 }
        }
    }
    val phase = if (reduced) 1.0 to 0.0 else AlkkagiPhoneGuideGeometry.pullHintPhase(t)
    Box(Modifier.width(sideDp).height(sideDp).clearAndSetSemantics { }.testTag(AlkkagiTags.PULL_HINT)) {
        Canvas(Modifier.fillMaxSize()) {
            GamesAlkkagiGuideDrawing.pullHint(this, (size.width / AlkkagiGame.boardSize).toFloat(), stone, mine, phase.first, phase.second, working)
        }
        // 손 · 말풍선(손 옆, 판 안쪽으로) — 점 단위 자리로 바꿔 놓는다.
        val scaleDp = sideDp.value / AlkkagiGame.boardSize.toFloat()
        val pts = GamesAlkkagiGuideDrawing.pullHintPoints(scaleDp, stone, mine, phase.first)
        AingIcon(sf("hand.point.up.left.fill", AppIcon.TouchAppFill), null, size = 24.dp, tint = Color.White,
            modifier = Modifier.padding(start = (pts.pullEnd.x + 8 - 12).coerceAtLeast(0f).dp, top = (pts.pullEnd.y + pts.back * 6 - 12).coerceAtLeast(0f).dp))
        val bubbleLeft = pts.fullEnd.x + 8 + 26
        val toLeft = bubbleLeft + 120 > sideDp.value
        val bubbleX = if (toLeft) (pts.fullEnd.x + 8 - 26 - 120).coerceAtLeast(0f) else bubbleLeft
        Text(
            AlkkagiPhoneGuideText.handHint,
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold), color = Color.Black, maxLines = 1,
            modifier = Modifier.padding(start = bubbleX.dp, top = (pts.fullEnd.y + pts.back * 6 - 11).coerceAtLeast(0f).dp)
                .background(Color.White.copy(alpha = 0.95f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 5.dp),
        )
    }
}

/** 숨겨 놓기 · 판 가운데 빈 띠(두 진영 사이 — 돌이 못 오는 곳)의 큰 안내 한 줄. */
@Composable
fun GamesAlkkagiGuideBand(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold), color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
        modifier = modifier.padding(horizontal = 8.dp).shadow(6.dp, RoundedCornerShape(50))
            .background(AingTheme.colors.accent.copy(alpha = 0.92f), RoundedCornerShape(50))
            .padding(horizontal = 14.dp, vertical = 7.dp).testTag(AlkkagiTags.GUIDE_BAND),
    )
}

/** 처음 하는 알까기 — 세 줄 따라 하기 카드(맥 `AlkkagiFirstTimeCoach` 와 같은 세 줄 · [알겠어요]). */
@Composable
fun GamesAlkkagiCoachCard(onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Column(
        modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(AingDimens.groupRadius)).padding(AingDimens.cardPadding)
            .testTag(AlkkagiTags.COACH),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(AlkkagiPhoneFirstTimeCoach.title, style = MaterialTheme.typography.titleMedium, color = colors.label, modifier = Modifier.semantics { heading() })
        for (step in AlkkagiPhoneFirstTimeCoach.steps) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top, modifier = Modifier.semantics(mergeDescendants = true) { }) {
                AingIcon(sf(step.icon, AppIcon.Info), null, size = 22.dp, tint = colors.accent, modifier = Modifier.width(28.dp))
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(step.title, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.label)
                    Text(step.detail, style = MaterialTheme.typography.bodySmall, color = colors.label2)
                }
            }
        }
        AingButton(AlkkagiPhoneFirstTimeCoach.done, onDone, Modifier.testTag(AlkkagiTags.COACH_DONE), fillsWidth = true)
    }
}
