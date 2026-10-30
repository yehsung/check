// W2-h1 토큰 스캐너 — 증분 캐시 값 모델.
// 원본: Sources/CheckCore/CheckTokenUsage.swift:304-656(TokenUsageCache · ClaudeEntryKey · FileProgress · ClaudeEntry · CodexFileProgress).
// Windows 차이: 안티그래비티 진행 상태(antigravityFileStates)는 두지 않는다(D-E27 전 집계 0 — sqlite-jdbc 를 쓰지 않는다).
package com.yehsung.aingcheck.feature.desktop.tokens.scan

import java.security.MessageDigest

/** Claude/Codex 공통 파일 진행 상태. consumedOffset 은 "마지막 완결 줄의 끝"(개행 다음 바이트) — 이어읽기 시작점. */
data class FileProgress(val size: Long, val mtimeMicros: Long, val consumedOffset: Long)

/** 중복 제거 뒤 엔트리 하나. ts14 = 타임스탬프 앞 19자의 숫자 14개(UTC, yyyyMMddHHmmss). */
data class ClaudeEntry(val ts14: Long, val input: Long, val output: Long, val cacheRead: Long, val cacheCreation: Long)

/**
 * Codex rollout 한 파일의 진행 상태(스키마 v5 — Swift 13원소 튜플과 같은 칸).
 * prev* = 필드별 기준선(마지막 유효 누적치), month* = 이 파일이 monthKey 달에 보탠 델타, dayContrib = KST 일별, dayContribUTC = UTC 일별.
 * forkCopyDeadlineMicros = 포크 복사 구간 마감(0 = 구간 없음 — CodexForkRule).
 */
data class CodexFileProgress(
    val size: Long,
    val mtimeMicros: Long,
    val consumedOffset: Long,
    val prevInput: Long,
    val prevOutput: Long,
    val prevCached: Long,
    val monthKey: String,
    val monthInput: Long,
    val monthOutput: Long,
    val monthCached: Long,
    val dayContrib: Map<String, Long>,
    val forkCopyDeadlineMicros: Long = 0,
    val dayContribUTC: Map<String, Long> = emptyMap(),
) {
    val prevCumulative: Long get() = prevInput + prevOutput
    val monthContribTotal: Long get() = monthInput + monthOutput
}

/**
 * Claude 엔트리 중복 제거 키 = "message.id\u0000requestId" 의 **SHA-256 앞 16바이트**(빅엔디언 두 Long).
 * NUL 구분이라 ("ab","") 와 ("a","b") 가 다른 키다. 정의가 "그 문자열의 해시"라 옛 문자열 키로 만들어도 같은 키다.
 */
data class ClaudeEntryKey(val hi: Long, val lo: Long) {
    /** 32자 소문자 16진(hi 16자 + lo 16자) — 캐시 JSON 의 오브젝트 키. */
    val hex: String get() = hex16(hi) + hex16(lo)

    companion object {
        fun of(messageID: String, requestID: String): ClaudeEntryKey {
            val a = messageID.encodeToByteArray()
            val b = requestID.encodeToByteArray()
            val bytes = ByteArray(a.size + 1 + b.size)
            a.copyInto(bytes)
            bytes[a.size] = 0
            b.copyInto(bytes, a.size + 1)
            return hashing(bytes)
        }

        fun ofDedupeString(dedupe: String): ClaudeEntryKey = hashing(dedupe.encodeToByteArray())

        /** 32자 16진에서(대소문자 둘 다). 자릿수가 다르거나 16진이 아닌 글자가 있으면 null. */
        fun fromHex(hex: String): ClaudeEntryKey? {
            if (hex.length != 32) return null
            val acc = longArrayOf(0, 0)
            for ((i, c) in hex.withIndex()) {
                val v = when (c) {
                    in '0'..'9' -> c - '0'
                    in 'a'..'f' -> c - 'a' + 10
                    in 'A'..'F' -> c - 'A' + 10
                    else -> return null
                }
                acc[i / 16] = (acc[i / 16] shl 4) or v.toLong()
            }
            return ClaudeEntryKey(acc[0], acc[1])
        }

        private fun hashing(bytes: ByteArray): ClaudeEntryKey {
            val d = MessageDigest.getInstance("SHA-256").digest(bytes)
            var hi = 0L
            var lo = 0L
            for (i in 0 until 8) hi = (hi shl 8) or (d[i].toLong() and 0xFF)
            for (i in 8 until 16) lo = (lo shl 8) or (d[i].toLong() and 0xFF)
            return ClaudeEntryKey(hi, lo)
        }

        private fun hex16(v: Long): String = java.lang.Long.toHexString(v).padStart(16, '0')
    }
}

/**
 * 증분 스캔 상태. 세 축: claudeFileStates(경로 → 크기·mtime·소비 오프셋) · claudeEntries(중복 제거 키 → 엔트리) ·
 * codexFileStates(경로 → 기준선·월/일 기여). 경로 키는 `Path.toString()`(Windows 는 역슬래시) — 같은 기기 안에서만 의미가 있다.
 * Swift 는 값 타입이라 [TokenUsageIncrementalScanner.update] 가 입력을 바꾸지 않는다 — 여기서도 [deepCopy] 로 지킨다.
 */
class TokenUsageCache(
    val claudeFileStates: MutableMap<String, FileProgress> = HashMap(),
    val claudeEntries: MutableMap<ClaudeEntryKey, ClaudeEntry> = HashMap(),
    var codexFileStates: MutableMap<String, CodexFileProgress> = HashMap(),
    var codexSchemaVersion: Int = CURRENT_CODEX_SCHEMA_VERSION,
) {
    fun deepCopy(): TokenUsageCache =
        TokenUsageCache(HashMap(claudeFileStates), HashMap(claudeEntries), HashMap(codexFileStates), codexSchemaVersion)

    override fun equals(other: Any?): Boolean = other is TokenUsageCache &&
        claudeFileStates == other.claudeFileStates && claudeEntries == other.claudeEntries &&
        codexFileStates == other.codexFileStates && codexSchemaVersion == other.codexSchemaVersion

    override fun hashCode(): Int = listOf(claudeFileStates, claudeEntries, codexFileStates, codexSchemaVersion).hashCode()

    companion object {
        /** Swift currentCodexSchemaVersion — 5(포크 복사 구간 규칙 + 13원소). 다르면 codex 상태만 버리고 전체 재파싱 1회. */
        const val CURRENT_CODEX_SCHEMA_VERSION = 5
    }
}
