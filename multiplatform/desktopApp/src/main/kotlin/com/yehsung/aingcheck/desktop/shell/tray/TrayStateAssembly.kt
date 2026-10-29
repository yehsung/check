// 원본: Sources/CheckCore/MenuBarStatusFormatter.swift:51-62·85-89 @ a90d8623 (★1 동기화 대기 > 근무 중 > 오프 · 상시 표면은 시:분만,
//       초를 보이지 않아야 티커를 60초로 늦출 수 있다) · Sources/check/CheckMenuView.swift:1186-1240 (MenuBarStatusLabel 입력)
//       · xplat-w1/briefs/shell.md §답 4(툴팁 = TrayTooltip.text + 점 사유 글, 127자 자름 · 갱신 = 분 경계 + 상태·점·테마 바뀜)
//
// 트레이 한 장 = 근무 값(core/rules WorkStatusSnapshot, 값만 — 조정 ⑩) + 점 사유 + 작업 표시줄 테마 + 크기.
// 판정은 새로 만들지 않는다: 우선순위는 TrayIconStatus.of, 글자는 TrayTooltip(=맥 localizedStatus) 그대로 부른다.
package com.yehsung.aingcheck.desktop.shell.tray

import com.yehsung.aingcheck.core.rules.format.WorkStatusSnapshot
import com.yehsung.aingcheck.desktop.platform.windows.tray.TaskbarTheme
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayIconSpec
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayIconStatus
import com.yehsung.aingcheck.desktop.platform.windows.tray.TrayTooltip

/** 트레이에 올릴 한 장(그림 명세 + 툴팁). 같으면 다시 올리지 않는다. */
data class TrayFrame(val spec: TrayIconSpec, val tooltip: String)

object TrayStateAssembly {
    /** NOTIFYICONDATAW.szTip 은 128 WCHAR(끝 NUL 포함) — 글은 127 단위까지. */
    const val TOOLTIP_MAX_UNITS = 127

    /** ★1 대기 > 근무 > 오프. 경과는 **분으로 내린다** — 그림·툴팁이 초를 말하지 않으니 초가 바뀌어도 같은 장이다. */
    fun status(s: WorkStatusSnapshot): TrayIconStatus {
        val safe = s.elapsedSeconds.coerceIn(0L, Int.MAX_VALUE.toLong())
        return TrayIconStatus.of(s.isWorking, (safe - safe % 60).toInt(), s.pendingSync)
    }

    fun frame(s: WorkStatusSnapshot, dots: TrayDotReasons, theme: TaskbarTheme, sizePx: Int): TrayFrame {
        val status = status(s)
        return TrayFrame(TrayIconSpec(status, redDot = !dots.isEmpty, theme = theme, sizePx = sizePx), tooltip(status, dots))
    }

    /** 첫 줄 = 상태(맥 글자), 둘째 줄 = 점 사유(있을 때만). */
    fun tooltip(status: TrayIconStatus, dots: TrayDotReasons): String =
        clip(listOfNotNull(TrayTooltip.text(status), dots.accessibilityDescription).joinToString("\n"))

    /** UTF-16 단위로 자르되 대리쌍 앞쪽 반만 남기지 않는다. */
    fun clip(text: String, max: Int = TOOLTIP_MAX_UNITS): String {
        if (text.length <= max) return text
        val end = if (Character.isHighSurrogate(text[max - 1])) max - 1 else max
        return text.substring(0, end)
    }
}

/**
 * ★1 분 경계 티커(맥 85-89: 초 금지 — 60초 티커). 근무 중(대기 아님)일 때만 다음 깨어남이 있고, 그 지연은
 * 다음 분 경계까지(60 − s%60 초, 밀리초 정밀). 오프·대기는 시계를 그리지 않으니 깨어나지 않는다(값이 바뀔 때만 다시 그린다).
 */
object TrayTickPlanner {
    const val MINUTE_MILLIS = 60_000L

    fun nextDelayMillis(s: WorkStatusSnapshot, elapsedMillis: Long): Long? {
        if (!s.isWorking || s.pendingSync) return null
        return MINUTE_MILLIS - Math.floorMod(maxOf(0L, elapsedMillis), MINUTE_MILLIS)
    }
}
