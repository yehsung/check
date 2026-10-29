package com.aingcheck.games.data

import com.aingcheck.games.core.GameKind
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.time.Instant
import java.text.Collator
import java.util.Locale
import java.util.concurrent.TimeUnit

data class Session(val access: String, val refresh: String, val userId: String)
data class BoardEntry(val userId: String, val name: String, val score: Int, val bestAt: String?)
data class Submission(val status: String, val bestScore: Int?, val improved: Boolean)
class ApiFailure(val status: Int, message: String) : IOException(message)

/** Blocking transport; callers run it on Dispatchers.IO. No credentials or response bodies are logged. */
class GameApi(
    baseUrl: String, private val anonKey: String,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS).retryOnConnectionFailure(false)
        .followRedirects(false).followSslRedirects(false).build()
) {
    private val base: HttpUrl = baseUrl.toHttpUrl()
    fun signIn(email: String, password: String): Session = parseSession(
        request("/auth/v1/token?grant_type=password", JSONObject().put("email", email.trim()).put("password", password))
    )
    fun refresh(token: String): Session = parseSession(
        request("/auth/v1/token?grant_type=refresh_token", JSONObject().put("refresh_token", token))
    )
    fun logout(session: Session) { request("/auth/v1/logout?scope=local", JSONObject(), session.access) }
    fun isPublic(session: Session): Boolean {
        val url = base.newBuilder().addPathSegments("rest/v1/profiles")
            .addQueryParameter("id", "eq.${session.userId}")
            .addQueryParameter("select", "minigame_public").build()
        val rows = JSONArray(execute(Request.Builder().url(url).get(), session.access))
        // Fail closed: a missing row/column/unknown value must not publish a private user's score.
        return rows.length() == 1 && rows.getJSONObject(0).opt("minigame_public") == true
    }
    fun startRound(session: Session, kind: GameKind): String {
        val json = JSONObject(request("/rest/v1/rpc/minigame_start_round", JSONObject().put("p_game", kind.wire), session.access))
        val token = json.optString("token")
        if (json.optString("status") != "ok" || token.isBlank() || token == "null")
            throw ApiFailure(409, "순위 게임을 시작하지 못했어요. 잠시 후 다시 시도해 주세요.")
        return token
    }
    fun submit(session: Session, kind: GameKind, score: Int, token: String): Submission {
        require(score in 0..kind.maxScore)
        val json = JSONObject(request("/rest/v1/rpc/minigame_submit_score", JSONObject()
            .put("p_game", kind.wire).put("p_score", score).put("p_token", token), session.access))
        return Submission(json.getString("status"), if (json.isNull("best_score")) null else json.getInt("best_score"), json.optBoolean("improved"))
    }
    fun board(session: Session, kind: GameKind): List<BoardEntry> {
        val rows = JSONArray(request("/rest/v1/rpc/minigame_board", JSONObject().put("p_game", kind.wire), session.access))
        return (0 until rows.length()).map { index ->
            val row = rows.getJSONObject(index)
            BoardEntry(row.getString("user_id"), row.optString("display_name").takeUnless { it.isBlank() || it == "null" } ?: "사용자",
                row.getInt("best_score"), row.optString("best_at").takeUnless { it.isBlank() || it == "null" })
        }.sortedWith(compareByDescending<BoardEntry> { it.score }
            .thenBy { entry -> entry.bestAt?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: Instant.MAX }
            .thenComparator { a, b -> Collator.getInstance(Locale.KOREAN).compare(a.name, b.name) }
            .thenBy { it.userId })
    }
    private fun parseSession(value: String): Session {
        val json = JSONObject(value)
        return Session(json.getString("access_token"), json.getString("refresh_token"), json.getJSONObject("user").getString("id"))
    }
    private fun request(path: String, body: JSONObject, token: String? = null): String = execute(
        Request.Builder().url(requireNotNull(base.resolve(path)))
            .post(body.toString().toRequestBody("application/json; charset=utf-8".toMediaType())), token)
    private fun execute(builder: Request.Builder, token: String?): String {
        val request = builder.header("apikey", anonKey).header("Authorization", "Bearer ${token ?: anonKey}").build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                val message = when (response.code) {
                    400, 401 -> "로그인 정보나 세션을 확인해 주세요."
                    403 -> "접근할 수 없어요. 계정 설정을 확인해 주세요."
                    429 -> "요청이 많아요. 잠시 후 다시 시도해 주세요."
                    else -> "서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요."
                }
                throw ApiFailure(response.code, message)
            }
            return response.body?.string().orEmpty()
        }
    }
}
