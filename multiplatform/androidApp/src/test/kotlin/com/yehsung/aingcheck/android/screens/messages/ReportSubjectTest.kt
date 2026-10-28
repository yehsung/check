// 원본: Sources/CheckMobileKit/Messages/MessagesBlockSheets.swift @ 3bd04bd (MessagesReportTarget — 사람 하나 · 또는 그 사람의 메시지 한 건)
package com.yehsung.aingcheck.android.screens.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReportSubjectTest {
    private val peer = "d0000000-0000-4000-8000-0000000000b2"
    private val message = "d0000000-0000-4000-8000-00000000e005"

    @Test
    fun roundTrips() {
        assertEquals(ReportSubject.Decoded(peer, null), ReportSubject.decode(ReportSubject.person(peer)))
        assertEquals(ReportSubject.Decoded(peer, message), ReportSubject.decode(ReportSubject.message(peer, message)))
    }

    @Test
    fun malformedIsRejected() {
        for (bad in listOf("", "p:", "m:$peer", "m::$message", "x:$peer", "p:$peer:extra", peer)) {
            assertNull("'$bad' 를 받았다", ReportSubject.decode(bad))
        }
    }
}
