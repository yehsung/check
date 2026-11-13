// 원본: Sources/CheckCore/GameDeviceLedger.swift @ e4995a3a(한 계정 여러 기기 — 이 기기가 연 1:1 판 장부, 2026-11-03) — Android 판 8
//
// 1:1 판의 초인종은 그 사람의 **모든 기기**로 간다. 창 띄우기 · 주의 · 말풍선 · 판 구동은 **이 기기가 연 판**에서만 한다.
// 이 기기에서 신청을 보냈다(ok) · 수락했다(ok) · 수를 뒀다 → 연 판. 장부는 **사용자별 키**다(같은 기기에서 계정을 바꿔도 앞 사람의 판을 열지 않는다).
// 테트리스 스토어(Kotlin)는 같은 규칙을 자기 파일 안에 들고 있다 — 이 값은 1:1 길건너(판 8)부터 쓰는 공용판이다.
// Kotlin 이식: [KeyValueStore] 에 사전 칸이 없어 `{판 id: epoch 초}` JSON 글자 한 칸으로 둔다(테트리스와 같은 꼴 · 깨진 글자는 빈 표).
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

class GameDeviceLedger(
    /** 키 접두("crossy_duel" …). 게임마다 따로다. */
    val game: String,
    /** 이만큼(초) 지난 기록은 버린다. */
    val ttlSeconds: Double,
    /** 기록을 이만큼만 둔다(새것부터). */
    val limit: Int = 8,
) {
    /** 기록을 둘 곳. **앱 배선이 넣는다**(폰 `PhoneAppModel`). null(시험 기본)이면 이 값 안에만 산다. */
    var defaults: KeyValueStore? = null

    private val inMemory: MutableMap<String, Map<String, Double>> = mutableMapOf()

    fun key(userID: String): String = "$game.ownedMatches.${userID.lowercase()}"

    /** 이 기기가 이 판을 열었는가. 로그인 전이면 언제나 아니다. */
    fun owns(matchID: String, userID: String?, nowEpochSeconds: Double): Boolean = records(userID, nowEpochSeconds)[matchID.lowercase()] != null

    /** 이 기기가 이 판을 열었다. 이미 있으면 처음 시각을 그대로 둔다. */
    fun note(matchID: String, userID: String?, nowEpochSeconds: Double) {
        val id = matchID.lowercase()
        if (id.isEmpty()) return
        val owned = records(userID, nowEpochSeconds).toMutableMap()
        if (owned[id] != null) return
        owned[id] = nowEpochSeconds
        store(owned, userID)
    }

    /** 이 판의 기록을 지운다(끝났다). 없으면 아무것도 쓰지 않는다. */
    fun drop(matchID: String, userID: String?, nowEpochSeconds: Double) {
        val owned = records(userID, nowEpochSeconds).toMutableMap()
        if (owned.remove(matchID.lowercase()) == null) return
        store(owned, userID)
    }

    private fun records(userID: String?, nowEpochSeconds: Double): Map<String, Double> {
        val user = userID?.lowercase()?.takeIf { it.isNotEmpty() } ?: return emptyMap()
        val store = defaults
        val raw = if (store != null) decode(store.getString(key(user))) else inMemory[user] ?: emptyMap()
        val cutoff = nowEpochSeconds - ttlSeconds
        return raw.filterValues { it >= cutoff }
    }

    private fun store(owned: Map<String, Double>, userID: String?) {
        val user = userID?.lowercase()?.takeIf { it.isNotEmpty() } ?: return
        val kept = owned.entries.sortedByDescending { it.value }.take(limit).associate { it.key to it.value }
        val store = defaults
        if (store != null) {
            val k = key(user)
            if (kept.isEmpty()) store.remove(k) else store.putString(k, JsonObject(kept.mapValues { JsonPrimitive(it.value) }).toString())
        } else {
            if (kept.isEmpty()) inMemory.remove(user) else inMemory[user] = kept
        }
    }

    private fun decode(text: String?): Map<String, Double> {
        if (text.isNullOrEmpty()) return emptyMap()
        val obj = try {
            Json.parseToJsonElement(text) as? JsonObject
        } catch (e: IllegalArgumentException) {
            null
        } ?: return emptyMap()
        return obj.entries.mapNotNull { (k, v) -> (v as? JsonPrimitive)?.doubleOrNull?.let { k to it } }.toMap()
    }
}
