// 원본: Sources/CheckMobileKit/Components/MobileRelativeTime.swift · Sources/CheckMobileKit/Components/MobileComponentRules.swift:41-46(MobileLoadText) ·
//       Sources/CheckMobileKit/Messages/MessagesBlockRules.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.rules.text.BlockReportText
import com.yehsung.aingcheck.core.rules.text.NaturalKoCollation
import com.yehsung.aingcheck.core.rules.text.TextNormalization
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.datetime.DatePeriod
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.minus
import kotlinx.datetime.toLocalDateTime
import kotlin.time.Instant

/*
 * 폰 공용 부품 중 메시지·지금·순위 스토어가 읽는 글자·시각 눈금(Swift `MobileRelativeTime` · `MobileLoadText`).
 * Swift 의 그 둘은 `Components/` 에 있어 화면 갈래 몫이지만 스토어가 문구를 정하므로(K8 — 판정은 스토어나 순수 함수) 여기 둔다.
 * 화면 갈래(W3)는 이 값을 그대로 쓴다.
 */

/** 시각 눈금. 폰 메시지·지금 화면은 **KST** 다(Swift `MobileRelativeTime.kst` — 그레고리력 · Asia/Seoul). */
object MessagesTime {
    val kst: TimeZone = TimeZone.of("Asia/Seoul")

    internal fun localDate(seconds: Double, zone: TimeZone): LocalDate = instant(seconds).toLocalDateTime(zone).date

    internal fun instant(seconds: Double): Instant {
        val whole = kotlin.math.floor(seconds)
        val nanos = ((seconds - whole) * 1e9).toLong().coerceIn(0, 999_999_999)
        return Instant.fromEpochSeconds(whole.toLong(), nanos)
    }

    /** Swift `calendar.isDate(a, inSameDayAs: b)`. */
    fun isSameDay(a: Double, b: Double, zone: TimeZone = kst): Boolean = localDate(a, zone) == localDate(b, zone)
}

/**
 * 이름 비교의 기본값(Swift `localizedStandardCompare` 를 사용자 기기 로캘 ko 로 — W1-c `NaturalKoCollation`, 골든 sort/natural-ko).
 * 앱 조립이 스토어에 이 값을 넘긴다. 골든 messages/poke-display-sort 가 Swift 답과 대조한다.
 */
object NaturalKoNameCollation : Collation {
    override fun compare(a: String, b: String): Int = NaturalKoCollation.compare(a, b)
}

/** Swift `MobileRelativeTime.text` — "방금" · "N분 전" · "N시간 전"(같은 날) · "어제" · "9월 3일" · "2025. 12. 3.". */
object MobileRelativeTime {
    fun text(date: SwiftDate, now: SwiftDate, zone: TimeZone = MessagesTime.kst): String {
        val seconds = now.timeIntervalSince(date)
        if (seconds < 60) return "방금"
        if (seconds < 3600) return "${(seconds / 60).toLong()}분 전"
        val day = MessagesTime.localDate(date.timeIntervalSince1970, zone)
        val today = MessagesTime.localDate(now.timeIntervalSince1970, zone)
        if (day == today) return "${(seconds / 3600).toLong()}시간 전"
        if (day == today.minus(DatePeriod(days = 1))) return "어제"
        if (day.year == today.year) return "${day.month.ordinal + 1}월 ${day.day}일"
        return "${day.year}. ${day.month.ordinal + 1}. ${day.day}."
    }
}

/** Swift `MobileLoadText` — 탭 공용 문장. */
object MobileLoadText {
    const val retry = "다시 시도"

    /** 코어 오목 문구와 같은 문장(`GomokuNoticeText.checkConnection`). */
    const val checkConnection = "연결을 확인하고 다시 시도해 주세요"
    const val retrying = "불러오는 중…"
}

/**
 * 차단한 시각 줄(Swift `BlockReportText.blockedAtLine(_:now:)` — 폰의 상대 시각 눈금). 문장 틀("… 차단")은 코어 한 곳이다.
 * INV-MessagesBlockRules-6d651a0c 이식: 신고 자유 입력은 사람이 쓴 문장이다 — 이 모듈엔 로그(print · Logger)가 없다.
 */
fun BlockReportText.blockedAtLine(date: SwiftDate, now: SwiftDate): String = blockedAtLine(relative = MobileRelativeTime.text(date, now))

/**
 * Swift `String` 비교(`<` · `==`) — 정준 동치(NFC)로 접은 뒤 유니코드 스칼라 순. uuid 처럼 ASCII 인 id 는 UTF-16 비교와 같다.
 * W1-c 의 같은 함수(`swiftStringCompare`)는 core/rules 안쪽(internal)이라 스토어가 부를 수 없어 한 벌을 둔다.
 */
object SwiftStrings {
    fun compare(a: String, b: String): Int {
        if (a == b) return 0
        val x = scalars(TextNormalization.nfc(a))
        val y = scalars(TextNormalization.nfc(b))
        for (i in 0 until minOf(x.size, y.size)) if (x[i] != y[i]) return x[i].compareTo(y[i])
        return x.size.compareTo(y.size)
    }

    fun less(a: String, b: String): Boolean = compare(a, b) < 0

    internal fun scalars(text: String): IntArray {
        val out = ArrayList<Int>(text.length)
        var i = 0
        while (i < text.length) {
            val c = text[i]
            if (c.isHighSurrogate() && i + 1 < text.length && text[i + 1].isLowSurrogate()) {
                out += 0x10000 + ((c.code - 0xD800) shl 10) + (text[i + 1].code - 0xDC00)
                i += 2
            } else {
                out += c.code
                i += 1
            }
        }
        return out.toIntArray()
    }
}
