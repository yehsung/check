// 원본: Sources/CheckCore/RummyStore.swift:1 @ 1a5eeca6
package com.yehsung.aingcheck.core.stores.rummy

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.rummy.RummyInviteQueue
import com.yehsung.aingcheck.core.rules.rummy.RummyInviteQueueHost
import com.yehsung.aingcheck.core.rules.rummy.RummyPhase
import com.yehsung.aingcheck.core.rules.rummy.RummyRackLayout
import com.yehsung.aingcheck.core.rules.rummy.RummyRackSort
import com.yehsung.aingcheck.core.rules.rummy.RummyTurnEditor
import com.yehsung.aingcheck.core.stores.gomoku.GomokuStoreHost
import com.yehsung.aingcheck.core.stores.gomoku.notice
import com.yehsung.aingcheck.core.stores.tetris.DISTANT_PAST
import com.yehsung.aingcheck.core.stores.tetris.DuelCall
import com.yehsung.aingcheck.core.stores.tetris.delayMillis
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.SwiftUUID
import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyLayout
import com.yehsung.aingcheck.core.wire.games.RummyLobby
import com.yehsung.aingcheck.core.wire.games.RummyMatchState
import com.yehsung.aingcheck.core.wire.games.RummyMatchStatus
import com.yehsung.aingcheck.core.wire.games.RummyRanking
import com.yehsung.aingcheck.core.wire.games.RummyRoom
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.abs
import kotlin.time.TimeSource

// 아잉 큐브(rummy) 스토어 — 화면 상태 · 서버 동기화 · 작업 상태 전송 · RPC 호출. 맥·폰 공용(코어).
//
// 파일 지도: 여기(표면 · 수명 · 창 · 신호 · 폴링 · 리셋 · 공용 관용구) · `RummyStoreLobby.kt`(로비 · 초대 · 방 동작 ·
// 순위 · 차단 거울) · `RummyStoreGame.kt`(state 깔때기 · 편집기 재구성 · 차례 동작 · 작업 상태 전송 · 마감) ·
// `RummyStoreV2.kt`(배치 · 하트비트 · 이탈 · 반응 · 뽑기 · 장부 · 받침대 저장) · `RummyNoticeText.kt`(문구 한 곳).
//
// ── 베낀 규약(Swift 머리말 그대로) ──
//  ① **서버가 권위다.** 판·랙·차례·결과·루비는 RPC 응답으로만 바뀐다. 낙관적 차감·낙관적 확정은 없다.
//     합법 판정의 주인도 서버다(`rummy_play` 가 R-16 을 다시 판정한다) — 편집기 판정은 버튼·안내용이다.
//  ② **시각은 서버 시계로 보정한다**(`noteServerNow` · `deviceDate`). 차례 마감은 서버 `turn_deadline_ms` 를 기기 시계로
//     옮겨 **화면이** 보간한다(`turnRemaining(date)` — 표시용이고 응답마다 통째로 덮는다).
//  ③ **폴링은 창이 보일 때만 돈다**(로비 30초 · 방/판 5초(구독 중 + 마감이 멀면 15초) · 순위 60초). 창이 안 보이면 초인종과 마감 깨우기만 남는다.
//  ④ **늦게 온 응답은 버린다.** 세대 두 개(`resetGeneration` + `host.sessionGeneration`)가 로그아웃·계정 전환 뒤의 응답을,
//     서버 `seq`·`draft_seq` 가 같은 판의 옛 스냅숏을, 요청 표(`requestTicket`)가 seq 가 안 바뀌는 방(forming)의 옛 응답을 버린다.
//  ⑤ **사용자 문구는 `RummyNoticeText` 한 곳에만 있다.**
//  ⑥ **신호는 합친다**(`requestSync` — 도는 중 온 신호는 뒤따르는 한 번).
//  ⑦ **초 단위 값은 화면 잎만 읽는다** — 스토어는 매초 대입하지 않는다(남은 초는 함수로 낸다).
//  ⑧ **2단 입력 상태(작업 판)는 스토어가 든다**(`editor`). 화면 상태에 두면 화면이 내려갔다 돌아올 때 작업이 날아간다.
//
// ── 아잉 큐브에서 새로 생긴 자리 ──
//  ⑨ **작업 상태 전송**(R-19). 내 차례에 끌기가 끝날 때마다 250ms 디바운스 → `rummy_draft`. 한 번에 하나만 비행하고,
//     비행 중에 바뀐 것은 끝난 뒤 **최신 것 한 번**. 서버는 마지막 것만 두고 시간 초과 때 그 판을 판정한다 —
//     그래서 차례 중간에 편집기를 새로 세우면(앱 재실행) 서버 작업 판을 내 화면(시작 판)으로 다시 맞춘다.
//     `p_expected_seq` 는 편집기가 선 seq 가 아니라 **지금 든 판의 seq** 다(같은 차례에 남의 기권으로 seq 가 오른다).
//     같은 차례에 stale 을 받으면 새 seq 로 한 번 더 보낸다. [완료]·뽑기가 확정되지 않으면(실패·거절·stale) 걷었던
//     디바운스를 다시 건다 — 서버 작업 판이 내 화면에 머물게.
//  ⑩ **편집기 수명.** **차례**(`RummyEditorKey` = 판 · 차례 자리 · `turn_started_ms`)가 바뀌면 새 판·랙으로 다시 세우되
//     랙 배치는 면 순서로 넘긴다. 같은 차례면 **덮지 않는다**. 같은 차례인데 확정 판·내 랙이 달라졌을 때만 다시 세운다.
//     '내 차례' 알림·마감 깨우기도 같은 차례 정체성으로 가른다.
//
// ── v2 ──
//  ⑪ **배치도 작업 상태다.** 편집기가 판 배치(`points`)를 들고, 작업 상태 전송·[완료]가 `p_layout` 으로 싣는다.
//  ⑫ **하트비트**는 phase 가 room·playing 인 동안 10초마다. 서버는 90초 안 보이면 끊김 기권시킨다.
//     의도적 이탈은 `leaveForExit` — 최대 2초 기다리고, 못 닿아도 이 기기에선 접는다.
//  ⑬ **반응**은 꾸밈이라 내 말풍선을 바로 띄우고(메아리는 한 번 삼킨다), 남의 것은 state 에서 처음 보는 것만 낸다.
//     **뽑기**는 다음 편집기의 랙에서 새로 생긴 면을 찾아 `onTileDrawn` 으로 알린다.
//  ⑭ **받침대 자리는 판마다 로컬 저장**(`rackDefaults`, 판 id 키) — 판이 끝나거나 접히면 지운다.
//  ⑮ **한 계정 기기 여럿.** `rummy__ring` 은 그 사람의 모든 기기를 울린다. **기기가 스스로 보내는 쓰기**(하트비트 · `leaveForExit` ·
//     차례 중간 작업 판 되돌리기)는 이 기기가 그 판에 손댄 적이 있을 때만 한다(`engagedMatchIDs`). 장부는 계정에 묶인다.
//  ⑯ **루비 잔액은 스토어가 마지막으로 안 값.** 판 state 에는 잔액이 없어서 판돈 차감·정산을 **처음 본** 순간 로비를 한 번 다시 읽는다.
//
// ── Kotlin 이식 ──
//  · Swift `@MainActor` 한 스레드 규약 그대로 — 이 스토어는 [scope](앱은 메인 디스패처, 시험은 시험 디스패처) 한 곳에서만 돈다.
//  · Swift `Task {}` = [scope] `launch`. Swift `@Observable` var = Compose `mutableStateOf`. `@ObservationIgnored` = 일반 필드.
//    **`Dispatchers.Main.immediate` 는 launch 를 그 자리에서 첫 중단까지 돌린다**(Swift Task 는 안 그렇다). 그래서
//    `syncJob` 은 살아 있는지(`isActive`)로 가르고, 지연 0 깨우기는 1ms 를 쉰다 — 안 그러면 몸통이 먼저 끝나 뒤늦은 대입이 끝난 잡을 남긴다.
//  · 취소는 예외다: `perform` 은 [CancellationException] 을 다시 던진다. 그래서 `refreshMatch` 의 비행 깃발은 finally 로 내린다
//    (안 그러면 폴링 잡이 취소될 때 깃발이 선 채로 남아 그 뒤 조회가 영영 안 나간다).
//  · 저장소는 [KeyValueStore] 라 목록은 JSON 글자 한 칸으로 둔다. 받침대 자리는 면이 와이어 타입이라 **SwiftJson 으로만** 읽고 쓴다.
//
// ── 폰 몫(맥에 없는 것) ──
//  · G §8-17 #1: 판돈 깃발 `appConfig.duelsEnabled` 가 꺼진 빌드는 **입구**(만들기 · 참가 · 초대 · 시작)를 잠그고 배지·초대 알림도 내지 않는다.
//    거절·나가기·조회·순위·이미 든 판의 차례 동작은 깃발과 무관하다. 잠긴 빌드는 화면이 보이거나 판을 들고 있을 때 말고는 조회도 내지 않는다.
//  · 맥의 창 닫기·앱 종료 이탈은 폰에 없다. 뒤로 가기(`requestBack`·`confirmBack`) · 로그아웃·계정 삭제(`leaveForExit`)가 잇는다.
//    **앱이 뒤로 가는 것은 이탈이 아니다** — 판단은 `appDidEnterBackground` 한 곳이고 서버 90초 규칙에 맡긴다.

/** 아잉 큐브 스토어가 네트워크·세션·루비 미러를 빌리는 곳 — 오목·체스와 **같은 문**이다. */
typealias RummyStoreHost = GomokuStoreHost

/** Swift `RummyStore.Availability`. */
enum class RummyAvailability { available, updateRequired, serverMissing }

/** Swift `RummyStore.StateApplyOutcome`. */
enum class RummyStateApplyOutcome { applied, ignored }

class RummyStore(
    /** 이 스토어의 일이 도는 곳(Swift `@MainActor`). 앱은 메인, 시험은 시험 디스패처. */
    val scope: CoroutineScope,
    host: RummyStoreHost? = null,
) {
    /** 네트워크·세션·루비 미러를 빌리는 곳. null 이면 미리보기·렌더 시험용이라 네트워크를 한 건도 내지 않는다. */
    var host: RummyStoreHost? = host
        private set

    /** 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다. */
    fun attach(host: RummyStoreHost) {
        this.host = host
    }

    companion object {
        /** 로비 목록 재조회 주기(초) — 테트리스와 같다. */
        const val lobbyPollSeconds: Double = 30.0

        /** 방·판에 있을 때 그 state 를 다시 읽는 주기(초) — 미구독이거나 마감이 가깝거나 마감을 모를 때. 창이 보일 때만. */
        const val matchPollSeconds: Double = 5.0

        /** 같은 조회 — 실시간 구독 중 + 마감까지 여유가 있을 때(1a5eeca6). 이 조회는 신호를 놓쳤을 때의 그물이다. */
        const val matchPollSecondsCalm: Double = 15.0

        /** 차례 마감·방 닫힘까지 남은 시간이 이 안으로 들어오면 [matchPollSeconds] 로 돌아간다. */
        const val matchPollNearDeadlineSeconds: Double = 15.0

        /** 허브·팝오버를 열 때 로비를 다시 읽는 스로틀(초). */
        const val menuLobbyThrottleSeconds: Double = 30.0

        /** 로비를 보고 있는 동안 순위표 재조회 주기(초). */
        const val rankingPollSeconds: Double = 60.0

        /** 창 열기와 창 표시가 같은 조회를 두 번 쏘지 않게 하는 간격(초). */
        const val reloadDedupeSeconds: Double = 1.0

        /** 서버 시계 오프셋을 다시 재는 문턱(초). */
        const val serverClockToleranceSeconds: Double = 0.25

        /** 작업 상태 전송 디바운스(초, 설계서 §2 R-19). */
        const val draftDebounceDefaultSeconds: Double = 0.25

        /** 응답이 유예를 안 실어 준 드문 경우의 기본값(초, 서버 `rummy_grace_seconds()`). */
        const val defaultGraceSeconds: Double = 2.0

        /** 마감 + 유예가 지난 뒤 다시 읽기 전 여유(초) — 기기·서버 시계 잔차를 흡수한다. */
        const val deadlineSlackSeconds: Double = 0.5

        /** 마감 뒤에도 같은 차례면 다시 읽는 간격(초)과 상한(서버 크론이 1분 안에 따라잡는다). */
        const val deadlineRetrySeconds: Double = 3.0
        const val deadlineRetryLimit: Int = 3

        /** 작업 상태 전송이 실패했을 때 다시 보내는 간격(초)과 상한. */
        const val draftRetrySeconds: Double = 1.0
        const val draftRetryLimit: Int = 3

        /** v2 하트비트 주기(초). 서버 끊김 기준은 90초(`rummy_disconnect_seconds()`). */
        const val heartbeatDefaultSeconds: Double = 10.0

        /** v2 의도적 이탈이 서버 답을 기다리는 상한(초). */
        const val exitLeaveLimitSeconds: Double = 2.0

        /** v2 반응 쿨다운(초) — 서버도 같은 사람 2초(`too_fast`). */
        const val reactionCooldownSeconds: Double = 2.0

        /** v2 [reactionFeed] 상한. */
        const val reactionFeedLimit: Int = 12

        /** v2 `engagedMatchIDs` 상한(못 지운 것이 쌓이지 않게 — 오래된 것부터 버린다). */
        const val engagedLimit: Int = 16

        /** v2 내 반응의 메아리를 기다리는 창(초) — 서버 state 는 최근 10초만 싣는다. */
        const val reactionEchoSeconds: Double = 10.0

        internal const val TAG: String = "rummy"

        const val engagedDefaultsKey: String = "rummy.engaged.v2"

        /** 장부 주인(계정 id). 강제 로그아웃으로 남은 앞 계정의 판 id 가 같은 판의 상대 계정에게 맞아 버리지 않게 한다. */
        const val engagedOwnerDefaultsKey: String = "rummy.engaged.v2.owner"

        fun rackDefaultsKey(matchID: SwiftUUID): String = "rummy.rack.v2.${matchID.lowercased}"

        /**
         * 아직 끝나지 않은 판 status(끝남·취소·만료가 아님) — 신호·폴링·따라잡기가 그 판을 다시 읽는 조건.
         * 모르는 값(`unknown`)도 다시 읽는다. 들고만 있고 안 읽으면 그 판에 굳는다.
         */
        fun isUnsettled(status: RummyMatchStatus?): Boolean =
            status != RummyMatchStatus.finished && status != RummyMatchStatus.cancelled && status != RummyMatchStatus.expired
    }

    // MARK: 화면 상태 (관찰 대상 — Compose 스냅숏)

    var phase: RummyPhase by mutableStateOf(RummyPhase.lobby)
        internal set
    var availability: RummyAvailability by mutableStateOf(RummyAvailability.available)
        internal set

    /** 와이어 모델 — **차단 거울을 거친 것**이다(차단한 사람·그 사람이 낀 방·그 사람의 초대는 빠진다). */
    var lobby: RummyLobby? by mutableStateOf(null)
        internal set

    /** 마지막 로비 조회가 실패했다 — 사람 목록이 "불러오는 중"에 영영 머물지 않게 화면이 다시 시도 줄을 세운다. 들고 있는 줄은 지우지 않는다. */
    var lobbyLoadFailed: Boolean by mutableStateOf(false)
        internal set

    /** 내가 앉은 방/판의 최신 state. */
    var match: RummyMatchState? by mutableStateOf(null)
        internal set

    /** 판이 active 이고 내가 playing 일 때. 내 차례가 아니면 랙 정렬만 쓰인다. 값 타입처럼 다룬다 — 바꿀 때는 copy() 뒤 다시 넣는다. */
    var editor: RummyTurnEditor? by mutableStateOf(null)
        internal set

    /** 0.3.70: 마지막 정렬이 아직 살아 있나 — 뽑은 타일을 이 정렬 자리에 끼운다. 받침대로 놓는 끌기가 끄고, 판이 바뀌면 지운다. 정렬 버튼의 '선택됨'. */
    var rackSortMode: RummyRackSort? by mutableStateOf(null)
        internal set

    /** 사용자 문구(`RummyNoticeText` 한 곳). */
    var notice: String? by mutableStateOf(null)
        internal set

    /** 마지막으로 안 내 루비 잔액(머리말 ⑯). null = 아직 모름. 판 중에도 그대로 남는다. */
    var rubyBalance: Long? by mutableStateOf(null)
        internal set

    /** 요청 비행 중(버튼 잠금). 작업 상태 전송·폴링은 세우지 않는다 — 사용자가 누른 동작만. */
    var isWorking: Boolean by mutableStateOf(false)
        internal set
    var ranking: RummyRanking? by mutableStateOf(null)
        internal set
    var selectedStake: Long by mutableStateOf(3L)
    var createPublic: Boolean by mutableStateOf(false)
    var rulesShown: Boolean by mutableStateOf(false)

    /** **순위 적재의 주 스위치. 기본 false**(배선 값 — [reset] 이 건드리지 않는다). */
    var rankingEnabled: Boolean by mutableStateOf(false)

    /** 최근 반응(오래된 것이 앞, 최대 [reactionFeedLimit]). 화면은 `receivedAt` 에서 2.5초 동안 말풍선을 그린다. */
    var reactionFeed: List<RummyReactionEvent> by mutableStateOf(emptyList())
        internal set

    /** 마지막 뽑기 사건(모션 계기). `serial` 이 바뀔 때마다 새 사건이다. */
    var lastDraw: RummyDrawEvent? by mutableStateOf(null)
        internal set

    /** 초대 줄에 서 있는 사람(화면의 "부르는 중"). 줄의 거울이다 — 줄 자체는 [inviteQueue]. */
    var callingPeerIDs: List<SwiftUUID> by mutableStateOf(emptyList())
        private set

    /**
     * 이 기기가 지금 판을 쥐고 있다(engaged 판이 room·playing · 내 자리가 아직 판에 있음 · 세션 있음). 맥은 App Nap 을 막고,
     * 폰은 게임 탭 스토어가 화면 꺼짐을 막는다(자동잠금이 닿으면 90초 끊김 기권이다).
     */
    var isHoldingMatch: Boolean by mutableStateOf(false)
        internal set

    val isMyTurn: Boolean get() = RummyStore.isMyTurn(match, myUserID)

    /** 남의 차례면 그 사람 작업 판(없으면 null → `match.table`). */
    val otherDraft: List<List<RummyFace>>?
        get() {
            val current = match ?: return null
            if (current.status != RummyMatchStatus.active || isMyTurn) return null
            return current.draft?.table
        }

    // MARK: §8-17 #1 — 판돈 대결 입구 깃발(Tetris·체스·오목 선례)

    /** 이 빌드가 판돈 대결의 입구를 여는가. 호스트가 없으면 false. */
    val duelsEnabled: Boolean get() = host?.appConfig?.duelsEnabled ?: false

    /** 입구(만들기 · 참가 · 초대 · 시작)가 이 빌드에서 잠겼는가. 거절·나가기·순위는 이 값을 보지 않는다. */
    val duelsLocked: Boolean get() = !duelsEnabled

    /** 잠긴 빌드에서 받은 초대를 접는 한 줄(받은 초대가 있을 때만). 화면은 참가 단추 대신 이 줄을 그린다. */
    val incomingFoldedNotice: String?
        get() = if (duelsLocked && incomingInvites.isNotEmpty()) RummyNoticeText.updateRequired else null

    /**
     * 초인종·깨어남·허브 같은 **화면 밖 계기**가 조회를 내도 되는가. 잠긴 빌드는 입구도 배지도 없어 그 조회를 쓸 데가 없다 —
     * 화면이 떠 있거나 판을 들고 있을 때만 읽는다(끌기마다 울리는 초인종이 안 쓰는 조회로 서버를 두드리지 않게).
     */
    internal val mayReadOutsideScreen: Boolean get() = !duelsLocked || isWindowVisible || match != null

    // MARK: 시간 — 화면 잎이 읽는다

    /** 지금 차례의 남은 초(0 아래로 안 간다). 판이 active 가 아니거나 마감을 모르면 null. */
    fun turnRemaining(date: SwiftDate): Double? {
        val current = match ?: return null
        if (current.status != RummyMatchStatus.active) return null
        val deadline = deviceDate(current.turnDeadlineMs) ?: return null
        return maxOf(0.0, deadline.timeIntervalSince(date))
    }

    /** 방(forming)이 닫히기까지 남은 초. 방이 아니면 null. */
    fun roomRemaining(date: SwiftDate): Double? {
        val current = match ?: return null
        if (current.status != RummyMatchStatus.forming) return null
        val expires = deviceDate(current.expiresAtMs) ?: return null
        return maxOf(0.0, expires.timeIntervalSince(date))
    }

    /** 지금 state 안전망 주기. 미구독은 신호가 없으니 언제나 촘촘하고, 구독 중에는 마감이 멀 때만 늦춘다. */
    fun matchPollInterval(date: SwiftDate): Double {
        if (host?.realtimeState?.isSubscribed != true) return matchPollSeconds
        val remaining = turnRemaining(date) ?: roomRemaining(date) ?: return matchPollSeconds
        return if (remaining > matchPollNearDeadlineSeconds) matchPollSecondsCalm else matchPollSeconds
    }

    // MARK: 문(앱 배선이 꽂는다)

    var presentWindow: (() -> Unit)? = null
    var dismissWindow: (() -> Unit)? = null

    /** 새 초대(방 id 마다 한 번, 차단한 방장 제외 · 잠긴 빌드 제외). */
    var onInviteArrived: ((RummyRoom) -> Unit)? = null

    /** 주의 끌기(판 시작 · 창이 안 보일 때 내 차례). */
    var requestAttention: (() -> Unit)? = null

    /** 말풍선 한 줄(`RummyNoticeText` 의 문구). 창이 안 보일 때만 부른다. */
    var onAttention: ((String) -> Unit)? = null

    /** 내 판이 끝난 것을 **처음 본** 순간 한 번(판 id 마다). 일일 미션 진행을 묻는 자리. */
    var onMatchFinished: (() -> Unit)? = null

    /** v2: 내 랙에 새 타일이 들어왔다. 편집기를 새로 세운 **뒤에** 부른다 — `tileID` 로 바로 찾을 수 있다. */
    var onTileDrawn: ((RummyDrawEvent) -> Unit)? = null

    /** v2: 이모티콘 반응 하나(내 것은 보내는 즉시, 남의 것은 state 에서 처음 볼 때). */
    var onReaction: ((RummyReactionEvent) -> Unit)? = null

    /** `isHoldingMatch` 가 바뀔 때마다 한 번(맥 App Nap 자리 — 폰은 안 꽂는다, 화면 꺼짐은 게임 탭 스토어가 값을 읽는다). */
    var onHoldingMatchChange: ((Boolean) -> Unit)? = null

    // MARK: v2 배선 · 장부

    /** 하트비트 주 스위치(시험은 끄고 `heartbeatTick` 을 직접 밟는다). */
    var heartbeatEnabled: Boolean = true

    /** 하트비트 주기(초). */
    var heartbeatSeconds: Double = heartbeatDefaultSeconds

    /** 받침대 자리 저장소. **null 이면 저장하지 않는다**(기본 — 시험이 앱 저장소를 더럽히지 않게). 앱 배선이 넣는다. */
    var rackDefaults: KeyValueStore? = null

    var heartbeatJob: Job? = null
        internal set
    var heartbeatMatchID: SwiftUUID? = null
        internal set

    /** 앱이 뒤로 갔다(판단은 `appDidEnterBackground` 한 곳). 하트비트만 이 값을 본다. 앱 상태라 [reset] 이 건드리지 않는다. */
    var isAppInBackground: Boolean = false
        internal set

    /** 서버가 들고 있다고 믿는 작업 판 배치([lastSentDraft] 의 짝). */
    var lastSentLayout: RummyLayout? = null
        internal set
    internal var lastReactionSentAt: SwiftDate = DISTANT_PAST

    /** 내가 보내고 이미 띄운 반응(키 · 보낸 시각) — state 로 돌아온 메아리를 한 번 삼킨다. */
    internal var pendingOwnReactions: MutableList<Pair<String, SwiftDate>> = mutableListOf()
    internal var seenReactionKeys: MutableSet<String> = mutableSetOf()
    internal var reactionSerial: Int = 0
    internal var drawSerial: Int = 0

    /** 이 기기가 손댄 판 저장소(머리말 ⑮). **null 이면 메모리에만 둔다.** 넣는 순간 저장된 목록을 읽어 합친다. */
    var engagedDefaults: KeyValueStore? = null
        set(value) {
            field = value
            loadEngaged()
        }

    /** 이 기기에서 create·join·start·draft·play·draw·react 를 **보낸** 판(오래된 것이 앞, 최대 [engagedLimit]). */
    var engagedMatchIDs: List<SwiftUUID> = emptyList()
        internal set

    /** [engagedMatchIDs] 의 주인(그 판들에 손댄 계정 id, 소문자). null = 세션 전에 적었다(믿는다). */
    var engagedOwnerUserID: String? = null
        internal set

    // MARK: 초대 줄(맥은 화면 수식어가 민다 — Kotlin 은 스토어가 민다)

    /** 방 없이 누른 [초대] · 결과의 [한 판 더] 가 남긴 '부를 사람' 줄. */
    val inviteQueue: RummyInviteQueue = RummyInviteQueue()

    private val inviteBridge = object : RummyInviteQueueHost {
        override val match: RummyMatchState? get() = this@RummyStore.match
        override val isWorking: Boolean get() = this@RummyStore.isWorking
        override fun createRoom() = this@RummyStore.createRoom()
        override fun invite(userId: SwiftUUID) = this@RummyStore.invite(userId)
    }

    /** 사람 행 [초대]. 내 방이면 바로 초대, 방이 없으면 탁자를 열고 줄에 세운다. */
    fun inviteQueued(userID: SwiftUUID) {
        inviteQueue.invite(userID, inviteBridge)
        callingPeerIDs = inviteQueue.pending
    }

    /** 결과 [한 판 더] — 탁자를 열고 지난 판 사람들을 줄에 세운다. */
    fun createAndInvite(userIDs: List<SwiftUUID>) {
        inviteQueue.createAndInvite(userIDs, inviteBridge)
        callingPeerIDs = inviteQueue.pending
    }

    /** 동작이 끝날 때 · 판이 바뀔 때 민다(Swift `.onChange(of: isWorking)` · `.onChange(of: match?.id)`). */
    internal fun pumpInviteQueue() {
        if (inviteQueue.pending.isEmpty()) return
        inviteQueue.pump(inviteBridge)
        callingPeerIDs = inviteQueue.pending
    }

    // MARK: 내부 장부 (관찰 대상 아님)

    /** 벽시계 '지금'(서버 시각 보정·마감). 벽시계는 조립 지점에서만 만든다 — 호스트에서 빌리고, 시험이 갈아 끼운다. */
    var clock: () -> SwiftDate = { this.host?.now() ?: SwiftDate.fromReferenceDate(0.0) }

    /** 폴링 루프의 한 걸음(초). 시험은 무한으로 재우고 `pollTick` 을 직접 밟는다. */
    var pollStepSeconds: Double = 0.5

    /** 작업 상태 전송 디바운스(초). */
    var draftDebounceSeconds: Double = draftDebounceDefaultSeconds

    /** 마감 깨우기(창이 안 보여도 마감 + 유예 뒤 state 를 한 번 다시 읽는다). 시험은 끄고 `checkDeadline` 을 밟는다. */
    var deadlineWakeEnabled: Boolean = true

    var serverClockOffset: Double = 0.0
        private set
    private var hasServerClockOffset = false
    var resetGeneration: Int = 0
        private set
    var isWindowVisible: Boolean = false
        internal set

    /** 창이 완전히 가려졌다. **폴링만** 이 값을 본다. */
    var isWindowOccluded: Boolean = false
        internal set

    /** 요청 표 — state 를 돌려줄 수 있는 요청마다 보낼 때 하나씩 오른다(머리말 ④). */
    var requestTicket: Int = 0
        private set

    /** 지금 [match] 를 만든 응답의 표. */
    var appliedTicket: Int = 0
        internal set

    // 조회 직렬화.
    var stateInFlightID: SwiftUUID? = null
        internal set
    internal var pendingStateID: SwiftUUID? = null
    var stateInFlight: Boolean = false
        internal set
    internal var stateAgain = false
    var lobbyInFlight: Boolean = false
        internal set

    /** 로비 조회가 도는 중에 또 불렸다 — 끝난 뒤 **한 번 더** 읽는다(그 사이 온 초인종을 버리지 않게). */
    internal var lobbyAgain = false
    internal var rankingInFlight = false

    /** 차단 거울을 거치기 전의 로비 응답. */
    var rawLobby: RummyLobby? = null
        internal set

    /** 차단으로 걷어낸 사람(소유자가 채운다). */
    var hiddenPeerIDs: Set<SwiftUUID> = emptySet()
        internal set

    /** 서버가 말한 내 방·판 id(로비 `me.active_match_id` ?: `me.room.id`). */
    var activeMatchID: SwiftUUID? = null
        internal set

    /** 이 기기가 방·판을 새로 세우거나 떠날 때마다 오른다. 그보다 **먼저** 나간 로비 응답이 "방 없음" 을 말해도 믿지 않는다. */
    internal var matchRevision = 0
    var seenInviteIDs: Set<SwiftUUID> = emptySet()
        internal set
    var startAnnouncedIDs: Set<SwiftUUID> = emptySet()
        internal set
    var turnAnnouncedKeys: Set<String> = emptySet()
        internal set
    var finishAnnouncedIDs: Set<SwiftUUID> = emptySet()
        internal set

    /** [로비로]·나가기로 접은 판. 늦게 온 그 판의 state 가 사용자를 다시 끌고 가지 않게 한다. */
    var dismissedMatchIDs: Set<SwiftUUID> = emptySet()
        internal set

    // 편집기 · 작업 상태 전송(RummyStoreGame.kt).
    /** 지금 편집기가 선 차례. 차례가 바뀌면 편집기를 다시 세운다. */
    var editorKey: RummyEditorKey? = null
        internal set

    /** 편집기가 마지막으로 맞춘 판 seq(같은 차례에 남의 기권으로 오를 수 있다). */
    var editorSeq: Long? = null
        internal set

    /** 서버가 들고 있다고 믿는 작업 판(마지막으로 보낸 것, 새 차례면 시작 판). 같으면 다시 보내지 않는다. */
    var lastSentDraft: List<List<RummyFace>>? = null
        internal set
    var draftDebounceJob: Job? = null
        internal set

    /** 지금 나가 있는 작업 상태 전송(한 번에 하나). */
    var draftFlushJob: Job? = null
        internal set
    var draftInFlight: Boolean = false
        internal set
    internal var draftDirty = false
    internal var draftRetryCount = 0

    // 마감.
    var deadlineJob: Job? = null
        internal set
    internal var deadlineWakeKey: String? = null
    var deadlineFetchKey: String? = null
        internal set
    internal var deadlineFetchCount = 0
    internal var lastDeadlineFetchAt: SwiftDate = DISTANT_PAST

    // 동작 · 폴링 · 신호.
    /** 사용자가 누른 동작(한 번에 하나). 시험이 `actionJob?.join()` 으로 기다린다. */
    var actionJob: Job? = null
        internal set
    var pollJob: Job? = null
        private set
    private var pollToken = 0
    var syncJob: Job? = null
        private set
    private var syncPendingTrailing = false
    var lastStateRequestAt: SwiftDate = DISTANT_PAST
    var lastLobbyRequestAt: SwiftDate = DISTANT_PAST
    var lastMenuLobbyAt: SwiftDate = DISTANT_PAST
    var lastRankingRequestAt: SwiftDate = DISTANT_PAST

    /** 로그인한 내 id(소문자). 호스트가 없으면(미리보기) null — 그때는 `my_seat_no` 로 나를 찾는다. */
    internal val myUserID: String? get() = host?.session?.userID?.lowercase()

    internal fun logNotice(message: String) {
        host.notice(TAG, message)
    }

    // MARK: - 창

    /** 창을 띄우고 로비(와 가리킨 방·판)를 읽는다. [focusMatchID] 는 배너·말풍선에서 온 경로의 대상이다. */
    fun openWindow(focusMatchID: SwiftUUID?) {
        if (host?.session != null) {
            // 곧 이어질 setWindowVisible(true) 가 같은 조회를 또 쏘지 않도록 **동기로** 먼저 적는다.
            lastLobbyRequestAt = clock()
            scope.launch {
                refreshLobby()
                if (focusMatchID != null && focusMatchID != match?.id && (lobby?.invites ?: emptyList()).none { it.id == focusMatchID }) {
                    refreshMatch(focusMatchID)
                }
            }
        }
        presentWindow?.invoke()
    }

    /** 창이 보이기 시작했다(true) · 숨었거나 닫혔다(false). 폴링만 켜고 끈다 — 방·판은 창과 무관하게 서버에 있다. */
    @kotlin.jvm.JvmName("updateWindowVisible")
    fun setWindowVisible(visible: Boolean) {
        if (!visible) {
            if (isWindowVisible) isWindowVisible = false
            isWindowOccluded = false
            stopPolling()
            return
        }
        isWindowVisible = true
        isWindowOccluded = false
        startPolling()
        if (host?.session == null) return
        val now = clock()
        if (now.timeIntervalSince(lastLobbyRequestAt) >= reloadDedupeSeconds) {
            lastLobbyRequestAt = now
            scope.launch { refreshLobby() }
        }
        val current = match
        if (current != null && isUnsettled(current.status) && now.timeIntervalSince(lastStateRequestAt) >= reloadDedupeSeconds) {
            lastStateRequestAt = now
            val id = current.id
            scope.launch { refreshMatch(id) }
        }
        if (rankingEnabled && phase == RummyPhase.lobby && now.timeIntervalSince(lastRankingRequestAt) >= reloadDedupeSeconds) {
            scope.launch { loadRanking() }
        }
    }

    /** 창의 가림 상태가 바뀌었다. **폴링만** 멈추고 되살린다. */
    @kotlin.jvm.JvmName("updateWindowOccluded")
    fun setWindowOccluded(occluded: Boolean) {
        isWindowOccluded = occluded
        if (occluded) stopPolling() else startPolling()
    }

    // MARK: - 신호 · 계기 (창 밖에서 아는 길)

    /** 실시간 'rummy' 초인종(`{v, m, s}` — 내용 없음). 직렬화된 재조회 — 도는 중이면 뒤따르는 **한 번**으로 합친다. */
    fun handleSignal() {
        if (!mayReadOutsideScreen) return
        requestSync()
    }

    fun requestSync() {
        if (host?.session == null) return
        if (syncJob?.isActive == true) {
            syncPendingTrailing = true
            return
        }
        val generation = resetGeneration
        syncJob = scope.launch {
            do {
                // 루프 **안에서 먼저** 내린다. 뒤에 내리면 이번 조회가 도는 동안 도착한 신호를 지운다.
                syncPendingTrailing = false
                syncOnce()
            } while (syncPendingTrailing && generation == resetGeneration)
        }
    }

    /** 신호 한 번의 조회: 방·판에 있으면 그 state(참가·시작·차례·작업 판·정산), 아니면 로비(초대 · 내 방·판 id). */
    suspend fun syncOnce() {
        val current = match
        if (current != null && isUnsettled(current.status)) refreshMatch(current.id) else refreshLobby()
    }

    /**
     * 조인 직후·깨어남의 따라잡기: 들고 있는 방·판(끝나지 않은 것)을 먼저 다시 읽고, 로비 한 번(+ 그 응답이 가리키는 다른 방·판).
     * 로비는 들고 있는 것과 **같은 id** 면 다시 읽지 않으므로, 잠든 사이 방이 판으로 시작된 것은 여기서 안다.
     */
    suspend fun catchUp() {
        val current = match
        if (current != null && isUnsettled(current.status)) refreshMatch(current.id)
        refreshLobby()
    }

    /** 실시간 조인 성공 직후. */
    fun realtimeDidJoin() {
        if (host?.session == null || !mayReadOutsideScreen) return
        scope.launch { catchUp() }
    }

    /** 깨어남(앱이 다시 active). 소켓이 끊겼던 사이에 온 초대·차례를 한 번 따라잡는다. */
    fun systemDidWake() {
        if (host?.session == null || !mayReadOutsideScreen) return
        scope.launch { catchUp() }
    }

    /** 허브 열림(30초 스로틀). 게임 탭 배지가 이 계기와 신호에 달려 있다. */
    fun refreshLobbyIfStale() {
        if (host?.session == null || !mayReadOutsideScreen) return
        val now = clock()
        if (now.timeIntervalSince(lastMenuLobbyAt) < menuLobbyThrottleSeconds) return
        lastMenuLobbyAt = now
        scope.launch { refreshLobby() }
    }

    // MARK: - 폴링 (창이 보일 때만)

    fun startPolling() {
        if (pollJob != null || !isWindowVisible || isWindowOccluded) return
        pollToken += 1
        val token = pollToken
        pollJob = scope.launch {
            while (true) {
                delay(delayMillis(pollStepSeconds))
                if (token != pollToken || !isWindowVisible || isWindowOccluded) {
                    if (token == pollToken) pollJob = null
                    return@launch
                }
                pollTick(clock())
            }
        }
    }

    fun stopPolling() {
        pollToken += 1
        pollJob?.cancel()
        pollJob = null
    }

    /**
     * 안전망 한 걸음. **창이 안 보이면 아무것도 하지 않는다.**
     *  · 방·판에 있으면 구독 중 15초(마감 15초 안쪽은 5초) · 미구독 5초마다 그 state · 마감이 지났으면 다시
     *  · 로비·방 화면이면 30초마다 로비(사람 목록·초대) · 순위는 60초(주 스위치)
     */
    suspend fun pollTick(now: SwiftDate) {
        if (!isWindowVisible || isWindowOccluded || host?.session == null) return
        val current = match
        if (current != null && isUnsettled(current.status) && now.timeIntervalSince(lastStateRequestAt) >= matchPollInterval(now)) {
            refreshMatch(current.id)
        }
        if (!isWindowVisible) return
        checkDeadline(now)
        if (!isWindowVisible) return
        if ((phase == RummyPhase.lobby || phase == RummyPhase.room) && now.timeIntervalSince(lastLobbyRequestAt) >= lobbyPollSeconds) {
            refreshLobby()
        }
        if (!isWindowVisible) return
        if (rankingEnabled && phase == RummyPhase.lobby && now.timeIntervalSince(lastRankingRequestAt) >= rankingPollSeconds) {
            loadRanking()
        }
    }

    // MARK: - 리셋

    /**
     * 로그아웃·계정 전환. 창을 닫고 상태를 전부 비운다 — 남기면 다음 사람이 앞 사람의 방·판·랙·초대를 본다.
     * **배선 값**(`rankingEnabled` · 시계 · 주기 · 문)은 건드리지 않는다.
     */
    fun reset() {
        resetGeneration += 1
        stopPolling()
        syncJob?.cancel()
        syncJob = null
        syncPendingTrailing = false
        actionJob = null
        stateInFlight = false
        stateAgain = false
        stateInFlightID = null
        pendingStateID = null
        lobbyInFlight = false
        lobbyAgain = false
        rankingInFlight = false
        cancelDraft()
        draftFlushJob = null
        draftInFlight = false
        deadlineJob?.cancel()
        deadlineJob = null
        deadlineWakeKey = null
        deadlineFetchKey = null
        deadlineFetchCount = 0
        lastDeadlineFetchAt = DISTANT_PAST
        heartbeatJob?.cancel()
        heartbeatJob = null
        heartbeatMatchID = null
        // 판을 놓는다. `engagedMatchIDs` 는 남긴다 — 같은 사람이 다시 들어오면(토큰 만료 강제 로그아웃) 쥐던 판의 하트비트가 이어져야 한다.
        // 다른 계정에겐 `engagedOwnerUserID` 가 막는다(같은 판의 상대 계정이면 판 id 가 같다).
        setHoldingMatch(false)
        lastSentLayout = null
        lastReactionSentAt = DISTANT_PAST
        pendingOwnReactions = mutableListOf()
        seenReactionKeys = mutableSetOf()
        if (reactionFeed.isNotEmpty()) reactionFeed = emptyList()
        if (lastDraw != null) lastDraw = null
        if (rackSortMode != null) rackSortMode = null
        if (phase != RummyPhase.lobby) phase = RummyPhase.lobby
        if (availability != RummyAvailability.available) availability = RummyAvailability.available
        if (lobby != null) lobby = null
        if (lobbyLoadFailed) lobbyLoadFailed = false
        if (match != null) match = null
        if (editor != null) editor = null
        if (notice != null) notice = null
        if (rubyBalance != null) rubyBalance = null
        if (isWorking) isWorking = false
        if (ranking != null) ranking = null
        if (selectedStake != 3L) selectedStake = 3L
        if (createPublic) createPublic = false
        if (rulesShown) rulesShown = false
        rawLobby = null
        hiddenPeerIDs = emptySet()
        activeMatchID = null
        matchRevision = 0
        seenInviteIDs = emptySet()
        startAnnouncedIDs = emptySet()
        turnAnnouncedKeys = emptySet()
        finishAnnouncedIDs = emptySet()
        dismissedMatchIDs = emptySet()
        editorKey = null
        editorSeq = null
        lastSentDraft = null
        requestTicket = 0
        appliedTicket = 0
        serverClockOffset = 0.0
        hasServerClockOffset = false
        isWindowVisible = false
        isWindowOccluded = false
        lastStateRequestAt = DISTANT_PAST
        lastLobbyRequestAt = DISTANT_PAST
        lastMenuLobbyAt = DISTANT_PAST
        lastRankingRequestAt = DISTANT_PAST
        // 줄에 남은 사람은 앞 계정의 것이다 — 방이 없으니 pump 가 버린다.
        pumpInviteQueue()
        dismissWindow?.invoke()
    }

    // MARK: - 공용 관용구

    /**
     * 공용 호출 관용구: 세션 가드 → 두 세대 캡처 → withSessionRetry → 두 세대 대조.
     * null = 버린 결과(세션 없음·세대가 밀림·취소). 호출부는 null 이면 **아무것도 바꾸지 않는다.**
     * 왕복마다 한 줄(부른 함수 이름 · 결과 · 밀리초)을 남긴다 — 토큰·본문은 싣지 않는다. 코루틴 취소는 삼키지 않고 다시 던진다.
     */
    suspend fun <T> perform(label: String, operation: suspend (SupabaseWorkService, String) -> T): DuelCall<T>? {
        val host = host ?: return null
        if (host.session == null) return null
        val sessionGeneration = host.sessionGeneration
        val generation = resetGeneration
        val service = host.service
        val started = TimeSource.Monotonic.markNow()
        fun trace(outcome: String) = logNotice("rpc $label $outcome ${started.elapsedNow().inWholeMilliseconds}ms")
        return try {
            val value = host.withSessionRetry { session -> operation(service, session.accessToken) }
            if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) {
                trace("discarded")
                null
            } else {
                trace("ok")
                DuelCall.Success(value)
            }
        } catch (e: Exception) {
            if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
            if (host.sessionGeneration != sessionGeneration || generation != resetGeneration) {
                trace("discarded")
                return null
            }
            if (host.classifyAuthError(e) == AuthErrorDisposition.cancelled) {
                trace("cancelled")
                return null
            }
            trace("failed")
            DuelCall.Failure(e)
        }
    }

    /** 사용자가 누른 동작 하나를 돌린다([isWorking] 을 세우고 내린다). 이미 도는 동작이 있으면 무시한다. */
    internal fun runAction(body: suspend (RummyStore) -> Unit) {
        if (isWorking || host?.session == null) return
        isWorking = true
        val generation = resetGeneration
        actionJob = scope.launch {
            body(this@RummyStore)
            if (generation == resetGeneration) {
                if (isWorking) isWorking = false
                pumpInviteQueue()
            }
        }
    }

    /** 요청 표 하나를 뗀다(state 를 돌려줄 수 있는 요청을 **보내기 직전에**). */
    internal fun issueTicket(): Int {
        requestTicket += 1
        return requestTicket
    }

    /** 서버에 아잉 큐브 RPC 가 아직 없다(PGRST202). */
    fun isSchemaMissing(error: Throwable): Boolean = error == SupabaseWorkServiceError.DatabaseSchemaMissing

    /** 쓰기 동작이 throw 로 실패했다(5xx·오프라인·PGRST202). */
    internal fun noteActionFailure(error: Throwable) {
        if (isSchemaMissing(error)) noteServerMissing() else setNotice(RummyNoticeText.checkConnection)
    }

    internal fun noteServerMissing() {
        if (availability != RummyAvailability.serverMissing) availability = RummyAvailability.serverMissing
        setNotice(RummyNoticeText.unavailable)
    }

    internal fun noteUpdateRequired() {
        if (availability != RummyAvailability.updateRequired) availability = RummyAvailability.updateRequired
        setNotice(RummyNoticeText.updateRequired)
    }

    /** 안내줄 한 문(JVM 이름은 [notice] 의 setter 와 겹치지 않게 따로 둔다). */
    @kotlin.jvm.JvmName("updateNotice")
    fun setNotice(text: String?) {
        if (notice != text) notice = text
    }

    /** 서버가 말한 내 잔액을 스토어와 호스트 거울(나 탭·상점) 둘 다에 둔다. */
    internal fun applyRuby(value: Long?) {
        if (value == null) return
        if (rubyBalance != value) rubyBalance = value
        val host = host ?: return
        if (host.rubyBalance != value) host.rubyBalance = value
    }

    /** `server_now_ms` 로 기기 시계 어긋남을 잰다. 처음 잰 값은 그대로, 그 뒤로는 문턱(250ms) 넘게 벗어날 때만. */
    fun noteServerNow(milliseconds: Double?) {
        if (milliseconds == null || !(milliseconds > 0)) return
        val measured = milliseconds / 1000 - clock().timeIntervalSince1970
        if (hasServerClockOffset && abs(measured - serverClockOffset) < serverClockToleranceSeconds) return
        serverClockOffset = measured
        hasServerClockOffset = true
    }

    /** 서버 epoch 밀리초 → 기기 시계의 같은 순간. */
    fun deviceDate(milliseconds: Double?): SwiftDate? {
        if (milliseconds == null || !(milliseconds > 0)) return null
        return SwiftDate(milliseconds / 1000 - serverClockOffset)
    }

    /** 화면 phase 를 [match] 에서 다시 정한다. */
    internal fun refreshPhase() {
        val current = match
        val next = when (current?.status) {
            RummyMatchStatus.forming -> RummyPhase.room
            RummyMatchStatus.active -> RummyPhase.playing
            RummyMatchStatus.finished -> RummyPhase.finished
            else -> RummyPhase.lobby
        }
        if (phase != next) {
            // 화면 전환 한 줄(판 id 앞 8자만 — 사람 정보 없음).
            val shortID = current?.id?.lowercased?.take(8) ?: "-"
            logNotice("phase $phase→$next match=$shortID")
            phase = next
        }
        updateHeartbeat()
    }
}

/**
 * 편집기가 선 **차례**(판 · 차례 자리 · 차례 시작 시각). `turn_started_ms` 는 차례가 넘어갈 때마다 바뀌고 남의 기권(seq+1)에는 안 바뀐다 —
 * seq 로 가르면 남이 기권할 때마다 내 차례 작업이 지워진다.
 */
data class RummyEditorKey(
    val matchID: SwiftUUID,
    val turnSeatNo: Long?,
    val turnStartedMs: Double?,
    /** `turn_started_ms` 가 없는 옛 모양·미리보기에서만 seq 로 차례를 가른다(있으면 null). */
    val fallbackSeq: Long?,
) {
    /** 알림·마감 깨우기 키에 쓰는 글자("<판>#<차례 자리>#<차례 시작>"). */
    val text: String
        get() {
            val started = turnStartedMs?.toLong()?.toString() ?: "s${fallbackSeq ?: 0}"
            return "${matchID.lowercased}#${turnSeatNo?.toString() ?: "-"}#$started"
        }

    companion object {
        fun of(state: RummyMatchState): RummyEditorKey = RummyEditorKey(
            matchID = state.id,
            turnSeatNo = state.turnSeatNo,
            turnStartedMs = state.turnStartedMs,
            fallbackSeq = if (state.turnStartedMs == null) (state.seq ?: 0L) else null,
        )
    }
}
