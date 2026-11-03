// 원본: ios-1017-int 1776440d Tests/CheckMobileKitTests/V1017FocusRowsMobileTests.swift(아이폰 1.0.17 — 집중 표시 넓히기) — 판 7 Android 짝.
// 본판(잠금 · 두 자리 칩 · 대화가 설 때 내 집중 조회)은 MessagesFocusGateTest.
//
// 대표 답(원문, 2026-11-03 — 아이폰 1.0.17 카드 답을 안드로이드 판 7 도 따른다. 되묻지 말 것):
//   #d_6A32rmcoJZZd "말 걸 수 있는 줄 전부"(두 곳 + 대화 목록 줄·지금 탭 근무 중 줄, 내가 집중 중이면 메시지 탭 위에 한 줄)
//   #d_ldP912RctnTt "안내만 (단추 없음)"
//
// 이 파일이 재는 것:
//  ① 규칙: 목록 위 한 줄은 켜짐일 때만(문장은 입력줄 · 서버 거절과 같은 글자) · 대화 목록 줄 · 얼굴 띠 TalkBack 의 '집중 중'
//     · 차단해 숨긴 사람은 집중 집합에 들지 않는다(판의 근무 점 · 상태메시지와 같은 규칙)
//  ② 스토어: 목록이 설 때 내 집중을 묻고 · 목록이 떠 있는 채 앞으로 오기 · 켜짐일 때 틱이 묻는다 — 목록도 대화도 없으면 묻지 않는다
//     · 맥에서 끄면 목록 위 한 줄이 사라진다 · 지금 탭은 메시지 스토어의 집합을 그대로 읽는다(출처 한 곳) · 차단 거르기
//     · 게이트가 꺼진 조립(Windows)은 목록이 서도 묻지 않고 집합이 비어 있다(기준선)
// 화면이 이 값을 실제로 부르는지는 화면 시험(ui MessagesFocusSnapshotTest · androidApp NowScreenSnapshotTest)이 잰다.
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.rules.text.MessageNoticeText
import com.yehsung.aingcheck.core.rules.text.MessageThread
import com.yehsung.aingcheck.core.stores.now.InMemoryTodoFileSystem
import com.yehsung.aingcheck.core.stores.now.ManualScheduler
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowStubServer
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryRow
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MessagesFocusRowsTest {
    private val focusedPeer = "peer-focus"
    private val plainPeer = "peer-plain"

    private fun row(id: String, name: String, focus: Boolean): String =
        """{"user_id":"$id","display_name":"$name","avatar_url":null,"is_working":true,"message_capable":true,"center":null,"status_message":null,"focus_mode":$focus}"""

    /** 명부 두 줄(서버 8칸 모양): 집중이(켬) · 보통이([plainIsFocused]). */
    private fun directory(plainIsFocused: Boolean = false): String =
        "[" + listOf(row(focusedPeer, "집중이", true), row(plainPeer, "보통이", plainIsFocused)).joinToString(",") + "]"

    private class Rig(val h: StoreHarness, val server: MessagesServer, val store: MessagesStore, val now: NowStore?) {
        var myFocus: Reply = Reply.Json("""[{"focus_mode":true}]""")
        var gate: CompletableDeferred<Unit>? = null
        fun focusGets(): Int = h.storeRequests.count { isMyFocusGet(it) }
        fun profileWrites(): Int = h.storeRequests.count { it.path == "/rest/v1/profiles" && it.method != "GET" }
    }

    private suspend fun TestScope.rig(gate: Boolean = true, withNow: Boolean = false): Rig {
        val server = MessagesServer().also { it.directory = directory() }
        val nowServer = NowStubServer()
        lateinit var rig: Rig
        val h = StoreHarness(this) { r ->
            if (isMyFocusGet(r)) {
                rig.gate?.let { Reply.Gate(it, rig.myFocus) } ?: rig.myFocus
            } else {
                server.route(r) ?: if (withNow) nowServer.route(r) else null
            }
        }
        h.signIn()
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" }, focusSendGate = gate)
        var now: NowStore? = null
        if (withNow) {
            now = NowStore(h.context, h.storeScope, NowTodoStorage("/mem/now", InMemoryTodoFileSystem()), runsPeriodicRefresh = true, timers = ManualScheduler())
            store.nowStore = now
            // 폰 조립(PhoneAppModel)과 같은 줄 — 지금 탭은 메시지 스토어의 집합을 그대로 읽는다.
            now.onPeriodicTick = { store.refreshMyFocusModeIfFocused() }
            now.focusedPeerIDsSource = { store.focusedPeerIDs }
        }
        rig = Rig(h, server, store, now)
        return rig
    }

    // ---------------------------------------------------------------- ① 규칙

    /** 목록 위 한 줄: 켜짐일 때만 서고 문장은 입력줄 · 서버 거절(sender_focused)과 같은 글자 · 꺼짐/모름은 줄 없음. */
    @Test
    fun listNoticeOnlyWhenOn() {
        assertEquals(MessageNoticeText.senderFocused, MessagesFocusRules.listNotice(true))
        assertEquals(MessagesFocusBlock.myself.notice, MessagesFocusRules.listNotice(true))
        assertTrue(MessageNoticeText.senderFocused.contains("맥에서 집중을 끄면"), "폰엔 [집중 끄기] 단추가 없다(#d_ldP912RctnTt) — 문장이 맥을 가리켜야 한다")
        assertNull(MessagesFocusRules.listNotice(false))
        assertNull(MessagesFocusRules.listNotice(null), "모름은 막지 않으므로 말하지도 않는다")
    }

    /** 대화 목록 줄 TalkBack: 집중이면 근무 줄 뒤에 '집중 중' · 아니면 지금과 한 글자도 같다(기준선). */
    @Test
    fun threadRowAccessibility() {
        val thread = MessageThread<MessageEntry>("p", "하린", null, emptyList())
        val item = MessagesThreadItem(
            thread = thread, pokes = emptyList(), lastActivityAt = SwiftDate.fromReferenceDate(0.0), previewText = "하린님이 콕 찔렀어요",
            lastIsMine = false, previewIsPoke = true, timeText = "13:58", isUnread = false, countBadge = null, group = 0,
        )
        val plain = MessagesThreadListRules.accessibilityText(item, "근무 중")
        assertEquals("하린, 근무 중, 하린님이 콕 찔렀어요, 13:58", plain)
        assertEquals(plain, MessagesThreadListRules.accessibilityText(item, "근무 중", isFocused = false))
        assertEquals("하린, 근무 중, 집중 중, 하린님이 콕 찔렀어요, 13:58", MessagesThreadListRules.accessibilityText(item, "근무 중", isFocused = true))
        // 근무 여부를 모르는 창(점 없음)에서도 집중은 말한다 — 출처가 다르다(명부의 focus_mode).
        assertEquals("하린, 집중 중, 하린님이 콕 찔렀어요, 13:58", MessagesThreadListRules.accessibilityText(item, null, isFocused = true))
    }

    /** 얼굴 띠 TalkBack: 근무 중 · 연결 끊김 뒤에 '집중 중' — 칩은 달지 않는다(대표 답: 얼굴 띠는 보이스오버 말만). 집중 아님은 판 7 전 문장 그대로. */
    @Test
    fun workingStripAccessibility() {
        val working = MessagesWorkingPerson("a", "하린", null, PresenceStatus.working, null)
        val pending = MessagesWorkingPerson("b", "민트", null, PresenceStatus.pending, null)
        assertEquals("하린, 근무 중", MessagesPresenceRules.workingAccessibilityText(working, false), "기준선(판 7 전 문장)이 바뀌었다")
        assertEquals("민트, 연결 끊김", MessagesPresenceRules.workingAccessibilityText(pending, false))
        assertEquals("하린, 근무 중, 집중 중", MessagesPresenceRules.workingAccessibilityText(working, true))
        assertEquals("민트, 연결 끊김, 집중 중", MessagesPresenceRules.workingAccessibilityText(pending, true))
    }

    /** 집중 집합은 차단해 숨긴 사람을 넣지 않는다 — 두 명부 어느 쪽에서 왔든(기준선: 숨기지 않으면 든다). */
    @Test
    fun hiddenPeersAreNotFocused() {
        val entry = PokeDirectoryEntry("a", "가", null, isWorking = true, isFocused = true)
        val row = PokeDirectoryRow("b", "나", null, isWorking = true, focusMode = true)
        assertEquals(setOf("a", "b"), MessagesFocusRules.focusedPeerIDs(listOf(row), listOf(entry), null))
        assertEquals(setOf("b"), MessagesFocusRules.focusedPeerIDs(listOf(row), listOf(entry), null, hidden = setOf("a")))
        assertEquals(emptySet(), MessagesFocusRules.focusedPeerIDs(listOf(row), listOf(entry), null, hidden = setOf("a", "b")))
    }

    // ---------------------------------------------------------------- ② 스토어

    /** 목록이 설 때 내 집중을 묻는다 · 목록이 떠 있는 채 앞으로 오면 묻고 · 켜짐이면 틱도 묻는다 — 목록이 내려가면 다시 묻지 않는다. */
    @Test
    fun listAsksMyFocus() = runTest {
        val r = rig()
        // 기준선: 메시지 화면이 없으면 앞으로 오기 · 틱 모두 묻지 않는다.
        r.store.appDidEnterBackground()
        r.store.appDidBecomeActive()
        r.store.refreshMyFocusModeIfFocused()
        advanceUntilIdle()
        assertEquals(0, r.focusGets(), "메시지 화면이 없는데 물었다")

        // ①-2 목록이 선다 → 묻는다 → 켜짐 → 목록 위 한 줄.
        r.store.listDidAppear()
        advanceUntilIdle()
        assertEquals(1, r.focusGets(), "목록이 섰는데 내 집중을 안 물었다 — 목록 위 한 줄이 맥에서 켠 집중을 모른다")
        assertEquals(true, r.store.myFocusMode)
        assertEquals(MessageNoticeText.senderFocused, MessagesFocusRules.listNotice(r.store.myFocusMode))

        // ③ 켜짐 + 목록 — 틱이 묻는다. 맥에서 껐다(false) → 한 줄이 사라진다.
        r.myFocus = Reply.Json("""[{"focus_mode":false}]""")
        r.store.refreshMyFocusModeIfFocused()
        advanceUntilIdle()
        assertEquals(2, r.focusGets(), "켜짐인데 목록에서 틱이 안 물었다 — 맥에서 끈 집중이 목록에 남는다")
        assertEquals(false, r.store.myFocusMode)
        assertNull(MessagesFocusRules.listNotice(r.store.myFocusMode), "맥에서 껐는데 목록 위 한 줄이 남았다")
        r.store.refreshMyFocusModeIfFocused()
        advanceUntilIdle()
        assertEquals(2, r.focusGets(), "꺼짐인데 틱이 물었다")

        // ② 목록이 떠 있는 채 앞으로 온다 — 맥에서 다시 켰다.
        r.myFocus = Reply.Json("""[{"focus_mode":true}]""")
        r.store.appDidEnterBackground()
        r.store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(3, r.focusGets(), "목록이 떠 있는데 앞으로 오기가 안 물었다")
        assertEquals(true, r.store.myFocusMode)

        // 목록이 내려가면(다른 탭) 켜짐이어도 틱 · 앞으로 오기 모두 묻지 않는다.
        r.store.listDidDisappear()
        r.store.refreshMyFocusModeIfFocused()
        r.store.appDidEnterBackground()
        r.store.appDidBecomeActive()
        advanceUntilIdle()
        assertEquals(3, r.focusGets(), "메시지 화면이 없는데 물었다")
        assertEquals(0, r.profileWrites(), "폰이 profiles 를 썼다(R9)")
        r.h.assertClean()
    }

    /** 목록에서 돌아올 때마다 묻되 날아가는 중이면 겹쳐 띄우지 않는다(조회 규칙은 refreshMyFocusMode 그대로 · 시간 스로틀 없음). */
    @Test
    fun listAppearDoesNotStackFetches() = runTest {
        val r = rig()
        r.gate = CompletableDeferred()
        r.store.listDidAppear()
        runCurrent()
        assertTrue(r.store.isFetchingMyFocusMode)
        r.store.listDidDisappear()
        r.store.listDidAppear()
        r.store.listDidDisappear()
        r.store.listDidAppear()
        runCurrent()
        // ★ 문이 닫힌 동안 가상 시간을 밀지 않는다(advanceUntilIdle 이면 붙잡힌 조회가 HTTP 시한에 걸려 실패로 끝난다).
        assertEquals(1, r.focusGets(), "날아가는 조회 위에 또 띄웠다")
        r.gate!!.complete(Unit)
        r.gate = null
        advanceUntilIdle()
        assertEquals(1, r.focusGets())
        assertFalse(r.store.isFetchingMyFocusMode)
        assertEquals(true, r.store.myFocusMode)
        // 끝난 뒤 다시 서면 또 묻는다(시간 스로틀 없음 — 맥에서 방금 끈 집중이 목록에 남지 않게).
        r.store.listDidDisappear()
        r.store.listDidAppear()
        advanceUntilIdle()
        assertEquals(2, r.focusGets())
        r.h.assertClean()
    }

    /** 지금 탭은 메시지 스토어의 집중 집합을 그대로 읽는다 · 차단해 숨기면 두 탭 모두에서 빠진다(기준선: 숨기기 전엔 든다). */
    @Test
    fun nowReadsMessagesFocusAndBlockHides() = runTest {
        val r = rig(withNow = true)
        val now = r.now!!
        now.appDidBecomeActive()
        advanceUntilIdle()
        assertTrue(now.hasLoadedDirectory, "전제: 지금 탭 명부가 있어야 겹치기를 잴 수 있다")
        assertEquals(setOf(focusedPeer), r.store.focusedPeerIDs)
        assertEquals(r.store.focusedPeerIDs, now.focusedPeerIDs, "지금 탭이 다른 출처로 집중을 읽는다")

        // 상대가 집중을 켰다 — 지금 탭 명부만 새로 받아도 두 탭이 함께 따라온다(메시지 명부는 안 받았다).
        assertFalse(r.store.directoryLoaded, "전제: 메시지 명부는 받지 않았다")
        r.server.directory = directory(plainIsFocused = true)
        now.refresh()
        advanceUntilIdle()
        assertEquals(setOf(focusedPeer, plainPeer), r.store.focusedPeerIDs)
        assertEquals(setOf(focusedPeer, plainPeer), now.focusedPeerIDs)

        // 차단해 숨겼다 — 서버가 다음 조회에서 빼기 전의 창. 근무 점 · 상태메시지처럼 집중도 걷는다.
        r.store.hiddenBlockedPeerIDs = setOf(focusedPeer)
        assertEquals(setOf(plainPeer), r.store.focusedPeerIDs, "차단해 숨긴 사람에게 '집중' 칩이 남는다")
        assertEquals(setOf(plainPeer), now.focusedPeerIDs, "지금 탭 근무 중 줄에 차단한 사람의 칩이 남는다")
        assertFalse(r.store.isPeerFocused(focusedPeer))
        // 차단이 실패해 되돌아오면(숨김을 푼다) 다시 든다.
        r.store.hiddenBlockedPeerIDs = emptySet()
        assertEquals(setOf(focusedPeer, plainPeer), now.focusedPeerIDs)
        r.h.assertClean()
    }

    /**
     * ★ 기준선: 게이트가 꺼진 조립(Windows v1 동결)은 같은 화면 사건 · 같은 명부에서도 내 집중을 묻지 않고 집합이 비어 있다 — 공용 화면(대화 목록 ·
     * 얼굴 띠)이 판 7 전 그림 그대로다. 같은 순서의 켠 조립은 위 시험처럼 묻고 집합이 선다.
     */
    @Test
    fun gateOffAssemblyAsksNothingAndShowsNothing() = runTest {
        val r = rig(gate = false, withNow = true)
        val now = r.now!!
        now.appDidBecomeActive()
        r.store.appDidBecomeActive()
        r.store.listDidAppear()
        r.store.loadDirectory(force = true)
        advanceUntilIdle()
        r.store.refreshMyFocusModeIfFocused()
        now.onPeriodicTick()
        advanceUntilIdle()
        assertTrue(now.hasLoadedDirectory && r.store.directoryLoaded, "전제: 명부 둘이 집중을 말한다")
        assertEquals(0, r.focusGets(), "게이트가 꺼졌는데 목록이 서며 내 집중을 물었다")
        assertNull(r.store.myFocusMode)
        assertNull(MessagesFocusRules.listNotice(r.store.myFocusMode))
        assertEquals(emptySet(), r.store.focusedPeerIDs, "게이트가 꺼졌는데 집중 집합이 섰다(Windows 목록에 칩이 선다)")
        assertEquals(emptySet(), now.focusedPeerIDs)
        r.h.assertClean()
    }

    private companion object {
        fun isMyFocusGet(r: RecordedRequest): Boolean =
            r.method == "GET" && r.path == "/rest/v1/profiles" && r.query.any { it.first == "select" && it.second == "focus_mode" }
    }
}
