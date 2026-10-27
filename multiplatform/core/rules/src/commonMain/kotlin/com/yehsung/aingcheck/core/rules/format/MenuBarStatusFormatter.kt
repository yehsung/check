// 원본: Sources/CheckCore/MenuBarStatusFormatter.swift @ 1b8260d (Windows 트레이 툴팁 · 팝오버 시계 · 잔디 툴팁 — G §8-13)
package com.yehsung.aingcheck.core.rules.format

/** 근무 상태(Swift `WorkStatus`). */
enum class WorkStatus {
    working,
    offWork,
    ;

    val localizedStatus: String
        get() = when (this) {
            working -> "근무중"
            offWork -> "근무종료"
        }
}

/** 메뉴바(Windows 트레이) 한 칸이 그리는 상태. */
data class WorkStatusSnapshot(val status: WorkStatus, val elapsedSeconds: Long, val pendingSync: Boolean = false) {
    val isWorking: Boolean get() = status == WorkStatus.working

    val localizedStatus: String get() = if (pendingSync) "동기화 대기" else status.localizedStatus
}

object MenuBarStatusFormatter {
    /** 메뉴바 라벨 한 칸의 최대 폭(pt) — 예산을 키워서 통과시키면 메뉴바에서 잘린다. */
    const val maxLabelWidth: Double = 82.0

    /** 동기화 대기가 먼저('대기'), 근무 중 HH:MM, 끝 '오프'. */
    fun title(snapshot: WorkStatusSnapshot): String = when {
        snapshot.pendingSync -> "대기"
        snapshot.status == WorkStatus.working -> titleDuration(snapshot.elapsedSeconds)
        else -> "오프"
    }

    /** SF Symbols 이름 — Android·Windows 는 W1-e 의 대응표(SfSymbols → Material Symbols)로 그린다. */
    fun symbolName(snapshot: WorkStatusSnapshot): String = when {
        snapshot.pendingSync -> "exclamationmark.icloud.fill"
        snapshot.status == WorkStatus.working -> "figure.run.circle.fill"
        else -> "pause.circle.fill"
    }

    /** 메뉴바 제목·캐릭터 라벨 전용 — 언제나 HH:MM(초 내림). 초를 보이지 않아야 티커를 60초로 늦출 수 있다. */
    fun titleDuration(seconds: Long): String {
        val safe = maxOf(0L, seconds)
        return "${two(safe / 3600)}:${two((safe % 3600) / 60)}"
    }

    /** 팝오버 안 — 1시간 미만 MM:SS, 이상 HH:MM. */
    fun duration(seconds: Long): String {
        val safe = maxOf(0L, seconds)
        val hours = safe / 3600
        val minutes = (safe % 3600) / 60
        if (hours > 0) return "${two(hours)}:${two(minutes)}"
        return "${two(minutes)}:${two(safe % 60)}"
    }

    /** "H시간 MM분". */
    fun hoursMinutes(seconds: Long): String {
        val safe = maxOf(0L, seconds)
        return "${safe / 3600}시간 ${two((safe % 3600) / 60)}분"
    }

    /** printf `%02d`(음수 없음 — 호출부가 0 으로 접는다). */
    private fun two(value: Long): String = value.toString().padStart(2, '0')
}
