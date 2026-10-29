// 원본: Sources/CheckMobileKit/Games/GamesCanvasKit.swift:124-133 @ 3bd04bd (GamesDisplay.maximumFramesPerSecond — 지금 앞에 있는 창 장면의 화면)
//
// 이 화면이 선 디스플레이의 주사율(Hz, 정수). 프레임 루프가 core MiniGameFrameRate 로 간격을 고르는 재료다(F§5.4 · 기억 game-frame-rate-judder).
// 창이 다른 디스플레이로 옮겨 가거나 디스플레이 설정(주사율)이 바뀌면 다시 읽는다(DisplayManager.DisplayListener) — 루프가 새 간격으로 다시 선다.
// 고주사율 **요청**(Surface.setFrameRate · preferredDisplayModeId)은 하지 않는다 — 어느 것이 갤럭시 적응형 주사율에 먹는지 미확인(E§4.4 '고주사율' 행)이라
// 지금 화면이 주는 주사율을 그대로 쓴다(물리는 dt 기준이라 공정성은 안 깨진다).
package com.yehsung.aingcheck.android.screens.games.minigame

import android.content.Context
import android.hardware.display.DisplayManager
import android.view.Display
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalView
import com.yehsung.aingcheck.core.rules.minigame.MiniGameFrameRate
import kotlin.math.roundToInt

object DisplayRefreshRate {
    /**
     * 디스플레이 주사율(실수 Hz, 59.94 같은 값) → 정수 Hz. 반올림한다(59.94 → 60 · 89.9 → 90). 디스플레이를 모르면(헤드리스·창 없음) 기준 60
     * (core MiniGameFrameRate 의 폴백과 같은 값 — 그쪽이 24 미만을 다시 60 으로 접는다).
     */
    fun hz(refreshRate: Float?): Int {
        if (refreshRate == null || refreshRate.isNaN() || refreshRate <= 0f) return MiniGameFrameRate.baselineFPS
        return refreshRate.roundToInt()
    }
}

/** 이 화면이 선 디스플레이의 주사율(정수 Hz). 디스플레이가 바뀌면 다시 그린다. */
@Composable
fun rememberDisplayRefreshHz(): Int {
    val view = LocalView.current
    var hz by remember(view) { mutableIntStateOf(DisplayRefreshRate.hz(view.display?.refreshRate)) }
    DisposableEffect(view) {
        val manager = view.context.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
        val listener = object : DisplayManager.DisplayListener {
            override fun onDisplayAdded(displayId: Int) = Unit
            override fun onDisplayRemoved(displayId: Int) = Unit
            override fun onDisplayChanged(displayId: Int) {
                val display: Display = view.display ?: return
                if (display.displayId == displayId) hz = DisplayRefreshRate.hz(display.refreshRate)
            }
        }
        manager?.registerDisplayListener(listener, view.handler)
        hz = DisplayRefreshRate.hz(view.display?.refreshRate)
        onDispose { manager?.unregisterDisplayListener(listener) }
    }
    return hz
}
