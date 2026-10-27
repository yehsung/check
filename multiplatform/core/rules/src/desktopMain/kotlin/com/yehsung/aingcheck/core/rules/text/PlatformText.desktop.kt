// 원본: Sources/CheckCore/StatusMessage.swift(NFC) · CheckTodoModel.swift(그래핌) @ 1b8260d — G §8-16 ①·③ 플랫폼 몫
package com.yehsung.aingcheck.core.rules.text

import java.text.BreakIterator
import java.text.Normalizer
import java.util.Locale

// 데스크톱(JDK)과 Android(ART — java.text 가 ICU 위에 있다)가 같은 코드다. 답이 갈리는 곳은 골든 knownDivergence 가 잠근다.
internal actual fun platformNfc(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFC)

internal actual fun platformNfd(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFD)

internal actual fun platformGraphemeLengths(text: String): IntArray {
    if (text.isEmpty()) return IntArray(0)
    val boundary = BreakIterator.getCharacterInstance(Locale.ROOT)
    boundary.setText(text)
    val out = ArrayList<Int>()
    var start = boundary.first()
    var end = boundary.next()
    while (end != BreakIterator.DONE) {
        out += end - start
        start = end
        end = boundary.next()
    }
    return out.toIntArray()
}
