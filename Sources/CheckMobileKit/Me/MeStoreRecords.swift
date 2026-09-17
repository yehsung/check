import CheckCore
import CheckMobileShared
import Foundation

/// 기록(지난주 회고 · 12주 근무 잔디 · 12주 AI 토큰 잔디 · 지난주 근무 리듬) — 계산은 전부 코어(`WorkInsightsComputation` ·
/// `TokenDailyGrid`) 그대로, 폰은 **읽기 GET** 만 한다: 내 완료 세션(`work_sessions`) · 내 일별 토큰(`token_usage_device_daily`) ·
/// 토큰 설정(`profiles` — 수집 여부만 쓴다) · 팀 상태(진행 중 세션 시작 시각만 쓴다).
extension MeStore {
    package func loadRecords() async {
        guard context.session.isSignedIn, let userID = context.session.userID else { return }
        let serial = nextSerial("records")
        let generation = context.generation
        let now = context.clock.now()
        // 주가 바뀐 뒤의 옛 계산은 '지난주'가 아니다 — 조회를 시작하는 순간 버린다(맥 discardInsightsIfWeekRolledOver).
        if let key = recordsWeekKey, key != RetroWeekKey.current(now) {
            discardRecords()
        }
        recordsState.isLoading = true
        recordsState.hasFailed = false
        defer { if isCurrent("records", serial) { recordsState.isLoading = false } }

        let service = context.service
        let since = MeText.insightsWindowStart(now: now)
        // 팀(목표 시간·진행 중 세션 조회)을 아직 모르면 먼저 읽는다 — 실행 직후 멤버십보다 기록이 먼저 오면 목표가 기본값(60시간)으로
        // 굳고 진행 중 세션도 빠졌다(데모 스크린샷 실측). 읽기 GET 한 번이다.
        if context.session.profile?.teamID == nil {
            await context.session.refreshProfile()
            guard generation == context.generation, isCurrent("records", serial) else { return }
        }
        let teamID = context.session.profile?.teamID
        let goalSeconds = (context.session.profile?.teamGoalHours ?? TeamWeeklyGoal.defaultGoalHours) * 3600
        do {
            let rows = try await context.withMobileSessionRetry { session in
                try await service.fetchMySessions(accessToken: session.accessToken, userID: session.userID, since: since)
            }
            guard generation == context.generation, isCurrent("records", serial) else { return }

            // 토큰 설정(독립 실패 — 못 읽으면 지난 값, 처음이면 수집 중으로 본다).
            let settings = try? await context.withMobileSessionRetry { session in
                try await service.fetchTokenUsageSettings(accessToken: session.accessToken, userID: session.userID)
            }
            guard generation == context.generation, isCurrent("records", serial) else { return }
            if let settings {
                // focus_mode 는 읽기만 하고 버린다 — 폰은 집중 모드를 건드리지 않는다(R9).
                tokenUsagePublic = settings.isPublic
                tokenUsagePublicLoaded = true
            }
            let collects = settings?.collects ?? showsTokenGrid

            var tokenRows: [TokenUsageDailyRow]?
            if collects {
                tokenRows = try? await context.withMobileSessionRetry { session in
                    try await service.fetchMyTokenDaily(accessToken: session.accessToken, userID: session.userID, since: TokenDailyGrid.dayString(since))
                }
                guard generation == context.generation, isCurrent("records", serial) else { return }
            }

            // 진행 중인 내 세션(맥에서 근무 중)의 시작 시각. **신호가 신선할 때만** 얹는다 — 끊긴 세션(맥 뚜껑을 닫음)을 now 까지
            // 세면 부풀린다(세는 쪽보다 덜 세는 쪽이 안전하다). 팀이 없으면 진행 중 세션도 없다.
            var ongoingStart: Date?
            if let teamID {
                let statuses = try? await context.withMobileSessionRetry { session in
                    try await service.fetchTeamStatuses(accessToken: session.accessToken, teamID: teamID, now: now)
                }
                guard generation == context.generation, isCurrent("records", serial) else { return }
                if let mine = statuses?.first(where: { $0.id == userID }), mine.presence(now: now) == .activeWorking {
                    ongoingStart = mine.currentSessionStartedAt
                }
            }

            let previousTokenGrid = tokenGrid
            let input = MeRecordsInput(rows: rows, tokenRows: tokenRows, collects: collects, now: now, goalSeconds: goalSeconds,
                                       ongoingStart: ongoingStart, previousTokenGrid: previousTokenGrid)
            // 세션이 많은 계정(수천 행)에서 메인 액터를 막지 않게 계산은 밖에서(맥 performLoadInsights 와 같은 이유).
            let output = await Task.detached(priority: .userInitiated) { MeRecordsOutput(input) }.value
            guard generation == context.generation, isCurrent("records", serial) else { return }
            if heatmap != output.insights.heatmap { heatmap = output.insights.heatmap }
            if retro != output.insights.retro { retro = output.insights.retro }
            if dailyGrid != output.insights.dailyGrid { dailyGrid = output.insights.dailyGrid }
            if tokenGrid != output.tokenGrid { tokenGrid = output.tokenGrid }
            showsTokenGrid = collects
            recordsWeekKey = RetroWeekKey.current(now)
            recordsState.hasLoaded = true
            recordsState.hasFailed = false
            recordsState.loadedAt = context.clock.now()
        } catch {
            guard generation == context.generation, isCurrent("records", serial) else { return }
            if AuthErrorRules.classify(error) == .cancelled { return }
            recordsState.hasFailed = true
        }
    }

    /// 화면에 그릴 회고 — 목표선은 **지금** 팀 목표를 따른다(맥 `reconcileInsightsGoal`: 목표가 계산 뒤에 확정·변경돼도 회고가 옛 목표에 굳지 않게).
    package var retroForDisplay: WeeklyRetro? {
        guard let retro else { return nil }
        guard let hours = context.session.profile?.teamGoalHours else { return retro }
        let goalSeconds = hours * 3600
        return retro.goalSeconds == goalSeconds ? retro : retro.withGoal(goalSeconds)
    }

    /// 본문 대신 보일 자리 문구(nil 이면 본문).
    package var recordsPlaceholder: String? {
        MeText.recordsPlaceholder(
            hasLoaded: recordsState.hasLoaded,
            hasFailed: recordsState.hasFailed,
            totalSeconds: heatmap.totalSeconds + dailyGrid.totalSeconds,
            hasTokenGrass: showsTokenGrid && tokenGrid.totalTokens > 0
        )
    }

    func discardRecords() {
        recordsWeekKey = nil
        heatmap = .empty
        retro = nil
        dailyGrid = .empty
        tokenGrid = .empty
        recordsState.hasLoaded = false
        recordsState.loadedAt = nil
    }
}

/// 기록 계산 입력(메인 액터 밖으로 넘긴다 — 코어 값 타입이 Sendable 표시가 없어 상자로 감싼다. 전부 불변 값 복사다).
struct MeRecordsInput: @unchecked Sendable {
    let rows: [WorkSessionRow]
    let tokenRows: [TokenUsageDailyRow]?
    let collects: Bool
    let now: Date
    let goalSeconds: Int
    let ongoingStart: Date?
    let previousTokenGrid: TokenDailyGrid
}

struct MeRecordsOutput: @unchecked Sendable {
    let insights: WorkInsightsComputation
    let tokenGrid: TokenDailyGrid

    init(_ input: MeRecordsInput) {
        insights = WorkInsightsComputation.build(rows: input.rows, now: input.now, goalSeconds: input.goalSeconds, ongoingStart: input.ongoingStart)
        if !input.collects {
            tokenGrid = .empty
        } else if let tokenRows = input.tokenRows {
            // 폰에는 로컬 스캐너가 없다 — 서버 일별 합만(맥 TokenDailyMerge 의 local 몫은 빈 맵).
            tokenGrid = TokenDailyGrid.build(daily: TokenDailyMerge.merged(server: TokenDailyMerge.serverTotals(tokenRows), local: [:]), now: input.now)
        } else {
            // 서버 조회 실패: 직전 잔디를 물려준다(주가 바뀌었으면 loadRecords 가 이미 비웠다).
            tokenGrid = TokenDailyGrid.build(daily: [:], now: input.now).overlaying(input.previousTokenGrid)
        }
    }
}
