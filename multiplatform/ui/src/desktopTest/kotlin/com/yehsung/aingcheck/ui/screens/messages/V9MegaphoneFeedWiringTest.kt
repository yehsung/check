// 원본: Tests/CheckMobileKitTests/V1019MegaphoneFeedTests.swift(wiring) @ 94975fa8
package com.yehsung.aingcheck.ui.screens.messages

import com.yehsung.aingcheck.ui.theme.SwiftStyleComments
import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/** 판 9 — 지난 확성기 배선: 작성 시트의 문 · 페이지가 서면 open · 떠나면 close · 작성기 열기에 rearm · 실시간 신호는 열린 페이지만. 주석을 걷고 본다. */
class V9MegaphoneFeedWiringTest {
    private val mp = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
    private fun code(rel: String) = SwiftStyleComments.strip(File(mp, rel).readText()).filter { !it.isWhitespace() }

    @Test
    fun entryPageAndRealtimeAreWired() {
        val sheet = code("ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/messages/MessagesSheets.kt")
        assertTrue(sheet.contains("if(store.showsMegaphoneFeedEntry){"), "작성 시트에 문이 없다")
        assertTrue(sheet.contains("LaunchedEffect(store){store.megaphoneFeed.rearm()}"), "작성기 열기가 문을 다시 세우지 않는다")
        assertTrue(sheet.contains("MessagesMegaphoneFeedPage(store,onBack={showsFeed=false}"))
        val page = code("ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/screens/messages/MessagesMegaphoneFeedPage.kt")
        assertTrue(page.contains("DisposableEffect(feed){feed.open()onDispose{feed.close()}}"), "페이지가 서고 떠날 때 열고 닫지 않는다")
        assertTrue(page.contains("valitems=store.visibleMegaphoneFeed"), "차단한 사람 글을 거르지 않은 목록을 그린다")
        val app = code("feature/phone/src/commonMain/kotlin/com/yehsung/aingcheck/feature/phone/app/PhoneAppModel.kt")
        assertTrue(app.contains("if(messages.megaphoneFeed.isOpen)messages.megaphoneFeed.refresh()"), "실시간 신호가 열린 페이지를 다시 읽지 않는다")
    }
}
