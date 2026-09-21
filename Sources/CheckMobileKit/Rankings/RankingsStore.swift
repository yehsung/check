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

    // ── 지난 6주 보기(v0.3.37 · 맥 WorkTimerStore 의 거울) ──
    /// 보고 있는 주(KST 월요일 'YYYY-MM-DD'). **오프셋이 아니라 절대 키다** — 오프셋은 '지금'에 매달려 있어
    /// 화면을 열어 둔 채 월요일 0시를 넘기면 같은 `1` 이 다른 주를 가리킨다(토큰 판이 'YYYY-MM' 을 드는 것과 같은 이유).
    package private(set) var leagueWeekKey: String
    /// 서버가 `p_week_offset` 을 아는가. false 면 주 이동 알약을 접는다. **조회마다 다시 판정한다**(기억하지 않는다 —
    /// 앱은 며칠씩 살아 있고 db push 는 그 사이 끝난다).
    package private(set) var leagueWeekOffsetSupported = true
    /// **그 주를 고른 시점의 '이번 주'.** 사용자가 고른 과거 주와 '이번 주 자체가 옮겨 간 것'을 가르는 유일한 값이다.
    /// 토큰 판의 `tokenMonthFollowsCurrent`(Bool)로는 안 된다 — 주는 창이 6주로 미끄러져 롤오버 때 **무조건** 스냅해야 한다
    /// (안 그러면 6주 밖으로 밀려 엉뚱한 주를 보여 준다).
    @ObservationIgnored private var leagueWeekAnchor: String

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
        // 주입 시계만 쓴다 — 테스트가 일요일 23:59 에서 시작한다(Date() 를 섞으면 그 창이 사라진다).
        let now = context.clock.now()
        self.tokenMonth = TokenUsageMonthKey.current(now)
        let currentWeek = TeamLeagueWeekNavigator.currentKey(now)
        self.leagueWeekKey = currentWeek
        self.leagueWeekAnchor = currentWeek
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
        leagueWeekKey = TeamLeagueWeekNavigator.currentKey(context.clock.now())
        leagueWeekAnchor = leagueWeekKey
        // 접힌 채 물려주면 db push 가 끝난 뒤에도 다음 계정이 화살표를 못 본다(맥과 같은 이유).
        leagueWeekOffsetSupported = true
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
        // 여는 길은 전부 이번 주로 떨어뜨린다(탭 진입 · 보드 전환 · 재진입) — 리그를 '여는' 동작에 과거 주가 따라오면
        // 6주 전 표가 이번 주인 척 앉아 있는다. 아이폰의 백그라운드 복귀(appDidBecomeActive)는 전화·알림 확인 같은
        // **비자발적** 사건이라 문이 아니다(맥 팝오버 재오픈에 대응하는 폰 동작은 이 탭 재진입이다).
        syncLeagueWeekToCurrent()
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
            // 이미 리그인 채로 다시 고르는 딥링크(`aingcheck://rankings/league`)도 명시적 "리그를 열어라"다.
            if target == .league { syncLeagueWeekToCurrent() }
            refreshIfStale()
            return
        }
        board = target
        if target == .league { syncLeagueWeekToCurrent() }
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
        // ① 롤오버가 먼저다 — 뒤집으면 아래 가드가 갱신을 영영 막아, 그 순간의 이번 주 숫자가 과거 주 문구를 달고 굳는다.
        rollLeagueWeekIfNeeded()
        let state: RankingsLoadState
        switch board {
        case .league:
            // ② 과거 주는 종료된 기록만 세므로 다시 물어도 같은 표다 — 주기 갱신은 이번 주에만.
            //    단 **실패한 과거 주는 예외**: 못 받은 것을 '안 변한다'로 접으면 MU5 계약에 리그 구멍이 난다.
            guard TeamLeagueWeekNavigator.isCurrentWeek(leagueWeekKey, now: context.clock.now()) || leagueState.hasFailed else { return }
            state = leagueState
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

    /// 표시 목록 + 문구가 필요한 사실 둘(맥 `leagueDisplay(myTeamID:)` 와 같은 자리). **계산값이라 `league` 와 어긋날 수 없고**,
    /// `myTeamMissing` 도 필터 전 원본에서 매번 다시 센다.
    package var leagueDisplayPage: TeamLeagueDisplay { league.leagueDisplay(myTeamID: myTeamID) }

    /// 표시 목록(이번 주 0시간 팀은 숨기되 내 팀은 남긴다, 평균 내림차순). 서명(배열)을 **유지한다** — 계약 테스트가 붙들고 있다.
    package var leagueDisplay: [TeamLeaderboardEntry] { leagueDisplayPage.entries }

    package var myTeamID: String? { context.session.profile?.teamID }

    /// 머리글·행·문구 함수가 **같은 '지금'** 을 본다(맥 `LeaderboardPanel.now` 와 같은 이유 — 머리글과 행이 서로 다른
    /// 말을 하던 결함을 재현하지 않는다).
    package var leagueNow: Date { context.clock.now() }

    package var leagueTitle: String { RankingsText.leagueTitle(week: leagueWeekKey, now: leagueNow) }
    package var leagueWeekName: String { RankingsText.leagueWeekName(week: leagueWeekKey, now: leagueNow) }
    package var isLeaguePastWeek: Bool { !TeamLeagueWeekNavigator.isCurrentWeek(leagueWeekKey, now: leagueNow) }
    package var canStepLeagueWeekBack: Bool { TeamLeagueWeekNavigator.canStepBack(from: leagueWeekKey, now: leagueNow) }
    package var canStepLeagueWeekForward: Bool { TeamLeagueWeekNavigator.canStepForward(from: leagueWeekKey, now: leagueNow) }
    /// 옛 서버(p_week_offset 모름)에서는 알약을 아예 그리지 않는다.
    package var showsLeagueWeekNavigation: Bool { leagueWeekOffsetSupported }

    /// 보던 주를 이번 주로 되돌린다. **요청은 부르는 쪽이 낸다** — 스냅이 스스로 로드를 걸면 스냅+스텝이 겹칠 때
    /// 버려지는 조회가 하나 생긴다.
    private func syncLeagueWeekToCurrent() {
        let current = TeamLeagueWeekNavigator.currentKey(context.clock.now())
        leagueWeekAnchor = current                      // 되돌릴 게 없어도 늘 되맞춘다(낡은 앵커는 다음 틱을 헛스냅시킨다)
        guard leagueWeekKey != current else { return }  // 같으면 행·상태를 건드리지 않는다(탭 재진입 깜빡임 방지)
        leagueSerial &+= 1                              // 떠 있는 과거 주 응답을 여기서 버린다
        leagueWeekKey = current
        league = []
        leagueState = RankingsLoadState()
    }

    /// 주 롤오버 되돌림(열어 둔 채 월요일 0시를 넘긴 경우). 사용자가 고른 과거 주는 건드리지 않는다 —
    /// 판정은 보고 있는 키가 아니라 **앵커**(그 주를 고른 시점의 이번 주)다.
    private func rollLeagueWeekIfNeeded() {
        guard leagueWeekAnchor != TeamLeagueWeekNavigator.currentKey(context.clock.now()) else { return }
        syncLeagueWeekToCurrent()
    }

    /// 주 이동(`-1` = ◂ 과거 · `+1` = ▸ 현재 쪽). 값이 안 바뀌면 요청도 없다(토큰 판 달 이동과 같은 규약).
    package func stepLeagueWeek(by delta: Int) {
        guard leagueWeekOffsetSupported else { return }   // 옛 서버: 알약은 이미 접혔지만 한 번 더 막는다
        rollLeagueWeekIfNeeded()                          // 경계를 막 넘은 ◂ 가 '옛 이번 주 − 1' 로 가지 않게
        let now = context.clock.now()
        let next = TeamLeagueWeekNavigator.step(leagueWeekKey, by: delta, now: now)
        guard next != leagueWeekKey else { return }
        leagueSerial &+= 1                                // 주 키를 바꾸는 모든 자리가 순번을 올린다(불변식)
        leagueWeekKey = next
        league = []                                       // 직전 주 행이 '그 주인 척' 남지 않게
        leagueState = RankingsLoadState()                 // hasLoaded=false 가 "그 주엔 근무한 팀이 없었어요"를 막는다
        leagueState.isLoading = true
        launch { [weak self] in await self?.loadLeague() }
    }

    package func loadLeague() async {
        guard context.session.isSignedIn else { return }
        rollLeagueWeekIfNeeded()                          // 당겨서 새로고침·[다시 시도]는 refreshIfStale 을 안 지난다
        leagueSerial &+= 1
        let serial = leagueSerial
        let weekKey = leagueWeekKey
        let weekOffset = TeamLeagueWeekNavigator.offset(forKey: weekKey, now: context.clock.now())
        let generation = context.generation
        leagueState.isLoading = true
        leagueState.hasFailed = false
        // defer 는 **순번만** 본다 — 여기에 주 키를 넣으면 아래 '서버 주 채택' 갈래에서 "불러오는 중"이 영영 남는다(맥이 두 번 고친 결함).
        defer { if serial == leagueSerial { leagueState.isLoading = false } }
        do {
            let service = context.service
            let page = try await context.withMobileSessionRetry { session in
                try await service.fetchTeamLeaderboard(accessToken: session.accessToken, weekOffset: weekOffset)
            }
            guard generation == context.generation, serial == leagueSerial else { return }
            let sorted = page.entries.sortedByAverageDescending()
            let now = context.clock.now()

            // ── ① 옛 서버(p_week_offset 모름) ── 돌아온 행은 **이번 주**다.
            guard page.supportsWeekOffset else {
                leagueWeekOffsetSupported = false
                let current = TeamLeagueWeekNavigator.currentKey(now)
                leagueWeekAnchor = current
                leagueWeekKey = current        // syncLeagueWeekToCurrent 을 타면 안 된다 — 그쪽은 행을 비운다.
                league = sorted                // 이 행은 버릴 이유가 없는 이번 주 표다. **추가 요청도 내지 않는다**
                leagueState.hasLoaded = true   // (다시 부르면 옛 서버 사용자는 조회마다 4왕복이 된다).
                leagueState.hasFailed = false
                leagueState.loadedAt = now
                return
            }
            leagueWeekOffsetSupported = true

            // ── ② 늦은 응답: 기다리는 사이 주를 옮겼으면 화면엔 안 꽂는다 ──
            //    키를 바꾸는 자리는 전부 순번을 올리지만, 아래 '서버 주 채택'처럼 못 올리는 갈래가 실제로 있어 그물을 하나 더 둔다.
            guard weekKey == leagueWeekKey else { return }
            // ── ③ 서버가 답한 주를 따른다(조회 중 월요일 0시를 넘긴 경우의 유일한 어긋남) ──
            let answered = page.serverWeekStart ?? weekKey
            if answered != leagueWeekKey {
                leagueWeekKey = answered
                if answered == TeamLeagueWeekNavigator.currentKey(now) { leagueWeekAnchor = answered }
            }
            if league != sorted { league = sorted }
            leagueState.hasLoaded = true
            leagueState.hasFailed = false
            leagueState.loadedAt = now
        } catch {
            guard generation == context.generation, serial == leagueSerial, weekKey == leagueWeekKey else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }   // 폰 모양 유지 — 빈 카드는 hasLoaded 로 갈린다
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

    /// 오늘 한 사람 수를 **안다**(정족수 줄 "오늘은 아직 아무도 안 했어요 · 5명부터 지급"을 그려도 된다). 게임 탭
    /// `GamesMiniGameBoard.knowsPlayerCount` 와 같은 공용 규칙(`MobileLoadKnowledge`) — 실패로 0 인 값을 "아무도 안 했다"로 말하지 않는다.
    package var knowsMiniGamePlayerCount: Bool {
        MobileLoadKnowledge.knowsCount(hasRows: !miniGameBoard.isEmpty, hasLoaded: miniGameState.hasLoaded, lastFailed: miniGameState.hasFailed)
    }

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
