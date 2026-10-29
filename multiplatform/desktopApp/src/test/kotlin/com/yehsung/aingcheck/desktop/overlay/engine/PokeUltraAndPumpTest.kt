package com.yehsung.aingcheck.desktop.overlay.engine

import com.yehsung.aingcheck.core.rules.text.AingStickerText
import com.yehsung.aingcheck.core.wire.models.PokeKind
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** 찌름·울트라(규약 11·13, 5s·감시) — 맥 UltraPokeOverlayTests·CheckOverlayTests overlayHandleReceivedPokes*. */
class PokeUltraTest {
    @Test fun pokeBubbleTextFormatsSingleAndMultipleNames() {
        assertEquals("민수님이 콕 찔렀어요!", BubbleForm.pokeText(listOf("민수")))
        assertEquals("민수님 외 2명이 콕 찔렀어요!", BubbleForm.pokeText(listOf("민수", "지영", "철수")))
        assertEquals("", BubbleForm.pokeText(emptyList()))
        assertEquals("민수님의 울트라 찌르기!", BubbleForm.ultraText("민수", 0))
        assertEquals("민수님의 울트라 찌르기! (외 1명)", BubbleForm.ultraText("민수", 1))
    }

    @Test fun overlayHandleReceivedPokesShowsBubbleForNonEmptyBatch() {
        val f = Fixture()
        val t = f.working()
        assertFalse(f.d.onPokes(emptyList(), t), "빈 배치 무시")
        assertTrue(f.d.onPokes(listOf(poke("1", "민수")), t))
        assertEquals("민수님이 콕 찔렀어요!", f.d.bubbleAt(t + 5.99)?.text)
        assertNull(f.d.bubbleAt(t + 6.0))
    }

    @Test fun overlayPokePeekPlaysEvenWhenCharacterHidden_forEightSeconds() {
        val f = Fixture()
        f.d.onWorking(false, true, 0.0)
        assertTrue(f.d.onPokes(listOf(poke("1", "민수")), 1.0))
        assertEquals(OverlayMode.Peek, f.d.mode(1.0))
        assertTrue(f.d.availability(1.0).visibleNow)
        f.d.tick(8.99)
        assertEquals(OverlayMode.Peek, f.d.mode(8.99))
        f.d.tick(9.0)
        assertEquals(OverlayMode.Hidden, f.d.mode(9.0))
        assertNull(f.d.bubbleAt(9.0))
    }

    @Test fun w3_06_characterTurnedOffMeansNoPeek_toastInstead() {
        val f = Fixture()
        f.d.onWorking(false, false, 0.0)
        assertFalse(f.d.onPokes(listOf(poke("1", "민수")), 1.0))
        assertEquals(OverlayMode.Hidden, f.d.mode(1.0))
        assertFalse(f.d.availability(1.0).canPeek, "W3-c1 이 토스트를 고르게")
    }

    // 규약 11 — 거부되면 창을 안 띄운다.
    @Test fun rule11_peekRejectedByEngineDoesNotOpenTheWindow() {
        val f = Fixture()
        f.d.onWorking(true, true, 0.0)
        f.d.onWorking(false, true, 10.0) // 작별 commuteEnd(3) 재생 중
        assertFalse(f.d.onPokes(listOf(poke("1", "민수")), 10.1), "동순위 commuteEnd 에 막힌 찌름")
        f.d.tick(10.6)
        assertEquals(OverlayMode.Hidden, f.d.mode(10.6), "peek 창이 열리지 않는다")
    }

    // 규약 11 — 첫 울트라가 배치를 대표(이름·캐릭터·외 N명), 울트라 중 일반 찌름은 삼킨다.
    @Test fun rule11_firstUltraRepresentsTheBatch_andNormalPokesAreSwallowedDuringUltra() {
        val f = Fixture()
        f.sink.characterId = "mine"
        val t = f.working()
        val batch = listOf(poke("1", "가영"), poke("2", "나영", PokeKind.ultra, "robot"), poke("3", "다영", PokeKind.ultra, "jelly"))
        assertTrue(f.d.onPokes(batch, t))
        assertTrue(f.d.isUltraActive)
        assertEquals(OverlayMode.Ultra, f.d.mode(t))
        assertEquals("나영님의 울트라 찌르기! (외 2명)", f.d.bubbleAt(t)?.text)
        assertEquals(BubbleKind.Ultra, f.d.bubbleAt(t)?.kind)
        assertTrue("swap:robot" in f.sink.calls, "찌른 사람 캐릭터")
        assertFalse(f.d.onPokes(listOf(poke("4", "라영")), t + 1), "울트라 중 일반 찌름은 삼킨다")
        assertEquals("나영님의 울트라 찌르기! (외 2명)", f.d.bubbleAt(t + 1)?.text)
    }

    @Test fun ultraWithoutSenderCharacterStillSwapsToAing_andRestoresMine() {
        val f = Fixture()
        f.sink.characterId = "mine"
        val t = f.working()
        f.d.onPokes(listOf(poke("1", "민수", PokeKind.ultra, null)), t)
        assertTrue("swap:null" in f.sink.calls, "★ nil 이어도 반드시 부른다")
        f.d.tick(t + 5.0)
        assertEquals("mine", f.sink.characterId)
    }

    @Test fun ultraPokedDurationIsFiveSeconds_thenRestoresVisibility() {
        val f = Fixture()
        val t = f.working()
        f.d.onPokes(listOf(poke("1", "민수", PokeKind.ultra)), t)
        f.d.tick(t + 4.99)
        assertTrue(f.d.isUltraActive)
        f.d.tick(t + 5.0)
        assertFalse(f.d.isUltraActive)
        assertEquals(OverlayMode.Normal, f.d.mode(t + 5.0))
        assertNull(f.d.activeReaction(t + 5.0))
    }

    @Test fun ultraWatchdogEndsAtStartPlusSix_evenIfTicksStall() {
        val f = Fixture()
        val t = f.working()
        f.d.onPokes(listOf(poke("1", "민수", PokeKind.ultra)), t)
        assertEquals(t + 6.0, f.d.ultraDeadline)
        assertFalse(f.d.enforceUltraDeadline(t + 5.99))
        assertTrue(f.d.enforceUltraDeadline(t + 6.0))
        val g = Fixture()
        g.d.onWorking(false, true, 0.0)
        g.d.onPokes(listOf(poke("1", "민수", PokeKind.ultra)), 1.0)
        g.d.tick(31.0) // 멈춘 뒤 늦게 온 tick
        assertFalse(g.d.isUltraActive)
        assertEquals(OverlayMode.Hidden, g.d.mode(31.0), "숨김에서 격발됐으면 다시 숨김")
        assertNull(g.d.bubbleAt(31.0))
    }

    // 규약 13 — 갱신은 복원 프레임을 다시 잡지 않는다.
    @Test fun rule13_refreshKeepsTheOriginalRestoreFrame_andExtendsTheDeadline() {
        val f = Fixture()
        val t = f.working()
        val original = OverlayRect(1700.0, 30.0, 140.0, 170.0)
        f.d.onSurfaceFrame(original)
        f.d.onPokes(listOf(poke("1", "민수", PokeKind.ultra)), t)
        assertIs<FrameIntent.UltraCover>(f.d.view(t).frame)
        f.d.onSurfaceFrame(Mon.primary.bounds) // 표면이 덮은 프레임을 알린다
        f.d.onPokes(listOf(poke("2", "지영", PokeKind.ultra)), t + 3)
        f.d.tick(t + 5.0)
        assertTrue(f.d.isUltraActive, "갱신이 5초를 다시 센다")
        f.d.tick(t + 8.0)
        val intent = f.d.view(t + 8.0).frame
        assertIs<FrameIntent.Restore>(intent)
        assertEquals(original, intent.frame)
    }

    @Test fun rule13_restoreFallsBackToDefaultWhenTheMonitorWasUnplugged() {
        val f = Fixture()
        val t = f.working()
        f.d.onSurfaceFrame(OverlayRect(3000.0, 40.0, 140.0, 170.0)) // DISPLAY2 위
        f.d.onPokes(listOf(poke("1", "민수", PokeKind.ultra)), t)
        f.d.onMonitors(listOf(Mon.primary))
        f.d.tick(t + 5.0)
        assertIs<FrameIntent.Default>(f.d.view(t + 5.0).frame)
    }

    @Test fun workStopDuringUltraEndsItWithoutRestoringVisibility_thenFarewell() {
        val f = Fixture()
        val t = f.working()
        f.d.onPokes(listOf(poke("1", "민수", PokeKind.ultra)), t)
        f.d.onWorking(false, true, t + 1)
        assertFalse(f.d.isUltraActive)
        assertEquals(OverlayMode.Farewell, f.d.mode(t + 1))
    }
}

/** 메시지 펌프(규약 9·10) — 맥 overlayMessage* 시나리오. */
class MessagePumpTest {
    @Test fun overlayShowsQueuedMessageAsPokeBubbleAndConsumesOne_thenDrainsInArrivalOrder() {
        val f = Fixture()
        val t = f.working()
        f.inbox.add("m1", "민수", "안녕")
        f.inbox.add("m2", "지영", "점심?")
        f.d.onMessagesChanged(t)
        assertEquals(1, f.inbox.consumed)
        assertEquals("민수님: 안녕", f.d.bubbleAt(t)?.text)
        for (s in 1..5) f.d.tick(t + s)
        assertEquals(1, f.inbox.consumed, "말풍선 표시 중엔 다음 것을 소비하지 않는다(덮어쓰기 금지)")
        f.d.tick(t + 6)
        assertEquals(2, f.inbox.consumed)
        assertEquals("지영님: 점심?", f.d.bubbleAt(t + 6)?.text)
        f.d.tick(t + 13)
        f.d.tick(t + 14)
        assertEquals(2, f.inbox.consumed)
    }

    // 규약 10 — 못 띄우면 소비하지 않는다.
    @Test fun rule10_messageWaitsDuringUltraBubbleOrPlayback_butNotDuringSleep() {
        val f = Fixture()
        val t = f.working()
        f.inbox.add("m1", "민수", "안녕")
        f.d.request(ReactionKind.Milestone, t) // 말 없는 재생
        assertFalse(f.d.showCurrentMessage(t + 0.1))
        f.d.onPokes(listOf(poke("u", "철수", PokeKind.ultra)), t + 2)
        assertFalse(f.d.showCurrentMessage(t + 3))
        assertEquals(0, f.inbox.consumed)
        f.d.tick(t + 7)
        f.d.request(ReactionKind.Drowsy, t + 20)
        assertTrue(f.d.isSleeping)
        assertTrue(f.d.showCurrentMessage(t + 21), "자는 중은 막지 않는다(깨우며 띄운다)")
        assertEquals(1, f.inbox.consumed)
        assertFalse(f.d.isSleeping)
    }

    @Test fun rule10_hiddenWithCharacterOffDoesNotConsume_hiddenWithCharacterOnPeeks() {
        val off = Fixture()
        off.d.onWorking(false, false, 0.0)
        off.inbox.add("m1", "민수", "안녕")
        off.d.onMessagesChanged(1.0)
        assertEquals(0, off.inbox.consumed)
        val on = Fixture()
        on.d.onWorking(false, true, 0.0)
        on.inbox.add("m1", "민수", "안녕")
        on.d.onMessagesChanged(1.0)
        assertEquals(1, on.inbox.consumed)
        assertEquals(OverlayMode.Peek, on.d.mode(1.0))
    }

    // ★ 규약 9 — 이모티콘 변환은 문구 함수 안에서.
    @Test fun rule09_stickerPreviewHappensInsideTheTextFunction() {
        val f = Fixture()
        val t = f.working()
        f.inbox.add("m1", "민수", "[아잉:하트]")
        f.d.onMessagesChanged(t)
        assertEquals("민수님: " + AingStickerText.preview("[아잉:하트]"), f.d.bubbleAt(t)?.text)
        assertEquals("민수님: 아잉이 하트", BubbleForm.messageBubble("민수", "[아잉:하트]", f.measure).text)
    }

    @Test fun arrivalBubbleCarriesSenderAndOpensMessagesOnClick() {
        val f = Fixture()
        val t = f.working()
        f.inbox.add("m1", "민수", "가".repeat(41), from = "user-9")
        f.d.onMessagesChanged(t)
        val b = f.d.bubbleAt(t)!!
        assertEquals("✉️ 민수님 메시지 도착!", b.text)
        assertEquals(BubbleKind.Arrival("user-9"), b.kind)
        val c = Mon.primary.work.right - 100
        f.d.onPointer(PointerKind.DOWN, OverlayPoint(c, 60.0), HitTarget.Bubble, t + 1)
        val out = f.d.onPointer(PointerKind.UP, OverlayPoint(c, 60.0), HitTarget.Bubble, t + 1.1)
        assertEquals(ClickAction.OpenMessages("user-9"), out.click)
    }
}

/** 대결 말풍선 큐(규약 10 + id 중복 제거 + 만료/살아 있음) — 맥 오목·체스·테트리스 세 벌을 하나로. */
class DuelBubbleQueueTest {
    private fun inv(id: String, game: DuelGame = DuelGame.GOMOKU, exp: Double = 1e9) = DuelInvite(game, id, "민수", 5, exp)

    @Test fun inviteShowsAsClickableBubble_andDedupesById() {
        val f = Fixture()
        val t = f.working()
        f.d.onPokes(listOf(poke("p", "지영")), t) // 말풍선이 바빠 큐에 쌓이게
        f.d.enqueueDuelInvite(inv("a"), t)
        f.d.enqueueDuelInvite(inv("a"), t + 0.1)
        assertEquals(1, f.d.pendingInvitesForTest(DuelGame.GOMOKU).size, "같은 id 는 한 번만")
        f.d.tick(t + 6.5)
        assertEquals(BubbleKind.Invite(DuelGame.GOMOKU, "a"), f.d.bubbleAt(t + 6.5)?.kind)
        val c = Mon.primary.work.right - 100
        f.d.onPointer(PointerKind.DOWN, OverlayPoint(c, 60.0), HitTarget.Bubble, t + 7)
        assertEquals(ClickAction.OpenDuel(DuelGame.GOMOKU, "a"), f.d.onPointer(PointerKind.UP, OverlayPoint(c, 60.0), HitTarget.Bubble, t + 7.1).click)
    }

    @Test fun rule10_inviteWaitsWhileBubbleIsShown_thenShowsOnALaterTick() {
        val f = Fixture()
        val t = f.working()
        f.d.onPokes(listOf(poke("p", "지영")), t)
        f.d.enqueueDuelInvite(inv("a"), t + 0.5)
        assertEquals(1, f.d.pendingInvitesForTest(DuelGame.GOMOKU).size, "못 띄우면 큐에 남는다")
        f.d.tick(t + 1.5); f.d.tick(t + 2.5); f.d.tick(t + 3.5); f.d.tick(t + 4.5); f.d.tick(t + 5.5)
        assertEquals(1, f.d.pendingInvitesForTest(DuelGame.GOMOKU).size)
        f.d.tick(t + 6.5)
        assertTrue(f.d.pendingInvitesForTest(DuelGame.GOMOKU).isEmpty())
        assertEquals(BubbleKind.Invite(DuelGame.GOMOKU, "a"), f.d.bubbleAt(t + 6.5)?.kind)
    }

    @Test fun expiredOrNoLongerAliveInvitesAreDropped() {
        val f = Fixture()
        val t = f.working()
        f.d.onPokes(listOf(poke("p", "지영")), t)
        f.d.enqueueDuelInvite(inv("old", exp = t + 2), t)
        f.d.enqueueDuelInvite(inv("gone", DuelGame.CHESS), t)
        f.d.onDuelFacts(DuelGame.CHESS, DuelFacts(aliveInviteIds = emptySet()))
        f.d.tick(t + 6.5)
        assertTrue(f.d.pendingInvitesForTest(DuelGame.GOMOKU).isEmpty())
        assertTrue(f.d.pendingInvitesForTest(DuelGame.CHESS).isEmpty())
        assertNull(f.d.bubbleAt(t + 6.5), "만료·사라진 신청은 띄우지 않는다")
    }

    @Test fun attentionShowsOnlyWhileCurrent() {
        val f = Fixture()
        val t = f.working()
        val a = DuelAttention(DuelGame.CHESS, "m1", DuelAttentionKind.MY_TURN, "민수", 7)
        f.d.onDuelFacts(DuelGame.CHESS, DuelFacts(windowVisible = true, match = DuelMatchFact("m1", false, true, 7)))
        f.d.enqueueDuelAttention(a, t)
        assertNull(f.d.bubbleAt(t), "창이 열려 있으면 버린다")
        f.d.onDuelFacts(DuelGame.CHESS, DuelFacts(match = DuelMatchFact("m1", false, true, 8)))
        f.d.enqueueDuelAttention(a, t + 1)
        assertNull(f.d.bubbleAt(t + 1), "수가 바뀌었으면 낡은 알림")
        f.d.onDuelFacts(DuelGame.CHESS, DuelFacts(match = DuelMatchFact("m1", false, true, 7)))
        f.d.enqueueDuelAttention(a, t + 2)
        assertEquals("민수님이 뒀어요 · 체스 내 차례예요", f.d.bubbleAt(t + 2)?.text)
        assertEquals(BubbleKind.Invite(DuelGame.CHESS, "m1"), f.d.bubbleAt(t + 2)?.kind)
    }

    @Test fun clearDuelsEmptiesQueueAndDisarmsTheShownBubble() {
        val f = Fixture()
        val t = f.working()
        f.d.enqueueDuelInvite(inv("a", DuelGame.TETRIS), t)
        f.d.enqueueDuelInvite(inv("b", DuelGame.TETRIS), t)
        f.d.clearDuels(DuelGame.TETRIS)
        assertTrue(f.d.pendingInvitesForTest(DuelGame.TETRIS).isEmpty())
        assertEquals(BubbleKind.Normal, f.d.bubbleAt(t)?.kind, "계정 전환 뒤엔 눌러도 그 판을 열지 않는다")
    }

    @Test fun duelTextsShrinkToFitTheCapsule() {
        val m = FakeMeasure()
        val slim = FakeMeasure(hangul = 7.0)
        assertEquals("민수님이 오목 대결을 신청했어요 · 루비 5", BubbleForm.duelInviteText(DuelGame.GOMOKU, "민수", 5, slim))
        assertEquals("민수님의 테트리스 신청 · 루비 10", BubbleForm.duelInviteText(DuelGame.TETRIS, "민수", 10, m))
        val tiny = FakeMeasure(hangul = 30.0, latin = 30.0)
        assertEquals("체스 대결 신청 · 루비 3", BubbleForm.duelInviteText(DuelGame.CHESS, "민수", 3, tiny))
        assertEquals("대국이 시작됐어요 · 내 차례예요",
            BubbleForm.duelAttentionText(DuelAttention(DuelGame.GOMOKU, "m", DuelAttentionKind.MATCH_STARTED, "민수", 0), m))
        assertEquals("민수님과 테트리스 대결이 시작됐어요",
            BubbleForm.duelAttentionText(DuelAttention(DuelGame.TETRIS, "m", DuelAttentionKind.MATCH_STARTED, "민수", 0), m))
    }
}
