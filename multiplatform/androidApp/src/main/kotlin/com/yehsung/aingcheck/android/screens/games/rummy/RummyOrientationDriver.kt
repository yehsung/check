// 원본: Sources/CheckMobileKit/Games/GamesRummyOrientation.swift:42-92 (GamesRummyOrientationLock · GamesRummyOrientationDriver) @ ios-1017-cube 61d75d8c · 설계서 §10.1
//
// 아잉 큐브 **판 화면만 가로**의 Android 대입. 답은 스토어가 쥔다(GamesStore.rummyInterfaceOrientation — 저장값이 아니라 지금 상태의 계산). 이 파일은 그 값을 Activity 에 옮기기만 한다.
// 값을 쥐지 않으니 '푸는 코드를 잊은 길'이 없다: 화면이 사라지면(GamesRummyScreen 의 DisposableEffect → rummyScreenDidDisappear) · 세션이 끝나면(GamesStore.reset) 그 순간 답이 세로고, 여기가 곧바로 옮긴다.
// 조립(MainActivity)이 Activity 수명 범위로 한 번 건다 — 합성 밖이라 셸이 통째로 바뀌어도(로그아웃) · 앱이 내려가 있어도(프레임이 멎어도) 값을 놓치지 않는다. 앱을 내려도 방향은 안 바뀐다.
// **세로 = 잠금이다**(폰). 맥 · iOS 와 같이 앱의 나머지는 세로이고, '돌리는 대로' 두면 옆으로 든 폰에서 판을 나간 뒤 결과 · 로비가 가로로 남는다. 큰 화면(최소 폭 600 이상)은 기기 방향을 따른다.
package com.yehsung.aingcheck.android.screens.games.rummy

import android.content.pm.ActivityInfo
import androidx.compose.runtime.snapshotFlow
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

object RummyOrientationDriver {
    /** 최소 폭이 이 값 이상이면 큰 화면이다(Android 16 은 여기서 방향 요청을 무시한다 — 그 전 판도 세로로 묶지 않는다). */
    const val LARGE_SCREEN_MIN_WIDTH_DP: Int = 600

    /** 방향 값 → Activity 값. 가로는 기기의 '화면 방향 고정'과 무관하게 돈다(SENSOR_LANDSCAPE). 양쪽 가로를 다 받는다. */
    fun activityOrientation(orientation: GamesRummyInterfaceOrientation, smallestWidthDp: Int): Int = when (orientation) {
        GamesRummyInterfaceOrientation.landscape -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        GamesRummyInterfaceOrientation.portrait ->
            if (smallestWidthDp >= LARGE_SCREEN_MIN_WIDTH_DP) ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }

    /** 값이 바뀔 때마다 [apply] 로 옮긴다(지금 값을 곧바로 한 번). [scope] = Activity 수명. */
    fun install(store: GamesStore, scope: CoroutineScope, apply: (GamesRummyInterfaceOrientation) -> Unit): Job =
        install({ store.rummyInterfaceOrientation }, scope, apply)

    /** 값 읽기만 받는 꼴(시험이 스토어 없이 잰다). */
    internal fun install(orientation: () -> GamesRummyInterfaceOrientation, scope: CoroutineScope, apply: (GamesRummyInterfaceOrientation) -> Unit): Job {
        apply(orientation())
        return scope.launch {
            snapshotFlow(orientation).distinctUntilChanged().collect { apply(it) }
        }
    }
}
