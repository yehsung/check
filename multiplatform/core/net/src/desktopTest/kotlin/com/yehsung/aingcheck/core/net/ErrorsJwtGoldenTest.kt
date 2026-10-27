// 원본: 없음 — 오류 분류(G §2-3 W1-d ③ · C§4 #2·#3)와 JWT(C§4 #5) 골든 대조. 골든: Tests/CheckMobileKitTests/GoldenExport/wire/GoldenExportWireRules.swift
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.testkit.dump.GoldenDump
import com.yehsung.aingcheck.testkit.golden.Golden
import com.yehsung.aingcheck.testkit.golden.GoldenCanonical
import com.yehsung.aingcheck.testkit.golden.int
import com.yehsung.aingcheck.testkit.golden.string
import io.ktor.client.plugins.HttpRequestTimeoutException
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.net.UnknownHostException
import kotlin.coroutines.cancellation.CancellationException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/** Swift `GoldenMirror.dump(SupabaseWorkServiceError)` 와 같은 모양. */
fun dumpError(e: SupabaseWorkServiceError): JsonElement = when (e) {
    is SupabaseWorkServiceError.RateLimited -> JsonObject(
        mapOf("\$case" to JsonPrimitive("rateLimited"), "\$value" to (e.retryAfterSeconds?.let { JsonPrimitive(it) } ?: JsonNull)),
    )
    is SupabaseWorkServiceError.AuthMessage -> JsonObject(mapOf("\$case" to JsonPrimitive("authMessage"), "\$value" to JsonPrimitive(e.text)))
    is SupabaseWorkServiceError.InvalidResponse -> JsonObject(mapOf("\$case" to JsonPrimitive("invalidResponse"), "\$value" to JsonPrimitive(e.statusCode)))
    else -> JsonPrimitive(e.caseName)
}

/** 덤프 → 오류(골든의 입력 칸). */
fun errorFromDump(d: JsonElement): SupabaseWorkServiceError {
    if (d is JsonPrimitive) {
        return listOf(
            SupabaseWorkServiceError.MissingAnonKey, SupabaseWorkServiceError.InvalidAPIKey, SupabaseWorkServiceError.SessionExpired,
            SupabaseWorkServiceError.InvalidLoginCredentials, SupabaseWorkServiceError.EmailNotConfirmed,
            SupabaseWorkServiceError.EmailAlreadyRegistered, SupabaseWorkServiceError.SignupDisabled, SupabaseWorkServiceError.WeakPassword,
            SupabaseWorkServiceError.DatabaseSchemaMissing, SupabaseWorkServiceError.UltraWalletUnavailable,
            SupabaseWorkServiceError.SessionAlreadyOpen, SupabaseWorkServiceError.OtpInvalidOrExpired, SupabaseWorkServiceError.SamePasswordReuse,
        ).first { it.caseName == d.content }
    }
    val o = d as JsonObject
    val v = o["\$value"]
    return when ((o["\$case"] as JsonPrimitive).content) {
        "rateLimited" -> SupabaseWorkServiceError.RateLimited((v as? JsonPrimitive)?.longOrNull)
        "authMessage" -> SupabaseWorkServiceError.AuthMessage((v as JsonPrimitive).content)
        "invalidResponse" -> SupabaseWorkServiceError.InvalidResponse((v as JsonPrimitive).content.toInt())
        else -> error("모르는 갈래 $d")
    }
}

class ErrorsJwtGoldenTest {
    private fun authError(id: String): Throwable = when {
        id == "cancellation" -> CancellationException("취소")
        id == "urlError.cancelled" -> CancellationException("요청 취소")
        id == "urlError.notConnectedToInternet" -> UnknownHostException("golden.invalid")
        id == "urlError.timedOut" -> HttpRequestTimeoutException("https://golden.invalid/x", 30_000)
        id.startsWith("service.") -> {
            val body = id.removePrefix("service.")
            val m = Regex("""(\w+)\((.*)\)""").matchEntire(body)
            if (body == "authMessage") SupabaseWorkServiceError.AuthMessage("x")
            else if (m == null) errorFromDump(JsonPrimitive(body)) else when (m.groupValues[1]) {
                "invalidResponse" -> SupabaseWorkServiceError.InvalidResponse(m.groupValues[2].toInt())
                "rateLimited" -> SupabaseWorkServiceError.RateLimited(m.groupValues[2].toLongOrNull())
                else -> error(id)
            }
        }
        else -> error("모르는 auth case $id")
    }

    @Test
    fun errorClassificationMatchesSwift() {
        val golden = Golden.load("errors/classify")
        val problems = mutableListOf<String>()
        var counted = 0
        for (c in golden.cases) {
            val id = c.string("id")
            val (want, got) = when {
                id.startsWith("classify-") -> c["error"]!! to dumpError(ServiceErrorClassifier.classify(c.int("status"), c.string("body").encodeToByteArray()))
                id.startsWith("recovery-") -> c["recovered"]!! to dumpError(ServiceErrorClassifier.passwordRecoveryError(errorFromDump(c["input"]!!)))
                id.startsWith("retry-after-") -> c["seconds"]!! to (ServiceErrorClassifier.retryAfterSeconds(c.string("text"))?.let { JsonPrimitive(it) } ?: JsonNull)
                id.startsWith("auth-") -> c["disposition"]!! to JsonPrimitive(AuthErrorRules.classify(authError(id.removePrefix("auth-"))).name)
                id.startsWith("message-") -> {
                    val e = errorFromDump(c["input"]!!)
                    JsonObject(mapOf("m" to c["message"]!!, "f" to c["missingFunction"]!!)) to
                        JsonObject(mapOf("m" to JsonPrimitive(AuthErrorRules.message(e, "<FALLBACK>")), "f" to JsonPrimitive(ServiceErrorClassifier.isMissingFunction(e))))
                }
                else -> error("모르는 case $id")
            }
            counted++
            if (GoldenCanonical.text(want) != GoldenCanonical.text(got)) {
                problems += golden.failure(id, "Swift ${GoldenCanonical.text(want).trim()} · Kotlin ${GoldenCanonical.text(got).trim()}")
            }
        }
        println("AINGCHECK-ERRORS cases=$counted problems=${problems.size}")
        assertTrue(counted >= 60, "오류 골든 case 가 적다($counted)")
        if (problems.isNotEmpty()) fail(problems.joinToString("\n\n"))
    }

    /** 순서 계약을 직접 짚는다(골든과 별개 — 23505 가 5xx 보다, 5xx 가 본문 문구보다, 429 가 본문보다 먼저). */
    @Test
    fun orderIs23505Then5xxThen429ThenBody() {
        val dup = """{"code":"23505","msg":"Invalid Refresh Token"}""".encodeToByteArray()
        assertEquals(SupabaseWorkServiceError.SessionAlreadyOpen, ServiceErrorClassifier.classify(503, dup))
        val refresh = """{"msg":"Invalid Refresh Token: Already Used"}""".encodeToByteArray()
        assertEquals(SupabaseWorkServiceError.InvalidResponse(502), ServiceErrorClassifier.classify(502, refresh))
        assertEquals(SupabaseWorkServiceError.RateLimited(null), ServiceErrorClassifier.classify(429, refresh))
        assertEquals(SupabaseWorkServiceError.SessionExpired, ServiceErrorClassifier.classify(400, refresh))
    }

    @Test
    fun jwtExpiryMatchesSwift() {
        val golden = Golden.load("jwt/expiry")
        val problems = mutableListOf<String>()
        for (c in golden.cases) {
            // payload 칸이면 토큰을 같은 규칙으로 다시 만든다(골든에 토큰 글자를 싣지 않는다 — 비밀 검사).
            val token = (c["payload"] as? JsonPrimitive)?.content?.let { payload ->
                "eyJhbGciOiJIUzI1NiJ9." + java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(payload.encodeToByteArray()) + ".c2ln"
            } ?: c.string("token")
            val got = JWTClaims.expiry(token)?.let { GoldenDump.date(it.timeIntervalSince1970) } ?: JsonNull
            if (GoldenCanonical.text(c["expiry"]!!) != GoldenCanonical.text(got)) {
                problems += golden.failure(c.string("id"), "Swift ${c["expiry"]} · Kotlin $got")
            }
        }
        println("AINGCHECK-JWT cases=${golden.cases.size} problems=${problems.size}")
        if (problems.isNotEmpty()) fail(problems.joinToString("\n\n"))
    }
}
