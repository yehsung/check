// W2-h3 Codex 계정 사용량 — 값 모델 · 프로브 상태 · app-server 응답 파싱(순수).
// 원본: Sources/CheckCore/CheckCodexAccountUsage.swift:26-100(CodexAccountUsage · CodexAccountProbeStatus) · :386-445 · :745-750(파싱)
// 셸 조회(:184-383)는 Windows 판으로 대체한다(desktopMain CodexAccountProbeRunner — 네이티브 exe 후보만).
package com.yehsung.aingcheck.feature.desktop.tokens.account

import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/** Swift `CodexAccountUsage` — 계정 스냅샷. buckets 키는 **UTC** 'YYYY-MM-DD'. */
data class CodexAccountUsage(val fetchedAt: SwiftDate, val lifetimeTokens: Long?, val buckets: Map<String, Long>) {
    /** 'YYYY-MM' 월의 버킷 합(접두어 — UTC 월). */
    fun monthTotal(month: String): Long {
        val prefix = "$month-"
        var sum = 0L
        for ((day, tokens) in buckets) if (day.startsWith(prefix)) sum += tokens
        return sum
    }

    val latestBucketDate: String? get() = buckets.keys.maxOrNull()

    /** 그 월 안의 가장 최근 버킷 날짜(지난달 버킷을 이번 달 반영일로 오인하지 않게). */
    fun latestBucketDate(month: String): String? = buckets.keys.filter { it.startsWith("$month-") }.maxOrNull()

    /** fetchedAt − 70일(UTC 일자) 이전 버킷을 버린 사본. */
    fun pruned(): CodexAccountUsage {
        val cutoff = utcDayString(fetchedAt.addingTimeInterval(-RETENTION_DAYS * 86_400.0))
        return copy(buckets = buckets.filterKeys { it >= cutoff })
    }

    companion object {
        const val RETENTION_DAYS: Int = 70

        /** SwiftDate → UTC 'YYYY-MM-DD'(버킷 축). */
        fun utcDayString(date: SwiftDate): String {
            val seconds = kotlin.math.floor(date.timeIntervalSince1970).toLong()
            val days = seconds.floorDiv(86_400L)
            // Howard Hinnant civil_from_days.
            val z = days + 719_468
            val era = z.floorDiv(146_097L)
            val doe = z - era * 146_097
            val yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
            val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
            val mp = (5 * doy + 2) / 153
            val d = doy - (153 * mp + 2) / 5 + 1
            val m = if (mp < 10) mp + 3 else mp - 9
            val y = yoe + era * 400 + (if (m <= 2) 1 else 0)
            return "${y.toString().padStart(4, '0')}-${m.toString().padStart(2, '0')}-${d.toString().padStart(2, '0')}"
        }
    }
}

/**
 * Swift `CodexAccountProbeStatus` — 원시값이 서버 칸 `codex_account_status`(smallint)에 그대로 올라간다.
 * 값을 바꾸거나 재배열하지 마라(token_scan_health() 가 이 숫자를 읽는다).
 */
enum class CodexAccountProbeStatus(val raw: Int) {
    OK(1),
    /** 후보 위치 어디에도 네이티브 codex 실행 파일이 없다. */
    CODEX_NOT_INSTALLED(2),
    /** `<codexHome>/auth.json` 부재(keyring 모드 포함 — W-3 #11) 또는 서버 인증 오류. */
    NOT_LOGGED_IN(3),
    TIMEOUT(4),
    FAILED(5);

    companion object {
        fun ofRaw(raw: Int): CodexAccountProbeStatus? = entries.firstOrNull { it.raw == raw }
    }
}

/** 업로드 조정자가 읽는 계정 출처(시험은 가짜로 바꾼다). */
interface CodexAccountSource {
    val snapshot: CodexAccountUsage?
    val lastStatus: CodexAccountProbeStatus?
    suspend fun refreshIfDue(now: SwiftDate, force: Boolean = false)
}

/** 프로브 결과(Swift `Result<CodexAccountUsage, Failure>`). */
sealed interface CodexProbeResult {
    data class Success(val usage: CodexAccountUsage) : CodexProbeResult
    data class Failure(val status: CodexAccountProbeStatus, val reason: String) : CodexProbeResult
}

/** Swift `CodexAccountUsageProbe` 의 순수 몫(요청 줄 · 응답 파싱 · 툴체인 확인 판정). */
object CodexAccountProbeProtocol {
    const val USAGE_REQUEST_ID: Int = 2
    /** 프로브 데드라인(Swift fetchDeadline 15초). */
    const val FETCH_DEADLINE_MILLIS: Long = 15_000
    /** 탐색 실패 캐시(Swift locateFailureTTL 1800초). */
    const val LOCATE_FAILURE_TTL_SECONDS: Double = 1800.0
    const val MAX_CANDIDATE_ATTEMPTS: Int = 4

    private val parser = Json { isLenient = false }

    /** stdio JSONL 요청 3줄. initialize(id 1) → initialized 알림 → account/usage/read(id 2). 버전의 따옴표는 지운다. */
    fun requestLines(appVersion: String): List<String> {
        val version = appVersion.replace("\"", "")
        return listOf(
            "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"aing-check\",\"title\":\"aing-check\",\"version\":\"$version\"}}}",
            "{\"method\":\"initialized\",\"params\":{}}",
            "{\"method\":\"account/usage/read\",\"id\":$USAGE_REQUEST_ID}",
        )
    }

    /**
     * 응답 줄 파싱 — **`id == requestID` 인 줄만** 쓴다(초기화 응답 · 알림 · 잘린 JSON 무시). error 면 실패(메시지에 'auth' 가 들면
     * 미로그인), result 면 summary.lifetimeTokens(null 허용)와 dailyUsageBuckets(null → 빈 맵, 'YYYY-MM-DD' 접두어로 접어 더함).
     */
    fun parse(lines: List<String>, requestID: Int = USAGE_REQUEST_ID, fetchedAt: SwiftDate): CodexProbeResult {
        for (raw in lines) {
            val line = raw.trim()
            if (line.isEmpty()) continue
            val obj = parseObject(line) ?: continue
            if (numberAsInt(obj["id"]) != requestID) continue
            if (obj.containsKey("error")) {
                val error = obj["error"]
                val message = ((error as? JsonObject)?.get("message") as? JsonPrimitive)?.takeIf { it.isString }?.content
                    ?: (error as? JsonPrimitive)?.takeIf { it.isString }?.content
                    ?: error.toString()
                val status = if (message.contains("auth", ignoreCase = true)) CodexAccountProbeStatus.NOT_LOGGED_IN else CodexAccountProbeStatus.FAILED
                return CodexProbeResult.Failure(status, message)
            }
            val result = obj["result"] as? JsonObject ?: return CodexProbeResult.Failure(CodexAccountProbeStatus.FAILED, "result 없음")
            val lifetime = numberAsLong((result["summary"] as? JsonObject)?.get("lifetimeTokens"))
            val buckets = HashMap<String, Long>()
            val daily = result["dailyUsageBuckets"] as? JsonArray
            // Swift `as? [[String: Any]]` — 원소 하나라도 객체가 아니면 배열 통째로 버린다.
            if (daily != null && daily.all { it is JsonObject }) {
                for (bucket in daily) {
                    bucket as JsonObject
                    val day = (bucket["startDate"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: continue
                    if (day.length < 10) continue
                    val tokens = numberAsLong(bucket["tokens"]) ?: continue
                    val key = day.substring(0, 10)
                    buckets[key] = (buckets[key] ?: 0L) + tokens
                }
            }
            return CodexProbeResult.Success(CodexAccountUsage(fetchedAt, lifetime, buckets).pruned())
        }
        return CodexProbeResult.Failure(CodexAccountProbeStatus.FAILED, "id $requestID 응답 줄 없음")
    }

    /** 툴체인을 **확인**하는 결과인가: 성공 또는 서버 인증 오류(바이너리는 돌고 메서드도 안다). */
    fun confirmsToolchain(result: CodexProbeResult): Boolean = when (result) {
        is CodexProbeResult.Success -> true
        is CodexProbeResult.Failure -> result.status == CodexAccountProbeStatus.NOT_LOGGED_IN
    }

    /** 러너가 조기 종료를 판정하는 줄(id 2 응답). */
    fun lineHasUsageResponseID(line: String): Boolean {
        if (!line.contains("\"id\"")) return false
        return numberAsInt(parseObject(line.trim())?.get("id")) == USAGE_REQUEST_ID
    }

    private fun parseObject(line: String): JsonObject? = try {
        parser.parseToJsonElement(line) as? JsonObject
    } catch (_: Exception) {
        null
    }

    /** NSNumber.int64Value — 정수 글자는 그대로, 소수는 0 쪽으로 버림, 불은 1/0, 글자·null 은 nil. */
    private fun numberAsLong(element: JsonElement?): Long? {
        val p = element as? JsonPrimitive ?: return null
        if (p.isString || p.content == "null") return null
        p.booleanOrNull?.let { return if (it) 1L else 0L }
        return p.content.toLongOrNull() ?: p.content.toDoubleOrNull()?.toLong()
    }

    private fun numberAsInt(element: JsonElement?): Int? = numberAsLong(element)?.toInt()
}
