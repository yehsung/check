// 원본: Tests/checkTests/V0328GomokuChatStoreTests.swift:285-836(채팅 증분 · 구멍 · 늦은 응답 · 보내기 · 음소거 토글 × 세대 · 판 바뀜) · V0350GomokuExitChatTests.swift:140-420(끝인사 초인종 · 안전망 130초 창) @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.net.realtime.RealtimeState
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 대국 중 대화의 **스토어 몫**(검증 지적 — 첫 판에는 chat_send 교착 재시도 하나뿐이었고 `p_since_chat_seq` 를 늘 0 으로 바꿔도 초록이었다, V08).
 *  ① 채팅은 들고 있는 발급 번호부터 묻고(증분), 구멍이 나면 since 0 으로 **한 번** 전체를 받는다 · 음소거로 건너뛴 번호는 구멍이 아니다.
 *  ② 늦게 온 응답은 착수와 같은 겹으로 막는다: 번호 역행은 통째로 버리고, 음소거 토글 **뒤에** 도착한 응답은 세대가 달라 채팅만 버린다(판은 받는다).
 *  ③ 음소거 토글은 기준선(`chatSeq`)을 **내리지 않는다** — 세대를 올리고 전체 재요청은 표시로 건다.
 *  ④ 끝난 판의 끝인사는 결과 화면에 서 있는 동안(끝난 뒤 **130초**, 끄지 않았을 때만) 초인종 · 따라잡기 · 안전망 폴링이 읽는다.
 * 기대값은 전부 손으로 적은 수다(번호 열 · 주기 5/10초 · 창 130초) — 구현 상수를 읽지 않는다.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class GomokuChatStoreTest {
    private fun TestScope.rig(configure: DuelStubServer.() -> Unit = {}): Triple<GomokuStore, FakeDuelHost, DuelStubServer> {
        val server = DuelStubServer(this).apply(configure)
        val host = FakeDuelHost(server.service { contractClock }, HAND_ME, clockNow = { contractClock })
        val store = GomokuStore(storeScope(), host)
        store.clock = { contractClock }
        return Triple(store, host, server)
    }

    private fun DuelStubServer.stateSinces(): List<Long?> = bodies("gomoku_state").map { it.sinceChat() }

    // MARK: ① 증분 · 구멍

    @Test
    fun chatAsksFromTheHeldSeqAndRereadsEverythingOnceOnAGap() = runTest {
        val (store, _, server) = rig {
            respondWith("gomoku_state") { body, _ ->
                if (body.sinceChat() == 0L) {
                    handReply(handState(chat = listOf(handChat(1, "안녕", mine = true), handChat(2, "반가워요"), handChat(3, "두세요", mine = true)), chatSeq = 3))
                } else {
                    // since 1 을 물었는데 2가 빠진 채 3만 온다(구멍) → 처음부터 다시 받아야 한다.
                    handReply(handState(chat = listOf(handChat(3, "두세요", mine = true)), chatSeq = 3))
                }
            }
        }
        store.applyState(handPayload(handState(chat = listOf(handChat(1, "안녕", mine = true)), chatSeq = 1)))
        assertEquals(1L, store.chatSeq)
        assertEquals(listOf(1L), store.chat.map { it.seq })

        store.refreshMatch()

        assertEquals(listOf<Long?>(1, 0), server.stateSinces(), "들고 있는 번호부터 묻고, 구멍이 나면 0 으로 한 번 더 받는다")
        assertEquals(listOf(1L, 2L, 3L), store.chat.map { it.seq }, "구멍 난 대화를 그리면 2번 줄이 영영 안 보인다")
        assertEquals(listOf("안녕", "반가워요", "두세요"), store.chat.map { it.body })
        assertEquals(listOf(true, false, true), store.chat.map { it.isMine }, "내 말·상대 말 판정은 서버가 한다")
        assertEquals(3L, store.chatSeq)
    }

    @Test
    fun anIncrementalReplyAppendsWithoutRereading() = runTest {
        val (store, _, server) = rig {
            queue("gomoku_state", handReply(handState(chat = listOf(handChat(2, "반가워요")), chatSeq = 2)))
        }
        store.applyState(handPayload(handState(chat = listOf(handChat(1, "안녕", mine = true)), chatSeq = 1)))
        store.refreshMatch()
        assertEquals(listOf<Long?>(1), server.stateSinces(), "이어지는 증분인데 전체를 다시 물었다")
        assertEquals(listOf(1L, 2L), store.chat.map { it.seq })
        assertEquals(2L, store.chatSeq)
        // 다음 조회는 받은 번호(2) 뒤만 묻는다.
        server.queue("gomoku_state", handReply(handState(chat = emptyList(), chatSeq = 2)))
        store.refreshMatch()
        assertEquals(listOf<Long?>(1, 2), server.stateSinces())
    }

    @Test
    fun aSkippedSeqWhileMutedIsNotAGap() = runTest {
        val (store, _, server) = rig {
            // 상대 줄(2·3)은 서버가 걸러 내고 내 줄(4)만 온다 — 번호가 뛰지만 정상이다.
            queue("gomoku_state", handReply(handState(chat = listOf(handChat(4, "혼잣말", mine = true)), chatSeq = 4, myMuted = true)))
        }
        store.applyState(handPayload(handState(chat = listOf(handChat(1, "안녕", mine = true)), chatSeq = 1, myMuted = true)))
        assertTrue(store.isMuted)
        store.refreshMatch()
        assertEquals(1, server.count("gomoku_state"), "가려진 줄을 구멍으로 읽어 다시 물었다")
        assertEquals(listOf(1L, 4L), store.chat.map { it.seq })
        assertEquals(4L, store.chatSeq, "다음 since 는 마지막 줄이 아니라 서버 발급 번호다")
    }

    @Test
    fun aRegressedSeqCannotRewindTheChatOrTheMute() = runTest {
        val (store, _, _) = rig()
        store.applyState(
            handPayload(
                handState(
                    chat = listOf(handChat(1, "안녕", mine = true), handChat(2, "반가워요"), handChat(3, "네")),
                    chatSeq = 3, myMuted = true, opponentMuted = true, chatCapable = false,
                ),
            ),
        )
        assertEquals(3, store.chat.size)
        // 조회 → 음소거 → 음소거 응답 → 조회 응답 순서로 늦게 도착한 옛 스냅숏.
        store.applyState(
            handPayload(handState(chat = listOf(handChat(1, "안녕", mine = true)), chatSeq = 1, myMuted = false, opponentMuted = false, chatCapable = true)),
        )
        assertEquals(listOf(1L, 2L, 3L), store.chat.map { it.seq }, "옛 스냅숏이 대화를 잘라 냈다")
        assertEquals(3L, store.chatSeq)
        assertTrue(store.isMuted, "옛 스냅숏이 방금 켠 음소거를 풀었다")
        assertTrue(store.isOpponentMuted)
        assertFalse(store.opponentChatCapable)
    }

    @Test
    fun aReplyWithoutChatKeysKeepsTheConversation() = runTest {
        val (store, _, _) = rig()
        store.applyState(handPayload(handState(chat = listOf(handChat(1, "안녕", mine = true)), chatSeq = 1)))
        // 쓰기 RPC 가 싣는 state 묶음에는 채팅 키가 없다 — 그것을 "대화가 비었다"로 읽으면 안 된다.
        store.applyState(handPayload(handState(moveCount = 1, moves = listOf(handMove(1, "black", 7, 7)), turn = "white")))
        assertEquals(listOf(1L), store.chat.map { it.seq })
        assertEquals(1L, store.chatSeq)
    }

    // MARK: 보내기

    @Test
    fun aFailedSendKeepsTheDraftAndIsNotResent() = runTest {
        val (store, _, server) = rig {
            respondWith("gomoku_chat_send") { _, index ->
                if (index == 0) jsonReply("status" to "invalid", "chat_max_len" to 100)
                else jsonReply("status" to "ok", "chat_seq" to 1, "opponent_muted" to true, "chat_capable" to false)
            }
            queue("gomoku_state", handReply(handState(chat = listOf(handChat(1, "안녕하세요", mine = true)), chatSeq = 1, opponentMuted = true, chatCapable = false)))
        }
        store.applyState(handPayload(handState(chat = emptyList(), chatSeq = 0)))
        store.chatDraft = "안녕하세요"
        assertTrue(store.canSendChatNow)

        store.sendChatDraft()
        advanceUntilIdle()
        assertEquals("안녕하세요", store.chatDraft, "실패한 글은 사용자 것이다 — 비우지 않는다")
        assertEquals(GomokuNoticeText.chatBlocked, store.chatNotice)
        assertEquals(1, server.count("gomoku_chat_send"), "실패를 자동으로 다시 보냈다")
        assertEquals(0, server.count("gomoku_state"), "실패에는 다시 읽지 않는다")
        assertTrue(store.chat.isEmpty())

        store.sendChatDraft()
        advanceUntilIdle()
        assertEquals("", store.chatDraft, "성공했을 때만 비운다")
        assertNull(store.chatNotice)
        // 낙관 삽입이 아니라 서버가 정규화한 줄을 다시 받아 그린다.
        assertEquals(listOf("안녕하세요"), store.chat.map { it.body })
        assertEquals(true, store.chat.first().isMine)
        assertEquals("text", server.lastBody("gomoku_chat_send").str("p_kind"))
        assertEquals("안녕하세요", server.lastBody("gomoku_chat_send").str("p_body"))
        // 상대가 껐다 · 못 받는 버전이다를 **보낸 사람이 안다**.
        assertTrue(store.isOpponentMuted)
        assertFalse(store.opponentChatCapable)
    }

    @Test
    fun sendingChatNeverLocksPlacingAStone() = runTest {
        val (store, _, server) = rig {
            queue("gomoku_chat_send", StubReply.Delayed(0.4, jsonReply("status" to "ok", "chat_seq" to 1)))
            queue("gomoku_move", jsonReply("status" to "ok", "state" to handState(turn = "white", moveCount = 1, moves = listOf(handMove(1, "black", 7, 7)))))
            respondWith("gomoku_state") { _, _ -> handReply(handState(turn = "white", moveCount = 1, moves = listOf(handMove(1, "black", 7, 7)), chat = emptyList(), chatSeq = 1)) }
        }
        store.applyState(handPayload(handState(turn = "black", chat = emptyList(), chatSeq = 0)))
        store.chatDraft = "잘 부탁해요"
        store.sendChatDraft()
        runCurrent()
        assertTrue(store.isSendingChat)
        assertFalse(store.isBusy, "채팅 왕복이 착수를 잠갔다 — 한 수 30초짜리 판에서 그건 곧 패배다")
        store.place(GomokuPoint.at(7, 7)!!)
        assertEquals(1, server.count("gomoku_move"), "채팅이 도는 동안 착수가 나가지 않았다")
        assertEquals(1, store.match?.moveCount)
        advanceUntilIdle()
        assertFalse(store.isSendingChat)
    }

    // MARK: ③ 음소거 토글

    @Test
    fun muteUsesTheServerValueAndRereadsTheWholeChat() = runTest {
        val (store, _, server) = rig {
            queue("gomoku_chat_mute", jsonReply("status" to "ok", "muted" to true))
            // 껐으니 상대 줄(1)은 서버가 걸러 내고 내 줄만 온다.
            queue("gomoku_state", handReply(handState(chat = listOf(handChat(2, "그럼", mine = true)), chatSeq = 2, myMuted = true)))
        }
        store.applyState(handPayload(handState(chat = listOf(handChat(1, "약올리기"), handChat(2, "그럼", mine = true)), chatSeq = 2)))
        assertEquals(2, store.chat.size)
        assertFalse(store.isMuted)

        store.setChatMuted(true)
        advanceUntilIdle()

        assertTrue(store.isMuted)
        assertEquals(true, server.lastBody("gomoku_chat_mute").bool("p_muted"))
        assertEquals(listOf<Long?>(0), server.stateSinces(), "가려짐은 서버가 정한다 — 그 판 대화를 처음부터 다시 받아야 한다")
        assertEquals(listOf(2L), store.chat.map { it.seq }, "끈 뒤에는 상대 말이 화면에서 사라진다")
        assertNull(store.chatNotice, "토글과 대화 자리의 한 줄이 이미 말한다")
    }

    @Test
    fun aLateReadDuringTheToggleCannotRewindItAndTheHiddenLinesComeBack() = runTest {
        // 음소거로 두던 판(서버 chat_seq = 8)에서 조회가 나간 **뒤** [켜기] 를 누른다. 늦게 온 응답은 my_muted = true · chat_seq = 8 을 싣는다 —
        // 그것을 받으면 방금 누른 토글이 되감기고, 줄은 하나도 안 담긴 채 번호만 8 로 남아 다음 회차가 since 8 로 물어 여덟 줄이 통째로 안 보인다.
        val (store, _, server) = rig {
            queue("gomoku_chat_mute", jsonReply("status" to "ok", "muted" to false))
            respondWith("gomoku_state") { body, index ->
                when {
                    // 음소거 직전에 나간 조회 — 토글 **뒤에** 도착한다.
                    index == 0 -> handReply(handState(chat = emptyList(), chatSeq = 8, myMuted = true), delaySeconds = 0.6)
                    // 서버는 **물은 번호 뒤만** 답한다. 0 으로 묻지 않으면 가려졌던 여덟 줄은 영영 안 온다.
                    body.sinceChat() != 0L -> handReply(handState(chat = emptyList(), chatSeq = 8, myMuted = false))
                    else -> handReply(handState(chat = (1L..8L).map { handChat(it, "줄 $it", mine = it % 2 == 0L) }, chatSeq = 8, myMuted = false))
                }
            }
        }
        store.applyState(handPayload(handState(chat = listOf(2L, 4L, 6L, 8L).map { handChat(it, "줄 $it", mine = true) }, chatSeq = 8, myMuted = true)))
        assertTrue(store.isMuted && store.chatSeq == 8L)

        val pending = launch { store.refreshMatch() }
        runCurrent()
        assertEquals(1, server.count("gomoku_state"))
        store.setChatMuted(false)
        runCurrent()
        assertFalse(store.isMuted, "토글 왕복은 나가 있던 조회를 기다리지 않는다")
        assertEquals(8L, store.chatSeq, "토글이 기준선을 내렸다 — 어떤 옛 스냅숏도 역행에 안 걸린다")
        pending.join()
        advanceUntilIdle()

        assertFalse(store.isMuted, "늦게 온 옛 스냅숏이 방금 누른 [켜기] 를 되감았다")
        assertEquals(listOf<Long?>(8, 0), server.stateSinces(), "켠 뒤에는 그 판 대화를 처음부터 받아야 한다")
        assertEquals((1L..8L).toList(), store.chat.map { it.seq }, "가려졌던 줄이 켠 뒤에도 안 돌아왔다")
        assertEquals(8L, store.chatSeq)
        assertEquals(false, server.lastBody("gomoku_chat_mute").bool("p_muted"))
    }

    @Test
    fun anUnmuteFromAnotherDeviceRereadsTheWholeChatOnce() = runTest {
        val (store, _, server) = rig {
            respondWith("gomoku_state") { body, _ ->
                if (body.sinceChat() == 0L) handReply(handState(chat = (1L..8L).map { handChat(it, "줄 $it", mine = it % 2 == 0L) }, chatSeq = 8, myMuted = false))
                else handReply(handState(chat = emptyList(), chatSeq = 8, myMuted = false))
            }
        }
        store.applyState(handPayload(handState(chat = listOf(2L, 4L, 6L, 8L).map { handChat(it, "줄 $it", mine = true) }, chatSeq = 8, myMuted = true)))
        store.refreshMatch()
        assertFalse(store.isMuted)
        assertEquals(listOf<Long?>(8, 0), server.stateSinces(), "음소거가 뒤집혀 왔는데 전체 재요청을 안 걸었다")
        assertEquals((1L..8L).toList(), store.chat.map { it.seq }, "가려졌던 줄이 안 돌아왔다")
        assertEquals(2, server.count("gomoku_state"), "전체 재요청은 한 번이다(되묻기 고리)")
    }

    @Test
    fun aLateMoveReplyCannotRewindTheMuteButTheStoneLands() = runTest {
        // 쓰기 RPC 도 state 묶음을 싣는다 — 토글보다 **먼저** 나간 착수의 응답이 옛 my_muted 를 싣고 뒤늦게 온다. 채팅은 버리고 판은 받는다.
        val stoneState = handState(
            turn = "white", moveCount = 1, moves = listOf(handMove(1, "black", 7, 7)),
            chat = listOf(handChat(1, "약올리기"), handChat(2, "그럼", mine = true)), chatSeq = 2, myMuted = false,
        )
        val (store, _, server) = rig {
            queue("gomoku_move", StubReply.Delayed(0.6, jsonReply("status" to "ok", "state" to stoneState)))
            queue("gomoku_chat_mute", jsonReply("status" to "ok", "muted" to true))
            queue(
                "gomoku_state",
                handReply(handState(turn = "white", moveCount = 1, moves = listOf(handMove(1, "black", 7, 7)), chat = listOf(handChat(2, "그럼", mine = true)), chatSeq = 2, myMuted = true)),
            )
        }
        store.applyState(handPayload(handState(turn = "black", chat = listOf(handChat(1, "약올리기"), handChat(2, "그럼", mine = true)), chatSeq = 2)))
        val pending = launch { store.place(GomokuPoint.at(7, 7)!!) }
        runCurrent()
        assertEquals(1, server.count("gomoku_move"))
        store.setChatMuted(true)
        runCurrent()
        assertTrue(store.isMuted, "토글 왕복은 착수 응답을 기다리지 않는다")
        pending.join()
        advanceUntilIdle()

        assertTrue(store.isMuted, "늦게 온 착수 응답의 옛 my_muted 가 방금 누른 토글을 되감았다")
        assertEquals(listOf(2L), store.chat.map { it.seq }, "껐는데 상대 줄이 늦은 착수 응답에 되살아났다")
        assertEquals(1, store.match?.moveCount, "늦은 응답의 채팅을 버리느라 착수 결과까지 버렸다")
        assertEquals(GomokuColor.black, store.match?.board?.get(GomokuPoint.at(7, 7)!!))
        assertEquals(GomokuColor.white, store.match?.turn)
    }

    @Test
    fun switchingMatchesClearsChatDraftAndMute() = runTest {
        val (store, _, _) = rig()
        store.applyState(
            handPayload(handState(chat = listOf(handChat(1, "안녕", mine = true)), chatSeq = 1, myMuted = true, opponentMuted = true, chatCapable = false, chatMaxLen = 80)),
        )
        store.chatDraft = "쓰다 만 글"
        assertTrue(store.isMuted && store.isOpponentMuted && !store.opponentChatCapable)
        assertEquals(80L, store.chatMaxLength)
        store.applyState(handPayload(handState(id = HAND_OTHER_MATCH)))
        assertEquals(HAND_OTHER_MATCH, store.match?.id)
        assertTrue(store.chat.isEmpty(), "앞 판의 대화가 새 판에 남았다")
        assertEquals(0L, store.chatSeq, "앞 판의 발급 번호로 새 판을 물으면 새 판 대화가 안 보인다")
        assertEquals("", store.chatDraft)
        assertFalse(store.isMuted || store.isOpponentMuted)
        assertTrue(store.opponentChatCapable)
        assertEquals(100L, store.chatMaxLength, "앞 판의 상한이 새 판에 남았다(기본 100)")
    }

    // MARK: ④ 끝인사

    @Test
    fun aDoorbellOnTheResultScreenReadsTheFarewellIncrementally() = runTest {
        val (store, _, server) = rig {
            queue(
                "gomoku_state",
                handReply(handState(finished = true, chat = listOf(handChat(1, "수고하셨어요")), chatSeq = 1)),
                handReply(handState(finished = true, chat = listOf(handChat(2, "한 판 더 해요")), chatSeq = 2)),
            )
            respondWith("gomoku_inbox") { _, _ -> jsonReply("status" to "ok", "incoming" to kotlinx.serialization.json.JsonArray(emptyList()), "outgoing" to null) }
        }
        store.applyState(handPayload(handState(finished = true, chat = emptyList(), chatSeq = 0)))
        assertEquals(GomokuPhase.result, store.phase)
        assertEquals(0, server.count("gomoku_state"), "결과 화면을 세우는 것만으로 판을 다시 읽었다")
        store.handleSignal()
        advanceUntilIdle()
        assertEquals(listOf("수고하셨어요"), store.chat.map { it.body }, "끝난 판의 초인종이 상대의 끝인사를 안 읽어 왔다")
        assertEquals(1, server.count("gomoku_inbox"), "끝난 판이어도 초인종은 새 신청일 수 있다 — 받은함도 읽는다")
        assertEquals(HAND_MATCH, server.lastBody("gomoku_state").str("p_match_id"))
        store.handleSignal()
        advanceUntilIdle()
        assertEquals(listOf("수고하셨어요", "한 판 더 해요"), store.chat.map { it.body })
        assertEquals(listOf<Long?>(0, 1), server.stateSinces(), "끝난 판의 대화를 매번 처음부터 다시 받는다")
        assertEquals(GomokuPhase.result, store.phase)
    }

    @Test
    fun theFarewellSafetyNetPollsOnlyWhileVisibleAndOnlyForThe130SecondWindow() = runTest {
        var now = contractClock
        val (store, host, server) = rig {
            respondWith("gomoku_state") { _, index -> handReply(handState(finished = true, chat = listOf(handChat(index + 1L, "줄 ${index + 1}")), chatSeq = index + 1L)) }
        }
        store.clock = { now }
        val t0 = now
        store.applyState(handPayload(handState(finished = true, chat = emptyList(), chatSeq = 0)))
        assertEquals(HAND_MATCH, store.finishedChatWatch?.first)
        assertEquals(t0.addingTimeInterval(130.0), store.finishedChatWatch?.second, "끝인사 창은 끝난 뒤 130초(서버 120초 + 여유)")
        store.lastStateRequestAt = t0
        suspend fun tick(offset: Double) {
            now = t0.addingTimeInterval(offset)
            store.pollTick(now)
        }
        // 창이 안 보이면 안 돈다.
        tick(50.0)
        assertEquals(0, server.count("gomoku_state"))
        store.isWindowVisible = true
        // 미구독: 5초.
        tick(4.9)
        assertEquals(0, server.count("gomoku_state"))
        tick(5.1)
        assertEquals(1, server.count("gomoku_state"))
        assertEquals(listOf("줄 1"), store.chat.map { it.body }, "안전망이 읽어 온 끝인사가 화면에 안 붙었다")
        tick(9.0)
        assertEquals(1, server.count("gomoku_state"))
        tick(10.2)
        assertEquals(2, server.count("gomoku_state"))
        // 구독 중: 10초(주 경로는 초인종이다).
        host.realtimeState = RealtimeState.Subscribed(t0, t0)
        tick(19.0)
        assertEquals(2, server.count("gomoku_state"))
        tick(20.3)
        assertEquals(3, server.count("gomoku_state"))
        // 같은 끝난 판을 다시 읽어도 끝이 뒤로 밀리지 않는다 — 밀리면 영영 안 닫힌다.
        assertEquals(t0.addingTimeInterval(130.0), store.finishedChatWatch?.second)
        tick(129.0)
        assertEquals(4, server.count("gomoku_state"))
        tick(141.0)
        assertEquals(4, server.count("gomoku_state"), "서버가 더는 말을 안 받는 시간에도 끝난 판을 읽는다")
        tick(3_600.0)
        assertEquals(4, server.count("gomoku_state"))
        assertEquals(0, server.count("gomoku_lobby"), "결과 화면에서는 로비 목록도 돌지 않는다")
    }

    @Test
    fun theSafetyNetCountsFromTheServersFinishTime() = runTest {
        val t0 = contractClock
        val t0Ms = t0.timeIntervalSince1970 * 1000
        // 서버가 끝난 시각을 말해 주면 **거기서** 센다 — 200초 전에 끝난 판을 뒤늦게 세우면 안전망은 이미 닫혀 있다.
        var now = t0
        val (late, _, lateServer) = rig { respondWith("gomoku_state") { _, _ -> handReply(handState(finished = true, chat = emptyList(), chatSeq = 0)) } }
        late.clock = { now }
        late.applyState(handPayload(handState(finished = true, chat = emptyList(), chatSeq = 0, finishedMs = t0Ms - 200_000, serverNowMs = t0Ms)))
        assertEquals(-70.0, late.finishedChatWatch!!.second.timeIntervalSince(t0), 1e-6)
        late.isWindowVisible = true
        late.lastStateRequestAt = t0
        now = t0.addingTimeInterval(30.0)
        late.pollTick(now)
        assertEquals(0, lateServer.count("gomoku_state"), "오래전에 끝난 판에 안전망이 돈다")
        // 기준선: 방금 끝난 판은 같은 순간에 돈다(위 0 이 '아무것도 안 도는 스토어'라서가 아니다).
        val (fresh, _, freshServer) = rig { respondWith("gomoku_state") { _, _ -> handReply(handState(finished = true, chat = emptyList(), chatSeq = 0)) } }
        now = t0
        fresh.clock = { now }
        fresh.applyState(handPayload(handState(finished = true, chat = emptyList(), chatSeq = 0, finishedMs = t0Ms, serverNowMs = t0Ms)))
        fresh.isWindowVisible = true
        fresh.lastStateRequestAt = t0
        now = t0.addingTimeInterval(30.0)
        fresh.pollTick(now)
        assertEquals(1, freshServer.count("gomoku_state"))
    }

    @Test
    fun doorbellsOutsideTheWindowOrWhileMutedDoNotReadTheFinishedMatch() = runTest {
        val inbox = { _: kotlinx.serialization.json.JsonObject, _: Int ->
            jsonReply("status" to "ok", "incoming" to kotlinx.serialization.json.JsonArray(emptyList()), "outgoing" to null)
        }
        val farewell = { _: kotlinx.serialization.json.JsonObject, _: Int ->
            handReply(handState(finished = true, chat = listOf(handChat(1, "수고하셨어요")), chatSeq = 1))
        }
        var now: SwiftDate = contractClock
        val t0 = now
        // 시간 밖(131초): 받은함은 읽고 판은 안 읽는다.
        val (late, _, lateServer) = rig { respondWith("gomoku_inbox", inbox); respondWith("gomoku_state", farewell) }
        late.clock = { now }
        late.applyState(handPayload(handState(finished = true, chat = emptyList(), chatSeq = 0)))
        now = t0.addingTimeInterval(131.0)
        late.handleSignal()
        advanceUntilIdle()
        late.catchUp()
        assertEquals(2, lateServer.count("gomoku_inbox"), "시간이 지나도 받은함은 읽는다(새 신청)")
        assertEquals(0, lateServer.count("gomoku_state"), "서버가 말을 안 받는 시간에 끝난 판을 읽는다")
        // 내가 상대 말을 껐다: 초인종도 안전망도 안 읽는다.
        now = t0
        val (muted, _, mutedServer) = rig { respondWith("gomoku_inbox", inbox); respondWith("gomoku_state", farewell) }
        muted.clock = { now }
        muted.applyState(handPayload(handState(finished = true, chat = emptyList(), chatSeq = 0, myMuted = true)))
        assertTrue(muted.isMuted)
        muted.handleSignal()
        advanceUntilIdle()
        muted.isWindowVisible = true
        muted.lastStateRequestAt = t0
        now = t0.addingTimeInterval(30.0)
        muted.pollTick(now)
        assertEquals(0, mutedServer.count("gomoku_state"), "상대 말을 껐는데 끝인사를 읽으러 간다")
        // 기준선: 같은 순간, 끄지 않은 판은 읽는다.
        now = t0
        val (open, _, openServer) = rig { respondWith("gomoku_inbox", inbox); respondWith("gomoku_state", farewell) }
        open.clock = { now }
        open.applyState(handPayload(handState(finished = true, chat = emptyList(), chatSeq = 0, myMuted = false)))
        open.handleSignal()
        advanceUntilIdle()
        assertEquals(1, openServer.count("gomoku_state"))
        assertEquals(listOf("수고하셨어요"), open.chat.map { it.body })
    }
}
