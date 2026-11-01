// 원본: Sources/check/RummyReactionOverlay.swift:84 (앵커) · :107 (RummyReactionOverlay) · :293 (RummyReactionButton) · :312 (RummyReactionPicker) @ 1a5eeca6 · 폰 배치는 ios-1017 설계서 §6
//
// 이모티콘 반응. 앵커는 여기 있고 판·방 뷰가 자리에 단다. 말풍선·버튼은 자리표시 — 다음 갈래가 채운다.
// **재생성 고리 금지**(맥 0.3.69 CPU 120% — 메모리 swiftui-task-id-identity-loop): 말풍선 수명은 시각 비교로 끝낸다. 키가 바뀌는 효과 안에서 키 값을 다시 쓰지 마라.
package com.yehsung.aingcheck.ui.games.rummy

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.wire.SwiftDate

/** 자리 번호 → 그 자리 사각형(뿌리 좌표, px). 자리를 그리는 뷰가 [rummyReactionAnchor] 로 채우고 말풍선 층이 읽는다. */
@Stable
class GamesRummyReactionAnchors {
    val rects = mutableStateMapOf<Long, Rect>()
}

/** 껍데기 GamesRummyScreen 이 넣는다. */
val LocalGamesRummyReactionAnchors = staticCompositionLocalOf { GamesRummyReactionAnchors() }

/** 이 뷰가 [seatNo] 자리다 — 그 사람의 반응 말풍선이 이 뷰 위에 선다. null 이면 아무것도 안 한다. */
fun Modifier.rummyReactionAnchor(anchors: GamesRummyReactionAnchors, seatNo: Long?): Modifier =
    if (seatNo == null) {
        this
    } else {
        onGloballyPositioned { coordinates -> anchors.rects[seatNo] = coordinates.boundsInRoot() }
    }

/** 말풍선 층 — `rummy.reactionFeed` 를 읽어 보낸 사람 자리에 2.5초. 입력을 막지 않는다. */
@Composable
fun GamesRummyReactionLayer(rummy: RummyStore, reduceMotion: Boolean, now: () -> SwiftDate, modifier: Modifier = Modifier) {
    Box(modifier)
}

/** 머리 줄 [반응] 단추 + 여섯 이모티콘 시트 → `rummy.sendReaction`, 쿨다운은 `rummy.canReact`. */
@Composable
fun GamesRummyReactionButton(rummy: RummyStore, now: () -> SwiftDate, modifier: Modifier = Modifier) {
    Box(modifier)
}
