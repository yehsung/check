import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// 한 판(리그·토큰·미니게임)의 불러오기 상태. 맥의 `…Loaded / …Loading / …Failed` 세 깃발과 같은 뜻이다 —
/// "로드 전"·"진행 중"·"실패"를 가르지 않으면 빈 목록 자리에 엉뚱한 문구가 뜬다(맥 TokenBoardEmptyMessage 주석의 회귀).
package struct RankingsLoadState: Equatable, Sendable {
    /// 한 번이라도 성공했다(빈 목록이어도).
    package var hasLoaded = false
    package var isLoading = false
    /// 마지막 조회가 실패로 끝났다.
    package var hasFailed = false
    /// 마지막 성공 시각(스토어 시계). 신선도 판정에 쓴다.
    package var loadedAt: Date?

    package init() {}
}

/// 순위 탭 스토어(SPEC-ios §3.4) — 팀 리그(`team_weekly_leaderboard`) · AI 토큰(`token_usage_board`, 달 넘기기) ·
/// 미니게임(`minigame_board` + `minigame_yesterday_winner`). 전부 **읽기**다.
///
/// 수명(기반 자리 API)
/// - `init(context:)` 네트워크 없음 · `appDidBecomeActive()` 탭이 보이면 낡은 판을 다시 읽는다 · `appDidEnterBackground()` ·
///   `reset()` 계정에 묶인 값 전부 비움 · `badgeCount` 0.
/// - 탭 화면이 `tabDidAppear()`/`tabDidDisappear()` 를 부른다. **보이지 않는 탭은 서버를 두드리지 않는다**(맥 Q7 — 닫힌 팝오버가
///   30초마다 리그 RPC 를 두드리던 계측과 같은 이유). 주기 폴링은 없다 — 탭 표시·앱 active·세그먼트 전환·당겨서 새로고침이 전부다.
///
/// 늦은 응답 가드(맥 performLoad… 관용): 세대(로그아웃) · 요청 순번(같은 판을 연달아 부르면 마지막 것만) · 보고 있는 달/게임 종류.
@MainActor
@Observable
package final class RankingsStore {
    @ObservationIgnored package let context: MobileContext

    /// 지금 보이는 세그먼트.
    package private(set) var board: AingRoute.RankingsBoard = .league
    package private(set) var isTabVisible = false

    // MARK: 팀 리그
    /// 서버가 준 전체 목록(1인당 평균 내림차순). 표시 목록은 `leagueDisplay`(0시간 팀 숨김 · 내 팀은 유지).
    package private(set) var league: [TeamLeaderboardEntry] = []
    package private(set) var leagueState = RankingsLoadState()

    // MARK: AI 토큰
    /// 보고 있는 달(KST 'YYYY-MM'). 기본은 이번 달.
    package private(set) var tokenMonth: String
    package private(set) var tokenBoard: [TokenBoardEntry] = []
    package private(set) var tokenState = RankingsLoadState()
    /// 내 토큰 사용량 공개 여부(내 행 "비공개" 칩). nil = 모른다(칩을 그리지 않는다).
    package private(set) var myTokenUsagePublic: Bool?

    // MARK: 미니게임
    package private(set) var miniGameKind: MiniGameKind = .timingBar
    package private(set) var miniGameBoard: [MiniGameBoardEntry] = []
    package private(set) var miniGameWinner: MiniGameWinner?
    package private(set) var miniGameState = RankingsLoadState()

    /// 이만큼 지난 판은 탭 표시·active 때 다시 읽는다.
    package nonisolated static let staleSeconds: TimeInterval = 30

    @ObservationIgnored private var leagueSerial = 0
    @ObservationIgnored private var tokenSerial = 0
    @ObservationIgnored private var miniGameSerial = 0
    /// 사용자가 달을 옮기지 않았으면 true — 앱을 켜 둔 채 달이 바뀌면 새 달로 따라간다(맥 WorkTimerStore.swift:2003 의 결함).
    @ObservationIgnored private var tokenMonthFollowsCurrent = true
    /// 나 탭이 공개 설정 저장 성공을 알린 횟수 — 토큰 판 조회가 떠날 때 찍고, 도착했을 때 달라졌으면 그 응답의 공개 여부는 저장 전 값이다.
    @ObservationIgnored private var privacyNoteSerial = 0
    @ObservationIgnored private var inflight: [Task<Void, Never>] = []

    package init(context: MobileContext) {
        self.context = context
        self.tokenMonth = TokenUsageMonthKey.current(context.clock.now())
    }

    // MARK: - 자리 API

    package func appDidBecomeActive() {
        guard isTabVisible else { return }
        refreshIfStale()
    }

    package func appDidEnterBackground() {}

    package func reset() {
        for task in inflight { task.cancel() }
        inflight.removeAll()
        leagueSerial &+= 1
        tokenSerial &+= 1
        miniGameSerial &+= 1
        league = []
        leagueState = RankingsLoadState()
        tokenMonth = TokenUsageMonthKey.current(context.clock.now())
        tokenMonthFollowsCurrent = true
        tokenBoard = []
        tokenState = RankingsLoadState()
        myTokenUsagePublic = nil
        miniGameBoard = []
        miniGameWinner = nil
        miniGameState = RankingsLoadState()
        board = .league
        miniGameKind = .timingBar
    }

    package var badgeCount: Int { 0 }

    // MARK: - 화면 사건

    package func tabDidAppear() {
        isTabVisible = true
        refreshIfStale()
    }

    package func tabDidDisappear() {
        isTabVisible = false
    }

    /// 딥링크(`aingcheck://rankings/<board>`).
    package func open(_ route: AingRoute) {
        guard case .rankings(let target) = route else { return }
        select(board: target)
    }

    package func select(board target: AingRoute.RankingsBoard) {
        guard board != target else {
            refreshIfStale()
            return
        }
        board = target
        refreshIfStale()
    }

    /// 당겨서 새로고침 · [다시 시도] — 지금 세그먼트를 신선도와 무관하게 다시 읽는다.
    package func refresh() async {
        switch board {
        case .league: await loadLeague()
        case .tokens: await loadTokens()
        case .minigame: await loadMiniGame()
        }
    }

    /// 지금 세그먼트가 한 번도 안 읽혔거나 낡았으면 다시 읽는다(Task 발사 — 화면 사건에서 부른다).
    package func refreshIfStale() {
        guard context.session.isSignedIn else { return }
        rollTokenMonthIfNeeded()
        let state: RankingsLoadState
        switch board {
        case .league: state = leagueState
        case .tokens: state = tokenState
        case .minigame: state = miniGameState
        }
        guard !state.isLoading else { return }
        if let loadedAt = state.loadedAt, context.clock.now().timeIntervalSince(loadedAt) < Self.staleSeconds, !state.hasFailed {
            return
        }
        launch { [weak self] in await self?.refresh() }
    }

    // MARK: - 팀 리그

    /// 표시 목록(맥 `filteredForDisplay` — 이번 주 0시간 팀은 숨기되 내 팀은 남긴다, 평균 내림차순).
    package var leagueDisplay: [TeamLeaderboardEntry] {
        league.filteredForDisplay(myTeamID: myTeamID)
    }

    package var myTeamID: String? { context.session.profile?.teamID }

    package func loadLeague() async {
        guard context.session.isSignedIn else { return }
        leagueSerial &+= 1
        let serial = leagueSerial
        let generation = context.generation
        leagueState.isLoading = true
        leagueState.hasFailed = false
        defer { if serial == leagueSerial { leagueState.isLoading = false } }
        do {
            let service = context.service
            let entries = try await context.withMobileSessionRetry { session in
                try await service.fetchTeamLeaderboard(accessToken: session.accessToken)
            }
            guard generation == context.generation, serial == leagueSerial else { return }
            let sorted = entries.sortedByAverageDescending()
            if league != sorted { league = sorted }
            leagueState.hasLoaded = true
            leagueState.hasFailed = false
            leagueState.loadedAt = context.clock.now()
        } catch {
            guard generation == context.generation, serial == leagueSerial else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            leagueState.hasFailed = true
        }
    }

    // MARK: - AI 토큰

    package var myUserID: String? { context.session.userID }

    /// 오늘(KST) 키 — 행의 "오늘 +N" 판정.
    package var todayKey: String { TokenUsageDayKey.current(context.clock.now()) }

    /// 보고 있는 달이 이번 달인가(› 비활성 == 이번 달 — 맥 `isCurrentMonth`).
    package var isCurrentTokenMonth: Bool {
        !TokenBoardMonthNavigator.canStepForward(from: tokenMonth, now: context.clock.now())
    }

    package var tokenTitle: String {
        RankingsText.tokenTitle(month: tokenMonth, now: context.clock.now())
    }

    /// 달 이동(-1 과거 · +1 미래). 미래는 이번 달로 막힌다 — 값이 그대로면 요청도 없다(맥 stepTokenBoardMonth).
    package func stepTokenMonth(by delta: Int) {
        let now = context.clock.now()
        let next = TokenBoardMonthNavigator.step(tokenMonth, by: delta, now: now)
        guard next != tokenMonth else { return }
        tokenSerial &+= 1
        tokenMonth = next
        tokenMonthFollowsCurrent = next == TokenUsageMonthKey.current(now)
        // 이전 달 행이 '이번 달인 척' 남지 않게 비우고 로드 전으로 되돌린다.
        tokenBoard = []
        tokenState = RankingsLoadState()
        tokenState.isLoading = true
        launch { [weak self] in await self?.loadTokens() }
    }

    package func loadTokens() async {
        guard context.session.isSignedIn else { return }
        rollTokenMonthIfNeeded()
        tokenSerial &+= 1
        let serial = tokenSerial
        let month = tokenMonth
        let generation = context.generation
        let privacyStamp = privacyNoteSerial
        tokenState.isLoading = true
        tokenState.hasFailed = false
        defer { if serial == tokenSerial { tokenState.isLoading = false } }
        let service = context.service
        // 공개 여부는 독립 실패(못 읽으면 칩만 안 그린다). GET 한 번 — focus_mode 칸도 딸려 오지만 읽기만 하고 버린다(R9: PATCH 금지).
        async let privacy: Bool? = try? await context.withMobileSessionRetry { session in
            try await service.fetchTokenUsageSettings(accessToken: session.accessToken, userID: session.userID).isPublic
        }
        do {
            let rows = try await context.withMobileSessionRetry { session in
                try await service.fetchTokenBoard(accessToken: session.accessToken, month: month)
            }
            let isPublic = await privacy
            guard generation == context.generation, serial == tokenSerial, month == tokenMonth else { return }
            let entries = rows.toTokenBoardEntries().sortedByTotalDescending()
            if tokenBoard != entries { tokenBoard = entries }
            // 조회가 떠 있는 사이 나 탭 저장이 끝났으면(칩이 이미 새 값) 옛 공개 여부로 되돌리지 않는다.
            if let isPublic, privacyStamp == privacyNoteSerial { myTokenUsagePublic = isPublic }
            tokenState.hasLoaded = true
            tokenState.hasFailed = false
            tokenState.loadedAt = context.clock.now()
        } catch {
            _ = await privacy
            guard generation == context.generation, serial == tokenSerial, month == tokenMonth else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            tokenState.hasFailed = true
        }
    }

    /// 나 탭에서 공개 설정을 바꿨다(서버 저장 성공 뒤) — 내 행 "비공개" 칩을 바로 맞춘다.
    package func noteTokenUsagePublic(_ isPublic: Bool) {
        privacyNoteSerial &+= 1
        myTokenUsagePublic = isPublic
    }

    private func rollTokenMonthIfNeeded() {
        let current = TokenUsageMonthKey.current(context.clock.now())
        guard tokenMonthFollowsCurrent, tokenMonth != current else { return }
        tokenMonth = current
        tokenBoard = []
        tokenState = RankingsLoadState()
    }

    // MARK: - 미니게임

    package func select(miniGame kind: MiniGameKind) {
        guard kind != miniGameKind else { return }
        miniGameKind = kind
        miniGameSerial &+= 1
        miniGameBoard = []
        miniGameWinner = nil
        miniGameState = RankingsLoadState()
        miniGameState.isLoading = true
        launch { [weak self] in await self?.loadMiniGame() }
    }

    /// 내 오늘 순위(1부터). 없으면 nil.
    package var myMiniGameRank: Int? {
        guard let me = myUserID, let index = miniGameBoard.firstIndex(where: { $0.userID == me }) else { return nil }
        return index + 1
    }

    package var miniGamePlayers: Int { miniGameBoard.count }

    /// 오늘 순위 + 어제 1등. 두 조회는 **독립 실패**(맥 performLoadMiniGameBoard). 표·함수가 없는 서버(PGRST202)는 실패가 아니라
    /// "아직 없음"으로 조용히 접는다.
    package func loadMiniGame() async {
        guard context.session.isSignedIn else { return }
        miniGameSerial &+= 1
        let serial = miniGameSerial
        let kind = miniGameKind
        let generation = context.generation
        miniGameState.isLoading = true
        miniGameState.hasFailed = false
        defer { if serial == miniGameSerial { miniGameState.isLoading = false } }
        let service = context.service
        do {
            let entries = try await context.withMobileSessionRetry { session in
                try await service.fetchMiniGameBoard(accessToken: session.accessToken, kind: kind, day: nil)
            }
            guard generation == context.generation, serial == miniGameSerial, kind == miniGameKind else { return }
            let sorted = entries.sortedForMiniGameBoard()
            if miniGameBoard != sorted { miniGameBoard = sorted }
            miniGameState.hasLoaded = true
            miniGameState.hasFailed = false
            miniGameState.loadedAt = context.clock.now()
        } catch {
            guard generation == context.generation, serial == miniGameSerial, kind == miniGameKind else { return }
            switch AuthErrorRules.classify(error) {
            case .cancelled:
                return
            default:
                if case SupabaseWorkServiceError.databaseSchemaMissing = error {
                    miniGameState.hasLoaded = true
                    miniGameState.loadedAt = context.clock.now()
                } else {
                    miniGameState.hasFailed = true
                }
                return
            }
        }
        let winner = try? await context.withMobileSessionRetry { session in
            try await service.fetchMiniGameYesterdayWinner(accessToken: session.accessToken, kind: kind)
        }
        guard generation == context.generation, serial == miniGameSerial, kind == miniGameKind else { return }
        if miniGameWinner != winner { miniGameWinner = winner }
    }

    // MARK: - 내부

    private func launch(_ body: @escaping @MainActor () async -> Void) {
        inflight.removeAll { $0.isCancelled }
        let task = Task { @MainActor in await body() }
        inflight.append(task)
        if inflight.count > 8 { inflight.removeFirst(inflight.count - 8) }
    }
}
