package com.yehsung.aingcheck.desktop.overlay.engine

import com.yehsung.aingcheck.character.player.WakeKind
import com.yehsung.aingcheck.core.wire.models.PokeKind
import com.yehsung.aingcheck.desktop.shellapi.OverlayAvailability
import com.yehsung.aingcheck.feature.desktop.socialapi.MessageBubbleInbox
import com.yehsung.aingcheck.feature.desktop.socialapi.ReceivedPoke
import com.yehsung.aingcheck.feature.desktop.work.WorkEvent
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import kotlin.random.Random

/**
 * Windows 오버레이 엔진(순수) — 맥 ReactionEngine(CheckOverlayReactions.swift :899-1208) + CheckOverlayController 의 판정
 * (CheckOverlayWindow.swift :512-2100)을 한 클래스로. **시계를 읽지 않는다**: 타이머(작별·peek·울트라·낮잠·졸기·깜빡·펌프)는
 * 전부 `tick(now)` 에서 마감 시각을 비교한다. 창·그리기는 b2, 보드는 b3(BoardHost), 조립은 P3.
 *
 * 맥 원본 판정 13개(★·⚠️) — overlay.md §2 번호. 시험 이름에 같은 번호를 남긴다.
 */
class OverlayDirector(
    private val sink: CharacterSink,
    private val measure: BubbleTextMeasure,
    private val inbox: MessageBubbleInbox = MessageBubbleInbox.Empty,
    private val board: BoardHost = BoardHost.None,
    private val random: Random = Random.Default,
) : OverlayInputs {

    enum class EngineState { IDLE, PLAYING, SLEEPING }

    private data class CommuteOverride(val text: String, val seconds: Double, val setAt: Double)

    private class DuelLane {
        val invites = ArrayList<DuelInvite>()
        var pendingAttention: DuelAttention? = null
        var facts = DuelFacts()
        var pumpAt: Double? = null
        fun hasWork(): Boolean = invites.isNotEmpty() || pendingAttention != null
    }

    // ── 리액션 엔진 상태(맥 ReactionEngine) ──
    private var activeKind: ReactionKind? = null
    private var activeStartedAt = 0.0
    private var activeUntil = Double.NEGATIVE_INFINITY
    private var lastHitAt: Double? = null
    private var sleeping = false
    private var napEndsAt: Double? = null
    private var bubble: OverlayBubble? = null
    private val particles = ArrayList<ParticleStart>()
    private var renderSuspended = false
    private var suspendedAt: Double? = null
    private var commuteOverride: CommuteOverride? = null

    // ── 컨트롤러 상태 ──
    private var overlayEnabled = false
    private var shouldBeVisible = false
    private var farewellUntil: Double? = null
    private var peekUntil: Double? = null
    private var nextDrowsyAt: Double? = null
    private var nextBlinkAt: Double? = null
    private var messagePumpAt: Double? = null
    private var pendingUpdateVersion: String? = null
    /** 말풍선을 이미 띄운 업데이트 버전(버전당 1회). 영속은 조립이 DesktopKeyValueStore 로 읽고 쓴다. */
    var shownUpdateVersion: String? = null
    private val renderSuspendReasons = LinkedHashSet<RenderSuspendReason>()
    private var monitors: List<MonitorInfo> = emptyList()
    private var surfaceFrame: OverlayRect? = null
    private var frameSeq = 0
    private var frameIntent: FrameIntent = FrameIntent.Default(0)

    // ── 울트라 ──
    private var ultraActive = false
    private var ultraStartedAt = 0.0
    private var ultraRestoreFrame: OverlayRect? = null
    private var ultraStashedCharacter: String? = null

    // ── 포인터 ──
    private var dragCandidate = false
    private var didDrag = false
    private var dragAnchor = OverlayPoint(0.0, 0.0)
    private var originAtDragStart = OverlayPoint(0.0, 0.0)
    private val hysteresis = DragFacingHysteresis()
    private var facing = 0
    private var walking = false

    private val duels: Map<DuelGame, DuelLane> = DuelGame.entries.associateWith { DuelLane() }
    private val greeting = TeammateGreetingDetector()

    // ───────────────────────── 읽기(시험·조립) ─────────────────────────

    val isUltraActive: Boolean get() = ultraActive
    val isSleeping: Boolean get() = sleeping
    val isVisibleWhileWorking: Boolean get() = shouldBeVisible
    internal val nextDrowsyAtForTest: Double? get() = nextDrowsyAt
    internal val napEndsAtForTest: Double? get() = napEndsAt
    internal val nextBlinkAtForTest: Double? get() = nextBlinkAt
    internal fun pendingInvitesForTest(game: DuelGame): List<DuelInvite> = duels.getValue(game).invites.toList()

    /** 울트라 감시 마감(맥 ultraDeadline = 시작 + 5 + 1). */
    val ultraDeadline: Double? get() = if (ultraActive) ultraStartedAt + OverlayTimings.ULTRA_S + OverlayTimings.ULTRA_WATCHDOG_GRACE_S else null

    fun state(now: Double): EngineState {
        expire(now)
        return when {
            sleeping -> EngineState.SLEEPING
            activeKind != null -> EngineState.PLAYING
            else -> EngineState.IDLE
        }
    }

    fun activeReaction(now: Double): ReactionKind? { expire(now); return activeKind }

    fun bubbleAt(now: Double): OverlayBubble? { expireBubble(now); return bubble }

    fun mode(now: Double): OverlayMode = when {
        ultraActive -> OverlayMode.Ultra
        shouldBeVisible -> OverlayMode.Normal
        farewellUntil != null -> OverlayMode.Farewell
        peekUntil != null -> OverlayMode.Peek
        else -> OverlayMode.Hidden
    }

    override fun view(now: Double): OverlayView {
        expire(now); expireBubble(now); pruneParticles(now)
        val active = activeKind
        return OverlayView(
            mode = mode(now),
            characterId = sink.currentCharacterId,
            bubble = bubble,
            activeReaction = active?.motionName,
            reactionStartedAt = if (active != null) activeStartedAt else null,
            sleeping = sleeping,
            facing = facing,
            walking = walking,
            particles = particles.toList(),
            frame = frameIntent,
            renderSuspended = renderSuspended,
        )
    }

    /** I-7 — canPeek = 사용자가 캐릭터를 켜 둠(W-3 #6: 켜져 있으면 8초 peek, 끈 경우에만 토스트). */
    override fun availability(now: Double): OverlayAvailability =
        OverlayAvailability(visibleNow = mode(now) != OverlayMode.Hidden, canPeek = overlayEnabled)

    // ───────────────────────── 리액션 중재(맥 request :915) ─────────────────────────

    /** 리액션 요청. 수용되면 true. 맥 ReactionEngine.request 와 같은 순서(자는 중 가지 → wake 거절 → 쿨다운 → 중재 → 인터럽트). */
    fun request(kind: ReactionKind, now: Double, bubbleKind: BubbleKind = BubbleKind.Normal): Boolean {
        expire(now)
        if (sleeping) {
            when (ReactionRules.sleepBranch(kind)) { // ⚠️ 규약 1
                ReactionRules.SleepBranch.IGNORE -> return false
                ReactionRules.SleepBranch.STARTLE -> { beginWake(now); return true }
                ReactionRules.SleepBranch.END_SLEEP_THEN_PLAY -> endSleep()
            }
        }
        if (kind == ReactionKind.Wake) return false
        if (kind == ReactionKind.Hit) {
            val last = lastHitAt
            if (last != null && now - last < ReactionRules.HIT_COOLDOWN_S) return false
        }
        val active = activeKind
        if (active != null && !ReactionRules.incomingWins(active, kind)) return false // 규약 2·3
        if (active != null) interruptCurrent(now)
        if (kind == ReactionKind.Drowsy) {
            if (renderSuspended) return false // 규약 5 — 엔진이 최종 문
            beginSleep(now)
            return true
        }
        if (kind == ReactionKind.Hit) lastHitAt = now
        activeKind = kind
        activeStartedAt = now
        activeUntil = now + kind.duration
        perform(kind, now, bubbleKind)
        return true
    }

    private fun expire(now: Double) {
        if (activeKind != null && now >= activeUntil) activeKind = null
    }

    private fun expireBubble(now: Double) {
        val b = bubble ?: return
        if (now >= b.until) bubble = null
    }

    private fun bubbleActive(now: Double): Boolean { expireBubble(now); return bubble != null }

    private fun pruneParticles(now: Double) {
        particles.removeAll { now - it.startedAt > it.cue.maxLifetimeS }
    }

    /** ⚠️ 규약 4 — 인터럽트는 일시 파티클을 **전부** 걷는다(ParticleCue 열거형 하나 — 이름 목록을 따로 두지 않는다). */
    private fun interruptCurrent(now: Double) {
        sink.interrupt(now)
        particles.clear()
    }

    private fun showBubble(text: String, seconds: Double, kind: BubbleKind, now: Double) {
        bubble = OverlayBubble(text, kind, now, now + seconds)
    }

    private fun perform(kind: ReactionKind, now: Double, bubbleKind: BubbleKind) {
        if (kind != ReactionKind.Drowsy && kind != ReactionKind.Wake) sink.play(kind.motionName, now)
        ReactionRules.particle(kind)?.let { particles += ParticleStart(it, now) }
        val seconds = ReactionRules.bubbleSeconds(kind)
        when (kind) {
            ReactionKind.CommuteStart -> {
                // 규약 7 — 오버라이드는 어느 길이든 소비된다. 10s 넘은 것은 평소 문구로.
                val o = commuteOverride
                commuteOverride = null
                if (o != null && now - o.setAt <= ReactionRules.COMMUTE_START_OVERRIDE_LIFETIME_S) {
                    showBubble(o.text, o.seconds, BubbleKind.Normal, now)
                } else {
                    showBubble(ReactionRules.COMMUTE_START_TEXT, ReactionRules.COMMUTE_START_BUBBLE_S, BubbleKind.Normal, now)
                }
            }
            ReactionKind.Hit -> showBubble(ReactionRules.HIT_TEXT, seconds!!, bubbleKind, now)
            ReactionKind.CommuteEnd -> showBubble(ReactionRules.COMMUTE_END_TEXT, seconds!!, bubbleKind, now)
            is ReactionKind.Greeting -> showBubble(ReactionRules.greetingText(kind.name), seconds!!, bubbleKind, now)
            is ReactionKind.Poked -> showBubble(kind.bubbleText, seconds!!, bubbleKind, now)
            is ReactionKind.UltraPoked -> showBubble(kind.bubbleText, seconds!!, BubbleKind.Ultra, now)
            ReactionKind.GoalAchieved -> showBubble(ReactionRules.GOAL_TEXT, seconds!!, bubbleKind, now)
            ReactionKind.UltraCharged -> showBubble(ReactionRules.MISSION_REWARD_TEXT, seconds!!, bubbleKind, now)
            is ReactionKind.RubyReward -> showBubble(ReactionRules.rubyRewardText(kind.amount), seconds!!, bubbleKind, now)
            ReactionKind.Milestone, ReactionKind.Drowsy, ReactionKind.Wake -> Unit
        }
    }

    private fun beginSleep(now: Double) {
        sleeping = true
        activeKind = null
        sink.beginSleep(now)
        particles += ParticleStart(ParticleCue.ZZZ, now)
        napEndsAt = now + OverlaySchedules.nextNapDuration(random)
    }

    /** 규약 6 — endSleep 은 낮잠 타이머까지 끊는다(옛 타이머가 다음 잠을 깨우지 않게). */
    private fun endSleep() {
        sleeping = false
        napEndsAt = null
        particles.clear()
    }

    private fun beginWake(now: Double) {
        endSleep()
        activeKind = ReactionKind.Wake
        activeStartedAt = now
        activeUntil = now + ReactionKind.Wake.duration
        sink.wake(WakeKind.startled, now)
        showBubble(ReactionRules.WAKE_TEXT, ReactionRules.WAKE_BUBBLE_S, BubbleKind.Normal, now)
    }

    /** 낮잠 끝 조용한 기상. 규약 5 — 렌더 정지 중이면 애니메이션 없이 스냅(interrupt). */
    fun wakeQuietly(now: Double) {
        if (!sleeping) return
        endSleep()
        if (renderSuspended) sink.interrupt(now) else sink.wake(WakeKind.quiet, now)
    }

    fun cancelActiveReaction(now: Double) {
        if (activeKind == null) return
        interruptCurrent(now)
        activeKind = null
        activeUntil = Double.NEGATIVE_INFINITY
    }

    private fun stopSleeping(now: Double) {
        if (!sleeping) return
        endSleep()
        sink.interrupt(now)
    }

    private fun setRenderSuspended(value: Boolean, now: Double) {
        if (renderSuspended == value) return
        renderSuspended = value
        sink.setSuspended(value, now)
        if (value) {
            suspendedAt = now
        } else {
            // 맥 reconcileAfterResume(:1457): 정지 사이에 끝난 리액션의 잔여 자세·파티클을 걷는다.
            val since = suspendedAt
            suspendedAt = null
            expire(now)
            val endedWhileSuspended = since != null && activeUntil > since && activeUntil <= now
            if (activeKind == null && !sleeping && (endedWhileSuspended || particles.isNotEmpty())) interruptCurrent(now)
        }
    }

    // ───────────────────────── 근무 전이(맥 updateWorking :512) ─────────────────────────

    override fun onWorking(isWorking: Boolean, overlayEnabled: Boolean, now: Double, startOrigin: WorkStartOrigin?) {
        this.overlayEnabled = overlayEnabled
        val visible = isWorking && overlayEnabled
        val wasVisible = shouldBeVisible
        // 넛지 자동 시작 8s 안내(I-8) — 맥 nudgeAutoStart(:660)는 캐릭터가 켜져 있을 때만 오버라이드를 건다.
        if (visible && !wasVisible && startOrigin == WorkStartOrigin.NUDGE && commuteOverride == null) {
            setCommuteStartOverride(OverlayTimings.NUDGE_AUTO_START_TEXT, OverlayTimings.NUDGE_AUTO_START_BUBBLE_S, now)
        }
        // StateFlow 는 다른 칸이 바뀌어도 다시 낸다 — 맥 updateWorking 은 변화 때만 불리므로 같은 값은 무시한다.
        if (visible == wasVisible) return
        shouldBeVisible = visible
        peekUntil = null
        if (ultraActive) endUltra(restoresVisibility = false, now = now)
        if (visible) {
            farewellUntil = null
            frameIntent = FrameIntent.Default(++frameSeq)
            if (nextDrowsyAt == null) nextDrowsyAt = now + OverlaySchedules.nextDrowsyInterval(random)
            if (nextBlinkAt == null) nextBlinkAt = now + OverlaySchedules.nextBlinkInterval(random)
            request(ReactionKind.CommuteStart, now)
        } else {
            nextDrowsyAt = null
            nextBlinkAt = null
            bubble = null
            if (wasVisible) {
                request(ReactionKind.CommuteEnd, now)
                farewellUntil = now + OverlayTimings.FAREWELL_HIDE_S
            } else {
                stopSleeping(now)
            }
        }
    }

    override fun setCommuteStartOverride(text: String, seconds: Double, now: Double) {
        commuteOverride = CommuteOverride(text, seconds, now)
    }

    override fun onWorkEvent(event: WorkEvent, now: Double) {
        when (event) {
            is WorkEvent.Milestone -> onReaction(ReactionKind.Milestone, now)
            // ★ 규약 8 — 팀 주간 목표는 보상 길(peek)이 아니라 가시 게이트 길이다.
            WorkEvent.TeamGoalAchieved -> onReaction(ReactionKind.GoalAchieved, now)
            WorkEvent.NudgeStarted ->
                if (overlayEnabled && !shouldBeVisible) {
                    setCommuteStartOverride(OverlayTimings.NUDGE_AUTO_START_TEXT, OverlayTimings.NUDGE_AUTO_START_BUBBLE_S, now)
                }
            // 자동 마감은 근무 스냅숏(onWorking false)으로 온다. 랩 보상 말풍선은 UltraChargedSink → onReward 길.
            is WorkEvent.AutoClosed, is WorkEvent.LapCelebrated -> Unit
        }
    }

    // ───────────────────────── 보상·가시 게이트·찌름 ─────────────────────────

    private fun isShowing(): Boolean = shouldBeVisible && !ultraActive

    override fun onReaction(kind: ReactionKind, now: Double): Boolean {
        if (!shouldBeVisible) return false
        return request(kind, now)
    }

    /** 맥 presentReward(:1131) — 화이트리스트 없음(규약 8: 무엇을 보낼지는 생산자). */
    override fun onReward(kind: ReactionKind, now: Double): Boolean {
        if (ultraActive) return false
        return if (isShowing()) request(kind, now) else beginPeek(kind, now)
    }

    /**
     * ★ 맥 beginPeek(:1990) — **엔진에 먼저 묻고 수용됐을 때만** 창을 띄운다(규약 11).
     * W-3 #6 — 사용자가 캐릭터를 끈 경우엔 peek 하지 않는다(false → W3-c1 이 토스트).
     */
    private fun beginPeek(kind: ReactionKind, now: Double, bubbleKind: BubbleKind = BubbleKind.Normal): Boolean {
        if (!overlayEnabled) return false
        if (!request(kind, now, bubbleKind)) return false
        peekUntil = now + OverlayTimings.PEEK_S
        frameIntent = FrameIntent.Default(++frameSeq)
        return true
    }

    /**
     * 규약 11 — 울트라가 하나라도 있으면 **첫 울트라**가 배치를 대표(이름·찌른 사람 캐릭터·"(외 N명)"),
     * 울트라 중 일반 찌름은 삼킨다, 숨김이면 peek 8s.
     */
    override fun onPokes(batch: List<ReceivedPoke>, now: Double): Boolean {
        if (batch.isEmpty()) return false
        val ultra = batch.firstOrNull { it.kind == PokeKind.ultra }
        if (ultra != null) {
            beginUltra(BubbleForm.ultraText(ultra.fromName, batch.size - 1), ultra.fromCharacterID, now)
            return true
        }
        if (ultraActive) return false
        val text = BubbleForm.pokeText(batch.map { it.fromName })
        return if (isShowing()) request(ReactionKind.Poked(text), now) else beginPeek(ReactionKind.Poked(text), now)
    }

    override fun onTeam(members: List<TeamPresence>, selfId: String?, now: Double) {
        for (name in greeting.detect(members, selfId, now)) onReaction(ReactionKind.Greeting(name), now)
    }

    override fun onUpdateAvailable(version: String, now: Double): Boolean {
        pendingUpdateVersion = version
        return showUpdateBubbleIfNeeded(now)
    }

    /** 버전당 1회, 보이고 한가할 때만(맥 :1062). 졸기 주기마다 다시 시도한다. */
    private fun showUpdateBubbleIfNeeded(now: Double): Boolean {
        val version = pendingUpdateVersion ?: return false
        if (!shouldBeVisible || ultraActive || state(now) != EngineState.IDLE) return false
        if (shownUpdateVersion == version) return false
        shownUpdateVersion = version
        showBubble(OverlayTimings.UPDATE_BUBBLE_TEXT, OverlayTimings.UPDATE_BUBBLE_S, BubbleKind.Normal, now)
        return true
    }

    // ───────────────────────── 울트라(맥 :1720-1958) ─────────────────────────

    private fun beginUltra(text: String, characterId: String?, now: Double) {
        val isRefresh = ultraActive
        peekUntil = null
        farewellUntil = null
        if (dragCandidate) { dragCandidate = false; didDrag = false; walking = false; hysteresis.reset() }
        if (!isRefresh) {
            // 규약 13 — 복원 프레임은 첫 격발에서만 잡는다(갱신은 다시 잡지 않는다).
            ultraRestoreFrame = surfaceFrame
            ultraActive = true
            ultraStashedCharacter = sink.currentCharacterId
            // ★ id 가 null 이어도 반드시 부른다 — 보낸 사람이 캐릭터를 안 골랐으면 아잉이다(내 캐릭터가 아니다).
            sink.swapCharacter(characterId, now)
            facing = 0
            frameIntent = FrameIntent.UltraCover(++frameSeq)
        }
        ultraStartedAt = now
        request(ReactionKind.UltraPoked(text), now)
    }

    /** 감시: 마감(시작+6)을 넘긴 tick 이 오면 반드시 끝낸다(맥 enforceUltraDeadline :1887). */
    fun enforceUltraDeadline(now: Double): Boolean {
        val deadline = ultraDeadline ?: return false
        if (now < deadline) return false
        endUltra(restoresVisibility = true, now = now)
        return true
    }

    private fun endUltra(restoresVisibility: Boolean, now: Double) {
        if (!ultraActive) return
        ultraActive = false
        ultraStashedCharacter?.let { sink.swapCharacter(it, now) }
        ultraStashedCharacter = null
        cancelActiveReaction(now)
        val restore = ultraRestoreFrame
        ultraRestoreFrame = null
        // 규약 13 — 원래 프레임이 어느 모니터와도 안 겹치면(5초 사이 모니터가 빠짐) 기본 자리로.
        frameIntent = if (restore != null && OverlayGeometry.canRestore(restore, monitors)) {
            FrameIntent.Restore(restore, ++frameSeq)
        } else {
            FrameIntent.Default(++frameSeq)
        }
        if (!restoresVisibility) return
        if (!shouldBeVisible) bubble = null
    }

    // ───────────────────────── 메시지·대결 펌프(규약 10) ─────────────────────────

    override fun onMessagesChanged(now: Double) {
        if (messagePumpAt != null || inbox.current == null) return
        showCurrentMessage(now)
        messagePumpAt = now + OverlayTimings.PUMP_TICK_S
    }

    /** 규약 10 — 못 띄우면 소비하지 않는다(울트라 중·말풍선 표시 중·재생 중이면 물러남, **자는 중은 막지 않음**). */
    fun showCurrentMessage(now: Double): Boolean {
        val msg = inbox.current ?: return false
        if (ultraActive || bubbleActive(now)) return false
        if (state(now) == EngineState.PLAYING) return false
        val form = BubbleForm.messageBubble(msg.fromName, msg.body, measure) // ★ 규약 9 — 변환은 문구 함수 안
        val kind: BubbleKind = if (form is BubbleForm.Form.Arrival) BubbleKind.Arrival(msg.fromUserID) else BubbleKind.Normal
        val reaction = ReactionKind.Poked(form.text)
        val ok = if (isShowing()) request(reaction, now, kind) else beginPeek(reaction, now, kind)
        if (!ok) return false
        inbox.consumeCurrent()
        return true
    }

    override fun enqueueDuelInvite(invite: DuelInvite, now: Double) {
        val lane = duels.getValue(invite.game)
        if (lane.invites.any { it.id == invite.id }) return // 규약 10 — id 중복 제거
        lane.invites += invite
        lane.facts = lane.facts.copy(aliveInviteIds = lane.facts.aliveInviteIds + invite.id)
        startDuelPump(invite.game, now)
    }

    override fun enqueueDuelAttention(attention: DuelAttention, now: Double) {
        val lane = duels.getValue(attention.game)
        lane.pendingAttention = attention
        if (lane.facts.match == null) {
            lane.facts = lane.facts.copy(match = DuelMatchFact(attention.matchId, finished = false, myTurn = true, moveCount = attention.moveCount))
        }
        startDuelPump(attention.game, now)
    }

    override fun onDuelFacts(game: DuelGame, facts: DuelFacts) {
        duels.getValue(game).facts = facts
    }

    override fun clearDuels(game: DuelGame) {
        val lane = duels.getValue(game)
        lane.invites.clear()
        lane.pendingAttention = null
        lane.pumpAt = null
        val b = bubble
        if (b != null && b.kind is BubbleKind.Invite && (b.kind as BubbleKind.Invite).game == game) bubble = b.copy(kind = BubbleKind.Normal)
    }

    override fun onSignedOut() {
        greeting.reset()
        DuelGame.entries.forEach(::clearDuels)
    }

    private fun startDuelPump(game: DuelGame, now: Double) {
        val lane = duels.getValue(game)
        if (lane.pumpAt != null) return
        pumpDuel(game, now)
        lane.pumpAt = if (lane.hasWork()) now + OverlayTimings.PUMP_TICK_S else null
    }

    private fun pumpDuel(game: DuelGame, now: Double) {
        if (!showPendingAttention(game, now)) showNextInvite(game, now)
    }

    /** 규약 10 — 만료·살아 있지 않은 신청은 거른 뒤, 못 띄우면 큐에 남긴다. */
    fun showNextInvite(game: DuelGame, now: Double): Boolean {
        val lane = duels.getValue(game)
        val alive = lane.facts.aliveInviteIds
        lane.invites.removeAll { it.expiresAt <= now || it.id !in alive }
        val invite = lane.invites.firstOrNull() ?: return false
        if (ultraActive || bubbleActive(now)) return false
        if (state(now) == EngineState.PLAYING) return false
        val text = BubbleForm.duelInviteText(game, invite.peerName, invite.stake, measure)
        val kind = BubbleKind.Invite(game, invite.id)
        val reaction = ReactionKind.Poked(text)
        val ok = if (isShowing()) request(reaction, now, kind) else beginPeek(reaction, now, kind)
        if (!ok) return false
        lane.invites.removeAt(0)
        return true
    }

    fun showPendingAttention(game: DuelGame, now: Double): Boolean {
        val lane = duels.getValue(game)
        val attention = lane.pendingAttention ?: return false
        if (!attentionIsCurrent(attention, lane.facts)) { lane.pendingAttention = null; return false }
        if (ultraActive || bubbleActive(now)) return false
        if (state(now) == EngineState.PLAYING) return false
        val text = BubbleForm.duelAttentionText(attention, measure)
        val kind = BubbleKind.Invite(game, attention.matchId)
        val reaction = ReactionKind.Poked(text)
        val ok = if (isShowing()) request(reaction, now, kind) else beginPeek(reaction, now, kind)
        if (!ok) return false
        lane.pendingAttention = null
        return true
    }

    /** 맥 gomokuAttentionIsCurrent(:1393) — 창이 닫혀 있고 같은 판·안 끝남·내 차례·같은 수. 테트리스는 차례가 없다. */
    private fun attentionIsCurrent(a: DuelAttention, facts: DuelFacts): Boolean {
        if (facts.windowVisible) return false
        val match = facts.match ?: return false
        if (match.id != a.matchId || match.finished) return false
        if (a.game == DuelGame.TETRIS) return true
        return match.myTurn && match.moveCount == a.moveCount
    }

    // ───────────────────────── 렌더 정지(맥 :2134-2163) ─────────────────────────

    override fun onRenderSuspend(reason: RenderSuspendReason, suspended: Boolean, now: Double) {
        if (suspended) renderSuspendReasons += reason else renderSuspendReasons -= reason
        setRenderSuspended(renderSuspendReasons.isNotEmpty(), now)
    }

    override fun reconcileStaleRenderSuspension(consoleSessionUsable: Boolean, now: Double): Boolean {
        val stale = renderSuspendReasons.intersect(RenderSuspendReason.STALE_RELEASABLE)
        if (stale.isEmpty() || !consoleSessionUsable) return false
        renderSuspendReasons -= stale
        setRenderSuspended(renderSuspendReasons.isNotEmpty(), now)
        return true
    }

    // ───────────────────────── 자리·포인터(맥 :864-986) ─────────────────────────

    override fun onMonitors(monitors: List<MonitorInfo>) { this.monitors = monitors }

    override fun onSurfaceFrame(frame: OverlayRect) { surfaceFrame = frame }

    private fun currentFrame(): OverlayRect = surfaceFrame
        ?: OverlayGeometry.defaultFrame(monitors.firstOrNull { it.primary }?.work ?: monitors.firstOrNull()?.work ?: OverlayRect(0.0, 0.0, 1920.0, 1080.0))

    private fun workNear(point: OverlayPoint, frame: OverlayRect): OverlayRect? = OverlayGeometry.monitorNear(point, frame, monitors)?.work

    override fun onPointer(kind: PointerKind, ptDip: OverlayPoint, target: HitTarget, now: Double): PointerOutcome = when (kind) {
        PointerKind.DOWN -> pointerDown(ptDip, target, now)
        PointerKind.DRAG -> pointerDrag(ptDip, now)
        PointerKind.UP -> pointerUp(ptDip, target, now)
    }

    private fun pointerDown(pt: OverlayPoint, target: HitTarget, now: Double): PointerOutcome {
        if (!shouldBeVisible || ultraActive || target == HitTarget.None) return PointerOutcome()
        dragCandidate = true
        didDrag = false
        dragAnchor = pt
        val f = currentFrame()
        originAtDragStart = OverlayPoint(f.left, f.top)
        facing = 0
        walking = false
        sink.setFacing(0, false, now) // 남은 방향은 새 누름에서 정면으로
        hysteresis.begin(pt.x)
        return PointerOutcome()
    }

    private fun pointerDrag(pt: OverlayPoint, now: Double): PointerOutcome {
        if (!dragCandidate) return PointerOutcome()
        val dx = pt.x - dragAnchor.x
        val dy = pt.y - dragAnchor.y
        if (!didDrag && DragRules.isDrag(dx, dy)) didDrag = true
        if (!didDrag) return PointerOutcome()
        val frame = currentFrame()
        val px = originAtDragStart.x + dx
        val py = originAtDragStart.y + dy
        val work = workNear(pt, frame)
        val clamped = if (work != null) OverlayGeometry.clampedOrigin(px, py, frame.width, frame.height, work) else OverlayPoint(px, py)
        val moved = clamped.x != frame.left || clamped.y != frame.top
        val next = frame.withOrigin(clamped.x, clamped.y)
        surfaceFrame = next
        if (board.isOpen() && work != null) board.reposition(next, work)
        // ★ 보드 통지보다 뒤 — 드래그 중엔 '가는 방향'을 본다.
        facing = hysteresis.update(pt.x)
        walking = moved
        sink.setFacing(facing, moved, now)
        return PointerOutcome(moveTo = clamped)
    }

    private fun pointerUp(pt: OverlayPoint, target: HitTarget, now: Double): PointerOutcome {
        if (!dragCandidate) return PointerOutcome()
        dragCandidate = false
        walking = false // ★ 걷기는 여기서 무조건 멈춘다.
        val out = if (didDrag) {
            val frame = currentFrame()
            if (board.isOpen()) workNear(frame.center, frame)?.let { board.reposition(frame, it) }
            PointerOutcome(savePlacement = OverlayGeometry.capture(frame, monitors))
        } else {
            PointerOutcome(click = handleClick(target, now))
        }
        didDrag = false
        hysteresis.reset()
        // ★ 정면 복귀는 보드가 닫혀 있을 때만 — 열려 있으면 보드 쪽을 본다.
        facing = if (board.isOpen()) board.facing() else 0
        sink.setFacing(facing, false, now)
        return out
    }

    /** 클릭 경로(맥 handleClick :952): 대결 말풍선 → 도착 말풍선 → 자는 중 화들짝 → 보드 → 때리기. */
    private fun handleClick(target: HitTarget, now: Double): ClickAction {
        if (!shouldBeVisible || ultraActive || target == HitTarget.None) return ClickAction.None
        if (target == HitTarget.Bubble) {
            when (val k = bubbleAt(now)?.kind) {
                is BubbleKind.Invite -> return ClickAction.OpenDuel(k.game, k.matchId)
                is BubbleKind.Arrival -> return ClickAction.OpenMessages(k.senderId)
                else -> Unit
            }
        }
        if (state(now) == EngineState.SLEEPING) {
            request(ReactionKind.Wake, now)
            return ClickAction.Wake
        }
        if (board.isEnabled()) {
            val frame = currentFrame()
            val work = workNear(frame.center, frame) ?: frame
            board.toggle(frame, work)
            return ClickAction.ToggleBoard
        }
        return if (request(ReactionKind.Hit, now)) ClickAction.Hit else ClickAction.None
    }

    // ───────────────────────── tick ─────────────────────────

    /** 졸 수 있나(맥 canEnterDrowsy :1017) — 보이고·한가하고·보드 닫힘·렌더 정지 아님. 시간창 없음(⚠️ 규약 12). */
    fun canEnterDrowsy(now: Double): Boolean =
        shouldBeVisible && !ultraActive && state(now) == EngineState.IDLE && !board.isOpen() && !renderSuspended

    override fun tick(now: Double) {
        expire(now)
        expireBubble(now)
        pruneParticles(now)
        farewellUntil?.let { if (now >= it) farewellUntil = null }
        peekUntil?.let {
            if (now >= it) {
                peekUntil = null
                if (!shouldBeVisible) bubble = null
            }
        }
        if (ultraActive && now >= ultraStartedAt + OverlayTimings.ULTRA_S) endUltra(restoresVisibility = true, now = now)
        val nap = napEndsAt
        if (sleeping && nap != null && now >= nap) wakeQuietly(now)
        nextDrowsyAt?.let {
            if (now >= it) {
                nextDrowsyAt = now + OverlaySchedules.nextDrowsyInterval(random)
                if (!showUpdateBubbleIfNeeded(now) && canEnterDrowsy(now)) request(ReactionKind.Drowsy, now)
            }
        }
        nextBlinkAt?.let {
            if (now >= it) {
                nextBlinkAt = now + OverlaySchedules.nextBlinkInterval(random)
                if (shouldBeVisible && !ultraActive) sink.blink(now)
            }
        }
        messagePumpAt?.let {
            if (now >= it) {
                if (inbox.current == null) {
                    messagePumpAt = null
                } else {
                    showCurrentMessage(now)
                    messagePumpAt = now + OverlayTimings.PUMP_TICK_S
                }
            }
        }
        for ((game, lane) in duels) {
            val at = lane.pumpAt ?: continue
            if (now < at) continue
            if (!lane.hasWork()) { lane.pumpAt = null; continue }
            pumpDuel(game, now)
            lane.pumpAt = if (lane.hasWork()) now + OverlayTimings.PUMP_TICK_S else null
        }
    }
}
