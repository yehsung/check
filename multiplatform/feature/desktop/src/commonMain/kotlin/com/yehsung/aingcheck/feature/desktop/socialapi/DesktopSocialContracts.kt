// 조정자 핀(W-windows-resume W-3·xplat-w2/pins.md) — 갈래는 읽기만
// 출처: xplat-w1/briefs/poke.md §4 + pins.md B 조정 ④⑤⑥. 시간 타입은 core 관례 SwiftDate 하나(조정 ⑥).
// 판정: 흡수·세션 id 정규화 = work(값 PokeConsumeFacts), 소비 게이트 = 찌르기(W2-g2) 한 벌. 바꿀 일은 coordinator_patches 로.
package com.yehsung.aingcheck.feature.desktop.socialapi

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.PokeKind
import com.yehsung.aingcheck.core.wire.models.TakenPokeRow
import kotlinx.coroutines.Job

/** (1) 근무 갈래가 내는 **값**(정규화 끝남). 조정 ⑤: 흡수 소비 깃발은 DesktopAppConfig.adoptedPokeConsume. */
data class PokeConsumeFacts(
    /** Swift startedAt != nil(isWorking 아님). */
    val localSessionOpen: Boolean,
    val adoptedRemoteSession: Boolean,
    val canonicalSessionID: String?,
    /** 정규화됨. */
    val ownOpenSessionID: String?,
    /** (deviceID, 정규화된 sessionID). null·빈 = 판정 불가. */
    val ownDeviceClaims: List<Pair<String, String?>>?,
    /** 'win:'+uuid, null 이면 흡수 소비 금지. */
    val deviceID: String?,
    val lastMeaningfulInputAt: SwiftDate?,
)

/** (2) 판정 한 벌 — W2-g2 가 구현, 폴링(W2-g2)·.drain/따라잡기(W2-g3)가 같은 함수를 부른다. */
fun interface PokeConsumeGate {
    fun mayConsume(now: SwiftDate): Boolean
}

/** (3) 소비 몸 — W2-g2 구현, W2-g3·work 가 부른다. */
sealed interface DrainOutcome {
    data class Ok(val count: Int) : DrainOutcome
    data class Failed(val reason: String) : DrainOutcome
}

interface PokeDrainer {
    suspend fun drainOnce(): DrainOutcome
    fun requestDrain()
    fun flushOnUserStop(isTerminating: Boolean): Job?
}

/** (4) 링 구독 신호의 단일 읽기 지점 — W2-g3 구현. */
interface RealtimeSubscription {
    val isSubscribed: Boolean
    fun clearCatchUpDebt()
}

/** (5) 근무→소셜 생명주기 훅(값 없는 사건). work 가 부르고 AppGraph 가 셋에 펼친다. */
interface DesktopSocialLifecycle {
    fun onSignedIn()
    fun onSignedOut()
    /** requestDrain + clearCatchUpDebt. */
    fun onWorkStarted()
    fun onUserStoppedWork(isTerminating: Boolean)
    /** 지갑 missionCandidate. */
    fun onLapCrossed(lap: Int)
    /** 빚 되맞춤. */
    fun onTeamStatusApplied()
    fun onWillSleep(at: SwiftDate)
    fun onDidWake(at: SwiftDate)

    /** 조립 전·시험 자리(아무것도 하지 않는다). */
    object None : DesktopSocialLifecycle {
        override fun onSignedIn() {}
        override fun onSignedOut() {}
        override fun onWorkStarted() {}
        override fun onUserStoppedWork(isTerminating: Boolean) {}
        override fun onLapCrossed(lap: Int) {}
        override fun onTeamStatusApplied() {}
        override fun onWillSleep(at: SwiftDate) {}
        override fun onDidWake(at: SwiftDate) {}
    }
}

/** (6) 바깥으로 나가는 신호(값) — 오버레이 W5-b·토스트·메시지. 받는 쪽이 없으면 take_pokes 를 조립하지 않는다. */
data class ReceivedPoke(val id: String, val fromName: String, val createdAt: SwiftDate, val kind: PokeKind, val fromCharacterID: String?)

/** ultra 는 이미 강등된 채. */
fun interface ReceivedPokeSink {
    fun onPokesReceived(batch: List<ReceivedPoke>)
}

/** granted_now 일 때만. */
fun interface UltraChargedSink {
    fun onUltraCharged()
}

interface ConsumedRowsSink {
    fun insertConsumedPokes(rows: List<TakenPokeRow>): Int
    fun receiveConsumedMessages(rows: List<TakenPokeRow>, now: SwiftDate)
}

/** 토스트 억제(D §14 B2)가 읽는다. */
interface FocusModeReader {
    val isFocusOn: Boolean
}

/** W2-g4 구현, W2-g2 발사 성공이 부른다. */
fun interface UltraWalletTrigger {
    fun sync(reason: UltraSyncReason)
}

enum class UltraSyncReason { SignIn, PanelOpen, MissionCandidate, Periodic }

/** 조정 ④: 받은 메시지 말풍선 한 칸(Swift ReceivedMessage — WorkTimerStorePoke.swift:1292). */
data class QueuedBubbleMessage(
    val id: String,
    val fromName: String,
    /** 앞뒤 공백 제거, 비어 있지 않음(큐가 거른다). */
    val body: String,
    val createdAt: SwiftDate,
    val fromUserID: String? = null,
    val fromAvatarURL: String? = null,
)

/** 조정 ④(overlay.md I-8): 큐와 상한 20·5분은 W2-g2, '띄웠을 때만 소비'는 오버레이(규약 10). */
interface MessageBubbleInbox {
    val current: QueuedBubbleMessage?
    fun consumeCurrent()

    /** 빈 받은 편지함(조립 전·시험). */
    object Empty : MessageBubbleInbox {
        override val current: QueuedBubbleMessage? get() = null
        override fun consumeCurrent() {}
    }
}
