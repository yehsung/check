// 원본: Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift @ 3bd04bd (TimelineView(.animation(minimumInterval:paused:)) 프레임 루프 · onChange(of: context.date) → tick)
// 원본: Sources/CheckCore/MiniGameEngine.swift @ 3bd04bd (MiniGameFrameRate — 간격 규칙 자체는 core/rules 가 옮겼다, 골든 framerate/fps)
//
// 미니게임·1:1 테트리스 판의 **프레임 루프**. Swift 는 `TimelineView(.animation(minimumInterval:))` 가 "직전 틱 + 최소 간격" 뒤 첫 vsync 에
// 화면을 깨운다. Compose 에는 그 스케줄러가 없으므로 같은 일을 vsync 마다 오는 `withFrameNanos` 위에서 직접 한다([MiniGameFramePacer]):
// 직전 틱에서 최소 간격이 지난 **첫 vsync** 에만 틱을 낸다. 최소 간격은 core `MiniGameFrameRate.minimumInterval` 이 고른 값 — 목표 fps 가
// 주사율의 **약수**라 간격이 vsync 정수배(k)에서 vsync 한 틱의 1% 만 뺀 값이다. 그래서 틱이 언제나 정확히 k vsync 마다 서고 저더가 원리적으로
// 없다(기억 game-frame-rate-judder: 1/60 고정 요구는 75Hz 에서 네 프레임에 한 번 26.67ms 로 늘어졌다).
//
// 지키는 것
//  · **판의 속도는 이 루프와 무관하다**: 물리는 실 dt(틱 시각의 차)를 쓰고 엔진 maxStep 이 클램프한다(타이밍 바·플래피 1/30 · 테트리스 1/20).
//  · 판이 멈춰 있으면(시작 전 · 결과 · 일시정지) 프레임을 **요청하지 않는다**(Swift `paused:`) — 시작 화면에서 60Hz 로 깨어 있지 않는다.
//  · 리터럴 프레임 간격(1/60 같은 상수)을 쓰지 않는다 — 간격은 언제나 core 표에서 온다(INV 소스 계약은 MiniGameHost.refreshHz 주석).
//  · 프레임 시각(vsync 나노초)을 그대로 틱 시각으로 넘긴다. 벽시계를 따로 읽으면 틱과 프레임이 어긋난다.
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.withFrameNanos
import com.yehsung.aingcheck.core.rules.minigame.MiniGameFrameRate
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.isActive
import kotlin.math.roundToLong

/**
 * vsync 위에서 틱을 고르는 순수 값(프레임 간격 선택 표 시험이 이것을 화면 없이 잰다).
 *
 * 규칙: 직전 틱에서 [minimumIntervalNanos] 가 지난 **첫 vsync** 가 다음 틱이다(Swift TimelineView 의 `minimumInterval` 과 같은 뜻 —
 * 스케줄이 "직전 날짜 + 간격" 을 다음 vsync 로 올림한다). 첫 vsync 는 언제나 틱이다(기준을 잡는다).
 */
class MiniGameFramePacer(val refreshHz: Int) {
    /** core 표가 고른 목표 fps. */
    val targetFPS: Int = MiniGameFrameRate.targetFPS(refreshHz)

    /** 틱 사이 최소 간격(나노초) — core `MiniGameFrameRate.minimumInterval` 를 나노초로(반올림). */
    val minimumIntervalNanos: Long = (MiniGameFrameRate.minimumInterval(refreshHz) * NANOS_PER_SECOND).roundToLong()

    /** 틱 하나가 차지하는 vsync 수(k). 저더 없는 길이면 정수, 폴백(나눠떨어지지 않음 — 저더 감수)이면 null. */
    val vsyncsPerTick: Int? =
        if (refreshHz >= MiniGameFrameRate.minPlausibleHz && refreshHz % targetFPS == 0) refreshHz / targetFPS else null

    private var lastTickNanos: Long? = null

    /** 루프를 새로 시작한다(판이 멈췄다 다시 돌 때 — 멈춘 구간을 첫 틱이 물려받지 않게). */
    fun reset() {
        lastTickNanos = null
    }

    /** vsync 시각 하나. 틱을 낼 차례면 참(그리고 그 시각을 직전 틱으로 적는다). */
    fun shouldTick(frameNanos: Long): Boolean {
        val last = lastTickNanos
        if (last == null || frameNanos - last >= minimumIntervalNanos) {
            lastTickNanos = frameNanos
            return true
        }
        return false
    }

    companion object {
        const val NANOS_PER_SECOND: Double = 1_000_000_000.0

        /**
         * 프레임 시각(단조 나노초) → 틱 시각. 구동기는 **차이만** 쓴다(dt · 판 상한의 기준점 — `GamesPlayController.roundLimitSeconds` 는
         * 절대 시각이 아니라 길이다). 그래서 단조 시계를 2001 기준 초 값으로 그대로 싣는다(벽시계를 섞지 않는다 — 축이 하나).
         */
        fun tickDate(frameNanos: Long): SwiftDate = SwiftDate.fromReferenceDate(frameNanos / NANOS_PER_SECOND)
    }
}

/**
 * 프레임 루프. [running] 이 거짓이면 프레임을 요청하지 않는다(Swift `paused:`). 참이면 vsync 마다 깨어 [MiniGameFramePacer] 가 고른 프레임에만
 * [onTick] 을 부른다. 주사율이 바뀌면(창이 다른 화면으로 · 디스플레이 설정) 루프가 새 간격으로 다시 선다.
 */
@Composable
fun MiniGameFrameLoop(running: Boolean, refreshHz: Int, onTick: (frameNanos: Long) -> Unit) {
    val tick by rememberUpdatedState(onTick)
    LaunchedEffect(running, refreshHz) {
        if (!running) return@LaunchedEffect
        val pacer = MiniGameFramePacer(refreshHz)
        while (isActive) {
            withFrameNanos { nanos -> if (pacer.shouldTick(nanos)) tick(nanos) }
        }
    }
}
