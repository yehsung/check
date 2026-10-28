// 원본: Sources/CheckMobileKit/Games/GamesStore.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.games

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.minigame.GamesMiniGameHub
import com.yehsung.aingcheck.core.stores.minigame.MiniGameExposure
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelUser
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
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
}

/**
 * 지금 **사람과의** 판을 들고 있는 게임 — 한 사람 한 판(B8)의 까닭을 화면이 말할 수 있게 하는 값.
 *
 * 서버는 체스 쪽에서만 두 게임을 함께 본다(`chess__busy`): **오목 쪽 게이트는 체스·테트리스를 모른다**. 그래서 체스·테트리스 중인 사람이
 * 오목을 신청·수락하는 길은 **클라만** 막을 수 있다. 폰은 세 게임 입구를 한 화면에 같이 띄우므로 **세 방향**을 그려야 한다.
 */
enum class GamesBusyGame(val rawValue: String) {
    gomoku("gomoku"),
    chess("chess"),

    /** 1:1 테트리스(1.0.11). 서버 `chess__busy` 는 셋을 함께 보지만 **오목 쪽 게이트는 여전히 남을 모른다**. */
    tetris("tetris");

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

    /** 오목 · 체스 · 테트리스 화면 중 하나가 떠 있다. 생일 선물 축하 시트(v0.3.66)가 이때는 스스로 뜨지 않는다(W2-c `presentCakeGiftIfDue`). */
    val isAnyMatchScreenVisible: Boolean get() = isGomokuScreenVisible || isChessScreenVisible || isTetrisScreenVisible

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
        syncIdleTimer()
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
        syncIdleTimer()
    }

    fun reset() {
        miniGames.reset()
        isGomokuScreenVisible = false
        isChessScreenVisible = false
        isTetrisScreenVisible = false
        pendingGomokuFocusID = null
        syncAIThinker()
        syncIdleTimer()
    }

    /** 코어 체스 스토어 문(= `context.chess`). */
    val chess: GamesBoardGameLink get() = context.chess

    /** 코어 테트리스 대결 스토어 줄임(= `context.tetris`). 화면·다른 갈래가 읽는 자리는 **두 이름이 같은 인스턴스**다. */
    val tetris: TetrisDuelStore get() = context.tetris

    /**
     * 탭 배지: 만료 안 된 받은 오목 신청 수.
     *
     * INV-GamesStore-7d3fdc37 이식: **체스 신청은 아직 안 센다.** 체스는 받은함 RPC 가 없어 받은 신청을 `chess_lobby` 로만 알고, 그 조회는
     * 허브·체스 화면에서만 나간다 — 배지에 넣으면 "60초 TTL 짜리 숫자가 30초 스로틀로 갱신되는" 꼴이 되어 없는 신청을 가리키거나 놓친다.
     * INV-GamesStore-3d7a8f45 이식: **테트리스 신청도 안 센다**(P5 — 같은 근거다). 받은 신청이 `tetris_lobby` 응답에만 실려 오고 그 조회는
     * **게임 탭·테트리스 화면에서만** 나간다. 알리는 자리는 **둘**이다: 게임 탭 테트리스 카드의 "받은 신청" 칩 · 테트리스 화면 로비 맨 위 신청 카드.
     */
    val badgeCount: Int get() = context.gomoku.pendingIncomingInviteCount

    /** 게임 탭이 보여 주는 루비 잔액 — **공유 미러**를 먼저 읽는다(나 탭 상점 구매가 미러만 적는다). 미러를 모르면 테트리스 코어 값. */
    val rubyBalance: Int? get() = context.sharedRubyBalance ?: context.tetris.rubyBalance

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

    /** 체스 입구를 막는 까닭(없으면 null). 오목·테트리스 판이 흐르면 체스를 신청·수락할 수 없다 — 서버도 같은 판정을 한다(`chess__busy`). */
    val chessEntryBlock: GamesBusyGame?
        get() {
            if (hasLiveGomokuMatch) return GamesBusyGame.gomoku
            return if (hasLiveTetrisMatch) GamesBusyGame.tetris else null
        }

    /**
     * 오목 입구를 막는 까닭(없으면 null).
     * INV-GamesStore-a6af4558 이식: **이 방향은 클라밖에 막는 데가 없다** — 서버의 오목 게이트는 체스·테트리스를 모른다.
     * 안 막으면 체스 중인 사람이 오목을 수락해 체스를 시간패한다.
     */
    val gomokuEntryBlock: GamesBusyGame?
        get() {
            if (hasLiveChessMatch) return GamesBusyGame.chess
            return if (hasLiveTetrisMatch) GamesBusyGame.tetris else null
        }

    /**
     * 테트리스 입구를 막는 까닭(없으면 null). 테트리스는 **판돈이 걸린 실시간 판**이라 막는 쪽이 더 무겁다 —
     * 오목·체스 판을 두는 중에 테트리스를 수락하면 그 판은 15초 침묵으로 **진다**(서버 D5).
     */
    val tetrisEntryBlock: GamesBusyGame?
        get() {
            if (hasLiveGomokuMatch) return GamesBusyGame.gomoku
            return if (hasLiveChessMatch) GamesBusyGame.chess else null
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
            // 미니게임: 끝나지 않은 판이 있으면 켠다(폰은 background 가 곧 판 폐기·무제출이라 자동잠금이 곧 판 폐기다).
            // INV-GamesStore-78b92b69 이식: **타이밍 바만 뺀다.** 그 판은 **스스로 끝나지 않는다** — 탭을 받을 때까지 진행 중에 머문다.
            //   여기에 타이밍 바를 넣으면 화면이 **영원히** 켜져 있다(자동잠금이 유일한 상한이었다). 새 게임을 더할 때 이 성질을 확인할 것.
            val controller = miniGames.controller
            if (controller != null && controller.isPlaying && controller.kind != MiniGameKind.timingBar) return true
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
            val tetrisMatch = context.tetris.match
            if (tetrisMatch != null && !tetrisMatch.isFinished) return true
            if (!context.gomoku.hasMatch) return false
            if (context.gomoku.isAIMatch) return context.gomoku.hasUnfinishedMatch && isGomokuScreenVisible
            return context.gomoku.hasUnfinishedMatch
        }

    // MARK: 화면 꺼짐 방지(주인은 이 스토어 하나)

    /**
     * 화면 꺼짐 방지 싱크를 단다(첫 한 번만 — 뒤의 호출은 무시). 이후 [wantsIdleTimerDisabled] 가 바뀔 때마다 이 스토어가 넘긴다.
     * 재료(앱 active · 판 · 미니게임 구동기)는 Compose 스냅숏 상태다 — `snapshotFlow` 가 그 값이 바뀔 때마다 다시 읽는다(Swift
     * `withObservationTracking`). 스냅숏 쓰기 알림은 앱에서 compose-ui 의 전역 스냅숏 관리자가 보낸다. 로그인 상태는 세션 스토어의
     * StateFlow 라 스냅숏이 못 보므로 자리 API(active · background · 로그아웃 [reset])가 끝에서 [syncIdleTimer] 를 직접 부른다.
     * 지금 값은 **곧바로 한 번** 넘긴다(구독이 첫 값을 받기 전에도 싱크가 상태를 안다).
     */
    fun installIdleTimerSink(sink: (Boolean) -> Unit) {
        if (idleTimerSink != null) return
        idleTimerSink = sink
        syncIdleTimer()
        idleTimerJob = context.scope.launch {
            snapshotFlow { wantsIdleTimerDisabled }.distinctUntilChanged().collect { syncIdleTimer() }
        }
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
    fun sendable(selected: Int?, store: GamesChessGateFacts, balance: Int?, blockedBy: GamesBusyGame?, duelsEnabled: Boolean): Int? {
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
    fun affordable(stake: Int, balance: Int?): Boolean = balance == null || balance >= stake
}
