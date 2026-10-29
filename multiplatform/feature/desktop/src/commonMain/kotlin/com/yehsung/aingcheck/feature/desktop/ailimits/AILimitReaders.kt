// 원본: Sources/CheckCore/AILimitReaders.swift:416-761(Claude · Codex 리더) @ a90d8623
// Windows 차이(지시서 §2 W2-h2 ①③): Claude 자격 증명은 키체인이 아니라 `%USERPROFILE%\.claude\.credentials.json`(D§12-2 — Windows 는 이 파일이 정본).
// 파일 읽기는 주입(`AILimitFileRead` — desktopMain 이 java.nio 로 읽기 전용 구현을 준다). 형식·판정은 맥 `parseCredentials`·`parseUsage` 그대로.
package com.yehsung.aingcheck.feature.desktop.ailimits

import com.yehsung.aingcheck.core.net.JWTClaims
import com.yehsung.aingcheck.core.rules.ailimit.AILimitFingerprint
import com.yehsung.aingcheck.core.rules.ailimit.AILimitPlanLabelContract
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSource
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindowSnapshot
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.serialization.json.JsonObject

/** 자격 증명 파일 한 번 읽기의 결과. **쓰기 경로가 타입에 없다.** */
sealed interface AILimitFileRead {
    /** 파일이 없다(그 도구를 안 쓴다 · keyring 모드). */
    data object Missing : AILimitFileRead
    /** 있는데 못 읽었다(공유 위반 · 권한). 원인은 담지 않는다(경로·메시지가 샐 자리를 만들지 않는다). */
    data object Unreadable : AILimitFileRead
    class Bytes(val data: ByteArray) : AILimitFileRead
}

/** Claude Code 의 5시간 · 주간 창. 5분에 5회 상한 — 주기·하한·429 침묵은 스토어가 쥔다. **갱신 책임을 지지 않는다**(refreshToken 은 담지도 않는다). */
class AILimitClaudeReader(
    private val readCredentialsFile: () -> AILimitFileRead,
    private val fetch: AILimitHTTPFetcher,
    private val appVersion: String,
) {
    /** 우리가 쓰는 것만. refreshToken 은 담을 자리가 없다 — 없으면 쓸 수도 없다. */
    data class Credentials(val accessToken: String, val expiresAt: SwiftDate?, val planLabel: String?)

    companion object {
        const val usageURL = "https://api.anthropic.com/api/oauth/usage"
        /** OAuth 사용량 베타 헤더. 없으면 401("x-api-key header is required"). */
        const val betaHeader = "oauth-2025-04-20"

        /** `.credentials.json` 파싱(순수 — 골든이 Swift 와 같은 바이트로 못 박는다). */
        fun parseCredentials(data: ByteArray): AILimitOutcome<Credentials> {
            val root = AILimitJson.parseObject(data) ?: return fail(AILimitReadFailure.malformed)
            val oauth = root["claudeAiOauth"] as? JsonObject ?: return fail(AILimitReadFailure.malformed)
            val token = AILimitJson.string(oauth["accessToken"]) ?: ""
            if (token.isEmpty()) return fail(AILimitReadFailure.notLoggedIn)
            // epoch **밀리초**다(수명 약 12시간). 초로 읽으면 1970년이 되어 언제나 만료다.
            val expires = AILimitJson.number(oauth["expiresAt"])?.let { SwiftDate(it / 1000) }
            val plan = AILimitJson.string(oauth["subscriptionType"])?.let(AILimitPlanLabelContract::normalized)
            return AILimitOutcome.Ok(Credentials(token, expires, plan))
        }

        /**
         * 사용량 응답에서 5시간·주간 두 창만 뽑는다(코드네임 창·달러 창은 단위가 다르다).
         * INV-AILimitReaders-e7b958d2 이식: `limits[].is_active` 를 게이트로 쓰지 않는다(27% 찬 5시간 창이 false 였다).
         */
        fun parseUsage(data: ByteArray, observedAt: SwiftDate, planLabel: String?): AILimitOutcome<AILimitProviderSnapshot> {
            val root = AILimitJson.parseObject(data) ?: return fail(AILimitReadFailure.malformed)
            val windows = ArrayList<AILimitWindowSnapshot>()
            for ((key, window) in listOf("five_hour" to AILimitWindow.fiveHour, "seven_day" to AILimitWindow.weekly)) {
                val row = root[key] as? JsonObject ?: continue
                val utilization = AILimitJson.number(row["utilization"]) ?: continue
                val resets = AILimitDateParser.date(AILimitJson.string(row["resets_at"]))
                // Claude 는 상대 초를 주지 않는다 — 0% 가드만 걸린다.
                val trusted = AILimitResetTrust.trusts(utilization, null, null)
                windows += AILimitWindowSnapshot(window, utilization, if (trusted) resets?.timeIntervalSince1970 else null,
                    observedAt.timeIntervalSince1970, AILimitSource.local)
            }
            // 창이 하나도 없다 = 아는 모양이 아니다. 0% 로 채워 "안 썼다"고 말하지 않는다.
            if (windows.isEmpty()) return fail(AILimitReadFailure.malformed)
            // 지문 없음: 이 응답에는 안정된 계정 식별자가 없다(12시간마다 회전하는 토큰을 해시하지 않는다).
            return AILimitOutcome.Ok(AILimitProviderSnapshot(AILimitProvider.claude, AILimitWindowSnapshot.worstPerWindow(windows), planLabel, null))
        }
    }

    /** 자격 증명을 읽는다. 없으면 숨김(notInstalled), 비면 notLoggedIn, 못 읽으면 malformed(값은 두고 다음 주기 — 지시서 §6 ④). */
    fun credentials(): AILimitOutcome<Credentials> = when (val read = readCredentialsFile()) {
        AILimitFileRead.Missing -> fail(AILimitReadFailure.notInstalled)
        AILimitFileRead.Unreadable -> fail(AILimitReadFailure.malformed)
        is AILimitFileRead.Bytes -> if (read.data.isEmpty()) fail(AILimitReadFailure.notLoggedIn) else parseCredentials(read.data)
    }

    suspend fun read(now: SwiftDate): AILimitOutcome<AILimitProviderSnapshot> {
        val credentials = when (val c = credentials()) {
            is AILimitOutcome.Ok -> c.value
            is AILimitOutcome.Err -> return c
        }
        // 만료는 네트워크 없이 공짜로 안다 — 호출조차 하지 않는다(갱신 책임을 지지 않는다).
        val expiresAt = credentials.expiresAt
        if (expiresAt != null && expiresAt <= now) return fail(AILimitReadFailure.expired)
        val response = fetch.fetch(
            AILimitHTTPRequest(
                "GET", usageURL,
                linkedMapOf(
                    "Authorization" to "Bearer ${credentials.accessToken}",
                    "anthropic-beta" to betaHeader,
                    "Accept" to "application/json",
                    "User-Agent" to AILimitHTTP.userAgent(appVersion, "ai-limits"),
                ),
                AILimitHTTP.timeout,
            ),
        )
        if (response.transportFailed) return fail(AILimitReadFailure.network)
        AILimitHTTP.failure(response.status, response.retryAfter)?.let { return AILimitOutcome.Err(it) }
        return parseUsage(response.body, now, credentials.planLabel)
    }
}

/**
 * Codex 의 5시간 · 주간 창. `<codexHome>\auth.json` **읽기 전용** — 없으면(keyring 모드 포함) 연결 안 됨(W-3 #11: 부재로만 판정,
 * config.toml `cli_auth_credentials_store` 는 읽지 않는다). account_id 를 몰라도 호출은 한다(개인 계정은 헤더 없이 200).
 */
class AILimitCodexReader(
    private val readAuthFile: () -> AILimitFileRead,
    private val fetch: AILimitHTTPFetcher,
    private val appVersion: String,
) {
    data class Credentials(val accessToken: String, val accountID: String?, val planLabel: String?, val expiresAt: SwiftDate?)

    companion object {
        const val usageURL = "https://chatgpt.com/backend-api/wham/usage"

        /** `auth.json` 파싱(순수). **쓰지 않는다.** 플랜·account_id 는 JWT 클레임에서도 꺼낸다(네트워크 없이). */
        fun parseCredentials(data: ByteArray): AILimitOutcome<Credentials> {
            val root = AILimitJson.parseObject(data) ?: return fail(AILimitReadFailure.malformed)
            val tokens = root["tokens"] as? JsonObject ?: return fail(AILimitReadFailure.malformed)
            val token = AILimitJson.string(tokens["access_token"]) ?: ""
            if (token.isEmpty()) return fail(AILimitReadFailure.notLoggedIn)
            val fileAccount = AILimitJson.string(tokens["account_id"])?.takeIf { it.isNotEmpty() }
            val claimAccount = AILimitJWT.stringClaim("chatgpt_account_id", token)
            val plan = AILimitJWT.stringClaim("chatgpt_plan_type", token)
            return AILimitOutcome.Ok(
                Credentials(token, fileAccount ?: claimAccount, AILimitPlanLabelContract.normalized(plan), JWTClaims.expiry(token)),
            )
        }

        /**
         * 사용량 응답 파싱.
         * INV-AILimitReaders-7199442d 이식: `reset_at` 은 epoch **초**다(1000 으로 나누지 않는다).
         * INV-AILimitReaders-d5639b9d 이식: `used_percent == 0` 이거나 `reset_after_seconds == limit_window_seconds` 면 투영 → null 로 접는다.
         * INV-AILimitReaders-d25d970c 이식: 두 창이 전부 없으면 `.noPlan`(창을 0% 로 지어내지 않는다). `rate_limit` 자체가 없으면 malformed.
         */
        fun parseUsage(data: ByteArray, observedAt: SwiftDate, fallbackPlanLabel: String?, accountID: String?): AILimitOutcome<AILimitProviderSnapshot> {
            val root = AILimitJson.parseObject(data) ?: return fail(AILimitReadFailure.malformed)
            val plan = AILimitPlanLabelContract.normalized(AILimitJson.string(root["plan_type"])) ?: fallbackPlanLabel
            val rateLimit = root["rate_limit"] as? JsonObject
            val windows = ArrayList<AILimitWindowSnapshot>()
            // INV-AILimitReaders-195466bb 이식: 이름은 **폴백일 뿐** — 어느 창인지는 `limit_window_seconds` 가 말한다(주간 하나만 primary 로 오는 플랜).
            for ((key, nameFallback) in listOf("primary_window" to AILimitWindow.fiveHour, "secondary_window" to AILimitWindow.weekly)) {
                val row = rateLimit?.get(key) as? JsonObject ?: continue
                val used = AILimitJson.number(row["used_percent"]) ?: continue
                val windowSeconds = AILimitJson.number(row["limit_window_seconds"])
                val window = AILimitWindow.matching(windowSeconds) ?: nameFallback
                val resetAfter = AILimitJson.number(row["reset_after_seconds"])
                val trusted = AILimitResetTrust.trusts(used, resetAfter, windowSeconds)
                // Swift 는 `Date(timeIntervalSince1970:)` 로 한 번 굳힌다(2001 기준 왕복 — 소수 초에서 1ulp 갈릴 수 있어 같은 길을 밟는다).
                val resets = AILimitJson.number(row["reset_at"])?.let { SwiftDate(it).timeIntervalSince1970 }
                windows +=AILimitWindowSnapshot(window, used, if (trusted) resets else null, observedAt.timeIntervalSince1970, AILimitSource.local)
            }
            if (windows.isEmpty()) return fail(if (rateLimit == null) AILimitReadFailure.malformed else AILimitReadFailure.noPlan)
            // 원문(account_id)은 올라가지 않는다 — 해시만, 그것도 로컬 게이트 비교용.
            return AILimitOutcome.Ok(
                AILimitProviderSnapshot(AILimitProvider.codex, AILimitWindowSnapshot.worstPerWindow(windows), plan, AILimitFingerprint.make(accountID)),
            )
        }
    }

    suspend fun read(now: SwiftDate): AILimitOutcome<AILimitProviderSnapshot> {
        val data = when (val read = readAuthFile()) {
            AILimitFileRead.Missing -> return fail(AILimitReadFailure.notInstalled)
            // 맥은 `try? Data(contentsOf:)` 실패를 전부 '없음'으로 접는다. Windows 는 덮어쓰는 중의 공유 위반이 잦아 숨기지 않고 다음 주기에 다시 읽는다.
            AILimitFileRead.Unreadable -> return fail(AILimitReadFailure.malformed)
            is AILimitFileRead.Bytes -> read.data
        }
        val credentials = when (val c = parseCredentials(data)) {
            is AILimitOutcome.Ok -> c.value
            is AILimitOutcome.Err -> return c
        }
        val expiresAt = credentials.expiresAt
        if (expiresAt != null && expiresAt <= now) return fail(AILimitReadFailure.expired)
        val headers = linkedMapOf(
            "Authorization" to "Bearer ${credentials.accessToken}",
            "Accept" to "application/json",
            "User-Agent" to AILimitHTTP.userAgent(appVersion, "ai-limits"),
        )
        credentials.accountID?.let { headers["ChatGPT-Account-Id"] = it }
        val response = fetch.fetch(AILimitHTTPRequest("GET", usageURL, headers, AILimitHTTP.timeout))
        if (response.transportFailed) return fail(AILimitReadFailure.network)
        AILimitHTTP.failure(response.status, response.retryAfter)?.let { return AILimitOutcome.Err(it) }
        return parseUsage(response.body, now, credentials.planLabel, credentials.accountID)
    }
}
