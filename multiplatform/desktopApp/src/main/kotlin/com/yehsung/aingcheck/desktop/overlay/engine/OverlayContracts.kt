package com.yehsung.aingcheck.desktop.overlay.engine

import com.yehsung.aingcheck.character.player.WakeKind
import com.yehsung.aingcheck.desktop.shellapi.OverlayAvailability
import com.yehsung.aingcheck.feature.desktop.socialapi.ReceivedPoke
import com.yehsung.aingcheck.feature.desktop.work.WorkEvent
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin

/*
 * W5-b 오버레이 갈래 사이 계약(overlay.md §4 I-1~I-8) — W5-b1 이 정의하고 b2(표면)·b3(할 일 보드)·조립(P3)이 쓴다.
 * 엔진(b1)은 시계를 읽지 않는다: 모든 시각은 호출자가 넘기는 **단조 초**(`now`, CharacterPlayer 와 같은 축)다.
 * 근무·찌르기·울트라·깃발의 **판정은 생산자 몫**(W2-g/W3-d·DesktopAppConfig) — 오버레이는 결과 값만 받는다.
 * 좌표는 전부 DIP(가상 데스크톱, 왼쪽 위 원점·y 아래로 — Windows 관례). 맥(왼쪽 아래 원점)과 위아래가 반대다.
 */

// ───────────────────────── 기하(값) ─────────────────────────

data class OverlayPoint(val x: Double, val y: Double)

data class OverlayRect(val left: Double, val top: Double, val width: Double, val height: Double) {
    val right: Double get() = left + width
    val bottom: Double get() = top + height
    val centerX: Double get() = left + width / 2
    val centerY: Double get() = top + height / 2
    val center: OverlayPoint get() = OverlayPoint(centerX, centerY)
    fun contains(p: OverlayPoint): Boolean = p.x >= left && p.x < right && p.y >= top && p.y < bottom
    /** NSRect.intersects 와 같게 넓이가 0 인 맞닿음은 겹침이 아니다. */
    fun intersects(o: OverlayRect): Boolean = left < o.right && o.left < right && top < o.bottom && o.top < bottom
    fun intersectionArea(o: OverlayRect): Double {
        val w = minOf(right, o.right) - maxOf(left, o.left)
        val h = minOf(bottom, o.bottom) - maxOf(top, o.top)
        return if (w <= 0 || h <= 0) 0.0 else w * h
    }
    fun withOrigin(x: Double, y: Double): OverlayRect = copy(left = x, top = y)
}

/** 모니터 하나(b2 가 EnumDisplayMonitors·GetMonitorInfo 로 채운다). `key` 는 다시 꽂아도 같은 장치 이름(\\.\DISPLAY1 등). */
data class MonitorInfo(val key: String, val bounds: OverlayRect, val work: OverlayRect, val primary: Boolean = false)

/**
 * 저장되는 창 자리(I-5) — 맥 `check.overlayOffset`([오른쪽 여백, 위 여백]) 에 모니터 키를 더한 값.
 * rx = 작업 영역 오른쪽 − 창 오른쪽, ry = 창 위 − 작업 영역 위. 저장·불러오기(DesktopKeyValueStore)는 b2.
 */
data class OverlayPlacement(val monitorKey: String, val rx: Double, val ry: Double)

// ───────────────────────── I-2 캐릭터 싱크 ─────────────────────────

/**
 * I-2 — `CharacterPlayer`(character/…/player) 와 **같은 시그니처**. b2 가 플레이어를 얇게 감싼다.
 * 엔진 중재는 반환값을 보지 않는다(맥 ReactionEngine 이 SCNAction 결과를 안 보는 것과 같다).
 */
interface CharacterSink {
    val currentCharacterId: String
    fun play(reaction: String, now: Double): Boolean
    fun interrupt(now: Double)
    fun beginSleep(now: Double): Boolean
    fun wake(kind: WakeKind, now: Double): Boolean
    fun blink(now: Double): Boolean
    fun setEyesClosed(closed: Boolean)
    fun setFacing(direction: Int, moving: Boolean, now: Double)
    fun swapCharacter(id: String?, now: Double)
    fun setSuspended(value: Boolean, now: Double): Boolean
}

// ───────────────────────── I-3 그릴 값 ─────────────────────────

enum class OverlayMode { Hidden, Normal, Peek, Ultra, Farewell }

sealed interface BubbleKind {
    data object Normal : BubbleKind
    /** ✉️ 도착 안내(본문을 싣지 않는 꼴). 누르면 보낸 사람 대화(없으면 찌르기 목록) — CheckApp.swift:192-200. */
    data class Arrival(val senderId: String?) : BubbleKind
    /** 대결 신청·차례 말풍선. 누르면 그 판을 연다. */
    data class Invite(val game: DuelGame, val matchId: String) : BubbleKind
    data object Ultra : BubbleKind
}

data class OverlayBubble(val text: String, val kind: BubbleKind, val shownAt: Double, val until: Double)

/** 일시 파티클 — ⚠️ 규약 4: 인터럽트는 **이 열거형 전부**를 걷는다(맥처럼 이름 목록을 따로 두지 않는다). */
enum class ParticleCue(val maxLifetimeS: Double) {
    CONFETTI(3.0),
    GOAL_SPARKS(3.0),
    ULTRA_CHARGE(3.0),
    /** 자는 동안 계속(수명은 endSleep 이 끊는다). */
    ZZZ(Double.POSITIVE_INFINITY),
}

data class ParticleStart(val cue: ParticleCue, val startedAt: Double)

/** 창 자리 지시(b2 는 seq 가 바뀔 때 한 번만 적용한다). */
sealed interface FrameIntent {
    val seq: Int
    /** 저장 자리(없으면 기본 오른쪽 위 24)로 놓는다 — 맥 reposition(). */
    data class Default(override val seq: Int) : FrameIntent
    /** 지금 창이 있는 모니터 전체를 덮는다(울트라). */
    data class UltraCover(override val seq: Int) : FrameIntent
    /** 울트라 전 프레임으로 돌린다(규약 13 — 어느 모니터와 겹칠 때만, 아니면 Default). */
    data class Restore(val frame: OverlayRect, override val seq: Int) : FrameIntent
}

/** I-3 — b2 는 이것만 그린다(캐릭터 자세는 CharacterPlayer 가 갖는다). */
data class OverlayView(
    val mode: OverlayMode,
    val characterId: String,
    val bubble: OverlayBubble?,
    val activeReaction: String?,
    val reactionStartedAt: Double?,
    val sleeping: Boolean,
    val facing: Int,
    val walking: Boolean,
    val particles: List<ParticleStart>,
    val frame: FrameIntent,
    val renderSuspended: Boolean,
)

// ───────────────────────── I-4 말풍선 재기 ─────────────────────────

/** I-4 — 판정 한 벌(b1), 재기·그리기(b2)는 같은 숫자로. 맥 OverlayMessageBubble.Metrics(:2392) 그대로. */
object BubbleMetrics {
    const val CAPSULE_MAX_WIDTH = 110.0
    const val HORIZONTAL_PADDING = 8.0
    const val VERTICAL_PADDING = 5.0
    const val LINE_LIMIT = 2
    const val TEXT_WIDTH = CAPSULE_MAX_WIDTH - HORIZONTAL_PADDING * 2 // 94
    const val FONT_SIZE_PT = 10.0
    /** 창 왼쪽 위에서 말풍선 자리(맥 inset 4·8). */
    const val INSET_X = 4.0
    const val INSET_Y = 8.0
}

/** b2 가 번들 Pretendard semibold 10pt 로 구현한다(W-3 #8). 시험은 가짜 측정기. */
interface BubbleTextMeasure {
    fun width(t: String): Double
    fun lineCount(t: String, widthPt: Double): Int
}

// ───────────────────────── I-5 포인터 ─────────────────────────

enum class PointerKind { DOWN, DRAG, UP }

/** b2 가 픽셀 알파로 판정(D §9-1 — 맥의 말풍선 특례 불필요). */
enum class HitTarget { Body, Bubble, None }

sealed interface ClickAction {
    data class OpenDuel(val game: DuelGame, val matchId: String) : ClickAction
    data class OpenMessages(val senderId: String?) : ClickAction
    data object Wake : ClickAction
    data object ToggleBoard : ClickAction
    data object Hit : ClickAction
    data object None : ClickAction
}

/** 포인터 한 번의 결과. moveTo = 창 새 왼쪽 위(이미 작업 영역 안으로 조인 값), savePlacement = 드래그 끝 저장할 자리. */
data class PointerOutcome(
    val click: ClickAction = ClickAction.None,
    val moveTo: OverlayPoint? = null,
    val savePlacement: OverlayPlacement? = null,
)

// ───────────────────────── I-6 할 일 보드 ─────────────────────────

/** I-6 — b3 구현. 엔진은 클릭·드래그 때 부르고, 열려 있으면 졸지 않는다(맥 canEnterDrowsy). */
interface BoardHost {
    /** 설정의 할 일 켜짐(맥 isTodoEnabled). 꺼져 있으면 클릭은 때리기다. */
    fun isEnabled(): Boolean = true
    fun isOpen(): Boolean
    fun toggle(anchor: OverlayRect, work: OverlayRect)
    fun reposition(anchor: OverlayRect, work: OverlayRect)
    fun close()
    /** 열린 보드 쪽 방향(−1 왼쪽 · 1 오른쪽 · 0 닫힘) — 맥 faceTheBoard. */
    fun facing(): Int = 0

    object None : BoardHost {
        override fun isEnabled(): Boolean = false
        override fun isOpen(): Boolean = false
        override fun toggle(anchor: OverlayRect, work: OverlayRect) {}
        override fun reposition(anchor: OverlayRect, work: OverlayRect) {}
        override fun close() {}
    }
}

// ───────────────────────── 입력 값 ─────────────────────────

/** 팀원 한 명(core.wire TeamMemberStatus 에서 조립이 옮긴다 — working = status == working). */
data class TeamPresence(val id: String, val name: String, val working: Boolean)

/** 렌더 정지 사유(맥 CheckOverlayController.RenderSuspendReason :98). platform.power/session 이 넣는다. */
enum class RenderSuspendReason {
    SCREENS_ASLEEP, SCREEN_LOCKED, SESSION_INACTIVE;

    companion object {
        /** 콘솔 세션이 쓸 수 있으면 풀어도 되는 사유(맥 staleReleasableReasons :111). */
        val STALE_RELEASABLE: Set<RenderSuspendReason> = setOf(SCREEN_LOCKED, SESSION_INACTIVE)
    }
}

enum class DuelGame { GOMOKU, CHESS, TETRIS }

/** 받은 대결 신청(스토어 onInviteArrived). expiresAt 은 엔진과 같은 단조 초로 조립이 바꿔 넣는다. */
data class DuelInvite(val game: DuelGame, val id: String, val peerName: String, val stake: Int, val expiresAt: Double)

enum class DuelAttentionKind { MATCH_STARTED, MY_TURN }

/** 차례 알림(스토어 onAttention). 게임마다 한 칸(새것이 덮는다). */
data class DuelAttention(
    val game: DuelGame,
    val matchId: String,
    val kind: DuelAttentionKind,
    val opponentName: String,
    val moveCount: Int,
)

/** 스토어 현재 사실 — 띄우기 직전 거르기(맥 :1297 alive · :1393 attentionIsCurrent). */
data class DuelFacts(
    val aliveInviteIds: Set<String> = emptySet(),
    val windowVisible: Boolean = false,
    val match: DuelMatchFact? = null,
)

data class DuelMatchFact(val id: String, val finished: Boolean, val myTurn: Boolean, val moveCount: Int)

// ───────────────────────── I-1 엔진 입력 · I-7 출력 ─────────────────────────

/**
 * I-1 — 오버레이 엔진(OverlayDirector)의 문. 전부 값이고, 시각은 단조 `now` 초.
 * I-8 — 받은 메시지는 생성자에 넘긴 `MessageBubbleInbox`(pins B) 로 읽고, 띄웠을 때만 consumeCurrent() 한다(규약 10).
 *        넛지 자동 시작은 `startOrigin == NUDGE`(DesktopWorkSnapshot) 또는 `WorkEvent.NudgeStarted` 로 온다.
 */
interface OverlayInputs {
    fun onWorking(isWorking: Boolean, overlayEnabled: Boolean, now: Double, startOrigin: WorkStartOrigin? = null)
    /** 1등 출근(MilestoneTracker firstArrival)·넛지 문구. 판정은 생산자, 10s 수명·소비는 엔진(규약 7). */
    fun setCommuteStartOverride(text: String, seconds: Double, now: Double)
    /** 근무 갈래 사건(W-3 #12): Milestone·TeamGoalAchieved(가시 게이트) · NudgeStarted(8s 문구). */
    fun onWorkEvent(event: WorkEvent, now: Double)
    /** ReceivedPokeSink 결과(1시간 신선분·강등 끝난 값). 띄웠으면 true. */
    fun onPokes(batch: List<ReceivedPoke>, now: Double): Boolean
    /** 보상 길(UltraChargedSink → UltraCharged, 주간 근무 → RubyReward). 무엇을 보낼지는 생산자 결정(규약 8). */
    fun onReward(kind: ReactionKind, now: Double): Boolean
    /** 가시 게이트 길(milestone·goalAchieved·greeting). 숨김이면 버린다. */
    fun onReaction(kind: ReactionKind, now: Double): Boolean
    fun onTeam(members: List<TeamPresence>, selfId: String?, now: Double)
    fun onUpdateAvailable(version: String, now: Double): Boolean
    fun onMessagesChanged(now: Double)
    fun enqueueDuelInvite(invite: DuelInvite, now: Double)
    fun enqueueDuelAttention(attention: DuelAttention, now: Double)
    fun onDuelFacts(game: DuelGame, facts: DuelFacts)
    fun clearDuels(game: DuelGame)
    fun onSignedOut()
    fun onRenderSuspend(reason: RenderSuspendReason, suspended: Boolean, now: Double)
    fun reconcileStaleRenderSuspension(consoleSessionUsable: Boolean, now: Double): Boolean
    fun onMonitors(monitors: List<MonitorInfo>)
    fun onSurfaceFrame(frame: OverlayRect)
    fun onPointer(kind: PointerKind, ptDip: OverlayPoint, target: HitTarget, now: Double): PointerOutcome
    fun tick(now: Double)
    fun view(now: Double): OverlayView
    /** I-7 — W3-c1 알림 중재에 넘길 값(W-3 #6: 말풍선 > 토스트 > 점). */
    fun availability(now: Double): OverlayAvailability
}
