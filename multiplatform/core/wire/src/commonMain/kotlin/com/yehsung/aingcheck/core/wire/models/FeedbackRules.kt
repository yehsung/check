// 원본: Sources/CheckCore/SupabaseWorkModels.swift:3489-3651(FeedbackComposer · FeedbackText) @ 1b8260d — 폰 MeStoreFeedback·MeText·MessagesBlockRules 가 쓴다
package com.yehsung.aingcheck.core.wire.models

import com.yehsung.aingcheck.core.foundation.platform.GraphemeCounter
import com.yehsung.aingcheck.core.wire.SwiftDate

/**
 * 제보 본문·메모의 길이 규칙(순수). 세는 단위는 Swift `Character`(확장 그래핌) — 플랫폼 [GraphemeCounter] 를 주입받는다
 * (Android = ICU, 데스크톱 = JDK BreakIterator, §8-16 W1-c ③). 서버 `char_length` 는 코드포인트를 세지만 산문에서는 같다.
 */
object FeedbackComposer {
    /** 본문 상한 — 서버 `submit_feedback` 의 1~1000 과 같은 값. */
    const val maxBodyLength = 1000
    /** 이 길이를 넘으면 카운터를 pending 색으로. */
    const val warnBodyLength = 900
    /** 관리자 메모(답장) 상한. */
    const val maxNoteLength = 500

    /** 앞뒤 공백·줄바꿈을 걷은 전송 본문(카운터는 원문을 센다). */
    fun normalized(text: String): String = swiftTrim(text)

    /** 지금 보낼 수 있는가 — 1자 이상 1000자 이하(그래핌). */
    fun isSendable(text: String, graphemes: GraphemeCounter): Boolean {
        val count = graphemes.count(normalized(text))
        return count in 1..maxBodyLength
    }

    /** "N/1000" 카운터(원문 그래핌 수). */
    fun counterText(text: String, graphemes: GraphemeCounter): String = "${graphemes.count(text)}/$maxBodyLength"

    fun isCounterWarning(text: String, graphemes: GraphemeCounter): Boolean = graphemes.count(text) > warnBodyLength

    /** 서버로 나갈 메모(답장도 같은 값). 비면 null, 길면 앞 500 그래핌. */
    fun normalizedNote(text: String, graphemes: GraphemeCounter): String? {
        val trimmed = normalized(text)
        if (trimmed.isEmpty()) return null
        return graphemePrefix(trimmed, maxNoteLength, graphemes)
    }

    /** [보내기](답장)를 누를 수 있는가: 비지 않았고 저장된 답장과 다르다. */
    fun isSendableReply(draft: String, savedNote: String?, graphemes: GraphemeCounter): Boolean {
        val normalized = normalizedNote(draft, graphemes) ?: return false
        return normalized != savedNote
    }

    /**
     * Swift `String.prefix(n)`(앞 n 그래핌). 그래핌 수는 접두가 길어질수록 줄지 않으므로, 코드포인트 경계 중 "세면 n 이하"인 가장 긴 접두를
     * 이분 탐색한다 — 그 끝은 n 번째 그래핌의 끝이다(n+1 번째 그래핌의 첫 코드포인트만 넣어도 n+1 이 된다).
     */
    fun graphemePrefix(text: String, n: Int, graphemes: GraphemeCounter): String {
        if (graphemes.count(text) <= n) return text
        val ends = ArrayList<Int>()
        var i = 0
        while (i < text.length) {
            i += if (text[i].isHighSurrogate() && i + 1 < text.length && text[i + 1].isLowSurrogate()) 2 else 1
            ends += i
        }
        var lo = 0
        var hi = ends.size - 1
        var best = 0
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            if (graphemes.count(text.substring(0, ends[mid])) <= n) {
                best = ends[mid]
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return text.substring(0, best)
    }
}

/** 제보 화면의 고정 문구(테스트가 문구 자체를 되묻는다 — 내부 코드 FEEDBACK_RATE_LIMIT 를 노출하지 않는다). */
object FeedbackText {
    const val windowTitle = "제보"
    const val sendTab = "보내기"
    const val inboxTab = "받은 제보"
    const val placeholder = "어떤 문제가 있었는지, 무엇을 하다 생겼는지 적어 주세요"
    const val sendAction = "보내기"
    const val sending = "보내는 중…"
    const val sendSuccess = "보냈어요. 고마워요!"
    /** 24시간 10건 상한 — 사용자 말투로만. */
    const val rateLimited = "오늘은 그만 받을게요 — 내일 다시 보내 주세요"
    const val sendFailed = "보내지 못했어요 — 잠시 뒤 다시 시도해 주세요"
    /** 서버에 제보 표·함수가 아직 없다(며칠 갈 수 있다 — 쓴 글은 그대로 있다고 말한다). */
    const val sendSchemaMissing = "이 기능은 곧 열려요 — 쓰신 글은 그대로 둘게요"
    const val forbidden = "권한이 없어요"
    const val statusFailed = "상태를 바꾸지 못했어요"
    const val mineTitle = "내가 보낸 제보"
    const val mineEmpty = "아직 보낸 제보가 없어요"
    const val inboxEmpty = "받은 제보가 없어요"
    const val inboxEmptyHint = "누가 보내면 여기에 바로 쌓여요"
    const val filterAll = "전체"
    /** 필터로 전부 숨겨졌을 때의 빠져나갈 길 — 칩 이름([filterAll])을 그대로 부른다. */
    const val inboxFilterEmptyHint = "위 [$filterAll]를 누르면 나머지가 보여요"
    const val loading = "불러오는 중…"
    const val failed = "제보를 불러오지 못했어요"
    const val retry = "다시 시도"
    const val notePlaceholder = "답장(500자까지)"
    const val noteSave = "상태와 답장은 따로 저장돼요 — 답장은 제보한 사람에게 보여요"
    const val replyAction = "답장 보내기"
    const val replySending = "보내는 중…"
    const val replyBlockTitle = "답장"
    const val replySent = "답장을 보냈어요"
    const val replyFailed = "답장을 보내지 못했어요"
    const val replySchemaMissing = "답장 보내기는 곧 열려요 — 쓰신 글은 그대로 둘게요"
    const val replyEmpty = "답장을 적어야 보낼 수 있어요"
    const val replyTooLong = "답장이 너무 길어요 — 500자까지 보낼 수 있어요"
    const val replyNotFound = "그 제보를 찾지 못했어요 — 목록을 다시 열어 주세요"

    /** 필터가 걸려 아무것도 안 남았을 때('진짜 빈 목록'과 같은 문장으로 말하지 않는다). */
    fun inboxFilterEmpty(status: FeedbackStatus): String = "${status.label} 제보가 없어요"

    /** 이 안내 한 줄이 좋은 소식인가(색은 여기 하나에서 갈린다). */
    fun isSuccessNotice(notice: String): Boolean = notice == sendSuccess || notice == replySent

    /** "앱 0.2.48 (58) · macOS 15.6 정보가 함께 전송돼요"(맥 문구 — 폰은 MeText 의 자기 판). */
    fun autoAttachNotice(appVersion: String, build: Long?, osVersion: String): String {
        var app = if (appVersion.isEmpty()) "앱" else "앱 $appVersion"
        if (build != null && build > 0) app += " ($build)"
        return "$app · macOS $osVersion 정보가 함께 전송돼요"
    }

    /** "방금 / N분 전 / N시간 전 / N일 전". 날짜가 없으면 빈 글자. */
    fun ageText(date: SwiftDate?, now: SwiftDate): String {
        if (date == null) return ""
        val seconds = maxOf(0L, swiftInt(now.timeIntervalSince(date)))
        if (seconds < 60) return "방금"
        if (seconds < 3600) return "${seconds / 60}분 전"
        if (seconds < 86_400) return "${seconds / 3600}시간 전"
        return "${seconds / 86_400}일 전"
    }
}
