import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 게임 탭에서 쌓는 화면(경로 원소).
package enum GamesDestination: Hashable, Sendable {
    case miniGame(MiniGameKind)
    case gomoku
    case chess
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
/// 탭 배지 = 받은 오목 신청 수(만료 안 된 것 — 체스는 아직 안 센다, `badgeCount` 주석). 받은 신청은 인박스가 채운다 —
/// 계기는 앱 active(60초 스로틀) · 실시간 'gomoku' 신호(기반 배선) · 오목 화면.
///
/// **한 사람 한 판(B8)은 양방향**이다 — 두 게임 입구가 한 화면에 있으므로 `chessEntryBlock`·`gomokuEntryBlock` 둘을
/// 그려야 한다(까닭은 `GamesBusyGame`).
@MainActor
@Observable
package final class GamesStore {
    @ObservationIgnored package let context: MobileContext
    package let miniGames: GamesMiniGameHub

    /// 오목 화면이 지금 떠 있다(내비게이션에 올라와 보인다).
    package private(set) var isGomokuScreenVisible = false
    /// 체스 화면이 지금 떠 있다(오목과 같은 뜻 — 코어의 '창 표시'를 폰 화면 수명으로 옮긴 값).
    package private(set) var isChessScreenVisible = false
    /// 앱이 active 다(로그인 상태에서 appDidBecomeActive ~ appDidEnterBackground).
    package private(set) var isAppActive = false
    /// 오목 화면을 열 때 보여 줄 신청·판 id(딥링크 `gomoku/invite/<id>` · `gomoku/match/<id>`). 화면이 한 번 꺼내 쓴다.
    /// 화면이 **이미 보이면** 여기 남기지 않는다(`routeStep(for:)` 이 코어에 바로 넘긴다).
    package var pendingGomokuFocusID: String?

    /// 데모 전용: 시작 라우트가 체스 장면(`games/chess/…`)이라 게임 탭이 체스를 쌓아야 한다.
    /// 앱 모델이 세우고(`MobileAppModel.openDemoRouteIfNeeded`) 게임 탭이 **한 번** 꺼내 쓴다.
    /// `#if DEBUG` 로 감싸지 않은 까닭: 이 파일은 플랫폼·구성 분기가 없어야 맥 스위트가 값으로 잴 수 있다
    /// (Bool 한 칸이고, 세우는 자리가 데모뿐이라 Release 에서는 영원히 false 다).
    package var pendingDemoChessScreen = false

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
        guard isChessScreenVisible else { return }
        if chess.isWindowVisible {
            chess.windowOcclusionDidChange(visible: true)
        } else {
            chess.windowDidShow()
        }
        Task { await chess.catchUp() }
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
    }

    package func reset() {
        miniGames.reset()
        isGomokuScreenVisible = false
        isChessScreenVisible = false
        pendingGomokuFocusID = nil
        pendingDemoChessScreen = false
        syncAIThinker()
    }

    /// 데모 체스 장면 깃발을 **한 번** 꺼낸다(꺼내면 비운다 — 뒤의 무관한 진입에 쓰이지 않게).
    /// 오목 `pendingGomokuFocusID` 가 같은 자리에서 데인 것과 같은 규약이다.
    package func consumePendingDemoChessScreen() -> Bool {
        guard pendingDemoChessScreen else { return false }
        pendingDemoChessScreen = false
        return true
    }

    /// 코어 체스 스토어 줄임(= `context.chess`). 화면·다른 레인이 읽는 자리는 **두 이름이 같은 인스턴스**다.
    package var chess: ChessStore { context.chess }

    /// 탭 배지: 만료 안 된 받은 오목 신청 수.
    ///
    /// ⚠️ **체스 신청은 아직 안 센다.** 체스는 받은함 RPC 가 없어 받은 신청을 `chess_lobby` 로만 알고(머리말 ⑪),
    /// 그 조회는 허브·체스 화면에서만 나간다 — 배지에 넣으면 "60초 TTL 짜리 숫자가 30초 스로틀로 갱신되는"
    /// 꼴이 되어 없는 신청을 가리키거나 있는 신청을 놓친다. 체스 신청을 배지에 싣는 날은 그 신선도를
    /// 어디서 받을지(푸시 · 실시간 `chessSignal`)를 먼저 정해야 한다.
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

    /// 체스 입구를 막는 까닭(없으면 nil). 오목 판이 흐르면 체스를 신청·수락할 수 없다 —
    /// 서버도 같은 판정을 한다(`chess__busy`), 그래서 이 쪽은 **클라가 사실을 먼저 그리는 것**이다.
    package var chessEntryBlock: GamesBusyGame? { hasLiveGomokuMatch ? .gomoku : nil }

    /// 오목 입구를 막는 까닭(없으면 nil). ★ **이 방향은 클라밖에 막는 데가 없다** — 서버의 오목 게이트는
    /// 체스를 모른다(`GamesBusyGame` 머리말). 안 막으면 체스 중인 사람이 오목을 수락해 체스를 시간패한다.
    package var gomokuEntryBlock: GamesBusyGame? { hasLiveChessMatch ? .chess : nil }

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
    package func gomokuScreenDidDisappear() {
        guard isGomokuScreenVisible else { return }
        isGomokuScreenVisible = false
        // 관전을 먼저 내린다(요청 없음). 뒤의 `windowDidHide` 는 **끝난** 관전만 내리므로 진행 중인 남의 판이 그대로 남았다.
        context.gomoku.stopWatching()
        context.gomoku.windowDidHide()
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
    package func chessScreenDidAppear() {
        let chess = context.chess
        isChessScreenVisible = true
        chess.openWindow(focusMatchID: nil)
        if isAppActive { chess.windowDidShow() }
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
    /// **내 판은 손대지 않는다.** 체스에는 `chess_leave` 가 없고(코어 `windowDidClose` 주석) 진행 중인 판은
    /// 서버에서 계속 흐른다 — 결과 화면인 채로 떠난 것도 "그 판에서 나갔다"가 아니다.
    package func chessScreenDidDisappear() {
        guard isChessScreenVisible else { return }
        isChessScreenVisible = false
        context.chess.stopWatching()
        context.chess.windowDidHide()
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

    /// 체스 판이 흐르는 동안 들어온 오목 링크(푸시·위젯)를 **열지 않는다** — 게임 탭 첫 화면에 세운다.
    ///
    /// 카드만 막으면 이 길이 남는다: 오목 로비의 [수락]은 `GomokuPhoneChallengeGate`(보낸 신청용)를 지나지 않아
    /// 아무 게이트도 없고, 서버의 오목 쪽 게이트는 체스를 모른다(`GamesBusyGame` 머리말). 그래서 **화면까지
    /// 가지 않는 것**이 지금 폰이 그 수락을 막는 유일한 방법이다. 첫 화면에서는 오목 카드가 그 까닭을 말한다.
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
