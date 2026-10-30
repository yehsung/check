// 원본: Sources/check/MiniGameCrossyScene.swift @ 1b8260d (CrossyPalette 땅·차 색 :592·:683-690) — 허브 타일 그림(데스크톱 허브 칸 · 공용 패치 16)
//
// 미니게임 허브 타일의 길건너 그림: 풀밭 · 찻길(차 한 대) · 강(통나무) 세 띠 위에 아잉 옆모습. 색은 판 그림([CrossyPaint])과 한 벌이다.
// 데스크톱은 구동, 폰은 phoneCases·라우트가 거른다 — 폰 허브 목록에는 이 칸이 오지 않는다.
package com.yehsung.aingcheck.ui.games.minigame.crossy

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.games.minigame.FlappyAingImage
import com.yehsung.aingcheck.ui.games.minigame.MiniGameArt

/** 허브 타일 그림(접근성은 부르는 쪽이 숨긴다 — 타일 글자가 말한다). */
@Composable
fun CrossyTileArt(art: MiniGameArt, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier) {
        val w = maxWidth
        Canvas(Modifier.fillMaxSize()) { drawCrossyTile(this) }
        FlappyAingImage(art.flappySide, 44.dp, Modifier.offset(w * 0.30f, 52.dp))
    }
}

/** 타일 무대: 위에서부터 강(통나무) · 찻길(차) · 풀밭(나무) — 앞(위)으로 건너가는 그림. */
fun drawCrossyTile(scope: DrawScope) = with(scope) {
    val h = size.height
    val w = size.width
    val bands = listOf(0f to 0.30f, 0.30f to 0.62f, 0.62f to 1f)
    drawRect(CrossyPaint.river, Offset(0f, h * bands[0].first), Size(w, h * (bands[0].second - bands[0].first)))
    drawRect(CrossyPaint.road, Offset(0f, h * bands[1].first), Size(w, h * (bands[1].second - bands[1].first)))
    drawRect(CrossyPaint.grassDark, Offset(0f, h * bands[2].first), Size(w, h * (bands[2].second - bands[2].first)))
    // 물결 두 점 · 통나무 하나.
    val u = 4.dp.toPx()
    drawRoundRect(CrossyPaint.log, Offset(w * 0.52f, h * 0.08f), Size(w * 0.34f, h * 0.13f), CornerRadius(u))
    drawRect(CrossyPaint.wave, Offset(w * 0.10f, h * 0.12f), Size(w * 0.10f, u * 0.5f))
    drawRect(CrossyPaint.wave, Offset(w * 0.30f, h * 0.22f), Size(w * 0.08f, u * 0.5f))
    // 찻길 점선 · 차 한 대(윗면 + 앞면).
    var x = w * 0.04f
    while (x < w) {
        drawRect(CrossyPaint.roadDash, Offset(x, h * 0.46f), Size(w * 0.07f, u * 0.4f))
        x += w * 0.16f
    }
    val car = CrossyPaint.carColors[0]
    drawRect(CrossyPaint.front(car), Offset(w * 0.08f, h * 0.44f), Size(w * 0.30f, h * 0.10f))
    drawRect(car, Offset(w * 0.08f, h * 0.36f), Size(w * 0.30f, h * 0.08f))
    drawRect(CrossyPaint.cabTop, Offset(w * 0.14f, h * 0.33f), Size(w * 0.16f, h * 0.05f))
    // 풀밭 나무 하나(오른쪽).
    drawRect(CrossyPaint.trunk, Offset(w * 0.80f, h * 0.84f), Size(w * 0.05f, h * 0.08f))
    drawRect(CrossyPaint.front(CrossyPaint.leaves), Offset(w * 0.75f, h * 0.70f), Size(w * 0.15f, h * 0.14f))
    drawRect(CrossyPaint.leavesTop, Offset(w * 0.75f, h * 0.64f), Size(w * 0.15f, h * 0.06f))
}
