// W2-h1 — Codex 포크 복사 구간 규칙(스캐너·진단 공용).
// 원본: Sources/CheckCore/CheckTokenUsage.swift:660-812(CodexForkRule · CodexForkTracker). 기억 codex-fork-copies-token-history:
// 포크 rollout 은 부모 이력을 자기 session_meta 직후에 복사해 쓴다 → 그 구간의 token_count 는 새 소비가 아니라 기준선만.
package com.yehsung.aingcheck.feature.desktop.tokens.scan

import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

object CodexForkRule {
    /** 자기 session_meta 시각 + 5초(마이크로초)까지가 복사 구간. */
    const val COPY_WINDOW_MICROS: Long = 5_000_000

    internal val SESSION_META_PATTERN: ByteArray = "session_meta".encodeToByteArray()

    fun isSessionMeta(obj: JsonObject): Boolean = obj.string("type") == "session_meta"

    /** payload.forked_from_id 또는 payload.parent_thread_id 가 빈 글자가 아닌 글자면 포크. */
    fun hasForkMarker(obj: JsonObject): Boolean {
        val payload = obj["payload"] as? JsonObject ?: return false
        for (key in listOf("forked_from_id", "parent_thread_id")) {
            val v = payload.string(key)
            if (!v.isNullOrEmpty()) return true
        }
        return false
    }

    /** "yyyy-MM-ddTHH:mm:ss[.ffffff]…" → epoch 마이크로초(UTC 로 읽음 — 뒤의 오프셋 표기는 보지 않는다). 소수부 최대 6자리. */
    fun timestampMicros(s: String): Long? {
        val b = s.encodeToByteArray()
        if (b.size < 19) return null
        for (i in intArrayOf(0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18)) {
            if (b[i] < 48 || b[i] > 57) return null
        }
        fun num(start: Int, len: Int): Long {
            var v = 0L
            for (k in start until start + len) v = v * 10 + (b[k] - 48)
            return v
        }
        val year = num(0, 4)
        val month = num(5, 2)
        val day = num(8, 2)
        val hour = num(11, 2)
        val minute = num(14, 2)
        val second = num(17, 2)
        if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60) return null
        val y = if (month <= 2) year - 1 else year
        val era = (if (y >= 0) y else y - 399) / 400
        val yearOfEra = y - era * 400
        val dayOfYear = (153 * (month + (if (month > 2) -3 else 9)) + 2) / 5 + day - 1
        val dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        val days = era * 146_097 + dayOfEra - 719_468
        var micros = (days * 86_400 + hour * 3_600 + minute * 60 + second) * 1_000_000
        if (b.size > 20 && b[19] == '.'.code.toByte()) {
            var frac = 0L
            var digits = 0
            var i = 20
            while (i < b.size && digits < 6 && b[i] >= 48 && b[i] <= 57) {
                frac = frac * 10 + (b[i] - 48)
                digits += 1
                i += 1
            }
            while (digits < 6) {
                frac *= 10
                digits += 1
            }
            micros += frac
        }
        return micros
    }
}

/**
 * 파일 하나를 읽는 동안의 포크 판정. 오프셋 0 부터 읽을 때(startedAtZero)만 첫 session_meta 를 '자기 것'으로 본다:
 * 포크 표시가 있으면 마감 = 자기 시각 + 5초. 표시가 없던 파일도 둘째 session_meta 를 만나면(이어 쓰기·포크 이어 붙임)
 * 마감 = 자기(없으면 그 줄) 시각 + 5초. 이어 읽기면 캐시에 남은 마감(deadlineMicros)을 이어 쓴다.
 */
class CodexForkTracker(val startedAtZero: Boolean, deadlineMicros: Long) {
    var deadlineMicros: Long = deadlineMicros
        private set
    private var ownMetaSeen = false
    private var ownMetaMicros: Long? = null

    fun observeSessionMeta(obj: JsonObject) {
        val lineMicros = obj.string("timestamp")?.let(CodexForkRule::timestampMicros)
        if (startedAtZero && !ownMetaSeen) {
            ownMetaSeen = true
            ownMetaMicros = lineMicros
            if (CodexForkRule.hasForkMarker(obj) && lineMicros != null) {
                deadlineMicros = lineMicros + CodexForkRule.COPY_WINDOW_MICROS
            }
            return
        }
        val t0 = ownMetaMicros ?: lineMicros
        if (deadlineMicros == 0L && t0 != null) {
            deadlineMicros = t0 + CodexForkRule.COPY_WINDOW_MICROS
        }
    }

    fun isCopy(eventTimestamp: String): Boolean {
        if (deadlineMicros <= 0) return false
        val micros = CodexForkRule.timestampMicros(eventTimestamp) ?: return false
        return micros <= deadlineMicros
    }
}

/** Swift `object["k"] as? String` — 글자 원시값일 때만. */
internal fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
