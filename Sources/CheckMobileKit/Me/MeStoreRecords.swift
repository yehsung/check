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
            // 공개 여부는 설정 화면 스위치와 같은 칸이다 — 이 GET 이 떠 있는 사이 사용자가 스위치를 바꿨으면(저장 중이든 끝났든) 옮기지
            // 않는다. 루트가 뜨자마자 이 조회가 시작되고 곧바로 설정에서 스위치를 바꾸는 흔한 순서에서 방금 끈 스위치를 켰다(rankme-verify R1).
            let privacyStamp = privacyReadStamp("token")
            let settings = try? await context.withMobileSessionRetry { session in
                try await service.fetchTokenUsageSettings(accessToken: session.accessToken, userID: session.userID)
            }
            guard generation == context.generation, isCurrent("records", serial) else { return }
            if let settings, canApplyPrivacyRead("token", stamp: privacyStamp) {
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

            // 공유 Codex 계정 비율(v0.3.36). 폰 잔디의 Codex 칸은 서버 **계정 버킷**에서 나오는데 그 버킷은
            // **그룹 전체의 하루 사용량**이라, 비율을 안 곱하면 공유 계정 사용자에게 '계정의 잔디'가 그려진다.
            // 저장본 복구를 먼저 한다 — 첫 프레임에 부푼 잔디가 떴다가 내려앉지 않게(맥 myTokenRow 영속과 같은 이유).
            if tokenShareRatio == nil { tokenShareRatio = storedTokenShareRatio() }
            await refreshTokenShareRatio(tokenRows: tokenRows, collects: collects, now: now, generation: generation)
            guard generation == context.generation, isCurrent("records", serial) else { return }

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
            // 비율은 **메인 액터에서 값으로 캡처**해 넘긴다 — detached 안에서 스토어를 읽지 않는다(맥과 같은 계약).
            let input = MeRecordsInput(rows: rows, tokenRows: tokenRows, collects: collects, now: now, goalSeconds: goalSeconds,
                                       ongoingStart: ongoingStart, previousTokenGrid: previousTokenGrid,
                                       accountShareRatio: tokenShareRatio ?? 1.0)
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

    /// 보드에서 공유 Codex 계정 비율을 한 번 읽어 `tokenShareRatio` 를 갱신한다(v0.3.36).
    ///
    /// **아무것도 비우지 않는다**: 어떤 갈래에서도 `tokenGrid` 를 비우거나 `recordsState.hasFailed` 를 세우지 않는다.
    /// 잔디는 두 격자(근무·토큰)가 phase 하나와 [다시 시도] 하나를 공유해서, 여기서 실패를 세우면 근무 잔디까지
    /// 사라지고 '수집을 끈 사람'과 구분되지 않는다.
    ///
    /// 게이트(하나라도 걸리면 **왕복 0건**):
    ///  1. 수집 꺼짐 → 잔디가 `.empty` 라 비율이 쓰일 자리가 없다. (맥은 수집 거부자에게도 이 RPC 를 막지 않는데,
    ///     그건 맥 팝오버가 이 보드의 **소비자**라서다 — 폰은 잔디 말고 이 값을 쓰는 곳이 없다. 이유가 다르다.)
    ///  2. 일별 조회 실패 → 그 경로의 잔디는 `previousTokenGrid` overlay 라 새 비율이 들어갈 자리가 없다.
    ///  3. **이번 달** 계정 버킷 합이 0 → 분모가 0 이면 비율이 어차피 1.0 이다. Codex 계정이 없는 사람은 이 무거운
    ///     보드 RPC 를 **한 번도 안 쏜다**.
    ///  4. **월초 유예**(KST 1~3일) → 새 달의 지분비는 서버에서 0 부터 다시 쌓여 첫 며칠은 표본이 아니라 잡음이다
    ///     (`TokenRowDisplayRule.shareRatioMonthIsYoung`). 그 잡음을 채택하면 13주 창이 통째로 0 이나 '계정 전체'로
    ///     뒤집힌다 — 안 재고 직전에 잰 값을 그대로 쓴다.
    ///  5. 300초 스로틀 → 캐시 값을 그대로 쓴다(맥 `loadMyTokenRowIfDue` 와 같은 간격).
    ///  6. 이미 떠 있는 왕복(`isFetchingTokenBoard`) → 겹친 [당겨서 새로고침]이 같은 RPC 를 두 번 쏘지 않게.
    ///
    /// 비율은 **이 로드의 산출물이 아니라 계정 단위 캐시**다. 그래서 응답을 받는 자리에 `isCurrent(_:_:)` 순번 가드를
    /// **두지 않는다**: 겹친 로드에서 늦게 온 응답을 순번으로 버리면 그 값은 어디에도 안 남는데 도장만 남아, 공유
    /// 사용자의 잔디가 300초 넘게 '계정 전체'(최대 19.15배)로 굳는다(v0.3.36 리뷰 1 — 새 설치 첫 로드가 정확히 이 모양).
    /// 세대(로그아웃·계정 교체) · 달 재확인 · userID 일치는 그대로 지킨다 — 그 셋이 '남의/다른 달 값' 을 막는 가드다.
    func refreshTokenShareRatio(
        tokenRows: [TokenUsageDailyRow]?, collects: Bool, now: Date, generation: Int
    ) async {
        guard collects, let tokenRows else { return }
        // 달은 이 호출의 시계로 뽑는다 — 분자(보드 p_month)와 분모(버킷 접두어)가 같은 순간의 같은 키여야 한다.
        let month = TokenUsageMonthKey.current(now)
        let bucketSum = TokenDailyMerge.accountBucketSum(tokenRows, month: month)
        guard bucketSum > 0 else { return }
        // 월초 유예. 새 달의 지분비는 **0 부터 다시 쌓이므로**(서버 `share_ratio` 의 분자·분모가 그 달치 로컬뿐이다)
        // 첫 며칠 값은 잡음이다 — 그 달 Codex 를 아직 안 쓴 멤버는 0(13주 잔디 전체가 내려앉고 그 0 이 영속된다),
        // 맨 먼저 쓴 멤버는 ≈1(잔디가 계정 전체로 되부푼다). 이 구간에는 **왕복 자체를 안 쏘고** 직전에 잰 비율을
        // 그대로 쓴다(근거·일수는 `TokenRowDisplayRule.shareRatioMonthIsYoung`). 캐시가 없으면 1.0 = 종전 동작.
        guard !TokenRowDisplayRule.shareRatioMonthIsYoung(now) else { return }
        if let last = lastTokenBoardFetchAt, now.timeIntervalSince(last) < 300 { return }
        guard !isFetchingTokenBoard else { return }
        isFetchingTokenBoard = true
        defer { isFetchingTokenBoard = false }
        let service = context.service
        let result = await attempt { session in
            try await service.fetchTokenBoard(accessToken: session.accessToken, month: month)
        }
        guard generation == context.generation else { return }
        let rows: [TokenBoardRow]
        switch result {
        case .success(let value):
            rows = value
        case .failure(let error):
            // 취소는 실패가 아니다 — [당겨서 새로고침] 중에 탭을 떠나는 흔한 동작이 300초 동안 잠기지 않게 **도장을 안 찍는다**.
            // (`try?` 로 접으면 이 둘을 영원히 못 가른다 — `attempt` 가 `Result` 를 주는 이유.)
            if AuthErrorRules.classify(error) == .cancelled { return }
            // 네트워크·5xx: 조용히 캐시를 지킨다(맥 catch 규약 — "실패는 조용히, 들고 있던 값을 비우지 않는다").
            // 끝난 시도이므로 도장을 찍는다 → 300초 뒤 재시도.
            lastTokenBoardFetchAt = context.clock.now()
            return
        }
        // 응답이 오는 사이 월말 자정을 넘겼으면 다른 달의 비율이다. 세대 가드가 못 잡는 경로다(맥과 같은 재확인).
        // 쓸 수 없는 왕복이라 **도장도 안 찍는다** — 새 달의 비율을 곧바로 다시 읽는다.
        guard month == TokenUsageMonthKey.current(context.clock.now()) else { return }
        lastTokenBoardFetchAt = context.clock.now()
        guard let userID = context.session.userID,
              let mine = rows.toTokenBoardEntries().first(where: { $0.userID == userID })
        else { return }   // 내 행 없음 → 캐시 유지(월·일별은 같은 업로드 주기라 드문 어긋남이다).
        // ★ 이 가드를 통과해야만 `codexAccountShare` 를 쓴다. 옛 RPC(codex_effective 없음)면 엔트리의 값이
        //   폐기된 `max(로컬, 계정)` 증폭기라, 그걸로 비율을 만들면 잔디를 되부풀린다 → 캐시 유지.
        guard let server = TokenRowServerValue(entry: mine, month: month, fetchedAt: now) else { return }
        // share == nil(미로그인 기기·옛 표가 이긴 행)이면 캐시 유지 — 1.0 으로 덮으면 잔디만 계정 전체로 부푼다.
        // share == 0 은 nil 과 **다르다**(진짜 몫 0) → 비율 0 으로 간다.
        guard let share = server.codexAccountShare else { return }
        // 몫이 분모를 넘었다 = '내 몫이 100%' 가 아니라 **분자와 분모가 다른 스냅샷**이라는 뜻이다: 분자는 그룹에서
        // 가장 최신인 남의 스냅샷에서 나오고(`group_account_month = max(m.account_month)`) 분모는 **내 기기만**
        // 관측한 버킷 합이다(2026-09-22 실측 '수 빈' 1.74). 이때 클램프가 돌려주는 1.0 을 '비공유'로 읽고 채택하면
        // 정확하던 캐시(예: 0.25)를 덮어 잔디가 최대 19.15배로 되부푼다 — 클램프의 '안전 착지'는 **캐시가 없는 첫
        // 로드**에서만 안전하다. 캐시가 있으면 `.keep` 이 규약이다(맥 `MyTokenRowOutcome.keep` · MeStore 주석).
        guard share <= bucketSum || tokenShareRatio == nil else { return }
        let ratio = TokenRowDisplayRule.accountShareRatio(share: share, bucketSum: bucketSum)
        tokenShareRatio = ratio
        persistTokenShareRatio(ratio)
    }

    /// 계정별 키(같은 폰에서 계정을 바꿔도 앞 사람의 비율을 물려받지 않게 — `feedbackReplySeenKey` 와 같은 관용구).
    var tokenShareRatioKey: String? {
        context.session.userID.map { "aing.me.codexShareRatio.\($0)" }
    }

    func storedTokenShareRatio() -> Double? {
        guard let key = tokenShareRatioKey else { return nil }
        return context.storage.defaults.object(forKey: key) as? Double
    }

    func persistTokenShareRatio(_ ratio: Double) {
        guard let key = tokenShareRatioKey else { return }
        context.storage.defaults.set(ratio, forKey: key)
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
    /// 서버 **계정 버킷**에만 곱하는 공유 Codex 계정 비율(v0.3.36). 1.0 이면 항등 = 이 수리 전과 한 칸도 다르지 않다.
    let accountShareRatio: Double
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
            // 공유 Codex 계정 비율은 **계정 버킷에만** 곱한다(맥 WorkTimerStoreInsights 와 같은 자리·같은 규칙).
            tokenGrid = TokenDailyGrid.build(daily: TokenDailyMerge.merged(server: TokenDailyMerge.serverTotals(tokenRows, accountShareRatio: input.accountShareRatio), local: [:]), now: input.now)
        } else {
            // 서버 조회 실패: 직전 잔디를 물려준다(주가 바뀌었으면 loadRecords 가 이미 비웠다).
            tokenGrid = TokenDailyGrid.build(daily: [:], now: input.now).overlaying(input.previousTokenGrid)
        }
    }
}
