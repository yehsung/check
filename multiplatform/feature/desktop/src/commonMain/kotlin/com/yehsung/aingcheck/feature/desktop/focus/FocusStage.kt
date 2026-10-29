// 원본: Sources/check/WorkTimerStorePoke.swift 962-1010(상수·기록 키·기록 읽기/쓰기) · 1236-1290(FocusStage·FocusStageRecord·FocusStagePolicy·FocusStageFace) @ a90d8623
// 집중 2단(W2-g4). ★F1 집중 **판정**은 서버(profiles.focus_mode → poke_user 의 target_focused)가 하고 **만료**는 클라가 한다.
// 만료를 서버로 옮기지 않는다 — 서버는 켜짐/꺼짐만 알고, 3시간 단계는 이 기기의 기록이다.
package com.yehsung.aingcheck.feature.desktop.focus

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** 단계(원시값 = 기록에 적는 글자). */
enum class FocusStage(val raw: String) {
    OFF("off"), TIMED("timed"), ALWAYS("always");

    companion object {
        fun fromRaw(raw: String): FocusStage? = entries.firstOrNull { it.raw == raw }
    }
}

/** 이 기기의 단계 기록. until 은 TIMED 일 때만 뜻이 있다. */
data class FocusStageRecord(val stage: FocusStage, val until: SwiftDate?)

object FocusStagePolicy {
    /** ★F2 1단 길이(초) — 이 상수 하나만 쓴다. */
    const val TIMED_DURATION_SECONDS: Double = 3.0 * 60 * 60

    /** ★F6 만료 PATCH 가 실패했을 때 다시 보내기까지(초). */
    const val EXPIRY_RETRY_SECONDS: Double = 60.0

    /** ★F7 사용자가 누른 PATCH 가 실패했을 때의 안내. */
    const val CHANGE_FAILED_NOTICE: String = "집중 모드를 바꾸지 못했어요. 잠시 후 다시 시도해 주세요"

    /**
     * 서버 값 + 이 기기 기록 → 단계. ★F8 부수효과 없음.
     * ★F4 서버 켜짐 + 기록 없음 = **ALWAYS**(다른 기기·옛 앱이 켠 것 — 이 기기가 3시간을 지어내지 않는다). 바꾸지 않는다.
     */
    fun stage(serverOn: Boolean, record: FocusStageRecord?, now: () -> SwiftDate): FocusStage {
        if (!serverOn) return FocusStage.OFF
        if (record == null) return FocusStage.ALWAYS
        return when (record.stage) {
            FocusStage.TIMED -> if (isExpired(record, now)) FocusStage.OFF else FocusStage.TIMED
            FocusStage.ALWAYS, FocusStage.OFF -> FocusStage.ALWAYS
        }
    }

    /** TIMED 가 아니면 만료 없음. TIMED 인데 until 이 없으면 만료(깨진 기록을 영원히 켜 두지 않는다). */
    fun isExpired(record: FocusStageRecord, now: () -> SwiftDate): Boolean {
        if (record.stage != FocusStage.TIMED) return false
        val until = record.until ?: return true
        return now() >= until
    }
}

/** 화면 한 칸(단계 + TIMED 일 때 남은 초). */
data class FocusStageFace(val stage: FocusStage, val remainingSeconds: Int? = null) {
    companion object {
        val OFF: FocusStageFace = FocusStageFace(FocusStage.OFF)

        /** Swift `focusStageFace(now:)` 의 순수 몫 — 남은 초는 0 쪽으로 자른다(`Int(until.timeIntervalSince(now))`). */
        fun of(serverOn: Boolean, record: FocusStageRecord?, now: SwiftDate): FocusStageFace {
            if (!serverOn) return OFF
            val until = record?.until
            if (record == null || record.stage != FocusStage.TIMED || until == null) {
                return FocusStageFace(FocusStagePolicy.stage(true, record) { now })
            }
            val stage = FocusStagePolicy.stage(true, record) { now }
            if (stage != FocusStage.TIMED) return FocusStageFace(stage)
            return FocusStageFace(FocusStage.TIMED, maxOf(0, until.timeIntervalSince(now).toInt()))
        }
    }
}

/**
 * 기록 칸(★F3 사용자별 · 소문자). 키 소문자화는 **로캘 무관**이다 — Kotlin `lowercase()` 는 불변 로캘(= Locale.ROOT)이라
 * tr-TR 기본 로캘에서도 "I" → "i"(점 없는 ı 가 아니다). Swift `lowercased()` 도 로캘을 보지 않는다.
 *
 * 값은 키 정렬 JSON `{"stage":"timed","until":<2001 기준 초>}` 글자다(Swift 와 같은 칸 이름 · 같은 기준일. 숫자 표기는 Kotlin 기본 —
 * 맥과 저장소를 나누지 않으므로 바이트 대조는 하지 않는다).
 * 같은 기록 = 같은 글자라서 [write] 가 "바뀌었나"를 글자로 견준다.
 */
class FocusStageRecords(private val store: DesktopKeyValueStore) {
    fun read(userID: String): FocusStageRecord? = store.getString(key(userID))?.let(::decode)

    /** 바뀌었으면 true(Swift `focusStageRevision &+= 1` 자리). */
    fun write(record: FocusStageRecord?, userID: String): Boolean {
        val k = key(userID)
        val new = record?.let(::encode)
        if (store.getString(k) == new) return false
        if (new != null) store.putString(k, new) else store.remove(k)
        return true
    }

    companion object {
        const val KEY_PREFIX: String = "focusStageRecord."

        fun key(userID: String): String = KEY_PREFIX + swiftLowercased(userID)

        /**
         * Swift `String.lowercased()` 와 같은 소문자화 — 유니코드 **무조건** 전체 대응(İ → i̇)만 쓰고 문맥 규칙은 쓰지 않는다.
         * JVM `lowercase()`(불변 로캘)는 Final_Sigma 문맥 규칙을 적용해 "ΣΑΣ" → "σας" 가 되지만 Swift 는 "σασ" 다
         * (골든 desktop-ultra/focus-stage record-keys 가 잡았다). 그래서 스칼라 하나씩 따로 내린다(문맥이 없으니 문맥 규칙도 없다).
         * 로캘은 보지 않는다(tr-TR 에서도 "I" → "i").
         */
        fun swiftLowercased(text: String): String = buildString(text.length) {
            var i = 0
            while (i < text.length) {
                val c = text[i]
                val n = if (c.isHighSurrogate() && i + 1 < text.length && text[i + 1].isLowSurrogate()) 2 else 1
                append(text.substring(i, i + n).lowercase())
                i += n
            }
        }

        fun encode(record: FocusStageRecord): String {
            // 키 정렬 순서("stage" < "until")로 넣는다(Swift `.sortedKeys`).
            val fields = linkedMapOf<String, kotlinx.serialization.json.JsonElement>("stage" to JsonPrimitive(record.stage.raw))
            record.until?.let { fields["until"] = JsonPrimitive(it.timeIntervalSinceReferenceDate) }
            return JsonObject(fields).toString()
        }

        /** 깨진 기록은 null(Swift `try? JSONDecoder().decode`). */
        fun decode(text: String): FocusStageRecord? = runCatching {
            val obj = Json.parseToJsonElement(text).jsonObject
            val stage = FocusStage.fromRaw(obj["stage"]!!.jsonPrimitive.also { require(it.isString) }.content) ?: return null
            val untilElement = obj["until"]
            val until = when {
                untilElement == null || untilElement is JsonNull -> null
                else -> SwiftDate.fromReferenceDate(
                    untilElement.jsonPrimitive.also { require(!it.isString && it.booleanOrNull == null) }.doubleOrNull ?: return null,
                )
            }
            FocusStageRecord(stage, until)
        }.getOrNull()
    }
}
