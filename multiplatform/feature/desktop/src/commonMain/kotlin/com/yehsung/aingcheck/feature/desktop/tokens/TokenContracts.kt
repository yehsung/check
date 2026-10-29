// 조정자 핀(W-windows-resume W-3·xplat-w2/pins.md) — 갈래는 읽기만
// 출처: pins.md D · tokens.md §4 ③ · Swift Sources/CheckCore/CheckTokenUsage.swift:17-141(값)·177-243(Codable).
// h1(스캐너)이 만들고 h3(업로드)가 값으로 읽는다. 더 필요한 계산(monthNumber·툴팁 등)은 갈래 패키지의 확장 함수로 둔다.
package com.yehsung.aingcheck.feature.desktop.tokens

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Swift `TokenUsageMonthly` — 프로퍼티 이름이 곧 JSON 키(Swift CodingKeys 가 프로퍼티 이름 그대로, 스네이크 변환 없음).
 * 정수는 전부 Long(Swift Int 64비트 · 합이 32비트를 넘는다, C §3.3). 디코드는 month 만 필수, 나머지는 없으면 0·""·빈 맵
 * (Swift decodeIfPresent 하위호환). 인코드는 언제나 모든 키를 쓴다 → [JSON] 으로만 넘긴다(encodeDefaults).
 */
@Serializable
data class TokenUsageMonthly(
    val month: String,
    val claudeInput: Long = 0,
    val claudeOutput: Long = 0,
    val claudeCacheRead: Long = 0,
    val claudeCacheCreation: Long = 0,
    val codexInput: Long = 0,
    val codexOutput: Long = 0,
    val codexCacheRead: Long = 0,
    val antigravityInput: Long = 0,
    val antigravityOutput: Long = 0,
    val antigravityThinking: Long = 0,
    val antigravityCacheRead: Long = 0,
    val todayTotal: Long = 0,
    val todayDate: String = "",
    val claudeDaily: Map<String, Long> = emptyMap(),
    val codexDaily: Map<String, Long> = emptyMap(),
    val codexDailyUTC: Map<String, Long> = emptyMap(),
    val antigravityDaily: Map<String, Long> = emptyMap(),
    val windowStart: String = "",
    val claudeCompleteFrom: String = "",
) {
    /** Swift 그대로: codexCacheRead·안티그래비티는 빼고 더한다. */
    val total: Long get() = claudeInput + claudeOutput + claudeCacheRead + claudeCacheCreation + codexInput + codexOutput
    val claudeTotal: Long get() = claudeInput + claudeOutput + claudeCacheRead + claudeCacheCreation
    val codexTotal: Long get() = codexInput + codexOutput
    val antigravityTotal: Long get() = antigravityInput + antigravityOutput + antigravityThinking + antigravityCacheRead
    val windowStartDay: String get() = if (windowStart.isEmpty()) "$month-01" else windowStart
    val codexDailyOnAccountAxis: Map<String, Long> get() = if (codexDailyUTC.isEmpty()) codexDaily else codexDailyUTC

    companion object {
        /** Swift JSONEncoder/Decoder 와 넘나드는 코덱(모든 키를 쓰고, 모르는 키는 무시). */
        val JSON: Json = Json {
            encodeDefaults = true
            ignoreUnknownKeys = true
        }

        fun decode(text: String): TokenUsageMonthly = JSON.decodeFromString(serializer(), text)
    }

    fun encode(): String = JSON.encodeToString(serializer(), this)
}
