// 원본: Sources/CheckCore/StatusMessage.swift @ 1b8260d (+ CheckCoreShared.swift statusMessageMaxLength)
package com.yehsung.aingcheck.core.rules.text

import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.format.swiftKeyed
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// v0.3.51 · 상태메시지(사장님 결정 2026-10-14): 40자(코드포인트) · 한 줄 · 맥과 폰. 만료 없음 · 비우면 지움 · 쿨타임 없음.
// 서버 정본은 set_status_message 다. 여기 있는 것은 ① 입력 카운터와 저장 게이트가 서버와 같은 눈금으로 세게 하는 정규화(서버 ①②③),
// ② 남의 상태를 화면에 올리기 전 관문(display), ③ RPC 응답 → 결과 · 안내 문구(맥·폰·Android 가 같은 말을 한다).

/** 상태메시지 입력의 사전 판정. `empty` 는 **지우기**다(오류가 아니다). */
sealed interface StatusMessageValidation {
    data class ok(val value: String) : StatusMessageValidation
    data object empty : StatusMessageValidation
    data class tooLong(val maxLength: Int) : StatusMessageValidation
}

object StatusMessage {
    /** 상한(CheckCoreShared.statusMessageMaxLength). **단위는 코드포인트** — 서버 `char_length` · `status_message_max_length()` 와 같은 눈금. */
    const val maxLength: Int = 40

    /** 줄바꿈류: 이것이 하나라도 든 공백·줄바꿈 묶음은 공백 하나로 접힌다(서버 ② 식과 같은 집합 — 하나를 바꾸면 둘 다). */
    private val lineBreakScalars: Set<Int> = setOf(0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029)

    /** 앞뒤에서 지우는 글자(서버 ③ btrim 집합). Foundation `.whitespacesAndNewlines` 가 아니다 — 집합이 다르다. */
    private val trimScalars: Set<Int> = setOf(0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0xA0, 0x200B, 0xFEFF, 0x3000)

    /** 사용자 입력 → 서버가 저장할 문자열과 같은 값: ① NFC ② 줄바꿈류가 든 최대 묶음 → 공백 하나 ③ 앞뒤 trim. */
    fun sanitized(raw: String): String {
        val scalars = TextNormalization.nfc(raw).codePointArray()
        val folded = ArrayList<Int>(scalars.size)
        var index = 0
        while (index < scalars.size) {
            val scalar = scalars[index]
            val isSpace = scalar == 0x20
            val isBreak = scalar in lineBreakScalars
            if (!isSpace && !isBreak) {
                folded += scalar
                index += 1
                continue
            }
            var end = index
            var hasBreak = false
            while (end < scalars.size && (scalars[end] == 0x20 || scalars[end] in lineBreakScalars)) {
                if (scalars[end] in lineBreakScalars) hasBreak = true
                end += 1
            }
            if (hasBreak) {
                folded += 0x20
            } else {
                for (i in index until end) folded += scalars[i]
            }
            index = end
        }
        var start = 0
        var stop = folded.size
        while (start < stop && folded[start] in trimScalars) start++
        while (stop > start && folded[stop - 1] in trimScalars) stop--
        return stringFromCodePoints(folded.subList(start, stop).toIntArray())
    }

    /** 서버와 같은 눈금의 길이(정규화 후 코드포인트 수). 카운터 "n/40" 이 이 값을 쓴다. */
    fun length(raw: String): Int = sanitized(raw).codePointCountCompat()

    /** 저장 전 사전 판정. 빈 판정이 먼저다. 보이는 글자 판정은 메시지와 같은 함수다. */
    fun validate(raw: String): StatusMessageValidation {
        val normalized = sanitized(raw)
        if (normalized.isEmpty() || !MessageBody.hasVisibleContent(normalized)) return StatusMessageValidation.empty
        if (normalized.codePointCountCompat() > maxLength) return StatusMessageValidation.tooLong(maxLength)
        return StatusMessageValidation.ok(normalized)
    }

    /** 남의(또는 내) 상태를 화면에 올리기 전 관문. null · 빈 값 · 보이는 글자 없는 값은 null(줄을 안 그린다). */
    fun display(raw: String?): String? {
        if (raw == null) return null
        val normalized = sanitized(raw)
        if (normalized.isEmpty() || !MessageBody.hasVisibleContent(normalized)) return null
        return normalized
    }

    /** 입력칸 카운터 문구("12/40"). */
    fun counterText(raw: String): String = "${length(raw)}/$maxLength"
}

// MARK: - 전선 위 모양(이 파일 몫 — StatusMessage.swift 한 파일이 한 Kotlin 파일이다, C§2.3)

/**
 * `set_status_message(p_text text default null)` 요청. **p_text 키를 언제나 싣는다**(null 이면 JSON null) —
 * PostgREST 는 본문 키 집합으로 함수를 고른다. 지우기를 `{}` 로 보내면 서버 기본값에 기대게 된다.
 */
data class SetStatusMessageRequest(val pText: String?) {
    /** 본문 JSON(키 `p_text` 를 언제나 싣는다 — 와이어 갈래의 요청 골든이 키 집합을 대조한다). */
    fun body(): JsonObject = JsonObject(mapOf("p_text" to (pText?.let { JsonPrimitive(it) } ?: JsonNull)))
}

/** set_status_message 응답: { status, status_message?, max_length? }. status 만 필수 — 나머지는 있으면 모양이 맞아야 한다(합성 Decodable). */
data class SetStatusMessageResponse(val status: String, val statusMessage: String? = null, val maxLength: Long? = null) {
    companion object {
        /** Swift `init(from:)` — status 가 없거나 글자가 아니면 [SwiftDecodingError]. */
        fun decode(element: JsonElement): SetStatusMessageResponse {
            val c = swiftKeyed(element)
            return SetStatusMessageResponse(
                status = c.string("status"),
                statusMessage = c.stringIfPresent("statusMessage"),
                maxLength = c.intIfPresent("maxLength"),
            )
        }
    }
}

/** 내 상태메시지 GET 의 1칸 행(`profiles?select=status_message&id=eq.<me>`). 별도 GET 이다(42703 이 다른 요청을 죽이지 않게). */
data class ProfileStatusMessageRow(val statusMessage: String?) {
    companion object {
        fun decode(element: JsonElement): ProfileStatusMessageRow =
            ProfileStatusMessageRow(swiftKeyed(element).stringIfPresent("statusMessage"))
    }
}

/** 저장 결과(스토어·화면 공유). 모르는 status 는 `invalid` 로 접는다. */
sealed interface StatusMessageSaveOutcome {
    /** 저장됐다 — 값은 **서버가 저장한 문자열**이다. */
    data class saved(val value: String) : StatusMessageSaveOutcome
    data object cleared : StatusMessageSaveOutcome
    data class tooLong(val maxLength: Int) : StatusMessageSaveOutcome
    data object notText : StatusMessageSaveOutcome
    /** 서버에 함수가 아직 없다(PGRST202 · 404). */
    data object serverNotReady : StatusMessageSaveOutcome
    /** unauthorized · 모르는 status. */
    data object invalid : StatusMessageSaveOutcome

    companion object {
        fun from(response: SetStatusMessageResponse): StatusMessageSaveOutcome = when (response.status) {
            // ok 인데 값이 없거나 비면 서버가 지운 것과 같다(빈 줄을 그리지 않는다).
            "ok" -> StatusMessage.display(response.statusMessage)?.let { saved(it) } ?: cleared
            "cleared" -> cleared
            "too_long" -> tooLong(response.maxLength?.toInt() ?: StatusMessage.maxLength)
            "not_text" -> notText
            else -> invalid
        }
    }
}

/** 맥·폰·Android 가 같이 쓰는 문구(짧은 해요체). */
object StatusMessageText {
    const val title = "상태메시지"
    const val placeholder = "지금 어떤지 한 줄로 남겨요"
    const val save = "저장"
    const val clear = "지우기"
    const val saved = "상태메시지를 바꿨어요"
    const val cleared = "상태메시지를 지웠어요"
    const val notText = "쓸 수 없는 글자가 있어요"
    const val invalid = "지금은 상태메시지를 바꿀 수 없어요"
    const val serverNotReady = "상태메시지는 서버 준비가 끝나면 쓸 수 있어요"
    const val network = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
    /** 기본 안내 한 줄(맥 설정 행에서 한 줄에 들어야 한다). */
    const val hint = "다른 사람에게 보여요 · 비우면 지워져요"

    fun tooLong(maxLength: Int): String = "상태메시지는 ${maxLength}자까지 쓸 수 있어요"

    /** 결과 → (문구, 오류 여부). 성공·지움은 오류가 아니다. */
    fun notice(outcome: StatusMessageSaveOutcome): Pair<String, Boolean> = when (outcome) {
        is StatusMessageSaveOutcome.saved -> saved to false
        StatusMessageSaveOutcome.cleared -> cleared to false
        is StatusMessageSaveOutcome.tooLong -> tooLong(outcome.maxLength) to true
        StatusMessageSaveOutcome.notText -> notText to true
        StatusMessageSaveOutcome.serverNotReady -> serverNotReady to true
        StatusMessageSaveOutcome.invalid -> invalid to true
    }
}
