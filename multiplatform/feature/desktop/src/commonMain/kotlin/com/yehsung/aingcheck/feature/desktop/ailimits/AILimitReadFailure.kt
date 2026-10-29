// 원본: Sources/CheckCore/AILimitReaders.swift:1-164(실패 분류 · noticeText · HTTP) · :370-415(DateParser · ResetTrust) · :1045-1061(JWT) @ a90d8623
// :165-368(Process — 맥 `security`·`agy` 자식 프로세스)는 옮기지 않는다: Windows 는 자격 증명을 **파일**로 읽고(D§12-2) 안티그래비티는 뺀다(W-3 #11).
package com.yehsung.aingcheck.feature.desktop.ailimits

import com.yehsung.aingcheck.core.net.JWTClaims
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftISO8601
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// 이 패키지는 **읽기만** 한다. `.credentials.json`·`auth.json` 어디에도 쓰지 않는다 — refresh 결과를 쓰면 실제 CLI 와 회전 경합이 되어
// 사용자가 그 도구에서 로그아웃된다(맥 머리말 그대로). 그래서 401 은 '갱신해야 한다'가 아니라 **'모른다'** 다. 다음 주기를 기다린다.
// 토큰 문자열이 새지 않게: [AILimitReadError] 에는 메시지 칸이 없다(분류 + 429 재시도 초뿐). 이 패키지에는 로그·println 도 없다.
// User-Agent 는 사칭하지 않는다 — `check/<버전> (ai-limits)`.

/** 리더가 돌려주는 실패. **분류뿐이다** — 본문·헤더·토큰이 담길 자리가 없다. rawValue = 맥 영속 글자와 같다. */
enum class AILimitReadFailure(val rawValue: String) {
    /** 자격 증명 파일이 없다(그 도구를 안 쓴다 · Codex keyring 모드 — W-3 #11). */
    notInstalled("notInstalled"),
    /** 파일은 있는데 토큰이 비었다(로그인 안 했다). */
    notLoggedIn("notLoggedIn"),
    /** 맥 키체인 거부. Windows 리더는 내지 않지만 영속 글자를 접지 않게 둔다(모르는 값 = 버림이 아니라 그대로 읽힌다). */
    blocked("blocked"),
    /** 토큰이 만료됐다(`expiresAt`·JWT `exp` 가 과거). 네트워크를 쓰지 않고 안다. */
    expired("expired"),
    /** 제공자가 401·403 으로 거절했다. 우리가 갱신하지 않으므로 만료와 같은 문구로 접는다. */
    unauthorized("unauthorized"),
    /** 429. `retryAfter` 까지 완전히 침묵한다. */
    rateLimited("rateLimited"),
    /** 전송 실패(오프라인·DNS·타임아웃). 직전 값을 그대로 두고 나이만 낡게 한다. */
    network("network"),
    /** 200 인데 아는 모양이 아니다(또는 파일을 읽는 도중 깨진 JSON — 다음 주기에 다시 읽는다, 지시서 §6 ④). 숫자를 지어내지 않는다. */
    malformed("malformed"),
    /** 구독 리밋이 없는 계정(두 창이 전부 null). */
    noPlan("noPlan"),
    ;

    /** 이 실패는 제공자를 목록에서 **통째로 숨기는가**. 숨기는 것은 "안 쓴다 / 볼 수 없다" 뿐이다. */
    val hidesProvider: Boolean
        get() = when (this) {
            notInstalled, notLoggedIn, blocked -> true
            expired, unauthorized, rateLimited, network, malformed, noPlan -> false
        }

    /** 카드에 덧붙일 한 줄(없으면 null = 나이 캡션만). **네트워크 실패에는 문구가 없다**(숫자를 두고 나이만 말한다). */
    fun noticeText(provider: AILimitProvider): String? = when (this) {
        expired, unauthorized -> when (provider) {
            AILimitProvider.claude -> "클로드 코드를 한 번 실행해 주세요"
            AILimitProvider.codex -> "코덱스를 한 번 실행해 주세요"
            AILimitProvider.antigravity -> "안티그래비티를 한 번 실행해 주세요"
        }
        rateLimited -> "잠시 뒤 다시"
        noPlan -> "구독 리밋 없음"
        notInstalled, notLoggedIn, blocked, network, malformed -> null
    }

    companion object {
        fun of(raw: String): AILimitReadFailure? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 리더의 오류. **메시지가 없다**(토큰이 샐 자리를 타입에서 없앴다). */
data class AILimitReadError(val failure: AILimitReadFailure, val retryAfter: Double? = null)

/** 리더 한 번의 결과(Swift `Result<T, AILimitReadError>`). */
sealed interface AILimitOutcome<out T> {
    data class Ok<out T>(val value: T) : AILimitOutcome<T>
    data class Err(val error: AILimitReadError) : AILimitOutcome<Nothing>
}

internal fun fail(failure: AILimitReadFailure, retryAfter: Double? = null): AILimitOutcome.Err =
    AILimitOutcome.Err(AILimitReadError(failure, retryAfter))

/** HTTP 요청 한 건(헤더 이름은 Swift `setValue(forHTTPHeaderField:)` 와 같은 글자). */
data class AILimitHTTPRequest(val method: String, val url: String, val headers: Map<String, String>, val timeoutSeconds: Double)

/** HTTP 한 번의 결과. 본문은 파싱 전 바이트, 실패는 상태 코드와 깃발로만 말한다. */
class AILimitHTTPResponse(val status: Int, val body: ByteArray, val retryAfter: Double? = null, val transportFailed: Boolean = false) {
    companion object {
        val offline = AILimitHTTPResponse(0, ByteArray(0), null, transportFailed = true)
    }
}

/** HTTP 주입 지점. 앱은 단일 팩토리 클라이언트를 감싼 것(`AILimitHTTP.fetcher(client)` — desktopMain), 시험은 MockEngine. */
fun interface AILimitHTTPFetcher {
    suspend fun fetch(request: AILimitHTTPRequest): AILimitHTTPResponse
}

object AILimitHTTP {
    /** 요청 타임아웃(초). 플라이아웃을 연 사람이 기다리는 시간이라 짧게. */
    const val timeout: Double = 15.0

    /** 우리 앱 이름을 담은 User-Agent. **사칭하지 않는다.** */
    fun userAgent(appVersion: String, note: String): String = "check/$appVersion ($note)"

    /** 상태 코드 → 분류. 2xx 는 null(성공). */
    fun failure(status: Int, retryAfter: Double?): AILimitReadError? = when (status) {
        in 200..299 -> null
        401, 403 -> AILimitReadError(AILimitReadFailure.unauthorized)
        429 -> AILimitReadError(AILimitReadFailure.rateLimited, retryAfter)
        else -> AILimitReadError(AILimitReadFailure.network)
    }

    private val decimal = Regex("""^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$""")
    private val special = Regex("""^[+-]?(inf|infinity|nan)$""", RegexOption.IGNORE_CASE)

    /**
     * `Retry-After` 글자 → 초. Swift `TimeInterval.init(String)`(= `Double(_:)`) 와 같은 판정: 글자 전체가 수여야 하고 공백을 걷지 않는다
     * (Kotlin `toDouble` 은 JDK 가 공백을 걷어 받아 준다 — 그래서 정규식으로 먼저 거른다). HTTP 날짜 꼴은 null(= 기본 300초).
     */
    fun retryAfterSeconds(raw: String?): Double? {
        if (raw == null) return null
        if (decimal.matches(raw)) return raw.toDouble()
        if (special.matches(raw)) {
            val negative = raw.startsWith("-")
            return if (raw.trimStart('+', '-').lowercase().startsWith("nan")) Double.NaN
            else if (negative) Double.NEGATIVE_INFINITY else Double.POSITIVE_INFINITY
        }
        return null
    }
}

/** ISO8601 글자 → 시각. 소수초 판을 먼저, 실패하면 기본 판(앱의 날짜 파서 한 벌 — [SwiftISO8601]). 빈 글자는 null. */
object AILimitDateParser {
    fun date(raw: String?): SwiftDate? {
        if (raw.isNullOrEmpty()) return null
        return SwiftISO8601.parse(raw)
    }
}

/**
 * "이 리셋 시각은 진짜 경계인가, `now + 창길이` 투영인가". **아직 아무것도 안 쓴 창의 리셋 시각은 모르는 것으로 접는다.**
 * INV-AILimitReaders-6d8c4082 이식: 절대 시각만 주는 제공자도 둘째 조건을 쓸 수 있다(`reset_time − observedAt` 가 상대 초) — null 을 넘기면 가드가 절반만 걸린다.
 */
object AILimitResetTrust {
    fun trusts(usedPercent: Double, resetAfterSeconds: Double?, windowSeconds: Double?): Boolean {
        if (!(usedPercent > 0)) return false
        if (resetAfterSeconds != null && windowSeconds != null && windowSeconds > 0 &&
            kotlin.math.abs(resetAfterSeconds - windowSeconds) < 1
        ) return false
        return true
    }
}

/** JWT 의 **문자열** 클레임. 숫자 클레임·base64url 은 core/net [JWTClaims] 를 그대로 부른다(두 벌이 되면 한쪽만 고쳐진다). */
object AILimitJWT {
    fun stringClaim(name: String, accessToken: String): String? {
        val parts = accessToken.split(".")
        if (parts.size < 2) return null
        val payload = JWTClaims.base64URLDecode(parts[1]) ?: return null
        val obj = AILimitJson.parseObject(payload) ?: return null
        AILimitJson.string(obj[name])?.takeIf { it.isNotEmpty() }?.let { return it }
        // 중첩 클레임도 본다(`https://api.openai.com/auth` 아래). Swift 사전 순회 순서는 정해져 있지 않다 — 골든은 한 곳에만 둔다.
        for (value in obj.values) {
            val nested = value as? JsonObject ?: continue
            AILimitJson.string(nested[name])?.takeIf { it.isNotEmpty() }?.let { return it }
        }
        return null
    }
}

/** Swift `JSONSerialization` + `as?` 캐스팅의 Kotlin 꼴. */
internal object AILimitJson {
    private val json = Json { isLenient = false }

    /** 최상위가 객체가 아니거나 JSON 이 아니면 null(Swift `as? [String: Any]` 실패). */
    fun parseObject(bytes: ByteArray): JsonObject? =
        runCatching { json.parseToJsonElement(bytes.decodeToString(throwOnInvalidSequence = true)) }.getOrNull() as? JsonObject

    /** `as? String` — JSON 글자만. */
    fun string(e: JsonElement?): String? = (e as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content

    /** `as? NSNumber` 의 `doubleValue` — JSON 수와 **불**(NSNumber 로 온다: true=1 · false=0). 글자·null 은 null. */
    fun number(e: JsonElement?): Double? {
        val p = e as? JsonPrimitive ?: return null
        if (p is JsonNull || p.isString) return null
        return when (p.content) {
            "true" -> 1.0
            "false" -> 0.0
            else -> p.content.toDoubleOrNull()
        }
    }
}
