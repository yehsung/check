// 원본: Sources/CheckMobileKit/Games/GamesMiniGameHub.swift @ 1b8260d
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
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

/** 아직 서버가 받았다고 확인해 주지 않은 제출 한 건(Swift 튜플 `(kind, score, token)`). */
data class GamesPendingSubmit(val kind: MiniGameKind, val score: Int, val token: String)

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
 * **테트리스는 여기까지의 점수로 확정해 제출한다**. 로그아웃([reset])과 화면 경합 정리([openScreen])는 **`abandon()` 그대로**다.
 *
 * 제출 인편([pendingSubmit]): 제출이 **네트워크로** 실패하면 (게임, 점수, 토큰)을 들고 있다가 앱이 다시 active 가 될 때
 * 같은 토큰으로 한 번 더 보낸다. 진단: 거절 status 이름까지만 로그에 남긴다 — need_seconds·elapsed_seconds 는 화면에도 로그에도
 * 쓰지 않는다(위조 보조 도구).
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
         * `too_fast` 재시도 지연(초). **눈먼 값이고 횟수가 묶여 있다.**
         *
         * INV-GamesMiniGameHub-1b3e0aef 이식: 서버가 같이 주는 `need_seconds`·`elapsed_seconds` 로 지연을 **계산하지 않는다** — 클라가
         * 그 숫자로 재시도 타이밍을 계산하면 그게 곧 위조 보조 도구다(응답 칸은 읽지도 않는다 — 구조 시험이 이 파일에 그 이름이 없음을 잰다).
         * INV-GamesMiniGameHub-2e37b9a7 이식: 무한 백오프로 두지 않는다. 그러면 "하한이 지나갈 때까지 기다려 주는 기계"가 되어 즉시
         * 위조한 점수도 결국 올려 준다. 정직한 판에 필요한 것은 0.2초뿐이므로 두 번으로 남는다 — 그 뒤엔 사실대로 "못 올렸어요".
         */
        val tooFastRetryDelaysSeconds: List<Double> = listOf(1.5, 4.0)

        /** 토큰이 죽어 **그 판은 영영 못 올리는** 거절. 문구가 "다시 해 주세요"(복구된다는 뜻)와 갈린다. */
        val deadTokenStatuses: Set<String> = setOf("no_token", "token_expired")

        internal const val TAG: String = "minigame"

        /** 로컬 최고 키 — **계정별**(같은 폰을 다른 계정이 쓰면 남의 최고를 물려받지 않는다). */
        fun bestKey(userID: String?, kind: MiniGameKind): String = "aing.minigame.best.${userID ?: "local"}.${kind.rawValue}"
    }

    /** 기다리기(시험은 가상 시간이라 그대로 둔다 — Swift `sleep` 주입 자리). */
    var sleep: suspend (Double) -> Unit = { seconds -> delay(delayMillis(seconds)) }

    /** `too_fast` 를 이 토큰으로 몇 번 되보냈나. 토큰과 짝지어 둔다 — 새 판이 인편을 갈아 끼우면 같이 리셋된다. */
    private var tooFastRetries: Pair<String, Int>? = null

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
     * 아직 서버가 받았다고 확인해 주지 않은 제출 한 건. **네트워크로 실패하면 남고**, 성공·명시적 거절이면 지운다.
     * 앱이 다시 active 가 될 때 [retryPendingSubmitIfAny] 가 **같은 토큰으로** 한 번 더 보낸다.
     */
    var pendingSubmit: GamesPendingSubmit? = null
        private set

    /** 지금 제출 왕복이 떠 있다(인편 재시도가 같은 토큰을 두 번 보내지 않게). */
    var isSubmitting: Boolean = false
        private set

    /** 출구에서 세운 안내("앱을 나가서 …")를 **비동기 제출 성공이 지우지 않게** 붙든다. */
    private var exitNoticeIsSticky = false
    private var resetGeneration = 0
    private var lastSummaryAt: SwiftDate? = null

    /** 엔진 시드 — 화면을 열 때마다 달라야 같은 판이 반복되지 않는다(데모 고정 시계에서도). */
    private var seedCounter: ULong = 0u

    /**
     * 이 빌드의 허브가 여는 게임(첫 화면 타일 · 오늘 순위 · openScreen). 기본은 폰 노출([MiniGameExposure.visible] — Android 동작 그대로)이고,
     * 데스크톱 조립만 [MiniGameExposure.desktopVisible](길건너 포함 — W-9 #6)로 바꾼다.
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
     * 게임 화면을 떠났다. 진행 중인 판은 **끝낸다**(`endRound()` — 테트리스는 여기까지의 점수로 확정 제출).
     * 토큰은 들고 있는다(재사용 나이 안에 다시 열면 그대로 쓴다). 안내 한 줄은 세우지 않는다.
     */
    fun closeScreen(kind: MiniGameKind) {
        if (activeKind != kind) return
        controller?.endRound()
        controller = null
        activeKind = null
    }

    /** 앱이 background 로 간다 — 판은 끝. 기존 두 게임은 제출하지 않고, **테트리스는 여기까지의 점수로 확정 제출한다**. */
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
                //  · 제출이 떠 있으면(인편이 있으면) "여기까지 기록했어요" 가 참이다 — 비동기 성공이 못 지우게 붙든다.
                //  · 못 띄웠으면(토큰이 없어 `recordScore` 가 그 사실을 말한 경우) 그 말을 **덮지 않는다**.
                if (pendingSubmit == null && isPublic && isSignedIn) return
                submitNotice = GamesMiniGameText.endedInBackground(controller.kind)
                exitNoticeIsSticky = pendingSubmit != null
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
        pendingSubmit = null
        tooFastRetries = null
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
     * @param force 왕복 중인 요청이 있어도 새로 받는다 — 판이 **이미 끝났는데** 토큰이 없던 자리. 새 요청이 나가면 앞 요청의 응답은
     *   세대 가드가 버린다.
     */
    fun prefetchRoundToken(kind: MiniGameKind, force: Boolean = false) {
        if (!isPublic || !isSignedIn) return
        // INV-GamesMiniGameHub-22dafde9 이식: 그 게임의 **인편이 살아 있으면 받지 않는다**(force 여도). 서버는 (사용자, 게임)당
        //   미사용 토큰을 한 행만 두고 새 요청이 오면 갈아 끼운다 — 제출이 네트워크로 실패한 직후 여기서 새 토큰을 받으면 복귀 재시도는
        //   `no_token`(terminal)을 받고 인편이 버려진다. 막힌 채로 굳지 않는다: 인편은 복귀·새 판이 밀어내고, 비워지는 순간
        //   `performSubmit` 의 꼬리가 여기를 다시 불러 새 토큰을 받는다.
        if (pendingSubmit?.kind == kind) return
        if (hasUsableRoundToken(kind)) return
        if (!force && roundTokenInFlightKind == kind) return
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
        // INV-GamesMiniGameHub-71a14b0b 이식: 이 게임의 인편이 살아 있으면 토큰을 받는 대신 **인편부터 밀어낸다**. 여기가 인편을 푸는
        //   두 방아쇠 가운데 하나다(다른 하나는 복귀 `retryPendingSubmitIfAny()`). 이번 판이 토큰 없이 시작될 수는 있다 — 그건 앞 판을
        //   확실히 버리는 것보다 싸고, `recordScore` 가 "못 올렸어요"로 사실대로 말한다.
        if (pendingSubmit?.kind == kind) {
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
        if (pendingSubmit?.kind == kind) {
            retryPendingSubmitIfAny()
            return
        }
        if (roundTokenInFlightKind == kind) return
        val issued = roundTokenAt
        if (roundToken != null && roundTokenKind == kind && issued != null && now.timeIntervalSince(issued) < limit) return
        log("round token refreshed mid-run game=${kind.rawValue}")
        requestRoundToken(kind)
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
                    return
                }
                roundToken = token
                roundTokenKind = kind
                roundTokenAt = context.clock.now()
            } catch (e: Exception) {
                if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
                if (requested != roundGeneration) return
                log("round token request failed game=${kind.rawValue}")
            }
        } finally {
            if (requested == roundGeneration) roundTokenInFlightKind = null
        }
    }

    /** 유효하게 끝난 판(엔진 onFinished). 범위 밖은 버리고, 로컬 최고를 올리고, 공개면 토큰과 함께 올린다. */
    fun recordScore(kind: MiniGameKind, score: Int) {
        if (score < 0 || score > kind.maxScore) return
        raiseLocalBest(kind, score.toLong())
        if (!isPublic || !isSignedIn) return
        val token = roundToken
        if (token == null || roundTokenKind != kind) {
            log("submit skipped — no token game=${kind.rawValue}")
            submitNotice = GamesMiniGameText.submitFailedConnection
            prefetchRoundToken(kind, force = true)
            return
        }
        // 한 토큰에 한 점수 — 여기서 비워 두면 같은 토큰이 두 번 나가지 않는다. 대신 **인편**에 적는다.
        roundToken = null
        roundTokenKind = null
        roundTokenAt = null
        // INV-GamesMiniGameHub-c7357ade 이식: 인편 칸은 하나뿐이다. 밀려나는 앞 판을 **조용히 버리지 않는다** — 예전에는 그대로 덮어써서
        //   앞 판 점수가 재시도 한 번 없이 사라졌다(사용자에게는 판이 통째로 증발한 것으로 보인다).
        val superseded = pendingSubmit
        if (superseded != null && superseded.token != token) sendSupersededPending(superseded)
        pendingSubmit = GamesPendingSubmit(kind, score, token)
        context.scope.launch { performSubmit(kind, score, token) }
    }

    /**
     * 인편 칸에서 밀려나는 제출을 **마지막으로 한 번** 보낸다(버리기 전에). 네트워크 실패는 "응답만 유실됐다"일 수도 있다 — 그러면
     * 점수는 이미 올라가 있고 서버가 `token_used` 로 답한다. [performSubmit] 을 재활용하지 않는 까닭: 그쪽은 [submitNotice] 를 쓴다 —
     * 밀려난 앞 판의 거절 문구가 지금 막 끝난 판의 자리를 덮으면 엉뚱한 판에 대한 말을 읽는다. 화면에 한 글자도 안 쓴다.
     */
    private fun sendSupersededPending(superseded: GamesPendingSubmit) {
        log("pending submit superseded — sending once more game=${superseded.kind.rawValue}")
        val sessionGeneration = context.generation
        val generation = resetGeneration
        val service = context.service
        context.scope.launch {
            try {
                val response = context.withSessionRetry { session ->
                    service.submitMiniGameScore(session.accessToken, superseded.kind.rawValue, superseded.score.toLong(), superseded.token)
                }
                if (sessionGeneration != context.generation || generation != resetGeneration) return@launch
                // `token_used` 는 여기서도 성공이다(응답만 유실된 첫 제출).
                if (response.status != "ok" && response.status != "token_used") {
                    log("superseded submit refused status=${response.status} game=${superseded.kind.rawValue}")
                    return@launch
                }
                response.bestScore?.let { raiseLocalBest(superseded.kind, it) }
                loadBoard(superseded.kind, withWinner = false)
            } catch (e: Exception) {
                if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
                log("superseded submit failed (network) game=${superseded.kind.rawValue}")
            }
        }
    }

    /**
     * 앱이 다시 active 가 됐다 — 서버가 받았다고 확인해 주지 않은 제출이 있으면 **같은 토큰으로** 한 번 더.
     * 같은 토큰이라 두 번 올라가지 않는다(서버가 `token_used` 로 돌려주고, 그건 아래에서 성공으로 접는다).
     */
    fun retryPendingSubmitIfAny() {
        val pending = pendingSubmit ?: return
        if (isSubmitting) return
        if (!isPublic || !isSignedIn) return
        context.scope.launch { performSubmit(pending.kind, pending.score, pending.token) }
    }

    suspend fun performSubmit(kind: MiniGameKind, score: Int, token: String) {
        if (!isSignedIn) return
        isSubmitting = true
        try {
            val sessionGeneration = context.generation
            val generation = resetGeneration
            val service = context.service
            try {
                val response = context.withSessionRetry { session ->
                    service.submitMiniGameScore(session.accessToken, kind.rawValue, score.toLong(), token)
                }
                if (sessionGeneration != context.generation || generation != resetGeneration) return
                // INV-GamesMiniGameHub-14bb03d9 이식: `token_used` 는 **성공이다.** 서버는 제출이 성공한 순간 그 토큰에 used_at 을 찍고,
                //   이미 쓴 토큰에는 `token_used` 를 돌려준다. 즉 이 응답은 **응답만 유실된 첫 제출의 재시도**뿐이고 점수는 이미 올라가 있다.
                if (response.status == "ok" || response.status == "token_used") {
                    response.bestScore?.let { raiseLocalBest(kind, it) }
                    clearPendingSubmit(token)
                    // 출구에서 세운 안내("앱을 나가서 …")는 제출과 무관한 사실이라 지우지 않는다.
                    if (!exitNoticeIsSticky) submitNotice = null
                    // 일일 미션(v0.3.64) — 판이 서버에 남은 직후 **한 번** 묻는다(새 타이머 없이 이벤트로). 순위 재조회보다 **앞**에 둔다.
                    context.refreshAchievementsAfterGameResult(kind.rawValue)
                    // 이 게임의 역대 표는 이제 낡았다(새 개인 최고가 들어갔을 수 있다 — 맥 v0.3.67).
                    if (allTimeFreshKind == kind) allTimeFreshKind = null
                    allTimeInvalidation += 1
                    // 순위 재조회는 **화면을 떠난 뒤에도** 한다(activeKind 로 막으면 뒤로가기로 끝낸 판이 반영되지 않는다).
                    loadBoard(kind, withWinner = false)
                    // 역대 — [역대] 를 보는 중일 때만, 오늘 순위 **뒤에** 받는다.
                    if (boardScope == MiniGameBoardScope.allTime && activeKind == kind) performLoadAllTimeBoard()
                } else if (response.status in retryableSubmitStatuses) {
                    // 아직 하한을 못 넘겼다 — 토큰이 살아 있으니 **인편을 남기고** 눈먼 지연 뒤 같은 토큰으로 다시 보낸다.
                    // INV-GamesMiniGameHub-e849bf8a 이식: 여기서 `prefetchRoundToken` 으로 내려가지 않는다. 새 토큰 요청은 서버가
                    //   (사용자, 게임) 행을 갈아 끼워 **지금 되보낼 토큰을 죽인다**. 인편 가드가 한 번 더 막지만 이 갈래의 생명줄이라
                    //   여기서도 명시적으로 비켜 간다.
                    log("submit too early — will retry status=${response.status} game=${kind.rawValue}")
                    scheduleTooFastRetry(kind, score, token)
                    return
                } else {
                    log("submit refused status=${response.status} game=${kind.rawValue}")
                    // 토큰이 죽은 거절은 **그 판이 영영 못 올라간다** — "다시 해 주세요"(복구된다는 뜻)와 문장을 가른다.
                    submitNotice = if (response.status in deadTokenStatuses) GamesMiniGameText.submitTokenDead else GamesMiniGameText.submitRefused
                    exitNoticeIsSticky = false
                    if (response.status in terminalSubmitStatuses) clearPendingSubmit(token)
                }
                prefetchRoundToken(kind)
            } catch (e: Exception) {
                if (e is CancellationException && !AuthErrorRules.isTransport(e)) throw e
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
                if (sessionGeneration != context.generation || generation != resetGeneration) return
                log("submit failed (network) game=${kind.rawValue}")
                // 네트워크 실패는 인편을 **남긴다** — 복귀 때 같은 토큰으로 한 번 더 보낸다.
                submitNotice = GamesMiniGameText.submitFailedConnection
                exitNoticeIsSticky = false
                prefetchRoundToken(kind)
            }
        } finally {
            isSubmitting = false
        }
    }

    /**
     * `too_fast` 를 받은 판을 눈먼 지연 뒤 **같은 토큰으로** 다시 보낸다. 횟수를 다 쓰면 그때 비로소 포기한다.
     * 기다리는 동안은 `submitRetrying`("올리는 중"), 포기할 때만 `submitRefused`.
     */
    private fun scheduleTooFastRetry(kind: MiniGameKind, score: Int, token: String) {
        val previous = tooFastRetries
        val attempt = if (previous?.first == token) previous.second else 0
        exitNoticeIsSticky = false
        if (attempt >= tooFastRetryDelaysSeconds.size) {
            // 묶은 횟수를 다 썼다 — 여기서부터는 사실대로 말하고 인편을 놓아 준다(안 놓으면 선발급이 계속 막힌다).
            log("submit too early — giving up game=${kind.rawValue}")
            submitNotice = GamesMiniGameText.submitRefused
            clearPendingSubmit(token)
            prefetchRoundToken(kind)
            return
        }
        tooFastRetries = token to attempt + 1
        submitNotice = GamesMiniGameText.submitRetrying
        val waitSeconds = tooFastRetryDelaysSeconds[attempt]
        val sessionGeneration = context.generation
        val generation = resetGeneration
        val wait = sleep
        context.scope.launch {
            wait(waitSeconds)
            if (sessionGeneration != context.generation || generation != resetGeneration) return@launch
            // 그 사이 새 판이 인편을 갈아 끼웠거나(그 판의 주인은 새 판이다) 다른 길로 비워졌으면 여기서 멈춘다.
            if (pendingSubmit?.token != token) return@launch
            performSubmit(kind, score, token)
        }
    }

    /** 이 토큰의 인편만 지운다(그 사이 새 판이 인편을 갈아 끼웠으면 건드리지 않는다). */
    private fun clearPendingSubmit(token: String) {
        if (pendingSubmit?.token != token) return
        pendingSubmit = null
        // 재시도 횟수는 인편과 한 벌이다 — 남겨 두면 다음 판이 이 토큰의 횟수를 물려받을 수 있다.
        if (tooFastRetries?.first == token) tooFastRetries = null
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
