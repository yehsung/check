// 원본: Sources/CheckMobileKit/Games/GamesStore.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.games

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.reversi.ReversiNoticeText
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.stores.reversi.ReversiUser
import com.yehsung.aingcheck.core.stores.reversi.isAIMatch as reversiIsAIMatch
import com.yehsung.aingcheck.core.stores.reversi.stopWatching as reversiStopWatching
import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameHub
import com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure
import com.yehsung.aingcheck.core.rules.rummy.RummyCloseDecision
import com.yehsung.aingcheck.core.rules.rummy.RummyPhase
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyInterfaceOrientation
import com.yehsung.aingcheck.core.stores.rummy.GamesRummyOrientationRule
import com.yehsung.aingcheck.core.stores.rummy.RummyAvailability
import com.yehsung.aingcheck.core.stores.rummy.RummyExitReason
import com.yehsung.aingcheck.core.stores.rummy.RummyPhoneText
import com.yehsung.aingcheck.core.stores.rummy.RummyRoomDeparture
import com.yehsung.aingcheck.core.stores.rummy.closeDecision
import com.yehsung.aingcheck.core.stores.rummy.defersMegaphoneBanner
import com.yehsung.aingcheck.core.stores.rummy.departRoom
import com.yehsung.aingcheck.core.stores.rummy.settleAfterLeaving
import com.yehsung.aingcheck.core.stores.tetris.delayMillis
import com.yehsung.aingcheck.core.stores.rummy.appDidBecomeActive as rummyAppDidBecomeActive
import com.yehsung.aingcheck.core.stores.rummy.appDidEnterBackground as rummyAppDidEnterBackground
import com.yehsung.aingcheck.core.stores.rummy.holdsLiveSeat
import com.yehsung.aingcheck.core.stores.rummy.isEngagedInCurrentMatch
import com.yehsung.aingcheck.core.stores.rummy.RummyStore
import com.yehsung.aingcheck.core.stores.rummy.pendingIncomingInviteCount
import com.yehsung.aingcheck.core.stores.rummy.windowDidClose as rummyWindowDidClose
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelUser
import com.yehsung.aingcheck.core.wire.SwiftUUID
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * 게임 탭에서 쌓는 화면(경로 원소).
 *
 * INV-GamesStore-ee149ab9 이식: **값을 더하면 게임 탭 화면(W4 — Android NavGraph 는 조정자 K11)의 목적지 when 을 같이 넓혀야 한다.**
 * Kotlin 은 `when` 이 sealed/enum 을 빠짐없이 가르면 컴파일러가 새 값을 막는다 — 화면 쪽에 `else ->` 를 두지 마라(모르는 목적지가 빈 화면으로
 * 오배달되지 않게).
 */
sealed interface GamesDestination {
    data class MiniGame(val kind: MiniGameKind) : GamesDestination
    data object Gomoku : GamesDestination
    data object Chess : GamesDestination

    /** 1:1 테트리스(1.0.11) — 로비·준비·판·결과·순위를 **입구 하나**로 연다(체스와 같은 구조). */
    data object TetrisDuel : GamesDestination

    /** 아잉 큐브(2~4인) — 로비·방·판·결과·순위를 **입구 하나**로 연다(테트리스와 같은 구조). */
    data object Rummy : GamesDestination

    /**
     * 아잉 뒤집기(판 7 — iOS 1.0.17 `GamesDestination.reversi`) — 로비·판·AI 연습·결과·관전·순위를 **입구 하나**로 연다(체스와 같은 구조 — 화면이
     * `phase`·`spectating` 으로 갈아 끼운다). 떼어 내기 깃발이 꺼진 조립(스토어 없음)에서는 이 목적지로 가는 문이 하나도 서지 않는다.
     */
    data object Reversi : GamesDestination

    /** 1:1 길건너(판 8 — iOS 1.0.18 `GamesDestination.crossyDuel`) — 로비 · 판 · 결과 · 순위를 **입구 하나**로 연다. */
    data object CrossyDuel : GamesDestination
}

/**
 * 지금 **사람과의** 판을 들고 있는 게임 — 한 사람 한 판(B8)의 까닭을 화면이 말할 수 있게 하는 값.
 *
 * 서버는 체스 쪽에서만 두 게임을 함께 본다(`chess__busy`): **오목 쪽 게이트는 체스·테트리스를 모른다**. 그래서 체스·테트리스 중인 사람이
 * 오목을 신청·수락하는 길은 **클라만** 막을 수 있다. 폰은 게임 입구를 한 화면에 같이 띄우므로 **네 방향**을 그려야 한다(아잉 큐브 1.0.x).
 *
 * ★ 값을 더하면 `ChessPhoneText.BusyGame`(rawValue 로 짝짓는다 — ui `chessText()` 가 `first` 로 찾는다)도 같이 넓힌다.
 */
enum class GamesBusyGame(val rawValue: String) {
    gomoku("gomoku"),
    chess("chess"),

    /** 1:1 테트리스(1.0.11). 서버 `chess__busy` 는 셋을 함께 보지만 **오목 쪽 게이트는 여전히 남을 모른다**. */
    tetris("tetris"),

    /** 아잉 큐브. 서버 `chess__busy` 는 모으는 방에 앉은 것(joined)과 판 중(playing)을 함께 바쁨으로 본다 — 방도 막는다. */
    rummy("rummy"),

    /**
     * 아잉 뒤집기(판 7). 서버 `game__busy_users()` 가 리버시 active 판까지 본다(다른 게임과 겹침을 서버도 막는다) — 클라는 **다섯 방향**을 막아
     * 어느 판 때문인지 먼저 그린다(iOS 1.0.17 `GamesBusyGame.reversi`).
     */
    reversi("reversi"),

    /** 1:1 길건너(판 8 — iOS 1.0.18). 서버 `game__busy_users()` 가 길건너 active 판까지 본다 — 클라는 여섯 방향을 막는다. */
    crossyDuel("crossyDuel"),

    /** 1:1 알까기 · 아잉 마작(판 8 — iOS 1.0.18). 마작은 방에 앉은 것(joined)도 바쁨이다. */
    alkkagi("alkkagi"),
    mahjong("mahjong");

    /**
     * 문구 표가 쓰는 이름(Swift `ChessPhoneText.BusyGame.gameName` — 그 표는 W2-d 의 GamesChessText 다).
     * INV-GamesStore-a45f8c41 이식: **빠짐없이 가르는 when 으로 둔다.** 삼항으로 두면 새 게임이 들어올 때 조용히 엉뚱한 이름이 되고
     * (테트리스가 "오목" 으로 읽힌다) 시험은 초록이다 — 1.0.11 에서 실제로 그 꼴이 됐다.
     */
    val gameName: String
        get() = when (this) {
            gomoku -> "오목"
            chess -> "체스"
            tetris -> "1:1 테트리스"
            rummy -> "아잉 큐브"
            reversi -> ReversiNoticeText.gameName
            crossyDuel -> com.yehsung.aingcheck.core.stores.crossy.CrossyDuelNoticeText.gameName
            alkkagi -> "1:1 알까기"
            mahjong -> "아잉 마작"
        }
}

/** 딥링크 한 건을 게임 탭 경로에 옮기는 동작([GamesStore.routeStep]). 화면은 돌려받은 대로 경로만 바꾼다. */
sealed interface GamesRouteStep {
    data object PopToRoot : GamesRouteStep
    data class Push(val destination: GamesDestination) : GamesRouteStep
}

/**
 * 게임 탭 딥링크 요청 — 앱 셸(W1-g/W2-f)이 `AingRoute` 를 이 값으로 옮겨 넘긴다(core/stores 는 앱 모듈의 `AingRoute` 를 볼 수 없다).
 *
 * INV-GamesStore-0dd92a43 이식: **빠짐없는 when 이어야 한다.** `AingRoute.MiniGame` → [MiniGameKind] 옮김은 앱 셸의 when 이 하고
 * (`else ->` 금지 — 모르는 값을 플래피로 오배달하지 않게), 이 요청은 종류를 그대로 실어 온다. 아래 [GamesStore.routeStep] 도 sealed 를
 * 빠짐없이 가른다.
 */
sealed interface GamesRouteRequest {
    /** `games` — 게임 탭 첫 화면. */
    data object Games : GamesRouteRequest
    data class MiniGame(val kind: MiniGameKind) : GamesRouteRequest
    data object GomokuLobby : GamesRouteRequest
    data class GomokuMatch(val matchID: String?) : GamesRouteRequest
    data class GomokuInvite(val inviteID: String) : GamesRouteRequest

    /** 게임 탭 밖 라우트(앱 셸이 다른 탭으로 보낸다). */
    data object Other : GamesRouteRequest
}

/**
 * 게임 탭 스토어(SPEC-ios §3.5) — 탭 자리 API 를 지키고, 갈래를 잇는다.
 *
 * 1. **미니게임** — [miniGames]([GamesMiniGameHub]): 오늘 순위 · 로컬 최고 · 라운드 토큰 · 제출. 엔진은 코어 규칙.
 * 2. **1:1 오목**(W2-d 스토어 — [GamesContext.gomoku] 문). 이 스토어는 **창 수명**을 폰 수명에 옮긴다:
 *    - 오목 화면이 나타남 → `openWindow` + active 면 `windowDidShow`. 사라짐 → `stopWatching` · `windowDidHide` · `windowDidClose`.
 *    - 앱이 background → **가림**(폴링만 멈추고 판에서 나가지 않는다). active 로 돌아옴 → 가림 해제(또는 `windowDidShow`) + 따라잡기.
 *    - 판이 막 시작됨(`presentWindow`) → 앱이 active 면 오목 화면을 연다.
 * 3. **AI 대국** — 선택기는 W2-d 몫. 이 스토어는 "오목 화면이 보이고 앱이 active 인가"를 그 선택기의 허락으로 옮긴다.
 * 4. **1:1 체스**(W2-d — [GamesContext.chess] 문) — 오목과 **같은 세 걸음**.
 * 5. **1:1 테트리스**([GamesContext.tetris] — [TetrisDuelStore]). 체스와 **같은 세 걸음**을 옮기되 갈리는 것이 둘이다.
 *    - 떠나는 길에 `stopWatching()` 이 **없다**: 관전은 로비 탭이 끊는다(`GamesTetrisWatchPlan.tabDidChange`).
 *    - `appDidBecomeActive` 에 **else 가지가 있다**(P8): 화면이 보이면 가림 해제/`windowDidShow()` + `catchUp()`, **안 보이면** `systemDidWake()`.
 *
 * 탭 배지 = 받은 오목 신청 수(체스·테트리스는 안 센다, [badgeCount] 주석).
 *
 * **한 사람 한 판(B8)은 삼각이다** — 세 게임 입구가 한 화면에 있으므로 [chessEntryBlock]·[gomokuEntryBlock]·[tetrisEntryBlock] 셋을 그려야 한다.
 *
 * 화면 꺼짐 방지: Swift 는 `withObservationTracking` 으로 값이 바뀔 때마다 싱크에 넘긴다. Kotlin 은 Compose `snapshotFlow` 로 같은 일을 한다
 * ([installIdleTimerSink] — 싱크는 Android 조립 지점이 `FLAG_KEEP_SCREEN_ON` 으로 단다).
 */
class GamesStore(val context: GamesContext) {
    val miniGames: GamesMiniGameHub = GamesMiniGameHub(context)

    /** 오목 화면이 지금 떠 있다(내비게이션에 올라와 보인다). */
    var isGomokuScreenVisible: Boolean by mutableStateOf(false)
        private set

    /** 체스 화면이 지금 떠 있다(오목과 같은 뜻 — 코어의 '창 표시'를 폰 화면 수명으로 옮긴 값). */
    var isChessScreenVisible: Boolean by mutableStateOf(false)
        private set

    /**
     * 1:1 테트리스 화면이 지금 떠 있다. [appDidBecomeActive] 의 P8 분기가 이 값으로 갈린다 — 거짓인데 `windowDidShow()` 를 부르면
     * **보이지도 않는 판의 준비 보고가 나가고** 사용자는 못 보는 카운트다운에 끌려 들어가 판돈을 잃는다.
     */
    var isTetrisScreenVisible: Boolean by mutableStateOf(false)
        private set

    /**
     * 오목 · 체스 · 테트리스 · 아잉 큐브 · 아잉 뒤집기 화면 중 하나가 떠 있다. 생일 선물 축하 시트(v0.3.66)와 확성기 배너가 이때는 스스로 뜨지 않는다
     * (W2-c `presentCakeGiftIfDue` · PhoneAppModel.isMegaphoneBannerDeferred).
     *
     * 아잉 뒤집기는 **화면으로만** 가른다(오목·체스·테트리스와 같다 — iOS 1.0.17 91ea495d 와 같은 결정). 코어 `defersMegaphoneBanner`(phase == playing)를
     * 쓰지 않는 까닭: 폰 스토어는 같은 계정 **맥이 두는 판**도 로비 `active_match_id` 로 읽어 들고 있어(playing), 그 값을 쓰면 맥이 한 판 두는 동안
     * 폰의 확성기·생일 선물이 통째로 멎는다. 내 판이 흐르는 동안 다른 탭에 있으면 배너를 보는 것이 맞다(체스와 같은 대접).
     */
    val isAnyMatchScreenVisible: Boolean
        get() {
            if (isGomokuScreenVisible || isChessScreenVisible || isTetrisScreenVisible || isReversiScreenVisible || isCrossyDuelScreenVisible) return true
            // 큐브: 손댄 판에서 내 자리가 playing 이면 다른 탭에 있어도 참(언제든 차례가 돌아온다). 놀던 기기가 판을 읽기만 하는 동안 · 기권 뒤 구경은 거짓. 로비 · 방 · 결과 화면은 다른 대결 화면과 같은 대접(iOS 61d75d8c).
            val rummy = context.rummy ?: return false
            return rummy.defersMegaphoneBanner || (isRummyScreenVisible && rummy.phase != RummyPhase.playing)
        }

    /** 아잉 큐브 화면이 지금 떠 있다(코어 '창 표시'를 폰 화면 수명으로 옮긴 값). */
    var isRummyScreenVisible: Boolean by mutableStateOf(false)
        private set

    /**
     * 아잉 뒤집기 화면이 지금 떠 있다(코어 '창 표시'를 폰 화면 수명으로 옮긴 값). [appDidBecomeActive] 가 이 값으로 갈린다 — 거짓인데 `windowDidShow()` 를
     * 부르면 보이지도 않는 판에 폴링이 돌고 AI 연습 판의 사람 시계가 흐른다.
     */
    var isReversiScreenVisible: Boolean by mutableStateOf(false)
        private set

    /** 1:1 길건너 화면(로비 · 판 · 결과)이 떠 있다(판 8 — iOS 1.0.18). */
    var isCrossyDuelScreenVisible: Boolean by mutableStateOf(false)
        private set

    /** 결과에서 [최종 판]을 펴 둔 판. 판 id 를 쥐는 까닭: 다음 판의 결과가 이 표시를 물려받아 저절로 가로가 되면 안 된다. */
    private var rummyFinalBoardMatchID: SwiftUUID? by mutableStateOf(null)

    /** 방장이 방을 떠나려 한다 — 화면이 띄울 "방이 닫혀요" 확인([rummyDepartureAllowed]). */
    var rummyDeparturePrompt: RummyCloseDecision? by mutableStateOf(null)
        private set

    /** 수락하면 원래 가려던 곳으로 가는 일. */
    private var rummyDepartureResume: (() -> Unit)? = null

    /** 마지막 탭 이탈(되보내기를 기다리는 동안 포함). 새 이탈이 앞의 기다림을 끊는다. */
    private var rummyDepartureJob: Job? = null

    /** `rummy_leave` 가 지금 나가는 중이다 — 여럿이 눌러도 하나만 나간다. */
    var isRummyDepartureRunning: Boolean by mutableStateOf(false)
        private set

    /** 나가기를 서버가 확인하지 않은 방. 자리가 남아 있으니 카드가 그 사실을 말한다. */
    private var rummyUnconfirmedLeaveRoomID: SwiftUUID? by mutableStateOf(null)

    /** 나가기가 안 닿았을 때 화면 밖에서 다시 보내기까지(초). 합이 90초를 넘게 둔다: 화면 밖 방은 하트비트를 쉬므로([RummyStore.roomHeartbeatHeld]) 그때쯤이면 서버가 시작 검사에서 이 자리를 뺀다 — 그 전에 망이 돌아오면 이 되보내기가 먼저 나간다. */
    var rummyLeaveRetrySeconds: List<Double> = listOf(3.0, 10.0, 30.0, 60.0)

    /** 탭을 옮겨 방에서 나왔다 — 로비가 한 번 말한다(tabLeftNotice). 코어 notice 에 넣지 않는 까닭: 그 줄은 방 · 판 화면도 읽고, 판 화면에선 차례 안내를 밀어낸다. */
    var rummyLeftByTabNotice: String? by mutableStateOf(null)
        private set

    /** 위 줄을 화면이 한 번 보였다 — 다음에 떠날 때 지운다. 아직 안 보인 줄을 먼저 지우면 돌아온 사람이 못 본다. */
    private var rummyTabLeftNoticeSeen: Boolean = false

    /**
     * 사람이 문을 지나 큐브 화면을 떠났다. 화면은 나가는 전환(기본 700ms) 동안 합성에 남아 [isRummyScreenVisible] 이 아직 참이다 — 그 값으로 '보고 있다'를 재면 빠른 응답이
     * 탭 이탈 안내를 '봤음'으로 적고, 빠른 실패가 되보내기를 끊는다. iOS 는 onDisappear 가 응답보다 먼저 와 이 틈이 없다. 화면이 다시 서거나 사라지면 내린다.
     */
    private var rummyPersonLeftScreen: Boolean = false

    /** 사람이 지금 큐브 화면을 보고 있다(떠나는 길의 판단은 이 값을 본다). */
    private val isPersonOnRummyScreen: Boolean get() = isRummyScreenVisible && !rummyPersonLeftScreen

    /** 지금 판 결과에서 [최종 판]을 보는 중인가. */
    val isRummyFinalBoardShown: Boolean
        get() {
            val id = rummyFinalBoardMatchID ?: return false
            val rummy = context.rummy ?: return false
            return rummy.phase == RummyPhase.finished && rummy.match?.id == id
        }

    fun setRummyFinalBoardShown(shown: Boolean) {
        rummyFinalBoardMatchID = if (shown) context.rummy?.match?.id else null
    }

    /** 화면 방향 — 앱에서 단 하나의 답(GamesRummyOrientation.kt 머리말). 저장하지 않고 지금 상태에서 계산한다. 이 기기가 큐브를 못 하는 안내가 서 있으면 판을 그리지 않으니 세로다. */
    val rummyInterfaceOrientation: GamesRummyInterfaceOrientation
        get() {
            val rummy = context.rummy ?: return GamesRummyInterfaceOrientation.portrait
            return GamesRummyOrientationRule.orientation(
                phase = rummy.phase,
                isScreenVisible = isRummyScreenVisible && rummy.availability == RummyAvailability.available,
                finalBoardShown = isRummyFinalBoardShown,
            )
        }

    /** 앱이 active 다(로그인 상태에서 appDidBecomeActive ~ appDidEnterBackground). */
    var isAppActive: Boolean by mutableStateOf(false)
        private set

    /**
     * 오목 화면을 열 때 보여 줄 신청·판 id(딥링크 `gomoku/invite/<id>` · `gomoku/match/<id>`). 화면이 한 번 꺼내 쓴다.
     * 화면이 **이미 보이면** 여기 남기지 않는다([routeStep] 이 코어에 바로 넘긴다).
     */
    var pendingGomokuFocusID: String? = null

    // INV-GamesStore-e0f4d753 이식: Swift `demoChessRoute` 를 `#if DEBUG` 안에 두는 까닭은 "출시물에 데모 타입 이름 0" 이다. Android·Windows 는
    //   데모 경로를 아예 옮기지 않으므로(C§3.2 "Mob/Demo/* 옮기지 않음 — 픽스처 JSON 만 시험에 쓴다") 이 스토어에 데모 깃발·꼬리 칸이 없다 —
    //   같은 목적을 더 세게 지킨다(릴리스 assets 에 Fixtures 0 은 W1-g 구조 시험이 잰다).
    // INV-GamesStore-df2b4ca2 이식: 같은 근거(`demoTetrisRoute` 의 `#if DEBUG`) — 데모 꼬리 칸을 두지 않는다.

    /** 화면 꺼짐 방지를 실제로 거는 곳(Android 조립은 창 FLAG_KEEP_SCREEN_ON · 시험은 기록용). */
    private var idleTimerSink: ((Boolean) -> Unit)? = null
    private var idleTimerJob: Job? = null

    /** 마지막으로 싱크에 넘긴 값(같은 값은 다시 넘기지 않는다). 싱크가 없으면 null. */
    var appliedIdleTimerDisabled: Boolean? = null
        private set

    init {
        // 판이 막 시작됐다(내 신청이 수락됨 · 내가 수락함 · 앱을 다시 켜니 진행 중인 판) — 오목 화면을 연다.
        context.gomoku.presentWindow = { presentGomokuScreen() }
        // 체스도 같은 문이 필요하다. 맥에서 이 문을 안 물려 **판돈이 걸린 판을 조용히 시간패**했다.
        context.chess.presentWindow = { presentChessScreen() }
        // 테트리스도 **같은 문**이다. 안 물리면 수락·시작이 화면을 못 연다 — 테트리스는 15초 침묵(D5)이 붙어 **수락한 판이 화면 없이 그대로 진다.**
        context.tetris.presentWindow = { presentTetrisScreen() }
        // 아잉 큐브도 **같은 문**이다. 안 물리면 방장이 시작한 판이 화면 없이 흘러 시간 초과가 쌓이고 3회째 기권(꼴찌)이 된다. 스토어가 없는 조립(데스크톱)은 건너뛴다.
        context.rummy?.presentWindow = { presentRummyScreen() }
        // 방 화면을 떠나는 길은 이 문 하나를 지난다(탭 막대 · 푸시 · 딥링크 · 위젯 · 다른 대결 화면 열기).
        if (context.rummy != null) context.router.installDepartureGuard { resume -> rummyDepartureAllowed(resume) }
        // 방 화면이 설 때만 방 하트비트를 돌린다(rummyScreenDidAppear) — 어느 길로 화면 밖에 앉게 됐든(앱을 다시 켬 · 다른 게임 화면이 덮음) 모르는 사이 판돈이 걷히지 않는다.
        context.rummy?.roomHeartbeatHeld = true
        // 아잉 뒤집기도 **같은 문**이다. 안 물리면 수락·시작이 화면을 못 연다 — 신청자는 수락된 순간을 몰라 흑 30초를 흘리고 자동 착수가 쌓인다
        // (연속 3번이면 판돈째 진다). 코어가 부르는 자리 셋: `openWindow` · 수락 응답(`respond`) · 진행 판으로 처음 넘어갈 때(`noteMatchProgress`).
        // 로그아웃 `reset()` 이 부르는 `dismissWindow` 는 달지 않는다 — 폰은 로그아웃의 `router.reset()` 이 경로를 비운다. 스토어가 없는 조립은 건너뛴다.
        context.reversi?.presentWindow = { presentReversiScreen() }
        // 1:1 길건너도 **같은 문**이다(판 8 — iOS 1.0.18). 안 물리면 수락·시작이 화면을 못 연다 — 30초 준비 문이 닫히면 판돈이 돌아오지만 판은 안 선다.
        context.crossyDuel?.presentWindow = { presentCrossyDuelScreen() }
    }

    // MARK: 자리 API

    fun appDidBecomeActive() {
        isAppActive = true
        syncAIThinker()
        // background 로 가며 끝낸 판의 제출이 네트워크로 실패했으면 **같은 토큰으로** 한 번 더(세 게임 모두).
        miniGames.retryPendingSubmitIfAny()
        val gomoku = context.gomoku
        // 받은 신청(탭 배지·첫 화면 카드)의 신선도. 60초 스로틀은 코어가 한다.
        gomoku.refreshInboxIfStale()
        if (isGomokuScreenVisible) {
            if (gomoku.isWindowVisible) gomoku.windowOcclusionDidChange(visible = true) else gomoku.windowDidShow()
            // background 동안 놓친 것(신청·수락·상대 수). 서버 시계는 그동안에도 흘렀다.
            context.scope.launch { gomoku.catchUp() }
        }
        // 체스: 같은 세 걸음. 체스는 시계가 **서버에서만** 흐르고 자동 착수가 없어 돌아온 순간의 따라잡기가 더 중요하다.
        val chess = context.chess
        chess.refreshLobbyIfStale()
        // INV-GamesStore-bb34b219 이식: 예전엔 여기가 `guard isChessScreenVisible else { return }` 였다. **`if` 로 바꾼 것이 계약이다** —
        //   아래 테트리스 가지가 이 함수의 꼬리에 붙으므로, guard 로 두면 "체스 화면이 안 보일 때"(= 거의 늘) 테트리스 따라잡기가
        //   **한 번도 안 돈다.** 새 게임을 더할 때도 꼬리에 guard(early return)를 쓰지 마라.
        if (isChessScreenVisible) {
            if (chess.isWindowVisible) chess.windowOcclusionDidChange(visible = true) else chess.windowDidShow()
            context.scope.launch { chess.catchUp() }
        }
        // 테트리스(P8): **깨어남은 한 번만 따라잡는다.**
        //  · 화면이 보이면 — 창이 서 있으면 가림만 풀고, 안 서 있으면 `windowDidShow()`. 그리고 `catchUp()`.
        //  · 안 보이면 — `systemDidWake()`. 받은 신청 칩과 한 사람 한 판의 `activeMatchID` 가 이 계기에 달려 있다. 체스처럼
        //    30초 스로틀을 쓰지 않는 까닭은 테트리스가 **판돈이 걸린 실시간 판**이라서다.
        // INV-GamesStore-93f09a31 이식: **두 가지를 겹쳐 부르지 마라.** `catchUp()` 과 `systemDidWake()` 는 **본문이 같다**(둘 다
        //   `refreshLobby()`). 겹쳐도 코어 `lobbyInFlight` 가드가 합치지만, `windowDidShow()` 를 화면 없이 부르면 **보이지 않는 판의 준비 보고가 나간다.**
        val tetris = context.tetris
        if (isTetrisScreenVisible) {
            if (tetris.isWindowVisible) tetris.windowOcclusionDidChange(visible = true) else tetris.windowDidShow()
            context.scope.launch { tetris.catchUp() }
        } else {
            tetris.systemDidWake()
        }
        // 아잉 큐브: 테트리스와 같은 두 가지(겹쳐 부르지 않는다) + 이 판에 쥔 자리의 하트비트를 **바로 한 번**(코어 appDidBecomeActive).
        // 꼬리에 guard 를 쓰지 않는다(위 INV-GamesStore-bb34b219 — 뒤에 올 게임을 죽인다).
        context.rummy?.let { rummy ->
            rummy.rummyAppDidBecomeActive()
            if (isRummyScreenVisible) {
                if (rummy.isWindowVisible) rummy.setWindowOccluded(false) else rummy.setWindowVisible(true)
                context.scope.launch { rummy.catchUp() }
            } else {
                rummy.systemDidWake()
            }
        }
        // 아잉 뒤집기: 체스와 같은 세 걸음이되 **두 갈래를 겹쳐 부르지 않는다**(iOS 1.0.17).
        //  · 화면이 보이면 — 창이 서 있으면 가림만 풀고(background 에서 '가림'으로 멈춘 폴링 · AI 사람 시계를 되살린다), 안 서 있으면 `windowDidShow()`.
        //    그리고 `catchUp()` 으로 background 동안 놓친 것을 읽는다(신청·수락·상대 수·서버가 대신 둔 수 — 시계는 서버에서 흘렀다).
        //  · 안 보이면 — `refreshLobbyIfStale()`(30초 스로틀). 탭 배지의 받은 신청과 한 사람 한 판의 `activeMatchID` 가 이 계기에 달려 있다.
        // 꼬리에 guard 를 쓰지 않는다(위 INV-GamesStore-bb34b219 — 뒤에 올 게임을 죽인다).
        context.reversi?.let { reversi ->
            if (isReversiScreenVisible) {
                if (reversi.isWindowVisible) reversi.windowOcclusionDidChange(visible = true) else reversi.windowDidShow()
                context.scope.launch { reversi.catchUp() }
            } else {
                reversi.refreshLobbyIfStale()
            }
        }
        // 1:1 길건너(판 8 — iOS 1.0.18): 화면이 보이면 가림을 풀거나 창을 세우고 신호 동기화 한 번, 안 보이면 가벼운 로비(30초 스로틀).
        context.crossyDuel?.let { duel ->
            if (isCrossyDuelScreenVisible) {
                if (duel.isWindowVisible) duel.windowOcclusionDidChange(visible = true) else duel.windowDidShow()
                duel.requestSync()
            } else {
                duel.refreshLobbyIfStale()
            }
        }
        syncIdleTimer()
    }

    /**
     * 장면이 앞에서 물러난다(Android ON_PAUSE — iOS `.inactive`: 앱 전환 · 다중 창 · 잠금 직전). 도는 미니게임을 얼린다. 연결·폴링은 건드리지 않는다: 곧 돌아오는 일이 대부분이다.
     * 원본: Sources/CheckMobileKit/Games/GamesStore.swift:247-251 @ de5c153b.
     */
    fun sceneWillResignActive() {
        miniGames.appWillResignActive()
    }

    /** 장면이 앞으로 왔다(ON_RESUME · 프로세스 ON_START). 얼어 있던 판의 상한을 재고 토큰을 챙긴다 — 자동으로 풀지는 않는다. */
    fun sceneDidComeForward() {
        miniGames.sceneDidComeForward()
    }

    fun appDidEnterBackground() {
        isAppActive = false
        // AI 탐색은 background 에서 돌지 않는다(돌아오면 처음부터 다시 생각한다).
        syncAIThinker()
        miniGames.appDidEnterBackground()
        // 오목은 **가림**으로 멈춘다 — 폴링만 멈추고 창은 닫지 않는다. `windowDidHide` 를 부르면 결과 화면인 채로 잠깐 앱을 나갔을 뿐인데
        // 그 판에서 '나간' 것이 되어(gomoku_leave) 인사 채팅이 서버에서 지워진다. 관전도 여기서 끊지 않는다.
        if (isGomokuScreenVisible && context.gomoku.isWindowVisible) context.gomoku.windowOcclusionDidChange(visible = false)
        // 체스도 **가림**이다(결과 화면 · 진행 중인 남의 판 관전을 지킨다).
        if (isChessScreenVisible && context.chess.isWindowVisible) context.chess.windowOcclusionDidChange(visible = false)
        // 테트리스도 **가림**이다. `windowDidHide()` 는 `windowDidClose()` 와 짝을 이뤄 끝난 판을 접는 길이라, 알림 하나 읽고 온 사람의
        // 결과 카드가 사라져 루비가 얼마 움직였는지 못 보고 로비로 떨어진다.
        // INV-GamesStore-e32aee34 이식: **판은 멈추지 않는다**(P7·D10). 가림은 폴링만 멈추고 눌린 키를 놓는다 — 조각은 단조 시계로 계속
        //   떨어지고, OS 가 판 루프를 재우면 서버가 15초 침묵으로 내 패(`disconnect`)로 닫는다. 그것이 의도다(화면을 가려 이득을 보는 길이
        //   없어야 한다). 그래서 화면이 **그 사실을 말한다** — "판 중에 앱을 나가면 져요".
        if (isTetrisScreenVisible && context.tetris.isWindowVisible) context.tetris.windowOcclusionDidChange(visible = false)
        // 아잉 큐브도 **가림**이다. 뒤로 가는 것은 기권이 아니다 — 정책은 코어 `appDidEnterBackground` 한 곳(서버 90초 규칙에 맡긴다).
        context.rummy?.let { rummy ->
            rummy.rummyAppDidEnterBackground()
            if (isRummyScreenVisible && rummy.isWindowVisible) rummy.setWindowOccluded(true)
        }
        // 아잉 뒤집기도 **가림**이다(체스와 같은 까닭 둘 — 결과 화면이 접히지 않고, 보던 관전이 끊기지 않는다). 가림은 폴링 · AI 사람 시계 · 뒤집기 그림만
        // 멈춘다. ★ **1:1 판은 멈추지 않는다** — 서버 시계가 흐르고 30초가 지나면 서버가 대신 둔다(연속 3번이면 패).
        context.reversi?.let { reversi ->
            if (isReversiScreenVisible && reversi.isWindowVisible) reversi.windowOcclusionDidChange(visible = false)
        }
        // 1:1 길건너도 **가림**이다(결과 카드를 지킨다). ★ 판은 멈추지 않는다 — 판 루프는 단조 시계로 흐르고 서버 시계도 흐른다.
        context.crossyDuel?.let { duel ->
            if (isCrossyDuelScreenVisible && duel.isWindowVisible) duel.windowOcclusionDidChange(visible = false)
        }
        syncIdleTimer()
    }

    fun reset() {
        miniGames.reset()
        isGomokuScreenVisible = false
        isChessScreenVisible = false
        isTetrisScreenVisible = false
        isRummyScreenVisible = false
        isReversiScreenVisible = false
        isCrossyDuelScreenVisible = false
        rummyPersonLeftScreen = false
        rummyFinalBoardMatchID = null
        rummyDeparturePrompt = null
        rummyDepartureResume = null
        rummyDepartureJob?.cancel()
        rummyDepartureJob = null
        isRummyDepartureRunning = false
        rummyUnconfirmedLeaveRoomID = null
        rummyLeftByTabNotice = null
        rummyTabLeftNoticeSeen = false
        context.rummy?.roomHeartbeatHeld = true
        pendingGomokuFocusID = null
        syncAIThinker()
        syncIdleTimer()
    }

    /** 코어 체스 스토어 문(= `context.chess`). */
    val chess: GamesBoardGameLink get() = context.chess

    /** 코어 테트리스 대결 스토어 줄임(= `context.tetris`). 화면·다른 갈래가 읽는 자리는 **두 이름이 같은 인스턴스**다. */
    val tetris: TetrisDuelStore get() = context.tetris

    /** 코어 아잉 뒤집기 스토어 줄임(= `context.reversi`). null = 이 조립에 리버시가 없다(Windows · 떼어 내기 깃발 끔) — 카드·화면 문을 세우지 않는다. */
    val reversi: ReversiStore? get() = context.reversi

    /** 코어 1:1 길건너 스토어 줄임(= `context.crossyDuel`, 판 8). null = 이 조립에 없다. */
    val crossyDuel: com.yehsung.aingcheck.core.stores.crossy.CrossyDuelStore? get() = context.crossyDuel

    /**
     * 탭 배지: 만료 안 된 받은 오목 신청 수 + 받은 아잉 큐브 초대 수.
     *
     * 아잉 큐브를 세는 까닭: 체스·테트리스와 달리 초대 수명이 10분이고(60초 TTL 이 아니다) 'rummy' 초인종이 로비를 다시 읽어 숫자가 늦지 않는다.
     * 잠긴 빌드는 코어가 0 을 낸다(§8-17 #1).
     *
     * INV-GamesStore-7d3fdc37 이식: **체스 신청은 아직 안 센다.** 체스는 받은함 RPC 가 없어 받은 신청을 `chess_lobby` 로만 알고, 그 조회는
     * 허브·체스 화면에서만 나간다 — 배지에 넣으면 "60초 TTL 짜리 숫자가 30초 스로틀로 갱신되는" 꼴이 되어 없는 신청을 가리키거나 놓친다.
     * INV-GamesStore-3d7a8f45 이식: **테트리스 신청도 안 센다**(P5 — 같은 근거다). 받은 신청이 `tetris_lobby` 응답에만 실려 오고 그 조회는
     * **게임 탭·테트리스 화면에서만** 나간다. 알리는 자리는 **둘**이다: 게임 탭 테트리스 카드의 "받은 신청" 칩 · 테트리스 화면 로비 맨 위 신청 카드.
     *
     * **아잉 뒤집기 신청도 센다**(판 7 — iOS 1.0.17 `badgeCount` 와 같은 근거): 초인종을 잇는다('reversi' → `handleSignal` → 판이 없으면 로비). 신청이 오면
     * 그 자리에서 로비를 읽어 `me.incoming` 을 갈아 끼우고, 60초 만료는 코어 타이머가 `incoming` 에서 걷는다 — 숫자가 30초 스로틀에 묶이지 않는다.
     * 차단 거울·판돈 깃발(§8-17 #1 — 잠긴 빌드는 0)을 거친 값(`visibleIncomingInvites`)을 센다. 스토어가 없는 조립(떼어 내기 깃발 끔)은 판 7 이전 값 그대로다.
     */
    val badgeCount: Int
        get() = context.gomoku.pendingIncomingInviteCount + (context.rummy?.pendingIncomingInviteCount ?: 0) +
            (context.reversi?.visibleIncomingInvites?.size ?: 0) +
            // 1:1 길건너(판 8 — iOS 1.0.18 badgeCount): 초인종을 잇고 만료는 코어 타이머가 걷는다(뒤집기와 같은 근거). 판돈 깃발이 꺼진 빌드는 수락할 수 없어 0.
            (context.crossyDuel?.takeIf { it.duelsEnabled }?.visibleIncomingInvites?.size ?: 0)

    /** 게임 탭이 보여 주는 루비 잔액 — **공유 미러**를 먼저 읽는다(나 탭 상점 구매가 미러만 적는다). 미러를 모르면 테트리스 코어 값. */
    val rubyBalance: Long? get() = context.sharedRubyBalance ?: context.tetris.rubyBalance

    /**
     * 오목 로비의 **상대 고르기 목록** — 메시지 탭에서 차단해 숨긴 사람을 걷어낸 것. 화면이 읽는 자리는 여기 하나다.
     *
     * 차단 확인 시트가 "사람 찾기와 오목 신청에서 서로 보이지 않아요" 라고 약속하는데, 코어 `users` 는 서버 로비 응답 그대로라 방금 차단한
     * 사람이 [도전] 버튼과 함께 그대로 서 있었다 — 사용자가 방금 읽은 세 줄 중 한 줄이 눈앞에서 거짓이 된다(메시지 탭 `filteredDirectory` 와
     * 같은 근거 · 같은 방식). **거르는 것은 화면이 읽는 이 자리뿐**이다: 코어 목록은 서버가 답한 그대로 둬야 차단이 실패했을 때 그대로 돌아온다.
     * 서버도 로비 응답에서 서로 차단한 사람을 빼 줘야 **반대쪽**에서도 사라진다(`gomoku_lobby`).
     *
     * [gomoku] 는 오목 스토어(W2-d — [GamesLobbyRoster] 를 구현한다). 게임 탭 스토어는 그 사용자 타입을 모르므로 화면이 넘긴다.
     */
    fun <U> gomokuLobbyUsers(gomoku: GamesLobbyRoster<U>): List<U> = hidingBlockedPeers(gomoku.lobbyUsers, gomoku::lobbyUserID)

    /**
     * 체스 로비의 **상대 고르기 목록** — 같은 근거·같은 방식(위 오목 주석). 코어 `visibleUsers` 는 스토어가 쥔 `hiddenPeerIDs`(폰은 안
     * 채운다)까지 거른 값이고, 거기에 메시지 탭의 차단 목록을 한 번 더 겹친다. **정렬은 하지 않는다** — 코어 `applyLobby` 가 서버와 같은
     * 규칙(근무 중·가능 → 대국 중 → …)으로 이미 맞춰 뒀고, 화면이 다시 정렬하면 두 규칙이 갈린다.
     */
    fun <U> chessLobbyUsers(chess: GamesLobbyRoster<U>): List<U> = hidingBlockedPeers(chess.lobbyUsers, chess::lobbyUserID)

    /**
     * 테트리스 로비의 상대 고르기 목록 — 같은 근거·같은 방식(위 두 주석). 코어 `visibleUsers` 는 스토어가 쥔 `hiddenPeerIDs` 까지
     * 거른 값이고, 거기에 메시지 탭의 차단 목록을 한 번 더 겹친다. **정렬은 하지 않는다**(코어 `applyLobby` 가 서버와 같은 규칙으로 이미
     * 맞춰 뒀다 — 화면이 다시 정렬하면 두 규칙이 갈린다).
     */
    val tetrisLobbyUsers: List<TetrisDuelUser>
        get() = hidingBlockedPeers(context.tetris.visibleUsers) { it.id }

    /**
     * 아잉 뒤집기 로비의 상대 고르기 목록 — 같은 근거·같은 방식(위 세 주석). 코어 `visibleUsers` 는 차단 거울([syncReversiHiddenPeers])까지 거른 값이고,
     * 거기에 메시지 탭의 차단 목록을 **지금 값으로** 한 번 더 겹친다. **정렬은 하지 않는다**(코어 `sortedForLobby` 가 이미 맞춰 뒀다). 스토어가 없으면 빈 목록.
     */
    val reversiLobbyUsers: List<ReversiUser>
        get() = hidingBlockedPeers(context.reversi?.visibleUsers ?: emptyList()) { it.id }

    /** 세 로비가 같은 규칙으로 거른다: 메시지 탭 차단 목록이 비면 코어 목록 그대로(같은 순서), 아니면 그 사람만 뺀다. */
    private fun <U> hidingBlockedPeers(users: List<U>, id: (U) -> String): List<U> {
        val hidden = context.hiddenBlockedPeerIDs
        if (hidden.isEmpty()) return users
        return users.filter { id(it) !in hidden }
    }

    // MARK: 한 사람 한 판 (B8 — 세 방향)

    /**
     * 사람과의 **오목** 판이 지금 흐르고 있는가. 둘을 뺀다: **AI 판**과 **끝난 판**(결과 화면은 판이 아니다).
     * 서버가 말한 진행 판 id(`activeMatchID`)는 들고 있는 판이 없어도 참이다 — 앱을 막 켠 사람의 판이 그 갈래다.
     */
    val hasLiveGomokuMatch: Boolean
        get() {
            val gomoku = context.gomoku
            if (gomoku.activeMatchID != null) return true
            if (!gomoku.hasUnfinishedMatch) return false
            return !gomoku.isAIMatch
        }

    /** 사람과의 **체스** 판이 지금 흐르고 있는가(위와 같은 규칙 — 로봇 판·끝난 판은 아니다). */
    val hasLiveChessMatch: Boolean
        get() {
            val chess = context.chess
            if (chess.activeMatchID != null) return true
            if (!chess.hasUnfinishedMatch) return false
            return !chess.isAIMatch
        }

    /**
     * 사람과의 **테트리스** 대결이 지금 흐르고 있는가. 테트리스에는 AI 판이 없으므로 가를 것이 하나 적다.
     *
     * INV-GamesStore-a5e996d5 이식: **`activeMatchID` 를 먼저 본다**(오목·체스와 같은 순서). 서버가 말한 진행 판 id 는 **들고 있는 판이
     *   없어도 참**이고, 그 틈이 테트리스에서는 **열린 채로 남을 수 있다**: 로비 응답이 `active_match_id` 를 주면 코어가 곧바로
     *   `refreshMatch` 를 쏘지만 그 `tetris_state` 가 네트워크로 실패하면 `match` 는 영영 null 인 채 id 만 남는다. 그 사이 오목·체스 입구가
     *   열려 있고, 그 길로 오목을 수락하면 흐르던 테트리스 판은 15초 침묵으로 **판돈째 진다**(D5). 닫는 쪽으로 틀리는 것이 맞다.
     */
    val hasLiveTetrisMatch: Boolean
        get() {
            val tetris = context.tetris
            if (tetris.activeMatchID != null) return true
            val match = tetris.match ?: return false
            return !match.isFinished
        }

    /**
     * 사람과의 **아잉 큐브** 방·판이 지금 있는가. 서버 `chess__busy` 와 같은 술어다 — 모으는 방에 앉았거나(joined) 판 중(playing).
     * 서버가 말한 내 방·판 id 는 들고 있는 것이 없어도 참이다(테트리스와 같은 까닭 — 닫는 쪽으로 틀리는 것이 맞다). 단 **그 판을 들고 있으면 그 판으로 판단한다**(로비 id 는 낡을 수 있다 —
     * 끝난 판 · 내가 기권한 자리는 구경이다. 로비 재조회가 실패하면 id 가 남아 입구가 닫힌 채로 굳는다. iOS `hasLiveRummyMatch` 와 같다).
     */
    val hasLiveRummyMatch: Boolean
        get() {
            val rummy = context.rummy ?: return false
            val active = rummy.activeMatchID
            if (active != null && rummy.match?.id != active) return true
            return rummy.holdsLiveSeat
        }

    /**
     * 사람과의 **아잉 뒤집기** 판이 지금 흐르고 있는가(오목·체스와 같은 규칙 — AI 연습 판·끝난 판은 아니다). 스토어가 없는 조립은 늘 false.
     * ★ `activeMatchID` 를 먼저 본다(테트리스 주석과 같은 근거): 로비가 진행 판 id 를 주면 코어가 곧바로 `reversi_state` 를 쏘지만, 그 조회가 실패하면
     *   `match` 는 null 인 채 id 만 남는다. 그 틈에 오목을 수락하면 흐르던 리버시 판은 30초마다 서버가 대신 두고 3번째에 **판돈째 진다**. AI 판 id 는
     *   이 칸에 오르지 않는다(서버 판만 적는다).
     * ★ 같은 계정의 **다른 기기**(맥)가 두는 판도 막는다 — 한 사람은 한 판만이다(서버 `game__busy_users` 도 기기를 가리지 않는다).
     */
    val hasLiveReversiMatch: Boolean
        get() {
            val reversi = context.reversi ?: return false
            if (reversi.activeMatchID != null) return true
            val match = reversi.match ?: return false
            return !match.isFinished && !match.isAI
        }

    /**
     * **AI 연습 판**이 지금 진행 중인가(끝난 판은 아니다). 서버는 이 판을 볼 수 없다(행이 없다). 코어 `challenge`·`respond` 에는 AI 가드가 없어 1:1 판이
     * 서는 순간 두던 AI 판이 문구 없이 버려진다 — 신청은 [com.yehsung.aingcheck.core.stores.reversi.GamesReversiChallengeGate] 가, 수락은 화면 확인이 막는다.
     */
    /** 1:1 길건너 진행 판(사람끼리뿐). 서버가 말한 id 또는 들고 있는 안 끝난 판(판 8 — iOS 1.0.18). */
    val hasLiveCrossyDuelMatch: Boolean
        get() {
            val duel = context.crossyDuel ?: return false
            if (duel.activeMatchID != null) return true
            val match = duel.match ?: return false
            return !match.isFinished
        }

    val hasLiveReversiAIGame: Boolean
        get() {
            val reversi = context.reversi ?: return false
            val match = reversi.match ?: return false
            return reversi.reversiIsAIMatch && !match.isFinished
        }

    /** 체스 입구를 막는 까닭(없으면 null). 오목·테트리스·큐브·리버시 판이 흐르면 체스를 신청·수락할 수 없다 — 서버도 같은 판정을 한다. */
    val chessEntryBlock: GamesBusyGame?
        get() {
            if (hasLiveGomokuMatch) return GamesBusyGame.gomoku
            if (hasLiveTetrisMatch) return GamesBusyGame.tetris
            if (hasLiveRummyMatch) return GamesBusyGame.rummy
            if (hasLiveReversiMatch) return GamesBusyGame.reversi
            return if (hasLiveCrossyDuelMatch) GamesBusyGame.crossyDuel else null
        }

    /**
     * 오목 입구를 막는 까닭(없으면 null).
     * INV-GamesStore-a6af4558 이식: **이 방향은 클라밖에 막는 데가 없다** — 서버의 오목 게이트는 체스·테트리스를 모른다.
     * 안 막으면 체스 중인 사람이 오목을 수락해 체스를 시간패한다.
     */
    val gomokuEntryBlock: GamesBusyGame?
        get() {
            if (hasLiveChessMatch) return GamesBusyGame.chess
            if (hasLiveTetrisMatch) return GamesBusyGame.tetris
            if (hasLiveRummyMatch) return GamesBusyGame.rummy
            if (hasLiveReversiMatch) return GamesBusyGame.reversi
            return if (hasLiveCrossyDuelMatch) GamesBusyGame.crossyDuel else null
        }

    /**
     * 테트리스 입구를 막는 까닭(없으면 null). 테트리스는 **판돈이 걸린 실시간 판**이라 막는 쪽이 더 무겁다 —
     * 오목·체스 판을 두는 중에 테트리스를 수락하면 그 판은 15초 침묵으로 **진다**(서버 D5).
     */
    val tetrisEntryBlock: GamesBusyGame?
        get() {
            if (hasLiveGomokuMatch) return GamesBusyGame.gomoku
            if (hasLiveChessMatch) return GamesBusyGame.chess
            if (hasLiveRummyMatch) return GamesBusyGame.rummy
            if (hasLiveReversiMatch) return GamesBusyGame.reversi
            return if (hasLiveCrossyDuelMatch) GamesBusyGame.crossyDuel else null
        }

    /**
     * 아잉 큐브 입구(방 만들기 · 참가)를 막는 까닭(없으면 null). 넷째 방향이다 — 다른 판을 두는 중에 방에 앉으면 시작 때 서버가 빠뜨리거나(`seats_dropped`)
     * 그 판을 시간패한다. 만들기·참가는 서버도 `busy` 로 막지만 화면이 먼저 말한다.
     */
    val rummyEntryBlock: GamesBusyGame?
        get() {
            if (hasLiveGomokuMatch) return GamesBusyGame.gomoku
            if (hasLiveChessMatch) return GamesBusyGame.chess
            if (hasLiveTetrisMatch) return GamesBusyGame.tetris
            if (hasLiveReversiMatch) return GamesBusyGame.reversi
            return if (hasLiveCrossyDuelMatch) GamesBusyGame.crossyDuel else null
        }

    /**
     * 아잉 뒤집기 입구를 막는 까닭(없으면 null) — 다섯 방향의 마지막 하나. 서버도 막는다(`reversi_challenge`·`reversi_respond` 가 `game__busy_users` 를 본다) —
     * 이 값은 **어느 판 때문인지** 화면이 먼저 말하게 한다. 판돈 걸린 다른 판을 두는 중에 리버시를 수락하면 그 판이 시간패한다(테트리스는 15초 침묵).
     */
    val reversiEntryBlock: GamesBusyGame?
        get() {
            if (hasLiveGomokuMatch) return GamesBusyGame.gomoku
            if (hasLiveChessMatch) return GamesBusyGame.chess
            if (hasLiveTetrisMatch) return GamesBusyGame.tetris
            if (hasLiveRummyMatch) return GamesBusyGame.rummy
            return if (hasLiveCrossyDuelMatch) GamesBusyGame.crossyDuel else null
        }

    /** 1:1 길건너 입구 막기(판 8 — iOS 1.0.18) — 다른 1:1 중 하나가 흐르면 그 까닭을 먼저 말한다(서버도 `game__busy_users` 로 막는다). */
    val crossyDuelEntryBlock: GamesBusyGame?
        get() {
            if (hasLiveGomokuMatch) return GamesBusyGame.gomoku
            if (hasLiveChessMatch) return GamesBusyGame.chess
            if (hasLiveTetrisMatch) return GamesBusyGame.tetris
            if (hasLiveRummyMatch) return GamesBusyGame.rummy
            return if (hasLiveReversiMatch) GamesBusyGame.reversi else null
        }

    /**
     * **로봇 체스 판**이 지금 진행 중인가(끝난 판은 아니다).
     * INV-GamesStore-8001b21f 이식: 서버는 이 판을 **볼 수 없다.** `chess__busy` 는 `chess_matches`·`gomoku_matches` 만 보고 로봇 판은 서버에
     *   행이 없다. 그래서 로봇 판 중 → 1:1 신청·수락은 그대로 나간다(코어 `challenge` 에 `isAIMatch` 가드가 없다). 그러면 1:1 판이 서는 순간
     *   두던 로봇 판이 말없이 사라진다 — 신청은 게이트가([GamesChessChallengeGate]·[GamesChessStakeSend]), 수락은 확인 시트(화면)가 막는다.
     */
    val hasLiveChessRobotGame: Boolean
        get() {
            val chess = context.chess
            return chess.isAIMatch && chess.hasUnfinishedMatch
        }

    // MARK: 첫 화면

    /** 게임 탭 첫 화면이 보였다: 카드의 오늘 최고·순위 · 받은 신청. */
    fun hubDidAppear() {
        if (!context.sessionStore.isSignedIn) return
        miniGames.refreshSummariesIfStale()
        context.gomoku.refreshInboxIfStale()
        // 체스는 **받은함 RPC 가 없다** — 받은 신청·진행 중 판·내 전적이 전부 `chess_lobby` 의 `me` 로 온다. 허브에서 한 번 당긴다(30초 스로틀).
        // INV-GamesStore-5bfb7b2a 이식: 조회를 더하는 값은 **한 사람 한 판**이다: 이 조회가 없으면 앱을 막 켠 사람의 `activeMatchID` 가 null 이라
        //   체스 판이 흐르는 중에도 오목 카드가 열려 있고, 그 길로 오목을 수락하면 체스가 시간패한다.
        context.chess.refreshLobbyIfStale()
        // 테트리스도 **받은함 RPC 가 없다**(P5) — 받은 신청·보낸 신청·진행 중 판 id·내 전적이 전부 `tetris_lobby` 의 `me` 로 온다.
        // INV-GamesStore-3a18e01e 이식: 이 조회가 없으면 **둘이 함께 죽는다**: ① 카드의 "받은 신청" 칩이 영영 비어 있다(받은 신청을 알 자리가
        //   통째로 사라진다), ② 앱을 막 켠 사람의 `activeMatchID` 가 null 이라 테트리스 판이 흐르는 중에도 오목·체스 카드가 열려 있다.
        context.tetris.refreshLobbyIfStale()
        // 아잉 큐브도 받은함 RPC 가 없다 — 받은 초대(배지)·내 방·판 id 가 전부 `rummy_lobby` 로 온다(30초 스로틀 · 잠긴 빌드는 코어가 안 낸다).
        context.rummy?.refreshLobbyIfStale()
        // 아잉 뒤집기도 **받은함 RPC 가 없다** — 받은 신청·보낸 신청·진행 판 id·전적이 전부 `reversi_lobby` 의 `me` 로 온다. 허브에서 한 번 당긴다(30초
        // 스로틀 — 로비는 사람마다 `reversi_capable` 을 부르는 무거운 조회라 스로틀을 꼭 지난다). 빠지면 둘이 함께 죽는다: ① 카드 칩과 탭 배지가 다음 초인종까지
        // 비고, ② 앱을 막 켠 사람의 `activeMatchID` 가 null 이라 리버시 판(같은 계정 맥의 판 포함)이 흐르는 중에도 다른 카드가 열려 있다.
        if (context.reversi != null) {
            syncReversiHiddenPeers()
            context.reversi?.refreshLobbyIfStale()
        }
        // 1:1 길건너도 받은함 RPC 가 없다 — 받은 신청 · 진행 판 id 가 `crossy_duel_lobby` 로 온다(30초 스로틀).
        if (context.crossyDuel != null) {
            syncCrossyDuelHiddenPeers()
            context.crossyDuel?.refreshLobbyIfStale()
        }
    }

    /** 차단 거울(맥 `WorkTimerStore` 의 `crossyDuel.hiddenPeerIDs = blockHiddenPeerIDs` 와 같은 길). 코어는 소문자 uuid. */
    fun syncCrossyDuelHiddenPeers() {
        val duel = context.crossyDuel ?: return
        val hidden = context.hiddenBlockedPeerIDs.map { it.lowercase() }.toSet()
        if (duel.hiddenPeerIDs != hidden) duel.hiddenPeerIDs = hidden
    }

    /**
     * 아잉 뒤집기 차단 거울(맥 `WorkTimerStore` 의 `reversi.hiddenPeerIDs = blockHiddenPeerIDs` 와 같은 길). 코어가 로비 사람·받은 신청·탭 배지를 이 집합으로
     * 거른다. 코어 id 는 소문자 uuid 라 소문자로 맞춘다. 같은 값이면 쓰지 않는다(관찰을 깨우지 않게). 폰 조립은 메시지 탭의 차단 변화 때도 같은 값을 넣는다.
     */
    fun syncReversiHiddenPeers() {
        val reversi = context.reversi ?: return
        val hidden = context.hiddenBlockedPeerIDs.map { it.lowercase() }.toSet()
        if (reversi.hiddenPeerIDs != hidden) reversi.hiddenPeerIDs = hidden
    }

    /** 오목 카드의 한 줄 재료: 진행 중인 판이 있는가(서버가 말한 진행 판 id 또는 들고 있는 끝나지 않은 판). */
    val hasActiveGomokuMatch: Boolean get() = context.gomoku.hasUnfinishedMatch || context.gomoku.activeMatchID != null

    /** 체스 카드의 한 줄 재료(위와 같은 뜻 — **로봇 판도 포함**이다). */
    val hasActiveChessMatch: Boolean get() = context.chess.hasUnfinishedMatch || context.chess.activeMatchID != null

    /**
     * 테트리스 카드의 한 줄 재료. 지금은 [hasLiveTetrisMatch] 와 **같은 값**이다 — 테트리스에는 AI·로봇 판이 없다.
     * 그래도 **이름을 따로 둔다**: 저쪽은 *다른 게임 입구를 막는 판정*이고 이쪽은 *카드 한 줄의 재료*다.
     */
    val hasActiveTetrisMatch: Boolean
        get() {
            val tetris = context.tetris
            val match = tetris.match
            if (match != null && !match.isFinished) return true
            return tetris.activeMatchID != null
        }

    /**
     * 아잉 뒤집기 카드의 한 줄 재료(위 체스와 같은 뜻 — **AI 연습 판도 포함**이다. 카드가 '대국 중'을 앞세울지는 [com.yehsung.aingcheck.core.stores.reversi.GamesReversiCard]
     * 가 AI 판과 받은 신청을 함께 보아 정한다 — 체스 카드와 같은 관례).
     */
    val hasActiveReversiMatch: Boolean
        get() {
            val reversi = context.reversi ?: return false
            val match = reversi.match
            if (match != null && !match.isFinished) return true
            return reversi.activeMatchID != null
        }

    // MARK: 오목 화면 수명

    /** 오목 화면이 나타났다. */
    fun gomokuScreenDidAppear() {
        val gomoku = context.gomoku
        // 먼저 적는다 — openWindow 가 presentWindow 를 부르고, 그 문이 "이미 보인다"를 봐야 화면을 또 열지 않는다.
        isGomokuScreenVisible = true
        val focus = pendingGomokuFocusID
        pendingGomokuFocusID = null
        gomoku.openWindow(focus)
        if (isAppActive) gomoku.windowDidShow()
        syncAIThinker()
    }

    /**
     * 오목 화면이 사라졌다(뒤로 · 다른 탭으로 · 로그아웃). 폴링만 멈춘다. **관전은 여기서 끝낸다**(폰에서만 — 탭을 옮기는 것이 곧 "그만 볼게").
     * `leaveWatch()` 가 **아니다**: 그쪽은 네트워크 호출이라 화면을 떠나는 길에서 조회가 나간다. `stopWatching()` 은 요청 0건이다.
     *
     * INV-GamesStore-29eba479 이식: **`windowDidClose()` 가 마지막이다**(0.3.50 수리의 폰 몫). 폰에서 화면을 떠나는 것은 맥의 '최소화'가
     *   아니라 **'창을 정말 닫았다'**다. `windowDidHide()` 만 부르면 끝난 판이 그대로 남아 오목을 다시 누를 때 결과 화면이 다시 섰다.
     * INV-GamesStore-e47eea33 이식: **진행 중인 내 판은 그대로 남는다** — 가드는 코어 안에 있다(오목 `windowDidClose` 의 끝난 판 가드 — W2-d).
     * INV-GamesStore-bfefc172 이식: **순서는 맥과 같다**: 숨김 → 닫힘. 뒤집으면 접힌 뒤의 `windowDidHide` 가 빈 판을 본다.
     * INV-GamesStore-5d5e8c41 이식: **요청은 늘지 않는다.** `windowDidClose()` 는 조회를 쏘지 않고 겹치는 일은 멱등이다.
     */
    fun gomokuScreenDidDisappear() {
        if (!isGomokuScreenVisible) return
        isGomokuScreenVisible = false
        // 관전을 먼저 내린다(요청 없음). 뒤의 `windowDidHide` 는 **끝난** 관전만 내리므로 진행 중인 남의 판이 그대로 남았다.
        context.gomoku.stopWatching()
        context.gomoku.windowDidHide()
        // 폰에서 '떠남'은 맥의 '닫기'다 — 끝난 판을 접는 자리는 이 문뿐이다(진행 중인 판은 코어가 가른다).
        context.gomoku.windowDidClose()
        syncAIThinker()
    }

    // MARK: 체스 화면 수명 (오목에서 수리한 모양 그대로)

    /**
     * 체스 화면이 나타났다: 로비·진행 판을 읽고(`openWindow`) 앱이 active 면 창을 세운다(`windowDidShow`).
     *
     * INV-GamesStore-172c5161 이식: **`windowDidShow()` 가 이 화면의 두 번째 주 스위치다.** 코어 `isWindowVisible` 도 기본이 false 이고
     *   그 깃발을 켜는 문은 이것뿐이다. 꺼져 있으면 폴링 · 순위·관전 · 말 이동 애니메이션이 함께 죽는다(화면 시험 W4-a 가 결과로 잰다).
     * INV-GamesStore-fc987c18 이식: `focusMatchID` 는 **데모 라우트의 꼬리**(`games/chess/match/<id>`)다. 사람이 쓰는 길에서는 null 이고
     *   Android 는 데모 경로를 옮기지 않으므로 늘 null 을 넘긴다 — 코어가 로비 `me.active_match_id` 로 내 판을 스스로 연다.
     */
    fun chessScreenDidAppear() {
        val chess = context.chess
        isChessScreenVisible = true
        chess.openWindow(null)
        if (isAppActive) chess.windowDidShow()
    }

    /**
     * 체스 화면이 사라졌다(뒤로 · 다른 탭으로 · 로그아웃). **`stopWatching()` 이 먼저, `windowDidHide()` 가 나중이다.**
     *
     * INV-GamesStore-4f3ed0e5 이식: **`windowDidClose()` 가 마지막이다**(0.3.50 수리의 폰 몫 — 오목과 같은 결함이었다).
     * INV-GamesStore-1c5d81ac 이식: **진행 중인 판을 가르는 가드는 코어 안에 있다**(체스 `foldFinishedMatch` 첫 줄 — W2-d).
     * INV-GamesStore-4dbbd7d3 이식: **순서는 맥과 같다**: 숨김 → 닫힘.
     * INV-GamesStore-871f928e 이식: **겹치는 일은 해롭지 않다** — 닫힘이 다시 부르는 정리들은 null 가드가 달린 멱등 함수다(W2-d 코어).
     */
    fun chessScreenDidDisappear() {
        if (!isChessScreenVisible) return
        isChessScreenVisible = false
        context.chess.stopWatching()
        context.chess.windowDidHide()
        context.chess.windowDidClose()
    }

    // MARK: 테트리스 화면 수명 (오목·체스에서 수리한 모양 그대로)

    /**
     * 1:1 테트리스 화면이 나타났다: 로비·진행 판을 읽고(`openWindow`) 앱이 active 면 창을 세운다(`windowDidShow`).
     * [isTetrisScreenVisible] 을 **먼저** 적는다 — `openWindow` 가 `presentWindow` 를 부르고, 그 문이 "이미 보인다"를 봐야 화면을 또 열지 않는다.
     *
     * INV-GamesStore-d157a045 이식: **`windowDidShow()` 가 이 화면의 주 스위치다.** 코어 `isWindowVisible` 도 기본이 false 이고 그 깃발을 켜는
     *   문은 이것뿐이다. 꺼져 있으면 폴링 · 순위·로비 재조회 · **준비 보고의 문**(코어 머리말 ⑨)이 함께 죽는다 — 준비를 못 내면 서버는 30초 뒤
     *   `no_show` 무승부로 판돈을 돌려주는데 사용자 눈에는 수락했는데 아무 일도 안 일어난 화면이 30초 서 있다. 시험
     *   `GamesTetrisWiringTest.theScreenHookOpensTheReadyReport` 가 그 결과(보고가 나가는지)를 훅을 안 부른 기준선과 나란히 잰다.
     * INV-GamesStore-bc740758 이식: `focusMatchID` 는 **데모 라우트의 꼬리**(`games/tetris/match/<장면>`)다. 사람이 쓰는 길에서는 null 이고
     *   Android 는 데모 경로를 옮기지 않으므로 늘 null 을 넘긴다(코어가 로비 `me.active_match_id` 로 내 판을 스스로 연다).
     */
    fun tetrisScreenDidAppear() {
        val tetris = context.tetris
        isTetrisScreenVisible = true
        tetris.openWindow(null)
        if (isAppActive) tetris.windowDidShow()
    }

    /**
     * 테트리스 화면이 사라졌다(뒤로 · 다른 탭으로 · 로그아웃).
     *
     * **기권이 아니다.** 테트리스에는 `tetris_leave` 가 없고 진행 중인 판은 서버에서 계속 흐른다. 떠나는 길에서 **요청은 한 건도 나가지 않는다.**
     * INV-GamesStore-24e0c495 이식: **`windowDidClose()` 가 마지막이다** — `windowDidHide()` 만 부르면 끝난 판이 그대로 남아 테트리스를 다시
     *   누를 때 로비가 아니라 그 결과 카드가 다시 선다. `windowDidClose()` 가 그 판을 접는다.
     * INV-GamesStore-da445813 이식: **진행 중인 내 판은 그대로 남는다** — 가드는 코어 안에 있다(`TetrisDuelStore.foldFinishedMatch` 첫 줄이
     *   끝난 판만 접는다). 그래서 폰 배선에서 따로 가를 것이 없다.
     * INV-GamesStore-c6933096 이식: **순서는 맥과 같다**: 숨김 → 닫힘. 뒤집으면 접힌 뒤의 `windowDidHide` 가 빈 판을 본다.
     * INV-GamesStore-89cb03c0 이식: **겹치는 일은 해롭지 않다.** 둘 다 `releaseAllKeys()` 를 부르는데 멱등이고 조회도 쏘지 않는다.
     * INV-GamesStore-2a454719 이식: 관전은 이 문이 **끊지 않는다**(Swift 1.0.11 은 관전이 없어 비어 있던 자리) — 0.3.65 부터 테트리스 관전은
     *   코어 `windowDidClose()` 가 내린다(`stopWatching` — 요청 0건). 그래서 이 함수에 `stopWatching()` 을 따로 적지 않는다.
     */
    fun tetrisScreenDidDisappear() {
        if (!isTetrisScreenVisible) return
        isTetrisScreenVisible = false
        context.tetris.windowDidHide()
        // 폰에서 '떠남'은 맥의 '닫기'다 — 끝난 판을 접는 자리는 이 문뿐이다(진행 중인 판은 코어가 가른다).
        context.tetris.windowDidClose()
    }

    // MARK: 아잉 뒤집기 화면 수명 (체스에서 수리한 모양 그대로 — 관전이 있다 · 화면 갈래가 부른다)

    /**
     * 아잉 뒤집기 화면이 나타났다: 차단 거울을 맞추고 로비·진행 판을 읽고(`openWindow`) 앱이 active 면 창을 세운다(`windowDidShow`).
     * [isReversiScreenVisible] 을 **먼저** 적는다 — `openWindow` 가 `presentWindow` 를 부르고, 그 문이 "이미 보인다"를 봐야 화면을 또 열지 않는다.
     * ★★ **`windowDidShow()` 가 이 화면의 둘째 주 스위치다.** 코어 `isWindowVisible` 도 기본이 false 이고 그 깃발을 켜는 문은 이것뿐이다. 꺼져 있으면 넷이
     *   함께 죽는다: 폴링(상대 차례·보낸 신청 5초·로비 30초) · 순위·관전 · **뒤집기 그림** · **AI 연습의 사람 시계**.
     */
    fun reversiScreenDidAppear() {
        val reversi = context.reversi ?: return
        isReversiScreenVisible = true
        syncReversiHiddenPeers()
        reversi.openWindow(null)
        if (isAppActive) reversi.windowDidShow()
    }

    /**
     * 아잉 뒤집기 화면이 사라졌다(뒤로 · 다른 탭으로 · 로그아웃). **`stopWatching()` 이 먼저, `windowDidHide()` 가 나중이다**(체스와 같은 순서) —
     * 폰에서 그 통지는 "화면을 떠났다"다. `leaveWatch()` 가 **아니다**(로비·순위를 다시 읽는 네트워크 호출이다).
     * ★★ **`windowDidClose()` 가 마지막이다** — 빼면 끝난 내 판(결과 카드)이 남아 다시 누를 때 로비가 아니라 결과가 다시 선다. **진행 중인 판은 남는다**
     *   (코어 `foldFinishedMatch` 가 `isFinished` 를 먼저 본다 — 1:1 은 서버 시계로 계속 흐르고, AI 연습은 숨김이 사람 시계를 멈춘다). 요청은 한 건도 안 나간다.
     * ★ **규칙 시트도 접는다**(판 7 검토 S-F3 · U-F1 의 Android 몫). 시트의 주인은 코어 `isRulesVisible` 이라 화면이 빠져도 남는다 — 다른 탭에 있는 사이 신청이
     *   수락돼 판 시작 문이 화면을 다시 열면, 새 화면은 그 판 id 를 처음 보는 것이라 '새 판'을 못 알아보고 시트가 판과 30초 시계를 덮는다. 다른 시트(돌 색 · 판돈 ·
     *   확인)는 화면 상태라 화면과 함께 사라진다 — 같은 수명으로 맞춘다. 아이폰은 탭을 옮겨도 화면이 살아 있어 `onChange` 가 잡는다.
     */
    fun reversiScreenDidDisappear() {
        if (!isReversiScreenVisible) return
        isReversiScreenVisible = false
        val reversi = context.reversi ?: return
        if (reversi.isRulesVisible) reversi.isRulesVisible = false
        reversi.reversiStopWatching()
        reversi.windowDidHide()
        reversi.windowDidClose()
    }

    // MARK: 1:1 길건너 화면 수명(판 8 — iOS 1.0.18)

    /**
     * 1:1 길건너 화면이 나타났다. [isCrossyDuelScreenVisible] 을 **먼저** 적는다 — `openWindow` 가 `presentWindow` 를 부르고, 그 문이 "이미 보인다"를
     * 봐야 화면을 또 열지 않는다. `windowDidShow()` 가 폴링 · **준비 보고의 문**이다(앱이 active 일 때만 — 안 보이는 판의 준비가 나가지 않게).
     */
    fun crossyDuelScreenDidAppear() {
        val duel = context.crossyDuel ?: return
        isCrossyDuelScreenVisible = true
        syncCrossyDuelHiddenPeers()
        duel.openWindow(null)
        if (isAppActive) duel.windowDidShow()
    }

    /** 1:1 길건너 화면이 사라졌다. **닫기는 기권이 아니다** — 진행 중 판은 그대로 흐르고, 끝난 판(결과 카드)은 접는다. */
    fun crossyDuelScreenDidDisappear() {
        if (!isCrossyDuelScreenVisible) return
        isCrossyDuelScreenVisible = false
        val duel = context.crossyDuel ?: return
        duel.windowDidHide()
        duel.windowDidClose()
    }

    // MARK: 아잉 큐브 화면 수명 (테트리스에서 수리한 모양 그대로 — GamesRummyScreen 이 부른다)

    /**
     * 아잉 큐브 화면이 나타났다: 로비·방·판을 읽고(`openWindow`) 앱이 active 면 창을 세운다(`setWindowVisible` — 폴링의 주 스위치).
     * [isRummyScreenVisible] 을 **먼저** 적는다 — `openWindow` 가 `presentWindow` 를 부르고, 그 문이 "이미 보인다"를 봐야 화면을 또 열지 않는다.
     * 이 문은 [presentRummyScreen] 이다.
     */
    fun rummyScreenDidAppear() {
        val rummy = context.rummy ?: return
        isRummyScreenVisible = true
        rummyPersonLeftScreen = false
        rummy.roomHeartbeatHeld = false
        if (rummyLeftByTabNotice != null) rummyTabLeftNoticeSeen = true
        rummy.openWindow(null)
        if (isAppActive) rummy.setWindowVisible(true)
    }

    /**
     * 아잉 큐브 화면이 사라졌다. **이것 자체는 이탈이 아니다** — 이 신호로는 요청이 한 건도 나가지 않는다(목적지가 다시 세워질 때도 온다). 방을 떠나는 판단은 사람의 행동을 보는 문([rummyDepartureAllowed])과
     * 뒤로 가기(코어 `requestBack`·`confirmBack`)가 먼저 했다. 끝난 판만 접는다(요청 0건 — 폰에서 '떠남'은 맥의 '닫기'다).
     */
    fun rummyScreenDidDisappear() {
        if (!isRummyScreenVisible) return
        isRummyScreenVisible = false
        rummyPersonLeftScreen = false
        rummyFinalBoardMatchID = null
        val rummy = context.rummy ?: return
        rummy.setWindowVisible(false)
        rummy.roomHeartbeatHeld = true
        rummy.rummyWindowDidClose()
        if (rummy.rulesShown) rummy.rulesShown = false
        if (rummyTabLeftNoticeSeen) rummyLeftByTabNotice = null
        rummyTabLeftNoticeSeen = false
        // 묻던 화면이 사라졌다 — 돌아왔을 때 낡은 확인이 뜨지 않게.
        cancelRummyDeparture()
    }

    // MARK: 아잉 큐브 방을 떠나는 문

    /**
     * 사용자 답(폰 아잉 큐브: 방에서 탭으로 나가도 자리를 남길까요?): **"맥처럼 방을 나가기"** — 모르는 사이 판돈이 걷히지 않게. 원본: Sources/CheckMobileKit/Games/GamesStore.swift @ ios-1017-cube dba0c647.
     *
     * | 지금(RummyCloseDecision)      | 이 문                                   |
     * |------------------------------|----------------------------------------|
     * | leaveRoom(손님)               | 곧바로 간다 + 뒤에서 나간다                |
     * | confirmCloseRoom(방장)        | 멈추고 묻는다 — 수락하면 나간 뒤 간다        |
     * | confirmForfeit(판 중)         | 그냥 간다 — 90초 규칙 그대로, 기권 아님     |
     * | close(로비·결과·놀던 기기)      | 그냥 간다 — 아무것도 안 보낸다             |
     *
     * 앱을 내리는 것과 로그아웃은 이 문을 지나지 않는다. 화면이 안 보이면 떠나는 것이 아니다.
     */
    private fun rummyDepartureAllowed(resume: () -> Unit): Boolean {
        if (!isRummyScreenVisible) return true
        if (isRummyDepartureRunning) {
            rummyPersonLeftScreen = true
            return true
        }
        val rummy = context.rummy ?: return true
        return when (rummy.closeDecision) {
            RummyCloseDecision.close, RummyCloseDecision.confirmForfeit -> true
            RummyCloseDecision.leaveRoom -> {
                rummyPersonLeftScreen = true
                startRummyDeparture(rummy, saysTabLeft = true)
                true
            }
            RummyCloseDecision.confirmCloseRoom -> {
                rummyDepartureResume = resume
                rummyDeparturePrompt = RummyCloseDecision.confirmCloseRoom
                if (rummy.rulesShown) rummy.rulesShown = false
                false
            }
        }
    }

    /**
     * 화면의 [나가기](손님) · [방 닫고 나가기](방장 — 이미 물었다). 탭 이탈과 같은 길이라 못 닿으면 방에 남아 사실을 말한다 — 접어 버리면 로비가 보이는데 서버엔 자리가 있다.
     * [onLeft] = 나간 뒤 할 일(화면이 아직 설 때만). 손님 뒤로는 부르는 쪽이 곧바로 화면을 내리고([personIsLeaving] 참), 그러면 여기서 되보내며 게임 탭 카드가 사실을 말한다.
     */
    fun leaveRummyRoomFromScreen(personIsLeaving: Boolean = false, onLeft: (() -> Unit)? = null) {
        if (isRummyDepartureRunning) return
        val rummy = context.rummy ?: return
        when (rummy.closeDecision) {
            RummyCloseDecision.leaveRoom, RummyCloseDecision.confirmCloseRoom -> {
                if (personIsLeaving) rummyPersonLeftScreen = true
                startRummyDeparture(rummy, saysTabLeft = false, onLeft = onLeft)
            }
            RummyCloseDecision.close, RummyCloseDecision.confirmForfeit -> Unit
        }
    }

    private fun startRummyDeparture(rummy: RummyStore, saysTabLeft: Boolean, onLeft: (() -> Unit)? = null) {
        rummyDepartureJob?.cancel()
        isRummyDepartureRunning = true
        rummyDepartureJob = context.scope.launch { runRummyDeparture(rummy, saysTabLeft, onLeft) }
    }

    /**
     * 보낸다. 화면 밖이면 서버가 확인할 때까지 몇 번 더 보낸다 — 방을 보고 있으면 그 사람에게 맡긴다(안내 줄이 서 있다). '보고 있다'는 [isPersonOnRummyScreen] 으로 잰다(나가는 전환 동안의 화면은 안 친다).
     * [onLeft](수락한 방장이 가려던 곳)는 **화면이 아직 설 때만** 간다: 나가는 중에 사람이 다른 탭으로 갔으면 그 탭이 답이다. 로비 조회를 기다리지 않고 간다 — 그 조회가 늦으면 사람이 빈 로비에 묶인다.
     */
    private suspend fun runRummyDeparture(rummy: RummyStore, saysTabLeft: Boolean, onLeft: (() -> Unit)?) {
        val generation = rummy.resetGeneration
        var outcome = sendRummyDeparture(rummy, saysTabLeft)
        if (outcome == RummyRoomDeparture.left && generation == rummy.resetGeneration && isPersonOnRummyScreen) onLeft?.invoke()
        for (seconds in rummyLeaveRetrySeconds) {
            if (outcome != RummyRoomDeparture.notConfirmed) break
            if (isPersonOnRummyScreen) return
            val roomID = rummy.match?.id
            delay(delayMillis(seconds))
            if (generation != rummy.resetGeneration || isPersonOnRummyScreen || rummy.phase != RummyPhase.room || rummy.match?.id != roomID) return
            isRummyDepartureRunning = true
            outcome = sendRummyDeparture(rummy, saysTabLeft)
        }
        if (outcome == RummyRoomDeparture.left && generation == rummy.resetGeneration) rummy.settleAfterLeaving()
    }

    /** 한 번 보내고 결과를 사람에게 남긴다(안내 줄 · 카드). 부르는 쪽이 [isRummyDepartureRunning] 을 세운다. */
    private suspend fun sendRummyDeparture(rummy: RummyStore, saysTabLeft: Boolean): RummyRoomDeparture {
        val generation = rummy.resetGeneration
        val outcome = rummy.departRoom(RummyExitReason.windowClosed)
        // 그새 로그아웃했으면 다음 사람에게 남길 말이 없다.
        if (generation != rummy.resetGeneration) return outcome
        isRummyDepartureRunning = false
        when (outcome) {
            RummyRoomDeparture.left -> {
                rummyUnconfirmedLeaveRoomID = null
                rummyLeftByTabNotice = if (saysTabLeft) RummyPhoneText.tabLeftNotice else null
                // 보고 있는 사람은 이미 봤다 — 다음에 떠날 때 지운다.
                rummyTabLeftNoticeSeen = saysTabLeft && isPersonOnRummyScreen
            }
            RummyRoomDeparture.notConfirmed -> rummyUnconfirmedLeaveRoomID = rummy.match?.id
            RummyRoomDeparture.startedMatch -> rummyUnconfirmedLeaveRoomID = null
        }
        return outcome
    }

    /** 로비를 떠나 새 방 · 판에 들었다 — 지난 방 이야기를 다음 로비까지 끌고 가지 않는다. */
    fun forgetRummyLeftByTabNotice() {
        rummyLeftByTabNotice = null
        rummyTabLeftNoticeSeen = false
    }

    /**
     * 방장의 [방 닫고 나가기]. **지금 판단으로 간다**(묻는 사이 판이 시작됐으면 나가지도 옮기지도 않는다 · 방이 없어졌으면 보낼 것 없이 간다).
     * 서버가 확인하지 않으면 옮기지 않는다 — 방이 안 닫혔는데 다른 탭으로 가면 다른 사람들이 빈 방에서 기다린다. 방 화면의 안내 줄이 말하고, 다시 누를 수 있다.
     */
    fun confirmRummyDeparture() {
        if (rummyDeparturePrompt == null) return
        val rummy = context.rummy ?: return
        val resume = rummyDepartureResume
        rummyDeparturePrompt = null
        rummyDepartureResume = null
        if (isRummyDepartureRunning) return
        when (rummy.closeDecision) {
            RummyCloseDecision.close -> resume?.invoke()
            RummyCloseDecision.confirmForfeit -> Unit
            RummyCloseDecision.leaveRoom, RummyCloseDecision.confirmCloseRoom -> startRummyDeparture(rummy, saysTabLeft = true, onLeft = resume)
        }
    }

    /** 방장의 [계속하기] — 아무것도 안 보내고 방에 남는다. 판이 시작돼 거둘 때도 부른다. */
    fun cancelRummyDeparture() {
        rummyDeparturePrompt = null
        rummyDepartureResume = null
    }

    /** 나가기를 서버가 확인하지 않은 그 방에 아직 앉아 있다. */
    val isRummyLeaveUnconfirmed: Boolean
        get() {
            val id = rummyUnconfirmedLeaveRoomID ?: return false
            val rummy = context.rummy ?: return false
            return rummy.phase == RummyPhase.room && rummy.match?.id == id
        }

    /** AI 선택기의 허락 = 오목 화면이 보이고 앱이 active. 거두면 도는 탐색이 곧바로 취소된다. */
    private fun syncAIThinker() {
        context.gomoku.setAIThinkerAllowed(isGomokuScreenVisible && isAppActive)
    }

    /**
     * 대국 중이라 화면이 꺼지면 안 된다(SPEC-ios §3.5). 앱이 active 이고 끝나지 않은 판이 있을 때. **어느 화면에 있든 같다.**
     * AI 판만 예외: 오목 화면이 보일 때만 켠다.
     */
    val wantsIdleTimerDisabled: Boolean
        get() {
            if (!isAppActive || !context.sessionStore.isSignedIn) return false
            // 미니게임: 끝나지 않은 판이 **돌고 있으면** 켠다(자동잠금은 판을 얼리고, 조각을 세워 두고 생각하는 무입력 구간이 있는 게임은 그 자리에서 판이 끊긴다).
            // ★ **정지 중에는 끈다**(폰 일시정지 — iOS de5c153b). 정지 카드를 띄운 채 폰을 내려놓으면 화면이 켜진 채로 남는다. 그 판은 이미 얼어 있어 자동잠금으로 더 잃을 것이 없다(상한은 벽시계라 잠겨 있어도 센다).
            // INV-GamesStore-78b92b69 이식: **타이밍 바만 뺀다.** 그 판은 **스스로 끝나지 않는다** — 탭을 받을 때까지 진행 중에 머문다.
            //   여기에 타이밍 바를 넣으면 화면이 **영원히** 켜져 있다(자동잠금이 유일한 상한이었다). 새 게임을 더할 때 이 성질을 확인할 것.
            val controller = miniGames.controller
            if (controller != null && controller.isPlaying && !controller.isFrozen && controller.kind != MiniGameKind.timingBar) return true
            // 체스: 1:1 판은 어느 화면에 있든 켜고, 로봇 판은 체스 화면이 보일 때만 켠다.
            if (context.chess.hasUnfinishedMatch) {
                if (context.chess.isAIMatch) {
                    if (isChessScreenVisible) return true
                } else {
                    return true
                }
            }
            // 테트리스: **어느 화면에 있든 켠다**(1:1 뿐이라 로봇 예외가 없다). 자동잠금이 닿으면 판 루프가 재워지고 서버는 15초 침묵에
            // **내 패**로 닫는다(D5 — 판돈을 잃는다).
            // INV-GamesStore-54545bcf 이식: [hasLiveTetrisMatch] 가 아니라 들고 있는 판을 본다: 서버가 말한 id 만 알고 판을 아직 못 읽은
            //   상태에서 화면을 8분까지 켜 두면 테트리스를 보고 있지도 않은 사람의 배터리를 태운다.
            // ★ 같은 계정의 **다른 기기**가 두는 판(코어 `playingElsewhere` · 0.3.69 — Swift 75c31cd2)은 켜지 않는다 — 이 폰에는 판 루프도
            //   보고도 없어 자동잠금이 닿아도 지는 사람이 없다. 켜 두면 남의 기기 판이 끝날 때까지(최대 8분) 배터리만 탄다.
            val tetrisMatch = context.tetris.match
            if (tetrisMatch != null && !tetrisMatch.isFinished && !context.tetris.playingElsewhere) return true
            // 아잉 큐브: 이 기기가 쥔 방·판이면 **어느 화면에 있든 켠다** — 남의 차례를 기다리는 동안(한 차례 60초 × 3명) 자동잠금이 닿으면 앱이 뒤로 가고 하트비트가 멈춰
            // 90초 뒤 끊김 기권으로 **판돈을 잃는다**. 놀던 기기 · 기권 뒤 구경은 쥐지 않는다(코어 `isHoldingMatch`).
            if (context.rummy?.isHoldingMatch == true) return true
            // 1:1 길건너(판 8): 이 기기가 두는 판이 카운트다운 · 달리기 중이면 **어느 화면에 있든** 켠다(코어 `holdsActivity` — 다른 기기 판은 아니다).
            //   자동잠금이 닿으면 판 루프가 재워지고 보고가 멎어 서버가 끊김으로 닫는다.
            if (context.crossyDuel?.holdsActivity == true) return true
            // 아잉 뒤집기: 1:1 판은 **어느 화면에 있든** 켠다(한 수 30초 — 자동잠금이 닿으면 소켓이 내려가 상대 수를 모르고, 서버가 대신 둔 수가 연속 3번이면
            // 판돈째 진다). AI 연습은 화면이 보일 때만(떠나면 코어가 사람 시계를 멈춘다 — 체스 로봇과 같다). '이 기기가 연 판' 장부가 없어 같은 계정 다른 기기의
            // 판에서도 켠다 — Android 오목과 같은 수준(ReversiStore 머리말 · 아이폰 1.0.17 은 `ownsMatch` 로 거른다).
            context.reversi?.match?.let { match ->
                if (!match.isFinished) {
                    if (match.isAI) {
                        if (isReversiScreenVisible) return true
                    } else {
                        return true
                    }
                }
            }
            if (!context.gomoku.hasMatch) return false
            if (context.gomoku.isAIMatch) return context.gomoku.hasUnfinishedMatch && isGomokuScreenVisible
            return context.gomoku.hasUnfinishedMatch
        }

    // MARK: 화면 꺼짐 방지(주인은 이 스토어 하나)

    /**
     * 화면 꺼짐 방지 싱크를 단다. **뒤의 호출이 앞을 갈아 끼운다** — 스토어는 앱 수명이고 싱크가 쥔 창은 Activity 수명이라, 첫 싱크만 쥐면 Activity 를 다시 만든 뒤 플래그가 죽은 창에 걸린다.
     * 새 창에는 플래그가 없으니 마지막 값을 잊고 지금 값을 곧바로 넘긴다. 떠나는 Activity 는 [uninstallIdleTimerSink] 로 푼다. 이후 [wantsIdleTimerDisabled] 가 바뀔 때마다 이 스토어가 넘긴다.
     * 재료(앱 active · 판 · 미니게임 구동기)는 Compose 스냅숏 상태다 — `snapshotFlow` 가 그 값이 바뀔 때마다 다시 읽는다(Swift
     * `withObservationTracking`). 스냅숏 쓰기 알림은 앱에서 compose-ui 의 전역 스냅숏 관리자가 보낸다. 로그인 상태는 세션 스토어의
     * StateFlow 라 스냅숏이 못 보므로 자리 API(active · background · 로그아웃 [reset])가 끝에서 [syncIdleTimer] 를 직접 부른다.
     * 지금 값은 **곧바로 한 번** 넘긴다(구독이 첫 값을 받기 전에도 싱크가 상태를 안다).
     */
    fun installIdleTimerSink(sink: (Boolean) -> Unit) {
        idleTimerSink = sink
        appliedIdleTimerDisabled = null
        syncIdleTimer()
        if (idleTimerJob != null) return
        idleTimerJob = context.scope.launch {
            snapshotFlow { wantsIdleTimerDisabled }.distinctUntilChanged().collect { syncIdleTimer() }
        }
    }

    /** 이 싱크를 푼다(Activity onDestroy — 죽은 창을 쥐지 않게). 이미 다른 싱크로 갈렸으면 아무것도 안 한다: 새 Activity 가 먼저 섰을 수 있다. */
    fun uninstallIdleTimerSink(sink: (Boolean) -> Unit) {
        if (idleTimerSink !== sink) return
        idleTimerSink = null
        appliedIdleTimerDisabled = null
    }

    /** 지금 값을 싱크에 넘긴다(같은 값은 다시 넘기지 않는다). */
    fun syncIdleTimer() {
        val sink = idleTimerSink ?: return
        val wants = wantsIdleTimerDisabled
        if (appliedIdleTimerDisabled == wants) return
        appliedIdleTimerDisabled = wants
        sink(wants)
    }

    // MARK: 딥링크

    /**
     * 게임 탭이 꺼낸 딥링크를 경로 동작으로 바꾼다. 게임 탭 밖 라우트면 null.
     *
     * 오목 라우트에서 **오목 화면이 이미 보이면** 대상 id 를 코어에 바로 넘긴다(`openWindow(focusMatchID)`). 경로는 그래도 다시 쌓는다.
     *
     * INV-GamesStore-6126529f 이식: **1:1 테트리스 가지는 여기 없다 — 그것이 결정이다**(1.0.11 레인 A). ① `games/tetris` 는 이미 **솔로**
     *   테트리스의 링크다(대결을 끼우면 이미 나간 솔로 딥링크의 뜻이 바뀐다) ② 대결 라우트는 `AingRoute` 에 **새 글자**가 필요하다(앱 셸 몫)
     *   ③ 지금 그 라우트를 쓸 소비자가 없다(푸시 `tetris_invite` 는 서버 범위 밖 — D8). 화면을 여는 길은 게임 탭 카드와 코어가 부르는
     *   `presentTetrisScreen()` 둘이다. 푸시·위젯이 대결을 열어야 하는 날 `games/tetris` 가 **아닌** 글자로 가지를 더하고 여기 [tetrisEntryBlock]
     *   가드를 지나는 가지를 더한다.
     *
     * Android(G §2-3 W2-e ④): 이 빌드에 보이지 않는 미니게임([MiniGameExposure.visible] 밖) 링크는 화면을 쌓지 않고 첫 화면에 세운다.
     */
    fun routeStep(request: GamesRouteRequest): GamesRouteStep? = when (request) {
        GamesRouteRequest.Games -> GamesRouteStep.PopToRoot
        is GamesRouteRequest.MiniGame ->
            if (MiniGameExposure.isVisible(request.kind)) GamesRouteStep.Push(GamesDestination.MiniGame(request.kind)) else GamesRouteStep.PopToRoot
        GamesRouteRequest.GomokuLobby -> openGomokuRoute(null)
        is GamesRouteRequest.GomokuMatch -> openGomokuRoute(request.matchID)
        is GamesRouteRequest.GomokuInvite -> openGomokuRoute(request.inviteID)
        GamesRouteRequest.Other -> null
    }

    private fun openGomokuRoute(focusID: String?): GamesRouteStep {
        if (gomokuEntryBlock != null) return blockedGomokuRoute()
        openGomoku(focusID)
        return GamesRouteStep.Push(GamesDestination.Gomoku)
    }

    /**
     * 체스·**테트리스** 판이 흐르는 동안 들어온 오목 링크(푸시·위젯)를 **열지 않는다** — 게임 탭 첫 화면에 세운다.
     * 카드만 막으면 이 길이 남는다: 오목 로비의 [수락]은 아무 게이트도 없고, 서버의 오목 쪽 게이트는 체스·테트리스를 모른다.
     *
     * INV-GamesStore-72b0b7e9 이식: 부르는 자리의 가드는 [gomokuEntryBlock] 하나다 — 그 값이 **세 방향 가운데 둘**(체스·테트리스)을 이미 함께
     *   보므로 이 길에 조건을 더 적지 않는다. 두 곳에 적으면 한 곳만 넓히는 날 조용히 갈린다.
     */
    private fun blockedGomokuRoute(): GamesRouteStep {
        pendingGomokuFocusID = null
        return GamesRouteStep.PopToRoot
    }

    private fun openGomoku(focusID: String?) {
        if (!isGomokuScreenVisible) {
            // 화면이 곧 나타난다(push) — 나타날 때 꺼내 쓴다.
            pendingGomokuFocusID = focusID
            return
        }
        pendingGomokuFocusID = null
        context.gomoku.openWindow(focusID)
    }

    private fun presentGomokuScreen() {
        if (!isAppActive || !context.sessionStore.isSignedIn || isGomokuScreenVisible) return
        context.router.present(GamesDestination.Gomoku)
    }

    /** 체스 판이 막 열렸다 — 체스 화면을 연다(게임 탭을 고르고 · 쌓인 화면을 비우고 · 체스를 쌓는다). */
    private fun presentChessScreen() {
        if (!isAppActive || !context.sessionStore.isSignedIn || isChessScreenVisible) return
        context.router.present(GamesDestination.Chess)
    }

    /**
     * 테트리스 판이 막 열렸다(내 신청이 수락됨 · 내가 수락함 · 앱을 다시 켜니 진행 중인 판) — 테트리스 화면을 연다.
     *
     * INV-GamesStore-c97985ac 이식: 이 문이 **없으면 수락이 화면을 못 연다.** 수락 뒤 30초 안에 준비 보고를 못 내면 `no_show` 무승부이고(D4),
     *   준비는 **창이 보일 때만** 나간다(코어 머리말 ⑨). 즉 화면이 안 열리면 수락한 판이 통째로 흘러간다.
     * INV-GamesStore-4b5947a1 이식: `!isTetrisScreenVisible` 가드가 **화면을 두 번 쌓는 것**을 막는다 — [tetrisScreenDidAppear] 가 깃발을
     *   먼저 적는 까닭이 이것이다(그 안의 `openWindow` 가 이 문을 부른다).
     */
    private fun presentTetrisScreen() {
        if (!isAppActive || !context.sessionStore.isSignedIn || isTetrisScreenVisible) return
        context.router.present(GamesDestination.TetrisDuel)
    }

    /**
     * 아잉 큐브 판이 막 열렸다 — 큐브 화면을 연다. `!isRummyScreenVisible` 가드가 화면을 두 번 쌓는 것을 막는다([rummyScreenDidAppear] 가 깃발을 먼저 적는 까닭).
     * **이 기기가 손댄 판에서만 연다**(iOS GamesStore.swift `presentRummyScreen` @ ios-1017-cube): 다른 기기로 하는 판을 읽기만 한 기기가 보던 탭에서 끌려 나와 가로로 돌면 안 된다.
     * 여기서 보낸 만들기 · 참가 · 시작은 보내기 전에 장부에 적으므로 이 기기의 판은 언제나 열린다. 놀던 기기의 판은 게임 탭 카드로 들어간다.
     */
    private fun presentRummyScreen() {
        if (!isAppActive || !context.sessionStore.isSignedIn || isRummyScreenVisible || context.rummy?.isEngagedInCurrentMatch != true) return
        context.router.present(GamesDestination.Rummy)
    }

    /**
     * 아잉 뒤집기 판이 막 열렸다(내 신청이 수락됨 · 내가 수락함 · 앱을 다시 켜니 진행 중인 판) — 아잉 뒤집기 화면을 연다(게임 탭을 고르고 · 쌓인 화면을
     * 비우고 · 쌓는다). 딥링크·푸시 가지는 없다(결정 "채팅·푸시 없음"). `!isReversiScreenVisible` 가드가 화면을 두 번 쌓는 것을 막는다.
     * ★ 큐브와 달리 **'이 기기가 손댄 판' 가드가 없다**(장부 미이식 — ReversiStore 머리말): 같은 계정의 다른 기기(맥)가 연 판에서도 이 문이 열린다 —
     *   Android 오목과 같은 수준이다. 아이폰 1.0.17 은 `ownsMatch` 로 막는다.
     */
    private fun presentReversiScreen() {
        if (!isAppActive || !context.sessionStore.isSignedIn || isReversiScreenVisible || context.reversi == null) return
        context.router.present(GamesDestination.Reversi)
    }

    /** 1:1 길건너 판이 막 열렸다 — 화면을 연다(판 8 — iOS 1.0.18). 코어는 **이 기기가 두는 판**에서만 부른다(한 판 한 기기). */
    private fun presentCrossyDuelScreen() {
        if (!isAppActive || !context.sessionStore.isSignedIn || isCrossyDuelScreenVisible || context.crossyDuel == null) return
        context.router.present(GamesDestination.CrossyDuel)
    }
}

/** 체스 입구 판정이 읽는 체스 스토어 사실(W2-d `ChessStore` 가 구현한다 — Swift `GamesChessChallengeGate` 가 읽는 칸 그대로). */
interface GamesChessGateFacts {
    /** 보낸 체스 신청이 있다(Swift `store.outgoing != nil`). */
    val hasOutgoing: Boolean

    /** 판을 들고 있다(1:1·**로봇** 둘 다 — Swift `store.match != nil`). */
    val hasMatch: Boolean
    val isBusy: Boolean
}

/**
 * 체스 로비 [도전] 활성 조건 — 맥 `ChessOpponentRow.canChallenge`(`isCapable && !inMatch && !isBusy`)에 **폰에서 셋을 더한** 것이다:
 * 보낸 신청 · 내 판 · **다른 게임의 판**(한 사람 한 판). Android 는 넷째로 **판돈 대결 빌드 깃발**(G §8-17 #1 `duelsEnabled`)을 더한다.
 *
 * INV-GamesStore-8a3da434 이식: 왜 화면이 아니라 여기 있나: 체스 화면(W4-a Compose)은 판정을 묻어 두면 JVM 시험이 값으로 못 잰다.
 *   게이트를 화면에 적으면 되돌려도 빨개지는 시험이 없다.
 * INV-GamesStore-8ba74b82 이식: `userIsCapable` 은 서버 `capable` 이 **null 이면 false** 다(W2-d `ChessStore.user(from:)` 의 계약 — 그 값을
 *   그대로 넘긴다). 모르는 상대에게 신청해 `target_outdated` 를 받는 것보다, 모르면 막는 것이 낫다.
 */
object GamesChessChallengeGate {
    fun isEnabled(
        userIsCapable: Boolean, userInMatch: Boolean, store: GamesChessGateFacts, blockedBy: GamesBusyGame?, duelsEnabled: Boolean,
    ): Boolean = duelsEnabled &&
        blockedBy == null &&
        userIsCapable &&
        !userInMatch &&
        !store.hasOutgoing &&
        // INV-GamesStore-9d8d4f3f 이식: `hasMatch` 가 **로봇 판까지** 막는 자리다([GamesStore.hasLiveChessRobotGame] 머리말) — 코어 `challenge` 에는
        //   `isAIMatch` 가드가 없어 여기를 열면 요청이 그대로 나가고, 1:1 판이 서는 순간 두던 로봇 판이 말없이 사라진다. 예외로 빼지 마라.
        !store.hasMatch &&
        !store.isBusy
}

/**
 * 판돈 시트의 [도전하기] 가 **실제로 요청을 낼 수 있는가**(낼 수 있으면 그 판돈, 못 내면 null). 판돈은 서버 CHECK 3·5·10 의 정수다.
 *
 * INV-GamesStore-be0e2038 이식: 왜 화면이 아니라 여기 있나: 신청이 나가는 **마지막 문**이라 "버튼이 비활성"이 아니라 **요청 0건**을 재야 하고
 *   (들어오는 다른 경로가 생기면 버튼 단언은 못 잡는다), 화면은 JVM 시험이 못 본다.
 */
object GamesChessStakeSend {
    fun sendable(selected: Int?, store: GamesChessGateFacts, balance: Long?, blockedBy: GamesBusyGame?, duelsEnabled: Boolean): Int? {
        if (selected == null || !duelsEnabled) return null
        if (!GamesChessStakeSelection.affordable(selected, balance)) return null
        if (store.isBusy || blockedBy != null) return null
        // 내 판(1:1·**로봇** 둘 다) · 보낸 신청이 있으면 낼 수 없다 — 게이트가 열린 뒤 상태가 바뀐 틈을 막는다.
        if (store.hasMatch || store.hasOutgoing) return null
        return selected
    }
}

/** 판돈 고르기(맥 `ChessStakePrompt` 와 같은 규약 — 고른 판돈을 다시 누르면 해제 · 잔액을 **모르면 막지 않는다**). */
object GamesChessStakeSelection {
    fun toggled(current: Int?, tapped: Int): Int? = if (current == tapped) null else tapped

    /** 이 판돈을 걸 수 있는가. **잔액을 모르면(null) 막지 않는다**(맥 0.3.29 규칙 — 서버가 거절하면 그때 안내한다). */
    fun affordable(stake: Int, balance: Long?): Boolean = balance == null || balance >= stake
}
