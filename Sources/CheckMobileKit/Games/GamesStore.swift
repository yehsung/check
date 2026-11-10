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
    /// 아잉 큐브(1.0.16) — 로비·방·판·결과·순위를 **입구 하나**로 연다(화면이 `phase` 로 갈아 끼운다).
    case rummy
    /// 아잉 뒤집기(1.0.17) — 로비·판·AI 연습·결과·관전·순위를 **입구 하나**로 연다(체스와 같은 구조 — 화면이 `phase` 로 갈아 끼운다).
    case reversi
    /// 1:1 길건너(폰 1.0.18).
    case crossyDuel
    /// 1:1 알까기(폰 1.0.18) — 로비 · 판 · 결과 · 관전 · 순위 · 연습을 **입구 하나**로 연다(화면이 판 유무로 갈아 끼운다).
    case alkkagi
}

/// 지금 **사람과의** 판을 들고 있는 게임 — 한 사람 한 판(B8)의 까닭을 화면이 말할 수 있게 하는 값.
///
/// 서버도 같은 판정으로 막는다: 오목 신청·수락(`gomoku_challenge` · `gomoku_respond`)도 체스·테트리스처럼 `chess__busy` 를
/// 부르고(20261005160000 §7A.1 부터), 그 함수는 지금 `game__busy_users()`(20261107140000 — 체스·오목·테트리스 active ·
/// 아잉 큐브 joined·playing · 아잉 뒤집기 active, 새 게임은 그 한 곳에 더한다)를 감싼다. 그래서 막힌 입구로 신청·수락해도
/// 판돈 걸린 둘째 판은 서지 않고 `busy` · `target_busy` 로 돌아온다. 다만 그 응답은 **어느 게임 때문인지 말하지 않는다**
/// (일반 문구 '이미 진행 중인 대국이 있어요'). 클라가 입구를 먼저 막는 까닭은 그것이다 — 화면이 어느 판 때문에 막혔는지 말하게.
/// (예전 주석의 '오목 쪽 게이트는 체스를 모른다'(인수인계 §6-7 '알려진 비대칭')는 사실이 아니다 — 위 마이그레이션이 근거다.)
/// 폰은 여러 게임 입구를 한 화면에 같이 띄우므로 **모든 방향**을 그린다.
package enum GamesBusyGame: String, Equatable, Sendable, CaseIterable {
    case gomoku
    case chess
    /// 1:1 테트리스(1.0.11). 서버 `chess__busy` 가 함께 본다(오목 신청·수락도 이 판정을 지난다) — 클라는 세 방향 입구를
    /// 막아 까닭을 먼저 그린다.
    case tetris
    /// 아잉 큐브(1.0.16). 서버 `chess__busy` 가 그 자리(joined·playing)까지 본다 — 클라도 네 방향을 막아 까닭을 먼저 그린다.
    case rummy
    /// 아잉 뒤집기(1.0.17). 서버 `game__busy_users()` 가 리버시 active 판까지 본다(함수는 20261107140000 이 만들고, 리버시 줄은
    /// 20261108200000_reversi.sql 이 조각 치환으로 더했다 — 맥 0.3.74 와 함께 운영 적용) —
    /// 클라는 **다섯 방향**을 막아 까닭을 먼저 그린다.
    case reversi
    /// 1:1 길건너(1.0.18). 서버 `game__busy_users()` 가 길건너 active 판까지 본다(20261109150000 — 맥 0.3.78) — 클라는 여섯 방향을 막는다.
    case crossyDuel
    /// 1:1 알까기(1.0.18). 서버 `game__busy_users()` 가 알까기 판까지 본다(20261110130000 §8 조각 치환) — 클라는 일곱 방향을 막는다.
    case alkkagi

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
        case .rummy: return .rummy
        case .reversi: return .reversi
        case .crossyDuel: return .crossyDuel
        case .alkkagi: return .alkkagi
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
/// 6. **아잉 뒤집기**(서버·맥 0.3.74 · 폰 1.0.17) — 코어 `ReversiStore`(context.reversi, host 는 위 넷과 **같은** 하나).
///    체스와 **같은 세 걸음**을 옮긴다(관전이 있다): 화면이 나타남 → `openWindow` + active 면 `windowDidShow` /
///    사라짐 → `stopWatching()` **먼저** 그리고 `windowDidHide()` → `windowDidClose()` / 앱이 background → **가림**.
///    오목처럼 30초·자동 착수가 있어(연속 3번이면 패) 판이 막 열리면(`presentWindow`) 화면을 연다 — 코어가 **이 기기가 연 판**에서만 그 문을 부른다.
///    AI 연습은 코어가 화면 수명(숨김·가림)으로 사람 시계를 멈춘다. 다른 게임 입구를 막지 않는다(`hasLiveReversiMatch`).
///
/// 탭 배지 = 받은 오목 신청 수 + 받은 아잉 큐브 초대 수 + 받은 아잉 뒤집기 신청 수(만료 안 된 것 — 체스·테트리스는 안 센다, `badgeCount` 주석).
/// 받은 오목 신청은 인박스가 채운다 — 계기는 앱 active(60초 스로틀) · 실시간 'gomoku' 신호(기반 배선) · 오목 화면.
///
/// **한 사람 한 판(B8)은 다섯 방향이다** — 다섯 게임 입구가 한 화면에 있으므로 `chessEntryBlock`·`gomokuEntryBlock`·
/// `tetrisEntryBlock`·`rummyEntryBlock`·`reversiEntryBlock` 다섯을 그려야 한다(까닭은 `GamesBusyGame`).
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
    /// 아잉 큐브 화면이 지금 떠 있다(위 셋과 같은 뜻 — 코어 `setWindowVisible` 을 폰 화면 수명으로 옮긴 값).
    package private(set) var isRummyScreenVisible = false
    /// 아잉 뒤집기 화면이 지금 떠 있다(위 넷과 같은 뜻 — 코어의 '창 표시'를 폰 화면 수명으로 옮긴 값). `appDidBecomeActive` 가 이 값으로 갈린다 —
    /// 거짓인데 `windowDidShow()` 를 부르면 보이지도 않는 판에 폴링이 돌고 AI 연습 판의 사람 시계가 흐른다.
    package private(set) var isReversiScreenVisible = false
    /// 1:1 길건너 화면(로비 · 판 · 결과)이 떠 있다(폰 1.0.18).
    package private(set) var isCrossyDuelScreenVisible = false
    /// 1:1 알까기 화면(로비 · 판 · 결과 · 관전 · 연습)이 떠 있다(폰 1.0.18).
    package private(set) var isAlkkagiScreenVisible = false
    /// 방장이 방을 떠나려 한다 — 화면이 띄울 "방이 닫혀요" 확인(`rummyDepartureAllowed`).
    package private(set) var rummyDeparturePrompt: RummyCloseDecision?
    /// 수락하면 원래 가려던 곳으로 가는 일.
    @ObservationIgnored private var rummyDepartureResume: (@MainActor () -> Void)?
    /// 마지막 탭 이탈(되보내기를 기다리는 동안 포함). 새 이탈이 앞의 기다림을 끊고, 시험이 끝을 기다린다.
    @ObservationIgnored package private(set) var rummyDepartureTask: Task<Void, Never>?
    /// `rummy_leave` 가 지금 나가는 중이다 — 여럿이 눌러도 하나만 나간다.
    @ObservationIgnored package private(set) var isRummyDepartureRunning = false
    /// 나가기를 서버가 확인하지 않은 방. 자리가 남아 있으니 카드가 그 사실을 말한다.
    package private(set) var rummyUnconfirmedLeaveRoomID: UUID?
    /// 나가기가 안 닿았을 때 화면 밖에서 다시 보내기까지(초). 합이 90초를 넘게 둔다: 화면 밖 방은 하트비트를 쉬므로(`roomHeartbeatHeld`) 그때쯤이면 서버가 시작 검사에서 이 자리를 뺀다 — 그 전에 망이 돌아오면 이 되보내기가 먼저 나간다.
    @ObservationIgnored package var rummyLeaveRetrySeconds: [Double] = [3, 10, 30, 60]
    /// 탭을 옮겨 방에서 나왔다 — 로비가 한 번 말한다(`tabLeftNotice`). 코어 `notice` 에 넣지 않는 까닭: 그 줄은 방·판 화면도 읽고, 판 화면에선 차례 안내를 밀어낸다.
    package private(set) var rummyLeftByTabNotice: String?
    /// 위 줄을 화면이 한 번 보였다 — 다음에 떠날 때 지운다. 아직 안 보인 줄을 먼저 지우면 돌아온 사람이 못 본다.
    @ObservationIgnored private var rummyTabLeftNoticeSeen = false
    /// 결과에서 [최종 판]을 펴 둔 판. 판 id 를 쥐는 까닭: 다음 판의 결과가 이 표시를 물려받아 저절로 가로가 되면 안 된다.
    private var rummyFinalBoardMatchID: UUID?
    /// 오목 · 체스 · 테트리스 · 아잉 큐브 · 아잉 뒤집기 화면(로비 · 대국 · 관전) 중 하나가 떠 있다. 생일 선물 축하 시트(v0.3.66)와 확성기 배너가 이때는 스스로 뜨지 않는다
    /// (`MeStore.presentCakeGiftIfDue` · `MobileAppModel.isMegaphoneBannerDeferred` — 수 시계 · 15초 침묵이 걸린 판을 덮지 않게).
    ///
    /// 아잉 큐브만 화면과 하나 더 갈린다(맥 `RummyStore.defersMegaphoneBanner` 의 짝):
    ///  · 이 기기가 손댄 판에서 내 자리가 playing 이면 **다른 탭에 있어도** 참이다 — 언제든 차례가 돌아온다.
    ///  · 놀던 기기가 남의 기기 판을 읽기만 하는 동안 · 기권 뒤 구경은 거짓이다(놀던 기기는 배너를 못 볼 까닭이 없다 — SPEC-v2 §6).
    ///  · 로비·방·결과 화면은 다른 대결 화면과 같은 대접이다.
    ///
    /// 아잉 뒤집기는 **화면으로만** 가른다(오목·체스·테트리스와 같다). 코어 `defersMegaphoneBanner`(phase == .playing)를 쓰지 않는 까닭:
    /// 폰 스토어는 같은 계정 **맥이 두는 판**도 로비 `active_match_id` 로 읽어 들고 있어(`playing`), 그 값을 쓰면 맥이 한 판 두는 동안
    /// 폰의 확성기·생일 선물이 통째로 멎는다. 내 판이 흐르는 동안 다른 탭에 있으면 배너를 보는 것이 맞다(체스와 같은 대접).
    package var isAnyMatchScreenVisible: Bool {
        if isGomokuScreenVisible || isChessScreenVisible || isTetrisScreenVisible || isReversiScreenVisible || isCrossyDuelScreenVisible
            || isAlkkagiScreenVisible { return true }
        let rummy = context.rummy
        if rummy.defersMegaphoneBanner { return true }
        return isRummyScreenVisible && rummy.phase != .playing
    }
    /// 지금 판 결과에서 [최종 판]을 보는 중인가.
    package var isRummyFinalBoardShown: Bool {
        guard let id = rummyFinalBoardMatchID else { return false }
        let rummy = context.rummy
        return rummy.phase == .finished && rummy.match?.id == id
    }

    package func setRummyFinalBoardShown(_ shown: Bool) {
        rummyFinalBoardMatchID = shown ? context.rummy.match?.id : nil
    }

    /// 화면 방향 — 앱에서 단 하나의 답(`GamesRummyOrientation.swift` 머리말). 저장하지 않고 지금 상태에서 계산한다. 이 기기가 큐브를 못 하는 안내가 서 있으면 판을 그리지 않으니 세로다.
    package var rummyInterfaceOrientation: GamesRummyInterfaceOrientation {
        let rummy = context.rummy
        return GamesRummyOrientationRule.orientation(phase: rummy.phase,
                                                     isScreenVisible: isRummyScreenVisible && rummy.availability == .available,
                                                     finalBoardShown: isRummyFinalBoardShown)
    }

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

    /// 데모 전용: 시작 라우트가 아잉 큐브 장면(`games/rummy/…`)이라 게임 탭이 큐브를 쌓아야 한다. 위 두 깃발과 같은 규약이다.
    package var pendingDemoRummyScreen = false

    /// 데모 전용: 시작 라우트의 꼬리를 푼 값(열 판 · 로비 탭 · 규칙 시트 — `MobileDemoRummyRoute`). 위 두 값과 같은 규약이다(DEBUG 안).
    #if DEBUG
    package var demoRummyRoute: MobileDemoRummyRoute?
    #endif

    /// 데모 전용: 시작 라우트가 아잉 뒤집기 장면(`games/reversi/…`)이라 게임 탭이 아잉 뒤집기를 쌓아야 한다. 위 세 깃발과 같은 규약이다
    /// (Bool 한 칸이라 `#if DEBUG` 밖 · 세우는 자리가 데모뿐이라 Release 에서는 영원히 false).
    package var pendingDemoReversiScreen = false

    /// 데모 전용: 시작 라우트의 꼬리를 푼 값(열 판 · 걸 관전 · 로봇 연습 · 규칙 시트 · 로비 시작 절 — `MobileDemoReversiRoute`).
    /// 위 값들과 같은 규약이다(꺼내 비우지 않는다 · 로그아웃 `reset()` 이 비운다 · 타입이 DEBUG 전용이라 `#if DEBUG` 안).
    #if DEBUG
    package var demoReversiRoute: MobileDemoReversiRoute?
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
        // 아잉 큐브도 **같은 문**이다. 코어가 부르는 자리 둘: `openWindow` · 판으로 처음 넘어갈 때(`announce`).
        context.rummy.presentWindow = { [weak self] in self?.presentRummyScreen() }
        // 아잉 뒤집기도 **같은 문**이다. 안 물리면 수락·시작이 화면을 못 연다 — 신청자는 수락된 순간을 몰라 흑 30초를 흘리고 자동 착수가 쌓인다
        // (연속 3번이면 판돈째 진다). 코어가 부르는 자리 셋: `openWindow` · 수락 응답(`respond`) · 이 기기가 연 판으로 처음 넘어갈 때(`noteMatchProgress`).
        // 로그아웃 `reset()` 이 부르는 `dismissWindow` 는 달지 않는다 — 폰은 `sessionDidSignOut` 의 `router.reset()` 이 경로를 비운다.
        context.reversi.presentWindow = { [weak self] in self?.presentReversiScreen() }
        context.crossyDuel.presentWindow = { [weak self] in self?.presentCrossyDuelScreen() }
        // 1:1 알까기: 판이 처음 서면(이 기기든 같은 계정 맥이든) 코어가 부른다 — 맥 창 열기와 같은 자리. 앱이 앞에 있을 때만 화면을 쌓는다.
        context.alkkagi.presentWindow = { [weak self] in self?.presentAlkkagiScreen() }
        // 방 화면을 떠나는 길은 이 문 하나를 지난다(탭 막대 · 푸시 · 딥링크 · 위젯 · 탭 재선택).
        context.router.departureGuard = { [weak self] resume in self?.rummyDepartureAllowed(resume: resume) ?? true }
        // 방 화면이 설 때만 방 하트비트를 돌린다(`rummyScreenDidAppear`) — 어느 길로 화면 밖에 앉게 됐든(앱을 다시 켬 · 다른 게임 화면이 덮음) 모르는 사이 판돈이 걷히지 않는다.
        context.rummy.roomHeartbeatHeld = true
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
        // 서버가 받았다고 확인해 주지 않은 끝난 판이 있으면 민다(모든 게임 · 앱을 껐다 켠 경우도 로그인 직후 여기로 온다).
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
        //   `refreshLobby()`). 겹쳐 부르면 코어가 도는 로비 뒤에 **한 번 더** 읽고(`lobbyAgain` — 2026-11-03, 도는 중에
        //   온 초인종을 버리지 않으려고), `windowDidShow()` 를 화면 없이 부르면 **보이지 않는 판의 준비 보고가 나간다.**
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
        // 아잉 큐브: background 에서 창을 내렸으니 되세운다. 안 보이면 따라잡기만(받은 초대 칩·탭 배지가 여기 달려 있다).
        // ★ 차례 시간은 서버에서 흐른다. 돌아온 순간 다음 폴링을 기다리면 옛 판을 그린다 — `setWindowVisible(true)` 가 로비와 든 판을 그 자리에서 한 번씩 읽는다.
        //   거기에 `catchUp()` 을 덧붙이면 복귀할 때마다 같은 조회가 한 벌 더 나간다(둘은 같은 두 조회다).
        let rummy = context.rummy
        if isRummyScreenVisible {
            rummy.setWindowVisible(true)
        } else {
            rummy.systemDidWake()
        }
        // 두 갈래 모두: 위 둘은 읽기뿐이라 서버의 접속 증거가 안 된다. 다음 주기를 기다리면 그 사이 90초를 넘겨 기권될 수 있다.
        rummy.heartbeatNow()
        // 아잉 뒤집기: 체스와 같은 세 걸음이되 **두 갈래를 겹쳐 부르지 않는다**.
        //  · 화면이 보이면 — 창이 서 있으면 가림만 풀고(background 에서 '가림'으로 멈춘 폴링 · AI 사람 시계를 되살린다), 안 서 있으면
        //    `windowDidShow()`. 그리고 `catchUp()` 으로 background 동안 놓친 것을 읽는다(신청·수락·상대 수·서버가 대신 둔 수 — 시계는 서버에서 흘렀다).
        //  · 안 보이면 — `refreshLobbyIfStale()`(30초 스로틀). 탭 배지의 받은 신청과 한 사람 한 판의 `activeMatchID` 가 이 계기에 달려 있다.
        //    로비는 사람마다 `reversi_capable` 을 부르는 무거운 조회라(조사 risks — 로비 부하) 스로틀에 맡긴다. 돌아온 순간의 신선도는
        //    실시간 조인 따라잡기(`.catchUp` → `realtimeDidJoin`)가 따로 맡는다.
        // ★ `if` 로 둔다(위 체스 주석) — 새 게임을 이 뒤에 더해도 따라잡기가 끊기지 않게.
        let reversi = context.reversi
        if isReversiScreenVisible {
            if reversi.isWindowVisible {
                reversi.windowOcclusionDidChange(visible: true)
            } else {
                reversi.windowDidShow()
            }
            Task { await reversi.catchUp() }
        } else {
            reversi.refreshLobbyIfStale()
        }
        let crossyDuel = context.crossyDuel
        if isCrossyDuelScreenVisible {
            if crossyDuel.isWindowVisible {
                crossyDuel.windowOcclusionDidChange(visible: true)
            } else {
                crossyDuel.windowDidShow()
            }
            crossyDuel.requestSync()
        } else {
            crossyDuel.refreshLobbyIfStale()
        }
        let alkkagi = context.alkkagi
        if isAlkkagiScreenVisible {
            if alkkagi.isWindowVisible {
                alkkagi.windowOcclusionDidChange(visible: true)
            } else {
                alkkagi.windowDidShow()
            }
            alkkagi.handleSignal()
        } else {
            alkkagi.refreshLobbyIfStale()
        }
    }

    /// 장면이 앞에서 물러난다(`.inactive` — 전화 수신 · 제어 센터 · 앱 전환기). 도는 미니게임을 얼린다.
    /// 연결·폴링은 건드리지 않는다: 곧 돌아오는 일이 대부분이다(`MobileRootView.applyScenePhase`).
    package func sceneWillResignActive() {
        miniGames.appWillResignActive()
    }

    /// 장면이 앞으로 왔다(`.inactive` 에서 돌아왔을 때도 온다). 얼어 있던 판의 상한을 재고 토큰을 챙긴다 — 자동으로 풀지는 않는다.
    package func sceneDidComeForward() {
        miniGames.sceneDidComeForward()
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
        // 아잉 큐브: **창만 내린다**(폴링을 멈춘다). 기권이 아니다 — 하트비트는 코어가 창과 무관하게 돌리고, iOS 가 재우면 서버가
        // 90초 뒤 끊김 기권을 시킨다(사용자 결정: 앱을 내려도 즉시 기권하지 않는다). 결과 화면도 접지 않는다(접는 길은 화면을 떠날 때뿐이다).
        if isRummyScreenVisible { context.rummy.setWindowVisible(false) }
        // 아잉 뒤집기도 **가림**이다(체스와 같은 까닭 둘 — 결과 화면이 접히지 않고, 보던 관전이 끊기지 않는다). 가림은 폴링 · AI 사람 시계 ·
        // 뒤집기 그림만 멈춘다. ★ **1:1 판은 멈추지 않는다** — 서버 시계가 흐르고 30초가 지나면 서버가 대신 둔다(연속 3번이면 패).
        if isReversiScreenVisible, context.reversi.isWindowVisible {
            context.reversi.windowOcclusionDidChange(visible: false)
        }
        if isCrossyDuelScreenVisible, context.crossyDuel.isWindowVisible {
            context.crossyDuel.windowOcclusionDidChange(visible: false)
        }
        // 1:1 알까기도 가림이다(폴링 · 관전 걸음만 쉰다 — 서버 시계는 흐른다).
        if isAlkkagiScreenVisible, context.alkkagi.isWindowVisible {
            context.alkkagi.windowOcclusionDidChange(visible: false)
        }
    }

    package func reset() {
        miniGames.reset()
        isGomokuScreenVisible = false
        isChessScreenVisible = false
        isTetrisScreenVisible = false
        isRummyScreenVisible = false
        isReversiScreenVisible = false
        isCrossyDuelScreenVisible = false
        isAlkkagiScreenVisible = false
        rummyFinalBoardMatchID = nil
        rummyDeparturePrompt = nil
        rummyDepartureResume = nil
        rummyDepartureTask?.cancel()
        rummyDepartureTask = nil
        isRummyDepartureRunning = false
        rummyUnconfirmedLeaveRoomID = nil
        rummyLeftByTabNotice = nil
        rummyTabLeftNoticeSeen = false
        context.rummy.roomHeartbeatHeld = true
        pendingGomokuFocusID = nil
        pendingDemoChessScreen = false
        pendingDemoTetrisScreen = false
        pendingDemoRummyScreen = false
        pendingDemoReversiScreen = false
        #if DEBUG
        demoChessRoute = nil
        demoTetrisRoute = nil
        demoRummyRoute = nil
        demoReversiRoute = nil
        #endif
        syncAIThinker()
    }

    /// 데모 아잉 큐브 장면 깃발을 **한 번** 꺼낸다(아래 체스·테트리스와 같은 규약).
    package func consumePendingDemoRummyScreen() -> Bool {
        guard pendingDemoRummyScreen else { return false }
        pendingDemoRummyScreen = false
        return true
    }

    /// 데모 아잉 뒤집기 장면 깃발을 **한 번** 꺼낸다(같은 규약 — 게임 탭이 두 계기에서 부르므로 비우지 않으면 화면이 두 번 쌓인다).
    package func consumePendingDemoReversiScreen() -> Bool {
        guard pendingDemoReversiScreen else { return false }
        pendingDemoReversiScreen = false
        return true
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
    /// 코어 아잉 큐브 스토어 줄임(= `context.rummy`). 같은 규약이다.
    package var rummy: RummyStore { context.rummy }
    /// 코어 아잉 뒤집기 스토어 줄임(= `context.reversi`). 같은 규약이다.
    package var reversi: ReversiStore { context.reversi }

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
    ///
    /// **아잉 큐브 초대는 센다**(1.0.16): 위 둘과 달리 초인종을 잇기 때문이다(`.rummySignal` → `handleSignal`). 초대가 오면 그 자리에서 로비를 읽고
    /// 방은 10분을 산다 — "60초 TTL 짜리 숫자를 30초 스로틀로 갱신하는" 꼴이 아니다. 오목 카드의 한 줄은 `gomokuIncomingCount` 를 읽는다(큐브 초대가 섞이면 안 된다).
    ///
    /// **아잉 뒤집기 신청도 센다**(1.0.17 — 큐브와 같은 근거): 초인종을 잇는다(`.reversiSignal` → `handleSignal` → 판이 없으면 로비). 신청이 오면 그 자리에서
    /// 로비를 읽어 `me.incoming` 을 갈아 끼우고, 60초 만료는 코어 타이머가 `incoming` 에서 걷는다(`scheduleInviteExpiry`) — 숫자가 30초 스로틀에 묶이지 않는다.
    /// 차단 거울을 거친 값(`visibleIncomingInvites`)을 센다 — 거울은 허브·화면이 설 때 맞춘다(`syncReversiHiddenPeers`).
    package var badgeCount: Int {
        gomokuIncomingCount + context.rummy.incomingInvites.count + context.reversi.visibleIncomingInvites.count
            + context.crossyDuel.visibleIncomingInvites.count + context.alkkagi.visibleIncomingInvites.count
    }

    /// 만료 안 된 받은 오목 신청 수(오목 카드의 재료).
    package var gomokuIncomingCount: Int { context.gomoku.pendingIncomingInvites.count }

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

    /// 아잉 뒤집기 로비의 상대 고르기 목록 — 같은 근거·같은 방식(위 세 주석). 코어 `visibleUsers` 는 차단 거울(`hiddenPeerIDs` — 허브·화면이 설 때
    /// `syncReversiHiddenPeers` 가 맞춘다)까지 거른 값이고, 거기에 메시지 탭의 차단 목록을 **지금 값으로** 한 번 더 겹친다(화면이 떠 있는 동안 막 차단한 사람).
    /// **정렬은 하지 않는다**(코어 `sortedForLobby` 가 서버와 같은 규칙으로 이미 맞춰 뒀다).
    package var reversiLobbyUsers: [ReversiUser] {
        let hidden = context.links.messages?.hiddenBlockedPeerIDs ?? []
        let users = context.reversi.visibleUsers
        guard !hidden.isEmpty else { return users }
        let lowered = Set(hidden.map { $0.lowercased() })
        return users.filter { !lowered.contains($0.id) }
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

    /// 사람과의 **아잉 뒤집기** 판이 지금 흐르고 있는가(오목·체스와 같은 규칙 — AI 연습 판·끝난 판은 아니다).
    ///
    /// ★ `activeMatchID` 를 먼저 본다(테트리스 주석과 같은 근거): 로비가 진행 판 id 를 주면 코어가 곧바로 `reversi_state` 를 쏘지만, 그 조회가
    ///   실패하면 `match` 는 nil 인 채 id 만 남는다. 그 틈에 오목을 수락하면 흐르던 리버시 판은 30초마다 서버가 대신 두고 3번째에 **판돈째 진다**.
    ///   닫는 쪽으로 틀리는 것이 맞다(서버가 판을 닫으면 다음 로비가 id 를 지운다). AI 판 id(`ai-…`)는 이 칸에 오르지 않는다(서버 판만 적는다).
    /// ★ 같은 계정의 **다른 기기**(맥)가 두는 판도 막는다 — 한 사람은 한 판만이다(서버 `game__busy_users` 도 기기를 가리지 않는다).
    package var hasLiveReversiMatch: Bool {
        let reversi = context.reversi
        if reversi.activeMatchID != nil { return true }
        guard let match = reversi.match, !match.isFinished else { return false }
        return !match.isAI
    }

    /// 1:1 길건너 진행 판(사람끼리뿐 — 로봇 연습이 없다). 서버가 말한 id 또는 들고 있는 안 끝난 판.
    package var hasLiveCrossyDuelMatch: Bool {
        let duel = context.crossyDuel
        if duel.activeMatchID != nil { return true }
        guard let match = duel.match else { return false }
        return !match.isFinished
    }

    /// 1:1 알까기 진행 판(사람끼리뿐 — 연습은 서버 판이 아니다). 코어는 로비가 진행 판을 실어 오면 `state` 를 세운다(같은 계정 맥의 판 포함).
    package var hasLiveAlkkagiMatch: Bool {
        guard let state = context.alkkagi.state else { return false }
        return state.phase != .finished
    }

    /// **AI 연습 판**이 지금 진행 중인가(끝난 판은 아니다). 서버는 이 판을 볼 수 없다(행이 없다 — `game__busy_users` 가 모른다).
    /// 코어 `challenge`·`respond` 에는 AI 가드가 없어 1:1 판이 서는 순간 `match` 관찰자가 AI 판을 **문구 없이 버린다**(1:1 이 이긴다) —
    /// 신청은 `GamesReversiChallengeGate`(내 판이 있으면 닫힘)가 막고, 받은 신청 수락은 화면이 먼저 묻는다(체스 로봇 판과 같은 규약).
    package var hasLiveReversiAIGame: Bool {
        let reversi = context.reversi
        guard reversi.isAIMatch, let match = reversi.match, !match.isFinished else { return false }
        return true
    }

    /// 체스 입구를 막는 까닭(없으면 nil). 오목·테트리스 판이 흐르면 체스를 신청·수락할 수 없다 —
    /// 서버도 같은 판정을 한다(`chess__busy`), 그래서 이 쪽은 **클라가 사실을 먼저 그리는 것**이다.
    package var chessEntryBlock: GamesBusyGame? {
        if hasLiveGomokuMatch { return .gomoku }
        if hasLiveTetrisMatch { return .tetris }
        if hasLiveRummyMatch { return .rummy }
        if hasLiveReversiMatch { return .reversi }
        if hasLiveCrossyDuelMatch { return .crossyDuel }
        return hasLiveAlkkagiMatch ? .alkkagi : nil
    }

    /// 오목 입구를 막는 까닭(없으면 nil). 서버도 막는다 — 오목 신청·수락이 `chess__busy` 를 본다(`GamesBusyGame` 머리말).
    /// 이 값은 **어느 판 때문인지** 화면이 먼저 말하게 한다. 안 막으면 오목 로비까지 들어가 [수락]을 누른 뒤에야 서버의
    /// 일반 문구('이미 진행 중인 대국이 있어요')를 받는다.
    package var gomokuEntryBlock: GamesBusyGame? {
        if hasLiveChessMatch { return .chess }
        if hasLiveTetrisMatch { return .tetris }
        if hasLiveRummyMatch { return .rummy }
        if hasLiveReversiMatch { return .reversi }
        if hasLiveCrossyDuelMatch { return .crossyDuel }
        return hasLiveAlkkagiMatch ? .alkkagi : nil
    }

    /// 테트리스 입구를 막는 까닭(없으면 nil). 테트리스는 **판돈이 걸린 실시간 판**이라 막는 쪽이 더 무겁다 —
    /// 오목·체스 판을 두는 중에 테트리스를 수락하면 그 판은 15초 침묵으로 **진다**(서버 D5).
    package var tetrisEntryBlock: GamesBusyGame? {
        if hasLiveGomokuMatch { return .gomoku }
        if hasLiveChessMatch { return .chess }
        if hasLiveRummyMatch { return .rummy }
        if hasLiveReversiMatch { return .reversi }
        if hasLiveCrossyDuelMatch { return .crossyDuel }
        return hasLiveAlkkagiMatch ? .alkkagi : nil
    }

    /// 아잉 큐브 입구를 막는 까닭(없으면 nil) — 네 방향의 마지막 하나. 시작 검사가 세 게임의 진행 판을 보지만(서버), 판돈 걸린 판을 두는 중에
    /// 방에 앉아 있으면 시작하는 순간 빠지거나 흐르던 판이 시간패한다. 입구에서 막는다.
    package var rummyEntryBlock: GamesBusyGame? {
        if hasLiveGomokuMatch { return .gomoku }
        if hasLiveChessMatch { return .chess }
        if hasLiveTetrisMatch { return .tetris }
        if hasLiveReversiMatch { return .reversi }
        if hasLiveCrossyDuelMatch { return .crossyDuel }
        return hasLiveAlkkagiMatch ? .alkkagi : nil
    }

    /// 아잉 뒤집기 입구를 막는 까닭(없으면 nil) — 다섯 방향의 마지막 하나. 서버도 막는다(`reversi_challenge`·`reversi_respond` 가 `game__busy_users` 를 본다) —
    /// 이 값은 **어느 판 때문인지** 화면이 먼저 말하게 한다. 판돈 걸린 다른 판을 두는 중에 리버시를 수락하면 그 판이 시간패한다(테트리스는 15초 침묵).
    package var reversiEntryBlock: GamesBusyGame? {
        if hasLiveGomokuMatch { return .gomoku }
        if hasLiveChessMatch { return .chess }
        if hasLiveTetrisMatch { return .tetris }
        if hasLiveRummyMatch { return .rummy }
        if hasLiveCrossyDuelMatch { return .crossyDuel }
        return hasLiveAlkkagiMatch ? .alkkagi : nil
    }

    /// 1:1 길건너 입구 막기(폰 1.0.18) — 다른 다섯 1:1 중 하나가 흐르면 그 까닭을 먼저 말한다.
    package var crossyDuelEntryBlock: GamesBusyGame? {
        if hasLiveGomokuMatch { return .gomoku }
        if hasLiveChessMatch { return .chess }
        if hasLiveTetrisMatch { return .tetris }
        if hasLiveRummyMatch { return .rummy }
        if hasLiveReversiMatch { return .reversi }
        return hasLiveAlkkagiMatch ? .alkkagi : nil
    }

    /// 1:1 알까기 입구 막기(폰 1.0.18) — 다른 여섯 1:1 중 하나가 흐르면 그 까닭을 먼저 말한다(서버도 `chess__busy` 로 막는다).
    package var alkkagiEntryBlock: GamesBusyGame? {
        if hasLiveGomokuMatch { return .gomoku }
        if hasLiveChessMatch { return .chess }
        if hasLiveTetrisMatch { return .tetris }
        if hasLiveRummyMatch { return .rummy }
        if hasLiveReversiMatch { return .reversi }
        return hasLiveCrossyDuelMatch ? .crossyDuel : nil
    }

    /// 지금 아잉 큐브 자리가 있는가 — 다른 게임 입구를 막는 값.
    ///
    /// ★ **방(forming)도 막는다.** 서버 `chess__busy` 가 rummy joined·playing 을 함께 본다(20261103120000 §50 — 그래서 오목·체스·테트리스
    ///   신청·수락은 `busy` 로 거절된다). 클라가 막는 것은 방에 앉은 사람에게 **어느 게임 때문인지** 말하려는 것이다. 다른 기기가 쥔 판도
    ///   같은 사람의 판이라 막는다.
    /// ★ 들고 있는 판이 있으면 **그 판으로 판단한다**(로비의 `activeMatchID` 는 30초 낡을 수 있다): 끝났거나 내가 기권했으면 자리가 없는 것이다.
    ///   판을 아직 못 읽었으면 서버가 말한 id 를 믿는다(닫는 쪽으로 틀린다 — 테트리스 `hasLiveTetrisMatch` 와 같은 근거).
    package var hasLiveRummyMatch: Bool {
        let rummy = context.rummy
        if let match = rummy.match, match.id == rummy.activeMatchID || rummy.activeMatchID == nil {
            guard RummyStore.isUnsettled(match.status) else { return false }
            return match.status != .active || RummyExitPolicy.mySeat(rummy)?.state != .forfeit
        }
        return rummy.activeMatchID != nil
    }

    /// 이 기기가 지금 쥔 판이 진행 중이고 내 자리가 playing 이다(화면 꺼짐 방지 · 확성기가 같은 말을 묻는다 — 코어 한 곳).
    package var holdsRummyMatch: Bool { context.rummy.defersMegaphoneBanner }

    /// **로봇 체스 판**이 지금 진행 중인가(끝난 판은 아니다).
    ///
    /// ★ 서버는 이 판을 **볼 수 없다.** `chess__busy`(지금은 `game__busy_users()` 껍데기 — 20261107140000)는 서버의 판·자리 표만 보고
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
        // 아잉 큐브도 **받은함 RPC 가 없다** — 받은 초대·내 방·진행 판 id·전적이 전부 `rummy_lobby` 로 온다(30초 스로틀). 빠지면 카드의 초대 칩과
        // 탭 배지가 비고, 앱을 막 켠 사람의 자리를 몰라 다른 게임 카드가 열려 있다(위 테트리스와 같은 근거).
        syncRummyHiddenPeers()
        context.rummy.refreshLobbyIfStale()
        // 아잉 뒤집기도 **받은함 RPC 가 없다** — 받은 신청·보낸 신청·진행 판 id·전적이 전부 `reversi_lobby` 의 `me` 로 온다. 그래서 허브에서 한 번 당긴다
        // (30초 스로틀 — 코어 `menuLobbyThrottleSeconds`, 맥 팝오버 열기와 같은 문). 로비는 사람마다 `reversi_capable` 을 부르는 무거운 조회라 스로틀을 꼭 지난다.
        // ★ 빠지면 둘이 함께 죽는다(테트리스 줄과 같은 근거): ① 카드의 "받은 신청" 칩과 탭 배지가 다음 초인종까지 비고, ② 앱을 막 켠 사람의
        //   `activeMatchID` 가 nil 이라 리버시 판(같은 계정 맥의 판 포함)이 흐르는 중에도 다른 카드가 열려 있다.
        syncReversiHiddenPeers()
        context.reversi.refreshLobbyIfStale()
        // 1:1 길건너도 받은함 RPC 가 없다 — 받은 신청 · 진행 판 id 가 `crossy_duel_lobby` 로 온다(30초 스로틀).
        syncCrossyDuelHiddenPeers()
        context.crossyDuel.refreshLobbyIfStale()
        // 1:1 알까기도 받은함 RPC 가 없다 — 받은 신청 · 진행 판이 가벼운 `alkkagi_lobby`(`p_users` 거짓)로 온다(30초 스로틀 — 맥 팝오버와 같은 문).
        syncAlkkagiHiddenPeers()
        context.alkkagi.refreshLobbyIfStale()
    }

    /// 차단 거울: 메시지 탭의 차단 목록을 코어에 넘긴다(로비 사람 · 초대 · 공개 방이 코어에서 걸러진다 — 맥 `WorkTimerStore` 와 같은 길).
    package func syncRummyHiddenPeers() {
        let hidden = context.links.messages?.hiddenBlockedPeerIDs ?? []
        context.rummy.setHiddenPeers(Set(hidden.compactMap { UUID(uuidString: $0) }))
    }

    /// 아잉 뒤집기 차단 거울(맥 `WorkTimerStore` 의 `reversi.hiddenPeerIDs = blockHiddenPeerIDs` 와 같은 길). 코어가 로비 사람·받은 신청·
    /// 탭 배지를 이 집합으로 거른다. 코어 id 는 소문자 uuid 라 소문자로 맞춘다. 같은 값이면 쓰지 않는다(관찰을 깨우지 않게).
    package func syncReversiHiddenPeers() {
        let hidden = Set((context.links.messages?.hiddenBlockedPeerIDs ?? []).map { $0.lowercased() })
        if context.reversi.hiddenPeerIDs != hidden { context.reversi.hiddenPeerIDs = hidden }
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

    /// 아잉 큐브 카드의 한 줄 재료 — **판이 흐른다**(방은 아니다 — 카드가 방과 판을 다른 말로 부른다).
    package var hasActiveRummyMatch: Bool {
        let rummy = context.rummy
        if let match = rummy.match { return match.status == .active }
        return rummy.lobby?.me?.activeMatchId != nil
    }

    /// 아잉 큐브 카드의 한 줄 재료 — 방에 앉아 있다.
    package var isInRummyRoom: Bool { context.rummy.myRoom != nil && !hasActiveRummyMatch }

    /// 아잉 뒤집기 카드의 한 줄 재료(위 체스와 같은 뜻 — **AI 연습 판도 포함**이다. 카드가 '대국 중'을 앞세울지는 `GamesReversiCard` 가
    /// AI 판과 받은 신청을 함께 보아 정한다 — 체스 카드와 같은 관례).
    package var hasActiveReversiMatch: Bool {
        let reversi = context.reversi
        if let match = reversi.match, !match.isFinished { return true }
        return reversi.activeMatchID != nil
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

    // MARK: 아잉 뒤집기 화면 수명 (체스에서 수리한 모양 그대로 — 관전이 있다)

    /// 아잉 뒤집기 화면이 나타났다: 차단 거울을 맞추고 로비·진행 판을 읽고(`openWindow`) 앱이 active 면 창을 세운다(`windowDidShow`).
    ///
    /// `isReversiScreenVisible` 을 **먼저** 적는다 — `openWindow` 가 `presentWindow` 를 부르고, 그 문이 "이미 보인다"를 봐야 화면을 또 열지 않는다.
    ///
    /// ★★ **`windowDidShow()` 가 이 화면의 둘째 주 스위치다.** 코어 `isWindowVisible` 도 기본이 false 이고 그 깃발을 켜는 문은 이것뿐이다.
    ///   깃발이 꺼져 있으면 넷이 함께 죽는다: 폴링(`startPolling` 가드 — 상대 차례·보낸 신청 5초·로비 30초) · 순위·관전(`canPollRanking` ·
    ///   `canPollSpectatorFeatures`) · **뒤집기 그림**(`noteBoardProgress` 가 `isWindowVisible` 을 먼저 본다 — 돌이 순간이동한다) ·
    ///   **AI 연습의 사람 시계**(`resumeAIClockIfVisible`). 못: `GamesReversiWiringTests`.
    /// ★ `focusMatchID` 는 **데모 라우트의 꼬리**다(`games/reversi/match/<장면>` — `MobileDemoReversiRoute`). 사람이 쓰는 길에서는 nil 이다 —
    ///   코어가 로비 `me.active_match_id` 로 내 판을 스스로 연다. 두 갈래는 **같은 동작**이다: `demoReversiRoute` 는 DEBUG 전용 값이고
    ///   Release 에서는 원래부터 영원히 nil 이다(체스 · 테트리스 · 큐브와 같은 꼴). 데모 장면의 규칙 시트 · 로봇 판은 `prepare` 가 판을 읽기 **전에** 세운다.
    package func reversiScreenDidAppear() {
        let reversi = context.reversi
        isReversiScreenVisible = true
        syncReversiHiddenPeers()
        #if DEBUG
        demoReversiRoute?.prepare(reversi)
        reversi.openWindow(focusMatchID: demoReversiRoute?.focusMatchID)
        #else
        reversi.openWindow(focusMatchID: nil)
        #endif
        if isAppActive { reversi.windowDidShow() }
        startDemoReversiWatchIfNeeded()
    }

    /// 데모 전용: 라우트 꼬리가 관전(`games/reversi/watch[/over]`)이면 **[관전] 칩을 누른 것과 같은 문**(`startWatching(matchID:)`)을 직접 건다 —
    /// 스크린샷에는 합성 탭이 없다(체스 `startDemoChessWatchIfNeeded` 와 같은 까닭). 코어 게이트는 하나도 우회하지 않는다.
    ///
    /// 로비 응답을 **먼저 기다린다**(`record` 가 서는 순간 = 로비를 옮겼다): 진행 중 판은 `liveMatches` 의 두 얼굴을 씨앗으로 쓰고,
    /// 끝난 판은 로비 목록에 없어(서버는 active 만 싣는다) 얼굴 없이 들어가 첫 응답이 채운다. 3초 안에 로비가 안 오면 그냥 건다.
    /// Release 에는 본문이 없다(`demoReversiRoute` 가 DEBUG 전용) — 그 구성에서도 값이 늘 nil 이라 동작이 같다.
    private func startDemoReversiWatchIfNeeded() {
        #if DEBUG
        guard let id = demoReversiRoute?.watchMatchID else { return }
        Task { [weak self] in
            for _ in 0..<60 {
                guard let self, self.isReversiScreenVisible else { return }
                if self.context.reversi.record != nil { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let self, self.isReversiScreenVisible else { return }
            self.context.reversi.startWatching(matchID: id)
        }
        #endif
    }

    // MARK: 1:1 길건너(폰 1.0.18)

    package var crossyDuel: CrossyDuelStore { context.crossyDuel }

    package func syncCrossyDuelHiddenPeers() {
        let hidden = Set((context.links.messages?.hiddenBlockedPeerIDs ?? []).map { $0.lowercased() })
        if context.crossyDuel.hiddenPeerIDs != hidden { context.crossyDuel.hiddenPeerIDs = hidden }
    }

    /// `isCrossyDuelScreenVisible` 을 **먼저** 적는다 — `openWindow` 가 `presentWindow` 를 부르고, 그 문이 "이미 보인다"를 봐야 화면을 또 열지 않는다.
    package func crossyDuelScreenDidAppear() {
        let duel = context.crossyDuel
        isCrossyDuelScreenVisible = true
        syncCrossyDuelHiddenPeers()
        duel.openWindow(focusMatchID: nil)
        if isAppActive { duel.windowDidShow() }
    }

    package func crossyDuelScreenDidDisappear() {
        guard isCrossyDuelScreenVisible else { return }
        isCrossyDuelScreenVisible = false
        context.crossyDuel.windowDidHide()
        context.crossyDuel.windowDidClose()
    }

    private func presentCrossyDuelScreen() {
        guard isAppActive, context.session.isSignedIn, !isCrossyDuelScreenVisible else { return }
        let router = context.router
        router.selectedTab = .games
        router.popToRoot(.games)
        router.push(GamesDestination.crossyDuel, on: .games)
    }

    // MARK: 1:1 알까기(폰 1.0.18)

    package var alkkagi: AlkkagiOnlineStore { context.alkkagi }

    /// 차단 거울(맥 `WorkTimerStore` 의 `alkkagi.hiddenPeerIDs = blockHiddenPeerIDs` 와 같은 길).
    package func syncAlkkagiHiddenPeers() {
        let hidden = Set((context.links.messages?.hiddenBlockedPeerIDs ?? []).map { $0.lowercased() })
        if context.alkkagi.hiddenPeerIDs != hidden { context.alkkagi.hiddenPeerIDs = hidden }
    }

    /// `isAlkkagiScreenVisible` 을 **먼저** 적는다 — `openWindow` 가 `presentWindow` 를 부르고, 그 문이 "이미 보인다"를 봐야 화면을 또 쌓지 않는다.
    package func alkkagiScreenDidAppear() {
        let store = context.alkkagi
        isAlkkagiScreenVisible = true
        syncAlkkagiHiddenPeers()
        store.openWindow(focusMatchID: nil)
        if isAppActive { store.windowDidShow() }
    }

    /// 화면을 떠났다 — 관전을 먼저 내리고(관전 걸음이 남지 않게) 창 닫기(끝난 내 판은 코어가 떠난다 — 다시 들어오면 로비).
    /// 진행 중인 내 판은 남는다(서버 시계 — 다시 들어오면 그 판이 선다).
    package func alkkagiScreenDidDisappear() {
        guard isAlkkagiScreenVisible else { return }
        isAlkkagiScreenVisible = false
        context.alkkagi.stopWatching()
        context.alkkagi.windowDidHide()
        context.alkkagi.windowDidClose()
    }

    private func presentAlkkagiScreen() {
        guard isAppActive, context.session.isSignedIn, !isAlkkagiScreenVisible else { return }
        let router = context.router
        router.selectedTab = .games
        router.popToRoot(.games)
        router.push(GamesDestination.alkkagi, on: .games)
    }

    /// 아잉 뒤집기 화면이 사라졌다(뒤로 · 다른 탭으로 · 로그아웃).
    ///
    /// **`stopWatching()` 이 먼저, `windowDidHide()` 가 나중이다**(체스와 같은 순서): 코어 `windowDidHide` 는 **끝난** 관전만 내리고 진행 중인
    /// 관전은 남긴다(맥의 최소화). 폰에서 그 통지는 "화면을 떠났다"다. 리버시 코어는 체스와 달리 `windowDidClose()` 도 관전을 내리므로
    /// 지금은 그 둘째 문이 같은 일을 겹쳐 한다(뮤테이션으로 확인 — 이 한 줄만 지우면 시험이 초록이다). 그래도 두는 까닭: 폰 '떠남'의 뜻을
    /// 코어 닫기 문의 몸통에 기대지 않고 이 훅이 스스로 말한다(체스·오목 훅과 같은 모양 — 코어가 닫기에서 관전을 빼는 날에도 그대로다).
    /// 두 문을 **함께** 지우면 다시 들어올 때 로비가 아니라 **남의 판이 다시 열린다**(`GamesReversiWiringTests` 의 기준선).
    /// `leaveWatch()` 가 **아니다**(로비·순위를 다시 읽는 네트워크 호출이다 — 떠나는 길에서 조회가 나가면 안 된다).
    ///
    /// ★★ **`windowDidClose()` 가 마지막이다** — 폰에서 화면을 떠나는 것은 '창을 정말 닫았다'다. 빼면 끝난 내 판(결과 카드)이 남아 다시 누를 때
    ///   로비가 아니라 결과가 다시 선다. **진행 중인 판은 남는다** — 코어 `foldFinishedMatch` 가 `isFinished` 를 먼저 본다(1:1 은 서버 시계로 계속 흐르고,
    ///   AI 연습은 숨김이 사람 시계를 멈춘다). 이 길로는 요청이 한 건도 나가지 않는다(리버시에는 `leave` RPC 가 없다).
    package func reversiScreenDidDisappear() {
        guard isReversiScreenVisible else { return }
        isReversiScreenVisible = false
        context.reversi.stopWatching()
        context.reversi.windowDidHide()
        context.reversi.windowDidClose()
    }

    // MARK: 아잉 큐브 화면 수명

    /// 아잉 큐브 화면이 나타났다: 로비·진행 판을 읽고(`openWindow`) 앱이 active 면 폴링을 켠다(`setWindowVisible`).
    ///
    /// `isRummyScreenVisible` 을 **먼저** 적는다 — `openWindow` 가 `presentWindow` 를 부르고, 그 문이 "이미 보인다"를 봐야 화면을 또 열지 않는다.
    /// 판의 하트비트는 이 값과 무관하게 코어가 돈다(`updateHeartbeat`). 방의 하트비트만 이 화면이 설 때 돈다(`roomHeartbeatHeld`).
    package func rummyScreenDidAppear() {
        let rummy = context.rummy
        isRummyScreenVisible = true
        rummy.roomHeartbeatHeld = false
        if rummyLeftByTabNotice != nil { rummyTabLeftNoticeSeen = true }
        // 화면이 내려간 사이(방장의 탭 재선택) 판이 시작되면 거둘 뷰가 없었다 — 틀린 글자로 되살리지 않는다.
        if rummyDeparturePrompt != nil, GamesRummyExit.decision(rummy) != .confirmCloseRoom { cancelRummyDeparture() }
        syncRummyHiddenPeers()
        #if DEBUG
        demoRummyRoute?.prepare(rummy)
        rummy.openWindow(focusMatchID: demoRummyRoute?.focusMatchID)
        #else
        rummy.openWindow(focusMatchID: nil)
        #endif
        if isAppActive { rummy.setWindowVisible(true) }
    }

    /// 아잉 큐브 화면이 사라졌다(뒤로 · 다른 탭으로 · 로그아웃).
    ///
    /// **기권이 아니다** — 이 신호로는 요청이 한 건도 나가지 않는다. 방을 떠나는 판단은 사람의 행동을 보는 문(`rummyDepartureAllowed`)이 먼저 했다: 이 신호는 목적지가 다시 세워질 때도 온다.
    /// ★ 끝난 판은 **여기서 접는다**: 폰에서 화면을 떠나는 것은 맥의 '창을 닫았다'다. 안 접으면 다시 들어올 때 로비가 아니라 그 결과가 다시 선다(테트리스 `windowDidClose` 와 같은 까닭).
    ///   `phase == .finished` 일 때만 부른다(쓰기가 아니라 접기 + 로비 조회 한 번이다). 진행 중인 판은 그대로 남는다.
    package func rummyScreenDidDisappear() {
        guard isRummyScreenVisible else { return }
        isRummyScreenVisible = false
        rummyFinalBoardMatchID = nil
        let rummy = context.rummy
        rummy.setWindowVisible(false)
        rummy.roomHeartbeatHeld = true
        if rummy.phase == .finished { rummy.dismissResult() }
        if rummy.rulesShown { rummy.rulesShown = false }
        if rummyTabLeftNoticeSeen { rummyLeftByTabNotice = nil }
        rummyTabLeftNoticeSeen = false
    }

    // MARK: 아잉 큐브 방을 떠나는 문

    /// 사용자 답(운영판 '폰 아잉 큐브: 방에서 탭으로 나가도 자리를 남길까요?'): **"맥처럼 방을 나가기"** — 모르는 사이 판돈이 걷히지 않게.
    ///
    /// | 지금(`RummyCloseDecision`)        | 이 문                                     | 맥의 같은 자리       |
    /// |---------------------------------|-----------------------------------------|---------------------|
    /// | `.leaveRoom`(손님)               | 곧바로 간다 + 뒤에서 나간다                 | 창이 닫히고 방 나가기 |
    /// | `.confirmCloseRoom`(방장)        | 멈추고 묻는다 — 수락하면 나간 뒤 간다          | "방이 닫혀요" 확인   |
    /// | `.confirmForfeit`(판 중)          | 그냥 간다 — 90초 규칙 그대로, 기권 아님        | (창 닫기와 다른 일)   |
    /// | `.close`(로비·결과·놀던 기기)       | 그냥 간다 — 아무것도 안 보낸다               | 그냥 닫힘           |
    ///
    /// 앱을 내리는 것(`appDidEnterBackground`)과 로그아웃은 이 문을 지나지 않는다. 화면이 안 보이면 떠나는 것이 아니다.
    private func rummyDepartureAllowed(resume: @escaping @MainActor () -> Void) -> Bool {
        guard isRummyScreenVisible, !isRummyDepartureRunning else { return true }
        let rummy = context.rummy
        switch GamesRummyExit.decision(rummy) {
        case .close, .confirmForfeit:
            return true
        case .leaveRoom:
            startRummyDeparture(saysTabLeft: true)
            return true
        case .confirmCloseRoom:
            rummyDepartureResume = resume
            if rummy.rulesShown { rummy.rulesShown = false }
            askRummyDeparture()
            return false
        }
    }

    /// 방장에게 묻는다. 이미 물어 둔 값에 또 오면 그 알림이 **안 떠 있는** 것이다(떠 있으면 탭 막대가 눌리지 않는다 — 다른 시트 위라 SwiftUI 가 조용히 안 띄웠다).
    /// 같은 값을 다시 적으면 SwiftUI 는 바뀐 줄 모르고 탭만 계속 막힌다 — 한 번 내렸다 올려 다시 띄운다.
    private func askRummyDeparture() {
        guard rummyDeparturePrompt != nil else {
            rummyDeparturePrompt = .confirmCloseRoom
            return
        }
        rummyDeparturePrompt = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.1))
            guard let self, self.rummyDepartureResume != nil else { return }
            self.rummyDeparturePrompt = .confirmCloseRoom
        }
    }

    /// 화면의 [나가기](손님) · [방 닫고 나가기](방장 — 이미 물었다). 탭 이탈과 같은 길이라 못 닿으면 방에 남아 사실을 말한다 — 접어 버리면 로비가 보이는데 서버엔 자리가 있다.
    package func leaveRummyRoomFromScreen() {
        guard !isRummyDepartureRunning else { return }
        switch GamesRummyExit.decision(context.rummy) {
        case .leaveRoom, .confirmCloseRoom:
            startRummyDeparture(saysTabLeft: false)
        case .close, .confirmForfeit:
            break
        }
    }

    private func startRummyDeparture(saysTabLeft: Bool, onLeft: (@MainActor () -> Void)? = nil) {
        rummyDepartureTask?.cancel()
        isRummyDepartureRunning = true
        rummyDepartureTask = Task { @MainActor [weak self] in
            await self?.runRummyDeparture(saysTabLeft: saysTabLeft, onLeft: onLeft)
        }
    }

    /// 보낸다. 화면 밖이면 서버가 확인할 때까지 몇 번 더 보낸다 — 방을 보고 있으면 그 사람에게 맡긴다(안내 줄이 서 있다).
    /// `onLeft`(수락한 방장이 가려던 곳)는 **화면이 아직 설 때만** 간다: 나가는 중에 사람이 다른 탭으로 갔으면 그 탭이 답이다.
    /// 로비 조회를 기다리지 않고 간다 — 그 조회가 늦으면 사람이 빈 로비에 묶인다.
    private func runRummyDeparture(saysTabLeft: Bool, onLeft: (@MainActor () -> Void)?) async {
        let rummy = context.rummy
        let generation = context.generation
        var outcome = await sendRummyDeparture(saysTabLeft: saysTabLeft)
        if outcome == .left, generation == context.generation, isRummyScreenVisible { onLeft?() }
        for delay in rummyLeaveRetrySeconds where outcome == .notConfirmed {
            let roomID = rummy.match?.id
            guard !isRummyScreenVisible else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, generation == context.generation, !isRummyScreenVisible,
                  rummy.phase == .room, rummy.match?.id == roomID else { return }
            isRummyDepartureRunning = true
            outcome = await sendRummyDeparture(saysTabLeft: saysTabLeft)
        }
        if outcome == .left, generation == context.generation { await GamesRummyExit.settleAfterLeaving(rummy) }
    }

    /// 한 번 보내고 결과를 사람에게 남긴다(안내 줄 · 카드). 부르는 쪽이 `isRummyDepartureRunning` 을 세운다.
    private func sendRummyDeparture(saysTabLeft: Bool) async -> RummyRoomDeparture {
        let rummy = context.rummy
        let generation = context.generation
        let outcome = await rummy.departRoom(reason: .windowClosed)
        // 그새 로그아웃했으면 다음 사람에게 남길 말이 없다.
        guard generation == context.generation else { return outcome }
        isRummyDepartureRunning = false
        switch outcome {
        case .left:
            rummyUnconfirmedLeaveRoomID = nil
            rummyLeftByTabNotice = saysTabLeft ? GamesRummyText.tabLeftNotice : nil
            // 보고 있는 사람은 이미 봤다 — 다음에 떠날 때 지운다.
            rummyTabLeftNoticeSeen = saysTabLeft && isRummyScreenVisible
        case .notConfirmed:
            rummyUnconfirmedLeaveRoomID = rummy.match?.id
        case .startedMatch:
            rummyUnconfirmedLeaveRoomID = nil
        }
        return outcome
    }

    /// 로비를 떠나 새 방·판에 들었다 — 지난 방 이야기를 다음 로비까지 끌고 가지 않는다.
    package func forgetRummyLeftByTabNotice() {
        rummyLeftByTabNotice = nil
        rummyTabLeftNoticeSeen = false
    }

    /// 방장의 [방 닫고 나가기]. **지금 판단으로 간다**(묻는 사이 판이 시작됐으면 나가지도 옮기지도 않는다 · 방이 없어졌으면 보낼 것 없이 간다).
    /// 서버가 확인하지 않으면 옮기지 않는다 — 방이 안 닫혔는데 다른 탭으로 가면 다른 사람들이 빈 방에서 기다린다. 방 화면의 안내 줄이 말하고, 다시 누를 수 있다.
    package func confirmRummyDeparture() {
        guard rummyDeparturePrompt != nil else { return }
        let resume = rummyDepartureResume
        rummyDeparturePrompt = nil
        rummyDepartureResume = nil
        guard !isRummyDepartureRunning else { return }
        switch GamesRummyExit.decision(context.rummy) {
        case .close:
            resume?()
        case .confirmForfeit:
            break
        case .leaveRoom, .confirmCloseRoom:
            startRummyDeparture(saysTabLeft: true, onLeft: resume)
        }
    }

    /// 방장의 [계속하기] — 아무것도 안 보내고 방에 남는다. 판이 시작돼 거둘 때도 부른다.
    package func cancelRummyDeparture() {
        rummyDeparturePrompt = nil
        rummyDepartureResume = nil
    }

    /// 나가기를 서버가 확인하지 않은 그 방에 아직 앉아 있다.
    package var isRummyLeaveUnconfirmed: Bool {
        guard let id = rummyUnconfirmedLeaveRoomID else { return false }
        return context.rummy.phase == .room && context.rummy.match?.id == id
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
        // 미니게임: 끝나지 않은 판이 **돌고 있으면** 켠다. **지금까지 미니게임은 아예 보호받지 않았다** — 플래피는 한 판이
        // 30초 남짓이라 자동잠금(최소 30초)에 닿을 일이 없어 드러나지 않았을 뿐이다. 자동잠금은 판을 얼리고, 조각을 세워 두고
        // 생각하는 무입력 구간이 있는 게임(테트리스)이 들어오면 그 자리에서 판이 끊긴다.
        //
        // ★ **정지 중에는 끈다**(폰 1.0.16). 정지 카드를 띄운 채 폰을 내려놓으면 화면이 켜진 채로 남는다 — 그 판은 이미 얼어 있어
        // 자동잠금으로 더 잃을 것이 없다(상한은 벽시계라 잠겨 있어도 센다).
        //
        // ★ **타이밍 바만 뺀다.** 그 판은 **스스로 끝나지 않는다** — `phase` 가 탭을 받을 때까지 `.running` 에 머문다
        // (`TimingBarGame.isPlaying`). 그래서 판을 켜 둔 채 자리를 뜨면 화면이 **영원히** 켜져 있다. 자동잠금이 그
        // 유일한 상한이었고, 여기에 타이밍 바를 넣으면 그 상한이 사라진다. 플래피(새가 떨어져 끝난다)와 테트리스
        // (쌓여서 탑아웃한다)는 방치해도 엔진이 판을 끝내므로 안전하다. 새 게임을 더할 때 이 성질을 확인할 것.
        //   · 길건너(폰 1.0.15): **확인했다 — 안전하다.** 가만히 두면 `CrossyGame.idleLimit` 9초에 "놓쳤어요"로 끝난다
        //     (카메라가 혼자 앞으로 가서 아잉이를 화면 아래로 밀어낸다). 그래서 타이밍 바 쪽이 아니라 이쪽이다.
        if let controller = miniGames.controller, controller.isPlaying, !controller.isFrozen, controller.kind != .timingBar { return true }
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
        // ★ 같은 계정의 **다른 기기**가 두는 판(코어 `playingElsewhere` · 0.3.69)은 켜지 않는다 — 이 폰에는 판 루프도
        //   보고도 없어 자동잠금이 닿아도 지는 사람이 없다. 켜 두면 남의 기기 판이 끝날 때까지(최대 8분) 배터리만 탄다.
        if let match = context.tetris.match, !match.isFinished, !context.tetris.playingElsewhere { return true }
        // 아잉 큐브: 이 기기가 쥔 판에서 내 자리가 playing 이면 **어느 화면에 있든** 켠다(차례 60초 · 시간 초과 3번이면 기권이다).
        // 같은 계정의 다른 기기가 하는 판(놀던 기기)은 켜지 않는다 — 지는 사람이 없는데 배터리만 탄다(위 테트리스와 같은 근거).
        if holdsRummyMatch { return true }
        // 아잉 뒤집기: 이 기기가 연 1:1 판이면 **어느 화면에 있든** 켠다(한 수 30초 — 자동잠금이 닿으면 소켓이 내려가 상대 수를 모르고, 서버가 대신 둔
        // 수가 연속 3번이면 판돈째 진다). AI 연습은 화면이 보일 때만(떠나면 코어가 사람 시계를 멈춘다 — 오목·체스 AI 와 같다).
        // ★ 같은 계정의 **다른 기기**(맥)가 두는 판은 켜지 않는다 — 폰 스토어는 로비 `active_match_id` 로 그 판을 읽어 들고 있을 뿐, 이 폰에서 지는 사람이
        //   없는데 판이 끝날 때까지 배터리만 탄다(테트리스 `playingElsewhere` · 큐브 `holdsRummyMatch` 와 같은 근거). 장부는 신청·수락·착수가 적는다.
        if let match = context.reversi.match, !match.isFinished {
            if match.isAI {
                if isReversiScreenVisible { return true }
            } else if context.reversi.ownsMatch(match.id) {
                return true
            }
        }
        // 1:1 길건너: 이 기기가 두는 판이면 켠다(테트리스처럼 실시간 판 — 자동잠금이면 판 루프가 잔다).
        if context.crossyDuel.holdsActivity { return true }
        // 1:1 알까기: 화면이 떠 있고 내 판이 흐르면 켠다(한 수 30초 — 화면이 꺼지면 차례를 넘겨 세 번이면 진다).
        if isAlkkagiScreenVisible, hasLiveAlkkagiMatch { return true }
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
            case .crossy: kind = .crossy
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

    /// 체스·**테트리스**·아잉 큐브 판이 흐르는 동안 들어온 오목 링크(푸시·위젯)를 **열지 않는다** — 게임 탭 첫 화면에 세운다.
    ///
    /// 카드만 막으면 이 길이 남는다: 오목 로비의 [수락]은 `GomokuPhoneChallengeGate`(보낸 신청용)를 지나지 않아 클라 게이트가
    /// 없다. 서버는 그 수락을 `busy` 로 거절하지만(오목 수락도 `chess__busy` 를 본다 — `GamesBusyGame` 머리말) 그 문구는 어느
    /// 게임 때문인지 말하지 않는다. 그래서 **화면까지 가지 않고** 첫 화면에 세운다 — 거기서는 오목 카드가 그 까닭을 말한다.
    ///
    /// ★ 부르는 자리의 가드는 `gomokuEntryBlock` 하나다 — 그 값이 오목 말고 다른 판(체스·테트리스·아잉 큐브)을 이미
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

    /// 아잉 뒤집기 판이 막 열렸다(내 신청이 수락됨 · 내가 수락함 · 앱을 다시 켜니 이 기기가 연 판이 진행 중) — 아잉 뒤집기 화면을 연다.
    ///
    /// 체스와 **같은 조각 셋**이다(`AingRoute` 에 리버시 가지가 없다 — `CheckMobileShared` 의 열거라 더하면 `IntegrationContractTests` 의
    /// '장면 폴더 예외'가 빨개진다. 푸시도 없다 — 결정 "채팅·푸시 없음"). 게임 탭을 고르고 · 쌓인 화면을 비우고 · 리버시를 쌓는다.
    /// ★ **이 기기가 연 판에서만** 불린다 — 코어가 `deviceLedger` 로 가른다(`noteMatchProgress`). 같은 계정 맥의 판을 로비로 읽어도 끌려 나오지 않는다.
    /// ★ `!isReversiScreenVisible` 가드가 화면을 두 번 쌓는 것을 막는다(`reversiScreenDidAppear` 가 깃발을 먼저 적는 까닭).
    private func presentReversiScreen() {
        guard isAppActive, context.session.isSignedIn, !isReversiScreenVisible else { return }
        let router = context.router
        router.selectedTab = .games
        router.popToRoot(.games)
        router.push(GamesDestination.reversi, on: .games)
    }

    /// 아잉 큐브 판이 막 열렸다(방에서 시작됨 · 앱을 다시 켜니 진행 중인 판) — 큐브 화면을 연다.
    ///
    /// ★ **이 기기가 손댄 판에서만 연다.** 같은 계정의 맥이 판을 하는 동안 폰이 로비로 그 판을 읽으면 코어가 `announce` → 이 문을 부른다.
    ///   막지 않으면 앱을 켠 사람이 보던 탭에서 끌려 나와 남의 기기 판 앞에 선다(폰은 읽기만 하는 판이다 — SPEC-v2 §6). 카드의 "진행 중" 칩이 그 사실을 말한다.
    /// ★ `!isRummyScreenVisible` 가드가 화면을 두 번 쌓는 것을 막는다(`rummyScreenDidAppear` 가 깃발을 먼저 적는 까닭).
    private func presentRummyScreen() {
        guard isAppActive, context.session.isSignedIn, !isRummyScreenVisible,
              context.rummy.isEngagedInCurrentMatch else { return }
        let router = context.router
        router.selectedTab = .games
        router.popToRoot(.games)
        router.push(GamesDestination.rummy, on: .games)
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
