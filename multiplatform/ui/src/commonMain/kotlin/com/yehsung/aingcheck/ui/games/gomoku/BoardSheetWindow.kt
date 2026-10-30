// 원본: Sources/CheckMobileKit/Games/GamesGomokuScreen.swift @ 3bd04bd (.sheet — 규칙 · 판돈 · AI 고르기: 창 전체를 어둡게 덮는 시트)
//
// 판 화면 시트(판돈 · 규칙 · AI 고르기 · 승진 · 신고/차단)를 **어디에** 띄우나 한 곳.
//  - Android 앱: 창 전체(M3 ModalBottomSheet — 따로 뜬 창이라 상태 바 · 탭 막대까지 덮는다, iOS `.sheet` 처럼).
//  - 데스크톱 창 · 판 스냅숏 시험: 화면 안(아래 화면 위 Box 덮개).
// 어느 쪽이든 판 화면은 컴포지션에 그대로 남는다(시트는 새 목적지가 아니다 — 폴링 · 관전이 살아 있다).
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalBottomSheetProperties
import androidx.compose.material3.SheetValue
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.ui.components.ModalPresenceMark

/**
 * 시트 · 확인 덮개의 막 색 — **검정** 반투명(iOS 시트의 어두운 막). 테마 글자색으로 칠하면 다크에서 흰 막이 되어 아래를 오히려 밝힌다(8c 05 결함).
 * 값은 M3 ModalBottomSheet 기본(scrim 검정 × 0.32)과 같다 — 테트리스 판돈 시트(GamesSheet)와 한 빛.
 */
val BoardSheetScrim: Color = Color.Black.copy(alpha = 0.32f)

/**
 * 판 시트를 창 전체에 띄우나(true) 화면 안에 띄우나(false). 기본은 플랫폼이 정한다(Android true · 데스크톱 false).
 * 판 스냅숏 시험은 시트를 한 장에 담으려고 false 를 흘린다(창 판정은 BoardSheetWindowAndroidTest 가 따로 잰다).
 */
val LocalBoardSheetsInWindow = staticCompositionLocalOf { BoardSheetsInWindowByDefault }

internal expect val BoardSheetsInWindowByDefault: Boolean

private val SheetShape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)

/**
 * 판 시트 그릇(면 색 [container] · 위 모서리 28 · 최대 폭 640). [onDismiss] 가 null 이면 막 누름 · 끌어내림 · 뒤로가기로 닫지 않는다(닫기는 시트의 ✕ 하나).
 * [testTag] 는 시트 면에 붙는다(창이든 화면 안이든 같은 이름).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BoxScope.BoardSheetHost(onDismiss: (() -> Unit)?, container: Color, testTag: String, body: @Composable () -> Unit) {
    val dismissible = onDismiss != null
    if (LocalBoardSheetsInWindow.current) {
        ModalPresenceMark()
        ModalBottomSheet(
            onDismissRequest = { onDismiss?.invoke() },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true, confirmValueChange = { dismissible || it != SheetValue.Hidden }),
            sheetGesturesEnabled = dismissible,
            shape = SheetShape,
            containerColor = container,
            scrimColor = BoardSheetScrim,
            dragHandle = null,
            properties = ModalBottomSheetProperties(shouldDismissOnBackPress = dismissible),
        ) {
            Box(Modifier.fillMaxWidth().testTag(testTag)) { body() }
        }
        return
    }
    Box(
        Modifier.matchParentSize().background(BoardSheetScrim)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onDismiss?.invoke() },
    )
    Box(
        Modifier.align(Alignment.BottomCenter).fillMaxWidth().widthIn(max = 640.dp)
            .background(container, SheetShape)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
            .testTag(testTag),
    ) { body() }
}
