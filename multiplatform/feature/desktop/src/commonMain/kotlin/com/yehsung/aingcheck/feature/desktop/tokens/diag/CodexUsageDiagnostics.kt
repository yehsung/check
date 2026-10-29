// W2-h3 Codex 사용량 진단 값 + 보고 도장.
// 원본: Sources/CheckCore/CheckTokenUsageDiagnostics.swift:26-177(값 · 하위호환 디코드) · Sources/check/WorkTimerStoreSync.swift:1053-1060(도장)
package com.yehsung.aingcheck.feature.desktop.tokens.diag

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TokenUsageDayKey
import kotlinx.serialization.Serializable

/**
 * Swift `CodexUsageDiagnostics` — 프로퍼티 이름 = JSON 키(저장·골든). 누락 키는 0(옛 빌드 페이로드 하위호환).
 * 서버로는 월간 upsert 의 codex_diag_* 칸으로만 나간다(TokenUsageUpsertRequest.of).
 */
@Serializable
data class CodexUsageDiagnostics(
    val filesTotal: Long = 0,
    val filesMonth: Long = 0,
    val eventsMonth: Long = 0,
    val maxDelta: Long = 0,
    val maxDeltaGapSeconds: Long = 0,
    val bigDeltaCount: Long = 0,
    val bigDeltaTotal: Long = 0,
    val bigGapMedianSeconds: Long = 0,
    val carryFiles: Long = 0,
    val carryTotal: Long = 0,
    val dupEvents: Long = 0,
    val dupTokens: Long = 0,
    val finalSum: Long = 0,
    val dedupTotal: Long = 0,
    val legacyTotal: Long = 0,
    val drops: Long = 0,
    val topFile: Long = 0,
    /** 값의 출처 빌드 — Windows 는 version.properties windowsBuild(지금 1). 서버 codex_diag_build. */
    val appBuild: Long = 0,
    val forkFiles: Long = 0,
    val forkCopyTokens: Long = 0,
)

/** 진단은 `"<빌드>:<KST 날짜>"` 도장당 1회. 도장은 **전송 성공 뒤에만** 찍는다(WorkTimerStoreSync.swift:799-803 · 1053-1092). */
object CodexDiagnosticsStamp {
    const val KEY: String = "check.codexDiag.reportedStamp"

    fun stamp(build: Long, now: SwiftDate): String = "$build:${TokenUsageDayKey.current(now)}"
}
