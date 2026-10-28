// 원본: Tests/CheckMobileKitTests/MessagesDemoFixtureTests.swift(목록 · 찌르기 · 대화 장면) · AvatarCharacterTests.swift(데모 캐릭터 표) @ 1b8260d
// 배정표(round5-lane-map:119·122): 데모 픽스처 `Demo/Fixtures/{base,messages}/**` 를 **복사 없이** 저장소 제자리에서 읽어(testkit RepoFiles)
// 실제 응답 모양으로 스토어를 몬다 — 손으로 지은 JSON 이 아니라 iOS 데모와 같은 바이트다. 응답 규칙은 Swift `MobileDemoFixtures.response`
// (장면 폴더 `_<장면>/` 가 먼저, 없으면 영역 폴더, `__status` 봉투는 그 상태 코드)를 그대로 따른다.
package com.yehsung.aingcheck.core.stores.messages

import com.yehsung.aingcheck.core.stores.characters.AppUserCharacterStore
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import com.yehsung.aingcheck.testkit.mock.RecordedRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class MessagesDemoFixtureTest {
    private val root = "Sources/CheckMobileKit/Demo/Fixtures"
    private val demoUser = "d0000000-0000-4000-8000-000000000001"
    private val hangyeol = "d0000000-0000-4000-8000-0000000000b1"
    private val sora = "d0000000-0000-4000-8000-0000000000b2"
    private val doyun = "d0000000-0000-4000-8000-0000000000b4"
    private val harin = "d0000000-0000-4000-8000-0000000000b5"

    /** 픽스처 하나(없으면 null). */
    private fun read(path: String): String? = try {
        RepoFiles.readText(path)
    } catch (e: IllegalArgumentException) {
        null
    }

    /** Swift `MobileDemoFixtures.response(for:scenario:)` — 장면 폴더 → 영역 폴더 → base. 없으면 함수 없음(404 · PGRST202). */
    private fun demoReply(r: RecordedRequest, scenario: String): Reply? {
        val rpc = r.rpcName ?: return null
        val name = "rpc.$rpc.json"
        val text = read("$root/messages/_$scenario/$name") ?: read("$root/messages/$name") ?: read("$root/base/$name") ?: return Reply.missingFunction
        val parsed = SwiftJson.parse(text)
        if (parsed is JsonObject && parsed["__status"] != null) {
            val status = parsed["__status"]!!.jsonPrimitive.intOrNull ?: 500
            return Reply.Json(parsed["__body"]?.toString() ?: "{}", status)
        }
        return Reply.Json(text)
    }

    private suspend fun TestScope.demo(scenario: String): Pair<StoreHarness, MessagesStore> {
        val h = StoreHarness(this) { demoReply(it, scenario) }
        h.signIn(demoUser)
        val store = MessagesStore(h.context, h.storeScope, NaturalKoNameCollation, newLocalID = { "local-1" })
        store.appDidBecomeActive()
        advanceUntilIdle()
        return h to store
    }

    @Test
    fun listSceneFromDemoFixtures() = runTest {
        val (h, store) = demo("messages")
        assertEquals(3, store.badgeCount, "요약 픽스처(안 읽음 3)를 배지로 세지 않았다")
        store.listDidAppear()
        advanceUntilIdle()
        assertTrue(store.readReceiptsAvailable)
        assertEquals(listOf("소라", "한결", "민재", "도윤"), store.threads.map { it.peerName }, "메시지 묶음은 최근순")
        assertEquals(setOf(sora, doyun), store.unreadPeerIDs)
        assertEquals(3, store.badgeCount)
        assertTrue(h.storeRequests.none { it.rpcName == "mark_messages_read" || it.rpcName == "mark_conversation_read" }, "목록만 보고 읽음을 올렸다")

        store.loadDirectory()
        advanceUntilIdle()
        assertEquals(listOf("하린", "소라", "도윤", "한결", "민재"), store.threadItems(h.now()).map { it.peerName },
            "찌르기를 포함한 네 무리 정렬(찌르기만 있는 하린이 맨 위)")
        assertEquals(8, store.directory.size)
        assertEquals(3, store.directory.take(3).count { it.isWorking })
        h.assertClean()
    }

    @Test
    fun pokeSceneGoesThroughTheStore() = runTest {
        val (h, store) = demo("messages")
        store.listDidAppear()
        store.loadDirectory()
        advanceUntilIdle()
        assertTrue(h.storeRequests.any { it.rpcName == "message_history_with_pokes" })
        assertTrue(h.storeRequests.none { it.rpcName == "message_history_with_reads" }, "새 RPC 가 있는데 옛 조회로 접었다")
        assertTrue(store.pokeLogAvailable)
        assertEquals(4, store.pokeLog.size)
        assertEquals(setOf(harin), store.unreadPokePeerIDs, "하린의 안 본 찌르기를 못 셌다")
        assertEquals(setOf(sora, doyun), store.unreadPeerIDs, "찌르기가 메시지 안 읽음으로 샜다")

        val rows = store.threadItems(h.now())
        assertEquals(listOf("하린", "소라", "도윤", "한결", "민재"), rows.map { it.peerName })
        assertEquals(listOf(0, 0, 1, 2, 3), rows.map { it.group })
        assertEquals("하린님이 울트라 찔렀어요", rows[0].previewText)
        assertTrue(rows[0].isUnread)
        assertNull(rows[0].countBadge, "안 읽음이 찌르기뿐인데 숫자가 섰다")
        assertEquals("2", rows[1].countBadge)
        assertEquals("내가 울트라 찔렀어요", rows[3].previewText, "한결 행 미리보기가 마지막 활동(내 울트라)이 아니다")

        val items = store.conversationItems(hangyeol)
        val pokeLines = items.mapNotNull { (it as? MessagesConversationItem.poke)?.line?.text }
        assertEquals(listOf("한결님이 콕 찔렀어요 · 11:39", "내가 울트라 찔렀어요 · 13:53"), pokeLines)
        val ids = items.map { it.id }
        val pokeIndex = ids.indexOf("poke-d0000000-0000-4000-8000-00000000f001")
        assertTrue(pokeIndex >= 0)
        val nextBubble = ids.drop(pokeIndex + 1).firstOrNull { !it.startsWith("poke-") && !it.startsWith("day-") }
        assertEquals("d0000000-0000-4000-8000-00000000e005", nextBubble, "찌르기 줄이 11:39 와 11:40 사이에 안 들어갔다")

        val harinLines = store.conversationItems(harin).mapNotNull { (it as? MessagesConversationItem.poke)?.line?.text }
        assertEquals(listOf("하린님이 콕 찔렀어요 · 14:00", "하린님이 울트라 찔렀어요 · 14:03"), harinLines)
        assertEquals("하린", store.peerName(harin))
        h.assertClean()
    }

    @Test
    fun conversationSceneHangyeol() = runTest {
        val (h, store) = demo("messages-$hangyeol")
        store.conversationDidAppear(hangyeol, "t1")
        advanceUntilIdle()
        val items = store.conversationItems(hangyeol)
        assertEquals(listOf("어제", "오늘"), items.mapNotNull { (it as? MessagesConversationItem.day)?.label })
        val bubbles = items.mapNotNull { (it as? MessagesConversationItem.bubble)?.line }
        assertEquals(7, bubbles.size)
        assertEquals(2, bubbles.count { it.showsUnreadOne }, "내 말 두 개에 1")
        assertEquals(listOf(false, true), bubbles.takeLast(2).map { it.showsTime }, "같은 분은 마지막에만 시각")
        assertEquals("한결", store.peerName(hangyeol))
        assertTrue(h.storeRequests.none { it.rpcName == "mark_messages_read" }, "안 읽은 말이 없는데 읽음을 올렸다")
        h.assertClean()
    }

    @Test
    fun historyFailureSceneFromStatusEnvelope() = runTest {
        val peer = "d0000000-0000-4000-8000-0000000000c1"
        val (h, store) = demo("messages-$peer")
        store.conversationDidAppear(peer, "t1")
        advanceUntilIdle()
        assertTrue(store.historyFailed, "이력 500 봉투를 실패로 읽지 않았다")
        assertFalse(store.historyLoaded)
        assertNull(store.peerName(peer))
        h.assertClean()
    }

    /** 데모 캐릭터 표(base/rpc.app_user_characters.json — 케이크 둘 포함, 0.3.66). null 은 아잉, 아는 그림은 그대로, 모르는 그림은 이니셜. */
    @Test
    fun characterDirectoryFromDemoFixtureIncludesCakes() = runTest {
        val h = StoreHarness(this) { r -> if (r.rpcName == "app_user_characters") Reply.Json(RepoFiles.readText("$root/base/rpc.app_user_characters.json")) else null }
        h.signIn(demoUser)
        val known = listOf("aing", "fox", "shiba", "squirrel", "jellyfish", "ghost", "aing_cake_choco", "aing_cake_strawberry")
        val store = AppUserCharacterStore(h.context, h.storeScope, known)
        store.refresh()
        advanceUntilIdle()
        assertEquals("fox", store.directory.characterID(demoUser))
        assertEquals("aing_cake_choco", store.directory.characterID("d0000000-0000-4000-8000-000000000201"))
        assertEquals("aing_cake_strawberry", store.directory.characterID("d0000000-0000-4000-8000-000000000202"))
        assertEquals("jellyfish", store.directory.characterID(hangyeol))
        assertEquals("aing", store.directory.characterID("d0000000-0000-4000-8000-000000000103"), "character null 은 아잉(Swift equippedID: null → 아잉)")
        assertNull(store.directory.characterID("d0000000-0000-4000-8000-000000000104"), "모르는 그림(무지개 — 이 목록 밖)은 이니셜")
        h.assertClean()
    }
}
