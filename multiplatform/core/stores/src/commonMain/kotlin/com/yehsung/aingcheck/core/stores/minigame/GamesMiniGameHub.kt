// 원본: Sources/CheckMobileKit/Games/GamesMiniGameHub.swift @ 1b8260d
// 원본: Sources/check/WorkTimerStoreMiniGame.swift:39-85·528-880 @ 1a5eeca6 (제출 인편 — 재시작 보존 · 토큰 대기 · no_token 되살림 · [2,8,30] 백오프)
// (역대 순위 [오늘|역대] · 판 도중 토큰 갈아 끼우기(길건너)는 맥 Sources/check/WorkTimerStoreMiniGame.swift:308-331·920-1000 @ 1b8260d —
//  폰 1.0.14 허브에는 아직 없다. G §8-16·6차 지시 "길건너·역대 순위·[오늘|역대] 상태도 스토어에" 로 허브에 더했다.)
package com.yehsung.aingcheck.core.stores.minigame

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.foundation.platform.LogLevel
import com.yehsung.aingcheck.core.foundation.platform.Logger
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.fetchMiniGameAllTimeBoard
import com.yehsung.aingcheck.core.net.fetchMiniGameBoard
import com.yehsung.aingcheck.core.net.fetchMiniGamePublic
import com.yehsung.aingcheck.core.net.fetchMiniGameYesterdayWinner
import com.yehsung.aingcheck.core.net.startMiniGameRound
import com.yehsung.aingcheck.core.net.submitMiniGameScore
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.rules.text.BlockReportRules
import com.yehsung.aingcheck.core.rules.text.ServiceErrorFacts
import com.yehsung.aingcheck.core.stores.games.GamesMiniGameText
import com.yehsung.aingcheck.core.stores.games.GamesPlayController
import com.yehsung.aingcheck.core.stores.games.MobileLoadKnowledge
import com.yehsung.aingcheck.core.stores.tetris.delayMillis
import com.yehsung.aingcheck.core.wire.SupabaseWorkServiceError
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.MiniGameAllTimeEntry
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardEntry
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardScope
import com.yehsung.aingcheck.core.wire.models.MiniGameWinner
import com.yehsung.aingcheck.core.wire.models.sortedForMiniGameAllTimeBoard
import com.yehsung.aingcheck.core.wire.models.sortedForMiniGameBoard
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlin.coroutines.cancellation.CancellationException

/** 한 게임의 오늘 순위 칸. */
data class GamesMiniGameBoard(
    val entries: List<MiniGameBoardEntry> = emptyList(),
    val yesterdayWinner: MiniGameWinner? = null,
    /** 이번 로그인에서 한 번이라도 받았다(빈 목록을 "아직 모른다"와 가른다). */
    val loaded: Boolean = false,
    val loading: Boolean = false,
    val failed: Boolean = false,
) {
    /**
     * 오늘 한 사람 수를 **안다**(정족수 줄 "오늘은 아직 아무도 안 했어요 · 5명부터 지급"을 그려도 된다).
     * 줄이 하나라도 있으면 적어도 그만큼은 했다. 비어 있으면 받은 적이 있고 마지막 조회가 실패하지 않았을 때만 0명이다 —
     * 불러오지 못한 순위를 "아무도 안 했다"로 말하지 않는다(games-verify: 실패 카드에 두 말이 함께 떴다).
     */
    val knowsPlayerCount: Boolean get() = MobileLoadKnowledge.knowsCount(entries.isNotEmpty(), loaded, failed)

    /** 빈 순위 자리를 무엇으로 채우는가(공용 규칙 — 순위 탭 미니게임 판과 같다). */
    val placeholder: MobileLoadKnowledge.Placeholder get() = MobileLoadKnowledge.placeholder(entries.isNotEmpty(), loaded, failed)
}

/**
 * 아직 서버가 받았다고 확인해 주지 않은 끝난 판 한 건 — **제출 인편**(맥 `MiniGamePendingSubmit`, 영속하므로 타입이다).
 *
 * [token] 이 null 이면 **토큰을 기다리는 인편**이다 — 판이 끝난 순간 토큰이 없었다(왕복이 늦었거나 못 받았다). 왕복 중이던 응답이나 새 요청이 채운다.
 * [attempts] 는 실패 횟수(백오프 단계)이고 영속한다 — 재시작이 백오프를 0 으로 되돌리지 않게. [nextRetryAt]·[heldUntilTrigger] 는 영속하지 않는다 — 재시작은 그 자체가 방아쇠다.
 * [recoveredFromDeadTokenOnce]: `no_token` 을 받아 토큰을 기다리는 인편으로 한 번 되돌렸다. 영속한다 — 재시작이 이 기회를 새로 주면 안 된다. 두 번은 주지 않는다:
 * 계속 `no_token` 이면 원인이 경합이 아니므로 두드려도 같은 답이고 무한 왕복이 된다(서버 시간 하한은 새 토큰의 started_at 부터 다시 재므로 그대로 선다).
 */
data class GamesPendingSubmit(
    val id: Long,
    val kind: MiniGameKind,
    val score: Int,
    val token: String?,
    val tokenIssuedAt: SwiftDate?,
    val recordedAt: SwiftDate,
    val attempts: Int = 0,
    val recoveredFromDeadTokenOnce: Boolean = false,
    val nextRetryAt: SwiftDate? = null,
    val heldUntilTrigger: Boolean = false,
) {
    /** 이 인편이 죽는 시각 — 토큰 발급 시각과 판이 끝난 시각 중 이른 쪽 + TTL. 토큰 없는 인편도 30분이 지나면 다른 날 순위표에 올라갈 수 있어 같은 수명이다. */
    fun deadline(ttlSeconds: Double): SwiftDate = minOf(recordedAt, tokenIssuedAt ?: recordedAt).addingTimeInterval(ttlSeconds)

    fun isExpired(now: SwiftDate, ttlSeconds: Double): Boolean = now >= deadline(ttlSeconds)
}

/** 인편의 영속 꼴(시각은 1970 기준 초). 기다림 표식 둘은 싣지 않는다. */
@Serializable
private data class GamesPendingSubmitRow(
    val id: Long,
    val kind: String,
    val score: Int,
    val token: String? = null,
    val tokenIssuedAt: Double? = null,
    val recordedAt: Double,
    val attempts: Int = 0,
    val recoveredFromDeadTokenOnce: Boolean = false,
)

/**
 * 미니게임 허브(SPEC-ios §3.5) — 오늘 순위 · 로컬 최고 · 라운드 토큰 · 점수 제출 · 공개 여부. 맥 `WorkTimerStoreMiniGame` 의
 * 흐름을 폰 세션 위에 다시 썼다.
 *
 * 라운드 토큰 흐름(맥과 같다 — 기억 minigame-round-token-race)
 * 1. **화면을 열 때 미리 받는다**([openScreen]). 판 시작에 받으면 플래피 즉사처럼 1초 안에 끝나는 판은 왕복이 못 끝나
 *    점수를 통째로 버린다. 일찍 받을수록 서버가 재는 경과가 길어져 **더 관대하다**(정직한 플레이를 못 막는다).
 * 2. 판이 시작될 때 쓸 수 있는 토큰이 없으면(선발급 실패·재사용 나이 지남) 그때 받는다. 게임을 막지 않는다(코루틴으로 띄운다).
 * 3. 판이 끝나면 토큰을 **로컬에서 먼저 비우고** 제출한다(한 토큰에 한 점수). 성공이든 거절이든 다음 토큰을 미리 받는다.
 * 4. 들고 있는 토큰이 쓸 만하면 다시 받지 않는다 — 다시 받으면 서버가 started_at 을 now() 로 되돌려 벌어 둔 여유가 사라진다.
 * 5. 늦게 온 토큰 응답은 버린다([roundGeneration]). 서버는 (사용자, 게임)당 미사용 토큰을 한 행만 두고 갈아 끼운다.
 * 6. `minigame_public == false` 면 토큰도 제출도 없다(설정 문구가 약속한 "올라가지도 않아요").
 * ★ 불변식: **그 게임의 인편(제출 대기)이 살아 있는 동안 그 게임의 `start_round` 는 나가지 않는다**(제출이 든 토큰이 그 자리에서
 *   죽는다 — 0.3.39 수리). 선발급([prefetchRoundToken])·판 시작([beginRound])·판 도중 갈아 끼우기([keepRoundTokenFresh]) 세 문이 모두
 *   이 가드를 지난다. 시험: `MiniGameRoundTokenRaceTest`.
 *
 * 폰 규칙: 앱이 background 로 가거나 화면을 떠나면 판을 **끝낸다**(`endRound()`). 타이밍 바·플래피는 기록 없이 버리고,
 * **테트리스·길건너는 여기까지의 점수로 확정해 제출한다**. 로그아웃([reset])과 화면 경합 정리([openScreen])는 **`abandon()` 그대로**다.
 *
 * 제출 인편([pendingSubmits] — 맥 `miniGamePendingSubmits`): 판이 끝나면 제출을 시도하기 **전에** 적는다. 지우는 것은 `ok`·`token_used`·terminal 거절·TTL 뿐이고
 * 네트워크 실패·`too_fast`·모르는 status 는 남긴다. 칸 하나가 아니라 **대기열**이다(토큰을 실은 인편은 게임당 하나뿐 — 나머지는 토큰을 기다린다) ·
 * [KeyValueStore][com.yehsung.aingcheck.core.foundation.platform.KeyValueStore] 에 **계정별**로 영속한다(남의 점수를 내 이름으로 올리지 않는다 · 앱이 죽어도 점수가 남는다) ·
 * 30분(서버 TTL)을 넘긴 인편은 읽을 때 버린다. 미는 방아쇠: 앱 복귀 · 화면 열기 · 그 게임의 선발급/판 시작 직전 · 실패 뒤 백오프(2초 → 8초 → 30초 반복).
 * 진단: 거절 status 이름까지만 로그에 남긴다 — need_seconds·elapsed_seconds 는 화면에도 로그에도 쓰지 않는다(위조 보조 도구).
 *
 * Android 몫(G §2-3 W2-e ④): 허브는 [MiniGameExposure.visible] 밖의 게임을 열지 않고 순위도 당기지 않는다(골든이 초록인 게임만).
 */
class GamesMiniGameHub(val context: GamesMiniGameContext, var logger: Logger? = null) {
    companion object {
        /**
         * 토큰을 새로 받는 기준(초). 서버 TTL 30분보다 넉넉히 짧다(맥 `miniGameTokenRefreshSeconds`).
         *
         * INV-GamesMiniGameHub-dff4c5c4 이식: v0.3.38 부터 **게임별**이다 — 판정은 `MiniGameKind.roundTokenReuseSeconds` 한 곳에서 나온다
         * (테트리스 12분 · 길건너 2분). 이 상수는 기존 두 게임의 값(20분)을 가리키는 별명으로 남긴다: 여기를 고쳐도 테트리스는 안 움직인다.
         */
        val tokenRefreshSeconds: Double = MiniGameKind.flappy.roundTokenReuseSeconds

        /** 판 도중 토큰 감시 간격(초 — 맥 `MiniGamePanel.tokenKeeperInterval`). [runRoundTokenKeeper] 가 이만큼 자고 한 번 본다. */
        const val tokenKeeperIntervalSeconds: Double = 30.0

        /** 첫 화면 카드(오늘 최고·순위)를 다시 읽는 간격(초). */
        const val summaryThrottleSeconds: Double = 60.0

        /**
         * 한 판의 **벽시계 상한**(초 · 폰 테트리스만). [beginRound] 가 구동기에 건넨다.
         * 검산: 토큰 재사용 12분 + 판 15분 + 제출 여유 1분 = 28분 < 서버 TTL 30분. 15분은 시뮬 최장 판 8.7분의 1.72배라 정직한 판은
         * 안 걸린다. 엔진의 **고의 늘어뜨리기 상계가 24.7분**이라 상한이 없으면 24분을 쌓아 올린 판이 통째로 거절된다.
         * 사용자 스위치로 주지 않는다(2026-09-15 '자동 종료는 사용자 스위치로 주지 않는다').
         */
        const val tetrisRoundLimitSeconds: Double = 15.0 * 60

        /**
         * 서버가 **명시적으로 거절**한 status. 이걸 받으면 그 토큰으로는 영영 못 올리므로 제출 인편을 지운다.
         * (`token_used` 는 여기 없다 — 그건 **성공**이다.)
         *
         * INV-GamesMiniGameHub-a9138931 이식: `unauthorized`·`no_profile` 도 여기다. 둘은 **토큰이 아니라 호출자 쪽 거절**이라
         * 스스로 `token_expired` 로 바뀌지 않는다. 지우지 않으면 인편이 남아 **앱을 켤 때마다 영원히** 같은 토큰을 다시 보낸다
         * (그 사이 선발급은 인편 가드에 막혀 그 게임의 새 토큰도 못 받는다). 다만 [deadTokenStatuses] 에는 넣지 않는다.
         */
        val terminalSubmitStatuses: Set<String> = setOf("invalid", "no_token", "token_expired", "unauthorized", "no_profile")

        /**
         * 서버가 **"아직 이르다"**로 되돌린 status — 토큰이 살아 있어 같은 토큰으로 다시 보내면 통과한다.
         *
         * INV-GamesMiniGameHub-72557e51 이식: `too_fast` 는 거절이 아니다. `minigame_submit_score` 는 이 응답을 **`used_at` 을 찍기 전에**
         * 돌려주고 판정에 쓰는 경과는 단조증가한다 — 조금 뒤 같은 토큰으로 보내면 같은 점수가 통과한다. terminal 에 두면 올라갈 점수를
         * 버린다. 정직한 판이 닿는 까닭: 타이밍바 하한과 실제 소요의 여유가 **0.1906초**뿐이다.
         */
        val retryableSubmitStatuses: Set<String> = setOf("too_fast")

        /**
         * 실패 뒤 백오프 간격(초 — 맥 `miniGamePendingRetryDelays`). n번째 실패 뒤 n번째 값을 기다리고, 끝을 넘기면 마지막 값을 반복한다([pendingSubmitTtlSeconds] 안에서만).
         *
         * INV-GamesMiniGameHub-1b3e0aef 이식: 서버가 같이 주는 `need_seconds`·`elapsed_seconds` 로 지연을 **계산하지 않는다** — 클라가
         * 그 숫자로 재시도 타이밍을 계산하면 그게 곧 위조 보조 도구다(응답 칸은 읽지도 않는다 — 구조 시험이 이 파일에 그 이름이 없음을 잰다).
         * `too_fast` 도 이 표를 탄다(맥과 같다 — iOS 의 '두 번 뒤 포기'를 따르지 않는다: 판 도중 토큰을 갈아 끼운 직후 끝난 길건너 판은 하한까지 몇 분이 걸려 두 번으로는 못 넘는다).
         */
        val pendingRetryDelaysSeconds: List<Double> = listOf(2.0, 8.0, 30.0)

        /** 인편의 수명(초) = 서버 토큰 TTL(`minigame_round_ttl()` 30분). 넘긴 인편은 토큰이 죽었으므로 읽을 때 버린다. */
        const val pendingSubmitTtlSeconds: Double = 30.0 * 60

        /** 토큰이 죽어 **그 판은 영영 못 올리는** 거절. 문구가 "다시 해 주세요"(복구된다는 뜻)와 갈린다. */
        val deadTokenStatuses: Set<String> = setOf("no_token", "token_expired")

        internal const val TAG: String = "minigame"

        /** 로컬 최고 키 — **계정별**(같은 폰을 다른 계정이 쓰면 남의 최고를 물려받지 않는다). */
        fun bestKey(userID: String?, kind: MiniGameKind): String = "aing.minigame.best.${userID ?: "local"}.${kind.rawValue}"

        /** 제출 인편의 영속 키. **계정별**이다(남의 점수를 내 이름으로 올리지 않는다). */
        fun pendingKey(userID: String): String = "aing.minigame.pending.$userID"

        /** 화면을 닫아 둔 사이에 인편이 TTL 로 죽었다는 표식(다음에 화면을 열 때 한 번 말한다). 계정별. */
        fun lostNoticeKey(userID: String): String = "aing.minigame.lostnotice.$userID"

        private val pendingJson = Json { ignoreUnknownKeys = true }
    }

    /** 기다리기(시험은 가상 시간이라 그대로 둔다 — Swift `sleep` 주입 자리). */
    var sleep: suspend (Double) -> Unit = { seconds -> delay(delayMillis(seconds)) }

    /** 지금 열려 있는 게임 화면(없으면 null). */
    var activeKind: MiniGameKind? by mutableStateOf(null)
        private set

    /** 열린 화면의 엔진 구동기. 화면마다 새로 만든다. */
    var controller: GamesPlayController? by mutableStateOf(null)
        private set
    var boards: Map<MiniGameKind, GamesMiniGameBoard> by mutableStateOf(emptyMap())
        private set

    /**
     * 내 순위 공개 여부(profiles.minigame_public). 이번 로그인에서 아직 모르면 공개로 본다(맥과 같다 — 컬럼 없는 서버).
     * 한 번 안 값은 조회 실패로 바뀌지 않는다([refreshPublic]).
     */
    var isPublic: Boolean by mutableStateOf(true)
        private set

    /** 제출 실패·판 끝남 안내 한 줄. */
    var submitNotice: String? by mutableStateOf(null)
        private set

    /** 로컬 최고(계정별 — 관찰용 미러). 읽기는 [best]. */
    var localBest: Map<MiniGameKind, Long> by mutableStateOf(emptyMap())
        private set

    // MARK: 역대 순위(v0.3.67 — 맥 WorkTimerStore.swift:650-678 의 칸) — 지금 연 게임([activeKind]) 한 판

    /**
     * 순위 열이 보여 주는 판 [오늘 | 역대]. **앱이 떠 있는 동안만** 기억한다 — 영속하지 않고, 로그아웃도 되돌리지 않는다(계정이 아니라
     * 이 앱 실행의 보기 선택이다). 어제 1등 카드·상금 안내는 오늘 판에만 있다.
     */
    var boardScope: MiniGameBoardScope by mutableStateOf(MiniGameBoardScope.today)
        private set

    /** 지금 연 게임의 **역대** 최고 순위(사람마다 한 줄 — `minigame_alltime_board`). 3플래그 규약은 오늘 순위와 같다. */
    var allTimeBoard: List<MiniGameAllTimeEntry> by mutableStateOf(emptyList())
        private set
    var allTimeLoaded: Boolean by mutableStateOf(false)
        private set
    var allTimeLoading: Boolean by mutableStateOf(false)
        private set
    var allTimeFailed: Boolean by mutableStateOf(false)
        private set

    /**
     * 서버에 함수가 아직 없다(PGRST202 · 본문 없는 404 — 앱이 db push 보다 먼저 나간 창). **실패가 아니다** — [다시 시도] 없이
     * "준비 중" 한 줄을 그린다(사용자가 고칠 수 없는 일에 실패 문구를 쓰지 않는다).
     */
    var allTimeUnavailable: Boolean by mutableStateOf(false)
        private set

    /** 지금 들고 있는 역대 표가 **어느 게임의 최신 응답인가.** null 이면 다음에 [역대] 를 열 때 다시 받는다. 관찰 대상 아님. */
    var allTimeFreshKind: MiniGameKind? = null
        private set

    /** 역대 표가 **낡았다고 표시된 횟수**(판 기록 · 게임 전환이 올린다). 받기를 시작할 때 쥐고, 응답 때 올랐으면 '최신' 표시를 안 세운다. */
    private var allTimeInvalidation = 0

    /** 역대 표 받기의 일련번호와, 마지막으로 **반영한** 받기의 번호. 늦게 닿은 옛 받기가 새 받기의 표를 덮지 않게 한다. */
    private var allTimeFetchSerial = 0
    private var allTimeAppliedSerial = 0

    /** 지금 [allTimeBoard] 가 어느 게임의 표인가(로컬 최고 합산용). */
    private var allTimeBoardKind: MiniGameKind? = null

    // MARK: 토큰(관찰 대상 아님)

    var roundToken: String? = null
        private set
    var roundTokenKind: MiniGameKind? = null
        private set
    var roundTokenAt: SwiftDate? = null
        private set
    var roundGeneration: Int = 0
        private set

    /**
     * 지금 왕복 중인 토큰 요청의 게임(없으면 null). 선발급이 도는 중에 판이 시작되면 **또 요청하지 않는다** —
     * 또 보내면 서버가 started_at 을 새로 찍어 앞 요청이 벌어 둔 여유를 버린다(폰에서 화면을 열자마자 탭하는 경로).
     */
    var roundTokenInFlightKind: MiniGameKind? = null
        private set

    /**
     * 제출 인편 대기열(지금 계정 것 — 받은 순서). 읽고 쓰는 문은 아래 인편 절 하나다(영속과 어긋나지 않게). 화면은 이 값을 그리지 않는다.
     * ★ 불변식(머리 주석): 이 목록에 그 게임이 있는 동안 그 게임의 `start_round` 는 나가지 않는다 — 토큰을 기다리는 맨 앞 인편에 받아 줄 때만 빼고.
     */
    var pendingSubmits: List<GamesPendingSubmit> = emptyList()
        private set

    /** 맨 앞 인편(없으면 null). 시험·진단용. */
    val pendingSubmit: GamesPendingSubmit? get() = pendingSubmits.firstOrNull()

    /** 메모리의 인편이 **어느 계정 것인가**(null = 아직 안 읽었거나 로그아웃). 계정이 바뀌면 그 계정의 키에서 다시 읽는다. */
    private var pendingOwner: String? = null
    private var nextPendingID: Long = 1

    /** 지금 제출 왕복이 떠 있는 게임들(같은 토큰을 두 번 동시에 보내지 않게). */
    private val submittingKinds = HashSet<MiniGameKind>()

    /** 지금 제출 왕복이 떠 있다. */
    val isSubmitting: Boolean get() = submittingKinds.isNotEmpty()

    /** 백오프 타이머 한 개 — 가장 먼저 돌아오는 인편에 맞춘다. */
    private var pendingRetryJob: Job? = null

    /** 출구에서 세운 안내("앱을 나가서 …")를 **비동기 제출 성공이 지우지 않게** 붙든다. */
    private var exitNoticeIsSticky = false
    private var resetGeneration = 0
    private var lastSummaryAt: SwiftDate? = null

    /** 엔진 시드 — 화면을 열 때마다 달라야 같은 판이 반복되지 않는다(데모 고정 시계에서도). */
    private var seedCounter: ULong = 0u

    /**
     * 이 빌드의 허브가 여는 게임(첫 화면 타일 · 오늘 순위 · openScreen). 기본은 폰 노출([MiniGameExposure.visible])이고,
     * 데스크톱 조립은 [MiniGameExposure.desktopVisible] 을 건넨다(지금은 같은 목록).
     */
    var visibleKinds: List<MiniGameKind> = MiniGameExposure.visible

    private val isSignedIn: Boolean get() = context.sessionStore.isSignedIn
    private val myUserID: String? get() = context.sessionStore.session?.userID?.lowercase()

    private fun log(message: String) {
        logger?.log(LogLevel.INFO, TAG, message)
    }

    // MARK: 화면

    /** 게임 화면이 열렸다. 오늘 순위·어제 1등·공개 여부를 읽고 **토큰을 미리 받는다**. 이 빌드에 보이지 않는 게임이면 아무것도 안 한다. */
    fun openScreen(kind: MiniGameKind) {
        if (kind !in visibleKinds) return
        if (activeKind == kind && controller != null) return
        // 화면 경합 정리는 **버리는 것**이다(`abandon()`) — 사람이 쌓아 올린 판을 끝내는 자리가 아니다.
        controller?.abandon()
        if (allTimeBoardKind != null && allTimeBoardKind != kind || activeKind != null && activeKind != kind) {
            // 게임이 바뀌었다 — 앞 게임의 역대 1등이 '이 게임 1등인 척' 보이면 안 된다(맥 selectMiniGame 의 역대 절).
            clearAllTime(invalidate = true)
        }
        activeKind = kind
        submitNotice = null
        exitNoticeIsSticky = false
        // 화면을 닫아 둔 사이에 죽은 점수가 있으면 **여기서 한 번 말하고 표식을 지운다**(아래 밀기가 문구를 덮기 전에).
        showLostNoticeIfAny()
        seedCounter += 1u
        val millis = (context.clock.now().timeIntervalSince1970 * 1000).toLong().toULong()
        val seed = millis + seedCounter * 0x9E37_79B9_7F4A_7C15uL
        val next = GamesPlayController(kind, seed)
        next.onStarted = { beginRound(kind) }
        next.onFinished = { score -> recordScore(kind, score) }
        controller = next
        loadLocalBest(kind)
        if (!isSignedIn) return
        if (boardScope == MiniGameBoardScope.allTime && !allTimeLoaded) allTimeLoading = true
        val generation = resetGeneration
        context.scope.launch {
            // 공개 여부를 **먼저** 안다 — 끈 사람에게 토큰을 받아 두지 않는다. 그 왕복 동안 판이 시작되면 `beginRound` 가
            // (아직 공개로 보고) 토큰을 받는다: 제출은 끝날 때 다시 공개 여부를 보므로 끈 사람의 점수는 여전히 안 나간다.
            refreshPublic()
            if (generation != resetGeneration || activeKind != kind) return@launch
            // 인편이 남아 있으면 **먼저 밀어낸다.** 선발급은 살아 있는 인편을 보면 스스로 비켜서므로 여기서 인편을 풀어 두지 않으면
            // 사람이 탭할 때까지 토큰이 없다. 비워지는 순간 `performSubmit` 의 꼬리가 새 토큰을 받아 주므로 대개 첫 탭 전에 준비가 끝난다.
            retryPendingSubmitIfAny()
            prefetchRoundToken(kind)
            loadBoard(kind, withWinner = true)
            // [역대] 를 보던 채로 다시 열면 역대 표도 새로 받는다(다른 기기에서 세운 기록·남의 새 기록) — 선발급·오늘 순위 **뒤**다.
            if (boardScope == MiniGameBoardScope.allTime && activeKind == kind) performLoadAllTimeBoard()
        }
    }

    /**
     * 게임 화면을 떠났다. 진행 중인 판은 **끝낸다**(`endRound()` — 테트리스·길건너는 여기까지의 점수로 확정 제출).
     * 토큰은 들고 있는다(재사용 나이 안에 다시 열면 그대로 쓴다). 안내 한 줄은 세우지 않는다.
     */
    fun closeScreen(kind: MiniGameKind) {
        if (activeKind != kind) return
        controller?.endRound()
        controller = null
        activeKind = null
    }

    /** 앱이 background 로 간다 — 판은 끝. 기존 두 게임은 제출하지 않고, **테트리스·길건너는 여기까지의 점수로 확정 제출한다**. */
    fun appDidEnterBackground() {
        val controller = controller ?: return
        when (controller.endRound()) {
            GamesPlayController.EndOutcome.None -> return
            GamesPlayController.EndOutcome.Abandoned -> {
                submitNotice = GamesMiniGameText.endedInBackground(controller.kind)
                exitNoticeIsSticky = false
            }
            is GamesPlayController.EndOutcome.Confirmed -> {
                // 이 줄에 닿기 전에 `endRound()` 안에서 `recordScore` 가 이미 돌았다.
                //  · 인편에 적혔으면 "여기까지 기록했어요" 가 참이다 — 비동기 성공이 못 지우게 붙든다(거절은 지운다).
                //  · 공개를 끈 사람·로그아웃은 인편이 없다 — 안내만 세운다.
                val pending = hasPendingSubmit(controller.kind)
                if (!pending && isPublic && isSignedIn) return
                submitNotice = GamesMiniGameText.endedInBackground(controller.kind)
                exitNoticeIsSticky = pending
            }
        }
    }

    /** 로그아웃·치명 만료. 계정에 묶인 값을 전부 비운다. 여기는 **`abandon()` 그대로**다 — 앞 사람의 판을 제출하면 안 된다. */
    fun reset() {
        resetGeneration += 1
        roundGeneration += 1
        controller?.abandon()
        controller = null
        activeKind = null
        boards = emptyMap()
        isPublic = true
        submitNotice = null
        exitNoticeIsSticky = false
        localBest = emptyMap()
        roundToken = null
        roundTokenKind = null
        roundTokenAt = null
        roundTokenInFlightKind = null
        // 인편은 **메모리에서만** 비운다. 영속본은 그 계정의 키에 그대로 남는다 — 같은 사람이 30분 안에 돌아오면 이어서 올린다(남의 계정으로는 키가 달라 안 나간다).
        // 백오프 타이머도 거둔다(다음 사람의 세션으로 밀면 안 된다).
        pendingSubmits = emptyList()
        pendingOwner = null
        submittingKinds.clear()
        pendingRetryJob?.cancel()
        pendingRetryJob = null
        lastSummaryAt = null
        // 역대 순위도 남의 행이라 계정에 묶인다. 보기 선택([boardScope])은 앱 실행의 것이라 그대로 둔다(맥과 같다).
        clearAllTime(invalidate = true)
        allTimeLoading = false
    }

    // MARK: 첫 화면 카드

    /**
     * 첫 화면이 보였다: **이 빌드에 보이는 게임**([MiniGameExposure.visible] — 폰 노출 ∩ 골든 초록)의 오늘 순위를 읽는다. 60초 스로틀.
     * 안 보이는 게임까지 돌면 폰이 쓰지 않는 순위표를 60초마다 한 번씩 더 받아 온다.
     */
    fun refreshSummariesIfStale() {
        if (!isSignedIn) return
        val now = context.clock.now()
        val last = lastSummaryAt
        if (last != null && now.timeIntervalSince(last) < summaryThrottleSeconds) return
        lastSummaryAt = now
        for (kind in visibleKinds) {
            loadLocalBest(kind)
            context.scope.launch { loadBoard(kind, withWinner = false) }
        }
    }

    /** 오늘 내 순위(1부터). 순위표에 없으면 null. */
    fun myRank(kind: MiniGameKind): Int? {
        val me = myUserID ?: return null
        val index = boards[kind]?.entries?.indexOfFirst { it.userID == me } ?: return null
        return if (index < 0) null else index + 1
    }

    /** 오늘 내 순위표 점수(없으면 null). */
    fun myTodayBest(kind: MiniGameKind): Long? {
        val me = myUserID ?: return null
        return boards[kind]?.entries?.firstOrNull { it.userID == me }?.bestScore
    }

    /** 역대 표의 내 점수(지금 든 표가 그 게임의 것일 때만). */
    fun myAllTimeBest(kind: MiniGameKind): Long? {
        val me = myUserID ?: return null
        if (allTimeBoardKind != kind) return null
        return allTimeBoard.firstOrNull { it.userID == me }?.bestScore
    }

    /** 결과 카드의 "최고 N" — 로컬 최고 · 오늘 내 행 · 역대 내 행 중 큰 쪽(맥 허브와 같다 — MiniGamePanel 의 best). */
    fun best(kind: MiniGameKind): Long = maxOf(localBest[kind] ?: 0L, myTodayBest(kind) ?: 0L, myAllTimeBest(kind) ?: 0L)

    // MARK: 토큰 · 제출

    /** 들고 있는 토큰이 이 게임에 **지금** 쓸 만한가. 나이 기준은 **게임별**이다(MiniGameKind.roundTokenReuseSeconds). */
    fun hasUsableRoundToken(kind: MiniGameKind): Boolean {
        val issued = roundTokenAt
        if (roundToken == null || roundTokenKind != kind || issued == null) return false
        return context.clock.now().timeIntervalSince(issued) < kind.roundTokenReuseSeconds
    }

    /**
     * 토큰을 미리 받는다(화면 열기 · 제출 뒤). 쓸 만한 토큰이 있으면 다시 받지 않는다.
     */
    fun prefetchRoundToken(kind: MiniGameKind) {
        if (!isPublic || !isSignedIn) return
        // INV-GamesMiniGameHub-22dafde9 이식: 그 게임의 **인편이 살아 있으면 받지 않고 인편부터 민다.** 서버는 (사용자, 게임)당
        //   미사용 토큰을 한 행만 두고 새 요청이 오면 갈아 끼운다 — 제출이 네트워크로 실패한 직후 여기서 새 토큰을 받으면 재시도는
        //   `no_token` 을 받는다. 막힌 채로 굳지 않는다: 인편이 비워지는 순간 `performSubmit` 의 꼬리가 여기를 다시 불러 새 토큰을 받는다.
        if (hasPendingSubmit(kind)) {
            retryPendingSubmitIfAny()
            return
        }
        if (hasUsableRoundToken(kind)) return
        if (roundTokenInFlightKind == kind) return
        requestRoundToken(kind)
    }

    /** 판이 시작됐다(엔진 onStarted). 쓸 만한 토큰이 없을 때만 받는다 — 게임은 기다리지 않는다. */
    fun beginRound(kind: MiniGameKind) {
        // 판 벽시계 상한은 **가드보다 먼저** 건다: 순위 공정성 장치라 공개 여부·로그인과 무관하다.
        // INV-GamesMiniGameHub-848cbf11 이식: **길이를 건넨다(절대 시각이 아니다).** 마감을 재는 축은 구동기의 `tick` 하나뿐인데 그 `now` 는
        //   화면 프레임 시계다 — 여기서 주입 시계로 찍으면 두 축이 섞여 시계를 주입한 빌드(데모·시험)에서 판이 첫 프레임에 죽는다.
        controller?.roundLimitSeconds = if (kind == MiniGameKind.tetris) tetrisRoundLimitSeconds else null
        exitNoticeIsSticky = false
        if (!isPublic || !isSignedIn) return
        submitNotice = null
        if (hasUsableRoundToken(kind)) return
        // INV-GamesMiniGameHub-71a14b0b 이식: 이 게임의 인편이 살아 있으면 토큰을 받는 대신 **인편부터 밀어낸다**. 이번 판이 토큰 없이 시작될 수는 있다 —
        //   그러면 이 판의 점수는 토큰을 기다리는 인편이 되어 앞 인편이 비워진 뒤 토큰을 받는다. 앞 판을 확실히 버리는 것보다 싸다.
        if (hasPendingSubmit(kind)) {
            retryPendingSubmitIfAny()
            return
        }
        if (roundTokenInFlightKind == kind) return
        requestRoundToken(kind)
    }

    /**
     * 판 도중 토큰 갈아 끼우기(v0.3.67 — 길건너처럼 끝이 정해지지 않은 판, 맥 `keepMiniGameRoundTokenFresh`). 판이 도는 동안 화면의 토큰
     * 감시가 30초마다 부른다. 들고 있는 그 게임의 토큰이 `roundTokenMidRunRefreshSeconds` 보다 늙었으면 새로 받는다. 아무것도 안 하는 자리:
     *  · 그 게임이 갈아 끼우지 않는 게임이다(null — 길건너만 20분) · 아직 젊다 · 이미 왕복 중이다.
     *  · **그 게임의 인편이 살아 있다** — 불변식: 새 토큰을 받는 순간 인편이 든 옛 토큰이 죽는다. 인편을 먼저 민다.
     * 들고 있는 토큰이 아예 없으면(판 시작 왕복이 실패했다) 받는다 — 그 판이 끝나기 전에 쥐어야 한다.
     */
    fun keepRoundTokenFresh(kind: MiniGameKind, now: SwiftDate = context.clock.now()) {
        val limit = kind.roundTokenMidRunRefreshSeconds ?: return
        if (!isSignedIn || !isPublic) return
        if (hasPendingSubmit(kind)) {
            retryPendingSubmitIfAny()
            return
        }
        if (roundTokenInFlightKind == kind) return
        val issued = roundTokenAt
        if (roundToken != null && roundTokenKind == kind && issued != null && now.timeIntervalSince(issued) < limit) return
        log("round token refreshed mid-run game=${kind.rawValue}")
        requestRoundToken(kind)
    }

    /**
     * 판 도중 토큰 감시(맥 `MiniGamePanel.armTokenKeeper` · MiniGamePanel.swift:1199). 화면이 판이 도는 동안 띄우고, 판이 끝나거나 화면이 사라지면 거둔다.
     * [tokenKeeperIntervalSeconds] 마다 [keepRoundTokenFresh] 를 부른다. 갈아 끼우지 않는 게임이면 곧장 돌아온다. 정지 중에도 돈다 — 멈춰 둔 동안에도 서버 TTL 은 흐른다.
     * 이 감시가 없으면 28분을 넘긴 길건너 판은 `token_expired` 로 점수를 잃는다.
     */
    suspend fun runRoundTokenKeeper(running: GamesPlayController) {
        val kind = running.kind
        if (kind.roundTokenMidRunRefreshSeconds == null) return
        while (true) {
            sleep(tokenKeeperIntervalSeconds)
            if (controller !== running || !running.isPlaying) return
            keepRoundTokenFresh(kind)
        }
    }

    private fun requestRoundToken(kind: MiniGameKind) {
        // 들고 있던 것은 버린다 — 서버가 행을 갈아 끼우므로 새 요청이 나가는 순간 죽는다.
        roundToken = null
        roundTokenKind = null
        roundTokenAt = null
        roundGeneration += 1
        roundTokenInFlightKind = kind
        val generation = roundGeneration
        context.scope.launch { performStartRound(kind, generation) }
    }

    suspend fun performStartRound(kind: MiniGameKind, requested: Int) {
        try {
            if (!isSignedIn) return
            val sessionGeneration = context.generation
            val service = context.service
            try {
                val response = context.withSessionRetry { session -> service.startMiniGameRound(session.accessToken, kind.rawValue) }
                if (sessionGeneration != context.generation) return
                // INV-GamesMiniGameHub-f4222af8 이식: 늦게 온 응답은 버린다 — 내 뒤에 나간 요청이 있었다면 내 토큰은 이미 죽었다.
                if (requested != roundGeneration) return
                val token = response.token
                if (response.status != "ok" || token == null) {
                    log("round token refused status=${response.status} game=${kind.rawValue}")
                    deferPendingTokenWait(kind)
                    return
                }
                // 토큰을 기다리는 인편이 있으면 **그 인편이 먼저 받는다**(살아 있는 판보다 앞). 이 요청은 그 판이 시작될 때 나간 것이라 서버의 started_at 이 그 판보다 앞이다 —
                // 판이 끝난 뒤에 나간 요청이었다면 서버가 too_fast 를 줄 수 있는데, 경과는 자라기만 하니 백오프 재시도가 통과시킨다.
                if (adoptTokenIntoWaitingPending(kind, token)) {
                    retryPendingSubmitIfAny(fromTrigger = false)
                    return
                }
                roundToken = token
                roundTokenKind = kind
                roundTokenAt = context.clock.now()
            } catch (e: Exception) {
                if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
                if (requested != roundGeneration) return
                log("round token request failed game=${kind.rawValue}")
                // 토큰이 없는 채로 둔다. 토큰을 기다리는 인편이 있으면 백오프 뒤 다시 받는다.
                deferPendingTokenWait(kind)
            }
        } finally {
            if (requested == roundGeneration) roundTokenInFlightKind = null
        }
    }

    /**
     * 유효하게 끝난 판(엔진 onFinished). 범위 밖은 버리고, 로컬 최고를 올리고, 공개면 **인편에 적고** 올린다 — 제출을 시도하기 전에 적는다.
     * 토큰이 없어도 버리지 않는다(맥 2026-09-27 진단의 1번 갈래) — 토큰을 기다리는 인편으로 적는다. 왕복 중인 요청이 있으면 그 응답이 이 인편에 오고, 없으면 미는 쪽이 하나 띄운다.
     */
    fun recordScore(kind: MiniGameKind, score: Int) {
        if (score < 0 || score > kind.maxScore) return
        raiseLocalBest(kind, score.toLong())
        if (!isPublic || !isSignedIn) return
        loadPendingIfNeeded()
        val now = context.clock.now()
        var token: String? = null
        var issuedAt: SwiftDate? = null
        val held = roundToken
        if (held != null && roundTokenKind == kind) {
            // 한 토큰에 한 점수 — 여기서 비워 두면 같은 토큰이 두 번 나가지 않는다. 인편이 그 토큰의 유일한 주인이 된다.
            token = held
            issuedAt = roundTokenAt ?: now
            roundToken = null
            roundTokenKind = null
            roundTokenAt = null
        } else {
            log("submit waiting for token game=${kind.rawValue}")
            submitNotice = GamesMiniGameText.submitRetrying
            exitNoticeIsSticky = false
        }
        pendingSubmits = pendingSubmits + GamesPendingSubmit(nextPendingID++, kind, score, token, issuedAt, now)
        persistPendingSubmits()
        retryPendingSubmitIfAny()
    }

    // MARK: 제출 인편

    /** 이 게임의 인편이 하나라도 있는가(토큰 유무 무관). */
    fun hasPendingSubmit(kind: MiniGameKind): Boolean {
        loadPendingIfNeeded()
        return pendingSubmits.any { it.kind == kind }
    }

    /**
     * 인편을 민다. 게임마다: 토큰을 실은 인편이 있으면 그것을 보낸다(백오프 중이면 기다린다). 전부 토큰을 기다리는 인편이면 맨 앞 것에 토큰을 받아 준다 — 왕복이 없을 때만 띄운다.
     * 같은 게임의 제출이 떠 있으면 건너뛴다. 인편이 없으면 비용이 없다.
     * @param fromTrigger 바깥 방아쇠(기본)면 모르는 status 로 붙든 인편을 푼다. 제출·토큰 응답의 **꼬리**와 타이머는 false — 방아쇠로 치면 모르는 status 응답이 곧 다음 제출을 부르는 고리가 된다.
     */
    fun retryPendingSubmitIfAny(fromTrigger: Boolean = true) {
        loadPendingIfNeeded()
        dropExpiredPendingSubmits()
        if (fromTrigger && pendingSubmits.any { it.heldUntilTrigger }) pendingSubmits = pendingSubmits.map { it.copy(heldUntilTrigger = false) }
        if (!isPublic || !isSignedIn || pendingSubmits.isEmpty()) {
            schedulePendingRetry()
            return
        }
        val now = context.clock.now()
        for (kind in MiniGameKind.entries) {
            if (kind in submittingKinds) continue
            var entries = pendingSubmits.filter { it.kind == kind }
            if (entries.isEmpty()) continue
            // 보험: 들고 있던 토큰이 이 게임 것인데 인편이 토큰을 기다린다면 넘겨준다(정상 흐름에선 recordScore 가 이미 실었다).
            val held = roundToken
            if (entries.none { it.token != null } && hasUsableRoundToken(kind) && held != null) {
                roundToken = null
                roundTokenKind = null
                roundTokenAt = null
                adoptTokenIntoWaitingPending(kind, held)
                entries = pendingSubmits.filter { it.kind == kind }
            }
            val ready = entries.firstOrNull { it.token != null }
            if (ready != null) {
                // 토큰을 실은 인편은 게임당 하나뿐이다. 붙들렸거나 백오프 중이면 이 게임은 통째로 건너뛴다 — 그 인편의 토큰이 살아 있으니 새 토큰도 청하지 않는다(불변식).
                if (ready.heldUntilTrigger || ready.isBackingOff(now)) continue
                context.scope.launch { performSubmit(ready) }
                continue
            }
            val head = entries.first()
            if (head.heldUntilTrigger || head.isBackingOff(now)) continue
            if (roundTokenInFlightKind == kind) continue
            requestRoundToken(kind)
        }
        schedulePendingRetry()
    }

    private fun GamesPendingSubmit.isBackingOff(now: SwiftDate): Boolean = nextRetryAt?.let { it > now } == true

    /**
     * 인편 하나를 보낸다. 지우는 것은 성공과 terminal 거절뿐이고 네트워크 실패·`too_fast`·모르는 status 는 남긴다.
     * 같은 토큰이라 두 번 올라가지 않는다(서버가 `token_used` 로 돌려주고, 그건 아래에서 성공으로 접는다).
     */
    suspend fun performSubmit(entry: GamesPendingSubmit) {
        if (!isSignedIn) return
        val token = entry.token ?: return
        val kind = entry.kind
        if (kind in submittingKinds) return
        // ★ 다른 계정 인편을 제출하지 않는다: 지금 세션의 주인과 인편 목록의 주인이 같고 목록에 그 인편이 그대로 있을 때만 — 아래 첫 왕복까지 멈춤점이 없다.
        val owner = myUserID
        if (owner == null || pendingOwner != owner || pendingSubmits.none { it.id == entry.id && it.token == token }) return
        submittingKinds += kind
        val sessionGeneration = context.generation
        val generation = resetGeneration
        // 한 번만 내린다 — 꼬리가 띄운 다음 제출의 깃발을 뒤늦은 finally 가 내리면 같은 토큰이 두 번 동시에 나간다. 계정이 바뀌었으면 건드리지 않는다.
        var holding = true
        fun release() {
            if (holding && generation == resetGeneration) submittingKinds -= kind
            holding = false
        }
        try {
            val service = context.service
            val response = context.withSessionRetry { session ->
                service.submitMiniGameScore(session.accessToken, kind.rawValue, entry.score.toLong(), token)
            }
            // 세대가 밀렸으면 이 응답으로 상태를 건드리지 않는다. 인편은 **남는다** — 영속본이 같은 계정의 다음 로그인을 기다린다(키가 계정별이라 남의 계정으로는 안 나간다).
            if (sessionGeneration != context.generation || generation != resetGeneration) {
                release()
                retryPendingSubmitIfAny()
                return
            }
            // 꼬리에서 다음 인편을 밀어야 하므로 깃발은 **여기서** 내린다.
            release()
            var recorded = false
            // INV-GamesMiniGameHub-14bb03d9 이식: `token_used` 는 **성공이다.** 서버는 제출이 성공한 순간 그 토큰에 used_at 을 찍고,
            //   이미 쓴 토큰에는 `token_used` 를 돌려준다. 즉 이 응답은 **응답만 유실된 첫 제출의 재시도**뿐이고 점수는 이미 올라가 있다.
            if (response.status == "ok" || response.status == "token_used") {
                recorded = true
                response.bestScore?.let { raiseLocalBest(kind, it) }
                removePendingSubmit(entry.id)
                // 출구에서 세운 안내("앱을 나가서 …")는 제출과 무관한 사실이라 지우지 않는다.
                if (!hasPendingSubmit(kind) && !exitNoticeIsSticky) submitNotice = null
                // 이 게임의 역대 표는 이제 낡았다(새 개인 최고가 들어갔을 수 있다 — 맥 v0.3.67).
                if (allTimeFreshKind == kind) allTimeFreshKind = null
                allTimeInvalidation += 1
            } else if (response.status in terminalSubmitStatuses) {
                log("submit refused status=${response.status} game=${kind.rawValue}")
                // `no_token` 은 **한 번은 되살린다.** 그 판은 진짜로 있었고 점수도 진짜다 — 죽은 것은 토큰뿐이다(토큰을 기다리는 인편으로 되돌리면 새 토큰을 받아 다시 올라간다).
                if (response.status == "no_token" && !entry.recoveredFromDeadTokenOnce) {
                    demotePendingToTokenWait(entry.id)
                    submitNotice = GamesMiniGameText.submitRetrying
                    exitNoticeIsSticky = false
                    retryPendingSubmitIfAny()
                    return
                }
                removePendingSubmit(entry.id)
                // 토큰이 죽은 거절은 **그 판이 영영 못 올라간다** — "다시 해 주세요"(복구된다는 뜻)와 문장을 가른다.
                submitNotice = if (response.status in deadTokenStatuses) GamesMiniGameText.submitTokenDead else GamesMiniGameText.submitRefused
                exitNoticeIsSticky = false
            } else if (response.status in retryableSubmitStatuses) {
                // `too_fast`: 토큰은 살아 있고(서버가 소모하기 전에 돌려준다) 경과는 자라기만 한다 — 같은 토큰으로 조금 뒤에 다시 보내면 통과한다.
                // INV-GamesMiniGameHub-e849bf8a 이식: 새 토큰 요청은 **지금 되보낼 토큰을 죽인다** — 인편이 남아 있어 꼬리의 선발급이 비켜 간다.
                log("submit too early — will retry status=${response.status} game=${kind.rawValue}")
                deferPendingRetry(entry.id)
                submitNotice = GamesMiniGameText.submitRetrying
                exitNoticeIsSticky = false
            } else {
                // 모르는 status(신버전 서버). 이해 못 한 거절을 두드리지는 않되 점수를 버리지도 않는다 — 타이머 없이 남기고 방아쇠에서만 다시 보낸다. TTL 이 끝을 낸다.
                log("submit refused (unknown status) status=${response.status} game=${kind.rawValue}")
                pendingSubmits = pendingSubmits.map { if (it.id == entry.id) it.copy(heldUntilTrigger = true) else it }
                submitNotice = GamesMiniGameText.submitRetrying
                exitNoticeIsSticky = false
            }
            // 다음 인편(토큰을 기다리는 것)에 토큰을 받아 주고, 이 게임의 인편이 다 비었으면 다음 판 토큰을 미리 받아 둔다(방금 쓴 토큰은 죽었다). 이 꼬리는 방아쇠가 아니다.
            retryPendingSubmitIfAny(fromTrigger = false)
            if (!hasPendingSubmit(kind)) prefetchRoundToken(kind)
            if (!recorded) return
            // 일일 미션(v0.3.64) — 판이 서버에 남은 직후 **한 번** 묻는다(새 타이머 없이 이벤트로). 선발급 **뒤**, 순위 재조회 **앞**.
            context.refreshAchievementsAfterGameResult(kind.rawValue)
            // 순위 재조회는 **화면을 떠난 뒤에도** 한다(activeKind 로 막으면 뒤로가기로 끝낸 판이 반영되지 않는다). 다음 판 토큰 뒤에 — 앞에 두면 그만큼 토큰이 늦는다.
            loadBoard(kind, withWinner = false)
            // 역대 — [역대] 를 보는 중일 때만, 오늘 순위 **뒤에** 받는다.
            if (boardScope == MiniGameBoardScope.allTime && activeKind == kind) performLoadAllTimeBoard()
        } catch (e: Exception) {
            if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
            if (sessionGeneration != context.generation || generation != resetGeneration) {
                release()
                retryPendingSubmitIfAny()
                return
            }
            release()
            log("submit failed (network) game=${kind.rawValue}")
            // 네트워크 실패는 인편을 **남긴다** — 백오프 뒤, 그리고 다음 방아쇠에 같은 토큰으로 한 번 더 보낸다.
            deferPendingRetry(entry.id)
            submitNotice = GamesMiniGameText.submitRetrying
            exitNoticeIsSticky = false
            // 인편이 살아 있으면 새 토큰은 안 받는다. 인편이 방금 TTL 로 버려졌을 때만 다음 판의 토큰을 미리 받는다.
            if (!hasPendingSubmit(kind)) prefetchRoundToken(kind)
        } finally {
            release()
        }
    }

    /** 화면을 닫아 둔 사이에 인편이 TTL 로 죽었다면 한 줄로 말하고 표식을 지운다(한 번만 말한다). */
    private fun showLostNoticeIfAny() {
        loadPendingIfNeeded()
        val owner = pendingOwner ?: return
        if (context.keyValueStore.getBoolean(lostNoticeKey(owner)) != true) return
        context.keyValueStore.remove(lostNoticeKey(owner))
        submitNotice = GamesMiniGameText.submitExpired
    }

    /** 죽은 토큰(`no_token`)을 받은 인편을 **토큰을 기다리는 인편으로 되돌린다.** 백오프는 0 으로 — 새 토큰을 받는 일은 앞의 실패와 다른 일이다. 표식을 세워 두 번은 오지 않는다. */
    private fun demotePendingToTokenWait(id: Long) {
        pendingSubmits = pendingSubmits.map {
            if (it.id == id) it.copy(token = null, tokenIssuedAt = null, attempts = 0, nextRetryAt = null, heldUntilTrigger = false, recoveredFromDeadTokenOnce = true) else it
        }
        persistPendingSubmits()
        log("pending submit recovered from dead token")
    }

    /** 토큰을 기다리는 이 게임의 맨 앞 인편에 토큰을 넘긴다. 넘겼으면 true(호출자가 인편을 민다). */
    private fun adoptTokenIntoWaitingPending(kind: MiniGameKind, token: String): Boolean {
        loadPendingIfNeeded()
        val head = pendingSubmits.firstOrNull { it.kind == kind && it.token == null } ?: return false
        val now = context.clock.now()
        pendingSubmits = pendingSubmits.map { if (it.id == head.id) it.copy(token = token, tokenIssuedAt = now, nextRetryAt = null) else it }
        persistPendingSubmits()
        return true
    }

    /** 실패한 인편의 백오프를 한 단계 올리고 타이머를 다시 잡는다(n번째 실패 → [pendingRetryDelaysSeconds] 의 n번째, 끝은 반복). */
    private fun deferPendingRetry(id: Long) {
        val now = context.clock.now()
        pendingSubmits = pendingSubmits.map {
            if (it.id != id) return@map it
            val attempts = it.attempts + 1
            val delays = pendingRetryDelaysSeconds
            it.copy(attempts = attempts, nextRetryAt = now.addingTimeInterval(delays[minOf(attempts - 1, delays.size - 1)]))
        }
        persistPendingSubmits()
        schedulePendingRetry()
    }

    /** 토큰 요청이 실패했는데 그 게임에 토큰을 기다리는 인편이 있으면 — 그 인편의 백오프를 올린다(다음 요청은 타이머가 띄운다). */
    private fun deferPendingTokenWait(kind: MiniGameKind) {
        val head = pendingSubmits.firstOrNull { it.kind == kind && it.token == null } ?: return
        deferPendingRetry(head.id)
    }

    /** 백오프 타이머 한 개 — 가장 먼저 돌아오는 인편의 시각에 맞춘다. TTL 을 넘겨서 돌아오는 재시도는 잡지 않는다. 기다릴 것이 없으면 거둔다. */
    private fun schedulePendingRetry() {
        pendingRetryJob?.cancel()
        pendingRetryJob = null
        val now = context.clock.now()
        val next = pendingSubmits.mapNotNull { entry ->
            entry.nextRetryAt?.takeIf { it > now && it < entry.deadline(pendingSubmitTtlSeconds) }
        }.minOrNull() ?: return
        val generation = resetGeneration
        val wait = sleep
        pendingRetryJob = context.scope.launch {
            wait(next.timeIntervalSince(now))
            if (generation != resetGeneration) return@launch
            pendingRetryJob = null
            retryPendingSubmitIfAny(fromTrigger = false)
        }
    }

    private fun removePendingSubmit(id: Long) {
        if (pendingSubmits.none { it.id == id }) return
        pendingSubmits = pendingSubmits.filterNot { it.id == id }
        persistPendingSubmits()
    }

    /** TTL 을 넘긴 인편을 버린다(토큰이 죽었다). 화면이 열려 있으면 그 사실을 말하고, 닫혀 있으면 표식을 남겨 다음에 화면을 열 때 말한다 — 사용자가 그 판이 사라진 것을 영영 모르면 안 된다. */
    private fun dropExpiredPendingSubmits() {
        val now = context.clock.now()
        val expired = pendingSubmits.filter { it.isExpired(now, pendingSubmitTtlSeconds) }
        if (expired.isEmpty()) return
        for (entry in expired) log("pending submit expired game=${entry.kind.rawValue}")
        val gone = expired.map { it.id }.toSet()
        pendingSubmits = pendingSubmits.filterNot { it.id in gone }
        persistPendingSubmits()
        if (activeKind != null) {
            submitNotice = GamesMiniGameText.submitExpired
            exitNoticeIsSticky = false
        } else {
            pendingOwner?.let { context.keyValueStore.putBoolean(lostNoticeKey(it), true) }
        }
    }

    /** 메모리의 인편이 지금 계정 것이 아니면(처음 · 계정 전환 · 재로그인) 그 계정의 키에서 읽는다. TTL 을 넘긴 것은 여기서 버린다. 깨진 저장값은 없는 것으로 친다. */
    private fun loadPendingIfNeeded() {
        val owner = myUserID
        if (pendingOwner == owner) return
        pendingOwner = owner
        submittingKinds.clear()
        pendingRetryJob?.cancel()
        pendingRetryJob = null
        if (owner == null) {
            pendingSubmits = emptyList()
            return
        }
        val stored = context.keyValueStore.getString(pendingKey(owner))
        val rows = stored?.let { runCatching { pendingJson.decodeFromString(ListSerializer(GamesPendingSubmitRow.serializer()), it) }.getOrNull() }.orEmpty()
        pendingSubmits = rows.mapNotNull { row ->
            val kind = MiniGameKind.fromRawValue(row.kind) ?: return@mapNotNull null
            GamesPendingSubmit(
                row.id, kind, row.score, row.token, row.tokenIssuedAt?.let { SwiftDate(it) }, SwiftDate(row.recordedAt), row.attempts, row.recoveredFromDeadTokenOnce,
            )
        }
        nextPendingID = (pendingSubmits.maxOfOrNull { it.id } ?: 0L) + 1
        dropExpiredPendingSubmits()
        if (pendingSubmits.isNotEmpty()) log("pending submits restored count=${pendingSubmits.size}")
    }

    /** 영속본을 메모리와 맞춘다. 비었으면 키를 지운다. 주인이 없으면(로그아웃 상태) 쓰지 않는다. */
    private fun persistPendingSubmits() {
        val owner = pendingOwner ?: return
        val key = pendingKey(owner)
        if (pendingSubmits.isEmpty()) {
            context.keyValueStore.remove(key)
            return
        }
        val rows = pendingSubmits.map {
            GamesPendingSubmitRow(it.id, it.kind.rawValue, it.score, it.token, it.tokenIssuedAt?.timeIntervalSince1970, it.recordedAt.timeIntervalSince1970, it.attempts, it.recoveredFromDeadTokenOnce)
        }
        context.keyValueStore.putString(key, pendingJson.encodeToString(ListSerializer(GamesPendingSubmitRow.serializer()), rows))
    }

    // MARK: 조회

    /**
     * 공개 여부를 읽는다(설정은 나 탭이 바꾼다 — 화면을 열 때마다 다시 읽는다).
     * - 서버가 답했다: 그 값. 행·컬럼이 없어 값이 없으면(null) 공개(맥과 같다 — 컬럼 없는 서버).
     * - 표·함수가 아직 없는 서버(`databaseSchemaMissing`): 공개.
     * - **그 밖의 실패(오프라인·5xx·만료)는 아는 값을 그대로 둔다** — 순위 공개를 끈 사람의 점수가 조회 한 번 실패 뒤 서버로 나가던
     *   결함(games-verify PROBE-1). 맥 `miniGamePublicLoaded` 도 실패는 값을 바꾸지 않는다.
     */
    suspend fun refreshPublic() {
        if (!isSignedIn) return
        val userID = context.sessionStore.session?.userID ?: return
        val sessionGeneration = context.generation
        val generation = resetGeneration
        val service = context.service
        val resolved: Boolean = try {
            val value = context.withSessionRetry { session -> service.fetchMiniGamePublic(session.accessToken, userID) }
            value ?: true
        } catch (e: Exception) {
            if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
            if (e == SupabaseWorkServiceError.DatabaseSchemaMissing) {
                true
            } else {
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
                if (sessionGeneration != context.generation || generation != resetGeneration) return
                log("minigame public lookup failed — keeping isPublic=$isPublic")
                return
            }
        }
        if (sessionGeneration != context.generation || generation != resetGeneration) return
        if (isPublic != resolved) isPublic = resolved
        if (!resolved) {
            // 꺼져 있으면 들고 있는 토큰은 쓸 일이 없다.
            roundToken = null
            roundTokenKind = null
            roundTokenAt = null
        }
    }

    /** 오늘 순위(+어제 1등). 두 조회는 독립 실패다(맥과 같다). */
    suspend fun loadBoard(kind: MiniGameKind, withWinner: Boolean) {
        if (!isSignedIn) return
        val sessionGeneration = context.generation
        val generation = resetGeneration
        val service = context.service
        val state = boards[kind] ?: GamesMiniGameBoard()
        if (!state.loading) boards = boards + (kind to state.copy(loading = true, failed = false))
        try {
            val entries = context.withSessionRetry { session -> service.fetchMiniGameBoard(session.accessToken, kind.rawValue, null) }
            if (sessionGeneration != context.generation || generation != resetGeneration) return
            val next = (boards[kind] ?: GamesMiniGameBoard()).copy(
                entries = entries.sortedForMiniGameBoard(context.collation), loaded = true, loading = false, failed = false,
            )
            if (boards[kind] != next) boards = boards + (kind to next)
            val me = myUserID
            if (me != null) next.entries.firstOrNull { it.userID == me }?.let { raiseLocalBest(kind, it.bestScore) }
        } catch (e: Exception) {
            if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
            if (sessionGeneration != context.generation || generation != resetGeneration) return
            val base = boards[kind] ?: GamesMiniGameBoard()
            // 표·함수가 아직 없는 서버: 실패가 아니라 "아직 기록이 없다"로 조용히 접는다(맥과 같다).
            val next = if (e == SupabaseWorkServiceError.DatabaseSchemaMissing) base.copy(loading = false, loaded = true)
            else base.copy(loading = false, failed = true)
            boards = boards + (kind to next)
            return
        }
        if (!withWinner) return
        val winner = try {
            context.withSessionRetry { session -> service.fetchMiniGameYesterdayWinner(session.accessToken, kind.rawValue) }
        } catch (e: Exception) {
            if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
            null
        }
        if (sessionGeneration != context.generation || generation != resetGeneration) return
        val current = boards[kind] ?: return
        if (current.yesterdayWinner != winner) boards = boards + (kind to current.copy(yesterdayWinner = winner))
    }

    // MARK: 역대 순위 (v0.3.67 — 맥 WorkTimerStoreMiniGame.swift:920-1000)
    //
    // 사용자 결정(2026-10-27): "미니게임 멀티 아닌 3종 에서 역대 최고 점수 랭킹 볼 수 있는 창도 만들어줘."
    // 순위 열 머리의 [오늘 | 역대] 가 이 절을 부른다. 받는 때는 넷뿐이다 — ① [역대] 로 넘어갈 때(그 게임 표가 최신이 아닐 때만)
    // ② [역대] 를 보는 중에 게임을 바꿀 때 ③ [역대] 를 보는 중에 판이 기록됐을 때 ④ [역대] 를 보던 채로 화면을 다시 열 때.
    // 주기 루프에 얹지 않는다(오늘 순위와 같은 이유).

    /**
     * 순위 열의 [오늘 | 역대] 전환. 같은 쪽을 다시 누르면 아무 일도 없다.
     * [역대] 로 넘어갈 때 그 게임의 최신 표를 들고 있으면 **다시 받지 않는다**(오가며 누를 때마다 요청이 나가지 않게).
     * 실패한 채였으면 넘어갈 때 한 번 더 받는다 — 사용자가 다시 보러 온 것이 곧 재시도 의사다.
     */
    fun selectBoardScope(scope: MiniGameBoardScope) {
        if (scope == boardScope) return
        boardScope = scope
        if (scope != MiniGameBoardScope.allTime) return
        val kind = activeKind ?: return
        if (allTimeFreshKind == kind && !allTimeFailed) return
        // 첫 프레임부터 빈 자리에 "불러오는 중…"이 뜨게 한다(본문 자리에 엉뚱한 문구 금지).
        if (!allTimeLoaded) allTimeLoading = true
        loadAllTimeBoard()
    }

    /** 역대 순위를 받는다(코루틴 발사). 위 네 방아쇠와 [다시 시도] 가 부른다. */
    fun loadAllTimeBoard() {
        context.scope.launch { performLoadAllTimeBoard() }
    }

    /**
     * `minigame_alltime_board` 를 받아 반영한다. 응답이 오는 사이 게임을 바꿨거나 계정이 바뀌었으면 버린다(오늘 순위와 같은 가드).
     * 실패는 셋으로 가른다.
     *  · 서버에 함수가 아직 없다(PGRST202 · 본문 없는 404) → **준비 중**(빈 표 + [allTimeUnavailable]). 실패 문구도 [다시 시도] 도 없다.
     *  · 그 밖(네트워크 · 5xx · 배열이 아닌 본문) → 실패. 이미 그린 표가 있으면 그대로 두고, 없을 때만 실패 문구 + [다시 시도].
     *  · 취소 → 아무것도 안 바꾼다.
     */
    suspend fun performLoadAllTimeBoard() {
        if (!isSignedIn) return
        val kind = activeKind ?: return
        val sessionGeneration = context.generation
        val generation = resetGeneration
        // 떠날 때의 낡음 표시 횟수와 일련번호(`allTimeInvalidation` 주석).
        val invalidation = allTimeInvalidation
        allTimeFetchSerial += 1
        val serial = allTimeFetchSerial
        if (!allTimeLoading) allTimeLoading = true
        if (allTimeFailed) allTimeFailed = false
        val service = context.service
        try {
            val entries = context.withSessionRetry { session -> service.fetchMiniGameAllTimeBoard(session.accessToken, kind.rawValue) }
            if (sessionGeneration != context.generation || generation != resetGeneration || kind != activeKind) return
            // 뒤에 떠난 받기가 이미 반영됐으면 이 (옛) 응답은 버린다 — 새 표를 옛 표로 덮지 않는다.
            if (serial <= allTimeAppliedSerial) return
            allTimeAppliedSerial = serial
            val sorted = entries.sortedForMiniGameAllTimeBoard()
            if (allTimeBoard != sorted) allTimeBoard = sorted
            allTimeBoardKind = kind
            if (!allTimeLoaded) allTimeLoaded = true
            if (allTimeFailed) allTimeFailed = false
            if (allTimeUnavailable) allTimeUnavailable = false
            // 떠난 뒤에 낡음 표시가 있었으면(그 사이 판이 기록됐다) **최신으로 표시하지 않는다** — 다음에 [역대] 로 넘어가면 다시 받는다.
            if (invalidation == allTimeInvalidation) allTimeFreshKind = kind
            // 내 역대 행은 이 계정의 **진짜** 전체 기간 최고다 — 로컬 캐시("최고 N")가 그보다 작으면(다른 기기 · 재설치) 올린다.
            val me = myUserID
            if (me != null) sorted.firstOrNull { it.userID == me }?.let { raiseLocalBest(kind, it.bestScore) }
        } catch (e: Exception) {
            if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
            if (sessionGeneration != context.generation || generation != resetGeneration || kind != activeKind) return
            if (BlockReportRules.isMissingFunction(errorFacts(e))) {
                if (allTimeBoard.isNotEmpty()) allTimeBoard = emptyList()
                allTimeBoardKind = kind
                if (!allTimeUnavailable) allTimeUnavailable = true
                if (!allTimeLoaded) allTimeLoaded = true
                // 같은 게임으로 오가며 누를 때마다 404 를 다시 두드리지 않는다(판 기록 · 게임 전환 · 화면 열기가 다시 묻는다).
                allTimeFreshKind = kind
            } else {
                log("alltime board fetch failed game=${kind.rawValue}")
                if (!allTimeFailed) allTimeFailed = true
            }
        } finally {
            if (kind == activeKind && allTimeLoading) allTimeLoading = false
        }
    }

    /** 역대 표를 비운다(게임 전환 · 로그아웃). [invalidate] 면 떠 있던 받기가 '최신' 을 다시 세우지 못하게 한다. */
    private fun clearAllTime(invalidate: Boolean) {
        if (allTimeBoard.isNotEmpty()) allTimeBoard = emptyList()
        allTimeBoardKind = null
        if (allTimeLoaded) allTimeLoaded = false
        if (allTimeFailed) allTimeFailed = false
        if (allTimeUnavailable) allTimeUnavailable = false
        allTimeFreshKind = null
        if (invalidate) allTimeInvalidation += 1
        allTimeLoading = boardScope == MiniGameBoardScope.allTime && activeKind != null
    }

    /** 서비스 오류 → W1-c 판정 재료(함수 없음 = 스키마 없음 또는 HTTP 404). */
    private fun errorFacts(e: Throwable): ServiceErrorFacts = when (e) {
        SupabaseWorkServiceError.DatabaseSchemaMissing -> ServiceErrorFacts.databaseSchemaMissing
        is SupabaseWorkServiceError.InvalidResponse -> ServiceErrorFacts.invalidResponse(e.statusCode)
        is SupabaseWorkServiceError.RateLimited -> ServiceErrorFacts.rateLimited
        is SupabaseWorkServiceError -> ServiceErrorFacts.otherServiceError
        else -> ServiceErrorFacts.notServiceError
    }

    // MARK: 로컬 최고

    private fun loadLocalBest(kind: MiniGameKind) {
        val stored = maxOf(0L, context.keyValueStore.getLong(bestKey(myUserID, kind)) ?: 0L)
        if (localBest[kind] != stored) localBest = localBest + (kind to stored)
    }

    private fun raiseLocalBest(kind: MiniGameKind, score: Long) {
        val key = bestKey(myUserID, kind)
        val current = maxOf(0L, context.keyValueStore.getLong(key) ?: 0L)
        if (score > current) context.keyValueStore.putLong(key, score)
        val resolved = maxOf(current, score)
        if (localBest[kind] != resolved) localBest = localBest + (kind to resolved)
    }
}
