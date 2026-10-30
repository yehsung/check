// 원본: Sources/check/CheckMenuView.swift:1186-1240 @ a90d8623 (라벨은 그리기만 — 스토어가 == 가드로 갱신, 매초 재계산 없음)
//       · shell.md §답 4(갱신 = 분 경계 + 상태·점·테마가 바뀔 때)
//
// 근무·점·테마 흐름을 모아 트레이에 올린다. 근무 값이 매초 와도(W2-g 가 1초로 내보내도) **같은 장이면 올리지 않는다**(== 가드),
// 근무 중엔 받은 값 + 단조 시계로 경과를 늘려 분 경계에서만 깨어난다(TrayTickPlanner). 1초 틱은 없다.
package com.yehsung.aingcheck.desktop.shell.tray

import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayHost
import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import com.yehsung.aingcheck.desktop.platform.windows.tray.TaskbarTheme
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayIconRenderer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

class TrayPresenter(
    private val host: TrayHost,
    /** SM_CXSMICON(현재 배율의 작은 아이콘, 물리 픽셀) — TrayIconRenderer.sizeForScalePercent. */
    private val sizePx: () -> Int,
    /** 단조 시계(밀리초). 벽시계를 쓰지 않는다 — 시계를 돌려도 경과가 튀지 않게. */
    private val monotonicMillis: () -> Long,
) {
    private var shown = false
    private var last: TrayFrame? = null

    /** 실제로 OS 에 올린 횟수(시험이 1초 틱 0회를 잰다). */
    @Volatile var uploads: Int = 0
        private set

    /** 깨어난 횟수(값이 와서 + 분 경계). */
    @Volatile var wakeups: Int = 0
        private set

    fun start(
        scope: CoroutineScope,
        work: StateFlow<WorkStatusSnapshot>,
        dots: StateFlow<TrayDotReasons>,
        theme: StateFlow<TaskbarTheme>,
    ): Job = scope.launch {
        combine(work, dots, theme) { w, d, t -> Triple(w, d, t) }.collectLatest { (w, d, t) ->
            val base = monotonicMillis()
            while (true) {
                wakeups++
                val drift = if (w.isWorking && !w.pendingSync) monotonicMillis() - base else 0L
                val elapsedMillis = w.elapsedSeconds * 1000 + drift
                val now = w.copy(elapsedSeconds = Math.floorDiv(elapsedMillis, 1000L))
                present(TrayStateAssembly.frame(now, d, t, sizePx()))
                val wait = TrayTickPlanner.nextDelayMillis(w, elapsedMillis) ?: break
                delay(wait)
            }
        }
    }

    private fun present(frame: TrayFrame) {
        if (frame == last) return
        val icon = TrayIconRenderer.render(frame.spec)
        if (shown) host.update(icon, frame.tooltip) else host.show(icon, frame.tooltip).also { shown = true }
        last = frame
        uploads++
    }
}
