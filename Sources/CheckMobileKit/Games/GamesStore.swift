import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 게임 탭에서 쌓는 화면(경로 원소).
///
/// ⚠️ **값을 더하면 `GamesTab.swift` 의 `navigationDestination(for: GamesDestination.self)` switch 를 같이 넓혀야
/// 한다.** 그 switch 에는 `default:` 가 없어서(일부러다 — 모르는 목적지가 빈 화면으로 오배달되지 않게) 값을
/// 더한 순간 **iOS 빌드가 컴파일 에러로 막힌다.** 그런데 그 파일은 통째로 `#if os(iOS)` 안이라 **맥 스위트와
/// `swift build` 는 통과한다** — 1.0.11 씨앗 커밋이 `.tetrisDuel` 을 더한 뒤 `ios/scripts/build-sim.sh` 만
/// 빨간 상태였다(레인 B 가 그 가지를 더하면 풀린다). 맥이 초록이라고 폰이 서는 것이 아니다.
package enum GamesDestination: Hashable, Sendable {
    case miniGame(MiniGameKind)
    case gomoku
    case chess
    /// 1:1 테트리스(1.0.11) — 로비·준비·판·결과·순위를 **입구 하나**로 연다(체스와 같은 구조).
    case tetrisDuel
}

/// 지금 **사람과의** 판을 들고 있는 게임 — 한 사람 한 판(B8)의 까닭을 화면이 말할 수 있게 하는 값.
///
/// 서버는 체스 쪽에서만 두 게임을 함께 본다(`chess__busy`): 체스를 신청·수락할 때는 오목 판까지 보고 막지만,
/// **오목 쪽 게이트는 체스를 모른다**(인수인계 §6-7 의 '알려진 비대칭'). 그래서 체스 중인 사람이 오목을
/// 신청·수락하는 길은 **클라만** 막을 수 있고, 안 막으면 오목이 열리는 동안 체스는 판돈이 걸린 채 시간패한다.
/// 폰은 두 게임 입구를 한 화면에 같이 띄우므로 **양방향**을 그려야 한다.
package enum GamesBusyGame: String, Equatable, Sendable, CaseIterable {
    case gomoku
    case chess
    /// 1:1 테트리스(1.0.11). 서버 `chess__busy` 는 셋을 함께 보지만 **오목 쪽 게이트는 여전히 남을 모른다** —
    /// 그래서 클라가 세 방향을 다 막는다.
    case tetris

    /// 문구 표가 쓰는 짝(`ChessPhoneText.BusyGame`). 두 열거가 따로 있는 까닭: 이쪽은 **스토어 판정**이고
    /// 그쪽은 **문구 표**다(문구 표는 뷰·스토어를 모르는 자리라야 맥 스위트가 값으로 잰다). 옮기는 자리를
    /// 여기 하나로 둬서 두 꼴을 손으로 가르는 switch 가 화면마다 생기지 않게 한다.
    /// ⚠️ **빠짐없이 가르는 switch 로 둔다.** 삼항으로 두면 새 게임이 들어올 때 조용히 엉뚱한 이름이 되고
    /// (테트리스가 "오목" 으로 읽힌다) 테스트는 초록이다 — 1.0.11 에서 실제로 그 꼴이 됐다.
    package var text: ChessPhoneText.BusyGame {
        switch self {
        case .gomoku: return .gomoku
        case .chess: return .chess
        case .tetris: return .tetris
        }
    }
}

/// 딥링크 한 건을 게임 탭 경로에 옮기는 동작(`GamesStore.routeStep(for:)`). 뷰는 돌려받은 대로 경로만 바꾼다.
package enum GamesRouteStep: Equatable, Sendable {
    case popToRoot
    case push(GamesDestination)
}

/// 게임 탭 스토어(SPEC-ios §3.5) — 탭 자리 API 를 지키고, 두 갈래를 잇는다.
///
/// 1. **미니게임** — `miniGames`(`GamesMiniGameHub`): 오늘 순위 · 로컬 최고 · 라운드 토큰 · 제출. 엔진은 코어 규칙.
/// 2. **1:1 오목** — 코어 `GomokuStore`(context.gomoku, host = 폰 세션). 이 스토어는 **창 수명**을 폰 수명에 옮긴다:
///    맥의 창 표시·숨김(`windowDidShow/Hide`)은 폰에서 "오목 화면이 보이고 앱이 active 인가"다.
///    - 오목 화면이 나타남 → `openWindow`(로비·인박스·진행 판) + active 면 `windowDidShow`(폴링 시작).
///    - 화면이 사라짐 → `windowDidHide`(폴링을 멈추고, 결과 화면이었으면 그 판에서 나간다 — **대국은 서버에서 계속 흐른다**)
///      **+ 관전 중이었으면 관전을 끝낸다**(폰에서만 — `gomokuScreenDidDisappear` 주석).
///    - 앱이 background → **가림**(`windowOcclusionDidChange(visible: false)`) — 폴링만 멈추고 판에서 나가지 않는다(관전도 남는다).
///    - 앱이 active 로 돌아옴(화면이 보이는 채) → 가림 해제(또는 `windowDidShow`) + 따라잡기(인박스 + 진행 판의 놓친 수).
///    - 판이 막 시작됨(`presentWindow`) → 앱이 active 면 오목 화면을 연다(신청자가 수락된 순간을 모르면 흑 30초를 흘린다).
/// 3. **AI 대국**(1.0.1) — 규칙·판·서버 차단은 코어(`GomokuStoreAI`, 맥과 한 벌). 이 스토어는 폰 선택기(`aiThinker`)를 코어에 끼우고
///    "오목 화면이 보이고 앱이 active 인가"를 그 선택기의 허락으로 옮긴다 — 떠나면 AI 탐색을 취소하고 돌아오면 다시 생각한다
///    (`GamesGomokuAI.swift` 머리 주석). 사람 시계 멈춤은 위 창 수명(숨김·가림)이 코어에서 이미 한다.
///
/// 4. **1:1 체스**(0.3.44 서버·맥 · 폰은 이번 세션) — 코어 `ChessStore`(context.chess, host = 오목과 **같은** 폰 세션 호스트).
///    오목과 **같은 세 걸음**을 옮긴다: 화면이 나타남 → `openWindow` + active 면 `windowDidShow` /
///    사라짐 → `stopWatching()` **먼저** 그리고 `windowDidHide()` / 앱이 background → **가림**(판·관전을 남긴다).
///    판이 막 열림(`presentWindow`) → 체스 화면을 연다(체스는 자동 착수가 없어 모르면 10분 시계를 그대로 흘린다).
///
/// 5. **1:1 테트리스**(0.3.60 서버·맥 · 폰은 1.0.11) — 코어 `TetrisDuelStore`(context.tetris, host 는 오목·체스와 **같은** 하나).
///    체스와 **같은 세 걸음**을 옮기되 갈리는 것이 둘이다.
///    - 떠나는 길에 `stopWatching()` 이 **없다**: 관전이 없다(D8 — 이번 범위에서 뺐다). `windowDidHide()` → `windowDidClose()` 둘이다.
///    - `appDidBecomeActive` 에 **else 가지가 있다**(P8): 화면이 보이면 가림 해제/`windowDidShow()` + `catchUp()`,
///      **안 보이면** `systemDidWake()`. 체스는 그 자리에 `refreshLobbyIfStale()`(30초 스로틀)을 쓰는데 테트리스는
///      판돈이 걸린 실시간 판이라 돌아온 순간의 신선도를 스로틀에 맡기지 않는다.
///    판이 막 열림(`presentWindow`) → 테트리스 화면을 연다. **맥이 체스에서 이 문을 안 물려 판돈 걸린 판을 조용히
///    시간패했다** — 테트리스는 거기에 15초 침묵(D5)이 더 붙어 수락하고 화면을 못 열면 그대로 진다.
///
/// 탭 배지 = 받은 오목 신청 수(만료 안 된 것 — 체스·테트리스는 안 센다, `badgeCount` 주석). 받은 신청은 인박스가 채운다 —
/// 계기는 앱 active(60초 스로틀) · 실시간 'gomoku' 신호(기반 배선) · 오목 화면.
///
/// **한 사람 한 판(B8)은 삼각이다** — 세 게임 입구가 한 화면에 있으므로 `chessEntryBlock`·`gomokuEntryBlock`·
/// `tetrisEntryBlock` 셋을 그려야 한다(까닭은 `GamesBusyGame`).
@MainActor
@Observable
package final class GamesStore {
    @ObservationIgnored package let context: MobileContext
    package let miniGames: GamesMiniGameHub

    /// 오목 화면이 지금 떠 있다(내비게이션에 올라와 보인다).
    package private(set) var isGomokuScreenVisible = false
    /// 체스 화면이 지금 떠 있다(오목과 같은 뜻 — 코어의 '창 표시'를 폰 화면 수명으로 옮긴 값).
    package private(set) var isChessScreenVisible = false
    /// 1:1 테트리스 화면이 지금 떠 있다(위 둘과 같은 뜻). `appDidBecomeActive` 의 P8 분기가 이 값으로 갈린다 —
    /// 거짓인데 `windowDidShow()` 를 부르면 **보이지도 않는 판의 준비 보고가 나가고**(코어 머리말 ⑨) 사용자는
    /// 못 보는 카운트다운에 끌려 들어가 판돈을 잃는다.
    package private(set) var isTetrisScreenVisible = false
    /// 앱이 active 다(로그인 상태에서 appDidBecomeActive ~ appDidEnterBackground).
    package private(set) var isAppActive = false
    /// 오목 화면을 열 때 보여 줄 신청·판 id(딥링크 `gomoku/invite/<id>` · `gomoku/match/<id>`). 화면이 한 번 꺼내 쓴다.
    /// 화면이 **이미 보이면** 여기 남기지 않는다(`routeStep(for:)` 이 코어에 바로 넘긴다).
    package var pendingGomokuFocusID: String?

    /// 데모 전용: 시작 라우트가 체스 장면(`games/chess/…`)이라 게임 탭이 체스를 쌓아야 한다.
    /// 앱 모델이 세우고(`MobileAppModel.openDemoRouteIfNeeded`) 게임 탭이 **한 번** 꺼내 쓴다.
    /// `#if DEBUG` 로 감싸지 않은 까닭: **Bool 한 칸**이라 Release 바이너리에 데모 타입 이름을 들이지 않고
    /// (아래 꼬리 값과 갈리는 지점이다 — 출시 게이트는 `MobileDemo` 라는 **이름**을 본다),
    /// 세우는 자리가 데모뿐이라 Release 에서는 영원히 false 다. 구성 분기가 없어야 맥 스위트가 값으로 잰다.
    package var pendingDemoChessScreen = false

    /// 데모 전용: 시작 라우트의 **꼬리를 푼 값**(열 판 · 걸 관전 · 로비 시작 절 — `MobileDemoChessRoute`).
    ///
    /// 위 깃발과 달리 **꺼내 비우지 않는다.** 스크롤 닻은 그릴 때마다 읽히는 값이고(한 번 꺼내면 두 번째
    /// 그리기에서 머리로 튄다), 판·관전을 거는 두 자리는 다시 불러도 무해하다 —
    /// `openWindow(focusMatchID:)` 는 들고 있는 판이면 다시 안 받고 `startWatching` 은 같은 관전이면 돌아선다.
    /// 로그아웃 `reset()` 이 비운다(다음 사람의 로비에 남의 장면이 남지 않게).
    ///
    /// ★ **`#if DEBUG` 안이다**(저장 프로퍼티라 확장으로 못 옮긴다 — 맥 전용 `workTickGate` 와 같은 수법).
    ///   타입이 DEBUG 전용이고 Release 바이너리에 그 **이름이 남으면 출시 게이트가 막는다**
    ///   (`ios/scripts/check-release-app.sh` · 까닭은 `Demo/MobileDemoChessRoute.swift` 머리).
    ///   Release 에서 잃는 것은 없다 — 세우는 자리가 데모 라우트뿐이라 그 구성에서는 원래부터 영원히 nil 이었다.
    #if DEBUG
    package var demoChessRoute: MobileDemoChessRoute?
    #endif

    /// 데모 전용: 시작 라우트가 1:1 테트리스 장면(`games/tetris/…`)이라 게임 탭이 테트리스를 쌓아야 한다.
    /// 위 체스 깃발과 **같은 규약**이다(Bool 한 칸이라 `#if DEBUG` 밖 · 세우는 자리가 데모뿐이라 Release 에서는
    /// 영원히 false · 구성 분기가 없어야 맥 스위트가 값으로 잰다).
    package var pendingDemoTetrisScreen = false

    /// 데모 전용: 시작 라우트의 **꼬리를 푼 값**(열 판 · 로비 탭 — `MobileDemoTetrisRoute`).
    ///
    /// 위 깃발과 달리 **꺼내 비우지 않는다.** 로비 탭은 화면이 설 때마다 읽는 값이고, 판을 거는 자리는 다시
    /// 불러도 무해하다(`openWindow(focusMatchID:)` 는 들고 있는 판이면 다시 안 받는다).
    /// 로그아웃 `reset()` 이 비운다(다음 사람의 로비에 남의 장면이 남지 않게).
    ///
    /// ★ **`#if DEBUG` 안이다**(저장 프로퍼티라 확장으로 못 옮긴다 — 체스 꼬리와 같은 수법). 타입이 DEBUG
    ///   전용이고 Release 바이너리에 그 **이름이 남으면 출시 게이트가 막는다**
    ///   (`ios/scripts/check-release-app.sh` · 까닭은 `Demo/MobileDemoTetrisRoute.swift` 머리).
    #if DEBUG
    package var demoTetrisRoute: MobileDemoTetrisRoute?
    #endif

    /// AI 대국의 수 선택기(코어 `aiMoveChooser` 에 끼운다). 사람 대국은 이것을 한 번도 부르지 않는다.
    @ObservationIgnored package let aiThinker = GamesGomokuAIThinker()

    /// 화면 꺼짐 방지를 실제로 거는 곳(iOS 는 init 이 `GamesSystemIdleTimer` 를 단다 · 테스트는 기록용).
    @ObservationIgnored private var idleTimerSink: (@MainActor (Bool) -> Void)?
    /// 마지막으로 싱크에 넘긴 값(같은 값은 다시 넘기지 않는다). 싱크가 없으면 nil.
    @ObservationIgnored package private(set) var appliedIdleTimerDisabled: Bool?

    package init(context: MobileContext) {
        self.context = context
        miniGames = GamesMiniGameHub(context: context)
        // 판이 막 시작됐다(내 신청이 수락됨 · 내가 수락함 · 앱을 다시 켜니 진행 중인 판) — 오목 화면을 연다.
        // 네트워크가 아니라 문을 다는 것이라 init 에서 해도 된다.
        context.gomoku.presentWindow = { [weak self] in self?.presentGomokuScreen() }
        // 체스도 같은 문이 필요하다. 맥에서 이 문을 안 물려 **판돈이 걸린 판을 조용히 시간패**했다
        // (CheckApp.wireChess 의 ⑤ — 체스는 오목의 자동 착수 장치를 전부 버렸다). 코어가 부르는 자리 셋:
        // `openWindow` · 수락 응답(`respond`) · 진행 중 판으로 처음 넘어갈 때(`noteMatchProgress`).
        context.chess.presentWindow = { [weak self] in self?.presentChessScreen() }
        // 테트리스도 **같은 문**이다. 안 물리면 수락·시작이 화면을 못 연다 — 맥이 체스에서 이 문을 안 물려
        // 판돈 걸린 판을 조용히 시간패했고(CheckApp.wireChess 의 ⑤), 테트리스는 거기에 15초 침묵(D5)이 붙어
        // **수락한 판이 화면 없이 그대로 진다.** 코어가 부르는 자리 셋:
        // `openWindow` · 수락 응답(`respond`) · 진행 중 판으로 처음 넘어갈 때(`noteMatchStarted`).
        context.tetris.presentWindow = { [weak self] in self?.presentTetrisScreen() }
        // AI 대국: 코어 기본 선택기(창을 몰라 떠나도 계속 생각한다 — 맥 동작) 대신 화면 수명을 아는 폰 선택기. 문을 다는 것뿐이다.
        context.gomoku.aiMoveChooser = aiThinker.chooser
        aiThinker.isStillNeeded = { [weak gomoku = context.gomoku] board, color in
            guard let gomoku, gomoku.isAIThinking, let game = gomoku.aiGame else { return false }
            return game.board == board && game.aiColor == color
        }
        #if os(iOS)
        // 화면 꺼짐 방지의 주인은 이 스토어다 — 게임 탭을 한 번도 안 열었어도(다른 탭에서 판이 시작돼도) 값이 따라간다.
        installIdleTimerSink { GamesSystemIdleTimer.apply(disabled: $0) }
        #endif
    }

    // MARK: 자리 API

    package func appDidBecomeActive() {
        isAppActive = true
        syncAIThinker()
        // background 로 가며 끝낸 판의 제출이 네트워크로 실패했으면 **같은 토큰으로** 한 번 더(세 게임 모두).
        miniGames.retryPendingSubmitIfAny()
        let gomoku = context.gomoku
        // 받은 신청(탭 배지·첫 화면 카드)의 신선도. 60초 스로틀은 코어가 한다.
        gomoku.refreshInboxIfStale()
        if isGomokuScreenVisible {
            if gomoku.isWindowVisible {
                // background 에서 '가림'으로 멈춰 둔 폴링을 되살린다(창은 닫힌 적이 없다).
                gomoku.windowOcclusionDidChange(visible: true)
            } else {
                gomoku.windowDidShow()
            }
            // background 동안 놓친 것(신청·수락·상대 수). 서버 시계는 그동안에도 흘렀다.
            Task { await gomoku.catchUp() }
        }
        // 체스: 같은 세 걸음. 체스는 시계가 **서버에서만** 흐르고 자동 착수가 없어(DECISIONS B4) background 에서
        // 돌아온 순간의 따라잡기가 오목보다 더 중요하다 — 안 하면 다음 폴링 한 걸음(1.0~1.5초)까지 옛 시계를 그린다.
        let chess = context.chess
        chess.refreshLobbyIfStale()
        // ★ 예전엔 여기가 `guard isChessScreenVisible else { return }` 였다. **`if` 로 바꾼 것이 계약이다** —
        //   아래 테트리스 가지가 이 함수의 꼬리에 붙으므로, guard 로 두면 "체스 화면이 안 보일 때"(= 거의 늘)
        //   테트리스 따라잡기가 **한 번도 안 돈다.** 새 게임을 더할 때도 꼬리에 guard 를 쓰지 마라.
        if isChessScreenVisible {
            if chess.isWindowVisible {
                chess.windowOcclusionDidChange(visible: true)
            } else {
                chess.windowDidShow()
            }
            Task { await chess.catchUp() }
        }
        // 테트리스(P8): **깨어남은 한 번만 따라잡는다.**
        //  · 화면이 보이면 — 창이 서 있으면 가림만 풀고(background 에서 '가림'으로 멈춰 둔 폴링을 되살린다),
        //    안 서 있으면 `windowDidShow()`. 그리고 `catchUp()` 으로 background 동안 놓친 것을 읽는다
        //    (신청·수락·**상대 공격 누계**·정산. 서버 시계는 그동안에도 흘렀고 15초 침묵은 그동안에도 셌다).
        //  · 안 보이면 — `systemDidWake()`. 받은 신청 칩(게임 탭 카드)과 한 사람 한 판의 `activeMatchID` 가
        //    이 계기에 달려 있다. 체스처럼 `refreshLobbyIfStale()`(30초 스로틀)을 쓰지 않는 까닭은 테트리스가
        //    **판돈이 걸린 실시간 판**이라서다 — 돌아온 순간 "내 판이 지금 흐르는가"를 스로틀에 맡기면
        //    30초까지 오목·체스 입구가 열린 채다.
        // ★ **두 가지를 겹쳐 부르지 마라.** `catchUp()` 과 `systemDidWake()` 는 **본문이 같다**(둘 다
        //   `refreshLobby()` — 코어 1166·1177줄). 겹쳐 불러도 코어 `lobbyInFlight` 가드가 합쳐서 조회가
        //   늘지는 않지만(실측), `windowDidShow()` 를 화면 없이 부르면 **보이지 않는 판의 준비 보고가 나간다.**
        let tetris = context.tetris
        if isTetrisScreenVisible {
            if tetris.isWindowVisible {
                tetris.windowOcclusionDidChange(visible: true)
            } else {
                tetris.windowDidShow()
            }
            Task { await tetris.catchUp() }
        } else {
            tetris.systemDidWake()
        }
    }

    package func appDidEnterBackground() {
        isAppActive = false
        // AI 탐색은 background 에서 돌지 않는다(돌아오면 처음부터 다시 생각한다).
        syncAIThinker()
        miniGames.appDidEnterBackground()
        // 오목은 **가림**으로 멈춘다(`windowOcclusionDidChange(visible: false)`) — 폴링만 멈추고 창은 닫지 않는다.
        // `windowDidHide` 를 부르면 결과 화면인 채로 잠깐 앱을 나갔을 뿐인데 그 판에서 '나간' 것이 되어(gomoku_leave)
        // 두 사람이 다 나간 판의 인사 채팅이 서버에서 지워진다.
        // **관전도 여기서 끊지 않는다**: 알림 하나 읽고 오는 것은 "그만 볼게"가 아니다 — 끊는 자리는 화면을 떠나는 길
        // (`gomokuScreenDidDisappear`)뿐이고, 그 대조를 `GamesGomokuWatchExitTests` 가 나란히 잰다.
        if isGomokuScreenVisible, context.gomoku.isWindowVisible {
            context.gomoku.windowOcclusionDidChange(visible: false)
        }
        // 체스도 **가림**이다. `windowDidHide` 를 부르면 두 가지가 깨진다: ① 결과 화면인 채로 알림 하나 읽고 온 것이
        // "그 판에서 나갔다"가 되고(`windowDidHide` 가 끝난 관전을 내린다), ② 진행 중인 남의 판 관전이 화면을
        // 떠난 적도 없는데 끊긴다. 끊는 자리는 화면을 떠나는 길(`chessScreenDidDisappear`) 하나뿐이다.
        if isChessScreenVisible, context.chess.isWindowVisible {
            context.chess.windowOcclusionDidChange(visible: false)
        }
        // 테트리스도 **가림**이다. `windowDidHide()` 를 부르면 안 되는 까닭이 테트리스에는 하나 더 있다:
        // 그 문이 `windowDidClose()` 와 짝을 이뤄 **끝난 판을 접는 길**이고(아래 `tetrisScreenDidDisappear`),
        // 알림 하나 읽고 온 사람의 결과 카드가 사라져 **루비가 얼마 움직였는지 못 보고 로비로 떨어진다.**
        // ★ **판은 멈추지 않는다**(P7·D10). 가림은 폴링만 멈추고 눌린 키를 놓는다 — 조각은 단조 시계로 계속
        //   떨어지고, iOS 가 판 루프 Task 를 재우면 서버가 15초 침묵으로 내 패(`disconnect`)로 닫는다.
        //   그것이 의도다(화면을 가려 이득을 보는 길이 없어야 한다). 그래서 화면이 **그 사실을 말한다** —
        //   "판 중에 앱을 나가면 져요"(레인 C).
        if isTetrisScreenVisible, context.tetris.isWindowVisible {
            context.tetris.windowOcclusionDidChange(visible: false)
        }
    }

    package func reset() {
        miniGames.reset()
        isGomokuScreenVisible = false
        isChessScreenVisible = false
        isTetrisScreenVisible = false
        pendingGomokuFocusID = nil
        pendingDemoChessScreen = false
        pendingDemoTetrisScreen = false
        #if DEBUG
        demoChessRoute = nil
        demoTetrisRoute = nil
        #endif
        syncAIThinker()
    }

    /// 데모 체스 장면 깃발을 **한 번** 꺼낸다(꺼내면 비운다 — 뒤의 무관한 진입에 쓰이지 않게).
    /// 오목 `pendingGomokuFocusID` 가 같은 자리에서 데인 것과 같은 규약이다.
    package func consumePendingDemoChessScreen() -> Bool {
        guard pendingDemoChessScreen else { return false }
        pendingDemoChessScreen = false
        return true
    }

    /// 데모 테트리스 장면 깃발을 **한 번** 꺼낸다(꺼내면 비운다 — 같은 규약). 게임 탭이 두 계기에서 부르므로
    /// (`onAppear` · `routeSerial`) 비우지 않으면 화면이 두 번 쌓인다.
    package func consumePendingDemoTetrisScreen() -> Bool {
        guard pendingDemoTetrisScreen else { return false }
        pendingDemoTetrisScreen = false
        return true
    }

    /// 코어 체스 스토어 줄임(= `context.chess`). 화면·다른 레인이 읽는 자리는 **두 이름이 같은 인스턴스**다.
    package var chess: ChessStore { context.chess }

    /// 코어 테트리스 대결 스토어 줄임(= `context.tetris`). 같은 규약이다.
    package var tetris: TetrisDuelStore { context.tetris }

    /// 탭 배지: 만료 안 된 받은 오목 신청 수.
    ///
    /// ⚠️ **체스 신청은 아직 안 센다.** 체스는 받은함 RPC 가 없어 받은 신청을 `chess_lobby` 로만 알고(머리말 ⑪),
    /// 그 조회는 허브·체스 화면에서만 나간다 — 배지에 넣으면 "60초 TTL 짜리 숫자가 30초 스로틀로 갱신되는"
    /// 꼴이 되어 없는 신청을 가리키거나 있는 신청을 놓친다. 체스 신청을 배지에 싣는 날은 그 신선도를
    /// 어디서 받을지(푸시 · 실시간 `chessSignal`)를 먼저 정해야 한다.
    ///
    /// ⚠️ **테트리스 신청도 안 센다**(P5 — 같은 근거다). 받은 신청이 `tetris_lobby` 응답에만 실려 오고 그 조회는
    /// **게임 탭·테트리스 화면에서만** 나간다(`hubDidAppear` 의 30초 스로틀 · `appDidBecomeActive` 의 P8 가지).
    /// 배지에 실으면 60초 TTL 짜리 숫자를 30초 스로틀로 갱신하는 꼴이 되어 없는 신청을 가리키거나 있는 신청을
    /// 놓친다. 알리는 자리는 **둘**이다: 게임 탭 테트리스 카드의 "받은 신청" 칩 · 테트리스 화면 로비 맨 위 신청 카드.
    /// 푸시(`tetris_invite`)는 서버 몫이고 **1.0.11 범위 밖**이다(D8) — 그때 이 자리를 다시 본다.
    package var badgeCount: Int { context.gomoku.pendingIncomingInvites.count }

    /// 게임 탭이 보여 주는 루비 잔액 — **공유 미러**(`context.gomokuHost.rubyBalance`)를 먼저 읽는다(통합 w4/int).
    /// 미러에는 두 쓰기가 모두 온다: 오목 응답 정산(코어 `applyRuby` 가 코어 값과 미러를 함께 적는다) · 나 탭 상점(`shop_state` · 구매 응답은
    /// 미러만 적는다). 코어 값을 먼저 읽으면 나 탭에서 캐릭터를 산 뒤 다음 오목 조회 전까지 옛 잔액이 보였다. 미러를 모르면 코어 값.
    package var rubyBalance: Int? { context.gomokuHost.rubyBalance ?? context.gomoku.rubyBalance }

    /// 오목 로비의 **상대 고르기 목록** — 차단해 숨긴 사람을 걷어낸 것. 화면이 읽는 자리는 여기 하나다.
    ///
    /// 차단 확인 시트가 "사람 찾기와 오목 신청에서 서로 보이지 않아요" 라고 약속하는데, 코어 `users` 는 서버 로비 응답 그대로라
    /// 방금 차단한 사람이 [도전] 버튼과 함께 그대로 서 있었다 — 사용자가 방금 읽은 세 줄 중 한 줄이 눈앞에서 거짓이 된다
    /// (메시지 탭 `filteredDirectory` 와 같은 근거 · 같은 방식).
    /// **거르는 것은 화면이 읽는 이 자리뿐**이다: 코어 목록은 서버가 답한 그대로 둬야 차단이 실패했을 때 그대로 돌아온다.
    /// 서버도 로비 응답에서 서로 차단한 사람을 빼 줘야 **반대쪽**에서도 사라진다(작업 S — `gomoku_lobby`).
    package var gomokuLobbyUsers: [GomokuUser] {
        let hidden = context.links.messages?.hiddenBlockedPeerIDs ?? []
        guard !hidden.isEmpty else { return context.gomoku.users }
        return context.gomoku.users.filter { !hidden.contains($0.id) }
    }

    /// 체스 로비의 **상대 고르기 목록** — 같은 근거·같은 방식(위 오목 주석). 코어 `visibleUsers` 는 스토어가 쥔
    /// `hiddenPeerIDs`(폰은 안 채운다)까지 거른 값이고, 거기에 메시지 탭의 차단 목록을 한 번 더 겹친다.
    /// **정렬은 하지 않는다** — 코어 `applyLobby` 가 서버와 같은 규칙(근무 중·가능 → 대국 중 → …)으로
    /// 이미 맞춰 뒀고(`ChessStore.sortedForLobby`), 화면이 다시 정렬하면 두 규칙이 갈린다.
    package var chessLobbyUsers: [ChessUser] {
        let hidden = context.links.messages?.hiddenBlockedPeerIDs ?? []
        let users = context.chess.visibleUsers
        guard !hidden.isEmpty else { return users }
        return users.filter { !hidden.contains($0.id) }
    }

    /// 테트리스 로비의 상대 고르기 목록 — 같은 근거·같은 방식(위 두 주석). **정렬은 하지 않는다**(코어
    /// `applyLobby` 가 서버와 같은 규칙으로 이미 맞춰 뒀다 — 화면이 다시 정렬하면 두 규칙이 갈린다).
    package var tetrisLobbyUsers: [TetrisDuelUser] {
        let hidden = context.links.messages?.hiddenBlockedPeerIDs ?? []
        let users = context.tetris.visibleUsers
        guard !hidden.isEmpty else { return users }
        return users.filter { !hidden.contains($0.id) }
    }

    // MARK: 한 사람 한 판 (B8 — 양방향)

    /// 사람과의 **오목** 판이 지금 흐르고 있는가.
    ///
    /// 둘을 뺀다: **AI 판**(루비·순위가 없고 화면을 떠나면 시계가 멈춘다 — 그 판이 다른 게임을 막으면 두던 채
    /// 며칠 남은 판 하나가 입구를 통째로 잠근다)과 **끝난 판**(결과 화면은 판이 아니다). 서버가 말한 진행 판
    /// id(`activeMatchID`)는 들고 있는 판이 없어도 참이다 — 앱을 막 켠 사람의 판이 그 갈래다.
    package var hasLiveGomokuMatch: Bool {
        let gomoku = context.gomoku
        if gomoku.activeMatchID != nil { return true }
        guard let match = gomoku.match, !match.isFinished else { return false }
        return !gomoku.isAIMatch
    }

    /// 사람과의 **체스** 판이 지금 흐르고 있는가(위와 같은 규칙 — 로봇 판·끝난 판은 아니다).
    package var hasLiveChessMatch: Bool {
        let chess = context.chess
        if chess.activeMatchID != nil { return true }
        guard let match = chess.match, !match.isFinished else { return false }
        return !chess.isAIMatch
    }

    /// 사람과의 **테트리스** 대결이 지금 흐르고 있는가. 테트리스에는 AI 판이 없으므로 가를 것이 하나 적다
    /// (끝난 판은 판이 아니다 — 결과 카드가 떠 있는 동안 다른 게임 입구를 잠그면 안 된다).
    ///
    /// ★★ **`activeMatchID` 를 먼저 본다**(오목·체스와 같은 순서 — 씨앗 커밋에는 이 줄이 없었다). 서버가 말한
    ///   진행 판 id 는 **들고 있는 판이 없어도 참**이고, 그 틈이 테트리스에서는 1 왕복이 아니라 **열린 채로 남을
    ///   수 있다**: 로비 응답이 `active_match_id` 를 주면 코어가 곧바로 `refreshMatch(id:)` 를 쏘지만
    ///   (`applyLobby` 꼬리), 그 `tetris_state` 가 네트워크로 실패하면 `match` 는 영영 nil 인 채 id 만 남는다.
    ///   그 사이 오목·체스 입구가 열려 있고, 그 길로 오목을 수락하면 흐르던 테트리스 판은 15초 침묵으로
    ///   **판돈째 진다**(D5). 닫는 쪽으로 틀리는 것이 맞다 — 서버 `tetris__due` 가 480초 상한으로 어차피 닫으므로
    ///   id 가 영원히 남지 않는다(cron 매분).
    ///   값이 참이 되는 실제 경로 셋: ① 앱을 막 켜고 게임 탭 첫 화면(`hubDidAppear` → 로비) ② 화면 밖에서 active
    ///   복귀(P8 의 `systemDidWake()`) ③ 맥에서 시작한 판을 폰이 로비로 처음 알게 될 때(1.0.11 e2e 방향).
    package var hasLiveTetrisMatch: Bool {
        let tetris = context.tetris
        if tetris.activeMatchID != nil { return true }
        guard let match = tetris.match else { return false }
        return !match.isFinished
    }

    /// 체스 입구를 막는 까닭(없으면 nil). 오목·테트리스 판이 흐르면 체스를 신청·수락할 수 없다 —
    /// 서버도 같은 판정을 한다(`chess__busy`), 그래서 이 쪽은 **클라가 사실을 먼저 그리는 것**이다.
    package var chessEntryBlock: GamesBusyGame? {
        if hasLiveGomokuMatch { return .gomoku }
        return hasLiveTetrisMatch ? .tetris : nil
    }

    /// 오목 입구를 막는 까닭(없으면 nil). ★ **이 방향은 클라밖에 막는 데가 없다** — 서버의 오목 게이트는
    /// 체스·테트리스를 모른다(`GamesBusyGame` 머리말). 안 막으면 체스 중인 사람이 오목을 수락해 체스를 시간패한다.
    package var gomokuEntryBlock: GamesBusyGame? {
        if hasLiveChessMatch { return .chess }
        return hasLiveTetrisMatch ? .tetris : nil
    }

    /// 테트리스 입구를 막는 까닭(없으면 nil). 테트리스는 **판돈이 걸린 실시간 판**이라 막는 쪽이 더 무겁다 —
    /// 오목·체스 판을 두는 중에 테트리스를 수락하면 그 판은 15초 침묵으로 **진다**(서버 D5).
    package var tetrisEntryBlock: GamesBusyGame? {
        if hasLiveGomokuMatch { return .gomoku }
        return hasLiveChessMatch ? .chess : nil
    }

    /// **로봇 체스 판**이 지금 진행 중인가(끝난 판은 아니다).
    ///
    /// ★ 서버는 이 판을 **볼 수 없다.** `chess__busy`(duel.sql:1088)는 `chess_matches`·`gomoku_matches` 만 보고
    ///   로봇 판은 서버에 행이 없다. 그래서 한 사람 한 판이 이 축에서도 **한 방향만** 걸린다:
    ///   1:1 중 → 로봇 입구는 코어가 막지만(`canStartAIMatch`), **로봇 판 중 → 1:1 신청·수락은 그대로 나간다**
    ///   (`ChessStore.challenge` 에 `isAIMatch` 가드가 없다 — 로봇 레인이 요청 1건을 실측했다).
    ///   그러면 1:1 판이 서는 순간 `match` 관찰자가 로봇 판을 버려(`discardAIGame`) **문구도 확인도 없이
    ///   두던 판이 사라진다.** 걸린 루비가 0이라 손실은 없지만 **조용히 사라지는 것**이 결함이다.
    ///   그래서 이 레인이 두 길을 다 막는다: 신청은 게이트가(`GamesChessChallengeGate`·`GamesChessStakeSend`),
    ///   수락은 확인 시트가(화면 — "로봇 판을 끝내고 수락할까요?").
    package var hasLiveChessRobotGame: Bool {
        let chess = context.chess
        guard chess.isAIMatch, let match = chess.match, !match.isFinished else { return false }
        return true
    }

    // MARK: 첫 화면

    /// 게임 탭 첫 화면이 보였다: 카드의 오늘 최고·순위 · 받은 신청.
    package func hubDidAppear() {
        guard context.session.isSignedIn else { return }
        miniGames.refreshSummariesIfStale()
        context.gomoku.refreshInboxIfStale()
        // 체스는 **받은함 RPC 가 없다**(ChessStore 머리말 ⑪) — 받은 신청·진행 중 판·내 전적이 전부 `chess_lobby`
        // 의 `me` 로 온다. 그래서 허브에서 한 번 당긴다(30초 스로틀 — `menuLobbyThrottleSeconds`).
        // ★ 조회를 더하는 값은 **한 사람 한 판**이다: 이 조회가 없으면 앱을 막 켠 사람의 `activeMatchID` 가 nil 이라
        //   체스 판이 흐르는 중에도 오목 카드가 열려 있고, 그 길로 오목을 수락하면 체스가 시간패한다.
        context.chess.refreshLobbyIfStale()
        // 테트리스도 **받은함 RPC 가 없다**(P5) — 받은 신청·보낸 신청·진행 중 판 id·내 전적이 전부 `tetris_lobby`
        // 의 `me` 로 온다. 그래서 허브에서 한 번 당긴다(30초 스로틀 — `menuLobbyThrottleSeconds`).
        // ★ 이 조회가 없으면 **둘이 함께 죽는다**: ① 카드의 "받은 신청" 칩이 영영 비어 있다(폰에 전역 배너도
        //   탭 배지도 없으므로 받은 신청을 알 자리가 통째로 사라진다 — P5 의 알림 자리 ①), ② 앱을 막 켠 사람의
        //   `activeMatchID` 가 nil 이라 테트리스 판이 흐르는 중에도 오목·체스 카드가 열려 있고, 그 길로 수락하면
        //   테트리스가 15초 침묵으로 판돈째 진다(체스가 바로 위 줄을 둔 것과 **같은 근거**다).
        context.tetris.refreshLobbyIfStale()
    }

    /// 오목 카드의 한 줄 재료: 진행 중인 판이 있는가(서버가 말한 진행 판 id 또는 들고 있는 끝나지 않은 판).
    package var hasActiveGomokuMatch: Bool {
        let gomoku = context.gomoku
        if let match = gomoku.match, !match.isFinished { return true }
        return gomoku.activeMatchID != nil
    }

    /// 체스 카드의 한 줄 재료(위와 같은 뜻 — **로봇 판도 포함**이다. 카드가 '대국 중'을 앞세울지는
    /// `GamesTab` 이 `isAIMatch` 와 받은 신청을 함께 보아 정한다 — 오목 카드와 같은 관례).
    package var hasActiveChessMatch: Bool {
        let chess = context.chess
        if let match = chess.match, !match.isFinished { return true }
        return chess.activeMatchID != nil
    }

    /// 테트리스 카드의 한 줄 재료(위 둘과 같은 뜻). 지금은 `hasLiveTetrisMatch` 와 **같은 값**이다 —
    /// 테트리스에는 AI·로봇 판이 없어서 "사람과의 판"과 "진행 중인 판"이 갈리지 않는다.
    /// 그래도 **이름을 따로 둔다**: 저쪽은 *다른 게임 입구를 막는 판정*이고 이쪽은 *카드 한 줄의 재료*라,
    /// 로봇 판 같은 갈래가 생기는 날 둘이 갈려야 한다(체스에서 실제로 갈렸다 — 위 주석).
    package var hasActiveTetrisMatch: Bool {
        let tetris = context.tetris
        if let match = tetris.match, !match.isFinished { return true }
        return tetris.activeMatchID != nil
    }

    // MARK: 오목 화면 수명

    /// 오목 화면이 나타났다.
    package func gomokuScreenDidAppear() {
        let gomoku = context.gomoku
        // 먼저 적는다 — openWindow 가 presentWindow 를 부르고, 그 문이 "이미 보인다"를 봐야 화면을 또 열지 않는다.
        isGomokuScreenVisible = true
        let focus = pendingGomokuFocusID
        pendingGomokuFocusID = nil
        gomoku.openWindow(focusMatchID: focus)
        if isAppActive { gomoku.windowDidShow() }
        syncAIThinker()
    }

    /// 오목 화면이 사라졌다(뒤로 · 다른 탭으로 · 로그아웃). 폴링만 멈춘다. 결과 화면인 채로 떠나면 코어가 그 판에서 나간다.
    ///
    /// **관전은 여기서 끝낸다**(0.3.41 수리). 왜 틀렸었나: 코어 `windowDidHide` 는 **진행 중인** 관전을 일부러 남긴다
    /// (`GomokuStoreWatch` C14) — 맥에서 그 통지는 '창 최소화'라 지우면 최소화만 해도 로비로 떨어지기 때문이다.
    /// 그런데 폰에서 같은 통지는 "사용자가 화면을 떠났다"다. 관전 화면은 대국·결과 화면과 달리 탭 막대를 숨기지 않아
    /// 탭 이동·뒤로가 그대로 되고, 그렇게 떠난 뒤 게임 탭에서 오목을 다시 누르면 로비가 아니라 **남의 대국이 다시 열렸다**
    /// (예고도 없다 — 카드 문구의 `hasActiveGomokuMatch` 는 관전 중 false 다). 관전은 구경이니 탭을 옮기는 것이 곧
    /// "그만 볼게"다. 그래서 **폰 배선에서만** 끊는다(코어는 맥과 한 벌이라 그쪽을 고치면 맥의 최소화가 깨진다).
    ///
    /// `leaveWatch()` 가 **아니다**: 그쪽은 로비·받은함·순위를 다시 읽는 네트워크 호출이라 화면을 떠나는 길에서 조회 셋이 나간다.
    /// `stopWatching()` 은 세대만 올리고 장부를 비운다(요청 0건).
    ///
    /// 머리 문장의 함정과 어긋나지 않는다: **내 판**은 여기서 손대지 않는다 — 결과 화면인 채로 떠나면 코어가 그 판에서
    /// 나가고(`gomoku_leave`), **진행 중인 내 판은 남는다**(끊으면 떠나 있는 사이 대국이 죽는다). 관전만 결과·진행 구분 없이 끝난다.
    ///
    /// ★★ **`windowDidClose()` 가 마지막이다**(0.3.50 수리의 폰 몫 · 2026-10-13 신고). 폰에서 화면을 떠나는 것은
    ///   맥의 '최소화'가 아니라 **'창을 정말 닫았다'**다 — 탭을 옮기면 화면이 통째로 내려가고 다음 진입은 처음부터다.
    ///   그런데 `windowDidHide()` 만 부르면 코어는 서버에 "그 판에서 나갔다"고 말하면서(`gomoku_leave`) **화면은 끝난 판을
    ///   그대로 들고 있어**, 오목을 다시 누를 때 로비가 아니라 **그 결과 화면이 다시 섰다**([로비로] 를 눌러야만 빠져나왔다).
    ///   `windowDidClose()` 가 그 끝난 판을 접는다(`foldFinishedMatch`).
    /// ★ **진행 중인 내 판은 그대로 남는다** — 가드는 코어 안에 있다(`GomokuStore.windowDidClose` 의
    ///   `if match?.isFinished == true`, 그 안의 `foldFinishedMatch` 도 `isFinished` 를 다시 본다. AI 판도 같다 —
    ///   `backToLobbyFromAIMatch` 가 `game.isFinished` 를 먼저 본다). 그래서 폰에서 따로 가를 것이 없다.
    /// ★ **순서는 맥과 같다**: 맥 창 배선도 `notifyVisibility(false)` → `notifyClosed()`,
    ///   즉 `windowDidHide()` 뒤에 `windowDidClose()` 다(`CheckGomokuWindow.windowWillClose`). 뒤집으면 접힌 뒤의
    ///   `windowDidHide` 가 빈 판을 보게 되는데, 그러면 "끝난 판에서 나간다"(`gomoku_leave`)를 부르는 자리가
    ///   `foldFinishedMatch` 안쪽 하나로 줄어 조용히 갈래가 바뀐다.
    /// ★ **요청은 늘지 않는다.** `windowDidClose()` 는 조회를 쏘지 않고(로비·받은함은 다음 `openWindow` 가 읽는다),
    ///   겹치는 `stopWatching()`·`leaveMatch` 는 멱등이다(`leftMatchIDs` 가 판마다 한 번으로 묶는다).
    package func gomokuScreenDidDisappear() {
        guard isGomokuScreenVisible else { return }
        isGomokuScreenVisible = false
        // 관전을 먼저 내린다(요청 없음). 뒤의 `windowDidHide` 는 **끝난** 관전만 내리므로 진행 중인 남의 판이 그대로 남았다.
        context.gomoku.stopWatching()
        context.gomoku.windowDidHide()
        // 폰에서 '떠남'은 맥의 '닫기'다 — 끝난 판을 접는 자리는 이 문뿐이다(진행 중인 판은 코어가 가른다).
        context.gomoku.windowDidClose()
        syncAIThinker()
    }

    // MARK: 체스 화면 수명 (오목에서 수리한 모양 그대로)

    /// 체스 화면이 나타났다: 로비·진행 판을 읽고(`openWindow`) 앱이 active 면 창을 세운다(`windowDidShow`).
    ///
    /// `isChessScreenVisible` 을 **먼저** 적는다 — `openWindow` 가 `presentWindow` 를 부르고, 그 문이
    /// "이미 보인다"를 봐야 화면을 또 열지 않는다(오목에서 같은 순서로 데였다).
    ///
    /// ★★ **`windowDidShow()` 가 이 레인의 두 번째 주 스위치다.** 코어 `isWindowVisible` 도 기본이 false 이고
    ///   (`ChessStore.swift:723`), 그 깃발을 켜는 문은 이것뿐이다. 깃발이 꺼져 있으면 셋이 함께 죽는다:
    ///   폴링(`startPolling` 의 가드) · 순위·관전(`canPollSpectatorFeatures`) · **말 이동 애니메이션**
    ///   (`beginFlight` 가 맨 앞에서 `guard isWindowVisible, !isWindowOccluded`). 애니메이션이 안 만들어지면
    ///   판은 멈춘 국면을 **정확히** 그리므로 사용자에게는 말이 순간이동하고, 거절이 의도된 동작이라
    ///   **빨개지는 테스트가 없다**. 그래서 못을 따로 박아 두었다 — `GamesChessWiringTests` 의
    ///   `theScreenHookMakesTheMoveAnimation`(깃발이 아니라 **그 결과로 애니메이션이 서는지**를 재고,
    ///   화면 훅을 안 부른 기준선과 나란히 본다).
    /// ★ `focusMatchID` 는 **데모 라우트의 꼬리**다(`games/chess/match/<id>`). 사람이 쓰는 길에서는 nil 이다 —
    ///   코어가 로비 `me.active_match_id` 로 내 판을 스스로 연다. 꼬리가 붙은 데모 라우트는 장면 폴더가 없어
    ///   바깥 층 로비(진행 판 없음)로 떨어지므로, 그 꼬리를 **코어가 이미 가진 문**으로 흘려 넣는다
    ///   (오목이 `pendingGomokuFocusID` 를 `gomoku.openWindow(focusMatchID:)` 에 넣는 것과 같은 선례).
    package func chessScreenDidAppear() {
        let chess = context.chess
        isChessScreenVisible = true
        // 두 갈래는 **같은 동작**이다: `demoChessRoute` 는 DEBUG 전용 값이고(출시 게이트 — 머리말 참조)
        // Release 에서는 원래부터 영원히 nil 이었다. 사람이 쓰는 길에서 꼬리는 한 번도 서지 않는다 —
        // 코어가 로비 `me.active_match_id` 로 내 판을 스스로 연다.
        #if DEBUG
        chess.openWindow(focusMatchID: demoChessRoute?.focusMatchID)
        #else
        chess.openWindow(focusMatchID: nil)
        #endif
        if isAppActive { chess.windowDidShow() }
        startDemoChessWatchIfNeeded()
    }

    /// 데모 전용: 라우트 꼬리가 관전(`games/chess/watch/<id>`)이면 **[관전] 칩을 누른 것과 같은 자리**를 직접 건다.
    ///
    /// 왜 데모 전용 길이 필요한가: 스크린샷은 `simctl` 헤드리스라 **합성 탭이 없다**(작업 규칙 §0-1) — 칩을 누를
    /// 사람이 없으면 관전 화면에 닿는 길이 아예 없다. 부르는 자리는 칩과 **똑같이** `startWatching(matchID:)` 이다
    /// (코어 게이트 — 주 스위치·세션·`phase == .lobby`·잠금 — 를 하나도 우회하지 않는다).
    ///
    /// 로비 응답을 **먼저 기다린다**: `liveMatches` 가 두 얼굴을 싣고 `startWatching` 이 그것을 씨앗으로 쓴다
    /// (못 기다리면 얼굴 없는 로딩 상태로 들어가고 응답이 뒤늦게 채운다 — 스크린샷에는 그 틈이 그대로 찍힌다).
    ///
    /// Release 에는 **본문이 없다**(`demoChessRoute` 가 DEBUG 전용 — 출시 게이트). 그 구성에서도 값이 늘 nil 이라
    /// 첫 guard 에서 돌아섰으므로 동작은 같다. `GamesTab.applyDemoSeed` · `MobileAppModel.demoOnlyRoute` 와 같은 모양이다.
    private func startDemoChessWatchIfNeeded() {
        #if DEBUG
        guard let id = demoChessRoute?.watchMatchID else { return }
        Task { [weak self] in
            for _ in 0..<60 {
                guard let self, self.isChessScreenVisible else { return }
                if self.context.chess.liveMatches.contains(where: { $0.id == id }) { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let self, self.isChessScreenVisible else { return }
            self.context.chess.startWatching(matchID: id)
        }
        #endif
    }

    /// 체스 화면이 사라졌다(뒤로 · 다른 탭으로 · 로그아웃).
    ///
    /// **`stopWatching()` 이 먼저, `windowDidHide()` 가 나중이다.** 코어 `windowDidHide` 는 **끝난** 관전만 내리고
    /// **진행 중인** 관전은 일부러 남긴다 — 맥에서 그 통지는 '창 최소화'라 지우면 최소화만 해도 남의 판 관전이
    /// 로비로 떨어지기 때문이다. 폰에서 같은 통지는 "사용자가 화면을 떠났다"다. 순서를 뒤집거나 `stopWatching()`
    /// 을 빼면 게임 탭에서 체스를 다시 누를 때 로비가 아니라 **남의 대국이 다시 열린다**(오목 0.3.41 수리와 같은 자리).
    ///
    /// `leaveWatch()` 가 **아니다**: 그쪽은 로비·순위를 다시 읽는 **네트워크 호출**이라 화면을 떠나는 길에서
    /// 조회 둘이 나간다. `stopWatching()` 은 세대만 올리고 장부를 비운다(요청 0건).
    ///
    /// **진행 중인 내 판은 손대지 않는다.** 체스에는 `chess_leave` 가 없고(코어 `windowDidClose` 주석) 진행 중인 판은
    /// 서버에서 계속 흐른다 — 떠나는 것은 기권이 아니다.
    ///
    /// ★★ **`windowDidClose()` 가 마지막이다**(0.3.50 수리의 폰 몫 · 2026-10-13 신고 — 오목과 같은 결함이었다).
    ///   폰에서 화면을 떠나는 것은 맥의 '최소화'가 아니라 **'창을 정말 닫았다'**다. `windowDidHide()` 만으로는
    ///   **끝난 내 판이 그대로 남아**, 게임 탭에서 체스를 다시 누를 때 로비가 아니라 **그 결과 화면이 다시 섰다**
    ///   ([로비로] 를 눌러야만 빠져나왔다). `windowDidClose()` 가 그 판을 접는다(`foldFinishedMatch`).
    /// ★ **진행 중인 판을 가르는 가드는 코어 안에 있다** — 체스 `foldFinishedMatch()` 의 첫 줄이
    ///   `guard let current = match, current.isFinished else { return false }` 다(직접 확인했다 ·
    ///   `ChessStore.swift:1817`). 그래서 폰 배선에서 따로 가를 것이 없다. AI 판도 같은 가드를 지난다.
    /// ★ **순서는 맥과 같다**: 맥 창 배선도 `notifyVisibility(false)` → `notifyClosed()`,
    ///   즉 `windowDidHide()` 뒤에 `windowDidClose()` 다(`CheckChessWindow.windowWillClose`).
    /// ★ **겹치는 일은 해롭지 않다.** `windowDidClose()` 도 `clearFlight`·`cancelDrag`·`clearPendingDrop` 을
    ///   부르는데 셋 다 nil 가드가 달린 멱등 함수다(`ChessStore.swift:1305·1534·1613`) — 두 번 불러도
    ///   거둘 것이 없으면 아무 일도 안 한다. 요청도 늘지 않는다(체스에는 `chess_leave` 가 없고 이 문은 조회를 안 쏜다).
    package func chessScreenDidDisappear() {
        guard isChessScreenVisible else { return }
        isChessScreenVisible = false
        context.chess.stopWatching()
        context.chess.windowDidHide()
        // 폰에서 '떠남'은 맥의 '닫기'다 — 끝난 판을 접는 자리는 이 문뿐이다(진행 중인 판은 코어가 가른다).
        context.chess.windowDidClose()
    }

    // MARK: 테트리스 화면 수명 (오목·체스에서 수리한 모양 그대로 · 관전만 없다)

    /// 1:1 테트리스 화면이 나타났다: 로비·진행 판을 읽고(`openWindow`) 앱이 active 면 창을 세운다(`windowDidShow`).
    ///
    /// `isTetrisScreenVisible` 을 **먼저** 적는다 — `openWindow` 가 `presentWindow` 를 부르고, 그 문이
    /// "이미 보인다"를 봐야 화면을 또 열지 않는다(체스 주석의 그 순서 · 오목에서 같은 순서로 데였다).
    ///
    /// ★★ **`windowDidShow()` 가 이 레인의 주 스위치다.** 코어 `isWindowVisible` 도 기본이 false 이고
    ///   (`TetrisDuelStore.swift:484`), 그 깃발을 켜는 문은 이것뿐이다. 꺼져 있으면 셋이 함께 죽는다:
    ///   폴링(`startPolling` 의 가드) · 순위·로비 재조회(`windowDidShow` 의 두 분기) · 그리고 가장 무거운 것 —
    ///   **준비 보고의 문**(코어 머리말 ⑨: "준비 = 첫 보고. 창이 화면에 떠 있을 때만 낸다"). 준비를 못 내면
    ///   서버는 30초 뒤 `no_show` 무승부로 판돈을 돌려주는데(D4), 사용자 눈에는 **수락했는데 아무 일도 안 일어난
    ///   화면**이 30초 서 있다. 되돌려도 빨개지는 테스트가 없게 두지 마라 — 못은
    ///   `GamesTetrisDuelWiringTests.theScreenHookOpensTheReadyReport`(깃발이 아니라 **그 결과로 보고가 나가는지**를
    ///   재고, 훅을 안 부른 기준선과 나란히 본다).
    /// ★ `focusMatchID` 는 **데모 라우트의 꼬리**다(`games/tetris/match/<장면>`). 사람이 쓰는 길에서는 nil 이다 —
    ///   코어가 로비 `me.active_match_id` 로 내 판을 스스로 연다. 두 갈래는 **같은 동작**이다:
    ///   `demoTetrisRoute` 는 DEBUG 전용 값이고 Release 에서는 원래부터 영원히 nil 이었다.
    ///   (장면 폴더의 로비 픽스처가 `me.active_match_id` 로도 같은 판을 가리키므로 두 길이 겹치지만 멱등이다 —
    ///   `refreshMatch` 가 도는 중이면 뒤따르는 한 번으로 합친다. 까닭은 `MobileDemoTetrisRoute` 머리말 2.)
    package func tetrisScreenDidAppear() {
        let tetris = context.tetris
        isTetrisScreenVisible = true
        #if DEBUG
        tetris.openWindow(focusMatchID: demoTetrisRoute?.focusMatchID)
        #else
        tetris.openWindow(focusMatchID: nil)
        #endif
        if isAppActive { tetris.windowDidShow() }
    }

    /// 테트리스 화면이 사라졌다(뒤로 · 다른 탭으로 · 로그아웃).
    ///
    /// **기권이 아니다.** 테트리스에는 `tetris_leave` 가 없고 진행 중인 판은 서버에서 계속 흐른다 — 조각은 단조
    /// 시계로 계속 떨어지고(D10) 보고도 계속 나간다. 떠나는 길에서 **요청은 한 건도 나가지 않는다**
    /// (`tetris_resign` 은 화면이 확인을 받은 뒤에만 나간다 — 레인 C).
    ///
    /// ★★ **`windowDidClose()` 가 마지막이다**(오목 0.3.41·0.3.50 과 체스에서 두 번 데인 자리의 폰 몫).
    ///   폰에서 화면을 떠나는 것은 맥의 '최소화'가 아니라 **'창을 정말 닫았다'**다 — 탭을 옮기면 화면이 통째로
    ///   내려가고 다음 진입은 처음부터다. `windowDidHide()` 만 부르면 **끝난 판이 그대로 남아**, 게임 탭에서
    ///   테트리스를 다시 누를 때 로비가 아니라 **그 결과 카드가 다시 선다**([로비로]를 눌러야만 빠져나온다).
    ///   `windowDidClose()` 가 그 판을 접는다(`foldFinishedMatch`).
    /// ★ **진행 중인 내 판은 그대로 남는다** — 가드는 코어 안에 있다(`TetrisDuelStore.foldFinishedMatch` 첫 줄이
    ///   `guard let current = match, current.isFinished else { return false }` 다 · 직접 확인했다). 그래서 폰
    ///   배선에서 따로 가를 것이 없다.
    /// ★ **순서는 맥과 같다**: 맥 창 배선도 숨김 → 닫힘이다. 뒤집으면 접힌 뒤의 `windowDidHide` 가 빈 판을 본다.
    /// ★ **겹치는 일은 해롭지 않다.** 둘 다 `releaseAllKeys()` 를 부르는데 멱등이고(놓을 키가 없으면 아무 일도
    ///   안 한다), 조회도 쏘지 않는다. SwiftUI 가 `onDisappear` 를 겹쳐 불러도 맨 앞 guard 가 돌아선다.
    /// ★ 관전은 **없다**(D8 — 이번 범위에서 뺐다). 그래서 체스의 `stopWatching()` 자리가 비어 있다.
    package func tetrisScreenDidDisappear() {
        guard isTetrisScreenVisible else { return }
        isTetrisScreenVisible = false
        context.tetris.windowDidHide()
        // 폰에서 '떠남'은 맥의 '닫기'다 — 끝난 판을 접는 자리는 이 문뿐이다(진행 중인 판은 코어가 가른다).
        context.tetris.windowDidClose()
    }

    /// AI 선택기의 허락 = 오목 화면이 보이고 앱이 active. 거두면 도는 탐색이 곧바로 취소된다.
    private func syncAIThinker() {
        aiThinker.setAllowed(isGomokuScreenVisible && isAppActive)
    }

    /// 대국 중이라 화면이 꺼지면 안 된다(`UIApplication.isIdleTimerDisabled`, SPEC-ios §3.5). 앱이 active 이고 끝나지 않은 판이 있을 때.
    /// **어느 화면에 있든 같다**(오목 화면 밖 — 게임 첫 화면 · 다른 탭 — 에서도 판이 도는 동안은 켠다).
    ///
    /// AI 판만 예외: 오목 화면이 보일 때만 켠다. 화면을 떠나면 사람 시계가 멈추고 AI 도 생각하지 않는다 — 기다릴 것이 없는데
    /// 다른 탭에서 화면을 켜 둘 까닭이 없다(1:1 은 서버 시계가 흐르므로 그대로다).
    package var wantsIdleTimerDisabled: Bool {
        guard isAppActive, context.session.isSignedIn else { return false }
        // 미니게임: 끝나지 않은 판이 있으면 켠다. **지금까지 미니게임은 아예 보호받지 않았다** — 플래피는 한 판이
        // 30초 남짓이라 자동잠금(최소 30초)에 닿을 일이 없어 드러나지 않았을 뿐이다. 폰은 background 가 곧
        // **판 폐기·무제출**(`GamesMiniGameHub.appDidEnterBackground`)이라 자동잠금이 곧 판 폐기이고, 조각을 세워 두고
        // 생각하는 무입력 구간이 있는 게임(테트리스)이 들어오면 그 구멍이 바로 열린다.
        //
        // ★ **타이밍 바만 뺀다.** 그 판은 **스스로 끝나지 않는다** — `phase` 가 탭을 받을 때까지 `.running` 에 머문다
        // (`TimingBarGame.isPlaying`). 그래서 판을 켜 둔 채 자리를 뜨면 화면이 **영원히** 켜져 있다. 자동잠금이 그
        // 유일한 상한이었고, 여기에 타이밍 바를 넣으면 그 상한이 사라진다. 플래피(새가 떨어져 끝난다)와 테트리스
        // (쌓여서 탑아웃한다)는 방치해도 엔진이 판을 끝내므로 안전하다. 새 게임을 더할 때 이 성질을 확인할 것.
        if let controller = miniGames.controller, controller.isPlaying, controller.kind != .timingBar { return true }
        // 체스: 오목과 **같은 규칙**이다. 1:1 판은 서버 시계가 흐르므로 어느 화면에 있든 켜고(10분 시계에
        // 자동잠금이 닿으면 한 수도 못 두고 시간패한다), 로봇 판은 체스 화면이 보일 때만 켠다
        // (화면을 떠나면 코어가 시계를 멈춘다 — `pauseAIClock`).
        if let match = context.chess.match, !match.isFinished {
            if context.chess.isAIMatch {
                if isChessScreenVisible { return true }
            } else {
                return true
            }
        }
        // 테트리스: **어느 화면에 있든 켠다**(1:1 뿐이라 로봇 예외가 없다). 다른 게임보다 결과가 무겁다 —
        // 자동잠금(최소 30초)이 닿으면 iOS 가 판 루프 Task 를 재우고, 서버는 15초 침묵에 **내 패**로 닫는다
        // (D5 — 판돈을 잃는다). 체스는 시계가 떨어지는 데 10분이 걸리지만 테트리스는 **15초**다.
        // ★ `hasLiveTetrisMatch` 가 아니라 들고 있는 판을 본다: 서버가 말한 id(`activeMatchID`)만 알고 판을
        //   아직 못 읽은 상태에서 화면을 8분까지 켜 두면, 테트리스를 보고 있지도 않은 사람의 배터리를 태운다
        //   (체스도 `context.chess.match` 를 본다 — 같은 선례).
        if let match = context.tetris.match, !match.isFinished { return true }
        guard let match = context.gomoku.match else { return false }
        if context.gomoku.isAIMatch { return !match.isFinished && isGomokuScreenVisible }
        return !match.isFinished
    }

    // MARK: 화면 꺼짐 방지(주인은 이 스토어 하나)

    /// 화면 꺼짐 방지 싱크를 단다(첫 한 번만 — 뒤의 호출은 무시). 이후 `wantsIdleTimerDisabled` 가 바뀔 때마다 이 스토어가 넘긴다.
    /// iOS 는 init 이 시스템 대입(`GamesSystemIdleTimer`)을 단다. macOS 테스트는 기록용 싱크를 단다.
    ///
    /// 예전에는 오목 화면(onDisappear 에서 무조건 false · onChange)과 게임 첫 화면(onChange)이 제각각 썼다. 대국 중 [뒤로]로
    /// 오목 화면을 떠나면 false 가 써지고, 첫 화면의 onChange 는 값이 안 바뀌어 다시 쓰지 않아, 같은 상태인데 이동 경로에 따라
    /// 값이 달랐다(games-verify probe-back). 이제 어느 뷰도 이 값을 쓰지 않는다.
    package func installIdleTimerSink(_ sink: @escaping @MainActor (Bool) -> Void) {
        guard idleTimerSink == nil else { return }
        idleTimerSink = sink
        syncIdleTimer()
    }

    /// 지금 값을 싱크에 넘기고, 재료(앱 active · 로그인 · 판)가 바뀌면 다시 불리도록 관찰을 건다(한 줄로 이어지는 관찰 하나).
    private func syncIdleTimer() {
        guard let sink = idleTimerSink else { return }
        let wants = withObservationTracking {
            wantsIdleTimerDisabled
        } onChange: { [weak self] in
            // willSet 에서 불린다 — 값이 실제로 바뀐 뒤에 읽도록 다음 차례로 미룬다.
            Task { @MainActor [weak self] in self?.syncIdleTimer() }
        }
        guard appliedIdleTimerDisabled != wants else { return }
        appliedIdleTimerDisabled = wants
        sink(wants)
    }

    // MARK: 딥링크

    /// 게임 탭이 꺼낸 딥링크(`router.consumePendingRoute(for: .games)`)를 경로 동작으로 바꾼다. 게임 탭 밖 라우트면 nil.
    ///
    /// 오목 라우트에서 **오목 화면이 이미 보이면** 대상 id 를 코어에 바로 넘긴다(`openWindow(focusMatchID:)`). 라우터가 경로를
    /// [오목] → [] → [오목] 으로 한 번에 바꾸면 SwiftUI 는 같은 화면으로 보아 onDisappear/onAppear 를 부르지 않으므로,
    /// `gomokuScreenDidAppear` 에 기대면 대상이 적용되지 않고 남아 나중의 무관한 진입에 쓰였다(games-verify probe-focus).
    /// 경로는 그래도 다시 쌓는다 — 라우터가 비운 경로를 되돌려야 화면이 닫히지 않는다.
    ///
    /// ★★ **1:1 테트리스 가지는 여기 없다 — 그것이 결정이다**(1.0.11 레인 A). 셋을 확인하고 그렇게 두었다.
    ///   ① `games/tetris` 는 **이미 임자가 있다**: `AingRoute.parse` 의 `("games", 1)` 가지가 그 글자를
    ///      `.miniGame(.tetris)` 로 읽고(= **솔로** 테트리스, v0.3.38 에 나간 링크), 바로 아래 `case .miniGame`
    ///      이 솔로 화면을 쌓는다. 여기에 대결을 끼우면 **이미 나간 솔로 딥링크의 뜻이 바뀐다.**
    ///   ② 그래서 대결 라우트는 `AingRoute` 에 **새 글자**가 필요한데, 그 열거는 `CheckMobileShared` 에 있고
    ///      가지를 더하는 순간 `IntegrationContractTests` 의 '장면 폴더 예외'가 자기 만료 단언으로 빨개진다
    ///      (픽스처 레인이 설계한 신호 — `MobileAppModel.openDemoRouteIfNeeded` 주석). 이 레인의 파일이 아니다.
    ///   ③ **1.0.11 에 그 라우트를 쓸 소비자가 없다**: 푸시(`tetris_invite`)는 서버 몫이고 범위 밖이며(D8),
    ///      위젯에도 테트리스가 없다. 화면을 여는 길은 둘 다 이미 있다 — 게임 탭 카드(레인 B)와
    ///      코어가 부르는 `presentTetrisScreen()`(수락·시작). 데모 장면 라우트(`games/tetris/…`)는 **레인 D** 가
    ///      `AingRoute` 밖에서 체스와 같은 꼴로 푼다.
    ///   푸시·위젯이 대결을 열어야 하는 날 할 일: `AingRoute` 에 **`games/tetris` 가 아닌** 글자로 가지를 더하고
    ///   (예: `tetris/match[/<id>]` — 오목이 `gomoku/…` 를 쓰는 꼴), 여기 `tetrisEntryBlock` 가드를 지나는 가지를
    ///   더하고, `presentTetrisScreen()` 을 그 쪽으로 옮긴다(체스 주석이 같은 말을 한다).
    package func routeStep(for route: AingRoute) -> GamesRouteStep? {
        switch route {
        case .games:
            return .popToRoot
        case .miniGame(let game):
            // ⚠️ **빠짐없는 switch 여야 한다.** 예전에는 `game == .timing ? .timingBar : .flappy` 였는데,
            // 그러면 `AingRoute.MiniGame` 에 값이 하나 늘 때 **경고 없이 플래피로 오배달**된다(기본값 가지가
            // 모르는 값을 삼킨다). switch 로 두면 그 순간 여기가 컴파일 에러로 막는다 —
            // 저장소 메모 '열거값 확장엔 능력 협상'과 같은 자리다. `default:` 를 넣지 마라.
            let kind: MiniGameKind
            switch game {
            case .timing: kind = .timingBar
            case .flappy: kind = .flappy
            case .tetris: kind = .tetris
            }
            return .push(.miniGame(kind))
        case .gomokuLobby, .gomokuMatch(matchID: nil):
            guard gomokuEntryBlock == nil else { return blockedGomokuRoute() }
            openGomoku(focusID: nil)
            return .push(.gomoku)
        case .gomokuInvite(let id), .gomokuMatch(matchID: .some(let id)):
            guard gomokuEntryBlock == nil else { return blockedGomokuRoute() }
            openGomoku(focusID: id)
            return .push(.gomoku)
        default:
            return nil
        }
    }

    /// 체스·**테트리스** 판이 흐르는 동안 들어온 오목 링크(푸시·위젯)를 **열지 않는다** — 게임 탭 첫 화면에 세운다.
    ///
    /// 카드만 막으면 이 길이 남는다: 오목 로비의 [수락]은 `GomokuPhoneChallengeGate`(보낸 신청용)를 지나지 않아
    /// 아무 게이트도 없고, 서버의 오목 쪽 게이트는 체스·테트리스를 모른다(`GamesBusyGame` 머리말). 그래서 **화면까지
    /// 가지 않는 것**이 지금 폰이 그 수락을 막는 유일한 방법이다. 첫 화면에서는 오목 카드가 그 까닭을 말한다.
    ///
    /// ★ 부르는 자리의 가드는 `gomokuEntryBlock` 하나다 — 그 값이 **세 방향 가운데 둘**(체스·테트리스)을 이미
    ///   함께 보므로 이 길에 조건을 더 적지 않는다. 두 곳에 적으면 한 곳만 넓히는 날 조용히 갈린다.
    ///   테트리스 판 중에 오목 링크가 막히는지는 `GamesTetrisDuelWiringTests` 가 값으로 잰다.
    private func blockedGomokuRoute() -> GamesRouteStep {
        pendingGomokuFocusID = nil
        return .popToRoot
    }

    private func openGomoku(focusID: String?) {
        guard isGomokuScreenVisible else {
            // 화면이 곧 나타난다(push) — 나타날 때 꺼내 쓴다.
            pendingGomokuFocusID = focusID
            return
        }
        pendingGomokuFocusID = nil
        context.gomoku.openWindow(focusMatchID: focusID)
    }

    private func presentGomokuScreen() {
        guard isAppActive, context.session.isSignedIn, !isGomokuScreenVisible else { return }
        context.router.open(.gomokuMatch(matchID: nil))
    }

    /// 체스 판이 막 열렸다(내 신청이 수락됨 · 내가 수락함 · 앱을 다시 켜니 진행 중인 판) — 체스 화면을 연다.
    ///
    /// `AingRoute` 에 체스 링크가 **아직 없다**(CheckMobileShared — 이 작업의 소유 파일 밖이다). 그래서 라우터의
    /// 조각 셋으로 같은 일을 한다: 게임 탭을 고르고 · 쌓인 화면을 비우고 · 체스를 쌓는다(`router.open` 이 하는 일과 같다).
    /// 푸시·위젯이 체스를 열려면 그때 `AingRoute` 에 가지를 더하고 이 함수를 `routeStep` 쪽으로 옮겨야 한다.
    private func presentChessScreen() {
        guard isAppActive, context.session.isSignedIn, !isChessScreenVisible else { return }
        let router = context.router
        router.selectedTab = .games
        router.popToRoot(.games)
        router.push(GamesDestination.chess, on: .games)
    }

    /// 테트리스 판이 막 열렸다(내 신청이 수락됨 · 내가 수락함 · 앱을 다시 켜니 진행 중인 판) — 테트리스 화면을 연다.
    ///
    /// 체스와 **같은 조각 셋**으로 같은 일을 한다(`AingRoute` 에 테트리스 대결 가지가 없다 — 아래 `routeStep` 주석):
    /// 게임 탭을 고르고 · 쌓인 화면을 비우고 · 테트리스를 쌓는다.
    ///
    /// ★ 이 문이 **없으면 수락이 화면을 못 연다.** 체스에서 맥이 그 결함으로 판돈 걸린 판을 조용히 시간패했고,
    ///   테트리스는 더 짧다: 수락 뒤 30초 안에 준비 보고를 못 내면 `no_show` 무승부이고(D4), 준비는 **창이
    ///   보일 때만** 나간다(코어 머리말 ⑨). 즉 화면이 안 열리면 수락한 판이 통째로 흘러간다.
    /// ★ `!isTetrisScreenVisible` 가드가 **화면을 두 번 쌓는 것**을 막는다 — `tetrisScreenDidAppear` 가 깃발을
    ///   먼저 적는 까닭이 이것이다(그 안의 `openWindow` 가 이 문을 부른다).
    private func presentTetrisScreen() {
        guard isAppActive, context.session.isSignedIn, !isTetrisScreenVisible else { return }
        let router = context.router
        router.selectedTab = .games
        router.popToRoot(.games)
        router.push(GamesDestination.tetrisDuel, on: .games)
    }
}

/// 체스 로비 [도전] 활성 조건 — 맥 `ChessOpponentRow.canChallenge`(`user.isCapable && !user.inMatch && !isBusy`)에
/// **폰에서 셋을 더한** 것이다: 보낸 신청 · 내 판 · **다른 게임의 판**(한 사람 한 판, 양방향).
///
/// ★ 왜 뷰 파일이 아니라 여기 있나: 체스 화면은 통째로 `#if os(iOS)` 안이라 **맥 스위트가 한 줄도 못 본다**
///   (저장소 메모 '폰 뷰는 맥 스위트가 못 본다'). 게이트를 뷰에 적으면 되돌려도 빨개지는 테스트가 없다.
///   이 파일은 플랫폼 분기가 없어 `GamesChessWiringTests` 가 값으로 잰다.
///
/// ★ `user.isCapable` 은 `capable` 이 **nil 이면 false** 다(`ChessStore.user(from:)` — `ChessWire.swift:118` 의 계약).
///   모르는 상대에게 신청해 `target_outdated` 를 받는 것보다, 모르면 막는 것이 낫다.
package enum GamesChessChallengeGate {
    @MainActor
    package static func isEnabled(user: ChessUser, store: ChessStore, blockedBy other: GamesBusyGame?) -> Bool {
        other == nil
            && user.isCapable
            && !user.inMatch
            && store.outgoing == nil
            // ★ `match == nil` 이 **로봇 판까지** 막는 자리다(`GamesStore.hasLiveChessRobotGame` 머리말) —
            //   코어 `challenge` 에는 `isAIMatch` 가드가 없어 여기를 열면 요청이 그대로 나가고,
            //   1:1 판이 서는 순간 두던 로봇 판이 말없이 사라진다. `isAIMatch` 를 예외로 빼지 마라.
            && store.match == nil
            && !store.isBusy
    }
}

/// 판돈 시트의 [도전하기] 가 **실제로 요청을 낼 수 있는가**(낼 수 있으면 그 판돈, 못 내면 nil).
///
/// ★ 왜 뷰가 아니라 여기 있나: 신청이 나가는 **마지막 문**이라 "버튼이 비활성"이 아니라 **요청 0건**을 재야 하고
///   (들어오는 다른 경로가 생기면 버튼 단언은 못 잡는다), 뷰는 `#if os(iOS)` 안이라 맥 스위트가 못 본다.
///   `GamesChessWiringTests` 가 세 판돈 전부에서 nil 인 것을 값으로 잰다.
package enum GamesChessStakeSend {
    @MainActor
    package static func sendable(
        _ selected: ChessStake?, store: ChessStore, balance: Int?, blockedBy other: GamesBusyGame?
    ) -> ChessStake? {
        guard let selected,
              GamesChessStakeSelection.affordable(selected, balance: balance),
              !store.isBusy,
              other == nil,
              // 내 판(1:1·**로봇** 둘 다) · 보낸 신청이 있으면 낼 수 없다. 버튼 게이트와 같은 조건을 두 번
              // 적는 것이 아니라, 게이트가 열린 뒤 상태가 바뀐 틈(시트가 떠 있는 동안 로봇 판을 시작했다)을 막는다.
              store.match == nil,
              store.outgoing == nil
        else { return nil }
        return selected
    }
}

/// 판돈 고르기(맥 `ChessStakePrompt` 와 같은 규약 — 고른 판돈을 다시 누르면 해제 · 잔액을 **모르면 막지 않는다**).
/// 오목의 `GomokuPhoneStakeSelection` 과 같은 자리·같은 뜻이고, 체스 판돈 표(3·5·10)는 서버 CHECK 가 쥔다.
package enum GamesChessStakeSelection {
    package static func toggled(current: ChessStake?, tapped: ChessStake) -> ChessStake? {
        current == tapped ? nil : tapped
    }

    /// 이 판돈을 걸 수 있는가. **잔액을 모르면(nil) 막지 않는다**(맥 0.3.29 규칙 — 서버가 거절하면 그때 안내한다).
    package static func affordable(_ stake: ChessStake, balance: Int?) -> Bool {
        guard let balance else { return true }
        return balance >= stake.rawValue
    }
}
